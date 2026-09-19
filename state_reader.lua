-- Phase 1 returns detached scalar records. No methods are called on Back,
-- Blind, Card or CardArea: modded accessors may have effects.
-- This overview snapshot is NOT a complete simulation state.
local M = {}
local function scalar(value)
    local t = type(value)
    if t == 'string' or t == 'number' or t == 'boolean' then return value end
end
local function definition(value)
    if type(value) ~= 'table' then return {} end
    return {key = scalar(value.key), name = scalar(value.name)}
end
function M.read(g)
    if not (g and g.STAGES and g.STAGE == g.STAGES.RUN and type(g.GAME) == 'table') then
        return {available = false, reason = 'oracle_no_run'}
    end
    local game = g.GAME
    local resets = game.round_resets or {}
    local rng = game.pseudorandom or {}
    local back = game.selected_back and game.selected_back.effect
    local stake = g.P_CENTER_POOLS and g.P_CENTER_POOLS.Stake
    stake = stake and stake[game.stake] or (g.P_STAKES and g.P_STAKES[game.stake])
    local blind, blind_context
    -- Blind selection can retain last round's Blind object. In the shop it
    -- describes the completed Blind, not the next one.
    if g.STATES and g.STATE == g.STATES.BLIND_SELECT then
        local states = resets.blind_states or {}
        local next_slot
        for _, slot in ipairs({'Small', 'Big', 'Boss'}) do
            local state = states[slot]
            if state ~= 'Defeated' and state ~= 'Skipped' and state ~= 'Hide' then
                next_slot = slot
                break
            end
        end
        local key = resets.blind_choices and resets.blind_choices[next_slot]
        blind = key and g.P_BLINDS and g.P_BLINDS[key]
        blind_context = 'oracle_upcoming_blind'
    else
        blind = game.blind and game.blind.config and game.blind.config.blind
        if not (blind and blind.key) then blind = resets.blind end
        blind_context = 'oracle_current_blind'
        if g.STATES and (g.STATE == g.STATES.SHOP or g.STATE == g.STATES.ROUND_EVAL) then
            blind_context = 'oracle_completed_blind'
        end
    end
    return {
        available = type(rng.seed) == 'string' and rng.seed ~= '',
        reason = 'oracle_run_loading',
        seed = scalar(rng.seed), ante = scalar(resets.ante),
        round = scalar(game.round), blind = definition(blind),
        blind_context = blind_context,
        stake = definition(stake), stake_level = scalar(game.stake),
        back = definition(back and back.center), state = scalar(g.STATE),
    }
end
return M
