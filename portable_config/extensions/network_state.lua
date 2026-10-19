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
    return {download_speed=tonumber(data.download_speed),active_peers=tonumber(data.active_peers),
        connected_seeders=tonumber(data.connected_seeders),capacity=tonumber(value.Capacity),
        filled=tonumber(value.FilledSize or value.Filled)}
end
return M
