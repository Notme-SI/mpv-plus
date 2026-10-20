local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
ui.install_messages()
-- Local UI preferences, kept separately from the upstream uosc code.
local utils = require 'mp.utils'
local config_path = dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua').path('script-opts/uosc.conf')
local style, cache = 'bar', true
local prefs={icon_style='glass',chapter_marks=true,controls_always=false,buffer_visible=false,statistics_visible=false}
dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua').options(prefs,'player_ui')
if prefs.icon_style~='plain' then prefs.icon_style='glass' end
local prefs_path=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua').path('script-opts/player_ui.conf')
local function save_prefs()
    local f=io.open(prefs_path,'wb')
    if not f then mp.osd_message('Не удалось сохранить оформление',3);return end
    local ok=f:write('icon_style='..prefs.icon_style..'\nchapter_marks='..(prefs.chapter_marks and 'yes' or 'no')..'\ncontrols_always='..(prefs.controls_always and 'yes' or 'no')..'\nbuffer_visible='..(prefs.buffer_visible and 'yes' or 'no')..'\nstatistics_visible='..(prefs.statistics_visible and 'yes' or 'no')..'\n')
    if not f:close() or not ok then mp.osd_message('Не удалось сохранить оформление',3) end
end
local function icons_menu()
    return {type='player-icons',title='Значки',keep_open=true,items={
        {title='Стекло',hint='Светлое и прозрачное',active=prefs.icon_style=='glass',
            value={'script-message-to','player_ui','icon-style','glass'}},
        {title='Обычные',hint='Тёмное оформление',active=prefs.icon_style=='plain',
            value={'script-message-to','player_ui','icon-style','plain'}},
    },footnote='Меняет кнопки, блок названия и оформление полос.'}
end
local function read_config()
    local f = io.open(config_path, 'rb')
    if not f then return '' end
    local text = f:read('*a')
    f:close()
    return text:gsub('\r\n', '\n')
end
local text = '\n' .. read_config()
style = text:match('\ntimeline_style%s*=%s*(%w+)') or style
cache = (text:match('\ntimeline_cache%s*=%s*(%w+)') or 'yes') ~= 'no'
if style ~= 'bar' then style = 'line' end

local function menu_data()
    return {
        type = 'player-timeline-style',
        title = 'Полоса перемотки',
        keep_open = true,
        items = {
            {title = 'Только ползунок', hint = 'Без заполнения',
             icon = 'vertical_align_center', active = style == 'line',
             value = {'script-message-to', 'player_ui', 'timeline-style', 'line'}},
            {title = 'Заполнение до текущей позиции', hint = 'Просмотренная часть',
             icon = 'linear_scale', active = style == 'bar',
             value = {'script-message-to', 'player_ui', 'timeline-style', 'bar'}},
            {title = 'Индикация загрузки', hint = cache and 'ВКЛ' or 'ВЫКЛ',
             icon = cache and 'toggle_on' or 'toggle_off',
             value = {'script-binding', 'player_ui/toggle_cache'}},
            {title='Метки пропуска',hint=prefs.chapter_marks and 'ВКЛ' or 'ВЫКЛ',
             icon=prefs.chapter_marks and 'toggle_on' or 'toggle_off',
             value={'script-binding','player_ui/toggle_marks'}},
        },
        footnote='Индикация загрузки видна, когда источник сообщает диапазоны буфера.',
    }
end
local function controls_menu()
    return {type='player-controls',title='Панель плеера',keep_open=true,items={
        {title='Не скрывать нижнюю панель',hint=prefs.controls_always and 'ВКЛ' or 'ВЫКЛ',
         icon=prefs.controls_always and 'toggle_on' or 'toggle_off',value={'script-binding','player_ui/toggle_controls'}},
        {title='Показывать строку буфера',hint=prefs.buffer_visible and 'ВКЛ' or 'ВЫКЛ',
         icon=prefs.buffer_visible and 'toggle_on' or 'toggle_off',value={'script-binding','player_ui/toggle_buffer'}},
        {title='Показывать статистику',hint=prefs.statistics_visible and 'ВКЛ' or 'ВЫКЛ',
         icon=prefs.statistics_visible and 'toggle_on' or 'toggle_off',value={'script-binding','player_ui/toggle_statistics'}},
    }}
end
local function publish()
    mp.set_property_native('user-data/player-ui/timeline-style', style)
    mp.set_property_native('user-data/player-ui/timeline-cache', cache)
    mp.set_property_native('user-data/player-ui/icon-style',prefs.icon_style)
    mp.set_property_native('user-data/player-ui/chapter-marks',prefs.chapter_marks)
    mp.set_property_native('user-data/player-ui/controls-always',prefs.controls_always)
    mp.set_property_native('user-data/player-ui/buffer-visible',prefs.buffer_visible)
    mp.set_property_native('user-data/player-ui/statistics-visible',prefs.statistics_visible)
    mp.commandv('script-message-to', 'uosc', 'update-menu', utils.format_json(menu_data()))
    mp.commandv('script-message-to','uosc','update-menu',utils.format_json(icons_menu()))
    mp.commandv('script-message-to','uosc','update-menu',utils.format_json(controls_menu()))
end
local function save_option(key, value)
    local source = '\n' .. read_config()
    local changed, count = source:gsub('\n' .. key .. '%s*=[^\n]*', '\n' .. key .. '=' .. value)
    changed = changed:sub(2)
    if count == 0 then changed = changed:gsub('\n*$', '') .. '\n' .. key .. '=' .. value .. '\n' end
    local f = io.open(config_path, 'wb')
    if not f then return false end
    local written = f:write(changed)
    local closed = f:close()
    return written ~= nil and closed ~= nil
end
local function apply(key, value)
    local saved = save_option(key, value)
    -- mp.options observes this property, updating uosc without a restart.
    local script_opts = mp.get_property_native('script-opts', {})
    script_opts['uosc-' .. key] = value
    mp.set_property_native('script-opts', script_opts)
    publish()
    mp.commandv('script-message-to', 'uosc', 'flash-elements', 'timeline')
    if not saved then mp.osd_message('Не удалось сохранить вид полосы перемотки', 3) end
end
mp.register_script_message('timeline-style', function(value)
    if value ~= 'line' and value ~= 'bar' then return end
    style = value
    apply('timeline_style', value)
end)
mp.add_key_binding(nil, 'toggle_cache', function()
    cache = not cache
    apply('timeline_cache', cache and 'yes' or 'no')
end)
mp.add_key_binding(nil, 'timeline_menu', function()
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json(menu_data()))
end)
mp.add_key_binding(nil,'icons_menu',function()
    mp.commandv('script-message-to','uosc','open-menu',utils.format_json(icons_menu()))
end)
mp.add_key_binding(nil,'controls_menu',function()
    mp.commandv('script-message-to','uosc','open-menu',utils.format_json(controls_menu()))
end)
mp.add_key_binding(nil,'toggle_controls',function()
    prefs.controls_always=not prefs.controls_always;save_prefs();publish()
end)
for _,item in ipairs({{'buffer','buffer_visible'},{'statistics','statistics_visible'}}) do
    local key=item[2]
    mp.add_key_binding(nil,'toggle_'..item[1],function()
        prefs[key]=not prefs[key];save_prefs();publish()
    end)
end
mp.register_script_message('icon-style',function(value)
    if value~='glass' and value~='plain' then return end
    prefs.icon_style=value;save_prefs();publish()
end)
mp.add_key_binding(nil,'toggle_marks',function()
    prefs.chapter_marks=not prefs.chapter_marks;save_prefs();publish()
    mp.commandv('script-message-to','uosc','flash-elements','timeline')
end)
publish()
