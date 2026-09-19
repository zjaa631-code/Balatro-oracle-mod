-- Data-only copying: no metatables, methods, userdata or references to live UI.
local M = {}
function M.copy(value, seen)
    if type(value) ~= 'table' then
        local t = type(value)
        if t == 'nil' or t == 'boolean' or t == 'string' or t == 'number' then return value end
        error('Unsupported simulation value: '..t)
    end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for k, v in next, value do out[M.copy(k, seen)] = M.copy(v, seen) end
    return out
end
function M.encode(value, seen)
    local t = type(value)
    if t == 'nil' or t == 'boolean' then return tostring(value) end
    if t == 'number' then return string.format('%.17g', value) end
    if t == 'string' then return string.format('%q', value) end
    assert(t == 'table', 'Non-data value in record')
    seen = seen or {}
    assert(not seen[value], 'Cycle in record')
    seen[value] = true
    local keys, out = {}, {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) < type(b)
    end)
    for _, k in ipairs(keys) do out[#out + 1] = '['..M.encode(k)..']='..M.encode(value[k], seen) end
    seen[value] = nil
    return '{'..table.concat(out, ',')..'}'
end
return M
