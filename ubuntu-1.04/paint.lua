local _M = { meta = {} }

local xform = require"xform"
local color = require"color"
local vector = require"vector"
local ramp = require"ramp"
local image = require"image"
local spread = require"spread"

local paint_meta = _M.meta
paint_meta.__index = {}
paint_meta.name = "paint"

function paint_meta.__tostring(self)
    return string.format("paint{%s}", self.type)
end

-- ?? as an optimization, we should cache all solid colors
-- to prevent unecessary creation. to do that, we must cache
-- rgb colors as well

-- paints can be solid, lineargradient, radialgradient, or texture
-- all paints include a xform. this xform gives the inverse
-- mapping from scene coordinates to paint coordinates. the
-- reason we use the inverse is that the inverse gets
-- transformed by the same transformations as the shapes the
-- paints are attached to.

-- solid colors do not vary in space
-- transparency is modulated by the global opacity
function _M.solid(color, opacity)
    opacity = opacity or 1
    return setmetatable({
        type = "solid",
        data = color,
        xf = xform.identity(),
        opacity = opacity
    }, paint_meta)
end

-- a texture paint contains an image
-- this image covers the area from [0,1] x [0,1]
-- the paint color is defined by sampling the image
-- the transparency is modulated by the global opacity
-- the xf is the *inverse* of the mapping from scene coordinates
-- to texture coordinates.
-- texure coordinates are wrapped with the spread.
-- only then is the texture sampled.
function _M.texture(img, sp, xf, opacity)
    xf = xf or xform.identity()
    opacity = opacity or 1
    sp = sp or spread.pad
    assert(getmetatable(img) == image.meta, "invalid image")
    assert(getmetatable(xf) == xform.meta, "invalid transformation")
    assert(type(opacity) == "number", "invalid opacity")
    return setmetatable({
        type = "texture",
        data = {
            image = img,
            spread = sp
        },
        xf = xf,
        opacity = opacity
    }, paint_meta)
end

-- radial gradients define an offset used to sample a ramp.
-- the offset varies with the gradient point, which is obtained
-- from the scene point by applying inverse xform.
-- radial radients define a circle from center and radius
-- the ray from the focus to the gradient point intersects
-- the circle at the circle point.
-- the offset is given by the ratio between the lengths of
-- the vector connecting the focus to the gradient point and
-- the vector connecting the focus to the circle point.
-- the offset is wrapped with the spread
-- only then the ramp is sampled.
function _M.radialgradient(rmp, center, focus, radius, xf, opacity)
    xf = xf or xform.identity()
    opacity = opacity or 1
    assert(getmetatable(rmp) == ramp.meta, "invalid ramp")
    assert(getmetatable(center) == vector.meta, "invalid center")
    assert(getmetatable(focus) == vector.meta, "invalid focus")
    assert(type(radius) == "number", "invalid radius")
    assert(getmetatable(xf) == xform.meta, "invalid transformation")
    assert(type(opacity) == "number", "invalid opacity")
    return setmetatable({
        type = "radialgradient",
        data = {
            ramp = rmp,
            center = center,
            focus = focus,
            radius = radius
        },
        xf = xf,
        opacity = opacity
    }, paint_meta)
end

-- linear gradients define an offset used to sample a ramp.
-- the offset varies with the gradient point, which is obtained
-- from the scene point by applying inverse xform.
-- linear gradients define a vector from p1 to p2.
-- projection of the gradient point to the fector from p1 to p2 defines
-- a projection point.
-- the offset is the ratio of the (signed) lengths between the vector
-- connecting p1 to the projection point and the vector
-- connectin p1 to p2.
-- the offset is wrapped with the spread
-- only then the ramp is sampled.
function _M.lineargradient(rmp, p1, p2, xf, opacity)
    xf = xf or xform.identity()
    opacity = opacity or 1
    assert(getmetatable(rmp) == ramp.meta, "invalid ramp")
    assert(getmetatable(p1) == vector.meta, "invalid endpoint")
    assert(getmetatable(p2) == vector.meta, "invalid endpoint")
    assert(getmetatable(xf) == xform.meta, "invalid transformation")
    assert(type(opacity) == "number", "invalid opacity")
    return setmetatable({
        type = "lineargradient",
        data = {
            ramp = rmp,
            p1 = p1,
            p2 = p2,
        },
        xf = xf,
        opacity = opacity
    }, paint_meta)
end

local function newxform(paint, xf)
    return setmetatable({
        type = paint.type,
        data = paint.data,
        opacity = paint.opacity,
        xf = xf
    }, paint_meta)
end

function paint_meta.__index.transform(paint, xf)
    return newxform(paint, xf * paint.xf)
end

function paint_meta.__index.translate(paint, ...)
    return newxform(paint, xform.translate(...) * paint.xf)
end

function paint_meta.__index.scale(paint, ...)
    return newxform(paint, xform.scale(...) * paint.xf)
end

function paint_meta.__index.rotate(paint, ...)
    return newxform(paint, xform.rotate(...) * paint.xf)
end

function paint_meta.__index.affine(paint, ...)
    return newxform(paint, xform.affine(...) * paint.xf)
end

function paint_meta.__index.linear(paint, ...)
    return newxform(paint, xform.linear(...) * paint.xf)
end

function paint_meta.__index.windowviewport(paint, ...)
    return newxform(paint, xform.windowviewport(...) * paint.xf)
end

-- create solid paints for all named colors
_M.named = {}
for name, rgb8 in pairs(color.named) do
    _M.named[name] = _M.solid(rgb8)
end

return _M
