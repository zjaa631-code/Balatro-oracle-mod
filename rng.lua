return function(Data, Backend)
    local M = {}
    function M.hash(str)
        local num = 1
        for i = #str, 1, -1 do
            num = ((1.1239285023 / num) * string.byte(str, i) * math.pi + math.pi * i) % 1
        end
        return num
    end
    function M.new(state)
        local copied_state = Data.copy(state)
        local backend = Backend.new()
        local self = {state = copied_state, trace = {}}
        function self:seed(key)
            assert(type(key) == 'string' and key ~= 'seed', 'Unkeyed RNG is unsupported')
            local before = self.state[key]
            local value = before or M.hash(key..(self.state.seed or ''))
            value = math.abs(tonumber(string.format('%.13f', (2.134453429141 + value * 1.72431234) % 1)))
            self.state[key] = value
            self.trace[#self.trace + 1] = {key = key, before = before, after = value}
            return (value + (self.state.hashed_seed or 0)) / 2
        end
        function self:random(key, lo, hi)
            return backend.draw(type(key) == 'string' and self:seed(key) or key, lo, hi)
        end
        function self:element(pool, key)
            local entries = {}
            for k, v in pairs(pool) do entries[#entries + 1] = {k = k, v = v} end
            if entries[1] and type(entries[1].v) == 'table' and entries[1].v.sort_id then
                table.sort(entries, function(a, b) return a.v.sort_id < b.v.sort_id end)
            else
                table.sort(entries, function(a, b) return a.k < b.k end)
            end
            -- Match evaluation of pseudoseed before pseudorandom_element,
            -- including the SMODS empty-pool branch.
            local seed = type(key) == 'string' and self:seed(key) or key
            if #entries == 0 then return nil, nil end
            local selected = entries[backend.draw(seed, 1, #entries)]
            return selected.v, selected.k
        end
        function self:close() backend.close() end
        function self:shuffle(list,key)
            local seed=type(key)=='string' and self:seed(key) or key
            if list[1] and list[1].sort_id then table.sort(list,function(a,b) return (a.sort_id or 1)<(b.sort_id or 2) end) end
            local swaps=backend.shuffle(seed,#list)
            for i=#list,2,-1 do local j=swaps[i]; list[i],list[j]=list[j],list[i] end
        end
        return self
    end
    return M
end
