-- Probe F (Afternight spike): chart-path function metadata preflight.
-- READ-ONLY: never calls any game function. Checks for introspection
-- primitives, then reads arity/constants/upvalues of the chart-input and
-- playback functions ONLY (parseChart, setSongData, getSongData,
-- addNotesFromChart, addSectionsFromChart, createNote, createStrumline,
-- setNoteSpawnTime, startSong, endSong, cancelSongStart). Output capped.
-- Anything inaccessible is reported as unknown, never guessed.
local MAXC = 60

local function has(name)
    if type(_G[name]) == "function" then return true end
    if type(getfenv) == "function" then
        local ok, env = pcall(function() return getfenv(0) end)
        if ok and type(env) == "table" and type(env[name]) == "function" then
            return true
        end
    end
    return false
end

local out = { introspect = {} }
for _, n in ipairs({ "getupvalues", "getconstants", "getinfo", "debug" }) do
    out.introspect[n] = has(n)
end
local dbg = nil
if type(debug) == "table" and type(rawget(debug, "getinfo")) == "function" then
    dbg = rawget(debug, "getinfo")
end

local function gameMod()
    for _, v in next, getgc(true) do
        if type(v) == "table" and type(rawget(v, "addNotesFromChart")) == "function" then
            return v
        end
    end
    return nil
end

local mod = gameMod()
if mod == nil then
    out.found = false
    return out
end
out.found = true
out.functions = {}

local targets = { "parseChart", "setSongData", "getSongData", "addNotesFromChart",
    "addSectionsFromChart", "createNote", "createStrumline", "setNoteSpawnTime",
    "startSong", "endSong", "cancelSongStart" }
for _, name in ipairs(targets) do
    local entry = { present = false }
    local ok, fn = pcall(function() return rawget(mod, name) end)
    if ok and type(fn) == "function" then
        entry.present = true
        if dbg ~= nil then
            local okI, info = pcall(dbg, fn)
            if okI and type(info) == "table" then
                entry.nparams = info.nparams
                entry.isvararg = info.isvararg
            end
        end
        if has("getconstants") then
            local okC, consts = pcall(function() return getconstants(fn) end)
            if okC and type(consts) == "table" then
                local kept = {}
                for _, c in next, consts do
                    if #kept >= MAXC then break end
                    if type(c) == "string" then table.insert(kept, c) end
                end
                table.sort(kept)
                entry.constants = kept
            end
        end
        if has("getupvalues") then
            local okU, ups = pcall(function() return getupvalues(fn) end)
            if okU and type(ups) == "table" then
                local names = {}
                for k, _ in next, ups do
                    if #names >= MAXC then break end
                    table.insert(names, tostring(k))
                end
                table.sort(names)
                entry.upvalues = names
            end
        end
    end
    out.functions[name] = entry
end
return out
