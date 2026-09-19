local O,D=ORACLE,ORACLE.data
local passed,cases=0,0
local function eq(a,b,label) assert(D.encode(a)==D.encode(b),(label or '')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
local function test(name,fn) if ORACLE_JOKERS_ONLY then return end; ORACLE_TEST_CASE=name; fn(); passed=passed+1; print('PASS '..name) end
local function noop() end
local function fixture(seed,ante)
    ORACLE_TAG_CHAIN_FIXTURE(seed,ante)
    G.C.PURPLE={}; G.C.SECONDARY_SET={Planet={},Spectral={},Voucher={}}
    G.play={T={x=0,y=0,w=8,h=2},cards={}}
    G.jokers.config={card_limit=5}; G.jokers.cards={}; G.jokers.T={x=0,y=0,w=8,h=2}
    G.jokers.emplace=function(self,c) self.cards[#self.cards+1]=c end
    Card.add_to_deck=noop; Card.start_materialize=noop
    unlock_card=noop
    SMODS.Consumable={legendaries={}}; SMODS.OPENED_BOOSTER=nil
    G.handlist={}; for k in pairs(G.GAME.hands) do G.handlist[#G.handlist+1]=k end; table.sort(G.handlist)
    G.P_CENTER_POOLS.Seal={}; G.P_SEALS={}
    for _,k in ipairs({'Gold','Red','Blue','Purple'}) do local seal={key=k,set='Seal',weight=10}; G.P_CENTER_POOLS.Seal[#G.P_CENTER_POOLS.Seal+1]=seal; G.P_SEALS[k]=seal end
    Card.set_seal=function(self,key) self.seal=key end
    SMODS.Booster={take_ownership_by_kind=function(_,kind,v)
        for _,c in ipairs(G.P_CENTER_POOLS.Booster) do if c.kind==kind then c.create_card=v.create_card end end
    end}
    dofile(ORACLE_TEST_SOURCE..'/booster_truth.lua'); dofile(ORACLE_TEST_SOURCE..'/seal_truth.lua')
    G.pack_cards={cards={},T={x=0,y=0,w=8,h=2}}
    G.FUNCS.use_card=function(e)
        local card=e.config.ref_table; assert(card.from_tag and card.cost==0,'not native free Tag pack')
        local p=card.config.center; G.TEST_PACK_KEY=p.key
        for i=1,math.max(1,p.config.extra+(G.GAME.modifiers.booster_size_mod or 0)) do
            G.pack_cards.cards[i]=SMODS.create_card(p:create_card(card,i))
        end
    end
    O.tag_rewards=dofile(ORACLE_TEST_ROOT..'/prediction/tag_rewards.lua')(O)
    O.tag_rewards_ui=nil
end
local function actual_cards(area)
    local out={}; for _,c in ipairs(area.cards) do out[#out+1]=O.shop_snapshot.card(c) end; return out
end
local function predict(key,blind)
    local tag=Tag(key,nil,blind or 'Small')
    local s=O.tag_prediction.capture(key,blind or 'Small',tag.ability,false,tag.config)
    local before=D.encode(s)
    math.randomseed(881); local sample=math.random(); math.randomseed(881)
    local r=O.tag_prediction.forecast(s)
    assert(math.random()==sample,'live math RNG advanced')
    eq(D.encode(O.tag_prediction.capture(key,blind or 'Small',tag.ability,false,tag.config)),before,'live snapshot changed')
    eq(D.encode(s),before,'caller snapshot changed')
    return tag,s,r
end
local function skip(tag)
    G.FUNCS.skip_blind({UIBox={get_UIE_by_ID=function() return {config={ref_table=tag}} end}})
    ORACLE_TAG_DRAIN()
end
test('five reward pack Tags match native skip/apply/create for both blinds across seeds',function()
    for seed=1,70 do for _,key in ipairs({'tag_standard','tag_charm','tag_meteor','tag_buffoon','tag_ethereal'}) do
        fixture('REWARD'..seed..key,seed%8+1)
        G.GAME.used_vouchers.v_omen_globe=seed%2==0; G.GAME.used_vouchers.v_telescope=seed%3==0
        G.GAME.modifiers.enable_eternals_in_shop=true; G.GAME.modifiers.enable_perishables_in_shop=true; G.GAME.modifiers.enable_rentals_in_shop=true
        G.GAME.modifiers.booster_size_mod=seed%2
        local blind=seed%2==0 and 'Big' or 'Small'; G.GAME.blind_on_deck=blind
        local tag,s,r=predict(key,blind); skip(tag)
        local e=r.effects[1]; assert(e.type=='pack')
        eq(G.P_CENTERS[G.TEST_PACK_KEY].kind,G.P_CENTERS[e.pack.key].kind,'actual native pack kind')
        eq(actual_cards(G.pack_cards),O.tag_rewards.plain(e.cards),key..' candidates')
        eq(G.GAME.pseudorandom,r.details.rng_after,key..' full keyed RNG')
        for _,c in ipairs(e.cards) do if c.legendary then
            local soul=create_card('Joker',G.jokers,true,nil,nil,nil,nil,'sou'); eq(soul.config.center.key,c.legendary,'Soul'); break
        end end
        cases=cases+1
    end end
end)
test('Top-up obeys actual capacity, common pool, ownership and Double propagation',function()
    for seed=1,100 do
        fixture('TOPUP'..seed,seed%8+1)
        G.jokers.config.card_limit=seed%6
        if seed%3==0 then G.jokers:emplace(create_card('Joker',G.jokers,nil,nil,nil,nil,'j_joker')) end
        if seed%4==0 then add_tag(Tag('tag_double')); ORACLE_TAG_DRAIN() end
        local tag,s,r=predict('tag_top_up'); skip(tag)
        local expected={}
        for _,e in ipairs(r.effects) do for _,c in ipairs(e.cards or {}) do expected[#expected+1]=c end end
        local actual=actual_cards(G.jokers); if seed%3==0 then table.remove(actual,1) end
        eq(actual,expected,'Top-up cards'); eq(G.GAME.pseudorandom,r.details.rng_after,'Top-up RNG')
        for _,c in ipairs(actual) do assert(G.P_CENTERS[c.key].rarity==1 and not c.perishable and not c.rental) end
        cases=cases+1
    end
end)
test('Double pack stops at choice boundary; held tag refreshes from the post-choice state',function()
    fixture('DOUBLE_REWARD',3); add_tag(Tag('tag_double')); ORACLE_TAG_DRAIN()
    local tag,s,r=predict('tag_charm'); assert(#r.expanded_tags==2 and r.effects[2].pending)
    skip(tag); eq(actual_cards(G.pack_cards),O.tag_rewards.plain(r.effects[1].cards))
    assert(not pcall(O.tag_prediction.capture,'tag_charm','Held'))
    for _,c in ipairs(G.pack_cards.cards) do G.GAME.used_jokers[c.config.center.key]=nil end
    G.pack_cards.cards={}
    local held=O.tag_prediction.get('tag_charm','Held'); assert(held and held.effects and held.effects[1].cards)
    for _,t in ipairs(G.GAME.tags) do if t:apply_to_run({type='new_blind_choice'}) then break end end
    ORACLE_TAG_DRAIN(); eq(actual_cards(G.pack_cards),O.tag_rewards.plain(held.effects[1].cards))
    eq(G.GAME.pseudorandom,held.details.rng_after,'second actual pack RNG'); cases=cases+1
end)
test('reward tooltip includes every candidate and caches repeated hover without RNG use',function()
    fixture('REWARD_TOOLTIP',3)
    local old=generate_card_ui; generate_card_ui=function() return {main={{{native=true}}}} end
    local tag=Tag('tag_standard',nil,'Small'); O.tag_ui.install()
    G.C.UI.TEXT_DARK={}; G.C.ORANGE={}; G.UIT.T=4
    local sprite={}; tag.tag_sprite=sprite
    tag:get_uibox_table(sprite)
    local count=O.tag_prediction.computations; local before=D.encode(G.GAME)
    tag:get_uibox_table(sprite); eq(O.tag_prediction.computations,count,'hover cache'); eq(D.encode(G.GAME),before,'hover readonly')
    local lines=O.tag_ui.lines(O.tag_prediction.get('tag_standard','Small'))
    local seen=0; for _,line in ipairs(lines) do if line:match('^%d+%. ') then seen=seen+1 end end
    assert(seen==5,'all five candidates must be visible in tooltip')
    assert(sprite.ability_UIBox_table.main[1][1].native,'native tooltip body changed')
    generate_card_ui=old
end)
test('Top-up pre-skip and native callback validators produce MATCH and detect mismatch',function()
    fixture('TOPUP_VALIDATION',3)
    O.tag_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_validator.lua')(O); O.tag_validator.install()
    O.tag_chain_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_chain_validator.lua')(O); O.tag_chain_validator.install()
    O.tag_reward_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_reward_validator.lua')(O); O.tag_reward_validator.install()
    local tag,s,r=predict('tag_top_up'); skip(tag)
    assert(O.validator.counts.MISMATCH==0 and O.validator.counts.MATCH>=2)
    assert(O.tag_chain_validator.chains[1].complete,'pre-skip result not completed')
    O.tag_validator.pending[tag]={result={cards=r.effects[1].cards},snapshot=s}
    O.tag_validator.finish_reward(tag,{}); assert(O.prediction_fault,'injected mismatch not detected')
end)
test('free pack auto-open keeps pre-skip validation bound through candidate emplace',function()
    fixture('PACK_REWARD_VALIDATION',3)
    local old_open,old_emplace=Card.open,CardArea.emplace
    CardArea.emplace=function(area,card) area.cards[#area.cards+1]=card end
    Card.open=function(card)
        G.E_MANAGER:add_event(Event({func=function()
            local p=card.config.center
            for i=1,p.config.extra do CardArea.emplace(G.pack_cards,SMODS.create_card(p:create_card(card,i))) end
            return true
        end}))
    end
    G.FUNCS.use_card=function(e) e.config.ref_table:open() end
    O.pack_validator=dofile(ORACLE_TEST_ROOT..'/debug/pack_validator.lua')(O); O.pack_validator.install()
    O.tag_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_validator.lua')(O); O.tag_validator.install()
    O.tag_chain_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_chain_validator.lua')(O); O.tag_chain_validator.install()
    O.tag_reward_validator=dofile(ORACLE_TEST_ROOT..'/debug/tag_reward_validator.lua')(O); O.tag_reward_validator.install()
    local tag,s,r=predict('tag_buffoon'); skip(tag)
    local chain=O.tag_chain_validator.chains[1]
    assert(chain and chain.complete and not chain.changed,'auto-open incorrectly treated as changed choice')
    assert(O.validator.counts.MISMATCH==0 and O.validator.counts.MATCH>=3,'pack validation did not complete')
    Card.open=old_open; CardArea.emplace=old_emplace
end)
test('Top-up respects Showman, depleted Common pool and existing Negative capacity',function()
    for _,showman in ipairs({false,true}) do
        fixture('TOPUP_POOLS',4); G.TEST_SHOWMAN=showman
        if showman then G.jokers:emplace(create_card('Joker',G.jokers,nil,nil,nil,nil,'j_ring_master')) end
        for _,c in ipairs(G.P_JOKER_RARITY_POOLS[1]) do G.GAME.used_jokers[c.key]=true end
        G.jokers.config.card_limit=6
        local before=#G.jokers.cards
        local tag,s,r=predict('tag_top_up'); skip(tag)
        local cards=actual_cards(G.jokers); for i=1,before do table.remove(cards,1) end
        eq(cards,r.effects[1].cards); eq(G.GAME.pseudorandom,r.details.rng_after); cases=cases+1
    end
end)
print(string.format('TAG REWARDS: %d tests passed; %d native skip reward scenarios',passed,cases))
