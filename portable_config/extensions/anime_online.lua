-- Read-only MAL catalog fallback through Jikan. A search ranking is not an identity.
local folder=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]'))
local fmt=dofile(folder..'/title_format.lua')
local anime=dofile(folder..'/anime_identity.lua')
local M={}
local function copy(value) local out={};for k,v in pairs(value or {})do out[k]=v end;return out end
local function integer(value,maximum)
    value=tonumber(value)
    return value and value==math.floor(value) and value>0 and value<=(maximum or 10000000) and value or nil
end
local function text(value)
    return type(value)=='string' and value:gsub('[%z\1-\31]',' '):sub(1,300) or ''
end
function M.eligible(query,raw,tracks)
    if query.anime==true then return true end
    if query.anime==false and query.source=='lampa' then return false end
    raw=(raw or ''):lower()
    if raw:find('subsplease',1,true) or raw:find('erai%-raws') or raw:find('rus%s*%+%s*jap') then return true end
    for _,track in ipairs(tracks or {})do
        if track.type=='audio' and (track.lang=='jpn' or track.lang=='ja') then return true end
    end
    return false
end
function M.mal_payload(payload)
    if type(payload)~='table' or type(payload.data)~='table' then return end
    local result={data={}}
    for _,entry in ipairs(payload.data)do
        local node=type(entry)=='table' and entry.node
        if type(node)=='table' then
            local titles=type(node.alternative_titles)=='table' and node.alternative_titles or {}
            result.data[#result.data+1]={mal_id=node.id,title=node.title,title_english=titles.en,title_japanese=titles.ja,
                title_synonyms=titles.synonyms,type=({tv='TV',ona='ONA',ova='OVA',movie='Movie',special='Special',tv_special='TV Special'})[node.media_type],
                aired={from=node.start_date},episodes=node.num_episodes,status=node.status=='not_yet_aired' and 'Not yet aired' or nil}
        end
    end
    return result
end
function M.candidates(payload,query)
    local result,seen={},{}
    for _,item in ipairs(type(payload)=='table' and type(payload.data)=='table' and payload.data or {})do
        if type(item)~='table' then item={} end
        local id=integer(item.mal_id)
        if id and not seen[id] and text(item.title)~='' then
            seen[id]=true
            local aliases={text(item.title),text(item.title_english),text(item.title_japanese)}
            for _,title in ipairs(type(item.titles)=='table' and item.titles or {})do if type(title)=='table' then aliases[#aliases+1]=text(title.title) end end
            for _,title in ipairs(type(item.title_synonyms)=='table' and item.title_synonyms or {})do aliases[#aliases+1]=text(title) end
            local candidate={mal_id=id,title=text(item.title),aliases=aliases,media_type=text(item.type),
                year=integer(item.year,2200) or integer(type(item.aired)=='table' and text(item.aired.from):match('^(%d%d%d%d)'),2200),
                episodes=integer(item.episodes,99999),upcoming=item.status=='Not yet aired'}
            if not candidate.upcoming and (not query.episode or not candidate.episodes or query.episode<=candidate.episodes) then
                result[#result+1]=candidate
            end
        end
        if #result>=15 then break end
    end
    return result
end
function M.match(candidate,query)
    if query.year and candidate.year~=query.year then return false end
    if query.kind=='movie' then
        if candidate.media_type~='Movie' then return false end
    elseif query.media_type then
        if candidate.media_type:lower()~=query.media_type:lower() then return false end
    elseif candidate.media_type~='TV' and candidate.media_type~='ONA' then return false end
    local names={query.title or '',query.original_title or ''}
    for _,name in ipairs(query.aliases or {})do names[#names+1]=name end
    local exact=false
    for _,name in ipairs(names)do
        local key=fmt.normalize(name)
        if #key>=3 then
            for _,alias in ipairs(candidate.aliases)do if fmt.normalize(alias)==key then exact=true end end
        end
    end
    if not exact then return false end
    local known=anime.catalog()[tostring(candidate.mal_id)]
    if known and query.tmdb_id and tonumber(known.tmdb_id)~=tonumber(query.tmdb_id) then return false end
    if (query.season or 1)>1 then
        if known and known.season==query.season and (not query.tmdb_id or tonumber(known.tmdb_id)==tonumber(query.tmdb_id)) then return true end
        -- Never map a generic franchise title + S2 to its first MAL entry.
        for _,alias in ipairs(candidate.aliases)do
            local number=alias:match('(%d+)[snrt][tdh]%s+[Ss]eason') or alias:match('[Ss]eason%s+(%d+)')
            if tonumber(number)==query.season then return true end
        end
        return false
    end
    return true
end
function M.identity(candidate,query)
    local result=copy(query)
    result.title=candidate.title;result.mal_id=candidate.mal_id;result.anime=true
    result.media_type=candidate.media_type;result.episodes=candidate.episodes;result.year=candidate.year
    result.kind=candidate.media_type=='Movie' and 'movie' or 'tv'
    result.identity_source='mal-online';result.requested_mal_id=nil
    local known=anime.catalog()[tostring(candidate.mal_id)]
    if known and known.tmdb_id then
        result.tmdb_id=known.tmdb_id;result.tmdb_season=known.season;result.tmdb_offset=known.offset or 0
        result.tmdb_episode=result.episode and result.episode+result.tmdb_offset
    end
    return result
end
function M.choose(candidates,query)
    local selected
    for _,candidate in ipairs(candidates)do
        if M.match(candidate,query) then
            if selected then return nil end
            selected=candidate
        end
    end
    return selected and M.identity(selected,query)
end
function M.new(call,settings,utils,clock,options)
    local cache,last_request,cooldown={},-math.huge,0
    local function load()
        local file=io.open(settings.path('anime-search-cache.json'),'rb')
        if file then local data=utils.parse_json(file:read('*a'));file:close();if type(data)=='table' then cache=data end end
    end
    load()
    local function save()
        local now=os.time();local entries={}
        for key,entry in pairs(cache)do
            if type(entry)=='table' and type(entry.expires)=='number' and entry.expires>now then entries[#entries+1]={key,entry} end
        end
        table.sort(entries,function(a,b)return a[2].expires>b[2].expires end)
        cache={};for i=1,math.min(#entries,64)do cache[entries[i][1]]=entries[i][2] end
        local file=io.open(settings.path('anime-search-cache.json'),'wb')
        if file then file:write(utils.format_json(cache));file:close() end
    end
    return {search=function(query,current)
        local name=text(query.original_title)
        if name=='' then name=text(query.title) end
        if name=='' or name:find('://',1,true) then return {},nil,'invalid' end
        local key='title:'..fmt.normalize(name)
        local entry=cache[key]
        local candidates
        if type(entry)=='table' and type(entry.expires)=='number' and entry.expires>os.time() and type(entry.payload)=='table' then
            candidates=M.candidates(entry.payload,query)
        else
            if clock()<cooldown or clock()-last_request<1.1 then return {},nil,'busy' end
            last_request=clock()
            local encoded=name:gsub('[^%w%-%.%_%~]',function(c)return string.format('%%%02X',c:byte()) end)
            local client=options and options.mal_client_id or ''
            local official=type(client)=='string' and #client>0 and #client<=200 and not client:find('[^%w_%-]')
            local url='https://api.jikan.moe/v4/anime?limit=15&q='..encoded
            local args={'curl.exe','-fsS','--globoff','--connect-timeout','3','--max-time','7'}
            if official then
                url='https://api.myanimelist.net/v2/anime?limit=15&fields=alternative_titles,start_date,media_type,num_episodes,status&q='..encoded
                args[#args+1]='--header';args[#args+1]='X-MAL-CLIENT-ID: '..client
            end
            args[#args+1]=url
            local response=call({name='subprocess',playback_only=false,capture_stdout=true,capture_stderr=true,args=args})
            if not current() then return {},nil,'stale' end
            if not response or response.status~=0 or type(response.stdout)~='string' or #response.stdout>2000000 then cooldown=clock()+60;return {},nil,'unavailable' end
            local payload=utils.parse_json(response.stdout)
            if type(payload)~='table' or type(payload.data)~='table' then return {},nil,'unavailable' end
            if official then payload=M.mal_payload(payload) end
            if not payload then return {},nil,'unavailable' end
            candidates=M.candidates(payload,query)
            -- Store only public catalog fields, never the media URL or torrent path.
            local clean={data={}}
            for _,candidate in ipairs(M.candidates(payload,{}))do
                clean.data[#clean.data+1]={mal_id=candidate.mal_id,title=candidate.title,title_synonyms=candidate.aliases,
                    type=candidate.media_type,year=candidate.year,episodes=candidate.episodes}
            end
            cache[key]={expires=os.time()+(#clean.data>0 and 7*86400 or 3600),payload=clean};save()
        end
        if not current() then return {},nil,'stale' end
        return candidates,M.choose(candidates,query)
    end}
end
return M
