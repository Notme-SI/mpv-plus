-- Embedded chapter boundaries belong to the actual release and outrank online times.
local M={}
local function finite(value)
    value=tonumber(value)
    return value and value==value and math.abs(value)<math.huge and value or nil
end
-- Unknown starts/ends must never turn into an invented opening at 00:00.
function M.validate(kind,segment,duration)
    -- Previews remain ordinary video, regardless of cached API data or preferences.
    if kind~='intro' and kind~='recap' and kind~='credits' then return end
    local start=finite(segment.start_ms)
    local finish=finite(segment.end_ms)
    duration=finite(duration) or 0
    if not start or start<0 then return end
    start=start/1000
    if (not finish or finish==0) and kind=='credits' and duration>0 then
        finish=duration*1000
    end
    if not finish then return end
    finish=finish/1000
    if duration>0 and finish>duration+1 then return end
    if duration>0 then finish=math.min(finish,duration) end
    local length=finish-start
    if length<=0 or length>(kind=='credits' and 900 or 300) then return end
    if kind=='credits' and length<10 then return end
    if kind=='credits' and segment.source~='chapters' and duration>0 and start<duration/2 then return end
    return {kind=kind,start=start,['end']=finish,source=segment.source or 'online'}
end
function M.flatten(data,duration)
    local result={}
    for _,kind in ipairs({'intro','recap','credits'}) do
        for _,segment in ipairs(type(data[kind])=='table' and data[kind] or {}) do
            if type(segment)=='table' then
                local valid=M.validate(kind,segment,duration)
                if valid and kind=='credits' then
                    -- An open-ended or overlapping credits interval must never
                    -- absorb a separately marked preview after the credits.
                    for _,preview in ipairs(type(data.preview)=='table' and data.preview or {})do
                        local start=type(preview)=='table' and finite(preview.start_ms)
                        local finish=type(preview)=='table' and finite(preview.end_ms)
                        if start and start>=0 and start/1000<valid['end']
                            and (not finish or finish==0 or finish/1000>valid.start)then
                            valid['end']=math.min(valid['end'],start/1000)
                        end
                    end
                end
                if valid and valid['end']>valid.start then result[#result+1]=valid end
            end
        end
    end
    table.sort(result,function(a,b) return a.start==b.start and a['end']<b['end'] or a.start<b.start end)
    local out={}
    for _,segment in ipairs(result) do
        local duplicate=false
        for _,other in ipairs(result) do
            if other~=segment and other.kind~=segment.kind
                and math.min(segment['end'],other['end'])-math.max(segment.start,other.start)>1 then
                -- A chapter wins over online data. Equally authoritative,
                -- contradictory labels are unsafe: discard both, never guess.
                if segment.source~='chapters' or other.source=='chapters' then duplicate=true;break end
            end
        end
        for _,prior in ipairs(out) do
            if segment.kind==prior.kind and math.abs(segment.start-prior.start)<1
                and math.abs(segment['end']-prior['end'])<1 then duplicate=true;break end
        end
        if not duplicate then out[#out+1]=segment end
    end
    return out
end
function M.aniskip(results,duration)
    local best={}
    local kinds={op='intro',ed='credits',recap='recap'}
    if not duration or duration<=0 then return best end
    for _,item in ipairs(results or {}) do
        local interval=item.interval or {}
        local length=finite(item.episodeLength)
        local start,finish=finite(interval.startTime),finite(interval.endTime)
        local kind=kinds[item.skipType]
        -- A different cut can have the same episode but shifted openings. Do not
        -- accept the previous 20-second tolerance or an unknown episode length.
        if kind and length and math.abs(length-duration)<=3 and start and finish
            and M.validate(kind,{start_ms=start*1000,end_ms=finish*1000},duration) then
            local delta=math.abs(length-duration)
            local prior=best[item.skipType]
            if not prior or delta<prior.delta-0.25 then
                best[item.skipType]={delta=delta,segment=item}
            elseif math.abs(delta-prior.delta)<=0.25 and
                (math.abs(start-prior.segment.interval.startTime)>2 or math.abs(finish-prior.segment.interval.endTime)>2) then
                prior.ambiguous=true
            end
        end
    end
    for kind,item in pairs(best) do if item.ambiguous then best[kind]=nil end end
    return best
end
local labels={
    intro={'op','opening','opening theme','openingtheme','opening song','intro','заставка','опенинг'},
    credits={'ed','ending','ending theme','endingtheme','ending song','outro','credits','титры','эндинг'},
    recap={'recap','previously','previously on','рекап','ранее в сериале'},
    preview={'preview','next episode','next episode preview','nextepisodepreview','next notice','nextnotice','анонс','превью'},
}
function M.kind(title,normalize)
    title=(title or ''):gsub('^%s*%d+[%s%.%-:]+','')
    title=normalize(title:match('^(.-)%s*[%(%[%:/%-]') or title)
    for kind,names in pairs(labels) do
        for _,name in ipairs(names) do
            local prefix=normalize(name)
            if title==prefix or title:match('^'..prefix..'%d+$') then return kind end
        end
    end
end
function M.from_chapters(chapters,duration,normalize)
    local out={}
    for i,chapter in ipairs(chapters or {}) do
        local kind=M.kind(chapter.title,normalize)
        local start=tonumber(chapter.time)
        local next_chapter=chapters[i+1]
        local finish=next_chapter and tonumber(next_chapter.time)
        if not finish and (kind=='credits' or kind=='preview') then finish=duration end
        -- "Intro" also labels studio logos and cold opens. Short chapters with
        -- this generic name are ambiguous; explicit OP/Opening labels remain valid.
        local generic=normalize(chapter.title or '')=='intro'
        local ambiguous=kind=='intro' and generic and start and finish and finish-start<30
        if kind and not ambiguous and start and finish and M.validate(kind,{start_ms=start*1000,end_ms=finish*1000,source='chapters'},duration) then
            out[kind]=out[kind] or {}
            out[kind][#out[kind]+1]={start_ms=start*1000,end_ms=finish*1000,source='chapters'}
        end
    end
    return out
end
function M.combine(remote,anime,native)
    local combined={}
    -- Do not mix different release/season databases into an identified AniSkip result.
    for k,v in pairs(next(anime or {}) and anime or remote or {}) do combined[k]=v end
    for k,v in pairs(native or {}) do combined[k]=v end
    return combined
end
-- Combine only neighbouring, explicitly recognised pairs. A real scene gap
-- must remain playable; allow at most one second of timestamp rounding.
function M.action(segments,segment,enabled,prefs)
    local action={kind=segment.kind,start=segment.start,['end']=segment['end'],
        kinds={segment.kind},members={segment}}
    local automatic=enabled and prefs[segment.kind] or false
    action.auto=automatic
    for i,current in ipairs(segments)do
        if current==segment then
            local next_segment=segments[i+1]
            if not next_segment or not segment['end'] then break end
            local a,b=segment.kind,next_segment.kind
            local opening=a=='recap' and b=='intro' or a=='intro' and b=='recap'
            local gap=next_segment.start-segment['end']
            local next_auto=enabled and prefs[b] or false
            if gap>=-1 and gap<=1 and next_segment['end'] and next_segment['end']>segment['end']
                and (automatic and next_auto and opening
                    or not automatic and not next_auto and opening) then
                action['end']=next_segment['end'];action.kinds[#action.kinds+1]=b
                action.members[#action.members+1]=next_segment
            end
            break
        end
    end
    return action
end
function M.caption(segment,automatic,language)
    local en=language=='en'
    local names=en and {intro='Intro',recap='Recap',credits='Credits',preview='Preview'}
        or {intro=automatic and 'Заставки' or 'Заставку',recap='Ранее в сериале',credits='Титры',preview='Анонс'}
    local labels={}
    for _,kind in ipairs(segment.kinds or {segment.kind})do labels[#labels+1]=names[kind] or kind end
    return (automatic and (en and 'Auto-skip: ' or 'Автопропуск: ') or (en and 'Skip: ' or 'Пропустить: '))
        ..table.concat(labels,en and ' and ' or ' и ')
end
return M
