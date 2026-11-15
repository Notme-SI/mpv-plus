-- Use mpv's watch-later files as the source of truth for positions.
local utils = require 'mp.utils'
local root = mp.command_native({'expand-path', '~~/'})
local ui = dofile(root .. '/extensions/ui_locale.lua')
local clock = dofile(root .. '/extensions/time_format.lua').clock
local settings = dofile(root .. '/extensions/user_settings.lua')

mp.set_property('watch-later-options', 'start')
mp.set_property_bool('write-filename-in-watch-later-config', true)
if mp.get_property('watch-later-dir', '') == '' and settings.directory() ~= root then
    mp.set_property('watch-later-dir', settings.path('watch_later/.keep'):match('^(.*)[/\\]'))
end

local loaded, entry_id = false, nil
mp.register_event('start-file', function(event) loaded, entry_id = false, event.playlist_entry_id end)
mp.register_event('file-loaded', function() loaded = true end)

local function save_position()
    if not loaded or not mp.get_property_bool('resume-playback', true)
        or not mp.get_property_bool('seekable') or mp.get_property_bool('partially-seekable') then return end
    local path = mp.get_property('path', '')
    local pos, duration = mp.get_property_number('time-pos'), mp.get_property_number('duration')
    if not pos or not duration or duration <= 0 or path == '' or path:find('%c') then return end
    local ending = mp.get_property_native('user-data/skip-finish', {})
    if pos < 1 or duration - pos < 3 or (ending.path == path and ending.id == entry_id) then
        mp.commandv('delete-watch-later-config')
    else
        mp.commandv('write-watch-later-config')
    end
end
mp.add_hook('on_unload', 80, save_position)

local function saved_entries()
    local directory = mp.get_property('current-watch-later-dir')
    if not directory then return {} end
    local entries = {}
    for _, name in ipairs(utils.readdir(directory, 'files') or {}) do
        if #name == 32 and name:match('^%x+$') then
            local filename = utils.join_path(directory, name)
            local info = utils.file_info(filename)
            local file = info and io.open(filename, 'rb')
            if file then
                local path = (file:read('*l') or ''):gsub('\r$', ''):match('^# (.+)$')
                local pos
                for line in file:lines() do
                    pos = tonumber(line:match('^start=([%d.]+)%s*$'))
                    if pos then break end
                end
                file:close()
                if path and #path < 1023 and pos and pos >= 1 and pos < math.huge then
                    entries[#entries + 1] = {path = path, pos = pos, time = info.mtime, name = name}
                end
            end
        end
    end
    table.sort(entries, function(a,b)
        if a.time ~= b.time then return a.time > b.time end
        return a.name < b.name
    end)
    return entries
end

local function label(path)
    local authority, route = path:match('https?://([^/?#;]+)([^?#;]*)')
    if authority then
        local name = route:match('/([^/]+)$')
        if name then
            local stem = name:gsub('%.[^.]+$', '')
            if #name <= 120 and not (#stem >= 16 and stem:match('^%x+$')) and stem ~= 'stream' then
                return (name:gsub('%%(%x%x)', function(byte)
                    local char = string.char(tonumber(byte, 16))
                    return char:match('%c') and ' ' or char
                end))
            end
        end
        local host = authority:match('[^@]+$') or ui.text('Онлайн-видео')
        local index = path:match('[?&]index=(%d+)')
        return index and (host .. ' · #' .. index) or host
    end
    return path:match('[^/\\]+$') or path
end

local shown = {}
mp.add_key_binding(nil, 'menu', function()
    shown = saved_entries()
    local items = {}
    for index = 1, math.min(#shown, 30) do
        local entry = shown[index]
        items[index] = {title = label(entry.path), hint = clock(mp.format_time(entry.pos)),
            value = {'script-message-to', mp.get_script_name(), 'open', tostring(index)}}
    end
    if #items == 0 then
        items[1] = {title = ui.text('Нет сохранённых позиций'), muted = true, selectable = false}
    end
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json({
        type = 'continue-watching', title = 'Продолжить просмотр', items = items,
    }))
end)

mp.register_script_message('open', function(index)
    local entry = shown[tonumber(index)]
    if not entry then return end
    if loaded and entry.path == mp.get_property('path') then
        mp.commandv('seek', tostring(entry.pos), 'absolute', 'exact')
        return
    end
    mp.command_native({'loadfile', entry.path, 'replace', -1, {start = tostring(entry.pos)}})
end)
