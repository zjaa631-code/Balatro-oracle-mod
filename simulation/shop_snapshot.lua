return function(O)
    local D, M = O.data, {}
    -- Native tags that persist between rounds but do not participate in shop
    -- card creation, edition modification or booster generation.
    local inert_types={tag_double='tag_add',tag_investment='eval',tag_juggle='round_start_bonus'}
    function M.inert_tag(g,smods,tag)
        local expected=inert_types[tag.key]
        local proto=(g.P_TAGS or {})[tag.key]
        local obj=(smods.Tags or {})[tag.key]
        return expected and proto and not proto.mod and not proto.apply and not proto.set_ability and
            proto.config and proto.config.type==expected and
            not (obj and (obj.mod or obj.apply or obj.set_ability)) and
            (not tag.config or tag.config.type==expected) or false
    end
    function M.card(card, detailed)
        local a, c = card.ability or {}, card.config or {}
        local edition = card.edition and card.edition.key
        if not edition then
            for _, e in ipairs({'foil','holo','polychrome','negative'}) do
                if card.edition and card.edition[e] then edition = 'e_'..e end
            end
        end
        return {key = c.center and c.center.key, set = c.center and c.center.set,
            front = c.card_key, edition = edition, eternal = a.eternal or false,
            perishable = a.perishable or false, rental = a.rental or false,
            to_do_poker_hand = a.to_do_poker_hand, seal=card.seal,
            ability=detailed and D.copy(a) or nil}
    end
    function M.capture(g, smods, tag_adapter)
        local s = O.snapshot.capture(g, smods)
        s.shop = {owned = {}, cards = {}, packs = {}, enhancements = {}, hands = {},
            visible_hands = {}, centers = {}, pools = {}, rarity_pools = {}, fronts = {}}
        local sh = s.shop
        sh.active = g.STATE == g.STATES.SHOP and g.shop_jokers ~= nil
        sh.ready = sh.active or g.STATE == g.STATES.ROUND_EVAL
        sh.transition = g.CONTROLLER and g.CONTROLLER.locks and g.CONTROLLER.locks.shop_reroll or false
        sh.limit = (g.GAME.shop or {}).joker_max or 2
        -- This is the authoritative limit, not #remaining goods or a count of
        -- voucher flags. Overstock and Overstock Plus each update it by +1.
        assert(type(sh.limit)=='number' and sh.limit>=0 and sh.limit%1==0,'oracle_shop_unsupported')
        for _, field in ipairs({'joker_rate','tarot_rate','planet_rate','playing_card_rate','spectral_rate',
            'edition_rate','common_mod','uncommon_mod','rare_mod','legendary_mod','first_shop_buffoon'}) do
            sh[field] = g.GAME[field]
        end
        sh.used_packs = D.copy((g.GAME.current_round or {}).used_packs or {})
        sh.reroll_count = ((g.GAME.round_scores or {}).times_rerolled or {}).amt
        sh.blind = (g.GAME.blind or {}).config and g.GAME.blind.config.blind and g.GAME.blind.config.blind.key
        for _, area in ipairs({g.jokers or {}, g.consumeables or {}}) do
            for _, c in ipairs(area.cards or {}) do
                sh.owned[c.config.center.key] = true
                if c.config.center.mod then sh.unsupported = true end
            end
        end
        for _, c in ipairs(g.shop_jokers and g.shop_jokers.cards or {}) do sh.cards[#sh.cards+1] = M.card(c,true) end
        for _, c in ipairs(g.shop_booster and g.shop_booster.cards or {}) do sh.packs[#sh.packs+1] = M.card(c) end
        -- Deferred native Investment/Juggle/Double effects are inert here.
        -- Keep tags which can change goods (and custom callbacks) behind the
        -- separate tag pipeline instead of disabling shops for held Doubles.
        if not tag_adapter then
            for _,tag in pairs(g.GAME.tags or {}) do
                if not M.inert_tag(g,smods,tag) then
                    sh.unsupported=true
                    sh.unsupported_tag=tag.key
                end
            end
        end
        if ((g.SETTINGS.tutorial_progress or {}).forced_shop) then sh.unsupported = true end
        for k, h in pairs(g.GAME.hands or {}) do
            sh.hands[k] = {played = h.played, visible = h.visible}
            if h.visible then sh.visible_hands[#sh.visible_hands+1] = k end
        end
        for _, c in ipairs(g.playing_cards or {}) do
            sh.enhancements[c.config.center.key] = true
            if c.config.center.mod then sh.unsupported = true end
        end
        for k, front in pairs(g.P_CARDS or {}) do
            sh.fronts[k] = {key = k, suit = front.suit, value = front.value}
            local rank,suit=(smods.Ranks or {})[front.value] or {},(smods.Suits or {})[front.suit] or {}
            if rank.in_pool or suit.in_pool or rank.mod or suit.mod then sh.unsupported=true end
        end
        local fields = {'key','name','set','effect','order','unlocked','rarity','hidden','no_pool_flag','yes_pool_flag',
            'enhancement_gate','eternal_compat','perishable_compat','config','weight','kind','in_shop','vanilla'}
        for k, c in pairs(g.P_CENTERS or {}) do
            if c.set == 'Joker' or c.consumeable or c.set == 'Enhanced' or c.set == 'Default'
                or c.set == 'Booster' or c.set == 'Edition' then
                local record = {}
                for _, f in ipairs(fields) do record[f] = D.copy(c[f]) end
                record.unsupported = c.mod ~= nil or type(c.in_pool) == 'function' or type(c.set_ability) == 'function'
                if c.set == 'Edition' and c.vanilla and ({e_foil=true,e_holo=true,e_polychrome=true,e_negative=true,e_base=true})[k] then
                    record.unsupported = false
                end
                sh.centers[k] = record
            end
        end
        for _, kind in ipairs({'Tarot','Planet','Spectral','Enhanced','Booster','Edition'}) do
            sh.pools[kind] = {}
            for _, c in ipairs(g.P_CENTER_POOLS[kind] or {}) do
                sh.pools[kind][#sh.pools[kind]+1] = c.key
                if sh.centers[c.key] and sh.centers[c.key].unsupported then sh.unsupported = true end
            end
        end
        for rarity, pool in pairs(g.P_JOKER_RARITY_POOLS or {}) do
            sh.rarity_pools[rarity] = {}
            for _, c in ipairs(pool) do
                sh.rarity_pools[rarity][#sh.rarity_pools[rarity]+1] = c.key
                if sh.centers[c.key].unsupported then sh.unsupported = true end
            end
        end
        sh.rarities = D.copy(smods.ObjectTypes.Joker.rarities)
        for _, r in ipairs(sh.rarities) do
            if not ({Common=true,Uncommon=true,Rare=true,Legendary=true})[r.key]
                or (smods.Rarities[r.key] or {}).mod then sh.unsupported = true end
        end
        for _, key in ipairs(smods.Sticker.obj_buffer) do
            if not ({eternal=true,perishable=true,rental=true,pinned=true})[key]
                or smods.Stickers[key].should_apply then sh.unsupported = true end
        end
        for _, key in ipairs(smods.ConsumableType.obj_buffer) do
            if not ({Tarot=true,Planet=true,Spectral=true})[key] then sh.unsupported = true end
        end
        return s
    end
    return M
end
