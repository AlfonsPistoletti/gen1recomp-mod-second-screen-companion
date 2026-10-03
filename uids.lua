-- Stable ids for mon tables, so the page can name a boxed Pokémon and an
-- edit can find the same table again even after it moved. The table itself
-- is the identity: weak keys let released mons be collected.
return function()
    local byMon = setmetatable({}, { __mode = "k" })
    local nextUid = 0

    local U = {}

    function U.of(mon)
        local uid = byMon[mon]
        if not uid then
            nextUid = nextUid + 1
            uid = nextUid
            byMon[mon] = uid
        end
        return uid
    end

    -- the box index and slot currently holding uid, or nil
    function U.findInBoxes(boxes, uid)
        -- pairs: Gen 2 creates boxes on demand, so there can be gaps
        for b, box in pairs(boxes or {}) do
            for i, mon in ipairs(box) do
                if byMon[mon] == uid then return b, i end
            end
        end
        return nil
    end

    return U
end
