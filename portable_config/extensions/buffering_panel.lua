-- Compact loading diagnostics. The full values remain in Network and buffer.
local M={}
local style=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/overlay_style.lua')
local measure=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/text_metrics.lua')
local info=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/media_info.lua')
function M.new(ui)
    local assdraw=require 'mp.assdraw'
    local metrics=measure.new()
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
    return {hide=function()overlay:remove()end,draw=function(data)
        local w,h=mp.get_osd_size()
        if w<=0 or h<=0 or data.show_buffer==false and data.show_statistics==false then overlay:remove();return end
        local en,scale=ui.language()=='en',math.max(.65,math.min(2,h/720))
        local second,megabyte,speed=en and 's' or 'с',en and 'MiB' or 'МБ',en and 'Mbps' or 'Мбит/с'
        local font='Segoe UI Semibold'
        local function bits(n)return valid(n) and n*8/1000000 end
        local ass=assdraw.ass_new()
        local function box(x,y,width,height,radius)
            style.panel(ass,{x0=x,y0=y,x1=x+width,y1=y+height},scale,data.icon_style or 'glass',false,radius or 7*scale)
        end
        local function text(value,x,y,size,color,width)
            value=measure.escape(value)
            ass:new_event();ass:append(string.format('{\\rDefault\\an7\\pos(%.1f,%.1f)\\fnSegoe UI Semibold\\fs%.1f\\alpha&H00&\\1c&H%s&\\1a&H00&\\bord0\\shad1\\4c&H000000&\\4a&H20&\\q2%s}%s',
                x,y,size*scale,color or 'FFFFFF',width and string.format('\\clip(%d,%d,%d,%d)',math.floor(x),math.floor(y),math.floor(x+width),math.ceil(y+size*scale*1.5))or'',value))
        end
        if data.show_statistics~=false then
            local rows={}
            local function row(value,muted)if value~=''then rows[#rows+1]={value,muted}end end
            local header=(en and 'Statistics' or 'Статистика')
            local states={opening=en and 'Opening stream' or 'Открытие потока',seeking=en and 'Seeking' or 'Перемотка',buffering=en and 'Buffering' or 'Буферизация'}
            local status=states[data.reason] or (en and 'Loading' or 'Загрузка')
            if not en then status=status:gsub('^Перемотка','перемотка'):gsub('^Буферизация','буферизация'):gsub('^Открытие','открытие'):gsub('^Загрузка','загрузка') end
            row((en and 'Status: ' or 'Статус: ')..status,true)
            local maximum=math.min(w-36*scale,420*scale)
            local content=maximum-24*scale
            if data.torrent then
                local context=data.torrent_context or {}
                local name=context.title or data.loader and data.loader.file
                local missing=context.unavailable and (en and 'name unavailable' or 'название недоступно')
                    or (en and 'resolving…' or 'определяется…')
                row(metrics.middle((en and 'Torrent: ' or 'Раздача: ')..(name or missing),content,20*scale,font))
                if context.path then
                    row((en and 'File: ' or 'Файл: ')..(context.path:match('[^/\\]+$') or context.path),true)
                end
            end
            local media=data.media or {};local video,audio=media.video,media.audio
            if video then
                row(join({video.width and video.height and (video.width..'×'..video.height) or '',video.codec or '',video.profile or '',video.fps and metric(video.fps,'FPS',3):gsub('%.000 FPS',' FPS') or ''}))
                local decoder=data.hwdec=='no' and (en and 'Decoder: software' or 'Декодер: программный')
                    or data.hwdec and ((en and 'Decoder: ' or 'Декодер: ')..data.hwdec) or ''
                row(join({decoder,data.display_fps and (en and 'display ' or 'экран ')..metric(data.display_fps,en and 'Hz' or 'Гц',0) or ''}),true)
            end
            if audio then
                local layout=({stereo='2.0',mono='1.0'})[audio.channels] or audio.channels
                local channels=layout or (audio.channel_count and tostring(audio.channel_count)..' ch') or ''
                row(join({audio.codec or '',channels,info.language(audio.language) or '',audio.samplerate and metric(audio.samplerate/1000,'kHz',1) or '',audio.bitrate and metric(audio.bitrate/1000,'kbps',0) or ''}))
                if audio.decoder and audio.decoder:lower():gsub('%W','')~=(audio.codec or ''):lower():gsub('%W','') then row((en and 'Audio decoder' or 'Декодер аудио')..' · '..audio.decoder,true)end
            end
            row((en and 'Player buffer: ' or 'Буфер плеера: ')..metric(data.seconds,second,0)..' · '..metric(bits(data.speed),speed),true)
            if data.torrent then
                local s,loader=data.stat or {},data.loader
                local transfer=s.download_speed and metric(bits(s.download_speed),speed)
                    or loader and loader.speed or s.unavailable and ((s.http_status==401 or s.http_status==403) and (en and 'API: sign in' or 'API: авторизация') or (en and 'API unavailable' or 'API недоступен')) or '—'
                local cache=s.capacity and metric(mb(s.filled),nil,0)..'/'..metric(mb(s.capacity),megabyte,0)
                    or loader and (en and loader.cache or loader.cache:gsub(' GB',' ГБ')) or '—'
                local transfer_label=en and 'Download: ' or 'Загрузка: '
                local line=transfer_label..transfer..' · '..(en and 'Cache ' or 'Кеш ')..cache
                if metrics.width(line,20*scale,font)<=content then row(line)
                else row(transfer_label..transfer);row((en and 'Cache ' or 'Кеш ')..cache,true) end
                local peers=(en and 'Peers/seeds ' or 'Пиры/сиды ')..(s.active_peers and metric(s.active_peers,nil,0)..' / '..metric(s.connected_seeders,nil,0)
                    or loader and loader.peers or '—')
                local external=loader and loader.extra and loader.extra:match('^Connected (%d+) external files$')
                -- The normal external-track count remains in the detailed menu.
                row(peers..' · '..(en and 'Dropped ' or 'Потери ')..metric(data.dropped,nil,0),true)
                if loader and loader.extra and loader.extra~='' and not external then
                    row(en and loader.extra or loader.extra:gsub('Connected ','Подключено '):gsub(' external files',' внешних файлов'):gsub('Errors:','Ошибки:'),true)
                end
            end
            if not data.torrent then row((en and 'Dropped ' or 'Потери ')..metric(data.dropped,nil,0),true)end
            rows[#rows][1]=rows[#rows][1]..' · A/V '..metric(data.avsync,second,3,true)
            local fitted={}
            local width=metrics.width(header,18*scale,font)+50*scale
            for _,item in ipairs(rows)do
                local value=metrics.fit(item[1],content,20*scale,font)
                fitted[#fitted+1]={value,item[2]}
                width=math.max(width,metrics.width(value,20*scale,font)+24*scale)
            end
            width=math.min(maximum,width)
            local x,y=w-width-18*scale,100*scale
            box(x,y,width,(45+#fitted*25)*scale)
            ass:new_event();ass:append(string.format('{\\rDefault\\an7\\pos(%.1f,%.1f)\\fnMaterialIconsRound-Regular\\fs%.1f\\alpha&H00&\\1c&HFFFFFF&\\bord0\\shad0}speed',x+12*scale,y+8*scale,20*scale))
            text(header,x+38*scale,y+8*scale,18,'FFFFFF',width-50*scale)
            for i,item in ipairs(fitted)do text(item[1],x+12*scale,y+(15+i*25)*scale,20,item[2] and 'EEEEEE' or 'FFFFFF',width-24*scale)end
        end
        if data.show_buffer~=false then
            -- Only mpv's forward packets describe video actually received by
            -- this player. A full server cache may belong to another byte range.
            local seconds=valid(data.seconds)
            local target=data.profile and valid(data.profile.seconds)
            local prefix=en and 'Buffer: ' or 'Буфер: '
            seconds=seconds and math.floor(seconds)
            target=target and math.floor(target)
            local unit=en and 's' or 'сек.'
            local summary=prefix..metric(seconds,unit,0)
            if seconds and target and target>0 then
                summary=prefix..metric(seconds,nil,0)..(en and ' of ' or ' из ')..metric(target,unit,0)
                    ..' ('..metric(math.min(100,seconds/target*100),nil,0)..'%)'
            end
            summary=summary..'  '
            local transfer=metric(bits(data.speed),en and 'Mbps' or 'Мбит/с')
            local prefix_width=metrics.width(summary,19*scale,font)
            local content_width=prefix_width+20*scale+metrics.width(transfer,19*scale,font)
            local width=math.min(w-36*scale,content_width+24*scale)
            local y=math.max(20*scale,h-139*scale)
            local x=(w-width)/2
            box(x,y,width,36*scale,18*scale)
            local left=(w-content_width)/2
            local function part(value,px,face,size,anchor)
                ass:new_event();ass:append(string.format('{\\rDefault\\an%d\\pos(%.1f,%.1f)\\fn%s\\fs%.1f\\alpha&H00&\\1c&HFFFFFF&\\1a&H00&\\bord0\\shad1\\4c&H000000&\\4a&H20&}%s',
                    anchor,px,y+18*scale,face,size*scale,measure.escape(value)))
            end
            part(summary,left,font,19,4)
            part('download',left+prefix_width+8*scale,'MaterialIconsRound-Regular',16,5)
            part(transfer,left+prefix_width+20*scale,font,19,4)
        end
        overlay.res_x=w;overlay.res_y=h;overlay.data=ass.text;overlay:update()
    end}
end
return M
