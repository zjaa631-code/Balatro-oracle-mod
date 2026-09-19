return function(O)
    local M = {counts = {MATCH = 0, MISMATCH = 0, SKIP = 0}, records = {}, last = nil}
    function M.record(kind, before, expected, actual, details)
        local status = O.data.encode(expected) == O.data.encode(actual) and 'MATCH' or 'MISMATCH'
        local r = {status = status, kind = kind, seed = before.game.pseudorandom.seed,
            ante = before.game.round_resets.ante, round = before.game.round,
            expected = expected, actual = actual, details = details, input = before}
        M.counts[status] = M.counts[status] + 1
        M.last = {status = status, kind = kind, ante = r.ante}
        M.records[#M.records + 1] = r
        if #M.records > 16 then table.remove(M.records, 1) end
        if sendInfoMessage then
            sendInfoMessage(status..' '..kind..' Ante '..tostring(r.ante), 'Oracle')
        end
        if status == 'MISMATCH' then
            -- Any mismatch disables forecasts for the rest of the session.
            -- Never silently continue presenting the same unreliable adapter.
            O.prediction_fault = true
            local line = O.data.encode(r)..'\n'
            if love and love.filesystem then
                local fs = love.filesystem
                local info = fs.getInfo('oracle-validation.log')
                -- Bounded two-file rotation; full input/RNG/pool on mismatches.
                if info and info.size > 1024 * 1024 then
                    local previous = fs.read('oracle-validation.log')
                    assert(fs.write('oracle-validation.previous.log', previous))
                    assert(fs.write('oracle-validation.log', ''))
                end
                assert(fs.append('oracle-validation.log', line))
            end
        end
        return r
    end
    return M
end
