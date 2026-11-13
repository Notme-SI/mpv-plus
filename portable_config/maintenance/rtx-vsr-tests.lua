return function(path)
    local api = dofile(path('extensions/rtx_vsr.lua'))
    assert(api.scale({w=1280,h=720},{w=3840,h=2160}) == 3,'720p to 4K')
    assert(api.scale({w=1920,h=1080},{w=3840,h=2160}) == 2,'1080p to 4K')
    assert(not api.scale({w=3840,h=2160},{w=3840,h=2160}),'Native 4K has no processing')
    assert(not api.scale({w=1920,h=1080},{w=1200,h=675}),'Small window has no processing')
    assert(api.scale({w=640,h=360},{w=7680,h=4320}) == 4,'Bound processing cost')
    assert(api.scale({w=1920,h=800},{w=3840,h=2160,mt=280,mb=280}) == 2,'Respect letterboxing')
    assert(not api.scale(nil,{w=1920,h=1080}) and not api.scale({w=0,h=0},{}),'Unknown dimensions stay unavailable')
    local original = mp
    local props = {platform='windows',['current-vo']='gpu-next',['current-gpu-context']='d3d11',
        vo='gpu-next',['gpu-api']='',['gpu-context']='',hwdec='no',
        vf={{name='hflip',label='personal'}},['video-params']={w=1920,h=1080},
        ['osd-dimensions']={w=3840,h=2160}}
    local events, observers, queue = {}, {}, {}
    local status, failure, fail_filter, reset_count = nil, nil, false, 0
    local function read(name, default) if props[name] == nil then return default end; return props[name] end
    local function drain()
        for attempt=1,20 do
            local pending=queue; queue={}
            if #pending==0 then return end
            for _,item in ipairs(pending) do if not item.dead then item.fn() end end
        end
        error('RTX test timers did not settle')
    end
    local ok, err = xpcall(function()
        mp = {
            get_property=read, get_property_native=read,
            set_property=function(name,value)
                if props['current-vo'] ~= '' then
                    assert(not (name=='gpu-api' and value=='vulkan' and props['gpu-context']=='d3d11'),
                        'Never request Vulkan with a forced D3D11 context')
                    assert(not (name=='gpu-context' and value=='winvk' and props['gpu-api']=='d3d11'),
                        'Never request a Vulkan context with a forced D3D11 API')
                end
                props[name]=value
                if name=='vo' then
                    reset_count=reset_count+1
                    props['current-gpu-context']=props['gpu-api']=='vulkan' and 'winvk' or 'd3d11'
                end
                return true
            end,
            set_property_native=function(name,value)
                if name=='vf' and fail_filter and #value>1 then return false end
                props[name]=value; return true
            end,
            add_timeout=function(_,fn)
                local item={fn=fn,kill=function(self)self.dead=true end};queue[#queue+1]=item;return item
            end,
            observe_property=function(name,_,fn)observers[name]=fn end,
            add_hook=function()end, enable_messages=function()end,
            osd_message=function()end,
            register_event=function(name,fn)events[name]=fn end,
        }
        local rtx=api.new(function(value)status=value end,function(value)failure=value end)
        assert(rtx.enable());drain()
        assert(status=='requested' and #props.vf==2 and props.vf[1].label=='personal','Add exactly one named processor')
        assert(props.vf[2].params.scale=='2.000000' and props.vf[2].params['scaling-mode']=='nvidia')
        assert(props.hwdec=='no','Software decoder is preserved; mpv uploads frames for the native processor')
        props['osd-dimensions']={w=1200,h=675};observers['osd-dimensions']();drain()
        assert(status=='idle' and #props.vf==1,'Window below native size removes only owned processing')
        props['osd-dimensions']={w=3840,h=2160};observers['osd-dimensions']();drain()
        assert(#props.vf==2,'Fullscreen restores processing without duplicate filters')
        events['end-file']();assert(#props.vf==1 and status=='waiting','Clear owned processor between files')
        events['file-loaded']();drain();assert(#props.vf==2,'Apply to next file')
        rtx.disable()
        assert(#props.vf==1 and props.hwdec=='no' and props['gpu-api']=='' and props['gpu-context']=='','Restore the previous options')
        props['gpu-api'],props['current-gpu-context']='vulkan','winvk'
        assert(rtx.enable());drain()
        assert(status=='restart' and #props.vf==1 and props['gpu-api']=='vulkan' and reset_count==0,'Never rebuild a running alternate renderer')
        rtx.disable();assert(props['gpu-api']=='vulkan' and reset_count==0)
        props['current-vo'],props['current-gpu-context']='',''
        props['gpu-context']='winvk'
        assert(rtx.enable());drain()
        assert(status=='waiting' and props['gpu-api']=='d3d11' and #props.vf==1,'Prepare requested renderer before the first video')
        props['current-vo'],props['current-gpu-context']='gpu-next','d3d11'
        events['file-loaded']();drain();assert(#props.vf==2,'Saved selection activates after video initialization')
        rtx.disable();assert(props['gpu-api']=='d3d11' and props['gpu-context']=='d3d11' and reset_count==0,'Disabling in a running window never resets the decoder or renderer')
        props['current-vo'],props['current-gpu-context']='',''
        props['gpu-api'],props['gpu-context']='vulkan','winvk'
        rtx.enable();drain();rtx.disable()
        assert(props['gpu-api']=='vulkan' and props['gpu-context']=='winvk','Before a window exists the previous API/context pair is restored')
        rtx.enable();drain()
        props['gpu-api']='opengl';rtx.disable()
        assert(props['gpu-api']=='opengl','Respect options changed by the user while active')
        props['current-vo']='gpu-next'
        props['gpu-api'],props['current-gpu-context']='','d3d11'
        rtx.enable();drain()
        events['log-message']({prefix='d3d11vpp',level='warn',text='Failed to enable NVIDIA RTX Super Resolution: rejected'})
        assert(not rtx.enabled and #props.vf==1 and failure,'Driver rejection must not silently run ordinary scaling')
        fail_filter=true;failure=nil;rtx.enable();drain()
        assert(not rtx.enabled and #props.vf==1 and failure,'Reject unavailable native filter and roll back')
        fail_filter=false;props.platform='linux';failure=nil
        assert(not rtx.enable() and failure and #props.vf==1,'Unsupported platform stays unmodified')
    end, debug.traceback)
    mp = original
    assert(ok, err)
end
