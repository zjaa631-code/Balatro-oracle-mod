local O,D=ORACLE,ORACLE.data
local passed,draws=0,0
local function eq(a,b,label) assert(D.encode(a)==D.encode(b),(label or 'mismatch')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
local function test(name,fn) if ORACLE_FIXTURES_ONLY then return end; ORACLE_TEST_CASE=name; ORACLE_TEST_CONTEXT=nil; fn(); passed=passed+1; print('PASS '..name) end
local function results(...) return {n=select('#',...),...} end
local function fixture(seed)
    ORACLE_PHASE3_FIXTURE(seed,3)
    O.config.enabled=true; O.config.validate_predictions=true; O.config.show_future_shops=true
    O.status={issues={}}; O.prediction_fault=nil
    O.controller=dofile(ORACLE_TEST_ROOT..'/controller.lua')(O)
    O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
end

test('invalid RNG input is rejected before allocating a private Lua state',function()
    local allocated=0
    local rng=dofile(ORACLE_TEST_ROOT..'/rng.lua')(D,{new=function() allocated=allocated+1; return {} end})
    assert(not pcall(rng.new,{seed='INVALID',callback=function() end}))
    assert(allocated==0,'Invalid snapshot allocated a backend before validation')
end)

test('shop validation wrappers preserve all arguments and nil-containing return tuples',function()
    fixture('RETURN7')
    O.config.validate_predictions=false
    local original=create_card_for_shop
    local calls,seen=0
    local card={config={center={key='j_joker'}}}
    create_card_for_shop=function(...) calls=calls+1; seen=results(...); return card,nil,'extension',nil end
    O.controller.install()
    local actual=results(create_card_for_shop(G.shop_jokers,nil,'context'))
    assert(actual.n==4 and actual[1]==card and actual[2]==nil and actual[3]=='extension' and actual[4]==nil)
    assert(calls==1 and seen.n==3 and seen[1]==G.shop_jokers and seen[2]==nil and seen[3]=='context')
    assert(O.controller.revision==1)
    create_card_for_shop=original
end)

test('private backend invalid-input rejection and repeated close leave live RNG intact',function()
    fixture('BACKEND7')
    math.randomseed(1781); local expected=math.random()
    math.randomseed(1781)
    local b=O.backend.new()
    assert(not pcall(b.draw,'invalid seed'),'Invalid seed unexpectedly accepted')
    assert(type(b.draw(0.4))=='number','Backend unusable after invalid input')
    b.close(); b.close()
    assert(not pcall(b.draw,0.4)); assert(math.random()==expected)
end)

test('simulation exceptions close private RNG exactly once and preserve every input field',function()
    fixture('EXCEPTION7')
    local closed=0
    local factory={new=function(state)
        local r=O.rng.new(state); local close=r.close
        r.close=function(self) closed=closed+1; close(self) end
        return r
    end}
    local predictor=dofile(ORACLE_TEST_ROOT..'/prediction/ante.lua')(D,factory)
    local snapshot=O.shop_snapshot.capture(G,SMODS); local before=D.encode(snapshot)
    for i=1,50 do
        assert(not pcall(predictor.run,snapshot,function(sh,r)
            r:random('failure_resample'..i); sh.game.used_jokers.j_joker=true
            error('injected shadow failure')
        end))
    end
    assert(closed==50)
    assert(not pcall(predictor.run,snapshot,function(sh,r)
        r.state.bad=function() end
        return 'invalid exported state'
    end))
    assert(closed==51,'Failed export did not close backend')
    eq(D.encode(snapshot),before)
    eq(O.shop_snapshot.capture(G,SMODS),snapshot)
end)

test('validation disk failures cannot change gameplay return values or leave forecasts enabled',function()
    fixture('DISK7')
    local original,love_before,warning_before=create_card_for_shop,love,sendWarnMessage
    local calls=0
    create_card_for_shop=function(...) calls=calls+1; return {config={center={key='j_not_the_prediction',set='Joker'}},ability={}},nil,'sentinel' end
    love={filesystem={getInfo=function() return nil end,append=function() return nil,'injected read-only disk' end}}
    local warnings={}; sendWarnMessage=function(message) warnings[#warnings+1]=message end
    O.controller.install()
    local out=results(create_card_for_shop(G.shop_jokers))
    assert(out.n==3 and out[3]=='sentinel' and calls==1)
    assert(O.validator.counts.MISMATCH==1 and O.prediction_fault and not O.controller.supported())
    assert(#warnings==1)
    create_card_for_shop=original; love=love_before; sendWarnMessage=warning_before
end)

test('unsupported shop recovery and zero slots never reuse a stale forecast',function()
    fixture('CACHE7'); O.config.prediction_depth=3
    local rows=assert(O.controller.shop_forecast())
    assert(#rows[2].cards==2)
    G.CONTROLLER.locks.shop_reroll=true
    assert(not O.controller.shop_forecast(),'Cached result escaped transition guard')
    G.CONTROLLER.locks.shop_reroll=false
    G.GAME.shop.joker_max=0
    rows=assert(O.controller.shop_forecast()); assert(#rows[2].cards==0)
    G.GAME.shop.joker_max=4
    rows=assert(O.controller.shop_forecast()); assert(#rows[2].cards==4)
end)

test('deterministic multi-seed per-key and resample sweeps match native pseudorandom',function()
    local samples=ORACLE_TEST_SAMPLES and ORACLE_TEST_SAMPLES.rng or 100
    for seed=ORACLE_TEST_START or 1,(ORACLE_TEST_START or 1)+samples-1 do
        fixture('RNG7_'..seed)
        local r=O.rng.new(G.GAME.pseudorandom)
        for i=1,40 do
            local key=({'shop','edition','soul','Joker2sho3_resample2','Voucher3_resample3',''} )[(i%6)+1]
            -- Warmed, interleaved streams and zero-valued existing stream state.
            if i==1 then G.GAME.pseudorandom[key]=0; r.state[key]=0 end
            local expected=r:random(key,-12,52)
            eq(pseudorandom(key,-12,52),expected,'seed '..seed..' draw '..i)
            draws=draws+1
        end
        eq(r.state,G.GAME.pseudorandom,'all per-key state')
        r:close()
    end
end)
print(string.format('PHASE7: %d tests passed; %d native RNG comparisons',passed,draws))
