-- reads and writes 16-bit PCM .wav files, so HCrafter can play FFXI's own
-- sounds and play any sound at the volume set in Settings. part of HCrafter,
-- GPL-3.0.
local wave = {
    -- the longest sound HCrafter rescales, in samples per channel (10 s at 48 kHz)
    maxSamples = 48000 * 10,
}

local function U16(s, at)
    local a, b = s:byte(at + 1, at + 2)
    return (a or 0) + (b or 0) * 256
end

local function U32(s, at)
    local a, b, c, d = s:byte(at + 1, at + 4)
    return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216
end

local function Clamp16(x)
    if x > 32767 then
        return 32767
    elseif x < -32768 then
        return -32768
    end
    return x
end

-- a 16-bit PCM .wav file as { rate, channels, samples, [1] = { ... }, ... },
-- or nil and why. other formats are left alone.
function wave.Read(data)
    if type(data) ~= 'string' or #data < 44 or data:sub(1, 4) ~= 'RIFF' or data:sub(9, 12) ~= 'WAVE' then
        return nil, 'not a .wav file'
    end
    local fmt, at, size = nil, nil, nil
    local p = 12
    while p + 8 <= #data do
        local id, len = data:sub(p + 1, p + 4), U32(data, p + 4)
        if id == 'fmt ' and len >= 16 then
            fmt = { tag = U16(data, p + 8), channels = U16(data, p + 10), rate = U32(data, p + 12), bits = U16(data, p + 22) }
        elseif id == 'data' then
            at, size = p + 8, math.min(len, #data - p - 8)
            break
        end
        p = p + 8 + len + (len % 2)
    end
    if fmt == nil or at == nil then
        return nil, 'a damaged .wav file'
    end
    if fmt.tag ~= 1 or fmt.bits ~= 16 or fmt.channels < 1 or fmt.channels > 2 or fmt.rate < 8000 or fmt.rate > 96000 then
        return nil, 'not 16-bit PCM'
    end
    local nch = fmt.channels
    local n = math.floor(size / (2 * nch))
    if n > wave.maxSamples then
        return nil, 'longer than 10 seconds'
    end
    local out = { rate = fmt.rate, channels = nch, samples = n }
    for c = 1, nch do
        out[c] = { }
    end
    for s = 0, n - 1 do
        for c = 1, nch do
            local v = U16(data, at + (s * nch + c - 1) * 2)
            if v >= 32768 then
                v = v - 65536
            end
            out[c][s + 1] = v
        end
    end
    return out
end

-- a 16-bit PCM .wav file from a sound table, each sample scaled by gain
-- (1 keeps it as it is) and kept in range
function wave.Write(sound, gain)
    gain = tonumber(gain) or 1
    if gain ~= gain then
        gain = 1
    end
    local nch, n = sound.channels, sound.samples
    local bytes = n * nch * 2
    local function U16le(v) return string.char(v % 256, math.floor(v / 256) % 256) end
    local function U32le(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
    local parts = {
        'RIFF', U32le(36 + bytes), 'WAVE',
        'fmt ', U32le(16), U16le(1), U16le(nch), U32le(sound.rate), U32le(sound.rate * nch * 2), U16le(nch * 2), U16le(16),
        'data', U32le(bytes),
    }
    local chunk, count = { }, 0
    for s = 1, n do
        for c = 1, nch do
            local v = sound[c][s] or 0
            if gain ~= 1 then
                v = Clamp16(math.floor(v * gain + 0.5))
            end
            if v < 0 then
                v = v + 65536
            end
            count = count + 1
            chunk[count] = string.char(v % 256, math.floor(v / 256))
            if count == 4096 then
                parts[#parts + 1] = table.concat(chunk)
                chunk, count = { }, 0
            end
        end
    end
    if count > 0 then
        parts[#parts + 1] = table.concat(chunk, '', 1, count)
    end
    return table.concat(parts)
end

return wave
