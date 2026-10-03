-- Gen 3 (FireRed / LeafGreen): a species' cry as a WAV file, so the phone
-- can play it through its own speaker (GET /cry?species=ID). FireRed's
-- cries are PCM samples, not chip programs: the sample comes out of the
-- game's audio pack the way the game finds it (m4a_player startCry: the
-- species' cry index, its sample) and is rendered with the game's own
-- mixer (m4a_sample renderCryMix: pitch, chorus voice, length and release
-- envelope of the normal cry mode), so it sounds as it does in the
-- POKéDEX. Rendered once per species and cached; the page may only ask for
-- species it may look at (dex.access: seen, or anything with SPOILERS).
return function(mod, platform, dex)
    local C = {}
    local cache = {} -- species -> wav bytes | false

    local OUT_RATE = 22050

    local function u32(n)
        return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256,
            math.floor(n / 16777216) % 256)
    end
    local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end

    -- floats -1..1 -> 16-bit mono PCM WAV
    local function wav(samples, rate)
        local parts = {}
        for i = 1, #samples do
            local v = math.floor(samples[i] * 32767 + 0.5)
            if v > 32767 then v = 32767 elseif v < -32768 then v = -32768 end
            if v < 0 then v = v + 65536 end
            parts[i] = string.char(v % 256, math.floor(v / 256))
        end
        local pcm = table.concat(parts)
        return "RIFF" .. u32(36 + #pcm) .. "WAVE"
            .. "fmt " .. u32(16) .. u16(1) .. u16(1) .. u32(rate) .. u32(rate * 2) .. u16(2) .. u16(16)
            .. "data" .. u32(#pcm) .. pcm
    end

    local function render(sp)
        local Audio = require("src.core.game3.audio")
        local Sample = require("src.core.game3.m4a_sample")
        local Mix = require("src.core.game3.m4a_mix")
        local pack = Audio._pack
        if not (pack and pack.index and pack.samplesBin) then return nil end
        -- m4a_player.lua startCry: the cry index, else species - 1
        local cryIds = pack.index.cryIds or {}
        local idx = cryIds[sp] or cryIds[tostring(sp)] or math.max(0, sp - 1)
        local cries = pack.index.cries or {}
        local cry = cries[idx] or cries[tostring(idx)]
        if not (cry and cry.sampleId) then return nil end
        local meta = pack.samples[cry.sampleId] or pack.samples[tostring(cry.sampleId)]
        local pcm = meta and Sample.loadPcm(pack.samplesBin, meta)
        if not pcm then return nil end
        local config = Audio.config and Audio.config() or {}
        local params = Sample.cryParams(0, nil, config.cryModeOverrides)
        local out, info = Sample.renderCryMix(pcm, Mix.waveRate(meta.freq), params, { outRate = OUT_RATE })
        if not (out and #out > 0) then return nil end
        return wav(out, info and info.outRate or OUT_RATE)
    end

    -- WAV bytes, or nil when there is no cry or the species may not be played
    function C.wav(game, species, spoilers)
        local sp = dex and dex.access and dex.access(game, species, spoilers)
        if not sp then return nil end
        if cache[sp] == nil then
            local ok, bytes = pcall(render, sp)
            if not ok then mod.log:warn("cry %s failed: %s", tostring(sp), tostring(bytes)) end
            -- not ready yet (audio still loading): try again next time
            if ok and bytes == nil then return nil end
            cache[sp] = ok and bytes or false
        end
        return cache[sp] or nil
    end

    return C
end
