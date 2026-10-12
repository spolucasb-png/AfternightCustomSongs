-- AFN player_core: callable local custom-chart play through the real orchestrator.
-- Returns a module table. No UI. No auto-run.
--
-- Local-only design (see HANDOFF session 4 / ROADMAP item 7):
--   * stage=nil  => v23=false, stageRemote=nil  => fireStageRemote* early-returns
--   * Audio omitted => SongPlayer stays paused => Conductor free-runs
--   * SkipCountdown=true  => Countdowns asset lookups skipped
--   * Ratings/<JudgementStyle> clone => getAsset cache hit
--   * enterLoadingState pre-flip with empty Sides => no overhead Invoke
--   * Main.Character relocated => CharacterModule Replicate() no-ops
--   * require wrap for our chart ModuleScript only; restored in stop()
--   * loadSong / Start / stop run at thread identity 2
-- Never invoked: sendServerEvent / fireStageRemote* / SongEvent /
-- startSong / endSong / setSongData / getSongData / remotes / hooks.

local EXP_PLACE = 13042495892
local MOD_NAME = "AFN Custom"
local DEFAULT_DIFF = "Easy"
local CACHED_AUDIO = 30
local GAME_IDENTITY = 2

local M = {
    VERSION = "1.1.0",
    playing = false,
    lastReport = nil,
}

local ctx = nil -- live play context (teardown handles)

local function poolCount(t, k)
    local p = rawget(t, k)
    if type(p) ~= "table" then return "n/a:" .. type(p) end
    local n = 0
    for _ in next, p do n += 1 end
    return n
end

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

local function gate(rep, name, ok, extra)
    rep.gates[name] = ok and "pass" or ("FAIL:" .. tostring(extra or ""))
    if not ok then rep.stage = "aborted-preflight" end
    return ok
end

local function atGameIdentity(idBefore, fn)
    local okSet = pcall(function() setthreadidentity(GAME_IDENTITY) end)
    if not okSet then return false, "setthreadidentity failed" end
    local ok, res = xpcall(fn, debug.traceback)
    pcall(function() setthreadidentity(idBefore) end)
    return ok, res
end

local function encodeWrapper(wrapper)
    local HS = game:GetService("HttpService")
    return HS:JSONEncode(wrapper)
end

-- Normalize accepted chart shapes into engine wrapper JSON string + song name.
function M.normalizeChart(input)
    if type(input) == "string" then
        local HS = game:GetService("HttpService")
        local ok, decoded = pcall(function() return HS:JSONDecode(input) end)
        if not ok or type(decoded) ~= "table" then
            return nil, "chart JSON decode failed: " .. tostring(decoded)
        end
        input = decoded
    end
    if type(input) ~= "table" then
        return nil, "chart must be table or JSON string"
    end

    -- Engine wrapper: { song = { song=..., notes=..., ... } }
    if type(input.song) == "table" and type(input.song.notes) == "table" then
        local name = tostring(input.song.song or "custom")
        return encodeWrapper(input), name, "wrapper"
    end

    -- Flat prototype: { song, bpm, notes=[{time_ms,lane,hold_len}] }
    if type(input.notes) == "table" and (input.time_ms ~= nil or (input.notes[1] and input.notes[1].time_ms ~= nil)) then
        local rows = {}
        for _, n in ipairs(input.notes) do
            if type(n) == "table" and type(n.time_ms) == "number" and type(n.lane) == "number" then
                local lane = math.clamp(math.floor(n.lane), 0, 3) + 4
                rows[#rows + 1] = { n.time_ms, lane, tonumber(n.hold_len) or 0 }
            end
        end
        if #rows == 0 then return nil, "flat chart has no convertible notes" end
        local name = tostring(input.song or "flat_chart")
        local wrapper = {
            song = {
                song = name,
                bpm = tonumber(input.bpm) or 120,
                keyCount = 4,
                playerKeyCount = 4,
                notes = { { mustHitSection = false, sectionNotes = rows } },
                events = {},
            },
        }
        return encodeWrapper(wrapper), name, "flat"
    end

    return nil, "unrecognized chart shape (need wrapper.song.notes or flat notes[])"
end

local function restoreRequire(env, prevReq, reqPatched)
    if reqPatched and type(env) == "table" then
        pcall(function() rawset(env, "require", prevReq) end)
    end
end

local function doTeardown(c)
    if type(c) ~= "table" then return end
    local idBefore = c.idBefore or (type(getthreadidentity) == "function" and getthreadidentity() or 2)
    if type(c.env) == "table" then
        if type(rawget(c.env, "abruptGameEnd")) == "function" then
            atGameIdentity(idBefore, function() rawget(c.env, "abruptGameEnd")() end)
        end
        if type(rawget(c.env, "leaveLoadingState")) == "function" then
            atGameIdentity(idBefore, function() rawget(c.env, "leaveLoadingState")() end)
        end
        restoreRequire(c.env, c.prevReq, c.reqPatched)
    end
    if c.charRemote ~= nil and c.charRemoteParent ~= nil then
        pcall(function() c.charRemote.Parent = c.charRemoteParent end)
    end
    if c.charTempFolder ~= nil then pcall(function() c.charTempFolder:Destroy() end) end
    if c.ratingsClone ~= nil then pcall(function() c.ratingsClone:Destroy() end) end
    if c.t1 ~= nil then
        local sid = rawget(c.t1, "songIds")
        if type(sid) == "table" then pcall(function() sid[MOD_NAME] = nil end) end
    end
    local RS = game:GetService("ReplicatedStorage")
    local hold = RS:FindFirstChild("AFNCustom_Play")
    if hold ~= nil then pcall(function() hold:Destroy() end) end
end

function M.stop()
    local rep = { stage = "stop", ok = false }
    if not M.playing and ctx == nil then
        rep.stage = "idle"
        rep.ok = true
        M.lastReport = rep
        return rep
    end
    local c = ctx
    ctx = nil
    M.playing = false
    local ok, err = pcall(function() doTeardown(c) end)
    rep.ok = ok
    rep.err = ok and nil or tostring(err)
    if c and c.t7 then
        rep.teardown_inSong = rawget(c.t7, "inSong")
    end
    if c and c.main and c.charRemote then
        rep.teardown_charRemote_restored = (c.main:FindFirstChild("Character") == c.charRemote) and "yes" or "NO"
    end
    if c and c.t1 then
        rep.teardown_registry_gone = (rawget(c.t1, "songIds")[MOD_NAME] == nil) and "yes" or "NO"
    end
    rep.stage = "stopped"
    M.lastReport = rep
    return rep
end

-- Read-only preflight. Does not mutate game state.
function M.preflight()
    local rep = { stage = "preflight", gates = {}, errors = {} }
    if M.playing then
        gate(rep, "not-playing", false, "already playing; Stop first")
        return false, rep
    end
    if type(getgc) ~= "function" then
        gate(rep, "getgc", false, "missing")
        return false, rep
    end
    if type(getthreadidentity) ~= "function" or type(setthreadidentity) ~= "function" then
        gate(rep, "identity-fns", false, "missing")
        return false, rep
    end
    if not gate(rep, "place", game.PlaceId == EXP_PLACE, game.PlaceId) then
        return false, rep
    end

    local loadSong = findFnByLine(8058)
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
    if not gate(rep, "v963-false", upval(loadSong, 1) == false) then return false, rep end

    local RS = game:GetService("ReplicatedStorage")
    local Players = game:GetService("Players")
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
    -- Residue after a prior custom play: Strums/Strumlines persist. Refuse.
    local su = rep.pools.Strums
    local sl = rep.pools.Strumlines
    if (type(su) == "number" and su > 0) or (type(sl) == "number" and sl > 0) then
        gate(rep, "clean-strum-residue", false, "Strums/Strumlines non-zero; rejoin first")
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

--[[
  opts:
    chartJson | wrapper | chart  (string JSON / table)
    songName (optional override)
    diff (optional, default Easy)
    keepAlive (bool) if true, leave song running until M.stop()
    observeSeconds (number, default 3 when not keepAlive)
]]
function M.play(opts)
    opts = opts or {}
    local rep = { stage = "init", gates = {}, subs = {}, errors = {} }
    M.lastReport = rep

    if M.playing then
        rep.aborted = "already-playing"
        rep.stage = "aborted"
        return rep
    end

    local chartInput = opts.chartJson or opts.wrapper or opts.chart
    if chartInput == nil then
        rep.aborted = "no-chart"
        rep.stage = "aborted"
        return rep
    end
    local chartJson, songName, shape = M.normalizeChart(chartInput)
    if not chartJson then
        rep.aborted = tostring(songName)
        rep.stage = "aborted-normalize"
        return rep
    end
    songName = opts.songName or songName
    local diff = tostring(opts.diff or DEFAULT_DIFF)
    rep.chart_shape = shape
    rep.songName = songName
    rep.diff = diff

    local okPf, pf = M.preflight()
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
        env = env, t1 = t1, t7 = t7, t21 = t21, nf = nf,
        main = main, charRemote = charRemote, idBefore = idBefore,
        reqPatched = false, prevReq = nil,
        ratingsClone = nil, charTempFolder = nil, charRemoteParent = nil,
    }

    -- 1. Ratings clone
    local styleKey = tostring(data.JudgementStyle)
    if ratings:FindFirstChild(styleKey) == nil then
        c.ratingsClone = afnRatings:Clone()
        c.ratingsClone.Name = styleKey
        c.ratingsClone.Parent = ratings
        rep.subs["ratings-clone"] = "created"
    else
        rep.subs["ratings-clone"] = "already-cached"
    end

    -- 2. Loading pre-flip
    do
        local okF, errF = pcall(function()
            rawget(env, "enterLoadingState")({
                Sides = { L = {}, R = {} },
                PlayerAmmo = { L = 0, R = 0 },
                IsSolo = false,
                Mod = MOD_NAME,
                Song = songName,
                Difficulty = diff,
                Rate = 1,
            })
        end)
        rep.subs["loading-preflip"] = okF and "v85=true" or ("FAIL:" .. tostring(errF))
        if not okF then
            doTeardown(c)
            rep.stage = "aborted-subs"
            return rep
        end
    end

    -- 3. Relocate Character remote
    if charRemote ~= nil then
        c.charRemoteParent = charRemote.Parent
        c.charTempFolder = Instance.new("Folder")
        c.charTempFolder.Name = "AFNCustom_RemoteHold"
        c.charTempFolder.Parent = pg
        charRemote.Parent = c.charTempFolder
        rep.subs["charRemote-moved"] = (main:FindFirstChild("Character") == nil) and "moved" or "MOVE-FAIL"
    else
        rep.subs["charRemote-moved"] = "already-nil"
    end

    -- Synthesize package
    rep.stage = "synth"
    local RS = game:GetService("ReplicatedStorage")
    local old = RS:FindFirstChild("AFNCustom_Play")
    if old then pcall(function() old:Destroy() end) end
    local holder = Instance.new("Folder")
    holder.Name = "AFNCustom_Play"
    holder.Parent = RS

    local chartMod = Instance.new("ModuleScript")
    chartMod.Name = diff
    chartMod.Parent = holder
    local okSrc, errSrc = pcall(function()
        chartMod.Source = "return " .. "[=[" .. chartJson .. "]=]"
    end)
    rep.synth_sourceWrite = okSrc and "ok" or ("FAIL:" .. tostring(errSrc))
    if not okSrc then
        doTeardown(c)
        rep.stage = "synth-failed"
        return rep
    end
    pcall(function() chartMod:SetAttribute("_CachedAudio", CACHED_AUDIO) end)

    local songInst = Instance.new("Folder")
    songInst.Name = songName
    songInst.Parent = holder
    local modInst = Instance.new("Folder")
    modInst.Name = MOD_NAME
    modInst.Parent = holder

    local okReq, reqRes = pcall(function() return require(chartMod) end)
    rep.synth_require = okReq and ("string-len=" .. #tostring(reqRes)) or ("FAIL:" .. tostring(reqRes))
    if not (okReq and type(reqRes) == "string") then
        doTeardown(c)
        rep.stage = "synth-require-failed"
        return rep
    end
    local okJ, decJ = pcall(function()
        return game:GetService("HttpService"):JSONDecode(reqRes)
    end)
    rep.synth_json = okJ and "decodes" or ("FAIL:" .. tostring(decJ))
    if not okJ then
        doTeardown(c)
        rep.stage = "synth-json-failed"
        return rep
    end

    local okW = pcall(function()
        c.prevReq = rawget(env, "require")
        local baseReq = c.prevReq or require
        rawset(env, "require", function(mod)
            if mod == chartMod then return chartJson end
            return baseReq(mod)
        end)
    end)
    c.reqPatched = okW and type(rawget(env, "require")) == "function"
    rep.subs["require-wrap"] = c.reqPatched and "installed" or "FAIL"
    if not c.reqPatched then
        doTeardown(c)
        rep.stage = "require-wrap-failed"
        return rep
    end

    rawget(t1, "songIds")[MOD_NAME] = {
        Songs = { [songName] = { SkipCountdown = true } },
        Metadata = {},
    }

    -- load
    rep.stage = "loading"
    local pkg = {
        Chart = chartMod,
        Song = songInst,
        Mod = modInst,
        ModchartsEnabled = false,
        GimmicksEnabled = false,
    }
    local okL, errL = atGameIdentity(idBefore, function()
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
        doTeardown(c)
        rep.stage = "load-failed-cleaned"
        return rep
    end
    rep.pools_after_load = {
        UnspawnedNotes = poolCount(gcMod, "UnspawnedNotes"),
        Notes = poolCount(gcMod, "Notes"),
        Strums = poolCount(gcMod, "Strums"),
        Strumlines = poolCount(gcMod, "Strumlines"),
    }

    -- start
    rep.stage = "starting"
    rawset(nf, "stageRemote", nil)
    local startFn = rawget(nf, "remoteListen") and rawget(nf, "remoteListen")["Start"]
    rep.start_listener = type(startFn)
    if type(startFn) ~= "function" then
        doTeardown(c)
        rep.stage = "no-start-listener-cleaned"
        return rep
    end
    local okS, errS = atGameIdentity(idBefore, function() startFn(0) end)
    rep.start_ok = okS
    rep.start_err = okS and nil or tostring(errS)
    rep.start_loadedSong = rawget(t7, "loadedSong")
    if not okS then
        doTeardown(c)
        rep.stage = "start-failed-cleaned"
        return rep
    end

    -- sample one note
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

    ctx = c
    M.playing = true

    if opts.keepAlive then
        rep.stage = "playing"
        M.lastReport = rep
        return rep
    end

    -- observe then stop (smoke path)
    rep.stage = "observing"
    local observe = tonumber(opts.observeSeconds) or 3
    local okC, cond = pcall(function() return require(game:GetService("ReplicatedStorage").Modules.Main.Conductor) end)
    if okC then
        task.wait(math.min(0.5, observe))
        local p0 = cond.SongPosition
        task.wait(math.max(0, observe - 0.5))
        local p1 = cond.SongPosition
        rep.conductor_p0 = p0
        rep.conductor_p1 = p1
        rep.conductor_advancing = (type(p0) == "number" and type(p1) == "number" and p1 > p0) and "YES" or "no"
    else
        task.wait(observe)
        rep.conductor_advancing = "conductor-missing"
    end
    rep.pools_after_start = {
        UnspawnedNotes = poolCount(gcMod, "UnspawnedNotes"),
        Notes = poolCount(gcMod, "Notes"),
        Strums = poolCount(gcMod, "Strums"),
        Strumlines = poolCount(gcMod, "Strumlines"),
    }

    local stopRep = M.stop()
    rep.stage = "done-cleaned"
    rep.teardown_inSong = stopRep.teardown_inSong
    rep.teardown_charRemote_restored = stopRep.teardown_charRemote_restored
    rep.teardown_registry_gone = stopRep.teardown_registry_gone
    M.lastReport = rep
    return rep
end

return M
