local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local v1 = require(Modules.Data.DataManager):GetData()
local LocalSignals_m = require(Modules.Signals.LocalSignals)
local Logger_m = require(Modules.Other.Logger)
local t = {
    ModulesFolder = ReplicatedStorage:WaitForChild("Events"),
    stageRemote = nil,
    remoteListen = {},
    batchQueues = {},
    batchScheduled = {},
    readyServer = function(arg4, ...) --[[ readyServer ]] -- line: 55
        -- upvalues:
        --  [1] ReplicatedStorage (copy)
        --  [2] v1 (copy)

        ReplicatedStorage.Events.DataControl:FireServer(arg4, ...)

        if v1.PrintOutgoingSignals then
            print("Ready Server:", arg4, ...)
        end
    end
}

local function v2(arg1) -- line: 16
    -- upvalues:
    --  [1] LocalSignals_m (copy)
    --  [2] Logger_m (copy)

    local t_1 = {
        header = "[AFTERNIGHT NETWORKING ERROR]",
        content = arg1,
        contentHiddenByDefault = true,
        color = Color3.new(0.490196, 0.254902, 1),
        timeout = 10
    }
    LocalSignals_m.SendNotification:Fire(t_1)
    Logger_m.warn(arg1)
end

local function handleRemote(arg2, arg3, ...) -- line: 28
    -- upvalues:
    --  [1] t (copy)
    --  [2] v2 (copy)
    --  [3] v1 (copy)

    local v3 = t.remoteListen[arg3]

    if v3 then
        xpcall(v3, v2, ...)

        if v1.PrintIncomingSignals then
            print("RemoteHandler:", arg2, arg3, ...)
        end
    end
end

ReplicatedStorage.Events.EngineControl.OnClientEvent:Connect(function(...) -- line: 41
    -- upvalues:
    --  [1] handleRemote (copy)

    handleRemote("EngineControl", ...)
end)
ReplicatedStorage.Events.InputControl.OnClientEvent:Connect(function(...) -- line: 44
    -- upvalues:
    --  [1] handleRemote (copy)

    handleRemote("InputControl", ...)
end)
ReplicatedStorage.Events.DataControl.OnClientEvent:Connect(function(...) -- line: 47
    -- upvalues:
    --  [1] handleRemote (copy)

    handleRemote("DataControl", ...)
end)
ReplicatedStorage.Events.ShowMessageOnChannel.OnClientEvent:Connect(function(
    u1: userdata,
    s1: string
) -- line: 50
    u1:DisplaySystemMessage(s1)
end)

function t.listenTo(arg5, arg6) -- line: 62
    -- upvalues:
    --  [1] t (copy)

    t.remoteListen[arg5] = arg6
end

function t.fireServer(arg7, ...) -- line: 66
    -- upvalues:
    --  [1] ReplicatedStorage (copy)
    --  [2] v1 (copy)

    ReplicatedStorage.Events.EngineControl:FireServer(arg7, ...)

    if v1.PrintOutgoingSignals then
        print("Fired Server:", arg7, ...)
    end
end

function t.fireStageRemote(arg8, ...) -- line: 73
    -- upvalues:
    --  [1] t (copy)
    --  [2] v1 (copy)

    if t.stageRemote == nil then
        return
    end

    t.stageRemote:FireServer(arg8, ...)

    if v1.PrintOutgoingSignals then
        print("Fired Server [Stage Remote]:", arg8, ...)
    end
end

function t.fireStageRemoteBatched(arg9, ...) -- line: 84
    -- upvalues:
    --  [1] t (copy)

    if t.stageRemote == nil then
        return
    end

    local BatchQueues = t.batchQueues
    local BatchScheduled = t.batchScheduled
    BatchQueues[arg9] = BatchQueues[arg9] or {}
    table.insert(BatchQueues[arg9], { ... })

    if not BatchScheduled[arg9] then
        BatchScheduled[arg9] = true
        task.defer(function() -- line: 96
            -- upvalues:
            --  [1] BatchQueues (copy)
            --  [2] arg9 (copy)
            --  [3] BatchScheduled (copy)
            --  [4] t (ref)

            local v5 = BatchQueues[arg9]
            BatchQueues[arg9] = nil
            BatchScheduled[arg9] = nil
            t.fireStageRemote(arg9 .. "Batch", v5)
        end)
    end
end

return t
