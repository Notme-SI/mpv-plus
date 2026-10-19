-- Short video-only fade around segment skips. Never changes volume or video filters.
local M={}
function M.new()
    local assdraw=require 'mp.assdraw'
    local overlay=mp.create_osd_overlay('ass-events');overlay.z=-1
    local phase,started,target,timer,origin
    local function publish()
        mp.set_property_native('user-data/skip-transition',{active=phase~=nil,phase=phase,target=target})
    end
    local function cancel()
        if timer then timer:kill();timer=nil end
        phase=nil;target=nil;overlay:remove();publish()
    end
    local function draw(opacity)
        local w,h=mp.get_osd_size();if w<=0 or h<=0 then return end
        local ass=assdraw.ass_new();ass:new_event()
        ass:append(string.format('{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H000000&\\1a&H%02X&}',math.floor(255*(1-opacity)+.5)))
        ass:draw_start();ass:rect_cw(0,0,w,h);ass:draw_stop()
        overlay.res_x=w;overlay.res_y=h;overlay.data=ass.text;overlay:update()
    end
    local function enter(name)phase=name;started=mp.get_time();publish()end
    local function tick()
        if not phase then return end
        if mp.get_property('path','')~=origin then cancel();return end
        local elapsed=mp.get_time()-started
        if phase=='out' then
            local p=math.min(1,elapsed/.12);draw(p*p*(3-2*p))
            if p>=1 then
                enter('waiting')
                mp.commandv('seek',tostring(target),'absolute','exact')
            end
        elseif phase=='waiting' then
            -- Let the new frame arrive, but never keep a stalled stream black.
            local ready=not mp.get_property_bool('seeking',false) and not mp.get_property_bool('paused-for-cache',false)
                and math.abs(mp.get_property_number('time-pos',-100)-target)<1
            if ready or elapsed>=.7 then enter('in') else draw(1) end
        else
            local p=math.min(1,elapsed/.18);draw(1-p*p*(3-2*p))
            if p>=1 then cancel()end
        end
    end
    mp.register_event('end-file',cancel)
    mp.register_event('shutdown',cancel)
    mp.register_event('seek',function()if phase=='out'then cancel()end end)
    return {seek=function(value)
        cancel();target=value;origin=mp.get_property('path','')
        local w,h=mp.get_osd_size()
        if w<=0 or h<=0 then mp.commandv('seek',tostring(target),'absolute','exact');target=nil;return end
        enter('out');draw(0);timer=mp.add_periodic_timer(1/60,tick)
    end,cancel=cancel}
end
return M
