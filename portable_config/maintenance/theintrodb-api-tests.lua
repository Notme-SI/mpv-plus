-- Exercise the patched script through its real file-loaded and HTTP callbacks.
return function(path)
    local real,clock,getenv=mp,os.time,os.getenv
    local utils=require 'mp.utils'
    local saved={}
    local modules={'mp.options','mpv-build/user_settings','mpv-build/ui_locale'}
    for _,name in ipairs(modules) do saved[name]=package.loaded[name] end
    local props={duration=1440,['time-pos']=0}
    local events,requests,timers={},{},{}
    local epoch=100000
    local function noop() end
    local function get(k,d) if props[k]==nil then return d end;return props[k] end
    local mock={get_property=get,get_property_native=get,get_property_number=get,get_property_bool=get,
        set_property=noop,set_property_native=noop,commandv=noop,osd_message=noop,
        command_native=function(a) return path(a[2]:gsub('^~~/','')) end,
        command_native_async=function(a,cb)
            if a.args[#a.args]:find('api.theintrodb.org/',1,true) then
                requests[#requests+1]={url=a.args[#a.args],callback=cb}
            end
            return #requests
        end,
        register_event=function(k,fn) events[k]=fn end,
        register_script_message=noop,observe_property=noop,add_key_binding=noop,remove_key_binding=noop,
        add_timeout=function(delay,fn)
            local t={delay=delay,fn=fn,kill=noop};timers[#timers+1]=t;return t
        end,
        add_periodic_timer=function()return {kill=noop}end,
        get_time=function()return 0 end,get_osd_size=function()return 1280,720 end,
        get_opt=function(k)if k=='theintrodb-debug'then return 'yes'end end,
        msg={log=noop,warn=noop,info=noop}}
    local function load(name)
        props.path='/fixtures/'..name;props.filename=name
        events['file-loaded']()
    end
    local function respond(code,body,index)
        requests[index or #requests].callback(true,{status=0,stdout=body..'\n'..code})
    end
    local ok,err=xpcall(function()
        mp=mock;os.time=function()return epoch end
        os.getenv=function(k)if k~='MPV_PLUS_LAMPA_CONTEXT'then return getenv(k)end end
        package.loaded['mp.options']={read_options=function(o)o.show_osd='no';o.auto_detect='no'end}
        package.loaded['mpv-build/user_settings']={options=noop,path=function()return path('maintenance/nonexistent-api-state')end}
        package.loaded['mpv-build/ui_locale']={install_messages=noop,text=function(t)return t end,language=function()return 'ru'end}
        dofile(path('scripts/theintrodb.lua'))
        local state=__tidb_debug()
        load('Example.S01E02.tmdb-615.mkv')
        assert(#requests==1 and requests[1].url:find('https://api.theintrodb.org/v4/media?',1,true)==1)
        assert(requests[1].url:find('tmdb_id=615&season=1&episode=2&duration_ms=1440000',1,true))
        respond(200,'{"tvdb_id":73871,"intro":[{"start_ms":0,"end_ms":14600}],"credits":[{"start_ms":1300000,"end_ms":null}]}')
        assert(state.loaded and #state.segments==2,'v4 responses use the existing segment arrays')
        assert(state.segments[1].kind=='intro' and state.segments[1]['end']==14.6)
        load('Example.S01E03.tmdb-615.mkv')
        respond(429,'{"code":"rate_limit_exceeded","retry_after_seconds":7}')
        assert(state.retry_timer.delay==7,'Respect the server retry delay')
        local count=#requests;state.retry_timer.fn();assert(#requests==count+1)
        respond(429,'{"code":"usage_limit_exceeded","retry_after_seconds":3600}')
        assert(state.limited_until==epoch+3600 and state.retry_timer==nil,'Daily exhaustion stops retries')
        count=#requests;load('Other.S01E01.tmdb-616.mkv')
        assert(#requests==count,'A daily hold spans titles')
        epoch=epoch+3601;load('Other.S01E02.tmdb-616.mkv')
        assert(#requests==count+1,'Requests resume after the daily hold expires')
        respond(429,'{"code":"specific_media_usage_limit_exceeded","retry_after_seconds":600}')
        count=#requests;load('Renamed.S01E02.tmdb-616.mkv')
        assert(#requests==count,'A title hold survives filename changes')
        load('Other.S01E03.tmdb-616.mkv')
        assert(#requests==count+1,'A title hold permits other episodes')
        respond(429,'not JSON')
        assert(state.retry_timer.delay==5,'A proxy error retains exponential backoff')
        count=#requests;load('Next.S01E01.tmdb-617.mkv')
        respond(429,'{"code":"usage_limit_exceeded","retry_after_seconds":86400}',count)
        assert(state.limited_until<epoch,'A stale response cannot impose a daily hold')
    end,debug.traceback)
    mp=real;os.time=clock;os.getenv=getenv;__tidb_debug=nil
    for _,name in ipairs(modules) do package.loaded[name]=saved[name] end
    assert(ok,err)
end
