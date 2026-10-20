-- Shared language for the interface and media titles. Track preferences are independent.
if package.loaded['mpv-build/ui_locale'] then return package.loaded['mpv-build/ui_locale'] end
local M={}
package.loaded['mpv-build/ui_locale']=M
local utils=require 'mp.utils'
local root=mp.command_native({'expand-path','~~/'})
local function read(path)
    local f=io.open(root..'/'..path,'rb')
    if not f then return '' end
    local value=f:read('*a');f:close();return value
end
local settings=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua')
local language_file=io.open(settings.path('script-opts/interface.conf'),'rb')
local saved='ru'
if language_file then saved=language_file:read('*a'):match('language%s*=%s*(%a+)') or saved;language_file:close() end
local entries=assert(utils.parse_json(read('extensions/interface-translations.json')))
local exact,formats={},{}
local function escape(s) return (s:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])','%%%1')) end
local function pattern(s)
    local parts,start={},1
    while true do
        local a,b=s:find('%%[sdg]',start)
        if not a then parts[#parts+1]=escape(s:sub(start));break end
        parts[#parts+1]=escape(s:sub(start,a-1));parts[#parts+1]='(.-)';start=b+1
    end
    return '^'..table.concat(parts)..'$'
end
for _,entry in ipairs(entries) do
    exact[entry.ru],exact[entry.en]=entry,entry
    if entry.en:find('%%[sdg]') then
        formats[#formats+1]={en=pattern(entry.en),ru=pattern(entry.ru),entry=entry}
    end
end
table.sort(formats,function(a,b) return #a.ru>#b.ru end)
function M.language()
    local current=mp.get_property_native('user-data/interface-language',saved)
    return current=='en' and 'en' or 'ru'
end
function M.text(value,language)
    if type(value)~='string' then return value end
    language=language or M.language()
    local entry=exact[value]
    if entry then return entry[language] end
    for _,item in ipairs(formats) do
        for _,source in ipairs({'ru','en'}) do
            local captures={value:match(item[source])}
            if #captures>0 then
                local i=0
                return (item.entry[language]:gsub('%%[sdg]',function()
                    i=i+1
                    local v=captures[i] or ''
                    return item.entry.translate_args and M.text(v,language) or v
                end))
            end
        end
    end
    -- Fixed help fragments can be combined with shortcuts or track metadata.
    for _,separator in ipairs({' · ', ', '}) do
        if value:find(separator,1,true) then
            local pieces,start={},1
            while true do
                local a,b=value:find(separator,start,true)
                if not a then pieces[#pieces+1]=M.text(value:sub(start),language);break end
                pieces[#pieces+1]=M.text(value:sub(start,a-1),language);start=b+1
            end
            return table.concat(pieces,separator)
        end
    end
    local label,suffix=value:match('^(.-)( %b())$')
    if label and exact[label] then return M.text(label,language)..suffix end
    return value
end
-- Translate standard chapter labels only in chapter UI, never media titles.
function M.chapter_text(value,language)
    local names={opening='Заставка (OP)',op='Заставка (OP)',ending='Титры (ED)',ed='Титры (ED)',
        intro='Заставка',credits='Титры',recap='Ранее в сериале',preview='Анонс'}
    local label=type(value)=='string' and names[value:lower():match('^%s*(.-)%s*$')]
    return M.text(label or value,language)
end
local interface_menus={menu=true,keybinds=true,['player-timeline-style']=true,['player-icons']=true,
    ['interface-language']=true,['picture-controls']=true,['language-defaults']=true,['audio-memory']=true,
    autocrop=true,['autocrop-settings']=true,theintrodb=true,['subtitle-memory']=true,['network-playback']=true,['player-controls']=true}
function M.menu(data)
    local kind=data.type
    local function walk(node,is_menu)
        local copy={}
        for k,v in pairs(node) do copy[k]=v end
        local command=type(node.value)=='table' and node.value[1] or node.value
        local special=type(command)=='string' and command:match('^%{')
        if is_menu or interface_menus[kind] or node.items or special then copy.title=M.text(node.title)
        elseif kind=='chapters' then copy.title=M.chapter_text(node.title) end
        -- Track and file titles are never translated. Only their standard UI metadata is.
        copy.hint=M.text(node.hint)
        copy.footnote=M.text(node.footnote)
        copy.search_suggestion=M.text(node.search_suggestion)
        for _,field in ipairs({'actions','item_actions'}) do
            if node[field] then
                copy[field]={}
                for i,action in ipairs(node[field]) do
                    local a={};for k,v in pairs(action) do a[k]=v end
                    a.label=M.text(a.label);copy[field][i]=a
                end
            end
        end
        -- Name saved personal menu entries by their binding, not an obsolete label.
        if kind=='menu' then
            local binding=(type(node.value)=='table' and node.value[1]=='script-binding' and node.value[2])
                or (type(node.value)=='string' and node.value:match('^script%-binding%s+(.+)$'))
            if binding=='player_ui/controls_menu' then copy.title=M.text('Панель плеера') end
        end
        if node.items then
            copy.items={}
            local removed={['theintrodb/theintrodb-skip-intro']=true,
                ['theintrodb/theintrodb-skip-recap']=true,['theintrodb/theintrodb-skip-credits']=true,
                ['theintrodb/theintrodb-skip-preview']=true}
            for _,item in ipairs(node.items) do
                local binding=(type(item.value)=='table' and item.value[1]=='script-binding' and item.value[2])
                    or (type(item.value)=='string' and item.value:match('^script%-binding%s+(.+)$'))
                if kind~='menu' or not removed[binding] then copy.items[#copy.items+1]=walk(item,false) end
            end
        end
        return copy
    end
    local result=walk(data,true)
    -- Add local features to older personal menus without rewriting input.conf.
    if kind=='menu' and result.items then
        local function has(node,binding)
            if type(node.value)=='table' and node.value[1]=='script-binding' and node.value[2]==binding then return true end
            if type(node.value)=='string' and node.value=='script-binding '..binding then return true end
            for _,item in ipairs(node.items or {}) do if has(item,binding) then return true end end
            return false
        end
        if not has(result,'subtitle_memory/menu') then
            local target
            for _,item in ipairs(result.items) do
                if item.items and (item.title==M.text('Субтитры') or item.title=='Subtitles') then target=item;break end
            end
            if not target then target={title=M.text('Субтитры'),items={}};result.items[#result.items+1]=target end
            target.items[#target.items+1]={title=M.text('Запоминание для сериала'),value={'script-binding','subtitle_memory/menu'}}
        end
        if not has(result,'network_playback/menu') then
            table.insert(result.items,math.max(1,#result.items),{title=M.text('Сеть и буфер'),value={'script-binding','network_playback/menu'}})
        end
        if not has(result,'player_ui/controls_menu') then
            local target
            for _,item in ipairs(result.items)do if item.items and item.title==M.text('Интерфейс')then target=item;break end end
            if not target then target={title=M.text('Интерфейс'),items={}};result.items[#result.items+1]=target end
            target.items[#target.items+1]={title=M.text('Панель плеера'),value={'script-binding','player_ui/controls_menu'}}
        end
        if not has(result,'player_maintenance/menu') then
            table.insert(result.items,math.max(1,#result.items),{title=M.language()=='en' and 'Maintenance' or 'Обслуживание',value={'script-binding','player_maintenance/menu'}})
        end
        if not has(result,'component_updates/menu') then
            table.insert(result.items,math.max(1,#result.items),{title=M.text('Обновления компонентов'),value={'script-binding','component_updates/menu'}})
        end
        -- Keep the menu name aligned with the actual feature: it now covers
        -- intro, recap, credits and automatic-skip preferences.
        local function rename_skip(node)
            if type(node)~='table' then return end
            local binding=(type(node.value)=='table' and node.value[1]=='script-binding' and node.value[2])
                or (type(node.value)=='string' and node.value:match('^script%-binding%s+(.+)$'))
            if binding=='theintrodb/theintrodb-toggle-ui' or node.title==M.text('Пропуск заставок') then
                node.title=M.text('Заставки и титры')
                node.hint=node.hint or 'Ctrl+I'
            end
            for _,child in ipairs(node.items or {}) do rename_skip(child) end
        end
        for _,item in ipairs(result.items) do rename_skip(item) end
    end
    return result
end
function M.install_messages()
    if M.installed then return end
    M.installed=true
    local osd=mp.osd_message
    mp.osd_message=function(text,...) return osd(M.text(text),...) end
    local ok,input=pcall(require,'mp.input')
    if not ok then return end
    for _,name in ipairs({'get','select'}) do
        local fn=input[name]
        if fn then input[name]=function(args)
            local copy={};for k,v in pairs(args) do copy[k]=v end
            copy.prompt=M.text(copy.prompt)
            return fn(copy)
        end end
    end
    local log=input.log
    if log then input.log=function(text,...) return log(M.text(text),...) end end
end
return M
