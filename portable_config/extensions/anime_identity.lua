-- Season-aware anime identity. Never substitute season one for an unknown season.
local folder=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]'))
local root=folder..'/..'
local shared='mpv-plus/anime-identity/'..root:gsub('\\','/')
if package.loaded[shared] then return package.loaded[shared] end
local fmt=dofile(folder..'/title_format.lua')
local M={}
local cached, catalog
function M.catalog()
    if catalog then return catalog end
    local file=io.open(root..'/data/anime-catalog.json','rb')
    if not file then return {} end
    catalog=require('mp.utils').parse_json(file:read('*a'));file:close()
    return catalog or {}
end
function M.invalidate() cached=nil end
local function copy(value) local result={};for k,v in pairs(value) do result[k]=v end;return result end
function M.index(database)
    local result={}
    for name,id in pairs(database or {}) do
        if type(name)=='string' and tonumber(id) then
            local key=fmt.normalize(name);id=tostring(id)
            if result[key] and result[key]~=id then result[key]=false
            elseif result[key]==nil then result[key]=id end
        end
    end
    return result
end
function M.database()
    if cached then return cached end
    local file=io.open(root..'/scripts/autochapters/anime.json','rb')
    if not file then return {} end
    local data=require('mp.utils').parse_json(file:read('*a'));file:close()
    cached=M.index(data);return cached
end
local function ordinal(n)
    local last=n%10
    local suffix=(n%100>=11 and n%100<=13) and 'th' or ({[1]='st',[2]='nd',[3]='rd'})[last] or 'th'
    return tostring(n)..suffix
end
local function season_id(title,season,index)
    local hits={}
    for _,suffix in ipairs({ordinal(season)..' Season','Season '..season,'S'..season,tostring(season)}) do
        local id=index[fmt.normalize(title..' '..suffix)]
        if id then hits[id]=true end
    end
    local id,count=nil,0
    for key in pairs(hits) do id=key;count=count+1 end
    return count==1 and id or nil
end
local function release_arc(title,number,index)
    local id=index[fmt.normalize(title)]
    local base=id and M.catalog()[tostring(id)]
    if not base or not base.tmdb_id then return end
    local match
    -- Keep verified release ordinals available with the clean bundled catalog,
    -- which predates the optional tv_number annotations in rebuilt snapshots.
    local release_numbers={['55701']=4}
    for id,entry in pairs(M.catalog())do
        if entry.tmdb_id==base.tmdb_id and entry.kind=='tv' and (entry.tv_number or release_numbers[tostring(id)])==number then
            if match then return end
            match=id
        end
    end
    return match
end
local function identify(data,index)
    data=copy(data)
    if fmt.normalize(data.title)=='' then data.anime=false;return data end
    local direct=index[fmt.normalize(data.title)]
    local release_base,release_number=data.title:match('^(.-)%s+[Tt][Vv]%s*%-%s*(%d+)%s*$')
    local arc=release_base and release_arc(release_base,tonumber(release_number),index)
    if arc then
        data.title=release_base;data.season=M.catalog()[arc].season;data.season_inferred=nil;direct=arc
    end
    local base,n=data.title:match('^(.-)%s+(%d+)[snrt][tdh]%s+[Ss]eason$')
    if not base then base,n=data.title:match('^(.-)%s+[Ss]eason%s+(%d+)$') end
    if not base then base,n=data.title:match('^(.-)%s+(%d+)$') end
    n=tonumber(n)
    if base and n and n>=1 and n<=20 and index[fmt.normalize(base)] then
        local resolved=n==1 and index[fmt.normalize(base)] or season_id(base,n,index)
        if resolved and (n==1 or resolved~=index[fmt.normalize(base)]) then
            data.title,data.season,direct,data.season_inferred=base,n,resolved,nil
        end
    end
    local base_id=index[fmt.normalize(data.title)]
    local direct_metadata=direct and M.catalog()[tostring(direct)]
    if direct_metadata and (not data.season or data.season_inferred or direct_metadata.season==data.season) then
        data.mal_id=direct
        if not data.season or data.season_inferred then data.season=direct_metadata.season;data.season_inferred=nil end
    elseif (data.season or 1)>1 then
        data.mal_id=season_id(data.title,data.season,index)
    else data.mal_id=direct or base_id end
    data.anime=base_id~=nil and base_id~=false or direct~=nil and direct~=false or data.mal_id~=nil
    if data.anime and (data.episode or data.season) then data.kind='tv' end
    local metadata=data.mal_id and M.catalog()[tostring(data.mal_id)]
    if metadata then
        -- An explicit conflicting release year can identify a live-action remake.
        -- Keep the source identity instead of substituting an anime namesake.
        if data.year and metadata.year and math.abs(tonumber(data.year)-metadata.year)>1 then
            data.anime,data.mal_id=false,nil
        elseif metadata.tmdb_id and (not data.tmdb_id or tostring(data.tmdb_id)==tostring(metadata.tmdb_id)) then
            data.tmdb_id=metadata.tmdb_id
            data.tmdb_season=metadata.season
            data.tmdb_offset=metadata.offset or 0
            data.kind=metadata.kind
        end
    end
    return data
end
function M.enrich(raw,data,index)
    index=index or M.database()
    local result=identify(data,index)
    -- Release TV-4 is not necessarily TMDB season 4. Use only an explicit,
    -- curated arc mapping; for this series TMDB includes the separate train arc.
    local tv=fmt.decode(raw or ''):match('[Tt][Vv]%s*%-%s*(%d+)')
    if tv then
        local arc=release_arc(data.title,tonumber(tv),index)
        if arc then
            result=copy(data);result.title=data.title;result.mal_id=arc;result.anime=true
            local entry=M.catalog()[arc]
            result.kind='tv';result.season=entry.season;result.season_inferred=nil
            result.tmdb_id=entry.tmdb_id;result.tmdb_season=entry.season;result.tmdb_offset=entry.offset or 0
        end
    end
    -- Leading episode numbers are stripped only after a database-confirmed anime match.
    local name=fmt.decode(raw or ''):gsub('^.*[/\\]','')
    local episode,rest=name:match('^(%d%d?%d?%d?)%.%s+(.+)$')
    if episode and tonumber(episode)>0 then
        local candidate=identify(fmt.parse(rest),index)
        if candidate.anime then
            candidate.episode=tonumber(episode);candidate.season=candidate.season or 1;candidate.kind='tv'
            return candidate
        end
    end
    return result
end
function M.from_source(raw,context,index)
    index=index or M.database()
    local parsed=fmt.parse(raw)
    local result=M.enrich(raw,parsed,index)
    context=context or {}
    -- Bare episode filenames (02.mkv) also occur as exact titles in anime
    -- catalogs. A numeric filename alone cannot identify that unrelated film.
    if (parsed.title or ''):match('^%d%d?%d?$') then
        result=copy(parsed)
        result.anime=false;result.episode=tonumber(parsed.title);result.kind='tv'
        result.season=nil;result.season_inferred=nil
    end
    local metadata=result.mal_id and M.catalog()[tostring(result.mal_id)]
    if (context.pending or context.unavailable) and result.episode
        and not (metadata and metadata.season and metadata.season>1) then
        -- A generic franchise filename is not evidence that this is season one.
        result.unresolved_context=true
        result.season,result.tmdb_season,result.tmdb_offset,result.tmdb_episode,result.mal_id,result.episode_title=nil,nil,nil,nil,nil,nil
        return result
    end
    local name=fmt.without_dimensions(fmt.decode(context.path or raw or '')):gsub('^.*[/\\]','')
    local episode,rest=name:match('^(%d%d?%d?%d?)[%.%s_%-]+(.+)$')
    if not episode then episode=name:match('^(%d%d?%d?%d?)%.[mM][kK][vV]$') end
    local number=tonumber(episode) or fmt.parse(name).episode or result.episode
    if not number or number<1 or number>1899 then return result end
    local candidates={}
    local parent=(context.path or ''):match('^(.*)[/\\][^/\\]+$')
    while parent and parent~='' and #candidates<3 do
        local name=parent:match('([^/\\]+)$') or parent
        if name:match('^%a:$') then break end
        candidates[#candidates+1]=name
        parent=parent:match('^(.*)[/\\][^/\\]+$')
    end
    candidates[#candidates+1]=context.title or ''
    for _,title in ipairs(candidates) do
        local data=M.enrich(title,fmt.parse(title),index)
        if data.anime then
            local metadata=data.mal_id and M.catalog()[tostring(data.mal_id)]
            -- A specific named arc in the torrent folder outranks the generic
            -- franchise name in an episode file. A generic base folder cannot
            -- overwrite an explicitly numbered sequel.
            if not (metadata and metadata.season==1 and (metadata.offset or 0)==0
                and result.season and result.season>1 and not result.season_inferred) then
                data.episode=number;data.season=data.season or result.season or 1;data.kind='tv'
                if metadata and metadata.season and metadata.season>0 and (metadata.offset or 0)==0 then
                    data.season=metadata.season
                    data.tmdb_season=metadata.season
                end
                data.tmdb_episode=number+(data.tmdb_offset or 0)
                data.episode_title=result.episode_title
                if not data.episode_title and rest and not rest:lower():match('^%w%w%w$')
                    and not M.enrich(rest,fmt.parse(rest),index).anime then
                    data.episode_title=fmt.parse(rest).title
                end
                return data
            end
        elseif data.kind=='tv' and data.season~=nil and not data.season_inferred and data.title~='' then
            -- Non-anime releases can also put the explicit season in the
            -- parent folder and only an episode number in the actual file.
            data.episode=number;data.tmdb_season=data.season;data.tmdb_episode=number;data.source_confirmed=true
            return data
        end
    end
    return result
end
package.loaded[shared]=M
return M
