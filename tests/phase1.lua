local root = ORACLE_TEST_ROOT
local passed = 0
local function test(name, f)
    ORACLE_TEST_CASE=name
    f()
    passed = passed + 1
    print('PASS '..name)
end
local function equal(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    seen = seen or {}
    if seen[a] then return seen[a] == b end
    seen[a] = b
    for k, v in pairs(a) do if not equal(v, b[k], seen) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function copy(t, seen)
    if type(t) ~= 'table' then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local out = {}; seen[t] = out
    for k, v in pairs(t) do out[k] = copy(v, seen) end
    return out
end
local function walk(node, pred, found)
    found = found or {}
    if type(node) ~= 'table' then return found end
    if pred(node) then found[#found + 1] = node end
    for _, child in pairs(node.nodes or {}) do walk(child, pred, found) end
    return found
end
local function buttons(tree, name)
    return walk(tree, function(n) return n.config and n.config.button == name end)
end
local Reader = dofile(root..'/state_reader.lua')
local function fixture()
    return {
        VERSION = '1.0.1o-FULL', STAGE = 1, STAGES = {RUN = 1, MAIN_MENU = 2},
        STATE = 2, STATES = {BLIND_SELECT = 1, SELECTING_HAND = 2, SHOP = 3, ROUND_EVAL = 4},
        P_BLINDS = {bl_small = {key = 'bl_small', name = 'Small Blind'}, bl_big = {key = 'bl_big', name = 'Big Blind'}},
        P_CENTER_POOLS = {Stake = {{key = 'stake_white', name = 'White Stake'}}},
        GAME = {stake = 1, round = 2, seeded = false,
            pseudorandom = {seed = 'ABCD1234', hashed_seed = 0.12, boss = 0.55},
            selected_back = {effect = {center = {key = 'b_red', name = 'Red Deck'}}},
            blind = {config = {blind = {key = 'bl_small', name = 'Small Blind'}}},
            round_resets = {ante = 1, blind_states = {Small = 'Defeated', Big = 'Select'},
                blind_choices = {Small = 'bl_small', Big = 'bl_big'}},
        },
    }
end
test('no run / loading / missing fields', function()
    assert(not Reader.read(nil).available)
    assert(not Reader.read({}).available)
    assert(not Reader.read({STAGES = {RUN = 1}, STAGE = 1, GAME = {}}).available)
end)
test('random run seed is read without seeded flag', function()
    local s = Reader.read(fixture())
    assert(s.available and s.seed == 'ABCD1234' and s.ante == 1)
    assert(s.back.key == 'b_red' and s.stake.key == 'stake_white')
end)
test('active, upcoming and completed blind contexts', function()
    local g = fixture()
    assert(Reader.read(g).blind.key == 'bl_small')
    g.STATE = g.STATES.BLIND_SELECT
    local s = Reader.read(g)
    assert(s.blind.key == 'bl_big' and s.blind_context == 'oracle_upcoming_blind')
    g.STATE = g.STATES.SHOP
    s = Reader.read(g)
    assert(s.blind.key == 'bl_small' and s.blind_context == 'oracle_completed_blind')
    g.STATE = g.STATES.ROUND_EVAL
    assert(Reader.read(g).blind_context == 'oracle_completed_blind')
end)
test('snapshot owns all returned records, including definition records', function()
    local g = fixture(); local before = copy(g); local s = Reader.read(g)
    s.blind.key = 'changed'; s.back.name = 'changed'; s.stake.key = 'changed'; s.seed = 'changed'
    assert(equal(g, before))
end)
test('reads do not touch LuaJIT global RNG sequence', function()
    math.randomseed(92); local expected = math.random()
    math.randomseed(92)
    for i = 1, 100 do Reader.read(fixture()) end
    assert(math.random() == expected)
end)
test('English and Chinese have identical localization keys', function()
    local en = dofile(root..'/localization/en-us.lua').misc.dictionary
    local zh = dofile(root..'/localization/zh_CN.lua').misc.dictionary
    for k in pairs(en) do assert(type(zh[k]) == 'string', k) end
    for k in pairs(zh) do assert(type(en[k]) == 'string', k) end
end)

-- Use the actual installed vanilla UI-definition functions, not mirrored
-- implementations. Rendering classes are stubs here; live rendering is separate.
G = fixture()
G.FUNCS = {}; G.SETTINGS = {}; G.ROOM = {T = {w = 20, h = 12}}
G.UIT = {ROOT = 1, R = 2, C = 3, T = 4, O = 5, B = 6}
local color = {1, 1, 1, 1}
G.C = setmetatable({UI = setmetatable({}, {__index = function() return color end})},
    {__index = function() return color end})
G.E_MANAGER = {add_event = function() end}
G.ASSET_ATLAS = {icons = {}}
function Sprite()
    return {states = {drag = {}, hover = {}, collide = {}}, define_draw_steps = function() end}
end
function Event(x) return x end
function Moveable() return {} end
function UIBox(x) return x end
function DynaText(x) return x end
function copy_table(x) return copy(x) end
function get_current_profile() return {} end
local en = dofile(root..'/localization/en-us.lua').misc.dictionary
function localize(key)
    if type(key) == 'table' then return key.key end
    return en[key] or key
end
local logs = {}
function sendInfoMessage() end
function sendWarnMessage(msg) logs[#logs + 1] = msg end
dofile(ORACLE_TEST_SOURCE..'/functions/UI_definitions.lua')
local original_options = create_UIBox_options
SMODS = {version = '26.829.0', current_mod = {id = 'Oracle', config = dofile(root..'/config.lua')},
    load_file = function(path) return loadfile(root..'/'..path) end, save_mod_config = function() end}
package.preload.lovely = function() return {version = '0.9.0'} end
dofile(root..'/Oracle.lua')
test('pause menu remains native without an Oracle entry', function()
    local tree = create_UIBox_options()
    assert(create_UIBox_options == original_options)
    assert(#buttons(tree, 'oracle_open') == 0)
    for _, name in ipairs({'settings', 'setup_run', 'go_to_menu', 'high_scores', 'your_collection', 'customize_deck'}) do
        assert(#buttons(tree, name) == #buttons(original_options(), name), name)
    end
end)
test('no Oracle entry on main menu or repeated pause menu opens', function()
    G.STAGE = G.STAGES.MAIN_MENU
    assert(#buttons(create_UIBox_options(), 'oracle_open') == 0)
    G.STAGE = G.STAGES.RUN
    for i = 1, 10 do assert(#buttons(create_UIBox_options(), 'oracle_open') == 0) end
end)
test('native overview, tab switching, refresh and disable do not mutate game', function()
    local before, rng_before = copy(G.GAME), G.GAME.pseudorandom
    local overlays = 0
    G.FUNCS.overlay_menu = function(args)
        assert(args.definition)
        assert(#buttons(args.definition, 'exit_overlay_menu') == 1)
        assert(#buttons(args.definition, 'options') == 0)
        overlays = overlays + 1
    end
    for i = 1, 20 do G.FUNCS.oracle_open(); G.FUNCS.oracle_refresh() end
    ORACLE.main.active = 'settings'; G.FUNCS.oracle_refresh()
    ORACLE.config.enabled = false; ORACLE.main.active = 'overview'; G.FUNCS.oracle_refresh()
    ORACLE.config.enabled = true
    assert(equal(before, G.GAME) and rng_before == G.GAME.pseudorandom)
    assert(overlays == 42)
    assert(#logs == 0, table.concat(logs, '\n'))
end)
test('UI construction calls no game RNG or global math RNG', function()
    local random, randomseed = math.random, math.randomseed
    math.random = function() error('Oracle called global math.random') end
    math.randomseed = function() error('Oracle called global math.randomseed') end
    pseudorandom = function() error('Oracle called game RNG') end
    pseudoseed = pseudorandom; get_current_pool = pseudorandom
    G.FUNCS.oracle_open()
    math.random, math.randomseed = random, randomseed
    assert(#logs == 0, table.concat(logs, '\n'))
end)
test('version mismatch closes prediction gate and reports issue', function()
    local status = ORACLE.compatibility.inspect({VERSION = 'future'}, SMODS, {version = 'future'})
    assert(not status.prediction_ready and #status.issues > 0)
end)
print(string.format('RESULT: %d tests passed; runtime=%s', passed, jit.version))
