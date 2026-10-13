-- AfternightCustomSongs - WindUI chart player (prototype).
--
-- Library UI over player_core: pick a local chart, Play through the real
-- orchestrator (keepAlive), Stop via abruptGameEnd teardown.
-- Note: the vendored library still contains dormant HTTP/key-system and remote
-- asset paths. This player's current CreateWindow configuration does not enable
-- those paths; the vendor is not a general-purpose guarantee of network silence.
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
local AUDIO_DIR = "AfternightCustomSongs/Audio"
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
    core = nil,
    charts = {}, -- label -> { path, name }
    selected = nil,
    dropdown = nil,
    audios = {}, -- label -> { path, name }
    selectedAudio = nil, -- workspace path or nil (audio-free)
    audioDropdown = nil,
}

local function stillAlive()
    return _G.AFNPlayerUIGen == MYGEN
end

local function log(message)
    print("[AFN-PlayerUI] " .. tostring(message))
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
    automatchAudio()
    return labels
end

local AUDIO_EXTS = { ".mp3", ".ogg", ".wav" }

local function listAudio()
    local found = {}
    if type(isfolder) == "function" and isfolder(AUDIO_DIR) and type(listfiles) == "function" then
        local ok, files = pcall(listfiles, AUDIO_DIR)
        if ok and type(files) == "table" then
            for _, path in ipairs(files) do
                local name = basename(path)
                local lower = string.lower(name)
                for _, ext in ipairs(AUDIO_EXTS) do
                    if lower:sub(-#ext) == ext then
                        found[#found + 1] = { label = name, path = path, name = name }
                        break
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.label < b.label end)
    state.audios = {}
    local labels = { "(no audio — audio-free)" }
    for _, item in ipairs(found) do
        state.audios[item.label] = item
        labels[#labels + 1] = item.label
    end
    return labels
end

local function chartStem(chartLabel)
    local s = tostring(chartLabel or "")
    s = s:gsub("%.chart%.json$", ""):gsub("%.json$", "")
    return string.lower(s)
end

-- Auto-pick <chartstem>.mp3/.ogg/.wav, else the chart's audioFile hint.
function automatchAudio()
    local labels = listAudio()
    local want = nil
    local stem = chartStem(state.selected)
    if stem ~= "" then
        for _, ext in ipairs(AUDIO_EXTS) do
            for label, item in next, state.audios do
                if string.lower(label) == stem .. ext then
                    want = label
                    break
                end
            end
            if want then break end
        end
    end
    if not want and state.selected and state.charts[state.selected] then
        local item = state.charts[state.selected]
        local ok, body = pcall(function() return readfile(item.path) end)
        if ok and type(body) == "string" then
            local hint = body:match('"audioFile"%s*:%s*"([^"]+)"')
            if hint then
                local base = basename(hint)
                if state.audios[base] then
                    want = base
                else
                    for label in next, state.audios do
                        if string.lower(label) == string.lower(base) then
                            want = label
                            break
                        end
                    end
                end
            end
        end
    end
    state.selectedAudio = (want and state.audios[want]) and state.audios[want].path or nil
    if state.audioDropdown and type(state.audioDropdown.Refresh) == "function" then
        pcall(function() state.audioDropdown:Refresh(labels) end)
        pcall(function()
            state.audioDropdown:Select(want or "(no audio — audio-free)")
        end)
    end
    log("Audio: " .. tostring(state.selectedAudio or "none (audio-free)"))
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
        "audio=" .. tostring(rep.audioFile or (rep.subs and rep.subs.audio) or "?"),
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

local function doPlay()
    if game.PlaceId ~= TARGET_PLACE_ID then
        log("REFUSED: wrong PlaceId")
        notify("Wrong place", "Need Project Afternight.")
        return
    end
    if not loadCore() then return end
    if state.core.playing then
        log("REFUSED: already playing. Press Stop first.")
        notify("Already playing", "Press Stop before loading another chart.")
        return
    end

    local okPf, pf = state.core.preflight()
    if not okPf then
        local gateName, gateValue = "preflight", tostring(pf and pf.stage)
        if type(pf) == "table" and type(pf.gates) == "table" then
            for name, value in next, pf.gates do
                if type(value) == "string" and value:sub(1, 5) == "FAIL:" then
                    gateName, gateValue = tostring(name), value
                    break
                end
            end
        end
        log("Preflight failed: " .. gateName .. " / " .. gateValue)
        notify("Preflight failed", gateName .. ": " .. gateValue)
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
        audioFile = state.selectedAudio,
        keepAlive = true,
        diff = "Easy",
    })
    log(summarizeReport(rep))
    if rep and rep.start_ok and rep.stage == "playing" then
        notify("Playing", tostring(rep.songName) .. ". Press Stop when finished.")
        -- Finish poller: the core ends the song itself at the audio clock
        -- (results screen); tell the user results are up. Read-only.
        task.spawn(function()
            while stillAlive() and state.core and state.core.playing do
                task.wait(1)
                local lr = state.core.lastReport
                if type(lr) ~= "table" or not state.core.playing then break end
                if lr.stage == "ended-results" then
                    notify("Finished", "Results on screen — press Stop when done.")
                    break
                elseif lr.stage == "ended-fallback-stop" then
                    notify("Finished", "Song ended.")
                    break
                end
            end
        end)
    elseif rep and rep.stage == "cleanup-incomplete" then
        notify("Cleanup incomplete", "Press Stop to retry cleanup; rejoin only if cleanup still fails.")
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
    if rep and rep.stage == "busy-initializing" then
        notify("Still initializing", "Wait for Play to finish loading, then press Stop again.")
        return
    end
    if rep and rep.stage == "cleanup-incomplete" then
        notify("Cleanup incomplete", "Press Stop again to retry; rejoin only if cleanup still fails.")
        return
    end
    if rep and rep.ok then
        notify("Stopped", "Ready for another chart.")
    else
        notify("Stop failed", tostring(rep and rep.err or "cleanup status unavailable"))
    end
end

local function cleanup()
    -- Splash teardown is inline here: hideSplash is declared further below
    -- and is not in scope at this point in the chunk.
    pcall(function()
        local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local gui = pg and pg:FindFirstChild("AFN-Loading")
        if gui then gui:Destroy() end
    end)
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
-- Boot splash (native ScreenGui; visible while the vendor + core load)
----------------------------------------------------------------
local loadingGui, loadingLabel = nil, nil
local function hideSplash()
    if loadingGui then
        pcall(function() loadingGui:Destroy() end)
        loadingGui, loadingLabel = nil, nil
    end
end
local function setStatus(text)
    pcall(function()
        if loadingLabel then loadingLabel.Text = tostring(text) end
    end)
    log(text)
end
do
    local okB, pg = pcall(function()
        return game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
    end)
    if okB and pg then
        local okG, g, s = pcall(function()
            local gui = Instance.new("ScreenGui")
            gui.Name = "AFN-Loading"
            gui.ResetOnSpawn = false
            gui.IgnoreGuiInset = true
            gui.DisplayOrder = 999
            local bg = Instance.new("Frame")
            bg.Name = "BG"
            bg.Size = UDim2.fromScale(1, 1)
            bg.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
            bg.BackgroundTransparency = 0.25
            bg.BorderSizePixel = 0
            bg.Parent = gui
            local title = Instance.new("TextLabel")
            title.Name = "Title"
            title.AnchorPoint = Vector2.new(0.5, 0.5)
            title.Position = UDim2.fromScale(0.5, 0.46)
            title.Size = UDim2.fromScale(0.8, 0.08)
            title.BackgroundTransparency = 1
            title.Font = Enum.Font.GothamBold
            title.TextSize = 22
            title.TextColor3 = Color3.fromRGB(255, 255, 255)
            title.Text = "AfternightCustomSongs"
            title.Parent = gui
            local sub = Instance.new("TextLabel")
            sub.Name = "Status"
            sub.AnchorPoint = Vector2.new(0.5, 0.5)
            sub.Position = UDim2.fromScale(0.5, 0.54)
            sub.Size = UDim2.fromScale(0.8, 0.06)
            sub.BackgroundTransparency = 1
            sub.Font = Enum.Font.Gotham
            sub.TextSize = 15
            sub.TextColor3 = Color3.fromRGB(180, 180, 190)
            sub.Text = "Loading..."
            sub.Parent = gui
            gui.Parent = pg
            return gui, sub
        end)
        if okG and type(g) == "userdata" then
            loadingGui, loadingLabel = g, s
        end
    end
end

----------------------------------------------------------------
-- Boot WindUI
----------------------------------------------------------------
print("[AFN-PlayerUI] boot gen=" .. tostring(MYGEN))
if game.PlaceId ~= TARGET_PLACE_ID then
    warn("[AFN-PlayerUI] PlaceId " .. tostring(game.PlaceId) .. " != " .. TARGET_PLACE_ID)
end
setStatus("Loading interface library...")

local okR, vsrc = pcall(function() return readfile(WINDUI_FILE) end)
if not okR then
    print("[AFN-PlayerUI] ABORT: cannot read " .. WINDUI_FILE .. ": " .. tostring(vsrc))
    hideSplash()
    return
end
local okL, WindUI = pcall(function() return loadstring(vsrc, "afn_windui")() end)
if not okL or type(WindUI) ~= "table" then
    print("[AFN-PlayerUI] ABORT: vendor load failed: " .. tostring(WindUI))
    hideSplash()
    return
end
state.windui = WindUI
setStatus("Building window...")

local okW, win = pcall(function()
    return WindUI:CreateWindow({
        Title = "AfternightCustomSongs",
        Size = UDim2.fromOffset(420, 320),
    })
end)
if not okW then
    print("[AFN-PlayerUI] ABORT: window failed: " .. tostring(win))
    hideSplash()
    return
end
state.window = win
setStatus("Scanning charts...")

local okT, tab = pcall(function() return win:Tab({ Title = "Play" }) end)
if not okT then
    print("[AFN-PlayerUI] ABORT: tab failed: " .. tostring(tab))
    hideSplash()
    return
end
local labels = listCharts()
if #labels == 0 then
    labels = { "(no charts — drop .chart.json into " .. CHARTS_DIR .. ")" }
else
    state.selected = labels[1]
end

pcall(function()
    state.dropdown = tab:Dropdown({
        Title = "Chart",
        Desc = "Engine wrappers (.chart.json) or flat notes JSON",
        Values = labels,
        Value = state.selected or labels[1],
        Callback = function(value)
            if type(value) == "string" and state.charts[value] then
                state.selected = value
                print("[AFN-PlayerUI] selected " .. value)
                if not stillAlive() then return end
                automatchAudio()
            end
        end,
    })

    state.audioDropdown = tab:Dropdown({
        Title = "Audio",
        Desc = "Local file from " .. AUDIO_DIR .. " (auto-matched)",
        Values = { "(no audio — audio-free)" },
        Value = "(no audio — audio-free)",
        Callback = function(value)
            if type(value) == "string" and state.audios[value] then
                state.selectedAudio = state.audios[value].path
                print("[AFN-PlayerUI] audio " .. value)
            elseif value == "(no audio — audio-free)" then
                state.selectedAudio = nil
                print("[AFN-PlayerUI] audio none (audio-free)")
            end
        end,
    })

    tab:Button({
        Title = "Refresh",
        Desc = "Rescan " .. CHARTS_DIR .. " + " .. AUDIO_DIR,
        Callback = function()
            if not stillAlive() then return end
            refreshDropdown()
        end,
    })
    tab:Button({
        Title = "Play",
        Desc = "Preflight, then load chart (local audio when matched)",
        Callback = function()
            if not stillAlive() then return end
            doPlay()
        end,
    })
    tab:Button({
        Title = "Stop",
        Desc = "Restore idle state; retry if cleanup is incomplete",
        Callback = function()
            if not stillAlive() then return end
            doStop()
        end,
    })
end)

log("UI ready. PlaceId " .. tostring(game.PlaceId) .. ". Charts dir: " .. CHARTS_DIR)
refreshDropdown()
setStatus("Loading player core...")
loadCore()
hideSplash()
