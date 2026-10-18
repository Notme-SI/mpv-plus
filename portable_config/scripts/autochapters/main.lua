-- autochapters
-- https://github.com/po5/mpv-auto-chapters
--
-- Automatically finds chapters for your anime files
-- using a local anime database to identify media,
-- and the Aniskip API for community-submitted times

local opts = require "mp.options"
local utils = require "mp.utils"
local msg = require "mp.msg"
local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
ui.install_messages()
local input = require "mp.input"
local encoding = require "encoding"
local root=mp.command_native({'expand-path','~~/'})
local title_format=dofile(root..'/extensions/title_format.lua')
local anime_identity=dofile(root..'/extensions/anime_identity.lua')
local source_context=dofile(root..'/extensions/media_source.lua')
local settings=dofile(root..'/extensions/user_settings.lua')
local manual=dofile(root..'/extensions/manual_identity.lua')
local lampa=dofile(root..'/extensions/lampa_context.lua')

local options = {
    create_chapters = true,
    on_file_load = true,
    search_only_when_chapters_missing = true,
    allow_loose_matches = true,
    keep_previous_chapters = false,
    pause_on_search = true,
    db_update_days = 7,
    hook = false
}

local script_name, script_dir = mp.get_script_name(), mp.get_script_directory()
opts.read_options(options, script_name, function() end)
local guessit_path = utils.join_path(script_dir, 'bin/guessit.exe')
local function media_key()
    return (mp.get_property('path') or '') .. '|' .. tostring(mp.get_property_number('playlist-pos', -1))
end
-- Capture original file chapters before any script creates online chapters.
mp.add_hook('on_preloaded',20,function()
    mp.set_property_native('user-data/file-chapters',{key=media_key(),chapters=mp.get_property_native('chapter-list',{})})
end)
local lookup_key
local function current_lookup() return lookup_key == media_key() end

local types = {
    op = "Заставка (OP)",
    ed = "Титры (ED)",
    ["mixed-op"] = "Заставка в эпизоде",
    ["mixed-ed"] = "Титры в эпизоде",
    recap = "Ранее в сериале"
}

local api_url = "https://api.aniskip.com/v2"
local db_url = "https://github.com/manami-project/anime-offline-database/releases/download/latest/anime-offline-database-minified.json"
local relations_url = "https://github.com/erengy/anime-relations/raw/master/anime-relations.txt"
local placeholder_title = ""

local anime, relations, borked, anime_index
local json_path = utils.join_path(script_dir, "anime.json")
local relations_path = utils.join_path(script_dir, "relations.json")

local function log(message)
    msg.warn(message)
end

local function guess(path, auto)
    if not path or path == "" then
        return nil, nil
    end
    local corrected=auto and manual.current(path) or manual.parse(path)
    if corrected then return corrected.title,corrected.episode,corrected.season,corrected.year end
    local card=auto and lampa.current(path)
    if card then return card.title,card.episode,card.season,card.year end
    local contextual=anime_identity.from_source(path,auto and source_context.current() or {})
    if contextual.unresolved_context then return end
    if contextual.anime and contextual.episode then
        return contextual.title,contextual.episode,contextual.season,contextual.year
    end

    local guessit = mp.command_native({name = "subprocess", playback_only = false, capture_stdout = true, args = {"powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", utils.join_path(script_dir, "guessit-json.ps1"), "-Name", path}})
    if not guessit or not guessit.stdout then
        return nil, nil
    end

    local data = utils.parse_json(encoding.utf8(guessit.stdout))
    if type(data) ~= "table" then
        log("AniSkip: не удалось определить название серии через GuessIt")
        return nil, nil
    end

    if auto then
        data.input = mp.get_property("path")
        data.filename = path
        mp.set_property_native("user-data/guessit", data)
    end

    if not data.title then
        return nil, nil
    end

    if type(data.title) == "table" then
        data.title = data.title[1]
    end

    if type(data.episode) == "table" then
        data.episode = data.episode[1]
    end

    local parsed=title_format.parse(path)
    parsed=anime_identity.enrich(path,parsed)
    return parsed.anime and parsed.title or data.title, parsed.episode or data.episode, parsed.season or data.season, parsed.year or data.year
end

local function time_sort(a, b)
    if a.time == b.time then
        return not a.title and b.title ~= nil
    end
    return a.time < b.time
end

local function extract_mal_id(url)
    local prefix = "https://myanimelist.net/anime/"
    if url:find(prefix) == 1 then
        return url:sub(31) -- #prefix + 1
    end
    return nil
end

local file_load
local database = require('database').new(script_dir, options.db_update_days, function(new_anime, new_relations)
    anime, relations, borked, anime_index = new_anime, new_relations, false, nil
    anime_identity.invalidate()
    if file_load and not mp.get_property_bool('idle-active', true) then
        mp.add_timeout(0, file_load)
    end
end)
local function update_db() database.request(true) end
mp.add_timeout(5, function() database.request(false) end)

local function resolve_relations(mal_id, episode)
    if not relations or not relations[mal_id] then
        return mal_id, episode
    end
    local ep = episode or 0
    for _, r in ipairs(relations[mal_id]) do
        if ep >= r.a and ep <= (r.b or math.huge) then
            local offset = r.a - r.x
            return r.z, ep - offset, r.t
        end
    end
    return mal_id, episode
end

local function read_json(path)
    local f = io.open(path, "r")
    if f then
        local json = f:read("*all")
        f:close()

        data = utils.parse_json(json or "")
        if data and type(data) == "table" then
            return data
        end
    end
end

local function api_lookup(title, episode, duration, auto, season, year)
    local card=auto and (manual.current(placeholder_title) or lampa.current())
    if auto and not card then
        local contextual=anime_identity.from_source(placeholder_title,source_context.current())
        if contextual.mal_id then card=contextual end
    end
    if not (card and card.mal_id) then
    if borked then return end

    if anime == nil or relations == nil then
        anime = read_json(json_path)
        relations = read_json(relations_path)
        if anime == nil or relations == nil then
            database.request(false, true)
        end
    end

    if anime == nil or relations == nil then
        borked = true
        return
    end

    if not anime._normalized then
        local normalized = {}
        for key, value in pairs(anime) do normalized[encoding.key(key)] = value end
        normalized._normalized = true
        anime = normalized
    end
    anime_index=anime_index or anime_identity.index(anime)
    end
    local identity=(card and card.mal_id) and card or anime_identity.enrich(title,{title=title,episode=episode,season=season,year=year,kind='tv'},anime_index)
    local mal_id=identity.mal_id
    if not mal_id or not episode or episode<1 then return end

    local relation_title
    local in_episode = episode
    mal_id = tostring(mal_id)
    mal_id, episode, relation_title = resolve_relations(mal_id, episode)

    local display_episode = relation_title and episode or in_episode

    if not auto then
        mp.osd_message("Поиск: " .. (relation_title or title) .. (display_episode and (" - серия " .. display_episode) or "") .. "...")
    end

    local function lookup(length)
        local url = api_url .. '/skip-times/' .. mal_id .. '/' .. (episode or 1)
            .. '?types=op&types=ed&types=recap&episodeLength=' .. math.max(0,length)
        local response = mp.command_native({name='subprocess', playback_only=false,
            capture_stdout=true, capture_stderr=true, args={'curl','-fsS','--globoff',
                '--connect-timeout','5','--max-time','10',url}})
        local data = response and response.status==0 and utils.parse_json(response.stdout or '')
        return type(data)=='table' and data.results or {}
    end
    local skip_rules=dofile(root..'/extensions/skip_segments.lua')
    local best=skip_rules.aniskip(lookup(duration),duration)
    if not next(best) and options.allow_loose_matches then
        best=skip_rules.aniskip(lookup(0),duration)
    end
    if not next(best) then return end
    local data={results={}}
    for _, kind in ipairs({'op','ed','recap'}) do
        if best[kind] then data.results[#data.results+1]=best[kind].segment end
    end

    if not current_lookup() then return end

    local original=mp.get_property_native('user-data/file-chapters',{})
    local embedded=original.key==media_key() and original.chapters or {}
    local chapters = {}
    local times = {}

    for _, skip in ipairs(data.results) do
        times[skip.skipType] = {}
        if skip.interval.startTime then
            table.insert(chapters, {title=types[skip.skipType], time=skip.interval.startTime})
            times[skip.skipType]["start"] = skip.interval.startTime
        end
        if skip.interval.endTime then
            table.insert(chapters, {title=nil, time=skip.interval.endTime})
            times[skip.skipType]["end"] = skip.interval.endTime
        end
    end

    if options.create_chapters and #embedded==0 then
        table.sort(chapters, time_sort)
        mp.set_property_native("chapter-list", chapters)
    end

    mp.set_property('user-data/autochapters-media', lookup_key)
    mp.set_property_native("user-data/autochapters", times)

    return true
end

local function find_chapters(media_title, auto)
    lookup_key = media_key()
    local title, episode, season, year = guess(media_title, auto)
    if not title then return end

    local duration = mp.get_property_number("duration", 0)

    local found = api_lookup(title, episode, duration, auto, season, year)

    if not found and current_lookup() then
        mp.set_property_native("user-data/autochapters", {})
    end
    return found, title, episode, season, year
end

-- TorrServer/Lampa playlists store the real episode filename in the M3U title.
local function episode_name()
    local playlist = mp.get_property_native('playlist') or {}
    local item = playlist[mp.get_property_number('playlist-pos', -1) + 1] or {}
    local name = item.title or mp.get_property('media-title') or mp.get_property('filename') or ''
    if name:match('^edl://') then return '' end
    name = name:gsub('[?#].*$', ''):match('([^/\\]+)$') or name
    return name:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
end

file_load = function()
    mp.set_property_native('user-data/autochapters', {})
    mp.set_property('user-data/autochapters-media', '')
    mp.set_property_native('user-data/guessit', {})
    placeholder_title = episode_name()
    if not options.on_file_load then return end
    local card=lampa.current(placeholder_title)
    if (placeholder_title == '' or placeholder_title == 'stream') and not card then return end
    find_chapters(placeholder_title, true)
end
mp.register_event('end-file', function()
    mp.set_property_native('user-data/file-chapters', {})
    mp.set_property_native('user-data/autochapters', {})
    mp.set_property('user-data/autochapters-media', '')
end)

local function search()
    mp.commandv('script-message-to','uosc','close-menu')
    local pause_and_restore = options.pause_on_search and mp.get_property_bool("pause") == false

    local corrected=manual.current(placeholder_title)
    local default=corrected and string.format('%s %d %d',corrected.title,corrected.season or 1,corrected.episode) or ''
    input.get({
        prompt = "Пример: Название 1 1 / Name 1 1",
        submit = function (media_title)
            placeholder_title = media_title
            if media_title ~= "" then
                mp.add_timeout(0.05, function()
                    local candidates={}
                    for value in media_title:gmatch('[^/|]+') do
                        value=value:gsub('^%s+',''):gsub('%s+$','')
                        if value~='' then candidates[#candidates+1]=value end
                    end
                    if #candidates==0 then candidates={media_title} end
                    local found,title,episode,season,year,manual_match
                    for _,candidate in ipairs(candidates) do
                        local parsed=manual.parse(candidate)
                        if parsed then
                            -- GuessIt cannot reliably parse Cyrillic titles.  Feed the
                            -- canonical S/E form through the same lookup path and keep
                            -- the explicit season/episode supplied by the user.
                            manual_match=parsed
                            found,title,episode,season,year=find_chapters(
                                string.format('%s S%d E%d',parsed.title,parsed.season,parsed.episode))
                            title,episode,season,year=parsed.title,parsed.episode,parsed.season,parsed.year
                        else
                            found,title,episode,season,year=find_chapters(candidate)
                        end
                        if found then break end
                    end
                    if found then
                        local chosen=manual_match or anime_identity.enrich(title,{title=title,season=season,episode=episode,kind='tv'})
                        chosen=anime_identity.enrich(title,chosen)
                        if chosen.mal_id then manual.save(chosen) end
                    end
                    if not found then
                        msg.info("Таймкоды не найдены: " .. (title and (title .. (episode and (" - серия " .. episode) or "")) or media_title))
                    end
                end)
            else
                mp.set_property_native("chapter-list", {})
            end
            input.terminate()
        end,
        closed = function (media_title)
            if pause_and_restore then
                mp.set_property_bool("pause", false)
            end
        end,
        default_text = default,
        cursor_position = #default + 1
    })

    if pause_and_restore then
        mp.set_property_bool("pause", true)
    end
end

mp.add_key_binding(nil, "search", search)
mp.add_key_binding(nil, "update", update_db)
mp.observe_property('user-data/torrserver-context','native',function()
    if not mp.get_property_bool('idle-active',true) then mp.add_timeout(0,file_load) end
end)

if options.hook then
    mp.add_hook("on_preloaded", 50, file_load)
else
    mp.register_event("file-loaded", file_load)
end
