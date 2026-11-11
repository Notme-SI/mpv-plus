return function(path)
    local real=mp
    mp={get_property=function(key,default)if key=='path' then return 'https://host/video.mkv' end;return default end}
    local ok,error=xpcall(function()
        local context=dofile(path('extensions/lampa_context.lua'))
        local own={title='Breaking Bad',kind='tv',season=3,episode=2}
        local hint={title='Во все тяжкие',original_title='Breaking Bad',aliases={'Breaking Bad'},kind='tv',season=1,episode=2,tmdb_season=1,tmdb_episode=2,tmdb_id=1396}
        local result=context.reconcile(own,hint,{path='Breaking.Bad.S03E02.mkv'})
        assert(result.season==3 and result.tmdb_season==3 and result.tmdb_id==nil and result.lampa_check=='conflict-season')
        hint.season,hint.tmdb_season=3,3
        result=context.reconcile(own,hint,{path='Breaking.Bad.S03E02.mkv'})
        assert(result.tmdb_id==1396 and result.season==3 and result.episode==2 and result.lampa_check=='confirmed')
        hint.tmdb_episode=4
        result=context.reconcile(own,hint,{path='Breaking.Bad.S03E02.mkv'})
        assert(result.tmdb_id==nil and result.episode==2 and result.lampa_check=='conflict-episode')
        hint.tmdb_episode=2
        result=context.reconcile(own,hint,{path='Another.Show.S03E02.mkv'})
        assert(result.tmdb_id==nil and result.lampa_check=='conflict-title')
        result=context.reconcile({title='Unknown',kind='movie',unresolved_context=true},hint,{pending=true})
        assert(result.tmdb_id==nil and result.unresolved_context and result.lampa_check=='pending')
        result=context.reconcile({title='stream',kind='movie'},hint,{unavailable=true})
        assert(result.tmdb_id==1396 and result.lampa_check=='hint')
        result=context.reconcile({title='Kimetsu no Yaiba',kind='tv',tmdb_id=85937,mal_id=55701,tmdb_season=5,season=5,episode=2},
            {title='Kimetsu no Yaiba',kind='tv',tmdb_id=85937,mal_id=38000,tmdb_season=1,season=1,episode=2},{path='03.mkv'})
        assert(result.mal_id==55701 and result.tmdb_season==5 and result.lampa_check=='conflict-arc')
        result=context.reconcile({title='A',kind='movie',tmdb_id=10},{title='B',kind='movie',tmdb_id=20},{})
        assert(result.tmdb_id==10 and result.lampa_check=='conflict-id')
        local anime=dofile(path('extensions/anime_identity.lua'))
        local automatic=anime.from_source('Wrong.Show.S01E09.mkv',{path='Breaking.Bad.S03/02.mkv'})
        assert(automatic.source_confirmed and automatic.season==3 and automatic.episode==2 and automatic.title=='Breaking Bad')
        hint.season,hint.tmdb_season,hint.episode,hint.tmdb_episode=1,1,2,2
        result=context.reconcile(automatic,hint,{path='Breaking.Bad.S03/02.mkv'})
        assert(result.season==3 and result.episode==2 and result.lampa_check=='conflict-season')
        local card={title='Тёмная материя',original_title='Dark Matter',kind='tv',year=2024,
            tmdb_id=196322,season=2,episode=1,tmdb_season=2,tmdb_episode=1}
        local releases={
            {folder='Dark.Matter.2026.S02.2160p.ATVP.WEB-DL.HDR.H265.Master5',
                file='Dark.Matter.2026.S02E01.2160p.HDR.Master5.mkv'},
            {folder='Dark.Matter.S02.ATVP.DV.HDR.WEB-DL.2160p.by.AKTEP',
                file='Dark.Matter.S02E01.A.Quiet.Life.ATVP.DV.HDR.WEB-DL.2160p.by.AKTEP.mkv'},
        }
        for _,release in ipairs(releases) do
            local physical={path=release.folder..'/'..release.file,title=release.folder}
            local independent=anime.from_source(release.file,physical)
            result=context.reconcile(independent,card,physical)
            assert(result.tmdb_id==196322 and result.year==2024 and result.source=='lampa'
                and result.lampa_check=='confirmed' and result.tmdb_season==2 and result.tmdb_episode==1,
                'The selected TV card survives a later-season filename year: '..release.file)
        end
        local function check_year_conflict(file,changes,expected)
            local hint={};for key,value in pairs(card) do hint[key]=value end
            for key,value in pairs(changes) do hint[key]=value end
            local independent=anime.from_source(file,{path=file})
            local actual=context.reconcile(independent,hint,{path=file})
            assert(actual.tmdb_id==nil and actual.lampa_check==expected,
                'Year exception must retain '..expected..' for '..file)
        end
        check_year_conflict('Dark.Matter.2026.S01E01.mkv',{season=1,tmdb_season=1},'conflict-year')
        check_year_conflict('Dark.Matter.2022.S02E01.mkv',{},'conflict-year')
        check_year_conflict('Dark.Matter.2026.mkv',{kind='movie',season=false,tmdb_season=false},'conflict-year')
        check_year_conflict('Other.Show.2026.S02E01.mkv',{},'conflict-title')
        check_year_conflict('Dark.Matter.2026.S03E01.mkv',{},'conflict-season')
        check_year_conflict('Dark.Matter.2026.S02E02.mkv',{},'conflict-episode')
        check_year_conflict('Dark.Matter.2026.S02E01.mkv',{tmdb_id=false},'conflict-year')
        local format=dofile(path('extensions/title_format.lua'))
        local unconfirmed=format.parse(releases[1].file)
        assert(not format.match_result({{id=196322,original_name='Dark Matter',first_air_date='2024-05-08'}},unconfirmed,true),
            'A later-season filename alone must not bypass the catalog year check')
        local independent=anime.from_source(releases[1].file,{path=releases[1].file})
        independent.tmdb_id=100
        result=context.reconcile(independent,card,{path=releases[1].file})
        assert(result.tmdb_id==100 and result.lampa_check=='conflict-id','A later-season year never replaces a conflicting catalog ID')
    end,debug.traceback)
    mp=real;assert(ok,error)
end
