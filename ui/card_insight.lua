-- Visual-only native shader and name tooltips. Never flip a card, set an
-- edition, call a live gameplay description, or consume RNG for a preview.
return function(O)
    local M={}
    function M.name(c)
        local p=c.config.center; local b=c.base or {}
        if c.playing_card and b.value and b.suit then
            return localize(b.suit,'suits_plural')..' '..localize(b.value,'ranks')
        end
        return O.text.name(p.set,{key=p.key,name=p.name})
    end
    function M.back_tooltip(c)
        local lines={O.text.get('oracle_face_down_identity')}
        local p=c.config.center
        if c.playing_card and p.key~='c_base' then lines[#lines+1]=O.text.name('Enhanced',{key=p.key,name=p.name}) end
        if c.edition and c.edition.key then lines[#lines+1]=O.text.name('Edition',{key=c.edition.key}) end
        if O.hook_controller.is_target(c) then lines[#lines+1]=O.text.get('oracle_hook_target') end
        return create_popup_UIBox_tooltip({title=M.name(c),text=lines})
    end
    function M.shine(c)
        if c.oracle_preview or not O.hook_controller.is_target(c) then return end
        local sprite=c.sprite_facing=='back' and c.children.back or c.children.center
        if sprite then sprite:draw_shader('voucher',nil,c.ARGS.send_to_shader) end
        if c.sprite_facing~='back' and c.children.front and c.config.center.key~='m_stone' then
            c.children.front:draw_shader('voucher',nil,c.ARGS.send_to_shader)
        end
    end
    function M.install()
        if SMODS.DrawStep then SMODS.DrawStep{key='oracle_hook_glow',order=90,func=M.shine} end
        if not Card or not Card.hover then return end
        local native=Card.hover
        Card.hover=function(c,...)
            if O.config.enabled and G.STAGE==G.STAGES.RUN and c.facing=='back' and not c.oracle_preview and
                not c.no_ui and not G.debug_tooltip_toggle and (not c.states.drag.is or G.CONTROLLER.HID.touch) then
                local ok,popup=pcall(M.back_tooltip,c)
                if ok then
                    c.config.h_popup=popup
                    c.config.h_popup_config={align='tm',offset={x=0,y=-0.1},parent=c}
                    Node.hover(c)
                    return
                end
                if sendWarnMessage then sendWarnMessage('Back card name: '..tostring(popup),'Oracle') end
            end
            return native(c,...)
        end
    end
    return M
end
