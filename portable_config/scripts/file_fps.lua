-- Static source metadata, independent of titles, crop and playback speed.
local info=dofile(mp.command_native({'expand-path','~~/extensions/media_info.lua'}))
local loaded=false
local track_id,hdr10plus
local function publish(data)
    mp.set_property_native('user-data/media-info',data)
    mp.set_property('user-data/file-fps/label',data.fps or '')
    mp.set_property('user-data/file-fps/suffix','')
end
local function refresh()
    if not loaded then publish({badges={}});return end
    local video=mp.get_property_native('current-tracks/video')
    local id=video and video.id
    if track_id~=id then track_id,hdr10plus=id,false end
    local params=mp.get_property_native('video-dec-params')
    hdr10plus=hdr10plus or info.has_hdr10plus(params)
    publish(info.describe(video,mp.get_property_native('current-tracks/audio'),params,
        mp.get_property_number('container-fps'),hdr10plus))
end
local function clear()
    loaded,track_id,hdr10plus=false,nil,false
    refresh()
end
mp.register_event('start-file',clear)
mp.register_event('end-file',clear)
mp.register_event('file-loaded',function() loaded=true;refresh() end)
for _,property in ipairs({'current-tracks/video','current-tracks/audio','video-dec-params','container-fps'}) do
    mp.observe_property(property,'native',refresh)
end
refresh()
