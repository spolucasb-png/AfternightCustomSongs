-- Probe D (Afternight feasibility spike): chart/song storage shapes.
-- READ-ONLY: rawget walks only, zero function calls. Inspects the gameplay
-- module's Map / mapModule / Conductor / songPlayer / getSongData-result
-- shapes to learn how a loaded song is represented. Empty tables simply mean
-- no song is currently loaded.
local MAXK = 60

local function shape(t, depth)
    if type(t) ~= "table" or (depth or 0) > 1 then return type(t) end
    local keys = {}
    for k, v in next, t do
        if type(k) == "string" and #keys < MAXK then
            table.insert(keys, k .. "=" .. type(v))
        end
    end
    table.sort(keys)
    return keys
end

local mod = nil
for _, v in next, getgc(true) do
    if type(v) == "table" and type(rawget(v, "addNotesFromChart")) == "function" then
        mod = v
        break
    end
end
if mod == nil then return { found = false } end

local out = { found = true }
for _, field in ipairs({ "Map", "mapModule", "Conductor", "songPlayer", "Settings", "svFunctions" }) do
    local ok, sub = pcall(function() return rawget(mod, field) end)
    if ok then out[field] = shape(sub, 0) end
end
-- one level deeper into Map only (the likely chart store), types only
local okM, map = pcall(function() return rawget(mod, "Map") end)
if okM and type(map) == "table" then
    local deep = {}
    for k, v in next, map do
        if type(k) == "string" and #deep < MAXK then
            if type(v) == "table" then
                local n, ex = 0, nil
                for k2, v2 in next, v do
                    n += 1
                    if ex == nil then ex = tostring(k2) .. "=" .. type(v2) end
                    if n > 3 then break end
                end
                table.insert(deep, k .. "=table[" .. tostring(n) .. "]{" .. tostring(ex) .. "}")
            else
                table.insert(deep, k .. "=" .. type(v))
            end
        end
    end
    table.sort(deep)
    out.MapDeep = deep
end
return out
