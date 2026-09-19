-- User-triggered local report. Never executes predictions, reads profile saves,
-- clears a fault, or writes gameplay state. Each section can fail independently.
return function(O)
    local M={recent={},folder='oracle-reports'}
    function M.note(kind,err)
        local entry={kind=tostring(kind),error=tostring(err)}
        local last=M.recent[#M.recent]
        if last and last.kind==entry.kind and last.error==entry.error then return end
        M.recent[#M.recent+1]=entry
        if #M.recent>16 then table.remove(M.recent,1) end
    end
    local function tail(fs,path)
        local info=fs.getInfo(path)
        if not info then return '(not present)' end
        local cap=512*1024
        if info.size<=cap then return assert(fs.read(path)) end
        if not fs.newFile then return '(oversized log; tail API unavailable)' end
        local file=assert(fs.newFile(path))
        local ok,result=pcall(function()
            assert(file:open('r')); assert(file:seek(info.size-cap))
            return '[truncated to last 512 KiB]\n'..assert(file:read(cap))
        end)
        pcall(function() file:close() end)
        if not ok then error(result) end
        return result
    end
    function M.build(fs)
        local parts={'ORACLE DIAGNOSTIC REPORT\nCreated: '..os.date('%Y-%m-%d %H:%M:%S'),
            'Local diagnostic data only. Includes run seed/RNG and log excerpts; no profile saves or undo history.'}
        local function section(name,read,raw)
            local ok,value=pcall(function()
                local data=read()
                return raw and tostring(data) or O.data.encode(data)
            end)
            value=ok and value or ('SECTION ERROR: '..tostring(value))
            if #value>2*1024*1024 then value=value:sub(1,2*1024*1024)..'\n[section truncated]' end
            parts[#parts+1]='\n=== '..name..' ===\n'..value
        end
        section('versions_and_status',function()
            local mods={}
            for _,mod in ipairs(SMODS.mod_list or {}) do mods[#mods+1]={id=mod.id,version=mod.version,can_load=mod.can_load} end
            local major,minor,revision
            if love.getVersion then major,minor,revision=love.getVersion() end
            return {oracle=O.version,game=G.VERSION,steamodded=SMODS.version,
                love={major,minor,revision},compatibility=O.status,mods=mods,
                prediction_fault=O.prediction_fault or false,restoring=O.undo and O.undo.restoring or false,
                config=O.config,counts=O.validator.counts,last_validation=O.validator.last,recent_errors=M.recent}
        end)
        section('run',function() return O.state_reader.read(G) end)
        section('last_mismatch',function()
            for i=#O.validator.records,1,-1 do
                if O.validator.records[i].status=='MISMATCH' then return O.validator.records[i] end
            end
        end)
        section('pack_snapshot_and_reasons',function() return O.pack_prediction.capture(G,SMODS) end)
        section('shop_snapshot_and_reasons',function() return O.shop_snapshot.capture(G,SMODS) end)
        section('deck',function() return O.deck_prediction.read(G) end)
        section('owned_cards',function()
            local out={}
            for _,name in ipairs({'jokers','consumeables'}) do
                out[name]={}
                for _,card in ipairs(G[name] and G[name].cards or {}) do out[name][#out[name]+1]=O.deck_prediction.card(card,G) end
            end
            return out
        end)
        section('oracle-validation.log',function() return tail(fs,'oracle-validation.log') end,true)
        section('oracle-validation.previous.log',function() return tail(fs,'oracle-validation.previous.log') end,true)
        section('latest_lovely_log',function()
            local paths={}
            for _,name in ipairs(fs.getDirectoryItems('Mods/lovely/log')) do
                if name:match('^lovely%-.+%.log$') and not name:find('[/\\]') then paths[#paths+1]=name end
            end
            table.sort(paths)
            if #paths==0 then return '(not present)' end
            return paths[#paths]..'\n'..tail(fs,'Mods/lovely/log/'..paths[#paths])
        end,true)
        return table.concat(parts,'\n')..'\n'
    end
    function M.export()
        local ok,result=pcall(function()
            local fs=assert(love and love.filesystem,'filesystem unavailable')
            assert(fs.createDirectory(M.folder),'cannot create report directory')
            local base=M.folder..'/Oracle-'..os.date('%Y%m%d-%H%M%S')
            local path=base..'.txt'; local index=1
            while fs.getInfo(path) do path=base..'-'..index..'.txt'; index=index+1 end
            assert(fs.write(path,M.build(fs)),'cannot write diagnostic report')
            return path
        end)
        if ok then M.last_path=result; M.last_error=nil; return result end
        M.last_error=tostring(result); return nil,M.last_error
    end
    return M
end
