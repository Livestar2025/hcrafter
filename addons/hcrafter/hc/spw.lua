-- reads FFXI's own sound effects (SeWave .spw files) from the player's game
-- folder and turns them into 16-bit PCM. it reads PS-ADPCM (codec 0) and
-- PCM (codec 1). encrypted ATRAC3 (codec 3) is reported and left alone.
-- no game audio ships with HCrafter. part of HCrafter, GPL-3.0.
--
-- the header layout and the PS-ADPCM rules follow vgmstream's SPW reader
-- (src/meta/bgw.c) and configurable PS-ADPCM decoder
-- (src/coding/psx_decoder.c), https://github.com/vgmstream/vgmstream, and the
-- output matches vgmstream sample for sample. vgmstream's notice:
--
--   Copyright (c) 2008-2025 Adam Gashlin, Fastelbja, Ronny Elfert, bnnm,
--   Christopher Snowhill, NicknineTheEagle, bxaimc, Thealexbarney, CyberBotX,
--   EdnessP, et al
--
--   Permission to use, copy, modify, and distribute this software for any
--   purpose with or without fee is hereby granted, provided that the above
--   copyright notice and this permission notice appear in all copies.
--
--   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
--   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
--   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
--   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
--   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
--   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
--   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
local bit = require('bit')
local wave = require('hc.wave')

local spw = {
    -- the longest sound HCrafter converts, in samples per channel (10 s)
    maxSamples = 48000 * 10,
}

local COEFS = { { 0, 0 }, { 60, 0 }, { 115, -52 }, { 98, -55 }, { 122, -60 } }

local function U8(s, at)
    return s:byte(at + 1) or 0
end

local function U32(s, at)
    local a, b, c, d = s:byte(at + 1, at + 4)
    return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216
end

local function S32(s, at)
    local v = U32(s, at)
    if v >= 2147483648 then
        v = v - 4294967296
    end
    return v
end

-- the 48-byte header of a SeWave file, or nil and why
function spw.Header(data)
    if type(data) ~= 'string' or #data < 0x30 or data:sub(1, 8) ~= 'SeWave\0\0' then
        return nil, 'not a SeWave file'
    end
    local h = {
        fileSize = U32(data, 0x08),
        codec = U32(data, 0x0C),
        blockSize = U32(data, 0x14),
        loopStart = S32(data, 0x18),
        -- stored as two halves that add up
        rate = (U32(data, 0x1C) + U32(data, 0x20)) % 2147483648,
        start = U32(data, 0x24),
        channels = U8(data, 0x2A),
        blockAlign = U8(data, 0x2C),
    }
    if h.codec == 0 then
        h.samples = h.blockSize * h.blockAlign
    elseif h.codec == 1 then
        h.samples = h.blockSize
    else
        h.samples = 0
    end
    h.loops = h.loopStart > 0
    if h.codec ~= 0 and h.codec ~= 1 then
        return nil, h.codec == 3 and 'ATRAC3, which HCrafter can\'t read' or 'an unknown codec', h
    end
    if h.channels < 1 or h.channels > 2 or h.rate < 8000 or h.rate > 96000 or h.start >= h.fileSize
        or h.fileSize ~= #data or (h.codec == 0 and (h.blockAlign < 2 or h.blockAlign % 2 ~= 0)) then
        return nil, 'a damaged file', h
    end
    if h.samples > spw.maxSamples then
        return nil, 'longer than 10 seconds', h
    end
    return h
end

-- decodes a whole file into { rate, channels, samples, [1] = { ... }, [2] = { ... } }
-- with the whole-number samples of each channel numbered from 1, or nil and
-- why
function spw.Decode(data)
    local h, why = spw.Header(data)
    if h == nil then
        return nil, why
    end
    local out = { rate = h.rate, channels = h.channels, samples = h.samples, loops = h.loops }
    local n, nch = h.samples, h.channels
    for c = 1, nch do
        out[c] = wave.NewSamples(n)
    end
    if h.codec == 1 then
        for s = 0, n - 1 do
            for c = 1, nch do
                local at = h.start + (s * nch + c - 1) * 2
                local lo, hi = data:byte(at + 1, at + 2)
                local v = (lo or 0) + (hi or 0) * 256
                if v >= 32768 then
                    v = v - 65536
                end
                out[c][s + 1] = v
            end
        end
        return out
    end
    -- PS-ADPCM in frames of blockAlign / 2 + 1 bytes: one byte of filter and
    -- shift, then blockAlign 4-bit samples, low nibble first. the channels
    -- take turns frame by frame.
    local per = h.blockAlign
    local frame = per / 2 + 1
    local rshift, band, lshift, arshift = bit.rshift, bit.band, bit.lshift, bit.arshift
    for c = 1, nch do
        local dst = out[c]
        local h1, h2 = 0, 0
        local f = 0
        while f * per < n do
            local off = h.start + (f * nch + c - 1) * frame
            local head = data:byte(off + 1) or 0
            local coef, shift = rshift(head, 4), band(head, 0x0F)
            if coef > 4 then
                coef = 0
            end
            if shift > 12 then
                shift = 9
            end
            local c0, c1 = COEFS[coef + 1][1], COEFS[coef + 1][2]
            local down = 16 + shift
            local base = f * per
            local count = math.min(per, n - base)
            -- two samples a byte, low nibble first. each nibble is moved to
            -- the top of 32 bits, so the shift down sign-extends it.
            local i = 0
            while i < count do
                local byte = data:byte(off + 2 + rshift(i, 1)) or 0
                local smp = arshift(lshift(byte, 28), down) + arshift(c0 * h1 + c1 * h2, 6)
                if smp > 32767 then
                    smp = 32767
                elseif smp < -32768 then
                    smp = -32768
                end
                dst[base + i + 1] = smp
                h2, h1 = h1, smp
                if i + 1 < count then
                    smp = arshift(lshift(band(byte, 0xF0), 24), down) + arshift(c0 * h1 + c1 * h2, 6)
                    if smp > 32767 then
                        smp = 32767
                    elseif smp < -32768 then
                        smp = -32768
                    end
                    dst[base + i + 2] = smp
                    h2, h1 = h1, smp
                end
                i = i + 2
            end
            f = f + 1
        end
    end
    return out
end

return spw
