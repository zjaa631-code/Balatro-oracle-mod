return function(O)
    return function()
        local U, T = O.ui, O.text
        if not O.config.enabled then return U.page({U.message('oracle_disabled')}) end
        -- Open / tab select / Refresh events reread the state. No frame polling.
        local s = O.state_reader.read(G)
        if not s.available then return U.page({U.message(s.reason)}) end
        local nodes = {
            U.message('oracle_readonly', G.C.UI.TEXT_INACTIVE),
            U.row({U.field('oracle_seed', s.seed, 7.8, G.C.ORANGE, 0.6)}),
            U.row({
                U.field('oracle_ante', s.ante, 2.1, G.C.RED, 0.55),
                U.field(s.blind_context, T.name('Blind', s.blind), 5.45),
            }, 0.12),
            U.row({
                U.field('oracle_stake', T.name('Stake', s.stake), 3.8),
                U.field('oracle_deck', T.name('Back', s.back), 3.8),
            }, 0.12),
            U.message('oracle_phase2', G.C.UI.TEXT_INACTIVE),
        }
        if O.status and #O.status.issues > 0 then
            nodes[#nodes + 1] = U.message(O.status.issues[1], G.C.ORANGE)
        end
        return U.page(nodes)
    end
end
