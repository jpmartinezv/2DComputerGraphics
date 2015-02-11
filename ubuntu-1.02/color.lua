local _M = { meta = {} }

local color_meta = _M.meta
color_meta.__index = {}
color_meta.name = "color"

local unpack = table.unpack

function color_meta.__tostring(self)
    return string.format("color{%g,%g,%g,%g}", unpack(self, 1, 4))
end

function _M.rgb(r, g, b, a)
    a = a or 1
    assert(type(r) == "number" and r <= 1 and r >= 0, "invalid red component")
    assert(type(g) == "number" and g <= 1 and g >= 0, "invalid green component")
    assert(type(b) == "number" and b <= 1 and b >= 0, "invalid blue component")
    assert(type(a) == "number" and a <= 1 and a >= 0, "invalid alpha component")
    return setmetatable({r, g, b, a}, color_meta)
end

_M.rgba = _M.rgb

local inv_255 = 1/255
function _M.rgb8(r, g, b, a)
    a = a or 255
    assert(type(r) == "number" and r <= 255 and r >= 0, "invalid red component")
    assert(type(g) == "number" and g <= 255 and g >= 0, "invalid gren component")
    assert(type(b) == "number" and b <= 255 and b >= 0, "invalid blue component")
    assert(type(a) == "number" and a <= 255 and a >= 0, "invalid alpha component")
    return setmetatable({r*inv_255, g*inv_255, b*inv_255, a*inv_255}, color_meta)
end

_M.rgba8 = _M.rgb8

_M.rgbx = function(s)
    local r, g, b
    local n = #s
    assert(n == 3 or n == 6, "invalid hex color " .. s)
    if #s == 3 then
        r, g, b = string.match(s, "(%x)(%x)(%x)")
        assert(r and g and b, "invalid hex color " .. s)
        r = assert(tonumber(r, 16), "invalid red component")*17
        g = assert(tonumber(g, 16), "invalid green component")*17
        b = assert(tonumber(b, 16), "invalid blue component")*17
    else
        r, g, b = string.match(s, "(%x%x)(%x%x)(%x%x)")
        assert(r and g and b, "invalid hex color " .. s)
        r = assert(tonumber(r, 16), "invalid red component")
        g = assert(tonumber(g, 16), "invalid green component")
        b = assert(tonumber(b, 16), "invalid blue component")
    end
    return _M.rgb8(r, g, b)
end

function _M.gray(v, a)
    a = a or 1
    assert(type(v) == "number", "invalid value component")
    assert(type(a) == "number", "invalid alpha component")
    return setmetatable({v, v, v, a or 1}, color_meta)
end

function _M.hsv(h, s, v, a)
    a = a or 1
    if s > 0 then
        if h >= 1 then h = 0 end
        local p = math.floor(h)
        local f = h - p
        local m = v*(1-s)
        local n = v*(1-s*f)
        local k = v*(1-s*(1-f))
        if p == 0 then return setmetatable({v, k, m, a}, color_meta)
        elseif p == 1 then return setmetatable({n, v, m, a}, color_meta)
        elseif p == 2 then return setmetatable({m, v, k, a}, color_meta)
        elseif p == 3 then return setmetatable({m, n, v, a}, color_meta)
        elseif p == 4 then return setmetatable({k, m, v, a}, color_meta)
        elseif p == 5 then return setmetatable({v, m, n, a}, color_meta)
        else return setmetatable({0, 0, 0, a}, color_meta) end
    else
        return setmetatable({v, v, v, a}, color_meta)
    end
end

return _M
