return function(O)
    local M={}
    function M.definition()
        local U,T=O.ui,O.text
        local ready,reason=O.undo.ready()
        local nodes={U.message('oracle_undo_scope',G.C.ORANGE),U.message('oracle_undo_pack_hint'),
            U.message('oracle_undo_hotkey',G.C.UI.TEXT_INACTIVE)}
        local i=O.undo.history.index
        nodes[#nodes+1]=U.row({U.text(T.get('oracle_undo_count')..' '..(i and #i.undo or 0),0.35)})
        if ready then
            local ok,target=pcall(O.undo.history.target)
            if ok and target then
                local game=target.GAME
                nodes[#nodes+1]=U.row({U.text(T.get('oracle_ante')..' '..game.round_resets.ante..' · '..
                    T.get('oracle_undo_round')..' '..(game.round or 0)..' · $'..(game.dollars or 0),0.4)})
            end
        else nodes[#nodes+1]=U.message(reason,G.C.ORANGE) end
        if M.message then nodes[#nodes+1]=U.message(M.message,G.C.ORANGE) end
        nodes[#nodes+1]=UIBox_button{button='oracle_undo_apply',func='oracle_undo_can',
            label={T.get('oracle_undo_button')},colour=G.C.RED,minw=4,minh=0.8,scale=0.4}
        nodes[#nodes+1]=U.message('oracle_undo_experimental',G.C.UI.TEXT_INACTIVE)
        return U.page(nodes)
    end
    function M.install()
        G.FUNCS.oracle_undo_can=function(e)
            local ready=O.undo.ready(); e.config.button=ready and 'oracle_undo_apply' or nil
            e.config.colour=ready and G.C.RED or G.C.UI.BACKGROUND_INACTIVE
        end
        G.FUNCS.oracle_undo_apply=function()
            local ok,reason=O.undo.restore(); M.message=not ok and reason or nil
            if not ok and G.OVERLAY_MENU then G.FUNCS.oracle_refresh() end
        end
        if SMODS.Keybind then
            SMODS.Keybind{key='oracle_undo',key_pressed='f9',event='pressed',action=function()
                if O.undo.restoring then return end
                if G.STAGE==G.STAGES.RUN and not G.CONTROLLER.text_input_hook then
                    local ok,reason=O.undo.restore(); M.message=not ok and reason or nil
                    if not ok and not G.OVERLAY_MENU then
                        O.main.active='undo'; G.FUNCS.oracle_refresh()
                    end
                end
            end}
        end
    end
    return M
end
