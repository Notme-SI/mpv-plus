-- Arrow seeking with grouped feedback. Preserve relative seek flags and custom bindings.
local root = mp.command_native({'expand-path', '~~/'})
local ui = dofile(root .. '/extensions/ui_locale.lua')
local metrics = dofile(root .. '/extensions/text_metrics.lua')
local measure = metrics.new()
local surface = dofile(root .. '/extensions/overlay_style.lua')
local glyphs = dofile(root .. '/extensions/lucide_glyphs.lua')
local assdraw = require 'mp.assdraw'
local overlay = mp.create_osd_overlay('ass-events')
overlay.z = 900
local steps = {left = -5, right = 5, up = 60, down = -60}
local keys = {LEFT = 'left', RIGHT = 'right', UP = 'up', DOWN = 'down'}
local installed, clear_timer, refresh_timer = {}, nil, nil
local total, origin, direction, last_press = 0, nil, nil, -math.huge

local function clear()
    if clear_timer then clear_timer:kill(); clear_timer = nil end
    total, origin, direction = 0, nil, nil
    overlay:remove()
    mp.set_property_native('user-data/player-seek', {})
end
local function render()
    if not origin or total == 0 then return end
    local w,h = mp.get_osd_size()
    if w <= 0 or h <= 0 then return end
    local scale = math.max(0.6, math.min(3, h / 720))
    local size, font = 20 * scale, 'Segoe UI'
    local label = string.format('%+d', total) .. (ui.language() == 'en' and ' s' or ' с')
    local width = math.min(measure.width(label, size, font, false) + 51 * scale, w - 16 * scale)
    local x = w * (total > 0 and 0.66 or 0.34) - width / 2
    x = math.max(8 * scale, math.min(w - width - 8 * scale, x))
    local height, y = 39 * scale, h / 2 - 19.5 * scale
    local ass = assdraw.ass_new()
    surface.panel(ass, {x0=x,y0=y,x1=x+width,y1=y+height}, scale,
        mp.get_property('user-data/player-ui/icon-style', 'glass'), false, height / 2)
    ass:new_event()
    ass:append(string.format('{\\rDefault\\an5\\pos(%.2f,%.2f)\\fnlucide\\fs%.2f\\bord0\\shad0\\1c&HFFFFFF&\\frz%d}%s',
        x + 19 * scale, y + height / 2, 19 * scale, total < 0 and 180 or 0, glyphs.fast_forward))
    ass:new_event()
    ass:append(string.format('{\\rDefault\\an4\\pos(%.2f,%.2f)\\fn%s\\fs%.2f\\bord0\\shad0\\1c&HFFFFFF&}%s',
        x + 35 * scale, y + height / 2, font, size, metrics.escape(label)))
    overlay.res_x, overlay.res_y, overlay.data = w, h, ass.text
    overlay:update()
    mp.set_property_native('user-data/player-seek', {seconds=total,label=label})
end
local function seek(name)
    local delta, position = steps[name], mp.get_property_number('time-pos')
    if not delta or not position or not mp.get_property_bool('seekable', false) then return end
    local now, sign = mp.get_time(), delta > 0 and 1 or -1
    if now - last_press > 0.9 or direction ~= sign or not origin then total, origin = 0, position end
    local duration = mp.get_property_number('duration')
    local target = math.max(0, origin + total + delta)
    if duration and duration > 0 then target = math.min(duration, target) end
    total = math.floor(target - origin + 0.5)
    direction, last_press = sign, now
    mp.commandv('no-osd', 'seek', tostring(delta), 'relative')
    mp.commandv('script-message-to', 'uosc', 'flash-timeline')
    if clear_timer then clear_timer:kill() end
    if total == 0 then clear(); return end
    render()
    clear_timer = mp.add_timeout(1, clear)
end
for name in pairs(steps) do
    local action = name
    mp.add_key_binding(nil, action, function() seek(action) end, {repeatable=true})
end

-- Older installations keep input.conf. Upgrade only known bundled/default
-- arrow actions in memory; menu/console sections and custom actions keep control.
local owner = mp.get_script_name()
local function normalize(command)
    return (command or ''):gsub('%s+', ' '):gsub('%s*;%s*', ';'):match('^%s*(.-)%s*$')
end
local function legacy(command, delta)
    command = normalize(command):gsub('^no%-osd ', '')
    local value = tostring(delta)
    return command == 'seek ' .. value or command == 'seek ' .. value .. ' relative'
        or command == 'seek ' .. value .. ' relative;script-binding uosc/flash-timeline'
end
local function refresh()
    refresh_timer = nil
    local best = {}
    for _,binding in ipairs(mp.get_property_native('input-bindings', {})) do
        if keys[binding.key] and binding.owner ~= owner and binding.priority and binding.priority >= 0 then
            local previous = best[binding.key]
            if not previous or binding.priority >= previous.priority then best[binding.key] = binding end
        end
    end
    for key,name in pairs(keys) do
        local binding = best[key]
        local eligible = binding and legacy(binding.cmd, steps[name])
        if eligible and not installed[key] then
            local action = name
            mp.add_forced_key_binding(key, 'legacy-' .. name, function() seek(action) end, {repeatable=true})
            installed[key] = true
        elseif not eligible and installed[key] then
            mp.remove_key_binding('legacy-' .. name)
            installed[key] = nil
        end
    end
end
local function queue_refresh()
    if refresh_timer then refresh_timer:kill() end
    refresh_timer = mp.add_timeout(0.01, refresh)
end
mp.observe_property('input-bindings', 'native', queue_refresh)
mp.observe_property('user-data/player-ui/icon-style', 'string', render)
mp.observe_property('user-data/interface-language', 'string', render)
mp.observe_property('osd-dimensions', 'native', render)
mp.register_event('file-loaded', clear)
mp.register_event('end-file', clear)
mp.register_event('shutdown', clear)
queue_refresh()
