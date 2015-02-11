local _M = { meta = {} }

local window_meta = _M.meta
window_meta.__index = {}
window_meta.name = "window"

local unpack = table.unpack

function window_meta.__tostring(self)
    return string.format("window{%g,%g,%g,%g}", unpack(self, 1, 4))
end

function _M.window(xmin, ymin, xmax, ymax)
    return setmetatable({xmin, ymin, xmax, ymax}, window_meta)
end

return _M
