--[[
    AfternightCustomSongs v1.0.0 (Rayfield edition)
    Local custom charts + local music for Project Afternight (PlaceId 13042495892).

    Lineage:
      - FunkyChart v1.23 (accountrevived): folder layout (Charts/Audio/Assets),
        chart list + manual select, options page, underframe, play/stop flow.
      - GakuranChart v2.x: capability check, re-exec generation cleanup,
        Rayfield UI structure, Settings.json persistence, chart validation,
        background underframe, local-only discipline.
      - AfternightCustomSongs player_core 1.3.0: the PROVEN live play path
        (registry inject -> loadSong @8058 -> Start listener -> autoplay ->
        endSong(true) results -> abruptGameEnd teardown). Ported verbatim;
        see HANDOFF.md / experiments/decompiled for engine evidence.

    How a play works (all client-side):
      1. Chart JSON (engine wrapper shape) is read from
         AfternightCustomSongs/Charts/*.chart.json and validated.
      2. A Folder "AFNRay_Play" is built in ReplicatedStorage holding a
         ModuleScript (the chart JSON string), a Song folder and a Mod folder.
      3. t1.songIds["AFN Custom"].Songs[name] = { SkipCountdown=true,
         Audio={Instrumental=<Content>, Volume=1} } (audio omitted = free-run).
      4. The engine's real loadSong runs at thread identity 2, then the
         "Start" listen function fires. Stop always runs abruptGameEnd +
         full teardown. At the audio-clock end, one allowlisted
         t21.endSong(true) raises the local results screen.
    In-game server is never touched (no remotes invoked). Downloading the
    Rayfield UI library over HTTP is allowed by standing rule (2026-10-14).

    Folders (executor workspace): AfternightCustomSongs/Charts (*.chart.json),
    AfternightCustomSongs/Audio (*.mp3/*.ogg/*.wav), AfternightCustomSongs/Skins
    (skins2afn packs: manifest.json + sheet PNGs + Sparrow XMLs),
    Assets (optional), Settings.json.
    Convert osu!mania maps with converters/osu_to_afn.py, skins with
    converters/skins2afn.py.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local VERSION = "1.1.0"
local FOLDER = "AfternightCustomSongs"
local CHARTS_DIR = FOLDER .. "/Charts"
local AUDIO_DIR = FOLDER .. "/Audio"
local SKINS_DIR = FOLDER .. "/Skins"
local ASSETS_DIR = FOLDER .. "/Assets"
local SETTINGS_FILE = FOLDER .. "/Settings.json"
local RAYFIELD_URL = "https://sirius.menu/rayfield"

local EXP_PLACE = 13042495892
local MOD_NAME = "AFN Custom"
local DEFAULT_DIFF = "Easy"
local CACHED_AUDIO = 30
local GAME_IDENTITY = 2
local LOADSONG_LINE = 8058

----------------------------------------------------------------
-- 0. Executor capability check
----------------------------------------------------------------
local function requireFn(name)
    if type(_G[name]) == "function" then return _G[name] end
    if type(getfenv) == "function" then
        local ok, env = pcall(function() return getfenv(0) end)
        if ok and type(env) == "table" and type(env[name]) == "function" then
            return env[name]
        end
    end
    return nil
end

local fn = {}
for _, n in ipairs({ "getgc", "readfile", "writefile", "isfile", "isfolder",
                      "makefolder", "listfiles", "getthreadidentity",
                      "setthreadidentity", "getcustomasset" }) do
    fn[n] = requireFn(n)
end
fn.getsynasset = requireFn("getsynasset")
fn.getlocalasset = fn.getcustomasset or fn.getsynasset

do
    local missing = {}
    for _, n in ipairs({ "getgc", "readfile", "writefile", "isfile", "isfolder",
                          "makefolder", "listfiles", "getthreadidentity",
                          "setthreadidentity" }) do
        if not fn[n] then table.insert(missing, n) end
    end
    if not fn.getlocalasset then table.insert(missing, "getcustomasset/getsynasset") end
    if type(loadstring) ~= "function" and type(requireFn("loadstring")) ~= "function" then
        table.insert(missing, "loadstring")
    end
    if #missing > 0 then
        warn("[AFNRay] Executor missing functions: " .. table.concat(missing, ", "))
        return
    end
end

for _, dir in ipairs({ FOLDER, CHARTS_DIR, AUDIO_DIR, SKINS_DIR, ASSETS_DIR }) do
    if not fn.isfolder(dir) then pcall(fn.makefolder, dir) end
end

----------------------------------------------------------------
-- 0.5. Re-execution cleanup (generation + Rayfield sweep)
----------------------------------------------------------------
local MYGEN = (_G.AFNRayGen or 0) + 1
_G.AFNRayGen = MYGEN

if type(_G.AFNRayCleanup) == "function" then
    pcall(_G.AFNRayCleanup)
    _G.AFNRayCleanup = nil
end

local function sweepRayfield()
    local containers = {}
    if type(gethui) == "function" then
        local okH, h = pcall(gethui)
        if okH and h then table.insert(containers, h) end
    end
    table.insert(containers, CoreGui)
    local rg = CoreGui:FindFirstChild("RobloxGui")
    if rg then table.insert(containers, rg) end
    for _, c in ipairs(containers) do
        for _, g in ipairs(c:GetChildren()) do
            if g.Name == "Rayfield" or g.Name == "Rayfield-Old" then
                pcall(function() g:Destroy() end)
            end
        end
    end
end
pcall(sweepRayfield)
pcall(function()
    local gui = player:FindFirstChildOfClass("PlayerGui")
    if gui then
        for _, g in ipairs(gui:GetChildren()) do
            if g.Name == "AFNRayUnderframe" then g:Destroy() end
        end
    end
end)

----------------------------------------------------------------
-- 1. Settings persistence
----------------------------------------------------------------
local settings = {
    offsetMs = 0,
    autoplay = false,
    bgEnabled = false,
    bgColor = { 0, 0, 0 },
    bgTransparency = 0,
    skin = nil, -- skins2afn pack folder name under SKINS_DIR, or nil (default)
    ignoreSV = false, -- flatten SV map at play (constant scroll feel)
}

local function saveSettings()
    pcall(fn.writefile, SETTINGS_FILE, HttpService:JSONEncode(settings))
end

local function loadSettings()
    if fn.isfile(SETTINGS_FILE) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(fn.readfile(SETTINGS_FILE))
        end)
        if ok and type(data) == "table" then
            for k, v in pairs(data) do settings[k] = v end
        end
    end
end
loadSettings()

----------------------------------------------------------------
-- 2. Logging / notify (Rayfield wired in later)
----------------------------------------------------------------
local uiNotify = nil -- assigned by buildUI; nil until then (warn-only)

local function notify(title, body, isError)
    warn(("[AFNRay] %s: %s"):format(title, body))
    if uiNotify then pcall(uiNotify, title, body, isError) end
end

----------------------------------------------------------------
-- 3. Engine access (ported from player_core 1.3.0, live-proven)
----------------------------------------------------------------
local function poolCount(t, k)
    local p = rawget(t, k)
    if type(p) ~= "table" then return "n/a:" .. type(p) end
    local n = 0
    for _ in next, p do n += 1 end
    return n
end

local function findFnByLine(line, tries)
    tries = tonumber(tries) or 3
    local attempts = 0
    for _ = 1, tries do
        attempts += 1
        for _, o in ipairs(getgc(true)) do
            if type(o) == "function" then
                local okS, s = pcall(function() return debug.info(o, "s") end)
                if okS and type(s) == "string" and string.find(s, "PlayerScripts", 1, true) then
                    local okL, a = pcall(function() return debug.info(o, "l") end)
                    if okL and a == line then return o, attempts end
                end
            end
        end
        task.wait(0.15)
    end
    return nil, attempts
end

local function upval(f, i)
    local ok, a, b = pcall(function() return debug.getupvalue(f, i) end)
    if not ok then return nil end
    if type(a) == "string" then return b end
    return a
end

-- SongPlayer instance (v90) via clearUp's upvalues. Nil-tolerant: without it
-- there is no song-end detection (Stop-only plays still work).
local function getSongPlayer(c)
    if type(c) ~= "table" or type(c.env) ~= "table" then return nil end
    local cu = rawget(c.env, "clearUp")
    if type(cu) ~= "function" then return nil end
    local ok, a, b = pcall(function() return debug.getupvalue(cu, 9) end)
    if not ok then return nil end
    local v90 = (type(a) == "string") and b or a
    if type(v90) ~= "table" then return nil end
    return v90
end

local function atGameIdentity(idBefore, f)
    local okSet = pcall(function() setthreadidentity(GAME_IDENTITY) end)
    if not okSet then return false, "setthreadidentity failed" end
    local ok, res = xpcall(f, debug.traceback)
    local okRestore, restoreErr = pcall(function() setthreadidentity(idBefore) end)
    if not okRestore then return false, "thread identity restore failed: " .. tostring(restoreErr) end
    return ok, res
end

----------------------------------------------------------------
-- 4. Chart library (read + validate, AFN wrapper shape)
----------------------------------------------------------------
local currentChart = nil       -- decoded + validated wrapper table
local currentChartPath = nil
local currentInfo = "No chart loaded"

local function listChartFiles()
    local out = {}
    local ok, files = pcall(fn.listfiles, CHARTS_DIR)
    if ok and type(files) == "table" then
        for _, f in ipairs(files) do
            local lower = tostring(f):lower()
            if lower:match("%.chart%.json$") or lower:match("%.json$") then
                table.insert(out, f)
            end
        end
    end
    table.sort(out)
    return out
end

local function basename(path)
    path = tostring(path):gsub("\\", "/")
    return path:match("([^/]+)$") or path
end

-- Returns validated wrapper table or nil + reason. Invalid rows are dropped
-- and counted (lanes must be 4-7, times >= 0, sus >= 0).
local function readChart(path)
    if not fn.isfile(path) then return nil, "File not found: " .. tostring(path) end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(fn.readfile(path))
    end)
    if not ok then return nil, "Invalid JSON: " .. tostring(data) end
    if type(data) ~= "table" then return nil, "Chart file is not a JSON object" end
    local song = data.song
    if type(song) ~= "table" or type(song.notes) ~= "table" then
        return nil, "Missing song.notes (need engine wrapper shape)"
    end
    if type(song.song) ~= "string" or song.song == "" then
        return nil, "Missing song.song (chart id)"
    end
    if type(song.bpm) ~= "number" or song.bpm <= 0 then
        return nil, "Missing valid song.bpm"
    end
    local total, holds, dropped = 0, 0, 0
    for _, section in ipairs(song.notes) do
        if type(section) == "table" and type(section.sectionNotes) == "table" then
            local kept = {}
            for _, row in ipairs(section.sectionNotes) do
                if type(row) == "table" and type(row[1]) == "number"
                    and type(row[2]) == "number" and row[1] >= 0
                    and row[2] >= 4 and row[2] <= 7 then
                    local sus = tonumber(row[3]) or 0
                    if sus < 0 then sus = 0 end
                    total += 1
                    if sus > 0 then holds += 1 end
                    kept[#kept + 1] = { row[1], math.floor(row[2]), sus }
                else
                    dropped += 1
                end
            end
            section.sectionNotes = kept
        end
    end
    if total == 0 then return nil, "All notes invalid (need [timeMs, lane 4-7, susMs] rows)" end
    -- SV-map anchor: the engine anchors cumulative track position at
    -- SV[1].startTime but runs raw time*speed before it, so a first SV
    -- after t=0 teleports every on-screen note at that timestamp
    -- (SOUND ARCHITECT glitch at 40.8s). osu! SV is implicitly 1.0 before
    -- the first inherited point; materialize it in-memory (never written
    -- back to the file). Idempotent: only when [1] starts > 0.
    data._svAnchored = false
    local sv = data.sliderVelocities
    if type(sv) == "table" and #sv > 0 then
        local first = sv[1]
        local t0 = type(first) == "table" and tonumber(first.startTime) or nil
        local m0 = type(first) == "table" and tonumber(first.multiplier) or nil
        if t0 ~= nil and t0 > 0 and m0 ~= nil and m0 == m0 then
            table.insert(sv, 1, { startTime = 0, multiplier = 1 })
            data._svAnchored = true
        end
    end
    data._noteCount = total
    data._holdCount = holds
    data._droppedNotes = dropped
    return data
end

local function chartInfo(chart, path)
    local bpmN = 0
    if type(chart.bpmChanges) == "table" then bpmN = #chart.bpmChanges end
    local svN = 0
    if type(chart.sliderVelocities) == "table" then svN = #chart.sliderVelocities end
    local anchorTag = ""
    if chart._svAnchored then
        svN -= 1 -- the prepended t0 anchor is engine plumbing, not a map SV
        anchorTag = " +t0-anchor"
    end
    local audioHint = ""
    if type(chart.song.audioFile) == "string" and chart.song.audioFile ~= "" then
        audioHint = " | audio: " .. chart.song.audioFile
    end
    return ("%s\n%s BPM | %d notes (%d holds) | %d BPM changes | %d SV%s%s%s"):format(
        basename(path),
        tostring(chart.song.bpm), chart._noteCount or 0, chart._holdCount or 0,
        bpmN, svN, anchorTag, audioHint,
        (chart._droppedNotes or 0) > 0
            and ("  (" .. chart._droppedNotes .. " invalid rows dropped)") or "")
end

local AUDIO_EXTS = { ".mp3", ".ogg", ".wav" }

local function listAudioFiles()
    local out = {}
    local ok, files = pcall(fn.listfiles, AUDIO_DIR)
    if ok and type(files) == "table" then
        for _, f in ipairs(files) do
            local lower = tostring(f):lower()
            for _, ext in ipairs(AUDIO_EXTS) do
                if lower:sub(-#ext) == ext then
                    table.insert(out, f)
                    break
                end
            end
        end
    end
    table.sort(out)
    return out
end

local selectedAudioPath = nil -- workspace path or nil (audio-free)

local function chartStem(name)
    return tostring(name or ""):lower()
        :gsub("%.chart%.json$", ""):gsub("%.json$", "")
end

-- Auto-pick <chartstem>.<ext>, else the chart's audioFile hint. Returns the
-- picked workspace path or nil.
local function automatchAudio(chart, chartPath)
    selectedAudioPath = nil
    local audios = listAudioFiles()
    local byLower = {}
    for _, p in ipairs(audios) do byLower[basename(p):lower()] = p end
    local stem = chartStem(basename(chartPath))
    for _, ext in ipairs(AUDIO_EXTS) do
        if byLower[stem .. ext] then
            selectedAudioPath = byLower[stem .. ext]
            return selectedAudioPath
        end
    end
    local hint = type(chart) == "table" and chart.song
        and chart.song.audioFile or nil
    if type(hint) == "string" and hint ~= "" then
        local base = basename(hint):lower()
        if byLower[base] then
            selectedAudioPath = byLower[base]
            return selectedAudioPath
        end
    end
    return nil
end

----------------------------------------------------------------
-- 4.5. Skin library (skins2afn packs; engine noteskin swap at Play)
----------------------------------------------------------------
local SKIN_DIRS = { "Left", "Down", "Up", "Right" }
local selectedSkinDir = nil      -- pack folder name under SKINS_DIR (or nil)
local selectedSkinManifest = nil -- decoded manifest.json table (or nil)
local skinByLabel = {}
local playSeq = 0

local function listSkinPacks()
    local out = {}
    local ok, files = pcall(fn.listfiles, SKINS_DIR)
    if ok and type(files) == "table" then
        for _, f in ipairs(files) do
            local mp = tostring(f) .. "/manifest.json"
            local okM, isF = pcall(fn.isfile, mp)
            if okM and isF then
                table.insert(out, tostring(f))
            end
        end
    end
    table.sort(out)
    return out
end

local function readSkinManifest(packDir)
    local ok, data = pcall(function()
        return HttpService:JSONDecode(fn.readfile(tostring(packDir) .. "/manifest.json"))
    end)
    if not ok or type(data) ~= "table" then return nil, "bad manifest JSON" end
    if data.format ~= "afn-skin/1" or type(data.dirs) ~= "table" then
        return nil, "unsupported skin format"
    end
    for _, d in ipairs(SKIN_DIRS) do
        local e = data.dirs[d]
        if type(e) ~= "table" or type(e.png) ~= "string" or type(e.xml) ~= "string" then
            return nil, "manifest missing direction " .. d
        end
    end
    return data
end

-- Select a pack folder (or nil = default game skin). Persists to Settings.
local function selectSkinDir(dirName)
    if dirName == nil then
        selectedSkinDir, selectedSkinManifest = nil, nil
        settings.skin = nil
        saveSettings()
        return true
    end
    local m, err = readSkinManifest(SKINS_DIR .. "/" .. tostring(dirName))
    if not m then return nil, err end
    selectedSkinDir, selectedSkinManifest = tostring(dirName), m
    settings.skin = selectedSkinDir
    saveSettings()
    return true
end

-- Build the engine noteskin Folder: per-direction ModuleScripts whose
-- Source returns the pack's Sparrow XML + Image attribute = the local PNG
-- (getcustomasset, same allowlisted pattern as audio). Pure instances;
-- no game state. Returns (folder, xmlByMod) or (nil, err).
local function buildSkinFolder(packDir, manifest, tag)
    local folder = Instance.new("Folder")
    folder.Name = tag
    local xmlByMod = {}
    for _, dirname in ipairs(SKIN_DIRS) do
        local e = manifest.dirs[dirname]
        local xmlOk, xml = pcall(fn.readfile, tostring(packDir) .. "/" .. e.xml)
        if not xmlOk or type(xml) ~= "string" or xml == "" then
            pcall(function() folder:Destroy() end)
            return nil, "skin xml unreadable: " .. dirname
        end
        local assetOk, uri = pcall(fn.getlocalasset, tostring(packDir) .. "/" .. e.png)
        if not assetOk or type(uri) ~= "string" or uri == "" then
            pcall(function() folder:Destroy() end)
            return nil, "skin png asset failed: " .. dirname
        end
        local mod = Instance.new("ModuleScript")
        mod.Name = dirname
        local okSrc, errSrc = pcall(function()
            mod.Source = "return " .. string.format("%q", xml)
        end)
        if not okSrc then
            pcall(function() mod:Destroy() end)
            pcall(function() folder:Destroy() end)
            return nil, "skin module source failed: " .. tostring(errSrc)
        end
        local okAttr, errAttr = pcall(function()
            mod:SetAttribute("Image", uri)
            mod:SetAttribute("SizeMult", 1)
            mod:SetAttribute("Factor", 1)
        end)
        if not okAttr then
            pcall(function() mod:Destroy() end)
            pcall(function() folder:Destroy() end)
            return nil, "skin module attribute failed: " .. tostring(errAttr)
        end
        mod.Parent = folder
        xmlByMod[mod] = xml
    end
    return folder, xmlByMod
end

----------------------------------------------------------------
-- 5. Underframe (background behind the highway)
----------------------------------------------------------------
local underframeGui = nil

local function destroyUnderframe()
    if underframeGui then
        pcall(function() underframeGui:Destroy() end)
        underframeGui = nil
    end
end

local function createUnderframe()
    destroyUnderframe()
    if not settings.bgEnabled then return end
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "AFNRayUnderframe"
    gui.DisplayOrder = -10
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    local bg = Instance.new("Frame")
    local c = settings.bgColor or { 0, 0, 0 }
    bg.BackgroundColor3 = Color3.fromRGB(c[1] or 0, c[2] or 0, c[3] or 0)
    bg.BackgroundTransparency = math.clamp(1 - (settings.bgTransparency or 0), 0, 1)
    bg.BorderSizePixel = 0
    bg.AnchorPoint = Vector2.new(0.5, 0.5)
    bg.Position = UDim2.fromScale(0.5, 0.5)
    bg.Size = UDim2.fromScale(1, 1)
    bg.Parent = gui
    gui.Parent = pg
    underframeGui = gui
end

----------------------------------------------------------------
-- 6. Play / Stop core (ported from player_core 1.3.0)
----------------------------------------------------------------
local playing = false
local lastReport = nil
local ctx = nil
local playStatusCallback = nil -- set by UI: function(text)

local function setStatus(text)
    if playStatusCallback then pcall(playStatusCallback, text) end
end

local function gate(rep, name, ok, extra)
    rep.gates[name] = ok and "pass" or ("FAIL:" .. tostring(extra or ""))
    if not ok then rep.stage = "aborted-preflight" end
    return ok
end

local function doTeardown(c)
    if type(c) ~= "table" then
        return { ok = false, error = "missing cleanup context" }
    end
    local idBefore = c.idBefore or 2
    c.cleanupDone = c.cleanupDone or {}
    c.teardownReport = c.teardownReport or {}
    local report = c.teardownReport

    local function step(name, f)
        if c.cleanupDone[name] then
            report[name] = "ok (already completed)"
            return true
        end
        local ok, err = pcall(f)
        if ok then
            c.cleanupDone[name] = true
            report[name] = "ok"
        else
            report[name] = "FAIL: " .. tostring(err)
        end
        return ok
    end

    step("abruptGameEnd", function()
        if c.loadAttempted then
            local f = type(c.env) == "table" and rawget(c.env, "abruptGameEnd") or nil
            if type(f) ~= "function" then error("abruptGameEnd unavailable during cleanup") end
            local ok, err = atGameIdentity(idBefore, function() f() end)
            if not ok then error(err) end
        end
    end)
    step("leaveLoadingState", function()
        if c.loadingStateTouched then
            local f = type(c.env) == "table" and rawget(c.env, "leaveLoadingState") or nil
            if type(f) ~= "function" then error("leaveLoadingState unavailable during cleanup") end
            local ok, err = atGameIdentity(idBefore, function() f() end)
            if not ok then error(err) end
        end
    end)
    step("idle-flags", function()
        if type(c.t7) ~= "table" then error("song state table unavailable") end
        if type(c.t21) ~= "table" then error("gameplay module unavailable") end
        rawset(c.t7, "loadedSong", false)
        rawset(c.t7, "inSong", false)
        rawset(c.t21, "inSong", false)
        if rawget(c.t21, "songData") ~= nil then
            rawset(c.t21, "songData", nil)
        end
        if rawget(c.t7, "loadedSong") == true
            or rawget(c.t7, "inSong") == true
            or rawget(c.t21, "inSong") == true then
            error("one or more idle flags remain true after forceIdle")
        end
    end)
    step("pools-notes", function()
        if type(c.gcMod) ~= "table" then error("gameplay pools unavailable") end
        for _, name in ipairs({ "Notes", "UnspawnedNotes" }) do
            local pool = rawget(c.gcMod, name)
            if type(pool) ~= "table" then error(name .. " pool is not a table") end
            for key in next, pool do rawset(pool, key, nil) end
            if poolCount(c.gcMod, name) ~= 0 then error(name .. " pool not empty after wipe") end
        end
    end)
    step("pools-strums", function()
        if type(c.gcMod) == "table" then
            for _, name in ipairs({ "Strums", "Strumlines" }) do
                local pool = rawget(c.gcMod, name)
                if type(pool) == "table" then
                    for key in next, pool do rawset(pool, key, nil) end
                end
            end
        end
    end)
    step("autoplay", function()
        if c.autoplaySet then
            local apFn = type(c.t21) == "table" and rawget(c.t21, "SetAutoplay") or nil
            if type(apFn) ~= "function" then error("autoplay setter unavailable") end
            local ok, err = atGameIdentity(c.idBefore, function() apFn(false) end)
            if not ok then error(err) end
            c.autoplaySet = false
        end
    end)
    step("skin", function()
        if c.skinFolder ~= nil then
            -- Drop our set from the engine's persistent noteskin cache
            -- (keyed by our unique folder name). Best-effort: with unique
            -- per-play names a leftover entry is inert, never a stale hit.
            local cacheNote = "untouched"
            if c.skinCachePath ~= nil and type(c.t21) == "table" then
                local cnFn = rawget(c.t21, "cacheNoteskin")
                if type(cnFn) == "function" then
                    local okU, a, b = pcall(function()
                        return debug.getupvalue(cnFn, 3)
                    end)
                    if okU then
                        local t143 = (type(a) == "string") and b or a
                        local sets = type(t143) == "table"
                            and rawget(t143, "noteSets") or nil
                        if type(sets) == "table" then
                            rawset(sets, c.skinCachePath, nil)
                            cacheNote = "cleared"
                        end
                    end
                end
            end
            report.skinCache = cacheNote
            c.skinFolder:Destroy()
            if c.skinFolder.Parent ~= nil then error("skin folder still parented") end
            c.skinFolder = nil
            c.skinXmlByMod = nil
        end
    end)
    step("require", function()
        if c.reqPatched then
            if type(c.env) ~= "table" then error("require environment unavailable") end
            rawset(c.env, "require", c.prevReq)
            if rawget(c.env, "require") ~= c.prevReq then error("require environment was not restored") end
            c.reqPatched = false
        end
        if c.spriteReqPatched then
            if type(c.spriteEnv) ~= "table" then error("sprite require environment unavailable") end
            rawset(c.spriteEnv, "require", c.prevSpriteReq)
            if rawget(c.spriteEnv, "require") ~= c.prevSpriteReq then
                error("sprite require environment was not restored")
            end
            c.spriteReqPatched = false
        end
    end)
    step("charRemote", function()
        if c.charRemote ~= nil then
            if c.charRemoteParent == nil then error("original Character parent missing") end
            c.charRemote.Parent = c.charRemoteParent
            if c.charRemote.Parent ~= c.charRemoteParent then error("Character remote parent was not restored") end
        end
    end)
    step("charTempFolder", function()
        if c.charTempFolder ~= nil then
            c.charTempFolder:Destroy()
            if c.charTempFolder.Parent ~= nil then error("temporary remote folder still parented") end
        end
    end)
    step("ratingsClone", function()
        if c.ratingsClone ~= nil then
            c.ratingsClone:Destroy()
            if c.ratingsClone.Parent ~= nil then error("ratings clone still parented") end
        end
    end)
    step("registry", function()
        if c.registryTouched then
            local sid = type(c.t1) == "table" and rawget(c.t1, "songIds") or nil
            if type(sid) ~= "table" then error("songIds unavailable during cleanup") end
            sid[MOD_NAME] = c.previousSongEntry
            if sid[MOD_NAME] ~= c.previousSongEntry then error("registry entry was not restored") end
        end
    end)
    step("holder", function()
        if c.holder ~= nil then
            c.holder:Destroy()
            if c.holder.Parent ~= nil then error("temporary chart holder still parented") end
        end
    end)
    pcall(destroyUnderframe)

    local allOk = true
    for _, status in next, report do
        if type(status) == "string" and status:sub(1, 5) == "FAIL:" then
            allOk = false
        end
    end
    report.ok = allOk
    return report
end

local function stopChart()
    local rep = { stage = "stop", ok = false }
    if not playing and ctx == nil then
        rep.stage = "idle"
        rep.ok = true
        lastReport = rep
        return rep
    end
    local c = ctx
    if c and (c.phase == "preparing" or c.phase == "finishing") then
        rep.stage = "busy-initializing"
        rep.ok = false
        rep.err = "Wait for startup to return, then retry Stop"
        lastReport = rep
        return rep
    end
    local cleanup = doTeardown(c)
    rep.cleanup = cleanup
    rep.ok = cleanup.ok == true
    if rep.ok then
        rep.err = nil
    else
        rep.err = "one or more cleanup steps failed; Stop may be retried"
    end
    if rep.ok then
        ctx = nil
        playing = false
        rep.stage = "stopped"
        setStatus("Idle")
    else
        rep.stage = "cleanup-incomplete"
        playing = true
    end
    lastReport = rep
    return rep
end

-- Read-only preflight. Does not mutate game state.
local function preflight()
    local rep = { stage = "preflight", gates = {}, errors = {} }
    if playing then
        gate(rep, "not-playing", false, "already playing; Stop first")
        return false, rep
    end
    if not gate(rep, "place", game.PlaceId == EXP_PLACE, game.PlaceId) then
        return false, rep
    end

    local loadSong, attempts = findFnByLine(LOADSONG_LINE)
    rep.gates["locator-attempts"] = tostring(attempts or "?")
    if not gate(rep, "loadSong-found", loadSong ~= nil) then return false, rep end

    local t1, t7, t21
    for i = 1, 9 do
        local v = upval(loadSong, i)
        if type(v) == "table" then
            if rawget(v, "SongPlayer") ~= nil then t1 = v
            elseif rawget(v, "loadedSong") ~= nil then t7 = v
            elseif rawget(v, "parseChart") ~= nil then t21 = v end
        end
    end
    if not gate(rep, "upvalues-t1-t7-t21", t1 ~= nil and t7 ~= nil and t21 ~= nil) then
        return false, rep
    end

    local okE, env = pcall(function() return getfenv(loadSong) end)
    if not gate(rep, "getfenv-ok", okE and type(env) == "table") then return false, rep end
    if not gate(rep, "env-abruptGameEnd", type(rawget(env, "abruptGameEnd")) == "function") then return false, rep end
    if not gate(rep, "env-enterLoadingState", type(rawget(env, "enterLoadingState")) == "function") then return false, rep end
    if not gate(rep, "env-leaveLoadingState", type(rawget(env, "leaveLoadingState")) == "function") then return false, rep end

    if not gate(rep, "idle-not-loaded", rawget(t7, "loadedSong") == false) then return false, rep end
    if not gate(rep, "idle-not-insong", rawget(t7, "inSong") == false) then return false, rep end
    local nf = rawget(t1, "NetworkFunctions")
    if not gate(rep, "stageRemote-nil", nf ~= nil and rawget(nf, "stageRemote") == nil) then return false, rep end
    if not gate(rep, "songIds-table", type(rawget(t1, "songIds")) == "table") then
        return false, rep
    end
    if not gate(rep, "v963-false", upval(loadSong, 1) == false) then return false, rep end

    local lp = Players.LocalPlayer
    local okD, dm = pcall(function() return require(RS.Modules.Data.DataManager) end)
    if not gate(rep, "datamanager", okD) then return false, rep end
    local okG, data = pcall(function() return dm:GetData() end)
    if not gate(rep, "getdata", okG and type(data) == "table") then return false, rep end
    rep.gates["style"] = tostring(data.JudgementStyle)
    if not gate(rep, "hideLobby-false", data.HideLobby == false, data.HideLobby) then return false, rep end
    if not gate(rep, "backgroundDim", (tonumber(data.BackgroundDim) or 0) > 0.05, data.BackgroundDim) then
        return false, rep
    end

    local ch = lp.Character
    if not gate(rep, "character", ch ~= nil) then return false, rep end
    if not gate(rep, "descriptionReady", ch:GetAttribute("DescriptionReady") == true) then return false, rep end

    local pg = lp:FindFirstChildOfClass("PlayerGui")
    local main = pg and pg:FindFirstChild("Main")
    if not gate(rep, "main-ui", main ~= nil) then return false, rep end
    local cont = pg and pg:FindFirstChild("__AssetContainer")
    local ratings = cont and cont:FindFirstChild("Ratings")
    local afnRatings = ratings and ratings:FindFirstChild("Afternight")
    if not gate(rep, "ratings-afternight-cached", afnRatings ~= nil) then return false, rep end

    local gcMod = nil
    for _, v in next, getgc(true) do
        if type(v) == "table" and rawget(v, "parseChart") ~= nil and rawget(v, "addNotesFromChart") ~= nil then
            gcMod = v
            break
        end
    end
    if not gate(rep, "gc-module", gcMod ~= nil) then return false, rep end

    rep.pools = {
        UnspawnedNotes = poolCount(gcMod, "UnspawnedNotes"),
        Notes = poolCount(gcMod, "Notes"),
        Strums = poolCount(gcMod, "Strums"),
        Strumlines = poolCount(gcMod, "Strumlines"),
    }
    local su = rep.pools.Strums
    local sl = rep.pools.Strumlines
    local un = rep.pools.UnspawnedNotes
    local no = rep.pools.Notes
    if (type(un) == "number" and un > 0) or (type(no) == "number" and no > 0) then
        gate(rep, "clean-note-pools", false, "Notes/UnspawnedNotes non-zero; press Stop then retry")
        return false, rep
    end
    if (type(su) == "number" and su > 0) or (type(sl) == "number" and sl > 0) then
        gate(rep, "clean-strum-residue", false, "Strums/Strumlines non-zero; retry Stop cleanup before Play")
        return false, rep
    end

    rep.stage = "ready"
    rep._refs = {
        loadSong = loadSong, t1 = t1, t7 = t7, t21 = t21, env = env,
        nf = nf, data = data, gcMod = gcMod, main = main, pg = pg,
        ratings = ratings, afnRatings = afnRatings,
        charRemote = main:FindFirstChild("Character"),
    }
    return true, rep
end

local function playChart()
    local rep = { stage = "init", gates = {}, subs = {}, errors = {} }
    lastReport = rep

    if playing then
        rep.aborted = "already-playing"
        rep.stage = "aborted"
        return rep
    end
    if type(currentChart) ~= "table" then
        rep.aborted = "no-chart"
        rep.stage = "aborted"
        return rep
    end

    -- Encode a play copy so audio offset / SV flatten never mutate the
    -- loaded chart. SV flatten empties the map: the engine then takes the
    -- raw-ms path everywhere (the proven-clean configuration) for a
    -- constant scroll feel regardless of map SVs.
    local chartJson
    do
        local off = tonumber(settings.offsetMs) or 0
        local flat = settings.ignoreSV and true or false
        local songName = tostring(currentChart.song.song)
        if off ~= 0 or flat then
            local copy = HttpService:JSONDecode(HttpService:JSONEncode(currentChart))
            if off ~= 0 then
                for _, section in ipairs(copy.song.notes) do
                    if type(section) == "table" and type(section.sectionNotes) == "table" then
                        for _, row in ipairs(section.sectionNotes) do
                            if type(row) == "table" and type(row[1]) == "number" then
                                row[1] = math.max(0, row[1] + off)
                            end
                        end
                    end
                end
                rep.subs["audio-offset-ms"] = tostring(off)
            end
            if flat then
                local n = type(copy.sliderVelocities) == "table" and #copy.sliderVelocities or 0
                copy.sliderVelocities = {}
                rep.subs["sv-flat"] = "emptied(" .. tostring(n) .. ")"
            else
                rep.subs["sv-flat"] = "off"
            end
            chartJson = HttpService:JSONEncode(copy)
        else
            chartJson = HttpService:JSONEncode(currentChart)
            rep.subs["sv-flat"] = "off"
        end
        rep.songName = songName
    end
    rep.diff = DEFAULT_DIFF
    if currentChart._svAnchored then rep.subs["sv-anchor"] = "t0 x1.0" end

    local okPf, pf = preflight()
    for k, v in next, (pf and pf.gates) or {} do rep.gates[k] = v end
    if not okPf then
        rep.stage = pf and pf.stage or "aborted-preflight"
        rep.pools_before = pf and pf.pools
        return rep
    end
    local r = pf._refs
    local loadSong, t1, t7, t21, env = r.loadSong, r.t1, r.t7, r.t21, r.env
    local nf, data, gcMod = r.nf, r.data, r.gcMod
    local main, pg, ratings, afnRatings = r.main, r.pg, r.ratings, r.afnRatings
    local charRemote = r.charRemote
    rep.pools_before = pf.pools
    rep.subs["judgementStyle"] = tostring(data.JudgementStyle)
    rep.subs["charRemote-class"] = charRemote and charRemote.ClassName or "nil"

    local idBefore = getthreadidentity()
    rep.subs["identity-before"] = tostring(idBefore)

    local c = {
        env = env, t1 = t1, t7 = t7, t21 = t21, nf = nf, gcMod = gcMod,
        main = main, charRemote = charRemote, idBefore = idBefore,
        reqPatched = false, prevReq = nil,
        spriteEnv = nil, prevSpriteReq = nil, spriteReqPatched = false,
        ratingsClone = nil, charTempFolder = nil, charRemoteParent = nil,
        skinFolder = nil, skinXmlByMod = nil, skinName = nil,
        skinCachePath = nil, skinApplied = false, judgeSwap = nil,
        judgeAnnounced = false, judgeErrShown = false,
        cleanupDone = {}, teardownReport = {}, holder = nil,
        previousSongEntry = rawget(rawget(t1, "songIds"), MOD_NAME),
        registryTouched = false, loadingStateTouched = false, loadAttempted = false,
        phase = "preparing",
    }

    ctx = c
    playing = true
    setStatus("Preparing...")
    local function abortPlay(report, stage)
        report.stage = stage
        c.phase = "cleaning"
        local stopped = stopChart()
        report.teardown = stopped.cleanup
        report.teardown_ok = stopped.ok
        if not stopped.ok then report.stage = "cleanup-incomplete" end
        return report
    end
    local okTxn, txnResult = xpcall(function()
        -- 1. Ratings clone (asset cache hit, no server fetch on miss)
        local styleKey = tostring(data.JudgementStyle)
        if ratings:FindFirstChild(styleKey) == nil then
            c.ratingsClone = afnRatings:Clone()
            c.ratingsClone.Name = styleKey
            c.ratingsClone.Parent = ratings
            rep.subs["ratings-clone"] = "created"
        else
            rep.subs["ratings-clone"] = "already-cached"
        end

        -- 2. Loading pre-flip (skips preview overhead)
        do
            local songName = rep.songName
            local okF, errF = pcall(function()
                rawget(env, "enterLoadingState")({
                    Sides = { L = {}, R = {} },
                    PlayerAmmo = { L = 0, R = 0 },
                    IsSolo = false,
                    Mod = MOD_NAME,
                    Song = songName,
                    Difficulty = DEFAULT_DIFF,
                    Rate = 1,
                })
            end)
            c.loadingStateTouched = true
            rep.subs["loading-preflip"] = okF and "v85=true" or ("FAIL:" .. tostring(errF))
            if not okF then
                return abortPlay(rep, "aborted-subs")
            end
        end

        -- 3. Relocate Character remote (character Replicate() no-ops)
        if charRemote ~= nil then
            c.charRemoteParent = charRemote.Parent
            c.charTempFolder = Instance.new("Folder")
            c.charTempFolder.Name = "AFNRay_RemoteHold"
            c.charTempFolder.Parent = pg
            charRemote.Parent = c.charTempFolder
            rep.subs["charRemote-moved"] = (main:FindFirstChild("Character") == nil) and "moved" or "MOVE-FAIL"
        else
            rep.subs["charRemote-moved"] = "already-nil"
        end

        -- 4. Synthesize package
        rep.stage = "synth"
        local old = RS:FindFirstChild("AFNRay_Play")
        if old then pcall(function() old:Destroy() end) end
        local holder = Instance.new("Folder")
        holder.Name = "AFNRay_Play"
        c.holder = holder
        holder.Parent = RS

        local chartMod = Instance.new("ModuleScript")
        chartMod.Name = DEFAULT_DIFF
        chartMod.Parent = holder
        local okSrc, errSrc = pcall(function()
            -- %q quotes/escapes the JSON as one Luau string literal; never
            -- embed untrusted JSON inside a fixed long-bracket delimiter.
            chartMod.Source = "return " .. string.format("%q", chartJson)
        end)
        rep.synth_sourceWrite = okSrc and "ok" or ("FAIL:" .. tostring(errSrc))
        if not okSrc then
            return abortPlay(rep, "synth-failed")
        end
        pcall(function() chartMod:SetAttribute("_CachedAudio", CACHED_AUDIO) end)

        local songInst = Instance.new("Folder")
        songInst.Name = rep.songName
        songInst.Parent = holder
        local modInst = Instance.new("Folder")
        modInst.Name = MOD_NAME
        modInst.Parent = holder

        local okReq, reqRes = pcall(function() return require(chartMod) end)
        rep.synth_require = okReq and ("string-len=" .. #tostring(reqRes)) or ("FAIL:" .. tostring(reqRes))
        if not (okReq and type(reqRes) == "string") then
            return abortPlay(rep, "synth-require-failed")
        end
        local okJ, decJ = pcall(function()
            return HttpService:JSONDecode(reqRes)
        end)
        rep.synth_json = okJ and "decodes" or ("FAIL:" .. tostring(decJ))
        if not okJ then
            return abortPlay(rep, "synth-json-failed")
        end

        local okW = pcall(function()
            c.prevReq = rawget(env, "require")
            local baseReq = c.prevReq or require
            rawset(env, "require", function(mod)
                if mod == chartMod then return chartJson end
                if c.skinXmlByMod ~= nil then
                    local sxml = rawget(c.skinXmlByMod, mod)
                    if type(sxml) == "string" then return sxml end
                end
                return baseReq(mod)
            end)
        end)
        c.reqPatched = okW and type(rawget(env, "require")) == "function"
        rep.subs["require-wrap"] = c.reqPatched and "installed" or "FAIL"
        if not c.reqPatched then
            return abortPlay(rep, "require-wrap-failed")
        end

        -- 5. Registry entry (+ local audio Content, resolved live)
        c.registryTouched = true
        local songEntry = { SkipCountdown = true }
        if selectedAudioPath ~= nil then
            local audioPath = tostring(selectedAudioPath)
            rep.audioFile = audioPath
            local okA, content = pcall(function()
                return Content.fromUri(fn.getlocalasset(audioPath))
            end)
            local isContent = false
            if okA and content ~= nil then
                local okT = pcall(function()
                    isContent = (typeof(content) == "Content")
                end)
                if not okT then isContent = false end
            end
            if not isContent then
                rep.audio_err = "audio resolve failed: " .. tostring(content)
                return abortPlay(rep, "audio-resolve-failed")
            end
            songEntry.Audio = { Instrumental = content, Volume = 1 }
            rep.subs["audio"] = "local:" .. audioPath
        else
            rep.subs["audio"] = "none(free-run)"
        end
        rawget(t1, "songIds")[MOD_NAME] = {
            Songs = { [rep.songName] = songEntry },
            Metadata = {},
        }

        -- 6. Load through the real orchestrator (identity 2, restored after)
        rep.stage = "loading"
        local pkg = {
            Chart = chartMod,
            Song = songInst,
            Mod = modInst,
            ModchartsEnabled = false,
            GimmicksEnabled = false,
        }
        local okL, errL = atGameIdentity(idBefore, function()
            c.loadAttempted = true
            return loadSong(pkg, "R", 1, nil, { L = {}, R = {} }, 0, { L = {}, R = {} }, nil, nil)
        end)
        rep.subs["identity-restored"] = (getthreadidentity() == idBefore) and "yes" or "NO"
        rep.load_ok = okL
        rep.load_err = okL and nil or tostring(errL)
        rep.load_inSong = rawget(t7, "inSong")
        rep.load_songData = (t21 ~= nil and rawget(t21, "songData") ~= nil) and "present" or "missing"
        if not okL then
            pcall(function() debug.setupvalue(loadSong, 1, false) end)
            if t7 ~= nil then pcall(function() rawset(t7, "inSong", false) end) end
            if t21 ~= nil then pcall(function() rawset(t21, "inSong", false) end) end
            rep.v963_repaired = upval(loadSong, 1) == false and "yes" or "NO"
            return abortPlay(rep, "load-failed-cleaned")
        end
        rep.pools_after_load = {
            UnspawnedNotes = poolCount(gcMod, "UnspawnedNotes"),
            Notes = poolCount(gcMod, "Notes"),
            Strums = poolCount(gcMod, "Strums"),
            Strumlines = poolCount(gcMod, "Strumlines"),
        }

        -- 7. Start (local listen function; stage remote kept nil)
        rep.stage = "starting"
        rawset(nf, "stageRemote", nil)
        local startFn = rawget(nf, "remoteListen") and rawget(nf, "remoteListen")["Start"]
        rep.start_listener = type(startFn)
        if type(startFn) ~= "function" then
            return abortPlay(rep, "no-start-listener-cleaned")
        end
        local okS, errS = atGameIdentity(idBefore, function() startFn(0) end)
        rep.start_ok = okS
        rep.start_err = okS and nil or tostring(errS)
        rep.start_loadedSong = rawget(t7, "loadedSong")
        if not okS then
            return abortPlay(rep, "start-failed-cleaned")
        end

        -- 8. Autoplay (engine botplay flag; reset in teardown)
        if settings.autoplay then
            local apFn = rawget(t21, "SetAutoplay")
            if type(apFn) ~= "function" then
                return abortPlay(rep, "autoplay-unavailable")
            end
            local okA, errA = atGameIdentity(idBefore, function() apFn(true) end)
            c.autoplaySet = okA and true or false
            rep.subs["autoplay"] = okA and "on" or ("FAIL:" .. tostring(errA))
            if not okA then
                return abortPlay(rep, "autoplay-failed")
            end
        else
            rep.subs["autoplay"] = "off(manual)"
        end

        -- 8.5. Custom skin (engine noteskin swap on side R; teardown clears
        -- the set-cache entry and destroys the synth folder, so the next
        -- play re-resolves the game skin from settings).
        if selectedSkinDir ~= nil then
            playSeq += 1
            local packDir = SKINS_DIR .. "/" .. tostring(selectedSkinDir)
            local manifest = selectedSkinManifest
            if type(manifest) ~= "table" then
                manifest = readSkinManifest(packDir)
            end
            if type(manifest) ~= "table" then
                return abortPlay(rep, "skin-manifest-unreadable")
            end
            local folder, xmlByMod = buildSkinFolder(packDir, manifest,
                "AFNRaySkin_" .. tostring(MYGEN) .. "_" .. tostring(playSeq))
            if not folder then
                rep.skin_err = tostring(xmlByMod)
                return abortPlay(rep, "skin-build-failed")
            end
            folder.Parent = holder
            c.skinFolder = folder
            c.skinXmlByMod = xmlByMod
            c.skinName = tostring(selectedSkinDir)
            c.skinCachePath = folder.Name
            -- The Sprite module (frame parsing) runs in a different env
            -- table than loadSong (proven live: same require via different
            -- env), so the require-wrap must be installed there too, or
            -- require(synthModule) falls through to the engine and fails.
            -- Reuses the chart wrapper (it already consults skinXmlByMod).
            local spriteEnv = nil
            for _, o in ipairs(getgc(true)) do
                if type(o) == "function" then
                    local okS, s = pcall(function() return debug.info(o, "s") end)
                    if okS and type(s) == "string"
                        and string.find(s, "Modules.Main.Sprite", 1, true) then
                        local okE, e = pcall(getfenv, o)
                        if okE and type(e) == "table" then
                            spriteEnv = e
                            break
                        end
                    end
                end
            end
            if spriteEnv == nil then
                return abortPlay(rep, "skin-sprite-env-missing")
            end
            local okW2 = pcall(function()
                c.prevSpriteReq = rawget(spriteEnv, "require")
                c.spriteEnv = spriteEnv
                rawset(spriteEnv, "require", rawget(env, "require"))
            end)
            c.spriteReqPatched = okW2 and type(rawget(spriteEnv, "require")) == "function"
            rep.subs["skin-require-wrap"] = c.spriteReqPatched and "installed" or "FAIL"
            if not c.spriteReqPatched then
                return abortPlay(rep, "skin-require-wrap-failed")
            end
            local skinFn = rawget(t21, "loadNoteskin")
            if type(skinFn) ~= "function" then
                return abortPlay(rep, "skin-loader-unavailable")
            end
            local okK, errK = atGameIdentity(idBefore, function()
                skinFn("R", folder)
            end)
            c.skinApplied = okK and true or false
            rep.subs["skin"] = okK and ("custom:" .. c.skinName)
                or ("FAIL:" .. tostring(errK))
            if not okK then
                return abortPlay(rep, "skin-apply-failed")
            end
        else
            rep.subs["skin"] = "default"
        end

        -- 8.6. Judgement/combo art swap data (a poll loop in doPlay swaps
        -- spawned popups; nothing persists: popups are engine-owned and die
        -- on their own, so there is no teardown counterpart).
        -- Engine art paths hard-prefix rbxassetid://, so local PNGs can only
        -- be applied by overwriting spawned popups with local URIs.
        do
            local jm = selectedSkinManifest
            local hasArt = selectedSkinDir ~= nil and type(jm) == "table"
                and (type(jm.judgements) == "table"
                    or type(jm.digits) == "table")
            if hasArt then
                local packDir = SKINS_DIR .. "/" .. tostring(selectedSkinDir)
                -- NOTE: popup .Image requires a ContentId STRING here (assigning
                -- a Content object throws "ContentId expected"); audio is the
                -- opposite (SongPlayer wants Content). Same getcustomasset URIs.
                local function skinContent(rel)
                    local okC, uri = pcall(fn.getlocalasset, packDir .. "/" .. rel)
                    if not okC or type(uri) ~= "string" or uri == "" then return nil end
                    return uri
                end
                local judgeArts, digitArts = {}, {}
                if type(jm.judgements) == "table" then
                    local prefs = {
                        marvelous = {"300g", "300"}, sick = {"300", "300g"},
                        good = {"200", "100"}, bad = {"100", "50"},
                        ok = {"50", "100"}, miss = {"0"},
                    }
                    for rating, keys in pairs(prefs) do
                        for _, key in ipairs(keys) do
                            local rel = jm.judgements[key]
                            if type(rel) == "string" then
                                local art = skinContent(rel)
                                if art ~= nil then
                                    judgeArts[rating] = art
                                    break
                                end
                            end
                        end
                    end
                end
                if type(jm.digits) == "table" then
                    for d = 0, 9 do
                        local rel = jm.digits[tostring(d)]
                        if type(rel) == "string" then
                            local art = skinContent(rel)
                            if art ~= nil then digitArts[tostring(d)] = art end
                        end
                    end
                end
                -- asset-id -> rating map from game settings (defensive:
                -- without it judgement popups can't be attributed, but
                -- combo digits (offset/100, no map needed) still swap).
                local idmap = {}
                do
                    local okJ, ji = pcall(function() return data.JudgementImages end)
                    if okJ and type(ji) == "table" then
                        for nm, idv in pairs(ji) do
                            local s = tostring(idv)
                            idmap[s] = tostring(nm):lower()
                            local digits = s:match("(%d+)$")
                            if digits then idmap[digits] = tostring(nm):lower() end
                        end
                    end
                end
                local container = rawget(t21, "RatingsContainer")
                if typeof(container) ~= "Instance" then container = nil end
                if (next(judgeArts) ~= nil or next(digitArts) ~= nil)
                    and container ~= nil then
                    -- Popups may land in a sibling of the container (method
                    -- OnRating/OnCombo can reparent), so scan the parent
                    -- subtree (capped per tick in the poll fn).
                    local scanRoot = container
                    local okP, parent = pcall(function() return container.Parent end)
                    if okP and typeof(parent) == "Instance" then
                        scanRoot = parent
                    end
                    c.judgeSwap = {
                        container = container, scanRoot = scanRoot,
                        judgeArts = judgeArts, digitArts = digitArts,
                        idmap = idmap, swapped = 0, scanned = 0,
                    }
                    local function countKeys(t)
                        local n = 0
                        for _ in next, t do n += 1 end
                        return n
                    end
                    rep.subs["judgeswap"] = ("armed arts=%d digits=%d map=%d"):format(
                        countKeys(judgeArts), countKeys(digitArts), countKeys(idmap))
                    if next(judgeArts) ~= nil and next(idmap) == nil then
                        rep.subs["judgeswap"] = rep.subs["judgeswap"] .. "(digits-only)"
                    end
                else
                    rep.subs["judgeswap"] = (container == nil) and "no-container" or "no-art"
                end
            else
                rep.subs["judgeswap"] = "off"
            end
        end

        -- 8.7. Sustain clipping (hold bodies pin at receptors while held
        -- instead of sliding over them; purely visual, hit logic untouched).
        -- Flag lives on throwaway strumline objects (pools read 0 after
        -- teardown), so there is nothing to restore.
        do
            local clipFn = rawget(t21, "setSustainClipping")
            if type(clipFn) ~= "function" then
                return abortPlay(rep, "clip-loader-unavailable")
            end
            local okC, errC = atGameIdentity(idBefore, function()
                clipFn("R", true)
            end)
            rep.subs["clip"] = okC and "R=true" or ("FAIL:" .. tostring(errC))
            if not okC then
                return abortPlay(rep, "clip-apply-failed")
            end
        end

        -- Sample one note for the report
        do
            local up = rawget(gcMod, "UnspawnedNotes")
            if type(up) == "table" then
                for _, n in next, up do
                    if type(n) == "table" then
                        rep.note0 = {
                            strumTime = rawget(n, "strumTime"),
                            column = rawget(n, "column"),
                            side = rawget(n, "side"),
                            mustPress = rawget(n, "mustPress"),
                        }
                        break
                    end
                end
            end
        end

        c.phase = "playing"
        rep.stage = "playing"
        setStatus("Playing: " .. tostring(rep.songName))
        pcall(createUnderframe)

        -- Song-end watcher: at the audio-clock end, run the engine's own
        -- endSong(true) for the local results screen; results stay up until
        -- the user's Stop. Audio-free plays have no clock end (Stop-only).
        task.spawn(function()
            while ctx == c and playing and c.phase == "playing" do
                task.wait(0.5)
                if ctx ~= c or not playing or c.phase ~= "playing" then break end
                local sp = getSongPlayer(c)
                if type(sp) == "table" then
                    local tl, tp = rawget(sp, "timeLength"), rawget(sp, "timePosition")
                    local paused = rawget(sp, "paused")
                    if type(tl) == "number" and tl > 0 and type(tp) == "number"
                        and paused == false and (tl - tp) <= 0.25 then
                        c.phase = "finishing"
                        rep.finished = "song-end-detected"
                        local endFn = rawget(c.t21, "endSong")
                        local okE, errE
                        if type(endFn) == "function" then
                            okE, errE = atGameIdentity(c.idBefore, function() endFn(true) end)
                        else
                            okE, errE = false, "endSong unavailable"
                        end
                        rep.finish_ok = okE
                        rep.finish_err = okE and nil or tostring(errE)
                        if okE then
                            c.phase = "ended"
                            rep.stage = "ended-results"
                            setStatus("Finished — results on screen")
                        else
                            c.phase = "cleaning"
                            local stopRep = stopChart()
                            rep.teardown = stopRep.cleanup
                            rep.teardown_ok = stopRep.ok
                            rep.stage = "ended-fallback-stop"
                        end
                        break
                    end
                end
            end
        end)
        lastReport = rep
        return rep
    end, debug.traceback)

    if not okTxn then
        rep.stage = "unexpected-error"
        rep.err = tostring(txnResult)
        c.phase = "cleaning"
        local stopRep = stopChart()
        rep.teardown = stopRep.cleanup
        rep.teardown_ok = stopRep.ok
        if not stopRep.ok then rep.stage = "cleanup-incomplete" end
        lastReport = rep
        return rep
    end
    lastReport = txnResult
    return txnResult
end

-- One judge-swap poll tick: overwrite newly spawned judgement/combo popup
-- art with the skin's local Content. Identification is exact, never fuzzy:
-- FNF_Rating popups attribute via the asset-id map; FNF_Combo digit labels
-- read their digit from ImageRectOffset.X/100 (combo text is pure digits).
-- FNF_Offset popups are skipped (symbol slots are indistinguishable from
-- digit 0). Handled popups get a marker attribute; returns swap count.
local function pollJudgeSwap(js)
    local n = 0
    if type(js) ~= "table" then return 0 end
    local root = js.scanRoot
    if typeof(root) ~= "Instance" then return 0 end
    local okG, kids = pcall(function() return root:GetDescendants() end)
    if not okG or type(kids) ~= "table" then return 0 end
    js.scanned = #kids
    local visited = 0
    for _, d in ipairs(kids) do
        if n >= 30 then break end
        visited += 1
        if visited > 600 then break end
        if typeof(d) == "Instance" and d:IsA("ImageLabel") then
            local okM, marked = pcall(function() return d:GetAttribute("_AFNSwapped") end)
            if not (okM and marked) then
                local done = false
                if d.Name == "FNF_Rating" and next(js.judgeArts) ~= nil
                    and next(js.idmap) ~= nil then
                    local okI, img = pcall(function() return d.Image end)
                    if okI then
                        local imgS = tostring(img)
                        local rating = js.idmap[imgS]
                            or js.idmap[(imgS:match("(%d+)$") or "")]
                        local art = rating and js.judgeArts[rating] or nil
                        if art ~= nil then
                            local okS = pcall(function()
                                d.Image = art
                                d:SetAttribute("_AFNSwapped", true)
                            end)
                            if okS then n += 1 js.swapped += 1 done = true end
                        end
                    end
                elseif d.Name == "FNF_Combo" then
                    local okO, off = pcall(function() return d.ImageRectOffset end)
                    if okO and typeof(off) == "Vector2" then
                        local digit = math.floor(off.X / 100 + 0.5)
                        local art = (digit >= 0 and digit <= 9)
                            and js.digitArts[tostring(digit)] or nil
                        if art ~= nil then
                            local okS = pcall(function()
                                d.Image = art
                                d.ImageRectOffset = Vector2.new(0, 0)
                                d:SetAttribute("_AFNSwapped", true)
                            end)
                            if okS then n += 1 js.swapped += 1 done = true end
                        end
                    end
                elseif d.Name == "FNF_Offset" then
                    -- Offset popups (ms readouts) mix digit and symbol slots
                    -- under one strip image; swapping would corrupt symbols.
                    -- Mark handled so they are not rescanned.
                    pcall(function() d:SetAttribute("_AFNSwapped", true) end)
                    done = true
                end
                if not done then
                    -- Unmappable (unknown art id / missing digit art): mark to
                    -- skip rescanning; the mapping is fixed for this play.
                    pcall(function() d:SetAttribute("_AFNSwapped", true) end)
                end
            end
        end
    end
    return n
end

local function summarizeReport(rep)
    if type(rep) ~= "table" then return tostring(rep) end
    local parts = {
        "stage=" .. tostring(rep.stage),
        "load=" .. tostring(rep.load_ok),
        "start=" .. tostring(rep.start_ok),
        "song=" .. tostring(rep.songName),
        "audio=" .. tostring(rep.audioFile or (rep.subs and rep.subs.audio) or "?"),
        "auto=" .. tostring((rep.subs and rep.subs.autoplay) or "?"),
        "skin=" .. tostring((rep.subs and rep.subs.skin) or "default"),
        "svflat=" .. tostring((rep.subs and rep.subs["sv-flat"]) or "?"),
        "judge=" .. tostring((rep.subs and rep.subs["judgeswap"]) or "?"),
        "clip=" .. tostring((rep.subs and rep.subs["clip"]) or "?"),
    }
    if rep.pools_after_load then
        parts[#parts + 1] = "Unspawned=" .. tostring(rep.pools_after_load.UnspawnedNotes)
        parts[#parts + 1] = "Strums=" .. tostring(rep.pools_after_load.Strums)
    end
    if rep.note0 then
        parts[#parts + 1] = string.format("note0=%s/%s@%s",
            tostring(rep.note0.side), tostring(rep.note0.column),
            tostring(rep.note0.strumTime))
    end
    if rep.load_err then parts[#parts + 1] = "load_err=" .. tostring(rep.load_err):sub(1, 80) end
    if rep.start_err then parts[#parts + 1] = "start_err=" .. tostring(rep.start_err):sub(1, 80) end
    if rep.aborted then parts[#parts + 1] = "aborted=" .. tostring(rep.aborted) end
    return table.concat(parts, " | ")
end

----------------------------------------------------------------
-- 7. Rayfield UI
----------------------------------------------------------------
local Rayfield = nil
local infoLabel, statusLabel, audioLabel, skinLabel = nil, nil, nil, nil
local songDropdown, audioDropdown, skinDropdown = nil, nil, nil
local songByLabel = {}
local audioByLabel = {}
local skinByLabel = {}

local function refreshSongList()
    local names, labels = {}, {}
    songByLabel = {}
    for _, path in ipairs(listChartFiles()) do
        local label = basename(path)
        local base, dup = label, 2
        while songByLabel[label] do
            label = ("%s (%d)"):format(base, dup)
            dup += 1
        end
        songByLabel[label] = path
        table.insert(labels, label)
    end
    table.sort(labels)
    if #labels == 0 then labels = { "(no charts — drop .chart.json into " .. CHARTS_DIR .. ")" } end
    return labels
end

local function refreshAudioList()
    local labels = { "(no audio — audio-free)" }
    audioByLabel = {}
    for _, path in ipairs(listAudioFiles()) do
        local label = basename(path)
        audioByLabel[label] = path
        table.insert(labels, label)
    end
    return labels
end

local function skinDisplayName(packDir, manifest)
    if type(manifest) == "table" and type(manifest.name) == "string"
        and manifest.name ~= "" then
        return manifest.name
    end
    return basename(packDir)
end

local function refreshSkinList()
    local labels = { "(default skin)" }
    skinByLabel = {}
    for _, packDir in ipairs(listSkinPacks()) do
        local dirName = basename(packDir)
        local manifest = readSkinManifest(packDir)
        local label = skinDisplayName(packDir, manifest)
        local base, dup = label, 2
        while skinByLabel[label] do
            label = ("%s (%d)"):format(base, dup)
            dup += 1
        end
        skinByLabel[label] = dirName
        table.insert(labels, label)
    end
    table.sort(labels)
    return labels
end

local function skinLabelText()
    if selectedSkinDir == nil then return "Skin: default game skin" end
    return "Skin: " .. skinDisplayName(selectedSkinDir, selectedSkinManifest)
end

local function selectSkin(label)
    if label == "(default skin)" then
        selectSkinDir(nil)
    elseif skinByLabel[label] then
        local ok, err = selectSkinDir(skinByLabel[label])
        if not ok then
            notify("Skin error", tostring(err), true)
            return
        end
    else
        return -- placeholder row
    end
    -- NOTE: never call skinDropdown:Set here; Rayfield's Set fires this
    -- callback, which would recurse until stack overflow.
    if skinLabel then
        pcall(function() skinLabel:Set(skinLabelText()) end)
    end
end

local function selectChart(label)
    local path = songByLabel[label]
    if not path then return end -- placeholder row
    local chart, err = readChart(path)
    if not chart then
        notify("Chart error", tostring(err), true)
        if infoLabel then pcall(function() infoLabel:Set("Error: " .. tostring(err)) end) end
        return
    end
    currentChart, currentChartPath = chart, path
    currentInfo = chartInfo(chart, path)
    if infoLabel then pcall(function() infoLabel:Set(currentInfo) end) end
    local picked = automatchAudio(chart, path)
    if audioLabel then
        pcall(function()
            audioLabel:Set("Audio: " .. tostring(picked and basename(picked) or "none (audio-free)"))
        end)
    end
    if audioDropdown and picked then
        pcall(function() audioDropdown:Set(basename(picked)) end)
    elseif audioDropdown then
        pcall(function() audioDropdown:Set("(no audio — audio-free)") end)
    end
    notify("Chart loaded", basename(path))
end

local function doPlay()
    if game.PlaceId ~= EXP_PLACE then
        notify("Wrong place", "Need Project Afternight.", true)
        return
    end
    if playing then
        notify("Already playing", "Press Stop before loading another chart.")
        return
    end
    if type(currentChart) ~= "table" then
        notify("No chart", "Pick a chart first.", true)
        return
    end
    notify("Loading", tostring(currentChart.song.song))
    local rep = playChart()
    notify("Play: " .. tostring(rep.stage), summarizeReport(rep),
        not (rep.start_ok and (rep.stage == "playing" or rep.stage == "ended-results")))
    if rep and rep.stage == "playing" then
        -- Finish poller (read-only): announce the results screen.
        task.spawn(function()
            while _G.AFNRayGen == MYGEN and playing do
                task.wait(1)
                local lr = lastReport
                if type(lr) ~= "table" or not playing then break end
                if lr.stage == "ended-results" then
                    notify("Finished", "Results on screen — press Stop when done.")
                    break
                elseif lr.stage == "ended-fallback-stop" then
                    notify("Finished", "Song ended.")
                    break
                end
            end
        end)
        -- Judge-swap loop: skin judgement/combo art onto spawned popups.
        -- No teardown: popups are engine-owned and die on their own.
        if ctx ~= nil and ctx.judgeSwap ~= nil then
            local c0 = ctx
            task.spawn(function()
                -- Every frame (not throttled): popups spawn showing the
                -- engine strip-slice until first sight, so the swap delay
                -- is the visible wrong-art flash. Marker skip + node/swap
                -- caps keep the per-frame cost trivial.
                while _G.AFNRayGen == MYGEN and playing and ctx == c0 do
                    local okP, errP = pcall(pollJudgeSwap, c0.judgeSwap)
                    if not okP and not c0.judgeErrShown then
                        c0.judgeErrShown = true
                        notify("Judge swap error", tostring(errP):sub(1, 160), true)
                    end
                    if (c0.judgeSwap.swapped or 0) > 0 and not c0.judgeAnnounced then
                        c0.judgeAnnounced = true
                        notify("Skin art", "Judgement/combo art applied ("
                            .. tostring(c0.judgeSwap.swapped) .. " so far).")
                    end
                    task.wait()
                end
                if lastReport == rep and type(rep.subs) == "table" then
                    rep.subs["judgeswap"] = tostring(c0.judgeSwap.swapped or 0) .. " swaps"
                end
                local total = c0.judgeSwap.swapped or 0
                if total > 0 then
                    notify("Skin art", tostring(total) .. " judgement/combo popups reskinned.")
                else
                    notify("Skin art", "No popups matched (scan sees "
                        .. tostring(c0.judgeSwap.scanned or 0) .. " nodes) — art not applied.",
                        true)
                end
            end)
        end
    end
end

local function doStop()
    if not playing then
        notify("Idle", "Nothing to stop.")
        return
    end
    local rep = stopChart()
    notify("Stop: " .. tostring(rep.stage), summarizeReport(rep),
        not (rep.ok and rep.stage == "stopped"))
end

local function buildUI()
    -- Single allowed remote fetch: the Rayfield UI library.
    Rayfield = loadstring(game:HttpGet(RAYFIELD_URL))()

    uiNotify = function(title, body, isError)
        Rayfield:Notify({ Title = title, Content = body, Duration = isError and 9 or 4 })
    end

    local Window = Rayfield:CreateWindow({
        Name = "AfternightCustomSongs v" .. VERSION,
        LoadingTitle = "AfternightCustomSongs",
        LoadingSubtitle = "local custom charts for Project Afternight",
        ConfigurationSaving = { Enabled = false },
        Discord = { Enabled = false },
        KeySystem = false,
    })

    local Tab = Window:CreateTab("Charts", 4483362458)
    local TabOpt = Window:CreateTab("Options", 4483362458)
    local TabMisc = Window:CreateTab("Misc", 4483362458)

    Tab:CreateSection("Chart Library")

    songDropdown = Tab:CreateDropdown({
        Name = "Chart",
        Options = refreshSongList(),
        CurrentOption = nil,
        MultiSelection = false,
        Callback = function(option)
            if _G.AFNRayGen ~= MYGEN then return end
            local label = type(option) == "table" and option[1] or option
            selectChart(label)
        end,
    })

    Tab:CreateButton({
        Name = "Refresh chart list",
        Callback = function()
            if _G.AFNRayGen ~= MYGEN then return end
            local opts = refreshSongList()
            pcall(function() songDropdown:Refresh(opts) end)
            local aopts = refreshAudioList()
            if audioDropdown then pcall(function() audioDropdown:Refresh(aopts) end) end
            local sopts = refreshSkinList()
            if skinDropdown then pcall(function() skinDropdown:Refresh(sopts) end) end
            notify("Refreshed", #opts .. " row(s) in " .. CHARTS_DIR)
        end,
    })

    infoLabel = Tab:CreateLabel("No chart loaded — pick one above")

    Tab:CreateSection("Audio")

    audioDropdown = Tab:CreateDropdown({
        Name = "Audio",
        Options = refreshAudioList(),
        CurrentOption = "(no audio — audio-free)",
        MultiSelection = false,
        Callback = function(option)
            if _G.AFNRayGen ~= MYGEN then return end
            local label = type(option) == "table" and option[1] or option
            if label == "(no audio — audio-free)" then
                selectedAudioPath = nil
            elseif audioByLabel[label] then
                selectedAudioPath = audioByLabel[label]
            end
            if audioLabel then
                pcall(function()
                    audioLabel:Set("Audio: " .. tostring(selectedAudioPath and label or "none (audio-free)"))
                end)
            end
        end,
    })

    audioLabel = Tab:CreateLabel("Audio: none (audio-free)")

    Tab:CreateSection("Skin")

    skinDropdown = Tab:CreateDropdown({
        Name = "Skin",
        Options = refreshSkinList(),
        CurrentOption = "(default skin)",
        MultiSelection = false,
        Callback = function(option)
            if _G.AFNRayGen ~= MYGEN then return end
            local label = type(option) == "table" and option[1] or option
            selectSkin(label)
        end,
    })

    skinLabel = Tab:CreateLabel("Skin: default game skin")

    -- Restore the persisted skin pick (if its pack is still on disk).
    do
        local saved = settings.skin
        if type(saved) == "string" and saved ~= "" then
            local ok, err = selectSkinDir(saved)
            if ok then
                local label = skinDisplayName(saved, selectedSkinManifest)
                pcall(function()
                    if skinByLabel[label] == saved then
                        skinDropdown:Set(label)
                    end
                    skinLabel:Set(skinLabelText())
                end)
            else
                settings.skin = nil
                saveSettings()
            end
        end
    end

    Tab:CreateSection("Playback")

    Tab:CreateToggle({
        Name = "Autoplay (botplay test)",
        CurrentValue = settings.autoplay or false,
        Callback = function(value)
            settings.autoplay = value and true or false
            saveSettings()
        end,
    })

    Tab:CreateToggle({
        Name = "Ignore SV (constant scroll)",
        CurrentValue = settings.ignoreSV or false,
        Callback = function(value)
            settings.ignoreSV = value and true or false
            saveSettings()
        end,
    })

    Tab:CreateButton({
        Name = "Play chart",
        Callback = function()
            local ok, err = pcall(doPlay)
            if not ok then notify("Play error", tostring(err), true) end
        end,
    })
    Tab:CreateButton({
        Name = "Stop",
        Callback = function()
            local ok, err = pcall(doStop)
            if not ok then notify("Stop error", tostring(err), true) end
        end,
    })

    statusLabel = Tab:CreateLabel("Idle")
    playStatusCallback = function(text)
        pcall(function() statusLabel:Set(text) end)
    end

    TabOpt:CreateSection("Calibration")
    TabOpt:CreateSlider({
        Name = "Audio offset (ms, + = notes later)",
        Range = { -500, 500 },
        Increment = 5,
        Suffix = "ms",
        CurrentValue = settings.offsetMs or 0,
        Callback = function(value)
            settings.offsetMs = value
            saveSettings()
        end,
    })

    TabOpt:CreateSection("Background")
    TabOpt:CreateToggle({
        Name = "Enable background",
        CurrentValue = settings.bgEnabled or false,
        Callback = function(value)
            settings.bgEnabled = value
            saveSettings()
            if not value then destroyUnderframe() end
        end,
    })
    TabOpt:CreateSlider({
        Name = "Background dim (%)",
        Range = { 0, 100 },
        Increment = 5,
        Suffix = "%",
        CurrentValue = math.clamp((settings.bgTransparency or 0) * 100, 0, 100),
        Callback = function(value)
            settings.bgTransparency = value / 100
            saveSettings()
        end,
    })
    TabOpt:CreateColorPicker({
        Name = "Background color",
        Color = Color3.fromRGB(
            (settings.bgColor or { 0, 0, 0 })[1] or 0,
            (settings.bgColor or { 0, 0, 0 })[2] or 0,
            (settings.bgColor or { 0, 0, 0 })[3] or 0),
        Callback = function(color)
            settings.bgColor = {
                math.floor(color.R * 255),
                math.floor(color.G * 255),
                math.floor(color.B * 255),
            }
            saveSettings()
        end,
    })

    TabOpt:CreateSection("Info")
    TabOpt:CreateLabel("Charts: " .. CHARTS_DIR)
    TabOpt:CreateLabel("Audio: " .. AUDIO_DIR)
    TabOpt:CreateLabel("Skins: " .. SKINS_DIR)
    TabOpt:CreateLabel("Convert osu!mania with converters/osu_to_afn.py")
    TabOpt:CreateLabel("Convert osu! skins with converters/skins2afn.py")

    TabMisc:CreateSection("Session")
    TabMisc:CreateButton({
        Name = "Copy last report",
        Callback = function()
            local ok, err = pcall(function()
                if type(setclipboard) == "function" then
                    setclipboard(summarizeReport(lastReport))
                end
            end)
            notify("Report", ok and "Copied to clipboard" or ("Copy failed: " .. tostring(err)), not ok)
        end,
    })
    TabMisc:CreateLabel("AfternightCustomSongs v" .. VERSION .. " (Rayfield)")
    TabMisc:CreateLabel("FunkyChart-style flow, Gakuran-style UI, AFN engine")
end

_G.AFNRayCleanup = function()
    if playing then pcall(stopChart) end
    uiNotify = nil
    playStatusCallback = nil
    if Rayfield and type(Rayfield.Destroy) == "function" then
        pcall(function() Rayfield:Destroy() end)
    end
    Rayfield = nil
    pcall(sweepRayfield)
    pcall(destroyUnderframe)
end

----------------------------------------------------------------
-- 8. Boot
----------------------------------------------------------------
print("[AFNRay] boot gen=" .. tostring(MYGEN) .. " v" .. VERSION)
if game.PlaceId ~= EXP_PLACE then
    warn("[AFNRay] PlaceId " .. tostring(game.PlaceId) .. " != " .. EXP_PLACE)
end

local uiOk, uiErr = xpcall(buildUI, debug.traceback)
if not uiOk then
    warn("[AFNRay] UI failed: " .. tostring(uiErr))
    pcall(sweepRayfield)
    return
end
notify("AfternightCustomSongs v" .. VERSION, "Pick a chart, then Play.")
