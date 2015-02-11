local _M = { }

local EPS = 1.17549435E-38 -- FLT_MIN

-- our own implementation of the C hypot function
local function hypot(x, y)
    x = math.abs(x)
    y = math.abs(y)
    if x < EPS and y < EPS then return 0 end
    local t = math.min(x,y);
    x = math.max(x,y)
    t = t/x
    return x*math.sqrt(1+t*t)
end

-- build an elementary projector from one of the
-- vectors in the nullspace of symmetric matrix
-- {{r, s}, {s,t}}, which is known to be rank defficient
-- returns the cos and the sin of the rotate
local function projector(r, s, t)
    if math.abs(r) > math.abs(t) then
        local h = hypot(r, s)
        if h > EPS then
            local inv_h = 1/h
            return s*inv_h, -r*inv_h
        else
            return 1, 0
        end
    else
        local h = hypot(t, s)
        if h > EPS then
            local inv_h = 1/h
            return t*inv_h, -s*inv_h
        else
            return 1, 0
        end
    end
end

-- returns the cos and sin of the rotate angle for U,
-- followed by the sx and sy of the scale S,
-- and omits the orthogonal matrix V
function _M.us(a, b, c, d)
    local ac = a*c
    local bd = b*d
    local a2 = a*a
    local b2 = b*b
    local c2 = c*c
    local d2 = d*d
    -- we have expressed things in a way that the
    -- discriminant is certainly non-negative even in the
    -- presence of numerical errors
    local D = hypot(.5*(a2+b2-c2-d2), ac+bd)
    local m = -.5*(a2+b2+c2+d2)
    local p = b2*c2+a2*d2-2*ac*bd
    local el0, el1
    if m < 0 then
        el0 = -m+D
        el1 = p/el0
    else
        el0 = 0
        el1 = 0
    end
    -- so now we have the
    local s0 = math.sqrt(el0) -- largest singular value
    if s0 > EPS then -- at least 1 singular value above threshold
        -- get projector from AAt - el0*I
        local cos, sin = projector(a2+b2-el0, ac+bd, c2+d2-el0)
        -- we will also use the
        local s1 = math.sqrt(el1) -- smallest singular value
        if s1 > EPS then -- both singular values are above threshold
            return cos, sin, s0, s1
        else -- only largest is above threshold
            return cos, sin, s0, 0
        end
    else  -- zero matrix
        return 1, 0, 0, 0
    end
end

return _M
