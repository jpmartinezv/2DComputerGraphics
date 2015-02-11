local _M = {}

local function merge(source, dest)
    for i,v in pairs(source) do
        dest[i] = v
    end
end

-- this builds a minimal driver from all the modules
-- the idea is to initialize your module table with new()
-- and fill in or replace the functions that you need in a
-- particular new driver
function _M.new()
    local newM = {}
    merge(require"path", newM)
    merge(require"circle", newM)
    merge(require"polygon", newM)
    merge(require"triangle", newM)
    newM.command = require"command"
    merge(newM.command.longname, newM)
    newM.spread = require"spread"
    local color = require"color"
    merge(color, newM)
    local paint = require"paint"
    merge(paint, newM)
    newM.named = {
        paint = paint.named,
        color = color.named,
    }
    merge(require"ramp", newM)
    newM.image = require"image"
    newM.base64 = require"base64"
    merge(require"xform", newM)
    merge(require"vector", newM)
    newM.p2 = newM.vector
    merge(require"viewport", newM)
    merge(require"window", newM)
    merge(require"element", newM)
    merge(require"scene", newM)
    local style = require"style"
    newM.cap = style.cap
    newM.join = style.join
    return newM
end

return _M
