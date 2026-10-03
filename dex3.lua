-- Gen 3 (FireRed / LeafGreen) twin of dex.lua: the POKéDEX tab from the
-- game3 engine. Same routes and shapes, with Gen 3's own facts:
--
--   * the list runs in national order, as long as the game's dex currently
--     is: Kanto's 151 until the NATIONAL DEX is unlocked, then all 386
--     (src/core/game3/dex.lua regionalMax / NATIONAL_MAX, never hard-coded)
--   * seen / caught marks live in session.dex, keyed by internal species
--   * an entry has a category, height in decimetres and weight in
--     hectograms, shown as the game prints them (ft/in, lbs) plus metric
--   * SHOW HIDDEN VALUES adds the base stats with SP. ATK / SP. DEF, both
--     abilities, the EV yield, catch rate, base EXP and the egg data
return function(mod, sprites, Json, platform)
    local Pokemon = require("src.core.game3.pokemon")
    local Dex = require("src.core.game3.dex")
    local Types = require("src.core.game3.battle.types")
    local ItemsData = require("src.core.game3.items_data")

    local D = {}

    local function try(fn, ...)
        local ok, a = pcall(fn, ...)
        if ok then return a end
        return nil
    end

    local session = ("%x"):format(os.time() % 0x1000000)
    local counter, lastSig = 0, nil
    local cachedBody, cachedVersion

    local function pokedexData()
        local ok, P = pcall(require, "src.core.game3.pokedex_data")
        return ok and P or nil
    end

    local function img(kind, sp)
        if not (sprites and sprites[kind]) then return false end
        local id = try(sprites[kind], nil, sp)
        return id and ("/img/" .. id .. ".png") or false
    end

    local function isSeen(save, sp) return try(Dex.isSeen, save.dex, sp) or false end
    local function isOwned(save, sp) return try(Dex.isCaught, save.dex, sp) or false end

    -- how far the dex reaches right now
    -- Whether the NATIONAL DEX is unlocked, by the game's own POKéDEX
    -- test (PokedexData.isNationalUnlocked: the dex's mark, or the live
    -- FLAG_SYS_NATIONAL_DEX / VAR_NATIONAL_DEX in the script store)
    local function nationalUnlocked(save)
        local P = pokedexData()
        if P and P.isNationalUnlocked then
            local ok, on = pcall(P.isNationalUnlocked, save, save and save.dex)
            if ok and on then return true end
        end
        return try(Dex.nationalEnabled, save) and true or false
    end

    -- the regional (KANTO) dex's length
    local function regionalMax(save)
        return try(Dex.regionalMax, save and save.version) or Dex.KANTO_MAX or 151
    end

    -- how far the dex reaches right now: Kanto's until the NATIONAL DEX
    local function dexSize(save)
        if nationalUnlocked(save) then return Dex.NATIONAL_MAX or 386 end
        return regionalMax(save)
    end

    local TYPE_KEY = {}
    for key, id in pairs(Types.ID or {}) do TYPE_KEY[id] = key end

    local function typeName(id)
        return try(Types.name, id) or TYPE_KEY[id] or tostring(id)
    end

    local function typesOf(sp)
        local out, dup = {}, {}
        for _, t in ipairs(try(Pokemon.types, sp) or {}) do
            local name = typeName(t)
            if not dup[name] then
                dup[name] = true
                out[#out + 1] = name
            end
        end
        return out
    end

    -- the summary screen's type badges for a species, { name, badge } each
    local function typeBadgesOf(sp)
        local out, dup = {}, {}
        for _, t in ipairs(try(Pokemon.types, sp) or {}) do
            if not dup[t] then
                dup[t] = true
                local id = sprites and sprites.typeBadge and try(sprites.typeBadge, t)
                out[#out + 1] = { name = typeName(t), badge = id and ("/img/" .. id .. ".png") or false }
            end
        end
        return out
    end

    -- the game's type order (pret TYPE_* ids, ??? left out)
    local function typeOrder()
        local ids = {}
        for id in pairs(TYPE_KEY) do
            if TYPE_KEY[id] ~= "MYSTERY" then ids[#ids + 1] = id end
        end
        table.sort(ids)
        local out = {}
        for _, id in ipairs(ids) do out[#out + 1] = typeName(id) end
        return out
    end

    -- Height / weight: the game's own ft/in and lbs text, plus metric;
    -- entry.height / .weight in metres and kilograms for sorting
    local function measures(entry, sp)
        local P = pokedexData()
        local e = P and try(P.getEntry, sp)
        if not e then return nil end
        local dm, hg = tonumber(e.heightDm) or 0, tonumber(e.weightHg) or 0
        entry.height, entry.weight = dm / 10, hg / 10
        entry.heightText = (tostring(e.heightFormatted or ""):gsub("^%s+", ""))
        entry.weightText = (tostring(e.weightFormatted or ""):gsub("^%s+", ""))
        entry.heightMetric = ("%.1fm"):format(dm / 10)
        entry.weightMetric = ("%.1fkg"):format(hg / 10)
        return e
    end

    local function signature(game, spoilers)
        local save = platform.save(game)
        local seenSet, ownedSet = platform.seenSet(save), platform.ownedSet(save)
        local n1, n2 = 0, 0
        for _, v in pairs(seenSet) do if v then n1 = n1 + 1 end end
        for _, v in pairs(ownedSet) do if v then n2 = n2 + 1 end end
        return table.concat({ tostring(seenSet), tostring(ownedSet), n1, n2, dexSize(save),
            spoilers and 1 or 0 }, "|")
    end

    -- the base-stat sorts (same keys as dex.lua): hp, atk, def, spa, spd,
    -- spe and their total, from the ROM's base stats
    local BASE_KEYS = { { "hp", "HP" }, { "atk", "ATTACK" }, { "def", "DEFENSE" },
        { "spa", "SP.ATK" }, { "spd", "SP.DEF" }, { "spe", "SPEED" } }

    local function baseOf(sp)
        local b = try(Pokemon.stats, sp)
        if type(b) ~= "table" then return nil end
        local out, total = {}, 0
        for _, k in ipairs(BASE_KEYS) do
            local v = tonumber(b[k[1]])
            if v then
                out[k[1]] = v
                total = total + v
            end
        end
        out.total = total
        return out
    end

    local function build(game, spoilers)
        local save = platform.save(game)
        local size = dexSize(save)
        local national = nationalUnlocked(save)
        local kantoMax = regionalMax(save)
        -- Emerald's regional dex is HOENN's own order, not the first national
        -- numbers like Kanto's: each species' Hoenn number from the game
        -- (Dex.regionalNumber, pokemon.c SpeciesToHoennPokedexNum). Before
        -- the NATIONAL DEX the list holds the Hoenn species only.
        local rse = platform.isRse(game)
        local version = save and save.version
        local limit = (rse and not national) and (Dex.NATIONAL_MAX or 386) or size
        local list, seen, owned = {}, 0, 0
        local kSeen, kOwned = 0, 0
        for n = 1, limit do
            local sp = try(Pokemon.speciesFromNational, n)
            local rn = rse and sp and try(Dex.regionalNumber, sp, version) or nil
            if rse and not national and not rn then sp = nil end
            if sp then
                local isO = isOwned(save, sp)
                local isS = isO or isSeen(save, sp)
                if isO then owned = owned + 1 end
                if isS then seen = seen + 1 end
                if (rse and rn) or (not rse and n <= kantoMax) then
                    if isO then kOwned = kOwned + 1 end
                    if isS then kSeen = kSeen + 1 end
                end
                local known = isS or spoilers
                local entry = {
                    n = n,
                    num = ("%03d"):format(n),
                    species = known and tostring(sp) or false,
                    name = known and (try(Pokemon.name, sp) or tostring(sp)) or false,
                    icon = known and img("iconSpecies", sp) or false,
                    types = known and typesOf(sp) or false,
                    seen = isS,
                    owned = isO,
                    -- Emerald: the HOENN number (the page's regional order)
                    rn = rn
                }
                -- the in-game entry shows HT / WT for caught species only
                if isO or spoilers then
                    measures(entry, sp)
                    -- base stats, for the base-stat sorts: known like HT / WT
                    entry.base = baseOf(sp)
                end
                entry.heightMetric, entry.weightMetric = nil, nil
                list[#list + 1] = entry
            end
        end
        -- with the NATIONAL DEX the game keeps both numerical modes: the
        -- list is national, and KANTO narrows it to the regional numbers
        -- with counts of its own (pokedex_screen.c build_modes)
        local regional = national and { label = "KANTO", max = kantoMax, seen = kSeen, owned = kOwned } or nil
        -- Emerald: HOENN always; before the NATIONAL DEX it is the only mode
        -- (only = true: the page offers HOENN instead of the national No.)
        if rse then
            regional = { label = "HOENN", max = kantoMax, seen = kSeen, owned = kOwned, only = not national,
                numbered = true }
        end
        return { seen = seen, owned = owned, size = size, list = list, johto = false, regional = regional,
            typeOrder = typeOrder(), spoilers = spoilers and true or false, stats = BASE_KEYS }
    end

    local function refresh(game, spoilers)
        local save = platform.save(game)
        if not (save and save.dex) then return nil end
        local sig = signature(game, spoilers)
        if sig ~= lastSig or not cachedBody then
            local result = build(game, spoilers)
            counter = counter + 1
            lastSig = sig
            cachedVersion = session .. "-" .. counter
            result.version = cachedVersion
            cachedBody = Json.encode(result)
            D.summary = { version = cachedVersion, seen = result.seen, owned = result.owned }
        end
        return cachedVersion, cachedBody
    end

    -- a species id from the page ("25"), and whether the player may look
    local function access(game, species, spoilers)
        local save = platform.save(game)
        local sp = tonumber(species)
        if not (save and sp and try(Pokemon.national, sp)) then return nil end
        local owned = isOwned(save, sp)
        local seen = owned or isSeen(save, sp)
        if not (seen or spoilers) then return nil end
        return sp, owned, seen, save
    end

    ---- SHOW HIDDEN VALUES --------------------------------------------------

    local BASE = { { "hp", "HP" }, { "atk", "ATTACK" }, { "def", "DEFENSE" },
        { "spa", "SP. ATK" }, { "spd", "SP. DEF" }, { "spe", "SPEED" } }
    local GROWTH = { [0] = "MEDIUM FAST", "ERRATIC", "FLUCTUATING", "MEDIUM SLOW", "FAST", "SLOW" }

    local function speciesHidden(sp)
        local base = try(Pokemon.stats, sp) or {}
        local stats, total = {}, 0
        for _, s in ipairs(BASE) do
            if base[s[1]] then
                stats[#stats + 1] = { label = s[2], value = base[s[1]] }
                total = total + base[s[1]]
            end
        end
        if #stats > 0 then stats[#stats + 1] = { label = "TOTAL", value = total } end
        local meta = try(Pokemon.speciesMeta, sp) or {}
        -- EV yield: the stats a defeat gives, e.g. "2 SP. ATK"
        local yield = try(Pokemon.evYield, sp) or {}
        local parts = {}
        for _, s in ipairs(BASE) do
            local v = tonumber(yield[s[1]]) or 0
            if v > 0 then parts[#parts + 1] = v .. " " .. s[2] end
        end
        -- held items wild ones may carry
        local items = {}
        for _, key in ipairs({ "itemCommon", "itemRare" }) do
            local id = tonumber(meta[key]) or 0
            if id > 0 then items[#items + 1] = try(ItemsData.displayName, id) or tostring(id) end
        end
        return {
            baseStats = stats,
            catchRate = tonumber(meta.catchRate),
            baseExp = tonumber(meta.expYield),
            growth = GROWTH[(tonumber(meta.growthRate) or 0) % 6],
            evYield = #parts > 0 and table.concat(parts, ", ") or nil,
            wildItems = #items > 0 and table.concat(items, ", ") or nil
        }
    end

    -- both abilities (the second only where the species has one)
    local function abilitiesOf(sp)
        local out = {}
        for _, id in ipairs(try(Pokemon.abilities, sp) or {}) do
            if id and id > 0 then
                local name = try(Pokemon.abilityName, id) or ("ABILITY " .. id)
                local dup = false
                for _, a in ipairs(out) do if a.name == name then dup = true end end
                if not dup then
                    local SD = try(require, "src.core.game3.summary_data")
                    out[#out + 1] = { name = name, desc = SD and try(SD.abilityDescription, id, name) or nil }
                end
            end
        end
        return out
    end

    -- GET /dex/entry
    function D.entry(game, species, spoilers, hidden)
        local sp, owned, seen = access(game, species, spoilers)
        if not sp then return nil end
        local nat = try(Pokemon.national, sp) or 0
        local out = {
            species = tostring(sp),
            num = ("%03d"):format(nat),
            name = try(Pokemon.name, sp) or tostring(sp),
            kind = false,
            types = typesOf(sp),
            typeBadges = typeBadgesOf(sp),
            front = img("frontSpecies", sp),
            owned = owned,
            seen = seen,
            full = owned,
            heightText = false,
            weightText = false,
            text = false,
            heightLabel = platform.text("HT"),
            weightLabel = platform.text("WT"),
            abilities = (owned or spoilers) and abilitiesOf(sp) or nil
        }
        if owned or spoilers then
            local e = measures(out, sp)
            if e then
                out.kind = e.category and (e.category .. " POKéMON") or false
                -- the flavour text runs as one paragraph on the phone
                local text = tostring(e.description or ""):gsub("[\n\\]n?", " "):gsub("%s+", " ")
                    :gsub("^%s+", ""):gsub("%s+$", "")
                if owned and text ~= "" then out.text = { text } end
            end
        end
        if hidden and (owned or spoilers) then out.hidden = speciesHidden(sp) end
        out.height, out.weight = nil, nil
        return out
    end

    ---- EVO and MOVES pages -------------------------------------------------

    local function pageSpecies(game, species, spoilers)
        local sp, owned = access(game, species, spoilers)
        if not sp then return nil end
        if not (owned or spoilers) then return "locked" end
        return sp
    end

    -- GET /dex/moves: level-up moves, egg moves and the TMs / HMs it learns
    function D.moves(game, species, spoilers)
        local sp = pageSpecies(game, species, spoilers)
        if sp == nil then return nil end
        if sp == "locked" then return { locked = true } end
        local out = {}
        for _, row in ipairs(try(Pokemon.learnset, sp) or {}) do
            local move = type(row) == "table" and (row.move or row.id or row[2]) or nil
            local level = type(row) == "table" and (row.level or row[1]) or nil
            if move then
                out[#out + 1] = { level = tonumber(level) or 1, name = try(Pokemon.moveName, move) or tostring(move) }
            end
        end
        table.sort(out, function(a, b) return a.level < b.level end)
        local eggMoves
        local egg = try(Pokemon.eggMoves, sp)
        if type(egg) == "table" then
            eggMoves = {}
            for _, id in ipairs(egg) do eggMoves[#eggMoves + 1] = try(Pokemon.moveName, id) or tostring(id) end
        end
        -- TM01..TM50, HM01..HM08 this species can learn
        local machines = {}
        for index = 0, 57 do
            if try(Pokemon.canLearnTmIndex, sp, index) then
                local item = 289 + index
                local label = index < 50 and ("TM%02d"):format(index + 1) or ("HM%02d"):format(index - 49)
                local moveId = try(Pokemon.moveFromTmItem, item)
                machines[#machines + 1] = label .. " " .. (moveId and try(Pokemon.moveName, moveId) or "")
            end
        end
        return { moves = out, eggMoves = eggMoves, machines = #machines > 0 and machines or nil }
    end

    -- pret egg groups (include/constants/pokemon.h EGG_GROUP_*)
    local EGG_GROUPS = {
        [0] = "NONE", "MONSTER", "WATER 1", "BUG", "FLYING", "FIELD", "FAIRY", "GRASS",
        "HUMAN-LIKE", "WATER 3", "MINERAL", "AMORPHOUS", "WATER 2", "DITTO", "DRAGON", "NO EGGS"
    }

    local function eggGroups(sp)
        local meta = try(Pokemon.speciesMeta, sp) or {}
        local out, dup = {}, {}
        for _, key in ipairs({ "eggGroup1", "eggGroup2" }) do
            local id = tonumber(meta[key])
            local name = id and EGG_GROUPS[id]
            if name and name ~= "NONE" and not dup[name] then
                dup[name] = true
                out[#out + 1] = name
            end
        end
        return #out > 0 and out or nil
    end

    -- gender split and hatch steps (genderRatio: 0 all male, 254 all
    -- female, 255 genderless; a mon is female when its personality's low
    -- byte is under the ratio)
    local function breedingHidden(sp)
        local meta = try(Pokemon.speciesMeta, sp) or {}
        local out = {}
        local ratio = tonumber(meta.genderRatio)
        if ratio then
            if ratio >= 255 then out.gender = { none = true }
            elseif ratio == 0 then out.gender = { male = 100, female = 0 }
            elseif ratio >= 254 then out.gender = { male = 0, female = 100 }
            else
                local female = ratio / 256 * 100
                out.gender = { male = 100 - female, female = female }
            end
        end
        local cycles = tonumber(meta.eggCycles)
        -- 256 steps per egg cycle (daycare.c)
        if cycles then out.hatchSteps = cycles * 256 end
        return out
    end

    -- An evolution row's condition in a few words (EVO_* methods,
    -- pokefirered/include/constants/pokemon.h:266)
    local function howText(evo)
        local method = tonumber(evo.method or evo[1]) or 0
        local param = tonumber(evo.param or evo[2]) or 0
        if method == 1 then return "FRIENDSHIP" end
        if method == 2 then return "FRIENDSHIP · DAY" end
        if method == 3 then return "FRIENDSHIP · NIGHT" end
        if method == 4 then return "Lv." .. param end
        if method == 5 then return "TRADE" end
        if method == 6 then return "TRADE · " .. (try(ItemsData.displayName, param) or tostring(param)) end
        if method == 7 then return try(ItemsData.displayName, param) or ("ITEM " .. param) end
        if method == 8 then return "Lv." .. param .. " · ATK>DEF" end
        if method == 9 then return "Lv." .. param .. " · ATK=DEF" end
        if method == 10 then return "Lv." .. param .. " · ATK<DEF" end
        if method == 11 or method == 12 then return "Lv." .. param .. " · PERSONALITY" end
        if method == 13 then return "Lv." .. param end
        if method == 14 then return "Lv." .. param .. " · EMPTY SLOT" end
        if method == 15 then return "BEAUTY " .. param end
        return "?"
    end

    local function targetOf(evo)
        return type(evo) == "table" and tonumber(evo.target or evo.species or evo[3]) or nil
    end

    -- GET /dex/evo: the family from its first stage down
    function D.family(game, species, spoilers, hidden)
        local sp = pageSpecies(game, species, spoilers)
        if sp == nil then return nil end
        if sp == "locked" then return { locked = true } end
        local save = platform.save(game)
        -- target -> the species it evolves from, over the whole national dex
        local pre = {}
        for n = 1, Dex.NATIONAL_MAX or 386 do
            local from = try(Pokemon.speciesFromNational, n)
            for _, evo in ipairs(from and try(Pokemon.evolutions, from) or {}) do
                local to = targetOf(evo)
                if to and pre[to] == nil then pre[to] = from end
            end
        end
        local root, guard = sp, 0
        while pre[root] and guard < 16 do root, guard = pre[root], guard + 1 end
        local visited = {}
        local function node(id, depth)
            if visited[id] or depth > 16 then return nil end
            visited[id] = true
            local known = spoilers or isOwned(save, id) or isSeen(save, id)
            local out = {
                known = known and true or false,
                current = id == sp,
                species = known and tostring(id) or nil,
                name = known and (try(Pokemon.name, id) or tostring(id)) or nil,
                icon = known and img("iconSpecies", id) or false,
                next = {}
            }
            for _, evo in ipairs(try(Pokemon.evolutions, id) or {}) do
                local child = targetOf(evo) and node(targetOf(evo), depth + 1)
                if child then out.next[#out.next + 1] = { how = howText(evo), node = child } end
            end
            return out
        end
        local tree = node(root, 0)
        return { family = tree, evolves = tree ~= nil and #tree.next > 0, eggGroups = eggGroups(sp),
            breeding = hidden and breedingHidden(sp) or nil }
    end

    function D.state(game, spoilers)
        if not refresh(game, spoilers) then return nil end
        return D.summary
    end

    function D.body(game, spoilers)
        local _, body = refresh(game, spoilers)
        return body
    end

    -- for area3.lua: may the player look at this species?
    D.access = access

    return D
end
