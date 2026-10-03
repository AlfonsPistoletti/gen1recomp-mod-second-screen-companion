-- A species' cry as a WAV file, so the phone can play it through its own
-- speaker (GET /cry?species=ID). Rendered the way the game plays it
-- (src/core/Sound.lua playCry): a chip cry through ChipSynth, a cry that
-- borrows another species' sound with its own pitch / length resolved the
-- same way, and a mod's audio file decoded as it is. Both generations keep
-- their cries in data.audio.cries.
--
-- Rendered once per species and cached; the page may only ask for species
-- it may look at (seen, or anything with SPOILERS).
return function(mod, platform)
    local ChipSynth = require("src.core.ChipSynth")

    local C = {}
    local cache = {} -- species -> wav bytes | false

    -- Sound.lua resolveCry: follow `base` to the chip program, keeping this
    -- species' own pitch / length
    local function resolve(cries, def, depth)
        if type(def) ~= "table" or not def.base then return def end
        if depth > 8 then return nil end
        local base = resolve(cries, cries[def.base], depth + 1)
        if type(base) ~= "table" or not (base.header or base.chip) then return nil end
        return { header = base.header, chip = base.chip,
            pitch = def.pitch or base.pitch, length = def.length or base.length }
    end

    local function u32(n)
        return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256,
            math.floor(n / 16777216) % 256)
    end
    local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end

    -- 16-bit PCM WAV, down-mixed to mono (the game's cries are the same on
    -- both channels)
    local function wav(sd)
        local rate, channels, frames = sd:getSampleRate(), sd:getChannelCount(), sd:getSampleCount()
        local mono = love.sound.newSoundData(frames, rate, 16, 1)
        for i = 0, frames - 1 do
            local v = sd:getSample(i, 1)
            if channels > 1 then v = (v + sd:getSample(i, 2)) / 2 end
            mono:setSample(i, v)
        end
        local pcm = mono:getString()
        return "RIFF" .. u32(36 + #pcm) .. "WAVE"
            .. "fmt " .. u32(16) .. u16(1) .. u16(1) .. u32(rate) .. u32(rate * 2) .. u16(2) .. u16(16)
            .. "data" .. u32(#pcm) .. pcm
    end

    local function render(data, species)
        local cries = data.audio and data.audio.cries
        local def = cries and cries[species]
        if not def then return nil end
        local cry = resolve(cries, def, 0)
        if type(cry) == "table" and (cry.header or cry.chip) then
            local sd = ChipSynth.renderEffectData(data, cry.chip and cry or cry.header,
                { frequencyOffset = cry.pitch, cryLength = cry.length })
            return sd and wav(sd) or nil
        end
        -- a mod's own cry file
        local file = type(cry) == "table" and cry.file or cry
        if type(file) == "string" then
            local ok, sd = pcall(love.sound.newSoundData, file)
            return ok and sd and wav(sd) or nil
        end
        return nil
    end

    -- Gen 2's phone ring (Sfx_Call, what RingTwice_StartCall plays) as a
    -- WAV, so the phone can ring along with the game
    local ring = nil -- wav bytes | false
    function C.ringWav(game)
        local data = game and game.data
        local sfx = data and data.audio and data.audio.sfx
        local def = sfx and sfx.Sfx_Call
        if not def then return nil end
        if ring == nil then
            local ok, bytes = pcall(function()
                local sd = ChipSynth.renderEffectData(data, def, { frequencyOffset = 0, frameTicks = 0x100 })
                return sd and wav(sd) or false
            end)
            if not ok then mod.log:warn("ring sound failed: %s", tostring(bytes)) end
            ring = ok and bytes or false
        end
        return ring or nil
    end

    -- WAV bytes, or nil when there is no cry or the species may not be played
    function C.wav(game, species, spoilers)
        local data, save = game and game.data, game and game.save
        if not (data and save) or type(species) ~= "string" then return nil end
        local def = data.pokemon and data.pokemon[species]
        if type(def) ~= "table" or not def.dex then return nil end
        local known = platform.ownedSet(save)[def.id] or platform.seenSet(save)[def.id]
        if not (known or spoilers) then return nil end
        if cache[species] == nil then
            local ok, bytes = pcall(render, data, species)
            if not ok then mod.log:warn("cry %s failed: %s", species, tostring(bytes)) end
            cache[species] = ok and bytes or false
        end
        return cache[species] or nil
    end

    return C
end
