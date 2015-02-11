local _M = { meta = {} }

local vector = require"vector"
local xform = require"xform"
local svd = require"svd"

local arc_meta = _M.meta
arc_meta.__index = {}
arc_meta.name = "arc"

local EPS = 1.17549435E-38
local unpack = table.unpack

function _M.degenerate(x0, y0, rx, ry, rot_deg, fa, fs, x2, y2)
    local dx = x2-x0
    local dy = y2-y0
    return dx*dx+dy*dy < EPS*EPS or rx < EPS or ry < EPS
end

local function elevate(x0, y0, x2, y2)
    return .5*(x0+x2), .5*(y0+y2), 1
end

function _M.torational(x0, y0, rx, ry, rot_deg, fa, fs, x2, y2)
    -- convert flags to booleans
    fa = fa == 1 or fa == '1' or fa == true
    fs = fs == 1 or fs == '1' or fs == true
    -- radii are assumed positive
    rx, ry = math.abs(rx), math.abs(ry)
    -- if radii are too small, we degenerate to line connecting endpoints
    if rx < EPS or ry < EPS then
        -- use degree elevation to represent line segment as quadratic
        return elevate(x0, y0, x2, y2)
    end
    local rot_rad = math.rad(rot_deg)
    local cos_rot = math.cos(rot_rad)
    local sin_rot = math.sin(rot_rad)
    local p0 = vector.vector(x0, y0)
    local p2 = vector.vector(x2, y2)
    local scale = xform.scale(1/rx, 1/ry)
    local rotate = xform.rotate(cos_rot, -sin_rot)
    -- we solve the problem in a new coordinate system
    -- where rx=ry=1 and rot_deg=0, then we move the solution
    -- back to the original coordinate system
    local q0 = scale*(rotate*p0)
    local q2 = scale*(rotate*p2)
    -- direction perpendicular to line connecting endpoints
    local perp = vector.perp(q2-q0)
    -- if transformed endpoints are too close, degenerate to
    -- line segment connecting endpoints
    local len2 = vector.len2(perp) -- perp doesn't change length
    if len2 < EPS then
        return elevate(x0, y0, x2, y2)
    end
    local mq = vector.lerp(q0, q2, .5) -- midpoint between transformed endpoints
    local radius -- circle radius
    local inv_radius -- its reciprocal
    local offset -- distance from midpoint to center
    -- center of circle, endpoint, and midpoint form a right triangle
    -- hypotenuse is the circle radius, which has length 1
    -- it connects the endpoint to the center
    -- the segment connecting the midpoint and endpoint is a cathetus
    -- the segment connecting midpoint and the center is the other
    local len = math.sqrt(len2)
    local inv_len = 1/len
    -- the length of the hypothenuse must be at least
    -- as large as the length of the catheti.
    if len2 > 4 then
        -- otherwise, we grow the circle isotropically until they are equal
        radius = 0.5*len
        inv_radius = 2*inv_len
        -- in which case, the midpoint *is* the center
        offset = 0
    else
        -- circle with radius 1 is large enough
        radius = 1
        inv_radius = 1
        -- length of the cathetus connecting the midpoint and the center
        offset = 0.5*math.sqrt(4-len2)
    end
    -- there are two possible circles. flags decide which one
    local sign = ((fa ~= fs) and 1) or -1 -- offset sign
    -- to find circle center in new coordinate system,
    -- simply offset midpoint in the perpendicular direction
    local cq = mq + (sign*offset*inv_len)*perp
    -- middle weight is the cosine of half the sector angle
    local w1 = math.abs(vector.dot(q0-cq, perp)*inv_len*inv_radius)
    -- if center was at the origin, this would be the
    -- intermediate control point for the rational quadratic
    local q1 = vector.vector((-sign*radius*inv_len)*perp, w1)
    -- so we translate it by the center
    q1 = xform.translate(cq[1], cq[2])*q1
    -- move control point back to original coordinate system
    scale = xform.scale(rx, ry)
    rotate = xform.rotate(cos_rot, sin_rot)
    local x1, y1 = unpack(rotate*(scale*q1), 1, 2)
    -- this selects the small arc. to select the large arc,
    -- negate all coordinates of intermediate control point
    if fa then
        return -x1, -y1, -w1
    else
        return x1, y1, w1
    end
end

local function det(a, b, c, d, e, f, g, h, i)
    return -c*e*g + b*f*g + c*d*h - a*f*h - b*d*i + a*e*i
end

function _M.tosvg(x0, y0, x1, y1, w1, x2, y2)
    -- we start by computing the projective transformation that
    -- maps the unit circle to the ellipse described by the control points
    local s2 = 1-w1*w1
    assert(math.abs(s2) > EPS, "not an ellipse (parabola?)")
    local s = ((s2 < 0) and -1 or 1) * math.sqrt(math.abs(s2))
    local a11 = 2*x1-w1*(x0+x2)
    local a12 = s*(x2-x0)
    local a21 = 2*y1-w1*(y0+y2)
    local a22 = s*(y2-y0)
    -- from the transformation, we extract the linear part and compute the SVD
    local ca, sa, sx, sy = svd.us(a11, a12, a21, a22)
    -- the sign of the middle weight gives the large/small angle flag
    local fa = (w1 < 0) and 1 or 0
    -- the sign of the area of the control point triangle gives the orientation
    local fs = (det(x0, y0, 1, x1, y1, w1, x2, y2, 1) > 0) and 1 or 0
    -- the rotate and the scale from SVD give the angle and axes
    return sx/(2*s2), sy/(2*s2), math.deg(math.atan2(sa, ca)), fa, fs
end

return _M
