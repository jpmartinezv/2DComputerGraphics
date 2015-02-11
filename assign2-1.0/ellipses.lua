local _M = { meta = {} }

local conic_meta = _M.meta
conic_meta.__index = {}
conic_meta.name = "conic"

local xform = require"xform"

function _M.rotateconic(m, alpha)
    local c = math.cos(-alpha)
    local s = math.sin(-alpha)
    local ir = xform.xform(c, -s, 0, s, c, 0, 0, 0, 1)
    return ir:transpose() * m * ir
end

function _M.translateconic(m, tx, ty)
    local it = xform.xform(1, 0, -tx, 0, 1, -ty, 0, 0, 1)
    return it:transpose() * m * it
end

function _M.scaleconic(m, sx, sy)
    local is = xform.xform(1.0/sx, 0, 0, 0, 1.0/sy, 0, 0, 0, 1)
    return is:transpose() * m * is
end

return _M

