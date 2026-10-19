return function(path)
    local real=mp
    local panel=dofile(path('extensions/torrent_panel.lua'))
    local message='Loading [ReinForce] Dan Da Dan (S01) - 03.mkv...\nCurrent state: caching\nTorrent load info:\nSpeed: 97.46 Mbps\nCache: 0.10 / 0.10 GB\nPeers·Seeders: 16 / 41 · 14\n\n'
    local parsed=assert(panel.parse(message))
    assert(parsed.speed=='97.46 Mbps' and parsed.peers=='16 / 41 · 14','Keep TorrServer values')
    local variant=assert(panel.parse(message:gsub('Peers·Seeders:', 'Peers / Seeders:'):gsub('\n\n','\n')))
    assert(variant.cache=='0.10 / 0.10 GB','Accept TorrServer label variants')
    assert(not panel.parse('No response from TorrServer\'s API!'),'Connection errors use ordinary OSD')
    assert(not panel.parse(''),'Empty OSD is not a stats panel')
    local russian=panel.render(parsed,'ru',1280,720)
    assert(russian:find('TORRSERVER И ПЛЕЕР',1,true) and russian:find('Буферизация',1,true))
    assert(russian:find('97.46 Mbps',1,true) and russian:find('0.10 / 0.10 ГБ',1,true))
    assert(panel.render(parsed,'en',1280,720):find('caching',1,true))
    local telemetry=panel.render(parsed,'ru',1280,720,{seconds=0.4,speed=2*1048576})
    assert(telemetry:find('Загрузка сервера',1,true) and telemetry:find('Кеш сервера',1,true))
    assert(telemetry:find('0.4 с',1,true) and telemetry:find('2.0 МБ/с',1,true),'Separate player delivery from peer download')
    assert(panel.render(parsed,'en',1280,720,{}):find('No data',1,true),'Unknown metrics are not zero speed')
    local settled=assert(panel.parse(message:gsub('Current state: caching','Current state: nil')))
    assert(panel.render(settled,'ru',1280,720):find('Воспроизведение',1,true),'Replace TorrServer nil state')
    local overlay={remove=function(self) self.visible=false end,update=function(self) self.visible=true end}
    local timers,events,observers,props={},{},{},{}
    local ok,err=xpcall(function()
        mp={
            create_osd_overlay=function() return overlay end,
            get_osd_size=function() return 1280,720 end,
            get_time=function()return 0 end,get_property=function()return 'http://fixture.invalid/stream'end,
            get_property_native=function(k,d)return props[k] or d end,set_property_native=function(k,v)props[k]=v end,
            get_property_number=function(key) if key=='demuxer-cache-duration' then return 0.4 end end,
            observe_property=function(k,_,fn)observers[k]=fn end,
            register_event=function(k,fn) events[k]=fn end,
            add_timeout=function(_,fn)
                local t={callback=fn,kill=function(self) self.dead=true end}
                timers[#timers+1]=t;return t
            end,
        }
        local instance=panel.new({language=function() return 'ru' end})
        assert(instance.show(message) and overlay.visible)
        assert(props['user-data/torrserver-loading'].file==parsed.file,'Share the full original loader statistics')
        props['user-data/network-buffering']={managed=true}
        observers['user-data/network-buffering']();assert(not overlay.visible,'Only the unified full panel draws while network diagnostics owns it')
        props['user-data/network-buffering']={managed=false}
        instance.show(message);assert(timers[1].dead,'New statistics reset expiry')
        timers[2].callback();assert(not overlay.visible,'Panel expires when buffering stops')
        assert(not props['user-data/torrserver-loading'].file,'Expired loader data cannot leak into another file')
        instance.show(message);events['end-file']();assert(not overlay.visible,'No stale stats on next episode')
    end,debug.traceback)
    mp=real;assert(ok,err)
end
