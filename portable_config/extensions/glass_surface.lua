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
local function arc(ass,cx,cy,r,a,b,continue)
    local steps=math.ceil(math.abs(b-a)/(.5*math.pi))
    local step=(b-a)/steps
    if continue then ass:line_to(cx+math.cos(a)*r,cy+math.sin(a)*r)
    else ass:move_to(cx+math.cos(a)*r,cy+math.sin(a)*r) end
    for i=1,steps do
        local last=a+(i-1)*step
        local next=last+step
        local k=4/3*math.tan(step/4)
        ass:bezier_curve(cx+r*(math.cos(last)-k*math.sin(last)),cy+r*(math.sin(last)+k*math.cos(last)),
            cx+r*(math.cos(next)+k*math.sin(next)),cy+r*(math.sin(next)-k*math.cos(next)),
            cx+r*math.cos(next),cy+r*math.sin(next))
    end
end
local function bevel(ass,cx,cy,r,a,b,width)
    arc(ass,cx,cy,r+width/2,a,b)
    arc(ass,cx,cy,r-width/2,b,a,true)
    ass:line_to(cx+math.cos(a)*(r+width/2),cy+math.sin(a)*(r+width/2))
end
-- Large menu panes share the buttons' soft side reflections and fine bevel.
-- Keep the centre evenly shaded so settings remain legible over bright scenes.
function M.menu(ass,box,scale,visibility,radius)
    local x0,y0,x1,y1=box.x0,box.y0,box.x1,box.y1
    local w,h=x1-x0,y1-y0
    local r=math.max(0,math.min(radius,w/2,h/2))
    local clip='\\clip(1,'..rounded_path(x0,y0,x1,y1,r)..')'
    shape(ass,'12171C',.42*visibility,0,nil,nil,function()ass:round_rect_cw(x0,y0,x1,y1,r)end)
    shape(ass,'FFFFFF',.12*visibility,math.min(w,h)*.16,nil,clip,function()
        oval(ass,x0+w*.05,y0+h*.18,w*.24,h*.38)
    end)
    shape(ass,'FCE7C3',.07*visibility,math.min(w,h)*.14,nil,clip,function()
        oval(ass,x1-w*.04,y1-h*.12,w*.20,h*.26)
    end)
    local inset=.5*scale
    shape(ass,'FFFFFF',.26*visibility,0,.75*scale,nil,function()
        ass:round_rect_cw(x0+inset,y0+inset,x1-inset,y1-inset,math.max(0,r-inset))
    end)
end
function M.panel(ass,box,scale,visibility,radius,hover)
    if visibility<=0 then return end
    local x0,y0,x1,y1=box.x0,box.y0,box.x1,box.y1
    local w,h=x1-x0,y1-y0
    local r=math.min(radius,w/2,h/2)
    local cx,cy=(x0+x1)/2,(y0+y1)/2
    local circular=math.abs(w-h)<scale*2 and r>=h*.45
    if not circular then
        -- A single even pane avoids clipped glow bands on shallow headers.
        -- Draw the rim inside the pane so no reflection bleeds above/below it.
        shape(ass,'12171C',(hover and .28 or .24)*visibility,0,nil,nil,function()
            ass:round_rect_cw(x0,y0,x1,y1,r)
        end)
        local inset=.4*scale
        shape(ass,'FFFFFF',.24*visibility,0,.6*scale,nil,function()
            ass:round_rect_cw(x0+inset,y0+inset,x1-inset,y1-inset,math.max(0,r-inset))
        end)
        return
    end
    local path=rounded_path(x0,y0,x1,y1,r)
    local clip='\\clip(1,'..path..')'
    local function rect(a,b,c,d,rad) ass:round_rect_cw(a,b,c,d,rad) end
    -- Clear centre: the scene supplies the colour rather than a grey paint layer.
    shape(ass,'000000',.18*visibility,2.4*scale,nil,nil,function() rect(x0,y0+1.5*scale,x1,y1+1.5*scale,r) end)
    shape(ass,hover and '393124' or '231E17',(hover and .16 or .08)*visibility,0,nil,nil,function() rect(x0,y0,x1,y1,r) end)
    -- Broad, soft reflections occupy the sides, never a horizontal top stripe.
    shape(ass,'FFFFFF',(hover and .28 or .21)*visibility,h*.20,nil,clip,function()
        oval(ass,x0+w*.14,y0+h*.19,math.min(w*.28,h*.38),h*.30)
    end)
    shape(ass,'FCE7C3',.14*visibility,h*.16,nil,clip,function()
        oval(ass,x1-w*.08,y1-h*.12,math.min(w*.25,h*.34),h*.22)
    end)
    shape(ass,'FFFFFF',.05*visibility,0,.55*scale,nil,function() rect(x0,y0,x1,y1,r) end)
    if circular then
        -- Continuous Bezier curves avoid segmented/dotted edges at small sizes.
        -- Nested blurred arcs feather the light along the bevel.
        for i=0,4 do
            local span=2.7-i*.35
            shape(ass,'FFFFFF',.16*(hover and 1.2 or 1)*visibility,.55*scale,nil,nil,function()
                bevel(ass,cx,cy,r-.15*scale,-2.36-span/2,-2.36+span/2,.9*scale)
            end)
            local span=1.85-i*.26
            shape(ass,'FCE7C3',.11*visibility,.5*scale,nil,nil,function()
                bevel(ass,cx,cy,r-.15*scale,.78-span/2,.78+span/2,.9*scale)
            end)
        end
    end
end
return M
