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
-- game sounds that couldn't be turned into a .wav file, until the next
-- Refresh
local failed = { }
-- your own .wav files HCrafter can't rescale, by name, with the code of the
-- file that failed: each plays as it is, without being read again, until
-- the file changes
local asIs = { }
-- copies that couldn't be written, by sound: the code of the source and
-- when. each plays HCrafter's fallback without being decoded again, and is
-- tried again a minute later or after a Refresh.
local unwritten = { }
-- sound files waiting to be made, one a frame, oldest first, and the volume
-- each is wanted at. asking again only changes the volume, so stepping
-- the volume never piles up work.
local toMake = { }
local wanted = { }

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
            void* __stdcall GetModuleHandleA(const char* lpModuleName);
            uint32_t __stdcall GetModuleFileNameA(void* hModule, char* lpFilename, uint32_t nSize);
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
    unwritten = { }
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

-- the size and last change of a file, from Windows' own record of it, or
-- nil when the file isn't there or is a folder. outside Windows only the
-- size is known.
local winStat = nil
local function Stat(path)
    if winStat ~= false then
        local ok, size, hi, lo = pcall(function()
            local ffi = require('ffi')
            if winStat == nil then
                pcall(ffi.cdef, [[
                    typedef struct {
                        uint32_t attributes;
                        uint32_t created[2];
                        uint32_t accessed[2];
                        uint32_t written[2];
                        uint32_t sizeHigh;
                        uint32_t sizeLow;
                    } hcrafter_file_info;
                    int __stdcall GetFileAttributesExA(const char* name, int level, hcrafter_file_info* info);
                ]])
            end
            local info = ffi.new('hcrafter_file_info')
            if ffi.C.GetFileAttributesExA(path, 0, info) == 0 then
                return false
            end
            -- FILE_ATTRIBUTE_DIRECTORY
            if math.floor(tonumber(info.attributes) / 16) % 2 == 1 then
                return false
            end
            return tonumber(info.sizeHigh) * 4294967296 + tonumber(info.sizeLow), tonumber(info.written[1]), tonumber(info.written[0])
        end)
        if ok then
            winStat = true
            if size == false then
                return nil
            end
            return size, hi, lo
        end
        -- only a first call that fails means Windows' record can't be read
        if winStat == nil then
            winStat = false
        end
    end
    local file = io.open(path, 'rb')
    if file == nil then
        return nil
    end
    local size = file:seek('end')
    file:close()
    if type(size) ~= 'number' then
        return nil
    end
    return size, 0, 0
end

-- how many seconds ago a file was written, from the write time Stat gives
-- (100 ns steps since 1601), or nil when the write time isn't known
local function Age(hi, lo)
    if hi == 0 and lo == 0 then
        return nil
    end
    return os.time() - ((hi * 4294967296 + lo) / 10000000 - 11644473600)
end

-- a short code for a file's size and last change, part of the name of each
-- copy HCrafter makes, so a changed sound gets a new copy. nil when the file
-- isn't there.
local function Code(path)
    local size, hi, lo = Stat(path)
    if size == nil then
        return nil
    end
    local h = size % 4294967296
    h = (h * 31 + hi) % 4294967296
    h = (h * 31 + lo) % 4294967296
    return ('%04x%04x'):format(math.floor(h / 65536), h % 65536)
end

-- where a sound's own file is: the game's .spw file or the .wav file in the
-- sounds folder, or nil
local function Source(choice)
    local id = sounds.GameId(choice)
    if id ~= nil then
        return sounds.GamePath(id)
    end
    local folder = Folder()
    return folder and (folder .. choice) or nil
end

-- the copy HCrafter makes of a sound at a volume, from a file with a code:
-- se043006-v80-1a2b3c4d.wav for a game sound, own-ready-v80-1a2b3c4d.wav for
-- a .wav file
local function CacheName(choice, volume, code)
    local id = sounds.GameId(choice)
    if id ~= nil then
        return ('%s-v%i-%s.wav'):format(id:match('/(se%d+)$'), volume, code)
    end
    return ('own-%s-v%i-%s.wav'):format((choice:gsub('%.[wW][aA][vV]$', '')), volume, code)
end

-- true for the name of a copy HCrafter made: one of the above, one from
-- 1.3.0 without a code, or a file a write left when the game closed
-- partway. nothing else in the folder is ever deleted.
local function Classify(name)
    if type(name) ~= 'string' or name:find('[\\/:]') or name:find('..', 1, true) then
        return nil
    end
    local lower = name:lower()
    local stem = lower:match('^(.-)%.wav%.%w+%.tmp$')
    if stem ~= nil then
        if stem:match('^se%d%d%d%d%d%d%-v%d+%-%x%x%x%x%x%x%x%x$') or stem:match('^own%-.+%-v%d+%-%x%x%x%x%x%x%x%x$') then
            return 'temp'
        end
        return nil
    end
    -- the name as it is, so your own file's name keeps its case
    stem = name:match('^(.-)%.[wW][aA][vV]$')
    if stem == nil then
        return nil
    end
    local se, code = stem:lower():match('^(se%d%d%d%d%d%d)%-v%d+%-(%x%x%x%x%x%x%x%x)$')
    if se ~= nil then
        return 'copy', 'game:' .. se:sub(1, 5) .. '/' .. se, code
    end
    local own
    own, code = stem:match('^[oO][wW][nN]%-(.+)%-[vV]%d+%-(%x%x%x%x%x%x%x%x)$')
    if own ~= nil then
        return 'copy', own .. '.wav', code:lower()
    end
    stem = stem:lower()
    if stem:match('^se%d%d%d%d%d%d%-v%d+$') or stem:match('^own%-.+%-v%d+$') then
        return 'old'
    end
    return nil
end

-- a name for a file being written that no other game window will pick:
-- the Windows process id, or else an address that differs by process
local token = nil
local function Token()
    if token == nil then
        local ok, id = pcall(function()
            local ffi = require('ffi')
            pcall(ffi.cdef, 'uint32_t __stdcall GetCurrentProcessId(void);')
            return tonumber(ffi.C.GetCurrentProcessId())
        end)
        if ok and type(id) == 'number' then
            token = ('%x'):format(id)
        else
            token = tostring({ }):match('(%x+)$') or '0'
        end
    end
    return token
end

-- gives a written file its own name in one step, replacing a damaged copy
-- there, with Windows' MoveFileEx. nil when that can't be called.
local function Replace(from, to)
    local ok, done = pcall(function()
        local ffi = require('ffi')
        pcall(ffi.cdef, 'int __stdcall MoveFileExA(const char* from, const char* to, uint32_t flags);')
        -- MOVEFILE_REPLACE_EXISTING
        return ffi.C.MoveFileExA(from, to, 1) ~= 0
    end)
    if ok then
        return done
    end
    return nil
end

-- writes a copy in full under another name, then gives it its own name, so
-- a crash or a full disk never leaves a short copy under the real name.
-- parts are written in order. returns true when a whole copy is there.
local function WriteCopy(path, ...)
    local temp = ('%s.%s.tmp'):format(path, Token())
    local file = io.open(temp, 'wb')
    if file == nil then
        return false
    end
    local wrote = file:write(...)
    local closed = file:close()
    if wrote and closed then
        if wave.Whole(path) then
            -- another game window made it in the meantime
            pcall(os.remove, temp)
            return true
        end
        local replaced = Replace(temp, path)
        if replaced == nil then
            -- without MoveFileEx: a rename fails onto a file that is there
            pcall(os.remove, path)
            local ok, renamed = pcall(os.rename, temp, path)
            replaced = ok and renamed ~= nil and renamed ~= false
        end
        if replaced then
            return true
        end
    end
    pcall(os.remove, temp)
    -- another game window may have won the race with a whole copy
    return wave.Whole(path)
end

-- makes the copy of a sound at a volume, unless a whole one is there.
-- returns its path, or nil and why: 'gone' when the source can't be opened.
local function Make(choice, volume, source, code)
    local path = CacheFolder() .. '\\' .. CacheName(choice, volume, code)
    if wave.Whole(path) then
        return path
    end
    local fs = Fs()
    if fs == nil or type(fs.create_dir) ~= 'function' then
        return nil, 'no folder'
    end
    local data = files.ReadText(source, true)
    if data == nil then
        return nil, 'gone'
    end
    local sound, why
    if sounds.GameId(choice) ~= nil then
        sound, why = spw.Decode(data)
    else
        sound, why = wave.Read(data)
    end
    if sound == nil then
        return nil, why
    end
    pcall(fs.create_dir, files.BaseDir())
    pcall(fs.create_dir, CacheFolder())
    if not WriteCopy(path, wave.Parts(sound, volume / 100)) then
        return nil, 'can\'t write'
    end
    return path
end

-- a sound's file is gone since the folder was last read
local function Gone(choice)
    local id = sounds.GameId(choice)
    if id ~= nil then
        gamePresent[id] = false
    elseif present ~= nil then
        present[choice:lower()] = nil
    end
    return nil, 'missing'
end

-- the file to play for a sound at a volume, or nil and why. the sound's own
-- file is checked each time, so one that went missing never reaches
-- Windows, which would play its own sound instead. a game sound is turned
-- into a .wav file the first time. any sound at a volume other than 100
-- gets a copy at that volume.
function sounds.PathFor(choice, volume)
    volume = sounds.Volume(volume)
    if volume <= 0 then
        return nil, 'volume 0'
    end
    if not sounds.Valid(choice) then
        return nil, 'missing'
    end
    local id = sounds.GameId(choice)
    if id ~= nil and not sounds.GameFolder() then
        return nil, 'missing'
    end
    if failed[choice] then
        return nil, 'unreadable'
    end
    local source = Source(choice)
    local code = source and Code(source)
    if code == nil then
        return Gone(choice)
    end
    if id ~= nil then
        gamePresent[id] = true
    elseif present ~= nil then
        present[choice:lower()] = true
    end
    if id == nil and (volume == 100 or asIs[choice] == code) then
        return source
    end
    local last = unwritten[choice]
    if last ~= nil and last.code == code and last.volume == volume and os.time() - last.at < 60 then
        if id == nil then
            return source
        end
        return nil, 'can\'t write'
    end
    local path, why = Make(choice, volume, source, code)
    if path ~= nil then
        return path
    end
    if why == 'gone' then
        return Gone(choice)
    end
    -- a write that failed is tried again in a minute
    local writing = why == 'can\'t write' or why == 'no folder'
    if writing then
        unwritten[choice] = { code = code, volume = volume, at = os.time() }
    end
    if id == nil then
        if not writing then
            asIs[choice] = code
        end
        -- a sound HCrafter can't rescale plays as it is
        return source
    end
    if not writing then
        failed[choice] = true
    end
    return nil, why
end

-- true when one of your own .wav files plays at its own volume because
-- HCrafter can't rescale it (see wave.Read for what it can)
function sounds.AsIs(choice)
    return type(choice) == 'string' and asIs[choice] ~= nil
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

-- get a sound's file ready ahead of time, so its first alert plays at once
function sounds.Warm(choice, volume)
    volume = sounds.Volume(volume)
    if volume <= 0 or not sounds.Valid(choice) or (sounds.GameId(choice) == nil and volume == 100) then
        -- nothing to make at this volume: a job asked for before goes too
        if wanted[choice] ~= nil then
            wanted[choice] = nil
            for i = #toMake, 1, -1 do
                if toMake[i] == choice then
                    table.remove(toMake, i)
                end
            end
        end
        return
    end
    if wanted[choice] == nil then
        toMake[#toMake + 1] = choice
    end
    wanted[choice] = volume
end

-- call once a frame: makes at most one waiting file
function sounds.Tick()
    local choice = table.remove(toMake, 1)
    if choice == nil then
        return false
    end
    local volume = wanted[choice]
    wanted[choice] = nil
    sounds.PathFor(choice, volume)
    return true
end

-- how many files are waiting to be made
function sounds.Waiting()
    return #toMake
end

-- the most copies the folder keeps. more go, oldest first, except the
-- ones in use.
sounds.maxCopies = 40

-- tidies the folder of copies. it deletes copies from 1.3.0, files a write
-- left more than ten minutes ago, and copies whose source changed or is
-- gone. past maxCopies, the oldest copies go too, except those of the
-- sounds given at the volume given. other characters and game windows
-- sharing the folder lose nothing they can't get back: a copy is made again
-- when it is needed. a copy Windows is playing stays until the next time.
-- returns how many went.
function sounds.Tidy(choices, volume)
    local fs = Fs()
    if fs == nil or type(fs.get_directory) ~= 'function' then
        return 0
    end
    volume = sounds.Volume(volume)
    local keep = { }
    for _, choice in ipairs(choices or { }) do
        if sounds.Valid(choice) and (sounds.GameId(choice) == nil or sounds.GameFolder()) then
            local source = Source(choice)
            local code = source and Code(source)
            if code ~= nil then
                keep[CacheName(choice, volume, code):lower()] = true
            end
        end
    end
    local folder = CacheFolder()
    local ok, list = pcall(fs.get_directory, folder .. '\\', '.*')
    if not ok or type(list) ~= 'table' then
        return 0
    end
    local removed = 0
    local function Remove(name)
        local done, result = pcall(os.remove, folder .. '\\' .. name)
        if done and result then
            removed = removed + 1
            return true
        end
        return false
    end
    local codes = { }
    local copies = { }
    for _, name in pairs(list) do
        local kind, choice, code = Classify(name)
        if kind == 'old' then
            Remove(name)
        elseif kind == 'temp' then
            -- another game window may be writing it right now
            local size, hi, lo = Stat(folder .. '\\' .. name)
            local age = size and Age(hi, lo)
            if size ~= nil and (age == nil or age > 600) then
                Remove(name)
            end
        elseif kind == 'copy' then
            -- with no game folder a game sound's copy can't be checked
            local stale = false
            if sounds.GameId(choice) == nil or sounds.GameFolder() then
                local current = codes[choice]
                if current == nil then
                    local source = Source(choice)
                    current = source and Code(source) or false
                    codes[choice] = current
                end
                stale = current ~= code
            end
            if stale then
                Remove(name)
            elseif not keep[name:lower()] then
                local _, hi, lo = Stat(folder .. '\\' .. name)
                copies[#copies + 1] = { name = name, age = hi and Age(hi, lo) or 0 }
            end
        end
    end
    local inUse = 0
    for _ in pairs(keep) do
        inUse = inUse + 1
    end
    local extra = #copies + inUse - sounds.maxCopies
    if extra > 0 then
        -- oldest first, then by name
        table.sort(copies, function(a, b)
            if a.age ~= b.age then
                return a.age > b.age
            end
            return a.name < b.name
        end)
        for i = 1, math.min(extra, #copies) do
            Remove(copies[i].name)
        end
    end
    return removed
end

return sounds
