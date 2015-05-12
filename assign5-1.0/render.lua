local driver = require"driver"
local image = require"image"
local chronos = require"chronos"

local solve = {}
solve.quadratic = require"quadratic"

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
    
local function sign(v)
    if v < 0 then return -1
    elseif v > 0 then return 1
    else return 0 end
end

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
            forward:linear_segment(x0, y0, x1, y1)
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
        forward:linear_segment(x0, y0, x1, y1)
    end
    function monotonizer:quadratic_segment(x0, y0, x1, y1, x2, y2)
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
    function monotonizer:rational_quadratic_segment(x0, y0, x1, y1, w1, x2, y2)
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
    function monotonizer:cubic_segment(x0, y0, x1, y1, x2, y2, x3, y3)
        function solve_extreme(z0, z1, z2,z3, t)
            local a = 3 * ( -z0 + 3*z1 - 3*z2 + z3 )
            local b = 6 * ( z0 - 2*z1 + z2 )
            local c = 3 * ( -z0 + z1 )
            local n, r1, s1, r2, s2 = solve.quadratic.quadratic(a, b, c)
            if n == 0 then return end
            local t1, t2 = r1/s1, r2/s2
            if 0 < t1 and t1 < 1 then t[#t + 1] = t1 end
            if 0 < t2 and t2 < 1 then t[#t + 1] = t2 end
        end
        function inflecction_double(x0, y0, x1, y1, x2, y2, x3, y3, t)
            local m = {
                x0, -3*x0 + 3*x1, 3*x0 - 6*x1 + 3*x2, -x0 + 3*x1 - 3*x2 + x3,
                y0, -3*y0 + 3*y1, 3*y0 - 6*y1 + 3*y2, -y0 + 3*y1 - 3*y2 + y3,
                1, 0, 0, 0
            }
            local _, d1 = _M.xform(m[2], m[3], m[4], m[6], m[7], m[8], m[10], m[11], m[12]):inversedet()
            local _, d2 = _M.xform(m[1], m[3], m[4], m[5], m[7], m[8], m[9], m[11], m[12]):inversedet()
            local _, d3 = _M.xform(m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10], m[12]):inversedet()
            local _, d4 = _M.xform(m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11]):inversedet()
            
            d2, d4 = -d2, -d4

            local a, b, c, n, r1, s1, r2, s2
            -- inflecction point
            a = -3*d2
            b = 3*d3
            c = -d4
            n, r1, s1, r2, s2 = solve.quadratic.quadratic(a, b, c)
            if n ~= 0 then 
                local t1, t2 = r1/s1, r2/s2
                if 0 < t1 and t1 < 1 then t[#t + 1] = t1 end
                if 0 < t2 and t2 < 1 then t[#t + 1] = t2 end
            end

            -- double point
            a = d2*d2
            b = -d2*d3
            c = d3*d3 - d2*d4
            n, r1, s1, r2, s2 = solve.quadratic.quadratic(a, b, c)
            if n ~= 0 then 
                local t1, t2 = r1/s1, r2/s2
                if 0 < t1 and t1 < 1 then t[#t + 1] = t1 end
                if 0 < t2 and t2 < 1 then t[#t + 1] = t2 end
            end

        end
        
        local t = {0,1}
        solve_extreme(x0, x1, x2, x3, t)
        solve_extreme(y0, y1, y2, y3, t)
        inflecction_double(x0, y0, x1, y1, x2, y2, x3, y3, t)
        
        table.sort(t)

        for i = 2, #t do 
            if t[i-1 ] ~= t[i] then
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

local function newlinear(x1, y1, x2, y2)
    local xmin, xmax = min(x1, x2), max(x1, x2)
    local ymin, ymax = min(y1, y2), max(y1, y2)
    local a = y2 - y1
    local b = x1 - x2
    local c = -(a * x1  + b * y1)
    local s = sign(a)
    a, b, c = s*a, s*b, s*c
    return {xmin, ymin, xmax, ymax, a, b, c;
    winding = function(self, x, y)
        local xmin, ymin, xmax, ymax, a, b, c = unpack(self)
        if y > ymax then return false end
        if y <= ymin then return false end
        return a * x + b * y + c < 0
    end
    }
end

-- create new structure for paths
function newimpliciter(forward)
    local px, py
    local fx, fy
    local impliciter = {}

    local function det(a00, a01, a10, a11)
        return a00 * a11 - a01 * a10
    end

    local function signed_area(x1, y1, x2, y2)
        return x1 * y2 - y1 * x2
    end

    function impliciter:begin_closed_contour(len, x0, y0)
        fx, fy = x0, y0
        px, py = x0, y0
    end
    impliciter.begin_open_contour = impliciter.begin_closed_contour
    function impliciter:linear_segment(x0, y0, x1, y1)
        local xmin = min(x0, x1)
        local xmax = max(x0, x1)
        local ymin = min(y0, y1)
        local ymax = max(y0, y1)

        local s = sign(y1 - y0) 
        local a = (y1 - y0)
        local b = (x0 - x1)
        local c = -(x0 * a + y0 * b)
        a, b, c = s*a, s*b, s*c
        forward[#forward + 1] = {xmin, ymin, xmax, ymax, s, a, b, c;
            winding = function(self, x, y)
                local xmin, ymin, xmax, ymax, s, a, b, c = unpack(self)
                if y > ymax then return 0 end
                if y <= ymin then return 0 end
                if x > xmax then return 0 end
                if x <= xmin then return s end
                if a * x + b * y + c < 0 then return s end
                return 0
            end
        }
        px, py = x1, y1
    end
    function impliciter:quadratic_segment(x0, y0, x1, y1, x2, y2)
        local u0, v0 = x0 - x0, y0 - y0
        local u1, v1 = x1 - x0, y1 - y0
        local u2, v2 = x2 - x0, y2 - y0
        
        --bounding box
        local xmin, xmax = min(0, u2), max(0, u2)
        local ymin, ymax = min(0, v2), max(0, v2)
        -- coefficients
        local s = sign(v2) 
        local a = 2*u1 - u2
        local b = -2*v1 + v2
        local c = -2*u1
        local d = 2*v1
        local e = 2*u2*v1 - 2*u1*v2
        
        local dd = newlinear(0, 0, u2, v2)

        local theta = signed_area(u2, v2, u1, v1)
        local command
        if (v2 > 0 and theta > 0) or (v2 < 0 and theta < 0 )then
            command = "and"
        elseif(v2 < 0 and theta > 0) or (v2 > 0 and theta < 0)then
            command = "or"
        end
        forward[#forward + 1] = {xmin, ymin, xmax, ymax, s, a, b, c, d, e, x0, y0, command, dd;
            winding = function(self, x, y)
                local xmin, ymin, xmax, ymax, s, a, b, c, d, e, tx, ty, command, dd = unpack(self)
                x, y = x - tx, y - ty
                if y > ymax then return 0 end
                if y <= ymin then return 0 end
                if x > xmax then return 0 end
                if x <= xmin then return s end
                local F =(a*y + x*b)^2 - (c*y + x*d)*e
                if command == "and" then
                    if dd:winding(x,y) and F > 0 then return s end 
                else
                    if dd:winding(x,y) or  F < 0 then return s end 
                end
                return 0
            end
        }
        px, py = x2, y2
    end
    function impliciter:rational_quadratic_segment(x0, y0, x1, y1, w1, x2, y2)
        local mt = _M.xform(1, 0, -x0, 0, 1, -y0, 0, 0, 1)
        local u0, v0 = x0 - x0, y0 - y0
        local u1, v1, w1 = mt:apply(x1, y1, w1)
        local u2, v2 = x2 - x0, y2 - y0
        
        -- bounding box
        local xmin, xmax = min(0, u2), max(0, u2)
        local ymin, ymax = min(0, v2), max(0, v2)
        -- coefficients
        local a = 4*u1^2 - 4*w1*u1*u2 + u2^2
        local b = 4*u1*u2*v1 - 4*u1^2*v2
        local c = -4*u2*v1^2 + 4*u1*v1*v2
        local d = -8*u1*v1 + 4*w1*u2*v1 + 4*w1*u1*v2 - 2*u2*v2
        local e = 4*v1^2 - 4*w1*v1*v2 + v2^2
        local s = sign(v2) 
        
        -- diagonal
        local dd = newlinear(0, 0, u2, v2)

        local theta = signed_area(u2, v2, u1, v1)
        local command
        if (v2 > 0 and theta > 0) or (v2 < 0 and theta < 0 )then
            command = "and"
        elseif(v2 < 0 and theta > 0) or (v2 > 0 and theta < 0)then
            command = "or"
        end

        forward[#forward + 1] = {xmin, ymin, xmax, ymax, s, a, b, c, d, e, x0, y0, command, dd;
            winding = function(self, x, y)
                local xmin, ymin, xmax, ymax, s, a, b, c, d, e, tx, ty, command, dd = unpack(self)
                x, y = x - tx, y - ty
                if y > ymax then return 0 end
                if y <= ymin then return 0 end
                if x > xmax then return 0 end
                if x <= xmin then return s end
                local f = y*(a*y + b) + x*(c + y*d + x*e)
                if command == "and" then
                    if dd:winding(x,y) and f > 0 then return s end 
                else
                    if dd:winding(x,y) or f < 0 then return s end 
                end
                return 0
            end
        }
        px, py = x2, y2
    end
    function impliciter:cubic_segment(x0, y0, x1, y1, x2, y2, x3, y3)
        local u0, v0 = x0 - x0, y0 - y0
        local u1, v1 = x1 - x0, y1 - y0
        local u2, v2 = x2 - x0, y2 - y0
        local u3, v3 = x3 - x0, y3 - y0

        -- bounding box
        local xmin, xmax = min(0, u3), max(0, u3)
        local ymin, ymax = min(0, v3), max(0, v3)

        -- coefficients
        local a = -27*u1*u3^2*v1^2 + 81*u1*u2*u3*v1*v2 - 81*u1^2*u3*v2^2 - 
        81*u1*u2^2*v1*v3 + 54*u1^2*u3*v1*v3 + 81*u1^2*u2*v2*v3 - 
        27*u1^3*v3^2

        local b = -27*u1^3 + 81*u1^2*u2 - 81*u1*u2^2 + 27*u2^3 - 27*u1^2*u3 + 
        54*u1*u2*u3 - 27*u2^2*u3 - 9*u1*u3^2 + 9*u2*u3^2 - u3^3

        local c = 81*u1*u2^2*v1 - 54*u1^2*u3*v1 - 81*u1*u2*u3*v1 + 
        54*u1*u3^2*v1 - 9*u2*u3^2*v1 - 81*u1^2*u2*v2 + 162*u1^2*u3*v2 -
        81*u1*u2*u3*v2 + 27*u2^2*u3*v2 - 18*u1*u3^2*v2 + 54*u1^3*v3 -
        81*u1^2*u2*v3 + 81*u1*u2^2*v3 - 27*u2^3*v3 - 54*u1^2*u3*v3 + 27*u1*u2*u3*v3
        
        local d = 27*u3^2*v1^3 - 81*u2*u3*v1^2*v2 + 81*u1*u3*v1*v2^2 +
        81*u2^2*v1^2*v3 - 54*u1*u3*v1^2*v3 - 81*u1*u2*v1*v2*v3 + 27*u1^2*v1*v3^2

        local e = -81*u2^2*v1^2 + 108*u1*u3*v1^2 + 81*u2*u3*v1^2 -
        54*u3^2*v1^2 - 243*u1*u3*v1*v2 + 81*u2*u3*v1*v2 + 27*u3^2*v1*v2 +
        81*u1^2*v2^2 + 81*u1*u3*v2^2 - 54*u2*u3*v2^2 - 108*u1^2*v1*v3 +
        243*u1*u2*v1*v3 - 81*u2^2*v1*v3 - 9*u2*u3*v1*v3 - 81*u1^2*v2*v3 -
        81*u1*u2*v2*v3 + 54*u2^2*v2*v3 + 9*u1*u3*v2*v3 + 54*u1^2*v3^2 - 27*u1*u2*v3^2

        local f = 81*u1^2*v1 - 162*u1*u2*v1 + 81*u2^2*v1 + 54*u1*u3*v1 -
        54*u2*u3*v1 + 9*u3^2*v1 - 81*u1^2*v2 + 162*u1*u2*v2 - 81*u2^2*v2 -
        54*u1*u3*v2 + 54*u2*u3*v2 - 9*u3^2*v2 + 27*u1^2*v3 - 54*u1*u2*v3 +
        27*u2^2*v3 + 18*u1*u3*v3 - 18*u2*u3*v3 + 3*u3^2*v3

        local g = -54*u3*v1^3 + 81*u2*v1^2*v2 + 81*u3*v1^2*v2 - 81*u1*v1*v2^2 -
        81*u3*v1*v2^2 + 27*u3*v2^3 + 54*u1*v1^2*v3 - 162*u2*v1^2*v3 + 54*u3*v1^2*v3 +
        81*u1*v1*v2*v3 + 81*u2*v1*v2*v3 - 27*u3*v1*v2*v3 - 27*u2*v2^2*v3 - 
        54*u1*v1*v3^2 + 18*u2*v1*v3^2 + 9*u1*v2*v3^2

        local h = -81*u1*v1^2 + 81*u2*v1^2 - 27*u3*v1^2 + 162*u1*v1*v2 -
        162*u2*v1*v2 + 54*u3*v1*v2 - 81*u1*v2^2 + 81*u2*v2^2 - 27*u3*v2^2 -
        54*u1*v1*v3 + 54*u2*v1*v3 - 18*u3*v1*v3 + 54*u1*v2*v3 - 54*u2*v2*v3 +
        18*u3*v2*v3 - 9*u1*v3^2 + 9*u2*v3^2 - 3*u3*v3^2

        local i = 27*v1^3 - 81*v1^2*v2+81*v1*v2^2 - 27*v2^3 + 27*v1^2*v3 -
        54*v1*v2*v3 + 27*v2^2*v3 + 9*v1*v3^2 - 9*v2*v3^2 + v3^3
        
        local s = sign(v3)
        
        local mx, my -- intersection tangents
        if abs(x0 - x1) < TOL and abs(y0 - y1) < TOL then
            mx, my = u2, v2
        elseif abs(x2 - x3) < TOL and abs(y2 - y3) < TOL then
            mx, my = u1, v1
        else
            local si = det(u3  - u0, u3 - u2, v3 - v0, v3 - v2)
            local ti = det(u1  - u0, u3 - u2, v1 - v0, v3 - v2)
            mx, my = u1*(si/ti), v1*(si/ti)
        end
        
        -- quadratic_segment
        if a == 0 and b == 0 and c == 0 and d == 0 and e == 0 and f == 0 and g ==0 and h == 0 and i == 0 then
            impliciter:quadratic_segment(x0, y0, mx + x0, my + y0, x3, y3)
            return
        end

        local theta = signed_area(u3, v3, mx, my)
        local command
        if (v3 > 0 and theta > 0) or (v3 < 0 and theta < 0 )then
            command = "and"
        elseif(v3 < 0 and theta > 0) or (v3 > 0 and theta < 0)then
            command = "or"
        end

        -- normalized function
        if  my*(a+my*(b*my+c)) + mx*(d + my*(e + my*f) + mx*(g + my*h + mx*i)) < 0 then 
            a, b, c, d, e, f, g, h, i = -a, -b, -c, -d, -e, -f, -g, -h, -i
        end

        -- bounding triangle
        local dd = newlinear(u0, v0, u3, v3)
        local da = newlinear(u0, v0, mx, my)
        local db = newlinear(u3, v3, mx, my)

        forward[#forward + 1] = {xmin, ymin, xmax, ymax, s, a, b, c, d, e, f, g, h, i, x0, y0, command, dd, da, db;
            winding = function(self, x, y)
                local xmin, ymin, xmax, ymax, s, a, b, c, d, e, f, g, h, i, tx, ty, command, dd, da, db = unpack(self)
                x, y = x - tx, y - ty
                if y > ymax then return 0 end
                if y <= ymin then return 0 end
                if x > xmax then return 0 end
                if x <= xmin then return s end

                local F = y*(a+y*(b*y+c)) + x*(d + y*(e + y*f) + x*(g + y*h + x*i))

                if command == "and" then
                    if dd:winding(x,y) and (da:winding(x, y) or db:winding(x, y) or F > 0 ) then return s end 
                else
                    if dd:winding(x,y) or (( da:winding(x, y) or db:winding(x, y)) and F < 0)  then return s end 
                end
                return 0
            end
        }
        px, py = x3, y3
    end
    function impliciter:end_closed_contour(len)
        if px ~= fx and py ~= fy then
            impliciter:linear_segment(px, py, fx, fy)
        end
    end
    impliciter.end_open_contour = impliciter.end_closed_contour
    return impliciter
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

function preparepath(oldpath)
    local implicitform = {}
    implicitform.path = {}
    oldpath:iterate(newimpliciter(implicitform.path))
    implicitform.winding = function(self, x, y)
        local w = 0
        for i, s in ipairs(self.path) do
            w = w + s:winding(x,y)
        end
        return w
    end
    implicitform.inside = function(self, x, y, type)
        local w = self:winding(x, y)
        if type == "eofill" and  w % 2 ~= 0 then
            return true
        elseif type == "fill" and w ~= 0 then
            return true
        end
        return false
    end
    return implicitform
end

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
        element.implicitform = preparepath(element.shape)
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
    return _M.path{
        _M.M, x1, y1,
        _M.L, x2, y2,
        _M.L, x3, y3,
        _M.Z
    } 
end

-- override polygon creation and return a path instead
function _M.polygon(data)
    local data_path = {_M.M, data[1], data[2]}
    local j = 1
    for i=3, #data, 2 do
        data_path[j*3 + 1] = _M.L
        data_path[j*3 + 2] = data[i]
        data_path[j*3 + 3] = data[i+1]
        j = j + 1
    end
    data_path[j*3 + 1] = _M.Z
    return _M.path{unpack(data_path)} 
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

local getcolor = {}

function getcolor.solid(paint, x, y)
    return unpack(paint.data)
end

function getcolor.lineargradient(paint, x0, y0)
    local p = paint.T:apply(x0, y0)
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


-- use scene to evaluate the color, and finally return r,g,b,a
local function sample(scene, x, y)
    -- implement
    local Cr, Cg, Cb, alpha = 1.0, 1.0, 1.0, 1.0
    local r, g, b, a 

    for i, element in ipairs(scene.elements) do
        if element.implicitform:inside(x, y, element.type) then
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

-- load your own svg driver here and use it for debugging!
local svg = dofile"assign/svg.lua"

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
        { "^%-tosvg$", function(d)
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
    stderr("preprocess in %.3fs\n", time:elapsed())
    time:reset()
    if scenetree then
        svg.render(scene, viewport, output)
        output:flush()
        stderr("scene to svg in %.3fs\n", time:elapsed())
        os.exit()
    end
    -- allocate output image
    local outputimage = image.image(width, height)
    -- render
    for i = 1, height do
        stderr("\r%d%%", floor(1000*i/height)/10)
        for j = 1, width do
            local x, y = vxmin+j-.5, vymin+i-.5
            local r, g, b, a = sample(scene, x, y)
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
