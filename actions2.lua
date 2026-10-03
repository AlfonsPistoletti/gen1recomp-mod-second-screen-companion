-- Game actions the phone can trigger on Gen 2 (Gold / Silver): the same
-- interface as actions.lua, run through Gold's WorldAPI (useFieldAction),
-- so rules, text and animations are the game's own. The previews below
-- only explain why a button is greyed out: they ask the same FieldMoves
-- checks the party menu does (FieldMoves.fromMenu), and the engine checks
-- again when the action runs.
--
-- FLY has no WorldAPI entry on Gold, so it goes through the World the way
-- the party menu does: World:flyPoints (the visited flypoints of the
-- current region, the fly map's list) and World:flyTo (the real flight).
-- Not here: ROCK SMASH (no field-action id).
return function(mod, platform)
    local FieldMoves = require("src.world.gen2.FieldMoves")
    local Bike = require("src.world.gen2.Bike")

    local WAIT_SECONDS = 2 -- how long a tap made mid-step may wait

    -- Gold's party-menu order (pokecrystal engine/pokemon/mon_menu.asm)
    local FIELD_MOVES = {
        { id = "cut", move = "CUT" },
        { id = "fly", move = "FLY", fly = true },
        { id = "surf", move = "SURF" },
        { id = "strength", move = "STRENGTH" },
        { id = "flash", move = "FLASH" },
        { id = "whirlpool", move = "WHIRLPOOL" },
        { id = "waterfall", move = "WATERFALL" },
        { id = "headbutt", move = "HEADBUTT" },
        { id = "sweet_scent", move = "SWEET_SCENT", label = "SWEET SCENT" },
        { id = "dig", move = "DIG", confirm = true },
        { id = "teleport", move = "TELEPORT", confirm = true },
        { id = "softboiled", move = "SOFTBOILED", heal = true },
        { id = "milk_drink", move = "MILK_DRINK", label = "MILK DRINK", heal = true },
    }
    local RODS = { "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }

    -- why a known move fails right here, as a short line
    local function shortReason(moveId, res)
        local T = FieldMoves.TEXT or {}
        local text = res and res.text
        if text == T.CUT_NOTHING then return "Face a tree" end
        if text == T.CANT_SURF then return "Face the water" end
        if text == T.ALREADY_SURFING then return "Already surfing" end
        if text == T.NOT_ENOUGH_HP then return "Not enough HP" end
        if moveId == "FLASH" then return "It isn't dark here" end
        if moveId == "HEADBUTT" then return "Face a tree" end
        if moveId == "WHIRLPOOL" then return "Face a whirlpool" end
        if moveId == "WATERFALL" then return "Face a waterfall" end
        if moveId == "DIG" then return "Only in caves" end
        if moveId == "TELEPORT" or moveId == "FLY" then return "Only outdoors" end
        return "Not here"
    end

    local A = {}
    local pending -- { run = fn, expires = time }

    local function world()
        local w = mod.world
        return w and w.useFieldAction and w or nil
    end

    local function monName(game, mon)
        if type(mon) ~= "table" then return false end
        local def = game.data.pokemon[mon.species] or {}
        return mon.nickname or def.name or tostring(mon.species)
    end

    -- what WorldAPI offers right now, by id
    local function offered()
        local w = world()
        if not w then return {} end
        local ok, list = pcall(w.availableFieldActions, w)
        local byId = {}
        for _, action in ipairs(ok and list or {}) do byId[action.id] = action end
        return byId
    end

    local function context(game)
        local w = platform.world(game)
        if not (w and w.fieldContext) then return nil end
        local ok, ctx = pcall(w.fieldContext, w)
        return ok and ctx or nil
    end

    ---- BICYCLE --------------------------------------------------------------

    -- what a tap on the BICYCLE answers when it can't run right here
    local BIKE_ERROR = { surf = "bike surf", forced = "bike forced", here = "bike here", busy = "bike busy" }
    -- The buttons are only greyed while the game has something open (a
    -- menu, text, a battle): whether it works right here is asked when it
    -- is tapped (full), and a "no" comes back as the reason.
    function A.bikeState(game, full)
        local save = game and game.save
        if not (save and (save.inventory or {}).BICYCLE and (save.inventory.BICYCLE or 0) > 0) then return false end
        local w = platform.world(game)
        if not w then return false end
        local on = FieldMoves.isBiking(w.playerState) and true or false
        local reason = false
        if not platform.worldFree(game) then
            reason = "busy"
        elseif not full then
            reason = false
        elseif FieldMoves.isSurfing(w.playerState) then
            reason = "surf"
        elseif not offered().bicycle then
            local forced = w.alwaysOnBike and select(2, pcall(w.alwaysOnBike, w))
            reason = (on and forced) and "forced" or "here"
        end
        -- the item's name, as the BAG shows it (a language mod's too)
        local def = game.data.items and game.data.items.BICYCLE
        local label = type(def) == "table" and def.name or "BICYCLE"
        return { on = on, label = label, available = not reason, reason = reason, pending = pending ~= nil }
    end

    ---- rods and field items (SQUIRTBOTTLE) ----------------------------------

    function A.rods(game, full)
        local save = game and game.save
        local w = platform.world(game)
        if not (save and w) then return {} end
        local inventory, items = save.inventory or {}, game.data.items or {}
        local free = platform.worldFree(game)
        local byId = (free and full) and offered() or {}
        local surfing = FieldMoves.isSurfing(w.playerState)
        local out = {}
        for _, id in ipairs(RODS) do
            if (inventory[id] or 0) > 0 then
                local def = items[id]
                local listed = false
                for _, rod in ipairs(byId.fish and byId.fish.rods or {}) do
                    if rod.id == id then listed = true end
                end
                local reason = false
                if full and free and not listed then reason = surfing and "Not while surfing" or "Face the water" end
                out[#out + 1] = { id = id, label = def and def.name or (id:gsub("_", " ")), action = "fish",
                    available = free and (listed or not full), reason = reason, pending = pending ~= nil }
            end
        end
        if (inventory.SQUIRTBOTTLE or 0) > 0 then
            local def = items.SQUIRTBOTTLE
            local listed = byId.squirtbottle ~= nil
            out[#out + 1] = { id = "SQUIRTBOTTLE", label = def and def.name or "SQUIRTBOTTLE", action = "item",
                available = free and (listed or not full), reason = (full and free and not listed) and "Not here" or false,
                pending = pending ~= nil }
        end
        return out
    end

    ---- field moves ------------------------------------------------------------

    function A.fieldMoves(game, full)
        local ctx = context(game)
        if not (game and game.save and ctx) then return {} end
        local free = platform.worldFree(game)
        -- WorldAPI's list: on a tap, or for the heals' sources
        local byIdCache = nil
        local function byIdNow()
            if not byIdCache then byIdCache = offered() end
            return byIdCache
        end
        local w = platform.world(game)
        local out = {}
        for _, entry in ipairs(FIELD_MOVES) do
            local ok, user = pcall(FieldMoves.partyMoveUser, ctx.party or game.save.party, entry.move, ctx)
            if ok and user then
                ctx.mon = user
                local okRes, res = pcall(FieldMoves.fromMenu, entry.move, ctx)
                res = okRes and res or { ok = false }
                -- no badge for it yet: hidden, like Gen 1's badge gate
                if not res.badge then
                    -- the party menu's label: the move's name (GetMoveName)
                    local mdef = game.data.moves and game.data.moves[entry.move]
                    local label = type(mdef) == "table" and mdef.name or entry.label or entry.move
                    local item = { id = entry.id, label = label, user = monName(game, user),
                        confirm = entry.confirm or false, heal = entry.heal or false,
                        available = false, reason = false }
                    local reason
                    if entry.fly then
                        item.destinations = {}
                        if w and w.flyPoints then
                            local okP, points = pcall(w.flyPoints, w)
                            for _, p in ipairs(okP and points or {}) do
                                item.destinations[#item.destinations + 1] = {
                                    mapId = p.spawn, name = (tostring(p.name or p.landmark):gsub("\n", " ")) }
                            end
                        end
                        if not full then
                            reason = nil
                        elseif not res.ok then
                            reason = shortReason(entry.move, res)
                        elseif #item.destinations == 0 then
                            reason = "No towns visited"
                        end
                    elseif entry.heal then
                        -- WorldAPI lists nothing while the world is busy, so
                        -- only a free world can say that nobody needs healing
                        local action = free and byIdNow()[entry.id] or nil
                        item.sources = action and action.sources or {}
                        if full and free and #item.sources == 0 then reason = "No one to heal" end
                    elseif not full then
                        reason = nil
                    elseif entry.move == "STRENGTH" and w and w.strengthActive then
                        reason = "Already active"
                    elseif not res.ok then
                        reason = shortReason(entry.move, res)
                    end
                    item.reason = reason or false
                    -- on a tap: is it offered right here (FLY: checked above,
                    -- no WorldAPI entry to ask)
                    local offeredHere = not full or entry.fly or entry.heal or byIdNow()[entry.id] ~= nil
                    item.available = free and not reason and offeredHere
                    if full and free and not reason and not offeredHere then item.reason = "Not here" end
                    out[#out + 1] = item
                end
            end
        end
        return out
    end

    ---- requests ---------------------------------------------------------------

    local function runOrQueue(game, run)
        local done, err = run()
        if done then
            pending = nil
            return true
        end
        if err == "world is busy" and platform.world(game) then
            pending = { run = run, expires = love.timer.getTime() + WAIT_SECONDS }
            return true
        end
        return nil, err
    end

    function A.requestBike(game, wantOn)
        if type(wantOn) ~= "boolean" then return nil, "bad request" end
        local state = A.bikeState(game, true)
        if not state then return nil, "no bike" end
        if not state.available then return nil, BIKE_ERROR[state.reason] or "bike here" end
        local w = world()
        if not w then return nil, "unavailable" end
        local done = runOrQueue(game, function()
            local wpl = platform.world(game)
            if wpl and (FieldMoves.isBiking(wpl.playerState) and true or false) == wantOn then return true end
            return w:useFieldAction("bicycle")
        end)
        if done then return true end
        return nil, "bike here"
    end

    function A.requestFish(game, rodId)
        local found
        for _, rod in ipairs(A.rods(game, true)) do
            if rod.id == rodId and rod.action == "fish" then found = rod break end
        end
        if not found then return nil, "no rod" end
        if not platform.worldFree(game) then return nil, "rod busy" end
        if not found.available then return nil, found.reason or "rod unavailable" end
        local w = world()
        if not w then return nil, "unavailable" end
        local done = runOrQueue(game, function() return w:useFieldAction("fish", { rod = rodId }) end)
        if done then return true end
        return nil, "rod unavailable"
    end

    -- POST /api/item { item = "SQUIRTBOTTLE" }
    function A.requestItem(game, itemId)
        if itemId ~= "SQUIRTBOTTLE" then return nil, "bad request" end
        local found
        for _, it in ipairs(A.rods(game, true)) do
            if it.id == itemId then found = it break end
        end
        if not found then return nil, "no item" end
        if not platform.worldFree(game) then return nil, "field busy" end
        if not found.available then return nil, found.reason or "field unavailable" end
        local w = world()
        if not w then return nil, "unavailable" end
        local done = runOrQueue(game, function() return w:useFieldAction("squirtbottle") end)
        if done then return true end
        return nil, "field unavailable"
    end

    function A.requestField(game, body)
        local w = world()
        if not w then return nil, "unavailable" end
        local id = body.id
        local found
        for _, item in ipairs(A.fieldMoves(game, true)) do
            if item.id == id then found = item break end
        end
        if not found then return nil, "field unknown" end
        if not platform.worldFree(game) then return nil, "field busy" end
        if found.reason then return nil, found.reason end
        local run
        if id == "fly" then
            -- only a visited flypoint of this region, as the fly map offers
            local dest
            for _, d in ipairs(found.destinations or {}) do
                if d.mapId == body.dest then dest = d.mapId end
            end
            if type(body.dest) ~= "string" then return nil, "bad request" end
            if not dest then return nil, "fly dest" end
            run = function()
                local wpl = platform.world(game)
                if not wpl then return nil, "no overworld" end
                -- the same guard WorldAPI's actions use (mid-step: wait)
                if not wpl:acceptsMenuInput() then return nil, "world is busy" end
                local ctx = context(game)
                local okU, user = pcall(FieldMoves.partyMoveUser, ctx and ctx.party or game.save.party, "FLY", ctx)
                if wpl:flyTo(dest, okU and user or nil) then return true end
                return nil, "fly dest"
            end
        elseif found.heal then
            local source, target = tonumber(body.source), tonumber(body.target)
            if not (source and target) then return nil, "bad request" end
            run = function() return w:useFieldAction(id, { sourceSlot = source, targetSlot = target }) end
        else
            run = function() return w:useFieldAction(id) end
        end
        local done, err = runOrQueue(game, run)
        if done then return true end
        if err == "softboiled target unavailable" then return nil, "soft target" end
        if err == "fly dest" then return nil, "fly dest" end
        return nil, "field unavailable"
    end

    ---- field items from the PACK (the items tab's USE) -------------------
    -- One way in for every item the PACK can use in the field: the BICYCLE,
    -- the rods and the SQUIRTBOTTLE through the quick actions above (the
    -- WorldAPI field actions), everything else through World:useFieldItem,
    -- the PACK's own field use (PackMenu:useSelected). The quick action
    -- buttons are shortcuts onto the same calls.
    local FIELD_ITEMS = {
        REPEL = true, SUPER_REPEL = true, MAX_REPEL = true, ESCAPE_ROPE = true,
        ITEMFINDER = true, COIN_CASE = true, BLUE_CARD = true, SACRED_ASH = true,
        BICYCLE = true, SQUIRTBOTTLE = true,
        OLD_ROD = true, GOOD_ROD = true, SUPER_ROD = true,
    }

    function A.fieldKind(_, id)
        return FIELD_ITEMS[id] and "field" or nil
    end

    function A.useItem(game, id)
        if not FIELD_ITEMS[id] then return nil, "cant use" end
        local save = game and game.save
        if not (save and (save.inventory or {})[id]) then return nil, "no item" end
        if id == "BICYCLE" then
            local state = A.bikeState(game)
            local done, err = A.requestBike(game, not (state and state.on))
            if not done then return nil, err end
            return true, nil, { scene = true }
        end
        if id == "OLD_ROD" or id == "GOOD_ROD" or id == "SUPER_ROD" then
            local done, err = A.requestFish(game, id)
            if not done then return nil, err end
            return true, nil, { scene = true }
        end
        if id == "SQUIRTBOTTLE" then
            local done, err = A.requestItem(game, id)
            if not done then return nil, err end
            return true, nil, { scene = true }
        end
        if not platform.worldFree(game) then return nil, "field busy" end
        local w = platform.world(game)
        if not (w and w.useFieldItem) then return nil, "unavailable" end
        local Strings = require("src.core.Strings")
        local ok, result, extra = pcall(w.useFieldItem, w, id)
        if not ok then
            mod.log:warn("field item failed: %s", tostring(result))
            return nil, "field unavailable"
        end
        local def = game.data.items and game.data.items[id]
        local name = def and def.name or (id:gsub("_", " "))
        -- PackMenu's lines for the answers it prints in the PACK
        if result == "repel_used" then return true, nil, { text = Strings("{PLAYER} used the\n%s.", name) } end
        if result == "repel_active" then
            return nil, Strings("The REPEL used\nearlier is still\nin effect.")
        end
        if result == "coin_case" then return true, nil, { text = Strings("Coins:\n%d", extra or 0) } end
        if result == "blue_card" then return true, nil, { text = Strings("You now have\n%d points.", extra or 0) } end
        if result == "nowhere" or result == nil then
            return nil, Strings("OAK: {PLAYER}!\nThis isn't the\ntime to use that!")
        end
        -- the rest (ESCAPE ROPE, ITEMFINDER, SACRED ASH) is queued in the
        -- world and plays as the PACK would leave it to the field
        return true, nil, { scene = true }
    end

    function A.tick(game)
        if not pending then return end
        if love.timer.getTime() > pending.expires or not platform.world(game) then
            pending = nil
            return
        end
        if pending.run() then pending = nil end
    end

    return A
end
