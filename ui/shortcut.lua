return function(O)
    local M={}
    function M.install()
        if SMODS.Keybind then
            SMODS.Keybind{key='oracle_open',key_pressed='f8',event='pressed',action=function()
                if G.STAGE==G.STAGES.RUN and O.config.enabled and not G.OVERLAY_MENU
                    and not G.CONTROLLER.text_input_hook then G.FUNCS.oracle_open() end
            end}
        end
        if type(create_UIBox_HUD)~='function' then return end
        local original=create_UIBox_HUD
        create_UIBox_HUD=function(...)
            local tree=original(...)
            local function insert(node)
                for i,child in ipairs(node.nodes or {}) do
                    if child.config and child.config.button=='options' then
                        child.config.minh=0.8
                        table.insert(node.nodes,i+1,{n=G.UIT.R,config={id='oracle_hud_button',align='cm',minh=0.8,minw=1.5,
                            padding=0.05,r=0.1,hover=true,colour=G.C.BLUE,button='oracle_open',shadow=true},nodes={
                            {n=G.UIT.T,config={text=O.text.get('oracle_title'),scale=0.35,colour=G.C.UI.TEXT_LIGHT,shadow=true}},
                        }})
                        return true
                    end
                    if insert(child) then return true end
                end
            end
            insert(tree)
            return tree
        end
    end
    return M
end
