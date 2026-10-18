-- craft history, one file per character. it is kept out of the Ashita
-- settings file so saving settings stays fast, and it is written when you
-- zone, log out or unload, or every five minutes when something changed.
--
-- each synth keeps the recipe it matched and your skill in each craft just
-- before the synth, so the skill-up mode can measure your real skill-up rate.
local files = require('hc.files')

local history = {
    max = 500,
    clock = os.clock,
}

local entries = { }
local currentName = nil
local dirty = false
local lastSave = nil

local function Path(name)
    return ('%s\\hist_%s.lua'):format(files.CharacterDir(), name)
end

local function Value(value)
    if type(value) == 'number' then
        if value == math.floor(value) then
            return ('%i'):format(value)
        end
        return ('%.4f'):format(value)
    end
    return tostring(value == true)
end

local function Serialize(list)
    local out = { '-- HCrafter craft history. written by the addon, safe to delete.', 'return {' }
    for _, entry in ipairs(list) do
        local parts = {
            ('startTime = %s'):format(Value(entry.startTime or 0)),
            ('item = %s'):format(Value(entry.item or 0)),
            ('count = %s'):format(Value(entry.count or 0)),
        }
        if entry.result ~= nil then
            table.insert(parts, ('result = %s'):format(Value(entry.result)))
        end
        if entry.recipe ~= nil then
            table.insert(parts, ('recipe = %s'):format(Value(entry.recipe)))
        end

        local lost = { }
        for _, itemId in ipairs(entry.lost or { }) do
            table.insert(lost, Value(itemId))
        end
        table.insert(parts, ('lost = { %s }'):format(table.concat(lost, ', ')))

        local skillups = { }
        for _, craftId in ipairs(files.SortedKeys(entry.skillup or { })) do
            local skillup = entry.skillup[craftId]
            local fields = { }
            if skillup.change ~= nil then
                table.insert(fields, ('change = %s'):format(Value(skillup.change)))
            end
            if skillup.before ~= nil then
                table.insert(fields, ('before = %s'):format(Value(skillup.before)))
            end
            table.insert(skillups, ('[%i] = { %s }'):format(craftId, table.concat(fields, ', ')))
        end
        table.insert(parts, ('skillup = { %s }'):format(table.concat(skillups, ', ')))

        table.insert(out, ('    { %s },'):format(table.concat(parts, ', ')))
    end
    table.insert(out, '}')
    table.insert(out, '')
    return table.concat(out, '\n')
end

-- keep only well-formed entries from a file
local function Clean(list)
    local clean = { }
    for _, entry in ipairs(list) do
        if type(entry) == 'table' and type(entry.item) == 'number' then
            local item = {
                startTime = tonumber(entry.startTime) or 0,
                item = entry.item,
                count = tonumber(entry.count) or 0,
                result = tonumber(entry.result),
                recipe = tonumber(entry.recipe),
                lost = { },
                skillup = { },
            }
            for _, itemId in ipairs(type(entry.lost) == 'table' and entry.lost or { }) do
                if type(itemId) == 'number' then
                    table.insert(item.lost, itemId)
                end
            end
            for craftId, skillup in pairs(type(entry.skillup) == 'table' and entry.skillup or { }) do
                if type(craftId) == 'number' and craftId >= 1 and craftId <= 8 and type(skillup) == 'table' then
                    item.skillup[craftId] = {
                        change = tonumber(skillup.change),
                        before = tonumber(skillup.before),
                    }
                end
            end
            table.insert(clean, item)
            if #clean >= history.max then
                break
            end
        end
    end
    return clean
end

function history.Save()
    if currentName == nil or not dirty then
        return
    end
    if files.Write(Path(currentName), Serialize(entries)) then
        dirty = false
    end
    lastSave = history.clock()
end

-- switch to a character's history, saving the previous one first
function history.Load(name)
    if name == currentName then
        return
    end

    history.Save()
    currentName = name
    entries = { }
    dirty = false
    if name ~= nil then
        entries = Clean(files.Read(Path(name)) or { })
    end
end

function history.Add(entry)
    table.insert(entries, 1, entry)
    while #entries > history.max do
        table.remove(entries)
    end
    dirty = true
end

function history.Latest()
    return entries[1]
end

function history.List()
    return entries
end

function history.Clear()
    entries = { }
    dirty = true
end

-- the latest entry was edited in place (a skill-up arrived)
function history.Changed()
    dirty = true
end

function history.Tick()
    if dirty and (lastSave == nil or history.clock() - lastSave >= 300) then
        history.Save()
    end
end

return history
