-- Probe D2 (Afternight feasibility spike): song list + live note shapes.
-- READ-ONLY: rawget walks only, zero function calls. Reads mapModule.Maps
-- keys (available songs), counts Notes/UnspawnedNotes, and if any note
-- object exists dumps its field-name inventory (types only, capped).
local MAXK = 80

local function gameMod()
    for _, v in next, getgc(true) do
        if type(v) == "table" and type(rawget(v, "addNotesFromChart")) == "function" then
            return v
        end
    end
    return nil
end

local function keysOf(t, cap)
    local out = {}
    for k, v in next, t do
        if #out >= (cap or MAXK) then break end
        table.insert(out, tostring(k) .. "=" .. type(v))
    end
    table.sort(out)
    return out
end

local mod = gameMod()
if mod == nil then return { found = false } end
local out = { found = true }

local okM, maps = pcall(function() return rawget(rawget(mod, "mapModule"), "Maps") end)
if okM and type(maps) == "table" then
    local names = {}
    for k, _ in next, maps do
        if #names >= MAXK then break end
        table.insert(names, tostring(k))
    end
    table.sort(names)
    out.mapNames = names
    out.nMaps = #names
end

for _, field in ipairs({ "Notes", "UnspawnedNotes" }) do
    local ok, t = pcall(function() return rawget(mod, field) end)
    if ok and type(t) == "table" then
        local n = 0
        local first = nil
        for _, v in next, t do
            n += 1
            if first == nil then first = v end
        end
        local entry = { count = n }
        if type(first) == "table" then entry.shape = keysOf(first, 40) end
        out[field] = entry
    end
end
return out
