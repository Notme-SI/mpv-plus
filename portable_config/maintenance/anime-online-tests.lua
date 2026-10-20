return function(path)
    local online=dofile(path('extensions/anime_online.lua'))
    local utils=require 'mp.utils'
    local function item(id,title,year,kind,episodes,aliases)
        return {mal_id=id,title=title,year=year,type=kind or 'TV',episodes=episodes or 12,title_synonyms=aliases}
    end
    local query={title='Unlisted Anime',year=2026,kind='tv',season=1,episode=3,anime=true}
    local function candidates(items,q)return online.candidates({data=items},q or query)end
    local first=item(991001,'Unlisted Anime',2026)
    assert(online.choose(candidates({first}),query).mal_id==991001)
    assert(not online.choose(candidates({first,item(991002,'Unlisted Anime',2026)}),query),'Ambiguous names must stay unresolved')
    assert(not online.choose(candidates({item(991001,'Unlisted Anime',2025)}),query),'Do not confuse a remake year')
    assert(not online.choose(candidates({item(991001,'Unlisted Anime',2026,'Movie')}),query),'Movie is not a TV episode')
    assert(not online.choose(candidates({item(991001,'Unlisted Anime',2026,'OVA')}),query),'OVA needs explicit type or manual choice')
    assert(not online.choose(candidates({item(991001,'Unlisted Anime: Another Arc',2026)}),query),'Never choose the first fuzzy result')
    assert(online.choose(candidates({item(991001,'Unknown Romanized Name',2026,'TV',12,{'Unlisted Anime'})}),query))
    local sequel={title='Unlisted Anime',year=2026,kind='tv',season=2,episode=3}
    assert(not online.choose(candidates({first},sequel),sequel),'S2 must not use the base MAL release')
    local named={title='Unlisted Anime 2nd Season',year=2026,kind='tv',season=2,episode=3}
    assert(online.choose(candidates({item(991002,named.title,2026)},named),named))
    local past={title=query.title,year=2026,kind='tv',season=1,episode=13}
    assert(#candidates({first},past)==0,'Episode outside the selected release is invalid')
    local mal=online.mal_payload({data={{node={id=991001,title=query.title,media_type='tv',num_episodes=12,
        start_date='2026-01-01',alternative_titles={en='Another title'}}}}})
    assert(online.choose(online.candidates(mal,query),query).mal_id==991001,'Official MAL response uses the same matching rules')
    assert(not online.eligible({title='Ordinary Show'},'Ordinary Show S01E03.mkv',{}))
    assert(online.eligible({},'[SubsPlease] New Show - 03.mkv',{}))
    assert(online.eligible({},'New Show S01E03.mkv',{{type='audio',lang='jpn'}}))
    assert(not online.eligible({source='lampa',anime=false},'[SubsPlease] Show - 03.mkv',{}))
    local cache_path=path('maintenance/online-test-state.tmp')
    os.remove(cache_path)
    local now,calls,stale=10,0,false
    local settings={path=function()return cache_path end}
    local service=online.new(function(args)
        calls=calls+1
        assert(args.args[#args.args]:find('https://api.jikan.moe/v4/anime?',1,true))
        return {status=0,stdout=utils.format_json({data={first}})}
    end,settings,utils,function()return now end)
    local ok,err=xpcall(function()
        local list,match=service.search(query,function()return not stale end)
        assert(#list==1 and match.mal_id==991001 and calls==1)
        list,match=service.search(query,function()return true end)
        assert(match and calls==1,'Next episode must reuse catalog cache')
        local restarted=online.new(function()error('Must use persistent cache')end,settings,utils,function()return now end)
        list,match=restarted.search(query,function()return true end)
        assert(match,'Cached identity must survive a restart')
        local failed=online.new(function()return {status=22}end,settings,utils,function()return now end)
        list,match=failed.search({title='Different Anime',episode=1},function()return true end)
        assert(#list==0 and not match,'Service outage must leave media unresolved')
        local late=online.new(function()stale=true;return {status=0,stdout=utils.format_json({data={first}})}end,settings,utils,function()return now end)
        list,match=late.search({title='Late Anime',episode=1},function()return not stale end)
        assert(#list==0 and not match,'Discard late response after changing files')
        stale=false
        local offline=online.new(function()return {status=0,stdout='not json'}end,settings,utils,function()return now end)
        assert(#(offline.search({title='Bad JSON'},function()return true end))==0)
        local official=online.new(function(args)
            assert(args.args[#args.args]:find('https://api.myanimelist.net/v2/anime?',1,true))
            assert(args.args[#args.args-1]=='X-MAL-CLIENT-ID: test-client-id','Use application identification, never a user login')
            return {status=0,stdout=utils.format_json({data={{node={id=991005,title='Official Testing Anime',
                media_type='tv',start_date='2026-01-01',num_episodes=12}}}})}
        end,settings,utils,function()return now end,{mal_client_id='test-client-id'})
        list,match=official.search({title='Official Testing Anime',episode=3,kind='tv',year=2026},function()return true end)
        assert(match and match.mal_id==991005,'Official API uses the same strict automatic matcher')
    end,debug.traceback)
    os.remove(cache_path)
    assert(ok,err)
end
