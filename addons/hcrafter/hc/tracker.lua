-- the Shopping list: a light, quest-tracker style list of what to buy and
-- what to make for your Resource Planner queue, how far your /lastsynth
-- macro is, and how good your last synth still is for skill-ups. part of
-- HCrafter, GPL-3.0.
require('common')
local bit = require('bit')
local imgui = require('imgui')
local guard = require('hc.guard')
local theme = require('hc.theme')
local text = require('hc.text')
local ui = require('hc.ui')
local items = require('hc.items')
local recipes = require('hc.recipes')
local hq = require('hc.hq')
local stock = require('hc.stock')
local history = require('hc.history')
local planner = require('hc.planner')
local skillup = require('hc.skillup')
local watch = require('hc.synthwatch')
local app = require('hc.app')

local tracker = {
    width = 320,
    -- the widths a player can drag the Shopping list to. its height always
    -- fits what it shows.
    limits = { defaultW = 320, minW = 260, maxW = 720, widthOnly = true },
    maxBuy = 10,
    maxMake = 8,
}

local col = theme.col
local Px = ui.Px
local sizes = { }
local flags = nil

local bandColors = {
    none = theme.textDim,
    optimal = theme.green,
    costly = theme.amber,
    danger = theme.red,
}

local function IsCrystal(itemId)
    return itemId >= 4096 and itemId <= 4103
end

-- the recipe of your last synth, if HCrafter knows it
local function LastRecipe()
    local latest = history.Latest()
    if latest == nil then
        return nil
    end
    return recipes.ForEntry(latest)
end

local function SkillupLine(recipe)
    local craftId, level = recipes.MainCraft(recipe)
    if craftId == nil or level > 110 then
        return nil
    end
    local skill = app.Skill(craftId)
    local band, gap = skillup.Band(level, skill, app.Gear(craftId) + app.Support(craftId), app.Cap(craftId))
    if band == 'none' then
        return ('No more skill-ups from this recipe (%s %i)'):format(recipes.skillAbbr[craftId], level), theme.textDim
    end
    local togo = gap == 1 and '1 level to go' or ('%i levels to go'):format(gap)
    return ('Skill-up: %s, %s'):format(skillup.bandNames[band], togo), bandColors[band]
end

function tracker.Draw()
    local cfg = app.Config()
    if not cfg.tracker.visible[1] then
        return
    end

    local result, entries = app.PlanResult()
    local count, missing = watch.State()
    local last = LastRecipe()
    local showRun = cfg.ready.enabled[1] and (count > 0 or missing ~= nil)
    if #entries == 0 and not showRun and last == nil then
        return
    end

    if flags == nil then
        flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoFocusOnAppearing)
    end

    local display = imgui.GetIO().DisplaySize
    if cfg.tracker.pos[1] < 0 then
        cfg.tracker.pos[1] = math.max(0, display.x - ui.WindowWidth(cfg.tracker, tracker.limits) - Px(40))
        cfg.tracker.pos[2] = math.floor(display.y * 0.2)
    end
    imgui.SetNextWindowPos(cfg.tracker.pos, ImGuiCond_FirstUseEver)
    guard.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    guard.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 0, 0 })
    guard.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0)
    local name = 'Shopping list###hcrafter.tracker'
    local open = guard.Begin(name, cfg.tracker.visible, flags)
    if not open then
        guard.End()
        guard.PopStyleVar(3)
        return
    end

    local dl = imgui.GetWindowDrawList()
    local x, y = imgui.GetWindowPos()
    cfg.tracker.pos[1], cfg.tracker.pos[2] = x, y
    -- the Shopping list sits over the game world, so all its text gets the
    -- full outline
    text.full = true
    local w = ui.WindowWidth(cfg.tracker, tracker.limits)
    local alpha = cfg.tracker.alpha[1]
    local size = sizes[name]
    if size ~= nil and alpha > 0 then
        ui.Rect(dl, x, y, x + size[1], y + size[2], col(0x0A0C10, alpha), Px(10))
    end

    local pad = Px(14)
    local cx, cy = x + pad, y + Px(12)
    local iw = w - pad * 2
    -- rows stop where the list would leave the screen, keeping room for
    -- the lines under them
    local bottom = display.y - Px(12) - (Px(22) * 3 + Px(28))

    -- header
    local first = entries[1]
    local headerItem = first and first.recipe.result or (last and last.result) or nil
    local title
    if #entries == 1 then
        title = items.ShortName(first.recipe.result)
    elseif #entries > 1 then
        title = ('%i recipes'):format(#entries)
    else
        title = 'Shopping list'
    end
    local slot = Px(34)
    if headerItem ~= nil then
        ui.Slot(dl, cx, cy, slot, headerItem, theme.slotBorder)
    end
    local tx = headerItem ~= nil and (cx + slot + Px(10)) or cx
    local bs = Px(24)
    local titleW = x + w - pad - bs * 2 - Px(10) - tx
    text.Draw(dl, text.Fit(title, Px(16), true, titleW), tx, cy, col(0xFFFFFF), Px(16), true)
    if #entries > 0 then
        local synths = 0
        for _, item in ipairs(entries) do
            synths = synths + item.synths
        end
        local sub = ('%i synth%s'):format(synths, synths == 1 and '' or 's')
        if #stock.others > 0 then
            sub = sub .. (cfg.planner.useOthers[1] and ', mules counted' or ', mules not counted')
        end
        text.Draw(dl, text.Fit(sub, Px(12.5), false, titleW), tx, cy + Px(19), col(theme.textMuted), Px(12.5))
    end
    if ui.IconButton(dl, 'tracker.book', x + w - pad - bs * 2 - Px(6), cy, bs, ui.BookGlyph, { tip = 'Recipe book' }) then
        cfg.book.visible[1] = not cfg.book.visible[1]
        app.Dirty()
    end
    if ui.IconButton(dl, 'tracker.hide', x + w - pad - bs, cy, bs, ui.CrossGlyph, { tip = 'Hide the Shopping list' }) then
        cfg.tracker.visible[1] = false
        app.Dirty()
    end
    cy = cy + slot + Px(10)

    if #entries > 0 then
        -- buy
        local rows = { }
        for _, row in ipairs(result.buy) do
            table.insert(rows, row)
        end
        table.sort(rows, function(a, b)
            if (a.buy == 0) ~= (b.buy == 0) then
                return a.buy > 0
            end
            local aCrystal, bCrystal = IsCrystal(a.id), IsCrystal(b.id)
            if aCrystal ~= bCrystal then
                return aCrystal
            end
            return items.Name(a.id) < items.Name(b.id)
        end)
        if #rows > 0 then
            text.Draw(dl, 'Buy', cx, cy, col(theme.gold), Px(13), true)
            cy = cy + Px(20)
            for index, row in ipairs(rows) do
                if index > tracker.maxBuy or (index > 1 and cy + Px(30) > bottom) then
                    text.Draw(dl, text.Fit(('and %i more in the Resource Planner'):format(#rows - index + 1), Px(12), false, iw), cx, cy, col(theme.textDim), Px(12))
                    cy = cy + Px(18)
                    break
                end
                local h = Px(30)
                local icon = Px(22)
                local done = row.buy == 0
                ui.Slot(dl, cx, cy + Px(1), icon, row.id, done and theme.green or theme.slotBorder, { dim = done })
                local nx = cx + icon + Px(8)
                local right
                if done then
                    right = 'got it'
                else
                    local stack = items.StackSize(row.id)
                    if stack > 1 and row.buy % stack == 0 then
                        right = planner.StackText(row.buy, stack)
                    else
                        right = ('buy %i'):format(row.buy)
                    end
                end
                local rightW = text.Width(right, Px(13), true)
                local nameW = iw - (nx - cx) - rightW - Px(8)
                local held = math.min(row.need, row.used)
                local label = ('%s  %i/%i'):format(items.ShortName(row.id), held, row.need)
                local onYou, inBags, onOthers = stock.Counts(row.id)
                local extra = ''
                if not cfg.planner.useOthers[1] and onOthers > 0 then
                    extra = ('  +%i on mules'):format(onOthers)
                elseif not cfg.planner.useBags[1] and inBags > 0 then
                    extra = ('  +%i in bags'):format(inBags)
                end
                text.Draw(dl, text.Fit(label .. extra, Px(13), false, nameW), nx, cy, col(done and theme.textDim or 0xFFFFFF), Px(13))
                ui.Bar(dl, nx, cy + Px(19), math.max(Px(40), nameW), Px(5), row.need > 0 and held / row.need or 1, done and theme.fills.mp or theme.fills.tp)
                text.DrawRight(dl, right, cx + iw, cy + Px(4), col(done and theme.green or 0xFFFFFF), Px(13), true)
                cy = cy + h
            end
            cy = cy + Px(6)
        end

        -- make
        local makes = { }
        for _, row in ipairs(result.made) do
            if row.synths > 0 then
                table.insert(makes, { id = row.id, recipe = row.recipe, synths = row.synths })
            end
        end
        for _, row in ipairs(result.top) do
            table.insert(makes, { id = row.recipe.result, recipe = row.recipe, synths = row.synths })
        end
        if #makes > 0 then
            text.Draw(dl, 'Make, in order', cx, cy, col(theme.gold), Px(13), true)
            cy = cy + Px(20)
            for index, row in ipairs(makes) do
                if index > tracker.maxMake or (index > 1 and cy + Px(26) > bottom) then
                    text.Draw(dl, text.Fit(('and %i more'):format(#makes - index + 1), Px(12), false, iw), cx, cy, col(theme.textDim), Px(12))
                    cy = cy + Px(18)
                    break
                end
                local h = Px(26)
                text.Draw(dl, tostring(index), cx, cy + Px(3), col(theme.textMuted), Px(13), true)
                local icon = Px(20)
                ui.Slot(dl, cx + Px(16), cy, icon, row.id, theme.slotBorder)
                local estimate = app.Estimate(row.recipe)
                local tier = '-'
                local tierRgb = theme.textDim
                if estimate ~= nil and not estimate.unknown then
                    if estimate.underCap then
                        tier = ('%i under'):format(-estimate.margin)
                        tierRgb = theme.amber
                    else
                        tier = estimate.tier.name
                        tierRgb = estimate.ring and theme.amber or theme.gold
                    end
                end
                local tierW = text.Width(tier, Px(12.5))
                local nx = cx + Px(16) + icon + Px(8)
                local label = ('%s x%i'):format(items.ShortName(row.id), row.synths)
                text.Draw(dl, text.Fit(label, Px(13), false, iw - (nx - cx) - tierW - Px(30)), nx, cy + Px(3), col(0xFFFFFF), Px(13))
                local main = recipes.MainCraft(row.recipe)
                if main ~= nil then
                    ui.Emblem(dl, cx + iw - tierW - Px(22), cy + Px(2), Px(16), main)
                end
                text.DrawRight(dl, tier, cx + iw, cy + Px(4), col(tierRgb), Px(12.5))
                cy = cy + h
            end
            cy = cy + Px(4)
        end
    end

    -- how far your macro is, quietly, or what you ran out of
    if showRun then
        if missing ~= nil then
            local label = text.Fit(('Out of %s'):format(items.ShortName(missing)), Px(13.5), true, iw)
            text.Draw(dl, label, cx, cy, col(theme.red), Px(13.5), true)
            cy = cy + math.max(Px(22), text.H(Px(13.5)) + Px(6))
        else
            local every = app.AlertEvery()
            local label = text.Fit(('%i of %i synths done'):format(count, every), Px(12.5), false, iw)
            text.Draw(dl, label, cx, cy, col(theme.textMuted), Px(12.5))
            cy = cy + math.max(Px(20), text.H(Px(12.5)) + Px(6))
        end
    end

    -- skill-up check on the last synth
    if last ~= nil then
        local line, rgb = SkillupLine(last)
        if line ~= nil then
            text.Draw(dl, text.Fit(line, Px(12.5), false, iw), cx, cy, col(rgb), Px(12.5))
            cy = cy + Px(20)
        end
    end

    text.Draw(dl, '/hcraft opens the book', cx, cy, col(theme.textDim), Px(12))
    cy = cy + math.max(Px(18), text.H(Px(12)) + Px(6)) + Px(10)

    if ui.ResizeGrip(dl, 'tracker', x, y, w, cy - y, cfg.tracker, tracker.limits) then
        app.Dirty()
    end
    text.full = false
    imgui.SetCursorScreenPos({ x, cy - 1 })
    imgui.Dummy({ w, 1 })
    sizes[name] = { w, cy - y }
    guard.End()
    guard.PopStyleVar(3)
end

return tracker
