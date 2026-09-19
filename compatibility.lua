local M = {}
function M.inspect(g, smods, lovely)
    local status = {
        game = tostring(g and g.VERSION or 'unknown'),
        steamodded = tostring(smods and smods.version or 'unknown'),
        lovely = tostring(lovely and lovely.version or 'unknown'),
        issues = {},
        -- A version match alone is NEVER evidence of prediction accuracy.
        prediction_ready = false,
    }
    if status.game ~= '1.0.1o-FULL' then
        status.issues[#status.issues + 1] = 'oracle_unverified_version'
    end
    if not smods or type(smods.load_file) ~= 'function' or not lovely then
        status.issues[#status.issues + 1] = 'oracle_dependency_missing'
    elseif status.steamodded ~= '26.829.0' or status.lovely:gsub('^v', '') ~= '0.9.0' then
        status.issues[#status.issues + 1] = 'oracle_unverified_version'
    end
    status.ui_ready = g and g.FUNCS and g.UIT and g.C and true or false
    return status
end
return M
