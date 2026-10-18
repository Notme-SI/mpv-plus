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
    end,debug.traceback)
    mp=real;assert(ok,error)
end
