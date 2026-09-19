return function(O)
    local M={pile=1,page=1,when=2,view=1}
    function M.nodes(branch)
        local U,T=O.ui,O.text; local nodes={}
        local names={'next','hand','discard','all'}
        local world=M.when==1 and branch.before or branch.after
        local labels={}; for _,key in ipairs(names) do labels[#labels+1]=T.get('oracle_pile_'..key) end
        nodes[#nodes+1]=U.row({create_option_cycle({options={T.get('oracle_before_use'),T.get('oracle_after_use')},current_option=M.when,
            opt_callback='oracle_branch_when',w=3.4,scale=0.4,no_pips=true}),
            create_option_cycle({options=labels,current_option=M.pile,opt_callback='oracle_branch_pile',w=3.4,scale=0.4,no_pips=true})})
        local cards=O.deck_state.list(world,names[M.pile]); local count=math.max(1,math.ceil(#cards/8))
        M.page=math.max(1,math.min(M.page,count))
        if #cards==0 then nodes[#nodes+1]=U.message('oracle_empty_pile') end
        for first=(M.page-1)*8+1,math.min(M.page*8,#cards),4 do
            local row={}
            for i=first,math.min(first+3,#cards) do row[#row+1]=cards[i] end
            if M.view==1 then nodes[#nodes+1]=U.row({O.preview_card.area(row,0.5)})
            else
                local text={}; for i,c in ipairs(row) do text[#text+1]=(first+i-1)..'. '..O.deck_prediction.label(c) end
                nodes[#nodes+1]=U.row({U.text(table.concat(text,'   '),0.3)})
            end
        end
        local pages={}; for i=1,count do pages[i]=i..' / '..count end
        nodes[#nodes+1]=U.row({create_option_cycle({options={T.get('oracle_cards_view'),T.get('oracle_list_view')},current_option=M.view,
            opt_callback='oracle_branch_view',w=3,scale=0.35,no_pips=true}),
            create_option_cycle({options=pages,current_option=M.page,opt_callback='oracle_branch_page',w=3,scale=0.35,no_pips=true})})
        nodes[#nodes+1]=U.message(branch.after.pack and 'oracle_branch_pack_boundary' or 'oracle_branch_boundary',G.C.UI.TEXT_INACTIVE)
        return nodes
    end
    function M.install()
        for _,field in ipairs({'pile','page','when','view'}) do
            local f=field
            G.FUNCS['oracle_branch_'..f]=function(a) M[f]=a.to_key; if f~='page' then M.page=1 end; G.FUNCS.oracle_refresh() end
        end
    end
    return M
end
