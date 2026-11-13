-- Exercise menu choices, persistence and ownership of the GLSL shader list.
return function(path)
    local real,open = mp,io.open
    local settings_key,locale_key = 'mpv-build/user_settings','mpv-build/ui_locale'
    local saved_settings,saved_locale = package.loaded[settings_key],package.loaded[locale_key]
    local utils = require 'mp.utils'
    local props = {['glsl-shaders'] = {'personal/colour.glsl'}, ['current-vo'] = 'gpu-next'}
    local messages,bindings = {},{}
    local state,menu,warning,writes,missing = '',nil,nil,0,false
    local function noop() end
    local function read_property(key,default)
        local value = props[key]
        if value == nil then return default end
        return value
    end
    local mock = {
        get_property = read_property, get_property_native = read_property,
        set_property_native = function(key,value)
            props[key] = value
            if key == 'glsl-shaders' then writes = writes + 1 end
            return true
        end,
        command_native = function(args)
            if args[1] == 'normalize-path' then return args[2] end
            return args[2]:gsub('^~~/',path(''))
        end,
        commandv = function(command,script,event,json)
            if command == 'script-message-to' and event == 'open-menu' then menu = utils.parse_json(json) end
        end,
        register_script_message = function(name,fn) messages[name] = fn end,
        observe_property = noop, add_hook = noop, register_event = noop, enable_messages = noop,
        add_key_binding = function(key,name,fn) bindings[key or name] = fn end,
        osd_message = function(text) warning = text end,
    }
    local ok,err = xpcall(function()
        mp = mock
        package.loaded[settings_key] = {
            options = function(prefs)
                prefs.mode = state:match('mode=(%w+)') or prefs.mode
                prefs.engine = state:match('engine=(%w+)') or prefs.engine
                prefs.quality = state:match('quality=(%w+)') or prefs.quality
            end,
            path = function() return 'memory:anime4k' end,
        }
        package.loaded[locale_key] = {install_messages = noop}
        io.open = function(name,mode)
            if name ~= 'memory:anime4k' then
                if missing and name:find('/shaders/anime4k/',1,true) then return nil end
                return open(name,mode)
            end
            return {write = function(self,text) state = text; return self end, close = function() return true end}
        end
        -- The native file_info call is also used by the missing-file case.
        local file_info = utils.file_info
        utils.file_info = function(name)
            if missing then return nil end
            return file_info(name)
        end
        local loaded,load_error = xpcall(function()
            dofile(path('scripts/upscale.lua'))
            assert(writes == 0 and #props['glsl-shaders'] == 1,'Default off never clears personal shaders')
            bindings.menu()
            assert(menu.type == 'upscale' and #menu.items == 3 and #menu.items[2].items == 4 and menu.items[1].active,'Normal menu entry is reachable')
            for _,quality in ipairs({'fast','hq'}) do
                messages.quality(quality)
                for index,mode in ipairs({'A','B','C'}) do
                    bindings['Ctrl+'..index]()
                    local list = props['glsl-shaders']
                    assert(list[1] == 'personal/colour.glsl' and #list == (mode == 'C' and 6 or 7),'Mode switches preserve personal shaders without accumulating old chains')
                    assert(props['user-data/anime4k'].mode == mode and props['user-data/anime4k'].quality == quality)
                    assert(state:find('mode='..mode,1,true) and state:find('quality='..quality,1,true),'Persist both selections')
                    local variant = quality == 'hq' and '_VL.glsl' or '_M.glsl'
                    assert(list[3]:find(variant,1,true),'Use the selected CNN size')
                end
            end
            dofile(path('scripts/upscale.lua'))
            assert(props['user-data/anime4k'].mode == 'C' and #props['glsl-shaders'] == 6,'Restore preferences without duplicate shaders')
            local before = writes
            messages.mode('invalid'); messages.quality('invalid')
            assert(writes == before,'Reject invalid modes')
            props['current-vo'] = 'null'
            messages.mode('A')
            assert(writes == before and warning:find('gpu',1,true),'Unsupported video output retains the active selection')
            bindings['Ctrl+0']()
            assert(#props['glsl-shaders'] == 1 and props['glsl-shaders'][1] == 'personal/colour.glsl','CTRL+0 removes only Anime4K')
            props['current-vo'] = 'gpu-next'
            state = 'engine=artcnn\nmode=A\nquality=hq\nartcnn=hq\n'
            props['glsl-shaders'] = {'personal/colour.glsl', path('shaders/artcnn/ArtCNN_C4F32.glsl')}
            dofile(path('scripts/upscale.lua'))
            assert(#props['glsl-shaders'] == 1 and props['glsl-shaders'][1] == 'personal/colour.glsl','Remove only the retired bundled ArtCNN shader')
            assert(props['user-data/upscale'].engine == 'off' and props['user-data/anime4k'].mode == 'off','Retired selection cannot activate on launch')
            assert(state:find('engine=off',1,true) and not state:find('artcnn',1,true),'Persist the safe migrated selection')
            bindings.menu()
            for _,item in ipairs(menu.items) do assert(item.title ~= 'ArtCNN','No retired engine in menu') end
            props['glsl-shaders'][2] = path('shaders/artcnn/ArtCNN_C4F16.glsl')
            dofile(path('scripts/upscale.lua'))
            assert(#props['glsl-shaders'] == 1,'Clean stale bundled shaders even with a saved off preference')
            missing = true
            before = writes; messages.mode('A')
            assert(writes == before and props['user-data/anime4k'].mode == 'off','Missing files cannot partly install a chain or save a failed selection')
        end,debug.traceback)
        utils.file_info = file_info
        assert(loaded,load_error)
    end,debug.traceback)
    mp,io.open = real,open
    package.loaded[settings_key],package.loaded[locale_key] = saved_settings,saved_locale
    assert(ok,err)
end
