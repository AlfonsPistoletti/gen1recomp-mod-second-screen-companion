-- PC TRANSFERS on Gen 1: item moves between the BAG and the item PC follow
-- the engine's PC rules (stacks of 99 in 50 slots) and never lose or make
-- items. Development only (.modkitignore). From the gen1recomp root:
--   luajit mods/second_screen_companion/tests/transfer_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = _G.love or require("tests.love_stub")
local Bag = require("src.inventory.Bag")

local failed = 0
local function check(label, pass)
    print((pass and "PASS " or "FAIL ") .. label)
    if not pass then failed = failed + 1 end
end

local mod = { options = { get = function(_, key) return key == "pc_transfer" end } }
local platform = {
    BOX_COUNT = 12,
    isGen2 = function() return false end,
    worldFree = function() return true end,
}
local edits = { editable = function() return true end }
local T = assert(loadfile("mods/second_screen_companion/transfer.lua"))()(mod, {}, platform, edits)

local data = { items = {}, field = { pcItemCap = 50 }, constants = {} }
for i = 1, 60 do
    local id = ("ITEM_%02d"):format(i)
    data.items[id] = { name = id }
end
data.items.POTION = { name = "POTION" }

local function total(save, id)
    return (save.inventory[id] or 0) + (save.pcItems[id] or 0)
end

-- a PC with 49 single stacks and POTION x99 in the 50th slot
local function fullPc()
    local save = { inventory = {}, pcItems = {}, party = {} }
    local game = { save = save, data = data }
    for i = 1, 49 do Bag.pcAdd(save, ("ITEM_%02d"):format(i), 1, data, 50) end
    Bag.pcAdd(save, "POTION", 99, data, 50)
    Bag.add(save, "POTION", 50, data)
    return game, save
end

do
    -- POTION x99 is a full stack: 50 more need a 51st slot, as the game refuses
    local game, save = fullPc()
    local ok, err = T.itemToPc(game, "POTION", 50, 50)
    check("deposit past the 50th slot is refused", ok == nil and err == "pc full")
    check("a refused deposit changes nothing", save.inventory.POTION == 50 and save.pcItems.POTION == 99)
end

do
    -- the same into a PC with room: the 99 + 50 land as two stacks
    local game, save = fullPc()
    Bag.pcRemove(save, "ITEM_01", 1, data)
    local ok = T.itemToPc(game, "POTION", 50, 50)
    check("deposit into a free slot works", ok == true)
    check("deposit keeps the total", total(save, "POTION") == 149 and not save.inventory.POTION)
    check("deposit takes the engine's slots", Bag.storeSlots(save.pcItems, data, nil, save.pcStacks) == 50)
    local listed = 0
    for _, row in ipairs(T.pcItems(game)) do
        if row.id == "POTION" then
            listed = listed + 1
            check("the PC list shows POTION's total", row.count == 149)
        end
    end
    check("the PC list shows POTION once", listed == 1)

    ok = T.itemToBag(game, "POTION", 120, 149)
    check("withdraw works", ok == true)
    check("withdraw keeps the total", total(save, "POTION") == 149 and save.pcItems.POTION == 29)
    local _, stale = T.itemToBag(game, "POTION", 1, 149)
    check("a count the page saw before is stale", stale == "stale")
end

if failed > 0 then
    print(("FAIL transfer_test (%d)"):format(failed))
    os.exit(1)
end
print("PASS transfer_test")
