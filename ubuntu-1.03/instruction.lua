local _M = {}

-- convert between the short names and the long ones
_M.longname = {
    BOC = "begin_open_contour",
    EOC = "end_open_contour",
    BCC = "begin_closed_contour",
    ECC = "end_closed_contour",
    LS = "linear_segment",
    LSWL = "linear_segment_with_length",
    QS = "quadratic_segment",
    RQS = "rational_quadratic_segment",
    CS = "cubic_segment",
    BS = "begin_segment",
    ES = "end_segment"
}

-- gives the number of arguments each of the instructions take
_M.nargs = {
    BOC = 3,
    EOC = 1,
    BCC = 3,
    ECC = 1,
    LS = 4,
    LSWL = 5,
    QS = 6,
    RQS = 7,
    CS = 8,
    BS = 2,
    ES = 2,
}

-- convert between the long names and the short ones
_M.shortname = { }

-- make sure the longname instructions are defined to the same value as
-- the shortname instructions
for short,long in pairs(_M.longname) do
    -- generate the shortname translate table from longname
    _M.shortname[long] = short
    -- copy nargs from short to long
    _M.nargs[long] = _M.nargs[short]
end

return _M
