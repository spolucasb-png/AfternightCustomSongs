-- Probe E (Afternight feasibility spike): local-file + asset feasibility.
-- Touches ONLY the executor workspace (write/read/delete one scratch file),
-- never game state. Proves the file APIs the chart pipeline needs.
local SCRATCH = "afternight_probe_scratch.txt"
local PAYLOAD = "afternight-probe-roundtrip"

local out = { root = nil, write = false, readBack = false, deleted = false }
out.hasDelfile = type(_G["delfile"]) == "function"
if not out.hasDelfile then
    out.note = "delfile missing: write roundtrip skipped (no cleanup primitive)"
    return out
end
local okL, files = pcall(function() return listfiles("") end)
if okL and type(files) == "table" then
    local names = {}
    for _, f in ipairs(files) do names[#names + 1] = tostring(f) end
    table.sort(names)
    out.root = names
end
local okW = pcall(function() writefile(SCRATCH, PAYLOAD) end)
out.write = okW == true
if out.write then
    local okR, back = pcall(function() return readfile(SCRATCH) end)
    out.readBack = okR and back == PAYLOAD
    pcall(function() delfile(SCRATCH) end)
    local okGone = pcall(function() return isfile(SCRATCH) end)
    out.deleted = not okGone or isfile(SCRATCH) == false
    if out.deleted == false then pcall(function() delfile(SCRATCH) end) end
end
return out
