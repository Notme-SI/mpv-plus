return function(path)
    local policy=dofile(path('extensions/playback_preferences.lua'))
    local normalize=dofile(path('extensions/title_format.lua')).normalize
    local chosen=policy.subtitle({title='Full',lang='rus'},normalize)
    assert(policy.find_subtitle({{type='sub',id=8,title='Full',lang='ru'}},chosen,normalize)==8)
    assert(not policy.find_subtitle({{type='sub',id=8,title='Forced',lang='ru',forced=true}},chosen,normalize))
    assert(not policy.find_subtitle({{type='sub',id=8,title='A',lang='ru'},{type='sub',id=9,title='B',lang='ru'}},chosen,normalize))
    assert(policy.find_subtitle({{type='sub',id=8,title='Full subtitles',lang='ru'}},chosen,normalize)==8)
    assert(not policy.find_subtitle({{type='sub',id=8,title='Full',lang='ru',['hearing-impaired']=true}},chosen,normalize))
    local state={path='https://example.invalid/a.mkv',loaded=true,seekable=true,duration=100,time=30}
    assert(policy.retry(state,'error') and policy.retry(state,'eof'))
    for _,reason in ipairs({'stop','quit','redirect'}) do assert(not policy.retry(state,reason)) end
    state.time=95;assert(not policy.retry(state,'eof'))
    state.time=30;state.intentional_end=true;assert(not policy.retry(state,'eof'))
    state.path='C:/video.mkv';assert(not policy.retry(state,'error'))
    state.path='edl://!new_stream;http://localhost:8090/stream?link=abc';assert(policy.retry(state,'error'))

    local real=mp
    local old_options,old_ui=package.loaded['mp.options'],package.loaded['mpv-build/ui_locale']
    local function noop() end
    local props={playlist={{id=1,filename='http://localhost:8090/stream?link='..string.rep('a',40)},
        {id=2,filename='http://localhost:8090/next'}},['playlist-pos']=0,pause=false,seekable=true,duration=100,['time-pos']=30}
    props.path=props.playlist[1].filename
    local events,hooks,observers,bindings,messages,timers,commands,requests={},{},{},{},{},{},{},{}
    local function get(k,d) if props[k]==nil then return d end;return props[k] end
    local function set(k,v) props[k]=v end
    local function timer(_,fn)
        local t={fn=fn,active=true,kill=function(self) self.active=false end};timers[#timers+1]=t;return t
    end
    local mock={get_property=get,get_property_number=get,get_property_bool=get,get_property_native=get,
        set_property=set,set_property_number=set,set_property_bool=set,set_property_native=set,
        osd_message=noop,remove_key_binding=function(k) bindings[k]=nil end,
        create_osd_overlay=function()return {remove=noop,update=noop}end,get_osd_size=function()return 1280,720 end,
        add_key_binding=function(_,k,fn) bindings[k]=fn end,add_forced_key_binding=function(_,k,fn) bindings[k]=fn end,
        add_hook=function(k,_,fn) hooks[k]=fn end,
        register_event=function(k,fn) events[k]=events[k] or {};table.insert(events[k],fn) end,
        observe_property=function(k,_,fn) observers[k]=fn end,
        register_script_message=function(k,fn) messages[k]=fn end,
        command_native=function() return path('') end,
        commandv=function(...) commands[#commands+1]={...} end,
        add_timeout=timer,add_periodic_timer=function() return {kill=noop} end,
        command_native_async=function(args,fn) requests[#requests+1]={args=args,fn=fn};return #requests end,
        abort_async_command=function(id) requests[id].aborted=true end,
    }
    local function emit(name,event) for _,fn in ipairs(events[name] or {}) do fn(event or {}) end end
    local function tick()
        local list=timers;timers={}
        for _,t in ipairs(list) do if t.active then t.fn() end end
    end
    local continued=0
    local hook={defer=noop,cont=function() continued=continued+1 end}
    local function ending(reason)
        hooks.on_unload();emit('end-file',{playlist_entry_id=1,reason=reason});hooks.on_after_end_file(hook)
    end
    local ok,err=xpcall(function()
        mp=mock;package.loaded['mp.options']={read_options=noop}
        package.loaded['mpv-build/ui_locale']={install_messages=noop,text=function(v) return v end,language=function()return 'ru'end}
        dofile(path('scripts/network_playback.lua'))
        emit('start-file',{playlist_entry_id=1});hooks.on_load();emit('file-loaded')
        ending('error');assert(props['user-data/network-playback'].attempt==1 and bindings['cancel-reconnect'])
        tick();assert(continued==1 and not bindings['cancel-reconnect'])
        local c=commands[#commands];assert(c[1]=='playlist-play-index' and c[2]==0 and c[3]=='yes')
        emit('start-file',{playlist_entry_id=1});hooks.on_load()
        assert(props['file-local-options/start']=='28','Resume uses a string-valued mpv time option')
        emit('file-loaded')
        for attempt=2,5 do
            ending('error');assert(props['user-data/network-playback'].attempt==attempt)
            tick();emit('start-file',{playlist_entry_id=1});hooks.on_load();emit('file-loaded')
        end
        ending('error');assert(props['user-data/network-playback'].state=='failed' and not bindings['cancel-reconnect'])
        assert(continued==5,'Retry limit must release every deferred hook exactly once')
        -- A manual playlist change cancels a pending timer and frees Esc.
        emit('start-file',{playlist_entry_id=1});emit('file-loaded');ending('error')
        props['playlist-pos']=1;observers['playlist-pos']();local count=#commands;tick()
        assert(#commands==count and continued==6 and not bindings['cancel-reconnect'])
        -- Cancelling an on-demand diagnostic rejects even a late subprocess response.
        local before=#requests
        props['playlist-pos']=0;bindings.menu();assert(#requests==before+1)
        local first=requests[#requests]
        observers['user-data/uosc/menu/type'](nil,nil);assert(first.aborted)
        first.fn(true,{status=0,stdout='{"download_speed":123}'})
        bindings.menu();assert(#requests==before+2)
        local second=requests[#requests]
        emit('start-file',{playlist_entry_id=2});assert(second.aborted)
    end,debug.traceback)
    mp=real;package.loaded['mp.options']=old_options;package.loaded['mpv-build/ui_locale']=old_ui
    assert(ok,err)
end
