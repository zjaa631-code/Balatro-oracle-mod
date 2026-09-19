-- Compact native text, appended to the existing card description.
return function(O)
    local M={appended=setmetatable({},{__mode='k'})}
    function M.kind(c)
        if not O.config.enabled or not G.STAGES or G.STAGE~=G.STAGES.RUN or c.oracle_preview then return end
        if c.area==G.deck and G.deck then return 'deck' end
        local p=c.config and c.config.center
        if not p then return end
        if p.set=='Booster' and c.area==G.shop_booster and G.shop_booster and O.config.show_packs~=false then return 'pack' end
        if O.jokers.supported(p.key) and c.area==G.jokers and G.jokers then return 'joker' end
        if O.events.supported('joker',p.key) and c.area and (c.area==G.jokers or c.area==G.hand or c.area==G.play) then return 'joker' end
        if c.ability and c.ability.consumeable and (c.area==G.consumeables or c.area==G.pack_cards or c.area==G.shop_jokers) and c.area then
            return 'consumable'
        end
    end
    function M.name(c)
        local base=c.base or (G.P_CARDS or {})[c.front]
        local name=base and O.deck_prediction.label({base=base}) or O.text.name(c.set or 'Joker',c)
        if base and c.key and c.key~='c_base' then name=name..' · '..O.text.name('Enhanced',c) end
        if c.edition then name=name..' · '..O.text.name('Edition',{key=c.edition}) end
        if c.seal then name=name..' · '..localize(c.seal:lower()..'_seal','labels') end
        if c.legendary then name=name..' → '..O.text.name('Joker',{key=c.legendary}) end
        return name
    end
    function M.lines(kind,c)
        local T=O.text
        local ok,r=pcall(O.quick.get,kind,c)
        if not ok then
            local reason=tostring(r):match('(oracle_[%w_]+)') or 'oracle_prediction_unavailable'
            if reason=='oracle_feature_hidden' or reason=='oracle_deck_reshuffle' or reason=='oracle_pack_wait' then return {T.get(reason)} end
            if O.diagnostics then O.diagnostics.note('hover:'..kind,r) end
            return {T.get(reason),T.get('oracle_export_hint')}
        end
        local lines={T.get(kind=='deck' and 'oracle_next_cards' or kind=='joker' and 'oracle_joker_conditional' or 'oracle_quick_conditional')}
        if kind=='joker' then
            lines[#lines+1]=T.get(r.condition)
            if r.target then
                lines[#lines+1]=T.get('oracle_target')..': '..O.tag_ui.reward_name(r.target)
            end
            if r.target and #r.created>0 then
                for _,copy in ipairs(r.created) do
                    lines[#lines+1]=T.get('oracle_created')..': '..O.tag_ui.reward_name(copy)
                end
            else
                for _,line in ipairs(O.events_ui.lines(r)) do lines[#lines+1]=line end
            end
            if r.reset then
                lines[#lines+1]=T.get('oracle_joker_current_target')..': '..M.reset_name(r.current)
                lines[#lines+1]=T.get('oracle_joker_next_target')..': '..M.reset_name(r.reset)
                lines[#lines+1]=T.get('oracle_reset_ante')..' '..r.ante
            end
            if r.hand then lines[#lines+1]=T.get('oracle_joker_next_target')..': '..localize(r.hand,'poker_hands') end
        elseif kind=='pack' or kind=='deck' then
            local limit=kind=='deck' and 8 or #r.cards
            for i=1,math.min(limit,#r.cards) do lines[#lines+1]=i..'. '..M.name(r.cards[i]) end
            if #r.cards==0 then lines[#lines+1]=T.get('oracle_empty_pile') end
            if #r.cards>limit then lines[#lines+1]=T.get('oracle_quick_more')..' '..(#r.cards-limit) end
            if kind=='deck' then lines[#lines+1]=T.get('oracle_quick_stack') end
        else
            if c.area==G.shop_jokers then lines[#lines+1]=T.get('oracle_quick_shop_use') end
            if r.success~=nil then lines[#lines+1]=T.get(r.success and 'oracle_success' or 'oracle_fail') end
            local function group(label,cards)
                for i,record in ipairs(cards or {}) do
                    if i<=8 then lines[#lines+1]=T.get(label)..': '..M.name(record) end
                end
                if #(cards or {})>8 then lines[#lines+1]=T.get('oracle_quick_more')..' '..(#cards-8) end
            end
            group('oracle_created',r.created)
            if r.target then group('oracle_target',{r.target}) end
            group('oracle_destroyed',r.destroyed)
            local changed={}; for _,v in ipairs(r.changes or {}) do changed[#changed+1]=v.after end
            group('oracle_after_use',changed)
            for i,v in ipairs(r.levels or {}) do
                if i<=5 then lines[#lines+1]=localize(v.hand,'poker_hands')..' '..v.before..' → '..v.after end
            end
            if #(r.levels or {})>5 then lines[#lines+1]=T.get('oracle_quick_more')..' '..(#r.levels-5) end
            if r.money and r.money~=0 then lines[#lines+1]=T.get('oracle_money_change')..' '..(r.money>0 and '+' or '')..'$'..r.money end
            if r.hand_size and r.hand_size~=0 then lines[#lines+1]=T.get('oracle_hand_size_change')..' '..r.hand_size end
        end
        return lines
    end
    function M.reset_name(target)
        target=target or {}
        local parts={}
        if target.rank then parts[#parts+1]=localize(target.rank,'ranks') end
        if target.suit then parts[#parts+1]=localize(target.suit,'suits_plural') end
        return table.concat(parts,' ')
    end
    function M.append(ui,kind,c)
        if not ui or not ui.main or M.appended[ui] then return end
        local lines=M.lines(kind,c)
        M.appended[ui]=true
        ui.main[#ui.main+1]={{n=G.UIT.T,config={text='— '..O.text.get('oracle_title')..' —',scale=0.27,colour=G.C.ORANGE}}}
        for _,line in ipairs(lines) do
            ui.main[#ui.main+1]={{n=G.UIT.T,config={text=line,scale=0.26,colour=G.C.UI.TEXT_DARK}}}
        end
    end
    local function deck_popup(node)
        -- CardArea:save serializes its ENTIRE config. A popup parent in that
        -- table would pull live UI/userdata into the save worker. Keep all
        -- visual state in children, matching Node:hover's UIBox lifetime.
        if not node.children.h_popup then
            node.children.h_popup=UIBox{
                definition=create_popup_UIBox_tooltip({title=O.text.get('oracle_title'),text=M.lines('deck',node)}),
                config={align='cl',offset={x=-0.1,y=0},parent=node,instance_type='POPUP'}}
            node.children.h_popup.states.collide.can=false
            node.children.h_popup.states.drag.can=true
        end
    end
    function M.install()
        if G.UIDEF and G.UIDEF.card_h_popup then
            -- Leave Card.generate_UIBox_ability_table unwrapped: Oracle's
            -- isolated full-card descriptions clone that native function.
            local native=G.UIDEF.card_h_popup
            G.UIDEF.card_h_popup=function(c,...)
                local ui=c.ability_UIBox_table
                local kind=M.kind(c)
                if kind and kind~='deck' then
                    local ok,err=pcall(M.append,ui,kind,c)
                    if not ok and sendWarnMessage then sendWarnMessage('Quick tooltip: '..tostring(err),'Oracle') end
                end
                return native(c,...)
            end
        end
        if Card and Card.hover then
            local native=Card.hover
            Card.hover=function(c,...)
                if M.kind(c)=='deck' and O.config.show_draw_order~=false and not c.no_ui and not G.debug_tooltip_toggle then
                    local ok=pcall(deck_popup,c); if ok then return end
                end
                return native(c,...)
            end
        end
        if CardArea and CardArea.hover then
            local native=CardArea.hover
            CardArea.hover=function(area,...)
                if area==G.deck and O.config.enabled and O.config.show_draw_order~=false and G.STAGE==G.STAGES.RUN and not G.debug_tooltip_toggle then
                    local ok=pcall(deck_popup,area); if ok then return end
                end
                return native(area,...)
            end
        end
    end
    return M
end
