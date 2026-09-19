local O,D=ORACLE,ORACLE.data
local passed=0
local function eq(a,b,label) assert(D.encode(a)==D.encode(b),(label or '')..'\nExpected '..D.encode(b)..'\nActual '..D.encode(a)) end
local function test(name,fn) ORACLE_TEST_CASE=name; fn(); passed=passed+1; print('PASS '..name) end
local function memory()
    local files,dirs={},{}
    return {files=files,dirs=dirs,time=function() return 12345 end,
        exists=function(path) return files[path]~=nil or dirs[path]~=nil end,
        mkdir=function(path) dirs[path]=true end,
        write=function(path,data) files[path]=D.copy(data) end,
        read=function(path) local value=assert(files[path],'oracle_undo_corrupt'); return D.copy(value) end}
end
local function snapshot(n)
    return {VERSION='1.0.1o-FULL',STATE=3,GAME={round=n,dollars=n*5,round_resets={ante=2},pseudorandom={seed='UNDO',shop=n/20}},
        cardAreas={deck={cards={{rank=n}},config={card_limit=52}}},tags={},BLIND={name='Small Blind'},BACK={name='Blue Deck'},SCORING_CALC={key='multiply'}}
end
test('Undo checkpoint isolation, action grouping, branching and saved RNG across 100 operations',function()
    local disk=memory(); local h=dofile(ORACLE_TEST_ROOT..'/undo/history.lua')(O,disk); h.new(1)
    h.observe(snapshot(0))
    for i=1,100 do h.begin_action(); h.observe(snapshot(i)); h.observe(snapshot(i)) end
    eq(#h.index.undo,100)
    for i=99,0,-1 do
        local s,id=h.target(); eq(s,snapshot(i)); s.GAME.dollars=-100; eq(h.target(),snapshot(i))
        h.restored(id)
    end
    assert(not h.target()); h.observe(snapshot(500)); h.begin_action(); h.observe(snapshot(501))
    eq(h.target(),snapshot(500)); assert(h.index.serial>100)
end)
test('Undo persists across restarts, isolates profiles and new runs and falls back from corrupt index',function()
    local disk=memory(); local factory=dofile(ORACLE_TEST_ROOT..'/undo/history.lua')
    local h=factory(O,disk); local run=h.new(1); h.observe(snapshot(0)); h.begin_action(); h.observe(snapshot(1))
    local resumed=factory(O,disk); assert(resumed.attach(1,run)); eq(resumed.target(),snapshot(0))
    assert(not factory(O,disk).attach(2,run)); assert(not factory(O,disk).attach(1,'wrong'))
    disk.files['oracle-undo/1/index'..(h.index.generation%2)..'.jkr']=nil
    assert(resumed.attach(1,run)); eq(resumed.target(),snapshot(0))
    local next_run=resumed.new(1); assert(next_run~=run); assert(not resumed.target())
    assert(not pcall(resumed.new,'../profile'))
end)
test('Undo write errors and corrupt checkpoint fail before restore and never overwrite existing points',function()
    local disk=memory(); local h=dofile(ORACLE_TEST_ROOT..'/undo/history.lua')(O,disk); h.new(1); h.observe(snapshot(0))
    local before=D.copy(h.index); local write=disk.write
    disk.write=function() error('oracle_undo_write') end
    assert(not pcall(h.begin_action)); eq(h.index,before)
    assert(not pcall(h.observe,snapshot(1))); eq(h.index,before)
    disk.write=write; h.begin_action(); h.observe(snapshot(1))
    local target=h.index.undo[1]; disk.files['oracle-undo/1/'..h.index.run..'/'..target..'.jkr'].profile=2
    assert(not pcall(h.target))
end)
local function fixture(tick)
    local disk=memory(); local h=dofile(ORACLE_TEST_ROOT..'/undo/history.lua')(O,disk)
    local manager={queues={base={}},clear_queue=function(self)
        for _,q in pairs(self.queues) do for i=#q,1,-1 do if not q[i].no_delete then table.remove(q,i) end end end
    end,add_event=function(self,e) self.queues.base[#self.queues.base+1]=e end}
    local writes={}
    local st={BLIND_SELECT=1,SELECTING_HAND=2,SHOP=3,ROUND_EVAL=4,GAME_OVER=5,TAROT_PACK=6,PLANET_PACK=7,
        SPECTRAL_PACK=8,BUFFOON_PACK=9,STANDARD_PACK=10,SMODS_BOOSTER_OPENED=999}
    local rebuild
    Game={update=tick or function() end,delete_run=function(self)
        self.GAME.won=false; self.STATE=-1; self.E_MANAGER:clear_queue()
    end,start_run=function(self,args)
        local save=args.savetext
        self.GAME=D.copy(save.GAME); self.STATE=save.STATE; self.STATE_COMPLETE=true
        self.CONTROLLER.locks={load=true}; self.STAGE=self.STAGES.RUN
        for k,area in pairs(save.cardAreas) do self[k]=rebuild(area) end
        local function obj(data) return {is=function(_,kind) return kind==Object end,save=function() return D.copy(data) end} end
        self.GAME.blind=obj(save.BLIND)
        self.GAME.selected_back=obj(save.BACK)
        self.GAME.current_scoring_calculation=obj(save.SCORING_CALC)
        self.GAME.tags={}
        self.GAME.pseudorandom.shop=0.987 -- injected constructor-side drift
        return 'loaded',nil,42
    end}
    G=setmetatable({VERSION='1.0.1o-FULL',STATE=st.SHOP,STATES=st,STATE_COMPLETE=true,STAGE=1,STAGES={RUN=1},
        SETTINGS={profile=1},PROFILES={[1]={wins=17,unlocked=true}},GAME=snapshot(0).GAME,
        E_MANAGER=manager,CONTROLLER={locks={}},ARGS={},FILE_HANDLER={},sort_id=20,playing_card=52,
        SAVE_MANAGER={channel={push=function(_,value) writes[#writes+1]=D.copy(value) end}},FUNCS={}}, {__index=Game})
    CardArea={}; Object={}; Tag={}
    dofile(ORACLE_TEST_SOURCE..'/undo_truth.lua')
    local function area(cards)
        local out={cards=cards,config={card_limit=5}}
        out.is=function(_,kind) return kind==CardArea end
        out.save=CardArea.save
        for _,c in ipairs(cards) do c.save=function(self) return {id=self.id,ability=D.copy(self.ability),joker_added_to_deck_but_debuffed=self.joker_added_to_deck_but_debuffed} end end
        return out
    end
    rebuild=function(saved) local out=area(D.copy(saved.cards)); out.config=D.copy(saved.config); return out end
    G.jokers=area({{id=1,ability={name='Blueprint',eternal=true}}}); G.deck=area({{id=2,ability={name='Steel'}}})
    local function obj(data) return {is=function(_,kind) return kind==Object end,save=function() return D.copy(data) end} end
    G.GAME.blind=obj({name='Small Blind'})
    G.GAME.selected_back=obj({name='Blue Deck'})
    G.GAME.current_scoring_calculation=obj({key='multiply'})
    G.GAME.tags={}; G.GAME.won=true
    Event=function(x) return x end
    G.FUNCS.wipe_on=function() end; G.FUNCS.wipe_off=function() end
    G.FUNCS.exit_overlay_menu=function() G.OVERLAY_MENU=nil; G.SETTINGS.paused=false end
    G.FUNCS.evaluate_round=function() G.PROFILES[1].wins=G.PROFILES[1].wins+1; G.GAME.current_round.dollars=999 end
    for _,key in ipairs({'play_cards_from_highlighted','discard_cards_from_highlighted','buy_from_shop','sell_card','use_card',
        'reroll_shop','reroll_boss','select_blind','skip_blind','toggle_shop','cash_out'}) do
        G.FUNCS[key]=function() G.GAME.dollars=G.GAME.dollars+1; return key,nil,13 end
    end
    O.status={issues={}}; O.config.enabled=true; O.prediction_fault=nil
    O.undo=dofile(ORACLE_TEST_ROOT..'/undo/runtime.lua')(O,h); O.undo.install()
    local function drain()
        local n=0
        while #manager.queues.base>0 do n=n+1; assert(n<100); local e=table.remove(manager.queues.base,1); e.func() end
    end
    return h,disk,writes,drain
end
test('Native save serializer checkpoints every action, preserves returns and does not alter RNG or global progress',function()
    for _,name in ipairs({'play_cards_from_highlighted','discard_cards_from_highlighted','buy_from_shop','sell_card','use_card',
        'reroll_shop','reroll_boss','select_blind','skip_blind','toggle_shop','cash_out'}) do
        local h=fixture(); local rng=D.copy(G.GAME.pseudorandom); local stats=D.copy(G.PROFILES)
        math.randomseed(712); local draw=math.random(); math.randomseed(712)
        local a,b,c=G.FUNCS[name](); eq({a,b,c},{name,nil,13}); eq(math.random(),draw)
        eq(h.target().GAME.dollars,0); eq(h.target().cardAreas.jokers.cards[1].ability.eternal,true)
        eq(G.GAME.pseudorandom,rng); eq(G.PROFILES,stats)
        assert(type(STR_PACK(h.target()))=='string')
    end
end)
test('Action settlement groups delayed saves then records subsequent native-only saved changes',function()
    local h=fixture(); G.FUNCS.buy_from_shop(); save_run()
    G.E_MANAGER:add_event({blocking=true,func=function() return true end})
    O.undo.update(1); assert(h.index.transaction)
    G.E_MANAGER.queues.base={}; O.undo.update(1); assert(not h.index.transaction)
    eq(#h.index.undo,1)
    G.GAME.dollars=73; save_run()
    eq(#h.index.undo,2); eq(h.target().GAME.dollars,1)
end)

test('Native queued restart restores checkpoint and RNG, cancels stale events and saves through FIFO',function()
    local h,disk,writes,drain=fixture()
    G.FUNCS.buy_from_shop(); local target=D.copy((h.target())); local stats=D.copy(G.PROFILES)
    G.SAVE_MANAGER.channel:push({type='save_run',save_table={old=true},profile_num=1})
    G.E_MANAGER:add_event({no_delete=true,func=function() error('stale old-run event') end})
    O.quick.cache={old=true}; SMODS.OPENED_BOOSTER={old=true}; G.TAROT_INTERRUPT=3
    assert(O.undo.restore()); assert(not O.controller.supported()); assert(not O.undo.restore())
    eq(writes[1].save_table,{old=true}); eq(writes[2].save_table,target)
    assert(not G.FILE_HANDLER.run and not SMODS.OPENED_BOOSTER and not G.TAROT_INTERRUPT)
    drain(); eq(G.GAME.dollars,target.GAME.dollars); eq(G.GAME.pseudorandom,target.GAME.pseudorandom)
    assert(O.undo.restoring); G.CONTROLLER.locks.load=nil; O.undo.update(4)
    assert(not O.undo.restoring and G.FILE_HANDLER.force and G.FILE_HANDLER.run)
    eq(G.GAME.pseudorandom,target.GAME.pseudorandom); eq(G.PROFILES,stats)
    eq(#h.index.undo,0); assert(O.controller.supported()); eq(O.quick.cache,{})
    assert(type(O.tag_validator.pending)=='table' and getmetatable(O.tag_validator.pending).__mode=='k')
    assert(not G.CONTROLLER.locks.oracle_undo)
end)
test('Booster ACTION is retained for native Continue but never replayed by Undo; loss remains undoable',function()
    local h=fixture(); G.FUNCS.use_card()
    save_with_action({type='use_card',card=1})
    assert(G.ARGS.save_run.ACTION and not h.target().ACTION)
    G.STATE=G.STATES.TAROT_PACK; local serial=h.index.serial
    save_run(); eq(h.index.serial,serial); G.FUNCS.use_card(); eq(#h.index.undo,1)
    assert(O.undo.ready())
    G.STATE=G.STATES.GAME_OVER; G.SAVED_GAME=nil; G.FILE_HANDLER.run=nil
    assert(O.undo.ready()); assert(O.undo.restore())
end)
test('Pack Undo survives native update frames before delete and load, including paused and accelerated frames',function()
    for _,state in ipairs({'SMODS_BOOSTER_OPENED','TAROT_PACK','PLANET_PACK','SPECTRAL_PACK','BUFFOON_PACK','STANDARD_PACK'}) do
        for _,dt in ipairs({0,0.00421868,1,10}) do
            local h,disk,writes,drain=fixture(function(self,delta) ORACLE_TEST_BOOSTER_UPDATE(self,delta) end)
            local calls=0
            local tick=function() calls=calls+1 end
            for _,name in ipairs({'update_arcana_pack','update_celestial_pack','update_spectral_pack','update_buffoon_pack','update_standard_pack'}) do
                Game[name]=tick
            end
            G.FUNCS.use_card(); local expected=D.copy((h.target()))
            G.STATE=G.STATES[state]; G.STATE_COMPLETE=true
            SMODS.OPENED_BOOSTER={config={center={update_pack=tick}}}
            G:update(dt); eq(calls,1) -- normal pack updates are still dispatched
            assert(O.undo.restore()); assert(not SMODS.OPENED_BOOSTER)
            for i=1,3 do G:update(dt) end -- native start_run has only queued events
            eq(calls,1); assert(O.undo.restoring)
            table.remove(G.E_MANAGER.queues.base,1).func() -- only delete_run
            G:update(dt); eq(calls,1)
            drain(); G:update(dt); assert(O.undo.restoring)
            G.CONTROLLER.locks.load=nil; G:update(dt)
            assert(not O.undo.restoring); eq(G.STATE,expected.STATE)
            eq(G.GAME.pseudorandom,expected.GAME.pseudorandom); eq(G.GAME.dollars,expected.GAME.dollars)
            eq(#h.index.undo,0)
        end
    end
end)

test('Undo restores global physical card order without using duplicate sort IDs and native omitted debuff flags',function()
    local h,disk,writes,drain=fixture()
    G.hand={cards={G.deck.cards[1]},is=G.deck.is,save=G.deck.save,config={card_limit=8}}
    G.deck.cards={{id=3,ability={name='Lucky'},save=G.jokers.cards[1].save}}; G.playing_cards={G.hand.cards[1],G.deck.cards[1]}
    G.hand.cards[1].sort_id=42; G.deck.cards[1].sort_id=42
    G.jokers.cards[1].joker_added_to_deck_but_debuffed=true
    G.FUNCS.play_cards_from_highlighted(); assert(O.undo.restore()); drain()
    G.CONTROLLER.locks.load=nil; O.undo.update(4)
    assert(G.playing_cards[1]==G.hand.cards[1] and G.playing_cards[2]==G.deck.cards[1])
    assert(G.jokers.cards[1].joker_added_to_deck_but_debuffed)
end)
test('Loading and action locks, foreign profiles, unsupported versions and failed writes block Undo safely',function()
    local h,disk,writes=fixture(); G.FUNCS.buy_from_shop()
    for _,key in ipairs({'load','use','selling_card','shop_reroll'}) do G.CONTROLLER.locks[key]=true; assert(not O.undo.restore()); G.CONTROLLER.locks[key]=nil end
    G.SETTINGS.profile=2; assert(not O.undo.restore()); G.SETTINGS.profile=1
    O.status.issues={'bad version'}; assert(not O.undo.restore()); O.status.issues={}
    G.SAVE_MANAGER.channel.push=function() error('cannot queue') end
    local before=D.copy(G.GAME.pseudorandom); assert(not O.undo.restore()); assert(not O.undo.restoring)
    eq(G.GAME.pseudorandom,before); eq(#h.index.undo,1); eq(#writes,0)
end)
test('Continue attaches durable history without mapping the incoming save to old live cards',function()
    local h=fixture(); G.FUNCS.buy_from_shop(); save_run()
    local incoming=D.copy(G.ARGS.save_run); local before=D.copy(incoming)
    G.playing_cards={{unrelated_old_entity=true}}
    G:start_run({savetext=incoming})
    assert(not O.undo.error); eq(incoming,before); eq(#h.index.undo,1)
    G.playing_cards=nil; G.CONTROLLER.locks.load=nil; G.FUNCS.buy_from_shop()
    assert(not O.undo.error); eq(#h.index.undo,2)
end)

test('Settled cash-out restores its saved total without re-running reward tags or global statistics',function()
    local h,disk,writes,drain=fixture()
    G.STATE=G.STATES.ROUND_EVAL; G.GAME.current_round={dollars=37}
    save_run(); assert(not h.index)
    G.FUNCS.cash_out(); eq(h.target().ORACLE_UNDO.cashout,37)
    assert(O.undo.restore()); drain(); G.CONTROLLER.locks.load=nil
    O.undo.update(4); assert(O.undo.restoring) -- wait for native evaluation UI
    local row; add_round_eval_row=function(config) row=config; G.GAME.current_round.dollars=config.dollars end
    G.FUNCS.evaluate_round(); eq(row,{name='bottom',dollars=37}); eq(G.PROFILES[1].wins,17)
    O.undo.update(4); assert(not O.undo.restoring); eq(G.GAME.current_round.dollars,37)
end)

test('Undo native page and F9 obey readiness without entering the prediction engine',function()
    fixture()
    G.UIT={ROOT=1,R=2,C=3,T=4,O=5,B=6}
    local colour={}; G.C={ORANGE=colour,RED=colour,WHITE=colour,BLACK=colour,CLEAR=colour,
        UI={TEXT_INACTIVE=colour,TEXT_LIGHT=colour,BACKGROUND_INACTIVE=colour}}
    local binding,old= nil,SMODS.Keybind
    SMODS.Keybind=function(args) binding=args end
    local ui=dofile(ORACLE_TEST_ROOT..'/ui/undo.lua')(O); ui.install(); assert(binding.key_pressed=='f9')
    local tree=ui.definition(); assert(tree.n==G.UIT.ROOT)
    local button={config={}}; G.FUNCS.oracle_undo_can(button); assert(not button.config.button)
    G.FUNCS.buy_from_shop(); local ready,reason=O.undo.ready(); assert(ready,reason)
    G.FUNCS.oracle_undo_can(button); eq(button.config.button,'oracle_undo_apply')
    local restore=O.undo.restore; local count=0
    O.undo.restore=function() count=count+1; return true end
    binding.action(); eq(count,1)
    O.undo.restoring=true; binding.action(); eq(count,1); O.undo.restoring=false
    G.CONTROLLER.text_input_hook=true; binding.action(); eq(count,1)
    O.undo.restore=restore; SMODS.Keybind=old
end)
test('Native Card and CardArea save/load preserve ordered decks, editions, stickers, seals and sale prices',function()
    fixture()
    local noop=function() end
    Card={set_sprites=noop,set_card_area=function(self,a) self.area=a end}
    setmetatable(Card,{__call=function() return setmetatable({T={},VT={},children={},ID=1234},{__index=Card}) end})
    dofile(ORACLE_TEST_SOURCE..'/undo_card_truth.lua')
    Moveable=function() return {} end; remove_all=noop
    G.CARD_H=1.4; G.CARD_W=1; G.ID=2000
    G.P_CENTERS={c_base={name='Default',set='Default'},j_joker={name='Joker',set='Joker'}}
    G.P_CARDS={S_A={suit='Spades',value='Ace',id=14}}
    local function area()
        return setmetatable({cards={},children={},highlighted={},config={type='deck',card_limits={base=52,total_slots=52}},
            set_ranks=noop,align_cards=noop,hard_set_cards=noop},{__index=CardArea})
    end
    for seed=1,25 do
        local source=area()
        for i=1,52 do
            local c=Card(); c.config={center_key='c_base',card_key='S_A'}; c.params={}
            c.base={suit='Spades',value='Ace',id=14}; c.ability={name='Lucky',perma_bonus=i,eternal=i%2==0,perishable=i%3==0,rental=i%4==0}
            c.sort_id=i+seed; c.playing_card=i; c.seal=i%2==0 and 'Red' or 'Gold'
            c.edition={polychrome=true,key='e_polychrome'}; c.cost=seed; c.sell_cost=i
            c.facing=i%3==0 and 'back' or 'front'; c.added_to_deck=true; c.ignore_base_shader={}; c.ignore_shadow={}
            source.cards[#source.cards+1]=c
        end
        local saved=D.copy(source:save()); local restored=area(); restored:load(D.copy(saved))
        eq(restored:save(),saved,'native area roundtrip')
        assert(restored.cards[1]~=source.cards[1]); restored.cards[1].ability.perma_bonus=0
        eq(saved.cards[1].ability.perma_bonus,1,'checkpoint owns card data')
    end
end)
test('History storage roundtrips through actual LOVE compression/hash and rejects corruption or code access',function()
    local old_love=love
    assert(package.loadlib(ORACLE_TEST_GAME_DIR..'/love.dll','luaopen_love'))()
    require('love.data')
    local files={}
    love.filesystem={getInfo=function(path) return files[path] and {} end,
        read=function(path) return files[path] end,write=function(path,data) files[path]=data; return true end,
        createDirectory=function() return true end}
    local store=dofile(ORACLE_TEST_ROOT..'/undo/storage.lua')()
    local data={text='中文\n测试',snapshot=snapshot(7)}
    store.write('oracle-undo/1/test.jkr',data); eq(store.read('oracle-undo/1/test.jkr'),data)
    local good=files['oracle-undo/1/test.jkr']
    files['oracle-undo/1/test.jkr']=good:sub(1,20); assert(not pcall(store.read,'oracle-undo/1/test.jkr'))
    files['oracle-undo/1/test.jkr']=good:gsub('ORACLE1','ORACLE2',1); assert(not pcall(store.read,'oracle-undo/1/test.jkr'))
    local bad='return {secret=os.execute("should not run")}'
    files['oracle-undo/1/test.jkr']='ORACLE1 '..love.data.encode('string','hex',love.data.hash('sha256',bad))..'\n'..love.data.compress('string','deflate',bad,1)
    assert(not pcall(store.read,'oracle-undo/1/test.jkr'))
    love.filesystem.write=function() return false,'disk full' end
    assert(not pcall(store.write,'oracle-undo/1/test.jkr',data))
    love=old_love
end)
print('UNDO: '..passed..' test groups passed; native serializer and native restart callback exercised')
