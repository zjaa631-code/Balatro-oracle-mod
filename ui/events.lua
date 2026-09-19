return function(O)
    local M={cache={},pages={consumable=1,joker=1}}
    function M.lines(r)
        local T,lines=O.text,{}
        if r.success~=nil then lines[#lines+1]=T.get(r.success and 'oracle_success' or 'oracle_fail') end
        for _,check in ipairs(r.checks or {}) do
            local label=check.label=='oracle_success' and '' or T.get(check.label)..': '
            lines[#lines+1]=label..T.get(check.success and 'oracle_success' or 'oracle_fail')
        end
        if r.mult~=nil then lines[#lines+1]='+'..r.mult..' '..T.get('oracle_joker_mult') end
        if r.inactive then lines[#lines+1]=T.get(r.inactive) end
        local cards={}
        for _,c in ipairs(r.created or {}) do cards[#cards+1]=O.tag_ui.reward_name(c) end
        for _,c in ipairs(r.changes or {}) do cards[#cards+1]=O.tag_ui.reward_name(c.after) end
        if #cards>0 then lines[#lines+1]=table.concat(cards,' / ') end
        return lines
    end
    function M.nodes(kind,card)
        local U,T=O.ui,O.text
        local depth=O.config.event_depth or 5
        local ok,s=pcall(kind=='consumable' and O.consumables.capture or O.jokers.capture,G,SMODS,card)
        local result,err
        if ok then
            local sig=O.data.encode(s)..':'..depth
            local cached=M.cache[kind]
            if cached and cached.sig==sig then result,err=cached.result,cached.error
            else
                local success,value=pcall(O.engine.predict,'events',s,{kind=kind,depth=depth})
                if success then result=value else err=tostring(value):match('(oracle_[%w_]+)') or 'oracle_action_unsupported' end
                M.cache[kind]={sig=sig,result=result,error=err}; M.pages[kind]=1
            end
        else err=tostring(s):match('(oracle_[%w_]+)') or 'oracle_action_unsupported' end
        local function note(key) return U.row({U.fitted(T.get(key),7.5,0.25)},0.02) end
        local nodes={O.settings.event_depth_control(),note(kind=='consumable' and 'oracle_event_wheel_condition' or 'oracle_event_condition')}
        if not result then nodes[#nodes+1]=U.message(err,G.C.ORANGE); return nodes end
        if kind=='joker' then nodes[#nodes+1]=note('oracle_trigger_'..result.key) end
        local count=math.max(1,math.ceil(#result.rows/5))
        local page=math.max(1,math.min(M.pages[kind],count)); M.pages[kind]=page
        for i=(page-1)*5+1,math.min(page*5,#result.rows) do
            local lines=M.lines(result.rows[i])
            nodes[#nodes+1]=U.row({U.fitted('#'..i..'  '..table.concat(lines,' · '),7.5,0.3)},0.015)
        end
        if result.stop then nodes[#nodes+1]=note(result.stop) end
        if count>1 then
            local labels={}; for i=1,count do labels[i]=((i-1)*5+1)..'–'..math.min(i*5,#result.rows)..' / '..#result.rows end
            nodes[#nodes+1]=create_option_cycle({options=labels,current_option=page,opt_callback='oracle_events_'..kind,w=4,scale=0.4,no_pips=true})
        end
        nodes[#nodes+1]=note('oracle_event_other_actions')
        return nodes
    end
    function M.install()
        for _,kind in ipairs({'consumable','joker'}) do
            local which=kind
            G.FUNCS['oracle_events_'..kind]=function(a) M.pages[which]=a.to_key; G.FUNCS.oracle_refresh() end
        end
    end
    return M
end
