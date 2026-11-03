return function(path)
    local real=mp
    local saved=package.loaded['mpv-build/ui_locale']
    local messages,bindings,commands,errors={},{},{},0
    local result={status=0}
    local mock={
        command_native=function(args)
            if args[1]=='expand-path' then return path('') end
            commands[#commands+1]=args;return result
        end,
        get_property_number=function(name) if name=='pid' then return 12345 end end,
        register_script_message=function(name,fn) messages[name]=fn end,
        add_key_binding=function(_,name,fn) bindings[name]=fn end,
        osd_message=function() errors=errors+1 end,
    }
    local ok,err=xpcall(function()
        mp=mock
        package.loaded['mpv-build/ui_locale']={language=function()return 'en'end,text=function(v)return v end}
        dofile(path('scripts/component_updates.lua'))
        bindings.menu()
        local worker=commands[#commands]
        assert(worker.detach and worker.args[1]:find('mpv-update.exe',1,true),'Open the native updater')
        assert(table.concat(worker.args,' '):find('--pid 12345 --language en --view components',1,true))
        assert(#commands==1,'Opening the updater must keep the player running')
        messages.player()
        assert(commands[#commands].args[#commands[#commands].args]=='player','The whole player has its own update view')
        result={status=1};messages.check();assert(errors==1,'A launch failure is reported in the player')
    end,debug.traceback)
    mp=real;package.loaded['mpv-build/ui_locale']=saved;assert(ok,err)
end
