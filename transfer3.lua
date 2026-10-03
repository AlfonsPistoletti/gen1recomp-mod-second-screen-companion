-- PC TRANSFERS on Gen 3 (FireRed / LeafGreen), behind the same mod option
-- as transfer.lua and with the same functions: POKéMON between the party
-- and the PC boxes, items between the BAG and the PLAYER's PC.
--
-- Every transfer is the game's own, through the engine's functions:
--   DEPOSIT   Storage.deposit (the PC heal, the first free slot, the quest
--             log), after the checks pret's PC screen makes first
--             (pokemon_storage_system.c): a full box, the last POKéMON
--             that can still fight, a POKéMON holding MAIL
--   WITHDRAW  Storage.withdraw (a full party is refused)
--   SWAP      Storage.moveMon party <-> box (for a full party and full
--             boxes, where neither fits): DEPOSIT's checks for the one
--             going in
--   items     to the PC: Storage.addPcItem (pret AddPCItem: a stack up to
--             999, a new one if one of the 50 is free), then out of the BAG
--             (item_menu.c Task_TryDoItemDeposit); to the BAG: Bag.canAdd /
--             Bag.add, then out of the PC (item_pc.c ItemPc_DoWithdraw).
--             Important items can't be stored (item_menu.c).
--
-- Guard rails, as with every Gen 3 edit (edits3.lua):
--   * only in free roam with nothing open (edits3.freeRoam)
--   * every check before the first write; POKéMON named by uid, items by id
--     plus the count the page saw, so anything that changed is stale
--   * checked afterwards (the same POKéMON / the same item totals, moved
--     exactly as asked) and put back as it was if anything is off
--   * only the game in memory changes: saving in the game keeps it
return function(mod, uids, platform, edits, sprites)
    local function need(name)
        local ok, m = pcall(require, "src.core.game3." .. name)
        return ok and type(m) == "table" and m or nil
    end

    local ItemsData = need("items_data")
    local T = {}

    function T.enabled()
        return mod.options:get("pc_transfer") == true
    end

    -- true, or nil plus the reason nothing may move right now
    local function gate(game)
        if not T.enabled() then return nil, "disabled" end
        if not (edits and edits.freeRoam) then return nil, "busy" end
        local ok, why = edits.freeRoam(game)
        if ok then return true end
        -- a step in progress: tap again once it's done
        if why == "walking" then return nil, "party busy" end
        return nil, why
    end

    local function wholeNumber(v)
        return type(v) == "number" and v == math.floor(v)
    end

    local function session(game) return platform.save(game) end

    local function partyIndexOf(s, uid)
        for i, mon in ipairs(s.party or {}) do
            if uids.of(mon) == uid then return i end
        end
        return nil
    end

    -- a boxed POKéMON by uid: box and slot (30 fixed slots with holes)
    local function findBoxed(storage, uid)
        for b, box in ipairs(storage.boxes or {}) do
            for s = 1, platform.BOX_CAPACITY do
                local mon = box.mons and box.mons[s]
                if mon and uids.of(mon) == uid then return b, s end
            end
        end
        return nil
    end

    local function isEgg(mon)
        local Pokemon = need("pokemon")
        if Pokemon and Pokemon.isEgg then
            local ok, egg = pcall(Pokemon.isEgg, mon)
            if ok then return egg end
        end
        return mon.isEgg == true
    end

    local function holdsMail(mon)
        local Mail = need("mail")
        local item = mon and (mon.item or mon.heldItem)
        if not (Mail and Mail.isMailItem and item) then return false end
        local ok, is = pcall(Mail.isMailItem, tonumber(item) or item)
        return ok and is or false
    end

    -- the party's POKéMON that can still fight, leaving out one slot and
    -- counting one coming in (pret CountPartyAliveNonEggMonsExcept)
    local function fighters(party, except, incoming)
        local n = 0
        for i, mon in ipairs(party) do
            if i ~= except and not isEgg(mon) and (tonumber(mon.hp) or 0) > 0 then n = n + 1 end
        end
        if incoming and not isEgg(incoming) and (tonumber(incoming.hp) or 0) > 0 then n = n + 1 end
        return n
    end

    local function cry(mon)
        local Audio, Pokemon = need("audio"), need("pokemon")
        if not (Audio and Audio.playCry) then return end
        local sp = Pokemon and Pokemon.speciesOf and select(2, pcall(Pokemon.speciesOf, mon)) or mon.species
        pcall(Audio.playCry, sp)
    end

    -- every POKéMON in the party and the boxes, each counted: mon -> true;
    -- nil when one sits twice
    local function census(s)
        local all, n = {}, 0
        for _, mon in ipairs(s.party or {}) do
            if all[mon] then return nil end
            all[mon] = true
            n = n + 1
        end
        for _, box in ipairs(s.storage and s.storage.boxes or {}) do
            for slot = 1, platform.BOX_CAPACITY do
                local mon = box.mons and box.mons[slot]
                if mon then
                    if all[mon] then return nil end
                    all[mon] = true
                    n = n + 1
                end
            end
        end
        return all, n
    end

    -- the party and every box's slots, to put back exactly
    local function saveMons(s)
        local copy = { party = {}, boxes = {} }
        for i, mon in ipairs(s.party or {}) do copy.party[i] = mon end
        for b, box in ipairs(s.storage.boxes) do
            copy.boxes[b] = {}
            for slot = 1, platform.BOX_CAPACITY do copy.boxes[b][slot] = box.mons and box.mons[slot] end
        end
        return copy
    end

    local function restoreMons(s, copy)
        for i = #s.party, 1, -1 do s.party[i] = nil end
        for i, mon in ipairs(copy.party) do s.party[i] = mon end
        for b, box in ipairs(s.storage.boxes) do
            box.mons = box.mons or {}
            for slot = 1, platform.BOX_CAPACITY do box.mons[slot] = copy.boxes[b] and copy.boxes[b][slot] or nil end
        end
    end

    -- run fn (the engine's move), then check that exactly the same
    -- POKéMON are still there, each once, and that ok(s) holds; else put
    -- everything back
    local function guardedMove(s, fn, ok)
        local before, count = census(s)
        if not before then return nil, "stale" end
        local copy = saveMons(s)
        local done, a, b = pcall(fn)
        local after, countAfter = census(s)
        local sane = done and a and after and countAfter == count and ok()
        if sane then
            for mon in pairs(before) do
                if not after[mon] then sane = false break end
            end
        end
        if not sane then
            restoreMons(s, copy)
            mod.log:warn("pc transfer refused: %s", done and "the party or boxes did not come out as expected"
                or tostring(a))
            return nil, "stale"
        end
        return true
    end

    ---- POKéMON --------------------------------------------------------------

    -- DEPOSIT: party POKéMON uid into box `box` (its first free slot)
    function T.deposit(game, uid, box)
        local ok, why = gate(game)
        if not ok then return nil, why end
        if not wholeNumber(uid) or not wholeNumber(box) or box < 1 or box > platform.BOX_COUNT then
            return nil, "bad request"
        end
        local s = session(game)
        local Storage = need("storage")
        if not (s and s.storage and s.storage.boxes and Storage and Storage.deposit) then return nil, "not loaded" end
        local index = partyIndexOf(s, uid)
        if not index then return nil, "stale" end
        local mon = s.party[index]
        local target = s.storage.boxes[box]
        if not target then return nil, "bad request" end
        -- pret's order: MAIL, the last one that can fight, a full box
        if holdsMail(mon) then return nil, "mail" end
        if #s.party <= 1 or fighters(s.party, index) < 1 then return nil, "last mon" end
        local free
        for slot = 1, platform.BOX_CAPACITY do
            if not (target.mons and target.mons[slot]) then free = slot break end
        end
        if not free then return nil, "full" end
        local done, err = guardedMove(s, function()
            return Storage.deposit(s, index, box, free)
        end, function()
            return target.mons[free] == mon and partyIndexOf(s, uid) == nil
        end)
        if not done then return nil, err end
        cry(mon)
        return true
    end

    -- WITHDRAW: boxed POKéMON uid to the end of the party
    function T.withdraw(game, uid)
        local ok, why = gate(game)
        if not ok then return nil, why end
        if not wholeNumber(uid) then return nil, "bad request" end
        local s = session(game)
        local Storage = need("storage")
        if not (s and s.storage and Storage and Storage.withdraw) then return nil, "not loaded" end
        local box, slot = findBoxed(s.storage, uid)
        if not box then return nil, "stale" end
        if #(s.party or {}) >= 6 then return nil, "party full" end
        local mon = s.storage.boxes[box].mons[slot]
        local done, err = guardedMove(s, function()
            return Storage.withdraw(s, box, slot)
        end, function()
            return s.party[#s.party] == mon and s.storage.boxes[box].mons[slot] == nil
        end)
        if not done then return nil, err end
        cry(mon)
        return true
    end

    -- SWAP: party POKéMON partyUid and boxed POKéMON boxUid trade places
    -- (the game's own party <-> box move), with DEPOSIT's checks for the
    -- one going in; the counts stay the same
    function T.swap(game, partyUid, boxUid)
        local ok, why = gate(game)
        if not ok then return nil, why end
        if not wholeNumber(partyUid) or not wholeNumber(boxUid) then return nil, "bad request" end
        local s = session(game)
        local Storage = need("storage")
        if not (s and s.storage and Storage and Storage.moveMon) then return nil, "not loaded" end
        local index = partyIndexOf(s, partyUid)
        local box, slot = findBoxed(s.storage, boxUid)
        if not (index and box) then return nil, "stale" end
        local out, incoming = s.party[index], s.storage.boxes[box].mons[slot]
        if holdsMail(out) then return nil, "mail" end
        if fighters(s.party, index, incoming) < 1 then return nil, "last mon" end
        local done, err = guardedMove(s, function()
            return Storage.moveMon(s, "party", index, "box", slot, nil, box)
        end, function()
            return s.party[index] == incoming and s.storage.boxes[box].mons[slot] == out
        end)
        if not done then return nil, err end
        cry(incoming)
        return true
    end

    ---- items ----------------------------------------------------------------

    local function info(id)
        if not (ItemsData and ItemsData.info) then return {} end
        local ok, i = pcall(ItemsData.info, id)
        return ok and type(i) == "table" and i or {}
    end

    -- an important item (key items, the TM CASE's...): the PC won't store it
    local function important(id)
        return (tonumber(info(id).importance) or 0) ~= 0
    end

    -- An item that always moves one (the game never asks "How many?"): the
    -- KEY ITEMS, TM CASE and other important items, which show no count
    function T.onlyOne(game, id)
        local pocket = ItemsData and select(2, pcall(ItemsData.pocketOf, tonumber(id) or id))
        return pocket == "KEY_ITEMS" or pocket == "TM_CASE" or important(tonumber(id) or id)
    end

    local function pcList(s)
        s.storage.items = s.storage.items or {}
        return s.storage.items
    end

    -- the PLAYER's PC items, as its WITHDRAW list shows them; each slot
    -- keyed like the BAG's (a slot can repeat an item)
    function T.pcItems(game)
        local s = session(game)
        if not (s and s.storage) then return {} end
        local out, seen = {}, {}
        for _, slot in ipairs(s.storage.items or {}) do
            local qty = tonumber(slot.qty) or 0
            if type(slot) == "table" and slot.id and slot.id ~= 0 and qty > 0 then
                local base = "PC:" .. tostring(slot.id) .. ":" .. qty
                seen[base] = (seen[base] or 0) + 1
                local name = ItemsData and select(2, pcall(ItemsData.displayName, slot.id)) or tostring(slot.id)
                local iconId = sprites and sprites.itemIcon and select(2, pcall(sprites.itemIcon, slot.id))
                out[#out + 1] = { key = base .. ":" .. seen[base], id = tostring(slot.id),
                    name = type(name) == "string" and name or tostring(slot.id), count = qty,
                    icon = type(iconId) == "string" and ("/img/" .. iconId .. ".png") or nil,
                    one = T.onlyOne(game, slot.id) or nil }
            end
        end
        return out
    end

    -- how many of item id a list of slots holds
    local function total(slots, id)
        local n = 0
        for _, slot in ipairs(slots or {}) do
            if tostring(slot.id) == id then n = n + (tonumber(slot.qty) or 0) end
        end
        return n
    end

    local function pcTotals(list)
        local out = {}
        for _, slot in ipairs(list) do
            local k = tostring(slot.id)
            out[k] = (out[k] or 0) + (tonumber(slot.qty) or 0)
        end
        return out
    end

    local function copyPc(list)
        local copy = {}
        for i, slot in ipairs(list) do copy[i] = { table = slot, id = slot.id, qty = slot.qty } end
        return copy
    end

    local function restorePc(list, copy)
        for i = #list, 1, -1 do list[i] = nil end
        for i, e in ipairs(copy) do
            e.table.id, e.table.qty = e.id, e.qty
            list[i] = e.table
        end
    end

    -- qty and the count the page saw (one slot's, or the item's total),
    -- checked against what is there
    local function checkQuantity(game, id, qty, seen, have, slotCounts)
        if not wholeNumber(qty) or qty < 1 then return nil, "bad request" end
        if seen ~= nil then
            local match = seen == have
            for _, c in ipairs(slotCounts) do if c == seen then match = true end end
            if not match then return nil, "stale" end
        end
        if T.onlyOne(game, id) then qty = 1 end
        if qty > have then return nil, "stale" end
        return qty
    end

    local function slotCountsOf(slots, id)
        local out = {}
        for _, slot in ipairs(slots or {}) do
            if tostring(slot.id) == id then out[#out + 1] = tonumber(slot.qty) or 0 end
        end
        return out
    end

    -- the BAG and the PC as they are, checked after a move: the item's
    -- totals moved by exactly n, nothing else changed
    local function guardedItems(s, id, n, toPc, fn)
        local bag = s.bag
        local list = pcList(s)
        local bagCopy, pcCopy = edits.saveBag(bag), copyPc(list)
        local bagBefore, pcBefore = edits.bagTotals(bag), pcTotals(list)
        local done, a = pcall(fn)
        -- refused before anything moved (the PC or the BAG had no room):
        -- put back to be sure, but nothing went wrong
        if done and a == false then
            edits.restoreBag(bag, bagCopy)
            restorePc(list, pcCopy)
            return nil, "refused"
        end
        local bagAfter, pcAfter = edits.bagTotals(bag), pcTotals(list)
        local expectBag, expectPc = {}, {}
        for k, v in pairs(bagBefore) do expectBag[k] = v end
        for k, v in pairs(pcBefore) do expectPc[k] = v end
        local sign = toPc and 1 or -1
        expectBag[id] = (expectBag[id] or 0) - sign * n
        expectPc[id] = (expectPc[id] or 0) + sign * n
        local sane = done and a
        local function same(x, y)
            for k, v in pairs(x) do if (y[k] or 0) ~= v then return false end end
            for k, v in pairs(y) do if (x[k] or 0) ~= v then return false end end
            return true
        end
        sane = sane and same(bagAfter, expectBag) and same(pcAfter, expectPc)
        if not sane then
            edits.restoreBag(bag, bagCopy)
            restorePc(list, pcCopy)
            mod.log:warn("item transfer refused: %s", done and "the BAG or the PC did not come out as expected"
                or tostring(a))
            return nil, "stale"
        end
        return true
    end

    -- DEPOSIT ITEM: qty of bag item id into the PC
    function T.itemToPc(game, id, qty, seen)
        local ok, why = gate(game)
        if not ok then return nil, why end
        if type(id) ~= "string" then return nil, "bad request" end
        local s = session(game)
        local Storage, Bag = need("storage"), need("bag")
        if not (s and s.bag and s.storage and Storage and Storage.addPcItem and Bag and Bag.remove) then
            return nil, "not loaded"
        end
        local bagTotals = edits.bagTotals(s.bag)
        local have = bagTotals[id] or 0
        if have <= 0 then return nil, "stale" end
        -- item_menu.c: "That's too important to store"
        local itemId = tonumber(id) or id
        if important(itemId) then return nil, "important" end
        local slotCounts = {}
        for _, key in ipairs({ "ITEMS", "KEY_ITEMS", "POKE_BALLS", "TM_CASE", "BERRY_POUCH" }) do
            for _, c in ipairs(slotCountsOf(s.bag.pockets[key], id)) do slotCounts[#slotCounts + 1] = c end
        end
        local n, err = checkQuantity(game, id, qty, seen, have, slotCounts)
        if not n then return nil, err end
        -- the PC first (it may be full), only then out of the BAG
        local added = false
        local done, gerr = guardedItems(s, id, n, true, function()
            local okAdd = Storage.addPcItem(s, itemId, n)
            if not okAdd then return false end
            added = true
            Bag.remove(s.bag, itemId, n)
            return true
        end)
        if not done then
            if not added then return nil, "pc full" end
            return nil, gerr
        end
        local Q = need("quest_log_recorder")
        if Q and Q.event and ItemsData then
            pcall(Q.event, s, "StoredItemInPC", { ItemsData.displayName(itemId) })
        end
        return true
    end

    -- WITHDRAW ITEM: qty of PC item id into the BAG
    function T.itemToBag(game, id, qty, seen)
        local ok, why = gate(game)
        if not ok then return nil, why end
        if type(id) ~= "string" then return nil, "bad request" end
        local s = session(game)
        local Bag = need("bag")
        if not (s and s.bag and s.storage and Bag and Bag.canAdd and Bag.add) then return nil, "not loaded" end
        local list = pcList(s)
        local have = total(list, id)
        if have <= 0 then return nil, "stale" end
        local n, err = checkQuantity(game, id, qty, seen, have, slotCountsOf(list, id))
        if not n then return nil, err end
        local itemId = tonumber(id) or id
        -- into the BAG first (it may be full), only then out of the PC
        local okCan, can = pcall(Bag.canAdd, s.bag, itemId, n)
        if not (okCan and can) then return nil, "bag full" end
        local done, gerr = guardedItems(s, id, n, false, function()
            if not Bag.add(s.bag, itemId, n) then return false end
            -- item.c RemovePCItem: from the item's slots, first to last,
            -- an emptied slot closing up (ItemPcCompaction)
            local left = n
            local i = 1
            while left > 0 and i <= #list do
                local slot = list[i]
                if tostring(slot.id) == id then
                    local take = math.min(left, tonumber(slot.qty) or 0)
                    slot.qty = (tonumber(slot.qty) or 0) - take
                    left = left - take
                    if slot.qty <= 0 then
                        table.remove(list, i)
                    else
                        i = i + 1
                    end
                else
                    i = i + 1
                end
            end
            return left == 0
        end)
        if not done then return nil, gerr == "refused" and "bag full" or gerr end
        local Q = need("quest_log_recorder")
        if Q and Q.event and ItemsData then
            pcall(Q.event, s, "WithdrewItemFromPC", { ItemsData.displayName(itemId) })
        end
        return true
    end

    return T
end
