#include <cstdio>
#include <lua.hpp>
#include <lauxlib.h>

#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_OUTLINE_H
#include FT_GLYPH_H
#include FT_BBOX_H

#define LIBRARYIDX (lua_upvalueindex(1))
#define METAFACEIDX (lua_upvalueindex(2))

#include "luafreetype.h"

// FT_Outline_Decompose

static int indexface(lua_State *L) {
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    lua_rawget(L, -2);
    return 1;
}

FT_Face *checkface(lua_State *L, int idx) {
    idx = lua_absindex(L, idx);
    if (!lua_getmetatable(L, idx)) lua_pushnil(L);
    if (!lua_compare(L, -1, METAFACEIDX, LUA_OPEQ))
        luaL_argerror(L, idx, "expected face");
    lua_pop(L, 1);
    return reinterpret_cast<FT_Face *>(lua_touserdata(L, idx));
}

static int tostringface(lua_State *L) {
    FT_Face *face = checkface(L, 1);
    lua_pushfstring(L, "face{%s,%s}", (*face)->family_name,
            (*face)->style_name);
    return 1;
}

static int  gcface(lua_State *L) {
    FT_Face *face = checkface(L, 1);
    FT_Done_Face(*face);
    return 0;
}

static const luaL_Reg metaface[] = {
    {"__gc", gcface},
    {"__tostring", tostringface},
    {"__index", indexface},
    {NULL, NULL}
};

static int moveto(lua_State *L, int tabidx, int cmdidx, FT_Vector p0) {
    lua_pushliteral(L, "move_to_abs");
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p0.x);
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p0.y);
    lua_rawseti(L, tabidx, cmdidx++);
    return cmdidx;
}

static int lineto(lua_State *L, int tabidx, int cmdidx, FT_Vector p0) {
    lua_pushliteral(L, "line_to_abs");
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p0.x);
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p0.y);
    lua_rawseti(L, tabidx, cmdidx++);
    return cmdidx;
}

static int quadto(lua_State *L, int tabidx, int cmdidx,
    FT_Vector p0, FT_Vector p1) {
    lua_pushliteral(L, "quad_to_abs");
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p0.x);
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p0.y);
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p1.x);
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p1.y);
    lua_rawseti(L, tabidx, cmdidx++);
    return cmdidx;
}

static int cubicto(lua_State *L, int tabidx, int cmdidx,
    FT_Vector p0, FT_Vector p1, FT_Vector p2) {
    lua_pushliteral(L, "cubic_to_abs");
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p0.x);
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p0.y);
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p1.x);
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p1.y);
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p2.x);
    lua_rawseti(L, tabidx, cmdidx++);
    lua_pushinteger(L, p2.y);
    lua_rawseti(L, tabidx, cmdidx++);
    return cmdidx;
}

static int closepath(lua_State *L, int tabidx, int cmdidx) {
    lua_pushliteral(L, "close_path");
    lua_rawseti(L, tabidx, cmdidx++);
    return cmdidx;
}

static bool isi(int tag) {
    return (tag&0x1);
}

static bool isq(int tag) {
    return (!(tag&0x1) && !(tag&0x2));
}

static bool isc(int tag) {
    return (!(tag&0x1) && (tag&0x2));
}

static void copyglyphattribs(lua_State *L, FT_GlyphSlot glyph, int idx) {
    idx = lua_absindex(L, idx);
    lua_newtable(L);
    lua_pushinteger(L, glyph->metrics.width);
    lua_setfield(L, -2, "width");
    lua_pushinteger(L, glyph->metrics.height);
    lua_setfield(L, -2, "height");
    lua_pushinteger(L, glyph->metrics.horiBearingX);
    lua_setfield(L, -2, "horiBearingX");
    lua_pushinteger(L, glyph->metrics.horiBearingY);
    lua_setfield(L, -2, "horiBearingY");
    lua_pushinteger(L, glyph->metrics.horiAdvance);
    lua_setfield(L, -2, "horiAdvance");
    lua_pushinteger(L, glyph->metrics.vertBearingX);
    lua_setfield(L, -2, "vertBearingX");
    lua_pushinteger(L, glyph->metrics.vertBearingY);
    lua_setfield(L, -2, "vertBearingY");
    lua_pushinteger(L, glyph->metrics.vertAdvance);
    lua_setfield(L, -2, "vertAdvance");
    lua_setfield(L, idx, "metrics");
    lua_pushnumber(L, glyph->linearHoriAdvance);
    lua_setfield(L, idx, "linearHoriAdvance");
    lua_pushnumber(L, glyph->linearVertAdvance);
    lua_setfield(L, idx, "linearVertAdvance");
}

static void copyglyphoutline(lua_State *L, FT_Outline outline, int tabidx) {
    tabidx = lua_absindex(L, tabidx);
    int cmdidx = 1;
    int i = 0, j = 0;
    while (i < outline.n_contours) {
        FT_Vector p[4];
        int tag[4] = {INT_MAX, INT_MAX, INT_MAX, INT_MAX};
        FT_Vector p0 = p[j%4] = outline.points[j];
        tag[j%4] = outline.tags[j];
        cmdidx = moveto(L, tabidx, cmdidx, p[j%4]);
        j++;
        while (j <= outline.contours[i]) {
            p[j%4] = outline.points[j];
            tag[j%4] = outline.tags[j];
            if (isi(tag[(j-1)%4])) {
                if (isi(tag[j%4]))
                    cmdidx = lineto(L, tabidx, cmdidx, p[j%4]);
            } else if (isq(tag[(j-1)%4])) {
                if (isi(tag[j%4])) {
                    cmdidx = quadto(L, tabidx, cmdidx, p[(j-1)%4], p[j%4]);
                } else if (isq(tag[j%4])) {
                    FT_Vector pm;
                    pm.x = (p[(j-1)%4].x+p[j%4].x)/2;
                    pm.y = (p[(j-1)%4].y+p[j%4].y)/2;
                    cmdidx = quadto(L, tabidx, cmdidx, p[(j-1)%4], pm);
                    p[(j-1)%4] = pm;
                    tag[(j-1)%4] = 1; // 'i'
                } else {
                    luaL_error(L, "illformed quadratic!");
                }
            } else if (isc(tag[(j-1)%4])) {
                if (isi(tag[j%4])) {
                    if (isc(tag[(j-2)%4]) && isi(tag[(j-3)%4])) {
                        cmdidx = cubicto(L, tabidx, cmdidx,
                            p[(j-2)%4], p[(j-1)%4], p[j%4]);
                    } else {
                        luaL_error(L, "illformed cubbic!");
                    }
                }
            } else {
                luaL_error(L, "unknown control tag!");
            }
            j++;
        }
        // last point that closes the contour
        p[j%4] = p0;
        tag[j%4] = 1; // 'i'
        if (isi(tag[(j-1)%4])) {
            cmdidx = lineto(L, tabidx, cmdidx, p[j%4]);
        } else if (isq(tag[(j-1)%4])) {
            cmdidx = quadto(L, tabidx, cmdidx, p[(j-1)%4], p[j%4]);
        } else if (isc(tag[(j-1)%4])) {
            cmdidx = cubicto(L, tabidx, cmdidx, p[(j-2)%4],
                p[(j-1)%4], p[j%4]);
        }
        cmdidx = closepath(L, tabidx, cmdidx);
        i++;
    }
}

static int glyphface(lua_State *L) {
    FT_Face face = *checkface(L, 1);
    int index = FT_Get_Char_Index(face, luaL_checkinteger(L, 2));
    if (!FT_Load_Glyph(face, index,
        FT_LOAD_LINEAR_DESIGN |
        FT_LOAD_NO_SCALE |
        FT_LOAD_IGNORE_TRANSFORM)) {
        lua_newtable(L);
        copyglyphoutline(L, face->glyph->outline, -1);
        copyglyphattribs(L, face->glyph, -1);
        lua_pushvalue(L, 1);
        lua_setfield(L, -2, "face");
        return 1;
    } else {
        lua_pushnil(L);
        return 1;
    }
}

static int kernface(lua_State *L) {
    FT_Face face = *checkface(L, 1);
    int previndex = FT_Get_Char_Index(face, luaL_checkinteger(L, 2));
    int index = FT_Get_Char_Index(face, luaL_checkinteger(L, 3));
    if (FT_HAS_KERNING(face)) {
        FT_Vector delta;
        FT_Get_Kerning(face, previndex, index, FT_KERNING_UNSCALED, &delta);
        lua_pushinteger(L, delta.x);
        lua_pushinteger(L, delta.y);
        return 2;
    } else {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        return 2;
    }
}

static const luaL_Reg methodsface[] = {
    {"glyph", glyphface},
    {"kern", kernface},
    {NULL, NULL}
};

FT_Library upvaluelibrary(lua_State *L) {
    return *reinterpret_cast<FT_Library *>(lua_touserdata(L, LIBRARYIDX));
}

void copyfaceattribs(lua_State *L, FT_Face face, int idx) {
    idx = lua_absindex(L, idx);
    lua_pushinteger(L, face->num_faces);
    lua_setfield(L, idx, "num_faces");
    lua_pushinteger(L, face->face_index);
    lua_setfield(L, idx, "face_index");
    lua_pushinteger(L, face->num_glyphs);
    lua_setfield(L, idx, "num_glyphs");
    if (face->family_name) {
        lua_pushstring(L, face->family_name);
        lua_setfield(L, idx, "face_family");
    }
    if (face->style_name) {
        lua_pushstring(L, face->style_name);
        lua_setfield(L, idx, "style_name");
    }
    lua_pushinteger(L, face->units_per_EM);
    lua_setfield(L, idx, "units_per_EM");
    lua_pushinteger(L, face->ascender);
    lua_setfield(L, idx, "ascender");
    lua_pushinteger(L, face->descender);
    lua_setfield(L, idx, "descender");
    lua_pushinteger(L, face->height);
    lua_setfield(L, idx, "height");
    lua_pushinteger(L, face->max_advance_width);
    lua_setfield(L, idx, "max_advance_width");
    lua_pushinteger(L, face->max_advance_height);
    lua_setfield(L, idx, "max_advance_height");
    lua_pushinteger(L, face->underline_position);
    lua_setfield(L, idx, "underline_position");
    lua_pushinteger(L, face->underline_thickness);
    lua_setfield(L, idx, "underline_thickness");
    lua_newtable(L);
    lua_pushinteger(L, face->bbox.xMin);
    lua_setfield(L, -2, "xMin");
    lua_pushinteger(L, face->bbox.yMin);
    lua_setfield(L, -2, "yMin");
    lua_pushinteger(L, face->bbox.xMax);
    lua_setfield(L, -2, "xMax");
    lua_pushinteger(L, face->bbox.yMax);
    lua_setfield(L, -2, "yMax");
    lua_setfield(L, idx, "bbox");
}

int newface(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    int face_index = luaL_optinteger(L, 2, 0);
    FT_Face *face = reinterpret_cast<FT_Face *>(
        lua_newuserdata(L, sizeof(FT_Face)));
    if (FT_New_Face(upvaluelibrary(L), path, face_index, face))
        luaL_error(L, "error loading face %d of %s", face_index, path);
    lua_pushvalue(L, METAFACEIDX);
    lua_setmetatable(L, -2);
    if (!FT_IS_SCALABLE((*face)))
        luaL_error(L, "error face %d of %s is not scalable", face_index, path);
    if (FT_IS_TRICKY((*face)))
        luaL_error(L, "face %d of %s is 'tricky' and not supported",
            face_index, path);
    FT_Set_Char_Size((*face), 0, 0, 0, 0); // dummy call
    lua_newtable(L);
    lua_pushvalue(L, LIBRARYIDX);
    lua_pushvalue(L, METAFACEIDX);
    luaL_setfuncs(L, methodsface, 2);
    copyfaceattribs(L, *face, -1);
    lua_setuservalue(L, -2);
    return 1;
}

static const luaL_Reg modfreetype2[] = {
    {"face", newface},
    {NULL, NULL}
};

int gclibrary(lua_State *L) {
    FT_Done_FreeType(*reinterpret_cast<FT_Library *>(lua_touserdata(L, 1)));
    return 0;
}

static void newlibrary(lua_State *L) {
    FT_Library *library = reinterpret_cast<FT_Library *>(
        lua_newuserdata(L, sizeof(FT_Library)));
    if (FT_Init_FreeType(library))
        luaL_error(L, "error loading FreeType");
    lua_newtable(L);
    lua_pushcfunction(L, gclibrary);
    lua_setfield(L, -2, "__gc");
    lua_setmetatable(L, -2);
}

extern "C"
#ifndef _WIN32
__attribute__((visibility("default")))
#else
__declspec(dllexport)
#endif
int luaopen_freetype(lua_State *L) {
    lua_newtable(L); // module
    newlibrary(L); // module library
    lua_newtable(L); // module library facemeta
    lua_pushvalue(L, -2); // module library facemeta library
    lua_pushvalue(L, -2); // module library facemeta library facemeta
    luaL_setfuncs(L, metaface, 2); // module library facemeta
    luaL_setfuncs(L, modfreetype2, 2); // module
    return 1;
}
