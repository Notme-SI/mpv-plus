-- Shared ASS glass surface for uosc and skip prompts. No video readback or filters.
local M={}
local function alpha(opacity)
    return math.floor(255*(1-math.max(0,math.min(1,opacity)))+.5)
end
local function shape(ass,color,opacity,blur,border,clip,draw)
    ass:new_event()
    ass:append(string.format('{\\rDefault\\an7\\pos(0,0)\\alpha&H00&\\bord%.2f\\shad0\\blur%.2f\\1c&H%s&\\1a&H%02X&\\3c&H%s&\\3a&H%02X&%s}',
        border or 0,blur or 0,color,alpha(border and border>0 and 0 or opacity),color,alpha(opacity),clip or ''))
    ass:draw_start();draw();ass:draw_stop()
end
local function rounded_path(x0,y0,x1,y1,r)
    r=math.max(0,math.min(r,(x1-x0)/2,(y1-y0)/2))
    local k=r*.55228475
    return string.format('m %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f',
        x0+r,y0,x1-r,y0,x1-r+k,y0,x1,y0+r-k,x1,y0+r,x1,y1-r,x1,y1-r+k,x1-r+k,y1,x1-r,y1,x0+r,y1,x0+r-k,y1,x0,y1-r+k,x0,y1-r,x0,y0+r,x0,y0+r-k,x0+r-k,y0,x0+r,y0)
end
local function oval(ass,cx,cy,rx,ry)
    local k=.55228475
    ass:move_to(cx-rx,cy)
    ass:bezier_curve(cx-rx,cy-ry*k,cx-rx*k,cy-ry,cx,cy-ry)
    ass:bezier_curve(cx+rx*k,cy-ry,cx+rx,cy-ry*k,cx+rx,cy)
    ass:bezier_curve(cx+rx,cy+ry*k,cx+rx*k,cy+ry,cx,cy+ry)
    ass:bezier_curve(cx-rx*k,cy+ry,cx-rx,cy+ry*k,cx-rx,cy)
end
-- One neutral surface for controls, titles, menus and status overlays.
function M.panel(ass,box,scale,visibility,radius,hover,primary,dense)
    if visibility<=0 then return end
    local x0,y0,x1,y1=box.x0,box.y0,box.x1,box.y1
    local w,h=x1-x0,y1-y0
    if w<=0 or h<=0 then return end
    local r=math.max(0,math.min(radius,w/2,h/2))
    local clip='\\clip(1,'..rounded_path(x0,y0,x1,y1,r)..')'
    local function rect(inset,offset)
        ass:round_rect_cw(x0+inset,y0+inset+offset,x1-inset,y1-inset+offset,math.max(0,r-inset))
    end
    shape(ass,'000000',.20*visibility,2.7*scale,nil,nil,function()rect(0,1.5*scale)end)
    shape(ass,'151515',(dense and .68 or primary and .42 or .32)*visibility,0,nil,nil,function()rect(0,0)end)
    if hover or primary then
        shape(ass,'FFFFFF',(hover and .14 or .08)*visibility,0,nil,nil,function()rect(0,0)end)
    end
    shape(ass,'FFFFFF',.19*visibility,math.min(w,h)*.17,nil,clip,function()
        oval(ass,x0+w*.28,y0-h*.07,w*.67,h*.34)
    end)
    shape(ass,'FFFFFF',.08*visibility,math.min(w,h)*.14,nil,clip,function()
        oval(ass,x1-w*.12,y1+h*.03,w*.43,h*.24)
    end)
    shape(ass,'FFFFFF',(primary and .48 or hover and .38 or .24)*visibility,0,.7*scale,nil,function()
        rect(.55*scale,0)
    end)
end

function M.menu(ass,box,scale,visibility,radius)
    M.panel(ass,box,scale,visibility,radius,false,false,true)
end
return M
