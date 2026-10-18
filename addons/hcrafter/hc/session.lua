-- who is logged in, and whether the game has finished loading their bags.
-- the name comes from the zone-in packet, the way Ashita's own settings
-- library does it, so a stale name in party memory can't mix characters up.
local files = require('hc.files')

local session = {
    clock = os.clock,
    name = nil,
    serverId = 0,
}

local readyAt = nil
local listeners = { }

-- fn(newName, oldName) runs whenever the character changes, including to nil
function session.OnChange(fn)
    table.insert(listeners, fn)
end

local function SetCharacter(serverId, name)
    if name == '' then
        name = nil
    end
    if name == session.name then
        return
    end

    local old = session.name
    session.name = name
    session.serverId = serverId or 0
    for _, fn in ipairs(listeners) do
        fn(name, old)
    end
end

-- when the addon loads mid-session there is no zone-in packet to read, so
-- the login status and the player entity are used instead
function session.OnLoad()
    local entity = GetPlayerEntity()
    if entity == nil then
        return
    end

    local ok, status = pcall(function()
        return AshitaCore:GetMemoryManager():GetPlayer():GetLoginStatus()
    end)
    if ok and status ~= 2 then
        return
    end

    SetCharacter(entity.ServerId, files.SafeName(entity.Name))
    readyAt = session.clock() + 3
end

-- packet 0x00A: server id at 0x04, character name at 0x84
function session.OnZoneIn(data)
    local serverId = struct.unpack('L', data, 0x04 + 1)
    local name = struct.unpack('c16', data, 0x84 + 1)
    name = files.SafeName((name:gsub('%z.*$', '')))

    if name ~= '' then
        SetCharacter(serverId, name)
    end

    -- bags reload on every zone. packet 0x01D usually ends the wait sooner.
    readyAt = session.clock() + 20
end

-- packet 0x01D: the game has finished sending your bags
function session.OnInventoryFinish()
    if session.name == nil then
        return
    end

    local soon = session.clock() + 2
    if readyAt == nil or soon < readyAt then
        readyAt = soon
    end
end

-- packet 0x00B: leaving the zone. byte 0x04 is 1 on logout.
function session.OnZoneOut(data)
    readyAt = nil
    if struct.unpack('b', data, 0x04 + 1) == 1 then
        SetCharacter(0, nil)
    end
end

-- true once your bags have loaded and the game still shows the same character
function session.IsReady()
    if session.name == nil or readyAt == nil or session.clock() < readyAt then
        return false
    end

    local entity = GetPlayerEntity()
    if entity == nil or files.SafeName(entity.Name) ~= session.name then
        return false
    end

    return true
end

return session
