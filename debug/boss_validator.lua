-- Compare deterministic Boss rules around the real callback, called exactly once.
-- Prediction reads detached records; no live Card helpers or RNG are invoked.
return function(O)
    local M,D={seen={},order={}},O.data
    local function enabled(b)
        local p=b and b.config and b.config.blind
        return O.config.validate_predictions and O.controller.supported() and G.GAME and
            G.GAME.pseudorandom and p and O.bosses.keys[p.key] and not p.mod and not G.SETTINGS.paused
    end
    local function warn(err)
        O.prediction_fault=true
        if sendWarnMessage then sendWarnMessage('BOSS validation: '..tostring(err),'Oracle') end
    end
    local function record(kind,s,expected,actual)
        local ok,err=pcall(function()
            local details={rng_before=s.game.pseudorandom,rng_after=D.copy(G.GAME.pseudorandom)}
            -- Native debuff checks may call a Stone's dummy random ID. Its sign
            -- alone matters; that native call is outside our prediction.
            local signature=kind..D.encode(s)..D.encode(expected)..D.encode(actual)
            if M.seen[signature] then return end
            M.seen[signature]=true; M.order[#M.order+1]=signature
            if #M.order>64 then M.seen[table.remove(M.order,1)]=nil end
            O.validator.record(kind,s,expected,actual,details)
        end)
        if not ok then warn(err) end
    end
    local function collect(...) return {n=select('#',...),...} end
    function M.install()
        if not Blind then return end
        local debuff_card=Blind.debuff_card
        if debuff_card then Blind.debuff_card=function(b,c,...)
            local s,expected
            if c and c.playing_card and not c.oracle_preview and enabled(b) then
                local ok=pcall(function()
                    s=O.bosses.context(G,SMODS,b); s.card=O.consumables.card(c); s.card.vampired=c.vampired
                    expected=O.bosses.card_effect(s,s.card).debuff
                end)
                if not ok then s=nil end
            end
            local ret=collect(debuff_card(b,c,...))
            if s then record('boss card:'..s.blind.key,s,expected,not not c.debuff) end
            return unpack(ret,1,ret.n)
        end end
        local debuff_hand=Blind.debuff_hand
        if debuff_hand then Blind.debuff_hand=function(b,cards,hands,name,check,...)
            local s,expected
            if enabled(b) then
                local ok=pcall(function()
                    s=O.bosses.context(G,SMODS,b); s.request={hand=name,count=#cards,poker_hands={},check=check}
                    for key,value in pairs(hands) do s.request.poker_hands[key]=not not next(value) end
                    local effect=O.bosses.hand_effect(s,s.request)
                    expected={blocked=effect.blocked,level=check and effect.level_before or effect.level_after,dollars=s.dollars}
                    if not check and s.blind.name=='The Ox' then expected.dollars=s.dollars+effect.money end
                end)
                if not ok then s=nil end
            end
            local ret=collect(debuff_hand(b,cards,hands,name,check,...))
            if s then record('boss hand:'..s.blind.key,s,expected,
                {blocked=not not ret[1],level=G.GAME.hands[name].level,dollars=G.GAME.dollars}) end
            return unpack(ret,1,ret.n)
        end end
        local modify_hand=Blind.modify_hand
        if modify_hand then Blind.modify_hand=function(b,cards,hands,name,mult,chips,...)
            local s,expected
            if enabled(b) then
                local ok=pcall(function()
                    s=O.bosses.context(G,SMODS,b); s.request={hand=name,count=#cards}
                    s.levels[name].mult=mult; s.levels[name].chips=chips
                    -- modify_hand is its own native callback, independent of
                    -- Eye/Mouth/size checks performed by debuff_hand.
                    local rule=D.copy(s); rule.blind.hands={}; rule.blind.only_hand=nil; rule.blind.debuff={}
                    local effect=O.bosses.hand_effect(rule,s.request)
                    expected={mult=effect.mult,chips=effect.chips,modified=effect.modified}
                end)
                if not ok then s=nil end
            end
            local ret=collect(modify_hand(b,cards,hands,name,mult,chips,...))
            if s then record('boss score base:'..s.blind.key,s,expected,{mult=ret[1],chips=ret[2],modified=not not ret[3]}) end
            return unpack(ret,1,ret.n)
        end end
    end
    return M
end
