return function(path)
    local real,getenv=mp,os.getenv
    local options=package.loaded['mp.options']
    local utils=require 'mp.utils'
    local props={path='fixture.mkv',['media-title']='Reacher.S01E04.In.a.Tree.2160p.mkv',
        ['current-tracks/audio']={lang='jpn'},['user-data/interface-language']='ru',aid=3,sid=2,['playlist-pos']=0,
        playlist={{filename='fixture.mkv',title='Reacher.S01E04.In.a.Tree.2160p.mkv'}},['user-data/guessit']={}}
    local events,observers,requests,timers={},{},{},{}
    local function get(k,d) if props[k]==nil then return d end;return props[k] end
    local function set(k,v) props[k]=v end
    local function noop() end
    local mock={get_property=get,get_property_native=get,get_property_number=get,
        set_property=set,set_property_native=set,abort_async_command=noop,
        command_native=function() return path('') end,
        observe_property=function(k,_,fn) observers[k]=fn end,
        register_event=function(k,fn) events[k]=fn end,
        add_timeout=function(_,fn)
            local t={callback=fn,active=true,kill=function(self) self.active=false end}
            timers[#timers+1]=t;return t
        end,
        command_native_async=function(args,fn)
            requests[#requests+1]={args=args,callback=fn};return #requests
        end}
    local function tick()
        local copy=timers;timers={}
        for _,t in ipairs(copy) do if t.active then t.callback() end end
    end
    local function respond(n,data)
        assert(requests[n],'missing metadata request '..n)
        requests[n].callback(true,{status=0,stdout=utils.format_json(data)})
    end
    local ok,err=xpcall(function()
        mp=mock;package.loaded['mp.options']={read_options=noop}
        dofile(path('scripts/readable_titles.lua'))
        events['file-loaded']();tick()
        assert(props['user-data/readable-title'].text:find('серия 4',1,true))
        props['current-tracks/audio']={lang='eng'}
        if observers['current-tracks/audio'] then observers['current-tracks/audio']() end
        tick();assert(#requests==1,'Audio selection must not change title language: '..#requests..' '..require('mp.utils').format_json(props['user-data/readable-title']))
        props['user-data/interface-language']='en';observers['user-data/interface-language']();tick()
        assert(#requests==2)
        respond(1,{results={{id=99,name='Устаревший ответ',original_name='Reacher'}}})
        assert(#requests==2,'stale response started more requests')
        respond(2,{results={{id=108978,name='Reacher',original_name='Reacher'}}})
        respond(3,{name='Reacher'})
        respond(4,{episodes={{episode_number=4,name='In a Tree'}}})
        assert(props['user-data/readable-title'].text=='Reacher · Season 1, episode 4: In a Tree')
        props['user-data/interface-language']='ru';observers['user-data/interface-language']();tick()
        respond(5,{results={{id=108978,name='Ричер',original_name='Reacher'}}})
        respond(6,{name='Ричер'})
        respond(7,{episodes={{episode_number=4,name='Укрытие'}}})
        assert(props['user-data/readable-title'].text=='Ричер · Сезон 1, серия 4: Укрытие')
        assert(props['user-data/readable-title'].episodes['4']=='Укрытие')
        assert(props['media-title']==props.playlist[1].title,'source title changed')
        events['end-file']()
        assert(props['user-data/readable-title'].text==nil,'stale title on end-file')
        props['media-title']='Protector.2025.2160p.mkv'
        props.playlist[1].title=props['media-title']
        events['file-loaded']();tick()
        assert(requests[8].args.args[#requests[8].args.args]:find('&year=2025',1,true))
        respond(8,{results={}})
        assert(not requests[9].args.args[#requests[9].args.args]:find('&year=',1,true),'Fallback removes strict year')
        respond(9,{results={{id=1383731,title='Мститель',original_title='Protector',release_date='2026-02-20'}}})
        respond(10,{title='Мститель'})
        assert(props['user-data/readable-title'].text=='Мститель (2025)','Localized movie with release-year offset')
        assert(props['media-title']=='Protector.2025.2160p.mkv','Movie source title preserved')
        events['end-file']()
        props['media-title']='Kusuriya no Hitorigoto S3 - 02 [1080p].mkv'
        props.playlist[1].title=props['media-title']
        events['file-loaded']();tick()
        local url=requests[11].args.args[#requests[11].args.args]
        assert(url:find('/tv/220542?language=ru',1,true),'Known anime uses its mapped catalog identity')
        respond(11,{name='Монолог фармацевта'})
        assert(requests[12].args.args[#requests[12].args.args]:find('/season/1?',1,true))
        respond(12,{episodes={{episode_number=50,name='Тестовая серия'}}})
        assert(props['user-data/readable-title'].text=='Монолог фармацевта · Сезон 3, серия 2: Тестовая серия')
        props['user-data/interface-language']='en';observers['user-data/interface-language']();tick()
        respond(13,{name='The Apothecary Diaries'})
        respond(14,{episodes={{episode_number=50,name='Test episode'}}})
        assert(props['user-data/readable-title'].text=='The Apothecary Diaries · Season 3, episode 2: Test episode')
        assert(props.aid==3 and props.sid==2,'Metadata must not change selected tracks')
        assert(props['media-title']==props.playlist[1].title,'Anime source title preserved')
        events['end-file']()
        props['user-data/interface-language']='ru'
        props['media-title']='01. Kusuriya no Hitorigoto 3 (WEBRip 1080p).mkv'
        props.playlist[1].title=props['media-title']
        events['file-loaded']();tick()
        assert(props['user-data/readable-title'].text=='Монолог фармацевта · Сезон 3, серия 1','Leading episode filename uses the same localized series')
        assert(props['user-data/readable-title'].source_title=='Kusuriya no Hitorigoto')
        events['end-file']()
        props['media-title']='Dan Da Dan S02E01.mkv';props.playlist[1].title=props['media-title']
        events['file-loaded']();tick()
        assert(requests[15].args.args[#requests[15].args.args]:find('/tv/240411?',1,true))
        respond(15,{name='Dandadan'})
        local fallback=requests[16].args.args
        assert(fallback[#fallback]=='https://shikimori.one/api/animes/60543')
        assert(not table.concat(fallback,' '):find('Bearer',1,true),'TMDB credentials must never reach another provider')
        respond(17,{episodes={{episode_number=1,name='Начало'}}})
        respond(16,{id=60543,russian='Дандадан',english={'Dandadan'}})
        assert(props['user-data/readable-title'].text=='Дандадан · Сезон 2, серия 1: Начало')
        events['end-file']()
        props['media-title']='[ReinForce] Dan Da Dan (S01) (2024) - 03 [BDRip 1080p x264 FLAC].mkv'
        props.playlist[1].title=props['media-title']
        events['file-loaded']();tick()
        assert(props['user-data/readable-title'].text=='Дандадан · Сезон 1, серия 3','Local title works before network metadata')
        assert(requests[19].args.args[#requests[19].args.args]:find('/tv/240411/season/1?',1,true),'Parenthesized season uses known anime ID')
        requests[18].callback(false,{status=7,stdout=''})
        requests[19].callback(false,{status=7,stdout=''})
        assert(props['user-data/readable-title'].text=='Дандадан · Сезон 1, серия 3','Network failure retains local title')
        events['end-file']()
        props['media-title']='Runner.2026.1080p.WEB-DL.mkv';props.playlist[1].title=props['media-title']
        events['file-loaded']();tick()
        assert(props['user-data/readable-title'].text=='Курьер (2026)','Runner has an immediate Russian movie title')
        events['end-file']()
        for _,case in ipairs({
            {folder='Demon Slayer - Kimetsu no Yaiba Entertainment District Arc',season=3},
            {folder='Kimetsu no Yaiba - Hashira Geiko Hen [TV-4] [2024] [WEBRip] [1080p] [RUS + JAP]',season=5},
        }) do
            props.path='http://localhost/stream?link=abcdef&index=3&play'
            props['media-title']='Kimetsu no Yaiba - 03 1920x1080.mkv';props.playlist[1].title=props['media-title']
            props['user-data/torrserver-context']={media=props.path,path=case.folder..'/03.1920x1080.mkv'}
            props['user-data/guessit']={input=props.path,season=1920,episode=1080}
            local before=#requests
            events['file-loaded']();tick()
            for n=before+1,#requests do
                if requests[n].args.args[#requests[n].args.args]:find('/tv/85937?',1,true) then respond(n,{name='Истребитель демонов'});break end
            end
            local season_request
            for n=before+1,#requests do
                local url=requests[n].args.args[#requests[n].args.args]
                if url:find('/season/',1,true) then season_request=n;assert(url:find('/season/'..case.season..'?',1,true),'Use the arc season for episode names') end
            end
            assert(season_request);respond(season_request,{episodes={{episode_number=3,name='Верная серия арки'}}})
            assert(props['user-data/readable-title'].text=='Истребитель демонов · Сезон '..case.season..', серия 3: Верная серия арки')
            events['end-file']()
        end
        -- Lampa supplies only the selected episode; one season response must
        -- also name siblings, even when that selected episode already has a name.
        local anchor='http://localhost/stream?link='..string.rep('a',40)..'&index=1&play'
        local files={{id=1,path='MobLand_S01E01_RHS_4K_[scarfilm].mkv'},{id=2,path='MobLand_S01E02_RHS_4K_[scarfilm].mkv'}}
        os.getenv=function(k)
            if k=='MPV_PLUS_LAMPA_CONTEXT' then return utils.format_json({version=1,source='lampa',entries={{url=anchor,identity={
                title='Гангстерленд',original_title='MobLand',kind='tv',tmdb_id=247718,season=1,episode=1,episode_title='Пан или пропал',
            }}}}) end
            return getenv(k)
        end
        props.path=anchor;props['media-title']=files[1].path;props.playlist={{filename=anchor,title=files[1].path}}
        props['user-data/torrserver-context']={media=anchor,path=files[1].path,files=files}
        props['user-data/guessit']={}
        dofile(path('scripts/readable_titles.lua'))
        local before=#requests
        events['file-loaded']();tick()
        assert(props['user-data/readable-title'].text=='Гангстерленд · Сезон 1, серия 1: Пан или пропал')
        assert(requests[before+1].args.args[#requests[before+1].args.args]:find('/tv/247718?',1,true),'Use the verified card ID')
        respond(before+1,{name='Гангстерленд'})
        respond(before+2,{episodes={{episode_number=1,name='Пан или пропал'},{episode_number=2,name='Пазл'}}})
        assert(props['user-data/readable-title'].episodes['2']=='Пазл','Named Lampa entries still populate the whole season')
        events['end-file']();props.path=anchor:gsub('index=1','index=2')
        props['media-title']=files[2].path;props.playlist={{filename=props.path,title=files[2].path}}
        props['user-data/torrserver-context']={media=props.path,path=files[2].path,files=files}
        local cached=#requests;events['file-loaded']();tick()
        assert(props['user-data/readable-title'].text=='Гангстерленд · Сезон 1, серия 2: Пазл','Sibling identity resolves to its actual episode name: '..utils.format_json(props['user-data/readable-title']))
        assert(#requests==cached,'Episode changes reuse the season dictionary')
        events['end-file']();props['user-data/interface-language']='en'
        local failed_title=#requests;events['file-loaded']();tick()
        requests[failed_title+1].callback(false,{status=7,stdout=''})
        assert(requests[failed_title+2].args.args[#requests[failed_title+2].args.args]:find('/season/1?',1,true),'A failed series-title lookup must not block the season dictionary')
        respond(failed_title+2,{episodes={{episode_number=2,name='Puzzle'}}})
        assert(props['user-data/readable-title'].episodes['2']=='Puzzle','Sibling names remain available after a temporary series-title error')
    end,debug.traceback)
    mp,os.getenv=real,getenv;package.loaded['mp.options']=options
    assert(ok,err)
end
