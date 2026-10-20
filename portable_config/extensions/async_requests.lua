-- Own metadata subprocesses inside the calling script's Lua client. Do not let
-- callbacks start fallback requests after the player has begun shutting down.
local M={}
function M.install()
    local native=mp.command_native_async
    if not native then return {call=mp.command_native,wrap=function(fn)return fn end} end
    local requests,closing={},false
    mp.command_native_async=function(args,callback)
        if type(args)~='table' or args.name~='subprocess' or args.detach then return native(args,callback)end
        local id,completed
        id=native(args,function(...)
            completed=true;if id then requests[id]=nil end
            if not closing and callback then callback(...)end
        end)
        if not completed then requests[id]=true end
        return id
    end
    mp.register_event('shutdown',function()
        closing=true
        local ids={};for id in pairs(requests)do ids[#ids+1]=id end
        requests={}
        for _,id in ipairs(ids)do mp.abort_async_command(id)end
    end)
    local function resume(task,...)
        if closing then return end
        local ok,err=coroutine.resume(task,...)
        if not ok then error(err)end
    end
    return {wrap=function(fn)
        return function(...)
            if closing then return end
            resume(coroutine.create(fn),...)
        end
    end,call=function(args)
        local task=coroutine.running()
        if not task then return mp.command_native(args)end
        local completed,result=false,nil
        local waiting=false
        mp.command_native_async(args,function(ok,value)
            result=ok and value or {status=-1};completed=true
            if waiting then resume(task,result)end
        end)
        if completed then return result end
        waiting=true;return coroutine.yield()
    end}
end
return M
