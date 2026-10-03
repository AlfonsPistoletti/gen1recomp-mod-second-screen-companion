-- Gen 3 (FireRed / LeafGreen) POKéDEX AREA: every place a species can be
-- found in the wild, with how (grass / cave, surfing, Rock Smash, each rod),
-- its levels and its share of that place's encounters. Same math as the
-- LIVE tab's DexNav (live3.mapSections). No region map yet: FireRed's is a
-- picture of its own, so the rows come without map squares.
return function(mod, sprites, live, platform, dex)
    local Pokemon = require("src.core.game3.pokemon")

    local A = {}

    local KIND_ORDER = { grass = 1, cave = 1, surf = 2, rock = 3, OLD_ROD = 4, GOOD_ROD = 5, SUPER_ROD = 6,
        roam = 7 }

    -- The Sevii Island a map lies on ("ISLAND 3"), or nil for Kanto, by
    -- the game's own POKéDEX data: the map's section (map_sections_extract
    -- getInfo), its POKéDEX area (area_markers mapsecToArea, as
    -- pokedex_data's own wild-area index looks it up) and that area's map
    -- (PokedexData.getAreaMapKey: "three_island"). Looked up once per map.
    local ISLAND_NUMBER = { one_island = 1, two_island = 2, three_island = 3, four_island = 4,
        five_island = 5, six_island = 6, seven_island = 7 }
    local islandCache, areaCache = {}, {}
    local ISLAND_TOWNS = { ["ONE ISLAND"] = true, ["TWO ISLAND"] = true, ["THREE ISLAND"] = true,
        ["FOUR ISLAND"] = true, ["FIVE ISLAND"] = true, ["SIX ISLAND"] = true, ["SEVEN ISLAND"] = true }
    -- a map's POKéDEX area key (its section, then area_markers mapsecToArea)
    local function areaOf(mapId)
        if areaCache[mapId] ~= nil then return areaCache[mapId] or nil end
        areaCache[mapId] = false
        local okS, Sections = pcall(require, "src.import.gba.map_sections_extract")
        local okP, PD = pcall(require, "src.core.game3.pokedex_data")
        if not (okS and okP and Sections.getInfo) then return nil end
        if PD.init then pcall(PD.init) end
        local okI, info = pcall(Sections.getInfo, nil, mapId)
        local sec = okI and type(info) == "table" and info.id
        local toArea = PD._areaData and PD._areaData.mapsecToArea
        areaCache[mapId] = sec and toArea and toArea[sec] or false
        return areaCache[mapId] or nil
    end
    local function islandOf(mapId)
        if islandCache[mapId] ~= nil then return islandCache[mapId] or nil end
        islandCache[mapId] = false
        local okP, PD = pcall(require, "src.core.game3.pokedex_data")
        local area = areaOf(mapId)
        local n = area and okP and PD.getAreaMapKey and ISLAND_NUMBER[PD.getAreaMapKey(area)]
        if n then islandCache[mapId] = "ISLAND " .. n end
        return islandCache[mapId] or nil
    end

    -- every map the wild tables cover, by id; built once (the ROM's tables
    -- do not change while the game runs)
    local mapIds
    local function allMaps()
        if mapIds then return mapIds end
        local okE, E = pcall(require, "src.core.game3.encounters")
        if not (okE and E.ensureLoaded) then return {} end
        pcall(E.ensureLoaded)
        local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
        local out, seen = {}, {}
        for key, t in pairs(E._tables or {}) do
            local id = key
            if type(t) == "table" and t.mapGroup and okC and MapCatalog.mapIdFor then
                id = MapCatalog.mapIdFor(t.mapGroup, t.mapNum) or key
            end
            if not seen[id] then
                seen[id] = true
                out[#out + 1] = id
            end
        end
        table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
        mapIds = out
        return out
    end

    -- GET /dex/area
    function A.body(game, species, spoilers)
        local sp = dex and dex.access and dex.access(game, species, spoilers)
        if not sp then return nil end
        local rows, byKey = {}, {}
        for _, mapId in ipairs(allMaps()) do
            local okS, sections = pcall(live.mapSections, game, mapId)
            for _, section in ipairs(okS and sections or {}) do
                for _, e in ipairs(section.list or {}) do
                    if tonumber(e.species) == sp then
                        local name = live.locationName(game, mapId)
                        local key = name .. "|" .. section.kind
                        local row = byKey[key]
                        if not row then
                            row = { name = name, kind = section.kind, label = section.label,
                                minL = e.minL, maxL = e.maxL, minChance = e.chance, maxChance = e.chance,
                                x = false, y = false,
                                -- the island towns say it in their own name
                                island = not ISLAND_TOWNS[name] and islandOf(mapId) or nil }
                            byKey[key] = row
                            rows[#rows + 1] = row
                        else
                            -- floors of one place merge into one row
                            if e.minL and (not row.minL or e.minL < row.minL) then row.minL = e.minL end
                            if e.maxL and (not row.maxL or e.maxL > row.maxL) then row.maxL = e.maxL end
                            row.minChance = math.min(row.minChance, e.chance)
                            row.maxChance = math.max(row.maxChance, e.chance)
                        end
                    end
                end
            end
        end
        -- the roaming legendary where it is right now (the game's POKéDEX
        -- shows it too), a marker of its own on the map
        local extraAreas = {}
        local r = live.roamer and live.roamer(game)
        if r and tonumber(r.species) == sp then
            for _, mapId in ipairs(allMaps()) do
                if live.roamerOn(game, mapId) then
                    local name = live.locationName(game, mapId)
                    local level = tonumber(r.level) or false
                    rows[#rows + 1] = { name = name, kind = "roam", label = "ROAMING",
                        minL = level, maxL = level, minChance = false, maxChance = false,
                        x = false, y = false, roam = true }
                    extraAreas[#extraAreas + 1] = areaOf(mapId)
                    break
                end
            end
        end
        table.sort(rows, function(a, b)
            if a.roam ~= b.roam then return not a.roam end
            if a.name ~= b.name then return a.name < b.name end
            return (KIND_ORDER[a.kind] or 9) < (KIND_ORDER[b.kind] or 9)
        end)
        local ok, name = pcall(Pokemon.name, sp)
        -- Emerald: Hoenn's map with the sections the game's own AREA search
        -- lights up (src/ui/game3/rse/pokedex_area.lua, given the context
        -- its POKéDEX builds: Pokedex.areaContext)
        if platform.isRse(game) then
            local map, mapW, mapH = false, 0, 0
            local okD, Dex = pcall(require, "src.ui.game3.rse.pokedex")
            local okA, Area = pcall(require, "src.ui.game3.rse.pokedex_area")
            if okD and okA and Dex.areaContext and sprites and sprites.areaMapHoenn then
                local okC, ctx = pcall(Dex.areaContext, { session = platform.save(game) })
                local okF, found = false, nil
                if okC then okF, found = pcall(Area.findMapsWithMon, sp, ctx) end
                if okF and found then
                    local okM, id, w, h = pcall(sprites.areaMapHoenn, found)
                    if okM and id then map, mapW, mapH = "/img/" .. id .. ".png", w, h end
                    if not okM then mod.log:warn("area map failed: %s", tostring(id)) end
                elseif not (okC and okF) then
                    mod.log:warn("area search failed: %s", tostring(okC and found or ctx))
                end
            end
            return { species = tostring(sp), name = ok and name or tostring(sp), map = map,
                mapW = mapW, mapH = mapH, mapTop = 0, nest = false, nests = {}, rows = rows }
        end
        -- the POKéDEX's own area map, markers drawn in (sprites3.areaMap);
        -- the Sevii Islands once the game has shown them on its maps
        local map, mapW, mapH = false, 0, 0
        if sprites and sprites.areaMap then
            local okR, RegionMap = pcall(require, "src.ui.game3.region_map")
            local function flag(name)
                if not (okR and RegionMap.isFlagSet) then return false end
                local okF, set = pcall(RegionMap.isFlagSet, name)
                return okF and set or false
            end
            local okM, id, w, h = pcall(sprites.areaMap, sp, flag("FLAG_SYS_SEVII_MAP_123"),
                flag("FLAG_SYS_SEVII_MAP_4567"), extraAreas)
            if okM and id then map, mapW, mapH = "/img/" .. id .. ".png", w, h end
            if not okM then mod.log:warn("area map failed: %s", tostring(id)) end
        end
        return { species = tostring(sp), name = ok and name or tostring(sp), map = map,
            mapW = mapW, mapH = mapH, mapTop = 0, nest = false, nests = {}, rows = rows }
    end

    return A
end
