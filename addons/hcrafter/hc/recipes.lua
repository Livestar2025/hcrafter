-- recipe lookups shared by the recipe book, the Resource Planner and the
-- skill-up mode. the recipe table itself comes from xitools
-- (data/recipesBySkill.lua), and the skill names and search come from its
-- crafty component (lin, GPL-3.0). part of HCrafter, GPL-3.0.
local recipesBySkill = require('data.recipesBySkill')

local recipes = {
    skillNames = {
        [1] = 'Woodworking',
        [2] = 'Smithing',
        [3] = 'Goldsmithing',
        [4] = 'Clothcraft',
        [5] = 'Leathercraft',
        [6] = 'Bonecraft',
        [7] = 'Alchemy',
        [8] = 'Cooking',
    },
    skillAbbr = {
        [1] = 'CRP',
        [2] = 'BSM',
        [3] = 'GSM',
        [4] = 'WVR',
        [5] = 'LTW',
        [6] = 'BON',
        [7] = 'ALC',
        [8] = 'CUL',
    },
    -- guild ranks as the game reports them in the skills packet. the skill
    -- cap of rank r is (r + 1) x 10 levels.
    rankNames = {
        [0] = 'Amateur',
        [1] = 'Recruit',
        [2] = 'Initiate',
        [3] = 'Novice',
        [4] = 'Apprentice',
        [5] = 'Journeyman',
        [6] = 'Craftsman',
        [7] = 'Artisan',
        [8] = 'Adept',
        [9] = 'Veteran',
        [10] = 'Expert',
        [11] = 'Authority',
    },
    all = { },
    byId = { },
    byResult = { },
    usedIn = { },
    byCraft = { },
}

for craftId = 1, 8 do
    recipes.byCraft[craftId] = { }
end

function recipes.MaxSkill(recipe)
    local maxSkill = 0
    for _, skillLevel in ipairs(recipe.skills) do
        if skillLevel > maxSkill then
            maxSkill = skillLevel
        end
    end

    return maxSkill
end

-- the craft a recipe belongs to: the highest level it needs, lowest craft id
-- on a tie, the same rule the LandSandBoat synth code uses
function recipes.MainCraft(recipe)
    local craftId, level = nil, 0
    for skillId, skillLevel in ipairs(recipe.skills) do
        if skillLevel > level then
            craftId, level = skillId, skillLevel
        end
    end
    return craftId, level
end

-- the cap of a guild rank in whole levels, or nil when the rank is unknown
function recipes.RankCap(rank)
    rank = tonumber(rank)
    if rank == nil or rank < 0 then
        return nil
    end
    return (math.floor(rank) + 1) * 10
end

-- crystal plus sorted material ids, the way the synth packet is matched
local byIngredients = { }

local function IngredientKey(ids)
    local sorted = { }
    for _, id in ipairs(ids) do
        if id ~= nil and id ~= 0 then
            table.insert(sorted, id)
        end
    end
    table.sort(sorted)
    return table.concat(sorted, ',')
end

recipes.IngredientKey = IngredientKey

-- HorizonXI's own changes to the recipe table, by recipe id: the craft
-- levels it set. { [recipe id] = { [craft id] = level } }
recipes.hxi = {
    -- Sonic Belt: Leathercraft 107 on HorizonXI (85 in the table)
    [44032] = { [5] = 107 },
}

for _, recipeList in ipairs(recipesBySkill) do
    for _, recipe in ipairs(recipeList) do
        local changes = recipes.hxi[recipe.id]
        if changes ~= nil and not recipe.hxi then
            for craftId, level in pairs(changes) do
                recipe.skills[craftId] = level
            end
            recipe.hxi = true
        end
        table.insert(recipes.all, recipe)
        recipes.byId[recipe.id] = recipe

        local options = recipes.byResult[recipe.result]
        if options == nil then
            options = { }
            recipes.byResult[recipe.result] = options
        end
        table.insert(options, recipe)

        local seen = { }
        for _, ingredientId in ipairs(recipe.ingredients) do
            if not seen[ingredientId] then
                seen[ingredientId] = true
                local uses = recipes.usedIn[ingredientId]
                if uses == nil then
                    uses = { }
                    recipes.usedIn[ingredientId] = uses
                end
                table.insert(uses, recipe)
            end
        end

        for skillId, skillLevel in ipairs(recipe.skills) do
            if skillLevel > 0 and recipes.byCraft[skillId] ~= nil then
                table.insert(recipes.byCraft[skillId], recipe)
            end
        end

        -- the first recipe with a given crystal and materials wins, as in
        -- the old lookup table
        local byCrystal = byIngredients[recipe.crystal]
        if byCrystal == nil then
            byCrystal = { }
            byIngredients[recipe.crystal] = byCrystal
        end
        local key = IngredientKey(recipe.ingredients)
        if byCrystal[key] == nil then
            byCrystal[key] = recipe
        end
    end
end

-- every recipe a craft takes part in, lowest level for that craft first
for craftId = 1, 8 do
    table.sort(recipes.byCraft[craftId], function(a, b)
        if a.skills[craftId] ~= b.skills[craftId] then
            return a.skills[craftId] < b.skills[craftId]
        end
        return a.id < b.id
    end)
end

-- when several recipes make the same item, list the easiest one first: no key
-- item, then the lowest skill requirement, then the lowest recipe id
local optionNumbers = { }
for _, options in pairs(recipes.byResult) do
    if #options > 1 then
        table.sort(options, function(a, b)
            local aNeedsKeyItem = a.keyItem > 0
            local bNeedsKeyItem = b.keyItem > 0
            if aNeedsKeyItem ~= bNeedsKeyItem then
                return bNeedsKeyItem
            end

            local aSkill = recipes.MaxSkill(a)
            local bSkill = recipes.MaxSkill(b)
            if aSkill ~= bSkill then
                return aSkill < bSkill
            end

            return a.id < b.id
        end)
    end

    for optionNumber, recipe in ipairs(options) do
        optionNumbers[recipe] = optionNumber
    end
end

-- the recipes that make an item, easiest first, or nil if it can't be crafted
function recipes.Options(itemId)
    return recipes.byResult[itemId]
end

-- this recipe's position among the recipes that make the same item
function recipes.OptionNumber(recipe)
    return optionNumbers[recipe] or 1
end

-- the recipe for a crystal and a list of material ids, or nil. crystal must
-- already be the normal crystal id (4096 to 4103).
function recipes.ByIngredients(crystal, ingredientIds)
    local byCrystal = byIngredients[crystal]
    if byCrystal == nil then
        return nil
    end
    return byCrystal[IngredientKey(ingredientIds)]
end

-- repeated materials grouped into { id, count } pairs, in the order each first
-- appears. built once per recipe and cached.
local grouped = { }
function recipes.Grouped(recipe)
    local list = grouped[recipe]
    if list ~= nil then
        return list
    end

    list = { }
    local indexById = { }
    for _, ingredientId in ipairs(recipe.ingredients) do
        local index = indexById[ingredientId]
        if index == nil then
            table.insert(list, { id = ingredientId, count = 1 })
            indexById[ingredientId] = #list
        else
            list[index].count = list[index].count + 1
        end
    end

    grouped[recipe] = list
    return list
end

-- the crafts a recipe needs, highest level first: { { id, level }, ... }
local requirements = { }
function recipes.Requirements(recipe)
    local list = requirements[recipe]
    if list ~= nil then
        return list
    end

    list = { }
    for skillId, skillLevel in ipairs(recipe.skills) do
        if skillLevel > 0 then
            table.insert(list, { id = skillId, level = skillLevel })
        end
    end

    table.sort(list, function(a, b)
        if a.level ~= b.level then
            return a.level > b.level
        end

        return a.id < b.id
    end)

    requirements[recipe] = list
    return list
end

return recipes
