return function(O)
    local M={page=1}
    function M.definition()
        local U,T=O.ui,O.text
        if O.config.show_packs==false then return U.page({U.message('oracle_feature_hidden')}) end
        if not O.controller.supported() then return U.page({U.message('oracle_prediction_unavailable')}) end
        local ok,s=pcall(O.pack_prediction.capture,G,SMODS)
        if not ok then return U.page({U.message('oracle_pack_unsupported',G.C.ORANGE)}) end
        local choices=s.shop.packs
        local observed=s.shop.opened_pack and #s.shop.opened_cards>0
        if not observed and s.shop.pack_reason then
            return U.page({U.message(s.shop.pack_reason,G.C.ORANGE)})
        end
        if observed then choices={{key=s.shop.opened_pack}} end
        if not observed and (not s.shop.active or #choices==0) then return U.page({U.message('oracle_pack_wait')}) end
        M.page=math.max(1,math.min(M.page,#choices))
        local pack=choices[M.page]
        local cards
        if observed then
            cards=s.shop.opened_cards
            for _,c in ipairs(cards) do
                if c.key=='c_soul' and not s.shop.pack_unsupported and not s.shop.unsupported then
                    local success,key=pcall(O.pack_prediction.legendary,s)
                    if success then c.legendary=key end
                end
            end
        else
            local sig=O.data.encode(s)..':'..pack.key
            if M.cache and M.cache.signature==sig then cards=M.cache.cards
            else
                local success,result=pcall(O.pack_prediction.forecast,s,pack)
                if not success then
                    if O.diagnostics then O.diagnostics.note('packs page',result) end
                    return U.page({U.message('oracle_pack_unsupported',G.C.ORANGE),U.message('oracle_export_hint')})
                end
                cards=result; M.cache={signature=sig,cards=cards}
            end
        end
        local options={}; for i,p in ipairs(choices) do options[i]=T.name('Booster',p) end
        local nodes={U.message(observed and 'oracle_observed' or 'oracle_experimental',G.C.ORANGE),
            U.row({O.preview_card.area({{key=pack.key,set='Booster'}},0.5)}),
            U.row({O.preview_card.area(cards,math.min(0.8,5.2/math.max(1,#cards)),{ante=s.game.round_resets.ante,pack=pack.key})}),
            U.message('oracle_pack_branch',G.C.UI.TEXT_INACTIVE)}
        for _,c in ipairs(cards) do
            if c.legendary then nodes[#nodes+1]=U.row({U.text(T.name('Spectral',{key='c_soul'})..' → '..T.name('Joker',{key=c.legendary}),0.35,G.C.ORANGE)}) end
        end
        nodes[#nodes+1]=U.message('oracle_soul_branch',G.C.UI.TEXT_INACTIVE)
        nodes[#nodes+1]=create_option_cycle({options=options,current_option=M.page,opt_callback='oracle_pack_page',w=4.7,scale=0.55,no_pips=true})
        return U.page(nodes)
    end
    function M.install()
        G.FUNCS.oracle_pack_page=function(args) M.page=args.to_key; G.FUNCS.oracle_refresh() end
    end
    return M
end
