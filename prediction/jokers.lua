-- Conditional next native trigger, never a full scoring-hand forecast.
return function(O)
    local M,D={},O.data
    M.probabilities={j_space={'space'},j_gros_michel={'gros_michel','odds'},j_cavendish={'cavendish','odds'},
        j_bloodstone={'bloodstone','odds'},j_business={'business'},j_reserved_parking={'parking','odds'},
        j_8_ball={'8ball'},j_hallucination={'halu'},m_glass={'glass'}}
    M.resets={j_idol='idol_card',j_mail='mail_card',j_ancient='ancient_card',j_castle='castle_card'}
    M.generators={j_riff_raff={'Joker','rif'},j_cartomancer={'Tarot','car'},j_sixth_sense={'Spectral','sixth'},
        j_vagabond={'Tarot','vag'},j_superposition={'Tarot','sup'},j_seance={'Spectral','sea'},
        j_8_ball={'Tarot','8ba'},j_hallucination={'Tarot','hal'}}
    M.choices={j_invisible=true,j_perkeo=true,j_madness=true,j_todo_list=true,j_marble=true,j_certificate=true}
    function M.supported(key)
        return M.probabilities[key] or M.resets[key] or M.generators[key] or M.choices[key] or key=='m_lucky' or key=='j_misprint'
    end
    -- Native end_round increments Ante BEFORE resetting these targets. In a
    -- shop the old Blind object still exists: use completion states instead.
    function M.next_reset_ante(g)
        local rr=g.GAME.round_resets
        local states=rr.blind_states or {}
        local function complete(key) return states[key]=='Defeated' or states[key]=='Skipped' end
        local boss=not complete('Boss') and (states.Boss=='Current' or states.Boss=='Select'
            or (complete('Small') and complete('Big')))
        return rr.ante+(boss and 1 or 0)
    end
    function M.base(g)
        return {game={pseudorandom=D.copy(g.GAME.pseudorandom),round=g.GAME.round,
            round_resets={ante=g.GAME.round_resets.ante}},trigger={probability=(g.GAME.probabilities or {}).normal or 1}}
    end
    function M.roll(s,rng,key,numerator,denominator,no_mod)
        return rng:random(key)<numerator*(no_mod and 1 or s.trigger.probability)/denominator
    end
    function M.capture(g,sm,card)
        local s=O.shop_snapshot.capture(g,sm,true)
        local a={probability=(g.GAME.probabilities or {}).normal or 1,source=O.consumables.card(card),
            jokers={},inventory={},playing={},round=D.copy(g.GAME.current_round),
            joker_limit=g.jokers.config.card_limit,consume_limit=g.consumeables.config.card_limit,
            joker_buffer=g.GAME.joker_buffer or 0,consume_buffer=g.GAME.consumeable_buffer or 0,seals={}}
        for _,v in ipairs(g.jokers.cards) do local c=O.consumables.card(v); c.sliced=v.getting_sliced or false; a.jokers[#a.jokers+1]=c end
        for _,v in ipairs(g.consumeables.cards) do a.inventory[#a.inventory+1]=O.consumables.card(v) end
        for _,v in ipairs(g.playing_cards or {}) do
            assert(not v.config.center.mod,'oracle_action_unsupported')
            a.playing[#a.playing+1]=O.consumables.card(v)
        end
        for _,v in ipairs(g.P_CENTER_POOLS.Seal or {}) do
            assert(not v.mod and not v.in_pool and not v.get_weight,'oracle_action_unsupported')
            a.seals[#a.seals+1]={key=v.key,weight=v.weight or 10}
        end
        s.trigger=a
        a.source.sliced=card.getting_sliced or false
        return s
    end
    function M.reset(s,rng,key)
        local a=s.trigger; local field=assert(M.resets[key]); local out=D.copy(a.round[field] or {})
        local pool={}
        if key=='j_ancient' then
            for _,suit in ipairs({'Spades','Hearts','Clubs','Diamonds'}) do if suit~=out.suit then pool[#pool+1]=suit end end
            out.suit=rng:element(pool,'anc'..s.game.round_resets.ante)
        else
            for _,c in ipairs(a.playing) do if c.ability.effect~='Stone Card' and c.key~='m_stone' then pool[#pool+1]=c end end
            if key~='j_castle' then out.rank='Ace' end
            if key~='j_mail' then out.suit='Spades' end
            if #pool>0 then
                local c=rng:element(pool,({j_idol='idol',j_mail='mail',j_castle='cas'})[key]..s.game.round_resets.ante)
                if key~='j_castle' then out.rank=c.base.value; out.id=c.base.id end
                if key~='j_mail' then out.suit=c.base.suit end
            end
        end
        a.round[field]=D.copy(out)
        return out,pool
    end
    function M.guaranteed_seal(s,rng)
        local pool,total={},0
        for _,v in ipairs(s.trigger.seals) do
            if not s.game.banned_keys[v.key] and not s.game.used_jokers[v.key] and v.weight>0 then pool[#pool+1]=v; total=total+v.weight end
        end
        assert(total>0,'oracle_action_unsupported')
        local roll,acc=rng:random('certsl'),0
        for _,v in ipairs(pool) do acc=acc+v.weight; if roll>1-acc/total then return v.key end end
    end
    function M.apply(s,rng,request)
        request=request or {}
        local a=s.trigger; local c=a.source; local key=c.key
        assert(M.supported(key) and not s.shop.unsupported and not c.custom,'oracle_action_unsupported')
        assert(not c.debuff or M.resets[key],'oracle_joker_debuffed')
        assert(not c.sliced,'oracle_consume_wait')
        local r={status='experimental',source=c,checks={},created={},condition='oracle_trigger_'..key}
        local function check(stream,odds,label,value)
            assert(type(odds)=='number' and odds>0,'oracle_action_unsupported')
            local success=M.roll(s,rng,stream,1,odds)
            r.checks[#r.checks+1]={key=stream,success=success,label=label or 'oracle_success',value=value}
            return success
        end
        local gen=M.generators[key]
        if gen then
            local room=gen[1]=='Joker' and a.joker_limit-#a.jokers-a.joker_buffer or a.consume_limit-#a.inventory-a.consume_buffer
            if room<=0 then r.inactive='oracle_joker_no_room'; return r end
        end
        if key=='m_lucky' then
            check('lucky_mult',5,'oracle_joker_mult',c.ability.mult)
            check('lucky_money',15,'oracle_joker_money',c.ability.p_dollars)
        elseif M.probabilities[key] then
            local p=M.probabilities[key]; local odds=p[2] and c.ability.extra[p[2]] or c.ability.extra
            local stream=p[1]..(key=='j_hallucination' and s.game.round_resets.ante or '')
            local label=(key=='m_glass' or key=='j_gros_michel' or key=='j_cavendish') and 'oracle_joker_destroy' or 'oracle_success'
            if not check(stream,odds,label) then return r end
        end
        if gen then
            local count=gen[1]=='Joker' and math.min(2,a.joker_limit-#a.jokers-a.joker_buffer) or 1
            for i=1,count do
                local card=O.shop_prediction.create(s,rng,gen[1],gen[2],{area='owned',rarity=gen[1]=='Joker' and 0 or nil})
                r.created[#r.created+1]=card
                s.shop.owned[card.key]=true
            end
        elseif M.resets[key] then
            if request.ante then s.game.round_resets.ante=request.ante end
            r.ante=s.game.round_resets.ante; r.current=D.copy(a.round[M.resets[key]])
            r.reset,r.pool=M.reset(s,rng,key)
        elseif key=='j_misprint' then r.mult=rng:random('misprint',c.ability.extra.min,c.ability.extra.max)
        elseif key=='j_todo_list' then
            local pool={}; for _,hand in ipairs(s.shop.visible_hands) do if hand~=c.ability.to_do_poker_hand then pool[#pool+1]=hand end end
            r.hand=rng:element(pool,'to_do'); r.pool=pool
        elseif key=='j_invisible' or key=='j_perkeo' or key=='j_madness' then
            if key=='j_invisible' and ((c.ability.invis_rounds or 0)<c.ability.extra or #a.jokers>a.joker_limit) then
                r.inactive='oracle_joker_not_ready'; return r
            end
            local pool={}
            for _,v in ipairs(key=='j_perkeo' and a.inventory or a.jokers) do
                if key=='j_perkeo' or (v.id~=c.id and (key~='j_madness' or (not v.eternal and not v.sliced))) then pool[#pool+1]=v end
            end
            if #pool==0 then r.inactive='oracle_joker_no_target'; return r end
            r.pool=pool; local target=rng:element(pool,key:sub(3)); r.target=D.copy(target)
            if key~='j_madness' then
                local copy=D.copy(r.target)
                if copy.key=='j_todo_list' then rng:element(s.shop.visible_hands,'to_do') end
                if key=='j_perkeo' then copy.edition='e_negative'
                elseif copy.edition=='e_negative' then copy.edition=nil end
                if copy.ability.invis_rounds then copy.ability.invis_rounds=0 end
                r.created[1]=copy
            end
        elseif key=='j_marble' or key=='j_certificate' then
            local _,front=rng:element(s.shop.fronts,key=='j_marble' and 'marb_fr' or 'cert_fr')
            r.created[1]={key=key=='j_marble' and 'm_stone' or 'c_base',set=key=='j_marble' and 'Enhanced' or 'Default',front=front,
                seal=key=='j_certificate' and M.guaranteed_seal(s,rng) or nil}
        end
        return r
    end
    function M.forecast(s,request)
        return O.ante_prediction.run(s,function(sh,rng) return M.apply(sh,rng,request) end)
    end
    return M
end
