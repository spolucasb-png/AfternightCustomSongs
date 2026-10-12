-- Probe S (Afternight spike): playback status snapshot. READ-ONLY, zero calls
-- into gameplay methods (only rawget walks + counting). Tells whether a song
-- is loaded/playing and what the clock says.
local function gameMod()
    for _, v in next, getgc(true) do
        if type(v) == "table" and type(rawget(v, "addNotesFromChart")) == "function" then
            return v
        end
    end
    return nil
end

local out = { placeId = game.PlaceId }
local mod = gameMod()
if mod == nil then
    out.found = false
    return out
end
out.found = true
local function count(t)
    local n = 0
    if type(t) == "table" then
        for _ in next, t do n += 1 end
    end
    return n
end
local okC, con = pcall(function() return rawget(mod, "Conductor") end)
if okC and type(con) == "table" then
    out.conductor = {}
    for _, k in ipairs({ "SongPosition", "TimePosition", "Paused", "BPM", "CurBPM", "Offset" }) do
        local ok, v = pcall(function() return rawget(con, k) end)
        if ok and (type(v) == "number" or type(v) == "boolean") then
            out.conductor[k] = v
        end
    end
end
local okS, sp = pcall(function() return rawget(mod, "songPlayer") end)
if okS and type(sp) == "table" then
    out.songPlayer = {}
    for _, k in ipairs({ "timePosition", "timeLength", "paused" }) do
        local ok, v = pcall(function() return rawget(sp, k) end)
        if ok and (type(v) == "number" or type(v) == "boolean") then
            out.songPlayer[k] = v
        end
    end
end
local okN, nn = pcall(function() return rawget(mod, "Notes") end)
out.notes = (okN and count(nn)) or -1
local okU, uu = pcall(function() return rawget(mod, "UnspawnedNotes") end)
out.unspawned = (okU and count(uu)) or -1
return out
