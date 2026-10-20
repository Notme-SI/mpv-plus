-- Local bootstrap using thumbfast's public frontend integration property.
local ok, ffi = pcall(require, 'ffi')
if ok and ffi.os == 'Windows' and not mp.get_property_native('user-data/frontend/process-path') then
    ffi.cdef[[unsigned long GetModuleFileNameW(void*, wchar_t*, unsigned long);
        int WideCharToMultiByte(unsigned int,unsigned long,const wchar_t*,int,char*,int,const char*,int*);]]
    local kernel = ffi.load('kernel32')
    local buffer = ffi.new('wchar_t[32768]')
    local n = kernel.GetModuleFileNameW(nil, buffer, 32768)
    if n > 0 and n < 32768 then
        local count = kernel.WideCharToMultiByte(65001,0,buffer,n,nil,0,nil,nil)
        if count > 0 then
            local out = ffi.new('char[?]',count)
            kernel.WideCharToMultiByte(65001,0,buffer,n,out,count,nil,nil)
            local frontend = mp.get_property_native('user-data/frontend',{})
            frontend['process-path'] = ffi.string(out,count)
            assert(mp.set_property_native('user-data/frontend',frontend))
        end
    end
end

-- Cancel our thumbnail subprocess before upstream closes its IPC pipe. A child
-- stuck on a network read must not keep the player executable or pipe open.
local native_async=mp.command_native_async
local children,closing={},false
mp.command_native_async=function(args,callback)
    if type(args)~='table' or args.name~='subprocess' or args.detach then return native_async(args,callback) end
    local id,completed
    id=native_async(args,function(...)
        completed=true;if id then children[id]=nil end
        if not closing and callback then callback(...) end
    end)
    if not completed then children[id]=true end
    return id
end
mp.register_event('shutdown',function()
    closing=true
    for id in pairs(children)do mp.abort_async_command(id)end
    children={}
end)
