return function(O)
    local M = {revision = 0, cache = nil, forecast_count = 0}
    function M.invalidate()
        M.revision = M.revision + 1
        M.cache = nil
        M.shop_cache = nil
        if O.tag_prediction then O.tag_prediction.cache={} end
    end
    function M.supported()
        return O.config.enabled and not O.prediction_fault and not (O.undo and O.undo.restoring) and O.status and #O.status.issues == 0
    end
    function M.snapshot()
        assert(M.supported(), 'oracle_prediction_unavailable')
        return O.snapshot.capture(G, SMODS)
    end
    function M.forecast()
        local ok, s = pcall(M.snapshot)
        if not ok then return nil, tostring(s) end
        local depth = O.config.prediction_depth or 3
        if depth ~= 3 and depth ~= 5 and depth ~= 10 and depth ~= 20 then depth = 3 end
        local signature = O.data.encode(s)..':'..depth
        if M.cache and M.cache.signature == signature then return M.cache.rows end
        local success, result = pcall(O.ante_prediction.forecast, s, depth)
        if not success then return nil, tostring(result) end
        M.forecast_count = M.forecast_count + 1
        M.cache = {signature = signature, rows = result}
        return result
    end
    local function report_failure(error)
        if sendWarnMessage then sendWarnMessage(tostring(error), 'Oracle') end
    end
    function M.shop_forecast()
        if not M.supported() then return nil, 'oracle_prediction_unavailable' end
        local ok,s=pcall(O.shop_snapshot.capture,G,SMODS)
        if not ok then return nil,tostring(s) end
        local depth=O.config.show_future_shops==false and 0 or (O.config.prediction_depth or 3)
        local sig=O.data.encode(s)..':'..depth
        if depth==0 and s.shop.active then
            return {{cards=s.shop.cards,packs=s.shop.packs,status='observed',reroll=0}},nil,s
        elseif depth==0 then return nil,'oracle_feature_hidden',s end
        if M.shop_cache and M.shop_cache.signature==sig then return M.shop_cache.rows,nil,s end
        local success,rows=pcall(O.shop_prediction.forecast,s,depth)
        if not success then return nil,tostring(rows),s end
        M.shop_cache={signature=sig,rows=rows}
        return rows,nil,s
    end
    local function wrap_shop(key, predict, normalize)
        local original=_G[key]
        if type(original)~='function' then return end
        _G[key]=function(...)
            local args={n=select('#',...),...}
            local before,expected,details
            if O.config.validate_predictions and M.supported() and not G.SETTINGS.paused then
                local ok=pcall(function()
                    before=O.shop_snapshot.capture(G,SMODS)
                    assert(not before.shop.unsupported, 'oracle_shop_unsupported')
                    expected,details=O.ante_prediction.run(before,function(s,rng) return predict(s,rng,unpack(args,1,args.n)) end)
                end)
                if not ok then before=nil; O.validator.counts.SKIP=O.validator.counts.SKIP+1 end
            end
            local results
            local function collect(...) results={n=select('#',...),...} end
            collect(original(...))
            M.invalidate()
            if before then
                local ok,err=pcall(function()
                    local actual=normalize(results[1])
                    if expected.variant_unknown and (actual.key=='p_buffoon_normal_1' or actual.key=='p_buffoon_normal_2') then
                        expected.key=actual.key; expected.variant_unknown=nil
                    end
                    O.validator.record(key,before,{value=expected,rng=details.rng_after},
                        {value=actual,rng=O.data.copy(G.GAME.pseudorandom)},details)
                end)
                if not ok then O.prediction_fault=true; report_failure(err) end
            end
            return unpack(results,1,results.n)
        end
    end
    local function wrap_prediction(owner, key, predict)
        if type(owner[key]) ~= 'function' then return end
        local original = owner[key]
        owner[key] = function(...)
            local args = {n = select('#', ...), ...}
            local before, expected, details
            -- This wrapper only predicts an actual forthcoming game call.
            -- The original is invoked exactly once for gameplay, never for preview.
            if O.config.validate_predictions and M.supported() and not (G.SETTINGS or {}).paused then
                local ok, err = pcall(function()
                    before = M.snapshot()
                    expected, details = O.ante_prediction.run(before, function(s, rng)
                        return predict(s, rng, unpack(args, 1, args.n))
                    end)
                end)
                if not ok then
                    before = nil; O.validator.counts.SKIP = O.validator.counts.SKIP + 1
                    -- Unsupported custom pools are a skip, not a fabricated match.
                end
            end
            local results = {n = 0}
            local function collect(...)
                results.n = select('#', ...)
                for i = 1, results.n do results[i] = select(i, ...) end
            end
            collect(original(...))
            M.invalidate()
            if before then
                local ok, err = pcall(function()
                    local actual_rng = O.data.copy(G.GAME.pseudorandom)
                    local result = O.validator.record(key, before,
                        {value = expected, rng = details.rng_after},
                        {value = O.data.copy(results[1]), rng = actual_rng}, details)
                end)
                if not ok then O.prediction_fault = true; report_failure(err) end
            end
            return unpack(results, 1, results.n)
        end
    end
    function M.install()
        wrap_shop('create_card_for_shop',O.shop_prediction.card,O.shop_snapshot.card)
        wrap_shop('get_pack',O.shop_prediction.pack,function(c) return {key=c.key,set='Booster'} end)
        wrap_prediction(_G, 'get_next_tag_key', O.ante_prediction.tag)
        wrap_prediction(_G, 'get_next_voucher_key', O.ante_prediction.voucher)
        wrap_prediction(_G, 'get_new_boss', function(s, rng) return O.ante_prediction.blind(s, rng, 'boss', true) end)
        wrap_prediction(SMODS, 'get_new_blind', O.ante_prediction.blind)
        wrap_prediction(SMODS, 'get_next_vouchers', O.ante_prediction.vouchers)
        -- Invalidate only; forecasts are performed on demand while the menu is open.
        local function wrap_dirty(owner, key)
            if not owner or type(owner[key]) ~= 'function' then return end
            local original = owner[key]
            owner[key] = function(...)
                local first=select(1,...)
                if type(first)~='table' or not first.oracle_preview then M.invalidate() end
                return original(...)
            end
        end
        for _, key in ipairs({'play_cards_from_highlighted', 'discard_cards_from_highlighted',
            'draw_from_deck_to_hand', 'reroll_shop', 'buy_from_shop', 'sell_card', 'use_card',
            'select_blind', 'cash_out', 'toggle_shop'}) do wrap_dirty(G.FUNCS, key) end
        for _, key in ipairs({'set_ability', 'set_base', 'set_edition', 'set_seal', 'add_to_deck',
            'remove_from_deck', 'remove', 'open', 'use_consumeable', 'redeem', 'start_dissolve', 'shatter'}) do wrap_dirty(Card, key) end
        for _, key in ipairs({'emplace', 'remove_card', 'shuffle', 'change_size', 'sort'}) do wrap_dirty(CardArea, key) end
        for _,key in ipairs({'change_shop_size','copy_card','create_playing_card'}) do wrap_dirty(_G,key) end
        wrap_dirty(_G,'add_tag')
        for _,key in ipairs({'apply_to_run','remove','remove_from_game','load'}) do wrap_dirty(Tag,key) end
        wrap_dirty(SMODS,'change_base')
        wrap_dirty(_G,'level_up_hand')
        wrap_dirty(SMODS,'upgrade_poker_hands')
        if Game then wrap_dirty(Game, 'start_run') end
    end
    return M
end
