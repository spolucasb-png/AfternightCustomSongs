-- Probe H (AfternightCustomSongs): native section/row format from live notes.
-- READ-ONLY, zero gameplay calls. Reads one live note's full rawData array
-- and its section.sectionNotes rows (capped scalars). Establishes the native
-- chart-row format empirically: time units, lane encoding, sustain encoding.
local MAXR = 8

local function gameMod()
    for _, v in next, getgc(true) do
        if type(v) == "table" and type(rawget(v, "addNotesFromChart")) == "function" then
            return v
        end
    end
    return nil
end

local function fullArray(t, cap)
    local out = {}
    if type(t) ~= "table" then return out end
    for k, v in next, t do
        if #out >= (cap or MAXR) then break end
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
local note = nil
local from = nil
for _, field in ipairs({ "Notes", "UnspawnedNotes" }) do
    local ok, t = pcall(function() return rawget(mod, field) end)
    if ok and type(t) == "table" then
        for _, v in next, t do
            if type(v) == "table" then
                note, from = v, field
                break
            end
        end
    end
    if note ~= nil then break end
end
if note == nil then
    out.notes = "empty"
    return out
end
out.from = from
local okR, rd = pcall(function() return rawget(note, "rawData") end)
if okR then out.rawData = fullArray(rd, 10) end
local okS, sc = pcall(function() return rawget(note, "section") end)
if okS and type(sc) == "table" then
    local okI, id = pcall(function() return rawget(sc, "id") end)
    if okI then out.sectionId = id end
    local okM, mh = pcall(function() return rawget(sc, "mustHitSection") end)
    if okM then out.mustHit = mh end
    local okN, sn = pcall(function() return rawget(sc, "sectionNotes") end)
    if okN and type(sn) == "table" then
        local rows = {}
        for _, row in next, sn do
            if #rows >= MAXR then break end
            table.insert(rows, fullArray(row, 8))
        end
        out.sectionRows = rows
    end
end
local okT, st = pcall(function() return rawget(note, "strumTime") end)
if okT then out.strumTime = st end
local okC, co = pcall(function() return rawget(note, "column") end)
if okC then out.column = co end
return out
