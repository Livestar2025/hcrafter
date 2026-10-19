-- reads .wav files and writes 16-bit PCM ones, so HCrafter can play FFXI's
-- own sounds and play any sound at the volume set in Settings. part of
-- HCrafter, GPL-3.0.
local wave = {
    -- the longest sound HCrafter rescales: 10 seconds at 48 kHz, in samples
    -- per channel
    maxSamples = 48000 * 10,
}

-- LuaJIT's FFI, when there is one and the machine is little-endian like a
-- .wav file: samples then live in plain arrays and a file is written in one
-- go, which is much faster and leaves little for the garbage collector
local ffi = nil
do
    local ok, lib = pcall(require, 'ffi')
    -- a short test, so a stand-in FFI or a big-endian one is never used
    ok = ok and type(lib) == 'table' and pcall(function()
        local probe = lib.new('int16_t[?]', 2)
        probe[0], probe[1] = 1, -2
        assert(lib.string(probe, 4) == '\1\0\254\255')
    end)
    if ok then
        ffi = lib
    end
end

-- room for n samples, numbered from 1 like a Lua table
function wave.NewSamples(n)
    if ffi ~= nil then
        return ffi.new('int16_t[?]', n + 1)
    end
    return { }
end

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

-- one sample as a whole number from -32768 to 32767, from bytes at a
-- position: 8-bit (unsigned), 16, 24 or 32-bit PCM, or 32-bit float
local readers = {
    [8] = function(s, at)
        return ((s:byte(at + 1) or 128) - 128) * 256
    end,
    [16] = function(s, at)
        local v = U16(s, at)
        if v >= 32768 then
            v = v - 65536
        end
        return v
    end,
    -- the top two bytes of 24 and 32-bit samples
    [24] = function(s, at)
        local v = U16(s, at + 1)
        if v >= 32768 then
            v = v - 65536
        end
        return v
    end,
    [32] = function(s, at)
        local v = U16(s, at + 2)
        if v >= 32768 then
            v = v - 65536
        end
        return v
    end,
    float = function(s, at)
        local b1, b2, b3, b4 = s:byte(at + 1, at + 4)
        b1, b2, b3, b4 = b1 or 0, b2 or 0, b3 or 0, b4 or 0
        local exp = (b4 % 128) * 2 + math.floor(b3 / 128)
        if exp == 0 or exp == 255 then
            -- too small to hear, or not a number
            return 0
        end
        local value = math.ldexp(1 + ((b3 % 128) * 65536 + b2 * 256 + b1) / 8388608, exp - 127)
        if b4 >= 128 then
            value = -value
        end
        return Clamp16(math.floor(value * 32767 + 0.5))
    end,
}

-- a PCM or float .wav file as { rate, channels, samples, [1] = { ... }, ... }
-- with 16-bit samples, or nil and why. it reads 8, 16, 24 and 32-bit PCM
-- and 32-bit float, mono or stereo, from 8 to 192 kHz, up to 480,000
-- samples a channel (10 seconds at 48 kHz).
function wave.Read(data)
    if type(data) ~= 'string' or #data < 44 or data:sub(1, 4) ~= 'RIFF' or data:sub(9, 12) ~= 'WAVE' then
        return nil, 'not a .wav file'
    end
    local fmt, at, size = nil, nil, nil
    local p = 12
    while p + 8 <= #data do
        local id, len = data:sub(p + 1, p + 4), U32(data, p + 4)
        if id == 'fmt ' and len >= 16 then
            fmt = { tag = U16(data, p + 8), channels = U16(data, p + 10), rate = U32(data, p + 12), align = U16(data, p + 20), bits = U16(data, p + 22) }
            -- WAVE_FORMAT_EXTENSIBLE: the real format is the first two bytes
            -- of the sub-format
            if fmt.tag == 0xFFFE and len >= 40 then
                fmt.tag = U16(data, p + 8 + 24)
            end
        elseif id == 'data' then
            at, size = p + 8, math.min(len, #data - p - 8)
            break
        end
        p = p + 8 + len + (len % 2)
    end
    if fmt == nil or at == nil then
        return nil, 'a damaged .wav file'
    end
    local read
    if fmt.tag == 1 then
        read = readers[fmt.bits]
    elseif fmt.tag == 3 and fmt.bits == 32 then
        read = readers.float
    end
    local nch = fmt.channels
    local width = math.floor(fmt.bits / 8)
    if read == nil or nch < 1 or nch > 2 or fmt.rate < 8000 or fmt.rate > 192000 or fmt.align ~= width * nch then
        return nil, 'not a PCM or float .wav file'
    end
    local n = math.floor(size / fmt.align)
    if n > wave.maxSamples then
        return nil, 'longer than 10 seconds at 48 kHz'
    end
    local out = { rate = fmt.rate, channels = nch, samples = n }
    for c = 1, nch do
        out[c] = wave.NewSamples(n)
    end
    for c = 1, nch do
        local dst = out[c]
        local pos = at + (c - 1) * width
        for s = 1, n do
            dst[s] = read(data, pos)
            pos = pos + fmt.align
        end
    end
    return out
end

local function U16le(v)
    return string.char(v % 256, math.floor(v / 256) % 256)
end

local function U32le(v)
    return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

-- a 16-bit PCM .wav file from a sound table, each sample scaled by gain
-- (1 keeps it as it is) and kept in range: its 44-byte header and its
-- samples, as two strings, so a writer needn't join them
function wave.Parts(sound, gain)
    gain = tonumber(gain) or 1
    if gain ~= gain then
        gain = 1
    end
    local nch, n = sound.channels, sound.samples
    local bytes = n * nch * 2
    local head = table.concat({
        'RIFF', U32le(36 + bytes), 'WAVE',
        'fmt ', U32le(16), U16le(1), U16le(nch), U32le(sound.rate), U32le(sound.rate * nch * 2), U16le(nch * 2), U16le(16),
        'data', U32le(bytes),
    })
    if ffi ~= nil then
        local buffer = ffi.new('int16_t[?]', math.max(1, n * nch))
        local k = 0
        for s = 1, n do
            for c = 1, nch do
                local v = sound[c][s] or 0
                if gain ~= 1 then
                    v = Clamp16(math.floor(v * gain + 0.5))
                end
                buffer[k] = v
                k = k + 1
            end
        end
        return head, ffi.string(buffer, bytes)
    end
    local parts = { }
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
    return head, table.concat(parts)
end

-- the same file as one string
function wave.Write(sound, gain)
    local head, body = wave.Parts(sound, gain)
    return head .. body
end

-- true when a file starts like a .wav file HCrafter wrote and is as long
-- as its header says: a copy cut short by a crash or a full disk fails
function wave.Whole(path)
    local file = io.open(path, 'rb')
    if file == nil then
        return false
    end
    local head = file:read(12)
    local size = file:seek('end')
    file:close()
    if type(head) ~= 'string' or #head < 12 or head:sub(1, 4) ~= 'RIFF' or head:sub(9, 12) ~= 'WAVE' then
        return false
    end
    return type(size) == 'number' and size >= 44 and U32(head, 4) + 8 == size
end

return wave
