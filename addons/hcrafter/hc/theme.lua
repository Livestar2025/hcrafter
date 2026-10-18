-- colors and sizes for cool mode. the palette follows XIUI's gold-on-dark
-- look (XIUI by the XIUI authors, GPL-3.0), so HCrafter sits well next to
-- it. colors are 0xRRGGBB numbers here and become imgui colors on use.
local imgui = require('imgui')

local theme = {
    gold = 0xF4DA97,
    goldDark = 0xC3AE79,
    goldDarker = 0x92835B,
    goldBright = 0xE9C466,
    bgDark = 0x0D0D0D,
    bgMedium = 0x191713,
    bgLight = 0x23201B,
    bgLighter = 0x2D2923,
    text = 0xFFFFFF,
    textSoft = 0xE0DACF,
    textMuted = 0xCFC8BA,
    textDim = 0xADA79B,
    border = 0x4D463C,
    slotBorder = 0xB89959,
    green = 0x94DB80,
    amber = 0xF0A93A,
    red = 0xF07B6B,
    blue = 0x78C4EE,
    black = 0x000000,
    -- bar track and end caps
    trackTop = 0x01122B,
    trackBottom = 0x061C39,
    capEdge = 0x1A2A4A,
    capMid = 0x2D4A7C,
    -- bar fills: { left, right }
    fills = {
        exp = { 0xC39040, 0xE9C466 },
        tp = { 0x3898CE, 0x78C4EE },
        mp = { 0x9ABB5A, 0xBFE07D },
        hp = { 0xE26C6C, 0xFB9494 },
    },
    -- window frames: 1 navy, 2 charcoal
    frames = {
        [1] = { name = 'Navy', bg = 0x181C3E, edge = 0xC8D0EC, corner = 0xEEF1FB },
        [2] = { name = 'Charcoal', bg = 0x14120F, edge = 0x8C8475, corner = 0xE0DACF },
    },
    -- one color per craft, used by the drawn emblems when the game's own
    -- imagery icons are off or can't load
    crafts = {
        [1] = 0xB98A4E, -- Woodworking
        [2] = 0x9AA3AE, -- Smithing
        [3] = 0xE3C25B, -- Goldsmithing
        [4] = 0xD58BB0, -- Clothcraft
        [5] = 0xA0663B, -- Leathercraft
        [6] = 0xE6DDC4, -- Bonecraft
        [7] = 0x7CC7A4, -- Alchemy
        [8] = 0xE88A5A, -- Cooking
    },
}

local cache = { }
local cached = 0

-- an imgui color for 0xRRGGBB and an alpha from 0 to 1
function theme.col(rgb, alpha)
    alpha = math.max(0, math.min(1, alpha or 1))
    local key = rgb * 1000 + math.floor(alpha * 999 + 0.5)
    local value = cache[key]
    if value == nil then
        -- fades make many alphas, so the cache starts over now and then
        if cached > 4000 then
            cache, cached = { }, 0
        end
        local r = math.floor(rgb / 65536) % 256
        local g = math.floor(rgb / 256) % 256
        local b = rgb % 256
        value = imgui.GetColorU32({ r / 255, g / 255, b / 255, alpha })
        cache[key] = value
        cached = cached + 1
    end
    return value
end

-- { r, g, b, a } for imgui style colors
function theme.rgba(rgb, alpha)
    local r = math.floor(rgb / 65536) % 256
    local g = math.floor(rgb / 256) % 256
    local b = rgb % 256
    return { r / 255, g / 255, b / 255, alpha or 1 }
end

-- a color between two 0xRRGGBB colors
function theme.mix(a, b, t)
    t = math.max(0, math.min(1, t))
    local function part(shift)
        local pa = math.floor(a / shift) % 256
        local pb = math.floor(b / shift) % 256
        return math.floor(pa + (pb - pa) * t + 0.5)
    end
    return part(65536) * 65536 + part(256) * 256 + part(1)
end

function theme.Frame(index)
    return theme.frames[index] or theme.frames[1]
end

return theme
