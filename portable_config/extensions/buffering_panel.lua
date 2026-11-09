-- Compact loading diagnostics. The full values remain in Network and buffer.
local M={}
local style=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/overlay_style.lua')
local measure=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/text_metrics.lua')
local glyphs=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/lucide_glyphs.lua')
function M.new(ui)
    local assdraw=require 'mp.assdraw'
    local metrics=measure.new()
    local overlay=mp.create_osd_overlay('ass-events');overlay.z=1100
    local function valid(n) n=tonumber(n);return n and n==n and math.abs(n)<math.huge and n>=0 and n or nil end
    local function metric(n,unit,precision)
        n=tonumber(n)
        if not n or n~=n or math.abs(n)==math.huge or n<0 then return '—' end
        return string.format('%.'..(precision or 1)..'f',n)..(unit and ' '..unit or '')
    end
    local function mb(n)return valid(n) and n/1048576 end
    local function join(parts)
        local out={};for _,v in ipairs(parts)do if v and v~='' then out[#out+1]=v end end
        return table.concat(out,' · ')
    end
    return {hide=function()overlay:remove()end,draw=function(data)
        local w,h=mp.get_osd_size()
        if w<100 or h<100 or data.show_buffer==false and data.show_statistics==false then overlay:remove();return end
        local en,scale=ui.language()=='en',math.max(.65,math.min(2,h/720))
        local second,megabyte,speed=en and 's' or 'с',en and 'MiB' or 'МБ',en and 'Mbps' or 'Мбит/с'
        local font='Segoe UI Semibold'
        local ass=assdraw.ass_new()
        local function box(x,y,width,height,radius)
            style.panel(ass,{x0=x,y0=y,x1=x+width,y1=y+height},scale,data.icon_style or 'glass',false,radius or 7*scale)
        end
        local function text(value,x,y,size,width)
            value=measure.escape(value)
            ass:new_event();ass:append(string.format('{\\rDefault\\an7\\pos(%.1f,%.1f)\\fnSegoe UI Semibold\\fs%.1f\\alpha&H00&\\1c&HFFFFFF&\\bord0\\shad1\\4c&H000000&\\4a&H20&\\q2%s}%s',
                x,y,size*scale,string.format('\\clip(%d,%d,%d,%d)',math.floor(x),math.floor(y),math.floor(x+width),math.ceil(y+size*scale*1.5)),value))
        end
        local function icon(name,x,y,size)
            ass:new_event()
            ass:append(string.format('{\\rDefault\\an5\\pos(%.1f,%.1f)\\fnlucide\\fs%.1f\\alpha&H00&\\1c&HFFFFFF&\\bord0\\shad0}%s',
                x,y,size*scale,glyphs[name]))
        end
        local function rate(value)
            if valid(value) then return metric(value/1000000,speed) end
        end
        local seconds=math.floor((valid(data.seconds) or 0)+.5)
        local reserve=seconds>0 and metric(seconds,second,0) or nil
        local read=rate(valid(data.speed) and data.speed*8)
        local bitrate=rate(data.bitrate)
        local s,loader=data.stat or {},data.loader
        local transfer=data.torrent and (rate(valid(s.download_speed) and s.download_speed*8) or loader and loader.speed)
        if transfer=='' then transfer=nil end
        if data.show_statistics~=false then
            local rows={}
            local function row(value) if value and value~='' then rows[#rows+1]=value end end
            local headers={opening=en and 'Opening stream' or 'Открытие потока',seeking=en and 'Seeking' or 'Перемотка',buffering=en and 'Waiting for data' or 'Ожидание данных'}
            local header=headers[data.reason] or (en and 'Loading' or 'Загрузка')
            local maximum=math.min(w-28*scale,375*scale)
            local content=maximum-28*scale
            local buffered=join({reserve or '',data.forward_bytes and metric(mb(data.forward_bytes),megabyte,0) or ''})
            row((en and 'Player buffer: ' or 'Буфер плеера: ')..(buffered~='' and buffered or '—'))
            if read then row((en and 'Player reads: ' or 'Чтение mpv+: ')..read) end
            if bitrate then row((en and 'Average file bitrate: ' or 'Средний битрейт файла: ')..bitrate) end
            if data.torrent then
                if transfer then row((en and 'Torrent download: ' or 'Загрузка торрента: ')..transfer) end
                local cache=valid(s.capacity) and metric(mb(s.filled),nil,0)..' / '..metric(mb(s.capacity),megabyte,0)
                    or loader and type(loader.cache)=='string' and (en and loader.cache or loader.cache:gsub(' GB',' ГБ'))
                if cache and cache~='' then row((en and 'Server cache: ' or 'Кеш сервера: ')..cache) end
                local peers=valid(s.active_peers) and metric(s.active_peers,nil,0)..' / '..metric(s.connected_seeders,nil,0)
                    or loader and loader.peers
                if peers and peers~='' then row((en and 'Peers / seeds: ' or 'Пиры / сиды: ')..peers) end
                if s.unavailable and not transfer then
                    row((s.http_status==401 or s.http_status==403) and (en and 'Server sign-in required' or 'Сервер требует авторизацию')
                        or (en and 'Server statistics unavailable' or 'Статистика сервера недоступна'))
                end
                if loader and type(loader.extra)=='string' and loader.extra~='' and not loader.extra:match('^Connected %d+ external files$') then
                    row(en and loader.extra or loader.extra:gsub('Connected ','Подключено '):gsub(' external files',' внешних файлов'):gsub('Errors:','Ошибки:'))
                end
            end
            local video=(data.media or {}).video
            if video then
                local decoder=data.hwdec=='no' and (en and 'Software decode' or 'Программный декодер') or data.hwdec or ''
                row(join({video.width and video.height and (video.width..'×'..video.height) or '',video.codec or '',decoder}))
            end
            local dropped=valid(data.dropped)
            if dropped and dropped>0 then row((en and 'Dropped frames: ' or 'Пропущено кадров: ')..metric(dropped,nil,0)) end
            local width=math.min(maximum,math.max(225*scale,metrics.width(header,18*scale,font)+56*scale))
            for i,item in ipairs(rows) do
                local value=metrics.fit(item,content,17*scale,font)
                rows[i]=value
                width=math.max(width,metrics.width(value,17*scale,font)+28*scale)
            end
            width=math.min(maximum,width)
            local x,y=w-width-14*scale,math.min(80*scale,h*.11)
            box(x,y,width,(48+#rows*23)*scale,14*scale)
            icon('speed',x+23*scale,y+22*scale,20)
            text(header,x+39*scale,y+12*scale,18,width-52*scale)
            for i,item in ipairs(rows) do text(item,x+14*scale,y+(17+i*23)*scale,17,width-28*scale) end
        end
        if data.show_buffer~=false then
            local download=transfer or read or rate(0)
            local label=download
            local width=math.min(w-16*scale,metrics.width(label,15*scale,font)+34*scale)
            local y=h/2+32*scale
            local x=(w-width)/2
            box(x,y,width,26*scale,13*scale)
            icon('arrow_down_to_line',x+12*scale,y+13*scale,15)
            text(metrics.fit(label,width-30*scale,15*scale,font),x+23*scale,y+4*scale,15,width-30*scale)
        end
        overlay.res_x=w;overlay.res_y=h;overlay.data=ass.text;overlay:update()
    end}
end
return M
