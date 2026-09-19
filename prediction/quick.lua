-- On-hover snapshots only; rendering never advances a live random stream.
return function(O)
    local M={cache={},count=0}
    function M.get(kind,card)
        assert(O.controller.supported(),'oracle_prediction_unavailable')
        local s,request
        if kind=='pack' then
            assert(O.config.show_packs~=false,'oracle_feature_hidden')
            s=O.pack_prediction.capture(G,SMODS)
            assert(s.shop.active and not s.shop.pack_open and not s.shop.transition,'oracle_pack_wait')
            request={key=card.config.center.key,size=card.ability.extra}
        elseif kind=='consumable' then
            s=O.consumables.capture(G,SMODS,card)
        elseif kind=='joker' then
            s=O.jokers.capture(G,SMODS,card)
            if O.jokers.resets[card.config.center.key] then request={ante=O.jokers.next_reset_ante(G)} end
        elseif kind=='deck' then
            assert(O.config.show_draw_order~=false,'oracle_feature_hidden')
            -- Native stack is authoritative. Never pretend the end-of-round
            -- stack is the next Blind's as-yet-unshuffled draw order.
            s=O.deck_prediction.read(G)
            assert(s.drawing_context,'oracle_deck_reshuffle')
        else error('oracle_action_unsupported') end
        local sig=O.data.encode({s=s,request=request})
        local cached=M.cache[kind]
        if cached and cached.sig==sig then
            if cached.error then error(cached.error) end
            return O.data.copy(cached.result)
        end
        local ok,r=pcall(function()
            if kind=='deck' then return {cards=s.next,status='observed'} end
            if kind=='pack' then return {cards=O.engine.predict('pack',s,request),status='experimental'} end
            if kind=='joker' then return O.engine.predict('joker',s,request) end
            return O.engine.predict('consumable',s)
        end)
        M.count=M.count+1
        M.cache[kind]={sig=sig,result=ok and r or nil,error=not ok and tostring(r) or nil}
        if not ok then error(r) end
        return O.data.copy(r)
    end
    return M
end
