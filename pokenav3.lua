-- Emerald's POKéNAV tab (the slot Gen 2's GEAR uses): what the game's
-- PokéNav knows that the other tabs don't, plus the berry trees.
--
--   MATCH CALL  the contacts, as the PokéNav lists them
--               (src/core/game3/rse/match_call.lua MatchCall.buildList:
--               the story contacts the game has enabled, then every trainer
--               registered), with where they are and a REMATCH badge when
--               they want a battle
--   BERRIES     every planted berry tree (save.berryTrees), placed by the
--               map it grows on: the berry, its stage, the time to the next
--               one, whether it wants water, and the yield once ripe
--
-- Read only. The rematch table is read as it is (Rematch.get / state would
-- create it), and so are the trees (BerryTrees.get / state would create
-- them and plant pending ones).
return function(mod, platform, live, sprites)
    local N = {}

    local function try(fn, ...)
        local ok, a, b = pcall(fn, ...)
        if ok then return a, b end
        return nil
    end
    local function need(name)
        local ok, m = pcall(require, name)
        return ok and m or nil
    end
    local function art(kind, ...)
        if not (sprites and sprites[kind]) then return false end
        local ok, id = pcall(sprites[kind], ...)
        return ok and id and ("/img/" .. id .. ".png") or false
    end

    ---- MATCH CALL -------------------------------------------------------------

    local function matchCall(game, session)
        local MatchCall = need("src.core.game3.rse.match_call")
        local Rematch = need("src.core.game3.rse.rematch")
        local Mapsec = need("src.ui.game3.rse.mapsec")
        if not (MatchCall and Rematch and MatchCall.buildList) then return {} end
        local list = try(MatchCall.buildList, session)
        if type(list) ~= "table" then return {} end
        local none = try(MatchCall.mapsecNone) or 213
        local count = try(Rematch.count) or 0
        local rematches = type(session.trainerRematches) == "table" and session.trainerRematches or {}
        local out = {}
        for _, e in ipairs(list) do
            local desc, name = try(MatchCall.entryNameAndDesc, e)
            local sec = tonumber(e.mapSec)
            local where = sec and sec < none and Mapsec and try(Mapsec.name, sec) or false
            local idx = try(MatchCall.entryRematchIdx, e)
            local ready = idx ~= nil and idx ~= count and (tonumber(rematches[idx]) or 0) ~= 0
            out[#out + 1] = {
                name = type(name) == "string" and name ~= "" and name or (type(desc) == "string" and desc) or "?",
                class = type(desc) == "string" and desc ~= "" and desc ~= name and desc or false,
                where = type(where) == "string" and where ~= "" and where or false,
                rematch = ready and true or false,
            }
        end
        return out
    end

    ---- BERRIES ----------------------------------------------------------------

    -- tree id -> { mapId, x, y }: the berry tree objects of every map
    -- (movement type 0x0C, MOVEMENT_TYPE_BERRY_TREE_GROWTH; the tree id in
    -- berryTreeId, as objects.lua reads it), found once in the script bundle
    local MT_BERRY_TREE = 0x0C
    local treePlaces = nil
    local function places()
        if treePlaces then return treePlaces end
        local Space = need("src.core.game3.scripting.space")
        if Space and not Space.bundle and Space.ensureBundle then try(Space.ensureBundle, mod) end
        local events = Space and Space.bundle and Space.bundle.events
        if type(events) ~= "table" then return {} end
        treePlaces = {}
        for mapId, ev in pairs(events) do
            for _, o in pairs(type(ev) == "table" and (ev.objects or ev.objectEvents) or {}) do
                if type(o) == "table" and tonumber(o.movementType) == MT_BERRY_TREE then
                    local id = tonumber(o.berryTreeId or o.trainerRange)
                    if id then treePlaces[id] = { mapId = mapId, x = o.x, y = o.y } end
                end
            end
        end
        return treePlaces
    end

    -- pokeemerald berry.h BERRY_STAGE_*: 1 planted .. 5 berries (255: the
    -- sparkle right after planting, shown as planted)
    local STAGES = { [1] = "PLANTED", [2] = "SPROUTED", [3] = "TALLER", [4] = "FLOWERING", [5] = "BERRIES",
        [255] = "PLANTED" }
    local FIRST_BERRY_ITEM = 133 -- pokeemerald items.h ITEM_CHERI_BERRY

    local function berries(game, session)
        local trees = type(session.berryTrees) == "table" and session.berryTrees or nil
        if not trees then return {} end
        local ItemsData = need("src.core.game3.items_data")
        local where = places()
        local out = {}
        for id, t in pairs(trees) do
            local berry, stage = tonumber(type(t) == "table" and t.berry) or 0, tonumber(type(t) == "table" and t.stage) or 0
            if berry > 0 and stage > 0 then
                local item = FIRST_BERRY_ITEM + berry - 1
                local place = where[tonumber(id) or -1]
                local ripe = stage == 5
                local watered = stage >= 1 and stage <= 4 and t["watered" .. stage]
                out[#out + 1] = {
                    id = tonumber(id) or 0,
                    berry = ItemsData and try(ItemsData.displayName, item) or ("BERRY " .. berry),
                    icon = art("itemIcon", item),
                    -- through the engine's string catalog, so a language
                    -- mod's words show (platform.text, keyed by the English)
                    stage = STAGES[stage] and platform.text(STAGES[stage]) or tostring(stage),
                    -- 1 planted .. 5 berries, for the page's five dots
                    step = stage == 255 and 1 or math.max(1, math.min(5, stage)),
                    ripe = ripe,
                    minutes = not ripe and tonumber(t.minutesUntilNextStage) or false,
                    thirsty = not ripe and stage ~= 255 and not watered or false,
                    yield = ripe and tonumber(t.berryYield) or false,
                    where = place and live and try(live.locationName, game, place.mapId) or false,
                }
            end
        end
        -- ripe ones first, then the soonest to change
        table.sort(out, function(a, b)
            if a.ripe ~= b.ripe then return a.ripe end
            if (a.minutes or 0) ~= (b.minutes or 0) then return (a.minutes or 0) < (b.minutes or 0) end
            return a.id < b.id
        end)
        return out
    end

    ---- state ------------------------------------------------------------------

    -- /state's pokenav part: false before the game world is up
    local callsMemo = {}
    function N.state(game)
        local session = platform.save(game)
        if not session then return false end
        local Rematch = need("src.core.game3.rse.rematch")
        local hasNav = Rematch and Rematch.flag and try(Rematch.flag, session, "FLAG_SYS_POKENAV_GET") or false
        -- the Match Call list changes slowly (a rematch coming up, a new
        -- number): built at most every 2 seconds
        local now = love.timer.getTime()
        local calls = callsMemo.list
        if not calls or callsMemo.session ~= session or now - callsMemo.at >= 2 then
            local okC, built = pcall(matchCall, game, session)
            if not okC then mod.log:warn("match call list failed: %s", tostring(built)) built = {} end
            calls = built
            callsMemo.list, callsMemo.session, callsMemo.at = calls, session, now
        end
        local okB, trees = pcall(berries, game, session)
        if not okB then mod.log:warn("berry trees failed: %s", tostring(trees)) trees = {} end
        return { nav = hasNav and true or false, matchCall = hasNav and calls or {}, berries = trees }
    end

    return N
end
