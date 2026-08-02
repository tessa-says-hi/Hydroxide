local environment = assert(getgenv, "<OH> ~ Your executor does not expose getgenv")()
local previous = rawget(environment, "oh")

if previous and type(previous.Exit) == "function" then
    pcall(previous.Exit)
end

local user = "tessa-says-hi"
local branch = "revision"
local repository = "https://github.com/" .. user .. "/Hydroxide"
local rawRepository = "https://raw.githubusercontent.com/" .. user .. "/Hydroxide/"
local importCache = {}
assert(loadstring, "<OH> ~ Your executor does not expose loadstring")
local pack = table.pack or function(...)
    return { n = select("#", ...), ... }
end
local unpackValues = table.unpack or unpack

local function first(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if value ~= nil then
            return value
        end
    end

    return nil
end

local globalMethods = {
    actorStateCreated = first(on_actor_state_created, onactorstatecreated),
    checkCaller = checkcaller,
    cloneRef = cloneref,
    compareInstances = compareinstances,
    decompileScript = first(decompile, decompile_script),
    getCallbackValue = getcallbackvalue,
    getActorStates = first(getactorstates, get_actor_states),
    getActors = first(getactors, get_actors, syn and syn.getactors),
    getCallingScript = first(getcallingscript, get_calling_script),
    getConnections = first(getconnections, get_signal_cons),
    getConstant = first(debug and debug.getconstant, getconstant, getconst),
    getConstants = first(debug and debug.getconstants, getconstants, getconsts),
    getContext = first(
        getthreadidentity,
        getidentity,
        getthreadcontext,
        get_thread_context,
        syn and syn.get_thread_identity
    ),
    getCustomAsset = first(getcustomasset, getsynasset),
    getGc = first(getgc, get_gc_objects),
    getGameState = first(getgamestate, get_game_state),
    getHui = first(gethui, get_hidden_gui),
    getInfo = first(debug and debug.getinfo, getinfo),
    getLoadedModules = first(getloadedmodules, get_loaded_modules),
    getLuaState = first(getluastate, get_lua_state),
    getMenv = first(getmenv, getsenv),
    getMetatable = first(getrawmetatable, debug and debug.getmetatable),
    getNamecallMethod = first(getnamecallmethod, get_namecall_method),
    getProto = first(debug and debug.getproto, getproto),
    getProtos = first(debug and debug.getprotos, getprotos),
    getRunningScripts = getrunningscripts,
    getScriptBytecode = first(getscriptbytecode, dumpstring),
    getScriptClosure = first(getscriptclosure, getscriptfunction, get_script_function),
    getScriptHash = getscripthash,
    getScripts = getscripts,
    getSenv = getsenv,
    getStack = first(debug and debug.getstack, getstack),
    getUpvalue = first(debug and debug.getupvalue, getupvalue, getupval),
    getUpvalues = first(debug and debug.getupvalues, getupvalues, getupvals),
    hookFunction = first(hookfunction, replaceclosure, detour_function),
    hookMetaMethod = hookmetamethod,
    identifyExecutor = identifyexecutor,
    isFile = isfile,
    isFolder = isfolder,
    isLClosure = first(islclosure, is_l_closure, iscclosure and function(closure)
        return not iscclosure(closure)
    end),
    isReadOnly = first(isreadonly, is_readonly),
    isXClosure = first(
        isexecutorclosure,
        checkclosure,
        isourclosure,
        is_synapse_function,
        issentinelclosure,
        is_protosmasher_closure,
        is_sirhurt_closure,
        iselectronfunction,
        istempleclosure
    ),
    makeFolder = makefolder,
    newCClosure = newcclosure,
    readFile = readfile,
    request = first(request, http and http.request, http_request, syn and syn.request),
    restoreFunction = restorefunction,
    runOnActor = first(run_on_actor, runonactor, syn and syn.run_on_actor),
    setClipboard = first(setclipboard, writeclipboard),
    setConstant = first(debug and debug.setconstant, setconstant, setconst),
    setContext = first(
        setthreadidentity,
        setidentity,
        setthreadcontext,
        set_thread_context,
        syn and syn.set_thread_identity
    ),
    setReadOnly = first(setreadonly, make_writeable and make_readonly and function(value, readonly)
        if readonly then
            make_readonly(value)
        else
            make_writeable(value)
        end
    end),
    setStack = first(debug and debug.setstack, setstack),
    setUpvalue = first(debug and debug.setupvalue, setupvalue, setupval),
    writeFile = writefile,
}

if PROTOSMASHER_LOADED and globalMethods.getConstants then
    globalMethods.getConstant = function(closure, index)
        return globalMethods.getConstants(closure)[index]
    end
end

local oldGetUpvalue = globalMethods.getUpvalue
if oldGetUpvalue then
    globalMethods.getUpvalue = function(closure, index)
        if type(closure) == "table" then
            return oldGetUpvalue(closure.Data, index)
        end

        return oldGetUpvalue(closure, index)
    end
end

local oldGetUpvalues = globalMethods.getUpvalues
if oldGetUpvalues then
    globalMethods.getUpvalues = function(closure)
        if type(closure) == "table" then
            return oldGetUpvalues(closure.Data)
        end

        return oldGetUpvalues(closure)
    end
end

local function useMethods(module)
    for name, method in pairs(module) do
        if method ~= nil then
            environment[name] = method
        end
    end
end

local function missingMethods(methods)
    local missing = {}

    for name in pairs(methods) do
        if type(environment[name]) ~= "function" then
            table.insert(missing, name)
        end
    end

    table.sort(missing)
    return missing
end

local function hasMethods(methods)
    return #missingMethods(methods) == 0
end

local executorName = "Unknown"
local executorVersion = ""
if globalMethods.identifyExecutor then
    local ok, name, version = pcall(globalMethods.identifyExecutor)
    if ok then
        executorName = tostring(name or executorName)
        executorVersion = tostring(version or "")
    end
end

local capabilities = {}
for name, method in pairs(globalMethods) do
    capabilities[name] = type(method) == "function" or name == "actorStateCreated"
end

local config = {
    CaptureActors = true,
    CaptureExecutorCalls = false,
    CaptureIncoming = true,
    MaxRemoteLogBytes = 8 * 1024 * 1024,
    MaxRemoteLogs = 500,
    MaxSerializedDepth = 7,
    MaxSerializedEntries = 150,
    MaxSerializedString = 16384,
}
local suppliedConfig = rawget(environment, "HydroxideConfig")
if type(suppliedConfig) == "table" then
    for name, value in pairs(suppliedConfig) do
        if type(value) == type(config[name]) and (type(value) ~= "number" or value > 0) then
            config[name] = value
        end
    end
end

local runtime = {
    Active = true,
    Cache = importCache,
    Capabilities = capabilities,
    Cleanup = {},
    Config = config,
    Constants = {
        Syntax = {
            ["function"] = Color3.fromRGB(225, 225, 225),
            ["nil"] = Color3.fromRGB(244, 135, 113),
            boolean = Color3.fromRGB(127, 200, 255),
            buffer = Color3.fromRGB(225, 150, 85),
            number = Color3.fromRGB(170, 225, 127),
            string = Color3.fromRGB(225, 150, 85),
            table = Color3.fromRGB(225, 225, 225),
            thread = Color3.fromRGB(225, 225, 225),
            userdata = Color3.fromRGB(225, 225, 225),
            vector = Color3.fromRGB(225, 225, 225),
            unnamed_function = Color3.fromRGB(175, 175, 175),
        },
        Types = {
            ["function"] = "rbxassetid://4666593447",
            ["nil"] = "rbxassetid://4800232219",
            boolean = "rbxassetid://4666593882",
            buffer = "rbxassetid://4666594723",
            integral = "rbxassetid://4666593882",
            number = "rbxassetid://4666593882",
            string = "rbxassetid://4666593882",
            table = "rbxassetid://4666594276",
            thread = "rbxassetid://4666593447",
            userdata = "rbxassetid://4666594723",
            vector = "rbxassetid://4666594723",
        },
    },
    Events = {},
    Executor = {
        Name = executorName,
        Version = executorVersion,
    },
    Failures = {},
    Hooks = {},
    Methods = globalMethods,
    Repository = repository,
}

function runtime.TrackConnection(connection, key)
    if key then
        runtime.Events[key] = connection
    else
        runtime.Events[connection] = connection
    end

    return connection
end

function runtime.TrackCleanup(callback)
    table.insert(runtime.Cleanup, callback)
    return callback
end

function runtime.TrackHook(target, original, method, object)
    local record = {
        Active = true,
        Kind = method and "metamethod" or "function",
        Method = method,
        Object = object,
        Original = original,
        Target = target,
    }

    table.insert(runtime.Hooks, record)
    return record
end

function runtime.RestoreHook(record)
    if not record or not record.Active then
        return true
    end

    local ok
    if record.Kind == "metamethod" and globalMethods.hookMetaMethod then
        ok = pcall(globalMethods.hookMetaMethod, record.Object, record.Method, record.Original)
    elseif globalMethods.hookFunction then
        ok = pcall(globalMethods.hookFunction, record.Target, record.Original)
    end

    if ok then
        record.Active = false
    end

    return ok == true
end

function runtime.Exit()
    if not runtime.Active then
        return
    end

    runtime.Active = false

    for i = #runtime.Cleanup, 1, -1 do
        pcall(runtime.Cleanup[i])
    end

    for _, connection in pairs(runtime.Events) do
        if connection then
            pcall(function()
                connection:Disconnect()
            end)
        end
    end

    for i = #runtime.Hooks, 1, -1 do
        runtime.RestoreHook(runtime.Hooks[i])
    end

    for asset, values in pairs(importCache) do
        if type(asset) == "string" and asset:find("^rbxassetid://") then
            for i = 1, values.n or #values do
                local value = values[i]
                if typeof(value) == "Instance" then
                    pcall(value.Destroy, value)
                end
            end
        end
    end

    table.clear(importCache)
    if rawget(environment, "oh") == runtime then
        environment.oh = nil
    end
end

environment.hasMethods = hasMethods
environment.missingMethods = missingMethods
environment.oh = runtime
useMethods(globalMethods)

local HttpService = game:GetService("HttpService")
local releaseVersion = branch
local sourceRef = branch
local versionKnown = false

local versionOk, versionInfo = pcall(function()
    local body = game:HttpGet("https://api.github.com/repos/" .. user .. "/Hydroxide/commits/" .. branch)
    return HttpService:JSONDecode(body)
end)

if versionOk and type(versionInfo) == "table" and type(versionInfo.sha) == "string" then
    releaseVersion = versionInfo.sha
    sourceRef = versionInfo.sha
    versionKnown = true
end

runtime.Version = releaseVersion

local canCache = type(globalMethods.readFile) == "function" and type(globalMethods.writeFile) == "function"
local nestedCache = canCache
    and type(globalMethods.isFolder) == "function"
    and type(globalMethods.makeFolder) == "function"
local cacheVersion = releaseVersion:gsub("[^%w._-]", "_")
local userCacheRoot = "hydroxide/user/" .. user
local cacheRoot = userCacheRoot .. "/" .. cacheVersion

if nestedCache then
    for _, path in ipairs({
        "hydroxide",
        "hydroxide/user",
        userCacheRoot,
        cacheRoot,
        cacheRoot .. "/methods",
        cacheRoot .. "/modules",
        cacheRoot .. "/objects",
        cacheRoot .. "/ui",
        cacheRoot .. "/ui/controls",
        cacheRoot .. "/ui/modules",
    }) do
        local checked, exists = pcall(globalMethods.isFolder, path)
        local created = exists or (checked and pcall(globalMethods.makeFolder, path))
        if not checked or not created then
            runtime.Failures[path] = "Could not create the source cache"
            nestedCache = false
            break
        end
    end
end

local function sourcePath(asset)
    if nestedCache then
        return cacheRoot .. "/" .. asset .. ".lua"
    end

    return "hydroxide-" .. user .. "-" .. cacheVersion .. "-" .. asset:gsub("/", "-") .. ".lua"
end

local function getCachedSource(path)
    if not canCache then
        return
    end

    if globalMethods.isFile then
        local ok, exists = pcall(globalMethods.isFile, path)
        if not ok or not exists then
            return
        end
    end

    local ok, content = pcall(globalMethods.readFile, path)
    if ok and type(content) == "string" and #content > 0 then
        return content
    end

    return nil
end

local function getWebSource(asset)
    local path = sourcePath(asset)
    local cached = getCachedSource(path)

    if cached and versionKnown then
        return cached
    end

    local ok, content = pcall(game.HttpGet, game, rawRepository .. sourceRef .. "/" .. asset .. ".lua")
    if not ok then
        if cached then
            runtime.Failures[asset] = tostring(content)
            return cached
        end

        error("<OH> ~ Failed to download " .. asset .. ": " .. tostring(content), 2)
    end

    if canCache then
        local wrote, reason = pcall(globalMethods.writeFile, path, content)
        if not wrote then
            runtime.Failures[path] = tostring(reason)
        end
    end

    return content
end

local function loadAsset(asset)
    local overrides = rawget(environment, "HydroxideAssets")
    local source = overrides and (overrides[asset] or overrides[asset:match("%d+")])

    if typeof(source) == "Instance" then
        return pack(source:Clone())
    elseif type(source) == "table" then
        local values = { n = source.n or #source }
        for i = 1, values.n do
            local value = source[i]
            values[i] = typeof(value) == "Instance" and value:Clone() or value
        end
        return values
    elseif type(source) == "string" then
        if not source:find("^rbxasset") and globalMethods.getCustomAsset then
            local ok, result = pcall(globalMethods.getCustomAsset, source)
            if ok then
                source = result
            else
                runtime.Failures[asset] = tostring(result)
            end
        end
    else
        source = asset
    end

    local ok, values = pcall(game.GetObjects, game, source)
    if not ok or not values[1] then
        error("<OH> ~ Failed to load UI asset " .. asset .. ": " .. tostring(values), 2)
    end

    return pack(values[1])
end

local function import(asset)
    local cached = importCache[asset]
    if cached then
        return unpackValues(cached, 1, cached.n or #cached)
    end

    local values
    if asset:find("^rbxassetid://") then
        values = loadAsset(asset)
    else
        local content = getWebSource(asset)
        local chunk, compileError = loadstring(content, "@" .. asset .. ".lua")
        if not chunk then
            error("<OH> ~ Failed to compile " .. asset .. ": " .. tostring(compileError), 2)
        end

        local results = pack(pcall(chunk))
        if not results[1] then
            error("<OH> ~ Failed to run " .. asset .. ": " .. tostring(results[2]), 2)
        end

        values = { n = results.n - 1 }
        for i = 2, results.n do
            values[i - 1] = results[i]
        end
    end

    importCache[asset] = values
    return unpackValues(values, 1, values.n or #values)
end

environment.import = import

useMethods(import("methods/serializer"))
useMethods(import("methods/environment"))
