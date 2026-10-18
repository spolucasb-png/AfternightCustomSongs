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
local VERSION = "2.2.1"
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
local SVFN_LINE = 3250 -- chunk-global getSVFromTime (spawn-path SV reader)
-- Teleport tamer: engine spawns notes spawnTime/|SV| early, so entries with
-- |multiplier| above TAME_THRESHOLD (dariacore teleport blips at x4.4M)
-- give zero approach (notes pop in at the receptor). Clamping them to
-- +-TAME_CAP on the play copy restores sane spawn leads while net-zero
-- away/back pairs agree again downstream (halloween max x1.5 and legit
-- fast SVs under x10 are never touched).
local TAME_THRESHOLD = 10
local TAME_CAP = 3
-- HOOK_CAP is the spawn-hook clamp (x1 = full base-speed approach for blip
-- notes; motion is untouched so no compromise is needed, unlike TAME_CAP).
local HOOK_CAP = 1.0
-- Spawn-window solver (session 25): for sane-SV charts the hook SOLVES the
-- real window instead of clamping — walk the SV table backwards until the
-- engine's signed distance budget is used up — so every saw-tooth/stutter
-- window spawns notes exactly on the spawn line. Flingy charts (|SV|>10,
-- teleport blips) keep the clamp, whose fixed-time window is the proven
-- ballin'/bozo behaviour.
local SOLVER_BUDGET = 1750 -- engine units = noteSpawnTime 1.75 s * 1000
local SOLVER_MAXW = 12000 -- ms walk cap; deeper windows fall back to clamp

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
    tameSV = true, -- auto-clamp teleport SVs (|M|>10 -> +-x3) on the play copy
    favorites = {}, -- in-menu star per chart file name (local only)
    sortMode = "az", -- song list order: "az" | "recent" | "favs" (both UIs)
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
    -- A hand-edited / stale Settings.json must never break the sort.
    if settings.sortMode ~= "az" and settings.sortMode ~= "recent" and settings.sortMode ~= "favs" then
        settings.sortMode = "az"
    end
end
loadSettings()

----------------------------------------------------------------
-- 1.5 Local play stats (Recent + per-chart best/last). Own file
-- (Stats.json in the workspace) - the game's saved data is never
-- touched. Stems are chart file names, same keys as favourites.
----------------------------------------------------------------
local STATS_FILE = FOLDER .. "/Stats.json"
local STATS_MAX_RECENT = 80
local stats = { recent = {}, charts = {} }

local function saveStats()
    pcall(fn.writefile, STATS_FILE, HttpService:JSONEncode(stats))
end

local function loadStats()
    if not fn.isfile(STATS_FILE) then return end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(fn.readfile(STATS_FILE))
    end)
    if not ok or type(data) ~= "table" then return end
    if type(data.recent) == "table" then
        for _, v in ipairs(data.recent) do
            if type(v) == "string" and #stats.recent < STATS_MAX_RECENT then
                stats.recent[#stats.recent + 1] = v
            end
        end
    end
    if type(data.charts) == "table" then
        for k, v in pairs(data.charts) do
            if type(k) == "string" and type(v) == "table" then
                stats.charts[k] = {
                    n = tonumber(v.n) or 0,
                    f = tonumber(v.f) or 0,
                    lastAt = tonumber(v.lastAt),
                    lastAcc = tonumber(v.lastAcc),
                    lastScore = tonumber(v.lastScore),
                    bestAcc = tonumber(v.bestAcc),
                    bestScore = tonumber(v.bestScore),
                    bestCombo = tonumber(v.bestCombo),
                    bestCleared = v.bestCleared == true,
                }
            end
        end
    end
end
loadStats()

-- A play started: move the stem to the front of the recent list (capped)
-- and count the start. Survives quits, so quits still show in Recent.
local function noteRecent(stem)
    if type(stem) ~= "string" or stem == "" then return end
    for i = #stats.recent, 1, -1 do
        if stats.recent[i] == stem then table.remove(stats.recent, i) end
    end
    table.insert(stats.recent, 1, stem)
    while #stats.recent > STATS_MAX_RECENT do table.remove(stats.recent) end
    local rec = stats.charts[stem]
    if type(rec) ~= "table" then
        rec = {}
        stats.charts[stem] = rec
    end
    rec.n = (tonumber(rec.n) or 0) + 1
    saveStats()
end

-- A play finished: fold the engine's results fields (captured from the
-- results table by the create-wrap below) into the per-chart record.
-- Missing fields are tolerated; returns "new best" or "recorded".
local function recordResult(stem, res)
    if type(stem) ~= "string" or type(res) ~= "table" then return nil end
    local rec = stats.charts[stem]
    if type(rec) ~= "table" then
        rec = {}
        stats.charts[stem] = rec
    end
    rec.f = (tonumber(rec.f) or 0) + 1
    rec.lastAt = os.time()
    local acc, score = tonumber(res.accuracy), tonumber(res.score)
    if acc ~= nil then rec.lastAcc = acc end
    if score ~= nil then rec.lastScore = score end
    local best = false
    if acc ~= nil and (rec.bestAcc == nil or acc > rec.bestAcc) then
        rec.bestAcc, rec.bestScore = acc, score
        rec.bestCombo = tonumber(res.topCombo)
        rec.bestCleared = res.cleared == true
        best = true
    end
    saveStats()
    return best and "new best" or "recorded"
end

-- Wrap the engine's Results.create for the duration of our play: it is
-- called with the freshly built stats table when endSong raises the local
-- results screen. We capture the simple fields and forward the call
-- untouched. Removed on teardown.
local function installStatsHook(c)
    if type(c) ~= "table" or type(c.t1) ~= "table" then return "no-t1" end
    if c.statsOrig ~= nil then return "already" end
    local res = rawget(c.t1, "Results")
    local orig = type(res) == "table" and rawget(res, "create") or nil
    if type(orig) ~= "function" then return "no-create" end
    local ok = pcall(function()
        rawset(res, "create", function(overlay, st)
            if type(st) == "table" then
                c.lastStats = {
                    score = tonumber(st.score),
                    accuracy = tonumber(st.accuracy),
                    topCombo = tonumber(st.topCombo),
                    cleared = st.cleared == true,
                    keyCount = tonumber(st.keyCount),
                }
            end
            return orig(overlay, st)
        end)
    end)
    if not ok then return "wrap-failed" end
    c.statsOrig = orig
    return "wrapped"
end

local function restoreStatsHook(c)
    if type(c) ~= "table" or c.statsOrig == nil then return "noop" end
    local res = type(c.t1) == "table" and rawget(c.t1, "Results") or nil
    if type(res) == "table" then rawset(res, "create", c.statsOrig) end
    c.statsOrig = nil
    return "restored"
end

-- Thousands separators for scores ("1,234,567").
local function fmtCount(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return out
end

-- Panel lines for a chart's stats record; nil when it has never finished.
local function chartStatsLines(stem)
    local rec = type(stem) == "string" and stats.charts[stem] or nil
    if type(rec) ~= "table" or (tonumber(rec.f) or 0) == 0 then return nil end
    local best = "Best: \u{2014}"
    if rec.bestAcc ~= nil then
        best = "Best: " .. ("%.2f%%"):format(rec.bestAcc)
        if rec.bestScore ~= nil then
            best = best .. " (" .. fmtCount(rec.bestScore) .. ")"
        end
    end
    local last = "Last: \u{2014}"
    if rec.lastAcc ~= nil then
        last = "Last: " .. ("%.2f%%"):format(rec.lastAcc)
    end
    return {
        ("\u{00B7} Plays: %d \u{00B7} Finishes: %d"):format(
            tonumber(rec.n) or 0, tonumber(rec.f) or 0),
        ("\u{00B7} %s \u{00B7} %s"):format(best, last),
    }
end

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

local function findFnByLine(line, tries, wantSrc)
    tries = tonumber(tries) or 3
    local attempts = 0
    for _ = 1, tries do
        attempts += 1
        for _, o in ipairs(getgc(true)) do
            if type(o) == "function" then
                local okS, s = pcall(function() return debug.info(o, "s") end)
                if okS and type(s) == "string" and string.find(s, "PlayerScripts", 1, true)
                    and (wantSrc == nil or string.find(s, wantSrc, 1, true)) then
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

-- Safe error-function for xpcall: debug.traceback is not guaranteed in this
-- environment (a nil errfunc masks the real error as "attempt to call a nil
-- value"), so fall back to plain tostring.
-- MUST stay above atGameIdentity: Lua locals are forward-only, so a
-- definition placed below it leaves the reference inside atGameIdentity bound
-- to the (nil) global and xpcall(f, nil) throws before f ever runs.
local function safeTraceback(err)
    if type(debug) == "table" and type(debug.traceback) == "function" then
        local ok, t = pcall(debug.traceback, tostring(err))
        if ok and type(t) == "string" then return t end
    end
    return tostring(err)
end

----------------------------------------------------------------
-- Teleport spawn hook (EXPLICIT user approval 2026-10-16: "this is THE
-- project"). Scope: local-only, spawn path only, restored on teardown.
-- The engine's checkNoteSpawns gates each note on
--   spawnTime / |getSVFromTime(noteTime)|
-- through the game chunk's chunk-global getSVFromTime (verified live:
-- chunk-global, called by spawn + reverse-destroy + the uncalled getSpeed
-- export; motion uses the getPosFromTime integral over the raw table and
-- never this function). The svFunctions export may hold a wrapped copy, so
-- the hook anchors on the line-located chunk global and only mirrors the
-- export (restored to its prior value). Teleport SVs (|M|>>10) collapse the
-- lead to ~0, so 55-62% of ballin'/bozo notes pop in at the receptor;
-- clamping the RETURN restores approach while motion stays bit-exact.
-- Any install failure falls back to the play-copy tame, never aborts.
----------------------------------------------------------------
local activeTameHook = nil

local function removeTameHook()
    local h = activeTameHook
    activeTameHook = nil
    if type(h) ~= "table" then return "none" end
    local ok, res = pcall(function()
        if type(h.env) == "table" and h.env.getSVFromTime == h.hook then
            h.env.getSVFromTime = h.orig
        end
        if type(h.svf) == "table" and h.svf.getSVFromTime == h.hook then
            h.svf.getSVFromTime = h.svfPrev
        end
        if type(h.env) == "table" and h.env.getSVFromTime == h.orig then
            return "restored"
        end
        return "env-changed-elsewhere"
    end)
    if not ok then return "FAIL:" .. tostring(res):sub(1, 60) end
    return res
end

local function installTameHook(t21, count)
    -- Anchor on the CHUNK-GLOBAL SV reader (source-line located): the
    -- svFunctions export may hold a wrapped copy (modifiers wrap exports;
    -- spawn reads the chunk global), so the export is only a best-effort
    -- mirror, restored to its PRIOR value rather than assumed original.
    -- Small line numbers collide across PlayerScripts modules: scope the
    -- scan to the game Client chunk (a bare scan once grabbed a Chat
    -- module's line 3250 during live verification).
    local gt = findFnByLine(SVFN_LINE, 1, "Client")
    if type(gt) ~= "function" then return nil, "no-sv-reader" end
    if type(getfenv) ~= "function" then return nil, "no-getfenv" end
    local okE, env = pcall(getfenv, gt)
    if not okE or type(env) ~= "table" then return nil, "no-game-env" end
    if env.getSVFromTime ~= gt then return nil, "env-mismatch" end
    if type(debug) ~= "table" or type(debug.getupvalue) ~= "function" then
        return nil, "no-getupvalue"
    end
    local v199 = upval(gt, 2)
    if type(v199) ~= "number" then return nil, "no-v199" end
    if type(upval(gt, 1)) ~= "table" then return nil, "no-sv-table" end
    local box = { v199 = v199, count = count }
    local clampHook = function(t)
        local v = gt(t)
        if type(v) ~= "number" then return v end
        local lim = box.v199 * HOOK_CAP
        if v > lim then return lim end
        if v < -lim then return -lim end
        return v
    end
    local hook, mode = clampHook, "clamp"
    if count <= 0 then
        -- Solver mode: return budget/W so the gate's 1750/|return| window
        -- equals W, the exact time where the note sat 1750 units above the
        -- receptor (signed engine integral over the SV table). The table is
        -- re-read from the function's upvalue on every call (the engine
        -- reassigns it when a chart loads; a captured reference would be
        -- stale). Falls back to the clamp whenever the walk cannot finish.
        hook = function(t)
            if type(t) ~= "number" then return clampHook(t) end
            local okC, res = pcall(function()
                local tbl = upval(gt, 1)
                if type(tbl) ~= "table" or #tbl == 0 then return nil end
                local lo, hi = 0, #tbl
                while lo < hi do
                    local mid = (lo + hi + 1) // 2
                    local e = tbl[mid]
                    local st = type(e) == "table" and tonumber(e.startTime) or nil
                    if st ~= nil and st <= t then
                        lo = mid
                    else
                        hi = mid - 1
                    end
                end
                local idx = lo
                local S, W = 0, 0
                local upper = t
                local guard = 0
                while W < SOLVER_MAXW and guard < 4096 do
                    guard += 1
                    local g, lower = box.v199, nil
                    if idx >= 1 then
                        local e = tbl[idx]
                        local m = type(e) == "table" and tonumber(e.multiplier) or nil
                        g = (m == nil) and box.v199 or (box.v199 * m)
                        lower = tonumber(e.startTime) or upper
                        if lower > upper then lower = upper end
                    end
                    local need = SOLVER_BUDGET - math.abs(S)
                    if need <= 0 then break end
                    if idx < 1 then
                        local gg = math.abs(g)
                        if gg <= 0 then break end
                        W = W + need / gg
                        S = S + g * (need / gg)
                        break
                    end
                    local seg = upper - lower
                    if seg > 0 then
                        local gg = math.abs(g)
                        local span = (gg > 0) and (need / gg) or math.huge
                        if span <= seg then
                            W = W + span
                            S = S + g * span
                            break
                        end
                        S = S + g * seg
                        W = W + seg
                    end
                    upper = lower
                    idx -= 1
                end
                if W < 2 or math.abs(S) < SOLVER_BUDGET - 0.5 then
                    return nil
                end
                local r = SOLVER_BUDGET / W
                if r > SOLVER_BUDGET then r = SOLVER_BUDGET end
                return r
            end)
            if okC and type(res) == "number" then return res end
            return clampHook(t)
        end
        mode = "solver"
    end
    local okW = pcall(function() env.getSVFromTime = hook end)
    if not okW or env.getSVFromTime ~= hook then
        pcall(function()
            if type(env) == "table" and env.getSVFromTime == hook then
                env.getSVFromTime = gt
            end
        end)
        return nil, "env-write-failed"
    end
    local svf, svfPrev = nil, nil
    if type(t21) == "table" then
        local s = rawget(t21, "svFunctions")
        if type(s) == "table" then
            svf = s
            svfPrev = rawget(s, "getSVFromTime")
            pcall(function() s.getSVFromTime = hook end)
        end
    end
    activeTameHook = { env = env, svf = svf, svfPrev = svfPrev,
        orig = gt, hook = hook, box = box, mode = mode }
    return activeTameHook, nil
end

-- No notify()/Rayfield calls between the identity switch and the restore:
-- Rayfield's Notify spawns a thread that inherits identity 2 and throws
-- "cannot access 'Instance' (lacking capability Plugin)".
local function atGameIdentity(idBefore, f)
    local okSet = pcall(function() setthreadidentity(GAME_IDENTITY) end)
    if not okSet then return false, "setthreadidentity failed" end
    -- pcall around xpcall so nothing can escape while elevated: the identity
    -- restore below always runs.
    local okCall, ok, res = pcall(xpcall, f, safeTraceback)
    local okRestore, restoreErr = pcall(function() setthreadidentity(idBefore) end)
    if not okRestore then return false, "thread identity restore failed: " .. tostring(restoreErr) end
    if not okCall then return false, tostring(ok) end
    return ok, res
end

----------------------------------------------------------------
-- 4. Chart library (read + validate, AFN wrapper shape)
----------------------------------------------------------------
local currentChart = nil       -- decoded + validated wrapper table
local currentChartPath = nil
local currentInfo = "No chart loaded"
local currentEntry = nil       -- menu entry of the loaded chart (title / difficulty labels)

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
    -- Wide charts (5K-10K): keyCount/playerKeyCount decide the lane range.
    -- Player rows carry lanes [keyCount, keyCount+playerKeyCount), exactly
    -- the range the engine's createNote maps onto the "R" strumline
    -- (4K charts keep their historical 4..7 rows).
    local kc = tonumber(song.keyCount) or 4
    local pkc = tonumber(song.playerKeyCount) or kc
    if kc < 1 then kc = 4 end
    if pkc < 1 then pkc = kc end
    local laneLo, laneHi = kc, kc + pkc - 1
    local total, holds, dropped = 0, 0, 0
    for _, section in ipairs(song.notes) do
        if type(section) == "table" and type(section.sectionNotes) == "table" then
            local kept = {}
            for _, row in ipairs(section.sectionNotes) do
                if type(row) == "table" and type(row[1]) == "number"
                    and type(row[2]) == "number" and row[1] >= 0
                    and row[2] >= laneLo and row[2] <= laneHi then
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
    if total == 0 then return nil, "All notes invalid (need [timeMs, lane, susMs] rows)" end
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
    data._keyCount = kc
    data._playerKeyCount = pkc
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
    local keysTag = ""
    if (chart._playerKeyCount or 4) ~= 4 then
        keysTag = " | " .. tostring(chart._playerKeyCount) .. "K"
    end
    return ("%s\n%s BPM | %d notes (%d holds) | %d BPM changes | %d SV%s%s%s%s"):format(
        basename(path),
        tostring(chart.song.bpm), chart._noteCount or 0, chart._holdCount or 0,
        bpmN, svN, keysTag, anchorTag, audioHint,
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

-- Song covers (session 26): Covers/<chart-stem>.<png|jpg|jpeg> in the
-- workspace. Shown on the in-menu selected-song icon and as the row
-- background art; every chart file of one song can carry its own copy.
local COVER_DIR = FOLDER .. "/Covers"
local COVER_EXTS = { ".png", ".jpg", ".jpeg" }

local function listCoverFiles()
    local out = {}
    local ok, files = pcall(fn.listfiles, COVER_DIR)
    if ok and type(files) == "table" then
        for _, f in ipairs(files) do
            local lower = tostring(f):lower()
            for _, ext in ipairs(COVER_EXTS) do
                if lower:sub(-#ext) == ext then
                    table.insert(out, f)
                    break
                end
            end
        end
    end
    return out
end

-- Cover for a chart entry: <stem>.<ext> first, else any sibling chart file
-- of the same song group (one art can serve every difficulty).
local function automatchCover(entry)
    if type(entry) ~= "table" or type(entry.path) ~= "string" then return nil end
    local files = listCoverFiles()
    if #files == 0 then return nil end
    local byLower = {}
    for _, p in ipairs(files) do byLower[basename(p):lower()] = p end
    local function tryStem(path)
        local stem = chartStem(basename(path))
        for _, ext in ipairs(COVER_EXTS) do
            local hit = byLower[stem .. ext]
            if hit ~= nil then return hit end
        end
        return nil
    end
    local hit = tryStem(entry.path)
    if hit ~= nil then return hit end
    local g = entry.group
    if type(g) == "table" and type(g.entries) == "table" then
        for _, e in ipairs(g.entries) do
            hit = tryStem(e.path)
            if hit ~= nil then return hit end
        end
    end
    return nil
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
-- One Sparrow dir module for a skin pack (Source = XML string, Image attr =
-- local PNG asset). Returns module, or nil + err.
local function buildSkinDirModule(dirname, xml, uri)
    local mod = Instance.new("ModuleScript")
    mod.Name = dirname
    local okSrc, errSrc = pcall(function()
        mod.Source = "return " .. string.format("%q", xml)
    end)
    if not okSrc then
        pcall(function() mod:Destroy() end)
        return nil, "skin module source failed: " .. tostring(errSrc)
    end
    local okAttr, errAttr = pcall(function()
        mod:SetAttribute("Image", uri)
        mod:SetAttribute("SizeMult", 1)
        mod:SetAttribute("Factor", 1)
    end)
    if not okAttr then
        pcall(function() mod:Destroy() end)
        return nil, "skin module attribute failed: " .. tostring(errAttr)
    end
    return mod
end

-- The game's own Square module (the "Space" art): the wide-lane centre key.
-- 4K skin packs never carry it; the engine's missing-dir fallback would
-- resolve Square to the pack's Up art, but the centre lane deserves its own
-- image (7K binds it to Space). Engine noteskin modules are requireable
-- from the executor (proven live), and the require-wrap serves our copy
-- through the xml map like every pack module. Returns module, xml or nil.
local function stockSquareModule()
    local okG, mod = pcall(function()
        local rs = game:GetService("ReplicatedStorage")
        local ns = rs:FindFirstChild("Assets")
        ns = ns and ns:FindFirstChild("Noteskins")
        local aft = ns and ns:FindFirstChild("Afternight")
        local inner = aft and aft:FindFirstChild("Afternight")
        return inner and inner:FindFirstChild("Square") or nil
    end)
    if not okG or mod == nil or not mod:IsA("ModuleScript") then return nil end
    local okX, xml = pcall(require, mod)
    if not okX or type(xml) ~= "string" or xml == "" then return nil end
    local mine = Instance.new("ModuleScript")
    mine.Name = "Square"
    local okS = pcall(function()
        mine.Source = "return " .. string.format("%q", xml)
    end)
    if not okS then
        pcall(function() mine:Destroy() end)
        return nil
    end
    -- Copy every stock attribute (Image, Color, ...) verbatim.
    local okA, attrs = pcall(function() return mod:GetAttributes() end)
    if okA and type(attrs) == "table" then
        for an, av in pairs(attrs) do
            pcall(function() mine:SetAttribute(an, av) end)
        end
    end
    return mine, xml
end

-- wideKeys (>4) adds the centre Square dir: a pack-provided Square wins,
-- else the stock one is borrowed. Returns folder, xmlByMod, squareNote.
local function buildSkinFolder(packDir, manifest, tag, wideKeys)
    local folder = Instance.new("Folder")
    folder.Name = tag
    local xmlByMod = {}
    local function fail(msg)
        pcall(function() folder:Destroy() end)
        return nil, msg
    end
    for _, dirname in ipairs(SKIN_DIRS) do
        local e = manifest.dirs[dirname]
        local xmlOk, xml = pcall(fn.readfile, tostring(packDir) .. "/" .. e.xml)
        if not xmlOk or type(xml) ~= "string" or xml == "" then
            return fail("skin xml unreadable: " .. dirname)
        end
        local assetOk, uri = pcall(fn.getlocalasset, tostring(packDir) .. "/" .. e.png)
        if not assetOk or type(uri) ~= "string" or uri == "" then
            return fail("skin png asset failed: " .. dirname)
        end
        local mod, err = buildSkinDirModule(dirname, xml, uri)
        if mod == nil then
            return fail(err)
        end
        mod.Parent = folder
        xmlByMod[mod] = xml
    end
    local note = nil
    if (tonumber(wideKeys) or 4) > 4 and folder:FindFirstChild("Square") == nil then
        local e = type(manifest.dirs) == "table" and manifest.dirs.Square or nil
        local made = false
        if type(e) == "table" and type(e.xml) == "string" and type(e.png) == "string" then
            local xmlOk, xml = pcall(fn.readfile, tostring(packDir) .. "/" .. e.xml)
            local assetOk, uri = pcall(fn.getlocalasset, tostring(packDir) .. "/" .. e.png)
            if xmlOk and assetOk and type(xml) == "string" and xml ~= ""
                and type(uri) == "string" and uri ~= "" then
                local mod = buildSkinDirModule("Square", xml, uri)
                if mod ~= nil then
                    mod.Parent = folder
                    xmlByMod[mod] = xml
                    made = true
                    note = "square=pack"
                end
            end
        end
        if not made then
            local mod, xml = stockSquareModule()
            if mod ~= nil then
                mod.Parent = folder
                xmlByMod[mod] = xml
                note = "square=stock"
            else
                note = "square=fallback(Up)"
            end
        end
    end
    return folder, xmlByMod, note
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

-- Song-select / results-screen cleanup helpers. They MUST stay above
-- doTeardown (Lua locals are forward-only). Two top-level locals only; the
-- services and tween info live inside the do-block (Luau 200-local limit).
--
-- Why they exist: our Play never goes through the game's SetSongSelector
-- "Hide" path, so the lobby music (UIMusic), the SettingsBlur 16 and the
-- shown-state of the song-select all survived the start. Likewise our song-end
-- watcher raises the local results screen (ResultsBlur 32) and nothing ever
-- cleared it on Stop.
local leaveSongSelect, clearResultsScreen
do
    local TweenService = game:GetService("TweenService")
    local Lighting = game:GetService("Lighting")
    -- Same timing the game uses for its own SettingsBlur fade.
    local BLUR_FADE = TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut)

    -- The game's song-select object is an upvalue of its SetSongSelector
    -- listen function (same route as the Start listener). The listener itself
    -- is only READ here, never invoked: its Hide branch ends with writes to
    -- the player's saved data, which stays out of a local-only player.
    local function findSongSelectObject(c)
        local nf = type(c) == "table" and c.nf or nil
        local rl = type(nf) == "table" and rawget(nf, "remoteListen") or nil
        local lst = type(rl) == "table" and rl["SetSongSelector"] or nil
        if type(lst) ~= "function" then return nil, "listener missing" end
        for i = 1, 16 do
            local v = upval(lst, i)
            if type(v) == "table" then
                local okH, h = pcall(function() return v.hide end)
                local okD, d = pcall(function() return v.deselectSong end)
                if okH and okD and type(h) == "function" and type(d) == "function" then
                    return v
                end
            end
        end
        return nil, "song-select object not found"
    end

    -- Leave the song-select the way the game's Hide does, minus its saved-data
    -- writes: inSongSelect=false, the object's own hide() (stops the lobby
    -- music, clears its shown-state, hides the frame, releases the cursor
    -- manager) and the SettingsBlur fade to 0. Only runs when the select was
    -- actually up (our menu tab, the frame visible, or the game's own flag),
    -- because SettingsBlur is shared with the Settings menu.
    leaveSongSelect = function(c, fromMenu)
        local ss, why = findSongSelectObject(c)
        local gui = ss ~= nil and ss.gui or nil
        local guiShown = typeof(gui) == "Instance" and gui:IsA("GuiObject") and gui.Visible
        local flagSet = type(c) == "table" and type(c.t7) == "table"
            and rawget(c.t7, "inSongSelect") == true
        if not (fromMenu or guiShown or flagSet) then
            return "skipped(select not shown)"
        end
        local parts = {}
        if type(c.t7) == "table" then
            rawset(c.t7, "inSongSelect", false)
            parts[#parts + 1] = "inSongSelect=false"
        end
        if ss ~= nil then
            local okH, errH = atGameIdentity(c.idBefore, function() ss:hide() end)
            parts[#parts + 1] = okH and "hide=ok" or ("hide=FAIL:" .. tostring(errH))
        else
            parts[#parts + 1] = "hide=skipped(" .. tostring(why) .. ")"
        end
        local blur = Lighting:FindFirstChild("SettingsBlur")
        if blur ~= nil then
            local okB, errB = pcall(function()
                TweenService:Create(blur, BLUR_FADE, { Size = 0 }):Play()
            end)
            parts[#parts + 1] = okB and "blur=fade0" or ("blur=FAIL:" .. tostring(errB))
        else
            parts[#parts + 1] = "blur=absent"
        end
        return table.concat(parts, " ")
    end

    -- Clears the local results screen our own song-end raised, with the
    -- results module's own clearUp (fades ResultsBlur to 0, slides the frame
    -- away, destroys it). The frame is found by name inside the game's Overlay
    -- (full PlayerGui scan as fallback); none found (Continue already pressed)
    -- is a clean no-op, not a failure.
    clearResultsScreen = function(c)
        local pg = player:FindFirstChildOfClass("PlayerGui")
        if pg == nil then return "no PlayerGui" end
        local function isResults(d)
            return d.Name == "ResultsRework" and d:IsA("GuiObject")
                and d:FindFirstChild("Continue") ~= nil
        end
        local frame = nil
        local main = pg:FindFirstChild("Main")
        local overlay = main and main:FindFirstChild("Overlay") or nil
        if overlay ~= nil then
            for _, d in ipairs(overlay:GetChildren()) do
                if isResults(d) then frame = d break end
            end
        end
        if frame == nil then
            for _, d in ipairs(pg:GetDescendants()) do
                if isResults(d) then frame = d break end
            end
        end
        if frame == nil then return "no results frame" end
        local res = type(c.t1) == "table" and rawget(c.t1, "Results") or nil
        local clearUp = type(res) == "table" and rawget(res, "clearUp") or nil
        if type(clearUp) ~= "function" then error("results clearUp unavailable") end
        local ok, err = atGameIdentity(c.idBefore, function() clearUp(frame) end)
        if not ok then error(err) end
        return "cleared"
    end
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
    step("stats-hook", function()
        -- Restore the engine's own Results.create (wrapped during play).
        local note = restoreStatsHook(c)
        if note == "restored" then report.statsHook = note end
    end)
    step("results", function()
        -- Only the results screen our own song-end raised (resultsRaised);
        -- never touches a results screen the game made for something else.
        if c.resultsRaised then
            report.resultsNote = clearResultsScreen(c)
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
    step("sv-hook", function()
        report.tameHookRestore = removeTameHook()
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

-- Labels the game's own HUD prints for a play (Now Playing card, time bar).
-- The engine reads the song name from the Song folder's DisplayName
-- attribute (the folder Name stays the internal id: it keys our registry
-- entry) and the difficulty from the chart module's Name ("Difficulties_<name>"
-- lookup, raw name as fallback). Use what the song-select menu shows for the
-- selected chart (song title + difficulty button label); a chart opened
-- without a menu entry falls back to its own metadata, then to the raw id /
-- "Custom".
local function playLabels(chart, path)
    local song = type(chart) == "table" and type(chart.song) == "table" and chart.song or {}
    local entry = currentEntry
    local title, diff
    if type(entry) == "table" and entry.path == path then
        local group = entry.group
        title = type(group) == "table" and group.display or entry.display
        diff = entry.diffLabel
    end
    if type(title) ~= "string" or title == "" then
        title = type(song.title) == "string" and song.title ~= "" and song.title
            or tostring(song.song)
    end
    if type(diff) ~= "string" or diff == "" then
        diff = type(song.difficulty) == "string" and song.difficulty ~= "" and song.difficulty
            or "Custom"
    end
    return title, diff
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
    -- constant scroll feel regardless of map SVs. The teleport tamer is
    -- hook-first (engine spawn fix, raw chart + exact motion); the copy
    -- clamp below only survives as a fallback when the hook cannot install.
    local chartJson
    local flat, tameNeed, svN = false, 0, 0
    do
        local off = tonumber(settings.offsetMs) or 0
        flat = settings.ignoreSV and true or false
        local songName = tostring(currentChart.song.song)
        if type(currentChart.sliderVelocities) == "table" then
            svN = #currentChart.sliderVelocities
            for _, e in ipairs(currentChart.sliderVelocities) do
                if type(e) == "table" and tonumber(e.multiplier)
                    and math.abs(e.multiplier) > TAME_THRESHOLD then
                    tameNeed += 1
                end
            end
        end
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
                rep.subs["sv-tame"] = "off(flat)"
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
    local playTitle, playDiff = playLabels(currentChart, currentChartPath)
    rep.title, rep.diff = playTitle, playDiff
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
        -- 0. Teleport spawn hook (tame): pre-clear any previous play's hook,
        -- then install when this chart needs it. Hook-first: raw chart plus
        -- spawn-path clamp = exact motion with sane approach. If the hook
        -- cannot install, fall back to clamping the play JSON (motion
        -- compromise, same as --sv-cap); either way the play continues.
        do
            local prevTame = removeTameHook()
            if prevTame ~= "none" then rep.subs["sv-tame-prev"] = prevTame end
            if flat then
                rep.subs["sv-tame"] = rep.subs["sv-tame"] or "off(flat)"
            elseif settings.tameSV ~= false and svN > 0 then
                -- Install whenever the chart HAS an SV map: sane-SV charts
                -- get the window SOLVER (exact spawn-line placement through
                -- stutters, session 25); flingy charts (|SV|>10) get the
                -- base clamp (fixed-time window, the proven ballin'/bozo
                -- behaviour). Motion stays untouched.
                local rec, why = installTameHook(t21, tameNeed)
                if rec then
                    if rec.mode == "solver" then
                        rep.subs["sv-tame"] = "solved(" .. tostring(svN) .. "sv)"
                    else
                        local lim = (type(rec.box) == "table" and tonumber(rec.box.v199) or 1) * HOOK_CAP
                        local clamped = 0
                        for _, e in ipairs(currentChart.sliderVelocities) do
                            local m = type(e) == "table" and tonumber(e.multiplier) or nil
                            if m and math.abs(m) > lim then clamped += 1 end
                        end
                        rep.subs["sv-tame"] = "hooked(" .. tostring(clamped) .. "@x" .. tostring(HOOK_CAP) .. ")"
                    end
                elseif tameNeed > 0 then
                    local okC, cp = pcall(function()
                        return HttpService:JSONDecode(chartJson)
                    end)
                    if okC and type(cp) == "table"
                        and type(cp.sliderVelocities) == "table" then
                        local n = 0
                        for _, e in ipairs(cp.sliderVelocities) do
                            local m = type(e) == "table" and tonumber(e.multiplier) or nil
                            if m and math.abs(m) > TAME_THRESHOLD then
                                e.multiplier = m > 0 and TAME_CAP or -TAME_CAP
                                n += 1
                            end
                        end
                        chartJson = HttpService:JSONEncode(cp)
                        rep.subs["sv-tame"] = "capped(" .. tostring(n) .. "@x"
                            .. tostring(TAME_CAP) .. ")-fallback(hook:" .. tostring(why) .. ")"
                    else
                        rep.subs["sv-tame"] = "fallback-failed(hook:" .. tostring(why) .. ")"
                    end
                else
                    rep.subs["sv-tame"] = "raw(hook:" .. tostring(why) .. ")"
                end
            elseif settings.tameSV ~= false then
                rep.subs["sv-tame"] = "clean"
            else
                rep.subs["sv-tame"] = "off(setting)"
            end
        end
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
            local okF, errF = pcall(function()
                rawget(env, "enterLoadingState")({
                    Sides = { L = {}, R = {} },
                    PlayerAmmo = { L = 0, R = 0 },
                    IsSolo = false,
                    Mod = MOD_NAME,
                    Song = playTitle,
                    Difficulty = playDiff,
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
        chartMod.Name = playDiff -- HUD prints this as the difficulty
        chartMod.Parent = holder
        -- ModuleScript.Source caps at 200000 chars (probed live 2026-10-16);
        -- SV-dense charts (halloween 637KB, bozo 432KB) exceed it. Split the
        -- raw JSON into ~100KB pieces (byte splits are safe: each piece is
        -- independently %q-encoded/decoded, so concatenation round-trips
        -- exactly) with a tiny reassembly shim as the main Source. The
        -- require-wrap below still short-circuits require(chartMod) by
        -- identity, so this path only serves validation + engine fallback.
        local SRC_CAP = 200000
        local RAW_CHUNK = 100000
        local okSrc, errSrc = pcall(function()
            local mainSrc = "return " .. string.format("%q", chartJson)
            if #mainSrc < SRC_CAP then
                chartMod.Source = mainSrc
                rep.synth_chunks = "single"
            else
                local parts, i, n = {}, 1, #chartJson
                while i <= n do
                    parts[#parts + 1] = chartJson:sub(i, math.min(i + RAW_CHUNK - 1, n))
                    i += RAW_CHUNK
                end
                local shim = {}
                for idx, raw in ipairs(parts) do
                    local cm = Instance.new("ModuleScript")
                    cm.Name = "Chunk" .. idx
                    local csrc = "return " .. string.format("%q", raw)
                    if #csrc >= SRC_CAP then
                        error("chunk " .. idx .. " still exceeds Source cap")
                    end
                    cm.Source = csrc
                    cm.Parent = chartMod
                    shim[#shim + 1] = 'require(script.Chunk' .. idx .. ')'
                end
                local joined = "return " .. table.concat(shim, "..")
                if #joined >= SRC_CAP then
                    error("shim exceeds Source cap (" .. #parts .. " chunks)")
                end
                chartMod.Source = joined
                rep.synth_chunks = "chunked:" .. #parts
            end
        end)
        rep.synth_sourceWrite = okSrc and "ok" or ("FAIL:" .. tostring(errSrc))
        if not okSrc then
            return abortPlay(rep, "synth-failed")
        end
        pcall(function() chartMod:SetAttribute("_CachedAudio", CACHED_AUDIO) end)

        local songInst = Instance.new("Folder")
        songInst.Name = rep.songName
        songInst:SetAttribute("DisplayName", playTitle) -- HUD song name
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
        -- Refresh the tame hook's v199: the engine recomputes it per load.
        do
            local h = activeTameHook
            if h ~= nil and type(debug) == "table"
                and type(debug.getupvalue) == "function" then
                local ok, a, b = pcall(debug.getupvalue, h.orig, 2)
                if ok then
                    local v = (type(a) == "string") and b or a
                    if type(v) == "number" then
                        h.box.v199 = v
                        rep.subs["sv-tame-v199"] = tostring(v)
                    end
                end
            end
        end

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
        -- play re-resolves the game skin from settings). Wide charts (5K+)
        -- extend the folder with the centre Square dir (the engine's strip
        -- fallback covers Left2/Right2/Down2/Up2 from the pack dirs).
        local wideKeys = tonumber(currentChart.song.playerKeyCount) or 4
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
            local folder, xmlByMod, squareNote = buildSkinFolder(packDir, manifest,
                "AFNRaySkin_" .. tostring(MYGEN) .. "_" .. tostring(playSeq), wideKeys)
            if not folder then
                rep.skin_err = tostring(xmlByMod)
                return abortPlay(rep, "skin-build-failed")
            end
            if squareNote ~= nil then rep.subs["skin-square"] = squareNote end
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
            rep.subs["skin"] = okK and ("custom:" .. c.skinName
                .. (wideKeys > 4 and ("(wide:" .. wideKeys .. "K)") or ""))
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
        -- Local stats: remember the play (Recent + start count) and wrap
        -- the engine's Results.create so the song-end results table is
        -- captured into Stats.json. Both local-only, both best-effort.
        c.statsKey = type(currentChartPath) == "string" and basename(currentChartPath) or nil
        if c.statsKey ~= nil then pcall(noteRecent, c.statsKey) end
        rep.statsHook = installStatsHook(c)

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
                            -- Our own endSong raised the local results screen;
                            -- teardown's "results" step clears it on Stop.
                            c.resultsRaised = true
                            -- Fold the captured results (if create ran) into
                            -- the local stats record.
                            if c.statsKey ~= nil then
                                rep.stats = recordResult(c.statsKey, c.lastStats)
                            end
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
    end, safeTraceback)

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
-- art with the skin's local URIs. Identification is exact, never fuzzy:
-- FNF_Rating popups attribute via the asset-id map; FNF_Combo digit labels
-- read their digit from ImageRectOffset.X/100 (combo text is pure digits).
-- FNF_Offset popups are skipped (symbol slots are indistinguishable from
-- digit 0).
--
-- The marker is a LATCH, deliberately: popup labels are destroyed per spawn
-- (releaseChildrenToPool + t_1 destroy), so first sight carries birth truth
-- and nothing is ever reused. Re-deriving later is WRONG: after we zero the
-- offset for our art, a revisit reads our own zero as digit 0 and clobbers
-- every nonzero digit within a tick (all-zeros session-15 bug). Contents and
-- idmap are fixed for the play, so a later visit decides identically anyway.
-- Swap one popup label's art. Returns true on a swap. Latch-once semantics
-- (see above): never re-derive from our own zeroed offset.
local function swapJudgeLabel(js, d)
    if type(js) ~= "table" then return false end
    if not (typeof(d) == "Instance" and d:IsA("ImageLabel")) then return false end
    local okM, marked = pcall(function() return d:GetAttribute("_AFNSwapped") end)
    if okM and marked then return false end
    local swapped = false
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
                if okS then swapped = true end
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
                if okS then swapped = true end
            end
        end
    end
    -- Latch unconditionally (even on miss: contents/idmap are fixed for
    -- the play, and FNF_Offset is never swappable).
    pcall(function() d:SetAttribute("_AFNSwapped", true) end)
    if swapped then js.swapped += 1 end
    return swapped
end

-- One sweep over the scan root (initial pass at connect time). The live
-- path is event-driven (DescendantAdded below), so this runs rarely.
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
        if swapJudgeLabel(js, d) then n += 1 end
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
        "tame=" .. tostring((rep.subs and rep.subs["sv-tame"]) or "?"),
        "judge=" .. tostring((rep.subs and rep.subs["judgeswap"]) or "?"),
        "clip=" .. tostring((rep.subs and rep.subs["clip"]) or "?"),
        "synth_chunks=" .. tostring(rep.synth_chunks or "?"),
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
-- 6.5. In-menu custom tab (native-styled launcher overlay inside SongSelect)
--
-- Design (HANDOFF session 17): the vote flow is server-mediated and stays
-- untouched. The tab is a pure-client launcher living in SEPARATE static
-- containers: own list + own info panels + own Play button calling
-- playChart(). It never reads/writes votes, never fires remotes, never
-- touches game data. Gates: menu present, solo/empty server (#Players==1,
-- re-checked at Play), engine-idle via the existing playChart preflight.
--
-- Look (HANDOFF session 18): every visible piece is a Clone() of the game's
-- own template - SongTemplate rows, the SongSearch bar, StatsPanel.Play
-- buttons, SongInfo panels - so fonts, colours, corners, strokes and the row
-- hover look come from the game itself. Clones carry no engine connections;
-- scripts inside clones are destroyed. Row clicks hook the row button itself
-- (the game's own click target), NOT the template's Cover, which lives
-- inside the hidden UnavailableDisplay and can never be hit.
--
-- Polish (HANDOFF session 19):
--   * Mod list: a pinned "Custom Charts" row (clone of the game's mod row)
--     sits above the native list; the native scroller is shrunk by exactly
--     that row (attribute AFNShrunk remembers it so any sweep can undo it).
--     Pressing any native mod / tab row closes our tab again.
--   * Song list: a section-header row (clone of WeekTemplate) and the
--     native favourite star on every row (local favourites, Settings.json).
--   * Info column: the SongInfo list layout stretches its visible children
--     to fill the column (free space split equally), so cloning only two
--     panels made them 2-3x too tall. We now clone all four native panels
--     (SelectedSong, Credits, SongStats, Difficulties) at their own sizes
--     and hide the native "Select a song first!" frame while open.
--   * Difficulties: one native-style button per chart. Pressing it plays a
--     local audio PREVIEW of the chart's song (never the chart itself); the
--     native menu music is ducked while it plays.
----------------------------------------------------------------
local doPlayFn -- forward; playChart/doPlay are defined later in the file.
-- Lua locals scope forward-only: referencing doPlay directly from this
-- section binds the (nil) global. Assigned right after doPlay's definition.
local toggleMenuTab -- forward; assigned after openMenuTab

local menuTab = nil -- live tab state while open, else nil
local menuToggleBtn = nil -- the always-present in-menu "Custom Charts" button
local modRowBtn = nil -- the pinned "Custom Charts" row in the game's mod list
local menuWatcherOn = false
local menuPreview = nil -- { snd, duck } while a difficulty preview plays

local MOD_ROW_H = 50 -- native mod row height (px)
local MOD_ROW_GAP = 6 -- native row spacing (px)
local PREVIEW_VOLUME = 0.5
local FAV_GOLD = Color3.fromRGB(255, 193, 8)
local MOD_ACCENT = Color3.fromRGB(60, 190, 175)
local DIFF_LABEL = "Custom"
local DIFF_BTN_H = 66 -- difficulty-button slot height incl. gap (59 px + 7 gap)
local NOTE_GLYPH = "\u{266A}"

-- Everything we ever parent into the game's menu carries one of these names,
-- so a re-exec (or a crashed earlier build) can always sweep its leftovers.
-- (AFNCredits is a label the GAME owns inside its Credits panel - our clone
-- of that panel is therefore named AFNCreds, and AFNCredits is never swept.)
local MENU_PIECES = {
    AFNCustomTab = true, AFNModRow = true, AFNToggle = true, AFNPlay = true,
    AFNSelected = true, AFNCreds = true, AFNStats = true, AFNDiffs = true,
    AFNPreview = true,
}

local function menuPlayerCount()
    local ok, n = pcall(function() return #Players:GetPlayers() end)
    return ok and n or 99
end

local function menuRoot()
    local pg = player:FindFirstChildOfClass("PlayerGui")
    local main = pg and pg:FindFirstChild("Main") or nil
    return main and main:FindFirstChild("SongSelect") or nil
end

-- Locates the native pieces we clone. Any member may be nil; callers check
-- exactly what they need.
local function menuParts()
    local ss = menuRoot()
    if ss == nil then return nil end
    local inner = ss:FindFirstChild("Main")
    local upper = (inner and inner:FindFirstChild("UpperPanel"))
        or ss:FindFirstChild("UpperPanel", true)
    local songs = upper and upper:FindFirstChild("Songs") or nil
    local frame = songs and (songs:FindFirstChild("ScrollingFrame")
        or songs:FindFirstChild("ScrollingFrame", true)) or nil
    local mods = upper and upper:FindFirstChild("Mods") or nil
    local modScroll = mods and mods:FindFirstChild("ScrollingFrame") or nil
    local modTmpl = nil
    if modScroll ~= nil then
        -- The game keeps pooled mod rows named "Template" (hidden ones are
        -- fine to clone: we overwrite every visible field).
        for _, c in ipairs(modScroll:GetChildren()) do
            if c.Name == "Template" and c:IsA("TextButton")
                and c:FindFirstChild("ModName") and c:FindFirstChild("BG") then
                modTmpl = c
                break
            end
        end
    end
    local info = upper and upper:FindFirstChild("SongInfo") or nil
    local diffs = info and info:FindFirstChild("Difficulties") or nil
    return {
        root = ss, inner = inner, upper = upper, songs = songs, frame = frame,
        tmpl = songs and songs:FindFirstChild("SongTemplate", true) or nil,
        weekTmpl = frame and frame:FindFirstChild("WeekTemplate") or nil,
        search = songs and songs:FindFirstChild("SongSearch") or nil,
        stats = inner and inner:FindFirstChild("StatsPanel") or nil,
        info = info, mods = mods, modScroll = modScroll, modTmpl = modTmpl,
        diffList = diffs and diffs:FindFirstChild("DifficultyList") or nil,
    }
end

-- Undoes the native-mod-list shrink (the attribute survives re-execs, so a
-- fresh build can always put the game's layout back).
local function restoreModScroller(found)
    local sf = found and found.modScroll or nil
    if sf == nil then return end
    pcall(function()
        local cur = sf:GetAttribute("AFNShrunk")
        if type(cur) == "number" then
            local s = sf.Size
            if s.Y.Offset <= -cur + 0.5 then
                sf.Size = UDim2.new(s.X.Scale, s.X.Offset, s.Y.Scale, s.Y.Offset + cur)
            end
        end
        sf:SetAttribute("AFNShrunk", nil)
    end)
end

local function sweepMenuPieces(keepToggle)
    local ss = menuRoot()
    if ss == nil then return end
    local strayTab = false
    for _, d in ipairs(ss:GetDescendants()) do
        if MENU_PIECES[d.Name]
            and not (keepToggle and (d == menuToggleBtn or d == modRowBtn)) then
            if d.Name == "AFNCustomTab" then strayTab = true end
            pcall(function() d:Destroy() end)
        end
    end
    local found = menuParts()
    if not keepToggle then restoreModScroller(found) end
    -- A crashed or replaced earlier build may have left the game's own song
    -- list hidden behind its overlay; put it back (our own open tab re-hides
    -- it right after, via hideNative).
    if strayTab and menuTab == nil then
        if found ~= nil and found.frame ~= nil then
            pcall(function() found.frame.Visible = true end)
        end
    end
end

-- Clones may carry LocalScripts that would start running once parented
-- into PlayerGui; the game's template clones must stay inert.
local function stripScripts(root)
    pcall(function()
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("LuaSourceContainer") then
                pcall(function() d:Destroy() end)
            end
        end
    end)
end

-- Native buttons show their text in Song.Label (Song.Text itself is empty).
local function setButtonLabel(btn, text)
    pcall(function()
        local song = btn:FindFirstChild("Song")
        local lab = song and song:FindFirstChild("Label") or nil
        if lab ~= nil and lab:IsA("TextLabel") then
            lab.Text = text
        elseif song ~= nil and (song:IsA("TextLabel") or song:IsA("TextButton")) then
            song.Text = text
        else
            btn.Text = text
        end
    end)
end

-- Clone of the game's own button (StatsPanel.Play / Skip look). The flat
-- fallback borrows the game's font so it still reads as native.
local function makeMenuButton(found, nativeBtn, text, name)
    local btn = nil
    if nativeBtn ~= nil and nativeBtn:IsA("TextButton") then
        local okC, c = pcall(function() return nativeBtn:Clone() end)
        if okC and c ~= nil then
            btn = c
            stripScripts(btn)
        end
    end
    if btn == nil then
        btn = Instance.new("TextButton")
        btn.AutoButtonColor = true
        btn.BackgroundColor3 = Color3.new(0, 0, 0)
        btn.BackgroundTransparency = 0.3
        btn.TextColor3 = Color3.fromRGB(220, 220, 220)
        btn.TextScaled = true
        pcall(function() btn.FontFace = found.tmpl.SongName.FontFace end)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = btn
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.new(1, 1, 1)
        stroke.Transparency = 0.9
        stroke.Thickness = 2
        stroke.Parent = btn
        local lim = Instance.new("UITextSizeConstraint")
        lim.MaxTextSize = 20
        lim.Parent = btn
    end
    btn.Name = name
    btn.Visible = true
    setButtonLabel(btn, text)
    return btn
end

----------------------------------------------------------------
-- Chart entries (display names, accents, summaries)
----------------------------------------------------------------
local function prettyChartName(path, chart)
    local id = chart and chart.song and chart.song.song or basename(path)
    local s = tostring(id):gsub("^afn_", ""):gsub("_", " ")
    return (s:gsub("(%l)(%w*)", function(a, b) return a:upper() .. b end))
end

-- Stable per-chart accent (the game gives every song its own row colour).
local function chartAccent(name)
    local h = 0
    for i = 1, #name do
        h = (h * 31 + string.byte(name, i)) % 360
    end
    return Color3.fromHSV(h / 360, 0.42, 1)
end

local function fmtTime(ms)
    local s = math.floor((tonumber(ms) or 0) / 1000 + 0.5)
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function chartLengthMs(chart)
    local last = 0
    for _, section in ipairs(chart.song.notes) do
        if type(section) == "table" and type(section.sectionNotes) == "table" then
            for _, row in ipairs(section.sectionNotes) do
                local t = (row[1] or 0) + (row[3] or 0)
                if t > last then last = t end
            end
        end
    end
    return last
end

local function chartCounts(chart)
    local bpmN = type(chart.bpmChanges) == "table" and #chart.bpmChanges or 0
    local svN = type(chart.sliderVelocities) == "table" and #chart.sliderVelocities or 0
    if chart._svAnchored then svN = math.max(0, svN - 1) end
    return bpmN, svN
end

local function buildEntries()
    local entries = {}
    for _, path in ipairs(listChartFiles()) do
        local chart = readChart(path)
        if chart then entries[#entries + 1] = { path = path, chart = chart } end
    end
    -- Display names derive from the internal song id, so variants sharing
    -- an id (e.g. full + NOBPM copies) would render identical rows:
    -- disambiguate with a counter.
    local used = {}
    for _, e in ipairs(entries) do
        e.display = prettyChartName(e.path, e.chart)
        if used[e.display] then
            used[e.display] += 1
            e.display = ("%s (%d)"):format(e.display, used[e.display])
        else
            used[e.display] = 1
        end
    end
    table.sort(entries, function(a, b) return a.display < b.display end)
    local favs = type(settings.favorites) == "table" and settings.favorites or {}
    for i, e in ipairs(entries) do
        local src = e.chart.song
        -- Source display metadata (converters emit these; hand-made charts
        -- may not have them and fall back to the id-derived name).
        e.title = type(src.title) == "string" and src.title ~= "" and src.title or nil
        e.artist = type(src.artist) == "string" and src.artist ~= "" and src.artist or nil
        e.diffLabel = type(src.difficulty) == "string" and src.difficulty ~= "" and src.difficulty or nil
        local bpm = tonumber(e.chart.song.bpm) or 0
        e.order = i
        e.key = basename(e.path)
        e.fav = favs[e.key] == true
        e.color = chartAccent(e.display)
        e.lengthMs = chartLengthMs(e.chart)
        e.sub = ("%d notes \u{00B7} %g BPM \u{00B7} %s"):format(
            e.chart._noteCount or 0, bpm, fmtTime(e.lengthMs))
        e.short = ("%g BPM \u{00B7} %s"):format(bpm, fmtTime(e.lengthMs))
    end
    return entries
end

-- One row per SONG: chart files that came from the same source song share
-- their (artist, title) metadata and become the difficulty entries of one
-- group; charts without metadata stay their own single-difficulty song.
-- Each difficulty gets a unique display label (duplicates get counters).
local function groupEntries(entries)
    local groups, byKey = {}, {}
    for _, e in ipairs(entries) do
        local key
        if e.title ~= nil then
            key = string.lower((e.artist or "") .. "\u{1}" .. e.title)
        else
            key = "file:" .. string.lower(basename(e.path))
        end
        local g = byKey[key]
        if g == nil then
            g = {
                key = key,
                display = e.title or e.display,
                artist = e.artist,
                entries = {},
            }
            byKey[key] = g
            groups[#groups + 1] = g
        end
        g.entries[#g.entries + 1] = e
        e.group = g
    end
    for _, g in ipairs(groups) do
        table.sort(g.entries, function(a, b)
            return (a.diffLabel or DIFF_LABEL) < (b.diffLabel or DIFF_LABEL)
        end)
        local used = {}
        for _, e in ipairs(g.entries) do
            local base = e.diffLabel or DIFF_LABEL
            if used[base] then
                used[base] += 1
                e.diffLabel = ("%s (%d)"):format(base, used[base])
            else
                used[base] = 1
                e.diffLabel = base
            end
        end
        g.accent = chartAccent(g.key)
        g.sub = g.entries[1].sub
    end
    table.sort(groups, function(a, b) return a.display < b.display end)
    for i, g in ipairs(groups) do g.order = i end
    return groups
end

-- Local favourites (the native star on each row). Stored by chart file name
-- in Settings.json; the game's own favourites list is never touched.
local function paintFav(entry)
    pcall(function()
        if entry.favSprite ~= nil then
            entry.favSprite.ImageColor3 = entry.fav and FAV_GOLD or Color3.new(1, 1, 1)
        end
    end)
end

local function saveFavorite(entry)
    if type(settings.favorites) ~= "table" then settings.favorites = {} end
    settings.favorites[entry.key] = entry.fav and true or nil
    saveSettings()
end

-- The row star is per SONG now: on if any of the group's chart files is
-- favourited; clicking sets every file of the group (one settings key each,
-- the storage format is unchanged).
local function groupHasFav(group)
    for _, e in ipairs(group.entries) do
        if e.fav then return true end
    end
    return false
end

-- Sort modes shared by both UIs (settings.sortMode): A-Z, recently played
-- first, favourites first. Recents rank by the earliest stats.recent hit
-- among the group's chart files; never-played songs trail A-Z. The reorder
-- is live: rows move via LayoutOrder, nothing is rebuilt.
local SORT_MODES = { "az", "recent", "favs" }
local SORT_LABELS = { az = "Sort: A-Z", recent = "Sort: Recent", favs = "Sort: Favourites" }

local function groupRecentRank(group)
    local rank = nil
    for _, e in ipairs(group.entries) do
        for i, stem in ipairs(stats.recent) do
            if stem == e.key then
                if rank == nil or i < rank then rank = i end
                break
            end
        end
    end
    return rank
end

local function sortGroups(groups, mode)
    if mode == "recent" then
        table.sort(groups, function(a, b)
            local ra, rb = groupRecentRank(a), groupRecentRank(b)
            ra = ra or math.huge
            rb = rb or math.huge
            if ra ~= rb then return ra < rb end
            return a.display < b.display
        end)
    elseif mode == "favs" then
        table.sort(groups, function(a, b)
            local fa, fb = groupHasFav(a), groupHasFav(b)
            if fa ~= fb then return fa end
            return a.display < b.display
        end)
    else
        table.sort(groups, function(a, b) return a.display < b.display end)
    end
    for i, g in ipairs(groups) do
        g.order = i
        if g.row ~= nil then pcall(function() g.row.LayoutOrder = i end) end
    end
end

local function cycleSortMode()
    local mode = settings.sortMode
    local idx = 1
    for j, m in ipairs(SORT_MODES) do
        if m == mode then idx = j end
    end
    return SORT_MODES[(idx % #SORT_MODES) + 1]
end

----------------------------------------------------------------
-- Difficulty preview (local audio only - never the chart itself)
----------------------------------------------------------------
local function findMenuMusic()
    local ok, inst = pcall(function()
        return RS.Modules.UI.SongSelectV2.Audio:FindFirstChild("UIMusic")
    end)
    if ok and inst ~= nil and inst:IsA("AudioPlayer") then return inst end
    return nil
end

local function stopMenuPreview()
    local p = menuPreview
    menuPreview = nil
    if p == nil then return end
    pcall(function() p.snd:Stop() end)
    pcall(function() p.snd:Destroy() end)
    -- Give the menu music its volume back (only if nothing else changed it
    -- while the preview was running).
    pcall(function()
        local d = p.duck
        if d ~= nil and d.inst.Parent ~= nil and d.inst.Volume == 0 and d.vol > 0 then
            d.inst.Volume = d.vol
        end
    end)
end

local function startMenuPreview(entry)
    stopMenuPreview()
    if type(entry) ~= "table" or menuTab == nil or menuTab.overlay == nil then return end
    local audioPath = automatchAudio(entry.chart, entry.path)
    if audioPath == nil then
        notify("Preview", "No audio file matches this chart.", true)
        return
    end
    local okA, asset = pcall(fn.getlocalasset, audioPath)
    if not okA or type(asset) ~= "string" then
        notify("Preview", "Could not open the audio file.", true)
        return
    end
    local snd = Instance.new("Sound")
    snd.Name = "AFNPreview"
    snd.Volume = PREVIEW_VOLUME
    snd.SoundId = asset
    snd.Parent = menuTab.overlay
    local duck = nil
    local um = findMenuMusic()
    if um ~= nil then
        duck = { inst = um, vol = um.Volume }
        pcall(function() um.Volume = 0 end)
    end
    local p = { snd = snd, duck = duck }
    menuPreview = p
    snd.Ended:Connect(function()
        if menuPreview == p then stopMenuPreview() end
    end)
    task.spawn(function()
        local t0 = os.clock()
        while menuPreview == p and not snd.IsLoaded and os.clock() - t0 < 6 do
            task.wait(0.05)
        end
        if menuPreview ~= p then return end
        local len = snd.TimeLength
        if len > 0 then
            -- Start a little way in, like a song-select preview.
            pcall(function() snd.TimePosition = math.max(0, math.min(len * 0.3, len - 25)) end)
        end
        snd:Play()
    end)
end

----------------------------------------------------------------
-- Selection + painting
----------------------------------------------------------------
local function paintMenuRow(group, selected)
    pcall(function()
        if group.stroke ~= nil then group.stroke.Transparency = selected and 0 or 0.6 end
        if group.bg ~= nil then
            group.bg.ImageTransparency = selected and 0 or (group.bgBase or 0.15)
        end
    end)
end

-- Native difficulty button look: dark chart-coloured fill + tinted border,
-- italic label from the game's own template.
local function styleDiffButton(btn, entry)
    if btn == nil then return end
    pcall(function()
        local h = entry.color:ToHSV()
        local dark = Color3.fromHSV(h, 0.95, 0.18)
        local edge = Color3.fromHSV(h, 0.55, 0.9)
        local label = btn:FindFirstChild("Difficulty", true)
        if label ~= nil and label:IsA("TextLabel") then
            local inner = label:FindFirstChild("Label")
            if inner ~= nil and inner:IsA("TextLabel") then
                inner.Text = entry.diffLabel or DIFF_LABEL
            else
                label.Text = entry.diffLabel or DIFF_LABEL
            end
        else
            btn.Text = entry.diffLabel or DIFF_LABEL
            btn.BackgroundColor3 = dark
        end
        local base = btn:FindFirstChild("BaseGradient")
        if base ~= nil and base:IsA("UIGradient") then base.Enabled = false end
        local cbg = btn:FindFirstChild("ColorBG")
        if cbg ~= nil and cbg:IsA("UIGradient") then
            cbg.Enabled = true
            cbg.Color = ColorSequence.new(dark)
        end
        local border = btn:FindFirstChild("Border")
        local stroke = border and border:FindFirstChildOfClass("UIStroke") or nil
        local grad = stroke and stroke:FindFirstChildOfClass("UIGradient") or nil
        if grad ~= nil then grad.Color = ColorSequence.new(edge) end
        btn.BackgroundTransparency = 0
        if border ~= nil then btn.BackgroundColor3 = Color3.new(1, 1, 1) end
    end)
end

-- Difficulty buttons are (re)built per selected song; the body sits below,
-- after the button helpers it needs (Luau locals resolve forward-only).
local renderDiffButtons

local function selectMenuEntry(entry, ui)
    if _G.AFNRayGen ~= MYGEN then return end
    if type(entry) ~= "table" or type(entry.chart) ~= "table" then return end
    if type(ui) == "table" and ui.selectedEntry ~= nil and ui.selectedEntry ~= entry then
        stopMenuPreview()
    end
    currentChart, currentChartPath = entry.chart, entry.path
    currentEntry = entry
    currentInfo = chartInfo(entry.chart, entry.path)
    local pickedAudio = automatchAudio(entry.chart, entry.path)
    if type(ui) ~= "table" then return end
    local group = entry.group
    local bpmN, svN = chartCounts(entry.chart)
    local lines = {
        ("\u{00B7} BPM: %g"):format(tonumber(entry.chart.song.bpm) or 0),
        ("\u{00B7} Keycount: %d"):format(entry.chart._playerKeyCount or 4),
        ("\u{00B7} Notes: %d (%d holds)"):format(entry.chart._noteCount or 0, entry.chart._holdCount or 0),
        "\u{00B7} Song Length: " .. fmtTime(entry.lengthMs),
        ("\u{00B7} BPM changes: %d"):format(bpmN),
        ("\u{00B7} Scroll velocities: %d"):format(svN),
        "\u{00B7} Audio: " .. (pickedAudio and basename(pickedAudio) or "none (audio-free)"),
    }
    local statsLines = chartStatsLines(entry.key)
    if statsLines ~= nil then
        table.insert(lines, "")
        for _, l in ipairs(statsLines) do table.insert(lines, l) end
    end
    pcall(function()
        if ui.songName ~= nil then
            ui.songName.Text = group ~= nil and group.display or entry.display
        end
        if ui.modName ~= nil then ui.modName.Text = "Custom Charts" end
        if ui.week ~= nil then ui.week.Text = entry.short end
        if ui.stats ~= nil then ui.stats.Text = table.concat(lines, "\n") end
        if ui.credits ~= nil then
            ui.credits.Text = ("Local custom chart \u{00B7} difficulty: %s\nFile: %s")
                :format(entry.diffLabel or DIFF_LABEL, entry.key)
        end
    end)
    -- Song cover on the native icon (Crop-fill); default art otherwise.
    pcall(function()
        if ui.coverIcon ~= nil then
            local coverPath = automatchCover(entry)
            local applied = false
            if coverPath ~= nil then
                local okA, asset = pcall(fn.getlocalasset, coverPath)
                if okA and type(asset) == "string" and asset ~= "" then
                    ui.coverIcon.Image = asset
                    ui.coverIcon.ScaleType = Enum.ScaleType.Crop
                    ui.coverIcon.ImageTransparency = 0
                    applied = true
                end
            end
            if not applied then
                ui.coverIcon.Image = ui.coverIconDefault
                ui.coverIcon.ScaleType = ui.coverIconScaleDefault
            end
        end
    end)
    ui.selectedEntry = entry
    ui.selected = group
    renderDiffButtons(ui, group)
    for _, g in ipairs(ui.groups or {}) do paintMenuRow(g, g == group) end
end

-- Width the game leaves for its list scrollbar; our rows/headers follow it.
local function rowInset(found)
    local inset = 12
    local tw = found.tmpl.Size.X.Offset
    local fw = found.frame.AbsoluteSize.X
    if tw > 0 and fw > tw and (fw - tw) <= 40 then inset = fw - tw end
    return inset
end

-- One row = one SONG (a group of chart files), a clone of the game's
-- SongTemplate filled the way the game's own renderer fills it (SongName /
-- WeekName / BG gradient / PrefixDisplay / favourite star). The selected
-- difficulty's stats ride the week line; difficulty buttons live in the
-- info column (renderDiffButtons).
local function buildMenuRow(found, rowsBox, group, ui)
    local r = found.tmpl:Clone()
    stripScripts(r)
    r.Name = "AFNRow"
    r.Visible = true -- the master template lives hidden
    r.LayoutOrder = group.order
    -- Template Size is pixel-based (the game's pooled scroller sizes it per
    -- layout); keep its height, make width follow our list minus the same
    -- scrollbar inset the game uses.
    local th = found.tmpl.Size.Y.Offset
    r.Size = UDim2.new(1, -rowInset(found), 0, th > 0 and th or 67)

    local nameLbl = r:FindFirstChild("SongName", true)
    if nameLbl ~= nil and nameLbl:IsA("TextLabel") then nameLbl.Text = group.display end
    local weekLbl = r:FindFirstChild("WeekName", true)
    if weekLbl ~= nil and weekLbl:IsA("TextLabel") then weekLbl.Text = group.sub end
    -- The game's own green tag pill (AutomaticSize X) reads "CUSTOM".
    local prefix = r:FindFirstChild("PrefixDisplay", true)
    if prefix ~= nil and prefix:IsA("TextLabel") then
        prefix.Text = "CUSTOM"
        prefix.Visible = true
    end
    -- Icons strip: keep the native favourite star, drop the FC medal slot.
    local icons = r:FindFirstChild("Icons")
    if icons ~= nil and icons:IsA("GuiObject") then
        local fc = icons:FindFirstChild("FCIcon")
        if fc ~= nil and fc:IsA("GuiObject") then fc.Visible = false end
        local favBtn = icons:FindFirstChild("Favorite")
        if favBtn ~= nil and favBtn:IsA("GuiButton") then
            group.favSprite = favBtn:FindFirstChild("Sprite")
            group.fav = groupHasFav(group)
            paintFav(group)
            favBtn.MouseButton1Click:Connect(function()
                local on = not groupHasFav(group)
                for _, e in ipairs(group.entries) do
                    e.fav = on
                    saveFavorite(e)
                end
                group.fav = on
                paintFav(group)
            end)
        end
    end
    local unavailable = r:FindFirstChild("UnavailableDisplay")
    if unavailable ~= nil and unavailable:IsA("GuiObject") then unavailable.Visible = false end

    local bg = r:FindFirstChild("BG")
    if bg ~= nil and bg:IsA("ImageLabel") then
        group.bg = bg
        group.bgBase = bg.ImageTransparency
        local grad = bg:FindFirstChildOfClass("UIGradient")
        if grad ~= nil then grad.Color = ColorSequence.new(group.accent) end
        -- Song cover as the row background art (Crop-fill under the accent
        -- gradient); dimmer than the native pattern while unselected so the
        -- name stays readable, full art when selected.
        local coverPath = automatchCover(group.entries[1])
        if coverPath ~= nil then
            local okA, asset = pcall(fn.getlocalasset, coverPath)
            if okA and type(asset) == "string" and asset ~= "" then
                bg.Image = asset
                bg.ScaleType = Enum.ScaleType.Crop
                group.bgBase = math.max(group.bgBase or 0.15, 0.35)
            end
        end
    end
    local stroke = r:FindFirstChild("StateStroke")
    if stroke ~= nil and stroke:IsA("UIStroke") then
        for _, g in ipairs(stroke:GetChildren()) do
            if g:IsA("UIGradient") then g.Enabled = (g.Name == "Default") end
        end
        stroke.Transparency = 0.6
        group.stroke = stroke
    end

    r.MouseEnter:Connect(function()
        if ui.selected ~= group and group.stroke ~= nil then group.stroke.Transparency = 0.2 end
    end)
    r.MouseLeave:Connect(function()
        if ui.selected ~= group and group.stroke ~= nil then group.stroke.Transparency = 0.6 end
    end)
    r.MouseButton1Click:Connect(function()
        selectMenuEntry(group.entries[1], ui)
    end)
    group.row = r
    r.Parent = rowsBox
    return r
end

-- The bordered "separation" rectangle the game puts above each mod's songs
-- (clone of WeekTemplate, right-aligned italic title).
local function buildHeaderRow(found, rowsBox, text, ui)
    local w = found.weekTmpl
    if w == nil then return nil end
    local okC, h = pcall(function() return w:Clone() end)
    if not okC or h == nil then return nil end
    stripScripts(h)
    h.Name = "AFNHeader"
    h.Visible = true
    h.LayoutOrder = 0
    local th = w.Size.Y.Offset
    h.Size = UDim2.new(1, -rowInset(found), 0, th > 0 and th or 26)
    local lab = h:FindFirstChild("Week")
    if lab ~= nil and lab:IsA("TextLabel") then lab.Text = text end
    local bg = h:FindFirstChild("BG")
    local grad = bg and bg:FindFirstChildOfClass("UIGradient") or nil
    if grad ~= nil then
        grad.Color = ColorSequence.new(MOD_ACCENT, Color3.fromRGB(90, 120, 230))
    end
    -- Sort button (left side of the header; the Week label is right-aligned).
    -- Click cycles A-Z -> Recent -> Favourites, saves the choice and
    -- re-sorts the live rows via LayoutOrder (nothing is rebuilt).
    if ui ~= nil then
        pcall(function()
            local sortBtn = Instance.new("TextButton")
            sortBtn.Name = "AFNSort"
            sortBtn.AutoButtonColor = true
            sortBtn.Text = SORT_LABELS[settings.sortMode] or SORT_LABELS.az
            sortBtn.TextColor3 = Color3.new(1, 1, 1)
            sortBtn.TextScaled = true
            sortBtn.BackgroundColor3 = Color3.new(0, 0, 0)
            sortBtn.BackgroundTransparency = 0.6
            sortBtn.BorderSizePixel = 0
            sortBtn.Position = UDim2.new(0, 6, 0, 2)
            sortBtn.Size = UDim2.new(0, 190, 1, -4)
            sortBtn.ZIndex = (lab and lab.ZIndex or 1) + 2
            if lab ~= nil then
                pcall(function() sortBtn.FontFace = lab.FontFace end)
            end
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 6)
            corner.Parent = sortBtn
            sortBtn.Parent = h
            ui.sortBtn = sortBtn
            sortBtn.MouseButton1Click:Connect(function()
                local mode = cycleSortMode()
                settings.sortMode = mode
                saveSettings()
                sortBtn.Text = SORT_LABELS[mode] or SORT_LABELS.az
                if type(ui.groups) == "table" then sortGroups(ui.groups, mode) end
            end)
        end)
    end
    h.Parent = rowsBox
    return h
end

----------------------------------------------------------------
-- Right-hand info column
----------------------------------------------------------------
local function cloneInfoPanel(info, nativeName, newName, order)
    local nat = info:FindFirstChild(nativeName)
    if nat == nil then return nil end
    local okC, c = pcall(function() return nat:Clone() end)
    if not okC or c == nil then return nil end
    stripScripts(c)
    c.Name = newName
    c.Visible = true
    c.LayoutOrder = order
    return c
end

local function hideArrows(panel)
    for _, nm in ipairs({ "Advancy", "Backy" }) do
        local b = panel:FindFirstChild(nm, true)
        if b ~= nil and b:IsA("GuiObject") then b.Visible = false end
    end
end

-- The game's difficulty buttons come in two looks; prefer the pooled one
-- with a Border frame (what the menu actually shows), else the template.
local function findDiffTemplate(list)
    local styleA, styleB = nil, nil
    for _, c in ipairs(list:GetChildren()) do
        if c:IsA("TextButton") then
            if c:FindFirstChild("Border") then
                styleB = c
            elseif styleA == nil and c:FindFirstChild("Difficulty", true) then
                styleA = c
            end
        end
    end
    return styleB or styleA
end

local function makeFlatDiffButton(found)
    local b = Instance.new("TextButton")
    b.AutoButtonColor = true
    b.BackgroundColor3 = Color3.fromRGB(40, 0, 0)
    b.TextColor3 = Color3.fromRGB(220, 220, 220)
    b.TextScaled = true
    pcall(function() b.FontFace = found.tmpl.SongName.FontFace end)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = b
    return b
end

-- Assignment for the forward cell declared above selectMenuEntry: one
-- native-styled difficulty button per chart entry of the selected song.
-- Click = select that difficulty + preview its audio (session-19 preview).
renderDiffButtons = function(ui, group)
    local list = ui.diffList
    if list == nil then return end
    for _, c in ipairs(list:GetChildren()) do
        if not (c:IsA("UIPadding") or c:IsA("UIListLayout") or c:IsA("UIGridLayout")) then
            pcall(function() c:Destroy() end)
        end
    end
    ui.diffButtons = {}
    if type(group) ~= "table" or type(group.entries) ~= "table" then
        pcall(function() list.CanvasSize = UDim2.new(0, 0, 0, 0) end)
        return
    end
    for i, e in ipairs(group.entries) do
        local btn = nil
        if ui.diffTpl ~= nil then
            local okB, b = pcall(function() return ui.diffTpl:Clone() end)
            if okB and b ~= nil then
                btn = b
                stripScripts(btn)
            end
        end
        if btn == nil then btn = makeFlatDiffButton(ui.diffFound) end
        btn.Name = "AFNDiff"
        btn.Visible = true
        btn.LayoutOrder = i
        btn.AnchorPoint = Vector2.new(0.5, 0)
        btn.Position = UDim2.new(0.5, 0, 0, (i - 1) * DIFF_BTN_H)
        btn.Size = UDim2.new(1, -24, 0, 59)
        styleDiffButton(btn, e)
        local border = btn:FindFirstChild("Border")
        local stroke = border and border:FindFirstChildOfClass("UIStroke") or nil
        if stroke ~= nil then
            stroke.Transparency = (e == ui.selectedEntry) and 0 or 0.35
        end
        btn.MouseButton1Click:Connect(function()
            if _G.AFNRayGen ~= MYGEN then return end
            selectMenuEntry(e, ui)
            startMenuPreview(e)
        end)
        btn.Parent = list
        ui.diffButtons[i] = btn
    end
    pcall(function() list.CanvasSize = UDim2.new(0, 0, 0, #group.entries * DIFF_BTN_H) end)
end

-- All four native panels at their native sizes: the SongInfo layout stretches
-- visible children to fill the column, so a partial set renders oversized.
local function buildInfoPanels(t, found, ui)
    local info = found.info
    if info == nil then return end

    local sel = cloneInfoPanel(info, "SelectedSong", "AFNSelected", 1)
    if sel ~= nil then
        local data = sel:FindFirstChild("DataContainer")
        ui.songName = data and data:FindFirstChild("SongName") or nil
        ui.modName = data and data:FindFirstChild("ModName") or nil
        ui.week = sel:FindFirstChild("WeekName")
        -- Cover slot: the native icon; capture its template image so charts
        -- without a cover keep the default art.
        local icon = sel:FindFirstChild("Icon")
        if icon ~= nil and icon:IsA("ImageLabel") then
            ui.coverIcon = icon
            ui.coverIconDefault = icon.Image
            ui.coverIconScaleDefault = icon.ScaleType
        end
        for _, nm in ipairs({ "SongTweaks", "Visualizer" }) do
            local x = sel:FindFirstChild(nm)
            if x ~= nil then pcall(function() x:Destroy() end) end
        end
        sel.Parent = info
        t.extras[#t.extras + 1] = sel
    end

    local cr = cloneInfoPanel(info, "Credits", "AFNCreds", 2)
    if cr ~= nil then
        local sf = cr:FindFirstChild("ScrollingFrame")
        local body = nil
        if sf ~= nil then
            local extra = sf:FindFirstChild("AFNCredits")
            if extra ~= nil then pcall(function() extra:Destroy() end) end
            body = sf:FindFirstChild("ModCredits")
            if body ~= nil and body:IsA("TextLabel") then
                body.RichText = false
                ui.credits = body
            end
        end
        hideArrows(cr)
        cr.Parent = info
        t.extras[#t.extras + 1] = cr
        local pl = sf and sf:FindFirstChildOfClass("UIPageLayout") or nil
        if pl ~= nil and body ~= nil then pcall(function() pl:JumpTo(body) end) end
    end

    local st = cloneInfoPanel(info, "SongStats", "AFNStats", 3)
    if st ~= nil then
        local pages = st:FindFirstChild("PagesContent")
        local body = nil
        if pages ~= nil then
            for _, nm in ipairs({ "SongDifficulty", "SongBest" }) do
                local extra = pages:FindFirstChild(nm)
                if extra ~= nil then pcall(function() extra:Destroy() end) end
            end
            body = pages:FindFirstChild("SongInfo")
            if body ~= nil and body:IsA("TextLabel") then
                body.RichText = false -- file names may contain markup characters
                ui.stats = body
            end
        end
        hideArrows(st)
        st.Parent = info
        t.extras[#t.extras + 1] = st
        local pl = pages and pages:FindFirstChildOfClass("UIPageLayout") or nil
        if pl ~= nil and body ~= nil then pcall(function() pl:JumpTo(body) end) end
    end

    local df = cloneInfoPanel(info, "Difficulties", "AFNDiffs", 4)
    if df ~= nil then
        local list = df:FindFirstChild("DifficultyList")
        if list ~= nil then
            for _, c in ipairs(list:GetChildren()) do
                if not (c:IsA("UIPadding") or c:IsA("UIListLayout") or c:IsA("UIGridLayout")) then
                    pcall(function() c:Destroy() end)
                end
            end
            -- Buttons are (re)built per selected song by renderDiffButtons;
            -- keep the native template + panel context for it.
            ui.diffList = list
            ui.diffTpl = found.diffList and findDiffTemplate(found.diffList) or nil
            ui.diffFound = found
        end
        df.Parent = info
        t.extras[#t.extras + 1] = df
    end
end

----------------------------------------------------------------
-- Pinned mod-list row
----------------------------------------------------------------
local function paintModRow(open)
    pcall(function()
        if modRowBtn == nil then return end
        local st = modRowBtn:FindFirstChildOfClass("UIStroke")
        if st ~= nil then st.Transparency = open and 0.05 or 0.75 end
    end)
end

-- One clone of the game's mod row: same font/corners/stroke/gradient look as
-- every other mod entry, our own colour, name and a note glyph as icon.
local function buildModRow(found)
    local tmpl = found.modTmpl
    if tmpl == nil or found.mods == nil then return nil end
    local okC, r = pcall(function() return tmpl:Clone() end)
    if not okC or r == nil then return nil end
    stripScripts(r)
    r.Name = "AFNModRow"
    r.Visible = true
    r.LayoutOrder = 0
    r.AnchorPoint = Vector2.new(0, 0)
    -- Same left edge as the native rows (scroller inset 1% + its 2px padding)
    -- and the same top as the native list; width = native row width.
    r.Position = UDim2.new(0.01, 2, 0.07, 0)
    r.Size = UDim2.new(0.98, -10, 0, MOD_ROW_H)

    local nameLbl = r:FindFirstChild("ModName")
    if nameLbl ~= nil and nameLbl:IsA("TextLabel") then nameLbl.Text = "Custom Charts" end
    local prefix = r:FindFirstChild("PrefixDisplay")
    if prefix ~= nil and prefix:IsA("GuiObject") then prefix.Visible = false end
    local icons = r:FindFirstChild("Icons")
    if icons ~= nil and icons:IsA("GuiObject") then icons.Visible = false end
    local bg = r:FindFirstChild("BG")
    local grad = bg and bg:FindFirstChildOfClass("UIGradient") or nil
    if grad ~= nil then grad.Color = ColorSequence.new(MOD_ACCENT) end
    local icon = r:FindFirstChild("ModIcon")
    if icon ~= nil and icon:IsA("ImageLabel") then
        icon.Image = ""
        icon.ImageTransparency = 1
        local glyph = Instance.new("TextLabel")
        glyph.BackgroundTransparency = 1
        glyph.Size = UDim2.new(1, 0, 1, 0)
        glyph.Text = NOTE_GLYPH
        glyph.TextScaled = true
        glyph.TextColor3 = Color3.new(1, 1, 1)
        if nameLbl ~= nil then pcall(function() glyph.FontFace = nameLbl.FontFace end) end
        local gs = Instance.new("UIStroke")
        gs.Thickness = 2
        gs.Color = Color3.new(0, 0, 0)
        gs.Parent = glyph
        glyph.Parent = icon
    end

    r.MouseEnter:Connect(function()
        if menuTab == nil then
            local st = r:FindFirstChildOfClass("UIStroke")
            if st ~= nil then st.Transparency = 0.35 end
        end
    end)
    r.MouseLeave:Connect(function()
        paintModRow(menuTab ~= nil)
    end)
    r.MouseButton1Click:Connect(function()
        if _G.AFNRayGen ~= MYGEN then return end
        toggleMenuTab()
    end)
    r.Parent = found.mods
    return r
end

----------------------------------------------------------------
-- Open / close / toggle
----------------------------------------------------------------
local function closeMenuTab()
    local t = menuTab
    menuTab = nil
    stopMenuPreview()
    if type(t) ~= "table" then return end
    for _, c in ipairs(t.conns or {}) do pcall(function() c:Disconnect() end) end
    for _, h in ipairs(t.hidden or {}) do
        pcall(function() h.inst.Visible = h.vis end)
    end
    for _, x in ipairs(t.extras or {}) do pcall(function() x:Destroy() end) end
    pcall(function() if t.overlay ~= nil then t.overlay:Destroy() end end)
    if menuToggleBtn ~= nil then setButtonLabel(menuToggleBtn, "Custom Charts") end
    paintModRow(false)
end

-- Hides a native piece while our tab is open; remembers it for close.
local function hideNative(t, inst)
    if inst == nil then return end
    local okV, vis = pcall(function() return inst.Visible end)
    if okV and vis then
        t.hidden[#t.hidden + 1] = { inst = inst, vis = true }
        pcall(function() inst.Visible = false end)
    end
end

-- Pressing any native mod / tab row means the player picked another list:
-- close our tab so the game's own list shows again (the game handles the
-- same press itself).
local function hookNativeModRows(t, found)
    local sf = found.modScroll
    if sf == nil then return end
    local function hook(c)
        if c:IsA("GuiButton") then
            t.conns[#t.conns + 1] = c.Activated:Connect(function()
                if menuTab == t then closeMenuTab() end
            end)
        end
    end
    for _, c in ipairs(sf:GetChildren()) do hook(c) end
    t.conns[#t.conns + 1] = sf.ChildAdded:Connect(hook)
end

-- The always-present entry point: a clone of the game's own Play button,
-- appended to the StatsPanel row (LayoutOrder 4, right after the native
-- Play slot). Appears in the lobby menu and in the solo stage menu alike;
-- re-created if the game rebuilds its menu.
local function ensureMenuToggle()
    if _G.AFNRayGen ~= MYGEN then return false end
    local found = menuParts()
    if found == nil or found.stats == nil then return false end
    local alive = false
    pcall(function() alive = menuToggleBtn ~= nil and menuToggleBtn.Parent == found.stats end)
    if alive then return true end
    pcall(function() if menuToggleBtn ~= nil then menuToggleBtn:Destroy() end end)
    menuToggleBtn = nil
    local nativePlay = found.stats:FindFirstChild("Play")
    local btn = makeMenuButton(found, nativePlay, menuTab ~= nil and "Close Custom" or "Custom Charts", "AFNToggle")
    btn.Size = UDim2.new(0.15, 0, 1, 0)
    btn.LayoutOrder = 4
    btn.Parent = found.stats
    btn.MouseButton1Click:Connect(function()
        if _G.AFNRayGen ~= MYGEN then return end
        toggleMenuTab()
    end)
    menuToggleBtn = btn
    return true
end

-- Keeps the pinned mod-list row present, and the native mod scroller shrunk
-- by exactly its height (re-applied if the game ever rewrites the size).
local function ensureModRow()
    if _G.AFNRayGen ~= MYGEN then return false end
    local found = menuParts()
    if found == nil or found.mods == nil or found.modScroll == nil then return false end
    local alive = false
    pcall(function() alive = modRowBtn ~= nil and modRowBtn.Parent == found.mods end)
    if not alive then
        pcall(function() if modRowBtn ~= nil then modRowBtn:Destroy() end end)
        modRowBtn = nil
        local row = buildModRow(found)
        if row == nil then return false end
        modRowBtn = row
        paintModRow(menuTab ~= nil)
    end
    pcall(function()
        local sf = found.modScroll
        local shrink = MOD_ROW_H + MOD_ROW_GAP
        local cur = sf:GetAttribute("AFNShrunk")
        if type(cur) ~= "number" or sf.Size.Y.Offset > -shrink + 0.5 then
            local s = sf.Size
            sf.Size = UDim2.new(s.X.Scale, s.X.Offset, s.Y.Scale, s.Y.Offset - shrink)
            sf:SetAttribute("AFNShrunk", shrink)
        end
    end)
    return true
end

local function destroyMenuToggle()
    pcall(function() if menuToggleBtn ~= nil then menuToggleBtn:Destroy() end end)
    menuToggleBtn = nil
    pcall(function() if modRowBtn ~= nil then modRowBtn:Destroy() end end)
    modRowBtn = nil
    pcall(function() restoreModScroller(menuParts()) end)
end

local function startMenuWatcher()
    if menuWatcherOn then return end
    menuWatcherOn = true
    task.spawn(function()
        while _G.AFNRayGen == MYGEN do
            pcall(ensureMenuToggle)
            pcall(ensureModRow)
            task.wait(2)
        end
    end)
end

local function openMenuTab()
    if menuTab ~= nil then return end -- toggleMenuTab closes; never double-open
    local found = menuParts()
    if found == nil or found.songs == nil or found.frame == nil or found.tmpl == nil then
        notify("Custom tab", "Song menu not found \u{2014} open it first.", true)
        return
    end
    if menuPlayerCount() ~= 1 then
        notify("Custom tab", "Solo only: custom plays need an empty server.", true)
        return
    end
    sweepMenuPieces(true)
    local entries = buildEntries()
    if #entries == 0 then
        notify("Custom tab", "No convertible charts on disk.", true)
        return
    end
    local groups = groupEntries(entries)
    sortGroups(groups, settings.sortMode or "az")
    local t = { conns = {}, hidden = {}, extras = {}, overlay = nil }
    menuTab = t
    local ui = { entries = entries, groups = groups }
    local okB, errB = pcall(function()
        -- Cover the game's own song list; keep it hidden even if the game
        -- re-shows it while our tab is open.
        hideNative(t, found.frame)
        t.conns[#t.conns + 1] = found.frame:GetPropertyChangedSignal("Visible"):Connect(function()
            if menuTab == t and found.frame.Visible then found.frame.Visible = false end
        end)
        if found.info ~= nil then
            for _, nm in ipairs({ "SelectedSong", "SongStats", "Difficulties", "Credits", "SongCredits" }) do
                hideNative(t, found.info:FindFirstChild(nm))
            end
            -- The native "Select a song first!" frame fills the whole column.
            local skip = found.info:FindFirstChild("ListSkip")
            hideNative(t, skip and skip:FindFirstChild("SelectWarning") or nil)
        end
        if found.stats ~= nil then hideNative(t, found.stats:FindFirstChild("Play")) end

        -- Transparent container over the Songs panel: the panel's own
        -- background, corners and stroke stay as the game draws them.
        local overlay = Instance.new("Frame")
        overlay.Name = "AFNCustomTab"
        overlay.BackgroundTransparency = 1
        overlay.BorderSizePixel = 0
        overlay.Size = UDim2.new(1, 0, 1, 0)
        overlay.ClipsDescendants = true
        overlay.ZIndex = 50
        overlay.Parent = found.songs
        t.overlay = overlay
        ui.overlay = overlay

        -- Search bar: the game's own SongSearch, filtering OUR list.
        local searchBox = nil
        if found.search ~= nil then
            local s = found.search:Clone()
            stripScripts(s)
            s.Name = "AFNSearch"
            s.Visible = true
            s.Parent = overlay
            searchBox = s:FindFirstChildWhichIsA("TextBox", true)
            if searchBox ~= nil then
                searchBox.Text = ""
                searchBox.PlaceholderText = ("Search %d custom song(s)..."):format(#groups)
            end
        end

        -- Song list: same rect + scrollbar look as the game's own list.
        local sf = found.frame
        local rowsBox = Instance.new("ScrollingFrame")
        rowsBox.Name = "AFNRows"
        rowsBox.BackgroundTransparency = 1
        rowsBox.BorderSizePixel = 0
        rowsBox.Active = true
        rowsBox.ClipsDescendants = true
        rowsBox.ScrollingDirection = Enum.ScrollingDirection.Y
        rowsBox.AutomaticCanvasSize = Enum.AutomaticSize.Y
        rowsBox.CanvasSize = UDim2.new(0, 0, 0, 0)
        rowsBox.AnchorPoint = sf.AnchorPoint
        rowsBox.Position = sf.Position
        rowsBox.Size = sf.Size
        pcall(function()
            rowsBox.ScrollBarThickness = sf.ScrollBarThickness
            rowsBox.ScrollBarImageColor3 = sf.ScrollBarImageColor3
            rowsBox.ScrollBarImageTransparency = sf.ScrollBarImageTransparency
            rowsBox.VerticalScrollBarInset = sf.VerticalScrollBarInset
        end)
        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 6)
        layout.Parent = rowsBox
        rowsBox.Parent = overlay

        buildInfoPanels(t, found, ui)
        ui.header = buildHeaderRow(found, rowsBox, "Custom Charts", ui)
        for _, g in ipairs(groups) do
            local okRow, rowErr = pcall(buildMenuRow, found, rowsBox, g, ui)
            if not okRow then
                warn("[AFNRay] menu row failed: " .. tostring(rowErr))
            end
        end

        if searchBox ~= nil then
            t.conns[#t.conns + 1] = searchBox:GetPropertyChangedSignal("Text"):Connect(function()
                local q = string.lower(searchBox.Text)
                local any = false
                for _, g in ipairs(groups) do
                    if g.row ~= nil then
                        local show = q == ""
                        if not show and string.find(string.lower(g.display), q, 1, true) ~= nil then
                            show = true
                        end
                        if not show and g.artist ~= nil
                            and string.find(string.lower(g.artist), q, 1, true) ~= nil then
                            show = true
                        end
                        if not show then
                            for _, e in ipairs(g.entries) do
                                local dl = string.lower(e.diffLabel or "")
                                if string.find(dl, q, 1, true) ~= nil then
                                    show = true
                                    break
                                end
                            end
                        end
                        g.row.Visible = show
                        if show then any = true end
                    end
                end
                if ui.header ~= nil then ui.header.Visible = any end
            end)
        end

        hookNativeModRows(t, found)

        -- Play lands in the native Play slot (StatsPanel, LayoutOrder 3).
        if found.stats ~= nil then
            local nativePlay = found.stats:FindFirstChild("Play")
            local playBtn = makeMenuButton(found, nativePlay, "Play Custom", "AFNPlay")
            if nativePlay ~= nil then
                playBtn.Size = nativePlay.Size
                playBtn.LayoutOrder = nativePlay.LayoutOrder
            else
                playBtn.Size = UDim2.new(0.2, 0, 1, 0)
                playBtn.LayoutOrder = 3
            end
            playBtn.Parent = found.stats
            t.extras[#t.extras + 1] = playBtn
            playBtn.MouseButton1Click:Connect(function()
                if _G.AFNRayGen ~= MYGEN then return end
                if menuPlayerCount() ~= 1 then
                    notify("Custom tab", "Solo only: custom plays need an empty server.", true)
                    return
                end
                if type(currentChart) ~= "table" then
                    notify("Custom tab", "Pick a chart first.", true)
                    return
                end
                stopMenuPreview() -- the chart brings its own audio
                local okP, errP = xpcall(doPlayFn, safeTraceback)
                if not okP then notify("Custom play error", tostring(errP):sub(1, 300), true) end
            end)
        end
    end)
    if not okB then
        local msg = tostring(errB):sub(1, 160)
        closeMenuTab()
        notify("Custom tab", "Could not build the tab: " .. msg, true)
        return
    end

    -- Pre-pick: keep the chart already chosen (Rayfield or earlier open),
    -- else the first song's first difficulty, so Play works immediately.
    local first = groups[1] and groups[1].entries[1] or nil
    for _, e in ipairs(entries) do
        if e.path == currentChartPath then
            first = e
            break
        end
    end
    if first ~= nil then pcall(selectMenuEntry, first, ui) end
    pcall(ensureMenuToggle)
    pcall(ensureModRow)
    if menuToggleBtn ~= nil then setButtonLabel(menuToggleBtn, "Close Custom") end
    paintModRow(true)
    notify("Custom tab", ("%d custom song(s), %d chart(s) loaded."):format(#groups, #entries))
end

toggleMenuTab = function()
    if _G.AFNRayGen ~= MYGEN then return end
    if menuTab ~= nil then
        closeMenuTab()
    else
        openMenuTab()
    end
end

-- Boot: clear leftovers of earlier builds (and undo any native-list shrink
-- they left), then keep the in-menu button + pinned mod row present.
pcall(sweepMenuPieces, false)
startMenuWatcher()

----------------------------------------------------------------
-- 7. Rayfield UI
----------------------------------------------------------------
local Rayfield = nil
local infoLabel, statusLabel, audioLabel, skinLabel = nil, nil, nil, nil
local songDropdown, audioDropdown, skinDropdown, diffDropdown = nil, nil, nil, nil
local songByLabel = {}
local audioByLabel = {}
local skinByLabel = {}
local diffByLabel = {}
local suppressDiffPick = false -- programmatic diffDropdown:Set must not re-select

local function refreshSongList()
    -- One row per SONG (charts grouped by their source title/artist metadata).
    local labels = {}
    songByLabel = {}
    local gs = groupEntries(buildEntries())
    sortGroups(gs, settings.sortMode or "az")
    for _, g in ipairs(gs) do
        local label = g.display
        local base, dup = label, 2
        while songByLabel[label] do
            label = ("%s (%d)"):format(base, dup)
            dup += 1
        end
        songByLabel[label] = g
        table.insert(labels, label)
    end
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

-- Options for the Difficulty dropdown: one per chart file of the song.
local function refreshDiffList(group)
    local labels = {}
    diffByLabel = {}
    if type(group) == "table" and type(group.entries) == "table" then
        for _, e in ipairs(group.entries) do
            local label = e.diffLabel or DIFF_LABEL
            diffByLabel[label] = e
            table.insert(labels, label)
        end
    end
    if #labels == 0 then labels = { "(pick a chart first)" } end
    return labels
end

-- Load one chart file and reflect it in both dropdowns (song + difficulty).
local function selectEntry(entry)
    if type(entry) ~= "table" then return end
    local path = entry.path
    local chart, err = readChart(path)
    if not chart then
        notify("Chart error", tostring(err), true)
        if infoLabel then pcall(function() infoLabel:Set("Error: " .. tostring(err)) end) end
        return
    end
    currentChart, currentChartPath = chart, path
    currentEntry = entry
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
    if diffDropdown ~= nil and type(entry.group) == "table" then
        local opts = refreshDiffList(entry.group)
        pcall(function() diffDropdown:Refresh(opts) end)
        if entry.diffLabel ~= nil then
            suppressDiffPick = true
            pcall(function() diffDropdown:Set(entry.diffLabel) end)
            suppressDiffPick = false
        end
    end
    notify("Chart loaded", basename(path))
end

-- Song dropdown pick: the song's first difficulty starts selected.
local function selectChart(label)
    local g = songByLabel[label]
    if type(g) ~= "table" or type(g.entries) ~= "table" or g.entries[1] == nil then
        return -- placeholder row
    end
    selectEntry(g.entries[1])
end

-- Difficulty dropdown pick.
local function selectDiff(label)
    local entry = diffByLabel[label]
    if entry ~= nil then selectEntry(entry) end
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
    notify("Loading", (playLabels(currentChart, currentChartPath)))
    local rep = playChart()
    notify("Play: " .. tostring(rep.stage), summarizeReport(rep),
        not (rep.start_ok and (rep.stage == "playing" or rep.stage == "ended-results")))
    if rep and rep.stage == "playing" then
        -- Leave the song-select like the native Play does. Restore our menu
        -- tab's native pieces (only when this play came from the tab; Rayfield
        -- plays never touch the menu), then run the game's own leave-select
        -- work: lobby music off, blur faded, shown-state cleared (see
        -- leaveSongSelect; it skips itself when the select was not up).
        -- The game re-shows the select itself on its next selection phase.
        local fromMenu = menuTab ~= nil
        if menuTab ~= nil then
            pcall(closeMenuTab)
        end
        if ctx ~= nil then
            local okLv, lvRes = pcall(leaveSongSelect, ctx, fromMenu)
            local lvNote = okLv and tostring(lvRes) or ("FAIL:" .. tostring(lvRes))
            if type(rep.subs) == "table" then rep.subs["leave-select"] = lvNote end
            if lvNote:find("FAIL", 1, true) or lvNote:find("hide=skipped", 1, true) then
                notify("Song select", "Did not fully leave the song select: " .. lvNote, true)
            end
        end
        -- Fallback for the frame itself (hide() already does this when found).
        if fromMenu then
            pcall(function()
                local r = menuRoot()
                if r ~= nil then r.Visible = false end
            end)
        end
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
        -- Judge-swap: skin judgement/combo art onto spawned popups.
        -- No teardown: popups are engine-owned and die on their own.
        -- Event-driven (zero flash): popups are fully built before the
        -- engine parents them, so DescendantAdded swaps land pre-render.
        -- The connection self-disconnects when the play ends.
        if ctx ~= nil and ctx.judgeSwap ~= nil then
            local c0 = ctx
            local js0 = c0.judgeSwap
            pcall(pollJudgeSwap, js0) -- sweep anything already spawned
            local okC, conn = pcall(function()
                return js0.container.DescendantAdded:Connect(function(d)
                    if _G.AFNRayGen ~= MYGEN or not playing or ctx ~= c0 then
                        pcall(function() conn:Disconnect() end)
                        return
                    end
                    pcall(swapJudgeLabel, js0, d)
                end)
            end)
            if okC and conn ~= nil then
                js0.conn = conn
            end
        end
    end
end

-- Back-assign the forward cell (see section 6.5): the menu tab is defined
-- before doPlay and must call it without binding the nil global.
doPlayFn = doPlay

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

    diffDropdown = Tab:CreateDropdown({
        Name = "Difficulty",
        Options = { "(pick a chart first)" },
        CurrentOption = nil,
        MultiSelection = false,
        Callback = function(option)
            if _G.AFNRayGen ~= MYGEN then return end
            if suppressDiffPick then return end
            local label = type(option) == "table" and option[1] or option
            selectDiff(label)
        end,
    })

    -- Song list order (shared with the in-menu tab's header button).
    local sortByLabel = { ["A-Z"] = "az", ["Recent"] = "recent", ["Favourites"] = "favs" }
    local sortLabelByMode = { az = "A-Z", recent = "Recent", favs = "Favourites" }
    Tab:CreateDropdown({
        Name = "Sort songs",
        Options = { "A-Z", "Recent", "Favourites" },
        CurrentOption = sortLabelByMode[settings.sortMode] or "A-Z",
        MultiSelection = false,
        Callback = function(option)
            if _G.AFNRayGen ~= MYGEN then return end
            local label = type(option) == "table" and option[1] or option
            local mode = sortByLabel[label]
            if mode == nil or mode == settings.sortMode then return end
            settings.sortMode = mode
            saveSettings()
            local opts = refreshSongList()
            if songDropdown then pcall(function() songDropdown:Refresh(opts) end) end
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
            notify("Refreshed", #opts .. " song(s) in " .. CHARTS_DIR)
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

    Tab:CreateToggle({
        Name = "Tame teleports (engine spawn fix)",
        CurrentValue = settings.tameSV ~= false,
        Callback = function(value)
            settings.tameSV = value and true or false
            saveSettings()
        end,
    })

    Tab:CreateButton({
        Name = "Play chart",
        Callback = function()
            local ok, err = xpcall(doPlay, safeTraceback)
            if not ok then notify("Play error", tostring(err):sub(1, 300), true) end
        end,
    })
    Tab:CreateButton({
        Name = "Stop",
        Callback = function()
            local ok, err = pcall(doStop)
            if not ok then notify("Stop error", tostring(err), true) end
        end,
    })
    Tab:CreateButton({
        Name = "Song-menu tab",
        Callback = function()
            local ok, err = pcall(toggleMenuTab)
            if not ok then notify("Custom tab error", tostring(err), true) end
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
    pcall(closeMenuTab)
    pcall(destroyMenuToggle)
    pcall(sweepMenuPieces, false)
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

local uiOk, uiErr = xpcall(buildUI, safeTraceback)
if not uiOk then
    warn("[AFNRay] UI failed: " .. tostring(uiErr))
    pcall(sweepRayfield)
    return
end
notify("AfternightCustomSongs v" .. VERSION, "Pick a chart, then Play.")
