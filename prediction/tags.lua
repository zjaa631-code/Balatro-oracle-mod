-- Tag effects are deferred until shop creation. Forecasts before a skip are
-- explicit frozen-state branches; Orbital uses the already generated choice.
return function(O)
    local D,M=O.data,{cache={},computations=0}
    M.editions={tag_foil='e_foil',tag_holo='e_holo',tag_polychrome='e_polychrome',tag_negative='e_negative'}
    M.rarities={tag_uncommon=0.9,tag_rare=1}
    function M.supported(key) return key=='tag_orbital' or key=='tag_double' or key=='tag_voucher' or key=='tag_top_up' or O.tag_rewards.packs[key] or M.editions[key] or M.rarities[key] end
    local function check_tag(key)
        local proto=G.P_TAGS[key]
        local obj=SMODS.Tags and SMODS.Tags[key]
        assert(proto and not proto.mod and not (obj and (obj.mod or obj.apply or obj.set_ability)), 'oracle_tag_custom')
    end
    function M.capture(key,blind,ability,at_effect,config)
        assert(M.supported(key),'oracle_tag_unsupported')
        assert(O.controller.supported(),'oracle_prediction_unavailable')
        check_tag(key)
        local g=G.GAME
        local needs_pack=O.tag_rewards.packs[key]
        for _,tag in ipairs(g.tags or {}) do if not tag.triggered and O.tag_rewards.packs[tag.key] then needs_pack=true end end
        local s=needs_pack and O.pack_prediction.capture(G,SMODS) or O.shop_snapshot.capture(G,SMODS,true)
        assert(not s.unsupported and not s.shop.unsupported,'oracle_tag_custom')
        s.tag={key=key,blind=blind,ante=g.round_resets.ante,queue={},pending={},definitions={},visible_hands={},hands={}}
        local t=s.tag
        t.joker_count=#(G.jokers.cards or {}); t.joker_limit=(G.jokers.config or {}).card_limit or 5
        t.depth=O.config.prediction_depth or 3
        for k,p in pairs(G.P_TAGS) do if M.supported(k) then t.definitions[k]=D.copy(p.config or {}) end end
        for hand,h in pairs(g.hands) do
            local proto=SMODS.PokerHands[hand]
            -- Do not execute arbitrary visibility callbacks against live state.
            assert(not (proto and (proto.mod or type(proto.visible)=='function')),'oracle_tag_custom')
            t.hands[hand]={level=h.level,visible=h.visible,played=h.played}
            if proto and h.visible then t.visible_hands[#t.visible_hands+1]=hand end
        end
        for _,tag in ipairs(g.tags or {}) do
            if not tag.triggered and not (at_effect and key=='tag_orbital' and tag.key==key) then
                check_tag(tag.key)
                assert(M.supported(tag.key),'oracle_tag_queue')
                t.pending[#t.pending+1]={key=tag.key,id='stored:'..(#t.pending+1),
                    config=D.copy(tag.config or t.definitions[tag.key]),ability=D.copy(tag.ability or {})}
            end
        end
        if key=='tag_orbital' then
            t.hand=(ability or {}).orbital_hand or ((g.orbital_choices or {})[t.ante] or {})[blind]
            assert(t.hands[t.hand],'oracle_tag_not_generated')
            t.levels=(config or G.P_TAGS[key].config or {}).levels
            assert(type(t.levels)=='number' and type(t.hands[t.hand].level)=='number','oracle_tag_custom')
        end
        if not at_effect and blind=='Held' then
            assert(not (SMODS.OPENED_BOOSTER or (G.pack_cards and #G.pack_cards.cards>0)),'oracle_tag_after_pack')
            t.queue=D.copy(t.pending); t.expanded_tags={}; t.stored_double_count=0
            for _,v in ipairs(t.queue) do
                if v.key=='tag_double' then t.stored_double_count=t.stored_double_count+1 end
                if v.key==key then v.target=true; t.expanded_tags[#t.expanded_tags+1]=D.copy(v) end
            end
        elseif not at_effect then
            -- Skip Big -> defeat Boss -> next Ante shop. Skip Small -> Big shop.
            assert(blind=='Small' or blind=='Big','oracle_tag_not_generated')
            t.shop_ante=t.ante+(blind=='Big' and 1 or 0)
            local new_ability=D.copy(ability or {})
            if key=='tag_orbital' then new_ability.orbital_hand=t.hand end
            O.tag_pipeline.expand(s,{key=key,ability=new_ability,config=D.copy(config or t.definitions[key])})
        else
            t.queue=D.copy(t.pending)
        end
        return s
    end
    function M.orbital(s)
        local t=s.tag
        return {type='orbital',tag=t.key,status='observed',hand_key=t.hand,
            current_level=t.hands[t.hand].level,resulting_level=t.hands[t.hand].level+t.levels,levels_added=t.levels}
    end
    function M.create(s,rng,key)
        local rarity=M.rarities[key]; assert(rarity,'oracle_tag_unsupported')
        if key=='tag_rare' then
            local n=0
            for k in pairs(s.shop.owned) do
                if s.shop.centers[k] and s.shop.centers[k].rarity==3 then n=n+1 end
            end
            -- Native Rare Tag's possession count still applies with Showman.
            if #s.shop.rarity_pools[3]<=n then return nil end
        end
        local pool=O.shop_prediction.pool(s,'Joker',key=='tag_rare' and 3 or 2)
        return O.shop_prediction.create(s,rng,'Joker',key=='tag_rare' and 'rta' or 'uta',{area='shop',rarity=rarity}),pool
    end
    function M.modify(card,key)
        if card.set=='Joker' and not card.edition and M.editions[key] then
            card.edition=M.editions[key]; return true
        end
    end
    function M.batch(s,rng)
        local cards,deferred,results,pools,execution={},{},{},{},{}
        local function modify(card,slot)
            for i,t in ipairs(s.tag.queue) do
                if not t.done and M.modify(card,t.key) then
                    t.done=true; results[i]={card=card,slot=slot}; execution[#execution+1]=i; break
                end
            end
        end
        for slot=1,s.shop.limit do
            local card
            for i,t in ipairs(s.tag.queue) do
                if not t.done and M.rarities[t.key] then
                    t.done=true; card,pools[i]=M.create(s,rng,t.key)
                    results[i]={card=card,slot=slot,nope=not card}
                    execution[#execution+1]=i
                    if card then modify(card,slot); break end
                end
            end
            if not card then
                card=O.shop_prediction.card(s,rng)
                deferred[#deferred+1]={card=card,slot=slot}
            end
            cards[#cards+1]=card
        end
        -- Native regular shop cards enqueue their tag modification; forced
        -- rarity cards apply it immediately, before those queued callbacks.
        for _,v in ipairs(deferred) do modify(v.card,v.slot) end
        return {cards=cards,results=results,execution=execution},pools
    end
    function M.forecast(s)
        local r,details=O.ante_prediction.run(s,O.tag_pipeline.run)
        details.pool=r.joker_pools
        r.details=details
        if #r.expanded_tags==1 then
            local target
            for _,v in ipairs(r.effects) do if v.target then target=v; break end end
            if s.tag.key=='tag_orbital' and target then
                r.type='orbital'; r.hand_key=target.hand_key; r.current_level=target.current_level
                r.resulting_level=target.resulting_level; r.levels_added=target.levels_added
            elseif M.rarities[s.tag.key] or M.editions[s.tag.key] then
                r.type='joker'; r.card=target and target.card; r.slot=target and target.slot
                r.nope=target and target.nope; r.pending=not target or target.pending
            end
        end
        return r
    end
    function M.simulate_next_skip()
        local blind=G.GAME.blind_on_deck
        local key=(G.GAME.round_resets.blind_tags or {})[blind]
        return M.get(key,blind)
    end
    function M.simulate_tag_acquisition(state,new)
        local r,details=O.ante_prediction.run(state,function(s,rng)
            new=D.copy(new); new.config=new.config or D.copy(s.tag.definitions[new.key]); new.ability=new.ability or {}
            s.tag.key=new.key; s.tag.ante=s.game.round_resets.ante
            s.tag.shop_ante=new.shop_ante or s.game.round_resets.ante
            if new.key=='tag_orbital' and not new.ability.orbital_hand then
                new.ability.orbital_hand=rng:element(s.tag.visible_hands,'orbital')
            end
            O.tag_pipeline.expand(s,new)
            return O.tag_pipeline.run(s,rng)
        end)
        r.details=details; return r
    end
    function M.get(key,blind,ability,config)
        if not M.supported(key) then return nil end
        local ok,s=pcall(M.capture,key,blind,ability,false,config)
        if not ok then
            local reason=tostring(s):match('(oracle_[%w_]+)') or 'oracle_tag_custom'
            if M.last_reason~=reason then
                M.last_reason=reason
                if sendWarnMessage then sendWarnMessage('TAG '..key..': '..reason,'Oracle') end
            end
            return {status='unavailable',tag=key,reason=reason}
        end
        -- On hover/open only. A complete data signature catches RNG, level,
        -- pool and modifier changes even if another mod bypasses dirty hooks.
        local sig=D.encode(s)
        local entry=M.cache[key..tostring(blind)]
        if entry and entry.signature==sig then return entry.result,entry.snapshot end
        local success,result=pcall(M.forecast,s)
        if not success then
            if sendWarnMessage then sendWarnMessage('TAG '..key..': '..tostring(result),'Oracle') end
            return {status='unavailable',tag=key,reason='oracle_tag_custom'}
        end
        M.computations=M.computations+1
        M.cache[key..tostring(blind)]={signature=sig,result=result,snapshot=s}
        return result,s
    end
    return M
end
