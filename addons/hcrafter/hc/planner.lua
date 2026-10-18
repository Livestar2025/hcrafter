-- shopping list math. given the recipes you want to synth and which
-- materials you will make yourself, works out every synth and every item to
-- buy. what you already hold is used once per item, before that item's own
-- materials are counted, so held intermediates cut the synths below them.
local planner = { }

-- whole-number "round up after adding spare %": n * (100 + spare) / 100
local function WithSpare(count, spare)
    if count <= 0 then
        return 0
    end
    return math.floor((count * (100 + spare) + 99) / 100)
end

planner.WithSpare = WithSpare

-- entries:  { { recipe = recipe, synths = n }, ... }
-- choose:   function(itemId) -> the recipe you will make it with, or nil to buy
-- have:     function(itemId) -> how many you hold that may be used
-- grouped:  function(recipe) -> { { id = itemId, count = n }, ... }
-- spare:    extra synths at every step, in percent (whole number, 0 = none)
function planner.Build(entries, choose, have, grouped, spare)
    spare = math.max(0, math.floor(tonumber(spare) or 0))

    local level = { }   -- deepest position of each item in the plan
    local loops = { }   -- items that would end up inside their own recipe
    local maxLevel = 0

    -- give every item its deepest level, so all demand for it is known
    -- before it is worked out
    local function Visit(itemId, depth, path)
        if path[itemId] then
            -- the item is inside its own recipe chain. it is bought instead,
            -- but it still needs a level so its demand is counted.
            loops[itemId] = true
            if level[itemId] == nil or level[itemId] < depth then
                level[itemId] = depth
                if depth > maxLevel then
                    maxLevel = depth
                end
            end
            return
        end
        if level[itemId] ~= nil and level[itemId] >= depth then
            return
        end

        level[itemId] = depth
        if depth > maxLevel then
            maxLevel = depth
        end

        local recipe = choose(itemId)
        if recipe ~= nil then
            path[itemId] = true
            for _, ingredient in ipairs(grouped(recipe)) do
                Visit(ingredient.id, depth + 1, path)
            end
            Visit(recipe.crystal, depth + 1, path)
            path[itemId] = nil
        end
    end

    local gross = { }
    local top = { }
    local keyItems = { }

    for _, entry in ipairs(entries) do
        local recipe = entry.recipe
        local synths = WithSpare(math.max(0, math.floor(entry.synths or 0)), spare)
        table.insert(top, { recipe = recipe, synths = synths, output = synths * recipe.count, asked = entry.synths })

        if synths > 0 then
            if recipe.keyItem > 0 then
                keyItems[recipe.keyItem] = true
            end

            for _, ingredient in ipairs(grouped(recipe)) do
                gross[ingredient.id] = (gross[ingredient.id] or 0) + synths * ingredient.count
                Visit(ingredient.id, 1, { [recipe.result] = true })
            end
            gross[recipe.crystal] = (gross[recipe.crystal] or 0) + synths
            Visit(recipe.crystal, 1, { [recipe.result] = true })
        end
    end

    local order = { }
    for itemId in pairs(level) do
        table.insert(order, itemId)
    end
    table.sort(order, function(a, b)
        if level[a] ~= level[b] then
            return level[a] < level[b]
        end
        return a < b
    end)

    local made = { }
    local buy = { }

    for _, itemId in ipairs(order) do
        local need = gross[itemId] or 0
        local held = math.max(0, math.floor(have(itemId) or 0))
        local used = math.min(held, need)
        local net = need - used
        local recipe = nil
        if not loops[itemId] then
            recipe = choose(itemId)
        end

        if recipe ~= nil then
            local synths = 0
            if net > 0 then
                synths = WithSpare(math.ceil(net / recipe.count), spare)
            end

            if synths > 0 then
                if recipe.keyItem > 0 then
                    keyItems[recipe.keyItem] = true
                end
                for _, ingredient in ipairs(grouped(recipe)) do
                    gross[ingredient.id] = (gross[ingredient.id] or 0) + synths * ingredient.count
                end
                gross[recipe.crystal] = (gross[recipe.crystal] or 0) + synths
            end

            if need > 0 then
                table.insert(made, {
                    id = itemId,
                    recipe = recipe,
                    need = need,
                    used = used,
                    synths = synths,
                    output = synths * recipe.count,
                    leftover = synths * recipe.count - net,
                    level = level[itemId],
                })
            end
        elseif need > 0 then
            table.insert(buy, {
                id = itemId,
                need = need,
                used = used,
                buy = net,
                level = level[itemId],
            })
        end
    end

    -- craft order: deepest steps first, the queued recipes last
    table.sort(made, function(a, b)
        if a.level ~= b.level then
            return a.level > b.level
        end
        return a.id < b.id
    end)

    return {
        top = top,
        made = made,
        buy = buy,
        keyItems = keyItems,
        loops = loops,
        spare = spare,
    }
end

-- how to buy n of an item that stacks to stackSize, such as
-- "2 stacks + 3, or 3 stacks (9 spare)"
function planner.StackText(n, stackSize)
    if n <= 0 then
        return 'none'
    end
    if stackSize == nil or stackSize <= 1 then
        return ('%i'):format(n)
    end

    local full = math.floor(n / stackSize)
    local rest = n % stackSize
    if rest == 0 then
        return ('%i stack%s'):format(full, full == 1 and '' or 's')
    end
    if full == 0 then
        return ('%i single%s, or 1 stack (%i spare)'):format(rest, rest == 1 and '' or 's', stackSize - rest)
    end

    return ('%i stack%s + %i, or %i stacks (%i spare)'):format(
        full, full == 1 and '' or 's', rest, full + 1, stackSize - rest)
end

return planner
