-- AfternightCustomSongs - safe synthetic tap-test UI for Madium
--
-- IMPORTANT: This is a runtime validation harness, NOT a full custom-song
-- playback loader. It calls parseChart exactly once after an explicit button
-- click. It does not directly call startSong, fire remotes, change scores, or download
-- external code. A client rejoin is required after the test because parser-made
-- Strums/Strumlines and possible module registries are not safely reversible.
--
-- Evidence used: repository HANDOFF.md + forensic audit in this conversation.
-- parseChart(wrapper, {}, nil, nil) is the one previously observed call shape,
-- but its arity/optional arguments are NOT a fully verified public contract.

local TARGET_PLACE_ID = 13042495892
local GUI_NAME = "AfternightCustomSongs_TestLoader"
local EXPECTED_TIMES = { 1200, 1800, 2400, 3000 }

local CONDUCTOR_FIELDS = {
    "BPM", "BaseBPM", "CurBPM", "Offset", "Crochet", "StepCrochet",
    "BeatsPerMeasure", "StepsPerBeat", "SongPosition", "TimePosition", "Paused",
}

local state = {
    module = nil,
    baseline = nil,
    ready = false,
    ran = false,
    cleaned = false,
    candidates = 0,
    gui = nil,
    status = nil,
    logLabel = nil,
    logScroll = nil,
    runButton = nil,
    cleanButton = nil,
}

local function log(message)
    message = tostring(message)
    print("[AfternightCustomSongs] " .. message)
    if not state.logLabel then
        return
    end
    local old = state.logLabel.Text or ""
    local combined = old == "" and message or (old .. "\n" .. message)
    local lines = {}
    for line in (combined .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    while #lines > 90 do
        table.remove(lines, 1)
    end
    state.logLabel.Text = table.concat(lines, "\n")
    task.defer(function()
        -- Best-effort scroll: the UI may be closed before this fires.
        pcall(function()
            if state.logScroll and state.logLabel then
                state.logScroll.CanvasSize = UDim2.fromOffset(0, state.logLabel.TextBounds.Y + 16)
                state.logScroll.CanvasPosition = Vector2.new(0, math.max(0, state.logScroll.CanvasSize.Y.Offset))
            end
        end)
    end)
end

local function setStatus(message, good)
    if state.status then
        state.status.Text = message
        state.status.TextColor3 = good and Color3.fromRGB(137, 230, 174) or Color3.fromRGB(255, 202, 124)
    end
end

local function setButtonEnabled(button, enabled)
    if not button then return end
    button.Active = enabled
    button.AutoButtonColor = enabled
    button.TextTransparency = enabled and 0 or 0.4
    button.BackgroundColor3 = enabled and Color3.fromRGB(66, 91, 166) or Color3.fromRGB(53, 57, 70)
end

local function tableCount(value)
    if type(value) ~= "table" then return -1 end
    local count = 0
    for _ in next, value do count += 1 end
    return count
end

local function safeGet(tbl, key)
    if type(tbl) ~= "table" then return nil end
    local ok, value = pcall(rawget, tbl, key)
    if ok then return value end
    return nil
end

local function deepClone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in next, value do
        local copiedKey = deepClone(key, seen)
        copy[copiedKey] = deepClone(child, seen)
    end
    return copy
end

local function clearTableInPlace(tbl)
    if type(tbl) ~= "table" then return false end
    for key in next, tbl do
        rawset(tbl, key, nil)
    end
    return true
end

local function captureNested(parent, key)
    local value = safeGet(parent, key)
    return {
        present = value ~= nil,
        value = value,
        isTable = type(value) == "table",
        ref = type(value) == "table" and value or nil,
        data = type(value) == "table" and deepClone(value) or nil,
    }
end

local function restoreNested(parent, key, snapshot)
    if type(parent) ~= "table" or type(snapshot) ~= "table" then return false end
    if not snapshot.present then
        rawset(parent, key, nil)
        return true
    end
    if snapshot.isTable and type(snapshot.ref) == "table" then
        clearTableInPlace(snapshot.ref)
        local restored = deepClone(snapshot.data or {})
        for entryKey, entryValue in next, restored do
            rawset(snapshot.ref, entryKey, entryValue)
        end
        rawset(parent, key, snapshot.ref)
    else
        rawset(parent, key, snapshot.value)
    end
    return true
end

local function findGameplayModules()
    if type(getgc) ~= "function" then
        return nil, "Madium getgc(true) is unavailable in this execution environment."
    end
    local ok, objects = pcall(function() return getgc(true) end)
    if not ok or type(objects) ~= "table" then
        return nil, "getgc(true) failed: " .. tostring(objects)
    end

    local found = {}
    for _, obj in next, objects do
        if type(obj) == "table"
            and type(safeGet(obj, "parseChart")) == "function"
            and type(safeGet(obj, "addNotesFromChart")) == "function"
            and type(safeGet(obj, "Notes")) == "table"
            and type(safeGet(obj, "UnspawnedNotes")) == "table" then
            found[#found + 1] = obj
        end
    end
    return found
end

local function getMapTable(mod)
    local mapModule = safeGet(mod, "mapModule")
    if type(mapModule) ~= "table" then return nil end
    local maps = safeGet(mapModule, "Maps")
    if type(maps) == "table" then return maps end
    return nil
end

local function captureSnapshot(mod)
    local snap = {
        NotesRef = safeGet(mod, "Notes"),
        UnspawnedNotesRef = safeGet(mod, "UnspawnedNotes"),
        Notes = tableCount(safeGet(mod, "Notes")),
        UnspawnedNotes = tableCount(safeGet(mod, "UnspawnedNotes")),
        Strums = tableCount(safeGet(mod, "Strums")),
        Strumlines = tableCount(safeGet(mod, "Strumlines")),
        Maps = tableCount(getMapTable(mod)),
    }

    local conductor = safeGet(mod, "Conductor")
    snap.conductorRef = conductor
    snap.conductorFields = {}
    if type(conductor) == "table" then
        for _, field in ipairs(CONDUCTOR_FIELDS) do
            local value = safeGet(conductor, field)
            snap.conductorFields[field] = { present = value ~= nil, value = value }
        end
        snap.bpmChangeMap = captureNested(conductor, "BPMChangeMap")
        snap.lastBPMChange = captureNested(conductor, "lastBPMChange")
    end

    local sv = safeGet(mod, "svFunctions")
    snap.svRef = sv
    if type(sv) == "table" then
        snap.sliderVelocities = captureNested(sv, "sliderVelocities")
    end

    local songPlayer = safeGet(mod, "songPlayer")
    if type(songPlayer) == "table" then
        snap.songPlayer = {
            timePosition = safeGet(songPlayer, "timePosition"),
            timeLength = safeGet(songPlayer, "timeLength"),
            paused = safeGet(songPlayer, "paused"),
            curPath = safeGet(songPlayer, "curPath"),
        }
    end
    return snap
end

local function restoreSnapshot(mod, snap)
    if type(mod) ~= "table" or type(snap) ~= "table" then
        error("No valid baseline snapshot exists.")
    end

    local notes = snap.NotesRef
    local unspawned = snap.UnspawnedNotesRef
    if type(notes) ~= "table" or type(unspawned) ~= "table" then
        error("Baseline note-pool references were not captured; refusing cleanup.")
    end
    -- Clear both current and original pools if the parser replaced a pool, then
    -- restore the original table identities captured before the test.
    local currentNotes = safeGet(mod, "Notes")
    local currentUnspawned = safeGet(mod, "UnspawnedNotes")
    if type(currentNotes) == "table" then clearTableInPlace(currentNotes) end
    if type(currentUnspawned) == "table" then clearTableInPlace(currentUnspawned) end
    clearTableInPlace(notes)
    clearTableInPlace(unspawned)
    rawset(mod, "Notes", notes)
    rawset(mod, "UnspawnedNotes", unspawned)

    local conductor = snap.conductorRef
    if type(conductor) == "table" then
        rawset(mod, "Conductor", conductor)
        for _, field in ipairs(CONDUCTOR_FIELDS) do
            local item = snap.conductorFields[field]
            if item and item.present then
                rawset(conductor, field, item.value)
            else
                rawset(conductor, field, nil)
            end
        end
        restoreNested(conductor, "BPMChangeMap", snap.bpmChangeMap)
        restoreNested(conductor, "lastBPMChange", snap.lastBPMChange)
    end

    if type(snap.svRef) == "table" then
        rawset(mod, "svFunctions", snap.svRef)
        restoreNested(snap.svRef, "sliderVelocities", snap.sliderVelocities)
    end
end

local function serialize(value, seen, depth)
    local kind = type(value)
    if kind == "nil" then return "nil" end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if kind == "string" then return string.format("%q", value) end
    if kind ~= "table" then return "<" .. kind .. ">" end
    if (depth or 0) > 8 then return "<depth>" end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local pieces = {}
    for key, child in next, value do
        pieces[#pieces + 1] = serialize(key, seen, (depth or 0) + 1) .. "=" .. serialize(child, seen, (depth or 0) + 1)
    end
    table.sort(pieces)
    seen[value] = nil
    return "{" .. table.concat(pieces, ",") .. "}"
end

local function baselineIsClean(snap)
    local required = { "Notes", "UnspawnedNotes", "Strums", "Strumlines", "Maps" }
    for _, field in ipairs(required) do
        if snap[field] ~= 0 then
            return false, field .. " count is " .. tostring(snap[field]) .. "; expected 0. Rejoin the client and retry."
        end
    end
    local con = snap.conductorFields or {}
    local tp = con.TimePosition and con.TimePosition.value
    local sp = con.SongPosition and con.SongPosition.value
    if type(tp) == "number" and math.abs(tp) > 250 then
        return false, "Conductor.TimePosition is " .. tostring(tp) .. "; the engine may not be idle."
    end
    if type(sp) == "number" and math.abs(sp) > 250 then
        return false, "Conductor.SongPosition is " .. tostring(sp) .. "; the engine may not be idle."
    end
    if snap.songPlayer then
        local audio = snap.songPlayer
        if type(audio.timePosition) == "number" and audio.timePosition > 250 then
            return false, "songPlayer.timePosition is " .. tostring(audio.timePosition) .. "; the engine may not be idle."
        end
        if type(audio.timeLength) == "number" and audio.timeLength > 0 and audio.paused == false then
            return false, "songPlayer has a non-paused transport; refusing to test during playback."
        end
    end
    return true, "clean idle baseline"
end

local function describeSnapshot(label, snap)
    log(label .. ": Notes=" .. tostring(snap.Notes)
        .. ", UnspawnedNotes=" .. tostring(snap.UnspawnedNotes)
        .. ", Strums=" .. tostring(snap.Strums)
        .. ", Strumlines=" .. tostring(snap.Strumlines)
        .. ", Maps=" .. tostring(snap.Maps))
    if snap.conductorFields then
        local parts = {}
        for _, field in ipairs({ "BPM", "BaseBPM", "CurBPM", "Offset", "TimePosition" }) do
            local item = snap.conductorFields[field]
            parts[#parts + 1] = field .. "=" .. tostring(item and item.value)
        end
        log(label .. " Conductor: " .. table.concat(parts, ", "))
    end
    if snap.sliderVelocities and snap.sliderVelocities.isTable then
        log(label .. " sliderVelocities entries=" .. tostring(tableCount(snap.sliderVelocities.ref)))
    end
    if snap.songPlayer then
        log(label .. " audio transport: timePosition=" .. tostring(snap.songPlayer.timePosition)
            .. ", timeLength=" .. tostring(snap.songPlayer.timeLength)
            .. ", paused=" .. tostring(snap.songPlayer.paused))
    end
end

local function prepareEngine()
    if game.PlaceId ~= TARGET_PLACE_ID then
        state.module = nil
        state.baseline = nil
        state.ready = false
        setStatus("Wrong experience: PlaceId " .. tostring(game.PlaceId), false)
        setButtonEnabled(state.runButton, false)
        log("ABORT: expected PlaceId " .. TARGET_PLACE_ID .. ", got " .. tostring(game.PlaceId) .. ".")
        return false
    end

    local candidates, err = findGameplayModules()
    if not candidates then
        state.module = nil
        state.baseline = nil
        state.ready = false
        setStatus("Engine discovery failed", false)
        setButtonEnabled(state.runButton, false)
        log("ABORT: " .. tostring(err))
        return false
    end
    state.candidates = #candidates
    if #candidates ~= 1 then
        state.module = nil
        state.baseline = nil
        state.ready = false
        setStatus("Found " .. #candidates .. " candidate modules; need exactly one", false)
        setButtonEnabled(state.runButton, false)
        log("ABORT: expected one unambiguous gameplay module; found " .. #candidates .. ".")
        return false
    end

    state.module = candidates[1]
    local snap = captureSnapshot(state.module)
    describeSnapshot("Current", snap)
    local clean, reason = baselineIsClean(snap)
    if not clean then
        state.ready = false
        if not state.ran then state.baseline = nil end
        setStatus("Not idle — test disabled", false)
        setButtonEnabled(state.runButton, false)
        log("ABORT: " .. reason)
        return false
    end

    if not state.ran then
        state.baseline = snap
        state.ready = true
        setStatus("Engine found; clean baseline. Ready for one tap test.", true)
        setButtonEnabled(state.runButton, true)
        log("Preflight OK. The test is still opt-in: click Run 4-Tap Test to make one parser call.")
    else
        setStatus("Test already attempted; rejoin before another run.", false)
        setButtonEnabled(state.runButton, false)
    end
    return true
end

local function collectNotes(mod)
    local result, seen = {}, {}
    for _, poolName in ipairs({ "UnspawnedNotes", "Notes" }) do
        local pool = safeGet(mod, poolName)
        if type(pool) == "table" then
            for _, note in next, pool do
                if type(note) == "table" and not seen[note] then
                    seen[note] = true
                    result[#result + 1] = { note = note, pool = poolName }
                end
            end
        end
    end
    return result
end

local function sampleNote(note, poolName, index)
    local section = safeGet(note, "section")
    local mustHit = safeGet(section, "mustHitSection")
    local rawData = safeGet(note, "rawData")
    local rawLane = type(rawData) == "table" and safeGet(rawData, 2) or nil
    local fields = {
        "strumTime=" .. tostring(safeGet(note, "strumTime")),
        "column=" .. tostring(safeGet(note, "column")),
        "noteData=" .. tostring(safeGet(note, "noteData")),
        "dir=" .. tostring(safeGet(note, "dir")),
        "rawLane=" .. tostring(rawLane),
        "isSustain=" .. tostring(safeGet(note, "isSustain")),
        "mustHitSection=" .. tostring(mustHit),
    }

    local side = nil
    local sideFields = { "side", "Side", "strumlineSide", "isPlayerNote", "mustPress" }
    for _, field in ipairs(sideFields) do
        local value = safeGet(note, field)
        if value ~= nil then
            fields[#fields + 1] = field .. "=" .. tostring(value)
            local keyLower = string.lower(field)
            if (keyLower == "side" or keyLower == "strumlineside") and type(value) == "string" then
                local v = string.lower(value)
                if v == "r" or v == "right" or v == "player" then side = "R" end
                if v == "l" or v == "left" or v == "opponent" then side = "L" end
            elseif (keyLower == "isplayernote" or keyLower == "mustpress") and type(value) == "boolean" then
                side = value and "R" or "L"
            end
        end
    end

    for _, linkField in ipairs({ "strumline", "strumLine", "strumlineObj", "strumLineObj" }) do
        local line = safeGet(note, linkField)
        if type(line) == "table" then
            for _, field in ipairs({ "side", "Side", "name", "Name", "isPlayer", "isOpponent" }) do
                local value = safeGet(line, field)
                if value ~= nil then
                    fields[#fields + 1] = linkField .. "." .. field .. "=" .. tostring(value)
                    local k, v = string.lower(field), type(value) == "string" and string.lower(value) or value
                    if (k == "side" or k == "name") and type(v) == "string" then
                        if v == "r" or v == "right" or v == "player" then side = "R" end
                        if v == "l" or v == "left" or v == "opponent" then side = "L" end
                    elseif (k == "isplayer" or k == "isopponent") and type(value) == "boolean" then
                        if k == "isplayer" then
                            side = value and "R" or "L"
                        else
                            side = value and "L" or "R"
                        end
                    end
                end
            end
        end
    end

    return {
        index = index,
        pool = poolName,
        time = safeGet(note, "strumTime"),
        column = safeGet(note, "column"),
        rawLane = rawLane,
        mustHitSection = mustHit,
        side = side,
        text = "#" .. index .. " [" .. poolName .. "] " .. table.concat(fields, " | "),
    }
end

local function evaluateNotes(mod, parserCallOk)
    local rawNotes = collectNotes(mod)
    local notes = {}
    for i, item in ipairs(rawNotes) do
        notes[#notes + 1] = sampleNote(item.note, item.pool, i)
    end

    log("Observed unique note tables: " .. #notes)
    for i, n in ipairs(notes) do
        log(n.text)
    end

    local times = {}
    local validTimes = true
    for _, note in ipairs(notes) do
        if type(note.time) ~= "number" then
            validTimes = false
            break
        end
        times[#times + 1] = note.time
    end
    table.sort(times)
    local timesMatch = #times == #EXPECTED_TIMES
    if timesMatch then
        for i, expected in ipairs(EXPECTED_TIMES) do
            if math.abs(times[i] - expected) > 0.1 then
                timesMatch = false
                break
            end
        end
    end
    if not validTimes then timesMatch = false end

    local columns = {}
    local allColumnsReadable = true
    for _, note in ipairs(notes) do
        if type(note.column) ~= "number" then
            allColumnsReadable = false
            break
        end
        columns[note.column] = true
    end
    local columnsMatch = allColumnsReadable and #notes == 4
    if columnsMatch then
        for col = 0, 3 do
            if not columns[col] then columnsMatch = false end
        end
        local nCols = 0
        for col in next, columns do nCols += 1 end
        if nCols ~= 4 then columnsMatch = false end
    end

    local allSidesReadable, allPlayerSide = #notes == 4, #notes == 4
    for _, note in ipairs(notes) do
        if note.side == nil then
            allSidesReadable = false
            allPlayerSide = false
        elseif note.side ~= "R" then
            allPlayerSide = false
        end
    end

    log("Check: note count " .. (#notes == 4 and "PASS" or ("FAIL (expected 4, got " .. #notes .. ")")))
    log("Check: exact timestamps " .. (timesMatch and "PASS" or "FAIL"))
    log("Check: columns 0,1,2,3 " .. (columnsMatch and "PASS" or (allColumnsReadable and "FAIL" or "UNVERIFIED (column field not exposed)")))
    log("Check: player-side routing " .. (allSidesReadable and (allPlayerSide and "PASS (all notes report R/player)" or "FAIL (one or more notes report non-player side)") or "UNVERIFIED (no explicit side field; do not infer a pass)"))

    local tapCorePass = parserCallOk and #notes == 4 and timesMatch and columnsMatch
    if not parserCallOk then
        log("RESULT: FAIL — parseChart raised an error; the sampled note state may be partial.")
        setStatus("FAIL — parseChart errored; inspect samples and clean up.", false)
    elseif tapCorePass and allSidesReadable and allPlayerSide then
        log("RESULT: PASS — count, timestamps, columns, and exposed player-side routing match the fixture.")
        setStatus("PASS — tap creation and exposed routing verified. Rejoin required.", true)
    elseif tapCorePass then
        log("RESULT: PARTIAL — count, timestamps, and columns match, but player-side routing was not fully observable.")
        setStatus("PARTIAL — tap/time/columns match; side routing not fully proven.", false)
    else
        log("RESULT: FAIL — at least one core tap-chart assertion did not match.")
        setStatus("FAIL — inspect log. Cleanup is available; rejoin still required.", false)
    end
    return notes
end

local function runTapTest()
    if state.ran then
        log("REFUSED: this UI permits one state-changing test attempt per client session. Rejoin first.")
        return
    end
    if not state.ready or not state.module or not state.baseline then
        log("REFUSED: run Inspect / Preflight first and require a clean baseline.")
        return
    end
    if game.PlaceId ~= TARGET_PLACE_ID then
        log("REFUSED: the current PlaceId no longer matches the target.")
        return
    end

    -- Mark the attempt before calling game code; an error is not permission to retry.
    state.ran = true
    state.ready = false
    setButtonEnabled(state.runButton, false)
    setButtonEnabled(state.cleanButton, false)
    setStatus("Running one parseChart call…", false)
    log("--- BEGIN SINGLE-CALL TAP TEST ---")
    log("Fixture: four taps at 1200/1800/2400/3000 ms, lanes 4/5/6/7, mustHitSection=false.")
    log("Calling parseChart(wrapper, {}, nil, nil). No addSectionsFromChart/addNotesFromChart follow-up will run.")

    local wrapper = {
        song = {
            song = "afn_synth_a_taps",
            bpm = 200,
            keyCount = 4,
            playerKeyCount = 4,
            notes = {
                {
                    mustHitSection = false,
                    sectionNotes = {
                        { 1200, 4, 0 },
                        { 1800, 5, 0 },
                        { 2400, 6, 0 },
                        { 3000, 7, 0 },
                    },
                },
            },
            events = {},
        },
    }

    local parser = safeGet(state.module, "parseChart")
    if type(parser) ~= "function" then
        log("FAIL: parseChart disappeared after preflight; no call executed.")
        setStatus("BLOCKED — parseChart unavailable", false)
        return
    end

    local ok, result = pcall(function()
        return parser(wrapper, {}, nil, nil)
    end)
    if not ok then
        log("parseChart ERROR: " .. tostring(result))
        setStatus("FAIL — parseChart raised an error. Cleanup is available.", false)
    else
        log("parseChart returned without a Lua error; return value type=" .. type(result) .. ".")
    end

    local post = captureSnapshot(state.module)
    describeSnapshot("Post-parse", post)
    evaluateNotes(state.module, ok)

    state.post = post
    setButtonEnabled(state.cleanButton, true)
    log("Reminder: do not run playback. This harness does not call startSong or validate audio playback.")
    log("Strums/Strumlines and unknown registry writes may persist; rejoin is required after cleanup.")
    log("--- END SINGLE-CALL TAP TEST ---")
end

local function cleanupTest()
    if not state.ran then
        log("Nothing to clean: the state-changing test has not been attempted.")
        return
    end
    if state.cleaned then
        log("Cleanup was already attempted. Rejoin the client; do not repeat cleanup.")
        return
    end
    state.cleaned = true
    setButtonEnabled(state.cleanButton, false)
    log("--- BEGIN BEST-EFFORT POOL/TIMING RESTORE ---")
    log("Restoring the known snapshot only. Strums/Strumlines and unknown registries are intentionally NOT destroyed.")

    local ok, err = pcall(function()
        restoreSnapshot(state.module, state.baseline)
    end)
    if not ok then
        log("CLEANUP ERROR: " .. tostring(err))
        setStatus("Cleanup incomplete — rejoin immediately.", false)
        return
    end

    local restored = captureSnapshot(state.module)
    describeSnapshot("After cleanup", restored)
    local poolsMatch = restored.Notes == state.baseline.Notes and restored.UnspawnedNotes == state.baseline.UnspawnedNotes
    local conMatch = true
    if state.baseline.conductorFields and restored.conductorFields then
        for _, field in ipairs(CONDUCTOR_FIELDS) do
            local a = state.baseline.conductorFields[field]
            local b = restored.conductorFields[field]
            if not a or not b or a.present ~= b.present or (a.present and a.value ~= b.value) then
                conMatch = false
                log("RESTORE DIFF Conductor." .. field .. ": baseline=" .. tostring(a and a.value) .. ", current=" .. tostring(b and b.value))
            end
        end
    end
    local bpmMapMatch = true
    if state.baseline.bpmChangeMap then
        local a = state.baseline.bpmChangeMap
        local b = captureNested(state.baseline.conductorRef, "BPMChangeMap")
        bpmMapMatch = a.present == b.present
            and ((not a.isTable and a.value == b.value)
            or (a.isTable and b.isTable and serialize(a.data) == serialize(b.data)))
    end
    local svMatch = true
    if state.baseline.sliderVelocities then
        local a = state.baseline.sliderVelocities
        local currentSv = safeGet(state.baseline.svRef, "sliderVelocities")
        local b = captureNested(state.baseline.svRef, "sliderVelocities")
        svMatch = a.present == b.present
            and ((not a.isTable and a.value == b.value)
            or (a.isTable and b.isTable and serialize(a.data) == serialize(b.data)))
        if a.isTable and type(currentSv) ~= "table" then svMatch = false end
    end

    log("Restore verification: pools=" .. (poolsMatch and "PASS" or "FAIL")
        .. ", Conductor scalars=" .. (conMatch and "PASS" or "FAIL")
        .. ", BPMChangeMap=" .. (bpmMapMatch and "PASS" or "FAIL")
        .. ", sliderVelocities=" .. (svMatch and "PASS" or "FAIL"))

    local structuralResidue = restored.Strums ~= state.baseline.Strums
        or restored.Strumlines ~= state.baseline.Strumlines
        or restored.Maps ~= state.baseline.Maps
    if structuralResidue then
        log("EXPECTED/UNRESTORED RESIDUE: Strums=" .. tostring(restored.Strums)
            .. ", Strumlines=" .. tostring(restored.Strumlines)
            .. ", Maps=" .. tostring(restored.Maps) .. ".")
    end
    log("Cleanup is not a clean-session guarantee. Rejoin now, then inspect and confirm all baseline counts are zero.")
    setStatus((poolsMatch and conMatch and bpmMapMatch and svMatch)
        and "Pools/timing restored where supported; rejoin required."
        or "Restore could not be fully verified; rejoin required immediately.",
        poolsMatch and conMatch and bpmMapMatch and svMatch)
    log("--- END BEST-EFFORT RESTORE ---")
end

-- ========================= UI (native Roblox instances; no third-party UI URL) =========================
local function make(className, props, parent)
    local obj = Instance.new(className)
    for key, value in pairs(props or {}) do
        pcall(function() obj[key] = value end)
    end
    obj.Parent = parent
    return obj
end

local function addCorner(parent, radius)
    make("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

local function makeButton(parent, title, x, width, callback)
    local button = make("TextButton", {
        Name = title:gsub("%W", "") .. "Button",
        Position = UDim2.fromOffset(x, 103),
        Size = UDim2.fromOffset(width, 34),
        BackgroundColor3 = Color3.fromRGB(66, 91, 166),
        BorderSizePixel = 0,
        Text = title,
        TextColor3 = Color3.fromRGB(245, 247, 255),
        TextSize = 13,
        Font = Enum.Font.GothamSemibold,
        AutoButtonColor = true,
        Active = true,
    }, parent)
    addCorner(button, 7)
    button.MouseButton1Click:Connect(callback)
    return button
end

local function makeUI()
    local parent
    if type(gethui) == "function" then
        local ok, result = pcall(function() return gethui() end)
        if ok then parent = result end
    end
    if not parent then
        local ok, result = pcall(function() return game:GetService("CoreGui") end)
        if ok then parent = result end
    end
    if not parent then error("Cannot access a UI parent (gethui/CoreGui unavailable).") end

    pcall(function()
        local old = parent:FindFirstChild(GUI_NAME)
        if old then old:Destroy() end
    end)

    local gui = make("ScreenGui", {
        Name = GUI_NAME,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 999999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, parent)
    state.gui = gui

    local window = make("Frame", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(700, 520),
        BackgroundColor3 = Color3.fromRGB(20, 22, 30),
        BorderSizePixel = 0,
        Active = true,
        Draggable = true,
    }, gui)
    addCorner(window, 12)
    make("UIStroke", { Color = Color3.fromRGB(76, 86, 120), Thickness = 1 }, window)

    local header = make("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 67),
        BackgroundColor3 = Color3.fromRGB(29, 32, 45),
        BorderSizePixel = 0,
    }, window)
    addCorner(header, 12)
    make("Frame", {
        Name = "HeaderSquareBottom",
        Position = UDim2.new(0, 0, 1, -12),
        Size = UDim2.new(1, 0, 0, 12),
        BackgroundColor3 = Color3.fromRGB(29, 32, 45),
        BorderSizePixel = 0,
    }, header)
    make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(18, 10),
        Size = UDim2.new(1, -36, 0, 25),
        Font = Enum.Font.GothamBold,
        Text = "AfternightCustomSongs  /  Test Loader",
        TextColor3 = Color3.fromRGB(244, 246, 255),
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)
    make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(19, 36),
        Size = UDim2.new(1, -38, 0, 18),
        Font = Enum.Font.Gotham,
        Text = "One-call synthetic tap validation • no playback • no remotes",
        TextColor3 = Color3.fromRGB(168, 176, 201),
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)

    local statusBack = make("Frame", {
        Position = UDim2.fromOffset(14, 76),
        Size = UDim2.new(1, -28, 0, 20),
        BackgroundColor3 = Color3.fromRGB(28, 31, 42),
        BorderSizePixel = 0,
    }, window)
    addCorner(statusBack, 6)
    state.status = make("TextLabel", {
        Name = "Status",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(1, -16, 1, 0),
        Font = Enum.Font.GothamMedium,
        Text = "Starting read-only preflight…",
        TextColor3 = Color3.fromRGB(255, 202, 124),
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, statusBack)

    local inspectButton = makeButton(window, "Inspect / Preflight", 14, 155, function()
        log("--- READ-ONLY PREFLIGHT ---")
        prepareEngine()
    end)
    state.runButton = makeButton(window, "Run 4-Tap Test", 177, 155, runTapTest)
    state.cleanButton = makeButton(window, "Cleanup + Verify", 340, 155, cleanupTest)
    setButtonEnabled(state.runButton, false)
    setButtonEnabled(state.cleanButton, false)
    makeButton(window, "Close UI", 503, 155, function()
        if state.gui then state.gui:Destroy() end
        state.gui = nil
    end)

    state.logScroll = make("ScrollingFrame", {
        Name = "LogScroll",
        Position = UDim2.fromOffset(14, 146),
        Size = UDim2.new(1, -28, 1, -160),
        BackgroundColor3 = Color3.fromRGB(13, 15, 21),
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = Color3.fromRGB(95, 107, 151),
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.None,
    }, window)
    addCorner(state.logScroll, 8)
    state.logLabel = make("TextLabel", {
        Name = "LogText",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 8),
        Size = UDim2.new(1, -20, 0, 20),
        AutomaticSize = Enum.AutomaticSize.Y,
        Font = Enum.Font.Code,
        Text = "",
        TextColor3 = Color3.fromRGB(213, 219, 238),
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, state.logScroll)
    local constraint = make("UITextSizeConstraint", { MinTextSize = 11, MaxTextSize = 12 }, state.logLabel)
    log("UI initialized. No game state has been changed.")
    log("Target PlaceId: " .. TARGET_PLACE_ID .. ". This script makes no outbound HTTP requests.")
    log("A clean rejoin is required before any state-changing test.")
    prepareEngine()
end

local okUI, uiErr = pcall(makeUI)
if not okUI then
    warn("[AfternightCustomSongs] UI initialization failed: " .. tostring(uiErr))
end
