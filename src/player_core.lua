-- AFN player_core: callable local custom-chart play through the real orchestrator.
-- Returns a module table. No UI. No auto-run.
--
-- Player non-invocation boundary (see HANDOFF / ROADMAP): this code does not
-- directly invoke server, score, or persistence APIs and does not hook/block
-- networking. This is NOT a strict network-silence guarantee: engine-internal
-- UpdPreferences/Sync may fire once during loadStageCharacters transitions.
-- Relocating Main.Character and nil-ing stageRemote are mitigations only.
-- Static identifier scans cannot prove that game-engine internals are silent.
--
--   * stage=nil  => v23=false, stageRemote=nil  => fireStageRemote* early-returns
--   * Audio omitted => SongPlayer stays paused => Conductor free-runs.
--     Audio given via opts.audioFile (executor workspace path) =>
--     SongPlayer:load({Instrumental=<Content>, Volume=1}) plays the local
--     file; the Content comes only from getcustomasset (no asset IDs).
--     Stop path is audio-safe: abruptGameEnd -> clearUp(true) tweens down
--     and unloads the SongPlayer ~1s later (decompile 11476-11488).
--   * SkipCountdown=true  => Countdowns asset lookups skipped
--   * Ratings/<JudgementStyle> clone => getAsset cache hit
--   * enterLoadingState pre-flip with empty Sides => no overhead Invoke
--   * Main.Character relocated => CharacterModule Replicate() no-ops
--   * require wrap for our chart ModuleScript only; restored in stop()
--   * loadSong / Start / stop run at thread identity 2
-- Never invoked: sendServerEvent / fireStageRemote* / SongEvent /
-- startSong / setSongData / getSongData / remotes / hooks. endSong IS
-- invoked (one site, user-approved 2026-10-13): the engine has no local
-- end-of-song path (audio end only fires a modchart hook; ending is
-- server-driven), so at the audio clock end we call t21.endSong(true) ->
-- local results screen (createResults, ShowResults=true live, no remotes)
-- + the standard clearUp. No score submission exists in that path.

local EXP_PLACE = 13042495892
local MOD_NAME = "AFN Custom"
local DEFAULT_DIFF = "Easy"
local CACHED_AUDIO = 30
local GAME_IDENTITY = 2

local M = {
    VERSION = "1.3.0",
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

-- Locator scan with retries: getgc/debug.info enumeration has missed once
-- live (single loadSong-found FAIL with an idle engine; the immediate retry
-- passed every gate). Retries only repeat reads; preflight stays read-only.
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

-- SongPlayer instance (v90), read-only via clearUp's upvalues. Nil-tolerant:
-- without it there is simply no song-end detection (Stop-only, as before).
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

local function gate(rep, name, ok, extra)
    rep.gates[name] = ok and "pass" or ("FAIL:" .. tostring(extra or ""))
    if not ok then rep.stage = "aborted-preflight" end
    return ok
end

local function atGameIdentity(idBefore, fn)
    local okSet = pcall(function() setthreadidentity(GAME_IDENTITY) end)
    if not okSet then return false, "setthreadidentity failed" end
    local ok, res = xpcall(fn, debug.traceback)
    local okRestore, restoreErr = pcall(function() setthreadidentity(idBefore) end)
    if not okRestore then return false, "thread identity restore failed: " .. tostring(restoreErr) end
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

local function doTeardown(c)
    if type(c) ~= "table" then
        return { ok = false, error = "missing cleanup context" }
    end
    local idBefore = c.idBefore or (type(getthreadidentity) == "function" and getthreadidentity() or 2)
    c.cleanupDone = c.cleanupDone or {}
    c.teardownReport = c.teardownReport or {}
    local report = c.teardownReport

    -- A successful step is remembered across retries. Failed steps remain
    -- retryable; one failure must not prevent the other resources being restored.
    local function step(name, fn)
        if c.cleanupDone[name] then
            report[name] = "ok (already completed)"
            return true
        end
        local ok, err = pcall(fn)
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
            local fn = type(c.env) == "table" and rawget(c.env, "abruptGameEnd") or nil
            if type(fn) ~= "function" then error("abruptGameEnd unavailable during cleanup") end
            local ok, err = atGameIdentity(idBefore, function() fn() end)
            if not ok then error(err) end
        end
    end)
    step("leaveLoadingState", function()
        if c.loadingStateTouched then
            local fn = type(c.env) == "table" and rawget(c.env, "leaveLoadingState") or nil
            if type(fn) ~= "function" then error("leaveLoadingState unavailable during cleanup") end
            local ok, err = atGameIdentity(idBefore, function() fn() end)
            if not ok then error(err) end
        end
    end)

    -- clearUp is not consistently enough to restore a reusable idle engine.
    -- Reset module flags and wipe the engine-owned pools in place. This is a
    -- best-effort recovery path; a live same-session replay test is still needed.
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
        report["idle-flags-detail"] = string.format(
            "loadedSong=%s, inSong=%s, moduleInSong=%s, songData=%s",
            tostring(rawget(c.t7, "loadedSong")),
            tostring(rawget(c.t7, "inSong")),
            tostring(rawget(c.t21, "inSong")),
            tostring(rawget(c.t21, "songData"))
        )
    end)
    step("pools-notes", function()
        if type(c.gcMod) ~= "table" then error("gameplay pools unavailable") end
        local details = {}
        for _, name in ipairs({ "Notes", "UnspawnedNotes" }) do
            local pool = rawget(c.gcMod, name)
            if type(pool) ~= "table" then error(name .. " pool is not a table") end
            local before = poolCount(c.gcMod, name)
            for key in next, pool do rawset(pool, key, nil) end
            local after = poolCount(c.gcMod, name)
            details[#details + 1] = name .. ":" .. tostring(before) .. "->" .. tostring(after)
            if after ~= 0 then error(name .. " pool is not empty after wipe") end
        end
        report["pools-notes-detail"] = table.concat(details, ", ")
    end)
    step("pools-strums", function()
        local details = {}
        if type(c.gcMod) == "table" then
            for _, name in ipairs({ "Strums", "Strumlines" }) do
                local pool = rawget(c.gcMod, name)
                local before = poolCount(c.gcMod, name)
                -- Best-effort only: do not guess undocumented Instance destroy APIs.
                if type(pool) == "table" then
                    for key in next, pool do rawset(pool, key, nil) end
                end
                local after = poolCount(c.gcMod, name)
                details[#details + 1] = name .. ":" .. tostring(before) .. "->" .. tostring(after)
            end
        else
            details[#details + 1] = "gameplay module unavailable"
        end
        report["pools-strums-detail"] = table.concat(details, ", ")
    end)
    local function cleanupStepOk(name)
        local status = report[name]
        return type(status) == "string" and status:sub(1, 2) == "ok"
    end
    report.forceIdle = (cleanupStepOk("idle-flags")
        and cleanupStepOk("pools-notes")
        and cleanupStepOk("pools-strums")) and "ok" or "FAIL: forceIdle substep failed"
    step("autoplay", function()
        if c.autoplaySet then
            local apFn = type(c.t21) == "table" and rawget(c.t21, "SetAutoplay") or nil
            if type(apFn) ~= "function" then error("autoplay setter unavailable") end
            local ok, err = atGameIdentity(c.idBefore, function() apFn(false) end)
            if not ok then error(err) end
            c.autoplaySet = false
        end
    end)
    step("require", function()
        if c.reqPatched then
            if type(c.env) ~= "table" then error("require environment unavailable") end
            rawset(c.env, "require", c.prevReq)
            if rawget(c.env, "require") ~= c.prevReq then error("require environment was not restored") end
            c.reqPatched = false
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

    local allOk = true
    for _, status in next, report do
        if type(status) == "string" and status:sub(1, 5) == "FAIL:" then
            allOk = false
        end
    end
    report.ok = allOk
    return report
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
    if c and (c.phase == "preparing" or c.phase == "finishing") then
        rep.stage = "busy-initializing"
        rep.ok = false
        rep.err = "Wait for startup to return, then retry Stop"
        M.lastReport = rep
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
    if c and c.t7 then
        rep.teardown_inSong = rawget(c.t7, "inSong")
    end
    if c and c.main and c.charRemote then
        rep.teardown_charRemote_restored = (c.main:FindFirstChild("Character") == c.charRemote) and "yes" or "NO"
    end
    if c and c.t1 then
        local sid = rawget(c.t1, "songIds")
        -- Restoration success = current entry matches what was there before play
        -- (nil when we injected into an empty slot; prior table when we overwrote).
        rep.teardown_registry_restored = type(sid) == "table"
            and sid[MOD_NAME] == c.previousSongEntry and "yes" or "NO"
    end
    -- Retain the context when any cleanup failed so a later Stop can retry.
    if rep.ok then
        ctx = nil
        M.playing = false
        rep.stage = "stopped"
    else
        rep.stage = "cleanup-incomplete"
        M.playing = true
    end
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

    local loadSong, attempts = findFnByLine(8058)
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
    -- Non-zero pools after Stop indicate cleanup needs attention. Stop retries
    -- forceIdle; only rejoin if cleanup remains incomplete after retrying.
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

--   opts:
--     chartJson | wrapper | chart  (string JSON / table)
--     songName (optional override)
--     diff (optional, default Easy)
--     audioFile (optional executor-workspace path, e.g.
--       "AfternightCustomSongs/Audio/x.mp3"): resolved live via
--       Content.fromUri(getcustomasset(path)) into the registry
--       Audio entry. Omit for the audio-free free-run.
--     autoplay (bool, ONE-TIME TEST ONLY, user-authorized 2026-10-13):
--       engine's own botplay flag via t21.SetAutoplay(true); reset to
--       false in teardown so it never leaks into the next play.
--     keepAlive (bool) if true, leave song running until M.stop()
--     observeSeconds (number, default 3 when not keepAlive)
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
        env = env, t1 = t1, t7 = t7, t21 = t21, nf = nf, gcMod = gcMod,
        main = main, charRemote = charRemote, idBefore = idBefore,
        reqPatched = false, prevReq = nil,
        ratingsClone = nil, charTempFolder = nil, charRemoteParent = nil,
        cleanupDone = {}, teardownReport = {}, holder = nil,
        previousSongEntry = rawget(rawget(t1, "songIds"), MOD_NAME),
        registryTouched = false, loadingStateTouched = false, loadAttempted = false,
        phase = "preparing",
    }

    -- Register cleanup before the first state-changing operation.
    ctx = c
    M.playing = true
    local function abortPlay(report, stage)
        report.stage = stage
        c.phase = "cleaning"
        local stopped = M.stop()
        report.teardown = stopped.cleanup
        report.teardown_ok = stopped.ok
        if not stopped.ok then report.stage = "cleanup-incomplete" end
        return report
    end
    local okTxn, txnResult = xpcall(function()
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
        c.loadingStateTouched = true
        rep.subs["loading-preflip"] = okF and "v85=true" or ("FAIL:" .. tostring(errF))
        if not okF then
            return abortPlay(rep, "aborted-subs")
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
    c.holder = holder
    holder.Parent = RS

    local chartMod = Instance.new("ModuleScript")
    chartMod.Name = diff
    chartMod.Parent = holder
    local okSrc, errSrc = pcall(function()
        -- %q quotes/escapes chartJson as one Luau string literal; never embed
        -- untrusted JSON inside a fixed long-bracket delimiter.
        chartMod.Source = "return " .. string.format("%q", chartJson)
    end)
    rep.synth_sourceWrite = okSrc and "ok" or ("FAIL:" .. tostring(errSrc))
    if not okSrc then
        return abortPlay(rep, "synth-failed")
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
        return abortPlay(rep, "synth-require-failed")
    end
    local okJ, decJ = pcall(function()
        return game:GetService("HttpService"):JSONDecode(reqRes)
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
            return baseReq(mod)
        end)
    end)
    c.reqPatched = okW and type(rawget(env, "require")) == "function"
    rep.subs["require-wrap"] = c.reqPatched and "installed" or "FAIL"
    if not c.reqPatched then
        return abortPlay(rep, "require-wrap-failed")
    end

    c.registryTouched = true
    local songEntry = { SkipCountdown = true }
    if opts.audioFile ~= nil then
        local audioPath = tostring(opts.audioFile)
        rep.audioFile = audioPath
        local okA, content = pcall(function()
            if type(getcustomasset) ~= "function" then
                error("getcustomasset unavailable")
            end
            return Content.fromUri(getcustomasset(audioPath))
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
        Songs = { [songName] = songEntry },
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

    -- start
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

    -- One-time test autoplay: engine's own botplay flag, reset in teardown.
    if opts.autoplay then
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
        local getAp = rawget(t21, "GetAutoplay")
        if type(getAp) == "function" then
            local okG, st = pcall(function() return getAp() end)
            rep.autoplay_state = okG and tostring(st) or ("FAIL:" .. tostring(st))
        end
    else
        rep.subs["autoplay"] = "off(manual)"
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

    c.phase = "playing"

    if opts.keepAlive then
        rep.stage = "playing"
        -- Song-end watcher: at the audio clock end, run the engine's own
        -- endSong(true) for the local results screen, then wait for the
        -- user's Stop (results stay up until teardown). Audio-free plays
        -- have no clock end (timeLength stays -1): Stop-only, as before.
        task.spawn(function()
            while ctx == c and M.playing and c.phase == "playing" do
                task.wait(0.5)
                if ctx ~= c or not M.playing or c.phase ~= "playing" then break end
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
                        if okE then
                            rep.finish_err = nil
                        else
                            rep.finish_err = tostring(errE)
                        end
                        if okE then
                            c.phase = "ended"
                            rep.stage = "ended-results"
                        else
                            c.phase = "cleaning"
                            local stopRep = M.stop()
                            rep.teardown = stopRep.cleanup
                            rep.teardown_ok = stopRep.ok
                            rep.stage = "ended-fallback-stop"
                        end
                        break
                    end
                end
            end
        end)
        M.lastReport = rep
        return rep
    end

    -- observe then stop (smoke path)
    rep.stage = "observing"
    local observe = tonumber(opts.observeSeconds) or 3
    -- Errors during observation also reach the transaction's rollback handler.
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
    rep.stage = stopRep.ok and "done-cleaned" or "cleanup-incomplete"
    rep.teardown_inSong = stopRep.teardown_inSong
    rep.teardown_charRemote_restored = stopRep.teardown_charRemote_restored
    rep.teardown_registry_restored = stopRep.teardown_registry_restored
    rep.teardown = stopRep.cleanup
    M.lastReport = rep
    return rep
    end, debug.traceback)

    if not okTxn then
        rep.stage = "unexpected-error"
        rep.err = tostring(txnResult)
        c.phase = "cleaning"
        local stopRep = M.stop()
        rep.teardown = stopRep.cleanup
        rep.teardown_ok = stopRep.ok
        if not stopRep.ok then rep.stage = "cleanup-incomplete" end
        M.lastReport = rep
        return rep
    end
    M.lastReport = txnResult
    return txnResult
end

return M
