local _M = { meta = {} }

local triangle_meta = _M.meta
triangle_meta.__index = {}
triangle_meta.name = "triangle"

local xform = require"xform"

-- a triangle is given by its three vertices in the obvious way
-- it also holds a xform to be applied to all vertices
function _M.triangle(x1, y1, x2, y2, x3, y3)
    return setmetatable({
        type = "triangle",
        xf = xform.identity(),
        x1 = x1, y1 = y1,
        x2 = x2, y2 = y2,
        x3 = x3, y3 = y3,
    }, triangle_meta)
end

local function newxform(triangle, xf)
    return setmetatable({
        type = "triangle", -- shape type
        x1 = triangle.x1, y1 = triangle.y1,
        x2 = triangle.x2, y2 = triangle.y2,
        x3 = triangle.x3, y3 = triangle.y3,
        xf = xf,
        style = triangle.style
    }, triangle_meta)
end

function triangle_meta.__index.transform(triangle, xf)
    return newxform(triangle, xf * triangle.xf)
end

function triangle_meta.__index.translate(triangle, ...)
    return newxform(triangle, xform.translate(...) * triangle.xf)
end

function triangle_meta.__index.scale(triangle, ...)
    return newxform(triangle, xform.scale(...) * triangle.xf)
end

function triangle_meta.__index.rotate(triangle, ...)
    return newxform(triangle, xform.rotate(...) * triangle.xf)
end

function triangle_meta.__index.affine(triangle, ...)
    return newxform(triangle, xform.affine(...) * triangle.xf)
end

function triangle_meta.__index.linear(triangle, ...)
    return newxform(triangle, xform.linear(...) * triangle.xf)
end

function triangle_meta.__index.windowviewport(triangle, ...)
    return newxform(triangle, xform.windowviewport(...) * triangle.xf)
end

return _M
