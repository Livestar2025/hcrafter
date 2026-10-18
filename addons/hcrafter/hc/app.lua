-- shared state for HCrafter's windows: settings access, your crafts as the
-- estimates see them, and the Resource Planner's result, worked out once a
-- frame. part of HCrafter, GPL-3.0.
require('common')
local recipes = require('hc.recipes')
local hq = require('hc.hq')
local gear = require('hc.gear')
local stock = require('hc.stock')
local planner = require('hc.planner')

local app = {
    frameNo = 0,
    clock = os.clock,
}

local getConfig, markDirty = nil, nil
local planCache = { frame = -1, result = nil, entries = nil }

function app.Init(configFn, dirtyFn)
    getConfig, markDirty = configFn, dirtyFn
end

function app.Config()
    return getConfig()
end

function app.Dirty()
    planCache.frame = -1
    if markDirty ~= nil then
        markDirty()
    end
end

function app.NewFrame()
    app.frameNo = app.frameNo + 1
end

---------------------------------------------------------------------------
-- your crafts
---------------------------------------------------------------------------

-- a finite number, even from a hand-edited settings file
local function Number(value)
    value = tonumber(value) or 0
    if value ~= value or value == math.huge or value == -math.huge then
        return 0
    end
    return value
end

function app.Skill(craftId)
    local skill = app.Config().skills[craftId]
    return Number(skill and skill[1])
end

-- the gear bonus for a craft: what you wear, or the number you typed, as a
-- whole number
function app.Gear(craftId)
    local cfg = app.Config()
    local value
    if cfg.autoGear[1] then
        value = gear.Bonus(craftId)
    else
        local saved = cfg.gear[craftId]
        value = saved and saved[1]
    end
    return math.floor(Number(value) + 0.5)
end

-- image support counted for a craft: only while its imagery buff is on,
-- at the strength picked in settings (+1 basic or +3 advanced)
function app.Support(craftId)
    if gear.HasImagery(craftId) then
        local strength = app.Config().support[1]
        if strength ~= 3 then
            strength = 1
        end
        return strength
    end
    return 0
end

function app.Ring(craftId)
    return gear.Ring(craftId)
end

-- how many synths in a row the alert after your macro waits for, 1 to 6
function app.AlertEvery()
    local ready = app.Config().ready
    local value = tonumber(ready and ready.every and ready.every[1])
    if value == nil or value ~= value then
        return 6
    end
    return math.max(1, math.min(6, math.floor(value + 0.5)))
end

-- your rank cap in a craft in levels, or nil before the game has sent it
function app.Cap(craftId)
    local rank = app.Config().ranks[craftId]
    return recipes.RankCap(rank and rank[1] or -1)
end

local ctx = {
    skill = app.Skill,
    gear = app.Gear,
    support = app.Support,
    ring = app.Ring,
    cap = app.Cap,
}

function app.Ctx()
    return ctx
end

function app.Estimate(recipe)
    return hq.Estimate(recipe, ctx)
end

function app.Hints(recipe)
    return hq.Hints(recipe, ctx, gear.ImageryCraft())
end

---------------------------------------------------------------------------
-- the Resource Planner
---------------------------------------------------------------------------

-- queue a recipe and open the Resource Planner
function app.AddToPlan(recipe)
    local plan = app.Config().planner
    plan.visible[1] = true
    plan.tab[1] = 1
    for _, entry in ipairs(plan.entries) do
        if entry.recipeId == recipe.id then
            app.Dirty()
            return false
        end
    end
    table.insert(plan.entries, T{ recipeId = recipe.id, synths = T{ 1 } })
    app.Dirty()
    return true
end

local function ChosenOption(itemId)
    local chosen = app.Config().planner.make[itemId]
    local options = recipes.Options(itemId)
    if chosen == nil or options == nil then
        return nil
    end
    chosen = math.floor(tonumber(chosen) or 1)
    if chosen < 1 then
        chosen = 1
    elseif chosen > #options then
        chosen = #options
    end
    return chosen
end

app.ChosenOption = ChosenOption

function app.Choose(itemId)
    local chosen = ChosenOption(itemId)
    if chosen == nil then
        return nil
    end
    return recipes.Options(itemId)[chosen]
end

-- what you hold that the plan may use
function app.Have(itemId)
    local plan = app.Config().planner
    local onYou, inBags, onOthers = stock.Counts(itemId)
    local held = onYou
    if plan.useBags[1] then
        held = held + inBags
    end
    if plan.useOthers[1] then
        held = held + onOthers
    end
    return held
end

-- the queued recipes that still exist: { { recipe, synths, entry }, ... }
function app.PlanEntries()
    local list = { }
    for _, entry in ipairs(app.Config().planner.entries) do
        local recipe = recipes.byId[entry.recipeId]
        if recipe ~= nil then
            table.insert(list, { recipe = recipe, synths = math.floor(tonumber(entry.synths[1]) or 1), entry = entry })
        end
    end
    return list
end

-- the plan worked out from the queue, at most once a frame
function app.PlanResult()
    if planCache.frame == app.frameNo and planCache.result ~= nil then
        return planCache.result, planCache.entries
    end
    local entries = app.PlanEntries()
    local result = planner.Build(entries, app.Choose, app.Have, recipes.Grouped, app.Config().planner.spare[1])
    planCache.frame = app.frameNo
    planCache.result = result
    planCache.entries = entries
    return result, entries
end

return app
