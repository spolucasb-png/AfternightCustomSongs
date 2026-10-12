if game:GetService("RunService"):IsClient() then
    repeat
        task.wait()
    until game:IsLoaded()
end

local t = { ReplicationEnabled = true, SupportEmotes = true }

if workspace:GetAttribute("_DebugSetReplicator") ~= nil and game:GetService("RunService"):IsStudio() then
    t.ReplicationEnabled = workspace:GetAttribute("_DebugSetReplicator")
end

if game:GetService("RunService"):IsServer() then
    workspace:SetAttribute("ReplicationEnabled", t.ReplicationEnabled)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Assets = ReplicatedStorage:WaitForChild("Assets")
local Events = ReplicatedStorage:WaitForChild("Events")
local Character_m = require(Modules.Main.Character)
local v1 = t.SupportEmotes and require(script.EmoteSupport) or nil
local CharacterReplication = Events.CharacterReplication
local StageAnimReplication = Events.StageAnimReplication
local Emotes = Assets:WaitForChild("Emotes")
local Animations = Assets:WaitForChild("Animations")
local Logger_m = require(Modules.Other.Logger)
local t_1 = {
    ManualPlay = function(
        arg1,
        arg2,
        arg3,
        arg4,
        arg5
    ) -- line: 42
        -- upvalues:
        --  [1] StageAnimReplication (copy)

        if arg3.isStage then
            StageAnimReplication:FireClient(arg2, arg1.owner, arg4, arg5)

            return
        end

        arg3.remote:FireClient(
            arg2,
            "Play",
            arg4,
            arg5,
            false
        )
    end
}
local t_2 = {
    loadCharacters = true,
    loadExtCharacters = true,
    loadExtHugeRigs = false,
    loadStageCharacters = true,
    hugeAnimReplacement = Animations:WaitForChild("BF")
}
local t_3 = { ManualPlay = true }

function getAnimInstanceFromString(arg6, arg7) -- line: 62
    -- upvalues:
    --  [1] Emotes (copy)
    --  [2] Animations (copy)

    return ((arg7 and Emotes or Animations):FindFirstChild(arg6))
end

function cleanAnimForReplication(arg8, arg9) -- line: 68
    for _, child in arg8:GetChildren() do
        if child.Name:sub(1, #arg9) ~= arg9 and child.Name ~= "Assets" then
            child:Destroy()
        end
    end

    return arg8
end

function writePropsAndStuffFromAnim(arg10, arg11) -- line: 77
    local PropData = arg10.propData
    local v5 = arg11:FindFirstChild(PropData.animSide or PropData.side)
    local v6 = arg11:GetAttributes()

    if v5 then
        for key_1, val in v5:GetAttributes() do
            v6[key_1] = val
        end
    end

    arg10.sideAttributes = v6
end

if game:GetService("RunService"):IsServer() then
    local t_4 = {}
    local t_5 = {}
    local t_6 = {}
    local t_7 = {}

    function replicateToClient(u1: userdata, arg12: any) -- line: 99
        -- upvalues:
        --  [1] ReplicatedStorage (copy)

        if arg12:IsDescendantOf(ReplicatedStorage.Assets) then
            arg12 = arg12:Clone()
        end

        arg12.Parent = u1.PlayerGui:FindFirstChild("__CharacterReplication")
    end

    function safeDestroyInvoke(arg13, arg14) -- line: 108
        local thread = coroutine.running()
        local v7 = false
        local v8 = nil
        v8 = task.delay(20, function() -- line: 113
            -- upvalues:
            --  [1] v7 (ref)
            --  [2] v8 (ref)
            --  [3] thread (copy)

            if not v7 then
                v8 = nil
                task.spawn(thread, false)
            end
        end)
        task.spawn(function() -- line: 120
            -- upvalues:
            --  [1] arg13 (copy)
            --  [2] arg14 (copy)
            --  [3] v7 (ref)
            --  [4] v8 (ref)
            --  [5] thread (copy)

            arg13:InvokeClient(arg14)
            v7 = true

            if v8 then
                task.cancel(v8)
                v8 = nil
            end

            task.spawn(thread, true)
        end)

        if not v7 then
            return coroutine.yield()
        end

        return true
    end

    function removePlayerFromData(arg15, arg16) -- line: 135
        if arg16.destRemote then
            safeDestroyInvoke(arg16.destRemote, arg15)
            arg16.destRemote:Destroy()
        end

        if arg16.model then
            arg16.model:Destroy()
        end

        if arg16.remote then
            arg16.remote:Destroy()
        end

        if arg16.extraAssets then
            for _, val_1 in arg16.extraAssets do
                pcall(function() -- line: 143
                    -- upvalues:
                    --  [1] val_1 (copy)

                    val_1:Destroy()
                end)
            end
        end
    end

    local NewWithProps = Character_m.newWithProps

    function Character_m.newWithProps(arg17) -- line: 150
        -- upvalues:
        --  [1] t (copy)
        --  [2] Logger_m (copy)
        --  [3] NewWithProps (copy)
        --  [4] t_5 (copy)
        --  [5] t_6 (copy)
        --  [6] t_7 (copy)
        --  [7] t_2 (copy)
        --  [8] CharacterReplication (copy)
        --  [9] t_3 (copy)
        --  [10] t_1 (copy)
        --  [11] t_4 (copy)

        if arg17.serverReplication or not t.ReplicationEnabled then
            Logger_m.log("Not doing replication!")

            return NewWithProps(arg17)
        end

        local v9 = arg17.charModel or arg17.model
        local v10 = ""
        local _ = v9
        local v13, v14

        if v9:IsA("Player") then
            v10 = v9
            local Character = v9.Character

            if not Character then
                return
            end

            Character.Archivable = true

            for _, descendant in Character:GetDescendants() do
                if descendant:IsA("Script") then
                    descendant.Archivable = false
                else
                    descendant.Archivable = true
                end
            end

            v13 = Character
            v14 = Character:Clone()
        end

        local v15 = arg17.remote or arg17.replicationRemote
        arg17.charModel = nil
        arg17.model = nil
        arg17.replicationRemote = nil
        arg17.remote = nil
        arg17.async = true
        local v16 = arg17.position or v13:GetPivot()
        arg17.position = v16
        v16 = arg17.animSide or (arg17.side or "L")
        local v17 = nil
        local v18 = arg17.anim or arg17.startingAnim

        if type(v18) == "string" then
            v18 = getAnimInstanceFromString(v18, arg17.isEmote or (arg17.emote or false))
        end

        if typeof(v18) == "Instance" then
            v18 = cleanAnimForReplication(v18:Clone(), v16)
        end

        local t_8 = {
            stagePlayers = nil,
            isStage = nil,
            isEmote = nil,
            preloadedAnims = nil,
            sideAttributes = nil,
            currentAnim = nil,
            players = nil,
            playersData = nil,
            owner = nil,
            propData = nil,
            alive = true,
            Destroy = nil,
            CanAddPlayer = nil,
            RemovePlayer = nil,
            AddPlayer = nil
        }
        local v23 = arg17.stagePlrs or arg17.stagePlayers
        t_8.stagePlayers = v23
        v23 = if arg17.stagePlrs then true else if not arg17.stagePlayers then false else true
        t_8.isStage = v23
        v23 = arg17.isEmote or (arg17.emote or false)
        t_8.isEmote = v23
        t_8.preloadedAnims = {}
        t_8.sideAttributes = {}
        t_8.currentAnim = v18
        t_8.players = {}
        t_8.playersData = {}
        t_8.owner = if v10 == "" then false else v10
        t_8.propData = arg17

        function t_8.Destroy(arg18) -- line: 221
            -- upvalues:
            --  [1] t_5 (ref)
            --  [2] t_6 (ref)
            --  [3] v10 (ref)
            --  [4] v17 (ref)

            local v25 = table.find(t_5, arg18)

            if v25 then
                table.remove(t_5, v25)
            end

            t_6[v10] = nil

            if v17 then
                v17:Disconnect()
                v17 = nil
            end

            for key_4, val_2 in arg18.playersData do
                task.spawn(removePlayerFromData, key_4, val_2)
            end
        end

        function t_8.CanAddPlayer(arg19, arg20) -- line: 236
            -- upvalues:
            --  [1] t_7 (ref)

            local v26 = t_7[arg20]

            if not v26 then
                return false
            end

            if not v26[1] then
                return false
            end

            local v27 = arg19.isStage

            if v27 then
                v27 = table.find(arg19.stagePlayers, arg20)
            end

            return if not v27 then if v27 then false else if not v26[2] then false else true else if not v26[3] then if v27 then false else if not v26[2] then false else true else true
        end

        function t_8.RemovePlayer(arg21, arg22) -- line: 251
            if not arg21.players[arg22] then
                return
            end

            arg21.players[arg22] = nil
            local v28 = arg21.playersData[arg22]
            arg21.playersData[arg22] = nil
            task.spawn(removePlayerFromData, arg22, v28)
        end

        function t_8.AddPlayer(arg23, arg24) -- line: 259
            -- upvalues:
            --  [1] v14 (ref)
            --  [2] v16 (copy)
            --  [3] t_7 (ref)
            --  [4] t_2 (ref)
            --  [5] arg17 (copy)
            --  [6] CharacterReplication (ref)
            --  [7] v13 (ref)

            if arg23.players[arg24] or arg24 == arg23.owner and arg23.isStage then
                return
            end

            arg23.players[arg24] = true
            local v29 = arg23.isStage

            if v29 then
                v29 = table.find(arg23.stagePlayers, arg24)
            end

            if v29 then
                arg23.playersData[arg24] = { isStage = true }

                return
            end

            local v30 = v14:Clone()
            local RemoteFunction = Instance.new("RemoteFunction")
            local CharRepl_RemoteEvent = Instance.new("RemoteEvent")
            CharRepl_RemoteEvent.Name = "CharRepl"
            local v31 = arg23.currentAnim and arg23.currentAnim:Clone() or nil

            if v31 then
                if not v31:GetAttribute("HugeAnim") then
                    if v31:FindFirstChild(v16) and v31[v16]:GetAttribute("HugeAnim") and t_7[arg24] and not t_7[arg24][4] then
                        v31 = t_2.hugeAnimReplacement:Clone()
                    end
                elseif t_7[arg24] and not t_7[arg24][4] then
                    v31 = t_2.hugeAnimReplacement:Clone()
                end
            end

            replicateToClient(arg24, v30)
            replicateToClient(arg24, RemoteFunction)
            replicateToClient(arg24, CharRepl_RemoteEvent)
            local t_9 = {}

            if v31 then
                replicateToClient(arg24, v31)
                t_9[arg23.currentAnim] = v31
            end

            arg17.anim = v31
            arg23.playersData[arg24] = {
                remote = CharRepl_RemoteEvent,
                destRemote = RemoteFunction,
                model = v30,
                extraAssets = t_9
            }
            CharacterReplication:FireClient(
                arg24,
                v30,
                arg17,
                CharRepl_RemoteEvent,
                RemoteFunction,
                v13,
                arg23.owner
            )
        end

        writePropsAndStuffFromAnim(t_8, v18)

        if v15 then
            v17 = v15.OnServerEvent:Connect(function(arg25, arg26, ...) -- line: 311
                -- upvalues:
                --  [1] v10 (ref)
                --  [2] t_3 (ref)
                --  [3] t_1 (ref)
                --  [4] t_8 (copy)

                if arg25 ~= v10 then
                    arg25:Kick("Banned. #real")

                    return
                end

                if not t_3[arg26 or ""] then
                    return
                end

                local v32 = t_1[arg26]

                if v32 then
                    for key_5, val_3 in t_8.playersData do
                        v32(t_8, key_5, val_3, ...)
                    end

                    return
                end

                for key_6, val_4 in t_8.playersData do
                    val_4.remote:FireClient(key_6, arg26, ...)
                end
            end)
        end

        for key_7, _ in t_4 do
            if t_8:CanAddPlayer(key_7) then
                t_8:AddPlayer(key_7)
            end
        end

        table.insert(t_5, t_8)
        t_6[v10] = t_8

        return t_8
    end

    game:GetService("Players").PlayerRemoving:Connect(function(arg27) -- line: 341
        -- upvalues:
        --  [1] t_4 (copy)
        --  [2] t_7 (copy)
        --  [3] t_5 (copy)

        t_4[arg27] = nil
        t_7[arg27] = nil

        for _, val_6 in t_5 do
            if val_6.players[arg27] then
                val_6:RemovePlayer(arg27)
            end
        end
    end)
    CharacterReplication.OnServerEvent:Connect(function(arg28, arg29, ...) -- line: 352
        -- upvalues:
        --  [1] t_5 (copy)
        --  [2] t_7 (copy)
        --  [3] t_4 (copy)

        local t_11 = { ... }

        if arg29 == "Sync" then
            for _, val_7 in t_5 do
                if not val_7:CanAddPlayer(arg28) then
                    if val_7.players[arg28] then
                        val_7:RemovePlayer(arg28)
                    end
                else
                    val_7:AddPlayer(arg28)
                end
            end

            return
        end

        if arg29 == "UpdPreferences" then
            t_7[arg28] = t_11[1]
            t_4[arg28] = t_11[1][1] or nil
        end
    end)
    Logger_m.log("Server replicator initialized!")
    ReplicatedStorage:SetAttribute("InitializedReplication", true)

    return t
end

repeat
    task.wait()
until ReplicatedStorage:GetAttribute("InitializedReplication") == true

t.ReplicationEnabled = workspace:GetAttribute("ReplicationEnabled") or t.ReplicationEnabled

if v1 then
    v1.init()
end

local DataManager_m = require(ReplicatedStorage.Modules.Data.DataManager)
local LocalPlayer = Players.LocalPlayer
local t_12 = {}
local t_13 = {}

function t.LinkPlayer(_, arg31, arg32) -- line: 381
    -- upvalues:
    --  [1] t_12 (copy)

    t_12[arg31] = arg32
end

function t.UnlinkPlayer(_, arg34) -- line: 385
    -- upvalues:
    --  [1] t_12 (copy)

    t_12[arg34] = nil
end

function t.UnlinkAll(_) -- line: 389
    -- upvalues:
    --  [1] t_12 (copy)

    table.clear(t_12)
end

function t.GetCharFromPlr(_, arg37) -- line: 393
    -- upvalues:
    --  [1] t_13 (copy)

    return t_13[arg37]
end

function t.SendCharSettingsUpdate(arg38) -- line: 397
    -- upvalues:
    --  [1] CharacterReplication (copy)
    --  [2] t_2 (copy)

    if not arg38.ReplicationEnabled then
        return
    end

    CharacterReplication:FireServer(
        "UpdPreferences",
        { t_2.loadCharacters, t_2.loadExtCharacters, t_2.loadStageCharacters, t_2.loadExtHugeRigs }
    )
end

function t.SetSettings(arg39, arg40) -- line: 407
    -- upvalues:
    --  [1] t_2 (copy)

    local t_14 = {}

    for key_10, val_8 in arg40 do
        if val_8 ~= t_2[key_10] then
            t_14[key_10] = true
        end

        t_2[key_10] = val_8
    end

    if t_14.loadCharacters or t_14.loadExtCharacters or t_14.loadStageCharacters then
        arg39:SendCharSettingsUpdate()
        arg39:SyncWithServer()
    end
end

function t.SyncWithServer(arg41) -- line: 422
    -- upvalues:
    --  [1] CharacterReplication (copy)

    if not arg41.ReplicationEnabled then
        return
    end

    CharacterReplication:FireServer("Sync")
end

StageAnimReplication.OnClientEvent:Connect(function(u2: userdata, s1: string?, n1: number?) -- line: 427
    -- upvalues:
    --  [1] t_12 (copy)

    if not t_12[u2] then
        return
    end

    t_12[u2]:Play(s1, "", n1, false)
end)
CharacterReplication.OnClientEvent:Connect(function(
    arg42: any,
    arg43: any,
    u3: userdata,
    u4: userdata,
    arg44: any,
    arg45: any
) -- line: 433
    -- upvalues:
    --  [1] LocalPlayer (copy)
    --  [2] Character_m (copy)
    --  [3] t_13 (copy)
    --  [4] v1 (copy)
    --  [5] Players (copy)

    local v34 = arg45 == LocalPlayer
    local v35 = arg43.isEmote or arg43.emote
    local v36 = nil
    arg43.charModel = arg42
    arg42.Parent = Character_m:GetRigStorage()
    local v37 = Character_m.newWithProps(arg43)
    v37.destroyChar = true

    if arg45 then
        t_13[arg45] = v37
    end

    local function doParentStuff() -- line: 448
        -- upvalues:
        --  [1] v37 (copy)
        --  [2] arg44 (copy)
        --  [3] arg42 (copy)
        --  [4] Character_m (ref)
        --  [5] v34 (copy)
        --  [6] v1 (ref)
        --  [7] v35 (copy)
        --  [8] arg43 (copy)

        if not v37.alive then
            return
        end

        if arg44 then
            local v38 = arg42
            local Parent = arg44.Parent
            local v39 = workspace

            if Parent ~= Character_m:GetRigStorage() or not v39 then
                v39 = arg44.Parent
            end

            v38.Parent = v39

            if v34 then
                local PrimaryPart = arg44.PrimaryPart
                local _ = Character_m:GetRigStorage()

                for _, descendant_1 in arg44:GetDescendants() do
                    if not descendant_1:IsA("BasePart") then
                        if descendant_1:IsA("FaceInstance") and (descendant_1 ~= PrimaryPart and descendant_1.Name ~= "HumanoidRootPart") then
                            descendant_1.Transparency = 1
                        elseif not descendant_1:IsA("LayerCollector") then
                            if not descendant_1:IsA("Beam") then
                                if descendant_1:IsA("ParticleEmitter") then
                                    descendant_1.Enabled = false
                                end
                            else
                                descendant_1.Enabled = false
                            end
                        else
                            descendant_1.Enabled = false
                        end
                    elseif descendant_1 ~= PrimaryPart and descendant_1.Name ~= "HumanoidRootPart" then
                        descendant_1.Transparency = 1
                    elseif not descendant_1:IsA("LayerCollector") then
                        if not descendant_1:IsA("Beam") then
                            if descendant_1:IsA("ParticleEmitter") then
                                descendant_1.Enabled = false
                            end
                        else
                            descendant_1.Enabled = false
                        end
                    else
                        descendant_1.Enabled = false
                    end
                end
            else
                arg44.Parent = nil
            end
        else
            arg42.Parent = workspace
        end

        if v34 and v1 and v35 then
            v1.localCharCreated(v37)
        end

        if v1 and v35 then
            v1.charCreated(v37, arg43.stage)
        end
    end

    if v34 then
        v37:postAsyncAnimLoad(doParentStuff)
    else
        doParentStuff()
    end

    if v35 then
        v37:postAsyncAnimLoad(function() -- line: 487
            -- upvalues:
            --  [1] v37 (copy)

            v37:Dance()
            v37:Play("Intro")
        end)
    end

    local v41 = u3.OnClientEvent:Connect(function(arg46, ...) -- line: 493
        -- upvalues:
        --  [1] v37 (copy)

        v37[arg46](v37, ...)
    end)

    function u4.OnClientInvoke() -- line: 497
        -- upvalues:
        --  [1] u4 (copy)
        --  [2] v34 (copy)
        --  [3] v1 (ref)
        --  [4] v35 (copy)
        --  [5] v37 (copy)
        --  [6] v41 (copy)
        --  [7] v36 (ref)
        --  [8] arg44 (copy)
        --  [9] arg45 (copy)
        --  [10] Players (ref)

        function u4.OnClientInvoke() -- line: 498
        end

        task.spawn(function() -- line: 501
            -- upvalues:
            --  [1] v34 (ref)
            --  [2] v1 (ref)
            --  [3] v35 (ref)
            --  [4] v37 (ref)
            --  [5] v41 (ref)
            --  [6] v36 (ref)
            --  [7] arg44 (ref)
            --  [8] arg45 (ref)
            --  [9] Players (ref)

            if v34 and v1 and v35 then
                v1.localDestroyed(v37)
            end

            v41:Disconnect()
            v37:Destroy()

            if v36 then
                v36:Disconnect()
                v36 = nil
            end

            if v34 then
                local PrimaryPart_1 = arg44.PrimaryPart

                for _, descendant_2 in arg44:GetDescendants() do
                    if not descendant_2:IsA("BasePart") then
                        if descendant_2:IsA("FaceInstance") and (descendant_2 ~= PrimaryPart_1 and descendant_2.Name ~= "HumanoidRootPart") then
                            descendant_2.Transparency = 0
                        elseif not descendant_2:IsA("LayerCollector") then
                            if not descendant_2:IsA("Beam") then
                                if descendant_2:IsA("ParticleEmitter") then
                                    descendant_2.Enabled = true
                                end
                            else
                                descendant_2.Enabled = true
                            end
                        else
                            descendant_2.Enabled = true
                        end
                    elseif descendant_2 ~= PrimaryPart_1 and descendant_2.Name ~= "HumanoidRootPart" then
                        descendant_2.Transparency = 0
                    elseif not descendant_2:IsA("LayerCollector") then
                        if not descendant_2:IsA("Beam") then
                            if descendant_2:IsA("ParticleEmitter") then
                                descendant_2.Enabled = true
                            end
                        else
                            descendant_2.Enabled = true
                        end
                    else
                        descendant_2.Enabled = true
                    end
                end

                return
            end

            if arg44 then
                if arg45 then
                    if arg45.Character == arg44 then
                        if not Players:IsAncestorOf(arg45) then
                            pcall(function() -- line: 521
                                -- upvalues:
                                --  [1] arg44 (ref)

                                arg44:Destroy()
                            end)

                            return
                        end

                        arg44.Parent = workspace

                        return
                    else
                        pcall(function() -- line: 521
                            -- upvalues:
                            --  [1] arg44 (ref)

                            arg44:Destroy()
                        end)

                        return
                    end
                else
                    pcall(function() -- line: 521
                        -- upvalues:
                        --  [1] arg44 (ref)

                        arg44:Destroy()
                    end)

                    return
                end
            else
                pcall(function() -- line: 521
                    -- upvalues:
                    --  [1] arg44 (ref)

                    arg44:Destroy()
                end)

                return
            end
        end)
    end
end)
local _ = DataManager_m:GetData()
t_2.loadCharacters = true
t_2.loadExtCharacters = true
t_2.loadStageCharacters = true
t:SendCharSettingsUpdate()

if t_2.loadCharacters and t_2.loadExtCharacters then
    t:SyncWithServer()
end

Logger_m.log(
    "Client initialized,",
    "Enabled?:",
    t.ReplicationEnabled,
    "Emote replication support?:",
    t.SupportEmotes
)

return t
