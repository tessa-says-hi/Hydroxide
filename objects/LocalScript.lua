local LocalScript = {}

function LocalScript.new(instance)
    local closure = assert(getScriptClosure(instance), "Could not read script closure")
    local localScript = {
        Instance = instance,
    }

    local envOk, env = pcall(getSenv, instance)
    local constantsOk, constants = pcall(getConstants, closure)
    local protosOk, protos = pcall(getProtos, closure)

    localScript.Environment = envOk and env or {}
    localScript.Constants = constantsOk and constants or {}
    localScript.Protos = protosOk and protos or {}
    return localScript
end

return LocalScript
