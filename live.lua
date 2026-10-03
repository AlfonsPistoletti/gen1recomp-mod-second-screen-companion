-- The LIVE tab: where the player is, what can be encountered there (a
-- DexNav) and, in battle, who the opponent is. Read-only, like snapshot.lua.
--
-- Hidden information follows the SPOILERS option: without it a trainer's
-- team shows only the mons already sent out this battle, and DexNav species
-- the player has never seen stay "???" (their id is not even sent).
--
-- Gen 1 only: Gold / Silver load live2.lua instead.
local GEN1_FIELD_DEFAULTS = "src.world.FieldDefaults"
return function(mod, sprites, platform)
    local FieldDefaults = require(GEN1_FIELD_DEFAULTS)

    local ROD_ORDER = { "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }
    local ROD_LABELS = { OLD_ROD = "OLD ROD", GOOD_ROD = "GOOD ROD", SUPER_ROD = "SUPER ROD" }
    -- the rod's item name, as the BAG shows it (a language mod's too)
    local function rodLabel(game, rod)
        local def = game.data.items and game.data.items[rod]
        return type(def) == "table" and def.name or ROD_LABELS[rod]
    end

    local function art(kind, ...)
        if not (sprites and sprites[kind]) then return false end
        local ok, id = pcall(sprites[kind], ...)
        return ok and id and ("/img/" .. id .. ".png") or false
    end

    local function findBattle(game)
        local states = game and game.stack and game.stack.states
        if not states then return nil end
        for i = #states, 1, -1 do
            if states[i].isBattleState then return states[i] end
        end
        return nil
    end

    local L = {}

    -- The phone must not run ahead of the screen: BattleState swaps
    -- enemyIndex / enemy before "BROCK sent out ONIX!" is shown. This is the
    -- same test that gates drawing the enemy HUD (BattleState draw, "enemy
    -- HUD (DrawEnemyHUDAndHPBar)"), minus its purely visual grow-in / slide.
    local function foeVisible(battle)
        return battle.enemy ~= nil and not battle.showEnemyTrainer
            and not battle.enemySendingOut and not battle.enemyHudPending
            and not battle.introBalls
    end

    -- battle table -> set of enemy mon tables sent out so far (weak both ways)
    local sentOut = setmetatable({}, { __mode = "k" })
    -- enemy mon table -> set of move ids the player has watched it use
    local knownMoves = setmetatable({}, { __mode = "k" })
    -- battle table -> moves used but not yet announced on screen
    local pendingMoves = setmetatable({}, { __mode = "k" })

    local function learnMove(mon, id)
        local set = knownMoves[mon]
        if not set then
            set = {}
            knownMoves[mon] = set
        end
        set[id] = true
    end

    local function inQueue(queue, row)
        for _, item in ipairs(queue or {}) do
            if item == row then return true end
        end
        return false
    end

    -- battle.move_used fires when the move is queued, before "ONIX used
    -- TACKLE!" is on screen. Its animation row is queued right behind that
    -- text, so the move counts as seen once the row has left the queue.
    if mod.events and mod.events.on then
        mod.events:on("battle.move_used", function(e)
            local battle, user, move = e.battle, e.user, e.move
            -- a Metronome / Mirror Move pick is not a move the foe knows
            if not (battle and user and move and move.id) or user.isPlayer or e.isCalled then return end
            local mon = user.mon
            if not mon then return end
            local row = battle.moveAnimRow
            if row and inQueue(battle.queue, row) then
                local list = pendingMoves[battle] or {}
                pendingMoves[battle] = list
                list[#list + 1] = { mon = mon, id = move.id, row = row }
            else
                learnMove(mon, move.id)
            end
        end)
    end

    -- Called every frame, so what counts as seen matches what was on screen
    -- even while no phone is polling.
    function L.track(game)
        local battle = findBattle(game)
        for b, list in pairs(pendingMoves) do
            if b ~= battle then
                pendingMoves[b] = nil
            else
                for i = #list, 1, -1 do
                    if not inQueue(b.queue, list[i].row) then
                        learnMove(list[i].mon, list[i].id)
                        table.remove(list, i)
                    end
                end
            end
        end
        local party = battle and battle.enemyParty
        local mon = party and party[battle.enemyIndex or 1]
        if not mon or not foeVisible(battle) then return end
        local seen = sentOut[battle]
        if not seen then
            seen = setmetatable({}, { __mode = "k" })
            sentOut[battle] = seen
        end
        seen[mon] = true
    end

    ---- location ----------------------------------------------------------

    -- townMap names cover interiors too (CELADON_MART_1F -> CELADON CITY)
    local function locationName(game, mapId)
        local field = game.data.field
        local locations = field and field.townMap and field.townMap.locations
        local loc = locations and locations[mapId]
        if loc and loc.name then return loc.name end
        local ok, DiscordPresence = pcall(require, "src.core.DiscordPresence")
        if ok and DiscordPresence.locationName then
            local okName, name = pcall(DiscordPresence.locationName, game, mapId)
            if okName and type(name) == "string" and name ~= "" then return name end
        end
        return (tostring(mapId):gsub("_", " "))
    end

    ---- DexNav ------------------------------------------------------------

    local function dexEntry(game, species, share, minL, maxL, spoilers)
        local dex = game.save and game.save.pokedex or {}
        local seen = dex.seen and dex.seen[species] and true or false
        local owned = dex.owned and dex.owned[species] and true or false
        local known = spoilers or seen or owned
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

    -- species -> {min, max} level over a list of { species, level } slots
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

    -- Per-species weights for a terrain. WorldAPI:effectiveEncounters applies
    -- mods' encounter.table hooks; the raw-slot fallback mirrors it.
    local function encounterDist(game, mapId, terrain, slotDef)
        local world = mod.world
        if world and world.effectiveEncounters then
            local ok, res = pcall(world.effectiveEncounters, world, mapId, terrain)
            if ok and type(res) == "table" and type(res.dist) == "table" then return res end
        end
        local chance = (tonumber(slotDef.rate) or 0) / 256
        local dist, prev = {}, 0
        local buckets = slotDef.buckets or FieldDefaults.constant(game.data, "encounterBuckets") or {}
        for i, threshold in ipairs(buckets) do
            local slot = slotDef.slots and slotDef.slots[i]
            if slot and slot.species then
                dist[slot.species] = (dist[slot.species] or 0) + (threshold - prev)
            end
            prev = threshold
        end
        return { chance = chance, dist = dist }
    end

    local function walkSection(game, mapId, key, terrain, kind, label, spoilers)
        local enc = game.data.encounters and game.data.encounters[mapId]
        local slotDef = enc and enc[key]
        if not slotDef then return nil end
        local eff = encounterDist(game, mapId, terrain, slotDef)
        if not eff or (eff.chance or 0) <= 0 then return nil end
        local total = 0
        for _, w in pairs(eff.dist) do total = total + w end
        if total <= 0 then return nil end
        local ranges = levelRanges(slotDef.slots)
        local list = {}
        for species, w in pairs(eff.dist) do
            local r = ranges[species] or {}
            list[#list + 1] = dexEntry(game, species, w / total, r.min, r.max, spoilers)
        end
        return { kind = kind, label = label, rate = eff.chance, list = sortList(list) }
    end

    -- Rods the player owns, where the map can be fished (it has a Super Rod
    -- group or a water encounter table). Picks are uniform over the pool
    -- (OverworldController rollFishingGroup), so each entry's share is
    -- count / #pool.
    local function fishingSections(game, mapId, spoilers, allRods)
        local data, save = game.data, game.save
        local superRod = data.field and data.field.superRod
        local enc = data.encounters and data.encounters[mapId]
        if not ((superRod and superRod[mapId]) or (enc and enc.water)) then return {} end
        local fishing = FieldDefaults.field(data, "fishing") or {}
        local inventory = save and save.inventory or {}
        local out = {}
        for _, rod in ipairs(ROD_ORDER) do
            local def = fishing[rod]
            if def and (allRods or inventory[rod]) then
                local pool
                if def.always then
                    pool = { def.always }
                elseif def.pool then
                    pool = def.pool
                elseif def.perMap then
                    local groups = data.field[def.perMap]
                    pool = groups and groups[mapId]
                end
                if pool and #pool > 0 then
                    local counts, order = {}, {}
                    for _, hook in ipairs(pool) do
                        if hook.species then
                            if not counts[hook.species] then order[#order + 1] = hook.species end
                            counts[hook.species] = (counts[hook.species] or 0) + 1
                        end
                    end
                    local ranges = levelRanges(pool)
                    local list = {}
                    for _, species in ipairs(order) do
                        local r = ranges[species] or {}
                        list[#list + 1] = dexEntry(game, species, counts[species] / #pool, r.min, r.max, spoilers)
                    end
                    out[#out + 1] = { kind = rod, label = rodLabel(game, rod), rate = false, list = sortList(list) }
                end
            end
        end
        return out
    end

    -- allRods: every rod, owned or not (the POKéDEX AREA list)
    local function dexnav(game, map, spoilers, allRods)
        local mapId = map.id
        local sections = {}
        -- the land table covers grass, or every tile on indoor non-forest
        -- maps (caves, towers, the Mansion) -- OverworldController's rule
        local indoor = game.data.field and game.data.field.indoorEncounters
        local def = map.def or {}
        local isIndoor = indoor and (def.index or 0) >= (indoor.firstIndoorMap or math.huge)
            and def.tileset ~= indoor.excludedTileset
        local land
        if isIndoor then
            local label = def.tileset == "CAVERN" and "CAVE" or "INDOORS"
            land = walkSection(game, mapId, "grass", "indoor", "cave", label, spoilers)
        else
            land = walkSection(game, mapId, "grass", "grass", "grass", "GRASS", spoilers)
        end
        sections[#sections + 1] = land
        sections[#sections + 1] = walkSection(game, mapId, "water", "water", "surf", "SURF", spoilers)
        for _, section in ipairs(fishingSections(game, mapId, spoilers, allRods)) do
            sections[#sections + 1] = section
        end
        return sections
    end

    -- Every wild section of one map (grass / cave, surf, all rods) with each
    -- species named, for the POKéDEX AREA list; same math as the DexNav.
    function L.mapSections(game, mapId)
        local def = game.data.maps and game.data.maps[mapId]
        return dexnav(game, { id = mapId, def = def or {} }, true, true)
    end

    L.locationName = function(game, mapId) return locationName(game, mapId) end

    ---- battle ------------------------------------------------------------

    -- HP and status as the screen shows them. The active foe's battler
    -- carries shownHP / shownStatus, which follow the HP-bar drain and the
    -- status text instead of jumping ahead to the result of the turn.
    local function shown(mon, battler)
        if battler and battler.mon == mon and type(battler.shownHP) == "number" then
            return battler.shownHP, battler.shownStatus
        end
        return mon.hp or 0, mon.status
    end

    -- BattleState:drawBallRow: empty / fainted / statused / healthy
    local function ballFrame(mon, battler)
        if not mon then return 3 end
        local hp, status = shown(mon, battler)
        if hp <= 0 then return 2 end
        if status then return 1 end
        return 0
    end

    local function monInfo(game, mon, name, battler)
        local def = game.data.pokemon[mon.species] or {}
        local stats = mon.stats or {}
        local hp, status = shown(mon, battler)
        return {
            name = name or mon.nickname or def.name or tostring(mon.species),
            level = mon.level or 0,
            hp = hp,
            maxHp = stats.hp or 0,
            status = status or false
        }
    end

    local function typeName(data, typeId)
        local types = data.type_chart and data.type_chart.types
        local record = types and types[typeId]
        return record and record.name or (tostring(typeId):gsub("_TYPE$", ""))
    end

    -- The foe's moves: all of them with SPOILERS, otherwise only the ones it
    -- has been seen using, in move-slot order (a seen move outside the
    -- slots, e.g. STRUGGLE, goes last).
    local function movesFor(data, mon, spoilers)
        local known = knownMoves[mon] or {}
        local list, listed = {}, {}
        local function add(id)
            if listed[id] then return end
            listed[id] = true
            local mdef = data.moves and data.moves[id] or {}
            list[#list + 1] = {
                name = mdef.name or tostring(id),
                type = mdef.type and typeName(data, mdef.type) or false
            }
        end
        for _, slot in ipairs(mon.moves or {}) do
            if slot.id and (spoilers or known[slot.id]) then add(slot.id) end
        end
        for id in pairs(known) do add(id) end
        return list
    end

    local function battleKind(battle)
        if type(battle.battleKind) == "function" then
            local ok, kind = pcall(battle.battleKind, battle)
            if ok and kind then return kind end
        end
        return battle.kind or "wild"
    end

    -- A SAFARI ZONE battle (BattleState:makeSafari): no POKéMON of yours
    -- fights, so what matters is the catch and the flee. For each choice
    -- of the menu, the SAFARI BALL's catch chance (Catching.chance, the
    -- exact stock odds; nil when a mod replaced the ball's roll) and the
    -- chance the foe runs this turn, worked out as safariEnemyTurn does:
    -- the BAIT / ROCK factor ticks down first, then b = 2 x SPEED,
    -- quartered while eating, doubled while angry, and it runs when
    -- SPEED > 127 or a byte rolls under b. BAIT and ROCK add 1-5 turns at
    -- random, so their flee is the average over those five.
    local function safariOdds(battle)
        local enemy = battle.enemy
        if not (battle.safari and enemy and enemy.mon and enemy.def) then return nil end
        local okC, Catching = pcall(require, "src.battle.Catching")
        local ballDef = type(battle.ballDef) == "function" and select(2, pcall(battle.ballDef, battle, "SAFARI_BALL")) or nil
        local function catch(rate)
            if not okC then return false end
            local ok, p = pcall(Catching.chance, "SAFARI_BALL", enemy.mon, enemy.def, rate,
                { ballDef = type(ballDef) == "table" and ballDef or nil, statuses = battle.data and battle.data.statuses })
            return ok and tonumber(p) and p / 100 or false
        end
        local speed = ((enemy.curStats and tonumber(enemy.curStats.speed)) or 0) % 256
        local function flee(bait, escape)
            -- PrintSafariZoneBattleText's tick, then the roll
            if bait > 0 then bait = bait - 1 elseif escape > 0 then escape = escape - 1 end
            if speed > 127 then return 1 end
            local b = (speed * 2) % 256
            if bait > 0 then b = math.floor(b / 4) end
            if escape > 0 then b = math.min(255, b * 2) end
            return b / 256
        end
        local function average(fn)
            local sum = 0
            for r = 1, 5 do sum = sum + fn(r) end
            return sum / 5
        end
        local rate = tonumber(battle.safariCatchRate) or enemy.def.catchRate or 0
        local bait, escape = tonumber(battle.baitFactor) or 0, tonumber(battle.escapeFactor) or 0
        local mood = bait > 0 and "EATING" or escape > 0 and "ANGRY" or false
        return {
            mood = mood,
            fleeHead = "RUNS",
            rate = rate,
            rows = {
                { action = "BALL", catch = catch(rate), flee = flee(bait, escape) },
                { action = "BAIT", catch = catch(math.floor(rate / 2)),
                    flee = average(function(r) return flee(math.min(255, bait + r), 0) end) },
                { action = "ROCK", catch = catch(math.min(255, rate * 2)),
                    flee = average(function(r) return flee(0, math.min(255, escape + r)) end) },
            },
        }
    end

    -- A wild battle's catch odds (SHOW HIDDEN VALUES): the species' catch
    -- rate and, for every ball in the BAG, the chance it catches the foe as
    -- it is now (BattleState:catchChance, the exact stock odds; nil when a
    -- mod replaced the roll), as the battle API lists them
    local function catchOdds(game, battle)
        local enemy = battle.enemy
        if not (enemy and enemy.def) then return nil end
        local okI, ItemEffects = pcall(require, "src.inventory.ItemEffects")
        local balls = {}
        for id, count in pairs(game.save and game.save.inventory or {}) do
            local isBall = okI and ItemEffects.isBall and select(2, pcall(ItemEffects.isBall, id))
            if (tonumber(count) or 0) > 0 and isBall then
                local def = game.data.items and game.data.items[id] or {}
                local ok, p = pcall(battle.catchChance, battle, id)
                balls[#balls + 1] = { name = def.name or tostring(id), count = count,
                    chance = ok and tonumber(p) and p / 100 or false }
            end
        end
        table.sort(balls, function(a, b) return a.name < b.name end)
        return { rate = tonumber(enemy.def.catchRate) or false, balls = balls }
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

    -- Gen 1: everything sits on the battler and a switch clears it
    -- (REFLECT, LIGHT SCREEN and MIST have no countdown: they last until
    -- then). WRAP and co. are counted on the one using them: the badge goes
    -- on the POKéMON held.
    local function moveLabel(data, id)
        local d = id ~= nil and data.moves and data.moves[id]
        return d and d.name or (id ~= nil and tostring(id):gsub("_", " ")) or "?"
    end
    local function battlerEffects(data, b, foe, hidden)
        local list, add = badgeList(hidden)
        if b.reflect then add("REFLECT") end
        if b.lightScreen then add("LIGHT SCREEN") end
        if b.mist then add("MIST") end
        if b.focusEnergy then add("FOCUS ENERGY") end
        if b.leechSeeded then add("LEECH SEED") end
        -- the next poison hit, in sixteenths of max HP (Status.lua)
        if positive(b.toxicCounter) then add("TOXIC", b.toxicCounter .. "/16") end
        if positive(b.confusedTurns) then add("CONFUSED", b.confusedTurns, true) end
        if positive(b.substituteHP) then add("SUBSTITUTE", b.substituteHP .. "HP", true) end
        if b.disabledSlot then
            local mv = (b.curMoves or (b.mon and b.mon.moves) or {})[b.disabledSlot]
            add(moveLabel(data, type(mv) == "table" and mv.id or mv) .. " DISABLED", b.disabledTurns, true)
        end
        if foe and positive(foe.trappingTurns) then add(moveLabel(data, foe.trapMove), foe.trappingTurns, true) end
        if positive(b.thrashTurns) then add(b.thrashMove and moveLabel(data, b.thrashMove) or "THRASH", b.thrashTurns, true) end
        if positive(b.bideTurns) then add("BIDE", b.bideTurns, true) end
        if b.rageMove then add("RAGE") end
        if b.mustRecharge then add("RECHARGE") end
        return #list > 0 and list or false
    end

    local function battleState(game, battle, spoilers, hidden)
        local data = game.data
        local ghost = battle.ghost and not battle.scopeReveal
        local out = {
            kind = battleKind(battle),
            title = "WILD POKéMON",
            trainerPic = false,
            size = 0,
            balls = false,
            ballSheet = false,
            team = {},
            active = false
        }
        if battle.trainer then
            out.title = battle.trainer.name or tostring(battle.oppClass)
            out.trainerPic = art("trainer", data, battle)
        elseif battle.opponentName then
            out.title = battle.opponentName
        end

        out.spoilers = spoilers
        local battler = battle.enemy
        -- during a trainer's send-out the incoming foe is not on screen yet
        local visible = foeVisible(battle)
        local party = battle.enemyParty
        if party then
            local seen = sentOut[battle] or {}
            out.size = #party
            out.ballSheet = art("balls", data)
            out.balls = {}
            for i = 1, 6 do out.balls[i] = ballFrame(party[i], battler) end
            for i, mon in ipairs(party) do
                local active = visible and i == battle.enemyIndex
                local revealed = spoilers or active or seen[mon]
                local entry = { slot = i, active = active, revealed = revealed and true or false,
                    ball = ballFrame(mon, battler) }
                if revealed then
                    for k, v in pairs(monInfo(game, mon, nil, battler)) do entry[k] = v end
                    entry.icon = art("icon", data, mon)
                    entry.moves = movesFor(data, mon, spoilers)
                end
                out.team[i] = entry
            end
        end

        local enemy = battler and battler.mon
        -- a wild foe is on screen from the start; a trainer's only once sent out
        if enemy and (visible or not party) then
            if ghost then
                -- the SILPH SCOPE hides the species in the game as well
                local hp = shown(enemy, battler)
                out.active = { name = "GHOST", level = false, hp = hp,
                    maxHp = (enemy.stats or {}).hp or 0, status = false, front = false, owned = false, moves = {} }
            else
                out.active = monInfo(game, enemy, battler.name, battler)
                out.active.front = art("front", data, enemy)
                out.active.moves = movesFor(data, enemy, spoilers)
                local dex = game.save and game.save.pokedex or {}
                out.active.owned = dex.owned and dex.owned[enemy.species] and true or false
            end
        end
        -- the player's POKéMON in the fight: its party slot (the battler's
        -- mon is the party's own table)
        local mine = battle.player and battle.player.mon
        for i, m in ipairs(game.save and game.save.party or {}) do
            if mine and m == mine and not battle.safari then out.playerSlot = i end
        end
        -- its card (HP as the HUD shows it) and both sides' stat changes
        -- (none in a SAFARI ZONE battle: no POKéMON is sent out there)
        if mine and not battle.safari then
            out.player = monInfo(game, mine, battle.player.name, battle.player)
            out.player.icon = art("icon", data, mine)
            -- its front pic: the HANDS-OFF view draws it facing the foe
            out.player.front = art("front", data, mine)
            out.player.stages = stagesOf(battle.player.stages)
        end
        if out.active and battler then out.active.stages = stagesOf(battler.stages) end
        -- multi-turn effects on each side's POKéMON
        if out.player and battle.player then
            out.player.effects = battlerEffects(data, battle.player, battler, hidden)
        end
        if out.active and battler and not ghost then
            out.active.effects = battlerEffects(data, battler, battle.player, hidden)
        end
        if hidden and battle.safari then
            local ok, odds = pcall(safariOdds, battle)
            out.safari = ok and odds or false
        elseif hidden and not battle.trainer and not battle.demo and not ghost and out.active then
            local ok, odds = pcall(catchOdds, game, battle)
            out.catch = ok and odds or false
        end
        return out
    end

    ---- DAY-CARE / SAFARI ---------------------------------------------------

    -- ROUTE 5's DAY-CARE (save.daycare = { mon, steps, depositLevel }): the
    -- level the POKéMON will have when picked up, the levels it grew and
    -- the fee, worked out as the gentleman does (story2.lua's withdraw,
    -- scripts/Daycare.asm): the stored exp plus 1 per step, capped at 100,
    -- against the level it was left at; ¥100 plus ¥100 per level
    local function daycare(game)
        local dc = game.save and game.save.daycare
        local mon = type(dc) == "table" and dc.mon
        if type(mon) ~= "table" then return false end
        local def = game.data.pokemon and game.data.pokemon[mon.species] or {}
        local start = tonumber(dc.depositLevel) or tonumber(mon.level) or 1
        local level = start
        local okG, Growth = pcall(require, "src.pokemon.Growth")
        if okG and Growth.levelForExp then
            local ok, lv = pcall(Growth.levelForExp, def.growthRate, (tonumber(mon.exp) or 0) + (tonumber(dc.steps) or 0))
            if ok and tonumber(lv) then level = math.max(start, math.min(100, lv)) end
        end
        local grown = level - start
        return { places = { { name = "ROUTE 5", mons = { {
            name = mon.nickname or def.name or tostring(mon.species),
            icon = art("icon", game.data, mon),
            level = level, gained = grown, fee = 100 + 100 * grown,
        } } } } }
    end

    -- In the SAFARI ZONE (save.safari = { balls, steps }; the steps count
    -- down, safari_game.asm): the SAFARI BALLS and steps left
    local function safari(game)
        local st = game.save and game.save.safari
        if type(st) ~= "table" then return false end
        local def = game.data.items and game.data.items.SAFARI_BALL
        return { balls = tonumber(st.balls) or 0, steps = tonumber(st.steps) or 0,
            ballName = type(def) == "table" and def.name or "SAFARI BALL", ballIcon = false,
            -- Gen 1 has no item icons: the battle's party-ball sheet instead
            ballSheet = art("balls", game.data) }
    end

    ---- state -------------------------------------------------------------

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
        local okSf, sf = pcall(safari, game)
        if okSf then out.safari = sf end
        local map = game.overworld and game.overworld.map
        if map and map.id then
            out.location = { mapId = tostring(map.id), name = locationName(game, map.id) }
            out.dexnav = memoNav(game, tostring(map.id) .. "|" .. tostring(spoilers),
                function() return dexnav(game, map, spoilers) end)
        end
        local battle = findBattle(game)
        if battle then out.battle = battleState(game, battle, spoilers, opts and opts.hidden) end
        return out
    end

    return L
end
