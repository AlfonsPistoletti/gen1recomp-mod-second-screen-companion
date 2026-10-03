-- Game actions the phone can trigger on Gen 3 (FireRed / LeafGreen): the
-- same interface as actions.lua / actions2.lua (the LIVE tab's QUICK
-- ACTIONS), run through the game's own code, so rules, text and animations
-- are the game's:
--
--   BICYCLE      mod.world:useFieldAction("bicycle") (ItemUse.useBike)
--   rods         ItemUse.useRod, the BAG's own rod use (item_use.c:286),
--                offered while ItemUse.canFish says the player faces water
--   field moves  mod.world:useFieldAction(id): CUT, FLASH, STRENGTH, SURF,
--                ROCK SMASH, WATERFALL, TELEPORT, DIG, SWEET SCENT and the
--                SOFTBOILED / MILK DRINK heal. Their previews ask the same
--                FieldMoves.fromMenu checks the party menu does; the engine
--                checks again when the action runs. A move without its
--                badge yet stays hidden, as on Gen 1 / 2.
--
--   FLY          the towns the game's fly map would offer (flyPoints: visited,
--                in the player's region), flown to with the game's own
--                Field.flyTo, as the fly map does after a town is picked
--                (WorldAPI:flyTo has no FireRed seam, so this goes to the
--                engine directly, like Gen 2's World:flyTo)
-- Everything runs only in free roam (edits3.freeRoam, the edits' gate); a
-- tap made mid-step waits for the step.
return function(mod, platform, edits)
    local function need(name)
        local ok, m = pcall(require, "src.core.game3." .. name)
        return ok and type(m) == "table" and m or nil
    end

    local FM = need("field_moves")
    local ItemsData = need("items_data")
    local Pokemon = need("pokemon")

    local WAIT_SECONDS = 2 -- how long a tap made mid-step may wait
    local ITEM_BICYCLE = 360 -- pokefirered/include/constants/items.h
    local RODS = { 262, 263, 264 } -- OLD ROD, GOOD ROD, SUPER ROD

    -- FireRed's party-menu order (pokefirered party_menu.c
    -- sFieldMoveCursorCallbacks), without DIVE / SECRET POWER (Emerald's)
    local FIELD_MOVES = {
        { id = "flash", move = "FLASH" },
        { id = "cut", move = "CUT" },
        { id = "fly", move = "FLY", fly = true },
        { id = "strength", move = "STRENGTH" },
        { id = "surf", move = "SURF" },
        { id = "rock_smash", move = "ROCK_SMASH" },
        { id = "waterfall", move = "WATERFALL" },
        { id = "teleport", move = "TELEPORT", confirm = true },
        { id = "dig", move = "DIG", confirm = true },
        { id = "milk_drink", move = "MILK_DRINK", heal = true },
        { id = "softboiled", move = "SOFTBOILED", heal = true },
        { id = "sweet_scent", move = "SWEET_SCENT" },
    }

    -- Emerald's party-menu order (pokeemerald party_menu.c, field_moves.lua
    -- FIELD_MOVE_ORDER), with DIVE and SECRET POWER. The world API runs
    -- neither, so those two go to the game directly (direct: the move's own
    -- FM.fromMenu result through Field.executeFieldMove, as the API does
    -- for the others)
    local FIELD_MOVES_RSE = {
        { id = "cut", move = "CUT" },
        { id = "flash", move = "FLASH" },
        { id = "rock_smash", move = "ROCK_SMASH" },
        { id = "strength", move = "STRENGTH" },
        { id = "surf", move = "SURF" },
        { id = "fly", move = "FLY", fly = true },
        { id = "dive", move = "DIVE", direct = true },
        { id = "waterfall", move = "WATERFALL" },
        { id = "teleport", move = "TELEPORT", confirm = true },
        { id = "dig", move = "DIG", confirm = true },
        { id = "secret_power", move = "SECRET_POWER", direct = true },
        { id = "milk_drink", move = "MILK_DRINK", heal = true },
        { id = "softboiled", move = "SOFTBOILED", heal = true },
        { id = "sweet_scent", move = "SWEET_SCENT" },
    }

    local A = {}
    local lastHeal = {} -- heal move id -> its sources when last free
    local pending -- { run = fn, expires = time }

    local function session(game) return platform.save(game) end

    local function free(game)
        if not (edits and edits.freeRoam) then return false, "busy" end
        return edits.freeRoam(game)
    end

    local function world()
        local w = mod.world
        return w and w.useFieldAction and w or nil
    end

    -- what WorldAPI offers right now, by id (empty unless the world is free)
    local function offered()
        local w = world()
        if not w then return {} end
        local ok, list = pcall(w.availableFieldActions, w)
        local byId = {}
        for _, action in ipairs(ok and type(list) == "table" and list or {}) do byId[action.id] = action end
        return byId
    end

    local function hasItem(game, id)
        local s = session(game)
        local Bag = need("bag")
        if not (s and s.bag and Bag and Bag.has) then return false end
        local ok, has = pcall(Bag.has, s.bag, id, 1)
        return ok and has or false
    end

    local function itemName(id, fallback)
        if not (ItemsData and ItemsData.displayName) then return fallback end
        local ok, n = pcall(ItemsData.displayName, id)
        return ok and n or fallback
    end

    ---- BICYCLE --------------------------------------------------------------

    -- Emerald's two bikes (pokeemerald items.h ITEM_MACH_BIKE / ACRO_BIKE),
    -- by the game's own constants; the player has one at a time
    local function rseBike(game)
        local s = session(game)
        local okC, Constants = pcall(require, "src.core.game3.constants")
        if not (s and okC) then return nil end
        local okA, C = pcall(Constants.active, s)
        if not okA or not C then return nil end
        for _, name in ipairs({ "ITEM_MACH_BIKE", "ITEM_ACRO_BIKE" }) do
            local okI, id = pcall(C.id, C, "items", name)
            if okI and id and hasItem(game, id) then return id end
        end
        return nil
    end

    -- Emerald: the BAG's own test (ItemUseOutOfBattle_Bike, item_use.c:200
    -- and :223): biking must be allowed on the map, not while surfing or on
    -- a spot the player can't run on; off the bike it's not on a rail
    local function rseBikeReason(game, on)
        local okB, BikeMod = pcall(require, "src.core.game3.bike")
        local BikeRse = okB and BikeMod.rse and select(2, pcall(BikeMod.rse, session(game))) or nil
        local okM, Map = pcall(require, "src.core.game3.map")
        local def = okM and Map.currentDef and select(2, pcall(Map.currentDef)) or nil
        -- the header keeps it as a number (1), the way item_use.lua
        -- map_header_flag reads it: anything but 0 allows the bike
        local allowed = type(def) == "table" and def.bikingAllowed
        if not (allowed == true or (tonumber(allowed) or 0) ~= 0) then return "here" end
        if type(BikeRse) == "table" then
            if on and BikeRse.onRail and select(2, pcall(BikeRse.onRail)) then return "here" end
            if not on and BikeRse.bikingDisallowedByPlayer and select(2, pcall(BikeRse.bikingDisallowedByPlayer)) then
                return "here"
            end
        end
        return false
    end

    -- what a tap on the BICYCLE answers when it can't run right here
    local BIKE_ERROR = { surf = "bike surf", forced = "bike forced", here = "bike here", busy = "bike busy" }
    -- The buttons are only greyed while the game has something open (a
    -- menu, text, a battle): whether it works right here is asked when it
    -- is tapped (full), and a "no" comes back as the reason.
    function A.bikeState(game, full)
        if platform.isRse(game) then
            local bike = rseBike(game)
            if not bike then return false end
            local P = need("player")
            local on = P and P.biking == true or false
            local okFree, why = free(game)
            local reason = false
            if not okFree and why ~= "walking" then
                reason = "busy"
            elseif not full then
                reason = false
            elseif P and P.surfing then
                reason = "surf"
            elseif okFree then
                reason = rseBikeReason(game, on)
            end
            return { on = on, label = itemName(bike, "BIKE"), available = not reason,
                reason = reason, pending = pending ~= nil }
        end
        if not hasItem(game, ITEM_BICYCLE) then return false end
        local P = need("player")
        local on = P and P.biking == true or false
        local okFree, why = free(game)
        local reason = false
        if not okFree and why ~= "walking" then
            reason = "busy"
        elseif not full then
            reason = false
        elseif P and P.surfing then
            reason = "surf"
        elseif okFree and not offered().bicycle then
            reason = "here"
        end
        return { on = on, label = itemName(ITEM_BICYCLE, "BICYCLE"), available = not reason,
            reason = reason, pending = pending ~= nil }
    end

    ---- rods -------------------------------------------------------------------

    local function canFish()
        local IU = need("item_use")
        if not (IU and IU.canFish) then return false end
        local ok, can = pcall(IU.canFish)
        return ok and can or false
    end

    function A.rods(game, full)
        local out = {}
        local okFree, why = free(game)
        -- mid-step counts: the cast waits for the step (runOrQueue)
        local usable = okFree or why == "walking"
        local P = need("player")
        for _, id in ipairs(RODS) do
            if hasItem(game, id) then
                local reason = false
                local available = false
                if usable and full then
                    available = canFish()
                    if not available then reason = "Face the water" end
                elseif usable then
                    available = true
                end
                out[#out + 1] = { id = tostring(id), label = itemName(id, "ROD"), action = "fish",
                    available = available, reason = reason, pending = pending ~= nil }
            end
        end
        return out
    end

    ---- field moves ------------------------------------------------------------

    local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

    -- a call's result, or nil when it fails
    local function try(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        if ok then return v end
        return nil
    end

    -- the party menu's view of the spot in front of the player
    -- (WorldAPI fieldContext, src/world/game3/WorldAPI.lua)
    local function fieldContext(game, mon)
        local P, C, Objects, M, S = need("player"), need("collision"), need("objects"), need("map"),
            need("scripting.space")
        local s = session(game)
        if not (P and s) then return nil end
        local d = DELTA[P.facing or "down"] or DELTA.down
        local fx, fy = (P.cellX or 0) + d[1], (P.cellY or 0) + d[2]
        local mapDef = M and try(M.currentDef)
        return {
            party = s.party, mon = mon, store = S and S.store, session = s,
            facingObject = Objects and try(Objects.at, fx, fy) or nil,
            isFacingWater = C and try(C.isWater, fx, fy),
            isSurfing = P.surfing == true,
            hasCuttableGrass = C and (try(C.isGrass, fx, fy) or try(C.isGrass, P.cellX, P.cellY)),
            -- FireRed's map defs call it mapType (src/core/game3/dataset.lua)
            mapType = type(mapDef) == "table" and (mapDef.mapType or mapDef.type) or nil,
        }
    end

    -- why a known move can't be used right here, as a short line
    local function shortReason(move, P)
        if move == "CUT" then return "Face a tree" end
        if move == "SURF" then return P and P.surfing and "Already surfing" or "Face the water" end
        if move == "STRENGTH" then return "Face a boulder" end
        if move == "FLASH" then return "It isn't dark here" end
        if move == "ROCK_SMASH" then return "Face a rock" end
        if move == "WATERFALL" then return "Face a waterfall" end
        if move == "DIVE" then return "Only in deep water" end
        if move == "SECRET_POWER" then return "Face a tree, bush or cave" end
        if move == "DIG" then return "Only in caves" end
        if move == "TELEPORT" then return "Only outdoors" end
        return "Not here"
    end

    -- FLY's destinations, as the game's fly map offers them: every section
    -- with a fly landing spot (Field.flyDestination, the baked
    -- fly_destinations table) that the player has visited (the fly map's own
    -- RegionMap.mapsecType, its FLAG_WORLD_MAP_* flags) and that lies in the
    -- region the player is in (the fly map shows that one region only:
    -- Kanto, or the Sevii Islands group). Each { mapId = section, name }.
    local ROUTE4_CENTER_FLAG = "FLAG_WORLD_MAP_ROUTE4_POKEMON_CENTER_1F"

    -- Emerald's fly map (pokeemerald region_map.c, src/ui/game3/rse/
    -- region_map.lua): the towns and cities LITTLEROOT .. EVER GRANDE the
    -- player has visited (RegionMap.mapSecType CITY_CANFLY: the
    -- FLAG_VISITED_* flags), and the BATTLE FRONTIER once its landmark flag
    -- is set. Hoenn is one map, so there is no region to match.
    local function flyPointsRse(game)
        local s = session(game)
        local Field = need("field")
        local okR, RegionMap = pcall(require, "src.ui.game3.rse.region_map")
        local okM, Mapsec = pcall(require, "src.ui.game3.rse.mapsec")
        if not (s and Field and okR and okM and RegionMap.mapSecType) then return {} end
        local TYPE = RegionMap.TYPE or {}
        local ctx = { session = s }
        local first, last = try(RegionMap.mapsec, "LITTLEROOT_TOWN"), try(RegionMap.mapsec, "EVER_GRANDE_CITY")
        local frontier = try(RegionMap.mapsec, "BATTLE_FRONTIER")
        if not (first and last) then return {} end
        local ids = {}
        for id = first, last do ids[#ids + 1] = id end
        if frontier then ids[#ids + 1] = frontier end
        local out = {}
        for _, id in ipairs(ids) do
            local kind = try(RegionMap.mapSecType, ctx, id)
            local canFly = kind == (TYPE.CITY_CANFLY or 2) or (id == frontier and kind == (TYPE.BATTLE_FRONTIER or 4))
            if canFly and try(Field.flyDestination, id) then
                local name = try(Mapsec.name, id)
                out[#out + 1] = { mapId = tostring(id), name = type(name) == "string" and name ~= "" and name or tostring(id) }
            end
        end
        return out
    end

    local function flyPoints(game)
        if platform.isRse(game) then return flyPointsRse(game) end
        local s = session(game)
        local Field = need("field")
        local okR, RegionMap = pcall(require, "src.ui.game3.region_map")
        local okS, Sections = pcall(require, "src.import.gba.map_sections_extract")
        local okE, RegionExtract = pcall(require, "src.import.gba.region_map_extract")
        local okP, Position = pcall(require, "src.ui.game3.region_map_position")
        if not (s and Field and Field.flyDestination and okR and okS and okE and okP) then return {} end
        if Field.flyDestinationsMounted and not try(Field.flyDestinationsMounted) then return {} end
        if RegionExtract.ensureGenerated then try(RegionExtract.ensureGenerated) end
        local layouts = RegionExtract.LAYOUTS
        local here = Pokemon and try(Pokemon.currentMapSec, s)
        local hereRegion = here and try(Position.regionFor, tonumber(here), layouts)
        local VISITED = RegionMap.MAPSECTYPE and RegionMap.MAPSECTYPE.VISITED or 2
        local out = {}
        for num, info in pairs(Sections.SECTIONS or {}) do
            local dest = try(Field.flyDestination, num)
            if dest then
                local visited
                if info.id == "MAPSEC_ROUTE_4_POKECENTER" then
                    -- the fly map's own rule for it (region_map.lua:289)
                    visited = try(RegionMap.isFlagSet, ROUTE4_CENTER_FLAG)
                else
                    visited = try(RegionMap.mapsecType, num) == VISITED
                end
                local region = try(Position.regionFor, num, layouts)
                if visited and (hereRegion == nil or region == hereRegion) then
                    local name = Sections.getPlaceName and try(Sections.getPlaceName, dest.map, num)
                    out[#out + 1] = { mapId = tostring(num), name = type(name) == "string" and name ~= "" and name
                        or (tostring(info.id):gsub("^MAPSEC_", ""):gsub("_", " ")), order = num }
                end
            end
        end
        table.sort(out, function(a, b) return a.order < b.order end)
        for _, p in ipairs(out) do p.order = nil end
        return out
    end

    local function moveLabel(move)
        local num = FM and FM.MOVES and FM.MOVES[move]
        if num and Pokemon and Pokemon.moveName then
            local ok, n = pcall(Pokemon.moveName, num)
            if ok and n then return n end
        end
        return (move:gsub("_", " "))
    end

    function A.fieldMoves(game, full)
        local s = session(game)
        if not (s and FM and FM.partyMoveUser) then return {} end
        local okFree, why = free(game)
        -- mid-step counts: the move waits for the step (runOrQueue)
        local usable = okFree or why == "walking"
        -- the world API's list: only for the heals' sources now
        local byId = okFree and offered() or {}
        local P = need("player")
        local out = {}
        for _, entry in ipairs(platform.isRse(game) and FIELD_MOVES_RSE or FIELD_MOVES) do
            local okU, user = pcall(FM.partyMoveUser, s.party, entry.move)
            if okU and user then
                local res = { ok = false }
                local ctx = fieldContext(game, user)
                if ctx and FM.fromMenu then
                    local okR, r = pcall(FM.fromMenu, entry.move, ctx)
                    if okR and type(r) == "table" then res = r end
                end
                -- no badge for it yet: hidden, like Gen 1 / 2's badge gate
                if not res.badge then
                    local name = Pokemon and try(Pokemon.displayName, user)
                    local item = { id = entry.id, label = moveLabel(entry.move),
                        user = type(name) == "string" and name or false,
                        confirm = entry.confirm or false, heal = entry.heal or false,
                        available = false, reason = false }
                    local reason
                    if entry.fly then
                        -- the towns the fly map would offer; the flight is
                        -- the game's own (Field.flyTo, requestField)
                        item.destinations = flyPoints(game)
                        if not full then
                            reason = nil
                        elseif not res.ok then
                            reason = "Only outdoors"
                        elseif #item.destinations == 0 then
                            reason = "No towns visited"
                        end
                    elseif entry.heal then
                        -- WorldAPI lists heals only while the world is free
                        -- mid-step it has no answer: the last one stands,
                        -- so the button does not flicker with every step
                        local action = byId[entry.id]
                        if okFree then lastHeal[entry.id] = action and action.sources or {} end
                        item.sources = lastHeal[entry.id] or {}
                        if full and okFree and #item.sources == 0 then reason = "No one to heal" end
                    else
                        -- the game's own test, right here (FM.fromMenu with
                        -- the map's real type), on a tap
                        if full and usable and not res.ok then reason = shortReason(entry.move, P) end
                    end
                    item.reason = reason or false
                    -- on a tap: heals need the world API's sources; FLY its
                    -- own checks; the rest FM.fromMenu's answer
                    local offeredHere = true
                    if not full then offeredHere = true
                    elseif entry.heal then offeredHere = #item.sources > 0
                    elseif entry.fly then offeredHere = true
                    else offeredHere = res.ok and true or false end
                    item.available = usable and not reason and offeredHere or false
                    -- run through the game's own field move (requestField)
                    if not entry.heal and not entry.fly then item.direct = entry.move end
                    out[#out + 1] = item
                end
            end
        end
        return out
    end

    ---- requests ---------------------------------------------------------------

    -- run it now, or (mid-step) let it wait a moment for the step to end
    local function runOrQueue(game, run)
        local okFree, why = free(game)
        if not okFree and why == "walking" then
            pending = { run = run, expires = love.timer.getTime() + WAIT_SECONDS }
            return true
        end
        if not okFree then return nil, "busy" end
        local done, err = run()
        if done then
            pending = nil
            return true
        end
        if err == "world is busy" then
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
        -- Emerald: the BAG's own use of the bike the player has (the world
        -- API's "bicycle" knows FireRed's BICYCLE only), and its message
        -- when it can't (as useFieldAction shows it)
        local rse = platform.isRse(game) and rseBike(game)
        local done = runOrQueue(game, function()
            local P = need("player")
            if P and (P.biking == true) == wantOn then return true end
            if rse then
                local IU = need("item_use")
                if not (IU and IU.useBike) then return nil end
                local okU, ok, _, text = pcall(IU.useBike, session(game), rse)
                local okMsg, Message = pcall(require, "src.ui.game3.message")
                if not okMsg then Message = nil end
                if okU and text and Message then Message.show(text, function() Message.close() end) end
                return okU and ok and true or nil
            end
            return w:useFieldAction("bicycle")
        end)
        if done then return true end
        return nil, "bike here"
    end

    function A.requestFish(game, rodId)
        local found
        for _, rod in ipairs(A.rods(game, true)) do
            if rod.id == tostring(rodId) then found = rod break end
        end
        if not found then return nil, "no rod" end
        local okFree = free(game)
        if not okFree then return nil, "rod busy" end
        if not found.available then return nil, found.reason or "rod unavailable" end
        local done = runOrQueue(game, function()
            local IU = need("item_use")
            local s = session(game)
            if not (IU and IU.useRod and s) then return nil, "rod unavailable" end
            local ok, used = pcall(IU.useRod, s, tonumber(rodId))
            if ok and used then return true end
            return nil, "rod unavailable"
        end)
        if done then return true end
        return nil, "rod unavailable"
    end

    -- Gen 2's SQUIRTBOTTLE has no FireRed counterpart
    function A.requestItem() return nil, "bad request" end

    function A.requestField(game, body)
        local w = world()
        if not w then return nil, "unavailable" end
        local id = body.id
        local found
        for _, item in ipairs(A.fieldMoves(game, true)) do
            if item.id == id then found = item break end
        end
        if not found then return nil, "field unknown" end
        local okFree, why = free(game)
        if not okFree and why ~= "walking" then return nil, "field busy" end
        if found.reason then return nil, found.reason end
        if not found.available then return nil, "field unavailable" end
        local run
        if id == "fly" then
            -- only a town the fly map would offer right now
            if type(body.dest) ~= "string" then return nil, "bad request" end
            local dest
            for _, d in ipairs(found.destinations or {}) do
                if d.mapId == body.dest then dest = tonumber(d.mapId) end
            end
            if not dest then return nil, "fly dest" end
            run = function()
                -- the game's own flight (pokefirered field_effect.c:1065
                -- ReturnToFieldFromFlyMapSelect: take-off with the POKéMON,
                -- the fade, the landing, the quest log entry)
                local Field = need("field")
                local s = session(game)
                if not (Field and Field.flyTo and s) then return nil, "fly dest" end
                local user = FM and try(FM.partyMoveUser, s.party, "FLY")
                if not user then return nil, "fly dest" end
                -- Emerald: the landing the fly map picks for its special
                -- cases (LITTLEROOT's own house, EVER GRANDE's POKéMON
                -- LEAGUE, the BATTLE FRONTIER; Field.lua's rse fly branch)
                local info = nil
                if platform.isRse(game) then
                    local okR, RegionMap = pcall(require, "src.ui.game3.rse.region_map")
                    local special = okR and RegionMap.flyWarpDestination
                        and try(RegionMap.flyWarpDestination, s, dest, 0)
                    if special then info = { dest = special } end
                end
                local ok, err = pcall(Field.flyTo, dest, user, info)
                if not ok then
                    mod.log:warn("fly failed: %s", tostring(err))
                    return nil, "fly dest"
                end
                return true
            end
        elseif found.heal then
            local source, target = tonumber(body.source), tonumber(body.target)
            if not (source and target) then return nil, "bad request" end
            run = function() return w:useFieldAction(id, { sourceSlot = source, targetSlot = target }) end
        elseif found.direct then
            -- the field moves (CUT .. SWEET SCENT, Emerald's DIVE and
            -- SECRET POWER): asked again at the moment it runs, then the
            -- game's own field move (Field.executeFieldMove, as the world
            -- API runs its own)
            run = function()
                local Field = need("field")
                local s = session(game)
                local user = s and FM and try(FM.partyMoveUser, s.party, found.direct)
                local ctx = user and fieldContext(game, user)
                local res = ctx and try(FM.fromMenu, found.direct, ctx)
                if not (Field and Field.executeFieldMove and type(res) == "table" and res.ok) then return nil end
                local ok, err = pcall(Field.executeFieldMove, res)
                if not ok then mod.log:warn("%s failed: %s", found.direct, tostring(err)) return nil end
                return true
            end
        else
            run = function() return w:useFieldAction(id) end
        end
        local done, err = runOrQueue(game, run)
        if done then return true end
        if err == "softboiled target unavailable" then return nil, "soft target" end
        if err == "fly dest" then return nil, "fly dest" end
        return nil, "field unavailable"
    end

    ---- field items from the BAG (the items tab's USE) --------------------
    -- One way in for every item the BAG can use in the field: the BICYCLE
    -- and the rods through the quick actions above (item_use.lua's useBike /
    -- useRod, as the BAG calls them), everything else through
    -- ItemUse.useField, the BAG's own field use (the REPEL, the ESCAPE ROPE's
    -- message and warp, the ITEMFINDER, the TOWN MAP, the COIN CASE). The
    -- quick action buttons are shortcuts onto the same calls.
    local FIELD_KINDS = {
        repel = "text", coin_case = "text", powder_jar = "text",
        escape = "scene", itemfinder = "scene", map = "scene",
        bike = "bike", rod = "rod",
    }
    local function fieldKindOf(id)
        if not (ItemsData and ItemsData.fieldUseKind) then return nil end
        local ok, kind = pcall(ItemsData.fieldUseKind, tonumber(id) or id)
        return ok and FIELD_KINDS[kind] or nil
    end

    function A.fieldKind(_, id)
        return fieldKindOf(id) and "field" or nil
    end

    function A.useItem(game, id)
        local how = fieldKindOf(id)
        if not how then return nil, "cant use" end
        local itemId = tonumber(id) or id
        if not hasItem(game, itemId) then return nil, "no item" end
        if how == "bike" then
            local state = A.bikeState(game)
            local done, err = A.requestBike(game, not (state and state.on))
            if not done then return nil, err end
            return true, nil, { scene = true }
        end
        if how == "rod" then
            local done, err = A.requestFish(game, itemId)
            if not done then return nil, err end
            return true, nil, { scene = true }
        end
        local IU = need("item_use")
        if not (IU and IU.useField) then return nil, "unavailable" end
        local reply = nil
        local done, err = runOrQueue(game, function()
            local s = session(game)
            if not (s and s.bag) then return nil, "unavailable" end
            local okU, ok, _, text = pcall(IU.useField, s, s.bag, itemId)
            if not okU then
                mod.log:warn("field item failed: %s", tostring(ok))
                return nil, "field unavailable"
            end
            if not ok then return nil, text or "field unavailable" end
            reply = how == "scene" and { scene = true } or { text = text }
            return true
        end)
        if not done then return nil, err == "busy" and "field busy" or err end
        return true, nil, reply or { scene = true }
    end

    function A.tick(game)
        if not pending then return end
        if love.timer.getTime() > pending.expires then
            pending = nil
            return
        end
        local okFree, why = free(game)
        if okFree then
            local run = pending.run
            pending = nil
            local ok, err = pcall(run)
            if not ok then mod.log:warn("queued action failed: %s", tostring(err)) end
        elseif why ~= "walking" then
            pending = nil -- something else opened: drop it, never run it late
        end
    end

    return A
end
