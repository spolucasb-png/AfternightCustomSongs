local t: any = {}
t.__index = t
local Signal_m: any = require(
    game:GetService("ReplicatedStorage"):WaitForChild("Modules").Lib.Signal
)

function t.new() -- line: 16
    -- upvalues:
    --  [1] Signal_m (copy)
    --  [2] t (copy)

    local t_1: table = {}
    local t_2: table = {}
    local t_4: any = setmetatable(
        {
            _calls = t_1,
            _registeredFuncs = t_2,
            isCloned = {},
            scripts = {},
            aliases = {},
            onError = Signal_m.new(),
            onPreAdd = Signal_m.new(),
            onAdd = Signal_m.new(),
            onRemove = Signal_m.new()
        },
        t
    )

    local function v1(arg1) -- line: 35
        -- upvalues:
        --  [1] t_4 (copy)

        t_4.onError:Fire(arg1)
    end

    function t_4.call(_: table, s1: string, ...) -- line: 40
        -- upvalues:
        --  [1] t_1 (copy)
        --  [2] v1 (copy)

        local v2: table = t_1[s1]

        if not v2 then
            return
        end

        for _, val in v2 do
            xpcall(val, v1, ...)
        end
    end

    function t_4.singleCall(_: table, t3: table, s2: string, ...) -- line: 49
        -- upvalues:
        --  [1] t_2 (copy)
        --  [2] v1 (copy)

        local v3: table? = t_2[t3]
        local v4: any = v3 and v3[s2] or nil

        if not v4 then
            local v5 = t3[s2]

            if not v5 then
                return
            end

            xpcall(v5, v1, ...)

            return
        else
            for _, val_1 in v4 do
                xpcall(val_1, v1, ...)
            end

            return
        end
    end

    return t_4
end

function t.defineAliases(t4: table, t5: table) -- line: 69
    local t_5: any = {}

    for key_2, val_2 in t5 do
        for _, val_3 in val_2 do
            t_5[val_3] = key_2
        end
    end

    t4.aliases = t_5
end

function t.mapScript(t6: table, t7: table) -- line: 81
    local Calls: any = t6._calls
    local Aliases: any = t6.aliases
    local t_6: any = {}
    local v7, v8

    for key_4, val_4 in t7 do
        if type(key_4) == "string" then
            if type(val_4) ~= "function" then
                print(key_4, type(key_4), val_4, (type(val_4)))
            else
                key_4 = Aliases[key_4] or key_4
                v7 = Calls[key_4]

                if not v7 then
                    Calls[key_4] = { val_4 }
                else
                    table.insert(v7, val_4)
                end

                v8 = t_6[key_4]

                if not v8 then
                    t_6[key_4] = { val_4 }
                else
                    table.insert(v8, val_4)
                end
            end
        else
            print(key_4, type(key_4), val_4, (type(val_4)))
            key_4 = Aliases[key_4] or key_4
            v7 = Calls[key_4]

            if not v7 then
                Calls[key_4] = { val_4 }
            else
                table.insert(v7, val_4)
            end

            v8 = t_6[key_4]

            if not v8 then
                t_6[key_4] = { val_4 }
            else
                table.insert(v8, val_4)
            end
        end
    end

    t6._registeredFuncs[t7] = t_6
end

function t.add(t8: table, arg2: any, b1: boolean?) -- line: 111
    if not arg2 then
        return
    end

    local v9 = arg2

    if typeof(arg2) == "Instance" then
        v9 = not b1 and arg2:Clone() or arg2
    end

    if typeof(v9) == "Instance" and v9 ~= arg2 then
        t8.isCloned[v9] = true
    end

    t8.onPreAdd:Fire(v9)
    local v11 = v9

    if type(v9) ~= "table" or not v11 then
        v11 = require(v9)
    end

    local v12
    t8.scripts[v9], v12 = v11, v11
    t8:mapScript(v12)
    t8.onAdd:Fire(v9, v11)

    return v11, v9
end

function t.remove(arg3, arg4) -- line: 135
    if not arg4 then
        return
    end

    local v13 = arg3.scripts[arg4]

    if not v13 then
        return
    end

    arg3.onRemove:Fire(arg4, v13)

    if arg3.isCloned[arg4] then
        arg4:Destroy()
    end

    local v14 = arg3._registeredFuncs[v13]

    if v14 then
        for key_5, val_5 in v14 do
            local v15 = arg3._calls[key_5]

            if v15 then
                for _, val_6 in val_5 do
                    local v16 = table.find(v15, val_6)

                    if v16 then
                        table.remove(v15, v16)
                    end
                end
            end
        end

        arg3._registeredFuncs[v13] = nil
    end

    arg3.scripts[arg4] = nil
end

function t.getModule(arg5, arg6) -- line: 167
    return arg5.scripts[arg6]
end

function t.removeAll(arg7) -- line: 171
    for key_7, _ in arg7.scripts do
        arg7:remove(key_7)
    end

    table.clear(arg7.scripts)
    table.clear(arg7._calls)
end

function t.stats(arg8) -- line: 180
    local t_7: any = {}
    local v17: number = 0

    for _, _ in arg8.scripts do
        v17 += 1
    end

    t_7.scripts = v17
    v17 = 0
    local v18: number = 0

    for _, val_9 in arg8._calls do
        v17 += 1
        v18 += #val_9
    end

    t_7.calls = v17
    t_7.callsRegistered = v18

    return t_7
end

return t
