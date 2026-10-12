-- SHINY HUNT on FireRed / LeafGreen / Ruby / Sapphire / Emerald: steps to
-- hatch for the party's eggs, and whether an egg (or the roaming
-- legendary) is shiny where that is already decided.
--
-- Gen 3 shininess is the PID against the player's ids (pokemon.lua
-- Pokemon.isShiny: TID xor SID xor both PID halves < 8), 1 in 8192 for every
-- new PID, eggs too: the parents don't change it. What's fixed when:
--   * a party egg: its PID, since it was made
--   * the day-care's waiting egg on Ruby / Sapphire / Emerald: the whole PID
--     (dc.offspringPersonality) when it appears (breeding.lua
--     setInitialEggData); on FireRed / LeafGreen half of it is rolled only
--     when the egg is collected, so nothing is known before
--   * the Ruby / Sapphire / Emerald roamer: its PID, since it was created
--     (session.roamer.personality); FireRed's rolls a new one each battle
return function(mod, platform)
    local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
    local okD, Daycare = pcall(require, "src.core.game3.daycare")
    local S = {}
    if not (okP and okD) then
        mod.log:warn("Gen 3 shiny info unavailable: game3 modules missing")
        return S
    end

    S.ODDS = 8 / 65536 -- 1 in 8192

    local function try(fn, ...)
        local ok, a = pcall(fn, ...)
        if ok then return a end
        return nil
    end

    -- the day-care record without creating it (live3.lua's peekStore: the
    -- session's own table first, else the one in the save's mod data)
    function S.daycare(session)
        if type(session) ~= "table" then return nil end
        local loose = rawget(session, "daycare")
        if type(loose) == "table" then return loose end
        local key = Daycare.saveKey and try(Daycare.saveKey, session)
        local data = type(session.modData) == "table" and key and session.modData[key]
        return type(data) == "table" and type(data.daycare) == "table" and data.daycare or nil
    end

    -- a PID against the player's own ids
    local function playerShiny(session, personality)
        if personality == nil then return nil end
        local okS, sid = pcall(Pokemon.playerSecretId, session)
        local ok, yes = pcall(Pokemon.isShiny, { personality = personality,
            otId = session.trainerId or session.id or session.playerId,
            otSecretId = okS and sid or nil })
        return ok and yes and true or false
    end

    -- whether an egg in the party hatches shiny
    function S.isShiny(mon)
        if type(mon) ~= "table" then return nil end
        local ok, yes = pcall(Pokemon.isShiny, mon)
        return ok and yes and true or false
    end

    -- Steps until an egg in the party hatches (daycare.lua Daycare.step /
    -- tickEggCycles): the day-care's step counter ticks every 256 steps,
    -- when it reaches 255; each tick takes 1 egg cycle off, or 2 on Ruby /
    -- Sapphire / Emerald with FLAME BODY or MAGMA ARMOR in the party (the
    -- party as it is now: Daycare.eggCyclesToSubtract); the egg hatches on
    -- the tick after its cycles reach 0. nil if not an egg.
    function S.hatchSteps(session, mon)
        if not (type(mon) == "table" and try(Pokemon.isEgg, mon)) then return nil end
        local cycles = tonumber(mon.friendship or mon.eggCycles or mon.cycles) or 20
        local sub = platform.isRse() and try(Daycare.eggCyclesToSubtract, session) or 1
        local ticks = (sub == 2 and math.floor(cycles / 2) + cycles % 2 or cycles) + 1
        local dc = S.daycare(session)
        local counter = tonumber(dc and dc.stepCounter) or 0
        local untilTick = (254 - counter) % 256 + 1
        return untilTick + (ticks - 1) * 256, sub == 2
    end

    -- Ruby / Sapphire / Emerald: whether the day-care's waiting egg will
    -- hatch shiny (its PID is whole once it appears); nil when there is no
    -- egg waiting, on FireRed / LeafGreen, or under a mod's own egg rules
    function S.pendingEggShiny(session, dc)
        if not (platform.isRse() and type(dc) == "table") then return nil end
        if not try(Daycare.isEggPending, dc) then return nil end
        local okR, Profile = pcall(require, "src.core.game3.profile")
        local row = okR and try(Profile.forSession, session)
        local policy = type(row) == "table" and row.daycare
        if type(policy) == "table" and policy.initialPersonality then return nil end
        local p = tonumber(dc.offspringPersonality)
        if not p or p == 0 then return nil end
        return playerShiny(session, p)
    end

    -- Ruby / Sapphire / Emerald: whether the roamer is shiny (its PID is
    -- kept); nil on FireRed / LeafGreen, where each battle rolls a new one
    function S.roamerShiny(session, roamer)
        if not (platform.isRse() and type(roamer) == "table") then return nil end
        return playerShiny(session, tonumber(roamer.personality))
    end

    return S
end
