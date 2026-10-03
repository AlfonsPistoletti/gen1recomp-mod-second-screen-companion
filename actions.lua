-- Game actions the phone can trigger: the BICYCLE, the fishing rods and the
-- party's field moves. Every action runs through the engine's companion shortcuts
-- (WorldAPI:useFieldAction / flyTo), so rules, text boxes, animations and
-- music are exactly the in-game ones. The previews below only explain why a
-- button is greyed out; the engine checks everything again when it runs.
--
-- Gen 1 only: Gold / Silver load actions2.lua instead, so the Gen 1 world
-- modules below are named once and required only here.
local GEN1_MAP, GEN1_FIELD_DEFAULTS = "src.world.Map", "src.world.FieldDefaults"
return function(mod, platform)
    local Map = require(GEN1_MAP)
    local FieldDefaults = require(GEN1_FIELD_DEFAULTS)

    local WAIT_SECONDS = 2 -- how long a tap made mid-step may wait

    -- Gen 1 party-menu order
    local FIELD_MOVES = {
        { id = "cut", move = "CUT" },
        { id = "fly", move = "FLY" },
        { id = "surf", move = "SURF" },
        { id = "strength", move = "STRENGTH" },
        { id = "flash", move = "FLASH" },
        { id = "dig", move = "DIG", confirm = true },
        { id = "teleport", move = "TELEPORT", confirm = true },
        { id = "softboiled", move = "SOFTBOILED" },
    }
    -- WorldAPI's DIG_TILESETS: where DIG leads out of the dungeon
    local DIG_TILESETS = { FOREST = true, CEMETERY = true, CAVERN = true, FACILITY = true, INTERIOR = true }
    local SURF_REASONS = {
        no_water = "Face the water",
        forced_bike = "Not on CYCLING ROAD",
        current = "The current is too strong",
        no_place = "No place to land",
    }

    local A = {}
    local pending -- { run = fn, expires = time }

    local function world()
        local w = mod.world
        return w and w.useFieldAction and w or nil
    end

    -- The overworld is on screen with nothing above it. A request made then
    -- only has to wait for the current step to end.
    local function onlyWorld(game)
        local stack = game and game.stack
        return game and game.overworld and stack and stack.top and stack:top() == game.overworld
    end

    local function monName(game, mon)
        if type(mon) ~= "table" then return false end
        local def = game.data.pokemon[mon.species] or {}
        return mon.nickname or def.name or tostring(mon.species)
    end

    local function knows(mon, moveId)
        for _, move in ipairs(mon.moves or {}) do
            if move.id == moveId then return true end
        end
        return false
    end

    local function outside(game, ow)
        return Map.isOutside(ow.map.def, FieldDefaults.field(game.data, "outsideTilesets"))
    end

    local function partyInfo(game, mon, slot)
        return { slot = slot, name = monName(game, mon), hp = mon.hp or 0,
            maxHp = mon.stats and mon.stats.hp or mon.hp or 0 }
    end

    -- WorldAPI softboiledSources: a SOFTBOILED user with HP to spare, and
    -- conscious party members below full HP to heal
    local function softboiledSources(game)
        local party, sources = game.save.party or {}, {}
        for s, source in ipairs(party) do
            local heal = source.stats and math.floor(source.stats.hp / 5) or 0
            if knows(source, "SOFTBOILED") and (source.hp or 0) > heal then
                local info = partyInfo(game, source, s)
                info.targets = {}
                for t, target in ipairs(party) do
                    if target ~= source and (target.hp or 0) > 0 and target.stats
                        and target.hp < target.stats.hp then
                        info.targets[#info.targets + 1] = partyInfo(game, target, t)
                    end
                end
                if #info.targets > 0 then sources[#sources + 1] = info end
            end
        end
        return sources
    end

    -- TownMap buildFlyList: visited towns with a fly spot, in map order
    local function flyDestinations(game)
        local field, maps = game.data.field or {}, game.data.maps or {}
        local visited, warps = game.save.visited or {}, field.flyWarps or {}
        local locations = field.townMap and field.townMap.locations or {}
        local out, seen = {}, {}
        for _, mapId in ipairs(field.flyOrder or {}) do
            local def = maps[mapId]
            if not seen[mapId] and visited[mapId] and warps[mapId] and def and Map.isFlyTown(def) then
                seen[mapId] = true
                local loc = locations[mapId]
                out[#out + 1] = { mapId = mapId, name = loc and loc.name or (mapId:gsub("_", " ")) }
            end
        end
        return out
    end

    ---- BICYCLE -------------------------------------------------------------

    -- Preview of WorldAPI:availableFieldActions' bicycle rule
    -- what a tap on the BICYCLE answers when it can't run right here
    local BIKE_ERROR = { surf = "bike surf", forced = "bike forced", here = "bike here", busy = "bike busy" }
    -- The buttons are only greyed while the game has something open (a
    -- menu, text, a battle): whether it works right here is asked when it
    -- is tapped (full), and a "no" comes back as the reason.
    function A.bikeState(game, full)
        local save = game and game.save
        local inventory = save and save.inventory or {}
        if (inventory.BICYCLE or 0) <= 0 then return false end
        local ow = game.overworld
        local on = save.onBike and true or false
        local reason = false
        if not onlyWorld(game) then
            reason = "busy"
        elseif not full then
            reason = false
        elseif ow.player and ow.player.surfing then
            reason = "surf"
        elseif on and save.forcedBike then
            reason = "forced"
        elseif not on then
            local ok, allowed = pcall(ow.bikeAllowed, ow, ow.map and ow.map.id)
            if not (ok and allowed) then reason = "here" end
        end
        -- the item's name, as the BAG shows it (a language mod's too)
        local def = game.data.items and game.data.items.BICYCLE
        local label = type(def) == "table" and def.name or "BICYCLE"
        return { on = on, label = label, available = not reason, reason = reason, pending = pending ~= nil }
    end

    ---- fishing rods -------------------------------------------------------

    local RODS = { "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }

    -- Every rod in the BAG, with WorldAPI's fish rule as the reason:
    -- facing water (or shore), not while surfing
    function A.rods(game, full)
        local save, ow = game and game.save, game and game.overworld
        if not (save and ow and ow.map and ow.player) then return {} end
        local inventory, items = save.inventory or {}, game.data.items or {}
        local free = onlyWorld(game)
        local reason = false
        if not full then
            reason = false
        elseif ow.player.surfing then
            reason = "Not while surfing"
        else
            local ok, water = pcall(ow.facingIsShoreOrWater, ow)
            if not (ok and water) then reason = "Face the water" end
        end
        local out = {}
        for _, id in ipairs(RODS) do
            if (inventory[id] or 0) > 0 then
                local def = items[id]
                out[#out + 1] = { id = id, label = def and def.name or (id:gsub("_", " ")),
                    available = free and not reason, reason = reason, pending = pending ~= nil }
            end
        end
        return out
    end

    ---- field moves --------------------------------------------------------

    -- why a move the party can use is not possible right here (false = ok),
    -- plus the button label when it differs from the move name
    local function fieldReason(game, ow, entry)
        local id = entry.id
        if id == "cut" then
            if ow:useCutFieldMove() ~= "ok" then return "Face a tree" end
        elseif id == "surf" then
            local mode = ow:useSurfFieldMove()
            if mode == "dismount" then return false, platform.text("LEAVE WATER") end
            if mode ~= "ok" then return SURF_REASONS[mode] or "Not here" end
        elseif id == "strength" then
            if ow.strengthActive then return "Already active" end
        elseif id == "flash" then
            if not ow.dark then return "It isn't dark here" end
        elseif id == "dig" then
            if not DIG_TILESETS[ow.map.def.tileset] or ow.map.id == "AGATHAS_ROOM" then
                return "Only in caves and buildings"
            end
        elseif id == "teleport" or id == "fly" then
            if not outside(game, ow) then return "Only outdoors" end
        end
        return false
    end

    -- Every field move the party can use with the badges it has
    -- (OverworldState:partyKnows applies the HM badge gates and any mod's
    -- fieldmove.eligibility hook). SOFTBOILED needs no badge.
    function A.fieldMoves(game, full)
        local ow = game and game.overworld
        if not (game.save and ow and ow.map and ow.player) then return {} end
        local free = onlyWorld(game)
        local out = {}
        for _, entry in ipairs(FIELD_MOVES) do
            local user
            if entry.id == "softboiled" then
                for _, mon in ipairs(game.save.party or {}) do
                    if knows(mon, "SOFTBOILED") then user = mon break end
                end
            else
                local ok, mon = pcall(ow.partyKnows, ow, entry.move)
                user = ok and mon or nil
            end
            if user then
                -- the party menu's label: Strings("FLY") and the like
                local item = { id = entry.id, label = platform.text(entry.move), user = monName(game, user),
                    confirm = entry.confirm or false, available = false, reason = false }
                local reason, label = false, nil
                if full then
                    local ok
                    ok, reason, label = pcall(fieldReason, game, ow, entry)
                    if not ok then reason = "Not here" end
                elseif entry.id == "surf" and ow.player.surfing then
                    -- on the water SURF is the way back to land
                    label = platform.text("LEAVE WATER")
                end
                if label then item.label = label end
                if entry.id == "fly" then
                    item.destinations = flyDestinations(game)
                    if full and not reason and #item.destinations == 0 then reason = "No towns visited" end
                elseif entry.id == "softboiled" then
                    item.sources = softboiledSources(game)
                    if full and not reason and #item.sources == 0 then reason = "No one to heal" end
                end
                item.reason = reason or false
                item.available = free and not reason
                out[#out + 1] = item
            end
        end
        return out
    end

    ---- requests -----------------------------------------------------------

    -- Run now, or -- when the player is only mid-step -- as soon as the step
    -- ends. run() returns what the WorldAPI call returns.
    local function runOrQueue(game, run)
        local done, err = run()
        if done then
            pending = nil
            return true
        end
        if err == "world is busy" and onlyWorld(game) then
            pending = { run = run, expires = love.timer.getTime() + WAIT_SECONDS }
            return true
        end
        return nil, err
    end

    -- POST /api/bike { on = true|false }: the state the player asked for, so
    -- a double tap cannot flip it back.
    function A.requestBike(game, wantOn)
        if type(wantOn) ~= "boolean" then return nil, "bad request" end
        local state = A.bikeState(game, true)
        if not state then return nil, "no bike" end
        if not state.available then return nil, BIKE_ERROR[state.reason] or "bike here" end
        local w = world()
        if not w then return nil, "unavailable" end
        local done = runOrQueue(game, function()
            if (game.save.onBike and true or false) == wantOn then return true end
            return w:useFieldAction("bicycle")
        end)
        if done then return true end
        return nil, "bike here"
    end

    -- POST /api/fish { rod = "OLD_ROD" | "GOOD_ROD" | "SUPER_ROD" }
    function A.requestFish(game, rodId)
        local found
        for _, rod in ipairs(A.rods(game, true)) do
            if rod.id == rodId then found = rod break end
        end
        if not found then return nil, "no rod" end
        if not onlyWorld(game) then return nil, "rod busy" end
        if found.reason then return nil, found.reason end
        local w = world()
        if not w then return nil, "unavailable" end
        local done = runOrQueue(game, function()
            return w:useFieldAction("fish", { rod = rodId })
        end)
        if done then return true end
        return nil, "rod unavailable"
    end

    -- POST /api/field { id, dest?, source?, target? }
    function A.requestField(game, body)
        local w = world()
        if not w then return nil, "unavailable" end
        local id = body.id
        local found
        for _, item in ipairs(A.fieldMoves(game, true)) do
            if item.id == id then found = item break end
        end
        if not found then return nil, "field unknown" end
        if not onlyWorld(game) then return nil, "field busy" end
        if found.reason then return nil, found.reason end
        local run
        if id == "fly" then
            if type(body.dest) ~= "string" then return nil, "bad request" end
            run = function() return w:flyTo(body.dest) end
        elseif id == "softboiled" then
            local source, target = tonumber(body.source), tonumber(body.target)
            if not (source and target) then return nil, "bad request" end
            run = function()
                return w:useFieldAction("softboiled", { sourceSlot = source, targetSlot = target })
            end
        else
            run = function() return w:useFieldAction(id) end
        end
        local done, err = runOrQueue(game, run)
        if done then return true end
        if err == "destination unavailable" then return nil, "fly dest" end
        if err == "softboiled target unavailable" then return nil, "soft target" end
        return nil, "field unavailable"
    end

    ---- field items from the BAG (the items tab's USE) --------------------
    -- One way in for every item the BAG can use in the field: the BICYCLE
    -- and the rods through the quick actions above (WorldAPI field actions,
    -- the same code the BAG runs), everything else through the BAG's own
    -- ItemEffects.use and what BagMenu does with its result (vanillaUseOn).
    -- The quick action buttons are shortcuts onto the same calls.
    local FIELD_ITEMS = {
        REPEL = true, SUPER_REPEL = true, MAX_REPEL = true, ESCAPE_ROPE = true,
        ITEMFINDER = true, TOWN_MAP = true, COIN_CASE = true, BICYCLE = true,
        OLD_ROD = true, GOOD_ROD = true, SUPER_ROD = true,
    }
    -- BagMenu's ESCAPE ROPE tilesets (escape_rope_tilesets.asm)
    local ESCAPE_TILESETS = { FOREST = true, CEMETERY = true, CAVERN = true, FACILITY = true, INTERIOR = true }

    function A.fieldKind(_, id)
        return FIELD_ITEMS[id] and "field" or nil
    end

    -- true plus { text, scene }, or nil plus the reason (a key of main.lua's
    -- ERRORS, or the game's own words)
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
        if not onlyWorld(game) then return nil, "field busy" end
        local Bag = require("src.inventory.Bag")
        local Strings = require("src.core.Strings")
        local ItemEffects = require("src.inventory.ItemEffects")
        local data, ow = game.data, game.overworld
        local ok, result, payload, extra = pcall(ItemEffects.use, data, save, id, nil, nil, nil, ow)
        if not ok then
            mod.log:warn("field item failed: %s", tostring(result))
            return nil, "field unavailable"
        end
        if result == "consumed" then
            -- a REPEL: PrintItemUseTextAndRemoveItem's jingle, the item gone
            Bag.remove(save, id, 1)
            if extra and extra.useJingle then pcall(function() require("src.core.Sound").play(data, "Heal_Ailment") end) end
            return true, nil, { text = payload }
        end
        if result == "escape_rope" then
            if not (ow and ow.map and ESCAPE_TILESETS[ow.map.def.tileset] and ow.map.id ~= "AGATHAS_ROOM") then
                return nil, Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name)
            end
            Bag.remove(save, id, 1)
            ow:beginTeleportOut()
            return true, nil, { scene = true }
        end
        if result == "itemfinder" then
            local t = data.text or {}
            local found = ow and ow.hasHiddenItemLeft and ow:hasHiddenItemLeft()
            return true, nil, { text = found
                and (t._ItemfinderFoundItemText or Strings("Yes! ITEMFINDER\nindicates there's\nan item nearby."))
                or (t._ItemfinderFoundNothingText or Strings("Nope! ITEMFINDER\nisn't responding.")) }
        end
        if result == "townmap" then
            local okT = pcall(function() require("src.ui.Screens").push(game, "TownMap") end)
            if not okT then return nil, Strings("The TOWN MAP is\nunreadable here.") end
            return true, nil, { scene = true }
        end
        -- the COIN CASE answers with the coins (as a "failed" use)
        if id == "COIN_CASE" then return true, nil, { text = payload } end
        if result == "kept" then return true, nil, { text = payload } end
        return nil, payload or "field unavailable"
    end

    -- every frame, before the game updates
    function A.tick(game)
        if not pending then return end
        if love.timer.getTime() > pending.expires or not onlyWorld(game) then
            pending = nil
            return
        end
        if pending.run() then pending = nil end
    end

    return A
end
