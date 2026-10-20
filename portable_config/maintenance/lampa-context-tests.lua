return function(path)
    local real,getenv=mp,os.getenv
    local wrapped,original_identify
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
        -- Repeated calls reuse only the current identity. Late torrent data,
        -- a changed title and another file must each invalidate that result.
        local native_dofile=dofile
        local calls,context=0,{media=media,pending=true}
        local props={path=media,['media-title']='Breaking Bad S03E02'}
        mp={get_property=function(k,d)return props[k] or d end,
            get_property_native=function()return context end}
        dofile=function(file)
            local module=native_dofile(file)
            if file:match('anime_identity.lua$') then
                local identify=module.from_source
                wrapped,original_identify=module,identify
                module.from_source=function(...)calls=calls+1;return identify(...) end
            end
            return module
        end
        local loaded,reader=pcall(dofile,path('extensions/lampa_context.lua'))
        dofile=native_dofile
        assert(loaded,reader)
        local first=reader.current()
        local count=calls;first.title='Caller edit'
        assert(reader.current().title~='Caller edit' and calls==count,'Cache must reuse a protected result')
        context={media=media,path='Breaking.Bad.S03E02.mkv'}
        assert(reader.current().season==3 and calls>count,'Late file data must invalidate a pending identity')
        count=calls;props['media-title']='Corrected title';reader.current()
        assert(calls>count,'Title changes must invalidate the current result')
        props.path=media:gsub('S03E02','S04E02')
        assert(reader.current()==nil,'Never reuse another file identity')
        local anchor='http://localhost/stream?link='..string.rep('a',40)..'&index=1&play'
        local second=anchor:gsub('index=1','index=2')
        local files={{id=1,path='MobLand/MobLand_S01E01_RHS_4K_[scarfilm].mkv'},
            {id=2,path='MobLand/MobLand_S01E02_RHS_4K_[scarfilm].mkv'}}
        props.path=second
        context={media=second,path=files[2].path,title='Гангстерленд_1_сезон_4K_RHS_[scarfilm]',files=files}
        os.getenv=function(key)
            if key=='MPV_PLUS_LAMPA_CONTEXT' then return utils.format_json({version=1,source='lampa',entries={{url=anchor,identity={
                title='Гангстерленд',original_title='MobLand',kind='tv',tmdb_id=247718,season=1,episode=1,episode_title='Пан или пропал',
            }}}}) end
            return getenv(key)
        end
        reader=dofile(path('extensions/lampa_context.lua'))
        local sibling=reader.current('MobLand_S01E02_RHS_4K_[scarfilm].mkv')
        assert(sibling and sibling.tmdb_id==247718 and sibling.title=='Гангстерленд' and sibling.season==1 and sibling.episode==2 and not sibling.episode_title,'Verified sibling keeps its own episode and canonical card identity')
        local first=reader.current('MobLand_S01E01_RHS_4K_[scarfilm].mkv',anchor)
        assert(first and first.episode==1 and first.episode_title=='Пан или пропал','Playlist entries resolve independently of the playing entry')
        for _,bad in ipairs({'OtherShow_S01E02.mkv','MobLand_S02E02.mkv','02.mkv'}) do
            files[2].path=bad;context.path=bad
            assert(not reader.current(bad),'Reject unproven sibling: '..bad)
        end
        files[2].path='MobLand_S01E02.mkv';context.path=files[2].path
        for _,bad in ipairs({(second:gsub(string.rep('a',40),string.rep('b',40))),(second:gsub('localhost','other.example')),(second:gsub('index=2','index=99'))}) do
            props.path=bad;context.media=bad
            assert(not reader.current(files[2].path),'Never inherit by episode number alone')
        end
    end,debug.traceback)
    if wrapped then wrapped.from_source=original_identify end
    mp,os.getenv=real,getenv
    assert(ok,err)
end
