-- Probe I (AfternightCustomSongs): caller + full-constant preflight.
-- READ-ONLY, zero gameplay calls. (1) Full string-constant list of
-- parseChart (no cap). (2) Heap sweep for functions referencing
-- "parseChart" / "addNotesFromChart" / "addSectionsFromChart" in their
-- constants (callers); each hit is resolved against the gameplay module's
-- own method table so callers are named, not anonymous. Capped output.
local MAXC = 250
local MAXCALLERS = 20

local function gameMod()
    for _, v in next, getgc(true) do
        if type(v) == "table" and type(rawget(v, "addNotesFromChart")) == "function" then
            return v
        end
    end
    return nil
end

local function strConsts(fn, cap)
    local kept = {}
    local ok, consts = pcall(function() return getconstants(fn) end)
    if ok and type(consts) == "table" then
        for _, c in next, consts do
            if #kept >= (cap or MAXC) then break end
            if type(c) == "string" then table.insert(kept, c) end
        end
    end
    table.sort(kept)
    return kept
end

local mod = gameMod()
if mod == nil then return { found = false } end
local out = { found = true }

local okP, pf = pcall(function() return rawget(mod, "parseChart") end)
if okP and type(pf) == "function" then
    out.parseChartConsts = strConsts(pf, MAXC)
end

-- index the module's own methods by identity for caller naming
local methodNames = {}
for k, v in next, mod do
    if type(k) == "string" and type(v) == "function" then
        methodNames[v] = k
    end
end

local targets = { "parseChart", "addNotesFromChart", "addSectionsFromChart", "createNote" }
out.callers = {}
for _, tname in ipairs(targets) do out.callers[tname] = {} end
for _, v in next, getgc(true) do
    if type(v) == "function" then
        local ok, consts = pcall(function() return getconstants(v) end)
        if ok and type(consts) == "table" then
            for _, c in next, consts do
                if type(c) == "string" then
                    for _, tname in ipairs(targets) do
                        if c == tname and #out.callers[tname] < MAXCALLERS then
                            local label = methodNames[v]
                            if label == nil then
                                local addr = tostring(v):match("0x[0-9a-f]+")
                                label = "anonymous@" .. (addr or "?")
                            end
                            table.insert(out.callers[tname], label)
                        end
                    end
                end
            end
        end
    end
end
for _, tname in ipairs(targets) do table.sort(out.callers[tname]) end
return out
