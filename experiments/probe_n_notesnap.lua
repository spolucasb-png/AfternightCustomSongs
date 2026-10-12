-- Probe N (Afternight spike): live note + timing snapshot. READ-ONLY, zero
-- gameplay calls. Samples up to 3 objects each from Notes / UnspawnedNotes
-- (scalar fields only, capped), Strumline/Strum counts, Conductor BPM map
-- size, svFunctions.sliderVelocities size, songPlayer paths (song identity).
local MAXN = 3
local MAXF = 40

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

local function sample(list, n)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, v in next, list do
        if #out >= (n or MAXN) then break end
        if type(v) == "table" then
            local fields = {}
            for k, vv in next, v do
                if #fields >= MAXF then break end
                local kt = type(k)
                local vt = type(vv)
                if vt == "number" or vt == "string" or vt == "boolean" then
                    table.insert(fields, tostring(k) .. "(" .. kt .. ")=" .. tostring(vv))
                else
                    table.insert(fields, tostring(k) .. "(" .. kt .. "):" .. vt)
                end
            end
            table.sort(fields)
            table.insert(out, fields)
        else
            table.insert(out, { "value:" .. type(v) })
        end
    end
    return out
end

local mod = gameMod()
if mod == nil then return { found = false } end
local out = { found = true }
for _, field in ipairs({ "Notes", "UnspawnedNotes", "Strumlines", "Strums" }) do
    local ok, t = pcall(function() return rawget(mod, field) end)
    out[field] = (ok and count(t)) or -1
end
out.noteSamples = sample(rawget(mod, "Notes"), 3)
out.unspawnedSamples = sample(rawget(mod, "UnspawnedNotes"), 3)
local okC, con = pcall(function() return rawget(mod, "Conductor") end)
if okC and type(con) == "table" then
    local okB, bm = pcall(function() return rawget(con, "BPMChangeMap") end)
    out.bpmChanges = (okB and count(bm)) or -1
    local okT, tp = pcall(function() return rawget(con, "TimePosition") end)
    if okT and type(tp) == "number" then out.t = tp end
end
local okS, sv = pcall(function() return rawget(mod, "svFunctions") end)
if okS and type(sv) == "table" then
    local okV, sl = pcall(function() return rawget(sv, "sliderVelocities") end)
    out.sliderVelocities = (okV and count(sl)) or -1
end
local okP, sp = pcall(function() return rawget(mod, "songPlayer") end)
if okP and type(sp) == "table" then
    local okPa, pa = pcall(function() return rawget(sp, "paths") end)
    if okPa and type(pa) == "table" then
        local names = {}
        for _, v in next, pa do
            if #names >= 10 then break end
            table.insert(names, tostring(v))
        end
        table.sort(names)
        out.audioPaths = names
    end
    local okCp, cp = pcall(function() return rawget(sp, "curPath") end)
    if okCp and type(cp) == "string" then out.curPath = cp end
end
local okM, mm = pcall(function() return rawget(mod, "mapModule") end)
if okM and type(mm) == "table" then
    local okMs, ms = pcall(function() return rawget(mm, "Maps") end)
    out.maps = (okMs and count(ms)) or -1
end
return out
