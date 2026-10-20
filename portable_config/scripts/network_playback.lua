-- Local extension: bounded reconnects, network cache presets and on-demand diagnostics.
local root=mp.command_native({'expand-path','~~/'})
local ui=dofile(root..'/extensions/ui_locale.lua');ui.install_messages()
local utils=require 'mp.utils'
local policy=dofile(root..'/extensions/playback_preferences.lua')
local source=dofile(root..'/extensions/media_source.lua')
local network=dofile(root..'/extensions/network_state.lua')
local opts={reconnect=true,buffer='auto'}
dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua').options(opts,'network_playback')
local profiles={auto=true,normal=true,large=true}
if profiles[opts.buffer]==nil then opts.buffer='auto' end
local session,pending,restarting,held,timer
local diagnostics=false
local stat,request,request_generation={},nil,0
local cache_profile
local samples,last_sample={},nil
local function snapshot()
    local cache=mp.get_property_native('demuxer-cache-state',{})
    return {time=mp.get_time(),position=mp.get_property_number('time-pos'),duration=mp.get_property_number('duration'),
        seeking=mp.get_property_bool('seeking',false),paused=mp.get_property_bool('pause',false),
        paused_for_cache=mp.get_property_bool('paused-for-cache',false),core_idle=mp.get_property_bool('core-idle',false),
        eof=mp.get_property_bool('eof-reached',false),
        player_seconds=mp.get_property_number('demuxer-cache-duration'),player_bytes=cache['fw-bytes'],
        player_total_bytes=cache['total-bytes'],player_read_speed=mp.get_property_number('cache-speed'),
        player_cache_state=mp.get_property_number('cache-buffering-state'),
        reader_pts=cache['reader-pts'],cache_end=cache['cache-end'],seekable_ranges=cache['seekable-ranges'],
        audio_pts=mp.get_property_number('audio-pts'),video_pts=mp.get_property_number('video-pts'),
        aid=mp.get_property_number('aid'),sid=mp.get_property_number('sid'),
        server_bytes=stat.filled,server_capacity=stat.capacity,server_download_speed=stat.download_speed,
        server_readers=stat.readers,server_piece_bytes=stat.piece_length,
        peers=stat.active_peers,seeders=stat.connected_seeders,server_http_status=stat.http_status}
end
local function sample()
    local now=mp.get_time()
    if last_sample and now-last_sample<1 then return end
    last_sample=now;samples[#samples+1]=snapshot()
    if #samples>60 then table.remove(samples,1) end
end
local function apply_buffer()
    local path=mp.get_property('path','')
    if not policy.network(path) then cache_profile=nil;return end
    cache_profile=network.profile(opts.buffer,source.stream(path)~=nil)
    local profile=cache_profile
    mp.set_property('file-local-options/cache','yes')
    mp.set_property('file-local-options/demuxer-seekable-cache','yes')
    mp.set_property('file-local-options/cache-pause','yes')
    mp.set_property_number('file-local-options/cache-secs',profile.seconds)
    mp.set_property_number('file-local-options/demuxer-max-bytes',profile.bytes)
    mp.set_property_number('file-local-options/demuxer-max-back-bytes',profile.back)
    mp.set_property_number('file-local-options/cache-pause-wait',profile.wait)
end
local function save()
    local f=io.open(dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua').path('script-opts/network_playback.conf'),'wb')
    if not f then mp.osd_message('Не удалось сохранить настройки сети',3);return end
    local ok=f:write('reconnect='..(opts.reconnect and 'yes' or 'no')..'\nbuffer='..opts.buffer..'\n');local closed=f:close()
    if not ok or not closed then mp.osd_message('Не удалось сохранить настройки сети',3) end
end
local function status(state)
    mp.set_property_native('user-data/network-playback',{state=state,attempt=session and session.tries or 0,
        reconnect=opts.reconnect,buffer=opts.buffer,profile=cache_profile})
end
local function release_hook()
    if timer then timer:kill();timer=nil end
    mp.remove_key_binding('cancel-reconnect')
    if held then local hook=held;held=nil;hook:cont() end
end
local function cancel(user)
    if user and session then session.cancelled=true end
    pending,restarting=nil,nil
    release_hook();mp.osd_message('',0);status(session and session.active and 'playing' or 'idle')
end
local function entry_index(id)
    for index,item in ipairs(mp.get_property_native('playlist',{})) do if item.id==id then return index-1,item end end
end
local function selected_id()
    local index=mp.get_property_number('playlist-pos',-1)
    local item=mp.get_property_native('playlist',{})[index+1]
    return item and item.id
end
local function capture()
    if not session or not session.active then return end
    local time=mp.get_property_number('time-pos')
    if time then session.time=time end
    session.duration=mp.get_property_number('duration',session.duration)
    session.seekable=mp.get_property_bool('seekable',session.seekable)
    session.pause=mp.get_property_bool('pause',false)
    session.intentional_end=mp.get_property('end','none')~='none' or mp.get_property('length','none')~='none'
    local ending=mp.get_property_native('user-data/skip-finish',{})
    if ending.path==session.path and ending.id==session.id then session.intentional_end=true end
end
mp.register_event('start-file',function(event)
    local path=mp.get_property('path','')
    if restarting and restarting.id==event.playlist_entry_id then
        session=restarting;restarting=nil
    else
        cancel();session={id=event.playlist_entry_id,path=path,time=0,tries=0,stable=0,loaded=false}
        mp.set_property_native('user-data/skip-finish',{})
    end
    session.path=path;session.active=true
    status('loading')
end)
mp.add_hook('on_load',70,function()
    if session and session.resume then
        if session.seekable then mp.set_property('file-local-options/start',tostring(math.max(0,session.time-2))) end
        mp.set_property_bool('pause',session.pause==true)
        session.resume=nil
    end
    apply_buffer()
end)
mp.register_event('file-loaded',function() if session then session.loaded=true;capture();status('playing') end end)
mp.add_periodic_timer(1,function()
    if session and session.active then
        local previous=session.time;capture()
        if not session.pause and session.time>previous and session.time-previous<3 then
            session.stable=session.stable+session.time-previous
            if session.stable>=60 then session.tries=0;session.stable=0 end
        end
    end
end)
mp.add_hook('on_unload',90,capture)
mp.register_event('end-file',function(event)
    if not session then return end
    session.active=false
    local limit=session.loaded and 5 or 2
    if opts.reconnect and session.id==event.playlist_entry_id and policy.retry(session,event.reason) then
        if session.tries<limit then
            session.tries=session.tries+1;session.stable=0;pending=session;status('waiting')
        else pending=nil;status('failed');mp.osd_message('Не удалось восстановить поток. Проверьте сеть или TorrServer.',5) end
    else pending=nil;status('idle') end
end)
mp.add_hook('on_after_end_file',50,function(hook)
    if not pending then return end
    local attempt=pending
    local delay=math.min(10,attempt.tries*attempt.tries)
    hook:defer();held=hook
    mp.osd_message(string.format(ui.text('Восстановление потока: попытка %d. Esc - отменить'),attempt.tries),delay+1)
    mp.add_forced_key_binding('ESC','cancel-reconnect',function() cancel(true) end)
    timer=mp.add_timeout(delay,function()
        local index,item=entry_index(attempt.id)
        local selected=selected_id()
        if pending~=attempt or not opts.reconnect or not index or item.filename~=attempt.path or (selected and selected~=attempt.id) then
            cancel();return
        end
        pending=nil;restarting=attempt;attempt.resume=true
        mp.commandv('playlist-play-index',index,'yes')
        mp.remove_key_binding('cancel-reconnect');release_hook()
    end)
end)
mp.observe_property('playlist-pos','number',function()
    if held and pending and selected_id()~=pending.id then cancel() end
end)
mp.observe_property('playlist','native',function() if pending and not entry_index(pending.id) then cancel() end end)
mp.register_event('shutdown',function() cancel();if request then mp.abort_async_command(request) end end)
mp.add_key_binding(nil,'cancel',function()cancel(true)end)
local function stop_stat()
    request_generation=request_generation+1
    if request then mp.abort_async_command(request);request=nil end
    stat={}
end
local function loading_reason()
    if not session or not session.active or not policy.network(mp.get_property('path','')) then return end
    if not session.loaded then return 'opening' end
    local loader=mp.get_property_native('user-data/torrserver-loading',{})
    if loader.media==mp.get_property('path','') and type(loader.time)=='number' and mp.get_time()-loader.time<1.3 then
        if loader.state=='opening' or loader.state=='connecting external files' then return 'opening' end
        if loader.state=='caching' then return 'buffering' end
    end
    if mp.get_property_bool('seeking',false) then return 'seeking' end
    if mp.get_property_bool('paused-for-cache',false) then return 'buffering' end
    -- uosc can show its spinner for core-idle without paused-for-cache.
    local progress=mp.get_property_number('cache-buffering-state')
    if mp.get_property_bool('core-idle',false) and not mp.get_property_bool('eof-reached',false)
        and (not mp.get_property_bool('pause',false) or progress and progress<100) then return 'buffering' end
end
local function buffering() return loading_reason()~=nil end
local draw_buffering
local function poll_stat()
    if not (diagnostics or buffering() and (mp.get_property_native('user-data/player-ui/statistics-visible',false) or mp.get_property_native('user-data/player-ui/buffer-visible',false))) or request then return end
    local stream=source.request_stream(mp.get_property('path',''))
    if not stream then stat={};return end
    local gen=request_generation
    request=mp.command_native_async({name='subprocess',playback_only=false,capture_stdout=true,capture_stderr=true,args={
        'curl','--silent','--fail','--write-out','\n%{http_code}','--connect-timeout','2','--max-time','3','--max-filesize','1048576',
        '-H','Content-Type: application/json','--data',utils.format_json({action='get',hash=stream.hash}),network.request(stream)}},function(ok,result)
        if gen~=request_generation then return end
        request=nil
        local raw=result and result.stdout or ''
        local http=tonumber(raw:match('\n(%d%d%d)%s*$'))
        if http then raw=raw:gsub('\n%d%d%d%s*$','') end
        local value=ok and result and result.status==0 and utils.parse_json(raw) or nil
        stat=network.stats(value);stat.http_status=http
        local current=mp.get_property_native('user-data/torrserver-context',{})
        if current.media~=mp.get_property('path','') then current={} end
        stat.buffer=network.cache_time(value,stream.index,mp.get_property_number('duration'),current)
        if draw_buffering then draw_buffering() end
    end)
end
local function number(value,format)
    value=tonumber(value)
    if not value or value~=value or value==math.huge then return ui.text('Нет данных') end
    return string.format(format or '%.0f',value)
end
local function megabytes(value) value=tonumber(value);return value and value/1048576 end
local function menu()
    local recovery=mp.get_property_native('user-data/network-playback',{})
    local states={waiting='Повторное подключение',failed='Ошибка подключения',loading='Открытие потока',idle='Нет воспроизведения',playing='Воспроизведение'}
    local state=states[recovery.state] or 'Нет воспроизведения'
    if mp.get_property_bool('paused-for-cache',false) then state='Ожидание данных'
    elseif mp.get_property_bool('pause',false) and recovery.state=='playing' then state='Пауза' end
    local cache=mp.get_property_native('demuxer-cache-state',{})
    local context=mp.get_property_native('user-data/torrserver-context',{})
    local items={
        {title='Восстановление после обрыва',hint=opts.reconnect and 'ВКЛ' or 'ВЫКЛ',value={'script-binding','network_playback/toggle'}},
        {title='Буфер',items={
            {title='Авто',hint='По текущему источнику',active=opts.buffer=='auto',value={'script-message-to','network_playback','buffer','auto'}},
            {title='Стандартный',hint='60 с · 256 МБ вперёд / 128 МБ назад',active=opts.buffer=='normal',value={'script-message-to','network_playback','buffer','normal'}},
            {title='Увеличенный',hint='180 с · 512 МБ вперёд / 256 МБ назад',active=opts.buffer=='large',value={'script-message-to','network_playback','buffer','large'}},
        }},
        {title='Источник',hint=source.stream(mp.get_property('path','')) and 'TorrServer' or policy.network(mp.get_property('path','')) and 'HTTP' or 'Файл',selectable=false},
        {title='Состояние',hint=state,selectable=false},
        {title='Запас видео',hint=number(mp.get_property_number('demuxer-cache-duration'),'%.1f')..' '..ui.text('с'),selectable=false},
        {title='Буфер плеера',hint=number(cache['fw-bytes'] and cache['fw-bytes']/1048576,'%.1f')..' '..ui.text('МБ'),selectable=false},
        {title='Буфер плеера назад',hint=number(cache['total-bytes'] and cache['fw-bytes'] and math.max(0,cache['total-bytes']-cache['fw-bytes'])/1048576,'%.1f')..' '..ui.text('МБ'),selectable=false},
        {title='Заполнение буфера',hint=number(mp.get_property_number('cache-buffering-state'))..' %',selectable=false},
        {title='Скорость чтения',hint=number(mp.get_property_number('cache-speed') and mp.get_property_number('cache-speed')*8/1000000,'%.1f')..' Мбит/с',selectable=false},
        {title='Пропущено кадров',hint=number(mp.get_property_number('frame-drop-count')),selectable=false},
        {title='Разница аудио и видео',hint=number(mp.get_property_number('avsync'),'%.3f')..' '..ui.text('с'),selectable=false},
        {title=ui.language()=='en' and 'Save loading report' or 'Сохранить отчёт о загрузке',
            value={'script-binding','network_playback/report'}},
    }
    if context.media==mp.get_property('path','') and context.title then
        items[#items+1]={title=ui.language()=='en' and 'Torrent' or 'Раздача',hint=context.title,selectable=false}
        if context.path then items[#items+1]={title=ui.language()=='en' and 'File' or 'Файл',hint=context.path,selectable=false} end
    end
    if source.stream(mp.get_property('path','')) then
        items[#items+1]={title='TorrServer',hint=stat.unavailable and 'Нет ответа' or stat.download_speed and 'Подключён' or 'Ожидание данных',selectable=false}
        items[#items+1]={title='Кеш TorrServer',hint=number(megabytes(stat.filled),'%.1f')..' / '..number(megabytes(stat.capacity),'%.1f')..' '..ui.text('МБ'),selectable=false}
        items[#items+1]={title='Загрузка TorrServer',hint=number(stat.download_speed and stat.download_speed*8/1000000,'%.1f')..' Мбит/с',selectable=false}
        items[#items+1]={title='Пиры / сиды',hint=number(stat.active_peers)..' / '..number(stat.connected_seeders),selectable=false}
    end
    local loader=mp.get_property_native('user-data/torrserver-loading',{})
    if loader.media==mp.get_property('path','') and type(loader.time)=='number' and mp.get_time()-loader.time<1.3 then
        for _,pair in ipairs({{'Файл',loader.file},{'Внешние дорожки',loader.extra}}) do
            if pair[2] and pair[2]~='' then items[#items+1]={title=pair[1],hint=pair[2],selectable=false} end
        end
    end
    if pending then items[#items+1]={title='Отменить восстановление',value={'script-binding','network_playback/cancel'}} end
    return {type='network-playback',title='Сеть и буфер',keep_open=true,items=items,
        footnote='Изменения действуют сразу. Кеш TorrServer и буфер плеера работают отдельно; перемотка вне сохранённого диапазона требует загрузки.'}
end
local function update_menu() if diagnostics then mp.commandv('script-message-to','uosc','update-menu',utils.format_json(menu())) end end
local panel=dofile(root..'/extensions/buffering_panel.lua').new(ui)
draw_buffering=function()
    local cache=mp.get_property_native('demuxer-cache-state',{})
    local reason=loading_reason()
    local path=mp.get_property('path','')
    local loader=mp.get_property_native('user-data/torrserver-loading',{})
    if loader.media~=path or type(loader.time)~='number' or mp.get_time()-loader.time>=1.3 then loader=nil end
    local context=mp.get_property_native('user-data/torrserver-context',{})
    if context.media~=path then context={} end
    local size=context.file_size or (stat.buffer or {}).file_size
    if not size and not path:match('^edl://') then size=mp.get_property_number('stream-end') end
    local player_seconds,estimated=network.player_time(mp.get_property_number('demuxer-cache-duration'),cache['fw-bytes'],size,mp.get_property_number('duration'))
    local data={active=reason~=nil,managed=session and session.active and policy.network(path) or false,
        reason=reason,torrent=source.stream(path)~=nil or loader~=nil,stat=stat,loader=loader,
        seconds=player_seconds,player_estimated=estimated,speed=mp.get_property_number('cache-speed'),
        forward_bytes=cache['fw-bytes'],back_bytes=cache['total-bytes'] and cache['fw-bytes'] and math.max(0,cache['total-bytes']-cache['fw-bytes']),
        progress=mp.get_property_number('cache-buffering-state'),dropped=mp.get_property_number('frame-drop-count'),
        avsync=mp.get_property_number('avsync'),profile=cache_profile,
        media=mp.get_property_native('user-data/media-info',{}),hwdec=mp.get_property('hwdec-current'),
        display_fps=mp.get_property_number('display-fps'),
        torrent_context=context,
        icon_style=mp.get_property_native('user-data/player-ui/icon-style','glass'),
        show_buffer=mp.get_property_native('user-data/player-ui/buffer-visible',false),
        show_statistics=mp.get_property_native('user-data/player-ui/statistics-visible',false)}
    mp.set_property_native('user-data/network-buffering',data)
    if data.managed and data.active then sample() end
    if not data.active then panel.hide();return end
    panel.draw(data)
end
mp.add_key_binding(nil,'report',function()
    -- A numeric snapshot is enough to diagnose stalled seeks. Never export
    -- stream URLs, credentials, torrent metadata, filenames or track titles.
    local report={format=1,created=os.date('!%Y-%m-%dT%H:%M:%SZ'),
        source=source.stream(mp.get_property('path','')) and 'TorrServer' or policy.network(mp.get_property('path','')) and 'HTTP' or 'file',
        buffer=opts.buffer,profile=cache_profile,reconnect=opts.reconnect,
        current=snapshot(),samples=samples}
    local target=dofile(root..'/extensions/user_settings.lua').path('network-report.json')
    local file=io.open(target,'wb')
    local written,closed
    if file then written=file:write(utils.format_json(report));closed=file:close()end
    local en=ui.language()=='en'
    mp.osd_message(written and closed and (en and 'Saved: network-report.json in the settings folder' or 'Отчёт сохранён: network-report.json в папке настроек')
        or (en and 'Could not save loading report' or 'Не удалось сохранить отчёт о загрузке'),5)
end)
local telemetry_timer
local function telemetry()
    poll_stat();draw_buffering();update_menu()
end
local function refresh_telemetry()
    if diagnostics or buffering() then
        if not telemetry_timer then telemetry_timer=mp.add_periodic_timer(1,telemetry) end
        telemetry()
    else
        if telemetry_timer then telemetry_timer:kill();telemetry_timer=nil end
        stop_stat();draw_buffering()
    end
end
mp.add_key_binding(nil,'menu',function()
    diagnostics=true;refresh_telemetry();mp.commandv('script-message-to','uosc','open-menu',utils.format_json(menu()))
end)
local function settings_changed()
    save();if session and session.active then apply_buffer() end;status(mp.get_property_native('user-data/network-playback',{}).state or 'idle');update_menu()
end
mp.add_key_binding(nil,'toggle',function() opts.reconnect=not opts.reconnect;if not opts.reconnect then cancel() end;settings_changed() end)
mp.register_script_message('buffer',function(value) if profiles[value]~=nil then opts.buffer=value;settings_changed() end end)
mp.observe_property('user-data/uosc/menu/type','string',function(_,kind)
    diagnostics=kind=='network-playback'
    refresh_telemetry()
end)
for _,property in ipairs({'paused-for-cache','seeking','core-idle','cache-buffering-state','pause','eof-reached'})do
    mp.observe_property(property,'native',refresh_telemetry)
end
for _,property in ipairs({'osd-dimensions','user-data/player-ui/buffer-visible','user-data/player-ui/statistics-visible',
    'user-data/interface-language','user-data/media-info','hwdec-current','display-fps','user-data/torrserver-context','user-data/player-ui/icon-style'}) do
    mp.observe_property(property,'native',function()draw_buffering()end)
end
mp.observe_property('user-data/torrserver-loading','native',refresh_telemetry)
mp.register_event('file-loaded',refresh_telemetry)
mp.register_event('playback-restart',refresh_telemetry)
mp.register_event('start-file',function()samples={};last_sample=nil;stop_stat();refresh_telemetry()end)
mp.register_event('end-file',function()stop_stat();refresh_telemetry()end)
mp.register_event('shutdown',function()if telemetry_timer then telemetry_timer:kill()end;panel.hide()end)
status('idle')
