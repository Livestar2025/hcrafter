-- the recipe book window: Recipes, History and Settings tabs in cool mode.
-- the recipe list and history are adapted from the crafty component of
-- xitools by lin (GPL-3.0). part of HCrafter, GPL-3.0.
require('common')
local imgui = require('imgui')
local guard = require('hc.guard')
local theme = require('hc.theme')
local text = require('hc.text')
local ui = require('hc.ui')
local icons = require('hc.icons')
local items = require('hc.items')
local recipes = require('hc.recipes')
local hq = require('hc.hq')
local stock = require('hc.stock')
local history = require('hc.history')
local prices = require('hc.prices')
local gear = require('hc.gear')
local skillup = require('hc.skillup')
local app = require('hc.app')
local menu = require('hc.menu')
local sounds = require('hc.sounds')
local fanfareMod = require('hc.fanfare')

local book = {
    width = 520,
    -- the sizes a player can drag the book to, in unscaled pixels
    limits = { defaultW = 520, minW = 460, maxW = 1400, minH = 240, maxH = 2400 },
    maxResults = 32,
    maxHistory = 60,
}

local col = theme.col
local Px = ui.Px

local state = {
    filter = { '' },
    open = { },        -- recipe id -> true for open recipe cards
    expanded = { },    -- material path -> true
    option = { },      -- material path -> chosen recipe number
    lastFilter = nil,
}

-- the synth effect's result. LandSandBoat sends 2 for every HQ tier, so 2
-- reads as HQ, not HQ1.
local resultNames = {
    [0] = 'NQ',
    [1] = 'Break',
    [2] = 'HQ',
    [3] = 'HQ2',
    [4] = 'HQ3',
}

local bandColors = {
    none = theme.textDim,
    optimal = theme.green,
    costly = theme.amber,
    danger = theme.red,
}

---------------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------------

local function Where(itemId)
    -- "+5 in Mog Safe", "+3 on Packrat" or "+9 in 3 places"
    local lines = stock.Locations(itemId)
    local total, places, first = 0, 0, nil
    for _, line in ipairs(lines) do
        if line.text ~= 'On you' and line.count > 0 then
            total = total + line.count
            places = places + 1
            first = first or line
        end
    end
    if total == 0 then
        return nil
    end
    if places == 1 then
        local name, bag = first.text:match('^(%w+), (.*)$')
        if name ~= nil then
            return ('+%i on %s'):format(total, name)
        end
        return ('+%i in %s'):format(total, first.text)
    end
    return ('+%i in %i places'):format(total, places)
end

local function DateText(saved)
    return os.date('%b %d', saved)
end

-- the hover card for an item: where it is, its price, and a hint
local function ItemTip(itemId, hint)
    local lines = { { item = itemId, items.ShortName(itemId), theme.gold, true } }
    table.insert(lines, { rule = true })
    for _, line in ipairs(stock.Locations(itemId)) do
        local label = line.text
        if line.saved ~= nil then
            label = ('%s (saved %s)'):format(line.text, DateText(line.saved))
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

local function Requirement(craftId, level)
    local skill = app.Skill(craftId)
    local bonus = app.Gear(craftId) + app.Support(craftId)
    local met = math.floor(skill + 0.0001) + bonus >= level
    return met, level - math.floor(skill + 0.0001) - bonus
end

-- material status: 'covered' on you, 'elsewhere' counting bags and
-- characters, or 'short'
local function Status(itemId, need)
    local onYou, inBags, onOthers = stock.Counts(itemId)
    if onYou >= need then
        return 'covered', onYou
    elseif onYou + inBags + onOthers >= need then
        return 'elsewhere', onYou
    end
    return 'short', onYou
end

local statusRgb = {
    covered = theme.green,
    elsewhere = theme.amber,
    short = theme.slotBorder,
}

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

local function RequirementText(recipe)
    local parts = { }
    for _, requirement in ipairs(recipes.Requirements(recipe)) do
        table.insert(parts, ('%s %i'):format(recipes.skillNames[requirement.id], requirement.level))
    end
    return table.concat(parts, ', ')
end

-- the HQ chip text for an estimate: "HQ T1, 1 in 16"
local function TierText(estimate)
    if estimate == nil then
        return nil, theme.textDim
    end
    if estimate.unknown then
        return 'no estimate', theme.textDim
    end
    if estimate.underCap then
        return ('%i under cap, %i%%'):format(-estimate.margin, estimate.success), theme.amber
    end
    if estimate.ring ~= nil then
        return ('%s, no HQ (ring)'):format(estimate.tier.name), theme.amber
    end
    return ('HQ %s, 1 in %i'):format(estimate.tier.name, estimate.tier.odds), theme.gold
end

book.TierText = TierText

---------------------------------------------------------------------------
-- recipes tab
---------------------------------------------------------------------------

local searchCache = { }
local searchCacheSize = 0

local function FilterRecipes(filter, byMaterial)
    local key = (byMaterial and 'm|' or 'r|') .. filter
    local found = searchCache[key]
    if found ~= nil then
        return found
    end
    found = { }
    if filter ~= '' then
        for _, recipe in ipairs(recipes.all) do
            if byMaterial then
                for _, ingredient in ipairs(recipes.Grouped(recipe)) do
                    if items.Matches(ingredient.id, filter) then
                        table.insert(found, recipe)
                        break
                    end
                end
            elseif items.Matches(recipe.result, filter) then
                table.insert(found, recipe)
            end
        end
    end
    if searchCacheSize > 200 then
        searchCache, searchCacheSize = { }, 0
    end
    searchCache[key] = found
    searchCacheSize = searchCacheSize + 1
    return found
end

-- recent distinct recipes from your history
local function RecentRecipes(limit)
    local list, seen = { }, { }
    for _, entry in ipairs(history.List()) do
        local recipe = entry.recipe and recipes.byId[entry.recipe] or nil
        if recipe == nil and entry.item ~= nil then
            local options = recipes.Options(entry.item)
            recipe = options and options[1] or nil
        end
        if recipe ~= nil and not seen[recipe.id] then
            seen[recipe.id] = true
            table.insert(list, recipe)
            if #list >= limit then
                break
            end
        end
    end
    return list
end

local function DrawEmblems(dl, x, y, w)
    local cfg = app.Config()
    local size = Px(36)
    local cell = Px(44)
    local gap = (w - cell * 8) / 7
    for craftId = 1, 8 do
        local cx = x + (craftId - 1) * (cell + gap)
        local ex = cx + (cell - size) / 2
        local skill = app.Skill(craftId)
        local cap = app.Cap(craftId)
        local capped = (cfg.capped[craftId] and cfg.capped[craftId][1]) or (cap ~= nil and skill >= cap)
        local clicked, hovered = ui.Hit(('book.emblem%i'):format(craftId), cx, y, cell, size + Px(18))
        ui.Emblem(dl, ex, y, size, craftId, { ring = capped })
        if gear.HasImagery(craftId) then
            ui.StarGlyph(dl, ex + size - Px(3), y + Px(3), Px(5), col(theme.blue))
        end
        local label = ('%.1f'):format(skill)
        text.DrawCenter(dl, label, cx + cell / 2, y + size + Px(3), col(capped and theme.gold or 0xFFFFFF), Px(12), true)
        if clicked then
            cfg.planner.visible[1] = true
            cfg.planner.tab[1] = 2
            cfg.skillup.craft[1] = craftId
            app.Dirty()
        end
        if hovered then
            local lines = { { recipes.skillNames[craftId], theme.gold, true, right = label } }
            local rank = cfg.ranks[craftId] and cfg.ranks[craftId][1] or -1
            if rank >= 0 then
                table.insert(lines, { ('%s, cap %i'):format(recipes.rankNames[rank] or ('rank ' .. rank), recipes.RankCap(rank)), theme.textSoft })
            else
                table.insert(lines, { 'Rank shows after you zone once', theme.textDim })
            end
            local bonus = app.Gear(craftId)
            if bonus ~= 0 then
                table.insert(lines, { ('Gear +%i'):format(bonus), theme.textSoft })
            end
            if gear.HasImagery(craftId) then
                table.insert(lines, { ('Imagery on, +%i counted'):format(app.Support(craftId)), theme.blue })
            end
            table.insert(lines, { rule = true })
            table.insert(lines, { 'Click for skill-up ideas', theme.textDim, size = Px(12) })
            ui.Tip(lines)
        end
    end
    return size + Px(18)
end

local function DrawSearch(dl, x, y, w)
    local cfg = app.Config()
    -- the box is imgui's own, in Ashita's font, so it is at least that tall
    local lineH = imgui.GetTextLineHeight()
    local h = math.max(Px(30), lineH + Px(6))
    local checkW = text.Width('Materials', Px(13)) + Px(15) + Px(7)
    local boxW = w - checkW - Px(12)
    ui.Rect(dl, x, y, x + boxW, y + h, col(theme.bgDark, 0.75), Px(3))
    ui.Outline(dl, x, y, x + boxW, y + h, col(theme.border), Px(3), 1)
    ui.SearchGlyph(dl, x + Px(9), y + (h - Px(14)) / 2, Px(14), col(theme.goldDark))

    local padY = math.max(0, (h - lineH) / 2 - 1)
    guard.PushStyleColor(ImGuiCol_FrameBg, { 0, 0, 0, 0 })
    guard.PushStyleColor(ImGuiCol_FrameBgHovered, { 0, 0, 0, 0 })
    guard.PushStyleColor(ImGuiCol_FrameBgActive, { 0, 0, 0, 0 })
    guard.PushStyleColor(ImGuiCol_Text, theme.rgba(0xFFFFFF, 1))
    guard.PushStyleVar(ImGuiStyleVar_FramePadding, { Px(4), padY })
    imgui.SetCursorScreenPos({ x + Px(28), y })
    imgui.SetNextItemWidth(boxW - Px(34))
    imgui.InputText('##hcrafter.search', state.filter, 256)
    guard.PopStyleVar(1)
    guard.PopStyleColor(4)
    if state.filter[1] == '' then
        text.Draw(dl, 'Search recipes', x + Px(32), y + (h - Px(13)) / 2 - 1, col(theme.textDim), Px(13), false, false)
    end

    local changed = ui.Checkbox(dl, 'book.bymaterial', x + boxW + Px(12), y + (h - Px(17)) / 2, 'Materials', cfg.searchMaterials)
    if changed then
        app.Dirty()
    end
    return h
end

local DrawMaterials

-- the requirement line inside an open sub-recipe: emblem, craft and level,
-- a check or cross, then the HQ chip
local function DrawRecipeLine(dl, x, y, w, recipe)
    local h = Px(26)
    local cx = x
    local estimate = app.Estimate(recipe)
    local list = recipes.Requirements(recipe)
    for i, requirement in ipairs(list) do
        local label = ('%s %i'):format(recipes.skillNames[requirement.id], requirement.level)
        -- keep room for "+n more" while more requirements follow. a placed
        -- requirement takes 8 more than the check below counts.
        local more = i < #list and (text.Width(('+%i more'):format(#list - i), Px(12)) + Px(8)) or 0
        if cx + Px(18) + Px(6) + text.Width(label, Px(13)) + Px(18) + more > x + w then
            text.Draw(dl, ('+%i more'):format(#list - i + 1), cx, y + (h - Px(12)) / 2 - 1, col(theme.textMuted), Px(12))
            return h
        end
        ui.Emblem(dl, cx, y + (h - Px(18)) / 2, Px(18), requirement.id)
        cx = cx + Px(18) + Px(6)
        text.Draw(dl, label, cx, y + (h - Px(13)) / 2 - 1, col(0xFFFFFF), Px(13))
        cx = cx + text.Width(label, Px(13)) + Px(5)
        local met = Requirement(requirement.id, requirement.level)
        if met then
            ui.CheckGlyph(dl, cx, y + (h - Px(13)) / 2, Px(13), col(theme.green))
        else
            ui.CrossGlyph(dl, cx, y + (h - Px(13)) / 2, Px(13), col(theme.red))
        end
        cx = cx + Px(13) + Px(8)
    end
    local chip, rgb = TierText(estimate)
    if chip ~= nil and cx + ui.ChipWidth(chip) < x + w then
        local cw = ui.Chip(dl, cx, y + (h - Px(17)) / 2, chip, rgb)
        cx = cx + cw + Px(6)
        if estimate ~= nil and not estimate.unknown and not estimate.underCap then
            local over = ('%i over cap'):format(estimate.margin)
            if cx + text.Width(over, Px(12)) < x + w then
                text.Draw(dl, over, cx, y + (h - Px(12)) / 2 - 1, col(theme.textMuted), Px(12))
            end
        end
    end
    return h
end

-- the open block under a material that can be crafted
local function DrawSubRecipe(dl, x, y, w, itemId, options, key, path, depth)
    local top = y
    local indent = Px(14)
    local innerX = x + indent + Px(12)
    local innerW = w - indent - Px(12)
    y = y + Px(4)

    local chosen = math.max(1, math.min(#options, state.option[key] or 1))
    if #options > 1 then
        -- "Recipe 1, Recipe 2" when they fit, plain numbers when they don't
        local labels, total = { }, 0
        for i = 1, #options do
            labels[i] = ('Recipe %i'):format(i)
            total = total + text.Width(labels[i], Px(12.5)) + Px(18)
        end
        if total > innerW then
            for i = 1, #options do
                labels[i] = tostring(i)
            end
        end
        local picked, segW, segH = ui.Segmented(dl, 'book.opt' .. key, innerX, y, labels, chosen)
        if picked ~= chosen then
            state.option[key] = picked
            chosen = picked
        end
        y = y + segH + Px(4)
        local summary = text.Fit(OptionSummary(options[chosen]), Px(12), false, innerW)
        text.Draw(dl, summary, innerX, y, col(theme.textMuted), Px(12))
        y = y + Px(17)
    end

    local recipe = options[chosen]
    y = y + DrawRecipeLine(dl, innerX, y, innerW, recipe)
    if recipe.keyItem > 0 then
        local has = AshitaCore:GetMemoryManager():GetPlayer():HasKeyItem(recipe.keyItem)
        local name = AshitaCore:GetResourceManager():GetString('keyitems.names', recipe.keyItem) or ('key item %i'):format(recipe.keyItem)
        local g = Px(13)
        if has then
            ui.CheckGlyph(dl, innerX, y + Px(2), g, col(theme.green))
        else
            ui.CrossGlyph(dl, innerX, y + Px(2), g, col(theme.red))
        end
        text.Draw(dl, text.Fit(name, Px(13), false, innerW - g - Px(6)), innerX + g + Px(6), y, col(has and theme.textSoft or theme.red), Px(13))
        y = y + Px(20)
    end

    path[itemId] = true
    y = y + DrawMaterials(dl, innerX, y, innerW, recipe, key, path, depth + 1)
    path[itemId] = nil

    ui.Line(dl, x + indent + 0.5, top + Px(2), x + indent + 0.5, y - Px(2), col(theme.gold, 0.4), 1)
    return y - top + Px(2)
end

-- one material row: chevron, slot, name, where else it is, count
local function DrawMaterial(dl, x, y, w, itemId, need, key, path, depth)
    local h = Px(46)
    local options = recipes.Options(itemId)
    local craftable = options ~= nil and not path[itemId] and depth < 8
    local clicked, hovered, right = ui.Hit('book.m' .. key, x, y, w, h)
    if hovered then
        ui.Rect(dl, x, y, x + w, y + h, col(theme.gold, 0.07), Px(3))
    end

    local status, onYou = Status(itemId, need)
    local open = craftable and state.expanded[key] == true
    if craftable then
        ui.ChevronGlyph(dl, x + Px(2), y + (h - Px(12)) / 2, Px(12), open, col(theme.gold))
    end

    local slot = Px(42)
    local sx = x + Px(20)
    ui.Slot(dl, sx, y + (h - slot) / 2, slot, itemId, statusRgb[status])

    local count = ('%i/%i'):format(onYou, need)
    local countW = text.Width(count, Px(15), true)
    local nameX = sx + slot + Px(10)
    local nameW = w - (nameX - x) - countW - Px(12)
    text.Draw(dl, text.Fit(items.ShortName(itemId), Px(14), false, nameW), nameX, y + Px(6), col(0xFFFFFF), Px(14))

    local sub = Where(itemId)
    if sub == nil and options ~= nil then
        if #options == 1 then
            sub = ('%s, makes %i'):format(RequirementText(options[1]), options[1].count)
        else
            sub = ('%s, %i recipes'):format(RequirementText(options[1]), #options)
        end
    end
    if sub ~= nil then
        text.Draw(dl, text.Fit(sub, Px(12), false, nameW), nameX, y + Px(25), col(theme.textMuted), Px(12))
    end
    local countRgb = status == 'covered' and theme.green or (status == 'elsewhere' and theme.amber or 0xFFFFFF)
    text.DrawRight(dl, count, x + w - Px(8), y + (h - Px(15)) / 2 - 1, col(countRgb), Px(15), true)

    if clicked and craftable then
        state.expanded[key] = not open or nil
        open = not open
    end
    if right then
        menu.Request('book', { itemId = itemId, recipes = options })
    end
    if hovered then
        local hint = 'Right-click to set a price.'
        if craftable then
            hint = 'Click to see its recipe. Right-click to plan it or set a price.'
        end
        ItemTip(itemId, hint)
    end

    local used = h + Px(2)
    if open then
        used = used + DrawSubRecipe(dl, x, y + used, w, itemId, options, key, path, depth)
    end
    return used
end

DrawMaterials = function(dl, x, y, w, recipe, key, path, depth)
    local top = y
    y = y + DrawMaterial(dl, x, y, w, recipe.crystal, 1, key .. '>c' .. recipe.crystal, path, depth)
    for _, ingredient in ipairs(recipes.Grouped(recipe)) do
        y = y + DrawMaterial(dl, x, y, w, ingredient.id, ingredient.count, key .. '>' .. ingredient.id, path, depth)
    end
    return y - top
end

-- the chips under a recipe's title: support, imagery, ring, skill-ups
local function DrawHints(dl, x, y, w, recipe, estimate)
    local chips = { }
    local hints = app.Hints(recipe)
    for _, hint in ipairs(hints) do
        local craft = recipes.skillNames[hint.craftId] or '?'
        if hint.kind == 'ring' then
            table.insert(chips, { ('%s blocks HQ'):format(items.ShortName(hint.ring)), theme.amber })
        elseif hint.kind == 'imagery' then
            table.insert(chips, { ('%s imagery on, +%i'):format(craft, hint.support), theme.blue })
        elseif hint.kind == 'support' then
            local name = hint.support == 3 and 'Advanced support (+3)' or 'Basic support (+1)'
            if hint.tier ~= nil then
                table.insert(chips, { ('%s reaches %s'):format(name, hint.tier), theme.amber })
            elseif hint.cap then
                table.insert(chips, { ('%s reaches cap'):format(name), theme.amber })
            elseif hint.success ~= nil then
                table.insert(chips, { ('%s: %i%% success'):format(name, hint.success), theme.amber })
            end
        elseif hint.kind == 'elsewhere' then
            table.insert(chips, { ('Imagery is on for %s'):format(recipes.skillNames[hint.other] or '?'), theme.amber })
        end
    end

    local main, level = recipes.MainCraft(recipe)
    if main ~= nil and level <= 110 then
        local band = skillup.Band(level, app.Skill(main), app.Gear(main) + app.Support(main), app.Cap(main))
        if band ~= 'none' then
            table.insert(chips, { ('Skill-up: %s'):format(skillup.bandNames[band]), bandColors[band] })
        end
    end

    if #chips == 0 then
        return 0
    end
    local cx, cy = x, y
    local rowH = Px(22)
    for _, chip in ipairs(chips) do
        local cw = ui.ChipWidth(chip[1])
        if cx > x and cx + cw > x + w then
            cx = x
            cy = cy + rowH
        end
        ui.Chip(dl, cx, cy, chip[1], chip[2])
        cx = cx + cw + Px(6)
    end
    return cy - y + rowH + Px(4)
end

-- a recipe in the list: a short row when closed, the full card when open
local function DrawRecipe(dl, x, y, w, recipe)
    local top = y
    local open = state.open[recipe.id] == true
    local estimate = app.Estimate(recipe)

    if not open then
        local h = Px(40)
        local clicked, hovered, right = ui.Hit('book.r' .. recipe.id, x, y, w, h)
        if hovered then
            ui.Rect(dl, x, y, x + w, y + h, col(theme.gold, 0.07), Px(3))
        end
        ui.ChevronGlyph(dl, x + Px(2), y + (h - Px(12)) / 2, Px(12), false, col(theme.gold))
        local slot = Px(34)
        local sx = x + Px(20)
        ui.Slot(dl, sx, y + (h - slot) / 2, slot, recipe.result, theme.slotBorder, { count = recipe.count })
        local nx = sx + slot + Px(10)
        local chip, rgb = TierText(estimate)
        local chipW = chip and ui.ChipWidth(chip) or 0
        local nameW = w - (nx - x) - chipW - Px(10)
        local name = items.ShortName(recipe.result)
        if recipe.count > 1 then
            name = ('%s x%i'):format(name, recipe.count)
        end
        text.Draw(dl, text.Fit(name, Px(14), false, nameW), nx, y + Px(3), col(0xFFFFFF), Px(14))
        text.Draw(dl, text.Fit(RequirementText(recipe), Px(12), false, nameW), nx, y + Px(21), col(theme.textMuted), Px(12))
        if chip ~= nil then
            ui.Chip(dl, x + w - chipW - Px(4), y + (h - Px(17)) / 2, chip, rgb)
        end
        if clicked then
            state.open[recipe.id] = true
        end
        if right then
            menu.Request('book', { itemId = recipe.result, recipes = { recipe } })
        end
        if hovered then
            ItemTip(recipe.result, 'Click to open. Right-click to plan it or set a price.')
        end
        return h + Px(2)
    end

    -- the open card. the title row closes it again.
    local heroH = Px(56)
    local clicked, hovered, right = ui.Hit('book.r' .. recipe.id, x, y, w, heroH)
    if hovered then
        ui.Rect(dl, x - Px(4), y - Px(2), x + w + Px(4), y + heroH, col(theme.gold, 0.05), Px(3))
    end
    local slot = Px(52)
    ui.Slot(dl, x, y + (heroH - slot) / 2, slot, recipe.result, theme.slotBorder, { glow = true })
    local nx = x + slot + Px(12)
    local name = items.ShortName(recipe.result)
    local nameW = w - (nx - x) - Px(24)
    text.Draw(dl, text.Fit(name, Px(17), true, nameW - Px(30)), nx, y + Px(4), col(0xFFFFFF), Px(17), true)
    local nameEnd = nx + math.min(text.Width(name, Px(17), true), nameW - Px(30))
    text.Draw(dl, ('x%i'):format(recipe.count), nameEnd + Px(8), y + Px(7), col(theme.textMuted), Px(13))
    ui.ChevronGlyph(dl, x + w - Px(16), y + Px(8), Px(12), true, col(theme.gold))

    local rx = nx
    local ry = y + Px(30)
    local list = recipes.Requirements(recipe)
    for i, requirement in ipairs(list) do
        local label = ('%s %i'):format(recipes.skillNames[requirement.id], requirement.level)
        local needed = Px(20) + Px(6) + text.Width(label, Px(13)) + Px(5) + Px(14)
        -- keep room for "+n more" while more requirements follow, after the
        -- 12 of space a placed requirement leaves
        local more = i < #list and (text.Width(('+%i more'):format(#list - i), Px(12)) + Px(12)) or 0
        if rx + needed + more > x + w then
            -- no room left on the line: say how many more crafts it needs
            text.Draw(dl, ('+%i more'):format(#list - i + 1), rx, ry + Px(2), col(theme.textMuted), Px(12))
            break
        end
        ui.Emblem(dl, rx, ry, Px(20), requirement.id)
        rx = rx + Px(20) + Px(6)
        text.Draw(dl, label, rx, ry + Px(2), col(0xFFFFFF), Px(13))
        rx = rx + text.Width(label, Px(13)) + Px(5)
        if Requirement(requirement.id, requirement.level) then
            ui.CheckGlyph(dl, rx, ry + Px(3), Px(14), col(theme.green))
        else
            ui.CrossGlyph(dl, rx, ry + Px(3), Px(14), col(theme.red))
        end
        rx = rx + Px(14) + Px(12)
    end
    if clicked then
        state.open[recipe.id] = nil
    end
    if right then
        menu.Request('book', { itemId = recipe.result, recipes = { recipe } })
    end
    if hovered then
        ItemTip(recipe.result, 'Click to close. Right-click to plan it or set a price.')
    end
    y = y + heroH + Px(8)

    if recipe.keyItem > 0 then
        local has = AshitaCore:GetMemoryManager():GetPlayer():HasKeyItem(recipe.keyItem)
        local kname = AshitaCore:GetResourceManager():GetString('keyitems.names', recipe.keyItem) or ('key item %i'):format(recipe.keyItem)
        local g = Px(13)
        if has then
            ui.CheckGlyph(dl, x, y + Px(2), g, col(theme.green))
        else
            ui.CrossGlyph(dl, x, y + Px(2), g, col(theme.red))
        end
        text.Draw(dl, text.Fit(kname, Px(13), false, w - g - Px(6)), x + g + Px(6), y, col(has and theme.textSoft or theme.red), Px(13))
        y = y + Px(20)
    end

    y = y + DrawHints(dl, x, y, w, recipe, estimate)

    if estimate ~= nil and not estimate.unknown then
        y = y + ui.Ladder(dl, x, y, w, estimate.margin, hq.TierIndex(estimate), {
            craftName = recipes.skillNames[estimate.craftId],
            success = estimate.success,
            ring = estimate.ring ~= nil,
        }) + Px(10)
    elseif estimate ~= nil and estimate.unknown then
        text.Draw(dl, hq.Describe(estimate, recipes.skillNames), x, y, col(theme.textDim), Px(12))
        y = y + Px(20)
    end

    y = y + ui.Section(dl, x, y, w, 'Materials') + Px(4)
    y = y + DrawMaterials(dl, x, y, w, recipe, 'r' .. recipe.id, { [recipe.result] = true }, 0)
    return y - top + Px(10)
end

local function DrawRecipesTab(dl, x, y, w)
    local cfg = app.Config()
    local top = y
    y = y + DrawEmblems(dl, x, y, w) + Px(12)
    y = y + DrawSearch(dl, x, y, w) + Px(12)

    local filter = state.filter[1]:lower()
    if filter ~= state.lastFilter then
        state.lastFilter = filter
        -- a search with one match opens it straight away
        local found = FilterRecipes(filter, cfg.searchMaterials[1])
        if #found == 1 then
            state.open[found[1].id] = true
        end
    end

    local list
    if filter == '' then
        list = RecentRecipes(6)
        if #list == 0 then
            y = y + ui.Paragraph(dl, x, y, w, 'Type an item name to find its recipe. Tick Materials to search by what goes in instead.', theme.textDim, Px(13))
            return y - top
        end
        y = y + ui.Section(dl, x, y, w, 'Recent') + Px(6)
    else
        list = FilterRecipes(filter, cfg.searchMaterials[1])
        if #list == 0 then
            text.Draw(dl, 'No recipes found.', x, y, col(theme.textDim), Px(13))
            return y - top + Px(20)
        end
    end

    for i = 1, math.min(book.maxResults, #list) do
        y = y + DrawRecipe(dl, x, y, w, list[i])
    end
    if #list > book.maxResults then
        text.Draw(dl, ('%i recipes found, showing the first %i.'):format(#list, book.maxResults), x, y + Px(4), col(theme.textDim), Px(12))
        y = y + Px(22)
    end
    return y - top
end

---------------------------------------------------------------------------
-- history tab
---------------------------------------------------------------------------

local function Ago(startTime)
    local seconds = os.time() - (startTime or 0)
    if seconds < 60 then
        return 'now'
    elseif seconds < 3600 then
        return ('%im ago'):format(math.floor(seconds / 60))
    elseif seconds < 86400 then
        return ('%ih ago'):format(math.floor(seconds / 3600))
    end
    return os.date('%b %d', startTime)
end

local function DrawHistoryTab(dl, x, y, w)
    local top = y
    local list = history.List()

    local nq, hqCount, breaks = 0, 0, 0
    local gains = { }
    for _, synth in ipairs(list) do
        if synth.result == 1 then
            breaks = breaks + 1
        elseif synth.result ~= nil and synth.result >= 2 then
            hqCount = hqCount + 1
        else
            nq = nq + 1
        end
        for craftId, skill in pairs(synth.skillup or { }) do
            if type(skill) == 'table' and skill.change ~= nil then
                gains[craftId] = (gains[craftId] or 0) + skill.change
            end
        end
    end

    local cx = x
    for _, chip in ipairs({
        { ('%i synths'):format(#list), theme.textSoft },
        { ('%i NQ'):format(nq), theme.textSoft },
        { ('%i HQ'):format(hqCount), theme.gold },
        { ('%i break%s'):format(breaks, breaks == 1 and '' or 's'), theme.red },
    }) do
        cx = cx + ui.Chip(dl, cx, y, chip[1], chip[2]) + Px(6)
    end
    local clearW = text.Width('Clear history', Px(13)) + Px(20)
    if ui.Button(dl, 'book.clearhistory', x + w - clearW, y - Px(3), 'Clear history', { danger = true }) then
        history.Clear()
    end
    y = y + Px(26)

    local gainParts = { }
    for craftId = 1, 8 do
        if gains[craftId] ~= nil and gains[craftId] ~= 0 then
            table.insert(gainParts, ('%s %+.1f'):format(recipes.skillAbbr[craftId], gains[craftId]))
        end
    end
    if #gainParts > 0 then
        text.Draw(dl, 'Skill gained: ' .. table.concat(gainParts, '   '), x, y, col(theme.textMuted), Px(12))
        y = y + Px(20)
    end
    y = y + ui.Section(dl, x, y, w, 'Latest synths') + Px(6)

    if #list == 0 then
        text.Draw(dl, 'Your synths show here as you craft.', x, y, col(theme.textDim), Px(13))
        return y - top + Px(22)
    end

    for index = 1, math.min(book.maxHistory, #list) do
        local synth = list[index]
        local h = Px(38)
        local _, hovered = ui.Hit(('book.h%i'):format(index), x, y, w, h)
        if hovered then
            ui.Rect(dl, x, y, x + w, y + h, col(theme.gold, 0.06), Px(3))
        end
        local result = synth.result
        local isHQ = result ~= nil and result >= 2
        local border = result == 1 and theme.red or (isHQ and theme.gold or theme.slotBorder)
        ui.Slot(dl, x, y + (h - Px(32)) / 2, Px(32), synth.item or 0, border, { hq = isHQ, count = synth.count })
        local nx = x + Px(42)
        local name = items.ShortName(synth.item or 0)
        if (synth.count or 0) > 1 then
            name = ('%s x%i'):format(name, synth.count)
        end
        local label = resultNames[result] or '?'
        local rgb = result == 1 and theme.red or (isHQ and theme.gold or theme.textSoft)
        local chipW = ui.ChipWidth(label)
        local ago = Ago(synth.startTime)
        local agoW = text.Width(ago, Px(12))
        text.Draw(dl, text.Fit(name, Px(14), false, w - Px(42) - chipW - agoW - Px(24)), nx, y + Px(2), col(0xFFFFFF), Px(14))
        ui.Chip(dl, x + w - chipW - agoW - Px(12), y + Px(2), label, rgb)
        text.DrawRight(dl, ago, x + w - Px(4), y + Px(4), col(theme.textDim), Px(12))

        local subParts = { }
        for craftId, skill in pairs(synth.skillup or { }) do
            if type(skill) == 'table' and skill.change ~= nil then
                table.insert(subParts, ('%s %+.1f'):format(recipes.skillAbbr[craftId] or tostring(craftId), skill.change))
            end
        end
        table.sort(subParts)
        local lostNames = { }
        for _, itemId in ipairs(synth.lost or { }) do
            table.insert(lostNames, items.ShortName(itemId))
        end
        local sub = table.concat(subParts, '  ')
        if #lostNames > 0 then
            sub = (sub ~= '' and (sub .. '   ') or '') .. 'lost ' .. table.concat(lostNames, ', ')
        end
        if sub ~= '' then
            text.Draw(dl, text.Fit(sub, Px(12), false, w - Px(46)), nx, y + Px(20), col(#lostNames > 0 and theme.red or theme.green), Px(12))
        end
        if hovered and #lostNames > 0 then
            local lines = { { 'Lost in this synth', theme.red, true }, { rule = true } }
            for _, itemId in ipairs(synth.lost) do
                table.insert(lines, { item = itemId, items.ShortName(itemId), theme.textSoft })
            end
            ui.Tip(lines)
        end
        y = y + h + Px(2)
    end
    if #list > book.maxHistory then
        text.Draw(dl, ('Showing the latest %i of %i synths.'):format(book.maxHistory, #list), x, y + Px(4), col(theme.textDim), Px(12))
        y = y + Px(22)
    end
    return y - top
end

---------------------------------------------------------------------------
-- settings tab
---------------------------------------------------------------------------

local function InputNumber(id, x, y, w, ref, step, format, isFloat)
    -- imgui needs a number here, and a hand-edited settings file may not
    -- have one
    local number = tonumber(ref[1])
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
        number = 0
    end
    ref[1] = number
    guard.PushStyleColor(ImGuiCol_FrameBg, theme.rgba(theme.bgDark, 0.85))
    guard.PushStyleColor(ImGuiCol_FrameBgHovered, theme.rgba(theme.bgLight, 0.95))
    guard.PushStyleColor(ImGuiCol_FrameBgActive, theme.rgba(theme.bgLighter, 1))
    guard.PushStyleColor(ImGuiCol_Button, theme.rgba(theme.bgMedium, 1))
    guard.PushStyleColor(ImGuiCol_ButtonHovered, theme.rgba(theme.gold, 0.3))
    guard.PushStyleColor(ImGuiCol_ButtonActive, theme.rgba(theme.gold, 0.45))
    imgui.SetCursorScreenPos({ x, y })
    imgui.SetNextItemWidth(w)
    local changed
    if isFloat then
        changed = imgui.InputFloat(id, ref, step, step, format)
    else
        changed = imgui.InputInt(id, ref)
    end
    guard.PopStyleColor(6)
    return changed
end

local function Clamp(ref, low, high)
    local number = tonumber(ref[1]) or low
    ref[1] = math.max(low, math.min(high, number))
end

-- one alert's sound: its name, a box that opens the list of sounds, and a
-- button to hear it. returns the height used.
local function SoundRow(dl, x, y, w, labelW, key, label)
    local cfg = app.Config()
    local ref = cfg.sounds[key]
    local file = (ref ~= nil and type(ref[1]) == 'string') and ref[1] or ''
    local s = Px(13)
    local h = math.max(Px(24), text.H(s) + Px(8))
    local playW = text.Width('Play', s) + Px(20)
    local bx, by = x + labelW, y
    local used = h
    if bx + Px(110) + Px(6) + playW > x + w then
        -- a narrow book: the name goes above its box
        text.Draw(dl, label, x, y + (text.H(s) - s) / 2, col(theme.textSoft), s)
        bx = x
        by = y + text.H(s) + Px(4)
        used = by - y + h
    else
        text.Draw(dl, label, x, y + (h - s) / 2 - 1, col(theme.textSoft), s)
    end
    local bw = math.max(Px(60), x + w - playW - Px(6) - bx)
    local clicked, hovered = ui.Hit('book.sound.' .. key, bx, by, bw, h)
    ui.Rect(dl, bx, by, bx + bw, by + h, col(hovered and theme.bgLighter or theme.bgDark, 0.9), Px(3))
    ui.Outline(dl, bx, by, bx + bw, by + h, col(hovered and theme.goldDarker or theme.border), Px(3), 1)
    local g = Px(11)
    local label = sounds.Label(file)
    if sounds.GameId(file) ~= nil and not sounds.GameFolder() then
        label = label .. ' (no game folder)'
    elseif file ~= '' and not sounds.Exists(file) then
        label = label .. ' (missing)'
    elseif sounds.Unreadable(file) then
        label = label .. ' (can\'t read)'
    end
    local name = text.Fit(label, s, false, math.max(Px(10), bw - Px(16) - g - Px(4)))
    text.Draw(dl, name, bx + Px(8), by + (h - s) / 2 - 1, col(file == '' and theme.textDim or 0xFFFFFF), s)
    ui.ChevronGlyph(dl, bx + bw - g - Px(7), by + (h - g) / 2, g, true, col(hovered and theme.gold or theme.goldDark))
    if clicked then
        sounds.Refresh()
        menu.Request('book', { mode = 'sound', key = key, label = label })
    elseif hovered then
        ui.Tip('Pick the sound for this alert')
    end
    if ui.Button(dl, 'book.soundplay.' .. key, x + w - playW, by, 'Play', { width = playW }) then
        fanfareMod.PlayChoice(key, file)
    end
    return used
end

local function DrawSettingsTab(dl, x, y, w)
    local cfg = app.Config()
    local top = y

    -- crafts
    y = y + ui.Section(dl, x, y, w, 'Your crafts') + Px(6)
    local changed, cw = ui.Checkbox(dl, 'book.autoskills', x, y, 'Craft levels from the game', cfg.autoSkills)
    if changed then app.Dirty() end
    local ax = x + cw + Px(18)
    if ax + Px(15) + Px(7) + text.Width('Detect crafting gear', Px(13)) > x + w then
        -- no room beside it: the second checkbox goes under the first
        ax = x
        y = y + Px(24)
    end
    changed = ui.Checkbox(dl, 'book.autogear', ax, y, 'Detect crafting gear', cfg.autoGear)
    if changed then app.Dirty() end
    y = y + Px(24)
    y = y + ui.Paragraph(dl, x, y, w, 'Whole levels and ranks come from the game when you zone. Decimals come from skill-ups.', theme.textDim, Px(11.5)) + Px(4)

    -- the columns make room for the longest craft name at any text size
    local nameW = 0
    for craftId = 1, 8 do
        nameW = math.max(nameW, text.Width(recipes.skillNames[craftId], Px(13)))
    end
    local inputX = math.max(x + Px(130), x + Px(32) + nameW + Px(8))
    -- the level boxes are imgui's own, drawn in Ashita's font, so they are
    -- sized to that font: room for "100.0" and the - and + buttons
    local frameH = ui.FrameHeight()
    local padX, innerX = ui.StylePads()
    local inputW = math.max(Px(120), ui.ImWidth('100.0') + frameH * 2 + padX * 2 + innerX * 2 + Px(4))
    local rowH = math.max(Px(28), frameH + Px(4))
    -- the rest of the row sits in the middle of a taller row
    local dy = (rowH - Px(28)) / 2
    local gx = math.max(x + Px(264), inputX + inputW + Px(14))
    for craftId = 1, 8 do
        ui.Emblem(dl, x, y + dy + Px(2), Px(24), craftId)
        text.Draw(dl, recipes.skillNames[craftId], x + Px(32), y + dy + Px(6), col(0xFFFFFF), Px(13))
        if InputNumber(('##hcrafter.level%i'):format(craftId), inputX, y + (rowH - frameH) / 2, inputW, cfg.skills[craftId], 0.1, '%.1f', true) then
            Clamp(cfg.skills[craftId], 0, 110)
            app.Dirty()
        end
        local gearEnd
        if cfg.autoGear[1] then
            local bonus = gear.Bonus(craftId)
            local label = bonus ~= 0 and ('gear +%i'):format(bonus) or 'no gear'
            text.Draw(dl, label, gx, y + dy + Px(6), col(bonus ~= 0 and theme.green or theme.textDim), Px(12.5))
            gearEnd = gx + text.Width(label, Px(12.5))
        else
            text.Draw(dl, 'gear', gx, y + dy + Px(6), col(theme.textMuted), Px(12.5))
            local stepX = gx + math.max(Px(34), text.Width('gear', Px(12.5)) + Px(6))
            local value, stepW, _, stepped = ui.Stepper(dl, ('book.gear%i'):format(craftId), stepX, y + dy + Px(3), app.Gear(craftId), 0, 10, 1)
            if stepped then
                cfg.gear[craftId][1] = value
                app.Dirty()
            end
            gearEnd = stepX + stepW
        end
        local rank = cfg.ranks[craftId] and cfg.ranks[craftId][1] or -1
        local rankText = rank >= 0 and (recipes.rankNames[rank] or ('rank ' .. rank)) or 'rank unknown'
        -- the rank shortens, or hides, when big text leaves no room for it
        local room = x + w - gearEnd - Px(10)
        if room >= text.Width('Abc...', Px(12)) then
            text.DrawRight(dl, text.Fit(rankText, Px(12), false, room), x + w, y + dy + Px(6), col(rank >= 0 and theme.textMuted or theme.textDim), Px(12))
        end
        y = y + rowH
    end
    y = y + Px(8)

    -- image support
    y = y + ui.Section(dl, x, y, w, 'Image support') + Px(6)
    text.Draw(dl, 'When an imagery buff is on, count it as', x, y + Px(3), col(theme.textSoft), Px(13))
    local labelW = text.Width('When an imagery buff is on, count it as', Px(13))
    local selected = cfg.support[1] == 3 and 2 or 1
    local sx = x + labelW + Px(10)
    local switchW = text.Width('Basic +1', Px(12.5)) + text.Width('Advanced +3', Px(12.5)) + Px(36)
    if sx + switchW > x + w then
        -- no room after the question: the switch goes under it
        sx = x
        y = y + math.max(Px(24), text.H(Px(13)) + Px(10))
    end
    local picked = ui.Segmented(dl, 'book.support', sx, y, { 'Basic +1', 'Advanced +3' }, selected)
    if picked ~= selected then
        cfg.support[1] = picked == 2 and 3 or 1
        app.Dirty()
    end
    y = y + Px(26)
    y = y + ui.Paragraph(dl, x, y, w, 'Support only counts for the craft whose imagery you have.', theme.textDim, Px(11.5)) + Px(6)

    -- look
    y = y + ui.Section(dl, x, y, w, 'Look') + Px(6)
    local percent = { format = function(v) return v .. '%' end }
    -- the labels' column fits the longest label at any text size
    local labelW = math.max(Px(70), text.Width('Text size', Px(13)) + Px(12))
    local rowH = math.max(Px(28), text.H(Px(13)) + Px(12))
    text.Draw(dl, 'Frame', x, y + Px(3), col(theme.textSoft), Px(13))
    local frame, frameW = ui.Segmented(dl, 'book.frame', x + labelW, y, { 'Navy', 'Charcoal' }, cfg.look.frame[1])
    if frame ~= cfg.look.frame[1] then
        cfg.look.frame[1] = frame
        app.Dirty()
    end
    -- Opacity sits on the right, moved left when a narrow book needs it,
    -- and onto its own line when that would crowd the frame switch
    local stepH = math.max(Px(22), text.H(Px(13)) + Px(7))
    local stepW = stepH * 2 + math.max(Px(34), text.Width('100%', Px(13), true) + Px(12))
    local opacityW = math.max(Px(60), text.Width('Opacity', Px(13)) + Px(8))
    local ox = math.min(x + Px(250), x + w - opacityW - stepW)
    local stepX = ox + opacityW
    if ox < x + labelW + frameW + Px(16) then
        y = y + rowH
        ox, stepX = x, x + labelW
    end
    local alphaPercent = math.floor(ui.bgAlpha * 100 + 0.5)
    text.Draw(dl, 'Opacity', ox, y + Px(3), col(theme.textSoft), Px(13))
    local value, _, _, stepped = ui.Stepper(dl, 'book.alpha', stepX, y, alphaPercent, 40, 100, 5, percent)
    if stepped then
        cfg.look.alpha[1] = value / 100
        app.Dirty()
    end
    y = y + rowH
    text.Draw(dl, 'Size', x, y + Px(3), col(theme.textSoft), Px(13))
    local scalePercent = math.floor(ui.size * 100 + 0.5)
    value, _, _, stepped = ui.Stepper(dl, 'book.scale', x + labelW, y, scalePercent, 75, 150, 5, percent)
    if stepped then
        cfg.look.scale[1] = value / 100
        app.Dirty()
    end
    y = y + rowH
    text.Draw(dl, 'Text size', x, y + Px(3), col(theme.textSoft), Px(13))
    -- text.scale is the size in use: always a number from 0.8 to 1.3
    local textPercent = math.floor(text.scale * 100 + 0.5)
    value, _, _, stepped = ui.Stepper(dl, 'book.textsize', x + labelW, y, textPercent, 80, 130, 5, percent)
    if stepped then
        cfg.look.text[1] = value / 100
        app.Dirty()
    end
    y = y + rowH
    changed = ui.Checkbox(dl, 'book.matchashita', x, y, "Grow with Ashita's font size", cfg.look.matchAshita)
    if changed then app.Dirty() end
    y = y + math.max(Px(24), text.H(Px(13)) + Px(8))
    local defaultPx = ui.AshitaDefaultPx()
    local fontPx = math.floor((ui.AshitaFontPx() or defaultPx) + 0.5)
    local fontNote
    if cfg.look.matchAshita[1] then
        fontNote = ("Ashita's font is %i px and its default is %i px, so HCrafter is drawn at %i%% before Size."):format(fontPx, defaultPx, math.floor(ui.AshitaScale() * 100 + 0.5))
    else
        fontNote = ("Ashita's font is %i px and its default is %i px. Tick this to grow HCrafter with it."):format(fontPx, defaultPx)
    end
    y = y + ui.Paragraph(dl, x, y, w, fontNote, theme.textDim, Px(11.5)) + Px(4)
    y = y + ui.Paragraph(dl, x, y, w, 'Size scales whole windows. Text size changes only the text. Drag a window by its bottom right corner to resize it, and double-click the corner to reset it.', theme.textDim, Px(11.5)) + Px(6)
    changed, cw = ui.Checkbox(dl, 'book.icons', x, y, 'Game icons', cfg.look.gameIcons)
    if changed then app.Dirty() end
    local fontLabel = text.HasGameFont() and 'Tahoma font' or 'Tahoma font (not found)'
    changed = ui.Checkbox(dl, 'book.font', x + cw + Px(18), y, fontLabel, cfg.look.gameFont)
    if changed then app.Dirty() end
    y = y + Px(28)

    -- alerts
    y = y + ui.Section(dl, x, y, w, 'Fanfare and sounds') + Px(6)
    local fanfare = cfg.fanfare
    local cx = x
    for _, spec in ipairs({
        { 'levelUp', 'Level-ups' }, { 'hq', 'Hard HQs' }, { 'hqEasy', 'Easy HQs' }, { 'breaks', 'Breaks' }, { 'skillUp', 'Every skill-up' },
    }) do
        local label = spec[2]
        local width = Px(15) + Px(7) + text.Width(label, Px(13))
        if cx > x and cx + width > x + w then
            cx = x
            y = y + Px(24)
        end
        local c, used = ui.Checkbox(dl, 'book.ff' .. spec[1], cx, y, label, fanfare[spec[1]])
        if c then app.Dirty() end
        cx = cx + used + Px(16)
    end
    y = y + Px(26)

    -- the alert after your macro: [x] Alert after [- 6 +] synths in a row
    local ready = cfg.ready
    local checkH
    changed, cw, checkH = ui.Checkbox(dl, 'book.ready', x, y, 'Alert after', ready.enabled)
    if changed then app.Dirty() end
    local everyX = x + cw + Px(8)
    local everyH = math.max(Px(22), text.H(Px(13)) + Px(7))
    local everyY = y + (checkH - everyH) / 2
    local every, everyW, everyStepped
    every, everyW, _, everyStepped = ui.Stepper(dl, 'book.every', everyX, everyY, app.AlertEvery(), 1, 6, 1)
    if everyStepped then
        ready.every[1] = every
        app.Dirty()
    end
    local afterX = everyX + everyW + Px(8)
    local afterLabel = 'synths in a row'
    if afterX + text.Width(afterLabel, Px(13)) > x + w then
        -- no room after the stepper: the words go under it
        y = y + math.max(checkH, everyH) + Px(4)
        afterX = x + Px(22)
        text.Draw(dl, afterLabel, afterX, y, col(theme.textSoft), Px(13))
        y = y + text.H(Px(13)) + Px(8)
    else
        text.Draw(dl, afterLabel, afterX, y + (checkH - Px(13)) / 2 - 1, col(ready.enabled[1] and theme.textSoft or theme.textMuted), Px(13))
        y = y + math.max(checkH, everyH) + Px(6)
    end
    y = y + ui.Paragraph(dl, x, y, w, 'One alert when that many synths in a row are done, or when you run out of a material. A pause of more than 25 seconds starts a new count. It only shows and sounds. It never presses your macro.', theme.textDim, Px(11.5)) + Px(8)

    -- the sound for each alert, and one volume for them all
    changed, cw = ui.Checkbox(dl, 'book.ffsound', x, y, 'Play sounds', fanfare.sound)
    if changed then app.Dirty() end
    local volumeLabelW = text.Width('Volume', Px(13)) + Px(10)
    local vx, vy = x + cw + Px(24), y - Px(2)
    if vx + volumeLabelW + stepW > x + w then
        -- no room beside the checkbox: Volume gets its own line
        y = y + math.max(Px(26), text.H(Px(13)) + Px(10))
        vx, vy = x, y - Px(2)
    end
    text.Draw(dl, 'Volume', vx, vy + (stepH - Px(13)) / 2 - 1, col(fanfare.sound[1] and theme.textSoft or theme.textMuted), Px(13))
    value, _, _, stepped = ui.Stepper(dl, 'book.volume', vx + volumeLabelW, vy, fanfareMod.Volume(), 0, 150, 10, percent)
    if stepped then
        cfg.soundVolume[1] = value
        app.Dirty()
        -- the picked sounds get their copies at the new volume ahead of
        -- time, and the folder is kept to sounds.maxCopies
        local picked = { }
        for _, ref in pairs(cfg.sounds) do
            if type(ref) == 'table' and type(ref[1]) == 'string' and ref[1] ~= '' then
                picked[#picked + 1] = ref[1]
                sounds.Warm(ref[1], value)
            end
        end
        sounds.Tidy(picked, value)
    end
    y = y + math.max(Px(26), text.H(Px(13)) + Px(10), stepH + Px(4))
    local soundRows = {
        { 'levelUp', 'Level-up' }, { 'hq', 'HQ' }, { 'hqBig', 'Rare HQ' }, { 'breaks', 'Break' },
        { 'skillUp', 'Skill-up' }, { 'noMore', 'No more skill-ups' }, { 'done', 'Synths done' }, { 'short', 'Out of a material' },
        { 'startup', 'Startup' }, { 'shutdown', 'Shutdown' },
    }
    local soundLabelW = 0
    for _, spec in ipairs(soundRows) do
        soundLabelW = math.max(soundLabelW, text.Width(spec[2], Px(13)))
    end
    for _, spec in ipairs(soundRows) do
        y = y + SoundRow(dl, x, y, w, soundLabelW + Px(12), spec[1], spec[2]) + Px(4)
    end
    local soundNote
    y = y + ui.Paragraph(dl, x, y + Px(2), w, 'Startup plays when HCrafter loads while you\'re in game, when you log in, and when /hcrafter shows this book. Shutdown plays when you log out or unload HCrafter.', theme.textDim, Px(11.5)) + Px(4)
    if sounds.GameFolder() then
        soundNote = 'Sounds marked FFXI are the game\'s own. HCrafter reads them from your game folder and keeps a copy in config\\addons\\hcrafter\\sounds. It ships none of them.'
    else
        soundNote = 'HCrafter can\'t find your game\'s sound folder, so FFXI sounds play HCrafter\'s own instead.'
    end
    soundNote = soundNote .. ' Your own .wav files in addons\\hcrafter\\sounds show up in these lists too. They follow the volume when they are 8, 16, 24 or 32-bit PCM or 32-bit float, mono or stereo, and up to 10 seconds long at 48 kHz. Others play at their own volume.'
    y = y + Px(2) + ui.Paragraph(dl, x, y + Px(2), w, soundNote, theme.textDim, Px(11.5)) + Px(6)

    -- shopping list
    y = y + ui.Section(dl, x, y, w, 'Shopping list') + Px(6)
    changed, cw = ui.Checkbox(dl, 'book.tracker', x, y, 'Show the Shopping list', cfg.tracker.visible)
    if changed then app.Dirty() end
    local ax, ay = x + cw + Px(24), y
    local alphaLabelW = math.max(Px(60), text.Width('Opacity', Px(13)) + Px(10))
    if ax + alphaLabelW + stepW > x + w then
        -- no room beside the checkbox: Opacity gets its own line
        ax, ay = x, y + Px(28)
        y = ay
    end
    text.Draw(dl, 'Opacity', ax, ay + Px(2), col(theme.textSoft), Px(13))
    local trackerAlpha = math.floor(cfg.tracker.alpha[1] * 100 + 0.5)
    value, _, _, stepped = ui.Stepper(dl, 'book.trackeralpha', ax + alphaLabelW, ay - Px(2), trackerAlpha, 0, 90, 5, percent)
    if stepped then
        cfg.tracker.alpha[1] = value / 100
        app.Dirty()
    end
    y = y + Px(28)

    -- hiding
    y = y + ui.Section(dl, x, y, w, 'Hide') + Px(6)
    cx = x
    for _, spec in ipairs({
        { 'hideUnderMap', 'With the map open' }, { 'hideDuringEvent', 'In cutscenes' }, { 'hideWithInterface', 'With the interface hidden' },
    }) do
        local width = Px(15) + Px(7) + text.Width(spec[2], Px(13))
        if cx > x and cx + width > x + w then
            cx = x
            y = y + Px(24)
        end
        local c, used = ui.Checkbox(dl, 'book.' .. spec[1], cx, y, spec[2], cfg[spec[1]])
        if c then app.Dirty() end
        cx = cx + used + Px(16)
    end
    y = y + Px(30)

    -- prices
    y = y + ui.Section(dl, x, y, w, 'Prices') + Px(6)
    local count = prices.Count()
    local reloadW = text.Width('Reload', Px(13)) + Px(20)
    local pricesLine = ('%i prices in config\\addons\\hcrafter\\prices.csv'):format(count)
    text.Draw(dl, text.Fit(pricesLine, Px(13), false, w - reloadW - Px(10)), x, y + Px(3), col(theme.textSoft), Px(13))
    if ui.Button(dl, 'book.reloadprices', x + w - reloadW, y, 'Reload') then
        local n, skipped = prices.Load(true)
        print(('[hcrafter] Read %i prices%s.'):format(n, skipped > 0 and (', skipped ' .. skipped .. ' lines') or ''))
    end
    y = y + Px(28)
    y = y + ui.Paragraph(dl, x, y, w, 'Right-click any item to set its price. Prices are for one item, in gil, shared by all your characters.', theme.textDim, Px(11.5)) + Px(6)

    -- characters
    y = y + ui.Section(dl, x, y, w, 'Characters') + Px(6)
    local others = stock.OtherCharacters()
    if #others == 0 then
        y = y + ui.Paragraph(dl, x, y, w, 'None yet. Log in on each character once with HCrafter loaded.', theme.textDim, Px(12.5))
    else
        for _, other in ipairs(others) do
            local line = ('%s: %i items, saved %s'):format(other.name, other.items, os.date('%b %d %H:%M', other.saved))
            text.Draw(dl, text.Fit(line, Px(12.5), false, w), x, y, col(theme.textSoft), Px(12.5))
            y = y + Px(19)
        end
    end
    local saveW = text.Width('Save this character now', Px(13)) + Px(20)
    if ui.Button(dl, 'book.savechar', x, y + Px(4), 'Save this character now') then
        local saved, why = stock.SaveCurrent(true)
        if saved then
            print('[hcrafter] Saved this character\'s bags.')
        else
            print(('[hcrafter] Not saved: %s.'):format(why or 'unknown reason'))
        end
    end
    y = y + Px(34)
    local bagH = Px(22)
    local bagClicked, bagHovered = ui.Hit('book.bagcheck', x, y, w, bagH)
    if bagClicked then
        state.showBags = not state.showBags
    end
    ui.ChevronGlyph(dl, x, y + (bagH - Px(12)) / 2, Px(12), state.showBags == true, col(bagHovered and theme.gold or theme.goldDark))
    text.Draw(dl, 'Bag check: what the game shows right now', x + Px(18), y + (bagH - Px(12)) / 2 - 1, col(theme.textMuted), Px(12))
    y = y + bagH
    if state.showBags then
        local bags = stock.LoadedBags()
        local colW = w / 2
        for i, bag in ipairs(bags) do
            local bx = x + ((i - 1) % 2) * colW
            local label = ('%s: %s, %i items'):format(bag.name, bag.loaded and 'readable' or 'not readable', bag.items)
            text.Draw(dl, text.Fit(label, Px(11.5), false, colW - Px(6)), bx, y, col(bag.loaded and theme.textMuted or theme.textDim), Px(11.5))
            if i % 2 == 0 or i == #bags then
                y = y + Px(16)
            end
        end
    end
    return y - top + Px(6)
end

---------------------------------------------------------------------------
-- the window
---------------------------------------------------------------------------

-- show a recipe in the book: its name in the search box and its card open
function book.Open(recipe)
    local cfg = app.Config()
    cfg.book.visible[1] = true
    cfg.book.tab[1] = 1
    cfg.searchMaterials[1] = false
    state.filter[1] = items.ShortName(recipe.result)
    state.lastFilter = state.filter[1]:lower()
    state.open[recipe.id] = true
    app.Dirty()
end

-- what is open and typed, for tests
function book.State()
    return state
end

function book.Draw()
    local cfg = app.Config()
    if not cfg.book.visible[1] then
        return
    end
    local name = 'HCrafter###hcrafter.book'
    local open, dl, x, y = ui.BeginWindow(name, cfg.book)
    if not open then
        ui.EndWindow(name)
        return
    end

    local w = ui.WindowWidth(cfg.book, book.limits)
    local clicked, titleH = ui.TitleBar(dl, 'book', x, y, w, 'HCrafter', ui.BookGlyph, {
        { key = 'planner', draw = ui.ListGlyph, badge = #cfg.planner.entries, tip = 'Resource Planner', active = cfg.planner.visible[1] },
        { key = 'list', draw = ui.FlagGlyph, tip = 'Shopping list', active = cfg.tracker.visible[1] },
        { key = 'close', draw = ui.CrossGlyph, tip = 'Close' },
    })
    if clicked == 'planner' then
        cfg.planner.visible[1] = not cfg.planner.visible[1]
        app.Dirty()
    elseif clicked == 'list' then
        cfg.tracker.visible[1] = not cfg.tracker.visible[1]
        app.Dirty()
    elseif clicked == 'close' then
        cfg.book.visible[1] = false
        app.Dirty()
    end

    local cy = y + titleH + Px(10)
    local tab, tabH = ui.Tabs(dl, 'book', x + Px(14), cy, w - Px(28), { 'Recipes', 'History', 'Settings' }, cfg.book.tab[1])
    if tab ~= cfg.book.tab[1] then
        cfg.book.tab[1] = tab
        app.Dirty()
    end
    cy = cy + tabH + 1

    local display = imgui.GetIO().DisplaySize
    local maxH = math.max(Px(200), display.y * 0.78 - (cy - y))
    local fixedH = ui.FixedBodyHeight(cfg.book, book.limits, cy - y)
    imgui.SetCursorScreenPos({ x, cy })
    local bdl, bx, by, bw, bh = ui.BeginBody('hcrafter.book.body', w, maxH, fixedH)
    local padX = Px(14)
    local inner = bw - padX * 2
    local used
    if tab == 2 then
        used = DrawHistoryTab(bdl, bx + padX, by + Px(12), inner)
    elseif tab == 3 then
        used = DrawSettingsTab(bdl, bx + padX, by + Px(12), inner)
    else
        used = DrawRecipesTab(bdl, bx + padX, by + Px(12), inner)
    end
    ui.EndBody('hcrafter.book.body', bx, by, bw, used + Px(12) + Px(14))
    local h = cy - y + bh + Px(ui.footerH)
    if ui.ResizeGrip(dl, 'book', x, y, w, h, cfg.book, book.limits) then
        app.Dirty()
    end
    menu.Draw('book')
    ui.EndWindow(name, x, y, w, h)
end

return book
