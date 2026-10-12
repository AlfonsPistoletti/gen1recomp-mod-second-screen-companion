-- SHINY HUNT (mod option): a reset counter for shiny hunting. Every load of
-- the save counts as one reset: the CONTINUE after a soft reset
-- (A+B+SELECT+START) and the F2 quick load both raise save.loaded on every
-- generation (Game:restoreSave, Game2:continueGame, Game3 "continue"). The
-- phone can add or take one (to correct a miss) and set it back to 0.
--
-- The count is kept in mod.storage, per playthrough (game version and save
-- identity), outside the game's save: a reset throws away whatever the save
-- in memory holds, so a count kept there would roll back with it.
return function(mod)
    local KEY = "shiny_hunt"
    local MAX = 999999

    local H = {}

    function H.enabled()
        return mod.options:get("shiny_hunt") and true or false
    end

    -- the count as last read or written, with the playthrough it belongs to
    -- (shown on the title screen too, where the save may not be bound yet)
    local current = { id = nil, count = nil }
    -- loads seen but not yet counted (the event can arrive before the new
    -- save is bound to the game; tick counts them once it is)
    local pending = 0
    local lastError

    local function warnOnce(fmt, ...)
        local msg = fmt:format(...)
        if msg ~= lastError then
            lastError = msg
            mod.log:warn("%s", msg)
        end
    end

    -- the current playthrough's id and count, read from storage when the
    -- playthrough changed; nil when no playthrough is bound (title, no save).
    -- peek: only for a save that already has its identity, since storage
    -- gives a fresh New Game one on first use and a look shouldn't do that
    local function bound(game, peek)
        if peek then
            local meta = game and game.save and game.save.meta
            if not (type(meta) == "table" and meta.playthroughId) then return nil end
        end
        local ok, ctx = pcall(mod.storage.context, mod.storage, game)
        local id = ok and type(ctx) == "table" and ctx.playthroughId and
            (tostring(ctx.gameVersion) .. "/" .. tostring(ctx.playthroughId)) or nil
        if not id then return nil end
        if current.id ~= id then
            local okR, data = pcall(mod.storage.read, mod.storage, game, KEY)
            local n = okR and type(data) == "table" and tonumber(data.count) or 0
            current = { id = id, count = math.max(0, math.floor(n)) }
        end
        return current
    end

    local function store(game, c, n)
        c.count = math.max(0, math.min(MAX, math.floor(n)))
        local ok, written, code, message = pcall(mod.storage.write, mod.storage, game, KEY, { count = c.count })
        if not ok or not written then
            warnOnce("shiny hunt counter not saved: %s", tostring(ok and (message or code) or written))
        end
        return c.count
    end

    -- save.loaded: one more reset (only while the option is on)
    mod.events:on("save.loaded", function()
        if H.enabled() then pending = pending + 1 end
    end)

    -- every frame: count the loads once the new save is bound
    function H.tick(game)
        if pending == 0 then return end
        if not H.enabled() then pending = 0 return end
        local c = bound(game)
        if not c then return end
        local n = pending
        pending = 0
        store(game, c, c.count + n)
    end

    -- for /state: { count } (the last known one at the title screen), or nil
    -- while the option is off or no save has been loaded yet
    function H.state(game)
        if not H.enabled() then return nil end
        local c = bound(game, true) or (current.id and current) or nil
        if not c then return nil end
        return { count = c.count }
    end

    -- Untamed Tohjo (overworldmons, Gen 1 / 2): its shiny chain, read from
    -- the save's mod data as it keeps it (mod.save chainSpecies /
    -- chainCount): defeating or catching the same species again adds one,
    -- running from it or blacking out breaks it. { species, count } while a
    -- chain runs and SHINY HUNT is on, else nil.
    local CHAIN_MOD = "overworldmons"
    -- Untamed Advanced (untamed_advanced, Gen 3): the same idea, kept in RAM
    -- only (owe.lua: never saved, so a reset loses it) and grown by
    -- defeating the species (catching it ends the chain). Read through what
    -- it publishes, mod.exports.engine.Owe.chainState() -> engine species
    -- number, count; nil while its "Chaining" option (C.OWE_ROGUE_CHAIN) is off.
    local CHAIN_MOD3 = "untamed_advanced"
    local function advancedChain()
        local handle = mod.find and mod.find(CHAIN_MOD3)
        local E = handle and type(handle.exports) == "table" and handle.exports.engine
        local Owe = type(E) == "table" and E.Owe
        if not (type(Owe) == "table" and type(Owe.chainState) == "function") then return nil end
        if type(E.C) == "table" and E.C.OWE_ROGUE_CHAIN == false then return nil end
        local ok, species, count = pcall(Owe.chainState)
        count = ok and tonumber(count)
        if not (species and count and count >= 1) then return nil end
        count = math.floor(count)
        -- its own odds curve (owe.lua getEncounterChainShinyOdds: 1/8192 up
        -- to 4, down to 1/16 at 48), rolled on top of the PID's own 1/8192
        -- for a spawn the chain picks (always from chain 9 on)
        local okO, denom = false, nil
        if type(Owe._chain) == "table" and type(Owe._chain.shinyOdds) == "function" then
            okO, denom = pcall(Owe._chain.shinyOdds, count)
        end
        denom = okO and tonumber(denom) or nil
        local odds = denom and denom > 0 and (1 - (8191 / 8192) * (1 - 1 / denom)) or nil
        return { species = tostring(species), count = count, odds = odds }
    end

    -- Modern Spawns (modern_spawns, every generation): counts a chain the
    -- same way (defeat or catch, saved with the game) and publishes it,
    -- exports.chain() -> { species = its id ("PIDGEY"), count } and
    -- exports.chainBonus(species) -> { shiny = chance, ... }, nil while its
    -- SHINY CHAINS option is off. The shiny chance only comes true with a mod
    -- that applies it: Wilds of Hoenn, on Gen 3 (on top of the PID's own
    -- 1/8192). Without it the chain makes no shinies, so nothing is shown:
    -- the game's shiny odds stay as they are.
    local SPAWNS_MOD, APPLIES_MOD = "modern_spawns", "wilds_of_hoenn"
    local function modernChain(gen3)
        if not (gen3 and mod.find and mod.find(APPLIES_MOD)) then return nil end
        local handle = mod.find and mod.find(SPAWNS_MOD)
        local api = handle and handle.exports
        if not (type(api) == "table" and type(api.chain) == "function" and type(api.chainBonus) == "function") then
            return nil
        end
        if type(api.isActive) == "function" then
            local okA, active = pcall(api.isActive)
            if not (okA and active) then return nil end
        end
        local ok, c = pcall(api.chain)
        local count = ok and type(c) == "table" and tonumber(c.count)
        if not (count and count >= 1 and c.species) then return nil end
        local okB, bonus = pcall(api.chainBonus, c.species)
        if not (okB and type(bonus) == "table") then return nil end
        -- the Gen 3 DEXNAV rows go by the engine's number: through the
        -- national dex number its profile carries (as Wilds of Hoenn does)
        local species = c.species
        local okP, profile = false, nil
        if type(api.profileOf) == "function" then okP, profile = pcall(api.profileOf, c.species) end
        local dex = okP and type(profile) == "table" and tonumber(profile.dex)
        local okE, Pokemon = pcall(require, "src.core.game3.pokemon")
        local okN, n = false, nil
        if dex and okE and Pokemon.speciesFromNational then okN, n = pcall(Pokemon.speciesFromNational, dex) end
        if okN and tonumber(n) and tonumber(n) > 0 then species = n end
        local chance = tonumber(bonus.shiny) or 0
        return { species = tostring(species), count = math.floor(count),
            odds = 1 - (8191 / 8192) * (1 - chance) }
    end

    -- gen3: the running game is FireRed .. Emerald (species ids are numbers)
    function H.chain(game, gen3)
        if not H.enabled() then return nil end
        if not (mod.find and mod.find(CHAIN_MOD)) then return advancedChain() or modernChain(gen3) end
        local modData = game and game.save and game.save.modData
        local own = type(modData) == "table" and modData[CHAIN_MOD]
        if type(own) ~= "table" then return nil end
        local species, count = own.chainSpecies, tonumber(own.chainCount)
        if type(species) ~= "string" or species == "" or not count or count < 1 then return nil end
        count = math.floor(count)
        -- its rollDVs: one 1/8192 roll per chain link for the chained
        -- species' every spawn (MAX_CHAIN 100)
        return { species = species, count = count, odds = 1 - (8191 / 8192) ^ math.min(count, 100) }
    end

    -- Wilds of Kanto Revival (wilds_of_kanto_gen3, Gen 1 / 2): its SHINY RATE
    -- option, the chance a WILD Pokémon is shiny (trainers, gifts, eggs and
    -- starters keep the game's own odds). Read the way its Config.shinyRate
    -- does: the save's option bucket, then the loader's, then the option's
    -- default; its lib/shiny.lua RATE_DENOMINATOR gives the odds.
    -- { odds (0..1, 0 when off), name } while it is on, else nil.
    local WILD_MOD = "wilds_of_kanto_gen3"
    local WILD_RATES = { off = false, gen2 = 8192, modern = 4096, common = 1024, frequent = 512,
        often = 100, high = 10, always = 1 }
    local WILD_DEFAULT = "modern"
    function H.wildRate(game)
        if not H.enabled() then return nil end
        if not (mod.find and mod.find(WILD_MOD)) then return nil end
        local function bucket(t) return type(t) == "table" and t[WILD_MOD] or nil end
        local loader = game and game.mods
        local buckets = {
            bucket(game and game.save and game.save.options and game.save.options.modOptions),
            bucket(loader and loader.modOptions),
        }
        local key
        for i = 1, 2 do -- in order: the save's bucket wins
            local b = buckets[i]
            if type(b) == "table" and b.shiny_rate ~= nil then key = b.shiny_rate break end
        end
        if key == nil then
            for _, row in ipairs(loader and loader.optionSchemas and loader.optionSchemas[WILD_MOD] or {}) do
                if row.key == "shiny_rate" then key = row.default end
            end
        end
        if key == true then key = "always" end
        key = type(key) == "string" and key:lower() or WILD_DEFAULT
        if WILD_RATES[key] == nil then key = WILD_DEFAULT end
        local denom = WILD_RATES[key]
        return { odds = denom and 1 / denom or 0, name = "Wilds of Kanto Revival" }
    end

    -- the phone's + / -: delta is 1 or -1
    function H.add(game, delta)
        if not H.enabled() then return nil, "hunt off" end
        if delta ~= 1 and delta ~= -1 then return nil, "bad request" end
        local c = bound(game)
        if not c then return nil, "not loaded" end
        store(game, c, c.count + delta)
        return true
    end

    -- the phone's RESET (after its confirmation): back to 0
    function H.clear(game)
        if not H.enabled() then return nil, "hunt off" end
        local c = bound(game)
        if not c then return nil, "not loaded" end
        store(game, c, 0)
        return true
    end

    return H
end
