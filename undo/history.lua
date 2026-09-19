-- Only Oracle-owned files. Native run/profile files are never written here.
return function(O,io)
    local M,D={index=nil,last_signature=nil},O.data
    local function valid_id(id) return type(id)=='string' and id:match('^%d+%-%d+$') end
    local function root(profile)
        assert(type(profile)=='number' and profile%1==0 and profile>=1 and profile<=100,'oracle_undo_profile')
        return 'oracle-undo/'..profile
    end
    function M.commit()
        local next_index=D.copy(assert(M.index)); next_index.generation=next_index.generation+1
        io.write(root(next_index.profile)..'/index'..(next_index.generation%2)..'.jkr',next_index)
        M.index=next_index
    end
    function M.attach(profile,run)
        local best
        for i=0,1 do
            local ok,v=pcall(io.read,root(profile)..'/index'..i..'.jkr')
            if ok and type(v)=='table' and v.format==1 and v.profile==profile and v.run==run and valid_id(v.run)
                and type(v.generation)=='number' and type(v.undo)=='table' and type(v.serial)=='number'
                and (not best or v.generation>best.generation) then best=v end
        end
        M.index=best; M.last_signature=nil
        return best~=nil
    end
    function M.new(profile)
        local stamp=math.floor(io.time()); local n=0
        repeat n=n+1 until not io.exists(root(profile)..'/'..stamp..'-'..n)
        local run=stamp..'-'..n; io.mkdir(root(profile)..'/'..run)
        M.index={format=1,profile=profile,run=run,generation=0,serial=0,undo={},transaction=false}
        M.last_signature=nil; M.commit(); return run
    end
    local function path(i,id)
        assert(valid_id(i.run) and type(id)=='number' and id%1==0 and id>0,'oracle_undo_corrupt')
        return root(i.profile)..'/'..i.run..'/'..id..'.jkr'
    end
    function M.read(id)
        local i=assert(M.index); local v=io.read(path(i,id))
        assert(type(v)=='table' and v.run==i.run and v.profile==i.profile and v.id==id and type(v.save)=='table','oracle_undo_corrupt')
        return D.copy(v.save)
    end
    function M.observe(save)
        local i=assert(M.index); local s=D.copy(save); s.ACTION=nil
        local sig=D.encode(s)
        if sig==M.last_signature then return false end
        if not M.last_signature and i.current then
            local ok,old=pcall(M.read,i.current)
            if ok and D.encode(old)==sig then M.last_signature=sig; return false end
        end
        local previous=D.copy(i)
        i.serial=i.serial+1
        -- Never overwrite a checkpoint, including after interrupted writes.
        while io.exists(path(i,i.serial)) do i.serial=i.serial+1 end
        local ok,err=pcall(function()
            io.write(path(i,i.serial),{run=i.run,profile=i.profile,id=i.serial,save=s})
            if i.current and not i.transaction then i.undo[#i.undo+1]=i.current end
            i.current=i.serial; M.commit()
        end)
        if not ok then M.index=previous; error(err) end
        M.last_signature=sig; return true
    end
    function M.begin_action()
        local i=assert(M.index); if not i.current then return end
        local before=D.copy(i)
        if i.undo[#i.undo]~=i.current then i.undo[#i.undo+1]=i.current end
        i.transaction=true
        local ok,err=pcall(M.commit); if not ok then M.index=before; error(err) end
    end
    function M.target()
        local i=M.index
        if not i or #i.undo==0 then return nil end
        return M.read(i.undo[#i.undo]),i.undo[#i.undo]
    end
    function M.finish_action()
        if not M.index or not M.index.transaction then return end
        local before=D.copy(M.index); M.index.transaction=false
        local ok,err=pcall(M.commit); if not ok then M.index=before; error(err) end
    end
    function M.restored(id)
        local i=assert(M.index); assert(i.undo[#i.undo]==id,'oracle_undo_corrupt')
        local before=D.copy(i)
        table.remove(i.undo); i.current=id; i.transaction=true
        local ok,err=pcall(M.commit); if not ok then M.index=before; error(err) end
        M.last_signature=nil
    end
    return M
end
