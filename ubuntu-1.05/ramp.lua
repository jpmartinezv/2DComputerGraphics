local _M = { meta = {} }

local ramp_meta = _M.meta
ramp_meta.__index = {}
ramp_meta.name = "ramp"

local color = require"color"

-- the color ramp is an array of offset/color pairs
-- { t1, color1, t2, color2 ... tn colorn }
function ramp_meta.__tostring(self)
    return "ramp"
end

function _M.ramp(ramp)
    assert(type(ramp) == "table", "expecting table")
    local n = #ramp
    assert(n > 0, "empty ramp")
    local copy = {}
    local last = -1
    for i=1, n, 2 do
        assert(type(ramp[i]) == "number", "stop offset not a number")
        assert(ramp[i] >= last, "stop offset out of order")
        assert(getmetatable(ramp[i+1]) == color.meta, "invalid stop color")
        last = ramp[i]
        if last < 0 then last = 0 end
        if last > 1 then last = 1 end
        copy[i] = last
        copy[i+1] = ramp[i+1]
    end
    copy.spread = ramp.spread
    return setmetatable(copy, ramp_meta)
end

return _M
