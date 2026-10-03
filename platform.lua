-- The one place that knows which generation is running and where each one
-- keeps things. Gen 1 (Red / Blue / Yellow) runs src/core/Game.lua with the
-- overworld as a stack state; Gen 2 (Gold / Silver) runs src/core/Game2.lua
-- with game.world beside the stack, a split save (player.money,
-- pokedex.caught, named boxes) and Gen2-prefixed screen ids. Gen 3
-- (FireRed / LeafGreen) runs src/core/Game3.lua: its live state is
-- game.session (party, bag pockets, storage, dex) and the world is reached
-- through mod.world only. Every other module asks here instead of reading
-- those fields itself.
return function(mod)
    local P = {}

    local generation = 1
    do
        local ok, GameVersion = pcall(require, "src.core.GameVersion")
        if ok and GameVersion.generation then
            local okGen, gen = pcall(GameVersion.generation)
            if okGen and gen then generation = gen end
        end
    end

    -- a save says so itself; the boot's generation covers the moments before one exists
    function P.gen(game)
        local save = game and game.save
        return (save and tonumber(save.generation)) or generation
    end

    function P.isGen2(game)
        return P.gen(game) == 2
    end

    -- FireRed / LeafGreen (src/core/Game3.lua): the live state is
    -- game.session; game.save there is only the copy the last save wrote
    function P.isGen3(game)
        return P.gen(game) == 3
    end

    -- Gen 3 comes in two layouts on the same engine: FireRed / LeafGreen
    -- ("frlg") and Emerald ("rse", GameVersion's layout). Most game3 code is
    -- shared; the menus' art, the region map and a few labels differ.
    local layout = nil
    do
        local ok, GameVersion = pcall(require, "src.core.GameVersion")
        if ok and GameVersion.layout then
            local okL, l = pcall(GameVersion.layout)
            if okL then layout = l end
        end
    end
    function P.isRse(game)
        return P.isGen3(game) and layout == "rse"
    end
    -- "frlg" / "rse" on Gen 3, false before it
    function P.variant(game)
        if not P.isGen3(game) then return false end
        return layout == "rse" and "rse" or "frlg"
    end

    -- the save as it stands right now, whichever generation runs
    function P.save(game)
        if not game then return nil end
        if P.isGen3(game) then
            if game.session then return game.session end
            -- mods have no package table: require hands over the engine's module
            local ok, s = pcall(function()
                local rt = require("src.core.game3.runtime")
                return rt and rt.getSession and rt.getSession()
            end)
            return ok and s or nil
        end
        return game.save
    end

    ---- text ---------------------------------------------------------------

    -- The engine's own words as the player sees them: a language mod
    -- translates them through the Strings catalog (mod.content.strings),
    -- keyed by the English source, so looking the same source up here
    -- follows it. Untranslated words come back unchanged.
    local okS, Strings = pcall(require, "src.core.Strings")
    function P.text(source)
        if not (okS and Strings and Strings.lookup) then return source end
        local ok, out = pcall(Strings.lookup, source)
        return ok and type(out) == "string" and out or source
    end

    -- a format string filled in, the way the engine's Strings(source, ...)
    -- does it (a translation with the wrong directives falls back to English)
    function P.format(source, ...)
        if okS and Strings and Strings.get then
            local ok, out = pcall(Strings.get, source, ...)
            if ok and type(out) == "string" then return out end
        end
        local ok, out = pcall(string.format, source, ...)
        return ok and out or source
    end

    -- MORN / DAY / NITE as the POKéGEAR's clock prints them (Clock.daytimeLabel);
    -- the English word stays the key everywhere else
    function P.daytimeLabel(key)
        if key == "DARK" then key = "NITE" end
        return P.text(key)
    end

    -- key -> printed word, for the page
    function P.daytimeLabels()
        return { MORN = P.daytimeLabel("MORN"), DAY = P.daytimeLabel("DAY"), NITE = P.daytimeLabel("NITE") }
    end

    ---- world --------------------------------------------------------------

    -- Gen 1's OverworldState (a stack state) or Gen 2's World (game.world)
    function P.world(game)
        if not game then return nil end
        -- Gen 3 has no world object of its own shape: mod.world answers
        if P.isGen3(game) then return nil end
        if P.isGen2(game) then
            local w = game.world
            return w and w.map and w or nil
        end
        return game.overworld
    end

    function P.mapId(game)
        if P.isGen3(game) then
            -- the map module's current map first: mod.world:mapOverview and
            -- current() name the map by it (src/world/game3/WorldAPI.lua)
            local okM, M = pcall(require, "src.core.game3.map")
            if okM and type(M) == "table" and M.current then return M.current end
            local s = P.save(game)
            return s and s.map or nil
        end
        local w = P.world(game)
        return w and w.map and w.map.id or nil
    end

    -- Only the overworld is on screen: no menu, text or battle above it.
    -- Walking does not count: a request made mid-step waits for the step
    -- to end (actions' runOrQueue). Gen 1 checks the stack top; Gold's world
    -- is not a stack state, so its stack must be empty and the world itself
    -- idle (World:busy: text, scripts, field-move animations).
    function P.worldFree(game)
        local w = P.world(game)
        if not w then return false end
        if P.isGen2(game) then
            local states = game.stack and game.stack.states or {}
            if #states > 0 or w.battleActive then return false end
            if w.busy then
                local ok, busy = pcall(w.busy, w)
                if not ok or busy then return false end
            end
            return true
        end
        local stack = game.stack
        return stack and stack.top and stack:top() == w or false
    end

    ---- save ---------------------------------------------------------------

    function P.money(save)
        if not save then return 0 end
        return save.money or (save.player and save.player.money) or 0
    end

    -- species -> true for caught ones (Gen 1 "owned", Gen 2 "caught"; Gen 3
    -- keeps session.dex, keyed by internal species number)
    function P.ownedSet(save)
        local dex = save and (save.pokedex or save.dex) or {}
        return dex.owned or dex.caught or {}
    end

    function P.seenSet(save)
        local dex = save and (save.pokedex or save.dex) or {}
        return dex.seen or {}
    end

    -- The gym badges, in gym order: { { name, has } ... }, read the way each
    -- game keeps them. Gen 1: inventory keys (src/inventory/Badges.lua, the
    -- badge set from the game's data); Gen 2: the player's Johto and Kanto
    -- badge tables; Gen 3: the badge flags of the version running
    -- (scripting/flags.lua forVersion(...).BADGES), read from the live
    -- script store. Read only.
    local function prettyBadge(name)
        name = tostring(name or ""):upper():gsub("_", " ")
        if not name:find("BADGE") then name = name .. " BADGE" end
        return (name:gsub("(%S)BADGE$", "%1 BADGE"))
    end
    function P.badges(game)
        local out = {}
        if P.isGen3(game) then
            local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
            local okV, GameVersion = pcall(require, "src.core.GameVersion")
            local okS, Space = pcall(require, "src.core.game3.scripting.space")
            if not (okF and okV) then return out end
            local okT, vt = pcall(Flags.forVersion, GameVersion.current)
            local list = okT and type(vt) == "table" and vt.BADGES or Flags.BADGES or {}
            local store = okS and Space.store or P.save(game)
            for _, b in ipairs(list) do
                local has = false
                for _, id in ipairs({ b.flag, b.name and ("FLAG_BADGE0" .. tostring(b.num) .. "_GET") }) do
                    if id ~= nil and not has then
                        local ok, v = pcall(Flags.getFlag, store, nil, id)
                        has = ok and v == true
                    end
                end
                out[#out + 1] = { name = prettyBadge(b.name), has = has, index = #out + 1 }
            end
            return out
        end
        local save = game and game.save
        if not save then return out end
        if P.isGen2(game) then
            -- the cart's own order, Johto then Kanto (src/battle/gen2/Battle.lua
            -- BADGE_TYPE_BOOSTS: each badge's name and which table holds it)
            local p = save.player or {}
            local okB, Battle = pcall(require, "src.battle.gen2.Battle")
            -- the Kanto eight only once Kanto is open: the same test as the
            -- POKeDEX AREA page's (the INDIGO PLATEAU fly point visited, or a
            -- HALL OF FAME record), or a Kanto badge already earned
            local kanto = false
            for _, has in pairs(p.kantoBadges or {}) do if has then kanto = true end end
            if not kanto then
                local okF, FieldMoves = pcall(require, "src.world.gen2.FieldMoves")
                if okF and FieldMoves.hasVisitedSpawn then
                    local ok, visited = pcall(FieldMoves.hasVisitedSpawn, save, "SPAWN_INDIGO")
                    kanto = ok and visited or false
                end
            end
            if not kanto then
                local hof = save.hallOfFame
                kanto = type(hof) == "table" and ((tonumber(hof.count) or 0) > 0 or hof.entered == true) or false
            end
            for i, b in ipairs(okB and Battle.BADGE_TYPE_BOOSTS or {}) do
                if b.store ~= "kantoBadges" or kanto then
                    local set = p[b.store] or {}
                    -- index: the badge's place in the full sixteen (its picture)
                    out[#out + 1] = { name = prettyBadge(b.badge), has = set[b.badge] and true or false, index = i }
                end
            end
            return out
        end
        local okB, Badges = pcall(require, "src.inventory.Badges")
        if not okB then return out end
        local inventory = save.inventory or {}
        for _, entry in ipairs(Badges.list(game.data)) do
            out[#out + 1] = { name = prettyBadge(entry.name or entry.id),
                has = inventory[Badges.itemFor(entry)] and true or false, index = #out + 1 }
        end
        return out
    end

    -- Whether the ELITE FOUR has been beaten: Gen 1 / 2 keep a HALL OF FAME
    -- record once the CHAMPION is beaten (save.hallOfFame: Gen 1 a list,
    -- Gen 2 a count); Gen 3 sets FLAG_SYS_GAME_CLEAR. Read only.
    function P.champion(game)
        if P.isGen3(game) then
            local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
            local okV, GameVersion = pcall(require, "src.core.GameVersion")
            local okS, Space = pcall(require, "src.core.game3.scripting.space")
            if not (okF and okV) then return false end
            local okT, vt = pcall(Flags.forVersion, GameVersion.current)
            local id = okT and type(vt) == "table" and vt.IDS and vt.IDS.FLAG_SYS_GAME_CLEAR
            local store = okS and Space.store or P.save(game)
            local ok, v = pcall(Flags.getFlag, store, nil, id or "FLAG_SYS_GAME_CLEAR")
            return ok and v == true
        end
        local hof = game and game.save and game.save.hallOfFame
        if type(hof) ~= "table" then return false end
        return (tonumber(hof.count) or #hof) > 0
    end

    ---- boxes --------------------------------------------------------------

    -- Gen 3's storage module: 14 boxes of 30 slots, each box
    -- { name, mons = { [slot] = mon } } with holes (src/core/game3/storage.lua)
    local Storage3
    if P.isGen3() then
        local ok, m = pcall(require, "src.core.game3.storage")
        Storage3 = ok and m or {}
    end

    local Boxes
    if Storage3 then
        Boxes = {}
    else
        local ok, mod2 = pcall(require, P.isGen2() and "src.core.gen2.Boxes" or "src.pokemon.Boxes")
        Boxes = ok and mod2 or {}
    end
    if Storage3 then
        P.BOX_COUNT = Storage3.TOTAL_BOXES_COUNT or 14
        P.BOX_CAPACITY = Storage3.IN_BOX_COUNT or 30
    else
        P.BOX_COUNT = Boxes.COUNT or Boxes.NUM_BOXES or (P.isGen2() and 14 or 12)
        P.BOX_CAPACITY = Boxes.CAPACITY or Boxes.MONS_PER_BOX or 20
    end

    -- the list of boxes (each a list of mons), without writing to the save.
    -- Gen 3's boxes keep empty slots as holes; they come back packed, each
    -- mon tagged with its slot in the list's `slots`
    function P.boxes(save)
        if not save then return {} end
        if Storage3 then
            local out = {}
            local st = save.storage
            for b, box in ipairs(st and st.boxes or {}) do
                local list, slots = {}, {}
                for s = 1, P.BOX_CAPACITY do
                    local mon = box.mons and box.mons[s]
                    if mon then
                        list[#list + 1] = mon
                        slots[#list] = s
                    end
                end
                list.slots = slots
                out[b] = list
            end
            return out
        end
        return save.boxes or { save.box }
    end

    -- the box the PC opens on (1-based)
    function P.currentBox(save)
        if Storage3 then
            return save and save.storage and tonumber(save.storage.currentBox) or 1
        end
        return save and save.currentBox or 1
    end

    -- the same, created where missing, for edits
    function P.editableBoxes(save)
        if P.isGen2() then
            save.boxes = save.boxes or {}
            for b = 1, P.BOX_COUNT do
                if Boxes.box then
                    pcall(Boxes.box, save, b)
                else
                    save.boxes[b] = save.boxes[b] or {}
                end
            end
            return save.boxes
        end
        if Boxes.ensure then Boxes.ensure(save) end
        return save.boxes
    end

    -- Gen 3: the wallpaper the player chose for box b (storage.lua, 1-based);
    -- nil elsewhere (the Game Boy PCs have none)
    function P.boxWallpaper(save, b)
        if not Storage3 then return nil end
        local box = save and save.storage and save.storage.boxes and save.storage.boxes[b]
        return box and tonumber(box.wallpaper) or nil
    end

    function P.boxName(save, b)
        if Storage3 then
            local box = save and save.storage and save.storage.boxes and save.storage.boxes[b]
            local name = box and box.name
            if type(name) == "string" and name ~= "" then return name end
            return "BOX " .. b
        end
        if Boxes.name then
            local ok, name = pcall(Boxes.name, save, b)
            if ok and type(name) == "string" and name ~= "" then return name end
        end
        local names = save and save.boxNames
        local name = names and names[b]
        if type(name) == "string" and name ~= "" then return name end
        return "BOX " .. b
    end

    ---- screens ------------------------------------------------------------

    -- Screens that list the bag / item PC / boxes while open (both games'
    -- registry ids: Gen 2 prefixes its own with "Gen2").
    local STORAGE_SCREENS = {
        BagMenu = true, BoxMenu = true, PlayerPC = true, ShopMenu = true,
        Gen2PackMenu = true, Gen2PcMenu = true, Gen2BoxMenu = true, Gen2ItemPcMenu = true,
        Gen2CenterPcMenu = true, Gen2MartMenu = true, Gen2HeldItemMenu = true,
        Gen2DayCareMenu = true, Gen2MailboxMenu = true
    }
    local TRADE_SCREENS = { TradeAnim = true, Gen2TradeAnim = true, Gen2TradeMenu = true }

    local LinkState
    do
        local ok, m = pcall(require, "src.link.LinkState")
        if ok and type(m) == "table" then LinkState = m end
    end

    function P.isStorageScreen(state)
        return type(state) == "table" and STORAGE_SCREENS[state.screenId] == true
    end

    -- A trade screen (Gen 2 has no Cable Club, only NPC trades through
    -- Gen2TradeMenu / Gen2TradeAnim), or Gen 1's Cable Club session
    -- (LinkState stays on the stack for the whole link, pushed directly, so
    -- matched by class).
    function P.isTrading(state)
        if type(state) ~= "table" then return false end
        if TRADE_SCREENS[state.screenId] then return true end
        return LinkState ~= nil and getmetatable(state) == LinkState
    end

    return P
end
