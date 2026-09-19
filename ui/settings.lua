return function(O)
    local M = {}
    local function save()
        if O.controller then O.controller.invalidate() end
        if SMODS and SMODS.save_mod_config then
            local ok, err = pcall(SMODS.save_mod_config, O.mod)
            if not ok then
                O.config_error = true
                if sendWarnMessage then sendWarnMessage(tostring(err), 'Oracle') end
            end
        end
    end
    M.save=save
    function M.event_depth_control()
        return create_option_cycle({label=O.text.get('oracle_event_depth'),options={1,3,5,10,20},
            current_option=({[1]=1,[3]=2,[5]=3,[10]=4,[20]=5})[O.config.event_depth] or 3,
            opt_callback='oracle_event_depth',w=4,scale=0.5,no_pips=true})
    end
    function M.definition()
        local U, T = O.ui, O.text
        local nodes={}
        local fields={{'enabled','oracle_enabled'},{'auto_refresh','oracle_auto_refresh'},
            {'show_draw_order','oracle_show_draw_order'},{'show_future_shops','oracle_show_future_shops'},
            {'show_packs','oracle_show_packs'},{'show_voucher','oracle_show_voucher'},
            {'advanced_info','oracle_advanced'},{'validate_predictions','oracle_validate'}}
        for i=1,#fields,2 do
            local row={}
            for j=i,i+1 do
                row[#row+1]=create_toggle({label=T.get(fields[j][2]),ref_table=O.config,ref_value=fields[j][1],
                    callback=save,w=2.7,scale=0.8,label_scale=0.28,col=true})
            end
            nodes[#nodes+1]=U.row(row,0.02)
        end
        nodes[#nodes+1]=
            create_option_cycle({label = T.get('oracle_depth'), options = {3, 5, 10, 20},
                current_option = ({[3] = 1, [5] = 2, [10] = 3, [20] = 4})[O.config.prediction_depth] or 1,
                opt_callback = 'oracle_depth', w = 4, scale = 0.55, no_pips = true})
        nodes[#nodes+1]=M.event_depth_control()
        nodes[#nodes+1]=U.message('oracle_manual_refresh_hint',G.C.UI.TEXT_INACTIVE)
        nodes[#nodes+1]=U.row({U.text('Oracle '..O.version,0.3,G.C.UI.TEXT_INACTIVE)})
        if O.config.advanced_info and O.status then
            for _, entry in ipairs({{'Balatro', O.status.game}, {'Steamodded', O.status.steamodded}, {'Lovely', O.status.lovely}}) do
                nodes[#nodes + 1] = U.row({U.text(entry[1]..' '..entry[2], 0.3)})
            end
            if O.validator then
                local c = O.validator.counts
                nodes[#nodes + 1] = U.row({U.text('MATCH '..c.MATCH..' / MISMATCH '..c.MISMATCH..' / SKIP '..c.SKIP, 0.27)})
            end
        end
        if O.config_error then nodes[#nodes + 1] = U.message('oracle_config_error', G.C.ORANGE) end
        return U.page(nodes)
    end
    G.FUNCS.oracle_depth = function(args)
        O.config.prediction_depth = args.to_val
        if O.controller then O.controller.invalidate() end
        save()
    end
    G.FUNCS.oracle_event_depth=function(args)
        if not ({[1]=true,[3]=true,[5]=true,[10]=true,[20]=true})[args.to_val] then return end
        O.config.event_depth=args.to_val
        if O.events_ui then O.events_ui.pages={consumable=1,joker=1} end
        save()
        if G.FUNCS.oracle_refresh then G.FUNCS.oracle_refresh() end
    end
    return M
end
