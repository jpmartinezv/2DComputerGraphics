local driver = require"driver"
local style = require"style"
local arc = require"arc"
local xform = require"xform"

local _M = driver.new()

local unpack = table.unpack
local floor = math.floor


local function xformtostring(xform)
    local a = xform[1]
    local b = xform[1+3]
    local c = xform[2]
    local d = xform[2+3]
    local e = xform[3]
    local f = xform[3+3]
    local t = ""
    -- factor scale and translate
    if b == 0 and c == 0 then
        if e ~= 0 or f ~= 0 then
            if f ~= 0 then
                t = string.format("translate(%g, %g)", e, f)
            else
                t = string.format("translate(%g)", e)
            end
        end
        if a == d then
            if a ~= 1 then
                t = t ~= "" and ":" .. t  or t
                t = string.format("scale(%g)", a) .. t
            end
        else
            t = t ~= "" and ":" .. t  or t
            t = string.format("scale(%g, %g)", a, d) .. t
        end
    else
        -- could also try to factor rotate, but not worth it
        t = string.format("affine(%g, %g, %g, %g, %g, %g)", a, c, e, b, d, f)
    end
    return t
end

local function printpaint(paint, mode, gradients, file)
    if paint.type == "solid" then
        local color = paint.data
        local r, g, b, a = unpack(color, 1, 4)
        a = a*paint.opacity
        file:write(string.format(' %s="rgb(%d,%d,%d)"',
            mode, r*255, g*255, b*255))
        if a < 1 then
            file:write(string.format(' %s-opacity="%g"', mode, a))
        end
    elseif paint.type == "lineargradient" or paint.type == "radialgradient" then
        file:write(string.format(' %s="url(#%s)"', mode, gradients[paint]))
        if paint.opacity < 1 then
            file:write(string.format(' %s-opacity="%g"', mode, paint.opacity))
        end
    else
        error("invalid paint type " .. tostring(paint.type))
    end
end

local function printstrokestyle(s, file)
    style.check(s)
    if type(s) == "number" then
        if s ~= 1 then
            file:write(string.format(' stroke-width="%g"', s))
        end -- default is 1
    else
        if s.width ~= 1 then
            file:write(string.format(' stroke-width="%g"', s.width))
        end -- default is 1
        if s.cap then
            file:write(' stroke-linecap="', s.cap, '"')
        end
        if s.join then
            file:write(' stroke-linejoin="', s.join, '"')
        end
        if s.miter_limit and s.miter_limit ~= 4 then
            file:write(string.format(' stroke-miterlimit="%g"', s.miter_limit))
        end -- default is 4
        if s.dash then
            if s.dash.initial_phase and s.dash.initial_phase ~= 0 then
                file:write(string.format(' stroke-dashoffset="%g"',
                    s.dash.initial_phase))
            end -- defualt is 0
            if s.dash.array then
                file:write(' stroke-dasharray="',
                    table.concat(s.dash.array, " "), '"')
            end
        end
    end
end

local function printradialgradient(paint, id, file)
    file:write('<radialGradient id="', id, '" gradientUnits="userSpaceOnUse"')
    local c = paint.data.center
    local f = paint.data.focus
    local r = paint.data.radius
    file:write(string.format(' cx="%g" cy="%g" fx="%g" fy="%g" r="%g"',
        c[1], c[2], f[1], f[2], r))
    file:write(string.format(' spreadMethod="%s"', paint.data.spread or "pad"))
    printxform(paint.xf, ' gradientTransform', file)
    file:write('>\n')
    printramp(paint.data.ramp, file)
    file:write('</radialGradient>\n')
end

local write = {}

local rvgcommand = {
    begin_open_contour = "M",
    begin_closed_contour = "M",
    linear_segment = "L",
    quadratic_segment = "Q",
    rational_quadratic_segment = "R",
    cubic_segment = "C",
    end_closed_contour = "Z",
}

function write.path(shape, file)
    local previous = ""
    file:write("path{")
    for i,v in ipairs(shape.instructions) do
        local o = shape.offsets[i]
        local s = rvgcommand[v]
        if s then
            if v ~= previous then
                file:write(s, ",")
            end
            if s == "M" then
                file:write(shape.data[o+1], ",", shape.data[o+2], ",")
            elseif s == "L" then
                file:write(shape.data[o+2], ",", shape.data[o+3], ",")
            elseif s == "Q" then
                file:write(shape.data[o+2], ",", shape.data[o+3], ",")
                file:write(shape.data[o+4], ",", shape.data[o+5], ",")
            elseif s == "C" then
                file:write(shape.data[o+2], ",", shape.data[o+3], ",")
                file:write(shape.data[o+4], ",", shape.data[o+5], ",")
                file:write(shape.data[o+6], ",", shape.data[o+7], ",")
            elseif s == "R" then
                file:write(shape.data[o+2], ",", shape.data[o+3], ",")
                file:write(shape.data[o+4], ",", shape.data[o+5], ",")
                file:write(shape.data[o+6], ",")
            end
            previous = v
        end
    end
    file:write("}")
end

function write.polygon(shape, file)
    file:write("polygon{", table.concat(shape.data, ","), "}")
end

function write.triangle(shape, file)
    file:write("triangle(",
        shape.x1, ",", shape.y1, ",",
        shape.x2, ",", shape.y2, ",",
        shape.x3, ",", shape.y3, ")")
end

function write.circle(shape, file)
    file:write("circle(",
        shape.cx, ",", shape.cy, ",", shape.r, ")")
end

function writecolor(color, file)
    local r, g, b, a = unpack(color)
    r = floor(r*255+.5)
    g = floor(g*255+.5)
    b = floor(b*255+.5)
    a = floor(a*255+.5)
    if a ~= 255 then
        file:write("rgba8(", r, ",", g, ",", b, ",", a, ")")
    else
        file:write("rgb8(", r, ",", g, ",", b, ")")
    end
end

local function writepoint(point, file)
    file:write("p2(", point[1], ",", point[2], ")")
end

local function writeramp(ramp, file)
    file:write("ramp{")
    file:write('spread=spread["',ramp.spread, '"];')
    for i = 1, #ramp, 2 do
        file:write(ramp[i], ",")
        writecolor(ramp[i+1], file)
        file:write(",")
    end
    file:write('}')
end

local function writexformopacity(xf, o, file)
    if o ~= 1 then
        file:write(",identity(),", o)
    end
end

function write.radialgradient(paint, file)
    file:write("radialgradient(")
    writeramp(paint.data.ramp, file)
    file:write(",")
    writepoint(paint.data.center, file)
    file:write(",")
    writepoint(paint.data.focus, file)
    file:write(",", paint.data.radius)
    writexformopacity(paint.xf, paint.opacity, file)
    file:write(")")
end

function write.lineargradient(paint, file)
    file:write("lineargradient(")
    writeramp(paint.data.ramp, file)
    file:write(",")
    writepoint(paint.data.p1, file)
    file:write(",")
    writepoint(paint.data.p2, file)
    writexformopacity(paint.xf, paint.opacity, file)
    file:write(")")
end

function write.solid(paint, file)
    file:write("solid(")
    writecolor(paint.data, file)
    if paint.opacity ~= 1 then
        file:write(",", paint.opacity, ")")
    else
        file:write(")")
    end
end

function write.fill(element, file)
    local s = xformtostring(element.shape.xf)
    local p = xformtostring(element.paint.xf)
    file:write("    fill(")
    write[element.shape.type](element.shape, file)
    if s ~= "" and s ~= p then file:write(":", s) end
    file:write(",\n      ")
    write[element.paint.type](element.paint, file)
    if p ~= "" and p ~= s then file:write(":", p) end
    if s ~= "" and s == p then file:write("):",s, ",")
    else file:write("),\n") end
end

function write.eofill(element, file)
    local s = xformtostring(element.shape.xf)
    local p = xformtostring(element.paint.xf)
    file:write("    eofill(")
    write[element.shape.type](element.shape, file)
    if s ~= "" and s ~= p then file:write(":", s) end
    file:write(",\n      ")
    write[element.paint.type](element.paint, file)
    if p ~= "" and p ~= s then file:write(":", p) end
    if s ~= "" and s == p then file:write("):",s, ",")
    else file:write("),\n") end
end

function _M.render(scene, viewport, file)
    local vxmin, vymin, vxmax, vymax = unpack(viewport, 1, 4)
    file:write("local _M = {}\n\n")
    file:write("function _M.viewport(drv)\n")
    file:write("  return drv.viewport(", table.concat(viewport, ","), ")\n")
    file:write("end\n\n")
    file:write("function _M.window(drv)\n")
    file:write("  return drv.window(", table.concat(viewport, ","), ")\n")
    file:write("end\n\n")
    file:write("function _M.scene(drv)\n")
    file:write("  local _ENV = drv\n")
    file:write("  local s = {\n")
    local s = xformtostring(scene.xf)
    for i,element in ipairs(scene.elements) do
        local callback = assert(write[element.type],
            "no handler for " .. element.type)
        callback(element, file)
    end
    file:write("  }\n")
    file:write("  return drv.scene(s)")
    if s ~= "" then file:write(":", s) end
    file:write("\nend\n\n")
    file:write("return _M\n")
end

return _M
