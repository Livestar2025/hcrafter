-- fanfare: short banners over the game for level-ups, skill-ups, HQs and
-- breaks, plus toasts for the alert after your macro, each with the sound
-- picked for it in Settings: one of the game's own sounds, read from your
-- game folder, or one of HCrafter's (see sounds\README.txt). drawn on the
-- foreground list so no window gets focus. part of HCrafter, GPL-3.0.
local imgui = require('imgui')
local theme = require('hc.theme')
local text = require('hc.text')
local ui = require('hc.ui')
local items = require('hc.items')
local recipes = require('hc.recipes')
local sounds = require('hc.sounds')

local fanfare = {
    clock = os.clock,
    maxBanners = 3,
    -- the alert whose sound played last
    lastSound = nil,
    -- set by hcrafter.lua: returns the settings, which hold the sound
    -- picked for each alert
    Config = function() return nil end,
}

local col = theme.col
local Px = ui.Px
local banners = { }
local toasts = { }

-- what plays for an alert when its game sound can't be: HCrafter's own
-- sound for that alert
fanfare.fallback = {
    levelUp = 'levelup.wav', hq = 'hq.wav', hqBig = 'hq_big.wav', breaks = 'break.wav',
    skillUp = 'blip.wav', noMore = 'bell.wav', done = 'ready.wav', short = 'alert.wav',
    startup = 'chimes.wav', shutdown = 'dingdong.wav',
}

-- the volume of every sound, a whole percent from 0 to 150
function fanfare.Volume()
    local cfg = fanfare.Config and fanfare.Config()
    local ref = cfg ~= nil and cfg.soundVolume or nil
    return sounds.Volume(type(ref) == 'table' and ref[1] or nil)
end

-- play a sound for an alert at the set volume (or the one given). a game
-- sound that isn't there, or can't be read, plays HCrafter's own sound for
-- that alert. returns true when something played.
function fanfare.PlayChoice(key, choice, volume)
    if type(choice) ~= 'string' or choice == '' then
        return false
    end
    volume = volume ~= nil and sounds.Volume(volume) or fanfare.Volume()
    if sounds.Play(choice, volume) then
        return true
    end
    local fallback = fanfare.fallback[key]
    if sounds.GameId(choice) ~= nil and fallback ~= nil then
        return sounds.Play(fallback, volume)
    end
    return false
end

-- play the sound picked for an alert: levelUp, skillUp, hq, hqBig,
-- breaks, noMore, done, short, startup or shutdown. nothing plays with sounds off in Settings,
-- with None picked, or at volume 0.
function fanfare.Sound(key)
    local cfg = fanfare.Config()
    if cfg == nil or cfg.sounds == nil or not (cfg.fanfare and cfg.fanfare.sound[1]) then
        return false
    end
    local choice = cfg.sounds[key]
    local file = type(choice) == 'table' and choice[1] or nil
    if type(file) ~= 'string' or file == '' then
        return false
    end
    fanfare.lastSound = key
    return fanfare.PlayChoice(key, file)
end

-- banner: { kind = 'levelup' | 'skillup' | 'hq' | 'break', title, sub,
-- itemId, craftId, size = 1 (normal) to 3 (big), rgb }
function fanfare.Push(banner)
    banner.born = fanfare.clock()
    banner.size = banner.size or 1
    banner.duration = banner.duration or (2.6 + banner.size * 0.6)
    table.insert(banners, 1, banner)
    while #banners > fanfare.maxBanners do
        table.remove(banners)
    end
end

-- a small toast near the bottom of the screen. two can show at once, the
-- newest at the bottom.
function fanfare.Toast(toast)
    toast.born = fanfare.clock()
    toast.duration = toast.duration or 2.4
    local keep = { }
    for _, old in ipairs(toasts) do
        if old.title ~= toast.title then
            keep[#keep + 1] = old
        end
    end
    keep[#keep + 1] = toast
    while #keep > 2 do
        table.remove(keep, 1)
    end
    toasts = keep
end

function fanfare.Clear()
    banners = { }
    toasts = { }
end

function fanfare.Count()
    return #banners, #toasts
end

local function Ease(t)
    return 1 - (1 - t) * (1 - t)
end

-- alpha and slide for a banner's age
local function Envelope(age, duration)
    if age < 0.18 then
        local t = Ease(math.max(0, age) / 0.18)
        return 0.25 + 0.75 * t, (1 - t) * Px(14)
    elseif age > duration - 0.6 then
        return math.max(0, (duration - age) / 0.6), 0
    end
    return 1, 0
end

local function DrawBanner(dl, banner, cx, y, age)
    local alpha, slide = Envelope(age, banner.duration)
    if alpha <= 0 then
        return 0
    end
    y = y + slide
    local big = banner.size
    local w = Px(300 + big * 60)
    local h = Px(52 + big * 10)
    local x = cx - w / 2
    local rgb = banner.rgb or theme.gold
    local frame = theme.Frame(ui.frame)

    -- a soft halo, wider for bigger moments
    for i = big, 1, -1 do
        local grow = Px(i * 5)
        ui.Rect(dl, x - grow, y - grow, x + w + grow, y + h + grow, col(rgb, 0.05 * alpha), Px(8 + i * 2))
    end
    ui.Rect(dl, x, y, x + w, y + h, col(frame.bg, 0.92 * alpha), Px(5))
    ui.VGradient(dl, x + 2, y + 2, x + w - 2, y + h / 2, col(rgb, 0.16 * alpha), col(rgb, 0))
    ui.Outline(dl, x, y, x + w, y + h, col(rgb, 0.85 * alpha), Px(5), math.max(1, Px(1.5)))

    -- sparkles for HQs
    if banner.kind == 'hq' and big >= 2 then
        local now = age * (1.6 + big * 0.3)
        for i = 1, 4 + big * 2 do
            local angle = i * 2.399 + now
            local radius = (w / 2 + Px(10)) * (0.55 + 0.45 * ((i * 0.37 + now * 0.25) % 1))
            local sx = cx + math.cos(angle) * radius
            local sy = y + h / 2 + math.sin(angle) * radius * 0.45
            local twinkle = 0.5 + 0.5 * math.sin(age * 7 + i)
            ui.StarGlyph(dl, sx, sy, Px(3 + (i % 3)), col(theme.gold, alpha * twinkle))
        end
    end

    local iconSize = h - Px(16)
    local ix = x + Px(10)
    local iy = y + Px(8)
    if banner.itemId ~= nil then
        ui.Slot(dl, ix, iy, iconSize, banner.itemId, rgb, { glow = big >= 2, hq = banner.kind == 'hq' })
    elseif banner.craftId ~= nil then
        ui.Emblem(dl, ix, iy, iconSize, banner.craftId, { ring = banner.kind == 'levelup' })
    end
    local tx = ix + iconSize + Px(12)
    local titleSize = Px(16 + big * 2)
    text.Draw(dl, banner.title or '', tx, iy + Px(1), col(rgb, alpha), titleSize, true)
    if banner.sub ~= nil then
        local subSize = Px(12.5)
        text.Draw(dl, text.Fit(banner.sub, subSize, false, x + w - Px(10) - tx), tx, iy + titleSize + Px(4), col(theme.textSoft, alpha), subSize)
    end

    -- a sweep for level-ups
    if banner.kind == 'levelup' then
        local sweep = math.min(1, age / 0.9)
        ui.Bar(dl, x + Px(10), y + h - Px(7), (w - Px(20)), Px(4), sweep, theme.fills.exp)
    end
    return h + Px(10)
end

local function DrawToast(dl, toast, cx, y, age)
    local alpha = Envelope(age, toast.duration)
    if alpha <= 0 then
        return
    end
    local s = Px(15)
    local display = imgui.GetIO().DisplaySize
    local label = text.Fit(toast.title or '', s, true, display.x - Px(60))
    local w = text.Width(label, s, true) + Px(36)
    local h = Px(34)
    local x = cx - w / 2
    local rgb = toast.rgb or theme.gold
    local pulse = 0.6 + 0.4 * math.sin(age * 8)
    ui.Rect(dl, x - Px(4), y - Px(4), x + w + Px(4), y + h + Px(4), col(rgb, 0.08 * alpha * pulse), Px(10))
    ui.Rect(dl, x, y, x + w, y + h, col(0x0A0C10, 0.85 * alpha), Px(8))
    ui.Outline(dl, x, y, x + w, y + h, col(rgb, 0.9 * alpha), Px(8), math.max(1, Px(1.5)))
    text.DrawCenter(dl, label, cx, y + (h - s) / 2 - 1, col(rgb, alpha), s, true)
end

-- call once a frame, after the windows
function fanfare.Draw()
    if #banners == 0 and #toasts == 0 then
        return
    end
    local now = fanfare.clock()
    local display = imgui.GetIO().DisplaySize
    local dl = imgui.GetForegroundDrawList()
    text.full = true
    local cx = display.x / 2
    local y = display.y * 0.16

    local keep = { }
    for _, banner in ipairs(banners) do
        local age = now - banner.born
        if age < banner.duration then
            y = y + DrawBanner(dl, banner, cx, y, age)
            table.insert(keep, banner)
        end
    end
    banners = keep

    local keepToasts = { }
    for _, toast in ipairs(toasts) do
        if now - toast.born < toast.duration then
            table.insert(keepToasts, toast)
        end
    end
    toasts = keepToasts
    -- stacked upward from the lowest one
    local ty = display.y * 0.72
    for i = #toasts, 1, -1 do
        local toast = toasts[i]
        DrawToast(dl, toast, cx, ty, now - toast.born)
        ty = ty - Px(42)
    end
    text.full = false
end

---------------------------------------------------------------------------
-- the events HCrafter raises. cfg is the fanfare settings table.
---------------------------------------------------------------------------

function fanfare.LevelUp(cfg, craftId, level)
    if not cfg.levelUp[1] then
        return
    end
    fanfare.Push({
        kind = 'levelup',
        craftId = craftId,
        title = ('%s %i'):format(recipes.skillNames[craftId] or 'Craft', level),
        sub = 'Level up!',
        size = 3,
    })
    fanfare.Sound('levelUp')
end

function fanfare.SkillUp(cfg, craftId, change, now)
    if not cfg.skillUp[1] then
        return
    end
    fanfare.Push({
        kind = 'skillup',
        craftId = craftId,
        title = ('%s %+.1f'):format(recipes.skillNames[craftId] or 'Craft', change),
        sub = ('Now %.1f'):format(now),
        size = 1,
        duration = 2.2,
        rgb = change >= 0 and theme.gold or theme.red,
    })
    fanfare.Sound('skillUp')
end

-- quality: 2 HQ, 3 HQ2, 4 HQ3. chance: the estimated chance of this
-- result, or nil. only hard HQs get fanfare: T0 (about 1 in 64) gets the
-- biggest, T1 (about 1 in 16) the middle one. easy HQs (better than 1 in
-- 10, such as T2 and T3) only get a banner when cfg.hqEasy is on.
function fanfare.HQ(cfg, itemId, count, quality, chance)
    if not cfg.hq[1] then
        return
    end
    local size
    if chance ~= nil then
        if chance > 0.1 and not (cfg.hqEasy and cfg.hqEasy[1]) then
            return
        end
        if chance < 0.04 then
            size = 3
        elseif chance < 0.1 then
            size = 2
        else
            size = 1
        end
    else
        size = math.max(1, math.min(3, quality - 1))
    end
    local title = quality >= 3 and ('HQ%i!'):format(quality - 1) or 'HQ!'
    local sub = items.ShortName(itemId)
    if count ~= nil and count > 1 then
        sub = ('%s x%i'):format(sub, count)
    end
    if chance ~= nil and chance > 0 then
        sub = ('%s, about 1 in %i'):format(sub, math.floor(1 / chance + 0.5))
    end
    fanfare.Push({ kind = 'hq', itemId = itemId, title = title, sub = sub, size = size })
    fanfare.Sound(size >= 2 and 'hqBig' or 'hq')
end

function fanfare.Break(cfg, itemId, lost)
    if not cfg.breaks[1] then
        return
    end
    local sub
    if lost ~= nil and #lost > 0 then
        local names = { }
        for _, id in ipairs(lost) do
            table.insert(names, items.ShortName(id))
        end
        sub = 'Lost ' .. table.concat(names, ', ')
    else
        sub = 'Only the crystal was lost'
    end
    fanfare.Push({
        kind = 'break',
        itemId = lost and lost[1] or itemId,
        title = 'Synthesis failed',
        sub = sub,
        size = 1,
        rgb = theme.red,
    })
    fanfare.Sound('breaks')
end

-- the recipe you repeat stopped giving skill-ups
function fanfare.NoMoreSkillups(craftId, level, itemId)
    fanfare.Toast({
        title = ('%s %i: no more skill-ups from %s'):format(recipes.skillNames[craftId] or 'Craft', level, items.ShortName(itemId or 0)),
        rgb = theme.amber,
        duration = 4,
    })
    fanfare.Sound('noMore')
end

-- the alert after your macro: count is the macro lines in the run
function fanfare.SynthsDone(count)
    fanfare.Toast({ title = ('Macro done: %i synth%s'):format(count, count == 1 and '' or 's'), rgb = theme.gold, duration = 3 })
    fanfare.Sound('done')
end

-- you are out of a material for another synth like the last one
function fanfare.OutOf(itemId)
    fanfare.Toast({ title = ('Out of %s'):format(items.ShortName(itemId or 0)), rgb = theme.red, duration = 3.5 })
    fanfare.Sound('short')
end

return fanfare
