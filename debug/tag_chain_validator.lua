-- Observe real acquisition callbacks and bind each NEW instance to its own
-- pre-skip result. No generated cards/tags are replaced or replayed.
return function(O)
    local D,M=O.data,{chains={},active=nil,copying=nil,acquiring=nil}
    local function safe(fn)
        local ok,err=pcall(fn)
        if not ok and sendWarnMessage then sendWarnMessage('TAG CHAIN validation SKIP: '..tostring(err),'Oracle') end
    end
    local function value(e)
        if e.cards then return O.tag_rewards.plain(e.cards) end
        if e.type=='orbital' then return {type='orbital',tag=e.tag,status='observed',hand_key=e.hand_key,
            current_level=e.current_level,resulting_level=e.resulting_level,levels_added=e.levels_added} end
        return e.card or (e.nope and {nope=true} or {pending=true})
    end
    function M.bind(chain,tag,id)
        local expected
        for _,e in ipairs(chain.prediction.effects) do if e.id==id then expected=e; break end end
        if not expected or expected.pending then return end
        local result={type=expected.type,card=expected.card,cards=expected.cards,nope=expected.nope,details=chain.prediction.details}
        if expected.type=='orbital' then result=value(expected) end
        chain.expected[id]=value(expected)
        O.tag_validator.pending[tag]={result=D.copy(result),snapshot=D.copy(chain.snapshot),chain=chain,instance_id=id,on_result=function(status,actual)
            chain.actual[id]=actual
            if status=='CONDITION_CHANGED' then chain.changed=true end
            local complete=true
            for key in pairs(chain.expected) do if not chain.actual[key] then complete=false end end
            if complete and chain.acquired then
                local expected_order={}
                for _,e in ipairs(chain.prediction.effects) do if chain.expected[e.id] then expected_order[#expected_order+1]=e.id end end
                local expected={effects=chain.expected,order=expected_order}
                local observed={effects=chain.actual,order=chain.order}
                if #chain.prediction.additional_vouchers>0 then
                    expected.vouchers={}; observed.vouchers={}
                    for _,v in ipairs(chain.prediction.normal_vouchers) do expected.vouchers[#expected.vouchers+1]=v.key end
                    for _,v in ipairs(chain.prediction.additional_vouchers) do expected.vouchers[#expected.vouchers+1]=v.key end
                    for _,c in ipairs(G.shop_vouchers.cards) do observed.vouchers[#observed.vouchers+1]=c.config.center.key end
                end
                if chain.changed then
                    if sendInfoMessage then sendInfoMessage('TAG CHAIN CONDITION_CHANGED '..chain.prediction.skip_tag,'Oracle') end
                    if love and love.filesystem then
                        local fs=love.filesystem; local file='oracle-tag-chain.log'; local info=fs.getInfo(file)
                        if info and info.size>1024*1024 then fs.write(file,'') end
                        fs.append(file,D.encode({status='CONDITION_CHANGED',input=chain.snapshot,expected=expected,actual=observed,
                            expansion=chain.instances,simulation=chain.prediction})..'\n')
                    end
                else
                    O.validator.record('TAG CHAIN results '..chain.prediction.skip_tag,chain.snapshot,
                        expected,observed,{expansion=chain.instances,simulation=chain.prediction})
                end
                chain.complete=true
            end
        end}
    end
    local function instance(tag)
        return {key=tag.key,config=D.copy(tag.config or {}),ability=D.copy(tag.ability or {})}
    end
    function M.register(chain,tag)
        local i=#chain.instances+1; local e=chain.prediction.expanded_tags[i]
        chain.instances[i]=instance(tag)
        if e then M.bind(chain,tag,e.id) end
        if i==#chain.prediction.expanded_tags then
            local expected={}
            for _,v in ipairs(chain.prediction.expanded_tags) do expected[#expected+1]=instance(v) end
            O.validator.record('TAG CHAIN expansion '..chain.prediction.skip_tag,chain.snapshot,expected,chain.instances,
                {stored=chain.snapshot.tag.pending,consumed=chain.prediction.consumed_doubles,
                    rng_before=chain.snapshot.game.pseudorandom,rng_after=D.copy(G.GAME.pseudorandom)})
            chain.acquired=true
            if not next(chain.expected) then chain.complete=true end
        end
    end
    function M.install()
        if not Tag or not Tag.apply_to_run or not add_tag then return end
        local skip=G.FUNCS.skip_blind
        if skip then G.FUNCS.skip_blind=function(e,...)
            local chain
            if O.config.validate_predictions and O.controller.supported() then safe(function()
                local node=e.UIBox:get_UIE_by_ID('tag_container'); local tag=node and node.config.ref_table
                if not tag then return end
                local r,s=O.tag_prediction.get(tag.key,tag.ability.blind_type,tag.ability,tag.config)
                if not r or not s or r.status=='unavailable' then return end
                chain={root=tag,prediction=D.copy(r),snapshot=D.copy(s),instances={},expected={},actual={},order={}}
                M.chains[#M.chains+1]=chain; if #M.chains>16 then table.remove(M.chains,1) end
                local i=0
                for _,stored in ipairs(G.GAME.tags) do
                    if not stored.triggered then i=i+1; M.bind(chain,stored,'stored:'..i) end
                end
            end) end
            M.acquiring=chain
            local result=skip(e,...)
            M.acquiring=nil
            return result
        end end
        local add=add_tag
        add_tag=function(tag,...)
            local chain=M.copying or (M.acquiring and M.acquiring.root==tag and M.acquiring)
            local result=add(tag,...)
            if chain then safe(function() M.register(chain,tag) end) end
            return result
        end
        local apply=Tag.apply_to_run
        Tag.apply_to_run=function(self,context,...)
            local previous=M.active; M.active={tag=self,context=context}
            local p=O.tag_validator.pending[self]
            if p and p.chain and not self.triggered then
                local match=(context.type=='store_joker_create' and O.tag_prediction.rarities[self.key]) or
                    (context.type=='immediate' and self.key=='tag_orbital') or
                    (context.type=='store_joker_modify' and O.tag_prediction.editions[self.key] and context.card and
                        context.card.ability.set=='Joker' and not context.card.edition and not context.card.temp_edition)
                if match then p.chain.order[#p.chain.order+1]=p.instance_id end
            end
            local result=apply(self,context,...)
            M.active=previous
            return result
        end
        local yep=Tag.yep
        Tag.yep=function(self,message,colour,fn,...)
            local active=M.active
            if active and active.tag==self and active.context.type=='tag_add' and self.key=='tag_double' then
                local root=active.context.tag
                local chain=M.copying or (M.acquiring and M.acquiring.root==root and M.acquiring)
                if chain then
                    local old=fn
                    fn=function(...)
                        local previous=M.copying; M.copying=chain
                        local r=old(...); M.copying=previous; return r
                    end
                end
            elseif active and active.tag==self and active.context.type=='voucher_add' and self.key=='tag_voucher' then
                local old=fn
                fn=function(...)
                    local before,expected,details
                    if O.config.validate_predictions and O.controller.supported() then safe(function()
                        before=O.tag_prediction.capture(self.key,nil,self.ability,true,self.config)
                        expected,details=O.ante_prediction.run(before,O.tag_pipeline.voucher)
                    end) end
                    local count=#G.shop_vouchers.cards
                    local result=old(...)
                    safe(function()
                        local card=G.shop_vouchers.cards[count+1]
                        local pending=O.tag_validator.pending[self]
                        if card and pending and pending.chain then pending.chain.order[#pending.chain.order+1]=pending.instance_id end
                        if before and expected and card then
                            O.validator.record('TAG Voucher callback',before,{card=expected,rng=details.rng_after},
                                {card={key=card.config.center.key,set='Voucher'},rng=D.copy(G.GAME.pseudorandom)},details)
                        end
                        if card then O.tag_validator.finish(self,card) end
                    end)
                    return result
                end
            end
            return yep(self,message,colour,fn,...)
        end
        for _,key in ipairs({'buy_from_shop','sell_card','use_card','play_cards_from_highlighted','discard_cards_from_highlighted'}) do
            if G.FUNCS[key] then
                local old=G.FUNCS[key]
                G.FUNCS[key]=function(...)
                    local e=select(1,...)
                    if key=='use_card' and e and e.config and e.config.ref_table and e.config.ref_table.from_tag then return old(...) end
                    for _,chain in ipairs(M.chains) do
                        if not chain.complete then
                            chain.changed=true
                            for _,p in pairs(O.tag_validator.pending) do if p.on_result then p.changed=true end end
                        end
                    end
                    return old(...)
                end
            end
        end
    end
    return M
end
