local _M = { meta = {} }

local element_meta = _M.meta
element_meta.__index = {}
element_meta.name = "element"

local xform = require"xform"

-- as described in the scene module, elements can be of the
-- following types
--     fill, eofill, clip, eoclip, pushclip, activateclip, popclip
-- elements fill, eofill, clip, and eoclip each contain a shape
-- elements fill and eofill contain, in addition, a paint
function _M.fill(shape, paint)
    return setmetatable({
        type = "fill",
        shape = shape,
        paint = paint
    }, element_meta)
end

function _M.eofill(shape, paint)
    return setmetatable({
        type = "eofill",
        shape = shape,
        paint = paint
    }, element_meta)
end

function _M.clip(shape)
    return setmetatable({
        type = "clip",
        shape = shape
    }, element_meta)
end

function _M.eoclip(shape)
    return setmetatable({
        type = "eoclip",
        shape = shape
    }, element_meta)
end

function _M.pushclip(depth)
    return setmetatable({
        type = "pushclip",
        depth = depth
    }, element_meta)
end

_M.push = _M.pushclip -- alias

function _M.popclip(depth)
    return setmetatable({
        type = "popclip",
        depth = depth
    }, element_meta)
end

_M.pop = _M.popclip -- alias

function _M.activateclip(depth)
    return setmetatable({
        type = "activateclip",
        depth = depth
    }, element_meta)
end

_M.activate = _M.activateclip
_M.commit = _M.activateclip

local function newxform(element, xf)
    return setmetatable({
        type = element.type,
        -- pushclip, activateclip and popclip do not contain shape or paint
        -- clip and eoclip do not contain paint
        -- so we only transform if these objects are there
        shape = element.shape and element.shape:transform(xf),
        paint = element.paint and element.paint:transform(xf),
        depth = element.depth
    }, element_meta)
end

function element_meta.__index.transform(element, xf)
    return newxform(element, xf)
end

function element_meta.__index.translate(element, ...)
    return newxform(element, xform.translate(...))
end

function element_meta.__index.scale(element, ...)
    return newxform(element, xform.scale(...))
end

function element_meta.__index.rotate(element, ...)
    return newxform(element, xform.rotate(...))
end

function element_meta.__index.affine(element, ...)
    return newxform(element, xform.affine(...))
end

function element_meta.__index.linear(element, ...)
    return newxform(element, xform.linear(...))
end

function element_meta.__index.windowviewport(element, ...)
    return newxform(element, xform.windowviewport(...))
end

return _M
