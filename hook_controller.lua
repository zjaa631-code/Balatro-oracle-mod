-- All live selection observation and forecasting happens here, never in draw.
return function(O)
    local M,D={targets={},elapsed=0,count=0},O.data
    local function pack(...) return {n=select('#',...),...} end
    function M.clear() M.targets={}; M.signature=nil end
    function M.update(dt,force)
        if not O.controller.supported() or not O.hook.active(G) then M.clear(); return end
        M.elapsed=M.elapsed+(dt or 0)
        if not force and M.elapsed<0.1 then return end
        M.elapsed=0
        local ok,s=pcall(O.hook.capture,G)
        if not ok then M.clear(); return end
        local sig=D.encode(s)
        if sig==M.signature then return end
        M.signature=sig; M.targets={}
        local success,r=pcall(O.engine.predict,'hook',s)
        if not success then
            if sendWarnMessage then sendWarnMessage('Hook prediction: '..tostring(r),'Oracle') end
            return
        end
        M.count=M.count+1
        for _,id in ipairs(r.targets) do M.targets[id]=true end
    end
    function M.is_target(c)
        return O.controller.supported() and O.hook.active(G) and c.area==G.hand and
            not c.highlighted and M.targets[c.playing_card] or false
    end
    function M.install()
        if Game and Game.update then
            local native=Game.update
            Game.update=function(self,dt,...)
                local ret=pack(native(self,dt,...)); M.update(dt); return unpack(ret,1,ret.n)
            end
        end
        if CardArea and CardArea.parse_highlighted then
            local native=CardArea.parse_highlighted
            CardArea.parse_highlighted=function(self,...)
                local ret=pack(native(self,...))
                if self==G.hand then M.update(0,true) end
                return unpack(ret,1,ret.n)
            end
        end
        local play=G.FUNCS.play_cards_from_highlighted
        if play then G.FUNCS.play_cards_from_highlighted=function(...)
            M.pending=nil
            if O.config.validate_predictions and O.controller.supported() and O.hook.active(G) then
                local ok,s,r,details=pcall(function()
                    local snapshot=O.hook.capture(G)
                    local result,trace=O.engine.predict('hook',snapshot)
                    return snapshot,result,trace
                end)
                if ok then M.pending={before=s,result=r,details=details} end
            end
            M.clear()
            return play(...)
        end end
        local discard=G.FUNCS.discard_cards_from_highlighted
        if discard then G.FUNCS.discard_cards_from_highlighted=function(e,hook,...)
            if hook and M.pending then
                local pending=M.pending; M.pending=nil
                local ok,err=pcall(function()
                    local actual={}; for _,c in ipairs(G.hand.highlighted) do actual[#actual+1]=c.playing_card end
                    -- Compare physical membership, independent of visual sorting.
                    local expected=D.copy(pending.result.targets); table.sort(expected); table.sort(actual)
                    O.validator.record('Hook discard',pending.before,
                        {cards=expected,hook=pending.details.rng_after.hook},
                        {cards=actual,hook=G.GAME.pseudorandom.hook},pending.details)
                end)
                if not ok then
                    O.prediction_fault=true
                    if sendWarnMessage then sendWarnMessage('Hook validation: '..tostring(err),'Oracle') end
                end
            end
            return discard(e,hook,...)
        end end
    end
    return M
end
