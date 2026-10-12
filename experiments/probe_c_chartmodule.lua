-- Probe C (Afternight feasibility spike): locate the gameplay chart module.
-- READ-ONLY: finds the table holding addNotesFromChart, dumps its string-key
-- inventory (methods vs data, capped), no calls, no writes, no hooks.
local MAXK = 120
local target = nil
for _, v in next, getgc(true) do
    if type(v) == "table" and type(rawget(v, "addNotesFromChart")) == "function" then
        target = v
        break
    end
end
if target == nil then return { found = false } end
local fns, data = {}, {}
for k, v in next, target do
    if type(k) == "string" then
        if type(v) == "function" then
            if #fns < MAXK then table.insert(fns, k) end
        else
            if #data < MAXK then table.insert(data, k .. "=" .. type(v)) end
        end
    end
end
table.sort(fns)
table.sort(data)
return { found = true, methods = fns, nMethods = #fns, fields = data, nFields = #data }
