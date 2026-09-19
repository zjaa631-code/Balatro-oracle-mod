local O,D=ORACLE,ORACLE.data
local passed,comparisons=0,0
local function eq(a,b,label) assert(D.encode(a)==D.encode(b),(label or '')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
local function test(name,fn) if ORACLE_FIXTURES_ONLY then return end; ORACLE_TEST_CASE=name; local ok,err=xpcall(fn,debug.traceback); assert(ok,err); passed=passed+1; print('PASS '..name) end
Game=Game or {}
local function noop() end
local function box() return {alignment={offset={}},T={y=0},VT={y=0},states={visible=true},
    remove=noop,set_alignment=noop,set_role=noop,get_UIE_by_ID=function() return {} end} end
local raw_add,raw_skip,raw_yep
local function fixture(seed,ante)
    ORACLE_TAG_FIXTURE(seed,ante)
    dofile(ORACLE_TEST_SOURCE..'/tag_chain_truth.lua')
    raw_add,raw_skip,raw_yep=add_tag,G.FUNCS.skip_blind,Tag.yep
    setmetatable(Tag,{__call=function(_,key,collection,blind)
        local t=setmetatable({}, {__index=Tag}); t:init(key,collection,blind); return t
    end})
    Tag.generate_UI=function() return {} end
    UIBox=function() return box() end
    G.UIT={ROOT=1,R=2,C=3,T=4,O=5}
    G.C.CLEAR={}; G.C.BLUE={}; G.C.WHITE={}; G.C.SECONDARY_SET={Voucher={}}
    G.SETTINGS.GAMESPEED=1; G.HUD_tags={}; G.GAME.tags={}; G.OVERLAY_MENU=nil
    G.GAME.round_resets.blind_states={Small='Select',Big='Upcoming',Boss='Upcoming'}
    G.GAME.round_resets.blind_tags={Small='tag_double',Big='tag_rare'}
    G.GAME.blind_on_deck='Small'; G.GAME.current_round.voucher={spawn={}}
    G.CONTROLLER.snap_to=noop; G.ROOM={T={y=0},jiggle=0}; G.hand={}; G.UIDEF={shop=function() return {} end}
    G.shop_vouchers={cards={},config={card_limit=1},T={x=0,y=0,w=1},emplace=function(self,c) self.cards[#self.cards+1]=c end}
    G.shop_jokers.emplace=G.shop_vouchers.emplace
    G.shop_booster.T={x=0,y=0,w=1}; G.shop_booster.emplace=G.shop_vouchers.emplace
    stop_use=noop; attention_text=noop; discover_card=noop; save_run=noop; ease_background_colour_blind=noop
    G.shop=nil; G.STATE_COMPLETE=false; G.load_shop_jokers=nil; G.load_shop_vouchers=nil; G.load_shop_booster=nil
    O.tag_pipeline=dofile(ORACLE_TEST_ROOT..'/prediction/tag_pipeline.lua')(O)
    O.tag_chain_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_chain_validator.lua')(O)
end
local function add_stored(keys)
    for _,key in ipairs(keys) do add_tag(Tag(key)) end
    ORACLE_TAG_DRAIN()
end
ORACLE_TAG_CHAIN_FIXTURE=fixture
local function skip_tag(key)
    local tag=Tag(key,nil,'Small')
    G.FUNCS.skip_blind({UIBox={get_UIE_by_ID=function() return {config={ref_table=tag}} end}})
    ORACLE_TAG_DRAIN()
    return tag
end
local function cards(area)
    local out={}; for _,c in ipairs(area.cards) do out[#out+1]=O.shop_snapshot.card(c) end; return out
end
local function assert_case(key,doubles,slots,setup)
    ORACLE_TEST_CONTEXT.tag=key; ORACLE_TEST_CONTEXT.doubles=doubles; ORACLE_TEST_CONTEXT.slots=slots or 4
    add_stored((function() local a={}; for i=1,doubles do a[i]='tag_double' end; return a end)())
    G.GAME.shop.joker_max=slots or 4
    if setup then setup() end
    local t=Tag(key,nil,'Small')
    local s=O.tag_prediction.capture(key,'Small',t.ability,false,t.config)
    local before=D.encode(s)
    local r=O.tag_prediction.forecast(s)
    eq(D.encode(O.tag_prediction.capture(key,'Small',t.ability,false,t.config)),before,'forecast readonly')
    G.FUNCS.skip_blind({UIBox={get_UIE_by_ID=function() return {config={ref_table=t}} end}})
    ORACLE_TAG_DRAIN()
    local live={}
    for _,tag in ipairs(G.GAME.tags) do if not tag.triggered then live[#live+1]=tag.key end end
    local acquisition={}; for _,tag in ipairs(r.acquisition_state.tag.pending) do acquisition[#acquisition+1]=tag.key end
    eq(live,acquisition,'pending acquisition order')
    for hand,h in pairs(r.acquisition_state.tag.hands) do eq(G.GAME.hands[hand].level,h.level,'Orbital propagated level') end
    if #r.deferred_effects>0 then
        Game.update_shop({},0); ORACLE_TAG_DRAIN()
        eq(cards(G.shop_jokers),r.shop_cards,'initial shop')
        local expected={}; for _,c in ipairs(r.normal_vouchers) do expected[#expected+1]=c.key end
        for _,c in ipairs(r.additional_vouchers) do expected[#expected+1]=c.key end
        local actual={}; for _,c in ipairs(G.shop_vouchers.cards) do actual[#actual+1]=c.config.center.key end
        eq(actual,expected,'normal then additional vouchers')
        for _,row in ipairs(r.rerolls) do
            for _,c in ipairs(G.shop_jokers.cards) do if not s.shop.owned[c.config.center.key] then G.GAME.used_jokers[c.config.center.key]=nil end end
            G.shop_jokers.cards={}
            for i=1,G.GAME.shop.joker_max do G.shop_jokers:emplace(create_card_for_shop(G.shop_jokers)) end
            ORACLE_TAG_DRAIN(); eq(cards(G.shop_jokers),row.cards,'pending tag reroll')
        end
    end
    eq(G.GAME.pseudorandom,r.resulting_shadow_state.game.pseudorandom,'full shop/tag keyed RNG')
    eq(G.GAME.used_jokers,r.resulting_shadow_state.game.used_jokers,'creation availability state')
    comparisons=comparisons+1
    return r
end
test('15 required chain cases across seed sweep with native add_tag, Tag, skip and update_shop',function()
    for seed=ORACLE_TEST_START or 1,(ORACLE_TEST_START or 1)+(ORACLE_TEST_SAMPLES and ORACLE_TEST_SAMPLES.chains or 20)-1 do
        local cases={
            {'tag_double',0},{'tag_rare',1},{'tag_rare',2},{'tag_negative',1},{'tag_polychrome',2},
            {'tag_orbital',1},{'tag_orbital',2},{'tag_voucher',0},{'tag_voucher',1},{'tag_voucher',2},
            {'tag_voucher',2,function() G.GAME.used_vouchers.v_seed_money=true; G.GAME.used_vouchers.v_grabber=true end},
            {'tag_voucher',1,function() G.GAME.used_vouchers.v_overstock_norm=true; G.GAME.used_vouchers.v_clearance_sale=true end},
            {'tag_voucher',2,function() for _,v in ipairs(G.P_CENTER_POOLS.Voucher) do G.GAME.used_vouchers[v.key]=true end end},
            {'tag_rare',2,function() add_stored({'tag_voucher','tag_foil'}) end},
            {'tag_uncommon',2,function()
                G.TEST_SHOWMAN=seed%2==0
                if G.TEST_SHOWMAN then G.jokers.cards={{config={center=G.P_CENTERS.j_ring_master}}} end
                for i,c in ipairs(G.P_JOKER_RARITY_POOLS[2]) do if i%2==0 then G.GAME.used_jokers[c.key]=true end end
            end},
        }
        for n,c in ipairs(cases) do
            fixture('CHAIN'..seed..'_'..n,3)
            G.GAME.modifiers.enable_eternals_in_shop=true; G.GAME.modifiers.enable_perishables_in_shop=true; G.GAME.modifiers.enable_rentals_in_shop=true
            assert_case(c[1],c[2],2+seed%3,c[3])
        end
    end
end)
test('all edition/rarity types and doubled Orbital constructor state are independently propagated',function()
    for _,key in ipairs({'tag_foil','tag_holo','tag_polychrome','tag_negative','tag_uncommon','tag_rare'}) do
        for seed=1,12 do fixture('ALLCHAIN'..key..seed,2); assert_case(key,2,2+seed%3) end
    end
    fixture('ORBITALCONFIGCHAIN',3); add_stored({'tag_double','tag_double'})
    local t=Tag('tag_orbital',nil,'Small'); t.config.levels=6
    local r=O.tag_prediction.get(t.key,'Small',t.ability,t.config)
    G.FUNCS.skip_blind({UIBox={get_UIE_by_ID=function() return {config={ref_table=t}} end}}); ORACLE_TAG_DRAIN()
    eq(r.immediate_effects[1].levels_added,6); eq(r.immediate_effects[2].levels_added,3)
    eq(r.immediate_effects[3].resulting_level,16); eq(G.GAME.hands.Pair.level,16)
end)
test('normal voucher survives separately; generated extras do not satisfy upgrade prerequisites',function()
    fixture('VOUCHER_PRESELECTED')
    G.GAME.current_round.voucher={'v_paint_brush',spawn={v_paint_brush=true}}
    local r=assert_case('tag_voucher',2,4)
    eq(r.normal_vouchers[1].key,'v_paint_brush')
    assert(not r.resulting_shadow_state.game.used_vouchers.v_paint_brush)
    for _,v in ipairs(r.additional_vouchers) do assert(v.key~='v_palette') end
end)
test('sequential acquisition API preserves doubles and rolls new Orbital only once before copying',function()
    fixture('ACQUIRE_API')
    local s=O.tag_prediction.capture('tag_double','Small')
    local a=O.tag_prediction.forecast(s)
    local b=O.tag_prediction.simulate_tag_acquisition(a.acquisition_state,{key='tag_double'})
    local c=O.tag_prediction.simulate_tag_acquisition(b.acquisition_state,{key='tag_orbital'})
    eq(#c.expanded_tags,3); assert(c.immediate_effects[1].hand_key==c.immediate_effects[3].hand_key)
    local polls=0; for _,v in ipairs(c.details.trace) do if v.key=='orbital' then polls=polls+1 end end
    eq(polls,1); eq(c.immediate_effects[3].resulting_level,c.immediate_effects[1].current_level+9)
    assert(#G.GAME.tags==0 and not G.GAME.pseudorandom.orbital)
end)
test('native acquisition and resolution validators bind every copy and Voucher callback',function()
    for _,key in ipairs({'tag_double','tag_orbital','tag_rare','tag_voucher','tag_negative'}) do
        fixture('CHAINVALIDATE'..key,3)
        O.tag_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_validator.lua')(O); O.tag_validator.install()
        O.tag_chain_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_chain_validator.lua')(O); O.tag_chain_validator.install()
        local r=assert_case(key,2,4)
        assert(O.validator.counts.MISMATCH==0,key..' validator mismatch')
        local chain=O.tag_chain_validator.chains[1]
        assert(chain and chain.acquired and #chain.instances==#r.expanded_tags)
        for id in pairs(chain.expected) do assert(chain.actual[id],key..' missing '..id) end
    end
end)
test('composed acquisitions keep distinct identities and consumed normal vouchers stay absent',function()
    fixture('CHAIN_IDENTITIES')
    local a=O.tag_prediction.forecast(O.tag_prediction.capture('tag_rare','Small'))
    local b=O.tag_prediction.simulate_tag_acquisition(a.acquisition_state,{key='tag_voucher'})
    local ids={}
    for _,e in ipairs(b.effects) do assert(not ids[e.id],'duplicate effect ID'); ids[e.id]=true end
    assert(ids['stored:1'] and ids.new)
    fixture('CHAIN_PURCHASED_NORMAL')
    G.GAME.current_round.voucher={'v_paint_brush',spawn={v_paint_brush=false}}
    G.GAME.used_vouchers.v_paint_brush=true
    local r=assert_case('tag_voucher',2,3)
    eq(#r.normal_vouchers,0); eq(#r.additional_vouchers,3)
end)
test('held Double tooltip is read-only and collection tooltips do not invent acquisitions',function()
    fixture('CHAIN_HELD_TOOLTIP'); add_stored({'tag_double','tag_double'})
    local original=generate_card_ui
    generate_card_ui=function() return {main={{{native=true}}}} end
    O.tag_ui.install()
    local held=G.GAME.tags[1]; held.tag_sprite={}
    local before=D.encode(O.tag_prediction.capture('tag_double','Small'))
    held:get_uibox_table()
    local lines=held.tag_sprite.ability_UIBox_table.main
    assert(lines[1][1].native and #lines==4)
    assert(lines[3][1].config.text:match(': 2$'))
    eq(D.encode(O.tag_prediction.capture('tag_double','Small')),before)
    local collection=Tag('tag_double',true); collection.tag_sprite={}
    collection:get_uibox_table()
    assert(#collection.tag_sprite.ability_UIBox_table.main==1)
    generate_card_ui=original
end)
test('held native Doubles keep current shop and ten rerolls available at 2/3/4 slots',function()
    for seed=1,6 do for limit=2,4 do for doubles=1,2 do
        fixture(seed==1 and 'CZZXRBWB' or ('DOUBLE_SHOP_'..seed),2)
        local keys={}; for i=1,doubles do keys[i]='tag_double' end; add_stored(keys)
        G.GAME.shop.joker_max=limit
        if limit>=3 then G.GAME.used_vouchers.v_overstock_norm=true end
        if limit==4 then G.GAME.used_vouchers.v_overstock_plus=true end
        Game.update_shop({},0); ORACLE_TAG_DRAIN()
        -- Simulate buying one actual offered card; availability and empty slot
        -- must be read from the updated live state, not the previous forecast.
        local purchased=table.remove(G.shop_jokers.cards,1)
        G.jokers.cards[#G.jokers.cards+1]=purchased
        local s=O.shop_snapshot.capture(G,SMODS)
        local before=D.encode(s)
        local rows,details=O.shop_prediction.forecast(s,10)
        O.controller.invalidate()
        local visible,err=O.controller.shop_forecast()
        assert(visible,err)
        eq(visible[1].cards,rows[1].cards,'shop page current goods')
        eq(#rows[1].cards,limit-1,'purchased slot remains empty')
        eq(D.encode(O.shop_snapshot.capture(G,SMODS)),before,'shop preview is read-only')
        for n=1,10 do
            for _,c in ipairs(G.shop_jokers.cards) do
                if not s.shop.owned[c.config.center.key] then G.GAME.used_jokers[c.config.center.key]=nil end
            end
            G.shop_jokers.cards={}
            for i=1,limit do G.shop_jokers:emplace(create_card_for_shop(G.shop_jokers)) end
            ORACLE_TAG_DRAIN()
            eq(cards(G.shop_jokers),rows[n+1].cards,'Double shop reroll '..n)
            eq(#rows[n+1].cards,limit,'full Overstock slots')
        end
        eq(G.GAME.pseudorandom,details.rng_after,'ten rerolls complete keyed RNG')
        eq(#G.GAME.tags,doubles,'Doubles remain held')
        for _,tag in ipairs(G.GAME.tags) do assert(not tag.triggered,'shop consumed Double') end
    end end end
end)
test('shop Double exception rejects custom callbacks and pending goods-changing tags',function()
    fixture('DOUBLE_SHOP_GUARDS',2); add_stored({'tag_double'})
    local function blocked()
        local s=O.shop_snapshot.capture(G,SMODS)
        assert(s.shop.unsupported)
        assert(not pcall(O.shop_prediction.forecast,s,3))
    end
    SMODS.Tags.tag_double={apply=function() error('must not execute') end}; blocked()
    SMODS.Tags.tag_double=nil
    G.P_TAGS.tag_double.mod={id='custom'}; blocked(); G.P_TAGS.tag_double.mod=nil
    G.GAME.tags[1].config.type='store_joker_create'; blocked()
    G.GAME.tags={}; add_stored({'tag_double','tag_rare'}); blocked()
    G.GAME.tags={}; add_stored({'tag_double'})
    assert(not O.shop_snapshot.capture(G,SMODS).shop.unsupported)
end)
print('TAG CHAINS: '..passed..' tests passed; '..comparisons..' native chain scenarios')
