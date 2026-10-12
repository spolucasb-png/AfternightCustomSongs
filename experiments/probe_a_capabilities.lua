-- Probe A (Afternight feasibility spike): runtime + capability census.
-- READ-ONLY. No game state is touched, nothing is written, no hooks.
-- Returns: { game = {placeId, name}, caps = {name = true/false}, unav = {...} }
local function has(name)
    if type(_G[name]) == "function" then return true end
    if type(getfenv) == "function" then
        local ok, env = pcall(function() return getfenv(0) end)
        if ok and type(env) == "table" and type(env[name]) == "function" then
            return true
        end
    end
    return false
end

local CAPS = {
    "getgc", "readfile", "writefile", "isfile", "isfolder", "makefolder",
    "listfiles", "loadstring", "getcustomasset", "getsynasset", "gethui",
    "getconnections", "identifyexecutor",
}

local out = { caps = {}, game = {} }
for _, n in ipairs(CAPS) do out.caps[n] = has(n) end
local okP, pid = pcall(function() return game.PlaceId end)
out.game.placeId = (okP and tonumber(pid)) or -1
local okN, nm = pcall(function() return game.Name end)
out.game.name = (okN and tostring(nm)) or "?"
return out
