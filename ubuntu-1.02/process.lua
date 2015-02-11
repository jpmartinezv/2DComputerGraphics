local driver = require((string.gsub(arg[1], "%.lua$", "")))
local rvg = dofile(arg[2])
local scene = rvg.scene(driver)
local window = rvg.window(driver)
local viewport = rvg.viewport(driver)
local out = io.stdout
if arg[3] then
    out = assert(io.open(arg[3], "wb"))
end
driver.render(scene:windowviewport(window,viewport),viewport,out)
if arg[3] then
    out:close()
end
