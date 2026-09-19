return function(O)
    local M,D={},O.data
    -- Card.open rolls synchronously, but Card:explode blocks the Tarot
    -- creation until AFTER the non-blockable pack candidate events finish.
    function M.before_open(s,rng)
        local a=s.shop.opening
        if not a then return 0 end
        local pending=0
        local function trigger(index,depth)
            local c=a.jokers[index]
            if not c or c.debuff then return end
            if c.key=='j_blueprint' or c.key=='j_brainstorm' then
                local target=c.key=='j_blueprint' and index+1 or 1
                local other=a.jokers[target]
                if other and target~=index and other.compat and depth<=#a.jokers then trigger(target,depth+1) end
            elseif c.key=='j_hallucination' and a.count+a.buffer+pending<a.limit then
                assert(type(c.odds)=='number' and c.odds>0,'oracle_pack_unsupported')
                if rng:random('halu'..s.game.round_resets.ante)<a.probability/c.odds then pending=pending+1 end
            end
        end
        for i=1,#a.jokers do trigger(i,0) end
        a.pending=pending
        a.buffer=a.buffer+pending
        return pending
    end
    function M.after_open(s,rng)
        local a=s.shop.opening
        if not a then return {} end
        local pending=a.pending or 0
        local created={}
        for i=1,pending do
            created[i]=O.shop_prediction.create(s,rng,'Tarot','hal',{area='owned'})
            s.shop.owned[created[i].key]=true
        end
        a.count=a.count+pending
        if pending>0 then a.buffer=0 end
        a.pending=0
        return created
    end
    function M.settlement(s,rng,cards)
        local branch=D.copy(s); branch.game.pseudorandom=D.copy(rng.state)
        local generated,details=O.ante_prediction.run(branch,function(b,r)
            local extras=M.after_open(b,r)
            b.game.pseudorandom=D.copy(r.state)
            for _,card in ipairs(cards) do
                if card.key=='c_soul' then card.legendary=M.legendary(b) end
            end
            return extras
        end)
        return {cards=generated,rng_after=details.rng_after,trace=details.trace}
    end
    function M.seal(s,rng)
        local sh,ante=s.shop,s.game.round_resets.ante
        local pool,total={},0
        for _,v in ipairs(sh.seals) do
            if not s.game.banned_keys[v.key] and not s.game.used_jokers[v.key] and v.weight>0 then
                pool[#pool+1]=v; total=total+v.weight
            end
        end
        if total==0 then error('oracle_pack_unsupported') end
        if rng:random('stdseal'..ante)>1-0.2 then
            local roll,acc=rng:random('stdsealtype'..ante),0
            for _,v in ipairs(pool) do acc=acc+v.weight; if roll>1-acc/total then return v.key end end
        end
    end
    function M.candidate(s,rng,pack,index)
        local sh,g=s.shop,s.game
        local c=assert(sh.centers[pack.key],'oracle_pack_unsupported')
        local kind,append,args,edition,seal=nil,nil,{area='pack',soulable=true}
        if c.kind=='Arcana' then
            local spectral=g.used_vouchers.v_omen_globe and rng:random('omen_globe')>0.8
            kind=spectral and 'Spectral' or 'Tarot'; append=spectral and 'ar2' or 'ar1'
        elseif c.kind=='Celestial' then
            kind='Planet'; append='pl1'
            if index==1 and g.used_vouchers.v_telescope then
                local hand,tally=nil,0
                for _,h in ipairs(sh.handlist) do
                    if sh.hands[h].visible and sh.hands[h].played>tally then hand=h; tally=sh.hands[h].played end
                end
                for _,key in ipairs(sh.pools.Planet) do if sh.centers[key].config.hand_type==hand then args.forced=key end end
            end
        elseif c.kind=='Spectral' then kind='Spectral'; append='spe'
        elseif c.kind=='Buffoon' then kind='Joker'; append='buf'
        elseif c.kind=='Standard' then
            edition=O.shop_prediction.edition(s,rng,'standard_edition'..g.round_resets.ante,false,true,2)
            seal=M.seal(s,rng)
            kind=rng:random('stdset'..g.round_resets.ante)>0.6 and 'Enhanced' or 'Base'; append='sta'
        else error('oracle_pack_unsupported') end
        local out=O.shop_prediction.create(s,rng,kind,append,args)
        if c.kind=='Standard' then out.edition=edition; out.seal=seal end
        return out
    end
    function M.legendary(snapshot)
        local out=O.ante_prediction.run(snapshot,function(s,rng)
            return O.shop_prediction.create(s,rng,'Joker','sou',{area='owned',legendary=true})
        end)
        return out.key
    end
    function M.forecast(snapshot,pack)
        assert(not snapshot.shop.unsupported and not snapshot.shop.pack_unsupported,'oracle_pack_unsupported')
        local settlement
        local out,details=O.ante_prediction.run(snapshot,function(s,rng)
            local center=s.shop.centers[pack.key]
            assert(center and not center.unsupported,'oracle_pack_unsupported')
            local size=math.max(1,(pack.size or center.config.extra)+(s.game.modifiers.booster_size_mod or 0))
            M.before_open(s,rng)
            local cards={}
            for i=1,size do cards[i]=M.candidate(s,rng,pack,i) end
            settlement=M.settlement(s,rng,cards)
            return cards
        end)
        details.opening_cards=settlement.cards
        details.settled_rng=settlement.rng_after
        details.settlement_trace=settlement.trace
        return out,details
    end
    function M.capture(g,smods)
        -- Pack candidates do not call Tag:apply_to_run's shop/tag_add paths.
        -- Anaglyph's held Double must not inherit the shop's blanket tag gate.
        -- Only audited vanilla tags bypass it; custom behavior stays closed.
        local s=O.shop_snapshot.capture(g,smods,true)
        local sh=s.shop
        local pack_inert_tags={tag_uncommon=true,tag_rare=true,
            tag_foil=true,tag_holo=true,tag_polychrome=true,tag_negative=true,
            tag_voucher=true,tag_orbital=true}
        for _,tag in pairs(g.GAME.tags or {}) do
            local proto=(g.P_TAGS or {})[tag.key]
            local obj=(smods.Tags or {})[tag.key]
            if not (O.shop_snapshot.inert_tag(g,smods,tag) or pack_inert_tags[tag.key] or (O.tag_rewards and (O.tag_rewards.packs[tag.key] or tag.key=='tag_top_up'))) or not proto or proto.mod or
                (obj and (obj.mod or obj.apply or obj.set_ability)) then
                sh.pack_unsupported=true
                sh.pack_reason='oracle_pack_tag_unsupported'
            end
        end
        sh.handlist=D.copy(g.handlist or {})
        sh.seals={}
        for _,seal in ipairs(g.P_CENTER_POOLS.Seal or {}) do
            sh.seals[#sh.seals+1]={key=seal.key,weight=seal.weight or 10}
            if not ({Red=true,Blue=true,Gold=true,Purple=true})[seal.key] or seal.in_pool or seal.mod then sh.pack_unsupported=true end
        end
        sh.custom_souls=next(smods.Consumable.legendaries or {})~=nil
        if sh.custom_souls then sh.pack_unsupported=true; sh.pack_reason='oracle_pack_custom_soul' end
        sh.opening={jokers={},count=#(g.consumeables and g.consumeables.cards or {}),
            limit=g.consumeables and g.consumeables.config and g.consumeables.config.card_limit or 0,
            buffer=g.GAME.consumeable_buffer or 0,probability=(g.GAME.probabilities or {}).normal or 1}
        for _,card in ipairs(g.jokers and g.jokers.cards or {}) do
            local center=card.config.center
            local item={key=center.key,debuff=card.debuff or false,compat=center.blueprint_compat or false}
            if center.key=='j_hallucination' then
                item.odds=card.ability and card.ability.extra
                if type(item.odds)~='number' or item.odds<=0 then sh.pack_unsupported=true end
            end
            sh.opening.jokers[#sh.opening.jokers+1]=item
        end
        -- OPENED_BOOSTER retains the last opened object after native pack
        -- cleanup. It is metadata, not a live-open flag. Opening changes STATE
        -- before creating the panel; closing can leave the panel briefly alive.
        sh.pack_open=g.booster_pack~=nil
        for _,state in ipairs({'SMODS_BOOSTER_OPENED','TAROT_PACK','PLANET_PACK','SPECTRAL_PACK','STANDARD_PACK','BUFFOON_PACK'}) do
            if g.STATES[state] and g.STATE==g.STATES[state] then sh.pack_open=true end
        end
        sh.opened_pack=sh.pack_open and smods.OPENED_BOOSTER and smods.OPENED_BOOSTER.config.center.key or nil
        sh.opened_cards={}
        if sh.pack_open then
            for _,c in ipairs(g.pack_cards and g.pack_cards.cards or {}) do sh.opened_cards[#sh.opened_cards+1]=O.shop_snapshot.card(c) end
        end
        return s
    end
    return M
end
