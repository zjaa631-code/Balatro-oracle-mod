return function(O)
    local M,D={},O.data
    function M.active(g)
        local b=g and g.GAME and g.GAME.blind
        local p=b and b.config and b.config.blind
        return g and g.STAGE==g.STAGES.RUN and g.STATE==g.STATES.SELECTING_HAND and
            b and not b.disabled and p and p.key=='bl_hook' and not p.mod and not p.press_play and
            g.hand and #g.hand.highlighted>0 and (g.GAME.current_round.hands_left or 0)>0 and
            g.play and #g.play.cards==0
    end
    function M.capture(g)
        assert(M.active(g),'oracle_hook_unavailable')
        local pr=g.GAME.pseudorandom
        local s={game={pseudorandom={seed=pr.seed,hashed_seed=pr.hashed_seed,hook=pr.hook},
            round_resets={ante=g.GAME.round_resets.ante},round=g.GAME.round},hand={},selected={}}
        for _,c in ipairs(g.hand.cards) do
            assert(c.playing_card and c.sort_id,'oracle_hook_unavailable')
            s.hand[#s.hand+1]={id=c.playing_card,sort_id=c.sort_id}
        end
        for _,c in ipairs(g.hand.highlighted) do s.selected[c.playing_card]=true end
        return s
    end
    function M.forecast(s)
        return O.ante_prediction.run(s,function(shadow,rng)
            local pool,targets={},{}
            for _,c in ipairs(shadow.hand) do if not shadow.selected[c.id] then pool[#pool+1]=c end end
            -- draw_card removes played cards before the Hook event. Each
            -- native pseudorandom_element sorts by sort_id, then returns the
            -- original pool index; remove exactly that entry for the next roll.
            for i=1,math.min(2,#pool) do
                local c,index=rng:element(pool,'hook')
                targets[#targets+1]=c.id; table.remove(pool,index)
            end
            return {targets=targets,status='experimental'}
        end)
    end
    return M
end
