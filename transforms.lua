-- Asset recipe (manifest "assets_transforms"), run by the engine against
-- the player's own imported cache of the game being played; the results go
-- to this mod's derived folder (save/mod-derived/<id>/companion/), which is
-- where sprites.lua reads them. Nothing ROM-derived ships with the mod, and
-- the mod never hard-codes the cache's paths. Mod-specific names keep them
-- from shadowing the game's own sheets for anyone else.
return function(ctx)
    -- the battle's party-ball sheet (Gen 1)
    if ctx.exists("battle/balls.png") then
        ctx.writeImage(ctx.readImage("battle/balls.png"), "companion/balls.png")
    end
    -- the trainer card's badge sheet, Gen 1's only (16x256: a face and a
    -- badge per 32 rows; Gold / Silver's is 16x176 and stays the game's).
    -- Kept once made: a Gen 2 game shows its KANTO badges with it, so they
    -- appear once a Gen 1 game has been played with the mod on.
    if ctx.exists("trainer_card/badges.png") then
        local sheet = ctx.readImage("trainer_card/badges.png")
        local w, h = sheet:getDimensions()
        if w == 16 and h == 256 then ctx.writeImage(sheet, "companion/badges_kanto.png") end
    end
end
