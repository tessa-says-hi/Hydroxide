local methods = {}
local Players = game:GetService("Players")
local client = Players.LocalPlayer

local serializableTypes = {
    Axes = true,
    BrickColor = true,
    CFrame = true,
    Color3 = true,
    ColorSequence = true,
    ColorSequenceKeypoint = true,
    DateTime = true,
    EnumItem = true,
    Faces = true,
    Font = true,
    Instance = true,
    NumberRange = true,
    NumberSequence = true,
    NumberSequenceKeypoint = true,
    OverlapParams = true,
    PathWaypoint = true,
    PhysicalProperties = true,
    Random = true,
    Ray = true,
    RaycastParams = true,
    Rect = true,
    Region3 = true,
    TweenInfo = true,
    UDim = true,
    UDim2 = true,
    Vector2 = true,
    Vector2int16 = true,
    Vector3 = true,
    Vector3int16 = true,
    buffer = true,
}

local function numberToString(value)
    if value ~= value then
        return "0 / 0"
    elseif value == math.huge then
        return "math.huge"
    elseif value == -math.huge then
        return "-math.huge"
    end

    return string.format("%.17g", value)
end

local function quoteString(value: string, maxLength: number?): string
    local suffix = ""
    if maxLength and #value > maxLength then
        value = value:sub(1, maxLength)
        suffix = "...<truncated>"
    end

    local out = table.create(#value + 2)
    table.insert(out, '"')

    for i = 1, #value do
        local byte = string.byte(value, i)
        if byte == 34 then
            table.insert(out, '\\"')
        elseif byte == 92 then
            table.insert(out, "\\\\")
        elseif byte == 7 then
            table.insert(out, "\\a")
        elseif byte == 8 then
            table.insert(out, "\\b")
        elseif byte == 9 then
            table.insert(out, "\\t")
        elseif byte == 10 then
            table.insert(out, "\\n")
        elseif byte == 11 then
            table.insert(out, "\\v")
        elseif byte == 12 then
            table.insert(out, "\\f")
        elseif byte == 13 then
            table.insert(out, "\\r")
        elseif byte < 32 or byte > 126 then
            table.insert(out, string.format("\\%03d", byte))
        else
            table.insert(out, string.char(byte))
        end
    end

    if suffix ~= "" then
        table.insert(out, suffix)
    end

    table.insert(out, '"')
    return table.concat(out)
end

local function sameInstance(a, b)
    if compareInstances then
        local ok, result = pcall(compareInstances, a, b)
        if ok then
            return result
        end
    end

    return a == b
end

local function instanceSegment(name)
    return ":FindFirstChild(" .. quoteString(name) .. ")"
end

local function getUnparentedInstancePath(instance)
    local className = quoteString(instance.ClassName)
    local name = quoteString(instance.Name)
    local debugId
    local debugIdOk, capturedDebugId = pcall(instance.GetDebugId, instance)
    if debugIdOk and type(capturedDebugId) == "string" then
        debugId = quoteString(capturedDebugId)
    end

    local lines = {
        "(function()",
        "    local getCandidates = getnilinstances or get_nil_instances or getinstances or get_instances",
        '    assert(type(getCandidates) == "function", "The executor cannot resolve unparented instances")',
        "    local match",
        "    for _, candidate in pairs(getCandidates()) do",
        "        if candidate.Parent == nil",
        "            and candidate.ClassName == " .. className,
        "            and candidate.Name == " .. name,
    }

    if debugId then
        table.insert(lines, "        then")
        table.insert(lines, "            local ok, id = pcall(candidate.GetDebugId, candidate)")
        table.insert(lines, "            if ok and id == " .. debugId .. " then")
        table.insert(lines, "                return candidate")
        table.insert(lines, "            end")
    else
        table.insert(lines, "        then")
        table.insert(
            lines,
            '            assert(match == nil, "More than one matching unparented instance exists")'
        )
        table.insert(lines, "            match = candidate")
    end

    table.insert(lines, "        end")
    table.insert(lines, "    end")
    if debugId then
        table.insert(lines, '    error("The captured unparented instance is no longer available")')
    else
        table.insert(
            lines,
            '    return assert(match, "The captured unparented instance is no longer available")'
        )
    end
    table.insert(lines, "end)()")

    return table.concat(lines, "\n")
end

local function getInstancePath(instance, seen)
    if instance == game then
        return "game"
    elseif instance == workspace then
        return "workspace"
    elseif instance == client then
        return 'game:GetService("Players").LocalPlayer'
    end

    seen = seen or {}
    if seen[instance] then
        return "nil"
    end
    seen[instance] = true

    local ok, service = pcall(game.GetService, game, instance.ClassName)
    if ok and sameInstance(service, instance) then
        return "game:GetService(" .. quoteString(instance.ClassName) .. ")"
    end

    local parent = instance.Parent
    if not parent then
        return getUnparentedInstancePath(instance)
    end

    local parentPath = getInstancePath(parent, seen)
    if parentPath == "nil" then
        return "nil"
    end

    return parentPath .. instanceSegment(instance.Name)
end

local serializeValue

local reservedIdentifiers = {
    ["and"] = true,
    ["break"] = true,
    ["continue"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true,
}

local keyTypeRanks = {
    number = 1,
    string = 2,
    boolean = 3,
    EnumItem = 4,
    Instance = 5,
}

local function isIdentifier(value)
    return type(value) == "string" and value:match("^[%a_][%w_]*$") ~= nil and not reservedIdentifiers[value]
end

local function newState(options)
    options = options or {}
    local config = oh and oh.Config or {}

    return {
        active = {},
        maxDepth = options.maxDepth or config.MaxSerializedDepth or 7,
        maxEntries = options.maxEntries or config.MaxSerializedEntries or 150,
        maxString = options.maxString or config.MaxSerializedString or 16384,
    }
end

local function serializeTable(value, state, depth)
    if state.active[value] or depth >= state.maxDepth then
        return "nil", false
    end

    state.active[value] = true
    local entries = {}
    local count = 0
    local indent = string.rep("    ", depth + 1)
    local sequenceLength = 0
    local omitted = false

    while sequenceLength < state.maxEntries and rawget(value, sequenceLength + 1) ~= nil do
        sequenceLength = sequenceLength + 1
        count = count + 1
        local valueText = serializeValue(rawget(value, sequenceLength), state, depth + 1)
        table.insert(entries, indent .. valueText .. ",")
    end

    if count >= state.maxEntries and rawget(value, sequenceLength + 1) ~= nil then
        omitted = true
    end

    local keyedEntries = {}
    local remaining = math.max(0, state.maxEntries - count)
    local inspected = 0
    for key, item in pairs(value) do
        local isSequenceKey = type(key) == "number" and key >= 1 and key <= sequenceLength and key % 1 == 0
        if not isSequenceKey then
            inspected = inspected + 1
            if inspected > remaining then
                omitted = true
                break
            end

            local keyText, keySupported = serializeValue(key, state, depth + 1)
            if keySupported then
                table.insert(keyedEntries, {
                    key = key,
                    keyText = keyText,
                    rank = keyTypeRanks[typeof(key)] or 99,
                    sortText = type(key) == "string" and key or keyText,
                    valueText = serializeValue(item, state, depth + 1),
                })
            end
        end
    end

    table.sort(keyedEntries, function(left, right)
        if left.rank ~= right.rank then
            return left.rank < right.rank
        end
        return left.sortText < right.sortText
    end)

    for _, entry in ipairs(keyedEntries) do
        local keyPrefix
        if isIdentifier(entry.key) then
            keyPrefix = entry.key
        else
            keyPrefix = "[" .. entry.keyText .. "]"
        end
        table.insert(entries, indent .. keyPrefix .. " = " .. entry.valueText .. ",")
    end

    if omitted then
        table.insert(entries, indent .. "--[[ remaining entries omitted ]]")
    end

    state.active[value] = nil

    if #entries == 0 then
        return "{}", true
    end

    return "{\n" .. table.concat(entries, "\n") .. "\n" .. string.rep("    ", depth) .. "}", true
end

local function serializeSequence(value, state, depth)
    local values = {}
    for i, point in ipairs(value.Keypoints) do
        values[i] = point
    end

    return serializeTable(values, state, depth)
end

local function readProperty(value, property)
    local ok, result = pcall(function()
        return value[property]
    end)
    if ok then
        return result
    end

    return nil
end

local function serializeParams(value, typeName, properties, state, depth)
    local lines = {
        "(function()",
        "    local value = " .. typeName .. ".new()",
    }

    for _, property in ipairs(properties) do
        local item = readProperty(value, property)
        if item ~= nil then
            local text, supported = serializeValue(item, state, depth + 1)
            if supported then
                table.insert(lines, "    value." .. property .. " = " .. text)
            end
        end
    end

    table.insert(lines, "    return value")
    table.insert(lines, "end)()")
    return table.concat(lines, "\n"), true
end

serializeValue = function(value, state, depth)
    state = state or newState()
    depth = depth or 0

    local valueType = typeof(value)
    if valueType == "nil" then
        return "nil", true
    elseif valueType == "boolean" then
        return tostring(value), true
    elseif valueType == "number" then
        return numberToString(value), true
    elseif valueType == "string" then
        return quoteString(value, state.maxString), true
    elseif valueType == "table" then
        return serializeTable(value, state, depth)
    elseif valueType == "Instance" then
        return getInstancePath(value), true
    elseif valueType == "EnumItem" then
        return tostring(value), true
    elseif valueType == "buffer" then
        if buffer and buffer.tostring and buffer.fromstring then
            local ok, content = pcall(buffer.tostring, value)
            if ok then
                return "buffer.fromstring(" .. quoteString(content, state.maxString) .. ")", true
            end
        end
    elseif valueType == "Vector2" then
        return "Vector2.new(" .. numberToString(value.X) .. ", " .. numberToString(value.Y) .. ")", true
    elseif valueType == "Vector2int16" then
        return "Vector2int16.new(" .. tostring(value.X) .. ", " .. tostring(value.Y) .. ")", true
    elseif valueType == "Vector3" then
        return "Vector3.new("
            .. numberToString(value.X)
            .. ", "
            .. numberToString(value.Y)
            .. ", "
            .. numberToString(value.Z)
            .. ")",
            true
    elseif valueType == "Vector3int16" then
        return "Vector3int16.new(" .. tostring(value.X) .. ", " .. tostring(value.Y) .. ", " .. tostring(
            value.Z
        ) .. ")",
            true
    elseif valueType == "CFrame" then
        local components = { value:GetComponents() }
        for i = 1, #components do
            components[i] = numberToString(components[i])
        end
        return "CFrame.new(" .. table.concat(components, ", ") .. ")", true
    elseif valueType == "Color3" then
        return "Color3.new("
            .. numberToString(value.R)
            .. ", "
            .. numberToString(value.G)
            .. ", "
            .. numberToString(value.B)
            .. ")",
            true
    elseif valueType == "BrickColor" then
        return "BrickColor.new(" .. tostring(value.Number) .. ")", true
    elseif valueType == "UDim" then
        return "UDim.new(" .. numberToString(value.Scale) .. ", " .. tostring(value.Offset) .. ")", true
    elseif valueType == "UDim2" then
        return "UDim2.new("
            .. numberToString(value.X.Scale)
            .. ", "
            .. tostring(value.X.Offset)
            .. ", "
            .. numberToString(value.Y.Scale)
            .. ", "
            .. tostring(value.Y.Offset)
            .. ")",
            true
    elseif valueType == "Rect" then
        local minText = serializeValue(value.Min, state, depth + 1)
        local maxText = serializeValue(value.Max, state, depth + 1)
        return "Rect.new(" .. minText .. ", " .. maxText .. ")", true
    elseif valueType == "Ray" then
        local origin = serializeValue(value.Origin, state, depth + 1)
        local direction = serializeValue(value.Direction, state, depth + 1)
        return "Ray.new(" .. origin .. ", " .. direction .. ")", true
    elseif valueType == "Region3" then
        local half = value.Size / 2
        local minText = serializeValue(value.CFrame.Position - half, state, depth + 1)
        local maxText = serializeValue(value.CFrame.Position + half, state, depth + 1)
        return "Region3.new(" .. minText .. ", " .. maxText .. ")", true
    elseif valueType == "NumberRange" then
        return "NumberRange.new(" .. numberToString(value.Min) .. ", " .. numberToString(value.Max) .. ")",
            true
    elseif valueType == "DateTime" then
        return "DateTime.fromUnixTimestampMillis(" .. tostring(value.UnixTimestampMillis) .. ")", true
    elseif valueType == "ColorSequenceKeypoint" then
        local color = serializeValue(value.Value, state, depth + 1)
        return "ColorSequenceKeypoint.new(" .. numberToString(value.Time) .. ", " .. color .. ")", true
    elseif valueType == "NumberSequenceKeypoint" then
        return "NumberSequenceKeypoint.new(" .. numberToString(value.Time) .. ", " .. numberToString(
            value.Value
        ) .. ", " .. numberToString(value.Envelope) .. ")",
            true
    elseif valueType == "ColorSequence" or valueType == "NumberSequence" then
        return valueType .. ".new(" .. serializeSequence(value, state, depth + 1) .. ")", true
    elseif valueType == "TweenInfo" then
        return "TweenInfo.new("
            .. numberToString(value.Time)
            .. ", "
            .. tostring(value.EasingStyle)
            .. ", "
            .. tostring(value.EasingDirection)
            .. ", "
            .. tostring(value.RepeatCount)
            .. ", "
            .. tostring(value.Reverses)
            .. ", "
            .. numberToString(value.DelayTime)
            .. ")",
            true
    elseif valueType == "PhysicalProperties" then
        return "PhysicalProperties.new(" .. numberToString(value.Density) .. ", " .. numberToString(
            value.Friction
        ) .. ", " .. numberToString(value.Elasticity) .. ", " .. numberToString(value.FrictionWeight) .. ", " .. numberToString(
            value.ElasticityWeight
        ) .. ")",
            true
    elseif valueType == "PathWaypoint" then
        local position = serializeValue(value.Position, state, depth + 1)
        return "PathWaypoint.new(" .. position .. ", " .. tostring(value.Action) .. ", " .. quoteString(
            value.Label
        ) .. ")",
            true
    elseif valueType == "RaycastParams" then
        return serializeParams(value, valueType, {
            "BruteForceAllSlow",
            "CollisionGroup",
            "FilterDescendantsInstances",
            "FilterType",
            "IgnoreWater",
            "RespectCanCollide",
        }, state, depth)
    elseif valueType == "OverlapParams" then
        return serializeParams(value, valueType, {
            "BruteForceAllSlow",
            "CollisionGroup",
            "FilterDescendantsInstances",
            "FilterType",
            "MaxParts",
            "RespectCanCollide",
        }, state, depth)
    elseif valueType == "Font" then
        return "Font.new(" .. quoteString(value.Family) .. ", " .. tostring(value.Weight) .. ", " .. tostring(
            value.Style
        ) .. ")",
            true
    elseif valueType == "Faces" then
        local faces = {}
        for _, name in ipairs({ "Top", "Bottom", "Left", "Right", "Back", "Front" }) do
            if value[name] then
                table.insert(faces, "Enum.NormalId." .. name)
            end
        end
        return "Faces.new(" .. table.concat(faces, ", ") .. ")", true
    elseif valueType == "Axes" then
        local axes = {}
        for _, name in ipairs({ "X", "Y", "Z" }) do
            if value[name] then
                table.insert(axes, "Enum.Axis." .. name)
            end
        end
        return "Axes.new(" .. table.concat(axes, ", ") .. ")", true
    elseif valueType == "Random" then
        return "Random.new()", true
    end

    return "nil", false
end

local function dataToString(value, options)
    return serializeValue(value, newState(options), 0)
end

local function tableToString(value, _root, _indents, options)
    return serializeValue(value, newState(options), 0)
end

local function serializeArgs(args, options)
    local state = newState(options)
    local out = {}
    local count = args.n or #args

    for i = 1, count do
        out[i] = serializeValue(args[i], state, 0)
    end

    return table.concat(out, ", ")
end

local function toUnicode(value)
    local codepoints = {}
    for _, point in utf8.codes(value) do
        table.insert(codepoints, tostring(point))
    end

    if #codepoints == 0 then
        return '""'
    end

    return "utf8.char(" .. table.concat(codepoints, ", ") .. ")"
end

local function toString(value)
    local valueType = typeof(value)
    if valueType == "function" and getInfo then
        local ok, info = pcall(getInfo, value)
        if ok and info then
            return (info.name and info.name ~= "" and info.name) or "Unnamed function"
        end
        return "Unnamed function"
    elseif valueType == "Instance" then
        return value.Name
    end

    local ok, result = pcall(tostring, value)
    return ok and result or valueType
end

local function compareTables(a, b)
    for key, value in pairs(a) do
        if b[key] ~= value then
            return false
        end
    end

    for key, value in pairs(b) do
        if a[key] ~= value then
            return false
        end
    end

    return true
end

local function userdataValue(value)
    return dataToString(value)
end

local function isUserdata(valueType)
    return serializableTypes[valueType] == true
end

methods.compareTables = compareTables
methods.dataToString = dataToString
methods.getInstancePath = getInstancePath
methods.isUserdata = isUserdata
methods.quoteString = quoteString
methods.serializeArgs = serializeArgs
methods.serializeValue = dataToString
methods.tableToString = tableToString
methods.toString = toString
methods.toUnicode = toUnicode
methods.userdataValue = userdataValue
return methods
