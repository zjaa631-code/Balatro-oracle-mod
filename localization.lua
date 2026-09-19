return function(english)
    local fallback = english.misc.dictionary
    local M = {}
    function M.get(key)
        if type(localize) == 'function' then
            local ok, value = pcall(localize, key)
            if ok and type(value) == 'string' and value ~= key and value ~= 'ERROR' then return value end
        end
        return fallback[key] or key
    end
    function M.name(set, entry)
        if set=='Booster' and entry and entry.key then
            entry={key=entry.key:gsub('_%d+$',''),name=entry.name}
            set='Other'
        end
        if entry and entry.key and type(localize) == 'function' then
            local ok, value = pcall(localize, {type = 'name_text', set = set, key = entry.key})
            if ok and type(value) == 'string' and value ~= 'ERROR' and value ~= entry.key then return value end
        end
        return (entry and (entry.name or entry.key)) or M.get('oracle_unknown')
    end
    return M
end
