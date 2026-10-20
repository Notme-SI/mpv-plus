-- Measure the rendered font, not a character-count estimate. Cache bounded
-- strings so a changing buffer counter never accumulates measurements forever.
local M={}
function M.escape(value)
    return tostring(value or ''):gsub('\\','\\e'):gsub('{','\\{'):gsub('}','\\}'):gsub('[\r\n]',' ')
end
function M.new()
    local overlay
    local cache,count={},0
    local function width(value,size,font,bold)
        value=tostring(value or '')
        if value=='' then return 0 end
        local w,h=mp.get_osd_size()
        if w<=0 or h<=0 then w,h=1280,720 end
        local key=table.concat({w,h,size,font or 'Segoe UI',bold and 1 or 0,value},'|')
        if cache[key] then return cache[key] end
        if not overlay then
            overlay=mp.create_osd_overlay('ass-events')
            overlay.compute_bounds=true;overlay.hidden=true
        end
        overlay.res_x=w;overlay.res_y=h
        overlay.data=string.format('{\\rDefault\\an7\\pos(10,10)\\fn%s\\fs%.3f\\b%d\\fscx100\\fscy100\\bord0\\shad0\\q2}%s',font or 'Segoe UI',size,bold and 1 or 0,M.escape(value))
        local ok,bounds=pcall(overlay.update,overlay)
        local result=ok and type(bounds)=='table' and tonumber(bounds.x1)
        if result and result>10 then result=result-10+2 else
            local _,n=value:gsub('[^\128-\191]','');result=n*size*.50
        end
        if count>=256 then cache={};count=0 end
        count=count+1;cache[key]=result
        return result
    end
    local function fit(value,limit,size,font,bold)
        value=tostring(value or ''):gsub('[\r\n]',' ')
        if width(value,size,font,bold)<=limit then return value end
        local chars={};for c in value:gmatch('[%z\1-\127\194-\244][\128-\191]*')do chars[#chars+1]=c end
        local low,high=0,#chars
        while low<high do
            local mid=math.ceil((low+high)/2)
            if width(table.concat(chars,'',1,mid)..'…',size,font,bold)<=limit then low=mid else high=mid-1 end
        end
        return table.concat(chars,'',1,low)..'…'
    end
    local function middle(value,limit,size,font,bold)
        if width(value,size,font,bold)<=limit then return value end
        local chars={};for c in value:gmatch('[%z\1-\127\194-\244][\128-\191]*')do chars[#chars+1]=c end
        local low,high=0,#chars
        local function shorten(n)
            local left=math.floor(n/2)
            return table.concat(chars,'',1,left)..'…'..table.concat(chars,'',#chars-(n-left)+1)
        end
        while low<high do
            local mid=math.ceil((low+high)/2)
            if width(shorten(mid),size,font,bold)<=limit then low=mid else high=mid-1 end
        end
        return shorten(low)
    end
    return {width=width,fit=fit,middle=middle}
end
return M
