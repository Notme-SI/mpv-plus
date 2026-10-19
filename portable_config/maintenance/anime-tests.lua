return function(path)
    local fmt=dofile(path('extensions/title_format.lua'))
    local anime=dofile(path('extensions/anime_identity.lua'))
    local skips=dofile(path('extensions/skip_segments.lua'))
    local index=anime.index({['Kusuriya no Hitorigoto']=54492,['Kusuriya no Hitorigoto 2nd Season']=58514,
        ['Kusuriya no Hitorigoto 3rd Season']=61987,['The Apothecary Diaries Season 3']=61987})
    for _,raw in ipairs({'Kusuriya no Hitorigoto S3 - 01.mkv','01. Kusuriya no Hitorigoto 3 (WEBRip 1080p).mkv',
        'Kusuriya no Hitorigoto 3rd Season - 01.mkv'}) do
        local data=anime.enrich(raw,fmt.parse(raw),index)
        assert(data.title=='Kusuriya no Hitorigoto' and data.episode==1 and data.season==3,raw)
        assert(data.mal_id=='61987','Third season must not resolve to first season: '..raw)
    end
    local unknown='Kusuriya no Hitorigoto S4 - 01.mkv'
    assert(not anime.enrich(unknown,fmt.parse(unknown),index).mal_id,'Unknown season must not use first-season times')
    local raw='01. Unknown Film 3.mkv'
    assert(anime.enrich(raw,fmt.parse(raw),index).title==fmt.parse(raw).title,'Do not strip unconfirmed titles')
    local demon=anime.index({['Kimetsu no Yaiba']=38000})
    local numeric=anime.from_source('02.mkv',{},anime.index({['02']=49523}))
    assert(not numeric.mal_id and numeric.episode==2,'An episode filename must not identify a film named 02')
    numeric=anime.from_source('02.mkv',{path='C:/Users/User/Downloads/Video/02.mkv'},anime.index({['C']=10163}))
    assert(not numeric.mal_id,'A Windows drive letter must not identify an anime named C')
    local arcs=anime.index({['Kimetsu no Yaiba']=38000,['Demon Slayer - Kimetsu no Yaiba Entertainment District Arc']=47778,
        ['Kimetsu no Yaiba - Hashira Geiko Hen']=55701})
    for _,case in ipairs({
        {folder='Demon Slayer - Kimetsu no Yaiba Entertainment District Arc',season=3,mal='47778'},
        {folder='Kimetsu no Yaiba - Hashira Geiko Hen [TV-4] [2024] [WEBRip] [1080p] [RUS + JAP]',season=5,mal='55701'},
    }) do
        local identity=anime.from_source('Kimetsu no Yaiba - 03 1920x1080.mkv',{path=case.folder..'/03.1920x1080.mkv'},arcs)
        assert(tostring(identity.mal_id)==case.mal and identity.season==case.season,'Named torrent arc must beat an inferred first season')
        assert(identity.episode==3 and identity.tmdb_season==case.season and identity.tmdb_episode==3,'Use the same coordinates for title and skip providers')
    end
    for _,name in ipairs({'02.Trainer.Sakonji.Urokodaki.mkv','02.mkv'}) do
        local data=anime.from_source(name,{path='Kimetsu no Yaiba/'..name},demon)
        assert(data.mal_id=='38000' and data.episode==2,'Resolve episode-only files from their folder')
        data=anime.from_source(name,{title='Kimetsu no Yaiba',path=name},demon)
        assert(data.mal_id=='38000' and data.episode==2,'Resolve episode-only files from the torrent title')
        assert(not anime.from_source(name,{title='Unknown Show',path=name},demon).anime,'Never invent a series match')
    end
    local episode_title=anime.from_source('13 Something More Important Than Life.mkv',
        {path='Kimetsu no Yaiba/13 Something More Important Than Life.mkv'},demon)
    assert(episode_title.mal_id=='38000' and episode_title.episode==13,
        'Use the torrent/folder series when the file starts with an episode title')
    assert(not anime.from_source('02.mkv',{},anime.index({['!!!']=1})).anime,'Empty title is not a catalog match')
    local chapters={{time=0,title='Prologue'},{time=62.94,title='Opening'},{time=152.993,title='Episode'},
        {time=1335,title='Ending'},{time=1425.053,title='Epilogue'}}
    local native=skips.from_chapters(chapters,1440.085,fmt.normalize)
    assert(math.abs(native.intro[1].start_ms-62940)<0.001 and math.abs(native.intro[1].end_ms-152993)<0.001)
    assert(native.credits[1].start_ms==1335000 and not native.preview,'Epilogue is not automatically skippable')
    local themed={{time=0,title='chapter 1'},{time=32,title='opening theme'},{time=121,title='subtitle'},
        {time=128,title='chapter 2'},{time=478,title='chapter 3'},{time=1289,title='ending theme'},
        {time=1379,title='next notice'}}
    local themed_native=skips.from_chapters(themed,1380,fmt.normalize)
    assert(themed_native.intro[1].start_ms==32000 and themed_native.credits[1].start_ms==1289000
        and themed_native.preview[1].start_ms==1379000,'Recognize theme and next-notice chapter names')
    assert(not next(skips.from_chapters({{time=0,title='Part 01'},{time=90,title='Part 02'}},1440,fmt.normalize)))
    assert(not next(skips.from_chapters({{time=0,title='Opening'}},1440,fmt.normalize)),'Unknown intro end is unsafe')
    assert(not next(skips.from_chapters({{time=0,title='Opening'},{time=700,title='Episode'}},1440,fmt.normalize)))
    local online={intro={{start_ms=63313,end_ms=153237}},credits={{start_ms=1335252,end_ms=1425384}}}
    local combined=skips.combine({intro={{start_ms=0,end_ms=95000}},preview={{start_ms=1355000}}},online,native)
    assert(combined.intro==native.intro and combined.credits==native.credits and not combined.preview)
    assert(skips.combine({},online,{}).intro==online.intro,'Online fallback for files without chapters')
    local short_logo=skips.from_chapters({{time=0,title='Intro'},{time=10,title='Part A'},
        {time=229,title='Opening'},{time=319,title='Part B'}},1440,fmt.normalize)
    assert(#short_logo.intro==1 and short_logo.intro[1].start_ms==229000,'Studio logo is not another opening')
    assert(skips.from_chapters({{time=0,title='OP'},{time=90,title='Part A'}},1440,fmt.normalize).intro[1].start_ms==0,
        'A genuine opening can begin at zero')
    local valid=skips.flatten({intro={{end_ms=90000},{start_ms=0},{start_ms=0,end_ms=0},
        {start_ms=35000,end_ms=150000},{start_ms=35100,end_ms=150100}},
        credits={{start_ms=1400000,end_ms=1550000}},preview={{start_ms=1420000}}},1440)
    assert(#valid==2 and valid[1].start==35 and valid[1]['end']==150 and valid[2]['end']==1440,
        'Reject incomplete or out-of-range times, deduplicate, permit an explicit final preview')
    assert(not skips.validate('intro',{start_ms=0/0,end_ms=90000},1440),'Reject NaN')
    local function result(length,start,finish)
        return {skipType='op',episodeLength=length,interval={startTime=start,endTime=finish}}
    end
    assert(not next(skips.aniskip({result(1422,0,95)},1440)),'Different cuts must not use the old 18-second fallback')
    assert(not next(skips.aniskip({result(nil,0,95)},1440)),'Missing release length is not a match')
    assert(not next(skips.aniskip({result(1440,0,95),result(1440,35,150)},1440)),'Conflicting equally good community times are ambiguous')
    assert(skips.aniskip({result(1440,35,150)},1440).op.segment.interval.startTime==35)

    -- Exercise the actual clickable prompt in both languages, including a live switch.
    local real=mp
    local saved=package.loaded['mpv-build/ui_locale'];package.loaded['mpv-build/ui_locale']=nil
    local props={['time-pos']=70,['idle-active']=false,['user-data/interface-language']='ru'}
    local observers,overlay,timer={},{},nil
    local function get(k,d) if props[k]==nil then return d end;return props[k] end
    local function noop() end
    local mock={get_property_native=get,get_property_number=get,get_property_bool=get,
        set_property_native=function(k,v) props[k]=v end,
        command_native=function(a) return path(a[2]:gsub('^~~/','')) end,
        create_osd_overlay=function() return overlay end,get_osd_size=function() return 1280,720 end,
        observe_property=function(k,_,f) observers[k]=f end,register_event=noop,
        add_forced_key_binding=noop,remove_key_binding=noop,commandv=noop}
    mock.add_timeout=function(delay,fn)
        timer={delay=delay,fn=fn,kill=noop};return timer
    end
    overlay.update=noop;overlay.remove=function() overlay.data='' end
    local ok,err=xpcall(function()
        mp=mock
        local ui=dofile(path('extensions/ui_locale.lua'))
        dofile(path('scripts/skip_prompt.lua'))
        for kind,text in pairs({intro={'Пропустить: Заставку','Skip: Intro'},credits={'Пропустить: Титры','Skip: Credits'},
            recap={'Пропустить: Ранее в сериале','Skip: Recap'},preview={'Пропустить: Анонс','Skip: Preview'}}) do
            props['user-data/interface-language']='ru'
            observers['user-data/skip-prompt'](nil,{kind=kind,start=63,['end']=153})
            assert(overlay.data:find(text[1],1,true),'Russian prompt '..kind)
            props['user-data/interface-language']='en';observers['user-data/interface-language']()
            assert(overlay.data:find(text[2],1,true),'Live English prompt '..kind)
            assert(not overlay.data:find('Пропустить',1,true),'Stale Russian prompt')
        end
        assert(ui.chapter_text('Opening','ru')=='Заставка (OP)' and ui.chapter_text('Ending','en')=='Credits (ED)')
        assert(ui.menu({type='chapters',items={{title='Opening'},{title='Chapter named by author'}}}).items[1].title=='Intro (OP)')
        props['time-pos']=160;observers['time-pos']()
        assert(props['user-data/skip-prompt-visible']==false,'Hide the prompt after its interval')
        props['user-data/interface-language']='ru'
        observers['user-data/skip-prompt'](nil,{kind='credits',start=63,['end']=153,auto=true,notice=true})
        assert(timer.delay==3,'Automatic skip confirmation lasts 3 seconds')
        observers['user-data/skip-prompt'](nil,{})
        observers['time-pos']()
        assert(props['user-data/skip-prompt-visible'],'Normal updates must not erase the skip confirmation')
        assert(overlay.data:find('Пропущено:',1,true),'Show the completed skip separately from an upcoming action')
        timer.fn();assert(not props['user-data/skip-prompt-visible'],'Confirmation expires')
    end,debug.traceback)
    mp=real;package.loaded['mpv-build/ui_locale']=saved
    assert(ok,err)
end
