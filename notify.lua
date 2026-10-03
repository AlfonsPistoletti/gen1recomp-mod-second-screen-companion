-- The HANDS-OFF screen's notifications: what happened since the last
-- update, worked out by comparing what /state already carries (party, bag,
-- money, battle, place) plus the badges and the POKéDEX between two
-- updates. Nothing here touches the game, and it works the same on every
-- generation.
--
--   items     "Got POTION ×2" when a bag count goes up
--   POKéMON   a new party member ("Caught …" right after a wild battle,
--             else "… joined the party"), a level up, an evolution, an egg
--             hatching, a new POKéDEX entry (first seen)
--   battles   a battle's end: the prize money from a trainer ("Defeated …
--             · ¥120"), or a blackout (the money went down)
--   progress  a new badge, the first visit to a place this session
--
-- No notices for the first update after a save loads (that is the whole
-- save arriving), nor for a few seconds after the phone itself changed
-- something (quiet: edits, transfers).
return function(mod, platform, sprites)
    local N = {}

    local MAX = 20        -- notices kept for pages that poll late
    local PRIZE_WAIT = 12 -- seconds after a battle the prize money may show up

    local feed, nextId = {}, 1
    local epoch = ("%x"):format(os.time() % 0x1000000)
    local prev = nil
    local quietUntil = 0
    local visited = {}
    local battle = nil -- the battle on screen: { kind, title, money }
    local ended = nil  -- a battle just over: { kind, title, money, at }
    local held = {}    -- POKéMON / item news from inside a battle (see news)

    local function now() return love and love.timer and love.timer.getTime() or os.clock() end

    local function push(kind, text, icon)
        feed[#feed + 1] = { id = nextId, kind = kind, text = text, icon = icon or false }
        nextId = nextId + 1
        while #feed > MAX do table.remove(feed, 1) end
    end

    -- In a battle the engine works the results out well before the game
    -- shows them: a level is up the moment the EXP is counted, while the
    -- screen is still draining the foe's HP, and a caught POKéMON joins
    -- before "Gotcha!". So the party's and the bag's news waits until the
    -- battle is over and comes then, in order, ahead of the prize money:
    -- never before the game has said it.
    local function news(kind, text, icon)
        if battle then held[#held + 1] = { kind, text, icon }
        else push(kind, text, icon) end
    end

    -- the phone changed something itself: its own changes make no news
    function N.quiet(seconds)
        quietUntil = math.max(quietUntil, now() + (seconds or 3))
    end

    local function speciesName(game, sp)
        if platform.isGen3(game) then
            local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
            local okN, name = false, nil
            if ok then okN, name = pcall(Pokemon.name, tonumber(sp) or sp) end
            return okN and name or tostring(sp)
        end
        local def = game.data and game.data.pokemon and game.data.pokemon[sp]
        return type(def) == "table" and def.name or tostring(sp)
    end

    local function count(set)
        local n = 0
        for _, v in pairs(set or {}) do if v then n = n + 1 end end
        return n
    end

    -- the parts of /state (and the save) that make news, flattened
    local function capture(game, state)
        local save = platform.save(game)
        local s = { save = save, party = {}, items = {}, money = 0, place = false, battle = false,
            badges = {}, seen = {} }
        for _, m in ipairs(state.party or {}) do
            if m.uid then
                s.party[m.uid] = { name = m.name, species = m.species, level = tonumber(m.level),
                    egg = m.egg and true or false, icon = m.icon or false }
            end
        end
        local bag = state.bag or {}
        s.money = tonumber(bag.money) or tonumber(platform.money(save)) or 0
        for _, it in ipairs(bag.items or {}) do
            local id = tostring(it.id)
            local e = s.items[id] or { name = it.name, icon = it.icon or false, n = 0 }
            e.n = e.n + (tonumber(it.count) or 1)
            s.items[id] = e
        end
        local live = state.live or {}
        s.place = live.location and live.location.name or false
        if live.battle then s.battle = { kind = live.battle.kind, title = live.battle.title } end
        -- the badges and HALL OF FAME as /state already has them
        local badges = state.badges
        if badges == nil then
            local okB, b = pcall(platform.badges, game)
            badges = okB and b or {}
        end
        for _, b in ipairs(badges) do s.badges[b.name] = b.has end
        if state.champion ~= nil then
            s.champion = state.champion and true or false
        else
            local okH, champ = pcall(platform.champion, game)
            s.champion = okH and champ or false
        end
        -- the POKéDEX: counted every time, copied only when it grew
        local seenSet, n = platform.seenSet(save) or {}, 0
        for _, v in pairs(seenSet) do if v then n = n + 1 end end
        s.seenCount = n
        if prev and prev.save == save and prev.seenCount == n then
            s.seen = prev.seen
        else
            for sp, v in pairs(seenSet) do if v then s.seen[sp] = true end end
        end
        return s
    end

    function N.update(game, state)
        if not (game and state) then return end
        local okC, s = pcall(capture, game, state)
        if not okC then mod.log:warn("notices failed: %s", tostring(s)) return end
        -- a save loaded (or none yet): this one is the start, no news
        if not prev or prev.save ~= s.save then
            prev, battle, ended, visited, held = s, nil, nil, {}, {}
            if s.place then visited[s.place] = true end
            return
        end
        local t = now()
        local quiet = t < quietUntil

        -- battles: remember the money it started with; afterwards the
        -- prize (or a blackout's loss) shows as the difference
        if s.battle and not battle then battle = { kind = s.battle.kind, title = s.battle.title, money = prev.money } end
        if battle and not s.battle then
            ended = { kind = battle.kind, title = battle.title, money = battle.money, at = t }
            battle = nil
            -- what happened in it, now that the game has shown it
            for _, n in ipairs(held) do push(n[1], n[2], n[3]) end
            held = {}
        end
        if ended then
            local diff = s.money - ended.money
            if diff < 0 then
                push("battle", ("Blacked out · lost ¥%d"):format(-diff))
                ended = nil
            elseif diff > 0 and t - ended.at <= PRIZE_WAIT then
                if ended.kind == "trainer" or ended.kind == "link" then
                    push("battle", ("Defeated %s · ¥%d"):format(ended.title or "TRAINER", diff))
                else
                    push("battle", ("Picked up ¥%d"):format(diff))
                end
                ended = nil
            elseif t - ended.at > PRIZE_WAIT then
                ended = nil
            end
        end

        if not quiet then
            -- the party: new members, levels, evolutions, eggs hatching
            local wildJustEnded = (prev.battle and prev.battle.kind == "wild") or (s.battle and s.battle.kind == "wild")
            for uid, m in pairs(s.party) do
                local was = prev.party[uid]
                if not was then
                    if not m.egg then
                        if wildJustEnded then news("pokemon", ("Caught %s!"):format(m.name), m.icon)
                        else news("pokemon", ("%s joined the party"):format(m.name), m.icon) end
                    end
                elseif was.egg and not m.egg then
                    news("pokemon", ("The EGG hatched into %s!"):format(m.species or m.name), m.icon)
                else
                    if m.species and was.species and m.species ~= was.species then
                        news("pokemon", ("%s evolved into %s!"):format(was.name, m.species), m.icon)
                    end
                    if m.level and was.level and m.level > was.level then
                        news("pokemon", ("%s grew to Lv.%d"):format(m.name, m.level), m.icon)
                    end
                end
            end
            -- the bag: counts that went up (a sort only reorders)
            for id, it in pairs(s.items) do
                local was = prev.items[id]
                local gained = it.n - (was and was.n or 0)
                if gained > 0 then
                    news("item", gained > 1 and ("Got %s ×%d"):format(it.name, gained) or ("Got %s"):format(it.name), it.icon)
                end
            end
            -- badges
            for name, has in pairs(s.badges) do
                if has and not prev.badges[name] then push("progress", ("Got the %s!"):format(name)) end
            end
            if s.champion and not prev.champion then push("progress", "Entered the HALL OF FAME!") end
            -- the POKéDEX: a species seen for the first time
            for sp in pairs(s.seen) do
                if not prev.seen[sp] then push("progress", ("New in the POKéDEX: %s"):format(speciesName(game, sp))) end
            end
            -- a place for the first time this session
            if s.place and s.place ~= prev.place and not visited[s.place] then
                push("progress", ("Arrived at %s"):format(s.place))
            end
        end
        if s.place then visited[s.place] = true end
        prev = s
    end

    -- /state's part: the recent notices, with the feed's start (a page that
    -- sees a new epoch starts counting again)
    function N.state()
        return { epoch = epoch, list = feed }
    end

    return N
end
