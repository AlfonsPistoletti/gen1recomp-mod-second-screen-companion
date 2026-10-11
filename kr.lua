-- Kanto Reforged (optional): the few things of it the page shows that live
-- in its own code rather than in game data. Ability texts, which items a
-- Gen 1 POKéMON can hold (and which are berries), its Gen 1 BAG pockets and
-- the split SP.ATK / SP.DEF come from its own modules, so they always match
-- what the game shows. Everything else of it (abilities, gender, held items,
-- the Day Care, species, encounters) is plain data the other modules read.
--
-- This is the only file that knows Kanto Reforged. It is found through
-- mod.find on every call (load order doesn't matter, and it can be turned
-- off), and every function answers nil while it is missing, a version it
-- wasn't written for, or a module of it fails to load; callers then show
-- what they show without it.
return function(mod)
    local ID = "Kanto-Reforged"
    -- the versions this was written against (its module paths and shapes)
    local RANGE = ">=1.7.0 <2.0.0"
    local MODULES = {
        abilityText = "mods.Kanto-Reforged.battle.ability_text",
        heldItems = "mods.Kanto-Reforged.items.held_items",
        bagPockets = "mods.Kanto-Reforged.items.bag_pockets",
        splitSpecial = "mods.Kanto-Reforged.battle.split_special",
    }

    local K = { ID = ID }

    local okSemver, Semver = pcall(require, "src.mods.Semver")
    local versionOk = {} -- version -> whether it is in RANGE (logged once)

    -- whether Kanto Reforged is on, in a version this file knows
    function K.active()
        local handle = mod.find and mod.find(ID)
        if not handle then return false end
        local v = tostring(handle.version or "")
        if versionOk[v] == nil then
            local ok, fits = false, false
            if okSemver then ok, fits = pcall(Semver.satisfies, v, RANGE) end
            versionOk[v] = ok and fits and true or false
            if not versionOk[v] then
                mod.log:warn("Kanto Reforged %s is not %s: its extras are left out", v, RANGE)
            end
        end
        return versionOk[v]
    end

    local loaded = {}
    local function module(name)
        if not K.active() then return nil end
        if loaded[name] == nil then
            local ok, m = pcall(require, MODULES[name])
            loaded[name] = ok and type(m) == "table" and m or false
            if not loaded[name] then mod.log:warn("Kanto Reforged's %s didn't load: %s", MODULES[name], tostring(m)) end
        end
        return loaded[name] or nil
    end

    -- one of its options, as its own menu has it (the loader keeps every
    -- mod's options: game.mods is the loader)
    function K.option(game, key)
        if not K.active() then return nil end
        local loader = game and game.mods
        local stored = loader and loader.modOptions and loader.modOptions[ID]
        if type(stored) == "table" and stored[key] ~= nil then return stored[key] end
        for _, row in ipairs(loader and loader.optionSchemas and loader.optionSchemas[ID] or {}) do
            if row.key == key then return row.default end
        end
        return nil
    end

    -- an ability's one-line text, as its summary page shows it
    function K.abilityText(id)
        local m = module("abilityText")
        if not (m and m.describe) then return nil end
        local ok, text = pcall(m.describe, id)
        return ok and type(text) == "string" and text or nil
    end

    -- Gen 1: whether a POKéMON may hold this item (its GIVE's list)
    function K.holdable(id)
        local m = module("heldItems")
        if not (m and m.isHoldable) then return nil end
        local ok, yes = pcall(m.isHoldable, id)
        return ok and yes and true or false
    end

    -- Gen 1: whether the phone may GIVE this item, like its BAG GIVE (the
    -- option of that name, on by default)
    function K.giveable(game, id)
        if K.option(game, "bag_give") == false then return false end
        return K.holdable(id)
    end

    -- Gen 1: whether this item is a berry (usable on a POKéMON from the BAG)
    function K.isBerry(id)
        local m = module("heldItems")
        if not (m and m.isBerry) then return nil end
        local ok, yes = pcall(m.isBerry, id)
        return ok and yes and true or false
    end

    -- Gen 1: its BAG pockets in tab order ({ id, label }), and the one an
    -- item goes in. nil when gen1_bag_pockets is on instead (Kanto Reforged
    -- then leaves the pockets to it).
    local function ownPockets()
        if mod.find and mod.find("gen1_bag_pockets") then return nil end
        return module("bagPockets")
    end

    function K.pockets()
        local m = ownPockets()
        return m and type(m.POCKETS) == "table" and m.POCKETS or nil
    end

    function K.pocketOf(data, id)
        local m = ownPockets()
        if not (m and m.classify) then return nil end
        local def = data and data.items and data.items[id]
        local ok, pocket = pcall(m.classify, id, def)
        return ok and pocket or nil
    end

    -- the pocket whose order is fixed (sorted by number, no SELECT swap)
    K.FIXED_POCKET = "tmhm"

    -- Gen 1 with its SP.ATK / SP.DEF option on: the two values its summary
    -- shows ({ sp_attack, sp_defense }), worked out by its own formula
    function K.splitSpecial(game, def, mon)
        local m = module("splitSpecial")
        if not (m and m.calcSpStats and def and (def.sp_attack or def.sp_defense)) then return nil end
        if not K.option(game, m.OPTION_KEY or "split_special") then return nil end
        local ok, stats = pcall(m.calcSpStats, def, mon)
        return ok and type(stats) == "table" and stats or nil
    end

    -- its own save data (game.save.modData["Kanto-Reforged"]), read only
    function K.saveData(game)
        if not K.active() then return nil end
        local modData = game and game.save and game.save.modData
        local own = type(modData) == "table" and modData[ID]
        return type(own) == "table" and own or nil
    end

    -- Gen 1: its roaming legendaries on this map right now (its save's
    -- "roamers": active, not beaten, here), the same test as its
    -- encounter.species hook; none in its KANTO dex scope, where they rest
    function K.roamersAt(game, mapId)
        local own = K.saveData(game)
        local s = own and own.roamers
        if type(s) ~= "table" or mapId == nil then return {} end
        if K.option(game, "g1:species_scope") == "kanto" then return {} end
        local beaten, locations = s.beaten or {}, s.locations or {}
        local out = {}
        for species, on in pairs(s.active or {}) do
            if on and not beaten[species] and tostring(locations[species]) == tostring(mapId) then
                out[#out + 1] = species
            end
        end
        table.sort(out)
        return out
    end

    return K
end
