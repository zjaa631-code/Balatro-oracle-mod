local O,D=ORACLE,ORACLE.data
local passed,cases=0,0
local function eq(a,b,label) assert(D.encode(a)==D.encode(b),(label or 'mismatch')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
local function test(name,fn) if ORACLE_JOKERS_ONLY then return end; ORACLE_TEST_CASE=name; fn(); passed=passed+1; print('PASS '..name) end
local noop=function() end
local events,nextid,native_use
local native_constructor=getmetatable(Card).__call
setmetatable(Card,{__call=function(_,x,y,w,h,front,center,params)
    local c=native_constructor(Card,x,y,w,h,front,center,params)
    nextid=nextid+1; c.sort_id=nextid; c.ability.card_limit=0; c.ability.extra_slots_used=0
    c:set_base(front); c.config.center_key=center.key
    return c
end})
function Card:set_base(front)
    self.config.card=front; self.base=D.copy(front or {}); self.config.card_key=nil
    for k,v in pairs(G.P_CARDS) do if v==front then self.config.card_key=k end end
end
function Card:change_suit(suit) SMODS.change_base(self,suit) end
function Card:set_edition(e)
    if type(e)=='string' then self.edition={key=e,[e:sub(3)]=true}
    elseif e and next(e) then self.edition=D.copy(e); for _,k in ipairs({'foil','holo','polychrome','negative'}) do if e[k] then self.edition.key='e_'..k end end
    else self.edition=nil end
    if self.edition and self.edition.key then self.edition.type=self.edition.key:sub(3) end
end
function Card:set_seal(seal) self.seal=seal end
Card.flip=noop; Card.juice_up=noop; Card.start_materialize=noop; Card.add_to_deck=noop
Card.set_cost=noop
Card.should_hide_front=function() return false end
function Card:start_dissolve()
    if self.added_to_deck then self:remove_from_deck() end
    for _,area in ipairs({G.hand,G.jokers}) do for i=#area.cards,1,-1 do if area.cards[i]==self then table.remove(area.cards,i) end end end
    for i=#G.playing_cards,1,-1 do if G.playing_cards[i]==self then table.remove(G.playing_cards,i) end end
end
Card.shatter=Card.start_dissolve
local function area(limit)
    return {cards={},highlighted={},config={card_limit=limit},T={x=0,y=0,w=8,h=2},
        emplace=function(self,c) self.cards[#self.cards+1]=c; c.area=self end,
        change_size=function(self,n) self.config.card_limit=self.config.card_limit+n end,
        unhighlight_all=function(self) self.highlighted={} end}
end
local function fixture(seed,key)
    ORACLE_PHASE3_FIXTURE(seed,3)
    ORACLE_TEST_CONTEXT.consumable=key
    O.prediction_fault=nil; O.status={issues={}}; O.config.enabled=true
    O.config.validate_predictions=false; O.controller=dofile(ORACLE_TEST_ROOT..'/controller.lua')(O)
    create_card=ORACLE_TRUTH_CREATE_CARD
    nextid=0; events={}; G.E_MANAGER={add_event=function(_,e) events[#events+1]=e end}; Event=function(e) return e end
    G.hand=area(8); G.deck=area(52); G.jokers=area(5); G.consumeables=area(2)
    G.pack_cards=area(5); G.discard=area(52); G.play=area(5); G.playing_cards={}
    G.STATE=G.STATES.SELECTING_HAND
    G.GAME.probabilities={normal=1}; G.GAME.dollars=27; G.GAME.last_tarot_planet='c_strength'
    G.GAME.bankrupt_at=0; G.GAME.interest_amount=1; G.GAME.round_resets.hands=4; G.GAME.round_resets.discards=3
    G.I={CARD={}}; G.P_CENTERS.e_base=G.P_CENTERS.e_base or {key='e_base',set='Edition'}
    G.C={SECONDARY_SET={Spectral={},Tarot={}}}; G.SETTINGS.GAMESPEED=1
    SMODS.Suits={}; SMODS.Ranks={}; SMODS.Rank={obj_buffer={}}
    SMODS.Suit={obj_list=function() local r={}; for _,v in pairs(SMODS.Suits) do r[#r+1]=v end; return r end}
    SMODS.Rank.obj_list=function() local r={}; for _,v in pairs(SMODS.Ranks) do r[#r+1]=v end; return r end
    local values={'2','3','4','5','6','7','8','9','10','Jack','Queen','King','Ace'}
    local codes={'2','3','4','5','6','7','8','9','T','J','Q','K','A'}
    for i,v in ipairs(values) do SMODS.Ranks[v]={key=v,card_key=codes[i],sort_id=i,face=i>=10 and i<=12,next={values[i%13+1]}}; SMODS.Rank.obj_buffer[i]=v end
    G.P_CARDS={empty={}}
    for i,suit in ipairs({'Spades','Hearts','Diamonds','Clubs'}) do
        SMODS.Suits[suit]={key=suit,card_key=suit:sub(1,1),sort_id=i}
        for j,value in ipairs(values) do G.P_CARDS[suit:sub(1,1)..'_'..codes[j]]={suit=suit,value=value,id=j+1} end
    end
    G.P_CENTERS.m_stone.overrides_base_rank=true
    SMODS.Consumable={legendaries={},take_ownership=function(_,k,def) for n,v in pairs(def) do G.P_CENTERS['c_'..k][n]=v end end}
    stop_use=noop; set_consumeable_usage=noop; update_hand_text=noop; delay=noop; play_sound=noop
    attention_text=noop; playing_card_joker_effects=noop; check_for_unlock=noop
    unlock_card=noop; discover_card=noop
    ease_discard=noop; calculate_reroll_cost=noop; SMODS.change_free_rerolls=noop
    SMODS.enh_cache.clear=noop; SMODS.is_playing_card=function(c) return c.playing_card~=nil end
    SMODS.shatters=function(c) return c.config.center.key=='m_glass' end
    SMODS.is_eternal=function(c) return c.ability.eternal end
    SMODS.find_card=function(k) local out={}; for _,c in ipairs(G.jokers.cards) do if c.config.center.key==k and not c.debuff then out[#out+1]=c end end; return out end
    SMODS.calculate_context=function(context)
        if context.mod_probability then return {numerator=context.numerator*2^#SMODS.find_card('j_oops')} end
        return {}
    end
    ease_dollars=function(n) G.GAME.dollars=G.GAME.dollars+n end
    level_up_hand=function(_,h) G.GAME.hands[h].level=G.GAME.hands[h].level+1 end
    Blind=Blind or {}
    dofile(ORACLE_TEST_SOURCE..'/consumable_truth.lua'); native_use=Card.use_consumeable
    for _,h in pairs(G.GAME.hands) do h.level=4 end
    for i,front in ipairs({'S_7','H_K','D_A','C_2','S_Q','D_T','H_5','C_9'}) do
        local c=Card(i,0,1,1.4,G.P_CARDS[front],G.P_CENTERS[i==1 and 'm_steel' or 'c_base'],{})
        c.playing_card=i; G.hand:emplace(c); G.playing_cards[#G.playing_cards+1]=c
    end
    G.hand.cards[1]:set_seal('Red')
    for _,joker in ipairs({'j_blueprint','j_mime','j_todo_list'}) do local c=Card(0,0,1,1.4,nil,G.P_CENTERS[joker],{}); G.jokers:emplace(c); c:add_to_deck() end
    G.jokers.cards[2].ability.eternal=true
    local center=G.P_CENTERS[key]; local c=Card(0,0,1,1.4,nil,center,{})
    c.ability.money=18
    G.consumeables:emplace(c)
    if center.config.max_highlighted then
        for i=1,center.config.min_highlighted or 1 do G.hand.highlighted[i]=G.hand.cards[i] end
    end
    if key=='c_aura' then G.hand.highlighted={G.hand.cards[1]} end
    c.eligible_strength_jokers=G.jokers.cards; c.eligible_editionless_jokers=G.jokers.cards
    return c
end
local function drain()
    local count=0
    while #events>0 do local e=table.remove(events,1); count=count+1; assert(count<2000,'event loop')
        if e.func and e.func()==false then events[#events+1]=e end
    end
end
local function compare(c)
    local before=O.consumables.capture(G,SMODS,c)
    local encoded=D.encode(before)
    math.randomseed(753); local sample=math.random(); math.randomseed(753)
    local result,details=O.engine.predict('consumable',before)
    assert(math.random()==sample,'Prediction polluted live math RNG')
    eq(D.encode(O.consumables.capture(G,SMODS,c)),encoded,'live snapshot after prediction')
    eq(D.encode(before),encoded,'caller snapshot mutated')
    -- The real use button removes the used card from its area before use_consumeable.
    for i=#G.consumeables.cards,1,-1 do if G.consumeables.cards[i]==c then table.remove(G.consumeables.cards,i) end end
    native_use(c,G.consumeables); drain()
    eq(O.consumables.observe(before,G),O.consumables.expected(result),'effects '..c.config.center.key)
    eq(G.GAME.pseudorandom,details.rng_after,'RNG '..c.config.center.key)
    cases=cases+1
    return result
end

test('all 52 vanilla consumables match installed use functions across 20 seeds',function()
    local keys={}; for k,c in pairs(ORACLE_TEST_PROTOS.P_CENTERS) do if c.consumeable then keys[#keys+1]=k end end
    table.sort(keys); assert(#keys==52,'Unexpected vanilla consumable count: '..#keys)
    for seed=1,20 do for _,key in ipairs(keys) do compare(fixture('CONSUME'..seed,key)) end end
end)
test('Wheel probability streams include Oops and failures do not poll target or edition',function()
    local success,fail=0,0
    for seed=1,100 do
        local c=fixture('WHEEL'..seed,'c_wheel_of_fortune')
        G.GAME.probabilities.normal=seed%3+1
        if seed%2==0 then G.jokers:emplace(Card(0,0,1,1.4,nil,G.P_CENTERS.j_oops,{})) end
        c.eligible_strength_jokers=G.jokers.cards
        local r=compare(c); if r.success then success=success+1 else fail=fail+1 end
    end
    assert(success>0 and fail>0)
end)
test('Ankh handles sort order, eternal survivors, negative stripping and copied To Do RNG',function()
    for seed=1,50 do
        local c=fixture('ANKH'..seed,'c_ankh')
        G.jokers.cards[1]:set_edition('e_negative')
        G.jokers.cards[1],G.jokers.cards[3]=G.jokers.cards[3],G.jokers.cards[1]
        compare(c)
    end
end)
test('selected card changes and generation respect pool exclusions, hidden planets and slots',function()
    for _,key in ipairs({'c_death','c_cryptid','c_high_priestess','c_emperor','c_grim','c_incantation','c_familiar'}) do
        local c=fixture('CONSUME_EDGES',key)
        G.hand.cards[1]:set_edition('e_polychrome')
        if key=='c_death' then G.hand.cards[1].T.x=100 end
        if key=='c_emperor' or key=='c_high_priestess' then G.consumeables:emplace(Card(0,0,1,1.4,nil,G.P_CENTERS.c_pluto,{})) end
        compare(c)
    end
end)
test('consumable validator waits for completion and detects an actual effect mismatch',function()
    local c=fixture('VALIDATE_CONSUME','c_wraith')
    O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
    O.consumable_validator=dofile(ORACLE_TEST_ROOT..'/debug/consumable_validator.lua')(O)
    O.consumable_validator.install()
    G.consumeables.cards={}; G.CONTROLLER.locks.use=true
    Card.use_consumeable(c,G.consumeables)
    events[#events+1]={func=function() G.CONTROLLER.locks.use=nil; return true end}
    drain(); assert(O.validator.counts.MATCH==1 and not O.prediction_fault)
    c=fixture('MISMATCH_CONSUME','c_hermit'); O.config.validate_predictions=true
    O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
    local record=O.validator.record; O.validator.record=function(...) local r=record(...); return r end
    O.consumable_validator=dofile(ORACLE_TEST_ROOT..'/debug/consumable_validator.lua')(O); O.consumable_validator.install()
    G.consumeables.cards={}; Card.use_consumeable(c,G.consumeables); G.GAME.dollars=999
    drain(); assert(O.validator.counts.MISMATCH==1 and O.prediction_fault)
end)
test('selection and transition gates are read-only and inherited forecasts remain available',function()
    local c=fixture('CONSUME_GUARDS','c_cryptid'); G.hand.highlighted={}
    local s=O.consumables.capture(G,SMODS,c); assert(not pcall(O.engine.predict,'consumable',s))
    G.hand.highlighted={G.hand.cards[1]}; G.CONTROLLER.locks.use=true
    assert(not pcall(O.engine.predict,'consumable',O.consumables.capture(G,SMODS,c)))
    G.CONTROLLER.locks.use=nil; c.debuff=true
    assert(not pcall(O.engine.predict,'consumable',O.consumables.capture(G,SMODS,c)))
    c.debuff=false; assert(O.engine.predict('consumable',O.consumables.capture(G,SMODS,c)))
end)

test('native buy-and-use queued payment does not disable later Tag predictions',function()
    for _,seed in ipairs({'U9WGYUR5','BUY_USE_2','BUY_USE_3','BUY_USE_4'}) do
        for _,key in ipairs({'c_wheel_of_fortune','c_hermit','c_wraith','c_temperance','c_judgement'}) do
            for _,cost in ipairs({0,1,3,6}) do
                local c=fixture(seed,key)
                G.GAME.dollars=7; c.cost=cost; c.children={}; c.is=function() return true end
                G.shop_jokers=area(2); G.consumeables.cards={}; G.shop_jokers:emplace(c)
                G.shop_jokers.remove_card=function(self,card)
                    for i=#self.cards,1,-1 do if self.cards[i]==card then table.remove(self.cards,i) end end
                    card.area=nil
                end
                G.GAME.round_scores={cards_purchased={amt=0}}
                G.HUD={get_UIE_by_ID=function() return {config={object={update=noop}}} end,recalculate=noop}
                G.CONTROLLER.save_cardarea_focus=noop; G.CONTROLLER.recall_cardarea_focus=noop
                inc_career_stat=noop; check_and_set_high_score=noop; remove_nils=noop
                localize=function(s) return s end
                dofile(ORACLE_TEST_SOURCE..'/purchase_truth.lua')
                -- Only use_card's rendering/animation is replaced; the native
                -- purchase callback, queued payment and consumable run verbatim.
                local calls=0
                G.FUNCS.use_card=function(e)
                    calls=calls+1; G.CONTROLLER.locks.use=true
                    e.config.ref_table:use_consumeable(G.shop_jokers)
                    events[#events+1]={func=function() G.CONTROLLER.locks.use=nil; return true end}
                    return 'used',nil,'sentinel',nil
                end
                O.config.validate_predictions=true
                O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
                O.consumable_validator=dofile(ORACLE_TEST_ROOT..'/debug/consumable_validator.lua')(O)
                O.consumable_validator.install()
                G.FUNCS.buy_from_shop({config={id='buy_and_use',ref_table=c}})
                drain()
                assert(calls==1 and not O.consumable_validator.purchase)
                assert(O.validator.counts.MATCH==1 and not O.prediction_fault,
                    seed..' '..key..' cost '..cost..' '..D.encode(O.validator.records[1]))
                local after=7-cost
                if key=='c_hermit' then after=after+math.min(after,c.ability.extra)
                elseif key=='c_wraith' then after=0
                elseif key=='c_temperance' then after=after+c.ability.money end
                eq(G.GAME.dollars,after,'actual purchase/use dollars')
                -- Same-session new run must retain a working prediction gate.
                assert(O.controller.supported())
                G.GAME.tags={}; G.pack_cards.cards={}; G.GAME.blind_on_deck='Small'
                local r=O.tag_prediction.get('tag_uncommon','Small')
                assert(r and r.status~='unavailable','Uncommon Tag blocked after buy-and-use')
                cases=cases+1
            end
        end
    end
end)

test('buy-and-use context preserves nil returns and clears after errors or ordinary use',function()
    local c=fixture('PURCHASE_SCOPE','c_hermit')
    local count=0
    G.FUNCS.use_card=function(e,...)
        count=count+1
        if e.fail then error('use failure') end
        assert(select('#',...)==2 and select(2,...)=='tail')
        if e.config.id=='buy_and_use' then assert(O.consumable_validator.purchase.card==c)
        else assert(not O.consumable_validator.purchase) end
        return 'ok',nil,'tail',nil
    end
    O.consumable_validator=dofile(ORACLE_TEST_ROOT..'/debug/consumable_validator.lua')(O)
    O.consumable_validator.install()
    local function tuple(...) return {n=select('#',...),...} end
    local e={config={id='buy_and_use',ref_table=c}}
    local r=tuple(G.FUNCS.use_card(e,nil,'tail')); assert(r.n==4 and r[3]=='tail' and count==1)
    e.fail=true; assert(not pcall(G.FUNCS.use_card,e)); assert(not O.consumable_validator.purchase)
    e.fail=nil; e.config.id='use'; G.FUNCS.use_card(e,nil,'tail')
    assert(not O.consumable_validator.purchase and count==3)
end)
test('Fool validation settles before its generated Planet is used even when its event is delayed',function()
    for seed=1,12 do
        local c=fixture('FOOL_BOUNDARY'..seed,'c_fool'); G.GAME.last_tarot_planet='c_mercury'
        G.GAME.hands.Pair.level=12
        G.FUNCS.use_card=function(e)
            G.CONTROLLER.locks.use=true
            local card=e.config.ref_table
            for i=#G.consumeables.cards,1,-1 do if G.consumeables.cards[i]==card then table.remove(G.consumeables.cards,i) end end
            card:use_consumeable(G.consumeables)
            events[#events+1]={func=function() G.CONTROLLER.locks.use=nil; return true end}
        end
        O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
        O.consumable_validator=dofile(ORACLE_TEST_ROOT..'/debug/consumable_validator.lua')(O); O.consumable_validator.install()
        G.FUNCS.use_card({config={ref_table=c}})
        local delayed=table.remove(events,#events-1)
        assert(delayed.trigger=='after' and delayed.blockable==false)
        drain(); eq(O.validator.counts.MATCH,0)
        local mercury=G.consumeables.cards[1]; eq(mercury.config.center.key,'c_mercury')
        G.FUNCS.use_card({config={ref_table=mercury}})
        events[#events+1]=delayed; drain()
        eq(O.validator.counts.MATCH,2); eq(O.validator.counts.MISMATCH,0)
        assert(O.controller.supported()); eq(G.GAME.hands.Pair.level,13)
        eq(O.validator.records[1].actual.effects.created[1].key,'c_mercury')
        eq(O.validator.records[1].actual.effects.levels,{})
        cases=cases+2
    end
end)

test('Undo cancels stale consumable callbacks but preserves genuine mismatch protection',function()
    local c=fixture('UNDO_PENDING','c_fool'); G.GAME.last_tarot_planet='c_mercury'
    O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
    O.consumable_validator=dofile(ORACLE_TEST_ROOT..'/debug/consumable_validator.lua')(O); O.consumable_validator.install()
    G.consumeables.cards={}; c:use_consumeable(G.consumeables)
    local delayed=table.remove(events); drain()
    O.consumable_validator.reset(); G.consumeables.cards={}
    assert(delayed.func()); eq(O.validator.counts.MISMATCH,0); assert(O.controller.supported())
    c=fixture('TRUE_MISMATCH','c_fool'); G.GAME.last_tarot_planet='c_mercury'
    O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
    O.consumable_validator=dofile(ORACLE_TEST_ROOT..'/debug/consumable_validator.lua')(O); O.consumable_validator.install()
    G.consumeables.cards={}; c:use_consumeable(G.consumeables)
    delayed=table.remove(events); drain(); G.consumeables.cards={}
    assert(delayed.func()); eq(O.validator.counts.MISMATCH,1); assert(not O.controller.supported())
    O.consumable_validator.reset(); assert(O.prediction_fault,'Undo must not hide genuine divergence')
end)

test('pack close moves cards without a false destruction report; new Joker hand-size effects agree',function()
    local c=fixture('PACK_CLOSE','c_sigil')
    local before=O.consumables.capture(G,SMODS,c); local r=O.engine.predict('consumable',before)
    G.consumeables.cards={}; native_use(c,G.pack_cards); drain()
    G.deck.cards=G.hand.cards; G.hand.cards={}
    eq(O.consumables.observe(before,G),O.consumables.expected(r),'cards survive closing pack')
    for _,key in ipairs({'j_juggler','j_merry_andy','j_turtle_bean','j_troubadour','j_stuntman'}) do
        c=fixture('HAND_SIZE_'..key,'c_ankh')
        G.jokers.cards={Card(0,0,1,1.4,nil,G.P_CENTERS[key],{})}; G.jokers.cards[1]:add_to_deck()
        compare(c)
    end
end)
test('Negative generators retain their native frozen slot during use; settled hand size is read without updates',function()
    for _,key in ipairs({'c_emperor','c_high_priestess','c_fool'}) do
        local c=fixture('NEGATIVE_'..key,key); c:set_edition('e_negative'); c.ability.card_limit=1
        G.consumeables.config.card_limit=3
        G.consumeables.config.type='joker'
        G.consumeables.config.card_limits={base=2,mod=0,total_slots=3,extra_slots=1,extra_slots_used=0}
        G.consumeables.count_property=CardArea.count_property
        G.consumeables:emplace(Card(0,0,1,1.4,nil,G.P_CENTERS.c_pluto,{}))
        G.TAROT_INTERRUPT=G.STATE
        CardArea.handle_card_limit(G.consumeables)
        local r=compare(c); assert(#r.created==(key=='c_fool' and 1 or 2))
        CardArea.handle_card_limit(G.consumeables); assert(G.consumeables.config.card_limits.total_slots==3)
        G.TAROT_INTERRUPT=nil
        CardArea.handle_card_limit(G.consumeables); assert(G.consumeables.config.card_limits.total_slots==2)
    end
    local c=fixture('DEFERRED_HAND_SIZE','c_ouija')
    G.hand.config.card_limits={base=8,mod=0,total_slots=8,extra_slots_used=0}
    G.hand.change_size=function(self,n) self.config.card_limits.mod=self.config.card_limits.mod+n end
    compare(c); assert(G.hand.config.card_limit==8,'fixture must retain stale rendered limit')
end)

test('copied Chicot disables Manacle once and restores its hand-size penalty',function()
    local c=fixture('CHICOT_MANACLE','c_ankh')
    G.jokers.cards={Card(0,0,1,1.4,nil,G.P_CENTERS.j_chicot,{})}
    G.jokers.cards[1].added_to_deck=true
    G.GAME.chips=0
    G.GAME.blind={name='The Manacle',boss=true,disabled=false,chips=100,disable=Blind.disable,
        debuff_card=noop,set_text=noop,wiggle=noop,config={blind={key='bl_manacle'}}}
    G.FUNCS.draw_from_deck_to_hand=noop; card_eval_status_text=noop
    local r=compare(c); assert(r.hand_size==1 and G.GAME.blind.disabled)
end)

test('reloaded sort-id collisions preserve generated cards and keep the prediction gate available',function()
    for seed=1,12 do for _,key in ipairs({'c_fool','c_high_priestess','c_emperor','c_judgement','c_wraith','c_soul','c_grim'}) do
        local c=fixture(seed==1 and 'HTS25CEP' or 'RELOADED_ID'..seed,key)
        G.GAME.round_resets.ante=2; G.GAME.last_tarot_planet='c_pluto'
        -- Card:load restores a saved sort_id without raising the constructor
        -- counter. The next native generated card can reuse this number.
        local old=G.jokers.cards[1]; old.sort_id=c.sort_id+1
        local playing=G.playing_cards[1]; playing.sort_id=old.sort_id
        local native_id=old.sort_id
        local snapshot=O.consumables.capture(G,SMODS,c)
        assert(snapshot.action.jokers[1].id~=snapshot.action.playing[1].id)
        eq(old.sort_id,native_id); eq(playing.sort_id,native_id)
        assert(rawget(old,'oracle_identity')==nil and rawget(playing,'oracle_identity')==nil)
        O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
        O.consumable_validator=dofile(ORACLE_TEST_ROOT..'/debug/consumable_validator.lua')(O); O.consumable_validator.install()
        G.consumeables.cards={}; c:use_consumeable(G.consumeables); drain()
        assert(O.validator.counts.MATCH==1 and O.controller.supported(),key..' false fault '..D.encode(O.validator.last))
        local r=O.validator.records[1]; assert(#r.actual.effects.created>0)
        local collision=false
        for _,area in ipairs({G.jokers.cards,G.playing_cards,G.consumeables.cards}) do for _,v in ipairs(area) do
            if v~=old and v~=playing and v.sort_id==native_id then
                collision=true; assert(O.consumables.identity(v)~=O.consumables.identity(old))
            end
        end end
        assert(collision,'must exercise actual native creation with reused sort_id')
        cases=cases+1
    end end
end)

test('duplicate native IDs do not merge selected cards or random Joker targets',function()
    for _,key in ipairs({'c_strength','c_cryptid','c_ankh','c_hex'}) do
        local c=fixture('DUPLICATE_TARGET_'..key,key)
        G.hand.cards[2].sort_id=G.hand.cards[1].sort_id
        G.jokers.cards[2].sort_id=G.jokers.cards[1].sort_id
        if key=='c_strength' or key=='c_cryptid' then G.hand.highlighted={G.hand.cards[2]} end
        local s=O.consumables.capture(G,SMODS,c)
        assert(s.action.hand[1].id~=s.action.hand[2].id)
        if #s.action.selected>0 then eq(s.action.selected,{s.action.hand[2].id}) end
        compare(c)
    end
end)

test('private identities still detect corrupted generation with a reused native ID',function()
    for _,corruption in ipairs({'key','edition','rng'}) do
        local c=fixture('RELOADED_CORRUPT','c_fool'); G.GAME.last_tarot_planet='c_pluto'
        G.jokers.cards[1].sort_id=c.sort_id+1
        O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
        O.consumable_validator=dofile(ORACLE_TEST_ROOT..'/debug/consumable_validator.lua')(O); O.consumable_validator.install()
        G.consumeables.cards={}; G.CONTROLLER.locks.use=true
        c:use_consumeable(G.consumeables)
        G.E_MANAGER:add_event({func=function()
            local created=assert(G.consumeables.cards[1])
            if corruption=='key' then created:set_ability(G.P_CENTERS.c_mars)
            elseif corruption=='edition' then created:set_edition('e_negative')
            else G.GAME.pseudorandom.unexpected=0.125 end
            G.CONTROLLER.locks.use=nil; return true
        end})
        drain()
        assert(O.validator.counts.MISMATCH==1 and O.prediction_fault,'lost '..corruption..' detection')
        cases=cases+1
    end
end)

test('native consumable page caches a repeated view and updates when highlighted target changes',function()
    local c=fixture('CONSUME_UI','c_cryptid')
    local colour={1,1,1,1}; G.C=setmetatable({UI=setmetatable({},{__index=function() return colour end})},{__index=function() return colour end})
    G.UIT={ROOT=1,R=2,C=3,T=4,O=5,B=6}
    local preview,predict=O.preview_card.area,O.engine.predict
    O.preview_card.area=function(cards) return {n=G.UIT.O,config={object={cards=cards}}} end
    local calls=0; O.engine.predict=function(...) calls=calls+1; return predict(...) end
    O.consumables_ui.cache=nil
    local before=D.encode(G.GAME)
    local random,seed=math.random,math.randomseed
    math.random=function() error('live RNG from UI') end; math.randomseed=math.random
    assert(O.consumables_ui.definition().n==G.UIT.ROOT); O.consumables_ui.definition(); assert(calls==1)
    G.hand.highlighted={G.hand.cards[2]}; O.consumables_ui.definition(); assert(calls==2)
    eq(D.encode(G.GAME),before)
    math.random=random; math.randomseed=seed; O.preview_card.area=preview; O.engine.predict=predict
    local change={before={front='S_K',key='m_steel'},after={front='S_A',key='m_mult',base={id=13},ability={h_x_mult=1.5,mult=0,perma_bonus=30}}}
    local encoded=D.encode(change)
    local rendered=O.consumables_ui.changed_preview(change,'c_empress')
    assert(rendered.base==nil and rendered.ability.mult==nil and rendered.ability.h_x_mult==nil and rendered.ability.perma_bonus==30)
    eq(D.encode(change),encoded,'preview source preserved')
    assert(O.consumables_ui.changed_preview(change,'c_death').ability.h_x_mult==1.5,'Death preserves copied ability')
end)
print(string.format('CONSUMABLES: %d tests passed; %d native use scenarios',passed,cases))
ORACLE_CONSUMABLE_FIXTURE=fixture
ORACLE_CONSUMABLE_DRAIN=drain
