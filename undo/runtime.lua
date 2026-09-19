-- Explicit gameplay rollback. This module is separate from read-only prediction.
return function(O,history)
    local M,D={history=history,restoring=false},O.data
    local function packed(...) return {n=select('#',...),...} end
    local function profile() return tonumber(G.SETTINGS.profile) or 1 end
    function M.safe(fn,...)
        local ok,value=pcall(fn,...)
        if not ok then
            M.error=tostring(value):match('(oracle_[%w_]+)') or 'oracle_undo_error'
            if sendWarnMessage then sendWarnMessage('Undo: '..tostring(value),'Oracle') end
        end
        return ok,value
    end
    function M.supported()
        return O.status and #O.status.issues==0 and G.STAGE==G.STAGES.RUN and not G.F_NO_SAVING
    end
    function M.serializable()
        local st=G.STATES
        return G.STATE==st.SHOP or G.STATE==st.SELECTING_HAND or G.STATE==st.BLIND_SELECT or G.STATE==st.ROUND_EVAL
    end
    function M.busy()
        if M.restoring then return true end
        local locks=(G.CONTROLLER or {}).locks or {}
        for _,key in ipairs({'load','use','selling_card','shop_reroll','blind','skip_blind','reroll_boss'}) do if locks[key] then return true end end
        if (G.GAME.STOP_USE or 0)>0 then return true end
        for _,queue in pairs((G.E_MANAGER or {}).queues or {}) do
            for _,e in ipairs(queue) do
                if e.blocking and not e.complete and not e.created_on_pause then return true end
            end
        end
        return false
    end
    function M.ready()
        if M.error then return false,M.error end
        if not M.supported() then return false,'oracle_undo_unavailable' end
        if M.busy() then return false,'oracle_undo_wait' end
        local st=G.STATES
        if not M.serializable() and G.STATE~=st.GAME_OVER and G.STATE~=st.TAROT_PACK and G.STATE~=st.PLANET_PACK
            and G.STATE~=st.SPECTRAL_PACK and G.STATE~=st.BUFFOON_PACK and G.STATE~=st.STANDARD_PACK
            and G.STATE~=st.SMODS_BOOSTER_OPENED then return false,'oracle_undo_wait' end
        if not history.index or history.index.profile~=profile() or #history.index.undo==0 then return false,'oracle_undo_empty' end
        return true
    end
    function M.ensure()
        if not history.index or history.index.profile~=profile() then history.new(profile()) end
    end
    function M.observe(save)
        if not M.supported() or M.restoring or not M.serializable() then return end
        -- The native ROUND_EVAL autosave precedes reward/tag evaluation. Only
        -- retain its settled pre-action state, so loading cannot repeat rewards.
        if G.STATE==G.STATES.ROUND_EVAL and not M.capturing then return end
        M.ensure()
        local meta={run=history.index.run,sort_id=G.sort_id,playing_card=G.playing_card,playing_order={},highlighted={}}
        local locations={}
        for name in pairs(save.cardAreas) do
            for index,card in ipairs(G[name] and G[name].cards or {}) do
                locations[card]={area=name,index=index}
                if card.highlighted then meta.highlighted[#meta.highlighted+1]={area=name,index=index} end
            end
        end
        for _,card in ipairs(G.playing_cards or {}) do
            assert(locations[card],'oracle_undo_wait')
            meta.playing_order[#meta.playing_order+1]=locations[card]
        end
        save.ORACLE_UNDO=meta
        if G.STATE==G.STATES.ROUND_EVAL then meta.cashout=G.GAME.current_round.dollars end
        history.observe(save)
    end
    function M.before_action()
        if M.restoring or M.error or not M.supported() or not M.serializable() or M.busy() then return end
        -- The native serializer also collects SMODS scoring metadata. This is
        -- an explicit checkpoint for Undo, never part of a prediction call.
        M.capturing=true
        M.safe(function() save_run(); history.begin_action(); M.pending_action=true end)
        M.capturing=nil
    end
    function M.reset_observers()
        O.controller.invalidate()
        for _,key in ipairs({'quick','events_ui','consumables_ui','jokers_ui','packs_ui','boss_analysis_ui'}) do
            if O[key] then O[key].cache=nil end
        end
        if O.quick then O.quick.cache={} end
        if O.events_ui then O.events_ui.cache={} end
        if O.pack_validator then O.pack_validator.pending=nil end
        if O.joker_validator then O.joker_validator.selection=nil end
        if O.consumable_validator then O.consumable_validator.reset() end
        if O.tag_validator then O.tag_validator.pending=setmetatable({},{__mode='k'}); O.tag_validator.active=nil end
        if O.tag_chain_validator then
            local v=O.tag_chain_validator; v.chains={}; v.active=nil; v.copying=nil; v.acquiring=nil
        end
        if O.tag_reward_validator then O.tag_reward_validator.active=nil; O.tag_reward_validator.opening=nil end
        if O.boss_validator then O.boss_validator.seen={}; O.boss_validator.order={} end
        if O.hook_controller then O.hook_controller.pending=nil end
        if O.hook_controller then O.hook_controller.clear() end
    end
    function M.restore()
        local ready,reason=M.ready(); if not ready then return false,reason end
        local ok,target,id=pcall(history.target)
        if not ok then M.safe(function() error(target) end); return false,M.error end
        if not target then return false,'oracle_undo_empty' end
        if target.VERSION~=G.VERSION or not target.GAME or not target.GAME.pseudorandom or not target.cardAreas
            or not target.BLIND or not target.BACK or not target.SCORING_CALC then return false,'oracle_undo_corrupt' end
        target.ACTION=nil
        local copy=D.copy(target)
        -- FIFO: already queued old saves complete BEFORE this replacement.
        -- Never directly race the game's save worker by writing save.jkr.
        local queued,err=pcall(function()
            assert(G.SAVE_MANAGER and G.SAVE_MANAGER.channel,'oracle_undo_unavailable')
            G.SAVE_MANAGER.channel:push({type='save_run',save_table=D.copy(copy),profile_num=profile()})
        end)
        if not queued then M.safe(function() error(err) end); return false,M.error end
        M.restoring=true; M.target=target; M.target_id=id; M.elapsed=0; M.evaluation_rebuilt=nil; M.pending_action=nil
        G.CONTROLLER.locks.oracle_undo=true
        G.FILE_HANDLER=G.FILE_HANDLER or {}; G.FILE_HANDLER.run=nil
        G.ARGS.save_run=D.copy(target)
        M.reset_observers()
        if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end
        -- Old no_delete callbacks also refer to the old run. Discard them before
        -- the native loader queues its own wipe/delete/start lifecycle.
        for _,queue in pairs(G.E_MANAGER.queues or {}) do for i=#queue,1,-1 do table.remove(queue,i) end end
        -- start_run queues deletion/loading: Game:update still dispatches the
        -- old state during intervening (even paused dt=0) frames. Leave gameplay
        -- before clearing its objects, using native delete_run's idle sentinel.
        -- Never run an old pack/hand/shop handler against partially cleared data.
        G.STATE=-1; G.STATE_COMPLETE=false
        G.TAROT_INTERRUPT=nil
        SMODS.OPENED_BOOSTER=nil; SMODS.last_hand=nil
        G.SAVED_GAME=D.copy(target)
        G.FUNCS.start_run(nil,{savetext=copy})
        return true
    end
    function M.update(dt)
        if not M.restoring then
            if M.pending_action and not M.error and M.supported() and M.serializable() and G.STATE_COMPLETE and not M.busy() then
                M.capturing=true
                M.safe(function() save_run(); history.finish_action() end)
                M.capturing=nil; M.pending_action=nil
            end
            return
        end
        M.elapsed=M.elapsed+(dt or 0)
        if not M.loaded or (G.CONTROLLER.locks or {}).load or not G.STATE_COMPLETE then return end
        if not M.serializable() then return end
        if G.load_shop_jokers or G.load_shop_vouchers or G.load_shop_booster then return end
        if M.target.ORACLE_UNDO and M.target.ORACLE_UNDO.cashout~=nil and not M.evaluation_rebuilt then return end
        local target=M.target
        -- Native reconstruction may initialize presentation objects. Restore the
        -- authoritative saved gameplay stream after reconstruction has settled.
        G.GAME.pseudorandom=D.copy(target.GAME.pseudorandom)
        if target.ORACLE_UNDO then
            local meta=target.ORACLE_UNDO
            G.sort_id=meta.sort_id or G.sort_id
            G.playing_card=meta.playing_card or G.playing_card
            if meta.playing_order then
                local order={}
                for _,ref in ipairs(meta.playing_order) do
                    local card=G[ref.area] and G[ref.area].cards[ref.index]
                    if not card then M.error='oracle_undo_corrupt'; break end
                    order[#order+1]=card
                end
                if #order==#meta.playing_order then G.playing_cards=order end
            end
            for _,ref in ipairs(meta.highlighted or {}) do
                local area=G[ref.area]; local card=area and area.cards[ref.index]
                if card and not card.highlighted and area.add_to_highlighted then area:add_to_highlighted(card,true) end
            end
        end
        -- The native save includes this flag but Card:load omits it.
        for name,area in pairs(target.cardAreas) do
            for index,record in ipairs(area.cards or {}) do
                local card=G[name] and G[name].cards[index]
                if card then card.joker_added_to_deck_but_debuffed=record.joker_added_to_deck_but_debuffed end
            end
        end
        M.safe(history.restored,M.target_id)
        M.restoring=false; M.loaded=nil; M.target=nil; M.target_id=nil
        G.CONTROLLER.locks.oracle_undo=nil
        M.reset_observers()
        save_run(); M.safe(history.finish_action); G.FILE_HANDLER.force=true
    end
    function M.install()
        if type(save_run)~='function' or not Game or not Game.start_run then return end
        local native_eval=G.FUNCS.evaluate_round
        if native_eval then G.FUNCS.evaluate_round=function(...)
            local meta=M.restoring and M.target and M.target.ORACLE_UNDO
            if meta and meta.cashout~=nil then
                -- Native bottom row recreates the cash-out button and amount.
                -- Never repeat Joker/Tag rewards or career counters while loading.
                add_round_eval_row({name='bottom',dollars=meta.cashout})
                M.evaluation_rebuilt=true
                return
            end
            return native_eval(...)
        end end
        local native_save=save_run
        save_run=function(...)
            if M.restoring then return end
            local old=G.ARGS and G.ARGS.save_run
            local ret=packed(native_save(...))
            local current=G.ARGS and G.ARGS.save_run
            if current and current~=old then M.safe(M.observe,current) end
            return unpack(ret,1,ret.n)
        end
        local native_start=Game.start_run
        Game.start_run=function(self,args,...)
            args=args or {}
            local incoming=args.savetext
            if not M.restoring then
                M.error=nil; M.pending_action=nil
                M.safe(function()
                    local run=incoming and incoming.ORACLE_UNDO and incoming.ORACLE_UNDO.run
                    if not run or not history.attach(profile(),run) then history.new(profile()) end
                    M.pending_action=history.index.transaction or nil
                    -- Incoming cards do not exist yet. Capturing here would map
                    -- saved records against the previous run's live entities.
                    -- The next native save/action captures the loaded run.
                end)
            end
            local ret=packed(native_start(self,args,...))
            if M.restoring then
                M.loaded=true
                G.CONTROLLER.locks.oracle_undo=true
                G.GAME.pseudorandom=D.copy(M.target.GAME.pseudorandom)
            end
            return unpack(ret,1,ret.n)
        end
        for _,name in ipairs({'play_cards_from_highlighted','discard_cards_from_highlighted','buy_from_shop','sell_card','use_card',
            'reroll_shop','reroll_boss','select_blind','skip_blind','toggle_shop','cash_out'}) do
            local which=name
            local original=G.FUNCS[name]
            if original then G.FUNCS[name]=function(...)
                -- The Hook invokes discard internally; it isn't another player action.
                if not (which=='discard_cards_from_highlighted' and select(2,...)) then M.before_action() end
                return original(...)
            end end
        end
        local native_update=Game.update
        if native_update then Game.update=function(self,dt,...)
            local ret=packed(native_update(self,dt,...)); M.update(dt); return unpack(ret,1,ret.n)
        end end
    end
    return M
end
