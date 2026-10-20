local root=mp.command_native({'expand-path','~~/'})
local utils=require 'mp.utils'
local ui=dofile(root..'/extensions/ui_locale.lua')
local settings=dofile(root..'/extensions/user_settings.lua')
local busy=false
local function text(ru,en) return ui.language()=='en' and en or ru end
local function version()
    for _,path in ipairs({root..'/../doc/VERSION',root..'/../VERSION'}) do
        local file=io.open(path,'rb')
        if file then
            local value=(file:read(64) or ''):match('^%s*(%d+%.%d+%.%d+)%s*$');file:close()
            if value then return value end
        end
    end
    return '1.1.2'
end
local function show()
    local items={
        {title=text('Версия плеера','Player version'),hint='mpv+ '..version(),value={'script-message-to','player_maintenance','github'}},
        {title=text('Обновления компонентов','Component updates'),value={'script-binding','component_updates/menu'}},
        {title=text(busy and 'Создаём резервную копию…' or 'Создать резервную копию',busy and 'Creating backup…' or 'Create backup'),selectable=not busy,value={'script-message-to','player_maintenance','backup'}},
        {title=text('Настроить TorrServer','Configure TorrServer'),value={'script-message-to','player_maintenance','configure'}},
        {title=text('Открыть инструкцию','Open guide'),value={'script-message-to','player_maintenance','guide'}},
    }
    mp.commandv('script-message-to','uosc','open-menu',utils.format_json({type='player-maintenance',title=text('Обслуживание','Maintenance'),items=items,keep_open=true}))
end
mp.add_key_binding(nil,'menu',show)
mp.register_script_message('github',function()
    mp.command_native({name='subprocess',detach=true,args={'powershell.exe','-NoProfile','-WindowStyle','Hidden','-Command',
        'Start-Process "https://github.com/Notme-SI/mpv-plus/releases/tag/v'..version()..'"'}})
end)
mp.register_script_message('backup',function()
    if busy then return end
    busy=true;show()
    local report=os.tmpname();os.remove(report)
    mp.command_native_async({name='subprocess',playback_only=false,capture_stdout=true,capture_stderr=true,args={
        'powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',root..'/maintenance/Export-MPV.ps1',
        '-SettingsDirectory',settings.directory(),'-ReportPath',report}},function(ok,result)
        busy=false
        local f=io.open(report,'rb');local data
        if f then data=utils.parse_json(f:read('*a'));f:close();os.remove(report) end
        if ok and result and result.status==0 and data and data.path then
            mp.osd_message(text('Резервная копия сохранена в Загрузки','Backup saved in Downloads'),5)
            mp.command_native({name='subprocess',detach=true,args={'explorer.exe','/select,',data.path}})
        else mp.osd_message(text('Не удалось создать резервную копию','Could not create backup'),5) end
    end)
end)
mp.register_script_message('configure',function()
    mp.command_native({name='subprocess',detach=true,args={'powershell.exe','-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',
        root..'/maintenance/Configure-TorrServer-GUI.ps1','-ConfigPath',settings.path('script-opts/torrserver-loader.conf'),'-Language',ui.language()}})
end)
mp.register_script_message('guide',function()
    local parent=root:gsub('[/\\]portable_config[/\\]?$','')
    mp.command_native({name='subprocess',detach=true,args={'notepad.exe',parent..'/README.txt'}})
end)
