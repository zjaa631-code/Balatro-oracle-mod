return function(O)
    local D,M=O.data,{pending=setmetatable({},{__mode='k'}),active=nil,records={}}
    local function log(status,kind,before,expected,actual,details)
        local entry={status=status,kind=kind,input=before,expected=expected,actual=actual,details=details}
        M.records[#M.records+1]=entry; if #M.records>16 then table.remove(M.records,1) end
        if sendInfoMessage then sendInfoMessage('TAG VALIDATION '..status..' '..kind,'Oracle') end
        if status~='MATCH' and love and love.filesystem then
            local fs=love.filesystem; local file='oracle-tag-validation.log'; local info=fs.getInfo(file)
            if info and info.size>1024*1024 then fs.write(file,'') end
            fs.append(file,D.encode(entry)..'\n')
        end
    end
    local function guard(fn)
        local ok,err=pcall(fn)
        if not ok and sendWarnMessage then sendWarnMessage('TAG validation SKIP: '..tostring(err),'Oracle') end
    end
    function M.baseline(s)
        local sh=s.shop
        return {ante=s.game.round_resets.ante,seed=s.game.pseudorandom.seed,
            used=s.game.used_jokers,owned=sh.owned,showman=s.showman,centers=sh.centers,
            pools=sh.rarity_pools,hands=sh.hands,enhancements=sh.enhancements,
            flags=s.game.pool_flags,banned=s.game.banned_keys,modifiers=s.game.modifiers,
            vouchers=s.game.used_vouchers,limit=sh.limit,joker_rate=sh.joker_rate,tarot_rate=sh.tarot_rate,
            planet_rate=sh.planet_rate,playing_card_rate=sh.playing_card_rate,spectral_rate=sh.spectral_rate,
            edition_rate=sh.edition_rate,rarities=sh.rarities,common_mod=sh.common_mod,uncommon_mod=sh.uncommon_mod,rare_mod=sh.rare_mod}
    end
    function M.finish(tag,card)
        local pending=M.pending[tag]; if not pending then return end
        M.pending[tag]=nil
        local actual=card and (pending.result.type=='voucher' and {key=card.config.center.key,set='Voucher'} or O.shop_snapshot.card(card)) or {nope=true}
        local expected=pending.result.card or (pending.result.nope and {nope=true} or {pending=true})
        local same=D.encode(actual)==D.encode(expected)
        local status=(pending.changed or pending.result.pending) and 'CONDITION_CHANGED' or same and 'MATCH' or 'MISMATCH'
        log(status,tag.key..' pre-skip',pending.snapshot,expected,actual,{prediction=pending.result,shop_input=pending.shop_input,rng_after=D.copy(G.GAME.pseudorandom)})
        if status=='MISMATCH' then O.prediction_fault=true end
        if pending.on_result then pending.on_result(status,actual) end
    end
    function M.finish_reward(tag,actual)
        local p=M.pending[tag]; if not p or not p.result.cards then return end
        M.pending[tag]=nil
        local expected=O.tag_rewards.plain(p.result.cards)
        local status=p.changed and 'CONDITION_CHANGED' or D.encode(expected)==D.encode(actual) and 'MATCH' or 'MISMATCH'
        log(status,tag.key..' pre-skip reward',p.snapshot,expected,actual,{prediction=p.result,rng_after=D.copy(G.GAME.pseudorandom)})
        if status=='MISMATCH' then O.prediction_fault=true end
        if p.chain then p.chain.order[#p.chain.order+1]=p.instance_id end
        if p.on_result then p.on_result(status,actual) end
    end
    function M.install()
        if not Tag or not Tag.apply_to_run then return end
        local skip=G.FUNCS.skip_blind
        if skip then G.FUNCS.skip_blind=function(e,...)
            if O.config.validate_predictions and O.controller.supported() then guard(function()
                local container=e.UIBox:get_UIE_by_ID('tag_container')
                local tag=container and container.config.ref_table
                if tag and O.tag_prediction.supported(tag.key) then
                    local r,s=O.tag_prediction.get(tag.key,tag.ability.blind_type,tag.ability,tag.config)
                    if r and s and r.status~='unavailable' then
                        if r.type=='orbital' then r=O.tag_prediction.orbital(s) end
                        M.pending[tag]={result=D.copy(r),snapshot=D.copy(s)}
                    end
                end
            end) end
            return skip(e,...)
        end end
        local shop=create_card_for_shop
        create_card_for_shop=function(...)
            if next(M.pending) then guard(function()
                local s=O.shop_snapshot.capture(G,SMODS,true)
                for tag,p in pairs(M.pending) do
                    if (p.result.type=='joker' or p.result.type=='voucher') and not p.shop_input then
                        p.shop_input=D.copy(s)
                        p.changed=p.changed or D.encode(M.baseline(s))~=D.encode(M.baseline(p.snapshot))
                        local actual_queue,expected_queue={},{}
                        for _,t in ipairs(G.GAME.tags or {}) do if not t.triggered then actual_queue[#actual_queue+1]=t.key end end
                        for _,t in ipairs(p.snapshot.tag.queue) do if not t.done and t.key~='tag_orbital' then expected_queue[#expected_queue+1]=t.key end end
                        if D.encode(actual_queue)~=D.encode(expected_queue) then p.changed=true end
                        for _,step in ipairs((p.result.details or {}).trace or {}) do
                            -- Compare only the initial value of each relevant stream.
                            if s.game.pseudorandom[step.key]~=p.snapshot.game.pseudorandom[step.key] then p.changed=true end
                        end
                    end
                end
            end) end
            return shop(...)
        end
        local apply,yep=Tag.apply_to_run,Tag.yep
        Tag.yep=function(self,message,colour,fn,...)
            local tx=M.active
            if tx and tx.tag==self then
                local old=fn
                fn=function(...)
                    local result=old(...)
                    guard(function()
                        if tx.kind=='store_joker_modify' then
                            O.validator.record('TAG '..self.key..' effect',tx.before,tx.expected,O.shop_snapshot.card(tx.card),tx.details)
                        end
                        if tx.kind~='immediate' and M.pending[self] then
                            G.E_MANAGER:add_event(Event({trigger='after',delay=0.5,blocking=false,func=function()
                                if tx.card and tx.card.temp_edition then return false end
                                guard(function() M.finish(self,tx.card) end); return true
                            end}))
                        end
                    end)
                    return result
                end
            end
            return yep(self,message,colour,fn,...)
        end
        Tag.apply_to_run=function(self,context,...)
            local tx
            if not self.triggered and O.config.validate_predictions and O.controller.supported() then guard(function()
                local kind=context.type
                if (kind=='store_joker_create' and O.tag_prediction.rarities[self.key]) or
                    (kind=='store_joker_modify' and O.tag_prediction.editions[self.key] and context.card and
                        not context.card.edition and not context.card.temp_edition and context.card.ability.set=='Joker') or
                    (kind=='immediate' and self.key=='tag_orbital') then
                    local s=O.tag_prediction.capture(self.key,self.ability.blind_type,self.ability,true,self.config)
                    local candidate={tag=self,kind=kind,before=s,card=context.card}
                    if kind=='store_joker_create' then
                        candidate.expected,candidate.details=O.ante_prediction.run(s,function(sh,rng) return O.tag_prediction.create(sh,rng,self.key) end)
                    elseif kind=='store_joker_modify' then
                        candidate.expected=D.copy(O.shop_snapshot.card(context.card)); O.tag_prediction.modify(candidate.expected,self.key)
                    else candidate.expected=O.tag_prediction.orbital(s) end
                    tx=candidate
                end
            end) end
            local previous=M.active; M.active=tx
            local result=apply(self,context,...)
            M.active=previous
            if tx then guard(function()
                if tx.kind=='store_joker_create' then
                    tx.card=result
                    O.validator.record('TAG '..self.key..' effect',tx.before,
                        {card=tx.expected,rng=tx.details.rng_after},
                        {card=result and O.shop_snapshot.card(result),rng=D.copy(G.GAME.pseudorandom)},tx.details)
                    if not result then M.finish(self,nil) end
                elseif tx.kind=='immediate' then
                    local actual=D.copy(tx.expected)
                    actual.hand_key=self.ability.orbital_hand
                    actual.resulting_level=G.GAME.hands[actual.hand_key].level
                    O.validator.record('TAG orbital effect',tx.before,tx.expected,actual,{pool=tx.before.tag.visible_hands})
                    local p=M.pending[self]
                    if p then
                        local status=p.result.current_level~=tx.expected.current_level and 'CONDITION_CHANGED' or
                            D.encode(p.result)==D.encode(actual) and 'MATCH' or 'MISMATCH'
                        log(status,'tag_orbital pre-skip',p.snapshot,p.result,actual)
                        if status=='MISMATCH' then O.prediction_fault=true end
                        if p.on_result then p.on_result(status,actual) end
                        M.pending[self]=nil
                    end
                end
            end) end
            return result
        end
    end
    return M
end
