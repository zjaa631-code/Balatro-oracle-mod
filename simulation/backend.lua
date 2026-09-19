-- Windows Balatro's own LuaJIT library, in a NEW Lua global state.
-- Every math.randomseed/math.random below executes in that separate state.
-- No live-state execution followed by rollback; no LuaJIT->LÖVE RNG substitution.
local M = {}
local ffi, lib
local code = "return function(seed, lo, hi) if seed ~= nil then math.randomseed(seed) end; if lo and hi then return math.random(lo,hi) end; return math.random() end"
function M.new()
    if not jit or jit.version_num ~= 20005 or jit.os ~= 'Windows' then
        error('oracle_rng_unsupported')
    end
    if not lib then
        ffi = require('ffi')
        ffi.cdef[[
            typedef struct lua_State lua_State;
            lua_State *luaL_newstate(void);
            void luaL_openlibs(lua_State *L);
            void lua_close(lua_State *L);
            int luaL_loadstring(lua_State *L, const char *s);
            int lua_pcall(lua_State *L, int nargs, int nresults, int errfunc);
            void lua_settop(lua_State *L, int idx);
            void lua_pushvalue(lua_State *L, int idx);
            void lua_pushnumber(lua_State *L, double n);
            void lua_pushnil(lua_State *L);
            double lua_tonumber(lua_State *L, int idx);
            const char *lua_tolstring(lua_State *L, int idx, size_t *len);
        ]]
        lib = ffi.load('lua51')
    end
    local ptr = lib.luaL_newstate()
    assert(ptr ~= nil, 'Cannot allocate shadow Lua state')
    ptr = ffi.gc(ptr, lib.lua_close)
    lib.luaL_openlibs(ptr)
    local function check(status)
        if status ~= 0 then
            local message = lib.lua_tolstring(ptr, -1, nil)
            error(message ~= nil and ffi.string(message) or 'Shadow Lua failure')
        end
    end
    check(lib.luaL_loadstring(ptr, code))
    check(lib.lua_pcall(ptr, 0, 1, 0)) -- stack slot 1 owns the private draw function
    local self = {}
    local function draw(seed, lo, hi)
        assert(ptr ~= nil, 'Closed shadow RNG')
        lib.lua_settop(ptr, 1)
        lib.lua_pushvalue(ptr, 1)
        if seed==nil then lib.lua_pushnil(ptr) else lib.lua_pushnumber(ptr, seed) end
        local argc = 1
        if lo ~= nil and hi ~= nil then
            lib.lua_pushnumber(ptr, lo); lib.lua_pushnumber(ptr, hi); argc = 3
        end
        check(lib.lua_pcall(ptr, argc, 1, 0))
        local result = tonumber(lib.lua_tonumber(ptr, -1))
        lib.lua_settop(ptr, 1)
        return result
    end
    function self.draw(seed,lo,hi)
        assert(type(seed)=='number','Invalid shadow RNG seed/state')
        return draw(seed,lo,hi)
    end
    function self.shuffle(seed,n)
        assert(type(seed)=='number','Invalid shadow RNG seed/state')
        local swaps={}
        for i=n,2,-1 do swaps[i]=draw(i==n and seed or nil,1,i) end
        return swaps
    end
    function self.close()
        if ptr ~= nil then lib.lua_close(ffi.gc(ptr, nil)); ptr = nil end
    end
    return self
end
return M
