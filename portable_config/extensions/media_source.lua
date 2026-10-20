-- Resolve the current TorrServer file independently of the configured library server.
local M={}
function M.stream(path)
    -- EDL can include external audio streams; the first stream identifies the video.
    local url=(path or ''):match('(https?://[^%s;]+)')
    if not url then return end
    local authority,route,query=url:match('^(https?://[^/?#]+)(/[^?#]*)%?([^#]*)')
    if not authority then return end
    -- Official M3U links append an escaped filename after /stream/.
    local prefix=route:match('^(.-)/stream$') or route:match('^(.-)/stream/[^/]+$')
    if not prefix then return end
    local params={}
    for pair in query:gmatch('[^&]+') do
        local key,value=pair:match('^([^=]+)=(.*)$')
        if key then params[key]=value end
    end
    local hash=params.link
    if not hash or #hash~=40 or hash:find('[^%x]') then return end
    local scheme,host=authority:match('^(https?)://(.+)$')
    host=host:match('.*@(.+)') or host
    host=host:lower():gsub(scheme=='https' and ':443$' or ':80$','')
    local name,port=host:match('^(.-)(:%d+)$')
    name=name or host
    if name=='127.0.0.1' or name=='[::1]' then name='localhost' end
    host=name..(port or '')
    local origin=scheme..'://'..host..prefix
    local stat={}
    for pair in query:gmatch('[^&]+') do
        local key=pair:match('^([^=]+)')
        if key~='index' and key~='play' and key~='stat' then stat[#stat+1]=pair end
    end
    stat[#stat+1]='stat'
    return {hash=hash:lower(),index=tonumber(params.index),origin=origin,key=origin..'|'..hash:lower(),
        url=authority..prefix..'/stream?'..table.concat(stat,'&')}
end
-- Library credentials apply only to the exact origin already playing.
-- The playback link can be public while /stream?stat and /cache require Basic auth.
function M.authorize(stream,server)
    if not stream or stream.url:match('^https?://[^/]*@') then return stream end
    local configured=M.stream((server.scheme or 'http')..'://'..(server.host or '')..':'..(server.port or '8090')..'/stream?link='..stream.hash)
    if not configured then return stream end
    local active_origin=stream.origin:match('^https?://[^/]+')
    if active_origin~=configured.origin then return stream end
    local userinfo=configured.url:match('^https?://([^/]+)@')
    if not userinfo then return stream end
    local out={};for k,v in pairs(stream)do out[k]=v end
    out.url=stream.url:gsub('^(https?://)',function(scheme)return scheme..userinfo..'@'end,1)
    return out
end
function M.request_stream(path)
    local stream=M.stream(path)
    if not stream then return end
    local server={scheme='http',host='127.0.0.1',port='8090',use_edl=true}
    dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua').options(server,'torrserver-loader')
    return M.authorize(stream,server)
end
function M.current(media)
    local path=media or mp.get_property('path','')
    local context=mp.get_property_native('user-data/torrserver-context',{})
    if type(context)=='table' and context.media==path then return context end
    local stream=M.stream(path)
    local active=type(context)=='table' and M.stream(context.media or '')
    if stream and active and stream.key==active.key then
        for _,file in ipairs(context.files or {}) do
            if tonumber(file.id)==stream.index and type(file.path)=='string' then
                local scoped={};for k,v in pairs(context)do scoped[k]=v end
                scoped.media=path;scoped.path=file.path;scoped.file_size=tonumber(file.length)
                return scoped
            end
        end
    end
    if stream then return {media=path,pending=true} end
    if not path:find('://',1,true) then return {path=path} end
    return {}
end
-- Expand a single incoming episode only. Existing playlists belong to the
-- caller, and the currently playing entry must never be reloaded or replaced.
function M.complete_playlist(context)
    local path=mp.get_property('path','')
    local stream=M.stream(path)
    if not stream or context.media~=path or context.hash~=stream.hash or type(context.files)~='table' then return end
    local list=mp.get_property_native('playlist',{})
    if #list~=1 or mp.get_property_number('playlist-pos',-1)~=0 then return end
    local current=M.stream(list[1].filename or '')
    if not current or current.key~=stream.key or current.index~=stream.index then return end
    local video,audio={},{}
    local video_ext={};for ext in ('3g2 3gp aaf asf avchd avi drc flv m2ts m2v m4p m4v mkv mng mov mp2 mp4 mpe mpeg mpg mpv mts mxf nsv ogv qt rm rmvb roq svi ts vob webm wmv yuv'):gmatch('%S+')do video_ext[ext]=true end
    local audio_ext={};for ext in ('aac aiff ape au dff dsf flac gsm it m4a mid mod mp3 mpa mpga oga ogg opus ra s3m sid spx wav wma xm ac3 aif amr mka'):gmatch('%S+')do audio_ext[ext]=true end
    for _,file in ipairs(context.files)do
        local ext=type(file.path)=='string' and file.path:match('%.([^%.]+)$')
        ext=ext and ext:lower()
        if tonumber(file.id) and ext then
            if video_ext[ext] then video[#video+1]=file
            elseif audio_ext[ext] then audio[#audio+1]=file end
        end
    end
    local files=#video>0 and video or audio
    if #files<2 then return end
    table.sort(files,function(a,b)return tonumber(a.id)<tonumber(b.id)end)
    local selected
    for i,file in ipairs(files)do if tonumber(file.id)==stream.index then selected=i end end
    if not selected then return end
    local base=stream.url:gsub('[?&]stat$','')
    local playlist={'#EXTM3U'}
    for i,file in ipairs(files)do
        if i~=selected then
            playlist[#playlist+1]='#EXTINF:0,'..file.path:gsub('[\r\n]',' ')
            playlist[#playlist+1]=base..'&index='..tonumber(file.id)..'&play'
        end
    end
    -- Append instead of replacing the playing entry. Titles arrive before the
    -- next episode is opened, including filenames with commas and Unicode.
    mp.commandv('loadlist','memory://'..table.concat(playlist,'\n'),'append')
    for i=1,selected-1 do mp.commandv('playlist-move',i,i-1)end
end
function M.install()
    local utils=require 'mp.utils'
    local subprocess=utils.subprocess
    local cached,failed,pending,request_key,request_id,retry_timer
    local attempts=0
    local function publish()
        local path=mp.get_property('path','')
        local stream=M.stream(path)
        local context={}
        if stream then
            context={media=path,hash=stream.hash,origin=stream.origin,pending=not (cached and cached.key==stream.key),
                unavailable=failed==stream.key or nil}
            if context.unavailable then context.pending=nil end
            if cached and cached.key==stream.key then
                context.pending=nil
                for _,file in ipairs(cached.data.file_stats or {}) do
                    if tonumber(file.id)==stream.index and type(file.path)=='string' then
                        context.path=file.path;context.title=cached.data.name or cached.data.title
                        context.file_size=tonumber(file.length)
                        context.files=cached.data.file_stats
                        break
                    end
                end
                if not context.path then context.unavailable=true end
            end
        end
        local previous=mp.get_property_native('user-data/torrserver-context',{})
        if previous.media~=context.media or previous.path~=context.path or previous.title~=context.title or previous.file_size~=context.file_size
            or previous.pending~=context.pending or previous.unavailable~=context.unavailable
            or (previous.files==nil)~=(context.files==nil) then
            mp.set_property_native('user-data/torrserver-context',context)
        end
        M.complete_playlist(context)
    end
    local function accept(data,stream)
        if type(data)~='table' or type(data.hash)~='string' or data.hash:lower()~=stream.hash
            or type(data.file_stats)~='table' then return false end
        cached={key=stream.key,data=data};failed=nil
        return true
    end
    utils.subprocess=function(args,...)
        local result=subprocess(args,...)
        if type(result)=='table' and result.status==0
            and type(result.stdout)=='string' and result.stdout:find('"file_stats"',1,true) then
            local argv=type(args)=='table' and args.args or {}
            local stream=M.stream(argv[#argv])
            local active=M.stream(mp.get_property('path',''))
            if stream and active and stream.key==active.key then
                local ok,data=pcall(utils.parse_json,result.stdout)
                if ok and accept(data,stream) then publish() end
            end
        end
        return result
    end
    local function resolve()
        local stream=M.request_stream(mp.get_property('path',''))
        if not stream or not stream.index then publish();return end
        if cached and cached.key==stream.key or pending==stream.key or failed==stream.key and (retry_timer or attempts>=3) then publish();return end
        if request_key~=stream.key then attempts=0 end
        if retry_timer then retry_timer:kill();retry_timer=nil end
        if request_id and mp.abort_async_command then mp.abort_async_command(request_id) end
        pending,request_key=stream.key,stream.key
        publish()
        local key=stream.key
        attempts=attempts+1
        request_id=mp.command_native_async({name='subprocess',playback_only=false,capture_stdout=true,capture_stderr=true,
            args={'curl','--silent','--fail','--connect-timeout','2','--max-time','3','--max-filesize','8388608',stream.url}},function(ok,result)
            if request_key~=key then return end
            pending,request_id=nil,nil
            local active=M.stream(mp.get_property('path',''))
            if not active or active.key~=key then return end
            local data=ok and result and result.status==0 and utils.parse_json(result.stdout or '')
            if not accept(data,stream) and not (cached and cached.key==key) then
                failed=key
                if attempts<3 then retry_timer=mp.add_timeout(1.5*attempts,function()
                    retry_timer=nil
                    local current=M.stream(mp.get_property('path',''))
                    if current and current.key==key then failed=nil;resolve() end
                end) end
            end
            publish()
        end)
    end
    mp.observe_property('path','string',publish)
    mp.register_event('file-loaded',function()
        if failed and not pending then
            if retry_timer then retry_timer:kill();retry_timer=nil end
            failed=nil;attempts=0
        end
        resolve()
    end)
    mp.register_event('shutdown',function()
        request_key=nil
        if retry_timer then retry_timer:kill();retry_timer=nil end
        if request_id and mp.abort_async_command then mp.abort_async_command(request_id) end
    end)
end
return M
