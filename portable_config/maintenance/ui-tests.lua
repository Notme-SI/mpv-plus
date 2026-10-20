return function(path)
    local clock=dofile(path('extensions/time_format.lua')).clock
    for raw,label in pairs({['00:26:53']='26:53',['-01:58:07']='1:58:07',['00:00:00']='0:00',
        ['-00:07:16']='7:16',['12:00:01']='12:00:01',['-00:00:04.500']='0:04.500'})do
        assert(clock(raw)==label,'Compact clock: '..raw)
    end
    local network=dofile(path('extensions/network_state.lua'))
    local single={Capacity=500,Filled=230,Torrent={file_stats={{id=1,length=1000}}}}
    local time=network.cache_time(single,1,100)
    assert(time.seconds==23 and time.target==50,'Convert current-file cached bytes using file duration and size')
    single.Filled=460
    assert(network.cache_time(single,1,100).seconds==46,'Cached seconds advance with downloaded bytes')
    assert(not network.cache_time(single,1,0).seconds,'Unknown duration cannot produce invented seconds')
    local multi={Capacity=500,Filled=9999,PiecesLength=100,Torrent={file_stats={{id=1,length=200},{id=2,length=1000}}},
        Pieces={['0']={Size=100},['2']={Size=100},['3']={Size=50},['4']={Size=100},['12']={Size=100}}}
    local selected=network.cache_time(multi,2,100)
    assert(selected.seconds==25 and selected.target==50,'Exclude other torrent files and use selected episode size')
    multi.Readers={{Reader=3,End=5}}
    assert(network.cache_time(multi,2,100).seconds==15,'Exclude cached pieces behind the current network reader')
    multi.Pieces['3'].Size=100
    assert(network.cache_time(multi,2,100).seconds==20,'Count loaded bytes of incomplete pieces as they arrive')
    multi.Readers={{Reader=4,End=5}}
    assert(network.cache_time(multi,2,100).seconds==10,'Seeking excludes old cached ranges')
    multi.Pieces=nil
    assert(not network.cache_time(multi,2,100).seconds,'Never attribute whole-torrent Filled to one file')
    assert(not network.cache_time({Filled=500},2,100,{file_size=1000}).seconds,'File size alone cannot identify torrent byte coverage')
    local boundary={Capacity=100,PiecesLength=100,Torrent={file_stats={{id=1,length=150},{id=2,length=200}}},
        Pieces={['1']={Size=100},['2']={Size=50},['3']={Size=100}}}
    assert(network.cache_time(boundary,2,20).seconds==15,'Clip boundary pieces to the selected file')
    local seconds,estimated=network.player_time(0,230,1000,100)
    assert(seconds==23 and estimated,'Fallback uses forward packet bytes and average file bitrate')
    seconds,estimated=network.player_time(7,230,1000,100)
    assert(seconds==7 and not estimated,'Prefer native packet timestamp coverage when available')
    assert(network.player_time(nil,0,1000,100)==nil,'Missing packet telemetry stays unavailable')
    local info=dofile(path('extensions/media_info.lua'))
    local function video(w,h,fps,codec) return {['demux-w']=w,['demux-h']=h,['demux-fps']=fps,codec=codec or 'hevc'} end
    local function badge(data,kind)
        for _,entry in ipairs(data.badges) do if entry.kind==kind then return entry.text end end
    end
    local data=info.describe(video(3840,1600,24000/1001),{codec='eac3'},{w=1920,h=800},60)
    assert(badge(data,'quality')=='4K' and badge(data,'video')=='HEVC')
    assert(badge(data,'audio')=='E-AC-3' and data.fps=='23,976 FPS','Static source metadata')
    assert(badge(info.describe(video(1440,1080,25),nil,{},nil),'quality')=='1080p','4:3 source')
    assert(badge(info.describe(video(1920,800,24),nil,{},nil),'quality')=='1080p','Cinemascope source')
    assert(info.describe(video(0,0,0),nil,{},29.97).fps=='29,97 FPS','Container fallback')
    assert(info.describe(video(nil,nil,math.huge),nil,{},0).fps==nil,'Invalid FPS')
    assert(#info.describe(nil,nil,{},0).badges==0,'New file clears old metadata')
    assert(info.describe({image=true,['demux-fps']=30},nil,{},60).fps==nil,'No FPS for cover images')

    local rich=info.describe(video(1920,1080,24000/1001,'h264'),{codec='aac',lang='rus',
        ['demux-channels']='stereo',['demux-channel-count']=2,['demux-samplerate']=48000,['demux-bitrate']=127000,decoder='aac'},{},nil)
    assert(rich.video.width==1920 and rich.video.fps==24000/1001 and rich.audio.samplerate==48000)
    assert(rich.summary[2].text=='Русский · AAC · 2.0 · 127 kbps','Audio summary uses real source values')
    assert(not rich.summary[1].text:find('60',1,true),'Display refresh must not replace source FPS')
    -- Real renderer: cache percentage must describe time coverage, not the
    -- unrelated loading-progress property; unknown values must not become zero.
    local native_mp=mp
    local overlay={update=function()end,remove=function(self)self.data=''end}
    local w,h=1280,720
    local ok_render,render_error=xpcall(function()
        mp={command_native=function()return path('')end,create_osd_overlay=function()return overlay end,
            get_osd_size=function()return w,h end}
        local panel=dofile(path('extensions/buffering_panel.lua')).new({language=function()return 'ru'end})
        local sample={reason='seeking',seconds=23,profile={seconds=50},progress=100,speed=2*1048576,
            forward_bytes=8*1048576,back_bytes=12*1048576,media=rich,hwdec='no',dropped=0,avsync=-.015}
        panel.draw(sample)
        assert(overlay.data:find('46%',1,true) and not overlay.data:find('100%',1,true),'Time coverage and loading progress are separate')
        assert(overlay.data:find('Буфер: 23 из 50 сек. (46%)  ',1,true) and overlay.data:find('16.8 Мбит/с',1,true),'Whole seconds and bytes/s converted to decimal Mbit/s')
        assert(overlay.data:find('Статистика',1,true) and overlay.data:find('}speed',1,true) and overlay.data:find('Статус: перемотка',1,true),'Statistics heading and separate state')
        assert(overlay.data:find('Декодер: программный',1,true) and overlay.data:find('AAC',1,true),'Describe actual codecs and active decoding')
        assert(overlay.data:find('-0.015',1,true),'Signed audio/video sync is retained')
        sample.torrent=true;sample.stat={download_speed=1025000,buffer={seconds=23,target=50}}
        panel.draw(sample)
        assert(overlay.data:find('Буфер: 23 из 50 сек. (46%)  ',1,true) and overlay.data:find('download',1,true) and overlay.data:find('16.8 Мбит/с',1,true),'Pill reflects actual mpv cache and read speed')
        sample.seconds=0;sample.stat.buffer={seconds=90,target=94};sample.stat.filled=100*1048576;sample.stat.capacity=100*1048576
        panel.draw(sample)
        assert(overlay.data:find('Буфер: 0 из 50 сек. (0%)',1,true) and overlay.data:find('100/100 МБ',1,true),'A full server cache must not masquerade as playable mpv buffer')
        sample.seconds=23;panel.draw(sample)
        assert(not overlay.data:find('TorrServer',1,true) and overlay.data:find('Загрузка:',1,true),'Compact statistics use the requested neutral heading')
        assert(not overlay.data:find('≈',1,true) and not overlay.data:find('CPU',1,true),'No approximation sign or misleading CPU/FPS label')
        sample.torrent=false;sample.stat=nil

        for _,size in ipairs({{640,360},{1920,1080},{3840,2160}})do
            w,h=size[1],size[2];panel.draw(sample)
            assert(overlay.res_x==w and overlay.res_y==h and not overlay.data:find('nan',1,true),'Scale to the actual OSD')
        end
        sample.seconds=nil;sample.speed=nil;sample.show_statistics=false;panel.draw(sample)
        assert(overlay.data:find('Буфер: —',1,true) and not overlay.data:find('0%',1,true),'Missing telemetry is not a fake zero')
        sample.show_buffer=false;panel.draw(sample);assert(overlay.data=='','Disabled overlays leave no stale ASS')
    end,debug.traceback)
    mp=native_mp;assert(ok_render,render_error)

    -- Check the real numeric-input callback without creating settings or opening a window.
    local real=mp
    local saved_input,saved_options=package.loaded['mp.input'],package.loaded['mp.options']
    local saved_ui=package.loaded['mpv-build/ui_locale']
    local values,messages,bindings,input_opts={},{},{},nil
    local log_count,closed=0,false
    local mock={command_native=function(args) return path(args[2]:gsub('^~~/','')) end,
        get_property=function(_,default) return default end,
        get_property_native=function(_,default) return default end,
        get_script_name=function() return 'picture_controls' end,
        set_property_number=function(key,value) values[key]=value;return true end,
        get_property_number=function(key,default) return values[key] or default end,
        observe_property=function() end,commandv=function() end,register_event=function() end,
        add_key_binding=function(_,name,fn) bindings[name]=fn end,
        register_script_message=function(name,fn) messages[name]=fn end}
    local ok,err=xpcall(function()
        mp=mock
        package.loaded['mp.options']={read_options=function() end}
        package.loaded['mp.input']={get=function(opts) input_opts=opts end,
            log=function() log_count=log_count+1 end,terminate=function() closed=true end}
        dofile(path('scripts/picture_controls.lua'))
        local utils=require 'mp.utils'
        messages.event(utils.format_json({type='activate',value='contrast',action='edit'}))
        assert(input_opts and input_opts.default_text=='0')
        for _,bad in ipairs({'','abc','-101','101','nan','inf'}) do input_opts.submit(bad) end
        assert(log_count==6 and values.contrast==0 and not closed,'Reject invalid values')
        input_opts.submit('-12,5')
        assert(values.contrast==-12.5 and closed,'Comma decimal input')
        input_opts.submit('100');assert(values.contrast==100,'Upper boundary')
        input_opts.submit('-100');assert(values.contrast==-100,'Lower boundary')
    end,debug.traceback)
    mp=real
    package.loaded['mp.input'],package.loaded['mp.options']=saved_input,saved_options
    package.loaded['mpv-build/ui_locale']=saved_ui
    assert(ok,err)
    -- Metadata requests finish normally in playback, but cannot retry on exit.
    do
        local original=mp
        local callbacks,aborted,shutdown={},{},nil
        local calls,finished=0,0
        local ok,err=xpcall(function()
            mp={command_native_async=function(args,fn)calls=calls+1;callbacks[calls]=fn;return calls end,
                abort_async_command=function(id)aborted[id]=true;callbacks[id](false,{status=-2})end,
                register_event=function(name,fn)if name=='shutdown'then shutdown=fn end end}
            dofile(path('extensions/async_requests.lua')).install()
            mp.command_native_async({name='subprocess'},function()finished=finished+1 end)
            callbacks[1](true,{status=0})
            mp.command_native_async({name='subprocess'},function()finished=finished+10 end)
            mp.command_native_async({name='subprocess'},function()finished=finished+100 end)
            shutdown()
            assert(finished==1 and aborted[2] and aborted[3] and not aborted[1],'Abort all pending metadata children without invoking failure/retry callbacks')
        end,debug.traceback)
        mp=original;assert(ok,err)
    end
    -- Only owned thumbnail subprocesses are cancelled before pipe shutdown.
    do
        local original=mp
        local callbacks,aborted,events={},{},{}
        local calls,finished=0,0
        local mock={get_property_native=function()return 'fixture-player-path'end,
            command_native_async=function(args,fn)calls=calls+1;callbacks[calls]=fn;return calls end,
            abort_async_command=function(id)aborted[id]=true;callbacks[id](false,{status=-2})end,
            register_event=function(name,fn)events[name]=fn end}
        local ok,err=xpcall(function()
            mp=mock;dofile(path('extensions/thumbfast.lua'))
            mock.command_native_async({name='subprocess',args={'fixture'}},function()finished=finished+1 end)
            callbacks[1](true,{status=0})
            mock.command_native_async({name='subprocess',args={'fixture'}},function()finished=finished+10 end)
            mock.command_native_async({'overlay-remove',1},function()end)
            mock.command_native_async({name='subprocess',detach=true,args={'fixture'}},function()end)
            events.shutdown()
            assert(aborted[2] and not aborted[1] and not aborted[3] and not aborted[4],'Cancel pending thumbnail child only')
            assert(finished==1,'Cancelled child cannot trigger a shutdown fallback or spawn a replacement')
        end,debug.traceback)
        mp=original;assert(ok,err)
    end

end
