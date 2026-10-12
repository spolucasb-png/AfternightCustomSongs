local _ = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local t = {
    BPM = 0,
    Step = 0,
    Beat = 0,
    Measure = 0,
    Paused = false,
    Crochet = 0,
    StepCrochet = 0,
    SongPosition = 0,
    TimePosition = 0,
    RawTimePosition = 0,
    CurrentTrackPos = 0,
    Offset = 0,
    SafeFrames = 10,
    SafeZoneOffset = 166,
    BPMChangeMap = {},
    CurBPM = 0,
    BaseBPM = 0,
    TotalPos = 0,
    TotalSteps = 0,
    StepsPerBeat = 4,
    BeatsPerMeasure = 4,
    DecimalStep = 0,
    DecimalBeat = 0,
    DecimalMeasure = 0
}
local t_1 = { __index = nil }
local t_2 = {
    bpm = "BPM",
    curStep = "Step",
    currentStep = "Step",
    curBeat = "Beat",
    currentBeat = "Beat",
    curMeasure = "Measure",
    currentMeasure = "Measure",
    crochet = "Crochet",
    SongPos = "SongPosition",
    songPosition = "SongPosition",
    TimePos = "TimePosition",
    timePosition = "TimePosition",
    safeZoneOffset = "SafeZoneOffset",
    stepCrochet = "StepCrochet",
    decimalStep = "DecimalStep",
    currentStepFloat = "DecimalStep",
    currentBeatFloat = "DecimalBeat",
    decimalBeat = "DecimalBeat",
    decimalMeasure = "DecimalMeasure",
    stepsPerBeat = "StepsPerBeat",
    beatsPerMeasure = "BeatsPerMeasure"
}

function t_1.__index(arg1, arg2) -- line: 61
    -- upvalues:
    --  [1] t_2 (copy)

    return (rawget(arg1, t_2[arg2] or arg2))
end

setmetatable(t, t_1)

function round(arg3, arg4) -- line: 67
    local v1 = 10 ^ (arg4 or 0)

    return math.floor(arg3 * v1 + 0.5) / v1
end

function t.setSongPos(arg5) -- line: 72
    -- upvalues:
    --  [1] t (copy)

    local v2 = arg5 + t.Offset
    t.SongPosition = v2 * 1000
    t.TimePosition = v2
    t.RawTimePosition = arg5
end

function t.init(arg6: any, n1: number?) -- line: 80
    -- upvalues:
    --  [1] t (copy)

    t.BPM = arg6
    t.Step = 0
    t.Beat = 0
    t.Measure = 0
    t.Paused = false
    t.BeatsPerMeasure = 4
    t.StepsPerBeat = 4
    t.Crochet = 60 / t.BPM * 1000 * (4 / t.StepsPerBeat)
    t.StepCrochet = t.Crochet / 4
    t.SongPosition = -(t.Crochet * 4)
    t.TimePosition = t.SongPosition / 1000
    t.RawTimePosition = t.TimePosition
    t.Offset = n1 or 0
    t.SafeZoneOffset = t.SafeFrames / 60 * 1000
    t.BPMChangeMap = {}
end

function t.mapBPMChanges(arg7) -- line: 103
    -- upvalues:
    --  [1] t (copy)

    t.BPMChangeMap = {}
    t.CurBPM = arg7.song.bpm
    t.BaseBPM = arg7.song.bpm
    t.TotalSteps = 0
    t.TotalPos = 0
    local v3

    if arg7.song.timeSignature then
        v3 = string.split(arg7.song.timeSignature, "/")
        t.BeatsPerMeasure = tonumber(v3[1])
        t.StepsPerBeat = tonumber(v3[2])
    end

    v3 = t.BeatsPerMeasure or 4
    local v6 = t.StepsPerBeat or 4

    if arg7.bpmChanges then
        for _, val in arg7.bpmChanges do
            if val.bpm ~= t.CurBPM then
                t.CurBPM = round(val.bpm, 2)
                v3 = if not val.beatsPerMeasure then v3 else if val.beatsPerMeasure == v3 then v3 else val.beatsPerMeasure
                v6 = if not val.stepsPerBeat then v6 else if val.stepsPerBeat == v6 then v6 else val.stepsPerBeat
                local v8 = 60 / t.CurBPM * 1000 * (4 / v6)
                table.insert(
                    t.BPMChangeMap,
                    {
                        stepTime = val.startTime / t.StepCrochet,
                        songTime = val.startTime,
                        bpm = t.CurBPM,
                        beatsPerMeasure = v3,
                        stepsPerBeat = v6,
                        crochet = v8,
                        stepCrochet = v8 / 4
                    }
                )
            end
        end
    else
        arg7 = arg7.song

        if not arg7.notes then
            warn("There's something wrong with the chart? idk")

            return t.BPMChangeMap
        end

        local v9 = 60 / t.CurBPM * 1000 * (4 / v6) / 4

        for index = 1, #arg7.notes do
            local v10 = arg7.notes[index]
            local _ = #arg7.notes

            if v10 ~= nil then
                if v10.changeBPM and v10.bpm ~= t.CurBPM then
                    t.CurBPM = v10.bpm
                    v3 = if not v10.beatsPerMeasure then v3 else if v10.beatsPerMeasure == v3 then v3 else v10.beatsPerMeasure
                    v6 = if not v10.stepsPerBeat then v6 else if v10.stepsPerBeat == v6 then v6 else v10.stepsPerBeat
                    local v12 = 60 / t.CurBPM * 1000 * (4 / v6)
                    v9 = v12 / 4
                    table.insert(
                        t.BPMChangeMap,
                        {
                            stepTime = t.TotalSteps,
                            songTime = t.TotalPos,
                            bpm = t.CurBPM,
                            crochet = v12,
                            stepCrochet = v9
                        }
                    )
                end

                local v14 = (v10.sectionBeats or (v10.lengthInSteps and v10.lengthInSteps / 4 or v3)) * 4
                local v15 = t
                v15.TotalSteps += v14
                local v16 = t
                v16.TotalPos += v9 * v14
            end
        end
    end

    return t.BPMChangeMap
end

function t.changeBPM(arg8) -- line: 205
    -- upvalues:
    --  [1] t (copy)

    t.BPM = arg8
    t.Crochet = 60 / t.BPM * 1000 * (4 / t.StepsPerBeat)
    t.StepCrochet = t.Crochet / 4
end

return t
