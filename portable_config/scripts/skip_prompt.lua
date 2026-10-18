-- A transient, clickable skip suggestion above the lower player controls.
local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
local utils=require 'mp.utils'
local assdraw=require 'mp.assdraw'
local panel_style=dofile(mp.command_native({'expand-path','~~/extensions/overlay_style.lua'}))
local overlay=mp.create_osd_overlay('ass-events')
overlay.z=1001
local cue,box,hover,bound=nil,nil,false,false
local notice_timer
local notice_seconds=3
local labels={intro='Заставку',recap='Ранее в сериале',credits='Титры',preview='Анонс'}
local auto_labels={intro='Заставки',recap='Ранее в сериале',credits='Титр',preview='Анонса'}
local draw
local function clicked()
    local t=mp.get_property_number('time-pos',-1)
    if cue and not cue.notice and box and t>=math.max(0,cue.start-1) and (not cue['end'] or t<cue['end']) then
        mp.commandv('script-message-to','theintrodb','skip-active',cue.kind,tostring(cue.start))
        cue=nil;draw()
    end
end
draw=function()
    local w,h=mp.get_osd_size()
    local t=mp.get_property_number('time-pos',-1)
    local visible=cue and labels[cue.kind] and w>0 and h>0 and (cue.notice or (t>=math.max(0,cue.start-1) and (not cue['end'] or t<cue['end'])))
        and not mp.get_property_bool('idle-active',true)
        and not mp.get_property_bool('user-data/mpv/console/open',false)
    if not visible then
        box=nil;overlay:remove()
        if bound then mp.remove_key_binding('click');bound=false end
        mp.set_property_native('user-data/skip-prompt-visible',false)
        mp.set_property_native('user-data/skip-prompt-ready',{})
        return
    end
    local scale=math.max(0.65,math.min(2,h/720))
    local widths=ui.language()=='en' and {intro=165,recap=180,credits=195,preview=195} or {intro=280,recap=360,credits=245,preview=245}
    local bw=math.min(widths[cue.kind]*scale,w-20*scale)
    local bh=40*scale
    local x1=w-25*scale
    local y1=h-105*scale
    box={x0=x1-bw,y0=y1-bh,x1=x1,y1=y1}
    local mouse=mp.get_property_native('mouse-pos',{})
    hover=mouse.hover~=false and mouse.x and mouse.y and mouse.x>=box.x0 and mouse.x<=box.x1 and mouse.y>=box.y0 and mouse.y<=box.y1
    if hover and not bound then
        mp.add_forced_key_binding('MBTN_LEFT','click',function(event)
            if event.event=='up' or event.event=='press' then clicked() end
        end,{complex=true})
        bound=true
    elseif not hover and bound then mp.remove_key_binding('click');bound=false end
    local ass=assdraw.ass_new()
    local radius=8*scale
    panel_style.panel(ass,box,scale,mp.get_property_native('user-data/player-ui/icon-style','glass'),hover,radius)
    ass:new_event()
    local prefix=cue.auto and 'Автопропуск: ' or 'Пропустить: '
    local label=cue.auto and auto_labels[cue.kind] or labels[cue.kind]
    ass:append(string.format('{\\an5\\pos(%.1f,%.1f)\\fnSegoe UI Semibold\\fs%.1f\\1c&HFFFFFF&\\1a&H00&\\3c&H000000&\\3a&H90&\\4c&H000000&\\4a&H80&\\bord%.2f\\shad%.2f\\blur%.2f}%s',
        (box.x0+box.x1)/2,(box.y0+box.y1)/2,25*scale,0,0,0,ui.text(prefix..label)))
    overlay.res_x=w;overlay.res_y=h;overlay.data=ass.text;overlay:update()
    mp.set_property_native('user-data/skip-prompt-visible',true)
    mp.set_property_native('user-data/skip-prompt-box',box)
    if not cue.notice and cue.id then
        local ready=mp.get_property_native('user-data/skip-prompt-ready',{})
        if ready.id~=cue.id then mp.set_property_native('user-data/skip-prompt-ready',{id=cue.id,time=mp.get_time()}) end
    end
end
local function start_notice_timer()
    if notice_timer then notice_timer:kill();notice_timer=nil end
    if not (cue and cue.notice) or mp.get_property_bool('seeking',false)
        or mp.get_property_bool('paused-for-cache',false) then return end
    notice_timer=mp.add_timeout(notice_seconds,function()
        notice_timer=nil
        if cue and cue.notice then cue=nil;draw() end
    end)
end
mp.observe_property('user-data/skip-prompt','native',function(_,data)
    if cue and cue.notice and not (type(data)=='table' and (data.notice or data.clear)) then return end
    cue=type(data)=='table' and data.kind and data or nil
    if notice_timer then notice_timer:kill();notice_timer=nil end
    if cue and cue.notice then
        start_notice_timer()
    end
    draw()
end)
-- Start the three-second confirmation after the seek and buffering finish.
mp.observe_property('seeking','bool',function() start_notice_timer();draw() end)
mp.observe_property('paused-for-cache','bool',function() start_notice_timer();draw() end)
mp.register_event('playback-restart',function() start_notice_timer();draw() end)
for _,name in ipairs({'time-pos','osd-dimensions','mouse-pos','user-data/mpv/console/open','user-data/interface-language','user-data/player-ui/icon-style'}) do mp.observe_property(name,'native',draw) end
mp.register_event('end-file',function() if notice_timer then notice_timer:kill();notice_timer=nil end;cue=nil;draw() end)
