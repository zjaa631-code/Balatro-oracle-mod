return function(O)
    local M={}
    function M.install()
        G.FUNCS.oracle_export_logs=function()
            local path,err=O.diagnostics.export()
            local nodes={O.ui.message(path and 'oracle_export_success' or 'oracle_export_failed',G.C.ORANGE)}
            if path then
                nodes[#nodes+1]=O.ui.row({O.ui.text(path:match('[^/]+$'),0.3)})
                nodes[#nodes+1]=O.ui.message('oracle_export_share')
                nodes[#nodes+1]=UIBox_button({button='oracle_report_folder',label={O.text.get('oracle_report_folder')},minw=3,scale=0.4})
            else
                O.diagnostics.note('export',err)
                nodes[#nodes+1]=O.ui.message('oracle_export_failed_hint')
            end
            -- Native paused overlay lifecycle, available even when prediction
            -- compatibility checks fail or a real mismatch disabled the engine.
            if G.FUNCS.overlay_menu then
                G.SETTINGS.paused=true
                G.FUNCS.overlay_menu({definition=create_UIBox_generic_options({back_func='exit_overlay_menu',contents=nodes})})
            end
        end
        G.FUNCS.oracle_report_folder=function()
            local fs=love and love.filesystem
            if fs and love.system and love.system.openURL then
                local path=(fs.getSaveDirectory()..'/'..O.diagnostics.folder):gsub('\\','/')
                path=path:gsub('%%','%%25'):gsub(' ','%%20'):gsub('#','%%23')
                local ok,result=pcall(love.system.openURL,'file://'..(path:sub(1,1)=='/' and '' or '/')..path)
                if not ok or not result then O.diagnostics.note('open report folder',result) end
            end
        end
        if SMODS.Keybind then
            SMODS.Keybind{key='oracle_export_logs',key_pressed='f10',event='pressed',action=function()
                if not (G.CONTROLLER and G.CONTROLLER.text_input_hook) and not (O.undo and O.undo.restoring) then
                    G.FUNCS.oracle_export_logs()
                end
            end}
        end
    end
    return M
end
