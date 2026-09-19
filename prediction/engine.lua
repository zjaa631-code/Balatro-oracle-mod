-- Data-only dispatch boundary. Adapters keep their own tested source semantics.
return function(O)
    local M={adapters={}}
    function M.register(name,fn) assert(not M.adapters[name]); M.adapters[name]=fn end
    function M.predict(name,shadow,request)
        return assert(M.adapters[name],'oracle_action_unsupported')(O.data.copy(shadow),O.data.copy(request or {}))
    end
    M.register('consumable',function(s) return O.consumables.forecast(s) end)
    M.register('deck_consumable',function(s) return O.deck_state.forecast(s) end)
    M.register('joker',function(s,r) return O.jokers.forecast(s,r) end)
    M.register('events',function(s,r) return O.events.forecast(s,r) end)
    M.register('boss_analysis',function(s,r) return O.bosses.analyze(s,r) end)
    M.register('hook',function(s) return O.hook.forecast(s) end)
    M.register('shop',function(s,r) return O.shop_prediction.forecast(s,r.depth or 3) end)
    M.register('pack',function(s,r) return O.pack_prediction.forecast(s,r) end)
    M.register('ante',function(s,r) return O.ante_prediction.forecast(s,r.depth or 3) end)
    M.register('boss_reroll',function(s,r) return O.ante_prediction.rerolls(s,r.depth or 3) end)
    M.register('tag',function(s) return O.tag_prediction.forecast(s) end)
    return M
end
