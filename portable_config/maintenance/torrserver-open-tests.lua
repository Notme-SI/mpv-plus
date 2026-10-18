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
end
