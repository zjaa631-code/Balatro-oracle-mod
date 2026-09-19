return function(O)
    local M,D={},O.data
    -- Native load restores sort_id without reserving that number globally.
    -- Distinct live objects can therefore share it. Keep private weak identities
    -- outside cards/G.GAME; snapshots contain only the numeric token. sort_id
    -- remains untouched and is still used by native RNG candidate ordering.
    local identities=setmetatable({},{__mode='k'})
    local identity_counter=0
    function M.identity(card)
        if not identities[card] then identity_counter=identity_counter+1; identities[card]=identity_counter end
        return identities[card]
    end
    local function require_target(ok) assert(ok,'oracle_consume_selection') end
    local function simple(c)
        return {key=c.key,set=c.set,front=c.front,edition=c.edition,seal=c.seal,
            eternal=c.eternal or false,perishable=c.perishable or false,rental=c.rental or false,to_do_poker_hand=c.to_do_poker_hand}
    end
    M.simple=simple
    -- SMODS change_size updates mod before the next CardArea update refreshes
    -- total_slots. Read the settled value without invoking a live update.
    local function hand_limit(area)
        local limits=area and area.config and area.config.card_limits
        if not limits or limits.base==nil then return area and area.config.card_limit or 0 end
        local size=limits.base+(limits.mod or 0)
        for _,c in ipairs(area.cards or {}) do size=size+(c.ability.card_limit or 0)-(c.ability.extra_slots_used or 0) end
        return size
    end
    function M.card(c)
        local r=O.shop_snapshot.card(c)
        r.id=M.identity(c); r.sort_id=c.sort_id; r.playing_card=c.playing_card
        r.x=(c.T or {}).x or 0; r.base=D.copy(c.base or {}); r.debuff=c.debuff or false
        r.ability=D.copy(c.ability or {})
        r.added=c.added_to_deck
        if c.config.center.mod then r.custom=true end
        return r
    end
    function M.capture(g,smods,card,using)
        assert(card and card.ability and card.ability.consumeable,'oracle_consume_empty')
        local s=O.shop_snapshot.capture(g,smods,true)
        local a={key=card.config.center.key,ability=D.copy(card.ability),hand={},playing={},selected={},jokers={},inventory={},
            levels={},suits={},ranks={},enhancements={},dollars=g.GAME.dollars or 0,ecto=g.GAME.ecto_minus or 1,
            last=g.GAME.last_tarot_planet,probability=(g.GAME.probabilities or {}).normal or 1,
            hand_size=hand_limit(g.hand),
            joker_limit=(g.jokers.config or {}).card_limit or 5,
            consume_limit=(g.consumeables.config or {}).card_limit or 2,
            debuff=card.debuff or false,using=using or false}
        s.action=a
        local blind=g.GAME.blind or {}
        a.manacle=blind.name=='The Manacle' and blind.boss and not blind.disabled or false
        -- During use_card, TAROT_INTERRUPT freezes SMODS area limits, including
        -- the used Negative consumable's slot, until its generation events finish.
        for _,c in ipairs(g.hand and g.hand.cards or {}) do a.hand[#a.hand+1]=M.card(c) end
        for _,c in ipairs(g.playing_cards or {}) do a.playing[#a.playing+1]=M.card(c) end
        for _,c in ipairs(g.hand and g.hand.highlighted or {}) do a.selected[#a.selected+1]=M.identity(c) end
        for _,c in ipairs(g.jokers.cards) do
            a.jokers[#a.jokers+1]=M.card(c)
        end
        -- Native Oops' context factor cancels the utility's Oops divisor;
        -- its add/remove/debuff behavior is already in probabilities.normal.
        for _,c in ipairs(g.consumeables.cards) do if c~=card then a.inventory[#a.inventory+1]=M.card(c) end end
        for key,h in pairs(g.GAME.hands) do a.levels[key]=h.level or 1 end
        for key,c in pairs(smods.Suits) do a.suits[key]={key=key,card_key=c.card_key,sort_id=c.sort_id} end
        for key,c in pairs(smods.Ranks) do a.ranks[key]={key=key,card_key=c.card_key,sort_id=c.sort_id,face=c.face,next=D.copy(c.next)} end
        for _,c in ipairs(g.P_CENTER_POOLS.Enhanced) do
            if not c.overrides_base_rank then a.enhancements[#a.enhancements+1]={key=c.key,sort_id=c.sort_id} end
        end
        local st=g.STATES
        a.hand_context=g.STATE==st.SELECTING_HAND or g.STATE==st.TAROT_PACK or g.STATE==st.SPECTRAL_PACK or
            g.STATE==st.PLANET_PACK or g.STATE==st.SMODS_BOOSTER_OPENED or using or false
        local locks=(g.CONTROLLER or {}).locks or {}
        a.busy=not using and (locks.use or locks.shop_reroll or (g.GAME.STOP_USE or 0)>0 or #(g.play and g.play.cards or {})>0) or false
        a.custom=card.config.center.mod~=nil
        if O.deck_state then
            local ok,world=pcall(O.deck_state.capture,g,smods)
            if ok then s.deck_state=world end
        end
        return s
    end
    local function selected(a)
        local out={}
        for _,id in ipairs(a.selected) do for _,c in ipairs(a.hand) do if c.id==id then out[#out+1]=c end end end
        return out
    end
    function M.apply(s,rng)
        local a=s.action; local key=a.key; local ability=a.ability; local cfg=ability.consumeable
        assert(not s.shop.unsupported and not a.custom,'oracle_action_unsupported')
        assert(not a.busy and not a.debuff,'oracle_consume_wait')
        local r={key=key,status='experimental',created={},destroyed={},changes={},levels={},money=0,hand_size=0}
        local targets=selected(a)
        local function change(c,fn)
            local before=D.copy(c); fn(c); r.changes[#r.changes+1]={id=c.id,before=before,after=D.copy(c)}
        end
        local function destroy(c) if c then r.destroyed[#r.destroyed+1]=D.copy(c) end end
        local function make(kind,append,args)
            local c=O.shop_prediction.create(s,rng,kind,append,args or {area='owned'})
            r.created[#r.created+1]=c; return c
        end
        local function rank(c,value,suit)
            local su=a.suits[suit or c.base.suit]; local ra=a.ranks[value or c.base.value]
            assert(su and ra,'oracle_action_unsupported')
            c.front=su.card_key..'_'..ra.card_key
            c.base.suit=su.key; c.base.value=ra.key
        end
        if cfg.max_highlighted then require_target(a.hand_context and #targets>=(cfg.min_highlighted or 1) and #targets<=(cfg.mod_num or cfg.max_highlighted)) end
        if key=='c_judgement' or key=='c_soul' or key=='c_wraith' then
            require_target(#a.jokers<a.joker_limit)
            make('Joker',key=='c_judgement' and 'jud' or key=='c_soul' and 'sou' or 'wra',
                {area='owned',legendary=key=='c_soul',rarity=key=='c_wraith' and 0.99 or nil})
            if key=='c_wraith' then r.money=-a.dollars end
        elseif key=='c_emperor' or key=='c_high_priestess' or key=='c_fool' then
            require_target(#a.inventory<a.consume_limit)
            local count=key=='c_fool' and 1 or cfg.tarots or cfg.planets
            if key=='c_fool' then require_target(a.last and a.last~='c_fool') end
            for i=1,math.min(count,a.consume_limit-#a.inventory) do
                make(key=='c_emperor' and 'Tarot' or key=='c_high_priestess' and 'Planet' or 'Tarot_Planet',
                    key=='c_emperor' and 'emp' or key=='c_high_priestess' and 'pri' or 'fool',{area='owned',forced=key=='c_fool' and a.last or nil})
            end
        elseif key=='c_wheel_of_fortune' or key=='c_ectoplasm' or key=='c_hex' then
            local pool={}; for _,c in ipairs(a.jokers) do if c.set=='Joker' and not c.edition then pool[#pool+1]=c end end
            require_target(#pool>0)
            local stream=key:sub(3)
            r.success=key~='c_wheel_of_fortune' or rng:random(stream)<a.probability/ability.extra
            if r.success then
                local c=rng:element(pool,stream)
                change(c,function(target) target.edition=key=='c_hex' and 'e_polychrome' or key=='c_ectoplasm' and 'e_negative' or O.shop_prediction.edition(s,rng,stream,true,true) end)
                if key=='c_hex' then for _,other in ipairs(a.jokers) do if other.id~=c.id and not other.eternal then destroy(other) end end end
                if key=='c_ectoplasm' then r.hand_size=-a.ecto; a.ecto=a.ecto+1 end
            end
        elseif key=='c_ankh' then
            require_target(#a.jokers>0 and a.joker_limit>1 and #a.jokers<a.joker_limit)
            local chosen=rng:element(a.jokers,'ankh_choice'); r.target=D.copy(chosen)
            for _,c in ipairs(a.jokers) do if c.id~=chosen.id and not c.eternal then destroy(c) end end
            if chosen.key=='j_todo_list' then rng:element(s.shop.visible_hands,'to_do') end
            local c=simple(chosen); c.ability=D.copy(chosen.ability); if c.edition=='e_negative' then c.edition=nil end
            r.created[#r.created+1]=c
        elseif key=='c_aura' then
            require_target(#targets==1 and not targets[1].edition)
            change(targets[1],function(c) c.edition=O.shop_prediction.edition(s,rng,'aura',true,true) end)
        elseif key=='c_cryptid' then
            require_target(#targets==1)
            r.target=D.copy(targets[1]); for i=1,ability.extra do local c=simple(targets[1]); c.ability=D.copy(targets[1].ability); c.base=D.copy(targets[1].base); r.created[#r.created+1]=c end
        elseif key=='c_sigil' or key=='c_ouija' then
            require_target(a.hand_context and #a.hand>1)
            local choice=rng:element(key=='c_sigil' and a.suits or a.ranks,key:sub(3))
            r.choice=choice.key
            for _,c in ipairs(a.hand) do change(c,function(t) rank(t,key=='c_ouija' and choice.key or nil,key=='c_sigil' and choice.key or nil) end) end
            if key=='c_ouija' then r.hand_size=-1 end
        elseif key=='c_grim' or key=='c_familiar' or key=='c_incantation' or key=='c_immolate' then
            require_target(a.hand_context and #a.hand>1)
            if key=='c_immolate' then
                local hand=D.copy(a.hand)
                table.sort(hand,function(x,y) return not x.playing_card or not y.playing_card or x.playing_card<y.playing_card end)
                rng:shuffle(hand,'immolate')
                for i=1,math.min(#hand,ability.extra.destroy) do destroy(hand[i]) end
                r.money=ability.extra.dollars
            else
                destroy(rng:element(a.hand,'random_destroy'))
                local ranks={}; for _,v in pairs(a.ranks) do if (key=='c_familiar' and v.face) or (key=='c_incantation' and v.key~='Ace' and not v.face) then ranks[#ranks+1]=v end end
                table.sort(ranks,function(x,y) return x.sort_id<y.sort_id end)
                for i=1,ability.extra do
                    local stream=key:sub(3)..'_create'
                    local ra=key=='c_grim' and 'A' or rng:element(ranks,stream).card_key
                    local su=rng:element(a.suits,stream).card_key
                    local enhancement=rng:element(a.enhancements,'spe_card').key
                    r.created[#r.created+1]={key=enhancement,set='Enhanced',front=su..'_'..ra,eternal=false,perishable=false,rental=false}
                end
            end
        elseif cfg.hand_type or key=='c_black_hole' then
            for hand,level in pairs(a.levels) do if key=='c_black_hole' or hand==cfg.hand_type then
                r.levels[#r.levels+1]={hand=hand,before=level,after=level+1}; a.levels[hand]=level+1
            end end
            table.sort(r.levels,function(x,y) return x.hand<y.hand end)
        elseif key=='c_hermit' then r.money=math.max(0,math.min(a.dollars,ability.extra))
        elseif key=='c_temperance' then r.money=ability.money or 0
        elseif key=='c_hanged_man' then for i=#targets,1,-1 do destroy(targets[i]) end
        elseif key=='c_talisman' or key=='c_deja_vu' or key=='c_trance' or key=='c_medium' then
            change(targets[1],function(c) c.seal=ability.extra end)
        elseif cfg.mod_conv or cfg.suit_conv then
            local rightmost=targets[1]; for _,c in ipairs(targets) do if c.x>rightmost.x then rightmost=c end end
            for _,c in ipairs(targets) do
                if key=='c_death' then
                    if c~=rightmost then change(c,function(t)
                        for _,f in ipairs({'key','set','front','edition','seal','base','ability','debuff','eternal','perishable','rental'}) do t[f]=D.copy(rightmost[f]) end
                    end) end
                elseif key=='c_strength' then change(c,function(t) rank(t,a.ranks[t.base.value].next[1]) end)
                elseif cfg.suit_conv then change(c,function(t) rank(t,nil,cfg.suit_conv) end)
                else change(c,function(t) t.key=cfg.mod_conv; t.set='Enhanced' end) end
            end
        else error('oracle_action_unsupported') end
        local function hand_bonus(c)
            if c.set~='Joker' then return 0 end
            local config=c.ability or s.shop.centers[c.key].config
            local size=config.h_size or 0
            if c.key=='j_turtle_bean' or c.key=='j_troubadour' then size=size+config.extra.h_size
            elseif c.key=='j_stuntman' then size=size-config.extra.h_size end
            return size
        end
        for _,c in ipairs(r.created) do
            r.hand_size=r.hand_size+hand_bonus(c)
            if c.key=='j_chicot' and a.manacle then r.hand_size=r.hand_size+1; a.manacle=false end
        end
        for _,c in ipairs(r.destroyed) do if c.added~=false then r.hand_size=r.hand_size-hand_bonus(c) end end
        a.dollars=a.dollars+r.money; a.hand_size=a.hand_size+r.hand_size
        return r
    end
    function M.forecast(s)
        return O.ante_prediction.run(s,M.apply)
    end
    -- Compare only direct effects; Joker scoring/stat changes are a separate phase.
    function M.expected(r)
        local out={created={},destroyed={},changes={},levels=r.levels,money=r.money,hand_size=r.hand_size}
        for _,c in ipairs(r.created) do out.created[#out.created+1]=simple(c) end
        for _,c in ipairs(r.destroyed) do out.destroyed[#out.destroyed+1]=c.id end
        table.sort(out.destroyed)
        for _,c in ipairs(r.changes) do if D.encode(simple(c.before))~=D.encode(simple(c.after)) then out.changes[#out.changes+1]={id=c.id,after=simple(c.after)} end end
        table.sort(out.changes,function(a,b) return a.id<b.id end)
        return out
    end
    function M.observe(before,g)
        local old,live={},{}; local out={created={},destroyed={},changes={},levels={},money=(g.GAME.dollars or 0)-before.action.dollars,
            hand_size=hand_limit(g.hand)-before.action.hand_size}
        for _,area in ipairs({before.action.jokers,before.action.playing,before.action.inventory}) do for _,c in ipairs(area) do old[c.id]=c end end
        for _,area in ipairs({g.jokers.cards,g.playing_cards,g.consumeables.cards}) do for _,c in ipairs(area) do live[M.identity(c)]=M.card(c) end end
        for id,c in pairs(old) do
            if not live[id] then out.destroyed[#out.destroyed+1]=id
            elseif D.encode(simple(c))~=D.encode(simple(live[id])) then out.changes[#out.changes+1]={id=id,after=simple(live[id])} end
        end
        local new={}; for id,c in pairs(live) do if not old[id] then new[#new+1]=c end end
        table.sort(new,function(a,b)
            local x,y=a.sort_id or a.id,b.sort_id or b.id
            return x==y and a.id<b.id or x<y
        end)
        for _,c in ipairs(new) do out.created[#out.created+1]=simple(c) end
        table.sort(out.destroyed); table.sort(out.changes,function(a,b) return a.id<b.id end)
        for hand,level in pairs(before.action.levels) do if g.GAME.hands[hand].level~=level then out.levels[#out.levels+1]={hand=hand,before=level,after=g.GAME.hands[hand].level} end end
        table.sort(out.levels,function(a,b) return a.hand<b.hand end)
        return out
    end
    return M
end
