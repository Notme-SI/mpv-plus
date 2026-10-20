return function(path)
    local real=mp
    local utils=require 'mp.utils'
    local saved_ui,saved_settings=package.loaded['mpv-build/ui_locale'],package.loaded['mpv-build/user_settings']
    local bindings,messages,menus,commands={},{},{},{}
    local function noop()end
    local ok,err=xpcall(function()
        package.loaded['mpv-build/ui_locale']={language=function()return 'ru'end}
        package.loaded['mpv-build/user_settings']={path=function(name)return path(name)end,directory=function()return path('')end}
        mp={command_native=function(args)
                if args[1]=='expand-path' then return path('')end
                commands[#commands+1]=args
            end,
            commandv=function(a,b,c,data)if c=='open-menu' then menus[#menus+1]=utils.parse_json(data)end end,
            add_key_binding=function(_,name,fn)bindings[name]=fn end,
            register_script_message=function(name,fn)messages[name]=fn end,
            osd_message=noop,command_native_async=noop}
        dofile(path('scripts/player_maintenance.lua'))
        bindings.menu()
        local item=menus[1].items[1]
        assert(item.title=='Версия плеера' and item.hint=='mpv+ 1.1.2','Maintenance shows the distribution version, not mpv core version')
        assert(item.value[3]=='github')
        messages.github()
        local command=commands[#commands]
        assert(command.detach and command.args[3]=='-WindowStyle' and command.args[4]=='Hidden')
        assert(command.args[#command.args]=='Start-Process "https://github.com/Notme-SI/mpv-plus/releases/tag/v1.1.2"','Version opens its matching GitHub release')
    end,debug.traceback)
    mp=real
    package.loaded['mpv-build/ui_locale'],package.loaded['mpv-build/user_settings']=saved_ui,saved_settings
    assert(ok,err)
end
