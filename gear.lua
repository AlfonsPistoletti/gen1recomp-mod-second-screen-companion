-- The GEAR tab (Gen 2 only): the POKéGEAR's clock, phone and radio on the
-- phone.
--
-- PHONE: a call runs the contact's real callee script on the overworld VM,
-- the way the POKéGEAR's phone card does (Pokegear:callContact ->
-- Phone.call -> Game2:runPokegearCall). The VM hands every page it prints
-- and every YES / NO it asks to host hooks (vm.showTextFn / vm.yesornoFn);
-- for the length of the call those hooks point here, so the dialogue shows
-- on the phone instead of the TV. Because the script really runs, whatever
-- it sets (a rematch, a gift) is set. The world is frozen while the script
-- runs (World:busy), as it is behind the POKéGEAR.
--
-- A call the GAME receives still rings and plays on the TV as always; the
-- phone follows along (see "incoming calls") and its buttons press A / B.
--
-- RADIO: a station's song stays on as the map music after leaving the
-- radio (Pokegear.exitRadioMusic), which is what gives the radio its field
-- effects (World.musicEncounterRate: POKéMON MARCH / UNOWN RADIO double wild
-- encounters, LULLABY halves them; the POKé FLUTE station wakes SNORLAX).
-- Tuning from the phone runs the station's show off screen until it picks
-- its song, then leaves that song on the way the POKéGEAR does.
return function(mod, platform, live)
    local Phone = require("src.core.gen2.Phone")
    local Pokegear = require("src.ui.gen2.Pokegear")
    local FieldMoves = require("src.world.gen2.FieldMoves")
    local Music = require("src.core.Music")
    local TextBox = require("src.render.TextBox")

    local G = {}

    local Clock = require("src.core.gen2.Clock")
    local IDLE_SECONDS = 60     -- an unanswered call pages on by itself after this
    local RADIO_FRAMES = 4000   -- how far a show may run to pick its song
    local JINGLE = "Music_PokemonChannel"
    -- World.musicEncounterRate's songs, plus the flute (Specials.SnorlaxAwake)
    local EFFECTS = {
        Music_PokemonMarch = { rate = "x2", song = "POKéMON MARCH" },
        Music_RuinsOfAlphRadio = { rate = "x2", song = "UNOWN RADIO" },
        Music_PokemonLullaby = { rate = "half", song = "POKéMON LULLABY" },
        Music_PokeFluteChannel = { flute = true, song = "POKé FLUTE" },
    }
    -- POKéMON MUSIC opens on the title theme and only then starts the
    -- day's MARCH or LULLABY, which is the song that matters
    local MARCH_OR_LULLABY = { Music_PokemonMarch = true, Music_PokemonLullaby = true }

    local tuned = nil   -- { knob, song } of the last station tuned from the phone
    local session = nil -- the call on the phone, see G.call

    local function now() return love.timer.getTime() end

    local function world(game)
        local w = platform.world(game)
        return w and w.vm and w or nil
    end

    -- a POKéGEAR that is never drawn: its card flags, clock and stations.
    -- An empty menuGfx skips the tile sheet, so nothing is loaded.
    local function gear(game)
        return Pokegear.new(game, { menuGfx = {} })
    end

    -- the font's two-tile glyphs, spelled out
    local GLYPHS = { ["<PK><MN>"] = "PKMN", ["<PO><KE>"] = "POKé" }

    local function glyphs(s)
        s = tostring(s or "")
        for token, text in pairs(GLYPHS) do s = s:gsub(token, text) end
        return s
    end

    local function oneLine(s)
        return (glyphs(s):gsub("%s*\n%s*", " "))
    end

    ---- phone ----------------------------------------------------------------

    local function phoneContext(game, w, pg)
        local hour, minute = pg:clockParts()
        return { map = w.map and w.map.def, clock = { hour = hour, minute = minute } }
    end

    -- one text command as one paragraph on the phone: tokens filled in, and
    -- the little box's line / page breaks gone (a word the box split,
    -- "POKé-" / "MON" or "man-" / "aged", joined back up)
    local function addPage(game, body)
        local ok, text = pcall(TextBox.substitute, game, body)
        text = glyphs(ok and text or body)
        text = text:gsub("%-[\n\v\f]%s*(%a)", "%1"):gsub("[\n\v\f]", " ")
        text = text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
        if text ~= "" then session.pages[#session.pages + 1] = text end
    end

    -- put the VM's own hooks back (only the ones this call replaced)
    local function unhook()
        if not (session and session.vm) then return end
        local vm = session.vm
        if vm.showTextFn == session.hooks.showText then vm.showTextFn = session.saved.showText end
        if vm.yesornoFn == session.hooks.yesorno then vm.yesornoFn = session.saved.yesorno end
        session.vm = nil
    end

    local function hook(vm, showText, yesorno)
        session.vm = vm
        session.saved = { showText = vm.showTextFn, yesorno = vm.yesornoFn }
        session.hooks = { showText = showText, yesorno = yesorno }
        vm.showTextFn, vm.yesornoFn = showText, yesorno
    end

    -- the script ended: the hooks go back. Nothing else: an outgoing call
    -- leaves the incoming-call timer alone (Phone.endCall is the tail of a
    -- RECEIVED call only; the POKéGEAR never runs it either)
    local function finish()
        unhook()
        session.waiting, session.resume, session.pending = nil, nil, nil
        session.ringing = nil
        session.done = true
    end

    -- hand the VM its answer; a script error ends the call cleanly
    local function resume(fn, value)
        session.waiting, session.resume = nil, nil
        session.seen = now()
        local ok, err = pcall(fn, value)
        if not ok then
            mod.log:warn("phone call failed: %s", tostring(err))
            finish()
            return
        end
        if session.vm and not session.vm:running() then finish() end
    end

    local serial = 0
    local function newSession(id, name, incoming)
        serial = serial + 1
        session = { n = serial, id = id, name = oneLine(name), pages = {}, seen = now(),
            incoming = incoming == true or nil }
    end

    -- POST /api/gear/call { id }
    function G.call(game, id)
        id = tonumber(id)
        local w = world(game)
        if not (w and game.save) then return nil, "not loaded" end
        if session and not session.done then return nil, "field busy" end
        if not platform.worldFree(game) then return nil, "field busy" end
        local pg = gear(game)
        if not pg:flags().phone then return nil, "no card" end
        local listed = false
        for _, cid in ipairs(Phone.contacts(game.save)) do
            if cid == id then listed = true end
        end
        if not (id and id ~= 0 and listed) then return nil, "stale" end

        local ctx = phoneContext(game, w, pg)
        local name = Phone.contactName(id, game.data.trainers or game.data.gen2Trainers)
        newSession(id, name, false)
        if not Phone.mapHasService(ctx) then
            addPage(game, pg:phoneText("GearOutOfService"))
            session.done = true
            return true
        end
        local call = Phone.call(game.save, id, ctx)
        local canned = (call.kind == "outofarea" and "OutOfArea")
            or (call.kind == "justtalk" and "JustTalkToThem")
            or (call.wrongNumber and "WrongNumber")
        local vm = w.vm
        if canned or call.kind ~= "call" or not (call.scriptKey and vm.scripts[call.scriptKey]) then
            addPage(game, pg:phoneText(canned or "OutOfArea"))
            session.done = true
            return true
        end

        -- the phone is the text box for this call
        hook(vm, function(body, onDone, stay)
            addPage(game, body)
            session.resume = onDone
            -- a page that stays up (under a YES / NO, or held) moves on by itself
            session.waiting = stay and "auto" or "next"
        end, function(onChoose)
            session.resume = onChoose
            session.waiting = "yesno"
        end)
        vm.curPhoneCaller = id
        local ok, started = pcall(vm.start, vm, call.scriptKey)
        if not ok then mod.log:warn("phone call failed: %s", tostring(started)) end
        if not (ok and started) then
            unhook()
            session = nil
            return nil, "field busy"
        end
        if not vm:running() then finish() end
        return true
    end

    ---- incoming calls -------------------------------------------------------
    --
    -- A call the game receives rings and plays on the TV exactly as always;
    -- the phone only follows along. Its hooks pass every page and YES / NO
    -- straight through to the game's own (World:showText / askYesNo) and
    -- just note them, so answering in the game works as if the phone
    -- weren't there. The phone's buttons are button taps (mod.input): A for
    -- the next page, A for YES (the cursor moved up first if needed), B for
    -- NO, and only while the game's text box or YES / NO box is up.

    local ChoiceBox = require("src.ui.ChoiceBox")
    local TAP_GAP = 8 -- frames between taps, so one tap is never read twice
    local lastGame = nil

    local function stackTop(game)
        local states = game and game.stack and game.stack.states
        return states and states[#states] or nil
    end

    -- PhoneRing.script's event: the rows are built and about to run
    local function onIncoming(ev)
        local game = lastGame
        local w = world(game)
        if not (w and ev) then return end
        if session and not session.done then return end -- a phone call runs already
        newSession(ev.contact, ev.name, true)
        -- ringing until the player picks up (A on the RING!…RING! page)
        session.ringing = true
        local vm = w.vm
        local showText, yesorno = vm.showTextFn, vm.yesornoFn
        hook(vm, function(body, onDone, ...)
            if session and session.vm == vm then
                addPage(game, body)
                session.waiting = "next"
                session.seen = now()
            end
            return showText(body, function(...)
                -- the game moved on (a button in the game or on the phone)
                if session and session.vm == vm then
                    session.ringing = nil
                    if session.waiting == "next" then session.waiting = nil end
                end
                if onDone then return onDone(...) end
            end, ...)
        end, function(onChoose)
            if session and session.vm == vm then session.waiting = "yesno" end
            return yesorno(function(...)
                if session and session.vm == vm then session.waiting = nil end
                if onChoose then return onChoose(...) end
            end)
        end)
    end
    mod.events:on("phone.call_received", function(ev)
        local ok, err = pcall(onIncoming, ev)
        if not ok then mod.log:warn("incoming call: %s", tostring(err)) end
    end)

    -- one frame of the phone's pending answer to an incoming call
    local function pressFor(game)
        local want = session.pending
        if not want then return end
        -- the page / question it was meant for is gone: forget it
        if #session.pages ~= session.pendingPage
            or (want == "next" and session.waiting ~= "next")
            or (want ~= "next" and session.waiting ~= "yesno") then
            session.pending = nil
            return
        end
        session.gap = (session.gap or 0) - 1
        if session.gap > 0 then return end
        local top = stackTop(game)
        if not top then return end
        local btn
        if want == "next" then
            -- the text box has typed its page out and waits for a button
            if getmetatable(top) ~= ChoiceBox and (top.done or top.waiting)
                and (top.preWait or 0) <= 0 then
                btn = "a"
            end
        elseif getmetatable(top) == ChoiceBox and not top.holdFrames then
            if want == "no" then
                btn, session.pending = "b", nil
            elseif top.index ~= 1 then
                btn = "up"
            else
                btn, session.pending = "a", nil
            end
        end
        if btn then
            mod.input:tap(game, btn)
            session.gap = TAP_GAP
        end
    end

    -- POST /api/gear/answer { what = "next" | "yes" | "no" | "close" }
    function G.answer(game, what)
        if not session then return true end
        if what == "close" then
            if session.done then session = nil end
            return true
        end
        if session.incoming then
            if session.done then return true end
            session.pending = what
            session.pendingPage = #session.pages
            session.gap = 0
            return true
        end
        if session.waiting == "next" and what == "next" then
            resume(session.resume)
        elseif session.waiting == "yesno" and (what == "yes" or what == "no") then
            resume(session.resume, what == "yes")
        end
        return true
    end

    -- every frame: pages that move on by themselves, the idle net, and a
    -- world that went away under the call
    function G.tick(game)
        lastGame = game
        if not session or session.done then return end
        local vm = session.vm
        local w = world(game)
        if vm and not (w and w.vm == vm) then
            finish()
            -- an incoming call closes with the game's (see below)
            if session.incoming then session = nil end
            return
        end
        if session.incoming then
            -- the rows start right after the ring event; the run's key is
            -- the call's own rows table (PhoneRing.script, Vm:start's ctxKey)
            if vm and vm:running() and not session.started then
                session.started = true
                session.runKey = vm.ctxKey
            end
            -- over when the VM stops, or has moved on to another script
            -- right away (a map script, a trainer walking up): it never
            -- goes idle in between then
            if session.started and not (vm and vm:running()
                    and (session.runKey == nil or vm.ctxKey == session.runKey)) then
                finish()
                -- the game played the call through: nothing is left to read
                -- on the phone, so its box closes by itself
                session = nil
                return
            end
            pressFor(game)
            return
        end
        if vm and not vm:running() then
            finish()
            return
        end
        if session.waiting == "auto" then
            resume(session.resume)
        elseif session.waiting and now() - session.seen > IDLE_SECONDS then
            -- nobody answers on the phone: page on and say NO, so the game
            -- never stays frozen behind a call
            resume(session.resume, false)
        end
    end

    local function callState()
        if not session then return nil end
        local waiting = (session.waiting == "next" or session.waiting == "yesno") and session.waiting or nil
        return {
            n = session.n, id = session.id, name = session.name, pages = session.pages,
            incoming = session.incoming or false,
            ringing = session.ringing or false,
            -- an answer from the phone is on its way to the game
            waiting = not session.pending and waiting or nil,
            done = session.done or false,
        }
    end

    ---- radio ----------------------------------------------------------------

    -- POST /api/gear/tune { knob }
    function G.tune(game, knob)
        knob = tonumber(knob)
        local w = world(game)
        if not (w and game.save) then return nil, "not loaded" end
        if session and not session.done then return nil, "field busy" end
        if not platform.worldFree(game) then return nil, "field busy" end
        local pg = gear(game)
        if not pg:flags().radio then return nil, "no card" end
        local row
        for _, r in ipairs(pg:stations()) do
            if r.knob == knob and r.station then row = r end
        end
        if not row then return nil, "no station" end

        -- UpdateRadioStation, then the show off screen until it picks its song
        pg.tuningKnob = knob
        pg:tuneRadio()
        local radio = pg.radio
        if not radio then return nil, "no station" end
        local song
        for _ = 1, RADIO_FRAMES do
            radio:step()
            local m = radio.music
            if m and m ~= JINGLE then
                song = m
                if MARCH_OR_LULLABY[m] then break end
                if row.station ~= "POKEMON_MUSIC" and row.station ~= "LETS_ALL_SING" then break end
            end
        end
        if not song then return nil, "no station" end
        -- the song plays and stays on as the map music (ExitPokegearRadio_HandleMusic)
        radio.music = song
        pg.radioSong = nil
        pg:playRadioMusic()
        Pokegear.exitRadioMusic(game, pg.radioMusicPlaying)
        tuned = { knob = knob, song = song }
        return true
    end

    -- POST /api/gear/off: the map's own music back
    function G.off(game)
        local w = world(game)
        if not (w and game.save) then return nil, "not loaded" end
        if not platform.worldFree(game) then return nil, "field busy" end
        tuned = nil
        if FieldMoves.isBiking(w.playerState) and w.playBikeMusic then
            w:playBikeMusic()
        else
            w:playMapMusic()
        end
        return true
    end

    ---- state ----------------------------------------------------------------

    function G.state(game)
        local w = world(game)
        if not (w and game.save) then return nil end
        local pg = gear(game)
        local flags = pg:flags()
        local out = {
            cards = { phone = flags.phone and true or false, radio = flags.radio and true or false },
            callable = platform.worldFree(game) and not (session and not session.done) or false,
            call = callState(),
        }

        local hour, minute, weekday = pg:clockParts()
        -- the clock card's words (Clock.weekdayName / daytimeLabel), so a
        -- language mod's names show here too
        local okD, day = pcall(Clock.weekdayName, weekday)
        out.clock = { day = okD and day or "", hour = hour, minute = minute }

        if out.cards.phone then
            local ctx = phoneContext(game, w, pg)
            local okSignal, signal = pcall(Phone.mapHasService, ctx)
            out.signal = okSignal and signal and true or false
            local trainers = game.data.trainers or game.data.gen2Trainers
            local events = w.vm.events
            local contacts = {}
            for slot, id in ipairs(Phone.contacts(game.save)) do
                if id and id ~= 0 then
                    local name, className = Phone.contactName(id, trainers)
                    local row = Phone.CONTACTS[id]
                    local where = nil
                    if row and row.map and live then
                        local ok, n = pcall(live.locationName, game, row.map)
                        where = ok and n or nil
                    end
                    local okR, ready = pcall(Phone.isReadyForRematch, events, id)
                    contacts[#contacts + 1] = {
                        slot = slot, id = id, name = oneLine(name),
                        class = className and oneLine(className) or nil,
                        where = where, rematch = okR and ready or false,
                    }
                end
            end
            out.contacts = contacts
        end

        if out.cards.radio then
            local stations = {}
            local ok, rows = pcall(pg.stations, pg)
            for _, r in ipairs(ok and rows or {}) do
                if r.station then
                    stations[#stations + 1] = { knob = r.knob, freq = r.frequency, name = oneLine(r.name or r.station) }
                end
            end
            out.stations = stations
            local song = Music.mapSong()
            if tuned and tuned.song ~= song then tuned = nil end
            out.playing = tuned and tuned.knob or nil
            local effect = song and EFFECTS[song]
            if effect then
                out.effect = { rate = effect.rate, flute = effect.flute, song = effect.song }
            end
        end
        return out
    end

    return G
end
