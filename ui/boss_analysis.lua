return function(O)
    local M={view=1,page=1,count=5}
    function M.definition()
        local U,T=O.ui,O.text
        if not O.controller.supported() then return U.page({U.message('oracle_prediction_unavailable')}) end
        local ok,s=pcall(O.bosses.capture,G,SMODS)
        if not ok then return U.page({U.message('oracle_boss_analysis_unsupported')}) end
        local hands={}; for key,h in pairs(s.levels) do if h.visible then hands[#hands+1]=key end end
        table.sort(hands,function(a,b) return (s.levels[a].order or 0)==(s.levels[b].order or 0) and a<b or
            (s.levels[a].order or 0)>(s.levels[b].order or 0) end)
        if #hands==0 then return U.page({U.message('oracle_boss_analysis_unsupported')}) end
        local selected,labels=1,{}
        for i,key in ipairs(hands) do labels[i]=localize(key,'poker_hands'); if M.hand==key then selected=i end end
        M.hands=hands; M.hand=hands[selected]
        local request={hand=M.hand,count=M.count}
        local sig=O.data.encode(s)..O.data.encode(request); local r
        if M.cache and M.cache.sig==sig then r=M.cache.result else
            local success,result=pcall(O.engine.predict,'boss_analysis',s,request)
            if success then r=result end
            M.cache={sig=sig,result=r}
        end
        if not r then return U.page({U.message('oracle_boss_analysis_unsupported')}) end
        local nodes={U.row({U.field('oracle_boss',T.name('Blind',{key=r.key}),7.5,nil,0.45)}),
            U.message(s.mode=='current' and 'oracle_boss_current' or 'oracle_boss_scheduled',G.C.ORANGE),
            create_option_cycle({options={T.get('oracle_boss_rules'),T.get('oracle_boss_cards'),T.get('oracle_boss_hand')},
                current_option=M.view,opt_callback='oracle_analysis_view',w=5,scale=0.4,no_pips=true})}
        if M.view==1 then
            local vars=r.key=='bl_ox' and {localize(s.most_played,'poker_hands')} or r.key=='bl_wheel' and {s.probability,7} or {}
            local desc=localize({type='raw_descriptions',set='Blind',key=r.key,vars=vars})
            if type(desc)=='table' then for _,line in ipairs(desc) do nodes[#nodes+1]=U.row({U.text(line,0.34)}) end end
            if r.disabled then nodes[#nodes+1]=U.message(r.chicot and 'oracle_boss_chicot' or 'oracle_boss_disabled',G.C.GREEN) end
            for _,field in ipairs({'hand_size_delta','discards_delta','hands_delta'}) do
                if r[field] then nodes[#nodes+1]=U.row({U.text(T.get('oracle_boss_'..field)..': '..r[field],0.34)}) end
            end
            for _,note in ipairs(r.notes) do nodes[#nodes+1]=U.message(note,G.C.UI.TEXT_INACTIVE) end
        elseif M.view==2 then
            nodes[#nodes+1]=U.row({U.text(T.get('oracle_boss_affected')..': '..#r.affected..' / '..r.total,0.4,G.C.ORANGE)})
            local pages={}; for i=1,math.max(1,math.ceil(#r.affected/4)) do pages[i]=i..' / '..math.max(1,math.ceil(#r.affected/4)) end
            M.page=math.min(M.page,#pages)
            local cards={}; for i=(M.page-1)*4+1,math.min(M.page*4,#r.affected) do cards[#cards+1]=r.affected[i] end
            if #cards>0 then nodes[#nodes+1]=U.row({O.preview_card.area(cards,0.65)})
            else nodes[#nodes+1]=U.message('oracle_boss_no_debuff') end
            nodes[#nodes+1]=create_option_cycle({options=pages,current_option=M.page,opt_callback='oracle_analysis_page',w=3,scale=0.35,no_pips=true})
            nodes[#nodes+1]=U.message('oracle_boss_card_boundary',G.C.UI.TEXT_INACTIVE)
        else
            nodes[#nodes+1]=U.row({create_option_cycle({options=labels,current_option=selected,opt_callback='oracle_analysis_hand',w=4,scale=0.35,no_pips=true}),
                create_option_cycle({options={'1','2','3','4','5'},current_option=M.count,opt_callback='oracle_analysis_count',w=2,scale=0.35,no_pips=true})})
            nodes[#nodes+1]=U.message('oracle_boss_plan_hint',G.C.UI.TEXT_INACTIVE)
            nodes[#nodes+1]=U.message(r.hand.blocked and 'oracle_boss_blocked' or 'oracle_boss_allowed',r.hand.blocked and G.C.RED or G.C.GREEN)
            nodes[#nodes+1]=U.row({U.text('Lv. '..r.hand.level_before..' → '..r.hand.level_after,0.4)})
            if r.hand.money~=0 then nodes[#nodes+1]=U.row({U.text(T.get('oracle_boss_money')..': $'..r.hand.money,0.35,G.C.MONEY)}) end
            if r.hand.modified then nodes[#nodes+1]=U.row({U.text(T.get('oracle_boss_base')..': '..r.hand.chips..' × '..r.hand.mult,0.36)}) end
            nodes[#nodes+1]=U.message('oracle_boss_score_boundary',G.C.UI.TEXT_INACTIVE)
        end
        return U.page(nodes)
    end
    function M.install()
        for _,field in ipairs({'view','page','count','hand'}) do local f=field
            G.FUNCS['oracle_analysis_'..f]=function(a)
                M[f]=f=='hand' and M.hands[a.to_key] or a.to_key
                if f=='view' then M.page=1 end
                G.FUNCS.oracle_refresh()
            end
        end
    end
    return M
end
