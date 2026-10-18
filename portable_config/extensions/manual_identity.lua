local folder=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]'))
local anime=dofile(folder..'/anime_identity.lua')
local fmt=dofile(folder..'/title_format.lua')
local settings=dofile(folder..'/user_settings.lua')
local utils=require 'mp.utils'
local M={}
local function scope()
    local path=mp.get_property('path','')
    local hash=path:match('[?&]link=(%x+)')
    if hash then return 'torrent:'..hash:lower() end
    local list=mp.get_property_native('playlist',{})
    if #list>1 then
        local files={}
        for _,item in ipairs(list) do files[#files+1]=item.filename or '' end
        return 'playlist:'..table.concat(files,'|')
    end
    return 'folder:'..(path:match('^(.*)[/\\]') or path)
end
local function read()
    local f=io.open(settings.path('anime-bindings.json'),'rb')
    if not f then return {} end
    local data=utils.parse_json(f:read('*a'));f:close()
    return type(data)=='table' and data or {}
end
function M.parse(text)
    local title,season,episode=text:match('^%s*(.-)%s+(%d+)%s+(%d+)%s*$')
    if not title or title=='' then return end
    local data=anime.enrich(title,fmt.parse(title))
    data.title=title;data.season=tonumber(season);data.episode=tonumber(episode);data.kind='tv'
    data=anime.enrich(title,data)
    if not data.mal_id or data.episode<1 then return end
    return data
end
function M.save(data)
    local all=read()
    all[scope()]={title=data.title,season=data.season,episode=data.episode,
        mal_id=data.mal_id,position=mp.get_property_number('playlist-pos',0)}
    local f=io.open(settings.path('anime-bindings.json'),'wb')
    if not f then return false end
    local ok=f:write(utils.format_json(all));local closed=f:close()
    mp.set_property_native('user-data/autochapters-manual',all[scope()])
    return ok and closed
end
function M.current(raw)
    local entry=read()[scope()]
    if not entry then return end
    local episode=entry.episode+mp.get_property_number('playlist-pos',0)-entry.position
    if episode<1 then return end
    local data=anime.enrich(entry.title,{title=entry.title,season=entry.season,episode=episode,kind='tv'})
    if tostring(data.mal_id)~=tostring(entry.mal_id) then return end
    return data
end
return M
