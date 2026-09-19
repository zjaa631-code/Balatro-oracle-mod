-- Checksummed compressed records, isolated Lua reader and alternating index files.
return function()
    local M={}
    function M.exists(path) return love.filesystem.getInfo(path)~=nil end
    function M.mkdir(path) assert(love.filesystem.createDirectory(path),'oracle_undo_write') end
    function M.time() return os.time() end
    local function hash(text) return love.data.encode('string','hex',love.data.hash('sha256',text)) end
    function M.write(path,data)
        M.mkdir(assert(path:match('^(.*)/')))
        local text=STR_PACK(data)
        local bytes='ORACLE1 '..hash(text)..'\n'..love.data.compress('string','deflate',text,1)
        assert(love.filesystem.write(path,bytes),'oracle_undo_write')
    end
    function M.read(path)
        local bytes=assert(love.filesystem.read(path),'oracle_undo_corrupt')
        local checksum,body=bytes:match('^ORACLE1 (%x+)\n(.*)$')
        assert(checksum and #checksum==64,'oracle_undo_corrupt')
        local text=love.data.decompress('string','deflate',body)
        assert(hash(text)==checksum and text:sub(1,7)=='return ','oracle_undo_corrupt')
        local fn=assert(loadstring(text)); setfenv(fn,{})
        return fn()
    end
    return M
end
