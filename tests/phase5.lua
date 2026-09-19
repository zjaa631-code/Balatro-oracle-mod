local O,D=ORACLE,ORACLE.data
local watch=O.main.watch
local passed=0
local function test(n,f) if ORACLE_FIXTURES_ONLY then return end; ORACLE_TEST_CASE=n; f(); passed=passed+1; print('PASS '..n) end
local function eq(a,b,n) assert(D.encode(a)==D.encode(b),(n or 'mismatch')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
CardArea={}
function CardArea:is(class) return class==CardArea end
function CardArea:set_ranks() end
function CardArea:align_cards() end
function CardArea:remove_from_highlighted() end
function Card:set_card_area(a) self.area=a end
local function area(kind)
    return setmetatable({cards={},config={type=kind,card_limit=52},T={x=0,y=0,w=8,h=2}},{__index=CardArea})
end
local function card(id,front)
    local c=setmetatable({playing_card=id,sort_id=id,config={card_key=front,center=G.P_CENTERS.c_base},
        ability={name='Default Base',set='Default'},base=D.copy(G.P_CARDS[front]),T={r=0},facing='front'}, {__index=Card})
    function c:set_card_area(a) self.area=a end
    function c:remove_from_area() self.area=nil end
    function c:flip() self.facing=self.facing=='front' and 'back' or 'front' end
    return c
end
local function fixture()
    ORACLE_PHASE3_FIXTURE('PHASE5',3)
    G.FUNCS.oracle_watch=watch
    create_card=ORACLE_TRUTH_CREATE_CARD
    SMODS.calculate_context=function() return {} end
    G.deck=area('deck'); G.hand=area('hand'); G.discard=area('discard'); G.playing_cards={}
    G.GAME.blind={name='The Serpent',config={blind={key='bl_serpent'}},stay_flipped=function() return false end}
    G.STATE=G.STATES.SELECTING_HAND
    G.GAME.starting_deck_size=52
    for i=1,12 do
        local c=card(i,({'S_A','H_K','D_2'})[(i-1)%3+1])
        G.playing_cards[i]=c; G.deck.cards[i]=c; c.area=G.deck
    end
    O.prediction_fault=nil
end
dofile(ORACLE_TEST_SOURCE..'/deck_truth.lua')

test('native draw uses actual deck tail; empty deck and detached state',function()
    fixture()
    local before=D.encode(O.deck_prediction.read(G))
    math.randomseed(505); local next_math=math.random(); math.randomseed(505)
    local s=O.deck_prediction.read(G)
    assert(s.next[1].id==12 and s.next[12].id==1)
    s.next[1].base.suit='Clubs'; s.next[1].ability.extra=900
    assert(G.deck.cards[12].base.suit=='Diamonds' and not G.deck.cards[12].ability.extra)
    assert(math.random()==next_math and D.encode(O.deck_prediction.read(G))==before)
    for i=12,1,-1 do
        local expected=O.deck_prediction.identity(O.deck_prediction.read(G).next[1])
        local actual=G.hand:draw_card_from(G.deck)
        assert(actual.playing_card==i)
        eq(O.deck_prediction.identity(O.deck_prediction.card(actual,G)),expected)
    end
    assert(#O.deck_prediction.read(G).next==0 and not G.hand:draw_card_from(G.deck))
end)

test('discard, destruction, addition, duplication and Tarot/Spectral mutations stay current',function()
    fixture()
    local first=G.hand:draw_card_from(G.deck)
    G.discard:emplace(G.hand:remove_card(first))
    local destroyed=G.deck:remove_card(G.deck.cards[5])
    for i,c in ipairs(G.playing_cards) do if c==destroyed then table.remove(G.playing_cards,i); break end end
    local added=card(50,'S_A'); G.deck:emplace(added); G.playing_cards[#G.playing_cards+1]=added
    local duplicate=card(51,'H_K'); G.deck:emplace(duplicate); G.playing_cards[#G.playing_cards+1]=duplicate
    local top=G.deck.cards[#G.deck.cards]
    top.base.suit='Hearts'; top.base.value='King' -- deliberately stale front key
    top.config.center=G.P_CENTERS.m_glass; top.ability={name='Glass Card',set='Enhanced',extra=4,perma_bonus=35}
    top.seal='Red'; top.edition={key='e_polychrome',polychrome=true}; top.debuff=true
    local s=O.deck_prediction.read(G)
    assert(s.next[1].front=='H_K' and s.next[1].key=='m_glass' and s.next[1].ability.perma_bonus==35)
    assert(s.next[1].seal=='Red' and s.next[1].edition=='e_polychrome' and s.next[1].debuff)
    assert(#s.hand==0 and #s.discard==1 and #s.all==13 and #s.next==12)
    assert(s.next[#s.next].id==51) -- native deck emplace inserts at the bottom
    G.deck.cards[1],G.deck.cards[12]=G.deck.cards[12],G.deck.cards[1] -- completed shuffle result
    assert(O.deck_prediction.read(G).next[1].id==51)
    G.STATE=G.STATES.SHOP; assert(not O.deck_prediction.read(G).drawing_context)
end)

test('draw validator verifies real generator identity without double drawing',function()
    fixture()
    O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
    O.deck_validator=dofile(ORACLE_TEST_ROOT..'/debug/deck_validator.lua')(O); O.deck_validator.install()
    G.hand:draw_card_from(G.deck)
    assert(#G.hand.cards==1 and #G.deck.cards==11 and O.validator.counts.MATCH==1)
    assert(O.validator.counts.MISMATCH==0)
end)

test('purchases and both Overstock upgrades refresh cached forecasts at 2/3/4 slots',function()
    fixture(); G.STATE=G.STATES.SHOP
    G.shop_jokers=area('shop'); G.shop={recalculate=function() end}
    O.controller=dofile(ORACLE_TEST_ROOT..'/controller.lua')(O)
    -- Use actual create_card_for_shop captured before validation wrappers.
    O.controller.install()
    for i=1,2 do G.shop_jokers:emplace(create_card_for_shop(G.shop_jokers)) end
    local first=O.controller.shop_forecast(); assert(#first[2].cards==2)
    -- Purchase one item: it stays in owned availability, leaving one shelf slot empty.
    local bought=table.remove(G.shop_jokers.cards,1); G.jokers.cards={bought}
    local after=O.controller.shop_forecast()
    assert(after~=first and #after[1].cards==1 and #after[2].cards==2)
    for slots=3,4 do
        G.GAME.used_vouchers[slots==3 and 'v_overstock_norm' or 'v_overstock_plus']=true
        change_shop_size(1) -- exact native function fills every vacant slot now
        local rows,err,snapshot=O.controller.shop_forecast(); assert(rows,err)
        assert(snapshot.shop.limit==slots and #rows[1].cards==slots and #rows[2].cards==slots)
        assert(snapshot.shop.owned[bought.config.center.key])
        -- Next actual reroll after the immediate expansion draws.
        for _,c in ipairs(G.shop_jokers.cards) do
            if c.config.center.key~=bought.config.center.key then G.GAME.used_jokers[c.config.center.key]=nil end
        end
        G.shop_jokers.cards={}
        local actual={}
        for i=1,slots do local c=create_card_for_shop(G.shop_jokers); G.shop_jokers:emplace(c); actual[i]=O.shop_snapshot.card(c) end
        eq(actual,rows[2].cards,'reroll after Overstock '..slots)
    end
end)

test('event refresh coalesces changes and never rebuilds an unchanged menu each frame',function()
    fixture()
    local pending,refreshes={},0
    G.E_MANAGER={add_event=function(_,e) pending[#pending+1]=e end}
    Event=function(e) return e end
    G.OVERLAY_MENU={}; G.FUNCS.oracle_refresh=function() refreshes=refreshes+1 end
    local e={config={}}
    G.FUNCS.oracle_watch(e)
    for i=1,100 do G.FUNCS.oracle_watch(e) end
    assert(#pending==0)
    O.controller.invalidate(); G.FUNCS.oracle_watch(e)
    for i=1,30 do O.controller.invalidate(); G.FUNCS.oracle_watch(e) end
    assert(#pending==1 and pending[1].timer=='REAL'); pending[1].func(); assert(refreshes==1)
    e={config={}}; G.FUNCS.oracle_watch(e); O.controller.invalidate(); G.FUNCS.oracle_watch(e)
    G.OVERLAY_MENU=nil; pending[2].func(); assert(refreshes==1)
end)
print('PHASE5: '..passed..' tests passed')
