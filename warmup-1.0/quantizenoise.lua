local image = require"image"

local inputimage = image.png.load(assert(io.open(arg[1], "rb")))
local levels = assert(tonumber(arg[2]), "invalid width")
assert(levels > 0, "invalid number of levels")
local filename = arg[3]
assert(type(filename) == "string" and filename:lower():sub(-3) == "png",
    "invalid output name")

local floor = math.floor
local random = math.random
local min = math.min

local function gray(r, g, b)
    return 0.3333333*(r+g+b)
end

local function quantizeimage(image, levels)
    levels = levels-1
    for i = 1, image.height do
        for j = 1, image.width do
            local g = gray(image:get(j, i))*levels
            local f = floor(g)
            local d = g - f
            if random() > d then g = f
            else g = f + 1 end
            g = g / levels
            image:set(j, i, g, g, g, 1)
        end
    end
    return image
end

local file = assert(io.open(filename, "wb"), "unable to open output file")
assert(image.png.store8(file, quantizeimage(inputimage, levels)))
file:close()
