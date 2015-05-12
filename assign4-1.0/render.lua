local driver = require"driver"
local image = require"image"
local chronos = require"chronos"

local solve = {}
solve.quadratic = require"quadratic"
solve.cubic = require"cubic"

local sqrt = math.sqrt
local min = math.min
local max = math.max
local unpack = table.unpack
local floor = math.floor
local abs = math.abs

-- output formatted string to stderr
local function stderr(...)
    io.stderr:write(string.format(...))
end

local FLT_MIN = 1.17549435E-38 -- smallest-magnitude normalized single-precision
local TOL = 0.01 -- root-finding tolerance, in pixels
local MAX_ITER = 30 -- maximum number of bisection iterations in root-finding
local MAX_DEPTH = 8 -- maximum quadtree depth

local _M = driver.new()

-- here are functions to cut a rational quadratic Bezier
-- you can write your own functions to cut lines,
-- integral quadratics, and cubics

-- linear interpolation
local function lerp(x0, x1, a)
    local a1 = 1-a
    return a1*x0+a*x1
end

-- quadratic interpolation
local function lerp2(x0, x1, x2, a, b)
    local x00 = lerp(x0, x1, a)
    local x01 = lerp(x1, x2, a)
    return lerp(x00, x01, b)
end

-- cubic interpolation
local function lerp3(x0, x1, x2, x3, a, b)
    local x00 = lerp2(x0, x1, x2, a, a)
    local x01 = lerp2(x1, x2, x3, a, a)
    return lerp(x00, x01, b)
end

-- cut canonic rational quadratic segment and recanonize
local function cutr2s(a, b, x0, y0, x1, y1, w1, x2, y2)
    local u0 = lerp2(x0, x1, x2, a, a)
    local v0 = lerp2(y0, y1, y2, a, a)
    local r0 = lerp2(1, w1, 1, a, a)
    local u1 = lerp2(x0, x1, x2, a, b)
    local v1 = lerp2(y0, y1, y2, a, b)
    local r1 = lerp2(1, w1, 1, a, b)
    local u2 = lerp2(x0, x1, x2, b, b)
    local v2 = lerp2(y0, y1, y2, b, b)
    local r2 = lerp2(1, w1, 1, b, b)
    local ir0, ir2 = 1/r0, 1/r2
    assert(ir0*ir2 >= 0, "canonization requires split!")
    local ir1 = sqrt(ir0*ir2)
    return u0*ir0, v0*ir0, u1*ir1, v1*ir1, r1*ir1, u2*ir2, v2*ir2
end

-- cut linear segment
local function cut1s(a, b, x0, y0, x1, y1)
    local u0 = lerp(x0, x1, a)
    local v0 = lerp(y0, y1, a)
    local u1 = lerp(x0, x1, b)
    local v2 = lerp(y0, y1, b)
    return u0, v0, u1, v2
end

-- cut quadratic segment
local function cut2s(a, b, x0, y0, x1, y1, x2, y2)
    local u0 = lerp2(x0, x1, x2, a, a)
    local v0 = lerp2(y0, y1, y2, a, a)
    local u1 = lerp2(x0, x1, x2, a, b)
    local v1 = lerp2(y0, y1, y2, a, b)
    local u2 = lerp2(x0, x1, x2, b, b)
    local v2 = lerp2(y0, y1, y2, b, b)
    return u0, v0, u1, v1, u2, v2
end

-- cut cubic segment
local function cut3s(a, b, x0, y0, x1, y1, x2, y2, x3, y3)
    local u0 = lerp3(x0, x1, x2, x3, a, a)
    local v0 = lerp3(y0, y1, y2, y3, a, a)
    local u1 = lerp3(x0, x1, x2, x3, a, b)
    local v1 = lerp3(y0, y1, y2, y3, a, b)
    local u2 = lerp3(x0, x1, x2, x3, b, a)
    local v2 = lerp3(y0, y1, y2, y3, b, a)
    local u3 = lerp3(x0, x1, x2, x3, b, b)
    local v3 = lerp3(y0, y1, y2, y3, b, b)
    return u0, v0, u1, v1, u2, v2, u3, v3
end

-- here are functions to find a root in a rational quadratic
-- you can write your own functions to find roots for lines,
-- integral quadratics, and cubics

-- assumes monotonic and x0 <= 0 <= x2
local function recursivebisectrationalquadratic(x0, x1, w1, x2, ta, tb, n)
    local tm = 0.5*(ta+tb)
    local xm = lerp2(x0, x1, x2, tm, tm)
    local wm = lerp2(1, w1, 1, tm, tm)
    if abs(xm) < TOL*abs(wm) or n >= MAX_ITER then
        return tm
    else
        n = n + 1
        if (wm < 0) ~= (xm < 0) then ta = tm
        else tb = tm end
        -- tail call
        return recursivebisectrationalquadratic(x0, x1, w1, x2, ta, tb, n)
    end
end

-- assumes monotonic and root in [0, 1]
local function bisectrationalquadratic(x0, x1, w1, x2)
    -- ensure root is bracketed by [0,1]
    assert(x2*x0 <= 0, "no root in interval!")
    -- reorder segment so it is increasing
    if x0 > x2 then
        return 1-recursivebisectrationalquadratic(x2, x1, w1, x0, 0, 1, 0)
    else
        return recursivebisectrationalquadratic(x0, x1, w1, x2, 0, 1, 0)
    end
end

local function recursivebisectlinear(x0, x1, ta, tb, n)
    local tm = 0.5 * (ta + tb)
    local xm = lerp(x0, x1, tm)

    if abs(xm) < TOL or n >= MAX_ITER then
        return tm
    else
        n = n + 1
        if xm < x then ta = tm
        else tb = tm end
        return recursivebisectlinear(x0, x1, ta, tb, n)
    end
end

local function bisectlinear(x0, x1)
    assert(x1*x0 <= 0, "no root in interval!")
    if x0 > x1 then
        return 1 - recursivebisectlinear(x1, x0, x, 0, 1, 0)
    else
        return recursivebisectlinear(x0, x1, x, 0, 1, 0)
    end
end

-- assumes monotonic and x0 <= 0 <= x2
local function recursivebisectquadratic(x0, x1, x2, ta, tb, n)
    local tm = 0.5*(ta+tb)
    local xm = lerp2(x0, x1, x2, tm, tm)
    if abs(xm) < TOL or n >= MAX_ITER then
        return tm
    else
        n = n + 1
        if (xm < 0) then ta = tm
        else tb = tm end
        -- tail call
        return recursivebisectquadratic(x0, x1, x2, ta, tb, n)
    end
end

-- assumes monotonic and root in [0, 1]
local function bisectquadratic(x0, x1, x2)
    -- ensure root is bracketed by [0,1]
    assert(x2*x0 <= 0, "no root in interval!")
    -- reorder segment so it is increasing
    if x0 > x2 then
        return 1-recursivebisectquadratic(x2, x1, x0, 0, 1, 0)
    else
        return recursivebisectquadratic(x0, x1, x2, 0, 1, 0)
    end
end

-- assumes monotonic and x0 <= 0 <= x3
local function recursivebisectcubic(x0, x1, x2, x3, ta, tb, n)
    local tm = 0.5*(ta+tb)
    local xm = lerp3(x0, x1, x2, x3, tm, tm)
    if abs(xm) < TOL or n >= MAX_ITER then
        return tm
    else
        n = n + 1
        if (xm < 0) then ta = tm
        else tb = tm end
        -- tail call
        return recursivebisectcubic(x0, x1, x2, x3, ta, tb, n)
    end
end

-- assumes monotonic and root in [0, 1]
local function bisectcubic(x0, x1, x2, x3)
    -- ensure root is bracketed by [0,1]
    assert(x3*x0 <= 0, "no root in interval!")
    -- reorder segment so it is increasing
    if x0 > x3 then
        return 1-recursivebisectcubic(x3, x2, x1, x0, 0, 1, 0)
    else
        return recursivebisectcubic(x0, x1, x2, x3, 0, 1, 0)
    end
end


-- transforms path by xf and ensures it is closed by a final segment
local function newxformer(xf, forward)
    local fx, fy -- first contour cursor
    local px, py -- previous cursor
    local xformer = {}
    function xformer:begin_closed_contour(len, x0, y0)
        fx, fy = xf:apply(x0, y0)
        forward:begin_closed_contour(_, fx, fy)
        px, py = fx, fy
    end
    xformer.begin_open_contour = xformer.begin_closed_contour
    function xformer:end_closed_contour(len)
        if px ~= fx or py ~= fy then
            forward:linear_segment(px, py, fx, fy)
        end
        forward:end_closed_contour(_)
    end
    xformer.end_open_contour = xformer.end_closed_contour
    function xformer:linear_segment(x0, y0, x1, y1)
        x1, y1 = xf:apply(x1, y1)
        forward:linear_segment(px, py, x1, y1)
        px, py = x1, y1
    end
    function xformer:quadratic_segment(x0, y0, x1, y1, x2, y2)
        x1, y1 = xf:apply(x1, y1)
        x2, y2 = xf:apply(x2, y2)
        forward:quadratic_segment(px, py, x1, y1, x2, y2)
        px, py = x2, y2
    end
    function xformer:rational_quadratic_segment(x0, y0, x1, y1, w1, x2, y2)
        x1, y1, w1 = xf:apply(x1, y1, w1)
        x2, y2 = xf:apply(x2, y2)
        assert(w1 > FLT_MIN, "unbounded rational quadratic segment")
        forward:rational_quadratic_segment(px, py, x1, y1, w1, x2, y2)
        px, py = x2, y2
    end
    function xformer:cubic_segment(x0, y0, x1, y1, x2, y2, x3, y3)
        x1, y1 = xf:apply(x1, y1)
        x2, y2 = xf:apply(x2, y2)
        x3, y3 = xf:apply(x3, y3)
        forward:cubic_segment(px, py, x1, y1, x2, y2, x3, y3)
        px, py = x3, y3
    end
    return xformer
end

-- remove segments that degenerate to points
-- should be improved to remove "almost" points
-- assumes segments are monotonic
local function newcleaner(forward)
    local cleaner = {}
    function cleaner:begin_closed_contour(len, x0, y0)
        forward:begin_closed_contour(_, x0, y0)
    end
    cleaner.begin_open_contour = cleaner.begin_closed_contour
    function cleaner:linear_segment(x0, y0, x1, y1)
        if x0 ~= x1 or y0 ~= y1 then
            forward:linear_segment(px, py, x1, y1)
        end
    end
    function cleaner:quadratic_segment(x0, y0, x1, y1, x2, y2)
        if x0 ~= x2 or y0 ~= y2 then
            forward:quadratic_segment(x0, y0, x1, y1, x2, y2)
        end
    end
    function cleaner:rational_quadratic_segment(x0, y0, x1, y1, w1, x2, y2)
        if x0 ~= x2 or y0 ~= y2 then
            if abs(w1-1) > FLT_MIN then
                forward:rational_quadratic_segment(x0, y0, x1, y1, w1, x2, y2)
            else
                forward:quadratic_segment(x0, y0, x1, y1, x2, y2)
            end
        end
    end
    function cleaner:cubic_segment(x0, y0, x1, y1, x2, y2, x3, y3)
        if x0 ~= x3 or y0 ~= y3 then
            forward:cubic_segment(x0, y0, x1, y1, x2, y2, x3, y3)
        end
    end
    function cleaner:end_closed_contour(len)
        forward:end_closed_contour(_)
    end
    cleaner.end_open_contour = cleaner.end_closed_contour
    return cleaner
end

-- transform segments to monotonic segments
function newmonotonizer(forward)
    local monotonizer = {}

    function monotonizer:begin_closed_contour(len, x0, y0)
        forward:begin_closed_contour(_, x0, y0)
    end
    monotonizer.begin_open_contour = monotonizer.begin_closed_contour
    function monotonizer:linear_segment(x0, y0, x1, y1)
        if x0 ~= x1 or y0 ~= y1 then
            forward:linear_segment(px, py, x1, y1)
        end
    end
    function monotonizer:quadratic_segment(x0, y0, x1, y1, x2, y2)
        if x0 ~= x2 or y0 ~= y2 then
            function solve_extreme(b0, b1, b2, t)
                if b0 + b2 == 2*b1 then return end
                local t1 = (b0 - b1)/(b0 - 2*b1 + b2)
                if 0 < t1 and t1 < 1 then t[#t + 1] = t1  end
            end
            local t = {0, 1}
            solve_extreme(x0, x1, x2, t)
            solve_extreme(y0, y1, y2, t)
            table.sort(t)

            for i = 2, #t do 
                forward:quadratic_segment(cut2s(t[i-1], t[i], x0, y0, x1, y1, x2, y2))
            end

        end
    end
    function monotonizer:rational_quadratic_segment(x0, y0, x1, y1, w1, x2, y2)
        if x0 ~= x2 or y0 ~= y2 then
            function solve_extreme(b0, b1, b2, w, t)
                local a = (w - 1)*(b0 - b2)
                local b = b0 - 2*b0*w + 2*b1 - b2                   
                local c = w*b0 - b1
                local n, r1, s1, r2, s2 = solve.quadratic.quadratic(a, b, c)
                if n == 0 then return end
                local t1, t2 = r1/s1, r2/s2
                if 0 < t1 and t1 < 1 then t[#t + 1] = t1 end
                if 0 < t2 and t2 < 1 then t[#t + 1] = t2 end
            end

            local t = {0, 1}
            solve_extreme(x0, x1, x2, w1, t)
            solve_extreme(y0, y1, y2, w1, t)

            table.sort(t)
            for i = 2, #t do 
                forward:rational_quadratic_segment(cutr2s(t[i-1], t[i], x0, y0, x1, y1, w1, x2, y2))
            end
        end
    end
    function monotonizer:cubic_segment(x0, y0, x1, y1, x2, y2, x3, y3)
        if x0 ~= x3 or y0 ~= y3 then
            function solve_extreme(z0, z1, z2,z3, t)
                local a = 3 * ( -z0 + 3*z1 - 3*z2 + z3 )
                local b = 2 * ( 3*z0 - 6*z1 + 3*z2 )
                local c = 3 * ( -z0 + z1 )
                local n, r1, s1, r2, s2 = solve.quadratic.quadratic(a, b, c)
                if n == 0 then return end
                local t1, t2 = r1/s1, r2/s2
                if 0 < t1 and t1 < 1 then t[#t + 1] = t1 end
                if 0 < t2 and t2 < 1 then t[#t + 1] = t2 end
            end
            local t = {0,1}
            solve_extreme(x0, x1, x2, x3, t)
            solve_extreme(y0, y1, y2, y3, t)
            table.sort(t)

            for i = 2, #t do 
                forward:cubic_segment(cut3s(t[i-1], t[i], x0, y0, x1, y1, x2, y2, x3, y3))
            end
        end
    end
    function monotonizer:end_closed_contour(len)
        forward:end_closed_contour(_)
    end
    monotonizer.end_open_contour = monotonizer.end_closed_contour
    return monotonizer
end

-- here is a function that returns a path transformed to
-- pixel coordinates using the iterator trick I talked about
-- you should chain your own implementation of monotonization!
-- if you don't do that, your life will be *much* harder
function transformpath(oldpath, xf)
    local newpath = _M.path()
    newpath:open()
    oldpath:iterate(
    newxformer(xf * oldpath.xf,
    newmonotonizer(
    newcleaner(
    newpath))))
    newpath:close()
    return newpath
end

-- Prepare paint

local function angleuv(vx, vy, ux, uy)
    if vx == ux and vy == uy then return 0 end
    local theta = math.atan((uy-vy)/(ux-vx))
    if (ux-vx) < 0 then
        return theta + math.pi
    end
    return theta
end

local prepare = {}

function prepare.solid(paint, xf)
end

function prepare.lineargradient(paint, xf)
    local data = paint.data
    local theta = angleuv(data.p1[1], data.p1[2], data.p2[1], data.p2[2])
    local c = math.cos(-theta)
    local s = math.sin(-theta)
    local dx = sqrt((data.p1[1] - data.p2[1])*(data.p1[1] - data.p2[1]) +
    (data.p1[2] - data.p2[2])*(data.p1[2] - data.p2[2]))

    local rl = _M.xform(c, -s, 0, s, c, 0, 0, 0, 1)
    local tl = _M.xform(1, 0, -data.p1[1], 0, 1, -data.p1[2], 0, 0, 1)
    local sl = _M.xform(1/dx, 0, 0, 0, 1, 0, 0, 0, 1)

    paint.T = sl* rl* tl * (xf*paint.xf):inverse()

end

function prepare.radialgradient(paint, xf)
    local data = paint.data
    local theta = angleuv(data.focus[1], data.focus[2], data.center[1], data.center[2])
    local c = math.cos(-theta)
    local s = math.sin(-theta)

    local rl = _M.xform(c, -s, 0, s, c, 0, 0, 0, 1)
    local tl = _M.xform(1, 0, -data.focus[1], 0, 1, -data.focus[2], 0, 0, 1)

    local m = rl * tl

    data.cx, data.cy = m:apply(data.center[1], data.center[2])
    data.fx, data.fy = m:apply(data.focus[1], data.focus[2])

    paint.T = m * (xf*paint.xf):inverse()
end

-- prepare scene for sampling and return modified scene
local function preparescene(scene)
    -- implement
    -- (feel free to use the transformpath function above)
    for i, element in ipairs(scene.elements) do
        prepare[element.paint.type](element.paint, scene.xf) 
        element.shape = transformpath(element.shape, scene.xf)
    end
    scene.xf = _M.identity()
    return scene
end

-- override circle creation function and return a path instead
function _M.circle(cx, cy, r)
    -- we start with a unit circle centered at the origin
    -- it is formed by 3 arcs covering each third of the unit circle
    local s = 0.5           -- sin(pi/6)
    local c = 0.86602540378 -- cos(pi/6)
    local w = s
    return _M.path{
        _M.M,  0,  1,
        _M.R, -c,  s,  w, -c, -s,
        _M.R,  0, -1,  w,  c, -s,
        _M.R,  c,  s,  w,  0,  1,
        _M.Z
        -- transform it to the circle with given center and radius
    }:scale(r, r):translate(cx, cy)
end

-- override triangle creation and return a path instead
function _M.triangle(x1, y1, x2, y2, x3, y3)
    -- implement
    return _M.path{
        _M.M, x1, y1,
        _M.L, x2, y2,
        _M.L, x3, y3,
        _M.Z
    }
end

-- override polygon creation and return a path instead
function _M.polygon(data)
    -- implement
    local  content = { _M.M, data[1], data[2]}
    local j = 1
    for i = 3, #data, 2 do
        content[3*j + 1] = _M.L
        content[3*j + 2] = data[i]
        content[3*j + 3] = data[i+1]
        j = j + 1
    end
    content[3*j+1] = _M.Z

    return _M.path{unpack(content)}
end

-- verifies that there is nothing unsupported in the scene
-- note that we only support paths!
-- triangles, circles, and polygons were overriden
local function checkscene(scene)
    for i, element in ipairs(scene.elements) do
        assert(element.type == "fill" or element.type == "eofill")
        assert(element.shape.type == "path", "unsuported primitive")
        assert(element.paint.type == "solid" or
        element.paint.type == "lineargradient" or
        element.paint.type == "radialgradient" or
        element.paint.type == "texture",
        "unsupported paint")
    end
end

local checkinside = {}

function checkinside.linear(x0, y0, x1, y1, x, y)
    local t = (y-y0)/(y1-y0)
    local u = lerp(x0,x1,t) - x
    if abs(u) < TOL then return 0 end

    if y1 > y0 then
        if 0 <= t and t < 1 and u > 0 then return 1 end
    elseif y1 < y0 then
        if 0 < t and t <= 1 and u > 0 then return -1 end
    end
    return 0
end

function checkinside.quadratic(x0, y0, x1, y1, x2, y2, x, y)
    if y0 <= y2 and (y < y0 or y2 <= y) then return 0 end
    if y0 >= y2 and (y >= y0 or y2 > y) then return 0 end

    local t = bisectquadratic(y0 - y, y1 - y, y2 - y)
    local u = lerp2(x0, x1, x2, t, t) - x
    if y0 < y2 then 
        if 0 <= t and t < 1 and u > 0 then return 1 end
    elseif y0 > y2 then
        if 0 < t and t <= 1 and  u > 0 then return -1 end
    end
    return 0
end

function checkinside.cubic(x0, y0, x1, y1, x2, y2, x3, y3, x, y)
    if y0 <= y3 and (y < y0 or y3 <= y) then return 0 end
    if y0 >= y3 and (y >= y0 or y3 > y) then return 0 end

    local t = bisectcubic(y0 - y, y1 - y, y2 - y, y3 - y)
    local u = lerp3(x0, x1, x2, x3, t, t) - x
    if y0 < y3 then 
        if 0 <= t and t < 1 and u > 0 then return 1 end
    elseif y0 > y3 then
        if 0 < t and t <= 1 and  u > 0 then return -1 end
    end
    return 0
end

function checkinside.rational_quadratic(x0, y0, x1, y1, w1, x2, y2, x, y)
    if y0 <= y2 and (y < y0 or y2 <= y) then return 0 end
    if y0 >= y2 and (y >= y0 or y2 > y) then return 0 end
    local t = bisectrationalquadratic(y0 - y, y1 - y*w1, w1, y2 - y)
    local u = lerp2(x0, x1, x2, t, t)/lerp2(1, w1, 1, t, t) - x
    if y0 < y2 then 
        if 0 <= t and t < 1 and u > 0 then return 1 end
    elseif y0 > y2 then
        if 0 < t and t <= 1 and  u > 0 then return -1 end
    end
    return 0
end

local rvgcommand = {
    begin_open_contour = "M",
    begin_closed_contour = "M",
    linear_segment = "L",
    quadratic_segment = "Q",
    rational_quadratic_segment = "A",
    cubic_segment = "C",
    end_closed_contour = "Z",
}

local getcolor = {}

function getcolor.solid(paint, x, y)
    return unpack(paint.data)
end

function getcolor.lineargradient(paint, x0, y0)
    local p, q = paint.T:apply(x0, y0)
    local ramp = paint.data.ramp
    local n = #ramp

    if p < 0 then
        return unpack(paint.data.ramp[2])
    elseif p > 1 then
        return unpack(paint.data.ramp[n])
    end

    local r, g, b, a
    for i=1, n-2, 2 do
        if ramp[i] <= p and p <= ramp[i+2] then
            r = (ramp[i+3][1]*(p-ramp[i]) + ramp[i+1][1]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            g = (ramp[i+3][2]*(p-ramp[i]) + ramp[i+1][2]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            b = (ramp[i+3][3]*(p-ramp[i]) + ramp[i+1][3]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            a = (ramp[i+3][4]*(p-ramp[i]) + ramp[i+1][4]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            return r,g,b,a 
        end
    end

    return 1,1,1,1 
end

function getcolor.radialgradient(paint, x0, y0)
    local data = paint.data
    local ramp = paint.data.ramp
    local n = #ramp

    x0, y0 = paint.T:apply(x0, y0)

    local a = (1.0 + (x0/y0)^2)
    local b = -2*data.cx*x0/y0
    local c = data.cx*data.cx - data.radius*data.radius

    local m,t1,s1,t2,s2 = solve.quadratic.quadratic(a,b,c)

    local x1, y1
    if y0 > 0 then
        y1 = t1/s1
        x1 = y1*x0/y0
    else
        y1 = t2/s2
        x1 = y1*x0/y0
    end
    local dp = sqrt(x0 * x0 + y0 * y0)
    local d = sqrt(x1 * x1 + y1 * y1)

    if dp > d then return unpack(paint.data.ramp[n]) end
    local p = dp/d

    local r, g, b, a
    for i=1, n-2, 2 do
        if ramp[i] <= p and p < ramp[i+2] then
            r = (ramp[i+3][1]*(p-ramp[i]) + ramp[i+1][1]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            g = (ramp[i+3][2]*(p-ramp[i]) + ramp[i+1][2]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            b = (ramp[i+3][3]*(p-ramp[i]) + ramp[i+1][3]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            a = (ramp[i+3][4]*(p-ramp[i]) + ramp[i+1][4]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            return r,g,b,a
        end
    end

    return 1,1,1,1
end

function getleaf(quadtree, xmin, ymin, xmax, ymax, x, y)
    if not quadtree.children then return quadtree end

    local xm = 0.5*(xmin + xmax)
    local ym = 0.5*(ymin + ymax)

    if xmin <= x and x < xm and ymin <= y and y < ym then
        return getleaf(quadtree.children[1], xmin, ymin, xm, ym, x, y)
    elseif xm <= x and x < xmax and ymin <= y and y < ym then
        return getleaf(quadtree.children[2], xm, ymin, xmax, ym, x, y)
    elseif xmin <= x and x < xm and ym <= y and y < ymax then
        return getleaf(quadtree.children[3], xmin, ym, xm, ymax, x, y)
    elseif xm <= x and x < xmax and ym <= y and y < ymax then
        return getleaf(quadtree.children[4], xm, ym, xmax, ymax, x, y)
    end
end


-- descend on quadtree, find leaf containing x,y, use leaf
-- to evaluate the color, and finally return r,g,b,a
local function sample(quadtree, xmin, ymin, xmax, ymax, x, y)
    -- implement
    local Cr = 1.0
    local Cg = 1.0
    local Cb = 1.0
    local alpha = 1.0

    local r, g, b, a 
    local scene = getleaf(quadtree, xmin, ymin, xmax, ymax, x, y)

    for i,element in ipairs(scene.elements) do
        local data = element.shape.data
        local px, py
        local fx, fy
        local ni = 0
        local n = #element.shape.instructions
        for j=1, n do
            local o = element.shape.offsets[j]
            local s = rvgcommand[element.shape.instructions[j]]
            if s == "M" then
                px, py = data[o+1], data[o+2]
                fx, fy = px, py
            elseif s == "Z" then
                ni = ni + checkinside.linear(px, py, fx, fy, x, y)
                fx, fy = px, py
            elseif s == "L" then
                ni = ni + checkinside.linear(px, py, data[o+2], data[o+3], x, y)
                px, py = data[o+2], data[o+3]
            elseif s == "Q" then
                ni = ni + checkinside.quadratic(px, py, data[o+2], data[o+3],
                data[o+4], data[o+5], x, y)
                px, py = data[o+4], data[o+5]
            elseif s == "A" then
                ni = ni + checkinside.rational_quadratic(px, py, data[o+2], data[o+3], 
                data[o+4], data[o+5], data[o+6], x, y)
                px, py = data[o+5], data[o+6]
            elseif s == "C" then
                ni = ni + checkinside.cubic(px, py, data[o+2], data[o+3], 
                data[o+4], data[o+5], data[o+6], data[o+7], x, y)
                px, py = data[o+6], data[o+7]
            end
        end
        if (element.type == "fill" and ni ~= 0) or (element.type == "eofill" and ni % 2 ~= 0) then
            r,g,b,a = getcolor[element.paint.type](element.paint, x, y)
            a = element.paint.opacity*a
            Cr = r*a + Cr*alpha*(1-a)
            Cg = g*a + Cg*alpha*(1-a)
            Cb = b*a + Cb*alpha*(1-a)
            alpha = a + alpha*(1-a)
        end
    end
    return Cr, Cg, Cb, alpha
end

-- this returns an iterator that prints the methods called
-- and then forwards them on.
-- very useful for debugging!
local function newtap(name, forward)
    local newwrite = function(method)
        return function(self, ...)
            io.stderr:write(name, ":", method, "(")
            for i = 1, select("#", ...) do
                io.stderr:write(tostring(select(i, ...)), ",")
            end
            io.stderr:write(")\n")
            forward[method](forward, ...)
        end
    end
    return setmetatable({}, {
        __index = function(tap, index)
            local new = newwrite(index)
            tap[index] = new
            return new
        end
    })
end

-- clipping

local clipl = {}

function clipl.right(x0, y0, x1, y1, x)
    local y = (y1-y0)*(x-x0)/(x1-x0) + y0
    return x, y
end
clipl.left = clipl.right

function clipl.top(x0, y0, x1, y1, y)
    local x = (x1-x0)*(y-y0)/(y1-y0) + x0
    return x, y
end
clipl.bottom = clipl.top

local clip2s = {}

function clip2s.right(x0, y0, x1, y1, x2, y2, x)
    return bisectquadratic(x0 - x, x1 - x, x2 - x)
end
clip2s.left = clip2s.right

function clip2s.top(x0, y0, x1, y1, x2, y2, y)
    return bisectquadratic(y0 - y, y1 - y, y2 - y)
end
clip2s.bottom = clip2s.top

local clipr2s = {}

function clipr2s.right(x0, y0, x1, y1, w1, x2, y2, x)
    return bisectrationalquadratic(x0 - x, x1 - x*w1, w1, x2 - x)
end
clipr2s.left = clipr2s.right

function clipr2s.top(  x0, y0, x1, y1, w1, x2, y2, y)
    return bisectrationalquadratic(y0 - y, y1 - y*w1, w1, y2 - y)
end
clipr2s.bottom = clipr2s.top

local clip3s = {}

function clip3s.right(x0, y0, x1, y1, x2, y2, x3, y3,  x)
    return bisectcubic(x0 - x, x1 - x, x2 - x, x3 - x)
end
clip3s.left = clip3s.right

function clip3s.top(x0, y0, x1, y1, x2, y2, x3, y3, y)
    return bisectcubic(y0 - y, y1 - y, y2 - y, y3 - y)
end
clip3s.bottom = clip3s.top

local function newclipper(a, type, forward)
    local fx, fy -- first contour cursor
    local sx, sy -- algorithm cursor
    local lix, liy -- last inside cursor
    local f = false
    local clipper = {}

    function clipper.left(x, y)
        return a <= x
    end
    function clipper.right(x, y)
        return x < a
    end
    function clipper.bottom(x, y)
        return a <= y
    end
    function clipper.top(x, y)
        return y < a
    end
    
    local checkinside = clipper[type]

    function clipper:begin_closed_contour(len, x0, y0)

        if checkinside(x0, y0) then
            forward:begin_closed_contour(_, x0, y0)
            f = true
        end
        fx, fy = x0, y0
        sx, sy = x0, y0
    end
    clipper.begin_open_contour = clipper.begin_closed_contour
    function clipper:end_closed_contour(len)
        if sx ~= fx or sy ~= fy then
            clipper:linear_segment(sx, sy, fx, fy)
        end
        if f then
            forward:end_closed_contour(_)
        end
        f = false
        lix, liy = nil, nil
    end
    clipper.end_open_contour = clipper.end_closed_contour
    function clipper:linear_segment(x0, y0, x1, y1)
        if checkinside(x1, y1) then
            if not checkinside(sx, sy) then
                local ix, iy = clipl[type](sx, sy, x1, y1, a)
                if not lix or not liy then
                    forward:begin_closed_contour(_, ix, iy)
                    f = true
                else
                    forward:linear_segment(lix, liy, ix, iy)
                    sx, sy = ix, iy
                end
            end
            forward:linear_segment(sx, sy, x1, y1)
        elseif checkinside(sx, sy) then
            lix, liy = clipl[type](sx, sy, x1, y1, a)
            forward:linear_segment(sx, sy, lix, liy)
        end
        sx, sy = x1, y1
    end
    function clipper:quadratic_segment(x0, y0, x1, y1, x2, y2)
        if clipper[type](x2, y2) then
            if not clipper[type](sx, sy) then
                local t = clip2s[type](sx, sy, x1, y1, x2, y2, a)
                local ix, iy = lerp2(sx, x1, x2, t, t), lerp2(sy, y1, y2, t, t)
                if lix == nil or liy == nil then
                    forward:begin_closed_contour(_, ix, iy)
                    f = true
                else
                    forward:linear_segment(lix, liy, ix, iy)
                end
                forward:quadratic_segment(cut2s(t, 1, sx, sy, x1, y1, x2, y2))
            else
                forward:quadratic_segment(sx, sy, x1, y1, x2, y2)
            end
        elseif clipper[type](sx, sy) then
            local t = clip2s[type](sx, sy, x1, y1, x2, y2, a)
            local ix, iy = lerp2(sx, x1, x2, t, t), lerp2(sy, y1, y2, t, t)
            forward:quadratic_segment(cut2s(0, t, sx, sy, x1, y1, x2, y2))
            lix, liy = ix, iy
        end
        sx, sy = x2, y2
    end
    function clipper:rational_quadratic_segment(x0, y0, x1, y1, w1, x2, y2)
        if clipper[type](x2, y2) then
            if not clipper[type](sx, sy) then
                local t = clipr2s[type](sx, sy, x1, y1, w1, x2, y2, a)
                local ix, iy, ax, ay, wa, bx, by = cutr2s(t, 1, sx, sy, x1, y1, w1, x2, y2)
                if lix == nil or liy == nil then
                    forward:begin_closed_contour(_, ix, iy)
                    f = true
                else
                    forward:linear_segment(lix, liy, ix, iy)
                end
                forward:rational_quadratic_segment(ix, iy, ax, ay, wa, bx, by)
            else
                forward:rational_quadratic_segment(sx, sy, x1, y1, w1, x2, y2)
            end
        elseif clipper[type](sx, sy) then
            local t = clipr2s[type](sx, sy, x1, y1, w1, x2, y2, a)
            local ix, iy, ax, ay, wa, bx, by = cutr2s(0, t, sx, sy, x1, y1, w1, x2, y2)
            forward:rational_quadratic_segment(ix, iy, ax, ay, wa, bx, by)
            lix, liy = ix, iy
        end
        sx, sy = x2, y2
    end
    function clipper:cubic_segment(x0, y0, x1, y1, x2, y2, x3, y3)
        if checkinside(x3, y3) then
            if not checkinside(sx, sy) then
                local t = clip3s[type](sx, sy, x1, y1, x2, y2, x3, y3, a)
                local ix, iy, u1, v1, u2, v2, u3, v3 = cut3s(t, 1, sx, sy, x1, y1, x2, y2, x3, y3)
                if lix == nil or liy == nil then
                    forward:begin_closed_contour(_, ix, iy)
                    f = true
                else
                    forward:linear_segment(lix, liy, ix, iy)
                end
                forward:cubic_segment(ix, iy, u1, v1, u2, v2, u3, v3)
            else
                forward:cubic_segment(sx, sy, x1, y1, x2, y2, x3, y3)
            end
        elseif checkinside(sx, sy) then
            local t = clip3s[type](sx, sy, x1, y1, x2, y2, x3, y3, a)
            local u0, u1, u1, v1, u2, v2, ix, iy = cut3s(0, t, sx, sy, x1, y1, x2, y2, x3, y3)
            forward:cubic_segment(u0, v0, u1, v1, u2, v2, ix, iy)
            lix, liy = ix, iy
        end
        sx, sy = x3, y3
    end
    return clipper
end

function clippath(oldpath, a, type)
    local newpath = _M.path()
    newpath:open()
    oldpath:iterate(newclipper(a, type, newpath))
    newpath:close()
    return newpath
end

local clipcommand = {
    T = "top",
    B = "bottom",
    R = "right",
    L = "left",
}

-- clip scene against bounding-box and return a quadtree leaf
local function scenetoleaf(scene, xmin, ymin, xmax, ymax, c1, c2)
    -- implement
    local newelements = {}
    local elements

    for i,element in ipairs(scene.elements) do
        newelements[#newelements + 1] = {element.shape, i}
    end
    
    if not c2 or c2 == 'r' then
        elements = newelements
        newelements = {}
        for _,element in ipairs(elements) do
            local newshape = clippath(element[1], xmax, clipcommand.R)
            if #newshape.instructions > 2 then
                newelements[#newelements + 1] = {newshape, element[2]}
                --newelements[#newelements + 1] = _M[element.type](newshape, element.paint)
            end
        end
    end

    if not c1 or c1 == 't' then
        elements = newelements
        newelements = {}
        for i,element in ipairs(elements) do
            local newshape = clippath(element[1], ymax, clipcommand.T)
            if #newshape.instructions > 2 then
                --newelements[#newelements + 1] = _M[element.type](newshape, element.paint)
                newelements[#newelements + 1] = {newshape, element[2]}
            end
        end
    end

    if not c2 or c2 == 'l' then
        elements = newelements
        newelements = {}
        for i,element in ipairs(elements) do
            local newshape = clippath(element[1], xmin, clipcommand.L)
            if #newshape.instructions > 2 then
                --newelements[#newelements + 1] = _M[element.type](newshape, element.paint)
                newelements[#newelements + 1] = {newshape, element[2]}
            end
        end
    end

    if not c1 or c1 == 'b' then
        elements = newelements
        newelements = {}
        for i,element in ipairs(elements) do
            local newshape = clippath(element[1], ymin, clipcommand.B)
            if #newshape.instructions > 2 then
                --newelements[#newelements + 1] = _M[element.type](newshape, element.paint)
                newelements[#newelements + 1] = {newshape, element[2]}
            end
        end
    end

    elements = scene.elements
    local copied_elements = {}

    for i,element in ipairs(newelements) do
        local obj = elements[element[2]]
        copied_elements[i] = _M[obj.type](element[1], obj.paint)
    end

    return _M.scene(copied_elements)
end

local function checkbound(x, y, xmin, ymin, xmax, ymax)
    if xmin <= x and x <= xmax and ( abs(y-ymin) < TOL or abs(y - ymax) < TOL ) then
        return true
    elseif ymin <= y and y <= ymax and ( abs(x-xmin) < TOL or abs(x - xmax) < TOL ) then
        return true
    end
    return false
end

local function checkaxi(x0, y0, x1, y1)
    return abs(x0 - x1) < TOL or abs(y0 - y1) < TOL
end

local function checkstop(scene, xmin, ymin, xmax, ymax)
    local px, py
    for i, element in ipairs(scene.elements) do
        local shape = element.shape
        local n = #shape.instructions
        for j=1,n do
            local o = shape.offsets[j]
            local s = rvgcommand[shape.instructions[j]]
            if s == "M" then
                px = shape.data[o+1]
                py = shape.data[o+2]
                if not checkbound(px, py, xmin, ymin, xmax, ymax) then return false end
            elseif s == "L" then
                if not checkbound(shape.data[o+2], shape.data[o+3], xmin, ymin, xmax, ymax) or 
                    not checkaxi(px, py, shape.data[o+2], shape.data[o+3]) then
                    return false
                end
                px = shape.data[o+2]
                py = shape.data[o+3]
            elseif s == "Q" or s == "A" or s == "C" then
                return false
            end
        end
    end
    return true
end

-- recursively subdivides leaf to create the quadtree
function subdividescene(leaf, xmin, ymin, xmax, ymax, maxdepth, depth)
    depth = depth or 1
    if depth >= maxdepth or checkstop(leaf, xmin, ymin, xmax, ymax) then  return leaf end
    local xm = 0.5*(xmin + xmax)
    local ym = 0.5*(ymin + ymax)

    leaf.children = {true, true, true, true}
    leaf.children[1] = subdividescene(scenetoleaf(leaf, xmin, ymin, xm, ym, 't', 'r'), xmin, ymin, xm, ym, maxdepth, depth + 1) --bl 
    leaf.children[2] = subdividescene(scenetoleaf(leaf, xm, ymin, xmax, ym, 't', 'l'), xm, ymin, xmax, ym, maxdepth, depth + 1) --br
    leaf.children[3] = subdividescene(scenetoleaf(leaf, xmin, ym, xm, ymax, 'b', 'r'), xmin, ym, xm, ymax, maxdepth, depth + 1) --tl
    leaf.children[4] = subdividescene(scenetoleaf(leaf, xm, ym, xmax, ymax, 'b', 'l'), xm, ym, xmax, ymax, maxdepth, depth + 1) --tr
    return leaf
end

-- return smallest power of 2 larger than n
local function power2(n)
    n = floor(n)
    if n > 0 then
        n = n - 1
        n = bit32.bor(n, bit32.rshift(n, 1))
        n = bit32.bor(n, bit32.rshift(n, 2))
        n = bit32.bor(n, bit32.rshift(n, 4))
        n = bit32.bor(n, bit32.rshift(n, 8))
        n = bit32.bor(n, bit32.rshift(n, 16))
        n = n + 1
        return n
    else
        return 1
    end
end

-- adjust the viewport so that the width and the height are
-- the smallest powers of 2 that are large enough to
-- contain the viewport
local function adjustviewport(vxmin, vymin, vxmax, vymax)
    local width = max(power2(vxmax - vxmin), power2(vymax - vymin))
    return vxmin, vymin, vxmin+width, vymin+width
end

-- load your own svg driver here and use it for debugging!
local svg = dofile"assign/svg.lua"

local function newstroke(x1, y1, x2, y2, t, w)
    if t == 'h' then
        return _M.fill(_M.path{
            _M.M, x1, y1-w/2,
            _M.L, x2, y1-w/2,
            _M.L, x2, y1+w/2,
            _M.L, x1, y1+w/2,
            _M.Z
        }, _M.solid(_M.rgb(0,0,1), 1))
    else
        return _M.fill(_M.path{
            _M.M, x1-w/2, y1,
            _M.L, x2-w/2, y2,
            _M.L, x2+w/2, y2,
            _M.L, x1+w/2, y1,
            _M.Z
        }, _M.solid(_M.rgb(0,0,1), 1))
    end
end

-- append lines marking the tree bounding box to the scene
local function appendbox(xmin, ymin, xmax, ymax, scene)
    -- implement
    local elements = scene.elements
    elements[#elements + 1] = newstroke(xmin, ymin, xmax, ymin, 'h', 0.5)
    elements[#elements + 1] = newstroke(xmin, ymax, xmax, ymax, 'h', 0.5)
    elements[#elements + 1] = newstroke(xmin, ymin, xmin, ymax, 'v', 0.5)
    elements[#elements + 1] = newstroke(xmax, ymin, xmax, ymax, 'v', 0.5)
end

-- recursively append the lines marking cell divisions to the scene
local function appendtree(quadtree, xmin, ymin, xmax, ymax, scene)
    -- implement
    if not quadtree.children then return end

    local xm = 0.5*(xmax+xmin)
    local ym = 0.5*(ymax+ymin)

    local elements = scene.elements
    elements[#elements + 1] = newstroke(xmin, ym, xmax, ym, 'h', 0.5)
    elements[#elements + 1] = newstroke(xm, ymin, xm, ymax, 'v', 0.5)

    appendtree(quadtree.children[1], xmin, ymin, xm, ym, scene)
    appendtree(quadtree.children[2], xm, ymin, xmax, ym, scene)
    appendtree(quadtree.children[3], xmin, ym, xm, ymax, scene)
    appendtree(quadtree.children[4], xm, ym, xmax, ymax, scene)
end

local function dumpscenetree(quadtree, xmin, ymin, xmax, ymax,
    scene, viewport, output)
    appendbox(xmin, ymin, xmax, ymax, scene)
    appendtree(quadtree, xmin, ymin, xmax, ymax, scene)
    -- use your svg driver to dump contents to an SVG file
    svg.render(scene, viewport, output)
end

function _M.render(scene, viewport, output, arguments)
    local maxdepth = MAX_DEPTH
    local scenetree = false
    -- dump arguments
    if #arguments > 0 then stderr("driver arguments:\n") end
    for i, argument in ipairs(arguments) do
        stderr("  %d: %s\n", i, argument)
    end
    -- list of supported options
    -- you can add your own options as well
    local options = {
        { "^(%-maxdepth:(%d+)(.*))$", function(all, n, e)
            if not n then return false end
            assert(e == "", "invalid option " .. all)
            n = assert(tonumber(n), "invalid option " .. all)
            assert(n >= 1, "invalid option " .. all)
            maxdepth = math.floor(n)
            return true
        end },
        { "^%-scenetree$", function(d)
            if not d then return false end
            scenetree = true
            return true
        end },
        { ".*", function(all)
            error("unrecognized option " .. all)
        end }
    }
    -- process options
    for i, argument in ipairs(arguments) do
        for j, option in ipairs(options) do
            if option[2](argument:match(option[1])) then
                break
            end
        end
    end
    -- create timer
    local time = chronos.chronos()
    -- make sure scene does not contain any unsuported content
    checkscene(scene)
    -- prepare scene for rendering
    scene = preparescene(scene)
    -- get viewport
    local vxmin, vymin, vxmax, vymax = unpack(viewport, 1, 4)
    -- get image width and height from viewport
    local width, height = vxmax-vxmin, vymax-vymin
    -- build quadtree for scene
    local qxmin, qymin, qxmax, qymax =
    adjustviewport(vxmin, vymin, vxmax, vymax)
    stderr("preparescene in %.3fs\n", time:elapsed())
    local quadtree = subdividescene(
    scenetoleaf(scene, vxmin, vymin, vxmax, vymax),
    qxmin, qymin, qxmax, qymax, maxdepth)
    stderr("preprocess in %.3fs\n", time:elapsed())
    time:reset()
    if scenetree then
        --dump tree on top of scene as svg into output
        dumpscenetree(quadtree, qxmin, qymin, qxmax, qymax,
        scene, viewport, output)
        output:flush()
        stderr("scene quadtree dump in %.3fs\n", time:elapsed())
        os.exit()
    end
    -- allocate output image
    local outputimage = image.image(width, height)
    -- render
    for i = 1, height do
        stderr("\r%d%%", floor(1000*i/height)/10)
        for j = 1, width do
            local x, y = vxmin+j-.5, vymin+i-.5
            local r, g, b, a = sample(quadtree,
            qxmin, qymin, qxmax, qymax, x, y)
            outputimage:set(j, i, r, g, b, a)
        end
    end
    stderr("\n")
    stderr("rendering in %.3fs\n", time:elapsed())
    time:reset()
    -- store output image
    image.png.store8(output, outputimage)
    stderr("saved in %.3fs\n", time:elapsed())
end

return _M
