-- Ordered native tag acquisition and settlement, operating only on data copies.
return function(O)
    local D,M=O.data,{}
    function M.expand(s,new)
        local t=s.tag
        t.queue=D.copy(t.pending or {}); t.expanded_tags={}; t.consumed_doubles={}; t.stored_double_count=0
        for i,v in ipairs(t.queue) do v.id='stored:'..i; v.target=false end
        for _,v in ipairs(t.queue) do if v.key=='tag_double' and not v.done then t.stored_double_count=t.stored_double_count+1 end end
        if not new then return end
        local copies={}
        -- add_tag visits existing tags BEFORE appending the acquired object.
        -- Double marks itself triggered now; its callback constructs a NEW Tag.
        if new.key~='tag_double' then
            for _,v in ipairs(t.queue) do
                if v.key=='tag_double' and not v.done then
                    v.done=true; t.consumed_doubles[#t.consumed_doubles+1]=v.id
                    copies[#copies+1]={id='copy:'..(#copies+1),key=new.key,target=true,copied_from=v.id,
                        config=D.copy(t.definitions[new.key]),ability={orbital_hand=new.ability and new.ability.orbital_hand}}
                end
            end
        end
        new=D.copy(new); new.id='new'; new.target=true
        t.queue[#t.queue+1]=new; t.expanded_tags[#t.expanded_tags+1]=D.copy(new)
        for _,v in ipairs(copies) do t.queue[#t.queue+1]=v; t.expanded_tags[#t.expanded_tags+1]=D.copy(v) end
    end
    local function pending(queue)
        local out={}; for _,v in ipairs(queue) do if not v.done then out[#out+1]=D.copy(v) end end
        return out
    end
    function M.immediate(s,rng)
        local out={}
        for i,t in ipairs(s.tag.queue) do
            if not t.done and t.key=='tag_orbital' then
                local hand=(t.ability or {}).orbital_hand
                local h=s.tag.hands[hand]; local levels=(t.config or {}).levels
                assert(h and type(h.level)=='number' and type(levels)=='number','oracle_tag_not_generated')
                out[#out+1]={instance=i,id=t.id,tag=t.key,type='orbital',stage='immediate',target=t.target,
                    hand_key=hand,current_level=h.level,resulting_level=h.level+levels,levels_added=levels}
                h.level=h.level+levels; t.done=true
            elseif not t.done and t.key=='tag_top_up' then
                out[#out+1]={instance=i,id=t.id,tag=t.key,type='cards',stage='immediate',target=t.target,
                    cards=O.tag_rewards.topup(s,rng,t)}
                t.done=true
            end
        end
        return out
    end
    function M.voucher(s,rng)
        local key,pool=O.ante_prediction.voucher(s,rng,true)
        -- Tag callback emplaces the card before the next callback selects its pool.
        -- Creation is not redemption: no upgrade prerequisite becomes purchased.
        s.shop_vouchers[key]=true; s.game.used_jokers[key]=true
        return {key=key,set='Voucher'},pool
    end
    function M.normal_vouchers(s,rng)
        local normal=s.game.current_round.voucher
        if type(normal)~='table' then normal={spawn={}} end
        normal.spawn=normal.spawn or {}
        normal=O.ante_prediction.vouchers(s,rng,normal)
        s.game.current_round.voucher=normal
        local out={}
        for _,key in ipairs(normal) do
            if normal.spawn[key] then
                out[#out+1]={key=key,set='Voucher'}; s.shop_vouchers[key]=true; s.game.used_jokers[key]=true
            end
        end
        return out
    end
    function M.run(s,rng)
        local immediate=M.immediate(s,rng)
        s.game.pseudorandom=D.copy(rng.state)
        local acquisition=D.copy(s)
        acquisition.tag.pending=pending(acquisition.tag.queue)
        local result={type='chain',tag=s.tag.key,status='experimental',skip_tag=s.tag.key,
            stored_double_count=s.tag.stored_double_count or 0,expanded_tags=D.copy(s.tag.expanded_tags or {}),
            consumed_doubles=D.copy(s.tag.consumed_doubles or {}),immediate_effects=immediate,
            deferred_effects={},future_shop_effects={},effects=D.copy(immediate),acquisition_state=acquisition,
            shop_ante=s.tag.shop_ante,normal_vouchers={},additional_vouchers={}}
        result.rerolls={}
        if O.tag_rewards.has_pack(s) then
            O.tag_rewards.resolve_pack(s,rng,result)
            s.game.pseudorandom=D.copy(rng.state); s.tag.pending=pending(s.tag.queue)
            result.pending_tags=D.copy(s.tag.pending); result.resulting_shadow_state=s
            return result
        end
        local has_deferred=false
        for i,t in ipairs(s.tag.queue) do
            if not t.done and t.key~='tag_double' then
                has_deferred=true
                result.deferred_effects[#result.deferred_effects+1]={instance=i,id=t.id,tag=t.key,stage='shop',target=t.target}
            end
        end
        if has_deferred then
            for _,card in ipairs(s.shop.cards or {}) do if not s.shop.owned[card.key] then s.game.used_jokers[card.key]=nil end end
            s.shop.cards={}
            for key in pairs(s.shop_vouchers) do s.game.used_jokers[key]=nil end
            s.shop_vouchers={}
            s.game.round_resets.ante=s.tag.shop_ante or s.game.round_resets.ante
            if s.game.round_resets.ante~=s.tag.ante then
                -- Native end_round generates normal Ante vouchers before the shop.
                s.game.current_round.voucher=O.ante_prediction.vouchers(s,rng)
                s.shop.used_packs={}
            end
            local batch,pools=O.tag_prediction.batch(s,rng)
            result.shop_cards=batch.cards; result.joker_pools=pools
            s.shop.cards=D.copy(batch.cards)
            result.normal_vouchers=M.normal_vouchers(s,rng)
            result.shop_packs={}
            for i=1,(s.game.starting_params.boosters_in_shop or 2)+(s.game.modifiers.extra_boosters or 0) do
                local key=s.shop.used_packs[i]
                if not key then
                    local pack=O.shop_prediction.pack(s,rng,'shop_pack')
                    key=pack.key; s.shop.used_packs[i]=key
                    if pack.variant_unknown then result.unknown_pack_cover=true end
                end
                if key~='USED' then
                    result.shop_packs[#result.shop_packs+1]={key=key,set='Booster'}
                    s.game.used_jokers[key]=true
                end
            end
            for i,t in ipairs(s.tag.queue) do
                if not t.done and t.key=='tag_voucher' then
                    local card,pool=M.voucher(s,rng); t.done=true
                    batch.results[i]={card=card,pool=pool}
                    batch.execution[#batch.execution+1]=i
                    result.additional_vouchers[#result.additional_vouchers+1]=D.copy(card)
                end
            end
            local function collect(batch,pools,reroll)
                for _,i in ipairs(batch.execution) do
                    local t=s.tag.queue[i]; local v=batch.results[i]
                    local effect={instance=i,id=t.id,tag=t.key,type=t.key=='tag_voucher' and 'voucher' or 'joker',
                        stage='shop',reroll=reroll,target=t.target,card=v.card,slot=v.slot,nope=v.nope,pool=v.pool or pools[i]}
                    result.future_shop_effects[#result.future_shop_effects+1]=effect; result.effects[#result.effects+1]=effect
                end
            end
            collect(batch,pools,0)
            result.rerolls={}
            for reroll=1,(s.tag.depth or 0) do
                local unresolved=false
                for _,t in ipairs(s.tag.queue) do
                    if not t.done and (O.tag_prediction.rarities[t.key] or O.tag_prediction.editions[t.key]) then unresolved=true end
                end
                if not unresolved then break end
                -- Explicit no-purchase continuation. Creation does not grant ownership.
                for _,card in ipairs(s.shop.cards) do if not s.shop.owned[card.key] then s.game.used_jokers[card.key]=nil end end
                local next_batch,next_pools=O.tag_prediction.batch(s,rng)
                s.shop.cards=D.copy(next_batch.cards)
                result.rerolls[#result.rerolls+1]={reroll=reroll,cards=D.copy(next_batch.cards)}
                collect(next_batch,next_pools,reroll)
            end
            for i,t in ipairs(s.tag.queue) do
                if not t.done and t.key~='tag_double' then
                    result.effects[#result.effects+1]={instance=i,id=t.id,tag=t.key,type='pending',stage='later',target=t.target,pending=true}
                end
            end
        end
        s.game.pseudorandom=D.copy(rng.state)
        s.tag.pending=pending(s.tag.queue)
        result.pending_tags=D.copy(s.tag.pending)
        result.resulting_shadow_state=s
        if not has_deferred and s.tag.key~='tag_top_up' then result.status='observed' end
        return result
    end
    return M
end
