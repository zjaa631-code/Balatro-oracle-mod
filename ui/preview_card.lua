-- Native Card rendering, with a UI-only constructor/lifecycle. Never calls
-- Card.init/set_ability/set_edition/remove, which change run state or RNG.
return function(O)
    local M = {}
    local Preview
    function M.class()
        if Preview then return Preview end
        Preview = Card:extend()
        function Preview:init(record, scale)
            self.oracle_preview = true
            local center = assert(G.P_CENTERS[record.key])
            local front = record.front and G.P_CARDS[record.front]
            Moveable.init(self,0,0,G.CARD_W*scale,G.CARD_H*scale)
            self.params={bypass_discovery_center=true,bypass_discovery_ui=true,bypass_lock=true}
            self.config={center=center,center_key=record.key,card=front or {},card_key=record.front}
            self.CT=self.VT; self.original_T=copy_table(self.T)
            self.tilt_var={mx=0,my=0,dx=0,dy=0,amt=0}; self.ambient_tilt=0.2
            self.sort_id=-self.ID; self.unique_val=1-self.ID/1603301
            self.back='selected_back'; self.facing='front'; self.sprite_facing='front'
            self.bypass_discovery_center=true; self.bypass_discovery_ui=true; self.bypass_lock=true
            self.children={shadow=Moveable(0,0,0,0)}
            self.ability=O.data.copy(center.config or {})
            for _,key in ipairs({'mult','h_mult','h_x_mult','h_dollars','p_dollars','t_mult','t_chips','bonus',
                'perma_bonus','perma_mult','perma_x_mult','perma_h_chips','perma_h_x_chips','perma_h_mult',
                'perma_h_x_mult','perma_x_chips','perma_p_dollars','perma_h_dollars','perma_repetitions',
                'perma_score','perma_h_score','perma_x_score','perma_h_x_score','perma_blind_size',
                'perma_h_blind_size','perma_x_blind_size','perma_h_x_blind_size'}) do
                self.ability[key]=self.ability[key] or 0
            end
            self.ability.name=center.name; self.ability.set=center.set
            self.ability.eternal=record.eternal; self.ability.perishable=record.perishable
            self.ability.rental=record.rental; self.ability.perish_tally=G.GAME.perishable_rounds
            self.ability.to_do_poker_hand=record.to_do_poker_hand
            self.ability.invis_rounds=0; self.ability.caino_xmult=1
            if center.name=='Loyalty Card' then self.ability.loyalty_remaining=self.ability.extra.every end
            if center.name=='Yorick' then self.ability.yorick_discards=self.ability.extra.discards end
            if record.ability then
                for key,value in pairs(record.ability) do self.ability[key]=O.data.copy(value) end
            end
            self.ability.x_mult=self.ability.x_mult or self.ability.Xmult or 1
            self.ability.extra_value=self.ability.extra_value or 0
            self.ability.consumeable=center.consumeable and O.data.copy(center.config) or nil
            self.ability.card_limit=0; self.ability.extra_slots_used=0
            local rank=front and SMODS.Ranks[front.value] or {}
            local suit=front and SMODS.Suits[front.suit] or {}
            self.base=front and {suit=front.suit,value=front.value,nominal=rank.nominal or 0,
                face_nominal=rank.face_nominal or 0,id=rank.id,suit_nominal=suit.suit_nominal or 0,colour=G.C.SUITS[front.suit]} or {}
            if record.base then self.base=O.data.copy(record.base) end
            self.seal=record.seal
            self.base_cost=0; self.cost=0; self.sell_cost=0; self.sell_cost_label=0
            self.extra_cost=0; self.zoom=true; self.debuff=record.debuff or false; self.highlighted=false
            self.discard_pos={x=0,y=0,r=0}; self.click_timeout=0.3
            self.label=center.name; self.record=record
            self.states.drag.can=false; self.states.click.can=false
            self.states.hover.can=true; self.states.collide.can=true
            if record.edition then
                self.edition=O.data.copy(G.P_CENTERS[record.edition].config)
                self.edition[record.edition:sub(3)]=true; self.edition.key=record.edition
                self.edition.type=record.edition:sub(3)
            end
            -- Preserve native special card silhouettes.
            if center.name=='Half Joker' then self.T.h=self.T.h/1.7
            elseif center.name=='Photograph' then self.T.h=self.T.h/1.2
            elseif center.name=='Square Joker' then self.T.h=self.T.w
            elseif center.name=='Wee Joker' then self.T.w=self.T.w*0.7; self.T.h=self.T.h*0.7 end
            self:set_sprites(center,front)
            for _, child in pairs(self.children) do child.parent=self end
            self:hard_set_VT()
        end
        function Preview:update() end -- No gameplay/Card/JokerDisplay update hooks.
        function Preview:click() end
        function Preview:highlight() end
        function Preview:juice_up() Moveable.juice_up(self,0.02,0.01) end
        function Preview:hover()
            self:juice_up()
            local ok,popup=pcall(O.tooltip.build,self)
            if ok then
                self.config.h_popup=popup
                self.config.h_popup_config={align='tm',offset={x=0,y=-0.1},parent=self}
                Node.hover(self)
                return
            end
            if sendWarnMessage then sendWarnMessage(tostring(popup),'Oracle tooltip') end
            local lines={O.text.get('oracle_type_'..self.record.set)}
            for _, key in ipairs({'edition','eternal','perishable','rental'}) do
                local v=self.record[key]
                if v then lines[#lines+1]=O.text.get('oracle_'..(key=='edition' and v or key)) end
            end
            if self.record.variant_unknown then lines[#lines+1]=O.text.get('oracle_cover_unknown') end
            if O.config.advanced_info then lines[#lines+1]=self.record.key end
            self.config.h_popup=create_popup_UIBox_tooltip({title=O.text.name(self.record.set,{key=self.record.key}),text=lines})
            self.config.h_popup_config={align='tm',offset={x=0,y=-0.1},parent=self}
            Node.hover(self)
        end
        function Preview:stop_hover() Node.stop_hover(self) end
        function Preview:remove()
            if self.REMOVED then return end
            self.REMOVED=true
            Moveable.remove(self)
        end
        return Preview
    end
    function M.area(records, scale, origin)
        scale=scale or 0.75
        local width=#records==1 and G.CARD_W*scale or 7.6
        local area=CardArea(0,0,width,G.CARD_H*scale+0.2,{card_limit=math.max(1,#records),type='title',highlight_limit=0,card_w=G.CARD_W*scale})
        area.oracle_preview=true
        for i, record in ipairs(records) do
            local r=record
            if origin then r=O.data.copy(record); r.oracle_origin=O.data.copy(origin); r.oracle_origin.slot=i end
            if G.P_CENTERS[r.key] then area:emplace(M.class()(r,scale)) end
        end
        return {n=G.UIT.O,config={object=area}}
    end
    return M
end
