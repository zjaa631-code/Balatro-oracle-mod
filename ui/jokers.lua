return function(O)
    local M={page=1,ante_offset=0}
    function M.choices()
        local out={}
        for _,area in ipairs({G.jokers or {},{cards=G.playing_cards or {}}}) do
            for _,c in ipairs(area.cards or {}) do if O.jokers.supported(c.config.center.key) then out[#out+1]=c end end
        end
        return out
    end
    function M.definition()
        local U,T=O.ui,O.text
        if not O.controller.supported() then return U.page({U.message('oracle_prediction_unavailable')}) end
        local choices=M.choices()
        if #choices==0 then return U.page({U.message('oracle_joker_empty'),U.message('oracle_joker_nonrandom')}) end
        M.page=math.max(1,math.min(M.page,#choices)); local card=choices[M.page]
        local labels={}; for i,c in ipairs(choices) do labels[i]=i..'. '..O.tag_ui.reward_name(O.shop_snapshot.card(c)) end
        local nodes={create_option_cycle({options=labels,current_option=M.page,opt_callback='oracle_joker_page',w=5,scale=0.4,no_pips=true}),
            U.message('oracle_joker_conditional',G.C.ORANGE),U.row({O.preview_card.area({O.shop_snapshot.card(card,true)},0.48)})}
        if O.events.supported('joker',card.config.center.key) then
            for _,node in ipairs(O.events_ui.nodes('joker',card)) do nodes[#nodes+1]=node end
            return U.page(nodes)
        end
        local ok,s=pcall(O.jokers.capture,G,SMODS,card); local r,err
        local request={}
        if O.jokers.resets[card.config.center.key] then
            request.ante=G.GAME.round_resets.ante+M.ante_offset
            nodes[#nodes+1]=create_option_cycle({options={T.get('oracle_reset_ante')..' '..G.GAME.round_resets.ante,
                T.get('oracle_reset_ante')..' '..(G.GAME.round_resets.ante+1)},current_option=M.ante_offset+1,
                opt_callback='oracle_joker_ante',w=4,scale=0.35,no_pips=true})
        end
        if ok then
            local sig=O.data.encode(s)..O.data.encode(request)
            if M.cache and M.cache.sig==sig then r,err=M.cache.result,M.cache.error else
                local success,result=pcall(O.engine.predict,'joker',s,request)
                if success then r=result else err=tostring(result):match('(oracle_[%w_]+)') or 'oracle_action_unsupported' end
                M.cache={sig=sig,result=r,error=err}
            end
        else err='oracle_action_unsupported' end
        if not r then nodes[#nodes+1]=U.message(err); return U.page(nodes) end
        nodes[#nodes+1]=U.message(r.condition,G.C.UI.TEXT_INACTIVE)
        if r.inactive then nodes[#nodes+1]=U.message(r.inactive) end
        for _,v in ipairs(r.checks) do
            local label=T.get(v.label)..(v.value and (' +'..v.value) or '')
            local prefix=v.label=='oracle_success' and (T.get('oracle_predicted')..' ') or (label..': ')
            nodes[#nodes+1]=U.row({U.text(prefix..T.get(v.success and 'oracle_success' or 'oracle_fail'),0.33,v.success and G.C.GREEN or G.C.RED)})
        end
        if r.mult then nodes[#nodes+1]=U.row({U.text('+'..r.mult..' '..T.get('oracle_joker_mult'),0.4,G.C.RED)}) end
        if r.target then nodes[#nodes+1]=U.row({U.text(T.get('oracle_target')..': '..O.tag_ui.reward_name(r.target),0.3)}) end
        if r.hand then nodes[#nodes+1]=U.row({U.text(localize(r.hand,'poker_hands'),0.4)}) end
        if r.reset then
            nodes[#nodes+1]=U.row({U.text(T.get('oracle_joker_current_target')..': '..O.quick_ui.reset_name(r.current),0.35)})
            nodes[#nodes+1]=U.row({U.text(T.get('oracle_joker_next_target')..': '..O.quick_ui.reset_name(r.reset),0.4)})
        end
        if #r.created>0 then nodes[#nodes+1]=U.row({O.preview_card.area(r.created,0.48)}) end
        nodes[#nodes+1]=U.message('oracle_joker_order_hint',G.C.UI.TEXT_INACTIVE)
        if O.config.advanced_info and r.checks[1] then nodes[#nodes+1]=U.row({U.text('RNG: '..r.checks[1].key,0.23)}) end
        return U.page(nodes)
    end
    function M.install()
        G.FUNCS.oracle_joker_page=function(a) M.page=a.to_key; G.FUNCS.oracle_refresh() end
        G.FUNCS.oracle_joker_ante=function(a) M.ante_offset=a.to_key-1; G.FUNCS.oracle_refresh() end
    end
    return M
end
