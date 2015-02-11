#include <new>
#include <lua.hpp>
#include <lauxlib.h>

#include "chronos.h"
#include "luachronos.h"

static chronos *checkchronos(lua_State *L, int idx) {
    idx = lua_absindex(L, idx);
    if (!lua_getmetatable(L, idx)) lua_pushnil(L);
    if (!lua_compare(L, -1, lua_upvalueindex(1), LUA_OPEQ))
        luaL_argerror(L, idx, "expected chronos");
    lua_pop(L, 1);
    return reinterpret_cast<chronos *>(lua_touserdata(L, idx));
}

static int resetchronos(lua_State *L) {
    chronos *time = checkchronos(L, 1);
    time->reset();
    return 0;
}

static int elapsedchronos(lua_State *L) {
    chronos *time = checkchronos(L, 1);
    lua_pushnumber(L, time->elapsed());
    return 1;
}

static int timechronos(lua_State *L) {
    chronos *time = checkchronos(L, 1);
    lua_pushnumber(L, time->time());
    return 1;
}

static const luaL_Reg methodschronos[] = {
    {"reset", resetchronos},
    {"time", timechronos},
    {"elapsed", elapsedchronos},
    {NULL, NULL}
};

static int gcchronos(lua_State *L) {
    chronos *time = checkchronos(L, 1);
    time->~chronos();
    return 0;
}

static int tostringchronos(lua_State *L) {
    chronos *time = checkchronos(L, 1);
    lua_pushfstring(L, "chronos{%f}", time->time());
    return 1;
}

static const luaL_Reg metachronos[] = {
    {"__gc", gcchronos},
    {"__tostring", tostringchronos},
    {NULL, NULL}
};

static int newchronos(lua_State *L) {
    void *p = lua_newuserdata(L, sizeof(chronos));
    new (p) chronos;
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);
    return 1;
}

static const luaL_Reg mod[] = {
    {"chronos", newchronos},
    {NULL, NULL}
};

extern "C"
#ifndef _WIN32
__attribute__((visibility("default")))
#else
__declspec(dllexport)
#endif
int luaopen_chronos(lua_State *L) {
    lua_newtable(L); // mod
    lua_newtable(L); // mod meta
    lua_newtable(L); // mod meta index
    lua_pushvalue(L, -2); // mod meta index meta
    luaL_setfuncs(L, methodschronos, 1); // mod meta index
    lua_setfield(L, -2, "__index"); // mod meta
    lua_pushvalue(L, -1); // mod meta meta
    luaL_setfuncs(L, metachronos, 1); // mod meta
    lua_pushvalue(L, -1); // mod meta meta
    lua_setfield(L, -3, "meta"); // mod meta
    luaL_setfuncs(L, mod, 1); // mod
    return 1;
}
