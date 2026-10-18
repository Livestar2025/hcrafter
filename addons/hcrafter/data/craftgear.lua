---@diagnostic disable
-- crafting gear HCrafter can recognize when you wear it.
--
-- skill: item id -> { [craft id] = skill bonus }
-- antiHQ: item id -> craft id. these rings stop HQ for any recipe that uses
-- that craft, and add 1% to its success.
--
-- craft ids: 1 Woodworking, 2 Smithing, 3 Goldsmithing, 4 Clothcraft,
-- 5 Leathercraft, 6 Bonecraft, 7 Alchemy, 8 Cooking.
--
-- source: LandSandBoat sql/item_mods.sql, mods WOOD..COOK (128-135) and
-- SYNTH_ANTI_HQ_* (144-151), read 2026-10-17. LandSandBoat lists Smythe's
-- Escutcheon (26429) as Bonecraft +1. the in-game name and the rest of the
-- escutcheon set point to Smithing, so it is listed as Smithing here. many
-- of these items are newer than the era HorizonXI recreates. a server can
-- give any item different bonuses, so the settings tab lets you type your
-- gear bonus instead.
return {
    skill = {
        -- guild torques, +2
        [10948] = { [1] = 2 }, -- Carver's Torque
        [10949] = { [2] = 2 }, -- Smithy's Torque
        [10950] = { [3] = 2 }, -- Goldsmith's Torque
        [10951] = { [4] = 2 }, -- Weaver's Torque
        [10952] = { [5] = 2 }, -- Tanner's Torque
        [10953] = { [6] = 2 }, -- Boneworker's Torque
        [10954] = { [7] = 2 }, -- Alchemist's Torque
        [10955] = { [8] = 2 }, -- Culinarian's Torque
        -- guild smocks, +1
        [11329] = { [1] = 1 }, -- Carpenter's Smock
        [11330] = { [2] = 1 }, -- Blacksmith's Smock
        [11331] = { [3] = 1 }, -- Goldsmith's Smock
        [11332] = { [4] = 1 }, -- Weaver's Smock
        [11333] = { [5] = 1 }, -- Tanner's Smock
        [11334] = { [6] = 1 }, -- Boneworker's Smock
        [11335] = { [7] = 1 }, -- Alchemist's Smock
        [11336] = { [8] = 1 }, -- Culinarian's Smock
        -- headgear
        [13945] = { [3] = 1 }, -- Shaded Spectacles
        [13946] = { [4] = 1 }, -- Magnifying Spectacles
        [13947] = { [6] = 1 }, -- Protective Spectacles
        [13948] = { [8] = 1 }, -- Chef's Hat
        -- guild aprons, +1
        [14392] = { [1] = 1 }, -- Carpenter's Apron
        [14393] = { [2] = 1 }, -- Blacksmith's Apron
        [14394] = { [3] = 1 }, -- Goldsmith's Apron
        [14395] = { [4] = 1 }, -- Weaver's Apron
        [14396] = { [5] = 1 }, -- Tanner's Apron
        [14397] = { [6] = 1 }, -- Boneworker's Apron
        [14398] = { [7] = 1 }, -- Alchemist's Apron
        [14399] = { [8] = 1 }, -- Culinarian's Apron
        -- gloves
        [14830] = { [1] = 1 }, -- Carpenter's Gloves
        [14831] = { [2] = 1 }, -- Smithy's Mitts
        [14832] = { [5] = 1 }, -- Tanner's Gloves
        -- others
        [17058] = { [7] = 1 }, -- Caduceus
        [26406] = { [1] = 3, [2] = 3, [3] = 3, [4] = 3, [5] = 3, [6] = 3, [7] = 3, [8] = 3 }, -- Kupo Shield
        -- escutcheons, +1
        [26424] = { [1] = 1 }, -- Joiner's Escutcheon
        [26429] = { [2] = 1 }, -- Smythe's Escutcheon (see the note above)
        [26434] = { [3] = 1 }, -- Toreutic Escutcheon
        [26439] = { [4] = 1 }, -- Plaiter's Escutcheon
        [26444] = { [5] = 1 }, -- Beveler's Escutcheon
        [26449] = { [6] = 1 }, -- Ossifier's Escutcheon
        [26454] = { [7] = 1 }, -- Brewer's Escutcheon
        [26459] = { [8] = 1 }, -- Chef's Escutcheon
    },
    antiHQ = {
        [15819] = 1, -- Carpenter's Ring
        [15820] = 2, -- Smith's Ring
        [15821] = 3, -- Goldsmith's Ring
        [15822] = 4, -- Tailor's Ring
        [15823] = 5, -- Tanner's Ring
        [15824] = 6, -- Bonecrafter's Ring
        [15825] = 7, -- Alchemist's Ring
        [15826] = 8, -- Chef's Ring
    },
}
