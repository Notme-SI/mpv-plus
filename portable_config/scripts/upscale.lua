-- Official Anime4K v4.0.1 chains. Retire the experimental ArtCNN selection safely.
local root = mp.command_native({'expand-path', '~~/'})
local utils = require 'mp.utils'
local ui = dofile(root .. '/extensions/ui_locale.lua')
local settings = dofile(root .. '/extensions/user_settings.lua')
ui.install_messages()

local prefs = {mode = 'off', quality = 'fast', engine = 'auto'}
settings.options(prefs, 'anime4k')
local retired = prefs.engine == 'artcnn'
if retired or prefs.engine == 'off' then prefs.mode = 'off' end
local modes = {'off', 'A', 'B', 'C'}
local valid_modes = {off = true, A = true, B = true, C = true}
if not valid_modes[prefs.mode] then prefs.mode = 'off' end
if prefs.quality ~= 'hq' then prefs.quality = 'fast' end
if prefs.engine == 'auto' then prefs.engine = prefs.mode == 'off' and 'off' or 'anime4k' end
if prefs.engine ~= 'anime4k' and prefs.engine ~= 'rtx' then prefs.engine = 'off'; prefs.mode = 'off' end
local prefs_path = settings.path('script-opts/anime4k.conf')
local shader_dir = root .. '/shaders/anime4k/'

local function chain(mode, quality)
    if mode == 'off' then return {} end
    local large = quality == 'hq' and 'VL' or 'M'
    local small = quality == 'hq' and 'M' or 'S'
    local files = {'Anime4K_Clamp_Highlights.glsl'}
    if mode == 'A' then
        files[#files + 1] = 'Anime4K_Restore_CNN_' .. large .. '.glsl'
    elseif mode == 'B' then
        files[#files + 1] = 'Anime4K_Restore_CNN_Soft_' .. large .. '.glsl'
    end
    local upscale = mode == 'C' and 'Anime4K_Upscale_Denoise_CNN_x2_' or 'Anime4K_Upscale_CNN_x2_'
    files[#files + 1] = upscale .. large .. '.glsl'
    files[#files + 1] = 'Anime4K_AutoDownscalePre_x2.glsl'
    files[#files + 1] = 'Anime4K_AutoDownscalePre_x4.glsl'
    files[#files + 1] = 'Anime4K_Upscale_CNN_x2_' .. small .. '.glsl'
    return files
end

local function canonical(path)
    path = mp.command_native({'expand-path', path}) or path
    path = mp.command_native({'normalize-path', path}) or path
    path = path:gsub('\\', '/')
    if package.config:sub(1, 1) == '\\' then path = path:lower() end
    return path
end

local owned = {}
local retired_shaders = {}
for _,name in ipairs({'ArtCNN_C4F16.glsl', 'ArtCNN_C4F32.glsl'}) do
    local path = canonical(root .. '/shaders/artcnn/' .. name)
    owned[path], retired_shaders[path] = true, true
end
for _,quality in ipairs({'fast', 'hq'}) do
    for _,mode in ipairs({'A', 'B', 'C'}) do
        for _,name in ipairs(chain(mode, quality)) do owned[canonical(shader_dir .. name)] = true end
    end
end

local function apply(mode, quality)
    local vo = mp.get_property('current-vo', '')
    if mode ~= 'off' and vo ~= '' and vo ~= 'gpu' and vo ~= 'gpu-next' then
        mp.osd_message('Anime4K требует видеовывод gpu или gpu-next.', 4)
        return false
    end
    local shaders = {}
    for _,file in ipairs(chain(mode, quality)) do
        local path = shader_dir .. file
        if not utils.file_info(path) then
            mp.osd_message('Файлы Anime4K отсутствуют. Переустановите сборку.', 4)
            return false
        end
        shaders[#shaders + 1] = path
    end
    local result = {}
    for _,path in ipairs(mp.get_property_native('glsl-shaders', {})) do
        if not owned[canonical(path)] then result[#result + 1] = path end
    end
    for _,path in ipairs(shaders) do result[#result + 1] = path end
    if not mp.set_property_native('glsl-shaders', result) then
        mp.osd_message('Не удалось применить Anime4K.', 4)
        return false
    end
    return true
end

local publish, save
local rtx = dofile(root .. '/extensions/rtx_vsr.lua').new(function()
    if publish then publish() end
end, function(message)
    prefs.engine, prefs.mode = 'off', 'off'
    if save then save() end
    mp.osd_message(message, 6)
    if publish then publish() end
end)
local rtx_status = {
    off = 'NVIDIA RTX', starting = 'Подготовка', restart = 'После перезапуска',
    waiting = 'Ожидание видео', idle = 'Не требуется', requested = 'Включено',
}
local mode_titles = {A = 'Чёткие линии', B = 'Мягкие линии', C = 'Уменьшение шума'}
local function menu()
    local quality_title = prefs.quality == 'hq' and 'Высокое' or 'Стандартное'
    local anime = {}
    for _,mode in ipairs({'A', 'B', 'C'}) do
        anime[#anime + 1] = {title = mode_titles[mode], hint = 'Anime4K ' .. mode,
            active = prefs.engine == 'anime4k' and prefs.mode == mode,
            value = {'script-message-to', 'upscale', 'mode', mode}}
    end
    anime[#anime + 1] = {id = 'anime-quality', title = 'Качество', hint = quality_title, items = {
        {title = 'Стандартное', hint = 'Ниже нагрузка', active = prefs.quality == 'fast',
            value = {'script-message-to', 'upscale', 'quality', 'fast'}},
        {title = 'Высокое', hint = 'Выше нагрузка', active = prefs.quality == 'hq',
            value = {'script-message-to', 'upscale', 'quality', 'hq'}},
    }}
    return {type = 'upscale', title = 'Улучшение изображения', keep_open = true, items = {
        {title = 'Без улучшений', active = prefs.engine == 'off',
            value = {'script-message-to', 'upscale', 'mode', 'off'}},
        {id = 'anime', title = 'Аниме', active = prefs.engine == 'anime4k',
            hint = prefs.engine == 'anime4k' and mode_titles[prefs.mode] or 'Anime4K', items = anime,
            footnote = 'Чёткие линии — восстановление, мягкие линии — деликатная обработка, уменьшение шума — очистка изображения. CTRL+1 / CTRL+2 / CTRL+3.'},
        {title = 'Фильмы и сериалы', active = prefs.engine == 'rtx',
            hint = prefs.engine == 'rtx' and rtx_status[rtx.status] or 'NVIDIA RTX',
            value = {'script-message-to', 'upscale', 'engine', 'rtx'}},
    }, footnote = 'Аниме — Anime4K. Фильмы и сериалы — RTX Video Super Resolution: включите Super Resolution в настройках NVIDIA. CTRL+0 — без улучшений.'}
end

publish = function()
    mp.set_property_native('user-data/anime4k', {mode = prefs.engine == 'anime4k' and prefs.mode or 'off', quality = prefs.quality})
    mp.set_property_native('user-data/upscale', {engine = prefs.engine, mode = prefs.mode, quality = prefs.quality, rtx = rtx.status})
    mp.commandv('script-message-to', 'uosc', 'update-menu', utils.format_json(menu()))
end

save = function()
    local engine = prefs.engine
    local file = io.open(prefs_path, 'wb')
    local written = file and file:write('engine=' .. engine .. '\nmode=' .. prefs.mode .. '\nquality=' .. prefs.quality .. '\n')
    local closed = file and file:close()
    if not written or not closed then mp.osd_message('Не удалось сохранить настройки улучшения изображения.', 4) end
end
local function select(mode, quality)
    if not valid_modes[mode] or quality ~= 'fast' and quality ~= 'hq' then return end
    local was_rtx = prefs.engine == 'rtx'
    rtx.disable()
    if not apply(mode, quality) then
        if was_rtx then prefs.engine, prefs.mode = 'off', 'off'; save(); publish() end
        return
    end
    prefs.engine = mode == 'off' and 'off' or 'anime4k'
    prefs.mode, prefs.quality = mode, quality
    save()
    publish()
end

mp.register_script_message('mode', function(mode) select(mode, prefs.quality) end)
mp.register_script_message('quality', function(quality)
    if quality ~= 'fast' and quality ~= 'hq' then return end
    if prefs.engine == 'rtx' then prefs.quality = quality; save(); publish()
    else select(prefs.mode, quality) end
end)
mp.register_script_message('engine', function(engine)
    if engine == 'off' then select('off', prefs.quality); return end
    if engine ~= 'rtx' then return end
    if not apply('off', prefs.quality) then return end
    prefs.engine = 'rtx'
    rtx.enable()
    save(); publish()
end)
mp.add_key_binding(nil, 'menu', function()
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json(menu()))
end)
for index,mode in ipairs(modes) do
    local selected = mode
    mp.add_key_binding('Ctrl+' .. (index - 1), 'mode-' .. mode, function() select(selected, prefs.quality) end)
end
-- A saved selection is explicit and also applies to subsequent files.
-- With the default off setting, startup leaves the user's shader list intact.
for _,path in ipairs(mp.get_property_native('glsl-shaders', {})) do
    if retired_shaders[canonical(path)] then retired = true end
end
if prefs.engine == 'rtx' then
    apply('off', prefs.quality)
    rtx.enable()
elseif (prefs.mode ~= 'off' or retired) and not apply(prefs.mode, prefs.quality) then
    prefs.engine, prefs.mode = 'off', 'off'
end
if retired then save() end
publish()
