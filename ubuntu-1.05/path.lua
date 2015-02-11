local _M = { meta = {} }

local xform = require"xform"
local command = require"command"
local style = require"style"
local arc = require"arc"

local overload = require"overload"

local unpack = table.unpack

local path_meta = _M.meta
path_meta.__index = {}
path_meta.name = "path"

-- Our internal representation of paths consists of an array
-- with instructions, an array of offsets, and an array with data.
-- Each instruction has a corresponding offset entry
-- pointing into the data array.  There are two interfaces to add
-- information to the path.  The traditional interface is
-- based on move_to, line_to, close_path etc commands. These
-- are converted to our internal representation in a way
-- that guarantees consistency.  The internal representation
-- can be used to directly add instructions and associated
-- data, without much in the way of consistency checks.  The
-- internal and traditional interfaces should not be mixed
-- when adding information to a path, since they depend on
-- some internal state.
--
-- Contours are bracketed by a begin/end pair of
-- instructions.  The pair can be either open or closed.
-- (For example, depending on whether there was a close_path
-- command or not). The offset of each instruction points to
-- the start of the instruction's data, so that all
-- instructions can be processed in parallel if need be.
-- Many instructions share common data. In the table below,
-- the data that each instruction needs when being added to
-- a path is marked with '+'. The data to which the
-- instruction's offset points is marked with a '^'
--
-- BOC ^len +x0 +y0                    ; begin_open_contour
-- BCC ^len +x0 +y0                    ; begin_closed_contour
-- ECC ^len                            ; end_closed_contour
-- EOC ^len                            ; end_open_contour
-- LS  ^x0 y0 +x1 +y1                  ; linear_segment
-- QS  ^x0 y0 +x1 +y1 +x2 +y2          ; quadratic_segment
-- RQS ^x0 y0 +x1 +y1 +w1 +x2 +y2      ; rational_quadratic_segment
-- CS  ^x0 y0 +x1 +y1 +x2 +y2 +x3 +y3  ; cubic_segment
-- LSL ^x0 y0 +len +x1 +y1             ; linear_segment_with_length
-- BS  ^+s +t                          ; begin_segment
-- ES  ^+s +t                          ; end_segment
--
-- The len in the begin/end contour instructions allows us
-- to find the matching end/begin instruction and is computed
-- automatically.
-- The data for begin/end segment is such that s/t should be the
-- curvature at the begin/end of the enclosed segment
-- The len for linear_segment_with_length should be set to
-- sqrt((x0-x1)^2+(y0-y1)^2).
--
-- The idea is that the representation is reversible in the
-- sense that traversing it forward or backward is equally
-- easy.
--
-- Paths also have room for a style describing the stoke
-- styles and a xform

function path_meta.__index.stroke(path, s)
    assert(not path.style, "repeated stroking not supported")
    return setmetatable({
        type = "path", -- shape type
        instructions = path.instructions,
        offsets = path.offsets,
        xf = path.xf,
        data = path.data,
        style = style.copy(s),
    }, path_meta)
end

_M.path = overload.handler("path.path")

overload.register("path.path", function()
    return setmetatable({
        type = "path", -- shape type
        instructions = {},
        offsets = {},
        data = {},
        xf = xform.identity()
    }, path_meta)
end)

local append = {}

local function push_data(path, ...)
    local n = #path.data
    for i = 1, select("#", ...) do
        path.data[n+i] = select(i, ...)
    end
end

local function pop_end_contour_sentinel(path)
    path.instructions[#path.instructions] = nil
    path.data[#path.data] = nil
    path.offsets[#path.offsets] = nil
end

local function push_instruction(path, type, rewind)
    rewind = rewind or -2
    local instructions_n = #path.instructions+1
    local data_n = #path.data+1
    path.instructions[instructions_n] = type
    path.offsets[instructions_n] = data_n+rewind
end

local function begin_contour(path, type, x0, y0)
    path.ibegin_contour = #path.instructions+1
    path.dbegin_contour = #path.data+1
    push_instruction(path, type, 0)
    push_data(path, 0, x0, y0)
end

function path_meta.__index.begin_open_contour(path, len, x0, y0)
    -- ignore len: computed automatically
    begin_contour(path, "begin_open_contour", x0, y0)
end

function path_meta.__index.begin_closed_contour(path, len, x0, y0)
    -- ignore len: computed automatically
    begin_contour(path, "begin_closed_contour", x0, y0)
end

local function end_contour(path, type)
    local len = #path.instructions+1 - path.ibegin_contour
    path.data[path.dbegin_contour] = len
    push_instruction(path, type, 0)
    push_data(path, len)
end

function path_meta.__index.end_open_contour(path, len)
    -- ignore len: computed automatically
    return end_contour(path, "end_open_contour")
end

function path_meta.__index.end_closed_contour(path, len)
    -- ignore len: computed automatically
    return end_contour(path, "end_closed_contour")
end

local function push_end_contour_sentinel(path)
    path:end_open_contour()
end

local function ensure_non_empty(path)
    local n = #path.instructions
    -- first contour or previous contour has been closed
    if n == 0 or path.instructions[n] == "end_close_contour" then
        local x0 = path.current_x
        local y0 = path.current_y
        append.move_to_abs(path, x0, y0)
    end
end

local function set_previous(path, x, y)
    path.previous_x = x
    path.previous_y = y
end

local function set_current(path, x, y)
    path.current_x = x
    path.current_y = y
end

local function set_start(path, x, y)
    path.start_x = x
    path.start_y = y
end

function path_meta.__index.linear_segment(path, x0, y0, x1, y1)
    -- ignore x0, y0: comes from previous instruction
    push_instruction(path, "linear_segment")
    push_data(path, x1, y1)
end

function path_meta.__index.quadratic_segment(path, x0, y0, x1, y1, x2, y2)
    -- ignore x0, y0: comes from previous instruction
    push_instruction(path, "quadratic_segment")
    push_data(path, x1, y1, x2, y2)
end

function path_meta.__index.rational_quadratic_segment(path, x0, y0, x1, y1, w1,
        x2, y2)
    -- ignore x0, y0: comes from previous instruction
    push_instruction(path, "rational_quadratic_segment")
    push_data(path, x1, y1, w1, x2, y2)
end

function path_meta.__index.cubic_segment(path, x0, y0, x1, y1, x2, y2, x3, y3)
    -- ignore x0, y0: comes from previous instruction
    push_instruction(path, "cubic_segment")
    push_data(path, x1, y1, x2, y2, x3, y3)
end

function append.squad_to_abs(path, x2, y2)
    local x1 = 2*path.current_x - path.previous_x
    local y1 = 2*path.current_y - path.previous_y
    return append.quad_to_abs(path, x1, y1, x2, y2)
end

function append.squad_to_rel(path, x2, y2)
    x2 = x2 + path.current_x
    y2 = y2 + path.current_y
    return append.squad_to_abs(path, x2, y2)
end

function append.rquad_to_abs(path, x1, y1, w1, x2, y2)
    ensure_non_empty(path)
    pop_end_contour_sentinel(path)
    path:rational_quadratic_segment(_, _, x1, y1, w1, x2, y2)
    push_end_contour_sentinel(path)
    set_previous(path, x2, y2)
    set_current(path, x2, y2)
end

function append.rquad_to_rel(path, x1, y1, w1, x2, y2)
    x1 = x1 + path.current_x*w1
    y1 = y1 + path.current_y*w1
    x2 = x2 + path.current_x
    y2 = y2 + path.current_y
    return append.rquad_to_abs(path, x1, y1, w1, x2, y2)
end

function append.svgarc_to_abs(path, rx, ry, rot_ang, fa, fs, x2, y2)
    local x0, y0 = path.current_x, path.current_y
    local x1, y1, w1 = arc.torational(x0, y0, rx, ry, rot_ang, fa, fs, x2, y2)
    return append.rquad_to_abs(path, x1, y1, w1, x2, y2)
end

function append.svgarc_to_rel(path, rx, ry, rot_ang, fa, fs, x2, y2)
    x2 = x2 + path.current_x
    y2 = y2 + path.current_y
    return append.svgarc_to_abs(path, rx, ry, rot_ang, fa, fs, x2, y2)
end

function append.cubic_to_abs(path, x1, y1, x2, y2, x3, y3)
    ensure_non_empty(path)
    pop_end_contour_sentinel(path)
    path:cubic_segment(_, _, x1, y1, x2, y2, x3, y3)
    push_end_contour_sentinel(path)
    set_previous(path, x2, y2)
    set_current(path, x3, y3)
end

function append.cubic_to_rel(path, x1, y1, x2, y2, x3, y3)
    x1 = x1 + path.current_x
    y1 = y1 + path.current_y
    x2 = x2 + path.current_x
    y2 = y2 + path.current_y
    x3 = x3 + path.current_x
    y3 = y3 + path.current_y
    return append.cubic_to_abs(path, x1, y1, x2, y2, x3, y3)
end

function append.hline_to_abs(path, x1)
    local y1 = path.current_y
    return append.line_to_abs(path, x1, y1)
end

function append.hline_to_rel(path, x1)
    x1 = x1 + path.current_x
    return append.hline_to_abs(path, x1)
end

function append.line_to_abs(path, x1, y1)
    ensure_non_empty(path)
    pop_end_contour_sentinel(path)
    path:linear_segment(_, _, x1, y1)
    push_end_contour_sentinel(path)
    set_previous(path, x1, y1)
    set_current(path, x1, y1)
end

function append.line_to_rel(path, x1, y1)
    x1 = x1 + path.current_x
    y1 = y1 + path.current_y
    return append.line_to_abs(path, x1, y1)
end

function append.move_to_abs(path, x0, y0)
    path:begin_open_contour(_, x0, y0);
    push_end_contour_sentinel(path);
    set_start(path, x0, y0);
    set_current(path, x0, y0);
    set_previous(path, x0, y0);
end

function append.move_to_rel(path, x0, y0)
    x0 = x0 + path.current_x
    y0 = y0 + path.current_y
    return append.move_to_abs(path, x0, y0)
end

function append.quad_to_abs(path, x1, y1, x2, y2)
    ensure_non_empty(path)
    pop_end_contour_sentinel(path)
    path:quadratic_segment(_, _, x1, y1, x2, y2)
    push_end_contour_sentinel(path)
    set_previous(path, x1, y1)
    set_current(path, x2, y2)
end

function append.quad_to_rel(path, x1, y1, x2, y2)
    x1 = x1 + path.current_x
    y1 = y1 + path.current_y
    x2 = x2 + path.current_x
    y2 = y2 + path.current_y
    return append.quad_to_abs(path, x1, y1, x2, y2)
end

function append.scubic_to_abs(path, x1, y1, x2, y2)
    local x0 = 2*path.current_x - path.previous_x
    local y0 = 2*path.current_y - path.previous_y
    return append.cubic_to_abs(path, x0, y0, x1, y1, x2, y2)
end

function append.scubic_to_rel(path, x1, y1, x2, y2)
    x1 = x1 + path.current_x
    y1 = y1 + path.current_y
    x2 = x2 + path.current_x
    y2 = y2 + path.current_y
    return append.scubic_to_abs(path, x1, y1, x2, y2)
end

function append.vline_to_abs(path, y1)
    local x1 = path.current_x
    return append.line_to_abs(path, x1, y1)
end

function append.vline_to_rel(path, y1)
    y1 = y1 + path.current_y
    return append.vline_to_abs(path, y1)
end

function append.close_path(path)
    path.instructions[path.ibegin_contour] = "begin_closed_contour"
    path.instructions[#path.instructions] = "end_closed_contour"
end

function path_meta.__index.open(path)
    path.current_x = 0
    path.current_y = 0
    path.previous_x = 0
    path.previous_y = 0
    path.start_x = 0
    path.start_y = 0
    path.ibegin_contour = 1
    path.dbegin_contour = 1
end

function path_meta.__index.close(path)
    path.current_x = nil
    path.current_y = nil
    path.previous_x = nil
    path.previous_y = nil
    path.start_x = nil
    path.start_y = nil
    path.ibegin_contour = nil
    path.dbegin_contour = nil
end

overload.register("path.path", function(svgpath)
    local path = _M.path()
    path:open()
    local first = 1
    local c = svgpath[first]
    first = first + 1
    while c do
        assert(command.shortname[c], "expected command, got " .. tostring(c))
        local count = command.nargs[c]
        local last = first + count
        append[c](path, unpack(svgpath, first, last-1))
        first = last
        if type(svgpath[first]) ~= "number" then
            c = svgpath[first]
            first = first + 1
        else
            -- multiple commands of a given kind can follow
            -- each other without repetition
            -- the exception is move_to, which gets
            -- transformed to a line_to
            if c == "move_to_abs" then
                c = "line_to_abs"
            elseif c == "move_to_rel" then
                c = "line_to_rel"
            end
        end
    end
    path:close()
    return setmetatable(path, path_meta)
end, "table")

local function newxform(path, xf)
    return setmetatable({
        type = "path", -- shape type
        instructions = path.instructions,
        offsets = path.offsets,
        data = path.data,
        xf = xf,
        style = path.style
    }, path_meta)
end

local ndata = { -- if instruction has n data elements, store n-1 
    begin_open_contour = 2,
    begin_closed_contour = 2,
    end_closed_contour = 0,
    end_open_contour = 0,
    linear_segment = 3,
    quadratic_segment = 5,
    rational_quadratic_segment = 6,
    cubic_segment = 7,
    linear_segment_with_length = 4,
    begin_segment = 1,
    end_segment = 1
}

function path_meta.__index.iterate(path, forward)
    for index, instruction in ipairs(path.instructions) do
        local offset = path.offsets[index]
        -- invoke method with same name as
        -- instruction from forward table, passing all its data
        local callback = assert(forward[instruction], 
            "unhandled instruction '" .. instruction .. "'")
        callback(forward, unpack(path.data, offset, offset+ndata[instruction]))
    end
end

function path_meta.__index.transform(path, xf)
    return newxform(path, xf * path.xf)
end

function path_meta.__index.translate(path, ...)
    return newxform(path, xform.translate(...) * path.xf)
end

function path_meta.__index.scale(path, ...)
    return newxform(path, xform.scale(...) * path.xf)
end

function path_meta.__index.rotate(path, ...)
    return newxform(path, xform.rotate(...) * path.xf)
end

function path_meta.__index.affine(path, ...)
    return newxform(path, xform.affine(...) * path.xf)
end

function path_meta.__index.linear(path, ...)
    return newxform(path, xform.linear(...) * path.xf)
end

function path_meta.__index.windowviewport(path, ...)
    return newxform(path, xform.windowviewport(...) * path.xf)
end

return _M
