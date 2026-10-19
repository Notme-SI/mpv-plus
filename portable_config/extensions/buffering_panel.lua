-- Compact loading diagnostics. The full values remain in Network and buffer.
local M={}
local info=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/media_info.lua')
function M.new(ui)
    local assdraw=require 'mp.assdraw'
    local overlay=mp.create_osd_overlay('ass-events');overlay.z=1100
    local function valid(n) n=tonumber(n);return n and n==n and math.abs(n)<math.huge and n>=0 and n or nil end
    local function metric(n,unit,precision,signed)
        n=tonumber(n)
        if not n or n~=n or math.abs(n)==math.huge or n<0 and not signed then return '—' end
        return string.format('%.'..(precision or 1)..'f',n)..(unit and ' '..unit or '')
    end
    local function mb(n)return valid(n) and n/1048576 end
    local function join(parts)
        local out={};for _,v in ipairs(parts)do if v and v~='' then out[#out+1]=v end end
        return table.concat(out,' · ')
    end
    local function chars(s)
        local count=0;for _ in s:gmatch('[%z\1-\127\194-\244][\128-\191]*')do count=count+1 end;return count
    end
    return {hide=function()overlay:remove()end,draw=function(data)
        local w,h=mp.get_osd_size()
        if w<=0 or h<=0 or data.show_buffer==false and data.show_statistics==false then overlay:remove();return end
        local en,scale=ui.language()=='en',math.max(.65,math.min(2,h/720))
        local second,megabyte,speed=en and 's' or 'с',en and 'MiB' or 'МБ',en and 'MiB/s' or 'МБ/с'
        local ass=assdraw.ass_new()
        local function box(x,y,width,height)
            ass:new_event();ass:append('{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H181818&\\1a&H72&}')
            ass:draw_start();ass:round_rect_cw(x,y,x+width,y+height,8*scale);ass:draw_stop()
        end
        local function text(value,x,y,size,color,width)
            value=tostring(value):gsub('\\','\\\\'):gsub('{','\\{'):gsub('}','\\}')
            ass:new_event();ass:append(string.format('{\\an7\\pos(%.1f,%.1f)\\fnSegoe UI\\fs%.1f\\1c&H%s&\\bord0.5\\3c&H101010&\\shad0\\q2%s}%s',
                x,y,size*scale,color or 'FFFFFF',width and string.format('\\clip(%d,%d,%d,%d)',math.floor(x),math.floor(y),math.floor(x+width),math.ceil(y+size*scale*1.5))or'',value))
        end
        if data.show_statistics~=false then
            local rows={}
            local function row(value,muted)if value~=''then rows[#rows+1]={value,muted}end end
            local media=data.media or {};local video,audio=media.video,media.audio
            if video then
                row(join({video.width and video.height and (video.width..'×'..video.height) or '',video.codec or '',video.profile or ''}))
                if data.hwdec and data.hwdec~='' then
                    row(data.hwdec=='no' and (en and 'Software decoding' or 'Программное декодирование')
                        or (en and 'Hardware' or 'Аппаратное')..' · '..data.hwdec,true)
                end
                row(join({video.fps and metric(video.fps,'fps',3) or '',data.display_fps and (en and 'Display ' or 'Экран ')..metric(data.display_fps,en and 'Hz' or 'Гц',2) or ''}),true)
            end
            if audio then
                local layout=({stereo='2.0',mono='1.0'})[audio.channels] or audio.channels
                local channels=layout or (audio.channel_count and tostring(audio.channel_count)..' ch') or ''
                row(join({audio.codec or '',channels,info.language(audio.language) or '',audio.samplerate and metric(audio.samplerate/1000,'kHz',1) or '',audio.bitrate and metric(audio.bitrate/1000,'kbps',0) or ''}))
                if audio.decoder then row((en and 'Audio decoder' or 'Декодер аудио')..' · '..audio.decoder,true)end
            end
            row((en and 'Read ' or 'Чтение ')..metric(mb(data.speed),speed)..' · '..(en and 'Back ' or 'Назад ')..metric(mb(data.back_bytes),megabyte),true)
            if data.torrent then
                local s,loader=data.stat or {},data.loader
                row('TorrServer · '..(s.download_speed and metric(mb(s.download_speed),speed)
                    or loader and loader.speed or s.unavailable and (en and 'No response' or 'Нет ответа') or '—'))
                row((en and 'Cache ' or 'Кеш TorrServer ')..(s.capacity and metric(mb(s.filled))..' / '..metric(mb(s.capacity),megabyte)
                    or loader and (en and loader.cache or loader.cache:gsub(' GB',' ГБ')) or '—'),true)
                row((en and 'Peers / seeds ' or 'Пиры / сиды ')..(s.active_peers and metric(s.active_peers,nil,0)..' / '..metric(s.connected_seeders,nil,0)
                    or loader and loader.peers or '—'),true)
                if loader and loader.extra and loader.extra~='' then
                    row(en and loader.extra or loader.extra:gsub('Connected ','Подключено '):gsub(' external files',' внешних файлов'):gsub('Errors:','Ошибки:'),true)
                end
            end
            row((en and 'Dropped ' or 'Потери ')..metric(data.dropped,nil,0)..' · A/V '..metric(data.avsync,second,3,true),true)
            local width=math.min(w-24*scale,398*scale)
            local x,y=w-width-18*scale,100*scale
            box(x,y,width,(43+#rows*23)*scale)
            local states={opening=en and 'Opening stream' or 'Открытие потока',seeking=en and 'Seeking' or 'Перемотка',buffering=en and 'Buffering' or 'Буферизация'}
            text((states[data.reason] or (en and 'Playback statistics' or 'Статистика воспроизведения'))..' · '..(data.torrent and 'TorrServer' or 'HTTP'),x+13*scale,y+10*scale,16,'D5D5D5',width-26*scale)
            for i,rowdata in ipairs(rows)do text(rowdata[1],x+13*scale,y+(18+i*23)*scale,17,rowdata[2] and 'C4C4C4' or 'FFFFFF',width-26*scale)end
        end
        if data.show_buffer~=false then
            local seconds=valid(data.seconds)
            local target=data.profile and valid(data.profile.seconds)
            local summary=(en and 'Buffer ' or 'Буфер ')..metric(seconds,second)
            if seconds and target and target>0 then
                summary=(en and 'Buffer ' or 'Буфер ')..metric(seconds,nil)..' / '..metric(target,second,0)
                    ..' ('..metric(math.min(100,seconds/target*100),'%',0)..')'
            end
            summary=summary..' · '..(en and 'ahead ' or 'вперёд ')..metric(mb(data.forward_bytes),megabyte)
            local width=math.min(w-36*scale,(chars(summary)*8.7+26)*scale)
            local y=math.max(20*scale,h-139*scale)
            box(18*scale,y,width,32*scale)
            text(summary,31*scale,y+5*scale,17,'FFFFFF',width-26*scale)
        end
        overlay.res_x=w;overlay.res_y=h;overlay.data=ass.text;overlay:update()
    end}
end
return M
