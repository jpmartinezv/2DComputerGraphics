local _M = { meta = {} }

local xform = require"xform"

local scene_meta = _M.meta
scene_meta.__index = {}
scene_meta.name = "scene"

local isclip = {
    clip = true,
    eoclip = true
}

local isfill = {
    fill = true,
    eofill = true
}

-- a scene contains all elements to be drawn
-- an element typically contain a filled primitive.
-- the fill rule is encoded in the element type
-- it can be "fill" for non-zero rule or "eofill" for the even-odd rule
-- the filled primitive contains a shape to be filled and a paint.
-- besides filled primitives, the scene can also contain clip regions.
-- a clip region definition starts with a pushclip element.
-- it is activated by an activateclip element.
-- the inside-outside tests of the primitives that are under
-- the effect of a clip path are only considered to succeed
-- when the inside-outside test for the clip path also succeeds.
-- the clip region is deactivated by a popclip element.
-- clip regions start empty with the pushclip, and are
-- formed by the union of all regions until the activateclip element.
-- the primitive regions are given by "clip" and "eoclip" elements.
-- these contain shapes with interiors defined by the
-- "non-zero" or the "even-odd" rules, respectively.
-- clip regions can be clipped themselves, naturally.
-- the following grammar defines a valid scene:
--
-- scene ::=
--     paintedprimitive*
--
-- paintedprimitive ::=
--     fill |
--     eofill |
--     pushclip clipregion* activateclip paintedprimitive* popclip
--
-- clipregion ::=
--     clip |
--     eoclip |
--     pushclip clipregion* activateclip clipregion* popclip
--
-- a scene also has a xform that affects all elments in the scene

function _M.scene(elements)
    local copied_elements = {}
    local depth = 0
    local inactive = 0
    for i,element in ipairs(elements) do
        if element.type == "pushclip" then
            depth = depth + 1
            inactive = inactive + 1
        elseif element.type == "popclip" then
            assert(depth > 0, "no clip to pop")
            depth = depth - 1
        elseif element.type == "activateclip" then
            assert(inactive > 0, "no clip to activate")
            inactive = inactive - 1
        elseif isclip[element.type] then
            assert(inactive > 0, "expecting fill definition")
        elseif isfill[element.type] then
            assert(inactive == 0, "expecting clip definition")
        end
        copied_elements[i] = element
    end
    return setmetatable({
        elements = copied_elements,
        xf = xform.identity(),
    }, scene_meta)
end

local function newxform(scene, xf)
    return setmetatable({
        elements = scene.elements,
        xf = xf,
    }, scene_meta)
end

function scene_meta.__index.transform(scene, xf)
    return newxform(scene, xf * scene.xf)
end

function scene_meta.__index.translate(scene, ...)
    return newxform(scene, xform.translate(...) * scene.xf)
end

function scene_meta.__index.scale(scene, ...)
    return newxform(scene, xform.scale(...) * scene.xf)
end

function scene_meta.__index.rotate(scene, ...)
    return newxform(scene, xform.rotate(...) * scene.xf)
end

function scene_meta.__index.affine(scene, ...)
    return newxform(scene, xform.affine(...) * scene.xf)
end

function scene_meta.__index.linear(scene, ...)
    return newxform(scene, xform.linear(...) * scene.xf)
end

function scene_meta.__index.windowviewport(scene, ...)
    return newxform(scene, xform.windowviewport(...) * scene.xf)
end

return _M
