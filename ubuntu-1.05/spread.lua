-- these are the different types of functions from the real line back
-- to the interval [0,1]
return {
    clamp = "pad",
    pad = "pad",
    mod = "repeat",
    ["repeat"] = "repeat",
    mirror = "reflect",
    reflect = "reflect",
    transparent = "transparent",
}
