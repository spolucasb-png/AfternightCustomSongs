-- AfternightCustomSongs - WindUI synthetic tap-test loader (prototype).
--
-- ONE explicit, user-triggered parseChart call using the four-tap fixture
-- structure. No addNotesFromChart / addSectionsFromChart / startSong /
-- endSong / remotes / scores / SaveData writes. No KeySystem, no backgrounds,
-- no icons passed, no downloads: WindUI is the audited local vendor
-- (src/vendor/windui_main.lua + AFN-P1/P2/P3) loaded from the executor
-- workspace file afn_windui.lua.
--
-- Thread lesson applied: EVERY UI touch is pcall-wrapped and append-only
-- (new status paragraphs, never mutations). print() is the primary record;
-- the console carries the full verdict even if a UI write throws.
-- Cleanup restores pools/timing only; Strums/Strumlines persist -> rejoin.

local TARGET_PLACE_ID = 13042495892
local EXPECTED_TIMES = { 1200, 1800, 2400, 3000 }

local CONDUCTOR_FIELDS = {
    "BPM", "BaseBPM", "CurBPM", "Offset", "Crochet", "StepCrochet",
    "BeatsPerMeasure", "StepsPerBeat", "SongPosition", "TimePosition", "Paused",
}

local state = {
    module = nil, baseline = nil, ready = false, ran = false,
    cleaned = false, tab = nil, notes = 0,
}

local function log(message)
    message = tostring(message)
    print("[AFN-WindUI] " .. message)
    if state.tab == nil or state.notes >= 14 then
        return
    end
    local ok, err = pcall(function()
        state.tab:Paragraph({ Title = message:sub(1, 220) })
    end)
    if ok then
        state.notes = state.notes + 1
    else
        print("[AFN-WindUI] (ui-note skipped: " .. tostring(err) .. ")")
    end
end

local function notify(title, content)
    pcall(function()
        state.windui:Notify({ Title = tostring(title), Content = tostring(content), Duration = 6 })
    end)
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
        copy[deepClone(key, seen)] = deepClone(child, seen)
    end
    return copy
end

local function clearTableInPlace(tbl)
    if type(tbl) ~= "table" then return false end
    for key in next, tbl do rawset(tbl, key, nil) end
    return true
end

local function captureNested(parent, key)
    local value = safeGet(parent, key)
    return {
        present = value ~= nil, value = value,
        isTable = type(value) == "table",
        ref = type(value) == "table" and value or nil,
        data = type(value) == "table" and deepClone(value) or nil,
    }
end

local function restoreNested(parent, key, snapshot)
    if type(parent) ~= "table" or type(snapshot) ~= "table" then return false end
    if not snapshot.present then rawset(parent, key, nil) return true end
    if snapshot.isTable and type(snapshot.ref) == "table" then
        clearTableInPlace(snapshot.ref)
        local restored = deepClone(snapshot.data or {})
        for k, v in next, restored do rawset(snapshot.ref, k, v) end
        rawset(parent, key, snapshot.ref)
    else
        rawset(parent, key, snapshot.value)
    end
    return true
end

local function findGameplayModule()
    if type(getgc) ~= "function" then
        return nil, "getgc(true) unavailable"
    end
    local ok, objects = pcall(function() return getgc(true) end)
    if not ok or type(objects) ~= "table" then
        return nil, "getgc(true) failed"
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
    local mm = safeGet(mod, "mapModule")
    if type(mm) ~= "table" then return nil end
    local maps = safeGet(mm, "Maps")
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
    local sp = safeGet(mod, "songPlayer")
    if type(sp) == "table" then
        snap.songPlayer = {
            timePosition = safeGet(sp, "timePosition"),
            timeLength = safeGet(sp, "timeLength"),
            paused = safeGet(sp, "paused"),
        }
    end
    return snap
end

local function restoreSnapshot(mod, snap)
    if type(mod) ~= "table" or type(snap) ~= "table" then
        error("No valid baseline snapshot exists.")
    end
    local notes, unspawned = snap.NotesRef, snap.UnspawnedNotesRef
    if type(notes) ~= "table" or type(unspawned) ~= "table" then
        error("Baseline pool references missing; refusing cleanup.")
    end
    local curN, curU = safeGet(mod, "Notes"), safeGet(mod, "UnspawnedNotes")
    if type(curN) == "table" then clearTableInPlace(curN) end
    if type(curU) == "table" then clearTableInPlace(curU) end
    clearTableInPlace(notes)
    clearTableInPlace(unspawned)
    rawset(mod, "Notes", notes)
    rawset(mod, "UnspawnedNotes", unspawned)
    local conductor = snap.conductorRef
    if type(conductor) == "table" then
        rawset(mod, "Conductor", conductor)
        for _, field in ipairs(CONDUCTOR_FIELDS) do
            local item = snap.conductorFields[field]
            if item and item.present then rawset(conductor, field, item.value)
            else rawset(conductor, field, nil) end
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
        pieces[#pieces + 1] = serialize(key, seen, (depth or 0) + 1)
            .. "=" .. serialize(child, seen, (depth or 0) + 1)
    end
    table.sort(pieces)
    seen[value] = nil
    return "{" .. table.concat(pieces, ",") .. "}"
end

local function baselineIsClean(snap)
    for _, field in ipairs({ "Notes", "UnspawnedNotes", "Strums", "Strumlines", "Maps" }) do
        if snap[field] ~= 0 then
            return false, field .. " is " .. tostring(snap[field]) .. "; expected 0. Rejoin first."
        end
    end
    local con = snap.conductorFields or {}
    local tp = con.TimePosition and con.TimePosition.value
    local sp = con.SongPosition and con.SongPosition.value
    if type(tp) == "number" and math.abs(tp) > 250 then
        return false, "TimePosition " .. tostring(tp) .. "; engine may not be idle."
    end
    if type(sp) == "number" and math.abs(sp) > 250 then
        return false, "SongPosition " .. tostring(sp) .. "; engine may not be idle."
    end
    if snap.songPlayer then
        local a = snap.songPlayer
        if type(a.timePosition) == "number" and a.timePosition > 250 then
            return false, "audio transport active; refusing test during playback."
        end
        if type(a.timeLength) == "number" and a.timeLength > 0 and a.paused == false then
            return false, "songPlayer transport not paused."
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
        log(label .. " audio: timePosition=" .. tostring(snap.songPlayer.timePosition)
            .. ", timeLength=" .. tostring(snap.songPlayer.timeLength)
            .. ", paused=" .. tostring(snap.songPlayer.paused))
    end
end

local function prepareEngine()
    if game.PlaceId ~= TARGET_PLACE_ID then
        state.module, state.baseline, state.ready = nil, nil, false
        log("ABORT: wrong PlaceId " .. tostring(game.PlaceId))
        return false
    end
    local candidates, err = findGameplayModule()
    if not candidates then
        state.module, state.baseline, state.ready = nil, nil, false
        log("ABORT: " .. tostring(err))
        return false
    end
    if #candidates ~= 1 then
        state.module, state.baseline, state.ready = nil, nil, false
        log("ABORT: " .. #candidates .. " candidate modules; need exactly one.")
        return false
    end
    state.module = candidates[1]
    local snap = captureSnapshot(state.module)
    describeSnapshot("Current", snap)
    local clean, reason = baselineIsClean(snap)
    if not clean then
        state.ready = false
        if not state.ran then state.baseline = nil end
        log("ABORT: " .. reason)
        return false
    end
    if not state.ran then
        state.baseline = snap
        state.ready = true
        log("Preflight OK. Still opt-in: press Run 4-Tap Test for one parser call.")
        notify("Preflight OK", "Clean baseline. Run is opt-in.")
    else
        log("Already attempted this session; rejoin before another run.")
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
    for _, field in ipairs({ "side", "Side", "isPlayerNote", "mustPress" }) do
        local value = safeGet(note, field)
        if value ~= nil then
            fields[#fields + 1] = field .. "=" .. tostring(value)
            local kl = string.lower(field)
            if kl == "side" and type(value) == "string" then
                local v = string.lower(value)
                if v == "r" or v == "right" or v == "player" then side = "R" end
                if v == "l" or v == "left" or v == "opponent" then side = "L" end
            elseif (kl == "isplayernote" or kl == "mustpress") and type(value) == "boolean" then
                side = value and "R" or "L"
            end
        end
    end
    return {
        index = index, pool = poolName, time = safeGet(note, "strumTime"),
        column = safeGet(note, "column"), rawLane = rawLane,
        mustHitSection = mustHit, side = side,
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
    for _, n in ipairs(notes) do log(n.text) end
    local times, validTimes = {}, true
    for _, note in ipairs(notes) do
        if type(note.time) ~= "number" then validTimes = false break end
        times[#times + 1] = note.time
    end
    table.sort(times)
    local timesMatch = validTimes and #times == #EXPECTED_TIMES
    if timesMatch then
        for i, expected in ipairs(EXPECTED_TIMES) do
            if math.abs(times[i] - expected) > 0.1 then timesMatch = false break end
        end
    end
    local columns, allCols = {}, true
    for _, note in ipairs(notes) do
        if type(note.column) ~= "number" then allCols = false break end
        columns[note.column] = true
    end
    local nCols = 0
    for _ in next, columns do nCols += 1 end
    local columnsMatch = allCols and #notes == 4 and nCols == 4
        and columns[0] and columns[1] and columns[2] and columns[3]
    local sidesRead, allR = #notes == 4, #notes == 4
    for _, note in ipairs(notes) do
        if note.side == nil then sidesRead, allR = false, false
        elseif note.side ~= "R" then allR = false end
    end
    log("Check: count " .. (#notes == 4 and "PASS" or ("FAIL got " .. #notes)))
    log("Check: timestamps " .. (timesMatch and "PASS" or "FAIL"))
    log("Check: columns 0-3 " .. (columnsMatch and "PASS"
        or (allCols and "FAIL" or "UNVERIFIED (column not exposed)")))
    log("Check: player-side " .. (sidesRead
        and (allR and "PASS (all R)" or "FAIL (non-R present)")
        or "UNVERIFIED (no side field; do not infer)"))
    local core = parserCallOk and #notes == 4 and timesMatch and columnsMatch
    if not parserCallOk then
        log("RESULT: FAIL - parseChart raised; samples may be partial.")
        notify("FAIL", "parseChart errored. Cleanup available.")
    elseif core and sidesRead and allR then
        log("RESULT: PASS - count, times, columns, player-side routing match.")
        notify("PASS", "Tap creation verified. Rejoin required.")
    elseif core then
        log("RESULT: PARTIAL - taps/time/columns match; side not fully proven.")
        notify("PARTIAL", "Side routing unproven. Rejoin required.")
    else
        log("RESULT: FAIL - a core assertion did not match.")
        notify("FAIL", "Inspect log. Rejoin required.")
    end
end

local function runTapTest()
    if state.ran then
        log("REFUSED: one attempt per session. Rejoin first.")
        return
    end
    if not state.ready or not state.module or not state.baseline then
        log("REFUSED: run Inspect / Preflight first; need a clean baseline.")
        return
    end
    if game.PlaceId ~= TARGET_PLACE_ID then
        log("REFUSED: PlaceId changed.")
        return
    end
    state.ran = true
    state.ready = false
    log("--- BEGIN SINGLE-CALL TAP TEST ---")
    log("Fixture: taps 1200/1800/2400/3000ms, lanes 4/5/6/7, mustHitSection=false.")
    log("Calling parseChart(wrapper, {}, nil, nil). No follow-up calls.")
    local wrapper = {
        song = {
            song = "afn_synth_a_taps", bpm = 200, keyCount = 4,
            playerKeyCount = 4,
            notes = { {
                mustHitSection = false,
                sectionNotes = { {1200,4,0}, {1800,5,0}, {2400,6,0}, {3000,7,0} },
            } },
            events = {},
        },
    }
    local parser = safeGet(state.module, "parseChart")
    if type(parser) ~= "function" then
        log("FAIL: parseChart disappeared after preflight; no call executed.")
        return
    end
    local ok, result = pcall(function() return parser(wrapper, {}, nil, nil) end)
    if not ok then
        log("parseChart ERROR: " .. tostring(result))
    else
        log("parseChart returned without a Lua error; return type=" .. type(result) .. ".")
    end
    local post = captureSnapshot(state.module)
    describeSnapshot("Post-parse", post)
    evaluateNotes(state.module, ok)
    state.post = post
    log("No playback entered. Strums/Strumlines may persist; rejoin after cleanup.")
    log("--- END SINGLE-CALL TAP TEST ---")
end

local function cleanupTest()
    if not state.ran then
        log("Nothing to clean: test not attempted.")
        return
    end
    if state.cleaned then
        log("Cleanup already attempted. Rejoin; do not repeat.")
        return
    end
    state.cleaned = true
    log("--- BEGIN BEST-EFFORT RESTORE ---")
    log("Pools/timing only. Strums/Strumlines intentionally NOT destroyed.")
    local ok, err = pcall(function() restoreSnapshot(state.module, state.baseline) end)
    if not ok then
        log("CLEANUP ERROR: " .. tostring(err) .. " - rejoin immediately.")
        notify("Cleanup incomplete", "Rejoin immediately.")
        return
    end
    local restored = captureSnapshot(state.module)
    describeSnapshot("After cleanup", restored)
    local poolsMatch = restored.Notes == state.baseline.Notes
        and restored.UnspawnedNotes == state.baseline.UnspawnedNotes
    local conMatch = true
    if state.baseline.conductorFields and restored.conductorFields then
        for _, field in ipairs(CONDUCTOR_FIELDS) do
            local a = state.baseline.conductorFields[field]
            local b = restored.conductorFields[field]
            if not a or not b or a.present ~= b.present
                or (a.present and a.value ~= b.value) then
                conMatch = false
                log("RESTORE DIFF Conductor." .. field .. ": base="
                    .. tostring(a and a.value) .. " current=" .. tostring(b and b.value))
            end
        end
    end
    local function mapMatch(key)
        local a = state.baseline[key]
        if not a then return true end
        local ref = (key == "bpmChangeMap") and state.baseline.conductorRef or state.baseline.svRef
        local sub = (key == "bpmChangeMap") and "BPMChangeMap" or "sliderVelocities"
        local b = captureNested(ref, sub)
        return a.present == b.present
            and ((not a.isTable and a.value == b.value)
                or (a.isTable and b.isTable and serialize(a.data) == serialize(b.data)))
    end
    local bpmOk, svOk = mapMatch("bpmChangeMap"), mapMatch("sliderVelocities")
    log("Restore: pools=" .. (poolsMatch and "PASS" or "FAIL")
        .. ", Conductor=" .. (conMatch and "PASS" or "FAIL")
        .. ", BPMmap=" .. (bpmOk and "PASS" or "FAIL")
        .. ", SV=" .. (svOk and "PASS" or "FAIL"))
    if restored.Strums ~= state.baseline.Strums
        or restored.Strumlines ~= state.baseline.Strumlines
        or restored.Maps ~= state.baseline.Maps then
        log("EXPECTED RESIDUE: Strums=" .. tostring(restored.Strums)
            .. " Strumlines=" .. tostring(restored.Strumlines)
            .. " Maps=" .. tostring(restored.Maps))
    end
    log("Not a clean session. Rejoin now and confirm zero baseline.")
    notify("Cleanup done", "Pools/timing restored where supported. Rejoin.")
    log("--- END BEST-EFFORT RESTORE ---")
end

-- Boot: load vendored WindUI, build window. All construction pcall-wrapped.
print("[AFN-WindUI] boot: loading local WindUI vendor")
local okR, vsrc = pcall(function() return readfile("afn_windui.lua") end)
if not okR then
    print("[AFN-WindUI] ABORT: cannot read afn_windui.lua: " .. tostring(vsrc))
    return
end
local okL, WindUI = pcall(function() return loadstring(vsrc, "afn_windui")() end)
if not okL or type(WindUI) ~= "table" then
    print("[AFN-WindUI] ABORT: vendor load failed: " .. tostring(WindUI))
    return
end
state.windui = WindUI
local okW, win = pcall(function()
    return WindUI:CreateWindow({ Title = "AfternightCustomSongs", Size = UDim2.fromOffset(560, 430) })
end)
if not okW then
    print("[AFN-WindUI] ABORT: window failed: " .. tostring(win))
    return
end
local okT, tab = pcall(function() return win:Tab({ Title = "Tap Test" }) end)
if not okT then
    print("[AFN-WindUI] ABORT: tab failed: " .. tostring(tab))
    return
end
state.tab = tab
pcall(function()
    tab:Button({ Title = "Inspect / Preflight", Desc = "Read-only idle check", Callback = function()
        log("--- READ-ONLY PREFLIGHT ---")
        prepareEngine()
    end })
    tab:Button({ Title = "Run 4-Tap Test", Desc = "One parseChart call (gated)", Callback = runTapTest })
    tab:Button({ Title = "Cleanup + Verify", Desc = "Best-effort restore", Callback = cleanupTest })
end)
log("UI ready. No game state changed. Target PlaceId " .. TARGET_PLACE_ID .. ".")
log("Rejoin-clean baseline required before Run.")
prepareEngine()
