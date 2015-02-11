local driver = require"driver"
local image = require"image"
local chronos = require"chronos"
local xform = require"xform"
local conic = require"ellipses"
local solve = require"quadratic"
require"utils"

local unpack = table.unpack
local floor = math.floor

local _M = driver.new()

-- output formatted string to stderr
local function stderr(...)
    io.stderr:write(string.format(...))
end

local EPS = 1.17549435E-38 -- FLT_MIN

-- these are the two functions that you need to modify/implement

-- prepare scene for sampling and return modified scene
local function preparescene(scene)
    -- implement

    for i, element in ipairs(scene.elements) do
        --transform paint
        -- lineargradient
        if element.paint.type == "lineargradient" then
            local data = element.paint.data
            local theta = angleinto2v(data.p1[1], data.p1[2], data.p2[1], data.p2[2])
            local c = math.cos(-theta)
            local s = math.sin(-theta)
            local dx = distance(data.p1[1], data.p1[2], data.p2[1], data.p2[2])
            
            local rl = xform.xform(c, -s, 0, s, c, 0, 0, 0, 1)
            local tl = xform.xform(1, 0, -data.p1[1], 0, 1, -data.p1[2], 0, 0, 1)
            local sl = xform.xform(1/dx, 0, 0, 0, 1, 0, 0, 0, 1)

            element.paint.xf = sl* rl* tl * (scene.xf*element.paint.xf):inverse()
            
        -- radialgradient
        elseif element.paint.type == "radialgradient" then

            local data = element.paint.data
            local theta = angleinto2v(data.focus[1], data.focus[2], data.center[1], data.center[2])
            local c = math.cos(-theta)
            local s = math.sin(-theta)

            local rl = xform.xform(c, -s, 0, s, c, 0, 0, 0, 1)
            local tl = xform.xform(1, 0, -data.focus[1], 0, 1, -data.focus[2], 0, 0, 1)

            element.paint.xf = rl* tl * (scene.xf*element.paint.xf):inverse()
            data.center[1], data.center[2] = element.paint.xf:apply(data.center[1], data.center[2])
            data.focus[1], data.focus[2] = element.paint.xf:apply(data.focus[1], data.focus[2])

        end

        --transform shape

        if element.shape.type == "triangle" then
            --merging transforms
            element.shape.xf = scene.xf*element.shape.xf

            --transform vrtxs
            element.shape.x1, element.shape.y1 = element.shape.xf:apply(element.shape.x1, element.shape.y1)
            element.shape.x2, element.shape.y2 = element.shape.xf:apply(element.shape.x2, element.shape.y2)
            element.shape.x3, element.shape.y3 = element.shape.xf:apply(element.shape.x3, element.shape.y3)

            -- implicit lines of triangle
            element.shape.lines = {}
            element.shape.lines[1] = implicitline(element.shape.x1, element.shape.y1, element.shape.x2, element.shape.y2)
            element.shape.lines[2] = implicitline(element.shape.x2, element.shape.y2, element.shape.x3, element.shape.y3)
            element.shape.lines[3] = implicitline(element.shape.x3, element.shape.y3, element.shape.x1, element.shape.y1)

        elseif element.shape.type == "circle" then
            -- basic circle
            local m = xform.xform(1, 0, 0, 0, 1, 0, 0, 0, -1)
            -- circle with center and radio
            m = conic.translateconic(conic.scaleconic(m, element.shape.r, element.shape.r), element.shape.cx, element.shape.cy)

            -- apply transforms of shape
            local inv = element.shape.xf:inverse()
            m = inv:transpose() * m * inv
            -- apply transforms of scene 
            inv = scene.xf:inverse()
            element.shape.xf = inv:transpose() * m * inv

        elseif element.shape.type == "polygon" then
            --merging transforms
            element.shape.xf = scene.xf*element.shape.xf

            --transform vrtxs
            local n = #element.shape.data
            for i=1,n,2 do
                element.shape.data[i], element.shape.data[i+1] = element.shape.xf:apply(element.shape.data[i], element.shape.data[i+1])
            end
            
            -- implicit lines of edges
            local cnt = 1
            local x1, y1, x2, y2
            element.shape.lines = {}
            
            for i=3, n, 2 do
                x1 = element.shape.data[i]
                y1 = element.shape.data[i+1]
                x2 = element.shape.data[i-2]
                y2 = element.shape.data[i-1]

                element.shape.lines[cnt] = implicitline(x1, y1, x2, y2, x, y)
                cnt = cnt + 1
            end
            x1 = element.shape.data[1]
            y1 = element.shape.data[2]
            x2 = element.shape.data[n-1]
            y2 = element.shape.data[n]
            
            element.shape.lines[cnt] = implicitline(x1, y1, x2, y2, x, y)
            cnt = cnt + 1 
        end
    end
    return scene
end

local function radialgradient(paint, x0, y0)
    local data = paint.data
    x0, y0 = paint.xf:apply(x0, y0)
    local a = (1.0 + (x0*x0)/(y0*y0))
    local b = -2*data.center[1]*x0/y0
    local c = data.center[1]*data.center[1] - data.radius*data.radius

    local m,t1,s1,t2,s2 =  solve.quadratic(a,b,c)

    local x1, y1
    if y0 > 0 then
        y1 = t1/s1
        x1 = y1*x0/y0
    else
        y1 = t2/s2
        x1 = y1*x0/y0
    end
    local d1 = distance(0, 0, x0, y0)
    local d2 = distance(x0, y0, x1, y1)
    local d = distance(0, 0, x1, y1)

    local ramp = paint.data.ramp
    local n = #paint.data.ramp
   
    if EPS < d1 - d then
        return paint.data.ramp[n]
    end

    local p = d1/d
    
    for i=1, n-2, 2 do
        if ramp[i] <= p and p < ramp[i+2] then
            local r, g, b, a
            r = (ramp[i+3][1]*(p-ramp[i]) + ramp[i+1][1]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            g = (ramp[i+3][2]*(p-ramp[i]) + ramp[i+1][2]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            b = (ramp[i+3][3]*(p-ramp[i]) + ramp[i+1][3]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            a = (ramp[i+3][4]*(p-ramp[i]) + ramp[i+1][4]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            return {r,g,b,a} 
        end
    end

    return {1,1,1,1}
end

local function lineargradient(paint, x0, y0)
    p, q = paint.xf:apply(x0, y0)

    local ramp = paint.data.ramp
    local n = #paint.data.ramp
   
    if p < 0 then
        return paint.data.ramp[2]
    elseif p >= 1 then
        return paint.data.ramp[n] 
    end

    for i=1, n-2, 2 do
        if ramp[i] <= p and p < ramp[i+2] then
            local r, g, b, a
            r = (ramp[i+3][1]*(p-ramp[i]) + ramp[i+1][1]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            g = (ramp[i+3][2]*(p-ramp[i]) + ramp[i+1][2]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            b = (ramp[i+3][3]*(p-ramp[i]) + ramp[i+1][3]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            a = (ramp[i+3][4]*(p-ramp[i]) + ramp[i+1][4]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            return {r,g,b,a} 
        end
    end

    return {1,1,1,1} 
end

-- sample scene at x,y and return r,g,b,a
local function sample(scene, x, y)
    -- implement
    -- paint
    local Cr = 1.0
    local Cg = 1.0
    local Cb = 1.0
    local alpha = 1.0

    for i, element in ipairs(scene.elements) do
        local r, g, b, a = unpack(element.paint.data) 
        if element.shape.type == "triangle" then
            local cnt = 0
            for i,line in ipairs(element.shape.lines) do
                if y > line.ymin and y <= line.ymax and line.a*x + line.b*y + line.c < 0 then
                    cnt = cnt + line.s
                end
            end
            if cnt ~= 0 then
                if element.paint.type == "lineargradient" then
                    r,g,b,a = unpack(lineargradient(element.paint, x, y))
                elseif element.paint.type =="radialgradient" then
                    r,g,b,a = unpack(radialgradient(element.paint, x, y))
                end
                Cr = r*a + Cr*alpha*(1-a)
                Cg = g*a + Cg*alpha*(1-a)
                Cb = b*a + Cb*alpha*(1-a)
                alpha = a + alpha*(1-a)
            end
        elseif element.shape.type == "circle" then
            local m = element.shape.xf
            local eval =  x*x*m[1] + x*y*(m[4] + m[2]) + m[5]*y*y + (m[7] + m[3])*x + (m[6] + m[8])*y + m[9]

            if ( eval < 0) then
                if element.paint.type == "lineargradient" then
                    r,g,b,a = unpack(lineargradient(element.paint, x, y))
                elseif element.paint.type =="radialgradient" then
                    r,g,b,a = unpack(radialgradient(element.paint, x, y))
                end
                
                Cr = r*a + Cr*alpha*(1-a)
                Cg = g*a + Cg*alpha*(1-a)
                Cb = b*a + Cb*alpha*(1-a)
                alpha = a + alpha*(1-a)
             end
        elseif element.shape.type == "polygon" then
            local ed = 0
            for i,line in ipairs(element.shape.lines) do
                if y > line.ymin and y <= line.ymax and line.a*x + line.b*y + line.c < 0 then
                    ed = ed + line.s
                end
            end

            if (element.type == "fill" and ed ~= 0) or (element.type == "eofill" and ed%2 ~= 0) then
                if element.paint.type == "lineargradient" then
                    r,g,b,a = unpack(lineargradient(element.paint, x, y))
                elseif element.paint.type =="radialgradient" then
                    r,g,b,a = unpack(radialgradient(element.paint, x, y))
                end
                Cr = r*a + Cr*alpha*(1-a)
                Cg = g*a + Cg*alpha*(1-a)
                Cb = b*a + Cb*alpha*(1-a)
                alpha = a + alpha*(1-a)
            end
        elseif element.shape.type == "path" then

        end
    end
    return Cr, Cg, Cb, alpha
end

-- verifies that there is nothing unsupported in the scene
local function checkscene(scene)
    for i, element in ipairs(scene.elements) do
        assert(element.type == "fill" or
               element.type == "eofill", "unsupported element")
        assert(element.shape.type == "circle" or
               element.shape.type == "triangle" or
               element.shape.type == "polygon" or 
               element.shape.type == "path", "unsuported primitive")
        assert(not element.shape.style, "stroking not unsuported")
        assert(element.paint.type == "solid" or
               element.paint.type == "lineargradient" or
               element.paint.type == "radialgradient" or
               element.paint.type == "texture",
                    "unsupported paint")
    end
end


function _M.render(scene, viewport, file)
local time = chronos.chronos()
    -- make sure scene does not contain any unsuported content
    checkscene(scene)
    -- transform and prepare scene for rendering
    scene = preparescene(scene)
    -- get viewport
    local vxmin, vymin, vxmax, vymax = unpack(viewport, 1, 4)
stderr("preprocess in %.3fs\n", time:elapsed())
time:reset()
    -- get image width and height from viewport
    local width, height = vxmax-vxmin, vymax-vymin
    -- allocate output image
    local img = image.image(width, height)
    -- render
    for i = 1, height do
stderr("\r%d%%", floor(1000*i/height)/10)
        for j = 1, width do
            img:set(j, i, sample(scene, j-0.5, i-0.5))
        end
    end
stderr("\n")
stderr("rendering in %.3fs\n", time:elapsed())
time:reset()
    -- store output image
    image.png.store8(file, img)
stderr("saved in %.3fs\n", time:elapsed())
end

return _M
