-- Compact display labels only; seek commands and signed offsets are unchanged.
local M={}
function M.clock(value)
    value=tostring(value or ''):gsub('^[%+%-]','')
    local h,m,s=value:match('^(%d+):(%d%d):(%d%d[.,]?%d*)$')
    if h then
        h=tonumber(h)
        return h>0 and (h..':'..m..':'..s) or (tonumber(m)..':'..s)
    end
    m,s=value:match('^(%d+):(%d%d[.,]?%d*)$')
    return m and tonumber(m)..':'..s or value
end
return M
