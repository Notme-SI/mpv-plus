-- ASS counterpart of uosc_theme's glass and plain controls.
local M={}
local glass=dofile(mp.command_native({'expand-path','~~/extensions/glass_surface.lua'}))
function M.panel(ass,box,scale,mode,hover,radius)
    local function layer(color,alpha,border,border_alpha,inset,clip)
        inset=inset or 0
        ass:new_event()
        ass:append(string.format('{\\an7\\pos(0,0)\\bord%.2f\\shad0\\1c&H%s&\\1a&H%02X&\\3c&HFFFFFF&\\3a&H%02X&%s}',
            border or 0,color,alpha,border_alpha or 255,clip or ''))
        ass:draw_start()
        ass:round_rect_cw(box.x0+inset,box.y0+inset,box.x1-inset,box.y1-inset,math.max(0,radius-inset))
        ass:draw_stop()
    end
    if mode=='plain' then layer('000000',hover and 92 or 122,0)
    else
        glass.panel(ass,box,scale,1,radius,hover)
    end
end
return M
