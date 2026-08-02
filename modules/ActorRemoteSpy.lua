local ActorRemoteSpy = {}

local actorSource = [==[
local actorId = __ACTOR_ID__
local bridgeName = __BRIDGE_NAME__
local captureExecutorCalls = __CAPTURE_EXECUTOR_CALLS__
local bridge = game:GetService("CoreGui"):FindFirstChild(bridgeName, true)
if not bridge then
    return
end

local dataEvent = bridge:FindFirstChild("Data")
local controlEvent = bridge:FindFirstChild("Control")
if not dataEvent or not controlEvent then
    return
end

local environment = type(getgenv) == "function" and getgenv() or _G
local runtimeKey = "__HydroxideActorRemoteSpy_" .. bridgeName
local existing = rawget(environment, runtimeKey)
if existing and existing.Active then
    dataEvent:Fire(actorId, nil, { Kind = "ready", Reused = true })
    return
end

local pack = table.pack or function(...)
    return { n = select("#", ...), ... }
end
local unpackValues = table.unpack or unpack
local hookFunction = hookfunction or replaceclosure or detour_function
local getConnections = getconnections or get_signal_cons
local newCClosure = newcclosure
local checkCaller = checkcaller
local states = setmetatable({}, { __mode = "k" })
local disabledConnections = setmetatable({}, { __mode = "k" })
local hooks = {}
local runtime = {
    Active = true,
}
environment[runtimeKey] = runtime

local function isExecutorCaller()
    if type(checkCaller) ~= "function" then
        return false
    end

    local ok, result = pcall(checkCaller)
    return ok and result == true
end

local function getState(remote)
    local state = states[remote]
    if not state then
        state = {
            Blocked = {},
            Ignored = {},
        }
        states[remote] = state
    end
    return state
end

local function setConnectionEnabled(connection, enabled)
    local method
    local ok = pcall(function()
        method = enabled and connection.Enable or connection.Disable
    end)
    return ok and type(method) == "function" and pcall(method, connection)
end

local function isHydroxideReceiver(func)
    if type(func) ~= "function" or not debug or not debug.getinfo then
        return false
    end

    local ok, info = pcall(debug.getinfo, func)
    local source = ok and info and (info.source or info.short_src)
    return type(source) == "string" and source:find("modules/RemoteSpy.lua", 1, true) ~= nil
end

local function syncIncomingBlock(remote, enabled)
    local disabled = disabledConnections[remote]
    if not enabled then
        if disabled then
            for connection in pairs(disabled) do
                setConnectionEnabled(connection, true)
            end
        end
        disabledConnections[remote] = nil
        return
    elseif type(getConnections) ~= "function" then
        return
    end

    local ok, connections = pcall(getConnections, remote.OnClientEvent)
    if not ok or type(connections) ~= "table" then
        return
    end

    if not disabled then
        disabled = {}
        disabledConnections[remote] = disabled
    end

    for _, connection in next, connections do
        local func
        local connectionEnabled = true
        pcall(function()
            func = connection.Function
            connectionEnabled = connection.Enabled ~= false
        end)
        if connectionEnabled and not disabled[connection] and not isHydroxideReceiver(func) then
            if setConnectionEnabled(connection, false) then
                disabled[connection] = true
            end
        end
    end
end

local function emit(remote, payload)
    local ok = pcall(dataEvent.Fire, dataEvent, actorId, remote, payload)
    if ok then
        return
    end

    pcall(dataEvent.Fire, dataEvent, actorId, remote, {
        Blocked = payload.Blocked,
        Direction = payload.Direction,
        Executor = payload.Executor,
        Kind = "call",
        Method = payload.Method,
        PayloadDropped = true,
        Success = payload.Success,
    })
end

local function handleCall(original, specs, instance, ...)
    if not runtime.Active or typeof(instance) ~= "Instance" then
        return original(instance, ...)
    end

    local ok, className = pcall(function()
        return instance.ClassName
    end)
    local spec = ok and specs[className]
    if not spec or instance == dataEvent or instance == controlEvent then
        return original(instance, ...)
    end

    local executorCall = isExecutorCaller()
    if executorCall and not captureExecutorCalls then
        return original(instance, ...)
    end

    local direction = className:find("^Bindable") and "local" or "outgoing"
    local state = getState(instance)
    local args = pack(...)
    local blocked = state.Blocked[direction] == true
    if blocked then
        if not state.Ignored[direction] then
            emit(instance, {
                Args = args,
                Blocked = true,
                Direction = direction,
                Executor = executorCall,
                Kind = "call",
                Method = spec.Method,
                Success = false,
            })
        end
        return
    end

    local started = os.clock()
    local results = pack(pcall(original, instance, ...))
    local payload = {
        Args = args,
        Blocked = false,
        Direction = direction,
        Duration = os.clock() - started,
        Executor = executorCall,
        Kind = "call",
        Method = spec.Method,
        Success = results[1] == true,
    }

    if results[1] then
        payload.Returns = { n = results.n - 1 }
        for index = 2, results.n do
            payload.Returns[index - 1] = results[index]
        end
    else
        payload.Error = tostring(results[2])
    end

    if not state.Ignored[direction] then
        emit(instance, payload)
    end

    if results[1] then
        return unpackValues(payload.Returns, 1, payload.Returns.n)
    end
    error(results[2], 0)
end

local function addMethodSpec(groups, className, method, yields)
    local ok, probe = pcall(Instance.new, className)
    if not ok then
        return
    end

    local target = probe[method]
    probe:Destroy()
    if type(target) ~= "function" then
        return
    end

    local group = groups[target]
    if not group then
        group = {
            Specs = {},
            Target = target,
            Yields = false,
        }
        groups[target] = group
    end
    group.Specs[className] = { Method = method }
    group.Yields = group.Yields or yields
end

local function installHooks()
    if type(hookFunction) ~= "function" then
        return false
    end

    local groups = {}
    addMethodSpec(groups, "RemoteEvent", "FireServer", false)
    addMethodSpec(groups, "UnreliableRemoteEvent", "FireServer", false)
    addMethodSpec(groups, "RemoteFunction", "InvokeServer", true)
    addMethodSpec(groups, "BindableEvent", "Fire", false)
    addMethodSpec(groups, "BindableFunction", "Invoke", true)

    for _, group in pairs(groups) do
        local currentGroup = group
        local original
        local replacement = function(instance, ...)
            return handleCall(original, currentGroup.Specs, instance, ...)
        end
        if not currentGroup.Yields and type(newCClosure) == "function" then
            replacement = newCClosure(replacement)
        end

        local hooked, result = pcall(hookFunction, currentGroup.Target, replacement)
        if hooked and type(result) == "function" then
            original = result
            table.insert(hooks, {
                Original = original,
                Target = currentGroup.Target,
            })
        end
    end

    return #hooks > 0
end

local function restore()
    if not runtime.Active then
        return
    end

    runtime.Active = false
    for remote in pairs(disabledConnections) do
        syncIncomingBlock(remote, false)
    end
    for index = #hooks, 1, -1 do
        local hook = hooks[index]
        pcall(hookFunction, hook.Target, hook.Original)
    end
    environment[runtimeKey] = nil
end

local controlConnection
controlConnection = controlEvent.Event:Connect(function(operation, remote, direction, blocked, ignored)
    if operation == "stop" then
        restore()
        controlConnection:Disconnect()
        return
    elseif
        operation ~= "state"
        or typeof(remote) ~= "Instance"
        or (direction ~= "incoming" and direction ~= "outgoing" and direction ~= "local")
    then
        return
    end

    local state = getState(remote)
    state.Blocked[direction] = blocked == true
    state.Ignored[direction] = ignored == true
    if direction == "incoming" then
        local className = remote.ClassName
        if className == "RemoteEvent" or className == "UnreliableRemoteEvent" then
            syncIncomingBlock(remote, state.Blocked.incoming)
        end
    end
end)

local installed = installHooks()
dataEvent:Fire(actorId, nil, {
    GetConnections = type(getConnections) == "function",
    Hooked = installed,
    Kind = "ready",
})

task.spawn(function()
    while runtime.Active do
        for remote, state in pairs(states) do
            if state.Blocked.incoming then
                local ok, className = pcall(function()
                    return remote.ClassName
                end)
                if ok and (className == "RemoteEvent" or className == "UnreliableRemoteEvent") then
                    syncIncomingBlock(remote, true)
                end
            end
        end
        task.wait(0.25)
    end
end)
]==]

local function createSource(bridgeName, actorId, captureExecutorCalls)
    local source = actorSource
    source = source:gsub("__ACTOR_ID__", tostring(actorId))
    source = source:gsub("__BRIDGE_NAME__", function()
        return string.format("%q", bridgeName)
    end)
    source = source:gsub("__CAPTURE_EXECUTOR_CALLS__", tostring(captureExecutorCalls == true))
    return source
end

local function addFailure(runtime, reason)
    if #runtime.Failures < 20 then
        table.insert(runtime.Failures, tostring(reason))
    elseif #runtime.Failures == 20 then
        table.insert(runtime.Failures, "Additional Actor failures omitted.")
    end
end

function ActorRemoteSpy.Start(onCall, onReady)
    local runtime = {
        Active = false,
        Attempts = 0,
        Available = type(getActors) == "function" and type(runOnActor) == "function",
        Failures = {},
        ReadyActors = 0,
    }

    function runtime:GetDiagnostics()
        return {
            Active = self.Active,
            Attempts = self.Attempts,
            Available = self.Available,
            Failures = table.clone(self.Failures),
            ReadyActors = self.ReadyActors,
        }
    end

    function runtime:Owns(instance)
        if self.Bridge == nil then
            return false
        elseif instance == self.Bridge then
            return true
        end

        local ok, parent = pcall(function()
            return instance.Parent
        end)
        return ok and parent == self.Bridge
    end

    function runtime:SetState(instance, direction, blocked, ignored)
        if self.Active and self.Control then
            pcall(self.Control.Fire, self.Control, "state", instance, direction, blocked, ignored)
        end
    end

    function runtime:Stop()
        if not self.Active then
            return
        end

        self.Active = false
        pcall(self.Control.Fire, self.Control, "stop")
        if self.Connection then
            self.Connection:Disconnect()
        end
        if self.Bridge then
            local oldBridge = self.Bridge
            task.defer(function()
                oldBridge:Destroy()
            end)
        end
    end

    if not oh.Config.CaptureActors or not runtime.Available then
        return runtime
    end

    local HttpService = game:GetService("HttpService")
    local bridge = Instance.new("Folder")
    bridge.Name = "HydroxideActorBridge_" .. HttpService:GenerateGUID(false):gsub("-", "")

    local dataEvent = Instance.new("BindableEvent")
    dataEvent.Name = "Data"
    dataEvent.Parent = bridge
    local controlEvent = Instance.new("BindableEvent")
    controlEvent.Name = "Control"
    controlEvent.Parent = bridge

    local parented, reason = pcall(function()
        bridge.Parent = game:GetService("CoreGui")
    end)
    if not parented then
        bridge:Destroy()
        addFailure(runtime, reason)
        return runtime
    end

    runtime.Active = true
    runtime.Bridge = bridge
    runtime.Control = controlEvent

    local ready = {}
    runtime.Connection = dataEvent.Event:Connect(function(actorId, instance, payload)
        if type(payload) ~= "table" then
            return
        elseif payload.Kind == "ready" then
            if not ready[actorId] then
                ready[actorId] = true
                runtime.ReadyActors += 1
            end
            if onReady and not payload.Reused then
                onReady(actorId, payload)
            end
        elseif payload.Kind == "call" and typeof(instance) == "Instance" then
            local captured, captureReason = pcall(onCall, instance, payload, actorId)
            if not captured then
                addFailure(runtime, captureReason)
            end
        end
    end)

    if oh and oh.TrackConnection then
        oh.TrackConnection(runtime.Connection)
    end

    local actors = setmetatable({}, { __mode = "k" })
    local nextActorId = 0
    local function scanActors()
        local ok, results = pcall(getActors)
        if not ok or type(results) ~= "table" then
            addFailure(runtime, results)
            return
        end

        for _, actor in next, results do
            local isActor = false
            if typeof(actor) == "Instance" then
                pcall(function()
                    isActor = actor:IsA("Actor")
                end)
            end

            if isActor then
                local record = actors[actor]
                if not record then
                    nextActorId += 1
                    record = {
                        Id = nextActorId,
                        LastAttempt = -math.huge,
                    }
                    actors[actor] = record
                end

                if os.clock() - record.LastAttempt >= 15 then
                    record.LastAttempt = os.clock()
                    runtime.Attempts += 1
                    local source = createSource(bridge.Name, record.Id, oh.Config.CaptureExecutorCalls)
                    local ran, runReason = pcall(runOnActor, actor, source)
                    if not ran then
                        local actorName = tostring(actor)
                        pcall(function()
                            actorName = actor:GetFullName()
                        end)
                        addFailure(runtime, actorName .. ": " .. tostring(runReason))
                    end
                end
            end
        end
    end

    task.spawn(function()
        while runtime.Active and oh.Active do
            scanActors()
            task.wait(1)
        end
    end)

    return runtime
end

return ActorRemoteSpy
