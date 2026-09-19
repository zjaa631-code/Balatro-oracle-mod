local O, root = ORACLE, ORACLE_TEST_ROOT
local native_ui = G
local D, passed, comparisons = O.data, 0, 0
local function test(name, fn)
    if ORACLE_PHASE2_FIXTURES_ONLY then return end
    ORACLE_TEST_CASE=name
    fn(); passed = passed + 1; print('PASS '..name)
end
local function eq(a, b, message)
    assert(D.encode(a) == D.encode(b), (message or 'Mismatch')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a))
end
function HEX() return {1, 1, 1, 1} end
function EMPTY() return {} end
SMODS.optional_features = {}
SMODS.ObjectTypes = {}
SMODS.log_crash_info = function() return '' end
SMODS.showman = function() return G.TEST_SHOWMAN or false end
dofile(ORACLE_TEST_SOURCE..'/truth.lua')
local protos = dofile(ORACLE_TEST_SOURCE..'/prototypes.lua')
for key, v in pairs(protos.P_BLINDS) do
    v.key, v.set = key, 'Blind'
    if v.boss then
        v.boss.max = nil; if v.boss.showdown then v.boss.min = nil end
        v.blind_types = {'boss'}
    end
    if key == 'bl_small' then v.small = {min = 1, allow_duplicates = true}; v.blind_types = {'small'} end
    if key == 'bl_big' then v.big = {min = 1, allow_duplicates = true}; v.blind_types = {'big'} end
end
for k, v in pairs(protos.P_CENTERS) do v.key = k end
for k, v in pairs(protos.P_TAGS) do v.key = k end
local function fixture(seed, ante)
    ORACLE_TEST_CONTEXT={seed=seed,ante=ante}
    local pools = {Tag = {}, Voucher = {}}
    local centers, tags = D.copy(protos.P_CENTERS), D.copy(protos.P_TAGS)
    for _, v in pairs(centers) do if v.set == 'Voucher' then pools.Voucher[#pools.Voucher + 1] = v end end
    for _, v in pairs(tags) do pools.Tag[#pools.Tag + 1] = v end
    for _, p in pairs(pools) do table.sort(p, function(a, b) return a.order < b.order end) end
    local g = {VERSION = '1.0.1o-FULL', STAGE = 1, STAGES = {RUN = 1},
        SETTINGS = {paused = false}, ARGS = {TEMP_POOL = {'untouched'}},
        P_CENTERS = centers, P_TAGS = tags, P_CENTER_POOLS = pools, P_BLINDS = D.copy(protos.P_BLINDS),
        jokers = {cards = {}}, consumeables = {cards = {}}, shop_vouchers = {cards = {}},
        GAME = {
            pseudorandom = {seed = seed, hashed_seed = O.rng.hash(seed)},
            round_resets = {ante = ante, blind_states = {Boss = 'Upcoming'},
                blind_choices = {}, blind_tags = {Small = 'tag_charm', Big = 'tag_coupon'}},
            starting_params = {vouchers_in_shop = 1}, modifiers = {}, current_round = {voucher = {spawn = {}}},
            used_jokers = {}, used_vouchers = {}, pool_flags = {}, banned_keys = {},
            bosses_used = {}, perscribed_bosses = {}, win_ante = 8, stake = 1, round = 1,
        }}
    G = g
    g.GAME.bosses_used = SMODS.normalize_bosses_used_table({})
    return g
end
local function compare(kind, sim, actual, ...)
    ORACLE_TEST_CONTEXT.ante=G.GAME.round_resets.ante
    ORACLE_TEST_CONTEXT.generator=kind
    local args = {...}
    local s = O.snapshot.capture(G, SMODS)
    local before = D.encode(s)
    local expected, details = O.ante_prediction.run(s, function(shadow, rng)
        return sim(shadow, rng, unpack(args))
    end)
    eq(O.snapshot.capture(G, SMODS), s, kind..' changed live state')
    assert(D.encode(s) == before, 'Input snapshot changed')
    local value = actual(unpack(args))
    eq(expected, value, kind..' result')
    eq(details.rng_after, G.GAME.pseudorandom, kind..' per-key RNG')
    comparisons = comparisons + 1
    return value
end
ORACLE_PHASE2_FIXTURE = fixture
ORACLE_TEST_PROTOS = protos
test('private Lua global states reproduce 4000 real math draws', function()
    local backend = O.backend.new()
    for i = 1, 2000 do
        local seed = i / 2001
        math.randomseed(seed); local expected = math.random()
        assert(backend.draw(seed) == expected)
        math.randomseed(seed); expected = math.random(-7, 21)
        assert(backend.draw(seed, -7, 21) == expected)
    end
    backend.close()
    assert(not pcall(backend.draw, 1), 'Closed backend remained usable')
end)
test('private RNG and deep snapshots leave live RNG and nested state intact', function()
    fixture('ISOLATE', 3)
    local s = O.snapshot.capture(G, SMODS)
    local before = D.encode(s)
    math.randomseed(1717); local expected = math.random()
    math.randomseed(1717)
    local r = O.rng.new(s.game.pseudorandom)
    for i = 1, 100 do r:random('Voucher3'); r:element({'x','y'}, 'Tag3') end
    r:close()
    assert(math.random() == expected)
    assert(D.encode(s) == before)
    local shadow = D.copy(s)
    shadow.game.bosses_used.boss.bl_hook = 999
    shadow.pools.Voucher[1].key = 'changed'
    shadow.game.pseudorandom.seed = 'changed'
    assert(D.encode(O.snapshot.capture(G, SMODS)) == before)
end)
test('2500 real pseudoseed draws, known keys and resamples match', function()
    fixture('PSHASH', 4)
    local r = O.rng.new(G.GAME.pseudorandom)
    for i = 1, 2500 do
        local key = ({'Tag4','Voucher4','boss','Voucher4_resample2','Tag8_resample3'})[(i % 5) + 1]
        assert(r:random(key) == pseudorandom(key))
    end
    eq(r.state, G.GAME.pseudorandom)
    assert(not pcall(function() r:seed('seed') end))
    r:close()
end)
test('200 seeds x 8 Antes: Tags, Vouchers and both Boss paths match patched code', function()
    for seed = 1, 200 do
        fixture('ORACLE'..seed, 1)
        for ante = 1, 8 do
            G.GAME.round_resets.ante = ante
            compare('tag', O.ante_prediction.tag, get_next_tag_key)
            compare('tag', O.ante_prediction.tag, get_next_tag_key)
            compare('voucher', O.ante_prediction.voucher, get_next_voucher_key)
            compare('vouchers', O.ante_prediction.vouchers, SMODS.get_next_vouchers)
            G.GAME.round_resets.blind_choices = {}
            for _, kind in ipairs({'small','big','boss'}) do
                local key = compare(kind, O.ante_prediction.blind, SMODS.get_new_blind, kind)
                G.GAME.round_resets.blind_choices[kind] = key
            end
            -- Legacy boss showdown prototypes require min; restore only for that
            -- legacy helper (SMODS normally does not use it at an Ante reset).
            for _, v in pairs(G.P_BLINDS) do if v.boss and v.boss.showdown then v.boss.min = 0 end end
            compare('legacy boss', function(s, r) return O.ante_prediction.blind(s, r, 'boss', true) end, get_new_boss)
        end
    end
end)
test('live Blind pool order survives shadow copies at Ante 6', function()
    fixture('XT11YKLW', 6)
    G.GAME.round_resets.blind_choices = {Small = 'bl_small', Big = 'bl_big'}
    for _, key in ipairs({'bl_fish', 'bl_hook', 'bl_mouth', 'bl_pillar', 'bl_tooth'}) do
        G.GAME.bosses_used.boss[key] = 1
    end
    G.GAME.pseudorandom.boss = 0.1480464234255
    local live_before = D.encode(G.GAME)
    local native_pool = SMODS.create_blind_pool('boss')
    local s = O.snapshot.capture(G, SMODS)
    assert(D.encode(G.GAME) == live_before, 'native pool capture changed game')
    eq(s.native_blind_pools.boss, native_pool, 'captured Blind pool order')
    -- An unrelated copied hash table may iterate in a different order. The
    -- current native pool must win over any reconstructed order.
    s.blind_order = {}
    local predicted, details = O.ante_prediction.run(s, function(shadow, rng)
        return O.ante_prediction.blind(shadow, rng, 'boss')
    end)
    eq(details.pool, native_pool, 'prediction used a rebuilt Blind pool')
    local actual = SMODS.get_new_blind('boss')
    eq(predicted, actual, 'Ante 6 Boss selection')
    eq(details.rng_after, G.GAME.pseudorandom, 'Ante 6 Boss RNG')
end)
test('eligibility: unlocks, prerequisites, shop exclusion, Showman and pool flags', function()
    fixture('CULL', 5)
    for _, v in ipairs(G.P_CENTER_POOLS.Voucher) do v.unlocked = true end
    G.GAME.used_vouchers.v_overstock_norm = true
    G.GAME.used_jokers.v_clearance_sale = true
    G.shop_vouchers.cards = {{config = {center = G.P_CENTERS.v_tarot_merchant}}}
    G.GAME.banned_keys.v_blank = true
    G.P_CENTER_POOLS.Voucher[3].yes_pool_flag = 'test'
    G.P_CENTER_POOLS.Voucher[4].no_pool_flag = 'test'
    for _, flag in ipairs({false, true}) do
        G.GAME.pool_flags.test = flag
        for _, showman in ipairs({false, true}) do
            G.TEST_SHOWMAN = showman
            G.jokers.cards = showman and {{config = {center = {key = 'j_ring_master'}}}} or {}
            for i = 1, 40 do compare('culled voucher', O.ante_prediction.voucher, get_next_voucher_key) end
        end
    end
end)
test('multiple Vouchers, already spawned cards and from-tag key match', function()
    fixture('MULTIVOUCHER', 6)
    G.GAME.modifiers.extra_vouchers = 3
    for i = 1, 40 do
        local existing = {spawn = {v_blank = true}, 'v_blank'}
        compare('multi vouchers', O.ante_prediction.vouchers, SMODS.get_next_vouchers, existing)
        compare('from-tag voucher', O.ante_prediction.voucher, get_next_voucher_key, true)
    end
end)
test('forced, prescribed, empty-pool fallback and debuffed Showman cases', function()
    fixture('FORCED', 2)
    G.FORCE_TAG = 'tag_charm'
    compare('forced tag', O.ante_prediction.tag, get_next_tag_key)
    G.FORCE_BOSS = 'bl_hook'
    compare('forced boss', function(s,r) return O.ante_prediction.blind(s,r,'boss',true) end, get_new_boss)
    G.GAME.perscribed_bosses[2] = 'bl_wall'
    compare('prescribed boss', function(s,r) return O.ante_prediction.blind(s,r,'boss',true) end, get_new_boss)
    G.FORCE_TAG = nil
    for _, v in ipairs(G.P_CENTER_POOLS.Tag) do G.GAME.banned_keys[v.key] = true end
    compare('tag fallback', O.ante_prediction.tag, get_next_tag_key)
    for _, v in ipairs(G.P_CENTER_POOLS.Voucher) do G.GAME.used_vouchers[v.key] = true end
    compare('voucher fallback', O.ante_prediction.voucher, get_next_voucher_key)
    G.jokers.cards = {{debuff = true, config = {center = {key = 'j_ring_master'}}}}
    assert(not O.snapshot.capture(G, SMODS).showman)
end)
test('custom pool callbacks are detected without executing them', function()
    fixture('HOOKS', 4)
    local count = 0
    G.P_CENTER_POOLS.Tag[1].in_pool = function() count = count + 1; return true end
    local s = O.snapshot.capture(G, SMODS)
    assert(s.unsupported and count == 0)
    assert(not pcall(O.ante_prediction.forecast, s, 3))
    assert(count == 0)
end)
test('20-Ante conditional branch matches sequential patched generators', function()
    for seed = 1, 60 do
        fixture('FUTURE'..seed, 1)
        local s = O.snapshot.capture(G, SMODS)
        local result = O.ante_prediction.forecast(s, 20)
        for ante = 2, 21 do
            G.GAME.round_resets.ante = ante
            local vouchers = SMODS.get_next_vouchers()
            local small, big = get_next_tag_key(), get_next_tag_key()
            G.GAME.round_resets.blind_choices = {}
            local boss
            for _, kind in ipairs({'small','big','boss'}) do
                local key = SMODS.get_new_blind(kind)
                G.GAME.round_resets.blind_choices[kind:gsub('^%l', string.upper)] = key
                if kind == 'boss' then boss = key end
            end
            eq(result[ante].vouchers, vouchers, 'future vouchers')
            eq(result[ante].tags, {Small = small, Big = big}, 'future tags')
            eq(result[ante].boss, boss, 'future boss')
            comparisons = comparisons + 4
        end
    end
end)
test('transition blocks stale boss forecasts; win_ante=1 uses patched showdown rule', function()
    fixture('TRANSITION', 2)
    G.GAME.round_resets.blind_states.Boss = 'Defeated'
    assert(not pcall(O.ante_prediction.forecast, O.snapshot.capture(G,SMODS), 3))
    fixture('SHOWDOWN', 1); G.GAME.win_ante = 1
    compare('showdown one', O.ante_prediction.blind, SMODS.get_new_blind, 'boss')
end)
test('native Ante UI and cache never invoke live RNG or mutate game state', function()
    fixture('NATIVEUI', 3)
    for _, key in ipairs({'C', 'UIT', 'ROOM', 'E_MANAGER', 'ASSET_ATLAS', 'FUNCS'}) do G[key] = native_ui[key] end
    G.SETTINGS.paused = true
    O.controller.invalidate()
    local before = O.snapshot.capture(G, SMODS)
    local random, randomseed = math.random, math.randomseed
    math.random = function() error('Live math.random called by Ante UI') end
    math.randomseed = function() error('Live math.randomseed called by Ante UI') end
    local n = O.controller.forecast_count
    O.ante_ui.page = 2
    assert(O.ante_ui.definition().n == G.UIT.ROOT)
    assert(O.ante_ui.definition().n == G.UIT.ROOT)
    assert(O.controller.forecast_count == n + 1, 'Unchanged state recomputed')
    eq(O.snapshot.capture(G, SMODS), before)
    G.GAME.used_vouchers.v_blank = true
    assert(O.controller.forecast())
    assert(O.controller.forecast_count == n + 2, 'Changed state not detected')
    O.config.enabled = false
    assert(not O.controller.forecast())
    O.config.enabled = true
    math.random, math.randomseed = random, randomseed
end)

test('private backend closes after a failed simulation; weighted pools fail closed', function()
    fixture('ERRORPATH', 3)
    local closed = 0
    local fake_rng = {new = function() return {trace = {}, state = {}, close = function() closed = closed + 1 end} end}
    local prediction = dofile(root..'/prediction/ante.lua')(D, fake_rng)
    assert(not pcall(prediction.run, O.snapshot.capture(G,SMODS), function() error('injected') end))
    assert(closed == 1)
    SMODS.optional_features.object_weights = true
    assert(not pcall(O.ante_prediction.forecast, O.snapshot.capture(G,SMODS), 3))
    SMODS.optional_features.object_weights = nil
end)

test('validator preserves calls/returns, compares RNG, and disables on mismatch', function()
    fixture('VALIDATE', 3)
    O.prediction_fault = nil
    O.validator = dofile(root..'/debug/validator.lua')(O)
    G.FUNCS = {}
    O.controller = dofile(root..'/controller.lua')(O)
    local original, calls = get_next_tag_key, 0
    get_next_tag_key = function(...) calls = calls + 1; return original(...), nil, 'sentinel' end
    O.controller.install()
    local a,b,c = get_next_tag_key()
    assert(a and b == nil and c == 'sentinel' and calls == 1)
    assert(O.validator.counts.MATCH == 1 and not O.prediction_fault)
    G.SETTINGS.paused = true
    get_next_tag_key()
    assert(calls == 2 and O.validator.counts.MATCH == 1)
    local s = O.snapshot.capture(G,SMODS)
    local record = O.validator.record('injected mismatch', s, 'expected', 'actual', {pool = {'expected'}})
    assert(record.status == 'MISMATCH' and record.input.game.pseudorandom.seed == 'VALIDATE')
    assert(O.prediction_fault and not O.controller.supported())
end)
print(string.format('PHASE2: %d tests passed; %d generator/result comparisons; runtime=%s', passed, comparisons, jit.version))
