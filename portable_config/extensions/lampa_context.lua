-- Verified Lampa card data, scoped to the current stream. No network calls or persistent bindings.
local folder=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]'))
local fmt=dofile(folder..'/title_format.lua')
local anime=dofile(folder..'/anime_identity.lua')
local M={}
local payload
local function number(value,min,max)
    value=tonumber(value)
    return value and value==math.floor(value) and value>=(min or 1) and value<=(max or 100000000) and value or nil
end
local function text(value)
    return type(value)=='string' and value:gsub('[%z\1-\31]',' '):sub(1,1000) or nil
end
local function copy(value) local out={};for k,v in pairs(value) do out[k]=v end;return out end
local function read()
    if payload~=nil then return payload end
    payload={}
    local value=os.getenv('MPV_PLUS_LAMPA_CONTEXT')
    if not value or #value>30000 then return payload end
    local ok,data=pcall(require('mp.utils').parse_json,value)
    if ok and type(data)=='table' and data.version==1 and data.source=='lampa' and type(data.entries)=='table' then
        payload=data.entries
    end
    return payload
end
local function url(value)
    value=value or ''
    -- TorrServer's loader can wrap the same stream in an EDL to attach external tracks.
    if value:match('^edl://') then value=value:match('https?://[^;]+') or value end
    return fmt.decode(value):gsub('&preload$','&play'):gsub('&preload&','&play&')
end
local function hash(value) return url(value):match('[?&]link=(%x+)') end
local function sanitize(value)
    if type(value)~='table' then return end
    local title=text(value.title)
    if not title or title=='' then return end
    local result={title=title,original_title=text(value.original_title),episode_title=text(value.episode_title),
        kind=value.kind=='tv' and 'tv' or 'movie',year=number(value.year,1870,2200),
        tmdb_id=number(value.tmdb_id),mal_id=number(value.mal_id),shikimori_id=number(value.shikimori_id),
        season=number(value.season,0,999),episode=number(value.episode,1,9999),anime=value.anime==true,aliases={}}
    if type(value.imdb_id)=='string' and value.imdb_id:match('^tt%d+$') then result.imdb_id=value.imdb_id end
    for i,alias in ipairs(type(value.aliases)=='table' and value.aliases or {}) do
        if i>12 then break end
        if text(alias) then result.aliases[#result.aliases+1]=text(alias) end
    end
    return result
end
local function enrich(data)
    local original_episode=data.episode
    -- Try original/alternative titles as well as the localized display name.
    local candidates={data.original_title or '',data.title}
    for _,alias in ipairs(data.aliases or {}) do candidates[#candidates+1]=alias end
    local identified
    -- Lampa's season is a TMDB coordinate, not an ordinal anime season.
    -- Resolve it before title aliases: anime "season 3" may map to TMDB season 4.
    if data.anime and data.tmdb_id and data.season~=nil then
        local best_offset,matches=-1,{}
        for id,entry in pairs(anime.catalog()) do
            local offset=entry.offset or 0
            if tonumber(entry.tmdb_id)==data.tmdb_id and entry.kind==data.kind and entry.season==data.season
                and (original_episode and original_episode>offset or not original_episode and offset==0) then
                if offset>best_offset then best_offset,matches=offset,{} end
                if offset==best_offset then matches[#matches+1]=id end
            end
        end
        if #matches==1 then identified={mal_id=matches[1],tmdb_season=data.season,tmdb_offset=best_offset} end
    end
    for _,title in ipairs(identified and {} or candidates) do
        if title~='' then
            local probe=anime.enrich(title,{title=title,kind=data.kind,season=data.season,episode=data.episode,tmdb_id=data.tmdb_id})
            if probe.mal_id and (not data.tmdb_id or not probe.tmdb_id or tonumber(probe.tmdb_id)==data.tmdb_id)
                and (data.season==nil or probe.tmdb_season==nil or probe.tmdb_season==data.season) then
                identified=probe;break
            end
        end
    end
    if identified then
        data.anime=true
        data.mal_id=number(identified.mal_id)
        if data.shikimori_id then data.shikimori_id=data.mal_id end
        -- Card season/episode are TMDB coordinates. Convert only a verified mapping to AniSkip coordinates.
        local offset=identified.tmdb_offset or 0
        if identified.tmdb_season==data.season and original_episode and original_episode>offset then
            data.episode=original_episode-offset
        end
    end
    local supplied=anime.catalog()[tostring(data.mal_id or data.shikimori_id)]
    if not identified and supplied and data.tmdb_id and tonumber(supplied.tmdb_id)==data.tmdb_id
        and data.season~=nil and supplied.season~=data.season then
        data.mal_id,data.shikimori_id=nil,nil
    end
    if data.mal_id or data.shikimori_id then data.anime=true;data.mal_id=data.mal_id or data.shikimori_id end
    data.tmdb_season=data.season
    data.tmdb_episode=original_episode
    data.tmdb_offset=(original_episode and data.episode) and original_episode-data.episode or 0
    data.source='lampa'
    return data
end
function M.current(raw)
    local path=mp.get_property('path','')
    if path=='' then return end
    local matched,fallback
    for _,entry in ipairs(read()) do
        if type(entry)=='table' and type(entry.url)=='string' then
            if url(entry.url)==url(path) then matched=entry;break end
            local a,b=hash(entry.url),hash(path)
            if a and b and a:lower()==b:lower() then fallback=entry end
        end
    end
    local data=sanitize((matched or fallback or {}).identity)
    if not data then return end
    local parsed=fmt.parse(raw or mp.get_property('media-title',''))
    if not matched then
        -- A sibling torrent file may be another season. Never carry over the previous episode.
        data.season,data.episode,data.episode_title=parsed.season,parsed.episode,parsed.episode_title
        data.mal_id,data.shikimori_id=nil,nil
    else
        data.season=data.season or parsed.season
        data.episode=data.episode or parsed.episode
    end
    if data.kind=='movie' then data.season,data.episode=nil,nil end
    data.input=path
    return enrich(copy(data))
end
return M
