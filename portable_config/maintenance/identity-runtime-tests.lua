-- Exercise the real lookup scripts without a Desktop bridge or network access.
return function(path)
    local real,getenv,old_path=mp,os.getenv,package.path
    local saved={}
    local modules={'mp.options','mp.msg','mp.input','encoding','database','mpv-build/user_settings','mpv-build/ui_locale'}
    for _,name in ipairs(modules) do saved[name]=package.loaded[name] end
    local utils=require 'mp.utils'
    local media='http://localhost/stream?link=abcdef&index=3&play'
    local props={path=media,duration=1440,['playlist-pos']=0,['time-pos']=0,['idle-active']=false,
        playlist={{filename=media,title='Kimetsu no Yaiba - 03 1920x1080.mkv'}}}
    local requests,events,observers={},{},{}
    local function noop() end
    local function get(k,d) if props[k]==nil then return d end;return props[k] end
    local function set(k,v) props[k]=v end
    local function timer(_,fn) return {kill=noop,fn=fn} end
    local mock={get_property=get,get_property_native=get,get_property_number=get,get_property_bool=get,
        set_property=set,set_property_native=set,commandv=noop,osd_message=noop,
        command_native=function(a)
            if a[1]=='expand-path' then return path(a[2]:gsub('^~~/','')) end
            assert(a.name=='subprocess','Unexpected native call')
            requests[#requests+1]={url=a.args[#a.args]}
            return {status=0,stdout='{"results":[]}'}
        end,
        command_native_async=function(a,callback)
            requests[#requests+1]={url=a.args[#a.args],callback=callback};return #requests
        end,
        observe_property=function(k,_,fn) observers[k]=fn end,
        register_event=function(k,fn) events[k]=fn end,
        register_script_message=noop,add_key_binding=noop,remove_key_binding=noop,add_hook=noop,
        add_timeout=timer,add_periodic_timer=timer,get_time=function() return 0 end,
        get_opt=function(k) if k=='theintrodb-debug' then return 'yes' end end,
        get_script_name=function() return 'autochapters' end,
        get_script_directory=function() return path('scripts/autochapters') end,
        msg={log=noop,warn=noop,info=noop},get_osd_size=function() return 1280,720 end}
    local cases={
        {folder='[VLD] Kimetsu no Yaiba TV-4 [WEBRip 1080p]',season=5,mal=55701},
        {folder='Demon Slayer - Kimetsu no Yaiba Entertainment District Arc',season=3,mal=47778},
        {folder='Kimetsu no Yaiba - Hashira Geiko Hen [TV-4] [2024] [WEBRip] [1080p] [RUS + JAP]',season=5,mal=55701},
    }
    local ok,err=xpcall(function()
        mp=mock
        os.getenv=function(k) if k~='MPV_PLUS_LAMPA_CONTEXT' then return getenv(k) end end
        package.loaded['mp.options']={read_options=noop}
        package.loaded['mp.msg']=mock.msg
        package.loaded['mp.input']={}
        package.loaded['mpv-build/user_settings']={options=noop,path=function() return path('maintenance/nonexistent-test-state') end}
        package.loaded['mpv-build/ui_locale']={install_messages=noop,text=function(t)return t end,language=function()return 'ru' end}
        dofile(path('scripts/theintrodb.lua'))
        local state=__tidb_debug()
        local pending
        for _,case in ipairs(cases) do
            props['user-data/torrserver-context']={media=media,path=case.folder..'/03.1920x1080.mkv'}
            requests={};events['file-loaded']()
            assert(state.season==tostring(case.season) and state.episode=='3','Wrong TheIntroDB coordinates')
            local request
            for _,r in ipairs(requests) do
                if r.url:find('api.theintrodb.org/',1,true) then request=r end
            end
            assert(request and request.url:find('tmdb_id=85937&season='..case.season..'&episode=3',1,true))
            assert(request.url:find('duration_ms=1440000',1,true),'Send actual file duration')
            if pending then
                pending.callback(true,{status=0,stdout='{"intro":[{"start_ms":1000,"end_ms":90000}]}\n200'})
                assert(state.media==nil,'Discard an answer for the previous arc on the same URL')
            end
            pending=request
        end
        pending.callback(true,{status=0,stdout='{}\n200'})
        assert(state.loaded)
        -- Correcting the arc on the same URL must not reuse another season's cache.
        props['user-data/torrserver-context']={media=media,path=cases[2].folder..'/03.mkv'}
        requests={};observers['user-data/torrserver-context']()
        assert(not state.loaded and #requests>0,'Cache must include resolved identity')
        props.duration=0
        props['user-data/torrserver-context']={media=media,path=cases[2].folder..'/08.mkv'}
        events['file-loaded']()
        assert(not state.duration_ms,'Do not invent the duration before demuxer readiness')
        requests={};props.duration=1440;observers.duration('duration',1440)
        local duration_request
        for _,r in ipairs(requests)do if r.url:find('api.theintrodb.org/',1,true) then duration_request=r end end
        assert(duration_request and duration_request.url:find('duration_ms=1440000',1,true),'Late duration refreshes skip matching for the first opened file')
        package.path=path('scripts/autochapters/?.lua')..';'..package.path
        package.loaded.encoding=nil;package.loaded.database={new=function() return {request=noop} end}
        requests={};dofile(path('scripts/autochapters/main.lua'))
        local prior
        for _,case in ipairs(cases) do
            props['user-data/torrserver-context']={media=media,path=case.folder..'/03.1920x1080.mkv'}
            requests={};events['file-loaded']()
            assert(#requests>0,'AniSkip request missing')
            if prior then
                local count=#requests
                prior.callback(true,{status=0,stdout=utils.format_json({results={{episodeLength=1440,skipType='op',interval={startTime=30,endTime=120}}}})})
                assert(#requests==count and not next(props['user-data/autochapters']),'Late async AniSkip response must not publish or start fallback queries for a different arc')
            end
            for _,request in ipairs(requests) do
                assert(request.url:find('api.aniskip.com/v2/skip-times/'..case.mal..'/3?',1,true),
                    'Wrong AniSkip identity: '..tostring(request.url))
            end
            prior=requests[1]
        end
        prior.callback(true,{status=0,stdout=utils.format_json({results={{episodeLength=1440,skipType='op',interval={startTime=30,endTime=120}}}})})
        assert(props['user-data/autochapters'].op.start==30 and props['user-data/autochapters'].op['end']==120,'Current async AniSkip response publishes validated times')
    end,debug.traceback)
    mp,os.getenv,package.path=real,getenv,old_path;__tidb_debug=nil
    for _,name in ipairs(modules) do package.loaded[name]=saved[name] end
    assert(ok,err)
end
