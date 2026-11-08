-- TMDB title logos with the same language priority as Lampa View.
local M={}
local width,height=640,216

function M.choose(logos,language)
    local best,rank
    for _,logo in ipairs(type(logos)=='table' and logos or {}) do
        local path=type(logo)=='table' and logo.file_path
        if type(path)=='string' and (path:match('^/[%w_%-]+%.png$') or path:match('^/[%w_%-]+%.webp$')) then
            local lang=logo.iso_639_1
            local priority=lang==language and 0 or lang=='en' and 1 or (not lang or lang=='null' or lang=='') and 2 or 3
            local candidate={priority,-(tonumber(logo.width) or 0),-(tonumber(logo.vote_count) or 0),path}
            local better=not rank
            if rank then
                for i=1,#candidate do
                    if candidate[i]~=rank[i] then better=candidate[i]<rank[i];break end
                end
            end
            if better then best,rank=path,candidate end
        end
    end
    return best
end

function M.new(root,on_change)
    local utils=require 'mp.utils'
    local temp=os.getenv('TEMP') or os.getenv('TMPDIR')
    if not temp then return {show=function() return false end,hide=function() end} end
    local ffmpeg=utils.join_path(root,'../ffmpeg.exe')
    local id=57 -- thumbfast uses a different overlay ID
    local files,order={},{}
    local identity,job,overlay,serial=nil,nil,nil,0
    local function hide()
        if overlay then mp.command_native({'overlay-remove',id});overlay=nil end
    end
    local function cleanup(j)
        os.remove(j.image)
        os.remove(j.raw)
    end
    local function cancel()
        local old=job;job=nil
        if old and old.request then mp.abort_async_command(old.request) end
    end
    local function subprocess(j,args,callback)
        j.request=mp.command_native_async({name='subprocess',args=args,playback_only=false,
            capture_stdout=true,capture_stderr=true},function(ok,result)
            j.request=nil
            if job~=j then cleanup(j);return end
            if ok and result and result.status==0 then callback(result.stdout)
            else job=nil;cleanup(j) end
        end)
        if not j.request then job=nil;cleanup(j) end
    end
    local function update(_,meta)
        meta=type(meta)=='table' and meta or {}
        local media_id=meta.artwork and tostring(meta.artwork_id or meta.tmdb_id or '')
        local kind,lang=meta.kind,meta.language=='en' and 'en' or 'ru'
        local next_key=media_id and media_id:match('^%d+$') and (kind=='movie' or kind=='tv') and kind..'/'..media_id..':'..lang or nil
        if next_key==identity then return end
        hide();cancel();identity=next_key;on_change()
        if not identity or files[identity]~=nil or not utils.file_info(ffmpeg) then return end
        serial=serial+1
        local stem=utils.join_path(temp,'mpv-plus-logo-'..mp.get_property_number('pid',0)..'-'..serial)
        local j={key=identity,image=stem..'.image',raw=stem..'.bgra'};job=j
        local token=dofile(root..'/extensions/tmdb_client.lua')
        local function request(...)
            local args={'curl','--silent','--fail','--location','--proto','=https','--proto-redir','=https',
                '--connect-timeout','3','--max-time','8','--max-filesize','3145728'}
            for _,arg in ipairs({...}) do args[#args+1]=arg end
            return args
        end
        local endpoint='https://api.themoviedb.org/3/'..kind..'/'..media_id..'/images?include_image_language='..lang..',en,null'
        local function remember(file)
            job=nil;files[j.key]=file;order[#order+1]=j.key
            if #order>16 then
                local old=table.remove(order,1)
                if files[old] then os.remove(files[old]) end
                files[old]=nil
            end
            on_change()
        end
        subprocess(j,request('--header','Authorization: Bearer '..token,endpoint),function(body)
            local images=utils.parse_json(body or '')
            local path=type(images)=='table' and M.choose(images.logos,lang)
            if not path then if type(images)=='table' then remember(false) else job=nil end;return end
            subprocess(j,request('--output',j.image,'https://image.tmdb.org/t/p/w500'..path),function()
                local filter=string.format('scale=%d:%d:force_original_aspect_ratio=decrease,format=gbrap,pad=%d:%d:0:(oh-ih)/2:color=black@0,premultiply=inplace=1,format=bgra',width,height,width,height)
                subprocess(j,{ffmpeg,'-nostdin','-hide_banner','-loglevel','error','-max_pixels','16777216',
                    '-i',j.image,'-frames:v','1','-vf',filter,'-c:v','rawvideo','-threads','1','-f','rawvideo',j.raw},function()
                    os.remove(j.image)
                    local info=utils.file_info(j.raw)
                    if not info or info.size~=width*height*4 then job=nil;cleanup(j);return end
                    remember(j.raw)
                end)
            end)
        end)
    end
    mp.observe_property('user-data/readable-title','native',update)
    mp.register_event('start-file',function() update(nil,nil) end)
    mp.register_event('shutdown',function()
        hide()
        local old=job;cancel();if old then cleanup(old) end
        for _,file in pairs(files) do if file then os.remove(file) end end
    end)
    return {hide=hide,show=function(x,y,w,h)
        local file=identity and files[identity]
        if not file then hide();return false end
        x,y,w,h=math.floor(x+.5),math.floor(y+.5),math.floor(w+.5),math.floor(h+.5)
        local key=table.concat({file,x,y,w,h},'|')
        if overlay==key then return true end
        local _,err=mp.command_native({'overlay-add',id,x,y,file,0,'bgra',width,height,width*4,w,h})
        if err then hide();return false end
        overlay=key
        return true
    end}
end
return M
