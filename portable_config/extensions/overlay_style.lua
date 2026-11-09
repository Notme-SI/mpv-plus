-- ASS counterpart of uosc_theme's glass and plain controls.
local M={}
local glass=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/glass_surface.lua')
function M.panel(ass,box,scale,mode,hover,radius)
    if mode=='plain' then glass.solid(ass,box,scale,1,radius,hover)
    else
        glass.panel(ass,box,scale,1,radius,hover)
    end
end
return M
