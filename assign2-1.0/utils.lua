local min = math.min
local max = math.max
local floor = math.floor

local function sign(v)
    if v < 0 then return -1
    elseif v > 0 then return 1
    else return 0 end
end

function implicitline(x1, y1, x2, y2)
    local line = {}
    line.a = y2 - y1
    line.b = x1 - x2
    line.c = -(line.a*x1 + line.b*y1)
    line.s = sign(line.a)

    line.ymin = min(y1, y2)
    line.ymax = max(y1, y2)

    line.a = line.a * line.s
    line.b = line.b * line.s
    line.c = line.c * line.s
    return line
end

function distance(x1, y1, x2, y2)
    return math.sqrt((x1-x2)*(x1-x2) + (y1-y2)*(y1-y2))
end

function angleinto2v(vx, vy, ux, uy)
    local theta = math.atan((uy-vy)/(ux-vx))
    if (ux-vx)<0 then
        theta = theta + math.pi
    end
    return theta
end
