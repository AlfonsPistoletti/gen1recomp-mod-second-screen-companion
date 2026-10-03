-- Turns the live save into the plain table /state serves as JSON. Battlers
-- hold the same mon tables as game.save.party, so HP, PP and status changes
-- during a fight show up here without any battle-specific code.
return function(mod, sprites, uids, platform)
    local Stats = require("src.pokemon.Stats")

    -- The stats each generation shows, in summary-screen order. Gen 2 split
    -- SPECIAL into SPCL.ATK / SPCL.DEF.
    local STATS_GEN1 = {
        { "attack", "ATTACK" }, { "defense", "DEFENSE" }, { "speed", "SPEED" }, { "special", "SPECIAL" }
    }
    local STATS_GEN2 = {
        { "attack", "ATTACK" }, { "defense", "DEFENSE" }, { "specialAttack", "SPCL.ATK" },
        { "specialDefense", "SPCL.DEF" }, { "speed", "SPEED" }
    }

    -- Gold's PACK pockets, in its tab order (src/ui/gen2/PackMenu.lua)
    local POCKETS = {
        { id = "ITEM", label = "ITEMS" }, { id = "BALL", label = "POKé BALLS" },
        { id = "KEY_ITEM", label = "KEY ITEMS" }, { id = "TM_HM", label = "TM/HM" }
    }

    -- art is optional: a sprite that cannot resolve only loses its image
    local function imageUrl(kind, data, mon)
        if not (sprites and sprites[kind]) then return false end
        local ok, id = pcall(sprites[kind], data, mon)
        return ok and id and ("/img/" .. id .. ".png") or false
    end

    local function animUrl(data, mon)
        if not (sprites and sprites.frontAnim) then return false end
        local ok, id = pcall(sprites.frontAnim, data, mon)
        return ok and id and ("/anim/" .. id) or false
    end

    local function typeName(data, typeId)
        local types = data.type_chart and data.type_chart.types
        local record = types and types[typeId]
        return record and record.name or tostring(typeId):gsub("_TYPE$", "")
    end

    local function typeEntry(data, typeId)
        if typeId == nil then return nil end
        return { id = tostring(typeId), name = typeName(data, typeId) }
    end

    local function itemName(data, id)
        local def = data.items and data.items[id]
        return def and def.name or (tostring(id):gsub("_", " "))
    end

    local function isEgg(mon)
        return mon.isEgg == true or mon.egg == true or mon.species == "EGG"
    end

    local function shiny(mon)
        if mon.shiny ~= nil then return mon.shiny and true or false end
        local ok, result = pcall(Stats.isShiny, mon.dvs)
        return ok and result and true or false
    end

    ---- hidden values (the SHOW HIDDEN VALUES option) -----------------------

    -- Gen 1-only module, named through a constant (see platform.lua)
    local GEN1_PIKACHU_FOLLOWER = "src.world.PikachuFollower"
    local STAT_ROWS = { { "hp", "HP" }, { "attack", "ATTACK" }, { "defense", "DEFENSE" },
        { "speed", "SPEED" }, { "special", "SPECIAL" } }
    local TIMES = { "MORN", "DAY", "NITE" } -- caughtTime 1..3

    local function num(v) return math.floor(tonumber(v) or 0) end

    -- the HP DV is not stored: it's the low bit of the other four
    -- (Gen 2 Mon.hpDV; Gen 1 works the same)
    local function hpDv(dvs)
        return num(dvs.attack) % 2 * 8 + num(dvs.defense) % 2 * 4
            + num(dvs.speed) % 2 * 2 + num(dvs.special) % 2
    end

    -- Gen 2: HiddenPowerDamage's type and power, from the engine's own routine
    local function hiddenPowerOf(data, mon)
        local ok, Battle = pcall(require, "src.battle.gen2.Battle")
        if not (ok and type(Battle) == "table" and Battle.hiddenPower) then return nil end
        local okH, power, typeId = pcall(Battle.hiddenPower, nil, mon)
        if not (okH and power and typeId) then return nil end
        return { type = typeName(data, typeId), power = power }
    end

    local function hiddenValues(game, data, mon, def)
        local dvs = type(mon.dvs) == "table" and mon.dvs or {}
        local exp = type(mon.statExp) == "table" and mon.statExp or {}
        local rows = {}
        for _, s in ipairs(STAT_ROWS) do
            local key = s[1]
            local dv = key == "hp" and hpDv(dvs) or num(dvs[key] or (key == "special" and dvs.specialAttack))
            local se = num(exp[key] or (key == "special" and exp.specialAttack))
            rows[#rows + 1] = { label = s[2], dv = dv, statExp = se }
        end
        local out = { stats = rows }
        if platform.isGen2(game) then
            out.hiddenPower = hiddenPowerOf(data, mon)
            -- happiness, and whether this species evolves by it (at 220)
            local happy = { value = num(mon.happiness) }
            for _, evo in ipairs(def.evolutions or {}) do
                if type(evo) == "table" and evo.method == "EVOLVE_HAPPINESS" then happy.evolvesAt = 220 end
            end
            out.happiness = happy
            -- Pokérus: high nybble strain, low nybble days left; a strain
            -- with no days left is cured (and still doubles Stat Exp)
            local pkrs = num(mon.pokerus)
            if pkrs == 0 then
                out.pokerus = "never"
            elseif pkrs % 16 > 0 then
                out.pokerus = { infected = pkrs % 16 }
            else
                out.pokerus = "cured"
            end
        else
            -- Yellow: the friendship of your own PIKACHU. Only a Yellow save
            -- carries pikachuHappiness, so its presence is the test
            local happiness = game.save and game.save.pikachuHappiness
            local okP, Follower = pcall(require, GEN1_PIKACHU_FOLLOWER)
            if happiness ~= nil and okP and Follower.isStarterPikachu
                and Follower.isStarterPikachu(game.save, mon) then
                out.friendship = num(happiness)
            end
        end
        return out
    end

    -- Crystal: where, when and at which level it was caught (the summary
    -- screen's MET line); nil on every other game or without the data
    local function caughtData(data, mon)
        -- the engine's own test: only Crystal stores catch data
        local okM, Mon = pcall(require, "src.battle.gen2.Mon")
        if not (okM and Mon.hasCaughtData and Mon.hasCaughtData()) then return nil end
        local level, time, loc = num(mon.caughtLevel), num(mon.caughtTime), num(mon.caughtLocation)
        if level == 0 and time == 0 and loc == 0 then return nil end
        local place
        if Mon.LANDMARK_GIFT and loc == Mon.LANDMARK_GIFT then
            place = "GIFT"
        elseif Mon.LANDMARK_EVENT and loc == Mon.LANDMARK_EVENT then
            place = "EVENT"
        elseif loc > 0 then
            local records = data.gen2Landmarks and data.gen2Landmarks.landmarks or {}
            for _, record in pairs(records) do
                if type(record) == "table" and tonumber(record.index) == loc then
                    place = tostring(record.name or ""):gsub("\n", " ")
                    break
                end
            end
        end
        return { level = level > 0 and level or nil, time = TIMES[time] and platform.daytimeLabel(TIMES[time]),
            place = place }
    end

    local function monEntry(game, data, mon, opts)
        opts = opts or {}
        local def = data.pokemon[mon.species] or {}
        if isEgg(mon) then
            return { name = "EGG", species = "EGG", egg = true, level = false, hp = 0, maxHp = 0,
                status = false, shiny = false, front = false, icon = imageUrl("icon", data, mon),
                types = {}, statList = {}, moves = {}, item = false }
        end

        local types = {}
        local seen = {}
        for _, typeId in ipairs(def.types or {}) do
            -- single-typed species list their type twice
            if not seen[typeId] then
                seen[typeId] = true
                types[#types + 1] = typeEntry(data, typeId)
            end
        end

        local moves = {}
        for _, slot in ipairs(mon.moves or {}) do
            local id = type(slot) == "table" and slot.id or slot
            local mdef = data.moves[id] or {}
            local basePP = mdef.pp or 0
            moves[#moves + 1] = {
                name = mdef.name or tostring(id),
                type = typeEntry(data, mdef.type),
                pp = type(slot) == "table" and slot.pp or 0,
                maxPP = basePP + (type(slot) == "table" and slot.ppUps or 0) * math.floor(basePP / 5)
            }
            -- SHOW HIDDEN VALUES: HIDDEN POWER's real type and power
            if opts.hidden and id == "HIDDEN_POWER" and platform.isGen2(game) then
                local hp = hiddenPowerOf(data, mon)
                if hp then moves[#moves].hiddenType, moves[#moves].hiddenPower = hp.type, hp.power end
            end
        end

        local stats = mon.stats or {}
        local statList = {}
        for _, s in ipairs(platform.isGen2(game) and STATS_GEN2 or STATS_GEN1) do
            statList[#statList + 1] = { label = s[2], value = stats[s[1]] or 0 }
        end
        local item = false
        if mon.item and mon.item ~= 0 and mon.item ~= "" then
            item = { id = tostring(mon.item), name = itemName(data, mon.item) }
        end
        return {
            name = mon.nickname or def.name or tostring(mon.species),
            species = def.name or tostring(mon.species),
            level = mon.level or 0,
            hp = mon.hp or 0,
            maxHp = stats.hp or mon.maxHp or 0,
            status = mon.status or false,
            shiny = shiny(mon),
            gender = (mon.gender == "male" or mon.gender == "female") and mon.gender or false,
            front = imageUrl("front", data, mon),
            -- Crystal: the front pic's animation, played when DETAILS opens
            anim = animUrl(data, mon),
            icon = imageUrl("icon", data, mon),
            -- Gen 2: the party menu's held-item marker (mail or item)
            held = imageUrl("held", data, mon),
            types = types,
            -- kept for pages that still read the Gen 1 fields
            stats = {
                attack = stats.attack or 0,
                defense = stats.defense or 0,
                speed = stats.speed or 0,
                special = stats.special or 0
            },
            statList = statList,
            item = item,
            moves = moves,
            -- SHOW HIDDEN VALUES: DVs, Stat Exp and the rest (nil when off)
            hidden = opts.hidden and hiddenValues(game, data, mon, def) or nil,
            -- Crystal: the summary screen's MET data
            caught = platform.isGen2(game) and caughtData(data, mon) or nil
        }
    end

    -- Bag order as the BAG menu shows it (src/inventory/Bag.lua Bag.order),
    -- recomputed read-only: Bag.order itself writes save.bagOrder, and the
    -- phone must never be the thing that changes a save.
    local function isBadge(id)
        return type(id) == "string" and id:find("BADGE", 1, true) ~= nil
    end

    local function bagOrder(save, items)
        local inventory = save.inventory or {}
        local order, seen = {}, {}
        -- same two cases as Bag.order: no stored order sorts by item index;
        -- a stored one keeps its ids and appends the rest in table order
        if not save.bagOrder then
            for id in pairs(inventory) do
                if not isBadge(id) then order[#order + 1] = id end
            end
            local function index(id)
                local def = items[id]
                local i = def and (def.index or def.itemId)
                return type(i) == "number" and i or math.huge
            end
            table.sort(order, function(a, b)
                local ia, ib = index(a), index(b)
                if ia ~= ib then return ia < ib end
                return tostring(a) < tostring(b)
            end)
            return order
        end
        for _, id in ipairs(save.bagOrder) do
            if inventory[id] and not seen[id] then
                seen[id] = true
                order[#order + 1] = id
            end
        end
        for id in pairs(inventory) do
            if not isBadge(id) and not seen[id] then order[#order + 1] = id end
        end
        return order
    end

    local function itemEntry(data, save, id, gen2)
        local items = data.items or {}
        local def = items[id] or {}
        local entry = { id = tostring(id), name = def.name or (tostring(id):gsub("_", " ")) }
        if gen2 then
            -- Gold: KEY ITEMs and HMs show no count (engine/items/pack.asm,
            -- tmhm.asm:390); a TM row reads as its number and its move
            local pocket = def.pocket or "ITEM"
            local hm = tostring(id):sub(1, 3) == "HM_"
            local key = pocket == "KEY_ITEM" or hm
            entry.pocket = pocket
            entry.key = key
            -- GIVE TO HOLD: what the game's GIVE accepts (HeldItemMenu:canHold:
            -- not a KEY ITEM, tossable), minus MAIL, which needs a letter
            local okMail, Mail = pcall(require, "src.core.gen2.Mail")
            local mail = okMail and Mail.isMail(id)
            entry.hold = (pocket ~= "KEY_ITEM" and def.canToss ~= false and not mail) or nil
            entry.count = not key and (save.inventory[id] or 0) or false
            if def.teaches then
                local mdef = data.moves and data.moves[def.teaches]
                entry.machine = def.tmLabel or def.name
                entry.move = mdef and mdef.name or tostring(def.teaches)
                entry.sortKey = tonumber(def.tmNumber) or (1000 + (tonumber(def.index) or 0))
            end
            return entry
        end
        -- Gen 1: key items and HMs print no quantity (PrintListMenuEntries)
        local machine = def.machine
        local key = def.keyItem or tostring(id):find("^HM_") ~= nil
        entry.count = not key and (save.inventory[id] or 0) or false
        entry.key = key and true or false
        if machine then
            local mdef = data.moves and data.moves[machine.move]
            entry.machine = ("%s%02d"):format(machine.kind or "TM", machine.number or 0)
            entry.move = mdef and mdef.name or tostring(machine.move)
        end
        return entry
    end

    local function bagEntry(game, data, save)
        local items = data.items or {}
        local gen2 = platform.isGen2(game)
        local list, raw = {}, {}
        for _, id in ipairs(bagOrder(save, items)) do
            list[#list + 1] = itemEntry(data, save, id, gen2)
            raw[#raw + 1] = tostring(id)
        end
        -- order: the bag's own order (the list below may regroup it), for
        -- the SORT's UNDO
        local bag = { money = platform.money(save), items = list, order = raw }
        if gen2 then
            -- the TM/HM pocket is always listed by number
            local tms = {}
            for _, e in ipairs(list) do
                if e.pocket == "TM_HM" then tms[#tms + 1] = e end
            end
            table.sort(tms, function(a, b)
                if (a.sortKey or 0) ~= (b.sortKey or 0) then return (a.sortKey or 0) < (b.sortKey or 0) end
                return a.id < b.id
            end)
            local rest = {}
            for _, e in ipairs(list) do
                if e.pocket ~= "TM_HM" then rest[#rest + 1] = e end
            end
            for _, e in ipairs(tms) do rest[#rest + 1] = e end
            for _, e in ipairs(rest) do e.sortKey = nil end
            bag.items = rest
            bag.pockets = {}
            for _, p in ipairs(POCKETS) do
                bag.pockets[#bag.pockets + 1] = { id = p.id, label = p.label, fixed = p.id == "TM_HM" }
            end
        end
        return bag
    end

    -- Bill's PC: every box, boxed mons as light rows. Box mons can lack
    -- stats (BoxMenu calls Stats.ensure on withdraw), so nothing here needs
    -- them, and nothing here writes to the save.
    local function pcEntry(game, data, save)
        local boxes, names = {}, {}
        local source = platform.boxes(save)
        for b = 1, platform.BOX_COUNT do
            local list = {}
            for _, mon in ipairs(source[b] or {}) do
                local def = data.pokemon[mon.species] or {}
                local egg = isEgg(mon)
                local row = {
                    uid = uids.of(mon),
                    name = egg and "EGG" or (mon.nickname or def.name or tostring(mon.species)),
                    species = egg and "EGG" or (def.name or tostring(mon.species)),
                    level = not egg and (mon.level or 0) or false,
                    egg = egg or nil,
                    icon = imageUrl("icon", data, mon)
                }
                if not egg and mon.item and mon.item ~= 0 and mon.item ~= "" then
                    row.item = itemName(data, mon.item)
                    row.held = imageUrl("held", data, mon)
                end
                list[#list + 1] = row
            end
            boxes[b] = list
            names[b] = platform.boxName(save, b)
        end
        return { current = save.currentBox or 1, capacity = platform.BOX_CAPACITY, boxes = boxes,
            names = platform.isGen2(game) and names or nil }
    end

    -- opts.hidden: the SHOW HIDDEN VALUES option
    -- opts.noPc: without the PC (main.lua sends it only when it changed);
    -- opts.pcOnly: the PC alone, as { pc = ... }
    return function(game, opts)
        opts = opts or {}
        local party = {}
        local bag = { money = 0, items = {} }
        local pc = { current = 1, capacity = platform.BOX_CAPACITY, boxes = {} }
        local save = game and game.save
        if opts.pcOnly then
            if save and game.data then pc = pcEntry(game, game.data, save) end
            return { pc = pc }
        end
        -- opts.monUid: one POKéMON's full card (party or box), for the PC's
        -- POKéMON sheet: { mon = ... }
        if opts.monUid then
            if not (save and game.data) then return {} end
            local found
            for _, m in ipairs(save.party or {}) do
                if uids.of(m) == opts.monUid then found = m end
            end
            if not found then
                for _, box in pairs(platform.boxes(save)) do
                    for _, m in ipairs(box) do
                        if uids.of(m) == opts.monUid then found = m end
                    end
                end
            end
            if not found then return {} end
            local entry = monEntry(game, game.data, found, opts)
            entry.uid = opts.monUid
            return { mon = entry }
        end
        if save and game.data then
            for i, mon in ipairs(save.party or {}) do
                local entry = monEntry(game, game.data, mon, opts)
                -- which mon this card is, for a SWITCH from the phone
                entry.uid, entry.slot = uids.of(mon), i
                party[#party + 1] = entry
            end
            bag = bagEntry(game, game.data, save)
        end
        return { gen = platform.gen(game), party = party, bag = bag }
    end
end
