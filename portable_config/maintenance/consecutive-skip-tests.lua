return function(path)
    local function scenario(options)
        local real,open=mp,io.open
        local saved={};for _,key in ipairs({'mp.options','mpv-build/ui_locale','mpv-build/user_settings'})do saved[key]=package.loaded[key]end
        local props={['time-pos']=options.position or 1,duration=1440,path='https://fixture.invalid/episode',playlist={{id=1},{id=2}},['playlist-pos']=options.last and 1 or 0,pause=false,['idle-active']=false,['mouse-pos']={hover=false}}
        local observers,timers,seeks,events,messages,notices={},{},{},{},{},{}
        local now,osd,finished=10,0,{}
        local function noop()end
        local function get(k,d)if props[k]==nil then return d end;return props[k]end
        local function set(k,v)
            if k=='pause'and v=='no'then v=false end
            if k=='user-data/skip-prompt' and v.notice then notices[#notices+1]=v end
            props[k]=v;for _,fn in ipairs(observers[k] or {})do fn(k,v)end
        end
        local function timer(delay,fn,periodic)
            local t={at=now+delay,delay=delay,fn=fn,periodic=periodic,active=true,kill=function(self)self.active=false end};timers[#timers+1]=t;return t
        end
        local overlay={update=noop,remove=function(self)self.data=''end}
        local mock={get_property=get,get_property_native=get,get_property_number=get,get_property_bool=get,
            set_property=set,set_property_native=set,set_property_number=set,command_native=function(a)return path(a[2]:gsub('^~~/',''))end,
            observe_property=function(k,_,fn)observers[k]=observers[k] or {};table.insert(observers[k],fn)end,
            commandv=function(command,target)if command=='seek'then seeks[#seeks+1]=tonumber(target);set('time-pos',tonumber(target))elseif command=='playlist-next' or command=='stop' then finished[#finished+1]=command;set('time-pos',1440)end end,
            add_timeout=function(d,fn)return timer(d,fn,false)end,add_periodic_timer=function(d,fn)return timer(d,fn,true)end,
            get_time=function()return now end,get_opt=function(k)if k=='theintrodb-debug'then return 'yes'end end,
            add_key_binding=noop,add_forced_key_binding=noop,remove_key_binding=noop,register_script_message=function(k,fn)messages[k]=fn end,
            osd_message=function()osd=osd+1 end,
            create_osd_overlay=function()if not overlay.created then overlay.created=true;return overlay end;return {update=noop,remove=noop}end,
            get_osd_size=function()return 1280,720 end,
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
            package.loaded['mpv-build/user_settings']={options=function(values,name)
                if name=='skip_preferences' then for k,v in pairs(options.preferences or {})do values[k]=v end end
            end,path=function(name)return 'memory:'..name end}
            package.loaded['mpv-build/ui_locale']={install_messages=noop,text=function(v)return v end,language=function()return options.language or 'ru'end}
            io.open=function(name,mode)if name:sub(1,7)=='memory:'then return nil end;return open(name,mode)end
            dofile(path('scripts/theintrodb.lua'));dofile(path('scripts/skip_prompt.lua'))
            local state=__tidb_debug();state.segments=options.segments
            advance(.2)
            if options.blocked then
                assert(not props['user-data/skip-prompt-visible'],'Previews have no suggestion')
                messages['toggle-skip-preference']('preview')
                messages['skip-active']('preview',tostring(options.segments[1].start))
                messages['skip-segment']('1')
                advance(5)
                assert(#seeks==0 and #finished==0,'No automatic, manual or legacy-message preview skips')
                return
            end
            assert(overlay.data:find(options.caption,1,true),'Unexpected suggestion: '..tostring(overlay.data))
            if options.manual then
                assert(#seeks==0,'Manual suggestion must not seek')
                messages['skip-active'](options.segments[1].kind,tostring(options.segments[1].start))
            end
            advance(options.manual and .4 or 1.2)
            if options.finish then
                assert(#seeks==0 and #finished==1 and finished[1]==(options.last and 'stop' or 'playlist-next'),'Terminal manual credits skips must advance/finish directly, without an EOF seek')
                assert(props['user-data/skip-finish'].path==props.path and props['user-data/skip-finish'].id==(options.last and 2 or 1))
            else assert(#seeks==1 and seeks[1]==options.target,'One transition must land at the requested final boundary')end
            if not options.manual then
                assert(#notices==1 and osd==0,'One notice without a duplicate OSD message')
                assert(#notices[1].kinds==(options.joined and 2 or 1),'Only the segments in this jump belong in the notice')
            end
            advance(3.5)
            assert(#seeks==(options.finish and 0 or 1) and (not options.finish or #finished==1),'The second segment must not cause another transition')
            if options.after_caption then assert(overlay.data:find(options.after_caption,1,true),'Next manual segment remains available')
            else assert(not props['user-data/skip-prompt-visible'],'No stale notification after the one transition')end
        end,debug.traceback)
        mp=real;io.open=open;__tidb_debug=nil;for key,value in pairs(saved)do package.loaded[key]=value end;assert(ok,err)
    end
    local opening={{kind='recap',start=0,['end']=40},{kind='intro',start=40,['end']=130}}
    local ending={{kind='credits',start=1000,['end']=1080},{kind='preview',start=1080,['end']=1120}}
    scenario{segments=opening,caption='Автопропуск: Ранее в сериале и Заставки',target=130,joined=true}
    scenario{segments=ending,position=1001,preferences={preview=true},caption='Автопропуск: Титры',target=1080}
    scenario{segments=opening,preferences={enabled=false},caption='Пропустить: Ранее в сериале и Заставку',target=130,manual=true,joined=true}
    scenario{segments=ending,position=1001,preferences={enabled=false},caption='Пропустить: Титры',target=1080,manual=true}
    scenario{segments=ending,position=1001,caption='Автопропуск: Титры',target=1080}
    scenario{segments=opening,preferences={intro=false},caption='Автопропуск: Ранее в сериале',target=40,after_caption='Пропустить: Заставку'}
    scenario{segments={{kind='intro',start=0,['end']=90}},caption='Автопропуск: Заставки',target=90}
    scenario{segments=opening,language='en',caption='Auto-skip: Recap and Intro',target=130,joined=true}
    for _,last in ipairs({false,true})do
        scenario{segments={{kind='preview',start=1420,['end']=1440}},position=1421,preferences={preview=true},blocked=true,last=last}
    end
    for _,last in ipairs({false,true})do
        scenario{segments={{kind='credits',start=1400,['end']=1440}},position=1401,caption='Пропустить: Титры',preferences={enabled=false},manual=true,finish=true,last=last}
    end
    local segments=dofile(path('extensions/skip_segments.lua'))
    local separated={{kind='recap',start=0,['end']=40},{kind='intro',start=43,['end']=130}}
    assert(segments.action(separated,separated[1],true,{recap=true,intro=true})['end']==40,'Preserve the scene between separated segments')
    separated[2].start=40.75
    assert(segments.action(separated,separated[1],true,{recap=true,intro=true})['end']==130,'Allow small timestamp rounding at a shared boundary')
    assert(segments.action(opening,opening[1],true,{recap=false,intro=true})['end']==40,'Never combine a manual recap with an automatic opening')
end
