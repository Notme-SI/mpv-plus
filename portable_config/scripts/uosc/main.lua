-- Local skin, independent of the upstream uosc distribution.
local root = mp.command_native({'expand-path', '~~/'})
dofile(root .. '/extensions/uosc_skin.lua')(mp.get_script_directory())
dofile(root .. '/vendor/uosc/main.lua')

local window_scale, fullscreen_scale = options.scale, options.scale_fullscreen
mp.observe_property('user-data/player-ui/interface-scale', 'number', function(_, value)
    local factor = value or 1
    options.scale = window_scale * factor
    options.scale_fullscreen = fullscreen_scale * factor
    update_display_dimensions()
    Elements:maybe('menu', 'update_content_dimensions')
end)
