return function(O)
    local M={page=1}
    function M.definition()
        local U,T=O.ui,O.text
        local ok,rows=pcall(function() return O.ante_prediction.rerolls(O.controller.snapshot(),O.config.prediction_depth) end)
        if not ok then return U.page({U.message('oracle_prediction_unavailable',G.C.ORANGE)}) end
        local nodes={U.message('oracle_experimental',G.C.ORANGE),U.message('oracle_boss_branch')}
        local start=(M.page-1)*5+1
        for i=start,math.min(start+4,#rows) do
            nodes[#nodes+1]=U.row({U.field('oracle_reroll',i..'  →  '..T.name('Blind',{key=rows[i]}),7.8,nil,0.36)})
        end
        if #rows>5 then
            local pages={}; for i=1,math.ceil(#rows/5) do pages[i]=tostring(i) end
            nodes[#nodes+1]=create_option_cycle({options=pages,current_option=M.page,opt_callback='oracle_boss_page',w=3,scale=0.6,no_pips=true})
        end
        nodes[#nodes+1]=U.message('oracle_boss_permission',G.C.UI.TEXT_INACTIVE)
        return U.page(nodes)
    end
    function M.install()
        G.FUNCS.oracle_boss_page=function(args) M.page=args.to_key; G.FUNCS.oracle_refresh() end
    end
    return M
end
