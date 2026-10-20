-- Exercise the actual upstream loader, including its on_load hook.
return function(path)
    local real=mp
    local utils=require 'mp.utils'
    local subprocess=utils.subprocess
    local saved_options,saved_input=package.loaded['mp.options'],package.loaded['mp.input']
    local hash=string.rep('a',40)
    local media='http://127.0.0.1:8090/stream?link='..hash..'&index=8&play'
    local props={path=media,['playlist-pos']=4,aid=3,sid=2}
    local hooks,events,observers,bindings,requests,sidecars={},{},{},{},{},{}
    local function noop()end
    local function get(k,d)if props[k]==nil then return d end;return props[k]end
    local mock={get_property=get,get_property_native=get,get_property_number=get,
        set_property_native=function(k,v)props[k]=v end,set_property_number=function(k,v)props[k]=v end,
        command_native=function(a)assert(a[1]=='expand-path');return path(a[2]:gsub('^~~/',''))end,
        command_native_async=function(a,fn)sidecars[#sidecars+1]={args=a,callback=fn};return #sidecars end,
        commandv=function(a)assert(a~='loadlist','Opening must preserve the incoming Lampa playlist')end,
        osd_message=noop,abort_async_command=noop,unobserve_property=noop,
        add_hook=function(k,_,fn)hooks[k]=fn end,
        register_event=function(k,fn)events[k]=fn end,observe_property=function(k,_,fn)observers[k]=fn end,
        add_key_binding=function(_,name,fn)bindings[name]=fn end,add_timeout=function()return {kill=noop}end,
        msg={warn=noop,info=noop}}
    local ok,err=xpcall(function()
        mp=mock;package.loaded['mp.options']={read_options=noop};package.loaded['mp.input']={select=noop}
        utils.subprocess=function(a)requests[#requests+1]=a.args;return {status=28,stderr='timeout'}end
        dofile(path('vendor/torrserver_loader.lua'))
        hooks.on_load()
        assert(#requests==0 and #sidecars==0,'on_load must not wait for an API or attach tracks before playback')
        events['file-loaded']()
        assert(#requests==0,'file-loaded must not call the synchronous curl helper')
        props['user-data/torrserver-context']={media=media,hash=hash,title='Kimetsu no Yaiba - Hashira Geiko Hen [TV-4]',
            files={{id=8,path='Hashira/Kimetsu - 08.mkv',length=1024},{id=9,path='Hashira/Kimetsu - 08.rus.ass',length=50},
                {id=10,path='Hashira/Kimetsu - 09.mkv',length=1024}}}
        observers['user-data/torrserver-context']()
        assert(#sidecars==1 and sidecars[1].args[1]=='sub-add','Attach external subtitles after metadata arrives')
        assert(sidecars[1].args[2]:find('index=9&play',1,true),'Attach the right file without using playlist position as file ID')
        sidecars[1].callback(true)
        observers['user-data/torrserver-context']()
        assert(#sidecars==1,'Do not attach a sidecar twice')
        assert(props['playlist-pos']==4 and props.aid==3 and props.sid==2,'Do not replace playlist position or track selections')
        events['end-file']();hooks.on_load()
        assert(#requests==0,'Reopening must not wait for the configured API either')
        bindings.torr_open()
        assert(#requests==1,'Manual library browsing still calls the API')
        local args=requests[1]
        local options={}
        for i,value in ipairs(args)do options[value]=args[i+1]end
        assert(options['--connect-timeout']=='2' and options['--max-time']=='3','Bound manual library requests')
    end,debug.traceback)
    mp=real;utils.subprocess=subprocess;package.loaded['mp.options']=saved_options;package.loaded['mp.input']=saved_input
    assert(ok,err)
    do
        local original=mp
        local source=dofile(path('extensions/media_source.lua'))
        local hash=string.rep('b',40)
        local url='https://active.invalid/proxy/stream/Episode%202.mkv?link='..hash..'&index=2&play&token=fixture'
        local props={path=url,['playlist-pos']=0,playlist={{filename=url,id=77}}}
        local calls={}
        local context={media=url,hash=hash,files={{id=1,path='01. Первая.mkv'},{id=2,path='02. Вторая.mkv'},
            {id=3,path='03. Третья, серия.MKV'},{id=4,path='02. Вторая.rus.ass'},{id=5,path='cover.jpg'}}}
        local function get(k,d)if props[k]~=nil then return props[k]end;return d end
        local ok,err=xpcall(function()
            mp={get_property=get,get_property_native=get,get_property_number=get,commandv=function(...)
                local args={...};calls[#calls+1]=args
                if args[1]=='loadlist'then props.playlist[2]={filename='fixture-added'}end
            end}
            source.complete_playlist(context)
            assert(#calls==2 and calls[1][1]=='loadlist' and calls[1][3]=='append' and calls[2][1]=='playlist-move','Append named episodes and reorder around the active item')
            local m3u=calls[1][2]
            assert(m3u:find('Третья, серия.MKV',1,true) and not m3u:find('.ass',1,true) and not m3u:find('cover.jpg',1,true),'Only video episodes enter the playlist')
            assert(m3u:find('https://active.invalid/proxy/stream?',1,true) and m3u:find('token=fixture',1,true),'Use actual playback origin, prefix and token')
            assert(not m3u:find('index=2&play',1,true),'Never append the currently playing episode again')
            source.complete_playlist(context);assert(#calls==2,'An existing playlist is preserved without duplicates')
            props.playlist={{filename=url,id=77}};context.hash=string.rep('c',40)
            source.complete_playlist(context);assert(#calls==2,'Never use metadata from another torrent')
            context.hash=hash;props.path='edl://!new_stream;'..url
            props.playlist={{filename=props.path,id=77}};context.media=props.path
            source.complete_playlist(context);assert(#calls==4,'Incoming EDL video can also gain the missing episode playlist')
        end,debug.traceback)
        mp=original;assert(ok,err)
    end

end
