-- The POKéDEX AREA view: where a species can be found. Nests follow the
-- in-game AREA screen (TownMap.new's nestSpecies: every map whose walking or
-- surfing slots hold the species, placed on that map's TOWN MAP square);
-- the list below adds levels, chances and the fishing rods.
--
-- Encounters come from the same code as the LIVE DexNav, so mods' changes
-- to wild tables (encounter.table hooks) show up here too.
return function(mod, sprites, live)
    local A = {}

    local REFRESH_SECONDS = 15 -- the index is rebuilt at most this often
    local KIND_ORDER = { grass = 1, cave = 1, surf = 2, OLD_ROD = 3, GOOD_ROD = 4, SUPER_ROD = 5 }
    local NESTING = { grass = true, cave = true, surf = true }

    local index, indexFor, indexAt

    -- species -> list of { mapId, kind, label, minL, maxL, chance }
    local function buildIndex(game)
        local data = game.data
        local maps, seen = {}, {}
        for mapId in pairs(data.encounters or {}) do
            if not seen[mapId] then seen[mapId] = true maps[#maps + 1] = mapId end
        end
        for mapId in pairs(data.field and data.field.superRod or {}) do
            if not seen[mapId] then seen[mapId] = true maps[#maps + 1] = mapId end
        end
        local out = {}
        for _, mapId in ipairs(maps) do
            local ok, sections = pcall(live.mapSections, game, mapId)
            if ok then
                for _, section in ipairs(sections) do
                    for _, e in ipairs(section.list or {}) do
                        if e.species then
                            local rows = out[e.species]
                            if not rows then rows = {} out[e.species] = rows end
                            rows[#rows + 1] = { mapId = mapId, kind = section.kind, label = section.label,
                                minL = e.minL, maxL = e.maxL, chance = e.chance }
                        end
                    end
                end
            end
        end
        return out
    end

    local function speciesRows(game, species)
        local now = love.timer.getTime()
        if indexFor ~= game.data.encounters or not index or now - indexAt > REFRESH_SECONDS then
            index, indexFor, indexAt = buildIndex(game), game.data.encounters, now
        end
        return index[species] or {}
    end

    -- the TOWN MAP square of a map (interiors share their town's square)
    local function square(data, mapId)
        local tm = data.field and data.field.townMap or {}
        local locs = tm.locations or {}
        local e = locs[mapId]
        if type(e) ~= "table" then return nil end
        local c = e.coords or e
        local x, y = tonumber(c.x or c.col), tonumber(c.y or c.row)
        if not (x and y) then return nil end
        return { x = x, y = y, name = e.name or e.label }
    end

    -- GET /dex/area: nil for species the player may not look at (same rule
    -- as the entry page: seen, or anything with SPOILERS)
    function A.body(game, species, spoilers)
        local data, save = game.data, game.save
        if not (data and save) or type(species) ~= "string" then return nil end
        local def = data.pokemon and data.pokemon[species]
        if type(def) ~= "table" or not def.dex then return nil end
        local dex = save.pokedex or {}
        local known = (dex.owned or {})[def.id] or (dex.seen or {})[def.id]
        if not (known or spoilers) then return nil end

        local tm = data.field and data.field.townMap or {}
        local order = {}
        for i, mapId in ipairs(tm.cursorOrder or {}) do order[mapId] = i end

        -- one row per place and way to find it; floors of one place merge
        local rows, byKey, nests, nestAt = {}, {}, {}, {}
        for _, r in ipairs(speciesRows(game, def.id)) do
            local sq = square(data, r.mapId)
            local name = sq and sq.name or live.locationName(game, r.mapId)
            local key = name .. "|" .. r.kind
            local row = byKey[key]
            if not row then
                row = { name = name, kind = r.kind, label = r.label, minL = r.minL, maxL = r.maxL,
                    minChance = r.chance, maxChance = r.chance, order = order[r.mapId] or math.huge,
                    x = sq and sq.x or false, y = sq and sq.y or false }
                byKey[key] = row
                rows[#rows + 1] = row
            else
                if r.minL and (not row.minL or r.minL < row.minL) then row.minL = r.minL end
                if r.maxL and (not row.maxL or r.maxL > row.maxL) then row.maxL = r.maxL end
                row.minChance = math.min(row.minChance, r.chance)
                row.maxChance = math.max(row.maxChance, r.chance)
                row.order = math.min(row.order, order[r.mapId] or math.huge)
            end
            -- engine/items/town_map.asm:388 skips this one square
            if sq and NESTING[r.kind] and not (sq.x == 9 and sq.y == 1) then
                local at = sq.x .. "," .. sq.y
                if not nestAt[at] then
                    nestAt[at] = true
                    nests[#nests + 1] = { x = sq.x, y = sq.y, name = name }
                end
            end
        end
        table.sort(rows, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            if a.name ~= b.name then return a.name < b.name end
            return (KIND_ORDER[a.kind] or 9) < (KIND_ORDER[b.kind] or 9)
        end)
        for _, row in ipairs(rows) do row.order = nil end

        local function img(kind)
            if not (sprites and sprites[kind]) then return false end
            local ok, id = pcall(sprites[kind], data)
            return ok and id and ("/img/" .. id .. ".png") or false
        end
        return {
            species = tostring(def.id),
            name = def.name or tostring(def.id),
            map = img("townMap"),
            -- the image's size, and how far below the screen's top it starts
            mapW = 160,
            mapH = sprites and sprites.TOWN_MAP_H or 144,
            mapTop = sprites and sprites.TOWN_MAP_TOP or 0,
            nest = img("nest"),
            nests = nests,
            rows = rows
        }
    end

    return A
end
