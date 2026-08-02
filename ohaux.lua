local aux = {}

local getGc = getgc or get_gc_objects
local getInfo = (debug and debug.getinfo) or getinfo
local getUpvalue = (debug and debug.getupvalue) or getupvalue or getupval
local getConstants = (debug and debug.getconstants) or getconstants or getconsts
local isXClosure = isexecutorclosure
    or checkclosure
    or isourclosure
    or is_synapse_function
    or issentinelclosure
    or is_protosmasher_closure
    or is_sirhurt_closure
    or istempleclosure
local isLClosure = islclosure
    or is_l_closure
    or (iscclosure and function(value)
        return not iscclosure(value)
    end)

assert(
    getGc and getInfo and getUpvalue and getConstants and isXClosure and isLClosure,
    "Your executor is not supported"
)

local placeholderUserdataConstant = (newproxy and newproxy(false)) or {}

local function matchConstants(closure, list)
    if not list then
        return true
    end

    local ok, constants = pcall(getConstants, closure)
    if not ok then
        return false
    end

    for index, value in pairs(list) do
        if constants[index] ~= value and value ~= placeholderUserdataConstant then
            return false
        end
    end

    return true
end

local function searchClosure(script, name, upvalueIndex, constants)
    for _, value in pairs(getGc()) do
        if type(value) == "function" and isLClosure(value) and not isXClosure(value) then
            local envOk, env = pcall(getfenv, value)
            local parentScript = envOk and type(env) == "table" and rawget(env, "script")
            local sourceMatches = script == parentScript
                or (script == nil and typeof(parentScript) == "Instance" and parentScript.Parent == nil)

            if sourceMatches and pcall(getUpvalue, value, upvalueIndex) then
                local infoOk, info = pcall(getInfo, value)
                local closureName = infoOk and info and info.name or ""
                local nameMatches = not name or name == "Unnamed function" or closureName == name

                if nameMatches and matchConstants(value, constants) then
                    return value
                end
            end
        end
    end

    return nil
end

aux.placeholderUserdataConstant = placeholderUserdataConstant
aux.searchClosure = searchClosure
return aux
