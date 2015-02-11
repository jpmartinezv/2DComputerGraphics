local _M = { meta = {} }

local circle_meta = _M.meta
circle_meta.__index = {}
circle_meta.name = "circle"

local xform = require"xform"
local command = require"command"
local path = require"path"

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
