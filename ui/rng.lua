return function(O)
    local M={page=1}
    function M.read()
        local out={}
        for key,value in pairs((G.GAME or {}).pseudorandom or {}) do
            if type(value)=='number' or type(value)=='string' then out[#out+1]={key=tostring(key),value=value} end
        end
        table.sort(out,function(a,b) return a.key<b.key end)
        return out
    end
    function M.definition()
        local U=O.ui
        if not O.config.advanced_info then return U.page({U.message('oracle_rng_enable')}) end
        local records=M.read()
        local pages=math.max(1,math.ceil(#records/6)); M.page=math.max(1,math.min(M.page,pages))
        local nodes={U.message('oracle_rng_readonly',G.C.ORANGE)}
        for i=(M.page-1)*6+1,math.min(M.page*6,#records) do
            local r=records[i]
            local value=type(r.value)=='number' and string.format('%.17g',r.value) or r.value
            nodes[#nodes+1]=U.row({U.fitted(r.key,3.6,0.28),U.fitted(value,4,0.28)},0.025)
        end
        if #records==0 then nodes[#nodes+1]=U.message('oracle_no_run') end
        local labels={}; for i=1,pages do labels[i]=i..' / '..pages end
        nodes[#nodes+1]=create_option_cycle({options=labels,current_option=M.page,opt_callback='oracle_rng_page',w=3,scale=0.5,no_pips=true})
        return U.page(nodes)
    end
    G.FUNCS.oracle_rng_page=function(args) M.page=args.to_key; G.FUNCS.oracle_refresh() end
    return M
end
