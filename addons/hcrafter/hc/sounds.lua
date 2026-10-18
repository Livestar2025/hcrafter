-- the sounds HCrafter can play for its alerts. HCrafter's own sounds were
-- made for it from plain sine tones (tools/make_sounds.py). any other .wav
-- file in the sounds folder shows up in the lists too, as XIUI's ready
-- check lists its sound folder. part of HCrafter, GPL-3.0.
local sounds = {
    -- HCrafter's own sounds, in the order the lists show them
    builtIn = {
        { file = 'ready.wav', label = 'Chime' },
        { file = 'chimes.wav', label = 'Three chimes' },
        { file = 'bell.wav', label = 'Bell' },
        { file = 'dingdong.wav', label = 'Ding-dong' },
        { file = 'blip.wav', label = 'Blip' },
        { file = 'alert.wav', label = 'Alert' },
        { file = 'levelup.wav', label = 'Level-up' },
        { file = 'hq.wav', label = 'HQ sparkle' },
        { file = 'hq_big.wav', label = 'Big HQ' },
        { file = 'break.wav', label = 'Break' },
    },
    -- the player's own .wav files found in the sounds folder
    custom = { },
    lastPlayed = nil,
}

-- every .wav in the sounds folder by lower-case name, from the last time it
-- was read, or nil when the folder couldn't be read
local present = nil

local labels = { }
for _, sound in ipairs(sounds.builtIn) do
    labels[sound.file:lower()] = sound.label
end

-- the sounds folder, or nil outside Ashita
local function Folder()
    if type(addon) ~= 'table' or type(addon.path) ~= 'string' then
        return nil
    end
    return addon.path .. '\\sounds\\'
end

-- a plain .wav file name: no folders, no "..", and nothing that would
-- confuse imgui's labels
function sounds.Valid(file)
    if type(file) ~= 'string' or file == '' or #file > 80 then
        return false
    end
    if file:find('[\\/:%%#]') or file:find('..', 1, true) then
        return false
    end
    return file:lower():match('%.wav$') ~= nil
end

-- read the sounds folder again: which sounds are there, and the player's
-- own. the whole folder is listed and filtered here, so a .WAV in capitals
-- counts too. returns how many of the player's own sounds it found.
function sounds.Refresh()
    local found = { }
    present = nil
    local folder = Folder()
    local fs = type(ashita) == 'table' and ashita.fs or nil
    if folder ~= nil and fs ~= nil and type(fs.get_directory) == 'function' then
        local ok, list = pcall(fs.get_directory, folder, '.*')
        if ok and type(list) == 'table' then
            present = { }
            for _, name in pairs(list) do
                if sounds.Valid(name) then
                    present[name:lower()] = true
                    if labels[name:lower()] == nil then
                        table.insert(found, name)
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b) return a:lower() < b:lower() end)
    sounds.custom = found
    return #found
end

-- whether a sound file is in the sounds folder. Windows plays its own
-- default sound for a file that isn't there, so a missing one is never
-- played.
function sounds.Exists(file)
    if not sounds.Valid(file) then
        return false
    end
    if present ~= nil then
        return present[file:lower()] == true
    end
    -- the folder couldn't be listed: ask about the file itself
    local folder = Folder()
    local fs = type(ashita) == 'table' and ashita.fs or nil
    if folder ~= nil and fs ~= nil and type(fs.exists) == 'function' then
        local ok, yes = pcall(fs.exists, folder .. file)
        if ok then
            return yes == true
        end
    end
    return true
end

-- what a sound is called in the lists
function sounds.Label(file)
    if type(file) ~= 'string' or file == '' then
        return 'None'
    end
    local label = labels[file:lower()]
    if label ~= nil then
        return label
    end
    return (file:gsub('%.[wW][aA][vV]$', ''))
end

-- every choice for a list: None, HCrafter's sounds, then the player's own
function sounds.Options()
    local list = { { file = '', label = 'None' } }
    for _, sound in ipairs(sounds.builtIn) do
        table.insert(list, sound)
    end
    for _, file in ipairs(sounds.custom) do
        table.insert(list, { file = file, label = sounds.Label(file), custom = true })
    end
    return list
end

-- play a sound from the sounds folder. returns true when Ashita took it.
function sounds.Play(file)
    if not sounds.Valid(file) or not sounds.Exists(file) then
        return false
    end
    local folder = Folder()
    if folder == nil or type(ashita) ~= 'table' or type(ashita.misc) ~= 'table' then
        return false
    end
    sounds.lastPlayed = file
    local ok = pcall(ashita.misc.play_sound, folder .. file)
    return ok
end

return sounds
