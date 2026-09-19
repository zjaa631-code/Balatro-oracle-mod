return function(O)
    local M={page=1,pile=1,view=1}
    local names={'next','hand','discard','all'}
    function M.definition()
        local U,T=O.ui,O.text
        if not O.config.enabled then return U.page({U.message('oracle_disabled')}) end
        if O.config.show_draw_order==false then return U.page({U.message('oracle_feature_hidden')}) end
        local ok,s=pcall(O.deck_prediction.read,G)
        if not ok then return U.page({U.message('oracle_deck_unavailable')}) end
        local cards=s[names[M.pile]]
        local pages=math.max(1,math.ceil(#cards/8)); M.page=math.max(1,math.min(M.page,pages))
        local nodes={U.message(M.pile==1 and s.drawing_context and 'oracle_next_cards' or 'oracle_observed',G.C.ORANGE)}
        local counts={}
        for _,key in ipairs(names) do counts[#counts+1]=T.get('oracle_pile_'..key)..' '..#s[key] end
        nodes[#nodes+1]=create_option_cycle({options=counts,current_option=M.pile,opt_callback='oracle_deck_pile',w=4,scale=0.5,no_pips=true})
        local first=(M.page-1)*8+1
        if #cards==0 then nodes[#nodes+1]=U.message('oracle_empty_pile') end
        local renderable=M.view==1
        for i=first,math.min(first+7,#cards) do if not cards[i].renderable then renderable=false end end
        if renderable then
            for start=first,math.min(first+7,#cards),4 do
                local row={}; for i=start,math.min(start+3,#cards,first+7) do row[#row+1]=cards[i] end
                nodes[#nodes+1]=U.row({O.preview_card.area(row,0.62)})
            end
        else
            for i=first,math.min(first+7,#cards) do
                local c=cards[i]
                local text=i..'. '..O.deck_prediction.label(c)
                if c.key~='c_base' then text=text..' · '..T.name('Enhanced',c) end
                if c.edition then text=text..' · '..T.get('oracle_'..c.edition) end
                if c.seal then text=text..' · '..localize(c.seal:lower()..'_seal','labels') end
                nodes[#nodes+1]=U.row({U.text(text,0.3) },0.01)
            end
        end
        nodes[#nodes+1]=U.message('oracle_deck_boundary',G.C.UI.TEXT_INACTIVE)
        if M.pile==1 and not s.drawing_context then nodes[#nodes+1]=U.message('oracle_deck_reshuffle',G.C.ORANGE) end
        local labels={}; for i=1,pages do labels[i]=tostring((i-1)*8+1)..'–'..math.min(i*8,#cards)..' / '..#cards end
        if #cards==0 then labels={'0 / 0'} end
        nodes[#nodes+1]=U.row({create_option_cycle({options={T.get('oracle_cards_view'),T.get('oracle_list_view')},
            current_option=M.view,opt_callback='oracle_deck_view',w=2.7,scale=0.45,no_pips=true}),
            create_option_cycle({options=labels,current_option=M.page,opt_callback='oracle_deck_page',w=3.2,scale=0.45,no_pips=true})})
        return U.page(nodes)
    end
    function M.install()
        for _,field in ipairs({'pile','view','page'}) do
            local name=field
            G.FUNCS['oracle_deck_'..name]=function(args)
                M[name]=args.to_key; if name=='pile' then M.page=1 end
                G.FUNCS.oracle_refresh()
            end
        end
    end
    return M
end
