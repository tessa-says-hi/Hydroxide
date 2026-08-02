local ModuleScanner = {}
local ModuleScript = import("objects/ModuleScript")

local requiredMethods = {
    ["getProtos"] = true,
    ["getConstants"] = true,
    ["getScriptClosure"] = true,
    ["getLoadedModules"] = true,
}

local function scan(query)
    local modules = {}
    query = tostring(query or ""):lower()
    local loaded, values = pcall(getLoadedModules)
    if not loaded or type(values) ~= "table" then
        return modules
    end

    for _i, module in pairs(values) do
        if
            typeof(module) == "Instance"
            and module:IsA("ModuleScript")
            and module.Name:lower():find(query, 1, true)
        then
            local ok, value = pcall(ModuleScript.new, module)
            if ok then
                modules[module] = value
            end
        end
    end

    return modules
end

ModuleScanner.Scan = scan
ModuleScanner.RequiredMethods = requiredMethods
return ModuleScanner
