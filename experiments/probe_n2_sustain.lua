-- Probe N2 (Afternight spike): sustain-note shape + phase-2 counts.
-- READ-ONLY, zero gameplay calls. Finds the first note with isSustain=true
-- in Notes then UnspawnedNotes; dumps its scalar fields plus one level into
-- prevNote / section / rawData (key Machine inventory, values only when
-- scalar, everything capped). Also recounts the four lists for migration.
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

local function scalars(t, cap)
    local out = {}
    for k, v in next, t do
        if #out >= (cap or MAXF) then break end
        local vt = type(v)
        if vt == "number" or vt == "string" or vt == "boolean" then
            table.insert(out, tostring(k) .. "=" .. tostring(v))
        end
    end
    table.sort(out)
    return out
end

local function subkeys(t, cap)
    local out = {}
    for k, v in next, t do
        if #out >= (cap or MAXF) then break end
        table.insert(out, tostring(k) .. ":" .. type(v))
    end
    table.sort(out)
    return out
end

local mod = gameMod()
if mod == nil then return { found = false } end
local out = { found = true }
for _, field in ipairs({ "Notes", "UnspawnedNotes", "Strumlines", "Strums" }) do
    local ok, t = pcall(function() return rawget(mod, field) end)
    out[field] = (ok and count(t)) or -1
end
local okT, tp = pcall(function() return rawget(rawget(mod, "Conductor"), "TimePosition") end)
if okT and type(tp) == "number" then out.t = tp end

local sus = nil
local susFrom = nil
for _, field in ipairs({ "Notes", "UnspawnedNotes" }) do
    local ok, t = pcall(function() return rawget(mod, field) end)
    if ok and type(t) == "table" then
        for _, v in next, t do
            if type(v) == "table" then
                local okS, s = pcall(function() return rawget(v, "isSustain") end)
                if okS and s == true then
                    sus, susFrom = v, field
                    break
                end
            end
        end
    end
    if sus ~= nil then break end
end
if sus == nil then
    out.sustain = "none-found"
else
    local entry = { from = susFrom, self = scalars(sus) }
    local okP, pv = pcall(function() return rawget(sus, "prevNote") end)
    if okP and type(pv) == "table" then entry.prevNote = scalars(pv, 20) end
    local okS2, sc = pcall(function() return rawget(sus, "section") end)
    if okS2 and type(sc) == "table" then entry.section = subkeys(sc, 20) end
    local okR, rd = pcall(function() return rawget(sus, "rawData") end)
    if okR and type(rd) == "table" then entry.rawData = subkeys(rd, 20) end
    out.sustain = entry
end
return out
