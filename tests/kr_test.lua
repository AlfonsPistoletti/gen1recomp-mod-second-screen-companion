-- Kanto Reforged support (kr.lua): without it every answer is "nothing";
-- with it (stand-ins for its modules) the Gen 1 BAG comes in its pockets,
-- the TMs & HMs one sorted by number, and the mons carry its ability,
-- gender and held item. Development only (.modkitignore). From the
-- gen1recomp root:
--   luajit mods/second_screen_companion/tests/kr_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = _G.love or require("tests.love_stub")

local failed = 0
local function check(label, pass)
    print((pass and "PASS " or "FAIL ") .. label)
    if not pass then failed = failed + 1 end
end

local DIR = "mods/second_screen_companion/"
local function factory(file) return assert(loadfile(DIR .. file))() end

-- a mod facade whose mod.find answers from `present`
local present = {}
local mod = {
    log = { warn = function() end, info = function() end, error = function() end },
    find = function(id) return present[id] end,
}

-- stand-ins for Kanto Reforged's own modules, under its require paths
package.loaded["mods.Kanto-Reforged.battle.ability_text"] = {
    describe = function(id) return id == "OVERGROW" and "Ups GRASS moves in a pinch." or "A mysterious ability." end,
}
local BERRIES = { CHERI_BERRY = true, BERRY = true }
package.loaded["mods.Kanto-Reforged.items.held_items"] = {
    isHoldable = function(id) return BERRIES[id] or id == "LEFTOVERS" end,
    isBerry = function(id) return BERRIES[id] or false end,
}
package.loaded["mods.Kanto-Reforged.items.bag_pockets"] = {
    POCKETS = {
        { id = "items", label = "ITEMS" }, { id = "balls", label = "BALLS" },
        { id = "key", label = "KEY ITEMS" }, { id = "tmhm", label = "TMs & HMs" },
        { id = "berries", label = "BERRIES" },
    },
    classify = function(id, def)
        if BERRIES[id] then return "berries" end
        if def and def.machine then return "tmhm" end
        if def and def.ball then return "balls" end
        return "items"
    end,
}
package.loaded["mods.Kanto-Reforged.battle.split_special"] = {
    OPTION_KEY = "split_special",
    calcSpStats = function() return { sp_attack = 55, sp_defense = 44 } end,
}

local kr = factory("kr.lua")(mod)

-- without Kanto Reforged
check("absent: not active", kr.active() == false)
check("absent: no ability text", kr.abilityText("OVERGROW") == nil)
check("absent: no pockets", kr.pockets() == nil and kr.pocketOf({}, "POTION") == nil)
check("absent: nothing holdable", kr.holdable("LEFTOVERS") == nil and kr.giveable({}, "LEFTOVERS") == nil)
check("absent: no roamers", #kr.roamersAt({ save = {} }, "ROUTE_1") == 0)

-- a version it wasn't written for
present["Kanto-Reforged"] = { id = "Kanto-Reforged", version = "2.0.0", exports = {} }
check("other major version: left out", kr.active() == false)

-- with Kanto Reforged
present["Kanto-Reforged"] = { id = "Kanto-Reforged", version = "1.7.7", exports = {} }
local game = {
    mods = { modOptions = { ["Kanto-Reforged"] = { bag_give = true } },
        optionSchemas = { ["Kanto-Reforged"] = { { key = "split_special", default = true } } } },
}
check("present: active", kr.active() == true)
check("present: ability text", kr.abilityText("OVERGROW") == "Ups GRASS moves in a pinch.")
check("present: option default from its schema", kr.option(game, "split_special") == true)
check("present: berry pocket", kr.pocketOf({ items = {} }, "CHERI_BERRY") == "berries")
check("present: GIVE a berry", kr.giveable(game, "CHERI_BERRY") == true)
game.mods.modOptions["Kanto-Reforged"].bag_give = false
check("BAG GIVE off: no GIVE", kr.giveable(game, "CHERI_BERRY") == false)
game.mods.modOptions["Kanto-Reforged"].bag_give = true

game.save = { modData = { ["Kanto-Reforged"] = { roamers = {
    active = { RAIKOU = true, ENTEI = true, SUICUNE = true },
    locations = { RAIKOU = "ROUTE_1", ENTEI = "ROUTE_1", SUICUNE = "ROUTE_2" },
    beaten = { ENTEI = true },
} } } }
local here = kr.roamersAt(game, "ROUTE_1")
check("roamers: active and not beaten, on this map only", #here == 1 and here[1] == "RAIKOU")

-- the snapshot's Gen 1 BAG and party with it
local data = {
    pokemon = { BULBASAUR = { id = "BULBASAUR", name = "BULBASAUR", types = { "GRASS", "POISON" },
        ability = "OVERGROW", sp_attack = 65, sp_defense = 65 } },
    moves = {},
    items = {
        POTION = { name = "POTION" }, POKE_BALL = { name = "POKé BALL", ball = true },
        CHERI_BERRY = { name = "CHERI BERRY" },
        TM_05 = { name = "TM05", machine = { kind = "TM", number = 5, move = "X" } },
        TM_01 = { name = "TM01", machine = { kind = "TM", number = 1, move = "X" } },
        HM_01 = { name = "HM01", machine = { kind = "HM", number = 1, move = "X" } },
    },
}
game.data = data
game.save.inventory = { POTION = 3, POKE_BALL = 5, CHERI_BERRY = 2, HM_01 = 1, TM_05 = 1, TM_01 = 1 }
game.save.bagOrder = { "HM_01", "POTION", "TM_05", "CHERI_BERRY", "POKE_BALL", "TM_01" }
game.save.party = { { species = "BULBASAUR", level = 5, gender = "F", heldItem = "CHERI_BERRY",
    stats = { hp = 20, attack = 10, defense = 10, speed = 10, special = 12 }, moves = {} } }
local platform = {
    BOX_CAPACITY = 20,
    gen = function() return 1 end,
    isGen2 = function() return false end,
    money = function() return 0 end,
}
local uids = { of = function() return 1 end }
local snapshot = factory("snapshot.lua")(mod, nil, uids, platform, kr)
local state = snapshot(game, {})

local ids = {}
for _, p in ipairs(state.bag.pockets or {}) do ids[#ids + 1] = p.id end
check("bag: KR's five pockets", table.concat(ids, ",") == "items,balls,key,tmhm,berries")
local fixed
for _, p in ipairs(state.bag.pockets or {}) do if p.fixed then fixed = p.id end end
check("bag: TMs & HMs is the fixed one", fixed == "tmhm")
local tms = {}
for _, it in ipairs(state.bag.items) do if it.pocket == "tmhm" then tms[#tms + 1] = it.id end end
check("bag: TMs, then HMs, by number", table.concat(tms, ",") == "TM_01,TM_05,HM_01")
local berry
for _, it in ipairs(state.bag.items) do if it.id == "CHERI_BERRY" then berry = it end end
check("bag: a berry can be given", berry and berry.pocket == "berries" and berry.hold == true)
check("bag: the UNDO order is the bag's own", table.concat(state.bag.order, ",") == table.concat(game.save.bagOrder, ","))

local mon = state.party[1]
check("mon: ability with its text", mon.ability and mon.ability.name == "OVERGROW" and mon.ability.desc ~= nil)
check("mon: gender from \"F\"", mon.gender == "female")
check("mon: held item from heldItem", mon.item and mon.item.id == "CHERI_BERRY")
local labels = {}
for _, s in ipairs(mon.statList) do labels[#labels + 1] = s.label end
check("mon: SP.ATK / SP.DEF in place of SPECIAL", table.concat(labels, ",") == "ATTACK,DEFENSE,SPEED,SP.ATK,SP.DEF")

-- and without it, the same save shows the plain Gen 1 BAG
present["Kanto-Reforged"] = nil
state = snapshot(game, {})
check("absent: one BAG, no pockets", state.bag.pockets == nil)
local plain = {}
for _, s in ipairs(state.party[1].statList) do plain[#plain + 1] = s.label end
check("absent: one SPECIAL", table.concat(plain, ",") == "ATTACK,DEFENSE,SPEED,SPECIAL")

if failed > 0 then
    print(("FAIL kr_test (%d)"):format(failed))
    os.exit(1)
end
print("PASS kr_test")
