-- HCrafter test harness: runs the addon under LuaJIT with stubbed Ashita,
-- imgui (draw lists, invisible buttons, children, popups), settings,
-- events, files, memory, packets, textures and sounds.
--
-- usage: luajit tests/harness.lua <addon folder> [item names csv] [cycle]
--   item names csv: optional "id,name" lines. without it the harness uses
--   tests/item_names.csv, a few public item names the checks need.
--   cycle: run the loop-guard checks on synthetic looping recipe data instead.
--
-- every check prints PASS or FAIL. the run ends with ALL OK or FAILURES: n.
local ADDON, NAMES, MODE = arg[1], arg[2], arg[3]
if NAMES == 'cycle' or NAMES == 'preview' then
    NAMES, MODE = nil, NAMES
end
-- preview <folder> comes after the names file when there is one
local PREVIEW_DIR = nil
if MODE == 'preview' then
    PREVIEW_DIR = arg[2] == 'preview' and arg[3] or arg[4]
    assert(PREVIEW_DIR ~= nil, 'usage: luajit tests/harness.lua <addon folder> [names file] preview <output folder>')
end
if NAMES == nil then
    NAMES = (arg[0]:match('^(.*[/\\])') or './') .. 'item_names.csv'
end
package.path = ADDON .. '/?.lua;' .. package.path
local bit = require('bit')
local realClock = os.clock

local failures = 0
local function check(cond, msg)
    print((cond and '  PASS  ' or '  FAIL  ') .. msg)
    if not cond then
        failures = failures + 1
    end
end

---------------------------------------------------------------------------
-- a fresh temp folder that stands in for the Ashita install. only this
-- folder is ever deleted, never the folder HCRAFTER_TMP points at.
---------------------------------------------------------------------------
local function quote(path)
    return "'" .. path:gsub("'", "'\\''") .. "'"
end
local base = os.getenv('HCRAFTER_TMP')
if base == nil or base == '' then
    base = os.tmpname()
    os.remove(base)
    base = base:match('^(.*)/[^/]*$') or '/tmp'
end
-- the address of a fresh table differs between two runs started in the
-- same second, so each run gets its own folder
math.randomseed(os.time() + (tonumber(tostring({ }):match('0x(%x+)') or '0', 16) or 0) % 1000003)
local TMP = ('%s/hcrafter_test_%d_%d'):format(base, os.time(), math.random(100000, 999999))
assert(TMP:find('hcrafter_test_', 1, true), 'unexpected temp path')
os.execute('mkdir -p ' .. quote(TMP))
local function cleanup()
    os.execute('rm -rf ' .. quote(TMP))
end
local function fixPath(path)
    return (path:gsub('\\', '/'))
end
local realOpen, realLoadfile = io.open, loadfile
io.open = function(path, mode)
    return realOpen(fixPath(path), mode)
end
loadfile = function(path)
    return realLoadfile(fixPath(path))
end

---------------------------------------------------------------------------
-- imgui constants (the ones Ashita's libs/imgui.lua defines that HCrafter
-- uses) and the T helper
---------------------------------------------------------------------------
local constants = {
    ImDrawFlags_RoundCornersTopLeft = 16, ImDrawFlags_RoundCornersTopRight = 32,
    ImDrawFlags_RoundCornersBottomLeft = 64, ImDrawFlags_RoundCornersBottomRight = 128,
    ImDrawFlags_RoundCornersNone = 256,
    ImGuiCol_Text = 0, ImGuiCol_TextDisabled = 1, ImGuiCol_ChildBg = 3, ImGuiCol_PopupBg = 4,
    ImGuiCol_Border = 5, ImGuiCol_FrameBg = 7, ImGuiCol_FrameBgHovered = 8, ImGuiCol_FrameBgActive = 9,
    ImGuiCol_ScrollbarBg = 14, ImGuiCol_ScrollbarGrab = 15, ImGuiCol_ScrollbarGrabHovered = 16,
    ImGuiCol_ScrollbarGrabActive = 17, ImGuiCol_Button = 21, ImGuiCol_ButtonHovered = 22,
    ImGuiCol_ButtonActive = 23, ImGuiCol_HeaderHovered = 25, ImGuiCol_HeaderActive = 26,
    ImGuiCond_FirstUseEver = 4,
    ImGuiMouseCursor_ResizeEW = 4, ImGuiMouseCursor_ResizeNWSE = 6,
    ImGuiStyleVar_WindowPadding = 2, ImGuiStyleVar_WindowBorderSize = 4, ImGuiStyleVar_FramePadding = 11,
    ImGuiStyleVar_ItemSpacing = 14,
    ImGuiWindowFlags_NoTitleBar = 1, ImGuiWindowFlags_NoMove = 4, ImGuiWindowFlags_NoScrollbar = 8,
    ImGuiWindowFlags_NoCollapse = 32, ImGuiWindowFlags_AlwaysAutoResize = 64, ImGuiWindowFlags_NoBackground = 128,
    ImGuiWindowFlags_NoFocusOnAppearing = 4096,
}
for k, v in pairs(constants) do
    _G[k] = v
end
ImDrawFlags_RoundCornersTop = bit.bor(16, 32)
ImDrawFlags_RoundCornersLeft = bit.bor(16, 64)
ImDrawFlags_RoundCornersRight = bit.bor(32, 128)

local Tmt = { __index = {
    append = function(self, v) self[#self + 1] = v; return self end,
    join = function(self, sep) return table.concat(self, sep or '') end,
} }
T = function(t) return setmetatable(t or { }, Tmt) end

-- Ashita's string:args() from common.lua, enough for commands
string.args = function(self)
    local out = T{ }
    for word in self:gmatch('%S+') do
        out[#out + 1] = word
    end
    return out
end

---------------------------------------------------------------------------
-- item data, status icons, key items
---------------------------------------------------------------------------
local names = { }
for line in io.lines(NAMES) do
    line = line:gsub('\r$', '')
    local id, name = line:match('^(%d+),(.*)$')
    if id then
        names[tonumber(id)] = (name:gsub('^"(.*)"$', '%1'))
    end
end
local stackOverride = { [12987] = 1, [14392] = 1, [15819] = 1 }  -- gear does not stack
local nilItems = { }
local noBitmap = { [1273] = true }    -- an item whose icon can't load: drawn fallback
local res = { }
function res:GetItemById(id)
    assert(type(id) == 'number', 'GetItemById needs a number')
    if nilItems[id] then
        return nil
    end
    local n = names[id] or ('Item' .. id)
    return {
        Name = { [0] = n, [1] = n },
        LogNameSingular = { [0] = n:lower(), [1] = n:lower() },
        StackSize = stackOverride[id] or 12,
        Bitmap = noBitmap[id] and nil or ('bmp' .. id),
        ImageSize = noBitmap[id] and 0 or 2048,
    }
end
function res:GetStatusIconByIndex(id)
    assert(type(id) == 'number')
    return { Index = id, Id = id, Bitmap = 'status' .. id, ImageSize = 1024 }
end
function res:GetString(tbl, id)
    assert(tbl == 'keyitems.names')
    return 'key item ' .. id
end

---------------------------------------------------------------------------
-- game memory: bags, equipment, buffs, party, player, entity status
---------------------------------------------------------------------------
local G = {
    partyName = 'Alpha',
    entityName = 'Alpha',
    serverId = 4242,
    loginStatus = 2,
    bags = { },
    keyItems = { },
    entity = true,
    equip = { },      -- equipment slot (0-15) -> item id
    buffs = { },      -- list of status ids
    status = 0,
}
local function SetBags(spec)
    -- spec: { [containerId] = { [itemId] = count, max = n } }
    G.bags = { }
    for containerId, contents in pairs(spec) do
        local bag = { max = contents.max or 80, slots = { } }
        local slot = 1
        for itemId, count in pairs(contents) do
            if itemId ~= 'max' then
                bag.slots[slot] = { Id = itemId, Count = count }
                slot = slot + 1
            end
        end
        G.bags[containerId] = bag
    end
end
-- equipped items sit in wardrobe 4 (container 12) at slots past 100, where
-- the bag counter (slots 0 to max) never looks
local EQUIP_CONTAINER = 12
local inventory = {
    GetContainerCountMax = function(self, c)
        local bag = G.bags[c]
        return bag and bag.max or 0
    end,
    GetContainerItem = function(self, c, slot)
        if c == EQUIP_CONTAINER and slot > 100 then
            local id = G.equip[slot - 101]
            return { Id = id or 0, Count = id and 1 or 0 }
        end
        local bag = G.bags[c]
        if bag == nil then return { Id = 0, Count = 0 } end
        if slot == 0 and c == 0 then return { Id = 65535, Count = 123456 } end  -- gil
        return bag.slots[slot] or { Id = 0, Count = 0 }
    end,
    GetEquippedItem = function(self, slot)
        assert(type(slot) == 'number' and slot >= 0 and slot <= 15, 'equipment slot out of range')
        if G.equip[slot] == nil then
            return { Slot = slot, Index = 0 }
        end
        return { Slot = slot, Index = EQUIP_CONTAINER * 256 + 101 + slot }
    end,
}
local party = {
    GetMemberName = function(self, i) return G.partyName end,
    GetMemberTargetIndex = function(self, i) return 1 end,
}
local player = {
    HasKeyItem = function(self, id) return G.keyItems[id] == true end,
    GetLoginStatus = function(self) return G.loginStatus end,
    GetBuffs = function(self)
        local out = { }
        for i = 0, 31 do out[i] = 255 end
        for i, id in ipairs(G.buffs) do out[i - 1] = id end
        return out
    end,
}
local entityMgr = {
    GetStatus = function(self, index) assert(index == 1) return G.status end,
}
local memory = {
    GetInventory = function(self) return inventory end,
    GetParty = function(self) return party end,
    GetPlayer = function(self) return player end,
    GetEntity = function(self) return entityMgr end,
}
AshitaCore = {
    GetResourceManager = function(self) return res end,
    GetMemoryManager = function(self) return memory end,
    GetInstallPath = function(self) return TMP end,
}
GetPlayerEntity = function()
    if not G.entity then return nil end
    return { ServerId = G.serverId, Name = G.entityName }
end

---------------------------------------------------------------------------
-- ashita: events, fs, memory, sounds
---------------------------------------------------------------------------
local handlers = { }
local listDirectory = true
local sounds = { }
ashita = {
    events = {
        register = function(event, name, fn)
            handlers[event] = handlers[event] or { }
            table.insert(handlers[event], fn)
        end,
    },
    fs = {
        exists = function(path)
            local f = realOpen(fixPath(path), 'r')
            if f then f:close() return true end
            return false
        end,
        create_dir = function(path)
            os.execute('mkdir -p ' .. quote(fixPath(path)))
            return true
        end,
        get_directory = function(path)
            if not listDirectory then return nil end
            local out = { }
            local pipe = io.popen('ls -1 ' .. quote(fixPath(path)) .. ' 2>/dev/null')
            for line in pipe:lines() do out[#out + 1] = line end
            pipe:close()
            return out
        end,
    },
    memory = {
        find = function() return 0 end,
        read_uint32 = function() return 0 end,
        read_uint8 = function() return 0 end,
        read_string = function() return nil end,
    },
    misc = {
        play_sound = function(path)
            assert(type(path) == 'string')
            sounds[#sounds + 1] = path
        end,
    },
}
local function fire(event, e)
    for _, fn in ipairs(handlers[event] or { }) do
        fn(e)
    end
end

-- struct.unpack for the formats HCrafter's parsers use (little endian).
-- reading past the end of the data is an error, as in Roberto
-- Ierusalimschy's struct library ("data string too short"), so an overread
-- fails the run.
struct = {
    unpack = function(fmt, s, pos)
        local chars = fmt:match('^c(%d+)$')
        local size = chars and tonumber(chars)
            or ({ B = 1, b = 1, i1 = 1, H = 2, i2 = 2, i4 = 4, I4 = 4, I = 4, L = 4 })[fmt]
        assert(size, 'struct.unpack format not stubbed: ' .. fmt)
        assert(type(s) == 'string', 'struct.unpack needs a string')
        pos = pos or 1
        if pos < 1 or pos - 1 + size > #s then
            error(('data string too short: %s at %i of %i bytes'):format(fmt, pos, #s), 2)
        end
        if chars then
            return s:sub(pos, pos + size - 1)
        end
        local value = 0
        for i = size - 1, 0, -1 do
            value = value * 256 + s:byte(pos + i)
        end
        if fmt == 'b' or fmt == 'i1' or fmt == 'i2' or fmt == 'i4' then
            local limit = 2 ^ (size * 8 - 1)
            if value >= limit then value = value - 2 * limit end
        end
        return value
    end,
}
local function packet(size, fields, text)
    local bytes = { }
    for i = 1, size do bytes[i] = 0 end
    for offset, spec in pairs(fields) do
        local value, width = spec[1], spec[2]
        if value < 0 then value = value + 2 ^ (width * 8) end
        for i = 0, width - 1 do
            bytes[offset + 1 + i] = value % 256
            value = math.floor(value / 256)
        end
    end
    for offset, str in pairs(text or { }) do
        for i = 1, #str do bytes[offset + i] = str:byte(i) end
    end
    local chars = { }
    for i = 1, size do chars[i] = string.char(bytes[i]) end
    return table.concat(chars)
end
local function zoneIn(name, serverId)
    return { id = 0x00A, data = packet(0x100, { [0x04] = { serverId, 4 } }, { [0x84] = name }) }
end
local function zoneOut(logout)
    return { id = 0x00B, data = packet(0x20, { [0x04] = { logout and 1 or 2, 1 } }) }
end
local inventoryFinish = { id = 0x01D, data = packet(0x10, { }) }

---------------------------------------------------------------------------
-- settings library stub. like Ashita's, keys missing from the saved file
-- come straight from the defaults table, by reference.
---------------------------------------------------------------------------
local settingsStub = { saves = 0, callbacks = { }, current = nil }
package.preload['settings'] = function()
    return {
        load = function(defaults)
            settingsStub.defaults = defaults
            local current = T{ }
            for key, value in pairs(defaults) do
                current[key] = value
            end
            settingsStub.current = current
            return current
        end,
        save = function() settingsStub.saves = settingsStub.saves + 1 end,
        register = function(alias, name, fn) table.insert(settingsStub.callbacks, fn) end,
    }
end
package.preload['common'] = function() return true end

---------------------------------------------------------------------------
-- texture stubs: d3d8 and ffi as equipmon and XIUI use them
---------------------------------------------------------------------------
local textures = { made = 0, failNext = false, byPtr = { } }
package.loaded['d3d8'] = {
    get_device = function() return { device = true } end,
    gc_safe_release = function(tex) return tex end,
}
local fakeC = setmetatable({
    D3DFMT_A8R8G8B8 = 21, D3DPOOL_MANAGED = 1, D3DX_DEFAULT = -1, S_OK = 0,
    D3DXCreateTextureFromFileInMemoryEx = function(dev, bitmap, size, w, h, mips, usage, fmt, pool, filter, mipFilter, key, info, palette, out)
        assert(dev ~= nil and type(bitmap) == 'string' and type(size) == 'number' and size > 0, 'bad texture call')
        assert(type(out) == 'table', 'texture out pointer missing')
        if textures.failNext then
            textures.failNext = false
            return 1
        end
        textures.made = textures.made + 1
        out[0] = { ptr = 1000 + textures.made, bitmap = bitmap }
        textures.byPtr[1000 + textures.made] = bitmap
        return 0
    end,
}, { __index = function(_, k) error('ffi.C.' .. tostring(k) .. ' is not stubbed', 2) end })
package.loaded['ffi'] = {
    C = fakeC,
    new = function(ctype) assert(ctype == 'IDirect3DTexture8*[1]', 'unexpected ffi.new: ' .. tostring(ctype)) return { } end,
    cast = function(ctype, value)
        if ctype == 'uint32_t' then
            return value.ptr
        end
        assert(ctype == 'IDirect3DTexture8*', 'unexpected ffi.cast: ' .. tostring(ctype))
        return value
    end,
}

---------------------------------------------------------------------------
-- imgui stub: windows, children and popups with their own id scopes, a
-- cursor, draw lists that check every coordinate, style and font stacks,
-- and scripted clicks, right-clicks, hovers and typing
---------------------------------------------------------------------------
local S = {
    colors = 0, vars = 0, fonts = 0, scopes = { }, popups = 0,
    cursor = { 0, 0 }, frame = nil,
    click = { }, rightClick = nil, hover = nil, hoverAll = false, select = nil,
    typed = { }, buttons = { }, openPopups = { },
    fontFail = false, display = { x = 1920, y = 1080 },
    percentText = { },
    -- a scripted drag: active names the item held down, doubleClick is the
    -- frame of a double-click, cursorShape the last mouse cursor asked for
    active = nil, doubleClick = false, cursorShape = nil,
}
local function scopeName()
    local top = S.scopes[#S.scopes]
    return top and top.name or ''
end
local function finite(v)
    return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge
end
local function vec(v, where)
    if type(v) ~= 'table' or not finite(v[1]) or not finite(v[2]) then
        error(('%s: bad position %s, %s'):format(where, tostring(v and v[1]), tostring(v and v[2])), 3)
    end
end
local function colorArg(c, where)
    if type(c) ~= 'number' or not finite(c) then
        error(where .. ': bad color ' .. tostring(c), 3)
    end
end
local function noPercent(s, where)
    local shown = s:match('^(.-)##') or s
    if shown:find('%', 1, true) then
        S.percentText[#S.percentText + 1] = where .. ': ' .. s
    end
end

local drawLists = { }
local function DrawList(name)
    local list = drawLists[name]
    if list ~= nil then
        return list
    end
    list = { name = name }
    local function prim(op, ...)
        S.frame.prims = S.frame.prims + 1
        if S.record then
            local scope = S.scopes[#S.scopes]
            S.frame.recorded[#S.frame.recorded + 1] = { list = name, op = op, args = { ... },
                clip = scope and scope.clip or nil, order = #S.frame.recorded }
        end
    end
    function list:AddText(a, b, c, d, e)
        local pos, col, s, size
        if type(c) == 'string' then
            pos, col, s = a, b, c
        else
            assert(type(a) == 'table', 'AddText: the font comes first')
            assert(type(b) == 'number' and finite(b) and b > 0, 'AddText: bad font size')
            pos, col, s, size = c, d, e, b
        end
        vec(pos, 'AddText')
        colorArg(col, 'AddText')
        assert(type(s) == 'string', 'AddText needs a string')
        -- text must stay inside the scrolling body it is drawn in (the stub
        -- measures 0.5 x size per character, as CalcTextSize does here)
        local scope = S.scopes[#S.scopes]
        if scope ~= nil and scope.clip ~= nil and name ~= 'foreground' then
            local width = 0.5 * (size or 14) * #s
            if pos[1] < scope.clip[1] - 2 or pos[1] + width > scope.clip[3] + 2 then
                S.frame.overflow[#S.frame.overflow + 1] = ('%s (x %.0f to %.0f, body %.0f to %.0f)'):format(s, pos[1], pos[1] + width, scope.clip[1], scope.clip[3])
            end
        end
        local bold = type(a) == 'table' and type(a.font) == 'string' and a.font:find('tahomabd', 1, true) ~= nil
        prim('text', pos[1], pos[2], col, s, size or 14, bold)
        local f = S.frame
        local key = self.name .. '\0' .. s
        if not f.textSeen[key] then
            f.textSeen[key] = true
            f.texts[#f.texts + 1] = { text = s, list = self.name, x = pos[1], y = pos[2], size = size }
        end
    end
    function list:AddRectFilled(p1, p2, col, rounding, flags)
        vec(p1, 'AddRectFilled'); vec(p2, 'AddRectFilled'); colorArg(col, 'AddRectFilled')
        assert(rounding == nil or finite(rounding), 'AddRectFilled rounding')
        prim('rectfill', p1[1], p1[2], p2[1], p2[2], col, rounding or 0, flags or 0)
    end
    function list:AddRect(p1, p2, col, rounding, flags, thickness)
        vec(p1, 'AddRect'); vec(p2, 'AddRect'); colorArg(col, 'AddRect')
        assert(thickness == nil or finite(thickness), 'AddRect thickness')
        prim('rect', p1[1], p1[2], p2[1], p2[2], col, rounding or 0, flags or 0, thickness or 1)
    end
    function list:AddLine(p1, p2, col, thickness)
        vec(p1, 'AddLine'); vec(p2, 'AddLine'); colorArg(col, 'AddLine')
        prim('line', p1[1], p1[2], p2[1], p2[2], col, thickness or 1)
    end
    function list:AddCircle(c, r, col, segments, thickness)
        vec(c, 'AddCircle'); assert(finite(r), 'AddCircle radius'); colorArg(col, 'AddCircle')
        prim('circle', c[1], c[2], r, col, thickness or 1)
    end
    function list:AddCircleFilled(c, r, col, segments)
        vec(c, 'AddCircleFilled'); assert(finite(r), 'AddCircleFilled radius'); colorArg(col, 'AddCircleFilled')
        prim('circlefill', c[1], c[2], r, col)
    end
    function list:AddTriangleFilled(a, b, c, col)
        vec(a, 'AddTriangleFilled'); vec(b, 'AddTriangleFilled'); vec(c, 'AddTriangleFilled'); colorArg(col, 'AddTriangleFilled')
        prim('tri', a[1], a[2], b[1], b[2], c[1], c[2], col)
    end
    function list:AddRectFilledMultiColor(p1, p2, c1, c2, c3, c4)
        vec(p1, 'AddRectFilledMultiColor'); vec(p2, 'AddRectFilledMultiColor')
        colorArg(c1, 'multi'); colorArg(c2, 'multi'); colorArg(c3, 'multi'); colorArg(c4, 'multi')
        prim('multi', p1[1], p1[2], p2[1], p2[2], c1, c2, c3, c4)
    end
    function list:AddImage(tex, p1, p2, uv1, uv2, col)
        assert(type(tex) == 'number', 'AddImage needs a texture number')
        vec(p1, 'AddImage'); vec(p2, 'AddImage')
        if col ~= nil then colorArg(col, 'AddImage') end
        S.frame.images = S.frame.images + 1
        prim('image', p1[1], p1[2], p2[1], p2[2], tex, col or 4294967295)
    end
    drawLists[name] = list
    return list
end

local lastItem = nil
local function newItem(label, kind)
    local scope = S.scopes[#S.scopes]
    assert(scope ~= nil, kind .. ' outside a window')
    local id = scope.name .. '/' .. label
    if scope.ids[label] then
        S.frame.dupes[#S.frame.dupes + 1] = id
    end
    scope.ids[label] = true
    lastItem = id
    S.frame.items = S.frame.items + 1
    if S.frame.keep then
        S.frame.labels[#S.frame.labels + 1] = id
    end
    return id
end
local function takeClick(id)
    for i, pattern in ipairs(S.click) do
        if id:find(pattern, 1, true) then
            table.remove(S.click, i)
            S.frame.clicked[#S.frame.clicked + 1] = id
            return true
        end
    end
    return false
end
local function pushScope(name, width, kind)
    table.insert(S.scopes, { name = name, ids = { }, width = width or 600, kind = kind })
end
local function popScope(kind)
    local top = table.remove(S.scopes)
    assert(top ~= nil and top.kind == kind, ('%s closed while %s was open'):format(kind, top and top.kind or 'nothing'))
end

local im = { }
function im.GetColorU32(c)
    assert(type(c) == 'table' and #c == 4, 'GetColorU32 needs { r, g, b, a }')
    for i = 1, 4 do
        assert(finite(c[i]) and c[i] >= -1e-9 and c[i] <= 1 + 1e-9, 'GetColorU32 channel out of range: ' .. tostring(c[i]))
    end
    return math.floor(c[1] * 255) + math.floor(c[2] * 255) * 256 + math.floor(c[3] * 255) * 65536 + math.floor(c[4] * 255) * 16777216
end
-- Ashita's font is 18 pixels, Ashita 4.3's default, unless a test sets
-- S.lineH. text is 0.5 x the line height per character, about what
-- Ashita's fixed-width Agave font is.
function im.CalcTextSize(s) assert(type(s) == 'string') local h = S.lineH or 18 return h / 2 * #s, h end
function im.GetTextLineHeight() return S.lineH or 18 end
function im.GetFrameHeight() return (S.lineH or 18) + 6 end
-- imgui 1.92's style, which Ashita 4.3 has: FontSizeBase is what tells it
-- apart from older Ashita
function im.GetStyle() return { FontSizeBase = 18, FramePadding = { x = 4, y = 3 }, ItemInnerSpacing = { x = 4, y = 4 } } end
function im.GetFont() return { default = true } end
function im.AddFontFromFileTTF(path, size)
    assert(type(path) == 'string' and type(size) == 'number')
    assert(S.frame == nil, 'AddFontFromFileTTF called during a frame')
    if S.fontFail then error('font not found') end
    return { font = path }
end
function im.PushFont(font, size)
    assert(type(font) == 'table')
    assert(size == nil or (finite(size) and size >= 0), 'PushFont size')
    S.fonts = S.fonts + 1
    S.lastFontSize = size
end
function im.PopFont() S.fonts = S.fonts - 1; assert(S.fonts >= 0, 'PopFont underflow') end
function im.SetWindowFontScale(scale) assert(finite(scale) and scale > 0, 'SetWindowFontScale'); S.windowFontScale = scale end
function im.GetIO() return { DisplaySize = S.display } end
function im.GetMousePos()
    if S.mouse ~= nil then return S.mouse[1], S.mouse[2] end
    return 500, 400
end
function im.PushStyleColor(c, v)
    assert(type(c) == 'number' and type(v) == 'table' and #v == 4, 'PushStyleColor args')
    S.colors = S.colors + 1
end
function im.PopStyleColor(n) S.colors = S.colors - (n or 1); assert(S.colors >= 0, 'PopStyleColor underflow') end
function im.PushStyleVar(v, val)
    assert(type(v) == 'number')
    assert(type(val) == 'number' or (type(val) == 'table' and finite(val[1]) and finite(val[2])), 'PushStyleVar value')
    S.vars = S.vars + 1
end
function im.PopStyleVar(n) S.vars = S.vars - (n or 1); assert(S.vars >= 0, 'PopStyleVar underflow') end
function im.SetNextWindowPos(pos, cond) vec(pos, 'SetNextWindowPos'); S.nextPos = { pos[1], pos[2] } end
function im.Begin(name, visible, flags)
    assert(type(name) == 'string' and type(visible) == 'table' and type(flags) == 'number', 'Begin args')
    assert(#S.scopes == 0, 'Begin inside another window')
    pushScope(name, 600, 'window')
    local pos = S.nextPos or { 100, 100 }
    S.nextPos = nil
    S.scopes[#S.scopes].pos = pos
    S.frame.windows[#S.frame.windows + 1] = name
    S.cursor = { pos[1], pos[2] }
    return true
end
function im.End() popScope('window') end
function im.GetWindowPos()
    for i = #S.scopes, 1, -1 do
        if S.scopes[i].kind == 'window' then return S.scopes[i].pos[1], S.scopes[i].pos[2] end
    end
    return 100, 100
end
function im.GetWindowDrawList()
    return DrawList(scopeName())
end
function im.GetForegroundDrawList() return DrawList('foreground') end
function im.SetCursorScreenPos(v) vec(v, 'SetCursorScreenPos'); S.cursor = { v[1], v[2] } end
function im.GetCursorScreenPos() return S.cursor[1], S.cursor[2] end
function im.GetContentRegionAvail()
    local top = S.scopes[#S.scopes]
    return top and top.width or 600, 400
end
function im.Dummy(size)
    vec(size, 'Dummy')
    S.cursor[2] = S.cursor[2] + size[2]
end
function im.InvisibleButton(label, size)
    assert(type(label) == 'string', 'InvisibleButton label')
    vec(size, 'InvisibleButton')
    assert(size[1] > 0 and size[2] > 0, 'InvisibleButton with zero size: ' .. label)
    local id = newItem(label, 'InvisibleButton')
    S.frame.rects[id] = { S.cursor[1], S.cursor[2], size[1], size[2] }
    S.cursor[2] = S.cursor[2] + size[2]
    return takeClick(id)
end
function im.IsItemHovered()
    local id = lastItem or ''
    -- a scripted right-click means the mouse is over that item too
    return S.hoverAll or (S.hover ~= nil and id:find(S.hover, 1, true) ~= nil)
        or (S.rightClick ~= nil and id:find(S.rightClick, 1, true) ~= nil)
end
function im.IsItemClicked(button)
    local id = lastItem or ''
    if button == 1 and S.rightClick ~= nil and id:find(S.rightClick, 1, true) then
        S.rightClick = nil
        return true
    end
    return false
end
function im.IsItemActive()
    local id = lastItem or ''
    return S.active ~= nil and id:find(S.active, 1, true) ~= nil
end
function im.IsMouseDoubleClicked(button)
    assert(button == 0, 'IsMouseDoubleClicked: only the left button is used')
    return S.doubleClick == true
end
function im.SetMouseCursor(c)
    assert(type(c) == 'number' and c >= -1 and c <= 10, 'SetMouseCursor needs an ImGuiMouseCursor value')
    S.cursorShape = c
end
function im.BeginChild(id, size, border, flags)
    assert(type(id) == 'string' and type(border) == 'boolean' and type(flags) == 'number', 'BeginChild args')
    vec(size, 'BeginChild')
    assert(size[2] > 0 and size[1] > 0, 'BeginChild size')
    pushScope(scopeName() .. '>' .. id, size[1], 'child')
    S.scopes[#S.scopes].clip = { S.cursor[1], S.cursor[2], S.cursor[1] + size[1], S.cursor[2] + size[2] }
    return true
end
function im.EndChild() popScope('child') end
function im.OpenPopup(id)
    assert(type(id) == 'string')
    S.openPopups[scopeName() .. '#' .. id] = true
end
function im.BeginPopup(id)
    local key = scopeName() .. '#' .. id
    if not S.openPopups[key] then
        return false
    end
    pushScope(key, 300, 'popup')
    S.popups = S.popups + 1
    S.frame.popupShown[#S.frame.popupShown + 1] = key
    return true
end
function im.EndPopup() popScope('popup'); S.popups = S.popups - 1 end
function im.CloseCurrentPopup()
    local top = S.scopes[#S.scopes]
    assert(top and top.kind == 'popup', 'CloseCurrentPopup outside a popup')
    S.openPopups[top.name] = nil
end
local function recordText(kind, s)
    assert(type(s) == 'string', kind .. ' needs a string')
    noPercent(s, kind)
    S.frame.widgetTexts[#S.frame.widgetTexts + 1] = s
end
function im.Text(s) recordText('Text', s) end
function im.TextDisabled(s) recordText('TextDisabled', s) end
function im.SameLine() end
function im.SetNextItemWidth(w) assert(finite(w) and w > 0, 'SetNextItemWidth'); S.nextWidth = w end
function im.Selectable(label)
    assert(S.popups > 0, 'Selectable outside a popup')
    recordText('Selectable', label)
    newItem(label, 'Selectable')
    if S.select ~= nil and label:find(S.select, 1, true) then
        S.select = nil
        -- a selectable closes its popup when clicked
        S.openPopups[S.scopes[#S.scopes].name] = nil
        return true
    end
    return false
end
function im.Button(label)
    recordText('Button', label)
    local id = newItem(label, 'Button')
    for i, pattern in ipairs(S.buttons) do
        if id:find(pattern, 1, true) then
            table.remove(S.buttons, i)
            return true
        end
    end
    return false
end
local function typedFor(label)
    for pattern, value in pairs(S.typed) do
        if label:find(pattern, 1, true) then
            S.typed[pattern] = nil
            return true, value
        end
    end
    return false
end
local function recordInput(value)
    if S.record and S.frame ~= nil then
        S.frame.inputs[#S.frame.inputs + 1] = { x = S.cursor[1], y = S.cursor[2], w = S.nextWidth or 100, text = value,
            list = scopeName(), order = #S.frame.recorded }
    end
    S.nextWidth = nil
end
function im.InputText(label, buf, size)
    assert(type(buf) == 'table' and type(buf[1]) == 'string' and type(size) == 'number', 'InputText args')
    recordText('InputText', label)
    newItem(label, 'InputText')
    recordInput(buf[1])
    local hit, value = typedFor(label)
    if hit then buf[1] = value; return true end
    return false
end
function im.InputInt(label, ref)
    assert(type(ref) == 'table' and type(ref[1]) == 'number', 'InputInt args')
    recordText('InputInt', label)
    newItem(label, 'InputInt')
    recordInput(tostring(ref[1]))
    local hit, value = typedFor(label)
    if hit then ref[1] = value; return true end
    return false
end
function im.InputFloat(label, ref, step, fast, fmt)
    assert(type(ref) == 'table' and type(ref[1]) == 'number', 'InputFloat args')
    recordText('InputFloat', label)
    newItem(label, 'InputFloat')
    recordInput(('%.1f'):format(ref[1]))
    local hit, value = typedFor(label)
    if hit then ref[1] = value; return true end
    return false
end
setmetatable(im, { __index = function(_, k) error('imgui.' .. tostring(k) .. ' is not stubbed', 2) end })
package.preload['imgui'] = function() return im end

-- capture print output
local printed = { }
local realPrint = print
print = function(...)
    local parts = { }
    for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
    local line = table.concat(parts, ' ')
    if line:find('[hcrafter]', 1, true) == 1 then
        printed[#printed + 1] = line
    else
        realPrint(line)
    end
end

-- a clock the tests control
local clockNow = 1000
local timeNow = 1792200000
os.clock = function() return clockNow end
os.time = function() return timeNow end
local function advance(seconds) clockNow = clockNow + seconds; timeNow = timeNow + math.floor(seconds) end

-- cycle mode swaps in recipe data that loops 9001 <- 9002 <- 9001
if MODE == 'cycle' then
    package.preload['data.recipesBySkill'] = function()
        return {
            [0] = { },
            [1] = {
                { result = 9001, count = 1, id = 1, crystal = 4098, keyItem = 0, ingredients = { 9002, 9003, }, skills = { 5, 0, 0, 0, 0, 0, 0, 0, }, },
                { result = 9002, count = 2, id = 2, crystal = 4098, keyItem = 0, ingredients = { 9001, }, skills = { 6, 0, 0, 0, 0, 0, 0, 0, }, },
            },
            [2] = { }, [3] = { }, [4] = { }, [5] = { }, [6] = { }, [7] = { }, [8] = { },
        }
    end
end

-- addon globals Ashita provides
addon = { path = TMP .. '\\addons\\hcrafter' }
-- the sounds go where a real install has them, so HCrafter can see they
-- are there
os.execute('mkdir -p ' .. quote(TMP .. '/addons/hcrafter') .. ' && cp -r ' .. quote(ADDON .. '/sounds') .. ' ' .. quote(TMP .. '/addons/hcrafter/'))

-- from here on, a read or write of an undefined global is an error
setmetatable(_G, {
    __index = function(_, k) error('undefined global read: ' .. tostring(k), 2) end,
    __newindex = function(_, k) error('unexpected global write: ' .. tostring(k), 2) end,
})

---------------------------------------------------------------------------
-- load the addon
---------------------------------------------------------------------------
local ALPHA_BAGS = {
    [0] = { [4098] = 12, [719] = 2 },        -- inventory: 12 wind crystals, 2 ebony lumber
    [5] = { [719] = 6 },                     -- satchel: 6 ebony lumber
    [1] = { [4099] = 5 },                    -- mog safe: 5 earth crystals
}
SetBags(ALPHA_BAGS)

local chunk = assert(loadfile(ADDON .. '/hcrafter.lua'))
local okLoad, errLoad = pcall(chunk)
check(okLoad, 'hcrafter.lua loads' .. (okLoad and '' or (': ' .. tostring(errLoad))))
if not okLoad then cleanup() os.exit(1) end
check(addon.name == 'hcrafter' and addon.version == '1.3.0', 'addon metadata set: hcrafter 1.3.0')

local config = settingsStub.current
local defaults = settingsStub.defaults
local recipes = require('hc.recipes')
local planner = require('hc.planner')
local hq = require('hc.hq')
local stock = require('hc.stock')
local history = require('hc.history')
local session = require('hc.session')
local prices = require('hc.prices')
local skillup = require('hc.skillup')
local gear = require('hc.gear')
local watch = require('hc.synthwatch')
local fanfare = require('hc.fanfare')
local icons = require('hc.icons')
local text = require('hc.text')
local app = require('hc.app')
local book = require('hc.book')
local files = require('hc.files')
local guard = require('hc.guard')

local function beginFrame(keep)
    S.frame = {
        keep = keep, prims = 0, images = 0, items = 0, texts = { }, textSeen = { }, widgetTexts = { },
        windows = { }, dupes = { }, labels = { }, clicked = { }, popupShown = { },
        rects = { }, recorded = { }, inputs = { }, overflow = { },
    }
    for name in pairs(drawLists) do drawLists[name] = nil end
end
local function endFrame()
    local why = nil
    if #S.scopes ~= 0 then why = 'scopes left open: ' .. S.scopes[#S.scopes].name
    elseif S.colors ~= 0 then why = 'style colors ' .. S.colors
    elseif S.vars ~= 0 then why = 'style vars ' .. S.vars
    elseif S.fonts ~= 0 then why = 'fonts ' .. S.fonts
    elseif S.popups ~= 0 then why = 'popups ' .. S.popups
    elseif #S.frame.dupes > 0 then why = 'duplicate ids, e.g. ' .. S.frame.dupes[1] end
    return S.frame, why
end
local function frame(keep)
    beginFrame(keep)
    local ok, err = pcall(fire, 'd3d_present')
    if not ok then
        S.scopes = { }
        S.colors, S.vars, S.fonts, S.popups = 0, 0, 0, 0
    end
    local f, why = endFrame()
    if not ok then why = 'd3d_present error: ' .. tostring(err) end
    S.frame = nil
    return f, why
end
-- every distinct string drawn in a list (a window name, 'foreground')
local function drawn(f, listPattern)
    local out = { }
    for _, t in ipairs(f.texts) do
        if listPattern == nil or t.list:find(listPattern, 1, true) then
            out[#out + 1] = t.text
        end
    end
    return out
end
local function hasText(f, s, listPattern)
    for _, t in ipairs(drawn(f, listPattern)) do
        if t == s then return true end
    end
    return false
end
local function hasTextLike(f, pattern, listPattern)
    for _, t in ipairs(drawn(f, listPattern)) do
        if t:find(pattern, 1, true) then return t end
    end
    return nil
end
local function hasLabel(f, pattern)
    for _, id in ipairs(f.labels) do
        if id:find(pattern, 1, true) then return id end
    end
    return nil
end
local function charFile(name)
    return TMP .. '/config/addons/hcrafter/characters/char_' .. name .. '.lua'
end
local function readFile(path)
    local f = realOpen(path, 'r')
    if f == nil then return nil end
    local data = f:read('*a')
    f:close()
    return data
end
local function writeFile(path, data)
    os.execute('mkdir -p ' .. quote(path:match('^(.*)/[^/]*$')))
    local f = assert(realOpen(path, 'w'))
    f:write(data)
    f:close()
end
local BOOK = 'HCrafter###hcrafter.book'
local PLAN = 'Resource Planner###hcrafter.planner'
local TRACK = 'Shopping list###hcrafter.tracker'

---------------------------------------------------------------------------
if MODE == 'cycle' then
    print('== loop guard on synthetic looping data')
    fire('load')
    local st = book.State()
    st.filter[1] = 'item9001'
    st.open = setmetatable({ }, { __index = function() return true end })
    st.expanded = setmetatable({ }, { __index = function() return true end })
    S.hoverAll = true
    local f, why = frame(true)
    check(why == nil, 'all-open frame on looping data is balanced' .. (why and (': ' .. why) or ''))
    check(hasLabel(f, '>9002>9001') ~= nil and hasLabel(f, '>9002>9001>9002') == nil, 'the looping material shows once as a plain row, never inside itself')
    local entries = { { recipe = recipes.byId[1], synths = 3 } }
    local result = planner.Build(entries, function(id) local o = recipes.Options(id); return o and o[1] end,
        function() return 0 end, recipes.Grouped, 0)
    check(result.loops[9001] == true, 'planner flags the loop item')
    local boughtLoop = false
    for _, row in ipairs(result.buy) do if row.id == 9001 then boughtLoop = true end end
    check(boughtLoop, 'the loop item is bought instead of made')
    nilItems[9003] = true
    f, why = frame(true)
    check(why == nil, 'an item id the game does not know draws without errors')
    S.hoverAll = false
    print(failures == 0 and 'ALL OK' or ('FAILURES: ' .. failures))
    cleanup()
    os.exit(failures == 0 and 0 or 1)
end

---------------------------------------------------------------------------
-- preview: draw a few scenes and write each frame's draw calls as SVG, so
-- the layout can be looked at without the game. icons are stand-ins and
-- text uses the stub's widths, so this is close to the game, not the same.
---------------------------------------------------------------------------
if MODE == 'preview' then
    assert(PREVIEW_DIR, 'usage: luajit tests/harness.lua <addon> preview <output folder>')
    os.execute('mkdir -p ' .. quote(PREVIEW_DIR))
    local theme = require('hc.theme')

    local function decode(n)
        local r = n % 256
        local g = math.floor(n / 256) % 256
        local b = math.floor(n / 65536) % 256
        local a = math.floor(n / 16777216) % 256
        return ('rgb(%d,%d,%d)'):format(r, g, b), a / 255
    end
    local function esc(str)
        return (str:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'))
    end
    local function roundedPath(x1, y1, x2, y2, r, flags)
        if flags == 0 then flags = 16 + 32 + 64 + 128 end
        if bit.band(flags, 256) ~= 0 then r = 0 end
        r = math.min(r, (x2 - x1) / 2, (y2 - y1) / 2)
        local tl = bit.band(flags, 16) ~= 0 and r or 0
        local tr = bit.band(flags, 32) ~= 0 and r or 0
        local bl = bit.band(flags, 64) ~= 0 and r or 0
        local br = bit.band(flags, 128) ~= 0 and r or 0
        return ('M%.2f,%.2f H%.2f A%.2f,%.2f 0 0 1 %.2f,%.2f V%.2f A%.2f,%.2f 0 0 1 %.2f,%.2f H%.2f A%.2f,%.2f 0 0 1 %.2f,%.2f V%.2f A%.2f,%.2f 0 0 1 %.2f,%.2f Z'):format(
            x1 + tl, y1, x2 - tr, tr, tr, x2, y1 + tr, y2 - br, br, br, x2 - br, y2, x1 + bl, bl, bl, x1, y2 - bl, y1 + tl, tl, tl, x1 + tl, y1)
    end

    local function svg(f, path, width, height)
        local out = { ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'):format(width, height, width, height) }
        out[#out + 1] = '<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3E5C80"/><stop offset="0.5" stop-color="#7C8F9A"/><stop offset="0.75" stop-color="#5F7A62"/><stop offset="1" stop-color="#22332A"/></linearGradient>'
        out[#out + 1] = '<linearGradient id="icon" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#8A6A3A"/><stop offset="0.5" stop-color="#D8B878"/><stop offset="1" stop-color="#5A4426"/></linearGradient></defs>'
        out[#out + 1] = ('<rect width="%d" height="%d" fill="url(#sky)"/>'):format(width, height)
        out[#out + 1] = ('<path d="M0 %d C 300 %d, 600 %d, 900 %d S 1500 %d, %d %d L %d %d L 0 %d Z" fill="#4F6A5E" opacity="0.8"/>'):format(
            height * 0.62, height * 0.56, height * 0.66, height * 0.6, height * 0.58, width, height * 0.63, width, height, height)
        local clips, clipCount = { }, 0
        local gradients = 0
        local list = { }
        for _, p in ipairs(f.recorded) do
            list[#list + 1] = p
        end
        for _, input in ipairs(f.inputs) do
            list[#list + 1] = { list = input.list, op = 'input', args = { input.x, input.y, input.w, input.text }, order = input.order + 0.5 }
        end
        table.sort(list, function(a, b)
            local af, bf = a.list == 'foreground', b.list == 'foreground'
            if af ~= bf then return bf end
            return a.order < b.order
        end)
        for _, p in ipairs(list) do
            local a = p.args
            local clipAttr = ''
            if p.clip ~= nil then
                local key = table.concat(p.clip, ',')
                if clips[key] == nil then
                    clipCount = clipCount + 1
                    clips[key] = 'c' .. clipCount
                    out[#out + 1] = ('<clipPath id="c%d"><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f"/></clipPath>'):format(
                        clipCount, p.clip[1], p.clip[2], p.clip[3] - p.clip[1], p.clip[4] - p.clip[2])
                end
                clipAttr = (' clip-path="url(#%s)"'):format(clips[key])
            end
            if p.op == 'rectfill' then
                local c, o = decode(a[5])
                out[#out + 1] = ('<path d="%s" fill="%s" fill-opacity="%.3f"%s/>'):format(roundedPath(a[1], a[2], a[3], a[4], a[6], a[7]), c, o, clipAttr)
            elseif p.op == 'rect' then
                local c, o = decode(a[5])
                local t = a[8]
                out[#out + 1] = ('<path d="%s" fill="none" stroke="%s" stroke-opacity="%.3f" stroke-width="%.2f"%s/>'):format(
                    roundedPath(a[1] + 0.5, a[2] + 0.5, a[3] - 0.5, a[4] - 0.5, a[6], a[7]), c, o, t, clipAttr)
            elseif p.op == 'line' then
                local c, o = decode(a[5])
                out[#out + 1] = ('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-opacity="%.3f" stroke-width="%.2f" stroke-linecap="round"%s/>'):format(
                    a[1], a[2], a[3], a[4], c, o, a[6], clipAttr)
            elseif p.op == 'circle' then
                local c, o = decode(a[4])
                out[#out + 1] = ('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="none" stroke="%s" stroke-opacity="%.3f" stroke-width="%.2f"%s/>'):format(a[1], a[2], a[3], c, o, a[5], clipAttr)
            elseif p.op == 'circlefill' then
                local c, o = decode(a[4])
                out[#out + 1] = ('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s" fill-opacity="%.3f"%s/>'):format(a[1], a[2], a[3], c, o, clipAttr)
            elseif p.op == 'tri' then
                local c, o = decode(a[7])
                out[#out + 1] = ('<polygon points="%.2f,%.2f %.2f,%.2f %.2f,%.2f" fill="%s" fill-opacity="%.3f"%s/>'):format(a[1], a[2], a[3], a[4], a[5], a[6], c, o, clipAttr)
            elseif p.op == 'multi' then
                gradients = gradients + 1
                local c1, o1 = decode(a[5])
                local c2, o2 = decode(a[6])
                local c3, o3 = decode(a[7])
                local vertical = a[5] == a[6]
                local x2, y2 = vertical and 0 or 1, vertical and 1 or 0
                local endC, endO = c2, o2
                if vertical then endC, endO = c3, o3 end
                out[#out + 1] = ('<linearGradient id="g%d" x1="0" y1="0" x2="%d" y2="%d"><stop offset="0" stop-color="%s" stop-opacity="%.3f"/><stop offset="1" stop-color="%s" stop-opacity="%.3f"/></linearGradient>'):format(
                    gradients, x2, y2, c1, o1, endC, endO)
                out[#out + 1] = ('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="url(#g%d)"%s/>'):format(a[1], a[2], a[3] - a[1], a[4] - a[2], gradients, clipAttr)
            elseif p.op == 'image' then
                local bitmap = textures.byPtr[a[5]] or ''
                local w, h = a[3] - a[1], a[4] - a[2]
                local _, tint = decode(a[6])
                local statusId = tonumber(bitmap:match('^status(%d+)$') or '')
                if statusId ~= nil then
                    local craftId = statusId - 235
                    local rgb = theme.crafts[craftId] or 0xC3AE79
                    local hex = ('#%06X'):format(rgb)
                    out[#out + 1] = ('<g opacity="%.2f"%s><rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" fill="#1B1A22" stroke="%s" stroke-width="1.5"/>'):format(
                        tint, clipAttr, a[1] + 1, a[2] + 1, w - 2, h - 2, w * 0.22, hex)
                    out[#out + 1] = ('<text x="%.2f" y="%.2f" font-family="DejaVu Sans" font-weight="bold" font-size="%.1f" fill="%s" text-anchor="middle">%s</text></g>'):format(
                        a[1] + w / 2, a[2] + h * 0.62, h * 0.3, hex, recipes.skillAbbr[craftId] or '?')
                else
                    local itemId = tonumber(bitmap:match('^bmp(%d+)$') or '') or 0
                    local name = (names[itemId] or ('Item' .. itemId))
                    local first, second = name:match('^(%w)%w*%s+(%w)')
                    local label = first and (first .. second):upper() or name:sub(1, 2):upper()
                    out[#out + 1] = ('<g opacity="%.2f"%s><rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" fill="url(#icon)"/>'):format(
                        tint, clipAttr, a[1], a[2], w, h, w * 0.12)
                    out[#out + 1] = ('<text x="%.2f" y="%.2f" font-family="DejaVu Sans" font-weight="bold" font-size="%.1f" fill="#2A1E0E" text-anchor="middle">%s</text></g>'):format(
                        a[1] + w / 2, a[2] + h * 0.64, h * 0.34, label)
                end
            elseif p.op == 'text' then
                local c, o = decode(a[3])
                local size = a[5]
                local width = 0.5 * size * #a[4]
                out[#out + 1] = ('<text x="%.2f" y="%.2f" font-family="Tahoma, \'DejaVu Sans\', sans-serif" font-size="%.2f"%s fill="%s" fill-opacity="%.3f" textLength="%.2f" lengthAdjust="spacingAndGlyphs"%s>%s</text>'):format(
                    a[1], a[2] + size * 0.82, size, a[6] and ' font-weight="bold"' or '', c, o, width, clipAttr, esc(a[4]))
            elseif p.op == 'input' then
                out[#out + 1] = ('<text x="%.2f" y="%.2f" font-family="DejaVu Sans" font-size="13" fill="#FFFFFF"%s>%s</text>'):format(a[1] + 4, a[2] + 19, clipAttr, esc(a[4]))
            end
        end
        out[#out + 1] = '</svg>'
        local file = assert(realOpen(path, 'w'))
        file:write(table.concat(out, '\n'))
        file:close()
    end

    local function scene(name, width, height, setup)
        S.record = false
        if setup then setup() end
        -- a few frames so icons load and sizes settle
        for _ = 1, 6 do frame(false) end
        S.record = true
        local f, why = frame(true)
        S.record = false
        if why ~= nil then
            print('  scene ' .. name .. ': ' .. why)
        end
        svg(f, PREVIEW_DIR .. '/' .. name .. '.svg', width, height)
        print(('  wrote %s.svg (%i primitives)'):format(name, f.prims))
        return f
    end

    -- the mockup's character: crafts from the cool mode boards
    fire('load')
    advance(4)
    frame(false)
    SetBags({
        [0] = { [4098] = 12, [719] = 2, [4099] = 0 },
        [5] = { [719] = 6 },
        [1] = { [4099] = 5 },
    })
    local levels = { 62.4, 60.0, 60.3, 60.0, 64.1, 100.0, 60.0, 61.2 }
    for craftId, level in ipairs(levels) do
        config.skills[craftId][1] = level
        config.ranks[craftId][1] = craftId == 6 and 9 or 6
    end
    config.capped[6][1] = true
    S.display = { x = 1600, y = 1500 }
    config.book.pos[1], config.book.pos[2] = 40, 40
    config.planner.pos[1], config.planner.pos[2] = 600, 40
    config.tracker.pos[1], config.tracker.pos[2] = 1220, 60
    prices.Set(4099, 130)
    prices.Set(1273, 2500)
    prices.Set(850, 450)

    local st = book.State()
    local inferno = recipes.byResult[14164][1]
    config.planner.visible[1] = false
    config.tracker.visible[1] = false
    scene('book_recipes', 1600, 1100, function()
        st.filter[1] = 'inferno'
        st.open = { [inferno.id] = true }
        st.expanded = { ['r' .. inferno.id .. '>12987'] = true }
        frame(false)
        local f2 = frame(true)
        local rect = f2.rects['HCrafter###hcrafter.book>hcrafter.book.body/book.mr' .. inferno.id .. '>12987>719']
        if rect then
            S.mouse = { rect[1] + 160, rect[2] + 20 }
        end
        S.hover = 'book.mr' .. inferno.id .. '>12987>719'
    end)
    S.hover = nil
    S.mouse = nil

    config.book.visible[1] = false
    config.planner.visible[1] = true
    scene('planner_plan', 1600, 1500, function()
        config.planner.entries = T{ T{ recipeId = inferno.id, synths = T{ 12 } } }
        config.planner.make = T{ [12987] = 1, [719] = 1 }
        config.planner.tab[1] = 1
    end)
    scene('planner_skillup', 1600, 1300, function()
        config.planner.tab[1] = 2
        config.skillup.craft[1] = 5
        config.skillup.target[1] = 66
    end)
    config.planner.visible[1] = false
    config.planner.tab[1] = 1

    config.tracker.visible[1] = true
    scene('tracker', 1600, 900, function()
        history.Clear()
        history.Add({ startTime = timeNow, item = 12987, count = 1, result = 0, recipe = recipes.byResult[12987][1].id, lost = { }, skillup = { } })
        watch.OnRequest({ crystal = 4098, ingredients = { 719, 850 } })
        watch.OnResult(false)
        watch.OnResult(false)
        SetBags({ [0] = { [4098] = 12, [719] = 2, [850] = 2 }, [5] = { [719] = 6 }, [1] = { [4099] = 5 } })
        stock.Refresh(true)
        advance(3)
    end)

    scene('fanfare', 1600, 900, function()
        S.display = { x = 1600, y = 900 }
        config.tracker.visible[1] = false
        fanfare.Clear()
        fanfare.LevelUp(config.fanfare, 6, 101)
        fanfare.HQ(config.fanfare, 14164, 1, 3, 0.0156)
        fanfare.SynthsDone(6)
        advance(0.6)
    end)
    fanfare.Clear()
    S.display = { x = 1600, y = 1500 }

    config.book.visible[1] = true
    scene('book_history', 1600, 1300, function()
        config.book.tab[1] = 2
        history.Clear()
        local samples = {
            { 14164, 1, 0, { }, { [6] = 0.1 } }, { 14164, 1, 3, { }, { } }, { 12987, 1, 1, { 850 }, { [1] = 0.1 } },
            { 12987, 1, 0, { }, { } }, { 719, 1, 2, { }, { [1] = 0.1 } }, { 719, 3, 0, { }, { } },
        }
        for i = #samples, 1, -1 do
            local sample = samples[i]
            local skill = { }
            for craftId, change in pairs(sample[5]) do skill[craftId] = { change = change, before = 60 } end
            history.Add({ startTime = timeNow - i * 140, item = sample[1], count = sample[2], result = sample[3], lost = sample[4], skillup = skill })
        end
    end)
    scene('book_settings', 1600, 1500, function()
        config.book.tab[1] = 3
        G.equip = { [5] = 14397 }
        gear.Refresh(true)
    end)
    config.book.tab[1] = 1
    cleanup()
    os.exit(0)
end

---------------------------------------------------------------------------
print('== settings: defaults are never shared')
check(not rawequal(config.planner, defaults.planner) and not rawequal(config.planner.entries, defaults.planner.entries)
    and not rawequal(config.skills[1], defaults.skills[1]) and not rawequal(config.look, defaults.look)
    and not rawequal(config.ranks[3], defaults.ranks[3]), 'every settings table is a copy, not the default itself')
table.insert(config.planner.entries, T{ recipeId = 1, synths = T{ 1 } })
check(#defaults.planner.entries == 0, 'editing settings leaves the defaults alone')
table.remove(config.planner.entries)
check(files.BaseDir() == TMP .. '\\config\\addons\\hcrafter', 'files live under config\\addons\\hcrafter, from the addon name')

---------------------------------------------------------------------------
print('== HQ estimates')
do
    local function ctx(skills, gearBonus, support, rings)
        return {
            skill = function(c) return skills[c] or 0 end,
            gear = function(c) return (gearBonus or { })[c] or 0 end,
            support = function(c) return (support or { })[c] or 0 end,
            ring = function(c) return (rings or { })[c] end,
        }
    end
    local function est(levels, skills, gearBonus, support, rings)
        return hq.Estimate({ skills = levels }, ctx(skills, gearBonus, support, rings))
    end
    local cases = {
        { 0, 'T0' }, { 10, 'T0' }, { 11, 'T1' }, { 30, 'T1' }, { 31, 'T2' }, { 50, 'T2' }, { 51, 'T3' }, { 80, 'T3' },
    }
    local allTiers = true
    for _, case in ipairs(cases) do
        local e = est({ 40, 0, 0, 0, 0, 0, 0, 0 }, { [1] = 40 + case[1] + 0.9 })
        if e.underCap or e.tier.name ~= case[2] or e.success ~= 95 then allTiers = false end
    end
    check(allTiers, 'tier edges: 0 and 10 T0, 11 and 30 T1, 31 and 50 T2, 51+ T3 (skill decimals ignored)')
    local u1, u3, u9, u12 = est({ 40 }, { [1] = 39 }), est({ 40 }, { [1] = 37 }), est({ 40 }, { [1] = 31 }), est({ 40 }, { [1] = 28 })
    check(u1.underCap and u1.success == 85 and u3.success == 65 and u9.success == 5 and u12.success == 5, 'under cap: 85, 65, then a 5 floor (HorizonXI wiki)')
    local multi = est({ 60, 20, 0, 0, 0, 0, 0, 0 }, { [1] = 100, [2] = 25 })
    check(multi.craftId == 2 and multi.margin == 5 and multi.tier.name == 'T0' and multi.success == 92, 'two crafts: the weaker sets the tier, and success at cap is 96 x 96 = 92')
    local mixed = est({ 60, 20, 0, 0, 0, 0, 0, 0 }, { [1] = 59, [2] = 25 })
    check(mixed.underCap and mixed.success == 82, 'two crafts, one 1 under: 92 less 10 = 82')
    local three = est({ 60, 20, 30, 0, 0, 0, 0, 0 }, { [1] = 60, [2] = 25, [3] = 30 })
    local threeUnder = est({ 60, 20, 30, 0, 0, 0, 0, 0 }, { [1] = 58, [2] = 19, [3] = 30 })
    check(three.success == 91 and threeUnder.success == 61 and est({ 60, 20 }, { [1] = 50, [2] = 10 }).success == 5,
        'three crafts at cap 97 x 97 x 97 = 91, three levels under in all 61, and never below 5')
    local oddGear = est({ 40 }, { [1] = 50 }, { [1] = 1.5 })
    local textGear = est({ 40 }, { [1] = 50 }, { [1] = '2' })
    check(oddGear.tier ~= nil and oddGear.margin == 12 and oddGear.tier.name == 'T1' and textGear.margin == 12,
        'a gear bonus with decimals or as text from a hand-edited file still gives a tier')
    local boosted = est({ 60, 20, 0, 0, 0, 0, 0, 0 }, { [1] = 75, [2] = 25 }, { [2] = 1 }, { [2] = 3 })
    check(boosted.craftId == 2 and boosted.margin == 9 and boosted.hasBonus, 'gear and support add to the craft they belong to')
    local wrongCraft = est({ 60, 20, 0, 0, 0, 0, 0, 0 }, { [1] = 75, [2] = 25 }, nil, { [1] = 3 })
    check(wrongCraft.craftId == 2 and wrongCraft.margin == 5, 'support on another craft does not help the weak one')
    local ringed = est({ 40 }, { [1] = 60 }, nil, nil, { [1] = 15819 })
    check(ringed.ring == 15819 and not ringed.canHQ and ringed.success == 96 and ringed.tier.name == 'T1', 'a crafting ring blocks HQ and adds 1 to success')
    check(hq.OutcomeChance(ringed, 2) == nil, 'with a crafting ring on, an HQ shows no odds, since the model says it cannot happen')
    check(hq.BaseSuccess(4) < hq.BaseSuccess(3) and hq.BaseSuccess(7) < hq.BaseSuccess(4) and hq.BaseSuccess(7) < 1,
        'more crafts never mean better odds, even past the three any recipe needs')
    check(est({ 40 }, { [1] = 60 }, nil, nil, { [2] = 15820 }).ring == nil, 'a ring for a craft the recipe does not use changes nothing')
    check(hq.Estimate({ skills = { 0, 0, 0, 0, 0, 0, 0, 0 } }, ctx({ })) == nil, 'a recipe with no craft gives no estimate')
    local drifted = 70
    for _ = 1, 10 do drifted = drifted + 0.1 end
    local atCap = est({ 71 }, { [1] = drifted })
    check(drifted < 71 and not atCap.underCap and atCap.margin == 0, 'a skill of 70.9999999 (ten 0.1 skill-ups) counts as 71')
    local placeholder = est({ 255 }, { [1] = 60 })
    check(placeholder.unknown and hq.Describe(placeholder, recipes.skillNames) == 'No estimate: the recipe data lists Woodworking 255', 'a placeholder level 255 gets no estimate')
    check(not hq.Describe(u3, recipes.skillNames):find('%', 1, true), 'the under-cap line uses the word percent')
    local t0, t1, t2, t3 = est({ 40 }, { [1] = 45 }), est({ 40 }, { [1] = 55 }), est({ 40 }, { [1] = 75 }), est({ 40 }, { [1] = 95 })
    local function near(a, b) return a ~= nil and math.abs(a - b) < 1e-9 end
    check(near(hq.OutcomeChance(t0, 2), 1 / 64) and near(hq.OutcomeChance(t1, 2), 1 / 16) and near(hq.OutcomeChance(t1, 3), 0.25 / 16)
        and near(hq.OutcomeChance(t2, 4), 0.25 * 0.25 / 4) and near(hq.OutcomeChance(t3, 2), 1 / 2) and near(hq.OutcomeChance(t3, 3), 0.25 * 0.75 / 2),
        'HQ odds: 2 is any HQ (LandSandBoat sends it for every tier), HQ2 and HQ3 by the upgrade rolls')
    check(hq.OutcomeChance(u3, 2) == nil, 'no HQ odds under cap')
    check(hq.OutcomeChance(t0, 3) == nil and hq.OutcomeChance(t1, 4) == nil and hq.OutcomeChance(t0, 4) == nil,
        'no odds for a result the model says cannot happen (HQ2 at T0, HQ3 at T0 or T1)')
    check(t0.nextTier.name == 'T1' and t0.toNext == 6 and t3.nextTier == nil, 'the next tier and the levels to it')

    -- what image support would do
    local nine = { skills = { 40, 0, 0, 0, 0, 0, 0, 0 } }
    local hints = hq.Hints(nine, ctx({ [1] = 49 }), nil)
    check(#hints == 1 and hints[1].kind == 'support' and hints[1].support == 3 and hints[1].tier == 'T1', '9 over cap: advanced support (+3) would reach T1')
    hints = hq.Hints(nine, ctx({ [1] = 50 }), nil)
    check(#hints == 1 and hints[1].support == 1 and hints[1].tier == 'T1', '10 over cap: basic support (+1) is enough')
    hints = hq.Hints(nine, ctx({ [1] = 45 }), nil)
    check(#hints == 0, '5 over cap: no support reaches the next tier, so no hint')
    hints = hq.Hints(nine, ctx({ [1] = 49 }), 4)
    check(#hints == 2 and hints[2].kind == 'elsewhere' and hints[2].other == 4, 'imagery on for another craft is pointed out')
    hints = hq.Hints(nine, ctx({ [1] = 49 }, nil, { [1] = 3 }), 1)
    check(#hints == 1 and hints[1].kind == 'imagery' and hints[1].support == 3, 'imagery on for this craft: it is counted, no hint')
    hints = hq.Hints(nine, ctx({ [1] = 38 }), nil)
    check(#hints == 1 and hints[1].cap and hints[1].support == 3, '2 under cap: +3 support reaches the cap')
    hints = hq.Hints(nine, ctx({ [1] = 33 }), nil)
    check(#hints == 1 and hints[1].success == 55 and hints[1].support == 3, '7 under cap: +3 support lifts success from 25 to 55')
    hints = hq.Hints(nine, ctx({ [1] = 60 }, nil, nil, { [1] = 15819 }), nil)
    check(hints[1].kind == 'ring' and hints[1].ring == 15819, 'a crafting ring shows as a hint')
end

---------------------------------------------------------------------------
print('== skill-up model')
do
    local function near(a, b) return math.abs(a - b) < 1e-9 end
    check(skillup.BaseChance(49.9) == 0.6 and skillup.BaseChance(50.0) == 0.25 and skillup.BaseChance(10) == 0.6, 'era chance: 60 below 50.0, 25 from 50.0')
    check(near(skillup.ExpectedAmount(45, 1), 1.15) and near(skillup.ExpectedAmount(45, 3), 1.2) and near(skillup.ExpectedAmount(45, 9), 1.6)
        and near(skillup.ExpectedAmount(45, 20), 3.0) and skillup.ExpectedAmount(60, 9) == 1 and skillup.ExpectedAmount(59.9, 0) == 1.15,
        'skill-up size: LandSandBoat weights below 60, always 0.1 from 60')
    local b1 = skillup.Band(64, 62.4, 0, 70)
    local b2 = skillup.Band(66, 62, 0, 70)
    local b3 = skillup.Band(68, 62, 0, 70)
    local b4 = skillup.Band(62, 62.4, 0, 70)
    local b5 = skillup.Band(66, 62, 3, 70)
    local b6 = skillup.Band(66, 70, 0, 70)
    check(b1 == 'optimal' and b2 == 'costly' and b3 == 'danger' and b4 == 'none' and b5 == 'optimal' and b6 == 'none',
        'bands: 2 over optimal, 4 costly, 6 dangerous, at level none, gear makes 4 optimal, at rank cap none')

    local recipe = { id = 99001, result = 702, crystal = 4098, keyItem = 0, ingredients = { 702 }, skills = { 44, 0, 0, 0, 0, 0, 0, 0 }, count = 1 }
    local function ctx(skill, bonus, cap)
        return {
            skill = function(c) return c == 1 and skill or 0 end,
            gear = function(c) return c == 1 and (bonus or 0) or 0 end,
            support = function() return 0 end,
            ring = function() return nil end,
            cap = function() return cap end,
        }
    end
    local per = skillup.PerSynth(recipe, 1, ctx(41.0), { breakRule = 1 })
    local expected = (0.65 * 0.6 + 0.35 * 0.3) * 1.2 / 10
    check(near(per.gain, expected) and per.band == 'costly' and per.gap == 3, ('3 over at 41: gain %.4f per synth (65 success, 60 chance, half on breaks)'):format(per.gain))
    per = skillup.PerSynth(recipe, 1, ctx(41.0), { breakRule = 2 })
    check(near(per.gain, (0.65 * 0.6 + 0.35 * 0.6) * 1.2 / 10), 'the same-rate break rule counts breaks fully')
    per = skillup.PerSynth(recipe, 1, ctx(37.0), { breakRule = 1 })
    check(near(per.gain, 0.25 * 0.6 * 1.4 / 10) and per.band == 'danger', '7 over: breaks give nothing, only the 25 percent that succeed')
    per = skillup.PerSynth(recipe, 1, ctx(41.0, 3), { breakRule = 1 })
    check(near(per.gain, 0.95 * 0.6 * 1.2 / 10 + 0.05 * 0.3 * 1.2 / 10) and per.band == 'optimal', '+3 gear: 95 success, skill-ups still count from real skill')
    per = skillup.PerSynth(recipe, 1, ctx(43.9, 0, 44), { breakRule = 1 })
    check(near(per.gain, (0.85 * 0.6 + 0.15 * 0.3) * 1 / 10), 'one tenth below the rank cap: skill-ups, capped at that last tenth')
    per = skillup.PerSynth(recipe, 1, ctx(44.0, 0, 44), { breakRule = 1 })
    check(per.gain == 0 and per.band == 'none', 'at the rank cap: no skill-ups')
    per = skillup.PerSynth(recipe, 1, ctx(41.0), { breakRule = 1, rate = 0.4 })
    check(near(per.gain, (0.65 * 0.4 + 0.35 * 0.2) * 1.2 / 10), 'a measured rate replaces the era rate')

    local list = {
        { recipe = recipe.id, result = 0, skillup = { [1] = { before = 41.0, change = 0.1 } } },
        { recipe = recipe.id, result = 0, skillup = { [1] = { before = 41.1 } } },
        { recipe = recipe.id, result = 1, skillup = { [1] = { before = 41.1, change = 0.1 } } },
        { recipe = recipe.id, result = 0, skillup = { [1] = { before = 44.0 } } },
        { recipe = recipe.id, result = 0, skillup = { [1] = { before = 52.0 } } },
        { recipe = recipe.id, result = 0, skillup = { [1] = { change = 0.1 } } },
    }
    recipes.byId[recipe.id] = recipe
    local ups, chances = skillup.Measured(1, list, 42.0, nil)
    check(ups == 1 and chances == 2, 'measured rate: successful synths below the recipe level and on the same side of 50 count')
    recipes.byId[recipe.id] = nil

    -- a real plan from the recipe data
    local woodCtx = {
        skill = function(c) return c == 1 and 30.4 or 100 end,
        gear = function() return 0 end,
        support = function() return 0 end,
        ring = function() return nil end,
        cap = function() return nil end,
    }
    local ideas = skillup.Recommend(1, woodCtx, { breakRule = 1 }, 10)
    local sorted, allGive = true, true
    for i, idea in ipairs(ideas) do
        if idea.gain <= 0 or idea.level <= 30 or idea.level > 38 then allGive = false end
        if i > 1 then
            local a, b = ideas[i - 1], idea
            local ao, bo = skillup.bandOrder[a.band], skillup.bandOrder[b.band]
            if ao > bo or (ao == bo and a.gain < b.gain - 1e-12) then sorted = false end
        end
    end
    check(#ideas > 0 and allGive and sorted, ('woodworking 30.4: %i ideas, all 1 to 8 over, best band first then most skill per synth'):format(#ideas))
    local steps, total = skillup.Plan(1, 33, woodCtx, { breakRule = 1 })
    local sum, contiguous = 0, true
    for i, step in ipairs(steps or { }) do
        sum = sum + step.synths
        if i == 1 and math.abs(step.from - 30.4) > 1e-9 then contiguous = false end
        if i > 1 and math.abs(steps[i - 1].to - step.from) > 1e-9 then contiguous = false end
    end
    check(total ~= nil and #steps == 3 and contiguous and math.abs(sum - total) < 1e-6 and math.abs(steps[#steps].to - 33) < 1e-9,
        ('plan 30.4 to 33: %i steps, about %i synths'):format(#(steps or { }), math.floor((total or 0) + 0.5)))
end

---------------------------------------------------------------------------
print('== prices file')
do
    local path = TMP .. '/config/addons/hcrafter/prices.csv'
    writeFile(path, table.concat({
        'item_id,name,price,updated',
        '4099,Earth Crystal,120,2026-10-01',
        '719,"Ebony Lumber, the good kind","1,500",2026-10-02',
        ',ebony log,900g,',
        '12987,Ebony Sabots,not a price,',
        '# a comment line',
        '',
        '850,Sheep Leather,  450 ,2026-10-03',
    }, '\r\n'))
    local n, skipped = prices.Load(true)
    check(n == 4 and skipped == 1, ('csv: %i prices read, %i bad line skipped'):format(n, skipped))
    check(prices.Get(4099) == 120 and prices.Get(719) == 1500 and prices.Get(702) == 900 and prices.Get(850) == 450 and prices.Get(12987) == nil,
        'quoted names, "1,500", 900g, spaces and a name-only line all read')
    check(select(2, prices.Get(4099)) == '2026-10-01', 'the date a price was set is kept')
    local before = readFile(path) or ''
    local ok = prices.Set(1273, 2500)
    local data = readFile(path) or ''
    check(ok and data == before .. '\r\n1273,Namtar Bone,2500,' .. prices.date() .. '\r\n',
        'setting a new price adds one line and leaves every other line as it was, Windows line ends too')
    -- another character changes the file in the meantime
    writeFile(path, data .. '4098,Wind Crystal,80,2026-10-17\n')
    prices.Set(4099, 130)
    data = readFile(path) or ''
    check(prices.Get(4098) == 80 and prices.Get(4099) == 130 and data:find('4098,Wind Crystal,80', 1, true),
        'a change made elsewhere is kept when this character saves')
    check(data:find('^item_id,name,price,updated\r\n4099,Earth Crystal,130,') ~= nil and not data:find('4099,Earth Crystal,120', 1, true),
        'a changed price stays on its own line, in place')
    prices.Set(4098, nil)
    data = readFile(path) or ''
    check(prices.Get(4098) == nil and not data:find('4098,', 1, true), 'clearing a price removes its line')
    check(data:find('\r\n# a comment line\r\n\r\n', 1, true) and data:find('\r\n12987,Ebony Sabots,not a price,\r\n', 1, true)
        and data:find('\r\n719,"Ebony Lumber, the good kind","1,500",2026-10-02\r\n', 1, true) and not data:find('[^\r]\n'),
        'comments, blank lines, lines it cannot read and your own names survive every save')
    prices.Set(702, 950)
    data = readFile(path) or ''
    check(prices.Get(702) == 950 and data:find('\r\n702,ebony log,950,', 1, true) and not data:find('900g', 1, true),
        'a name-only line gets its item id and the new price, and keeps your name')
    prices.Set(702, 900)
    -- two lines for one item: the later one counts, and a save keeps one
    local dupes = TMP .. '/config/addons/hcrafter/prices_dupes.csv'
    local realPath = prices.Path
    prices.Path = function() return dupes end
    writeFile(dupes, '4099,Earth Crystal,100,\n850,Sheep Leather,450,\n4099,Earth Crystal,110,\n')
    prices.Load(true)
    local later = prices.Get(4099)
    prices.Set(4099, 120)
    data = readFile(dupes) or ''
    local _, lines4099 = data:gsub('4099,', '')
    check(later == 110 and prices.Get(4099) == 120 and lines4099 == 1 and data:find('^4099,Earth Crystal,120,') and not data:find('\r', 1, true),
        'with two lines for one item the later counts, a save keeps one line, and Unix line ends stay')
    prices.Path = realPath
    prices.Load(true)
    -- columns you add after the date stay, and a byte order mark stays
    prices.Path = function() return dupes end
    writeFile(dupes, '\239\187\1914099,Earth Crystal,120,2026-01-01,buy in Jeuno,"cheap, mostly"\n850,Sheep Leather,450,\n')
    local nBom, badBom = prices.Load(true)
    prices.Set(4099, 125)
    data = readFile(dupes) or ''
    local _, lines4099b = data:gsub('4099,', '')
    local expectBom = '\239\187\1914099,Earth Crystal,125,' .. prices.date() .. ',buy in Jeuno,"cheap, mostly"\n'
    check(nBom == 2 and badBom == 0 and lines4099b == 1 and data:sub(1, #expectBom) == expectBom,
        'a byte order mark and extra columns after the date survive a save')
    prices.Path = realPath
    prices.Load(true)
    -- a file that is there but can't be read right now is left alone
    local realReadText = files.ReadText
    files.ReadText = function() return nil end
    local untouched = readFile(path)
    local okLocked, whyLocked = prices.Set(4099, 999)
    files.ReadText = realReadText
    check(not okLocked and tostring(whyLocked):find('could not read', 1, true) and readFile(path) == untouched and prices.Get(4099) == 130,
        'a prices file that is there but cannot be read is never written over')
    -- the same when Ashita can't say whether the file is there, once it was read
    local realExists = ashita.fs.exists
    ashita.fs.exists = nil
    files.ReadText = function() return nil end
    local okUnknown = prices.Set(4099, 999)
    files.ReadText = realReadText
    ashita.fs.exists = realExists
    check(not okUnknown and readFile(path) == untouched, 'with no way to check, a prices file read earlier is not written over')
    check(prices.Format(1234567) == '1,234,567' and prices.Format(999) == '999' and prices.Format(123456) == '123,456', 'prices print with commas')
    check(not prices.Set(4099, -5) and not prices.Set(4099, '12.5') and prices.Get(4099) == 130, 'negative and decimal prices are refused')
    check(prices.Find('EBONY LUMBER') == 719 and prices.Find('inferno sabots') == 14164 and prices.Find('no such thing') == nil, 'names match the items recipes use, any case')
    local fields = prices.SplitLine('1,"a ""quoted"" name",3,')
    check(#fields == 4 and fields[2] == 'a "quoted" name' and fields[4] == '', 'csv fields with doubled quotes and an empty last field')
end

---------------------------------------------------------------------------
print('== stack text and spare')
do
    local st = planner.StackText
    check(st(0, 12) == 'none' and st(7, 12) == '7 singles, or 1 stack (5 spare)' and st(12, 12) == '1 stack'
        and st(27, 12) == '2 stacks + 3, or 3 stacks (9 spare)' and st(24, 12) == '2 stacks' and st(5, 1) == '5'
        and st(1, 12) == '1 single, or 1 stack (11 spare)', 'stack text for singles, full stacks, mixes and gear')
    check(planner.WithSpare(12, 10) == 14 and planner.WithSpare(10, 10) == 11 and planner.WithSpare(12, 0) == 12 and planner.WithSpare(0, 50) == 0, 'spare percent rounds up in whole numbers')
end

---------------------------------------------------------------------------
print('== load: fonts, character, bag snapshots')
fire('load')
check(text.HasGameFont(), 'Tahoma loads from the load event')
check(session.name == 'Alpha', 'loading mid-session picks up the logged-in character')
local f, why = frame(true)
check(why == nil, 'first frame balanced' .. (why and (': ' .. why) or ''))
check(readFile(charFile('Alpha')) == nil, 'nothing saved before the bags are ready')
advance(4)
frame(false)
check(readFile(charFile('Alpha')) ~= nil, 'Alpha saved after the load delay')

-- log out, then in on a mule. party memory keeps the old name on purpose.
fire('packet_in', zoneOut(true))
check(session.name == nil, 'logout clears the character')
G.entity = false
advance(70)
frame(false)
G.entity = true
G.entityName, G.serverId = 'Mule1', 5151
G.partyName = 'Alpha'
SetBags({ [0] = { [1273] = 3 }, [1] = { [702] = 30, [4098] = 6 } })
fire('packet_in', zoneIn('Mule1', 5151))
check(session.name == 'Mule1', 'the zone-in packet names the new character')
advance(1)
frame(false)
check(readFile(charFile('Mule1')) == nil, 'mule not saved while zoning')
fire('packet_in', inventoryFinish)
G.entityName = 'Alpha'                       -- the game still shows the old entity
advance(3)
frame(false)
check(readFile(charFile('Mule1')) == nil and not readFile(charFile('Alpha')):find('[702]', 1, true), 'a stale entity name blocks the save, and Alpha keeps her own bags')
G.entityName = 'Mule1'
advance(1)
frame(false)
check(readFile(charFile('Mule1')) ~= nil, 'mule saved once its bags loaded')
local others = stock.OtherCharacters()
check(#others == 1 and others[1].name == 'Alpha', 'on the mule, Alpha shows as the other character')

-- back to Alpha
G.entityName, G.serverId, G.partyName = 'Alpha', 4242, 'Alpha'
SetBags(ALPHA_BAGS)
fire('packet_in', zoneOut(true))
fire('packet_in', zoneIn('Alpha', 4242))
fire('packet_in', inventoryFinish)
advance(3)
frame(false)
others = stock.OtherCharacters()
check(#others == 1 and others[1].name == 'Mule1' and others[1].items == 39, 'back on Alpha, Mule1 is on file with 39 items')
local onYou, inBags, onOthers = stock.Counts(702)
check(onYou == 0 and inBags == 0 and onOthers == 30, 'ebony log: 0 on you, 0 in bags, 30 on the mule')
onYou, inBags, onOthers = stock.Counts(719)
check(onYou == 2 and inBags == 6 and onOthers == 0, 'ebony lumber: 2 on you, 6 in the satchel')
do
-- a snapshot that changed on disk (another game window saved it) is read
-- on the frame after the next zone-in, not every few minutes
local mulePath = charFile('Mule1')
local muleText = readFile(mulePath) or ''
writeFile(mulePath, (muleText:gsub('%[702%] = 30,', '[702] = 31,')))
advance(150)
frame(false)
local _, _, beforeZone = stock.Counts(702)
fire('packet_in', zoneIn('Alpha', 4242))
fire('packet_in', inventoryFinish)
advance(3)
frame(false)
local _, _, afterZone = stock.Counts(702)
check(muleText:find('[702] = 30,', 1, true) and beforeZone == 30 and afterZone == 31,
    ('other characters are read again after zoning, not every two minutes (%s then %s)'):format(tostring(beforeZone), tostring(afterZone)))
end

-- guards
SetBags({ [0] = { max = 80 } })
local saved, reason = stock.SaveCurrent(false)
check(not saved and reason == 'bags read empty', 'an all-empty read never overwrites a real snapshot on its own')
saved = stock.SaveCurrent(true)
check(saved, 'a forced save can record a character that really is empty')
SetBags(ALPHA_BAGS)
stock.SaveCurrent(true)
SetBags({ [0] = { [4098] = 12, [719] = 2 }, [5] = { [719] = 6 } })   -- mog safe not readable now
saved = stock.SaveCurrent(true)
local snap = readFile(charFile('Alpha'))
check(saved and snap:find('[1] = { saved', 1, true) and snap:find('[4099] = 5', 1, true), 'a bag the game is not showing keeps what was saved last time')
SetBags(ALPHA_BAGS)
stock.SaveCurrent(true)

-- a damaged character list is rebuilt from the folder
local indexPath = TMP .. '/config/addons/hcrafter/characters/index.lua'
local damaged = realOpen(indexPath, 'w')
damaged:write('return { "Mule1", ')
damaged:close()
stock.LoadOthers()
others = stock.OtherCharacters()
check(#others == 1 and others[1].name == 'Mule1', 'a damaged index still finds Mule1 from the folder')
stock.SaveCurrent(true)
check((readFile(indexPath) or ''):find('"Mule1"', 1, true) and readFile(indexPath):find('"Alpha"', 1, true), 'the next save writes a complete index again')
advance(2)

---------------------------------------------------------------------------
print('== recipe book: emblems, search, card, materials, hover, menu')
config.skills[6][1] = 80.0      -- bonecraft
config.skills[1][1] = 45.0      -- woodworking
config.skills[5][1] = 20.0      -- leathercraft
local st = book.State()
f, why = frame(true)
check(why == nil and #f.windows >= 1 and f.windows[1] == BOOK, 'the book draws first, balanced' .. (why and (': ' .. why) or ''))
check(hasText(f, 'HCrafter', 'hcrafter.book') and hasText(f, 'Recipes', 'hcrafter.book') and hasText(f, 'History', 'hcrafter.book') and hasText(f, 'Settings', 'hcrafter.book'), 'title and three tabs drawn')
check(hasText(f, '80.0', 'hcrafter.book') and hasText(f, '45.0', 'hcrafter.book'), 'the emblem row shows craft levels')
check(f.images >= 8, ('game icons used for the emblems (%i images)'):format(f.images))
check(hasTextLike(f, 'Type an item name', 'hcrafter.book') ~= nil, 'an empty search with no history shows a hint')

S.typed['##hcrafter.search'] = 'inferno sabots'
f, why = frame(true)
local inferno = recipes.byResult[14164][1]
local sabots = recipes.byResult[12987][1]
check(why == nil and st.open[inferno.id] == true, 'one match: the Inferno Sabots card opens by itself')
f, why = frame(true)
check(why == nil and hasText(f, 'Inferno Sabots', 'hcrafter.book') and hasTextLike(f, 'Bonecraft', 'hcrafter.book') ~= nil, 'the card shows the name and its craft')
check(hasText(f, 'Bonecraft 9 under cap', 'hcrafter.book') and hasText(f, 'success about 5%', 'hcrafter.book') and hasText(f, 'No HQ under cap', 'hcrafter.book'),
    'Bonecraft 80 on an 89 recipe: the ladder shows 9 under cap and about 5 percent success')
check(hasText(f, 'Materials', 'hcrafter.book') and hasText(f, 'Ebony Sabots', 'hcrafter.book') and hasText(f, 'Earth Crystal', 'hcrafter.book'), 'materials listed')
check(hasText(f, '0/1', 'hcrafter.book') and hasTextLike(f, '+5 in Mog Safe', 'hcrafter.book') ~= nil, 'earth crystal: 0 on you, +5 in the Mog Safe')
check(hasTextLike(f, '+3 on Mule1', 'hcrafter.book') ~= nil, 'namtar bone: +3 on the mule')
check(hasText(f, 'NB', 'hcrafter.book'), 'an item whose icon cannot load gets drawn initials')

local sabKey = 'book.mr' .. inferno.id .. '>12987'
S.click = { sabKey }
f, why = frame(true)
check(why == nil and st.expanded['r' .. inferno.id .. '>12987'] == true, 'clicking Ebony Sabots opens its recipe')
f, why = frame(true)
check(hasText(f, 'Ebony Lumber', 'hcrafter.book') and hasText(f, '2/1', 'hcrafter.book') and hasTextLike(f, '+6 in Mog Satchel', 'hcrafter.book') ~= nil,
    'ebony lumber: 2 on you, +6 in the satchel')
check(hasTextLike(f, 'HQ T', 'hcrafter.book') ~= nil, 'the sub-recipe shows its HQ chip')

S.hover = sabKey .. '>719'
f, why = frame(true)
S.hover = nil
check(why == nil and hasText(f, 'On you', 'foreground') and hasText(f, 'Mog Satchel', 'foreground') and hasText(f, '6', 'foreground'),
    'hovering lumber lists On you and Mog Satchel 6 in the tooltip')

S.click = { sabKey .. '>719' }
f, why = frame(true)
f, why = frame(true)
check(why == nil and hasText(f, 'Recipe 1', 'hcrafter.book') and hasText(f, 'Recipe 2', 'hcrafter.book') and hasTextLike(f, 'Makes 1 from 1 Ebony Log', 'hcrafter.book') ~= nil,
    'lumber has two recipes: picker and summary shown')
local key719 = 'book.optr' .. inferno.id .. '>12987>719'
S.click = { key719 .. '.seg2' }
f, why = frame(true)
f, why = frame(true)
check(st.option['r' .. inferno.id .. '>12987>719'] == 2 and hasTextLike(f, 'Makes 3 from 3 Ebony Log, 1 Bundling Twine, key item', 'hcrafter.book') ~= nil, 'picking recipe 2 shows the key item recipe')
check(hasText(f, 'key item 1986', 'hcrafter.book'), 'the key item line is shown')

S.rightClick = 'book.r' .. inferno.id
f, why = frame(true)
check(why == nil and #f.popupShown == 1, 'right-click opens the menu')
S.select = 'Add to Resource Planner'
f, why = frame(true)
check(why == nil and #config.planner.entries == 1 and config.planner.entries[1].recipeId == inferno.id and config.planner.visible[1], 'menu adds Inferno Sabots and opens the Resource Planner')
f, why = frame(true)
local planSeen = false
for _, name in ipairs(f.windows) do if name == PLAN then planSeen = true end end
check(why == nil and planSeen, 'the Resource Planner draws, balanced' .. (why and (': ' .. why) or ''))

-- set a price from the menu
S.rightClick = sabKey .. '>c4098'
f, why = frame(true)
S.rightClick = nil
check(why == nil, 'right-click on wind crystal opens its menu')
f, why = frame(true)
check(#f.popupShown == 1, 'the menu stays open')
S.select = 'Set price##hcrafter.setprice'
f, why = frame(true)
check(why == nil and S.select == nil, 'picking Set price closes the menu and asks for the price box')
S.select = nil
local okSet = false
for _ = 1, 3 do
    S.typed['##hcrafter.price'] = '95'
    S.buttons = { 'Save##hcrafter.pricesave' }
    f, why = frame(true)
    if prices.Get(4098) == 95 then okSet = true break end
end
check(why == nil and okSet, 'the price box saves 95 gil for Wind Crystal')
S.buttons = { }

---------------------------------------------------------------------------
print('== Resource Planner: 12 synths, make sabots and lumber')
st.option = { }
for _ = 1, 11 do
    S.click = { 'plan.synths1.plus' }
    frame(false)
end
check(config.planner.entries[1].synths[1] == 12, 'the + button steps the synths to 12')
S.click = { 'plan.mbe1>12987.seg2' }
f, why = frame(true)
check(why == nil and config.planner.make[12987] == 1, 'Make picked for Ebony Sabots')
S.click = { 'plan.mbe1>12987>719.seg2' }
f, why = frame(true)
f, why = frame(true)
check(why == nil and config.planner.make[719] == 1, 'Make picked for Ebony Lumber, nested under the sabots')

local function buyRow(result, id)
    for _, row in ipairs(result.buy) do if row.id == id then return row end end
end
local function madeRow(result, id)
    for _, row in ipairs(result.made) do if row.id == id then return row end end
end
local result = app.PlanResult()
local expected = {
    { 4099, 12, 7 }, { 4098, 16, 4 }, { 702, 4, 4 }, { 1273, 12, 12 }, { 850, 12, 12 },
}
for _, e in ipairs(expected) do
    local row = buyRow(result, e[1])
    check(row ~= nil and row.need == e[2] and row.buy == e[3], ('buy %s: need %i, buy %i%s'):format(names[e[1]], e[2], e[3],
        row and '' or ' (missing)') .. (row and (row.need ~= e[2] or row.buy ~= e[3]) and (' (got ' .. row.need .. ', ' .. row.buy .. ')') or ''))
end
local lumber = madeRow(result, 719)
local sab = madeRow(result, 12987)
check(lumber ~= nil and lumber.synths == 4 and lumber.leftover == 0 and sab ~= nil and sab.synths == 12, 'lumber 4 synths (12 needed, 8 held), sabots 12 synths')
check(hasText(f, '7 singles, or 1 stack (5 spare)', 'hcrafter.planner') and hasText(f, '1 stack', 'hcrafter.planner') and hasText(f, 'buy 7', 'hcrafter.planner'), 'how-to-buy text drawn')
-- prices so far: earth 130, wind 95, log 900, namtar 2500, leather 450
check(hasText(f, '380 g', 'hcrafter.planner') and hasText(f, 'Estimated cost: 40,290 gil', 'hcrafter.planner'),
    '4 wind crystals at 95 cost 380, and the whole list 40,290: ' .. tostring(hasTextLike(f, 'Estimated cost', 'hcrafter.planner')))
check(hasText(f, 'Synths, in order', 'hcrafter.planner') and hasTextLike(f, '12 synths, makes 12, queued', 'hcrafter.planner') ~= nil, 'the synth order ends with the queued Inferno Sabots')

S.click = { 'plan.others' }
f, why = frame(true)
result = app.PlanResult()
check(config.planner.useOthers[1] and buyRow(result, 702).buy == 0, 'with mules counted, the 4 ebony logs come from the mule')
S.click = { 'plan.others' }
frame(false)

S.click = { 'plan.oe1>12987>719.2' }
f, why = frame(true)
f, why = frame(true)
result = app.PlanResult()
check(config.planner.make[719] == 2, 'lumber switched to recipe 2')
check(buyRow(result, 702).need == 6 and buyRow(result, 1657).need == 2 and buyRow(result, 4098).need == 14, 'recipe 2: 6 logs, 2 bundling twine, 14 wind crystals')
check(madeRow(result, 719).synths == 2 and madeRow(result, 719).leftover == 2, 'recipe 2: 2 synths make 6, 2 left over')
check(hasText(f, 'Key items needed', 'hcrafter.planner') and hasText(f, 'key item 1986', 'hcrafter.planner'), 'the key item for recipe 2 is listed')

S.click = { 'plan.spare.plus' }
frame(false)
S.click = { 'plan.spare.plus' }
frame(false)
result = app.PlanResult()
check(config.planner.spare[1] == 10 and result.top[1].synths == 14 and madeRow(result, 12987).synths == 16, '10 percent spare: 12 becomes 14, and 14 sabots needed becomes 16')
config.planner.spare[1] = 0

-- the skill-up tab
config.planner.tab[1] = 2
config.skillup.craft[1] = 1
f, why = frame(true)
check(why == nil and hasTextLike(f, 'Woodworking 45.0', 'hcrafter.planner') ~= nil and hasText(f, 'Best recipes now', 'hcrafter.planner'), 'the skill-up tab shows the craft and ideas')
check(hasTextLike(f, 'About ', 'hcrafter.planner') ~= nil and hasTextLike(f, ' synths from 45.0 to 46.0', 'hcrafter.planner') ~= nil, 'an estimate to the next level')
S.click = { 'plan.target.plus' }
frame(false)
S.click = { 'plan.target.plus' }
f, why = frame(true)
check(config.skillup.target[1] == 48 and hasTextLike(f, 'to 48.0', 'hcrafter.planner') ~= nil, 'the target steps to 48')
S.click = { 'plan.craft6' }
f, why = frame(true)
check(config.skillup.craft[1] == 6, 'picking the bonecraft emblem switches crafts')
S.click = { 'plan.idea1' }
f, why = frame(true)
check(st.open ~= nil and config.book.tab[1] == 1 and st.filter[1] ~= 'inferno sabots', 'clicking an idea opens it in the recipe book: ' .. tostring(st.filter[1]))
config.planner.tab[1] = 1
st.filter[1] = 'inferno sabots'
st.lastFilter = 'inferno sabots'

S.click = { 'plan.remove1' }
f, why = frame(true)
check(#config.planner.entries == 0, 'remove clears the entry')
-- a saved entry whose recipe no longer exists is not drawn, so places in the
-- drawn list differ from places in the saved one
config.planner.entries = T{ T{ recipeId = 999999, synths = T{ 1 } }, T{ recipeId = sabots.id, synths = T{ 1 } }, T{ recipeId = inferno.id, synths = T{ 2 } } }
S.click = { 'plan.remove2' }
f, why = frame(true)
check(why == nil and #config.planner.entries == 2 and config.planner.entries[1].recipeId == 999999 and config.planner.entries[2].recipeId == sabots.id,
    'with a saved entry for a recipe that is gone, remove takes the entry you clicked')
config.planner.entries = T{ }

---------------------------------------------------------------------------
print('== gear, rings and imagery')
G.equip = { [5] = 14392, [13] = 15819 }       -- body: Carpenter's Apron, ring 1: Carpenter's Ring
advance(1)
gear.Refresh(true)
check(gear.Bonus(1) == 1 and app.Gear(1) == 1 and #gear.Items(1) == 1, 'a Carpenter\'s Apron adds Woodworking +1')
check(app.Ring(1) == 15819, 'a Carpenter\'s Ring in a ring slot is found')
local est = app.Estimate(sabots)
check(est.ring == 15819 and not est.canHQ, 'with the ring on, Ebony Sabots cannot HQ')
G.equip = { [4] = 15819 }
gear.Refresh(true)
check(app.Ring(1) == nil, 'a ring id outside the ring slots is ignored')
config.autoGear[1] = false
config.gear[1][1] = 2
check(app.Gear(1) == 2, 'with detection off, the typed gear bonus is used')
config.gear[1][1] = 1.5
local roundedGear = app.Gear(1)
config.gear[1][1] = 'x'
local textGear = app.Gear(1)
config.gear[1][1] = 2
check(roundedGear == 2 and textGear == 0, 'a typed gear bonus with decimals or text from a hand-edited file reads as a whole number')
config.autoGear[1] = true
G.equip = { }
G.buffs = { 236 }
gear.Refresh(true)
check(gear.HasImagery(1) and gear.ImageryCraft() == 1 and app.Support(1) == 1, 'Woodworking imagery (buff 236) counts +1')
config.support[1] = 3
check(app.Support(1) == 3 and app.Support(6) == 0, 'set to advanced it counts +3, and only for its own craft')
config.support[1] = 1
G.buffs = { }
gear.Refresh(true)

---------------------------------------------------------------------------
print('== packets: synths, skill-ups, levels, fanfare, the alert after a macro')
config.skills[1][1] = 45.0
config.skills[6][1] = 100.3
config.ranks[1][1] = 4
-- packet sizes as LandSandBoat sends them (src/map/packets, read
-- 2026-10-17): 0x096 is 0x24 bytes, 0x030 0x10, 0x06F 0x38, 0x029 0x1C
local function startSynth(ingredients, crystal, size)
    local fields = { [0x06] = { crystal or 4098, 2 }, [0x09] = { #ingredients, 1 } }
    for i, id in ipairs(ingredients) do fields[0x0A + (i - 1) * 2] = { id, 2 } end
    fire('packet_out', { id = 0x096, data = packet(size or 0x24, fields) })
end
local function synthEffect(param)
    fire('packet_in', { id = 0x030, data = packet(0x10, { [0x04] = { 4242, 4 }, [0x0C] = { param or 0, 1 } }) })
end
local function synthResult(item, result, lost, crystal, materials)
    local fields = { [0x04] = { result or 0, 1 }, [0x06] = { 1, 1 }, [0x08] = { item, 2 }, [0x1A] = { 49, 1 } }
    for i, id in ipairs(lost or { }) do fields[0x0A + (i - 1) * 2] = { id, 2 } end
    -- LandSandBoat also names the crystal and the materials
    if crystal ~= nil then fields[0x22] = { crystal, 2 } end
    for i, id in ipairs(materials or { }) do fields[0x24 + (i - 1) * 2] = { id, 2 } end
    fire('packet_in', { id = 0x06F, data = packet(0x38, fields) })
end
local function basic(message, param, value)
    fire('packet_in', { id = 0x029, data = packet(0x1C, { [0x08] = { 4242, 4 }, [0x0C] = { param, 4 }, [0x10] = { value, 4 }, [0x18] = { message, 2 } }) })
end
history.Clear()
fanfare.Clear()
sounds = { }
config.fanfare.skillUp[1] = true
SetBags({ [0] = { [4098] = 12, [719] = 4, [850] = 3 } })
stock.Refresh(true)
startSynth({ 719, 850 })
synthEffect(0)
synthResult(12987)
local latest = history.Latest()
check(#history.List() == 1 and latest.item == 12987 and latest.count == 1 and latest.recipe == sabots.id, 'synth lands in history as ebony sabots with its recipe')
check(latest.skillup[1] ~= nil and latest.skillup[1].before == 45.0, 'the skill before the synth is kept for the measured rate')
basic(38, 49, 1)
check(config.skills[1][1] == 45.1 and history.Latest().skillup[1].change == 0.1, 'skill-up adds 0.1 woodworking and tags the synth')
local banners = fanfare.Count()
check(banners == 1, 'with every skill-up on, a skill-up raises a small banner')
config.fanfare.skillUp[1] = false
fanfare.Clear()
basic(38, 49, 1)
check(fanfare.Count() == 0 and config.skills[1][1] == 45.2, 'by default a 0.1 skill-up has no banner')
config.skills[1][1] = 45.1
config.skills[1][1] = 70.0
for _ = 1, 10 do basic(38, 49, 1) end
check(config.skills[1][1] == 71, 'ten 0.1 skill-ups from 70 land exactly on 71')
fanfare.Clear()
sounds = { }
basic(53, 49, 71)
check(fanfare.Count() == 1 and #sounds == 1 and sounds[1]:find('levelup.wav', 1, true), 'a level-up raises a banner and plays levelup.wav')
f, why = frame(true)
check(why == nil and hasText(f, 'Woodworking 71', 'foreground') and hasText(f, 'Level up!', 'foreground'), 'the level-up banner is drawn')
advance(10)
f, why = frame(true)
check(fanfare.Count() == 0, 'banners go away on their own')
config.skills[1][1] = 45.0
history.Clear()
local okSkill = pcall(basic, 38, 50, 2)
check(okSkill and config.skills[2][1] == 0.2, 'a skill-up with an empty history still counts')

-- in a function of its own, so its locals don't count toward the main
-- chunk's limit of 200
;(function()
-- the alert after your macro: one alert after N synths in a row, no
-- countdown and no sound for each synth
fanfare.Clear()
sounds = { }
config.ready.every[1] = 3
advance(90)
frame(false)
SetBags({ [0] = { [4098] = 12, [719] = 10, [850] = 10 } })
stock.Refresh(true)
for _ = 1, 2 do
    startSynth({ 719, 850 })
    synthEffect(0)
    synthResult(12987)
    advance(3)
    frame(false)
end
f, why = frame(true)
check(watch.State() == 2 and #sounds == 0 and fanfare.Count() == 0, 'two synths into a run of three: no alert, no sound, no toast')
check(why == nil and hasTextLike(f, '2 of 3 synths done', 'hcrafter.tracker') ~= nil, 'the Shopping list quietly shows 2 of 3 synths done')
check(hasTextLike(f, 'Next synth', 'hcrafter.tracker') == nil and hasTextLike(f, 'Ready', 'hcrafter.tracker') == nil, 'no countdown and no ready line')
startSynth({ 719, 850 })
synthEffect(0)
synthResult(12987)
advance(1)
frame(false)
check(#sounds == 0, 'the alert waits a moment, so the inventory can catch up')
advance(1.5)
f, why = frame(true)
local _, toasts = fanfare.Count()
check(#sounds == 1 and sounds[1]:find('ready.wav', 1, true) and toasts == 1 and hasText(f, 'Macro done: 3 synths', 'foreground'),
    'the third synth in a row: one toast, "Macro done: 3 synths", with ready.wav')
check(watch.State() == 0 and hasTextLike(f, 'synths done', 'hcrafter.tracker') == nil, 'the count starts over after the alert')
advance(5)
frame(false)
check(#sounds == 1, 'the alert plays once')

-- out of a material after a synth
fanfare.Clear()
sounds = { }
startSynth({ 719, 850 })
synthEffect(0)
synthResult(12987)
SetBags({ [0] = { [4098] = 11, [719] = 9 } })     -- the last sheep leather went in
stock.Refresh(true)
advance(2.5)
f, why = frame(true)
local countShort, missingShort = watch.State()
check(missingShort == 850 and countShort == 0 and #sounds == 1 and sounds[1]:find('alert.wav', 1, true),
    'out of sheep leather after a synth: one alert with alert.wav, and the count starts over')
check(hasTextLike(f, 'Out of', 'foreground') ~= nil and hasTextLike(f, 'Out of', 'hcrafter.tracker') ~= nil, 'the toast and the Shopping list both say what ran out')
SetBags({ [0] = { [4098] = 11, [719] = 9, [850] = 5 } })
stock.Refresh(true)
advance(1.5)
frame(false)
local _, missingBack = watch.State()
check(missingBack == nil and #sounds == 1, 'the "Out of" line goes once the material is back, quietly')

-- a pause of more than 25 seconds after an answer starts a new count
sounds = { }
config.ready.every[1] = 2
advance(90)
frame(false)
startSynth({ 719, 850 })
synthEffect(0)
synthResult(12987)
advance(3)
frame(false)
advance(30)
frame(false)
check(watch.State() == 0, 'a run that stops for over 25 seconds is forgotten')
startSynth({ 719, 850 })
synthEffect(0)
synthResult(12987)
advance(3)
frame(false)
check(watch.State() == 1 and #sounds == 0, 'after the pause, the next synth is 1 of a new run')
startSynth({ 719, 850 })
synthEffect(0)
synthResult(12987)
advance(3)
f, why = frame(true)
check(#sounds == 1 and watch.State() == 0 and hasText(f, 'Macro done: 2 synths', 'foreground'), 'and the run alerts at 2: "Macro done: 2 synths"')

-- every macro line counts, refused or cancelled, so a run with a refused
-- line still alerts when the macro ends, and the next run stays in step
sounds = { }
config.ready.every[1] = 3
advance(90)
frame(false)
startSynth({ 719, 850 })
synthEffect(0)
synthResult(12987)
advance(3)
frame(false)
startSynth({ 719, 850 })
basic(94, 0, 0)
synthResult(0, 0x0D)
advance(3)
frame(false)
check(watch.State() == 2 and #sounds == 0, 'a refused line counts as a line of the macro')
startSynth({ 719, 850 })
synthResult(0, 3)
advance(3)
frame(false)
check(#sounds == 1 and watch.State() == 0, 'a cancelled line counts too, and the macro of three alerts on time')
startSynth({ 719, 850 })
synthEffect(0)
synthResult(12987)
advance(3)
frame(false)
check(watch.State() == 1, 'the next macro starts at 1')
basic(94, 0, 0)
frame(false)
check(watch.State() == 1, 'a "wait longer" with no request waiting is not counted')

-- the next line right after a result: the server already took its crystal,
-- so that result's material check is skipped
sounds = { }
fanfare.Clear()
config.ready.every[1] = 6
advance(90)
frame(false)
SetBags({ [0] = { [4098] = 2, [719] = 10, [850] = 10 } })
stock.Refresh(true)
startSynth({ 719, 850 })
synthEffect(0)
synthResult(12987)
advance(0.5)
SetBags({ [0] = { [4098] = 1, [719] = 9, [850] = 9 } })
stock.Refresh(true)
startSynth({ 719, 850 })
synthEffect(0)
SetBags({ [0] = { [4098] = 0, [719] = 9, [850] = 9 } })   -- the crystal goes as the synth starts
stock.Refresh(true)
advance(2.5)
frame(false)
local _, early = watch.State()
check(early == nil and #sounds == 0, 'no "Out of" while the last synth is still running')
synthResult(12987)
SetBags({ [0] = { [719] = 8, [850] = 8 } })
stock.Refresh(true)
advance(2.5)
f, why = frame(true)
local _, outCrystal = watch.State()
check(outCrystal == 4098 and #sounds == 1 and hasTextLike(f, 'Out of', 'foreground') ~= nil, 'after the last synth, one "Out of" for the crystal')
SetBags({ [0] = { [719] = 8 } })
stock.Refresh(true)
startSynth({ 719, 850 })
synthEffect(0)
synthResult(12987)
advance(2.5)
frame(false)
local _, firstShort = watch.State()
check(firstShort == 4098, 'with the crystal and a material both gone, "Out of" names the crystal first')
SetBags({ [0] = { [4098] = 12, [719] = 10, [850] = 10 } })
stock.Refresh(true)

-- a request whose answer never comes counts as answered after 30 seconds
sounds = { }
fanfare.Clear()
config.ready.every[1] = 1
advance(90)
frame(false)
startSynth({ 719, 850 })
advance(31)
frame(false)
advance(2.5)
frame(false)
check(#sounds == 1 and watch.State() == 0, 'a lost answer still ends the run')
config.ready.every[1] = 6

-- a refused request must not lend its guess to the next synth
history.Clear()
advance(90)
startSynth({ 698 })          -- ash lumber, refused
basic(94, 0, 0)
startSynth({ 719, 850 })     -- ebony sabots, goes through
synthEffect(0)
synthResult(12987)
check(#history.List() == 1 and history.Latest().recipe == sabots.id, 'after a refused ash lumber request, the sabots synth is recorded as sabots')

-- the alert switched off, sounds off, or no sound picked
config.ready.every[1] = 2
advance(90)
frame(false)
config.ready.enabled[1] = false
sounds = { }
fanfare.Clear()
for _ = 1, 2 do
    startSynth({ 719, 850 })
    synthEffect(0)
    synthResult(12987)
    advance(3)
    frame(false)
end
local _, toastsOff = fanfare.Count()
check(#sounds == 0 and toastsOff == 0, 'with the alert off, nothing shows and nothing plays')
config.ready.enabled[1] = true
advance(90)
frame(false)
config.sounds.done[1] = ''
for _ = 1, 2 do
    startSynth({ 719, 850 })
    synthEffect(0)
    synthResult(12987)
    advance(3)
    frame(false)
end
local _, toastsNone = fanfare.Count()
check(#sounds == 0 and toastsNone == 1, 'with None picked, the alert shows without a sound')
config.sounds.done[1] = 'ready.wav'
config.fanfare.sound[1] = false
fanfare.Clear()
advance(90)
frame(false)
for _ = 1, 2 do
    startSynth({ 719, 850 })
    synthEffect(0)
    synthResult(12987)
    advance(3)
    frame(false)
end
check(#sounds == 0, 'with Play sounds off, the alert is quiet')
config.fanfare.sound[1] = true
config.ready.every[1] = 6
fanfare.Clear()

end)()

-- HQ, break and fanfare sizes
fanfare.Clear()
sounds = { }
config.skills[1][1] = 45.0
advance(20)
startSynth({ 719, 850 })
synthEffect(2)
synthResult(12987)
check(history.Latest().result == 2 and fanfare.Count() == 1 and sounds[#sounds]:find('hq_big.wav', 1, true), 'a T0 HQ (1 in 64) gets the big fanfare')
fanfare.Clear()
sounds = { }
config.skills[1][1] = 60.0
advance(20)
startSynth({ 719, 850 })
synthEffect(2)
synthResult(12987)
check(fanfare.Count() == 1 and #sounds == 1 and sounds[1]:find('hq_big.wav', 1, true), 'a T1 HQ (1 in 16) gets fanfare too')
fanfare.Clear()
sounds = { }
config.skills[1][1] = 80.0
advance(20)
startSynth({ 719, 850 })
synthEffect(2)
synthResult(12987)
check(fanfare.Count() == 0 and #sounds == 0, 'a T2 HQ (1 in 4) is easy: no banner and no sound by default')
config.skills[1][1] = 45.0
fanfare.Clear()
config.skills[1][1] = 100.0
advance(20)
startSynth({ 719, 850 })
synthEffect(2)
synthResult(12987)
check(fanfare.Count() == 0, 'an easy T3 HQ (1 in 2) gets no banner by default')
config.fanfare.hqEasy[1] = true
advance(20)
startSynth({ 719, 850 })
synthEffect(2)
synthResult(12987)
check(sounds[#sounds]:find('hq.wav', 1, true) ~= nil and not sounds[#sounds]:find('hq_big', 1, true), 'with easy HQs on, a T3 HQ gets the small one')
f, why = frame(true)
check(hasText(f, 'HQ!', 'foreground') and hasTextLike(f, 'about 1 in 2', 'foreground') ~= nil, 'the HQ banner shows the odds')
config.fanfare.hqEasy[1] = false
fanfare.Clear()
advance(20)
startSynth({ 719, 850 })
synthEffect(1)
synthResult(29695, 1, { 850 })
check(history.Latest().result == 1 and history.Latest().item == 12987 and #history.Latest().lost == 1, 'a break keeps the guessed name and the lost item')
f, why = frame(true)
check(hasText(f, 'Synthesis failed', 'foreground') and hasText(f, 'Lost Sheep Leather', 'foreground') and (#sounds == 0 or not sounds[#sounds]:find('break.wav', 1, true)), 'the break banner names what was lost, with no sound by default')
config.sounds.breaks[1] = 'break.wav'
fanfare.Clear()
advance(20)
startSynth({ 719, 850 })
synthEffect(1)
synthResult(29695, 1, { 850 })
check(sounds[#sounds]:find('break.wav', 1, true) ~= nil, 'with Break set to a sound, a break plays it')
config.sounds.breaks[1] = ''
config.fanfare.sound[1] = false
config.skills[1][1] = 45.0
sounds = { }
fanfare.Clear()
advance(20)
startSynth({ 719, 850 })
synthEffect(2)
synthResult(12987)
check(#sounds == 0 and fanfare.Count() == 1, 'with sounds off, the banner still shows but nothing plays')
config.fanfare.sound[1] = true
config.fanfare.hq[1] = false
fanfare.Clear()
advance(20)
startSynth({ 719, 850 })
synthEffect(2)
synthResult(12987)
check(fanfare.Count() == 0, 'with HQ fanfare off, no banner')
config.fanfare.hq[1] = true
config.skills[1][1] = 45.0

-- the recipe you repeat stops giving skill-ups
fanfare.Clear()
config.skills[1][1] = 42.9
advance(20)
startSynth({ 719, 850 })
synthEffect(0)
synthResult(12987)
basic(38, 49, 1)
local _, toastCount = fanfare.Count()
check(config.skills[1][1] == 43 and toastCount == 1, 'reaching level 43 on a level 43 recipe raises a "no more skill-ups" toast')
f, why = frame(true)
check(hasTextLike(f, 'no more skill-ups from Ebony Sabots', 'foreground') ~= nil, 'the toast names the recipe')
fanfare.Clear()
config.skills[1][1] = 45.0

-- an HQ crystal still finds the recipe
advance(20)
startSynth({ 719, 850 }, 4240)
synthEffect(0)
synthResult(12987)
check(history.Latest().recipe == sabots.id, 'an HQ wind crystal still matches the recipe')

-- an interrupted synth counts as a break
advance(20)
startSynth({ 719, 850 })
synthEffect(0)
synthResult(29695, 0x0E, { 719, 850 })
check(history.Latest().result == 1 and #history.Latest().lost == 2, 'an interrupted synth is recorded as a break that lost everything')

do
-- a request with no synth effect at all gives way to the next one after 3 s
advance(20)
startSynth({ 698 })          -- ash lumber, never answered
advance(4)
startSynth({ 719, 850 })     -- ebony sabots
synthEffect(0)
synthResult(12987)
check(history.Latest().recipe == sabots.id and history.Latest().item == 12987, 'a request that never started gives way to the next one after 3 seconds')

-- a slow synth and a second request in the lag: the result names its own
-- crystal and materials, so the synth that happened is recorded
advance(20)
startSynth({ 719, 850 })      -- ebony sabots
advance(3.5)
startSynth({ 698 })           -- ash lumber, pressed while the server lagged
synthEffect(1)                -- the sabots synth breaks
basic(94, 0, 0)               -- the ash lumber request is refused
synthResult(29695, 1, { 850 }, 4098, { 719, 850 })
check(history.Latest().recipe == sabots.id and history.Latest().item == 12987, 'a result that names its materials is recorded as that recipe, whatever was pressed meanwhile')
-- the same without materials in the result: an NQ item that is not the
-- guessed recipe's drops the guess
advance(20)
startSynth({ 719, 850 })
advance(3.5)
startSynth({ 698 })
synthEffect(0)
basic(94, 0, 0)
synthResult(12987)
check(history.Latest().recipe == nil and history.Latest().item == 12987, 'without materials in the result, an NQ item that does not match the guess drops the guessed recipe')

-- a result whose request was missed still counts toward the alert
advance(90)
frame(false)
synthResult(12987)
check(watch.State() == 1, 'a result with its request missed still counts')
watch.OnZone()
check(watch.State() == 0, 'zoning forgets the run')

-- a skill change long after the last result tags no synth
advance(20)
startSynth({ 719, 850 })
synthEffect(0)
synthResult(12987)
advance(30)
basic(38, 49, 1)
check(history.Latest().skillup[1] ~= nil and history.Latest().skillup[1].change == nil, 'a skill-up long after the last result does not tag that synth')

-- a skill drop (310) is followed by 53 with the lower level (LandSandBoat
-- doSynthSkillUp): that is not a level-up
fanfare.Clear()
sounds = { }
config.skills[1][1] = 60.0
basic(310, 49, 1)
basic(53, 49, 59)
check(config.skills[1][1] == 59.9 and fanfare.Count() == 0 and #sounds == 0, 'a skill drop and the lower level after it get no level-up fanfare')
basic(38, 49, 1)
basic(53, 49, 60)
check(config.skills[1][1] == 60 and fanfare.Count() == 1, 'the next real level-up still gets its banner')
fanfare.Clear()
config.skills[1][1] = 45.0

-- short packets are skipped, never an error
local okTiny = pcall(startSynth, { 719 }, 4098, 0x08)
local okShort = pcall(startSynth, { 719, 850 }, 4098, 0x0C)
local okFull = pcall(startSynth, { 719, 850, 698, 702, 703, 704, 705, 706 }, 4098, 0x24)
local okResult = pcall(fire, 'packet_in', { id = 0x06F, data = packet(0x10, { }) })
local okBasic = pcall(fire, 'packet_in', { id = 0x029, data = packet(0x08, { }) })
local okEffect = pcall(fire, 'packet_in', { id = 0x030, data = packet(0x06, { }) })
local okSkills = pcall(fire, 'packet_in', { id = 0x062, data = packet(0x40, { }) })
check(okTiny and okShort and okFull and okResult and okBasic and okEffect and okSkills, 'short packets are skipped and a full request with 8 materials reads')
watch.OnZone()
end

-- a result that never arrives must not block the next synth
startSynth({ 719, 850 })
advance(61)
startSynth({ 698 })
synthEffect(0)
synthResult(29695)
check(history.Latest() ~= nil and history.Latest().item == 715, 'after a lost result, the next synth is tracked as ash lumber')

-- history goes to its own file when you zone, and comes back per character
fire('packet_in', zoneIn('Alpha', 4242))
local histPath = TMP .. '/config/addons/hcrafter/characters/hist_Alpha.lua'
local histText = readFile(histPath) or ''
check(histText:find('item = 715', 1, true) ~= nil and histText:find('recipe = ' .. sabots.id, 1, true) ~= nil and histText:find('before = 45', 1, true) ~= nil,
    'zoning writes the history file, with recipes and skills before')
fire('packet_in', zoneOut(true))
fire('packet_in', zoneIn('Mule1', 5151))
check(#history.List() == 0, 'another character starts with its own history')
fire('packet_in', zoneOut(true))
fire('packet_in', zoneIn('Alpha', 4242))
check(#history.List() > 1 and history.Latest().item == 715, 'Alpha\'s history comes back')
fire('packet_in', inventoryFinish)
advance(3)

local skillsBytes = { }
skillsBytes[0xE0 + 1 * 2] = { 61 * 32 + 5, 2 }               -- woodworking 61, journeyman
skillsBytes[0xE0 + 6 * 2] = { 0x8000 + 100 * 32 + 9, 2 }     -- bonecraft 100, veteran, capped
fire('packet_in', { id = 0x062, data = packet(0x100, skillsBytes) })
check(config.skills[1][1] == 61 and config.skills[6][1] == 100.3, 'skills packet: woodworking set to 61, bonecraft keeps 100.3')
check(config.ranks[1][1] == 5 and config.ranks[6][1] == 9 and config.capped[6][1] == true and config.capped[1][1] == false and app.Cap(1) == 60,
    'ranks and the capped flag come from the same packet: journeyman caps at 60')
fire('packet_in', { id = 0x062, data = packet(0x100, { }) })
check(config.skills[1][1] == 61 and config.ranks[1][1] == 5, 'an all-zero skills packet is ignored')
config.autoSkills[1] = false
skillsBytes[0xE0 + 1 * 2] = { 62 * 32 + 5, 2 }
fire('packet_in', { id = 0x062, data = packet(0x100, skillsBytes) })
check(config.skills[1][1] == 61 and config.ranks[1][1] == 5, 'with game levels off, typed levels stay')
config.autoSkills[1] = true

-- a full history saves quickly
history.Clear()
for i = 1, 500 do
    history.Add({ startTime = timeNow - i * 30, item = 715, count = 3, result = (i % 9 == 0) and 1 or ((i % 7 == 0) and 2 or 0), recipe = sabots.id,
        lost = { 698 }, skillup = { [1] = { change = 0.1, before = 40 + i / 100 } } })
end
local t0 = realClock()
history.Save()
local saveMs = (realClock() - t0) * 1000
check(#history.List() == 500 and saveMs < 50, ('a 500-synth history saves in %.1f ms'):format(saveMs))
config.book.tab[1] = 2
f, why = frame(true)
check(why == nil and hasText(f, '500 synths', 'hcrafter.book') and hasTextLike(f, 'Showing the latest 60 of 500', 'hcrafter.book') ~= nil, 'the history tab sums up and shows the latest 60')
check(hasText(f, 'Break', 'hcrafter.book') and hasText(f, 'HQ', 'hcrafter.book'), 'history rows show results')
config.book.tab[1] = 3
f, why = frame(true)
check(why == nil and hasText(f, 'Your crafts', 'hcrafter.book') and hasText(f, 'Journeyman', 'hcrafter.book') and hasTextLike(f, 'prices in config', 'hcrafter.book') ~= nil, 'the settings tab draws ranks and the prices line')
S.click = { 'book.support.seg2' }
f, why = frame(true)
check(config.support[1] == 3, 'settings: advanced support picked')
S.click = { 'book.frame.seg2' }
frame(false)
check(config.look.frame[1] == 2, 'settings: charcoal frame picked')
config.autoGear[1] = false
f, why = frame(true)
check(why == nil and hasLabel(f, 'book.gear1.plus') ~= nil, 'with detection off, gear steppers show')
config.autoGear[1] = true
config.support[1] = 1
config.look.frame[1] = 1
config.book.tab[1] = 1

---------------------------------------------------------------------------
print('== commands')
local function command(textIn)
    local e = { command = textIn, blocked = false }
    fire('command', e)
    return e.blocked
end
local bookBefore = config.book.visible[1]
check(command('/hcrafter') and config.book.visible[1] ~= bookBefore, '/hcrafter toggles the recipe book')
command('/hcraft')
check(config.book.visible[1] == bookBefore, '/hcraft works the same')
local planBefore = config.planner.visible[1]
command('/hcrafter plan')
check(config.planner.visible[1] ~= planBefore, '/hcrafter plan toggles the Resource Planner')
local listBefore = config.tracker.visible[1]
command('/hcrafter list')
check(config.tracker.visible[1] ~= listBefore, '/hcrafter list toggles the Shopping list')
command('/hcrafter list')
command('/hcrafter clear')
check(#history.List() == 0, '/hcrafter clear empties the history')
printed = { }
command('/hcrafter save')
check(#printed == 1 and printed[1]:find('Saved', 1, true), '/hcrafter save writes this character: ' .. tostring(printed[1]))
printed = { }
command('/hcrafter price ebony log 1,100')
check(prices.Get(702) == 1100 and printed[1]:find('Ebony Log: 1,100 gil each', 1, true), '/hcrafter price sets a price by name: ' .. tostring(printed[1]))
command('/hcrafter price ebony log')
check(prices.Get(702) == nil, '/hcrafter price with no number clears it')
printed = { }
command('/hcrafter price unobtainium 5')
check(printed[1]:find('No recipe uses', 1, true), 'an unknown item name is reported')
printed = { }
command('/hcrafter prices')
check(printed[1]:find('Read %d+ prices') ~= nil, '/hcrafter prices reads the file again: ' .. tostring(printed[1]))
printed = { }
command('/hcrafter help')
check(#printed >= 7, '/hcrafter help prints the commands')
check(not command('/craftbook') and not command('/xit c'), 'other commands are left alone')

---------------------------------------------------------------------------
print('== an error in the middle of a window')
do
    config.book.visible[1] = true
    config.book.tab[1] = 1
    config.tracker.visible[1] = true
    config.planner.entries = T{ T{ recipeId = sabots.id, synths = T{ 2 } } }
    local realInputText = im.InputText
    -- the search box sits inside the book's scrolling body, between four
    -- style colors and a style variable
    im.InputText = function() error('test error in the search box') end
    printed = { }
    local f1, why1 = frame(true)
    local f2, why2 = frame(true)
    im.InputText = realInputText
    local messages = 0
    for _, line in ipairs(printed) do
        if line:find('The recipe book stopped on an error', 1, true) and line:find('test error in the search box', 1, true) then
            messages = messages + 1
        end
    end
    check(why1 == nil and why2 == nil, 'a draw that stops on an error leaves imgui balanced: ' .. tostring(why1 or why2))
    check(messages == 1 and #printed == 1, ('the error is printed once, not every frame (%i lines)'):format(#printed))
    check(hasTextLike(f2, 'opens the book', 'hcrafter.tracker') ~= nil, 'the other windows still draw')
    local f3, why3 = frame(true)
    check(why3 == nil and hasText(f3, 'Recipes', 'hcrafter.book') and guard.Depth() == 0, 'the book draws again once the error is gone, and nothing is left open')
    -- a draw that ends cleanly but leaves something open
    local ui = require('hc.ui')
    local realFlush = ui.FlushTip
    ui.FlushTip = function() guard.PushStyleColor(ImGuiCol_Text, { 1, 1, 1, 1 }) realFlush() end
    printed = { }
    local _, why4 = frame(true)
    local _, why5 = frame(true)
    ui.FlushTip = realFlush
    check(why4 == nil and why5 == nil and guard.Depth() == 0 and #printed == 1 and printed[1]:find('left 1 imgui item open', 1, true) ~= nil,
        'a draw that ends with something still open gets it closed, and that prints once: ' .. tostring(printed[1]))
    config.planner.entries = T{ }
end

---------------------------------------------------------------------------
print('== character select, hiding and unload')
fire('packet_in', zoneOut(true))
G.entity = false
f, why = frame(true)
check(why == nil and #f.windows == 0, 'nothing draws at character select')
local before = readFile(charFile('Alpha'))
SetBags({ [0] = { max = 80, [4098] = 1 } })
advance(120)
frame(false)
check(readFile(charFile('Alpha')) == before, 'nothing is saved at character select')
G.entity = true
SetBags(ALPHA_BAGS)
fire('packet_in', zoneIn('Alpha', 4242))
fire('packet_in', inventoryFinish)
advance(3)
config.look.gameIcons[1] = false
f, why = frame(true)
check(why == nil and f.images == 0, 'with game icons off, nothing loads a texture')
config.look.gameIcons[1] = true
config.look.gameFont[1] = false
f, why = frame(true)
check(why == nil, 'with Tahoma off, the default font draws')
config.look.gameFont[1] = true
config.look.scale[1] = 1.5
f, why = frame(true)
check(why == nil, 'at 150 percent size, frames stay balanced')
config.look.scale[1] = 1.0
local savesBefore = settingsStub.saves
fire('unload')
check(settingsStub.saves > savesBefore, 'unload saves settings')

---------------------------------------------------------------------------
print('== textures: budget, failures, zoning')
do
    icons.Reset()
    icons.NewFrame()
    local made = textures.made
    textures.failNext = true
    local first = icons.Item(4099)
    check(first == nil, 'a texture that fails to load returns nothing, so a fallback draws')
    local loaded = 0
    for id = 4096, 4103 do
        if icons.Item(id) ~= nil then loaded = loaded + 1 end
    end
    check(loaded <= icons.perFrame, ('at most %i textures load in one frame (%i did)'):format(icons.perFrame, loaded))
    icons.NewFrame()
    check(icons.Item(4099) == nil, 'a failed texture is not retried every frame')
    local again = icons.Item(4098)
    check(again ~= nil and icons.Item(4098) == again, 'a loaded texture is reused')
    icons.Reset()
    icons.NewFrame()
    check(icons.Item(4098) ~= nil and textures.made > made, 'zoning drops textures, and they load again')
    check(icons.Emblem(6) ~= nil and icons.Emblem(9) == nil, 'guild emblems come from the imagery status icons')
end

---------------------------------------------------------------------------
print('== a font that fails to load')
do
    local chunk2 = assert(loadfile(ADDON .. '/hc/text.lua'))
    local text2 = chunk2()
    S.fontFail = true
    text2.Load()
    S.fontFail = false
    check(not text2.HasGameFont() and text2.Width('abc', 14) == 21, 'without Tahoma, text is measured with the default font')
end

---------------------------------------------------------------------------
print('== every recipe, every material open, every line hovered')
local all = setmetatable({ }, { __index = function() return true end })
st.open = all
st.expanded = all
S.hoverAll = true
for itemId in pairs(recipes.byResult) do
    config.planner.make[itemId] = 1
end
config.planner.visible[1] = true
config.book.visible[1] = true
local total, bad, biggest, firstBad = 0, 0, 0, nil
local slowest = 0
local overflowCount, firstOverflow = 0, nil
for index, recipe in ipairs(recipes.all) do
    st.filter[1] = res:GetItemById(recipe.result).Name[1]:lower()
    if index % 10 == 0 then
        config.planner.entries = T{ T{ recipeId = recipe.id, synths = T{ 3 } } }
    else
        config.planner.entries = T{ }
    end
    local t1 = realClock()
    local fr, w = frame(false)
    local ms = (realClock() - t1) * 1000
    if ms > slowest then slowest = ms end
    total = total + fr.prims
    if fr.prims > biggest then biggest = fr.prims end
    if #fr.overflow > 0 then
        overflowCount = overflowCount + #fr.overflow
        firstOverflow = firstOverflow or (recipe.id .. ': ' .. fr.overflow[1])
    end
    if w then
        bad = bad + 1
        firstBad = firstBad or (recipe.id .. ': ' .. w)
    end
end
check(bad == 0, ('%i searches drawn fully open and hovered, %i failed%s'):format(#recipes.all, bad, firstBad and (' (first: ' .. firstBad .. ')') or ''))
check(overflowCount == 0, ('no text runs past the edge of its window (%i did%s)'):format(overflowCount, firstOverflow and (', first: ' .. firstOverflow) or ''))
print(('  info  %i primitives drawn, largest frame %i, slowest frame %.1f ms in the stub'):format(total, biggest, slowest))

-- the skill-up tab for every craft at a few levels
config.planner.tab[1] = 2
config.planner.entries = T{ }
local skillBad, skillFirst = 0, nil
for craftId = 1, 8 do
    for _, level in ipairs({ 0, 9.9, 30.4, 49.9, 59.5, 75, 99.9, 100 }) do
        config.skillup.craft[1] = craftId
        config.skillup.target[1] = 0
        config.skills[craftId][1] = level
        local fr, w = frame(false)
        if w or #fr.overflow > 0 then
            skillBad = skillBad + 1
            skillFirst = skillFirst or (('craft %i at %.1f: %s'):format(craftId, level, w or ('text past the edge: ' .. fr.overflow[1])))
        end
    end
end
check(skillBad == 0, 'the skill-up tab draws for every craft from 0 to 100' .. (skillFirst and (' (first: ' .. skillFirst .. ')') or ''))
config.planner.tab[1] = 1
S.hoverAll = false
st.open = { }
st.expanded = { }
check(#S.percentText == 0, 'no percent sign in any imgui widget text' .. (#S.percentText > 0 and (': ' .. S.percentText[1]) or ''))

---------------------------------------------------------------------------
print('== window sizes and text size')
do
    local function gripRect(f, which)
        for id, r in pairs(f.rects) do
            if id:find('##hcrafter.grip.' .. which, 1, true) then return r end
        end
        return nil
    end
    -- the window's size, read from where its corner grip sits
    local function windowSize(which, pos)
        local f, why = frame(false)
        local r = gripRect(f, which)
        if r == nil then return nil, nil, why or 'no grip' end
        return r[1] + r[3] - pos[1], r[2] + r[4] - pos[2], why
    end
    -- press the grip, move the mouse, let go
    local function dragGrip(which, dx, dy, double)
        local f0 = frame(false)
        local r = gripRect(f0, which)
        assert(r ~= nil, 'no grip for ' .. which)
        local mx, my = r[1] + r[3] / 2, r[2] + r[4] / 2
        S.hover, S.active, S.mouse = 'grip.' .. which, 'grip.' .. which, { mx, my }
        S.doubleClick = double == true
        local _, why1 = frame(false)
        S.doubleClick = false
        S.mouse = { mx + dx, my + dy }
        local _, why2 = frame(false)
        S.active = nil
        local _, why3 = frame(false)
        S.hover, S.mouse = nil, nil
        return why1 or why2 or why3
    end

    config.look.text[1] = 1.0
    config.look.scale[1] = 1.0
    config.book.visible[1] = true
    config.book.tab[1] = 1
    config.planner.visible[1] = true
    config.tracker.visible[1] = true
    config.planner.entries = T{ T{ recipeId = sabots.id, synths = T{ 2 } } }

    -- settings saved by 1.0.0 have no sizes and no text size
    config.book.width, config.book.height = nil, nil
    config.planner.width, config.planner.height = nil, nil
    config.tracker.width = nil
    config.look.text = nil
    settingsStub.callbacks[1](config)
    check(config.book.width[1] == 520 and config.book.height[1] == 0 and config.planner.width[1] == 560 and config.planner.height[1] == 0
        and config.tracker.width[1] == 320 and config.look.text[1] == 1, 'settings from 1.0.0 get the default sizes and text size')

    local bookPos = config.book.pos
    -- the body fits the content it measured last frame, so let it settle
    frame(false)
    frame(false)
    local w0, h0, why0 = windowSize('book', bookPos)
    check(why0 == nil and w0 ~= nil and math.abs(w0 - 520) < 0.01, ('the book is 520 wide by default (%s)'):format(tostring(w0)))

    local why = dragGrip('book', 120, 80)
    check(why == nil and config.book.width[1] == 640 and config.book.height[1] == math.floor(h0 + 80 + 0.5),
        ('dragging the book corner sets its size: %s x %s'):format(tostring(config.book.width[1]), tostring(config.book.height[1])))
    local w1, h1 = windowSize('book', bookPos)
    check(math.abs(w1 - 640) < 0.01 and math.abs(h1 - config.book.height[1]) < 0.01, ('the book draws at the new size: %.0f x %.0f'):format(w1, h1))
    check(S.cursorShape == ImGuiMouseCursor_ResizeNWSE, 'the corner shows the resize cursor')

    local savesBefore = settingsStub.saves
    advance(6)
    frame(false)
    check(settingsStub.saves > savesBefore, 'a resize is saved')

    dragGrip('book', -5000, -5000)
    check(config.book.width[1] == 460 and config.book.height[1] == 240, 'the book stops at 460 by 240')
    dragGrip('book', 5000, 5000)
    local _, h2 = windowSize('book', bookPos)
    check(config.book.width[1] == 1400 and config.book.height[1] == 2400 and h2 <= S.display.y + 0.01,
        ('the book stops at 1400 wide and never grows past the screen (%.0f high)'):format(h2))

    config.book.width[1], config.book.height[1] = 520, 0
    dragGrip('book', 0, 0)
    check(config.book.width[1] == 520 and config.book.height[1] == 0, 'a click on the corner without a drag changes nothing')

    config.book.width[1], config.book.height[1] = 900, 500
    dragGrip('book', 60, 60, true)
    check(config.book.width[1] == 520 and config.book.height[1] == 0, 'a double-click on the corner resets the size, and that press does not drag')

    -- a drag sideways only keeps a book that fits its content fitting
    config.book.width[1], config.book.height[1] = 520, 0
    dragGrip('book', 100, 0)
    check(config.book.width[1] == 620 and config.book.height[1] == 0, ('a drag sideways changes only the width: %s x %s'):format(tostring(config.book.width[1]), tostring(config.book.height[1])))
    dragGrip('book', 0, 60)
    check(config.book.width[1] == 620 and config.book.height[1] > 0, 'a drag down changes only the height')
    config.book.width[1], config.book.height[1] = 520, 0
    dragGrip('book', 100, 10)
    check(config.book.width[1] == 620 and config.book.height[1] == 0, 'a sideways drag that drifts 10 pixels down still changes only the width')
    config.book.width[1], config.book.height[1] = 520, 0

    -- imgui reports -FLT_MAX while the mouse is unavailable: the size stays
    do
        local f0 = frame(false)
        local r = gripRect(f0, 'book')
        local mx, my = r[1] + r[3] / 2, r[2] + r[4] / 2
        S.hover, S.active, S.mouse = 'grip.book', 'grip.book', { mx, my }
        frame(false)
        S.mouse = { -3.4e38, -3.4e38 }
        frame(false)
        local held = config.book.width[1] == 520 and config.book.height[1] == 0
        S.active = nil
        frame(false)
        S.hover, S.mouse = nil, nil
        check(held and config.book.width[1] == 520 and config.book.height[1] == 0, 'a mouse that goes missing mid-drag changes nothing')
    end

    -- a quick grab again right after a drag is a new drag, not a reset
    dragGrip('book', 40, 0)
    dragGrip('book', 40, 0, true)
    check(config.book.width[1] == 600, ('a quick second grab after a drag keeps dragging: %s'):format(tostring(config.book.width[1])))
    dragGrip('book', 0, 0)
    dragGrip('book', 0, 0, true)
    check(config.book.width[1] == 520 and config.book.height[1] == 0, 'a real double-click still resets')

    -- never wider than the screen
    config.book.width[1] = 1400
    S.display = { x = 1200, y = 1080 }
    local wNarrow = windowSize('book', bookPos)
    check(wNarrow ~= nil and wNarrow <= 1200 - 8 + 0.01, ('on a 1200 wide screen the book is %.0f wide'):format(wNarrow or -1))
    S.display = { x = 1920, y = 1080 }
    config.book.width[1] = 520

    config.book.height[1] = 300
    local _, h3 = windowSize('book', bookPos)
    check(math.abs(h3 - 300) < 0.01, ('a set height draws that tall: %.0f'):format(h3))
    config.book.height[1] = 0

    local badOk = true
    for _, v in ipairs({ 'wide', -50, 0 / 0, 1 / 0, 1e12 }) do
        config.book.width[1] = v
        config.book.height[1] = v
        local w, h, whyBad = windowSize('book', bookPos)
        if whyBad ~= nil or w == nil or w < 460 - 0.01 or w > 1400 + 0.01 or h > S.display.y + 0.01 then
            badOk = false
        end
    end
    check(badOk, 'odd sizes in the settings file still draw inside the limits')
    config.book.width[1], config.book.height[1] = 520, 0

    dragGrip('plan', -60, 40)
    check(config.planner.width[1] == 500 and config.planner.height[1] > 0,
        ('the planner corner resizes it: %s x %s'):format(tostring(config.planner.width[1]), tostring(config.planner.height[1])))
    config.planner.width[1], config.planner.height[1] = 560, 0

    dragGrip('tracker', 80, 120)
    check(config.tracker.width[1] == 400 and config.tracker.height == nil,
        ('the Shopping list corner changes only its width: %s'):format(tostring(config.tracker.width[1])))
    check(S.cursorShape == ImGuiMouseCursor_ResizeEW, 'its corner shows the sideways cursor')
    config.tracker.width[1] = 320

    config.look.text[1] = 1.3
    local f, whyText = frame(true)
    local titleSize = nil
    for _, t in ipairs(f.texts) do
        if t.text == 'HCrafter' and t.list:find('hcrafter.book', 1, true) then titleSize = t.size end
    end
    check(whyText == nil and math.abs(text.scale - 1.3) < 1e-9 and titleSize ~= nil and math.abs(titleSize - 15 * 1.3) < 1e-6,
        ('at 130 percent text, the title draws at %s pixels'):format(tostring(titleSize)))
    check(math.abs(text.Width('abcd', 10) - 26) < 1e-6, 'text widths grow with the text size')
    local limitsOk = true
    for v, want in pairs({ [9] = 1.3, [0.2] = 0.8, ['big'] = 1, [1.05] = 1.05 }) do
        config.look.text[1] = v
        frame(false)
        if math.abs(text.scale - want) > 1e-9 then limitsOk = false end
    end
    config.look.text[1] = 0 / 0
    config.book.tab[1] = 3
    local fNan = frame(true)
    check(limitsOk and text.scale == 1, 'the text size stays between 80 and 130 percent')
    check(hasText(fNan, '100%', 'hcrafter.book') and not hasTextLike(fNan, 'nan', 'hcrafter.book'), 'a NaN text size in the file shows 100% in Settings')
    config.book.tab[1] = 1

    -- every view at 130 percent text with every window at its narrowest
    config.look.text[1] = 1.3
    config.book.width[1], config.planner.width[1], config.tracker.width[1] = 460, 480, 260
    st.open = all
    st.expanded = all
    S.hoverAll = true
    local bad, firstBad, views = 0, nil, 0
    local function look(label, fr, w)
        views = views + 1
        if w or #fr.overflow > 0 then
            bad = bad + 1
            firstBad = firstBad or (label .. ': ' .. (w or fr.overflow[1]))
            if os.getenv('HCRAFTER_DEBUG') then print('    ' .. label .. ': ' .. (w or table.concat(fr.overflow, ' | '))) end
        end
    end
    for index = 1, #recipes.all, 7 do
        local recipe = recipes.all[index]
        st.filter[1] = res:GetItemById(recipe.result).Name[1]:lower()
        config.planner.entries = T{ T{ recipeId = recipe.id, synths = T{ 3 } } }
        look('recipe ' .. recipe.id, frame(false))
    end
    for tab = 2, 3 do
        config.book.tab[1] = tab
        look('book tab ' .. tab, frame(false))
    end
    config.book.tab[1] = 1
    config.planner.tab[1] = 2
    for craftId = 1, 8 do
        config.skillup.craft[1] = craftId
        look('skill-up ' .. craftId, frame(false))
    end
    config.planner.tab[1] = 1
    check(bad == 0, ('at 130 percent text and the narrowest windows, %i views draw inside their windows%s'):format(views, firstBad and (' (first: ' .. firstBad .. ')') or ''))

    config.look.text[1] = 0.8
    config.book.width[1], config.planner.width[1], config.tracker.width[1] = 1400, 1400, 720
    local fr, w = frame(false)
    check(w == nil and #fr.overflow == 0, 'at 80 percent text and the widest windows, frames stay balanced')

    S.hoverAll = false
    st.open = { }
    st.expanded = { }
    config.look.text[1] = 1.0
    config.book.width[1], config.planner.width[1], config.tracker.width[1] = 520, 560, 320
    config.planner.entries = T{ }
end

---------------------------------------------------------------------------
print("== Ashita's font, level boxes, sounds, labels, Sonic Belt and the cap")
-- a function of its own, so its locals don't count toward the main chunk's
-- limit of 200
;(function()
    local ui = require('hc.ui')
    local tracker = require('hc.tracker')
    config.look.text[1] = 1.0
    config.look.scale[1] = 1.0
    config.book.visible[1] = true
    config.book.tab[1] = 1
    config.book.width[1], config.book.height[1] = 520, 0
    printed = { }

    -- 1.1.0 settings get the new keys
    config.look.matchAshita = nil
    config.ready.every = nil
    config.sounds = nil
    settingsStub.callbacks[1](config)
    check(config.look.matchAshita[1] == true and config.ready.every[1] == 6 and config.sounds.done[1] == 'game:se008/se008229'
        and config.sounds.short[1] == 'game:se035/se035131' and config.sounds.skillUp[1] == 'game:se044/se044177' and config.sounds.breaks[1] == ''
        and config.soundVolume[1] == 100, 'settings from 1.1.0 get the font switch, the alert count, the game\'s sounds and the volume')

    -- Ashita's font size sets the scale
    frame(false)
    check(ui.S == 1, "with Ashita 4.3's default 18 pixel font, HCrafter draws at 100%")
    S.lineH = 28
    frame(false)
    check(math.abs(ui.S - 1.55) < 1e-9, ('with a 28 pixel Ashita font, HCrafter draws at 155%% (%s)'):format(tostring(ui.S)))
    S.lineH = 36
    local f, why = frame(true)
    local titleSize = nil
    for _, t in ipairs(f.texts) do
        if t.text == 'HCrafter' and t.list:find('hcrafter.book', 1, true) then titleSize = t.size end
    end
    check(why == nil and ui.S == 2 and titleSize ~= nil and math.abs(titleSize - 30) < 1e-6, ('with a 36 pixel Ashita font, twice the default, HCrafter draws at 200%% (title %s px)'):format(tostring(titleSize)))
    config.look.scale[1] = 1.5
    frame(false)
    check(math.abs(ui.S - 3) < 1e-9, 'Size multiplies it: 150% of 200% is 300%')
    config.look.scale[1] = 1.0
    config.look.matchAshita[1] = false
    frame(false)
    check(ui.S == 1, 'with the switch off, Size alone sets the scale')
    config.look.matchAshita[1] = true
    S.lineH = 7
    frame(false)
    local low = ui.S
    S.lineH = 140
    frame(false)
    check(low == 0.75 and ui.S == 3, 'the font scale stays between 75 and 300 percent')

    -- the level boxes fit Ashita's font, even with the switch off
    S.lineH = 28
    config.look.matchAshita[1] = false
    config.book.tab[1] = 3
    config.skills[1][1] = 100.0
    S.record = true
    f, why = frame(true)
    S.record = false
    local boxes = { }
    for _, input in ipairs(f.inputs) do
        if input.list:find('hcrafter.book', 1, true) and input.text:find('%.%d$') then boxes[#boxes + 1] = input end
    end
    local need = 14 * #'100.0' + 2 * 34 + 2 * 4 + 2 * 4 + 4
    local rowsOk = #boxes == 8
    for i = 2, #boxes do
        if boxes[i].y - boxes[i - 1].y < 34 + 4 - 0.01 then rowsOk = false end
    end
    check(why == nil and #boxes == 8 and boxes[1].w >= need - 0.01 and rowsOk,
        ('with a 28 pixel font the level boxes are %s wide (need %i) and %s apart'):format(tostring(boxes[1] and boxes[1].w), need, tostring(boxes[2] and (boxes[2].y - boxes[1].y))))
    check(hasTextLike(f, "Ashita's font is 28 px", 'hcrafter.book') ~= nil, 'Settings says how big Ashita\'s font is')
    config.look.matchAshita[1] = true
    S.lineH = nil
    config.skills[1][1] = 45.0

    -- the sound for each alert
    sounds = { }
    f, why = frame(true)
    check(why == nil and hasText(f, 'Synths done', 'hcrafter.book') and hasTextLike(f, 'FFXI synths done (missing)', 'hcrafter.book') ~= nil
        and hasTextLike(f, 'FFXI level-up (missing)', 'hcrafter.book') ~= nil and hasTextLike(f, 'find your game', 'hcrafter.book') ~= nil,
        'Settings lists each alert with its sound, marks the game\'s sounds missing with no game folder, and says why')
    config.sounds.done[1] = 'ready.wav'
    config.sounds.short[1] = 'alert.wav'
    S.click = { 'book.sound.done' }
    frame(false)
    f, why = frame(true)
    check(why == nil and #f.popupShown == 1 and hasLabel(f, 'Three chimes##hcrafter.sound') ~= nil and hasLabel(f, 'Chime  (now)##hcrafter.sound') ~= nil,
        'clicking a sound opens the list, with the current one marked')
    S.select = 'Three chimes##'
    frame(false)
    check(config.sounds.done[1] == 'chimes.wav' and #sounds == 1 and sounds[1]:find('chimes.wav', 1, true), 'picking a sound sets it and plays it')
    S.click = { 'book.soundplay.short' }
    frame(false)
    check(#sounds == 2 and sounds[2]:find('alert.wav', 1, true), 'Play plays the picked sound')
    config.sounds.done[1] = 'ready.wav'

    -- your own sounds from the sounds folder, and odd names left out
    local realList = ashita.fs.get_directory
    ashita.fs.get_directory = function(path, filter)
        assert(type(path) == 'string' and path:find('sounds', 1, true) and filter == '.*', 'sound folder listing')
        return { 'ready.wav', 'My Bell.wav', 'Loud.WAV', '..\\evil.wav', 'bad%sound.wav', 'notes.txt', 'x#y.wav' }
    end
    local soundsMod = require('hc.sounds')
    soundsMod.Refresh()
    ashita.fs.get_directory = realList
    local labels = { }
    for _, option in ipairs(soundsMod.Options()) do labels[#labels + 1] = option.label end
    local list = table.concat(labels, '|')
    check(list:find('My Bell', 1, true) ~= nil and list:find('Loud', 1, true) ~= nil and not list:find('evil', 1, true) and not list:find('bad', 1, true)
        and not list:find('notes', 1, true) and not list:find('x#y', 1, true) and labels[1] == 'None', 'your own .wav files show up, in any case, and odd names are left out: ' .. list)
    sounds = { }
    check(not soundsMod.Play('..\\evil.wav') and not soundsMod.Play('C:\\x.wav') and #sounds == 0, 'a sound with a folder in its name never plays')
    soundsMod.custom = { }

    -- the new sounds are there and are real .wav files
    local wavOk = true
    for _, sound in ipairs(soundsMod.builtIn) do
        local file = io.open(ADDON .. '/sounds/' .. sound.file, 'rb')
        local head = file and file:read(12) or ''
        if file then file:close() end
        if head:sub(1, 4) ~= 'RIFF' or head:sub(9, 12) ~= 'WAVE' then wavOk = false end
    end
    check(wavOk and #soundsMod.builtIn == 10, 'all ten of HCrafter\'s sounds are in the sounds folder')

    -- the right-click menu uses the game font at HCrafter's text size
    config.book.tab[1] = 1
    frame(false)
    S.lastFontSize = nil
    require('hc.menu').Request('book', { itemId = 12987, recipes = { sabots } })
    frame(false)
    f, why = frame(true)
    check(why == nil and #f.popupShown == 1 and S.lastFontSize == 14, ('the right-click menu pushes the game font at 14 pixels, the size of recipe names (%s)'):format(tostring(S.lastFontSize)))
    S.lastFontSize = nil
    S.lineH = 36
    f, why = frame(true)
    check(why == nil and S.lastFontSize == 28, ('with a 36 pixel Ashita font it pushes it at 28 (%s)'):format(tostring(S.lastFontSize)))
    -- older imgui (Ashita 4.16) draws a font at its loaded size: the menu's
    -- text is scaled instead
    local textMod = require('hc.text')
    textMod.dynamic = false
    S.lastFontSize, S.windowFontScale = nil, nil
    f, why = frame(true)
    check(why == nil and S.lastFontSize == nil and S.windowFontScale ~= nil and math.abs(S.windowFontScale - 28 / textMod.bakeSize) < 0.001,
        ('on older imgui the menu pushes the game font and scales it to 28 pixels (%s)'):format(tostring(S.windowFontScale)))
    textMod.dynamic = nil
    S.lineH = nil
    S.openPopups = { }
    frame(false)

    -- the skill-up labels
    check(skillup.bandNames.optimal == 'Optimal' and skillup.bandNames.costly == 'Manageable' and skillup.bandNames.danger == 'Risky', 'the skill-up labels are Optimal, Manageable and Risky')
    config.planner.visible[1] = true
    config.planner.tab[1] = 2
    config.skillup.craft[1] = 1
    config.ranks[1][1] = 5
    config.skills[1][1] = 45.0
    f, why = frame(true)
    check(why == nil and hasTextLike(f, 'Manageable', 'hcrafter.planner') ~= nil and hasTextLike(f, 'Risky', 'hcrafter.planner') ~= nil
        and hasTextLike(f, 'Costly', 'hcrafter.planner') == nil, 'the Skill-up tab uses the new labels')

    -- at HorizonXI's cap of 100 the Skill-up tab says nothing about ranking up
    config.ranks[1][1] = 9
    config.skills[1][1] = 100.0
    f, why = frame(true)
    check(why == nil and hasTextLike(f, 'Rank up', 'hcrafter.planner') == nil and hasTextLike(f, 'Woodworking 100.0', 'hcrafter.planner') ~= nil,
        'at 100 there is no rank-up message')
    config.ranks[1][1] = 5
    config.skills[1][1] = 60.0
    f, why = frame(true)
    check(hasTextLike(f, 'Rank up at your guild', 'hcrafter.planner') ~= nil, 'at a lower rank cap the rank-up message stays')
    config.planner.tab[1] = 1
    config.planner.visible[1] = false
    config.skills[1][1] = 45.0
    config.ranks[1][1] = 4

    -- Sonic Belt needs Leathercraft 107 on HorizonXI
    local belt = recipes.byId[44032]
    check(belt ~= nil and belt.result == 13249 and belt.skills[5] == 107 and recipes.MaxSkill(belt) == 107, 'Sonic Belt needs Leathercraft 107')
    local ctx = {
        skill = function(c) return c == 5 and 100 or 0 end,
        gear = function(c) return c == 5 and 3 or 0 end,
        support = function(c) return c == 5 and 3 or 0 end,
    }
    local est = hq.Estimate(belt, ctx)
    check(est ~= nil and est.margin == -1 and est.underCap and est.success == 85, ('at Leathercraft 100 with +3 gear and +3 support it is 1 under: %s percent'):format(tostring(est and est.success)))
    ctx.support = function() return 0 end
    est = hq.Estimate(belt, ctx)
    check(est.margin == -4 and est.success == 55, 'without support, 4 under: 55 percent')

    -- the Shopping list's "and N more" line stays inside it
    config.tracker.visible[1] = true
    config.tracker.width[1] = 260
    config.look.text[1] = 1.3
    local entries = T{ }
    for _, recipe in ipairs(recipes.all) do
        if #recipe.ingredients >= 6 and #entries < 3 then entries[#entries + 1] = T{ recipeId = recipe.id, synths = T{ 1 } } end
    end
    config.planner.entries = entries
    SetBags({ })
    stock.Refresh(true)
    f, why = frame(true)
    local right = config.tracker.pos[1] + ui.WindowWidth(config.tracker, tracker.limits)
    local outside = nil
    for _, t in ipairs(f.texts) do
        if t.list:find('hcrafter.tracker', 1, true) and t.x + 0.5 * (t.size or 14) * #t.text > right + 2 then outside = t.text end
    end
    check(why == nil and hasTextLike(f, 'more', 'hcrafter.tracker') ~= nil and outside == nil, 'at 260 wide and 130 percent text, no Shopping list line runs past its edge: ' .. tostring(outside))
    config.planner.entries = T{ }
    config.tracker.width[1] = 320
    config.look.text[1] = 1.0
    config.book.tab[1] = 1

    -- the Resource Planner opens beside the book the first time
    config.planner.pos[1], config.planner.pos[2] = -1, -1
    config.planner.visible[1] = true
    config.book.pos[1], config.book.pos[2] = 100, 120
    frame(false)
    check(config.planner.pos[1] == 100 + 520 + 16 and config.planner.pos[2] == 120, ('the planner first opens beside the book, at %s, %s'):format(tostring(config.planner.pos[1]), tostring(config.planner.pos[2])))
    S.lineH = 36
    config.planner.pos[1], config.planner.pos[2] = -1, -1
    frame(false)
    check(config.planner.pos[1] + 1120 <= S.display.x, 'with a big Ashita font it still opens on the screen')
    S.lineH = nil
    config.planner.visible[1] = false

    -- every view with a 36 pixel Ashita font, 130 percent text and every
    -- window at its narrowest, on a 4K screen
    S.display = { x = 3840, y = 2160 }
    S.lineH = 36
    config.look.text[1] = 1.3
    config.book.width[1], config.planner.width[1], config.tracker.width[1] = 460, 480, 260
    config.book.visible[1], config.planner.visible[1], config.tracker.visible[1] = true, true, true
    config.planner.entries = T{ T{ recipeId = sabots.id, synths = T{ 2 } } }
    local bad4k, first4k, views4k = 0, nil, 0
    for _, view in ipairs({ { 1, 1 }, { 2, 1 }, { 3, 1 }, { 1, 2 } }) do
        config.book.tab[1], config.planner.tab[1] = view[1], view[2]
        for _, match in ipairs({ true, false }) do
            config.look.matchAshita[1] = match
            local fr, w = frame(false)
            views4k = views4k + 1
            if w or #fr.overflow > 0 then
                bad4k = bad4k + 1
                first4k = first4k or (w or fr.overflow[1])
            end
        end
    end
    check(bad4k == 0, ('with a 36 pixel Ashita font at 130 percent text, %i views draw inside their windows%s'):format(views4k, first4k and (' (first: ' .. first4k .. ')') or ''))
    S.display = { x = 1920, y = 1080 }
    S.lineH = nil
    config.look.matchAshita[1] = true
    config.look.text[1] = 1.0
    config.book.width[1], config.planner.width[1], config.tracker.width[1] = 520, 560, 320
    config.book.tab[1], config.planner.tab[1] = 1, 1
    config.planner.visible[1] = false
    config.planner.entries = T{ }

    -- a picked sound that is gone plays nothing, not Windows' own sound,
    -- and Settings says it is missing
    local soundsMod2 = require('hc.sounds')
    soundsMod2.Refresh()
    sounds = { }
    config.sounds.done[1] = 'gone.wav'
    check(not soundsMod2.Exists('gone.wav') and soundsMod2.Exists('ready.wav') and soundsMod2.Exists('alert.wav'), 'HCrafter knows which sounds are in the folder')
    fanfare.SynthsDone(6)
    check(#sounds == 0, 'a missing sound plays nothing')
    config.book.tab[1] = 3
    f, why = frame(true)
    check(why == nil and hasTextLike(f, 'gone (missing)', 'hcrafter.book') ~= nil, 'Settings marks a missing sound')
    -- a number where a sound name belongs
    config.sounds.done[1] = 5
    config.sounds.hq[1] = { }
    printed = { }
    f, why = frame(true)
    fanfare.SynthsDone(6)
    check(why == nil and #printed == 0 and #sounds == 0 and hasText(f, 'Out of a material', 'hcrafter.book'), 'odd values for a sound draw as None and play nothing')
    config.sounds.done[1] = 'ready.wav'
    config.sounds.hq[1] = 'hq.wav'
    config.book.tab[1] = 1
    fanfare.Clear()

    -- 1.2.0 played break.wav on breaks by default: 1.2.1 turns that off once
    config.version = 1
    config.sounds.breaks[1] = 'break.wav'
    settingsStub.callbacks[1](config)
    check(config.version == 3 and config.sounds.breaks[1] == '', 'settings from 1.2.0 stop playing a sound on breaks')
    config.sounds.breaks[1] = 'break.wav'
    settingsStub.callbacks[1](config)
    check(config.sounds.breaks[1] == 'break.wav', 'a break sound picked after that stays')
    config.sounds.breaks[1] = ''

    -- a 1.1.0 player who had the ready cue's sound off keeps the alert quiet
    config.sounds = nil
    config.ready.sound = T{ false }
    settingsStub.callbacks[1](config)
    check(config.sounds.done[1] == '' and config.sounds.levelUp[1] == 'game:se043/se043006', 'the old "with a sound" off becomes None for the alert')
    config.sounds.done[1] = 'ready.wav'
    config.ready.sound = nil

    -- two toasts at once both show
    fanfare.Clear()
    fanfare.NoMoreSkillups(1, 50, 12987)
    fanfare.SynthsDone(6)
    f, why = frame(true)
    local _, toastCount = fanfare.Count()
    check(toastCount == 2 and hasTextLike(f, 'no more skill-ups', 'foreground') ~= nil and hasText(f, 'Macro done: 6 synths', 'foreground'), 'two toasts at once both show')
    fanfare.Clear()

    -- a window far to the right is no wider than the room left of the edge
    S.display = { x = 3840, y = 2160 }
    config.book.width[1] = 1400
    config.book.pos[1] = 3000
    check(math.abs(ui.WindowWidth(config.book, book.limits) - (3840 - 3000 - 8)) < 0.01, 'a wide book near the right edge narrows to the room left')
    config.book.pos[1] = 100
    check(ui.WindowWidth(config.book, book.limits) == 1400, 'with room, it keeps its width')
    config.book.width[1] = 520
    S.display = { x = 1920, y = 1080 }

    -- the Shopping list stays on a 1080 screen with a long plan at 130 percent
    config.look.text[1] = 1.3
    config.look.scale[1] = 1.3
    config.tracker.visible[1] = true
    config.tracker.pos[1], config.tracker.pos[2] = 1500, 216
    local long = T{ }
    for _, recipe in ipairs(recipes.all) do
        if #recipe.ingredients >= 5 and #long < 6 then long[#long + 1] = T{ recipeId = recipe.id, synths = T{ 2 } } end
    end
    config.planner.entries = long
    SetBags({ })
    stock.Refresh(true)
    f, why = frame(true)
    local lowest = 0
    for _, t in ipairs(f.texts) do
        if t.list:find('hcrafter.tracker', 1, true) then lowest = math.max(lowest, t.y + (t.size or 14)) end
    end
    check(why == nil and lowest > 0 and lowest <= S.display.y, ('a long Shopping list stays on the screen (lowest text at %.0f)'):format(lowest))
    config.planner.entries = T{ }
    config.look.text[1] = 1.0
    config.look.scale[1] = 1.0

    check(#printed == 0, 'no window stopped on an error: ' .. tostring(printed[1]))
end)()

---------------------------------------------------------------------------
print("== the game's own sounds")
;(function()
    local spw = require('hc.spw')
    local wave = require('hc.wave')
    local soundsMod = require('hc.sounds')
    local fanfareMod = require('hc.fanfare')
    -- SeWave files built the same way as the reference files vgmstream
    -- decoded: the hashes below are vgmstream's output for these bytes
    local FILTERS = { 0, 1, 2, 3, 4, 6, 7 }
    local function U32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
    local function MakeSpw(codec, ch, count, blockAlign, sizeOff)
        local payload = { }
        if codec == 0 then
            for fr = 0, count - 1 do
                for c = 0, ch - 1 do
                    payload[#payload + 1] = string.char(FILTERS[(fr + c) % 7 + 1] * 16 + (fr * 3 + c) % 16)
                    for j = 0, blockAlign / 2 - 1 do
                        payload[#payload + 1] = string.char((fr * 29 + c * 101 + j * 7 + 3) % 256)
                    end
                end
            end
        else
            for smp = 0, count - 1 do
                for c = 0, ch - 1 do
                    local v = ((smp * 37 + c * 1000) % 2000 - 1000) * 13
                    if v < 0 then v = v + 65536 end
                    payload[#payload + 1] = string.char(v % 256, math.floor(v / 256))
                end
            end
        end
        local body = table.concat(payload)
        local size = 0x30 + #body + (sizeOff or 0)
        return 'SeWave\0\0' .. U32(size) .. U32(codec) .. U32(7) .. U32(count) .. U32(0) .. U32(40000) .. U32(8000) .. U32(0x30)
            .. '\0\0' .. string.char(ch, codec == 1 and 1 or 16, blockAlign) .. '\0\0\0' .. body
    end
    local function Hash(sound)
        local acc = 0
        for i = 1, sound.samples do
            for c = 1, sound.channels do
                acc = (acc * 31 + (sound[c][i] + 32768)) % 2147483647
            end
        end
        return acc
    end

    -- the decoder
    for _, case in ipairs({
        { 'PS-ADPCM mono', 0, 1, 40, 16, 640, 1686257036 },
        { 'PS-ADPCM stereo', 0, 2, 40, 16, 640, 1960583072 },
        { 'PCM mono', 1, 1, 300, 1, 300, 2069657294 },
        { 'PCM stereo', 1, 2, 300, 1, 300, 1983374577 },
    }) do
        local sound, why = spw.Decode(MakeSpw(case[2], case[3], case[4], case[5]))
        check(sound ~= nil and sound.rate == 48000 and sound.channels == case[3] and sound.samples == case[6] and Hash(sound) == case[7],
            ('%s decodes sample for sample as vgmstream does (%s)'):format(case[1], tostring(why or Hash(sound))))
    end
    local adpcm = MakeSpw(0, 2, 40, 16)
    local atrac = adpcm:sub(1, 12) .. U32(3) .. adpcm:sub(17)
    local damaged = MakeSpw(0, 2, 40, 16, 4)
    check(spw.Decode(atrac) == nil and spw.Decode(damaged) == nil, 'an ATRAC3 file and a file whose size disagrees with its header are left alone')
    check(spw.Decode('SeWave') == nil and spw.Decode(nil) == nil and spw.Decode(('x'):rep(100)) == nil and spw.Decode(adpcm:sub(1, 200)) == nil,
        'junk and a cut-off file are left alone')
    check(spw.Decode(MakeSpw(1, 1, 480001, 1)) == nil and spw.Decode(MakeSpw(1, 1, 480000, 1)) ~= nil, 'a sound longer than 10 seconds is left alone')

    -- .wav files
    local pcm = spw.Decode(MakeSpw(1, 2, 300, 1))
    local w1 = wave.Write(pcm, 1)
    local back = wave.Read(w1)
    check(#w1 == 44 + 300 * 2 * 2 and back ~= nil and back.rate == 48000 and back.channels == 2 and Hash(back) == 1983374577,
        'a .wav file written and read back keeps every sample')
    local half, loud = wave.Read(wave.Write(pcm, 0.5)), wave.Read(wave.Write(pcm, 3))
    local loudMin, loudMax = 0, 0
    for i = 1, loud.samples do
        loudMin, loudMax = math.min(loudMin, loud[1][i]), math.max(loudMax, loud[1][i])
    end
    check(half[1][1] == -6500 and half[2][2] == 241 and loud[1][1] == -32768 and loudMax == 32767 and loudMin == -32768 and loud[1][300] == 2457,
        'volume scales every sample and keeps loud ones in range: ' .. tostring(half[1][1]) .. ' ' .. tostring(loudMax))
    local eightBit = w1:sub(1, 34) .. string.char(8, 0) .. w1:sub(37)
    check(wave.Read(eightBit) == nil and wave.Read('RIFF') == nil and wave.Read(nil) == nil, 'a .wav file that isn\'t 16-bit PCM is left alone')

    -- no game folder: HCrafter's own sounds stand in
    local seRoot = TMP .. '/SquareEnix/FINAL FANTASY XI/sound/win/se'
    local cache = TMP .. '/config/addons/hcrafter/sounds'
    local function Put(id, data)
        os.execute('mkdir -p ' .. quote(seRoot .. '/' .. id:match('^(se%d+)/')))
        local file = realOpen(seRoot .. '/' .. id .. '.spw', 'wb')
        file:write(data)
        file:close()
    end
    local function ReadFile(path)
        local file = realOpen(path, 'rb')
        if file == nil then return nil end
        local data = file:read('*a')
        file:close()
        return data
    end
    soundsMod.Refresh()
    local gameListed = false
    for _, option in ipairs(soundsMod.Options()) do
        if option.group == 'game' then gameListed = true end
    end
    check(soundsMod.GameFolder() == nil and not gameListed, 'with no game folder, the lists leave the game\'s sounds out')
    sounds = { }
    config.fanfare.sound[1] = true
    config.soundVolume[1] = 100
    config.sounds.levelUp[1] = 'game:se043/se043006'
    check(fanfareMod.Sound('levelUp') and #sounds == 1 and sounds[1]:find('levelup.wav', 1, true) ~= nil,
        'a game sound with no game folder plays HCrafter\'s own level-up sound instead')

    -- the game folder where HorizonXI puts the game
    for _, sound in ipairs(soundsMod.game) do
        if sound.id == 'se000/se000026' then
            Put(sound.id, atrac)
        elseif sound.id == 'se000/se000027' then
            Put(sound.id, damaged)
        else
            Put(sound.id, adpcm)
        end
    end
    soundsMod.Refresh()
    local folder = soundsMod.GameFolder()
    check(folder ~= nil and folder:find('SquareEnix\\FINAL FANTASY XI\\sound\\win\\se\\', 1, true) ~= nil, 'the game\'s sound folder is found inside Ashita\'s folder: ' .. tostring(folder))
    local options = soundsMod.Options()
    local extra = nil
    for _, option in ipairs(options) do
        if option.file == 'game:se000/se000026' then extra = option.label end
    end
    check(options[1].label == 'None' and options[2].file == 'game:se043/se043006' and options[2].label == 'FFXI level-up'
        and options[9].label == 'FFXI out of a material' and extra == 'FFXI 000-026' and options[#soundsMod.game + 2].file == 'ready.wav',
        'the lists show None, the game\'s sounds by name, then HCrafter\'s')

    -- playing one makes a .wav file once
    sounds = { }
    check(fanfareMod.Sound('levelUp') and #sounds == 1 and sounds[1]:find('se043006-v100.wav', 1, true) ~= nil, 'a game sound plays from a .wav file HCrafter made')
    local made = wave.Read(ReadFile(cache .. '/se043006-v100.wav'))
    check(made ~= nil and Hash(made) == 1960583072, 'the file holds the game\'s sound sample for sample')
    os.remove(seRoot .. '/se043/se043006.spw')
    soundsMod.Refresh()
    check(not soundsMod.Exists('game:se043/se043006'), 'a game file that is gone counts as missing')
    Put('se043/se043006', adpcm)
    soundsMod.Refresh()
    local before = ReadFile(cache .. '/se043006-v100.wav')
    local file = realOpen(cache .. '/se043006-v100.wav', 'ab')
    file:write('X')
    file:close()
    sounds = { }
    fanfareMod.Sound('levelUp')
    check(#sounds == 1 and ReadFile(cache .. '/se043006-v100.wav') == before .. 'X', 'the next time it plays the file already made')

    -- volume
    config.soundVolume[1] = 50
    sounds = { }
    fanfareMod.Sound('levelUp')
    local quiet = wave.Read(ReadFile(cache .. '/se043006-v50.wav'))
    check(#sounds == 1 and sounds[1]:find('se043006-v50.wav', 1, true) ~= nil and quiet ~= nil and quiet[1][1] == math.floor(made[1][1] * 0.5 + 0.5),
        'at volume 50 it plays a copy at half the level')
    config.sounds.done[1] = 'ready.wav'
    sounds = { }
    fanfareMod.Sound('done')
    local ownQuiet = wave.Read(ReadFile(cache .. '/own-ready-v50.wav'))
    check(#sounds == 1 and sounds[1]:find('own-ready-v50.wav', 1, true) ~= nil and ownQuiet ~= nil, 'HCrafter\'s own sounds follow the volume too')
    config.soundVolume[1] = 0
    sounds = { }
    fanfareMod.Sound('levelUp')
    fanfareMod.Sound('done')
    check(#sounds == 0, 'at volume 0 nothing plays')
    check(soundsMod.Volume('x') == 100 and soundsMod.Volume(999) == 150 and soundsMod.Volume(-5) == 0 and soundsMod.Volume(0 / 0) == 100 and soundsMod.Volume(54.6) == 55,
        'odd volume values are kept between 0 and 150')
    config.soundVolume[1] = 100

    -- a game sound HCrafter can't read plays HCrafter's own instead
    config.sounds.hq[1] = 'game:se000/se000026'
    config.sounds.hqBig[1] = 'game:se000/se000027'
    sounds = { }
    fanfareMod.Sound('hq')
    fanfareMod.Sound('hqBig')
    check(#sounds == 2 and sounds[1]:find('hq.wav', 1, true) ~= nil and sounds[2]:find('hq_big.wav', 1, true) ~= nil
        and soundsMod.Unreadable('game:se000/se000026') and soundsMod.Unreadable('game:se000/se000027'),
        'an ATRAC3 or damaged game file plays HCrafter\'s own sound and is marked unreadable')
    config.book.tab[1] = 3
    f, why = frame(true)
    check(why == nil and hasTextLike(f, "FFXI 000-026 (can't read)", 'hcrafter.book') ~= nil and hasTextLike(f, 'Sounds marked FFXI', 'hcrafter.book') ~= nil,
        'Settings marks the unreadable one and says where the game\'s sounds come from')

    -- settings names that are not game sounds
    sounds = { }
    check(not soundsMod.Play('game:../evil') and not soundsMod.Play('game:se043/se043006/../x') and not soundsMod.Play('game:se0430/se043006')
        and soundsMod.GameId('game:se043/se043006') == 'se043/se043006' and #sounds == 0, 'only the exact game sound shape plays, so a setting can\'t name a path')

    -- the Settings controls
    S.click = { 'book.volume.minus' }
    frame(false)
    check(config.soundVolume[1] == 90, 'the volume steps down by 10: ' .. tostring(config.soundVolume[1]))
    S.click = { 'book.volume.plus' }
    frame(false)
    config.sounds.hq[1] = 'game:se041/se041147'
    config.sounds.hqBig[1] = 'game:se037/se037067'
    S.click = { 'book.sound.levelUp' }
    frame(false)
    f, why = frame(true)
    local headers = table.concat(f.widgetTexts, '|')
    check(why == nil and headers:find('FFXI sounds', 1, true) ~= nil and headers:find('HCrafter\'s sounds', 1, true) ~= nil
        and hasLabel(f, 'FFXI level-up  (now)##hcrafter.sound') ~= nil, 'the list groups the game\'s sounds and HCrafter\'s, with the current one marked')
    sounds = { }
    S.select = 'FFXI skill-up##'
    frame(false)
    check(config.sounds.levelUp[1] == 'game:se044/se044177' and #sounds == 1 and sounds[1]:find('se044177-v100.wav', 1, true) ~= nil,
        'picking a game sound sets it and plays it')
    config.sounds.levelUp[1] = 'game:se043/se043006'
    frame(false)

    -- ready ahead of time, one file a frame
    os.execute('rm -rf ' .. quote(cache))
    soundsMod.Refresh()
    while soundsMod.Tick() do end
    os.execute('rm -rf ' .. quote(cache))
    soundsMod.Warm('game:se008/se008229', 100)
    soundsMod.Warm('game:se035/se035131', 100)
    soundsMod.Warm('ready.wav', 100)
    check(soundsMod.Waiting() == 2, 'only game sounds and sounds at another volume wait to be made')
    frame(false)
    check(soundsMod.Waiting() == 1 and ReadFile(cache .. '/se008229-v100.wav') ~= nil and ReadFile(cache .. '/se035131-v100.wav') == nil,
        'each frame makes one file')
    frame(false)
    check(soundsMod.Waiting() == 0 and ReadFile(cache .. '/se035131-v100.wav') ~= nil, 'and the next frame the next one')

    -- settings saved by 1.2.1
    config.version = 2
    config.sounds.levelUp[1] = 'levelup.wav'
    config.sounds.skillUp[1] = ''
    config.sounds.done[1] = 'chimes.wav'
    settingsStub.callbacks[1](config)
    check(config.version == 3 and config.sounds.levelUp[1] == 'game:se043/se043006' and config.sounds.skillUp[1] == 'game:se044/se044177'
        and config.sounds.done[1] == 'chimes.wav' and config.sounds.breaks[1] == '',
        'settings from 1.2.1 move sounds still at their old default to the game\'s, keep a sound you picked, and leave breaks quiet')
    settingsStub.callbacks[1](config)
    check(config.sounds.done[1] == 'chimes.wav', 'the move happens once')

    -- startup and shutdown: optional, None by default
    check(config.sounds.startup[1] == '' and config.sounds.shutdown[1] == '', 'startup and shutdown play nothing by default')
    config.sounds.startup[1] = 'chimes.wav'
    config.sounds.shutdown[1] = 'dingdong.wav'
    frame(false)
    sounds = { }
    -- Ashita's settings library may switch to its default settings before
    -- HCrafter hears of the logout: the character's own choice still plays
    config.sounds.shutdown[1] = ''
    fire('packet_in', zoneOut(true))
    check(#sounds == 1 and sounds[1]:find('dingdong.wav', 1, true) ~= nil, 'logging out plays the shutdown sound from your own settings')
    config.sounds.shutdown[1] = 'dingdong.wav'
    G.entity = false
    frame(false)
    G.entity = true
    sounds = { }
    fire('packet_in', zoneIn('Alpha', 4242))
    check(#sounds == 0, 'the startup sound waits for the frame after the login')
    frame(false)
    check(#sounds == 1 and sounds[1]:find('chimes.wav', 1, true) ~= nil, 'the first frame after you log in plays the startup sound, without waiting for your bags')
    fire('packet_in', inventoryFinish)
    advance(3)
    frame(false)
    fire('packet_in', zoneIn('Alpha', 4242))
    fire('packet_in', inventoryFinish)
    advance(3)
    frame(false)
    check(#sounds == 1, 'it plays once, not again when you zone')
    sounds = { }
    fire('load')
    frame(false)
    check(#sounds == 1 and sounds[1]:find('chimes.wav', 1, true) ~= nil, 'loading HCrafter while you\'re in game plays the startup sound at once, and once')
    sounds = { }
    config.book.visible[1] = false
    command('/hcrafter')
    check(config.book.visible[1] == true and #sounds == 1 and sounds[1]:find('chimes.wav', 1, true) ~= nil, '/hcrafter showing the book plays the startup sound')
    command('/hcrafter')
    check(config.book.visible[1] == false and #sounds == 1, 'hiding it plays nothing')
    command('/hcrafter')
    sounds = { }
    fire('unload')
    check(#sounds == 1 and sounds[1]:find('dingdong.wav', 1, true) ~= nil, 'unloading HCrafter while logged in plays the shutdown sound')
    config.sounds.startup[1] = ''
    config.sounds.shutdown[1] = ''
    frame(false)
    sounds = { }
    fire('packet_in', zoneOut(true))
    G.entity = false
    frame(false)
    G.entity = true
    fire('packet_in', zoneIn('Alpha', 4242))
    fire('packet_in', inventoryFinish)
    advance(3)
    frame(false)
    check(#sounds == 0, 'with None picked, logging out and in plays nothing')

    -- back to no game folder for the checks that follow
    os.execute('rm -rf ' .. quote(TMP .. '/SquareEnix'))
    os.execute('rm -rf ' .. quote(cache))
    soundsMod.Refresh()
    config.sounds.done[1] = 'game:se008/se008229'
    config.book.tab[1] = 1
    fanfare.Clear()
    frame(false)
end)()

print('== planner against a brute-force check, every recipe, everything made')
local function makeAll(id)
    local options = recipes.Options(id)
    return options and options[1] or nil
end
local function bruteForce(entries, choose, have, spare)
    local synths = { }
    local function compute()
        local gross = { }
        for _, entry in ipairs(entries) do
            local n = planner.WithSpare(entry.synths, spare)
            for _, ing in ipairs(recipes.Grouped(entry.recipe)) do gross[ing.id] = (gross[ing.id] or 0) + n * ing.count end
            gross[entry.recipe.crystal] = (gross[entry.recipe.crystal] or 0) + n
        end
        for id, n in pairs(synths) do
            local recipe = choose(id)
            for _, ing in ipairs(recipes.Grouped(recipe)) do gross[ing.id] = (gross[ing.id] or 0) + n * ing.count end
            gross[recipe.crystal] = (gross[recipe.crystal] or 0) + n
        end
        return gross
    end
    for _ = 1, 50 do
        local gross = compute()
        local changed = false
        local nextSynths = { }
        for id, need in pairs(gross) do
            local recipe = choose(id)
            if recipe ~= nil then
                local net = math.max(0, need - have(id))
                local n = net > 0 and planner.WithSpare(math.ceil(net / recipe.count), spare) or 0
                if n > 0 then nextSynths[id] = n end
            end
        end
        for id, n in pairs(nextSynths) do if synths[id] ~= n then changed = true end end
        for id in pairs(synths) do if nextSynths[id] == nil then changed = true end end
        synths = nextSynths
        if not changed then break end
    end
    local gross = compute()
    local buy = { }
    for id, need in pairs(gross) do
        if choose(id) == nil then buy[id] = math.max(0, need - have(id)) end
    end
    return synths, buy
end
local mismatches, firstMismatch, checked = 0, nil, 0
local function haveSome(id) return (id * 7) % 5 end
for _, recipe in ipairs(recipes.all) do
    local entries = { { recipe = recipe, synths = 7 } }
    for _, spare in ipairs({ 0, 15 }) do
        local planned = planner.Build(entries, makeAll, haveSome, recipes.Grouped, spare)
        local synths, buy = bruteForce(entries, makeAll, haveSome, spare)
        checked = checked + 1
        local ok = true
        local seen = { }
        for _, row in ipairs(planned.made) do
            seen[row.id] = true
            if (synths[row.id] or 0) ~= row.synths or row.leftover < 0 or row.synths * row.recipe.count < row.need - row.used then ok = false end
        end
        for id, n in pairs(synths) do if not seen[id] and n > 0 then ok = false end end
        local seenBuy = { }
        for _, row in ipairs(planned.buy) do
            seenBuy[row.id] = true
            if (buy[row.id] or -1) ~= row.buy or row.buy > row.need or row.buy < 0 then ok = false end
        end
        for id, n in pairs(buy) do if not seenBuy[id] and n > 0 then ok = false end end
        if not ok then
            mismatches = mismatches + 1
            firstMismatch = firstMismatch or recipe.id
        end
    end
end
check(mismatches == 0, ('%i plans (every recipe, 0 and 15 percent spare) match the brute-force answer%s'):format(checked, firstMismatch and (', first mismatch recipe ' .. firstMismatch) or ''))

---------------------------------------------------------------------------
print('== random packets')
do
    -- packets of every size with random bytes, for the ids HCrafter reads
    -- mid-session. zoning packets are left out, so the character stays put.
    math.randomseed(20261017)
    local ids = { 0x029, 0x030, 0x06F, 0x062 }
    local escaped, firstError = 0, nil
    local function randomPacket(size, playerId)
        local bytes = { }
        for i = 1, size do bytes[i] = string.char(math.random(0, 255)) end
        -- often make it about this character, so the handlers go deep
        if size >= 0x0C and math.random() < 0.5 then
            local id = 4242
            for i = 0, 3 do
                bytes[playerId + 1 + i] = string.char(id % 256)
                id = math.floor(id / 256)
            end
        end
        return table.concat(bytes)
    end
    for round = 1, 3000 do
        local id = ids[math.random(1, #ids)]
        local size = math.random(0, 0x110)
        local playerAt = (id == 0x029) and 0x08 or 0x04
        local event, data
        if round % 5 == 0 then
            event = 'packet_out'
            id = 0x096
            data = randomPacket(math.random(0, 0x30), 0x04)
        else
            event = 'packet_in'
            data = randomPacket(size, playerAt)
        end
        local ok, err = pcall(fire, event, { id = id, data = data })
        if not ok then
            escaped = escaped + 1
            firstError = firstError or (('0x%03X, %i bytes: %s'):format(id, #data, tostring(err)))
        end
        if round % 100 == 0 then
            advance(1)
            local _, why = frame(false)
            if why ~= nil then
                escaped = escaped + 1
                firstError = firstError or ('frame: ' .. why)
            end
        end
    end
    check(escaped == 0, ('3000 random packets raise no error and every frame stays balanced%s'):format(firstError and (', first: ' .. firstError) or ''))
    local finite = true
    for craftId = 1, 8 do
        local v = config.skills[craftId][1]
        if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then finite = false end
    end
    check(finite, 'craft levels stay finite numbers after random packets')
end

print(failures == 0 and 'ALL OK' or ('FAILURES: ' .. failures))
cleanup()
os.exit(failures == 0 and 0 or 1)
