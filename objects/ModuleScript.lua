local ModuleScript = {}

function ModuleScript.new(instance)
    local closure = assert(getScriptClosure(instance), "Could not read module closure")
    local moduleScript = {
        Instance = instance,
    }

    local constantsOk, constants = pcall(getConstants, closure)
    local protosOk, protos = pcall(getProtos, closure)
    moduleScript.Constants = constantsOk and constants or {}
    moduleScript.Protos = protosOk and protos or {}
    return moduleScript
end

return ModuleScript
