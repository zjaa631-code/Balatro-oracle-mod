-- Reuse the runtime's native description logic in NEW Lua function objects.
-- The live functions/environments are never changed. Description-only probability
-- queries and random animated text are isolated from gameplay callbacks/RNG.
return function(O)
    local M={}
    local function clone(fn,env)
        assert(type(fn)=='function' and not debug.getupvalue(fn,1),'Unsupported tooltip wrapper')
        local copied=assert(loadstring(string.dump(fn)))
        setfenv(copied,env)
        return copied
    end
    function M.build(card)
        assert(not card.config.center.mod,'Custom descriptions require an adapter')
        local env=setmetatable({}, {__index=_G})
        -- Native enhancement/edition/seal descriptions also call loc_vars through
        -- center methods. Isolate that whole description call chain, including
        -- Lucky Card probabilities, without changing any prototype or closure.
        local seen,originals={},{}
        local function isolated(value)
            if type(value)=='function' then
                if not seen[value] then seen[value]=clone(value,env) end
                return seen[value]
            elseif type(value)=='table' then
                if not seen[value] then
                    seen[value]=setmetatable({}, {__index=function(_,key) return isolated(value[key]) end})
                    originals[seen[value]]=value
                    for i=1,#value do seen[value][i]=isolated(value[i]) end
                end
                return seen[value]
            end
            return value
        end
        env.pairs=function(t)
            local source=originals[t]
            if not source then return pairs(t) end
            return function(_,key)
                local k,v=next(source,key)
                if k~=nil then return k,isolated(v) end
            end,t,nil
        end
        env.copy_table=function(t)
            if originals[t] then t=originals[t] end
            return copy_table(t)
        end
        local smods=isolated(SMODS)
        smods.compat_0_9_8={}
        smods.get_probability_vars=function(_,n,d) return n*((G.GAME.probabilities or {}).normal or 1),d end
        smods.calculate_context=function() return {} end
        env.SMODS=smods
        env.DynaText=function(args)
            local safe={}; for k,v in pairs(args) do safe[k]=v end
            safe.random_element=false
            return DynaText(safe)
        end
        local generate=clone(generate_card_ui,env)
        env.generate_card_ui=function(center,...) return generate(isolated(center),...) end
        local native=clone(Card.generate_UIBox_ability_table,env)
        env.Card=setmetatable({generate_UIBox_ability_table=native},{__index=Card})
        local ui=native(card)
        local function append(text)
            ui.main[#ui.main+1]={{n=G.UIT.T,config={text=text,scale=0.28,colour=G.C.UI.TEXT_DARK}}}
        end
        if card.record.legendary then
            append(O.text.get('oracle_predicted')..' '..O.text.name('Joker',{key=card.record.legendary}))
        end
        if card.record.variant_unknown then append(O.text.get('oracle_cover_unknown')) end
        if O.config.advanced_info then
            append(O.text.get('oracle_card_key')..' '..card.record.key)
            local origin=card.record.oracle_origin
            if origin then
                if origin.ante then append(O.text.get('oracle_ante')..' '..origin.ante) end
                if origin.reroll then append(O.text.get('oracle_reroll')..' +'..origin.reroll) end
                if origin.pack then append(O.text.name('Booster',{key=origin.pack})) end
                append(O.text.get('oracle_slot')..' '..origin.slot)
            end
        end
        card.ability_UIBox_table=ui
        return G.UIDEF.card_h_popup(card)
    end
    return M
end
