-- Minimal QR code encoder: byte mode, error correction level M, versions 1-6
-- (up to 106 bytes, far more than a LAN URL needs). Returns a square boolean
-- matrix, true = dark module. Follows ISO/IEC 18004; the placement and
-- format-bit layout mirror Project Nayuki's reference encoder.
return function()
    local bit = bit

    -- per version: data codewords per block, EC codewords per block, blocks
    local VERSIONS = {
        { data = 16, ec = 10, blocks = 1 },
        { data = 28, ec = 16, blocks = 1 },
        { data = 44, ec = 26, blocks = 1 },
        { data = 32, ec = 18, blocks = 2 },
        { data = 43, ec = 24, blocks = 2 },
        { data = 27, ec = 16, blocks = 4 },
    }
    local EC_LEVEL_M = 0 -- format bits for level M

    -- GF(256) with the QR polynomial x^8 + x^4 + x^3 + x^2 + 1
    local EXP, LOG = {}, {}
    do
        local x = 1
        for i = 0, 254 do
            EXP[i] = x
            LOG[x] = i
            x = x * 2
            if x >= 256 then x = bit.bxor(x, 0x11D) end
        end
        for i = 255, 511 do EXP[i] = EXP[i - 255] end
    end

    local function gfMul(a, b)
        if a == 0 or b == 0 then return 0 end
        return EXP[LOG[a] + LOG[b]]
    end

    -- generator polynomial coefficients (highest degree first, leading 1 dropped)
    local function generator(degree)
        local poly = { 1 }
        for i = 0, degree - 1 do
            local nextPoly = {}
            for j = 1, #poly + 1 do
                local a = poly[j] or 0
                local b = gfMul(poly[j - 1] or 0, EXP[i])
                nextPoly[j] = bit.bxor(a, b)
            end
            poly = nextPoly
        end
        table.remove(poly, 1)
        return poly
    end

    local function reedSolomon(dataBytes, degree)
        local gen = generator(degree)
        local rem = {}
        for i = 1, degree do rem[i] = 0 end
        for _, byte in ipairs(dataBytes) do
            local factor = bit.bxor(byte, rem[1])
            table.remove(rem, 1)
            rem[degree] = 0
            for i = 1, degree do
                rem[i] = bit.bxor(rem[i], gfMul(gen[i], factor))
            end
        end
        return rem
    end

    local function encodeData(text, v)
        local spec = VERSIONS[v]
        local capacity = spec.data * spec.blocks
        local bits = {}
        local function push(value, count)
            for i = count - 1, 0, -1 do
                bits[#bits + 1] = bit.band(bit.rshift(value, i), 1)
            end
        end
        push(4, 4) -- byte mode
        push(#text, 8)
        for i = 1, #text do push(text:byte(i), 8) end
        for _ = 1, math.min(4, capacity * 8 - #bits) do bits[#bits + 1] = 0 end
        while #bits % 8 ~= 0 do bits[#bits + 1] = 0 end

        local bytes = {}
        for i = 1, #bits, 8 do
            local b = 0
            for j = 0, 7 do b = b * 2 + bits[i + j] end
            bytes[#bytes + 1] = b
        end
        local pad = { 0xEC, 0x11 }
        local p = 1
        while #bytes < capacity do
            bytes[#bytes + 1] = pad[p]
            p = 3 - p
        end

        -- split into blocks, add EC, interleave
        local dataBlocks, ecBlocks = {}, {}
        for b = 1, spec.blocks do
            local block = {}
            for i = 1, spec.data do block[i] = bytes[(b - 1) * spec.data + i] end
            dataBlocks[b] = block
            ecBlocks[b] = reedSolomon(block, spec.ec)
        end
        local out = {}
        for i = 1, spec.data do
            for b = 1, spec.blocks do out[#out + 1] = dataBlocks[b][i] end
        end
        for i = 1, spec.ec do
            for b = 1, spec.blocks do out[#out + 1] = ecBlocks[b][i] end
        end
        return out
    end

    local function newMatrix(size)
        local m, fn = {}, {}
        for y = 0, size - 1 do
            m[y], fn[y] = {}, {}
            for x = 0, size - 1 do
                m[y][x], fn[y][x] = false, false
            end
        end
        return m, fn
    end

    local function drawFunctionPatterns(m, fn, size, v)
        local function set(x, y, dark)
            m[y][x] = dark
            fn[y][x] = true
        end
        for i = 0, size - 1 do
            set(6, i, i % 2 == 0)
            set(i, 6, i % 2 == 0)
        end
        local function finder(cx, cy)
            for dy = -4, 4 do
                for dx = -4, 4 do
                    local x, y = cx + dx, cy + dy
                    if x >= 0 and x < size and y >= 0 and y < size then
                        local d = math.max(math.abs(dx), math.abs(dy))
                        set(x, y, d ~= 2 and d ~= 4)
                    end
                end
            end
        end
        finder(3, 3)
        finder(size - 4, 3)
        finder(3, size - 4)
        if v >= 2 then
            local c = size - 7 -- versions 2-6 have a single alignment pattern
            for dy = -2, 2 do
                for dx = -2, 2 do
                    set(c + dx, c + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
                end
            end
        end
        -- reserve format areas (written later) and the dark module
        for i = 0, 8 do
            if not fn[8][i] then set(i, 8, false) end
            if not fn[i][8] then set(8, i, false) end
        end
        for i = 0, 7 do
            set(size - 1 - i, 8, false)
            set(8, size - 1 - i, false)
        end
        set(8, size - 8, true)
    end

    local function drawFormatBits(m, size, mask)
        local data = EC_LEVEL_M * 8 + mask
        local rem = data
        for _ = 1, 10 do
            rem = bit.bxor(bit.lshift(rem, 1), bit.rshift(rem, 9) * 0x537)
        end
        local bits = bit.bxor(bit.bor(bit.lshift(data, 10), rem), 0x5412)
        local function b(i) return bit.band(bit.rshift(bits, i), 1) == 1 end
        for i = 0, 5 do m[i][8] = b(i) end
        m[7][8] = b(6)
        m[8][8] = b(7)
        m[8][7] = b(8)
        for i = 9, 14 do m[8][14 - i] = b(i) end
        for i = 0, 7 do m[8][size - 1 - i] = b(i) end
        for i = 8, 14 do m[size - 15 + i][8] = b(i) end
        m[size - 8][8] = true
    end

    local function drawCodewords(m, fn, size, codewords)
        local total = #codewords * 8
        local i = 0
        local right = size - 1
        while right >= 1 do
            if right == 6 then right = 5 end
            local upward = bit.band(right + 1, 2) == 0
            for vert = 0, size - 1 do
                local y = upward and (size - 1 - vert) or vert
                for j = 0, 1 do
                    local x = right - j
                    if not fn[y][x] and i < total then
                        local byte = codewords[math.floor(i / 8) + 1]
                        m[y][x] = bit.band(bit.rshift(byte, 7 - i % 8), 1) == 1
                        i = i + 1
                    end
                end
            end
            right = right - 2
        end
    end

    local MASKS = {
        [0] = function(x, y) return (x + y) % 2 == 0 end,
        function(_, y) return y % 2 == 0 end,
        function(x, _) return x % 3 == 0 end,
        function(x, y) return (x + y) % 3 == 0 end,
        function(x, y) return (math.floor(x / 3) + math.floor(y / 2)) % 2 == 0 end,
        function(x, y) return x * y % 2 + x * y % 3 == 0 end,
        function(x, y) return (x * y % 2 + x * y % 3) % 2 == 0 end,
        function(x, y) return ((x + y) % 2 + x * y % 3) % 2 == 0 end,
    }

    local function applyMask(m, fn, size, mask)
        local f = MASKS[mask]
        for y = 0, size - 1 do
            for x = 0, size - 1 do
                if not fn[y][x] and f(x, y) then m[y][x] = not m[y][x] end
            end
        end
    end

    -- ISO penalty rules N1-N4; lower is easier to scan
    local function penalty(m, size)
        local score = 0
        local function line(get)
            local runColor, run = nil, 0
            local seq = {}
            for i = 0, size - 1 do
                local c = get(i)
                seq[i] = c
                if c == runColor then
                    run = run + 1
                    if run == 5 then score = score + 3
                    elseif run > 5 then score = score + 1 end
                else
                    runColor, run = c, 1
                end
            end
            -- finder-like 1:1:3:1:1 with 4 light modules on either side
            for i = 0, size - 7 do
                if seq[i] and not seq[i + 1] and seq[i + 2] and seq[i + 3] and seq[i + 4]
                    and not seq[i + 5] and seq[i + 6] then
                    local before, after = true, true
                    for k = 1, 4 do
                        if seq[i - k] then before = false end
                        if seq[i + 6 + k] then after = false end
                    end
                    if before or after then score = score + 40 end
                end
            end
        end
        for y = 0, size - 1 do line(function(i) return m[y][i] end) end
        for x = 0, size - 1 do line(function(i) return m[i][x] end) end
        local dark = 0
        for y = 0, size - 1 do
            for x = 0, size - 1 do
                local c = m[y][x]
                if c then dark = dark + 1 end
                if x < size - 1 and y < size - 1 and c == m[y][x + 1]
                    and c == m[y + 1][x] and c == m[y + 1][x + 1] then
                    score = score + 3
                end
            end
        end
        local total = size * size
        local k = math.ceil(math.abs(dark * 20 - total * 10) / total) - 1
        return score + math.max(0, k) * 10
    end

    local function copy(m, size)
        local out = {}
        for y = 0, size - 1 do
            out[y] = {}
            for x = 0, size - 1 do out[y][x] = m[y][x] end
        end
        return out
    end

    -- Returns matrix (0-based rows/cols, true = dark) and its size, or nil, err.
    -- forceMask (0-7) skips the penalty search; only tests need it.
    return function(text, forceMask)
        local v
        for version, spec in ipairs(VERSIONS) do
            if #text <= spec.data * spec.blocks - 2 then
                v = version
                break
            end
        end
        if not v then return nil, "text too long for a QR code" end
        local size = 17 + 4 * v
        local base, fn = newMatrix(size)
        drawFunctionPatterns(base, fn, size, v)
        drawCodewords(base, fn, size, encodeData(text, v))

        local best, bestScore
        for mask = forceMask or 0, forceMask or 7 do
            local m = copy(base, size)
            applyMask(m, fn, size, mask)
            drawFormatBits(m, size, mask)
            local score = penalty(m, size)
            if not bestScore or score < bestScore then
                best, bestScore = m, score
            end
        end
        return best, size
    end
end
