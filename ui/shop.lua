return function(O)
    local M={page=1}
    function M.definition()
        local U,T=O.ui,O.text
        local rows,err,s=O.controller.shop_forecast()
        if not rows then
            local nodes={U.message('oracle_shop_unsupported',G.C.ORANGE)}
            if err and err:find('oracle_shop_wait',1,true) then nodes={U.message('oracle_shop_wait',G.C.ORANGE)} end
            if err and err:find('oracle_feature_hidden',1,true) then nodes={U.message('oracle_feature_hidden',G.C.ORANGE)} end
            if s and s.shop.active then
                nodes[#nodes+1]=U.message('oracle_current_shop')
                nodes[#nodes+1]=U.row({O.preview_card.area(s.shop.cards)})
            end
            return U.page(nodes)
        end
        M.page=math.max(1,math.min(M.page,#rows))
        local r=rows[M.page]
        local labels={T.get(s.shop.active and 'oracle_current_shop' or 'oracle_next_shop')}
        for i=2,#rows do labels[i]=T.get('oracle_reroll')..' +'..(i-1) end
        local nodes={
            U.message(r.status=='observed' and 'oracle_observed' or 'oracle_experimental',G.C.ORANGE),
            U.row({U.text(T.get('oracle_shop_slots')..' '..s.shop.limit,0.27,G.C.UI.TEXT_INACTIVE)},0.02),
            U.row({O.preview_card.area(r.cards,nil,{ante=s.game.round_resets.ante,reroll=r.reroll})}),
            O.config.show_packs~=false and U.message('oracle_boosters') or U.row({}),
            O.config.show_packs~=false and U.row({O.preview_card.area(r.packs,0.48)}) or U.row({}),
            U.message('oracle_shop_branch',G.C.UI.TEXT_INACTIVE),
            U.message('oracle_shop_sync',G.C.UI.TEXT_INACTIVE),
            create_option_cycle({options=labels,current_option=M.page,opt_callback='oracle_shop_page',w=4,scale=0.65,no_pips=true}),
        }
        return U.page(nodes)
    end
    function M.install()
        G.FUNCS.oracle_shop_page=function(args) M.page=args.to_key; G.FUNCS.oracle_refresh() end
    end
    return M
end
