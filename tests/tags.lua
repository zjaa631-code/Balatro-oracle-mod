local O,D=ORACLE,ORACLE.data
-- The local Lovely dump can include Handy's animation-only level_up_hand
-- patch. Its optional UI shortcut is disabled in this detached native test.
Handy = Handy or {animation_skip={should_skip_messages=function() return false end,
    mute_ease_dollars=0},
    regular_keybinds={on_shop_loaded=function() end}, ARGS={}}
local passed,count=0,0
local function eq(a,b,label) assert(D.encode(a)==D.encode(b),(label or '')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
local function test(name,fn) if ORACLE_FIXTURES_ONLY then return end; ORACLE_TEST_CASE=name; fn(); passed=passed+1; print('PASS '..name) end
Tag={}
function Tag:yep(_,_,fn) G.E_MANAGER:add_event(Event({func=fn})) end
function Tag:nope() self.noped=true end
function Tag:juice_up() end
dofile(ORACLE_TEST_SOURCE..'/tag_truth.lua')
local apply,yep,getui=Tag.apply_to_run,Tag.yep,Tag.get_uibox_table
local actual_shop=create_card_for_shop
local native_ability=Card.set_ability
function Card:set_ability(...) local r=native_ability(self,...); self.states={visible=true}; return r end
function Card:set_edition(e)
    if type(e)=='string' then self.edition={key=e,[e:sub(3)]=true}
    elseif e then for k,v in pairs(e) do if v then self.edition={key='e_'..k,[k]=true} end end
    else self.edition=nil end
end
function update_hand_text() end
function delay() end
function play_sound() end
Event=function(e) return e end
local events
local function drain()
    local n=0
    while #events>0 do
        local event=table.remove(events,1); n=n+1; assert(n<1000,'event loop')
        if event.func and event.func()==false then events[#events+1]=event end
    end
end
local function fixture(seed,ante)
    ORACLE_PHASE3_FIXTURE(seed or 'TAGS',ante or 3)
    create_card=ORACLE_TRUTH_CREATE_CARD; create_card_for_shop=actual_shop
    Tag.apply_to_run=apply; Tag.yep=yep; Tag.get_uibox_table=getui
    SMODS.Tags={}; SMODS.calculate_context=function() return {} end
    SMODS.Scoring_Parameter={obj_buffer={}}; SMODS.Scoring_Parameters={}; SMODS.displaying_scoring=nil
    O.controller=dofile(ORACLE_TEST_ROOT..'/controller.lua')(O)
    O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
    O.tag_prediction=dofile(ORACLE_TEST_ROOT..'/prediction/tags.lua')(O)
    O.tag_ui=dofile(ORACLE_TEST_ROOT..'/ui/tags.lua')(O)
    O.status={issues={}}; O.config.validate_predictions=true; O.config.enabled=true
    G.GAME.blind_on_deck='Small'
    G.C={RED={},GREEN={},MONEY={},DARK_EDITION={},UI={TEXT_DARK={}},ORANGE={}}
    events={}; G.E_MANAGER={add_event=function(_,e) events[#events+1]=e end}
    for _,h in pairs(G.GAME.hands) do h.level=4; h.chips=10; h.mult=1 end
    G.GAME.orbital_choices={[G.GAME.round_resets.ante]={Small='Pair',Big='High Card'}}
end
local function tag(key,blind)
    local proto=G.P_TAGS[key]
    return setmetatable({key=key,name=proto.name,config=D.copy(proto.config),ability={blind_type=blind},ID=key}, {__index=Tag})
end
local function expected_actual(key,slots)
    ORACLE_TEST_CONTEXT.tag=key; ORACLE_TEST_CONTEXT.slots=slots or 2
    local t=tag(key,'Small')
    G.GAME.shop.joker_max=slots or 2
    local s=O.tag_prediction.capture(key,'Small',t.ability)
    local before=D.encode(O.shop_snapshot.capture(G,SMODS,true))
    local expected,details=O.ante_prediction.run(s,O.tag_prediction.batch)
    eq(D.encode(O.shop_snapshot.capture(G,SMODS,true)),before,'readonly')
    G.GAME.tags[#G.GAME.tags+1]=t
    local actual={}
    for i=1,G.GAME.shop.joker_max do actual[i]=actual_shop(G.shop_jokers) end
    drain()
    local records={}; for i,c in ipairs(actual) do records[i]=O.shop_snapshot.card(c) end
    eq(records,expected.cards,key); eq(G.GAME.pseudorandom,details.rng_after,key..' RNG')
    count=count+#actual
    return expected
end
test('all six Tag effects match native shop/Tag/create_card across seed sweep and 2/3/4 slots',function()
    for seed=ORACLE_TEST_START or 1,(ORACLE_TEST_START or 1)+(ORACLE_TEST_SAMPLES and ORACLE_TEST_SAMPLES.tags or 100)-1 do
        for _,key in ipairs({'tag_uncommon','tag_rare','tag_foil','tag_holo','tag_polychrome','tag_negative'}) do
            fixture('TAG'..seed,seed%7+1)
            G.GAME.modifiers.enable_eternals_in_shop=true
            G.GAME.modifiers.enable_perishables_in_shop=true
            G.GAME.modifiers.enable_rentals_in_shop=true
            G.GAME.edition_rate=seed%4+1
            expected_actual(key,2+seed%3)
        end
    end
end)
test('queued rarity and edition tags respect immediate versus deferred modification order',function()
    for seed=1,35 do
        fixture('QUEUE'..seed)
        G.GAME.tags={tag('tag_negative'),tag('tag_uncommon'),tag('tag_holo')}
        expected_actual('tag_rare',4)
        fixture('DEFER'..seed)
        G.GAME.tags={tag('tag_foil')}
        expected_actual('tag_polychrome',4)
    end
end)
test('Showman, owned Jokers, rare exhaustion, unlocks, bans, gates and resamples',function()
    for seed=1,45 do
        fixture('POOLTAG'..seed)
        for i,c in ipairs(G.P_JOKER_RARITY_POOLS[2]) do
            if i%3==0 then G.GAME.used_jokers[c.key]=true end
            if i%7==0 then c.unlocked=false end
            if i%11==0 then G.GAME.banned_keys[c.key]=true end
        end
        if seed%2==0 then G.jokers.cards={{config={center=G.P_CENTERS.j_ring_master}}}; G.TEST_SHOWMAN=true end
        expected_actual('tag_uncommon',4)
    end
    for _,showman in ipairs({false,true}) do
        fixture('RAREFULL')
        for _,c in ipairs(G.P_JOKER_RARITY_POOLS[3]) do G.jokers.cards[#G.jokers.cards+1]={config={center=c}} end
        if showman then G.jokers.cards[#G.jokers.cards+1]={config={center=G.P_CENTERS.j_ring_master}}; G.TEST_SHOWMAN=true end
        local batch=expected_actual('tag_rare'); assert(batch.results[1].nope)
    end
end)
test('Orbital uses native visible hand selection and stored choices, including secret hands and current levels',function()
    for seed=1,60 do
        fixture('ORBIT'..seed)
        for _,k in ipairs({'Five of a Kind','Flush House','Flush Five'}) do
            SMODS.PokerHands[k]={}; G.GAME.hands[k]={visible=seed%2==0,played=seed%2==0 and 1 or 0,level=seed, chips=10,mult=1}
        end
        -- Actual Tag constructor fallback chooses from native visibility rules.
        local t=tag('tag_orbital'); t.ability.orbital_hand='['..localize('k_poker_hand')..']'
        t:set_ability()
        assert(G.GAME.hands[t.ability.orbital_hand].visible)
        G.GAME.orbital_choices[G.GAME.round_resets.ante].Small=t.ability.orbital_hand
        t.ability.blind_type='Small'
        local before=D.copy(G.GAME.pseudorandom)
        local r=O.tag_prediction.get(t.key,'Small',t.ability)
        assert(r.status=='observed' and r.hand_key==t.ability.orbital_hand)
        local current=G.GAME.hands[r.hand_key].level
        t:apply_to_run({type='immediate'}); drain()
        eq(G.GAME.hands[r.hand_key].level,r.resulting_level); assert(r.current_level==current)
        eq(before,G.GAME.pseudorandom,'Orbital observed consumes no RNG')
        G.GAME.hands[r.hand_key].level=20
        local updated=O.tag_prediction.get(t.key,'Small',t.ability)
        assert(updated.current_level==20 and updated.resulting_level==23)
    end
end)
test('cache, repeated hover and branch simulation preserve live keyed and global RNG',function()
    fixture('CACHE')
    local before=D.encode(G.GAME)
    math.randomseed(514); local expected=math.random(); math.randomseed(514)
    local first=O.tag_prediction.get('tag_rare','Small')
    for i=1,30 do assert(O.tag_prediction.get('tag_rare','Small')==first) end
    assert(O.tag_prediction.computations==1)
    eq(D.encode(G.GAME),before); assert(math.random()==expected)
    G.GAME.pseudorandom.Joker3rta3=0.3
    assert(O.tag_prediction.get('tag_rare','Small')~=first)
    local big=O.tag_prediction.get('tag_rare','Big'); assert(big.shop_ante==4)
    G.GAME.tags={tag('tag_double')}
    local doubled=O.tag_prediction.get('tag_orbital','Small')
    assert(#doubled.expanded_tags==2 and doubled.effects[2].resulting_level==10)
    G.GAME.tags={}; SMODS.PokerHands.Pair.visible=function() error('must not invoke') end
    assert(O.tag_prediction.get('tag_orbital','Small').status=='unavailable')
end)
test('pre-skip and effect validation use actual tags and compare after edition callbacks',function()
    for _,key in ipairs({'tag_rare','tag_uncommon','tag_negative','tag_orbital'}) do
        fixture('VALIDTAG'..key)
        G.GAME.joker_rate=100; G.GAME.planet_rate=0; G.GAME.tarot_rate=0; G.GAME.spectral_rate=0
        local t=tag(key,'Small'); if key=='tag_orbital' then t.ability.orbital_hand='Pair' end
        G.FUNCS.skip_blind=function() G.GAME.tags={t}; if key=='tag_orbital' then t:apply_to_run({type='immediate'}) end end
        O.tag_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_validator.lua')(O); O.tag_validator.install()
        local e={UIBox={get_UIE_by_ID=function() return {config={ref_table=t}} end}}
        G.FUNCS.skip_blind(e)
        if key~='tag_orbital' then for i=1,2 do create_card_for_shop(G.shop_jokers) end end
        drain()
        assert(O.validator.counts.MISMATCH==0, key)
        assert(O.validator.counts.MATCH>0,key..' missing effect MATCH')
        assert(#O.tag_validator.records>0 and O.tag_validator.records[#O.tag_validator.records].status=='MATCH',key..' pre-skip')
    end
end)
test('legitimate state changes retain pre-skip expected versus actual as CONDITION_CHANGED',function()
    fixture('CHANGEDTAG')
    local t=tag('tag_rare','Small')
    G.FUNCS.skip_blind=function() G.GAME.tags={t} end
    O.tag_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_validator.lua')(O); O.tag_validator.install()
    G.FUNCS.skip_blind({UIBox={get_UIE_by_ID=function() return {config={ref_table=t}} end}})
    G.GAME.pseudorandom.Joker3rta3=0.1234
    create_card_for_shop(G.shop_jokers); drain()
    assert(O.tag_validator.records[1].status=='CONDITION_CHANGED')
    assert(not O.prediction_fault and O.validator.counts.MISMATCH==0)
end)
test('native Tag tooltip remains the body and Oracle appends localized outcome without RNG draws',function()
    fixture('UITAG')
    local old=generate_card_ui
    generate_card_ui=function() return {main={{{native=true}}}} end
    G.UIT={T=1}; G.C={UI={TEXT_DARK={}},ORANGE={}}
    local t=tag('tag_orbital','Small'); t.ability.orbital_hand='Pair'; t.tag_sprite={}
    O.tag_ui.install()
    local before=D.encode(G.GAME)
    for i=1,20 do
        t:get_uibox_table()
        assert(t.tag_sprite.ability_UIBox_table.main[1][1].native)
        assert(#t.tag_sprite.ability_UIBox_table.main==5)
    end
    eq(before,D.encode(G.GAME)); generate_card_ui=old
end)
test('Orbital reads actual tag levels; harmless queued Joker tags do not block it',function()
    fixture('ORBITALCONFIG')
    G.GAME.tags={tag('tag_rare')}
    local r=O.tag_prediction.get('tag_orbital','Small',{orbital_hand='Pair'},{levels=6})
    assert(r.current_level==4 and r.resulting_level==10 and r.levels_added==6)
end)
test('Ante summaries reuse native card previews with the predicted edition',function()
    fixture('ANTE_TAG_CARD')
    local old_preview,old_get=O.preview_card.area,O.tag_prediction.get
    local received
    O.preview_card.area=function(cards,scale) received=cards[1]; assert(scale==0.5); return {n='native_preview'} end
    O.tag_prediction.get=function() return {type='joker',status='experimental',card={key='j_blueprint',edition='e_negative'},shop_ante=3} end
    G.UIT={R=1,C=2,T=3}
    O.tag_ui.summary('tag_negative','Small',3)
    assert(received.key=='j_blueprint' and received.edition=='e_negative')
    O.preview_card.area=old_preview; O.tag_prediction.get=old_get
end)
test('Rare NOPE validates without false mismatch and a real disagreement closes the gate',function()
    fixture('NOPE_VALIDATOR')
    for _,c in ipairs(G.P_JOKER_RARITY_POOLS[3]) do G.jokers.cards[#G.jokers.cards+1]={config={center=c}} end
    local t=tag('tag_rare','Small')
    G.FUNCS.skip_blind=function() G.GAME.tags={t} end
    O.tag_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_validator.lua')(O); O.tag_validator.install()
    G.FUNCS.skip_blind({UIBox={get_UIE_by_ID=function() return {config={ref_table=t}} end}})
    create_card_for_shop(G.shop_jokers); drain()
    assert(O.tag_validator.records[1].status=='MATCH' and not O.prediction_fault)
    fixture('MISMATCH_VALIDATOR')
    t=tag('tag_rare','Small'); G.FUNCS.skip_blind=function() G.GAME.tags={t} end
    O.tag_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_validator.lua')(O); O.tag_validator.install()
    G.FUNCS.skip_blind({UIBox={get_UIE_by_ID=function() return {config={ref_table=t}} end}})
    O.tag_validator.pending[t].result.card.key='test_injected_wrong_expected'
    create_card_for_shop(G.shop_jokers); drain()
    local report=O.tag_validator.records[1]
    assert(report.status=='MISMATCH' and O.prediction_fault)
    assert(report.input.game.pseudorandom.seed=='MISMATCH_VALIDATOR')
    assert(report.input.shop.rarity_pools[3] and report.details.prediction.details.trace)
    assert(report.details.prediction.details.pool[1])
end)
print('TAGS: '..passed..' tests passed; '..count..' shop card comparisons')
ORACLE_TAG_FIXTURE=fixture
ORACLE_TAG_FACTORY=tag
ORACLE_TAG_DRAIN=drain
