-- The LOCATION section's two maps, cheap on purpose: no tiles are sent.
--
--   HERE    the current map as the engine's own minimap grid (WorldAPI
--           mapOverview: walkable / water / blocked per step), its warps
--           sorted by where they lead (POKéMON CENTER, MART, GYM, exit,
--           door), visible item balls (hidden ones only with SPOILERS) and
--           the neighbouring maps named at the edges
--   REGION  the TOWN MAP (Gen 1) or POKéGEAR map (Gen 2) the AREA view
--           already draws, with the current place marked
--
-- The map part changes rarely, so /state carries only a version stamp and
-- the player's position; the page downloads /minimap when the stamp moves.
return function(mod, sprites, live, platform, Json)
    local M = {}

    local REFRESH_SECONDS = 5 -- how often items picked up show up

    local session = ("%x"):format(os.time() % 0x1000000)
    local counter = 0
    local cached, cachedFor, cachedAt, cachedBody, cachedSpoilers

    local function img(kind, ...)
        if not (sprites and sprites[kind]) then return false end
        local ok, id = pcall(sprites[kind], ...)
        return ok and id and ("/img/" .. id .. ".png") or false
    end

    local function mapDef(game, mapId)
        local w = platform.world(game)
        if w and w.map and w.map.id == mapId and w.map.def then return w.map.def end
        local maps = platform.isGen2(game) and game.data.gen2Maps or game.data.maps
        return maps and maps[mapId] or nil
    end

    -- outdoor maps: Gen 2's ROUTE / TOWN environments, Gen 1's outside tilesets
    local GEN1_MAP, GEN1_FIELD_DEFAULTS = "src.world.Map", "src.world.FieldDefaults"
    local function outdoor(game, def)
        if not def then return false end
        if platform.isGen2(game) then return def.environment == "ROUTE" or def.environment == "TOWN" end
        if platform.isGen3(game) then
            -- MAP_TYPE_TOWN .. MAP_TYPE_ROUTE, OCEAN_ROUTE (pokefirered overworld.c)
            local okD, Dataset = pcall(require, "src.core.game3.dataset")
            return okD and Dataset.isOutdoorMapType and Dataset.isOutdoorMapType(def.mapType) or false
        end
        local okM, Map = pcall(require, GEN1_MAP)
        local okF, FieldDefaults = pcall(require, GEN1_FIELD_DEFAULTS)
        if not (okM and okF and Map.isOutside) then return false end
        local ok, out = pcall(Map.isOutside, def, FieldDefaults.field(game.data, "outsideTilesets"))
        return ok and out and true or false
    end

    -- what a warp leads to, by its destination map's id
    local function warpKind(game, fromDef, destMap)
        local id = tostring(destMap or "")
        -- Gen 3 ids spell it POKEMON_CENTER (FR_VIRIDIAN_CITY_POKEMON_CENTER_1F)
        if id:find("POKECENTER", 1, true) or id:find("POKEMON_CENTER", 1, true) then return "center" end
        if id:find("MART", 1, true) then return "mart" end
        if id:find("GYM", 1, true) then return "gym" end
        if id == "LAST_MAP" then return "exit" end
        if not outdoor(game, fromDef) and outdoor(game, mapDef(game, id)) then return "exit" end
        return "door"
    end

    local function placeName(game, mapId)
        local ok, name = pcall(live.locationName, game, mapId)
        return ok and name or (tostring(mapId):gsub("_", " "))
    end

    -- Gen 3: the TOWN MAP the game opens from the BAG, with the player's
    -- icon on the square the game would put it on (region_map_position's
    -- playerCell: GetPlayerPositionOnRegionMap and its overrides) and in
    -- the map of the player's own region (Kanto or a Sevii pair)
    -- Emerald: Hoenn's map, the player's square as the game's own map puts
    -- it (src/ui/game3/rse/region_map.lua RegionMap.initFromPlayer, given a
    -- scratch table it fills in: indoors and in caves the entrance's
    -- square, the special cases of long routes); no icon on the islands off
    -- the map (manifest offMap), as in the game
    local function regionRse(game, mapId)
        local session = platform.save(game)
        local okR, RegionMap = pcall(require, "src.ui.game3.rse.region_map")
        if not (session and okR and sprites and sprites.regionMap) then return false end
        local def = mapDef(game, session.map) or mapDef(game, mapId)
        local cell = { session = session, mapDef = def }
        if not pcall(RegionMap.initFromPlayer, cell) then return false end
        if not (tonumber(cell.cursorX) and tonumber(cell.cursorY)) then return false end
        local okM, man = pcall(RegionMap.manifest)
        for _, id in ipairs(okM and type(man) == "table" and man.offMap or {}) do
            if id == tonumber(def and def.regionMapSectionId) then return false end
        end
        local okI, id, w, h = pcall(sprites.regionMap)
        if not (okI and id) then return false end
        local female = session.gender == 1 or session.gender == "female" or session.playerGender == 1
        -- the icon's 16x16 box centred on the square's middle (8x + 4, 8y + 4)
        return { map = "/img/" .. id .. ".png", w = w, h = h, px = cell.cursorX * 8 - 4, py = cell.cursorY * 8 - 4,
            icon = img("regionPlayer", female), iw = 16, ih = 16, name = placeName(game, mapId) }
    end

    local function region3(game, mapId)
        if platform.isRse(game) then return regionRse(game, mapId) end
        local session = platform.save(game)
        local okE, RegionExtract = pcall(require, "src.import.gba.region_map_extract")
        local okP, Position = pcall(require, "src.ui.game3.region_map_position")
        if not (session and okE and okP and sprites and sprites.regionMap) then return false end
        if RegionExtract.ensureGenerated then pcall(RegionExtract.ensureGenerated) end
        if not (RegionExtract.GEOMETRY and RegionExtract.LAYOUTS) then return false end
        local maps = game.data and game.data.maps or {}
        local function def(id) return assert(maps[id], "no map header for " .. tostring(id)) end
        local okD, here = pcall(def, session.map)
        if not okD then return false end
        local okC, cx, cy = pcall(Position.playerCell, {
            map = session.map, x = session.x, y = session.y,
            escapeWarp = session.escapeWarp, dynamicWarp = session.dynamicWarp, def = def,
        }, RegionExtract.GEOMETRY)
        local okR, which = pcall(Position.regionFor, here.regionMapSectionId, RegionExtract.LAYOUTS)
        if not (okC and okR and cx and cy) then return false end
        local okM, RegionMap = pcall(require, "src.ui.game3.region_map")
        local function flag(name)
            if not (okM and RegionMap.isFlagSet) then return true end
            local ok, set = pcall(RegionMap.isFlagSet, name)
            return ok and set or false
        end
        local okI, id, w, h = pcall(sprites.regionMap, which,
            which == 2 and not flag("FLAG_WORLD_MAP_NAVEL_ROCK_EXTERIOR"),
            which == 3 and not flag("FLAG_WORLD_MAP_BIRTH_ISLAND_EXTERIOR"))
        if not (okI and id) then return false end
        local female = session.gender == 1 or session.gender == "female" or session.playerGender == 1
        -- the icon's 16x16 box centred on the 8x8 square (8x + 8, 8y + 16)
        return { map = "/img/" .. id .. ".png", w = w, h = h, px = cx * 8 + 4, py = cy * 8 + 12,
            icon = img("regionPlayer", female), iw = 16, ih = 16, name = placeName(game, mapId) }
    end

    -- the region map and where the current place sits on it
    local function region(game, mapId)
        local data = game.data
        if platform.isGen3(game) then return region3(game, mapId) end
        if platform.isGen2(game) then
            local okN, Nests = pcall(require, "src.core.gen2.Nests")
            local def = mapDef(game, mapId)
            local idx = def and def.landmark
            if not (okN and idx) then return false end
            local mark = Nests.landmark(data, idx)
            local which = Nests.regionOf(idx, data) or "johto"
            if not (mark and mark.x and mark.y) then return false end
            local top = sprites and sprites.REGION_MAP_TOP or 0
            return { map = img("regionMap", data, which), w = 160, h = sprites and sprites.REGION_MAP_H or 144,
                px = mark.x - 4, py = mark.y - 4 - top, name = (tostring(mark.name or ""):gsub("\n", " ")) }
        end
        local tm = data.field and data.field.townMap or {}
        local loc = tm.locations and tm.locations[mapId]
        if type(loc) ~= "table" or not (loc.x and loc.y) then return false end
        local top = sprites and sprites.TOWN_MAP_TOP or 0
        return { map = img("townMap", data), w = 160, h = sprites and sprites.TOWN_MAP_H or 144,
            px = loc.x * 8 + 16, py = loc.y * 8 + 8 - top, name = loc.name or placeName(game, mapId) }
    end

    -- Tall grass (where wild POKéMON appear on foot), by each game's own
    -- test: Gen 1 / Gen 2's Map:isGrassCell (the tileset's grass tile,
    -- Gold's grass collision), FireRed's tall-grass metatile behaviours
    -- (pokefirered metatile_behavior.c:432 MB_TALL_GRASS and the Cycling
    -- Road's grass). Returns a (x, y) -> bool test, or nil.
    -- the grass behaviours per Gen 3 layout: FireRed's tall grass and the
    -- Cycling Road's (0xD1); Emerald's tall and long grass (pokeemerald
    -- metatile_behaviors.h MB_TALL_GRASS 0x02, MB_LONG_GRASS 0x03; its 0xD1
    -- is MB_BUMPY_SLOPE, not grass)
    local GRASS_FRLG = { [0x02] = true, [0xD1] = true }
    local GRASS_RSE = { [0x02] = true, [0x03] = true }
    local function grassTest(game)
        if platform.isGen3(game) then
            -- mods have no package table: require hands over the engine's own
            -- (already loaded) modules
            local function loaded(name)
                local ok, m = pcall(require, "src.core.game3." .. name)
                return ok and m or nil
            end
            local C = loaded("collision")
            if not C then return nil end
            local E = loaded("encounters")
            -- a tile's encounter type counts outdoors only: a cave's whole
            -- floor has the LAND type too
            local M = loaded("map")
            local def = M and M.currentDef and select(2, pcall(M.currentDef))
            local okD, Dataset = pcall(require, "src.core.game3.dataset")
            local outdoors = type(def) == "table" and okD and Dataset.isOutdoorMapType
                and Dataset.isOutdoorMapType(def.mapType) or false
            -- the engine's three ways of telling (any one will do): the
            -- metatile behaviour, the collision grid's grass value
            -- (Collision.isGrass) and, outdoors, the LAND encounter type
            local grassBehavior = platform.isRse(game) and GRASS_RSE or GRASS_FRLG
            return function(x, y)
                if C.behavior then
                    local ok, b = pcall(C.behavior, x, y)
                    if ok and grassBehavior[b] then return true end
                end
                if C.isGrass then
                    local ok, g = pcall(C.isGrass, x, y)
                    if ok and g then return true end
                end
                if outdoors and E and E.encounterTypeAt then
                    local ok, t = pcall(E.encounterTypeAt, x, y)
                    if ok and t == (E.TILE_ENCOUNTER_LAND or 1) then return true end
                end
                return false
            end
        end
        local w = platform.world(game)
        local map = w and w.map
        if not (map and map.isGrassCell) then return nil end
        return function(x, y)
            local ok, g = pcall(map.isGrassCell, map, x, y)
            return ok and g
        end
    end

    -- the grid with its grass cells marked '"' (drawn green): walkable ones
    -- ('.'), and ones the overview drew as blocked (' ') although they are
    -- grass (a game whose collision gives grass its own value)
    local function markGrass(game, rows)
        local isGrass = grassTest(game)
        if not isGrass then return rows end
        local out = {}
        for y, row in ipairs(rows) do
            out[y] = row:gsub("()([%. ])", function(i, c)
                return isGrass(i - 1, y - 1) and '"' or c
            end)
        end
        return out
    end

    -- Emerald, ROUTE 119 with SPOILERS: the six tiles where FEEBAS bites
    -- today (pokeemerald wild_encounter.c:90-150, as the engine's
    -- encounter_rules/rse.lua checkFeebas works them out). Redone here
    -- without its side effect: checkFeebas rolls the game's random number
    -- first, which the phone must never do. The day's seed is the first
    -- Dewford trend's; the LCG is the engine's own formula, kept exactly as
    -- it is so the spots match where FEEBAS really bites in this game.
    -- Spots are numbered across the route's three sections, row by row,
    -- over the surfable tiles that aren't a waterfall.
    local NUM_FEEBAS_SPOTS, NUM_FISHING_SPOTS, TILE_FLAG_SURFABLE = 6, 131 + 167 + 149, 2
    local function feebasSpots(game, mapId)
        local session = platform.save(game)
        local okV, GameVersion = pcall(require, "src.core.GameVersion")
        local okI, MapIds = pcall(require, "src.core.game3.map_ids")
        local route = okI and okV and select(2, pcall(MapIds.forConst, "MAP_ROUTE119", GameVersion.current)) or "EM_ROUTE119"
        if not session or tostring(mapId) ~= tostring(route) then return nil end
        local trend = type(session.dewfordTrends) == "table" and session.dewfordTrends[1]
        local okE, E = pcall(require, "src.core.game3.encounters")
        local okC, Coll = pcall(require, "src.core.game3.collision")
        local okR, CollRse = pcall(require, "src.core.game3.scripting.collision_rse")
        local okM, MB = pcall(require, "src.core.game3.mb")
        if not (okE and okC and okR and okM and E.loadCacheFile and Coll.behavior) then return nil end
        local okX, extra = pcall(E.loadCacheFile, "wild_extra.lua")
        local sections = okX and type(extra) == "table" and extra.feebas and extra.feebas.sections
        local bits = CollRse._tileBits
        local layout = Coll._mapDef and Coll._mapDef.midLayout
        local width = layout and tonumber(layout.width) or 0
        if not (sections and bits and width > 0) then return nil end
        -- the day's six spot numbers
        local v = tonumber(trend and trend.rand) or 0
        local wanted, i = {}, 0
        local list = {}
        while i ~= NUM_FEEBAS_SPOTS do
            v = (1103515245 * v + 12345) % 4294967296
            local n = math.floor(v / 65536) % NUM_FISHING_SPOTS
            if n == 0 then n = NUM_FISHING_SPOTS end
            list[i + 1] = n
            if n < 1 or n >= 4 then i = i + 1 end
        end
        for _, n in ipairs(list) do wanted[n] = true end
        -- walk the sections, numbering the fishable water
        local waterfall = select(2, pcall(MB.id, "WATERFALL"))
        local out = {}
        for _, sec in ipairs(sections) do
            local spot = tonumber(sec.spotBase) or 0
            for y = sec.yMin, sec.yMax do
                for x = 0, width - 1 do
                    local okB, b = pcall(Coll.behavior, x, y)
                    local tb = okB and b ~= nil and tonumber(bits[b]) or 0
                    if math.floor(tb / TILE_FLAG_SURFABLE) % 2 == 1 and b ~= waterfall then
                        spot = spot + 1
                        if wanted[spot] then out[#out + 1] = { x = x, y = y } end
                    end
                end
            end
        end
        return out
    end

    local function build(game, spoilers)
        local w = mod.world
        if not (w and w.mapOverview) then return nil end
        local ok, view = pcall(w.mapOverview, w)
        if not (ok and type(view) == "table" and view.rows) then return nil end
        local mapId = view.mapId
        local def = mapDef(game, mapId) or {}
        local out = { mapId = tostring(mapId), w = view.width, h = view.height, rows = markGrass(game, view.rows),
            warps = {}, items = {}, edges = {}, region = false }
        for _, warp in ipairs(def.warps or {}) do
            -- Gen 3 warps may name their map by group / number only
            local dest = warp.destMap or warp.map
            if not dest and warp.mapGroup ~= nil then
                local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
                dest = okC and MapCatalog.mapIdFor and MapCatalog.mapIdFor(warp.mapGroup, warp.mapNum) or nil
            end
            out.warps[#out.warps + 1] = { x = warp.x, y = warp.y, kind = warpKind(game, def, dest),
                to = dest ~= "LAST_MAP" and dest and placeName(game, dest) or false }
        end
        for _, m in ipairs(view.markers or {}) do
            if m.kind == "item" or (m.kind == "hidden" and spoilers) then
                out.items[#out.items + 1] = { x = m.x, y = m.y, hidden = m.kind == "hidden" or nil }
            end
        end
        if platform.isGen3(game) then
            -- a list of { dir = "north", map = ... } (src/core/game3/connections.lua)
            local okC, Connections = pcall(require, "src.core.game3.connections")
            local list = okC and Connections.each and select(2, pcall(Connections.each, def)) or {}
            for _, conn in ipairs(type(list) == "table" and list or {}) do
                if conn.dir and type(conn.map) == "string" and not out.edges[conn.dir] then
                    out.edges[conn.dir] = placeName(game, conn.map)
                end
            end
        else
            for dir, conn in pairs(def.connections or {}) do
                local to = type(conn) == "table" and (conn.mapId or conn.map)
                if type(to) == "string" then out.edges[dir] = placeName(game, to) end
            end
        end
        out.region = region(game, mapId)
        if spoilers and platform.isRse(game) then
            local ok, spots = pcall(feebasSpots, game, mapId)
            if ok and spots and #spots > 0 then out.feebas = spots end
        end
        return out
    end

    local function refresh(game, spoilers)
        local mapId = platform.mapId(game)
        if not mapId then return nil end
        local now = love.timer.getTime()
        if cachedFor ~= mapId or cachedSpoilers ~= spoilers or not cachedAt or now - cachedAt > REFRESH_SECONDS then
            local view = build(game, spoilers)
            -- Only a map built for the place the player is in counts: during
            -- a map change the overview can fail or still describe the map
            -- being left, and taking that as done would keep the old map on
            -- the phone until the next timed refresh. Such a build is tried
            -- again on the next poll instead.
            if not (view and tostring(view.mapId) == tostring(mapId)) then
                return cached
            end
            cachedAt, cachedFor, cachedSpoilers = now, mapId, spoilers
            if view then
                local body = Json.encode(view)
                if body ~= cachedBody then
                    counter = counter + 1
                    view.version = session .. "-" .. counter
                    cached, cachedBody = view, body
                    cached.body = Json.encode(view)
                end
            end
        end
        return cached
    end

    -- /state: the version stamp, so the page knows when to fetch the map
    function M.summary(game, spoilers)
        local view = refresh(game, spoilers)
        if not view then return false end
        -- the player's tile (mod.world:current), so a page can tell the game
        -- is being played (the HANDS-OFF screen dims when nothing happens)
        local x, y = false, false
        local w = mod.world
        if w and w.current then
            local ok, here = pcall(w.current, w)
            if ok and type(here) == "table" then x, y = here.x or false, here.y or false end
        end
        return { version = view.version, mapId = view.mapId, x = x, y = y }
    end

    -- GET /minimap: the map part
    function M.body(game, spoilers)
        local view = refresh(game, spoilers)
        return view and view.body or nil
    end

    return M
end
