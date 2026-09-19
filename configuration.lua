-- Runtime defaults are separate from config.lua, which SMODS persists.
local M={defaults={enabled=true,auto_refresh=true,show_draw_order=true,
    show_future_shops=true,show_packs=true,show_voucher=true,
    advanced_info=false,prediction_depth=3,event_depth=5,validate_predictions=true}}
function M.normalize(config)
    config=config or {}
    for key,value in pairs(M.defaults) do
        if type(config[key])~=type(value) then config[key]=value end
    end
    if not ({[3]=true,[5]=true,[10]=true,[20]=true})[config.prediction_depth] then config.prediction_depth=3 end
    if not ({[1]=true,[3]=true,[5]=true,[10]=true,[20]=true})[config.event_depth] then config.event_depth=5 end
    return config
end
return M
