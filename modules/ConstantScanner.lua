local ConstantScanner = {}
local Closure = import("objects/Closure")
local Constant = import("objects/Constant")

local requiredMethods = {
    ["getGc"] = true,
    ["getInfo"] = true,
    ["isLClosure"] = true,
    ["isXClosure"] = true,
    ["getConstant"] = true,
    ["setConstant"] = true,
    ["getConstants"] = true,
}

local function compareConstant(query, constant)
    local constantType = typeof(constant)

    local stringCheck = constantType == "string"
        and (query == constant or constant:lower():find(query:lower(), 1, true))
    local numberCheck = constantType == "number"
        and (tonumber(query) == constant or ("%.2f"):format(constant) == query)
    local userDataCheck = constantType ~= "table"
        and constantType ~= "function"
        and toString(constant) == query

    if constantType == "function" then
        local ok, info = pcall(getInfo, constant)
        local closureName = ok and info and info.name or ""
        return query == closureName or closureName:lower():find(query:lower(), 1, true)
    end

    return stringCheck or numberCheck or userDataCheck
end

local function isScannableClosure(value)
    if type(value) ~= "function" then
        return false
    end

    local executorChecked, executorClosure = pcall(isXClosure, value)
    local luauChecked, luauClosure = pcall(isLClosure, value)
    return executorChecked and not executorClosure and luauChecked and luauClosure
end

local function scan(query)
    local constants = {}
    query = tostring(query or "")
    local collected, objects = pcall(getGc)
    if not collected or type(objects) ~= "table" then
        return constants
    end

    for _i, closure in pairs(objects) do
        if isScannableClosure(closure) and not constants[closure] then
            local ok, values = pcall(getConstants, closure)
            for index, constant in pairs(ok and values or {}) do
                if compareConstant(query, constant) then
                    local storage = constants[closure]

                    if not storage then
                        local newClosure = Closure.new(closure)
                        newClosure.Constants[index] = Constant.new(newClosure, index, constant)
                        constants[closure] = newClosure
                    else
                        storage.Constants[index] = Constant.new(storage, index, constant)
                    end
                end
            end
        end
    end

    return constants
end

ConstantScanner.Scan = scan
ConstantScanner.RequiredMethods = requiredMethods
return ConstantScanner
