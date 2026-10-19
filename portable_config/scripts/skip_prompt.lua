-- A transient, clickable skip suggestion above the lower player controls.
local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
local utils=require 'mp.utils'
local assdraw=require 'mp.assdraw'
local panel_style=dofile(mp.command_native({'expand-path','~~/extensions/overlay_style.lua'}))
local overlay=mp.create_osd_overlay('ass-events')
overlay.z=1001
local cue,notice,box,hover,bound=nil,nil,nil,false,false
local notice_timer
local notice_seconds=3
local labels={intro='Заставку',recap='Ранее в сериале',credits='Титры',preview='Анонс'}
local auto_labels={intro='Заставка',recap='Ранее в сериале',credits='Титры',preview='Анонс'}
local draw
local function clicked()
    local t=mp.get_property_number('time-pos',-1)
    if cue and not cue.notice and box and t>=math.max(0,cue.start-1) and (not cue['end'] or t<cue['end']) then
        mp.commandv('script-message-to','theintrodb','skip-active',cue.kind,tostring(cue.start))
        cue=nil;notice=nil;if notice_timer then notice_timer:kill();notice_timer=nil end;draw()
    end
end
draw=function()
    local w,h=mp.get_osd_size()
    local t=mp.get_property_number('time-pos',-1)
    local active=cue and labels[cue.kind] and t>=math.max(0,cue.start-1) and (not cue['end'] or t<cue['end'])
    local visible=(active or notice) and w>0 and h>0
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
    local ass=assdraw.ass_new()
    local function render(data,y,clickable)
        local text
        if data.notice then
            local names={}
            local en=ui.language()=='en'
            local english={intro='Intro',recap='Recap',credits='Credits',preview='Preview'}
            for _,kind in ipairs(data.kinds or {data.kind})do names[#names+1]=en and english[kind] or auto_labels[kind] end
            text=(en and 'Skipped: ' or 'Пропущено: ')..table.concat(names,' · ')
        else
            text=ui.text((data.auto and 'Автопропуск: ' or 'Пропустить: ')..(data.auto and auto_labels[data.kind] or labels[data.kind]))
        end
        local _,glyphs=text:gsub('[^\128-\191]','')
        local bw=math.min(math.max(widths[data.kind],glyphs*13+32)*scale,w-20*scale)
        local x1=w-25*scale
        local area={x0=x1-bw,y0=y-40*scale,x1=x1,y1=y}
        local mouse=mp.get_property_native('mouse-pos',{})
        local over=clickable and mouse.hover~=false and mouse.x and mouse.y and mouse.x>=area.x0 and mouse.x<=area.x1 and mouse.y>=area.y0 and mouse.y<=area.y1
        if clickable then box=area;hover=over end
        panel_style.panel(ass,area,scale,mp.get_property_native('user-data/player-ui/icon-style','glass'),over,8*scale)
        ass:new_event()
        ass:append(string.format('{\\an5\\pos(%.1f,%.1f)\\fnSegoe UI Semibold\\fs%.1f\\1c&HFFFFFF&\\1a&H00&\\3c&H000000&\\3a&H90&\\4c&H000000&\\4a&H80&\\bord0\\shad0\\blur0}%s',
            (area.x0+area.x1)/2,(area.y0+area.y1)/2,25*scale,text))
    end
    box=nil;hover=false
    -- Only one panel: an upcoming action takes priority; consecutive results
    -- are combined into its final three-second confirmation.
    if active then render(cue,h-105*scale,true)
    elseif notice then render(notice,h-105*scale,false) end
    if hover and not bound then
        mp.add_forced_key_binding('MBTN_LEFT','click',function(event)
            if event.event=='up' or event.event=='press' then clicked() end
        end,{complex=true})
        bound=true
    elseif not hover and bound then mp.remove_key_binding('click');bound=false end
    overlay.res_x=w;overlay.res_y=h;overlay.data=ass.text;overlay:update()
    mp.set_property_native('user-data/skip-prompt-visible',true)
    mp.set_property_native('user-data/skip-prompt-box',box or {})
    if active and cue.id and not mp.get_property_bool('seeking',false) and not mp.get_property_bool('paused-for-cache',false)
        and not (mp.get_property_native('user-data/skip-transition',{}).active) then
        local ready=mp.get_property_native('user-data/skip-prompt-ready',{})
        if ready.id~=cue.id then mp.set_property_native('user-data/skip-prompt-ready',{id=cue.id,time=mp.get_time()}) end
    else mp.set_property_native('user-data/skip-prompt-ready',{}) end
end
local function start_notice_timer()
    if notice_timer then notice_timer:kill();notice_timer=nil end
    if not notice or mp.get_property_bool('seeking',false)
        or mp.get_property_bool('paused-for-cache',false)
        or mp.get_property_native('user-data/skip-transition',{}).active then return end
    notice_timer=mp.add_timeout(notice_seconds,function()
        notice_timer=nil
        if notice then notice=nil;draw() end
    end)
end
mp.observe_property('user-data/skip-prompt','native',function(_,data)
    if type(data)=='table' and data.clear then
        cue=nil;notice=nil
        if notice_timer then notice_timer:kill();notice_timer=nil end
    elseif type(data)=='table' and data.kind and labels[data.kind] then
        if data.notice then
            local kinds=notice and notice.kinds or {}
            local found=false;for _,kind in ipairs(kinds)do if kind==data.kind then found=true end end
            if not found then kinds[#kinds+1]=data.kind end
            notice={kind=data.kind,start=data.start,['end']=data['end'],auto=true,notice=true,kinds=kinds}
            cue=nil;start_notice_timer()
        elseif not (notice and notice.kind==data.kind and notice.start==data.start)then cue=data end
    else cue=nil end
    draw()
end)
-- Start the three-second confirmation after the seek and buffering finish.
mp.observe_property('seeking','bool',function() start_notice_timer();draw() end)
mp.observe_property('paused-for-cache','bool',function() start_notice_timer();draw() end)
mp.register_event('playback-restart',function() start_notice_timer();draw() end)
mp.observe_property('user-data/skip-transition','native',function()start_notice_timer();draw()end)
for _,name in ipairs({'time-pos','osd-dimensions','mouse-pos','user-data/mpv/console/open','user-data/interface-language','user-data/player-ui/icon-style'}) do mp.observe_property(name,'native',draw) end
mp.register_event('end-file',function() if notice_timer then notice_timer:kill();notice_timer=nil end;cue=nil;notice=nil;draw() end)
