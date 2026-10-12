-- SHINY HUNT on Gold (shiny2.lua), against the engine's own Breeding and
-- Mon: the egg odds come out as the cart's DV inheritance gives them (a
-- shiny Ditto 1 in 64, a shiny parent of a 1:1 species 1 in 128, a starter
-- with a shiny father never), and the steps to hatch follow the 256-step
-- cycle. Development only (.modkitignore). From the gen1recomp root:
--   luajit mods/second_screen_companion/tests/shiny2_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = _G.love or require("tests.love_stub")

local failed = 0
local function check(label, pass)
    print((pass and "PASS " or "FAIL ") .. label)
    if not pass then failed = failed + 1 end
end

local mod = { log = { warn = function() end } }
local S = assert(loadfile("mods/second_screen_companion/shiny2.lua"))()(mod)
check("loads against the engine", type(S.eggOdds) == "function")

-- a tiny dex: genderRatio is the cart's byte (127 = 1:1, 31 = 7:1, 255 none)
local data = {
    pokemon = {
        DITTO = { id = "DITTO", eggGroups = { "DITTO" }, genderRatio = 255 },
        RATTATA = { id = "RATTATA", eggGroups = { "GROUND" }, genderRatio = 127, eggSteps = 15 },
        CYNDAQUIL = { id = "CYNDAQUIL", eggGroups = { "GROUND" }, genderRatio = 31, eggSteps = 20 },
        MAGNEMITE = { id = "MAGNEMITE", eggGroups = { "MINERAL" }, genderRatio = 255, eggSteps = 20 },
    },
}
-- gender comes from the DVs (Attack * 16 + Speed against the ratio), so
-- these sets are chosen by it: for RATTATA (127) and CYNDAQUIL (31),
-- Attack 10 / 12 reads male, Attack 1 / 2 female
local SHINY_M = { attack = 10, defense = 10, speed = 10, special = 10 }
local SHINY_F = { attack = 2, defense = 10, speed = 10, special = 10 }
local PLAIN_M = { attack = 12, defense = 3, speed = 5, special = 7 }
local PLAIN_F = { attack = 1, defense = 3, speed = 5, special = 7 }
local function mon(species, dvs) return { species = species, dvs = dvs } end

local function near(p, n) return p and math.abs(1 / p - n) < 0.5 end

local okD, pd = pcall(S.eggOdds, data, mon("RATTATA", PLAIN_M), mon("DITTO", SHINY_M))
check("shiny Ditto: 1 in 64", okD and near(pd, 64))
local okM, pm = pcall(S.eggOdds, data, mon("RATTATA", SHINY_F), mon("RATTATA", PLAIN_M))
check("1:1 species, shiny mother: 1 in 128", okM and near(pm, 128))
local okP, pp = pcall(S.eggOdds, data, mon("RATTATA", PLAIN_F), mon("RATTATA", SHINY_M))
check("1:1 species, shiny father: 1 in 128", okP and near(pp, 128))
local okF, pf = pcall(S.eggOdds, data, mon("CYNDAQUIL", PLAIN_F), mon("CYNDAQUIL", SHINY_M))
check("7:1 starter, shiny father: never", okF and pf == 0)
local okG, pg = pcall(S.eggOdds, data, mon("MAGNEMITE", SHINY_M), mon("DITTO", PLAIN_M))
check("plain Ditto passes its Defense DV 3: never", okG and pg == 0)
local okN, pn = pcall(S.eggOdds, data, mon("RATTATA", SHINY_M), mon("RATTATA", PLAIN_M))
check("two males: no eggs, no odds", okN and pn == nil)

-- the game's own rules take the Speed 10 shortcut: one pair at once, fast
do
    local t = os.clock()
    local p = S.eggOdds(data, mon("RATTATA", SHINY_F), mon("RATTATA", { attack = 13, defense = 3, speed = 5, special = 7 }))
    local ms = (os.clock() - t) * 1000
    print(("     shortcut: %.1f ms"):format(ms))
    check("shortcut: answered at once, still 1 in 128", near(p, 128) and ms < 20)
end

-- a mod's shiny rule: every roll counted, over frames, same answer
do
    local Runtime = require("src.mods.Runtime")
    local wants, call = Runtime.wantsHook, Runtime.call
    Runtime.wantsHook = function(name) return name == "shiny.roll" end
    Runtime.call = function(_, fallback, ctx) return fallback(ctx) end
    local a, b = mon("RATTATA", SHINY_F), mon("RATTATA", { attack = 14, defense = 3, speed = 5, special = 7 })
    local p, pending = S.eggOdds(data, a, b)
    check("a mod's rule: counted over frames", p == nil and pending == true)
    local ticks, slowest = 0, 0
    repeat
        local t = os.clock()
        S.tick()
        slowest = math.max(slowest, (os.clock() - t) * 1000)
        ticks = ticks + 1
        p, pending = S.eggOdds(data, a, b)
    until not pending or ticks > 100
    print(("     %d frames, slowest %.1f ms"):format(ticks, slowest))
    check("a mod's rule: same 1 in 128 once done", near(p, 128) and ticks == 16)
    Runtime.wantsHook, Runtime.call = wants, call
end

-- steps to hatch: ticks 128 steps into each 256-step cycle
check("not an egg: nil", S.hatchSteps({ stepCount = 0 }, { species = "RATTATA" }) == nil)
check("15 cycles at step 0", S.hatchSteps({ stepCount = 0 }, { isEgg = true, eggSteps = 15 }) == 14 * 256 + 128)
check("one tick left, just past the tick", S.hatchSteps({ stepCount = 128 }, { isEgg = true, eggSteps = 1 }) == 256)
check("one tick left, one step before it", S.hatchSteps({ stepCount = 127 }, { isEgg = true, eggSteps = 1 }) == 1)
check("counter at 0: hatching now", S.hatchSteps({ stepCount = 9 }, { isEgg = true, eggSteps = 0 }) == 0)
check("an egg made shiny stays shiny", S.isShiny({ isEgg = true, shiny = true, dvs = PLAIN }) == true)

if failed > 0 then
    print(("FAIL shiny2_test (%d)"):format(failed))
    os.exit(1)
end
print("PASS shiny2_test")
