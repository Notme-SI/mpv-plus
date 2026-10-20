-- Pure matching and retry decisions shared by the local extensions and tests.
local M={}
local aliases={rus='ru',eng='en',jpn='ja',ukr='uk',deu='de',ger='de',fra='fr',fre='fr',zho='zh',chi='zh'}
function M.language(value)
    value=(value or ''):lower():match('^[a-z]+') or ''
    return aliases[value] or value
end
function M.subtitle(track,normalize)
    local title=track.title or ''
    local lower=normalize(title)
    return {title=title,match=lower,lang=M.language(track.lang),
        forced=track.forced==true or lower:find('forced',1,true)~=nil or lower:find('форс',1,true)~=nil or lower:find('надписи',1,true)~=nil,
        hearing=track['hearing-impaired']==true}
end
function M.find_subtitle(tracks,chosen,normalize)
    local exact,candidates={},{}
    for _,track in ipairs(tracks) do
        if track.type=='sub' then
            local candidate=M.subtitle(track,normalize)
            if candidate.lang==chosen.lang and candidate.forced==chosen.forced and candidate.hearing==chosen.hearing then
                candidates[#candidates+1]=track.id
                if candidate.match==chosen.match then exact[#exact+1]=track.id end
            end
        end
    end
    if #exact==1 then return exact[1] end
    if #exact==0 and #candidates==1 and chosen.lang~='' and chosen.lang~='und' then return candidates[1] end
end
function M.network(path)
    path=path or ''
    return path:match('^https?://')~=nil or (path:match('^edl://')~=nil and path:find('https?://')~=nil)
end
function M.retry(state,reason)
    if not state or not M.network(state.path) or state.cancelled or state.intentional_end then return false end
    -- Decoder errors at EOF must not replay the last two seconds forever.
    if state.loaded and state.duration and state.duration>0 and state.time and state.time>=state.duration-3 then return false end
    if reason=='error' then return true end
    return reason=='eof' and state.loaded and state.seekable and state.duration and state.duration>0
        and state.time>0 and state.time<state.duration-10 and not state.intentional_end
end
return M
