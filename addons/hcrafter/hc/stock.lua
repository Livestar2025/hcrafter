-- what you hold, and where. live counts come from the game for the character
-- you are on. other characters come from snapshot files that HCrafter saves
-- whenever you play that character with HCrafter loaded, so their counts
-- are only as fresh as their last save. nothing here sends packets.
local files = require('hc.files')
local session = require('hc.session')

local stock = {
    clock = os.clock,
    now = os.time,
    -- seconds between reads of the other characters' files while you play
    othersEvery = 600,
    -- the bags HCrafter counts. wardrobes are included because some
    -- materials are gear (ebony sabots, for example).
    containers = {
        { id = 0,  name = 'Inventory' },
        { id = 5,  name = 'Mog Satchel' },
        { id = 6,  name = 'Mog Sack' },
        { id = 7,  name = 'Mog Case' },
        { id = 1,  name = 'Mog Safe' },
        { id = 9,  name = 'Mog Safe 2' },
        { id = 2,  name = 'Storage' },
        { id = 4,  name = 'Mog Locker' },
        { id = 8,  name = 'Mog Wardrobe' },
        { id = 10, name = 'Mog Wardrobe 2' },
        { id = 11, name = 'Mog Wardrobe 3' },
        { id = 12, name = 'Mog Wardrobe 4' },
        { id = 13, name = 'Mog Wardrobe 5' },
        { id = 14, name = 'Mog Wardrobe 6' },
        { id = 15, name = 'Mog Wardrobe 7' },
        { id = 16, name = 'Mog Wardrobe 8' },
    },
    containerNames = { },
    others = { },
}

for _, container in ipairs(stock.containers) do
    stock.containerNames[container.id] = container.name
end

local live = { at = nil, items = { }, loaded = { }, checksum = 0 }
local othersByItem = { }
local lastSaveChecksum = nil
local lastSaveAt = nil
local lastOthersLoad = nil

---------------------------------------------------------------------------
-- snapshot files: characters\char_<Name>.lua plus characters\index.lua
---------------------------------------------------------------------------

local function SnapshotPath(name)
    return ('%s\\char_%s.lua'):format(files.CharacterDir(), name)
end

local function IndexPath()
    return files.CharacterDir() .. '\\index.lua'
end

local function SerializeSnapshot(snapshot)
    local out = {
        '-- HCrafter bag snapshot. written by the addon, safe to delete.',
        'return {',
        '    version = 1,',
        ('    name = %q,'):format(snapshot.name),
        ('    saved = %i,'):format(snapshot.saved),
        '    containers = {',
    }

    for _, containerId in ipairs(files.SortedKeys(snapshot.containers)) do
        local container = snapshot.containers[containerId]
        table.insert(out, ('        [%i] = { saved = %i, items = {'):format(containerId, container.saved))
        local line = { }
        for _, itemId in ipairs(files.SortedKeys(container.items)) do
            table.insert(line, ('[%i] = %i,'):format(itemId, container.items[itemId]))
            if #line == 8 then
                table.insert(out, '            ' .. table.concat(line, ' '))
                line = { }
            end
        end
        if #line > 0 then
            table.insert(out, '            ' .. table.concat(line, ' '))
        end
        table.insert(out, '        } },')
    end

    table.insert(out, '    },')
    table.insert(out, '}')
    table.insert(out, '')
    return table.concat(out, '\n')
end

local function SerializeIndex(names)
    local out = { '-- HCrafter character list. written by the addon, safe to delete.', 'return {' }
    for _, name in ipairs(names) do
        table.insert(out, ('    %q,'):format(name))
    end
    table.insert(out, '}')
    table.insert(out, '')
    return table.concat(out, '\n')
end

-- snapshot names found in the folder itself, when Ashita can list it. this
-- rebuilds the character list if the index file is ever lost or damaged.
local function ListedNames()
    local names = { }
    if ashita.fs.get_directory == nil then
        return names
    end

    local ok, list = pcall(ashita.fs.get_directory, files.CharacterDir())
    if ok and type(list) == 'table' then
        for _, entry in pairs(list) do
            local name = tostring(entry):match('char_(%w+)%.lua$')
            if name ~= nil then
                table.insert(names, name)
            end
        end
    end
    return names
end

-- every character on file: the index plus anything found in the folder
local function KnownNames()
    local names, seen = { }, { }
    local function Add(name)
        name = files.SafeName(name)
        if name ~= '' and not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end

    for _, name in ipairs(files.Read(IndexPath()) or { }) do
        Add(name)
    end
    for _, name in ipairs(ListedNames()) do
        Add(name)
    end
    return names
end

-- a snapshot read back from disk, or nil if it is missing or malformed
local function ReadSnapshot(name)
    local snapshot = files.Read(SnapshotPath(name))
    if snapshot == nil or type(snapshot.containers) ~= 'table' then
        return nil
    end

    local clean = {
        name = files.SafeName(snapshot.name or name),
        saved = tonumber(snapshot.saved) or 0,
        containers = { },
    }

    for containerId, container in pairs(snapshot.containers) do
        if type(containerId) == 'number' and stock.containerNames[containerId] ~= nil
        and type(container) == 'table' and type(container.items) == 'table' then
            local items = { }
            for itemId, count in pairs(container.items) do
                local safeCount = files.Count(count)
                if type(itemId) == 'number' and safeCount ~= nil then
                    items[itemId] = safeCount
                end
            end
            clean.containers[containerId] = { saved = tonumber(container.saved) or clean.saved, items = items }
        end
    end

    return clean
end

local function SnapshotItemCount(snapshot)
    local total = 0
    for _, container in pairs(snapshot.containers) do
        for _, count in pairs(container.items) do
            total = total + count
        end
    end
    return total
end

---------------------------------------------------------------------------
-- live counts for the character you are on
---------------------------------------------------------------------------

function stock.CurrentName()
    return session.name or ''
end

-- re-read your bags, at most once a second unless forced
function stock.Refresh(force)
    local now = stock.clock()
    if not force and live.at ~= nil and now - live.at < 1 then
        return
    end
    live.at = now

    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local items = { }
    local loaded = { }
    local checksum = 0

    if inv ~= nil then
        for _, container in ipairs(stock.containers) do
            local max = inv:GetContainerCountMax(container.id) or 0
            if max > 0 then
                loaded[container.id] = true
                for slot = 0, max do
                    local item = inv:GetContainerItem(container.id, slot)
                    if item ~= nil and item.Id ~= 0 and item.Id ~= 65535 and item.Count > 0 then
                        local byContainer = items[item.Id]
                        if byContainer == nil then
                            byContainer = { }
                            items[item.Id] = byContainer
                        end
                        byContainer[container.id] = (byContainer[container.id] or 0) + item.Count
                        checksum = (checksum * 31 + item.Id * 7 + container.id * 3 + item.Count) % 2147483647
                    end
                end
            end
        end
    end

    live.items = items
    live.loaded = loaded
    live.checksum = checksum
end

---------------------------------------------------------------------------
-- other characters
---------------------------------------------------------------------------

-- read every other character's snapshot from disk
function stock.LoadOthers()
    local me = stock.CurrentName()
    local others = { }
    othersByItem = { }

    for _, name in ipairs(KnownNames()) do
        if name ~= me then
            local snapshot = ReadSnapshot(name)
            if snapshot ~= nil then
                table.insert(others, snapshot)
                for containerId, container in pairs(snapshot.containers) do
                    for itemId, count in pairs(container.items) do
                        local list = othersByItem[itemId]
                        if list == nil then
                            list = { }
                            othersByItem[itemId] = list
                        end
                        table.insert(list, {
                            name = snapshot.name,
                            containerId = containerId,
                            count = count,
                            saved = container.saved,
                        })
                    end
                end
            end
        end
    end

    for _, list in pairs(othersByItem) do
        table.sort(list, function(a, b)
            if a.name ~= b.name then
                return a.name < b.name
            end
            return a.containerId < b.containerId
        end)
    end

    stock.others = others
    lastOthersLoad = stock.clock()
end

-- save the character you are on, once the game has finished loading your
-- bags. force skips the "nothing changed" and "bags read empty" checks.
-- returns true when a file was written, or false and a reason.
function stock.SaveCurrent(force)
    local name = stock.CurrentName()
    if name == '' then
        return false, 'not logged in'
    end
    if not session.IsReady() then
        return false, 'bags still loading'
    end

    stock.Refresh(true)
    if not live.loaded[0] then
        return false, 'bags still loading'
    end

    if not force and lastSaveChecksum == live.checksum then
        return false, 'no change'
    end

    local previous = ReadSnapshot(name)
    local now = stock.now()
    local snapshot = { name = name, saved = now, containers = { } }

    for _, container in ipairs(stock.containers) do
        if live.loaded[container.id] then
            local items = { }
            for itemId, byContainer in pairs(live.items) do
                local count = byContainer[container.id]
                if count ~= nil then
                    items[itemId] = count
                end
            end
            snapshot.containers[container.id] = { saved = now, items = items }
        elseif previous ~= nil and previous.containers[container.id] ~= nil then
            -- the game is not showing this bag right now, so keep what was seen last time
            snapshot.containers[container.id] = previous.containers[container.id]
        end
    end

    -- an empty read right after zoning must never wipe a real snapshot. only
    -- the bags the game shows right now are compared.
    if not force then
        local liveTotal, previousTotal = 0, 0
        for _, container in ipairs(stock.containers) do
            if live.loaded[container.id] then
                for _, count in pairs(snapshot.containers[container.id].items) do
                    liveTotal = liveTotal + count
                end
                local old = previous ~= nil and previous.containers[container.id] or nil
                if old ~= nil then
                    for _, count in pairs(old.items) do
                        previousTotal = previousTotal + count
                    end
                end
            end
        end
        if liveTotal == 0 and previousTotal > 0 then
            return false, 'bags read empty'
        end
    end

    if not files.Write(SnapshotPath(name), SerializeSnapshot(snapshot)) then
        return false, 'could not write the snapshot file'
    end

    -- the character list only ever grows here
    local names = KnownNames()
    local listed = false
    for _, listedName in ipairs(names) do
        if listedName == name then
            listed = true
        end
    end
    if not listed then
        table.insert(names, name)
    end
    files.Write(IndexPath(), SerializeIndex(names))

    lastSaveChecksum = live.checksum
    lastSaveAt = stock.clock()
    return true
end

---------------------------------------------------------------------------
-- timing
---------------------------------------------------------------------------

-- a new character (or none): save promptly once its bags load, and re-read
-- everyone else
session.OnChange(function()
    lastSaveChecksum = nil
    lastSaveAt = nil
    stock.LoadOthers()
end)

-- zoning is a good moment to read the others again: the next frame is on
-- the loading screen, so the disk read can't stall the game. a character
-- change reads them at once instead, and then this read is skipped.
function stock.OnZoneIn()
    lastSaveChecksum = nil
    lastSaveAt = nil
    lastOthersLoad = nil
end

-- call once a frame. saves this character at most once a minute when its
-- bags changed. the others are read when you change character or zone, and
-- every ten minutes in case another game window saved one.
function stock.Tick()
    local now = stock.clock()

    if lastOthersLoad == nil or now - lastOthersLoad > stock.othersEvery then
        stock.LoadOthers()
    end

    if session.IsReady() and (lastSaveAt == nil or now - lastSaveAt >= 60) then
        stock.Refresh(false)
        if live.checksum ~= lastSaveChecksum then
            stock.SaveCurrent(false)
        end
        lastSaveAt = now
    end
end

function stock.OnUnload()
    stock.SaveCurrent(false)
end

---------------------------------------------------------------------------
-- what the drawing code asks for
---------------------------------------------------------------------------

-- counts for one item: on you (inventory), in your other bags, on others
function stock.Counts(itemId)
    stock.Refresh(false)

    local onYou, inBags, onOthers = 0, 0, 0
    local byContainer = live.items[itemId]
    if byContainer ~= nil then
        for containerId, count in pairs(byContainer) do
            if containerId == 0 then
                onYou = onYou + count
            else
                inBags = inBags + count
            end
        end
    end

    local list = othersByItem[itemId]
    if list ~= nil then
        for _, entry in ipairs(list) do
            onOthers = onOthers + entry.count
        end
    end

    return onYou, inBags, onOthers
end

-- every place an item is, for the hover popup: { { text, count, saved }, ... }
function stock.Locations(itemId)
    stock.Refresh(false)

    local lines = { }
    local byContainer = live.items[itemId] or { }
    table.insert(lines, { text = 'On you', count = byContainer[0] or 0 })

    for _, container in ipairs(stock.containers) do
        local count = byContainer[container.id]
        if container.id ~= 0 and count ~= nil then
            table.insert(lines, { text = container.name, count = count })
        end
    end

    for _, entry in ipairs(othersByItem[itemId] or { }) do
        table.insert(lines, {
            text = ('%s, %s'):format(entry.name, stock.containerNames[entry.containerId] or ('bag ' .. entry.containerId)),
            count = entry.count,
            saved = entry.saved,
        })
    end

    return lines
end

-- other characters on file, for the settings panel
function stock.OtherCharacters()
    local list = { }
    for _, snapshot in ipairs(stock.others) do
        table.insert(list, { name = snapshot.name, saved = snapshot.saved, items = SnapshotItemCount(snapshot) })
    end
    return list
end

-- for the bag check in settings: which bags the game reports right now
function stock.LoadedBags()
    stock.Refresh(false)
    local list = { }
    for _, container in ipairs(stock.containers) do
        local items = 0
        for _, byContainer in pairs(live.items) do
            items = items + (byContainer[container.id] or 0)
        end
        table.insert(list, { name = container.name, loaded = live.loaded[container.id] == true, items = items })
    end
    return list
end

return stock
