return function(O)
    local M={pending=nil}
    function M.install()
        if not Card or not CardArea then return end
        local original_open=Card.open
        if original_open then Card.open=function(card,...)
            M.pending=nil
            if O.config.validate_predictions and O.controller.supported() and card.ability.set=='Booster' then
                local ok=pcall(function()
                    local s=O.pack_prediction.capture(G,SMODS)
                    local expected,details=O.pack_prediction.forecast(s,{key=card.config.center.key,size=card.ability.extra})
                    for _,c in ipairs(expected) do c.legendary=nil end
                    M.pending={input=s,expected=expected,details=details,key=card.config.center.key}
                end)
                if not ok then M.pending=nil; O.validator.counts.SKIP=O.validator.counts.SKIP+1 end
            end
            return original_open(card,...)
        end end
        local original_emplace=CardArea.emplace
        if original_emplace then CardArea.emplace=function(area,card,...)
            local result=original_emplace(area,card,...)
            local pending=M.pending
            if pending and area==G.pack_cards and #area.cards>=#pending.expected then
                M.pending=nil
                local ok,err=pcall(function()
                    local actual={}; for i,c in ipairs(area.cards) do actual[i]=O.shop_snapshot.card(c) end
                    O.validator.record('pack:'..pending.key,pending.input,
                        {cards=pending.expected,rng=pending.details.rng_after},
                        {cards=actual,rng=O.data.copy(G.GAME.pseudorandom)},pending.details)
                    if pending.reward_tag then O.tag_validator.finish_reward(pending.reward_tag,actual) end
                end)
                if not ok then O.prediction_fault=true; if sendWarnMessage then sendWarnMessage(tostring(err),'Oracle') end end
            end
            return result
        end end
        local original_create=create_card
        if original_create then create_card=function(kind,area,legendary,rarity,skip,soulable,forced,append)
            local before,expected,details
            if legendary and append=='sou' and O.config.validate_predictions and O.controller.supported() then
                local ok=pcall(function()
                    before=O.pack_prediction.capture(G,SMODS)
                    assert(not before.shop.unsupported and not before.shop.pack_unsupported,'oracle_pack_unsupported')
                    expected,details=O.ante_prediction.run(before,function(s,rng)
                        return O.shop_prediction.create(s,rng,'Joker','sou',{area='owned',legendary=true})
                    end)
                end)
                if not ok then before=nil; O.validator.counts.SKIP=O.validator.counts.SKIP+1 end
            end
            local result=original_create(kind,area,legendary,rarity,skip,soulable,forced,append)
            if before then
                local ok,err=pcall(O.validator.record,'Soul',before,{card=expected,rng=details.rng_after},
                    {card=O.shop_snapshot.card(result),rng=O.data.copy(G.GAME.pseudorandom)},details)
                if not ok then O.prediction_fault=true; if sendWarnMessage then sendWarnMessage(tostring(err),'Oracle') end end
            end
            return result
        end end
    end
    return M
end
