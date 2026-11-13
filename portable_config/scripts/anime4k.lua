-- Compatibility for existing personal bindings and script messages.
mp.add_key_binding(nil, 'menu', function() mp.commandv('script-binding', 'upscale/menu') end)
for _,name in ipairs({'mode', 'quality'}) do
    local message = name
    mp.register_script_message(message, function(value)
        mp.commandv('script-message-to', 'upscale', message, value)
    end)
end
