local TextSelection = {}

function TextSelection.getCursor(text, cursor)
    text = tostring(text or "")
    if type(cursor) ~= "number" or cursor < 1 then
        return nil
    end

    cursor = math.min(cursor, #text + 1)
    local line = 0
    local lineStart = 1

    while true do
        local newline = text:find("\n", lineStart, true)
        local lineBoundary = newline or (#text + 1)
        if cursor <= lineBoundary then
            return {
                Line = line,
                Prefix = text:sub(lineStart, cursor - 1),
            }
        end

        line += 1
        lineStart = newline + 1
    end
end

function TextSelection.getRanges(text, anchor, cursor)
    text = tostring(text or "")
    if type(anchor) ~= "number" or type(cursor) ~= "number" or anchor < 1 or cursor < 1 then
        return {}
    end

    local selectionStart = math.clamp(math.min(anchor, cursor), 1, #text + 1)
    local selectionEnd = math.clamp(math.max(anchor, cursor) - 1, 0, #text)
    if selectionEnd < selectionStart then
        return {}
    end

    local ranges = {}
    local line = 0
    local lineStart = 1

    while true do
        if lineStart > selectionEnd then
            break
        end

        local newline = text:find("\n", lineStart, true)
        local lineEnd = newline and newline - 1 or #text
        local includesNewline = newline ~= nil and selectionStart <= newline and selectionEnd >= newline
        local rangeStart = math.max(selectionStart, lineStart)
        local rangeEnd = math.min(selectionEnd, lineEnd)

        if rangeStart <= rangeEnd or includesNewline then
            local textStart = math.min(rangeStart, lineEnd + 1)
            table.insert(ranges, {
                IncludesNewline = includesNewline,
                Line = line,
                Prefix = text:sub(lineStart, textStart - 1),
                Text = rangeEnd >= textStart and text:sub(textStart, rangeEnd) or "",
            })
        end

        if not newline then
            break
        end
        line += 1
        lineStart = newline + 1
    end

    return ranges
end

return TextSelection
