#include <cstdio>
#include <new>
#include <lua.hpp>
#include <lauxlib.h>

#include "luaimage.h"
#include "image.h"
#include "pngio.h"

static FILE* checkfile(lua_State *L, int idx) {
    luaL_Stream *ls = (luaL_Stream *) luaL_checkudata(L, idx, LUA_FILEHANDLE);
    if (ls->closef == NULL) luaL_argerror(L, idx, "file is closed");
    return ls->f;
}

static image::RGBA *checkimage(lua_State *L, int idx) {
    idx = lua_absindex(L, idx);
    if (!lua_getmetatable(L, idx)) lua_pushnil(L);
    if (!lua_compare(L, -1, lua_upvalueindex(1), LUA_OPEQ))
        luaL_argerror(L, idx, "expected image");
    lua_pop(L, 1);
    return reinterpret_cast<image::RGBA *>(lua_touserdata(L, idx));
}

static void saveimagedimensions(lua_State *L, int idx, int width, int height) {
    lua_getuservalue(L, idx);
    lua_pushinteger(L, width);
    lua_setfield(L, -2, "width");
    lua_pushinteger(L, height);
    lua_setfield(L, -2, "height");
    lua_pop(L, 1);
}

static int setimage(lua_State *L) {
    image::RGBA *img = checkimage(L, 1);
    int x = luaL_checkinteger(L, 2);
    if (x < 1 || x > img->width()) luaL_argerror(L, 2, "out of bounds");
    int y = luaL_checkinteger(L, 3);
    if (y < 1 || y > img->height()) luaL_argerror(L, 2, "out of bounds");
    float r = static_cast<float>(luaL_checknumber(L, 4));
    float g = static_cast<float>(luaL_checknumber(L, 5));
    float b = static_cast<float>(luaL_checknumber(L, 6));
    float a = static_cast<float>(luaL_optnumber(L, 7, 1.f));
    img->set(x-1, y-1, r, g, b, a);
    return 0;
}

static int getimage(lua_State *L) {
    image::RGBA *img = checkimage(L, 1);
    int x = luaL_checkinteger(L, 2);
    if (x < 1 || x > img->width()) luaL_argerror(L, 2, "out of bounds");
    int y = luaL_checkinteger(L, 3);
    if (y < 1 || y > img->height()) luaL_argerror(L, 2, "out of bounds");
    float r, g, b, a;
    img->get(x-1, y-1, r, g, b, a);
    lua_pushnumber(L, r);
    lua_pushnumber(L, g);
    lua_pushnumber(L, b);
    lua_pushnumber(L, a);
    return 4;
}

static const luaL_Reg methodsimage[] = {
    {"set", setimage},
    {"get", getimage},
    {NULL, NULL}
};

static image::RGBA *pushimage(lua_State *L) {
    void *p = lua_newuserdata(L, sizeof(image::RGBA));
    new (p) image::RGBA;
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);
    lua_newtable(L);
    lua_pushvalue(L, lua_upvalueindex(1));
    luaL_setfuncs(L, methodsimage, 1);
    lua_setuservalue(L, -2);
    return reinterpret_cast<image::RGBA *>(p);
}

static int loadpng(lua_State *L) {
    // try to load from string
    if (lua_isstring(L, 1)) {
        size_t len = 0;
        const char *str = lua_tolstring(L, 1, &len);
        image::RGBA *img = pushimage(L);
        if (!pngio::load(std::string(str, len), *img))
            luaL_argerror(L, 1, "load from memory failed");
        saveimagedimensions(L, -1, img->width(), img->height());
        return 1;
    // else try to load from file
    } else {
        FILE *f = checkfile(L, 1);
        image::RGBA *img = pushimage(L);
        if (!pngio::load(f, *img))
            luaL_argerror(L, 1, "load from file failed");
        saveimagedimensions(L, -1, img->width(), img->height());
        return 1;
    }
}

static int store16png(lua_State *L) {
    FILE *f = checkfile(L, 1);
    image::RGBA *img = checkimage(L, 2);
    if (!pngio::store16(f, *img)) luaL_error(L, "store to file failed");
    lua_pushnumber(L, 1);
    return 1;
}

static int store8png(lua_State *L) {
    FILE *f = checkfile(L, 1);
    image::RGBA *img = checkimage(L, 2);
    if (!pngio::store8(f, *img)) luaL_error(L, "store to file failed");
    lua_pushnumber(L, 1);
    return 1;
}

static int string8png(lua_State *L) {
    image::RGBA *img = checkimage(L, 1);
    std::string str;
    if (!pngio::store8(str, *img)) luaL_error(L, "store to memory failed");
    lua_pushlstring(L, str.data(), str.length());
    return 1;
}

static int string16png(lua_State *L) {
    image::RGBA *img = checkimage(L, 1);
    std::string str;
    if (!pngio::store16(str, *img)) luaL_error(L, "store to memory failed");
    lua_pushlstring(L, str.data(), str.length());
    return 1;
}

static int newimage(lua_State *L) {
    int width = luaL_checkint(L, 1);
    if (width <= 0) luaL_argerror(L, 1, "invalid width");
    int height = luaL_checkint(L, 2);
    if (height <= 0) luaL_argerror(L, 2, "invalid height");
    image::RGBA *img = pushimage(L);
    img->resize(width, height);
    saveimagedimensions(L, -1, width, height);
    return 1;
}

static int indeximage(lua_State *L) {
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    lua_rawget(L, -2);
    return 1;
}

static int tostringimage(lua_State *L) {
    image::RGBA* img = checkimage(L, 1);
    lua_pushfstring(L, "image{%d,%d}", img->width(), img->height());
    return 1;
}

static int gcimage(lua_State *L) {
    image::RGBA* img = checkimage(L, 1);
    img->~RGBA();
    return 0;
}

static const luaL_Reg metaimage[] = {
    {"__gc", gcimage},
    {"__tostring", tostringimage},
    {"__index", indeximage},
    {NULL, NULL}
};

static const luaL_Reg modimage[] = {
    {"image", newimage},
    {NULL, NULL}
};

static const luaL_Reg modpng[] = {
    {"load", loadpng},
    {"store8", store8png},
    {"store16", store16png},
    {"string8", string8png},
    {"string16", string16png},
    {NULL, NULL}
};

extern "C"
#ifndef _WIN32
__attribute__((visibility("default")))
#else
__declspec(dllexport)
#endif
int luaopen_image(lua_State *L) {
    lua_newtable(L); // modimage
    lua_newtable(L); // modimage metaimage
    lua_pushvalue(L, -1); // modimage metaimage metaimage
    lua_setfield(L, -3, "meta"); // modimage metaimage
    lua_pushliteral(L, "image"); // modimage metaimage "image"
    lua_setfield(L, -3, "name"); // modimage metaimage
    lua_pushvalue(L, -1); // modimage metaimage metaimage
    luaL_setfuncs(L, metaimage, 1); // modimage metaimage
    lua_newtable(L); // modimage metaimage modpng
    lua_pushvalue(L, -2); // modimage metaimage modpng metaimage
    luaL_setfuncs(L, modpng, 1); // modimage metaimage modpng
    lua_setfield(L, -3, "png"); // modimage metaimage
    luaL_setfuncs(L, modimage, 1); // modimage
    return 1;
}
