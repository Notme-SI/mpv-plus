-- Pure filename parsing and display formatting. Never changes media/playlist source names.
local M={}
local function trim(s) return (s or ''):gsub('^[%s%._%-%(]+',''):gsub('[%s%._%-%(]+$','') end
function M.without_dimensions(s)
    return (s or ''):gsub('×','x'):gsub('(%d+)%s*[xX]%s*(%d+)',function(a,b)
        if tonumber(a)>=180 and tonumber(b)>=180 then return ' ' end
        return a..'x'..b
    end)
end
function M.decode(s)
    for _=1,2 do s=s:gsub('%%(%x%x)',function(h) return string.char(tonumber(h,16)) end) end
    return s:gsub('[%c]',' ')
end
local function cut_technical(s)
    local lower=s:lower()
    local cut=#s+1
    for _,p in ipairs({'%f[%w]%d%d%d[pPiI]%f[%W]','%f[%w]%d%d%d%d[pPiI]%f[%W]',
        '%f[%w]web[%s%-]*dl%f[%W]','%f[%w]webrip%f[%W]','%f[%w]bluray%f[%W]',
        '%f[%w]blu%-ray%f[%W]','%f[%w]bdrip%f[%W]','%f[%w]hdtv%f[%W]',
        '%f[%w]hevc%f[%W]','%f[%w][xh]26[45]%f[%W]','%f[%w]hdr%f[%W]',
        '%f[%w]hdr10','%f[%w]dovi%f[%W]','%f[%w]remux%f[%W]','%f[%w]aac%f[%W]',
        '%f[%w]ddp%d','%f[%w]dts%f[%W]','%f[%w]4k%f[%W]'}) do
        local i=lower:find(p); if i and i<cut then cut=i end
    end
    return trim(s:sub(1,cut-1))
end
function M.parse(raw)
    local s=M.without_dimensions(M.decode(raw or ''))
    if s:match('^edl://') or s:match('^lavfi://') then return {title='',kind='movie'} end
    if s:match('^%a+://') then
        s=s:match('^[^?#]+') or s
        s=s:match('([^/]+)$') or s
        if s=='stream' then s='' end
    elseif s:find('\\',1,true) or s:find('/',1,true) and (s:lower():find('%.mkv') or s:lower():find('%.mp4')) then
        s=s:match('([^/\\]+)$') or s
    end
    -- A failed server lookup can leave a query after the filename in playlist titles.
    s=s:gsub('(%.[mM][kK][vV])[?#].*$','%1'):gsub('(%.[mM][pP]4)[?#].*$','%1')
    s=s:gsub('%.[mM][kK][vV]$',''):gsub('%.[mM][pP]4$',''):gsub('%.[aA][vV][iI]$','')
        :gsub('%.[mM]4[vV]$',''):gsub('%.[tT][sS]$',''):gsub('%.[mM][oO][vV]$','')
    s=s:gsub('%[[^%]]*%]',' '):gsub('[._]',' '):gsub('%s+',' ')
    local out={kind='movie'}
    local parenthesized_season
    s=s:gsub('%([Ss](%d+)%)',function(n)
        parenthesized_season=tonumber(n)
        return ' '
    end):gsub('%s+',' ')
    out.tmdb_id=s:match('[Tt][Mm][Dd][Bb][%s%-:]*(%d+)')
    local a,b,season,episode=s:find('[Ss](%d%d?)%s*[Ee](%d%d?%d?%d?)%f[%D]')
    if not a then a,b,season,episode=s:find('%f[%d](%d%d?)[xX](%d%d?%d?%d?)%f[%D]') end
    if not a then a,b,season,episode=s:find('[Ss]eason%s+(%d+)%s+[Ee]pisode%s+(%d+)') end
    if a then
        out.season,out.episode,out.kind=tonumber(season),tonumber(episode),'tv'
        if trim(s:sub(1,a-1))~='' then
            out.episode_title=cut_technical(s:sub(b+1))
            s=s:sub(1,a-1)
        else
            s=trim(s:sub(b+1))
        end
    else
        a,b,season=s:find('[Ss]eason%s+(%d+)')
        if not a then a,b,season=s:find('%f[%d](%d+)%s+сезон') end
        if not a then a,b,season=s:find('%f[%d](%d+)%s+Сезон') end
        if not a then a,b,season=s:find('Сезон%s+(%d+)%f[%W]') end
        if not a then a,b,season=s:find('сезон%s+(%d+)%f[%W]') end
        if a then out.season,out.kind=tonumber(season),'tv';s=s:sub(1,a-1):gsub('%s*/%s*$','') end
        if not a then
            a,b,episode=s:find('%s%-%s*(%d%d?%d?%d?)%f[%D]')
            if episode and tonumber(episode)>=1900 and tonumber(episode)<=2100 then a,b,episode=nil,nil,nil end
            if a then
                out.season,out.episode,out.kind,out.season_inferred=1,tonumber(episode),'tv',true
                out.episode_title=cut_technical(s:sub(b+1));s=s:sub(1,a-1)
            end
        end
    end
    -- Anime releases often use "Title S3 - 02" instead of S03E02.
    -- Keep the season marker out of the title sent to the metadata catalog.
    if not a or out.episode then
        local title,short_season=s:match('^(.-)%s+[Ss](%d+)%s*$')
        if title and trim(title)~='' then
            out.season,out.kind,out.season_inferred=tonumber(short_season),'tv',nil
            s=title
        end
    end
    if parenthesized_season then out.season=parenthesized_season;out.kind='tv';out.season_inferred=nil end
    s=cut_technical(s)
    for p,y in s:gmatch('()(%d%d%d%d)') do
        if tonumber(y)>=1900 and tonumber(y)<=2100 and trim(s:sub(1,p-1))~='' then
            out.year=y
            local rest=trim(s:sub(p+4):gsub('^%)',''))
            if out.episode and not out.episode_title and rest~='' then out.episode_title=rest end
            s=s:sub(1,p-1)
            break
        end
    end
    out.title=trim(s):gsub('%s*/%s*$','')
    out.episode_title=out.episode_title and trim(out.episode_title) or nil
    if out.episode_title=='' then out.episode_title=nil end
    if out.episode_title and out.episode_title:lower():match('^rhs%s*%d*[kK]?$') then out.episode_title=nil end
    return out
end
local languages={rus='ru',eng='en',ukr='uk',jpn='ja',deu='de',ger='de',fra='fr',fre='fr',spa='es',ita='it',
    kor='ko',zho='zh',chi='zh',por='pt',pol='pl',tur='tr',ara='ar',hin='hi'}
function M.language(lang)
    lang=(lang or ''):lower():match('^[a-z]+') or ''
    return languages[lang] or (#lang==2 and lang) or 'ru'
end
function M.label(data,lang,title,episode_title)
    local name=title or data.title or ''
    if data.episode then
        local marker
        if data.unresolved_context then
            marker=((lang=='ru' and 'Серия ' or lang=='uk' and 'Серія ' or 'Episode ')..data.episode)
        elseif lang=='ru' then marker=string.format('Сезон %d, серия %d',data.season or 1,data.episode)
        elseif lang=='uk' then marker=string.format('Сезон %d, серія %d',data.season or 1,data.episode)
        elseif lang=='en' then marker=string.format('Season %d, episode %d',data.season or 1,data.episode)
        else marker=string.format('S%02dE%02d',data.season or 1,data.episode) end
        name=name~='' and name..' · '..marker or marker
        local ep=episode_title or data.episode_title
        if ep and ep~='' then name=name..': '..ep end
    elseif data.season then
        local marker=(lang=='ru' or lang=='uk') and 'Сезон ' or 'Season '
        name=name..' · '..marker..data.season
    elseif data.year then name=name..' ('..data.year..')' end
    return name
end
local upper={'А','Б','В','Г','Д','Е','Ё','Ж','З','И','Й','К','Л','М','Н','О','П','Р','С','Т','У','Ф','Х','Ц','Ч','Ш','Щ','Ъ','Ы','Ь','Э','Ю','Я','І','Ї','Є','Ґ'}
local lower={'а','б','в','г','д','е','ё','ж','з','и','й','к','л','м','н','о','п','р','с','т','у','ф','х','ц','ч','ш','щ','ъ','ы','ь','э','ю','я','і','ї','є','ґ'}
function M.normalize(s)
    s=(s or ''):lower()
    for i,c in ipairs(upper) do s=s:gsub(c,lower[i]) end
    return s:gsub('[%s%p]','')
end
function M.animation_candidates(results)
    local matches={}
    for _,candidate in ipairs(results) do
        for _,genre in ipairs(candidate.genre_ids or {}) do
            if genre==16 then matches[#matches+1]=candidate;break end
        end
    end
    return matches
end
function M.match_result(results,data,allow_year_offset)
    local hits,nearby={},{}
    local name=M.normalize(data.title)
    for _,r in ipairs(results or {}) do
        local exact=false
        for _,k in ipairs({'name','original_name','title','original_title'}) do
            if r[k] and M.normalize(r[k])==name then exact=true end
        end
        for _,alias in ipairs(r.aliases or {}) do
            if type(alias.title)=='string' and M.normalize(alias.title)==name then exact=true end
        end
        local year=(r.first_air_date or r.release_date or ''):sub(1,4)
        if exact then
            if not data.year or tostring(data.year)==year then hits[#hits+1]=r
            elseif allow_year_offset and tonumber(year) and tonumber(data.year)
                and math.abs(tonumber(year)-tonumber(data.year))==1 then nearby[#nearby+1]=r end
        end
    end
    -- Ambiguous searches retain the filename instead of selecting an unrelated remake.
    if #hits>0 then return #hits==1 and hits[1] or nil end
    return #nearby==1 and nearby[1] or nil
end
return M
