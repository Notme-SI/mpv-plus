return function(path)
    local real,open=mp,io.open
    local utils=require 'mp.utils'
    local subprocess=utils.subprocess
    local saved={}
    for _,k in ipairs({'mp.options','mpv-build/user_settings','mpv-build/ui_locale'}) do saved[k]=package.loaded[k] end
    local props={volume=100,['volume-max']=130,pause=false,['time-pos']=40,duration=1440}
    local observers,events,messages,timers,commands,osd={},{},{},{},{},{}
    local now=10
    local files={['volume-state.json']='{"volume":37}'}
    local function noop() end
    local function get(k,d) if props[k]==nil then return d end;return props[k] end
    local function set(k,v) if k=='pause' and v=='no' then v=false end;props[k]=v end
    local function timer(_,fn)
        local t={fn=fn,active=true,kill=function(self) self.active=false end};timers[#timers+1]=t;return t
    end
    local mock={get_property=get,get_property_native=get,get_property_number=get,get_property_bool=get,
        set_property=set,set_property_native=set,set_property_number=set,
        command_native=function(a) return path(a[2]:gsub('^~~/','')) end,
        commandv=function(...) local args={...};commands[#commands+1]=args;if args[1]=='seek'then props['time-pos']=tonumber(args[2])end end,
        observe_property=function(k,_,fn) observers[k]=fn end,
        register_event=function(k,fn) events[k]=fn end,
        register_script_message=function(k,fn) messages[k]=fn end,
        add_key_binding=noop,remove_key_binding=noop,osd_message=function(text,seconds)osd[#osd+1]={text=text,seconds=seconds}end,
        add_timeout=timer,add_periodic_timer=timer,get_time=function() return now end,
        get_opt=function(k) if k=='theintrodb-debug' then return 'yes' end end,
        create_osd_overlay=function()return {update=noop,remove=noop}end,
        msg={log=noop,warn=noop,info=noop},get_osd_size=function() return 1280,720 end}
    local ok,err=xpcall(function()
        mp=mock
        package.loaded['mp.options']={read_options=noop}
        package.loaded['mpv-build/user_settings']={path=function(name) return 'memory:'..name end,options=noop}
        package.loaded['mpv-build/ui_locale']={install_messages=noop,text=function(v) return v end,language=function() return 'ru' end}
        io.open=function(name,mode)
            if name:sub(1,7)~='memory:' then return open(name,mode) end
            name=name:sub(8)
            if mode=='rb' and not files[name] then return nil end
            return {read=function() return files[name] end,close=function() return true end,
                write=function(self,v) files[name]=v;return self end}
        end
        dofile(path('scripts/volume_memory.lua'))
        assert(props.volume==37,'Restore session volume')
        local manual=dofile(path('extensions/manual_identity.lua'))
        local parsed=assert(manual.parse('Kimetsu no Yaiba 1 20'))
        assert(parsed.episode==20 and parsed.season==1 and tostring(parsed.mal_id)=='38000','Parse season and episode explicitly')
        props.path='http://localhost:8090/stream?link='..string.rep('a',40)..'&index=20'
        props['playlist-pos']=19
        assert(manual.save(parsed))
        props['playlist-pos']=20
        local next_episode=assert(manual.current('21.Against.Corps.Rules.mkv'))
        assert(next_episode.episode==21 and tostring(next_episode.mal_id)=='38000','Reuse confirmed series on next episode')
        props.path='http://localhost:8090/stream?link='..string.rep('b',40)..'&index=21'
        assert(not manual.current('21.mkv'),'A manual correction must not leak into another torrent')
        props.volume=23;observers.volume(nil,23);events.shutdown()
        assert(utils.parse_json(files['volume-state.json']).volume==23,'Flush volume on exit before debounce')
        props.volume=100;dofile(path('scripts/volume_memory.lua'));assert(props.volume==23,'Restore on next launch')
        dofile(path('scripts/theintrodb.lua'))
        local state=__tidb_debug()
        for _,kind in ipairs({'intro','recap','credits','preview'}) do
            props['time-pos']=40
            state.segments={{kind=kind,start=35,['end']=125}};state.seek_grace_until=0
            commands={}
            for _,t in ipairs(timers) do if t.active then t.fn() end end
            for _,c in ipairs(commands) do assert(c[1]~='seek','Never seek before the banner renders')end
            local prompt=props['user-data/skip-prompt']
            assert(prompt.id and prompt.kind==kind,'Publish the preview before automatic seeking')
            props['user-data/skip-prompt-ready']={id=prompt.id,time=now}
            now=now+.9
            for _,t in ipairs(timers) do if t.active then t.fn() end end
            for _,c in ipairs(commands) do assert(c[1]~='seek','Preview must last a full second')end
            now=now+.11
            for _,t in ipairs(timers) do if t.active then t.fn() end end
            now=now+.13
            for _,t in ipairs(timers) do if t.active then t.fn() end end
            local sought=false
            for _,c in ipairs(commands) do if c[1]=='seek' then sought=true;assert(c[2]=='125') end end
            assert(sought==(kind~='preview'),'Default skip selection: '..kind)
            if sought then assert(osd[#osd].seconds==3,'Skip result must stay visible for 3 seconds')end
            now=now+.025;for _,t in ipairs(timers)do if t.active then t.fn()end end
            now=now+.2;for _,t in ipairs(timers)do if t.active then t.fn()end end
        end
        messages['toggle-skip-preference']('intro')
        assert(files['script-opts/skip_preferences.conf']:find('intro=no',1,true),'Persist separate type selection')
        messages['toggle-skip-preference']('enabled')
        props['time-pos']=40;state.segments={{kind='credits',start=35,['end']=125}};state.seek_grace_until=0;commands={}
        for _,t in ipairs(timers) do if t.active then t.fn() end end
        for _,c in ipairs(commands) do assert(c[1]~='seek','Master switch stops automatic skipping') end
        commands={};messages['skip-active']('intro','35');assert(#commands==0,'Reject a stale prompt')
        messages['skip-active']('credits','35')
        now=now+.13;for _,t in ipairs(timers)do if t.active then t.fn()end end
        local manual_seek
        for _,command in ipairs(commands)do if command[1]=='seek'then manual_seek=command end end
        assert(manual_seek and manual_seek[2]=='125','Manual skip works with automatic skipping off')
        local hash=string.rep('a',40)
        props.path='http://localhost:8090/stream?link='..hash..'&index=2&play'
        utils.subprocess=function() return {status=0,stdout=utils.format_json({hash=hash,name='Kimetsu no Yaiba',
            file_stats={{id=2,path='Kimetsu no Yaiba/02.Trainer.Sakonji.Urokodaki.mkv'}}})} end
        local source=dofile(path('extensions/media_source.lua'));source.install()
        utils.subprocess({args={'curl','http://localhost:8090/stream?link='..hash..'&stat'}})
        assert(source.current().title=='Kimetsu no Yaiba','Reuse the loader response for series context')
        props.path='edl://!new_stream;http://localhost:8090/stream?link='..hash..'&index=2&play'
        observers.path();assert(source.current().path:find('02.Trainer',1,true),'EDL streams keep context')
        props.path='http://localhost:8090/stream?link='..string.rep('b',40)..'&index=2&play'
        observers.path();assert(not source.current().title,'Never reuse another torrent context')
    end,debug.traceback)
    mp=real;io.open=open;utils.subprocess=subprocess;__tidb_debug=nil
    for k,v in pairs(saved) do package.loaded[k]=v end
    assert(ok,err)
end
