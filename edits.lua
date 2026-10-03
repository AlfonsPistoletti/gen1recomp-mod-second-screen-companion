-- Save edits requested by the phone. Like the in-game BAG / PC menus they
-- change the save in memory; saving in-game persists them.
--
-- Why an edit is safe at almost any moment: it runs from core.update on the
-- main thread, between game updates, and completes in one go. A save the
-- game writes therefore sees either the old or the new order, never half of
-- one. Walking, warps, scripts, text and battles never hold a position in
-- the bag order or a box across frames (scripts give / take by item id or
-- append to a box), so a second player can rearrange while the first one
-- plays. Online trades that address box slots only run from the launcher
-- with the game closed (src/online/Trade.lua openSlot).
return function(mod, uids, platform, bagsort)
    local Bag = require("src.inventory.Bag")
    local Sound = require("src.core.Sound")

    local E = {}

    -- The screens that list the bag / item PC / boxes while open: an edit
    -- under them would leave their list stale, so a SELECT swap, a withdraw
    -- or a RELEASE by position could hit a different entry than the one
    -- shown. Every way in pushes them through the Screens registry, which
    -- stamps screenId, also on a mod's replacement screen. Their sub-lists
    -- and prompts are pushed on top, so scanning the whole stack covers them.
    -- Trading pauses every edit (platform.isTrading).

    -- true, or false plus "not loaded" (no save / world yet), "trading"
    -- or "busy" (a BAG / PC / shop screen is open)
    function E.editable(game)
        if not (game and game.save and platform.world(game)) then return false, "not loaded" end
        local busy = false
        for _, state in ipairs(game.stack and game.stack.states or {}) do
            if platform.isTrading(state) then return false, "trading" end
            if platform.isStorageScreen(state) then busy = true end
        end
        if busy then return false, "busy" end
        return true
    end

    local function swapSound(game)
        pcall(Sound.play, game.data, platform.isGen2(game) and "Sfx_SwitchPokemon" or "Swap")
    end

    -- Which pocket an item sits in (Gen 1 has one bag: everything is ITEM).
    function E.pocketOf(game, id)
        if not platform.isGen2(game) then return "ITEM" end
        local ok, pocket = pcall(Bag.pocketOf, id, game.data)
        return ok and pocket or "ITEM"
    end

    -- Gold's TM/HM pocket is always shown sorted by number (engine/items/
    -- tmhm.asm), so its order cannot be changed.
    function E.pocketFixed(game, pocket)
        return platform.isGen2(game) and pocket == "TM_HM"
    end

    -- The BAG's SELECT swap: exchange two entries of the live order table,
    -- within one pocket.
    function E.bagSwap(game, a, b)
        local ok, why = E.editable(game)
        if not ok then return nil, why end
        if type(a) ~= "string" or type(b) ~= "string" then return nil, "bad request" end
        local order = Bag.order(game.save, game.data)
        local ia, ib
        for i, id in ipairs(order) do
            if id == a then ia = i end
            if id == b then ib = i end
        end
        if not (ia and ib) then return nil, "stale" end
        local pocket = E.pocketOf(game, a)
        if pocket ~= E.pocketOf(game, b) then return nil, "other pocket" end
        if E.pocketFixed(game, pocket) then return nil, "fixed pocket" end
        if ia ~= ib then
            order[ia], order[ib] = order[ib], order[ia]
            swapSound(game)
        end
        return true
    end

    -- SORT: the bag in a new order (bagsort.lua: "kind", "name" or
    -- "number"). Only the order changes: the same ids, each once. Gen 2 sorts
    -- each pocket within that pocket's own places in the list (the way
    -- Bag.move rotates one pocket); the TM/HM pocket is always listed by
    -- number, so it is left as it is.
    function E.bagSort(game, by)
        local ok, why = E.editable(game)
        if not ok then return nil, why end
        if not (bagsort and bagsort.ORDERS[by]) then return nil, "bad request" end
        local gen2 = platform.isGen2(game)
        local order = Bag.order(game.save, game.data)
        -- the places each pocket holds in the list, and its ids in order
        local groups, keys = {}, {}
        for i, id in ipairs(order) do
            local pocket = E.pocketOf(game, id)
            if not groups[pocket] then
                groups[pocket] = { slots = {}, ids = {} }
                keys[#keys + 1] = pocket
            end
            local g = groups[pocket]
            g.slots[#g.slots + 1] = i
            g.ids[#g.ids + 1] = id
        end
        local result = {}
        for i, id in ipairs(order) do result[i] = id end
        for _, pocket in ipairs(keys) do
            if not E.pocketFixed(game, pocket) then
                local g = groups[pocket]
                local sortedIds = bagsort.sorted(game.data, g.ids, by, gen2)
                for k, slot in ipairs(g.slots) do result[slot] = sortedIds[k] end
            end
        end
        -- written in place, one entry at a time, so the list itself (which
        -- the game holds) stays the same table
        local changed = false
        for i = 1, #order do
            if order[i] ~= result[i] then
                order[i] = result[i]
                changed = true
            end
        end
        if changed then swapSound(game) end
        return true
    end

    -- UNDO for SORT: put back an order the page saw. Accepted only as an
    -- exact rearrangement of the bag as it is now (every id once, nothing
    -- new, nothing missing) that leaves every place in its pocket and the
    -- TM/HM pocket as it is; anything else is stale.
    function E.bagSetOrder(game, ids)
        local ok, why = E.editable(game)
        if not ok then return nil, why end
        if type(ids) ~= "table" then return nil, "bad request" end
        local order = Bag.order(game.save, game.data)
        if #ids ~= #order then return nil, "stale" end
        local count = {}
        for _, id in ipairs(order) do count[id] = (count[id] or 0) + 1 end
        for i = 1, #ids do
            local id = ids[i]
            if type(id) ~= "string" or not count[id] or count[id] < 1 then return nil, "stale" end
            count[id] = count[id] - 1
            local pocket = E.pocketOf(game, order[i])
            if E.pocketOf(game, id) ~= pocket then return nil, "stale" end
            if E.pocketFixed(game, pocket) and id ~= order[i] then return nil, "stale" end
        end
        for i = 1, #order do order[i] = ids[i] end
        swapSound(game)
        return true
    end

    ---- party ---------------------------------------------------------------

    local WAIT_SECONDS = 2 -- how long a SWITCH made mid-step may wait
    local pendingSwap -- { a, b, uidA, uidB, expires }

    local function partySlotOf(party, uid)
        for i, mon in ipairs(party or {}) do
            if uids.of(mon) == uid then return i end
        end
        return nil
    end

    -- whether the party can be reordered right now (the game's own rule:
    -- WorldAPI:canReorderParty, free roam with 2+ mons)
    function E.partyEditable(game)
        local ok, why = E.editable(game)
        if not ok and why ~= "busy" then return false, why end
        local w = mod.world
        if not (w and w.canReorderParty) then return false, "unavailable" end
        local okC, can = pcall(w.canReorderParty, w)
        if okC and can then return true end
        if #((game.save and game.save.party) or {}) < 2 then return false, "one mon" end
        -- walking counts as free: a SWITCH made mid-step waits for the step
        if platform.worldFree(game) then return true end
        return false, "party busy"
    end

    -- Swap two party slots with the game's SWITCH (WorldAPI:reorderParty:
    -- its sound, and on Gen 2 the MAIL moves with the mon). uidA / uidB
    -- name the mons the page saw, so a party that changed in between is
    -- refused instead of swapping the wrong two.
    local function runSwap(game, p)
        local party = game.save and game.save.party or {}
        local a, b = partySlotOf(party, p.uidA), partySlotOf(party, p.uidB)
        if not (a and b) then return nil, "stale" end
        return mod.world:reorderParty(a, b)
    end

    function E.partySwap(game, uidA, uidB)
        if type(uidA) ~= "number" or type(uidB) ~= "number" then return nil, "bad request" end
        local ok, why = E.partyEditable(game)
        if not ok then return nil, why end
        local p = { uidA = uidA, uidB = uidB }
        local done, err = runSwap(game, p)
        if done then return true end
        if err == "world is busy" and platform.worldFree(game) then
            p.expires = love.timer.getTime() + WAIT_SECONDS
            pendingSwap = p
            return true
        end
        if err == "world is busy" then return nil, "party busy" end
        return nil, err == "stale" and "stale" or "bad request"
    end

    -- every frame: a SWITCH that waited for the step to end
    function E.tick(game)
        if not pendingSwap then return end
        if love.timer.getTime() > pendingSwap.expires or not platform.worldFree(game) then
            pendingSwap = nil
            return
        end
        local done, err = runSwap(game, pendingSwap)
        if done or err ~= "world is busy" then pendingSwap = nil end
    end

    -- Swap monUid with targetUid (any boxes), or, without a target, move it
    -- to the end of targetBox.
    function E.boxMove(game, monUid, targetUid, targetBox)
        local ok, why = E.editable(game)
        if not ok then return nil, why end
        if type(monUid) ~= "number" then return nil, "bad request" end
        local boxes = platform.editableBoxes(game.save)
        local fromBox, fromSlot = uids.findInBoxes(boxes, monUid)
        if not fromBox then return nil, "stale" end

        if targetUid ~= nil then
            if type(targetUid) ~= "number" then return nil, "bad request" end
            local toBox, toSlot = uids.findInBoxes(boxes, targetUid)
            if not toBox then return nil, "stale" end
            local a, b = boxes[fromBox], boxes[toBox]
            a[fromSlot], b[toSlot] = b[toSlot], a[fromSlot]
            swapSound(game)
            return true
        end

        if type(targetBox) ~= "number" or targetBox ~= math.floor(targetBox)
            or targetBox < 1 or targetBox > platform.BOX_COUNT or not boxes[targetBox] then
            return nil, "bad request"
        end
        if targetBox ~= fromBox and #boxes[targetBox] >= platform.BOX_CAPACITY then
            return nil, "full"
        end
        local mon = table.remove(boxes[fromBox], fromSlot)
        table.insert(boxes[targetBox], mon)
        swapSound(game)
        return true
    end

    ---- GIVE TO HOLD (Gen 2) ------------------------------------------------

    -- HeldItemMenu:canHold: not a KEY ITEM, and tossable (so HMs stay out;
    -- TMs can be held, as on the cartridge)
    function E.canHold(game, id)
        local def = game.data.items and game.data.items[id]
        if type(def) ~= "table" then return false end
        return def.pocket ~= "KEY_ITEM" and def.canToss ~= false
    end

    local function isMail(id)
        local ok, Mail = pcall(require, "src.core.gen2.Mail")
        return ok and Mail.isMail(id) and true or false
    end
    E.isMail = isMail

    -- restore a table in place (the game holds these very tables)
    local function refill(t, from)
        for k in pairs(t) do t[k] = nil end
        for k, v in pairs(from) do t[k] = v end
    end

    -- The game's GIVE (HeldItemMenu:giveItem, TryGiveItemToPartymon): bag
    -- item id to party POKéMON uid; an item it already holds goes back to
    -- the bag. Every check runs first. MAIL is refused: giving it opens the
    -- letter keyboard in the game, which the phone can't fill in.
    function E.giveItem(game, id, uid)
        if not platform.isGen2(game) then return nil, "unavailable" end
        local ok, why = E.editable(game)
        if not ok then return nil, why end
        if not platform.worldFree(game) then return nil, "party busy" end
        if type(id) ~= "string" or type(uid) ~= "number" then return nil, "bad request" end
        local save = game.save
        local inv = save.inventory or {}
        if (inv[id] or 0) <= 0 or Bag.isBadge(id) then return nil, "stale" end
        local slot = partySlotOf(save.party, uid)
        if not slot then return nil, "stale" end
        local mon = save.party[slot]
        -- PackMenu:giveToSlot, then TryGiveItemToPartymon in its order
        if mon.isEgg then return nil, "egg" end
        if not E.canHold(game, id) then return nil, "cant hold" end
        if isMail(id) then return nil, "mail give" end
        local held = mon.item
        if held and isMail(held) then return nil, "mail" end
        if held == id then return true end
        if not held then
            Bag.remove(save, id, 1)
            mon.item = id
            return true
        end
        -- the swap: the old item back into the bag. A bag that can't take
        -- it gets everything back exactly as it was, order included.
        local invCopy, orderCopy = {}, {}
        for k, v in pairs(save.inventory) do invCopy[k] = v end
        local order = save.bagOrder
        if order then for i, v in ipairs(order) do orderCopy[i] = v end end
        Bag.remove(save, id, 1)
        if not Bag.add(save, held, 1, game.data) then
            refill(save.inventory, invCopy)
            if order then refill(order, orderCopy) end
            return nil, "bag full"
        end
        mon.item = id
        return true
    end

    ---- USE ON A POKéMON (medicine, vitamins, PP) ------------------------------

    -- the game's message as one line for the phone: its line and page breaks
    -- as spaces, and the placeholders the text box would fill in (the
    -- player's name, Gold's # for POKé)
    local function gameText(t, player)
        if type(t) == "table" then
            local parts = {}
            for _, s in ipairs(t) do
                local one = gameText(s, player)
                if one then parts[#parts + 1] = one end
            end
            return #parts > 0 and table.concat(parts, " ") or nil
        end
        if type(t) ~= "string" then return nil end
        player = tostring(player or "")
        t = t:gsub("{PLAYER}", player):gsub("<PLAYER>", player):gsub("#MON", "POKéMON"):gsub("#", "POKé")
        t = t:gsub("%c+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        return t ~= "" and t or nil
    end

    E.gameText = gameText

    -- Gen 1: the party-menu items of item_effects.asm the phone may use, and
    -- the ones that ask which move first (ItemUsePPRestore / ItemUsePPUp).
    -- RARE CANDY, the stones and the TMs play scenes in the game: not here.
    local GEN1_USE = {
        POTION = true, SUPER_POTION = true, HYPER_POTION = true, MAX_POTION = true,
        FULL_RESTORE = true, FRESH_WATER = true, SODA_POP = true, LEMONADE = true,
        ANTIDOTE = true, BURN_HEAL = true, ICE_HEAL = true, AWAKENING = true,
        PARLYZ_HEAL = true, FULL_HEAL = true, REVIVE = true, MAX_REVIVE = true,
        HP_UP = true, PROTEIN = true, IRON = true, CARBOS = true, CALCIUM = true,
        ETHER = true, MAX_ETHER = true, ELIXER = true, MAX_ELIXER = true, PP_UP = true,
    }
    local GEN1_PICKS_MOVE = { ETHER = true, MAX_ETHER = true, PP_UP = true }
    local GEN2_USE = { heal = true, status = true, revive = true, vitamin = true, pp = true }

    -- "mon" (pick a POKéMON), "move" (then one of its moves), "scene" (RARE
    -- CANDY, a stone, a TM / HM: picked here, played on the game screen) or nil
    function E.useKind(game, id)
        if type(id) ~= "string" then return nil end
        local def = game.data.items and game.data.items[id]
        if platform.isGen2(game) then
            if type(def) == "table" and def.teaches then return "scene" end
            -- Game2:usePartyItem's families (ItemEffects.partyAction), minus
            -- RARE CANDY and the stones; the ETHER family picks a move, the
            -- ELIXER pair doesn't (RESTORE_PP .each)
            local okI, ItemEffects = pcall(require, "src.core.gen2.ItemEffects")
            if not okI then return nil end
            local okA, action = pcall(ItemEffects.partyAction, id, game.data)
            if okA and (action == "candy" or action == "stone") then return "scene" end
            if not (okA and GEN2_USE[action]) then return nil end
            if action == "pp" then
                local row = ItemEffects.RESTORE_PP and ItemEffects.RESTORE_PP[id]
                return (row and row.each) and "mon" or "move"
            end
            return "mon"
        end
        if id == "RARE_CANDY" or (type(def) == "table" and def.machine) then return "scene" end
        local okI, ItemEffects = pcall(require, "src.inventory.ItemEffects")
        if okI and ItemEffects.isStone and ItemEffects.isStone(id) then return "scene" end
        if not GEN1_USE[id] then return nil end
        return GEN1_PICKS_MOVE[id] and "move" or "mon"
    end

    -- For a TM / HM or a stone: what each party POKéMON makes of it, as the
    -- game's party menu marks it ("able", "learned" or "no"), keyed by uid.
    -- nil for anything else.
    function E.ableFor(game, id)
        local data = game.data
        local def = data.items and data.items[id]
        if type(def) ~= "table" then return nil end
        local gen2 = platform.isGen2(game)
        local moveId = gen2 and def.teaches or (def.machine and def.machine.move)
        local stone = false
        if not moveId then
            if gen2 then
                local okI, ItemEffects = pcall(require, "src.core.gen2.ItemEffects")
                local okA, action = false, nil
                if okI then okA, action = pcall(ItemEffects.partyAction, id, data) end
                stone = okA and action == "stone"
            else
                local okI, ItemEffects = pcall(require, "src.inventory.ItemEffects")
                stone = okI and ItemEffects.isStone(id) and true or false
            end
            if not stone then return nil end
        end
        local out = {}
        for _, mon in ipairs(game.save and game.save.party or {}) do
            local uid = uids.of(mon)
            local sp = data.pokemon and data.pokemon[mon.species]
            local mark = "no"
            if uid and not mon.isEgg and type(sp) == "table" then
                if moveId then
                    -- the species' TM/HM list, then the moves it knows
                    for _, m in ipairs(sp.tmhm or {}) do if m == moveId then mark = "able" end end
                    for _, mv in ipairs(mon.moves or {}) do
                        if (type(mv) == "table" and mv.id or mv) == moveId then mark = "learned" end
                    end
                elseif gen2 then
                    -- the stone's own check (ItemEffects' stone record)
                    local okE, Evolution = pcall(require, "src.core.gen2.Evolution")
                    if okE and mon.item ~= "EVERSTONE" then
                        local okC, entry = pcall(Evolution.checkMon, data, mon, { force = true, item = id })
                        if okC and entry then mark = "able" end
                    end
                else
                    for _, evo in ipairs(sp.evolutions or {}) do
                        if evo.method == "ITEM" and evo.item == id then mark = "able" end
                    end
                end
            end
            if uid then out[tostring(uid)] = mark end
        end
        return out
    end

    -- Gen 1: what BagMenu's vanillaUseOn does after ItemEffects.use for the
    -- items that play on screen (src/ui/BagMenu.lua): a stone's evolution, a
    -- RARE CANDY's level text, stat box, new moves and evolution, a TM's
    -- teach (the forget prompt when four moves are known). The pieces are
    -- the game's own: TextBox, StatBox, MoveLearnMenu, Evolution.
    local function gen1Scene(game, id, mon, player)
        local ItemEffects = require("src.inventory.ItemEffects")
        local TextBox = require("src.render.TextBox")
        local Screens = require("src.ui.Screens")
        local Strings = require("src.core.Strings")
        local data, save = game.data, game.save
        local name = mon.nickname or (data.pokemon[mon.species] or {}).name or "?"
        local function say(msgs, onDone, opts)
            if type(msgs) == "string" then msgs = { msgs } end
            if not msgs or #msgs == 0 then
                if onDone then onDone() end
                return
            end
            game.stack:push(TextBox.new(game, table.concat(msgs, "\f"), onDone, opts))
        end
        local function jingle() return TextBox.soundOpts(game, "Get_Item1") end
        local function follower(fn, ...)
            local okF, Follower = pcall(require, "src.world.PikachuFollower")
            if okF and Follower[fn] then pcall(Follower[fn], ...) end
        end

        local okU, result, payload, extra = pcall(ItemEffects.use, data, save, id, mon, nil, nil, game.overworld)
        if not okU then
            mod.log:warn("use failed: %s", tostring(result))
            return nil, "stale"
        end

        -- TM / HM: "learn" (a TM, used up) or "learnkept" (an HM)
        if result == "learn" or result == "learnkept" then
            local moveId = payload
            local mdef = data.moves[moveId] or {}
            local function taught()
                follower("modifyHappiness", save, "USEDTMHM", mon)
                follower("onMoveLearned", save, mon, moveId)
            end
            if #mon.moves < 4 then
                table.insert(mon.moves, { id = moveId, pp = mdef.pp })
                if result == "learn" then Bag.remove(save, id, 1) end
                taught()
                local text = Strings("%s learned\n%s!", name, mdef.name or moveId)
                say(text, nil, jingle())
                return true, nil, { text = gameText(text, player), scene = true }
            end
            Screens.push(game, "MoveLearnMenu", mon, moveId, function(learned)
                if learned and result == "learn" then Bag.remove(save, id, 1) end
                if learned then taught() end
            end)
            return true, nil, { text = ("%s wants to learn %s: choose on the game screen."):format(name, mdef.name or moveId), scene = true }
        end
        if result ~= "consumed" then return nil, gameText(payload, player) or "no effect" end
        Bag.remove(save, id, 1)

        -- a stone: the evolution, which a stone's can't be cancelled ("ITEM")
        if extra and extra.evolveTo then
            require("src.pokemon.Evolution").evolve(game, mon, extra.evolveTo, function() end, "ITEM")
            return true, nil, { text = ("%s is evolving: look at the game screen."):format(name), scene = true }
        end

        -- RARE CANDY: the level text, the stat box, any new moves, then a
        -- level evolution (item_effects.asm .useRareCandy)
        if extra and extra.leveledTo then
            say(payload, function()
                local StatBox = require("src.battle.BattleState").StatBox
                local statBox
                local function dropStatBox()
                    if statBox and game.stack:top() == statBox then game.stack:pop() end
                    statBox = nil
                end
                statBox = StatBox.new(game, mon, function()
                    local Experience = require("src.battle.Experience")
                    local def = data.pokemon[mon.species]
                    local moves = Experience.movesLearnedAt(def, extra.leveledTo) or {}
                    local i = 0
                    local nextStep
                    nextStep = function()
                        i = i + 1
                        local moveId = moves[i]
                        if not moveId then
                            local Evolution = require("src.pokemon.Evolution")
                            local evoTo, evo = Evolution.pendingFor(game, mon, { kind = "levelup" })
                            if evoTo then
                                Evolution.evolve(game, mon, evoTo, dropStatBox, evo and evo.method)
                            else
                                dropStatBox()
                            end
                            return
                        end
                        for _, mv in ipairs(mon.moves) do
                            if mv.id == moveId then return nextStep() end
                        end
                        local mdef = data.moves[moveId] or {}
                        if #mon.moves < 4 then
                            table.insert(mon.moves, { id = moveId, pp = mdef.pp })
                            follower("onMoveLearned", save, mon, moveId)
                            say(Strings("%s learned\n%s!", name, mdef.name or moveId), nextStep, jingle())
                        else
                            Screens.push(game, "MoveLearnMenu", mon, moveId, nextStep)
                        end
                    end
                    nextStep()
                end, true)
                game.stack:push(statBox)
            end, jingle())
            return true, nil, { text = gameText(payload, player), scene = true }
        end
        return true, nil, { text = gameText(payload, player) }
    end

    -- Gen 2: the same, from Game2's own pieces: a stone through Game2:
    -- usePartyItem's evolution (Gen2EvolutionAnim, the stone spent only
    -- when it evolved), RARE CANDY through Game2:afterRareCandy (new moves,
    -- then evolution), a TM / HM through PackMenu:openTeachParty's checks
    -- and Game2:learnMoveOn (the forget prompt on the game screen).
    local function gen2Scene(game, id, mon, player)
        local ItemEffects = require("src.core.gen2.ItemEffects")
        local Screens = require("src.ui.Screens")
        local TextBox = require("src.render.TextBox")
        local Strings = require("src.core.Strings")
        local Mon = require("src.battle.gen2.Mon")
        local data, save = game.data, game.save
        local name = Mon.displayName(mon)
        local def = data.items and data.items[id]

        if type(def) == "table" and def.teaches then
            local moveId = def.teaches
            local mdef = data.moves and data.moves[moveId]
            local moveName = (mdef and mdef.name) or moveId
            local sp = data.pokemon and data.pokemon[mon.species]
            local allowed = false
            for _, m in ipairs((sp and sp.tmhm) or {}) do if m == moveId then allowed = true end end
            -- engine/items/tmhm.asm:131
            if not allowed then return nil, gameText(Strings("%s can't learn %s!", name, moveName), player) end
            for _, mv in ipairs(mon.moves or {}) do
                if mv.id == moveId then return nil, gameText(Strings("%s already knows %s!", name, moveName), player) end
            end
            if not game.learnMoveOn then return nil, "unavailable" end
            game:learnMoveOn(mon, moveId, function(learned)
                if not learned then return end
                if tostring(id):sub(1, 3) == "HM_" then return end
                pcall(function() require("src.core.gen2.Happiness").change(mon, "LEARNMOVE") end)
                game:consumeItem(id)
            end)
            return true, nil, { text = ("Teaching %s to %s: look at the game screen."):format(moveName, name), scene = true }
        end

        local action = ItemEffects.partyAction(id, data)
        local okU, result = pcall(ItemEffects.useOnMon, id, mon, data)
        if not okU then
            mod.log:warn("use failed: %s", tostring(result))
            return nil, "stale"
        end
        if not (type(result) == "table" and result.used) then
            return nil, gameText(result and result.text, player) or "no effect"
        end
        if action == "stone" then
            local index
            for i, member in ipairs(save.party or {}) do if member == mon then index = i end end
            Screens.push(game, "Gen2EvolutionAnim", {
                mon = mon, entry = result.evolution, index = index,
                party = save.party, save = save, force = true,
                onDone = function(evolution)
                    if evolution and evolution.evolved then game:consumeItem(id) end
                    game.stack:pop()
                    if game.restartMapMusicAfterEvolution then game:restartMapMusicAfterEvolution() end
                end,
            })
            return true, nil, { text = ("%s is evolving: look at the game screen."):format(name), scene = true }
        end
        -- RARE CANDY (data/text/common_1.asm:86)
        game:consumeItem(id)
        game:say(result.text, function() game:afterRareCandy(mon, result) end,
            result.sfx and TextBox.soundOpts(game, result.sfx) or nil)
        return true, nil, { text = gameText(result.text, player), scene = true }
    end

    -- The game's own use of an item on a party POKéMON, as its party menu
    -- runs it: Gen 1 ItemEffects.use (BagMenu's "consumed" path takes one
    -- out of the bag), Gen 2 ItemEffects.useOnMon / usePpItem (Game2:
    -- usePartyItem, then consumeItem). Free roam only, like GIVE. Returns
    -- true plus { text = the game's message }, or nil plus the reason (the
    -- game's own words when it refuses: "It won't have any effect.").
    function E.useItem(game, id, uid, moveSlot)
        local ok, why = E.editable(game)
        if not ok then return nil, why end
        if not platform.worldFree(game) then return nil, "party busy" end
        if type(id) ~= "string" or type(uid) ~= "number" then return nil, "bad request" end
        local kind = E.useKind(game, id)
        if not kind then return nil, "cant use" end
        if kind == "move" then
            if type(moveSlot) ~= "number" or moveSlot ~= math.floor(moveSlot) or moveSlot < 1 or moveSlot > 4 then
                return nil, "bad request"
            end
        else
            moveSlot = nil
        end
        local save = game.save
        local inv = save.inventory or {}
        if (inv[id] or 0) <= 0 then return nil, "stale" end
        local slot = partySlotOf(save.party, uid)
        if not slot then return nil, "stale" end
        local mon = save.party[slot]
        if mon.isEgg then return nil, "egg use" end
        if moveSlot and not (mon.moves and mon.moves[moveSlot]) then return nil, "stale" end
        local player = save.player and save.player.name

        if kind == "scene" then
            if not (game.stack and game.stack.push) then return nil, "unavailable" end
            local okS, done, err, info = pcall(platform.isGen2(game) and gen2Scene or gen1Scene, game, id, mon, player)
            if not okS then
                mod.log:warn("use failed: %s", tostring(done))
                return nil, "stale"
            end
            return done, err, info
        end

        if platform.isGen2(game) then
            local ItemEffects = require("src.core.gen2.ItemEffects")
            local action = ItemEffects.partyAction(id, game.data)
            local okU, result
            if action == "pp" then
                okU, result = pcall(ItemEffects.usePpItem, id, mon, moveSlot, game.data)
            else
                okU, result = pcall(ItemEffects.useOnMon, id, mon, game.data)
            end
            if not okU then
                mod.log:warn("use failed: %s", tostring(result))
                return nil, "stale"
            end
            if not (type(result) == "table" and result.used) then
                return nil, gameText(result and result.text, player) or "no effect"
            end
            if game.consumeItem then game:consumeItem(id) else Bag.remove(save, id, 1) end
            return true, nil, { text = gameText(result.text, player) }
        end

        local ItemEffects = require("src.inventory.ItemEffects")
        local okU, result, payload = pcall(ItemEffects.use, game.data, save, id, mon, nil, moveSlot, game.overworld)
        if not okU then
            mod.log:warn("use failed: %s", tostring(result))
            return nil, "stale"
        end
        if result ~= "consumed" then return nil, gameText(payload, player) or "no effect" end
        Bag.remove(save, id, 1)
        return true, nil, { text = gameText(payload, player) }
    end

    return E
end
