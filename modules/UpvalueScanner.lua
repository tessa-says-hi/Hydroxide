local UpvalueScanner = {}
local Closure = import("objects/Closure")
local Upvalue = import("objects/Upvalue")

local requiredMethods = {
    getGc = true,
    getInfo = true,
    getUpvalue = true,
    getUpvalues = true,
    isXClosure = true,
    setUpvalue = true,
}

local function contains(value, query)
    return value:lower():find(query:lower(), 1, true) ~= nil
end

local function compareUpvalue(query, upvalue, ignoreNumber)
    local valueType = typeof(upvalue)
    if valueType == "string" then
        return upvalue == query or contains(upvalue, query)
    elseif valueType == "number" and not ignoreNumber then
        return tonumber(query) == upvalue or string.format("%.2f", upvalue) == query
    elseif valueType == "Instance" then
        return upvalue.Name == query or contains(upvalue.Name, query)
    elseif valueType == "function" then
        local ok, info = pcall(getInfo, upvalue)
        local name = ok and info and info.name or ""
        return name == query or contains(name, query)
    elseif valueType ~= "table" then
        return toString(upvalue) == query
    end

    return false
end

local function isScannableClosure(value)
    if type(value) ~= "function" then
        return false
    end

    local checked, executorClosure = pcall(isXClosure, value)
    return checked and not executorClosure
end

local function scan(query, deepSearch)
    query = tostring(query or "")
    local upvalues = {}
    local collected, objects = pcall(getGc)
    if not collected or type(objects) ~= "table" then
        return upvalues
    end

    for _, closure in pairs(objects) do
        if isScannableClosure(closure) and not upvalues[closure] then
            local ok, values = pcall(getUpvalues, closure)
            if ok then
                for index, value in pairs(values) do
                    local valueType = type(value)

                    if valueType ~= "table" and compareUpvalue(query, value) then
                        local storage = upvalues[closure]
                        if not storage then
                            storage = Closure.new(closure)
                            upvalues[closure] = storage
                        end
                        storage.Upvalues[index] = Upvalue.new(storage, index, value)
                    elseif deepSearch and valueType == "table" then
                        local storage
                        local tableUpvalue

                        for key, item in next, value do
                            if
                                key ~= value
                                and item ~= value
                                and (compareUpvalue(query, key, true) or compareUpvalue(query, item))
                            then
                                storage = storage or upvalues[closure] or Closure.new(closure)
                                upvalues[closure] = storage

                                if not tableUpvalue then
                                    tableUpvalue = Upvalue.new(storage, index, value)
                                    tableUpvalue.Scanned = {}
                                    storage.Upvalues[index] = tableUpvalue
                                end

                                tableUpvalue.Scanned[key] = item
                            end
                        end
                    end
                end
            end
        end
    end

    return upvalues
end

UpvalueScanner.RequiredMethods = requiredMethods
UpvalueScanner.Scan = scan
return UpvalueScanner
