-- Native Boss rules over detached data; no live Card:is_face/get_id calls.
-- In particular, a Stone Card's native get_id consumes global math RNG.
return function(O)
    local M,D={},O.data
    M.keys={bl_hook=true,bl_ox=true,bl_house=true,bl_wall=true,bl_wheel=true,bl_arm=true,bl_club=true,
        bl_fish=true,bl_psychic=true,bl_goad=true,bl_water=true,bl_window=true,bl_manacle=true,bl_eye=true,
        bl_mouth=true,bl_plant=true,bl_serpent=true,bl_pillar=true,bl_needle=true,bl_head=true,bl_tooth=true,
        bl_flint=true,bl_mark=true,bl_final_acorn=true,bl_final_leaf=true,bl_final_vessel=true,bl_final_heart=true,bl_final_bell=true}
    function M.context(g,sm,blind)
        local proto=blind.config and blind.config.blind
        assert(proto and M.keys[proto.key] and not proto.mod,'oracle_boss_analysis_unsupported')
        local s={game={pseudorandom=D.copy(g.GAME.pseudorandom),round_resets={ante=g.GAME.round_resets.ante},round=g.GAME.round},
            blind={key=proto.key,name=proto.name,disabled=blind.disabled or false,debuff=D.copy(blind.debuff or proto.debuff or {}),
                hands=D.copy(blind.hands or {}),only_hand=blind.only_hand,mult=proto.mult},
            levels={},jokers={},ranks={},dollars=g.GAME.dollars or 0,most_played=g.GAME.current_round.most_played_poker_hand,
            round=D.copy(g.GAME.current_round),hands_per_round=g.GAME.round_resets.hands or 0,probability=(g.GAME.probabilities or {}).normal or 1}
        for _,c in ipairs(g.jokers.cards) do
            assert(not c.config.center.mod,'oracle_boss_analysis_unsupported')
            if not c.debuff then s.jokers[c.config.center.key]=true end
        end
        for key,r in pairs(sm.Ranks) do assert(not r.mod,'oracle_boss_analysis_unsupported'); s.ranks[key]={face=r.face} end
        for key,h in pairs(g.GAME.hands) do s.levels[key]={level=h.level,chips=h.chips,mult=h.mult,visible=h.visible,order=h.order} end
        return s
    end
    function M.capture(g,sm,mode)
        local b=g.GAME.blind or {}; local proto=b.config and b.config.blind
        local st=g.STATES or {}
        local in_round=g.STATE==st.SELECTING_HAND or g.STATE==st.DRAW_TO_HAND or g.STATE==st.HAND_PLAYED
        local current=in_round and proto and M.keys[proto.key]
        mode=mode or (current and 'current' or 'upcoming')
        if mode=='current' then assert(current,'oracle_boss_no_active')
        else
            local key=(g.GAME.round_resets.blind_choices or {}).Boss
            assert(key and g.P_BLINDS[key],'oracle_boss_analysis_unsupported')
            b={config={blind=g.P_BLINDS[key]}}
        end
        local s=M.context(g,sm,b); s.mode=mode or 'upcoming'
        if s.mode~='current' then
            s.round.discards_left=math.max(0,(g.GAME.round_resets.discards or 0)+((g.GAME.round_bonus or {}).discards or 0))
        end
        if s.mode~='current' and s.jokers.j_chicot then s.blind.disabled=true; s.chicot=true end
        s.world=O.deck_state.capture(g,sm)
        for _,c in ipairs(g.playing_cards) do s.world.cards[c.playing_card].vampired=c.vampired end
        s.selected=#(g.hand.highlighted or {})
        return s
    end
    function M.card_effect(s,c)
        assert(not c.custom,'oracle_boss_analysis_unsupported')
        local b=s.blind; local d=b.debuff; local a=c.ability or {}; local base=c.base or {}
        local stone=c.key=='m_stone'
        -- Native is_face ignores debuff for Boss checks, and Pareidolia applies
        -- even to a rankless Stone. No need to sample its negative dummy ID.
        local face=((not stone or c.vampired) and (base.id or 0)>0 and (s.ranks[base.value] or {}).face) or s.jokers.j_pareidolia
        local function colour(suit)
            return ({Hearts='red',Diamonds='red',Spades='black',Clubs='black'})[suit]
        end
        local suit=not stone and (c.key=='m_wild' or base.suit==d.suit or
            (s.jokers.j_smeared and colour(d.suit) and colour(d.suit)==colour(base.suit)))
        local affected=not b.disabled and ((d.suit and suit) or (d.is_face=='face' and face) or
            (b.name=='The Pillar' and a.played_this_ante) or (d.value and base.value==d.value) or
            (d.nominal and base.nominal==d.nominal) or b.name=='Verdant Leaf') or false
        local debuffed=affected
        for _,v in pairs(a.debuff_sources or {}) do
            if v=='prevent_debuff' then return {debuff=false,affected=false} end
            debuffed=debuffed or v
        end
        if a.perishable and (a.perish_tally or 0)<=0 then debuffed=true end
        return {debuff=not not debuffed,affected=not not affected}
    end
    function M.hand_effect(s,request)
        local h=assert(s.levels[request.hand],'oracle_boss_analysis_unsupported')
        local b=s.blind; local d=b.debuff; local size=request.count or 0
        local r={blocked=false,level_before=h.level,level_after=h.level,money=0,mult=h.mult,chips=h.chips,modified=false}
        if b.disabled then return r end
        r.blocked=not not ((d.h_size_ge and size<d.h_size_ge) or (d.h_size_le and size>d.h_size_le) or
            (d.hand and request.poker_hands and request.poker_hands[d.hand]) or
            (b.name=='The Eye' and b.hands[request.hand]) or (b.name=='The Mouth' and b.only_hand and b.only_hand~=request.hand))
        if r.blocked then return r end
        if b.name=='The Arm' and h.level>1 then r.level_after=h.level-1
        elseif b.name=='The Ox' and request.hand==s.most_played then r.money=-s.dollars
        elseif b.name=='The Tooth' then r.money=-size
        elseif b.name=='The Flint' then
            r.mult=math.max(math.floor(h.mult*0.5+0.5),1); r.chips=math.max(math.floor(h.chips*0.5+0.5),0); r.modified=true
        end
        return r
    end
    function M.analyze(s,request)
        local out={key=s.blind.key,status='experimental',disabled=s.blind.disabled,chicot=s.chicot,affected={},total=#s.world.all,
            mode=s.mode,hand=M.hand_effect(s,request),hand_key=request.hand,count=request.count,mult=s.blind.mult,notes={}}
        for _,id in ipairs(s.world.all) do
            local c=s.world.cards[id]; local effect=M.card_effect(s,c)
            if effect.affected then local copy=D.copy(c); copy.debuff=effect.debuff; out.affected[#out.affected+1]=copy end
        end
        local key=out.key
        out.card_rule=({bl_club=true,bl_goad=true,bl_head=true,bl_window=true,bl_plant=true,bl_pillar=true,bl_final_leaf=true})[key]
        if not out.disabled then
            if s.mode=='current' then -- Entry costs have already been applied.
            elseif key=='bl_manacle' then out.hand_size_delta=-1
            elseif key=='bl_water' then out.discards_delta=-(s.round.discards_left or 0)
            elseif key=='bl_needle' then out.hands_delta=-(s.hands_per_round-1) end
            if key=='bl_hook' or key=='bl_wheel' or key=='bl_final_acorn' or key=='bl_final_bell' or key=='bl_final_heart' then
                out.notes[#out.notes+1]='oracle_boss_random_boundary'
            end
            if key=='bl_mark' or key=='bl_house' or key=='bl_fish' or key=='bl_serpent' then out.notes[#out.notes+1]='oracle_boss_draw_boundary' end
        end
        return out
    end
    return M
end
