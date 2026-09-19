local O,D=ORACLE,ORACLE.data
local passed,count,souls,holes=0,0,0,0
local function test(n,f) if ORACLE_FIXTURES_ONLY then return end; ORACLE_TEST_CASE=n; f(); passed=passed+1; print('PASS '..n) end
local function eq(a,b,n) assert(D.encode(a)==D.encode(b),(n or 'mismatch')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
local function fixture(seed,ante)
    ORACLE_PHASE3_FIXTURE(seed,ante)
    create_card=ORACLE_TRUTH_CREATE_CARD
    SMODS.Consumable={legendaries={}}
    G.handlist={}; for k in pairs(G.GAME.hands) do G.handlist[#G.handlist+1]=k end; table.sort(G.handlist)
    G.P_CENTER_POOLS.Seal={}; G.P_SEALS={}
    for _,k in ipairs({'Gold','Red','Blue','Purple'}) do
        local seal={key=k,set='Seal',weight=10}; G.P_SEALS[k]=seal
        G.P_CENTER_POOLS.Seal[#G.P_CENTER_POOLS.Seal+1]=seal
    end
    G.pack_cards={cards={},T={x=0,y=0,w=8,h=2}}
    G.jokers.T={x=0,y=0,w=8,h=2}
    SMODS.Booster={take_ownership_by_kind=function(_,kind,v)
        for _,c in ipairs(G.P_CENTER_POOLS.Booster) do if c.kind==kind then
            c.create_card=v.create_card
        end end
    end}
    dofile(ORACLE_TEST_SOURCE..'/booster_truth.lua')
    dofile(ORACLE_TEST_SOURCE..'/seal_truth.lua')
    function Card:set_seal(key) self.seal=key end
    function unlock_card() end -- Achievement persistence is outside generator truth.
    function discover_card() end
end
local function compare(pack)
    ORACLE_TEST_CONTEXT.pack=pack.key
    local snapshot=O.pack_prediction.capture(G,SMODS)
    local before=D.encode(snapshot)
    local expected,details=O.pack_prediction.forecast(snapshot,{key=pack.key})
    assert(D.encode(O.pack_prediction.capture(G,SMODS))==before,'Pack preview mutated live state')
    local size=math.max(1,pack.config.extra+(G.GAME.modifiers.booster_size_mod or 0))
    local actual={}
    for i=1,size do
        local args=pack:create_card({ability=pack.config},i)
        local c=SMODS.create_card(args)
        actual[i]=O.shop_snapshot.card(c)
        G.pack_cards.cards[i]=c
        if expected[i].legendary then
            souls=souls+1
            -- This branch is tested below after ALL candidates have generated.
        end
        if c.config.center.key=='c_black_hole' then holes=holes+1 end
    end
    local expected_plain=D.copy(expected)
    for _,c in ipairs(expected_plain) do c.legendary=nil end
    eq(actual,expected_plain,'pack '..pack.key)
    eq(G.GAME.pseudorandom,details.rng_after,'pack keyed RNG')
    for _,c in ipairs(expected) do if c.legendary then
        local legendary=create_card('Joker',G.jokers,true,nil,nil,nil,nil,'sou')
        eq(legendary.config.center.key,c.legendary,'Soul Legendary')
        -- Independent immediate-use branch; do not consume another Soul here.
        break
    end end
    count=count+size
end
test('all five native pack types, Omen Globe, Telescope, edition, seals and stickers',function()
    for seed=ORACLE_TEST_START or 1,(ORACLE_TEST_START or 1)+(ORACLE_TEST_SAMPLES and ORACLE_TEST_SAMPLES.packs or 60)-1 do
        for _,kind in ipairs({'Arcana','Celestial','Spectral','Standard','Buffoon'}) do
            fixture('PACK4_'..seed,seed%8+1)
            G.GAME.used_vouchers.v_omen_globe=seed%2==0
            G.GAME.used_vouchers.v_telescope=seed%3==0
            G.GAME.modifiers.enable_eternals_in_shop=true
            G.GAME.modifiers.enable_perishables_in_shop=true
            G.GAME.modifiers.enable_rentals_in_shop=true
            G.GAME.modifiers.booster_size_mod=seed%2
            G.GAME.edition_rate=seed%4+1
            for _,p in ipairs(G.P_CENTER_POOLS.Booster) do if p.kind==kind and p.name:find('Mega') then compare(p); break end end
        end
    end
end)
test('Soul, Black Hole and Legendary selection occur and match real generators',function()
    for seed=1,400 do
        if souls>2 and holes>2 then break end
        fixture('SOUL4_'..seed,4)
        compare(G.P_CENTERS.p_spectral_mega_1)
    end
    assert(souls>0 and holes>0,'Special card cases were not exercised')
end)
test('pack/Soul UI branch does not advance the global math RNG',function()
    fixture('READONLY4',4)
    math.randomseed(4321); local expected=math.random()
    math.randomseed(4321)
    O.pack_prediction.forecast(O.pack_prediction.capture(G,SMODS),{key='p_arcana_mega_1'})
    assert(math.random()==expected)
    G.jokers.cards={{config={center=G.P_CENTERS.j_hallucination}}}
    assert(not pcall(O.pack_prediction.forecast,O.pack_prediction.capture(G,SMODS),{key='p_arcana_mega_1'}))
end)
test('CZZXRBWB Anaglyph Double and settled Holographic Tag do not block any native pack type',function()
    for _,held in ipairs({'tag_investment','tag_juggle','tag_double','tag_uncommon','tag_rare','tag_foil','tag_holo',
        'tag_polychrome','tag_negative','tag_voucher','tag_orbital'}) do
        for _,kind in ipairs({'Arcana','Celestial','Spectral','Standard','Buffoon'}) do
            fixture('CZZXRBWB',2)
            G.GAME.stake=1
            G.GAME.tags={{key=held},{key='tag_holo',triggered=true}}
            G.jokers.cards={{config={center=G.P_CENTERS.j_half}},
                {config={center=G.P_CENTERS.j_to_the_moon},edition={key='e_holo',holo=true}}}
            local before=D.encode(G.GAME.tags)
            local s=O.pack_prediction.capture(G,SMODS)
            assert(not s.shop.unsupported and not s.shop.pack_unsupported,'inert tag blocked packs: '..held)
            -- Pending shop effects still use their separate shop protection.
            assert(O.shop_snapshot.capture(G,SMODS).shop.unsupported)
            for _,p in ipairs(G.P_CENTER_POOLS.Booster) do if p.kind==kind then compare(p); break end end
            eq(D.encode(G.GAME.tags),before,'held/triggered tags mutated by pack generation')
        end
    end
end)
test('pack tag exception keeps unknown tags, custom callbacks and unrelated effects closed',function()
    fixture('CZZXRBWB',2)
    local function blocked()
        local s=O.pack_prediction.capture(G,SMODS)
        assert(s.shop.pack_unsupported)
        assert(not pcall(O.pack_prediction.forecast,s,{key='p_arcana_normal_1'}))
    end
    G.GAME.tags={{key='tag_unknown'}}; blocked()
    G.GAME.tags={{key='tag_double'}}
    SMODS.Tags={tag_double={apply=function() error('must never execute live callback') end}}; blocked()
    SMODS.Tags={}
    G.P_TAGS.tag_double.mod={id='custom'}; blocked(); G.P_TAGS.tag_double.mod=nil
    G.jokers.cards={{config={center=G.P_CENTERS.j_hallucination}}}; blocked()
end)
test('Booster names use shared Other localization keys',function()
    local old=localize
    local seen
    localize=function(args) seen=args; return '标准包' end
    assert(O.text.name('Booster',{key='p_standard_normal_2'})=='标准包')
    assert(seen.set=='Other' and seen.key=='p_standard_normal')
    localize=old
end)
test('native Joker, Misprint and Booster descriptions preserve live RNG and environments',function()
    fixture('TOOLTIPS4',4)
    dofile(ORACLE_TEST_SOURCE..'/tooltip_truth.lua')
    SMODS.compat_0_9_8={generate_UIBox_ability_table_card='sentinel'}
    SMODS.UndiscoveredCompat={}
    G.UIT={T=1,O=2,R=3,C=4}
    G.C=setmetatable({UI={TEXT_DARK={}}},{__index=function() return {} end})
    G.UIDEF={card_h_popup=function(c) return c.ability_UIBox_table end}
    local old_localize=localize
    localize=function(a)
        if type(a)~='table' then return tostring(a) end
        local node={key=a.key,vars=D.copy(a.vars or {})}
        if a.nodes then a.nodes[#a.nodes+1]={node} end
        return {node}
    end
    DynaText=function(a) assert(not a.random_element,'Random animation not isolated'); return a end
    SMODS.get_probability_vars=function() error('live probability callback invoked') end
    SMODS.calculate_context=function() error('live gameplay context invoked') end
    local native,environment=Card.generate_UIBox_ability_table,getfenv(Card.generate_UIBox_ability_table)
    for _,key in ipairs({'j_joker','j_blueprint','j_misprint','j_space','p_standard_normal_2'}) do
        local card=create_card(G.P_CENTERS[key].set,G.shop_jokers,nil,nil,true,false,key,'test')
        card.bypass_lock=true; card.bypass_discovery_ui=true; card.record={key=key}
        local before=D.encode(G.GAME)
        math.randomseed(542); local expected=math.random(); math.randomseed(542)
        local ui=O.tooltip.build(card)
        assert(#ui.main>0,'Missing native description '..key)
        assert(math.random()==expected and D.encode(G.GAME)==before)
        assert(SMODS.compat_0_9_8.generate_UIBox_ability_table_card=='sentinel')
    end
    assert(Card.generate_UIBox_ability_table==native and getfenv(native)==environment)
    localize=old_localize
    SMODS.calculate_context=function() return {} end
end)

test('HUD shortcut and F8 are gated during text input and overlays',function()
    fixture('SHORTCUT4',1)
    local keybind,opens=nil,0
    SMODS.Keybind=function(k) keybind=k end
    create_UIBox_HUD=function() return {nodes={{nodes={{config={button='options',minh=1.75}}}}}} end
    G.UIT={R=1,T=2}; G.C={BLUE={},UI={TEXT_LIGHT={}}}
    G.FUNCS.oracle_open=function() opens=opens+1 end
    O.shortcut.install()
    local tree=create_UIBox_HUD()
    assert(tree.nodes[1].nodes[2].config.button=='oracle_open')
    assert(keybind.key_pressed=='f8')
    keybind.action(); assert(opens==1)
    G.CONTROLLER.text_input_hook={}; keybind.action(); assert(opens==1)
    G.CONTROLLER.text_input_hook=nil; G.OVERLAY_MENU={}; keybind.action(); assert(opens==1)
    G.OVERLAY_MENU=nil; O.config.enabled=false; keybind.action(); assert(opens==1)
    O.config.enabled=true
end)
print(string.format('PHASE4: %d tests passed; %d candidate comparisons; Soul=%d; Black Hole=%d',passed,count,souls,holes))
