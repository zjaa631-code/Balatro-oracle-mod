-- Detached physical-card state. No Card constructors, live callbacks or RNG.
return function(O)
    local M,D={},O.data
    local piles={'hand','deck','discard','play'}
    function M.capture(g,sm)
        local w={cards={},all={},hand={},deck={},discard={},play={},ranks={},suits={},fronts={},
            counter=g.playing_card or 0,pack=g.booster_pack~=nil,hands_played=g.GAME.hands_played or 0,
            blind={},jokers={}}
        for _,c in ipairs(g.playing_cards or {}) do
            local r=O.consumables.card(c); local id=c.playing_card
            assert(id and not w.cards[id],'oracle_deck_branch_unavailable')
            w.cards[id]=r; w.all[#w.all+1]=id
        end
        for _,name in ipairs(piles) do for _,c in ipairs(g[name] and g[name].cards or {}) do
            if c.playing_card then assert(w.cards[c.playing_card],'oracle_deck_branch_unavailable'); w[name][#w[name]+1]=c.playing_card end
        end end
        for key,r in pairs(sm.Ranks) do w.ranks[key]={id=r.id,nominal=r.nominal,face_nominal=r.face_nominal,face=r.face} end
        for key,s in pairs(sm.Suits) do w.suits[key]={suit_nominal=s.suit_nominal,shade=s.shade,colour=D.copy(g.C.SUITS and g.C.SUITS[key])} end
        for key,f in pairs(g.P_CARDS) do w.fronts[key]={name=f.name,suit=f.suit,value=f.value} end
        local b=g.GAME.blind or {}
        w.blind={name=b.name,disabled=b.disabled,debuff=D.copy(b.debuff)}
        for _,c in ipairs(g.jokers.cards) do if not c.debuff then w.jokers[c.config.center.key]=true end end
        return w
    end
    local function base(w,c,front,initial)
        local f=assert(w.fronts[front],'oracle_deck_branch_unavailable')
        local r,s=w.ranks[f.value] or {},w.suits[f.suit] or {}
        c.base={name=f.name,suit=f.suit,value=f.value,id=r.id,nominal=r.nominal or 0,
            face_nominal=r.face_nominal or 0,suit_nominal=s.suit_nominal or 0,
            suit_nominal_original=(c.base or {}).suit_nominal_original or s.suit_nominal or 0,
            colour=D.copy(s.colour),shade=s.shade,times_played=0,original_value=initial and f.value or nil}
    end
    -- Audited vanilla subset of Card:set_ability: playing-card centers only.
    local zero={'mult','h_mult','h_x_mult','h_dollars','p_dollars','t_mult','t_chips','h_chips','repetitions','h_size','d_size'}
    local perma={'bonus','x_chips','mult','x_mult','h_chips','h_x_chips','h_mult','h_x_mult','p_dollars','h_dollars','repetitions',
        'score','h_score','x_score','h_x_score','blind_size','h_blind_size','x_blind_size','h_x_blind_size'}
    local function ability(w,c,center,previous)
        local a=D.copy(c.ability or {}); local cfg=center.config or {}
        a.bonus=(a.bonus or 0)-(((previous or {}).config or {}).bonus or 0)+(cfg.bonus or 0)
        for _,k in ipairs(zero) do a[k]=cfg[k] or 0 end
        for _,k in ipairs(perma) do a['perma_'..k]=a['perma_'..k] or 0 end
        a.x_mult=cfg.Xmult or cfg.x_mult or 1; a.x_chips=cfg.x_chips or 1; a.h_x_chips=cfg.h_x_chips or 1
        a.name=center.name or center.key; a.set=center.set; a.effect=center.effect
        a.type=cfg.type or ''; a.order=center.order; a.extra=D.copy(cfg.extra)
        a.played_this_ante=nil; a.perma_debuff=nil; a.debuff_sources={}
        a.extra_value=a.extra_value or 0; a.card_limit=(a.card_limit or 0)+(cfg.card_limit or 0)
        a.extra_slots_used=(a.extra_slots_used or 0)+(cfg.extra_slots_used or 0)
        for k,v in pairs(cfg) do if k~='bonus' then a[k]=D.copy(v) end end
        a.hands_played_at_create=w.hands_played
        c.ability=a
    end
    local function debuff(w,c)
        local b=w.blind; local d=b.debuff or {}; local stone=c.key=='m_stone'
        local face=(not stone and (w.ranks[c.base.value] or {}).face) or w.jokers.j_pareidolia
        local function colour(s) return s=='Hearts' or s=='Diamonds' end
        local suit=not stone and (c.key=='m_wild' or c.base.suit==d.suit or
            (d.suit and w.jokers.j_smeared and colour(d.suit)==colour(c.base.suit)))
        local v=not b.disabled and ((d.suit and suit) or (d.is_face=='face' and face) or
            (b.name=='The Pillar' and c.ability.played_this_ante) or (d.value and d.value==c.base.value) or
            (d.nominal and d.nominal==c.base.nominal) or b.name=='Verdant Leaf') or false
        for _,source in pairs(c.ability.debuff_sources or {}) do if source=='prevent_debuff' then v=false; break else v=v or source end end
        c.debuff=not not v
    end
    function M.materialize(s,effects)
        assert(s.deck_state,'oracle_deck_branch_unavailable')
        local w=D.copy(s.deck_state)
        -- Positive hand-size effects can schedule automatic draws. Their event
        -- chain belongs to the later action/timeline engine, not this boundary.
        assert(effects.hand_size<=0,'oracle_deck_branch_draw_boundary')
        local by_sort={}; for id,c in pairs(w.cards) do by_sort[c.id]=id end
        for _,change in ipairs(effects.changes) do
            local id=by_sort[change.id]
            if id then
                local old=w.cards[id]; local c=D.copy(change.after)
                c.playing_card=id; c.id=old.id; c.sort_id=old.sort_id
                local rebased=c.front~=old.front or effects.key=='c_death' or effects.key=='c_strength' or
                    effects.key=='c_ouija' or effects.key=='c_sigil' or s.action.ability.consumeable.suit_conv
                if rebased then c.base=D.copy(old.base); base(w,c,c.front,false) end
                local enhanced=s.action.ability.consumeable.mod_conv and effects.key~='c_death' and effects.key~='c_strength'
                if enhanced then
                    c.ability=D.copy(old.ability); ability(w,c,s.shop.centers[c.key],s.shop.centers[old.key])
                end
                if effects.key~='c_death' and (rebased or enhanced) then debuff(w,c) end
                w.cards[id]=c
            end
        end
        local removed={}
        for _,c in ipairs(effects.destroyed) do local id=by_sort[c.id]; if id then w.cards[id]=nil; removed[id]=true end end
        for _,name in ipairs({'all','hand','deck','discard','play'}) do
            for i=#w[name],1,-1 do if removed[w[name][i]] then table.remove(w[name],i) end end
        end
        for _,record in ipairs(effects.created) do if record.set=='Default' or record.set=='Enhanced' then
            w.counter=w.counter+1; local id=w.counter
            assert(not w.cards[id],'oracle_deck_branch_unavailable')
            local c=D.copy(record); c.playing_card=id; c.id='oracle:'..id; c.sort_id=nil; c.added=true
            -- copy_card resets base even when ability/edition/seal are copied.
            c.base=effects.key=='c_cryptid' and {suit_nominal_original=0} or {}
            base(w,c,c.front,effects.key~='c_cryptid')
            if effects.key~='c_cryptid' then ability(w,c,s.shop.centers[c.key]); c.debuff=false
            else c.debuff=effects.target.debuff or false end
            w.cards[id]=c; w.all[#w.all+1]=id; w.hand[#w.hand+1]=id
        end end
        w.rng=D.copy(s.game.pseudorandom)
        return w
    end
    function M.list(w,name)
        local out={}; local ids=name=='next' and w.deck or w[name]
        for i=1,#ids do out[#out+1]=D.copy(w.cards[ids[name=='next' and #ids-i+1 or i]]) end
        return out
    end
    function M.forecast(s)
        local r,details=O.consumables.forecast(s)
        local after=M.materialize(s,r); after.rng=D.copy(details.rng_after)
        return {effects=r,before=D.copy(s.deck_state),after=after,status='experimental'},details
    end
    -- Card:remove renumbers every playing_card, even when removing a Tarot.
    -- For validation only, align live objects to the pre-action identities by
    -- their private object identity. New objects follow constructor order. Never sort
    -- an actual draw pile or match by card content (duplicates must stay distinct).
    function M.align_identities(w,before)
        local known,seen,remap,new={},{},{},{}
        for id,c in pairs(before.cards) do
            assert(type(c.id)=='number' and not known[c.id],'oracle_deck_identity_unavailable')
            known[c.id]=id
        end
        for id,c in pairs(w.cards) do
            assert(type(c.id)=='number' and not seen[c.id],'oracle_deck_identity_unavailable')
            seen[c.id]=true
            if known[c.id] then remap[id]=known[c.id]
            else new[#new+1]={id=id,sort_id=c.sort_id} end
        end
        table.sort(new,function(a,b) return a.sort_id<b.sort_id end)
        for i,c in ipairs(new) do remap[c.id]=before.counter+i end
        local aligned=D.copy(w); aligned.cards={}
        for id,c in pairs(w.cards) do
            local mapped=assert(remap[id],'oracle_deck_identity_unavailable')
            assert(not aligned.cards[mapped],'oracle_deck_identity_unavailable')
            aligned.cards[mapped]=D.copy(c); aligned.cards[mapped].playing_card=mapped
        end
        for _,name in ipairs({'all','hand','deck','discard','play'}) do
            for i,id in ipairs(w[name]) do aligned[name][i]=assert(remap[id],'oracle_deck_identity_unavailable') end
        end
        return aligned
    end
    -- Stable gameplay fields, in the input identity namespace when validating.
    function M.projection(w,areas,before)
        if before then w=M.align_identities(w,before) end
        local out={cards={},areas=areas and {deck=D.copy(w.deck),discard=D.copy(w.discard),play=D.copy(w.play)} or nil}
        local ids=D.copy(w.all); table.sort(ids)
        for _,id in ipairs(ids) do
            local c=w.cards[id]; local a=c.ability or {}; local b=c.base or {}
            local r={id=id,key=c.key,front=c.front,edition=c.edition,seal=c.seal,
                rank=b.id,suit=b.suit,value=b.value,nominal=b.nominal,face_nominal=b.face_nominal,ability={}}
            for _,k in ipairs({'bonus','mult','h_x_mult','x_mult','p_dollars','h_dollars','extra'}) do r.ability[k]=D.copy(a[k]) end
            for _,k in ipairs(perma) do r.ability['perma_'..k]=a['perma_'..k] or 0 end
            out.cards[#out.cards+1]=r
        end
        if areas then out.areas.hand=D.copy(w.hand); table.sort(out.areas.hand) end
        return out
    end
    return M
end
