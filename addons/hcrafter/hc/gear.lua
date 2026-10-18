-- what you wear and which imagery buff you have, read from game memory.
-- read-only: nothing here changes your gear or sends anything.
--
-- the imagery buffs (image support) are status effects 236 to 243, one per
-- craft from Woodworking to Cooking, so a buff id minus 235 is the craft id.
local bit = require('bit')
local craftgear = require('data.craftgear')

local gear = {
    clock = os.clock,
    slots = 16,
    -- the two ring slots, counted from 0 like the game
    ringSlots = { [13] = true, [14] = true },
}

local state = {
    at = nil,
    bonus = { },
    items = { },
    rings = { },
    imagery = { },
    imageryCraft = nil,
}

-- the item ids you have equipped, slot by slot (0 when empty)
local function EquippedIds()
    local ids = { }
    local memory = AshitaCore:GetMemoryManager()
    local inv = memory and memory:GetInventory() or nil
    if inv == nil then
        return ids
    end

    for slot = 0, gear.slots - 1 do
        local itemId = 0
        local ok, equipped = pcall(inv.GetEquippedItem, inv, slot)
        if ok and equipped ~= nil and equipped.Index ~= nil then
            local raw = tonumber(equipped.Index) or 0
            local index = bit.band(raw, 0x00FF)
            if index > 0 then
                local container = bit.rshift(bit.band(raw, 0xFF00), 8)
                local item = inv:GetContainerItem(container, index)
                if item ~= nil and item.Id ~= nil and item.Id > 0 and item.Id ~= 65535 then
                    itemId = item.Id
                end
            end
        end
        ids[slot] = itemId
    end
    return ids
end

local function ActiveBuffs()
    local active = { }
    local memory = AshitaCore:GetMemoryManager()
    local player = memory and memory:GetPlayer() or nil
    if player == nil or player.GetBuffs == nil then
        return active
    end
    local ok, buffs = pcall(player.GetBuffs, player)
    if not ok or type(buffs) ~= 'table' then
        return active
    end
    for i = 0, 31 do
        local id = buffs[i]
        if id ~= nil and id > 0 and id ~= 255 then
            active[id] = true
        end
    end
    return active
end

-- read gear and buffs again, at most twice a second unless forced
function gear.Refresh(force)
    local now = gear.clock()
    if not force and state.at ~= nil and now - state.at < 0.5 then
        return
    end
    state.at = now

    local bonus, itemsByCraft, rings = { }, { }, { }
    for craftId = 1, 8 do
        bonus[craftId] = 0
        itemsByCraft[craftId] = { }
    end

    for slot, itemId in pairs(EquippedIds()) do
        local skill = craftgear.skill[itemId]
        if skill ~= nil then
            for craftId, amount in pairs(skill) do
                if bonus[craftId] ~= nil then
                    bonus[craftId] = bonus[craftId] + amount
                    table.insert(itemsByCraft[craftId], { id = itemId, bonus = amount })
                end
            end
        end
        local antiCraft = craftgear.antiHQ[itemId]
        if antiCraft ~= nil and gear.ringSlots[slot] then
            rings[antiCraft] = itemId
        end
    end

    local imagery, imageryCraft = { }, nil
    local buffs = ActiveBuffs()
    for craftId = 1, 8 do
        if buffs[235 + craftId] then
            imagery[craftId] = true
            imageryCraft = imageryCraft or craftId
        end
    end

    state.bonus = bonus
    state.items = itemsByCraft
    state.rings = rings
    state.imagery = imagery
    state.imageryCraft = imageryCraft
end

-- the skill bonus your equipped gear gives a craft
function gear.Bonus(craftId)
    gear.Refresh(false)
    return state.bonus[craftId] or 0
end

-- the equipped items that add to a craft: { { id, bonus }, ... }
function gear.Items(craftId)
    gear.Refresh(false)
    return state.items[craftId] or { }
end

-- an equipped ring that blocks HQ for this craft, or nil
function gear.Ring(craftId)
    gear.Refresh(false)
    return state.rings[craftId]
end

function gear.HasImagery(craftId)
    gear.Refresh(false)
    return state.imagery[craftId] == true
end

-- the craft whose imagery buff is on, or nil
function gear.ImageryCraft()
    gear.Refresh(false)
    return state.imageryCraft
end

return gear
