return function(Data)
    local M = {}
    local proto_fields = {'key', 'name', 'set', 'unlocked', 'discovered', 'rarity', 'requires',
        'min_ante', 'no_pool_flag', 'yes_pool_flag', 'hidden', 'boss', 'small', 'big', 'blind_types'}
    local function proto(value)
        local out = {}
        for _, field in ipairs(proto_fields) do out[field] = Data.copy(value[field]) end
        -- Never invoke custom eligibility/weight callbacks from a prediction.
        if type(value.in_pool) == 'function' or value.enhancement_gate then
            out.unsupported = true
        end
        return out
    end
    function M.capture(g, smods)
        assert(g and g.GAME and g.GAME.pseudorandom and g.GAME.pseudorandom.seed, 'oracle_no_run')
        local game = g.GAME
        local s = {game = {}, pools = {}, blinds = {}, blind_order = {}, centers = {}, shop_vouchers = {},
            force_boss = g.FORCE_BOSS, force_tag = g.FORCE_TAG}
        for _, field in ipairs({'pseudorandom', 'round_resets', 'used_jokers', 'used_vouchers',
            'pool_flags', 'banned_keys', 'perscribed_bosses', 'starting_params', 'modifiers'}) do
            -- round_resets.blind is a prototype with methods in modded games.
            if field ~= 'round_resets' then s.game[field] = Data.copy(game[field] or {}) end
        end
        local rr = game.round_resets or {}
        s.game.round_resets = {}
        for _, field in ipairs({'ante', 'blind_ante', 'blind_states', 'blind_choices', 'blind_tags', 'blind_order'}) do
            s.game.round_resets[field] = Data.copy(rr[field])
        end
        s.game.current_round = {voucher = Data.copy((game.current_round or {}).voucher)}
        s.game.win_ante = game.win_ante or 8
        s.game.stake, s.game.round = game.stake, game.round
        s.game.bosses_used = Data.copy(game.bosses_used or {})
        s.showman = smods and (smods.create_card_allow_duplicates or smods.poll_object_allow_duplicates) or false
        for _, area in ipairs({g.jokers or {}, g.consumeables or {}}) do
            for _, card in ipairs(area.cards or {}) do
                if card.config and card.config.center and card.config.center.key == 'j_ring_master' and not card.debuff then s.showman = true end
            end
        end
        for _, card in ipairs(g.shop_vouchers and g.shop_vouchers.cards or {}) do
            s.shop_vouchers[card.config.center.key] = true
        end
        for _, kind in ipairs({'Tag', 'Voucher'}) do
            s.pools[kind] = {}
            for i, v in ipairs(g.P_CENTER_POOLS and g.P_CENTER_POOLS[kind] or {}) do
                s.pools[kind][i] = proto(v)
            end
            assert(#s.pools[kind] > 0, 'oracle_pool_unsupported')
        end
        -- Preserve the real iteration/insertion order. SMODS new-Blind selection
        -- materializes an UNSORTED hash pool into an array before sampling.
        for key, value in pairs(g.P_BLINDS or {}) do
            s.blind_order[#s.blind_order + 1] = key
            s.blinds[key] = proto(value)
        end
        -- SMODS.create_blind_pool builds a fresh hash table and returns its
        -- unsorted iteration order. Rebuilding that table from a deep copy can
        -- yield a different order, even with identical eligibility and RNG.
        -- The vanilla function is read-only when no Blind has an in_pool
        -- callback, so capture its exact array before simulating a live call.
        if smods and type(smods.create_blind_pool) == 'function'
            and not (smods.optional_features or {}).object_weights then
            local safe = true
            for _, v in pairs(s.blinds) do if v.unsupported then safe = false; break end end
            if safe then
                s.native_blind_pools = {}
                for _, kind in ipairs({'small', 'big', 'boss'}) do
                    s.native_blind_pools[kind] = Data.copy(smods.create_blind_pool(kind))
                end
                s.native_blind_state = Data.encode({s.game.round_resets.ante,
                    s.game.round_resets.blind_choices, s.game.bosses_used, s.game.banned_keys})
            end
        end
        for key, value in pairs(g.P_CENTERS or {}) do
            s.centers[key] = {discovered = value.discovered}
        end
        s.unsupported = smods and smods.optional_features and smods.optional_features.object_weights
        for _, kind in ipairs({'Tag', 'Voucher'}) do
            local object_type = smods and smods.ObjectTypes and smods.ObjectTypes[kind]
            if object_type and (object_type.rarities or object_type.default) then s.unsupported = true end
            for _, v in ipairs(s.pools[kind]) do if v.unsupported then s.unsupported = true end end
        end
        for _, v in pairs(s.blinds) do if v.unsupported then s.unsupported = true end end
        return s
    end
    return M
end
