local O,D=ORACLE,ORACLE.data
local passed,cases=0,0
local function eq(a,b,label) assert(D.encode(a)==D.encode(b),(label or '')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
local function test(name,fn) if ORACLE_PACK_OPENING_ONLY then return end; ORACLE_TEST_CASE=name; fn(); passed=passed+1; print('PASS '..name) end
local function noop() end
local original_probability,original_seed,original_element,original_random=pseudorandom and SMODS.pseudorandom_probability,pseudoseed,pseudorandom_element,pseudorandom
local native_create=create_card
local drain=ORACLE_CONSUMABLE_DRAIN
local function fixture(seed,key)
    pseudoseed=original_seed; pseudorandom_element=original_element; pseudorandom=original_random
    ORACLE_CONSUMABLE_FIXTURE(seed,'c_wheel_of_fortune')
    ORACLE_TEST_CONTEXT.joker=key
    O.jokers=dofile(ORACLE_TEST_ROOT..'/prediction/jokers.lua')(O)
    O.engine=dofile(ORACLE_TEST_ROOT..'/prediction/engine.lua')(O)
    O.jokers_ui=dofile(ORACLE_TEST_ROOT..'/ui/jokers.lua')(O)
    G.P_CARDS.empty=nil
    local c=Card(0,0,1,1.4,key:sub(1,2)=='m_' and G.P_CARDS.S_7 or nil,G.P_CENTERS[key],{})
    if key:sub(1,2)=='m_' then c.playing_card=90; G.playing_cards[#G.playing_cards+1]=c
    else G.jokers.cards={c,G.jokers.cards[2],G.jokers.cards[3]} end
    G.consumeables.cards={}; G.GAME.consumeable_buffer=0; G.GAME.joker_buffer=0; G.GAME.dollar_buffer=0
    G.GAME.current_round.idol_card={rank='7',suit='Diamonds',id=7}
    G.GAME.current_round.mail_card={rank='7',id=7}
    G.GAME.current_round.ancient_card={suit='Diamonds'}
    G.GAME.current_round.castle_card={suit='Diamonds'}
    G.GAME.current_round.hands_played=0
    G.P_CENTER_POOLS.Seal={}; G.P_SEALS={}
    for _,key in ipairs({'Gold','Red','Blue','Purple'}) do local seal={key=key,weight=10}; G.P_CENTER_POOLS.Seal[#G.P_CENTER_POOLS.Seal+1]=seal; G.P_SEALS[key]=seal end
    SMODS.Enhancement={take_ownership=function(_,key,t) for k,v in pairs(t) do G.P_CENTERS['m_'..key][k]=v end end}
    SMODS.has_no_suit=function(c) return c.config.center.key=='m_stone' end
    SMODS.has_no_rank=SMODS.has_no_suit
    SMODS.destroy_cards=function(card) card.test_destroyed=true end
    SMODS.scale_card=noop; SMODS.reset_card=noop; SMODS.calculate_effect=noop
    SMODS.post_prob={}; G.GAME.blind={debuff_card=noop}
    card_eval_status_text=noop; juice_card_until=noop; save_run=noop; draw_card=noop
    G.hand.sort=noop; G.play.emplace=function(self,c) self.cards[#self.cards+1]=c end
    localize=function(x) return type(x)=='table' and tostring(x.vars and x.vars[1] or x.key) or x end
    function Card:get_id() return self.base.id end
    function Card:is_face() return self.base.value=='King' or self.base.value=='Queen' or self.base.value=='Jack' end
    function Card:is_suit(suit) return self.base.suit==suit end
    dofile(ORACLE_TEST_SOURCE..'/joker_truth.lua')
    if key=='j_invisible' then c.ability.invis_rounds=c.ability.extra end
    if key=='j_perkeo' then
        for _,k in ipairs({'c_hermit','c_pluto'}) do G.consumeables:emplace(Card(0,0,1,1.4,nil,G.P_CENTERS[k],{})) end
    end
    return c
end
local function predict(c,request)
    local s=O.jokers.capture(G,SMODS,c); local before=D.encode(s)
    math.randomseed(712); local draw=math.random(); math.randomseed(712)
    local r,details=O.engine.predict('joker',s,request)
    assert(draw==math.random(),'preview changed global RNG')
    eq(s,O.jokers.capture(G,SMODS,c),'preview changed live state')
    eq(D.encode(s),before,'preview changed input')
    return r,details
end
local function context(c)
    local key=c.config.center.key
    if key=='j_space' then return {before=true} end
    if key=='j_gros_michel' or key=='j_cavendish' or key=='j_todo_list' then return {end_of_round=true} end
    if key=='j_hallucination' then return {open_booster=true} end
    if key=='j_invisible' then return {selling_self=true} end
    if key=='j_perkeo' then return {ending_shop=true} end
    if key=='j_certificate' then return {first_hand_drawn=true} end
    if key=='j_madness' or key=='j_riff_raff' or key=='j_cartomancer' or key=='j_marble' then return {setting_blind=true,blind={boss=false}} end
    local other=G.hand.cards[2]
    if key=='j_8_ball' then other.base.id=8 end
    if key=='j_sixth_sense' then other.base.id=6; return {destroying_card=other,full_hand={other}} end
    if key=='j_bloodstone' or key=='j_business' or key=='j_reserved_parking' or key=='j_8_ball' then
        return {individual=true,cardarea=key=='j_reserved_parking' and G.hand or G.play,other_card=other,scoring_hand={other}}
    end
    G.GAME.dollars=0; other.base.id=14
    return {joker_main=true,cardarea=G.jokers,full_hand={other},scoring_hand={other},poker_hands={Straight={true},['Straight Flush']={true}}}
end
local function actual(c,ctx)
    local result
    if c.config.center.key=='m_lucky' then result={mult=c:get_chip_mult(),money=c:get_p_dollars()}
    elseif c.config.center.key=='m_glass' then result=G.P_CENTERS.m_glass:calculate(c,{destroy_card=c,cardarea=G.play})
    else result=c:calculate_joker(ctx or context(c)) end
    if type(result)=='table' and result.extra and result.extra.func then result.extra.func() end
    drain(); return result
end
ORACLE_JOKER_FIXTURE=fixture
ORACLE_JOKER_ACTUAL=actual
local function creations(before)
    local found={}; for _,list in ipairs({G.jokers.cards,G.consumeables.cards,G.playing_cards}) do for _,c in ipairs(list) do
        if not before[c.sort_id] then found[#found+1]=O.consumables.simple(O.consumables.card(c)) end
    end end
    return found
end
local function ids()
    local seen={}; for _,list in ipairs({G.jokers.cards,G.consumeables.cards,G.playing_cards}) do for _,c in ipairs(list) do seen[c.sort_id]=true end end
    return seen
end
test('native Joker probability branches, Lucky dual hits and Glass match across seeds and Oops factors',function()
    for seed=1,80 do
        for _,key in ipairs({'j_space','j_gros_michel','j_cavendish','j_bloodstone','j_business','j_reserved_parking','j_8_ball','j_hallucination','m_lucky','m_glass'}) do
            local c=fixture('JOKER_CHANCE_'..seed,key)
            G.GAME.probabilities.normal=2^(seed%3)
            local r,details=predict(c); actual(c)
            eq(#SMODS.post_prob,#r.checks,key..' checks')
            for i,check in ipairs(r.checks) do eq(SMODS.post_prob[i].result,check.success,key..' result') end
            eq(G.GAME.pseudorandom,details.rng_after,key..' RNG')
            cases=cases+1
        end
    end
end)
test('native round targets preserve duplicate-card weights, stone exclusions and current-suit exclusion',function()
    for seed=1,80 do
        for key,field in pairs(O.jokers.resets) do
            local c=fixture('JOKER_RESET_'..seed,key)
            if seed%3==0 then for _,v in ipairs(G.playing_cards) do v:set_ability(G.P_CENTERS.m_stone) end end
            if seed%4==0 then G.playing_cards={} end
            local r,details=predict(c,{ante=G.GAME.round_resets.ante+seed%2})
            G.GAME.round_resets.ante=G.GAME.round_resets.ante+seed%2
            _G[({j_idol='reset_idol_card',j_mail='reset_mail_rank',j_ancient='reset_ancient_card',j_castle='reset_castle_card'})[key]]()
            eq(G.GAME.current_round[field],r.reset,key); eq(G.GAME.pseudorandom,details.rng_after,key..' RNG')
            cases=cases+1
        end
    end
end)
test('native random targets, copy editions, To Do exclusion and Misprint match',function()
    for seed=1,50 do
        for _,key in ipairs({'j_invisible','j_perkeo','j_madness','j_todo_list','j_misprint','j_marble','j_certificate'}) do
            local c=fixture('JOKER_TARGET_'..seed,key)
            G.jokers.cards[2]:set_edition('e_negative')
            if seed%2==0 then G.jokers.cards[2].ability.eternal=false end
            local r,details=predict(c); local before=ids(); local target_live
            for _,v in ipairs(G.jokers.cards) do if r.target and O.consumables.identity(v)==r.target.id then target_live=v end end
            local result=actual(c)
            if r.hand then eq(c.ability.to_do_poker_hand,r.hand,'To Do hand') end
            if r.mult then eq(result.mult_mod,r.mult,'Misprint') end
            local expected={}; for _,v in ipairs(r.created) do expected[#expected+1]=O.consumables.simple(v) end
            eq(creations(before),expected,key..' created')
            if key=='j_madness' and r.target then
                assert(target_live and target_live.getting_sliced,'Madness target')
            end
            eq(G.GAME.pseudorandom,details.rng_after,key..' RNG'); cases=cases+1
        end
    end
end)
test('native Joker creation callbacks respect buffers, Common rarity and current pools',function()
    for seed=1,40 do
        for _,key in ipairs({'j_riff_raff','j_cartomancer','j_sixth_sense','j_vagabond','j_superposition','j_seance'}) do
            local c=fixture('JOKER_CREATE_'..seed,key)
            G.jokers.config.card_limit=3+seed%3; G.consumeables.config.card_limit=seed%3
            if seed%5==0 then G.GAME.joker_buffer=1; G.GAME.consumeable_buffer=1 end
            local ctx=context(c); local r,details=predict(c); local before=ids(); actual(c,ctx)
            local expected={}; for _,v in ipairs(r.created) do expected[#expected+1]=O.consumables.simple(v) end
            eq(creations(before),expected,key..' created'); eq(G.GAME.pseudorandom,details.rng_after,key..' RNG'); cases=cases+1
        end
    end
end)
test('native live validation matches and detects probability, target and generation corruption',function()
    for _,key in ipairs({'j_space','j_invisible','j_perkeo','j_todo_list','j_riff_raff','j_idol','j_certificate','j_misprint'}) do
        local c=fixture('JOKER_VALIDATE',key)
        O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
        O.joker_validator=dofile(ORACLE_TEST_ROOT..'/debug/joker_validator.lua')(O); O.joker_validator.install()
        if key=='j_idol' then reset_idol_card() else actual(c) end
        assert(O.validator.counts.MATCH>0 and O.validator.counts.MISMATCH==0 and not O.prediction_fault,key..' validation')
    end
    local c=fixture('JOKER_FAULT','j_space')
    local native=SMODS.pseudorandom_probability
    SMODS.pseudorandom_probability=function(...) return not native(...) end
    O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
    O.joker_validator=dofile(ORACLE_TEST_ROOT..'/debug/joker_validator.lua')(O); O.joker_validator.install()
    actual(c); assert(O.validator.counts.MISMATCH==1 and O.prediction_fault)
    c=fixture('JOKER_TARGET_FAULT','j_invisible')
    local element=pseudorandom_element
    pseudorandom_element=function(pool,seed,...)
        local v,i=element(pool,seed,...)
        if #pool==2 then return pool[v==pool[1] and 2 or 1],i end
        return v,i
    end
    O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
    O.joker_validator=dofile(ORACLE_TEST_ROOT..'/debug/joker_validator.lua')(O); O.joker_validator.install()
    actual(c); assert(O.validator.counts.MISMATCH>0 and O.prediction_fault)
    c=fixture('JOKER_CREATE_FAULT','j_cartomancer')
    local create=create_card
    create_card=function(...) local card=create(...); card.ability.rental=true; return card end
    O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
    O.joker_validator=dofile(ORACLE_TEST_ROOT..'/debug/joker_validator.lua')(O); O.joker_validator.install()
    actual(c); assert(O.validator.counts.MISMATCH>0 and O.prediction_fault)
end)
test('readiness, empty pools, active Oops, hidden hands and sliced cards fail or advance exactly as native',function()
    for _,key in ipairs({'j_invisible','j_perkeo','j_madness','j_riff_raff','j_hallucination'}) do
        local c=fixture('JOKER_EMPTY',key)
        if key=='j_invisible' then c.ability.invis_rounds=0
        elseif key=='j_perkeo' then G.consumeables.cards={}
        elseif key=='j_madness' then for _,v in ipairs(G.jokers.cards) do v.ability.eternal=true end
        elseif key=='j_riff_raff' then G.jokers.config.card_limit=#G.jokers.cards
        else G.consumeables.config.card_limit=0 end
        local before=D.copy(G.GAME.pseudorandom); local r,details=predict(c)
        assert(r.inactive); actual(c); eq(before,G.GAME.pseudorandom); eq(details.rng_after,before); cases=cases+1
    end
    for count=0,3 do
        local c=fixture('JOKER_OOPS_'..count,'j_space')
        for i=1,count do local v=Card(0,0,1,1.4,nil,G.P_CENTERS.j_oops,{}); G.jokers:emplace(v); if i==3 then v.debuff=true end end
        G.GAME.probabilities.normal=2^math.min(count,2); c.ability.extra=7
        local r,details=predict(c); actual(c)
        eq(SMODS.post_prob[1].result,r.checks[1].success); eq(G.GAME.pseudorandom,details.rng_after); cases=cases+1
    end
    local c=fixture('JOKER_HIDDEN','j_todo_list')
    G.GAME.hands['Flush Five'].visible=true; G.GAME.hands['Flush Five'].played=1
    c.ability.to_do_poker_hand='Pair'
    local r,details=predict(c); actual(c); eq(c.ability.to_do_poker_hand,r.hand); eq(G.GAME.pseudorandom,details.rng_after)
    assert(r.hand~='Pair'); cases=cases+1
    c=fixture('JOKER_DEBUFF','j_space'); c.debuff=true
    assert(not pcall(predict,c)); c.debuff=false; c.getting_sliced=true; assert(not pcall(predict,c))
    c=fixture('JOKER_DEBUFF_RESET','j_idol'); c.debuff=true
    assert(predict(c).reset,'global reset remains active when Joker is debuffed')
end)
test('repeated next-trigger previews are cached, localized and use native card areas',function()
    local c=fixture('JOKER_UI','j_space')
    G.UIT={ROOT=1,R=2,C=3,T=4,O=5,B=6}
    local colour={}; G.C=setmetatable({UI=setmetatable({},{__index=function() return colour end})},{__index=function() return colour end})
    local preview=O.preview_card.area; O.preview_card.area=function(cards) return {n=G.UIT.R,config={},nodes={}} end
    local calls=0; local original=O.engine.predict
    O.engine.predict=function(...) calls=calls+1; return original(...) end
    local before=D.encode(G.GAME.pseudorandom)
    O.jokers_ui.definition(); O.jokers_ui.definition(); assert(calls==1)
    eq(D.encode(G.GAME.pseudorandom),before,'UI RNG')
    pseudorandom('space'); O.jokers_ui.definition(); assert(calls==2)
    O.engine.predict=original; O.preview_card.area=preview
end)
test('Invisible Joker hover matches native sale copies across seeds, editions and candidate orders',function()
    for seed=1,60 do
        local c=fixture('INVISIBLE_HOVER_'..seed,'j_invisible'); c.area=G.jokers
        G.jokers.cards[2]:set_edition(seed%2==0 and 'e_negative' or 'e_polychrome')
        G.jokers.cards[3]:set_edition('e_foil')
        if seed%3==0 then G.jokers.cards[2],G.jokers.cards[3]=G.jokers.cards[3],G.jokers.cards[2] end
        O.quick=dofile(ORACLE_TEST_ROOT..'/prediction/quick.lua')(O)
        eq(O.quick_ui.kind(c),'joker'); O.config.event_depth=20
        local s=O.jokers.capture(G,SMODS,c)
        math.randomseed(641); local draw=math.random(); math.randomseed(641)
        local r=O.quick.get('joker',c); local lines=O.quick_ui.lines('joker',c)
        eq(math.random(),draw,'hover global RNG'); eq(O.jokers.capture(G,SMODS,c),s,'hover live state')
        assert(r.target.id~=O.consumables.identity(c) and #r.created==1 and not r.rows)
        eq(#lines,4,'one target and one resulting copy')
        eq(lines[3],O.text.get('oracle_target')..': '..O.tag_ui.reward_name(r.target))
        eq(lines[4],O.text.get('oracle_created')..': '..O.tag_ui.reward_name(r.created[1]))
        eq(O.quick.count,1,'repeated hover cached')
        if r.target.edition=='e_negative' then assert(not r.created[1].edition) end
        local _,details=O.engine.predict('joker',s); local before=ids(); actual(c)
        eq(creations(before),{O.consumables.simple(r.created[1])},'native sale copy')
        eq(G.GAME.pseudorandom,details.rng_after,'native sale RNG'); cases=cases+1
    end
    O.config.event_depth=5
end)
test('Invisible hover refreshes readiness, RNG and owned pool and excludes shop and collection cards',function()
    local c=fixture('INVISIBLE_HOVER_CACHE','j_invisible'); c.area=G.jokers
    O.quick=dofile(ORACLE_TEST_ROOT..'/prediction/quick.lua')(O)
    c.ability.invis_rounds=0
    local before=D.copy(G.GAME.pseudorandom); local r=O.quick.get('joker',c)
    eq(r.inactive,'oracle_joker_not_ready'); eq(#r.created,0); eq(G.GAME.pseudorandom,before)
    assert(table.concat(O.quick_ui.lines('joker',c),'\n'):find(O.text.get(r.inactive),1,true))
    c.ability.invis_rounds=c.ability.extra
    r=O.quick.get('joker',c); assert(r.target); eq(O.quick.count,2)
    pseudorandom('invisible'); O.quick.get('joker',c); eq(O.quick.count,3)
    G.jokers.cards={c}; r=O.quick.get('joker',c); eq(r.inactive,'oracle_joker_no_target'); eq(O.quick.count,4)
    c.area=G.shop_jokers; eq(O.quick_ui.kind(c),nil)
    c.area=nil; eq(O.quick_ui.kind(c),nil)
    c.area=G.jokers; c.oracle_preview=true; eq(O.quick_ui.kind(c),nil); c.oracle_preview=nil
    O.config.enabled=false; eq(O.quick_ui.kind(c),nil); O.config.enabled=true
end)
test('generation and copy hover matches native triggers, names, seals and RNG across seeds',function()
    for seed=1,20 do
        for _,key in ipairs({'j_cartomancer','j_vagabond','j_sixth_sense','j_seance','j_perkeo',
            'j_certificate','j_riff_raff','j_superposition','j_marble','j_todo_list'}) do
            local c=fixture('GENERATOR_HOVER_'..seed,key); c.area=G.jokers
            O.quick=dofile(ORACLE_TEST_ROOT..'/prediction/quick.lua')(O)
            eq(O.quick_ui.kind(c),'joker')
            local ctx=context(c); local snapshot=O.jokers.capture(G,SMODS,c)
            local r=O.quick.get('joker',c); local lines=O.quick_ui.lines('joker',c)
            local text=table.concat(lines,'\n')
            assert(text:find(O.text.get(r.condition),1,true),'trigger condition missing')
            for _,created in ipairs(r.created) do
                assert(text:find(O.tag_ui.reward_name(created),1,true),'created card or attributes missing')
            end
            if r.target then assert(text:find(O.tag_ui.reward_name(r.target),1,true),'copy target missing') end
            if r.hand then assert(text:find(localize(r.hand,'poker_hands'),1,true)) end
            eq(O.quick.count,1,'repeat hover cached'); eq(O.jokers.capture(G,SMODS,c),snapshot,'hover is read-only')
            local _,details=O.engine.predict('joker',snapshot); local before=ids(); actual(c,ctx)
            local expected={}; for _,v in ipairs(r.created) do expected[#expected+1]=O.consumables.simple(v) end
            eq(creations(before),expected,'native created cards'); eq(G.GAME.pseudorandom,details.rng_after,'native RNG')
            if r.hand then eq(c.ability.to_do_poker_hand,r.hand) end
            cases=cases+1
        end
    end
end)

test('target hover uses next settlement Ante, current target and native weighted deck choices',function()
    local states={
        {{Small='Current',Big='Upcoming',Boss='Upcoming'},0},
        {{Small='Defeated',Big='Upcoming',Boss='Upcoming'},0},
        {{Small='Skipped',Big='Select',Boss='Upcoming'},0},
        {{Small='Defeated',Big='Defeated',Boss='Upcoming'},1},
        {{Small='Skipped',Big='Skipped',Boss='Select'},1},
        {{Small='Defeated',Big='Defeated',Boss='Current'},1},
        {{Small='Defeated',Big='Defeated',Boss='Defeated'},0},
    }
    for seed=1,12 do for key,field in pairs(O.jokers.resets) do for _,case in ipairs(states) do
        local c=fixture('TARGET_HOVER_'..seed,key); c.area=G.jokers
        G.GAME.round_resets.blind_states=D.copy(case[1])
        if seed%3==0 then G.playing_cards[1]:set_ability(G.P_CENTERS.m_stone) end
        O.quick=dofile(ORACLE_TEST_ROOT..'/prediction/quick.lua')(O)
        local snapshot=O.jokers.capture(G,SMODS,c); local ante=G.GAME.round_resets.ante+case[2]
        local r=O.quick.get('joker',c); eq(r.ante,ante); eq(r.current,G.GAME.current_round[field])
        local text=table.concat(O.quick_ui.lines('joker',c),'\n')
        assert(text:find(O.quick_ui.reset_name(r.current),1,true)); assert(text:find(O.quick_ui.reset_name(r.reset),1,true))
        assert(text:find(O.text.get('oracle_reset_ante')..' '..ante,1,true))
        eq(O.quick.count,1); eq(O.jokers.capture(G,SMODS,c),snapshot,'reset hover read-only')
        local _,details=O.engine.predict('joker',snapshot,{ante=ante})
        G.GAME.round_resets.ante=ante
        _G[({j_idol='reset_idol_card',j_mail='reset_mail_rank',j_ancient='reset_ancient_card',j_castle='reset_castle_card'})[key]]()
        eq(G.GAME.current_round[field],r.reset); eq(G.GAME.pseudorandom,details.rng_after)
        if key=='j_ancient' then assert(r.reset.suit~=r.current.suit) end
        cases=cases+1
    end end end
end)

test('generator hover invalidates inventory, capacity and reset route without exposing unowned cards',function()
    local c=fixture('HOVER_INVENTORY','j_perkeo'); c.area=G.jokers
    O.quick=dofile(ORACLE_TEST_ROOT..'/prediction/quick.lua')(O)
    assert(O.quick.get('joker',c).target)
    G.consumeables.cards={}; local r=O.quick.get('joker',c)
    eq(r.inactive,'oracle_joker_no_target'); eq(O.quick.count,2)
    assert(table.concat(O.quick_ui.lines('joker',c),'\n'):find(O.text.get(r.inactive),1,true))
    c=fixture('HOVER_ROOM','j_cartomancer'); c.area=G.jokers
    O.quick=dofile(ORACLE_TEST_ROOT..'/prediction/quick.lua')(O)
    assert(#O.quick.get('joker',c).created==1)
    G.consumeables.config.card_limit=0; eq(O.quick.get('joker',c).inactive,'oracle_joker_no_room')
    c.debuff=true; assert(not pcall(O.quick.get,'joker',c)); c.debuff=false
    c.area=G.shop_jokers; eq(O.quick_ui.kind(c),nil)
    c.area=nil; eq(O.quick_ui.kind(c),nil)
    c.area=G.jokers; c.oracle_preview=true; eq(O.quick_ui.kind(c),nil)
    c=fixture('HOVER_RESET_ROUTE','j_idol'); c.area=G.jokers
    O.quick=dofile(ORACLE_TEST_ROOT..'/prediction/quick.lua')(O)
    G.GAME.round_resets.blind_states={Small='Defeated',Big='Current',Boss='Upcoming'}
    local first=O.quick.get('joker',c)
    G.GAME.round_resets.blind_states.Big='Defeated'
    local second=O.quick.get('joker',c); eq(second.ante,first.ante+1); eq(O.quick.count,2)
    G.playing_cards={}; local empty=O.quick.get('joker',c)
    eq(empty.reset.rank,'Ace'); eq(empty.reset.suit,'Spades'); eq(O.quick.count,3)
end)
print(string.format('JOKERS: %d tests passed; %d native trigger scenarios',passed,cases))
