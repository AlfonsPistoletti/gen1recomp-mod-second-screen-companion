-- SHINY HUNT on Gen 3 (shiny3.lua), against the engine's own Pokemon.isShiny
-- and Daycare: steps to hatch follow the day-care's 256-step counter and
-- FLAME BODY / MAGMA ARMOR (Ruby / Sapphire / Emerald only), the waiting
-- egg and the roamer are told apart by game, and a PID is shiny against the
-- player's own ids. Development only (.modkitignore). From the gen1recomp
-- root:
--   luajit mods/second_screen_companion/tests/shiny3_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = _G.love or require("tests.love_stub")

local failed = 0
local function check(label, pass)
    print((pass and "PASS " or "FAIL ") .. label)
    if not pass then failed = failed + 1 end
end

local Daycare = require("src.core.game3.daycare")
local rse = false
local platform = { isRse = function() return rse end }
local S = assert(loadfile("mods/second_screen_companion/shiny3.lua"))()({ log = { warn = function() end } }, platform)
check("loads against the engine", type(S.hatchSteps) == "function" and S.ODDS == 8 / 65536)

-- the party's FLAME BODY test, as the engine answers it, set by hand here
local sub = 1
local realSub = Daycare.eggCyclesToSubtract
Daycare.eggCyclesToSubtract = function() return sub end

local session = { trainerId = 0, secretId = 0, daycare = { stepCounter = 0 } }
local egg = { isEgg = true, friendship = 20 }

-- FireRed: 20 cycles, then the hatching tick; the counter ticks on reaching 255
rse = false
check("FireRed: 21 ticks, the first in 255 steps", S.hatchSteps(session, egg) == 255 + 20 * 256)
session.daycare.stepCounter = 254
check("FireRed: one step before a tick", S.hatchSteps(session, egg) == 1 + 20 * 256)
session.daycare.stepCounter = 255
check("FireRed: just past a tick, 256 to the next", S.hatchSteps(session, egg) == 256 + 20 * 256)
sub = 2
local steps, fast = S.hatchSteps(session, egg)
check("FireRed: FLAME BODY does nothing there", steps == 256 + 20 * 256 and not fast)

-- Emerald: FLAME BODY takes 2 cycles a tick (20 -> 10 ticks, then hatch)
rse = true
steps, fast = S.hatchSteps(session, egg)
check("Emerald + FLAME BODY: 11 ticks", steps == 256 + 10 * 256 and fast == true)
steps = S.hatchSteps(session, { isEgg = true, friendship = 5 })
check("odd cycles: 2, 2, 1, then hatch", steps == 256 + 3 * 256)
sub = 1
check("Emerald without it: 21 ticks", S.hatchSteps(session, egg) == 256 + 20 * 256)
check("not an egg: nil", S.hatchSteps(session, { species = 1 }) == nil)

-- a PID against the player's ids (TID 0, SID 0): shiny when PID's halves
-- xor below 8
local realPending = Daycare.isEggPending
Daycare.isEggPending = function(dc) return dc.eggPending == true end
local dc = { eggPending = true, offspringPersonality = 7 }
rse = true
check("Emerald: the waiting egg's PID 7 is shiny", S.pendingEggShiny(session, dc) == true)
dc.offspringPersonality = 0x00010010
check("Emerald: PID 0x00010010 is not", S.pendingEggShiny(session, dc) == false)
rse = false
check("FireRed: the waiting egg is not known yet", S.pendingEggShiny(session, dc) == nil)
rse = true
check("Emerald roamer: its kept PID", S.roamerShiny(session, { personality = 3 }) == true)
rse = false
check("FireRed roamer: rolled each battle, unknown", S.roamerShiny(session, { pid = 3 }) == nil)
check("a party egg: its own PID and OT ids", S.isShiny({ personality = 7, otId = 0, otSecretId = 0 }) == true)

Daycare.eggCyclesToSubtract, Daycare.isEggPending = realSub, realPending

if failed > 0 then
    print(("FAIL shiny3_test (%d)"):format(failed))
    os.exit(1)
end
print("PASS shiny3_test")
