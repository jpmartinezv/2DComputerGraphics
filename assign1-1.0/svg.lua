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
                t = t .. string.format(" scale(%g)", a)
            end
        else
            t = t .. string.format(" scale(%g, %g)", a, d)
        end
    else
        t = string.format("matrix(%g, %g, %g, %g, %g, %g)", a, b, c, d, e, f)
    end
    return t
end

local function cordrvgtovsg(xform, vymax)
    local a = xform[1]
    local b = xform[1+3]
    local c = xform[2]
    local d = xform[2+3]
    local e = xform[3]
    local f = xform[3+3]
    local t = ""
    t = t .. "<g transform=\"" .. string.format("translate(%g, %g)", e, -f+vymax)
    t = t .. string.format(" scale(%g, %g)", a, -1*d)
    t = t .. "\">\n"
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

function writestopcolor(color, file)
    local r, g, b, a = unpack(color)
    r = floor(r*255)
    g = floor(g*255)
    b = floor(b*255)
    a  = a
    file:write(" stop-color=\"rgb(", r, ",", g, ",", b, ")\"", " stop-opacity=\"", a , "\"")
end

local mapgradient = {}

local function printlineargradient(paint, id, file)
    file:write('<linearGradient id="', id, '" gradientUnits="userSpaceOnUse"')
    local p1 = paint.data.p1
    local p2 = paint.data.p2
    local f = paint.data.focus
    file:write(string.format(' x1="%g" y1="%g" x2="%g" y2="%g"',
        p1[1], p1[2], p2[1], p2[2]))
    file:write(string.format(' spreadMethod="%s"', paint.data.spread or "pad"))
    
    if paint.xf ~= nil then file:write(" gradientTransform=\"", xformtostring(paint.xf), "\"") end
    
    file:write('>\n')
    for i = 1,#paint.data.ramp,2 do
        file:write("<stop offset=\"" .. paint.data.ramp[i], "\"")
        writestopcolor(paint.data.ramp[i+1], file)
        file:write("/>\n")
    end
    file:write('</linearGradient>\n')
end

local function printradialgradient(paint, id, file)
    file:write('<radialGradient id="', id, '" gradientUnits="userSpaceOnUse"')
    local c = paint.data.center
    local f = paint.data.focus
    local r = paint.data.radius
    file:write(string.format(' cx="%g" cy="%g" fx="%g" fy="%g" r="%g"',
        c[1], c[2], f[1], f[2], r))
    file:write(string.format(' spreadMethod="%s"', paint.data.spread or "pad"))

    if paint.xf ~= nil then file:write(" gradientTransform=\"", xformtostring(paint.xf), "\"") end

    file:write('>\n')
    for i = 1,#paint.data.ramp,2 do
        file:write("<stop offset=\"" .. paint.data.ramp[i], "\"")
        writestopcolor(paint.data.ramp[i+1], file)
        file:write("/>\n")
    end
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
    file:write(" d=\"")
    for i,v in ipairs(shape.instructions) do
        local o = shape.offsets[i]
        local s = rvgcommand[v]
        if s then
            if v ~= previous then
                file:write(s, " ")
            end
            if s == "M" then
                file:write(shape.data[o+1], " ", shape.data[o+2], " ")
            elseif s == "L" then
                file:write(shape.data[o+2], " ", shape.data[o+3], " ")
            elseif s == "Q" then
                file:write(shape.data[o+2], " ", shape.data[o+3], " ")
                file:write(shape.data[o+4], " ", shape.data[o+5], " ")
            elseif s == "C" then
                file:write(shape.data[o+2], " ", shape.data[o+3], " ")
                file:write(shape.data[o+4], " ", shape.data[o+5], " ")
                file:write(shape.data[o+6], " ", shape.data[o+7], " ")
            elseif s == "R" then
                file:write(shape.data[o+2], " ", shape.data[o+3], " ")
                file:write(shape.data[o+4], " ", shape.data[o+5], " ")
                file:write(shape.data[o+6], " ")
            end
            previous = v
        end
    end
    file:write("\"")
end

function write.polygon(shape, file)
    file:write(" points=\"", table.concat(shape.data, " "), "\"")
end

function write.triangle(shape, file)
    file:write(" points=\"",
        shape.x1, " ", shape.y1, " ",
        shape.x2, " ", shape.y2, " ",
        shape.x3, " ", shape.y3, "\"")
end

function write.circle(shape, file)
    file:write(
        " cx=\"", shape.cx, "\"",
        " cy=\"", shape.cy, "\"",
        " r=\"", shape.r, "\"")
end

function writecolor(color, file)
    local r, g, b, a = unpack(color)
    r = floor(r*255+.5)
    g = floor(g*255+.5)
    b = floor(b*255+.5)
    a = floor(a*255+.5)
    if a ~= 255 then
        file:write(" fill=\"rgb(", r, ",", g, ",", b, ")\"", " fill-opacity=\"", string.format("%.6f", a/255.0) , "\"")
    else
        file:write(" fill=\"rgb(", r, ",", g, ",", b, ")\"")
    end
end

function write.radialgradient(paint, id, file)
    if paint.opacity ~= 1 then
        file:write(" fill=\"url(#", mapgradient[id], ")\"", " fill-opacity=\"",  paint.opacity , "\"" )
    else
        file:write(" fill=\"url(#", mapgradient[id], ")\"")
    end
end

function write.lineargradient(paint, id, file)
    if paint.opacity ~= 1 then
        file:write(" fill=\"url(#", mapgradient[id], ")\"", " fill-opacity=\"",  paint.opacity , "\"" )
    else
        file:write(" fill=\"url(#", mapgradient[id], ")\"")
    end
end

function write.solid(paint, id, file)
    writecolor(paint.data, file)
    if paint.opacity ~= 1 then
        file:write(" fill-opacity=\"", paint.opacity, "\"")
    end
end

local mapshape = {}
mapshape["triangle"] = "polygon";
mapshape["polygon"] = "polygon";
mapshape["circle"] = "circle";
mapshape["path"] = "path";

function write.fill(element, id, file)
    local s = xformtostring(element.shape.xf)
    file:write("<" .. mapshape[element.shape.type] .. " id=\"" .. id .. "\"")
    write[element.paint.type](element.paint, id, file)
    if s ~= "" then file:write(" transform=\"", s, "\"") end
    write[element.shape.type](element.shape, file)
    file:write("/>\n") 
end

function write.eofill(element, id, file)
    local s = xformtostring(element.shape.xf)
    file:write("<" .. mapshape[element.shape.type] .. " id=\"" .. id .. "\"")
    file:write(" fill-rule=\"evenodd\"")
    write[element.paint.type](element.paint, id, file)
    if s ~= "" then file:write(" transform=\"", s, "\"") end
    write[element.shape.type](element.shape, file)
    file:write("/>\n") 
end

function _M.render(scene, viewport, file)
    local vxmin, vymin, vxmax, vymax = unpack(viewport, 1, 4)
    file:write("<?xml version=\"1.0\" standalone=\"no\"?>\n")
    file:write("<svg\n")
    file:write("    xmlns:xlink=\"http://www.w3.org/1999/xlink\"\n")
    file:write("    xmlns:dc=\"http://purl.org/dc/elements/1.1/\"\n")
    file:write("    xmlns:cc=\"http://creativecommons.org/ns#\"\n")
    file:write("    xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"\n")
    file:write("    xmlns:svg=\"http://www.w3.org/2000/svg\"\n")
    file:write("    xmlns=\"http://www.w3.org/2000/svg\"\n")
    file:write("    version=\"1.1\"\n")
    file:write("    viewBox=\"", table.concat(viewport, " ") ,"\"")
    file:write(">\n")
    file:write("<defs>\n")
    local contl = 1
    local contr = 1
    for i,element in ipairs(scene.elements) do
        if element.shape.xf == element.paint.xf then element.paint.xf = nil end
        if element.paint.type == "radialgradient" then    
            printradialgradient(element.paint, "radial"..contr, file)
            mapgradient["p"..i] = "radial"..contr
            contr = contr + 1
        elseif element.paint.type == "lineargradient" then
            printlineargradient(element.paint, "linear"..contl, file)
            mapgradient["p"..i] = "linear"..contl
            contl = contl + 1
        end
    end
    file:write("</defs>\n")
    local s = cordrvgtovsg(scene.xf, vymax)
    if s ~= "" then file:write(s) end
    for i,element in ipairs(scene.elements) do
        local callback = assert(write[element.type],
            "no handler for " .. element.type)
        callback(element, "p"..i, file)
    end
    if s ~= "" then file:write("</g>\n") end
    file:write("</svg>\n")
end

return _M
