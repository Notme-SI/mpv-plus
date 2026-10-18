-- Local launcher; upstream code and build extensions are maintained separately.
dofile(mp.command_native({'expand-path','~~/extensions/media_source.lua'})).install()
dofile(mp.command_native({'expand-path','~~/extensions/torrserver.lua'})).install()
local settings=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua')
local server={scheme='http',host='127.0.0.1',port='8090',use_edl=true}
settings.options(server,'torrserver-loader')
local opts=mp.get_property_native('script-opts',{})
for key,value in pairs(server) do opts['torrserver-loader-'..key]=type(value)=='boolean' and (value and 'yes' or 'no') or tostring(value) end
mp.set_property_native('script-opts',opts)
dofile(mp.command_native({'expand-path','~~/vendor/torrserver_loader.lua'}))
