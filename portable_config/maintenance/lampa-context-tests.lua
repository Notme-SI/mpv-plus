return function(path)
    local real,getenv=mp,os.getenv
    local utils=require 'mp.utils'
    local media='http://localhost/stream?link=abcdef&index=2&play'
    local function check(season,expected)
        os.getenv=function(key)
            if key=='MPV_PLUS_LAMPA_CONTEXT' then return utils.format_json({version=1,source='lampa',entries={{url=media,identity={
                title='Истребитель демонов',original_title='Kimetsu no Yaiba',kind='tv',anime=true,tmdb_id=85937,
                season=season,episode=2,mal_id=38000,
            }}}}) end
            return getenv(key)
        end
        mp={get_property=function(k,d)if k=='path' then return media end;return d end}
        local data=dofile(path('extensions/lampa_context.lua')).current('02.mkv')
        assert(data.tmdb_id==85937 and data.tmdb_season==season and data.tmdb_episode==2,utils.format_json(data))
        assert(data.mal_id==expected,'TMDB season '..season..' selected wrong AniSkip anime: '..tostring(data.mal_id))
        assert(data.episode==2,'Do not shift the episode when the arc has no offset')
    end
    local ok,err=xpcall(function()
        check(1,38000)
        check(3,47778)
        check(4,51019)
        check(9,nil)
        -- The source URL contains a clear episode filename while Lampa's
        -- display title and coordinates incorrectly refer to season one.
        local media='https://host/Breaking.Bad.S03E02.mkv?token=fixture'
        os.getenv=function(key)
            if key=='MPV_PLUS_LAMPA_CONTEXT' then return utils.format_json({version=1,source='lampa',entries={{url=media,identity={
                title='Во все тяжкие',original_title='Breaking Bad',kind='tv',tmdb_id=1396,season=1,episode=2,
            }}}}) end
            return getenv(key)
        end
        mp={get_property=function(k,d)if k=='path' then return media end;return d end}
        local data=dofile(path('extensions/lampa_context.lua')).current('Breaking Bad S01E02')
        assert(data.season==3 and data.episode==2 and data.lampa_check=='conflict-season',utils.format_json(data))
    end,debug.traceback)
    mp,os.getenv=real,getenv
    assert(ok,err)
end
