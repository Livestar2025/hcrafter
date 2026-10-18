-- the right-click menu on items and recipes: add a recipe to the Resource
-- Planner, and set or clear an item's price. it also shows the list of
-- sounds for an alert in Settings. each window asks for the menu while it
-- draws and shows it at the end, so the popup opens and draws in the same
-- imgui scope. part of HCrafter, GPL-3.0.
local imgui = require('imgui')
local guard = require('hc.guard')
local theme = require('hc.theme')
local items = require('hc.items')
local recipes = require('hc.recipes')
local prices = require('hc.prices')
local app = require('hc.app')
local sounds = require('hc.sounds')
local fanfare = require('hc.fanfare')
local text = require('hc.text')
local ui = require('hc.ui')

local menu = { }

local pending = { }   -- window key -> request
local current = { }   -- window key -> open request
local priceText = { '' }
local message = nil

-- request: { itemId = id, recipes = { recipe, ... } or nil, mode = 'menu' or 'price' },
-- or { mode = 'sound', key = the alert's key in the sounds settings, label }
function menu.Request(windowKey, request)
    request.mode = request.mode or 'menu'
    pending[windowKey] = request
end

local function PopupId(windowKey)
    return 'hcrafter.menu.' .. windowKey
end

local function PushStyle()
    guard.PushStyleColor(ImGuiCol_PopupBg, theme.rgba(theme.Frame(1).bg, 0.98))
    guard.PushStyleColor(ImGuiCol_Border, theme.rgba(theme.goldDarker, 1))
    guard.PushStyleColor(ImGuiCol_Text, theme.rgba(theme.textSoft, 1))
    guard.PushStyleColor(ImGuiCol_TextDisabled, theme.rgba(theme.goldDark, 1))
    guard.PushStyleColor(ImGuiCol_HeaderHovered, theme.rgba(theme.gold, 0.25))
    guard.PushStyleColor(ImGuiCol_HeaderActive, theme.rgba(theme.gold, 0.4))
    guard.PushStyleColor(ImGuiCol_FrameBg, theme.rgba(theme.bgDark, 0.9))
    guard.PushStyleColor(ImGuiCol_Button, theme.rgba(theme.bgMedium, 1))
    guard.PushStyleColor(ImGuiCol_ButtonHovered, theme.rgba(theme.gold, 0.3))
    guard.PushStyleColor(ImGuiCol_ButtonActive, theme.rgba(theme.gold, 0.45))
end

local function PopStyle()
    guard.PopStyleColor(10)
end

local function SavePrice(itemId)
    local typed = priceText[1]:gsub('%s', '')
    local ok, why
    if typed == '' then
        ok, why = prices.Set(itemId, nil)
    else
        ok, why = prices.Set(itemId, typed)
    end
    if ok then
        app.Dirty()
        return true
    end
    message = why
    return false
end

-- call once per window, after its body is drawn
function menu.Draw(windowKey)
    local id = PopupId(windowKey)
    local request = pending[windowKey]
    if request ~= nil then
        pending[windowKey] = nil
        current[windowKey] = request
        if request.mode == 'price' then
            local price = prices.Get(request.itemId)
            priceText[1] = price and tostring(price) or ''
            message = nil
        end
        imgui.OpenPopup(id)
    end

    PushStyle()
    local shown = current[windowKey]
    if shown ~= nil and shown.mode == 'sound' then
        -- a long list of sounds scrolls instead of running off the screen
        local maxH = 600
        pcall(function()
            maxH = math.max(ui.Px(200), imgui.GetIO().DisplaySize.y * 0.7)
        end)
        pcall(function()
            if imgui.IsPopupOpen(id) then
                imgui.SetNextWindowSizeConstraints({ 0, 0 }, { 100000, maxH })
            end
        end)
    end
    if guard.BeginPopup(id) then
        -- the menu's text in the same font and size as the rest of HCrafter
        local fontPushed = text.PushWidgetFont(ui.Px(13))
        local open = current[windowKey]
        if open == nil then
            imgui.CloseCurrentPopup()
        elseif open.mode == 'price' then
            imgui.TextDisabled(items.ShortName(open.itemId))
            imgui.Text('Price for one, in gil')
            imgui.SetNextItemWidth(160)
            imgui.InputText('##hcrafter.price', priceText, 16)
            if imgui.Button('Save##hcrafter.pricesave') then
                if SavePrice(open.itemId) then
                    imgui.CloseCurrentPopup()
                end
            end
            imgui.SameLine()
            if prices.Get(open.itemId) ~= nil then
                if imgui.Button('Clear##hcrafter.priceclear') then
                    prices.Set(open.itemId, nil)
                    app.Dirty()
                    imgui.CloseCurrentPopup()
                end
                imgui.SameLine()
            end
            if imgui.Button('Cancel##hcrafter.pricecancel') then
                imgui.CloseCurrentPopup()
            end
            if message ~= nil then
                imgui.TextDisabled(message)
            end
            imgui.TextDisabled('Saved to prices.csv for all your characters.')
        elseif open.mode == 'sound' then
            -- picking a sound plays it, so you hear what you picked
            local ref = app.Config().sounds[open.key]
            imgui.TextDisabled(open.label)
            local groupNames = { game = 'FFXI sounds', hcrafter = 'HCrafter\'s sounds', custom = 'Your sounds' }
            local lastGroup = nil
            for index, option in ipairs(sounds.Options()) do
                if option.group ~= nil and option.group ~= lastGroup then
                    imgui.TextDisabled(groupNames[option.group] or '')
                    lastGroup = option.group
                end
                local label = (option.label:gsub('[%%#]', ''))
                if ref ~= nil and ref[1] == option.file then
                    label = label .. '  (now)'
                end
                if imgui.Selectable(('%s##hcrafter.sound%i'):format(label, index)) then
                    if ref ~= nil then
                        ref[1] = option.file
                        app.Dirty()
                    end
                    fanfare.PlayChoice(open.key, option.file)
                end
            end
        else
            imgui.TextDisabled(items.ShortName(open.itemId))
            local list = open.recipes or { }
            for _, recipe in ipairs(list) do
                local label = 'Add to Resource Planner'
                if #list > 1 then
                    label = ('Add recipe %i to Resource Planner'):format(recipes.OptionNumber(recipe))
                end
                if imgui.Selectable(('%s##hcrafter.add%i'):format(label, recipe.id)) then
                    app.AddToPlan(recipe)
                end
            end
            local price = prices.Get(open.itemId)
            local label = price and ('Change price (%s gil)'):format(prices.Format(price)) or 'Set price'
            if imgui.Selectable(label .. '##hcrafter.setprice') then
                -- a selectable closes the menu, so the price box opens next frame
                menu.Request(windowKey, { itemId = open.itemId, mode = 'price' })
            end
        end
        if fontPushed then
            guard.PopFont()
        end
        guard.EndPopup()
    end
    PopStyle()
end

return menu
