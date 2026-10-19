return function(path)
    local real,open=mp,io.open
    local saved={};for _,key in ipairs({'mp.options','mpv-build/ui_locale','mpv-build/user_settings'})do saved[key]=package.loaded[key]end
    local utils=require 'mp.utils'
    local hash=string.rep('a',40)
    local props={path='edl://!new_stream;http://user:pass@other.invalid:8090/prefix/stream?link='..hash..'&index=3&play&token=fixture',pause=false,['time-pos']=30,duration=1400,['demuxer-cache-duration']=.2,['cache-speed']=1048576}
    local events,observers,hooks,messages,bindings,timers,requests,commands={},{},{},{},{},{},{},{}
    local overlay={remove=function(self)self.visible=false end,update=function(self)self.visible=true end}
    local function noop()end
    local function get(k,d)if props[k]==nil then return d end;return props[k]end
    local function set(k,v)props[k]=v end
    local function emit(k,event)for _,fn in ipairs(events[k]or{})do fn(event or {})end end
    local function timer(delay,fn)local t={delay=delay,fn=fn,active=true,kill=function(self)self.active=false end};timers[#timers+1]=t;return t end
    local mock={get_property=get,get_property_native=get,get_property_number=get,get_property_bool=get,set_property=set,set_property_native=set,set_property_number=set,set_property_bool=set,
        observe_property=function(k,_,fn)observers[k]=fn end,add_hook=function(k,_,fn)hooks[k]=fn end,
        register_event=function(k,fn)events[k]=events[k]or{};table.insert(events[k],fn)end,
        register_script_message=function(k,fn)messages[k]=fn end,add_key_binding=function(_,k,fn)bindings[k]=fn end,
        add_forced_key_binding=noop,remove_key_binding=noop,osd_message=noop,
        create_osd_overlay=function()return overlay end,get_osd_size=function()return 1280,720 end,
        command_native=function()return path('')end,commandv=function(...)commands[#commands+1]={...}end,
        command_native_async=function(args,fn)requests[#requests+1]={args=args.args,fn=fn};return #requests end,
        abort_async_command=function(id)requests[id].aborted=true end,add_timeout=timer,add_periodic_timer=timer}
    mock.get_time=function()return 0 end
    local ok,err=xpcall(function()
        mp=mock;package.loaded['mp.options']={read_options=noop}
        package.loaded['mpv-build/user_settings']={options=noop,path=function(name)return 'memory:'..name end}
        package.loaded['mpv-build/ui_locale']={install_messages=noop,text=function(v)return v end,language=function()return 'ru'end}
        io.open=function(name,mode)if name:sub(1,7)=='memory:'then return {write=function()return true end,close=function()return true end}end;return open(name,mode)end
        dofile(path('scripts/network_playback.lua'));emit('start-file',{playlist_entry_id=1})
        assert(overlay.visible and props['user-data/network-buffering'].reason=='opening','Opening always shows the full network panel')
        assert(overlay.data:find('Буфер плеера вперёд',1,true) and overlay.data:find('Кеш TorrServer',1,true),'Full statistics are present before playback starts')
        hooks.on_load();emit('file-loaded')
        assert(props['file-local-options/demuxer-max-bytes']==128*1048576 and props['file-local-options/demuxer-max-back-bytes']==128*1048576,'Auto distinguishes TorrServer and retains back buffer')
        assert(#requests==1 and requests[1].aborted and not overlay.visible,'Opening poll stops during ordinary playback')
        messages.buffer('large');assert(props['file-local-options/demuxer-max-bytes']==512*1048576 and props['file-local-options/demuxer-max-back-bytes']==256*1048576,'Apply buffer immediately')
        for _,command in ipairs(commands)do assert(command[1]~='seek' and command[1]~='loadfile' and command[1]~='playlist-play-index','Changing buffer must not reload or seek')end
        props['paused-for-cache']=true;observers['paused-for-cache']()
        assert(overlay.visible and #requests==2,'Buffering must show stats without opening the menu')
        local request=requests[2];assert(request.args[#request.args]=='http://user:pass@other.invalid:8090/prefix/cache?token=fixture','Use active stream origin, prefix and authentication')
        local body=utils.parse_json(request.args[#request.args-1]);assert(body.action=='get'and body.hash==hash)
        observers['paused-for-cache']();assert(#requests==2,'Single-flight statistics')
        request.fn(true,{status=0,stdout=utils.format_json({Capacity=100*1048576,Filled=50*1048576,Torrent={download_speed=2*1048576,active_peers=7,connected_seeders=3}})})
        assert(overlay.data:find('2.0 МБ/с',1,true) and overlay.data:find('50.0 / 100.0 МБ',1,true),'Show actual server stats separately from player read speed')
        props['paused-for-cache']=false;observers['paused-for-cache']();assert(not overlay.visible)
        for i=1,4 do
            props.seeking=true;observers.seeking()
            assert(overlay.visible and props['user-data/network-buffering'].reason=='seeking','Every seek shows statistics')
            props.seeking=false;observers.seeking();assert(not overlay.visible)
            props['core-idle']=true;observers['core-idle']()
            assert(overlay.visible,'Core idle must show statistics even when paused-for-cache is false')
            props.pause=true;observers.pause();assert(not overlay.visible,'Intentional pause is not network loading')
            props['cache-buffering-state']=0;observers['cache-buffering-state']()
            assert(overlay.visible,'Actual cache fill still shows statistics when the user is paused')
            props['cache-buffering-state']=100;observers['cache-buffering-state']();assert(not overlay.visible)
            props['cache-buffering-state']=nil
            props.pause=false;props['core-idle']=false;observers['core-idle']()
            assert(not overlay.visible,'All repeated loading episodes clear on recovery')
        end
        local count=#requests;for _,t in ipairs(timers)do if t.active then t.fn()end end;assert(#requests==count,'Polling stops after buffering')
        props['paused-for-cache']=true;observers['paused-for-cache']();local late=requests[#requests]
        emit('end-file',{playlist_entry_id=1,reason='stop'});assert(late.aborted and not overlay.visible)
        late.fn(true,{status=0,stdout='{"download_speed":999}'});assert(not overlay.visible,'Late stats must not leak into next file')
        props.path='https://media.invalid/file.mkv';props['paused-for-cache']=false;emit('start-file',{playlist_entry_id=2});hooks.on_load();emit('file-loaded');messages.buffer('auto')
        assert(props['file-local-options/demuxer-max-bytes']==256*1048576,'Auto adapts ordinary HTTP too')
        count=#requests;props['paused-for-cache']=true;observers['paused-for-cache']();assert(overlay.visible and #requests==count,'Direct HTTP needs player stats without TorrServer calls')
        props['paused-for-cache']=false
        props['user-data/torrserver-loading']={media=props.path,time=0,state='caching',file='episode.mkv',speed='97.46 Mbps',cache='0.10 / 0.10 GB',peers='16 / 41 · 14',extra=''}
        observers['user-data/torrserver-loading']()
        assert(overlay.visible and overlay.data:find('97.46 Mbps',1,true) and overlay.data:find('0.10 / 0.10 ГБ',1,true)
            and overlay.data:find('16 / 41 · 14',1,true) and overlay.data:find('episode.mkv',1,true),'Retain the complete original loader data even before a standard stream endpoint is known')
        assert(#requests==count,'Opaque URLs must not query an unrelated configured server')
        props['user-data/torrserver-loading']={};observers['user-data/torrserver-loading']();assert(not overlay.visible)
        emit('end-file',{playlist_entry_id=2,reason='stop'})
        props.path='C:/movie.mkv';props['file-local-options/cache-secs']=17;emit('start-file',{playlist_entry_id=3});hooks.on_load();assert(props['file-local-options/cache-secs']==17,'Local-file options stay untouched')
    end,debug.traceback)
    mp=real;io.open=open;for key,value in pairs(saved)do package.loaded[key]=value end;assert(ok,err)

    local now,calls=0,{}
    mp={get_time=function()return now end,get_property_bool=function()return true end,get_property=function()return 'http://media.invalid/video'end}
    local Timeline={set_from_cursor=function(self,fast)calls[#calls+1]=fast end,handle_cursor_up=function(self)self.pressed=false end,on_global_mouse_leave=function(self)self.pressed=false end}
    dofile(path('extensions/network_seek.lua'))(Timeline)
    local item=setmetatable({pressed={}}, {__index=Timeline})
    for i=1,100 do now=i*.001;item:set_from_cursor(false)end
    assert(#calls==1 and calls[1]==true,'A burst of network dragging must coalesce into a keyframe seek')
    item:handle_cursor_up();assert(#calls==2 and calls[2]==false and not item.pressed,'Release performs exactly one final precise seek')
    mp=real
end
