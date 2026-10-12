-- Probe B (Afternight feasibility spike): read-only game-structure census.
-- One bounded getgc(true) sweep. NO mutation: predicates only type()/rawget()
-- tables, nothing is called, nothing is written, no hooks installed.
-- Returns counts + the method/field NAME sets of up to N matches per shape.
-- Shapes are generic rhythm-game guesses, NOT Gakuran names: a miss here
-- proves nothing about the game, only that these shapes were absent.
local MAX_REPORT = 5
local MAX_NAMES = 40

local function nameset(t, wantFn)
    local fns, fields = {}, {}
    for k, v in next, t do
        if type(k) == "string" then
            if type(v) == "function" and wantFn then table.insert(fns, k) end
            if type(v) ~= "function" and not wantFn then table.insert(fields, k) end
        end
    end
    table.sort(fns)
    table.sort(fields)
    while #fns > MAX_NAMES do table.remove(fns) end
    while #fields > MAX_NAMES do table.remove(fields) end
    return fns, fields
end

local specs = {
    playish = function(t)  -- something with Play + Stop functions
        local n = 0
        for k, v in next, t do
            if type(k) == "string" and type(v) == "function"
                and (k:lower():find("play") or k:lower():find("stop")) then
                n += 1
            end
        end
        return n >= 2
    end,
    registryish = function(t)  -- _byId + _list tables
        return type(rawget(t, "_byId")) == "table" and type(rawget(t, "_list")) == "table"
    end,
    sessionish = function(t)  -- holds a _session table
        return type(rawget(t, "_session")) == "table"
    end,
}

local counts = { playish = 0, registryish = 0, sessionish = 0, tables = 0 }
local samples = { playish = {}, registryish = {}, sessionish = {} }
for _, v in next, getgc(true) do
    if type(v) == "table" then
        counts.tables += 1
        for name, pred in pairs(specs) do
            local ok, hit = pcall(pred, v)
            if ok and hit then
                counts[name] += 1
                if #samples[name] < MAX_REPORT then
                    local fns, fields = nameset(v, name == "playish")
                    samples[name][#samples[name] + 1] = { fns = fns, fields = fields }
                end
            end
        end
    end
end
return { counts = counts, samples = samples }
