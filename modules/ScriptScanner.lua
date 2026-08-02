local ScriptScanner = {}
local LocalScript = import("objects/LocalScript")

local requiredMethods = {
    getConstants = true,
    getProtos = true,
    getScriptClosure = true,
    getSenv = true,
}

local function addScript(results, instance, query)
    if
        typeof(instance) ~= "Instance"
        or not instance:IsA("LocalScript")
        or results[instance]
        or not instance.Name:lower():find(query, 1, true)
    then
        return
    end

    local ok, value = pcall(LocalScript.new, instance)
    if ok then
        results[instance] = value
    end
end

local function scan(query)
    query = tostring(query or ""):lower()
    local scripts = {}
    local enumerated = false
    local enumerators = {}

    if getScripts then
        table.insert(enumerators, getScripts)
    end
    if getRunningScripts then
        table.insert(enumerators, getRunningScripts)
    end

    for _, enumerate in ipairs(enumerators) do
        local ok, values = pcall(enumerate)
        if ok then
            enumerated = true
            for _, instance in pairs(values) do
                addScript(scripts, instance, query)
            end
        end
    end

    if not enumerated and getGc and isXClosure then
        for _, value in pairs(getGc()) do
            if type(value) == "function" and not isXClosure(value) then
                local ok, env = pcall(getfenv, value)
                if ok and type(env) == "table" then
                    addScript(scripts, rawget(env, "script"), query)
                end
            end
        end
    end

    return scripts
end

ScriptScanner.RequiredMethods = requiredMethods
ScriptScanner.Scan = scan
return ScriptScanner
