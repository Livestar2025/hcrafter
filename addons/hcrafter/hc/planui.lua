-- the Resource Planner window: the Plan tab works out every synth and every
-- item to buy for your queued recipes, the Skill-up tab suggests recipes
-- for skilling up a craft. part of HCrafter, GPL-3.0.
require('common')
local imgui = require('imgui')
local theme = require('hc.theme')
local text = require('hc.text')
local ui = require('hc.ui')
local items = require('hc.items')
local recipes = require('hc.recipes')
local hq = require('hc.hq')
local stock = require('hc.stock')
local history = require('hc.history')
local prices = require('hc.prices')
local planner = require('hc.planner')
local skillup = require('hc.skillup')
local app = require('hc.app')
local menu = require('hc.menu')
local book = require('hc.book')

local planui = {
    width = 560,
    -- the sizes a player can drag the planner to, in unscaled pixels
    limits = { defaultW = 560, minW = 480, maxW = 1400, minH = 240, maxH = 2400 },
    maxSteps = 12,
    maxIdeas = 12,
}

local col = theme.col
local Px = ui.Px

local bandColors = {
    none = theme.textDim,
    optimal = theme.green,
    costly = theme.amber,
    danger = theme.red,
}

-- set by hcrafter.lua so a click here can open a recipe in the book
planui.OpenInBook = nil

local function IsCrystal(itemId)
    return itemId >= 4096 and itemId <= 4103
end

local function WhereText(itemId)
    local onYou, inBags, onOthers = stock.Counts(itemId)
    local parts = { }
    if inBags > 0 then
        table.insert(parts, ('%i in bags'):format(inBags))
    end
    if onOthers > 0 then
        table.insert(parts, ('%i on others'):format(onOthers))
    end
    if #parts == 0 then
        if onYou > 0 then
            return ('%i on you'):format(onYou)
        end
        return 'none held'
    end
    return table.concat(parts, ', ')
end

local function ItemTip(itemId, hint)
    local lines = { { item = itemId, items.ShortName(itemId), theme.gold, true }, { rule = true } }
    for _, line in ipairs(stock.Locations(itemId)) do
        local label = line.text
        if line.saved ~= nil then
            label = ('%s (saved %s)'):format(line.text, os.date('%b %d', line.saved))
        end
        table.insert(lines, { label, line.count > 0 and theme.textSoft or theme.textDim, right = tostring(line.count) })
    end
    local price, updated = prices.Get(itemId)
    if price ~= nil then
        table.insert(lines, { ('Price %s gil'):format(prices.Format(price)) .. ((updated ~= nil and updated ~= '') and (', set ' .. updated) or ''), theme.goldDark })
    end
    if hint ~= nil then
        table.insert(lines, { rule = true })
        table.insert(lines, { hint, theme.textDim, size = Px(12) })
    end
    ui.Tip(lines)
end

local function RequirementText(recipe)
    local parts = { }
    for _, requirement in ipairs(recipes.Requirements(recipe)) do
        table.insert(parts, ('%s %i'):format(recipes.skillNames[requirement.id], requirement.level))
    end
    return table.concat(parts, ', ')
end

local function OptionSummary(recipe)
    local parts = { }
    for _, ingredient in ipairs(recipes.Grouped(recipe)) do
        table.insert(parts, ('%i %s'):format(ingredient.count, items.ShortName(ingredient.id)))
    end
    local summary = ('Makes %i from %s'):format(recipe.count, table.concat(parts, ', '))
    if recipe.keyItem > 0 then
        summary = summary .. ', key item'
    end
    return summary
end

---------------------------------------------------------------------------
-- plan tab
---------------------------------------------------------------------------

local function DrawEntries(dl, x, y, w, entries)
    local top = y
    local cfg = app.Config()
    -- the entry itself, not its place: the list skips entries whose recipe
    -- is gone, so a place here can point at a different saved entry
    local removeEntry = nil
    for index, item in ipairs(entries) do
        local recipe, entry = item.recipe, item.entry
        local h = Px(50)
        local _, hovered, right = ui.Hit(('plan.e%i'):format(index), x, y, w - Px(200), h)
        local slot = Px(42)
        ui.Slot(dl, x, y + (h - slot) / 2, slot, recipe.result, theme.slotBorder, { count = recipe.count })
        local nx = x + slot + Px(10)
        local nameW = w - (nx - x) - Px(210)
        local name = items.ShortName(recipe.result)
        text.Draw(dl, text.Fit(name, Px(14), false, nameW), nx, y + Px(6), col(0xFFFFFF), Px(14))
        local tier = book.TierText(app.Estimate(recipe))
        local sub = RequirementText(recipe) .. (tier and (', ' .. tier) or '')
        text.Draw(dl, text.Fit(sub, Px(12), false, nameW), nx, y + Px(26), col(theme.textMuted), Px(12))

        local sx = x + w - Px(200)
        local synths = math.floor(tonumber(entry.synths[1]) or 1)
        local value, stepW, stepH, stepped = ui.Stepper(dl, ('plan.synths%i'):format(index), sx, y + (h - Px(22)) / 2, synths, 1, 9999, 1, { minWidth = Px(46) })
        if stepped then
            entry.synths[1] = value
            app.Dirty()
        end
        text.Draw(dl, 'synths', sx + stepW + Px(6), y + (h - Px(13)) / 2 - 1, col(theme.textMuted), Px(13))
        if ui.IconButton(dl, ('plan.remove%i'):format(index), x + w - Px(24), y + (h - Px(24)) / 2, Px(24), ui.CrossGlyph, { tip = 'Remove' }) then
            removeEntry = entry
        end
        if right then
            menu.Request('plan', { itemId = recipe.result, recipes = { recipe } })
        end
        if hovered then
            ItemTip(recipe.result, 'Right-click to set a price.')
        end
        y = y + h + Px(4)
    end
    if removeEntry ~= nil then
        for i, saved in ipairs(cfg.planner.entries) do
            if rawequal(saved, removeEntry) then
                table.remove(cfg.planner.entries, i)
                break
            end
        end
        app.Dirty()
    end
    return y - top
end

local function DrawOptions(dl, x, y, w)
    local cfg = app.Config()
    local plan = cfg.planner
    text.Draw(dl, 'Extra for breaks', x, y + Px(3), col(theme.textSoft), Px(13))
    local lw = text.Width('Extra for breaks', Px(13))
    local value, stepW, _, stepped = ui.Stepper(dl, 'plan.spare', x + lw + Px(8), y, plan.spare[1], 0, 100, 5, { format = function(v) return v .. '%' end })
    if stepped then
        plan.spare[1] = value
        app.Dirty()
    end
    local cx, cy = x + lw + Px(8) + stepW + Px(18), y + Px(2)
    local used = Px(26)
    local function BoxW(label)
        return Px(15) + Px(7) + text.Width(label, Px(13))
    end
    if cx + BoxW('Other bags') + Px(16) + BoxW('Other characters') > x + w then
        -- a narrow planner or big text: the checkboxes get their own line
        cx, cy = x, y + Px(28)
        used = Px(28) + Px(26)
    end
    local changed, cw = ui.Checkbox(dl, 'plan.bags', cx, cy, 'Other bags', plan.useBags)
    if changed then app.Dirty() end
    changed = ui.Checkbox(dl, 'plan.others', cx + cw + Px(16), cy, 'Other characters', plan.useOthers)
    if changed then app.Dirty() end
    return used
end

-- make-or-buy rows, nested the same way as the recipes. key is the path
-- from the queued entry, so every row has its own id even when the same
-- material shows up in more than one place.
local function DrawChoices(dl, x, y, w, recipe, path, depth, parentKey)
    local top = y
    local make = app.Config().planner.make
    for _, ingredient in ipairs(recipes.Grouped(recipe)) do
        local itemId = ingredient.id
        local options = recipes.Options(itemId)
        if options ~= nil and not path[itemId] and depth < 8 then
            local key = parentKey .. '>' .. itemId
            local h = Px(40)
            local indent = depth * Px(22)
            local rx = x + indent
            local _, hovered, right = ui.Hit('plan.c' .. key, rx, y, w - indent - Px(130), h)
            local slot = Px(32)
            ui.Slot(dl, rx, y + (h - slot) / 2, slot, itemId, theme.slotBorder)
            local nx = rx + slot + Px(10)
            local nameW = w - (nx - x) - Px(140)
            text.Draw(dl, text.Fit(items.ShortName(itemId), Px(14), false, nameW), nx, y + Px(2), col(0xFFFFFF), Px(14))
            local held = app.Have(itemId)
            local sub = RequirementText(options[app.ChosenOption(itemId) or 1])
            if held > 0 then
                sub = ('%s, %i held'):format(sub, held)
            end
            if #options > 1 then
                sub = ('%s, %i recipes'):format(sub, #options)
            end
            text.Draw(dl, text.Fit(sub, Px(12), false, nameW), nx, y + Px(20), col(theme.textMuted), Px(12))

            local chosen = app.ChosenOption(itemId)
            local selected = chosen ~= nil and 2 or 1
            local picked = ui.Segmented(dl, 'plan.mb' .. key, x + w - Px(110), y + (h - Px(22)) / 2, { 'Buy', 'Make' }, selected, { width = Px(55) })
            if picked ~= selected then
                make[itemId] = picked == 2 and 1 or nil
                chosen = make[itemId]
                app.Dirty()
            end
            if right then
                menu.Request('plan', { itemId = itemId, recipes = options })
            end
            if hovered then
                ItemTip(itemId, 'Make it yourself and its own materials join the list.')
            end
            y = y + h + Px(2)

            if chosen ~= nil then
                chosen = app.ChosenOption(itemId)
                if #options > 1 then
                    for number, option in ipairs(options) do
                        local oh = Px(22)
                        local ox = rx + Px(42)
                        local clicked, ohover = ui.Hit(('plan.o%s.%i'):format(key, number), ox, y, w - (ox - x), oh)
                        local r = Px(6)
                        local cyc = y + oh / 2
                        dl:AddCircle({ ox + r, cyc }, r, col(ohover and theme.gold or theme.goldDarker), 16, 1.5)
                        if number == chosen then
                            dl:AddCircleFilled({ ox + r, cyc }, r - Px(3), col(theme.gold), 12)
                        end
                        local label = text.Fit(OptionSummary(option), Px(12.5), false, w - (ox - x) - Px(24))
                        text.Draw(dl, label, ox + r * 2 + Px(8), y + (oh - Px(12.5)) / 2 - 1, col(number == chosen and theme.textSoft or theme.textMuted), Px(12.5))
                        if clicked then
                            make[itemId] = number
                            chosen = number
                            app.Dirty()
                        end
                        y = y + oh
                    end
                    y = y + Px(2)
                end
                path[itemId] = true
                y = y + DrawChoices(dl, x, y, w, options[chosen], path, depth + 1, key)
                path[itemId] = nil
            end
        end
    end
    return y - top
end

local function DrawBuy(dl, x, y, w, result)
    local top = y
    local rows = { }
    for _, row in ipairs(result.buy) do
        table.insert(rows, row)
    end
    table.sort(rows, function(a, b)
        local aCrystal, bCrystal = IsCrystal(a.id), IsCrystal(b.id)
        if aCrystal ~= bCrystal then
            return aCrystal
        end
        local aName, bName = items.Name(a.id), items.Name(b.id)
        if aName ~= bName then
            return aName < bName
        end
        return a.id < b.id
    end)

    if #rows == 0 then
        text.Draw(dl, 'Nothing to buy.', x, y, col(theme.textDim), Px(13))
        return Px(20)
    end

    -- name and where | have bar | buy count over how to buy, cost
    local haveX = x + w * 0.36
    local haveW = Px(84)
    local rightX = haveX + haveW + Px(14)
    local small = Px(11.5)
    text.Draw(dl, 'Item', x, y, col(theme.textDim), small)
    text.Draw(dl, 'Have', haveX, y, col(theme.textDim), small)
    text.DrawRight(dl, 'Buy', x + w - Px(2), y, col(theme.textDim), small)
    y = y + Px(18)

    local total, unpriced = 0, 0
    for _, row in ipairs(rows) do
        local h = Px(40)
        local _, hovered, right = ui.Hit('plan.buy' .. row.id, x, y, w, h)
        if hovered then
            ui.Rect(dl, x, y, x + w, y + h, col(theme.gold, 0.06), Px(3))
        end
        local slot = Px(32)
        local covered = row.buy == 0
        ui.Slot(dl, x, y + (h - slot) / 2, slot, row.id, covered and theme.green or theme.slotBorder)
        local nx = x + slot + Px(8)
        local nameW = haveX - nx - Px(8)
        text.Draw(dl, text.Fit(items.ShortName(row.id), Px(13.5), false, nameW), nx, y + Px(3), col(covered and theme.green or 0xFFFFFF), Px(13.5))
        text.Draw(dl, text.Fit(WhereText(row.id), Px(11.5), false, nameW), nx, y + Px(21), col(theme.textMuted), Px(11.5))

        local held = math.min(row.need, row.used)
        text.Draw(dl, ('%i / %i'):format(held, row.need), haveX, y + Px(3), col(theme.textSoft), Px(12.5), true)
        ui.Bar(dl, haveX, y + Px(23), haveW, Px(7), row.need > 0 and held / row.need or 1, covered and theme.fills.mp or theme.fills.tp)

        local buyText = covered and 'none' or ('buy %i'):format(row.buy)
        text.DrawRight(dl, buyText, x + w - Px(2), y + Px(2), col(covered and theme.green or 0xFFFFFF), Px(14), true)
        local cost = prices.Cost(row.id, row.buy)
        if cost ~= nil and row.buy > 0 then
            total = total + cost
            text.Draw(dl, ('%s g'):format(prices.Format(cost)), rightX, y + Px(4), col(theme.goldDark), Px(12))
        elseif row.buy > 0 then
            unpriced = unpriced + 1
        end
        if not covered then
            local how = planner.StackText(row.buy, items.StackSize(row.id))
            text.DrawRight(dl, text.Fit(how, Px(11.5), false, x + w - rightX), x + w - Px(2), y + Px(22), col(theme.textMuted), Px(11.5))
        end

        if right then
            menu.Request('plan', { itemId = row.id, recipes = recipes.Options(row.id) })
        end
        if hovered then
            ItemTip(row.id, 'Right-click to set a price.')
        end
        y = y + h + Px(2)
    end

    y = y + Px(4)
    if total > 0 or unpriced > 0 then
        local label
        if total > 0 then
            label = ('Estimated cost: %s gil'):format(prices.Format(total))
            if unpriced > 0 then
                label = label .. (', %i item%s without a price'):format(unpriced, unpriced == 1 and '' or 's')
            end
        else
            label = 'Right-click an item to set its price and see the cost.'
        end
        text.Draw(dl, label, x, y, col(total > 0 and theme.gold or theme.textDim), Px(12.5), total > 0)
        y = y + Px(22)
    end
    return y - top
end

local function DrawSynths(dl, x, y, w, result)
    local top = y
    local rows = { }
    for _, row in ipairs(result.made) do
        table.insert(rows, { id = row.id, recipe = row.recipe, synths = row.synths, output = row.output, leftover = row.leftover })
    end
    for _, row in ipairs(result.top) do
        table.insert(rows, { id = row.recipe.result, recipe = row.recipe, synths = row.synths, output = row.output, queued = true })
    end

    for index, row in ipairs(rows) do
        local h = Px(40)
        local _, hovered, right = ui.Hit(('plan.s%i'):format(index), x, y, w, h)
        text.DrawCenter(dl, tostring(index), x + Px(8), y + (h - Px(13)) / 2 - 1, col(theme.textMuted), Px(13), true)
        local slot = Px(32)
        local sx = x + Px(20)
        ui.Slot(dl, sx, y + (h - slot) / 2, slot, row.id, theme.slotBorder)
        local nx = sx + slot + Px(10)
        local estimate = app.Estimate(row.recipe)
        local chip, rgb = book.TierText(estimate)
        local chipW = chip and ui.ChipWidth(chip) or 0
        local nameW = w - (nx - x) - chipW - Px(16)
        local name = items.ShortName(row.id)
        text.Draw(dl, text.Fit(name, Px(14), false, nameW - Px(26)), nx, y + Px(2), col(estimate and estimate.underCap and theme.amber or 0xFFFFFF), Px(14))
        local main = recipes.MainCraft(row.recipe)
        if main ~= nil then
            local ex = nx + math.min(text.Width(name, Px(14)), nameW - Px(26)) + Px(6)
            ui.Emblem(dl, ex, y + Px(2), Px(16), main)
        end
        local sub
        if row.synths == 0 then
            sub = 'covered by what you hold'
        else
            sub = ('%i synth%s, makes %i'):format(row.synths, row.synths == 1 and '' or 's', row.output)
        end
        if row.queued then
            sub = sub .. ', queued'
        elseif (row.leftover or 0) > 0 then
            sub = ('%s, %i left over'):format(sub, row.leftover)
        end
        text.Draw(dl, text.Fit(sub, Px(12), false, nameW), nx, y + Px(21), col(theme.textMuted), Px(12))
        if chip ~= nil then
            ui.Chip(dl, x + w - chipW - Px(4), y + (h - Px(17)) / 2, chip, rgb)
        end
        if right then
            menu.Request('plan', { itemId = row.id, recipes = recipes.Options(row.id) })
        end
        if hovered then
            ItemTip(row.id, hq.Describe(estimate, recipes.skillNames))
        end
        y = y + h + Px(2)
    end
    return y - top
end

local function DrawKeyItems(dl, x, y, w, result)
    local list = { }
    for keyItem in pairs(result.keyItems) do
        table.insert(list, keyItem)
    end
    if #list == 0 then
        return 0
    end
    table.sort(list)
    local top = y
    y = y + ui.Section(dl, x, y, w, 'Key items needed') + Px(4)
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local res = AshitaCore:GetResourceManager()
    for _, keyItem in ipairs(list) do
        local has = player:HasKeyItem(keyItem)
        local name = res:GetString('keyitems.names', keyItem) or ('key item %i'):format(keyItem)
        if has then
            ui.CheckGlyph(dl, x, y + Px(2), Px(13), col(theme.green))
        else
            ui.CrossGlyph(dl, x, y + Px(2), Px(13), col(theme.red))
        end
        text.Draw(dl, name, x + Px(20), y, col(has and theme.textSoft or theme.red), Px(13))
        y = y + Px(20)
    end
    return y - top + Px(6)
end

local function DrawPlanTab(dl, x, y, w)
    local top = y
    local result, entries = app.PlanResult()
    if #entries == 0 then
        text.Draw(dl, 'Nothing queued yet.', x, y, col(theme.textSoft), Px(13.5))
        return Px(20) + ui.Paragraph(dl, x, y + Px(20), w, 'Right-click a recipe in HCrafter and pick Add to Resource Planner.', theme.textDim, Px(12.5))
    end

    y = y + DrawEntries(dl, x, y, w, entries) + Px(4)
    y = y + DrawOptions(dl, x, y, w) + Px(12)

    local choicesTop = y
    y = y + ui.Section(dl, x, y, w, 'Make or buy') + Px(6)
    local before = y
    for index, item in ipairs(entries) do
        y = y + DrawChoices(dl, x, y, w, item.recipe, { [item.recipe.result] = true }, 0, 'e' .. index)
    end
    if y == before then
        y = choicesTop
    else
        y = y + Px(8)
    end

    y = y + ui.Section(dl, x, y, w, 'To buy') + Px(6)
    y = y + DrawBuy(dl, x, y, w, result) + Px(8)
    y = y + ui.Section(dl, x, y, w, 'Synths, in order') + Px(6)
    y = y + DrawSynths(dl, x, y, w, result) + Px(8)
    y = y + DrawKeyItems(dl, x, y, w, result)

    if next(result.loops) ~= nil then
        y = y + ui.Paragraph(dl, x, y, w, 'Some materials loop back into their own recipe, so they are bought instead.', theme.textDim, Px(12))
    end
    y = y + ui.Paragraph(dl, x, y, w, 'Other characters count as of their last save.', theme.textDim, Px(12))
    return y - top
end

---------------------------------------------------------------------------
-- skill-up tab
---------------------------------------------------------------------------

local cache = { key = nil }
local measured = { at = nil, key = nil }

-- your measured rate, worked out at most once a second
local function Measured(craftId, skill)
    local now = os.clock()
    local key = craftId .. '|' .. tostring(skill >= 50) .. '|' .. tostring(app.Cap(craftId))
    if measured.key ~= key or measured.at == nil or now - measured.at > 1 then
        measured.key = key
        measured.at = now
        measured.ups, measured.chances = skillup.Measured(craftId, history.List(), skill, app.Cap(craftId))
    end
    return measured.ups, measured.chances
end

local function SkillupOptions(craftId)
    local cfg = app.Config()
    local opts = { breakRule = cfg.skillup.breakRule[1] }
    local skill = app.Skill(craftId)
    local ups, chances = Measured(craftId, skill)
    if cfg.skillup.useMeasured[1] and chances >= skillup.minMeasured then
        opts.rate = ups / chances
    end
    return opts, ups, chances
end

local function Compute(craftId, target)
    local cfg = app.Config()
    local opts, ups, chances = SkillupOptions(craftId)
    local key = table.concat({
        craftId, app.Skill(craftId), target, opts.breakRule, tostring(opts.rate),
        app.Gear(craftId), app.Support(craftId), tostring(app.Cap(craftId)),
    }, '|')
    for c = 1, 8 do
        key = key .. '|' .. app.Skill(c) .. ':' .. app.Gear(c)
    end
    if cache.key ~= key then
        cache.key = key
        cache.ideas = skillup.Recommend(craftId, app.Ctx(), opts, planui.maxIdeas)
        cache.steps, cache.total, cache.stuckAt = skillup.Plan(craftId, target, app.Ctx(), opts)
        cache.ups, cache.chances = ups, chances
        cache.rate = opts.rate
    end
    return cache
end

local function MaterialCost(recipe)
    local total = prices.Cost(recipe.crystal, 1)
    if total == nil then
        return nil
    end
    for _, ingredient in ipairs(recipes.Grouped(recipe)) do
        local cost = prices.Cost(ingredient.id, ingredient.count)
        if cost == nil then
            return nil
        end
        total = total + cost
    end
    return total
end

local function DrawSkillupTab(dl, x, y, w)
    local top = y
    local cfg = app.Config()
    local craftId = math.max(1, math.min(8, cfg.skillup.craft[1]))

    -- craft picker
    local size = Px(32)
    local cell = Px(40)
    local gap = (w - cell * 8) / 7
    for c = 1, 8 do
        local cx = x + (c - 1) * (cell + gap)
        local clicked, hovered = ui.Hit(('plan.craft%i'):format(c), cx, y, cell, size + Px(16))
        ui.Emblem(dl, cx + (cell - size) / 2, y, size, c, { ring = c == craftId, dim = c ~= craftId and not hovered })
        text.DrawCenter(dl, ('%.1f'):format(app.Skill(c)), cx + cell / 2, y + size + Px(2), col(c == craftId and theme.gold or theme.textMuted), Px(11.5), c == craftId)
        if clicked and c ~= craftId then
            cfg.skillup.craft[1] = c
            cfg.skillup.target[1] = 0
            craftId = c
            app.Dirty()
        end
        if hovered then
            ui.Tip(recipes.skillNames[c])
        end
    end
    y = y + size + Px(24)

    local skill = app.Skill(craftId)
    local cap = app.Cap(craftId)
    local rank = cfg.ranks[craftId] and cfg.ranks[craftId][1] or -1
    local title = ('%s %.1f'):format(recipes.skillNames[craftId], skill)
    text.Draw(dl, title, x, y, col(0xFFFFFF), Px(16), true)
    local rankText = rank >= 0 and ('%s, cap %i'):format(recipes.rankNames[rank] or '?', cap) or 'rank shows after you zone once'
    text.Draw(dl, rankText, x + text.Width(title, Px(16), true) + Px(10), y + Px(3), col(theme.textMuted), Px(12.5))
    y = y + Px(26)

    if cap ~= nil and skill >= cap then
        -- 100 is HorizonXI's cap, with no rank above it, so there is
        -- nothing to suggest
        if cap < 100 then
            y = y + ui.Paragraph(dl, x, y, w, ('You are at your rank cap of %i. Rank up at your guild to keep going.'):format(cap), theme.amber, Px(13))
        end
        return y - top
    end

    -- target
    local whole = math.floor(skill + 0.0001)
    local high = cap or 110
    local target = cfg.skillup.target[1]
    if target == nil or target <= whole or target > high then
        target = math.min(high, whole + 1)
    end
    text.Draw(dl, 'Skill up to', x, y + Px(3), col(theme.textSoft), Px(13))
    -- the stepper follows its label at any text size and font
    local targetX = x + math.max(Px(80), text.Width('Skill up to', Px(13)) + Px(8))
    local value, stepW, _, stepped = ui.Stepper(dl, 'plan.target', targetX, y, target, whole + 1, high, 1)
    if stepped then
        cfg.skillup.target[1] = value
        target = value
        app.Dirty()
    end

    -- break rule
    local rx = targetX + stepW + Px(24)
    local ruleX = rx + math.max(Px(52), text.Width('Breaks', Px(13)) + Px(8))
    local ruleW = text.Width('Half rate', Px(12.5)) + text.Width('Same rate', Px(12.5)) + Px(36)
    if ruleX + ruleW > x + w then
        -- no room after the target: the break rule gets its own line
        y = y + math.max(Px(28), text.H(Px(13)) + Px(12))
        rx = x
        ruleX = x + math.max(Px(52), text.Width('Breaks', Px(13)) + Px(8))
    end
    text.Draw(dl, 'Breaks', rx, y + Px(3), col(theme.textSoft), Px(13))
    local rule = cfg.skillup.breakRule[1] == 2 and 2 or 1
    local picked = ui.Segmented(dl, 'plan.breakrule', ruleX, y, { 'Half rate', 'Same rate' }, rule)
    if picked ~= rule then
        cfg.skillup.breakRule[1] = picked
        app.Dirty()
    end
    y = y + Px(30)

    local data = Compute(craftId, target)
    local measuredLabel
    if data.chances > 0 then
        measuredLabel = ('Use my rate: %i of %i synths (%i%%)'):format(data.ups, data.chances, math.floor(data.ups / data.chances * 100 + 0.5))
    else
        measuredLabel = 'Use my rate (no synths of this craft yet)'
    end
    local changed = ui.Checkbox(dl, 'plan.measured', x, y, measuredLabel, cfg.skillup.useMeasured)
    if changed then
        app.Dirty()
    end
    y = y + Px(22)
    if cfg.skillup.useMeasured[1] and data.chances < skillup.minMeasured then
        y = y + ui.Paragraph(dl, x, y, w, ('Your own rate needs %i synths that could skill up. Until then the era rate is used.'):format(skillup.minMeasured), theme.textDim, Px(11.5))
    end
    local rate = data.rate or skillup.BaseChance(skill)
    local rateText = data.rate and 'your measured rate' or (skill < 50 and 'era rate below 50' or 'era rate from 50')
    text.Draw(dl, ('Skill-up chance on a good synth: %i%%, %s.'):format(math.floor(rate * 100 + 0.5), rateText), x, y, col(theme.textMuted), Px(12))
    y = y + Px(22)

    -- estimate
    y = y + ui.Section(dl, x, y, w, 'Estimate') + Px(6)
    if data.total ~= nil then
        local total = math.floor(data.total + 0.5)
        text.Draw(dl, ('About %i synths from %.1f to %i.0'):format(total, skill, target), x, y, col(theme.gold), Px(15), true)
        y = y + Px(24)
        for i, step in ipairs(data.steps) do
            if i > planui.maxSteps then
                text.Draw(dl, ('and %i more levels'):format(#data.steps - planui.maxSteps), x, y, col(theme.textDim), Px(12))
                y = y + Px(18)
                break
            end
            local line = ('%.1f to %.1f: %s, about %i synths'):format(step.from, step.to, items.ShortName(step.recipe.result), math.floor(step.synths + 0.5))
            dl:AddCircleFilled({ x + Px(4), y + Px(8) }, Px(3), col(bandColors[step.band] or theme.textDim), 8)
            text.Draw(dl, text.Fit(line, Px(12.5), false, w - Px(14)), x + Px(14), y, col(theme.textSoft), Px(12.5))
            y = y + Px(19)
        end
        y = y + Px(2) + ui.Paragraph(dl, x, y + Px(2), w, 'Uses the best recipe at each level. Real results vary.', theme.textDim, Px(11.5)) + Px(4)
    else
        local at = data.stuckAt or skill
        y = y + ui.Paragraph(dl, x, y, w, ('No recipe in reach gives skill-ups at %.1f.'):format(at), theme.amber, Px(13)) + Px(4)
    end

    -- ideas
    y = y + ui.Section(dl, x, y, w, 'Best recipes now') + Px(6)
    if #data.ideas == 0 then
        y = y + ui.Paragraph(dl, x, y, w, 'Nothing within 8 levels gives skill-ups.', theme.textDim, Px(13))
        return y - top
    end
    for index, idea in ipairs(data.ideas) do
        local recipe = idea.recipe
        local h = Px(42)
        local clicked, hovered, right = ui.Hit(('plan.idea%i'):format(index), x, y, w, h)
        if hovered then
            ui.Rect(dl, x, y, x + w, y + h, col(theme.gold, 0.06), Px(3))
        end
        local slot = Px(34)
        ui.Slot(dl, x, y + (h - slot) / 2, slot, recipe.result, bandColors[idea.band] or theme.slotBorder)
        local nx = x + slot + Px(10)
        local band = skillup.bandNames[idea.band]
        local chipW = ui.ChipWidth(band)
        local nameW = w - (nx - x) - chipW - Px(12)
        local name = items.ShortName(recipe.result)
        local options = recipes.Options(recipe.result)
        if options ~= nil and #options > 1 then
            name = ('%s (recipe %i)'):format(name, recipes.OptionNumber(recipe))
        end
        text.Draw(dl, text.Fit(name, Px(14), false, nameW), nx, y + Px(3), col(0xFFFFFF), Px(14))
        local per = idea.synthsPerLevel
        local sub = ('%s %i (+%i), success %i%%, about %i synths per level'):format(
            recipes.skillAbbr[craftId], idea.level, idea.gap, math.floor(idea.success * 100 + 0.5), math.floor(per + 0.5))
        local cost = MaterialCost(recipe)
        if cost ~= nil then
            sub = ('%s, %s g a synth'):format(sub, prices.Format(cost))
        end
        if recipe.keyItem > 0 then
            sub = sub .. ', key item'
        end
        text.Draw(dl, text.Fit(sub, Px(12), false, nameW), nx, y + Px(22), col(theme.textMuted), Px(12))
        ui.Chip(dl, x + w - chipW - Px(4), y + (h - Px(17)) / 2, band, bandColors[idea.band])
        if clicked and planui.OpenInBook ~= nil then
            planui.OpenInBook(recipe)
        end
        if right then
            menu.Request('plan', { itemId = recipe.result, recipes = { recipe } })
        end
        if hovered then
            local lines = {
                { item = recipe.result, items.ShortName(recipe.result), theme.gold, true },
                { rule = true },
                { RequirementText(recipe), theme.textSoft },
                { ('Expected skill per synth: %.3f'):format(idea.gain), theme.textSoft },
                { rule = true },
                { 'Click to open it in the recipe book. Right-click to plan it.', theme.textDim, size = Px(12) },
            }
            ui.Tip(lines)
        end
        y = y + h + Px(2)
    end
    y = y + Px(4) + ui.Paragraph(dl, x, y + Px(4), w, 'Optimal: few breaks. Manageable: breaks are common. Risky: most synths break.', theme.textDim, Px(11.5))
    return y - top
end

---------------------------------------------------------------------------
-- the window
---------------------------------------------------------------------------

function planui.Draw()
    local cfg = app.Config()
    if not cfg.planner.visible[1] then
        return
    end
    local name = 'Resource Planner###hcrafter.planner'
    if (tonumber(cfg.planner.pos[1]) or -1) < 0 then
        -- the first time: just right of the recipe book, kept on screen
        local display = imgui.GetIO().DisplaySize
        local w = ui.WindowWidth(cfg.planner, planui.limits)
        local bookX = tonumber(cfg.book.pos[1]) or 100
        local besideBook = bookX + ui.WindowWidth(cfg.book, book.limits) + Px(16)
        cfg.planner.pos[1] = math.max(0, math.min(besideBook, display.x - w - Px(16)))
        cfg.planner.pos[2] = math.max(0, tonumber(cfg.book.pos[2]) or 100)
    end
    local open, dl, x, y = ui.BeginWindow(name, cfg.planner)
    if not open then
        ui.EndWindow(name)
        return
    end

    local w = ui.WindowWidth(cfg.planner, planui.limits)
    local clicked, titleH = ui.TitleBar(dl, 'plan', x, y, w, 'Resource Planner', ui.ListGlyph, {
        { key = 'list', draw = ui.FlagGlyph, tip = 'Shopping list', active = cfg.tracker.visible[1] },
        { key = 'close', draw = ui.CrossGlyph, tip = 'Close' },
    })
    if clicked == 'list' then
        cfg.tracker.visible[1] = not cfg.tracker.visible[1]
        app.Dirty()
    elseif clicked == 'close' then
        cfg.planner.visible[1] = false
        app.Dirty()
    end

    local cy = y + titleH + Px(10)
    local tab, tabH = ui.Tabs(dl, 'plan', x + Px(14), cy, w - Px(28), { 'Plan', 'Skill-up' }, cfg.planner.tab[1])
    if tab ~= cfg.planner.tab[1] then
        cfg.planner.tab[1] = tab
        app.Dirty()
    end
    cy = cy + tabH + 1

    local display = imgui.GetIO().DisplaySize
    local maxH = math.max(Px(200), display.y * 0.78 - (cy - y))
    local fixedH = ui.FixedBodyHeight(cfg.planner, planui.limits, cy - y)
    imgui.SetCursorScreenPos({ x, cy })
    local bdl, bx, by, bw, bh = ui.BeginBody('hcrafter.planner.body', w, maxH, fixedH)
    local padX = Px(14)
    local inner = bw - padX * 2
    local used
    if tab == 2 then
        used = DrawSkillupTab(bdl, bx + padX, by + Px(12), inner)
    else
        used = DrawPlanTab(bdl, bx + padX, by + Px(12), inner)
    end
    ui.EndBody('hcrafter.planner.body', bx, by, bw, used + Px(12) + Px(14))
    local h = cy - y + bh + Px(ui.footerH)
    if ui.ResizeGrip(dl, 'plan', x, y, w, h, cfg.planner, planui.limits) then
        app.Dirty()
    end
    menu.Draw('plan')
    ui.EndWindow(name, x, y, w, h)
end

return planui
