local _M = {}

-- this function receives a string in utf8 format and
-- returns an array of corresponding code points
function _M.decode(s)
    local codes = {}
    for bytes in string.gmatch(s, ".[\128-\191]*") do
        local b1, b2, b3, b4, b5, b6, b7 = string.byte(bytes, 1, -1)
        assert(b1, "sequence too short")
        assert(not b7, "sequence too long")
        if b1 < 192 then -- 1 byte
            codes[#codes+1] = b1
            assert(not b2, "sequence too long")
        elseif b1 < 224 then -- 2 bytes
            assert(b2, "sequence too short")
            codes[#codes+1] =
                bit32.bor(
                    bit32.lshift(bit32.band(b1, 31), 6),
                    bit32.band(63, b2))
            assert(not b3, "sequence too long")
        elseif b1 < 240 then -- 3 bytes
            assert(b3, not b3 and "sequence too short " ..
                table.concat({string.byte(bytes)}, " "))
            codes[#codes+1] =
                bit32.bor(
                    bit32.lshift(bit32.band(b1, 15), 12),
                    bit32.lshift(bit32.band(b2, 63), 6),
                    bit32.band(63, b3))
            assert(not b4, "sequence too long")
        elseif b1 < 248 then -- 4 bytes
            assert(b4, "sequence too short")
            codes[#codes+1] =
                bit32.bor(
                    bit32.lshift(bit32.band(b1, 7), 18),
                    bit32.lshift(bit32.band(b2, 63), 12),
                    bit32.lshift(bit32.band(b3, 63), 6),
                    bit32.band(63, b4))
            assert(not b5, "sequence too long")
        elseif b1 < 252 then -- 5 bytes
            assert(b5, "sequence too short")
            codes[#codes+1] =
                bit32.bor(
                    bit32.lshift(bit32.band(b1, 3), 24),
                    bit32.lshift(bit32.band(b2, 63), 18),
                    bit32.lshift(bit32.band(b3, 63), 12),
                    bit32.lshift(bit32.band(b4, 63), 6),
                    bit32.band(63, b5))
            assert(not b6, "sequence too long")
        else -- 6 bytes
            assert(b6, "sequence too short")
            codes[#codes+1] =
                bit32.bor(
                    bit32.lshift(bit32.band(b1, 1), 30),
                    bit32.lshift(bit32.band(b2, 63), 24),
                    bit32.lshift(bit32.band(b3, 63), 18),
                    bit32.lshift(bit32.band(b4, 63), 12),
                    bit32.lshift(bit32.band(b5, 63), 6),
                    bit32.band(63, b6))
        end
    end
    return codes
end

return _M
