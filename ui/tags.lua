-- Extend native Tag text; never instantiate a gameplay Tag or Card to preview.
return function(O)
    local M={page=1,blind=1}
    function M.reward_name(card)
        local T=O.text
        local name=T.name(card.set,card)
        if card.front and G.P_CARDS[card.front] then
            local f=G.P_CARDS[card.front]
            name=localize(f.value,'ranks')..({Spades='♠',Hearts='♥',Diamonds='♦',Clubs='♣'})[f.suit]
            if card.key~='c_base' then name=name..' · '..T.name('Enhanced',card) end
        end
        if card.edition then name=name..' · '..T.get('oracle_'..card.edition) end
        if card.seal then name=name..' · '..localize(card.seal:lower()..'_seal','labels') end
        for _,k in ipairs({'eternal','perishable','rental'}) do if card[k] then name=name..' · '..T.get('oracle_'..k) end end
        if card.legendary then name=name..' → '..T.name('Joker',{key=card.legendary}) end
        return name
    end
    function M.visible_effects(r)
        local out={}
        for _,e in ipairs(r.effects or {}) do
            if O.config.show_voucher~=false or e.type~='voucher' then out[#out+1]=e end
        end
        return out
    end
    function M.effect_lines(e)
        local T=O.text
        local lines={T.name('Tag',{key=e.tag})}
        if e.type=='orbital' then
            lines[#lines+1]=localize(e.hand_key,'poker_hands')..' · Lv. '..e.current_level..' → '..e.resulting_level
        elseif e.cards then
            if e.pack then lines[#lines+1]=T.name('Booster',e.pack) end
            for i,card in ipairs(e.cards) do lines[#lines+1]=i..'. '..M.reward_name(card) end
            if #e.cards==0 then lines[#lines+1]=T.get('oracle_tag_no_room') end
            if e.pack and e.pack.variant_unknown then lines[#lines+1]=T.get('oracle_tag_pack_cover') end
            for _,card in ipairs(e.cards) do if card.legendary then lines[#lines+1]=T.get('oracle_soul_branch'); break end end
        elseif e.card then
            lines[#lines+1]=T.name(e.card.set,e.card)
            local attrs={}
            if e.card.edition then attrs[#attrs+1]=T.get('oracle_'..e.card.edition) end
            for _,k in ipairs({'eternal','perishable','rental'}) do if e.card[k] then attrs[#attrs+1]=T.get('oracle_'..k) end end
            if #attrs>0 then lines[#lines+1]=table.concat(attrs,' · ') end
        else lines[#lines+1]=T.get(e.reason or (e.nope and 'oracle_tag_nope' or 'oracle_tag_pending')) end
        if (e.reroll or 0)>0 then lines[#lines+1]=T.get('oracle_chain_reroll')..' +'..e.reroll end
        return lines
    end
    function M.lines(r,compact)
        if not r then return {} end
        local T=O.text
        if r.status=='unavailable' then return {T.get('oracle_tag_unavailable'),T.get(r.reason)} end
        if r.type=='chain' then
            local effects=M.visible_effects(r)
            local lines={T.get('oracle_stored_doubles')..': '..r.stored_double_count,
                T.name('Tag',{key=r.skip_tag})..' ×'..#r.expanded_tags}
            if r.skip_tag=='tag_double' then lines[#lines+1]=T.get('oracle_double_pending') end
            if O.config.show_voucher~=false and #r.normal_vouchers>0 then
                local names={}; for _,v in ipairs(r.normal_vouchers) do names[#names+1]=T.name('Voucher',v) end
                lines[#lines+1]=T.get('oracle_normal_voucher')..': '..table.concat(names,' / ')
            end
            for i=1,math.min(#effects,compact and 2 or 3) do
                for j,line in ipairs(M.effect_lines(effects[i])) do lines[#lines+1]=(j==1 and ('#'..i..' ') or '')..line end
            end
            if #effects>(compact and 2 or 3) then lines[#lines+1]=T.get('oracle_chain_more') end
            if r.status=='experimental' then lines[#lines+1]=T.get('oracle_tag_experimental') end
            if not compact and #r.deferred_effects>0 then
                lines[#lines+1]=T.get('oracle_tag_condition_1'); lines[#lines+1]=T.get('oracle_tag_condition_2')
                if #r.rerolls>0 then lines[#lines+1]=T.get('oracle_chain_no_purchase') end
            end
            return lines
        end
        if r.type=='orbital' then
            return {localize(r.hand_key,'poker_hands'),
                'Lv. '..r.current_level..' → Lv. '..r.resulting_level..' (+'..r.levels_added..')'}
        end
        local lines={}
        if r.card then
            lines[#lines+1]='→ '..T.name('Joker',r.card)
            local attrs={}
            if r.card.edition then attrs[#attrs+1]=T.get('oracle_'..r.card.edition) end
            for _,k in ipairs({'eternal','perishable','rental'}) do if r.card[k] then attrs[#attrs+1]=T.get('oracle_'..k) end end
            if #attrs>0 then lines[#lines+1]=table.concat(attrs,' · ') end
        else lines[#lines+1]=T.get(r.nope and 'oracle_tag_nope' or 'oracle_tag_pending') end
        lines[#lines+1]=T.get('oracle_tag_experimental')
        if not compact then
            lines[#lines+1]=T.get('oracle_ante')..' '..tostring(r.shop_ante)..' · '..T.get('oracle_tag_first_shop')
            lines[#lines+1]=T.get('oracle_tag_condition_1')
            lines[#lines+1]=T.get('oracle_tag_condition_2')
        end
        return lines
    end
    function M.summary(key,blind,ante)
        if not O.tag_prediction.supported(key) then return O.ui.row({}) end
        local r=ante==G.GAME.round_resets.ante and O.tag_prediction.get(key,blind) or
            {status='unavailable',reason='oracle_tag_future'}
        local nodes={}
        for _,line in ipairs(M.lines(r,true)) do nodes[#nodes+1]=O.ui.row({O.ui.text(line,0.25)},0.01) end
        if r.card then nodes[#nodes+1]=O.ui.row({O.preview_card.area({r.card},0.5)},0.02) end
        return {n=G.UIT.C,config={align='cm',minw=3.8,padding=0.03},nodes=nodes}
    end
    function M.definition()
        local U,T=O.ui,O.text
        local blind=({'Small','Big'})[M.blind]
        local key=((G.GAME.round_resets or {}).blind_tags or {})[blind]
        local r=O.tag_prediction.get(key,blind)
        local selector=create_option_cycle({options={T.get('oracle_small_tag'),T.get('oracle_big_tag')},current_option=M.blind,
            opt_callback='oracle_chain_blind',w=4,scale=0.5,no_pips=true})
        if not r or r.status=='unavailable' then
            return U.page({selector,U.message(r and r.reason or 'oracle_tag_unsupported')})
        end
        local effects=M.visible_effects(r)
        local per_page=r.choice_boundary and 1 or 2
        local pages=math.max(1,math.ceil(#effects/per_page)); M.page=math.min(M.page,pages)
        local nodes={U.message(r.status=='experimental' and 'oracle_tag_experimental' or 'oracle_observed',G.C.ORANGE),
            selector,
            U.row({U.text(T.get('oracle_stored_doubles')..': '..r.stored_double_count..' · '..T.name('Tag',{key=key})..' ×'..#r.expanded_tags,0.3)})}
        if key=='tag_double' then nodes[#nodes+1]=U.message('oracle_double_pending') end
        if O.config.show_voucher~=false and #r.normal_vouchers>0 then
            local names={}; for _,v in ipairs(r.normal_vouchers) do names[#names+1]=T.name('Voucher',v) end
            nodes[#nodes+1]=U.row({U.field('oracle_normal_voucher',table.concat(names,' / '),7.6,nil,0.28)})
        end
        for i=(M.page-1)*per_page+1,math.min(M.page*per_page,#effects) do
            local e=effects[i]; local texts={}
            for _,line in ipairs(M.effect_lines(e)) do texts[#texts+1]=U.row({U.text(line,0.29)},0.01) end
            texts[#texts+1]=U.message((e.stage=='immediate' or e.stage=='new_blind_choice') and 'oracle_chain_immediate' or 'oracle_chain_deferred',G.C.ORANGE)
            local row={{n=G.UIT.C,config={align='cm',minw=4},nodes=texts}}
            if e.card then row[#row+1]=O.preview_card.area({e.card},0.5) end
            nodes[#nodes+1]=U.row(row)
            if e.cards and #e.cards>0 then nodes[#nodes+1]=U.row({O.preview_card.area(e.cards,0.43)}) end
        end
        local labels={}; for i=1,pages do labels[i]=i..' / '..pages end
        nodes[#nodes+1]=create_option_cycle({options=labels,current_option=M.page,opt_callback='oracle_chain_page',w=3,scale=0.45,no_pips=true})
        if #r.deferred_effects>0 then nodes[#nodes+1]=U.message('oracle_chain_no_purchase',G.C.UI.TEXT_INACTIVE) end
        return U.page(nodes)
    end
    function M.install()
        G.FUNCS.oracle_chain_blind=function(args) M.blind=args.to_key; M.page=1; G.FUNCS.oracle_refresh() end
        G.FUNCS.oracle_chain_page=function(args) M.page=args.to_key; G.FUNCS.oracle_refresh() end
        if not Tag or not Tag.get_uibox_table then return end
        local original=Tag.get_uibox_table
        Tag.get_uibox_table=function(self,sprite,vars_only)
            local result=original(self,sprite,vars_only)
            if vars_only or self.hide_ability or not O.config.enabled or not G.STAGES or G.STAGE~=G.STAGES.RUN then return result end
            -- Only actual held Doubles get a stored-state tooltip; collections
            -- must never be interpreted as newly acquired tags.
            local blind=(self.ability or {}).blind_type
            local held_double=false
            local held_reward=false
            if O.tag_rewards.packs[self.key] and not self.triggered then
                for _,tag in ipairs(G.GAME.tags or {}) do if tag==self then held_reward=true; blind='Held'; break end end
            end
            if self.key=='tag_double' and not self.triggered then
                for _,tag in ipairs(G.GAME.tags or {}) do if tag==self then held_double=true; break end end
            end
            if (not blind and not held_double and not held_reward) or not O.tag_prediction.supported(self.key) then return result end
            local target=sprite or self.tag_sprite
            local ui=target and target.ability_UIBox_table
            if not ui or not ui.main then return result end
            local ok,err=pcall(function()
                local r
                if not held_double then r=O.tag_prediction.get(self.key,blind,self.ability,self.config) end
                local function line(text,colour)
                    ui.main[#ui.main+1]={{n=G.UIT.T,config={text=text,scale=0.27,colour=colour or G.C.UI.TEXT_DARK}}}
                end
                line('— '..O.text.get('oracle_title')..' —',G.C.ORANGE)
                if held_double then
                    local count=0
                    for _,tag in ipairs(G.GAME.tags) do if tag.key=='tag_double' and not tag.triggered then count=count+1 end end
                    line(O.text.get('oracle_stored_doubles')..': '..count)
                    line(O.text.get('oracle_double_pending'))
                    return
                end
                line(O.text.get('oracle_predicted'))
                for _,text in ipairs(M.lines(r)) do line(text) end
                if O.config.advanced_info then line(self.key) end
            end)
            if not ok and sendWarnMessage then sendWarnMessage('TAG tooltip: '..tostring(err),'Oracle') end
            return result
        end
    end
    return M
end
