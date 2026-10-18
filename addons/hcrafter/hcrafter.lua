--[[
    HCrafter: a recipe book for Ashita v4 in a game-style look, with
    sub-recipes, HQ odds, a Resource Planner, a Shopping list, skill-up
    ideas, prices you type in, fanfare, and an alert after your
    /lastsynth macro.

    Copyright (C) lin (xitools, https://github.com/mousseng/xitools)
    Copyright (C) 2026 HCrafter contributors

    Based on the crafty component of xitools v0.26 by lin, which also ships
    unchanged in Aravix's xitools 0.27. Changed for HCrafter starting
    2026-10-17: standalone addon, cool mode drawing in XIUI's style, game
    icons and guild emblems, sub-recipe dropdowns, HQ and success estimates,
    Resource Planner, Shopping list, skill-up mode, prices, fanfare, an
    alert after your macro, bag and character counts, craft levels read from
    the game, history in its own file. See CHANGELOG.md.

    HCrafter only reads. It never sends packets and never acts for you.

    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License, version 3, as
    published by the Free Software Foundation.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
    Public License for more details. You should have received a copy of the
    license with this program (LICENSE). If not, see
    https://www.gnu.org/licenses/.
]]

addon.name    = 'hcrafter'
addon.author  = 'lin (xitools crafty), HCrafter contributors'
addon.version = '1.3.1'
addon.desc    = 'Recipe book with sub-recipes, HQ odds, planner, skill-up ideas and fanfare. Based on xitools crafty.'

require('common')
local settings = require('settings')
local packets = require('hc.packets')
local recipesByIngredients = require('data.recipesByIngredients')
local recipes = require('hc.recipes')
local items = require('hc.items')
local session = require('hc.session')
local stock = require('hc.stock')
local history = require('hc.history')
local game = require('hc.game')
local prices = require('hc.prices')
local gear = require('hc.gear')
local hq = require('hc.hq')
local skillup = require('hc.skillup')
local watch = require('hc.synthwatch')
local text = require('hc.text')
local icons = require('hc.icons')
local ui = require('hc.ui')
local app = require('hc.app')
local book = require('hc.book')
local planui = require('hc.planui')
local tracker = require('hc.tracker')
local fanfare = require('hc.fanfare')
local sounds = require('hc.sounds')
local guard = require('hc.guard')

-- the game reports HQ and special crystals by their own ids, the recipe
-- table only knows the normal ones
local crystalMap = {
    [4096] = 4096, [4097] = 4097, [4098] = 4098, [4099] = 4099,
    [4100] = 4100, [4101] = 4101, [4102] = 4102, [4103] = 4103,
    [4238] = 4096, [4239] = 4097, [4240] = 4098, [4241] = 4099,
    [4242] = 4100, [4243] = 4101, [4244] = 4102, [4245] = 4103,
    [6506] = 4096, [6507] = 4097, [6508] = 4098, [6509] = 4099,
    [6510] = 4100, [6511] = 4101, [6512] = 4102, [6513] = 4103,
}

local function PerCraft(value)
    local list = T{ }
    for craftId = 1, 8 do
        list[craftId] = T{ value }
    end
    return list
end

local defaults = T{
    -- 2 since 1.2.1: breaks play no sound by default. 3 since 1.3.0: the
    -- game's own sounds by default
    version = 3,
    book = T{
        visible = T{ true },
        pos = T{ 100, 100 },
        tab = T{ 1 },
        -- unscaled pixels. height 0 fits the content.
        width = T{ 520 },
        height = T{ 0 },
    },
    planner = T{
        visible = T{ false },
        -- -1: placed beside the recipe book the first time it opens
        pos = T{ -1, -1 },
        tab = T{ 1 },
        width = T{ 560 },
        height = T{ 0 },
        entries = T{ },
        make = T{ },
        spare = T{ 0 },
        useBags = T{ true },
        useOthers = T{ false },
    },
    tracker = T{
        visible = T{ true },
        pos = T{ -1, -1 },
        alpha = T{ 0.5 },
        width = T{ 320 },
    },
    skills = T{
        [0] = T{ 0.0 },
        [1] = T{ 0.0 },
        [2] = T{ 0.0 },
        [3] = T{ 0.0 },
        [4] = T{ 0.0 },
        [5] = T{ 0.0 },
        [6] = T{ 0.0 },
        [7] = T{ 0.0 },
        [8] = T{ 0.0 },
    },
    ranks = PerCraft(-1),
    capped = PerCraft(false),
    gear = PerCraft(0),
    autoGear = T{ true },
    -- the strength of image support while an imagery buff is on: 1 or 3
    support = T{ 1 },
    autoSkills = T{ true },
    searchMaterials = T{ false },
    look = T{
        frame = T{ 1 },
        alpha = T{ 0.92 },
        scale = T{ 1.0 },
        text = T{ 1.0 },
        -- grow with Ashita's own font size (font0.size in its boot ini)
        matchAshita = T{ true },
        gameIcons = T{ true },
        gameFont = T{ true },
    },
    fanfare = T{
        levelUp = T{ true },
        skillUp = T{ false },
        hq = T{ true },
        hqEasy = T{ false },
        breaks = T{ true },
        sound = T{ true },
    },
    -- the alert after your /lastsynth macro: after this many synths in a
    -- row, 1 to 6
    ready = T{
        enabled = T{ true },
        every = T{ 6 },
    },
    -- the sound for each alert: one of the game's own sounds ('game:' and
    -- its id under sound\win\se), a .wav file in the sounds folder, or ''
    -- for none. Livestar picked the game sounds by ear.
    sounds = T{
        levelUp = T{ 'game:se043/se043006' },
        hq = T{ 'game:se041/se041147' },
        hqBig = T{ 'game:se037/se037067' },
        breaks = T{ '' },
        skillUp = T{ 'game:se044/se044177' },
        noMore = T{ 'game:se034/se034012' },
        done = T{ 'game:se008/se008229' },
        short = T{ 'game:se035/se035131' },
        -- optional: on load or login, when /hcrafter shows the book, and at
        -- logout or unload
        startup = T{ '' },
        shutdown = T{ '' },
    },
    -- the volume of every sound, in percent (0 to 150)
    soundVolume = T{ 100 },
    skillup = T{
        craft = T{ 1 },
        target = T{ 0 },
        breakRule = T{ 1 },
        useMeasured = T{ false },
    },
    hideUnderMap = T{ true },
    hideDuringEvent = T{ true },
    hideWithInterface = T{ true },
}

local function DeepCopy(value)
    if type(value) ~= 'table' then
        return value
    end
    local copy = T{ }
    for key, inner in pairs(value) do
        copy[key] = DeepCopy(inner)
    end
    return copy
end

-- Ashita's settings library fills keys missing from an older file with the
-- default table itself. give every such key its own copy, so editing one
-- character's settings can never change the defaults or another character.
local function Detach(current, base)
    for key, value in pairs(base) do
        if type(value) == 'table' then
            if rawequal(current[key], value) or type(current[key]) ~= 'table' then
                current[key] = DeepCopy(value)
            else
                Detach(current[key], value)
            end
        end
    end
end

-- copy the defaults into a loaded settings table, and carry choices from
-- before 1.2.0 over to the new settings
local function Prepare(cfg)
    -- Ashita's settings library fills a missing table with the default table
    -- itself, so this is how a file from before 1.2.0 looks
    local noSounds = cfg.sounds == nil or rawequal(cfg.sounds, defaults.sounds)
    Detach(cfg, defaults)
    local ready = cfg.ready
    if noSounds and type(ready) == 'table' and type(ready.sound) == 'table' and ready.sound[1] == false then
        -- the ready cue's sound was off: the alert after a macro stays quiet
        cfg.sounds.done[1] = ''
    end
    -- 1.2.0 played break.wav on breaks by default. 1.2.1 plays nothing.
    if (tonumber(cfg.version) or 1) < 2 then
        if cfg.sounds.breaks[1] == 'break.wav' then
            cfg.sounds.breaks[1] = ''
        end
        cfg.version = 2
    end
    -- 1.3.0 plays the game's own sounds by default. a sound still at its
    -- 1.2.1 default moves to the new one. a sound you picked stays.
    if (tonumber(cfg.version) or 1) < 3 then
        local before = {
            levelUp = 'levelup.wav', hq = 'hq.wav', hqBig = 'hq_big.wav', skillUp = '',
            noMore = '', done = 'ready.wav', short = 'alert.wav',
        }
        for key, old in pairs(before) do
            local ref = cfg.sounds[key]
            if type(ref) == 'table' and ref[1] == old then
                ref[1] = defaults.sounds[key][1]
            end
        end
        cfg.version = 3
    end
end

local config = settings.load(defaults)
Prepare(config)

local dirtyAt = nil
local inProgSynth = nil

local function MarkDirty()
    if dirtyAt == nil then
        dirtyAt = os.clock()
    end
end

app.Init(function() return config end, MarkDirty)
fanfare.Config = function() return config end
planui.OpenInBook = book.Open

-- every sound picked in the settings in use
local function PickedSounds()
    local list = { }
    for _, ref in pairs(config.sounds) do
        if type(ref) == 'table' and type(ref[1]) == 'string' and ref[1] ~= '' then
            list[#list + 1] = ref[1]
        end
    end
    return list
end

-- the picked sounds get their files made a frame at a time, so the first
-- alert plays at once
local function WarmPicked()
    local volume = fanfare.Volume()
    for _, choice in ipairs(PickedSounds()) do
        sounds.Warm(choice, volume)
    end
end

settings.register('settings', 'hcrafter_settings_update', function(s)
    if s ~= nil then
        config = s
        Prepare(config)
        -- at login this is your own character's settings: its sounds and
        -- volume may differ from the ones HCrafter loaded with
        WarmPicked()
    end

    settings.save()
end)

-- each character has its own history file
session.OnChange(function(name)
    history.Load(name)
end)

-- the startup sound plays as HCrafter loads while you're in game, on the
-- first frame after you log in, and when /hcrafter shows the recipe book.
-- the shutdown sound plays when you log out, or when HCrafter unloads while
-- you're logged in.
local startupNext = false
-- the shutdown sound from your own character's settings, kept every frame:
-- at logout Ashita's settings library may switch to its default settings
-- before HCrafter hears of the logout
local farewell = { on = false, choice = '', volume = 100 }
local loggedIn = false
session.OnChange(function(name, old)
    if name == nil and old ~= nil then
        if loggedIn and farewell.on then
            fanfare.PlayChoice('shutdown', farewell.choice, farewell.volume)
        end
        loggedIn = false
        startupNext = false
    elseif name ~= nil and old == nil then
        -- the next frame, once every handler has seen the login
        startupNext = true
    end
end)

local function Print(message)
    print('[hcrafter] ' .. message)
end

---------------------------------------------------------------------------
-- synth tracking (from xitools crafty), craft levels and the alert after
-- your macro
---------------------------------------------------------------------------

local function IsMe(serverId)
    local player = GetPlayerEntity()
    return player ~= nil and serverId == player.ServerId
end

-- a packet that is shorter than expected is skipped, never an error
local function Parse(parser, data)
    if type(data) ~= 'string' then
        return nil
    end
    local ok, parsed = pcall(parser.parse, data)
    if ok then
        return parsed
    end
    return nil
end

-- the synth that just ended, so skill-up messages (which LandSandBoat
-- sends right after the result) land on it and not on an older one
local lastResult = nil
-- the last skill change per craft: a drop (310) is followed by message 53
-- with the lower level, which is not a level-up
local lastChange = { }

-- the game asked the server for a synth. guess the result from the
-- materials, since a break reports "Mangled Mess" as the item.
local function OnStartSynth(e)
    local startSynth = Parse(packets.outbound.startSynth, e.data)
    if startSynth == nil then
        return
    end
    local ingredients = { }
    for i = 0, math.min(7, startSynth.ingredientCount - 1) do
        local ingredient = startSynth.ingredient[i]
        if ingredient ~= nil and ingredient ~= 0 then
            table.insert(ingredients, ingredient)
        end
    end
    watch.OnRequest({ crystal = startSynth.crystal, ingredients = ingredients })

    -- a result that never arrived must not block tracking for good, and a
    -- request that never started (no synth effect after 3 seconds) gives
    -- way to the new one
    if inProgSynth ~= nil then
        if os.time() - (inProgSynth.startTime or 0) > 60 then
            inProgSynth = nil
        elseif inProgSynth.result == nil and os.clock() - (inProgSynth.requestClock or 0) > 3 then
            inProgSynth = nil
        end
    end
    if inProgSynth ~= nil then
        return
    end

    local crystal = crystalMap[startSynth.crystal]
    local key = recipes.IngredientKey(ingredients)
    local byCrystal = crystal and recipesByIngredients[crystal]
    local target = (byCrystal and byCrystal[key]) or { itemId = 0, count = 0 }
    local recipe = crystal and recipes.ByIngredients(crystal, ingredients) or nil

    local before = { }
    if recipe ~= nil then
        for craftId, level in ipairs(recipe.skills) do
            if level > 0 then
                before[craftId] = app.Skill(craftId)
            end
        end
    end

    inProgSynth = {
        startTime = os.time(),
        requestClock = os.clock(),
        result = nil,
        item = target.itemId or 0,
        count = target.count or 0,
        recipe = recipe and recipe.id or nil,
        estimate = recipe and app.Estimate(recipe) or nil,
        before = before,
        lost = nil,
        skillup = { },
    }
end

-- the recipe a synth result names. LandSandBoat lists the crystal and the
-- materials in the result (0x06f_combine_ans.cpp), so the result can say
-- what was made even when the request guess is wrong. nil when the result
-- does not list them or they match no recipe.
local function RecipeFromResult(synth)
    local crystal = crystalMap[synth.crystal or 0]
    if crystal == nil then
        return nil
    end
    local ids = { }
    for _, id in ipairs(synth.materials or { }) do
        if id ~= 0 and id ~= 65535 then
            table.insert(ids, id)
        end
    end
    if #ids == 0 then
        return nil
    end
    return recipes.ByIngredients(crystal, ids)
end

-- put the synth the result names in place of the guess
local function UseRecipe(recipe)
    if inProgSynth.recipe == recipe.id then
        return
    end
    local before = { }
    for craftId, level in ipairs(recipe.skills) do
        if level > 0 then
            -- skill-up messages come after the result, so your skill now is
            -- your skill before this synth
            before[craftId] = inProgSynth.before[craftId] or app.Skill(craftId)
        end
    end
    inProgSynth.recipe = recipe.id
    inProgSynth.item = recipe.result
    inProgSynth.count = recipe.count
    inProgSynth.before = before
    inProgSynth.estimate = app.Estimate(recipe)
end

local function OnSynthAnimation(e)
    local anim = Parse(packets.inbound.synthAnimation, e.data)
    if anim == nil or not IsMe(anim.player) then
        return
    end
    if inProgSynth ~= nil then
        inProgSynth.result = anim.param
    end
end

local function OnSynthResult(e)
    local synth = Parse(packets.inbound.synthResultPlayer, e.data)
    if synth == nil then
        return
    end
    lastResult = nil

    -- "you must wait longer": the request was refused, nothing started
    if synth.result == 0x0D then
        watch.OnAnswer(false)
        inProgSynth = nil
        return
    end

    -- the server cancelled the synth
    if synth.result == 3 or synth.result == 4 or synth.result == 6 or synth.result == 7 then
        watch.OnAnswer(false)
        inProgSynth = nil
        return
    end

    watch.OnAnswer(true)
    if inProgSynth == nil or not inProgSynth.startTime then
        return
    end

    -- an interrupted synth (zoning out mid-synth, say) loses everything
    if synth.result == 0x02 or synth.result == 0x0E then
        inProgSynth.result = 1
    end

    -- what the result says was made beats the guess from the request. with
    -- no materials listed, an NQ item that isn't the guessed recipe's
    -- result means the guess was for another request.
    local named = RecipeFromResult(synth)
    if named ~= nil then
        UseRecipe(named)
    elseif inProgSynth.result == 0 and synth.item ~= 29695 and inProgSynth.recipe ~= nil then
        local guessed = recipes.byId[inProgSynth.recipe]
        if guessed ~= nil and guessed.result ~= synth.item then
            inProgSynth.recipe = nil
            inProgSynth.estimate = nil
            inProgSynth.before = { }
        end
    end

    -- keep the guessed name instead of "Mangled Mess" when there is one
    if synth.item ~= 29695 or inProgSynth.item == 0 then
        inProgSynth.item = synth.item
        inProgSynth.count = synth.count
    end

    inProgSynth.lost = { }
    for _, itemId in pairs(synth.lost) do
        if itemId > 0 then
            table.insert(inProgSynth.lost, itemId)
        end
    end

    for _, skill in pairs(synth.skill) do
        if skill.skillId > 48 and skill.skillId < 57 then
            local craftId = skill.skillId - 48
            inProgSynth.skillup[craftId] = {
                change = nil,
                before = inProgSynth.before[craftId] or app.Skill(craftId),
            }
        end
    end

    local done = inProgSynth
    inProgSynth = nil
    local estimate = done.estimate
    done.estimate = nil
    done.before = nil
    done.requestClock = nil
    history.Add(done)
    lastResult = { entry = done, clock = os.clock() }

    if done.result == 1 then
        fanfare.Break(config.fanfare, done.item, done.lost)
    elseif done.result ~= nil and done.result >= 2 then
        fanfare.HQ(config.fanfare, done.item, done.count, done.result, hq.OutcomeChance(estimate, done.result))
    end
end

-- skill-up (38), level-up (53) and skill-down (310) for crafts 49 to 56,
-- and "you must wait longer" (94)
local function OnBasicMessage(e)
    local basic = Parse(packets.inbound.basic, e.data)
    if basic == nil or not IsMe(basic.target) then
        return
    end

    if basic.message == 94 then
        -- the macro line was answered, refused. it only counts while a
        -- synth request is waiting.
        watch.OnAnswer(false)
        -- a synth request refused moments ago never started, so the next
        -- synth must not inherit its guess
        if inProgSynth ~= nil and inProgSynth.result == nil and os.clock() - (inProgSynth.requestClock or 0) < 3 then
            inProgSynth = nil
        end
        return
    end

    if basic.param < 49 or basic.param > 56 then
        return
    end
    local craftId = basic.param - 48

    if basic.message == 53 then
        if basic.value < 1 or basic.value > 110 then
            return
        end
        -- after a drop, 53 carries the lower level: no fanfare for that
        local last = lastChange[craftId]
        if last ~= nil and last.change < 0 and os.clock() - last.clock < 10 then
            return
        end
        fanfare.LevelUp(config.fanfare, craftId, basic.value)
        return
    end
    if basic.message ~= 38 and basic.message ~= 310 then
        return
    end
    -- a skill change is a few tenths. anything else is not a skill change.
    if basic.value < 1 or basic.value > 100 then
        return
    end

    local change = basic.value / 10
    if basic.message == 310 then
        change = -change
    end
    lastChange[craftId] = { change = change, clock = os.clock() }

    -- the synth that just ended, and whether its recipe still gave
    -- skill-ups. a skill change long after any result belongs to no synth.
    local latest = nil
    if lastResult ~= nil and os.clock() - lastResult.clock < 10 then
        latest = lastResult.entry
    end
    local recipe = latest and latest.recipe and recipes.byId[latest.recipe] or nil
    local bandBefore = nil
    if recipe ~= nil and (recipe.skills[craftId] or 0) > 0 then
        bandBefore = skillup.Band(recipe.skills[craftId], app.Skill(craftId), 0, app.Cap(craftId))
    end

    -- rounded to one decimal, so ten 0.1 skill-ups land exactly on a level
    local skill = config.skills[craftId]
    if skill ~= nil then
        local level = math.floor(((tonumber(skill[1]) or 0) + change) * 10 + 0.5) / 10
        skill[1] = math.max(0, math.min(110, level))
        MarkDirty()
    end

    if latest ~= nil and type(latest.skillup) == 'table' and latest.skillup[craftId] ~= nil then
        latest.skillup[craftId].change = change
        history.Changed()
    end

    fanfare.SkillUp(config.fanfare, craftId, change, skill and skill[1] or 0)

    if bandBefore ~= nil and bandBefore ~= 'none' then
        local bandAfter = skillup.Band(recipe.skills[craftId], app.Skill(craftId), 0, app.Cap(craftId))
        if bandAfter == 'none' then
            fanfare.NoMoreSkillups(craftId, math.floor(app.Skill(craftId) + 0.0001), recipe.result)
        end
    end
end

-- the skills packet carries your whole craft levels and guild ranks.
-- decimals stay as they are while the whole level agrees.
local function OnSkills(e)
    local update = Parse(packets.inbound.charSkills, e.data)
    if update == nil then
        return
    end
    local anyLevel = false
    for craftId = 1, 8 do
        local craft = update.craftSkills[craftId]
        if craft ~= nil and (craft.level > 0 or craft.rank > 0) then
            anyLevel = true
        end
    end

    -- an all-zero packet would wipe real levels, so it is ignored
    if not anyLevel then
        return
    end

    local changed = false
    for craftId = 1, 8 do
        local craft = update.craftSkills[craftId]
        if craft ~= nil then
            if config.ranks[craftId][1] ~= craft.rank then
                config.ranks[craftId][1] = craft.rank
                changed = true
            end
            if config.capped[craftId][1] ~= craft.isCapped then
                config.capped[craftId][1] = craft.isCapped
                changed = true
            end
            local skill = config.skills[craftId]
            if config.autoSkills[1] and skill ~= nil and math.floor(skill[1] + 0.0001) ~= craft.level then
                skill[1] = craft.level
                changed = true
            end
        end
    end

    if changed then
        MarkDirty()
    end
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------

ashita.events.register('load', 'hcrafter_load', function()
    -- fonts can only be added here, never in the middle of a frame
    text.Load()
    sounds.Refresh()
    -- out-of-date copies go, and the folder keeps at most sounds.maxCopies.
    -- at the title screen these are Ashita's default settings, so a
    -- character's own copies are only ever trimmed oldest first.
    sounds.Tidy(PickedSounds(), fanfare.Volume())
    WarmPicked()
    session.OnLoad()
    -- loaded while you're in game: the startup sound plays right away, and
    -- only once
    if session.name ~= nil then
        startupNext = false
        fanfare.Sound('startup')
    end
    stock.LoadOthers()
    prices.Load(true)
end)

ashita.events.register('unload', 'hcrafter_unload', function()
    if session.name ~= nil then
        fanfare.Sound('shutdown')
    end
    stock.OnUnload()
    history.Save()
    settings.save()
end)

ashita.events.register('packet_out', 'hcrafter_packet_out', function(e)
    if e.id == 0x096 then
        OnStartSynth(e)
    end
end)

ashita.events.register('packet_in', 'hcrafter_packet_in', function(e)
    if e.id == 0x030 then
        OnSynthAnimation(e)
    elseif e.id == 0x06F then
        OnSynthResult(e)
    elseif e.id == 0x029 then
        OnBasicMessage(e)
    elseif e.id == 0x062 then
        OnSkills(e)
    elseif e.id == 0x00A then
        -- zoning is a good moment to write: the screen is loading anyway
        inProgSynth = nil
        lastResult = nil
        watch.OnZone()
        icons.Reset()
        history.Save()
        stock.OnZoneIn()
        session.OnZoneIn(e.data)
        prices.Load(false)
    elseif e.id == 0x00B then
        history.Save()
        session.OnZoneOut(e.data)
    elseif e.id == 0x01D then
        session.OnInventoryFinish()
    end
end)

local function PrintHelp()
    Print('/hcrafter                show or hide the recipe book')
    Print('/hcrafter plan           show or hide the Resource Planner')
    Print('/hcrafter list           show or hide the Shopping list')
    Print('/hcrafter price <item> <gil>   set a price (no gil clears it)')
    Print('/hcrafter prices         read prices.csv again')
    Print('/hcrafter save           save this character\'s bags now')
    Print('/hcrafter clear          clear the craft history')
    Print('/hcraft works the same as /hcrafter')
end

local function PriceCommand(args)
    -- /hcrafter price ebony lumber 1200, or with no number to clear
    local words = { }
    for i = 3, #args do
        table.insert(words, args[i])
    end
    if #words == 0 then
        Print('Usage: /hcrafter price <item name> <gil>')
        return
    end
    local amount = nil
    if #words > 1 and prices.ParsePrice(words[#words]) ~= nil then
        amount = table.remove(words)
    end
    local name = table.concat(words, ' ')
    local itemId = prices.Find(name)
    if itemId == nil then
        Print(('No recipe uses an item called "%s".'):format(name))
        return
    end
    local ok, why = prices.Set(itemId, amount)
    if not ok then
        Print(('Price not saved: %s.'):format(why or 'unknown reason'))
    elseif amount == nil then
        Print(('Cleared the price of %s.'):format(items.ShortName(itemId)))
    else
        Print(('%s: %s gil each.'):format(items.ShortName(itemId), prices.Format(prices.Get(itemId))))
    end
end

ashita.events.register('command', 'hcrafter_command', function(e)
    local args = e.command:args()
    if #args == 0 then
        return
    end

    local command = args[1]:lower()
    if command ~= '/hcrafter' and command ~= '/hcraft' then
        return
    end

    e.blocked = true
    local verb = args[2] and args[2]:lower() or nil

    if verb == nil then
        config.book.visible[1] = not config.book.visible[1]
        if config.book.visible[1] then
            fanfare.Sound('startup')
        end
    elseif verb == 'plan' or verb == 'planner' then
        config.planner.visible[1] = not config.planner.visible[1]
    elseif verb == 'list' then
        config.tracker.visible[1] = not config.tracker.visible[1]
    elseif verb == 'clear' then
        history.Clear()
        Print('Craft history cleared.')
    elseif verb == 'save' then
        local saved, why = stock.SaveCurrent(true)
        if saved then
            Print('Saved this character\'s bags.')
        else
            Print(('Not saved: %s.'):format(why or 'unknown reason'))
        end
    elseif verb == 'prices' then
        local n, skipped = prices.Load(true)
        Print(('Read %i prices%s.'):format(n, skipped > 0 and (', skipped ' .. skipped .. ' lines') or ''))
    elseif verb == 'price' then
        PriceCommand(args)
    else
        PrintHelp()
    end
    MarkDirty()
end)

-- a number from a settings value, or the fallback for anything that isn't
-- one (text, NaN, infinity), kept between low and high
local function Setting(value, fallback, low, high)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        value = fallback
    end
    return math.max(low, math.min(high, value))
end

-- the look settings, applied once a frame
local function ApplyLook()
    local look = config.look
    -- Size, times Ashita's own font size when the player wants HCrafter to
    -- grow with it (2 for a font doubled for a 4K screen)
    local base = look.matchAshita[1] == true and ui.AshitaScale() or 1
    ui.size = Setting(look.scale[1], 1, 0.75, 1.5)
    ui.S = base * ui.size
    ui.frame = look.frame[1] == 2 and 2 or 1
    ui.bgAlpha = Setting(look.alpha[1], 0.92, 0.4, 1)
    ui.gameIcons = look.gameIcons[1] == true
    icons.enabled = ui.gameIcons
    if text.useGame ~= (look.gameFont[1] == true) then
        text.useGame = look.gameFont[1] == true
        text.Reset()
    end
    local textScale = Setting(look.text[1], 1, 0.8, 1.3)
    if text.scale ~= textScale then
        text.scale = textScale
        text.Reset()
    end
end

-- each window draws on its own: an error in one closes what it left open
-- in imgui, and the others still draw
local function DrawWindow(name, draw)
    guard.Run(name, draw)
    -- a window over the game world turns on the full text outline, and one
    -- that stopped early never turned it off
    text.full = false
end

local function InventoryCount(itemId)
    local onYou = stock.Counts(itemId)
    return onYou
end

ashita.events.register('d3d_present', 'hcrafter_present', function()
    app.NewFrame()
    icons.NewFrame()
    stock.Tick()
    history.Tick()
    -- at most one game sound turned into a .wav file a frame. a file that
    -- can't be made never stops the frame.
    pcall(sounds.Tick)
    if startupNext then
        startupNext = false
        fanfare.Sound('startup')
    end
    if session.name ~= nil then
        local ref = config.sounds.shutdown
        farewell.on = config.fanfare.sound[1] == true
        farewell.choice = type(ref) == 'table' and ref[1] or ''
        farewell.volume = fanfare.Volume()
        loggedIn = true
    end

    -- settings no longer hold the history, so a save here is small
    if dirtyAt ~= nil and os.clock() - dirtyAt > 5 then
        dirtyAt = nil
        settings.save()
    end

    if GetPlayerEntity() == nil then
        return
    end

    -- the alert after your macro: once when the synths in a row are done,
    -- or when you run out of a material
    local alert, detail = watch.Tick(InventoryCount, app.AlertEvery())
    if alert ~= nil and config.ready.enabled[1] then
        if alert == 'short' then
            fanfare.OutOf(detail)
        else
            fanfare.SynthsDone(detail)
        end
    end

    if config.hideUnderMap[1] and game.IsMapOpen() then
        return
    end
    if config.hideDuringEvent[1] and game.IsEventHappening() then
        return
    end
    if config.hideWithInterface[1] and game.IsInterfaceHidden() then
        return
    end

    ApplyLook()
    guard.NewFrame()
    DrawWindow('The recipe book', book.Draw)
    DrawWindow('The Resource Planner', planui.Draw)
    DrawWindow('The Shopping list', tracker.Draw)
    DrawWindow('The fanfare', fanfare.Draw)
    DrawWindow('A tooltip', ui.FlushTip)
end)
