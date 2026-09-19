-- A conditional sequence of the same eligible event, not a future turn script.
return function(O)
    local M,D={},O.data
    function M.supported(kind,key)
        if kind=='consumable' then return key=='c_wheel_of_fortune' end
        return kind=='joker' and (O.jokers.probabilities[key]~=nil or key=='m_lucky' or key=='j_misprint')
    end
    function M.forecast(snapshot,request)
        local kind,depth=request.kind,request.depth or 5
        assert(type(depth)=='number' and depth%1==0 and depth>=1 and depth<=20,'oracle_action_unsupported')
        return O.ante_prediction.run(snapshot,function(s,rng)
            local key=kind=='consumable' and s.action.key or s.trigger.source.key
            assert(M.supported(kind,key) and not s.shop.unsupported,'oracle_action_unsupported')
            local out={rows={},requested=depth,status='experimental',kind=kind,key=key}
            for i=1,depth do
                if kind=='consumable' then
                    local eligible=false
                    for _,c in ipairs(s.action.jokers) do if c.set=='Joker' and not c.edition then eligible=true end end
                    if not eligible then out.stop='oracle_event_no_target'; break end
                end
                local r=kind=='consumable' and O.consumables.apply(s,rng) or O.jokers.apply(s,rng,{})
                r.index=i; r.rng_after=D.copy(rng.state)
                out.rows[#out.rows+1]=D.copy(r)
                if r.inactive then out.stop=r.inactive; break end
                -- Consumable.apply already updates editions in shadow jokers.
                if kind=='joker' then
                    for _,c in ipairs(r.created) do s.trigger.inventory[#s.trigger.inventory+1]=D.copy(c) end
                    if (key=='m_glass' or key=='j_gros_michel' or key=='j_cavendish') and r.checks[1].success then
                        out.stop='oracle_event_destroy_boundary'; break
                    end
                end
            end
            return out
        end)
    end
    return M
end
