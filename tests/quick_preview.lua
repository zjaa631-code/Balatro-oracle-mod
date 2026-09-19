local O,D=ORACLE,ORACLE.data
local groups=0
local function eq(a,b) assert(D.encode(a)==D.encode(b),'Expected '..D.encode(b)..' Actual '..D.encode(a)) end
local function test(n,f) ORACLE_TEST_CASE=n; f(); groups=groups+1; print('PASS '..n) end
local function fixture(seed,key)
    local c=ORACLE_CONSUMABLE_FIXTURE(seed,key)
    O.quick=dofile(ORACLE_TEST_ROOT..'/prediction/quick.lua')(O)
    O.quick_ui=dofile(ORACLE_TEST_ROOT..'/ui/quick_preview.lua')(O)
    O.config.show_draw_order=true; O.config.show_packs=true
    G.C.ORANGE={}; G.C.UI={TEXT_DARK={}}; G.UIT={T=1,R=2}
    SMODS.OPENED_BOOSTER=nil
    return c
end
test('Quick Tarot results match actual native uses over 80 seeds without advancing live RNG',function()
    for seed=1,80 do for _,key in ipairs({'c_judgement','c_high_priestess','c_emperor','c_wheel_of_fortune'}) do
        local c=fixture('QUICK'..seed,key)
        local before=O.consumables.capture(G,SMODS,c); local encoded=D.encode(before)
        local _,trace=O.engine.predict('consumable',before)
        math.randomseed(456); local expected_random=math.random(); math.randomseed(456)
        local r=O.quick.get('consumable',c)
        local lines=O.quick_ui.lines('consumable',c); assert(#lines>=2)
        eq(math.random(),expected_random); eq(O.consumables.capture(G,SMODS,c),before)
        eq(D.encode(before),encoded); eq(O.quick.count,1)
        G.consumeables.cards={}; c:use_consumeable(G.consumeables); ORACLE_CONSUMABLE_DRAIN()
        eq(O.consumables.observe(before,G),O.consumables.expected(r)); eq(G.GAME.pseudorandom,trace.rng_after)
    end end
end)
test('Quick pack contains every native candidate including size and detached cache',function()
    for seed=1,20 do for _,key in ipairs({'p_arcana_mega_1','p_celestial_normal_1','p_buffoon_mega_1','p_standard_mega_1','p_spectral_normal_1'}) do
        fixture('QUICKPACK'..seed,'c_judgement')
        G.STATE=G.STATES.SHOP; SMODS.OPENED_BOOSTER=nil
        G.P_CENTER_POOLS.Seal={{key='Red',weight=10},{key='Blue',weight=10},{key='Gold',weight=10},{key='Purple',weight=10}}
        local p=G.P_CENTERS[key]; assert(p,key)
        local card={config={center=p},ability={extra=p.config.extra},area=G.shop_booster}
        local s=O.pack_prediction.capture(G,SMODS)
        local expected=O.engine.predict('pack',s,{key=key,size=p.config.extra})
        local r=O.quick.get('pack',card); eq(r.cards,expected)
        eq(O.pack_prediction.capture(G,SMODS),s)
        r.cards[1].key='corrupted'; eq(O.quick.get('pack',card).cards,expected); eq(O.quick.count,1)
        assert(#O.quick_ui.lines('pack',card)==1+#expected)
    end end
end)
test('native pack close preserves stale metadata while next-shop hover and page agree',function()
    local old_save,old_background=save_run,ease_background_colour_blind
    save_run=function() end; ease_background_colour_blind=function() end
    for seed=1,5 do for _,key in ipairs({'p_arcana_mega_1','p_celestial_normal_1','p_buffoon_mega_1','p_standard_mega_1','p_spectral_normal_1'}) do
        fixture('QUICKCLOSE'..seed,'c_judgement')
        G.STATES.SMODS_BOOSTER_OPENED=99; G.STATE=99
        local old={config={center=G.P_CENTERS.p_buffoon_normal_1}}
        SMODS.OPENED_BOOSTER=old
        G.booster_pack={alignment={offset={}},remove=function() end}
        G.ROOM={T={y=0}}; G.CONTROLLER.interrupt={}
        G.GAME.PACK_INTERRUPT=G.STATES.SHOP
        G.FUNCS.draw_from_hand_to_deck=function() end
        -- Deliberately leave an old candidate area, too: closed metadata must
        -- never make the full page display a previous pack's cards.
        G.pack_cards.cards={G.consumeables.cards[1]}
        G.pack_cards.remove=function() end
        dofile(ORACLE_TEST_SOURCE..'/quick_pack_close_truth.lua')
        G.FUNCS.end_consumeable(nil,1); ORACLE_CONSUMABLE_DRAIN()
        assert(G.STATE==G.STATES.SHOP and not G.booster_pack)
        assert(SMODS.OPENED_BOOSTER==old,'native lifecycle must retain the reference')
        G.P_CENTER_POOLS.Seal={{key='Red',weight=10},{key='Blue',weight=10},{key='Gold',weight=10},{key='Purple',weight=10}}
        local p=G.P_CENTERS[key]
        local card={config={center=p},ability={extra=p.config.extra},area=G.shop_booster}
        G.shop_booster.cards={card}
        local s=O.pack_prediction.capture(G,SMODS)
        assert(not s.shop.pack_open and not s.shop.opened_pack and #s.shop.opened_cards==0)
        local expected=O.pack_prediction.forecast(s,{key=key})
        local old_ui,old_area,old_cycle=O.ui,O.preview_card.area,create_option_cycle
        local rendered={}
        O.ui={message=function(k) return k end,row=function(n) return n end,page=function(n) return n end,text=function(t) return t end}
        O.preview_card.area=function(cards) rendered[#rendered+1]=D.copy(cards); return {} end
        create_option_cycle=function(t) return t end
        dofile(ORACLE_TEST_ROOT..'/ui/packs.lua')(O).definition()
        O.ui=old_ui; O.preview_card.area=old_area; create_option_cycle=old_cycle
        eq(rendered[1],{{key=key,set='Booster'}})
        eq(rendered[2],expected)
        math.randomseed(654); local real_random=math.random(); math.randomseed(654)
        eq(O.quick.get('pack',card).cards,expected)
        eq(math.random(),real_random); eq(O.pack_prediction.capture(G,SMODS),s)
        assert(SMODS.OPENED_BOOSTER==old,'prediction must not clear real SMODS state')
        assert(#O.quick_ui.lines('pack',card)==#expected+1)
        for i=1,10 do eq(O.quick.get('pack',card).cards,expected) end
        eq(O.quick.count,1)
    end end
    save_run=old_save; ease_background_colour_blind=old_background
end)

test('pack readiness blocks real opening closing and rerolls but recovers after they settle',function()
    fixture('PACK_LIFECYCLE','c_judgement')
    G.STATE=G.STATES.SHOP
    local p=G.P_CENTERS.p_celestial_normal_1
    local card={config={center=p},ability={extra=p.config.extra},area=G.shop_booster}
    SMODS.OPENED_BOOSTER={config={center=p}}
    local expected=O.quick.get('pack',card)
    for i,name in ipairs({'SMODS_BOOSTER_OPENED','TAROT_PACK','PLANET_PACK','SPECTRAL_PACK','STANDARD_PACK','BUFFOON_PACK'}) do
        G.STATES[name]=100+i; G.STATE=100+i
        local s=O.pack_prediction.capture(G,SMODS)
        assert(s.shop.pack_open and s.shop.opened_pack==p.key)
        assert(not pcall(O.quick.get,'pack',card),'opening must wait')
    end
    G.STATE=G.STATES.SHOP; G.booster_pack={}
    assert(not pcall(O.quick.get,'pack',card),'closing panel must wait')
    G.booster_pack=nil; G.CONTROLLER.locks.shop_reroll=true
    assert(not pcall(O.quick.get,'pack',card),'reroll must wait')
    G.CONTROLLER.locks.shop_reroll=false
    eq(O.quick.get('pack',card),expected)
    G.GAME.pseudorandom.Planetpl13=0.2
    local s=O.pack_prediction.capture(G,SMODS)
    eq(O.quick.get('pack',card).cards,O.pack_prediction.forecast(s,{key=p.key}))
    eq(O.quick.count,2)
end)

test('Hover cache refreshes RNG, hand selection, inventory and real deck mutations',function()
    local c=fixture('QUICKCACHE','c_wheel_of_fortune')
    O.quick.get('consumable',c); local n=O.quick.count
    for i=1,20 do O.quick.get('consumable',c) end; eq(O.quick.count,n)
    G.GAME.pseudorandom.wheel_of_fortune=0.8; O.quick.get('consumable',c); eq(O.quick.count,n+1)
    G.hand.highlighted={G.hand.cards[1]}; O.quick.get('consumable',c); eq(O.quick.count,n+2)
    table.remove(G.jokers.cards); O.quick.get('consumable',c); eq(O.quick.count,n+3)
    for _,card in ipairs(G.hand.cards) do G.deck.cards[#G.deck.cards+1]=card end
    local r=O.quick.get('deck'); eq(r.cards[1].id,G.deck.cards[#G.deck.cards].playing_card)
    G.deck.cards[#G.deck.cards].base.value='Ace'
    eq(O.quick.get('deck').cards[1].base.value,'Ace')
    table.remove(G.deck.cards); eq(#O.quick.get('deck').cards,7)
    G.STATE=G.STATES.SHOP; assert(not pcall(O.quick.get,'deck'))
    O.prediction_fault=true; assert(not pcall(O.quick.get,'consumable',c))
end)
test('Native tooltip retains description, appends once, and leaves preview clone source untouched',function()
    local c=fixture('QUICKUI','c_judgement')
    local generated=Card.generate_UIBox_ability_table
    G.UIDEF=G.UIDEF or {}; G.UIDEF.card_h_popup=function(card) return card.ability_UIBox_table end
    local oldhover=Card.hover; local called=0; Card.hover=function() called=called+1 end
    local oldareahover=CardArea.hover; CardArea.hover=function() called=called+1 end
    Node=Node or {}; local nodehover=Node.hover; Node.hover=function(node) node.children.h_popup={definition=node.config.h_popup} end
    local popup=create_popup_UIBox_tooltip; create_popup_UIBox_tooltip=function(v) return v end
    local nativebox=UIBox; UIBox=function(args) return {definition=args.definition,config=args.config,states={collide={},drag={}},resource=io.stdout} end
    O.quick_ui.install(); assert(Card.generate_UIBox_ability_table==generated)
    c.ability_UIBox_table={main={{{text='original description'}}}}
    local ui=G.UIDEF.card_h_popup(c); local count=#ui.main
    assert(count>1); eq(ui.main[1],{{text='original description'}})
    G.UIDEF.card_h_popup(c); eq(#ui.main,count)
    c.oracle_preview=true; c.ability_UIBox_table={main={{}}}; G.UIDEF.card_h_popup(c); eq(#c.ability_UIBox_table.main,1)
    c.oracle_preview=nil
    local saved_config=D.encode(G.deck.config)
    G.deck.children={}; CardArea.hover(G.deck); assert(G.deck.children.h_popup)
    eq(D.encode(G.deck.config),saved_config)
    dofile(ORACLE_TEST_SOURCE..'/quick_save_truth.lua')
    local save=CardArea.save(G.deck)
    assert(type(STR_PACK(save))=='string','Native save must ignore UI/userdata')
    eq(save.config,G.deck.config)
    local top=G.hand.cards[1]; top.area=G.deck; top.children={}; top.no_ui=false
    Card.hover(top); assert(top.children.h_popup); eq(called,0)
    O.config.enabled=false; CardArea.hover(G.deck); eq(G.deck.config.h_popup,nil); eq(called,1)
    Card.hover(c); eq(called,2)
    Card.hover=oldhover; CardArea.hover=oldareahover; Node.hover=nodehover; create_popup_UIBox_tooltip=popup; UIBox=nativebox
end)
test('Compact names include Wheel edition, Soul destination, and draw preview truncation',function()
    fixture('QUICKNAMES','c_judgement')
    local name=O.quick_ui.name({key='c_soul',set='Spectral',legendary='j_perkeo'})
    assert(name:find('→',1,true))
    assert(O.quick_ui.name({key='j_blueprint',set='Joker',edition='e_polychrome'}):find(' · ',1,true))
    for i=1,12 do G.deck.cards[i]=G.hand.cards[(i-1)%8+1] end
    local lines=O.quick_ui.lines('deck',G.deck); eq(#lines,11)
    O.config.show_draw_order=false; eq(#O.quick_ui.lines('deck',G.deck),1)
    O.config.show_draw_order=true
end)
print('Quick preview: '..groups..' groups, 320 native Tarot uses and 100 pack adapter comparisons passed')
