-- small file helpers for HCrafter's own files. they all live under
-- config\addons\<addon name>, so a renamed copy of the addon keeps its files
-- apart. lua files are read in an empty environment, so a damaged or edited
-- file can only fail to load.
local files = { }

-- the folder name comes from addon.name ('hcrafter'). anything but letters,
-- digits, _ and - is dropped, so the name can never point a path elsewhere.
function files.AddonName()
    local name = 'hcrafter'
    if type(addon) == 'table' and type(addon.name) == 'string' then
        local clean = addon.name:gsub('[^%w_%-]', '')
        if clean ~= '' then
            name = clean
        end
    end
    return name
end

function files.BaseDir()
    return ('%s\\config\\addons\\%s'):format(AshitaCore:GetInstallPath(), files.AddonName())
end

function files.CharacterDir()
    return files.BaseDir() .. '\\characters'
end

-- character names are letters only in FFXI. anything else is dropped, so a
-- name can never point a path somewhere else.
function files.SafeName(name)
    if type(name) ~= 'string' then
        return ''
    end

    return (name:gsub('[^%w]', ''))
end

function files.Read(path)
    local file = io.open(path, 'r')
    if file == nil then
        return nil
    end
    file:close()

    local chunk = loadfile(path)
    if chunk == nil then
        return nil
    end

    setfenv(chunk, { })
    local ok, result = pcall(chunk)
    if ok and type(result) == 'table' then
        return result
    end

    return nil
end

-- the whole file as text, or nil
function files.ReadText(path, binary)
    local file = io.open(path, binary and 'rb' or 'r')
    if file == nil then
        return nil
    end
    local text = file:read('*a')
    file:close()
    return text
end

-- true when a file is there, false when not, nil when Ashita can't tell
function files.Exists(path)
    if ashita == nil or ashita.fs == nil or ashita.fs.exists == nil then
        return nil
    end
    local ok, exists = pcall(ashita.fs.exists, path)
    if not ok then
        return nil
    end
    return exists == true
end

-- write a file under the character folder (or the base folder). returns true
-- when the file was written. binary writes the bytes as they are, so line
-- ends are not changed on Windows.
function files.Write(path, text, binary)
    ashita.fs.create_dir(files.BaseDir())
    ashita.fs.create_dir(files.CharacterDir())

    local file = io.open(path, binary and 'wb' or 'w')
    if file == nil then
        return false
    end

    file:write(text)
    file:close()
    return true
end

function files.SortedKeys(tbl)
    local keys = { }
    for key in pairs(tbl) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

-- a count read back from a file: a whole number from 1 to a million, or nil
function files.Count(value)
    if type(value) ~= 'number' or value ~= value or value < 1 or value > 1000000 then
        return nil
    end
    return math.floor(value)
end

return files
