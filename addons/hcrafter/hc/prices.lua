-- prices you type in, shared by all your characters. they live in
-- config\addons\hcrafter\prices.csv, one item per line:
--
--   item_id,name,price,updated
--   4099,Earth Crystal,120,2026-10-17
--
-- HCrafter never fetches prices from anywhere. you set them in game
-- (right-click an item, or /hcrafter price), or edit the file yourself.
-- a line may leave item_id empty: the name is then matched against the
-- items that recipes use. the name column is only there to make the file
-- readable. prices are per single item, in gil.
local files = require('hc.files')
local items = require('hc.items')

local prices = {
    maxPrice = 999999999,
    date = function() return os.date('%Y-%m-%d') end,
    -- the file is read and written as bytes, so a new one gets Windows line
    -- ends on Windows
    windowsLineEnds = package.config:sub(1, 1) == '\\',
}

local list = { }        -- itemId -> { price, updated }
local count = 0
local lastText = nil
local skipped = 0
local nameIndex = nil   -- lower-case name -> itemId, built on first use

function prices.Path()
    return files.BaseDir() .. '\\prices.csv'
end

---------------------------------------------------------------------------
-- names of the items recipes use, for lines without an item id
---------------------------------------------------------------------------

local function Trim(s)
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function BuildNameIndex()
    local recipes = require('hc.recipes')
    local ids, seen = { }, { }
    local function Add(id)
        if id ~= nil and id > 0 and not seen[id] then
            seen[id] = true
            table.insert(ids, id)
        end
    end
    for _, recipe in ipairs(recipes.all) do
        Add(recipe.result)
        Add(recipe.crystal)
        for _, id in ipairs(recipe.ingredients) do
            Add(id)
        end
    end
    table.sort(ids)

    nameIndex = { }
    for _, id in ipairs(ids) do
        for _, name in ipairs({ items.ShortName(id), items.Name(id) }) do
            local key = Trim(name:lower())
            if key ~= '' and nameIndex[key] == nil then
                nameIndex[key] = id
            end
        end
    end
end

-- the item a recipe uses with this name (either the menu name or the chat
-- log name, any case), or nil
function prices.Find(name)
    if type(name) ~= 'string' then
        return nil
    end
    if nameIndex == nil then
        BuildNameIndex()
    end
    return nameIndex[Trim(name:lower())]
end

---------------------------------------------------------------------------
-- csv
---------------------------------------------------------------------------

-- one csv line into fields. handles "quoted, fields" and doubled quotes.
local function SplitLine(line)
    local fields = { }
    local i, n = 1, #line
    while i <= n + 1 do
        local c = line:sub(i, i)
        if c == '"' then
            local value = { }
            i = i + 1
            while i <= n do
                local d = line:sub(i, i)
                if d == '"' then
                    if line:sub(i + 1, i + 1) == '"' then
                        table.insert(value, '"')
                        i = i + 2
                    else
                        i = i + 1
                        break
                    end
                else
                    table.insert(value, d)
                    i = i + 1
                end
            end
            table.insert(fields, table.concat(value))
            -- skip to the next comma
            local comma = line:find(',', i, true)
            if comma == nil then
                break
            end
            i = comma + 1
        else
            local comma = line:find(',', i, true)
            if comma == nil then
                table.insert(fields, line:sub(i))
                break
            end
            table.insert(fields, line:sub(i, comma - 1))
            i = comma + 1
        end
    end
    return fields
end

prices.SplitLine = SplitLine

-- "1,200", "1200g" and " 1200 " all read as 1200. nil when it is not a
-- whole number from 0 to the gil cap.
local function ParsePrice(text)
    if type(text) ~= 'string' then
        return nil
    end
    local digits = text:gsub('[%s,]', ''):gsub('[gG]$', '')
    if not digits:match('^%d+$') or #digits > 9 then
        return nil
    end
    local value = tonumber(digits)
    if value == nil or value < 0 or value > prices.maxPrice then
        return nil
    end
    return value
end

prices.ParsePrice = ParsePrice

-- a UTF-8 byte order mark, which some editors put at the start of a file
local BOM = '\239\187\191'

-- the file's lines without their line ends, whether it uses Windows line
-- ends, and whether it starts with a byte order mark
local function Lines(text)
    local bom = text:sub(1, 3) == BOM
    if bom then
        text = text:sub(4)
    end
    local lines = { }
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do
        lines[#lines + 1] = (line:gsub('\r$', ''))
    end
    -- a final line end leaves one empty line behind
    if #lines > 0 and lines[#lines] == '' then
        table.remove(lines)
    end
    return lines, text:find('\r\n', 1, true) ~= nil, bom
end

-- what one line holds: 'blank' (empty or a # comment), 'header', 'bad', or
-- 'price' with the item, its entry, the name written on the line and any
-- columns after the date
local function ReadLine(line, first)
    if Trim(line) == '' or line:match('^%s*#') then
        return 'blank'
    end
    local fields = SplitLine(line)
    local idText = Trim(fields[1] or '')
    if first and not idText:match('^%d+$') and idText:lower():find('item', 1, true) ~= nil then
        return 'header'
    end
    local itemId = idText:match('^%d+$') and tonumber(idText) or nil
    if itemId ~= nil and (itemId <= 0 or itemId > 65534) then
        itemId = nil
    end
    if itemId == nil then
        itemId = prices.Find(fields[2] or '')
    end
    local price = ParsePrice(fields[3])
    if itemId ~= nil and price ~= nil then
        local extra = { }
        for i = 5, #fields do
            extra[#extra + 1] = fields[i]
        end
        return 'price', itemId, { price = price, updated = Trim(fields[4] or '') }, Trim(fields[2] or ''), extra
    end
    return 'bad'
end

local function Parse(text)
    local parsed, n, bad = { }, 0, 0
    local first = true
    for _, line in ipairs((Lines(text))) do
        local kind, itemId, entry = ReadLine(line, first)
        if kind ~= 'blank' then
            first = false
        end
        if kind == 'price' then
            if parsed[itemId] == nil then
                n = n + 1
            end
            -- a later line for the same item wins
            parsed[itemId] = entry
        elseif kind == 'bad' then
            bad = bad + 1
        end
    end
    return parsed, n, bad
end

local function Quote(text)
    text = tostring(text or '')
    if text:find('[,"\r\n]') then
        return '"' .. text:gsub('"', '""') .. '"'
    end
    return text
end

-- one price line. extra holds any columns you added after the date.
local function PriceLine(itemId, name, price, updated, extra)
    if name == nil or name == '' then
        name = items.ShortName(itemId)
    end
    local line = ('%i,%s,%i,%s'):format(itemId, Quote(name), price, Quote(updated or ''))
    for _, field in ipairs(extra or { }) do
        line = line .. ',' .. Quote(field)
    end
    return line
end

-- the file with one item's price set (or with nil, removed). every other
-- line stays as it was: comments, blank lines, lines HCrafter can't read,
-- and the names and extra columns you wrote. a new file gets the line ends
-- of the computer it is made on.
local function WithPrice(text, itemId, price, updated)
    local lines, crlf, bom = { }, prices.windowsLineEnds, false
    if text ~= nil and Trim(text) ~= '' then
        lines, crlf, bom = Lines(text)
    else
        lines = { 'item_id,name,price,updated' }
    end

    local out = { }
    local first = true
    local placed = false
    for _, line in ipairs(lines) do
        local kind, id, _, name, extra = ReadLine(line, first)
        if kind ~= 'blank' then
            first = false
        end
        if kind == 'price' and id == itemId then
            -- the first line for the item takes the new price, and any
            -- later copies go, so the file keeps one line per item
            if not placed and price ~= nil then
                table.insert(out, PriceLine(itemId, name, price, updated, extra))
            end
            placed = true
        else
            table.insert(out, line)
        end
    end
    if not placed and price ~= nil then
        table.insert(out, PriceLine(itemId, nil, price, updated))
    end

    local eol = crlf and '\r\n' or '\n'
    return (bom and BOM or '') .. table.concat(out, eol) .. eol
end

---------------------------------------------------------------------------
-- what the rest of HCrafter uses
---------------------------------------------------------------------------

-- read the file again. returns the number of prices and of lines skipped.
-- unchanged files are not parsed twice.
function prices.Load(force)
    local text = files.ReadText(prices.Path(), true)
    if text == nil then
        list, count, skipped, lastText = { }, 0, 0, nil
        return 0, 0
    end
    if not force and text == lastText then
        return count, skipped
    end
    list, count, skipped = Parse(text)
    lastText = text
    return count, skipped
end

-- price of one item in gil and the day it was set, or nil
function prices.Get(itemId)
    local entry = list[itemId]
    if entry == nil then
        return nil
    end
    return entry.price, entry.updated
end

-- n of an item at its price, or nil without a price
function prices.Cost(itemId, n)
    local price = prices.Get(itemId)
    if price == nil then
        return nil
    end
    return price * (n or 1)
end

function prices.Count()
    return count
end

-- set (or with nil, clear) one price. the file is read again first, so a
-- change another character made in the meantime is kept, and only that
-- item's line changes. returns true, or false and a reason.
function prices.Set(itemId, price)
    if type(itemId) ~= 'number' or itemId <= 0 then
        return false, 'no item'
    end
    if price ~= nil then
        price = ParsePrice(tostring(price))
        if price == nil then
            return false, 'a price is a whole number of gil'
        end
    end

    local current = files.ReadText(prices.Path(), true)
    -- a file that is there but can't be read is never written over. when
    -- Ashita can't say whether it is there, a file read earlier counts.
    if current == nil then
        local exists = files.Exists(prices.Path())
        if exists == true or (exists == nil and lastText ~= nil) then
            return false, 'could not read prices.csv (is it open in another program?)'
        end
    end
    local text = WithPrice(current, itemId, price, prices.date())
    if not files.Write(prices.Path(), text, true) then
        return false, 'could not write prices.csv (is it open in another program?)'
    end

    list, count, skipped = Parse(text)
    lastText = text
    return true
end

-- "12,345" for a price
function prices.Format(value)
    if value == nil then
        return nil
    end
    local text = tostring(math.floor(value + 0.5))
    local formatted = text:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (formatted:gsub('^,', ''))
end

return prices
