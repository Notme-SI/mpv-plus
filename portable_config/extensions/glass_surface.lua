-- Shared ASS glass surface for uosc and skip prompts. No video readback or filters.
local M={}
local function alpha(opacity)
    return math.floor(255*(1-math.max(0,math.min(1,opacity)))+.5)
end
local function shape(ass,color,opacity,blur,border,clip,draw)
    ass:new_event()
    ass:append(string.format('{\\rDefault\\an7\\pos(0,0)\\alpha&H00&\\bord%.2f\\shad0\\blur%.2f\\1c&H%s&\\1a&H%02X&\\3c&H%s&\\3a&H%02X&%s}',
        border or 0,blur or 0,color,alpha(border and border>0 and 0 or opacity),color,alpha(opacity),clip or ''))
    -- Eight drawing units per OSD pixel keep small curves and thin rims smooth.
    ass:append('{\\p4}');draw();ass:draw_stop()
end
local function rounded_path(x0,y0,x1,y1,r,reverse)
    x0,y0,x1,y1,r=x0*8,y0*8,x1*8,y1*8,r*8
    r=math.max(0,math.min(r,(x1-x0)/2,(y1-y0)/2))
    local k=r*.55228475
    if reverse then
        return string.format('m %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f',
            x0+r,y0,x0+r-k,y0,x0,y0+r-k,x0,y0+r,x0,y1-r,x0,y1-r+k,x0+r-k,y1,x0+r,y1,x1-r,y1,x1-r+k,y1,x1,y1-r+k,x1,y1-r,x1,y0+r,x1,y0+r-k,x1-r+k,y0,x1-r,y0)
    end
    return string.format('m %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f',
        x0+r,y0,x1-r,y0,x1-r+k,y0,x1,y0+r-k,x1,y0+r,x1,y1-r,x1,y1-r+k,x1-r+k,y1,x1-r,y1,x0+r,y1,x0+r-k,y1,x0,y1-r+k,x0,y1-r,x0,y0+r,x0,y0+r-k,x0+r-k,y0,x0+r,y0)
end
-- Filled opposing paths avoid libass's subpixel stroke expansion. The small
-- edge blur is in screen pixels, so it stays consistent at Full HD and 4K.
function M.rim(ass,box,scale,opacity,radius)
    local thickness=math.max(.9,.85*scale)
    shape(ass,'FFFFFF',opacity,.38,0,nil,function()
        ass:append(rounded_path(box.x0,box.y0,box.x1,box.y1,radius))
        ass:append(rounded_path(box.x0+thickness,box.y0+thickness,box.x1-thickness,box.y1-thickness,
            math.max(0,radius-thickness),true))
    end)
end
local function oval(ass,cx,cy,rx,ry)
    cx,cy,rx,ry=cx*8,cy*8,rx*8,ry*8
    local k=.55228475
    ass:move_to(cx-rx,cy)
    ass:bezier_curve(cx-rx,cy-ry*k,cx-rx*k,cy-ry,cx,cy-ry)
    ass:bezier_curve(cx+rx*k,cy-ry,cx+rx,cy-ry*k,cx+rx,cy)
    ass:bezier_curve(cx+rx,cy+ry*k,cx+rx*k,cy+ry,cx,cy+ry)
    ass:bezier_curve(cx-rx*k,cy+ry,cx-rx,cy+ry*k,cx-rx,cy)
end
function M.solid(ass,box,scale,visibility,radius,hover,primary)
    local function rect(inset)
        ass:append(rounded_path(box.x0+inset,box.y0+inset,box.x1-inset,box.y1-inset,math.max(0,radius-inset)))
    end
    shape(ass,'000000',(hover and .76 or primary and .66 or .52)*visibility,0,nil,nil,function()rect(0)end)
    M.rim(ass,box,scale,(primary and .50 or hover and .44 or .32)*visibility,radius)
end
function M.disc(ass,x,y,r,color,opacity)
    shape(ass,color,opacity,0,nil,nil,function()ass:append(rounded_path(x-r,y-r,x+r,y+r,r))end)
end
-- Lucide closed-caption (ISC): two round C strokes in a 20×14 frame.
-- Render as paths so its stroke stays as light as the other toolbar icons.
function M.caption(ass,x,y,size,color,opacity,clip)
    local u=size/28
    local ox,oy=x-12*u,y-12*u
    local function arc(cx,cy,r,a,b,move)
        local n=math.ceil(math.abs(b-a)/(math.pi/2))
        local step=(b-a)/n
        if move then ass:append(string.format('m %.3f %.3f ',(cx+r*math.cos(a))*8,(cy+r*math.sin(a))*8)) end
        for i=1,n do
            local t=a+(i-1)*step
            local last=t+step
            local k=4/3*math.tan(step/4)
            ass:append(string.format('b %.3f %.3f %.3f %.3f %.3f %.3f ',
                (cx+r*(math.cos(t)-k*math.sin(t)))*8,(cy+r*(math.sin(t)+k*math.cos(t)))*8,
                (cx+r*(math.cos(last)+k*math.sin(last)))*8,(cy+r*(math.sin(last)-k*math.cos(last)))*8,
                (cx+r*math.cos(last))*8,(cy+r*math.sin(last))*8))
        end
    end
    shape(ass,color,opacity,.08*u,.85*u,clip,function()
        ass:append(rounded_path(ox+2*u,oy+5*u,ox+22*u,oy+19*u,2*u))
    end)
    local start=-math.acos(1/3)
    local finish=-2*math.pi-start
    for _,center in ipairs({9,16}) do
        local cx,cy=ox+center*u,oy+12*u
        shape(ass,color,opacity,0,nil,clip,function()
            arc(cx,cy,3.85*u,start,finish,true)
            ass:append(string.format('l %.3f %.3f ',(cx+2.15*u*math.cos(finish))*8,(cy+2.15*u*math.sin(finish))*8))
            arc(cx,cy,2.15*u,finish,start)
        end)
        for _,angle in ipairs({start,finish}) do
            shape(ass,color,opacity,0,nil,clip,function()
                local px,py=cx+3*u*math.cos(angle),cy+3*u*math.sin(angle)
                ass:append(rounded_path(px-.85*u,py-.85*u,px+.85*u,py+.85*u,.85*u))
            end)
        end
    end
end
-- One neutral surface for controls, titles, menus and status overlays.
function M.panel(ass,box,scale,visibility,radius,hover,primary,dense)
    if visibility<=0 then return end
    local x0,y0,x1,y1=box.x0,box.y0,box.x1,box.y1
    local w,h=x1-x0,y1-y0
    if w<=0 or h<=0 then return end
    local r=math.max(0,math.min(radius,w/2,h/2))
    local clip='\\clip(4,'..rounded_path(x0,y0,x1,y1,r)..')'
    local function rect(inset,offset)
        ass:append(rounded_path(x0+inset,y0+inset+offset,x1-inset,y1-inset+offset,math.max(0,r-inset)))
    end
    -- Clear glass: the video supplies the colour. Keep most of the contrast
    -- in the rim instead of stacking an opaque grey fill over the picture.
    shape(ass,'000000',.07*visibility,1.6*scale,nil,nil,function()rect(0,scale)end)
    shape(ass,'080808',(dense and .38 or primary and .15 or .11)*visibility,0,nil,nil,function()rect(0,0)end)
    if hover or primary then
        shape(ass,'FFFFFF',(hover and .06 or .025)*visibility,0,nil,nil,function()rect(0,0)end)
    end
    shape(ass,'FFFFFF',.12*visibility,math.min(w,h)*.10,nil,clip,function()
        oval(ass,x0+w*.30,y0-h*.10,w*.64,h*.23)
    end)
    shape(ass,'FFFFFF',.06*visibility,math.min(w,h)*.10,nil,clip,function()
        oval(ass,x1-w*.12,y1+h*.08,w*.40,h*.19)
    end)
    M.rim(ass,box,scale,(primary and .56 or hover and .52 or .40)*visibility,r)
end

function M.menu(ass,box,scale,visibility,radius)
    M.panel(ass,box,scale,visibility,radius,false,false,true)
end
return M
