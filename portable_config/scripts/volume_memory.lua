-- Session volume is independent of a file's watch-later state and track choices.
local root=mp.command_native({'expand-path','~~/'})
local utils=require 'mp.utils'
local settings=dofile(root..'/extensions/user_settings.lua')
local path=settings.path('volume-state.json')
local function valid(value)
    return type(value)=='number' and value==value and value>=0 and value<math.huge
end
local file=io.open(path,'rb')
local saved
if file then saved=utils.parse_json(file:read('*a'));file:close() end
if type(saved)=='table' and valid(saved.volume) then
    mp.set_property_number('volume',math.min(saved.volume,mp.get_property_number('volume-max',100)))
end
local timer,dirty
local function save()
    if timer then timer:kill();timer=nil end
    if not dirty then return end
    local value=mp.get_property_number('volume')
    if not valid(value) then return end
    local out=io.open(path,'wb')
    if out then
        local written=out:write(utils.format_json({volume=value}))
        local closed=out:close()
        if written and closed then dirty=false;return end
    end
    mp.msg.warn('Could not save player volume')
end
mp.observe_property('volume','number',function(_,value)
    if not valid(value) then return end
    dirty=true
    if timer then timer:kill() end
    timer=mp.add_timeout(0.5,save)
end)
mp.register_event('shutdown',save)
