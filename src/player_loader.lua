-- AFN player_loader v1: local custom-chart play through the real orchestrator.
-- One shot per client session. Preflight gates -> reversible local
-- substitutions -> xpcall(loadSong) -> remoteListen["Start"](0) ->
-- observe -> abruptGameEnd teardown. Returns a report table.
--
-- Local-only design (see HANDOFF session 4):
--   * stage=nil  => v23=false, stageRemote=nil  => every fireStageRemote*
--     call in the play path early-returns (NetworkFunctions source).
--   * Audio omitted from the songIds entry => SongPlayer stays paused =>
--     the Conductor free-runs from a wall clock (updateConductor source).
--   * SkipCountdown=true  => both getAsset("Countdowns") sites skipped.
--   * Ratings/<JudgementStyle> cloned from Ratings/Afternight before the
--     run  => getAsset cache hit, no RequestEvent traffic (getAsset source).
--   * enterLoadingState pre-flip with empty Sides => the overhead
--     GetPreviewOverheadData:InvokeServer in LoadingScreen.start never runs.
--   * Main.Character (RemoteEvent) temporarily relocated => CharacterModule
--     Replicate() calls no-op (remote=nil) for our chars.
--   * No fireServer wrap (needs explicit user approval). Known residual:
--     CharReplicator.SetSettings fires "UpdPreferences"+"Sync" ONCE when
--     loadStageCharacters flips true->false (first run only).
--   * Engine-side require() of our executor-created chart ModuleScript fails
--     inside the game (warn "Chart is not valid!" => loadSong returns ok but
--     builds nothing). loadSong's env.require is wrapped for that ONE
--     instance (returns the chart JSON); all other requires pass through.
--     Restored in teardown.
--   * loadSong / Start / teardown run at thread identity 2 (restored after).
--     At the executor's default identity BaseHUD.Switch's own
--     require(HUD:Clone()) fails ("Cannot require a non-RobloxScript module
--     from a RobloxScript") => no HUD => Start crashed on ShowHUD nil.
-- Never invoked here: sendServerEvent / fireStageRemote* / SongEvent /
-- startSong / endSong / setSongData / getSongData / remotes / hooks.

if _G.AFNPlayerRan then
    return { aborted = "already-ran-this-session" }
end
_G.AFNPlayerRan = true

local EXP_PLACE = 13042495892
local MOD_NAME = "AFN Custom"
local SONG_NAME = "afn_synth_a_taps"
local DIFF = "Easy"
local CACHED_AUDIO = 30

-- Fixture: 4 taps 1200/1800/2400/3000 lanes 4-7 (matches
-- fixtures/afn_synth_a_taps.chart.json).
local CHART_JSON = [=[{"song":{"song":"afn_synth_a_taps","bpm":200,"keyCount":4,"playerKeyCount":4,"notes":[{"mustHitSection":false,"sectionNotes":[[1200,4,0],[1800,5,0],[2400,6,0],[3000,7,0]]}],"events":[]}}]=]

local rep = { stage = "init", gates = {}, subs = {}, errors = {} }
local function gate(name, ok, extra)
    rep.gates[name] = ok and "pass" or ("FAIL:" .. tostring(extra or ""))
    if not ok then rep.stage = "aborted-preflight" end
    return ok
end

-- ---------- locate engine ----------
local function findFnByLine(line)
    for _, o in ipairs(getgc(true)) do
        if type(o) == "function" then
            local okS, s = pcall(function() return debug.info(o, "s") end)
            if okS and type(s) == "string" and string.find(s, "PlayerScripts", 1, true) then
                local okL, a = pcall(function() return debug.info(o, "l") end)
                if okL and a == line then return o end
            end
        end
    end
    return nil
end

local function upval(f, i)
    local ok, a, b = pcall(function() return debug.getupvalue(f, i) end)
    if not ok then return nil end
    if type(a) == "string" then return b end
    return a
end

local loadSong = findFnByLine(8058)
if not gate("loadSong-found", loadSong ~= nil) then return rep end

local t1, t7, t21
for i = 1, 9 do
    local v = upval(loadSong, i)
    if type(v) == "table" then
        if rawget(v, "SongPlayer") ~= nil then t1 = v
        elseif rawget(v, "loadedSong") ~= nil then t7 = v
        elseif rawget(v, "parseChart") ~= nil then t21 = v end
    end
end
if not gate("upvalues-t1-t7-t21", t1 ~= nil and t7 ~= nil and t21 ~= nil) then return rep end

local okE, env = pcall(function() return getfenv(loadSong) end)
if not gate("getfenv-ok", okE and type(env) == "table") then return rep end
if not gate("env-abruptGameEnd", type(rawget(env, "abruptGameEnd")) == "function") then return rep end
if not gate("env-enterLoadingState", type(rawget(env, "enterLoadingState")) == "function") then return rep end
if not gate("env-leaveLoadingState", type(rawget(env, "leaveLoadingState")) == "function") then return rep end
if not gate("identity-fns", type(getthreadidentity) == "function" and type(setthreadidentity) == "function") then return rep end

-- ---------- preflight (read-only) ----------
if not gate("place", game.PlaceId == EXP_PLACE, game.PlaceId) then return rep end
if not gate("idle-not-loaded", rawget(t7, "loadedSong") == false) then return rep end
if not gate("idle-not-insong", rawget(t7, "inSong") == false) then return rep end
local nf = rawget(t1, "NetworkFunctions")
if not gate("stageRemote-nil", nf ~= nil and rawget(nf, "stageRemote") == nil) then return rep end
if not gate("v963-false", upval(loadSong, 1) == false) then return rep end

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local okD, dm = pcall(function() return require(RS.Modules.Data.DataManager) end)
if not gate("datamanager", okD) then return rep end
local okG, data = pcall(function() return dm:GetData() end)
if not gate("getdata", okG and type(data) == "table") then return rep end
rep.gates["style"] = tostring(data.JudgementStyle)
if not gate("hideLobby-false", data.HideLobby == false, data.HideLobby) then return rep end
if not gate("backgroundDim", (tonumber(data.BackgroundDim) or 0) > 0.05, data.BackgroundDim) then return rep end

local ch = lp.Character
if not gate("character", ch ~= nil) then return rep end
if not gate("descriptionReady", ch:GetAttribute("DescriptionReady") == true) then return rep end

local pg = lp:FindFirstChildOfClass("PlayerGui")
local main = pg and pg:FindFirstChild("Main")
if not gate("main-ui", main ~= nil) then return rep end
local charRemote = main:FindFirstChild("Character")
rep.subs["charRemote-class"] = charRemote and charRemote.ClassName or "nil"

local cont = pg and pg:FindFirstChild("__AssetContainer")
local ratings = cont and cont:FindFirstChild("Ratings")
local afnRatings = ratings and ratings:FindFirstChild("Afternight")
if not gate("ratings-afternight-cached", afnRatings ~= nil) then return rep end
rep.subs["judgementStyle"] = tostring(data.JudgementStyle)

-- pool baseline via the gc module table
local gcMod = nil
for _, v in next, getgc(true) do
    if type(v) == "table" and rawget(v, "parseChart") ~= nil and rawget(v, "addNotesFromChart") ~= nil then
        gcMod = v break
    end
end
if not gate("gc-module", gcMod ~= nil) then return rep end
local function poolCount(t, k)
    local p = rawget(t, k)
    if type(p) ~= "table" then return "n/a:" .. type(p) end
    local n = 0
    for _ in next, p do n += 1 end
    return n
end
rep.pools_before = {
    UnspawnedNotes = poolCount(gcMod, "UnspawnedNotes"),
    Notes = poolCount(gcMod, "Notes"),
    Strums = poolCount(gcMod, "Strums"),
    Strumlines = poolCount(gcMod, "Strumlines"),
}

-- ---------- reversible local substitutions ----------
-- 1. Ratings/<style> clone (cache hit => no RequestEvent).
local styleKey = tostring(data.JudgementStyle)
local ratingsClone = nil
if ratings:FindFirstChild(styleKey) == nil then
    ratingsClone = afnRatings:Clone()
    ratingsClone.Name = styleKey
    ratingsClone.Parent = ratings
    rep.subs["ratings-clone"] = "created"
else
    rep.subs["ratings-clone"] = "already-cached"
end

-- 2. Loading-screen pre-flip (empty Sides => no overhead Invoke later).
-- Full t_234 shape: start() also reads PlayerAmmo/IsSolo/Mod/Song/
-- Difficulty/Rate (decompile: MatchType + SongInfo text).
do
    local okF, errF = pcall(function()
        rawget(env, "enterLoadingState")({
            Sides = { L = {}, R = {} },
            PlayerAmmo = { L = 0, R = 0 },
            IsSolo = false,
            Mod = MOD_NAME,
            Song = SONG_NAME,
            Difficulty = DIFF,
            Rate = 1,
        })
    end)
    rep.subs["loading-preflip"] = okF and "v85=true" or ("FAIL:" .. tostring(errF))
    if not okF then rep.stage = "aborted-subs" end
end

-- 3. Relocate Main.Character remote (char Replicate() nil-guards).
local charRemoteParent = nil
local charTempFolder = nil
if charRemote ~= nil then
    charRemoteParent = charRemote.Parent
    charTempFolder = Instance.new("Folder")
    charTempFolder.Name = "AFNCustom_RemoteHold"
    charTempFolder.Parent = pg
    charRemote.Parent = charTempFolder
    rep.subs["charRemote-moved"] = (main:FindFirstChild("Character") == nil) and "moved" or "MOVE-FAIL"
else
    rep.subs["charRemote-moved"] = "already-nil"
end

-- ---------- engine-call helpers ----------
-- Run game code at LocalScript-level identity; always restore afterwards.
local GAME_IDENTITY = 2
local idBefore = getthreadidentity()
rep.subs["identity-before"] = tostring(idBefore)
local function atGameIdentity(fn)
    local okSet = pcall(function() setthreadidentity(GAME_IDENTITY) end)
    if not okSet then return false, "setthreadidentity failed" end
    local ok, res = xpcall(fn, debug.traceback)
    pcall(function() setthreadidentity(idBefore) end)
    rep.subs["identity-restored"] = (getthreadidentity() == idBefore) and "yes" or "NO"
    return ok, res
end

-- Chart require() wrap state (installed just before loadSong).
local reqPatched, prevReq = false, nil
local function restoreRequire()
    if reqPatched then
        pcall(function() rawset(env, "require", prevReq) end)
        reqPatched = false
    end
end

local function teardown()
    atGameIdentity(function() rawget(env, "abruptGameEnd")() end)
    atGameIdentity(function() rawget(env, "leaveLoadingState")() end)
    restoreRequire()
    if charRemote ~= nil and charRemoteParent ~= nil then
        pcall(function() charRemote.Parent = charRemoteParent end)
    end
    if charTempFolder ~= nil then pcall(function() charTempFolder:Destroy() end) end
    if ratingsClone ~= nil then pcall(function() ratingsClone:Destroy() end) end
    if t1 ~= nil then
        local sid = rawget(t1, "songIds")
        if type(sid) == "table" then pcall(function() sid[MOD_NAME] = nil end) end
    end
    local hold = RS:FindFirstChild("AFNCustom_Play")
    if hold ~= nil then pcall(function() hold:Destroy() end) end
end

if rep.stage == "aborted-subs" then teardown() return rep end

-- ---------- synthesize package ----------
rep.stage = "synth"
local holder = Instance.new("Folder")
holder.Name = "AFNCustom_Play"
holder.Parent = RS

local chartMod = Instance.new("ModuleScript")
chartMod.Name = DIFF
chartMod.Parent = holder
local okSrc, errSrc = pcall(function()
    chartMod.Source = "return " .. "[=[" .. CHART_JSON .. "]=]"
end)
rep.synth_sourceWrite = okSrc and "ok" or ("FAIL:" .. tostring(errSrc))
if not okSrc then teardown() return rep end
pcall(function() chartMod:SetAttribute("_CachedAudio", CACHED_AUDIO) end)

local songInst = Instance.new("Folder")
songInst.Name = SONG_NAME
songInst.Parent = holder
local modInst = Instance.new("Folder")
modInst.Name = MOD_NAME
modInst.Parent = holder

-- require() must return the JSON string
local okReq, reqRes = pcall(function() return require(chartMod) end)
rep.synth_require = okReq and ("string-len=" .. #tostring(reqRes)) or ("FAIL:" .. tostring(reqRes))
if not (okReq and type(reqRes) == "string") then teardown() return rep end
local okJ, decJ = pcall(function()
    return game:GetService("HttpService"):JSONDecode(reqRes)
end)
rep.synth_json = okJ and "decodes" or ("FAIL:" .. tostring(decJ))
if not okJ then teardown() return rep end

-- Serve the chart JSON to the engine's own require() for this one instance.
local okW = pcall(function()
    prevReq = rawget(env, "require")
    local baseReq = prevReq or require
    rawset(env, "require", function(mod)
        if mod == chartMod then return CHART_JSON end
        return baseReq(mod)
    end)
end)
reqPatched = okW and type(rawget(env, "require")) == "function"
rep.subs["require-wrap"] = reqPatched and "installed" or "FAIL"
if not reqPatched then teardown() return rep end

-- registry entry: SkipCountdown=true, NO Audio (audio-free free-run)
rawget(t1, "songIds")[MOD_NAME] = {
    Songs = {
        [SONG_NAME] = { SkipCountdown = true },
    },
    Metadata = {},
}
rep.stage = "loading"

-- ---------- load ----------
local pkg = {
    Chart = chartMod,
    Song = songInst,
    Mod = modInst,
    ModchartsEnabled = false,
    GimmicksEnabled = false,
}
local okL, errL = atGameIdentity(function()
    return loadSong(pkg, "R", 1, nil, { L = {}, R = {} }, 0, { L = {}, R = {} }, nil, nil)
end)
rep.load_ok = okL
rep.load_err = okL and nil or tostring(errL)
rep.load_inSong = rawget(t7, "inSong")
rep.load_songData = (t21 ~= nil and rawget(t21, "songData") ~= nil) and "present" or "missing"
if not okL then
    pcall(function() debug.setupvalue(loadSong, 1, false) end)
    if t7 ~= nil then pcall(function() rawset(t7, "inSong", false) end) end
    if t21 ~= nil then pcall(function() rawset(t21, "inSong", false) end) end
    rep.v963_repaired = upval(loadSong, 1) == false and "yes" or "NO"
    teardown()
    rep.stage = "load-failed-cleaned"
    return rep
end

rep.pools_after_load = {
    UnspawnedNotes = poolCount(gcMod, "UnspawnedNotes"),
    Notes = poolCount(gcMod, "Notes"),
    Strums = poolCount(gcMod, "Strums"),
    Strumlines = poolCount(gcMod, "Strumlines"),
}

-- ---------- start ----------
rep.stage = "starting"
rawset(nf, "stageRemote", nil)
local startFn = rawget(nf, "remoteListen") and rawget(nf, "remoteListen")["Start"]
rep.start_listener = type(startFn)
if type(startFn) ~= "function" then
    teardown()
    rep.stage = "no-start-listener-cleaned"
    return rep
end
local okS, errS = atGameIdentity(function() startFn(0) end)
rep.start_ok = okS
rep.start_err = okS and nil or tostring(errS)
rep.start_loadedSong = rawget(t7, "loadedSong")
if not okS then
    teardown()
    rep.stage = "start-failed-cleaned"
    return rep
end

-- ---------- observe ----------
rep.stage = "observing"
local okC, cond = pcall(function() return require(RS.Modules.Main.Conductor) end)
if okC then
    task.wait(0.5)
    local p0 = cond.SongPosition
    task.wait(2.5)
    local p1 = cond.SongPosition
    rep.conductor_p0 = p0
    rep.conductor_p1 = p1
    rep.conductor_advancing = (type(p0) == "number" and type(p1) == "number" and p1 > p0) and "YES" or "no"
else
    rep.conductor_advancing = "conductor-missing"
end
rep.pools_after_start = {
    UnspawnedNotes = poolCount(gcMod, "UnspawnedNotes"),
    Notes = poolCount(gcMod, "Notes"),
    Strums = poolCount(gcMod, "Strums"),
    Strumlines = poolCount(gcMod, "Strumlines"),
}
-- first unspawned note shape (proves chart content arrived)
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
    local st = rawget(gcMod, "Strums")
    if type(st) == "table" then
        local n = 0
        for _ in next, st do n += 1 end
        rep.strum_total = n
    end
end

-- ---------- teardown ----------
teardown()
rep.stage = "done-cleaned"
rep.teardown_inSong = rawget(t7, "inSong")
rep.teardown_charRemote_restored = (main:FindFirstChild("Character") == charRemote) and "yes" or "NO"
rep.teardown_ratingsClone_gone = (ratings:FindFirstChild(styleKey) == nil or rep.subs["ratings-clone"] == "already-cached") and "yes" or "NO"
rep.teardown_registry_gone = (rawget(t1, "songIds")[MOD_NAME] == nil) and "yes" or "NO"
return rep
