local O,D=ORACLE,ORACLE.data
local passed,cases=0,0
local function eq(a,b,label) assert(D.encode(a)==D.encode(b),(label or '')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
local function test(name,fn) ORACLE_TEST_CASE=name; fn(); passed=passed+1; print('PASS '..name) end
local drain=ORACLE_CONSUMABLE_DRAIN
local fixture_base=Card.set_base
local fixture_constructor=getmetatable(Card).__call
local function fixture(seed,key)
    Card.set_base=fixture_base
    local c=ORACLE_CONSUMABLE_FIXTURE(seed,key)
    G.C.SUITS={}; G.GAME.blind={debuff_card=function() end}
    for _,r in pairs(SMODS.Ranks) do r.id=r.sort_id+1; r.nominal=r.face and 10 or r.key=='Ace' and 11 or tonumber(r.key); r.face_nominal=r.face and (r.id-10)/10 or 0 end
    for _,s in pairs(SMODS.Suits) do s.suit_nominal=s.sort_id/10 end
    dofile(ORACLE_TEST_SOURCE..'/deck_state_truth.lua')
    getmetatable(Card).__call=function(t,x,y,w,h,front,center,params)
        local card=fixture_constructor(t,x,y,w,h,front,center,params)
        card.playing_card=params and params.playing_card
        return card
    end
    for _,p in ipairs(G.playing_cards) do p:set_base(p.config.card,true) end
    for i=9,32 do
        local front=({'H_A','D_K','C_4','S_9'})[(i-9)%4+1]
        local p=Card(i,0,1,1.4,G.P_CARDS[front],G.P_CENTERS.c_base,{})
        p.playing_card=i; G.playing_cards[#G.playing_cards+1]=p
        local area=i<29 and G.deck or G.discard; area:emplace(p)
    end
    G.playing_card=32
    G.hand.cards[1].ability.perma_bonus=77
    G.hand.cards[2].ability.perma_mult=8
    G.hand.cards[2]:set_edition('e_polychrome'); G.hand.cards[2]:set_seal('Red')
    if key=='c_death' then G.hand.highlighted={G.hand.cards[1],G.hand.cards[2]} end
    return c
end
local function compare(c)
    local s=O.consumables.capture(G,SMODS,c); local original=D.encode(s)
    local live=D.encode(O.deck_state.capture(G,SMODS)); local prng=D.encode(G.GAME.pseudorandom)
    math.randomseed(417); local roll=math.random(); math.randomseed(417)
    local r,details=O.engine.predict('deck_consumable',s)
    eq(math.random(),roll,'live math RNG'); eq(D.encode(s),original,'caller snapshot')
    eq(D.encode(O.deck_state.capture(G,SMODS)),live,'live deck'); eq(D.encode(G.GAME.pseudorandom),prng,'live keyed RNG')
    local again=O.engine.predict('deck_consumable',s); eq(r,again,'repeated preview')
    G.consumeables.cards={}; Card.use_consumeable(c,G.consumeables); drain()
    local actual=O.deck_state.capture(G,SMODS)
    eq(O.deck_state.projection(actual,true),O.deck_state.projection(r.after,true),'complete physical cards and areas '..c.config.center.key)
    eq(G.GAME.pseudorandom,details.rng_after,'post-use streams')
    -- Native draw starts at the stack's end. Neither hand edits nor creations
    -- may be silently appended to this currently drawable stack.
    local expected=O.deck_state.list(r.after,'next')
    for i,p in ipairs(expected) do eq(G.deck.cards[#G.deck.cards-i+1].playing_card,p.playing_card,'next physical draw') end
    cases=cases+1
    return r,s
end
test('shadow deck transformations match native uses across 30 seeds and 24 consumables',function()
    local keys={'c_death','c_hanged_man','c_strength','c_sigil','c_ouija','c_immolate','c_cryptid','c_grim','c_familiar','c_incantation',
        'c_magician','c_empress','c_heirophant','c_lovers','c_chariot','c_justice','c_devil','c_tower','c_star','c_moon','c_sun','c_world','c_aura','c_talisman'}
    for seed=1,30 do for _,key in ipairs(keys) do compare(fixture('DECK_STATE'..seed,key)) end end
end)
test('same enhancement reapplied preserves permanent bonuses and resets native base values',function()
    local c=fixture('REAPPLY','c_chariot')
    local r=compare(c); local p=r.after.cards[1]
    eq(p.ability.perma_bonus,77); eq(p.ability.h_x_mult,G.hand.cards[1].ability.h_x_mult)
    c=fixture('KING_TO_ACE','c_strength'); G.hand.highlighted={G.hand.cards[2]}
    r=compare(c); eq(r.after.cards[2].base.id,14); eq(r.after.cards[2].base.nominal,11)
    c=fixture('ACE_TO_TWO','c_strength'); G.hand.highlighted={G.hand.cards[3]}
    r=compare(c); eq(r.after.cards[3].base.id,2)
end)
test('copy identities stay distinct, deletion prunes every area and pack boundary remains explicit',function()
    local c=fixture('COPY_PHYSICAL','c_cryptid'); G.booster_pack={}
    local r=compare(c)
    eq(#r.after.all,34); eq(#r.after.hand,10); assert(r.after.pack)
    assert(r.after.cards[33]~=r.after.cards[1]); eq(r.after.cards[33].ability.perma_bonus,77)
    r.after.cards[33].ability.perma_bonus=999; eq(r.after.cards[1].ability.perma_bonus,77)
    c=fixture('REMOVE_PHYSICAL','c_immolate'); r=compare(c)
    eq(#r.after.all,27); eq(#r.after.hand,3); eq(#r.after.deck,20)
end)
test('remaining seals and non-random hand upgrades preserve the physical deck',function()
    for _,key in ipairs({'c_deja_vu','c_trance','c_medium','c_black_hole','c_mars'}) do compare(fixture('DECK_UNCHANGED',key)) end
end)
test('native deck removal after a modification follows the shadow draw order',function()
    local r=compare(fixture('DECK_DRAW_AFTER','c_death'))
    dofile(ORACLE_TEST_SOURCE..'/deck_truth.lua')
    G.deck.config.type='deck'; G.deck.set_ranks=function() end
    for _,c in ipairs(G.deck.cards) do c.remove_from_area=function() end end
    for _,c in ipairs(O.deck_state.list(r.after,'next')) do
        eq(CardArea.remove_card(G.deck).playing_card,c.playing_card,'native remove_card')
    end
    assert(not CardArea.remove_card(G.deck))
end)
test('post-use validator detects altered physical stack and permanent bonus',function()
    for _,corruption in ipairs({'none','order','permanent'}) do
        local c=fixture('DECK_VALIDATE','c_strength')
        O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
        O.consumable_validator=dofile(ORACLE_TEST_ROOT..'/debug/consumable_validator.lua')(O); O.consumable_validator.install()
        G.consumeables.cards={}; Card.use_consumeable(c,G.consumeables)
        if corruption=='order' then G.deck.cards[1],G.deck.cards[2]=G.deck.cards[2],G.deck.cards[1]
        elseif corruption=='permanent' then G.hand.cards[1].ability.perma_bonus=99 end
        drain()
        if corruption=='none' then assert(O.validator.counts.MATCH==1 and not O.prediction_fault)
        else assert(O.validator.counts.MISMATCH==1 and O.prediction_fault) end
    end
end)
test('native consumed-card removal renumbers identities without disabling predictions',function()
    local previous_remove=Card.remove
    dofile(ORACLE_TEST_SOURCE..'/remove_truth.lua')
    local native_remove=Card.remove; Card.remove=previous_remove
    local previous_moveable,previous_remove_all=Moveable,remove_all
    Moveable={remove=function() end}; remove_all=function() end
    for seed=1,12 do
        for _,key in ipairs({'c_high_priestess','c_emperor','c_judgement','c_strength','c_hanged_man','c_cryptid','c_grim'}) do
            local c=fixture(seed==1 and 'HTS25CEP' or 'RENUMBER'..seed,key)
            G.GAME.round_resets.ante=2
            -- Viewing the native deck changes G.playing_cards order, but not
            -- the real deck stack. Card:remove later assigns IDs in this order.
            table.sort(G.playing_cards,function(a,b) return a.sort_id>b.sort_id end)
            local before=O.deck_state.capture(G,SMODS)
            O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
            O.consumable_validator=dofile(ORACLE_TEST_ROOT..'/debug/consumable_validator.lua')(O); O.consumable_validator.install()
            G.consumeables.cards={}; c.area=nil; G.CONTROLLER.locks.use=true
            Card.use_consumeable(c,G.consumeables)
            G.E_MANAGER:add_event({func=function()
                native_remove(c); G.CONTROLLER.locks.use=nil; return true
            end})
            drain()
            assert(O.validator.counts.MATCH==1 and O.controller.supported(),key..' false fault '..D.encode(O.validator.last))
            local live=O.deck_state.capture(G,SMODS); local encoded=D.encode(live)
            local normalized=O.deck_state.projection(live,true,before)
            assert(D.encode(normalized)~=D.encode(O.deck_state.projection(live,true)),'must exercise real renumbering')
            eq(D.encode(live),encoded,'normalization must not mutate captured state')
            eq(D.encode(O.deck_state.capture(G,SMODS)),encoded,'normalization must not mutate live cards')
            cases=cases+1
        end
    end
    Moveable=previous_moveable; remove_all=previous_remove_all
end)

test('identity alignment retains duplicate-card order, attribute and RNG mismatch detection',function()
    local previous_remove=Card.remove
    dofile(ORACLE_TEST_SOURCE..'/remove_truth.lua')
    local native_remove=Card.remove; Card.remove=previous_remove
    local previous_moveable,previous_remove_all=Moveable,remove_all
    Moveable={remove=function() end}; remove_all=function() end
    for _,corruption in ipairs({'order','attribute','rng'}) do
        local c=fixture('RENUMBER_CORRUPTION','c_high_priestess')
        -- Positions 1 and 5 of this fixture are distinct copies of H_A.
        assert(G.deck.cards[1].config.card_key==G.deck.cards[5].config.card_key)
        table.sort(G.playing_cards,function(a,b) return a.sort_id>b.sort_id end)
        O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
        O.consumable_validator=dofile(ORACLE_TEST_ROOT..'/debug/consumable_validator.lua')(O); O.consumable_validator.install()
        G.consumeables.cards={}; c.area=nil; G.CONTROLLER.locks.use=true
        Card.use_consumeable(c,G.consumeables)
        G.E_MANAGER:add_event({func=function()
            native_remove(c)
            if corruption=='order' then G.deck.cards[1],G.deck.cards[5]=G.deck.cards[5],G.deck.cards[1]
            elseif corruption=='attribute' then G.deck.cards[1].ability.perma_bonus=99
            else G.GAME.pseudorandom.unexpected=0.125 end
            G.CONTROLLER.locks.use=nil; return true
        end})
        drain()
        assert(O.validator.counts.MISMATCH==1 and O.prediction_fault,'lost '..corruption..' detection')
        cases=cases+1
    end
    Moveable=previous_moveable; remove_all=previous_remove_all
end)

test('branch native UI supports before/after piles, pagination, list and cached previews',function()
    local c=fixture('DECK_UI','c_strength'); O.config.show_draw_order=true
    G.UIT={ROOT=1,R=2,C=3,T=4,O=5,B=6}
    local colour={}; G.C=setmetatable({SUITS={},UI=setmetatable({},{__index=function() return colour end})},{__index=function() return colour end})
    local calls=0; local predict=O.engine.predict
    O.engine.predict=function(...) calls=calls+1; return predict(...) end
    O.consumables_ui=dofile(ORACLE_TEST_ROOT..'/ui/consumables.lua')(O)
    O.deck_after_ui=dofile(ORACLE_TEST_ROOT..'/ui/deck_after.lua')(O)
    local preview=O.preview_card.area
    O.preview_card.area=function(cards) return {n=G.UIT.R,nodes={},config={oracle_cards=D.copy(cards)}} end
    O.consumables_ui.view=2; local before=D.encode(O.consumables.capture(G,SMODS,c))
    O.consumables_ui.definition(); O.consumables_ui.definition(); eq(calls,1)
    for _,pile in ipairs({1,2,3,4}) do for _,view in ipairs({1,2}) do for _,when in ipairs({1,2}) do
        O.deck_after_ui.pile=pile; O.deck_after_ui.view=view; O.deck_after_ui.when=when; O.deck_after_ui.page=2
        O.consumables_ui.definition()
    end end end
    eq(calls,1); eq(D.encode(O.consumables.capture(G,SMODS,c)),before,'UI state mutation')
    G.hand.highlighted={G.hand.cards[2]}; O.consumables_ui.definition(); eq(calls,2,'selection invalidates cache')
    O.engine.predict=predict; O.preview_card.area=preview
end)
print('Deck state: '..passed..' test groups, '..cases..' native cases passed')
