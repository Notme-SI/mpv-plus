return function(path)
    local real = mp
    local utils = require 'mp.utils'
    local settings, locale = package.loaded['mpv-build/user_settings'], package.loaded['mpv-build/ui_locale']
    local now, overlays, timers, actions, forced, observers, events, commands = 0, {}, {}, {}, {}, {}, {}, {}
    local props = {['time-pos']=20,duration=200,seekable=true,['input-bindings']={
        {key='LEFT',priority=13,cmd='no-osd seek -5 relative; script-binding uosc/flash-timeline'},
        {key='RIGHT',priority=13,cmd='no-osd seek 5 relative; script-binding uosc/flash-timeline'},
        {key='UP',priority=13,cmd='seek 99'},
    }}
    local function get(name, default) if props[name]==nil then return default end;return props[name] end
    local function advance(seconds)
        local target=now+seconds
        for _=1,100 do
            local next_timer
            for _,timer in ipairs(timers) do
                if timer.active and timer.at<=target and (not next_timer or timer.at<next_timer.at) then next_timer=timer end
            end
            if not next_timer then now=target;return end
            now=next_timer.at;next_timer.active=false;next_timer.fn()
        end
        error('Seek timers did not settle')
    end
    local ok,err=xpcall(function()
        package.loaded['mpv-build/ui_locale']={language=function()return props.language or 'ru'end}
        mp={get_property=get,get_property_native=get,get_property_number=get,get_property_bool=get,
            get_time=function()return now end,get_script_name=function()return 'keyboard_seek'end,
            get_osd_size=function()return 1280,720 end,
            command_native=function(args)return args[2]:gsub('^~~/',path(''))end,
            set_property_native=function(name,value)props[name]=value;return true end,
            create_osd_overlay=function()
                local overlay={update=function(self)self.visible=true end,remove=function(self)self.visible=false end}
                overlays[#overlays+1]=overlay;return overlay
            end,
            add_timeout=function(delay,fn)
                local t={at=now+delay,fn=fn,active=true,kill=function(self)self.active=false end};timers[#timers+1]=t;return t
            end,
            add_key_binding=function(_,name,fn)actions[name]=fn end,
            add_forced_key_binding=function(key,name,fn)forced[name]=fn end,
            remove_key_binding=function(name)forced[name]=nil end,
            observe_property=function(name,_,fn)observers[name]=fn end,
            register_event=function(name,fn)events[name]=fn end,
            commandv=function(...)
                local args={...};commands[#commands+1]=args
                if args[1]=='no-osd' and args[2]=='seek' then
                    assert(args[4]=='relative','Preserve keyframe and network seek policy')
                    props['time-pos']=math.max(0,math.min(props.duration,props['time-pos']+tonumber(args[3])))
                end
            end,
        }
        dofile(path('scripts/keyboard_seek.lua'));advance(.02)
        assert(forced['legacy-left'] and forced['legacy-right'] and not forced['legacy-up'],'Migrate only known old arrows, retaining custom actions')
        actions.right();advance(.1);actions.right();advance(.1);actions.right()
        assert(props['player-seek']==nil and props['user-data/player-seek'].seconds==15 and props['time-pos']==35,'Three presses show one cumulative +15 seconds')
        assert(overlays[1].visible and overlays[1].data:find('+15 с',1,true),'Draw the feedback')
        actions.left();assert(props['user-data/player-seek'].seconds==-5,'Changing direction starts a new group')
        advance(1.1);assert(not overlays[1].visible and not props['user-data/player-seek'].seconds,'Feedback expires')
        props['time-pos']=2;actions.left();assert(props['user-data/player-seek'].seconds==-2,'Do not claim movement past the file start')
        advance(1.1);props['time-pos']=198;actions.right();assert(props['user-data/player-seek'].seconds==2,'Limit feedback at the end')
        props.language='en';observers['user-data/interface-language']();assert(props['user-data/player-seek'].label=='+2 s')
        events['end-file']();assert(not overlays[1].visible,'No stale feedback on another episode')
        props['input-bindings'][#props['input-bindings']+1]={key='RIGHT',priority=20,owner='uosc',cmd='script-binding uosc/menu-next'}
        props['input-bindings'][#props['input-bindings']+1]={key='LEFT',priority=20,owner='console',cmd='script-binding console/cursor-left'}
        observers['input-bindings']();advance(.02)
        assert(not forced['legacy-right'] and not forced['legacy-left'],'Menu and text input arrows keep control')
        props['input-bindings']={{key='RIGHT',priority=13,cmd='script-binding keyboard_seek/right'}}
        observers['input-bindings']();advance(.02)
        assert(not forced['legacy-right'],'New input.conf needs no forced override')
        local count=#commands;props.seekable=false;actions.right();assert(#commands==count,'Do not seek an unseekable stream')
    end,debug.traceback)
    mp=real
    package.loaded['mpv-build/user_settings'],package.loaded['mpv-build/ui_locale']=settings,locale
    assert(ok,err)
end
