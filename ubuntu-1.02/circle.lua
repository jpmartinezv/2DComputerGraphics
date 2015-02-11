local _M = { meta = {} }

local circle_meta = _M.meta
circle_meta.__index = {}
circle_meta.name = "circle"

local xform = require"xform"
local command = require"command"
local path = require"path"

function _M.topath(circle)
    assert(getmetatable(circle) == circle_meta, "not a circle")
    -- we use a unit circle centered at the origin and
    -- transform it to the circle with given center and radius
    local r = circle.r
    local cx = circle.cx
    local cy = circle.cy
    -- here is the affine transformation
    local T = xform.affine(r, 0, cx, 0, r, cy)
    -- these are the control points of the unit circle
    -- mapped by the transformation. it is formed by two
    -- arcs covering each half of the circle
    local x1, y1 = T:apply(-1, 0)
    local x2, y2, w2 = T:apply(0, 1, 0)
    local x3, y3 = T:apply(1, 0)
    local x4, y4, w4 = T:apply(0, -1, 0)
    return path.path{
        command.M, x1, y1,
        command.R, x2, y2, w2, x3, y3, x4, y4, w4, x1, y1,
        command.Z
    }
end

function _M.circle(cx, cy, r)
    return setmetatable({
        type = "circle",
        cx = cx,
        cy = cy,
        r = r,
        xf = xform.identity()
    }, circle_meta)
end

local function newxform(circle, xf)
    return setmetatable({
        type = "circle",
        cx = circle.cx,
        cy = circle.cy,
        r = circle.r,
        xf = xf
    }, circle_meta)
end

function circle_meta.__index.transform(circle, xf)
    return newxform(circle, xf * circle.xf)
end

function circle_meta.__index.translate(circle, ...)
    return newxform(circle, xform.translate(...) * circle.xf)
end

function circle_meta.__index.scale(circle, ...)
    return newxform(circle, xform.scale(...) * circle.xf)
end

function circle_meta.__index.rotate(circle, ...)
    return newxform(circle, xform.rotate(...) * circle.xf)
end

function circle_meta.__index.affine(circle, ...)
    return newxform(circle, xform.affine(...) * circle.xf)
end

function circle_meta.__index.linear(circle, ...)
    return newxform(circle, xform.linear(...) * circle.xf)
end

function circle_meta.__index.windowviewport(circle, ...)
    return newxform(circle, xform.windowviewport(...) * circle.xf)
end

return _M
