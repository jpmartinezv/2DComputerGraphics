local _M = { meta = {} }

local polygon_meta = _M.meta
polygon_meta.__index = {}
polygon_meta.name = "polygon"

local xform = require"xform"

-- the polygon data is an array with the coordinates of each vertex
-- { x1, y1, x2, y2, ... xn, yn }
-- it also has room for a xform to be applied to all vertices
function _M.polygon(original)
    local copy = {}
    assert(type(original) == "table", "expected table with coordinates")
    assert(#original % 2 == 0, "invalid number of coordinates in polygon")
    for i,v in ipairs(original) do
        assert(type(v) == "number", "coordinate " .. i .. " not a number")
        copy[i] = v
    end
    return setmetatable({
        type = "polygon",
        data = copy,
        xf = xform.identity()
    }, polygon_meta)
end

local function newxform(polygon, xf)
    return setmetatable({
        type = "polygon", -- shape type
        data = polygon.data,
        xf = xf,
        style = polygon.style
    }, polygon_meta)
end

function polygon_meta.__index.transform(polygon, xf)
    return newxform(polygon, xf * polygon.xf)
end

function polygon_meta.__index.translate(polygon, ...)
    return newxform(polygon, xform.translate(...) * polygon.xf)
end

function polygon_meta.__index.scale(polygon, ...)
    return newxform(polygon, xform.scale(...) * polygon.xf)
end

function polygon_meta.__index.rotate(polygon, ...)
    return newxform(polygon, xform.rotate(...) * polygon.xf)
end

function polygon_meta.__index.affine(polygon, ...)
    return newxform(polygon, xform.affine(...) * polygon.xf)
end

function polygon_meta.__index.linear(polygon, ...)
    return newxform(polygon, xform.linear(...) * polygon.xf)
end

function polygon_meta.__index.windowviewport(A, ...)
    return newxform(polygon, xform.windowviewport(...) * polygon.xf)
end

return _M
