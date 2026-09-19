return function(Data, RNG)
    local M = {}
    local function pool(s, kind, append)
        local result, count = {}, 0
        local g = s.game
        for _, v in ipairs(s.pools[kind]) do
            local add = false
            if kind == 'Tag' then
                add = (not v.requires or (s.centers[v.requires] and s.centers[v.requires].discovered))
                    and (not v.min_ante or v.min_ante <= g.round_resets.ante)
            elseif not (g.used_jokers[v.key] and not s.showman) and (v.unlocked ~= false or v.rarity == 4) then
                add = not g.used_vouchers[v.key] and not s.shop_vouchers[v.key]
                for _, requirement in pairs(v.requires or {}) do if not g.used_vouchers[requirement] then add = false end end
                if v.hidden then add = false end
            end
            if v.no_pool_flag and g.pool_flags[v.no_pool_flag] then add = false end
            if v.yes_pool_flag and not g.pool_flags[v.yes_pool_flag] then add = false end
            if g.banned_keys[v.key] then add = false end
            result[#result + 1] = add and v.key or 'UNAVAILABLE'
            if add then count = count + 1 end
        end
        if count == 0 then result = {kind == 'Tag' and 'tag_handy' or 'v_blank'}; count = 1 end
        return result, kind..(append or '')..g.round_resets.ante, count
    end
    local function choose(rng, candidates, key, exclude)
        local picked = rng:element(candidates, key)
        local n = 1
        while picked == 'UNAVAILABLE' or (exclude and exclude[picked]) do
            n = n + 1
            assert(n <= 10000, 'oracle_resample_limit')
            picked = rng:element(candidates, key..'_resample'..n)
        end
        assert(picked, 'oracle_pool_unsupported')
        return picked
    end
    function M.tag(s, rng, append)
        if s.force_tag then return s.force_tag, {} end
        local p, key = pool(s, 'Tag', append)
        return choose(rng, p, key), p
    end
    function M.voucher(s, rng, from_tag)
        local p, key = pool(s, 'Voucher')
        if from_tag then key = 'Voucher_fromtag' end
        return choose(rng, p, key), p
    end
    function M.vouchers(s, rng, existing)
        local out = Data.copy(existing or {spawn = {}})
        local p, key, count = pool(s, 'Voucher')
        local limit = (s.game.starting_params.vouchers_in_shop or 1) + (s.game.modifiers.extra_vouchers or 0)
        for i = #out + 1, math.min(count, limit) do
            local selected = choose(rng, p, key, out.spawn)
            out[#out + 1] = selected; out.spawn[selected] = true
        end
        return out, p
    end
    local function counts(s, kind)
        return s.game.bosses_used[kind] or s.game.bosses_used
    end
    function M.blind(s, rng, kind, legacy)
        kind = kind or 'boss'
        local g, eligible = s.game, {}
        local ante = g.round_resets.ante
        if not legacy and s.native_blind_pools and s.native_blind_pools[kind]
            and s.native_blind_state == Data.encode({ante, g.round_resets.blind_choices,
                g.bosses_used, g.banned_keys}) then
            local p = s.native_blind_pools[kind]
            local selected = rng:element(p, kind)
            assert(selected and s.blinds[selected], 'oracle_pool_unsupported')
            local uses = (g.bosses_used[kind] or g.bosses_used)
            if s.blinds[selected][kind].allow_others then
                uses[selected] = (uses[selected] or 0) + 1
            else
                for _, t in pairs(s.blinds[selected].blind_types or {kind}) do
                    local c = (g.bosses_used[t] or g.bosses_used)
                    c[selected] = (c[selected] or 0) + 1
                end
            end
            return selected, p
        end
        if legacy then
            local forced = g.perscribed_bosses[ante]
            if forced then
                g.perscribed_bosses[ante] = nil
                counts(s, 'boss')[forced] = (counts(s, 'boss')[forced] or 0) + 1
                return forced, {forced}
            end
            if s.force_boss then return s.force_boss, {s.force_boss} end
        end
        local showdown = (legacy and ante >= 2 or not legacy and ante > 0) and ante % g.win_ante == 0
        for _, key in ipairs(s.blind_order) do
            local v, included = s.blinds[key], true
            local config = v[kind]
            if config then
                if not legacy then
                    for _, chosen in pairs(g.round_resets.blind_choices or {}) do
                        if chosen == key then included = false end
                    end
                end
                local minimum = legacy and config.min or (config.min or ante)
                if minimum > math.max(1, ante) then included = false end
                if not legacy and (config.max or ante) < ante then included = false end
                if kind == 'boss' and showdown ~= (config.showdown or false) then included = false end
                if included then eligible[key] = true end
            end
        end
        for key in pairs(g.banned_keys) do eligible[key] = nil end
        local uses, min_use = counts(s, kind), 100
        for key, value in pairs(uses) do
            if eligible[key] then eligible[key] = value; min_use = math.min(min_use, value) end
        end
        for key, value in pairs(eligible) do
            assert(type(value) == 'number', 'oracle_pool_unsupported')
            if value > min_use and (legacy or not s.blinds[key][kind].allow_duplicates) then eligible[key] = nil end
        end
        local selected, p
        if legacy then
            local _
            _, selected = rng:element(eligible, 'boss')
            p = eligible
        else
            p = {}
            for key in pairs(eligible) do p[#p + 1] = key end
            selected = rng:element(p, kind)
        end
        assert(selected, 'oracle_pool_unsupported')
        if legacy or s.blinds[selected][kind].allow_others then
            uses[selected] = (uses[selected] or 0) + 1
        else
            for _, t in pairs(s.blinds[selected].blind_types or {kind}) do
                local c = counts(s, t); c[selected] = (c[selected] or 0) + 1
            end
        end
        return selected, p
    end
    function M.run(snapshot, f)
        assert(not snapshot.unsupported, 'oracle_pool_unsupported')
        local s = Data.copy(snapshot)
        local rng = RNG.new(s.game.pseudorandom)
        -- Export can fail too; keep it inside the same cleanup boundary.
        local ok, result, p, state = pcall(function()
            local value, pool = f(s, rng)
            return value, pool, Data.copy(rng.state)
        end)
        local trace = rng.trace
        rng:close()
        if not ok then error(result) end
        return result, {trace = trace, pool = p, rng_after = state}
    end
    function M.rerolls(snapshot, depth)
        return M.run(snapshot, function(s, rng)
            local rows = {}
            for i = 1, depth do
                local key = M.blind(s, rng, 'boss', true)
                s.game.round_resets.blind_choices.Boss = key
                rows[i] = key
            end
            return rows
        end)
    end
    function M.forecast(snapshot, depth)
        assert(not (snapshot.game.round_resets.blind_states or {}).Boss
            or snapshot.game.round_resets.blind_states.Boss ~= 'Defeated', 'oracle_transition')
        return M.run(snapshot, function(s, rng)
            local g, out = s.game, {}
            local current = g.round_resets.ante
            out[1] = {ante = current, status = 'observed',
                boss = (g.round_resets.blind_choices or {}).Boss,
                tags = Data.copy(g.round_resets.blind_tags or {}),
                vouchers = Data.copy(g.current_round.voucher or {})}
            -- Conditional branch: no purchases, skips, boss rerolls, pool changes,
            -- or extra voucher/tag generation before the requested Ante.
            for key in pairs(s.shop_vouchers) do g.used_jokers[key] = nil end
            s.shop_vouchers = {}
            for offset = 1, depth do
                g.round_resets.ante = current + offset
                local row = {ante = current + offset, status = 'experimental'}
                row.vouchers = M.vouchers(s, rng)
                row.tags = {Small = M.tag(s, rng), Big = M.tag(s, rng)}
                g.round_resets.blind_choices = {}
                for _, kind in ipairs({'small', 'big', 'boss'}) do
                    local key = M.blind(s, rng, kind)
                    g.round_resets.blind_choices[kind:gsub('^%l', string.upper)] = key
                    if kind == 'boss' then row.boss = key end
                end
                out[#out + 1] = row
            end
            return out
        end)
    end
    return M
end
