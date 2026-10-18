-- keeps count of what HCrafter opens in imgui: windows, children, popups,
-- style colors and variables, and fonts. every module opens and closes them
-- through here. if a draw ever stops on an error halfway through a window,
-- or ends with something still open, guard.Run closes what that draw left
-- open, newest first, so imgui stays balanced and the game keeps running.
-- each different problem is printed once, up to a few per window.
local imgui = require('imgui')

local guard = { }

local stack = { }
-- per window: the problems already printed, and how many
local reported = { }
local maxReports = 3

local closers = {
    window = function() imgui.End() end,
    child = function() imgui.EndChild() end,
    popup = function() imgui.EndPopup() end,
    color = function() imgui.PopStyleColor(1) end,
    var = function() imgui.PopStyleVar(1) end,
    font = function() imgui.PopFont() end,
}

local function Push(kind)
    stack[#stack + 1] = kind
end

local function Pop(kind, count)
    for _ = 1, count or 1 do
        for i = #stack, 1, -1 do
            if stack[i] == kind then
                table.remove(stack, i)
                break
            end
        end
    end
end

-- each opener records itself only after imgui accepted the call, so a call
-- that fails on its arguments is never closed later

function guard.Begin(...)
    local open, more = imgui.Begin(...)
    Push('window')
    return open, more
end

function guard.End()
    imgui.End()
    Pop('window')
end

function guard.BeginChild(...)
    local open = imgui.BeginChild(...)
    Push('child')
    return open
end

function guard.EndChild()
    imgui.EndChild()
    Pop('child')
end

-- a popup only needs closing when it is open
function guard.BeginPopup(...)
    local open = imgui.BeginPopup(...)
    if open then
        Push('popup')
    end
    return open
end

function guard.EndPopup()
    imgui.EndPopup()
    Pop('popup')
end

function guard.PushStyleColor(...)
    imgui.PushStyleColor(...)
    Push('color')
end

function guard.PopStyleColor(count)
    imgui.PopStyleColor(count or 1)
    Pop('color', count or 1)
end

function guard.PushStyleVar(...)
    imgui.PushStyleVar(...)
    Push('var')
end

function guard.PopStyleVar(count)
    imgui.PopStyleVar(count or 1)
    Pop('var', count or 1)
end

function guard.PushFont(...)
    imgui.PushFont(...)
    Push('font')
end

function guard.PopFont()
    imgui.PopFont()
    Pop('font')
end

-- how many things are open, for tests
function guard.Depth()
    return #stack
end

local function Report(name, message)
    local seen = reported[name]
    if seen == nil then
        seen = { count = 0 }
        reported[name] = seen
    end
    if seen[message] or seen.count >= maxReports then
        return
    end
    seen[message] = true
    seen.count = seen.count + 1
    print(('[hcrafter] %s %s'):format(name, message))
end

-- close what a draw left open, newest first. returns how many.
local function Unwind(base)
    local closed = 0
    while #stack > base do
        local kind = table.remove(stack)
        pcall(closers[kind])
        closed = closed + 1
    end
    return closed
end

-- run one window's draw. on an error, or with something still open at the
-- end, close what it left open and print the problem once. returns true
-- when the draw finished cleanly.
function guard.Run(name, fn, ...)
    local base = #stack
    local ok, err = pcall(fn, ...)
    local closed = Unwind(base)
    if not ok then
        Report(name, ('stopped on an error and was skipped this frame: %s'):format(tostring(err)))
        return false, err
    end
    if closed > 0 then
        Report(name, ('left %i imgui item%s open, now closed'):format(closed, closed == 1 and '' or 's'))
        return false
    end
    return true
end

-- a new frame starts with nothing open
function guard.NewFrame()
    for i = #stack, 1, -1 do
        stack[i] = nil
    end
end

return guard
