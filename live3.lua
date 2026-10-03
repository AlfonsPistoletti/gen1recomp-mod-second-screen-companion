-- Gen 3 (FireRed / LeafGreen) LIVE tab: where the player is, what can be
-- found there, and the battle on screen. Same output as live.lua, built
-- from the game3 engine: the place name is the region map section's
-- (region_map.c GetMapName), the DexNav reads the ROM's wild tables
-- (land / water / Rock Smash / the three rods, with pret's slot weights)
-- and the battle comes from the game3 battle state.
return function(mod, sprites, platform)
    local Pokemon = require("src.core.game3.pokemon")
    local ItemsData = require("src.core.game3.items_data")

    local L = {}

    local function try(fn, ...)
        local ok, a = pcall(fn, ...)
        if ok then return a end
        return nil
    end

    local function art(kind, mon)
        if not (sprites and sprites[kind]) then return false end
        local id = try(sprites[kind], nil, mon)
        return id and ("/img/" .. id .. ".png") or false
    end

    ---- location -----------------------------------------------------------

    local function mapDef(game, mapId)
        local maps = game and game.data and game.data.maps
        return maps and maps[mapId] or nil
    end

    function L.locationName(game, mapId)
        local def = mapDef(game, mapId)
        local sec = def and def.regionMapSectionId
        if platform.isRse(game) then
            -- Emerald's sections (Hoenn's 0-87) are named by its own region
            -- map data (src/ui/game3/rse/mapsec.lua, as its POKéNAV and map
            -- popup name them); buildings carry their town's section
            local okM, Mapsec = pcall(require, "src.ui.game3.rse.mapsec")
            local name = okM and sec and try(Mapsec.name, sec)
            if type(name) == "string" and name ~= "" then return name end
        else
            local okS, Sections = pcall(require, "src.import.gba.map_sections_extract")
            if okS and Sections.getPlaceName then
                local name = try(Sections.getPlaceName, mapId, sec)
                if type(name) == "string" and name ~= "" then return name end
            end
        end
        return (tostring(mapId):gsub("^FR_", ""):gsub("^EM_", ""):gsub("_", " "))
    end

    -- FireRed / LeafGreen: the place's location preview artwork (the full
    -- screen picture shown on entering MT. MOON, VIRIDIAN FOREST ...), as
    -- the HANDS-OFF screen's backdrop while the player is there; the same
    -- map section -> artwork table the preview screen uses
    -- (map_preview_screen.lua artworkFor). false elsewhere and on Emerald.
    function L.backdrop(game, mapId)
        if platform.isRse(game) or not (sprites and sprites.mapPreview) then return false end
        local def = mapDef(game, mapId)
        local sec = def and def.regionMapSectionId
        if not sec then return false end
        local okP, Preview = pcall(require, "src.ui.game3.map_preview_screen")
        local artwork = okP and Preview.artworkFor and try(Preview.artworkFor, sec)
        if not artwork then return false end
        local id = try(sprites.mapPreview, artwork)
        return id and ("/img/" .. id .. ".png") or false
    end

    ---- DexNav -------------------------------------------------------------

    -- pokefirered/src/wild_encounter.c slot weights (percent of the roll)
    local LAND_WEIGHTS = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
    local WATER_WEIGHTS = { 60, 30, 5, 4, 1 }
    -- the fishing table's 10 slots, split by rod (wild_encounter.c:117)
    local RODS = {
        { item = 262, kind = "OLD_ROD", first = 1, weights = { 70, 30 } },
        { item = 263, kind = "GOOD_ROD", first = 3, weights = { 60, 20, 20 } },
        { item = 264, kind = "SUPER_ROD", first = 6, weights = { 40, 40, 15, 4, 1 } },
    }

    local function encounters()
        local ok, E = pcall(require, "src.core.game3.encounters")
        return ok and E or nil
    end

    local function dexEntry(save, species, share, minL, maxL, spoilers)
        local seenSet, ownedSet = platform.seenSet(save), platform.ownedSet(save)
        local seen = seenSet[species] and true or false
        local owned = ownedSet[species] and true or false
        local known = spoilers or seen or owned
        return {
            species = known and tostring(species) or false,
            name = known and (try(Pokemon.name, species) or tostring(species)) or false,
            icon = known and art("icon", { species = species, speciesNumbering = "internal" }) or false,
            minL = minL or false,
            maxL = maxL or false,
            chance = share,
            seen = seen,
            owned = owned
        }
    end

    local function sortList(list)
        table.sort(list, function(a, b)
            if a.chance ~= b.chance then return a.chance > b.chance end
            return (a.minL or 0) < (b.minL or 0)
        end)
        return list
    end

    -- one section: slots[first .. first + #weights - 1] with their weights
    local function section(save, slots, first, weights, kind, label, rate, spoilers)
        if type(slots) ~= "table" or #slots == 0 then return nil end
        local share, ranges, order = {}, {}, {}
        local total = 0
        for i, w in ipairs(weights) do
            local slot = slots[first + i - 1]
            local sp = type(slot) == "table" and tonumber(slot.species or slot[1])
            if sp and sp > 0 then
                if not share[sp] then order[#order + 1] = sp end
                share[sp] = (share[sp] or 0) + w
                total = total + w
                local lo = tonumber(slot.minLevel or slot.level) or 0
                local hi = tonumber(slot.maxLevel or slot.level) or lo
                local r = ranges[sp]
                if r then r.min, r.max = math.min(r.min, lo), math.max(r.max, hi)
                else ranges[sp] = { min = lo, max = hi } end
            end
        end
        if total <= 0 then return nil end
        local list = {}
        for _, sp in ipairs(order) do
            local r = ranges[sp]
            list[#list + 1] = dexEntry(save, sp, share[sp] / total, r.min, r.max, spoilers)
        end
        return { kind = kind, label = label, rate = rate or false, list = sortList(list) }
    end

    local function slotsOf(area)
        if type(area) ~= "table" then return nil, 0 end
        local slots = area.slots or area.mons or (#area > 0 and area) or nil
        return slots, tonumber(area.rate) or 0
    end

    -- the player's rods (KEY_ITEMS pocket), read without touching the bag
    local function hasItem(save, id)
        local pockets = save and save.bag and save.bag.pockets or {}
        for _, slots in pairs(pockets) do
            for _, slot in ipairs(type(slots) == "table" and slots or {}) do
                if tonumber(slot.id) == id and (tonumber(slot.qty) or 0) > 0 then return true end
            end
        end
        return false
    end

    -- allRods: every rod, owned or not (the POKéDEX AREA list)
    local function dexnav(game, mapId, spoilers, allRods)
        local E = encounters()
        if not (E and E.tableFor) then return {} end
        local t = try(E.tableFor, mapId)
        if type(t) ~= "table" then return {} end
        local save = platform.save(game)
        local out = {}
        -- a cave's land table covers every tile, not just grass
        local def = mapDef(game, mapId) or {}
        -- MAP_TYPE_UNDERGROUND (pokefirered/include/constants/map_types.h)
        local cave = tonumber(def.mapType) == 4 or tostring(def.mapType or ""):find("UNDERGROUND") ~= nil
        local land, landRate = slotsOf(t.land or t.grass)
        out[#out + 1] = section(save, land, 1, LAND_WEIGHTS, cave and "cave" or "grass",
            cave and "CAVE" or "GRASS", math.min(landRate * 16, 2880) / 2880, spoilers)
        local water, waterRate = slotsOf(t.water)
        out[#out + 1] = section(save, water, 1, WATER_WEIGHTS, "surf", "SURF",
            math.min(waterRate * 16, 2880) / 2880, spoilers)
        local rocks, rockRate = slotsOf(t.rocks)
        out[#out + 1] = section(save, rocks, 1, WATER_WEIGHTS, "rock", "ROCK SMASH",
            math.min(rockRate * 16, 2880) / 2880, spoilers)
        local fish = slotsOf(t.fishing)
        if fish then
            for _, rod in ipairs(RODS) do
                if allRods or hasItem(save, rod.item) then
                    local label = try(ItemsData.displayName, rod.item) or rod.kind:gsub("_", " ")
                    out[#out + 1] = section(save, fish, rod.first, rod.weights, rod.kind, label, false, spoilers)
                end
            end
        end
        return out
    end

    -- The roaming legendary (RAIKOU / ENTEI / SUICUNE after the NATIONAL
    -- DEX; roamer.lua): the save's roamer while it is out there (active,
    -- not fainted), read as it is, never through Roamer's own setters
    function L.roamer(game)
        local session = platform.save(game)
        local r = session and session.roamer
        if type(r) ~= "table" or not r.active or not tonumber(r.species) then return nil end
        if tonumber(r.hp) and tonumber(r.hp) <= 0 then return nil end
        return r
    end

    -- is the roamer on this map? The same test as Roamer.tryEncounter:
    -- both ids through Roamer.normalizeMapId
    function L.roamerOn(game, mapId)
        local r = L.roamer(game)
        if not (r and r.map and mapId) then return nil end
        -- Emerald (LATIAS / LATIOS) matches the map ids as they are
        -- (roamer.lua try_encounter_rse: r.map == mapId)
        if platform.isRse(game) then return tostring(r.map) == tostring(mapId) and r or nil end
        local ok, Roamer = pcall(require, "src.core.game3.roamer")
        if not (ok and Roamer.normalizeMapId) then return nil end
        local okA, a = pcall(Roamer.normalizeMapId, tostring(mapId))
        local okB, b = pcall(Roamer.normalizeMapId, tostring(r.map))
        return okA and okB and a ~= nil and a == b and r or nil
    end

    -- Every wild section of one map, for the POKéDEX AREA list
    function L.mapSections(game, mapId)
        return dexnav(game, mapId, true, true)
    end

    ---- battle -------------------------------------------------------------

    local STATUS = { [1] = "PSN", [2] = "PAR", [3] = "SLP", [4] = "FRZ", [5] = "BRN" }

    -- moves seen per foe mon (weak keys: battles end, their mons go away)
    local knownMoves = setmetatable({}, { __mode = "k" })
    -- Gen 3: the same by the foe's team slot, per battle
    local knownBySlot = setmetatable({}, { __mode = "k" })
    local sentOut = setmetatable({}, { __mode = "k" })

    local function battleState()
        -- mods have no package table: require hands over the engine's own
        -- (already loaded) module
        local B = try(require, "src.core.game3.battle")
        if not (B and B.isActive and try(B.isActive)) then return nil end
        return B.getState and try(B.getState) or nil
    end

    local function statusOf(mon)
        local SummaryData = try(require, "src.core.game3.summary_data")
        if not SummaryData then return false end
        return STATUS[try(SummaryData.statusAilment, mon) or 0] or false
    end

    local function typeName(t)
        local Types = try(require, "src.core.game3.battle.types")
        if not Types then return false end
        local id = tonumber(t) or (Types.ID or {})[tostring(t):upper()]
        return id and try(Types.name, id) or false
    end

    -- known: the moves seen so far (default: those seen from this table)
    local function movesFor(mon, spoilers, known)
        known = known or knownMoves[mon] or {}
        local list = {}
        for slot = 1, 4 do
            local id = Pokemon.moveIdAt(mon, slot)
            if id and id > 0 and (spoilers or known[id]) then
                local row = try(Pokemon.battleMove, id) or {}
                list[#list + 1] = { name = try(Pokemon.moveName, id) or tostring(id), type = typeName(row.type) }
            end
        end
        return list
    end

    local function monInfo(mon)
        return {
            name = try(Pokemon.displayName, mon) or "?????",
            level = tonumber(mon.level) or 0,
            hp = tonumber(mon.hp) or 0,
            maxHp = tonumber(mon.maxHp) or 0,
            status = statusOf(mon)
        }
    end

    -- BattleState ball row: empty / fainted / statused / healthy
    local function ballFrame(mon)
        if not mon then return 3 end
        if (tonumber(mon.hp) or 0) <= 0 then return 2 end
        if statusOf(mon) then return 1 end
        return 0
    end

    -- A SAFARI ZONE battle (st.safariState, battle/rules.lua Rules.safari):
    -- the SAFARI BALL's catch chance (Catching.catchOdds with the safari
    -- catch factor, then the four shake checks: (b / 65536)^4, b =
    -- 1048560 / sqrt(sqrt(16711680 / odds))) and the flee chance
    -- (Rules.safari.fleeRate, the AI's roll under it out of 100). The foe
    -- decides to run as the turn is chosen, so this turn's chance is one
    -- for every choice ("RUNS NOW"); each row's flee is next turn's, after
    -- that choice and the end-of-turn tick (watchStep). BAIT halves the
    -- catch factor (at least 3) and keeps it eating; ROCK doubles it (at
    -- most 20) and keeps it angry.
    -- the chance one throw of a ball catches, from its catch odds
    -- (Catching.catchOdds) and the four shake checks
    local function oddsToChance(odds)
        odds = tonumber(odds)
        if not odds then return false end
        if odds >= 255 then return 1 end
        local b = math.floor(1048560 / math.sqrt(math.sqrt(16711680 / math.max(1, odds))))
        return (b / 65536) ^ 4
    end

    -- Emerald's SAFARI ZONE battle (pokeemerald battle_util.c, Rules.safari
    -- rse): no BAIT / ROCK and nothing wears off between turns. The foe runs
    -- with escape factor x 5 percent (decided as the turn starts: RUNS NOW
    -- for every choice); GO NEAR raises both the catch and the escape
    -- factor by the game's table for how close the player already is;
    -- a POKéBLOCK it likes lowers the escape factor (pkblToEscapeFactor; a
    -- disliked one less, the row shows the liked case). Each row: the next
    -- ball's catch chance and the next turn's flee after that choice.
    local function safariOddsRse(game, st, sf, Rules, Catching)
        local session = platform.save(game)
        local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
        local function catch(state)
            local view = setmetatable({ safariState = state }, { __index = st })
            local ok, odds = pcall(Catching.catchOdds, 5, st.enemy, view, session)
            return ok and oddsToChance(odds) or false
        end
        local function flee(state)
            local ok, rate = pcall(Rules.safari.fleeRate, state)
            return ok and tonumber(rate) and math.min(100, rate) / 100 or false
        end
        local okP, Profile = pcall(require, "src.core.game3.battle.profile")
        local cfg = okP and Profile.of and try(Profile.of, st)
        local tables = cfg and cfg.safari and try(Rules.safari.rseTables, cfg.safari)
        local near, block = copy(sf), copy(sf)
        if tables then
            pcall(Rules.safari.goNear, near, tables)
            pcall(Rules.safari.throwPokeblock, block, tables, 1)
        end
        local function label(key, fallback)
            local okT, RomText = pcall(require, "src.core.game3.rom_text")
            local t = okT and try(RomText.plain, key)
            return type(t) == "string" and t ~= "" and t:upper() or fallback
        end
        return {
            mood = false,
            fleeNow = flee(sf),
            fleeHead = "RUNS NEXT",
            rate = try(Rules.safari.ballCatchRate, sf) or false,
            rows = {
                { action = "BALL", catch = catch(sf), flee = flee(sf) },
                { action = "POKéBLOCK", catch = catch(block), flee = tables and flee(block) or false },
                { action = "GO NEAR", catch = tables and catch(near) or false, flee = tables and flee(near) or false },
            },
        }
    end

    local function safariOdds(game, st)
        local sf = st.safariState
        if type(sf) ~= "table" then return nil end
        local okR, Rules = pcall(require, "src.core.game3.battle.rules")
        local okC, Catching = pcall(require, "src.core.game3.battle.catching")
        if not (okR and okC and Rules.safari) then return nil end
        if sf.rse then return safariOddsRse(game, st, sf, Rules, Catching) end
        local session = platform.save(game)
        local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
        local function catch(state)
            local view = setmetatable({ safariState = state }, { __index = st })
            local ok, odds = pcall(Catching.catchOdds, 5, st.enemy, view, session)
            return ok and oddsToChance(odds) or false
        end
        local function fleeAfter(state)
            local s = copy(state)
            pcall(Rules.safari.watchStep, s)
            local ok, rate = pcall(Rules.safari.fleeRate, s)
            return ok and tonumber(rate) and math.min(100, rate) / 100 or false
        end
        local bait = copy(sf)
        bait.baitCounter = math.min(6, (tonumber(sf.baitCounter) or 0) + 2)
        bait.rockCounter = 0
        bait.catchFactor = math.max(3, math.floor((tonumber(sf.catchFactor) or 0) / 2))
        local rock = copy(sf)
        rock.rockCounter = math.min(6, (tonumber(sf.rockCounter) or 0) + 2)
        rock.baitCounter = 0
        rock.catchFactor = math.min(20, (tonumber(sf.catchFactor) or 0) * 2)
        local okN, now = pcall(Rules.safari.fleeRate, sf)
        local mood = (tonumber(sf.rockCounter) or 0) > 0 and "ANGRY"
            or (tonumber(sf.baitCounter) or 0) > 0 and "EATING" or false
        return {
            mood = mood,
            fleeNow = okN and tonumber(now) and math.min(100, now) / 100 or false,
            fleeHead = "RUNS NEXT",
            rate = try(Rules.safari.ballCatchRate, sf) or false,
            rows = {
                { action = "BALL", catch = catch(sf), flee = fleeAfter(sf) },
                { action = "BAIT", catch = catch(bait), flee = fleeAfter(bait) },
                { action = "ROCK", catch = catch(rock), flee = fleeAfter(rock) },
            },
        }
    end

    -- A wild battle's catch odds (SHOW HIDDEN VALUES): the species' catch
    -- rate and, for every ball in the POKé BALLS pocket, the chance it
    -- catches the foe as it is now (Catching.catchOdds: the ball's own
    -- bonus, HP and status)
    local function catchOdds(game, st)
        local okC, Catching = pcall(require, "src.core.game3.battle.catching")
        if not (okC and st.enemy) then return nil end
        local session = platform.save(game)
        local sp = try(Pokemon.speciesOf, st.enemy.mon)
        local meta = sp and try(Pokemon.speciesMeta, sp)
        local balls, seen = {}, {}
        local pocket = session and session.bag and session.bag.pockets and session.bag.pockets.POKE_BALLS or {}
        for _, slot in ipairs(pocket) do
            local id, qty = tonumber(slot.id), tonumber(slot.qty) or 0
            if id and qty > 0 then
                if seen[id] then seen[id].count = seen[id].count + qty
                else
                    local ok, odds = pcall(Catching.catchOdds, id, st.enemy, st, session)
                    local row = { name = try(ItemsData.displayName, id) or tostring(id), count = qty,
                        chance = ok and oddsToChance(odds) or false }
                    seen[id] = row
                    balls[#balls + 1] = row
                end
            end
        end
        return { rate = meta and tonumber(meta.catchRate) or false, balls = balls }
    end

    -- a battler's raised / lowered stats: the stages that aren't 0, by the
    -- engine's own names (the page shows them as ATK×0.66 and so on)
    local function stagesOf(t)
        if type(t) ~= "table" then return false end
        local out, any = {}, false
        for k, v in pairs(t) do
            v = tonumber(v)
            if type(k) == "string" and v and v ~= 0 then out[k] = v any = true end
        end
        return any and out or false
    end

    -- multi-turn effects as badges: { label, n }; n (turns left, layers,
    -- HP) only where the player could know it, or with SHOW HIDDEN VALUES
    -- for the counts the game rolls in secret
    local function badgeList(hidden)
        local list = {}
        local function add(label, n, secret)
            local show = n ~= nil and n ~= false and (hidden or not secret)
            list[#list + 1] = { label = label, n = show and n or false }
        end
        return list, add
    end
    local function positive(v) v = tonumber(v) return v and v > 0 and v or nil end

    -- Gen 3: a battler's effects on the battler (a switch clears them,
    -- BATON PASS aside), the side's on st.playerSide / enemySide (the
    -- screens, SPIKES, and FUTURE SIGHT / WISH as tokens)
    local function moveIdOf(m)
        if type(m) == "table" then return tonumber(m.id or m.moveId or m.move) end
        return tonumber(m)
    end
    local function moveLabel(m)
        local id = moveIdOf(m)
        return id and try(Pokemon.moveName, id) or "?"
    end
    local function battlerEffects(b, hidden)
        local list, add = badgeList(hidden)
        if b.focusEnergy then add("FOCUS ENERGY") end
        if b.leechSeed then add("LEECH SEED") end
        -- the next poison hit, in sixteenths of max HP (status.lua: +1, up to 15)
        if b.toxicCounter ~= nil and tonumber(b.toxicCounter) then
            add("TOXIC", math.min(15, tonumber(b.toxicCounter) + 1) .. "/16")
        end
        if positive(b.confusionTurns) then add("CONFUSED", b.confusionTurns, true) end
        if positive(b.substituteHP) then add("SUBSTITUTE", b.substituteHP .. "HP", true) end
        if b.expDisabledMove and positive(b.expDisableTurns) then
            add(moveLabel(b.expDisabledMove) .. " DISABLED", b.expDisableTurns, true)
        end
        if positive(b.expEncoreTurns) then add("ENCORE " .. moveLabel(b.expEncoreMove), b.expEncoreTurns, true) end
        if positive(b.expTrapTurns) then add(b.expTrapMove and moveLabel(b.expTrapMove) or "WRAP", b.expTrapTurns, true) end
        -- MEAN LOOK / SPIDER WEB / BLOCK (INGRAIN holds it too: its own badge)
        if b.escapePrevention or (b.expTrapped and not b.expIngrain) then add("CAN'T ESCAPE") end
        if b.perishSong and positive(b.expPerishTurns) then add("PERISH", b.expPerishTurns) end
        if b.cursed or b.expCursed then add("CURSED") end
        if b.expNightmare then add("NIGHTMARE") end
        if b.expInfatuated then add("IN LOVE") end
        if positive(b.expLockedOn) then add("LOCKED ON") end
        if b.foresight or b.expIdentified then add("IDENTIFIED") end
        if positive(b.expTauntedTurns) then add("TAUNT", b.expTauntedTurns) end
        if positive(b.expYawnTurns) then add("DROWSY") end
        if b.expIngrain then add("INGRAIN") end
        if positive(b.expUproarTurns) then add("UPROAR", b.expUproarTurns, true) end
        if b.torment or b.expTormented then add("TORMENT") end
        if positive(b.stockpile) then add("STOCKPILE", b.stockpile) end
        if b.chargedUp then add("CHARGE") end
        if positive(b.expRampageTurns) then add("RAMPAGE", b.expRampageTurns, true) end
        if positive(b.bideTurns) then add("BIDE", b.bideTurns) end
        if positive(b.expRechargeTurns) then add("RECHARGE") end
        if b.expImprison then add("IMPRISON") end
        if b.expGrudge then add("GRUDGE") end
        if b.destinyBond or b.expDestinyBond then add("DESTINY BOND") end
        if b.transformed then add("TRANSFORMED") end
        if b.minimized then add("MINIMIZED") end
        if b.defenseCurl then add("DEFENSE CURL") end
        if b.rage then add("RAGE") end
        return #list > 0 and list or false
    end

    -- what covers the whole field: MUD SPORT / WATER SPORT, kept on the
    -- one that used it and in force for everyone while it's in battle
    -- (battle_script_commands.c: Electric / Fire moves at half power)
    local function fieldEffects(st, hidden)
        local list, add = badgeList(hidden)
        -- as the damage code asks it (effects/hit.lua field_sport): any
        -- battler in play that used it and hasn't fainted, or the battle's
        -- own flag. st.battlers is a proxy (slots 0 / 1 are st.player /
        -- st.enemy, read through it, not stored in it): asked by slot.
        local mud = st.expMudSport and true or false
        local water = st.expWaterSport and true or false
        local battlers = type(st.battlers) == "table" and st.battlers or {}
        for id = 0, 3 do
            local b = battlers[id] or (id == 0 and st.player) or (id == 1 and st.enemy) or nil
            if type(b) == "table" and not b.fainted then
                if b.mudSport then mud = true end
                if b.waterSport then water = true end
            end
        end
        if mud then add("MUD SPORT", "ELECTRIC ×0.5") end
        if water then add("WATER SPORT", "FIRE ×0.5") end
        return #list > 0 and list or false
    end
    local function sideEffects(side, hidden)
        if type(side) ~= "table" then return false end
        local list, add = badgeList(hidden)
        if positive(side.expReflectTurns) then add("REFLECT", side.expReflectTurns) end
        if positive(side.expLightScreenTurns) then add("LIGHT SCREEN", side.expLightScreenTurns) end
        if positive(side.expSafeguardTurns) then add("SAFEGUARD", side.expSafeguardTurns) end
        if positive(side.expMistTurns) then add("MIST", side.expMistTurns) end
        if positive(side.spikes) then add("SPIKES", "×" .. side.spikes) end
        for _, tok in ipairs(type(side.tokens) == "table" and side.tokens or {}) do
            if tok.id == "EXP_FUTURE_SIGHT" then add("FUTURE SIGHT", positive(tok.turns) or false) end
            if tok.id == "EXP_WISH" then add("WISH", positive(tok.turns) or false) end
        end
        return #list > 0 and list or false
    end

    -- The battler at a position (0 / 2 the player's side, 1 / 3 the foe's;
    -- state.lua), while one is out there: st.player / st.enemy are 0 / 1,
    -- st.battlers[2] / [3] a double battle's partners, st.absent[id] an
    -- empty position (its POKéMON fainted with nobody left to send)
    local function battlerAt(st, id)
        local b = (id == 0 and st.player) or (id == 1 and st.enemy) or nil
        if not b and type(st.battlers) == "table" then b = st.battlers[id] end
        if type(b) ~= "table" or type(b.mon) ~= "table" then return nil end
        if type(st.absent) == "table" and st.absent[id] then return nil end
        return b
    end

    local function battleOut(game, st, spoilers, hidden)
        local out = { kind = st.wild and "wild" or (st.kind or "trainer"), title = "WILD POKéMON",
            trainerPic = false, size = 0, balls = false, ballSheet = false, team = {}, active = false,
            spoilers = spoilers, double = st.double and true or false }
        local twoFoes = (st.trainerB and tonumber(st.foeHalf)) and true or false
        if not st.wild then
            local name = st.trainerName
            local class = st.trainerClassName
            out.title = (class and name and (class .. " " .. name)) or name or class or "TRAINER"
            -- the trainer's front pic, as the battle draws it (trainerPicId)
            if st.trainerPicId ~= nil then out.trainerPic = art("trainer", st.trainerPicId) end
        end

        -- the POKéMON out on each side: one each in a single battle, up to
        -- two each in a double
        local foeIds = st.double and { 1, 3 } or { 1 }
        local myIds = st.double and { 0, 2 } or { 0 }
        local foes, mine = {}, {}
        for _, id in ipairs(foeIds) do
            local b = battlerAt(st, id)
            if b then foes[#foes + 1] = { id = id, b = b } end
        end
        if not st.safari then -- (no POKéMON is sent out in a SAFARI ZONE battle)
            for _, id in ipairs(myIds) do
                local b = battlerAt(st, id)
                if b then mine[#mine + 1] = { id = id, b = b } end
            end
        end

        local bySlot = knownBySlot[st] or {}
        -- the moves a foe has been seen using: on this battle copy, on its
        -- team slot (all of this battle) and on the team's own entry
        local function knownFor(slot, ...)
            local known = {}
            for _, m in ipairs({ ... }) do
                for id in pairs(knownMoves[m] or {}) do known[id] = true end
            end
            for id in pairs(slot and bySlot[slot] or {}) do known[id] = true end
            return known
        end

        local enemy = st.enemy and st.enemy.mon
        local party = not st.wild and st.foeParty or nil
        -- the foe's team slot out at each position (the battler's POKéMON
        -- is the battle's copy of the team's: known by its partyIndex)
        local outAt = {}
        for _, f in ipairs(foes) do
            local slot = tonumber(f.b.partyIndex)
            if slot then outAt[slot] = f.b end
        end
        if type(party) == "table" and #party > 0 then
            local seen = sentOut[st] or {}
            sentOut[st] = seen
            for slot in pairs(outAt) do seen[slot] = true end
            out.size = #party
            -- the lineup of six balls, as the battle's party summary shows it
            out.ballSheet = art("balls")
            out.balls = {}
            for i = 1, 6 do out.balls[i] = ballFrame(party[i]) end
            for i, mon in ipairs(party) do
                local battler = outAt[i]
                local active = battler ~= nil or (not st.double and mon == enemy)
                local revealed = spoilers or active or seen[i]
                local entry = { slot = i, active = active and true or false, revealed = revealed and true or false,
                    ball = ballFrame(mon) }
                if revealed then
                    -- one out fighting: as the battle has it (HP, status)
                    local src = (battler and battler.mon) or mon
                    for k, v in pairs(monInfo(src)) do entry[k] = v end
                    entry.icon = art("icon", mon)
                    entry.moves = movesFor(src, spoilers, knownFor(i, mon, battler and battler.mon))
                end
                out.team[i] = entry
            end
            -- two trainers against you (Emerald): each with their own half
            -- of the team (st.foeHalf), picture and balls
            if twoFoes then
                local half = tonumber(st.foeHalf)
                local B = st.trainerB
                local nameB = (B.className and B.className ~= "" and B.name and (B.className .. " " .. B.name))
                    or B.name or B.className or "TRAINER"
                local function side(title, pic, from, to)
                    local t = { title = title, trainerPic = pic, team = {}, balls = {}, size = 0 }
                    for i = from, to do
                        if party[i] then
                            t.team[#t.team + 1] = out.team[i]
                            t.balls[#t.balls + 1] = out.team[i].ball
                            t.size = t.size + 1
                        end
                    end
                    return t
                end
                out.trainers = {
                    side(out.title, out.trainerPic, 1, half),
                    side(nameB, B.pic ~= nil and art("trainer", B.pic) or false, half + 1, #party),
                }
                out.title = out.title .. " & " .. nameB
            end
        end

        -- each foe out: its card (as out.active always was), its stat
        -- changes and effects; in a two-trainer battle, whose it is
        local actives = {}
        for _, f in ipairs(foes) do
            local m = f.b.mon
            local slot = tonumber(f.b.partyIndex)
            local e = monInfo(m)
            e.front = art("front", m)
            e.moves = movesFor(m, spoilers, knownFor(slot, m, party and slot and party[slot]))
            local sp = try(Pokemon.speciesOf, m)
            e.owned = sp and platform.ownedSet(platform.save(game))[sp] and true or false
            e.stages = stagesOf(f.b.stages)
            e.effects = battlerEffects(f.b, hidden)
            e.pos, e.slot = f.id, slot
            if twoFoes and slot then e.trainer = slot <= tonumber(st.foeHalf) and 1 or 2 end
            actives[#actives + 1] = e
        end
        out.actives = actives
        out.active = actives[1] or false

        -- the player's side: each POKéMON out, with its card, stat changes
        -- and effects. In a battle with a partner (STEVEN, a link multi),
        -- position 2 is the partner's POKéMON, not one of the player's.
        local withPartner = (st.partner or st.playerHalf or st.multi) and true or false
        local players, mySlots = {}, {}
        for _, p in ipairs(mine) do
            local m = p.b.mon
            local e = monInfo(m)
            e.icon = art("icon", m)
            -- its front pic: the HANDS-OFF view draws it facing the foe
            e.front = art("front", m)
            e.stages = stagesOf(p.b.stages)
            e.effects = battlerEffects(p.b, hidden)
            e.pos, e.slot = p.id, tonumber(p.b.partyIndex)
            if withPartner and p.id == 2 then
                e.partner = true
                e.partnerName = type(st.partner) == "table" and st.partner.name or false
            elseif e.slot then
                mySlots[#mySlots + 1] = e.slot
            end
            players[#players + 1] = e
        end
        out.players = players
        out.playerSlots = mySlots
        out.player = players[1] or false
        out.playerSlot = mySlots[1] or false

        -- the battle's scenery, as it draws it (battle/bg.lua: the terrain
        -- this battle was set up with), for the HANDS-OFF backdrop
        local okBg, BattleBg = pcall(require, "src.core.game3.battle.bg")
        local sceneKey = okBg and BattleBg.sheetKey and try(BattleBg.sheetKey) or nil
        local sceneId = sceneKey and sprites and sprites.battleScene and try(sprites.battleScene, sceneKey)
        out.scene = sceneId and ("/img/" .. sceneId .. ".png") or false
        -- each side's effects (REFLECT, SPIKES ...), and the whole field's
        local sides = { player = sideEffects(st.playerSide, hidden), enemy = sideEffects(st.enemySide, hidden) }
        if sides.player or sides.enemy then out.sides = sides end
        out.field = fieldEffects(st, hidden)
        -- the weather and the turns it has left (st.weatherTurns, this one
        -- included); 0 = for good (the map's own weather, DRIZZLE and co.)
        local okR, Rules = pcall(require, "src.core.game3.battle.rules")
        local kind = okR and Rules.weather and try(Rules.weather.kind, st.weather) or nil
        if kind then
            local turns = tonumber(st.weatherTurns) or 0
            out.weather = { kind = kind, turns = turns > 0 and turns or false }
        end
        if st.safari then
            out.kind = "safari"
            if hidden then
                local ok, odds = pcall(safariOdds, game, st)
                out.safari = ok and odds or false
            end
        elseif hidden and st.wild and enemy and not (st.oldManTutorial or st.pokedude) then
            local ok, odds = pcall(catchOdds, game, st)
            out.catch = ok and odds or false
        end
        return out
    end

    -- the foe's moves as it uses them: remembered while the battle lasts
    local okEv = pcall(function()
        -- src/core/game3/battle/engine.lua Ctx:attackString: user is the
        -- battler, moveNum the FRLG move number
        mod.events:on("battle.move_used", function(ev)
            if type(ev) ~= "table" or ev.isCalled or ev.side == "player" then return end
            local mon = type(ev.user) == "table" and ev.user.mon or nil
            local id = tonumber(ev.moveNum)
            if mon and id then
                knownMoves[mon] = knownMoves[mon] or {}
                knownMoves[mon][id] = true
            end
            -- and by its team slot: the battler's POKéMON is the battle's
            -- own copy, not the team's, and a new one comes with each
            -- switch-in
            local slot = type(ev.user) == "table" and tonumber(ev.user.partyIndex)
            local st = slot and id and battleState()
            if st then
                local bySlot = knownBySlot[st] or {}
                knownBySlot[st] = bySlot
                bySlot[slot] = bySlot[slot] or {}
                bySlot[slot][id] = true
            end
        end)
    end)
    if not okEv then mod.log:info("battle.move_used unavailable: foe moves show with SPOILERS only") end

    -- nothing to track each frame on Gen 3 (live.lua's sentOut is kept above)
    function L.track() end

    ---- CONTEST (Emerald) -------------------------------------------------------

    -- The contest on screen (src/ui/game3/rse/contest.lua: UI.active(), its
    -- contest at .c, src/core/game3/rse/contest.lua). The game works out a
    -- turn the moment its animation starts (UI:taskDoAppeals -> runTurn),
    -- and a jam changes the others' points while it plays; so the phone
    -- takes its picture only between turns (no turn playing: screen.turn is
    -- nil) and keeps showing the last one while a turn plays. Never ahead of
    -- the screen, like the battle view.
    local RANKS = { [0] = "NORMAL RANK", "SUPER RANK", "HYPER RANK", "MASTER RANK", "LINK" }
    -- the five categories (pokemon/contest_moves.lua categories; the
    -- contest's built data keeps only the moves and effects)
    local CATEGORIES = { [0] = "COOL", "BEAUTY", "CUTE", "SMART", "TOUGH" }
    -- the screen counts appeals in hearts, 10 points each
    local function hearts(points)
        local p = tonumber(points) or 0
        return p >= 0 and math.floor(p / 10) or -math.floor(-p / 10)
    end
    local NUM_APPEALS = 5
    local contestShots = setmetatable({}, { __mode = "k" }) -- contest -> last picture

    local function contestMoveInfo(c, move)
        local d = c.data or {}
        local m = d.moves and d.moves[move]
        local e = m and d.effects and d.effects[m.effect]
        local cats = CATEGORIES
        return {
            name = try(Pokemon.moveName, move) or tostring(move),
            category = m and (cats[m.category] or tostring(m.category)) or false,
            appeal = e and math.floor((tonumber(e.appeal) or 0) / 10) or 0,
            jam = e and math.floor((tonumber(e.jam) or 0) / 10) or 0,
            desc = e and type(e.description) == "string" and (e.description:gsub("%s*\n%s*", " ")) or false,
        }
    end

    local function contestPicture(c, screen, hidden)
        local round = tonumber(c.contest and c.contest.appealNumber) or 0
        local finished = round >= NUM_APPEALS
        local shownTurns = tonumber(screen.e and screen.e.turnNumber) or 0
        local order = c.results and c.results.turnOrder or {}
        local cats = CATEGORIES
        -- names as the screen prints them (opponents' are ROM texts)
        local okU, Util = pcall(require, "src.core.game3.rse.contest_util")
        local function text(fn, m)
            local v = okU and Util[fn] and try(Util[fn], m)
            return type(v) == "string" and v ~= "" and v or nil
        end
        local out = {
            category = cats[c.category] or tostring(c.category),
            rank = RANKS[tonumber(c.rank) or 0] or "",
            round = math.min(round + 1, NUM_APPEALS), rounds = NUM_APPEALS, finished = finished,
            applause = tonumber(c.contest and c.contest.applauseLevel) or 0, applauseMax = 5,
            contestants = {}, moves = {},
        }
        for i = 0, 3 do
            local m = c.mons and c.mons[i]
            local st = c.status and c.status[i] or {}
            if type(m) == "table" then
                -- appealed this round: its turn is among the ones shown
                local appealed = not finished and (tonumber(order[i]) or 9) < shownTurns
                local entry = {
                    name = text("monName", m) or (type(m.nickname) == "string" and m.nickname)
                        or try(Pokemon.name, m.species) or "?",
                    trainer = text("trainerName", m) or (type(m.trainerName) == "string" and m.trainerName) or false,
                    icon = art("iconSpecies", tonumber(m.species)),
                    player = i == c.playerIndex,
                    -- Round 1: the condition the judge saw, as hearts (10 points each)
                    condition = math.floor((tonumber(c.round1 and c.round1[i]) or 0) / 10),
                    total = hearts(st.pointTotal),
                    appealed = appealed,
                    move = appealed and st.currMove and st.currMove ~= 0 and (try(Pokemon.moveName, st.currMove) or false) or false,
                    hearts = appealed and hearts(st.appeal) or false,
                    nervous = (tonumber(st.nervous) or 0) ~= 0,
                    resting = (tonumber(st.numTurnsSkipped) or 0) ~= 0 or (tonumber(st.noMoreTurns) or 0) ~= 0,
                    attention = (tonumber(st.hasJudgesAttention) or 0) ~= 0,
                    place = finished and c.standings and (tonumber(c.standings[i]) or 0) + 1 or false,
                }
                if hidden then entry.round1 = tonumber(c.round1 and c.round1[i]) or 0 end
                out.contestants[#out.contestants + 1] = entry
            end
        end
        -- the player's moves, with the summary's CONTEST page info and a
        -- combo mark after the move it used last
        local me = c.mons and c.mons[c.playerIndex]
        local last = c.status and c.status[c.playerIndex] and c.status[c.playerIndex].prevMove
        for k = 0, 3 do
            local move = me and me.moves and tonumber(me.moves[k])
            if move and move > 0 then
                local info = contestMoveInfo(c, move)
                if last and last ~= 0 then
                    local ok, combo = pcall(c.areMovesCombo, c, last, move)
                    info.combo = ok and (tonumber(combo) or 0) > 0 or false
                end
                out.moves[#out.moves + 1] = info
            end
        end
        return out
    end

    local function contestState(hidden)
        local okU, UI = pcall(require, "src.ui.game3.rse.contest")
        local screen = okU and UI.active and try(UI.active)
        local c = type(screen) == "table" and screen.c
        if type(c) ~= "table" then return false end
        local shot = contestShots[c]
        if screen.turn ~= nil and shot then return shot end
        local ok, pic = pcall(contestPicture, c, screen, hidden)
        if not ok then mod.log:warn("contest view failed: %s", tostring(pic)) return shot or false end
        contestShots[c] = pic
        return pic
    end

    ---- DAY-CARE / SAFARI -----------------------------------------------------

    -- The day-cares' stores, read as they are. Daycare.stateOf / route5Of
    -- would create them (persistentStore), so this mirrors its lookup
    -- without writing: the session's own table first (the one persistentStore
    -- copies from), else the one kept in the save's mod data.
    local function peekStore(session, field)
        local loose = rawget(session, field)
        if type(loose) == "table" then return loose end
        local okD, Daycare = pcall(require, "src.core.game3.daycare")
        local okK, key = false, nil
        if okD and Daycare.saveKey then okK, key = pcall(Daycare.saveKey, session) end
        local data = type(session.modData) == "table" and okK and key and session.modData[key]
        return type(data) == "table" and type(data[field]) == "table" and data[field] or nil
    end

    -- the day-care man's words on the pair (daycare.c:1480, by
    -- Breeding.compatibility's 70 / 50 / 20 / 0)
    local COMPAT = {
        [70] = "The two seem to get along very well.",
        [50] = "The two seem to get along.",
        [20] = "The two don't seem to like each other much.",
        [0] = "The two prefer to play with other POKéMON than each other.",
    }

    -- ROUTE 5's single guest and FOUR ISLAND's pair: each POKéMON's level
    -- once picked up (daycare.c GetLevelAfterDaycareSteps), the levels it
    -- gained and the fee (GetDaycareCostForSelectedMon); the pair adds the
    -- waiting egg and how well the two get along
    local function daycare(game)
        local session = platform.save(game)
        local okD, Daycare = pcall(require, "src.core.game3.daycare")
        if not (session and okD) then return false end
        local function monOut(mon, steps)
            local sp = tonumber(mon and (mon.species or mon.speciesId)) or 0
            if sp <= 0 then return nil end
            steps = tonumber(steps) or 0
            return {
                name = try(Daycare.nickname, mon) or try(Pokemon.name, sp) or tostring(sp),
                icon = art("icon", { species = sp, speciesNumbering = "internal" }),
                level = try(Daycare.levelAfterSteps, mon, steps) or tonumber(mon.level) or false,
                gained = try(Daycare.levelsGained, mon, steps) or 0,
                fee = try(Daycare.cost, mon, steps) or false,
            }
        end
        local places = {}
        local r5 = peekStore(session, "route5Daycare")
        local guest = r5 and monOut(r5.mon, r5.steps)
        if guest then places[#places + 1] = { name = "ROUTE 5", mons = { guest } } end
        local dc = peekStore(session, "daycare")
        if dc then
            local mons = {}
            local steps = type(dc.steps) == "table" and dc.steps or {}
            for i = 1, Daycare.DAYCARE_MON_COUNT or 2 do
                mons[#mons + 1] = monOut(Daycare.mon(dc, i), steps[i])
            end
            if #mons > 0 then
                -- FireRed's pair lives on FOUR ISLAND; Emerald has this one
                -- day-care only, on ROUTE 117 (its section's own name)
                local where = "FOUR ISLAND"
                if platform.isRse(game) then
                    local okR, RegionMap = pcall(require, "src.ui.game3.rse.region_map")
                    local okM, Mapsec = pcall(require, "src.ui.game3.rse.mapsec")
                    local sec = okR and try(RegionMap.mapsec, "ROUTE_117")
                    where = okM and sec and try(Mapsec.name, sec) or "ROUTE 117"
                end
                local place = { name = where, mons = mons, egg = try(Daycare.isEggPending, dc) and true or false }
                if #mons == 2 then
                    local okB, Breeding = pcall(require, "src.core.game3.breeding")
                    local c = okB and try(Breeding.compatibility, dc)
                    place.compat = c and COMPAT[c] or false
                end
                places[#places + 1] = place
            end
        end
        return #places > 0 and { places = places } or false
    end

    -- In the SAFARI ZONE (FLAG_SYS_SAFARI_MODE, safari_zone.c): the SAFARI
    -- BALLS and steps left, read without Safari.state (which would create
    -- the table) or Safari.isActive (which may reset it)
    local SAFARI_FLAG, SAFARI_BALL = 0x800, 5
    local function safari(game)
        local session = platform.save(game)
        local st = session and rawget(session, "safari")
        if type(st) ~= "table" then return false end
        local okM, RegionMap = pcall(require, "src.ui.game3.region_map")
        local on = okM and RegionMap.isFlagSet and try(RegionMap.isFlagSet, SAFARI_FLAG)
        if not on then return false end
        return {
            balls = tonumber(st.balls) or 0,
            steps = tonumber(st.steps) or 0,
            ballName = try(ItemsData.displayName, SAFARI_BALL) or "SAFARI BALL",
            ballIcon = art("itemIcon", SAFARI_BALL),
        }
    end

    ---- state --------------------------------------------------------------

    -- DexNav's sections change with the place, the time of day, SPOILERS
    -- and the POKéDEX (its owned marks): rebuilt when one of those changes,
    -- and at least every few seconds for the rest (a new rod, a swarm).
    -- A copy of the list goes out, so what's added to it (the roamer)
    -- never lands in the kept one.
    local NAV_SECONDS = 5
    local navMemo = {}
    local function setCount(set)
        local n = 0
        for _, v in pairs(set or {}) do if v then n = n + 1 end end
        return n
    end
    local function memoNav(game, key, build)
        local save = platform.save(game)
        key = key .. "|" .. setCount(platform.seenSet(save)) .. "|" .. setCount(platform.ownedSet(save))
        local now = love.timer.getTime()
        if not (navMemo.key == key and now - navMemo.at < NAV_SECONDS) then
            navMemo.key, navMemo.value, navMemo.at = key, build(), now
        end
        local copy = {}
        for i, v in ipairs(navMemo.value or {}) do copy[i] = v end
        return copy
    end

    function L.state(game, spoilers, opts)
        spoilers = spoilers and true or false
        local out = { spoilers = spoilers, location = false, dexnav = {}, battle = false,
            daycare = false, safari = false }
        if not game then return out end
        local w = mod.world
        local here = w and w.current and try(w.current, w)
        local mapId = here and here.mapId or platform.mapId(game)
        if mapId then
            out.location = { mapId = tostring(mapId), name = L.locationName(game, mapId),
                backdrop = L.backdrop(game, mapId) }
            out.dexnav = memoNav(game, tostring(mapId) .. "|" .. tostring(spoilers),
                function() return dexnav(game, mapId, spoilers) end)
            -- the roaming legendary, while it is on this route (as the
            -- POKéDEX's AREA shows it; no slot, so no share)
            local r = #out.dexnav > 0 and L.roamerOn(game, mapId)
            if r then
                local e = dexEntry(platform.save(game), tonumber(r.species), false, tonumber(r.level), tonumber(r.level), spoilers)
                out.dexnav[#out.dexnav + 1] = { kind = "roam", label = "ROAMING", rate = false,
                    note = "ON THIS ROUTE", list = { e } }
            end
        end
        -- Emerald: the contest on screen
        if platform.isRse(game) then out.contest = contestState(opts and opts.hidden) or false end
        local okDc, dc = pcall(daycare, game)
        if okDc then out.daycare = dc else mod.log:warn("day-care state failed: %s", tostring(dc)) end
        local okSf, sf = pcall(safari, game)
        if okSf then out.safari = sf end
        local st = battleState()
        if st then
            local ok, b = pcall(battleOut, game, st, spoilers, opts and opts.hidden)
            if ok then out.battle = b else mod.log:warn("battle state failed: %s", tostring(b)) end
        end
        return out
    end

    return L
end
