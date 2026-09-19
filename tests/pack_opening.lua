local O,D=ORACLE,ORACLE.data
local function eq(a,b,label) assert(D.encode(a)==D.encode(b),(label or '')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
local layouts={{'j_hallucination'},{'j_blueprint','j_hallucination','j_brainstorm'},
    {'j_hallucination','j_blueprint','j_brainstorm'},{'j_blueprint','j_brainstorm','j_hallucination'},
    {'j_hallucination','j_hallucination'},{'j_oops','j_hallucination','j_brainstorm'}}
local cases,hits=0,0
ORACLE_TEST_CASE='Hallucination open-booster ordering, copies and pack candidates match native callbacks'
for seed=1,12 do for index,layout in ipairs(layouts) do
    for _,key in ipairs({'p_arcana_mega_1','p_celestial_normal_1','p_spectral_normal_1','p_standard_jumbo_1','p_buffoon_mega_1'}) do
        ORACLE_JOKER_FIXTURE('OPENING_'..seed,'j_hallucination')
        G.jokers.cards={}
        for i,jkey in ipairs(layout) do
            local card=Card(0,0,1,1.4,nil,G.P_CENTERS[jkey],{})
            if seed%4==0 and i==2 then card.debuff=true end
            G.jokers:emplace(card)
        end
        G.GAME.probabilities.normal=index==6 and 2 or 1
        G.consumeables.config.card_limit=seed%4
        G.GAME.consumeable_buffer=seed%5==0 and 1 or 0
        G.GAME.used_vouchers.v_omen_globe=seed%2==0
        SMODS.Booster={take_ownership_by_kind=function(_,kind,v)
            for _,c in ipairs(G.P_CENTER_POOLS.Booster) do if c.kind==kind then c.create_card=v.create_card end end
        end}
        dofile(ORACLE_TEST_SOURCE..'/booster_truth.lua')
        local pack=G.P_CENTERS[key]; assert(pack,key)
        local snapshot=O.pack_prediction.capture(G,SMODS); local frozen=D.encode(snapshot)
        local expected,details=O.pack_prediction.forecast(snapshot,{key=key})
        for tag,pkey in pairs(O.tag_rewards.packs) do if pkey==key then
            local from_tag,tag_trace=O.ante_prediction.run(snapshot,function(s,rng)
                local _,cards=O.tag_rewards.open(s,rng,{key=tag}); return cards
            end)
            eq(from_tag,expected,'gift pack opening'); eq(tag_trace.rng_after,details.rng_after,'gift pack RNG')
        end end
        eq(D.encode(O.pack_prediction.capture(G,SMODS)),frozen,'pack preview is read-only')
        -- Probabilities happen first; explode blocks the queued creations
        -- beyond the non-blockable pack candidate/emplace events.
        for _,card in ipairs(G.jokers.cards) do
            if not card.debuff then card:calculate_joker({open_booster=true}) end
        end
        local actual={}
        for i=1,pack.config.extra do
            local c=SMODS.create_card(pack:create_card({ability=pack.config},i))
            actual[i]=O.shop_snapshot.card(c); G.pack_cards:emplace(c)
        end
        eq(actual,O.tag_rewards.plain(expected),'native pack candidates')
        eq(G.GAME.pseudorandom,details.rng_after,'native opening plus pack RNG')
        ORACLE_CONSUMABLE_DRAIN()
        local generated={}; for _,c in ipairs(G.consumeables.cards) do generated[#generated+1]=O.shop_snapshot.card(c) end
        eq(generated,details.opening_cards,'native Hallucination creations'); hits=hits+#generated
        eq(G.GAME.pseudorandom,details.settled_rng,'settled opening RNG')
        cases=cases+1
    end
end end
assert(hits>0)
print('PASS '..ORACLE_TEST_CASE..' ('..cases..' scenarios, '..hits..' generated Tarot cards)')

-- Exercise the actual native event barriers, not a manually drained callback
-- list: explode is blocking, whereas the earlier candidate events are not.
local saved={Object=Object,Event=Event,EventManager=EventManager,Particles=Particles,
    open=Card.open,explode=Card.explode,remove=Card.remove,emplace=CardArea.emplace}
local schedules=0
ORACLE_TEST_CASE='native Card.open, explode and EventManager validate before deferred Hallucination creation'
for _,speed in ipairs({1,4,16,64}) do for _,dt in ipairs({1/60,0.1,1}) do
    local joker=ORACLE_JOKER_FIXTURE('W9CWGHUX','j_hallucination')
    G.GAME.round_resets.ante=5; G.GAME.probabilities.normal=2
    G.jokers.cards={joker}; G.consumeables.cards={}; G.GAME.consumeable_buffer=0
    SMODS.Booster={take_ownership_by_kind=function(_,kind,v)
        for _,c in ipairs(G.P_CENTER_POOLS.Booster) do if c.kind==kind then c.create_card=v.create_card end end
    end}
    dofile(ORACLE_TEST_SOURCE..'/booster_truth.lua')
    dofile(ORACLE_TEST_SOURCE..'/pack_event_truth.lua')
    G.ARGS={}; G.TIMERS={REAL=0,TOTAL=0}; G.SETTINGS.paused=false; G.SETTINGS.GAMESPEED=speed
    G.E_MANAGER=EventManager(); G.ROOM={T={h=10}}; G.VIBRATION=0; G.C.WHITE={1,1,1,1}
    G.pack_cards.VT={y=0}; G.pack_cards.cards={}
    SMODS.ease_types={lerp=function(t) return t end}; SMODS.log_crash_info=function() return '' end
    Particles=function() return {scale=1,set_role=function() end,fade=function() end} end
    Card.remove=function() end; inc_career_stat=function() end
    SMODS.Centers=G.P_CENTERS
    local calc=SMODS.calculate_context
    SMODS.calculate_context=function(ctx,...)
        if ctx.open_booster then
            for _,c in ipairs(G.jokers.cards) do if not c.debuff then c:calculate_joker(ctx) end end
            return {}
        end
        return calc(ctx,...)
    end
    CardArea.emplace=function(area,c) area.cards[#area.cards+1]=c; c.area=area end
    O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
    O.pack_validator=dofile(ORACLE_TEST_ROOT..'/debug/pack_validator.lua')(O)
    O.config.validate_predictions=true; O.pack_validator.install()
    G.pack_cards.emplace=CardArea.emplace
    local pack=Card(0,0,1,1.4,nil,G.P_CENTERS.p_arcana_mega_1,{})
    pack.cost=0; pack.states={hover={can=true}}
    local before=O.pack_prediction.capture(G,SMODS)
    local expected,details=O.pack_prediction.forecast(before,{key=pack.config.center.key})
    pack:open()
    local saw_candidates=false
    for frame=1,2000 do
        G.TIMERS.REAL=G.TIMERS.REAL+dt; G.TIMERS.TOTAL=G.TIMERS.TOTAL+dt*speed
        G.E_MANAGER:update(dt,true)
        if not saw_candidates and #G.pack_cards.cards==#expected then
            saw_candidates=true
            eq(#G.consumeables.cards,0,'Tarot must still be queued at pack emplacement')
            eq(G.GAME.pseudorandom,details.rng_after,'candidate checkpoint RNG')
            assert(O.validator.counts.MATCH==1 and O.validator.counts.MISMATCH==0 and not O.prediction_fault)
        end
        if #G.E_MANAGER.queues.base==0 then break end
        assert(frame<2000,'native event queue failed to settle')
    end
    assert(saw_candidates and #G.consumeables.cards==1,'both actual event phases must execute')
    eq(O.shop_snapshot.card(G.consumeables.cards[1]),details.opening_cards[1],'post-pack Tarot')
    eq(G.GAME.pseudorandom,details.settled_rng,'post-animation RNG')
    schedules=schedules+1
end end
Object,Event,EventManager,Particles=saved.Object,saved.Event,saved.EventManager,saved.Particles
Card.open,Card.explode,Card.remove,CardArea.emplace=saved.open,saved.explode,saved.remove,saved.emplace
print('PASS '..ORACLE_TEST_CASE..' ('..schedules..' timing/speed combinations)')
