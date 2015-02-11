local _M = { }

_M.cap = {
    butt = "butt",
    round = "round",
    square = "square"
}

_M.join = {
    miter = "miter",
    round = "round",
    bevel = "bevel"
}

function _M.check(style)
    if type(style) == "table" then
        assert(style.cap and _M.cap[style.cap],
            "invalid cap " .. tostring(style.cap))
        assert(style.join and _M.join[style.join],
            "invalid join " .. tostring(style.join))
        assert(style.miter_limit and type(style.miter_limit) == "number",
            "invalid miter_limit")
        if style.dash then
            assert(type(style.dash) == "table", "invalid dash")
            assert(not style.dash.initial_phase or
                type(style.dash.initial_phase) == "number",
                "invalid dash initial_phase")
            if style.dash.array then
                assert(type(style.dash.array) == "table", "invalid dash array")
                for i,v in ipairs(style.dash.array) do
                    assert(type(v) == "number", "invalid dash array")
                end
            end
        end
    else
        assert(type(style) == "number", "invalid style")
    end
end

function _M.copy(style)
    _M.check(style)
    if type(style) == "table" then
        local copy = {}
        if style.dash then
            copy.dash = { initial_phase = style.dash.initial_phase }
            if style.dash.array then
                copy.dash.array = {}
                for i,v in ipairs(style.dash.array) do
                    copy.dash.array[i] = v
                end
            end
        end
        copy.width = style.width
        copy.cap = style.cap
        copy.join = style.join
        copy.miter_limit = style.miter_limit
        return copy
    else return style end
end

return _M
