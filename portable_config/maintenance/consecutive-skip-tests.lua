return function(path)
    local real,open=mp,io.open
    local saved={};for _,key in ipairs({'mp.options','mpv-build/ui_locale','mpv-build/user_settings'})do saved[key]=package.loaded[key]end
    local props={['time-pos']=1,duration=1440,pause=false,['idle-active']=false,['mouse-pos']={hover=false}}
    local observers,timers,seeks,events={},{},{},{}
    local now=10
    local function noop()end
    local function get(k,d)if props[k]==nil then return d end;return props[k]end
    local function set(k,v)if k=='pause'and v=='no'then v=false end;props[k]=v;for _,fn in ipairs(observers[k] or {})do fn(k,v)end end
    local function timer(delay,fn,periodic)
        local t={at=now+delay,delay=delay,fn=fn,periodic=periodic,active=true,kill=function(self)self.active=false end};timers[#timers+1]=t;return t
    end
    local overlay={update=noop,remove=noop}
    local mock={get_property=get,get_property_native=get,get_property_number=get,get_property_bool=get,
        set_property=set,set_property_native=set,set_property_number=set,command_native=function(a)return path(a[2]:gsub('^~~/',''))end,
        observe_property=function(k,_,fn)observers[k]=observers[k] or {};table.insert(observers[k],fn)end,
        commandv=function(command,target)if command=='seek'then seeks[#seeks+1]=tonumber(target);set('time-pos',tonumber(target))end end,
        add_timeout=function(d,fn)return timer(d,fn,false)end,add_periodic_timer=function(d,fn)return timer(d,fn,true)end,
        get_time=function()return now end,get_opt=function(k)if k=='theintrodb-debug'then return 'yes'end end,
        add_key_binding=noop,add_forced_key_binding=noop,remove_key_binding=noop,register_script_message=noop,osd_message=noop,
        create_osd_overlay=function()if not overlay.created then overlay.created=true;return overlay end;return {update=noop,remove=noop}end,get_osd_size=function()return 1280,720 end,
        register_event=function(k,fn)events[k]=events[k] or {};table.insert(events[k],fn)end,msg={log=noop,warn=noop,info=noop}}
    local function advance(seconds)
        for i=1,math.floor(seconds/.025+.5)do
            now=now+.025;set('time-pos',props['time-pos']+.025)
            local count=#timers
            for j=1,count do local t=timers[j];if t.active and t.at<=now then if t.periodic then t.at=now+t.delay else t.active=false end;t.fn()end end
        end
    end
    local ok,err=xpcall(function()
        mp=mock;package.loaded['mp.options']={read_options=noop}
        package.loaded['mpv-build/user_settings']={options=noop,path=function(name)return 'memory:'..name end}
        package.loaded['mpv-build/ui_locale']={install_messages=noop,text=function(v)return v end,language=function()return 'ru'end}
        io.open=function(name,mode)if name:sub(1,7)=='memory:'then return nil end;return open(name,mode)end
        dofile(path('scripts/theintrodb.lua'));dofile(path('scripts/skip_prompt.lua'))
        local state=__tidb_debug();state.segments={{kind='recap',start=0,['end']=40},{kind='intro',start=40,['end']=130}}
        advance(1.3);assert(#seeks==1 and seeks[1]==40,'First recap must skip after its preview and fade')
        assert(overlay.data:find('Автопропуск: Заставка',1,true) and not overlay.data:find('Ранее в сериале',1,true),'Only the next active action renders, without stacking the old result')
        advance(1.8);assert(#seeks==2 and seeks[2]==130,'Adjacent opening must skip despite the previous notice')
        assert(overlay.data:find('Пропущено: Ранее в сериале · Заставка',1,true),'Consecutive results combine into one final panel')
        advance(3.5);assert(#seeks==2 and not props['user-data/skip-prompt-visible'],'No repeated seeks or stale panels after both segments')
    end,debug.traceback)
    mp=real;io.open=open;__tidb_debug=nil;for key,value in pairs(saved)do package.loaded[key]=value end;assert(ok,err)
end
