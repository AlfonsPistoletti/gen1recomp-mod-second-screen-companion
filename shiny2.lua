-- SHINY HUNT on Gold / Silver / Crystal: how likely the Day-Care's eggs are
-- to hatch shiny, how many steps an egg in the party still needs, and
-- whether an egg already is shiny (an egg's DVs, and so its shininess, are
-- fixed when it is made).
--
-- The odds are counted, not looked up: the rolls of the egg's two DV bytes
-- are put through the engine's own rules (Breeding.lua makeEgg: which parent
-- passes its Defense DV and the low three bits of its Special, by the egg's
-- gender), with the engine's own gender and shiny tests (Breeding.gender /
-- Mon.isShiny). On the game's own rules only the rolls with Speed 10 can be
-- shiny (Mon.vanillaShiny), so only those 4096 of the 65536 are counted:
-- the same answer, at once. When a mod changes who is shiny (shiny.roll) or
-- an egg's gender (gender.roll), every roll is counted, its rules with it,
-- spread over a few frames (S.tick) so the game never stalls; the odds show
-- once that is done.
return function(mod)
    local okM, Mon = pcall(require, "src.battle.gen2.Mon")
    local okB, Breeding = pcall(require, "src.core.gen2.Breeding")
    local okR, Runtime = pcall(require, "src.mods.Runtime")
    local S = {}
    if not (okM and okB) then
        mod.log:warn("shiny odds unavailable: Gen 2 modules missing")
        return S
    end

    -- rows of the first DV byte counted per frame when every roll is counted
    -- (16 x 256 rolls: about as much as the whole shortcut)
    local ROWS_PER_TICK = 16

    -- whether a mod changes the shiny or gender rule (then only counting
    -- every roll is exact)
    local function hooked()
        if not (okR and Runtime.wantsHook) then return false end
        return (Runtime.wantsHook("shiny.roll") or Runtime.wantsHook("gender.roll")) and true or false
    end

    local function dvsKey(mon)
        local d = type(mon) == "table" and type(mon.dvs) == "table" and mon.dvs or {}
        return table.concat({ tostring(mon and mon.species), tostring(d.attack), tostring(d.defense),
            tostring(d.speed), tostring(d.special), tostring(mon and mon.gender) }, ",")
    end

    -- one egg species' count. Byte 0 is Attack<<4 | Defense, byte 1
    -- Speed<<4 | Special; full: every byte 1, else only Speed 10's (160-175)
    local function newCount(data, species, motherSlot, mon1, mon2, full)
        local def = data.pokemon and data.pokemon[species]
        if type(def) ~= "table" then return nil end
        return {
            def = def,
            mother = (motherSlot == 1) and mon1 or mon2,
            father = (motherSlot == 1) and mon2 or mon1,
            ditto = (mon1.species == Breeding.DITTO and mon1) or (mon2.species == Breeding.DITTO and mon2) or nil,
            ctx = { species = species, def = def, level = Breeding.EGG_LEVEL },
            b1lo = full and 0 or 160, b1hi = full and 255 or 175,
            b0 = 0, hits = 0,
        }
    end

    -- counts `rows` more rows of byte 0; true once all 256 are done
    local function countRows(c, rows)
        local last = math.min(255, c.b0 + rows - 1)
        for b0 = c.b0, last do
            for b1 = c.b1lo, c.b1hi do
                local dvs = { attack = math.floor(b0 / 16), defense = b0 % 16,
                    speed = math.floor(b1 / 16), special = b1 % 16 }
                local source = c.ditto
                if not source then
                    local gender = Breeding.gender(c.def, dvs)
                    if gender == "male" then source = c.mother
                    elseif gender == "female" then source = c.father end
                end
                if source then
                    local parent = type(source.dvs) == "table" and source.dvs or {}
                    dvs.defense = (parent.defense or 0) % 16
                    dvs.special = dvs.special - (dvs.special % 8) + ((parent.special or 0) % 8)
                end
                dvs.hp = Mon.hpDV(dvs)
                if Mon.isShiny(dvs, c.ctx) then c.hits = c.hits + 1 end
            end
        end
        c.b0 = last + 1
        return c.b0 > 255
    end

    -- the counts' average (the rolls left out can't be shiny, so every
    -- count is out of all 65536)
    local function average(counts)
        local sum = 0
        for _, c in ipairs(counts) do sum = sum + c.hits / 65536 end
        return #counts > 0 and sum / #counts or nil
    end

    -- The chance that one egg from this pair hatches shiny (0..1), or nil
    -- when they can't have one; second value true while it is still being
    -- counted (a mod's rules: S.tick finishes it). Kept until the pair
    -- changes.
    local memo = { key = nil, value = nil }
    local job -- { key, counts, i }: the count spread over frames
    function S.eggOdds(data, mon1, mon2)
        if not (data and type(mon1) == "table" and type(mon2) == "table") then return nil end
        local full = hooked()
        local key = dvsKey(mon1) .. "|" .. dvsKey(mon2) .. "|" .. tostring(full)
        if memo.key == key then return memo.value, false end
        if job and job.key == key then return nil, true end
        job = nil
        local counts = {}
        local okC, compat = pcall(Breeding.compatibility, data, mon1, mon2, { dayCare = true })
        if okC and compat and compat ~= 0 and compat ~= 255 then
            -- the species can be a coin flip (NIDORAN ♀ / ♂): each side
            -- of Breeding.eggSpecies' roll, averaged
            local seen = {}
            for _, roll in ipairs({ 0, 255 }) do
                local okS, species, slot = pcall(Breeding.eggSpecies, data, mon1, mon2, function() return roll end)
                if okS and species and not seen[species] then
                    seen[species] = true
                    local c = newCount(data, species, slot or Breeding.motherSlot(data, mon1, mon2), mon1, mon2, full)
                    if c then counts[#counts + 1] = c end
                end
            end
        end
        if #counts == 0 or not full then
            for _, c in ipairs(counts) do countRows(c, 256) end
            memo.key, memo.value = key, average(counts)
            return memo.value, false
        end
        job = { key = key, counts = counts, i = 1 }
        return nil, true
    end

    -- the chance one new Pokémon is shiny (1 in 8192), or nil when a mod
    -- changes the shiny rule and the base rate isn't known
    function S.baseOdds()
        if okR and Runtime.wantsHook and Runtime.wantsHook("shiny.roll") then return nil end
        return 8 / 65536
    end

    -- every frame: a few more rows of a count spread over frames
    function S.tick()
        if not job then return end
        local c = job.counts[job.i]
        local ok, done = pcall(countRows, c, ROWS_PER_TICK)
        if not ok then
            mod.log:warn("shiny odds failed: %s", tostring(done))
            memo.key, memo.value, job = job.key, nil, nil
            return
        end
        if not done then return end
        job.i = job.i + 1
        if job.i > #job.counts then
            memo.key, memo.value = job.key, average(job.counts)
            job = nil
        end
    end

    -- Steps until an egg in the party hatches: its counter ticks once every
    -- 256 steps, 128 steps into each cycle (Breeding.step: save.stepCount),
    -- and the egg hatches on the tick that takes it to 0. nil if not an egg.
    function S.hatchSteps(save, mon)
        if not Breeding.isEgg(mon) then return nil end
        local ticks = tonumber(mon.eggSteps) or 0
        if ticks <= 0 then return 0 end
        local cycle, phase = Breeding.STEP_CYCLE, Breeding.EGG_STEP_PHASE
        local now = (tonumber(save and save.stepCount) or 0) % cycle
        local untilTick = (phase - now - 1) % cycle + 1
        return (ticks - 1) * cycle + untilTick
    end

    -- whether an egg (or any mon) is shiny: fixed when it was made
    -- (Mon.new writes it), else read from its DVs
    function S.isShiny(mon)
        if type(mon) ~= "table" then return nil end
        if mon.shiny ~= nil then return mon.shiny and true or false end
        local ok, yes = pcall(Mon.isShiny, mon.dvs, { species = mon.species })
        return ok and yes and true or false
    end

    return S
end
