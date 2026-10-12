local t = {
    RepStorage = game:GetService("ReplicatedStorage"),
    TweenService = game:GetService("TweenService"),
    Debris = game:GetService("Debris")
}
local v1 = nil
local Modules = t.RepStorage:WaitForChild("Modules")
local _ = require(Modules.Modchart.MirasTools.BadAppleFilter)
local v2 = nil
local t_1 = {
    Conductor = require(Modules.Main.Conductor),
    varTweener = require(Modules.Main.VarTweener),
    CustomFont = require(Modules.Other.RBX_CustomFont)
}
local t_2 = {}

function createFullScreenFrame(s1: string, u1: Color3) -- line: 21
    local Frame = Instance.new("Frame")
    Frame.Name = s1
    Frame.Size = UDim2.fromScale(10, 10)
    Frame.AnchorPoint = Vector2.new(0.5, 0.5)
    Frame.Position = UDim2.fromScale(0.5, 0.5)
    local v3 = u1 or Color3.new(0, 0, 0)
    Frame.BackgroundColor3 = v3
    Frame.BackgroundTransparency = 1
    Frame.ZIndex = 3

    return Frame
end

function signedIntToColor(arg1) -- line: 34
    local v4 = bit32.band(arg1, 4294967295)
    local v5 = bit32.rshift(v4, 16)
    local v6 = bit32.band(v5, 255)
    local v7 = bit32.rshift(v4, 8)
    local v8 = bit32.band(v7, 255)
    local v9 = bit32.band(v4, 255)
    local _ = Color3.fromRGB(v6, v8, v9)

    return (tostring((string.format("#%02X%02X%02X", v6, v8, v9))))
end

function parseColor(arg2) -- line: 46
    local v11 = tonumber(arg2) or arg2

    if typeof(v11) == "number" then
        if v11 < 0 then
            return signedIntToColor(v11)
        end

        return (tostring(hex(v11, 6)))
    else
        return v11
    end
end

local BlammedLights_m = require(script.BlammedLights)
local t_3 = {}

function findFontWeight(arg3) -- line: 60
    for _, val in (Enum.FontWeight:GetEnumItems()) do
        if val.Value == arg3 then
            return val
        end
    end

    return nil
end

local v12 = createFullScreenFrame("Fade")
local v13 = createFullScreenFrame("Fade")
local v14 = nil
local v15 = 3
local v16 = nil
local v17 = nil
local v18 = nil
local _ = nil
local v20 = nil

function setSubtitleTarget(arg4) -- line: 84
    -- upvalues:
    --  [1] v17 (ref)

    if not v17 or not arg4 then
        return
    end

    v17.Parent = arg4
end

function setBarTarget(arg5) -- line: 89
    -- upvalues:
    --  [1] v20 (ref)
    --  [2] v18 (ref)
    --  [3] v1 (ref)

    v20 = arg5

    if v18 ~= nil then
        local v21 = arg5 or v1.Overlay
        v18.Parent = v21
    end

    setFadeTarget(arg5)
end

function setFadeTarget(arg6) -- line: 97
    -- upvalues:
    --  [1] _ (ref)
    --  [2] v12 (ref)
    --  [3] v1 (ref)

    _ = arg6

    if v12 ~= nil then
        local v22 = arg6 or v1.Overlay
        v12.Parent = v22
    end
end

local t_4 = {
    camZoomingMult = { "camGame.cameraBeatMultiplier", 1 },
    beatsPerZoom = { "camGame.cameraBeat", 4 },
    defaultCamZoom = { "camGame.defaultZoom", 1 }
}
local v23 = nil

function fireStageRemote(arg7, ...) -- line: 112
    -- upvalues:
    --  [1] v23 (ref)

    if v23 == nil then
        print("no stage remote")

        return
    end

    v23:FireServer(arg7, ...)
end

function setBarTransparency(arg8) -- line: 120
    -- upvalues:
    --  [1] v18 (ref)

    v18:SetAttribute("TargetTransparency", arg8)
end

function parseStepsToSeconds(arg9) -- line: 124
    -- upvalues:
    --  [1] t_1 (copy)

    return t_1.Conductor.StepCrochet / 1000 * arg9
end

function hex(arg10, arg11) -- line: 128
    local v24 = ""

    repeat
        local v25 = arg10 % 16 + 1
        v24 = string.sub("0123456789ABCDEF", v25, v25) .. v24
        arg10 = math.floor(arg10 / 16)
    until arg10 <= 0

    if arg11 ~= nil then
        if arg11 < #v24 then
            v24 = string.sub(v24, -arg11)
        end

        while true do
            if not (arg11 > #v24) then
                break
            end

            v24 = "0" .. v24
        end
    end

    return "#" .. v24
end

local t_5 = {
    ["BPM Change"] = function(arg12) -- line: 155
        -- upvalues:
        --  [1] t_1 (copy)

        t_1.Conductor.changeBPM(tonumber(arg12) or 100)
    end,
    ["Time Sig Change"] = function(arg13) -- line: 158
        -- upvalues:
        --  [1] t_1 (copy)

        local BPM = t_1.Conductor.BPM
        local v26 = string.split(arg13, "/")
        t_1.Conductor.BeatsPerMeasure = tonumber(v26[1] or "4") or 4
        t_1.Conductor.StepsPerBeat = tonumber(v26[2] or "4") or 4
        t_1.Conductor.changeBPM(BPM)
    end,
    ["Add Camera Zoom"] = function(arg14, arg15) -- line: 165
        -- upvalues:
        --  [1] v1 (ref)

        v1.setProperty("camGame.zoom", v1.getProperty("camGame.zoom") + (tonumber(arg14) or 0.015))
        v1.setProperty("camHUD.zoom", v1.getProperty("camHUD.zoom") + (tonumber(arg15) or 0.03))
    end,
    ["Set Camera Zoom"] = function(arg16, arg17) -- line: 169
        -- upvalues:
        --  [1] v1 (ref)

        local v29 = tonumber(arg16) or 1
        local v30 = (tonumber(arg17) or 0.001) / v1.playbackRate

        if v30 and v30 > 0 then
            v1.tweenProperty("camGame.defaultZoom", v29, v30, "sineInOut")

            return
        end

        v1.setProperty("camGame.defaultZoom", v29)
    end,
    ["Set HUD Zoom"] = function(arg18, arg19) -- line: 180
        -- upvalues:
        --  [1] v1 (ref)

        local v31 = tonumber(arg18) or 1
        local v32 = (tonumber(arg19) or 0) / v1.playbackRate

        if v32 and v32 > 0 then
            v1.tweenProperty("camHUD.defaultZoom", v31, v32, "sineInOut")

            return
        end

        v1.setProperty("camHUD.defaultZoom", v31)
    end,
    ["Blammed Lights"] = function(arg20, _) -- line: 191
        -- upvalues:
        --  [1] BlammedLights_m (copy)

        local v33 = tonumber(arg20) or 0
        BlammedLights_m.doBlammedLights(if v33 > 0 then true else false, v33)
    end,
    ["Set Scroll Speed"] = function(arg22, arg23) -- line: 195
        -- upvalues:
        --  [1] v1 (ref)
        --  [2] t_1 (copy)

        if not v1.Settings.SVChanges then
            return
        end

        local v35 = tonumber(arg22) or 1
        local v36 = (tonumber(arg23) or 0) / v1.playbackRate

        if v36 > 0 then
            t_1.varTweener:Create(
                v1,
                TweenInfo.new(v36, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { songSpeed = v35 }
            ):Play()

            return
        end

        v1.songSpeed = v35
    end,
    ["Change Scroll Speed"] = function(arg24, arg25) -- line: 210
        -- upvalues:
        --  [1] v1 (ref)
        --  [2] t_1 (copy)

        if not v1.Settings.SVChanges then
            return
        end

        local v38 = (tonumber(arg25) or 0) / v1.playbackRate
        local v39 = v1.Settings.ScrollSpeed
        local v40 = tonumber(arg24) or 1

        if not v1.Settings.ForceScrollSpeed or not v39 then
            v39 = v1.song.speed * v1.Settings.ScrollSpeed
        end

        local v41 = v39 * v1.balanceSpeedMult(v40, v39)

        if v38 > 0 then
            t_1.varTweener:Create(
                v1,
                TweenInfo.new(v38, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { songSpeed = v41 }
            ):Play()

            return
        end

        v1.songSpeed = v41
    end
}

function t_5.ZoomCamera(arg26) -- line: 228
    -- upvalues:
    --  [1] v1 (ref)

    local v43 = arg26.ease or "instant"
    local v44 = tonumber(arg26.zoom) or 1
    local v45 = if v43 == "instant" then 0.001 else tonumber(arg26.duration) or 1
    local v48 = (if arg26 == nil then "" else arg26.ease or "") .. (if arg26 == nil then "" else arg26.ease and arg26.easeDir or "")
    v1.cancelTweensOf("camGame.baseGameZoom")
    local TweenProperty = v1.tweenProperty
    TweenProperty(
        "camGame.baseGameZoom",
        v44,
        if v43 == "instant" then 0.001 else v1.Conductor.StepCrochet * v45 / 1000 / v1.playbackRate,
        if v43 ~= "instant" then v48 else "linear"
    )
end

function t_5.SetCameraBop(arg27) -- line: 238
    -- upvalues:
    --  [1] v1 (ref)

    local v51 = (tonumber(arg27.rate) or 1) * 4
    local v52 = tonumber(arg27.intensity) or 1
    v1.setProperty("camGame.cameraBeat", v51)
    v1.setProperty("camHUD.cameraBeat", v51)
    v1.setProperty("camGame.cameraBeatMultiplier", v52)
    v1.setProperty("camHUD.cameraBeatMultiplier", v52)
end

t_5["Set Game Zoom"] = function(arg28, arg29) -- line: 248
    -- upvalues:
    --  [1] v1 (ref)

    local v53 = tonumber(arg28) or 1
    local v54 = (tonumber(arg29) or 0) / v1.playbackRate

    if v54 and v54 > 0 then
        v1.tweenProperty("camGame.defaultZoom", v53, v54, "sineInOut")

        return
    end

    v1.setProperty("camGame.defaultZoom", v53)
end

t_5["Screen Shake"] = function(arg30, arg31) -- line: 258
    -- upvalues:
    --  [1] v1 (ref)

    local v55 = string.split(arg30, ",")
    local v56 = string.split(arg31, ",")

    for index = 1, 2 do
        local v57 = if index ~= 1 then "camHUD" else "camGame"
        local v58 = if index ~= 1 then v56 else v55 or v56

        if #v58 ~= 0 then
            v1.setProperty(v57 .. "._shakeDuration", (tonumber(v58[1]) or 0) / v1.playbackRate)
            v1.setProperty(v57 .. "._shakeIntensity", tonumber(v58[2]) or 0)
        end
    end
end

t_5["HUD Shake"] = function(arg32, arg33, _, _) -- line: 273
    callEvent("Screen Shake", "0,0", `{arg32},{arg33}`)
end

t_5["Camera Shake"] = function(arg36, arg37) -- line: 276
    callEvent("Screen Shake", `{arg36},{arg37}`, "0,0")
end

t_5["Play Animation"] = function(arg38, arg39, arg40) -- line: 279
    -- upvalues:
    --  [1] v1 (ref)

    local v63 = if arg39 then if arg39:lower() == "dad" then "L" else "R" else "R"

    if if arg39 then if arg39:lower() ~= "gf" then if arg39:lower() ~= "girlfriend" then false else true else true else false then
        if v1.GFCharacter ~= nil then
            v1.GFCharacter:Play(arg38)
        end

        if arg40 ~= nil then
            fireStageRemote("GFEventAnimation", arg40, arg38)
        end

        return
    end

    for _, val_1 in (v1.getCharacters(v63)) do
        val_1:Play(arg38)
    end
end

function t_5.PlayAnimation(arg41, _, arg43) -- line: 294
    callEvent("Play Animation", arg41.anim, arg41.target, arg43)
end

t_5["Hey!"] = function(arg44, _, arg46) -- line: 297
    local v65 = if arg44 ~= nil then if arg44 ~= "" then if arg44:lower() ~= "bf" then if arg44:lower() ~= "boyfriend" then if arg44:lower() ~= "0" then false else true else true else true else true else true
    callEvent(
        "Play Animation",
        "Hey",
        if not (if arg44:lower() ~= "gf" then if arg44:lower() ~= "girlfriend" then if arg44:lower() ~= "1" then false else true else true else true) then if not v65 then "dad" else "bf" else "gf",
        arg46
    )
end

t_5["Switch Prefix"] = function(arg47, arg48, _) -- line: 302
    -- upvalues:
    --  [1] v1 (ref)

    local v68 = if arg48:lower() == "dad" then "L" else "R"

    if if arg48:lower() ~= "gf" then false else true then
        if v1.GFCharacter ~= nil then
            v1.GFCharacter.animPrefix = arg47
            v1.GFCharacter:Dance()
        end

        return
    end

    local v70 = if v68 ~= "R" then "L" else "R"

    for _, val_2 in (v1.getCharacters(v70)) do
        val_2.animPrefix = arg47
        val_2:Dance()
    end
end

t_5["Set Property"] = function(arg50, arg51) -- line: 319
    -- upvalues:
    --  [1] t_4 (copy)
    --  [2] v1 (ref)

    if t_4[arg50] then
        local v71 = t_4[arg50]
        arg50 = v71[1]
        arg51 = (tonumber(arg51) or 0) * v71[2]
    end

    v1.setProperty(arg50, arg51)
end

t_5["Afternight Window Title"] = function(arg52, _) -- line: 328
    -- upvalues:
    --  [1] v1 (ref)

    v1.setTitle(arg52)
end

t_5["Afternight Flash"] = function(arg54, arg55, _, arg57) -- line: 331
    -- upvalues:
    --  [1] v1 (ref)
    --  [2] t (copy)
    --  [3] t_2 (copy)

    if not v1.Settings.CameraFlash then
        return
    end

    local v73 = string.find(arg57, "Underlay") ~= nil
    local v74 = arg57
    local v75 = string.find(v74, "Reverse") ~= nil
    local v77 = (tonumber(arg54) or 1) / v1.playbackRate
    local color_1 = Color3.new(1, 1, 1)
    local Success, Result = pcall(function() -- line: 340
        -- upvalues:
        --  [1] color_1 (ref)
        --  [2] arg55 (copy)

        color_1 = Color3.fromHex(arg55)
    end)

    if Result or not Success then
        color_1 = Color3.new(1, 1, 1)
    end

    local v79 = v73 and v1.Underlay or v1.Overlay

    if v79:FindFirstChild("Flash") then
        v79.Flash:Destroy()
    end

    local v80 = createFullScreenFrame("Flash", color_1)
    v80.BackgroundTransparency = if not v75 then 0 else 1
    v80.Visible = true
    v80.Parent = v79
    local TweenService = t.TweenService
    local tweenInfo_2 = TweenInfo.new(v77)
    TweenService:Create(v80, tweenInfo_2, { BackgroundTransparency = if not v75 then 1 else 0 }):Play()
    t.Debris:AddItem(v80, v77 + 1)
    table.insert(t_2, v80)
end

t_5["Afternight Flash Reverse"] = "Afternight Flash"
t_5["Afternight Underlay Flash"] = "Afternight Flash"
t_5["Afternight Flash Underlay"] = "Afternight Flash"
t_5["Afternight Underlay Flash Reverse"] = "Afternight Flash"
t_5["Afternight Flash Underlay Reverse"] = "Afternight Flash"

t_5["Afternight HUD Fade"] = function(arg58, arg59) -- line: 363
    -- upvalues:
    --  [1] v1 (ref)

    local v84 = (tonumber(arg59) or 1) / v1.playbackRate

    if arg58 == "true" or arg58 == true or arg58 == 1 then
        v1.HUDApi:ShowHUD(v84)

        return
    end

    v1.HUDApi:HideHUD(v84)
end

t_5["Afternight Game Fade"] = function(arg60, arg61) -- line: 371
    -- upvalues:
    --  [1] v1 (ref)
    --  [2] t_1 (copy)

    local v85 = (tonumber(arg61) or 1) / v1.playbackRate
    local v86 = shared.getReceptors()

    if arg60 == "true" or arg60 == true or arg60 == 1 then
        v1.HUDApi:ShowHUD(v85)
        local _ = shared.getStrumsByName("player")

        for _, val_3 in v86 do
            t_1.varTweener:Create(
                val_3,
                TweenInfo.new(v85, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
                { alpha = 1 }
            ):Play()
        end

        return
    end

    v1.HUDApi:HideHUD(v85)

    for _, val_4 in v86 do
        t_1.varTweener:Create(
            val_4,
            TweenInfo.new(v85, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
            { alpha = 0 }
        ):Play()
    end
end

t_5["Afternight HUD Alpha"] = function(arg62, arg63) -- line: 389
    -- upvalues:
    --  [1] v1 (ref)

    local v87 = 1 - (tonumber(arg62) or 0)
    v1.HUDApi:HideHUD((tonumber(arg63) or 1) / v1.playbackRate, v87)
end

t_5["Afternight Strums Alpha"] = function(arg64, arg65) -- line: 395
    -- upvalues:
    --  [1] v1 (ref)
    --  [2] t_1 (copy)

    local v88 = (tonumber(arg65) or 1) / v1.playbackRate
    local v89 = tonumber(arg64) or 0

    for _, val_5 in (shared.getReceptors()) do
        t_1.varTweener:Create(
            val_5,
            TweenInfo.new(v88, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
            { alpha = v89 }
        ):Play()
    end
end

t_5["Afternight Strums Side Alpha"] = function(arg66, arg67) -- line: 404
    -- upvalues:
    --  [1] v1 (ref)

    local v90 = v1.getStrumsBySide(arg66)
    local num = tonumber(arg67)

    for _, val_6 in v90 do
        val_6.alpha = num
    end
end

t_5["Afternight Game Alpha"] = function(arg68, arg69, _, _) -- line: 412
    callEvent("Afternight HUD Alpha", arg68, arg69)
    callEvent("Afternight Strums Alpha", arg68, arg69)
end

t_5["Afternight Fade ZIndex"] = function(arg72) -- line: 416
    -- upvalues:
    --  [1] v15 (ref)

    v15 = tonumber(arg72) or 3
end

t_5["Afternight Fade"] = function(arg73, arg74, _, arg76) -- line: 419
    -- upvalues:
    --  [1] v1 (ref)
    --  [2] v13 (ref)
    --  [3] v12 (ref)
    --  [4] v15 (ref)
    --  [5] v14 (ref)
    --  [6] t (copy)

    local v91 = (tonumber(arg73) or 1) / v1.playbackRate
    local v92 = tonumber(arg74) or 1
    local v93 = if string.find(arg76, "Underlay") == nil then false else true
    local v94 = v93 and v13 or v12

    if v94 == nil then
        v94 = createFullScreenFrame("Fade")
        v94.Parent = v93 and v1.Underlay or v1.Overlay
        v94.ZIndex = v15
    end

    if v14 ~= nil then
        v14:Cancel()
    end

    v94.BackgroundTransparency = v92
    v94.Visible = true
    local v96 = v91 or 1
    local v97 = v96 <= 0.01 and true
    local v98 = 1 - v92

    if v97 then
        v94.BackgroundTransparency = v98

        return
    end

    v14 = t.TweenService:Create(v94, TweenInfo.new(v96), { BackgroundTransparency = v98 })
    v14:Play()
end

t_5["Afternight Fade Underlay"] = "Afternight Fade"

t_5["Afternight Reset Fade"] = function(_, _) -- line: 451
    -- upvalues:
    --  [1] v14 (ref)
    --  [2] _ (ref)
    --  [3] v15 (ref)
    --  [4] v12 (ref)
    --  [5] v1 (ref)
    --  [6] v13 (ref)

    if v14 ~= nil then
        v14:Cancel()
        v14 = nil
    end

    _ = nil
    v15 = 3

    if v12 ~= nil then
        v12:Destroy()
    end

    v12 = createFullScreenFrame("Fade")
    v12.Parent = v1.Overlay

    if v13 ~= nil then
        v13:Destroy()
    end

    v13 = createFullScreenFrame("Fade")
    v13.Parent = v1.Underlay
end

t_5["Afternight Bars"] = function(arg79, arg80, _, arg82) -- line: 472
    -- upvalues:
    --  [1] v1 (ref)
    --  [2] v18 (ref)
    --  [3] v20 (ref)
    --  [4] t (copy)
    --  [5] t_1 (copy)

    local v99 = tonumber(arg79) or 0
    local v100 = v99 / 100
    local v101 = v100 / 2
    local v102 = (tonumber(arg80) or 1) / v1.playbackRate
    local v103 = if string.find(arg82, "Underlay") == nil then false else true
    local v104 = v18
    local v105 = if v100 == 0 then 1 else v18:GetAttribute("TargetTransparency")
    v104.Parent = v20 and v20 or (v103 and v1.Underlay or v1.Overlay)

    for _, child in v104:GetChildren() do
        child.Visible = true
    end

    t.TweenService:Create(
        v104.TopBar,
        TweenInfo.new(v102, Enum.EasingStyle.Quad),
        { Position = UDim2.fromScale(0.5, v101) }
    ):Play()
    t.TweenService:Create(
        v104.BottomBar,
        TweenInfo.new(v102, Enum.EasingStyle.Quad),
        { Position = UDim2.fromScale(0.5, 1 - v101) }
    ):Play()

    if v105 == 1 then
        task.delay(v102 / 10 * 9, function() -- line: 491
            -- upvalues:
            --  [1] t (ref)
            --  [2] v104 (copy)
            --  [3] v102 (copy)
            --  [4] v105 (copy)

            t.TweenService:Create(
                v104.TopBar,
                TweenInfo.new(v102 / 10, Enum.EasingStyle.Quad),
                { BackgroundTransparency = v105 }
            ):Play()
            t.TweenService:Create(
                v104.BottomBar,
                TweenInfo.new(v102 / 10, Enum.EasingStyle.Quad),
                { BackgroundTransparency = v105 }
            ):Play()
        end)
    else
        t.TweenService:Create(
            v104.TopBar,
            TweenInfo.new(v102 / 10, Enum.EasingStyle.Quad),
            { BackgroundTransparency = v105 }
        ):Play()
        t.TweenService:Create(
            v104.BottomBar,
            TweenInfo.new(v102 / 10, Enum.EasingStyle.Quad),
            { BackgroundTransparency = v105 }
        ):Play()
    end

    if if string.find(arg82, "Note Movement") == nil then false else true then
        for _, val_7 in (shared.getReceptors()) do
            local VarTweener_5 = t_1.varTweener
            local tweenInfo_13 = TweenInfo.new(
                v102,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out
            )
            local t_17 = { y = nil }
            local v109 = _G["defaultStrum" .. tostring(val_7.strumIndex) .. "Y"]
            local v110 = v1.getSetting(val_7.side, "Downscroll") and -v99 or v99
            t_17.y = v109 + v110 * 2.75
            VarTweener_5:Create(val_7, tweenInfo_13, t_17):Play()
        end
    end
end

t_5["Afternight Bars with Note Movement"] = "Afternight Bars"
t_5["Afternight Bars Underlay with Note Movement"] = "Afternight Bars"
t_5["Afternight Bars Underlay"] = "Afternight Bars"

t_5["Afternight Subtitles"] = function(arg83, arg84) -- line: 511
    -- upvalues:
    --  [1] v1 (ref)
    --  [2] v17 (ref)
    --  [3] v16 (ref)
    --  [4] t (copy)
    --  [5] Modules (copy)
    --  [6] t_1 (copy)

    if not v1.Settings.ShowSubtitles then
        return
    end

    local v112 = arg83 ~= nil and tostring(arg83) or ""
    local v113 = if arg84 == nil then {} else string.split(arg84, ",") or {}
    local string_split = string.split
    local v115 = "\n"
    local v116 = #string_split(v112, v115)
    local v117 = Color3.new
    v115 = 1
    v117 = v117(1, v115, 1)
    local font = nil
    v115 = nil
    local v122 = "Height"
    local v121 = v17:GetAttribute(v122)

    if v113[1] ~= nil and v113[1] ~= "" then
        function v122() -- line: 525
            -- upvalues:
            --  [1] v117 (ref)
            --  [2] v113 (copy)

            v117 = Color3.fromHex(v113[1])
        end

        local _
        _, v122 = pcall(v122)

        if v122 then
            v117 = Color3.new(1, 1, 1)
        end
    end

    if v113[2] ~= nil and v113[2] ~= "" then
        v122 = v113[2]
        local v124 = string.split(v122, ":")
        v122 = 400

        for key_9, val_8 in v124 do
            if key_9 == 1 then
                v115 = val_8
            elseif key_9 == 2 then
                v122 = tonumber(val_8)
            end
        end

        local _, _ = pcall(function() -- line: 541
            -- upvalues:
            --  [1] font (ref)
            --  [2] v115 (ref)
            --  [3] v122 (ref)

            font = Font.fromName(v115, findFontWeight(v122))
        end)
    end

    if v113[3] ~= nil and v113[3] ~= "" then
        local function v127() -- line: 547
            -- upvalues:
            --  [1] v121 (ref)
            --  [2] v113 (copy)

            v121 = tonumber(v113[3])
        end

        local _
        _, v127 = pcall(v127)

        if v127 then
            v121 = v17:GetAttribute("Height")
        end
    end

    if v112 == "" then
        if v16 then
            for _, descendant in v17:GetDescendants() do
                if descendant.ClassName == "ImageLabel" then
                    t.TweenService:Create(
                        descendant,
                        TweenInfo.new(0.25 / v1.playbackRate),
                        { ImageTransparency = 1 }
                    ):Play()
                end
            end
        else
            t.TweenService:Create(
                v17,
                TweenInfo.new(0.25 / v1.playbackRate, Enum.EasingStyle.Quad),
                { TextTransparency = 1 }
            ):Play()
        end
    else
        v17.Size = UDim2.fromScale(0.95, v121 * v116)
        local FromScale_1 = UDim2.fromScale
        local v130 = v17
        local v131 = v1.getSetting(nil, "Downscroll") and 1 - v17:GetAttribute("Position") or v17:GetAttribute(
            "Position"
        )
        v130.Position = FromScale_1(0.5, v131)
        v17.Text = v112
        v17.TextColor3 = v117
        t.TweenService:Create(
            v17,
            TweenInfo.new(0.001, Enum.EasingStyle.Quad),
            { TextTransparency = 0 }
        ):Play()

        if v16 then
            v16:Revert()
            v16 = nil
        end

        if v115 ~= nil then
            if string.sub(v115, 1, 1) == "+" then
                if Modules.Other.RBX_CustomFont:FindFirstChild(v115:sub(2)) then
                    if v117 == Color3.new(0, 0, 0) then
                        v17.TextColor3 = Color3.new(1, 1, 1)
                    end

                    v16 = t_1.CustomFont.Replace(v115:sub(2), v17)
                else
                    v17.FontFace = Font.fromName("PressStart2P", Enum.FontWeight.Regular)

                    if v117 == Color3.new(0, 0, 0) then
                        v17.TextStrokeColor3 = Color3.new(1, 1, 1)
                    else
                        v17.TextStrokeColor3 = Color3.new(0, 0, 0)
                    end
                end
            elseif font ~= nil then
                if v117 == Color3.new(0, 0, 0) then
                    v17.TextStrokeColor3 = Color3.new(1, 1, 1)
                else
                    v17.TextStrokeColor3 = Color3.new(0, 0, 0)
                end

                v17.FontFace = font
            end
        elseif font ~= nil then
            if v117 == Color3.new(0, 0, 0) then
                v17.TextStrokeColor3 = Color3.new(1, 1, 1)
            else
                v17.TextStrokeColor3 = Color3.new(0, 0, 0)
            end

            v17.FontFace = font
        end
    end
end

t_5["Add CamOnly Zoom"] = function(arg85, _) -- line: 605
    -- upvalues:
    --  [1] v1 (ref)

    v1.setProperty("camGame.zoom", v1.getProperty("camGame.zoom") + (tonumber(arg85) or 0.015))
end

t_5["Codename Afternight Camera Shake"] = function(arg87) -- line: 703
    local v146 = arg87[1]
    local v147 = tonumber(arg87[2]) or 0.005
    callEvent(if v146 then "HUD Shake" else "Camera Shake", tonumber(arg87[3]) or 1, v147)
end

t_5["Codename Afternight Bars"] = function(arg88) -- line: 711
    local v151 = "Afternight Bars"
    local v152 = tonumber(arg88[1]) or 0
    local v153 = tonumber(arg88[2]) or 1

    if arg88[4] then
        v151 ..= " Underlay"
    end

    if arg88[3] then
        v151 ..= " with Note Movement"
    end

    callEvent(v151, v152, v153)
end

t_5["Codename Afternight Fade"] = function(arg89) -- line: 724
    local v154 = "Afternight Fade"
    local v155 = tonumber(arg89[1]) or 1
    local v156 = tonumber(arg89[2]) or 1

    if arg89[3] == true then
        v154 ..= " Underlay"
    end

    callEvent(v154, v156, v155)
end

t_5["Codename Afternight Subtitles"] = function(arg90) -- line: 734
    callEvent(
        "Afternight Subtitles",
        arg90[1] or "",
        `{parseColor(arg90[2]) or "#FFFFFF"},{arg90[3] or "Montserrat"}:{arg90[4] or 400}`
    )
end

t_5["Codename Add Camera Zoom"] = function(arg91) -- line: 740
    -- upvalues:
    --  [1] v1 (ref)

    local v159 = arg91[2] or "camHUD"
    local v160 = v159 .. ".zoom"
    local v161 = tonumber(arg91[1]) or 0.015
    v1.setProperty(v160, v1.getProperty(v159 .. ".zoom") + v161)
end

t_5["Codename Camera Bop"] = function(arg92) -- line: 746
    -- upvalues:
    --  [1] v1 (ref)

    local v162 = (tonumber(arg92[1]) or 4) * 4
    local v163 = tonumber(arg92[2]) or 1
    v1.setProperty("camGame.cameraBeat", v162)
    v1.setProperty("camHUD.cameraBeat", v162)
    v1.setProperty("camGame.cameraBeatMultiplier", v163)
    v1.setProperty("camHUD.cameraBeatMultiplier", v163)
end

t_5["Codename BPM Change"] = function(arg93) -- line: 756
    -- upvalues:
    --  [1] t_1 (copy)

    t_1.Conductor.changeBPM((tonumber(tonumber(arg93[1]) or 100)))
end

t_5["Codename Change Stage Zoom"] = function(arg94) -- line: 760
    -- upvalues:
    --  [1] v1 (ref)

    local v164 = tonumber(arg94[5]) or 1

    if arg94[1] == true then
        v1.setProperty("camGame.defaultZoom", v164)
    end

    if arg94[2] == true then
        for _, val_9 in (v1.getCharacters("L")) do
            val_9.zoom = v164
        end
    end

    if arg94[3] == true then
        for _, val_10 in (v1.getCharacters("R")) do
            val_10.zoom = v164
        end
    end
end

t_5["Codename Scroll Speed Change"] = function(arg95) -- line: 775
    -- upvalues:
    --  [1] v1 (ref)
    --  [2] t_1 (copy)

    if not v1.Settings.SVChanges then
        return
    end

    local v165 = tonumber(arg95[2]) or 1
    local v168 = parseStepsToSeconds(tonumber(arg95[3]) or 0) / v1.playbackRate
    local v169 = "linear"
    local v170 = arg95[6]

    if arg95[4] then
        v169 = arg95[4]
    end

    if arg95[5] then
        v169 ..= arg95[5]
    end

    local v171 = v1.getTweenStyle(v169)
    local v172 = v1.getTweenDir(v169)
    local v173 = v1.Settings.ForceScrollSpeed and v1.Settings.ScrollSpeed or v1.song.speed * v1.Settings.ScrollSpeed
    local v174 = if not v170 then v165 else v173 * v1.balanceSpeedMult(v165, v173)

    if v168 > 0 then
        t_1.varTweener:Create(v1, TweenInfo.new(v168, v171, v172), { songSpeed = v174 }):Play()

        return
    end

    v1.songSpeed = v174
end

t_5["Codename Time Signature Change"] = function(arg96) -- line: 809
    callEvent("Time Sig Change", `{arg96[1]}/{arg96[2]}`, "")
end

t_5["Codename Camera Flash"] = function(arg97) -- line: 812
    local v177 = "Afternight Flash"

    if arg97[4] ~= "camHUD" then
        v177 ..= " Underlay"
    end

    if arg97[1] then
        v177 ..= " Reverse"
    end

    callEvent(v177, tostring(parseStepsToSeconds(arg97[3])), parseColor(arg97[2]))
end

t_5["Codename Alt Animation Toggle"] = function(arg98) -- line: 822
    -- upvalues:
    --  [1] v1 (ref)

    local v179 = if arg98[3] ~= 0 then "R" else "L"

    if if arg98[3] ~= 2 then false else true then
        if v1.GFCharacter ~= nil then
            local GFCharacter = v1.GFCharacter
            GFCharacter.animPrefix = if not arg98[2] then "" else "ALT"
            v1.GFCharacter:Dance()
        end

        return
    end

    for _, val_11 in (v1.getCharacters(v179)) do
        val_11.animPrefix = if not arg98[2] then "" else "ALT"
        val_11:Dance()
    end
end

t_5["Codename Play Animation"] = function(arg99) -- line: 839
    local v183 = arg99[1]
    local v184 = if v183 ~= 0 then if v183 ~= 1 then "gf" else "bf" else "dad"
    callEvent("Play Animation", arg99[2], v184)
end

t_5["Codename Camera Zoom"] = function(arg100) -- line: 845
    -- upvalues:
    --  [1] v1 (ref)

    local v185 = if arg100[3] ~= "camHUD" then "camGame" else "camHUD"
    local v188 = arg100[2] * (if arg100[7] == "direct" then 1 else tonumber(
        v1.getProperty("camGame.baseZoom")
    ) or 1)

    if arg100[8] then
        v188 *= tonumber(v1.getProperty(v185 .. ".zoom") or 1)
    end

    if arg100[1] == false then
        v1.setProperty(v185 .. ".zoom", v188)
        v1.setProperty(v185 .. ".defaultZoom", v188)

        return
    end

    local v190 = parseStepsToSeconds(arg100[4]) / v1.playbackRate
    local v191 = `{arg100[5]}{arg100[6]}`
    v1.tweenProperty(v185 .. ".defaultZoom", v188, v190, v191)
    v1.tweenProperty(v185 .. ".zoom", v188, v190, v191)
end

t_5["Codename Camera Module Change"] = function(arg101) -- line: 862
    -- upvalues:
    --  [1] v1 (ref)

    local v192 = if string.upper(arg101[3]) ~= "STEP" then if string.upper(arg101[3]) ~= "BEAT" then 16 else 4 else 1
    v1.setProperty("cams.cameraBeat", arg101[1] * v192)
    v1.setProperty("cams.cameraBeatMultiplier", tonumber(arg101[2]) or 1)
end

for key_14, val_12 in t_5 do
    if typeof(val_12) == "string" then
        t_5[key_14] = t_5[val_12]
    end
end

function callEvent(arg102, arg103, arg104, arg105) -- line: 876
    -- upvalues:
    --  [1] t_5 (copy)

    local v193 = t_5[arg102]

    if v193 == nil then
        return
    end

    v193(arg103, arg104, arg105, arg102)
end

local t_19 = {
    onCreate = nil,
    eventCases = nil,
    callEvent = nil,
    clearUp = nil,
    setSubtitleTarget = nil,
    setBarTarget = nil,
    setBarTransparency = nil,
    setFadeTarget = nil,
    getCurrentFade = nil
}

function t_19.onCreate(arg106, arg107) -- line: 884
    -- upvalues:
    --  [1] v1 (ref)
    --  [2] v23 (ref)
    --  [3] v17 (ref)
    --  [4] v18 (ref)
    --  [5] v12 (ref)
    --  [6] v13 (ref)
    --  [7] BlammedLights_m (copy)

    v1 = arg107
    v23 = arg106
    local Subtitles = v1.Overlay._Subtitles

    if Subtitles then
        v17 = Subtitles:Clone()
        v17.Name = "Subtitles"
        v17.Visible = true
        v17.Parent = v1.Overlay
    end

    v18 = script.EventBars:Clone()
    setBarTarget(nil)

    for _, child_1 in v18:GetChildren() do
        if child_1:IsA("GuiObject") then
            child_1.Visible = true
        end
    end

    if v12 ~= nil then
        v12:Destroy()
    end

    v12 = createFullScreenFrame("Fade")
    v12.Parent = v1.Overlay

    if v13 ~= nil then
        v13:Destroy()
    end

    v13 = createFullScreenFrame("Fade")
    v13.Parent = v1.Underlay
    BlammedLights_m.onCreate(v1)
end

t_19.eventCases = t_5
t_19.callEvent = callEvent

function t_19.clearUp() -- line: 922
    -- upvalues:
    --  [1] v1 (ref)
    --  [2] v17 (ref)
    --  [3] v16 (ref)
    --  [4] BlammedLights_m (copy)
    --  [5] t_3 (copy)
    --  [6] t_2 (copy)
    --  [7] v14 (ref)
    --  [8] v12 (ref)
    --  [9] v13 (ref)
    --  [10] _ (ref)
    --  [11] v18 (ref)
    --  [12] v2 (ref)

    if v1 == nil then
        return
    end

    if v17 then
        if v16 then
            v16:Revert()
        end

        v17:Destroy()
    end

    BlammedLights_m.clearUp()
    table.clear(t_3)

    for _, val_13 in t_2 do
        if val_13 then
            val_13:Destroy()
        end
    end

    table.clear(t_2)

    if v14 ~= nil then
        v14:Cancel()
        v14 = nil
    end

    if v12 ~= nil then
        v12:Destroy()
    end

    v12 = createFullScreenFrame("Fade")
    v12.Parent = v1.Overlay

    if v13 ~= nil then
        v13:Destroy()
    end

    v13 = createFullScreenFrame("Fade")
    v13.Parent = v1.Underlay
    _ = nil

    if v18 ~= nil then
        v18:Destroy()
    end

    if v2 and v2.Destroy then
        v2:Destroy()
        v2 = nil
    end

    v1 = nil
end

t_19.setSubtitleTarget = setSubtitleTarget
t_19.setBarTarget = setBarTarget
t_19.setBarTransparency = setBarTransparency
t_19.setFadeTarget = setFadeTarget

function t_19.getCurrentFade() -- line: 975
    -- upvalues:
    --  [1] v12 (ref)

    return v12
end

return t_19
