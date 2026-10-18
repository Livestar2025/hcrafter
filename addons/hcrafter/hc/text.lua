-- text drawing for cool mode: Tahoma like the game menus, with a thin dark
-- outline. the font loading and outline method follow XIUI's libs/imtext.lua
-- (GPL-3.0): fonts are added once, from the addon's load event, because
-- adding a font in the middle of a frame can crash some Ashita builds. if
-- Tahoma can't load, imgui's own font is used at the same sizes.
local imgui = require('imgui')
local guard = require('hc.guard')

local text = {
    useGame = true,
    outline = 1,
    -- text at this size and up gets the full outline. smaller text on a
    -- dark panel gets a drop shadow (2 draw calls instead of 5, as XIUI's
    -- DrawShadow). set full = true while drawing over the game world.
    fullFrom = 15,
    full = false,
    fontDir = 'C:\\Windows\\Fonts\\',
    bakeSize = 20.0,
    -- the Text size setting. every string is measured and drawn this much
    -- bigger, around the same middle line, so rows keep their layout.
    scale = 1,
}

local fonts = { regular = nil, bold = nil }
local loaded = false
local widths = { }
local widthCount = 0
local fits = { }
local fitCount = 0
local pos = { 0, 0 }
local outlineCol = nil

-- call once, from the load event
function text.Load()
    if loaded then
        return
    end
    loaded = true
    for _, spec in ipairs({ { 'regular', 'tahoma.ttf' }, { 'bold', 'tahomabd.ttf' } }) do
        local ok, font = pcall(imgui.AddFontFromFileTTF, text.fontDir .. spec[2], text.bakeSize)
        if ok and font ~= nil then
            fonts[spec[1]] = font
        else
            fonts[spec[1]] = false
        end
    end
end

-- true when Tahoma loaded
function text.HasGameFont()
    return fonts.regular ~= nil and fonts.regular ~= false
end

local function FontFor(bold)
    if not text.useGame then
        return nil
    end
    if bold and fonts.bold then
        return fonts.bold
    end
    if fonts.regular then
        return fonts.regular
    end
    return nil
end

local function Measure(s, size, bold)
    local font = FontFor(bold)
    if font ~= nil then
        local pushed = pcall(guard.PushFont, font)
        if pushed then
            local lineHeight = imgui.GetTextLineHeight()
            local w = imgui.CalcTextSize(s)
            guard.PopFont()
            if lineHeight > 0 then
                return w * size / lineHeight
            end
        end
    end
    local lineHeight = imgui.GetTextLineHeight()
    local w = imgui.CalcTextSize(s)
    if lineHeight > 0 then
        return w * size / lineHeight
    end
    return w
end

-- push the game font for imgui's own widgets, such as the right-click
-- menu, at a pixel size before the Text size setting, so they match
-- HCrafter's text. returns true when it was pushed: call guard.PopFont()
-- after. with Tahoma off or missing, nothing is pushed and imgui's own font
-- stays.
function text.PushWidgetFont(size)
    local font = FontFor(false)
    if font == nil then
        return false
    end
    return (pcall(guard.PushFont, font, size * text.scale))
end

-- the height a string at this pixel size takes with the Text size setting
function text.H(size)
    return size * text.scale
end

-- the width of a string at a pixel size, with the Text size setting
function text.Width(s, size, bold)
    if s == nil or s == '' then
        return 0
    end
    size = size * text.scale
    local key = s .. (bold and '\1' or '\0') .. size .. (text.useGame and 'g' or 'd')
    local w = widths[key]
    if w == nil then
        if widthCount > 3000 then
            widths, widthCount = { }, 0
        end
        w = Measure(s, size, bold)
        widths[key] = w
        widthCount = widthCount + 1
    end
    return w
end

-- the string cut with "..." to fit a width. a cut string is kept, so the
-- same row drawn every frame doesn't measure its cuts again.
function text.Fit(s, size, bold, maxWidth)
    if s == nil or text.Width(s, size, bold) <= maxWidth then
        return s
    end
    local key = s .. (bold and '\1' or '\0') .. size .. (text.useGame and 'g' or 'd') .. '\2' .. maxWidth
    local cut = fits[key]
    if cut ~= nil then
        return cut
    end
    local low, high = 0, #s
    while low < high do
        local mid = math.floor((low + high + 1) / 2)
        if text.Width(s:sub(1, mid) .. '...', size, bold) <= maxWidth then
            low = mid
        else
            high = mid - 1
        end
    end
    cut = s:sub(1, low):gsub('%s+$', '') .. '...'
    if fitCount > 2000 then
        fits, fitCount = { }, 0
    end
    fits[key] = cut
    fitCount = fitCount + 1
    return cut
end

-- a sentence split into lines that fit a width, at word breaks
function text.Wrap(s, size, bold, maxWidth)
    local lines, line = { }, ''
    for word in s:gmatch('%S+') do
        local try = line == '' and word or (line .. ' ' .. word)
        if line == '' or text.Width(try, size, bold) <= maxWidth then
            line = try
        else
            table.insert(lines, line)
            line = word
        end
    end
    if line ~= '' then
        table.insert(lines, line)
    end
    return lines
end

-- draw a string with its top-left at x, y. col is an imgui color.
-- outline: false for none, true for the full outline, nil to pick by size.
-- with the Text size setting the string grows around its middle line, so
-- x, y stay the top-left of the string at its plain size.
function text.Draw(dl, s, x, y, col, size, bold, outline)
    if s == nil or s == '' then
        return
    end
    local font = FontFor(bold) or imgui.GetFont()
    local plain = size
    size = size * text.scale
    y = y - (size - plain) / 2
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if outline ~= false and text.outline > 0 then
        if outlineCol == nil then
            outlineCol = imgui.GetColorU32({ 0, 0, 0, 0.9 })
        end
        local o = text.outline
        if outline == true or text.full or size >= text.fullFrom then
            pos[1], pos[2] = x - o, y
            dl:AddText(font, size, pos, outlineCol, s)
            pos[1] = x + o
            dl:AddText(font, size, pos, outlineCol, s)
            pos[1], pos[2] = x, y - o
            dl:AddText(font, size, pos, outlineCol, s)
            pos[2] = y + o
            dl:AddText(font, size, pos, outlineCol, s)
        else
            pos[1], pos[2] = x + o, y + o
            dl:AddText(font, size, pos, outlineCol, s)
        end
    end
    pos[1], pos[2] = x, y
    dl:AddText(font, size, pos, col, s)
end

-- draw a string right-aligned to x
function text.DrawRight(dl, s, x, y, col, size, bold, outline)
    text.Draw(dl, s, x - text.Width(s, size, bold), y, col, size, bold, outline)
end

-- draw a string centered on x
function text.DrawCenter(dl, s, x, y, col, size, bold, outline)
    text.Draw(dl, s, x - text.Width(s, size, bold) / 2, y, col, size, bold, outline)
end

-- forget measured widths (after the font setting changes)
function text.Reset()
    widths, widthCount = { }, 0
    fits, fitCount = { }, 0
end

return text
