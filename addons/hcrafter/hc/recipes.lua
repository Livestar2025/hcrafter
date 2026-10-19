-- recipe lookups shared by the recipe book, the Resource Planner and the
-- skill-up mode. the recipe table (data/recipesBySkill.lua) is built from
-- LandSandBoat's recipes with AirSkyBoat's craft levels and HorizonXI's own
-- changes (tools/regen_recipes.py). the skill names and search come from
-- xitools' craft tool (lin, GPL-3.0). part of HCrafter, GPL-3.0.
local recipesBySkill = require('data.recipesBySkill')

-- recipes from expansions after Treasures of Aht Urhgan, by id. they are
-- listed only when Settings asks for them.
local laterIds = { }
do
    local ok, list = pcall(require, 'data.recipeEras')
    if ok and type(list) == 'table' then
        laterIds = list
    end
end

-- what changed from the table before 1.4.0: each changed item's recipes in
-- their old order, and the ids that made another item. used once, to carry
-- old settings over.
local moves = { options = { }, madeBefore = { } }
do
    local ok, list = pcall(require, 'data.recipeMoves')
    if ok and type(list) == 'table' then
        moves.options = type(list.options) == 'table' and list.options or { }
        moves.madeBefore = type(list.madeBefore) == 'table' and list.madeBefore or { }
    end
end

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
    -- the recipes the lists show: every era, or up to ToAU (see ShowLater)
    all = { },
    byResult = { },
    byCraft = { },
    -- every recipe in the table, whatever the setting, and by id
    every = { },
    byId = { },
    -- true when recipes from after ToAU are listed
    showLater = false,
    -- goes up each time the lists change, so a cache can tell
    version = 0,
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
        recipe.later = laterIds[recipe.id] == true
        table.insert(recipes.every, recipe)
        recipes.byId[recipe.id] = recipe

        -- every era, so a synth is always recognized. the first recipe with
        -- a given crystal and materials wins, as in the old lookup table.
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

-- when several recipes make the same item, the easiest first: no key item,
-- then the lowest skill requirement, then the lowest recipe id
local function Easier(a, b)
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
end

-- every recipe that makes an item, any era, easiest first
local everyOption = { }
for _, recipe in ipairs(recipes.every) do
    local options = everyOption[recipe.result]
    if options == nil then
        options = { }
        everyOption[recipe.result] = options
    end
    table.insert(options, recipe)
end
for _, options in pairs(everyOption) do
    table.sort(options, Easier)
end

-- every recipe a craft takes part in, any era, lowest level for that craft
-- first
local everyByCraft = { }
for craftId = 1, 8 do
    local list = { }
    for _, recipe in ipairs(recipes.every) do
        if (recipe.skills[craftId] or 0) > 0 then
            list[#list + 1] = recipe
        end
    end
    table.sort(list, function(a, b)
        if a.skills[craftId] ~= b.skills[craftId] then
            return a.skills[craftId] < b.skills[craftId]
        end
        return a.id < b.id
    end)
    everyByCraft[craftId] = list
end

local function Clear(list)
    for key in pairs(list) do
        list[key] = nil
    end
end

local optionNumbers = { }

-- fills the lists the book, the planner and the skill-up ideas use: every
-- recipe, or only those up to ToAU. the tables are refilled in place, from
-- lists already in order.
local function Shown(recipe)
    return recipes.showLater or not recipe.later
end

function recipes.ShowLater(on)
    recipes.showLater = on == true
    Clear(recipes.all)
    Clear(recipes.byResult)
    Clear(optionNumbers)
    for _, recipe in ipairs(recipes.every) do
        if Shown(recipe) then
            table.insert(recipes.all, recipe)
        end
    end
    for craftId = 1, 8 do
        local list = recipes.byCraft[craftId]
        Clear(list)
        for _, recipe in ipairs(everyByCraft[craftId]) do
            if Shown(recipe) then
                list[#list + 1] = recipe
            end
        end
    end
    for result, every in pairs(everyOption) do
        local options = nil
        for _, recipe in ipairs(every) do
            if Shown(recipe) then
                options = options or { }
                options[#options + 1] = recipe
                optionNumbers[recipe] = #options
            end
        end
        recipes.byResult[result] = options
    end
    recipes.version = recipes.version + 1
end

recipes.ShowLater(false)

-- the easiest recipe that makes an item, up to ToAU when there is one, or
-- nil when nothing makes it
local function Easiest(itemId)
    local options = everyOption[itemId]
    if options == nil then
        return nil
    end
    for _, recipe in ipairs(options) do
        if not recipe.later then
            return recipe
        end
    end
    return options[1]
end

-- the id of the recipe that a setting from before 1.4.0 meant by a place in
-- an item's recipe list, the list as it was then. when that recipe is gone
-- or now makes something else, the easiest one stands in. nil when nothing
-- makes the item.
function recipes.IdForOption(itemId, number)
    itemId = tonumber(itemId)
    if itemId == nil or everyOption[itemId] == nil then
        return nil
    end
    number = tonumber(number)
    if number == nil or number ~= number then
        number = 1
    end
    -- moves.options has the old list of every item whose list changed, so
    -- a place past the old end stays on the old last recipe
    local before = moves.options[itemId] or everyOption[itemId]
    local place = math.max(1, math.min(#before, math.floor(number)))
    local entry = before[place]
    local id = type(entry) == 'table' and entry.id or entry
    local recipe = recipes.byId[id]
    if recipe ~= nil and recipe.result == itemId then
        return id
    end
    local easiest = Easiest(itemId)
    return easiest and easiest.id or nil
end

-- the item a recipe id made before 1.4.0 when it now makes another, or nil
function recipes.MadeBefore(id)
    return moves.madeBefore[tonumber(id) or -1]
end

-- the easiest recipe for an item, up to ToAU when there is one, any era
function recipes.Easiest(itemId)
    return Easiest(tonumber(itemId))
end

-- the recipe a history entry names, or nil. the entry's item is what the
-- server said was made, an HQ item for an HQ, so it isn't checked against
-- the recipe. an id whose result changed in 1.4.0 kept its materials and
-- crystal, so it is still the recipe that was used.
function recipes.ForEntry(entry)
    if type(entry) ~= 'table' or entry.recipe == nil then
        return nil
    end
    return recipes.byId[tonumber(entry.recipe) or -1]
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
