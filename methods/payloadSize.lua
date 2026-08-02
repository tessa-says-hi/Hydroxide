local PayloadSize = {}

local function primitiveSize(value, valueType)
    if valueType == "nil" then
        return 1
    elseif valueType == "boolean" then
        return 1
    elseif valueType == "number" then
        return 8
    elseif valueType == "string" then
        return #value
    elseif valueType == "function" or valueType == "thread" then
        return 32
    end

    return nil
end

local function estimateValue(value, seen, budget)
    local valueType = type(value)
    local primitive = primitiveSize(value, valueType)
    if primitive then
        return math.min(primitive, budget + 1)
    end

    local robloxType = typeof(value)
    if robloxType == "buffer" and buffer and buffer.len then
        local ok, length = pcall(buffer.len, value)
        if ok then
            return math.min(16 + length, budget + 1)
        end
    end

    if valueType ~= "table" then
        return math.min(64, budget + 1)
    elseif seen[value] then
        return 8
    end

    seen[value] = true
    local size = 40
    for key, child in next, value do
        if size > budget then
            break
        end

        size += 16
        size += estimateValue(key, seen, budget - size)
        if size > budget then
            break
        end
        size += estimateValue(child, seen, budget - size)
    end

    return math.min(size, budget + 1)
end

local function addValue(size, value, seen, budget)
    if size > budget then
        return size
    end

    return size + estimateValue(value, seen, budget - size)
end

function PayloadSize.EstimateCall(call, budget)
    local limit = math.max(0, budget or math.huge)
    local seen = {}
    local size = addValue(0, call.args, seen, limit)

    if call.returns ~= nil then
        size = addValue(size, call.returns, seen, limit)
    end
    if call.error ~= nil then
        size = addValue(size, call.error, seen, limit)
    end

    return math.min(size, limit + 1)
end

return PayloadSize
