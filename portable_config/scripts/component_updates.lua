local root=mp.command_native({'expand-path','~~/'})
local ui=dofile(root..'/extensions/ui_locale.lua')
local function open(view)
    local result=mp.command_native({name='subprocess',detach=true,args={
        root..'/maintenance/mpv-update.exe','--root',root..'/..',
        '--pid',tostring(mp.get_property_number('pid') or 0),
        '--language',ui.language(),'--view',view}})
    if not result or result.status~=0 then mp.osd_message(ui.text('Не удалось запустить обновление'),4) end
end
mp.add_key_binding(nil,'menu',function() open('components') end)
mp.register_script_message('check',function() open('components') end)
mp.register_script_message('install',function() open('components') end)
mp.register_script_message('player',function() open('player') end)
