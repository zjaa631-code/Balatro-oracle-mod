local O,D=ORACLE,ORACLE.data
local groups,cases=0,0
local noop=function() end
local function eq(a,b,label) assert(D.encode(a)==D.encode(b),(label or '')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
local function test(name,fn) ORACLE_TEST_CASE=name; fn(); groups=groups+1; print('PASS '..name) end
local function fixture(seed)
    -- Restore the constructor's base setter after the preceding native deck tests.
    Card.set_base=function(c,front)
        c.config.card=front; c.base=D.copy(front or {}); c.config.card_key=nil
        for k,v in pairs(G.P_CARDS) do if v==front then c.config.card_key=k end end
    end
    ORACLE_CONSUMABLE_FIXTURE(seed,'c_strength')
    G.C.SUITS={}; G.P_SEALS={}; SMODS.mod_list={}; SMODS.Stickers={}; SMODS.optional_features={}
    SMODS.Enhancement={take_ownership=function(_,key,def) for k,v in pairs(def) do G.P_CENTERS['m_'..key][k]=v end end}
    dofile(ORACLE_TEST_SOURCE..'/boss_truth.lua')
    for key,p in pairs(G.P_BLINDS) do p.key=key end
    G.GAME.current_round.most_played_poker_hand='Pair'
    G.GAME.current_round.discards_left=1; G.GAME.round_resets.discards=3; G.GAME.round_bonus={discards=1}
    for i,key in ipairs({'High Card','Pair','Flush','Flush Five'}) do
        G.GAME.hands[key]={level=i,chips=10*i+1,mult=i*2+1,visible=key~='Flush Five',order=i,played=i}
    end
    -- The tested Blind functions call these unrelated presentation/economy
    -- helpers; level_up_hand itself is independently tested in earlier phases.
    level_up_hand=function(_,name,instant,delta) G.GAME.hands[name].level=G.GAME.hands[name].level+(delta or 1) end
    ease_dollars=function(delta) G.GAME.dollars=G.GAME.dollars+delta end
    O.config.validate_predictions=false; O.prediction_fault=nil; G.SETTINGS.paused=false
end
local function blind(key,disabled)
    local p=assert(G.P_BLINDS[key],key)
    local b=setmetatable({config={blind=p},name=p.name,debuff=D.copy(p.debuff or {}),disabled=disabled or false,
        hands={},only_hand=false,children={animatedSprite={}},wiggle=noop},{__index=Blind})
    G.GAME.blind=b; G.GAME.round_resets.blind_choices.Boss=key; return b
end
local function card(c,key,index)
    c.config.center=G.P_CENTERS[key]; c.ability=D.copy(c.config.center.config or {})
    c.ability.name=c.config.center.name; c.ability.set=c.config.center.set
    c.ability.played_this_ante=index%2==0; c.ability.debuff_sources={}
    c.debuff=index%3==0; c.vampired=nil
    return c
end
test('all 28 Boss card rules match native across 20 seeds and trait combinations',function()
    for seed=1,20 do
        fixture('BOSS_RULES_'..seed)
        for key in pairs(O.bosses.keys) do
            local b=blind(key,seed%5==0)
            for variant=1,4 do
                G.jokers.cards={}
                if variant==2 or variant==4 then G.jokers.cards[#G.jokers.cards+1]={config={center=G.P_CENTERS.j_pareidolia},ability={name='Pareidolia'}} end
                if variant==3 or variant==4 then G.jokers.cards[#G.jokers.cards+1]={config={center=G.P_CENTERS.j_smeared},ability={name='Smeared Joker'}} end
                local s=O.bosses.context(G,SMODS,b)
                for index,c in ipairs(G.playing_cards) do
                    card(c,({'c_base','m_stone','m_wild','m_steel'})[(index+seed)%4+1],index)
                    if seed%7==0 then c.ability.debuff_sources={safety='prevent_debuff'} end
                    if seed%11==0 then c.ability.debuff_sources={other=true} end
                    if seed%3==0 then c.vampired=true end
                    local record=O.consumables.card(c); record.vampired=c.vampired
                    local expected=O.bosses.card_effect(s,record)
                    b:debuff_card(c); eq(not not c.debuff,expected.debuff,key..' '..variant..' '..index)
                    cases=cases+1
                end
            end
        end
    end
end)
test('hand restrictions and level/money changes match native checks and actual callbacks',function()
    fixture('BOSS_HANDS')
    for key in pairs(O.bosses.keys) do for _,disabled in ipairs({false,true}) do
        for _,check in ipairs({false,true}) do for count=1,5 do for _,name in ipairs({'High Card','Pair','Flush','Flush Five'}) do
            local b=blind(key,disabled); b.hands.Pair=true; b.only_hand='Flush'
            G.GAME.hands[name].level=count; G.GAME.dollars=count%2==0 and -3 or 27
            local cards={}; for i=1,count do cards[i]=G.hand.cards[i] end
            local hands={}; for h in pairs(G.GAME.hands) do hands[h]=h==name and {cards} or {} end
            local s=O.bosses.context(G,SMODS,b); local r=O.bosses.hand_effect(s,{hand=name,count=count})
            local blocked=b:debuff_hand(cards,hands,name,check)
            eq(not not blocked,r.blocked,key..' block')
            eq(G.GAME.hands[name].level,check and r.level_before or r.level_after,key..' level')
            local dollars=s.dollars
            if key=='bl_ox' and not check then dollars=dollars+r.money end
            eq(G.GAME.dollars,dollars,key..' money'); cases=cases+1
        end end end
    end end
end)
test('Flint rounding matches native for fractional base values, disabled and floor boundaries',function()
    fixture('FLINT_BASE')
    for _,disabled in ipairs({true,false}) do for _,mult in ipairs({0,1,1.5,3,17.9,101}) do for _,chips in ipairs({0,1,2.5,13,250.9}) do
        local b=blind('bl_flint',disabled); local s=O.bosses.context(G,SMODS,b)
        s.levels.Pair.mult=mult; s.levels.Pair.chips=chips
        local r=O.bosses.hand_effect(s,{hand='Pair',count=2})
        local m,c,changed=b:modify_hand({}, {}, 'Pair', mult,chips)
        eq({m,c,changed},{r.mult,r.chips,r.modified}); cases=cases+1
    end end end
end)
test('capture, repeat analysis and detached outputs preserve physical state and both RNGs',function()
    fixture('BOSS_READ_ONLY'); local b=blind('bl_plant')
    card(G.hand.cards[2],'m_stone',2)
    for i=1,10 do
        local s=O.bosses.capture(G,SMODS); local original=D.encode(s)
        math.randomseed(479); local random=math.random(); math.randomseed(479)
        local r=O.engine.predict('boss_analysis',s,{hand='Pair',count=2})
        eq(math.random(),random,'live math RNG')
        eq(D.encode(s),original,'input'); eq(D.encode(O.bosses.capture(G,SMODS)),original,'live world')
        eq(r,O.engine.predict('boss_analysis',s,{hand='Pair',count=2}),'repeat')
        if r.affected[1] then r.affected[1].base.value='changed' end
        eq(D.encode(O.bosses.capture(G,SMODS)),original,'output isolation'); cases=cases+1
    end
end)
test('upcoming entry effects use reset counters; current Boss does not repeat entry cost',function()
    fixture('BOSS_ENTRY'); local b=blind('bl_water')
    local request={hand='Pair',count=2}
    eq(O.engine.predict('boss_analysis',O.bosses.capture(G,SMODS,'upcoming'),request).discards_delta,-4)
    eq(O.engine.predict('boss_analysis',O.bosses.capture(G,SMODS,'current'),request).discards_delta,nil)
    G.GAME.round_resets.blind_choices.Boss='bl_needle'
    eq(O.engine.predict('boss_analysis',O.bosses.capture(G,SMODS,'upcoming'),request).hands_delta,-3)
    G.GAME.round_resets.blind_choices.Boss='bl_manacle'
    eq(O.engine.predict('boss_analysis',O.bosses.capture(G,SMODS,'upcoming'),request).hand_size_delta,-1)
    G.jokers.cards[#G.jokers.cards+1]={config={center=G.P_CENTERS.j_chicot},ability={name='Chicot'}}
    local r=O.engine.predict('boss_analysis',O.bosses.capture(G,SMODS,'upcoming'),request)
    assert(r.disabled and r.chicot and not r.hand_size_delta)
    -- Eye history is reset when entering a new Boss, not inherited.
    b=blind('bl_eye'); b.hands.Pair=true
    assert(O.engine.predict('boss_analysis',O.bosses.capture(G,SMODS,'current'),request).hand.blocked)
    G.jokers.cards={}
    assert(not O.engine.predict('boss_analysis',O.bosses.capture(G,SMODS,'upcoming'),request).hand.blocked)
end)
test('Boss validation compares native callbacks, detects corruption and preserves returns',function()
    for _,kind in ipairs({'card','hand','base'}) do for _,corrupt in ipairs({false,true}) do
        fixture('BOSS_VALIDATE_'..kind); local b=blind(kind=='card' and 'bl_plant' or kind=='hand' and 'bl_arm' or 'bl_flint')
        local method=kind=='card' and 'debuff_card' or kind=='hand' and 'debuff_hand' or 'modify_hand'
        local native=Blind[method]; local calls=0
        Blind[method]=function(self,...)
            calls=calls+1; local ret={native(self,...)}
            if corrupt then
                if kind=='card' then local c=...; c.debuff=not c.debuff
                elseif kind=='hand' then G.GAME.hands.Pair.level=99
                else ret[1]=999 end
            end
            if kind=='base' then return unpack(ret,1,3) end
            return ret[1],nil,'sentinel'
        end
        O.config.validate_predictions=true; O.validator=dofile(ORACLE_TEST_ROOT..'/debug/validator.lua')(O)
        O.boss_validator=dofile(ORACLE_TEST_ROOT..'/debug/boss_validator.lua')(O); O.boss_validator.install()
        if kind=='card' then local a,n,v=b:debuff_card(G.hand.cards[2]); eq(v,'sentinel'); eq(n,nil)
        elseif kind=='hand' then local a,n,v=b:debuff_hand({G.hand.cards[1],G.hand.cards[2]},{Pair={{}}},'Pair',false); eq(v,'sentinel'); eq(n,nil)
        else b:modify_hand({}, {}, 'Pair', 3,11) end
        eq(calls,1,'original call count')
        eq(O.validator.counts[corrupt and 'MISMATCH' or 'MATCH'],1,kind..' validator')
        eq(not not O.prediction_fault,corrupt); cases=cases+1
    end end
end)
test('Boss UI caches state, localizes labels and respects hidden hand visibility',function()
    fixture('BOSS_UI'); blind('bl_plant'); O.boss_analysis_ui=dofile(ORACLE_TEST_ROOT..'/ui/boss_analysis.lua')(O)
    G.UIT={ROOT=1,R=2,C=3,T=4,O=5,B=6}
    local colour={}; G.C=setmetatable({SUITS={},UI=setmetatable({},{__index=function() return colour end})},{__index=function() return colour end})
    local preview,predict=O.preview_card.area,O.engine.predict; local calls=0
    O.preview_card.area=function(cards) return {n=G.UIT.R,nodes={},config={oracle_cards=D.copy(cards)}} end
    O.engine.predict=function(...) calls=calls+1; return predict(...) end
    local before=D.encode(O.bosses.capture(G,SMODS))
    for view=1,3 do O.boss_analysis_ui.view=view; assert(O.boss_analysis_ui.definition()) end
    eq(calls,1); for _,name in ipairs(O.boss_analysis_ui.hands) do assert(name~='Flush Five') end
    eq(D.encode(O.bosses.capture(G,SMODS)),before)
    G.GAME.hands['Flush Five'].visible=true; O.boss_analysis_ui.definition(); eq(calls,2)
    G.GAME.hands.Pair.level=10; O.boss_analysis_ui.definition(); eq(calls,3)
    O.preview_card.area=preview; O.engine.predict=predict
    local en=dofile(ORACLE_TEST_ROOT..'/localization/en-us.lua').misc.dictionary
    local zh=dofile(ORACLE_TEST_ROOT..'/localization/zh_CN.lua').misc.dictionary
    for key in pairs(en) do if key:match('^oracle_boss_') then assert(zh[key],key) end end
end)
print('Boss effects: '..groups..' test groups, '..cases..' native cases passed')
