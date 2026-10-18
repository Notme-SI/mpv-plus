-- Reproduce an external TorrServer stream with no configured server and no bridge.
return function(path)
    local real,getenv,old_path,old_file_load=mp,os.getenv,package.path,file_load
    local utils=require 'mp.utils'
    local subprocess=utils.subprocess
    local saved={}
    local modules={'mp.options','mp.msg','mp.input','encoding','database','mpv-build/user_settings','mpv-build/ui_locale'}
    for _,name in ipairs(modules) do saved[name]=package.loaded[name] end
    local hash=string.rep('a',40)
    local media='https://remote.example/torrserver/stream?link='..hash..'&index=12&play&token=fixture'
    local raw='Kimetsu no Yaiba - 05 [1920x1080].mkv'
    local props={path=media,['media-title']=raw,['playlist-pos']=4,playlist={{},{},{},{},{filename=media,title=raw}},
        duration=1440,['time-pos']=0,['idle-active']=false,['user-data/interface-language']='ru'}
    local events,observers,requests,timers={},{},{},{}
    local function noop() end
    local function get(k,d)if props[k]==nil then return d end;return props[k]end
    local function set(k,v)
        props[k]=v
        for _,fn in ipairs(observers[k] or {}) do fn(k,v) end
    end
    local function timer(_,fn)
        local t={active=true,fn=fn,kill=function(self)self.active=false end}
        timers[#timers+1]=t;return t
    end
    local function emit(name)for _,fn in ipairs(events[name] or {})do fn()end end
    local function tick()
        local pending=timers;timers={}
        for _,t in ipairs(pending)do if t.active then t.fn()end end
    end
    local mock={get_property=get,get_property_native=get,get_property_number=get,get_property_bool=get,
        set_property=set,set_property_native=set,set_property_number=set,
        commandv=noop,osd_message=noop,abort_async_command=noop,
        command_native=function(a)
            if a[1]=='expand-path' then return path(a[2]:gsub('^~~/','')) end
            assert(a.name=='subprocess' and a.args[1]=='curl','Do not run GuessIt while the arc is unresolved')
            requests[#requests+1]={url=a.args[#a.args]}
            return {status=0,stdout='{"results":[]}'}
        end,
        command_native_async=function(a,callback)
            requests[#requests+1]={url=a.args[#a.args],callback=callback};return #requests
        end,
        observe_property=function(k,_,fn)observers[k]=observers[k] or {};table.insert(observers[k],fn)end,
        register_event=function(k,fn)events[k]=events[k] or {};table.insert(events[k],fn)end,
        register_script_message=noop,add_hook=noop,add_key_binding=noop,remove_key_binding=noop,
        add_timeout=timer,add_periodic_timer=function()return {kill=noop}end,
        get_time=function()return 0 end,get_osd_size=function()return 1280,720 end,
        get_opt=function(k)if k=='theintrodb-debug'then return 'yes'end end,
        get_script_name=function()return 'autochapters'end,get_script_directory=function()return path('scripts/autochapters')end,
        msg={log=noop,warn=noop,info=noop}}
    local ok,err=xpcall(function()
        mp=mock
        os.getenv=function(k)if k~='MPV_PLUS_LAMPA_CONTEXT'then return getenv(k)end end
        package.loaded['mp.options']={read_options=noop};package.loaded['mp.msg']=mock.msg;package.loaded['mp.input']={}
        package.loaded['mpv-build/user_settings']={options=noop,path=function()return path('maintenance/nonexistent-test-state')end}
        package.loaded['mpv-build/ui_locale']={install_messages=noop,text=function(t)return t end,language=function()return 'ru'end}
        local source=dofile(path('extensions/media_source.lua'))
        local stream=assert(source.stream(media))
        assert(stream.origin=='https://remote.example/torrserver' and stream.index==12)
        assert(stream.url=='https://remote.example/torrserver/stream?link='..hash..'&token=fixture&stat')
        local encoded=source.stream('edl://!new_stream;%200%'..media..';!new_stream;https://audio.example/track;')
        assert(encoded and encoded.key==stream.key,'Use the main EDL video stream')
        assert(not source.stream('https://remote.example/film?link='..hash..'&index=12'))
        local local_stream=source.stream('http://127.0.0.1:8090/stream?link='..hash..'&index=5')
        assert(local_stream.origin=='http://localhost:8090')
        local other=source.stream('http://127.0.0.1.example/stream?link='..hash..'&index=5')
        assert(other.origin=='http://127.0.0.1.example','Do not normalize a different hostname to localhost')
        source.install()
        local anime=dofile(path('extensions/anime_identity.lua'))
        local awaiting=anime.from_source('Kimetsu no Yaiba S01E05.mkv',source.current())
        assert(awaiting.unresolved_context and not awaiting.mal_id,'Wait for torrent context before trusting a generic S01 filename')
        package.path=path('scripts/autochapters/?.lua')..';'..package.path
        package.loaded.encoding=nil;package.loaded.database={new=function()return {request=noop}end}
        dofile(path('scripts/readable_titles.lua'))
        dofile(path('scripts/theintrodb.lua'))
        dofile(path('scripts/autochapters/main.lua'))
        emit('file-loaded');tick();tick()
        assert(#requests==1 and requests[1].url==stream.url,'Fetch metadata from the playing server, not localhost')
        assert(source.current().pending)
        assert(not props['user-data/readable-title'].text:find('Сезон 1',1,true),'Do not publish an invented first season')
        local state=__tidb_debug()
        assert(not state.loaded and not state.season,'Do not fetch season-one skip ranges while metadata is pending')
        requests[1].callback(true,{status=0,stdout=utils.format_json({hash=hash,name='Kimetsu no Yaiba - Hashira Geiko Hen [TV-4]',
            -- Corrupt history values must never become playback coordinates.
            season=20,episode=10,file_stats={{id=12,path='Kimetsu no Yaiba - Hashira Geiko Hen [TV-4]/'..raw}}})})
        tick()
        assert(source.current().path:find('[TV-4]',1,true))
        local season_request,aniskip,theintrodb
        local n=1
        while n<=#requests do
            local request=requests[n]
            if request.url:find('/tv/85937?language=ru',1,true) then
                request.callback(true,{status=0,stdout='{"name":"Истребитель демонов"}'})
            elseif request.url:find('/season/',1,true)then
                assert(request.url:find('/season/5?',1,true),'Wrong episode names season')
                season_request=request
            elseif request.url:find('api.aniskip.com/',1,true)then
                assert(request.url:find('/55701/5?',1,true),'Wrong AniSkip arc/episode');aniskip=true
            elseif request.url:find('api.theintrodb.org/',1,true)then
                assert(request.url:find('tmdb_id=85937&season=5&episode=5',1,true),'Wrong TheIntroDB coordinates');theintrodb=true
            end
            n=n+1
        end
        assert(season_request and aniskip and theintrodb,'All consumers must use the resolved arc')
        season_request.callback(true,{status=0,stdout='{"episodes":[{"episode_number":5,"name":"Я ел даже демонов"}]}'})
        assert(props['user-data/readable-title'].text=='Истребитель демонов · Сезон 5, серия 5: Я ел даже демонов')
        -- Same hash on another server cannot reuse this server's folder metadata.
        props.path=media:gsub('remote.example','another.example');set('path',props.path)
        emit('file-loaded');tick()
        local pending=requests[#requests]
        assert(pending.url:find('another.example',1,true))
        pending.callback(false,{status=28,stdout=''})
        tick()
        assert(source.current().unavailable and not state.season,'A failed lookup must not silently become season one')
        assert(not props['user-data/readable-title'].text:find('Сезон 1',1,true))
        props.playlist[5].title='Kimetsu no Yaiba S01E08.mkv';props['media-title']=props.playlist[5].title
        emit('file-loaded');tick();tick()
        assert(not props['user-data/readable-title'].text:find('Сезон 1',1,true),'A timeout must not restore the S01 fallback from a generic filename')
        assert(not state.season and not state.loaded,'A timeout must not enable season-one auto-skips')
    end,debug.traceback)
    mp,os.getenv,package.path,file_load=real,getenv,old_path,old_file_load
    utils.subprocess=subprocess;__tidb_debug=nil
    for _,name in ipairs(modules)do package.loaded[name]=saved[name]end
    assert(ok,err)
end
