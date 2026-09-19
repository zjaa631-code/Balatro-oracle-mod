return function(O)
    local M = {page = 1, voucher_page = 1}
    local function name(set, key)
        return O.text.name(set, key and {key = key})
    end
    function M.definition()
        local U, T = O.ui, O.text
        local rows, err = O.controller.forecast()
        if not rows then
            local reason = 'oracle_prediction_unavailable'
            for _, key in ipairs({'oracle_transition', 'oracle_pool_unsupported', 'oracle_rng_unsupported'}) do
                if err and err:find(key, 1, true) then reason = key end
            end
            return U.page({U.message(reason, G.C.ORANGE), U.message('oracle_experimental')})
        end
        M.page = math.min(M.page, #rows)
        local r = rows[M.page]
        local labels = {}
        for i, row in ipairs(rows) do labels[i] = T.get('oracle_ante')..' '..row.ante end
        local vouchers = type(r.vouchers) == 'table' and r.vouchers or {r.vouchers}
        M.voucher_page = math.max(1, math.min(M.voucher_page, #vouchers))
        local key = vouchers[M.voucher_page]
        local nodes = {
            U.message(r.status == 'observed' and 'oracle_observed' or 'oracle_experimental', G.C.ORANGE),
            U.row({
                U.field('oracle_small_tag', name('Tag', r.tags.Small), 3.8),
                U.field('oracle_big_tag', name('Tag', r.tags.Big), 3.8),
            }, 0.12),
            U.row({O.tag_ui.summary(r.tags.Small,'Small',r.ante),O.tag_ui.summary(r.tags.Big,'Big',r.ante)},0.02),
            U.row({U.field('oracle_boss', name('Blind', r.boss), 7.8)}),
            O.config.show_voucher~=false and U.row({U.field('oracle_voucher', name('Voucher', key), 7.8)}) or U.row({}),
        }
        if O.config.show_voucher~=false and #vouchers > 1 then
            local options = {}
            for i = 1, #vouchers do options[i] = i..' / '..#vouchers end
            nodes[#nodes + 1] = create_option_cycle({options = options, current_option = M.voucher_page,
                opt_callback = 'oracle_voucher_page', w = 3, scale = 0.6, no_pips = true})
        end
        nodes[#nodes + 1] = U.message('oracle_branch_1', G.C.UI.TEXT_INACTIVE)
        nodes[#nodes + 1] = U.message('oracle_branch_2', G.C.UI.TEXT_INACTIVE)
        nodes[#nodes + 1] = create_option_cycle({options = labels, current_option = M.page,
            opt_callback = 'oracle_ante_page', w = 4, scale = 0.7, no_pips = true})
        return U.page(nodes)
    end
    function M.install()
        G.FUNCS.oracle_ante_page = function(args)
            M.page = args.to_key; M.voucher_page = 1
            G.FUNCS.oracle_refresh()
        end
        G.FUNCS.oracle_voucher_page = function(args)
            M.voucher_page = args.to_key
            G.FUNCS.oracle_refresh()
        end
    end
    return M
end
