-- the sounds HCrafter can play for its alerts:
--   FFXI's own sound effects, read from the player's game folder and turned
--   into .wav files on the player's PC under config\addons\hcrafter\sounds.
--   no game audio ships with HCrafter. the ones listed here were picked by
--   ear, one for each alert.
--   HCrafter's own sounds, made from plain tones (tools/make_sounds.py).
--   any other .wav file in the sounds folder, as XIUI's ready check lists
--   its sound folder.
-- every sound plays at the volume set in Settings. part of HCrafter, GPL-3.0.
local files = require('hc.files')
local spw = require('hc.spw')
local wave = require('hc.wave')

local sounds = {
    -- FFXI's own sound effects, as folder/name under sound\win\se. a setting
    -- names one as 'game:' followed by its id.
    game = {
        -- the first set Livestar picked, one for each alert (the defaults)
        { id = 'se043/se043006', label = 'FFXI level-up' },
        { id = 'se041/se041147', label = 'FFXI HQ' },
        { id = 'se037/se037067', label = 'FFXI rare HQ' },
        { id = 'se034/se034071', label = 'FFXI break' },
        { id = 'se044/se044177', label = 'FFXI skill-up' },
        { id = 'se034/se034012', label = 'FFXI no more skill-ups' },
        { id = 'se008/se008229', label = 'FFXI synths done' },
        { id = 'se035/se035131', label = 'FFXI out of a material' },
        -- his second set
        { id = 'se014/se014176', label = 'FFXI level-up 2' },
        { id = 'se034/se034043', label = 'FFXI HQ 2' },
        { id = 'se044/se044226', label = 'FFXI rare HQ 2' },
        { id = 'se016/se016106', label = 'FFXI break 2' },
        { id = 'se000/se000047', label = 'FFXI skill-up 2' },
        { id = 'se007/se007198', label = 'FFXI no more skill-ups 2' },
        { id = 'se032/se032013', label = 'FFXI synths done 2' },
        { id = 'se041/se041132', label = 'FFXI out of a material 2' },
        -- more he starred, named by folder and number
        { id = 'se000/se000026' }, { id = 'se000/se000027' }, { id = 'se000/se000032' },
        { id = 'se000/se000035' }, { id = 'se000/se000036' }, { id = 'se000/se000038' },
        { id = 'se000/se000048' }, { id = 'se000/se000050' }, { id = 'se002/se002096' },
        { id = 'se004/se004020' }, { id = 'se007/se007155' }, { id = 'se007/se007156' },
        { id = 'se007/se007157' }, { id = 'se007/se007167' }, { id = 'se007/se007188' },
        { id = 'se007/se007213' }, { id = 'se008/se008297' }, { id = 'se016/se016161' },
        { id = 'se016/se016171' }, { id = 'se032/se032014' }, { id = 'se032/se032096' },
        { id = 'se035/se035119' }, { id = 'se044/se044121' }, { id = 'se044/se044214' },
        { id = 'se044/se044219' }, { id = 'se044/se044227' },
    },
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
local gameLabels = { }
for _, sound in ipairs(sounds.game) do
    -- the extra ones are named by their folder and number: FFXI 000-026
    sound.label = sound.label or ('FFXI %s-%s'):format(sound.id:match('^se(%d+)/se%d%d%d(%d%d%d)$'))
    gameLabels[sound.id] = sound.label
end

-- the game's sound effect folder with a trailing \, false when it wasn't
-- found, nil before the first look
local gameFolder = nil
-- which game sounds are there, by id, since the last look
local gamePresent = { }
-- sounds that couldn't be turned into a .wav file, until the next Refresh
local failed = { }
-- .wav files waiting to be made, one a frame
local queue = { }

local function Fs()
    return type(ashita) == 'table' and ashita.fs or nil
end

-- HCrafter's sounds folder, or nil outside Ashita
local function Folder()
    if type(addon) ~= 'table' or type(addon.path) ~= 'string' then
        return nil
    end
    return addon.path .. '\\sounds\\'
end

-- where HCrafter keeps the .wav files it makes
local function CacheFolder()
    return files.BaseDir() .. '\\sounds'
end

-- the folder a loaded module came from (FFXiMain.dll is the game itself),
-- or nil
local function ModuleFolder(name)
    local ok, path = pcall(function()
        local ffi = require('ffi')
        pcall(ffi.cdef, [[
            void* GetModuleHandleA(const char* lpModuleName);
            uint32_t GetModuleFileNameA(void* hModule, char* lpFilename, uint32_t nSize);
        ]])
        local module = ffi.C.GetModuleHandleA(name)
        if module == nil then
            return nil
        end
        local buffer = ffi.new('char[?]', 1024)
        local length = ffi.C.GetModuleFileNameA(module, buffer, 1024)
        if length == 0 or length >= 1024 then
            return nil
        end
        return ffi.string(buffer, length)
    end)
    if ok and type(path) == 'string' then
        return path:match('^(.*[\\/])[^\\/]+$')
    end
    return nil
end

-- a game sound's id from a setting such as 'game:se043/se043006', or nil.
-- only this exact shape is accepted, so a setting can never name a path.
function sounds.GameId(choice)
    if type(choice) ~= 'string' then
        return nil
    end
    return choice:match('^game:(se%d%d%d/se%d%d%d%d%d%d)$')
end

-- the volume as a whole percent from 0 to 150 (100 when the value is odd)
function sounds.Volume(value)
    local v = tonumber(value)
    if v == nil or v ~= v then
        return 100
    end
    return math.max(0, math.min(150, math.floor(v + 0.5)))
end

-- the game's own .spw file for a game sound id
function sounds.GamePath(id)
    if not gameFolder then
        return nil
    end
    return gameFolder .. id:gsub('/', '\\') .. '.spw'
end

-- looks for the game's sound effect folder: first where HorizonXI's launcher
-- puts the game (inside Ashita's folder), then wherever the game's own
-- FFXiMain.dll was loaded from
local function FindGame()
    local roots = { }
    local okInstall, install = pcall(function() return AshitaCore:GetInstallPath() end)
    if okInstall and type(install) == 'string' and install ~= '' then
        roots[#roots + 1] = (install:gsub('[\\/]+$', '')) .. '\\SquareEnix\\FINAL FANTASY XI\\'
    end
    local dll = ModuleFolder('FFXiMain.dll')
    if dll ~= nil then
        roots[#roots + 1] = dll
    end
    for _, root in ipairs(roots) do
        local folder = root .. 'sound\\win\\se\\'
        if files.Exists(folder .. sounds.game[1].id:gsub('/', '\\') .. '.spw') == true then
            return folder
        end
    end
    return false
end

-- the game's sound effect folder, or nil when it wasn't found
function sounds.GameFolder()
    if gameFolder == nil then
        gameFolder = FindGame()
    end
    return gameFolder or nil
end

-- a plain .wav file name: no folders, no "..", and nothing that would
-- confuse imgui's labels
local function ValidFile(file)
    if type(file) ~= 'string' or file == '' or #file > 80 then
        return false
    end
    if file:find('[\\/:%%#]') or file:find('..', 1, true) then
        return false
    end
    return file:lower():match('%.wav$') ~= nil
end

-- a sound a setting can name: a game sound or a .wav file in the sounds folder
function sounds.Valid(choice)
    return sounds.GameId(choice) ~= nil or ValidFile(choice)
end

-- read the sounds folder again: which sounds are there, and the player's
-- own. the whole folder is listed and filtered here, so a .WAV in capitals
-- counts too. also looks for the game's sound folder again. returns how
-- many of the player's own sounds it found.
function sounds.Refresh()
    local found = { }
    present = nil
    local folder = Folder()
    local fs = Fs()
    if folder ~= nil and fs ~= nil and type(fs.get_directory) == 'function' then
        local ok, list = pcall(fs.get_directory, folder, '.*')
        if ok and type(list) == 'table' then
            present = { }
            for _, name in pairs(list) do
                if ValidFile(name) then
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
    gameFolder = FindGame()
    gamePresent = { }
    failed = { }
    return #found
end

-- whether a sound is there to play. a game sound needs the game's folder;
-- a .wav file must be in the sounds folder. Windows plays its own default
-- sound for a file that isn't there, so a missing one is never played.
function sounds.Exists(choice)
    local id = sounds.GameId(choice)
    if id ~= nil then
        if not sounds.GameFolder() then
            return false
        end
        local known = gamePresent[id]
        if known == nil then
            known = files.Exists(sounds.GamePath(id)) == true
            gamePresent[id] = known
        end
        return known
    end
    if not ValidFile(choice) then
        return false
    end
    if present ~= nil then
        return present[choice:lower()] == true
    end
    -- the folder couldn't be listed: ask about the file itself
    local folder = Folder()
    local fs = Fs()
    if folder ~= nil and fs ~= nil and type(fs.exists) == 'function' then
        local ok, yes = pcall(fs.exists, folder .. choice)
        if ok then
            return yes == true
        end
    end
    return true
end

-- true when a sound is there but couldn't be read, such as a game sound in
-- a format HCrafter can't read
function sounds.Unreadable(choice)
    return type(choice) == 'string' and failed[choice] == true
end

-- what a sound is called in the lists
function sounds.Label(choice)
    if type(choice) ~= 'string' or choice == '' then
        return 'None'
    end
    local id = sounds.GameId(choice)
    if id ~= nil then
        return gameLabels[id] or ('FFXI %s-%s'):format(id:match('^se(%d+)/se%d%d%d(%d%d%d)$'))
    end
    local label = labels[choice:lower()]
    if label ~= nil then
        return label
    end
    return (choice:gsub('%.[wW][aA][vV]$', ''))
end

-- every choice for a list: None, the game's sounds (when the game's folder
-- was found), HCrafter's sounds, then the player's own
function sounds.Options()
    local list = { { file = '', label = 'None' } }
    if sounds.GameFolder() then
        for _, sound in ipairs(sounds.game) do
            table.insert(list, { file = 'game:' .. sound.id, label = sound.label, group = 'game' })
        end
    end
    for _, sound in ipairs(sounds.builtIn) do
        table.insert(list, { file = sound.file, label = sound.label, group = 'hcrafter' })
    end
    for _, file in ipairs(sounds.custom) do
        table.insert(list, { file = file, label = sounds.Label(file), custom = true, group = 'custom' })
    end
    return list
end

-- the file HCrafter makes for a sound at a volume
local function CacheName(choice, volume)
    local id = sounds.GameId(choice)
    if id ~= nil then
        return ('%s-v%i.wav'):format(id:match('/(se%d+)$'), volume)
    end
    return ('own-%s-v%i.wav'):format(choice:gsub('%.[wW][aA][vV]$', ''), volume)
end

-- makes the .wav file for a sound at a volume, unless it is already there.
-- returns its path, or nil and why.
local function Make(choice, volume)
    local path = CacheFolder() .. '\\' .. CacheName(choice, volume)
    if files.Exists(path) == true then
        return path
    end
    local sound, why
    local id = sounds.GameId(choice)
    if id ~= nil then
        local data = files.ReadText(sounds.GamePath(id), true)
        if data == nil then
            return nil, 'can\'t open the game\'s file'
        end
        sound, why = spw.Decode(data)
    else
        local data = files.ReadText(Folder() .. choice, true)
        if data == nil then
            return nil, 'can\'t open the file'
        end
        sound, why = wave.Read(data)
    end
    if sound == nil then
        return nil, why
    end
    local fs = Fs()
    if fs == nil or type(fs.create_dir) ~= 'function' then
        return nil, 'no folder'
    end
    pcall(fs.create_dir, files.BaseDir())
    pcall(fs.create_dir, CacheFolder())
    local file = io.open(path, 'wb')
    if file == nil then
        return nil, 'can\'t write'
    end
    file:write(wave.Write(sound, volume / 100))
    file:close()
    return path
end

-- the file to play for a sound at a volume, or nil and why. a game sound
-- is turned into a .wav file the first time; any sound at a volume other
-- than 100 gets a copy at that volume.
function sounds.PathFor(choice, volume)
    volume = sounds.Volume(volume)
    if volume <= 0 then
        return nil, 'volume 0'
    end
    if not sounds.Valid(choice) or not sounds.Exists(choice) then
        return nil, 'missing'
    end
    if failed[choice] then
        return nil, 'unreadable'
    end
    local id = sounds.GameId(choice)
    local folder = Folder()
    if id == nil and folder == nil then
        return nil, 'no sounds folder'
    end
    if id == nil and volume == 100 then
        return folder .. choice
    end
    local path, why = Make(choice, volume)
    if path ~= nil then
        return path
    end
    if id == nil then
        -- a sound HCrafter can't rescale plays as it is
        return folder .. choice
    end
    failed[choice] = true
    return nil, why
end

-- play a sound at a volume (100 when left out). returns true when Ashita
-- took it.
function sounds.Play(choice, volume)
    local path = sounds.PathFor(choice, volume)
    if path == nil or type(ashita) ~= 'table' or type(ashita.misc) ~= 'table' then
        return false
    end
    sounds.lastPlayed = choice
    local ok = pcall(ashita.misc.play_sound, path)
    return ok
end

-- get a sound's file ready ahead of time, so the first alert plays at once
function sounds.Warm(choice, volume)
    volume = sounds.Volume(volume)
    if volume > 0 and sounds.Valid(choice) and (sounds.GameId(choice) ~= nil or volume ~= 100) then
        queue[#queue + 1] = { choice, volume }
    end
end

-- call once a frame: makes at most one waiting file
function sounds.Tick()
    local job = table.remove(queue, 1)
    if job ~= nil then
        sounds.PathFor(job[1], job[2])
    end
    return job ~= nil
end

-- how many files are waiting to be made
function sounds.Waiting()
    return #queue
end

return sounds
