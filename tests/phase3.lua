local O,D=ORACLE,ORACLE.data
local count,passed=0,0
local function test(name,fn) if ORACLE_FIXTURES_ONLY then return end; ORACLE_TEST_CASE=name; fn(); passed=passed+1; print('PASS '..name) end
local function eq(a,b,label) assert(D.encode(a)==D.encode(b),(label or 'mismatch')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
-- Rendering is stubbed here; creation/ability/pool/rarity/edition functions below
-- are extracted verbatim from the actual installed source.
Card={}
function Card:set_sprites() end
function Card:set_cost() end
function Card:start_materialize() end
function Card:set_edition(e)
    self.edition=e and {key=e,[e:sub(3)]=true} or nil
end
setmetatable(Card,{__call=function(_,x,y,w,h,front,center,params)
    local c=setmetatable({params=params,T={x=x,y=y,w=w,h=h},original_T={x=x,y=y,w=w,h=h},
        config={center=center},children={},base={}}, {__index=Card})
    c:set_ability(center,true)
    for k,v in pairs(G.P_CARDS) do if v==front then c.config.card_key=k end end
    return c
end})
SMODS.PokerHands={}
SMODS.enh_cache={write=function() end}
SMODS.clean_up_children=function() end
SMODS.get_ability_reset_keys=function() return {} end
SMODS.find_card=function(key)
    local out={}; for _,area in ipairs({G.jokers,G.consumeables}) do
        for _,c in ipairs(area.cards) do if c.config.center.key==key then out[#out+1]=c end end
    end
    return out
end
SMODS.merge_defaults=function(a,b) local out={}; for k,v in pairs(b) do out[k]=v end; for k,v in pairs(a) do out[k]=v end; return out end
SMODS.calculate_context=function() return {} end
SMODS.Sticker={obj_buffer={'eternal','perishable','rental'}}
SMODS.Stickers={eternal={},perishable={},rental={}}
SMODS.ConsumableType={obj_buffer={'Tarot','Planet','Spectral'}}
SMODS.ConsumableTypes={Tarot={},Planet={},Spectral={}}
SMODS.Rarities={Common={},Uncommon={},Rare={},Legendary={}}
SMODS.remove_pool=function() error('Unexpected custom rarity path') end
SMODS.has_enhancement=function(c,k) return c.config.center.key==k end
function check_for_unlock() end
function create_shop_card_ui() end
local function fixture(seed,ante)
    ORACLE_PHASE2_FIXTURE(seed,ante)
    G.FUNCS={}; G.OVERLAY_MENU=nil; G.STATES={SHOP=1,ROUND_EVAL=2,SELECTING_HAND=3}; G.STATE=1
    G.CARD_W=1; G.CARD_H=1.4; G.CONTROLLER={locks={}}
    G.E_MANAGER={add_event=function() end}
    G.P_CARDS={S_A={suit='Spades',value='Ace'},H_K={suit='Hearts',value='King'},D_2={suit='Diamonds',value='2'}}
    SMODS.Ranks={Ace={},King={},['2']={}}; SMODS.Suits={Spades={},Hearts={},Diamonds={}}
    G.P_JOKER_RARITY_POOLS={[1]={},[2]={},[3]={},[4]={}}
    G.shop_jokers={cards={},T={x=0,y=0,w=2,h=2}}
    G.shop_booster={cards={}}
    G.GAME.shop={joker_max=2}; G.GAME.tags={}; G.GAME.selected_back={pos={x=0,y=0}}
    G.GAME.hands={['High Card']={played=1,visible=true},Pair={played=1,visible=true},['Flush Five']={played=0,visible=false}}
    SMODS.PokerHands={['High Card']={},Pair={},['Flush Five']={}}
    for _,c in pairs(G.P_CENTERS) do
        if c.set=='Planet' then G.GAME.hands[c.config.hand_type]=G.GAME.hands[c.config.hand_type] or {played=1,visible=true}; SMODS.PokerHands[c.config.hand_type]={} end
    end
    G.GAME.joker_rate=20; G.GAME.tarot_rate=4; G.GAME.planet_rate=4
    G.GAME.playing_card_rate=0; G.GAME.spectral_rate=1; G.GAME.edition_rate=1
    G.GAME.starting_params.boosters_in_shop=2; G.GAME.first_shop_buffoon=true
    G.GAME.current_round.used_packs={}; G.GAME.perishable_rounds=5
    G.playing_cards={{config={center={key='m_steel'}}}}
    for _,kind in ipairs({'Tarot','Planet','Spectral','Enhanced','Booster','Edition'}) do G.P_CENTER_POOLS[kind]={} end
    SMODS.Edition={take_ownership=function(_,k,v)
        local c=G.P_CENTERS['e_'..k] or {key='e_'..k,set='Edition'}
        for name,value in pairs(v) do c[name]=value end
        G.P_CENTERS[c.key]=c
    end}
    dofile(ORACLE_TEST_SOURCE..'/edition_truth.lua')
    for _,c in pairs(G.P_CENTERS) do
        if c.set=='Joker' then
            c.eternal_compat=c.eternal_compat~=false; c.perishable_compat=c.perishable_compat~=false
            table.insert(G.P_JOKER_RARITY_POOLS[c.rarity],c)
        elseif G.P_CENTER_POOLS[c.set] then table.insert(G.P_CENTER_POOLS[c.set],c) end
    end
    for _,p in pairs(G.P_CENTER_POOLS) do table.sort(p,function(a,b) return (a.order or 0)<(b.order or 0) end) end
    for _,p in pairs(G.P_JOKER_RARITY_POOLS) do table.sort(p,function(a,b) return a.order<b.order end) end
    SMODS.ObjectTypes.Joker={rarities={{key='Common',weight=0.7},{key='Uncommon',weight=0.25},{key='Rare',weight=0.05},{key='Legendary',weight=0}}}
    O.prediction_fault=nil
end
fixture('INIT',1)
dofile(ORACLE_TEST_SOURCE..'/shop_truth.lua')
local real_create,real_pack=create_card_for_shop,get_pack
ORACLE_PHASE3_FIXTURE=fixture
ORACLE_TRUTH_CREATE_CARD=create_card
local function compare()
    local s=O.shop_snapshot.capture(G,SMODS)
    local before=D.encode(s)
    local expected,detail=O.ante_prediction.run(s,O.shop_prediction.card)
    assert(D.encode(O.shop_snapshot.capture(G,SMODS))==before,'Simulation mutated game')
    local actual=real_create(G.shop_jokers)
    eq(O.shop_snapshot.card(actual),expected,'shop card')
    eq(G.GAME.pseudorandom,detail.rng_after,'shop RNG')
    G.shop_jokers.cards[#G.shop_jokers.cards+1]=actual
    count=count+1
end
test('seed sweep: real shop/create_card/set_ability/rarity/edition/stickers agree',function()
    for seed=ORACLE_TEST_START or 1,(ORACLE_TEST_START or 1)+(ORACLE_TEST_SAMPLES and ORACLE_TEST_SAMPLES.shop or 80)-1 do
        fixture('SHOP'..seed,seed%8+1)
        G.GAME.modifiers.enable_eternals_in_shop=true
        G.GAME.modifiers.enable_perishables_in_shop=true
        G.GAME.modifiers.enable_rentals_in_shop=true
        G.GAME.edition_rate=seed%4+1
        for i=1,12 do compare() end
    end
end)
test('Illusion playing cards, enhancement gates, softlocks and Showman agree',function()
    for seed=1,20 do
        fixture('ILLUSION'..seed,4)
        G.GAME.playing_card_rate=40; G.GAME.used_vouchers.v_illusion=true
        G.GAME.hands['Flush Five'].played=0
        if seed%2==0 then
            G.jokers.cards={{config={center=G.P_CENTERS.j_ring_master}}}; G.TEST_SHOWMAN=true
        end
        for i=1,12 do compare() end
    end
end)
test('sequential rerolls match after removing prior shop candidates',function()
    for seed=1,20 do
        fixture('REROLL'..seed,3)
        compare(); compare()
        local rows=O.shop_prediction.forecast(O.shop_snapshot.capture(G,SMODS),10)
        for n=1,10 do
            for _,c in ipairs(G.shop_jokers.cards) do G.GAME.used_jokers[c.config.center.key]=nil end
            G.shop_jokers.cards={}
            for i=1,2 do G.shop_jokers.cards[i]=real_create(G.shop_jokers) end
            local cards={}; for i,c in ipairs(G.shop_jokers.cards) do cards[i]=O.shop_snapshot.card(c) end
            eq(cards,rows[n+1].cards,'reroll '..n); count=count+2
        end
    end
end)
test('Booster types match actual get_pack; first Buffoon cover is explicitly unknown',function()
    fixture('PACKS',2)
    for i=1,400 do
        local s=O.shop_snapshot.capture(G,SMODS)
        local expected,d=O.ante_prediction.run(s,function(sh,rng) return O.shop_prediction.pack(sh,rng,'shop_pack') end)
        local actual=real_pack('shop_pack')
        eq(actual.key,expected.key); eq(G.GAME.pseudorandom,d.rng_after); count=count+1
    end
    G.GAME.first_shop_buffoon=nil
    local s=O.shop_snapshot.capture(G,SMODS)
    local p=O.ante_prediction.run(s,O.shop_prediction.pack)
    assert(p.variant_unknown and not G.GAME.first_shop_buffoon)
end)
test('Boss rerolls use actual legacy boss path including showdown and prescription',function()
    for seed=1,40 do
        fixture('BOSSREROLL'..seed,seed%8+1)
        if seed%3==0 then G.GAME.perscribed_bosses[G.GAME.round_resets.ante]='bl_hook' end
        local rows=O.ante_prediction.rerolls(O.snapshot.capture(G,SMODS),10)
        for i=1,10 do eq(get_new_boss(),rows[i]); count=count+1 end
    end
end)
test('unsupported tags and timing fail closed',function()
    fixture('GUARD',3)
    G.GAME.tags={{key='tag_rare'}}
    assert(not pcall(O.shop_prediction.forecast,O.shop_snapshot.capture(G,SMODS),3))
    G.GAME.tags={}; G.STATE=G.STATES.SELECTING_HAND
    assert(not pcall(O.shop_prediction.forecast,O.shop_snapshot.capture(G,SMODS),3))
    G.STATE=G.STATES.ROUND_EVAL
    assert(O.shop_prediction.forecast(O.shop_snapshot.capture(G,SMODS),3))
end)
test('live shop validation preserves creation and verifies keyed RNG',function()
    fixture('LIVEVALIDATE',4)
    O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
    O.controller=dofile(ORACLE_TEST_ROOT..'/controller.lua')(O)
    O.controller.install()
    create_card_for_shop(G.shop_jokers)
    get_pack('shop_pack')
    assert(O.validator.counts.MATCH==2 and O.validator.counts.MISMATCH==0)
end)
test('held Investment Juggle and Double preserve native shop and three rerolls at 2 3 4 slots',function()
    SMODS.Tags=SMODS.Tags or {}
    local oldtag=Tag; Tag={}; dofile(ORACLE_TEST_SOURCE..'/inert_tag_truth.lua')
    local native_apply=Tag.apply_to_run; Tag=oldtag
    local replay=os.getenv('ORACLE_REPLAY_SAVE')
    local saved=replay and dofile(replay) or nil
    for seed=1,20 do for _,key in ipairs({'tag_investment','tag_juggle','tag_double'}) do
        fixture(seed==1 and 'HTS25CEP' or 'INERT'..seed,1)
        if seed==1 and saved then G.GAME.pseudorandom=D.copy(saved.GAME.pseudorandom) end
        local proto=G.P_TAGS[key]
        local tag={key=key,name=proto.name,config=D.copy(proto.config),apply_to_run=native_apply}
        G.GAME.tags={tag}; G.GAME.shop.joker_max=2+seed%3
        for i=1,G.GAME.shop.joker_max do compare() end
        local s=O.shop_snapshot.capture(G,SMODS); assert(not s.shop.unsupported)
        local rows=O.shop_prediction.forecast(s,3)
        for reroll=1,3 do
            for _,c in ipairs(G.shop_jokers.cards) do G.GAME.used_jokers[c.config.center.key]=nil end
            G.shop_jokers.cards={}
            for i=1,G.GAME.shop.joker_max do G.shop_jokers.cards[i]=real_create(G.shop_jokers) end
            local actual={}; for _,c in ipairs(G.shop_jokers.cards) do actual[#actual+1]=O.shop_snapshot.card(c) end
            eq(actual,rows[reroll+1].cards); count=count+#actual
        end
        assert(G.GAME.tags[1]==tag and not tag.triggered,'shop must not consume held tags')
        if key=='tag_investment' then
            G.C=G.C or {}
            G.GAME.last_blind={boss=true}; tag.yep=function() end
            eq(native_apply(tag,{type='eval'}).dollars,25); assert(tag.triggered)
        end
    end end
end)
test('inert tag exception rejects custom callbacks and changed trigger types',function()
    fixture('INERTGUARD',1)
    local tag={key='tag_investment',config={type='eval'}}; G.GAME.tags={tag}
    assert(not O.shop_snapshot.capture(G,SMODS).shop.unsupported)
    tag.config.type='store_joker_create'; assert(O.shop_snapshot.capture(G,SMODS).shop.unsupported)
    tag.config.type='eval'; SMODS.Tags.tag_investment={apply=function() error('must not run') end}
    assert(O.shop_snapshot.capture(G,SMODS).shop.unsupported); SMODS.Tags.tag_investment=nil
    G.P_TAGS.tag_investment.mod={id='custom'}; assert(O.shop_snapshot.capture(G,SMODS).shop.unsupported)
    G.P_TAGS.tag_investment.mod=nil
end)
print(string.format('PHASE3: %d tests passed; %d comparisons',passed,count))
