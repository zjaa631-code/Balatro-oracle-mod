local O,D=ORACLE,ORACLE.data
local passed=0
-- Restore rendering shells after the gameplay fixtures; UI definitions remain native.
G.ASSET_ATLAS={icons={}}; G.ROOM={T={w=20,h=12}}
G.UIT={ROOT=1,R=2,C=3,T=4,O=5,B=6}
local colour={1,1,1,1}
G.C=setmetatable({UI=setmetatable({},{__index=function() return colour end})},{__index=function() return colour end})
Sprite=function() return {states={drag={},hover={},collide={}},define_draw_steps=function() end} end
DynaText=function(args) return args end
UIBox=function(args) return args end
local function test(name,fn) if ORACLE_FIXTURES_ONLY then return end; ORACLE_TEST_CASE=name; fn(); passed=passed+1; print('PASS '..name) end
test('legacy user config gains defaults without changing preferences and rejects malformed depth',function()
    local c={enabled=false,advanced_info=true,prediction_depth=20,validate_predictions=false,custom='preserved'}
    assert(O.configuration.normalize(c)==c)
    assert(not c.enabled and c.advanced_info and c.prediction_depth==20 and not c.validate_predictions)
    assert(c.auto_refresh and c.show_draw_order and c.show_future_shops and c.show_packs and c.show_voucher)
    assert(c.custom=='preserved')
    c.prediction_depth=500; c.auto_refresh='false'; O.configuration.normalize(c)
    assert(c.prediction_depth==3 and c.auto_refresh==true)
end)
test('native settings expose all eight toggles and supported depth choices',function()
    local found={}; local original=create_toggle
    create_toggle=function(args) found[args.ref_value]=args; return original(args) end
    O.settings.definition()
    create_toggle=original
    for _,key in ipairs({'enabled','auto_refresh','show_draw_order','show_future_shops','show_packs',
        'show_voucher','advanced_info','validate_predictions'}) do assert(found[key] and found[key].callback) end
    local old=O.config.prediction_depth
    G.FUNCS.oracle_depth({to_val=10}); assert(O.config.prediction_depth==10)
    O.config.prediction_depth=old
end)
test('all nine pages use at most four native tabs and disabled Oracle avoids page readers',function()
    local oldtabs,refresh=create_tabs,G.FUNCS.oracle_refresh
    local seen={}
    create_tabs=function(args)
        assert(#args.tabs<=4 and args.scale<=0.75)
        for _,tab in ipairs(args.tabs) do seen[tab.label]=true end
        return {n=G.UIT.R,config={},nodes={}}
    end
    for _,p in ipairs(O.main.pages) do O.main.active=p.id; O.main.definition() end
    for _,p in ipairs(O.main.pages) do assert(seen[O.text.get(p.label)]) end
    local target
    G.FUNCS.oracle_refresh=function() target=O.main.active end
    G.FUNCS.oracle_tab_group({to_key=2}); assert(target==O.main.pages[5].id)
    create_tabs=oldtabs; G.FUNCS.oracle_refresh=refresh
    local old=O.deck_ui.definition
    O.config.enabled=false; O.main.active='deck'
    local page; for _,p in ipairs(O.main.pages) do if p.id=='deck' then page=p end end
    local build=page.build; page.build=function() error('disabled reader called') end
    O.main.definition(); page.build=build; O.config.enabled=true; O.main.active='overview'
end)
test('manual refresh mode cancels queued automatic refresh without losing invalidation',function()
    local manager,refresh,overlay=G.E_MANAGER,G.FUNCS.oracle_refresh,G.OVERLAY_MENU
    local pending,calls={},0
    G.E_MANAGER={add_event=function(_,e) pending[#pending+1]=e end}
    G.FUNCS.oracle_refresh=function() calls=calls+1 end; G.OVERLAY_MENU={}
    O.config.auto_refresh=true
    local e={config={}}; O.main.watch(e); O.controller.invalidate(); O.main.watch(e)
    assert(#pending==1)
    O.config.auto_refresh=false; pending[1].func(); assert(calls==0)
    for i=1,100 do O.controller.invalidate(); O.main.watch(e) end
    assert(#pending==1)
    G.E_MANAGER=manager; G.FUNCS.oracle_refresh=refresh; G.OVERLAY_MENU=overlay; O.config.auto_refresh=true
end)
test('hidden views skip readers and current shop remains visible with future shops off',function()
    local pack,deck=O.pack_prediction.capture,O.deck_prediction.read
    O.pack_prediction.capture=function() error('hidden pack reader') end
    O.deck_prediction.read=function() error('hidden deck reader') end
    O.config.show_packs=false; O.packs_ui.definition()
    O.config.show_draw_order=false; O.deck_ui.definition()
    O.pack_prediction.capture=pack; O.deck_prediction.read=deck
    O.config.show_packs=true; O.config.show_draw_order=true
    local capture,forecast,supported=O.shop_snapshot.capture,O.shop_prediction.forecast,O.controller.supported
    O.controller.supported=function() return true end
    local snapshot={shop={active=true,cards={{key='j_joker'}},packs={}}}
    O.shop_snapshot.capture=function() return snapshot end
    O.shop_prediction.forecast=function() error('future simulation while disabled') end
    O.config.show_future_shops=false; local rows=O.controller.shop_forecast()
    assert(#rows==1 and rows[1].status=='observed' and rows[1].cards[1].key=='j_joker')
    snapshot.shop.active=false; local r,err=O.controller.shop_forecast(); assert(not r and err=='oracle_feature_hidden')
    O.config.show_future_shops=true; O.shop_snapshot.capture=capture; O.shop_prediction.forecast=forecast; O.controller.supported=supported
    O.config.show_voucher=false
    local effects=O.tag_ui.visible_effects({effects={{type='voucher'},{type='joker'}}})
    assert(#effects==1 and effects[1].type=='joker'); O.config.show_voucher=true
end)
test('RNG inspector sorts detached rows, paginates and never draws RNG',function()
    local game=G.GAME
    G.GAME={pseudorandom={seed='CZZXRBWB',z=0.3,a=0.2}}
    for i=1,20 do G.GAME.pseudorandom['stream'..i]=i/23 end
    local before=D.encode(G.GAME)
    local random,ps=math.random,pseudoseed
    math.random=function() error('RNG UI draws random') end; pseudoseed=math.random
    O.config.advanced_info=true
    local rows=O.rng_ui.read(); assert(rows[1].key=='a')
    rows[1].value=999; assert(G.GAME.pseudorandom.a==0.2)
    for i=1,4 do O.rng_ui.page=i; O.rng_ui.definition() end
    assert(before==D.encode(G.GAME))
    O.config.advanced_info=false; O.rng_ui.definition()
    math.random=random; pseudoseed=ps; G.GAME=game
end)
print('PHASE6: '..passed..' tests passed')
