return function(path)
    local real,open=mp,io.open
    local globals={};for _,name in ipairs({'class','state','config','Elements','request_render'})do globals[name]=_G[name]end
    local packages={};for _,name in ipairs({'mpv-build/user_settings','mpv-build/ui_locale'})do packages[name]=package.loaded[name]end
    local preload={};for name,value in pairs(package.preload)do preload[name]=value end
    local files={['script-opts/uosc.conf']='timeline_persistency=\ncontrols_persistency=\n'}
    local props,observers,bindings,menus={},{},{},{}
    local function noop()end
    local mock={command_native=function(a)return path(a[2]:gsub('^~~/',''))end,
        observe_property=function(k,_,fn)observers[k]=fn end,
        set_property_native=function(k,v)props[k]=v;if observers[k]then observers[k](k,v)end end,
        get_property_native=function(k,d)if props[k]==nil then return d end;return props[k]end,
        add_key_binding=function(_,k,fn)bindings[k]=fn end,register_script_message=noop,osd_message=noop,
        commandv=function(a,b,c,data)if a=='script-message-to'and c=='open-menu'then menus[#menus+1]=require('mp.utils').parse_json(data)end end}
    local ok,err=xpcall(function()
        mp=mock
        package.loaded['mpv-build/ui_locale']={install_messages=noop,text=function(v)return v end}
        package.loaded['mpv-build/user_settings']={path=function(name)return 'memory:'..name end,options=function(values,name)
            if name=='player_ui'then for key in pairs(values) do
                local value=(files['script-opts/player_ui.conf']or''):match(key..'=([^\n]+)')
                if value=='yes' or value=='no' then values[key]=value=='yes' end
            end end
        end}
        io.open=function(name,mode)
            if name:sub(1,7)~='memory:'then return open(name,mode)end;name=name:sub(8)
            if mode=='rb'and not files[name]then return nil end
            return {read=function()return files[name]end,write=function(self,v)files[name]=v;return self end,close=function()return true end}
        end
        _G.class=function()return {}end;_G.state={is_idle=false};_G.config={};_G.Elements={curtain={opacity=0,render_order=100}};_G.request_render=noop
        dofile(path('extensions/uosc_skin.lua'))(path('scripts/uosc'))
        local Element=package.preload['elements/Element']()
        local element=setmetatable({id='controls',render_order=6,min_visibility=0,proximity=0},{__index=Element})
        dofile(path('scripts/player_ui.lua'));assert(element:get_visibility()==0,'Existing automatic hiding remains default')
        bindings.controls_menu();assert(menus[1].title=='Панель плеера'and menus[1].items[1].title=='Не скрывать нижнюю панель'and menus[1].items[1].hint=='ВЫКЛ')
        assert(props['user-data/player-ui/buffer-visible'] and props['user-data/player-ui/statistics-visible'])
        bindings.toggle_buffer();assert(not props['user-data/player-ui/buffer-visible'] and props['user-data/player-ui/statistics-visible'])
        bindings.toggle_statistics();assert(not props['user-data/player-ui/buffer-visible'] and not props['user-data/player-ui/statistics-visible'])
        bindings.toggle_buffer();assert(props['user-data/player-ui/buffer-visible'] and not props['user-data/player-ui/statistics-visible'])
        dofile(path('scripts/player_ui.lua'));assert(props['user-data/player-ui/buffer-visible'] and not props['user-data/player-ui/statistics-visible'],'Independent preferences survive restart')
        bindings.toggle_statistics()
        bindings.toggle_controls();assert(element:get_visibility()==1 and files['script-opts/player_ui.conf']:find('controls_always=yes',1,true),'Pin controls immediately and persist')
        state.is_idle=true;assert(element:get_visibility()==1,'Keep the panel visible before opening a file')
        state.is_idle=false
        Elements.curtain.opacity=1;assert(element:get_visibility()==0,'Native menus still cover pinned controls');Elements.curtain.opacity=0
        dofile(path('scripts/player_ui.lua'));assert(element:get_visibility()==1,'Restore persistent controls on next launch')
        bindings.toggle_controls();assert(element:get_visibility()==0,'Turning off restores native proximity hiding')
        config.controls_persistency={video=true};state.is_video=true;assert(element:get_visibility()==1,'Turning off preserves custom native persistency')
    end,debug.traceback)
    mp=real;io.open=open
    for _,name in ipairs({'class','state','config','Elements','request_render'})do _G[name]=globals[name]end
    for _,name in ipairs({'mpv-build/user_settings','mpv-build/ui_locale'})do package.loaded[name]=packages[name]end
    for name in pairs(package.preload)do if preload[name]==nil then package.preload[name]=nil end end
    for name,value in pairs(preload)do package.preload[name]=value end
    assert(ok,err)
end
