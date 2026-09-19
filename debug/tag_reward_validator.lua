return function(O)
    local D,M=O.data,{active=nil,opening=nil}
    local function guard(fn)
        local ok,err=pcall(fn)
        if not ok and sendWarnMessage then sendWarnMessage('TAG reward validation SKIP: '..tostring(err),'Oracle') end
    end
    function M.install()
        if not Tag or not Tag.apply_to_run then return end
        local apply,yep=Tag.apply_to_run,Tag.yep
        Tag.apply_to_run=function(self,context,...)
            local previous=M.active
            M.active=not self.triggered and ((self.key=='tag_top_up' and context.type=='immediate') or
                (O.tag_rewards.packs[self.key] and context.type=='new_blind_choice')) and self or nil
            local ret={n=0}; local function collect(...) ret={n=select('#',...),...} end
            collect(apply(self,context,...)); M.active=previous; return unpack(ret,1,ret.n)
        end
        Tag.yep=function(self,message,colour,fn,...)
            if M.active==self then
                local original=fn
                fn=function(...)
                    local before,expected,details
                    if self.key=='tag_top_up' and O.config.validate_predictions and O.controller.supported() then guard(function()
                        before=O.tag_prediction.capture(self.key,nil,self.ability,true,self.config)
                        expected,details=O.ante_prediction.run(before,function(s,rng) return O.tag_rewards.topup(s,rng,self) end)
                    end) end
                    local count=#G.jokers.cards
                    local prev=M.opening; M.opening=O.tag_rewards.packs[self.key] and self or nil
                    local ret; local function collect(...) ret={n=select('#',...),...} end
                    collect(original(...)); M.opening=prev
                    if expected then guard(function()
                        local actual={}; for i=count+1,#G.jokers.cards do actual[#actual+1]=O.shop_snapshot.card(G.jokers.cards[i]) end
                        O.validator.record('TAG Top-up callback',before,{cards=expected,rng=details.rng_after},
                            {cards=actual,rng=D.copy(G.GAME.pseudorandom)},details)
                        O.tag_validator.finish_reward(self,actual)
                    end) end
                    return unpack(ret,1,ret.n)
                end
            end
            return yep(self,message,colour,fn,...)
        end
        local open=Card and Card.open
        if open then Card.open=function(card,...)
            local tag=M.opening
            local ret; local function collect(...) ret={n=select('#',...),...} end
            collect(open(card,...))
            if tag and O.config.validate_predictions then
                -- Existing pack validator observes the complete candidate list;
                -- attach pre-skip identity without replacing its open-time check.
                local p=O.pack_validator.pending
                if p then p.reward_tag=tag end
            end
            return unpack(ret,1,ret.n)
        end end
    end
    return M
end
