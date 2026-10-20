-- Presentation of the loader's own statistics; no requests or playback changes.
local M={}
local surface=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/overlay_style.lua')
function M.parse(message)
    if type(message)~='string' then return end
    message=message:gsub('\r\n','\n')
    -- TorrServer versions differ in punctuation and in whether the blank
    -- line before the external-file status is present. Keep parsing the
    -- stable labels instead of requiring one exact formatted message.
    local file,state,speed,cache,peers,extra=message:match(
        '^%s*Loading%s+(.-)%.%.%.%s*\n.-Current state:%s*(.-)%s*\n.-Speed:%s*(.-)%s*\n.-Cache:%s*(.-)%s*\n.-Peers[^:]*:%s*([^\n]*)\n(.*)$')
    if file then
        return {file=file,state=state,speed=speed,cache=cache,peers=peers,extra=extra:match('^%s*(.-)%s*$')}
    end
    local file,state,speed,cache,peers,extra=message:match(
        '^%s*Loading (.-)%.%.%.\nCurrent state: (.-)\nTorrent load info:\nSpeed: (.-)\nCache: (.-)\nPeers·Seeders: ([^\n]*)\n*(.*)$')
    if not file then return end
    return {file=file,state=state,speed=speed,cache=cache,peers=peers,extra=extra:match('^%s*(.-)%s*$')}
end
local function escape(value)
    return tostring(value or ''):gsub('\\','\\e'):gsub('{','\\{'):gsub('}','\\}'):gsub('[\r\n]',' ')
end
local function shorten(value,limit)
    local chars={}
    for c in value:gmatch('[%z\1-\127\194-\244][\128-\191]*') do chars[#chars+1]=c end
    if #chars<=limit then return value end
    return table.concat(chars,'',1,limit-1)..'…'
end
function M.render(data,language,w,h,playback)
    local ass=require('mp.assdraw').ass_new()
    local en=language=='en'
    local scale=math.max(0.8,math.min(2.1,h/720))
    local width=math.min(440*scale,w-20*scale)
    local x,y=w-width-10*scale,10*scale
    local height=(data.extra~='' and 218 or 190)*scale
    if playback then height=height+54*scale end
    surface.panel(ass,{x0=x,y0=y,x1=x+width,y1=y+height},scale,playback and playback.icon_style or 'glass',false,8*scale)
    local function text(value,px,py,size,color,bold,align)
        ass:new_event()
        ass:append(string.format('{\\rDefault\\an%d\\pos(%.1f,%.1f)\\fnSegoe UI\\fs%.1f\\1c&H%s&\\alpha&H00&\\1a&H00&\\bord0\\shad0\\b%d}%s',
            align or 7,px,py,size*scale,color,bold and 1 or 0,escape(value)))
    end
    text(en and 'TORRSERVER AND PLAYER' or 'TORRSERVER И ПЛЕЕР',x+12*scale,y+10*scale,20,'C8C8C8',true)
    text(shorten(data.file,36),x+12*scale,y+38*scale,18,'9B9B9B')
    ass:new_event()
    ass:append('{\\an7\\pos(0,0)\\bord0\\shad0\\1c&HFFFFFF&\\1a&HE0&}')
    ass:draw_start();ass:rect_cw(x+12*scale,y+65*scale,x+width-12*scale,y+66*scale);ass:draw_stop()
    local state=tostring(data.state or '')
    -- Some TorrServer builds send the literal string "nil" after the
    -- initial cache fill. The stream is already playing at that point.
    if state=='' or state:lower()=='nil' or state:lower()=='unknown' then
        state=en and 'Playing' or 'Воспроизведение'
    end
    if not en then
        state=state:gsub('connecting external files','Внешние дорожки'):gsub('opening','Открытие'):gsub('caching','Буферизация')
    end
    local cache=en and data.cache or data.cache:gsub(' GB',' ГБ')
    local rows={
        {en and 'State' or 'Состояние',state},
        {en and 'Server download' or 'Загрузка сервера',data.speed},
        {en and 'Server cache' or 'Кеш сервера',cache},
        {en and 'Peers · seeders' or 'Пиры · сиды',data.peers},
    }
    if playback then
        local function metric(value,unit)
            if type(value)~='number' or value<0 or value~=value or value==math.huge then
                return en and 'No data' or 'Нет данных'
            end
            return string.format('%.1f %s',value,unit)
        end
        rows[#rows+1]={en and 'Player buffer' or 'Запас видео',metric(playback.seconds,en and 's' or 'с')}
        rows[#rows+1]={en and 'Player read' or 'Чтение mpv',metric(playback.speed and playback.speed/1048576,en and 'MiB/s' or 'МБ/с')}
    end
    for i,row in ipairs(rows) do
        local yy=y+(76+(i-1)*27)*scale
        text(row[1],x+12*scale,yy,21,'999999')
        text(row[2],x+width-12*scale,yy,21,'FFFFFF',true,9)
    end
    if data.extra~='' then
        local extra=data.extra
        if not en then extra=extra:gsub('Connected ','Подключено '):gsub(' external files',' внешних файлов'):gsub('Errors:','Ошибки:') end
        text(shorten(extra,38),x+12*scale,y+(playback and 244 or 190)*scale,18,'999999')
    end
    return ass.text
end
function M.new(ui)
    local overlay=mp.create_osd_overlay('ass-events')
    overlay.z=1100
    local value,timer
    local function hide()
        value=nil;overlay:remove()
        mp.set_property_native('user-data/torrserver-loading',{})
        if timer then timer:kill();timer=nil end
    end
    local function draw()
        local w,h=mp.get_osd_size()
        if not value or w<=0 or h<=0 then overlay:remove();return end
        -- The network extension owns a single full panel while this stream is
        -- open. Keep the standalone loader panel as a fallback before launch.
        if mp.get_property_native('user-data/network-buffering',{}).managed then overlay:remove();return end
        overlay.res_x=w;overlay.res_y=h
        overlay.data=M.render(value,ui.language(),w,h,{
            icon_style=mp.get_property_native('user-data/player-ui/icon-style','glass'),
            seconds=mp.get_property_number('demuxer-cache-duration'),
            speed=mp.get_property_number('cache-speed'),
        });overlay:update()
    end
    mp.observe_property('osd-dimensions','native',draw)
    mp.observe_property('user-data/interface-language','native',draw)
    mp.observe_property('user-data/player-ui/icon-style','native',draw)
    mp.observe_property('user-data/network-buffering','native',draw)
    mp.register_event('end-file',hide)
    mp.register_event('shutdown',hide)
    return {
        show=function(message)
            local parsed=M.parse(message)
            if not parsed then return false end
            value=parsed;draw()
            local shared={media=mp.get_property('path',''),time=mp.get_time()}
            for k,v in pairs(parsed)do shared[k]=v end
            mp.set_property_native('user-data/torrserver-loading',shared)
            -- Loader refreshes every 0.5s only while buffering.
            if timer then timer:kill() end
            timer=mp.add_timeout(1.2,hide)
            return true
        end,
        hide=hide,
    }
end
return M
