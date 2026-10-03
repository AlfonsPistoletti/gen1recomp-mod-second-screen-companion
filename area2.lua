-- The POKéDEX AREA view on Gen 2 (Gold / Silver). Like the #DEX AREA page
-- (src/ui/gen2/PokedexMenu.lua drawArea): the POKéGEAR region map with a
-- blinking nest on every LANDMARK whose grass or water holds the species
-- (src/core/gen2/Nests.lua find, roaming legendaries included), JOHTO and,
-- once the HALL OF FAME has been entered (or with SPOILERS), KANTO.
--
-- The list below adds what the map cannot show: how (grass / surf / rod),
-- levels, chance, and WHEN -- Gold's grass tables differ by MORN / DAY /
-- NITE, and some fishing rows by day / night.
return function(mod, sprites, live, platform)
    local Nests = require("src.core.gen2.Nests")

    local A = {}

    local REFRESH_SECONDS = 15
    local DAYTIMES = { "MORN", "DAY", "NITE" }
    local KIND_ORDER = { grass = 1, cave = 1, surf = 2, OLD_ROD = 3, GOOD_ROD = 4, SUPER_ROD = 5, roam = 6 }

    local index, indexFor, indexAt

    -- species -> list of { mapId, kind, label, minL, maxL, chance, daytime }
    local function buildIndex(game)
        local enc = game.data.gen2Encounters or {}
        local maps, seen = {}, {}
        for _, key in ipairs({ "grass", "water" }) do
            for mapId in pairs(enc[key] or {}) do
                if not seen[mapId] then seen[mapId] = true maps[#maps + 1] = mapId end
            end
        end
        for mapId, def in pairs(game.data.gen2Maps or {}) do
            if type(def) == "table" and def.fishGroup and not seen[mapId] then
                seen[mapId] = true
                maps[#maps + 1] = mapId
            end
        end
        local out = {}
        for _, mapId in ipairs(maps) do
            for _, daytime in ipairs(DAYTIMES) do
                local ok, sections = pcall(live.mapSections, game, mapId, true, { daytime = daytime, allRods = true })
                if ok then
                    for _, section in ipairs(sections) do
                        for _, e in ipairs(section.list or {}) do
                            if e.species then
                                local rows = out[e.species]
                                if not rows then rows = {} out[e.species] = rows end
                                rows[#rows + 1] = { mapId = mapId, kind = section.kind, label = section.label,
                                    minL = e.minL, maxL = e.maxL, chance = e.chance, daytime = daytime }
                            end
                        end
                    end
                end
            end
        end
        return out
    end

    local function speciesRows(game, species)
        local now = love.timer.getTime()
        if indexFor ~= game.data.gen2Encounters or not index or now - indexAt > REFRESH_SECONDS then
            index, indexFor, indexAt = buildIndex(game), game.data.gen2Encounters, now
        end
        return index[species] or {}
    end

    local function landmarkOf(game, mapId)
        local def = game.data.gen2Maps and game.data.gen2Maps[mapId]
        local idx = def and def.landmark
        local mark = idx and Nests.landmark(game.data, idx)
        return idx, mark
    end

    local function cleanName(name)
        return (tostring(name or ""):gsub("\n", " "))
    end

    -- KANTO opens where the game opens it: the POKéGEAR's fly map shows its
    -- Kanto half once INDIGO PLATEAU has been visited (FieldMoves.flyPoints,
    -- the SPAWN_INDIGO gate), and the #DEX AREA page after the HALL OF FAME.
    -- Either counts, since a save converted from a cartridge can carry the
    -- visited flypoints without the Hall of Fame record.
    local function kantoOpen(game, spoilers)
        if spoilers then return true end
        local save = game.save
        local okF, FieldMoves = pcall(require, "src.world.gen2.FieldMoves")
        if okF and FieldMoves.hasVisitedSpawn then
            local ok, visited = pcall(FieldMoves.hasVisitedSpawn, save, "SPAWN_INDIGO")
            if ok and visited then return true end
        end
        -- read the record without HallOfFame.record, which fills in a
        -- missing table (the phone never writes to the save)
        local hof = save and save.hallOfFame
        if type(hof) == "table" and ((tonumber(hof.count) or 0) > 0 or hof.entered == true) then return true end
        return false
    end

    function A.body(game, species, spoilers)
        local data, save = game.data, game.save
        if not (data and save) or type(species) ~= "string" then return nil end
        local def = data.pokemon and data.pokemon[species]
        if type(def) ~= "table" or not def.dex then return nil end
        local known = platform.ownedSet(save)[def.id] or platform.seenSet(save)[def.id]
        if not (known or spoilers) then return nil end

        local function img(kind, ...)
            if not (sprites and sprites[kind]) then return false end
            local ok, id = pcall(sprites[kind], data, ...)
            return ok and id and ("/img/" .. id .. ".png") or false
        end

        -- one row per place and way; floors and times merge (times listed)
        local rows, byKey = {}, {}
        for _, r in ipairs(speciesRows(game, def.id)) do
            local idx, mark = landmarkOf(game, r.mapId)
            local name = mark and cleanName(mark.name) or live.locationName(game, r.mapId)
            local region = idx and Nests.regionOf(idx, data) or "johto"
            local key = region .. "|" .. name .. "|" .. r.kind
            local row = byKey[key]
            if not row then
                row = { name = name, region = region, kind = r.kind, label = r.label, minL = r.minL, maxL = r.maxL,
                    minChance = r.chance, maxChance = r.chance, order = idx or math.huge, times = {} }
                byKey[key] = row
                rows[#rows + 1] = row
            else
                if r.minL and (not row.minL or r.minL < row.minL) then row.minL = r.minL end
                if r.maxL and (not row.maxL or r.maxL > row.maxL) then row.maxL = r.maxL end
                row.minChance = math.min(row.minChance, r.chance)
                row.maxChance = math.max(row.maxChance, r.chance)
            end
            row.times[r.daytime] = true
        end

        -- nests: the game's own search, per region (roamers included)
        local regions = {}
        local kanto = kantoOpen(game, spoilers)
        -- the map image starts below the cropped title strip (sprites.regionMap)
        local top = sprites and sprites.REGION_MAP_TOP or 0
        local mapH = sprites and sprites.REGION_MAP_H or 144
        for _, region in ipairs({ "johto", "kanto" }) do
            local nests, placed = {}, {}
            local ok, found = pcall(Nests.find, data, def.id, region, save)
            for _, idx in ipairs(ok and found or {}) do
                local mark = Nests.landmark(data, idx)
                if mark and mark.x and mark.y then
                    local name = cleanName(mark.name)
                    -- drawn at x - 4, y - 4 (PokedexMenu drawArea), in map-image pixels
                    nests[#nests + 1] = { px = mark.x - 4, py = mark.y - 4 - top, name = name }
                    placed[name] = true
                end
            end
            -- a roaming legendary is at a landmark the tables do not list
            for name in pairs(placed) do
                local listed = false
                for _, row in ipairs(rows) do
                    if row.region == region and row.name == name then listed = true break end
                end
                if not listed then
                    rows[#rows + 1] = { name = name, region = region, kind = "roam", label = "ROAMING",
                        minL = false, maxL = false, minChance = false, maxChance = false, order = math.huge, times = {} }
                end
            end
            regions[#regions + 1] = {
                id = region, label = region == "johto" and "JOHTO" or "KANTO",
                open = region == "johto" or kanto,
                mapW = 160, mapH = mapH,
                map = (region == "johto" or kanto) and img("regionMap", region) or false,
                nests = (region == "johto" or kanto) and nests or {}
            }
        end

        table.sort(rows, function(a, b)
            if a.region ~= b.region then return a.region == "johto" end
            if a.order ~= b.order then return a.order < b.order end
            if a.name ~= b.name then return a.name < b.name end
            return (KIND_ORDER[a.kind] or 9) < (KIND_ORDER[b.kind] or 9)
        end)
        for _, row in ipairs(rows) do
            -- every time of day: no label; else the ones that apply
            -- (whenKeys: MORN / DAY / NITE, for the page's time-of-day icons)
            local list, keys = {}, {}
            for _, t in ipairs(DAYTIMES) do
                if row.times[t] then
                    list[#list + 1] = platform.daytimeLabel(t)
                    keys[#keys + 1] = t
                end
            end
            local partial = #list > 0 and #list < 3
            row.when = partial and table.concat(list, "/") or false
            row.whenKeys = partial and keys or false
            row.times, row.order = nil, nil
            -- the other region stays hidden until the page may show it
            if row.region == "kanto" and not kanto then row.hidden = true end
        end
        local visible = {}
        for _, row in ipairs(rows) do
            if not row.hidden then visible[#visible + 1] = row end
        end

        return {
            species = tostring(def.id),
            name = def.name or tostring(def.id),
            nest = img("nest"),
            regions = regions,
            rows = visible
        }
    end

    return A
end
