-- The LIVE tab on Gen 2 (Gold / Silver): the same JSON as live.lua, read
-- from Gold's own world, encounter tables and battle screen.
--
-- Differences from Gen 1 that show here:
--   * the location is the map's LANDMARK name (World:landmarkName)
--   * grass tables are three lists, one per time of day (MORN / DAY / NITE);
--     the DexNav shows the current one and can preview the others
--   * fishing rolls a map's FISH GROUP (some rows change at night)
--   * the battle screen (src/ui/gen2/BattleState.lua) keeps what is drawn
--     (shownMon / shownHp / shownStatus / showEnemyHud) apart from the
--     model (.battle, src/battle/gen2/Battle.lua), which runs a whole turn
--     ahead: the phone reads the drawn side so it never runs ahead
return function(mod, sprites, platform)
    local Encounter = require("src.battle.gen2.Encounter")

    local ROD_ORDER = { "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }
    local ROD_KEYS = { OLD_ROD = "old", GOOD_ROD = "good", SUPER_ROD = "super" }
    local ROD_LABELS = { OLD_ROD = "OLD ROD", GOOD_ROD = "GOOD ROD", SUPER_ROD = "SUPER ROD" }
    -- the rod's item name, as the BAG shows it (a language mod's too)
    local function rodLabel(game, rod)
        local def = game.data.items and game.data.items[rod]
        return type(def) == "table" and def.name or ROD_LABELS[rod]
    end
    local DAYTIMES = { "MORN", "DAY", "NITE" }
    local DAYTIME_OK = { MORN = true, DAY = true, NITE = true }
    -- a move whose "used" text never came up is counted after this long
    local PENDING_FRAMES = 60 * 20

    local function art(kind, ...)
        if not (sprites and sprites[kind]) then return false end
        local ok, id = pcall(sprites[kind], ...)
        return ok and id and ("/img/" .. id .. ".png") or false
    end

    local L = {}

    ---- time of day ----------------------------------------------------------

    -- The time of day the next wild roll uses (WorldAPI:effectiveEncounters'
    -- own default): Clock hour -> MORN / DAY / NITE (DARK reads as NITE).
    function L.daytime(game)
        local okC, Clock = pcall(require, "src.core.gen2.Clock")
        local okP, Palettes = pcall(require, "src.world.gen2.Palettes")
        if okC and okP and game and game.save then
            local ok, dt = pcall(function() return Palettes.clockDaytime(Clock.hour(game.save)) end)
            if ok and dt then return dt == "DARK" and "NITE" or dt end
        end
        return "DAY"
    end

    ---- location -------------------------------------------------------------

    function L.locationName(game, mapId)
        local w = platform.world(game)
        if w and w.map and w.map.id == mapId and w.landmarkName then
            local ok, name = pcall(w.landmarkName, w)
            if ok and type(name) == "string" and name ~= "" then return (name:gsub("\n", " ")) end
        end
        local okN, Nests = pcall(require, "src.core.gen2.Nests")
        local def = game.data.gen2Maps and game.data.gen2Maps[mapId]
        if okN and def and def.landmark then
            local mark = Nests.landmark(game.data, def.landmark)
            if mark and mark.name then return (mark.name:gsub("\n", " ")) end
        end
        return (tostring(mapId):gsub("_", " "))
    end

    ---- DexNav ---------------------------------------------------------------

    local function dexEntry(game, species, share, minL, maxL, spoilers)
        local seen = platform.seenSet(game.save)[species] and true or false
        local owned = platform.ownedSet(game.save)[species] and true or false
        seen = seen or owned
        local known = spoilers or seen
        local def = game.data.pokemon[species] or {}
        return {
            species = known and tostring(species) or false,
            name = known and (def.name or tostring(species)) or false,
            icon = known and art("icon", game.data, { species = species }) or false,
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

    local function levelRanges(slots)
        local ranges = {}
        for _, slot in ipairs(slots or {}) do
            local species, level = slot.species, slot.level
            if species and level then
                local r = ranges[species]
                if r then
                    r.min, r.max = math.min(r.min, level), math.max(r.max, level)
                else
                    ranges[species] = { min = level, max = level }
                end
            end
        end
        return ranges
    end

    -- The effective distribution, the same way WorldAPI:effectiveEncounters
    -- builds it (swarm tables, then the slot chances, then mods'
    -- encounter.table hook). Computed here because Gold's WorldAPI reads
    -- data.encounters, which Gold keeps as data.gen2Encounters, so it
    -- answers "no encounters" everywhere.
    local function effective(game, mapId, terrain, daytime)
        local tables = game.data.gen2Encounters
        if not tables then return nil end
        local okR, Roamers = pcall(require, "src.core.gen2.Roamers")
        if okR and Roamers.Swarm and Roamers.Swarm.tables and game.save then
            local ok, swapped = pcall(Roamers.Swarm.tables, game.save, tables, mapId)
            if ok and swapped then tables = swapped end
        end
        local dist, chance = {}, 0
        local function fill(slots, chances)
            local prev = 0
            for i, cumulative in ipairs(chances) do
                local slot = slots[i]
                if slot and slot.species then
                    dist[slot.species] = (dist[slot.species] or 0) + (cumulative - prev)
                end
                prev = cumulative
            end
        end
        if terrain == "water" then
            local entry = tables.water and tables.water[mapId]
            chance = (entry and tonumber(entry.rate) or 0) / 256
            if entry and chance > 0 and entry.slots then fill(entry.slots, Encounter.WATER_SLOT_CHANCES) end
        else
            local entry = tables.grass and tables.grass[mapId]
            local key = (daytime == "DARK") and "NITE" or (daytime or "DAY")
            local rate = entry and entry.rates and (entry.rates[key] or entry.rates.DAY)
            chance = (tonumber(rate) or 0) / 256
            local slots = entry and entry.slots and entry.slots[key]
            if slots and chance > 0 then fill(slots, Encounter.GRASS_SLOT_CHANCES) end
        end
        local okRt, Runtime = pcall(require, "src.mods.Runtime")
        if okRt and Runtime.wantsHook and Runtime.wantsHook("encounter.table") then
            local ok, transformed = pcall(Runtime.call, "encounter.table", function(d) return d end, dist,
                { mapId = mapId, terrain = terrain, preview = true })
            if ok and type(transformed) == "table" then dist = transformed end
        end
        return { chance = chance, dist = dist }
    end

    -- GRASS in the open, CAVE underground, INDOORS in buildings (towers, the
    -- Slowpoke Well floors are caves)
    local function landLabel(game, mapId)
        local def = game.data.gen2Maps and game.data.gen2Maps[mapId]
        local env = def and def.environment
        if env == "CAVE" or env == "DUNGEON" then return "cave", "CAVE" end
        if env == "INDOOR" or env == "GATE" then return "cave", "INDOORS" end
        return "grass", "GRASS"
    end

    local function section(game, eff, slots, kind, label, spoilers)
        if not eff or (eff.chance or 0) <= 0 then return nil end
        local total = 0
        for _, w in pairs(eff.dist) do total = total + w end
        if total <= 0 then return nil end
        local ranges = levelRanges(slots)
        local list = {}
        for species, w in pairs(eff.dist) do
            local r = ranges[species] or {}
            list[#list + 1] = dexEntry(game, species, w / total, r.min, r.max, spoilers)
        end
        return { kind = kind, label = label, rate = eff.chance, list = sortList(list) }
    end

    -- The rod rows of a map's fish group at a time of day: species -> share
    -- (rows are cumulative out of 256; a row may hold day / nite species of
    -- its own or through timeFishGroups; an empty row is "no bite")
    local function fishRows(game, mapId, rod, daytime)
        local enc = game.data.gen2Encounters or {}
        local def = game.data.gen2Maps and game.data.gen2Maps[mapId]
        local group = def and def.fishGroup
        if not group then return nil end
        local swarm = game.save and game.save.dailyFlags and game.save.dailyFlags.fishingSwarm
        group = Encounter.fishGroupFor(enc, group, swarm)
        local rows = enc.fishGroups and enc.fishGroups[group] and enc.fishGroups[group][ROD_KEYS[rod]]
        if not rows or #rows == 0 then return nil end
        local tod = (daytime == "NITE" or daytime == "DARK") and "nite" or "day"
        local shares, levels, prev = {}, {}, 0
        for _, row in ipairs(rows) do
            local chance = row.chance or 0
            local slot = row[tod]
            if not slot and row.timeGroup and enc.timeFishGroups then
                local tg = enc.timeFishGroups[row.timeGroup]
                slot = tg and tg[tod]
            end
            slot = slot or row
            local w = chance - prev
            prev = chance
            if slot.species and slot.species ~= 0 and slot.species ~= "NO_ITEM" and w > 0 then
                shares[slot.species] = (shares[slot.species] or 0) + w
                levels[#levels + 1] = { species = slot.species, level = slot.level }
            end
        end
        return shares, levels
    end

    -- every section of one map: land (per daytime), surf, rods
    -- opts.daytime: which grass list; opts.allRods: every rod, owned or not
    function L.mapSections(game, mapId, spoilers, opts)
        opts = opts or {}
        local daytime = opts.daytime or L.daytime(game)
        local enc = game.data.gen2Encounters or {}
        local sections = {}
        local grass = enc.grass and enc.grass[mapId]
        if grass then
            local kind, label = landLabel(game, mapId)
            local s = section(game, effective(game, mapId, "grass", daytime),
                grass.slots and grass.slots[daytime], kind, label, spoilers)
            if s then
                s.daytime = platform.daytimeLabel(daytime)
                sections[#sections + 1] = s
            end
        end
        local water = enc.water and enc.water[mapId]
        if water then
            sections[#sections + 1] = section(game, effective(game, mapId, "water"), water.slots, "surf", "SURF", spoilers)
        end
        local inventory = game.save and game.save.inventory or {}
        for _, rod in ipairs(ROD_ORDER) do
            if opts.allRods or (inventory[rod] or 0) > 0 then
                local shares, levels = fishRows(game, mapId, rod, daytime)
                if shares then
                    local total = 0
                    for _, w in pairs(shares) do total = total + w end
                    if total > 0 then
                        local ranges = levelRanges(levels)
                        local list = {}
                        for species, w in pairs(shares) do
                            local r = ranges[species] or {}
                            list[#list + 1] = dexEntry(game, species, w / total, r.min, r.max, spoilers)
                        end
                        sections[#sections + 1] = { kind = rod, label = rodLabel(game, rod), rate = false,
                            list = sortList(list) }
                    end
                end
            end
        end
        return sections
    end

    ---- battle -----------------------------------------------------------------

    -- Gold's battle screen: registry id Gen2BattleState, model in .battle
    local function findBattle(game)
        local states = game and game.stack and game.stack.states
        if not states then return nil end
        for i = #states, 1, -1 do
            local s = states[i]
            if type(s) == "table" and s.battle and s.shownMon and s.battle.enemyParty then return s end
        end
        return nil
    end

    local sentOut = setmetatable({}, { __mode = "k" })      -- screen -> set of mons
    local knownMoves = setmetatable({}, { __mode = "k" })   -- mon -> set of move ids
    local pendingMoves = setmetatable({}, { __mode = "k" }) -- model -> list

    local function learnMove(mon, id)
        local set = knownMoves[mon]
        if not set then set = {} knownMoves[mon] = set end
        set[id] = true
    end

    local function inQueue(queue, event)
        for _, item in ipairs(queue or {}) do
            if item == event then return true end
        end
        return false
    end

    -- Battle.lua raises battle.move_used right after queueing the move's
    -- "X used Y!" event (battle.moveEvent). The move counts as seen once
    -- the screen has taken that event off its queue to show it.
    if mod.events and mod.events.on then
        mod.events:on("battle.move_used", function(e)
            local model = e.battle
            if not (model and e.user and (e.moveId or (e.move and e.move.id))) then return end
            if e.side == "player" or e.isCalled then return end
            if model.enemy ~= e.user and e.side ~= "enemy" then return end
            local list = pendingMoves[model] or {}
            pendingMoves[model] = list
            list[#list + 1] = { mon = e.user, id = e.moveId or e.move.id, event = model.moveEvent, age = 0 }
        end)
    end

    -- what the screen shows of the foe right now (nil while it is not up)
    local function shownFoe(screen)
        if not screen.showEnemyHud then return nil end
        return screen.shownMon and screen.shownMon.enemy or nil
    end

    function L.track(game)
        local screen = findBattle(game)
        local model = screen and screen.battle
        for m, list in pairs(pendingMoves) do
            if m ~= model then
                pendingMoves[m] = nil
            else
                for i = #list, 1, -1 do
                    local p = list[i]
                    p.age = p.age + 1
                    -- still undelivered (model.events) or waiting on screen
                    -- (screen.queue): not shown yet
                    local waiting = p.event and (inQueue(m.events, p.event) or inQueue(screen.queue, p.event))
                    if not waiting or p.age > PENDING_FRAMES then
                        learnMove(p.mon, p.id)
                        table.remove(list, i)
                    end
                end
            end
        end
        local foe = screen and shownFoe(screen)
        if not foe then return end
        local seen = sentOut[screen]
        if not seen then
            seen = setmetatable({}, { __mode = "k" })
            sentOut[screen] = seen
        end
        seen[foe] = true
    end

    local function typeName(data, typeId)
        local types = data.type_chart and data.type_chart.types
        local record = types and types[typeId]
        return record and record.name or (tostring(typeId):gsub("_TYPE$", ""))
    end

    local function movesFor(data, mon, spoilers)
        local known = knownMoves[mon] or {}
        local list, listed = {}, {}
        local function add(id)
            if listed[id] then return end
            listed[id] = true
            local mdef = data.moves and data.moves[id] or {}
            list[#list + 1] = { name = mdef.name or tostring(id), type = mdef.type and typeName(data, mdef.type) or false }
        end
        for _, slot in ipairs(mon.moves or {}) do
            local id = type(slot) == "table" and slot.id or slot
            if id and (spoilers or known[id]) then add(id) end
        end
        for id in pairs(known) do add(id) end
        return list
    end

    -- HP / status as drawn: the active foe follows the HUD's draining bar
    -- (the player's too, for its card)
    local function shown(screen, mon)
        for _, side in ipairs({ "enemy", "player" }) do
            if screen.shownMon and screen.shownMon[side] == mon and screen.shownHp then
                return screen.shownHp[side] or mon.hp or 0, (screen.shownStatus and screen.shownStatus[side]) or false
            end
        end
        return mon.hp or 0, mon.status or false
    end

    local function ballFrame(screen, mon)
        if not mon then return 3 end
        local hp, status = shown(screen, mon)
        if hp <= 0 then return 2 end
        if status then return 1 end
        return 0
    end

    local function monInfo(game, screen, mon)
        local def = game.data.pokemon[mon.species] or {}
        local hp, status = shown(screen, mon)
        return {
            name = mon.nickname or def.name or tostring(mon.species),
            level = mon.level or 0,
            hp = hp,
            maxHp = (mon.stats and mon.stats.hp) or mon.maxHp or 0,
            status = status or false
        }
    end

    -- A wild battle's catch odds (SHOW HIDDEN VALUES): the species' catch
    -- rate and, for every ball in the BALL pocket, the chance it catches
    -- the foe as it is now (the battle screen's catchChance: Gold's own
    -- ball multipliers and HP / status math; nil when a mod hooks the roll)
    local function catchOdds(game, screen, foe)
        local def = foe and game.data.pokemon and game.data.pokemon[foe.species]
        local balls = {}
        for id, count in pairs(game.save and game.save.inventory or {}) do
            local item = game.data.items and game.data.items[id]
            if (tonumber(count) or 0) > 0 and type(item) == "table" and item.pocket == "BALL" then
                local ok, p = pcall(screen.catchChance, screen, id)
                balls[#balls + 1] = { name = item.name or tostring(id), count = count,
                    chance = ok and tonumber(p) and p / 100 or false }
            end
        end
        table.sort(balls, function(a, b) return a.name < b.name end)
        return { rate = def and tonumber(def.catchRate) or false, balls = balls }
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

    -- Gen 2: a POKéMON's effects sit in its volatile table (Battle:volatile;
    -- a switch clears them), the side's in Battle.screens / spikes
    local function moveLabel(data, id)
        local d = id ~= nil and data.moves and data.moves[id]
        return d and d.name or (id ~= nil and tostring(id):gsub("_", " ")) or "?"
    end
    local function volatileOf(mon)
        return type(mon) == "table" and type(mon.volatile) == "table" and mon.volatile or {}
    end
    local function monEffects(data, mon, foe, hidden)
        local v, fv = volatileOf(mon), volatileOf(foe)
        local list, add = badgeList(hidden)
        if v.mist then add("MIST") end
        if v.focusEnergy then add("FOCUS ENERGY") end
        if v.leechSeed then add("LEECH SEED") end
        -- the next poison hit, in sixteenths of max HP (Battle's toxic residual)
        local toxic = positive(mon.toxicCounter) or positive(v.toxicCounter)
        if toxic then add("TOXIC", toxic .. "/16") end
        if positive(v.confuseCount) then add("CONFUSED", v.confuseCount, true) end
        if positive(v.substitute) then add("SUBSTITUTE", v.substitute .. "HP", true) end
        if v.disabled then add(moveLabel(data, v.disabled) .. " DISABLED", v.disabledTurns, true) end
        if v.encore then add("ENCORE " .. moveLabel(data, v.encore), v.encoreTurns, true) end
        -- a count of n hurts on n - 1 turns (HandleWrap decrements first)
        if positive(v.wrapCount) then
            add(v.wrapMoveId and moveLabel(data, v.wrapMoveId) or v.wrapMove or "WRAP", math.max(1, v.wrapCount - 1), true)
        end
        if fv.trapsTarget then add("CAN'T ESCAPE") end
        if positive(v.perish) then add("PERISH", v.perish) end
        if v.cursed then add("CURSED") end
        if v.attract then add("IN LOVE") end
        if v.lockOn then add("LOCKED ON") end
        if v.identified then add("IDENTIFIED") end
        if positive(v.rampageTurns) then add(v.rampageMove and moveLabel(data, v.rampageMove) or "RAMPAGE", v.rampageTurns, true) end
        if positive(v.bideTurns) then add("BIDE", v.bideTurns, true) end
        if v.recharge then add("RECHARGE") end
        if v.transformed then add("TRANSFORMED") end
        if v.curled then add("DEFENSE CURL") end
        if v.rage then add("RAGE") end
        return #list > 0 and list or false
    end
    -- what covers one side: the screens (5 turns), SPIKES, and a FUTURE
    -- SIGHT on its way to it (counted on the one that used it)
    local function sideEffects(model, key, mons, hidden)
        local list, add = badgeList(hidden)
        local s = model.screens and model.screens[key] or {}
        if positive(s.reflect) then add("REFLECT", s.reflect) end
        if positive(s.lightScreen) then add("LIGHT SCREEN", s.lightScreen) end
        if positive(s.safeguard) then add("SAFEGUARD", s.safeguard) end
        if model.spikes and model.spikes[key] then add("SPIKES") end
        for _, mon in ipairs(mons) do
            local v = volatileOf(mon)
            if positive(v.futureSight) and v.futureSightSide == key then add("FUTURE SIGHT", v.futureSight) end
        end
        return #list > 0 and list or false
    end

    local function battleState(game, screen, spoilers, hidden)
        local data, model = game.data, screen.battle
        local out = { kind = model.wild and "wild" or "trainer", title = "WILD POKéMON", trainerPic = false,
            size = 0, balls = false, ballSheet = false, team = {}, active = false, spoilers = spoilers }
        local trainer = model.trainer
        if not model.wild and trainer then
            out.title = trainer.name or trainer.className or "TRAINER"
            out.trainerPic = art("trainer", data, { trainerClass = screen.enemyTrainerClass or trainer.classId or trainer.class })
        end
        local foe = shownFoe(screen)
        if not model.wild then
            local party = model.enemyParty or {}
            local seen = sentOut[screen] or {}
            out.size = #party
            out.ballSheet = art("balls", data)
            out.balls = {}
            for i = 1, 6 do out.balls[i] = ballFrame(screen, party[i]) end
            for i, mon in ipairs(party) do
                local active = foe ~= nil and mon == foe
                local revealed = spoilers or active or seen[mon]
                local entry = { slot = i, active = active, revealed = revealed and true or false,
                    ball = ballFrame(screen, mon) }
                if revealed then
                    for k, v in pairs(monInfo(game, screen, mon)) do entry[k] = v end
                    entry.icon = art("icon", data, mon)
                    entry.moves = movesFor(data, mon, spoilers)
                end
                out.team[i] = entry
            end
        end
        -- a wild foe is up from the start; a trainer's once its HUD is
        local enemy = foe or (model.wild and screen.shownMon and screen.shownMon.enemy) or nil
        if enemy then
            out.active = monInfo(game, screen, enemy)
            out.active.front = art("front", data, enemy)
            out.active.moves = movesFor(data, enemy, spoilers)
            out.active.owned = platform.ownedSet(game.save)[enemy.species] and true or false
        end
        -- the player's POKéMON in the fight: its party slot (Battle.playerIndex)
        out.playerSlot = tonumber(model.playerIndex) or false
        -- its card and both sides' stat changes (Battle.stages.player / enemy)
        local stages = model.stages or {}
        local mine = model.player
        if type(mine) == "table" and mine.species then
            out.player = monInfo(game, screen, mine)
            out.player.icon = art("icon", data, mine)
            -- its front pic: the HANDS-OFF view draws it facing the foe
            out.player.front = art("front", data, mine)
            out.player.stages = stagesOf(stages.player)
        end
        if out.active then out.active.stages = stagesOf(stages.enemy) end
        -- multi-turn effects: each POKéMON's, then each side's
        local foeMon = enemy
        if out.player and type(mine) == "table" then out.player.effects = monEffects(data, mine, foeMon, hidden) end
        if out.active and foeMon then out.active.effects = monEffects(data, foeMon, mine, hidden) end
        local both = { mine, foeMon }
        local sides = { player = sideEffects(model, "player", both, hidden), enemy = sideEffects(model, "enemy", both, hidden) }
        if sides.player or sides.enemy then out.sides = sides end
        -- the weather (RAIN DANCE, SUNNY DAY, SANDSTORM) and the turns it
        -- has left, this one included (Battle.weatherTurns: 5 when cast,
        -- one less at each turn's end; it stops at 0)
        local kind = model.weather and ({ rain = "RAIN", sun = "SUN", sandstorm = "SAND" })[model.weather]
        if kind then
            local turns = tonumber(model.weatherTurns) or 0
            out.weather = { kind = kind, turns = turns > 0 and turns or false }
        end
        if hidden and model.wild and enemy then
            local ok, odds = pcall(catchOdds, game, screen, enemy)
            out.catch = ok and odds or false
        end
        return out
    end

    ---- DAY-CARE --------------------------------------------------------------

    -- DayCareMonCompatibilityText's five verdicts (Specials.lua COMPATIBILITY,
    -- by Breeding.compatibilityText), said of the first POKéMON about the other
    local COMPAT = {
        brimming = "It's brimming with energy.",
        none = "It has no interest in %s.",
        cares = "It appears to care for %s.",
        friendly = "It's friendly with %s.",
        interest = "It shows interest in %s.",
    }

    -- ROUTE 34's DAY-CARE (save.dayCare: the man's and the lady's POKéMON,
    -- the egg). Read as it is: Breeding.dayCare / side would create the
    -- tables. Each POKéMON's level now, the levels it grew and the fee
    -- (Breeding.levelGrowth / retrievePrice, as the couple work it out);
    -- with two, the egg waiting and the couple's word on the pair
    -- (Breeding.compatibility, which a mod may change).
    local function daycare(game)
        local dc = game.save and game.save.dayCare
        if type(dc) ~= "table" then return false end
        local okB, Breeding = pcall(require, "src.core.gen2.Breeding")
        if not okB then return false end
        local data = game.data
        local mons, raw = {}, {}
        for _, which in ipairs({ "man", "lady" }) do
            local slot = dc[which]
            local mon = type(slot) == "table" and slot.mon
            if type(mon) == "table" then
                local def = data.pokemon and data.pokemon[mon.species] or {}
                local ok, stored, level, grown = pcall(Breeding.levelGrowth, data, slot)
                if not ok then stored, level, grown = mon.level, mon.level, 0 end
                local okP, fee = pcall(Breeding.retrievePrice, grown)
                mons[#mons + 1] = {
                    name = mon.nickname or def.name or tostring(mon.species),
                    icon = art("icon", data, mon),
                    level = level or false, gained = grown or 0, fee = okP and fee or false,
                }
                raw[#raw + 1] = mon
            end
        end
        if #mons == 0 then return false end
        local place = { name = "ROUTE 34", mons = mons, egg = dc.hasEgg and true or false }
        if #raw == 2 then
            local okC, value = pcall(Breeding.compatibility, data, raw[1], raw[2])
            local key = okC and Breeding.compatibilityText(value)
            place.compat = key and COMPAT[key] and COMPAT[key]:format(mons[2].name) or false
        end
        return { places = { place } }
    end

    ---- state ----------------------------------------------------------------

    -- opts.daytime: preview another time of day's grass list
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
        if not (game and game.data) then return out end
        local okDc, dc = pcall(daycare, game)
        if okDc then out.daycare = dc else mod.log:warn("day-care state failed: %s", tostring(dc)) end
        local mapId = platform.mapId(game)
        if mapId then
            local current = L.daytime(game)
            local want = opts and DAYTIME_OK[opts.daytime] and opts.daytime or current
            out.location = { mapId = tostring(mapId), name = L.locationName(game, mapId) }
            out.dexnav = memoNav(game, tostring(mapId) .. "|" .. tostring(spoilers) .. "|" .. tostring(want),
                function() return L.mapSections(game, mapId, spoilers, { daytime = want }) end)
            -- the roaming legendaries on this route right now (save.roamers,
            -- the same test as Roamers.checkEncounter: the slot's current
            -- map), as the POKéDEX's AREA shows them; no slot, so no share.
            -- Only where the route has wild POKéMON at all.
            local okR, Roamers = pcall(require, "src.core.gen2.Roamers")
            if okR and #out.dexnav > 0 then
                local list = {}
                for _, slot in ipairs(game.save and game.save.roamers or {}) do
                    if Roamers.active(slot) and slot.map == mapId then
                        local level = tonumber(slot.level) or Roamers.LEVEL
                        list[#list + 1] = dexEntry(game, slot.species, false, level, level, spoilers)
                    end
                end
                if #list > 0 then
                    out.dexnav[#out.dexnav + 1] = { kind = "roam", label = "ROAMING", rate = false,
                        note = "ON THIS ROUTE", list = list }
                end
            end
            out.daytime = { current = current, shown = want, options = DAYTIMES,
                labels = platform.daytimeLabels() }
        end
        local screen = findBattle(game)
        if screen then out.battle = battleState(game, screen, spoilers, opts and opts.hidden) end
        return out
    end

    return L
end
