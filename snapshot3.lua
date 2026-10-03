-- Gen 3 (FireRed / LeafGreen) twin of snapshot.lua: the live session as
-- the plain table /state serves. Same shape as the Game Boy games' (party,
-- bag, pc), plus what Gen 3 adds to a POKéMON: its nature (and which stats
-- it raises and lowers), its ability, IVs / EVs instead of DVs / Stat Exp,
-- and the summary screen's TRAINER MEMO. Nothing here writes to the save.
return function(mod, sprites, uids, platform)
    local Pokemon = require("src.core.game3.pokemon")
    local SummaryData = require("src.core.game3.summary_data")
    local ItemsData = require("src.core.game3.items_data")
    local Types = require("src.core.game3.battle.types")

    local function num(v) return math.floor(tonumber(v) or 0) end

    -- Emerald's TRAINER MEMO (pokemon_summary_screen.c:3116, drawn inline by
    -- src/ui/game3/rse/summary_menu.lua): its own texts, e.g.
    -- gText_XNatureMetAtYZ " nature,\nmet at {LV_2},\n." with the nature,
    -- the level and the met section filled in. Returned as the shared
    -- formatTrainerMemo's lines, without the nature (the card shows it).
    -- Defined below try (it uses it).
    local rseMemo

    local function try(fn, ...)
        local ok, a, b = pcall(fn, ...)
        if ok then return a, b end
        return nil
    end
    function rseMemo(mon, session)
        local okR, RomText = pcall(require, "src.core.game3.rom_text")
        local okM, Mapsec = pcall(require, "src.ui.game3.rse.mapsec")
        if not okR then return nil end
        local sec = tonumber(mon.metLocation)
        local secName = okM and sec and try(Mapsec.name, sec) or nil
        if secName == "" then secName = nil end
        local level = tonumber(mon.metLevel) or 0
        local otName = tostring(mon.otName or mon.ot or "")
        local own = otName == tostring(session and (session.name or session.playerName) or "")
            and ((tonumber(mon.otId) or 0) % 65536) == ((tonumber(session and session.trainerId) or 0) % 65536)
        local key
        if own then
            if level == 0 then key = secName and "gText_XNatureHatchedAtYZ" or "gText_XNatureHatchedSomewhereAt"
            else key = secName and "gText_XNatureMetAtYZ" or "gText_XNatureMetSomewhereAt" end
        else
            key = secName and "gText_XNatureProbablyMetAt" or "gText_XNatureObtainedInTrade"
        end
        local text = try(RomText.plain, key)
        if type(text) ~= "string" then return nil end
        -- the nature's slot leads the text; the level and the section are
        -- the dynamic slots after {LV_2} and before the closing "."
        text = text:gsub("^%s*[^\n]-nature,%s*", "")
        text = text:gsub("{LV_2}", "Lv." .. (level == 0 and 5 or level))
        if secName then text = text:gsub(",%s*%.%s*$", ", " .. secName .. ".") end
        text = text:gsub("%s*\n%s*", " "):gsub("^%l", string.upper)
        return { text }
    end

    -- art is optional: a sprite that cannot resolve only loses its image
    local function imageUrl(kind, mon)
        if not (sprites and sprites[kind]) then return false end
        local id = try(sprites[kind], nil, mon)
        return id and ("/img/" .. id .. ".png") or false
    end

    ---- types --------------------------------------------------------------

    -- type id -> "FIRE" (the page's colour classes key on the English id)
    local TYPE_KEY = {}
    for key, id in pairs(Types.ID or {}) do TYPE_KEY[id] = key end

    -- a picture of the game's own (sprites3.lua), as a page URL
    local function artUrl(kind, ...)
        if not (sprites and sprites[kind]) then return false end
        local id = try(sprites[kind], ...)
        return id and ("/img/" .. id .. ".png") or false
    end

    -- a type's id, name and the summary screen's badge for it
    local function typeEntry(t)
        if t == nil then return nil end
        local id = tonumber(t) or (Types.ID or {})[tostring(t):upper()]
        if id == nil then return { id = tostring(t), name = tostring(t) } end
        local name = try(Types.name, id) or TYPE_KEY[id] or tostring(id)
        return { id = TYPE_KEY[id] or tostring(id), name = name, badge = artUrl("typeBadge", id) }
    end

    local function speciesTypes(sp)
        local out, seen = {}, {}
        for _, t in ipairs(try(Pokemon.types, sp) or {}) do
            -- single-typed species list their type twice
            if not seen[t] then
                seen[t] = true
                out[#out + 1] = typeEntry(t)
            end
        end
        return out
    end

    ---- nature, stats ------------------------------------------------------

    -- summary-screen order and labels (pokefirered sStatNames), each with
    -- the key natureStatModifier and the mon table use
    local STATS = {
        { mon = "attack", nature = "atk", label = "ATTACK" },
        { mon = "defense", nature = "def", label = "DEFENSE" },
        { mon = "spAtk", nature = "spAtk", label = "SP. ATK" },
        { mon = "spDef", nature = "spDef", label = "SP. DEF" },
        { mon = "speed", nature = "spd", label = "SPEED" },
    }

    local function natureOf(mon)
        local id = Pokemon.natureId(mon.personality)
        local name = try(function() return SummaryData.NATURES[id] end)
        local out = { id = id, name = type(name) == "string" and name or ("NATURE " .. id) }
        for _, s in ipairs(STATS) do
            local m = SummaryData.natureStatModifier(id, s.nature)
            if m > 1 then out.up = s.label elseif m < 1 then out.down = s.label end
        end
        return out
    end

    -- A boxed mon may carry no computed stats: work them out the game's way
    local function statsOf(mon, sp)
        if mon.maxHp and mon.attack then
            return { maxHp = mon.maxHp, attack = mon.attack, defense = mon.defense,
                speed = mon.speed, spAtk = mon.spAtk, spDef = mon.spDef }
        end
        return try(Pokemon.calcStats, sp, mon.level, mon.ivs, mon.evs, mon.personality) or {}
    end

    ---- moves --------------------------------------------------------------

    local function ppUps(mon, slot)
        if type(mon.ppBonuses) == "table" then return num(mon.ppBonuses[slot]) end
        if type(mon.ppBonusesPacked) == "number" then
            return math.floor(mon.ppBonusesPacked / 4 ^ (slot - 1)) % 4
        end
        return 0
    end

    -- pokefirered/include/constants/moves.h MOVE_HIDDEN_POWER
    local MOVE_HIDDEN_POWER = 237

    -- HIDDEN POWER's type and power from the IVs, by the engine's own routine
    local function hiddenPowerOf(mon)
        local okD, Damage = pcall(require, "src.core.game3.battle.damage")
        if not (okD and type(Damage) == "table" and Damage.hiddenPower) then return nil end
        local ok, power, t = pcall(Damage.hiddenPower, mon)
        if not (ok and power) then return nil end
        local te = typeEntry(t)
        return { type = te and te.name or tostring(t), badge = te and te.badge or false, power = power }
    end

    local function movesOf(mon, hidden)
        local out = {}
        for slot = 1, 4 do
            local id = Pokemon.moveIdAt(mon, slot)
            if id and id > 0 then
                local row = try(Pokemon.battleMove, id) or {}
                local base = tonumber(row.pp) or try(Pokemon.movePp, id) or 0
                local maxPP = (type(mon.maxPp) == "table" and tonumber(mon.maxPp[slot]))
                    or (base + math.floor(base / 5) * ppUps(mon, slot))
                local pp = type(mon.pp) == "table" and tonumber(mon.pp[slot])
                    or (type(mon.moves[slot]) == "table" and tonumber(mon.moves[slot].pp)) or maxPP
                local entry = {
                    name = try(Pokemon.moveName, id) or ("MOVE " .. id),
                    type = typeEntry(row.type),
                    pp = pp, maxPP = maxPP
                }
                -- SHOW HIDDEN VALUES: HIDDEN POWER's real type and power
                if hidden and (id == MOVE_HIDDEN_POWER or row.effect == "HIDDEN_POWER") then
                    local hp = hiddenPowerOf(mon)
                    if hp then
                        entry.hiddenType, entry.hiddenPower, entry.hiddenBadge = hp.type, hp.power, hp.badge
                    end
                end
                out[#out + 1] = entry
            end
        end
        return out
    end

    ---- hidden values (the SHOW HIDDEN VALUES option) -----------------------

    local IV_ROWS = {
        { "hp", "HP" }, { "atk", "ATTACK" }, { "def", "DEFENSE" },
        { "spa", "SP. ATK" }, { "spd", "SP. DEF" }, { "spe", "SPEED" }
    }

    local function hiddenValues(mon, sp)
        local ivs = type(mon.ivs) == "table" and mon.ivs or {}
        -- read as stored (Pokemon.evsOf would fill in and write mon.evs)
        local evs = type(mon.evs) == "table" and mon.evs or {}
        local rows, evTotal = {}, 0
        for _, r in ipairs(IV_ROWS) do
            local ev = num(evs[r[1]])
            evTotal = evTotal + ev
            rows[#rows + 1] = { label = r[2], iv = num(ivs[r[1]]), ev = ev }
        end
        local out = { ivs = rows, evTotal = evTotal, evMax = Pokemon.MAX_TOTAL_EVS or 510 }
        out.hiddenPower = hiddenPowerOf(mon)

        -- friendship, and whether this species evolves by it (at 220)
        local happy = { value = num(try(Pokemon.friendshipOf, mon) or mon.friendship or mon.happiness) }
        -- EVO_FRIENDSHIP, _DAY, _NIGHT (pokefirered/include/constants/pokemon.h:266)
        for _, evo in ipairs(try(Pokemon.evolutions, sp) or {}) do
            local method = type(evo) == "table" and tonumber(evo.method or evo[1]) or 0
            if method >= 1 and method <= 3 then happy.evolvesAt = 220 end
        end
        out.happiness = happy

        -- Pokérus: high nybble strain, low nybble days left; a strain with
        -- no days left is cured (and still doubles EV gains)
        local pkrs = num(mon.pokerus)
        if pkrs == 0 then
            out.pokerus = "never"
        elseif pkrs % 16 > 0 then
            out.pokerus = { infected = pkrs % 16 }
        else
            out.pokerus = "cured"
        end
        return out
    end

    ---- one POKéMON ---------------------------------------------------------

    local STATUS = { [1] = "PSN", [2] = "PAR", [3] = "SLP", [4] = "FRZ", [5] = "BRN" }

    local function genderOf(mon, sp)
        local g = mon.gender
        if g == nil then g = try(Pokemon.gender, sp, mon.personality) end
        if g == "M" or g == "male" then return "male" end
        if g == "F" or g == "female" then return "female" end
        return false
    end

    local function itemOf(mon)
        local id = mon.item or mon.heldItem
        if not id or id == 0 or id == "" then return false end
        return { id = tostring(id), name = try(ItemsData.displayName, id) or tostring(id),
            icon = artUrl("itemIcon", id) }
    end

    ---- Emerald: CONDITION, RIBBONS, POKéBLOCKS ---------------------------

    -- the five conditions and sheen (pokemon.h MON_DATA_COOL .. SHEEN, kept
    -- in mon.contest as evolution.lua reads them), in the order the game's
    -- condition graph names them; each with its category's badge
    local CONDITIONS = { { "cool", 0 }, { "beauty", 1 }, { "cute", 2 }, { "smart", 3 }, { "tough", 4 } }
    local function conditionOf(mon)
        local c = type(mon.contest) == "table" and mon.contest or {}
        local out = { sheen = num(c.sheen or mon.sheen), max = 255, list = {} }
        for _, k in ipairs(CONDITIONS) do
            out.list[#out.list + 1] = { id = k[1], value = num(c[k[1]] or mon[k[1]]), badge = artUrl("categoryBadge", k[2]) }
        end
        return out
    end

    -- the PokeNav's ribbon data (pokenav_ribbons_summary.c; the manifest
    -- src/ui/game3/rse/pokenav/condition.lua loads): which bits are which
    -- ribbons, their pictures and their two description lines
    local ribbonManifest = nil
    local function ribbonMan()
        if ribbonManifest == nil then
            ribbonManifest = false
            local okC, Condition = pcall(require, "src.ui.game3.rse.pokenav.condition")
            local okM, man = false, nil
            if okC and Condition.manifest then okM, man = pcall(Condition.manifest) end
            if okM and type(man) == "table" and man.ribbonData then ribbonManifest = man end
        end
        return ribbonManifest or nil
    end
    local FIRST_GIFT = 20 -- pokeemerald pokenav.h FIRST_GIFT_RIBBON
    local function ribbonText(keys)
        local okR, RomText = pcall(require, "src.core.game3.rom_text")
        local lines = {}
        for _, k in ipairs(type(keys) == "table" and keys or {}) do
            local t = okR and try(RomText.plain, k)
            if type(t) == "string" and t ~= "" then lines[#lines + 1] = (t:gsub("%s*\n%s*", " ")) end
        end
        return lines
    end
    -- a POKEMON's ribbons, as its PokeNav ribbon page lists them (normal
    -- ones, then the gift ribbons the save holds). Read only: the gift
    -- list is session.giftRibbons as it is (Ribbons.giftRibbons would
    -- create it)
    local function ribbonsOf(session, mon)
        local okR, Ribbons = pcall(require, "src.core.game3.rse.ribbons")
        local man = ribbonMan()
        if not (okR and man) then return nil end
        local okI, normal, gift = pcall(Ribbons.monRibbonIds, mon, man.ribbonData)
        if not okI then return nil end
        local first = tonumber(Ribbons.FIRST_GIFT_RIBBON) or FIRST_GIFT
        local giftValues = type(session.giftRibbons) == "table" and session.giftRibbons or {}
        local out = {}
        local function add(id, desc)
            local gfx = man.ribbonGfx and man.ribbonGfx[id]
            local lines = ribbonText(desc)
            -- Gen 3 ribbons have no name of their own: the PokeNav shows
            -- their two-line description, one sentence
            local text = table.concat(lines, " ")
            out[#out + 1] = { id = id, name = text ~= "" and text or ("RIBBON " .. id),
                icon = gfx and artUrl("ribbon", gfx.pal, gfx.tile) or false }
        end
        for _, id in ipairs(normal or {}) do add(id, man.ribbonDescriptions and man.ribbonDescriptions[id]) end
        for _, id in ipairs(gift or {}) do
            local v = tonumber(giftValues[id - first + 1]) or 0
            if v > 0 then add(id, man.giftRibbonDescriptions and man.giftRibbonDescriptions[v - 1]) end
        end
        return out
    end

    -- the POKEBLOCK CASE (pokeblock.c), read as it is (Pokeblock.slots
    -- would fill in missing slots): each block's name ("RED BLOCK"), level
    -- (its highest flavour), the five flavours and FEEL
    local function pokeblocksOf(session)
        local list = type(session.pokeblocks) == "table" and session.pokeblocks or nil
        if not list then return {} end
        local okP, Pokeblock = pcall(require, "src.core.game3.rse.pokeblock")
        local okT, Text = pcall(require, "src.core.game3.rom_text")
        local flavorNames = {}
        for i, k in ipairs({ "Spicy", "Dry", "Sweet", "Bitter", "Sour" }) do
            local t = okT and try(Text.plain, "gText_" .. k)
            flavorNames[i] = type(t) == "string" and t ~= "" and t:upper() or k:upper()
        end
        local out = {}
        for i = 1, (okP and Pokeblock.COUNT or 40) do
            local b = list[i]
            if type(b) == "table" and num(b.color) ~= 0 then
                local flavors = {}
                for f, k in ipairs({ "spicy", "dry", "sweet", "bitter", "sour" }) do
                    flavors[f] = { name = flavorNames[f], value = num(b[k]) }
                end
                out[#out + 1] = {
                    slot = i,
                    color = num(b.color),
                    name = okP and try(Pokeblock.name, b) or "POKEBLOCK",
                    level = okP and try(Pokeblock.highestFlavorLevel, b) or 0,
                    feel = num(b.feel),
                    flavors = flavors,
                }
            end
        end
        return out
    end

    local function monEntry(session, mon, opts)
        opts = opts or {}
        if Pokemon.isEgg(mon) then
            return { name = "EGG", species = "EGG", egg = true, level = false, hp = 0, maxHp = 0,
                status = false, shiny = false, front = imageUrl("front", mon), icon = imageUrl("icon", mon),
                types = {}, statList = {}, moves = {}, item = false }
        end
        local sp = Pokemon.speciesOf(mon)
        local speciesName = try(Pokemon.name, sp) or tostring(mon.species)
        local stats = statsOf(mon, sp)
        local nature = natureOf(mon)

        local statList = {}
        for _, s in ipairs(STATS) do
            local row = { label = s.label, value = num(stats[s.mon]) }
            if nature.up == s.label then row.mod = "up" elseif nature.down == s.label then row.mod = "down" end
            statList[#statList + 1] = row
        end

        local abilityId = tonumber(mon.abilityId or mon.ability) or try(Pokemon.abilityId, sp, mon.personality)
        local ability
        if abilityId and abilityId > 0 then
            local name = try(Pokemon.abilityName, abilityId) or ("ABILITY " .. abilityId)
            ability = { name = name, desc = try(SummaryData.abilityDescription, abilityId, name) }
        end

        -- the TRAINER MEMO lines, as the summary screen prints them; {LV_2}
        -- is the font's "Lv." glyph, other control codes print nothing
        local memo = nil
        if platform.isRse() then
            memo = rseMemo(mon, session)
        else
            memo = try(SummaryData.formatTrainerMemo, mon, session)
        end
        if type(memo) == "table" then
            for i, line in ipairs(memo) do
                memo[i] = tostring(line):gsub("{LV_2}%s*", "Lv."):gsub("{[^}]*}", "")
            end
        end
        local caught = {
            ball = mon.pokeball and try(ItemsData.displayName, mon.pokeball) or nil,
            ballIcon = artUrl("ball", mon),
            ot = mon.otName or mon.ot,
            otId = mon.otId and ("%05d"):format(num(mon.otId) % 65536) or nil,
            memo = type(memo) == "table" and table.concat(memo, " ") or nil
        }
        -- the card shows the nature on its own: MET keeps the rest
        -- ("BASHFUL nature. Met in PALLET TOWN at Lv.5." -> "Met in ...")
        if caught.memo then
            local lead = nature.name .. " nature."
            if caught.memo:sub(1, #lead):upper() == lead:upper() then
                caught.memo = caught.memo:sub(#lead + 1):gsub("^%s+", "")
            end
            if caught.memo == "" then caught.memo = nil end
        end

        local exp
        local progress = try(SummaryData.expProgress, mon, mon.growthRate or try(Pokemon.growthRate, sp))
        if progress then exp = { total = progress.totalExp, toNext = progress.expNeeded } end

        local status = STATUS[try(SummaryData.statusAilment, mon) or 0] or false
        return {
            name = try(Pokemon.displayName, mon) or speciesName,
            species = speciesName,
            dex = try(Pokemon.national, sp),
            level = num(mon.level),
            hp = num(mon.hp),
            maxHp = num(stats.maxHp or mon.maxHp),
            status = status,
            shiny = try(Pokemon.isShiny, mon) and true or false,
            gender = genderOf(mon, sp),
            front = imageUrl("front", mon),
            icon = imageUrl("icon", mon),
            types = speciesTypes(sp),
            statList = statList,
            item = itemOf(mon),
            -- the party menu's held-item marker (sprites3.held)
            held = imageUrl("held", mon),
            moves = movesOf(mon, opts.hidden),
            nature = nature,
            ability = ability,
            exp = exp,
            caught = caught,
            -- SHOW HIDDEN VALUES: IVs, EVs and the rest (nil when off)
            hidden = opts.hidden and hiddenValues(mon, sp) or nil,
            -- Emerald: CONDITION and RIBBONS (nil elsewhere)
            condition = platform.isRse() and conditionOf(mon) or nil,
            ribbons = platform.isRse() and ribbonsOf(session, mon) or nil
        }
    end

    ---- bag ----------------------------------------------------------------

    local function pocketLabel(key)
        local label = try(function() return ItemsData.POCKET_LABEL[key] end)
        if type(label) == "string" and label ~= "" then return label end
        return (key:gsub("_", " "))
    end

    -- the game's item description as one line of text (items_data:
    -- description, its line breaks as spaces)
    local function itemDesc(id)
        local d = try(ItemsData.description, id)
        if type(d) ~= "string" then return nil end
        d = d:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        return d ~= "" and d or nil
    end

    local function itemEntry(slot, pocket)
        local id = slot.id
        local entry = {
            id = tostring(id),
            name = try(ItemsData.displayName, id) or tostring(id),
            pocket = pocket,
            count = num(slot.qty),
            -- the item's BAG icon, shown in front of its name
            icon = artUrl("itemIcon", id)
        }
        -- GIVE TO HOLD: what the game's GIVE accepts (item_use.lua
        -- checkGive: not a KEY ITEM, not from the TM CASE), minus MAIL,
        -- which needs a letter written in the game
        local okM, Mail = pcall(require, "src.core.game3.mail")
        local mail = okM and Mail.isMailItem and Mail.isMailItem(tonumber(id) or id)
        entry.hold = (pocket ~= "KEY_ITEMS" and pocket ~= "TM_CASE" and not mail) or nil
        if pocket == "KEY_ITEMS" or try(ItemsData.isHm, id) then
            -- key items and HMs show no quantity
            entry.key = true
            entry.count = false
        end
        if try(ItemsData.isTm, id) then
            -- a TM CASE row reads as its number and its move
            local n = try(ItemsData.tmNumber, id)
            local kind = try(ItemsData.isHm, id) and "HM" or "TM"
            local moveId = try(Pokemon.moveFromTmItem, id)
            entry.machine = n and ("%s%02d"):format(kind, n) or entry.name
            entry.move = moveId and try(Pokemon.moveName, moveId) or nil
        end
        return entry
    end

    -- A slot's reference: a pocket can hold the same item in two slots
    -- (RARE CANDY ×90 and ×99), so the page picks a slot by pocket, item,
    -- count and which of the identical slots it is ("ITEMS:68:90:1").
    -- Identical slots are interchangeable, so which one "the 2nd" resolves
    -- to never matters; a count that changed in the game no longer
    -- matches, and the edit is refused (edits3.lua resolves these).
    local function slotRefs(slots, pocket)
        local refs, seen = {}, {}
        for i, slot in ipairs(slots) do
            if type(slot) == "table" then
                local base = pocket .. ":" .. tostring(slot.id) .. ":" .. num(slot.qty)
                seen[base] = (seen[base] or 0) + 1
                refs[i] = base .. ":" .. seen[base]
            end
        end
        return refs
    end

    local function bagEntry(session)
        local bag = session.bag or {}
        local pockets = type(bag.pockets) == "table" and bag.pockets or {}
        local order = ItemsData.POCKET_ORDER
        if not (order and #order > 0) then
            order = { "ITEMS", "KEY_ITEMS", "POKE_BALLS", "TM_CASE", "BERRY_POUCH" }
        end
        local list, raw, tabs = {}, {}, {}
        for _, key in ipairs(order) do
            local slots = pockets[key] or {}
            -- TM CASE / BERRY POUCH: kept sorted by the game (edits3.lua FIXED)
            tabs[#tabs + 1] = { id = key, label = pocketLabel(key), fixed = key == "TM_CASE" or key == "BERRY_POUCH" }
            local refs = slotRefs(slots, key)
            for i, slot in ipairs(slots) do
                if type(slot) == "table" and slot.id and slot.id ~= 0 and num(slot.qty) > 0 then
                    local entry = itemEntry(slot, key)
                    entry.key = refs[i]
                    list[#list + 1] = entry
                    raw[#raw + 1] = refs[i]
                end
            end
        end
        -- Emerald: the POKEBLOCK CASE too (nil elsewhere)
        return { money = num(session.money), items = list, order = raw, pockets = tabs,
            pokeblocks = platform.isRse() and pokeblocksOf(session) or nil }
    end

    -- the PLAYER's PC: its item storage (session.storage.items)
    local function pcItemsOf(session)
        local out = {}
        local items = session.storage and session.storage.items or {}
        local refs = slotRefs(items, "PC")
        for i, slot in ipairs(items) do
            if type(slot) == "table" and slot.id and slot.id ~= 0 and num(slot.qty) > 0 then
                out[#out + 1] = { key = refs[i], id = tostring(slot.id), name = try(ItemsData.displayName, slot.id) or tostring(slot.id),
                    count = num(slot.qty), icon = artUrl("itemIcon", slot.id) }
            end
        end
        return out
    end

    ---- PC -----------------------------------------------------------------

    local function pcEntry(session)
        local boxes, names, headers = {}, {}, {}
        local source = platform.boxes(session)
        for b = 1, platform.BOX_COUNT do
            local list = {}
            for _, mon in ipairs(source[b] or {}) do
                local egg = Pokemon.isEgg(mon)
                local sp = Pokemon.speciesOf(mon)
                local row = {
                    uid = uids.of(mon),
                    name = egg and "EGG" or (try(Pokemon.displayName, mon) or tostring(mon.species)),
                    species = egg and "EGG" or (try(Pokemon.name, sp) or tostring(mon.species)),
                    level = not egg and num(mon.level) or false,
                    egg = egg or nil,
                    icon = imageUrl("icon", mon)
                }
                local item = not egg and itemOf(mon)
                if item then
                    row.item = item.name
                    row.held = imageUrl("held", mon)
                end
                list[#list + 1] = row
            end
            boxes[b] = list
            names[b] = platform.boxName(session, b)
            -- the box's wallpaper header, behind its name in the box bar
            headers[b] = artUrl("boxHeader", platform.boxWallpaper(session, b)) or false
        end
        return { current = platform.currentBox(session), capacity = platform.BOX_CAPACITY,
            boxes = boxes, names = names, headers = headers,
            -- the game's ◀ ▶ beside the box name
            arrows = { left = artUrl("boxArrow", "left") or false, right = artUrl("boxArrow", "right") or false } }
    end

    -- opts.hidden: the SHOW HIDDEN VALUES option
    local S = {}

    -- the PC is built on its own (opts.pcOnly: { pc = ... }): main.lua sends
    -- it only when it changed, so every other poll skips its 420 slots
    function S.snapshot(game, opts)
        opts = opts or {}
        local party = {}
        local bag = { money = 0, items = {} }
        local pc = { current = 1, capacity = platform.BOX_CAPACITY, boxes = {} }
        local session = platform.save(game)
        -- opts.monUid: one POKéMON's full card (party or box), for the PC's
        -- POKéMON sheet: { mon = ... }
        if opts.monUid then
            if not session then return {} end
            local found
            for _, m in ipairs(session.party or {}) do
                if uids.of(m) == opts.monUid then found = m end
            end
            if not found then
                for _, box in pairs(platform.boxes(session)) do
                    for _, m in ipairs(box) do
                        if uids.of(m) == opts.monUid then found = m end
                    end
                end
            end
            if not found then return {} end
            local ok, entry = pcall(monEntry, session, found, opts)
            if not ok then
                mod.log:warn("pokemon details failed: %s", tostring(entry))
                return {}
            end
            entry.uid = opts.monUid
            return { mon = entry }
        end
        if opts.pcOnly then
            if session then
                local okP, p = pcall(pcEntry, session)
                if okP then pc = p else mod.log:warn("pc failed: %s", tostring(p)) end
            end
            return { pc = pc }
        end
        if session then
            for i, mon in ipairs(session.party or {}) do
                local ok, entry = pcall(monEntry, session, mon, opts)
                if not ok then
                    mod.log:warn("party slot %d failed: %s", i, tostring(entry))
                    entry = { name = "?????", species = "?????", level = 0, hp = 0, maxHp = 0,
                        types = {}, statList = {}, moves = {} }
                end
                -- which mon this card is
                entry.uid, entry.slot = uids.of(mon), i
                party[#party + 1] = entry
            end
            local okB, b = pcall(bagEntry, session)
            if okB then bag = b else mod.log:warn("bag failed: %s", tostring(b)) end
        end
        -- variant: "frlg" / "rse" (the page's html.rse)
        return { gen = 3, variant = platform.variant(game), party = party, bag = bag }
    end

    -- an item's description, for the item sheet (fetched when it opens)
    S.itemDesc = itemDesc

    function S.pcItems(game)
        local session = platform.save(game)
        return session and pcItemsOf(session) or {}
    end

    return S
end
