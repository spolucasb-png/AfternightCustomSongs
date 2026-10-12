-- AfternightCustomSongs - WindUI chart player (prototype).
--
-- Library UI over player_core: pick a local chart, Play through the real
-- orchestrator (keepAlive), Stop via abruptGameEnd teardown.
-- WindUI is the audited local vendor (afn_windui.lua = src/vendor/windui_main.lua
-- with AFN-P1/P2/P3). Charts live under AfternightCustomSongs/Charts/.
--
-- Architecture mirrored from GakuranChart sections 0 / 0.5 (capability check +
-- re-exec cleanup) only — no Gakuran hooks/registry/UI code copied.
--
-- Local-only: play path is player_core (statically checked). This file may
-- loadstring the local vendor + core from the executor workspace; no HTTP.

----------------------------------------------------------------
-- 0. Executor capability check
----------------------------------------------------------------
local NEED = {
    "getgc", "readfile", "isfile", "isfolder", "listfiles", "loadstring",
    "getthreadidentity", "setthreadidentity",
}
local missing = {}
for _, n in ipairs(NEED) do
    if type(_G[n]) ~= "function" then
        -- some executors put these on getfenv(0)
        local ok, env = pcall(function() return getfenv(0) end)
        if not (ok and type(env) == "table" and type(env[n]) == "function") then
            missing[#missing + 1] = n
        end
    end
end
if #missing > 0 then
    warn("[AFN-PlayerUI] missing: " .. table.concat(missing, ", "))
    return
end

local TARGET_PLACE_ID = 13042495892
local CHARTS_DIR = "AfternightCustomSongs/Charts"
local CORE_FILE = "afn_player_core.lua"
local WINDUI_FILE = "afn_windui.lua"

----------------------------------------------------------------
-- 0.5. Re-execution cleanup
----------------------------------------------------------------
local MYGEN = (_G.AFNPlayerUIGen or 0) + 1
_G.AFNPlayerUIGen = MYGEN

if type(_G.AFNPlayerUICleanup) == "function" then
    pcall(_G.AFNPlayerUICleanup)
    _G.AFNPlayerUICleanup = nil
end

local state = {
    windui = nil,
    window = nil,
    tab = nil,
    core = nil,
    charts = {}, -- label -> { path, name }
    selected = nil,
    notes = 0,
    dropdown = nil,
}

local function stillAlive()
    return _G.AFNPlayerUIGen == MYGEN
end

local function log(message)
    message = tostring(message)
    print("[AFN-PlayerUI] " .. message)
    if not stillAlive() or state.tab == nil or state.notes >= 18 then
        return
    end
    local ok, err = pcall(function()
        state.tab:Paragraph({ Title = message:sub(1, 220) })
    end)
    if ok then
        state.notes = state.notes + 1
    else
        print("[AFN-PlayerUI] (ui-note skipped: " .. tostring(err) .. ")")
    end
end

local function notify(title, content)
    pcall(function()
        state.windui:Notify({
            Title = tostring(title),
            Content = tostring(content),
            Duration = 6,
        })
    end)
end

local function loadCore()
    if state.core then return true end
    local okR, src = pcall(function() return readfile(CORE_FILE) end)
    if not okR then
        log("ABORT: cannot read " .. CORE_FILE .. ": " .. tostring(src))
        return false
    end
    local okL, core = pcall(function() return loadstring(src, "afn_player_core")() end)
    if not okL or type(core) ~= "table" or type(core.play) ~= "function" then
        log("ABORT: player_core load failed: " .. tostring(core))
        return false
    end
    state.core = core
    log("player_core " .. tostring(core.VERSION) .. " ready.")
    return true
end

local function basename(path)
    path = tostring(path):gsub("\\", "/")
    local name = path:match("([^/]+)$") or path
    return name
end

local function listCharts()
    local found = {}
    if type(isfolder) == "function" and isfolder(CHARTS_DIR) and type(listfiles) == "function" then
        local ok, files = pcall(listfiles, CHARTS_DIR)
        if ok and type(files) == "table" then
            for _, path in ipairs(files) do
                local name = basename(path)
                local lower = string.lower(name)
                if lower:match("%.chart%.json$") or lower:match("%.json$") then
                    local label = name
                    found[#found + 1] = { label = label, path = path, name = name }
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.label < b.label end)
    state.charts = {}
    local labels = {}
    for _, item in ipairs(found) do
        state.charts[item.label] = item
        labels[#labels + 1] = item.label
    end
    return labels
end

local function refreshDropdown()
    local labels = listCharts()
    if #labels == 0 then
        labels = { "(no charts — drop .chart.json into " .. CHARTS_DIR .. ")" }
        state.selected = nil
    else
        if not state.selected or not state.charts[state.selected] then
            state.selected = labels[1]
        end
    end
    if state.dropdown and type(state.dropdown.Refresh) == "function" then
        pcall(function() state.dropdown:Refresh(labels) end)
        if state.selected then
            pcall(function() state.dropdown:Select(state.selected) end)
        end
    end
    log("Charts found: " .. tostring(#labels) .. " in " .. CHARTS_DIR)
    return labels
end

local function readSelectedChart()
    if not state.selected or not state.charts[state.selected] then
        return nil, "no chart selected"
    end
    local item = state.charts[state.selected]
    local ok, body = pcall(function() return readfile(item.path) end)
    if not ok then
        return nil, "reading " .. tostring(item.path) .. ": " .. tostring(body)
    end
    return body, item
end

local function summarizeReport(rep)
    if type(rep) ~= "table" then return tostring(rep) end
    local parts = {
        "stage=" .. tostring(rep.stage),
        "load=" .. tostring(rep.load_ok),
        "start=" .. tostring(rep.start_ok),
        "song=" .. tostring(rep.songName),
    }
    if rep.pools_after_load then
        parts[#parts + 1] = "Unspawned=" .. tostring(rep.pools_after_load.UnspawnedNotes)
        parts[#parts + 1] = "Strums=" .. tostring(rep.pools_after_load.Strums)
    end
    if rep.note0 then
        parts[#parts + 1] = string.format(
            "note0=%s/%s@%s",
            tostring(rep.note0.side),
            tostring(rep.note0.column),
            tostring(rep.note0.strumTime)
        )
    end
    if rep.load_err then parts[#parts + 1] = "load_err=" .. tostring(rep.load_err):sub(1, 80) end
    if rep.start_err then parts[#parts + 1] = "start_err=" .. tostring(rep.start_err):sub(1, 80) end
    if rep.aborted then parts[#parts + 1] = "aborted=" .. tostring(rep.aborted) end
    return table.concat(parts, " | ")
end

local function doPreflight()
    if game.PlaceId ~= TARGET_PLACE_ID then
        log("ABORT: PlaceId " .. tostring(game.PlaceId))
        notify("Wrong place", "Need Project Afternight.")
        return
    end
    if not loadCore() then return end
    log("--- PREFLIGHT ---")
    local ok, rep = state.core.preflight()
    if ok then
        local p = rep.pools or {}
        log("READY: pools N/U/S/SL="
            .. tostring(p.Notes) .. "/"
            .. tostring(p.UnspawnedNotes) .. "/"
            .. tostring(p.Strums) .. "/"
            .. tostring(p.Strumlines))
        notify("Preflight OK", "Idle engine. Select a chart and Play.")
    else
        log("NOT READY: " .. summarizeReport(rep))
        -- surface first FAIL gate
        if type(rep.gates) == "table" then
            for name, val in next, rep.gates do
                if type(val) == "string" and val:sub(1, 5) == "FAIL:" then
                    log("gate " .. tostring(name) .. ": " .. val)
                end
            end
        end
        notify("Preflight failed", "See log. Rejoin if residue.")
    end
end

local function doPlay()
    if game.PlaceId ~= TARGET_PLACE_ID then
        log("REFUSED: wrong PlaceId")
        return
    end
    if not loadCore() then return end
    if state.core.playing then
        log("REFUSED: already playing. Press Stop first.")
        return
    end
    local body, itemOrErr = readSelectedChart()
    if not body then
        log("REFUSED: " .. tostring(itemOrErr))
        notify("No chart", tostring(itemOrErr))
        return
    end
    local item = itemOrErr
    log("--- PLAY " .. tostring(item.name) .. " ---")
    notify("Loading", item.name)
    local rep = state.core.play({
        chartJson = body,
        keepAlive = true,
        diff = "Easy",
    })
    log(summarizeReport(rep))
    if rep and rep.start_ok and rep.stage == "playing" then
        notify("Playing", tostring(rep.songName) .. " (audio-free). Stop when done; rejoin after.")
    else
        notify("Play failed", tostring(rep and rep.stage or "?"))
    end
end

local function doStop()
    if not loadCore() then return end
    if not state.core.playing then
        log("Nothing to stop.")
        return
    end
    log("--- STOP ---")
    local rep = state.core.stop()
    log(summarizeReport(rep))
    notify("Stopped", "Teardown done. Rejoin before another Play (strum residue).")
end

local function cleanup()
    if type(state.core) == "table" and state.core.playing then
        pcall(function() state.core.stop() end)
    end
    pcall(function()
        if state.window and state.window.Destroy then
            state.window:Destroy()
        end
    end)
end
_G.AFNPlayerUICleanup = cleanup

----------------------------------------------------------------
-- Boot WindUI
----------------------------------------------------------------
print("[AFN-PlayerUI] boot gen=" .. tostring(MYGEN))
if game.PlaceId ~= TARGET_PLACE_ID then
    warn("[AFN-PlayerUI] PlaceId " .. tostring(game.PlaceId) .. " != " .. TARGET_PLACE_ID)
end

local okR, vsrc = pcall(function() return readfile(WINDUI_FILE) end)
if not okR then
    print("[AFN-PlayerUI] ABORT: cannot read " .. WINDUI_FILE .. ": " .. tostring(vsrc))
    return
end
local okL, WindUI = pcall(function() return loadstring(vsrc, "afn_windui")() end)
if not okL or type(WindUI) ~= "table" then
    print("[AFN-PlayerUI] ABORT: vendor load failed: " .. tostring(WindUI))
    return
end
state.windui = WindUI

local okW, win = pcall(function()
    return WindUI:CreateWindow({
        Title = "AfternightCustomSongs",
        Size = UDim2.fromOffset(580, 460),
    })
end)
if not okW then
    print("[AFN-PlayerUI] ABORT: window failed: " .. tostring(win))
    return
end
state.window = win

local okT, tab = pcall(function() return win:Tab({ Title = "Play" }) end)
if not okT then
    print("[AFN-PlayerUI] ABORT: tab failed: " .. tostring(tab))
    return
end
state.tab = tab

local labels = listCharts()
if #labels == 0 then
    labels = { "(no charts — drop .chart.json into " .. CHARTS_DIR .. ")" }
else
    state.selected = labels[1]
end

pcall(function()
    tab:Paragraph({
        Title = "Local chart player (audio-free). Charts: " .. CHARTS_DIR
            .. "  |  Convert osu with converters/osu_to_afn.py  |  Rejoin after Stop.",
    })

    state.dropdown = tab:Dropdown({
        Title = "Chart",
        Desc = "Engine wrappers (.chart.json) or flat notes JSON",
        Values = labels,
        Value = state.selected or labels[1],
        Callback = function(value)
            if type(value) == "string" and state.charts[value] then
                state.selected = value
                print("[AFN-PlayerUI] selected " .. value)
            end
        end,
    })

    tab:Button({
        Title = "Refresh charts",
        Desc = "Rescan " .. CHARTS_DIR,
        Callback = function()
            if not stillAlive() then return end
            refreshDropdown()
        end,
    })
    tab:Button({
        Title = "Preflight",
        Desc = "Read-only idle / residue check",
        Callback = function()
            if not stillAlive() then return end
            doPreflight()
        end,
    })
    tab:Button({
        Title = "Play",
        Desc = "loadSong + Start (keepAlive until Stop)",
        Callback = function()
            if not stillAlive() then return end
            doPlay()
        end,
    })
    tab:Button({
        Title = "Stop",
        Desc = "abruptGameEnd + restore; rejoin after",
        Callback = function()
            if not stillAlive() then return end
            doStop()
        end,
    })
end)

-- Optional Tap Test tab (same harness buttons as loader_windui, thin link)
pcall(function()
    local tap = win:Tab({ Title = "Tap Test" })
    tap:Paragraph({
        Title = "Parse-only 4-tap harness lives in afn_loader_windui.lua. This tab does not run it.",
    })
    tap:Button({
        Title = "Open note",
        Desc = "Use afn_loader_windui.lua for gated parseChart tests",
        Callback = function()
            notify("Tap Test", "Run afn_loader_windui.lua separately on a clean join.")
        end,
    })
end)

log("UI ready. PlaceId " .. tostring(game.PlaceId) .. ". Charts dir: " .. CHARTS_DIR)
refreshDropdown()
loadCore()
