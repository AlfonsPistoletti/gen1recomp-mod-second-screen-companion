-- Gen 3 (FireRed / LeafGreen / Emerald): the full-screen QR code for the
-- companion URL, opened from the START menu's PHONE entry (Gen 3's OPTION
-- menu has no rows a mod can add), plus the pairing PIN in SECURE MODE.
-- A layer on the game's own screen stack (src/ui/game3/stack.lua), drawn
-- with FireRed's font; A / B / START close it, back to the START menu.
return function(mod, encodeQr, currentUrl)
    local Stack = require("src.ui.game3.stack")
    local okF, FrlgFont = pcall(require, "src.ui.game3.frlg_font")
    if not okF then FrlgFont = nil end

    local ID = "second_screen_companion.phone"
    local W, H = 240, 160
    local QR_TOP, QR_HEIGHT = 22, 132

    local Screen = { isMenu = true }
    local state = { url = nil, pin = nil, matrix = nil, size = nil }

    local function refresh()
        -- the server can come up (or move ports) while this is open
        local url, pin = currentUrl()
        state.pin = pin
        if url ~= state.url then
            state.url = url
            state.matrix, state.size = nil, nil
            if url then state.matrix, state.size = encodeQr(url) end
        end
    end

    local function centered(text, y)
        if FrlgFont then
            local okW, w = pcall(FrlgFont.measure, text)
            local x = math.floor((W - ((okW and tonumber(w)) or 0)) / 2)
            pcall(FrlgFont.draw, text, x, y)
        else
            local font = love.graphics.getFont()
            love.graphics.print(text, math.floor((W - font:getWidth(text)) / 2), y)
        end
    end

    function Screen.update() refresh() end

    function Screen.handleInput(input)
        if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
            -- SE_SELECT, as the game's own windows close
            local okA, Audio = pcall(require, "src.core.game3.audio")
            if okA and Audio.playSe then pcall(Audio.playSe, 5) end
            Stack.pop(ID)
        end
    end

    function Screen.draw()
        local lg = love.graphics
        lg.push("all")
        lg.setColor(1, 1, 1, 1)
        lg.rectangle("fill", 0, 0, W, H)
        -- text in black where FireRed's font is missing (it brings its own colours)
        lg.setColor(0, 0, 0, 1)
        if not state.matrix then
            centered("PHONE SERVER OFF", 60)
            centered("Turn it on in the mod options.", 80)
            lg.pop()
            return
        end
        -- SECURE MODE: the PIN pairs devices that cannot scan
        centered(state.pin and ("PIN " .. state.pin .. " OR SCAN") or "SCAN WITH YOUR PHONE", 4)
        local size = state.size
        -- whole pixels per module, keeping a module of quiet zone around it
        local scale = math.max(1, math.floor(QR_HEIGHT / (size + 2)))
        local px = size * scale
        local ox = math.floor((W - px) / 2)
        local oy = QR_TOP + math.floor((QR_HEIGHT - px) / 2)
        lg.setColor(0, 0, 0, 1)
        for y = 0, size - 1 do
            local row = state.matrix[y]
            for x = 0, size - 1 do
                if row[x] then lg.rectangle("fill", ox + x * scale, oy + y * scale, scale, scale) end
            end
        end
        centered((state.url or ""):gsub("^https?://", ""):gsub("/%?key=.*$", ""), H - 15)
        lg.pop()
    end

    local Q = {}
    Q.ID = ID
    function Q.open()
        refresh()
        Stack.push(ID, Screen, { hideBelow = true })
    end
    return Q
end
