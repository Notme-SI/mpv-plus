local M={}
function M.new(ui)
    local assdraw=require 'mp.assdraw'
    local overlay=mp.create_osd_overlay('ass-events');overlay.z=1100
    local function metric(value,unit)
        value=tonumber(value)
        if not value or value<0 or value~=value or value==math.huge then return ui.text('Нет данных') end
        return string.format('%.1f%s',value,unit and ' '..unit or '')
    end
    return {hide=function()overlay:remove()end,draw=function(data)
        local w,h=mp.get_osd_size();if w<=0 or h<=0 then overlay:remove();return end
        local en,scale=ui.language()=='en',math.max(.65,math.min(2,h/720))
        local rows={{en and 'Video buffered' or 'Запас видео',metric(data.seconds,en and 's' or 'с')},
            {en and 'Player read' or 'Чтение плеера',metric(data.speed and data.speed/1048576,en and 'MiB/s' or 'МБ/с')}}
        if data.torrent then
            local s=data.stat or {}
            rows[#rows+1]={en and 'Server download' or 'Загрузка сервера',metric(s.download_speed and s.download_speed/1048576,en and 'MiB/s' or 'МБ/с')}
            rows[#rows+1]={en and 'Server cache' or 'Кеш сервера',metric(s.filled and s.filled/1048576)..' / '..metric(s.capacity and s.capacity/1048576,en and 'MiB' or 'МБ')}
            rows[#rows+1]={en and 'Peers / seeders' or 'Пиры / сиды',metric(s.active_peers)..' / '..metric(s.connected_seeders)}
        end
        local x1,x0,y=w-20*scale,math.max(5*scale,w-410*scale),20*scale
        local ass=assdraw.ass_new();ass:new_event();ass:append('{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H151515&\\1a&H30&}')
        ass:draw_start();ass:round_rect_cw(x0,y,x1,y+(55+#rows*27)*scale,9*scale);ass:draw_stop()
        local function text(value,x,yy,align,color)
            ass:new_event();ass:append(string.format('{\\an%d\\pos(%.1f,%.1f)\\fnSegoe UI\\fs%.1f\\1c&H%s&\\bord0\\shad0}%s',align,x,yy,18*scale,color,value))
        end
        text(en and 'BUFFERING' or 'БУФЕРИЗАЦИЯ',x0+12*scale,y+12*scale,7,'FFFFFF')
        for i,row in ipairs(rows)do text(row[1],x0+12*scale,y+(24+i*27)*scale,7,'BBBBBB');text(row[2],x1-12*scale,y+(24+i*27)*scale,9,'FFFFFF')end
        overlay.res_x=w;overlay.res_y=h;overlay.data=ass.text;overlay:update()
    end}
end
return M
