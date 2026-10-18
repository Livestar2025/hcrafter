-- item names, search keys and stack sizes from the game's own item data.
-- names never change while the game runs, so lookups are cached.
local items = { }

local cache = { }

local function Lookup(itemId)
    local entry = cache[itemId]
    if entry ~= nil then
        return entry
    end

    local item = AshitaCore:GetResourceManager():GetItemById(itemId)
    if item == nil then
        entry = {
            name = ('item %i'):format(itemId),
            shortName = ('item %i'):format(itemId),
            stackSize = 1,
        }
    else
        entry = {
            name = item.LogNameSingular[1] or ('item %i'):format(itemId),
            shortName = item.Name[1] or ('item %i'):format(itemId),
            stackSize = item.StackSize or 1,
        }
    end

    if entry.stackSize < 1 then
        entry.stackSize = 1
    end

    entry.searchShort = entry.shortName:lower()
    entry.searchName = entry.name:lower()
    cache[itemId] = entry
    return entry
end

-- the long name, as the game writes it in the chat log
function items.Name(itemId)
    return Lookup(itemId).name
end

-- the short name, as the game shows it in menus
function items.ShortName(itemId)
    return Lookup(itemId).shortName
end

function items.StackSize(itemId)
    return Lookup(itemId).stackSize
end

-- plain substring match (no lua patterns) on both names
function items.Matches(itemId, filter)
    local entry = Lookup(itemId)
    return entry.searchShort:find(filter, 1, true) ~= nil
        or entry.searchName:find(filter, 1, true) ~= nil
end

return items
