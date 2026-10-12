-- Probe T (Afternight spike): SV entries + BPM-map contents. READ-ONLY,
-- zero gameplay calls. Dumps svFunctions.sliderVelocities entries,
// Conductor BPM fields + BPMChangeMap entries, and lastBPMChange — all
-- scalar dumps, capped. Repeated runs show whether they move in playback.
local MAXE = 8

local function gameMod()
    for _, v in next, getgc(true) do
        if type(v) == "table" and type(rawget(v, "addNotesFromChart")) == "function" then
            return v
        end
    end
    return nil
end

local function dumpEntries(t, cap)
    local out = {}
    if type(t) ~= "table" then return out end
    for k, v in next, t do
        if #out >= (cap or MAXE) then break end
        local ks = tostring(k)
        local vt = type(v)
        if vt == "number" or vt == "string" or vt == "boolean" then
            table.insert(out, ks .. "=" .. tostring(v))
        elseif vt == "table" then
            local inner = {}
            for k2, v2 in next, v do
                if #inner >= 6 then break end
                local v2t = type(v2)
                if v2t == "number" or v2t == "string" or v2t == "boolean" then
                    table.insert(inner, tostring(k2) .. "=" .. tostring(v2))
                else
                    table.insert(inner, tostring(k2) .. ":" .. v2t)
                end
            end
            table.sort(inner)
            table.insert(out, ks .. "={" .. table.concat(inner, ",") .. "}")
        else
            table.insert(out, ks .. ":" .. vt)
        end
    end
    table.sort(out)
    return out
end

local function count(t)
    local n = 0
    if type(t) == "table" then
        for _ in next, t do n += 1 end
    end
    return n
end

local mod = gameMod()
if mod == nil then return { found = false } end
local out = { found = true }
local okC, con = pcall(function() return rawget(mod, "Conductor") end)
if okC and type(con) == "table" then
    out.con = {}
    for _, k in ipairs({ "BPM", "BaseBPM", "CurBPM", "Offset", "Crochet",
                         "StepCrochet", "BeatsPerMeasure", "StepsPerBeat",
                         "SongPosition", "TimePosition" }) do
        local ok, v = pcall(function() return rawget(con, k) end)
        if ok and (type(v) == "number" or type(v) == "boolean") then
            out.con[k] = v
        end
    end
    local okB, bm = pcall(function() return rawget(con, "BPMChangeMap") end)
    out.bpmChangeCount = (okB and count(bm)) or -1
    out.bpmChangeEntries = dumpEntries(bm, MAXE)
end
local okL, lb = pcall(function() return rawget(mod, "lastBPMChange") end)
if okL then
    if type(lb) == "table" then out.lastBPMChange = dumpEntries(lb, 6)
    else out.lastBPMChange = tostring(lb) end
end
local okS, sv = pcall(function() return rawget(mod, "svFunctions") end)
if okS and type(sv) == "table" then
    local okV, sl = pcall(function() return rawget(sv, "sliderVelocities") end)
    out.svCount = (okV and count(sl)) or -1
    out.svEntries = dumpEntries(sl, 5)
end
return out
