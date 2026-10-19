-- The automatic panel uses the same metrics as the detailed network menu.
local M={}
function M.new(ui)
    local assdraw=require 'mp.assdraw'
    local overlay=mp.create_osd_overlay('ass-events');overlay.z=1100
    local function metric(value,unit,precision,signed)
        value=tonumber(value)
        if not value or value~=value or math.abs(value)==math.huge or value<0 and not signed then return ui.text('Нет данных') end
        return string.format('%.'..(precision or 1)..'f',value)..(unit and ' '..unit or '')
    end
    local function mb(value) return value and value/1048576 end
    return {hide=function()overlay:remove()end,draw=function(data)
        local w,h=mp.get_osd_size();if w<=0 or h<=0 then overlay:remove();return end
        local en,scale=ui.language()=='en',math.max(.65,math.min(2,h/720))
        local second,megabyte,speed=en and 's' or 'с',en and 'MiB' or 'МБ',en and 'MiB/s' or 'МБ/с'
        local loader=data.loader
        local rows={
            {en and 'Source' or 'Источник',data.torrent and 'TorrServer' or 'HTTP'},
            {en and 'Video buffered' or 'Запас видео',metric(data.seconds,second)},
            {en and 'Player buffer (ahead)' or 'Буфер плеера вперёд',metric(mb(data.forward_bytes),megabyte)},
            {en and 'Player buffer (back)' or 'Буфер плеера назад',metric(mb(data.back_bytes),megabyte)},
            {en and 'Player read speed' or 'Скорость чтения',metric(mb(data.speed),speed)},
            {en and 'Buffer progress' or 'Заполнение буфера',metric(data.progress,'%',0)},
        }
        if data.torrent then
            local s=data.stat or {}
            rows[#rows+1]={'TorrServer',s.unavailable and not loader and (en and 'No response' or 'Нет ответа')
                or (s.download_speed or loader) and (en and 'Connected' or 'Подключён') or (en and 'Waiting for data' or 'Ожидание данных')}
            rows[#rows+1]={en and 'Server download' or 'Загрузка TorrServer',s.download_speed and metric(mb(s.download_speed),speed) or loader and loader.speed or metric(nil)}
            rows[#rows+1]={en and 'Server cache' or 'Кеш TorrServer',s.capacity and metric(mb(s.filled))..' / '..metric(mb(s.capacity),megabyte)
                or loader and (en and loader.cache or loader.cache:gsub(' GB',' ГБ')) or metric(nil)}
            rows[#rows+1]={en and 'Peers / seeders' or 'Пиры / сиды',s.active_peers and metric(s.active_peers,nil,0)..' / '..metric(s.connected_seeders,nil,0)
                or loader and loader.peers or metric(nil)}
            if loader and loader.extra~='' then
                local extra=loader.extra
                if not en then extra=extra:gsub('Connected ','Подключено '):gsub(' external files',' внешних файлов'):gsub('Errors:','Ошибки:') end
                rows[#rows+1]={en and 'External files' or 'Внешние дорожки',extra}
            end
        end
        rows[#rows+1]={en and 'Dropped frames' or 'Пропущено кадров',metric(data.dropped,nil,0)}
        rows[#rows+1]={en and 'Audio/video sync' or 'Разница аудио и видео',metric(data.avsync,second,3,true)}
        local x1=w-18*scale
        local width=math.min(w-24*scale,530*scale)
        local x0,y=x1-width,62*scale
        local name_height=loader and loader.file and 27 or 0
        local ass=assdraw.ass_new();ass:new_event();ass:append('{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H151515&\\1a&H20&}')
        ass:draw_start();ass:round_rect_cw(x0,y,x1,y+(90+name_height+#rows*27)*scale,9*scale);ass:draw_stop()
        local function text(value,x,yy,align,color,size)
            value=tostring(value):gsub('\\','\\\\'):gsub('{','\\{'):gsub('}','\\}')
            ass:new_event();ass:append(string.format('{\\an%d\\pos(%.1f,%.1f)\\fnSegoe UI\\fs%.1f\\1c&H%s&\\bord0\\shad0}%s',align,x,yy,(size or 21)*scale,color,value))
        end
        text(data.torrent and (en and 'TORRSERVER AND PLAYER' or 'TORRSERVER И ПЛЕЕР') or (en and 'Network and buffer' or 'Сеть и буфер'),x0+16*scale,y+12*scale,7,'FFFFFF',22)
        local states={opening=en and 'Opening stream' or 'Открытие потока',seeking=en and 'Seeking' or 'Перемотка',buffering=en and 'Buffering' or 'Буферизация'}
        text(states[data.reason] or states.buffering,x0+16*scale,y+41*scale,7,'BDBDBD',17)
        if name_height>0 then
            local chars={};for c in loader.file:gmatch('[%z\1-\127\194-\244][\128-\191]*')do if #chars>=46 then break end;chars[#chars+1]=c end
            text(table.concat(chars)..(#table.concat(chars)<#loader.file and '…' or ''),x0+16*scale,y+65*scale,7,'BDBDBD',17)
        end
        for i,row in ipairs(rows)do
            text(row[1],x0+16*scale,y+(55+name_height+i*27)*scale,7,'BBBBBB')
            text(row[2],x1-16*scale,y+(55+name_height+i*27)*scale,9,'FFFFFF')
        end
        overlay.res_x=w;overlay.res_y=h;overlay.data=ass.text;overlay:update()
    end}
end
return M
