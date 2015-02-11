local image = require"image"

local inputimage = image.png.load(assert(io.open(arg[1], "rb")))
local filename = arg[2]
assert(type(filename) == "string" and filename:lower():sub(-3) == "png",
    "invalid output name")

local floor = math.floor

local function gray(r, g, b)
    return 0.3333333*(r+g+b)
end

local function zeros(width)
    local row = {}
    for i = 0, width+1 do
        row[i] = 0
    end
    return row
end

local function threshold(t)
    if t > 0.5 then return 1
    else return 0 end
end

local function diffusion(image)
    local next = zeros(image.width)
    local current = zeros(image.width)
    for i = 1, image.height do
        local right = 0
        current, next = next, current
        for j = 1, image.width do
            local g = gray(image:get(j, i))+current[j]+right
            local t = threshold(g)
            local e = (g-t)/16
            current[j] = 0
            right = 7*e
            next[j-1] = next[j-1] + 3*e
            next[j]   = next[j] + 5*e
            next[j+1] = next[j+1] + e
            image:set(j, i, t, t, t, 1)
        end
    end
    return image
end

local file = assert(io.open(filename, "wb"), "unable to open output file")
assert(image.png.store8(file, diffusion(inputimage, levels)))
file:close()
