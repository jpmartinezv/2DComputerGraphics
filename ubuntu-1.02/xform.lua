local _M = require"delay.xform"
local vector = require"delay.vector"
local overload = require"overload"
local window = require"window"
local viewport = require"viewport"

local xform_meta = _M.meta
xform_meta.__index = {}
xform_meta.name = "xform"

local EPS = 1.17549435E-38
local unpack = table.unpack

function xform_meta.__call(A, i, j)
    return A[(i-1)*3+(j-1)+1]
end

function xform_meta.__eq(m, n)
    if getmetatable(m) ~= xform_meta or getmetatable(n) ~= xform_meta then
        return false
    end
    for i = 1, 9 do
        if math.abs(m[i]-n[i]) > EPS then
            return false
        end
    end
    return true
end

function xform_meta.__tostring(m)
    return string.format("xform{%f,%f,%f,%f,%f,%f,%f,%f,%f}",
        m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9])
end

xform_meta.__add = overload.handler("__add")

overload.register("__add", function(A, B)
    local m = {0, 0, 0, 0, 0, 0, 0, 0, 0}
    for i=1,9 do
        m[i] = A[i] + B[i]
    end
    return setmetatable(m, xform_meta)
end, xform_meta, xform_meta)

function xform_meta.__unm(A)
    return _M.scale(-1) * A
end

xform_meta.__mul = overload.handler("__mul")

overload.register("__mul", function(s, A)
    return _M.scale(s) * A
end, "number", xform_meta)

overload.register("__mul", function(A, s)
    return A * _M.scale(s)
end, xform_meta, "number")

overload.register("__mul", function(A, B)
    local m = {0, 0, 0, 0, 0, 0, 0, 0, 0}
    for i=0,2 do
        for j=0,2 do
            local s = 0
            for k = 0, 2 do
                s = s + A[i*3+k+1]*B[k*3+j+1]
            end
            m[i*3+j+1] = s
        end
    end
    return setmetatable(m, xform_meta)
end, xform_meta, xform_meta)

overload.register("__mul", function(A, u)
    local v = {0, 0, 0}
    for i=0,2 do
        local s = 0
        for k = 0, 2 do
            s = s + A[i*3+k+1]*u[k+1]
        end
        v[i+1] = s
    end
    return setmetatable(v, vector.meta)
end, xform_meta, vector.meta)

function xform_meta.__index.apply(A, x, y, w)
    w = w or 1
    local ax = A[0*3+0+1]*x + A[0*3+1+1]*y + A[0*3+2+1]*w
    local ay = A[1*3+0+1]*x + A[1*3+1+1]*y + A[1*3+2+1]*w
    local aw = A[2*3+0+1]*x + A[2*3+1+1]*y + A[2*3+2+1]*w
    return ax, ay, aw
end

function xform_meta.__index.inversedet(A)
    local a, b, c, d, e, f, g, h, i = unpack(A, 1, 9)
    return setmetatable({
        -f*h + e*i, c*h - b*i,-c*e + b*f,
         f*g - d*i,-c*g + a*i, c*d - a*f,
        -e*g + d*h, b*g - a*h,-b*d + a*e
    }, xform_meta), -c*e*g + b*f*g + c*d*h - a*f*h - b*d*i + a*e*i
end

function xform_meta.__index.transpose(A)
    local a, b, c, d, e, f, g, h, i = unpack(A, 1, 9)
    return setmetatable({
        a, d, g,
        b, e, h,
        c, f, i
    }, xform_meta)
end

function xform_meta.__index.inverse(A)
    local a, b, c, d, e, f, g, h, i = unpack(A, 1, 9)
    local inv_det = -c*e*g + b*f*g + c*d*h - a*f*h - b*d*i + a*e*i
    assert(math.abs(inv_det) > EPS, "singular")
    inv_det = 1.0/inv_det
    return setmetatable({
        inv_det*(-f*h + e*i),inv_det*( c*h - b*i),inv_det*(-c*e + b*f),
        inv_det*( f*g - d*i),inv_det*(-c*g + a*i),inv_det*( c*d - a*f),
        inv_det*(-e*g + d*h),inv_det*( b*g - a*h),inv_det*(-b*d + a*e)
    }, xform_meta)
end

function xform_meta.__index.det(A)
    local a, b, c, d, e, f, g, h, i = unpack(A, 1, 9)
    return -c*e*g + b*f*g + c*d*h - a*f*h - b*d*i + a*e*i
end

function xform_meta.__index.issymmetric(A)
    for i = 0, 2 do
        for j = i, 2 do
            if math.abs(A[i*3+j+1]-A[j*3+i+1]) > EPS then
                return false
            end
        end
    end
    return true
end

function xform_meta.__index.translate(A, ...)
    return _M.translate(...) * A
end

function xform_meta.__index.scale(A, ...)
    return _M.scale(...) * A
end

function xform_meta.__index.rotate(A, ...)
    return _M.rotate(...) * A
end

function xform_meta.__index.affine(A, ...)
    return _M.affine(...) * A
end

function xform_meta.__index.linear(A, ...)
    return _M.linear(...) * A
end

function xform_meta.__index.xform(A, ...)
    return _M.xform(...) * A
end

function xform_meta.__index.windowviewport(A, ...)
    return _M.windowviewport(...) * A
end

local I = setmetatable({1,0,0,0,1,0,0,0,1}, xform_meta)

function _M.rotate(a_or_c, s)
    assert(type(a_or_c) == "number")
    if not s then
        a_or_c = math.rad(a_or_c)
        s = math.sin(a_or_c)
        a_or_c = math.cos(a_or_c)
    end
    assert(type(s) == "number")
    return setmetatable(
        {a_or_c, -s, 0, s, a_or_c, 0, 0, 0, 1},
        xform_meta
    )
end

function _M.scale(sx, sy_or_nil)
    assert(type(sx) == "number")
    local sy = sy_or_nil or sx
    return setmetatable(
        {sx, 0, 0, 0, sy, 0, 0, 0, 1},
        xform_meta
    )
end

function _M.xform(a11, a12, a13, a21, a22, a23, a31, a32, a33)
    assert(type(a11) == "number")
    assert(type(a12) == "number")
    assert(type(a13) == "number")
    assert(type(a21) == "number")
    assert(type(a22) == "number")
    assert(type(a23) == "number")
    assert(type(a31) == "number")
    assert(type(a32) == "number")
    assert(type(a33) == "number")
    return setmetatable(
        {a11, a12, a13, a21, a22, a23, a31, a32, a33},
        xform_meta
    )
end

function _M.affine(a11, a12, a13, a21, a22, a23)
    assert(type(a11) == "number")
    assert(type(a12) == "number")
    assert(type(a13) == "number")
    assert(type(a21) == "number")
    assert(type(a22) == "number")
    assert(type(a23) == "number")
    return setmetatable(
        {a11, a12, a13, a21, a22, a23, 0, 0, 1},
        xform_meta
    )
end

function _M.linear(a11, a12, a21, a22)
    assert(type(a11) == "number")
    assert(type(a12) == "number")
    assert(type(a21) == "number")
    assert(type(a22) == "number")
    return setmetatable(
        {a11, a12, 0, a21, a22, 0, 0, 0, 1},
        xform_meta
    )
end

function _M.translate(tx, ty)
    assert(type(tx) == "number")
    ty = ty or 0
    assert(type(ty) == "number")
    return setmetatable(
        {1, 0, tx, 0, 1, ty, 0, 0, 1},
        xform_meta
    )
end

function _M.identity(...)
    assert(select('#', ...) == 0, "too many arguments")
    return I
end

function _M.windowviewport(w, v)
    assert(getmetatable(w) == window.meta, "expected window")
    assert(getmetatable(v) == viewport.meta, "expected viewport")
    local wxmin, wymin, wxmax, wymax = unpack(w, 1, 4)
    local wxmed, wymed = .5*(wxmin+wxmax), .5*(wymin+wymax)
    local wdx, wdy = wxmax-wxmin, wymax-wymin
    local vxmin, vymin, vxmax, vymax = unpack(v, 1, 4)
    local vxmed, vymed = .5*(vxmin+vxmax), .5*(vymin+vymax)
    local vdx, vdy = vxmax-vxmin, vymax-vymin
    return _M.translate(vxmed, vymed) *
           _M.scale(vdx/wdx, vdy/wdy) *
           _M.translate(-wxmed, -wymed)
end

return _M
