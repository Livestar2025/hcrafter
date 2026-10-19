-- the alert after your /lastsynth macro. it counts your synth requests,
-- one per macro line, refused or not, and speaks up once: when a set number
-- in a row have been answered, or when you are out of a material for
-- another synth like the last one. it only watches: it never presses your
-- macro and never sends anything.
local watch = {
    clock = os.clock,
    -- no new request this long after the last answer: the run is over and
    -- the next request starts a new count
    gap = 25,
    -- seconds after a result before the materials are checked, so the
    -- inventory has caught up with what the synth used
    settle = 2,
    -- a request with no answer this long counts as answered
    lost = 30,
    -- how long "Out of" stays up when nothing changes
    expire = 120,
}

local st = {
    -- synth requests in this run
    count = 0,
    -- the last request or answer
    lastAt = nil,
    -- a request is waiting for its answer
    waiting = false,
    -- when the last request was answered, until the answer is looked at
    answeredAt = nil,
    -- the last answer was a synth that used materials: check them
    check = false,
    -- the crystal and materials the last request used: { { id, count }, ... }
    request = nil,
    -- the alert count, as of the last frame
    every = 6,
    -- a run that reached the alert count when a new request came first
    doneNext = nil,
    missing = nil,
    missingAt = nil,
    lastCheck = nil,
}

local function NewRun()
    st.count = 0
    st.lastAt = nil
    st.waiting = false
    st.answeredAt = nil
    st.check = false
end

-- 0x096 left the client: a synth request, which is one line of a macro.
-- request: { crystal = id, ingredients = { ids } }
function watch.OnRequest(request)
    local now = watch.clock()
    -- the last run reached the alert count but its answer was still being
    -- looked at: it alerts now, and this request starts a new run
    if st.answeredAt ~= nil and st.count >= st.every then
        st.doneNext = st.count
        NewRun()
    elseif st.lastAt == nil or (not st.waiting and now - st.lastAt > watch.gap) then
        st.count = 0
    end
    st.count = st.count + 1
    st.lastAt = now
    st.waiting = true
    st.answeredAt = nil
    -- the client only asks when the materials are there, and the server
    -- takes the crystal as the synth starts. a check still waiting from the
    -- last result would miss that crystal, so it is dropped.
    st.check = false
    st.missing = nil
    st.missingAt = nil

    local order, index = { }, { }
    local function Add(id)
        if id ~= nil and id > 0 then
            if index[id] == nil then
                order[#order + 1] = { id, 0 }
                index[id] = #order
            end
            local entry = order[index[id]]
            entry[2] = entry[2] + 1
        end
    end
    Add(request.crystal)
    for _, id in ipairs(request.ingredients or { }) do
        Add(id)
    end
    st.request = order
end

-- the server answered: made is true for a synth that happened (made
-- something, HQ, broke or was interrupted) and false for a refused or
-- cancelled one. an answer with no request seen counts only if a synth
-- happened.
function watch.OnAnswer(made)
    local now = watch.clock()
    if not st.waiting then
        if not made then
            return
        end
        -- the request was missed: this synth still counts
        if st.lastAt == nil or now - st.lastAt > watch.gap then
            st.count = 0
        end
        st.count = st.count + 1
    end
    st.lastAt = now
    st.waiting = false
    st.answeredAt = now
    st.check = made == true
end

function watch.OnZone()
    NewRun()
    st.request = nil
    st.doneNext = nil
end

-- the first item you are short of for another synth like the last one:
-- the crystal first, then the materials in the order they were used
local function Missing(countOf)
    for _, entry in ipairs(st.request or { }) do
        if (countOf(entry[1]) or 0) < entry[2] then
            return entry[1]
        end
    end
    return nil
end

-- call once a frame. countOf(id) is how many of an item are in your
-- inventory, every the macro lines in a row to alert after. returns 'done'
-- and the count, or 'short' and the item you are out of, on the frame to
-- alert. nil otherwise.
function watch.Tick(countOf, every)
    local now = watch.clock()
    every = math.max(1, math.floor(tonumber(every) or 6))
    st.every = every

    if st.doneNext ~= nil then
        local done = st.doneNext
        st.doneNext = nil
        return 'done', done
    end

    -- a request whose answer never came
    if st.waiting and st.lastAt ~= nil and now - st.lastAt > watch.lost then
        st.waiting = false
        st.answeredAt = now - watch.settle
        st.check = false
    end

    if st.answeredAt ~= nil then
        if now < st.answeredAt + watch.settle then
            return nil
        end
        st.answeredAt = nil
        if st.check then
            st.check = false
            local missing = Missing(countOf)
            if missing ~= nil then
                -- the macro can't go on, so the next request starts a new run
                NewRun()
                st.missing = missing
                st.missingAt = now
                st.lastCheck = now
                return 'short', missing
            end
        end
        if st.count >= every then
            local done = st.count
            NewRun()
            return 'done', done
        end
        return nil
    end

    -- "Out of" goes away once the material is back, or after a while
    if st.missing ~= nil then
        if now - (st.missingAt or now) > watch.expire then
            st.missing = nil
        elseif now - (st.lastCheck or 0) >= 1 then
            st.lastCheck = now
            if Missing(countOf) == nil then
                st.missing = nil
            end
        end
    end
    return nil
end

-- what the Shopping list shows: requests so far in this run, and the item
-- you are out of (or nil). a run that has been quiet past the gap shows 0.
function watch.State()
    local count = st.count
    if count > 0 and not st.waiting and st.answeredAt == nil and st.lastAt ~= nil and watch.clock() - st.lastAt > watch.gap then
        count = 0
    end
    return count, st.missing
end

return watch
