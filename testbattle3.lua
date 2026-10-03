-- DEVELOPMENT ONLY, never released (.modkitignore and .gitattributes
-- leave this file out of `modkit pack` and the GitHub release zip; main.lua
-- loads it only when it's there). Gen 3: START menu entries that start a
-- double battle right away, to try the companion's double-battle view
-- without walking to one. The game's own battle is used (battle_bridge
-- BattleBridge.start, as the scripts start theirs), against trainers from
-- the game's own data:
--   DOUBLE TEST    a trainer the game marks as a double battle
--   2 TRAINERS     (Emerald) two trainers at once, like the game's
--                  two-trainer battles (twoOpponents + trainerIdB)
-- Each press takes the next suitable trainer, so the teams vary.
-- No trainer is marked as beaten (the game's scripts do that, not the
-- battle), and losing doesn't black you out (scriptedLoss, as the BATTLE
-- TOWER does). EXP and prize money are won as in any battle.
return function(mod, platform)
    local T = {}

    local next1, next2 = 0, 0

    local function trainers()
        local ok, Trainers = pcall(require, "src.core.game3.scripting.trainers")
        if not ok then return nil end
        return Trainers
    end

    -- every trainer id in the game's data, in order
    local idList = nil
    local function ids(Trainers)
        if idList then return idList end
        idList = {}
        local pack = Trainers.pack and Trainers.pack()
        for id in pairs(pack and pack.trainers or {}) do
            if tonumber(id) then idList[#idList + 1] = tonumber(id) end
        end
        table.sort(idList)
        return idList
    end

    -- the next trainer after `from` that `want` accepts
    local function nextTrainer(Trainers, from, want)
        local list = ids(Trainers)
        local n = #list
        for step = 1, n do
            local id = list[(from + step - 1) % n + 1]
            local t = Trainers.get(id)
            if t and type(t.party) == "table" and want(t) then
                return id, (from + step) % n
            end
        end
        return nil, from
    end

    local function start(game, opts)
        local okS, StartMenu = pcall(require, "src.ui.game3.start_menu")
        if okS and StartMenu.close then pcall(StartMenu.close, true) end
        local okB, Bridge = pcall(require, "src.core.game3.battle_bridge")
        local okR, Runtime = pcall(require, "src.core.game3.runtime")
        local Trainers = trainers()
        if not (okB and okR and Trainers) then return end
        local foe = Trainers.foeFromId(opts.trainerId)
        if not foe then return end
        opts.wild = false
        opts.scriptedLoss = true
        opts.done = function() end
        local ok, err = pcall(Bridge.start, Runtime._mod, game, foe, opts)
        if not ok then mod.log:warn("test battle failed: %s", tostring(err)) end
    end

    -- the START menu entries
    function T.entries(game)
        local out = {
            { id = "second_screen_companion.testdouble", label = "DOUBLE TEST",
                onSelect = function(g)
                    local Trainers = trainers()
                    if not Trainers then return end
                    local id
                    id, next1 = nextTrainer(Trainers, next1, function(t)
                        return t.doubleBattle and #t.party >= 2
                    end)
                    if id then start(g or game, { trainerId = id, double = true }) end
                end },
        }
        if platform.isRse(game) then
            out[#out + 1] = { id = "second_screen_companion.testtwo", label = "2 TRAINERS",
                onSelect = function(g)
                    local Trainers = trainers()
                    if not Trainers then return end
                    local single = function(t) return not t.doubleBattle and #t.party >= 1 end
                    local a, b
                    a, next2 = nextTrainer(Trainers, next2, single)
                    b, next2 = nextTrainer(Trainers, next2, single)
                    if a and b and a ~= b then
                        start(g or game, { trainerId = a, trainerIdB = b, twoOpponents = true, double = true })
                    end
                end }
        end
        return out
    end

    return T
end
