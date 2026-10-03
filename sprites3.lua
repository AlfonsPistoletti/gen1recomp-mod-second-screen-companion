-- Gen 3 (FireRed / LeafGreen) art for the phone page as PNGs. Unlike the
-- Game Boy games there is nothing to recolor: the extractor keeps every
-- picture as ready-made RGBA (pokemon/<kind>/<sp>.rgba under the engine's
-- Gen 3 cache root, shiny ones in <kind>_shiny/), palette applied and index
-- 0 transparent. Read where the engine says its cache is (its own
-- CachePaths.CACHE_ROOT, the root Gen3Compat's data.pokemon spriteFront /
-- spriteBack paths are built on; the mod names no location of its own),
-- and encoded once.
--
-- Same contract as sprites.lua: a function returns an id, the page asks
-- for /img/<id>.png. Only the functions the Gen 3 modules call exist here.
return function(mod, platform)
    local Pokemon = require("src.core.game3.pokemon")
    local CachePaths = require("src.core.game3.cache_paths")
    local okI, ItemsData = pcall(require, "src.core.game3.items_data")
    if not okI then ItemsData = nil end

    -- the engine's Gen 3 cache root (src/core/game3/cache_paths.lua)
    local function cacheRoot() return CachePaths.CACHE_ROOT end
    local ROOT = cacheRoot() .. "/pokemon/"
    local PIC = 64 -- front / back pics are 64x64 (8x8 tiles)

    local cache
    local function read(rel)
        if not cache then
            local ok, Dataset = pcall(require, "src.core.game3.dataset")
            cache = ok and Dataset.cache and Dataset.cache() or nil
            if not cache then return nil end
        end
        local ok, d = pcall(cache.read, cache, rel)
        return ok and type(d) == "string" and #d > 0 and d or nil
    end

    local entries = {} -- id -> { build = fn, png = string | false }

    -- stable ids across restarts (the browser caches images for a day)
    local function hashKey(key)
        local a, b = 0x811C9DC5, 5381
        for i = 1, #key do
            local c = key:byte(i)
            a = bit.tobit(bit.bxor(a, c) * 16777619)
            b = bit.tobit(b * 33 + c)
        end
        return bit.tohex(a) .. bit.tohex(b)
    end

    local ART_VERSION = "g3-4" -- bump when drawn images change (the page caches them for good)

    local function register(key, build)
        local id = hashKey(ART_VERSION .. "|" .. key)
        if not entries[id] then entries[id] = { build = build } end
        return id
    end

    local function imageData(rgba, w, h)
        if not rgba or #rgba < w * h * 4 then return nil end
        return love.image.newImageData(w, h, "rgba8", rgba:sub(1, w * h * 4))
    end

    local S = {}

    -- A mon's species as the game draws it: an egg's own art, Unown's letter
    local function picSpecies(mon)
        local ok, sp = pcall(Pokemon.monPicSpecies, mon)
        return ok and sp or nil
    end

    local function shiny(mon)
        local ok, s = pcall(Pokemon.isShiny, mon)
        return ok and s and not Pokemon.isEgg(mon)
    end

    -- the battle / summary front pic (Castform's normal form; Spinda's spots
    -- are the one per-mon picture and have no file, so it falls back to the
    -- plain species art)
    local function frontOf(sp, isShiny)
        local kind = isShiny and "front_shiny" or "front"
        local rel = ROOT .. kind .. "/" .. sp .. ".rgba"
        if not read(rel) and isShiny then rel = ROOT .. "front/" .. sp .. ".rgba" end
        return register("front|" .. rel, function()
            return imageData(read(rel), PIC, PIC)
        end)
    end

    function S.front(_, mon)
        local sp = picSpecies(mon)
        if not sp then return nil end
        return frontOf(sp, shiny(mon))
    end

    -- the POKéDEX entry's picture: a species, never shiny
    function S.frontSpecies(_, species)
        local sp = tonumber(species)
        if not sp then return nil end
        return frontOf(sp, false)
    end

    -- the party menu icon: a 32x64 sheet of two 32x32 frames, the shape the
    -- page's .icon flip animation expects
    local function iconOf(sp)
        local rel = ROOT .. "icons/" .. sp .. ".rgba"
        return register("icon|" .. rel, function()
            local rgba = read(rel)
            if not rgba then return nil end
            local h = #rgba >= 32 * 64 * 4 and 64 or 32
            return imageData(rgba, 32, h)
        end)
    end

    function S.icon(_, mon)
        local sp = picSpecies(mon)
        if not sp then return nil end
        return iconOf(sp)
    end

    function S.iconSpecies(_, species)
        local sp = tonumber(species)
        if not sp then return nil end
        return iconOf(sp)
    end

    -- A w x h cell of a sheet as its own picture
    local function crop(rgba, sheetW, sheetH, x, y, w, h)
        local sheet = imageData(rgba, sheetW, sheetH)
        if not sheet then return nil end
        local out = love.image.newImageData(w, h)
        out:paste(sheet, 0, 0, x, y, w, h)
        return out
    end

    -- The summary screen's type badges: 32x12 cells of its 128x128
    -- menu_info sheet (src/ui/game3/summary_chrome.lua TYPE_RECTS)
    local TYPE_CELLS = {
        [0] = { 0, 16 }, [1] = { 32, 48 }, [2] = { 0, 48 }, [3] = { 0, 64 }, [4] = { 64, 32 },
        [5] = { 32, 32 }, [6] = { 96, 48 }, [7] = { 64, 48 }, [8] = { 64, 64 }, [9] = { 32, 80 },
        [10] = { 32, 16 }, [11] = { 64, 16 }, [12] = { 96, 16 }, [13] = { 0, 32 }, [14] = { 32, 64 },
        [15] = { 96, 32 }, [16] = { 0, 80 }, [17] = { 96, 64 },
    }

    function S.typeBadge(typeId)
        local cell = TYPE_CELLS[tonumber(typeId) or -1]
        if not cell then return nil end
        local rel = ROOT .. "summary/menu_info.rgba"
        return register("type|" .. rel .. "|" .. typeId, function()
            return crop(read(rel), 128, 128, cell[1], cell[2], 32, 12)
        end)
    end

    -- The POKé BALL a mon was caught in, as the summary screen shows it
    -- (pokemon_summary_screen.c:4108): the first 16x16 frame of that
    -- ball's column in the battle's ball sheet
    function S.ball(mon)
        local okB, BallOpen = pcall(require, "src.core.game3.battle.ball_open")
        if not okB then return nil end
        local id = Pokemon.isEgg(mon) and 0 or (BallOpen.ballIdForItem(mon.pokeball) or 0)
        local d = BallOpen.data and BallOpen.data() or {}
        local w, h = d.ballSheetW or 192, d.ballSheetH or 48
        local rel = ROOT .. "battle/ball_open/" .. (d.ballSheet or "balls.rgba")
        return register("ball|" .. rel .. "|" .. id, function()
            return crop(read(rel), w, h, id * 16, 0, 16, 16)
        end)
    end

    -- The trainer's party lineup balls (pokefirered battle_interface.c
    -- party summary): 8x8 tiles of the battle's 320x24 elements sheet,
    -- laid out as the page's ball frames: healthy, status, fainted, empty
    -- (src/ui/game3/battle_chrome.lua PARTY_BALL_TILE: ok 66, empty 67,
    -- status 68, faint 69)
    local BALL_TILES = { 66, 68, 69, 67 }
    function S.balls()
        local rel = ROOT .. "battle/elements.rgba"
        return register("balls|" .. rel, function()
            local sheet = imageData(read(rel), 320, 24)
            if not sheet then return nil end
            local out = love.image.newImageData(32, 8)
            for i, tile in ipairs(BALL_TILES) do
                out:paste(sheet, (i - 1) * 8, 0, (tile % 40) * 8, math.floor(tile / 40) * 8, 8, 8)
            end
            return out
        end)
    end

    -- A PC box's header: the capsule at the top of its wallpaper, behind the
    -- box name (pokefirered pokemon_storage_system.c; the game draws the
    -- 160x144 wallpaper under the name and arrows, src/ui/game3/
    -- pc_chrome.lua). Wallpaper ids are 1-based in storage.lua, named by the
    -- storage manifest's wallpaperOrder. The capsule is found, not assumed:
    -- the box around the top rows' pixels that differ from the plain
    -- background colour in the corner.
    local STORAGE = cacheRoot() .. "/pokemon/storage/"
    -- pret's order (pokemon_storage_system.c), for when neither the manifest
    -- nor the engine says otherwise
    local WALLPAPER_ORDER = { "forest", "city", "desert", "savanna", "crag", "volcano", "snow", "cave",
        "beach", "seafloor", "river", "sky", "stars", "pokecenter", "tiles", "simple" }
    local wallpaperNames
    local function wallpaperName(id)
        if wallpaperNames == nil then
            -- the engine's own list first (PcChrome.wallpaperNames: the
            -- manifest's wallpaperOrder when the extract has one, else its
            -- built-in order), then the manifest, then pret's order
            local okP, PcChrome = pcall(require, "src.ui.game3.pc_chrome")
            if okP and type(PcChrome) == "table" and PcChrome.wallpaperNames then
                local ok, names = pcall(PcChrome.wallpaperNames)
                if ok and type(names) == "table" and #names > 0 then wallpaperNames = names end
            end
            if not wallpaperNames then
                local src = read(STORAGE .. "manifest.lua")
                local chunk = src and load(src, "=storage manifest", "t", {})
                local ok, m = false, nil
                if chunk then ok, m = pcall(chunk) end
                if ok and type(m) == "table" and type(m.wallpaperOrder) == "table" then
                    wallpaperNames = m.wallpaperOrder
                end
            end
            wallpaperNames = wallpaperNames or WALLPAPER_ORDER
        end
        return wallpaperNames[tonumber(id) or 0]
    end

    local function pngData(rel)
        local okA, Assets = pcall(require, "src.render.Assets")
        if okA and Assets and Assets.imageData then
            local root = cacheRoot() .. "/"
            local bare = rel:sub(1, #root) == root and rel:sub(#root + 1) or rel
            for _, path in ipairs({ rel, bare }) do
                local ok, img = pcall(Assets.imageData, path)
                if ok and img then return img end
            end
        end
        local bytes = read(rel)
        if not (bytes and love.data and love.data.newByteData) then return nil end
        local ok, img = pcall(function()
            return love.image.newImageData(love.data.newByteData(bytes))
        end)
        return ok and img or nil
    end

    -- the capsule sits in the wallpaper's top rows (1-22); the box's own
    -- frame starts at row 26, so the search stops before it
    local HEADER_ROWS = 24
    local headerIds = {}
    function S.boxHeader(wallpaperId)
        local name = wallpaperName(wallpaperId)
        if not name then return nil end
        if headerIds[name] ~= nil then return headerIds[name] or nil end
        local rel = STORAGE .. "wallpapers/" .. name .. ".png"
        if not read(rel) then
            headerIds[name] = false
            return nil
        end
        headerIds[name] = register("boxheader|" .. rel, function()
            local img = pngData(rel)
            if not img then return nil end
            local w, h = img:getDimensions()
            local br, bg, bb = img:getPixel(0, 0)
            local function differs(x, y)
                local r, g, b = img:getPixel(x, y)
                return math.abs(r - br) + math.abs(g - bg) + math.abs(b - bb) > 0.02
            end
            local x0, y0, x1, y1 = w, h, -1, -1
            for y = 0, math.min(HEADER_ROWS, h) - 1 do
                for x = 0, w - 1 do
                    if differs(x, y) then
                        if x < x0 then x0 = x end
                        if y < y0 then y0 = y end
                        if x > x1 then x1 = x end
                        if y > y1 then y1 = y end
                    end
                end
            end
            if x1 < x0 or y1 < y0 then return nil end
            local out = love.image.newImageData(x1 - x0 + 1, y1 - y0 + 1)
            out:paste(img, 0, 0, x0, y0, x1 - x0 + 1, y1 - y0 + 1)
            return out
        end)
        return headerIds[name]
    end

    -- The party menu's held-item marker, as Gen 2's sprites.held gives it:
    -- pokemon/party/hold_icons.rgba, 8x16, the item marker on top and the
    -- MAIL one below (src/ui/game3/party_menu.lua heldItemSheet / Frame)
    local HOLD_ICONS = cacheRoot() .. "/pokemon/party/hold_icons.rgba"
    local heldIds = {}
    function S.held(_, mon)
        local raw = mon and (mon.item or mon.heldItem)
        local item = tonumber(raw)
        if not item and raw ~= nil and ItemsData then
            local ok, v = pcall(ItemsData.toNumericId, raw)
            item = ok and tonumber(v) or nil
        end
        if not item or item == 0 then return nil end
        local okM, Mail = pcall(require, "src.core.game3.mail")
        local frame = okM and Mail.isMailItem and Mail.isMailItem(item) and 1 or 0
        if heldIds[frame] ~= nil then return heldIds[frame] or nil end
        if not read(HOLD_ICONS) then
            heldIds[frame] = false
            return nil
        end
        heldIds[frame] = register("held|" .. HOLD_ICONS .. "|" .. frame, function()
            local sheet = imageData(read(HOLD_ICONS), 8, 16)
            if not sheet then return nil end
            local out = love.image.newImageData(8, 8)
            out:paste(sheet, 0, 0, 0, frame * 8, 8, 8)
            return out
        end)
        return heldIds[frame]
    end

    -- The PC's box arrows (◀ ▶ beside the box name): box_scroll_arrow.png,
    -- 8x32, the left arrow's 8x16 frame on top, the right one below it
    -- (src/ui/game3/pc_chrome.lua drawInterfaceFrame)
    local arrowIds = {}
    function S.boxArrow(dir)
        local row = dir == "left" and 0 or dir == "right" and 16 or nil
        if not row then return nil end
        if arrowIds[dir] ~= nil then return arrowIds[dir] or nil end
        local rel = STORAGE .. "box_scroll_arrow.png"
        if not read(rel) then
            arrowIds[dir] = false
            return nil
        end
        arrowIds[dir] = register("boxarrow|" .. rel .. "|" .. dir, function()
            local img = pngData(rel)
            if not img then return nil end
            local out = love.image.newImageData(8, 16)
            out:paste(img, 0, 0, 0, row, 8, 16)
            return out
        end)
        return arrowIds[dir]
    end

    -- The POKéDEX AREA map: the sepia Kanto map and the Sevii Islands' maps
    -- on one canvas, with a red marker on every area the species lives in,
    -- composed the way the game draws its area page (src/ui/game3/
    -- pokedex.lua, pokefirered pokedex_area_markers.c). The canvas is 128 x
    -- 104: Kanto (96 x 72) at x 32, One to Three Island (32 x 24) down the
    -- left, Four to Seven Island (32 x 32) along the bottom; area_markers
    -- gives each area's marker (its top left and one of seven shapes) in
    -- those coordinates. A marker is the GBA's alpha blend: the marker colour
    -- at eva/16 over the map at evb/16 (chrome.lua marker / marker_blend).
    -- Islands the game hasn't shown yet are left off (show123 / show4567),
    -- down to the Kanto map alone. No area at all: the bare map (the page
    -- lays its own AREA UNKNOWN box over it, in place of the POKéDEX's
    -- wide ellipse). Returns the image id and its width, height.
    local DEX = ROOT .. "pokedex/"
    local ISLANDS = {
        one_island = { 0, 0, 32, 24, "123" }, two_island = { 0, 24, 32, 24, "123" },
        three_island = { 0, 48, 32, 24, "123" },
        four_island = { 0, 72, 32, 32, "4567" }, five_island = { 32, 72, 32, 32, "4567" },
        six_island = { 64, 72, 32, 32, "4567" }, seven_island = { 96, 72, 32, 32, "4567" },
    }
    local MARKER_FILES = {
        MARKER_CIRCULAR = { "marker_0", 8, 8 }, MARKER_SMALL_H = { "marker_1", 16, 8 },
        MARKER_SMALL_V = { "marker_2", 8, 16 }, MARKER_MED_H = { "marker_3", 32, 16 },
        MARKER_MED_V = { "marker_4", 16, 32 }, MARKER_LARGE_H = { "marker_5", 32, 16 },
        MARKER_LARGE_V = { "marker_6", 16, 32 },
    }
    local dexColors
    local function markerColors()
        if dexColors == nil then
            dexColors = false
            local src = read(DEX .. "chrome.lua")
            local chunk = src and load(src, "=pokedex chrome", "t", {})
            local ok, t = false, nil
            if chunk then ok, t = pcall(chunk) end
            local c = ok and type(t) == "table" and (t.colors or t) or {}
            if type(c.marker) == "table" and type(c.marker_blend) == "table" then
                dexColors = { c.marker[1] / 255, c.marker[2] / 255, c.marker[3] / 255,
                    c.marker_blend[1] / 16, c.marker_blend[2] / 16 }
            end
        end
        -- pret's values when the extract has none
        return dexColors or { 206 / 255, 66 / 255, 58 / 255, 12 / 16, 8 / 16 }
    end

    -- extraAreas: more area keys to mark (the roaming legendary's route)
    function S.areaMap(species, show123, show4567, extraAreas)
        local sp = tonumber(species)
        local okD, PD = pcall(require, "src.core.game3.pokedex_data")
        if not (sp and okD and PD.getWildAreasForSpecies) then return nil end
        -- the canvas: Kanto alone, or with the island columns / row shown
        local width = (show123 or show4567) and 128 or 96
        local height = show4567 and 104 or 72
        local ox = width == 128 and 0 or -32 -- layout x -> canvas x
        local shown = {}
        local marks = {}
        local keys, seenKey = {}, {}
        for _, list in ipairs({ PD.getWildAreasForSpecies(sp) or {}, extraAreas or {} }) do
            for _, key in ipairs(list) do
                if not seenKey[key] then seenKey[key] = true; keys[#keys + 1] = key end
            end
        end
        for _, key in ipairs(keys) do
            local mapKey = PD.getAreaMapKey and PD.getAreaMapKey(key) or "kanto"
            local island = ISLANDS[mapKey]
            local visible = not island or (island[5] == "123" and show123) or (island[5] == "4567" and show4567)
            local m = PD.getAreaMarker and PD.getAreaMarker(key)
            if visible and type(m) == "table" and MARKER_FILES[m.shape] then
                marks[#marks + 1] = m
                shown[#shown + 1] = key
            end
        end
        table.sort(shown)
        local key = ("areamap|%d|%s%s|%s"):format(sp, show123 and "a" or "", show4567 and "b" or "",
            table.concat(shown, ","))
        local id = register(key, function()
            local out = love.image.newImageData(width, height)
            local function place(file, x, y, w, h)
                local img = imageData(read(DEX .. file .. ".rgba"), w, h)
                if img then out:paste(img, x + ox, y, 0, 0, w, h) end
            end
            place("map_kanto", 32, 0, 96, 72)
            for name, box in pairs(ISLANDS) do
                if (box[5] == "123" and show123) or (box[5] == "4567" and show4567) then
                    place("map_" .. name, box[1], box[2], box[3], box[4])
                end
            end
            local c = markerColors()
            local cr, cg, cb, eva, evb = c[1], c[2], c[3], c[4], c[5]
            for _, m in ipairs(marks) do
                local f = MARKER_FILES[m.shape]
                local mask = imageData(read(DEX .. f[1] .. ".rgba"), f[2], f[3])
                if mask then
                    for py = 0, f[3] - 1 do
                        for px = 0, f[2] - 1 do
                            local _, _, _, a = mask:getPixel(px, py)
                            local x, y = m.x + ox + px, m.y + py
                            if a > 0.5 and x >= 0 and x < width and y >= 0 and y < height then
                                local dr, dg, db, da = out:getPixel(x, y)
                                out:setPixel(x, y, math.min(1, cr * eva + dr * evb), math.min(1, cg * eva + dg * evb),
                                    math.min(1, cb * eva + db * evb), math.max(da, 1))
                            end
                        end
                    end
                end
            end
            return out
        end)
        return id, width, height
    end

    -- An item's 24x24 BAG icon, as the bag menu draws it beside the list
    -- (src/ui/game3/bag_chrome.lua BagChrome.iconImage: items/bag/icons/<id>)
    local ITEM_ICONS = cacheRoot() .. "/items/bag/icons/"
    local itemIconIds = {} -- item number -> image id, false without an icon
    function S.itemIcon(id)
        local n = tonumber(id)
        if not n and ItemsData then
            local ok, v = pcall(ItemsData.toNumericId, id)
            n = ok and tonumber(v) or nil
        end
        if not n or n <= 0 then return nil end
        -- looked up once per item: the page asks on every poll
        if itemIconIds[n] ~= nil then return itemIconIds[n] or nil end
        local rel = ITEM_ICONS .. n .. ".rgba"
        if not read(rel) then
            itemIconIds[n] = false
            return nil
        end
        itemIconIds[n] = register("item|" .. rel, function()
            return imageData(read(rel), 24, 24)
        end)
        return itemIconIds[n]
    end

    -- ♂ / ♀ from the game's own font, as sprites.lua's glyphPath gives Gen
    -- 1 / 2's: an SVG path of 1x1 squares, one per ink pixel. FireRed's
    -- latin_normal sheet is 16 x 32 cells of 16x16, one per character code
    -- (src/ui/game3/frlg_font.lua); ♂ is 0xB5, ♀ 0xB6 (pret charmap). The
    -- glyph is cut to its own box, and its size comes along ({ d, w, h }),
    -- since it isn't the Game Boy's 8x8.
    local FONT_REL = cacheRoot() .. "/chrome/fonts/latin_normal_fg.rgba"
    local GLYPH_CODES = { ["♂"] = 0xB5, ["♀"] = 0xB6 }
    local glyphCache = {}
    function S.glyphPath(_, ch)
        local code = GLYPH_CODES[ch]
        if not code then return nil end
        if glyphCache[code] ~= nil then return glyphCache[code] or nil end
        glyphCache[code] = false
        local rgba = read(FONT_REL)
        if not rgba or #rgba < 256 * 512 * 4 then return nil end
        local cx, cy = (code % 16) * 16, math.floor(code / 16) * 16
        local function ink(x, y)
            local i = ((cy + y) * 256 + cx + x) * 4
            return rgba:byte(i + 4) > 127
        end
        local x0, y0, x1, y1 = 16, 16, -1, -1
        for y = 0, 15 do
            for x = 0, 15 do
                if ink(x, y) then
                    if x < x0 then x0 = x end
                    if y < y0 then y0 = y end
                    if x > x1 then x1 = x end
                    if y > y1 then y1 = y end
                end
            end
        end
        if x1 < 0 then return nil end
        local parts = {}
        for y = y0, y1 do
            for x = x0, x1 do
                if ink(x, y) then parts[#parts + 1] = ("M%d %dh1v1h-1z"):format(x - x0, y - y0) end
            end
        end
        glyphCache[code] = { d = table.concat(parts), w = x1 - x0 + 1, h = y1 - y0 + 1 }
        return glyphCache[code]
    end

    -- The TOWN MAP (region_map.c): one 240x160 picture per map (Kanto,
    -- the Sevii Islands 1-3, 4-5, 6-7), cut to the window the game shows
    -- it in (MAP_WINDOW 24,16 - 216,160: 192x144, square (x, y) at
    -- 8x + 8, 8y + 16). The CANCEL button the picture carries (square
    -- 21,13) is painted over with the sea's two stripes; Navel Rock and
    -- Birth Island stay covered until the game has shown them
    -- (bufferRegionMapBg's patches). Returns the image id, width, height.
    local REGION = cacheRoot() .. "/region_map/"
    local REGION_FILES = { [0] = "kanto_map", "sevii123_map", "sevii45_map", "sevii67_map" }
    S.REGION_W, S.REGION_H = 192, 144
    function S.regionMap(region, navelPatch, birthPatch)
        local file = REGION_FILES[tonumber(region) or 0]
        if not file then return nil end
        local key = ("regionmap|%s|%s%s"):format(file, navelPatch and "n" or "", birthPatch and "b" or "")
        return register(key, function()
            local full = imageData(read(REGION .. file .. ".rgba"), 240, 160)
            if not full then return nil end
            local out = love.image.newImageData(S.REGION_W, S.REGION_H)
            out:paste(full, 0, 0, 24, 16, S.REGION_W, S.REGION_H)
            -- the CANCEL button (240x160 pixels 197-210, 134-147); the sea
            -- stripes alternate by row (even rows as row 100, odd as 101)
            local seaA = { full:getPixel(210, 100) }
            local seaB = { full:getPixel(210, 101) }
            if seaA[4] > 0 and seaB[4] > 0 then
                for y = 132, 149 do
                    local c = y % 2 == 0 and seaA or seaB
                    for x = 196, 211 do out:setPixel(x - 24, y - 16, c[1], c[2], c[3], 1) end
                end
            end
            local function patchIn(name, x, y, w, h)
                local img = imageData(read(REGION .. name .. ".rgba"), w, h)
                if not img then return end
                for py = 0, h - 1 do
                    for px = 0, w - 1 do
                        local r, g, b, a = img:getPixel(px, py)
                        if a > 0 then out:setPixel(x - 24 + px, y - 16 + py, r, g, b, a) end
                    end
                end
            end
            if navelPatch then patchIn("navel_rock_patch", 104, 88, 24, 16) end
            if birthPatch then patchIn("birth_island_patch", 168, 128, 24, 24) end
            return out
        end), S.REGION_W, S.REGION_H
    end

    -- the TOWN MAP's player icon (RED or LEAF, 16x16)
    function S.regionPlayer(female)
        local name = female and "player_leaf" or "player_red"
        return register("regionplayer|" .. name, function()
            return imageData(read(REGION .. name .. ".rgba"), 16, 16)
        end)
    end

    ---- Emerald ("rse") -------------------------------------------------------
    -- Emerald runs on the same engine but keeps its menu art under rse/, in
    -- its own shapes; these replace the FireRed builders above when it runs.
    if platform and platform.isRse and platform.isRse() then
        local RSE = cacheRoot() .. "/rse/"

        -- the summary screen's type badges (pokemon_summary_screen.c, drawn
        -- by src/ui/game3/rse/summary_menu.lua drawTypeIcon): move_types.png,
        -- one 32x16 frame per type id, top to bottom; the badge itself is
        -- rows 1-14 of its frame (32x14, FireRed's are 32x12)
        local TYPE_FRAME_H, TYPE_ROWS = 16, 14
        function S.typeBadge(typeId)
            local n = tonumber(typeId)
            if not n or n < 0 or n > 17 then return nil end
            local rel = RSE .. "summary/move_types.png"
            return register("type|" .. rel .. "|" .. n, function()
                local sheet = pngData(rel)
                if not sheet then return nil end
                local out = love.image.newImageData(32, TYPE_ROWS)
                out:paste(sheet, 0, 0, 0, n * TYPE_FRAME_H + 1, 32, TYPE_ROWS)
                return out
            end)
        end

        -- the five contest categories' badges (COOL .. TOUGH), the same
        -- sheet's frames 18-22, after the 18 types: Emerald's own pictures
        -- for the CONDITION rows. cat: 0 COOL, 1 BEAUTY, 2 CUTE, 3 SMART, 4 TOUGH
        function S.categoryBadge(cat)
            local n = tonumber(cat)
            if not n or n < 0 or n > 4 then return nil end
            local rel = RSE .. "summary/move_types.png"
            return register("category|" .. rel .. "|" .. n, function()
                local sheet = pngData(rel)
                if not sheet then return nil end
                local out = love.image.newImageData(32, TYPE_ROWS)
                out:paste(sheet, 0, 0, 0, (18 + n) * TYPE_FRAME_H + 1, 32, TYPE_ROWS)
                return out
            end)
        end

        -- a ribbon's small picture (pokenav_ribbons_summary.c:1057, as
        -- src/ui/game3/rse/pokenav/ribbons_summary.lua draws it): a 16x16
        -- cell of rse/pokenav_cr/ribbons_small.png, column = its palette,
        -- row = its tile (the manifest's ribbonGfx)
        function S.ribbon(pal, tile)
            local p, t = tonumber(pal), tonumber(tile)
            if not (p and t) then return nil end
            local rel = RSE .. "pokenav_cr/ribbons_small.png"
            return register(("ribbon|%s|%d|%d"):format(rel, p, t), function()
                local sheet = pngData(rel)
                if not sheet then return nil end
                local out = love.image.newImageData(16, 16)
                out:paste(sheet, 0, 0, p * 16, t * 16, 16, 16)
                return out
            end)
        end

        -- the BAG's item icons (item_menu_icons.c, BagChrome.drawItemIcon):
        -- one 24-pixel-wide strip, 24x24 per item, indexed by the item's
        -- number; the manifest gives its size and count
        local BAG = RSE .. "bag/"
        local iconSheet = nil -- { rgba, w, h, count } | false
        local function sheetInfo()
            if iconSheet == nil then
                iconSheet = false
                local src = read(BAG .. "manifest.lua")
                local chunk = src and load(src, "=rse bag", "t", {})
                local ok, m = false, nil
                if chunk then ok, m = pcall(chunk) end
                local icons = ok and type(m) == "table" and m.icons
                if type(icons) == "table" and icons.count then
                    iconSheet = { rel = BAG .. "icons.rgba", w = tonumber(icons.w) or 24,
                        h = tonumber(icons.h) or 0, count = tonumber(icons.count) or 0 }
                end
            end
            return iconSheet or nil
        end
        local rseIconIds = {}
        function S.itemIcon(id)
            local n = tonumber(id)
            if not n and ItemsData then
                local ok, v = pcall(ItemsData.toNumericId, id)
                n = ok and tonumber(v) or nil
            end
            local info = sheetInfo()
            -- 0 is the empty slot; past the strip there is no icon of its own
            if not (n and info) or n <= 0 or n >= info.count then return nil end
            if rseIconIds[n] == nil then
                rseIconIds[n] = register("item|" .. info.rel .. "|" .. n, function()
                    local sheet = imageData(read(info.rel), info.w, info.h)
                    if not sheet then return nil end
                    local out = love.image.newImageData(24, 24)
                    out:paste(sheet, 0, 0, 0, n * 24, 24, 24)
                    return out
                end)
            end
            return rseIconIds[n]
        end

        -- Hoenn's map (pokeemerald region_map.c; drawn by src/ui/game3/rse/
        -- region_map.lua): the top-left 240x160 of rse/region_map/map.png,
        -- all of it map. Square (x, y) of its grid (RegionMap.mapSecAt,
        -- x 1-28, y 2-16) is the 8x8 block at (8x, 8y).
        local RMAP = RSE .. "region_map/"
        S.REGION_W, S.REGION_H = 240, 160
        local function hoennMap()
            local full = pngData(RMAP .. "map.png")
            if not full then return nil end
            local out = love.image.newImageData(S.REGION_W, S.REGION_H)
            out:paste(full, 0, 0, 0, 0, S.REGION_W, S.REGION_H)
            return out
        end
        function S.regionMap()
            return register("regionmap|" .. RMAP .. "map.png", hoennMap), S.REGION_W, S.REGION_H
        end
        -- the map's player icon (BRENDAN / MAY, 16x16)
        function S.regionPlayer(female)
            local rel = RMAP .. (female and "may_icon.png" or "brendan_icon.png")
            return register("regionplayer|" .. rel, function() return pngData(rel) end)
        end

        -- The POKéDEX AREA page on Hoenn's map. found is the game's own
        -- search (pokedex_area.lua Area.findMapsWithMon): overworld = the
        -- sections that glow (every square of the section washed red, with a
        -- dark red edge where the area ends: Hoenn's bright yellow routes
        -- swallow a lighter tint), special = the caves and such the game
        -- marks with a blinking dot (here a solid one in the section's
        -- middle). Returns the image id, width, height.
        local WASH, WASH_RGB, EDGE_RGB = .55, { 232 / 255, 40 / 255, 40 / 255 }, { 150 / 255, 20 / 255, 20 / 255 }
        function S.areaMapHoenn(found)
            local okR, RegionMap = pcall(require, "src.ui.game3.rse.region_map")
            local okM, Mapsec = pcall(require, "src.ui.game3.rse.mapsec")
            if not (okR and okM and type(found) == "table") then return nil end
            local glow, dots = {}, {}
            for _, o in ipairs(found.overworld or {}) do
                if tonumber(o.sec) then glow[#glow + 1] = tonumber(o.sec) end
            end
            for _, sec in ipairs(found.special or {}) do
                if tonumber(sec) then dots[#dots + 1] = tonumber(sec) end
            end
            table.sort(glow); table.sort(dots)
            local key = ("hoennarea|%s|%s"):format(table.concat(glow, ","), table.concat(dots, ","))
            return register(key, function()
                local out = hoennMap()
                if not out then return nil end
                local c = markerColors()
                local cr, cg, cb, eva, evb = c[1], c[2], c[3], c[4], c[5]
                local function put(px, py, rgb, a)
                    if px < 0 or py < 0 or px >= S.REGION_W or py >= S.REGION_H then return end
                    local dr, dg, db = out:getPixel(px, py)
                    out:setPixel(px, py, dr + (rgb[1] - dr) * a, dg + (rgb[2] - dg) * a, db + (rgb[3] - db) * a, 1)
                end
                local isGlow = {}
                for _, sec in ipairs(glow) do isGlow[sec] = true end
                local function lit(gx, gy)
                    local okS, sec = pcall(RegionMap.mapSecAt, gx, gy)
                    return okS and isGlow[sec] or false
                end
                for gy = RegionMap.CURSOR_Y_MIN, RegionMap.CURSOR_Y_MAX do
                    for gx = RegionMap.CURSOR_X_MIN, RegionMap.CURSOR_X_MAX do
                        if lit(gx, gy) then
                            local x0, y0 = gx * 8, gy * 8
                            for py = y0, y0 + 7 do
                                for px = x0, x0 + 7 do put(px, py, WASH_RGB, WASH) end
                            end
                            -- the edge, on each side the area ends
                            for k = 0, 7 do
                                if not lit(gx, gy - 1) then put(x0 + k, y0, EDGE_RGB, 1) end
                                if not lit(gx, gy + 1) then put(x0 + k, y0 + 7, EDGE_RGB, 1) end
                                if not lit(gx - 1, gy) then put(x0, y0 + k, EDGE_RGB, 1) end
                                if not lit(gx + 1, gy) then put(x0 + 7, y0 + k, EDGE_RGB, 1) end
                            end
                        end
                    end
                end
                -- a dot: a 6x6 disc in the marker colour with a dark rim
                for _, sec in ipairs(dots) do
                    local okE, e = pcall(Mapsec.entry, sec)
                    if okE and type(e) == "table" then
                        local cx = (e.x + RegionMap.CURSOR_X_MIN) * 8 + (e.width or 1) * 4
                        local cy = (e.y + RegionMap.CURSOR_Y_MIN) * 8 + (e.height or 1) * 4
                        for py = -4, 3 do
                            for px = -4, 3 do
                                local d = (px + .5) ^ 2 + (py + .5) ^ 2
                                local x, y = cx + px, cy + py
                                if x >= 0 and y >= 0 and x < S.REGION_W and y < S.REGION_H then
                                    if d <= 9 then out:setPixel(x, y, cr, cg, cb, 1)
                                    elseif d <= 16 then out:setPixel(x, y, .25, .08, .06, 1) end
                                end
                            end
                        end
                    end
                end
                return out
            end), S.REGION_W, S.REGION_H
        end
    end

    -- A gym badge's picture (16x16): Emerald's from its trainer card
    -- (rse/trainer_card/badges.png, the Hoenn eight side by side, in colour),
    -- FireRed's the Kanto eight its trainer card draws
    -- (trainer_card/badges.rgba, 128x16, as src/ui/game3/trainer_card.lua
    -- shows them)
    function S.badge(k)
        k = tonumber(k)
        if not k or k < 1 or k > 8 then return nil end
        local root = cacheRoot()
        if platform and platform.isRse and platform.isRse() then
            local rel = root .. "/rse/trainer_card/badges.png"
            return register("badge|" .. rel .. "|" .. k, function()
                local sheet = pngData(rel)
                if not sheet then return nil end
                local out = love.image.newImageData(16, 16)
                out:paste(sheet, 0, 0, (k - 1) * 16, 0, 16, 16)
                return out
            end)
        end
        local rel = root .. "/trainer_card/badges.rgba"
        return register("badge|" .. rel .. "|" .. k, function()
            local sheet = imageData(read(rel), 128, 16)
            if not sheet then return nil end
            local out = love.image.newImageData(16, 16)
            out:paste(sheet, 0, 0, (k - 1) * 16, 0, 16, 16)
            return out
        end)
    end

    -- PNG bytes for an id, built on first request; nil when unknown or broken
    function S.png(id)
        local entry = entries[id]
        if not entry then return nil end
        if entry.png == nil then
            local ok, result = pcall(function()
                local img = entry.build()
                return img and img:encode("png"):getString() or false
            end)
            if not ok then mod.log:warn("sprite %s failed: %s", id, tostring(result)) end
            entry.png = ok and result or false
        end
        return entry.png or nil
    end

    -- A battle's scenery (pokemon/battle/terrain_bg_<key>.rgba, 256x160,
    -- the sky and ground the battle draws without its two ground patches),
    -- for the HANDS-OFF backdrop: the 240 columns the screen shows, above
    -- the 48 black rows the text box covers, so 240x112
    function S.battleScene(key)
        key = tostring(key or "")
        if not key:match("^[%w_]+$") then return nil end
        local rel = cacheRoot() .. "/pokemon/battle/terrain_bg_" .. key .. ".rgba"
        if not read(rel) then return nil end
        return register("scene|" .. rel, function()
            return crop(read(rel), 256, 160, 0, 0, 240, 112)
        end)
    end

    -- A trainer's front pic in battle (src/core/game3/trainer_pic.lua:
    -- trainers/front/<picId>.rgba, 64x64), by the battle's trainerPicId
    function S.trainer(_, picId)
        picId = tonumber(picId)
        if not picId or picId < 0 then return nil end
        local rel = cacheRoot() .. "/trainers/front/" .. picId .. ".rgba"
        if not read(rel) then return nil end
        return register("trainer|" .. rel, function()
            return imageData(read(rel), 64, 64)
        end)
    end

    -- The party menu's status labels (pokemon/party/status_icons.rgba:
    -- 32x64, eight 32x8 rows in PartyChrome.statusFrameFor's order). Each
    -- label is drawn in columns 5-26 of its row: cut to that, 22x8.
    local STATUS_ROWS = { PSN = 0, PAR = 1, SLP = 2, FRZ = 3, BRN = 4, PKRS = 5, FNT = 6 }
    local STATUS_SHEET = cacheRoot() .. "/pokemon/party/status_icons.rgba"
    function S.statusIcon(code)
        local row = STATUS_ROWS[code]
        if not row or not read(STATUS_SHEET) then return nil end
        return register("status|" .. STATUS_SHEET .. "|" .. code, function()
            return crop(read(STATUS_SHEET), 32, 64, 5, row * 8, 22, 8)
        end)
    end

    -- FireRed's location preview artwork (map_preview_screen.c, baked by
    -- map_preview_extract.lua: map_preview/<artwork>.rgba, 240x160), for
    -- the HANDS-OFF backdrop. The artwork is letterboxed: 24 black rows at
    -- the top (the blank name window the preview prints the place's name
    -- into sits in them) and 24 at the bottom. Both cut, so 240x112 remain.
    local PREVIEW_W, PREVIEW_H, PREVIEW_CUT, PREVIEW_CUT_BOTTOM = 240, 160, 24, 24
    function S.mapPreview(artwork)
        artwork = tonumber(artwork)
        if not artwork then return nil end
        local rel = cacheRoot() .. "/map_preview/" .. artwork .. ".rgba"
        if not read(rel) then return nil end
        return register("preview|" .. rel, function()
            local rgba = read(rel)
            if not rgba or #rgba < PREVIEW_W * PREVIEW_H * 4 then return nil end
            local h = PREVIEW_H - PREVIEW_CUT - PREVIEW_CUT_BOTTOM
            local skip = PREVIEW_W * PREVIEW_CUT * 4
            return imageData(rgba:sub(skip + 1, skip + PREVIEW_W * h * 4), PREVIEW_W, h)
        end)
    end

    return S
end
