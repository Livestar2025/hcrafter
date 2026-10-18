-- skill-up estimates. the model is the era ("non-modern") skill-up code in
-- LandSandBoat synthutils.cpp, read 2026-10-17:
--   no skill-up at or over the recipe level, by your real skill (gear and
--   image support do not count). no skill-up at or over your rank cap.
--   chance 60% below skill 50.0, 25% from 50.0, whatever the level gap.
--   a break can still give a skill-up when the recipe is 1 to 5 levels over
--   your real skill, at half the chance.
--   below skill 60.0 a skill-up is 0.1 to 0.5, larger more often when the
--   gap is wide. from 60.0 every skill-up is 0.1.
-- the HorizonXI wiki says a break skills up at the same rate, so the break
-- rule is a setting. HorizonXI may tune any of this, which is why HCrafter
-- can also use the skill-up rate measured from your own synth history.
-- every number here is an estimate.
local hq = require('hc.hq')
local recipes = require('hc.recipes')

local skillup = {
    halfOnBreak = 1,
    sameOnBreak = 2,
    -- chance a skill-up is +0.1 to +0.5, by levels between the recipe and
    -- your real skill (LandSandBoat skillUpAmountWeights, from retail logs)
    weights = {
        [0] = { 85, 15, 0, 0, 0 },
        [1] = { 85, 15, 0, 0, 0 },
        [2] = { 85, 15, 0, 0, 0 },
        [3] = { 80, 20, 0, 0, 0 },
        [4] = { 80, 20, 0, 0, 0 },
        [5] = { 70, 30, 0, 0, 0 },
        [6] = { 70, 30, 0, 0, 0 },
        [7] = { 60, 40, 0, 0, 0 },
        [8] = { 60, 40, 0, 0, 0 },
        [9] = { 50, 40, 10, 0, 0 },
        [10] = { 40, 40, 20, 0, 0 },
        [11] = { 40, 40, 20, 0, 0 },
        [12] = { 15, 45, 30, 10, 0 },
        [13] = { 10, 40, 25, 25, 0 },
        [14] = { 0, 40, 30, 20, 10 },
    },
    -- the widest gap the recommendations look at
    maxGap = 8,
    -- synths in your history before the measured rate can be used
    minMeasured = 30,
}

local function Tenths(skill)
    return math.floor((skill or 0) * 10 + 0.5)
end

-- the era chance of a skill-up on a successful synth
function skillup.BaseChance(skill)
    if Tenths(skill) < 500 then
        return 0.6
    end
    return 0.25
end

-- the expected size of one skill-up, in tenths of a level
function skillup.ExpectedAmount(skill, gap)
    if Tenths(skill) >= 600 then
        return 1
    end
    local row = skillup.weights[math.max(0, math.min(14, gap))]
    local total = 0
    for amount, weight in ipairs(row) do
        total = total + amount * weight
    end
    return total / 100
end

-- how good a recipe is for skilling up right now (the names players see
-- are in bandNames):
--   'none'    no skill-ups (you are at or over its level, or at your cap)
--   'optimal' 1 or more levels over you and a break is unlikely: Optimal
--   'costly'  breaks are common: Manageable
--   'danger'  most synths break, and breaks give no skill-ups: Risky
-- gap uses your real skill, risk uses skill plus gear and support.
-- returns the band, the gap and the effective difficulty.
function skillup.Band(recipeLevel, skill, bonus, cap)
    local whole = math.floor((skill or 0) + 0.0001)
    local gap = recipeLevel - whole
    local difficulty = gap - (bonus or 0)
    if gap <= 0 or (cap ~= nil and Tenths(skill) >= cap * 10) then
        return 'none', gap, difficulty
    end
    if difficulty <= 2 then
        return 'optimal', gap, difficulty
    elseif difficulty <= 5 then
        return 'costly', gap, difficulty
    end
    return 'danger', gap, difficulty
end

skillup.bandNames = {
    none = 'No skill-ups',
    optimal = 'Optimal',
    costly = 'Manageable',
    danger = 'Risky',
}

skillup.bandOrder = { optimal = 1, costly = 2, danger = 3, none = 4 }

-- expected skill per synth for one craft of a recipe.
-- ctx: the hq context (skill, gear, support, ring functions), plus
--   cap(c)      your rank cap in levels, or nil when unknown
-- opts: breakRule (1 half, 2 same), rate (a measured chance, or nil)
-- returns { gain (levels per synth), success (0-1), chance, band, gap, difficulty }
function skillup.PerSynth(recipe, craftId, ctx, opts)
    opts = opts or { }
    local level = recipe.skills[craftId] or 0
    local skill = ctx.skill(craftId) or 0
    local cap = ctx.cap and ctx.cap(craftId) or nil
    local bonus = (ctx.gear and ctx.gear(craftId) or 0) + (ctx.support and ctx.support(craftId) or 0)
    local band, gap, difficulty = skillup.Band(level, skill, bonus, cap)

    local estimate = hq.Estimate(recipe, ctx)
    local success = 0
    if estimate ~= nil and not estimate.unknown then
        success = estimate.success / 100
    end

    local out = { gain = 0, success = success, chance = 0, band = band, gap = gap, difficulty = difficulty, level = level }
    if band == 'none' or level <= 0 or level > 110 then
        return out
    end

    local chance = opts.rate or skillup.BaseChance(skill)
    local onBreak = 0
    if gap <= 5 then
        onBreak = opts.breakRule == skillup.sameOnBreak and chance or chance / 2
    end

    local amount = skillup.ExpectedAmount(skill, gap)
    if cap ~= nil then
        amount = math.min(amount, cap * 10 - Tenths(skill))
    end

    out.chance = success * chance + (1 - success) * onBreak
    out.gain = out.chance * amount / 10
    return out
end

-- recipes that give skill-ups in a craft now, best first: Optimal before
-- Manageable before Risky, then the most skill per synth.
-- returns { { recipe, gain, success, band, gap, difficulty, synthsPerLevel }, ... }
function skillup.Recommend(craftId, ctx, opts, limit)
    local skill = ctx.skill(craftId) or 0
    local whole = math.floor(skill + 0.0001)
    local list = { }
    for _, recipe in ipairs(recipes.byCraft[craftId] or { }) do
        local level = recipe.skills[craftId]
        if level > whole and level - whole <= skillup.maxGap and recipes.MaxSkill(recipe) <= 110 then
            local per = skillup.PerSynth(recipe, craftId, ctx, opts)
            if per.gain > 0 then
                per.recipe = recipe
                per.synthsPerLevel = 1 / per.gain
                table.insert(list, per)
            end
        end
    end

    table.sort(list, function(a, b)
        local ao, bo = skillup.bandOrder[a.band], skillup.bandOrder[b.band]
        if ao ~= bo then
            return ao < bo
        end
        if math.abs(a.gain - b.gain) > 1e-9 then
            return a.gain > b.gain
        end
        return a.recipe.id < b.recipe.id
    end)

    if limit ~= nil then
        while #list > limit do
            table.remove(list)
        end
    end
    return list
end

-- a path from your skill to a target: at each whole level, the best recipe
-- and about how many synths it takes. returns steps and the total synths,
-- or steps so far and nil when no recipe gives skill-ups at some level.
function skillup.Plan(craftId, target, ctx, opts)
    local skill = ctx.skill(craftId) or 0
    local cap = ctx.cap and ctx.cap(craftId) or nil
    if cap ~= nil and target > cap then
        target = cap
    end

    local steps, total = { }, 0
    local tenths, goal = Tenths(skill), Tenths(target)
    local guard = 0
    while tenths < goal and guard < 200 do
        guard = guard + 1
        local at = tenths / 10
        local nextWhole = (math.floor(tenths / 10) + 1) * 10
        local span = math.min(nextWhole, goal) - tenths

        local stepCtx = { }
        for key, fn in pairs(ctx) do
            stepCtx[key] = fn
        end
        stepCtx.skill = function(c)
            if c == craftId then
                return at
            end
            return ctx.skill(c)
        end

        local best = skillup.Recommend(craftId, stepCtx, opts, 1)[1]
        if best == nil then
            return steps, nil, at
        end
        local synths = (span / 10) / best.gain
        table.insert(steps, { from = at, to = (tenths + span) / 10, recipe = best.recipe, synths = synths, band = best.band })
        total = total + synths
        tenths = tenths + span
    end
    return steps, total
end

-- your own skill-up rate in a craft, from synth history: successful synths
-- that could give a skill-up (recipe over your skill, below your cap) and
-- how many did. only synths at the same side of skill 50 as now count,
-- since the era rate changes there.
function skillup.Measured(craftId, list, currentSkill, cap)
    local chances, ups = 0, 0
    local high = Tenths(currentSkill) >= 500
    for _, entry in ipairs(list or { }) do
        local recipe = entry.recipe and recipes.byId[entry.recipe] or nil
        local skillupEntry = type(entry.skillup) == 'table' and entry.skillup[craftId] or nil
        if recipe ~= nil and skillupEntry ~= nil and skillupEntry.before ~= nil and entry.result ~= 1 then
            local before = skillupEntry.before
            local level = recipe.skills[craftId] or 0
            local eligible = level - math.floor(before + 0.0001) > 0
                and (cap == nil or Tenths(before) < cap * 10)
                and (Tenths(before) >= 500) == high
            if eligible then
                chances = chances + 1
                if (skillupEntry.change or 0) > 0 then
                    ups = ups + 1
                end
            end
        end
    end
    return ups, chances
end

return skillup
