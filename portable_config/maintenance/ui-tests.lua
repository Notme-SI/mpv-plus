return function(path)
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
        local sample={seconds=23,profile={seconds=50},progress=100,speed=2*1048576,
            forward_bytes=8*1048576,back_bytes=12*1048576,media=rich,hwdec='no',dropped=0,avsync=-.015}
        panel.draw(sample)
        assert(overlay.data:find('46 %',1,true) and not overlay.data:find('100 %',1,true),'Time coverage and loading progress are separate')
        assert(overlay.data:find('Программное декодирование',1,true) and overlay.data:find('AAC',1,true),'Describe actual codecs and active decoding')
        assert(overlay.data:find('-0.015',1,true),'Signed audio/video sync is retained')
        for _,size in ipairs({{640,360},{1920,1080},{3840,2160}})do
            w,h=size[1],size[2];panel.draw(sample)
            assert(overlay.res_x==w and overlay.res_y==h and not overlay.data:find('nan',1,true),'Scale to the actual OSD')
        end
        sample.seconds=nil;sample.speed=nil;sample.show_statistics=false;panel.draw(sample)
        assert(overlay.data:find('Буфер —',1,true) and not overlay.data:find('0 %',1,true),'Missing telemetry is not a fake zero')
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
end
