return function(O)
    local D, M = O.data, {}
    local rarity_ids = {Common=1,Uncommon=2,Rare=3,Legendary=4}
    local function choose(rng, p, key)
        local value, i = rng:element(p, key), 1
        while value == 'UNAVAILABLE' do
            i = i+1; assert(i <= 10000, 'oracle_resample_limit')
            value = rng:element(p, key..'_resample'..i)
        end
        assert(value, 'oracle_pool_unsupported')
        return value
    end
    function M.pool(s, kind, rarity)
        local sh, g = s.shop, s.game
        local source = kind == 'Joker' and sh.rarity_pools[rarity] or sh.pools[kind]
        assert(source, 'oracle_pool_unsupported')
        local p, count = {}, 0
        for _, key in ipairs(source) do
            local c = sh.centers[key]
            local add = kind == 'Enhanced' or (kind == 'Edition' and c.in_shop)
            if kind ~= 'Enhanced' and kind ~= 'Edition' then
                add = not (g.used_jokers[key] and not s.showman) and (c.unlocked ~= false or c.rarity == 4)
                if c.set == 'Planet' and c.config.softlock then add = add and sh.hands[c.config.hand_type].played > 0 end
                if c.enhancement_gate then add = add and sh.enhancements[c.enhancement_gate] end
                if c.hidden or c.name == 'The Soul' or c.name == 'Black Hole' then add = false end
            end
            if c.no_pool_flag and g.pool_flags[c.no_pool_flag] then add = false end
            if c.yes_pool_flag and not g.pool_flags[c.yes_pool_flag] then add = false end
            if g.banned_keys[key] then add = false end
            p[#p+1] = add and key or 'UNAVAILABLE'; if add then count=count+1 end
        end
        if count == 0 then p = {({Tarot='c_strength',Planet='c_pluto',Spectral='c_incantation',Edition='e_foil'})[kind] or 'j_joker'} end
        return p
    end
    function M.edition(s, rng, key, guaranteed, no_negative, modifier)
        local sh = s.shop
        local poll, options, total = rng:random(key), {}, 0
        for _, e in ipairs(M.pool(s, 'Edition')) do
            if e ~= 'UNAVAILABLE' then
                if sh.centers[e].vanilla then table.insert(options,1,e) else options[#options+1]=e end
                total = total + sh.centers[e].weight
            end
        end
        if not guaranteed then total = total + total/4*96 end
        local cumulative = 0
        for _, e in ipairs(options) do
            local w, rate = sh.centers[e].weight, sh.edition_rate or 1
            if not guaranteed then
                if e == 'e_polychrome' then w=(rate-1)*sh.centers.e_negative.weight+rate*w
                elseif e ~= 'e_negative' then w=rate*w end
            end
            cumulative = cumulative + w*(modifier or 1)
            if poll > 1-cumulative/total and not (e == 'e_negative' and no_negative) then return e end
        end
    end
    function M.card(s, rng)
        assert(not s.shop.unsupported, 'oracle_shop_unsupported')
        local sh, g, ante = s.shop, s.game, s.game.round_resets.ante
        local total = (sh.joker_rate or 0)+(sh.tarot_rate or 0)+(sh.planet_rate or 0)+(sh.playing_card_rate or 0)+(sh.spectral_rate or 0)
        local poll = rng:random('cdt'..ante)*total
        local playing = g.used_vouchers.v_illusion and rng:random('illusion') > 0.6 and 'Enhanced' or 'Base'
        local rates = {{'Joker',sh.joker_rate},{'Tarot',sh.tarot_rate},{'Planet',sh.planet_rate},
            {playing,sh.playing_card_rate},{'Spectral',sh.spectral_rate}}
        local kind, cumulative = nil, 0
        for _, entry in ipairs(rates) do
            if poll > cumulative and poll <= cumulative+(entry[2] or 0) then kind=entry[1]; break end
            cumulative=cumulative+(entry[2] or 0)
        end
        assert(kind, 'oracle_pool_unsupported')
        local out=M.create(s,rng,kind,'sho',{area='shop'})
        if (kind=='Base' or kind=='Enhanced') and g.used_vouchers.v_illusion and rng:random('illusion') > 0.8 then
            out.edition=M.edition(s,rng,'illusion',true,true)
        end
        return out
    end
    function M.create(s,rng,kind,append,args)
        args=args or {}; append=append or ''
        local sh,g,ante=s.shop,s.game,s.game.round_resets.ante
        local forced=args.forced
        if not forced and args.soulable and not g.banned_keys.c_soul then
            assert(not sh.custom_souls, 'oracle_pack_unsupported')
            rng:random('soul_smods_'..kind..ante)
            if (kind=='Tarot' or kind=='Spectral' or kind=='Tarot_Planet') and not (g.used_jokers.c_soul and not s.showman) then
                if rng:random('soul_'..kind..ante)>0.997 then forced='c_soul' end
            end
            if (kind=='Planet' or kind=='Spectral') and not (g.used_jokers.c_black_hole and not s.showman) then
                if rng:random('soul_'..kind..ante)>0.997 then forced='c_black_hole' end
            end
        end
        if kind=='Base' then forced='c_base' end
        local rarity
        if kind=='Joker' and args.legendary then rarity=4
        elseif kind=='Joker' and args.rarity then
            -- Native get_current_pool maps the supplied numeric rarity; it does
            -- not poll rarity<ante><append> on Uncommon/Rare Tag creation.
            rarity=args.rarity > 0.95 and 3 or args.rarity > 0.7 and 2 or 1
        elseif kind == 'Joker' and not forced then
            local roll, sum = rng:random('rarity'..ante..append), 0
            for _, r in ipairs(sh.rarities) do sum=sum+r.weight*(sh[r.key:lower()..'_mod'] or 1) end
            local acc = 0
            for _, r in ipairs(sh.rarities) do
                acc=acc+r.weight*(sh[r.key:lower()..'_mod'] or 1)/sum
                if roll < acc then rarity=rarity_ids[r.key]; break end
            end
        end
        local key=forced and not g.banned_keys[forced] and forced or choose(rng,M.pool(s,kind,rarity),
            kind..(rarity or '')..(args.legendary and '' or append..ante))
        local center, out = sh.centers[key], {key=key,eternal=false,perishable=false,rental=false}
        out.set = center.set
        if forced and not g.banned_keys[forced] and center.set~='Default' then kind=center.set end
        if kind == 'Base' or kind == 'Enhanced' then
            local _, front = rng:element(sh.fronts, 'front'..append..ante); out.front=front
        end
        if center.name == 'To Do List' then out.to_do_poker_hand = rng:element(sh.visible_hands, 'to_do') end
        g.used_jokers[key] = true
        if kind == 'Joker' then
            local mod = g.modifiers
            out.eternal = mod.all_eternal and center.eternal_compat or false
            if args.area=='shop' or args.area=='pack' then
                local ep = rng:random((args.area=='pack' and 'packetper' or 'etperpoll')..ante)
                if mod.enable_eternals_in_shop and ep > 0.7 then out.eternal=center.eternal_compat or false
                elseif mod.enable_perishables_in_shop and ep > 0.4 and ep <= 0.7 and not out.eternal then
                    out.perishable = center.perishable_compat or false
                end
                if mod.enable_rentals_in_shop then out.rental=rng:random((args.area=='pack' and 'packssjr' or 'ssjr')..ante) > 0.7 end
            end
            out.edition = M.edition(s,rng,'edi'..append..ante)
        end
        return out
    end
    function M.pack(s, rng, key, kind)
        local sh, g = s.shop, s.game
        if not sh.first_shop_buffoon and not g.banned_keys.p_buffoon_normal_1 then
            sh.first_shop_buffoon=true
            -- Cover 1/2 is unkeyed global math.random; identical type/size only.
            return {key='p_buffoon_normal_1',set='Booster',variant_unknown=true}
        end
        local pool, total = {}, 0
        for _, k in ipairs(sh.pools.Booster) do
            local c=sh.centers[k]
            if not g.banned_keys[k] and (not kind or c.kind==kind) then
                pool[#pool+1]=k; total=total+(c.weight or 1)
            end
        end
        local roll, acc=rng:random((key or 'pack_generic')..g.round_resets.ante)*total,0
        for _, k in ipairs(pool) do
            local w=sh.centers[k].weight or 1; acc=acc+w
            if acc>=roll and acc-w<=roll then return {key=k,set='Booster'} end
        end
        return {key='p_buffoon_normal_1',set='Booster'}
    end
    function M.forecast(snapshot, depth)
        assert(snapshot.shop.ready, 'oracle_shop_wait')
        assert(not snapshot.shop.transition, 'oracle_transition')
        return O.ante_prediction.run(snapshot,function(s,rng)
            assert(not s.shop.unsupported, 'oracle_shop_unsupported')
            local sh, rows=s.shop,{}
            local function clear(cards)
                for _, c in ipairs(cards) do if not sh.owned[c.key] then s.game.used_jokers[c.key]=nil end end
            end
            local current
            if sh.active then current=D.copy(sh.cards)
            else
                clear(sh.cards); current={}
                for i=1,sh.limit do current[i]=M.card(s,rng) end
            end
            local packs=D.copy(sh.packs)
            if not sh.active then
                packs={}
                for i=1,(s.game.starting_params.boosters_in_shop or 2)+(s.game.modifiers.extra_boosters or 0) do
                    local k=sh.used_packs[i]
                    if not k then packs[#packs+1]=M.pack(s,rng,'shop_pack')
                    elseif k~='USED' then packs[#packs+1]={key=k,set='Booster'} end
                end
            end
            rows[1]={cards=current,packs=packs,status=sh.active and 'observed' or 'experimental',reroll=0}
            for i=1,depth do
                clear(current); current={}
                for j=1,sh.limit do current[j]=M.card(s,rng) end
                rows[#rows+1]={cards=current,packs=packs,status='experimental',reroll=i}
            end
            return rows
        end)
    end
    return M
end
