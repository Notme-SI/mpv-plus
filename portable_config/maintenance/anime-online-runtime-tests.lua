-- Real async lookup script, without network access or any text-input UI.
return function(path)
    local real,old_path=mp,package.path
    local modules={'mp.options','mp.msg','mp.input','encoding','database','mpv-build/user_settings','mpv-build/ui_locale'}
    local saved={};for _,name in ipairs(modules)do saved[name]=package.loaded[name] end
    local utils=require 'mp.utils'
    local props={path='https://example.invalid/stream?link=aabb&index=1&play',duration=1440,
        ['playlist-pos']=0,['idle-active']=false,pause=false,['track-list']={{type='audio',lang='jpn'}},
        playlist={{filename='one',title='[SubsPlease] Unlisted Testing Anime - 03.mkv'}}}
    local events,requests={},{},{}
    local now=100
    local function noop()end
    local function get(k,d)if props[k]==nil then return d end;return props[k] end
    local function set(k,v)props[k]=v end
    local function state_path(name)return path('maintenance/anime-online-runtime-'..name..'.tmp')end
    local files={state_path('anime-bindings.json'),state_path('anime-search-cache.json')}
    for _,file in ipairs(files)do os.remove(file)end
    local mock={get_property=get,get_property_native=get,get_property_number=get,get_property_bool=get,
        set_property=set,set_property_native=set,set_property_bool=set,osd_message=noop,
        get_time=function()return now end,get_opt=function()end,
        get_script_name=function()return 'autochapters'end,get_script_directory=function()return path('scripts/autochapters')end,
        command_native=function(args)if args[1]=='expand-path' then return path(args[2]:gsub('^~~/','')) end;error('Blocking subprocess')end,
        command_native_async=function(args,callback)requests[#requests+1]={args=args,callback=callback};return #requests end,
        abort_async_command=noop,commandv=noop,
        register_event=function(name,fn)events[name]=fn end,
        register_script_message=noop,add_key_binding=noop,add_hook=noop,observe_property=noop,
        add_timeout=function()return {kill=noop}end,
        msg={warn=noop,info=noop,log=noop}}
    local function answer(payload,status)
        local request=requests[#requests];assert(request,'Missing async request')
        request.callback(true,{status=status or 0,stdout=utils.format_json(payload)})
        return request
    end
    local function url()local args=requests[#requests].args.args;return args[#args]end
    local ok,err=xpcall(function()
        mp=mock
        package.loaded['mp.options']={read_options=noop};package.loaded['mp.msg']=mock.msg
        package.loaded['mp.input']={get=function()error('Anime identification must not ask for text input')end}
        package.loaded['mpv-build/user_settings']={options=noop,path=state_path}
        package.loaded['mpv-build/ui_locale']={install_messages=noop,text=function(t)return t end,language=function()return 'ru'end}
        package.path=path('scripts/autochapters/?.lua')..';'..package.path
        dofile(path('scripts/autochapters/main.lua'))
        events['file-loaded']()
        answer({title='Unlisted Testing Anime',episode=3,season=1,year=2026})
        assert(url():find('api.jikan.moe',1,true),'Unrecognized anime must reach online lookup')
        answer({data={
            {mal_id=991101,title='Unlisted Testing Anime',year=2026,type='TV',episodes=12},
            {mal_id=991102,title='Unlisted Testing Anime',year=2026,type='TV',episodes=12}}})
        assert(not next(props['user-data/autochapters']),'Ambiguous result must not apply skip times')
        now=now+2;props.playlist[1].title='[SubsPlease] New Testing Anime - 03.mkv'
        events['end-file']();events['file-loaded']()
        answer({title='New Testing Anime',episode=3,season=1,year=2026})
        answer({data={{mal_id=991103,title='New Testing Anime',year=2026,type='TV',episodes=12}}})
        assert(url():find('/991103/3?',1,true),'An exact unique result must reach AniSkip automatically')
        assert(props['user-data/anime-online'].identity.mal_id==991103,'Publish the verified identity for title metadata')
        answer({results={}});answer({results={}})
        props.playlist[1].title='[SubsPlease] New Testing Anime - 04.mkv';now=now+2
        events['end-file']();events['file-loaded']()
        answer({title='New Testing Anime',episode=4,season=1,year=2026})
        assert(url():find('/991103/4?',1,true),'Next episode reuses catalog cache without another search')
        answer({results={}});answer({results={}})
        props.playlist[1].title='[SubsPlease] Late Testing Anime - 01.mkv';now=now+2
        events['end-file']();events['file-loaded']()
        answer({title='Late Testing Anime',episode=1,season=1,year=2026})
        assert(url():find('api.jikan.moe',1,true))
        events['end-file']();local count=#requests
        answer({data={{mal_id=991104,title='Late Testing Anime',year=2026,type='TV',episodes=12}}})
        assert(#requests==count and not next(props['user-data/anime-online']),'Discard late catalog responses')
        events.shutdown()
    end,debug.traceback)
    mp,package.path=real,old_path
    for _,name in ipairs(modules)do package.loaded[name]=saved[name] end
    for _,file in ipairs(files)do os.remove(file)end
    assert(ok,err)
end
