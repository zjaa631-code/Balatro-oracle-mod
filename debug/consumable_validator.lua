return function(O)
    local M={pending={},generation=0}
    function M.reset()
        M.generation=M.generation+1; M.pending={}; M.purchase=nil
    end
    local function settle(tx)
        if tx.done then return true end
        if tx.generation~=M.generation or tx.game~=G.GAME or (O.undo and O.undo.restoring) then
            tx.done=true; return true
        end
        if (G.CONTROLLER.locks or {}).use or (G.GAME.STOP_USE or 0)>0 then return false end
        tx.done=true
        local before,expected,details=tx.before,tx.expected,tx.details
        local ok,err=pcall(function()
            O.validator.record('consumable:'..before.action.key,before,
                {effects=O.consumables.expected(expected),rng=details.rng_after,deck=tx.deck_expected},
                {effects=O.consumables.observe(before,G),rng=O.data.copy(G.GAME.pseudorandom),
                    deck=tx.deck_expected and O.deck_state.projection(O.deck_state.capture(G,SMODS),not before.deck_state.pack,before.deck_state) or nil},details)
        end)
        if not ok then O.prediction_fault=true; if sendWarnMessage then sendWarnMessage(tostring(err),'Oracle') end end
        O.controller.invalidate()
        return true
    end
    function M.flush()
        local waiting={}
        for _,tx in ipairs(M.pending) do if not settle(tx) then waiting[#waiting+1]=tx end end
        M.pending=waiting
    end
    function M.install()
        local original=Card and Card.use_consumeable
        if not original then return end
        local use_card=G.FUNCS.use_card
        if use_card then
            G.FUNCS.use_card=function(e,...)
                -- Input can arrive after native use locks clear but before the
                -- nonblocking validation event gets its next turn. Observe the
                -- previous card before the new action removes/uses its result.
                M.flush()
                -- Native buy_from_shop queues ease_dollars(-cost), then calls
                -- use_card synchronously. That payment has not settled when
                -- use_consumeable captures its input, but precedes its effects.
                local previous=M.purchase
                local config=e and e.config
                M.purchase=config and config.id=='buy_and_use' and
                    {card=config.ref_table,cost=config.ref_table.cost or 0} or nil
                local args={n=select('#',...),...}; local ret
                local ok,err=pcall(function() ret={n=0}
                    local function collect(...) ret={n=select('#',...),...} end
                    collect(use_card(e,unpack(args,1,args.n)))
                end)
                M.purchase=previous
                if not ok then error(err,0) end
                return unpack(ret,1,ret.n)
            end
        end
        Card.use_consumeable=function(card,area,copier,...)
            if card.oracle_preview then return original(card,area,copier,...) end
            local before,expected,details,deck_expected
            if O.config.validate_predictions and O.controller.supported() and not copier then
                local ok=pcall(function()
                    before=O.consumables.capture(G,SMODS,card,true)
                    if M.purchase and M.purchase.card==card then
                        before.action.purchase_cost=M.purchase.cost
                        before.action.dollars=before.action.dollars-M.purchase.cost
                    end
                    expected,details=O.engine.predict('consumable',before)
                    if O.deck_state and before.deck_state then
                        local modeled,world=pcall(O.deck_state.materialize,before,expected)
                        if modeled then deck_expected=O.deck_state.projection(world,not world.pack)
                        else details.deck_boundary=tostring(world) end
                    end
                end)
                if not ok then before=nil; O.validator.counts.SKIP=O.validator.counts.SKIP+1 end
            end
            local ret
            local function collect(...) ret={n=select('#',...),...} end
            collect(original(card,area,copier,...))
            if before then
                local tx={before=before,expected=expected,details=details,deck_expected=deck_expected,
                    generation=M.generation,game=G.GAME}
                M.pending[#M.pending+1]=tx
                G.E_MANAGER:add_event(Event({trigger='after',delay=0,blocking=false,blockable=false,func=function()
                    if tx.done or tx.generation~=M.generation or tx.game~=G.GAME then return settle(tx) end
                    M.flush()
                    return tx.done or false
                end}))
            end
            return unpack(ret,1,ret.n)
        end
        for _,name in ipairs({'buy_from_shop','sell_card','reroll_shop','reroll_boss','play_cards_from_highlighted',
            'discard_cards_from_highlighted','select_blind','skip_blind','toggle_shop','cash_out','skip_booster'}) do
            local action=G.FUNCS[name]
            if action then G.FUNCS[name]=function(...) M.flush(); return action(...) end end
        end
    end
    return M
end
