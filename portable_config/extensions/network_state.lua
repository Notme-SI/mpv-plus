-- TorrServer pieces and mpv's demuxed packets are separate cache layers.
local M={}
local mib=1048576
M.profiles={normal={seconds=60,bytes=256*mib,back=128*mib,wait=3},large={seconds=180,bytes=512*mib,back=256*mib,wait=4}}
function M.profile(mode,torrent)
    return M.profiles[mode] or (torrent and {seconds=45,bytes=128*mib,back=128*mib,wait=2} or M.profiles.normal)
end
function M.request(stream)
    if not stream then return end
    local base,query=stream.url:match('^(.-)/stream%?(.*)$')
    if not base then return end
    local keep={}
    for pair in query:gmatch('[^&]+') do
        local key=pair:match('^([^=]+)')
        if key~='link' and key~='stat' then keep[#keep+1]=pair end
    end
    return base..'/cache'..(#keep>0 and '?'..table.concat(keep,'&') or '')
end
function M.stats(value)
    if type(value)~='table' then return {unavailable=true} end
    local data=type(value.Torrent)=='table' and value.Torrent or value
    local readers={}
    for _,reader in ipairs(type(value.Readers)=='table' and value.Readers or {})do
        if type(reader)=='table' then readers[#readers+1]={start=tonumber(reader.Start),
            position=tonumber(reader.Reader),finish=tonumber(reader.End)}end
    end
    return {download_speed=tonumber(data.download_speed),active_peers=tonumber(data.active_peers),
        connected_seeders=tonumber(data.connected_seeders),capacity=tonumber(value.Capacity),
        filled=tonumber(value.FilledSize or value.Filled),readers=readers,piece_length=tonumber(value.PiecesLength)}
end
local function positive(n)
    n=tonumber(n);return n and n>0 and n<math.huge and n==n and n or nil
end
-- Time equivalent of bytes belonging to the current file. This is an estimate
-- based on average bitrate, never a promise of continuous playable timestamps.
function M.cache_time(value,index,duration,context)
    if type(value)~='table' or not positive(duration) then return {} end
    context=context or {}
    local files=(type(value.Torrent)=='table' and value.Torrent.file_stats) or context.files or {}
    local ordered={};for _,file in ipairs(files)do ordered[#ordered+1]=file end
    table.sort(ordered,function(a,b)return (tonumber(a.id)or 0)<(tonumber(b.id)or 0)end)
    local offset,size,complete,found=0,nil,true,false
    for i,file in ipairs(ordered)do
        local length=positive(file.length)
        if tonumber(file.id)~=i or not length then complete=false end
        if tonumber(file.id)==tonumber(index) then size=length;found=true;break end
        offset=offset+(length or 0)
    end
    size=size or positive(context.file_size)
    if not size then return {} end
    local bytes,scope
    local piece_length=positive(value.PiecesLength)
    if complete and found and piece_length and type(value.Pieces)=='table' then
        local first,last=offset,offset+size
        -- Readers expose global piece positions. A unique matching reader lets
        -- us exclude old cached data behind the HTTP reader and unrelated files.
        local reader,count=nil,0
        for _,r in ipairs(value.Readers or {})do
            local position=tonumber(r.Reader)
            if position and position*piece_length>=offset-piece_length and position*piece_length<offset+size then
                reader=r;count=count+1
            end
        end
        if count==1 then
            first=math.max(first,tonumber(reader.Reader)*piece_length)
            last=math.min(last,(tonumber(reader.End)or math.ceil((offset+size)/piece_length))*piece_length)
            scope='reader'
        else scope='file' end
        bytes=0
        for key,piece in pairs(value.Pieces)do
            local id=tonumber(piece.Id)or tonumber(key)
            local loaded=tonumber(piece.Size)
            if id and id>=0 and loaded and loaded>=0 and loaded<math.huge then
                local start=id*piece_length
                local span=math.max(0,math.min(start+piece_length,last)-math.max(start,first))
                bytes=bytes+math.min(loaded,piece_length)*span/piece_length
            end
        end
    elseif #ordered==1 and tonumber(ordered[1].id)==tonumber(index) then
        -- A single-file torrent has no other files whose cache could be counted.
        bytes=tonumber(value.FilledSize or value.Filled);scope='file'
    end
    if not bytes or bytes~=bytes or bytes<0 or bytes==math.huge then return {file_size=size} end
    bytes=math.min(bytes,size)
    local rate=size/duration
    local capacity=positive(value.Capacity)
    return {file_size=size,seconds=bytes/rate,target=capacity and math.min(capacity,size)/rate,
        bytes=bytes,scope=scope,estimated=true}
end
function M.player_time(seconds,bytes,size,duration)
    seconds=tonumber(seconds)
    if seconds and seconds>0 and seconds<math.huge then return seconds,false end
    if positive(bytes) and positive(size) and positive(duration) then return bytes*duration/size,true end
    return seconds and seconds>=0 and seconds<math.huge and seconds or nil,false
end
return M
