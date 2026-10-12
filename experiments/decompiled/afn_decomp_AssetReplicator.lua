local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RequestEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("Engine"):WaitForChild(
    "RequestEvent"
)
local t = {}

if RunService:IsServer() then
    local t_1 = {}

    local function getContainer(arg1, arg2) -- line: 23
        local PlayerGui = arg1:FindFirstChild("PlayerGui")

        if not PlayerGui then
            return nil
        end

        local v1 = PlayerGui:FindFirstChild("__AssetContainer")

        if not v1 then
            v1 = Instance.new("ScreenGui")
            v1.Name = "__AssetContainer"
            v1.ResetOnSpawn = false
            v1.Parent = PlayerGui
        end

        local v2 = v1:FindFirstChild(arg2)

        if not v2 then
            v2 = Instance.new("Folder")
            v2.Name = arg2
            v2.Parent = v1
        end

        return v2
    end

    RequestEvent.OnServerEvent:Connect(function(arg3, arg4, arg5, arg6) -- line: 45
        -- upvalues:
        --  [1] ServerStorage (copy)
        --  [2] RequestEvent (copy)
        --  [3] t_1 (copy)
        --  [4] getContainer (copy)

        if typeof(arg4) ~= "string" then
            return
        end

        local v3 = if typeof(arg5) == "string" then false else true
        local v4 = arg5

        if typeof(arg5) ~= "string" or not v4 then
            v4 = nil
        end

        local v5 = arg5

        if typeof(arg5) ~= "table" or not v5 then
            v5 = arg6

            if typeof(arg6) ~= "table" or not v5 then
                v5 = { persistentInstance = true }
            end
        end

        local v6 = ServerStorage.ReplicableAssets:FindFirstChild(arg4)

        if not v6 then
            RequestEvent:FireClient(arg3, arg4, v4, false)

            return
        end

        local UserId = arg3.UserId
        local v7 = t_1
        local v8 = t_1[UserId] or {}
        v7[UserId] = v8
        local v9 = getContainer(arg3, arg4)

        if not v9 then
            return
        end

        if v3 then
            for _, child in v6:GetChildren() do
                local v10 = `{arg4}/{child.Name}`
                local v11 = t_1[UserId][v10]

                if not v11 then
                    local v12 = child:Clone()

                    if v5.persistentInstance ~= false then
                        t_1[UserId][v10] = v12
                        v12.Destroying:Connect(function() -- line: 72
                            -- upvalues:
                            --  [1] t_1 (ref)
                            --  [2] UserId (copy)
                            --  [3] v10 (copy)

                            if t_1[UserId] then
                                t_1[UserId][v10] = nil
                            end
                        end)
                    end

                    v12.Parent = v9

                    if v5.persistentInstance == false then
                        task.defer(function() -- line: 80
                            -- upvalues:
                            --  [1] v12 (copy)

                            v12:Destroy()
                        end)
                    end
                elseif v11.Parent ~= v9 then
                    v11.Parent = v9
                end
            end

            RequestEvent:FireClient(arg3, arg4, nil, true)

            return
        end

        local v13 = v6:FindFirstChild(v4)

        if not v13 then
            RequestEvent:FireClient(arg3, arg4, v4, false)

            return
        end

        local v14 = `{arg4}/{v4}`
        local v15 = t_1[UserId][v14]

        if v15 then
            if v15.Parent ~= v9 then
                v15.Parent = v9
            end

            RequestEvent:FireClient(arg3, arg4, v4, true)

            return
        end

        local v16 = v13:Clone()

        if v5.persistentInstance ~= false then
            t_1[UserId][v14] = v16
            v16.Destroying:Connect(function() -- line: 113
                -- upvalues:
                --  [1] t_1 (ref)
                --  [2] UserId (copy)
                --  [3] v14 (copy)

                if t_1[UserId] then
                    t_1[UserId][v14] = nil
                end
            end)
        end

        v16.Parent = v9
        RequestEvent:FireClient(arg3, arg4, v4, true)

        if v5.persistentInstance == false then
            task.defer(function() -- line: 124
                -- upvalues:
                --  [1] v16 (copy)

                v16:Destroy()
            end)
        end
    end)
    Players.PlayerRemoving:Connect(function(arg7) -- line: 131
        -- upvalues:
        --  [1] t_1 (copy)

        t_1[arg7.UserId] = nil
    end)

    return nil
end

local PlayerGui_1 = Players.LocalPlayer:WaitForChild("PlayerGui")
local t_2 = {}
local t_3 = {}

local _ = function(arg8, arg9) --[[ getAssetKey ]] -- line: 142
    return typeof(arg9) == "string" and `{arg8}/{arg9}` or arg8
end

RequestEvent.OnClientEvent:Connect(function(arg10, arg11, arg12) -- line: 146
    -- upvalues:
    --  [1] t_3 (copy)
    --  [2] t_2 (copy)
    --  [3] PlayerGui_1 (copy)

    local v18 = if typeof(arg11) == "string" then false else true

    if arg12 and v18 then
        t_3[arg10] = true
    end

    local v19 = typeof(arg11) == "string" and `{arg10}/{arg11}` or arg10
    local v20 = t_2[v19]

    if v20 then
        if not arg12 then
            for _, val in v20 do
                task.spawn(val, nil)
            end

            t_2[v19] = nil

            return
        end

        local AssetContainer = PlayerGui_1:WaitForChild("__AssetContainer", 5)
        local v21 = AssetContainer and AssetContainer:WaitForChild(arg10, 5) or nil
        local v22 = nil

        if v18 then
            v22 = v21
        elseif v21 then
            v22 = v21:WaitForChild(arg11, 5)
        end

        for _, val_1 in v20 do
            task.spawn(val_1, v22)
        end

        t_2[v19] = nil
    end
end)

function t.getAsset(s1: string, arg13: any, arg14: any) -- line: 181
    -- upvalues:
    --  [1] PlayerGui_1 (copy)
    --  [2] t_3 (copy)
    --  [3] t_2 (copy)
    --  [4] RequestEvent (copy)

    local v23 = if typeof(arg13) == "string" then false else true
    local v24 = arg13

    if typeof(arg13) ~= "string" or not v24 then
        v24 = nil
    end

    local v25 = arg13

    if typeof(arg13) ~= "table" or not v25 then
        v25 = arg14

        if typeof(arg14) ~= "table" or not v25 then
            v25 = {}
        end
    end

    local v26 = v25.yieldTimeout or 5
    local AssetContainer_1 = PlayerGui_1:FindFirstChild("__AssetContainer")
    local v27 = AssetContainer_1 and AssetContainer_1:FindFirstChild(s1) or nil
    local v28 = v27

    if not v23 or not t_3[s1] or not v28 then
        v28 = v27 and v27:FindFirstChild(v24) or nil
    end

    if v28 then
        return v28
    end

    local v29

    if typeof(v24) == "string" then
        v29 = ("%*/%*"):format(s1, v24) or s1
    else
        v29 = s1
    end

    if not t_2[v29] then
        t_2[v29] = {}
        RequestEvent:FireServer(s1, v24, v25)
    end

    local thread = coroutine.running()
    table.insert(t_2[v29], thread)
    task.delay(v26, function() -- line: 201
        -- upvalues:
        --  [1] t_2 (ref)
        --  [2] v29 (copy)
        --  [3] thread (copy)

        local v30 = t_2[v29]

        if v30 then
            for key_3, val_2 in v30 do
                if val_2 == thread then
                    table.remove(v30, key_3)
                    task.spawn(thread, nil)

                    return
                end
            end
        end
    end)

    return coroutine.yield()
end

function t.getAssetAsync(s2: string, arg15: any, arg16: any) -- line: 217
    -- upvalues:
    --  [1] PlayerGui_1 (copy)
    --  [2] t_3 (copy)
    --  [3] t_2 (copy)
    --  [4] RequestEvent (copy)

    local v31 = if typeof(arg15) == "string" then false else true
    local v32 = arg15

    if typeof(arg15) ~= "string" or not v32 then
        v32 = nil
    end

    local v33 = arg15

    if typeof(arg15) ~= "table" or not v33 then
        v33 = arg16

        if typeof(arg16) ~= "table" or not v33 then
            v33 = {}
        end
    end

    local AssetContainer_2 = PlayerGui_1:FindFirstChild("__AssetContainer")
    local v34 = AssetContainer_2 and AssetContainer_2:FindFirstChild(s2) or nil
    local v35 = v34

    if not v31 or not t_3[s2] or not v35 then
        v35 = v34 and v34:FindFirstChild(v32) or nil
    end

    if v35 then
        return v35, true
    end

    local v36 = typeof(v32) == "string" and `{s2}/{v32}` or s2

    if not t_2[v36] then
        t_2[v36] = {}
        RequestEvent:FireServer(s2, v32, v33)
    end

    return nil, false
end

return t
