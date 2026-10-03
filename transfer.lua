-- PC TRANSFERS (mod option, off by default): POKéMON between the party and
-- the PC boxes, items between the BAG and the item PC.
--
-- Every transfer is the game's own: the same checks its PC screens make and
-- the same side effects, through the engine's functions where it has them
-- (Gen 2's Boxes.deposit / withdraw, ItemPcMenu's PC stack math, Bag.add /
-- remove) and a faithful copy of the screen's rules where it has none (Gen
-- 1's BoxMenu / PlayerPC). Guard rails on top, so a save can't be damaged:
--   * every check runs before the first write: a refused request leaves
--     the save exactly as it was (the item order is the engine's own: the
--     receiving side is filled first, and only then the giving side emptied)
--   * only while the world stands still: no screen, battle, script or text
--     (platform.worldFree) and nothing a BAG / PC screen could hold a stale
--     list of (edits.editable)
--   * POKéMON are named by uid and items by id plus the count the page saw,
--     so anything that changed in between is refused as stale
--   * like every edit, only the save in memory changes: saving in-game
--     keeps it
--
-- Gen 1-only modules are named through constants (see platform.lua).
local GEN1_BOXES, GEN1_PARTY, GEN1_STATS = "src.pokemon.Boxes", "src.pokemon.Party", "src.pokemon.Stats"
local GEN1_FOLLOWER = "src.world.PikachuFollower"
local GEN2_BOXES, GEN2_MAIL = "src.core.gen2.Boxes", "src.core.gen2.Mail"
local GEN2_MON = "src.battle.gen2.Mon"

-- Gen 2: a boxed POKéMON can come without stats or HP (a loaded save's
-- box entries have none), and Boxes.withdraw only copies MAXHP over HP.
-- The party copy gets its stats now, at full HP (withdraw heals; an EGG
-- stays at 0), as the PARTY menu's refreshStats would give them: else the
-- next battle takes it for fainted (Battle.firstHealthy picks the lead
-- before the battle refreshes the stats) and sends out another POKéMON.
local function gen2PartyReady(game, mon)
    if type(mon) ~= "table" then return end
    local ok, Mon = pcall(require, GEN2_MON)
    if ok and Mon.refreshStats then pcall(Mon.refreshStats, mon, game.data) end
    if mon.isEgg then mon.hp = 0 else mon.hp = mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp end
end
local GEN2_ITEM_PC, GEN2_PC_ITEMS = "src.ui.gen2.ItemPcMenu", "src.core.gen2.PcItems"

return function(mod, uids, platform, edits)
    local Bag = require("src.inventory.Bag")
    local Sound = require("src.core.Sound")

    local T = {}

    function T.enabled()
        return mod.options:get("pc_transfer") == true
    end

    -- true, or nil plus the reason nothing may move right now
    local function gate(game)
        if not T.enabled() then return nil, "disabled" end
        local ok, why = edits.editable(game)
        if not ok then return nil, why end
        if not platform.worldFree(game) then return nil, "party busy" end
        return true
    end

    local function partyIndexOf(save, uid)
        for i, mon in ipairs(save.party or {}) do
            if uids.of(mon) == uid then return i end
        end
        return nil
    end

    local function wholeNumber(v)
        return type(v) == "number" and v == math.floor(v)
    end

    local function cry(game, mon)
        pcall(Sound.playCry, game.data, mon.species)
    end

    ---- POKéMON --------------------------------------------------------------

    -- DEPOSIT: party POKéMON uid to the end of box `box`
    function T.deposit(game, uid, box)
        local ok, why = gate(game)
        if not ok then return nil, why end
        if not wholeNumber(uid) or not wholeNumber(box) or box < 1 or box > platform.BOX_COUNT then
            return nil, "bad request"
        end
        local save = game.save
        local index = partyIndexOf(save, uid)
        if not index then return nil, "stale" end
        local mon = save.party[index]

        if platform.isGen2(game) then
            -- Boxes.canDeposit: full box, the last healthy POKéMON, MAIL
            local Boxes = require(GEN2_BOXES)
            local can = Boxes.canDeposit(save, index, box)
            if not can then
                if Boxes.isFull(save, box) then return nil, "full" end
                local okM, Mail = pcall(require, GEN2_MAIL)
                if okM and Mail.monHoldsMail(mon) then return nil, "mail" end
                return nil, "last mon"
            end
            -- moves the party's MAIL slots, heals and restores PP on entry
            local done = Boxes.deposit(save, index, box, game.data)
            if not done then return nil, "stale" end
            cry(game, mon)
            return true
        end

        -- Gen 1: BoxMenu's deposit, the same checks in its order
        local Boxes = require(GEN1_BOXES)
        local boxes = Boxes.ensure(save)
        local target = boxes[box]
        if not target then return nil, "bad request" end
        if #save.party <= 1 then return nil, "last mon" end
        if #target >= Boxes.CAPACITY then return nil, "full" end
        local okF, Follower = pcall(require, GEN1_FOLLOWER)
        if okF and Follower.isFollowingDisabled(game.overworld) and Follower.isStarterPikachu(save, mon) then
            return nil, "asleep"
        end
        table.remove(save.party, index)
        table.insert(target, mon)
        -- PIKAHAPPY_DEPOSITED (Yellow only; the function checks)
        if okF then pcall(Follower.modifyHappiness, save, "DEPOSITED", mon) end
        cry(game, mon)
        return true
    end

    -- WITHDRAW: boxed POKéMON uid to the end of the party
    function T.withdraw(game, uid)
        local ok, why = gate(game)
        if not ok then return nil, why end
        if not wholeNumber(uid) then return nil, "bad request" end
        local save = game.save
        local boxes = platform.editableBoxes(save)
        local box, slot = uids.findInBoxes(boxes, uid)
        if not box then return nil, "stale" end
        local mon = boxes[box][slot]

        if platform.isGen2(game) then
            -- Boxes.canWithdraw: a full party; withdraw heals on the way out
            local Boxes = require(GEN2_BOXES)
            if not Boxes.canWithdraw(save, box, slot) then return nil, "party full" end
            local done = Boxes.withdraw(save, box, slot)
            if not done then return nil, "stale" end
            gen2PartyReady(game, mon)
            cry(game, mon)
            return true
        end

        -- Gen 1: BoxMenu's withdraw
        local Party = require(GEN1_PARTY)
        local Stats = require(GEN1_STATS)
        if #(save.party or {}) >= Party.MAX then return nil, "party full" end
        -- a box mon carries no stat block (an imported save's may lack
        -- stats): the party copy gets them first, as the game's PC does
        Stats.ensure(game.data.pokemon[mon.species], mon)
        table.remove(boxes[box], slot)
        table.insert(save.party, mon)
        cry(game, mon)
        return true
    end

    -- SWAP: party POKéMON partyUid and boxed POKéMON boxUid trade places,
    -- for a full party and full boxes, where neither DEPOSIT nor WITHDRAW
    -- fits. The game has no such command, so it is the two applied at once:
    -- the checks of both (minus the room each would need, as the counts
    -- stay the same) and the effects of both, each POKéMON landing in the
    -- other's slot.
    function T.swap(game, partyUid, boxUid)
        local ok, why = gate(game)
        if not ok then return nil, why end
        if not wholeNumber(partyUid) or not wholeNumber(boxUid) then return nil, "bad request" end
        local save = game.save
        local index = partyIndexOf(save, partyUid)
        local boxes = platform.editableBoxes(save)
        local box, slot = uids.findInBoxes(boxes, boxUid)
        if not (index and box) then return nil, "stale" end
        local out, incoming = save.party[index], boxes[box][slot]

        if platform.isGen2(game) then
            local Boxes = require(GEN2_BOXES)
            local okM, Mail = pcall(require, GEN2_MAIL)
            -- DEPOSIT's MAIL rule for the one going in
            if okM and Mail.monHoldsMail(out) then return nil, "mail" end
            -- DEPOSIT's last-healthy rule, counting the one coming out (healed
            -- on withdraw, so it can fight unless it is an EGG)
            local healthy = Boxes.healthyCount(save.party) - (((out.hp or 0) > 0) and 1 or 0)
            if not incoming.isEgg then healthy = healthy + 1 end
            if healthy < 1 then return nil, "last mon" end
            -- the effects: WITHDRAW's heal on the way out, enterBox (heal and
            -- PP) on the way in; the slot's letter entry goes, as a deposit's
            -- does (its POKéMON held no MAIL)
            incoming.status, incoming.statusTurns = nil, nil
            incoming.hp = incoming.isEgg and 0 or (incoming.maxHp or incoming.hp)
            gen2PartyReady(game, incoming)
            save.party[index] = incoming
            boxes[box][slot] = out
            Boxes.enterBox(out, game.data)
            if okM then Mail.set(save, index, nil) end
            cry(game, incoming)
            return true
        end

        -- Gen 1: DEPOSIT's sleeping-PIKACHU rule; the party keeps its size,
        -- so the last-POKéMON rule can't be broken
        local okF, Follower = pcall(require, GEN1_FOLLOWER)
        if okF and Follower.isFollowingDisabled(game.overworld) and Follower.isStarterPikachu(save, out) then
            return nil, "asleep"
        end
        -- WITHDRAW's stats for a box mon, then both moves
        local Stats = require(GEN1_STATS)
        Stats.ensure(game.data.pokemon[incoming.species], incoming)
        save.party[index] = incoming
        boxes[box][slot] = out
        if okF then pcall(Follower.modifyHappiness, save, "DEPOSITED", out) end
        cry(game, incoming)
        return true
    end

    ---- items ----------------------------------------------------------------

    -- An item that always moves one (the PC never asks "How many?"):
    -- Gen 1 key items and HMs (PlayerPC IsKeyItem), Gen 2 items that can't
    -- be tossed (ItemPcMenu:cantToss)
    function T.onlyOne(game, id)
        local def = game.data.items and game.data.items[id]
        if platform.isGen2(game) then return type(def) == "table" and def.canToss == false end
        return (type(def) == "table" and def.keyItem) and true or tostring(id):find("^HM_") ~= nil
    end

    local function pcStore(save)
        save.pcItems = save.pcItems or {}
        return save.pcItems
    end

    -- the item PC, in the order its WITHDRAW list shows: Gen 2's own order
    -- (PcItems.order), Gen 1's sorted by id (PlayerPC buildItems)
    function T.pcItems(game)
        local save = game and game.save
        if not save then return {} end
        local pc = pcStore(save)
        local order
        if platform.isGen2(game) then
            local okP, PcItems = pcall(require, GEN2_PC_ITEMS)
            order = okP and PcItems.order(save, game.data.items) or {}
        else
            order = {}
            for id in pairs(pc) do order[#order + 1] = id end
            table.sort(order)
        end
        local out = {}
        for _, id in ipairs(order) do
            local count = pc[id]
            if count and count > 0 then
                local def = game.data.items and game.data.items[id]
                local one = T.onlyOne(game, id)
                out[#out + 1] = {
                    id = tostring(id), name = type(def) == "table" and def.name or (tostring(id):gsub("_", " ")),
                    count = count, one = one or nil
                }
            end
        end
        return out
    end

    -- qty and the count the page saw, checked against what is there
    local function checkQuantity(game, id, qty, seen, have)
        if not wholeNumber(qty) or qty < 1 then return nil, "bad request" end
        if seen ~= nil and seen ~= have then return nil, "stale" end
        if T.onlyOne(game, id) then qty = 1 end
        if qty > have then return nil, "stale" end
        return qty
    end

    -- DEPOSIT ITEM: qty of bag item id into the PC
    function T.itemToPc(game, id, qty, seen)
        local ok, why = gate(game)
        if not ok then return nil, why end
        if type(id) ~= "string" then return nil, "bad request" end
        local save = game.save
        local have = (save.inventory or {})[id] or 0
        if have <= 0 or Bag.isBadge(id) then return nil, "stale" end
        local n, err = checkQuantity(game, id, qty, seen, have)
        if not n then return nil, err end
        local pc = pcStore(save)

        if platform.isGen2(game) then
            -- ItemPcMenu:deposit: room in the PC first (50 stacks of 99),
            -- only then out of the PACK
            local ItemPcMenu = require(GEN2_ITEM_PC)
            if not ItemPcMenu.pcAdd({ save = save }, id, n) then return nil, "pc full" end
            Bag.remove(save, id, n)
            local okP, PcItems = pcall(require, GEN2_PC_ITEMS)
            if okP then PcItems.order(save, game.data.items) end
            return true
        end

        -- Gen 1: PlayerPC's deposit (a new stack needs a free one of 50)
        if not pc[id] then
            local cap = (game.data.field or {}).pcItemCap or 50
            local stacks = 0
            for _ in pairs(pc) do stacks = stacks + 1 end
            if stacks >= cap then return nil, "pc full" end
        end
        Bag.remove(save, id, n)
        pc[id] = (pc[id] or 0) + n
        pcall(Sound.play, game.data, "Withdraw_Deposit")
        return true
    end

    -- WITHDRAW ITEM: qty of PC item id into the bag
    function T.itemToBag(game, id, qty, seen)
        local ok, why = gate(game)
        if not ok then return nil, why end
        if type(id) ~= "string" then return nil, "bad request" end
        local save = game.save
        local pc = pcStore(save)
        local have = pc[id] or 0
        if have <= 0 then return nil, "stale" end
        local n, err = checkQuantity(game, id, qty, seen, have)
        if not n then return nil, err end
        -- both games: into the bag first (Bag.add refuses a full pocket or a
        -- stack past 99 and then adds nothing), only then out of the PC
        if not Bag.add(save, id, n, game.data) then return nil, "bag full" end
        if platform.isGen2(game) then
            local ItemPcMenu = require(GEN2_ITEM_PC)
            ItemPcMenu.pcRemove({ save = save }, id, n)
            local okP, PcItems = pcall(require, GEN2_PC_ITEMS)
            if okP then PcItems.order(save, game.data.items) end
            return true
        end
        pc[id] = have - n
        if pc[id] <= 0 then pc[id] = nil end
        pcall(Sound.play, game.data, "Withdraw_Deposit")
        return true
    end

    return T
end
