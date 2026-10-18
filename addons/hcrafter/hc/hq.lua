-- HQ and success estimates.
--
-- success and tiers follow the HorizonXI wiki crafts page
-- (https://horizonffxi.wiki/Category:Crafts):
--   at or above cap: 95% success, HQ by levels over cap
--     T0 0-10 = 1 in 64, T1 11-30 = 1 in 16, T2 31-50 = 1 in 4, T3 51+ = 1 in 2
--   below cap: 95% minus 10 per level under, never below 5%, no HQ
--
-- a recipe with more than one craft:
--   at cap, success is (95% + 1% per extra craft) to the power of the craft
--   count: 95% with one craft, about 92% with two and 91% with three.
--   each level under cap, in any of its crafts, adds 10% break chance, up
--   to 95%. with one craft this is the wiki rule above. the two- and
--   three-craft figures are an estimate, not a measurement: check them
--   against your own results.
--
-- these parts follow the LandSandBoat synth code (synthutils.cpp):
--   skill is counted in whole levels. the craft with the smallest margin
--   sets the HQ tier. a crafting ring for any craft in the recipe blocks HQ
--   and adds 1% to success. HQ2 and HQ3: a T1 HQ upgrades once at 25%, a T2
--   or T3 HQ can upgrade twice at 25% each, a T0 HQ never upgrades.
--   image support and gear both add to the craft skill used for the synth.
--
-- these are estimates, not guarantees. a server can change any of them.
-- levels above 110 are placeholders in the recipe data, so those recipes get
-- no estimate.
local hq = {
    tiers = {
        { name = 'T0', index = 0, from = 0,  to = 10,        odds = 64 },
        { name = 'T1', index = 1, from = 11, to = 30,        odds = 16 },
        { name = 'T2', index = 2, from = 31, to = 50,        odds = 4 },
        { name = 'T3', index = 3, from = 51, to = math.huge, odds = 2 },
    },
    -- the over-cap levels where a new tier starts
    thresholds = { 11, 31, 51 },
    -- break chance at cap with one craft
    baseBreak = 0.05,
    -- at cap, each craft's success is this much higher per extra craft
    craftStep = 0.01,
    -- break chance added per level under cap, per craft
    breakPerLevel = 0.10,
    maxBreak = 0.95,
    -- a ring that blocks HQ adds this much success
    ringSuccess = 0.01,
    maxSuccess = 0.99,
}

local function Zero()
    return 0
end

-- the tier for a margin of 0 or more. the highest tier the margin reaches,
-- so a margin between two whole numbers still finds one.
local function TierFor(margin)
    if margin == nil or margin < 0 then
        return nil
    end
    local found = hq.tiers[1]
    for _, tier in ipairs(hq.tiers) do
        if margin >= tier.from then
            found = tier
        end
    end
    return found
end

hq.TierFor = TierFor

-- success from 0 to 1 for a recipe of n crafts at cap, before levels under
-- cap and rings. the step per extra craft stops at three crafts, the most
-- any recipe needs, so more crafts can never mean better odds.
function hq.BaseSuccess(crafts)
    if crafts < 1 then
        return 1
    end
    local perCraft = 1 - hq.baseBreak + hq.craftStep * (math.min(crafts, 3) - 1)
    return perCraft ^ crafts
end

-- success from 0 to 1: crafts is the craft count, under the levels under cap
-- added over all crafts, rings the number of crafts with a ring that blocks HQ
function hq.Success(crafts, under, rings)
    local breakChance = math.min(hq.maxBreak, hq.breakPerLevel * (under or 0) + 1 - hq.BaseSuccess(crafts))
    return math.min(hq.maxSuccess, 1 - breakChance + hq.ringSuccess * (rings or 0))
end

-- a whole number from a bonus that a hand-edited settings file might give
-- as text or with decimals
local function WholeBonus(value)
    value = tonumber(value) or 0
    if value ~= value or value == math.huge or value == -math.huge then
        return 0
    end
    return math.floor(value + 0.5)
end

-- ctx fields, each a function of a craft id:
--   skill(c)   your real skill
--   gear(c)    your gear bonus
--   support(c) image support counted for that craft (0 when none)
--   ring(c)    the id of an equipped ring that blocks HQ for that craft, or nil
-- returns nil for a recipe that needs no craft.
function hq.Estimate(recipe, ctx)
    local skillOf = ctx.skill or Zero
    local gearOf = ctx.gear or Zero
    local supportOf = ctx.support or Zero
    local ringOf = ctx.ring or function() return nil end

    local worstId, worstMargin = nil, math.huge
    local crafts = 0
    local hasBonus = false
    local under, rings = 0, 0
    local ring, ringCraft = nil, nil
    local margins = { }

    for craftId, level in ipairs(recipe.skills) do
        if level > 110 then
            return { unknown = true, craftId = craftId, level = level }
        end
        if level > 0 then
            crafts = crafts + 1
            local bonus = WholeBonus(gearOf(craftId)) + WholeBonus(supportOf(craftId))
            if bonus ~= 0 then
                hasBonus = true
            end

            -- the tiny offset keeps 70.9999999 (ten 0.1 skill-ups) at 71
            local margin = math.floor((tonumber(skillOf(craftId)) or 0) + 0.0001) + bonus - level
            margins[craftId] = margin
            if margin < worstMargin then
                worstId, worstMargin = craftId, margin
            end
            if margin < 0 then
                under = under - margin
            end

            local ringId = ringOf(craftId)
            if ringId ~= nil then
                ring, ringCraft = ring or ringId, ringCraft or craftId
                rings = rings + 1
            end
        end
    end

    if crafts == 0 then
        return nil
    end
    local success = hq.Success(crafts, under, rings)

    local estimate = {
        craftId = worstId,
        margin = worstMargin,
        level = recipe.skills[worstId],
        crafts = crafts,
        margins = margins,
        hasBonus = hasBonus,
        success = math.floor(success * 100 + 0.5),
        ring = ring,
        ringCraft = ringCraft,
    }

    if worstMargin < 0 then
        estimate.underCap = true
    else
        estimate.underCap = false
        estimate.tier = TierFor(worstMargin)
        local nextTier = hq.tiers[estimate.tier.index + 2]
        if nextTier ~= nil then
            estimate.nextTier = nextTier
            estimate.toNext = nextTier.from - worstMargin
        end
    end

    estimate.canHQ = not estimate.underCap and ring == nil
    return estimate
end

-- -1 under cap, then 0 to 3 for T0 to T3
function hq.TierIndex(estimate)
    if estimate == nil or estimate.unknown or estimate.underCap then
        return -1
    end
    return estimate.tier.index
end

-- one line of text for an estimate, such as
-- "HQ T1, about 1 in 16 (Bonecraft 11 over cap)"
function hq.Describe(estimate, skillNames)
    if estimate == nil then
        return nil
    end

    local craftName = skillNames[estimate.craftId] or '?'
    if estimate.unknown then
        return ('No estimate: the recipe data lists %s %i'):format(craftName, estimate.level)
    end

    local extra = estimate.hasBonus and ', with gear and support' or ''
    if estimate.underCap then
        return ('No HQ: %s %i under cap, success about %i percent%s'):format(
            craftName, -estimate.margin, estimate.success, extra)
    end
    if estimate.ring ~= nil then
        return ('No HQ: a crafting ring is on (%s %i over cap%s)'):format(craftName, estimate.margin, extra)
    end

    return ('HQ %s, about 1 in %i (%s %i over cap%s)'):format(
        estimate.tier.name, estimate.tier.odds, craftName, estimate.margin, extra)
end

-- the chance of an HQ result once the synth succeeds. quality is the synth
-- effect value: 2 = HQ, 3 = HQ2, 4 = HQ3. LandSandBoat sends 2 for every HQ
-- tier (synthutils.cpp, handleSynthResult), so 2 counts as any HQ.
-- upgrades follow LandSandBoat's calcSynthResult: T0 never upgrades, T1 gets
-- one 25 percent try at HQ2, T2 and T3 get two tries. returns nil without a
-- tier, and for a result the model says can't happen (an HQ3 at T1, say):
-- then the estimate or the model is off for this server, so no odds show.
function hq.OutcomeChance(estimate, quality)
    if estimate == nil or estimate.unknown or estimate.underCap or estimate.tier == nil then
        return nil
    end
    -- with a crafting ring on the model says no HQ at all
    if estimate.ring ~= nil then
        return nil
    end

    local p = 1 / estimate.tier.odds
    local index = estimate.tier.index
    if quality == 2 then
        return p
    elseif quality == 3 then
        if index == 0 then
            return nil
        end
        return index == 1 and p * 0.25 or p * 0.25 * 0.75
    elseif quality == 4 then
        if index <= 1 then
            return nil
        end
        return p * 0.25 * 0.25
    end
    return nil
end

-- what image support would do for a recipe. returns a list of hints:
--   { kind = 'imagery', state = 'on', craftId, support }  support is counted
--   { kind = 'support', craftId, support = 1 or 3, tier = 'T1' }   support would reach a tier
--   { kind = 'support', craftId, support, success = n }  support would raise success under cap
--   { kind = 'support', craftId, support, cap = true }   support would reach the cap
--   { kind = 'elsewhere', craftId, other }  imagery is on for another craft
--   { kind = 'ring', craftId, ring }  a crafting ring blocks HQ
-- imageryCraft is the craft with an active imagery buff, or nil.
function hq.Hints(recipe, ctx, imageryCraft)
    local hints = { }
    local estimate = hq.Estimate(recipe, ctx)
    if estimate == nil or estimate.unknown then
        return hints, estimate
    end

    if estimate.ring ~= nil then
        table.insert(hints, { kind = 'ring', craftId = estimate.ringCraft, ring = estimate.ring })
    end

    local limiting = estimate.craftId
    local supportOf = ctx.support or Zero
    local counted = supportOf(limiting) or 0
    if counted > 0 then
        table.insert(hints, { kind = 'imagery', state = 'on', craftId = limiting, support = counted })
        return hints, estimate
    end

    for _, amount in ipairs({ 1, 3 }) do
        local boosted = hq.Estimate(recipe, {
            skill = ctx.skill,
            gear = ctx.gear,
            ring = ctx.ring,
            support = function(c)
                if c == limiting then
                    return amount
                end
                return supportOf(c)
            end,
        })

        local hint = nil
        if estimate.underCap then
            if not boosted.underCap then
                hint = { kind = 'support', craftId = limiting, support = amount, cap = true }
            elseif amount == 3 and boosted.success > estimate.success then
                hint = { kind = 'support', craftId = limiting, support = amount, success = boosted.success }
            end
        elseif hq.TierIndex(boosted) > hq.TierIndex(estimate) then
            hint = { kind = 'support', craftId = limiting, support = amount, tier = boosted.tier.name }
        end

        if hint ~= nil then
            table.insert(hints, hint)
            if imageryCraft ~= nil and imageryCraft ~= limiting then
                table.insert(hints, { kind = 'elsewhere', craftId = limiting, other = imageryCraft })
            end
            break
        end
    end

    return hints, estimate
end

return hq
