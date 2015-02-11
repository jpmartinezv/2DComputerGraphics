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

local rgb8 = color.rgb8

-- named colors in SVG
_M.color = {
    aliceblue = rgb8(240,248,255),
    antiquewhite = rgb8(250,235,215),
    aqua = rgb8(0,255,255),
    aquamarine = rgb8(127,255,212),
    azure = rgb8(240,255,255),
    beige = rgb8(245,245,220),
    bisque = rgb8(255,228,196),
    black = rgb8(0,0,0),
    blanchedalmond = rgb8(255,235,205),
    blue = rgb8(0,0,255),
    blueviolet = rgb8(138,43,226),
    brown = rgb8(165,42,42),
    burlywood = rgb8(222,184,135),
    cadetblue = rgb8(95,158,160),
    chartreuse = rgb8(127,255,0),
    chocolate = rgb8(210,105,30),
    coral = rgb8(255,127,80),
    cornflowerblue = rgb8(100,149,237),
    cornsilk = rgb8(255,248,220),
    crimson = rgb8(220,20,60),
    cyan = rgb8(0,255,255),
    darkblue = rgb8(0,0,139),
    darkcyan = rgb8(0,139,139),
    darkgoldenrod = rgb8(184,134,11),
    darkgray = rgb8(169,169,169),
    darkgreen = rgb8(0,100,0),
    darkgrey = rgb8(169,169,169),
    darkkhaki = rgb8(189,183,107),
    darkmagenta = rgb8(139,0,139),
    darkolivegreen = rgb8(85,107,47),
    darkorange = rgb8(255,140,0),
    darkorchid = rgb8(153,50,204),
    darkred = rgb8(139,0,0),
    darksalmon = rgb8(233,150,122),
    darkseagreen = rgb8(143,188,143),
    darkslateblue = rgb8(72,61,139),
    darkslategray = rgb8(47,79,79),
    darkslategrey = rgb8(47,79,79),
    darkturquoise = rgb8(0,206,209),
    darkviolet = rgb8(148,0,211),
    deeppink = rgb8(255,20,147),
    deepskyblue = rgb8(0,191,255),
    dimgray = rgb8(105,105,105),
    dimgrey = rgb8(105,105,105),
    dodgerblue = rgb8(30,144,255),
    firebrick = rgb8(178,34,34),
    floralwhite = rgb8(255,250,240),
    forestgreen = rgb8(34,139,34),
    fuchsia = rgb8(255,0,255),
    gainsboro = rgb8(220,220,220),
    ghostwhite = rgb8(248,248,255),
    gold = rgb8(255,215,0),
    goldenrod = rgb8(218,165,32),
    gray = rgb8(128,128,128),
    green = rgb8(0,128,0),
    greenyellow = rgb8(173,255,47),
    grey = rgb8(128,128,128),
    honeydew = rgb8(240,255,240),
    hotpink = rgb8(255,105,180),
    indianred = rgb8(205,92,92),
    indigo = rgb8(75,0,130),
    ivory = rgb8(255,255,240),
    khaki = rgb8(240,230,140),
    lavender = rgb8(230,230,250),
    lavenderblush = rgb8(255,240,245),
    lawngreen = rgb8(124,252,0),
    lemonchiffon = rgb8(255,250,205),
    lightblue = rgb8(173,216,230),
    lightcoral = rgb8(240,128,128),
    lightcyan = rgb8(224,255,255),
    lightgoldenrodyellow = rgb8(250,250,210),
    lightgray = rgb8(211,211,211),
    lightgreen = rgb8(144,238,144),
    lightgrey = rgb8(211,211,211),
    lightpink = rgb8(255,182,193),
    lightsalmon = rgb8(255,160,122),
    lightseagreen = rgb8(32,178,170),
    lightskyblue = rgb8(135,206,250),
    lightslategray = rgb8(119,136,153),
    lightslategrey = rgb8(119,136,153),
    lightsteelblue = rgb8(176,196,222),
    lightyellow = rgb8(255,255,224),
    lime = rgb8(0,255,0),
    limegreen = rgb8(50,205,50),
    linen = rgb8(250,240,230),
    magenta = rgb8(255,0,255),
    maroon = rgb8(128,0,0),
    mediumaquamarine = rgb8(102,205,170),
    mediumblue = rgb8(0,0,205),
    mediumorchid = rgb8(186,85,211),
    mediumpurple = rgb8(147,112,219),
    mediumseagreen = rgb8(60,179,113),
    mediumslateblue = rgb8(123,104,238),
    mediumspringgreen = rgb8(0,250,154),
    mediumturquoise = rgb8(72,209,204),
    mediumvioletred = rgb8(199,21,133),
    midnightblue = rgb8(25,25,112),
    mintcream = rgb8(245,255,250),
    mistyrose = rgb8(255,228,225),
    moccasin = rgb8(255,228,181),
    navajowhite = rgb8(255,222,173),
    navy = rgb8(0,0,128),
    oldlace = rgb8(253,245,230),
    olive = rgb8(128,128,0),
    olivedrab = rgb8(107,142,35),
    orange = rgb8(255,165,0),
    orangered = rgb8(255,69,0),
    orchid = rgb8(218,112,214),
    palegoldenrod = rgb8(238,232,170),
    palegreen = rgb8(152,251,152),
    paleturquoise = rgb8(175,238,238),
    palevioletred = rgb8(219,112,147),
    papayawhip = rgb8(255,239,213),
    peachpuff = rgb8(255,218,185),
    peru = rgb8(205,133,63),
    pink = rgb8(255,192,203),
    plum = rgb8(221,160,221),
    powderblue = rgb8(176,224,230),
    purple = rgb8(128,0,128),
    red = rgb8(255,0,0),
    rosybrown = rgb8(188,143,143),
    royalblue = rgb8(65,105,225),
    saddlebrown = rgb8(139,69,19),
    salmon = rgb8(250,128,114),
    sandybrown = rgb8(244,164,96),
    seagreen = rgb8(46,139,87),
    seashell = rgb8(255,245,238),
    sienna = rgb8(160,82,45),
    silver = rgb8(192,192,192),
    skyblue = rgb8(135,206,235),
    slateblue = rgb8(106,90,205),
    slategray = rgb8(112,128,144),
    slategrey = rgb8(112,128,144),
    snow = rgb8(255,250,250),
    springgreen = rgb8(0,255,127),
    steelblue = rgb8(70,130,180),
    tan = rgb8(210,180,140),
    teal = rgb8(0,128,128),
    thistle = rgb8(216,191,216),
    tomato = rgb8(255,99,71),
    turquoise = rgb8(64,224,208),
    violet = rgb8(238,130,238),
    wheat = rgb8(245,222,179),
    white = rgb8(255,255,255),
    whitesmoke = rgb8(245,245,245),
    yellow = rgb8(255,255,0),
    yellowgreen = rgb8(154,205,50),
}

-- create solid paints for all colors
_M.color.solid = {}
for name, rgb8 in pairs(_M.color) do
    _M.color.solid[name] = _M.solid(rgb8)
end

return _M
