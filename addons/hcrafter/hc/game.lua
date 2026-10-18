-- read-only checks on the game client, used to hide HCrafter's windows at
-- the right times. memory signatures copied from xitools utils/ffxi.lua
-- (lin and aravix, GPL-3.0). The event and interface signatures are courtesy of Velyn.
local game = { }

local menuBase = ashita.memory.find('FFXiMain.dll', 0, '8B480C85C974??8B510885D274??3B05', 16, 0)
local eventSystem = ashita.memory.find('FFXiMain.dll', 0, 'A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3', 0, 0)
local interfaceHidden = ashita.memory.find('FFXiMain.dll', 0, '8B4424046A016A0050B9????????E8????????F6D81BC040C3', 0, 0)

-- the name of the top-most menu, or '' if none is open
function game.GetMenuName()
    if menuBase == nil or menuBase == 0 then
        return ''
    end

    local subPointer = ashita.memory.read_uint32(menuBase)
    if subPointer == nil or subPointer == 0 then
        return ''
    end

    local subValue = ashita.memory.read_uint32(subPointer)
    if subValue == nil or subValue == 0 then
        return ''
    end

    local menuHeader = ashita.memory.read_uint32(subValue + 4)
    if menuHeader == nil or menuHeader == 0 then
        return ''
    end

    local menuName = ashita.memory.read_string(menuHeader + 0x46, 16)
    if menuName == nil then
        return ''
    end
    return (string.gsub(menuName, '\x00', ''))
end

function game.IsMapOpen()
    local menuName = game.GetMenuName()
    return menuName:match('menu%s+map.*') ~= nil
        or menuName:match('menu%s+scanlist.*') ~= nil
        or menuName:match('menu%s+cnqframe') ~= nil
end

function game.IsEventHappening()
    if eventSystem == nil or eventSystem == 0 then
        return false
    end

    local ptr = ashita.memory.read_uint32(eventSystem + 1)
    if ptr == 0 then
        return false
    end

    return ashita.memory.read_uint8(ptr) == 1
end

function game.IsInterfaceHidden()
    if interfaceHidden == nil or interfaceHidden == 0 then
        return false
    end

    local ptr = ashita.memory.read_uint32(interfaceHidden + 10)
    if ptr == 0 then
        return false
    end

    return ashita.memory.read_uint8(ptr + 0xB4) == 1
end

-- your character's status (44 while you synth), or nil when it can't be
-- read. the same entity lookup XIUI uses.
function game.PlayerStatus()
    local ok, status = pcall(function()
        local memory = AshitaCore:GetMemoryManager()
        local index = memory:GetParty():GetMemberTargetIndex(0)
        return memory:GetEntity():GetStatus(index)
    end)
    if ok and type(status) == 'number' then
        return status
    end
    return nil
end

return game
