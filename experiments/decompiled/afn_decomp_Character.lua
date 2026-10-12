local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local _ = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local _ = game["Run Service"]:IsServer()
game:GetService("AnimationClipProvider")
local CharacterReplicator_m = nil
local Signal_m = require(ReplicatedStorage.Modules.Lib.Signal)
local VarTweener_m = require(ReplicatedStorage.Modules.Main.VarTweener)
local CacheService_m = require(ReplicatedStorage.Modules.Main.CacheService)
local AppearanceManager_m = require(ReplicatedStorage.Modules.Other.AppearanceManager)
local DataManager_m = require(ReplicatedStorage.Modules.Data.DataManager)
local RigAssets_m = require(ReplicatedStorage.Modules.Main.RigAssets)
local Logger_m = require(ReplicatedStorage.Modules.Other.Logger)
require(script.RewriteStuff.RigInfo)
local v3 = false
local GetDescription = AppearanceManager_m.getDescription
local t = { __minz = true }

function t.__index(arg1, arg2) -- line: 49
    -- upvalues:
    --  [1] t (copy)

    if arg2 == "Parent" then
        if arg1.charModel then
            return arg1.charModel.Parent
        end

        return
    else
        return t[arg2]
    end
end

function t.__newindex(arg3, arg4, arg5) -- line: 56
    if arg4 == "Parent" then
        if arg3.charModel then
            arg3.charModel.Parent = arg5
        end

        return
    end

    return (rawset(arg3, arg4, arg5))
end

local v4 = RunService:IsServer()
local v5 = RunService:IsStudio()

if game.PlaceId ~= 13042469490 then
    local _ = false
else
    local _ = true
end

local v8 = DataManager_m:GetLocalData()
local Characters = ReplicatedStorage.Characters
local Emotes = ReplicatedStorage.Assets.Emotes
local Animations = ReplicatedStorage.Assets.Animations
local v9 = game
local v10 = v9:FindFirstChild("RigStorage") or Instance.new("Folder")
v10.Name = "RigStorage"
v10.Parent = v9
t.RigStorage = v9

if CacheService_m.AnimationDummy then
    CacheService_m.AnimationDummy.Parent = v10
end

local t_1 = {
    R6 = Characters:FindFirstChild("DefaultR6"),
    R15 = Characters:FindFirstChild("DefaultR15"),
    D15 = Characters:FindFirstChild("DefaultD15")
}
local t_2 = { useFaces = true, useProps = true, useReqProps = true, extraIds = {} }
local t_3 = { Left = "Left", Down = "Down", Up = "Up", Right = "Right" }
local t_5 = {
    [Enum.AccessoryType.Face] = true,
    [Enum.AccessoryType.Eyebrow] = true,
    [Enum.AccessoryType.Eyelash] = true
}
local t_6 = {}

for key, val in {
    Left = { "Left", "rLeft", "rLeft2", "Left2" },
    Down = { "Down", "rDown", "rDown2", "Down2" },
    Up = { "Up", "rUp", "rUp2", "Up2", "Square", "Plus" },
    Right = { "Right", "rRight", "rRight2", "Right2" }
} do
    for _, val_1 in val do
        t_6[val_1] = key
    end
end

local _ = {}
local t_8 = { "", "ALT", "MISS", "DODGE", "SHOOT" }
local t_9 = { "", "ALT" }
local t_10 = {}
t_10.R15 = {
    "Head",
    "UpperTorso",
    "LowerTorso",
    "LeftUpperArm",
    "LeftLowerArm",
    "LeftHand",
    "RightUpperArm",
    "RightLowerArm",
    "RightHand",
    "LeftUpperLeg",
    "LeftLowerLeg",
    "LeftFoot",
    "RightUpperLeg",
    "RightLowerLeg",
    "RightFoot",
    "HumanoidRootPart"
}
t_10.R6 = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "HumanoidRootPart" }

function getAnimations(u1: userdata, s1: string?) -- line: 158
    -- upvalues:
    --  [1] v5 (copy)
    --  [2] Logger_m (copy)

    if not u1 then
        return {}
    end

    local v13 = typeof(u1) == "Instance" and u1:FindFirstChild(s1 or "") or u1
    u1 = v13
    v13 = {}

    for _, val_2 in u1:QueryDescendants(">Animation") do
        v13[val_2.Name] = {
            Id = val_2.AnimationId,
            Speed = tonumber(val_2:GetAttribute("Speed")) or 1,
            Priority = val_2:GetAttribute("Priority"),
            Looped = val_2:GetAttribute("Looped")
        }
    end

    if v5 then
        for _, val_3 in u1:QueryDescendants(">AnimationClip") do
            for _, val_4 in val_3:QueryDescendants("Pose") do
                if val_4.EasingStyle == Enum.PoseEasingStyle.Constant and val_4.EasingDirection ~= Enum.PoseEasingDirection.Out then
                    Logger_m.warn(
                        "AnimationClip has wrongly exported constant ease dir, changing to out for intended preview (Fix this before publishing!)"
                    )
                    val_4.EasingDirection = Enum.PoseEasingDirection.Out
                end
            end

            v13[val_3.Name] = {
                Id = game:GetService("AnimationClipProvider"):RegisterAnimationClip(val_3),
                Speed = tonumber(val_3:GetAttribute("Speed")) or 1,
                Priority = val_3:GetAttribute("Priority"),
                Looped = val_3:GetAttribute("Looped")
            }
        end
    end

    return v13
end

t.IdlePrefixes = t_9
t.GetAnimations = getAnimations
t.AnimationPrefixes = t_8

function getId(arg6) -- line: 203
    return tonumber(arg6) and "rbxassetid://" .. arg6 or arg6
end

function hasProperty(arg7, arg8) -- line: 207
    local Success, _ = pcall(function() -- line: 208
        -- upvalues:
        --  [1] arg7 (copy)
        --  [2] arg8 (copy)

        arg7[arg8] = arg7[arg8]
    end)

    return Success
end

function getInstance(arg9, arg10) -- line: 214
    if arg10 == nil then
        return
    end

    local v15 = arg9

    for index = 1, #arg10 do
        local v16 = arg10[index]

        if not v15:FindFirstChild(v16) then
            break
        end

        v15 = v15:FindFirstChild(v16)
    end

    return v15
end

function getRealName(arg11, arg12) -- line: 225
    if arg12 == nil or arg12.Parent == nil then
        return nil
    end

    local t_13 = {}
    table.insert(t_13, 1, arg12.Name)
    local Parent = arg12.Parent

    if Parent ~= arg11 then
        table.insert(t_13, 1, Parent.Name)

        repeat
            if Parent.Parent ~= arg11 then
                Parent = Parent.Parent
                table.insert(t_13, 1, Parent.Name)
            end
        until Parent.Parent == arg11
    end

    return t_13
end

function reverseTable(arg13) -- line: 245
    local t_14 = table.clone(arg13)

    for index_1 = 1, math.floor(#t_14 / 2) do
        local v18 = #t_14 - index_1 + 1
        t_14[index_1], t_14[v18] = t_14[v18], t_14[index_1]
    end

    return t_14
end

function getFullPath(arg14) -- line: 256
    local t_15 = {}
    local v19 = arg14

    if v19.Name and v19 then
        repeat
            if v19.Name and v19 then
                table.insert(t_15, v19.Name)
                v19 = v19.Parent
            end
        until v19.Name == "PreloadedRig"
    else
        return t_15
    end
end

function findObject(arg15, arg16) -- line: 272
    local v20 = arg15

    if #arg16 <= 0 then
        return v20
    end

    local v21 = 1
    local v22 = reverseTable(arg16)

    repeat
        v20 = v20:FindFirstChild(v22[v21])
        v21 += 1

        if v20 == nil then
            break
        end
    until v21 == #v22 + 1

    return v20
end

local GetImageID = ReplicatedStorage:WaitForChild("Events"):WaitForChild("GetImageID")
local _ = game:GetService("MarketplaceService")
local _ = game:GetService("InsertService")
local v23 = if v4 then task.wait(2) and shared.getImageId or function() -- line: 291
    return "rbxassetid://0"
end else function() -- line: 291
    return "rbxassetid://0"
end

function getDecalFromFaceId(arg17) -- line: 293
    -- upvalues:
    --  [1] v4 (copy)
    --  [2] v23 (copy)
    --  [3] GetImageID (copy)

    if arg17 == 0 then
        return "rbxasset://textures/face.png"
    end

    return v4 and v23(arg17) or GetImageID:InvokeServer(arg17) or "rbxassetid://" .. arg17
end

function findFaceInHead(u2: userdata) -- line: 299
    return u2:FindFirstChildOfClass("Decal")
end

function getFaceFromCharacter(arg18) -- line: 303
    if arg18:FindFirstChild("Head") then
        return findFaceInHead(arg18.Head)
    end
end

function loadDescription(
    u3: userdata,
    u4: userdata?,
    u5: userdata?,
    t1: table?,
    t2: table?
) -- line: 309
    -- upvalues:
    --  [1] Logger_m (copy)
    --  [2] t_10 (copy)
    --  [3] v8 (copy)
    --  [4] Characters (copy)

    local v26 = u4 or u3 and u3:FindFirstChild("Humanoid")
    u4 = v26
    v26 = u3 and u3:FindFirstChild("AnimationController") or nil

    if v26 ~= nil then
        return Logger_m.log("Character is a mesh rig, continuing...")
    end

    if not u3 then
        return Logger_m.log("No character found!")
    end

    if not u4 then
        return Logger_m.log("No humanoid found!")
    end

    if not u5 then
        return Logger_m.log("No description found!")
    end

    local v27 = t1 or {}
    local v28 = v27
    v27 = t2 or {}
    local v29 = v27
    local v30 = v29.suffix or ""
    local now = tick()
    local t_16 = {}
    local t_17 = {}
    local t_18 = {}
    local v31 = t_10
    local v32 = v31[u4.RigType.Name] or {}
    v31 = getFaceFromCharacter(u3)

    if v31 then
        v31 = if v31.Texture == "rbxassetid://0" then nil else if v31.Texture == "" then nil else if v31.Transparency ~= 1 then v31 else nil
    end

    local v33 = #u3:QueryDescendants("[$Face]") > 0 and true
    local t_20 = {}
    local t_21 = {}

    if v8 and not v8.CameraFlash then
        table.insert(t_21, "[$Flashing]")
    end

    if not v28.useFaces then
        table.insert(t_21, "[$Face]")
    end

    if not v28.useProps then
        table.insert(t_21, "[$Prop]")
    end

    if not v28.useReqProps then
        table.insert(t_21, "[$RequiredProp]")
    end

    for _, val_5 in u3:QueryDescendants(table.concat(t_21, ",")) do
        if val_5:IsDescendantOf(u3) then
            pcall(function() -- line: 369
                -- upvalues:
                --  [1] val_5 (copy)

                val_5:Destroy()
            end)
        end
    end

    for _, val_6 in u3:QueryDescendants("BasePart") do
        val_6.CanCollide = false
        val_6.CanQuery = false
        val_6.CanTouch = false

        if table.find(v32, val_6.Name) and val_6.Parent == u3 then
            local t_22 = { Transparency = nil }
            local Transparency = val_6.Transparency
            local Name_3 = val_6.Name
            t_22.Transparency = Transparency
            t_17[Name_3] = t_22
        end
    end

    for _, val_7 in u3:QueryDescendants("Accessory") do
        if val_7.AccessoryType == Enum.AccessoryType.Face or val_7.AccessoryType == Enum.AccessoryType.Eyebrow or val_7.AccessoryType == Enum.AccessoryType.Eyelash then
            t_20[#t_20 + 1] = val_7
        end
    end

    task.wait()
    local v38

    if not v28.useFaces and not v31 and v33 then
        v38 = Instance.new("Decal")
        v38.Transparency = 0
        v38.Texture = getDecalFromFaceId(u4:GetAppliedDescription().Face)
        v38.Parent = u3:FindFirstChild("Head")
        v31 = v38
    end

    v38 = not v28["Head_Part" .. v30]

    if v38 then
        v38 = not v31

        if v38 then
            v38 = u3:FindFirstChild("Head")
        end
    end

    if v38 then
        u5.Face = 0
        u5.Head = 0
    end

    require(script.RewriteStuff.NormalizeRig)(u3)
    require(script.RewriteStuff.ApplyDescription)(u3, u5)

    for key_8, val_8 in t_16 do
        if val_8.Part0 then
            key_8.Part0 = u3:FindFirstChild(val_8.Part0)
        end

        if val_8.Part1 then
            key_8.Part1 = u3:FindFirstChild(val_8.Part1)
        end

        if key_8.Part0 then
            if key_8.Part0 ~= u3.PrimaryPart then
                key_8.Part0.Anchored = false
            end
        end

        if key_8.Part1 then
            if key_8.Part1 ~= u3.PrimaryPart then
                key_8.Part1.Anchored = false
            end
        end
    end

    for key_9, val_9 in t_17 do
        local v43 = u3:FindFirstChild(key_9)

        if v43 then
            if key_9 == "Head" then
                if not v43:FindFirstChildOfClass("FaceControls") then
                    for key_10, val_10 in val_9 do
                        v43[key_10] = val_10
                    end
                end
            else
                for key_11, val_11 in val_9 do
                    v43[key_11] = val_11
                end
            end
        end
    end

    for key_12, val_12 in t_18 do
        if key_12 then
            if key_12.Parent and val_12 then
                if val_12.Parent then
                    key_12.Parent = val_12
                end
            end
        end
    end

    local v49

    if not v28["Head_Part" .. v30] and not v31 and u3:FindFirstChild("Head") then
        local Head = u3.Head

        if Head.Transparency < 1 then
            local v46 = Characters.DefaultHead:Clone()
            v46.Size *= v29.headScale or 1
            v46.Color = Head.Color
            v46.Transparency = Head.Transparency
            v46.CFrame = Head.CFrame
            local WeldConstraint = Instance.new("WeldConstraint")
            WeldConstraint.Part0 = Head
            WeldConstraint.Part1 = v46
            WeldConstraint.Parent = Head
            v46.Parent = Head

            for _, val_13 in t_20 do
                if val_13:IsDescendantOf(u3) then
                    function v49() -- line: 543
                        -- upvalues:
                        --  [1] val_13 (copy)

                        val_13:Destroy()
                    end

                    pcall(v49)
                end
            end

            Head.Transparency = 1
        end
    end

    table.clear(t_17)
    table.clear(t_18)
    table.clear(t_16)
    local v52, v63, v68, v78

    for key_14, val_14 in v28 do
        local v51, v52 = key_14:gsub("_Part" .. v30, "")
        v49 = "ReplaceRoot"
        local v50 = if key_14 ~= v49 .. v30 then false else true

        if v52 >= 1 then
            local v55 = u3:FindFirstChild(v51 or "")

            if v55 and v55.ClassName == "MeshPart" then
                for _, child in v55:GetChildren() do
                    if child:IsA("LayerCollector") then
                        child.Enabled = false
                    elseif child:IsA("FaceInstance") then
                        child.Transparency = 1
                    end
                end

                v55.Transparency = 1
            end

            function v49(u6: userdata, t3: table) --[[ resolvePath ]] -- line: 576
                local v61 = { u6 }

                for _, val_15 in t3 do
                    if val_15 ~= "" then
                        local t_23 = {}

                        for _, val_16 in v61 do
                            if val_15 == "*" then
                                for _, child_1 in val_16:GetChildren() do
                                    table.insert(t_23, child_1)
                                end
                            else
                                local v62 = val_16:FindFirstChild(val_15)

                                if v62 then
                                    table.insert(t_23, v62)
                                end
                            end
                        end

                        v61 = t_23

                        if #v61 == 0 then
                            break
                        end
                    end
                end

                return v61
            end

            v63 = string.split(val_14, ",")

            if #v63 >= 1 then
                for _, val_17 in v63 do
                    local v66 = string.match(val_17, "^%s*(.-)%s*$") or val_17
                    local v67 = string.split(v66, "/")
                    v68 = "_Props"
                    local v69 = u3:FindFirstChild(v68)
                    local v70 = {}

                    if v69 then
                        v68 = v49
                        v70 = v68(v69, v67)
                    end

                    v68 = #v70

                    if v68 == 0 then
                        v68 = v49
                        v70 = v68(u3, v67)
                    end

                    v68 = #v70

                    if v68 == 0 then
                        v68 = Logger_m.log
                        v68("No", v66, "found!")
                    else
                        v68 = {}

                        local function collectPartsAndMeshes(u7: userdata) -- line: 627
                            -- upvalues:
                            --  [1] v68 (copy)
                            --  [2] collectPartsAndMeshes (copy)

                            if not u7:IsA("BasePart") then
                                if u7:IsA("SpecialMesh") then
                                    table.insert(v68, u7)

                                    return
                                end

                                if not u7:IsA("Model") then
                                    if u7:IsA("Folder") then
                                        for _, child_2 in u7:GetChildren() do
                                            collectPartsAndMeshes(child_2)
                                        end
                                    end
                                else
                                    for _, child_3 in u7:GetChildren() do
                                        collectPartsAndMeshes(child_3)
                                    end
                                end

                                return
                            else
                                table.insert(v68, u7)

                                return
                            end
                        end

                        for _, val_18 in v70 do
                            collectPartsAndMeshes(val_18)
                        end

                        for _, val_19 in v68 do
                            v78 = pcall
                            local v79
                            v78, v79 = v78(function() -- line: 643
                                -- upvalues:
                                --  [1] u5 (copy)
                                --  [2] v51 (copy)
                                --  [3] val_19 (copy)

                                local v76 = u5 ~= nil and u5[v51 .. "Color"] or Color3.new()

                                if val_19:IsA("BasePart") then
                                    val_19.Color = v76

                                    return
                                end

                                if val_19:IsA("SpecialMesh") then
                                    val_19.VertexColor = Vector3.new(v76.R, v76.G, v76.B)
                                end
                            end)

                            if not v78 then
                                local v80 = v79
                                Logger_m.log(`Applying Color failed, response: {v80}`)
                            end

                            if v51 == "Head" then
                                v78 = nil

                                if val_19:IsA("BasePart") then
                                    v78 = findFaceInHead(val_19)
                                elseif val_19:IsA("SpecialMesh") then
                                    if val_19.Parent then
                                        if val_19.Parent:IsA("BasePart") then
                                            v78 = findFaceInHead(val_19.Parent)
                                        end
                                    end
                                end

                                if v78 then
                                    task.spawn(function() -- line: 666
                                        -- upvalues:
                                        --  [1] v31 (ref)
                                        --  [2] v78 (ref)
                                        --  [3] u5 (copy)

                                        if v31 then
                                            v78.Texture = v31.Texture

                                            return
                                        end

                                        v78.Texture = getDecalFromFaceId(u5.Face)
                                    end)
                                end
                            end
                        end
                    end
                end
            end
        elseif v50 and val_14 == true then
            v63 = if u4.RigType.Name ~= "R6" then "LowerTorso" else "Torso"
            local v92 = u3:FindFirstChild(v63)

            if v92 then
                local Root = v92:FindFirstChild("Root")

                if Root then
                    task.delay(0, function() -- line: 688
                        -- upvalues:
                        --  [1] Root (copy)

                        task.wait()
                        Root.Enabled = false
                    end)
                end
            end
        end
    end

    if v28["Color_Offset_Target" .. v30] and v28["Color_Offset" .. v30] then
        local v97 = string.split(v28["Color_Offset_Target" .. v30], ",")

        if #v97 >= 1 then
            local v101, v99

            for _, val_20 in v97 do
                local v98 = string.split(val_20, "/")

                if #v98 > 1 then
                    v99 = u3

                    for _, val_21 in v98 do
                        if v99 == nil then
                            break
                        end

                        if v99:FindFirstChild(val_21) then
                        end
                    end

                    v101 = v99
                else
                    v99 = u3:FindFirstChild(val_20, true)
                    v101 = v99
                end

                if v101 then
                    v99 = if v101.ClassName == "Model" then v101:GetChildren() or { v101 } else {
                        v101
                    }

                    for _, val_22 in v99 do
                        local Success_1, Result_1 = pcall(function() -- line: 724
                            -- upvalues:
                            --  [1] val_22 (copy)
                            --  [2] v28 (ref)
                            --  [3] v30 (copy)

                            val_22.Color = Color3.new(
                                math.clamp(val_22.Color.R + v28["Color_Offset" .. v30].X, 0, 1),
                                math.clamp(val_22.Color.G + v28.Color_Offset.Y, 0, 1),
                                (math.clamp(val_22.Color.B + v28.Color_Offset.Z, 0, 1))
                            )
                        end)

                        if not Success_1 then
                            Logger_m.warn(`Applying Color failed, response: {Result_1}`)
                        end
                    end
                end
            end
        end
    end

    local Log_1 = Logger_m.log
    local v106 = tick() - now
    Log_1(`Took {v106} seconds to load appearance!`)

    return { rootWelds = {} }
end

function mergeTracks(arg19) -- line: 746
    if #arg19 == 0 then
        return
    end

    local t_25 = { tracks = arg19 }
    local t_26 = { __index = nil, __newindex = nil }

    function t_26.__index(_, arg21) -- line: 751
        -- upvalues:
        --  [1] arg19 (copy)

        local v107 = arg19[1][arg21]

        if type(v107) == "function" then
            local t_27 = { __call = nil }

            function t_27.__call(...) -- line: 754
                -- upvalues:
                --  [1] arg19 (ref)
                --  [2] arg21 (copy)

                for _, val_23 in arg19 do
                    val_23[arg21](val_23, unpack({ ... }, 3, select("#", ...)))
                end
            end

            return (setmetatable({}, t_27))
        end

        return v107
    end

    function t_26.__newindex(_, arg23, arg24) -- line: 763
        -- upvalues:
        --  [1] arg19 (copy)

        for _, val_24 in arg19 do
            val_24[arg23] = arg24
        end
    end

    return (setmetatable(t_25, t_26))
end

function t.LoadAnimationsOnAnimator(arg25, arg26, arg27) -- line: 771
    -- upvalues:
    --  [1] t_3 (copy)
    --  [2] t_9 (copy)

    local t_29 = {}
    local t_30 = {}

    for key_31, val_25 in t_3 do
        for _, val_26 in arg25.prefixes do
            local v109 = key_31 .. val_26
            local v110 = val_25 .. val_26
            local v111 = arg26[v110]
            local v112 = arg25.optionalPrefixes[val_26]

            if not v111 then
                v111 = arg26[val_25]
            end

            if v111 then
                local v113 = if v111 ~= arg26[v110] then key_31 else v109 or key_31

                if v113 ~= key_31 or not v112 then
                    t_30[v109] = t_30[v113] or arg25:AddAnimation(
                        v109,
                        v111.Id,
                        v111.Speed,
                        false,
                        Enum.AnimationPriority.Movement,
                        arg27
                    )
                    table.insert(t_29, v113)
                end
            end
        end
    end

    for _, val_27 in if not arg26.IdleLeft then if arg26.IdleRight then { "IdleLeft", "IdleRight" } or {
        arg25.idleName
    } else { arg25.idleName } else { "IdleLeft", "IdleRight" } or { arg25.idleName } do
        for _, val_28 in t_9 do
            local v116 = val_27 .. val_28
            local v117 = arg26[v116] or arg26[val_27]

            if v117 then
                local v118 = if v117 ~= arg26[v116] then val_27 else v116 or val_27
                t_30[v116] = t_30[v118] or arg25:AddAnimation(
                    v116,
                    v117.Id,
                    v117.Speed,
                    true,
                    Enum.AnimationPriority.Idle,
                    arg27
                )
                table.insert(t_29, v118)
            end
        end
    end

    for key_35, val_29 in arg26 do
        if not table.find(t_29, key_35) then
            t_30[key_35] = arg25:AddAnimation(
                key_35,
                val_29.Id,
                val_29.Speed,
                val_29.Looped or false,
                Enum.AnimationPriority[val_29.Priority or "Action"],
                arg27
            )
        end
    end

    return t_30
end

function getHumanoid(u8: userdata) -- line: 818
    local Humanoid = u8:FindFirstChild("Humanoid")

    if Humanoid then
        return Humanoid
    end

    local AnimationController = u8:FindFirstChild("AnimationController")

    if AnimationController then
        return AnimationController
    end

    local Humanoid_1 = Instance.new("Humanoid")
    Humanoid_1.Parent = u8
    Humanoid_1.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    Instance.new("Animator").Parent = Humanoid_1

    return Humanoid_1
end

function getAnimator(u9: userdata) -- line: 837
    local v119 = getHumanoid(u9)
    local Animator = v119:FindFirstChild("Animator")

    if Animator then
        return Animator
    end

    local Animator_1 = Instance.new("Animator")
    Animator_1.Parent = v119

    return Animator_1
end

local t_31 = {
    "Play",
    "ManualPlay",
    "LoadAnim",
    "PreloadAnim",
    "AddPrefix",
    "SetAnimationSpeed",
    "SetAnimTrackSpeed"
}

function t.Replicate(arg28, ...) -- line: 857
    -- upvalues:
    --  [1] v4 (copy)

    local Remote = arg28.remote

    if not Remote or v4 then
        return
    end

    Remote:FireServer(...)
end

function t.AddPrefix(arg29, arg30, arg31) -- line: 864
    -- upvalues:
    --  [1] t_3 (copy)

    arg29:Replicate("AddPrefix", arg30, arg31)
    table.insert(arg29.prefixes, arg30)
    arg29.optionalPrefixes[arg30] = arg31

    for _, val_30 in arg29.preloadedAnims or {} do
        local Animations_1 = val_30.animations

        for key_37, _ in t_3 do
            local v121 = key_37 .. arg30
            local v122 = Animations_1[key_37]

            if not Animations_1[v121] and (not arg31 and v122) then
                Animations_1[v121] = v122
                v122.Priority = Enum.AnimationPriority.Movement
            elseif Animations_1[v121] then
                Animations_1[v121].Priority = Enum.AnimationPriority.Movement
            end
        end
    end
end

function t.cloneModel(u10: userdata) -- line: 889
    u10.Archivable = true
    u10 = u10:Clone()
    u10.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    local ForceField = u10:FindFirstChildOfClass("ForceField")

    if ForceField then
        ForceField:Destroy()
    end

    for _, val_32 in u10:QueryDescendants("LuaSourceContainer, LayerCollector") do
        val_32:Destroy()
    end

    local Rig = u10:FindFirstChild("Rig")

    if Rig then
        Rig:Destroy()
    end

    return u10
end

function t.new(
    u11: userdata,
    s2: string?,
    u12: CFrame?,
    arg32: any,
    arg33: any,
    u13: userdata?,
    b1: boolean?,
    t4: table?,
    b2: boolean?,
    b3: boolean?
) -- line: 912
    -- upvalues:
    --  [1] t (copy)

    return if type(u11) == "table" then t.newWithProps(u11) or t.newWithProps(
        {
            charModel = u11,
            animSide = s2,
            position = u12,
            anim = arg32,
            humanoidDescription = arg33,
            replicationRemote = u13,
            isLocked = b1,
            extraIds = t4,
            isEmote = b2,
            isAsync = b3
        }
    ) else t.newWithProps(
        {
            charModel = u11,
            animSide = s2,
            position = u12,
            anim = arg32,
            humanoidDescription = arg33,
            replicationRemote = u13,
            isLocked = b1,
            extraIds = t4,
            isEmote = b2,
            isAsync = b3
        }
    )
end

function t.newWithProps(arg34) -- line: 927
    -- upvalues:
    --  [1] CharacterReplicator_m (ref)
    --  [2] ReplicatedStorage (copy)
    --  [3] v3 (ref)
    --  [4] t (copy)
    --  [5] t_2 (copy)
    --  [6] Logger_m (copy)
    --  [7] t_8 (copy)
    --  [8] Signal_m (copy)
    --  [9] GetDescription (copy)
    --  [10] v4 (copy)
    --  [11] t_31 (copy)

    local v125

    if not CharacterReplicator_m then
        CharacterReplicator_m = require(ReplicatedStorage.Modules.Main.CharacterReplicator)
        v3 = CharacterReplicator_m.ReplicationEnabled
        v125 = t.newWithProps

        return v125(arg34)
    end

    v125 = arg34.charModel or arg34.model
    local v126 = arg34.animSide or arg34.side
    local v127 = arg34.replicationRemote or arg34.remote
    local v128 = arg34.anim or arg34.startingAnim
    local v129 = arg34.humanoidDescription or (arg34.description or arg34.desc)
    local v130 = arg34.isLocked or arg34.locked
    local v131 = arg34.position or arg34.pos
    local v132 = arg34.isEmote or arg34.emote
    local v133 = arg34.isAsync or arg34.async
    local ExtraIds = arg34.extraIds
    local v134 = arg34.animAttributes or (arg34.animAttrs or table.clone(t_2))
    local AsyncDescriptions = arg34.asyncDescriptions
    local Offset = arg34.offset

    if ExtraIds then
        v134.extraIds = ExtraIds
    end

    local v135 = nil

    if v125:IsA("Player") then
        v135 = v125
        v125 = v135.Character

        if not v125 then
            Logger_m.warn("Passed player does not have a character!")

            return nil
        end

        v125.Archivable = true
    end

    local t_33 = {
        locked = v130 or false,
        characterSide = v126,
        defaultCharacterSide = v126,
        player = v135
    }
    t_33.hasPlayer = if v135 then true else false
    t_33.camOffset = CFrame.new()
    t_33.serverOff = CFrame.new()
    local v138 = Offset or CFrame.new()
    t_33.offsetPos = v138
    local v140 = if not v130 then getHeightDiffFromCharacter(v125) else 0
    t_33.heightOff = CFrame.new(0, v140, 0)
    t_33.danced = false
    t_33.idleName = "Idle"
    t_33.zoom, v138 = 1, v131
    local v141

    if not v138 then
        v141 = v125:GetPivot()
    end

    t_33.startPos = v141
    t_33.userId = 0
    t_33.curTweenID = 0
    t_33.charModel = v125
    t_33.char = v125
    t_33.destroyChar = false
    t_33.currentAnim = ""
    t_33.animPrefix = ""
    t_33.remote = v127
    t_33.humanoid = getHumanoid(v125)
    t_33.animator = getAnimator(v125)
    t_33.prioritizeActions = true
    t_33.preloadedRigs = {}
    t_33.preloadedAnims = {}
    t_33.updateCon = nil
    t_33.animAttributes = v134
    t_33.animations = {}
    local v144 = v132 or v126 == "Emote"
    t_33.isEmote = v144
    t_33.currentRig = nil
    t_33.hidden = false
    t_33.prefixes = table.clone(t_8)
    t_33.optionalPrefixes = {}
    t_33.animOptionalPrefixes = {}
    t_33.asyncDescriptions = AsyncDescriptions
    t_33.animationPlayed = Signal_m.new()
    t_33.animationLoaded = Signal_m.new()
    t_33.animationStoppedLoading = Signal_m.new()
    t_33.animationEnded = Signal_m.new()
    t_33.connections = {}
    t_33.sideAttributes = {}
    t_33.alive = true

    if t_33.humanoid then
    end

    local v148

    if type(v129) == "number" then
        t_33.userId = v129
        v148 = GetDescription(v129)
    elseif type(v129) == "table" then
        t_33.userId = v129.id
        v148 = GetDescription(v129.id, v129.type)
    end

    setmetatable(t_33, t)

    if v127 and not v3 then
        if v4 then
            table.insert(t_33.connections, v127.OnServerEvent:Connect(function(arg35, arg36, ...) -- line: 1046
                -- upvalues:
                --  [1] t_33 (copy)
                --  [2] t_31 (ref)

                if arg35 and t_33.player ~= arg35 then
                    return
                end

                if not table.find(t_31, arg36) then
                    return
                end

                t_33[arg36](t_33, ...)
            end))
        else
            table.insert(t_33.connections, v127.OnClientEvent:Connect(function(arg37, ...) -- line: 1053
                -- upvalues:
                --  [1] t_33 (copy)

                t_33[arg37](t_33, ...)
            end))
        end
    end

    t_33.spawnPos = t_33.startPos
    t_33.finalPos = t_33.startPos
    t_33.currentPos = t_33.startPos
    local v151 = if t_33.humanoid.ClassName ~= "Humanoid" then "MeshRig" else t_33.humanoid.RigType.Name or "MeshRig"
    t_33.rigType = v151
    v151 = v148 or t_33.humanoid:GetAppliedDescription()
    t_33.humanoidDescription = v151
    v151 = { humanoid = t_33.humanoid, animator = nil }
    v151.animator, t_33.defaultData = t_33.animator, v151

    if not v3 and v135 and not v4 and v135 ~= game.Players.LocalPlayer then
        local Connections_2 = t_33.connections
        local v152 = v125

        function t_33.GetActiveCharacter(_) -- line: 1093
            -- upvalues:
            --  [1] v152 (ref)

            return v152
        end

        local function setupPosListener(u14: userdata, b4: boolean) -- line: 1098
            -- upvalues:
            --  [1] v152 (ref)
            --  [2] t_33 (copy)
            --  [3] Connections_2 (copy)

            if not u14 then
                return
            end

            v152 = u14

            local function updatePos() -- line: 1104
                -- upvalues:
                --  [1] t_33 (ref)
                --  [2] u14 (copy)
                --  [3] v152 (ref)
                --  [4] b4 (copy)

                task.wait()

                if not t_33.alive then
                    return
                end

                local v153 = u14:GetAttribute("ServerPos") or u14:GetPivot()
                local v154 = u14:GetAttribute("ServerOffset")

                if not v154 then
                    v154 = (t_33.spawnPos or CFrame.new()):Inverse() * v153
                end

                v152 = u14
                local v156 = v154 or CFrame.new()
                t_33.serverOff = v156
                t_33:SetPosition()
                task.defer(function() -- line: 1122
                    -- upvalues:
                    --  [1] b4 (ref)
                    --  [2] u14 (ref)
                    --  [3] t_33 (ref)

                    task.wait()

                    if b4 then
                        u14:PivotTo(t_33.finalPos)
                    end
                end)
            end

            if Connections_2[u14] then
                return updatePos()
            end

            Connections_2[u14] = u14:GetAttributeChangedSignal("ServerPos"):Connect(updatePos)
            table.insert(
                Connections_2,
                u14:GetAttributeChangedSignal("ServerOffset"):Connect(updatePos)
            )
            updatePos()
        end

        task.spawn(setupPosListener, v125)

        if v125:FindFirstChild("Rig") then
            task.spawn(function() -- line: 1148
                -- upvalues:
                --  [1] setupPosListener (copy)
                --  [2] v125 (ref)

                setupPosListener(v125.Rig:WaitForChild("PlayerRig"), true)
            end)
        end

        Connections_2.REPLICATION_ChildAdded = v125.ChildAdded:Connect(function(child_7) -- line: 1153
            -- upvalues:
            --  [1] Connections_2 (copy)
            --  [2] v125 (ref)
            --  [3] setupPosListener (copy)

            if child_7:IsA("Folder") and child_7.Name == "Rig" and not Connections_2[child_7] then
                Connections_2[child_7] = v125.ChildAdded:Connect(function(child_6) -- line: 1156
                    -- upvalues:
                    --  [1] setupPosListener (ref)

                    if child_6:IsA("Model") and child_6.Name == "PlayerRig" then
                        setupPosListener(child_6, true)
                    end
                end)
                setupPosListener(child_7:WaitForChild("PlayerRig"), true)
            end
        end)
    end

    t_33:SetPosition(t_33.startPos, true)

    if v128 and v128 ~= "" then
        if v133 then
            local function v161() -- line: 1173
                -- upvalues:
                --  [1] t_33 (copy)
                --  [2] v128 (copy)

                t_33:LoadAnim(v128)
            end

            task.spawn(v161)
        else
            t_33:LoadAnim(v128)
        end
    end

    return t_33
end

function t.Destroy(arg41) -- line: 1184
    -- upvalues:
    --  [1] Players (copy)
    --  [2] v4 (copy)

    arg41.alive = false

    if arg41.connections then
        for _, val_33 in arg41.connections do
            pcall(function() -- line: 1189
                -- upvalues:
                --  [1] val_33 (copy)

                val_33:Disconnect()
            end)
        end

        arg41.connections = {}
    end

    local _ = pcall

    if arg41.animationLoaded then
        arg41.animationLoaded:DisconnectAll()
    end

    if arg41.animationEnded then
        arg41.animationEnded:DisconnectAll()
    end

    if arg41.animationPlayed then
        arg41.animationPlayed:DisconnectAll()
    end

    if arg41.currentTrackStop then
        arg41.currentTrackStop:Disconnect()
        arg41.currentTrackStop = nil
    end

    if arg41.trackedIdleBeat then
        arg41.trackedIdleBeat:Disconnect()
        arg41.trackedIdleBeat = nil
    end

    arg41:UnloadRig()
    local CharModel = arg41.charModel

    if CharModel then
        local v162 = pcall
        v162(function() -- line: 1215
            -- upvalues:
            --  [1] CharModel (copy)

            CharModel:SetAttribute("ServerOffset", nil)
            CharModel:SetAttribute("ServerPos", nil)
        end)
        v162 = pcall
        v162(function() -- line: 1217
            -- upvalues:
            --  [1] CharModel (copy)
            --  [2] arg41 (copy)

            CharModel:PivotTo(arg41.spawnPos)
        end)
        v162 = arg41.destroyChar

        if v162 then
            v162 = pcall
            v162(function() -- line: 1220
                -- upvalues:
                --  [1] CharModel (copy)

                CharModel:Destroy()
            end)
        else
            v162 = true

            if arg41.hasPlayer then
                if CharModel then
                    if arg41.player ~= nil then
                        if arg41.player.Character == CharModel then
                            if arg41.player.Parent ~= nil then
                                if not Players:IsAncestorOf(arg41.player) then
                                    v162 = false
                                end
                            else
                                v162 = false
                            end
                        else
                            v162 = false
                        end
                    else
                        v162 = false
                    end
                else
                    v162 = false
                end
            end

            if not v4 then
                pcall(function() -- line: 1233
                    -- upvalues:
                    --  [1] CharModel (copy)
                    --  [2] v162 (ref)

                    CharModel.Parent = v162 and workspace or nil
                end)

                if not v162 then
                    pcall(function() -- line: 1235
                        -- upvalues:
                        --  [1] CharModel (copy)

                        CharModel:Destroy()
                    end)
                end
            end
        end
    end

    arg41:UnloadAllFromMemory()
    table.clear(arg41)
    arg41.locked = true
end

function t.AddAnimation(
    t5: table,
    s3: string,
    arg42: any,
    n1: number?,
    b5: boolean?,
    arg43: any,
    u15: userdata?
) -- line: 1250
    -- upvalues:
    --  [1] v4 (copy)
    --  [2] CacheService_m (copy)

    if t5.locked then
        return nil
    end

    local v165 = if not u15 then false else true
    u15 = u15 or t5.animator

    if not u15 then
        return nil
    end

    local Animation = Instance.new("Animation")
    Animation.AnimationId = getId(arg42)
    local v167 = u15:LoadAnimation(Animation)
    v167.Name = s3
    v167:AdjustSpeed(n1 or 1)
    v167:SetAttribute("Speed", n1)

    if arg43 ~= Enum.AnimationPriority.Movement and not v4 then
        CacheService_m.cacheAnimation(Animation)
    end

    v167.Looped = b5 or false
    local v168 = arg43 or v167.Priority
    v167.Priority = v168

    if not v165 then
        t5.animations[s3] = v167
    end

    return v167
end

function t.linkActionsToRate(arg44, arg45) -- line: 1285
    for key_40, val_34 in arg44:GetActions() do
        arg44:SetAnimationSpeed(key_40, (val_34:GetAttribute("Speed") or 1) * arg45 or 1)
    end
end

local AfterImage = ReplicatedStorage.Modules.Assets.Templates.AfterImage
local tweenInfo = TweenInfo.new(0.5)
local t_34 = { { -0.05, 0 }, { 0, 0.05 }, { 0, -0.05 }, { 0.05, 0 } }

function t.CreateAfterImage(
    t6: table,
    n2: number?,
    u16: Color3?,
    n3: number?,
    u17: userdata?
) -- line: 1301
    -- upvalues:
    --  [1] AfterImage (copy)
    --  [2] t_34 (copy)
    --  [3] TweenService (copy)
    --  [4] tweenInfo (copy)

    if t6.locked or not t6.alive then
        return
    end

    local v169 = t6:GetActiveCharacter()
    local v170 = (n2 or 0) + 1
    local v171 = n3 or 1
    local v172 = AfterImage:Clone()
    local v173 = u17 or v169.PrimaryPart
    v172.Parent = v173
    v172.CurrentCamera, v173 = workspace.CurrentCamera, u16
    v173 = v173 or Color3.new(1, 1, 1)
    v172.ImageColor3 = v173
    v169.Archivable = true
    v169:Clone().Parent = v172
    local v174 = t_34[v170] or { 0, 0 }
    TweenService:Create(
        v172,
        tweenInfo,
        { ImageTransparency = 1, Position = UDim2.new(v174[1] * v171, 0, v174[2] * v171, 0) }
    ):Play()
    task.delay(0.5, function() -- line: 1328
        -- upvalues:
        --  [1] v172 (copy)

        v172:Destroy()
    end)

    return v172
end

function t.GetFace(arg46) -- line: 1335
    return getFaceFromCharacter((arg46:GetActiveCharacter()))
end

function t.loadDescription(t7: table, u18: userdata?, t8: table?, t9: table?) -- line: 1340
    return loadDescription(
        t7:GetActiveCharacter(),
        nil,
        u18,
        t8,
        t9
    )
end

function t.HideFace(_) -- line: 1345
end

function t.ShowFace(_) -- line: 1349
end

function t.GetTrack(arg49, arg50) -- line: 1353
    return arg49.animations[arg50]
end

function t.GetIdles(arg51) -- line: 1357
    local t_36 = {}

    for key_41, val_35 in arg51.animations do
        if arg51:isTrackIdle(val_35) then
            t_36[key_41] = val_35
        end
    end

    return t_36
end

function t.GetActions(arg52) -- line: 1369
    local t_37 = {}

    for key_42, val_36 in arg52.animations do
        if not arg52:isTrackDirectional(val_36) and not arg52:isTrackIdle(val_36) then
            t_37[key_42] = val_36
        end
    end

    return t_37
end

function t.SetAnimationSpeed(arg53, arg54, arg55) -- line: 1381
    -- upvalues:
    --  [1] Logger_m (copy)

    local v177 = arg53.animations[arg54]

    if not v177 then
        return Logger_m.log("No animations found!")
    end

    arg53:Replicate("SetAnimationSpeed", arg54, arg55)
    v177:AdjustSpeed(arg55 or v177:GetAttribute("Speed"))
end

function t.SetAnimTrackSpeed(arg56, arg57, arg58, arg59) -- line: 1390
    local v179 = arg56.preloadedAnims[arg57]

    if not v179 then
        return
    end

    local v180 = v179.animations[arg58]

    if not v180 then
        return
    end

    arg56:Replicate("SetAnimTrackSpeed", arg57, arg58, arg59)
    v180:AdjustSpeed(arg59 or v180:GetAttribute("Speed"))
end

function t.GetAnimTrack(arg60, arg61, arg62) -- line: 1402
    local v182 = arg60.preloadedAnims[arg61]

    if not v182 then
        return
    end

    local v183 = v182.animations[arg62]

    if not v183 then
        return
    end

    return v183
end

local v184 = t_1.R15.PrimaryPart.Size.Y / 2 + t_1.R15.Humanoid.HipHeight

function getHeightDiffFromCharacter(arg63) -- line: 1413
    -- upvalues:
    --  [1] v184 (copy)

    local v185 = getHumanoid(arg63)

    if not v185:IsA("Humanoid") then
        return 0
    end

    if v185.RigType == Enum.HumanoidRigType.R15 and arg63.PrimaryPart then
        return arg63.PrimaryPart.Size.Y / 2 + v185.HipHeight - v184
    end

    return 0
end

function t.getHeightDiffFromCharacter(_, arg65) -- line: 1424
    return getHeightDiffFromCharacter(arg65)
end

function parseAccesoryTable(arg66) -- line: 1428
    arg66 = string.split(arg66, ",")

    for index_2 = #arg66, 1, -1 do
        local v186 = arg66[index_2]:gsub(" ", "")
        arg66[index_2] = nil

        if v186 == "%HEAD" then
            arg66.Head = true
            arg66.Hat = true
            arg66.Face = true
            arg66.Hair = true
            arg66.Eyebrow = true
            arg66.Eyelash = true
        else
            arg66[v186] = true
        end
    end

    return arg66
end

local t_38 = {}

for _, val_37 in { "R6", "R15" } do
    local t_39 = {}

    for _, child_8 in t_1[val_37]:GetChildren() do
        if child_8:IsA("BasePart") then
            local t_40 = { Wraps = {}, Attachments = {} }
            local Attachments = t_40.Attachments
            local Wraps = t_40.Wraps

            for _, child_9 in child_8:GetChildren() do
                if child_9:IsA("Attachment") then
                    local v190 = child_9.CFrame.Position / child_8.Size
                    Attachments[child_9.Name] = { v190.X, v190.Y, v190.Z }
                elseif child_9:IsA("WrapTarget") then
                    local _ = child_9.CageOrigin.Position / child_8.Size
                    local _ = child_9.ImportOrigin.Position / child_8.Size
                    Wraps[child_9.Name] = child_9
                end
            end

            if not next(t_40.Wraps) then
                if next(t_40.Attachments) then
                    t_39[child_8.Name] = t_40
                end
            else
                t_39[child_8.Name] = t_40
            end
        end
    end

    t_38[val_37] = t_39
end

function addMissingAttachments(arg67: any, u19: userdata) -- line: 1487
    -- upvalues:
    --  [1] t_38 (copy)

    local v193 = t_38[arg67]

    if not v193 then
        return
    end

    for key_46, val_38 in v193 do
        local v194 = u19:FindFirstChild(key_46)

        if v194 and v194:IsA("BasePart") then
            local Size = v194.Size

            for key_47, val_39 in val_38.Attachments do
                if not v194:FindFirstChild(key_47) then
                    local Attachment = Instance.new("Attachment")
                    Attachment.Name = key_47
                    Attachment.Axis = Vector3.new(1, 0, 0)
                    Attachment.SecondaryAxis = Vector3.new(0, 1, 0)
                    Attachment.CFrame = CFrame.new(
                        val_39[1] * Size.X,
                        val_39[2] * Size.Y,
                        val_39[3] * Size.Z
                    )
                    Attachment.Parent = v194
                end
            end

            if v194:IsA("MeshPart") then
                for key_48, val_40 in val_38.Wraps do
                    if not v194:FindFirstChild(key_48) then
                        val_40:Clone().Parent = v194
                    end
                end
            end
        end
    end
end

function optimizeHumanoids(u20: userdata) -- line: 1520
    if typeof(u20) ~= "Instance" then
        return
    end

    u20.EvaluateStateMachine = false
    u20.RequiresNeck = false
    u20.AutoRotate = false
    u20.AutoJumpEnabled = false
    u20.BreakJointsOnDeath = false
    u20:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    u20:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
    u20:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
    u20:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    u20:SetStateEnabled(Enum.HumanoidStateType.Landed, false)
    u20:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
    u20:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
    u20:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
end

function t.PrepareRig(
    t10: table,
    u21: userdata,
    u22: userdata?,
    s4: string?,
    b6: boolean?,
    b7: boolean?
) -- line: 1540
    -- upvalues:
    --  [1] RigAssets_m (copy)
    --  [2] Logger_m (copy)
    --  [3] t_1 (copy)
    --  [4] v10 (copy)
    --  [5] GetDescription (copy)
    --  [6] t_5 (copy)
    --  [7] t_10 (copy)
    --  [8] Signal_m (copy)

    if not u21 then
        return
    end

    local v195 = u21:FindFirstChild(t10.characterSide) or u21
    local v196 = v195
    local v198

    if s4 then
        v195 = u21:FindFirstChild(t10.characterSide .. s4) or v196
    else
        v198 = ""
    end

    local _ = function(s5: string) --[[ getNumberAttribute ]] -- line: 1561
        -- upvalues:
        --  [1] v195 (ref)
        --  [2] v196 (copy)
        --  [3] v198 (ref)
        --  [4] u21 (copy)

        return v195 ~= v196 and tonumber(v195:GetAttribute(s5)) or (tonumber(
            v196:GetAttribute(s5 .. v198)
        ) or tonumber(u21:GetAttribute(s5 .. v198)))
    end

    local _ = function(s6: string) --[[ getStringAttribute ]] -- line: 1566
        -- upvalues:
        --  [1] v195 (ref)
        --  [2] v196 (copy)
        --  [3] v198 (ref)
        --  [4] u21 (copy)

        if v195 ~= v196 then
            local attribute = v195:GetAttribute(s6)

            if attribute and attribute ~= "" then
                return attribute
            end
        end

        local attribute_1 = v196:GetAttribute(s6 .. v198)

        if attribute_1 and attribute_1 ~= "" then
            return attribute_1
        end

        local attribute_2 = u21:GetAttribute(s6 .. v198)

        if attribute_2 and attribute_2 ~= "" then
            return attribute_2
        end
    end

    local _ = function(s7: string) --[[ getBooleanAttribute ]] -- line: 1579
        -- upvalues:
        --  [1] v195 (ref)
        --  [2] v196 (copy)
        --  [3] v198 (ref)
        --  [4] u21 (copy)

        if v195 ~= v196 then
            local attribute_3 = v195:GetAttribute(s7)

            if attribute_3 ~= nil then
                return attribute_3
            end
        end

        local attribute_4 = v196:GetAttribute(s7 .. v198)

        if attribute_4 ~= nil then
            return attribute_4
        end

        local attribute_5 = u21:GetAttribute(s7 .. v198)

        if attribute_5 ~= nil then
            return attribute_5
        end
    end

    local _ = function(s8: string) --[[ getAttribute ]] -- line: 1592
        -- upvalues:
        --  [1] v195 (ref)
        --  [2] v196 (copy)
        --  [3] v198 (ref)
        --  [4] u21 (copy)

        if v195 ~= v196 then
            local attribute_6 = v195:GetAttribute(s8)

            if attribute_6 ~= nil then
                return attribute_6
            end
        end

        local attribute_7 = v196:GetAttribute(s8 .. v198)

        if attribute_7 ~= nil then
            return attribute_7
        end

        local attribute_8 = u21:GetAttribute(s8 .. v198)

        if attribute_8 ~= nil then
            return attribute_8
        end
    end

    local v208 = u21
    local v209 = RigAssets_m.get(v208)
    local attribute_10, attribute_9

    if v195 ~= v196 then
        local RigType = v195:GetAttribute("RigType")

        if RigType and RigType ~= "" then
            v208 = RigType
        else
            attribute_9 = v196:GetAttribute("RigType" .. v198)

            if attribute_9 and attribute_9 ~= "" then
                v208 = attribute_9
            else
                attribute_10 = u21:GetAttribute("RigType" .. v198)
                v208 = if attribute_10 and attribute_10 ~= "" then attribute_10 else nil
            end
        end
    else
        attribute_9 = v196:GetAttribute("RigType" .. v198)

        if attribute_9 and attribute_9 ~= "" then
            v208 = attribute_9
        else
            attribute_10 = u21:GetAttribute("RigType" .. v198)
            v208 = if attribute_10 and attribute_10 ~= "" then attribute_10 else nil
        end
    end

    local v216

    if not v208 then
        v208 = u21:GetAttribute("RigType")

        if not v208 then
            local attribute_11, attribute_12

            if v195 ~= v196 then
                local R6 = v195:GetAttribute("R6")

                if R6 and R6 ~= "" then
                    v216 = R6
                else
                    attribute_11 = v196:GetAttribute("R6" .. v198)

                    if attribute_11 and attribute_11 ~= "" then
                        v216 = attribute_11
                    else
                        attribute_12 = u21:GetAttribute("R6" .. v198)
                        v216 = if attribute_12 and attribute_12 ~= "" then attribute_12 else nil
                    end
                end
            else
                attribute_11 = v196:GetAttribute("R6" .. v198)

                if attribute_11 and attribute_11 ~= "" then
                    v216 = attribute_11
                else
                    attribute_12 = u21:GetAttribute("R6" .. v198)
                    v216 = if attribute_12 and attribute_12 ~= "" then attribute_12 else nil
                end
            end

            if not v216 then
                v208 = u21:GetAttribute("R6")

                if v208 then
                    v208 = "R6"
                end
            else
                v208 = "R6"
            end
        end
    end

    local attribute_14, attribute_15

    if v195 ~= v196 then
        local attribute_13 = v195:GetAttribute("Character")

        if attribute_13 and attribute_13 ~= "" then
            v216 = attribute_13
        else
            attribute_14 = v196:GetAttribute("Character" .. v198)

            if attribute_14 and attribute_14 ~= "" then
                v216 = attribute_14
            else
                attribute_15 = u21:GetAttribute("Character" .. v198)
                v216 = if attribute_15 and attribute_15 ~= "" then attribute_15 else nil
            end
        end
    else
        attribute_14 = v196:GetAttribute("Character" .. v198)

        if attribute_14 and attribute_14 ~= "" then
            v216 = attribute_14
        else
            attribute_15 = u21:GetAttribute("Character" .. v198)
            v216 = if attribute_15 and attribute_15 ~= "" then attribute_15 else nil
        end
    end

    local v231

    if not v216 then
        v231 = Logger_m.warn
        local Name_5 = u21.Name
        v231(`IDK how to tell you this bro but {Name_5} does not have a character rig..`)
    end

    v231 = v209

    if v231 then
        v231 = v209:FindFirstChild(v216 or "")
    end

    if v231 and not v208 then
        local v235 = getHumanoid(v231)

        if v235 then
            if v235:IsA("Humanoid") then
                v208 = v235.RigType.Name
            end
        end
    end

    v208 = v208 or "R15"

    if (v198 ~= "" or v208 ~= t10.rigType) and not v231 then
        v216 = v208 .. "DefaultRig"
        v231 = t_1[v208]
    end

    if not v231 then
        return
    end

    local v241 = v216 .. u21.Name .. v195.Name .. v198

    if t10.preloadedRigs and (t10.preloadedRigs[v241] and not b7) then
        return t10.preloadedRigs[v241]
    end

    local v242 = v231:Clone()
    v242.Name = "PreloadedRig"
    v242.PrimaryPart = v242.PrimaryPart or v242:FindFirstChild("HumanoidRootPart")
    v242.Parent = v10

    if not t10.alive then
        pcall(function() -- line: 1646
            -- upvalues:
            --  [1] v242 (copy)

            v242:Destroy()
        end)

        return
    end

    local v245 = getHumanoid(v242)
    local v246, v247, v248, v249

    if v195 ~= v196 then
        v246 = tonumber(v195:GetAttribute("Scale"))

        if not v246 then
            v247 = "Scale"
            v248 = v247 .. v198
            v246 = tonumber(v196:GetAttribute(v248))

            if not v246 then
                v247 = "Scale"
                v249 = v247 .. v198
                v246 = tonumber(u21:GetAttribute(v249))
            end
        end
    else
        v247 = "Scale"
        v248 = v247 .. v198
        v246 = tonumber(v196:GetAttribute(v248))

        if not v246 then
            v247 = "Scale"
            v249 = v247 .. v198
            v246 = tonumber(u21:GetAttribute(v249))
        end
    end

    local v250 = v246 or 1
    local v251, v252

    if v195 ~= v196 then
        v246 = tonumber(v195:GetAttribute("HipHeight"))

        if not v246 then
            v247 = "HipHeight"
            v251 = v247 .. v198
            v246 = tonumber(v196:GetAttribute(v251))

            if not v246 then
                v247 = "HipHeight"
                v252 = v247 .. v198
                v246 = tonumber(u21:GetAttribute(v252))
            end
        end
    else
        v247 = "HipHeight"
        v251 = v247 .. v198
        v246 = tonumber(v196:GetAttribute(v251))

        if not v246 then
            v247 = "HipHeight"
            v252 = v247 .. v198
            v246 = tonumber(u21:GetAttribute(v252))
        end
    end

    local attribute_17
    local v253, v254, v255

    if v195 ~= v196 then
        v247 = "Offset"
        local attribute_16 = v195:GetAttribute(v247)

        if attribute_16 ~= nil then
            v253 = attribute_16
        else
            v254 = v198
            v247 = "Offset" .. v254
            v255 = v196:GetAttribute(v247)

            if v255 ~= nil then
                v253 = v255
            else
                v254 = "Offset"
                attribute_17 = u21:GetAttribute(v254 .. v198)
                v253 = if attribute_17 ~= nil then attribute_17 else nil
            end
        end
    else
        v254 = v198
        v247 = "Offset" .. v254
        v255 = v196:GetAttribute(v247)

        if v255 ~= nil then
            v253 = v255
        else
            v254 = "Offset"
            attribute_17 = u21:GetAttribute(v254 .. v198)
            v253 = if attribute_17 ~= nil then attribute_17 else nil
        end
    end

    local num

    if v195 ~= v196 then
        v254 = "Rotation"
        num = tonumber(v195:GetAttribute(v254))

        if not num then
            v254 = "Rotation" .. v198
            num = tonumber(v196:GetAttribute(v254))

            if not num then
                v254 = "Rotation" .. v198
                num = tonumber(u21:GetAttribute(v254))
            end
        end
    else
        v254 = "Rotation" .. v198
        num = tonumber(v196:GetAttribute(v254))

        if not num then
            v254 = "Rotation" .. v198
            num = tonumber(u21:GetAttribute(v254))
        end
    end

    v255 = num or 0

    if v195 ~= v196 then
        v254 = "Zoom"
        num = tonumber(v195:GetAttribute(v254))

        if not num then
            v254 = "Zoom" .. v198
            num = tonumber(v196:GetAttribute(v254))

            if not num then
                v254 = "Zoom" .. v198
                num = tonumber(u21:GetAttribute(v254))
            end
        end
    else
        v254 = "Zoom" .. v198
        num = tonumber(v196:GetAttribute(v254))

        if not num then
            v254 = "Zoom" .. v198
            num = tonumber(u21:GetAttribute(v254))
        end
    end

    if v195 ~= v196 then
        v247 = tonumber(v196:GetAttribute("Rotation")) or 0
        v255 -= v247
    end

    local v265

    if v195 ~= v196 then
        local attribute_18 = v195:GetAttribute("AnchorRoot")

        if attribute_18 ~= nil then
            v247 = attribute_18
        else
            v265 = v196:GetAttribute("AnchorRoot" .. v198)

            if v265 ~= nil then
                v247 = v265
            else
                v254 = u21:GetAttribute("AnchorRoot" .. v198)
                v247 = if v254 ~= nil then v254 else nil
            end
        end
    else
        v265 = v196:GetAttribute("AnchorRoot" .. v198)

        if v265 ~= nil then
            v247 = v265
        else
            v254 = u21:GetAttribute("AnchorRoot" .. v198)
            v247 = if v254 ~= nil then v254 else nil
        end
    end

    if v247 == nil then
        v247 = true
    end

    local attribute_19, attribute_20
    local v267

    if v195 ~= v196 then
        local NoDescription = v195:GetAttribute("NoDescription")

        if NoDescription ~= nil then
            v254 = NoDescription
        else
            v267 = v198
            attribute_19 = v196:GetAttribute("NoDescription" .. v267)

            if attribute_19 ~= nil then
                v254 = attribute_19
            else
                v267 = "NoDescription"
                attribute_20 = u21:GetAttribute(v267 .. v198)
                v254 = if attribute_20 ~= nil then attribute_20 else nil
            end
        end
    else
        v267 = v198
        attribute_19 = v196:GetAttribute("NoDescription" .. v267)

        if attribute_19 ~= nil then
            v254 = attribute_19
        else
            v267 = "NoDescription"
            attribute_20 = u21:GetAttribute(v267 .. v198)
            v254 = if attribute_20 ~= nil then attribute_20 else nil
        end
    end

    v265 = not v254
    local attribute_21, attribute_22

    if v195 ~= v196 then
        local HeightFix = v195:GetAttribute("HeightFix")

        if HeightFix ~= nil then
            v254 = HeightFix
        else
            v267 = v198
            attribute_21 = v196:GetAttribute("HeightFix" .. v267)

            if attribute_21 ~= nil then
                v254 = attribute_21
            else
                v267 = "HeightFix"
                attribute_22 = u21:GetAttribute(v267 .. v198)
                v254 = if attribute_22 ~= nil then attribute_22 else nil
            end
        end
    else
        v267 = v198
        attribute_21 = v196:GetAttribute("HeightFix" .. v267)

        if attribute_21 ~= nil then
            v254 = attribute_21
        else
            v267 = "HeightFix"
            attribute_22 = u21:GetAttribute(v267 .. v198)
            v254 = if attribute_22 ~= nil then attribute_22 else nil
        end
    end

    if v254 == nil then
        v254 = true
    end

    local v272 = u21:GetAttributes()

    for key_49, val_41 in v196:GetAttributes() do
        v272[key_49] = val_41
    end

    for key_50, val_42 in v195:GetAttributes() do
        v272[key_50] = val_42
    end

    if type(v272.extraIds) == "string" then
        v272.extraIds = string.split(v272.extraIds, ",")
    end

    for key_51, val_43 in t10.animAttributes do
        if v272[key_51] == nil then
            v272[key_51] = val_43
        end
    end

    if v272.extraIds == nil then
        v272.extraIds = {}
    end

    local t_41 = {
        hideCharacter = if not v242 then false else true,
        rig = v242,
        rigType = v208,
        humanoid = v245,
        zoom = num or 0,
        animator = getAnimator(v242),
        rotation = v255,
        offset = nil,
        defaultPivot = nil,
        heightOffset = nil,
        rawScale = 1,
        curScale = 1,
        modelScale = 1,
        rigId = nil,
        descSettings = nil,
        subRigs = nil,
        subRigsAnims = nil
    }
    local v274 = v253 or CFrame.new()
    v267 = CFrame.Angles(0, math.rad(v255), 0)
    t_41.offset = v274 * v267
    t_41.defaultPivot = v242:GetPivot()
    v267 = 0
    t_41.heightOffset = CFrame.new(0, v267, 0)
    t_41.rigId = v241
    t_41.descSettings = v272
    t_41.subRigs = {}
    t_41.subRigsAnims = {}

    local _ = function() --[[ applyHipHeight ]] -- line: 1714
        -- upvalues:
        --  [1] v246 (copy)
        --  [2] t10 (copy)
        --  [3] v245 (copy)

        if not v246 or not t10.alive then
            return
        end

        task.defer(function() -- line: 1717
            -- upvalues:
            --  [1] v245 (ref)
            --  [2] v246 (ref)

            task.wait()
            v245.HipHeight = v246
        end)
    end

    local function loadAppearance() -- line: 1723
        -- upvalues:
        --  [1] v195 (ref)
        --  [2] v196 (copy)
        --  [3] v198 (ref)
        --  [4] u21 (copy)
        --  [5] u22 (copy)
        --  [6] GetDescription (ref)
        --  [7] t10 (copy)
        --  [8] v242 (copy)
        --  [9] v272 (copy)
        --  [10] t_5 (ref)
        --  [11] v208 (ref)
        --  [12] v231 (ref)
        --  [13] v245 (copy)
        --  [14] v247 (ref)
        --  [15] v250 (copy)
        --  [16] t_41 (copy)
        --  [17] v246 (copy)
        --  [18] v254 (ref)
        --  [19] t_10 (ref)

        local attribute_23
        local v275, v277

        if v195 ~= v196 then
            local AccessoryWhitelist = v195:GetAttribute("AccessoryWhitelist")

            if AccessoryWhitelist ~= nil then
                v275 = AccessoryWhitelist
            else
                v277 = v196:GetAttribute("AccessoryWhitelist" .. v198)

                if v277 ~= nil then
                    v275 = v277
                else
                    attribute_23 = u21:GetAttribute("AccessoryWhitelist" .. v198)
                    v275 = if attribute_23 ~= nil then attribute_23 else nil
                end
            end
        else
            v277 = v196:GetAttribute("AccessoryWhitelist" .. v198)

            if v277 ~= nil then
                v275 = v277
            else
                attribute_23 = u21:GetAttribute("AccessoryWhitelist" .. v198)
                v275 = if attribute_23 ~= nil then attribute_23 else nil
            end
        end

        local attribute_24, attribute_25

        if v195 ~= v196 then
            local AccessoryBlacklist = v195:GetAttribute("AccessoryBlacklist")

            if AccessoryBlacklist ~= nil then
                v277 = AccessoryBlacklist
            else
                attribute_24 = v196:GetAttribute("AccessoryBlacklist" .. v198)

                if attribute_24 ~= nil then
                    v277 = attribute_24
                else
                    attribute_25 = u21:GetAttribute("AccessoryBlacklist" .. v198)
                    v277 = if attribute_25 ~= nil then attribute_25 else nil
                end
            end
        else
            attribute_24 = v196:GetAttribute("AccessoryBlacklist" .. v198)

            if attribute_24 ~= nil then
                v277 = attribute_24
            else
                attribute_25 = u21:GetAttribute("AccessoryBlacklist" .. v198)
                v277 = if attribute_25 ~= nil then attribute_25 else nil
            end
        end

        local v281 = v275 and parseAccesoryTable(v275) or {}
        v275 = v281
        v281 = v277 and parseAccesoryTable(v277) or {}
        v277 = v281
        v281 = nil

        if type(u22) == "number" then
            v281 = GetDescription(u22)
        elseif type(u22) == "table" then
            v281 = GetDescription(u22.id, u22.type)
        elseif typeof(u22) == "Instance" then
            v281 = u22
        end

        if not v281 then
            return
        end

        if not t10.alive then
            pcall(function() -- line: 1743
                -- upvalues:
                --  [1] v242 (ref)

                v242:Destroy()
            end)

            return
        end

        v281.Archivable = true

        for _, descendant in v281:GetDescendants() do
            descendant.Archivable = true
        end

        v281 = v281:Clone()
        local Name_8

        if not next(v275) then
            if next(v277) then
                for _, child_10 in v281:GetChildren() do
                    if child_10:IsA("AccessoryDescription") then
                        Name_8 = child_10.AccessoryType.Name

                        if not v275[Name_8] or v277[Name_8] then
                            child_10:Destroy()
                        end
                    end
                end
            end
        else
            for _, child_11 in v281:GetChildren() do
                if child_11:IsA("AccessoryDescription") then
                    Name_8 = child_11.AccessoryType.Name

                    if not v275[Name_8] or v277[Name_8] then
                        child_11:Destroy()
                    end
                end
            end
        end

        if v272.useFaces and #v242:QueryDescendants("[$Face]") > 0 then
            for _, val_44 in v281:QueryDescendants(">AccessoryDescription") do
                if t_5[val_44.AccessoryType] then
                    pcall(val_44.Destroy, val_44)
                end
            end
        end

        if v208 == "D15" or v208 == "S15" then
            local v282 = getHumanoid(v231):GetAppliedDescription()
            v281.Torso = v282.Torso
            v281.LeftLeg = v282.LeftLeg
            v281.RightLeg = v282.RightLeg
            v281.LeftArm = v282.LeftArm
            v281.RightArm = v282.RightArm
        end

        local v283 = loadDescription(
            v242,
            v245,
            v281,
            v272,
            { headScale = v281.HeadScale }
        )

        if not t10.alive then
            pcall(function() -- line: 1800
                -- upvalues:
                --  [1] v242 (ref)

                v242:Destroy()
            end)

            return
        end

        if v242.PrimaryPart then
            v242.PrimaryPart.Anchored = v247 or false
        end

        if v250 ~= 1 then
            local v284 = v242
            v284:ScaleTo(1 * v250 * (t_41.parentRig and t_41.parentRig.rawScale or 1))
            t_41.modelScale = 1 * v250
        end

        if v246 and t10.alive then
            task.defer(function() -- line: 1717
                -- upvalues:
                --  [1] v245 (ref)
                --  [2] v246 (ref)

                task.wait()
                v245.HipHeight = v246
            end)
        end

        if v283 and v254 then
            local cframe = CFrame.new(0, getHeightDiffFromCharacter(v242), 0)
            local v289 = cframe:Inverse()
            local v290 = t_10[v245.RigType.Name] or {}
            local v291 = v283.rootWelds or {}

            for _, val_45 in v291 do
                local v292 = val_45.Part0 and (table.find(v290, val_45.Part0.Name) and val_45.Part0.Parent == v242)
                local v293 = val_45.Part1 and (table.find(v290, val_45.Part1.Name) and val_45.Part1.Parent == v242)

                if v292 and val_45.Part0.Name == "HumanoidRootPart" then
                    val_45.C0 *= v289
                end

                if v293 and val_45.Part1.Name == "HumanoidRootPart" then
                    val_45.C1 *= v289
                end
            end

            local v294 = t_41
            v294.offset *= cframe
            t_41.heightOffset = cframe
        end
    end

    if v208 == "MeshRig" then
        v265 = false
    end

    if v245 then
        v267 = v245:IsA("Humanoid")

        if not v267 then
            v265 = false
        end
    else
        v265 = false
    end

    v267 = v265 and (b6 and Signal_m.new()) or nil

    if v265 then
        if b6 then
            v267:Once(function() -- line: 1858
                -- upvalues:
                --  [1] v267 (ref)

                v267 = nil
            end)
            task.spawn(function() -- line: 1862
                -- upvalues:
                --  [1] loadAppearance (copy)
                --  [2] v267 (ref)

                loadAppearance()
                v267:Fire()
            end)
        else
            loadAppearance()
        end
    elseif v246 and t10.alive then
        task.defer(function() -- line: 1717
            -- upvalues:
            --  [1] v245 (copy)
            --  [2] v246 (copy)

            task.wait()
            v245.HipHeight = v246
        end)
    end

    if v242.PrimaryPart then
        v242.PrimaryPart.Anchored = v247 or false
    end

    return t_41, v267
end

function t.PreloadRig(t11: table, u23: userdata, u24: userdata?, b8: boolean?) -- line: 1882
    -- upvalues:
    --  [1] CacheService_m (copy)
    --  [2] Logger_m (copy)
    --  [3] AppearanceManager_m (copy)

    if not u23 or t11.locked then
        return
    end

    local v297, v298 = t11:PrepareRig(
        u23,
        u24 or t11.humanoidDescription,
        nil,
        false,
        b8
    )

    if not v297 then
        return
    end

    if not t11.alive then
        pcall(function() -- line: 1889
            -- upvalues:
            --  [1] v297 (copy)

            v297.rig:Destroy()
        end)

        for _, val_46 in v297.subRigs do
            pcall(function() -- line: 1894
                -- upvalues:
                --  [1] val_46 (copy)

                val_46.rig:Destroy()
            end)
        end

        return
    end

    if t11.preloadedRigs and t11.preloadedRigs[v297.rigId] then
        return t11.preloadedRigs[v297.rigId]
    end

    if v298 then
        v298:Once(function() -- line: 1904
            -- upvalues:
            --  [1] t11 (copy)
            --  [2] v297 (copy)
            --  [3] CacheService_m (ref)

            if t11.currentRig == v297 then
                t11:Scale()
                t11:SetPosition()
                task.spawn(function() -- line: 1910
                    -- upvalues:
                    --  [1] v297 (ref)
                    --  [2] CacheService_m (ref)

                    for _, descendant_1 in v297.rig:GetDescendants() do
                        if descendant_1:IsA("Decal") then
                            CacheService_m.cacheImage(descendant_1.ColorMapContent)
                        elseif not descendant_1:IsA("MeshPart") then
                            if descendant_1:IsA("SpecialMesh") then
                                CacheService_m.cacheMesh(descendant_1)
                            end
                        else
                            CacheService_m.cacheMesh(descendant_1)
                        end
                    end
                end)
            end
        end)
    end

    Logger_m.log("Loaded main rig for", u23.Name)
    local v299 = tonumber(
        (u23:FindFirstChild(t11.characterSide or "") or u23):GetAttribute("ExtraChars")
    ) or (tonumber(u23:GetAttribute("ExtraChars")) or 0)
    local v303

    for index_3 = 1, v299 do
        if t11.alive then
            local str = tostring(index_3 + 1)
            local v300 = v297.descSettings.extraIds[index_3]

            if v300 == nil then
                v300 = {
                    id = AppearanceManager_m.getRandomFriend(false, t11.userId),
                    type = "User ID"
                }
            end

            Logger_m.log("Trying to load extra rig", index_3)
            local v302, v303 = t11:PrepareRig(
                u23,
                v300,
                str,
                t11.asyncDescriptions,
                b8
            )

            if v302 then
                if v303 then
                    v303:Once(function() -- line: 1941
                        -- upvalues:
                        --  [1] v302 (copy)
                        --  [2] v297 (copy)
                        --  [3] t11 (copy)

                        local Rig_1 = v302.rig
                        local v304 = v297.defaultPivot
                        local Rig_2 = v297.rig

                        if not v297 or not v304 then
                            v304 = nil
                        end

                        if t11.currentRig == v297 then
                            v304 = t11.finalPos
                        end

                        if Rig_2 and Rig_1 then
                            Rig_1:PivotTo(v304 * v302.offset)
                        end
                    end)
                end

                v302.parentRig = v297
                local Rig_3 = v302.rig
                Rig_3.Name = "ExtraCharacter" .. str
                Rig_3:PivotTo(v297.defaultPivot * v302.offset, 0)
                Rig_3.Parent = v297.rig
                table.insert(
                    v297.subRigsAnims,
                    t11:LoadAnimationsOnAnimator(
                        getAnimations(u23, t11.characterSide .. str),
                        v302.animator
                    )
                )
                table.insert(v297.subRigs, v302)
                task.spawn(function() -- line: 1971
                    -- upvalues:
                    --  [1] Rig_3 (copy)
                    --  [2] CacheService_m (ref)

                    for _, descendant_2 in Rig_3:GetDescendants() do
                        if descendant_2:IsA("Decal") then
                            CacheService_m.cacheImage(descendant_2.ColorMapContent)
                        elseif not descendant_2:IsA("MeshPart") then
                            if descendant_2:IsA("SpecialMesh") then
                                CacheService_m.cacheMesh(descendant_2)
                            end
                        else
                            CacheService_m.cacheMesh(descendant_2)
                        end
                    end
                end)
            end
        end
    end

    if not t11.alive then
        pcall(function() -- line: 1984
            -- upvalues:
            --  [1] v297 (copy)

            v297.rig:Destroy()
        end)

        for _, val_47 in v297.subRigs do
            pcall(function() -- line: 1989
                -- upvalues:
                --  [1] val_47 (copy)

                val_47.rig:Destroy()
            end)
        end

        return
    end

    print("loaded rig", v297.rig.Parent, v297.rig)
    t11.preloadedRigs[v297.rigId] = v297

    return v297
end

function t.UnloadAllFromMemory(arg68) -- line: 2002
    local v309 = arg68.preloadedAnims or {}

    for key_61, _ in v309 do
        arg68:UnloadAnim(key_61)
    end
end

function t.UnloadAnim(arg69, arg70) -- line: 2008
    local v310 = arg70 or arg69.currentAnim
    arg70 = v310
    v310 = (arg69.preloadedAnims or {})[arg70]

    if not v310 then
        return
    end

    if arg69.currentAnim == arg70 then
        arg69:UnloadRig()
    end

    local Rig_4 = v310.rig
    local v312

    if Rig_4 then
        arg69.preloadedRigs[Rig_4.rigId] = nil

        if Rig_4.rig then
            for _, val_49 in Rig_4.rig:QueryDescendants("Highlight") do
                if val_49:IsDescendantOf(Rig_4.rig) then
                    val_49.Enabled = false
                    val_49.Adornee = nil
                    val_49.Parent = nil
                    val_49:Destroy()
                end
            end

            for _, val_50 in Rig_4.rig:QueryDescendants("LayerCollector, Script, LocalScript") do
                val_50.Enabled = false
            end
        end

        if Rig_4.rig then
            pcall(function() -- line: 2035
                -- upvalues:
                --  [1] Rig_4 (copy)

                Rig_4.rig:Destroy()
            end)
        end

        v312 = Rig_4.subRigs or {}

        for _, val_51 in v312 do
            if val_51.rig then
                pcall(function() -- line: 2042
                    -- upvalues:
                    --  [1] val_51 (copy)

                    val_51.rig:Destroy()
                end)
            end
        end
    end

    v312 = v310.animations or {}

    for _, val_52 in v312 do
        val_52:Stop(0)
        pcall(function() -- line: 2050
            -- upvalues:
            --  [1] val_52 (copy)

            val_52:Destroy()
        end)
    end

    arg69.preloadedAnims[arg70] = nil
end

function t.PreloadAnim(t12: table, arg71: any, u25: userdata?, b9: boolean?) -- line: 2057
    -- upvalues:
    --  [1] Logger_m (copy)
    --  [2] Emotes (copy)
    --  [3] Animations (copy)

    if not arg71 or t12.locked then
        return
    end

    local v313 = arg71

    if type(arg71) ~= "string" or not v313 then
        v313 = arg71.Name
    end

    local v314 = t12.preloadedAnims[v313]
    local v315

    if v314 and not b9 then
        if v314.isLoading then
            Logger_m.log("Preloaded animation is already loading, yielding...")

            repeat
                task.wait()

                if not t12.alive then
                    break
                end
            until t12.preloadedAnims[v313] ~= v314
        end

        v315 = t12.alive and t12.preloadedAnims[v313]

        return v315
    end

    t12:Replicate("PreloadAnim", arg71, u25)
    v315 = t12.isEmote and Emotes or Animations
    local v316 = type(arg71) == "string" and v315:FindFirstChild(v313, true) or arg71

    if not v316 then
        return
    end

    if type(v316) == "string" then
        Logger_m.log(`{arg71} IS A STRING NOT AN ANIM`)

        return
    end

    if v316:GetAttribute("Pack") then
        for _, child_12 in v316:GetChildren() do
            if child_12.ClassName == "Folder" then
                v316 = child_12
                break
            end
        end
    end

    t12.preloadedAnims[v313] = { isLoading = true }
    local v317 = getAnimations(v316, t12.characterSide)
    local v318 = v316:FindFirstChild(t12.characterSide)
    local v319 = v316:GetAttributes()

    if v318 then
        for key_67, val_53 in v318:GetAttributes() do
            v319[key_67] = val_53
        end
    end

    local v320 = (v316:GetAttribute("OptionalPrefixes") or ""):split(",")

    if v320[1] == "%ALL" then
        v320 = setmetatable({}, {
            __index = function() --[[ __index ]] -- line: 2117
                return true
            end
        })
    end

    for key_68, val_54 in v320 do
        v320[key_68] = nil
        v320[val_54] = true
    end

    local t_44 = {
        name = v313,
        rig = t12:PreloadRig(v316, u25, b9),
        isBeatDance = if v317.IdleLeft or v317.IdleRight then true else false,
        folder = v316,
        optionalPrefixes = v320,
        sideAttrs = v319
    }

    if not t12.alive then
        return
    end

    t12.animOptionalPrefixes = v320
    local v321 = t_44.rig or t12.defaultData
    t_44.animations = t12:LoadAnimationsOnAnimator(v317, v321.animator)
    t12.animOptionalPrefixes = {}

    if not t12.alive then
        return
    end

    if t_44.rig and #t_44.rig.subRigsAnims > 0 then
        local t_45 = {}

        for _, val_55 in t_44.rig.subRigsAnims do
            for key_70, _ in val_55 do
                t_45[key_70] = true
            end
        end

        for key_71, _ in t_44.animations do
            t_45[key_71] = true
        end

        local function animFromName(arg72, arg73) -- line: 2166
            -- upvalues:
            --  [1] t12 (copy)

            if arg72[arg73] then
                return arg72[arg73]
            end

            for _, val_58 in t12.prefixes do
                local v322 = arg73:gsub(val_58, "")

                if arg72[v322] then
                    return arg72[v322]
                end
            end

            return nil
        end

        for key_73, _ in t_45 do
            local t_46 = { (animFromName(t_44.animations, key_73)) }

            for _, val_60 in t_44.rig.subRigsAnims do
                table.insert(t_46, (animFromName(val_60, key_73)))
            end

            t_44.animations[key_73] = mergeTracks(t_46)
        end
    end

    t12.preloadedAnims[v313] = t_44
    Logger_m.log("Preloaded anim " .. v313)

    if not t12.loadingAnim and t12.animToLoad == v313 then
        Logger_m.log("Server caught Preload request received after same anim failed Load request")

        return t12:LoadAnim(v313, b9)
    end

    return t_44
end

function t.BulkPreload(t13: table, t14: table) -- line: 2200
    local v324 = #t14
    local thread = coroutine.running()

    for _, val_61 in t14 do
        task.spawn(function() -- line: 2207
            -- upvalues:
            --  [1] t13 (copy)
            --  [2] val_61 (copy)
            --  [3] v324 (ref)
            --  [4] thread (copy)

            t13:PreloadAnim(val_61)
            v324 -= 1

            if v324 == 0 then
                coroutine.resume(thread)
            end
        end)
    end

    if v324 == 0 then
        return
    end

    return coroutine.yield()
end

function t.SetSide(t15: table, s9: string) -- line: 2223
    -- upvalues:
    --  [1] Logger_m (copy)

    local v325 = s9 or t15.defaultCharacterSide
    local v326 = string.upper((tostring(v325)))
    Logger_m.log("Changed Character side to " .. v326)
    t15.characterSide = v326
end

function t.SetIdleAnim(t16: table, s10: string?) -- line: 2230
    -- upvalues:
    --  [1] Logger_m (copy)

    t16.idleName = s10 or "Idle"
    t16:Dance()
    Logger_m.log("Changed Character default idle animation to " .. t16.idleName)
end

function t.Hide(t17: table, t18: table?, t19: table?) -- line: 2238
    local v327 = if t18 ~= nil then false else t19 == nil
    local v328 = t18 or {}
    t18 = v328
    v328 = t19 or {}
    t19 = v328

    if v327 then
        t17.hidden = true
    end

    for _, val_62 in t17.charModel:QueryDescendants("BasePart, FaceInstance") do
        if table.find(t18, val_62) then
            if table.find(t19, val_62) then
                val_62.Transparency = 1
            end
        else
            val_62.Transparency = 1
        end
    end

    for _, val_63 in t17.charModel:QueryDescendants(
        "LayerCollector, Beam, Fire, Sparkles, ParticleEmitter, RopeConstraint"
    ) do
        if table.find(t18, val_63) then
            if table.find(t19, val_63) then
                val_63.Enabled = false
            end
        else
            val_63.Enabled = false
        end
    end
end

function t.Show(t20: table, t21: table?, t22: table?) -- line: 2258
    local CurrentRig = t20.currentRig
    local v329 = CurrentRig and CurrentRig.rig
    local v330 = false
    local v331

    if t21 == nil and t22 == nil then
        v331 = CurrentRig and t20.charModel:GetDescendants() or {}
        t21 = v331
        v331 = CurrentRig and v329:GetDescendants() or {}
        t22 = v331
        v330 = true
    else
        v331 = t21 or {}
        t21 = v331
        v331 = t22 or {}
        t22 = v331
    end

    if v330 then
        t20.hidden = false
    end

    for _, val_64 in t20.charModel:QueryDescendants("BasePart, FaceInstance") do
        if val_64 ~= t20.charModel.PrimaryPart and (not CurrentRig or val_64 ~= v329.PrimaryPart) then
            if table.find(t21, val_64) then
                if table.find(t22, val_64) then
                    val_64.Transparency = 0
                end
            else
                val_64.Transparency = 0
            end
        end
    end

    for _, val_65 in t20.charModel:QueryDescendants(
        "LayerCollector, Beam, Fire, Sparkles, ParticleEmitter, RopeConstraint"
    ) do
        if table.find(t21, val_65) then
            if table.find(t22, val_65) then
                val_65.Enabled = true
            end
        else
            val_65.Enabled = true
        end
    end
end

function t.CreateClone(arg74) -- line: 2288
    return arg74:GetActiveCharacter():Clone()
end

function t.GetActiveCharacter(arg75) -- line: 2292
    return arg75.currentRig and arg75.currentRig.rig or arg75.charModel
end

function t.LoadRig(t23: table, u26: userdata) -- line: 2296
    -- upvalues:
    --  [1] v4 (copy)

    if not u26 then
        return
    end

    if t23.currentRig then
        t23:UnloadRig()
    end

    local v333 = t23:PreloadRig(u26)

    if not v333 then
        return
    end

    local Rig_5 = v333.rig
    Rig_5.Name = "PlayerRig"

    if v333.hideCharacter then
        t23:Hide(t23.hidden and {} or Rig_5:GetDescendants())
    end

    local v335 = t23.charModel:FindFirstChild("Rig") or Instance.new("Folder")
    v335.Name = "Rig"

    for _, descendant_3 in Rig_5:GetDescendants() do
        if descendant_3.Name == "Highlight" and descendant_3.ClassName == "Folder" then
            if not v4 then
                local Highlight = Instance.new("Highlight")
                Highlight:AddTag("AnimationHighlight")

                for _, child_13 in descendant_3:GetChildren() do
                    if hasProperty(Highlight, child_13.Name) then
                        if child_13.Name == "DepthMode" then
                            local Name_9 = child_13.Name
                            Highlight[Name_9] = Enum.HighlightDepthMode:FromName(
                                child_13.Value or ""
                            ) or Enum.HighlightDepthMode.Occluded
                        else
                            Highlight[child_13.Name] = child_13.Value
                        end
                    end
                end

                if Highlight.Adornee == nil then
                    Highlight.Adornee = descendant_3.Parent
                end

                Highlight.Parent = descendant_3.Parent
            end
        elseif not descendant_3:IsA("LayerCollector") then
            if not descendant_3:IsA("Script") then
                if descendant_3:IsA("LocalScript") then
                    descendant_3.Enabled = true
                elseif not descendant_3:IsA("AudioEmitter") then
                    if descendant_3:IsA("Wire") then
                        descendant_3:Destroy()
                    end
                else
                    descendant_3:Destroy()
                end
            else
                descendant_3.Enabled = true

                if not descendant_3:IsA("AudioEmitter") then
                    if descendant_3:IsA("Wire") then
                        descendant_3:Destroy()
                    end
                else
                    descendant_3:Destroy()
                end
            end
        else
            descendant_3.Enabled = true

            if not descendant_3:IsA("AudioEmitter") then
                if descendant_3:IsA("Wire") then
                    descendant_3:Destroy()
                end
            else
                descendant_3:Destroy()
            end
        end
    end

    t23.rigFolder = v335
    t23.currentRig = v333
    t23.humanoid = v333.humanoid
    t23.animator = v333.animator
    t23:Scale()
    t23:SetPosition()
    local WeldConstraint_1 = Instance.new("WeldConstraint")
    WeldConstraint_1.Part0 = t23.charModel.PrimaryPart
    WeldConstraint_1.Part1 = Rig_5.PrimaryPart
    WeldConstraint_1.Enabled = true
    WeldConstraint_1.Name = "RigWeld"
    WeldConstraint_1.Parent = v335
    Rig_5.Parent = v335
    v335.Parent = t23.charModel

    return v333
end

function t.Scale(arg76, arg77) -- line: 2375
    local v337 = arg76:GetActiveCharacter()

    if not v337 then
        return
    end

    local CurrentRig_1 = arg76.currentRig

    if CurrentRig_1 then
        if not arg77 then
            arg77 = CurrentRig_1.rawScale
        end

        CurrentRig_1.rawScale = arg77
        arg77 *= CurrentRig_1.modelScale

        if CurrentRig_1.curScale == arg77 then
            return
        end

        CurrentRig_1.curScale = arg77
    else
        arg77 = arg77 or 1
    end

    v337:ScaleTo(arg77)
end

function t.UnloadRig(arg78) -- line: 2407
    -- upvalues:
    --  [1] v10 (copy)

    if not arg78.currentRig then
        return
    end

    local Rig_6 = arg78.currentRig.rig
    pcall(function() -- line: 2411
        -- upvalues:
        --  [1] Rig_6 (copy)
        --  [2] v10 (ref)

        Rig_6.Parent = v10
        Rig_6.Name = "PreloadedRig"
    end)

    if arg78.rigFolder then
        arg78.rigFolder:Destroy()
        arg78.rigFolder = nil
    end

    arg78:Show(arg78.hidden and arg78.charModel:GetDescendants() or {})
    arg78.currentRig = nil
    arg78.humanoid = arg78.defaultData.humanoid
    arg78.animator = arg78.defaultData.animator
end

function t.firstAnimLoad(arg79, arg80) -- line: 2424
    return arg79:postAsyncAnimLoad(arg80)
end

function t.postAsyncAnimLoad(arg81, arg82) -- line: 2428
    if arg81.loadingAnim then
        arg81.animationStoppedLoading:Wait()
    end

    if not arg81.currentAnim then
        return
    end

    arg82()
end

function t.requestTrackLoad(arg83, arg84) -- line: 2437
    -- upvalues:
    --  [1] ContentProvider (copy)

    local v339 = arg83.Animations[arg84]

    if not v339 then
        return
    end

    ContentProvider:PreloadAsync({ v339.Animation })
end

function t.LoadAnim(t24: table, arg85: any, b10: boolean?, b11: boolean?) -- line: 2444
    -- upvalues:
    --  [1] Logger_m (copy)

    if t24.locked or not t24.alive then
        return
    end

    if not b11 then
        t24:Replicate("LoadAnim", arg85)
    end

    if t24.loadingAnim then
        if t24.animQueue == arg85 then
            return
        end

        Logger_m.log("Animation trying to load while another animation is loading!")
        local thread_1 = coroutine.running()
        t24.animQueue = arg85
        t24.animationStoppedLoading:Once(function() -- line: 2460
            -- upvalues:
            --  [1] t24 (copy)
            --  [2] arg85 (copy)
            --  [3] thread_1 (copy)
            --  [4] b10 (copy)

            if t24.animQueue == arg85 and t24.alive then
                return task.spawn(coroutine.resume, thread_1, t24:LoadAnim(arg85, b10, true))
            end

            task.spawn(coroutine.resume, thread_1)
        end)

        return coroutine.yield()
    else
        t24.loadingAnim = true
        local v341 = t24:PreloadAnim(arg85, nil, b10)

        if not v341 then
            t24.loadingAnim = false
            local v342 = arg85

            if v342 then
                v342 = arg85

                if type(arg85) ~= "string" or not v342 then
                    v342 = arg85.Name
                end
            end

            t24.animToLoad = v342

            if t24.alive then
                t24.animationStoppedLoading:Fire()

                return Logger_m.warn("[Character] Animation:", arg85, "is not a valid animation!")
            end

            return
        else
            if not t24.alive then
                t24.loadingAnim = false

                return
            end

            t24.animToLoad = nil
            Logger_m.log("Loading anim: " .. v341.name)
            t24.currentAnim = v341.name
            t24.curAnimFile = arg85
            local Animations_3 = t24.animations
            t24.isBeatDance = v341.isBeatDance
            t24.prevIdle = nil

            if t24.trackedIdleBeat then
                t24.trackedIdleBeat:Disconnect()
                t24.trackedIdleBeat = nil
            end

            t24.animations = v341.animations
            t24.sideAttributes = v341.sideAttrs
            t24.animationData = v341
            t24:Dance()
            t24:LoadRig(v341.folder)

            if t24.animations ~= Animations_3 then
                for _, val_66 in Animations_3 do
                    val_66:Stop(0)
                end
            end

            if not t24.alive then
                t24:UnloadRig()
            end

            t24.loadingAnim = false
            t24.animationStoppedLoading:Fire()

            if not t24.alive then
                return
            end

            t24.animationLoaded:Fire(v341)

            return
        end
    end
end

function t.StopDirectionalAnims(arg86) -- line: 2529
    -- upvalues:
    --  [1] t_3 (copy)

    for key_83, _ in t_3 do
        for _, val_68 in arg86.prefixes do
            local v343 = arg86.animations[key_83 .. val_68]

            if v343 then
                v343:Stop(0)
            end
        end
    end
end

local t_47 = { [0] = true, [1] = true, [1000] = true }

function t.isActionTrackPlaying(arg87) -- line: 2547
    -- upvalues:
    --  [1] t_47 (copy)

    for _, val_69 in arg87.animator:GetPlayingAnimationTracks() do
        if not t_47[val_69.Priority.Value] then
            return true
        end
    end
end

function t.isTrackDirectional(_, arg89) -- line: 2553
    return arg89.Priority == Enum.AnimationPriority.Movement
end

function startTrackAt(u27: userdata, n4: number?, n5: number?) -- line: 2557
    if n4 then
        u27:Play(0, nil, n5)
        u27:AdjustSpeed(0)
        u27.TimePosition = n4
        u27:AdjustSpeed(n5 or 1)

        return
    end

    u27:Play(0, nil, n5)
end

function t.PlayAsManual(arg90, arg91, arg92, arg93) -- line: 2569
    arg90:Play(arg91, arg92, arg93, false)
end

function t.GetValidTrack(t25: table, s11: string, s12: string?) -- line: 2573
    -- upvalues:
    --  [1] v4 (copy)
    --  [2] Logger_m (copy)

    local v345 = s12 or (t25.animPrefix or "")
    s12 = v345
    s12 = if s12 ~= " " then s12 else ""
    v345 = s11 .. s12
    local v346 = t25.animations[v345]

    if not v346 then
        v346 = t25.animations[s11]
        v345 = s11

        if not v346 then
            if not v4 then
                Logger_m.log(
                    "No animation called '" .. v345 .. "' found for '" .. t25.currentAnim .. "'!"
                )
            end

            return
        end
    end

    return v346, v345
end

function t._Play(
    t26: table,
    u28: userdata,
    b12: boolean?,
    s13: string?,
    n6: number?
) -- line: 2596
    -- upvalues:
    --  [1] ContentProvider (copy)
    --  [2] RunService (copy)

    if not u28 then
        return
    end

    local v347 = t26:isActionTrackPlaying()
    local v348 = s13 or (if t26:isTrackDirectional(u28) then "direction" else if t26:isTrackIdle(
        u28
    ) then "idle" else "action")
    local v349 = v348

    if b12 == nil then
        v348 = not t26.prioritizeActions or (v349 == "action" or not t26.prioritizeActions)
        b12 = v348
    end

    if v349 == "direction" and (v347 and not b12) then
        return
    end

    local RecentTrack

    if v349 == "idle" then
        if type(u28) == "table" then
            task.spawn(function() -- line: 2611
                -- upvalues:
                --  [1] u28 (copy)
                --  [2] ContentProvider (ref)
                --  [3] n6 (copy)

                local t_48 = {}

                for _, val_70 in u28.tracks do
                    pcall(function() -- line: 2615
                        -- upvalues:
                        --  [1] t_48 (copy)
                        --  [2] val_70 (copy)

                        table.insert(t_48, val_70.Animation)
                    end)
                end

                ContentProvider:PreloadAsync(t_48)
                startTrackAt(u28, n6, u28.Speed)
            end)
        else
            if v349 ~= "idle" then
                RecentTrack = t26.recentTrack

                if RecentTrack then
                    RecentTrack:Stop(0)
                end

                if t26.currentTrackStop then
                    t26.currentTrackStop:Disconnect()
                    t26.currentTrackStop = nil
                end
            end

            startTrackAt(u28, n6, u28.Speed)
        end
    else
        if v349 ~= "idle" then
            RecentTrack = t26.recentTrack

            if RecentTrack then
                RecentTrack:Stop(0)
            end

            if t26.currentTrackStop then
                t26.currentTrackStop:Disconnect()
                t26.currentTrackStop = nil
            end
        end

        startTrackAt(u28, n6, u28.Speed)
    end

    if v349 == "idle" then
        local PrevIdle = t26.prevIdle

        if PrevIdle and PrevIdle ~= u28 then
            PrevIdle:Stop(0)
        end

        t26.prevIdle = u28

        if t26.isBeatDance then
            if t26.trackedIdleBeat then
                t26.trackedIdleBeat:Disconnect()
                t26.trackedIdleBeat = nil
            end

            local now_1 = tick()
            t26.trackedIdleBeat = RunService.PreAnimation:Connect(function() -- line: 2644
                -- upvalues:
                --  [1] now_1 (copy)
                --  [2] u28 (copy)
                --  [3] t26 (copy)

                if tick() >= now_1 + (u28.Length - 0.04 / u28.Speed) then
                    t26.trackedIdleBeat:Disconnect()
                    t26.trackedIdleBeat = nil
                    t26.danced = not t26.danced
                    t26:Dance(true)
                end
            end)
        end

        return
    end

    t26.recentTrack = u28

    if u28.Looped then
        return
    end

    local _ = function() --[[ stopAnim ]] -- line: 2665
        -- upvalues:
        --  [1] u28 (copy)
        --  [2] t26 (copy)
        --  [3] v349 (ref)

        if not u28 then
            return
        end

        t26.recentTrack = nil
        u28:Stop(0)

        if v349 == "action" then
            t26.animationEnded:Fire(u28.Name)
        end
    end

    local now_3 = tick()
    local v350 = (u28.Length - 0.04) / u28.Speed
    t26.currentTrackStop = RunService.PreAnimation:Connect(function(_: number) -- line: 2683
        -- upvalues:
        --  [1] now_3 (copy)
        --  [2] v350 (copy)
        --  [3] t26 (copy)
        --  [4] u28 (copy)
        --  [5] v349 (ref)

        if tick() >= now_3 + v350 then
            t26.currentTrackStop:Disconnect()
            t26.currentTrackStop = nil

            if not u28 then
                return
            end

            t26.recentTrack = nil
            u28:Stop(0)

            if v349 == "action" then
                t26.animationEnded:Fire(u28.Name)
            end
        end
    end)
end

function t.Stop(arg94) -- line: 2692
    local RecentTrack_1 = arg94.recentTrack

    if RecentTrack_1 then
        RecentTrack_1:Stop(0)
        arg94.recentTrack = nil
    end

    local CurrentTrackStop = arg94.currentTrackStop

    if CurrentTrackStop then
        CurrentTrackStop:Disconnect()
        arg94.currentTrackStop = nil
    end
end

function t.Play(
    t27: table,
    s14: string,
    s15: string?,
    n8: number?,
    b13: boolean?,
    b14: boolean
) -- line: 2702
    -- upvalues:
    --  [1] v3 (ref)

    if t27.locked or not s14 then
        return
    end

    local v351, v352 = t27:GetValidTrack(s14, s15)

    if not v351 then
        return
    end

    local v353 = if t27:isTrackDirectional(v351) then "direction" else if t27:isTrackIdle(v351) then "idle" else "action"

    if b13 == nil then
        b13 = not t27.prioritizeActions or (v353 == "action" or not t27.prioritizeActions)
    end

    if not b14 then
        if v3 then
            if not b13 then
                t27:Replicate("ManualPlay", v352, n8)
            end
        else
            t27:Replicate(
                "Play",
                v352,
                "",
                n8,
                b13
            )
        end
    end

    t27:_Play(v351, b13, v353, n8)
end

function t.isTrackIdle(_: table, u29: userdata) -- line: 2727
    return u29.Priority == Enum.AnimationPriority.Idle
end

function t.PlayAnimation(arg95, ...) -- line: 2731
    return arg95:Play(...)
end

function t.Dance(arg96) -- line: 2735
    arg96:Play(
        if not arg96.isBeatDance then arg96.idleName else if not arg96.danced then "IdleLeft" else "IdleRight"
    )
end

t.ChangeAnim = t.LoadAnim

function t.TweenPosition(t29: table, u30: CFrame, u31: userdata, b15: boolean?) -- line: 2741
    -- upvalues:
    --  [1] VarTweener_m (copy)

    t29.curTweenID += 1
    local v357 = u30 or (t29.currentPos or t29.startPos)
    u30 = v357
    local CurTweenID = t29.curTweenID
    v357 = t29:GetFinalPosition(u30)
    local v358 = t29:GetActiveCharacter()
    local v359 = VarTweener_m:Create(t29, u31, { currentPos = u30 })
    local v360 = nil
    v360 = VarTweener_m:CreateValueTween(t29.finalPos, v357, u31, function(arg97) -- line: 2750
        -- upvalues:
        --  [1] t29 (copy)
        --  [2] CurTweenID (copy)
        --  [3] v359 (copy)
        --  [4] v360 (ref)
        --  [5] v358 (copy)

        if t29.curTweenID ~= CurTweenID then
            v359:Pause()
            v360:Pause()

            return
        end

        t29.finalPos = arg97
        v358:PivotTo(arg97)
    end)
    v359:Play()
    v360:Play()

    if b15 then
        v359.Completed:Connect(function() -- line: 2764
            -- upvalues:
            --  [1] t29 (copy)
            --  [2] u30 (ref)

            t29.startPos = u30
        end)
    end

    return VarTweener_m:MergeTweens(v359, v360)
end

function t.GetFinalPosition(arg98, arg99) -- line: 2772
    local v361 = arg99 or (arg98.currentPos or arg98.startPos)
    local v362 = arg98.offsetPos or CFrame.new()
    local v364 = v362 * (arg98.serverOff or CFrame.new())
    v362 = arg98.currentRig

    if v362 ~= nil then
        v364 *= v362.offset
    else
        local v365 = arg98.heightOff or CFrame.new()
        v364 *= v365
    end

    return v361 * v364, v364, v361
end

function t.SetPosition(t30: table, u32: CFrame?, b16: boolean?) -- line: 2791
    -- upvalues:
    --  [1] v3 (ref)
    --  [2] Logger_m (copy)
    --  [3] v4 (copy)

    local v366, v367, v368 = t30:GetFinalPosition(u32)
    local v369 = if t30.finalPos ~= v366 then false else true
    t30.finalPos = v366
    t30.currentPos = v368

    if b16 then
        t30.startPos = v368
    end

    if v3 then
        local v370 = t30:GetActiveCharacter()

        if v370 then
            v370:PivotTo(v366)
        else
            Logger_m.warn("NO ACTIVE CHARACTER!")
        end
    else
        local v371 = t30:GetActiveCharacter()

        if v4 then
            if v369 then
                v366 *= CFrame.new(0, 0.001, 0)
                t30.finalPos = v366
            end

            if v371 then
                v371:SetAttribute("ServerOffset", v367)
                v371:SetAttribute("ServerPos", v368)
            end
        end

        if v4 then
            if v371 then
                v371:PivotTo(v366)
            else
                Logger_m.warn("NO ACTIVE CHARACTER!")
            end
        else
            task.defer(function() -- line: 2813
                -- upvalues:
                --  [1] v371 (copy)
                --  [2] v366 (ref)
                --  [3] Logger_m (ref)

                if v371 then
                    v371:PivotTo(v366)

                    return
                end

                Logger_m.warn("NO ACTIVE CHARACTER!")
            end)
        end
    end
end

function t.GetRigStorage(_) -- line: 2839
    -- upvalues:
    --  [1] v10 (copy)

    return v10
end

return t
