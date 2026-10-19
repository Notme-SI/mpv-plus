-- Source metadata only. Crop filters and playback speed do not change these badges.
local M={}
local codecs={h264='H.264',hevc='HEVC',av1='AV1',vp9='VP9',vp8='VP8',mpeg2video='MPEG-2',
    mpeg4='MPEG-4',aac='AAC',ac3='AC-3',eac3='E-AC-3',dts='DTS',truehd='TrueHD',
    flac='FLAC',opus='Opus',vorbis='Vorbis',mp3='MP3',alac='ALAC'}
function M.number(n)
    n=tonumber(n)
    return n and n>0 and n<math.huge and n==n and n or nil
end
function M.codec(value)
    if type(value)~='string' or value=='' then return nil end
    return codecs[value:lower()] or (value:match('^pcm_') and 'PCM') or value:upper()
end
function M.language(value)
    return ({rus='Русский',ru='Русский',eng='English',en='English',jpn='日本語',ja='日本語'})[value] or value
end
function M.describe(video,audio,params,container_fps)
    local out={badges={},summary={}}
    local function add(kind,text)
        if text then out.badges[#out.badges+1]={kind=kind,text=text} end
    end
    if type(video)=='table' and not video.image and not video.albumart then
        params=params or {}
        local w=M.number(video['demux-w']) or M.number(params.w)
        local h=M.number(video['demux-h']) or M.number(params.h)
        if w and h then
            local edge,short=math.max(w,h),math.min(w,h)
            local quality=(edge>=7680 or short>=4320) and '8K' or (edge>=3840 or short>=2160) and '4K'
                or (edge>=2560 or short>=1440) and '1440p' or (edge>=1920 or short>=1080) and '1080p'
                or (edge>=1280 or short>=720) and '720p' or tostring(short)..'p'
            add('quality',quality)
        end
        out.video={width=w,height=h,codec=M.codec(video.codec),profile=video['codec-profile'],decoder=video.decoder}
        add('video',out.video.codec)
        if params.gamma=='pq' or params.gamma=='hlg' then add('hdr','HDR') end
        local fps=M.number(video['demux-fps']) or M.number(container_fps)
        out.video.fps=fps
        if fps then out.fps=string.format('%.3f',fps):gsub('0+$',''):gsub('%.$',''):gsub('%.',',')..' FPS' end
    end
    if type(audio)=='table' then
        out.audio={codec=M.codec(audio.codec),channels=audio['demux-channels'],
            channel_count=M.number(audio['demux-channel-count']),samplerate=M.number(audio['demux-samplerate']),
            bitrate=M.number(audio['demux-bitrate']),language=audio.lang,decoder=audio.decoder}
        add('audio',out.audio.codec)
    end
    local video_parts,audio_parts={},{}
    for _,badge in ipairs(out.badges) do
        if badge.kind~='audio' then video_parts[#video_parts+1]=badge.text end
    end
    if out.fps then video_parts[#video_parts+1]=out.fps end
    if #video_parts>0 then out.summary[#out.summary+1]={kind='video',text=table.concat(video_parts,' · ')} end
    if out.audio then
        local a=out.audio
        if a.language and a.language~='' then audio_parts[#audio_parts+1]=M.language(a.language) end
        if a.codec then audio_parts[#audio_parts+1]=a.codec end
        local layout=({stereo='2.0',mono='1.0'})[a.channels] or a.channels
        if layout and layout~='' then audio_parts[#audio_parts+1]=layout
        elseif a.channel_count then audio_parts[#audio_parts+1]=tostring(a.channel_count)..' ch' end
        if a.bitrate then audio_parts[#audio_parts+1]=string.format('%.0f kbps',a.bitrate/1000) end
        if #audio_parts>0 then out.summary[#out.summary+1]={kind='audio',text=table.concat(audio_parts,' · ')} end
    end
    add('fps',out.fps)
    return out
end
return M
