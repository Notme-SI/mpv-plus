-- Resolve the current TorrServer file independently of the configured library server.
local M={}
function M.stream(path)
    -- EDL can include external audio streams; the first stream identifies the video.
    local url=(path or ''):match('(https?://[^%s;]+)')
    if not url then return end
    local authority,route,query=url:match('^(https?://[^/?#]+)(/[^?#]*)%?([^#]*)')
    if not authority or not route:match('/stream$') then return end
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
    local prefix=route:sub(1,-8)
    local origin=scheme..'://'..host..prefix
    local stat={}
    for pair in query:gmatch('[^&]+') do
        local key=pair:match('^([^=]+)')
        if key~='index' and key~='play' and key~='stat' then stat[#stat+1]=pair end
    end
    stat[#stat+1]='stat'
    return {hash=hash:lower(),index=tonumber(params.index),origin=origin,key=origin..'|'..hash:lower(),
        url=authority..route..'?'..table.concat(stat,'&')}
end
function M.current()
    local path=mp.get_property('path','')
    local context=mp.get_property_native('user-data/torrserver-context',{})
    if type(context)=='table' and context.media==path then return context end
    local stream=M.stream(path)
    if stream then return {media=path,pending=true} end
    if not path:find('://',1,true) then return {path=path} end
    return {}
end
function M.install()
    local utils=require 'mp.utils'
    local subprocess=utils.subprocess
    local cached,failed,pending,request_key,request_id
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
                        context.files=cached.data.file_stats
                        break
                    end
                end
                if not context.path then context.unavailable=true end
            end
        end
        local previous=mp.get_property_native('user-data/torrserver-context',{})
        if previous.media~=context.media or previous.path~=context.path or previous.title~=context.title
            or previous.pending~=context.pending or previous.unavailable~=context.unavailable
            or (previous.files==nil)~=(context.files==nil) then
            mp.set_property_native('user-data/torrserver-context',context)
        end
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
        local stream=M.stream(mp.get_property('path',''))
        if not stream or not stream.index then publish();return end
        if cached and cached.key==stream.key or failed==stream.key or pending==stream.key then publish();return end
        if request_id and mp.abort_async_command then mp.abort_async_command(request_id) end
        pending,request_key=stream.key,stream.key
        publish()
        local key=stream.key
        request_id=mp.command_native_async({name='subprocess',playback_only=false,capture_stdout=true,capture_stderr=true,
            args={'curl','--silent','--fail','--connect-timeout','2','--max-time','3','--max-filesize','8388608',stream.url}},function(ok,result)
            if request_key~=key then return end
            pending,request_id=nil,nil
            local active=M.stream(mp.get_property('path',''))
            if not active or active.key~=key then return end
            local data=ok and result and result.status==0 and utils.parse_json(result.stdout or '')
            if not accept(data,stream) and not (cached and cached.key==key) then failed=key end
            publish()
        end)
    end
    mp.observe_property('path','string',publish)
    mp.register_event('file-loaded',resolve)
    mp.register_event('shutdown',function()
        request_key=nil
        if request_id and mp.abort_async_command then mp.abort_async_command(request_id) end
    end)
end
return M
