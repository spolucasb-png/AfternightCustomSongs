local t = {}
t.__index = t
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _ = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Signal_m = require(Modules.Lib.Signal)
local Logger_m = require(Modules.Other.Logger)
local AudioWindowSize_Medium = Enum.AudioWindowSize.Medium
local v1 = if AudioWindowSize_Medium == Enum.AudioWindowSize.Large then 4096 else if AudioWindowSize_Medium ~= Enum.AudioWindowSize.Small then 1024 else 256
latency_samples = v1 * 0.75
local v2 = latency_samples / 48000
Logger_m.log("Internal pitch effect offset used:", v2 * 1000, "ms")

function v1(u1: userdata, u2: userdata) --[[ new ]] -- line: 102
    -- upvalues:
    --  [1] Signal_m (copy)
    --  [2] t (copy)
    --  [3] AudioWindowSize_Medium (copy)

    if pcall(function() -- line: 103
        -- upvalues:
        --  [1] u1 (copy)

        return u1:GetOutputPins()
    end) and not u2 then
        u2 = u1
    end

    local t_2 = setmetatable(
        {
            isStatic = false,
            curAudio = nil,
            curAudioChanged = Signal_m.new(),
            curPath = "",
            playingPaths = {},
            paths = {},
            audios = {},
            timeLength = -1,
            timeLengthChanged = Signal_m.new(),
            speed = 1,
            pitched = true,
            paused = true,
            parent = u1,
            output = u2,
            timePosition = 0,
            _startTime = 0,
            ended = Signal_m.new()
        },
        t
    )
    local PitchEffect_AudioPitchShifter = Instance.new("AudioPitchShifter")
    PitchEffect_AudioPitchShifter.Pitch = 1
    PitchEffect_AudioPitchShifter.Bypass = true
    PitchEffect_AudioPitchShifter.WindowSize = AudioWindowSize_Medium
    PitchEffect_AudioPitchShifter.Name = "PitchEffect"
    local AudioFader = Instance.new("AudioFader")
    AudioFader.Volume = 0.6683439175686147
    AudioFader.Bypass = true
    local Wire = Instance.new("Wire")
    Wire.SourceInstance = PitchEffect_AudioPitchShifter
    Wire.TargetInstance = AudioFader
    local Wire_1 = Instance.new("Wire")
    Wire_1.SourceInstance = AudioFader
    Wire_1.TargetInstance = u2
    t_2.pitchEffect = PitchEffect_AudioPitchShifter
    t_2.pitchEffectWire = Wire
    t_2.volFix = AudioFader
    t_2.volFixWire = Wire_1
    Wire.Parent = PitchEffect_AudioPitchShifter
    Wire_1.Parent = AudioFader
    PitchEffect_AudioPitchShifter.Parent = u1
    AudioFader.Parent = u1
    t_2.streamTarget = PitchEffect_AudioPitchShifter
    t_2.streamFinal = Wire_1

    return t_2
end

t.new = v1

function t.setSpeed(t1: table, n1: number) -- line: 201
    t1.speed = n1
    local v3 = not t1.pitched and n1 ~= 1
    t1.isPitchEffectUsed = v3
    v3 = t1.volFix

    if v3 then
        v3.Bypass = not t1.isPitchEffectUsed
    end

    local PitchEffect = t1.pitchEffect

    if PitchEffect then
        PitchEffect.Bypass = not t1.isPitchEffectUsed
        PitchEffect.Pitch = 1 / n1
    end

    for _, val in t1.paths do
        for _, val_1 in val.audios do
            val_1.Obj.PlaybackSpeed = n1 * val_1.Speed
        end
    end
end

function t.setPitched(t2: table, b1: boolean) -- line: 225
    t2.pitched = b1 or false
    local v4 = b1 and t2.speed ~= 1
    t2.isPitchEffectUsed = v4
    v4 = t2.volFix

    if v4 then
        v4.Bypass = not t2.isPitchEffectUsed
    end

    local PitchEffect_1 = t2.pitchEffect

    if PitchEffect_1 then
        PitchEffect_1.Bypass = not t2.isPitchEffectUsed
    end
end

function t.setOutput(t3: table, u3: userdata) -- line: 240
    t3.output = u3
    local VolFixWire = t3.volFixWire

    if VolFixWire then
        VolFixWire.TargetInstance = u3
    end
end

function t.getAudios(arg1) -- line: 249
    local t_3 = {}

    for _, val_2 in arg1.audios do
        table.insert(t_3, val_2.Obj)
    end

    return t_3
end

local t_4 = {}

function getIdInfo(arg2) -- line: 260
    -- upvalues:
    --  [1] t_4 (ref)

    local v6 = t_4[tostring(arg2)] or (t_4[tonumber(arg2) or -1] or arg2)

    if type(v6) == "table" then
        return v6
    end

    return { Id = v6 }
end

function t.setIdOverrides(_: table, t5: table) -- line: 271
    -- upvalues:
    --  [1] t_4 (ref)

    t_4 = t5
end

function t.parsePath(t6: table, t7: table, s1: string?) -- line: 275
    local t_6 = {
        usesSplits = false,
        splitLength = 0,
        splitGap = 10,
        playing = false,
        audios = {},
        audiosByName = {},
        wires = {},
        pathName = s1,
        curSplit = 0,
        length = -1,
        folder = Instance.new("Folder")
    }
    t_6.folder.Name = s1 or "unnamedPath"

    if t7.Segments then
        local v8 = t7.InitVolumeMult or 1

        if v8 <= 0 and t6.isStatic then
            return
        end

        local Wire_2 = Instance.new("Wire")
        Wire_2.Parent = t_6.folder
        table.insert(t_6.wires, Wire_2)
        local t_7 = {}

        for index = 1, #t7.Segments do
            local _ = #t7.Segments
            table.insert(t_7, t7.Segments[index][1])
        end

        local v11 = getIdInfo(table.concat(t_7, ","))

        if type(v11) ~= "table" then
            v11 = {}
        end

        local v12 = v11.SegmentExtraTime or (t7.SegmentExtraTime or 10)
        local v13 = v11.SegmentLength or (t7.SegmentLength or 0)
        t_6.usesSplits = true
        local v14 = v11.Speed or (t7.Speed or 1)
        t_6.splitLength = v13 / v14
        t_6.splitGap = v12
        t_6.length = 0
        local v16 = v11.Segments or t7.Segments

        for index_1 = 1, #v16 do
            local v17 = v11.Segments or t7.Segments
            local _ = #v16
            v16 = v17[index_1]
            v17 = v16[1]

            if v17 then
                local AudioPlayer = Instance.new("AudioPlayer")
                local v19 = s1 and s1 .. "/" or ""
                AudioPlayer.Name = v19 .. "Segment" .. index_1
                local v20 = Content.fromUri("rbxassetid://" .. (v17 or ""))
                v19 = v16[3] or (v11.Speed or (t7.Speed or 1))
                local v21 = v16[2] or (v11.Volume or (t7.Volume or 1))
                local v22 = v11.Side or (t7.Side or nil)
                local v23 = v11.ChannelLayout or (t7.ChannelLayout or nil)
                t_6.length += v13 / v19
                AudioPlayer.AudioContent = v20
                AudioPlayer.PlaybackSpeed = t6.speed * v19
                AudioPlayer.Volume = v21 * v8
                AudioPlayer.Parent = t_6.folder

                if v22 then
                    local AudioChannelSplitter = Instance.new("AudioChannelSplitter")
                    local AudioChannelMixer = Instance.new("AudioChannelMixer")
                    AudioChannelSplitter.Layout = Enum.AudioChannelLayout:FromName(v23 or "Stereo") or Enum.AudioChannelLayout.Stereo
                    AudioChannelMixer.Layout = Enum.AudioChannelLayout.Mono
                    local Wire_3 = Instance.new("Wire")
                    Wire_3.SourceName = v22
                    Wire_3.SourceInstance = AudioChannelSplitter
                    Wire_3.TargetName = "Center"
                    Wire_3.TargetInstance = AudioChannelMixer
                    Wire_3.Parent = AudioChannelSplitter
                    local Wire_4 = Instance.new("Wire")
                    Wire_4.SourceInstance = AudioChannelMixer
                    Wire_4.TargetInstance = t6.streamTarget
                    Wire_4.Parent = AudioChannelMixer
                    Wire_2.TargetInstance = AudioChannelSplitter
                    table.insert(t_6.wires, Wire_3)
                    table.insert(t_6.wires, Wire_4)
                    AudioChannelSplitter.Parent = t_6.folder
                    AudioChannelMixer.Parent = t_6.folder
                else
                    Wire_2.TargetInstance = t6.streamTarget
                end

                table.insert(
                    t_6.audios,
                    {
                        Obj = AudioPlayer,
                        Speed = v19,
                        Volume = v21,
                        Name = "Segment" .. index_1,
                        Wire = Wire_2
                    }
                )
                t_6.audiosByName["Segment" .. index_1] = t_6.audios[#t_6.audios]
            end
        end

        t_6.mainAudio = t_6.audios[#t_6.audios]
    else
        if not t7.SoundNames then
            local v25 = t7.Instrumental and t7.Instrumental ~= 0
            local v26 = t7.Voices and t7.Voices ~= 0
            local t_9 = {}

            if v25 then
                table.insert(t_9, "Instrumental")
            end

            if v26 then
                table.insert(t_9, "Voices")
            end

            t7.SoundNames = t_9
        end

        if table.find(t7.SoundNames, t7.MainSound or "") then
            t7.MainSound = t7.SoundNames[1]
        end

        local v27 = nil
        local v29, v30, v31, v32, v33, v34, v35, v36

        for _, val_3 in t7.SoundNames do
            local v28 = t7[val_3]

            if v28 then
                if type(v28) == "table" then
                    v29 = getIdInfo(v28.Id) or getIdInfo(v28[1])
                    v30 = Content.fromUri("rbxassetid://" .. (v29.Id or ""))
                    v31 = v29.Volume or (v28.Volume or (t7.Volume or 1))
                    v32 = v31
                    v31 = v28.InitVolumeMult or (t7.InitVolumeMult or 1)
                    v33 = v31
                    v31 = v29.Speed or (v28.Speed or (t7.Speed or 1))
                    v34 = v31
                    v31 = v29.Side or (v28.Side or (t7.Side or nil))
                    v35 = v31
                    v31 = v29.ChannelLayout or (v28.ChannelLayout or (t7.ChannelLayout or nil))
                    v36 = v31
                else
                    v29 = getIdInfo(v28)
                    v31 = v28

                    if typeof(v28) ~= "Content" or not v31 then
                        v31 = Content.fromUri("rbxassetid://" .. (v29.Id or ""))
                    end

                    v30 = v31
                    v31 = v29.Volume or (t7[val_3 .. "Volume"] or (t7.Volume or 1))
                    v32 = v31
                    v31 = t7[val_3 .. "InitVolumeMult"] or (t7.InitVolumeMult or 1)
                    v33 = v31
                    v31 = v29.Speed or (t7[val_3 .. "Speed"] or (t7.Speed or 1))
                    v34 = v31
                    v31 = v29.Side or (t7[val_3 .. "Side"] or (t7.Side or nil))
                    v35 = v31
                    v31 = v29.ChannelLayout or (t7[val_3 .. "ChannelLayout"] or (t7.ChannelLayout or nil))
                    v36 = v31
                end

                if not (v33 <= 0) or not t6.isStatic then
                    local AudioPlayer_1 = Instance.new("AudioPlayer")
                    local v37 = s1 and s1 .. "/" or ""
                    AudioPlayer_1.Name = v37 .. val_3
                    AudioPlayer_1.AudioContent = v30
                    AudioPlayer_1.PlaybackSpeed = t6.speed * v34
                    AudioPlayer_1.Volume = v32 * v33
                    local Wire_5 = Instance.new("Wire")
                    Wire_5.Parent = AudioPlayer_1

                    if v35 then
                        local AudioChannelSplitter_1 = Instance.new("AudioChannelSplitter")
                        local AudioChannelMixer_1 = Instance.new("AudioChannelMixer")
                        AudioChannelSplitter_1.Layout = Enum.AudioChannelLayout:FromName(
                            v36 or "Stereo"
                        ) or Enum.AudioChannelLayout.Stereo
                        AudioChannelMixer_1.Layout = Enum.AudioChannelLayout.Mono
                        local Wire_6 = Instance.new("Wire")
                        Wire_6.SourceName = v35
                        Wire_6.SourceInstance = AudioChannelSplitter_1
                        Wire_6.TargetName = "Center"
                        Wire_6.TargetInstance = AudioChannelMixer_1
                        Wire_6.Parent = AudioChannelSplitter_1
                        local Wire_7 = Instance.new("Wire")
                        Wire_7.SourceInstance = AudioChannelMixer_1
                        Wire_7.TargetInstance = t6.streamTarget
                        Wire_7.Parent = AudioChannelMixer_1
                        Wire_5.TargetInstance = AudioChannelSplitter_1
                        table.insert(t_6.wires, Wire_6)
                        table.insert(t_6.wires, Wire_7)
                        AudioChannelSplitter_1.Parent = AudioPlayer_1
                        AudioChannelMixer_1.Parent = AudioPlayer_1
                    else
                        Wire_5.TargetInstance = t6.streamTarget
                    end

                    AudioPlayer_1.Parent = t_6.folder
                    table.insert(t_6.wires, Wire_5)
                    table.insert(
                        t_6.audios,
                        {
                            Obj = AudioPlayer_1,
                            Speed = v34,
                            Volume = v32,
                            Name = val_3,
                            Wire = Wire_5
                        }
                    )

                    if t7.MainSound == val_3 then
                        v27 = t_6.audios[#t_6.audios]
                    end

                    t_6.audiosByName[val_3] = t_6.audios[#t_6.audios]
                end
            end
        end

        t6:setMainAudioForPath(v27 or t_6.audios[1], t_6)
    end

    t_6.folder.Parent = t6.parent

    return t_6
end

function t.setMainAudioForPath(arg3, arg4, arg5) -- line: 520
    if not arg5 then
        return
    end

    arg5.mainAudio = arg4

    if not arg4 then
        return
    end

    arg5.length = arg4.Obj.TimeLength / arg4.Speed

    if arg5.length <= 0 then
        arg4.Obj:GetPropertyChangedSignal("TimeLength"):Once(function() -- line: 528
            -- upvalues:
            --  [1] arg5 (copy)
            --  [2] arg4 (copy)
            --  [3] arg3 (copy)

            if arg5.mainAudio ~= arg4 then
                return
            end

            arg5.length = arg4.Obj.TimeLength / arg4.Speed

            if arg3.curPath == arg5.pathName then
                arg3.timeLength = arg5.length
                arg3.timeLengthChanged:Fire(arg5.length)
            end
        end)
    end
end

function t.setVolume(t8: table, n2: number, s2: string?, s3: string?) -- line: 542
    if s3 and s2 then
        local v40 = t8.paths[s3]

        if not v40 then
            return warn("[SongPlayer] Tried to set volume of non-existent path")
        end

        local v41 = v40.audiosByName[s2]

        if not v41 then
            return warn("[SongPlayer] Tried to set volume of non-existent audio")
        end

        v41.Obj.Volume = v41.Volume * n2

        return
    end

    if s3 and not s2 then
        local v42 = t8.paths[s3]

        if not v42 then
            return warn("[SongPlayer] Tried to set volume of non-existent path")
        end

        for _, val_4 in v42.audios do
            val_4.Obj.Volume = val_4.Volume * n2
        end

        return
    end

    if not s3 and s2 then
        for _, val_5 in t8.audios do
            if val_5.Name == s2 then
                val_5.Obj.Volume = val_5.Volume * n2
            end
        end

        return
    end

    for _, val_6 in t8.audios do
        val_6.Obj.Volume = val_6.Volume * n2
    end
end

function t.tweenVolume(
    t9: table,
    u4: userdata,
    n3: number,
    s4: string?,
    s5: string?
) -- line: 575
    -- upvalues:
    --  [1] TweenService (copy)

    if s4 then
        local v43 = t9.paths[s4]

        if not v43 then
            return warn("[SongPlayer] Tried to set volume of non-existent path")
        end

        for _, val_7 in v43.audios do
            if not s5 or val_7.Name == s5 then
                TweenService:Create(val_7.Obj, u4, { Volume = val_7.Volume * n3 }):Play()
            end
        end

        return
    else
        for _, val_8 in t9.paths do
            for _, val_9 in val_8.audios do
                if not s5 or val_9.Name == s5 then
                    TweenService:Create(val_9.Obj, u4, { Volume = val_9.Volume * n3 }):Play()
                end
            end
        end

        return
    end
end

function t.load(t10: table, t11: table) -- line: 594
    if next(t10.paths) then
        t10:unload()
    end

    if not t11.Paths then
        t11 = { Paths = { _default = t11 }, StartingPaths = { "_default" } }
    end

    if t11.DefaultPath and not t11.StartingPaths then
        t11.StartingPaths = t11.DefaultPath
    end

    if type(t11.StartingPaths) == "string" then
        t11.StartingPaths = { t11.StartingPaths }
    end

    for key_10, val_10 in t11.Paths do
        if not t11.StartingPaths then
            t11.StartingPaths = { key_10 }
        end

        if table.find(t11.StartingPaths, key_10) or not t10.isStatic then
            local v44 = t10:parsePath(val_10, key_10)

            if v44 then
                t10.paths[key_10] = v44

                for _, val_11 in v44.audios do
                    table.insert(t10.audios, val_11)
                end
            end
        end
    end

    t10:setPosition(0)
    t10:switchPath(t11.StartingPaths)
end

function t.unload(arg6) -- line: 637
    -- upvalues:
    --  [1] AudioWindowSize_Medium (copy)

    arg6:Pause()

    for _, val_12 in arg6.paths do
        for _, val_13 in val_12.wires do
            val_13.SourceInstance = nil
            val_13.TargetInstance = nil
            val_13:Destroy()
        end

        for _, val_14 in val_12.audios do
            val_14.Obj:Destroy()
        end

        if val_12.folder then
            val_12.folder:Destroy()
        end
    end

    table.clear(arg6.paths)
    table.clear(arg6.audios)

    if arg6.pitchEffect then
        local AudioPitchShifter_1 = Instance.new("AudioPitchShifter")
        AudioPitchShifter_1.Pitch = 1 / arg6.speed
        AudioPitchShifter_1.Bypass = not arg6.isPitchEffectUsed
        AudioPitchShifter_1.WindowSize = AudioWindowSize_Medium
        AudioPitchShifter_1.Name = "PitchEffect"
        AudioPitchShifter_1.Parent = arg6.parent
        local PitchEffectWire = arg6.pitchEffectWire
        PitchEffectWire.SourceInstance = AudioPitchShifter_1
        PitchEffectWire.Parent = AudioPitchShifter_1

        if arg6.streamTarget == arg6.pitchEffect then
            arg6.streamTarget = AudioPitchShifter_1
        end

        arg6.pitchEffect:Destroy()
        arg6.pitchEffect = AudioPitchShifter_1
    end
end

local v45 = 0
local t_15 = {}

local _ = function() --[[ acquireLengthSlot ]] -- line: 693
    -- upvalues:
    --  [1] v45 (ref)
    --  [2] t_15 (copy)

    if v45 >= 10 then
        table.insert(t_15, coroutine.running())
        coroutine.yield()

        return
    end

    v45 += 1
end

local _ = function() --[[ releaseLengthSlot ]] -- line: 702
    -- upvalues:
    --  [1] t_15 (copy)
    --  [2] v45 (ref)

    local v47 = table.remove(t_15, 1)

    if v47 then
        task.spawn(v47)

        return
    end

    v45 -= 1
end

local function loadRawLength(arg7) -- line: 711
    local AudioPlayer_2 = Instance.new("AudioPlayer")
    AudioPlayer_2.AudioContent = Content.fromUri("rbxassetid://" .. tostring(arg7))
    AudioPlayer_2.Parent = game:GetService("SoundService")
    local v48 = AudioPlayer_2.TimeLength

    if v48 <= 0 then
        local thread = coroutine.running()
        local v49 = false
        local TimeLength_1 = AudioPlayer_2:GetPropertyChangedSignal("TimeLength"):Connect(function() -- line: 721
            -- upvalues:
            --  [1] v49 (ref)
            --  [2] AudioPlayer_2 (copy)
            --  [3] thread (copy)

            if v49 or AudioPlayer_2.TimeLength <= 0 then
                return
            end

            v49 = true
            task.spawn(thread, AudioPlayer_2.TimeLength)
        end)
        task.delay(10, function() -- line: 727
            -- upvalues:
            --  [1] v49 (ref)
            --  [2] thread (copy)

            if v49 then
                return
            end

            v49 = true
            task.spawn(thread, 0)
        end)
        v48 = coroutine.yield()
        TimeLength_1:Disconnect()
    end

    AudioPlayer_2:Destroy()

    return v48
end

local t_16 = {}
local t_17 = {}

local function getAssetLength(arg8) -- line: 741
    -- upvalues:
    --  [1] t_16 (copy)
    --  [2] t_17 (copy)
    --  [3] v45 (ref)
    --  [4] t_15 (copy)
    --  [5] loadRawLength (copy)

    if t_16[arg8] then
        return t_16[arg8]
    end

    local v50 = t_17[arg8]

    if v50 then
        table.insert(v50, coroutine.running())

        return coroutine.yield()
    end

    local t_18 = {}
    t_17[arg8] = t_18

    if v45 >= 10 then
        table.insert(t_15, coroutine.running())
        coroutine.yield()
    else
        v45 += 1
    end

    local v52 = 0

    for _ = 1, 5 do
        v52 = loadRawLength(arg8)

        if v52 > 0 then
            break
        end
    end

    local v53 = table.remove(t_15, 1)

    if v53 then
        task.spawn(v53)
    else
        v45 -= 1
    end

    if v52 > 0 then
        t_16[arg8] = v52
    end

    local v54
    t_17[arg8], v54 = nil, t_18

    for _, val_15 in v54 do
        task.spawn(val_15, v52)
    end

    return v52
end

function t.getTotalLength(arg9) -- line: 775
    -- upvalues:
    --  [1] getAssetLength (copy)

    if not arg9 then
        return 0
    end

    local v55 = arg9.Audio or arg9

    if v55.Paths then
        local v56 = v55.StartingPaths and v55.StartingPaths[1] or next(v55.Paths)
        v55 = v55.Paths[v56]

        if not v55 then
            return 0
        end
    end

    local v57, v59

    if v55.Segments and #v55.Segments > 0 then
        v57 = v55.SegmentLength or 0
        local v58 = v55.Speed or 1
        v59 = 0

        for _, val_16 in v55.Segments do
            v59 += v57 / (val_16[3] or v58)
        end

        return v59
    end

    v57 = v55.MainSound or (v55.SoundNames and v55.SoundNames[1] or "Instrumental")
    local v60 = v55[v57] or (v55.Instrumental or v55.Voices)
    v59 = nil
    local v61 = v55.Speed or 1

    if type(v60) == "table" then
        v59 = v60.Id or v60[1]
        v61 = v60.Speed or v61
    elseif type(v60) == "number" then
        v59 = v60
    end

    if not v59 then
        return 0
    end

    local v63 = getAssetLength(v59)

    if v63 > 0 then
        return v63 / v61
    end

    return 0
end

function t.Destroy(arg10) -- line: 821
    arg10:unload()

    if arg10.pitchEffect then
        arg10.pitchEffect:Destroy()
        arg10.pitchEffect = nil
        arg10.pitchEffectWire = nil
    end

    if arg10.volFix then
        arg10.volFix:Destroy()
        arg10.volFix = nil
        arg10.volFixWire = nil
    end
end

function t.Play(arg11) -- line: 838
    arg11:setPosition(0)
    arg11:Resume()
end

function t.Resume(arg12) -- line: 843
    if not arg12.curAudio then
        return
    end

    local Paused = arg12.paused
    arg12.paused = false
    arg12._appliedFix = 0
    arg12._lastRbxPos = (arg12.timePosition * 1000 + 0.5) // 1 / 1000
    arg12._startTime = os.clock() - arg12.timePosition / arg12.speed

    if Paused then
        for _, val_17 in arg12.audios do
            val_17.Obj:Play()
        end
    end
end

function t.ResumeSyncedWith(t12: table) -- line: 862
    local t_19 = {}
    local clock_1 = os.clock()

    for _, val_18 in t12 do
        local Paused_1 = val_18.paused
        val_18.paused = false
        val_18._appliedFix = 0
        val_18._lastRbxPos = (val_18.timePosition * 1000 + 0.5) // 1 / 1000
        val_18._startTime = clock_1 - val_18.timePosition / val_18.speed

        if Paused_1 then
            local Audios = val_18.audios
            table.move(
                Audios,
                1,
                #Audios,
                #t_19 + 1,
                t_19
            )
        end
    end

    for _, val_19 in t_19 do
        val_19.Obj:Play()
    end
end

function t.Pause(arg13) -- line: 888
    if not arg13.paused then
        arg13:update()
    end

    arg13.paused = true

    for _, val_20 in arg13.audios do
        val_20.Obj:Stop()
    end
end

function t.update(arg14) -- line: 900
    -- upvalues:
    --  [1] v2 (ref)

    if arg14.paused then
        return
    end

    local Speed = arg14.speed
    local Paths = arg14.paths
    local clock_2 = os.clock()
    local AppliedFix = arg14._appliedFix

    if AppliedFix ~= 10 then
        local v64 = Paths[arg14.curPath]

        if not v64 then
            return
        end

        local CurAudio = arg14.curAudio
        local v65 = CurAudio.Obj.TimePosition / CurAudio.Speed + v64.splitLength * v64.curSplit

        if v65 - arg14._lastRbxPos > 0 then
            if AppliedFix == 0 then
                arg14._startTime = clock_2 - v65 / Speed
            else
                arg14._startTime += (clock_2 - v65 / Speed - arg14._startTime) * 0.2
            end

            arg14._appliedFix += 1
            arg14._lastRbxPos = v65
        end
    end

    local v68 = (clock_2 - arg14._startTime) * Speed - (arg14.isPitchEffectUsed and v2 or 0)
    arg14.timePosition = v68

    for key_21, val_21 in Paths do
        if val_21.usesSplits then
            local v69 = (v68 - 1.5) / Speed // (val_21.splitLength / Speed)

            if val_21.curSplit < v69 then
                val_21.curSplit = v69
                local v70 = val_21.audios[v69 + 1]

                if v70 then
                    local Obj = v70.Obj
                    Obj.Looping = false

                    if val_21.playing then
                        v70.Wire.SourceInstance = Obj

                        if key_21 == arg14.curPath then
                            arg14:setCurAudio(v70)
                        end
                    end
                end
            end
        end
    end
end

function t.setPosition(t13: table, n4: number) -- line: 960
    local v71 = not t13.paused

    if v71 then
        t13:Pause()
    end

    t13.timePosition = n4

    for key_22, val_22 in t13.paths do
        if val_22.usesSplits then
            local v72 = math.max((n4 - 1.5) / t13.speed // (val_22.splitLength / t13.speed), 0)
            val_22.curSplit = v72
            local v73 = v72 + 1
            local v74 = if key_22 ~= t13.curPath then false else true

            if v73 > #val_22.audios then
                for _, val_23 in val_22.wires do
                    val_23.SourceInstance = nil
                end

                if v74 then
                    t13:setCurAudio(val_22.audios[#val_22.audios])
                end
            end

            for key_24, val_24 in val_22.audios do
                local Obj_1 = val_24.Obj
                local v75 = v73 < key_24 and true
                Obj_1.TimePosition = n4 % val_22.splitLength * val_24.Speed
                Obj_1.Looping = v75
                local v76 = if not v75 then val_22.splitGap else 0
                Obj_1.LoopRegion = NumberRange.new(0, val_22.splitLength * val_24.Speed + v76)

                if key_24 == v73 and val_22.playing then
                    val_24.Wire.SourceInstance = Obj_1

                    if v74 then
                        t13:setCurAudio(val_24)
                    end
                end
            end
        else
            if key_22 == t13.curPath then
                t13:setCurAudio(val_22.mainAudio)
            end

            for _, val_25 in val_22.audios do
                val_25.Obj.TimePosition = n4 * val_25.Speed
            end
        end
    end

    if v71 then
        t13:Resume()
    end
end

function t.setCurAudio(arg15, arg16) -- line: 1020
    if arg15.curAudio == arg16 then
        return
    end

    if arg15._audioEnded then
        arg15._audioEnded:Disconnect()
        arg15._audioEnded = nil
    end

    if arg16 then
        arg15._audioEnded = arg16.Obj.Ended:Connect(function() -- line: 1026
            -- upvalues:
            --  [1] arg15 (copy)

            arg15.ended:Fire()
        end)
    end

    arg15.curAudio = arg16
    arg15.curAudioChanged:Fire(arg16)
end

function t.getLength(t14: table, s6: string?) -- line: 1035
    local v77 = t14.paths[s6 or ""] or t14.paths[t14.curPath]

    if v77 then
        return v77.length
    end

    return -1
end

function t.switchPath(t15: table, s7: string?) -- line: 1044
    local v78 = type(s7) == "string" and { s7 } or s7

    if not v78 then
        return warn("[SongPlayer] Invalid path list")
    end

    local v79 = t15.paths[v78[1] or ""]

    if not v79 then
        return warn("[SongPlayer] Main path not found: " .. (v78[1] or ""))
    end

    t15.curPath = v78[1]
    t15.playingPaths = v78
    t15.timeLength = v79.length
    t15.timeLengthChanged:Fire(v79.length)

    if v79.usesSplits then
        t15:setCurAudio(v79.audios[v79.curSplit + 1])
    else
        t15:setCurAudio(v79.mainAudio)
    end

    for key_26, val_26 in t15.paths do
        local Playing = val_26.playing
        local v80 = table.find(v78, key_26)

        if Playing and not v80 then
            val_26.playing = false

            for _, val_27 in val_26.wires do
                val_27.SourceInstance = nil
            end
        elseif not Playing and v80 then
            val_26.playing = true

            if val_26.usesSplits then
                local v81 = val_26.audios[val_26.curSplit + 1]

                if v81 then
                    v81.Wire.SourceInstance = v81.Obj
                end
            else
                for _, val_28 in val_26.audios do
                    val_28.Wire.SourceInstance = val_28.Obj
                end
            end
        end
    end
end

function t.stats(arg17) -- line: 1089
    local v82 = 0

    for _, _ in arg17.paths do
        v82 += 1
    end

    local v83 = 0

    for _, _ in arg17.audios do
        v83 += 1
    end

    return { totalPaths = v82, totalAudios = v83, curPath = arg17.curPath }
end

return t
