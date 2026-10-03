-- Gen 3 (FireRed / LeafGreen) twin of edits.lua: the phone's SWITCH, BAG
-- swaps / SORT / UNDO and PC box moves, on the live session. Same functions
-- the page already calls, so main.lua only picks this file on Gen 3.
--
-- Keeping the save sound is the whole point of this file:
--
--   * An edit only ever REORDERS what is there. Bag slots are moved, never
--     rebuilt (each { id, qty } table stays the same table); POKéMON tables
--     move between slots. Nothing is created, dropped, split or merged.
--   * It runs only when the game is in free roam with nothing open: no
--     menu (BAG, PC, party, shop, save...), text, YES / NO, script, battle,
--     warp or step in progress (the checks below, the same ones the engine's
--     own mod API makes for a party SWITCH). If any check can't be made,
--     the edit is refused, never guessed.
--   * It completes in one go on the main thread, between two game frames,
--     so a save the game writes sees the old or the new order, never half.
--   * Every edit first copies what it touches, then checks afterwards that
--     exactly the same slots / POKéMON are still there, each once; if not,
--     the copy is put back and the edit is refused.
--   * The page names things by the ids it saw (item ids, POKéMON uids): if
--     the game changed in between, the edit is refused as stale instead of
--     hitting a different entry.
return function(mod, uids, platform)
    local E = {}

    local function need(name)
        local ok, m = pcall(require, "src.core.game3." .. name)
        return ok and type(m) == "table" and m or nil
    end

    local ItemsData = need("items_data")

    ---- when an edit may run --------------------------------------------------

    -- true, or false and why: "not loaded" (no session / not in the field),
    -- "walking" (a step in progress: may wait for it), "busy" (anything else)
    local function freeRoam(game)
        local session = platform.save(game)
        if not session then return false, "not loaded" end
        if game.phase ~= nil and game.phase ~= "field" then return false, "not loaded" end
        local Field = need("field")
        if not (Field and Field.running) then return false, "not loaded" end
        if Field.locked then return false, "busy" end
        local Runtime = need("runtime")
        if not (Runtime and Runtime.uiBusy) then return false, "busy" end
        local okU, ui = pcall(Runtime.uiBusy)
        if not okU or ui then return false, "busy" end
        local Space = need("scripting.space")
        local vm = Space and Space.vm
        if vm and vm.isRunning then
            local okV, running = pcall(vm.isRunning, vm)
            if not okV or running then return false, "busy" end
        end
        local Battle = need("battle")
        if Battle and Battle.isActive then
            local okB, active = pcall(Battle.isActive)
            if not okB or active then return false, "busy" end
        end
        local Warp = need("warp")
        if Warp and Warp.isBusy then
            local okW, warping = pcall(Warp.isBusy)
            if not okW or warping then return false, "busy" end
        end
        local Player = need("player")
        if Player and Player.moving then return false, "walking" end
        return true
    end

    -- shared with actions3.lua: the same free-roam test for the quick actions
    E.freeRoam = freeRoam

    -- the page's reasons (main.lua ERRORS). Walking counts as editable, as
    -- on Gen 1 / 2: an edit made mid-step waits for the step (whenFree).
    -- Reporting it as busy would flip on every step, and each flip makes
    -- the page rebuild the whole BAG and PC.
    function E.editable(game)
        local ok, why = freeRoam(game)
        if ok or why == "walking" then return true end
        return false, why
    end

    local function swapSound()
        -- SE_SELECT, the sound the game's own SELECT swap makes
        local Audio = need("audio")
        if Audio and Audio.playSe then pcall(Audio.playSe, 5) end
    end

    ---- a request made mid-step waits for the step to end ------------------------

    local WAIT_SECONDS = 2
    local pending -- { run = fn, expires }

    -- run fn now if the game is free, queue it briefly if only a step is in
    -- the way, else refuse
    local function whenFree(game, fn)
        local ok, why = freeRoam(game)
        if ok then return fn() end
        if why == "walking" then
            pending = { run = fn, expires = love.timer.getTime() + WAIT_SECONDS }
            return true
        end
        return nil, why
    end

    -- a scene item started from the phone (see E.useItem): the game's party
    -- menu, opened on the item with its cursor on the POKéMON, gets one A
    -- press on the next frame, then is closed once its flow has played out
    local scene = nil -- { menu, pressed, started }
    local SCENE_TIMEOUT = 600
    -- a one-frame input: A pressed, nothing else
    local PRESS_A = setmetatable({ wasPressed = function(_, key) return key == "a" end },
        { __index = function() return function() return false end end })

    local function moduleOpen(name)
        local ok, m = pcall(require, name)
        if not (ok and type(m) == "table") then return false end
        if type(m.isOpen) == "function" then
            local okO, open = pcall(m.isOpen)
            return okO and open and true or false
        end
        return m.open and true or false
    end

    local function tickScene()
        local m = scene.menu
        if love.timer.getTime() - scene.started > SCENE_TIMEOUT then scene = nil return end
        if not scene.pressed then
            scene.pressed = true
            if m.isOpen() and m.mode == "use" then
                local ok, err = pcall(m.handleInput, PRESS_A)
                if not ok then mod.log:warn("use: the party menu refused: %s", tostring(err)) end
            else
                scene = nil
            end
            return
        end
        if not m.isOpen() then scene = nil return end
        -- the flow is over when the menu is back to waiting, with nothing
        -- of it still on screen: back to the field
        local idle = (m.mode == "use" or m.mode == "list") and not m._hpAnim
            and not moduleOpen("src.ui.game3.evolution_scene")
            and not moduleOpen("src.ui.game3.summary_menu")
        if idle then
            pcall(m.close)
            scene = nil
        end
    end

    function E.tick(game)
        if scene then tickScene() end
        if not pending then return end
        if love.timer.getTime() > pending.expires then
            pending = nil
            return
        end
        local ok, why = freeRoam(game)
        if ok then
            local run = pending.run
            pending = nil
            local done, err = pcall(run)
            if not done then mod.log:warn("queued edit failed: %s", tostring(err)) end
        elseif why ~= "walking" then
            pending = nil -- something else opened: drop it, never run it late
        end
    end

    ---- party ---------------------------------------------------------------

    local function partySlotOf(party, uid)
        for i, mon in ipairs(party or {}) do
            if uids.of(mon) == uid then return i end
        end
        return nil
    end

    function E.partyEditable(game)
        local session = platform.save(game)
        if not session then return false, "not loaded" end
        if #(session.party or {}) < 2 then return false, "one mon" end
        local ok, why = freeRoam(game)
        if ok or why == "walking" then return true end
        return false, why == "busy" and "party busy" or why
    end

    -- The game's SWITCH through the engine's own mod API
    -- (WorldAPI:reorderParty: swaps the slots and their move overlay,
    -- plays the sound). Checked afterwards: the same mons, each once.
    function E.partySwap(game, uidA, uidB)
        if type(uidA) ~= "number" or type(uidB) ~= "number" then return nil, "bad request" end
        local ok, why = E.partyEditable(game)
        if not ok then return nil, why end
        return whenFree(game, function()
            local session = platform.save(game)
            local party = session and session.party or {}
            local a, b = partySlotOf(party, uidA), partySlotOf(party, uidB)
            if not (a and b) then return nil, "stale" end
            local before = {}
            for i, mon in ipairs(party) do before[i] = mon end
            -- the move overlay rides the party slots (WorldAPI swaps both)
            local overlay = type(session.move_overlay) == "table" and session.move_overlay or nil
            local overlayBefore = {}
            if overlay then for k, v in pairs(overlay) do overlayBefore[k] = v end end
            local w = mod.world
            local okR, done, err = pcall(w.reorderParty, w, a, b)
            if okR and not done then
                -- refused by the game: nothing was changed
                return nil, err == "world is busy" and "party busy" or "stale"
            end
            -- the same mons, each once, and the two swapped
            local sane = okR and #party == #before and party[a] == before[b] and party[b] == before[a]
            for i, mon in ipairs(before) do
                if i ~= a and i ~= b and party[i] ~= mon then sane = false end
            end
            if not sane then
                for i = 1, math.max(#party, #before) do party[i] = before[i] end
                if overlay then
                    for k in pairs(overlay) do overlay[k] = nil end
                    for k, v in pairs(overlayBefore) do overlay[k] = v end
                end
                mod.log:warn("party swap refused: %s", okR and "the party did not come out as expected" or tostring(done))
                return nil, "stale"
            end
            return true
        end)
    end

    ---- bag -----------------------------------------------------------------

    -- TM CASE and BERRY POUCH: the game keeps them sorted by number
    -- (bag.lua sort_pocket, item.c), so their order can't be changed
    local FIXED = { TM_CASE = true, BERRY_POUCH = true }

    function E.pocketFixed(_, pocket) return FIXED[pocket] == true end

    local function pocketKeys()
        local order = ItemsData and ItemsData.POCKET_ORDER
        if order and #order > 0 then return order end
        return { "ITEMS", "KEY_ITEMS", "POKE_BALLS", "TM_CASE", "BERRY_POUCH" }
    end

    -- always read fresh: the engine replaces pocket tables when it tidies
    local function pockets(game)
        local session = platform.save(game)
        local bag = session and session.bag
        return bag and type(bag.pockets) == "table" and bag.pockets or nil
    end

    -- a plain item id: the one slot holding it (nil if none, or several)
    local function findPlainId(p, id)
        local hitPocket, hitIndex, hits = nil, nil, 0
        for _, key in ipairs(pocketKeys()) do
            for i, slot in ipairs(p[key] or {}) do
                if type(slot) == "table" and tostring(slot.id) == id then
                    hits = hits + 1
                    hitPocket, hitIndex = key, i
                end
            end
        end
        if hits ~= 1 then return nil end
        return hitPocket, hitIndex
    end

    -- The slot a page reference names: "POCKET:id:qty:n" is the n-th slot
    -- of that pocket holding that item with that count (snapshot3.lua
    -- slotRefs; a pocket can hold one item in two slots). Returns the
    -- pocket and slot index, or nil when no such slot is there (stale).
    -- A plain item id still works where it is in exactly one slot.
    local function findItem(p, ref)
        local pocket, id, qty, n = tostring(ref):match("^([%u_]+):([^:]+):(%d+):(%d+)$")
        if pocket then
            qty, n = tonumber(qty), tonumber(n)
            local k = 0
            for i, slot in ipairs(p[pocket] or {}) do
                if type(slot) == "table" and tostring(slot.id) == id and (tonumber(slot.qty) or 0) == qty then
                    k = k + 1
                    if k == n then return pocket, i end
                end
            end
            return nil
        end
        return findPlainId(p, ref)
    end

    -- A pocket's slots copied, and a check that `slots` holds exactly those
    -- same slot tables (each once, none new, none gone, ids and counts as
    -- they were)
    local function snapshot(slots)
        local copy = { list = {}, id = {}, qty = {} }
        for i, s in ipairs(slots) do
            copy.list[i] = s
            copy.id[s] = s.id
            copy.qty[s] = s.qty
        end
        return copy
    end

    local function intact(slots, copy)
        if #slots ~= #copy.list then return false end
        local seen = {}
        for _, s in ipairs(slots) do
            if seen[s] or copy.id[s] == nil then return false end
            if s.id ~= copy.id[s] or s.qty ~= copy.qty[s] then return false end
            seen[s] = true
        end
        return true
    end

    local function restore(slots, copy)
        for i = #slots, 1, -1 do slots[i] = nil end
        for i, s in ipairs(copy.list) do slots[i] = s end
    end

    -- rearrange one pocket in place with fn(slots); undone if the result
    -- isn't the same slots in another order
    local function rearrange(slots, fn)
        local copy = snapshot(slots)
        local okF, err = pcall(fn, slots)
        if not okF or not intact(slots, copy) then
            restore(slots, copy)
            mod.log:warn("bag edit refused: %s", okF and "the pocket did not come out as expected" or tostring(err))
            return nil, "stale"
        end
        return true
    end

    -- the BAG's SELECT swap: two items of one pocket trade places
    function E.bagSwap(game, a, b)
        if type(a) ~= "string" or type(b) ~= "string" then return nil, "bad request" end
        return whenFree(game, function()
            local p = pockets(game)
            if not p then return nil, "not loaded" end
            local pa, ia = findItem(p, a)
            local pb, ib = findItem(p, b)
            if not (pa and pb) then return nil, "stale" end
            if pa ~= pb then return nil, "other pocket" end
            if FIXED[pa] then return nil, "fixed pocket" end
            if ia == ib then return true end
            local done, err = rearrange(p[pa], function(slots)
                slots[ia], slots[ib] = slots[ib], slots[ia]
            end)
            if done then swapSound() end
            return done, err
        end)
    end

    -- SORT, within each pocket (TM CASE / BERRY POUCH stay as the game keeps
    -- them): "number" = the game's item order, "name" = A-Z, "kind" = the
    -- groups the Gen 1 / 2 sort uses (bagsort.lua RANK), each by number:
    --   MEDICINE  heals HP / status / fainting / PP (fieldUse heal, status,
    --             revive, pp)
    --   BATTLE    battle-only items: X items, GUARD SPEC., POKé DOLL
    --   BOOSTS    raise a POKéMON for good: vitamins, RARE CANDY, PP UP,
    --             evolution stones
    --   FIELD     used on the map: REPELs, ESCAPE ROPE, flutes...
    --   HOLD      items with a hold effect (LEFTOVERS, SOOTHE BELL...)
    --   MAIL, then the rest (NUGGETs, shards...)
    -- read from the ROM's item data (items_data.info: fieldUse, battleUsage,
    -- holdEffect), so a mod's item sorts with its kind
    local function info(id)
        if not (ItemsData and ItemsData.info) then return {} end
        local ok, i = pcall(ItemsData.info, id)
        return ok and type(i) == "table" and i or {}
    end

    local MEDICINE = { heal = true, status = true, revive = true, pp = true }
    local BOOSTS = { vitamin = true, level = true, evo = true, pp_up = true, ppup = true, ppmax = true }
    -- pokefirered/include/constants/items.h ITEM_ORANGE_MAIL .. ITEM_RETRO_MAIL
    local FIRST_MAIL, LAST_MAIL = 121, 132

    local function kindRank(id)
        local i = info(id)
        local use = type(i.fieldUse) == "string" and i.fieldUse:lower() or "none"
        local battle = tonumber(i.battleUsage) or 0
        -- PP UP / PP MAX share ETHER's "pp" but can't be used in battle:
        -- they raise a move for good, so they are BOOSTS
        if use == "pp" and battle == 0 then return 3 end
        if MEDICINE[use] then return 1 end
        if use == "battle" or (battle > 0 and use == "none") then return 2 end
        if BOOSTS[use] then return 3 end
        if use ~= "none" then return 4 end
        if (tonumber(i.holdEffect) or 0) > 0 then return 5 end
        local n = tonumber(i.id)
        if n and n >= FIRST_MAIL and n <= LAST_MAIL then return 6 end
        return 7
    end

    local function numberOf(id)
        local n = tonumber(id)
        if not n and ItemsData and ItemsData.toNumericId then
            local ok, v = pcall(ItemsData.toNumericId, id)
            n = ok and tonumber(v) or nil
        end
        return n or math.huge
    end

    local function nameOf(id)
        local ok, n = pcall(ItemsData.displayName, id)
        return ok and tostring(n) or tostring(id)
    end

    local SORTS = {
        number = function(s) return { numberOf(s.id) } end,
        name = function(s) return { nameOf(s.id), numberOf(s.id) } end,
        kind = function(s) return { kindRank(s.id), numberOf(s.id) } end,
    }

    local function less(ka, kb)
        for i = 1, #ka do
            if ka[i] ~= kb[i] then return ka[i] < kb[i] end
        end
        return false
    end

    function E.bagSort(game, by)
        local keyOf = SORTS[by]
        if not keyOf then return nil, "bad request" end
        return whenFree(game, function()
            local p = pockets(game)
            if not p then return nil, "not loaded" end
            local changed = false
            for _, key in ipairs(pocketKeys()) do
                local slots = p[key]
                if not FIXED[key] and type(slots) == "table" and #slots > 1 then
                    local keys, sorted = {}, {}
                    for i, s in ipairs(slots) do
                        keys[s] = keyOf(s)
                        sorted[i] = s
                    end
                    -- a stable sort: ties keep their order
                    local pos = {}
                    for i, s in ipairs(slots) do pos[s] = i end
                    table.sort(sorted, function(x, y)
                        if less(keys[x], keys[y]) then return true end
                        if less(keys[y], keys[x]) then return false end
                        return pos[x] < pos[y]
                    end)
                    local done, err = rearrange(slots, function(t)
                        for i, s in ipairs(sorted) do
                            if t[i] ~= s then changed = true end
                            t[i] = s
                        end
                    end)
                    if not done then return nil, err end
                end
            end
            if changed then swapSound() end
            return true
        end)
    end

    -- UNDO for SORT: every pocket back to an order the page saw (all ids of
    -- all pockets, in the snapshot's order). Only an exact rearrangement of
    -- what is there now is accepted.
    function E.bagSetOrder(game, ids)
        if type(ids) ~= "table" then return nil, "bad request" end
        return whenFree(game, function()
            local p = pockets(game)
            if not p then return nil, "not loaded" end
            -- each reference to its own slot, split by pocket in the page's
            -- order; every slot exactly once
            local want, total, used = {}, 0, {}
            for _, key in ipairs(pocketKeys()) do
                want[key] = {}
                total = total + #(p[key] or {})
            end
            if #ids ~= total then return nil, "stale" end
            for _, ref in ipairs(ids) do
                if type(ref) ~= "string" then return nil, "bad request" end
                local key, index = findItem(p, ref)
                if not key then return nil, "stale" end
                local slot = p[key][index]
                if used[slot] then return nil, "stale" end
                used[slot] = true
                local w = want[key]
                w[#w + 1] = slot
            end
            local changed = false
            for _, key in ipairs(pocketKeys()) do
                local slots = p[key]
                if type(slots) == "table" and #slots > 0 then
                    if FIXED[key] then
                        for i, slot in ipairs(want[key]) do
                            if slots[i] ~= slot then return nil, "stale" end
                        end
                    else
                        local done, err = rearrange(slots, function(t)
                            for i, slot in ipairs(want[key]) do
                                if t[i] ~= slot then changed = true end
                                t[i] = slot
                            end
                        end)
                        if not done then return nil, err end
                    end
                end
            end
            if changed then swapSound() end
            return true
        end)
    end

    ---- PC boxes --------------------------------------------------------------

    -- a boxed mon by uid: box number and slot (boxes keep 30 fixed slots
    -- with holes: storage.boxes[b].mons[slot])
    local function findBoxed(storage, uid)
        for b, box in ipairs(storage.boxes or {}) do
            for s = 1, platform.BOX_CAPACITY do
                local mon = box.mons and box.mons[s]
                if mon and uids.of(mon) == uid then return b, s end
            end
        end
        return nil
    end

    -- every boxed mon once: mon -> "b:s"; nil when a mon sits twice
    local function census(storage)
        local where, n = {}, 0
        for b, box in ipairs(storage.boxes or {}) do
            for s = 1, platform.BOX_CAPACITY do
                local mon = box.mons and box.mons[s]
                if mon then
                    if where[mon] then return nil end
                    where[mon] = b .. ":" .. s
                    n = n + 1
                end
            end
        end
        return where, n
    end

    -- Swap monUid with targetUid (any boxes), or without a target move it to
    -- the first empty slot of targetBox, the way the PC's MOVE drops it.
    -- The game's own Storage.moveMon does the move (its heal and quest log);
    -- afterwards every boxed mon must still be there exactly once.
    function E.boxMove(game, monUid, targetUid, targetBox)
        if type(monUid) ~= "number" then return nil, "bad request" end
        return whenFree(game, function()
            local session = platform.save(game)
            local Storage = need("storage")
            local storage = session and session.storage
            if not (Storage and Storage.moveMon and storage and storage.boxes) then return nil, "not loaded" end
            local fromBox, fromSlot = findBoxed(storage, monUid)
            if not fromBox then return nil, "stale" end
            local toBox, toSlot
            if targetUid ~= nil then
                if type(targetUid) ~= "number" then return nil, "bad request" end
                toBox, toSlot = findBoxed(storage, targetUid)
                if not toBox then return nil, "stale" end
            else
                if type(targetBox) ~= "number" or targetBox ~= math.floor(targetBox)
                    or targetBox < 1 or targetBox > platform.BOX_COUNT or not storage.boxes[targetBox] then
                    return nil, "bad request"
                end
                if targetBox == fromBox then return true end
                local mons = storage.boxes[targetBox].mons or {}
                for s = 1, platform.BOX_CAPACITY do
                    if mons[s] == nil then toSlot = s break end
                end
                if not toSlot then return nil, "full" end
                toBox = targetBox
            end
            if toBox == fromBox and toSlot == fromSlot then return true end

            -- the boxes as they are, to check against and to put back
            local before, count = census(storage)
            if not before then return nil, "stale" end
            local saved = {}
            for b, box in ipairs(storage.boxes) do
                saved[b] = {}
                for s = 1, platform.BOX_CAPACITY do saved[b][s] = box.mons and box.mons[s] end
            end
            local moving, other = storage.boxes[fromBox].mons[fromSlot], storage.boxes[toBox].mons[toSlot]

            local okM, done = pcall(Storage.moveMon, session, "box", fromSlot, "box", toSlot, fromBox, toBox)
            local after, countAfter = census(storage)
            local sane = okM and done and after and countAfter == count
                and storage.boxes[toBox].mons[toSlot] == moving
                and storage.boxes[fromBox].mons[fromSlot] == other
            if sane then
                for mon in pairs(before) do
                    if not after[mon] then sane = false break end
                end
            end
            if not sane then
                for b, box in ipairs(storage.boxes) do
                    box.mons = box.mons or {}
                    for s = 1, platform.BOX_CAPACITY do box.mons[s] = saved[b] and saved[b][s] or nil end
                end
                mod.log:warn("box move refused: %s", okM and "the boxes did not come out as expected" or tostring(done))
                return nil, "stale"
            end
            swapSound()
            return true
        end)
    end

    ---- GIVE TO HOLD ---------------------------------------------------------

    local function isMail(id)
        local Mail = need("mail")
        if not (Mail and Mail.isMailItem) then return false end
        local ok, is = pcall(Mail.isMailItem, tonumber(id) or id)
        return ok and is or false
    end
    E.isMail = isMail

    -- the game's own rule (item_use.lua checkGive): no KEY ITEMS, nothing
    -- from the TM CASE
    function E.canHold(_, id)
        if not (ItemsData and ItemsData.pocketOf) then return false end
        local ok, pocket = pcall(ItemsData.pocketOf, id)
        return ok and pocket ~= "KEY_ITEMS" and pocket ~= "TM_CASE"
    end

    -- every item in the bag and its count: id -> qty, over all pockets
    local function bagTotals(bag)
        local out = {}
        for _, key in ipairs(pocketKeys()) do
            for _, s in ipairs(bag.pockets[key] or {}) do
                local k = tostring(s.id)
                out[k] = (out[k] or 0) + (tonumber(s.qty) or 0)
            end
        end
        return out
    end

    -- the bag as it is, to put back exactly (Bag.add / remove may rebuild a
    -- pocket's table, so the pockets and their slots are copied)
    local function saveBag(bag)
        local copy = { pockets = {}, stacks = nil }
        for key, slots in pairs(bag.pockets) do
            local list = {}
            for i, s in ipairs(slots) do list[i] = { table = s, id = s.id, qty = s.qty } end
            copy.pockets[key] = { table = slots, list = list }
        end
        if type(bag.stacks) == "table" then
            copy.stacks = {}
            for k, v in pairs(bag.stacks) do copy.stacks[k] = v end
        end
        return copy
    end

    local function restoreBag(bag, copy)
        for key in pairs(bag.pockets) do
            if not copy.pockets[key] then bag.pockets[key] = nil end
        end
        for key, c in pairs(copy.pockets) do
            local slots = c.table
            for i = #slots, 1, -1 do slots[i] = nil end
            for i, e in ipairs(c.list) do
                e.table.id, e.table.qty = e.id, e.qty
                slots[i] = e.table
            end
            bag.pockets[key] = slots
        end
        if copy.stacks then
            for k in pairs(bag.stacks) do bag.stacks[k] = nil end
            for k, v in pairs(copy.stacks) do bag.stacks[k] = v end
        end
    end

    -- shared with transfer3.lua (PC TRANSFERS), which guards its moves the
    -- same way
    E.saveBag, E.restoreBag, E.bagTotals = saveBag, restoreBag, bagTotals

    -- The game's GIVE from the BAG (item_use.lua ItemUse.giveToMon: its
    -- checks, the swap when the POKéMON already holds something, the bag-
    -- full refusal, the quest log): bag item id to party POKéMON uid.
    -- Checked afterwards: one of the item left the bag, the old held item
    -- (if any) came back, nothing else changed, and the POKéMON holds the
    -- item. Anything else is put back as it was.
    function E.giveItem(game, id, uid)
        if type(id) ~= "string" or type(uid) ~= "number" then return nil, "bad request" end
        return whenFree(game, function()
            local session = platform.save(game)
            local ItemUse = need("item_use")
            local bag = session and session.bag
            if not (ItemUse and ItemUse.giveToMon and bag and type(bag.pockets) == "table") then
                return nil, "not loaded"
            end
            local slot = partySlotOf(session.party, uid)
            if not slot then return nil, "stale" end
            local mon = session.party[slot]
            local Pokemon = need("pokemon")
            if Pokemon and Pokemon.isEgg and Pokemon.isEgg(mon) then return nil, "egg" end
            if not E.canHold(game, id) then return nil, "cant hold" end
            -- MAIL needs a letter: the game opens its keyboard for that
            if isMail(id) then return nil, "mail give" end
            local before = bagTotals(bag)
            if (before[id] or 0) < 1 then return nil, "stale" end
            local itemId = tonumber(id) or id
            local held = mon.item or mon.heldItem
            if held == 0 or held == "" or held == "NONE" then held = nil end
            if held and tostring(held) == id then return true end
            if held and isMail(held) then return nil, "mail" end

            local bagCopy = saveBag(bag)
            local monCopy = { item = mon.item, heldItem = mon.heldItem }
            local function undo(why)
                restoreBag(bag, bagCopy)
                mon.item, mon.heldItem = monCopy.item, monCopy.heldItem
                if why then mod.log:warn("give refused: %s", why) end
            end

            local okG, done, reason = pcall(ItemUse.giveToMon, session, bag, itemId, slot)
            if not okG then
                undo(tostring(done))
                return nil, "stale"
            end
            if not done then
                undo()
                if reason == "bag_full" then return nil, "bag full" end
                if reason == "mail" then return nil, "mail" end
                if reason == "cant_hold" then return nil, "cant hold" end
                return nil, "stale"
            end

            -- exactly: one less of the item, one more of the old held item
            local after = bagTotals(bag)
            local expect = {}
            for k, v in pairs(before) do expect[k] = v end
            expect[id] = expect[id] - 1
            if held then
                local hk = tostring(held)
                expect[hk] = (expect[hk] or 0) + 1
            end
            local sane = tostring(mon.item or mon.heldItem) == tostring(itemId)
            for k, v in pairs(expect) do
                if (after[k] or 0) ~= v then sane = false end
            end
            for k, v in pairs(after) do
                if (expect[k] or 0) ~= v then sane = false end
            end
            if not sane then
                undo("the bag or the POKéMON did not come out as expected")
                return nil, "stale"
            end
            return true
        end)
    end

    ---- USE ON A POKéMON (medicine, vitamins, PP) ------------------------------

    -- the game's message as one line for the phone: its line and page breaks
    -- as spaces, and the placeholders the text box would fill in (the
    -- player's name, Gold's # for POKé)
    local function gameText(t, player)
        if type(t) == "table" then
            local parts = {}
            for _, s in ipairs(t) do
                local one = gameText(s, player)
                if one then parts[#parts + 1] = one end
            end
            return #parts > 0 and table.concat(parts, " ") or nil
        end
        if type(t) ~= "string" then return nil end
        player = tostring(player or "")
        t = t:gsub("{PLAYER}", player):gsub("<PLAYER>", player):gsub("#MON", "POKéMON"):gsub("#", "POKé")
        t = t:gsub("%c+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        return t ~= "" and t or nil
    end

    E.gameText = gameText

    -- the field-use kinds of item_use.lua's party branch the phone may use;
    -- RARE CANDY ("level"), the stones ("evo") and TMs play scenes in the
    -- game: not here
    local USE_KINDS = { heal = true, status = true, revive = true, vitamin = true, pp = true }

    -- RARE CANDY, the stones and TMs / HMs: picked on the phone, played on
    -- the game screen by its own party menu
    local SCENE_KINDS = { level = true, evo = true, tm = true }

    -- "mon" (pick a POKéMON), "move" (then one of its moves), "scene" or nil
    function E.useKind(_, id)
        local ItemsData, ItemUse = need("items_data"), need("item_use")
        if not (ItemsData and ItemUse and ItemsData.fieldUseKind) then return nil end
        local itemId = tonumber(id) or id
        local okK, kind = pcall(ItemsData.fieldUseKind, itemId)
        if okK and SCENE_KINDS[kind] then return "scene" end
        local okT, tm = pcall(ItemsData.isTm, itemId)
        if okT and tm then return "scene" end
        if not (okK and USE_KINDS[kind]) then return nil end
        if kind == "pp" then
            local okM, picks = pcall(ItemUse.ppItemNeedsMove, itemId)
            if okM and picks then return "move" end
        end
        return "mon"
    end

    -- For a TM / HM or a stone: what each party POKéMON makes of it, as the
    -- party menu marks it ("able", "learned", "no"), keyed by uid; nil else
    function E.ableFor(game, id)
        local ItemsData, ItemUse = need("items_data"), need("item_use")
        if not (ItemsData and ItemUse) then return nil end
        local session = platform.save(game)
        local itemId = tonumber(id) or id
        local okK, kind = pcall(ItemsData.fieldUseKind, itemId)
        local okT, tm = pcall(ItemsData.isTm, itemId)
        tm = (okT and tm) or (okK and kind == "tm")
        local stone = okK and kind == "evo"
        if not (tm or stone) then return nil end
        local Evolution = stone and need("evolution")
        local Pokemon = need("pokemon")
        local out = {}
        for _, mon in ipairs(session and session.party or {}) do
            local uid = uids.of(mon)
            local mark = "no"
            local egg = Pokemon and Pokemon.isEgg and Pokemon.isEgg(mon)
            if uid and not egg then
                if tm then
                    local okP, status = pcall(ItemUse.checkTmPreflight, mon, itemId)
                    if okP and status == "ok" then mark = "able"
                    elseif okP and status == "knows" then mark = "learned" end
                elseif Evolution and Evolution.itemTarget then
                    local okE, to = pcall(Evolution.itemTarget, mon, itemId, session)
                    if okE and to then mark = "able" end
                end
            end
            if uid then out[tostring(uid)] = mark end
        end
        return out
    end

    -- A scene item: the phone checks what the party menu would refuse (so
    -- the game never stops on a refusal nobody asked for there), then opens
    -- the game's own party menu on the item with its cursor on the POKéMON,
    -- as the BAG does (bag_menu.lua), and E.tick presses A once. The menu
    -- then plays it all as in the game: the level-up and its stats, the moves
    -- (the forget prompt through the summary), the evolution, the TM's teach.
    local function startScene(game, id, uid)
        local session = platform.save(game)
        local bag = session and session.bag
        local ItemsData, ItemUse, Pokemon = need("items_data"), need("item_use"), need("pokemon")
        if not (bag and ItemsData and ItemUse) then return nil, "not loaded" end
        if scene then return nil, "party busy" end
        local slot = partySlotOf(session.party, uid)
        if not slot then return nil, "stale" end
        local mon = session.party[slot]
        if Pokemon and Pokemon.isEgg and Pokemon.isEgg(mon) then return nil, "egg use" end
        if (bagTotals(bag)[id] or 0) < 1 then return nil, "stale" end
        local itemId = tonumber(id) or id
        local player = session.playerName or (session.player and session.player.name)
        local okK, kind = pcall(ItemsData.fieldUseKind, itemId)
        local okT, tm = pcall(ItemsData.isTm, itemId)
        if (okT and tm) or (okK and kind == "tm") then
            local okP, status, text = pcall(ItemUse.checkTmPreflight, mon, itemId)
            if not okP then return nil, "stale" end
            if status ~= "ok" then return nil, gameText(text, player) or "no effect" end
        elseif okK and kind == "evo" then
            local Evolution = need("evolution")
            local okE, to = false, nil
            if Evolution and Evolution.itemTarget then okE, to = pcall(Evolution.itemTarget, mon, itemId, session) end
            if not (okE and to) then return nil, "no effect" end
        elseif okK and kind == "level" then
            if (tonumber(mon.level) or 1) >= 100 or (tonumber(mon.hp) or 0) <= 0 then return nil, "no effect" end
        end
        local okS, Screens = pcall(require, "src.ui.game3.screens")
        local okM, menu = false, nil
        if okS and Screens.get then okM, menu = pcall(Screens.get, "party", session) end
        if not (okM and type(menu) == "table" and menu.show and menu.handleInput and menu.isOpen) then
            return nil, "unavailable"
        end
        local okO, err = pcall(menu.show, session.party, session.moveOverlay or session.move_overlay, {
            session = session, bag = bag, item = itemId, mode = "use",
        })
        if not okO then
            mod.log:warn("use: the party menu didn't open: %s", tostring(err))
            return nil, "unavailable"
        end
        menu.cursor = slot
        scene = { menu = menu, pressed = false, started = love.timer.getTime() }
        return true
    end

    -- The game's own use from the BAG (item_use.lua ItemUse.useField: its
    -- checks, the heal / cure / revive / vitamin / PP, the friendship of the
    -- bitter herbs, one out of the bag, the quest log, and the "item.use"
    -- hook other mods wrap). Free roam only. Returns true plus { text = the
    -- game's message }, or nil plus the reason (the game's own words when it
    -- refuses). Checked afterwards: the bag lost exactly one of the item
    -- and nothing else; otherwise the bag is put back as it was.
    function E.useItem(game, id, uid, moveSlot)
        if type(id) ~= "string" or type(uid) ~= "number" then return nil, "bad request" end
        local kind = E.useKind(game, id)
        if not kind then return nil, "cant use" end
        if kind == "scene" then
            -- mid-step it waits for the step, like every edit
            local done, why = whenFree(game, function() return startScene(game, id, uid) end)
            if not done then return nil, why end
            return true, nil, { text = "Look at the game screen.", scene = true }
        end
        if kind == "move" then
            if type(moveSlot) ~= "number" or moveSlot ~= math.floor(moveSlot) or moveSlot < 1 or moveSlot > 4 then
                return nil, "bad request"
            end
        else
            moveSlot = nil
        end
        local reply = nil
        local ok, err = whenFree(game, function()
            local session = platform.save(game)
            local ItemUse = need("item_use")
            local bag = session and session.bag
            if not (ItemUse and ItemUse.useField and bag and type(bag.pockets) == "table") then
                return nil, "not loaded"
            end
            local slot = partySlotOf(session.party, uid)
            if not slot then return nil, "stale" end
            local mon = session.party[slot]
            local Pokemon = need("pokemon")
            if Pokemon and Pokemon.isEgg and Pokemon.isEgg(mon) then return nil, "egg use" end
            local before = bagTotals(bag)
            if (before[id] or 0) < 1 then return nil, "stale" end
            local bagCopy = saveBag(bag)
            local player = session.playerName or (session.player and session.player.name)

            local okU, used, _, text = pcall(ItemUse.useField, session, bag, tonumber(id) or id, slot, moveSlot)
            if not okU then
                restoreBag(bag, bagCopy)
                mod.log:warn("use failed: %s", tostring(used))
                return nil, "stale"
            end
            if not used then return nil, gameText(text, player) or "no effect" end

            -- exactly one of the item gone, nothing else in the bag changed
            local after = bagTotals(bag)
            local sane = (after[id] or 0) == before[id] - 1
            for k, v in pairs(before) do
                if k ~= id and (after[k] or 0) ~= v then sane = false end
            end
            for k, v in pairs(after) do
                if k ~= id and (before[k] or 0) ~= v then sane = false end
            end
            if not sane then
                restoreBag(bag, bagCopy)
                mod.log:warn("use: the bag did not come out as expected; put back")
            end
            reply = { text = gameText(text, player) }
            return true
        end)
        if not ok then return nil, err end
        return true, nil, reply
    end

    return E
end
