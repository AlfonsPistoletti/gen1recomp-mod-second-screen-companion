-- The ITEM / PACK tab's SORT: a new order for the bag's ids, never a new
-- set of them (edits.lua checks that and writes it). Three orders:
--   kind    groups, then the game's item number inside each group
--   name    A-Z by the item's name (a language mod's names included)
--   number  the game's item number (index), as the cartridge lists items
--
-- Gen 2 reads an item's group from the ROM's own item attributes
-- (battleMenu / fieldMenu / heldEffect), so a mod's item with the same
-- attributes sorts with its kind. Gen 1's data has no such attributes: its
-- groups mirror the engine's own item-effect tables (src/inventory/
-- ItemEffects.lua: BALLS, HEAL_AMOUNT, STATUS_HEAL, X_ITEMS, VITAMINS,
-- STONES, REPELS), and anything unknown is OTHER.
local GEN1_ITEM_EFFECTS = "src.inventory.ItemEffects"
local GEN2_MAIL = "src.core.gen2.Mail"

return function()
    local B = {}

    -- group order
    local RANK = {
        BALLS = 1, MEDICINE = 2, BERRIES = 3, BATTLE = 4, BOOSTS = 5, FIELD = 6,
        HOLD = 7, MAIL = 8, OTHER = 9, TM = 10, HM = 11, KEY = 12,
    }
    B.RANK = RANK

    local function set(list)
        local out = {}
        for _, id in ipairs(list) do out[id] = true end
        return out
    end

    -- Gen 1, the engine's item-effect tables by name
    local GEN1 = {
        MEDICINE = set({ "POTION", "SUPER_POTION", "HYPER_POTION", "MAX_POTION", "FULL_RESTORE",
            "FRESH_WATER", "SODA_POP", "LEMONADE", "ANTIDOTE", "BURN_HEAL", "ICE_HEAL", "AWAKENING",
            "PARLYZ_HEAL", "FULL_HEAL", "REVIVE", "MAX_REVIVE", "ETHER", "MAX_ETHER", "ELIXER",
            "MAX_ELIXER" }),
        BATTLE = set({ "X_ATTACK", "X_DEFEND", "X_SPEED", "X_SPECIAL", "X_ACCURACY", "GUARD_SPEC",
            "DIRE_HIT", "POKE_DOLL" }),
        BOOSTS = set({ "HP_UP", "PROTEIN", "IRON", "CARBOS", "CALCIUM", "RARE_CANDY", "PP_UP",
            "FIRE_STONE", "WATER_STONE", "THUNDER_STONE", "LEAF_STONE", "MOON_STONE" }),
        FIELD = set({ "REPEL", "SUPER_REPEL", "MAX_REPEL", "ESCAPE_ROPE" }),
    }
    local gen1Balls
    do
        local ok, ItemEffects = pcall(require, GEN1_ITEM_EFFECTS)
        gen1Balls = ok and type(ItemEffects) == "table" and ItemEffects.BALLS or {}
    end
    local okMail, Mail = pcall(require, GEN2_MAIL)

    local function machineKind(def, id)
        local kind = type(def.machine) == "table" and def.machine.kind
        if kind == "HM" or tostring(id):find("^HM_") then return "HM" end
        if kind or def.teaches or tostring(id):find("^TM_") then return "TM" end
        return nil
    end

    local function kind1(def, id, data)
        if gen1Balls[id] or def.ball or (data.balls and data.balls[id]) then return "BALLS" end
        local machine = machineKind(def, id)
        if machine then return machine end
        if def.keyItem then return "KEY" end
        for group, ids in pairs(GEN1) do
            if ids[id] then return group end
        end
        return "OTHER"
    end

    local function kind2(def, id)
        if def.pocket == "BALL" then return "BALLS" end
        if def.pocket == "KEY_ITEM" then return "KEY" end
        if def.pocket == "TM_HM" then return machineKind(def, id) or "TM" end
        local battle, field = def.battleMenu, def.fieldMenu
        local held = def.heldEffect ~= nil and def.heldEffect ~= "HELD_NONE"
        if okMail and Mail.isMail and Mail.isMail(id) then return "MAIL" end
        if battle == "ITEMMENU_PARTY" then return held and "BERRIES" or "MEDICINE" end
        if battle == "ITEMMENU_CLOSE" then return "BATTLE" end
        if field == "ITEMMENU_PARTY" then return "BOOSTS" end
        if field == "ITEMMENU_CURRENT" or field == "ITEMMENU_CLOSE" then return "FIELD" end
        if held then return "HOLD" end
        return "OTHER"
    end

    function B.kindOf(data, id, gen2)
        local def = (data.items or {})[id]
        if type(def) ~= "table" then return "OTHER" end
        return gen2 and kind2(def, id) or kind1(def, id, data)
    end

    B.ORDERS = { kind = true, name = true, number = true }

    -- ids sorted by `by`; a stable sort (ties keep their current order)
    function B.sorted(data, ids, by, gen2)
        local items = data.items or {}
        local rows = {}
        for i, id in ipairs(ids) do
            local def = type(items[id]) == "table" and items[id] or {}
            rows[i] = {
                id = id, at = i,
                rank = by == "kind" and (RANK[B.kindOf(data, id, gen2)] or RANK.OTHER) or 0,
                index = tonumber(def.index) or math.huge,
                name = tostring(def.name or id),
            }
        end
        table.sort(rows, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            if by == "name" and a.name ~= b.name then return a.name < b.name end
            if a.index ~= b.index then return a.index < b.index end
            if by ~= "name" and a.name ~= b.name then return a.name < b.name end
            return a.at < b.at
        end)
        local out = {}
        for i, r in ipairs(rows) do out[i] = r.id end
        return out
    end

    return B
end
