local O,D=ORACLE,ORACLE.data
local groups,cases=0,0
local function eq(a,b,msg) assert(D.encode(a)==D.encode(b),(msg or '')..' Expected '..D.encode(b)..' Actual '..D.encode(a)) end
local function test(name,fn) ORACLE_TEST_CASE=name; fn(); groups=groups+1; print('PASS '..name) end
local queue,actual
local function fixture(seed,n,chosen)
    O.prediction_fault=nil; O.status={issues={}}; O.config.enabled=true; O.config.validate_predictions=false
    G.STAGES={RUN=1,MAIN_MENU=2}; G.STAGE=1; G.STATES={SELECTING_HAND=1,HAND_PLAYED=2}; G.STATE=1
    G.GAME={pseudorandom={seed=seed,hashed_seed=O.rng.hash(seed),hook=0.173},round=2,round_resets={ante=1},current_round={hands_left=4}}
    G.SETTINGS={paused=false}; G.CONTROLLER={HID={touch=false}}; G.hand={cards={},highlighted={}}; G.play={cards={}}
    for i=1,n do
        local c={playing_card=i,sort_id=n-i+20,highlighted=i<=chosen,facing='front',sprite_facing='front',
            base={suit='Hearts',value='King'},config={center={key='c_base',set='Default'}},ability={},
            states={drag={is=false}},children={},ARGS={send_to_shader={1,2}},area=G.hand}
        G.hand.cards[i]=c; if i<=chosen then G.hand.highlighted[#G.hand.highlighted+1]=c end
    end
    G.hand.add_to_highlighted=function(self,c) self.highlighted[#self.highlighted+1]=c end
    queue={}; actual={}; G.E_MANAGER={add_event=function(_,e) queue[#queue+1]=e end}; Event=function(e) return e end
    play_sound=function() end; delay=function() end
    G.FUNCS.discard_cards_from_highlighted=function(_,hook)
        assert(hook); for _,c in ipairs(G.hand.highlighted) do actual[#actual+1]=c.playing_card end
        return nil,'discarded'
    end
    Blind={}; dofile(ORACLE_TEST_SOURCE..'/hook_truth.lua')
    G.GAME.blind=setmetatable({name='The Hook',config={blind={key='bl_hook'}}},{__index=Blind})
    G.FUNCS.play_cards_from_highlighted=function()
        local keep={}; for _,c in ipairs(G.hand.cards) do if not c.highlighted then keep[#keep+1]=c else G.play.cards[#G.play.cards+1]=c end end
        G.hand.cards=keep; G.hand.highlighted={}; G.STATE=G.STATES.HAND_PLAYED
        G.GAME.blind:press_play(); return nil,'played'
    end
    O.hook_controller=dofile(ORACLE_TEST_ROOT..'/hook_controller.lua')(O)
end
local function drain() while #queue>0 do local e=table.remove(queue,1); assert(e.func()) end end
test('Hook shadow targets match native queued press_play over 100 seeds and remaining-hand sizes',function()
    for seed=1,100 do for n=1,12 do for chosen=1,math.min(n,5) do
        fixture('HOOK'..seed,n,chosen)
        if seed%2==0 then G.GAME.pseudorandom.hook=nil end
        local s=O.hook.capture(G); local before=D.encode(s)
        math.randomseed(781); local r0=math.random(); math.randomseed(781)
        local r,details=O.engine.predict('hook',s)
        eq(math.random(),r0,'global math RNG unchanged'); eq(D.encode(O.hook.capture(G)),before,'live state unchanged'); eq(D.encode(s),before,'input unchanged')
        G.FUNCS.play_cards_from_highlighted(); drain()
        eq(actual,r.targets,'native targets'); eq(G.GAME.pseudorandom.hook,details.rng_after.hook,'native stream'); cases=cases+1
    end end end
end)
test('physical IDs, sort_id order, changing selection and advancing Hook RNG invalidate cache',function()
    fixture('HOOK_CACHE',8,2); O.hook_controller.update(0,true)
    local count=O.hook_controller.count
    for i=1,100 do O.hook_controller.update(0.1) end
    eq(O.hook_controller.count,count)
    G.hand.highlighted[2]=G.hand.cards[3]; G.hand.cards[2].highlighted=false; G.hand.cards[3].highlighted=true
    O.hook_controller.update(0,true); eq(O.hook_controller.count,count+1)
    G.GAME.pseudorandom.hook=0.5; O.hook_controller.update(0,true); eq(O.hook_controller.count,count+2)
    G.GAME.blind.disabled=true; O.hook_controller.update(0,true); eq(O.hook_controller.targets,{})
    G.GAME.blind.disabled=false; G.hand.highlighted={}; O.hook_controller.update(0,true); eq(O.hook_controller.targets,{})
    assert(not O.hook.active(G))
end)
test('Hook glow draws only native shaders without editions, facing or RNG changes',function()
    fixture('HOOK_DRAW',8,2); O.hook_controller.update(0,true)
    local draws=0; local sprite={draw_shader=function(_,shader) eq(shader,'voucher'); draws=draws+1 end}
    local oldrng=D.encode(G.GAME.pseudorandom)
    for _,c in ipairs(G.hand.cards) do c.children={back=sprite,center=sprite,front=sprite} end
    for _,c in ipairs(G.hand.cards) do
        c.sprite_facing='back'; c.facing='back'; O.card_insight.shine(c)
        eq(c.edition,nil); eq(c.facing,'back')
    end
    eq(draws,2); eq(D.encode(G.GAME.pseudorandom),oldrng)
    G.GAME.blind.disabled=true
    for _,c in ipairs(G.hand.cards) do O.card_insight.shine(c) end
    eq(draws,2)
end)
test('face-down Joker and playing-card names follow actual shuffled objects without RNG or flips',function()
    fixture('BACK_NAME',3,1)
    local original_card,original_node=Card,Node
    local native_calls,hovered=0,0
    Card={hover=function() native_calls=native_calls+1; return 'native' end}
    Node={hover=function() hovered=hovered+1 end}
    local original_localize,original_popup=localize,create_popup_UIBox_tooltip
    localize=function(key,set) if type(key)=='table' then return 'name:'..key.key end; return (set or 'text')..':'..key end
    create_popup_UIBox_tooltip=function(args) return args end
    O.card_insight=dofile(ORACLE_TEST_ROOT..'/ui/card_insight.lua')(O); O.card_insight.install()
    local a,b=G.hand.cards[1],G.hand.cards[2]
    a.facing='back'; b.facing='back'; b.playing_card=nil; b.config.center={key='j_blueprint',set='Joker',name='Blueprint'}
    math.randomseed(422); local sample=math.random(); math.randomseed(422)
    Card.hover(a); Card.hover(b)
    eq(a.config.h_popup.title,'suits_plural:Hearts ranks:King'); eq(b.config.h_popup.title,'name:j_blueprint')
    G.jokers={cards={b,a}}; Card.hover(G.jokers.cards[1]); eq(b.config.h_popup.title,'name:j_blueprint')
    eq(math.random(),sample); eq(a.facing,'back'); eq(b.facing,'back'); eq(native_calls,0); eq(hovered,3)
    b.facing='front'; eq(Card.hover(b),'native'); eq(native_calls,1)
    O.config.enabled=false; a.config.h_popup=nil; Card.hover(a); eq(a.config.h_popup,nil)
    localize=original_localize; create_popup_UIBox_tooltip=original_popup
    Card,Node=original_card,original_node
end)
test('actual Hook discard validation matches, detects corruption and retains callback returns',function()
    for _,corrupt in ipairs({false,true}) do
        fixture('HOOK_VALIDATE',8,3)
        O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
        O.hook_controller.install()
        local nil_result,result=G.FUNCS.play_cards_from_highlighted(); eq(nil_result,nil); eq(result,'played')
        if corrupt then G.GAME.pseudorandom.hook=0.9 end
        drain(); eq(O.validator.counts[corrupt and 'MISMATCH' or 'MATCH'],1)
        eq(not not O.prediction_fault,corrupt)
    end
end)
print('Card insight: '..groups..' groups, '..cases..' native Hook scenarios passed')
