return function(O)
    local M={page=1,detail=1,view=1}
    function M.changed_preview(change,key)
        local card=O.data.copy(change.after)
        -- Rebuild rank/suit tooltip metadata from the new native front.
        if card.front~=change.before.front then card.base=nil end
        if card.key~=change.before.key and key~='c_death' then
            -- A new enhancement uses its own native config. Do not overlay old
            -- Steel/Bonus/etc values onto it; permanent card bonuses survive.
            local permanent={}
            for field,value in pairs(card.ability or {}) do
                if field:match('^perma_') then permanent[field]=value end
            end
            card.ability=permanent
        end
        return card
    end
    function M.choices()
        local out={}
        for _,area in ipairs({G.consumeables or {},G.pack_cards or {}}) do
            for _,c in ipairs(area.cards or {}) do if c.ability.consumeable then out[#out+1]=c end end
        end
        return out
    end
    function M.definition()
        local U,T=O.ui,O.text
        if not O.controller.supported() then return U.page({U.message('oracle_prediction_unavailable')}) end
        local choices=M.choices()
        if #choices==0 then return U.page({U.message('oracle_consume_empty')}) end
        M.page=math.max(1,math.min(M.page,#choices)); local card=choices[M.page]
        local labels={}; for _,c in ipairs(choices) do labels[#labels+1]=T.name(c.ability.set,{key=c.config.center.key}) end
        local nodes={create_option_cycle({options=labels,current_option=M.page,opt_callback='oracle_consume_page',w=M.view==2 and 4 or 4.7,scale=0.5,no_pips=true})}
        if M.view~=2 and O.events.supported('consumable',card.config.center.key) then
            nodes[#nodes+1]=create_option_cycle({options={T.get('oracle_consume_effects'),T.get('oracle_branch_deck')},current_option=1,
                opt_callback='oracle_consume_view',w=4.7,scale=0.4,no_pips=true})
            nodes[#nodes+1]=U.row({O.preview_card.area({O.shop_snapshot.card(card,true)},0.4)})
            for _,node in ipairs(O.events_ui.nodes('consumable',card)) do nodes[#nodes+1]=node end
            return U.page(nodes)
        end
        local ok,s=pcall(O.consumables.capture,G,SMODS,card)
        local r,err,branch,branch_error
        if ok then
            local sig=O.data.encode(s)
            if M.cache and M.cache.sig==sig then r,err=M.cache.result,M.cache.error; branch,branch_error=M.cache.branch,M.cache.branch_error
            else
                local success,result,details=pcall(O.engine.predict,'consumable',s)
                if success then r=result else err=tostring(result):match('(oracle_[%w_]+)') or 'oracle_action_unsupported' end
                if r and O.deck_state then
                    local made,world=pcall(O.deck_state.materialize,s,r)
                    if made then world.rng=O.data.copy(details.rng_after); branch={before=s.deck_state,after=world}
                    else branch_error=tostring(world):match('(oracle_[%w_]+)') or 'oracle_deck_branch_unavailable' end
                end
                M.cache={sig=sig,result=r,error=err,branch=branch,branch_error=branch_error}
            end
        else err='oracle_action_unsupported' end
        if not r then nodes[#nodes+1]=U.message(err,G.C.ORANGE); return U.page(nodes) end
        if O.deck_after_ui then
            local mode=create_option_cycle({options={T.get('oracle_consume_effects'),T.get('oracle_branch_deck')},current_option=M.view,
                opt_callback='oracle_consume_view',w=M.view==2 and 3.5 or 4.7,scale=0.4,no_pips=true})
            if M.view==2 then nodes[1]=U.row({nodes[1],mode}) else nodes[#nodes+1]=mode end
            if M.view==2 then
                nodes[#nodes+1]=U.message('oracle_branch_experimental',G.C.ORANGE)
                if not O.config.show_draw_order then nodes[#nodes+1]=U.message('oracle_draw_disabled')
                elseif branch then for _,node in ipairs(O.deck_after_ui.nodes(branch)) do nodes[#nodes+1]=node end
                else nodes[#nodes+1]=U.message(branch_error or 'oracle_deck_branch_unavailable') end
                return U.page(nodes)
            end
        end
        nodes[#nodes+1]=U.row({O.preview_card.area({O.shop_snapshot.card(card,true)},0.5)})
        nodes[#nodes+1]=U.message('oracle_consume_direct',G.C.ORANGE)
        local groups={}
        if r.success~=nil then nodes[#nodes+1]=U.message(r.success and 'oracle_success' or 'oracle_fail',r.success and G.C.GREEN or G.C.RED) end
        if #r.created>0 then groups[#groups+1]={label='oracle_created',cards=r.created} end
        if r.target then groups[#groups+1]={label='oracle_target',cards={r.target}} end
        if #r.destroyed>0 then groups[#groups+1]={label='oracle_destroyed',cards=r.destroyed} end
        local changed={}; for _,c in ipairs(r.changes) do changed[#changed+1]=M.changed_preview(c,r.key) end
        -- Card changes use native sprites and edition/seal rendering.
        for first=1,#changed,4 do local cards={}; for i=first,math.min(first+3,#changed) do cards[#cards+1]=changed[i] end; groups[#groups+1]={label='oracle_after_use',cards=cards} end
        for first=1,#r.levels,4 do local levels={}; for i=first,math.min(first+3,#r.levels) do levels[#levels+1]=r.levels[i] end; groups[#groups+1]={levels=levels} end
        M.detail=math.max(1,math.min(M.detail,math.max(1,#groups)))
        local group=groups[M.detail]
        if group and group.cards then
            nodes[#nodes+1]=U.message(group.label)
            nodes[#nodes+1]=U.row({O.preview_card.area(group.cards,math.min(0.7,4.7/#group.cards))})
        elseif group then
            for _,level in ipairs(group.levels) do nodes[#nodes+1]=U.row({U.text(localize(level.hand,'poker_hands')..'   Lv. '..level.before..' → '..level.after,0.32)}) end
        end
        if r.money~=0 then nodes[#nodes+1]=U.row({U.text(T.get('oracle_money_change')..' '..(r.money>0 and '+' or '')..'$'..r.money,0.32,G.C.MONEY)}) end
        if r.hand_size~=0 then nodes[#nodes+1]=U.row({U.text(T.get('oracle_hand_size_change')..' '..r.hand_size,0.3)}) end
        if #groups>1 then
            local pages={}; for i=1,#groups do pages[i]=i..' / '..#groups end
            nodes[#nodes+1]=create_option_cycle({options=pages,current_option=M.detail,opt_callback='oracle_consume_detail',w=3,scale=0.4,no_pips=true})
        end
        nodes[#nodes+1]=U.message('oracle_consume_selection_hint',G.C.UI.TEXT_INACTIVE)
        return U.page(nodes)
    end
    function M.install()
        G.FUNCS.oracle_consume_view=function(a) M.view=a.to_key; G.FUNCS.oracle_refresh() end
        G.FUNCS.oracle_consume_page=function(a) M.page=a.to_key; M.detail=1; G.FUNCS.oracle_refresh() end
        G.FUNCS.oracle_consume_detail=function(a) M.detail=a.to_key; G.FUNCS.oracle_refresh() end
    end
    return M
end
