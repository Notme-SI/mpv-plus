-- Keep portable installations portable; protected installations use the user's profile.
if package.loaded['mpv-build/user_settings'] then return package.loaded['mpv-build/user_settings'] end
local M={}
package.loaded['mpv-build/user_settings']=M
local root=mp.command_native({'expand-path','~~/'})
local utils=require 'mp.utils'
local base
function M.directory()
    if base then return base end
    local probe=root..'/.settings-write-test'
    local f=io.open(probe,'wb')
    if f then f:close();os.remove(probe);base=root;return base end
    base=(os.getenv('APPDATA') or os.getenv('HOME') or root)..'/mpv-plus/settings'
    return base
end
function M.path(name)
    local directory=M.directory()
    if directory==root then return root..'/'..name end
    local target=directory..'/'..name
    if not utils.file_info(target) then
        local parent=target:match('^(.*)[/\\]')
        local args=package.config:sub(1,1)=='\\' and {'powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',root..'/maintenance/Ensure-Directory.ps1','-Directory',parent} or {'mkdir','-p',parent}
        mp.command_native({name='subprocess',playback_only=false,capture_stdout=true,capture_stderr=true,args=args})
        local source=io.open(root..'/'..name,'rb')
        if source then
            local content=source:read('*a');source:close()
            local out=io.open(target,'wb');if out then out:write(content);out:close() end
        end
    end
    return target
end
-- Account identifiers stay in the Windows profile, outside distributed packages.
function M.account_path(name)
    local profile=os.getenv('APPDATA')
    return profile and profile..'/mpv-plus/'..name or M.path(name)
end
function M.options(values,name)
    require('mp.options').read_options(values,name)
    local file=io.open(M.path('script-opts/'..name..'.conf'),'rb')
    if not file then return end
    for line in file:lines() do
        local key,value=line:match('^%s*([%w_%-]+)%s*=%s*(.-)%s*$')
        if key and values[key]~=nil then
            if type(values[key])=='boolean' then values[key]=value=='yes' or value=='true'
            elseif type(values[key])=='number' then values[key]=tonumber(value) or values[key]
            else values[key]=value end
        end
    end
    file:close()
end
return M
