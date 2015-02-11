local driver = require"driver"
local image = require"image"
local chronos = require"chronos"
local xform = require"xform"
local conic = require"ellipses"
local solve = require"quadratic"
local solvec = require"cubic"

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

local rvgcommand = {
    begin_open_contour = "M",
    begin_closed_contour = "M",
    linear_segment = "L",
    quadratic_segment = "Q",
    rational_quadratic_segment = "R",
    cubic_segment = "C",
    end_closed_contour = "Z",
}

local prepare = {}

function prepare.solid(element, scene_xform)
end

function prepare.lineargradient(element, scene_xform)
    local data = element.paint.data
    local theta = angleinto2v(data.p1[1], data.p1[2], data.p2[1], data.p2[2])
    local c = math.cos(-theta)
    local s = math.sin(-theta)
    local dx = distance(data.p1[1], data.p1[2], data.p2[1], data.p2[2])

    local rl = xform.xform(c, -s, 0, s, c, 0, 0, 0, 1)
    local tl = xform.xform(1, 0, -data.p1[1], 0, 1, -data.p1[2], 0, 0, 1)
    local sl = xform.xform(1/dx, 0, 0, 0, 1, 0, 0, 0, 1)

    element.paint.xf = sl* rl* tl * (scene_xform*element.paint.xf):inverse()

end

function prepare.radialgradient(element, scene_xform)
    local data = element.paint.data
    local theta = angleinto2v(data.focus[1], data.focus[2], data.center[1], data.center[2])
    local c = math.cos(-theta)
    local s = math.sin(-theta)

    local rl = xform.xform(c, -s, 0, s, c, 0, 0, 0, 1)
    local tl = xform.xform(1, 0, -data.focus[1], 0, 1, -data.focus[2], 0, 0, 1)

    local m = rl * tl

    data.center[1], data.center[2] = m:apply(data.center[1], data.center[2])
    data.focus[1], data.focus[2] = m:apply(data.focus[1], data.focus[2])

    element.paint.xf = m * (scene_xform*element.paint.xf):inverse()
end

function prepare.triangle(element, scene)
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
end

function prepare.circle(element, scene)

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
end

function prepare.polygon(element, scene)
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

end    

function prepare.path(element, scene)
    element.shape.xf = scene.xf*element.shape.xf

    local shape = element.shape
    for i,v in ipairs(shape.instructions) do
        local o = shape.offsets[i]
        local s = rvgcommand[v]
        if s == "M" then
            shape.data[o+1], shape.data[o+2] = element.shape.xf:apply(shape.data[o+1], shape.data[o+2])
        elseif s == "L" then
            shape.data[o+2], shape.data[o+3] = element.shape.xf:apply(shape.data[o+2], shape.data[o+3])
        elseif s == "Q" then
            shape.data[o+2], shape.data[o+3] = element.shape.xf:apply(shape.data[o+2], shape.data[o+3])
            shape.data[o+4], shape.data[o+5] = element.shape.xf:apply(shape.data[o+4], shape.data[o+5])
        elseif s == "C" then
            shape.data[o+2], shape.data[o+3] = element.shape.xf:apply(shape.data[o+2], shape.data[o+3])
            shape.data[o+4], shape.data[o+5] = element.shape.xf:apply(shape.data[o+4], shape.data[o+5])
            shape.data[o+6], shape.data[o+7] = element.shape.xf:apply(shape.data[o+6], shape.data[o+7])
        end
    end
end


-- prepare scene for sampling and return modified scene
local function preparescene(scene)
    -- implement
    for i, element in ipairs(scene.elements) do
        prepare[element.paint.type](element, scene.xf) 
        prepare[element.shape.type](element, scene) 
    end
    return scene
end

local function bb11(t, x0, y0, x1, y1)
    return ((1-t)*x0 + t*x1), ((1-t)*y0 + t*y1)
end

local function bb12(t, x0, y0, x1, y1, x2, y2)
    return ( (1-t)^2 * x0 + 2 * (1-t) * t * x1 + t^2 * x2), ( (1-t)^2 * y0 + 2 * (1-t) * t * y1 + t^2 * y2)
end

local function bb13(t, x0, y0, x1, y1, x2, y2, x3, y3)
    return ( (1-t)^3 * x0 + 3 * (1-t)^2 * t * x1 + 3 * (1-t) * t^2 * x2 + t^3 * x3), ( (1-t)^3 * y0 + 3 * (1-t)^2 * t * y1 + 3 * (1-t) * t^2 * y2 + t^3 * y3)
end

local function checklinearinside(x0, y0, x1, y1, x, y)
    local cnt = 0
    
    local t = (y-y0)/(y1-y0)
    k = (1-t)*x0 + t*x1 - x

    if t >= 0 and t <= 1 and k > 0 then
        cnt = cnt + sign((y1-y0))
    end
    return cnt
end

local function checkquadraticinside(x0, y0, x1, y1, x2, y2, x, y)
    local cnt = 0
    
    local a = y0 - 2*y1 + y2
    local b = 2*y1 - 2*y0
    local c = y0 - y

    local n, k1, s1, k2, s2 = solve.quadratic(a,b,c)

    if n == 0 then return 0 end

    local t

    local xa0 = 2*(-x0+x1) 
    local ya0 = 2*(-y0+y1) 
    local xa1 = 2*(-x1+x2) 
    local ya1 = 2*(-y1+y2) 

    if k1 ~= nil then
        t = k1/s1
        k = (1-t)^2 * x0 + 2*(1-t)*t*x1 + t^2 * x2 - x
        if t >= 0 and t <= 1 and k>0 then
            local xa, ya = bb11(t, xa0, ya0, xa1, ya1)
            cnt = cnt + sign(ya/xa)
            return cnt
        end
    end
    
    if k2 ~= nil then
        t = k2/s2
        k = (1-t)^2 * x0 + 2*(1-t)*t*x1 + t^2 * x2 - x
        if t >= 0 and t <= 1 and k>0 then
            local xa, ya = bb11(t, xa0, ya0, xa1, ya1)
            cnt = cnt + sign(ya/xa)
        end
    end

    return cnt
end

local function checkcubicinside(x0, y0, x1, y1, x2, y2, x3, y3, x, y)
    local cnt = 0

    local a = -y0 + 3*y1 - 3*y2 + y3
    local b = 3*y0 - 6*y1 + 3*y2
    local c = -3*y0 + 3*y1
    local d = y0 - y
    
    local n, k1, s1, k2, s2, k3, s3 = solvec.cubic(a,b,c,d)
    
    local xa0 = 3*(-x0+x1) 
    local ya0 = 3*(-y0+y1) 
    local xa1 = 3*(-x1+x2) 
    local ya1 = 3*(-y1+y2) 
    local xa2 = 3*(-x2+x3) 
    local ya2 = 3*(-y2+y3) 

    local t
    local dx, dy

    if k1 ~= nil then
        t = k1/s1
        if t >= 0 and t <= 1 then
            k = (1-t)^3 * x0 + 3 * (1-t)^2 * t * x1 + 3 * (1-t) * t^2 * x2 + t^3 * x3 - x
            if k > 0 then
                dx, dy = bb12(t, xa0, ya0, xa1, ya1, xa2, ya2)
                cnt = cnt + sign(dy/dx)
            end
        end
    end

    if k2 ~= nil then
        t = k2/s2
        if t >= 0 and t <= 1 then
            k = (1-t)^3 * x0 + 3 * (1-t)^2 * t * x1 + 3 * (1-t) * t^2 * x2 + t^3 * x3 - x
            if k > 0 then
                dx, dy = bb12(t, xa0, ya0, xa1, ya1, xa2, ya2)
                cnt = cnt + sign(dy/dx)
            end
        end
    end

    if k3 ~= nil then
        t = k3/s3
        if t >= 0 and t <= 1 then
            k = (1-t)^3 * x0 + 3 * (1-t)^2 * t * x1 + 3 * (1-t) * t^2 * x2 + t^3 * x3 - x
            if k > 0 then
                dx, dy = bb12(t, xa0, ya0, xa1, ya1, xa2, ya2)
                cnt = cnt + sign(dy/dx)
            end
        end
    end

    return cnt
end

local getcolor = {}

function getcolor.solid(paint, x, y)
    return unpack(paint.data)
end

function getcolor.lineargradient(paint, x0, y0)
    local p, q = paint.xf:apply(x0, y0)
    local ramp = paint.data.ramp
    local n = #ramp

    if p < 0 then
        return unpack(paint.data.ramp[2])
    elseif p > 1 then
        return unpack(paint.data.ramp[n])
    end

    local r, g, b, a
    for i=1, n-2, 2 do
        if ramp[i] <= p and p <= ramp[i+2] then
            r = (ramp[i+3][1]*(p-ramp[i]) + ramp[i+1][1]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            g = (ramp[i+3][2]*(p-ramp[i]) + ramp[i+1][2]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            b = (ramp[i+3][3]*(p-ramp[i]) + ramp[i+1][3]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            a = (ramp[i+3][4]*(p-ramp[i]) + ramp[i+1][4]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            return r,g,b,a 
        end
    end

    return 1,1,1,1 
end

function getcolor.radialgradient(paint, x0, y0)
    local data = paint.data
    x0, y0 = paint.xf:apply(x0, y0)

    local a = (1.0 + (x0/y0)^2)
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
    local dp = distance(0, 0, x0, y0)
    local d = distance(0, 0, x1, y1)
   
    local ramp = paint.data.ramp
    local n = #ramp
    
    if dp > d then return unpack(paint.data.ramp[n]) end
    local p = dp/d
    
    local r, g, b, a
    for i=1, n-2, 2 do
        if ramp[i] <= p and p < ramp[i+2] then
            r = (ramp[i+3][1]*(p-ramp[i]) + ramp[i+1][1]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            g = (ramp[i+3][2]*(p-ramp[i]) + ramp[i+1][2]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            b = (ramp[i+3][3]*(p-ramp[i]) + ramp[i+1][3]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            a = (ramp[i+3][4]*(p-ramp[i]) + ramp[i+1][4]*(ramp[i+2] - p))/(ramp[i+2] - ramp[i])
            return r,g,b,a
        end
    end

    return 1,1,1,1
end

-- sample scene at x,y and return r,g,b,a
local function sample(scene, x, y)
    -- implement
    -- paint
    local Cr = 1.0
    local Cg = 1.0
    local Cb = 1.0
    local alpha = 1.0

    local r, g, b, a 
    
    for i, element in ipairs(scene.elements) do
        
        if element.shape.type == "triangle" then
            local cnt = 0
            local lines = element.shape.lines
            for i=1,3 do
                if y > lines[i].ymin and y <= lines[i].ymax and lines[i].a*x + lines[i].b*y + lines[i].c < 0 then
                    cnt = cnt + lines[i].s
                end
            end
            if cnt ~= 0 then
                
                r,g,b,a = getcolor[element.paint.type](element.paint, x, y)
                a = element.paint.opacity*a

                Cr = r*a + Cr*alpha*(1-a)
                Cg = g*a + Cg*alpha*(1-a)
                Cb = b*a + Cb*alpha*(1-a)
                alpha = a + alpha*(1-a)
            end
        elseif element.shape.type == "circle" then
            local m = element.shape.xf
            local eval =  x*x*m[1] + x*y*(m[4] + m[2]) + m[5]*y*y + (m[7] + m[3])*x + (m[6] + m[8])*y + m[9]

            if eval < 0 then
                r,g,b,a = getcolor[element.paint.type](element.paint, x, y)
                a = element.paint.opacity*a
                
                Cr = r*a + Cr*alpha*(1-a)
                Cg = g*a + Cg*alpha*(1-a)
                Cb = b*a + Cb*alpha*(1-a)
                alpha = a + alpha*(1-a)
             end
        elseif element.shape.type == "polygon" then
            local cnt = 0
            local lines = element.shape.lines
            local n = #lines
            for i=1,n do
                if y > lines[i].ymin and y <= lines[i].ymax and lines[i].a*x + lines[i].b*y + lines[i].c < 0 then
                    cnt = cnt + lines[i].s
                end
            end

            if (element.type == "fill" and cnt ~= 0) or (element.type == "eofill" and cnt%2 ~= 0) then
                r,g,b,a = getcolor[element.paint.type](element.paint, x, y)

                Cr = r*a + Cr*alpha*(1-a)
                Cg = g*a + Cg*alpha*(1-a)
                Cb = b*a + Cb*alpha*(1-a)
                alpha = a + alpha*(1-a)
            end
        
        elseif element.shape.type == "path" then
            
            local shape = element.shape
            local lastx, lasty
            local last_beginx, last_beginy
            local cnt = 0
            local n = #shape.instructions
            for j=1,n do
                local o = shape.offsets[j]
                local s = rvgcommand[shape.instructions[j]]
                if s == "M" then
                    lastx = shape.data[o+1]
                    lasty = shape.data[o+2]
                    last_beginx = lastx
                    last_beginy = lasty 
                elseif s == "Z" then
                    cnt = cnt + checklinearinside(lastx, lasty, last_beginx, last_beginy, x, y)
                    lastx = last_beginx
                    lasty = last_beginy
                elseif s == "L" then
                    cnt = cnt + checklinearinside(lastx, lasty, shape.data[o+2], shape.data[o+3], x, y)
                    lastx = shape.data[o+2]
                    lasty = shape.data[o+3]
                elseif s == "Q" then
                    cnt = cnt + checkquadraticinside(lastx, lasty, shape.data[o+2], shape.data[o+3], shape.data[o+4], shape.data[o+5], x, y)
                    lastx = shape.data[o+4]
                    lasty = shape.data[o+5]
                elseif s == "C" then
                    cnt = cnt + checkcubicinside(lastx, lasty, shape.data[o+2], shape.data[o+3], shape.data[o+4], shape.data[o+5], shape.data[o+6], shape.data[o+7], x, y)
                    lastx = shape.data[o+6]
                    lasty = shape.data[o+7]
                end
            end
            if cnt % 2 ~= 0 then
                r,g,b,a = getcolor[element.paint.type](element.paint, x, y)
                a = element.paint.opacity*a

                Cr = r*a + Cr*alpha*(1-a)
                Cg = g*a + Cg*alpha*(1-a)
                Cb = b*a + Cb*alpha*(1-a)
                alpha = a + alpha*(1-a)
            end
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
