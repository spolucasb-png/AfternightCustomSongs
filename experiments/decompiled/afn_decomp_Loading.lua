local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Events = ReplicatedStorage.Events
local IconV2_m = require(ReplicatedStorage.Modules.Main.IconV2)
local Adapters_m = require(ReplicatedStorage.Modules.Other.Adapters)
local Overheads_m = require(ReplicatedStorage.Modules.UI.Overheads)
local AssetIcons_m = require(ReplicatedStorage.Modules.UI.AssetIcons)
local v1 = require(ReplicatedStorage.Modules.Main.Translator).new("_Gameplay", { "Gameplay" })
local t = {
    UI = script.Loading:Clone(),
    TargetLocation = nil,
    BannerObjects = {},
    BannerSides = { L = {}, R = {} },
    Icons = {},
    Tweens = {}
}
t.UI.RootLocalizationTable = v1.localizationTable

local _ = function(arg1) --[[ isURI ]] -- line: 55
    if string.find(arg1, "^rbx") then
        return true
    end

    return false
end

function t.reset() -- line: 59
    -- upvalues:
    --  [1] t (copy)

    stopTweens()

    for _, val in t.BannerObjects do
        if val ~= nil then
            val:Destroy()
        end
    end

    for _, val_1 in t.Icons do
        if val_1 ~= nil then
            val_1:Destroy()
        end
    end

    table.clear(t.Icons)
    table.clear(t.BannerObjects)
    table.clear(t.BannerSides.L)
    table.clear(t.BannerSides.R)
    t.UI.LoadingLabel.CancelLoading.Visible = false
    t.UI.MatchType.Position = UDim2.fromScale(0.5, -0.1)
    t.UI.LoadingLabel.Position = UDim2.fromScale(0.5, 1.1)
    t.UI.Transition.Size = UDim2.fromScale(0, 0)
end

local function getTimeColor(u1: userdata, n1: number) -- line: 79
    if n1 == 0 then
        return u1.Keypoints[1].Value
    end

    if n1 == 1 then
        return u1.Keypoints[#u1.Keypoints].Value
    end

    for index = 1, #u1.Keypoints - 1 do
        local v2 = u1.Keypoints[index]
        local v3 = u1.Keypoints[index + 1]

        if n1 >= v2.Time and n1 < v3.Time then
            local v4 = (n1 - v2.Time) / (v3.Time - v2.Time)
            local _ = #u1.Keypoints - 1

            return Color3.new(
                (v3.Value.R - v2.Value.R) * v4 + v2.Value.R,
                (v3.Value.G - v2.Value.G) * v4 + v2.Value.G,
                (v3.Value.B - v2.Value.B) * v4 + v2.Value.B
            )
        end
    end
end

local function getRichText(arg2, arg3) -- line: 100
    -- upvalues:
    --  [1] getTimeColor (copy)

    local v6 = ""
    local v7 = 0
    local v9

    for key_2, val_2 in utf8.graphemes(arg2) do
        local v8 = arg2:sub(key_2, val_2)

        if arg3 then
            v9 = arg3

            if typeof(arg3) ~= "Color3" or not v9 then
                v9 = getTimeColor(arg3, v7 / #arg2) or Color3.new(1, 1, 1)
            end
        else
            v9 = Color3.new(1, 1, 1)
        end

        local v10 = v9:ToHex()
        v6 ..= `<font color='#{v10}'>{v8}</font>`
        v7 += 1
    end

    return v6
end

function stopTweens() -- line: 113
    -- upvalues:
    --  [1] t (copy)

    for _, val_3 in t.Tweens do
        if val_3 ~= nil and val_3.PlaybackState == Enum.PlaybackState.Playing then
            val_3:Cancel()
        end
    end
end

function t.setLoadingText(s1: string) -- line: 121
    -- upvalues:
    --  [1] t (copy)

    t.UI.LoadingLabel.Text = s1
end

function t.start(t1: table) -- line: 125
    -- upvalues:
    --  [1] t (copy)
    --  [2] Events (copy)
    --  [3] IconV2_m (copy)
    --  [4] AssetIcons_m (copy)
    --  [5] getRichText (copy)
    --  [6] Overheads_m (copy)
    --  [7] v1 (copy)
    --  [8] Adapters_m (copy)

    t.UI.Parent = t.TargetLocation
    t.UI.Visible = true
    t.reset()
    local CreateTwn = t.createTwn
    local Transition_1 = t.UI.Transition
    local t_2 = { Size = UDim2.fromScale(5, 5) }
    CreateTwn(
        Transition_1,
        TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
        t_2
    ):Play()
    local CreateTwn_1 = t.createTwn
    local VS = t.UI.VS
    local t_3 = { Size = UDim2.fromScale(0.2, 0.2) }
    CreateTwn_1(VS, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), t_3):Play()
    task.delay(0.5, function() -- line: 134
        -- upvalues:
        --  [1] t (ref)

        local tweenInfo_2 = TweenInfo.new(
            1.5,
            Enum.EasingStyle.Exponential,
            Enum.EasingDirection.Out
        )
        local t_4 = { Position = UDim2.fromScale(0.5, 0.02) }
        t.createTwn(t.UI.MatchType, tweenInfo_2, t_4):Play()
        local t_5 = { Position = UDim2.fromScale(0.5, 0.98) }
        t.createTwn(t.UI.LoadingLabel, tweenInfo_2, t_5):Play()
    end)
    local v19, v20, v26

    for key_4, val_4 in t1.Sides do
        for key_5, val_5 in val_4 do
            local v11 = val_5.IsBot and val_5 or Events.Overheads.GetPreviewOverheadData:InvokeServer(
                val_5.Player
            )
            local v12 = if key_4 ~= "L" then "Right" else "Left"
            local v14 = t.UI:FindFirstChild(`{v12}Side`)
            local v15 = v14.Template:Clone()
            v15.Name = `Player{key_5}`
            v15.Visible = true
            v15.Parent = v14
            local v16 = IconV2_m.new(
                v15.Banner.IconHolder.Icon,
                key_4,
                v11.HealthIcon,
                v11.HealthIconPack
            )
            table.insert(t.Icons, v16)
            v16.sFactors = Vector2.new(150, 375)
            v16.Position = UDim2.fromScale(0.5, 0.5)
            v16.anchor = Vector2.new(0.5, 0.5)
            v16.Scale = Vector2.new(1, 1)
            v16:ForceUpdate()

            if v11.IsBot and (v11.Banner == "None" and v11.BannerPack == nil) then
                v15.Banner.BannerHolder.Banner.Image = "rbxassetid://71711014610737"
            else
                local v17 = v11.BannerData or AssetIcons_m:format(
                    "Banners",
                    { name = v11.Banner, pack = v11.BannerPack }
                )
                local t_11 = nil

                if v11.ReplaceBannerByCustom and v11.CustomBannerImage then
                    local CustomBannerImage = v11.CustomBannerImage
                    local CustomBannerStyle = v11.CustomBannerStyle

                    if tonumber(CustomBannerImage) then
                        v19 = Content.fromAssetId((tonumber(CustomBannerImage)))

                        if not v19 then
                            v20 = if string.find(CustomBannerImage, "^rbx") then true else false
                            v19 = v20 and Content.fromUri(CustomBannerImage) or Content.none
                        end
                    else
                        v20 = if string.find(CustomBannerImage, "^rbx") then true else false
                        v19 = v20 and Content.fromUri(CustomBannerImage) or Content.none
                    end

                    t_11 = {
                        imgContent = v19,
                        antialiasing = true,
                        isBanner = true,
                        style = CustomBannerStyle or "Crop"
                    }
                end

                local t_8 = { fitFor = Vector2.new(1280, 256) }
                table.insert(
                    t.Icons,
                    (AssetIcons_m:render(v15.Banner.BannerHolder.Banner, t_11 or v17, t_8))
                )
            end

            if v11.IsBot then
                v15.Banner.BannerHolder.Username.Text = "BOT"
            else
                local v23 = ""

                for _, val_6 in v11.ImportantTags do
                    local v24 = val_6.RawTag or val_6.Tag
                    local v25 = getRichText
                    v26 = Overheads_m:formatTag(v24, v11.DisplayName)
                    local v28 = v25(`[{v26}]`, val_6.Color)
                    v23 ..= `<b>{v28}</b> `
                end

                for _, val_7 in v11.Tags do
                    v26 = val_7.RawTag or val_7.Tag
                    local v29 = getRichText
                    local v30 = Overheads_m:formatTag(v26, v11.DisplayName)
                    v23 ..= v29(`[{v30}]`, val_7.Color) .. " "
                end

                local Username = v15.Banner.BannerHolder.Username
                local v32 = if v23 == "" then "" else `{v23}\n`
                Username.Text = `{v32}{v11.DisplayName}\n@{v11.Username}`
            end

            table.insert(t.BannerObjects, v15)
            table.insert(t.BannerSides[key_4], v15)
        end
    end

    for _, val_8 in t.BannerSides do
        task.spawn(function() -- line: 193
            -- upvalues:
            --  [1] val_8 (copy)
            --  [2] t (ref)

            for _, val_9 in val_8 do
                t.createTwn(
                    val_9.Banner,
                    TweenInfo.new(1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                    { Position = UDim2.fromScale(0, 0) }
                ):Play()
                wait(0.3)
            end
        end)
    end

    local MatchType_2 = t.UI.MatchType
    MatchType_2.Text = if t1.IsSolo then v1.Get("Gameplay.Loading.SoloMatch") or v1.Format(
        "Gameplay.Loading.MultiplayerMatch",
        { LCount = t1.PlayerAmmo.L, RCount = t1.PlayerAmmo.R }
    ) else v1.Format(
        "Gameplay.Loading.MultiplayerMatch",
        { LCount = t1.PlayerAmmo.L, RCount = t1.PlayerAmmo.R }
    )
    local SongInfo = t.UI.MatchType.SongInfo
    local Mod = t1.Mod
    local Song = t1.Song
    local Difficulty = t1.Difficulty
    local v35

    if t1.Rate ~= 1 then
        local v34 = Adapters_m.floatToString(t1.Rate)
        v35 = ` [{v34}x]` or ""
    else
        v35 = ""
    end

    SongInfo.Text = `{Mod} - {Song} ({Difficulty}){v35}`
end

function t.createTwn(u2: userdata, u3: userdata, t2: table) -- line: 205
    -- upvalues:
    --  [1] TweenService (copy)
    --  [2] t (copy)

    local v36 = TweenService:Create(u2, u3, t2)
    table.insert(t.Tweens, v36)

    return v36
end

function t.finished() -- line: 211
    -- upvalues:
    --  [1] t (copy)

    stopTweens()
    local CreateTwn_5 = t.createTwn
    local VS_1 = t.UI.VS
    local t_16 = { Size = UDim2.fromScale(0) }
    CreateTwn_5(VS_1, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.In), t_16):Play()

    for key_10, val_10 in t.BannerSides do
        task.spawn(function() -- line: 216
            -- upvalues:
            --  [1] val_10 (copy)
            --  [2] key_10 (copy)
            --  [3] t (ref)

            for _, val_11 in val_10 do
                task.spawn(function() -- line: 218
                    -- upvalues:
                    --  [1] key_10 (ref)
                    --  [2] t (ref)
                    --  [3] val_11 (copy)

                    local v38 = if key_10 ~= "L" then 2 else -2
                    local udim2 = UDim2.fromScale(v38, 0)
                    t.createTwn(
                        val_11.Banner,
                        TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.In),
                        { Position = udim2 }
                    ):Play()
                    task.wait(1)
                    val_11:Destroy()
                end)
                wait(0.1)
            end
        end)
    end

    task.delay(0.3, function() -- line: 229
        -- upvalues:
        --  [1] t (ref)

        local tweenInfo_6 = TweenInfo.new(1, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
        local t_13 = { Position = UDim2.fromScale(0.5, -0.1) }
        t.createTwn(t.UI.MatchType, tweenInfo_6, t_13):Play()
        local t_14 = { Position = UDim2.fromScale(0.5, 1.1) }
        t.createTwn(t.UI.LoadingLabel, tweenInfo_6, t_14):Play()
    end)
    t.createTwn(
        t.UI.Transition,
        TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
        { Size = UDim2.fromScale(0, 0) }
    ):Play()
end

function t.showFailedLoad() -- line: 238
    -- upvalues:
    --  [1] t (copy)

    t.UI.LoadingLabel.CancelLoading.Visible = true
end

return t
