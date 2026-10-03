-- The POKéDEX tab: SEEN / OWN counts and one entry per dex number, counted
-- the way PokedexMenu does (an owned species also counts as seen). Read-only.
--
-- The dex is as long as constants.dexSize, which the engine derives from the
-- merged roster, so species added by other mods show up like in the game's
-- own POKéDEX. Species the player has never seen carry only their number,
-- unless the SPOILERS option is on.
--
-- The full list is big and rarely changes, so /state only carries a cheap
-- version stamp and the page downloads /dex when that changes. Change is
-- detected, not announced: battles, catches, evolutions, trades, gift
-- scripts, save loads and other mods all write the dex, and a signature
-- check each poll notices every one of them.
--
-- Gen 2 (Gold) keeps its entries apart (data.gen2Pokedex.entries: kind,
-- height as feet * 100 + inches, weight in tenths of a pound, two text
-- pages) and calls owned "caught"; it also has the Johto (NEW POKéDEX)
-- order, sent as each entry's `jn` so the page can sort by it.
return function(mod, sprites, Json, platform)
    local D = {}

    -- a new game session must never match a page's version from the last one
    local session = ("%x"):format(os.time() % 0x1000000)
    local counter, lastSig = 0, nil
    local cachedBody, cachedVersion

    -- dex number -> species; rebuilt on every list build (rare), so species
    -- a mod adds or renumbers are always picked up
    local function byDex(pokemon)
        local out = {}
        for _, def in pairs(pokemon) do
            if type(def) == "table" and def.dex then out[def.dex] = def end
        end
        return out
    end

    -- Data:seedDefaults' own rule when a dataset leaves dexSize out
    local function dexSize(data)
        local constants = data.constants or {}
        if constants.dexSize then return constants.dexSize end
        local highest = 0
        for n in pairs(byDex(data.pokemon or {})) do
            if n > highest then highest = n end
        end
        return highest
    end

    local function count(set)
        local n = 0
        for _, v in pairs(set or {}) do
            if v then n = n + 1 end
        end
        return n
    end

    local function icon(data, species)
        if not (sprites and sprites.icon) then return false end
        local ok, id = pcall(sprites.icon, data, { species = species })
        return ok and id and ("/img/" .. id .. ".png") or false
    end

    -- Everything the list depends on, cheap enough for every poll: the
    -- tables themselves (a loaded save or reloaded data swaps them), how many
    -- marks they hold, the dex bounds, SPOILERS and the icons' palette.
    local function signature(game, spoilers)
        local data = game.data
        local seenSet, ownedSet = platform.seenSet(game.save), platform.ownedSet(game.save)
        local constants = data.constants or {}
        local look = sprites and sprites.iconLook and sprites.iconLook(data) or ""
        return table.concat({
            tostring(seenSet), tostring(ownedSet), tostring(data.pokemon),
            count(seenSet), count(ownedSet), dexSize(data), constants.dexDigits or 3,
            spoilers and 1 or 0, look
        }, "|")
    end

    -- A species' entry in the Gen 1 shape (kind, heightFt / heightIn,
    -- weight in tenths of a pound, text pages): Gen 1 keeps it on the
    -- species, Gold in gen2Pokedex with the height packed as ft * 100 + in.
    -- Gold's entry comes first, as its POKéDEX reads only that one: a mod
    -- may also put a partial def.dexEntry on the species (a language mod
    -- adds height / weight only), which must not hide the text.
    local function dexEntryOf(data, def)
        local entries = data.gen2Pokedex and data.gen2Pokedex.entries
        local e = entries and entries[def.id]
        if not e then return def.dexEntry or {} end
        local h = tonumber(e.height)
        return {
            kind = e.kind,
            heightFt = h and math.floor(h / 100) or nil,
            heightIn = h and (h % 100) or nil,
            weight = tonumber(e.weight),
            -- metric numbers, should a mod add them (Gold has no metric screen)
            heightM = tonumber(e.heightM),
            weightKg = tonumber(e.weightKg),
            pages = { e.text, e.text2 }
        }
    end

    -- Johto (NEW POKéDEX) numbers: species -> 1..n, when the data has the order
    local function johtoNumbers(data)
        local order = data.gen2Pokedex and data.gen2Pokedex.newOrder
        if type(order) ~= "table" then return nil end
        local out = {}
        for i, species in ipairs(order) do out[species] = i end
        return out
    end

    -- "PSYCHIC_TYPE" -> "PSYCHIC" (the name the type chart lists)
    local function typeName(data, typeId)
        local chart = data.type_chart
        local record = chart and chart.types and chart.types[typeId]
        if type(record) == "table" and record.name then return record.name end
        return (tostring(typeId):gsub("_TYPE$", ""))
    end

    local function typesOf(data, def)
        local out, dup = {}, {}
        for _, typeId in ipairs(def.types or {}) do
            local name = typeName(data, typeId)
            -- single-typed species list their type twice
            if not dup[name] then
                dup[name] = true
                out[#out + 1] = name
            end
        end
        return out
    end

    -- the game's own type order (the type chart's name list); types only a
    -- mod knows follow alphabetically
    local function typeOrder(data, list)
        local order, have = {}, {}
        local chart = data.type_chart
        for _, name in ipairs(chart and chart.names or {}) do
            if not have[name] then
                have[name] = true
                order[#order + 1] = name
            end
        end
        local extra = {}
        for _, e in ipairs(list) do
            for _, name in ipairs(e.types or {}) do
                if not have[name] then
                    have[name] = true
                    extra[#extra + 1] = name
                end
            end
        end
        table.sort(extra)
        for _, name in ipairs(extra) do order[#order + 1] = name end
        return order
    end

    -- A metric line as DexEntryMenu prints it ("GR. %.1fm", decimal comma),
    -- split into its label and value: "GR. 0,7m" -> "GR.", "0,7m"
    local function metricLine(source, value)
        local text = platform.format(source, value)
        text = text:gsub("(%d)%.(%d)", "%1,%2")
        local label, rest = text:match("^(.-)%s*(%d.*)$")
        if not label then return "", text end
        return label, rest
    end

    -- Height / weight as the entry page prints them, with its labels:
    -- metric (DexEntryMenu's GR. / GEW. lines) when the entry carries metric
    -- numbers, as a language mod may add them; else feet+inches and pounds
    -- (tenths) under HT / WT. entry.height / entry.weight are for sorting,
    -- in metres and kilograms either way, so a mix still sorts right.
    local function measures(entry, dexEntry)
        local e = dexEntry or {}
        if e.heightM then
            entry.height = e.heightM
            entry.weight = e.weightKg or 0
            entry.heightLabel, entry.heightText = metricLine("GR. %.1fm", e.heightM)
            entry.weightLabel, entry.weightText = metricLine("GEW. %.1fkg", e.weightKg or 0)
        elseif e.heightFt then
            entry.height = (e.heightFt * 12 + (e.heightIn or 0)) * 0.0254
            entry.heightText = ("%d'%02d\""):format(e.heightFt, e.heightIn or 0)
            local lb = (e.weight or 0) / 10
            entry.weight = lb * 0.45359237
            -- whole pounds past 100 so the text fits a grid cell
            local unit = platform.text("lb")
            entry.weightText = lb >= 100 and ("%d"):format(math.floor(lb + 0.5)) .. unit
                or ("%.1f"):format(lb) .. unit
        end
    end

    -- the entry page's labels and unknown values, metric or not
    local function measureLabels(out, dexEntry)
        if dexEntry and dexEntry.heightM then
            out.heightLabel = out.heightLabel or (metricLine("GR. %.1fm", 0))
            out.weightLabel = out.weightLabel or (metricLine("GEW. %.1fkg", 0))
            out.metric = true
        else
            out.heightLabel, out.weightLabel = platform.text("HT"), platform.text("WT")
            out.poundLabel = platform.text("lb")
        end
    end

    -- The base-stat sorts: each species' base stats and their total, keyed
    -- the same in every generation (hp, atk, def, spa, spd, spe; Gen 1's
    -- one SPECIAL is spc), and the list of keys this game has, in the
    -- summary screen's order, for the page's chips
    local BASE_KEYS_GEN1 = { { "hp", "hp", "HP" }, { "atk", "attack", "ATTACK" }, { "def", "defense", "DEFENSE" },
        { "spe", "speed", "SPEED" }, { "spc", "special", "SPECIAL" } }
    local BASE_KEYS_GEN2 = { { "hp", "hp", "HP" }, { "atk", "attack", "ATTACK" }, { "def", "defense", "DEFENSE" },
        { "spa", "specialAttack", "SP.ATK" }, { "spd", "specialDefense", "SP.DEF" }, { "spe", "speed", "SPEED" } }

    local function baseKeys(defs)
        for _, def in pairs(defs) do
            local b = type(def.baseStats) == "table" and def.baseStats
            if b then return b.specialAttack and BASE_KEYS_GEN2 or BASE_KEYS_GEN1 end
        end
        return BASE_KEYS_GEN1
    end

    local function baseOf(def, keys)
        local b = type(def.baseStats) == "table" and def.baseStats
        if not b then return nil end
        local out, total = {}, 0
        for _, k in ipairs(keys) do
            local v = tonumber(b[k[2]])
            if v then
                out[k[1]] = v
                total = total + v
            end
        end
        out.total = total
        return out
    end

    local function statChips(keys)
        local out = {}
        for _, k in ipairs(keys) do out[#out + 1] = { k[1], k[3] } end
        return out
    end

    local function build(game, spoilers)
        local data, save = game.data, game.save
        local seenSet, ownedSet = platform.seenSet(save), platform.ownedSet(save)
        local size = dexSize(data)
        local numFmt = ("%%0%dd"):format((data.constants or {}).dexDigits or 3)
        local defs = byDex(data.pokemon or {})
        local johto = johtoNumbers(data)
        local keys = baseKeys(defs)
        local list, seen, owned = {}, 0, 0
        for n = 1, size do
            local def = defs[n]
            if def then
                local isOwned = ownedSet[def.id] and true or false
                local isSeen = isOwned or (seenSet[def.id] and true or false)
                if isOwned then owned = owned + 1 end
                if isSeen then seen = seen + 1 end
                local known = isSeen or spoilers
                local entry = {
                    n = n,
                    num = numFmt:format(n),
                    species = known and tostring(def.id) or false,
                    name = known and (def.name or tostring(def.id)) or false,
                    icon = known and icon(data, def.id) or false,
                    types = known and typesOf(data, def) or false,
                    seen = isSeen,
                    owned = isOwned,
                    jn = johto and johto[def.id] or nil
                }
                -- the in-game entry shows HT / WT for owned species only
                if isOwned or spoilers then
                    measures(entry, dexEntryOf(data, def))
                    -- base stats, for the base-stat sorts: known like HT / WT
                    entry.base = baseOf(def, keys)
                end
                list[#list + 1] = entry
            end
        end
        return { seen = seen, owned = owned, size = size, list = list, johto = johto ~= nil,
            typeOrder = typeOrder(data, list), spoilers = spoilers and true or false,
            stats = statChips(keys) }
    end

    -- Rebuilds only when the signature moved; returns the version and body.
    local function refresh(game, spoilers)
        if not (game and game.data and game.save) then return nil end
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

    -- The description as DexEntryMenu's descPages reads it: pages split by
    -- \f, lines by \n (or \v), and a "." after the last page. The pages only
    -- exist because the Game Boy screen fits one at a time, so on the phone
    -- they run together as one paragraph.
    local function description(data, dexEntry)
        local chunks = {}
        if dexEntry and dexEntry.pages then
            -- Gold: two pages, lines joined by <NEXT> (and the like)
            for _, page in ipairs(dexEntry.pages) do
                if type(page) == "string" then chunks[#chunks + 1] = (page:gsub("<%u+>", " ")) end
            end
        else
            local key = dexEntry and dexEntry.text
            local text = key and data.text and data.text[key]
            if type(text) ~= "string" then return false end
            for chunk in (text .. "\f"):gmatch("(.-)\f") do chunks[#chunks + 1] = chunk end
        end
        local pages = {}
        for _, chunk in ipairs(chunks) do
            local words = chunk:gsub("[\n\v]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("@$", "")
            if words ~= "" then pages[#pages + 1] = words end
        end
        if #pages == 0 then return false end
        local text = table.concat(pages, " ")
        -- a hyphenated word the screen broke after its hyphen ("hot-" /
        -- "headed") is one word again, hyphen kept: "hot-headed"
        text = text:gsub("(%a)%-%s+(%a)", "%1-%2")
        -- Gen 1's entry screen prints a full stop after the last page
        -- (DexEntryMenu descPages); Gold's text carries its own
        if not (dexEntry and dexEntry.pages) or not text:find("[%.!?]$") then text = text .. "." end
        return { text }
    end

    ---- SHOW HIDDEN VALUES ----------------------------------------------------

    -- base stats in the summary screen's order; Gen 2 splits SPECIAL
    local BASE_GEN1 = { { "hp", "HP" }, { "attack", "ATTACK" }, { "defense", "DEFENSE" },
        { "speed", "SPEED" }, { "special", "SPECIAL" } }
    local BASE_GEN2 = { { "hp", "HP" }, { "attack", "ATTACK" }, { "defense", "DEFENSE" },
        { "specialAttack", "SPCL.ATK" }, { "specialDefense", "SPCL.DEF" }, { "speed", "SPEED" } }

    -- The species' own numbers, the ones no screen in the game shows
    local function speciesHidden(def)
        local base = type(def.baseStats) == "table" and def.baseStats or {}
        local stats = {}
        for _, s in ipairs(base.specialAttack and BASE_GEN2 or BASE_GEN1) do
            if base[s[1]] then stats[#stats + 1] = { label = s[2], value = base[s[1]] } end
        end
        local growth = def.growthRate and tostring(def.growthRate):gsub("^GROWTH_", ""):gsub("_", " ")
        return {
            baseStats = stats,
            catchRate = tonumber(def.catchRate),
            baseExp = tonumber(def.baseExp),
            growth = growth or nil
        }
    end

    -- Gen 2 breeding numbers (nil on Gen 1):
    --   gender  BASE_GENDER as shares: GetGender makes a mon female when its
    --           Attack/Speed DV byte is under the ratio, so a ratio of 31
    --           means (31 + 1) / 256 = 12.5 % female; 0 / 254 / 255 are the
    --           all-male, all-female and genderless markers
    --   hatchSteps  BASE_EGG_STEPS counts 256-step cycles (Breeding.STEP_CYCLE)
    local function breedingHidden(def)
        local out, any = {}, false
        local ratio = tonumber(def.genderRatio)
        if ratio then
            any = true
            if ratio >= 255 then
                out.gender = { none = true }
            elseif ratio == 0 then
                out.gender = { male = 100, female = 0 }
            elseif ratio >= 254 then
                out.gender = { male = 0, female = 100 }
            else
                local female = (ratio + 1) / 256 * 100
                out.gender = { male = 100 - female, female = female }
            end
        end
        local cycles = tonumber(def.eggSteps)
        if cycles then
            any = true
            out.hatchSteps = cycles * 256
        end
        return any and out or nil
    end

    -- GET /dex/entry: one species' POKéDEX page. Caught: everything the
    -- in-game entry shows. Seen, or unseen with SPOILERS: the limited Gen 1
    -- page (no description; HT / WT only with SPOILERS, as in the list).
    -- Returns nil for species the player may not look at.
    function D.entry(game, species, spoilers, hidden)
        local data, save = game.data, game.save
        if not (data and save) or type(species) ~= "string" then return nil end
        local def = data.pokemon and data.pokemon[species]
        if type(def) ~= "table" or not def.dex then return nil end
        local owned = platform.ownedSet(save)[def.id] and true or false
        local seen = owned or (platform.seenSet(save)[def.id] and true or false)
        if not (seen or spoilers) then return nil end
        local e = dexEntryOf(data, def)
        local out = {
            species = tostring(def.id),
            num = ("%%0%dd"):format((data.constants or {}).dexDigits or 3):format(def.dex),
            name = def.name or tostring(def.id),
            kind = e.kind or false,
            types = typesOf(data, def),
            front = false,
            owned = owned,
            seen = seen,
            full = owned,
            heightText = false,
            weightText = false,
            text = owned and description(data, e) or false
        }
        if sprites and sprites.front then
            local ok, id = pcall(sprites.front, data, { species = def.id })
            out.front = ok and id and ("/img/" .. id .. ".png") or false
            -- Crystal: the animation, played when the entry opens
            if sprites.frontAnim then
                local okA, anim = pcall(sprites.frontAnim, data, { species = def.id })
                out.anim = okA and anim and ("/anim/" .. anim) or false
            end
        end
        if owned or spoilers then measures(out, e) end
        measureLabels(out, e)
        -- SHOW HIDDEN VALUES, for what the entry shows in full
        if hidden and (owned or spoilers) then out.hidden = speciesHidden(def) end
        -- Gen 2: the footprint the entry shows beside the picture
        if sprites and sprites.footprintPath then
            local okF, fp = pcall(sprites.footprintPath, data, def.id)
            out.footprint = okF and fp or nil
        end
        -- only the texts go to the page
        out.height, out.weight = nil, nil
        return out
    end

    ---- EVO and MOVES pages ------------------------------------------------

    -- The pages' shared gate, D.entry's rule with the description's limit:
    -- nil when the player may not look at the species at all, "locked" when
    -- it is seen but not caught (without SPOILERS), else its def.
    local function pageDef(game, species, spoilers)
        local data, save = game.data, game.save
        if not (data and save) or type(species) ~= "string" then return nil end
        local def = data.pokemon and data.pokemon[species]
        if type(def) ~= "table" or not def.dex then return nil end
        local owned = platform.ownedSet(save)[def.id] and true or false
        local seen = owned or (platform.seenSet(save)[def.id] and true or false)
        if not (seen or spoilers) then return nil end
        if not (owned or spoilers) then return "locked" end
        return def
    end

    local function moveName(data, id)
        local mdef = data.moves and data.moves[id]
        return type(mdef) == "table" and mdef.name or (tostring(id):gsub("_", " "))
    end

    -- move -> { kind = "TM" | "HM", number } over the game's machine items:
    -- Gen 1's def.machine { kind, number, move }, Gold's def.teaches with its
    -- tmNumber / tmLabel (an HM_ id is an HM). Rebuilt when the items table
    -- is swapped (a reload, a mod).
    local machineIndex, machineFor
    local function machinesByMove(data)
        if machineFor == data.items and machineIndex then return machineIndex end
        local out = {}
        for id, def in pairs(data.items or {}) do
            if type(def) == "table" then
                if type(def.machine) == "table" and def.machine.move then
                    out[def.machine.move] = { kind = def.machine.kind or "TM", number = tonumber(def.machine.number) or 0 }
                elseif def.teaches then
                    local hm = tostring(id):sub(1, 3) == "HM_"
                    local n = tonumber(def.tmNumber)
                        or tonumber(tostring(def.tmLabel or def.name or id):match("(%d+)")) or 0
                    -- Gold numbers HMs after the 50 TMs; the label counts from 1
                    if hm and n > 50 then n = n - 50 end
                    out[def.teaches] = { kind = hm and "HM" or "TM", number = n }
                end
            end
        end
        machineIndex, machineFor = out, data.items
        return out
    end

    -- The TMs and HMs a species can learn ("TM06 TOXIC"), by number with
    -- the HMs after the TMs; Crystal's move tutor moves last ("TUTOR ...")
    local function machineList(data, def)
        local index = machinesByMove(data)
        local rows = {}
        for _, move in ipairs(def.tmhm or {}) do
            local m = index[move]
            if m then
                rows[#rows + 1] = { order = (m.kind == "HM" and 1000 or 0) + m.number,
                    text = ("%s%02d %s"):format(m.kind, m.number, moveName(data, move)) }
            else
                rows[#rows + 1] = { order = 2000, text = "TUTOR " .. moveName(data, move) }
            end
        end
        for _, move in ipairs(def.tutorMoves or {}) do
            rows[#rows + 1] = { order = 2000, text = "TUTOR " .. moveName(data, move) }
        end
        table.sort(rows, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.text < b.text
        end)
        local out = {}
        for _, r in ipairs(rows) do out[#out + 1] = r.text end
        return #out > 0 and out or nil
    end

    -- GET /dex/moves: the level-up moves, as the species learns them. Gen 1
    -- keeps its level-1 moves apart (level1Moves) and the rest in learnset;
    -- Gold's levelMoves holds both.
    function D.moves(game, species, spoilers)
        local def = pageDef(game, species, spoilers)
        if def == nil then return nil end
        if def == "locked" then return { locked = true } end
        local data, out = game.data, {}
        for _, id in ipairs(def.level1Moves or {}) do
            out[#out + 1] = { level = 1, name = moveName(data, id) }
        end
        for _, row in ipairs(def.learnset or def.levelMoves or {}) do
            if type(row) == "table" and row.move then
                out[#out + 1] = { level = tonumber(row.level) or 1, name = moveName(data, row.move) }
            end
        end
        -- Gen 2: the moves it can only get from a parent, as an EGG
        local eggMoves
        if type(def.eggMoves) == "table" then
            eggMoves = {}
            for _, id in ipairs(def.eggMoves) do eggMoves[#eggMoves + 1] = moveName(data, id) end
        end
        return { moves = out, eggMoves = eggMoves, machines = machineList(data, def) }
    end

    -- Gen 2's egg groups (BASE_EGG_GROUPS) by the names the games print
    -- in later generations; the ids stand for themselves otherwise
    local EGG_GROUP_NAMES = {
        EGG_MONSTER = "MONSTER", EGG_WATER_1 = "WATER 1", EGG_BUG = "BUG",
        EGG_FLYING = "FLYING", EGG_GROUND = "FIELD", EGG_FAIRY = "FAIRY",
        EGG_PLANT = "GRASS", EGG_HUMANSHAPE = "HUMAN-LIKE", EGG_WATER_3 = "WATER 3",
        EGG_MINERAL = "MINERAL", EGG_INDETERMINATE = "AMORPHOUS", EGG_WATER_2 = "WATER 2",
        EGG_DITTO = "DITTO", EGG_DRAGON = "DRAGON", EGG_NONE = "NO EGGS",
    }

    -- nil on Gen 1 (no breeding); one name when both groups are the same
    local function eggGroups(def)
        if type(def.eggGroups) ~= "table" then return nil end
        local out, dup = {}, {}
        for _, id in ipairs(def.eggGroups) do
            local name = EGG_GROUP_NAMES[id] or tostring(id):gsub("^EGG_", ""):gsub("_", " ")
            if not dup[name] then
                dup[name] = true
                out[#out + 1] = name
            end
        end
        return #out > 0 and out or nil
    end

    local STAT_TEXT = { ATK_GT_DEF = "ATK>DEF", ATK_LT_DEF = "ATK<DEF", ATK_EQ_DEF = "ATK=DEF" }

    local function itemName(data, id)
        local def = data.items and data.items[id]
        return type(def) == "table" and def.name or (tostring(id):gsub("_", " "))
    end

    -- An evolution row's condition, in a few words. The methods both
    -- generations know are worded here; one a mod adds says itself through
    -- its record's describe (Gen 1's method records carry one).
    local function howText(data, evo)
        local method = tostring(evo.method or ""):gsub("^EVOLVE_", "")
        local level = tonumber(evo.level)
        if method == "LEVEL" then
            return "Lv." .. (level or "?")
        elseif method == "ITEM" then
            return itemName(data, evo.item)
        elseif method == "TRADE" then
            return evo.item and ("TRADE · " .. itemName(data, evo.item)) or "TRADE"
        elseif method == "HAPPINESS" then
            if evo.time == "MORNDAY" then
                return "HAPPINESS · " .. platform.daytimeLabel("MORN") .. "/" .. platform.daytimeLabel("DAY")
            elseif evo.time == "NITE" then
                return "HAPPINESS · " .. platform.daytimeLabel("NITE")
            end
            return "HAPPINESS"
        elseif method == "STAT" then
            local cmp = STAT_TEXT[evo.comparison]
            return "Lv." .. (level or "?") .. (cmp and (" · " .. cmp) or "")
        end
        local methods = data.evolution_methods or data.gen2EvolutionMethods
        local record = type(methods) == "table" and methods[evo.method]
        if type(record) == "table" and type(record.describe) == "function" then
            local ok, text = pcall(record.describe, evo, data)
            if ok and type(text) == "string" and text ~= "" then return text end
        end
        return (method:gsub("_", " "))
    end

    local function targetOf(evo)
        return type(evo) == "table" and (evo.species or evo.into) or nil
    end

    -- GET /dex/evo: the whole family around the species, from its first
    -- stage down, every branch included. A family member the player has not
    -- seen (without SPOILERS) keeps its place and method, but not its name,
    -- picture or id.
    function D.family(game, species, spoilers, hidden)
        local def = pageDef(game, species, spoilers)
        if def == nil then return nil end
        if def == "locked" then return { locked = true } end
        local data, save = game.data, game.save
        local seenSet, ownedSet = platform.seenSet(save), platform.ownedSet(save)
        -- target species -> the species it evolves from
        local pre = {}
        for id, d in pairs(data.pokemon) do
            if type(d) == "table" then
                for _, evo in ipairs(d.evolutions or {}) do
                    local to = targetOf(evo)
                    if to and pre[to] == nil then pre[to] = d.id or id end
                end
            end
        end
        local root, guard = def.id, 0
        while pre[root] and guard < 16 do
            root, guard = pre[root], guard + 1
        end
        local visited = {}
        local function node(id, depth)
            local d = data.pokemon[id]
            if type(d) ~= "table" or visited[id] or depth > 16 then return nil end
            visited[id] = true
            local known = spoilers or ownedSet[id] or seenSet[id]
            local out = {
                known = known and true or false,
                current = id == def.id,
                species = known and tostring(id) or nil,
                name = known and (d.name or tostring(id)) or nil,
                icon = known and icon(data, id) or false,
                next = {}
            }
            for _, evo in ipairs(d.evolutions or {}) do
                local child = targetOf(evo) and node(targetOf(evo), depth + 1)
                if child then out.next[#out.next + 1] = { how = howText(data, evo), node = child } end
            end
            return out
        end
        local tree = node(root, 0)
        return { family = tree, evolves = tree ~= nil and #tree.next > 0, eggGroups = eggGroups(def),
            breeding = hidden and breedingHidden(def) or nil }
    end

    -- for /state: { version, seen, owned }, or nil before a save is loaded
    function D.state(game, spoilers)
        if not refresh(game, spoilers) then return nil end
        return D.summary
    end

    -- GET /dex: the whole list as JSON
    function D.body(game, spoilers)
        local _, body = refresh(game, spoilers)
        return body
    end

    return D
end
