-- the cool mode drawing kit: window frames, item slots, guild emblems,
-- gradient bars, the HQ tier ladder, chips and a few custom widgets. it
-- draws with imgui draw lists and invisible buttons, the same calls XIUI
-- uses, so it needs nothing outside Ashita's imgui. it never sends
-- anything to the game.
require('common')
local bit = require('bit')
local imgui = require('imgui')
local guard = require('hc.guard')
local theme = require('hc.theme')
local text = require('hc.text')
local icons = require('hc.icons')
local items = require('hc.items')
local recipes = require('hc.recipes')

local ui = {
    -- the scale everything is drawn at: Size, times Ashita's font size when
    -- that setting is on
    S = 1,
    -- the Size setting alone
    size = 1,
    frame = 1,
    bgAlpha = 0.92,
    gameIcons = true,
}

local col = theme.col

local function V(x, y)
    return { x, y }
end

-- a size scaled by the look setting
function ui.Px(value)
    return value * ui.S
end
local Px = ui.Px

-- Ashita's default font size: 18 pixels since Ashita 4.3, whose imgui
-- (1.92) has style.FontSizeBase, and 14 before that. HCrafter's 100% is
-- drawn for that size. XIUI tells the two apart the same way.
local defaultFontPx = nil
function ui.AshitaDefaultPx()
    if defaultFontPx == nil then
        local ok, base = pcall(function() return imgui.GetStyle().FontSizeBase end)
        defaultFontPx = (ok and type(base) == 'number') and 18 or 14
    end
    return defaultFontPx
end

-- Ashita's own font size in pixels, or nil when it can't be read
function ui.AshitaFontPx()
    local ok, lineH = pcall(function() return imgui.GetTextLineHeight() end)
    if not ok or type(lineH) ~= 'number' or lineH ~= lineH or lineH <= 0 or lineH > 1000 then
        return nil
    end
    return lineH
end

-- Ashita's own font size as a scale: 1 at Ashita's default size, and more
-- for a player who made Ashita's font bigger, say for a 4K screen
function ui.AshitaScale()
    local lineH = ui.AshitaFontPx()
    if lineH == nil then
        return 1
    end
    local scale = math.floor(lineH / ui.AshitaDefaultPx() * 20 + 0.5) / 20
    return math.max(0.75, math.min(3, scale))
end

-- imgui's padding inside an input box and between its parts, read from
-- the style Ashita uses, or imgui's defaults
function ui.StylePads()
    local ok, padX, innerX = pcall(function()
        local style = imgui.GetStyle()
        return style.FramePadding.x, style.ItemInnerSpacing.x
    end)
    if not ok or type(padX) ~= 'number' or type(innerX) ~= 'number' or padX ~= padX or innerX ~= innerX then
        return 4, 4
    end
    return math.max(0, math.min(64, padX)), math.max(0, math.min(64, innerX))
end

-- the height of imgui's own input boxes: Ashita's font plus padding
function ui.FrameHeight()
    -- GetFrameHeight is looked up inside the pcall, in case an Ashita build
    -- lacks it
    local ok, h = pcall(function() return imgui.GetFrameHeight() end)
    if ok and type(h) == 'number' and h == h and h > 0 and h < 1000 then
        return h
    end
    return imgui.GetTextLineHeight() + 6
end

-- a string's width in Ashita's font, as imgui's own input boxes draw it
function ui.ImWidth(s)
    local w = tonumber((imgui.CalcTextSize(s)))
    if w == nil or w ~= w or w < 0 or w == math.huge then
        return 0
    end
    return w
end

-- letters drawn as part of an icon (its stand-in letters, a count, a
-- badge) keep the icon's size, whatever the Text size setting
local function IconText(draw, ...)
    local scale = text.scale
    text.scale = 1
    draw(...)
    text.scale = scale
end

---------------------------------------------------------------------------
-- primitives
---------------------------------------------------------------------------

function ui.Rect(dl, x1, y1, x2, y2, color, rounding, flags)
    dl:AddRectFilled(V(x1, y1), V(x2, y2), color, rounding or 0, flags or 0)
end

function ui.Outline(dl, x1, y1, x2, y2, color, rounding, thickness)
    dl:AddRect(V(x1, y1), V(x2, y2), color, rounding or 0, 0, thickness or 1)
end

function ui.Line(dl, x1, y1, x2, y2, color, thickness)
    dl:AddLine(V(x1, y1), V(x2, y2), color, thickness or 1)
end

-- left to right gradient between two imgui colors
function ui.HGradient(dl, x1, y1, x2, y2, left, right)
    if x2 - x1 < 1 or y2 - y1 < 0.5 then
        return
    end
    dl:AddRectFilledMultiColor(V(x1, y1), V(x2, y2), left, right, right, left)
end

-- top to bottom gradient between two imgui colors
function ui.VGradient(dl, x1, y1, x2, y2, top, bottom)
    if x2 - x1 < 0.5 or y2 - y1 < 1 then
        return
    end
    dl:AddRectFilledMultiColor(V(x1, y1), V(x2, y2), top, top, bottom, bottom)
end

-- a 1px line that fades out at both ends, like XIUI's dividers
function ui.FadeLine(dl, x1, y, x2, rgb, alpha)
    local mid = (x1 + x2) / 2
    ui.HGradient(dl, x1, y, mid, y + 1, col(rgb, 0), col(rgb, alpha or 0.6))
    ui.HGradient(dl, mid, y, x2, y + 1, col(rgb, alpha or 0.6), col(rgb, 0))
end

-- a 1px line that fades out to the right
function ui.FadeRight(dl, x1, y, x2, rgb, alpha)
    ui.HGradient(dl, x1, y, x2, y + 1, col(rgb, alpha or 0.5), col(rgb, 0))
end

---------------------------------------------------------------------------
-- glyphs, drawn with lines so they need no icon font
---------------------------------------------------------------------------

function ui.CheckGlyph(dl, x, y, s, color)
    local t = math.max(1.5, s / 7)
    ui.Line(dl, x + s * 0.16, y + s * 0.54, x + s * 0.4, y + s * 0.78, color, t)
    ui.Line(dl, x + s * 0.4, y + s * 0.78, x + s * 0.86, y + s * 0.24, color, t)
end

function ui.CrossGlyph(dl, x, y, s, color)
    local t = math.max(1.5, s / 7)
    ui.Line(dl, x + s * 0.22, y + s * 0.22, x + s * 0.78, y + s * 0.78, color, t)
    ui.Line(dl, x + s * 0.78, y + s * 0.22, x + s * 0.22, y + s * 0.78, color, t)
end

-- a chevron: right when closed, down when open
function ui.ChevronGlyph(dl, x, y, s, open, color)
    local t = math.max(1.5, s / 6)
    if open then
        ui.Line(dl, x + s * 0.18, y + s * 0.36, x + s * 0.5, y + s * 0.68, color, t)
        ui.Line(dl, x + s * 0.5, y + s * 0.68, x + s * 0.82, y + s * 0.36, color, t)
    else
        ui.Line(dl, x + s * 0.36, y + s * 0.18, x + s * 0.68, y + s * 0.5, color, t)
        ui.Line(dl, x + s * 0.68, y + s * 0.5, x + s * 0.36, y + s * 0.82, color, t)
    end
end

function ui.PlusGlyph(dl, x, y, s, color)
    local t = math.max(1.5, s / 7)
    ui.Line(dl, x + s * 0.2, y + s * 0.5, x + s * 0.8, y + s * 0.5, color, t)
    ui.Line(dl, x + s * 0.5, y + s * 0.2, x + s * 0.5, y + s * 0.8, color, t)
end

function ui.MinusGlyph(dl, x, y, s, color)
    local t = math.max(1.5, s / 7)
    ui.Line(dl, x + s * 0.2, y + s * 0.5, x + s * 0.8, y + s * 0.5, color, t)
end

-- three lines with bullets: the Resource Planner
function ui.ListGlyph(dl, x, y, s, color)
    local t = math.max(1.2, s / 9)
    for i = 0, 2 do
        local ly = y + s * (0.26 + i * 0.24)
        dl:AddCircleFilled(V(x + s * 0.2, ly), math.max(1, s * 0.07), color, 8)
        ui.Line(dl, x + s * 0.36, ly, x + s * 0.86, ly, color, t)
    end
end

-- a small flag: the Shopping list tracker
function ui.FlagGlyph(dl, x, y, s, color)
    local t = math.max(1.2, s / 9)
    ui.Line(dl, x + s * 0.26, y + s * 0.14, x + s * 0.26, y + s * 0.88, color, t)
    dl:AddTriangleFilled(V(x + s * 0.28, y + s * 0.16), V(x + s * 0.82, y + s * 0.32), V(x + s * 0.28, y + s * 0.5), color)
end

-- an open book: the recipe book
function ui.BookGlyph(dl, x, y, s, color)
    local t = math.max(1.2, s / 9)
    local mx = x + s * 0.5
    ui.Line(dl, x + s * 0.1, y + s * 0.24, mx, y + s * 0.32, color, t)
    ui.Line(dl, mx, y + s * 0.32, x + s * 0.9, y + s * 0.24, color, t)
    ui.Line(dl, x + s * 0.1, y + s * 0.24, x + s * 0.1, y + s * 0.8, color, t)
    ui.Line(dl, x + s * 0.9, y + s * 0.24, x + s * 0.9, y + s * 0.8, color, t)
    ui.Line(dl, x + s * 0.1, y + s * 0.8, mx, y + s * 0.88, color, t)
    ui.Line(dl, mx, y + s * 0.88, x + s * 0.9, y + s * 0.8, color, t)
    ui.Line(dl, mx, y + s * 0.32, mx, y + s * 0.88, color, t)
end

function ui.SearchGlyph(dl, x, y, s, color)
    local t = math.max(1.2, s / 8)
    dl:AddCircle(V(x + s * 0.42, y + s * 0.42), s * 0.28, color, 16, t)
    ui.Line(dl, x + s * 0.62, y + s * 0.62, x + s * 0.88, y + s * 0.88, color, t)
end

-- a warning triangle with a bar
function ui.WarnGlyph(dl, x, y, s, color)
    dl:AddTriangleFilled(V(x + s * 0.5, y + s * 0.08), V(x + s * 0.95, y + s * 0.9), V(x + s * 0.05, y + s * 0.9), color)
    local dark = col(theme.black, 0.85)
    ui.Line(dl, x + s * 0.5, y + s * 0.38, x + s * 0.5, y + s * 0.64, dark, math.max(1.2, s / 8))
    dl:AddCircleFilled(V(x + s * 0.5, y + s * 0.76), math.max(1, s * 0.06), dark, 8)
end

-- a four point star, for HQ
function ui.StarGlyph(dl, cx, cy, r, color)
    local k = r * 0.32
    dl:AddTriangleFilled(V(cx, cy - r), V(cx + k, cy), V(cx - k, cy), color)
    dl:AddTriangleFilled(V(cx, cy + r), V(cx - k, cy), V(cx + k, cy), color)
    dl:AddTriangleFilled(V(cx - r, cy), V(cx, cy - k), V(cx, cy + k), color)
    dl:AddTriangleFilled(V(cx + r, cy), V(cx, cy + k), V(cx, cy - k), color)
end

---------------------------------------------------------------------------
-- window frame, slots, emblems, bars
---------------------------------------------------------------------------

-- the window background: navy or charcoal panel, light edge, bright corner
-- brackets
function ui.WindowFrame(dl, x, y, w, h, alpha)
    local frame = theme.Frame(ui.frame)
    alpha = alpha or ui.bgAlpha
    ui.Rect(dl, x, y, x + w, y + h, col(frame.bg, alpha), Px(4))
    ui.VGradient(dl, x + 2, y + 2, x + w - 2, y + Px(42), col(0xFFFFFF, 0.05 * alpha), col(0xFFFFFF, 0))
    ui.Outline(dl, x + 1, y + 1, x + w - 1, y + h - 1, col(theme.black, 0.35 * alpha), Px(3), 1)
    ui.Outline(dl, x, y, x + w, y + h, col(frame.edge, 0.55 * alpha), Px(4), 1)
    local c = col(frame.corner, 0.95 * math.max(alpha, 0.5))
    local k = Px(9)
    local t = math.max(1.5, Px(2))
    ui.Line(dl, x, y + t / 2, x + k, y + t / 2, c, t)
    ui.Line(dl, x + t / 2, y, x + t / 2, y + k, c, t)
    ui.Line(dl, x + w - k, y + t / 2, x + w, y + t / 2, c, t)
    ui.Line(dl, x + w - t / 2, y, x + w - t / 2, y + k, c, t)
    ui.Line(dl, x, y + h - t / 2, x + k, y + h - t / 2, c, t)
    ui.Line(dl, x + t / 2, y + h - k, x + t / 2, y + h, c, t)
    ui.Line(dl, x + w - k, y + h - t / 2, x + w, y + h - t / 2, c, t)
    ui.Line(dl, x + w - t / 2, y + h - k, x + w - t / 2, y + h, c, t)
end

local function Initials(itemId)
    local name = items.ShortName(itemId) or '?'
    local first, second = name:match('^(%w)%w*%s+(%w)')
    if first then
        return (first .. second):upper()
    end
    return (name:sub(1, 2)):upper()
end

-- an item slot with the game's icon. border is a 0xRRGGBB color.
-- opts: glow (soft gold halo), count (number in the corner), hq (star),
-- dim (draw faded)
function ui.Slot(dl, x, y, size, itemId, border, opts)
    opts = opts or { }
    local alpha = opts.dim and 0.45 or 1
    if opts.glow then
        ui.Outline(dl, x - 2, y - 2, x + size + 2, y + size + 2, col(theme.gold, 0.22), Px(3), 2)
    end
    ui.Rect(dl, x, y, x + size, y + size, col(theme.bgMedium, 0.96))

    local icon = ui.gameIcons and itemId ~= nil and icons.Item(itemId) or nil
    if icon ~= nil then
        local iconSize = size >= Px(40) and math.floor(size * 0.8) or size - 4
        local pad = (size - iconSize) / 2
        dl:AddImage(icon, V(x + pad, y + pad), V(x + pad + iconSize, y + pad + iconSize), V(0, 0), V(1, 1), col(0xFFFFFF, alpha))
    elseif itemId ~= nil and itemId > 0 then
        local label = Initials(itemId)
        local s = math.max(9, size * 0.34)
        IconText(text.DrawCenter, dl, label, x + size / 2, y + (size - s) / 2 - 1, col(theme.goldDark, 0.9 * alpha), s, true)
    end

    ui.Outline(dl, x + 1, y + 1, x + size - 1, y + size - 1, col(theme.black, 0.6), 0, 1)
    ui.Outline(dl, x, y, x + size, y + size, col(border or theme.slotBorder, alpha), 0, 1)

    if opts.hq then
        ui.StarGlyph(dl, x + size - Px(7), y + Px(7), Px(5), col(theme.gold))
    end
    if opts.count ~= nil and opts.count > 1 then
        local s = math.max(10, size * 0.28)
        IconText(text.DrawRight, dl, tostring(opts.count), x + size - 3, y + size - s - 2, col(0xFFFFFF), s, true)
    end
end

-- a guild emblem: the craft's imagery icon from the game, or a drawn badge
-- with the craft's short name. opts: ring (gold halo), dim
function ui.Emblem(dl, x, y, size, craftId, opts)
    opts = opts or { }
    local alpha = opts.dim and 0.45 or 1
    if opts.ring then
        ui.Rect(dl, x - 3, y - 3, x + size + 3, y + size + 3, col(theme.gold, 0.16), Px(6))
        ui.Outline(dl, x - 2, y - 2, x + size + 2, y + size + 2, col(theme.gold, 0.95), Px(6), math.max(1.5, Px(2)))
    end

    local icon = ui.gameIcons and icons.Emblem(craftId) or nil
    if icon ~= nil then
        dl:AddImage(icon, V(x, y), V(x + size, y + size), V(0, 0), V(1, 1), col(0xFFFFFF, alpha))
        return
    end

    local rgb = theme.crafts[craftId] or theme.goldDark
    local cx, cy, r = x + size / 2, y + size / 2, size / 2 - 1
    dl:AddCircleFilled(V(cx, cy), r, col(theme.mix(rgb, theme.bgDark, 0.72), 0.95 * alpha), 24)
    dl:AddCircle(V(cx, cy), r, col(rgb, alpha), 24, math.max(1.2, size / 18))
    dl:AddCircle(V(cx, cy), r - math.max(2, size / 9), col(rgb, 0.35 * alpha), 24, 1)
    local label = recipes.skillAbbr[craftId] or '?'
    local s = math.max(8, size * 0.3)
    IconText(text.DrawCenter, dl, label, cx, cy - s / 2 - 1, col(rgb, alpha), s, true)
end

-- a bar in XIUI's style: dark navy track, gradient fill, end caps.
-- fill is { leftRgb, rightRgb }
function ui.Bar(dl, x, y, w, h, frac, fill)
    frac = math.max(0, math.min(1, frac or 0))
    fill = fill or theme.fills.exp
    local r = h / 2
    ui.Rect(dl, x, y, x + w, y + h, col(theme.trackBottom), r)
    ui.VGradient(dl, x + r, y + 1, x + w - r, y + h / 2, col(theme.trackTop), col(theme.trackBottom))

    local fw = w * frac
    if fw >= 1 then
        local left, right = col(fill[1]), col(theme.mix(fill[1], fill[2], frac))
        if fw <= 2 * r then
            ui.Rect(dl, x, y, x + fw, y + h, left, math.min(r, fw / 2))
        else
            ui.Rect(dl, x, y, x + 2 * r, y + h, left, r, ImDrawFlags_RoundCornersLeft)
            ui.HGradient(dl, x + r, y, x + fw - r, y + h, left, right)
            ui.Rect(dl, x + fw - 2 * r, y, x + fw, y + h, right, r, ImDrawFlags_RoundCornersRight)
        end
        ui.HGradient(dl, x + r, y + 1, x + math.max(r, fw - r), y + 2, col(0xFFFFFF, 0.28), col(0xFFFFFF, 0.12))
    end

    -- end caps
    local capW = math.max(3, Px(5))
    ui.Rect(dl, x + 1, y + 1, x + 1 + capW, y + h - 1, col(theme.capMid, 0.85), r, ImDrawFlags_RoundCornersLeft)
    ui.Rect(dl, x + w - 1 - capW, y + 1, x + w - 1, y + h - 1, col(theme.capMid, 0.85), r, ImDrawFlags_RoundCornersRight)
    ui.Outline(dl, x, y, x + w, y + h, col(theme.black), r, 1)
end

-- a bordered chip with text, returns its width. rgb sets text and border.
function ui.Chip(dl, x, y, label, rgb, size, bold)
    size = size or Px(12)
    local padX = Px(7)
    local h = text.H(size) + Px(5)
    local w = text.Width(label, size, bold) + padX * 2
    ui.Rect(dl, x, y, x + w, y + h, col(rgb, 0.16), Px(3))
    ui.Outline(dl, x, y, x + w, y + h, col(rgb, 0.7), Px(3), 1)
    text.Draw(dl, label, x + padX, y + (h - size) / 2 - 1, col(rgb), size, bold)
    return w, h
end

function ui.ChipWidth(label, size, bold)
    size = size or Px(12)
    return text.Width(label, size, bold) + Px(7) * 2
end

-- the HQ tier ladder. margin is levels over cap. tierIndex -1 under cap.
-- opts: craftName, success (under cap), ring (no HQ)
function ui.Ladder(dl, x, y, w, margin, tierIndex, opts)
    opts = opts or { }
    local scale = 60
    local small = Px(11.5)
    local barY = y + Px(17)
    local barH = Px(12)
    if tierIndex < 0 then
        -- under cap there is no HQ, so the bar shows the chance to succeed
        text.Draw(dl, 'No HQ under cap', x, y, col(theme.amber), small, true)
        text.DrawRight(dl, 'success', x + w, y, col(theme.textDim), small)
        ui.Bar(dl, x, barY, w, barH, (opts.success or 0) / 100, { 0xC9573F, 0xF0A93A })
        for _, at in ipairs({ 0.25, 0.5, 0.75 }) do
            local tx = math.floor(x + w * at) + 0.5
            ui.Line(dl, tx, barY + 1, tx, barY + barH - 1, col(0xFFFFFF, 0.35), 1)
        end
    else
        local labels = { { 'T0', '1/64', 5.5 }, { 'T1', '1/16', 21 }, { 'T2', '1/4', 41 }, { 'T3', '1/2', 55.5 } }
        for i, label in ipairs(labels) do
            local active = (i - 1) == tierIndex
            local s = ('%s  %s'):format(label[1], label[2])
            local cx = x + w * label[3] / scale
            text.DrawCenter(dl, s, cx, y, col(active and theme.gold or theme.textDim), small, active)
        end
        ui.Bar(dl, x, barY, w, barH, math.min(margin, scale) / scale, theme.fills.exp)
        for _, at in ipairs({ 11, 31, 51 }) do
            local tx = math.floor(x + w * at / scale) + 0.5
            ui.Line(dl, tx, barY + 1, tx, barY + barH - 1, col(0xFFFFFF, 0.5), 1)
        end
    end

    local capY = barY + barH + Px(4)
    local s = Px(12)
    local name = opts.craftName or ''
    local left, right
    if tierIndex < 0 then
        left = ('%s %i under cap'):format(name, -margin)
        right = ('success about %i%%'):format(opts.success or 0)
    else
        left = ('%s %i over cap'):format(name, margin)
        if opts.ring then
            right = 'a crafting ring blocks HQ'
        elseif tierIndex < 3 then
            local nextAt = ({ [0] = 11, [1] = 31, [2] = 51 })[tierIndex]
            right = ('T%i at %i over'):format(tierIndex + 1, nextAt)
        else
            right = 'top tier'
        end
    end
    text.Draw(dl, left, x, capY, col(theme.textMuted), s)
    text.DrawRight(dl, right, x + w, capY, col(opts.ring and theme.amber or theme.textMuted), s)
    return capY + s + Px(2) - y
end

---------------------------------------------------------------------------
-- layout and widgets. every window keeps its own y and draws at exact
-- spots. invisible buttons go where their box is, and a window or body ends
-- with one dummy at its bottom, so imgui knows the full size for sizing and
-- scrolling.
---------------------------------------------------------------------------

-- an invisible button over a box. returns left-clicked, hovered,
-- right-clicked.
function ui.Hit(id, x, y, w, h)
    imgui.SetCursorScreenPos(V(x, y))
    local clicked = imgui.InvisibleButton(id, V(math.max(1, w), math.max(1, h)))
    local hovered = imgui.IsItemHovered()
    local right = hovered and imgui.IsItemClicked(1)
    return clicked, hovered, right
end

-- a square button with a glyph. draw(dl, x, y, size, color). opts: badge
-- (a number), active, tip
function ui.IconButton(dl, id, x, y, size, draw, opts)
    opts = opts or { }
    local clicked, hovered = ui.Hit(id, x, y, size, size)
    local bg = hovered and theme.bgLighter or theme.bgMedium
    ui.Rect(dl, x, y, x + size, y + size, col(bg, 0.95), Px(3))
    ui.Outline(dl, x, y, x + size, y + size, col(opts.active and theme.goldDarker or theme.border), Px(3), 1)
    local glyph = size * 0.58
    draw(dl, x + (size - glyph) / 2, y + (size - glyph) / 2, glyph, col(opts.active and theme.gold or (hovered and theme.gold or theme.goldDark)))
    if opts.badge ~= nil and opts.badge > 0 then
        local label = tostring(opts.badge)
        local s = Px(10)
        local scale = text.scale
        text.scale = 1
        local bw = math.max(Px(14), text.Width(label, s, true) + Px(6))
        text.scale = scale
        local bx, by = x + size - bw + Px(5), y - Px(5)
        ui.Rect(dl, bx, by, bx + bw, by + Px(14), col(theme.goldBright), Px(7))
        ui.Outline(dl, bx, by, bx + bw, by + Px(14), col(theme.black), Px(7), 1)
        IconText(text.DrawCenter, dl, label, bx + bw / 2, by + (Px(14) - s) / 2 - 1, col(0x1A1408), s, true, false)
    end
    if hovered and opts.tip ~= nil then
        ui.Tip(opts.tip)
    end
    return clicked
end

-- a text button. returns clicked and its width. opts: primary, width, danger
function ui.Button(dl, id, x, y, label, opts)
    opts = opts or { }
    local s = Px(13)
    local h = math.max(Px(24), text.H(s) + Px(8))
    local w = opts.width or (text.Width(label, s) + Px(20))
    local clicked, hovered = ui.Hit(id, x, y, w, h)
    local edge = opts.danger and theme.red or (opts.primary and theme.goldDarker or theme.border)
    local bg = hovered and theme.bgLighter or theme.bgMedium
    if opts.primary then
        ui.Rect(dl, x, y, x + w, y + h, col(theme.gold, hovered and 0.34 or 0.24), Px(3))
    else
        ui.Rect(dl, x, y, x + w, y + h, col(bg, 0.95), Px(3))
    end
    ui.Outline(dl, x, y, x + w, y + h, col(edge), Px(3), 1)
    text.DrawCenter(dl, label, x + w / 2, y + (h - s) / 2 - 1, col(opts.danger and theme.red or (opts.primary and 0xFFFFFF or theme.textSoft)), s)
    return clicked, w
end

-- tabs across a window. returns the selected index. x, y top left, w width
function ui.Tabs(dl, id, x, y, w, labels, selected)
    local s = Px(14)
    local h = math.max(Px(26), text.H(s) + Px(8))
    local tx = x
    for i, label in ipairs(labels) do
        local tw = text.Width(label, s) + Px(32)
        local clicked, hovered = ui.Hit(('%s.tab%i'):format(id, i), tx, y, tw, h)
        if clicked then
            selected = i
        end
        local active = i == selected
        if active then
            ui.Rect(dl, tx, y, tx + tw, y + h, col(theme.gold, 0.3), Px(3), ImDrawFlags_RoundCornersTop)
        else
            ui.Rect(dl, tx, y, tx + tw, y + h, col(hovered and theme.bgLighter or theme.bgMedium, 0.95), Px(3), ImDrawFlags_RoundCornersTop)
        end
        ui.Outline(dl, tx, y, tx + tw, y + h + 1, col(active and theme.goldDarker or theme.border), Px(3), 1)
        text.DrawCenter(dl, label, tx + tw / 2, y + (h - s) / 2 - 1, col(active and 0xFFFFFF or theme.textMuted), s)
        tx = tx + tw + Px(4)
    end
    ui.Line(dl, x, y + h, x + w, y + h, col(theme.goldDarker), 1)
    return selected, h
end

-- a checkbox drawn in the gold style. ref is an { value } table. returns
-- changed and the width used.
function ui.Checkbox(dl, id, x, y, label, ref)
    local s = Px(13)
    local box = Px(15)
    local w = box + Px(7) + text.Width(label, s)
    local h = math.max(box, text.H(s) + Px(4))
    local clicked, hovered = ui.Hit(id, x, y, w, h)
    if clicked then
        ref[1] = not ref[1]
    end
    local by = y + (h - box) / 2
    ui.Rect(dl, x, by, x + box, by + box, col(theme.bgDark, 0.9), Px(2))
    ui.Outline(dl, x, by, x + box, by + box, col(hovered and theme.gold or theme.goldDarker), Px(2), 1)
    if ref[1] then
        ui.CheckGlyph(dl, x + 1, by + 1, box - 2, col(theme.gold))
    end
    text.Draw(dl, label, x + box + Px(7), y + (h - s) / 2 - 1, col(ref[1] and theme.textSoft or theme.textMuted), s)
    return clicked, w, h
end

-- a row of joined buttons, one selected. returns the new selection and width
function ui.Segmented(dl, id, x, y, labels, selected, opts)
    opts = opts or { }
    local s = Px(12.5)
    local h = math.max(Px(22), text.H(s) + Px(7))
    local widths, total = { }, 0
    for i, label in ipairs(labels) do
        widths[i] = opts.width or (text.Width(label, s) + Px(18))
        total = total + widths[i]
    end
    local sx = x
    for i, label in ipairs(labels) do
        local clicked, hovered = ui.Hit(('%s.seg%i'):format(id, i), sx, y, widths[i], h)
        if clicked then
            selected = i
        end
        local active = i == selected
        local flags = 0
        if i == 1 then
            flags = ImDrawFlags_RoundCornersLeft
        elseif i == #labels then
            flags = ImDrawFlags_RoundCornersRight
        else
            flags = ImDrawFlags_RoundCornersNone
        end
        if active then
            ui.Rect(dl, sx, y, sx + widths[i], y + h, col(theme.gold, 0.3), Px(3), flags)
        else
            ui.Rect(dl, sx, y, sx + widths[i], y + h, col(hovered and theme.bgLighter or theme.bgMedium, 0.95), Px(3), flags)
        end
        text.DrawCenter(dl, label, sx + widths[i] / 2, y + (h - s) / 2 - 1, col(active and 0xFFFFFF or theme.textMuted), s)
        sx = sx + widths[i]
    end
    ui.Outline(dl, x, y, x + total, y + h, col(theme.goldDarker), Px(3), 1)
    for i = 1, #labels - 1 do
        local lx = x
        for j = 1, i do
            lx = lx + widths[j]
        end
        ui.Line(dl, lx, y + 1, lx, y + h - 1, col(theme.goldDarker, 0.7), 1)
    end
    return selected, total, h
end

-- [-] value [+]. returns the new value and the width used. step and range
-- in whole numbers unless opts.format says otherwise.
function ui.Stepper(dl, id, x, y, value, low, high, step, opts)
    opts = opts or { }
    local s = Px(13)
    local h = math.max(Px(22), text.H(s) + Px(7))
    local bw = h
    local label = opts.format and opts.format(value) or tostring(value)
    local vw = math.max(opts.minWidth or Px(34), text.Width(label, s, true) + Px(12))
    local minus = ui.Hit(id .. '.minus', x, y, bw, h)
    local plus = ui.Hit(id .. '.plus', x + bw + vw, y, bw, h)
    if minus then
        value = math.max(low, value - step)
    elseif plus then
        value = math.min(high, value + step)
    end
    local total = bw * 2 + vw
    ui.Rect(dl, x, y, x + total, y + h, col(theme.bgDark, 0.85), Px(3))
    ui.Outline(dl, x, y, x + total, y + h, col(theme.border), Px(3), 1)
    ui.Line(dl, x + bw, y + 1, x + bw, y + h - 1, col(theme.border), 1)
    ui.Line(dl, x + bw + vw, y + 1, x + bw + vw, y + h - 1, col(theme.border), 1)
    local g = h * 0.62
    ui.MinusGlyph(dl, x + (bw - g) / 2, y + (h - g) / 2, g, col(value > low and theme.gold or theme.goldDarker))
    ui.PlusGlyph(dl, x + bw + vw + (bw - g) / 2, y + (h - g) / 2, g, col(value < high and theme.gold or theme.goldDarker))
    label = opts.format and opts.format(value) or tostring(value)
    text.DrawCenter(dl, label, x + bw + vw / 2, y + (h - s) / 2 - 1, col(0xFFFFFF), s, true)
    return value, total, h, (minus or plus)
end

-- wrapped text. returns the height used.
function ui.Paragraph(dl, x, y, w, s, rgb, size, bold)
    size = size or Px(12)
    local lineH = text.H(size) + Px(5)
    local lift = (text.H(size) - size) / 2
    local lines = text.Wrap(s, size, bold, w)
    for i, line in ipairs(lines) do
        text.Draw(dl, line, x, y + (i - 1) * lineH + lift, col(rgb or theme.textDim), size, bold)
    end
    return #lines * lineH
end

-- a section title with a fading gold line after it
function ui.Section(dl, x, y, w, label)
    local s = Px(12.5)
    local h = text.H(s)
    text.Draw(dl, label, x, y + (h - s) / 2, col(theme.gold), s, true)
    local lw = text.Width(label, s, true)
    ui.FadeRight(dl, x + lw + Px(8), y + h / 2 + 1, x + w, theme.gold, 0.5)
    return h + Px(4)
end

---------------------------------------------------------------------------
-- tooltips, drawn last on the foreground list (as XIUI does)
---------------------------------------------------------------------------

local pendingTip = nil

-- a tooltip: a string, or a table of lines where each line is a string or
-- { text, rgb, bold } or { item = id, text, rgb } (a line with an icon)
function ui.Tip(content)
    pendingTip = content
end

function ui.FlushTip()
    local content = pendingTip
    pendingTip = nil
    if content == nil then
        return
    end
    if type(content) == 'string' then
        content = { content }
    end

    local s = Px(13)
    local gap = Px(5)
    local pad = Px(9)
    -- a row is as tall as the 13 pixel text, or its own text if that is
    -- taller, so the Text size setting grows the tooltip with its text. a
    -- row with an item icon leaves room for the icon at small text.
    local function RowH(row)
        local size = row.size or s
        local h = math.max(text.H(s), text.H(size))
        if row.item then
            h = math.max(h, Px(18) - gap)
        end
        return h
    end
    local w, h = 0, 0
    local rows = { }
    for i, line in ipairs(content) do
        local row = type(line) == 'table' and line or { line }
        local size = row.size or s
        local iconW = row.item and (Px(18) + Px(6)) or 0
        local lw = text.Width(row[1] or '', size, row[3]) + iconW
        if row.right ~= nil then
            lw = lw + Px(16) + text.Width(row.right, size, true)
        end
        if lw > w then
            w = lw
        end
        rows[i] = row
        h = h + (row.rule and Px(7) or (RowH(row) + gap))
    end
    w = w + pad * 2
    h = h + pad * 2 - gap

    local io = imgui.GetIO()
    local mx, my = imgui.GetMousePos()
    local x, y = mx + Px(16), my + Px(16)
    if x + w > io.DisplaySize.x then
        x = math.max(0, mx - w - Px(8))
    end
    if y + h > io.DisplaySize.y then
        y = math.max(0, my - h - Px(8))
    end

    local dl = imgui.GetForegroundDrawList()
    local frame = theme.Frame(ui.frame)
    ui.Rect(dl, x, y, x + w, y + h, col(frame.bg, 0.97), Px(4))
    ui.Outline(dl, x, y, x + w, y + h, col(theme.goldDarker), Px(4), 1)
    local ty = y + pad
    for _, row in ipairs(rows) do
        if row.rule then
            ui.FadeLine(dl, x + pad, ty + Px(2), x + w - pad, theme.gold, 0.45)
            ty = ty + Px(7)
        else
            local size = row.size or s
            local rowH = RowH(row)
            -- the row's text keeps its top at ty, whatever the text size
            local tyText = ty + (text.H(size) - size) / 2
            local tx = x + pad
            if row.item then
                -- the icon sits on the middle of its row
                ui.Slot(dl, tx, ty + (rowH - Px(18)) / 2, Px(18), row.item, theme.slotBorder)
                tx = tx + Px(24)
            end
            text.Draw(dl, row[1] or '', tx, tyText, col(row[2] or theme.textSoft), size, row[3])
            if row.right ~= nil then
                text.DrawRight(dl, row.right, x + w - pad, tyText, col(row.rightRgb or 0xFFFFFF), size, true)
            end
            ty = ty + rowH + gap
        end
    end
end

---------------------------------------------------------------------------
-- windows
---------------------------------------------------------------------------

local sizes = { }
local windowFlags = nil

-- begin a cool mode window. cfg has visible = { bool } and pos = { x, y }.
-- returns true when the window is open, then the draw list, x and y. always
-- call ui.EndWindow after, open or not.
function ui.BeginWindow(name, cfg)
    if windowFlags == nil then
        windowFlags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoBackground,
            ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoCollapse)
    end
    imgui.SetNextWindowPos(cfg.pos, ImGuiCond_FirstUseEver)
    guard.PushStyleVar(ImGuiStyleVar_WindowPadding, V(0, 0))
    guard.PushStyleVar(ImGuiStyleVar_ItemSpacing, V(0, 0))
    guard.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0)
    local open = guard.Begin(name, cfg.visible, windowFlags)
    if not open then
        return false
    end
    local dl = imgui.GetWindowDrawList()
    local x, y = imgui.GetWindowPos()
    cfg.pos[1], cfg.pos[2] = x, y
    -- the window size is only known after drawing, so the frame uses the
    -- size from the last frame, as XIUI's party list does
    local size = sizes[name]
    if size ~= nil then
        ui.WindowFrame(dl, x, y, size[1], size[2])
    end
    return true, dl, x, y
end

-- end a window whose content is w by h, from its top left corner
function ui.EndWindow(name, x, y, w, h)
    if x ~= nil then
        imgui.SetCursorScreenPos(V(x, y + math.max(1, h) - 1))
        imgui.Dummy(V(math.max(1, w), 1))
        sizes[name] = { w, h }
    end
    guard.End()
    guard.PopStyleVar(3)
end

-- a title bar: glyph, title and buttons on the right. buttons is a list of
-- { key, draw = glyph function, badge, tip, active }. returns the key of
-- the button clicked, or nil, and the height used.
function ui.TitleBar(dl, id, x, y, w, title, glyph, buttons)
    local h = Px(38)
    local gs = Px(18)
    glyph(dl, x + Px(14), y + (h - gs) / 2, gs, col(theme.gold))
    local s = Px(15)
    text.Draw(dl, title, x + Px(14) + gs + Px(8), y + (h - s) / 2 - 1, col(theme.gold), s, true)
    local clicked = nil
    local bs = Px(26)
    local bx = x + w - Px(10) - bs
    for i = #buttons, 1, -1 do
        local button = buttons[i]
        if ui.IconButton(dl, ('%s.%s'):format(id, button.key), bx, y + (h - bs) / 2, bs, button.draw, button) then
            clicked = button.key
        end
        bx = bx - bs - Px(6)
    end
    ui.FadeLine(dl, x + Px(10), y + h, x + w - Px(10), theme.gold, 0.6)
    return clicked, h
end

-- a scrolling body. its height follows the content, up to maxHeight.
-- returns the draw list, x, y and the inner width (less when the scrollbar
-- shows). call ui.EndBody after with the content height.
local bodies = { }
-- the scrolling body under a window's tabs. it fits its content up to
-- maxHeight, or takes fixedHeight when the player set the window's height.
function ui.BeginBody(id, w, maxHeight, fixedHeight)
    local last = bodies[id] or Px(200)
    local h = fixedHeight or math.max(Px(40), math.min(last, maxHeight))
    guard.PushStyleColor(ImGuiCol_ScrollbarBg, theme.rgba(theme.bgDark, 0.35))
    guard.PushStyleColor(ImGuiCol_ScrollbarGrab, theme.rgba(theme.goldDarker, 0.8))
    guard.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, theme.rgba(theme.goldDark, 0.9))
    guard.PushStyleColor(ImGuiCol_ScrollbarGrabActive, theme.rgba(theme.gold, 1))
    guard.PushStyleColor(ImGuiCol_ChildBg, { 0, 0, 0, 0 })
    guard.BeginChild(id, V(w, h), false, bit.bor(ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoBackground))
    local dl = imgui.GetWindowDrawList()
    local x, y = imgui.GetCursorScreenPos()
    local avail = imgui.GetContentRegionAvail()
    return dl, x, y, avail, h
end

function ui.EndBody(id, x, y, w, contentHeight)
    contentHeight = math.max(1, contentHeight)
    bodies[id] = contentHeight
    imgui.SetCursorScreenPos(V(x, y + contentHeight - 1))
    imgui.Dummy(V(math.max(1, w), 1))
    guard.EndChild()
    guard.PopStyleColor(5)
end

---------------------------------------------------------------------------
-- window sizes the player sets by dragging the bottom right corner
---------------------------------------------------------------------------

-- the strip under a window's body that holds the grip, in unscaled pixels
ui.footerH = 14

local grips = { }
-- whether the last press on each grip dragged it
local lastMoved = { }

local function Limit(v, low, high)
    v = tonumber(v)
    if v == nil or v ~= v then
        return nil
    end
    return math.max(low, math.min(high, v))
end

-- a window's width in screen pixels. win.width holds unscaled pixels, so
-- the Size setting still scales the window. limits: defaultW, minW, maxW,
-- minH, maxH, widthOnly
function ui.WindowWidth(win, limits)
    local v = Limit(win.width and win.width[1], limits.minW, limits.maxW) or limits.defaultW
    -- never wider than the screen, or than the room right of where the
    -- window sits (down to its smallest width), so the grip and the title
    -- bar buttons stay in reach
    local display = imgui.GetIO().DisplaySize
    local x = tonumber(win.pos and win.pos[1]) or 0
    if x ~= x then
        x = 0
    end
    local room = math.max(Px(limits.minW or 100), display.x - math.max(0, x) - 8)
    return math.max(Px(100), math.min(Px(v), display.x - 8, room))
end

-- the body height for a window the player made taller or shorter, or nil
-- when it fits its content. headerH is the space above the body.
function ui.FixedBodyHeight(win, limits, headerH)
    local v = Limit(win.height and win.height[1], 0, limits.maxH)
    if v == nil or v <= 0 then
        return nil
    end
    v = math.max(limits.minH, v)
    local total = math.min(Px(v), imgui.GetIO().DisplaySize.y - 8)
    return math.max(Px(60), total - headerH - Px(ui.footerH))
end

-- the grip in a window's bottom right corner. x, y, w, h is the window on
-- screen. dragging sets win.width, and win.height unless limits.widthOnly,
-- in unscaled pixels. a double-click goes back to the default width and a
-- height that fits the content. returns true when a drag or a reset ends,
-- so the caller can save. a click that doesn't move changes nothing.
function ui.ResizeGrip(dl, id, x, y, w, h, win, limits)
    local gw, gh = Px(22), Px(ui.footerH)
    imgui.SetCursorScreenPos(V(x + w - gw, y + h - gh))
    imgui.InvisibleButton('##hcrafter.grip.' .. id, V(gw, gh))
    local hovered = imgui.IsItemHovered()
    local active = imgui.IsItemActive()
    local drag = grips[id]
    local done = false
    -- a quick grab again right after a drag is a new drag, not a
    -- double-click
    if hovered and imgui.IsMouseDoubleClicked(0) and not lastMoved[id] then
        win.width[1] = limits.defaultW
        if not limits.widthOnly then
            win.height[1] = 0
        end
        -- the second press of the double-click doesn't start a drag
        grips[id] = { reset = true }
        done = true
    elseif active then
        local mx, my = imgui.GetMousePos()
        -- imgui reports -FLT_MAX while the mouse is unavailable
        local valid = type(mx) == 'number' and type(my) == 'number' and mx > -1e30 and my > -1e30
        if drag == nil and valid then
            drag = { mx = mx, my = my, w = w, h = h }
            grips[id] = drag
        end
        if drag ~= nil and valid and not drag.reset then
            -- each side changes only once the mouse has clearly moved that
            -- way, so a drag sideways that drifts a little keeps a window
            -- that fits its content fitting
            local dx, dy = math.abs(mx - drag.mx), math.abs(my - drag.my)
            if not drag.movedX and dx >= math.max(Px(8), dy / 2) then
                drag.movedX = true
            end
            if not drag.movedY and dy >= math.max(Px(8), dx / 2) then
                drag.movedY = true
            end
            drag.moved = drag.movedX or drag.movedY
            if drag.movedX then
                local nw = (drag.w + mx - drag.mx) / ui.S
                win.width[1] = math.floor(math.max(limits.minW, math.min(limits.maxW, nw)) + 0.5)
            end
            if drag.movedY and not limits.widthOnly then
                local nh = (drag.h + my - drag.my) / ui.S
                win.height[1] = math.floor(math.max(limits.minH, math.min(limits.maxH, nh)) + 0.5)
            end
        end
    elseif drag ~= nil then
        grips[id] = nil
        done = drag.moved == true
        lastMoved[id] = done
    end

    -- three short lines across the corner
    local c = col(theme.gold, (hovered or active) and 0.95 or 0.4)
    local cx, cy = x + w - Px(4), y + h - Px(4)
    for i = 1, 3 do
        local o = Px(3.5) * i
        ui.Line(dl, cx - o, cy, cx, cy - o, c, 1)
    end
    if hovered or active then
        pcall(imgui.SetMouseCursor, limits.widthOnly and ImGuiMouseCursor_ResizeEW or ImGuiMouseCursor_ResizeNWSE)
    end
    if hovered and not active then
        ui.Tip({
            { limits.widthOnly and 'Drag to change the width' or 'Drag to resize', theme.textSoft },
            { 'Double-click to reset', theme.textDim, size = Px(12) },
        })
    end
    return done
end

return ui
