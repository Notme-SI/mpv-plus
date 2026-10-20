-- Offline compatibility tests, run in an isolated mpv process before updating.
local real = mp
local utils = require 'mp.utils'
local script_file = debug.getinfo(1,'S').source:sub(2)
local root = utils.join_path(assert(script_file:match('^(.*)[/\\]')), '..')
local function path(p) return utils.join_path(root,p) end
local function read(p)
    local f=assert(io.open(path(p),'rb')); local s=f:read('*a'); f:close(); return s
end
local function contains(p,s) assert(read(p):find(s,1,true),p..': integration API changed: '..s) end
local function parse_dir(dir)
    for _,name in ipairs(utils.readdir(path(dir),'files') or {}) do
        if name:match('%.lua$') then assert(loadfile(path(dir..'/'..name))) end
    end
    for _,name in ipairs(utils.readdir(path(dir),'dirs') or {}) do parse_dir(dir..'/'..name) end
end
local function tests()
    parse_dir('scripts'); parse_dir('vendor'); parse_dir('extensions')
    contains('vendor/thumbfast.lua','user-data/frontend/process-path')
    contains('scripts/sub-select.lua','"select-subtitles"')
    contains('scripts/uosc/lib/buttons.lua',"'set-button'")
    contains('vendor/uosc/main.lua',"'update-menu'")
    contains('scripts/theintrodb.lua','user-data/skip-prompt')
    contains('scripts/theintrodb.lua','user-data/autochapters-media')

    contains('scripts/uosc/elements/Timeline.lua','function Timeline:get_time_at_x(x)')
    contains('scripts/uosc/elements/Timeline.lua','function Timeline:handle_cursor_down()')
    contains('scripts/uosc/elements/Speed.lua','function Speed:handle_wheel_up()')
    contains('scripts/uosc/elements/Volume.lua','self.slider = VolumeSlider:new')
    contains('scripts/uosc/elements/TopBar.lua','function TopBar:update_dimensions()')
    contains('scripts/uosc/elements/Button.lua','function Button:handle_cursor_click()')
    contains('scripts/uosc/lib/menus.lua','function create_self_updating_menu_opener(opts)')
    dofile(path('maintenance/ui-tests.lua'))(path)
    dofile(path('maintenance/ontop-tests.lua'))(path)
    dofile(path('maintenance/interface-tests.lua'))(path)
    dofile(path('maintenance/controls-visibility-tests.lua'))(path)
    dofile(path('maintenance/title-tests.lua'))(path)
    dofile(path('maintenance/anime-tests.lua'))(path)
    dofile(path('maintenance/title-runtime-tests.lua'))(path)
    dofile(path('maintenance/lampa-context-tests.lua'))(path)
    dofile(path('maintenance/identity-reconcile-tests.lua'))(path)
    dofile(path('maintenance/identity-runtime-tests.lua'))(path)
    dofile(path('maintenance/source-runtime-tests.lua'))(path)
    dofile(path('maintenance/torrserver-open-tests.lua'))(path)
    dofile(path('maintenance/playback-tests.lua'))(path)
    dofile(path('maintenance/network-runtime-tests.lua'))(path)
    dofile(path('maintenance/update-runtime-tests.lua'))(path)
    dofile(path('maintenance/torrent-panel-tests.lua'))(path)
    dofile(path('maintenance/skip-preferences-tests.lua'))(path)
    dofile(path('maintenance/skip-notice-tests.lua'))(path)
    dofile(path('maintenance/skip-transition-tests.lua'))(path)
    dofile(path('maintenance/consecutive-skip-tests.lua'))(path)

    local torrent=dofile(path('extensions/torrserver.lua'))
    local matches=torrent.matcher('http://someone%40example.invalid:secret@EXAMPLE.invalid:80')
    assert(matches('http://example.invalid/stream?link=abc'))
    assert(matches('edl://!new_stream;%40%http://example.invalid/stream?link=abc'))
    assert(not matches('http://example.invalid.evil/stream'))
    assert(not matches('http://example.invalid:8090/stream'))
    assert(not matches('https://example.invalid/stream'))
    assert(not matches(''))
    assert(torrent.matcher('http://localhost:8090')('http://127.0.0.1:8090/stream'))
    assert(torrent.matcher('https://[::1]:443')('https://localhost/stream'))
    assert(torrent.translate('Select an entry of torrent:')=='Выберите серию:')

    -- Exercise upstream sub-select itself, including its public reselect message.
    local props={['options/sid']='auto',aid=1,['track-list']={
        {type='audio',id=1,lang='rus'},
        {type='sub',id=1,lang='rus',forced=true},
        {type='sub',id=2,lang='rus',title='Полные'},
        {type='sub',id=3,lang='eng',title='Full'},
    }}
    local messages,hooks,bindings,events,timers={},{},{},{},{}
    local function noop() end
    local function get(k,d) local v=props[k]; if v==nil then return d end; return v end
    local function set(k,v) props[k]=v end
    local mock={
        get_property=get,get_property_native=get,get_property_number=get,get_property_bool=get,
        set_property=set,set_property_native=set,set_property_number=set,
        get_script_name=function() return 'autocrop' end,
        get_time=function() return 1 end,
        command_native=function(args)
            assert(args[1]=='expand-path')
            return (args[2]:gsub('^~~/',root..'/'))
        end,
        commandv=function(a,b,c,d)
            if a=='no-osd' and b=='set' then set(c,d) end
        end,
        observe_property=function(k,_,fn) if k=='track-list/count' then hooks.read=fn end end,
        unobserve_property=noop,osd_message=noop,
        add_hook=function(name,priority,fn) hooks[name..priority]=fn end,
        register_event=function(name,fn) events[name]=fn end,
        add_key_binding=function(_,name,fn) bindings[name]=fn end,
        register_script_message=function(name,fn) messages[name]=fn end,
        add_periodic_timer=function(_,fn)
            local timer={callback=fn,active=true,kill=function(self) self.active=false end}
            timers[#timers+1]=timer; return timer
        end,
        msg=setmetatable({},{__index=function() return noop end}),
    }
    local saved={}
    for _,name in ipairs({'mp','mp.msg','mp.options'}) do saved[name]=package.loaded[name] end
    mp=mock; package.loaded.mp=mock; package.loaded['mp.msg']=mock.msg
    package.loaded['mp.options']={read_options=noop}
    dofile(path('scripts/sub-select.lua'))
    hooks.read()
    for mode,id in pairs({forced_ru=1,full_ru=2,full_en=3,off='no'}) do
        props['user-data/language-defaults/subtitles']=mode
        messages['select-subtitles']()
        assert(props['file-local-options/sid']==id,'subtitle mode '..mode)
    end
    props['track-list'][2].forced=false
    props['track-list'][2].title='Надписи (Forced)'
    props['user-data/language-defaults/subtitles']='forced_ru'
    messages['select-subtitles'](); assert(props['file-local-options/sid']==1,'forced title fallback')
    props['track-list']={{type='audio',id=1,lang='eng'},{type='sub',id=1,lang='eng'}}
    hooks.read(); messages['select-subtitles']()
    assert(props['file-local-options/sid']=='no','missing Russian subtitles')

    -- Continuous crop: two samples, pause stability, return to full-frame,
    -- invalid/dark samples, current-file opt-out. No user settings are written.
    local cropTimers={}
    local crop_attempts=0
    local function cleanup()
        for k,t in pairs(cropTimers) do t:kill(); cropTimers[k]=nil end
    end
    local opts={auto=true,auto_delay=0,auto_fill=true,check_interval=1,detect_seconds=0.2,detect_min_ratio=0.5}
    props['time-pos']=0; props.width=1920; props.height=1080; props['video-crop']=''
    props['vf-metadata/autocrop-cropdetect']={['lavfi.cropdetect.w']='1920',['lavfi.cropdetect.h']='800',['lavfi.cropdetect.x']='0',['lavfi.cropdetect.y']='140'}
    mock.commandv=function(a,b,c,d)
        if a=='no-osd' and b=='set' then props[c]=d; if c=='file-local-options/video-crop' then props['video-crop']=d end end
    end
    dofile(path('extensions/autocrop.lua'))({
        options=opts,timers=cropTimers,label='autocrop-cropdetect',
        cleanup=cleanup,remove_cropdetect=noop,restore_hwdec=noop,
        start_detection=function()
            crop_attempts=crop_attempts+1
            if crop_attempts>1 then cropTimers.detect_crop={kill=noop} end
        end,
    })
    local function tick(seconds,paused)
        props.pause=paused
        for _=1,math.ceil(seconds/0.1) do
            if not paused then props['time-pos']=props['time-pos']+0.1 end
            local count=#timers
            for i=1,count do if timers[i].active then timers[i].callback() end end
        end
    end
    events['file-loaded']()
    tick(0.4,false); assert(props['video-crop']=='','crop waits for confirmation')
    tick(2,true); assert(props['video-crop']=='','pause does not consume sample')
    tick(1.4,false); assert(crop_attempts>=3 and props['video-crop']=='1920x800+0+140','first-file crop retries when the decoder is initially unready')
    props.width=nil;props.height=nil;tick(3,false)
    assert(props['video-crop']=='1920x800+0+140','Temporary missing decoder dimensions keep the last crop')
    props.width=1920;props.height=1080
    props['vf-metadata/autocrop-cropdetect']['lavfi.cropdetect.w']='-16'
    tick(3,false); assert(props['video-crop']=='1920x800+0+140','invalid sample retains crop')
    props['vf-metadata/autocrop-cropdetect']={['lavfi.cropdetect.w']='1920',['lavfi.cropdetect.h']='1080',['lavfi.cropdetect.x']='0',['lavfi.cropdetect.y']='0'}
    tick(3,false); assert(props['video-crop']=='','full frame restored')
    bindings.fit(); assert(props['user-data/autocrop/active']==false,'manual framing suspends scanning')
    events['file-loaded'](); assert(props['user-data/autocrop/active']==true,'new file resumes automatic scanning')
    events['end-file']()
    mp=real
    for name,value in pairs(saved) do package.loaded[name]=value end
end
local ok,err=xpcall(tests,debug.traceback)
mp=real
if ok then print('MPV_EXTENSIONS_OK') else print('MPV_EXTENSIONS_FAILED: '..tostring(err)) end
real.commandv('quit',ok and 0 or 1)
