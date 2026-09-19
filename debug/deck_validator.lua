return function(O)
    local M={}
    function M.install()
        if not CardArea or type(CardArea.draw_card_from)~='function' then return end
        local original=CardArea.draw_card_from
        CardArea.draw_card_from=function(area,from,...)
            local snapshot,expected
            if area==G.hand and from==G.deck and O.config.validate_predictions and O.controller.supported() then
                local ok=pcall(function()
                    snapshot=O.deck_prediction.read(G)
                    if snapshot.next[1] then expected=O.deck_prediction.identity(snapshot.next[1]) end
                end)
                if not ok then snapshot=nil; O.validator.counts.SKIP=O.validator.counts.SKIP+1 end
            end
            local result=original(area,from,...)
            if snapshot and expected and type(result)=='table' then
                local ok,err=pcall(function()
                    O.validator.record('draw',snapshot,expected,O.deck_prediction.identity(O.deck_prediction.card(result,G)),
                        {source='deck.cards[#deck.cards]',rng_before=snapshot.game.pseudorandom,
                            rng_after=O.data.copy(G.GAME.pseudorandom)})
                end)
                if not ok then O.prediction_fault=true; if sendWarnMessage then sendWarnMessage(tostring(err),'Oracle') end end
            end
            return result
        end
    end
    return M
end
