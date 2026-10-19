return function(path)
    local real=mp
    local now,props,timers,events,commands=0,{path='fixture.mkv',['time-pos']=10,volume=63},{},{},{}
    local overlay={remove=function(self)self.visible=false end,update=function(self)self.visible=true end}
    local function get(k,d)if props[k]==nil then return d end;return props[k]end
    local function advance(seconds)
        for _=1,math.floor(seconds/.01+.5)do
            now=now+.01
            for _,timer in ipairs(timers)do if timer.active and now>=timer.at then timer.at=now+timer.delay;timer.fn()end end
        end
    end
    local ok,err=xpcall(function()
        mp={get_time=function()return now end,get_property=get,get_property_bool=get,get_property_number=get,
            get_osd_size=function()return 1280,720 end,create_osd_overlay=function()return overlay end,
            set_property_native=function(k,v)props[k]=v end,
            register_event=function(k,fn)events[k]=fn end,
            add_periodic_timer=function(delay,fn)local t={at=now+delay,delay=delay,fn=fn,active=true,kill=function(self)self.active=false end};timers[#timers+1]=t;return t end,
            commandv=function(...)local args={...};commands[#commands+1]=args;assert(args[1]=='seek','Fade cannot alter volume, filters or reload the file');props['time-pos']=tonumber(args[2]);events.seek()end}
        local transition=dofile(path('extensions/skip_transition.lua')).new()
        transition.seek(32);advance(.06)
        assert(#commands==0 and overlay.visible and props['user-data/skip-transition'].active,'Fade starts before seeking')
        local alpha=tonumber(overlay.data:match('1a&H(%x%x)&'),16)
        assert(alpha>0 and alpha<255,'There are intermediate fade frames')
        advance(.08);assert(#commands==1 and commands[1][2]=='32','Exactly one precise seek after fade out')
        advance(.24);assert(not overlay.visible and not props['user-data/skip-transition'].active and props.volume==63,'Fade ends promptly without touching volume')
        transition.seek(60);advance(.14);props['paused-for-cache']=true
        advance(1);assert(not overlay.visible,'A stalled stream must not remain black indefinitely')
        props['paused-for-cache']=false
        local count=#commands
        transition.seek(90);advance(.05);events['end-file']();advance(.3)
        assert(#commands==count and not overlay.visible,'End-file cancels a delayed skip')
        transition.seek(90);events.seek();advance(.3)
        assert(#commands==count,'Manual seeking takes priority over a pending automatic skip')
        transition.seek(90);props.path='another-file.mkv';advance(.3)
        assert(#commands==count and not overlay.visible,'A fade cannot seek in a different file')
        for _,timer in ipairs(timers)do assert(not timer.active,'All animation timers stop when inactive')end
    end,debug.traceback)
    mp=real;assert(ok,err)
end
