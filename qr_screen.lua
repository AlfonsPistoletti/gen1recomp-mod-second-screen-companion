-- Full-screen QR code for the companion URL, opened from the OPTION menu's
-- PHONE row, plus the pairing PIN in SECURE MODE. Any of A / B / START
-- closes it, the way OPTION pages close.
return function(mod, encodeQr, currentUrl)
    local Font = require("src.render.Font")
    local PaletteFX = require("src.render.PaletteFX")

    local W, H = 160, 144
    local QR_TOP, QR_HEIGHT = 18, 108

    local Screen = {}
    Screen.__index = Screen
    Screen.isOpaque = true

    function Screen.new(game)
        return setmetatable({ game = game }, Screen)
    end

    -- same palette as the OPTION menu it opens from
    function Screen:sgbPalettes(game)
        return PaletteFX.wholeNamed(game.data, "MEWMON")
    end

    function Screen:update()
        -- the server can come up (or move ports) while this is open
        local url, pin = currentUrl()
        self.pin = pin
        if url ~= self.url then
            self.url = url
            self.matrix, self.size = nil, nil
            if url then self.matrix, self.size = encodeQr(url) end
        end
        local input = self.game.input
        if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
            if self.game.data then require("src.core.Sound").play(self.game.data, "Press_AB") end
            self.game.stack:pop()
        end
    end

    local function centered(text, y)
        Font.draw(text, math.floor((W - Font.width(text)) / 2), y)
    end

    function Screen:draw()
        local lg = love.graphics
        lg.push("all")
        lg.setColor(1, 1, 1, 1)
        lg.rectangle("fill", 0, 0, W, H)
        lg.setColor(0, 0, 0, 1)

        if not self.matrix then
            centered("PHONE SERVER OFF", 56)
            centered("Turn it on in", 72)
            centered("the mod options.", 84)
            lg.pop()
            return
        end

        -- SECURE MODE: the PIN pairs devices that cannot scan
        centered(self.pin and ("PIN " .. self.pin .. " OR SCAN") or "SCAN WITH PHONE", 6)
        local size = self.size
        -- whole pixels per module, keeping at least a module of quiet zone
        local scale = math.max(1, math.floor(QR_HEIGHT / (size + 2)))
        local px = size * scale
        local ox = math.floor((W - px) / 2)
        local oy = QR_TOP + math.floor((QR_HEIGHT - px) / 2)
        for y = 0, size - 1 do
            local row = self.matrix[y]
            for x = 0, size - 1 do
                if row[x] then lg.rectangle("fill", ox + x * scale, oy + y * scale, scale, scale) end
            end
        end
        -- host:port only: the code carries the edit key, the text does not
        centered(self.url:match("^http://([^/]+)") or self.url, 130)
        lg.pop()
    end

    return Screen
end
