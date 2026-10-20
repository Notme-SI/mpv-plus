-- Load ICO frames at the window DPI instead of scaling a 256px taskbar icon.
local ok,ffi=pcall(require,'ffi')
if not ok or ffi.os~='Windows' then return end
ffi.cdef[[
int MultiByteToWideChar(unsigned int,unsigned long,const char*,int,wchar_t*,int);
void* LoadImageW(void*,const wchar_t*,unsigned int,int,int,unsigned int);
int EnumWindows(int (__stdcall *)(void*,intptr_t),intptr_t);
unsigned long GetWindowThreadProcessId(void*,unsigned long*);
unsigned int GetDpiForWindow(void*);
int GetSystemMetricsForDpi(int,unsigned int);
int GetSystemMetrics(int);
int IsWindowVisible(void*);
intptr_t SendMessageTimeoutW(void*,unsigned int,uintptr_t,intptr_t,unsigned int,unsigned int,uintptr_t*);
int DestroyIcon(void*);
]]
local user=ffi.load('user32')
local kernel=ffi.load('kernel32')
local path=mp.command_native({'expand-path','~~/assets/mpv-monochrome.ico'})
local n=kernel.MultiByteToWideChar(65001,0,path,#path,nil,0)
local wide=ffi.new('wchar_t[?]',n+1)
kernel.MultiByteToWideChar(65001,0,path,#path,wide,n)
local icons={}
local function metric(code,dpi)
    local success,value=pcall(function() return user.GetSystemMetricsForDpi(code,dpi) end)
    return success and value or user.GetSystemMetrics(code)
end
local function icon(width,height)
    local key=width..'x'..height
    if not icons[key] then icons[key]=user.LoadImageW(nil,wide,1,width,height,0x10) end
    return icons[key]
end
local pid=require('mp.utils').getpid()
local applied={}
local function message(window,id,wparam,lparam)
    local result=ffi.new('uintptr_t[1]')
    -- Window teardown must not leave a script waiting on the GUI thread.
    if user.SendMessageTimeoutW(window,id,wparam,lparam,0x22,100,result)==0 then return end
    return ffi.cast('intptr_t',result[0])
end
local callback=ffi.cast('int (__stdcall *)(void*,intptr_t)',function(window)
    local process=ffi.new('unsigned long[1]')
    user.GetWindowThreadProcessId(window,process)
    if tonumber(process[0])==pid and user.IsWindowVisible(window)~=0 then
        local success,dpi=pcall(function() return tonumber(user.GetDpiForWindow(window)) end)
        if not success or dpi==0 then dpi=96 end
        local small=icon(metric(49,dpi),metric(50,dpi))
        local large=icon(metric(11,dpi),metric(12,dpi))
        if small==nil or large==nil or applied[tostring(window)]==dpi then return 1 end
        message(window,0x80,0,ffi.cast('intptr_t',small))
        message(window,0x80,1,ffi.cast('intptr_t',large))
        local correct=message(window,0x7F,0,0)==ffi.cast('intptr_t',small)
            and message(window,0x7F,1,0)==ffi.cast('intptr_t',large)
        if correct then applied[tostring(window)]=dpi end
        mp.set_property_native('user-data/window-icon-applied',correct)
    end
    return 1
end)
local timer=mp.add_periodic_timer(1,function() user.EnumWindows(callback,0) end)
mp.register_event('shutdown',function()
    timer:kill();callback:free()
    for _,handle in pairs(icons) do if handle~=nil then user.DestroyIcon(handle) end end
end)
