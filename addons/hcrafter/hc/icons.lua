-- the game's own pictures: item icons from the item data, and status icons
-- (the imagery buffs double as guild emblems). the loading code follows
-- Ashita's equipmon addon and XIUI's texture manager: the icon bitmap the
-- game already has in memory becomes a Direct3D texture. nothing is read
-- from disk and nothing is sent anywhere.
--
-- a few textures load per frame at most, so opening a long list never
-- stalls the game. anything that fails falls back to drawn shapes.
local icons = {
    enabled = true,
    perFrame = 6,
    maxCached = 300,
}

local ffi, d3d8 = nil, nil
local available = nil
local device = nil
local cache = { }
local cached = 0
local budget = 0
local frameNo = 0
-- textures dropped this frame stay referenced until the next frame starts,
-- since this frame's draw lists may still point at them
local graveyard = { }

local function Init()
    if available ~= nil then
        return available
    end
    local okFfi, ffiModule = pcall(require, 'ffi')
    local okD3d, d3dModule = pcall(require, 'd3d8')
    if okFfi and okD3d and ffiModule ~= nil and d3dModule ~= nil then
        ffi, d3d8 = ffiModule, d3dModule
        available = true
    else
        available = false
    end
    return available
end

local function Device()
    if device == nil and d3d8 ~= nil then
        local ok, dev = pcall(d3d8.get_device)
        if ok then
            device = dev
        end
    end
    return device
end

-- bitmap and size from a resource (item or status icon) into a texture
local function Load(resource)
    if resource == nil or resource.Bitmap == nil or resource.ImageSize == nil or resource.ImageSize <= 0 then
        return nil
    end
    local dev = Device()
    if dev == nil then
        return nil
    end
    local ok, texture = pcall(function()
        local C = ffi.C
        local out = ffi.new('IDirect3DTexture8*[1]')
        local result = C.D3DXCreateTextureFromFileInMemoryEx(dev, resource.Bitmap, resource.ImageSize,
            0xFFFFFFFF, 0xFFFFFFFF, 1, 0, C.D3DFMT_A8R8G8B8, C.D3DPOOL_MANAGED,
            C.D3DX_DEFAULT, C.D3DX_DEFAULT, 0xFF000000, nil, nil, out)
        if result ~= C.S_OK then
            return nil
        end
        return d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', out[0]))
    end)
    if ok and texture ~= nil then
        return texture
    end
    return nil
end

local function Trim()
    -- drop the least recently used half, never one used this frame
    local list = { }
    for key, entry in pairs(cache) do
        if entry.used ~= frameNo then
            table.insert(list, { key = key, used = entry.used })
        end
    end
    table.sort(list, function(a, b) return a.used < b.used end)
    for i = 1, math.floor(#list / 2) do
        table.insert(graveyard, cache[list[i].key])
        cache[list[i].key] = nil
        cached = cached - 1
    end
end

local function Get(key, fetch)
    if not icons.enabled or not Init() then
        return nil
    end
    local entry = cache[key]
    if entry ~= nil then
        entry.used = frameNo
        return entry.ptr
    end
    if budget <= 0 then
        return nil
    end
    budget = budget - 1

    local okFetch, resource = pcall(fetch)
    local texture = okFetch and Load(resource) or nil
    local ptr = false
    if texture ~= nil then
        local okPtr, number = pcall(function() return tonumber(ffi.cast('uint32_t', texture)) end)
        if okPtr and number ~= nil and number ~= 0 then
            ptr = number
        end
    end

    if cached >= icons.maxCached then
        Trim()
    end
    -- a failure is remembered too, so it is not retried every frame
    cache[key] = { texture = texture, ptr = ptr, used = frameNo }
    cached = cached + 1
    return ptr
end

-- the texture of an item's icon, or nil (draw a fallback instead)
function icons.Item(itemId)
    if itemId == nil or itemId <= 0 or itemId == 65535 then
        return nil
    end
    local ptr = Get('i' .. itemId, function()
        return AshitaCore:GetResourceManager():GetItemById(itemId)
    end)
    return ptr or nil
end

-- the texture of a status icon, or nil
function icons.Status(statusId)
    local ptr = Get('s' .. statusId, function()
        return AshitaCore:GetResourceManager():GetStatusIconByIndex(statusId)
    end)
    return ptr or nil
end

-- a craft's guild emblem: its imagery status icon (236 Woodworking to 243
-- Cooking)
function icons.Emblem(craftId)
    if craftId == nil or craftId < 1 or craftId > 8 then
        return nil
    end
    return icons.Status(235 + craftId)
end

-- call once a frame, before drawing
function icons.NewFrame()
    frameNo = frameNo + 1
    budget = icons.perFrame
    graveyard = { }
end

-- forget every texture. call on zoning, since a device reset can make old
-- textures invalid (XIUI does the same).
function icons.Reset()
    for _, entry in pairs(cache) do
        table.insert(graveyard, entry)
    end
    cache = { }
    cached = 0
    device = nil
end

function icons.Available()
    return Init()
end

return icons
