-- SHINY HUNT (hunt.lua): every save.loaded counts once the save is bound,
-- the count lives in mod.storage per playthrough, - / + / RESET work, and
-- nothing counts or shows while the option is off. Development only
-- (.modkitignore). From the gen1recomp root:
--   luajit mods/second_screen_companion/tests/hunt_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(label, pass)
    print((pass and "PASS " or "FAIL ") .. label)
    if not pass then failed = failed + 1 end
end

-- a mod facade: options, events, and a storage keyed like the engine's
-- (game version + playthrough id), which only answers for a bound save
local options = { shiny_hunt = true }
local handlers = {}
local disk = {}
local function scope(game)
    local save = game and game.save
    local id = save and save.meta and save.meta.playthroughId
    if not (save and save.version and id) then return nil end
    return save.version .. "/" .. id
end
local mod = {
    log = { warn = function() end },
    options = { get = function(_, key) return options[key] end },
    events = { on = function(_, name, fn) handlers[name] = fn end },
    storage = {
        context = function(_, game)
            local s = scope(game)
            if not s then return nil, "not_in_playthrough" end
            return { gameVersion = game.save.version, playthroughId = game.save.meta.playthroughId }
        end,
        read = function(_, game, key)
            local s = scope(game)
            return s and disk[s .. ":" .. key] or nil
        end,
        write = function(_, game, key, value)
            local s = scope(game)
            if not s then return false, "not_in_playthrough" end
            disk[s .. ":" .. key] = { count = value.count }
            return true
        end,
    },
}
local function loaded() handlers["save.loaded"]({}) end

local H = assert(loadfile("mods/second_screen_companion/hunt.lua"))()(mod)
check("listens to save.loaded", type(handlers["save.loaded"]) == "function")

local title = { save = nil }
local red = { save = { version = "red", meta = { playthroughId = "aaa" } } }

-- a load before the save is bound waits, then counts
loaded()
H.tick(title)
check("no save bound: nothing shown yet", H.state(title) == nil)
H.tick(red)
check("counted once the save is bound", H.state(red).count == 1)
loaded(); loaded()
H.tick(red)
check("two more loads", H.state(red).count == 3)
check("kept in storage", disk["red/aaa:shiny_hunt"].count == 3)

-- the title screen between resets still shows the last count
check("title screen keeps the last count", H.state(title) and H.state(title).count == 3)

-- - / + / RESET
check("+1", H.add(red, 1) == true and H.state(red).count == 4)
check("-1", H.add(red, -1) == true and H.state(red).count == 3)
local ok, err = H.add(red, 5)
check("only one at a time", ok == nil and err == "bad request")
check("RESET to 0", H.clear(red) == true and H.state(red).count == 0)
check("never below 0", H.add(red, -1) == true and H.state(red).count == 0)

-- another playthrough has its own count; the first one is still there
local blue = { save = { version = "blue", meta = { playthroughId = "bbb" } } }
loaded()
H.tick(blue)
check("another playthrough: its own count", H.state(blue).count == 1 and disk["red/aaa:shiny_hunt"].count == 0)

-- a New Game without an identity yet: a look doesn't make storage give it one
local fresh = { save = { version = "red", meta = {} } }
check("new game: no count shown", H.state(fresh) == nil or H.state(fresh).count == 1)

-- option off: nothing counts, nothing shows, the buttons refuse
options.shiny_hunt = false
loaded()
H.tick(blue)
check("off: not shown", H.state(blue) == nil)
local okOff, errOff = H.add(blue, 1)
check("off: buttons refuse", okOff == nil and errOff == "hunt off")
options.shiny_hunt = true
check("on again: the load while off didn't count", H.state(blue).count == 1)

-- Untamed Tohjo's chain (overworldmons), read from the save's mod data
local found = {}
mod.find = function(id) return found[id] end
local chained = { save = { modData = { overworldmons = { chainSpecies = "SPEAROW", chainCount = 12 } } } }
check("chain: nothing without Untamed Tohjo", H.chain(chained) == nil)
found.overworldmons = { id = "overworldmons" }
local c = H.chain(chained)
check("chain: species and length", c and c.species == "SPEAROW" and c.count == 12)
check("chain: Tohjo's odds, one 1/8192 roll per link", c and math.abs(c.odds - (1 - (8191 / 8192) ^ 12)) < 1e-12)
chained.save.modData.overworldmons.chainSpecies = ""
check("chain: none running", H.chain(chained) == nil)
options.shiny_hunt = false
chained.save.modData.overworldmons.chainSpecies = "SPEAROW"
check("chain: hidden with SHINY HUNT off", H.chain(chained) == nil)
options.shiny_hunt = true

-- Untamed Advanced (Gen 3): its RAM chain through mod.exports.engine.Owe
found.overworldmons = nil
local chainS, chainN = 16, 7 -- PIDGEY's engine number, 7 defeated
local engine = { C = { OWE_ROGUE_CHAIN = true }, Owe = { chainState = function() return chainS, chainN end } }
found.untamed_advanced = { id = "untamed_advanced", exports = { engine = engine } }
local c3 = H.chain({ save = {} })
check("Gen 3 chain: species as the DEXNAV id, and length", c3 and c3.species == "16" and c3.count == 7)
check("Gen 3 chain: no odds without its curve", c3 and c3.odds == nil)
engine.Owe._chain = { shinyOdds = function() return 16 end }
local c3o = H.chain({ save = {} })
check("Gen 3 chain: its curve on top of the PID's 1/8192",
    c3o and math.abs(c3o.odds - (1 - (8191 / 8192) * (15 / 16))) < 1e-12)
engine.Owe._chain = nil
engine.C.OWE_ROGUE_CHAIN = false
check("Gen 3 chain: hidden with its Chaining option off", H.chain({ save = {} }) == nil)
engine.C.OWE_ROGUE_CHAIN = true
chainS, chainN = nil, 0
check("Gen 3 chain: none running", H.chain({ save = {} }) == nil)
found.untamed_advanced = nil

-- Modern Spawns: its published chain; the shiny bonus only with Wilds of Hoenn
local msChain = { species = "PIDGEY", count = 12 }
local msBonus = { shiny = 1 - (8191 / 8192) ^ 12, perfectIvs = 1 }
local msApi = {
    isActive = function() return true end,
    chain = function() return msChain end,
    chainBonus = function() return msBonus end,
    profileOf = function() return { dex = 16 } end,
}
found.modern_spawns = { id = "modern_spawns", exports = msApi }
check("Modern Spawns, Gen 1/2: no chain (nothing makes its shinies)", H.chain({ save = {} }, false) == nil)
check("Modern Spawns, Gen 3 without Wilds of Hoenn: no chain", H.chain({ save = {} }, true) == nil)
found.wilds_of_hoenn = { id = "wilds_of_hoenn" }
msBonus = nil
check("Modern Spawns: hidden with SHINY CHAINS off", H.chain({ save = {} }, true) == nil)
msBonus = { shiny = 0.01 }
package.loaded["src.core.game3.pokemon"] = { speciesFromNational = function(n) return n == 16 and 16 or nil end }
local m3 = H.chain({ save = {} }, true)
check("Modern Spawns + Wilds of Hoenn, Gen 3: engine number and odds", m3 and m3.species == "16"
    and math.abs(m3.odds - (1 - (8191 / 8192) * 0.99)) < 1e-12)
package.loaded["src.core.game3.pokemon"] = nil
found.modern_spawns, found.wilds_of_hoenn = nil, nil

-- Wilds of Kanto Revival's SHINY RATE (wild Pokémon only)
local revival = { mods = { modOptions = {}, optionSchemas = { wilds_of_kanto_gen3 = {
    { key = "shiny_rate", default = "modern" } } } }, save = { options = { modOptions = {} } } }
check("wild rate: nothing without Revival", H.wildRate(revival) == nil)
found.wilds_of_kanto_gen3 = { id = "wilds_of_kanto_gen3" }
local w = H.wildRate(revival)
check("wild rate: its default 1/4096", w and math.abs(w.odds - 1 / 4096) < 1e-12)
revival.mods.modOptions.wilds_of_kanto_gen3 = { shiny_rate = "often" }
check("wild rate: the loader's option", math.abs(H.wildRate(revival).odds - 1 / 100) < 1e-12)
revival.save.options.modOptions.wilds_of_kanto_gen3 = { shiny_rate = "gen2" }
check("wild rate: the save's option wins", math.abs(H.wildRate(revival).odds - 1 / 8192) < 1e-12)
revival.save.options.modOptions.wilds_of_kanto_gen3.shiny_rate = "off"
check("wild rate: off", H.wildRate(revival).odds == 0)
revival.save.options.modOptions.wilds_of_kanto_gen3.shiny_rate = true
check("wild rate: an old 'true' means always", H.wildRate(revival).odds == 1)

if failed > 0 then
    print(("FAIL hunt_test (%d)"):format(failed))
    os.exit(1)
end
print("PASS hunt_test")
