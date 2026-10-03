-- second_screen_companion: serves a live party overview page over the LAN so
-- a phone on the same Wi-Fi can follow along in its browser. The server is
-- pumped from core.update with non-blocking sockets (see server.lua).
return function(mod)

    -- SKIN: STANDARD plus every `@skin <id> "<NAME>"` line in web/skins.css,
    -- so adding a skin there is all it takes (read once, at start-up)
    local function skinChoices()
        local choices = { { "STANDARD", "standard" } }
        local css = mod:read("web/skins.css") or ""
        for id, name in css:gmatch('@skin%s+([%w%-]+)%s+"([^"]+)"') do
            choices[#choices + 1] = { name, id }
        end
        return choices
    end

    mod.options:define({{
        key = "enabled",
        type = "toggle",
        label = "PHONE SERVER",
        default = true
    }, {
        key = "port",
        type = "choice",
        label = "PORT",
        default = 8080,
        choices = {{"8080", 8080}, {"8081", 8081}, {"8888", 8888}, {"3000", 3000}}
    }, {
        key = "show_url",
        type = "choice",
        label = "SHOW URL",
        default = "start",
        choices = {{"AT START", "start"}, {"ALWAYS", "always"}, {"OFF", "off"}}
    }, {
        -- rearranging needs the PIN / QR code from OPTION > PHONE
        key = "secure",
        type = "toggle",
        label = "SECURE MODE",
        default = false
    }, {
        -- LIVE tab: reveal a trainer's whole team and unseen DexNav species
        key = "spoilers",
        type = "toggle",
        label = "SPOILERS",
        default = false
    }, {
        -- the phone buzzes with a cry and rings with an incoming call
        key = "vibration",
        type = "toggle",
        label = "VIBRATION",
        default = false
    }, {
        -- POKéMON DETAILS: DVs, Stat Exp, HIDDEN POWER's type and more
        key = "show_hidden",
        type = "toggle",
        label = "SHOW HIDDEN VALUES",
        default = false
    }, {
        -- POKéMON party <-> PC boxes, items BAG <-> item PC (transfer.lua)
        key = "pc_transfer",
        type = "toggle",
        label = "PC TRANSFERS",
        default = false
    }, {
        -- a dashboard for a screen nobody touches (a TV): party, maps,
        -- DexNav, battles and notifications at once, no tabs or buttons.
        -- A device can override it with ?handsoff=1 / ?handsoff=0
        key = "hands_off",
        type = "toggle",
        label = "HANDS-OFF MODE",
        default = false
    }, {
        -- the page's look: a skin from web/skins.css
        key = "skin",
        type = "choice",
        label = "SKIN",
        default = "standard",
        choices = skinChoices()
    }})

    local function loadFactory(filename)
        local source, readErr = mod:read(filename)
        if not source then
            mod.log:error("%s is missing (%s)", filename, tostring(readErr))
            return nil
        end

        local chunk, compileErr = load(source, "@" .. mod.path .. "/" .. filename)
        if not chunk then
            mod.log:error("%s did not compile: %s", filename, tostring(compileErr))
            return nil
        end

        local ok, factory = pcall(chunk)
        if not ok or type(factory) ~= "function" then
            mod.log:error("%s must return a factory function: %s", filename, tostring(factory))
            return nil
        end
        return factory
    end

    local function runModule(filename, ...)
        local factory = loadFactory(filename)
        if not factory then return nil end
        local ok, result = pcall(factory, ...)
        if not ok then
            mod.log:error("%s failed to load: %s", filename, tostring(result))
            return nil
        end
        return result
    end

    local okSocket, socket = pcall(require, "socket")
    if not okSocket then
        mod.log:error("luasocket is unavailable: %s", tostring(socket))
        return
    end
    local Json = require("src.link.Json")
    local Server = runModule("server.lua", mod, socket)
    -- which generation runs, and where it keeps things (Gen 1 / 2 / 3)
    local platform = runModule("platform.lua", mod)
    -- Gen 3 (FireRed / LeafGreen) has modules of its own (the *3.lua files):
    -- its engine shares no data shapes with the Game Boy games. It is
    -- read-only for now: nothing on the phone changes the game there.
    local gen3 = platform and platform.isGen3() or false
    -- sprites are a nice-to-have: without them the page still shows the party
    local sprites = platform and runModule(gen3 and "sprites3.lua" or "sprites.lua", mod, platform)
    local uids = runModule("uids.lua")
    local snapshot3 = gen3 and uids and platform and runModule("snapshot3.lua", mod, sprites, uids, platform)
    local snapshot = snapshot3 and snapshot3.snapshot
        or (not gen3 and uids and platform and runModule("snapshot.lua", mod, sprites, uids, platform))
    -- the ITEM / PACK tab's SORT orders (pure; edits.lua writes them)
    local bagsort = not gen3 and runModule("bagsort.lua")
    -- Gen 3's edits (SWITCH, BAG swaps / SORT, box moves) have their own
    -- file: FireRed's bag pockets and 30-slot boxes are shaped differently
    local edits = uids and platform and (gen3 and runModule("edits3.lua", mod, uids, platform)
        or runModule("edits.lua", mod, uids, platform, bagsort))
    -- PC TRANSFERS: party <-> boxes, BAG <-> item PC, behind the option
    local transfer = edits and (gen3 and runModule("transfer3.lua", mod, uids, platform, edits, sprites)
        or runModule("transfer.lua", mod, uids, platform, edits))
    -- the LIVE tab is optional too: without it the other tabs still work
    local function byGen(gen1File, gen2File, gen3File)
        if gen3 then return gen3File end
        return platform.isGen2() and gen2File or gen1File
    end
    local live = platform and runModule(byGen("live.lua", "live2.lua", "live3.lua"), mod, sprites, platform)
    -- quick actions (BICYCLE, rods, field moves); Gen 3's share the edits'
    -- free-roam gate
    local actions = platform and runModule(byGen("actions.lua", "actions2.lua", "actions3.lua"), mod, platform, edits)
    local dex = platform and runModule(byGen("dex.lua", "dex.lua", "dex3.lua"), mod, sprites, Json, platform)
    local area = live and runModule(byGen("area.lua", "area2.lua", "area3.lua"), mod, sprites, live, platform, dex)
    local minimap = live and runModule("minimap.lua", mod, sprites, live, platform, Json)
    -- cries are rendered from Game Boy chip data; Gen 3's are PCM samples
    -- (cry3.lua: the game's own sample mixer)
    local cry = platform and (gen3 and runModule("cry3.lua", mod, platform, dex)
        or runModule("cry.lua", mod, platform))
    -- Gen 2's POKéGEAR tab: clock, phone calls and the radio
    local gear = platform and platform.isGen2() and runModule("gear.lua", mod, platform, live)
    -- HANDS-OFF mode's notifications (what changed between updates)
    local notify = platform and runModule("notify.lua", mod, platform, sprites)
    -- Emerald's POKeNAV tab (Match Call, berry trees), in GEAR's slot
    local pokenav = platform and platform.isRse() and runModule("pokenav3.lua", mod, platform, live, sprites)
    local page = mod:read("web/index.html")
    -- the look: shared styles plus the standard theme, the same on every
    -- game (the SKIN option's looks, skins.css, work on every game too).
    -- Read on each request (like skins.css), so style edits show on a page
    -- reload.
    local function themeCss()
        return mod:read("web/standard.css") or ""
    end
    if not (Server and snapshot and edits and page) then
        mod.log:error("companion disabled: a module failed to load")
        return
    end

    local URL_SECONDS = 12
    local RETRY_SECONDS = 3

    local game
    local server
    local url
    -- when the startup message was first drawn (nil: not yet). Counted from
    -- the first frame it's on screen, not from the bind: a game's first,
    -- loading-heavy frames can bring one dt that would use it all up unseen.
    local urlShownAt
    local retryTimer = 0
    local lastBindError

    -- The address the OS would route LAN traffic from. A UDP "connect" only
    -- picks the interface; no packet is sent.
    local function lanAddress()
        local udp = socket.udp()
        if not udp then return "localhost" end
        udp:setpeername("8.8.8.8", 80)
        local ip = udp:getsockname()
        udp:close()
        if not ip or ip == "0.0.0.0" then return "localhost" end
        return ip
    end

    -- SECURE MODE: editing needs this per-session key. A device gets it by
    -- scanning the in-game QR code (the key is in the URL) or by entering the
    -- 4-digit PIN shown next to it (OPTION > PHONE). With SECURE MODE off,
    -- any device that can open the page may edit.
    local key = love.data.encode("string", "hex", love.data.hash("sha256", table.concat({
        tostring(os.time()), tostring(os.clock()), tostring(love.timer.getTime()),
        tostring({}), tostring(love.math.random()), tostring(love.math.random())
    }, "|"))):sub(1, 24)

    local PIN_TRIES = 5          -- wrong PINs before a new PIN is drawn
    local PIN_LOCK_SECONDS = 30  -- and no guesses are taken for this long
    local pin, pinMisses, pinLockedUntil = nil, 0, 0

    local function newPin()
        pin = ("%04d"):format(love.math.random(0, 9999))
        pinMisses = 0
    end
    newPin()

    local function secure()
        return mod.options:get("secure") and true or false
    end

    local function keyOk(req)
        return req.headers and req.headers["x-companion-key"] == key
    end

    local function authorized(req)
        return not secure() or keyOk(req)
    end

    -- A page on another site can make the browser send simple requests to
    -- this LAN server; a custom header cannot be added without a CORS
    -- preflight this server never approves, so requiring it stops that.
    local function sameOrigin(req)
        return req.headers and req.headers["x-companion"] == "1"
    end

    -- DNS rebinding: a hostile domain re-pointed at this PC shows up with its
    -- own name in Host. Accept IP literals, localhost, bare machine names and
    -- local-network suffixes only.
    local LOCAL_SUFFIXES = { ".local", ".lan", ".home", ".home.arpa", ".internal" }
    local function hostAllowed(req)
        local host = (req.headers and req.headers["host"] or ""):lower()
        host = host:gsub(":%d+$", "")
        if host == "" or host == "localhost" or host:match("^%[.*%]$") then return true end
        if host:match("^%d+%.%d+%.%d+%.%d+$") or not host:find(".", 1, true) then return true end
        for _, suffix in ipairs(LOCAL_SUFFIXES) do
            if host:sub(-#suffix) == suffix then return true end
        end
        return false
    end

    -- The PC, sent only when it changed: /state carries a version stamp and
    -- the page fetches /pc when it moves (like the POKéDEX). Building every
    -- box's rows each second was most of a poll's work and size, so a cheap
    -- fingerprint of the boxes (who sits where, level, item, name, egg; box
    -- names, the current box, the icons' look) decides when to rebuild.
    -- dirty: a command from the phone may have changed the boxes; checkedAt:
    -- when the signature was last walked (every box's every POKéMON)
    local pcCache = { sig = nil, version = nil, body = nil, dirty = true, checkedAt = nil }
    local PC_CHECK_SECONDS = 2
    local pcSession = ("%x"):format(os.time() % 0x1000000)
    local pcCounter = 0

    local function pcSignature(save)
        local parts = { tostring(platform.currentBox(save)) }
        if sprites and sprites.iconLook and game and game.data then
            local ok, look = pcall(sprites.iconLook, game.data)
            if ok then parts[#parts + 1] = tostring(look) end
        end
        for b, box in pairs(platform.boxes(save)) do
            parts[#parts + 1] = "|" .. b .. ":" .. tostring(platform.boxName(save, b))
                .. ":" .. tostring(platform.boxWallpaper and platform.boxWallpaper(save, b))
            local slots = box.slots
            for i, mon in ipairs(box) do
                parts[#parts + 1] = table.concat({ uids.of(mon), slots and slots[i] or i, tostring(mon.level),
                    tostring(mon.item or mon.heldItem), tostring(mon.species), tostring(mon.nickname),
                    tostring(mon.isEgg or mon.egg) }, ",")
            end
        end
        return table.concat(parts, ";")
    end

    local function pcSummary()
        local save = platform.save(game)
        if not save then return nil end
        -- the boxes change slowly from in the game (the PC is open for that):
        -- walked at most every 2 s, and at once after the phone's own change
        local now = love.timer.getTime()
        if pcCache.body and pcCache.save == save and not pcCache.dirty and pcCache.checkedAt
            and now - pcCache.checkedAt < PC_CHECK_SECONDS then
            return { version = pcCache.version }
        end
        pcCache.checkedAt, pcCache.dirty, pcCache.save = now, false, save
        local okS, sig = pcall(pcSignature, save)
        if not okS then
            mod.log:warn("pc signature failed: %s", tostring(sig))
            sig = nil
        end
        if sig == nil or sig ~= pcCache.sig or not pcCache.body then
            local ok, result = pcall(snapshot, game, { pcOnly = true })
            if not ok then
                mod.log:warn("pc failed: %s", tostring(result))
                return nil
            end
            local body = Json.encode(result.pc)
            if body ~= pcCache.body then
                pcCounter = pcCounter + 1
                pcCache.version = pcSession .. "-" .. pcCounter
                pcCache.body = body
            end
            pcCache.sig = sig
        end
        return { version = pcCache.version }
    end

    ---- /state ----------------------------------------------------------------
    -- Everything that doesn't depend on the asking device is built once per
    -- SHARED_SECONDS and kept as JSON: a phone and a TV polling each second
    -- cost one build, not two. A command clears it (the phone sees its own
    -- edit at once). What depends on the device's key (may it edit) is added
    -- to the end per request.
    local SHARED_SECONDS = 0.5
    local shared = { json = nil, ctx = nil, at = -1 }
    local function invalidateShared()
        shared.json = nil
        pcCache.dirty = true
    end

    local function clock() return love.timer.getTime() end

    -- Answers that don't change while the same save is loaded: what each
    -- item is used for (useKind / fieldKind), the status labels; the ABLE
    -- marks while the party is the same. Cleared when another save loads.
    local memo = { save = false }
    local function memoFor()
        local save = platform.save(game)
        if memo.save ~= save then memo = { save = save, use = {}, able = {}, ableKey = nil, icons = nil } end
        return memo
    end
    local function partyKey(party)
        local parts = {}
        for _, m in ipairs(party or {}) do
            local moves = {}
            for i, mv in ipairs(m.moves or {}) do moves[i] = tostring(mv.name) end
            parts[#parts + 1] = table.concat({ tostring(m.uid), tostring(m.species), tostring(m.level),
                table.concat(moves, "+") }, ":")
        end
        return table.concat(parts, ";")
    end

    local function buildShared(daytime)
        local ctx = {}
        local state = snapshot(game, { hidden = mod.options:get("show_hidden") and true or false, noPc = true })
        state.pc = pcSummary()
        state.secure = secure()
        state.vibration = mod.options:get("vibration") ~= false
        state.skin = mod.options:get("skin") or "standard"
        -- the dex pages' cache depends on it (SHOW HIDDEN VALUES)
        state.showHidden = mod.options:get("show_hidden") and true or false
        -- the game's own words the page prints, as a language mod has them
        -- (the POKéDEX's SEEN / OWN, the BAG's MONEY, the TOWN MAP's AREA UNKNOWN)
        state.words = {
            SEEN = platform.text("SEEN"), OWN = platform.text("OWN"),
            MONEY = platform.text("MONEY"), AREA_UNKNOWN = platform.text("AREA UNKNOWN"),
            -- the items tab's name, as each start menu has it: Gen 1's ITEM,
            -- Gold's PACK, FireRed's BAG
            BAG = platform.text(byGen("ITEM", "PACK", "BAG"))
        }
        -- Gen 3: the PLAYER's PC items are listed (read-only; PC TRANSFERS
        -- are not on Gen 3 yet)
        if snapshot3 then
            state.pcItemsShown = true
            local okI, pcItems = pcall(snapshot3.pcItems, game)
            state.pcItems = okI and pcItems or nil
        end
        local canEdit, why = edits.editable(game)
        ctx.canEdit = canEdit and true or false
        -- why editing is paused, for the page's hint: "busy" / "not loaded"
        state.editBlock = not canEdit and why or false
        -- the party's own rule (free roam, 2+ mons): SWITCH on the POKéMON tab
        local okParty, partyOk, partyWhy = pcall(edits.partyEditable, game)
        ctx.partyOk = okParty and partyOk and true or false
        state.partyBlock = okParty and not partyOk and partyWhy or false
        -- PC TRANSFERS: whether the page may offer them, and the item PC
        if transfer and transfer.enabled() then
            ctx.transfers = true
            local okI, pcItems = pcall(transfer.pcItems, game)
            state.pcItems = okI and pcItems or {}
        end
        if actions then
            local ok, bike = pcall(actions.bikeState, game)
            state.bike = ok and bike or false
            local okRods, rods = pcall(actions.rods, game)
            state.rods = okRods and rods or {}
            local okMoves, moves = pcall(actions.fieldMoves, game)
            state.fieldMoves = okMoves and moves or {}
            if not okMoves then mod.log:warn("field moves failed: %s", tostring(moves)) end
        end
        if live then
            -- ?daytime=MORN|DAY|NITE: the DexNav previews another time of day (Gen 2)
            -- hidden: the battle's catch odds (SHOW HIDDEN VALUES)
            local ok, result = pcall(live.state, game, mod.options:get("spoilers"),
                { daytime = daytime, hidden = mod.options:get("show_hidden") and true or false })
            if ok then
                state.live = result
            else
                mod.log:warn("live state failed: %s", tostring(result))
            end
        end
        if minimap then
            -- LOCATION's map: a version stamp and the player's position
            local ok, result = pcall(minimap.summary, game, mod.options:get("spoilers"))
            if ok then state.minimap = result else mod.log:warn("minimap failed: %s", tostring(result)) end
        end
        if pokenav then
            local ok, result = pcall(pokenav.state, game)
            if ok then state.pokenav = result else mod.log:warn("pokenav state failed: %s", tostring(result)) end
        end
        if gear then
            local ok, result = pcall(gear.state, game)
            if ok then state.gear = result else mod.log:warn("gear state failed: %s", tostring(result)) end
        end
        if dex then
            local ok, result = pcall(dex.state, game, mod.options:get("spoilers"))
            if ok then
                state.pokedex = result
            else
                mod.log:warn("pokedex failed: %s", tostring(result))
            end
        end
        -- HANDS-OFF: the option, the badges for its header, and the news
        state.handsOff = mod.options:get("hands_off") and true or false
        if platform and platform.badges then
            local okB, badges = pcall(platform.badges, game)
            state.badges = okB and badges or {}
            -- each with the game's own picture where it has one
            for _, b in ipairs(state.badges) do
                if sprites and sprites.badge and b.index then
                    local okI, id
                    if gen3 then okI, id = pcall(sprites.badge, b.index)
                    else okI, id = pcall(sprites.badge, game and game.data, b.index) end
                    b.icon = okI and id and ("/img/" .. id .. ".png") or false
                end
            end
            local okC, champ = pcall(platform.champion, game)
            state.champion = okC and champ or false
        end
        if notify then
            -- (reads state.badges / state.champion as built above)
            local ok, err = pcall(notify.update, game, state)
            if not ok then mod.log:warn("notices failed: %s", tostring(err)) end
            state.notices = notify.state()
        end
        -- the BAG's items: what USE does with each ("mon", "move", "scene",
        -- "field"), and for a TM or stone ABLE / LEARNED / NOT ABLE per
        -- POKéMON. Fixed per item (kept for the save); the marks kept while
        -- the party stays the same.
        local m = memoFor()
        if edits and edits.useKind and state.bag and state.bag.items then
            local pk = partyKey(state.party)
            if m.ableKey ~= pk then m.able, m.ableKey = {}, pk end
            for _, it in ipairs(state.bag.items) do
                local kind = m.use[it.id]
                if kind == nil then
                    local okK, k = pcall(edits.useKind, game, it.id)
                    kind = okK and k or nil
                    if not kind and actions and actions.fieldKind then
                        local okF, fk = pcall(actions.fieldKind, game, it.id)
                        kind = okF and fk or nil
                    end
                    m.use[it.id] = kind or false
                end
                if kind then it.use = kind end
                if kind == "scene" and edits.ableFor then
                    local able = m.able[it.id]
                    if able == nil then
                        local okA, a = pcall(edits.ableFor, game, it.id)
                        able = okA and a or false
                        m.able[it.id] = able
                    end
                    if able then it.able = able end
                end
            end
        end
        -- whether the game is in free roam (nothing open over the field):
        -- USE and GIVE wait for it, so the page offers them only then
        local okF, free = pcall(function()
            if gen3 then
                if not (edits and edits.freeRoam) then return false end
                local ok, why2 = edits.freeRoam(game)
                return ok or why2 == "walking"
            end
            return platform.worldFree(game)
        end)
        state.gameFree = okF and free and true or false
        -- Gen 3: the party menu's own status labels (PSN, PAR ... FNT), shown
        -- by the page in place of the text (built once)
        if gen3 and sprites and sprites.statusIcon then
            if not m.icons then
                local icons = {}
                for _, code in ipairs({ "PSN", "PAR", "SLP", "FRZ", "BRN", "PKRS", "FNT" }) do
                    local okI, id = pcall(sprites.statusIcon, code)
                    if okI and id then icons[code] = "/img/" .. id .. ".png" end
                end
                m.icons = icons
            end
            state.statusIcons = m.icons
        end
        local json = Json.encode(state)
        return json, ctx
    end

    -- info: what a command answers besides the new state (state.result)
    local function stateBody(req, info)
        -- ?daytime= (Gen 2's DexNav preview) is that device's own: built for it
        local daytime = (req.query or ""):match("[?&]?daytime=(%u+)")
        local now = clock()
        local json, ctx = shared.json, shared.ctx
        if daytime or not json or now - shared.at >= SHARED_SECONDS then
            json, ctx = buildShared(daytime)
            if not daytime then shared.json, shared.ctx, shared.at = json, ctx, now end
        end
        -- this device's own: may it edit (SECURE MODE's key)
        local auth = authorized(req) and true or false
        local mine = {
            keyValid = keyOk(req) and true or false,
            editable = auth and ctx.canEdit or false,
            partyEditable = auth and ctx.partyOk or false,
        }
        if ctx.transfers then mine.transfers = mine.editable end
        if type(info) == "table" then mine.result = info end
        -- the shared object with these added at its end (an object always:
        -- the encoder writes an empty table as [], which can't take them)
        if json:sub(1, 1) ~= "{" or json:sub(-1) ~= "}" then return Json.encode(mine) end
        return json:sub(1, -2) .. "," .. Json.encode(mine):sub(2)
    end

    local ERRORS = {
        busy = "Close the BAG, PC or shop in the game first.",
        ["not loaded"] = "Load your save in the game first.",
        trading = "A trade is in progress in the game. Try again when it's done.",
        ["no bike"] = "There's no BICYCLE in the BAG.",
        ["bike busy"] = "Close the menu, text or battle in the game first.",
        ["bike surf"] = "You can't ride the BICYCLE while surfing.",
        ["bike forced"] = "You can't get off the BICYCLE on CYCLING ROAD.",
        ["bike here"] = "No cycling allowed here.",
        unavailable = "The game can't do that right now.",
        ["no rod"] = "That rod isn't in the BAG.",
        ["no item"] = "That item isn't in the PACK.",
        ["rod busy"] = "Close the menu, text or battle in the game first.",
        ["rod unavailable"] = "Face the water to fish (not while surfing).",
        ["field unknown"] = "No POKéMON in the party can use that.",
        ["field busy"] = "Close the menu, text or battle in the game first.",
        ["field unavailable"] = "That can't be used right here.",
        ["fly dest"] = "You can't FLY there.",
        ["soft target"] = "That POKéMON can't be healed with SOFTBOILED right now.",
        ["other pocket"] = "Items can only swap places within one pocket.",
        ["fixed pocket"] = "The TM/HM pocket is always sorted by number.",
        ["party busy"] = "Close the menu, text or battle in the game first.",
        ["one mon"] = "There's only one POKéMON in the party.",
        ["no card"] = "The POKéGEAR doesn't have that card yet.",
        ["no station"] = "That station isn't on the air here.",
        stale = "That changed in the game. Try again.",
        full = "The BOX is full.",
        disabled = "Turn on PC TRANSFERS in the mod's options first.",
        ["last mon"] = "You can't deposit the last POKéMON!",
        mail = "Remove MAIL first.",
        asleep = "There isn't any response... (PIKACHU is asleep)",
        ["party full"] = "The party is full.",
        ["bag full"] = "You can't carry any more items.",
        ["pc full"] = "No room left to store items.",
        egg = "An EGG can't hold an item.",
        ["cant hold"] = "This item can't be held.",
        ["cant use"] = "That item can't be used on a POKéMON from here.",
        ["egg use"] = "It won't have any effect on an EGG.",
        ["no effect"] = "It won't have any effect.",
        ["mail give"] = "MAIL needs a letter: give it in the game.",
        ["bad request"] = "The game didn't understand that request.",
        important = "That's too important to store.",
        ["read-only"] = "Changes from the phone aren't supported in this game yet."
    }

    -- POST /api/<command> with a small JSON body; replies with fresh state
    local COMMANDS = {
        ["/api/bag/swap"] = function(body)
            return edits.bagSwap(game, body.a, body.b)
        end,
        ["/api/bag/sort"] = function(body)
            return edits.bagSort(game, body.by)
        end,
        ["/api/bag/order"] = function(body)
            return edits.bagSetOrder(game, body.order)
        end,
        ["/api/party/swap"] = function(body)
            return edits.partySwap(game, body.a, body.b)
        end,
        ["/api/box/move"] = function(body)
            return edits.boxMove(game, body.mon, body.target, body.box)
        end,
        ["/api/pc/deposit"] = function(body)
            if not transfer then return nil, "unavailable" end
            return transfer.deposit(game, body.mon, body.box)
        end,
        ["/api/pc/swap"] = function(body)
            if not transfer then return nil, "unavailable" end
            return transfer.swap(game, body.mon, body.target)
        end,
        ["/api/pc/withdraw"] = function(body)
            if not transfer then return nil, "unavailable" end
            return transfer.withdraw(game, body.mon)
        end,
        ["/api/items/give"] = function(body)
            return edits.giveItem(game, body.id, body.mon)
        end,
        -- USE on a party POKéMON: medicine, vitamins, PP (the move picked
        -- on the phone where the item asks for one)
        ["/api/items/use"] = function(body)
            -- no POKéMON: a field item (REPEL, ESCAPE ROPE, a rod, the
            -- BICYCLE ...), through the same calls as the quick actions
            if body.mon == nil then
                if not (actions and actions.useItem) then return nil, "unavailable" end
                if type(body.id) ~= "string" then return nil, "bad request" end
                local done, err, info = actions.useItem(game, body.id)
                -- the game's own words, as one line
                local save = platform.save(game)
                local player = save and (save.playerName or (save.player and save.player.name))
                local function line(t)
                    if edits and edits.gameText then return edits.gameText(t, player) end
                    return type(t) == "string" and t or nil
                end
                if not done then
                    if type(err) == "string" and ERRORS[err] then return nil, err end
                    return nil, line(err) or "field unavailable"
                end
                if type(info) == "table" and info.text ~= nil then info.text = line(info.text) end
                return true, nil, info
            end
            if not edits.useItem then return nil, "unavailable" end
            return edits.useItem(game, body.id, body.mon, body.move)
        end,
        ["/api/items/topc"] = function(body)
            if not transfer then return nil, "unavailable" end
            return transfer.itemToPc(game, body.id, body.qty, body.seen)
        end,
        ["/api/items/tobag"] = function(body)
            if not transfer then return nil, "unavailable" end
            return transfer.itemToBag(game, body.id, body.qty, body.seen)
        end,
        ["/api/bike"] = function(body)
            if not actions then return nil, "unavailable" end
            return actions.requestBike(game, body.on)
        end,
        ["/api/fish"] = function(body)
            if not actions then return nil, "unavailable" end
            return actions.requestFish(game, body.rod)
        end,
        ["/api/item"] = function(body)
            if not (actions and actions.requestItem) then return nil, "unavailable" end
            return actions.requestItem(game, body.item)
        end,
        ["/api/field"] = function(body)
            if not actions then return nil, "unavailable" end
            return actions.requestField(game, body)
        end,
        ["/api/gear/call"] = function(body)
            if not gear then return nil, "unavailable" end
            return gear.call(game, body.id)
        end,
        ["/api/gear/answer"] = function(body)
            if not gear then return nil, "unavailable" end
            return gear.answer(game, body.what)
        end,
        ["/api/gear/tune"] = function(body)
            if not gear then return nil, "unavailable" end
            return gear.tune(game, body.knob)
        end,
        ["/api/gear/off"] = function()
            if not gear then return nil, "unavailable" end
            return gear.off(game)
        end
    }

    local function jsonError(status, message)
        return status, "application/json", Json.encode({ error = message })
    end

    -- POST /api/pair { pin }: trade the PIN for the session key
    local function pair(req)
        if not secure() then return 200, "application/json", Json.encode({ ok = true }) end
        local now = love.timer.getTime()
        if now < pinLockedUntil then
            return jsonError(429, "Too many wrong PINs. Wait a moment, then use the new PIN.")
        end
        local ok, body = pcall(Json.decode, req.body, 256)
        local guess = ok and type(body) == "table" and tostring(body.pin or "") or ""
        if guess == pin then
            pinMisses = 0
            return 200, "application/json", Json.encode({ ok = true, key = key })
        end
        pinMisses = pinMisses + 1
        if pinMisses >= PIN_TRIES then
            newPin()
            pinLockedUntil = now + PIN_LOCK_SECONDS
            mod.log:warn("too many wrong PINs; drew a new one")
            return jsonError(403, "Too many wrong PINs. The game shows a new PIN now.")
        end
        return jsonError(403, "Wrong PIN.")
    end

    local function command(req, run)
        if req.method ~= "POST" then return 405, "text/plain", "POST only\n" end
        if not sameOrigin(req) then return jsonError(403, "Request refused.") end
        if run == pair then return pair(req) end
        if not authorized(req) then
            return jsonError(403, "SECURE MODE is on: enter the PIN or scan the QR code from OPTION > PHONE.")
        end
        local ok, body = pcall(Json.decode, req.body, 4096)
        if not ok or type(body) ~= "table" then
            return 400, "application/json", Json.encode({ error = ERRORS["bad request"] })
        end
        local done, err, info = run(body)
        if not done then
            local status = err == "bad request" and 400 or 409
            return status, "application/json", Json.encode({ error = ERRORS[err] or tostring(err) })
        end
        return 200, "application/json", stateBody(req, info)
    end

    COMMANDS["/api/pair"] = pair

    local function handle(req)
        if not hostAllowed(req) then return 403, "text/plain", "unknown host\n" end
        local path = req.path
        local run = COMMANDS[path]
        if run then
            -- what the phone changes itself makes no notification
            if notify then notify.quiet(5) end
            -- and the state built after it is a fresh one
            invalidateShared()
            return command(req, run)
        end
        if path == "/" or path == "/index.html" then
            -- read per request (like the CSS), so page edits show on a reload;
            -- the start-up copy stands in if the file went missing meanwhile
            return 200, "text/html; charset=utf-8", mod:read("web/index.html") or page
        elseif path == "/base.css" then
            return 200, "text/css; charset=utf-8", mod:read("web/base.css") or ""
        elseif path == "/theme.css" then
            return 200, "text/css; charset=utf-8", themeCss()
        elseif path == "/skins.css" then
            -- read per request, so edits show on a page reload
            return 200, "text/css; charset=utf-8", mod:read("web/skins.css") or ""
        elseif path == "/state" then
            return 200, "application/json", stateBody(req)
        elseif path == "/dex" then
            local ok, body = pcall(function()
                return dex and dex.body(game, mod.options:get("spoilers"))
            end)
            if ok and body then return 200, "application/json", body end
            if not ok then mod.log:warn("pokedex failed: %s", tostring(body)) end
            return 409, "application/json", '{"error":"not loaded"}'
        elseif path == "/item/desc" then
            -- one item's description, for the item sheet (loaded when it
            -- opens, not with every bag update): FireRed's item data, Gold's
            -- pack text (its <NEXT> breaks as spaces; "?" is none)
            local raw = (req.query or ""):match("[?&]?id=([^&]*)")
            local id = raw and raw:gsub("%+", " "):gsub("%%(%x%x)", function(h)
                return string.char(tonumber(h, 16))
            end)
            local desc
            if id and snapshot3 then
                local ok, d = pcall(snapshot3.itemDesc, tonumber(id) or id)
                desc = ok and d or nil
            elseif id and game and game.data then
                local def = game.data.items and game.data.items[id]
                if type(def) == "table" and type(def.description) == "string" then
                    desc = def.description:gsub("<%u+>", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                    if desc == "" or desc == "?" then desc = nil end
                end
            end
            -- the text never changes while the game runs: the phone may keep it
            return 200, "application/json", Json.encode({ desc = desc or false }), 3600
        elseif path == "/pc/mon" then
            -- one POKéMON's full card, for the PC's POKéMON sheet
            local uid = tonumber((req.query or ""):match("[?&]?uid=(%d+)"))
            local ok, result = pcall(function()
                return uid and snapshot(game, { monUid = uid,
                    hidden = mod.options:get("show_hidden") and true or false })
            end)
            if not ok then mod.log:warn("pokemon details failed: %s", tostring(result)) end
            if ok and result and result.mon then return 200, "application/json", Json.encode(result.mon) end
            return 404, "application/json", '{"error":"unknown"}'
        elseif path == "/pc" then
            -- the boxes, as last stamped in /state
            pcSummary()
            if pcCache.body then
                return 200, "application/json", '{"version":' .. Json.encode(pcCache.version)
                    .. ',"pc":' .. pcCache.body .. "}"
            end
            return 409, "application/json", '{"error":"not loaded"}'
        elseif path == "/minimap" then
            local ok, body = pcall(function()
                return minimap and minimap.body(game, mod.options:get("spoilers"))
            end)
            if ok and body then return 200, "application/json", body end
            if not ok then mod.log:warn("minimap failed: %s", tostring(body)) end
            return 409, "application/json", '{"error":"not loaded"}'
        elseif path:match("^/anim/%x+$") then
            -- Crystal: a front pic's animation (sprites.frontAnim)
            local anim = sprites and sprites.anim and sprites.anim(path:match("^/anim/(%x+)$"))
            if anim then return 200, "application/json", Json.encode(anim), 86400 end
            return 404, "text/plain", "no animation\n"
        elseif path == "/glyphs" then
            -- ♂ / ♀ from the game's font, as pixel paths (see sprites.glyphPath)
            local out = {}
            if sprites and sprites.glyphPath and game and game.data then
                for key, ch in pairs({ male = "♂", female = "♀" }) do
                    local ok, d = pcall(sprites.glyphPath, game.data, ch)
                    if ok and d then out[key] = d end
                end
                -- Gen 2's shiny mark (the summary screen's ⁂)
                local ok, d = pcall(sprites.shinyPath, game.data)
                if ok and d then out.shiny = d end
            end
            return 200, "application/json", Json.encode(out)
        elseif path == "/sfx/ring" then
            -- Gen 2's phone ring, played on the phone during an incoming call
            local ok, bytes = pcall(function() return cry and cry.ringWav and cry.ringWav(game) end)
            if ok and bytes then return 200, "audio/wav", bytes end
            return 404, "text/plain", "no ring\n"
        elseif path == "/cry" then
            -- the species' cry as a WAV the phone plays itself
            local raw = (req.query or ""):match("[?&]?species=([^&]*)")
            local species = raw and raw:gsub("%+", " "):gsub("%%(%x%x)", function(h)
                return string.char(tonumber(h, 16))
            end)
            local ok, bytes = pcall(function()
                return cry and cry.wav(game, species, mod.options:get("spoilers"))
            end)
            if ok and bytes then return 200, "audio/wav", bytes end
            return 404, "text/plain", "no cry\n"
        elseif path == "/dex/entry" or path == "/dex/area" or path == "/dex/moves" or path == "/dex/evo" then
            local raw = (req.query or ""):match("[?&]?species=([^&]*)")
            local species = raw and raw:gsub("%+", " "):gsub("%%(%x%x)", function(h)
                return string.char(tonumber(h, 16))
            end)
            local ok, result = pcall(function()
                local spoilers = mod.options:get("spoilers")
                if path == "/dex/area" then return area and area.body(game, species, spoilers) end
                if path == "/dex/moves" then return dex and dex.moves(game, species, spoilers) end
                local hidden = mod.options:get("show_hidden") and true or false
                if path == "/dex/evo" then return dex and dex.family(game, species, spoilers, hidden) end
                return dex and dex.entry(game, species, spoilers, hidden)
            end)
            if not ok then mod.log:warn("pokedex %s failed: %s", path, tostring(result)) end
            if ok and result then return 200, "application/json", Json.encode(result) end
            return 404, "application/json", '{"error":"unknown"}'
        end
        local id = path:match("^/img/(%x+)%.png$")
        -- ?gray=1: the picture in plain gray shades, for a skin's sprite palette
        local gray = (req.query or ""):match("[?&]?gray=1") ~= nil
        local png = id and sprites and sprites.png(id, gray)
        if png then
            -- an id names one (art, palette) pair for good, so cache hard
            return 200, "image/png", png, 86400
        end
        return 404, "text/plain", "not found\n"
    end

    -- the server's options, read twice a second rather than every frame
    local optTimer, optWanted, optPort = 0, nil, 8080
    local function sync(dt)
        optTimer = optTimer - dt
        if optTimer <= 0 then
            optTimer = 0.5
            optWanted = mod.options:get("enabled")
            optPort = tonumber(mod.options:get("port")) or 8080
        end
        local wanted, port = optWanted, optPort
        if server and (not wanted or server.port ~= port) then
            server:stop()
            server, url = nil, nil
            retryTimer = 0
        end
        if wanted and not server then
            retryTimer = retryTimer - dt
            if retryTimer > 0 then return end
            local err
            server, err = Server.new(port, handle)
            if server then
                url = ("http://%s:%d"):format(lanAddress(), port)
                urlShownAt = nil
                lastBindError = nil
                mod.log:info("companion page at %s", url)
            else
                -- A hot reload leaves the previous listener open until it is
                -- collected, so collect and retry instead of giving up.
                collectgarbage("collect")
                retryTimer = RETRY_SECONDS
                if err ~= lastBindError then
                    lastBindError = err
                    mod.log:warn("could not listen on port %d (%s); retrying", port, tostring(err))
                end
            end
        end
        if live then pcall(live.track, game) end
        if actions then pcall(actions.tick, game) end
        pcall(edits.tick, game)
        if gear then
            local ok, err = pcall(gear.tick, game)
            if not ok then mod.log:warn("gear tick failed: %s", tostring(err)) end
        end
        if server then server:poll(dt) end
    end

    local lastSyncError
    mod.hooks:wrap("core.update", function(next, g, dt)
        game = g
        local ok, err = pcall(sync, dt)
        if not ok and err ~= lastSyncError then
            lastSyncError = err
            mod.log:error("companion update failed: %s", tostring(err))
        end
        return next(g, dt)
    end)

    -- Quitting a game on desktop starts a fresh copy of the program for the
    -- launcher (HostShell.restart), and Windows hands that copy the open
    -- sockets, so the listener would keep the port from the next game.
    -- love.quit asks this hook just before, so the server closes here, every
    -- time: from here the program either restarts or exits.
    mod.hooks:wrap("core.quit_to_launcher", function(next, ...)
        if server then
            pcall(server.stop, server)
            server, url = nil, nil
        end
        return next(...)
    end)

    local hud = {}
    mod.hooks:wrap("render.hud", function(next, g, viewport)
        next(g, viewport)
        local mode = mod.options:get("show_url")
        if not url or mode == "off" then return end
        if mode == "start" then
            local now = love.timer.getTime()
            urlShownAt = urlShownAt or now
            if now - urlShownAt > URL_SECONDS then return end
        end

        local lg = love.graphics
        local scale = math.max(1, math.floor((viewport.scale or 2) / 2))
        local font = lg.getFont()
        -- the text and its size, kept until the URL, PIN, scale or font change
        local sec = secure()
        local key = url .. "|" .. tostring(sec and pin) .. "|" .. scale .. "|" .. tostring(font)
        if hud.key ~= key then
            hud.key = key
            -- two lines, so it fits the narrow Game Boy screen: the address
            -- (and PIN), then where the QR code is
            local line1 = "Phone: " .. url .. (sec and ("  PIN " .. pin) or "")
            local line2 = gen3 and "QR code: START > PHONE" or "QR code: OPTION > PHONE"
            hud.text = line1 .. "\n" .. line2
            hud.w = (math.max(font:getWidth(line1), font:getWidth(line2)) + 8) * scale
            hud.h = (font:getHeight() * 2 + 4) * scale
        end
        local text, w, h = hud.text, hud.w, hud.h
        local x = (viewport.gameX or 0) + 4
        local y = (viewport.gameY or 0) + (viewport.gameHeight or viewport.height) - h - 4

        lg.push("all")
        lg.origin()
        lg.setColor(0, 0, 0, 0.7)
        lg.rectangle("fill", x, y, w, h, 3 * scale)
        lg.setColor(1, 1, 1, 1)
        lg.print(text, x + 4 * scale, y + 2 * scale, 0, scale, scale)
        lg.pop()
    end)

    -- OPTION > PHONE opens a scannable QR code of the URL. The screen is
    -- drawn with the Game Boy font and palette (Gen 3: START > PHONE, below).
    local encodeQr = runModule("qr.lua")
    -- Gen 3: its OPTION menu takes no rows from mods, so PHONE goes into the
    -- START menu (the ui.start_menu.items hook), just above EXIT, and opens
    -- the same QR code drawn with FireRed's font (qr_screen3.lua)
    if gen3 then
        local QrScreen3 = encodeQr and runModule("qr_screen3.lua", mod, encodeQr, function()
            if not url then return nil end
            if secure() then return url .. "/?key=" .. key, pin end
            return url
        end)
        -- development only: testbattle3.lua's START menu entries start a
        -- double battle. The file never ships (.modkitignore and
        -- .gitattributes leave it out of every release), so a released mod
        -- has none of it.
        local TestBattles = mod:info("testbattle3.lua") and runModule("testbattle3.lua", mod, platform) or nil
        if QrScreen3 then
            mod.hooks:wrap("ui.start_menu.items", function(next, g, items)
                items = next(g, items)
                if type(items) ~= "table" then return items end
                local add = { { id = QrScreen3.ID, label = "PHONE",
                    onSelect = function() QrScreen3.open() end } }
                -- development only (testbattle3.lua): start a double battle
                if TestBattles then
                    local okT, extra = pcall(TestBattles.entries, g)
                    for _, e in ipairs(okT and extra or {}) do add[#add + 1] = e end
                end
                local at = #items + 1
                for i, e in ipairs(items) do
                    if type(e) == "table" and e.id == "exit" then at = i end
                end
                for k, e in ipairs(add) do table.insert(items, at + k - 1, e) end
                return items
            end)
        end
        return
    end
    -- the QR code carries the key only in SECURE MODE; the screen also shows
    -- the PIN then, for devices that cannot scan (a PC browser)
    local QrScreen = encodeQr and runModule("qr_screen.lua", mod, encodeQr, function()
        if not url then return nil end
        if secure() then return url .. "/?key=" .. key, pin end
        return url
    end)
    if QrScreen then
        mod.hooks:wrap("ui.options.rows", function(next, g, rows)
            rows = next(g, rows)
            rows[#rows + 1] = {
                id = "second_screen_companion.phone",
                label = "PHONE",
                value = function() return url and "QR CODE" or "OFF" end,
                activate = function(game) game.stack:push(QrScreen.new(game)) end
            }
            return rows
        end)
    end
end
