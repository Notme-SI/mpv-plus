local utils=require 'mp.utils'
local root=mp.command_native({'expand-path','~~/'})
local ui=dofile(root..'/extensions/ui_locale.lua')
local busy,report=false,nil
local result_path=(os.getenv('APPDATA') or os.getenv('TEMP'))..'/mpv-plus/update-result.json'
local function read(path)
    local f=io.open(path,'rb');if not f then return nil end
    local data=utils.parse_json(f:read('*a'));f:close();return data
end
local function item(title,binding,hint)
    return {title=ui.text(title),hint=hint and ui.text(hint),value={'script-message-to','component_updates',binding}}
end
local function menu()
    local items={item(busy and 'Проверяем обновления…' or 'Проверить обновления','check')}
    local log=result_path:gsub('update%-result.json$','update.log')
    if utils.file_info(log) then items[#items+1]=item('Открыть журнал обновления','log') end
    if report then
        for _,row in ipairs(report.components or {}) do
            items[#items+1]={title=row.name,hint=ui.text(row.status),selectable=false}
        end
        if (report.available or 0)>0 and not busy then
            items[#items+1]=item('Установить и закрыть плеер','install')
        end
        if report.failed then items[#items+1]={title=ui.text('Проверка не завершена. Повторите позже.'),hint=report.error,selectable=false} end
    end
    return {type='component-updates',title=ui.text('Обновления компонентов'),keep_open=true,items=items,
        footnote=ui.text('При установке плеер закроется и откроется снова. Личные настройки сохраняются.')}
end
local function show(update)
    mp.commandv('script-message-to','uosc',update and 'update-menu' or 'open-menu',utils.format_json(menu()))
end
local function check()
    if busy then return end
    busy=true;report=nil;show(true)
    local path=os.tmpname();os.remove(path)
    mp.command_native_async({name='subprocess',playback_only=false,capture_stdout=true,capture_stderr=true,
        args={'powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',root..'/maintenance/Update-MPV.ps1',
            '-Mode','Check','-ReportPath',path}},function(ok,result)
        busy=false;report=read(path) or {failed=true};os.remove(path)
        if not ok or not result or result.status~=0 then
            report.failed=true
            local log=result_path:gsub('update%-result.json$','update.log')
            dofile(root..'/extensions/user_settings.lua').path('update-state')
            local f=io.open(log,'wb');if f then f:write(result and (result.stderr or '')..(result.stdout or '') or 'Could not start updater');f:close() end
        end
        show(true)
    end)
end
mp.register_script_message('check',check)
mp.register_script_message('log',function()
    local path=result_path:gsub('update%-result.json$','update.log')
    if utils.file_info(path) then mp.command_native({name='subprocess',detach=true,args={'notepad.exe',path}}) end
end)
mp.register_script_message('install',function()
    if busy or not report or (report.available or 0)==0 then return end
    local pid=mp.get_property_number('pid')
    if not pid then return end
    local result=mp.command_native({name='subprocess',detach=true,
        args={'powershell.exe','-NoProfile','-WindowStyle','Normal','-ExecutionPolicy','Bypass','-File',
            root..'/maintenance/Update-Components.ps1','-WaitProcessId',tostring(pid),'-ResultPath',result_path,'-Visible'}})
    if result and result.status==0 then mp.commandv('quit')
    else mp.osd_message(ui.text('Не удалось запустить обновление'),4) end
end)
mp.add_key_binding(nil,'menu',function() show(false) end)
mp.observe_property('user-data/interface-language','string',function() show(true) end)
mp.add_timeout(1,function()
    local result=read(result_path)
    if result then
        os.remove(result_path)
        mp.osd_message(ui.text(result.success and 'Компоненты обновлены' or 'Обновление не завершено. Откройте журнал.'),5)
    end
end)
