-- Continuous crop controller. The detector is supplied by the small upstream adapter.
return function(core)
local options, timers = core.options, core.timers
local cropdetect_label = core.label
local cleanup, remove_cropdetect, restore_hwdec = core.cleanup, core.remove_cropdetect, core.restore_hwdec
local utils = require 'mp.utils'
local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
ui.install_messages()
local config_path = dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua').path('script-opts/autocrop.conf')
local settings=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua')
if settings.directory()~=mp.command_native({'expand-path','~~/'}) then
    local f=io.open(config_path,'rb')
    if f then local saved=f:read('*a'):match('auto%s*=%s*(%w+)');f:close();if saved then options.auto=saved~='no' end end
end
local enabled, manual_scan, candidate_crop = false, false, nil
local detect_crop
-- Count decoded playback time, not wall time: pause/cache/seek cannot consume
-- the sampling interval before cropdetect has seen enough frames.
local function playback_timeout(seconds, callback)
    local elapsed = 0
    local previous = mp.get_property_number('time-pos')
    local timer
    timer = mp.add_periodic_timer(0.1, function()
        local now = mp.get_property_number('time-pos')
        if now and previous and not mp.get_property_bool('pause')
            and not mp.get_property_bool('paused-for-cache') then
            local delta = now - previous
            if delta > 0 and delta <= 1 then elapsed = elapsed + delta end
        end
        previous = now
        if elapsed >= seconds then
            timer:kill()
            callback()
        end
    end)
    return timer
end

local function schedule_next_scan(delay)
    if not enabled or not options.auto then return end
    if timers.auto_delay then timers.auto_delay:kill() end
    timers.auto_delay = playback_timeout(delay or options.check_interval, function()
        timers.auto_delay = nil
        detect_crop()
    end)
end

local function apply_crop(meta)
    local effective = meta.x > 0 or meta.y > 0
        or meta.w < meta.max_w or meta.h < meta.max_h
    local desired = effective and string.format('%dx%d+%d+%d',
        meta.w, meta.h, meta.x, meta.y) or ''

    -- Reject over-cropping and strongly asymmetric dark scene boundaries.
    local centered = math.abs(meta.x - (meta.max_w - meta.w) / 2) <= math.max(4, meta.max_w * 0.015)
        and math.abs(meta.y - (meta.max_h - meta.h) / 2) <= math.max(4, meta.max_h * 0.015)
    if effective and (meta.w < meta.min_w or meta.h < meta.min_h or not centered) then
        candidate_crop = nil
        return false
    end
    if desired == mp.get_property('video-crop', '') then
        candidate_crop = nil
        return false
    end
    -- Require two independent samples before changing automatic framing.
    -- Invalid/dark samples retain the last known good crop.
    if not manual_scan and desired ~= candidate_crop then
        candidate_crop = desired
        return true
    end
    candidate_crop = nil
    mp.commandv('no-osd', 'set', 'file-local-options/video-crop', desired)
    if manual_scan then
        mp.osd_message(effective and 'Полосы обрезаны' or 'Полосы не обнаружены', 2)
    end
    return false
end

local function detect_end()
    -- Get the metadata and remove the cropdetect filter.
    local cropdetect_metadata = mp.get_property_native(
        "vf-metadata/" .. cropdetect_label)
    remove_cropdetect()

    -- Remove the timer of detect crop.
    if timers.detect_crop then
        timers.detect_crop:kill()
        timers.detect_crop = nil
    end

    restore_hwdec()

    local meta

    -- Verify the existence of metadata.
    if cropdetect_metadata then
        meta = {
            w = cropdetect_metadata["lavfi.cropdetect.w"],
            h = cropdetect_metadata["lavfi.cropdetect.h"],
            x = cropdetect_metadata["lavfi.cropdetect.x"],
            y = cropdetect_metadata["lavfi.cropdetect.y"],
        }
    else
        mp.msg.verbose("No crop data yet.")
        candidate_crop = nil
        manual_scan = false
        schedule_next_scan()
        return
    end

    -- Verify that the metadata meets the requirements and convert it.
    if meta.w and meta.h and meta.x and meta.y then
        local width = mp.get_property_native("width")
        local height = mp.get_property_native("height")
        -- Restoring hardware decoding can temporarily remove video dimensions.
        -- Wait for the next valid sample instead of terminating the controller.
        if not width or not height or width<=0 or height<=0 then
            candidate_crop=nil;manual_scan=false;schedule_next_scan(0.5);return
        end

        meta = {
            w = tonumber(meta.w),
            h = tonumber(meta.h),
            x = tonumber(meta.x),
            y = tonumber(meta.y),
            min_w = width * options.detect_min_ratio,
            min_h = height * options.detect_min_ratio,
            max_w = width,
            max_h = height
        }
    else
        mp.msg.verbose("Got empty crop data.")
        mp.msg.info("You might need to increase detect_seconds.")
    end

    -- Completely black frames can report negative sizes or missing bounds.
    if not meta.w or not meta.h or not meta.x or not meta.y or not meta.max_w
        or meta.w <= 0 or meta.h <= 0 or meta.x < 0 or meta.y < 0
        or meta.x + meta.w > meta.max_w or meta.y + meta.h > meta.max_h then
        candidate_crop = nil
        manual_scan = false
        schedule_next_scan()
        return
    end
    local confirm = apply_crop(meta)
    manual_scan = false
    schedule_next_scan(confirm and 0.2 or nil)
end

detect_crop = function()
    core.start_detection()
    -- Replace only the sampling clock. The detector's filter and hwdec logic
    -- stay upstream; paused playback must not consume the sample interval.
    if timers.detect_crop then
        timers.detect_crop:kill()
        timers.detect_crop = playback_timeout(options.detect_seconds, detect_end)
    elseif enabled and options.auto then
        -- On the first stream, file-loaded can precede a usable video track,
        -- duration or filter chain. A rejected initial probe must not stop auto.
        schedule_next_scan(0.5)
    end
end

local function reset_scale()
    mp.set_property_number('video-zoom', 0)
    mp.set_property_number('video-pan-x', 0)
    mp.set_property_number('video-pan-y', 0)
    mp.set_property_number('panscan', 0)
end

local function menu_data()
    return {
        type = 'autocrop-settings',
        title = 'Автообрезка',
        keep_open = true,
        items = {
            {title = 'Автоматически убирать полосы',
             hint = options.auto and 'ВКЛ · Shift+C' or 'ВЫКЛ · Shift+C',
             icon = options.auto and 'toggle_on' or 'toggle_off',
             value = {'script-binding', 'autocrop/toggle_auto'}},
            {title = 'Определить полосы сейчас',
             value = {'script-binding', 'autocrop/detect_now'}, keep_open = false},
        }
    }
end

local function publish_state()
    mp.set_property_native('user-data/autocrop/auto', options.auto)
    mp.set_property_native('user-data/autocrop/active', enabled)
    mp.commandv('script-message-to', 'uosc', 'update-menu', utils.format_json(menu_data()))
end

local function save_preference()
    local f = io.open(config_path, 'rb')
    local text = f and f:read('*a') or ''
    if f then f:close() end
    text = text:gsub('\r\n', '\n')
    local count
    text, count = ('\n' .. text):gsub('\nauto%s*=[^\n]*',
        '\nauto=' .. (options.auto and 'yes' or 'no'))
    text = text:sub(2)
    if count == 0 then
        text = text .. '\nauto=' .. (options.auto and 'yes' or 'no') .. '\n'
    end
    f = io.open(config_path, 'wb')
    if not f then return false end
    local ok = f:write(text)
    local closed = f:close()
    return ok ~= nil and closed ~= nil
end

local function on_start()
    cleanup()
    enabled = options.auto
    manual_scan = false
    candidate_crop = nil
    reset_scale()
    publish_state()
    if not enabled then return end
    if options.auto_fill then mp.set_property_number('panscan', 1) end
    local delay = math.max(0, options.auto_delay - mp.get_property_number('time-pos', 0))
    schedule_next_scan(delay)
end

local function toggle_auto()
    options.auto = not options.auto
    local saved = save_preference()
    cleanup()
    enabled = options.auto
    manual_scan = false
    candidate_crop = nil
    reset_scale()
    if enabled then
        if options.auto_fill then mp.set_property_number('panscan', 1) end
        if not mp.get_property_bool('idle-active') then schedule_next_scan(0.1) end
    else
        mp.set_property('file-local-options/video-crop', '')
    end
    publish_state()
    local message = options.auto and 'Автообрезка включена' or 'Автообрезка выключена'
    mp.osd_message(saved and (message .. ' · настройка сохранена')
        or (message .. ' · не удалось сохранить настройку'), 2)
end

local function detect_now()
    cleanup()
    manual_scan = true
    candidate_crop = nil
    if options.auto_fill then mp.set_property_number('panscan', 1) end
    detect_crop()
end

mp.add_key_binding('C', 'toggle_auto', toggle_auto)
-- Preserve compatibility with older custom bindings.
mp.add_key_binding(nil, 'toggle_crop', toggle_auto)
mp.add_key_binding(nil, 'detect_now', detect_now)
mp.add_key_binding(nil, 'menu', function()
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json(menu_data()))
end)
mp.register_event('end-file', function()
    cleanup()
    enabled = false
    candidate_crop = nil
    publish_state()
end)
mp.register_event('file-loaded', on_start)
publish_state()

-- Explicit framing choices suspend automatic scans only for the current file.
local function stop_auto()
    enabled = false
    candidate_crop = nil
    cleanup()
    publish_state()
end
mp.add_key_binding(nil, 'reset', function()
    stop_auto()
    mp.set_property('file-local-options/video-crop', '')
    reset_scale()
    mp.osd_message('Исходный кадр и масштаб - до следующего видео', 2)
end)
mp.add_key_binding(nil, 'fit', function()
    stop_auto()
    reset_scale()
    mp.osd_message('Вписать изображение целиком - до следующего видео', 2)
end)
mp.add_key_binding(nil, 'fill', function()
    stop_auto()
    reset_scale()
    mp.set_property_number('panscan', 1)
    mp.osd_message('Заполнить окно: края изображения обрезаются', 2)
end)

end
