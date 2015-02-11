-- Load driver
local driver = dofile(arg[1])
-- Load and run the Lua program that defines the scene, window, and viewport
-- The only globals visible are the ones exported by the driver
local rvg = assert(assert(loadfile(arg[2], "bt", driver))())
-- By default, dump to stadard out
local out = io.stdout
-- If arg[3] was given, replace with the open file
if arg[3] then
    out = assert(io.open(arg[3], "wb"))
end
-- Invoke driver-defined rendering function
driver.render(rvg.scene:windowviewport(rvg.window,rvg.viewport),rvg.viewport,out)
-- close file
if arg[3] then
    out:close()
end
