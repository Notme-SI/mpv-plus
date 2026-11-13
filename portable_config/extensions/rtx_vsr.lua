-- RTX VSR uses mpv's native video processor, not a GLSL shader chain.
local M = {}
function M.scale(video, display)
    if type(video) ~= 'table' or type(display) ~= 'table' then return end
    local w, h = tonumber(video.dw or video.w), tonumber(video.dh or video.h)
    local tw, th = tonumber(display.w), tonumber(display.h)
    if not w or not h or not tw or not th or w <= 0 or h <= 0 then return end
    tw = tw - (tonumber(display.ml) or 0) - (tonumber(display.mr) or 0)
    th = th - (tonumber(display.mt) or 0) - (tonumber(display.mb) or 0)
    if (tonumber(video.rotate) or 0) % 180 ~= 0 then w, h = h, w end
    -- Avoid a larger intermediate than 4K, including native 4K playback.
    local ratio = math.min(tw / w, th / h, 4, 3840 / w, 2160 / h)
    if ratio <= 1.01 then return end
    return tonumber(string.format('%.6f', ratio))
end

function M.new(changed, failed)
    local self = {enabled = false, status = 'off'}
    local label = 'mpvplus-vsr'
    local managed, timer = {}, nil
    local applied_scale = nil
    local function notify(status)
        self.status = status
        changed(status)
    end
    local function cancel()
        if timer then timer:kill(); timer = nil end
    end
    local function filter(scale)
        local list = {}
        for _,entry in ipairs(mp.get_property_native('vf', {})) do
            if entry.label ~= label then list[#list + 1] = entry end
        end
        if scale then
            list[#list + 1] = {name = 'd3d11vpp', label = label,
                params = {scale = string.format('%.6f', scale), ['scaling-mode'] = 'nvidia'}}
        end
        return mp.set_property_native('vf', list)
    end
    local function set_option(name, value)
        local old = mp.get_property(name, '')
        if old == value then return true end
        if not mp.set_property(name, value) then return false end
        managed[name] = managed[name] or {before = old}
        managed[name].after = value
        return true
    end
    local function restore()
        -- API option writes also reset mpv's decoder/VO. Leave a running
        -- window intact; the untouched mpv.conf restores its API next launch.
        if mp.get_property('current-vo', '') ~= '' then managed = {}; return end
        -- Restore the pair together only while it is still ours. A neutral
        -- context bridges the APIs, avoiding an impossible Vulkan/D3D11 pair.
        local untouched, any = true, false
        for name,value in pairs(managed) do
            any = true
            if mp.get_property(name, '') ~= value.after then untouched = false end
        end
        if untouched and any then
            local api = managed['gpu-api'] and managed['gpu-api'].before or mp.get_property('gpu-api', '')
            local context = managed['gpu-context'] and managed['gpu-context'].before or mp.get_property('gpu-context', '')
            mp.set_property('gpu-context', '')
            mp.set_property('gpu-api', api)
            mp.set_property('gpu-context', context)
        end
        managed = {}
    end
    function self.disable()
        cancel()
        self.enabled = false
        if applied_scale then filter(nil) end
        applied_scale = nil
        restore()
        notify('off')
    end
    local function fail(message)
        if not self.enabled then return end
        self.disable()
        failed(message)
    end
    local function prepare()
        if not set_option('gpu-api', 'd3d11') or not set_option('gpu-context', 'd3d11') then
            fail('Не удалось настроить видеовывод RTX VSR.')
            return false
        end
        return true
    end
    local function update()
        if not self.enabled then return end
        if mp.get_property('current-vo', '') == '' then notify('waiting'); return end
        if mp.get_property('current-gpu-context', '') ~= 'd3d11' then
            notify('restart')
            return
        end
        local scale = M.scale(mp.get_property_native('video-params'), mp.get_property_native('osd-dimensions'))
        if not scale then
            if applied_scale then filter(nil); applied_scale = nil end
            notify('idle')
            return
        end
        if applied_scale and math.abs(applied_scale - scale) < 0.005 then return end
        -- Only this named filter is managed. Personal crop/audio/video filters survive.
        if not filter(scale) then fail('Не удалось включить фильтр RTX VSR.'); return end
        applied_scale = scale
        notify('requested')
    end
    local function schedule()
        if not self.enabled then return end
        if timer then timer:kill() end
        timer = mp.add_timeout(0.3, function() timer = nil; update() end)
    end
    function self.enable()
        if self.enabled then schedule(); return true end
        if mp.get_property('platform', '') ~= 'windows' then
            failed('RTX VSR доступен только в Windows с видеокартой NVIDIA RTX.')
            return false
        end
        self.enabled = true
        notify('starting')
        -- Windows chooses D3D11 by default. Preserve any running renderer and
        -- software filters; mpv uploads software frames to the processor itself.
        if mp.get_property('current-vo', '') == '' then
            if not prepare() then return false end
        elseif mp.get_property('current-gpu-context', '') ~= 'd3d11' then
            notify('restart')
            mp.osd_message('RTX VSR включится после перезапуска плеера. Текущий просмотр продолжается.', 6)
        end
        schedule()
        return true
    end
    for _,name in ipairs({'video-params', 'osd-dimensions'}) do mp.observe_property(name, 'native', schedule) end
    mp.add_hook('on_load', 5, function()
        if self.enabled and mp.get_property('current-vo', '') == '' then prepare() end
    end)
    mp.register_event('file-loaded', schedule)
    mp.register_event('end-file', function()
        if timer then timer:kill(); timer = nil end
        if applied_scale then filter(nil); applied_scale = nil end
        if self.enabled then notify('waiting') end
    end)
    -- Failure of the NVIDIA extension otherwise leaves ordinary D3D scaling
    -- running silently. Surface it and remove the owned filter instead.
    mp.enable_messages('warn')
    mp.register_event('log-message', function(event)
        if self.enabled and event.prefix == 'd3d11vpp' and (event.level == 'error'
            or (event.text or ''):find('Failed to enable NVIDIA RTX Super Resolution', 1, true)) then
            fail('Драйвер не включил RTX VSR. Проверьте видеокарту и настройки NVIDIA.')
        end
    end)
    return self
end
return M
