-- Verified Lampa card data, scoped to the current stream. No network calls or persistent bindings.
local folder=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]'))
local fmt=dofile(folder..'/title_format.lua')
local anime=dofile(folder..'/anime_identity.lua')
local source=dofile(folder..'/media_source.lua')
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
    -- Native Lampa Desktop can pass this directly through its existing spawn
    -- API. Hex keeps JSON commas and Unicode out of mpv's option grammar.
    local encoded=mp.get_opt and mp.get_opt('mpv_plus_lampa_context')
    if type(encoded)=='string' and #encoded<=22000 and #encoded%2==0 and not encoded:find('[^%x]') then
        value=encoded:gsub('%x%x',function(pair)return string.char(tonumber(pair,16)) end)
    end
    if not value or #value>30000 then return payload end
    local ok,data=pcall(require('mp.utils').parse_json,value)
    if ok and type(data)=='table' and data.version==1 and data.source=='lampa' and type(data.entries)=='table' then
        payload=data.entries
    end
    return payload
end
local function coordinates(data)
    if data.kind=='tv' then
        data.tmdb_season=data.tmdb_season or data.season
        data.tmdb_episode=data.tmdb_episode or (data.episode and data.episode+(data.tmdb_offset or 0))
    end
    return data
end
local function physical_path(context)
    if context.path then return context.path end
    local path=mp.get_property('path','')
    if not path:find('://',1,true) then return path end
    -- A direct named video URL is independent evidence too. Manifest names,
    -- opaque endpoints and TorrServer's /stream are not movie titles.
    local name=path:match('^https?://[^/]+/([^?#]+)')
    name=name and fmt.decode(name):match('([^/]+)$')
    if not name or not name:lower():match('%.mkv$') and not name:lower():match('%.mp4$')
        and not name:lower():match('%.avi$') and not name:lower():match('%.mov$') then return '' end
    local parsed=fmt.parse(name)
    local title=fmt.normalize(parsed.title or '')
    if #title<4 or title=='video' or title=='stream' or title=='file' or title:match('^%x+$') then return '' end
    return name
end
-- A card is a scoped hint, never an instruction to replace stronger file data.
-- This function is shared by the title renderer, TheIntroDB and AniSkip.
function M.reconcile(independent,card,context)
    local own=coordinates(copy(independent))
    if not card then return own end
    context=context or {}
    local function keep(reason)
        own.lampa_check=reason
        return own
    end
    if context.pending then return keep('pending') end
    local physical=physical_path(context)
    local parsed=fmt.parse(physical)
    local episode_name=(physical:match('[^/\\]+$') or physical):match('^%d+[%. _%-]')
    local specific=own.tmdb_id~=nil or own.mal_id~=nil or own.source_confirmed==true
    local explicit=parsed.season~=nil and not parsed.season_inferred
    local known_title=own.source_confirmed or physical~='' and not episode_name and #fmt.normalize(parsed.title or '')>3
        and not (parsed.title or ''):lower():match('^video$')
        and not (parsed.title or ''):lower():match('^stream$')
        and not (parsed.title or ''):match('^%x+$')
    if own.tmdb_id and card.tmdb_id and tonumber(own.tmdb_id)~=tonumber(card.tmdb_id) then return keep('conflict-id') end
    if own.kind~=card.kind and (specific or explicit or known_title) then return keep('conflict-kind') end
    if own.mal_id and card.mal_id and tonumber(own.mal_id)~=tonumber(card.mal_id) then return keep('conflict-arc') end
    if known_title and own.year and card.year and not own.anime and math.abs(own.year-card.year)>1 then return keep('conflict-year') end
    if (specific or explicit) and own.tmdb_season~=nil and card.tmdb_season~=nil
        and own.tmdb_season~=card.tmdb_season then return keep('conflict-season') end
    local physical_episode=parsed.episode or episode_name and tonumber((physical:match('[^/\\]+$') or physical):match('^(%d+)'))
    if physical_episode then
        local actual=own.tmdb_season~=nil and own.tmdb_episode or physical_episode
        local supplied=own.tmdb_season~=nil and card.tmdb_episode or card.episode
        if actual and supplied and actual~=supplied then return keep('conflict-episode') end
    end
    if known_title and not (own.tmdb_id and card.tmdb_id and tonumber(own.tmdb_id)==tonumber(card.tmdb_id)) then
        local names={card.title,card.original_title or ''}
        for _,alias in ipairs(card.aliases or {}) do names[#names+1]=alias end
        local matched=false
        for _,name in ipairs(names) do
            if fmt.normalize(fmt.parse(name).title)==fmt.normalize(own.source_confirmed and own.title or parsed.title) then matched=true;break end
        end
        if not matched then return keep('conflict-title') end
    end
    local result=copy(own)
    -- Uncertain coordinates from a guessed generic title are replaced only by
    -- the exact launched card, after the real torrent file has been checked.
    for _,key in ipairs({'title','original_title','aliases','year','kind','tmdb_id','imdb_id','mal_id','shikimori_id','anime'}) do
        if card[key]~=nil then result[key]=card[key] end
    end
    if not specific and not explicit or own.unresolved_context then
        for _,key in ipairs({'season','episode','tmdb_season','tmdb_episode','tmdb_offset'}) do result[key]=card[key] or own[key] end
    end
    result.unresolved_context=nil
    result.episode_title=card.episode_title
    result.source='lampa'
    result.lampa_check=(specific or explicit or known_title) and 'confirmed' or 'hint'
    return coordinates(result)
end
local function url(value)
    value=value or ''
    -- TorrServer's loader can wrap the same stream in an EDL to attach external tracks.
    if value:match('^edl://') then value=value:match('https?://[^;]+') or value end
    return fmt.decode(value):gsub('&preload$','&play'):gsub('&preload&','&play&')
end
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
    local matched
    for _,entry in ipairs(read()) do
        if type(entry)=='table' and type(entry.url)=='string' then
            if url(entry.url)==url(path) then matched=entry;break end
        end
    end
    -- A shared torrent hash does not identify a file or its season. Metadata
    -- supplied for a sibling is never reused for the current episode.
    if not matched then return end
    local data=sanitize(matched.identity)
    if not data then return end
    if data.kind=='movie' then data.season,data.episode=nil,nil end
    data.input=path
    local hint=enrich(copy(data))
    local context=mp.get_property_native and source.current() or {}
    local independent=anime.from_source(raw or mp.get_property('media-title',''),context)
    if not context.path and not context.pending and mp.get_property('path',''):match('^https?://') then
        local physical=physical_path(context)
        if physical~='' then independent=anime.from_source(physical,{path=physical}) end
    end
    return M.reconcile(independent,hint,context)
end
return M
