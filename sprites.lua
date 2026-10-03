-- Party art for the phone page as PNGs. The game keeps its art as DMG
-- grays and colors whole screen regions with a shader at present time, so
-- a canvas grab would come out gray; instead the gray art is remapped here
-- with the same red-channel thresholds and the current display palette.
--
-- Each distinct (art path, palette) pair gets a hashed id, and the page
-- asks for /img/<id>.png: the id changes whenever the art or palette does,
-- so the browser may cache every image.
--
-- Gen 2 (Gold) art is the same 4-shade grayscale, colored per species / per
-- screen with GBC palettes (src/world/gen2/Palettes.lua); its branch sits
-- at the end and replaces the Gen 1 functions when Gold runs.
return function(mod, platform)
    local Sprites = require("src.pokemon.Sprites")
    local Assets = require("src.render.Assets")
    local PaletteFX = require("src.render.PaletteFX")
    local gen2 = platform and platform.isGen2()
    -- Gen 1's party menu knows the icon frames and mirrored halves; Gold's
    -- icons are plain two-frame sheets and need neither
    local PartyMenu = not gen2 and require("src.ui.PartyMenu") or {}
    -- Gen 1's battle screen, required only where Gen 1 art is drawn
    local GEN1_BATTLE_STATE = "src.battle.BattleState"

    local GRAYS = { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 }, { 0, 0, 0 } }

    local entries = {} -- id -> { build = fn, gray = fn | nil, png = string | false, grayPng = ... }

    -- Ids are hashes of the key rather than counters so they stay stable
    -- across game restarts: the browser caches images for a day, and a
    -- reused counter would show last session's sprite for a different mon.
    local function hashKey(key)
        local a, b = 0x811C9DC5, 5381 -- FNV-1a and djb2, 64 bits combined
        for i = 1, #key do
            local c = key:byte(i)
            a = bit.tobit(bit.bxor(a, c) * 16777619)
            b = bit.tobit(b * 33 + c)
        end
        return bit.tohex(a) .. bit.tohex(b)
    end

    -- Part of every id: bump it whenever the way art is drawn changes, or
    -- browsers keep showing their day-long cached copies of the old look
    -- (same art + same palette would otherwise mean the same id).
    local ART_VERSION = "4"

    -- gray: optional builder of the same art in the plain 4 gray shades,
    -- for a skin that puts pictures through its own palette (?gray=1)
    local function register(key, build, gray)
        local id = hashKey(ART_VERSION .. "|" .. key)
        if not entries[id] then entries[id] = { build = build, gray = gray } end
        return id
    end

    local function colorsKey(colors)
        if not colors then return "raw" end
        local parts = {}
        for i = 1, 4 do
            local c = colors[i] or {}
            parts[i] = ("%d,%d,%d"):format(c[1] or 0, c[2] or 0, c[3] or 0)
        end
        return table.concat(parts, ";")
    end

    -- PaletteFX's shade-remap shader thresholds, lightest shade first;
    -- shade 0 is the Game Boy's "transparent white" and becomes alpha 0 so
    -- the art sits on whatever the page draws behind it
    local function recolor(img, colors)
        img:mapPixel(function(_, _, r, _, _, a)
            if a == 0 or r > 0.83 then return 0, 0, 0, 0 end
            local c = r > 0.5 and colors[2] or (r > 0.17 and colors[3] or colors[4])
            return c[1] / 255, c[2] / 255, c[3] / 255, a
        end)
    end

    -- Game Boy art is 4-shade grayscale and gets colored by a palette. Art a
    -- mod ships already in color (e.g. unique_menu_icons' GBC RED / UNIQUE
    -- COLORS modes, which the game shows unshaded) must be used as drawn.
    local function isGray(img)
        local w, h = img:getDimensions()
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local r, g, b, a = img:getPixel(x, y)
                if a > 0 and (math.abs(r - g) > 0.02 or math.abs(g - b) > 0.02) then return false end
            end
        end
        return true
    end

    local function effective(colors)
        return PaletteFX.effectiveColors(colors) or GRAYS
    end

    -- small pics sit in the 7x7-tile frame the way the game places them:
    -- centered by whole tiles, bottom-aligned
    local function framed(img)
        local w, h = img:getDimensions()
        if w > 56 or h > 56 or (w == 56 and h == 56) then return img end
        local out = love.image.newImageData(56, 56)
        local ox = math.floor((8 - math.ceil(w / 8)) / 2) * 8
        out:paste(img, ox, 56 - h, 0, 0, w, h)
        return out
    end

    -- a front / trainer picture: in `colors`, and (Game Boy art only, not
    -- a mod's true-colour art) also in the plain gray shades
    local function picture(key, path, colors)
        return register(key, function()
            local img = framed(Assets.imageData(path))
            if colors then recolor(img, colors) end
            return img
        end, colors and function()
            local img = framed(Assets.imageData(path))
            recolor(img, GRAYS)
            return img
        end or nil)
    end

    local S = {}

    -- the battle/summary front pic, colored with the species' palette
    function S.front(data, mon)
        local path, trueColor = Sprites.path(data, mon.species, "front", { mon = mon, kind = "summary" })
        if not path then return nil end
        local colors = not trueColor and effective(PaletteFX.monPal(data, mon.species)) or nil
        return picture("front|" .. path .. "|" .. colorsKey(colors), path, colors)
    end


    -- Same icon choice as PartyMenu.drawIcon: per-species override, then the
    -- pokemon record's icon, then the dex default, then the pokemon.icon hook.
    local function iconSource(data, mon)
        local icons = data.icons
        if not icons then return nil end
        local def = data.pokemon[mon.species]
        local entry = (icons.bySpecies and icons.bySpecies[mon.species]) or (def and def.icon)
        local name, path, trueColor
        if type(entry) == "string" then
            name = entry
            path = icons.icons and icons.icons[entry]
        elseif type(entry) == "table" then
            path = entry.image
            trueColor = entry.trueColor
        end
        if not path then
            name = def and def.dex and icons.byDex and icons.byDex[def.dex]
            path = name and icons.icons and icons.icons[name]
        end
        path, trueColor = Sprites.iconPath(data, mon, path, { name = name, trueColor = trueColor })
        return path, name, trueColor
    end

    -- The colors built-in icons are drawn in right now: changes when the
    -- player picks another palette, so cached icon lists know to refresh.
    function S.iconLook(data)
        return colorsKey(effective(PaletteFX.pal(data, "MEWMON")))
    end

    -- A 16x32 sheet: the resting frame on top, the animation frame below.
    function S.icon(data, mon)
        local path, name, trueColor = iconSource(data, mon)
        if not path then return nil end
        -- icons are OBJ art seen through OBP0 (see PartyMenu's obpIcon); the
        -- party screen colors them with its MEWMON zone, unless the art is
        -- marked trueColor or already in color (checked when built)
        local colors = not trueColor and effective(PaletteFX.pal(data, "MEWMON")) or nil
        local key = "icon|" .. path .. "|" .. tostring(name) .. "|" .. colorsKey(colors)
        return register(key, function()
            local src = Assets.imageData(path)
            local iw, ih = src:getDimensions()
            local out = love.image.newImageData(16, 32)
            local mirrored = PartyMenu.mirrorsIcon(name)

            local function copy(sx, sy, dx, dy)
                if sx < iw and sy < ih and dy >= 0 and dy < 32 then
                    out:setPixel(dx, dy, src:getPixel(sx, sy))
                end
            end
            local function blit(frame, top, shift)
                for y = 0, 15 - shift do
                    local sy = frame * 16 + y
                    local dy = top + y + shift
                    if mirrored then
                        for x = 0, 7 do
                            copy(x, sy, x, dy)
                            copy(x, sy, 15 - x, dy)
                        end
                    else
                        for x = 0, 15 do copy(x, sy, x, dy) end
                    end
                end
            end

            local rest = ih > 16 and PartyMenu.frameFor(name, false, ih) or 0
            local alt = ih > 16 and PartyMenu.frameFor(name, true, ih) or 0
            blit(rest, 0, 0)
            if name == "BALL" or name == "HELIX" then
                blit(rest, 16, 1) -- these bob a pixel instead of switching frames
            else
                blit(alt, 16, 0)
            end

            -- a mod's own image (a table entry, no icon name) skips the OBP0
            -- bake but is still shaded by the screen zone (PartyMenu drawIcon)
            if colors and name == nil and isGray(out) then
                recolor(out, colors)
            elseif colors and isGray(out) then
                -- OBP0 "3100": colors 0/1 -> shade 0, 2 -> shade 1, 3 -> shade 3
                out:mapPixel(function(_, _, r, _, _, a)
                    if a == 0 or r > 0.5 then return 0, 0, 0, 0 end
                    local c = r > 0.17 and colors[2] or colors[4]
                    return c[1] / 255, c[2] / 255, c[3] / 255, a
                end)
            end
            return out
        end)
    end

    -- The battle's party-ball sheet (SetupPokeballs tiles): four 8x8 frames,
    -- healthy / status / fainted / empty. transforms.lua copies it out of the
    -- player's cache; until that has run the page draws plain balls instead.
    local BALLS = "save/mod-derived/" .. (mod.id or "second_screen_companion") .. "/companion/balls.png"
    function S.balls(data)
        if not Assets.exists(BALLS) then return nil end
        local colors = effective(PaletteFX.pal(data, "MEWMON"))
        -- gray: the plain shades too, for a skin's sprite palette (?gray=1)
        local function build(pal)
            return function()
                local img = Assets.imageData(BALLS)
                recolor(img, pal)
                return img
            end
        end
        return register("balls|" .. BALLS .. "|" .. colorsKey(colors), build(colors), build(GRAYS))
    end

    -- The opponent's battle pic, resolved and colored the way the battle
    -- intro does it (BattleState.trainerPicPath / trainerPalette).
    function S.trainer(data, battle)
        -- Gen 1's battle screen only: on Gold this function is replaced by
        -- the Gen 2 one below and never runs
        local BattleState = require(GEN1_BATTLE_STATE)
        local trainer = battle.trainer
        local path = BattleState.trainerPicPath(data, trainer, battle.oppClass, battle.partyIndex)
        if not path then return nil end
        local colors
        if not BattleState.trainerTrueColor(data, trainer) then
            local pal = BattleState.trainerPalette(data, trainer)
            colors = effective(pal and pal.colors)
        end
        return picture("trainer|" .. path .. "|" .. colorsKey(colors), path, colors)
    end

    -- The Kanto TOWN MAP the Pokédex AREA screen draws (TownMap's
    -- loadBackground: a 20x18 tilemap of 8x8 tiles), in the TOWNMAP palette
    -- zone. Unlike sprites, shade 0 stays opaque: it is the map's paper.
    -- Row 0 is the AREA screen's name strip, empty on the page (which draws
    -- its own title): cropped off, so the map is 160x136 and starts
    -- TOWN_MAP_TOP pixels below the screen's top.
    S.TOWN_MAP_TOP, S.TOWN_MAP_H = 8, 136
    function S.townMap(data)
        local tm = data.field and data.field.townMap or {}
        local bg = tm.background
        if not (bg and bg.map and bg.tiles and bg.tiles.path) then return nil end
        local colors = effective(PaletteFX.pal(data, "TOWNMAP"))
        return register("townmap|" .. bg.tiles.path .. "|" .. #bg.map .. "|" .. colorsKey(colors), function()
            local tiles = Assets.imageData(bg.tiles.path)
            local per = math.floor(tiles:getWidth() / 8)
            local out = love.image.newImageData(160, S.TOWN_MAP_H)
            for i, t in ipairs(bg.map) do
                local col, row = (i - 1) % 20, math.floor((i - 1) / 20)
                if row >= 1 and row < 18 then
                    out:paste(tiles, col * 8, row * 8 - S.TOWN_MAP_TOP, (t % per) * 8, math.floor(t / per) * 8, 8, 8)
                end
            end
            out:mapPixel(function(_, _, r, _, _, a)
                local c = r > 0.83 and colors[1] or r > 0.5 and colors[2] or r > 0.17 and colors[3] or colors[4]
                return c[1] / 255, c[2] / 255, c[3] / 255, 1
            end)
            return out
        end)
    end

    -- the blinking nest icon of the AREA screen, same palette zone
    function S.nest(data)
        local tm = data.field and data.field.townMap or {}
        local path = tm.nest and tm.nest.path
        if not (path and Assets.exists(path)) then return nil end
        local colors = effective(PaletteFX.pal(data, "TOWNMAP"))
        return register("nest|" .. path .. "|" .. colorsKey(colors), function()
            local img = Assets.imageData(path)
            recolor(img, colors)
            return img
        end)
    end

    ---- Gen 2 (Gold / Silver) ----------------------------------------------

    if gen2 then
        local GbcPalette = require("src.render.GbcPalette")
        local Palettes = require("src.world.gen2.Palettes")

        -- the COLOR option (GEN 2 / DMG / CLASSIC) applied to a palette,
        -- the way GbcPalette draws it on screen (CLASSIC is DMG shown through
        -- the green ramp)
        local function gbc(colors)
            local present = GbcPalette.presentColors and GbcPalette.presentColors()
            if present then return present end
            return (colors and GbcPalette.resolve(colors)) or GRAYS
        end

        -- 8x8 tile `index` of a sheet `wide` tiles across
        local function pasteTile(out, sheet, index, wide, dx, dy)
            out:paste(sheet, dx, dy, (index % wide) * 8, math.floor(index / wide) * 8, 8, 8)
        end

        -- SummaryMenu:picPath: the species' front pic (Unown in its own
        -- form) through the pokemon.sprite hook. Returns path, trueColor,
        -- the vanilla path and the Unown letter.
        local function frontPic(data, mon, kind)
            local def = data.pokemon[mon.species]
            local vanilla = def and def.spriteFront
            local letter
            local okU, Unown = pcall(require, "src.core.gen2.Unown")
            if okU and mon.species == Unown.SPECIES then
                letter = Unown.monLetter(mon)
                vanilla = Unown.formSprite(data.pokemon, letter) or vanilla
            end
            local path, trueColor = Sprites.pic(vanilla, { side = "front", kind = kind or "summary", mon = mon,
                data = data, species = mon.species, letter = letter, shiny = mon.shiny and true or false })
            return path, trueColor, vanilla, letter
        end

        local function monColors(data, mon)
            return gbc(Palettes.monColors(data.gen2Palettes, mon.species, mon.shiny))
        end

        -- the front pic in its normal / shiny colors
        function S.front(data, mon)
            local path, trueColor = frontPic(data, mon)
            if not path then return nil end
            local colors = not trueColor and monColors(data, mon) or nil
            return picture("front2|" .. path .. "|" .. colorsKey(colors), path, colors)
        end


        -- Crystal's animated front pic (def.anim; nil on Gold / Silver,
        -- whose caches have no anim row). The page plays it the way the
        -- summary screen does (SummaryMenu:startPicAnim, scene "menu"):
        --   strip   every frame of anim.sheet (base picture first), each
        --           framed like the static pic, stacked 56 px apart
        --   frames  { {frame, ticks}, ... } at 60 ticks a second, from
        --           running MonAnim over the scene once
        local okMA, MonAnimView = pcall(require, "src.render.MonAnimView")
        local okMR, MonAnim = pcall(require, "src.render.MonAnim")
        local anims = {} -- id -> { sheet, size, frames }
        local ANIM_MAX_TICKS = 1500

        local function animStrip(sheetPath, size, colors)
            local src = Assets.imageData(sheetPath)
            local count = math.max(1, math.floor(src:getHeight() / size))
            local out = love.image.newImageData(56, 56 * count)
            for i = 0, count - 1 do
                local frame = love.image.newImageData(size, size)
                frame:paste(src, 0, 0, 0, i * size, size, size)
                out:paste(framed(frame), 0, i * 56, 0, 0, 56, 56)
            end
            if colors then recolor(out, colors) end
            return out
        end

        local function animTimeline(anim)
            local runner = MonAnim.new(anim, "menu")
            if not runner then return nil end
            local frames = {}
            for _ = 1, ANIM_MAX_TICKS do
                runner:update()
                local f = math.max(0, runner:currentFrame() or 0)
                local last = frames[#frames]
                if last and last[1] == f then last[2] = last[2] + 1 else frames[#frames + 1] = { f, 1 } end
                if runner:finished() then break end
            end
            return frames
        end

        function S.frontAnim(data, mon)
            if not (okMA and okMR) then return nil end
            local def = data.pokemon and data.pokemon[mon.species]
            local anim = def and MonAnimView.animData(def, mon)
            if not (anim and anim.sheet and anim.tiles and anim.play) then return nil end
            local path, _, vanilla, letter = frontPic(data, mon)
            local sheet, trueColor = Sprites.pic(anim.sheet, { side = "front", kind = "summary_anim", mon = mon,
                data = data, species = mon.species, letter = letter, shiny = mon.shiny and true or false })
            if type(sheet) ~= "string" or sheet == "" then sheet = anim.sheet end
            -- a mod replaced the still picture but not its animation: stay still
            if MonAnimView.replaced(vanilla, path) and not MonAnimView.replaced(anim.sheet, sheet) then
                return nil
            end
            local colors = not trueColor and monColors(data, mon) or nil
            local key = "anim2|" .. sheet .. "|" .. colorsKey(colors)
            local id = hashKey(ART_VERSION .. "|" .. key)
            if anims[id] == nil then
                local size = anim.tiles * 8
                local frames = animTimeline(anim)
                if frames and #frames > 1 then
                    local stripId = register(key .. "|strip", function()
                        return animStrip(sheet, size, colors)
                    end, colors and function() return animStrip(sheet, size, GRAYS) end or nil)
                    anims[id] = { sheet = "/img/" .. stripId .. ".png", size = 56, frames = frames }
                else
                    anims[id] = false
                end
            end
            return anims[id] and id or nil
        end

        -- GET /anim/<id>: what S.frontAnim prepared
        function S.anim(id)
            return anims[id] or nil
        end

        local function partyColors(data)
            local pals = data.gen2Palettes and data.gen2Palettes.partyMenu
            return gbc(pals and pals[1])
        end

        function S.iconLook(data)
            return colorsKey(partyColors(data))
        end

        -- PartyMenu:iconFor: MonMenuIcons -> the ICON_* sheet (ICON_EGG for
        -- an egg), through the pokemon.icon hook; all icons share the party
        -- menu's OBJ palette
        function S.icon(data, mon)
            local icons = data.gen2Icons
            if not (icons and icons.icons) then return nil end
            local iconId = mon.isEgg and "ICON_EGG" or (icons.species and icons.species[mon.species])
            local entry = iconId and icons.icons[iconId]
            local path = Sprites.iconPath(data, mon, entry and entry.image, { name = iconId })
            if not path then return nil end
            local colors = partyColors(data)
            return register("icon2|" .. path .. "|" .. colorsKey(colors), function()
                local src = Assets.imageData(path)
                local out = love.image.newImageData(16, 32)
                local w, h = src:getDimensions()
                out:paste(src, 0, 0, 0, 0, math.min(w, 16), math.min(h, 32))
                if h <= 16 then out:paste(src, 0, 16, 0, 0, math.min(w, 16), h) end
                -- a mod's full-color icon is drawn unshaded in the game too
                if isGray(out) then recolor(out, colors) end
                return out
            end)
        end

        -- The party menu's held-item marker (PartyMenu.heldMarkerRow /
        -- heldMarkerImage): one 8x8 tile of the HeldItemIcons sheet, row 0
        -- MAIL and row 1 any other item, in the icons' party palette. nil
        -- for an empty hand or a cache without the sheet.
        function S.held(data, mon)
            local icons = data.gen2Icons
            local entry = icons and icons.heldItem
            if not (entry and entry.image) then return nil end
            local okP, PartyMenu = pcall(require, "src.ui.gen2.PartyMenu")
            local row = okP and PartyMenu.heldMarkerRow and PartyMenu.heldMarkerRow(mon)
            if not row then return nil end
            local colors = partyColors(data)
            return register("held2|" .. entry.image .. "|" .. row .. "|" .. colorsKey(colors), function()
                local src = Assets.imageData(entry.image)
                local out = love.image.newImageData(8, 8)
                out:paste(src, 0, 0, 0, row * 8, 8, 8)
                if isGray(out) then recolor(out, colors) end
                return out
            end)
        end

        -- BattleHud:drawBallRow: tiles ballsFirstTile.. = healthy, status,
        -- fainted, empty, in PAL_BATTLE_OB_YELLOW
        function S.balls(data)
            local hud = data.gen2MenuGfx and data.gen2MenuGfx.battleHud
            local path = hud and hud.balls
            if not (path and Assets.exists(path)) then return nil end
            local pals = data.gen2Palettes and data.gen2Palettes.battleObjects
            local colors = gbc(pals and pals.PAL_BATTLE_OB_YELLOW)
            -- gray: the plain shades too, for a skin's sprite palette (?gray=1)
            local function build(pal)
                return function()
                    local sheet = Assets.imageData(path)
                    local wide = math.max(1, math.floor(sheet:getWidth() / 8))
                    local out = love.image.newImageData(32, 8)
                    -- the sheet's first tile IS ballsFirstTile (BattleHud:drawTile)
                    for i = 0, 3 do pasteTile(out, sheet, i, wide, i * 8, 0) end
                    recolor(out, pal)
                    return out
                end
            end
            return register("balls2|" .. path .. "|" .. colorsKey(colors), build(colors), build(GRAYS))
        end

        -- BattleState.trainerArt + Palettes.trainerColors (the class row)
        function S.trainer(data, battle)
            local okB, BattleState = pcall(require, "src.ui.gen2.BattleState")
            local class = battle.trainerClass or battle.enemyTrainerClass
                or (battle.trainer and (battle.trainer.class or battle.trainer.classId))
            if not (okB and BattleState.trainerArt and class) then return nil end
            local path, trueColor = BattleState.trainerArt(data, class)
            if not path then return nil end
            local colors = not trueColor and gbc(Palettes.trainerColors(data.gen2Palettes, class)) or nil
            return picture("trainer2|" .. path .. "|" .. colorsKey(colors), path, colors)
        end

        -- The POKéGEAR region map the #DEX AREA page draws (PokedexMenu
        -- drawTilemap): 20x18 tiles of the pokegear sheet, each tile in its
        -- own palette (palMap; the font tiles from $60 in palette 1).
        -- The page draws its title outside the map, so row 0 (the title
        -- strip) is cropped off and row 1 gets the frame's top edge the #DEX
        -- draws over it (PokedexMenu drawAreaHeader: $06, $07 ... $07, $17):
        -- a 160x136 image, REGION_MAP_TOP pixels below the screen's top.
        S.REGION_MAP_TOP, S.REGION_MAP_H = 8, 136
        function S.regionMap(data, region)
            local pg = data.gen2MenuGfx and data.gen2MenuGfx.pokegear
            local cells = pg and pg.maps and pg.maps[region]
            if not (cells and pg.tiles and pg.palettes) then return nil end
            local pals, keyParts = {}, {}
            for i, p in ipairs(pg.palettes) do
                pals[i] = gbc(p)
                keyParts[i] = colorsKey(pals[i])
            end
            local wide = pg.tilesWide or 16
            return register("region|" .. region .. "|" .. pg.tiles .. "|" .. table.concat(keyParts, "/"), function()
                local sheet = Assets.imageData(pg.tiles)
                local out = love.image.newImageData(160, S.REGION_MAP_H)
                local function put(id, tx, ty)
                    local tile = love.image.newImageData(8, 8)
                    pasteTile(tile, sheet, id, wide, 0, 0)
                    -- palMap holds 1-based palette numbers
                    local colors = (id >= 0x60) and pals[1]
                        or pals[pg.palMap and pg.palMap[id + 1] or 1] or pals[1]
                    tile:mapPixel(function(_, _, r, _, _, a)
                        local c = r > 0.83 and colors[1] or r > 0.5 and colors[2]
                            or r > 0.17 and colors[3] or colors[4]
                        return c[1] / 255, c[2] / 255, c[3] / 255, 1
                    end)
                    out:paste(tile, tx * 8, ty * 8 - S.REGION_MAP_TOP, 0, 0, 8, 8)
                end
                local i = 1
                for ty = 0, 17 do
                    for tx = 0, 19 do
                        local id = cells[i]
                        i = i + 1
                        -- row 0 is the title strip, row 1 the frame's top edge
                        if id and ty > 1 then put(id, tx, ty) end
                    end
                end
                put(0x06, 0, 1)
                for tx = 1, 18 do put(0x07, tx, 1) end
                put(0x17, 19, 1)
                return out
            end)
        end

        -- the nest icon the AREA page blinks (the day OBJ palette)
        function S.nest(data)
            local pg = data.gen2MenuGfx and data.gen2MenuGfx.pokegear
            local path = pg and pg.nestIcon
            if not (path and Assets.exists(path)) then return nil end
            local okSet, set = pcall(Palettes.objectSet, data.gen2Palettes, "DAY")
            local colors = gbc(okSet and set and set[1] or (pg.palettes and pg.palettes[1]))
            return register("nest2|" .. path .. "|" .. colorsKey(colors), function()
                local img = Assets.imageData(path)
                recolor(img, colors)
                return img
            end)
        end
        S.townMap = nil
    end

    -- An 8x8 tile of a Game Boy sheet as an SVG path: one 1x1 square per
    -- dark pixel. nil when the tile is outside the sheet or empty.
    -- light: the ink is the light pixels (art stored inverted, like the
    -- footprints), not the dark ones
    local function tilePath(img, gx, gy, size, light)
        size = size or 8
        if gx + size > img:getWidth() or gy + size > img:getHeight() then return nil end
        local parts = {}
        for y = 0, size - 1 do
            for x = 0, size - 1 do
                local r, _, _, a = img:getPixel(gx + x, gy + y)
                if a > 0.5 and (r < 0.5) ~= (light == true) then parts[#parts + 1] = ("M%d %dh1v1h-1z"):format(x, y) end
            end
        end
        return #parts > 0 and table.concat(parts) or nil
    end

    -- One character of the game's own font (e.g. "♂", "♀") as an SVG path
    -- on its 8x8 tile, one 1x1 square per ink pixel, so the page can draw
    -- it sharp, at any size and in the text's colour. Looked up through
    -- the game's charmap (Font.encode), so a mod's font is respected; nil
    -- when the font has no such glyph.
    function S.glyphPath(data, ch)
        local okF, Font = pcall(require, "src.render.Font")
        if not okF then return nil end
        local okE, codes = pcall(Font.encode, ch)
        local code = okE and type(codes) == "table" and #codes == 1 and codes[1]
        if not code or code == 0x7F then return nil end -- 0x7F: no glyph (a space)
        local def = data.font or {}
        local image, base
        if def.image and code >= (def.mainBase or 0x80) then
            image, base = def.image, def.mainBase or 0x80
        elseif def.imageExtra and code >= (def.extraBase or 0x60) then
            image, base = def.imageExtra, def.extraBase or 0x60
        end
        if not image then return nil end
        local img = Assets.imageData(image)
        local per = def.glyphsPerRow or math.floor(img:getWidth() / 8)
        local index = code - base
        return tilePath(img, (index % per) * 8, math.floor(index / per) * 8)
    end

    -- Gen 2's shiny mark: the summary screen's ⁂ (StatsScreen_PlaceShinyIcon,
    -- tile $3f of the stats tile sheet, SummaryMenu's TILE_SHINY), as a path
    -- like glyphPath's. nil on Gen 1 (no shinies there) or without the sheet.
    function S.shinyPath(data)
        local gfx = data.gen2MenuGfx and data.gen2MenuGfx.stats
        if not (gfx and gfx.sheet) then return nil end
        local index = 0x3f - (gfx.firstTile or 0x31)
        return tilePath(Assets.imageData(gfx.sheet), index * 8, 0)
    end

    -- Gen 2's footprint, as the POKéDEX entry draws it (PokedexMenu:
    -- drawFootprint): the species' 16x16 cell of the footprints strip, in
    -- footprintOrder, as an SVG path on a 16x16 box like glyphPath's. nil on
    -- Gen 1 (no footprints there), without the strip, or for a species the
    -- strip has no cell for (one a mod adds).
    local footprintSheet -- path -> ImageData, loaded once
    function S.footprintPath(data, species)
        local gfx = data.gen2MenuGfx and data.gen2MenuGfx.pokedex
        local path, order = gfx and gfx.footprints, gfx and gfx.footprintOrder
        if not (path and type(order) == "table") then return nil end
        local index
        for i, id in ipairs(order) do
            if id == species then index = i break end
        end
        if not index then return nil end
        if not (footprintSheet and footprintSheet.path == path) then
            footprintSheet = { path = path, img = Assets.imageData(path) }
        end
        -- the strip is 1bpp as extracted, print light on dark; the game's
        -- palette turns it dark on light, the way the page draws it
        return tilePath(footprintSheet.img, 0, (index - 1) * 16, 16, true)
    end

    -- A gym badge's picture from the trainer card (16x16, the game's gray).
    -- Gen 1: badges.png is eight stacked [leader face, badge] pairs (32 px
    -- each, src/ui/TrainerCard.lua), badge k at y = (k - 1) * 32 + 16.
    -- Gen 2: the Johto badges only (its trainer card draws no Kanto ones):
    -- 2x2 blocks of 8x8 tiles in a 2-tile-wide sheet, badge k's first tile
    -- from the first frame of TrainerCard_JohtoBadgesOAM (badgeOam, its x-flip
    -- bit cleared), in the same Johto order platform.badges lists them.
    -- Gen 1's trainer card badge sheet, as transforms.lua derives it from
    -- the player's own cache while a Gen 1 game runs. Gold / Silver's
    -- KANTO badges (9-16) have no picture of their own: the same eight from
    -- that sheet stand in, once a Gen 1 game has been played with the mod.
    local GEN1_BADGES = "save/mod-derived/" .. (mod.id or "second_screen_companion") .. "/companion/badges_kanto.png"
    local function importedGen1Badges()
        return Assets.exists(GEN1_BADGES) and GEN1_BADGES or nil
    end
    function S.badge(data, k)
        k = tonumber(k)
        if not k or k < 1 then return nil end
        local path, y
        local card = data and data.gen2MenuGfx and data.gen2MenuGfx.trainerCard
        local keepWhite = false
        if card and k > 8 then
            path = importedGen1Badges()
            if not path or k > 16 then return nil end
            y = (k - 9) * 32 + 16
            -- shown beside Gold's own badges: on their card's white, as a tile
            keepWhite = true
        elseif card then
            local oam = card.badgeOam and card.badgeOam[k]
            local base = oam and oam.frames and tonumber(oam.frames[1])
            if not (base and card.badges) then return nil end
            path, y = card.badges, math.floor((base % 0x80) / 2) * 8
        else
            if k > 8 then return nil end
            path, y = GEN1_BADGES, (k - 1) * 32 + 16
        end
        if not Assets.exists(path) then return nil end
        return register(("badge|%s|%d|%s"):format(path, y, keepWhite and "w" or "t"), function()
            local sheet = Assets.imageData(path)
            local out = love.image.newImageData(16, 16)
            out:paste(sheet, 0, 0, 0, y, 16, 16)
            -- the card's white around the badge is background: see-through
            -- (filled in from the edges, so the badge's own white highlights
            -- stay), and the badge sits on whatever strip shows it
            local function white(x, y)
                local r, g, b, a = out:getPixel(x, y)
                return a > 0 and r > 0.96 and g > 0.96 and b > 0.96
            end
            local todo = {}
            for e = 0, keepWhite and -1 or 15 do
                todo[#todo + 1] = { e, 0 }; todo[#todo + 1] = { e, 15 }
                todo[#todo + 1] = { 0, e }; todo[#todo + 1] = { 15, e }
            end
            while #todo > 0 do
                local p = table.remove(todo)
                local x, y = p[1], p[2]
                if x >= 0 and y >= 0 and x < 16 and y < 16 and white(x, y) then
                    local r, g, b = out:getPixel(x, y)
                    out:setPixel(x, y, r, g, b, 0)
                    todo[#todo + 1] = { x + 1, y }; todo[#todo + 1] = { x - 1, y }
                    todo[#todo + 1] = { x, y + 1 }; todo[#todo + 1] = { x, y - 1 }
                end
            end
            return out
        end)
    end

    -- PNG bytes for an id, built on first request; nil when unknown or
    -- broken. gray: the plain-gray version where there is one (else the
    -- normal one: a mod's true-colour art has no gray shades to give)
    function S.png(id, gray)
        local entry = entries[id]
        if not entry then return nil end
        local field, build = "png", entry.build
        if gray and entry.gray then field, build = "grayPng", entry.gray end
        if entry[field] == nil then
            local ok, result = pcall(function()
                return build():encode("png"):getString()
            end)
            if not ok then mod.log:warn("sprite %s failed: %s", id, tostring(result)) end
            entry[field] = ok and result or false
        end
        return entry[field] or nil
    end

    return S
end
