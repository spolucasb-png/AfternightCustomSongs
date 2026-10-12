-- AFN player_loader v1.1: one-shot smoke wrapper around player_core.
-- Loads afn_player_core.lua from the executor workspace (deploy sibling),
-- plays the synth fixture with a short observe window, then tears down.
-- Returns the report table. One shot per client session (_G.AFNPlayerRan).

if _G.AFNPlayerRan then
    return { aborted = "already-ran-this-session" }
end
_G.AFNPlayerRan = true

local CHART_JSON = [=[{"song":{"song":"afn_synth_a_taps","bpm":200,"keyCount":4,"playerKeyCount":4,"notes":[{"mustHitSection":false,"sectionNotes":[[1200,4,0],[1800,5,0],[2400,6,0],[3000,7,0]]}],"events":[]}}]=]

local okR, src = pcall(function() return readfile("afn_player_core.lua") end)
if not okR then
    return { aborted = "missing-afn_player_core.lua", err = tostring(src) }
end
local okL, core = pcall(function() return loadstring(src, "afn_player_core")() end)
if not okL or type(core) ~= "table" or type(core.play) ~= "function" then
    return { aborted = "player_core-load-failed", err = tostring(core) }
end

return core.play({
    chartJson = CHART_JSON,
    songName = "afn_synth_a_taps",
    diff = "Easy",
    keepAlive = false,
    observeSeconds = 3,
})
