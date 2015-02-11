local image = require"image"

local function wrap(i, n)
    i = (i-1) % (2*n)
    if i < n then return i+1
    else return 2*n-i end
end

local function pointxy(img, x, y)
    x = wrap(x, img.width)
    y = wrap(y, img.height)
    img:set(x, y, 1, 1, 1, 1)
end

local function pointyx(img, y, x)
    x = wrap(x, img.width)
    y = wrap(y, img.height)
    img:set(x, y, 1, 1, 1, 1)
end

local function sign(v)
    if v < 0 then return -1
    elseif v > 0 then return 1
    else return 0 end
end

function linex(img, x1, y1, x2, y2, point)
    local dx, dy = x2 - x1, y2 - y1
    local s = sign(dy)
    dy = s * dy
    if dx < 0 or dx < dy then return end
    local f = dy - dx
    dx, dy = dx*2, dy*2
    local x, y = x1, y1
    point(img, x1, y1)
    while x < x2 do
        x = x + 1
        f = f + dy
        if f > 0 then
            f = f - dx
            y = y + s
        end
        point(img, x, y)
    end
    point(img, x2, y2)
end

function line(img, x1, y1, x2, y2)
    local dx, dy = math.abs(x2 - x1), math.abs(y2 - y1)
    if dx > dy then
        if x2 > x1 then
            linex(img, x1, y1, x2, y2, pointxy)
        else
            linex(img, x2, y2, x1, y1, pointxy)
        end
    else
        if y2 > y1 then
            linex(img, y1, x1, y2, x2, pointyx)
        else
            linex(img, y2, x2, y1, x1, pointyx)
        end
    end
end

local halfwidth, halfheight = 256, 256
local n = 20

function clear(img)
    for i = 1, img.height do
        for j = 1, img.width do
            img:set(j, i, 0, 0, 0, 1)
        end
    end
    return img
end

local outputimage = clear(image.image(2*halfwidth+1, 2*halfheight+1))

for i = 0, n do
    local x = math.floor((1-i/n)*halfwidth+0.5)
    local y = math.floor((i/n)*halfheight+0.5)
    line(outputimage, halfwidth, halfheight+y, halfwidth+x, halfheight)
    line(outputimage, halfwidth, halfheight-y, halfwidth+x, halfheight)
    line(outputimage, halfwidth, halfheight+y, halfwidth-x, halfheight)
    line(outputimage, halfwidth, halfheight-y, halfwidth-x, halfheight)
    print(x, y)
end

local filename = "lines.png"

local file = assert(io.open(filename, "wb"), "unable to open output file")
assert(image.png.store8(file, outputimage))
file:close()
