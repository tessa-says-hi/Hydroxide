local SyntaxHighlighter = {}

local colors = {
    builtin = "#4EC9B0",
    comment = "#6A9955",
    field = "#9CDCFE",
    functionName = "#DCDCAA",
    keyword = "#C586C0",
    number = "#B5CEA8",
    operator = "#D7BA7D",
    string = "#CE9178",
}

local keywords = {
    ["and"] = true,
    ["break"] = true,
    ["continue"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["export"] = true,
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
    ["type"] = true,
    ["until"] = true,
    ["while"] = true,
}

local builtins = {
    Axes = true,
    BrickColor = true,
    CFrame = true,
    Color3 = true,
    ColorSequence = true,
    DateTime = true,
    Enum = true,
    Faces = true,
    Instance = true,
    NumberRange = true,
    NumberSequence = true,
    OverlapParams = true,
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
    Vector3 = true,
    _G = true,
    assert = true,
    bit32 = true,
    buffer = true,
    collectgarbage = true,
    coroutine = true,
    debug = true,
    error = true,
    game = true,
    getfenv = true,
    getmetatable = true,
    ipairs = true,
    math = true,
    next = true,
    os = true,
    pairs = true,
    pcall = true,
    print = true,
    rawequal = true,
    rawget = true,
    rawlen = true,
    rawset = true,
    require = true,
    script = true,
    select = true,
    setfenv = true,
    setmetatable = true,
    shared = true,
    string = true,
    table = true,
    task = true,
    tonumber = true,
    tostring = true,
    type = true,
    typeof = true,
    unpack = true,
    utf8 = true,
    warn = true,
    workspace = true,
    xpcall = true,
}

local function escapeRichText(text)
    local escaped = tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    return escaped
end

local function colorize(text, color)
    return '<font color="' .. color .. '">' .. escapeRichText(text) .. "</font>"
end

local function isDigit(byte)
    return byte and byte >= 48 and byte <= 57
end

local function isHexDigit(byte)
    return isDigit(byte) or (byte and byte >= 65 and byte <= 70) or (byte and byte >= 97 and byte <= 102)
end

local function isIdentifierStart(byte)
    return byte == 95 or (byte and byte >= 65 and byte <= 90) or (byte and byte >= 97 and byte <= 122)
end

local function isIdentifierPart(byte)
    return isIdentifierStart(byte) or isDigit(byte)
end

local function longBracketEnd(source, index)
    if source:byte(index) ~= 91 then
        return nil
    end

    local cursor = index + 1
    while source:byte(cursor) == 61 do
        cursor += 1
    end
    if source:byte(cursor) ~= 91 then
        return nil
    end

    local closing = "]" .. string.rep("=", cursor - index - 1) .. "]"
    local _, closeEnd = source:find(closing, cursor + 1, true)
    return closeEnd or #source
end

local function quotedStringEnd(source, index, quote)
    local cursor = index + 1
    while cursor <= #source do
        local byte = source:byte(cursor)
        if byte == 92 then
            cursor += 2
        elseif byte == quote then
            return cursor
        else
            cursor += 1
        end
    end

    return #source
end

local function numberEnd(source, index)
    local cursor = index
    local first = source:byte(cursor)
    local second = source:byte(cursor + 1)

    if first == 48 and (second == 120 or second == 88) then
        cursor += 2
        while isHexDigit(source:byte(cursor)) or source:byte(cursor) == 95 do
            cursor += 1
        end
        return cursor - 1
    elseif first == 48 and (second == 98 or second == 66) then
        cursor += 2
        while source:byte(cursor) == 48 or source:byte(cursor) == 49 or source:byte(cursor) == 95 do
            cursor += 1
        end
        return cursor - 1
    end

    if first == 46 then
        cursor += 1
    end
    while isDigit(source:byte(cursor)) or source:byte(cursor) == 95 do
        cursor += 1
    end
    if source:byte(cursor) == 46 and source:byte(cursor + 1) ~= 46 then
        cursor += 1
        while isDigit(source:byte(cursor)) or source:byte(cursor) == 95 do
            cursor += 1
        end
    end
    if source:byte(cursor) == 101 or source:byte(cursor) == 69 then
        cursor += 1
        if source:byte(cursor) == 43 or source:byte(cursor) == 45 then
            cursor += 1
        end
        while isDigit(source:byte(cursor)) or source:byte(cursor) == 95 do
            cursor += 1
        end
    end

    return cursor - 1
end

local function previousNonSpaceByte(source, index)
    local cursor = index - 1
    while cursor > 0 do
        local byte = source:byte(cursor)
        if byte ~= 9 and byte ~= 10 and byte ~= 13 and byte ~= 32 then
            return byte
        end
        cursor -= 1
    end
    return nil
end

local function nextNonSpaceByte(source, index)
    local cursor = index
    while cursor <= #source do
        local byte = source:byte(cursor)
        if byte ~= 9 and byte ~= 10 and byte ~= 13 and byte ~= 32 then
            return byte
        end
        cursor += 1
    end
    return nil
end

function SyntaxHighlighter.escape(text)
    return escapeRichText(text)
end

function SyntaxHighlighter.highlight(source)
    source = tostring(source or "")
    local output = {}
    local index = 1
    local length = #source

    while index <= length do
        local byte = source:byte(index)
        local nextByte = source:byte(index + 1)
        local tokenEnd
        local color

        if byte == 45 and nextByte == 45 then
            tokenEnd = longBracketEnd(source, index + 2)
            if not tokenEnd then
                local newline = source:find("\n", index + 2, true)
                tokenEnd = newline and newline - 1 or length
            end
            color = colors.comment
        elseif byte == 34 or byte == 39 or byte == 96 then
            tokenEnd = quotedStringEnd(source, index, byte)
            color = colors.string
        elseif byte == 91 then
            tokenEnd = longBracketEnd(source, index)
            color = tokenEnd and colors.string or nil
        elseif isDigit(byte) or (byte == 46 and isDigit(nextByte)) then
            tokenEnd = numberEnd(source, index)
            color = colors.number
        elseif isIdentifierStart(byte) then
            tokenEnd = index + 1
            while isIdentifierPart(source:byte(tokenEnd)) do
                tokenEnd += 1
            end
            tokenEnd -= 1

            local identifier = source:sub(index, tokenEnd)
            if keywords[identifier] then
                color = colors.keyword
            elseif builtins[identifier] then
                color = colors.builtin
            elseif nextNonSpaceByte(source, tokenEnd + 1) == 40 then
                color = colors.functionName
            else
                local previous = previousNonSpaceByte(source, index)
                if previous == 46 or previous == 58 then
                    color = colors.field
                end
            end
        elseif source:sub(index, index):find("[+%-%*/%%%^#=~<>;:,.{}%[%]()]") then
            tokenEnd = index
            color = colors.operator
        end

        if tokenEnd then
            local token = source:sub(index, tokenEnd)
            table.insert(output, color and colorize(token, color) or escapeRichText(token))
            index = tokenEnd + 1
        else
            local plainStart = index
            repeat
                index += 1
                byte = source:byte(index)
                nextByte = source:byte(index + 1)
            until index > length
                or (byte == 45 and nextByte == 45)
                or byte == 34
                or byte == 39
                or byte == 96
                or byte == 91
                or isDigit(byte)
                or (byte == 46 and isDigit(nextByte))
                or isIdentifierStart(byte)
                or source:sub(index, index):find("[+%-%*/%%%^#=~<>;:,.{}%[%]()]")
            table.insert(output, escapeRichText(source:sub(plainStart, index - 1)))
        end
    end

    return table.concat(output)
end

function SyntaxHighlighter.highlightFunctionInfo(information)
    information = tostring(information or "")
    local output = {}
    local index = 1

    while index <= #information do
        local newline = information:find("\n", index, true)
        local lineEnd = newline and newline - 1 or #information
        local line = information:sub(index, lineEnd)
        local colon = line:find(":", 1, true)

        if colon then
            table.insert(output, colorize(line:sub(1, colon), colors.field))
            table.insert(output, SyntaxHighlighter.highlight(line:sub(colon + 1)))
        else
            table.insert(output, SyntaxHighlighter.highlight(line))
        end

        if newline then
            table.insert(output, "\n")
            index = newline + 1
        else
            break
        end
    end

    return table.concat(output)
end

return SyntaxHighlighter
