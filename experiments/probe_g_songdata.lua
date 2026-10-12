-- Probe G (AfternightCustomSongs): populated map data + getSongData check.
-- getSongData() is invoked ONCE inside pcall with a pre/post state snapshot
-- (pools, clock, SV count) to prove the read did not mutate anything. If the
-- call errors or the snapshots differ, the returned shape is distrusted.
-- Map registry entries are dumped read-only (key inventory, capped).
local MAXE = 12

local function gameMod()
    for _, v in next, getgc(true) do
        if type(v) == "table" and type(rawget(v, "addNotesFromChart")) == "function" then
            return v
        end
    end
    return nil
end

local function count(t)
    local n = 0
    if type(t) == "table" then
        for _ in next, t do n += 1 end
    end
    return n
end

local function snap(mod)
    local s = {}
    local okN, nn = pcall(function() return rawget(mod, "Notes") end)
    s.notes = (okN and count(nn)) or -1
    local okU, uu = pcall(function() return rawget(mod, "UnspawnedNotes") end)
    s.unspawned = (okU and count(uu)) or -1
    local okC, con = pcall(function() return rawget(mod, "Conductor") end)
    if okC and type(con) == "table" then
        local okT, tp = pcall(function() return rawget(con, "TimePosition") end)
        if okT and type(tp) == "number" then s.t = tp end
    end
    local okS, sv = pcall(function() return rawget(mod, "svFunctions") end)
    if okS and type(sv) == "table" then
        local okV, sl = pcall(function() return rawget(sv, "sliderVelocities") end)
        s.sv = (okV and count(sl)) or -1
    end
    return s
end

local function keyinv(t, cap)
    local out = {}
    for k, v in next, t do
        if #out >= (cap or MAXE) then break end
        local vt = type(v)
        if vt == "number" or vt == "string" or vt == "boolean" then
            table.insert(out, tostring(k) .. "=" .. tostring(v))
        else
            table.insert(out, tostring(k) .. ":" .. vt)
        end
    end
    table.sort(out)
    return out
end

local mod = gameMod()
if mod == nil then return { found = false } end
local out = { found = true }

local okM, mm = pcall(function() return rawget(mod, "mapModule") end)
if okM and type(mm) == "table" then
    local okMs, ms = pcall(function() return rawget(mm, "Maps") end)
    if okMs and type(ms) == "table" then
        out.maps = { count = count(ms), entries = {} }
        for k, v in next, ms do
            if #out.maps.entries >= 4 then break end
            if type(v) == "table" then
                table.insert(out.maps.entries, { key = tostring(k), shape = keyinv(v, 15) })
            else
                table.insert(out.maps.entries, { key = tostring(k), shape = type(v) })
            end
        end
    end
end

out.pre = snap(mod)
local okG, gd = pcall(function()
    local fn = rawget(mod, "getSongData")
    if type(fn) ~= "function" then return nil end
    return fn()
end)
out.getSongData = { ok = okG }
if okG and type(gd) == "table" then
    out.getSongData.shape = keyinv(gd, 20)
    local okN2, nn2 = pcall(function() return rawget(gd, "notes") end)
    if okN2 and type(nn2) == "table" then
        out.getSongData.notesCount = count(nn2)
        for _, sec in next, nn2 do
            if type(sec) == "table" then
                out.getSongData.sectionShape = keyinv(sec, 20)
                break
            end
        end
    end
elseif okG then
    out.getSongData.value = tostring(gd)
end
out.post = snap(mod)
return out
