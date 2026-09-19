local O,D=ORACLE,ORACLE.data
local passed,cases=0,0
local function eq(a,b,label) assert(D.encode(a)==D.encode(b),(label or '')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
local function test(name,fn) ORACLE_TEST_CASE=name; fn(); passed=passed+1; print('PASS '..name) end
local function predict(kind,c,depth)
    local capture=kind=='joker' and O.jokers.capture or O.consumables.capture
    local s=capture(G,SMODS,c); local before=D.encode(s)
    math.randomseed(128); local draw=math.random(); math.randomseed(128)
    local r=O.engine.predict('events',s,{kind=kind,depth=depth})
    eq(math.random(),draw,'global RNG'); eq(D.encode(s),before,'input state')
    eq(capture(G,SMODS,c),s,'live state')
    return r
end
test('event sequences match native probability checks, creations and RNG after every step',function()
    for seed=1,30 do
        for _,key in ipairs({'j_space','j_gros_michel','j_cavendish','j_bloodstone','j_business','j_reserved_parking','j_8_ball','j_hallucination','m_lucky','m_glass','j_misprint'}) do
            local c=ORACLE_JOKER_FIXTURE('EVENT_'..seed,key)
            G.GAME.probabilities.normal=2^(seed%3)
            G.consumeables.config.card_limit=seed%5
            local r=predict('joker',c,20)
            for _,row in ipairs(r.rows) do
                local count=#G.consumeables.cards; SMODS.post_prob={}
                local actual=ORACLE_JOKER_ACTUAL(c)
                eq(#SMODS.post_prob,#row.checks,key..' checks')
                for i,check in ipairs(row.checks) do eq(SMODS.post_prob[i].result,check.success,key..' result') end
                if row.mult then eq(actual.mult_mod,row.mult,'Misprint') end
                eq(#G.consumeables.cards-count,#row.created,'created count')
                for i,card in ipairs(row.created) do eq(O.consumables.simple(O.consumables.card(G.consumeables.cards[count+i])),O.consumables.simple(card),'created card') end
                eq(G.GAME.pseudorandom,row.rng_after,key..' sequence RNG'); cases=cases+1
            end
        end
    end
end)
test('successive Wheels propagate editions and shrink eligible pools exactly as native use',function()
    local successes,failures,stops=0,0,0
    for seed=1,40 do
        local c=ORACLE_CONSUMABLE_FIXTURE('WHEEL_SEQUENCE_'..seed,'c_wheel_of_fortune')
        G.consumeables.cards={}
        local r=predict('consumable',c,20)
        for _,row in ipairs(r.rows) do
            -- Card:update uses this historical field name specifically for Wheel.
            c.eligible_strength_jokers={}
            for _,j in ipairs(G.jokers.cards) do if not j.edition then c.eligible_strength_jokers[#c.eligible_strength_jokers+1]=j end end
            local before=O.consumables.capture(G,SMODS,c)
            c:use_consumeable(G.consumeables); ORACLE_CONSUMABLE_DRAIN()
            eq(O.consumables.observe(before,G),O.consumables.expected(row),'Wheel outcome')
            eq(G.GAME.pseudorandom,row.rng_after,'Wheel sequence RNG')
            if row.success then successes=successes+1 else failures=failures+1 end
            cases=cases+1
        end
        if r.stop=='oracle_event_no_target' then
            stops=stops+1; for _,j in ipairs(G.jokers.cards) do assert(j.edition,'stop before pool exhausted') end
        end
    end
    assert(successes>0 and failures>0 and stops>0)
end)
test('depth prefixes are stable, snapshot-isolated and stop at native boundaries',function()
    local c=ORACLE_JOKER_FIXTURE('PREFIX','j_space')
    local full=predict('joker',c,20)
    for _,depth in ipairs({1,3,5,10,20}) do
        local r=predict('joker',c,depth); eq(#r.rows,depth)
        for i,row in ipairs(r.rows) do eq(row,full.rows[i],'prefix') end
    end
    for _,key in ipairs({'j_gros_michel','j_cavendish','m_glass'}) do
        c=ORACLE_JOKER_FIXTURE('TERMINAL',key); G.GAME.probabilities.normal=10000
        local r=predict('joker',c,20); eq(#r.rows,1); eq(r.stop,'oracle_event_destroy_boundary')
    end
    c=ORACLE_JOKER_FIXTURE('FULL','j_hallucination'); G.consumeables.config.card_limit=0
    local before=D.copy(G.GAME.pseudorandom); local r=predict('joker',c,20)
    eq(r.stop,'oracle_joker_no_room'); eq(r.rows[1].rng_after,before)
    c=ORACLE_CONSUMABLE_FIXTURE('NO_TARGET','c_wheel_of_fortune')
    for _,j in ipairs(G.jokers.cards) do j:set_edition('e_foil') end
    r=predict('consumable',c,20); eq(#r.rows,0); eq(r.stop,'oracle_event_no_target')
end)
test('config persists independent depth; sequence UI pages cache and hover only predicts next event',function()
    local normalize=dofile(ORACLE_TEST_ROOT..'/configuration.lua').normalize
    eq(normalize({}).event_depth,5); eq(normalize({event_depth=500}).event_depth,5)
    eq(normalize({event_depth=20,prediction_depth=3}).prediction_depth,3)
    local c=ORACLE_JOKER_FIXTURE('DEPTH_UI','j_space'); c.area=G.jokers
    G.UIT={ROOT=1,R=2,C=3,T=4,O=5,B=6}
    local colour={}; G.C=setmetatable({UI=setmetatable({},{__index=function() return colour end})},{__index=function() return colour end})
    local old_cycle,old_refresh,old_save=create_option_cycle,G.FUNCS.oracle_refresh,SMODS.save_mod_config
    local cycles={}; create_option_cycle=function(args) cycles[#cycles+1]=args; return {n=G.UIT.R,config={},nodes={}} end
    local saved,refreshed=0,0
    G.FUNCS.oracle_refresh=function() refreshed=refreshed+1 end
    SMODS.save_mod_config=function() saved=saved+1 end
    O.settings=dofile(ORACLE_TEST_ROOT..'/ui/settings.lua')(O)
    O.events_ui=dofile(ORACLE_TEST_ROOT..'/ui/events.lua')(O); O.events_ui.install()
    G.FUNCS.oracle_event_depth({to_val=20}); eq(saved,1); eq(refreshed,1); eq(O.config.event_depth,20)
    local original=O.engine.predict; local calls={}
    O.engine.predict=function(name,...) calls[#calls+1]=name; return original(name,...) end
    O.events_ui.nodes('joker',c); O.events_ui.nodes('joker',c); eq(calls,{'events'})
    eq(#O.events_ui.cache.joker.result.rows,20)
    G.FUNCS.oracle_events_joker({to_key=4}); O.events_ui.nodes('joker',c)
    eq(O.events_ui.pages.joker,4); eq(#calls,1)
    assert(cycles[#cycles].options[4]=='16–20 / 20','all results accessible')
    O.quick=dofile(ORACLE_TEST_ROOT..'/prediction/quick.lua')(O)
    eq(O.quick_ui.kind(c),'joker')
    local r=O.quick.get('joker',c); eq(calls[#calls],'joker'); assert(not r.rows)
    eq(r.checks,O.events_ui.cache.joker.result.rows[1].checks)
    G.FUNCS.oracle_event_depth({to_val=3}); O.quick.get('joker',c); eq(#calls,2,'hover independent of depth')
    O.events_ui.nodes('joker',c); eq(#calls,3); eq(#O.events_ui.cache.joker.result.rows,3)
    c=ORACLE_CONSUMABLE_FIXTURE('WHEEL_HOVER','c_wheel_of_fortune')
    O.config.event_depth=20
    r=O.quick.get('consumable',c); assert(not r.rows and r.success~=nil)
    local expected=O.engine.predict('consumable',O.consumables.capture(G,SMODS,c)); eq(r,expected)
    O.engine.predict=original; create_option_cycle=old_cycle
    G.FUNCS.oracle_refresh=old_refresh; SMODS.save_mod_config=old_save
    O.config.event_depth=5
end)
print(string.format('EVENT DEPTH: %d tests passed; %d sequential native actions compared',passed,cases))
