-- Observe actual native RNG calls. Previews only use O.rng's private backend.
return function(O)
    local M,D={},O.data
    local target_keys={invisible=true,perkeo=true,madness=true,to_do=true,cert_fr=true,marb_fr=true}
    local chance_keys={space=true,gros_michel=true,cavendish=true,bloodstone=true,business=true,parking=true,
        ['8ball']=true,lucky_mult=true,lucky_money=true,glass=true}
    local generation={rif=true,car=true,sixth=true,vag=true,sup=true,sea=true,hal=true,['8ba']=true}
    local function enabled()
        return O.config.validate_predictions and O.controller.supported() and G.GAME and G.GAME.pseudorandom and not G.SETTINGS.paused
    end
    local function warn(err)
        O.prediction_fault=true
        if sendWarnMessage then sendWarnMessage('JOKER validation: '..tostring(err),'Oracle') end
    end
    local function record(kind,before,expected,actual,details)
        local ok,err=pcall(O.validator.record,kind,before,{value=expected,rng=details.rng_after},
            {value=actual,rng=D.copy(G.GAME.pseudorandom)},details)
        if not ok then warn(err) end
    end
    local function detached(value)
        if type(value)=='table' and value.config and value.config.center then
            local c=O.shop_snapshot.card(value); c.sort_id=value.sort_id; c.id=value.playing_card; return c
        end
        return D.copy(value)
    end
    function M.install()
        local probability=SMODS.pseudorandom_probability
        SMODS.pseudorandom_probability=function(card,key,n,d,identifier,no_mod,...)
            local before,expected,details
            if enabled() and (chance_keys[key] or type(key)=='string' and key:match('^halu%d+$')) then
                local ok=pcall(function()
                    before=O.jokers.base(G)
                    before.check={key=key,numerator=n,denominator=d,no_mod=no_mod,source=card and detached(card)}
                    before.owned={}; for _,v in ipairs(G.jokers.cards) do before.owned[#before.owned+1]=detached(v) end
                    expected,details=O.ante_prediction.run(before,function(s,rng) return O.jokers.roll(s,rng,key,n,d,no_mod) end)
                end)
                if not ok then before=nil end
            end
            local result=probability(card,key,n,d,identifier,no_mod,...)
            if before then record('joker probability:'..key,before,expected,result,details) end
            return result
        end
        local seed=pseudoseed
        pseudoseed=function(key,predict_seed,...)
            M.selection=nil
            if enabled() and target_keys[key] and not predict_seed then
                local ok,before=pcall(O.jokers.base,G)
                if ok then M.selection={key=key,before=before} end
            end
            local value=seed(key,predict_seed,...)
            if M.selection then M.selection.seed=value end
            return value
        end
        local element=pseudorandom_element
        pseudorandom_element=function(pool,seed_value,...)
            local pending=M.selection; M.selection=nil
            local expected,details
            if pending and pending.seed==seed_value and enabled() then
                local ok=pcall(function()
                    local copied={}; for k,v in pairs(pool) do copied[k]=detached(v) end
                    pending.before.pool=copied
                    expected,details=O.ante_prediction.run(pending.before,function(s,rng)
                        local value,index=rng:element(s.pool,pending.key)
                        return {value=value,index=index}
                    end)
                end)
                if not ok then pending=nil end
            else pending=nil end
            local value,index=element(pool,seed_value,...)
            if pending then
                local ok,err=pcall(function() record('joker target:'..pending.key,pending.before,expected,
                    {value=detached(value),index=index},details) end)
                if not ok then warn(err) end
            end
            return value,index
        end
        local random=pseudorandom
        pseudorandom=function(key,lo,hi,...)
            local before,expected,details
            if key=='misprint' and enabled() then
                local ok=pcall(function()
                    before=O.jokers.base(G)
                    expected,details=O.ante_prediction.run(before,function(s,rng) return rng:random(key,lo,hi) end)
                end)
                if not ok then before=nil end
            end
            local value=random(key,lo,hi,...)
            if before then record('joker value:misprint',before,expected,value,details) end
            return value
        end
        for key,field in pairs(O.jokers.resets) do
            local method=({j_idol='reset_idol_card',j_mail='reset_mail_rank',j_ancient='reset_ancient_card',j_castle='reset_castle_card'})[key]
            local native=_G[method]
            if native then
                _G[method]=function(...)
                    local before,expected,details
                    if enabled() then
                        local ok=pcall(function()
                            before=O.jokers.base(G); before.trigger.round=D.copy(G.GAME.current_round); before.trigger.playing={}
                            for _,c in ipairs(G.playing_cards) do
                                assert(not c.config.center.mod,'oracle_action_unsupported')
                                before.trigger.playing[#before.trigger.playing+1]=O.consumables.card(c)
                            end
                            expected,details=O.ante_prediction.run(before,function(s,rng) return O.jokers.reset(s,rng,key) end)
                        end)
                        if not ok then before=nil end
                    end
                    local ret
                    local function collect(...) ret={n=select('#',...),...} end
                    collect(native(...))
                    if before then record('joker reset:'..key,before,expected,D.copy(G.GAME.current_round[field]),details) end
                    O.controller.invalidate()
                    return unpack(ret,1,ret.n)
                end
            end
        end
        local create=create_card
        create_card=function(kind,area,legendary,rarity,skip,soulable,forced,append,...)
            local before,expected,details
            if generation[append] and enabled() then
                local ok=pcall(function()
                    before=O.shop_snapshot.capture(G,SMODS,true)
                    assert(not before.shop.unsupported,'oracle_action_unsupported')
                    expected,details=O.ante_prediction.run(before,function(s,rng)
                        return O.shop_prediction.create(s,rng,kind,append,{area='owned',legendary=legendary,rarity=rarity,soulable=soulable,forced=forced})
                    end)
                end)
                if not ok then before=nil end
            end
            local card=create(kind,area,legendary,rarity,skip,soulable,forced,append,...)
            if before then record('joker creation:'..append,before,expected,O.shop_snapshot.card(card),details) end
            return card
        end
        local poll=SMODS.poll_seal
        if poll then
            SMODS.poll_seal=function(args,...)
                local before,expected,details
                if args and args.type_key=='certsl' and args.guaranteed and not args.options and enabled() then
                    local ok=pcall(function()
                        before=O.jokers.capture(G,SMODS,G.jokers.cards[1])
                        expected,details=O.ante_prediction.run(before,O.jokers.guaranteed_seal)
                    end)
                    if not ok then before=nil end
                end
                local seal=poll(args,...)
                if before then record('joker seal:certsl',before,expected,seal,details) end
                return seal
            end
        end
    end
    return M
end
