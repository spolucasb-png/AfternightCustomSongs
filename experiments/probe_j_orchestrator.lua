-- Probe J (AfternightCustomSongs): orchestrator call-shape preflight.
-- READ-ONLY, zero gameplay calls. Finds heap functions referencing ALL of
-- parseChart + addNotesFromChart + addSectionsFromChart (the normal loading
-- orchestrator) and dumps their full string-constant lists: this reveals the
-- call order, argument roles (events/difficulty/subtitles), and any guard
-- strings, without invoking anything. Capped output.
local MAXC = 300

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

local function hasAll(fn, names)
    local ok, consts = pcall(function() return getconstants(fn) end)
    if not (ok and type(consts) == "table") then return false end
    local hit = {}
    for _, c in next, consts do
        if type(c) == "string" then hit[c] = true end
    end
    for _, n in ipairs(names) do
        if not hit[n] then return false end
    end
    return true
end

local out = { orchestrators = {} }
for _, v in next, getgc(true) do
    if type(v) == "function"
        and hasAll(v, { "parseChart", "addNotesFromChart", "addSectionsFromChart" })
        and #out.orchestrators < 5 then
        table.insert(out.orchestrators, { consts = strConsts(v, MAXC) })
    end
end
return out
