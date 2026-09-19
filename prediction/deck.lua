-- Observed stack order, not a seed reconstruction or simulated shuffle.
return function(O)
    local M,D={},O.data
    function M.card(card,g)
        local record=O.shop_snapshot.card(card,true)
        record.id=card.playing_card or card.sort_id
        record.base=D.copy(card.base or {})
        record.debuff=card.debuff or false
        -- Rank/suit mutations are authoritative even if a mod leaves card_key stale.
        local front=(g.P_CARDS or {})[record.front]
        if not front or front.suit~=record.base.suit or front.value~=record.base.value then
            record.front=nil
            for key,v in pairs(g.P_CARDS or {}) do
                if v.suit==record.base.suit and v.value==record.base.value then record.front=key; break end
            end
        end
        record.renderable=record.front~=nil and card.config.center.mod==nil
        return record
    end
    function M.identity(record)
        return {id=record.id,key=record.key,front=record.front,edition=record.edition,seal=record.seal,
            suit=record.base.suit,value=record.base.value}
    end
    function M.read(g)
        assert(g and g.STAGES and g.STAGE==g.STAGES.RUN and g.GAME and g.deck,'oracle_no_run')
        local out={next={},hand={},discard={},all={},game={
            pseudorandom=D.copy(g.GAME.pseudorandom),round=g.GAME.round,
            round_resets={ante=g.GAME.round_resets.ante}},state=g.STATE}
        for _,name in ipairs({'hand','discard'}) do
            for _,card in ipairs(g[name] and g[name].cards or {}) do out[name][#out[name]+1]=M.card(card,g) end
        end
        for _,card in ipairs(g.playing_cards or {}) do out.all[#out.all+1]=M.card(card,g) end
        -- Native CardArea.remove_card(nil) draws from the END of deck.cards.
        for i=#g.deck.cards,1,-1 do out.next[#out.next+1]=M.card(g.deck.cards[i],g) end
        local st=g.STATES or {}
        out.drawing_context=g.STATE==st.SELECTING_HAND or g.STATE==st.DRAW_TO_HAND or g.STATE==st.HAND_PLAYED
            or g.STATE==st.TAROT_PACK or g.STATE==st.SPECTRAL_PACK
        return out
    end
    function M.label(record)
        local rank=({Ace='A',King='K',Queen='Q',Jack='J'})[record.base.value] or record.base.value or '?'
        local suit=({Hearts='♥',Diamonds='♦',Clubs='♣',Spades='♠'})[record.base.suit] or record.base.suit or '?'
        return rank..suit
    end
    return M
end
