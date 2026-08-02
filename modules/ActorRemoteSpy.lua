local ActorRemoteSpy = {}

local actorSource = [==[
local actorId = __ACTOR_ID__
local bridgeName = __BRIDGE_NAME__
local channelId = __CHANNEL_ID__
local captureExecutorCalls = __CAPTURE_EXECUTOR_CALLS__
local useOth = __USE_OTH__
local dataEvent
local controlEvent

if channelId then
    local getChannel = get_comm_channel or getcommchannel
    if type(getChannel) ~= "function" then
        return
    end

    local received, channel = pcall(getChannel, channelId)
    if not received or typeof(channel) ~= "Instance" then
        return
    end
    dataEvent = channel
    controlEvent = channel
else
    local bridge = game:GetService("CoreGui"):FindFirstChild(bridgeName, true)
    if not bridge then
        return
    end
    dataEvent = bridge:FindFirstChild("Data")
    controlEvent = bridge:FindFirstChild("Control")
    if not dataEvent or not controlEvent then
        return
    end
end

local environment = type(getgenv) == "function" and getgenv() or _G
local runtimeKey = "__HydroxideActorRemoteSpy_" .. bridgeName
local existing = rawget(environment, runtimeKey)
if existing and existing.Active then
    local status = existing.Status or {}
    pcall(dataEvent.Fire, dataEvent, actorId, nil, {
        HookCount = status.HookCount or 0,
        Hooked = status.Hooked == true,
        Kind = "ready",
        MethodHooks = status.MethodHooks or 0,
        NamecallHook = status.NamecallHook == true,
        OthHooks = status.OthHooks or 0,
        Reused = true,
        Transport = channelId and "channel" or "instance",
    })
    return
end

local pack = table.pack or function(...)
    return { n = select("#", ...), ... }
end
local unpackValues = table.unpack or unpack
local hookFunction = hookfunction or replaceclosure or detour_function
local hookMetaMethod = hookmetamethod
local restoreFunction = restorefunction
local othLibrary = type(oth) == "table" and oth or nil
local getNamecallMethod = getnamecallmethod or get_namecall_method
local getConnections = getconnections or get_signal_cons
local newCClosure = newcclosure
local checkCaller = checkcaller
local states = setmetatable({}, { __mode = "k" })
local disabledConnections = setmetatable({}, { __mode = "k" })
local namecallThreads = setmetatable({}, { __mode = "k" })
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

local function getHookThread()
    if othLibrary and type(othLibrary.get_original_thread) == "function" then
        local ok, thread = pcall(othLibrary.get_original_thread)
        if ok and thread then
            return thread
        end
    end

    return coroutine.running()
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
                ArgCount = args.n,
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
        ArgCount = args.n,
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
        payload.ReturnCount = results.n - 1
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

local namecallSpecs = {
    Fire = {
        BindableEvent = { Method = "Fire" },
    },
    FireServer = {
        RemoteEvent = { Method = "FireServer" },
        UnreliableRemoteEvent = { Method = "FireServer" },
    },
    Invoke = {
        BindableFunction = { Method = "Invoke" },
    },
    InvokeServer = {
        RemoteFunction = { Method = "InvokeServer" },
    },
}

local function runNamecall(original, specs, instance, ...)
    local thread = coroutine.running()
    if thread then
        namecallThreads[thread] = (namecallThreads[thread] or 0) + 1
    end

    local results = pack(pcall(handleCall, original, specs, instance, ...))
    if thread then
        local depth = namecallThreads[thread] - 1
        namecallThreads[thread] = depth > 0 and depth or nil
    end

    if results[1] then
        return unpackValues(results, 2, results.n)
    end
    error(results[2], 0)
end

local function installNamecallHook()
    if type(hookMetaMethod) ~= "function" or type(getNamecallMethod) ~= "function" then
        return false
    end

    local original
    local replacement = function(instance, ...)
        local specs = namecallSpecs[getNamecallMethod()]
        if not specs then
            return original(instance, ...)
        end

        return runNamecall(original, specs, instance, ...)
    end
    local hooked, result = pcall(hookMetaMethod, game, "__namecall", replacement)
    if not hooked or type(result) ~= "function" then
        return false
    end

    original = result
    table.insert(hooks, {
        Kind = "metamethod",
        Method = "__namecall",
        Object = game,
        Original = original,
    })
    return true
end

local function installHooks()
    local methodHooks = 0
    local othHooks = 0
    local othHook = useOth
        and othLibrary
        and type(othLibrary.hook) == "function"
        and type(othLibrary.unhook) == "function"
        and othLibrary.hook
    if othHook or (not useOth and type(hookFunction) == "function") then
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
                local thread = getHookThread()
                if thread and namecallThreads[thread] then
                    return original(instance, ...)
                end

                return handleCall(original, currentGroup.Specs, instance, ...)
            end

            local hookKind = "function"
            local hooked
            local result
            if othHook then
                hookKind = "oth"
                hooked, result = pcall(othHook, currentGroup.Target, replacement)
            else
                if not currentGroup.Yields and type(newCClosure) == "function" then
                    replacement = newCClosure(replacement)
                end
                hooked, result = pcall(hookFunction, currentGroup.Target, replacement)
            end

            if hooked and type(result) == "function" then
                original = result
                methodHooks += 1
                if hookKind == "oth" then
                    othHooks += 1
                end
                table.insert(hooks, {
                    Kind = hookKind,
                    Original = original,
                    Target = currentGroup.Target,
                })
            end
        end
    end

    local namecallHook = installNamecallHook()
    return {
        HookCount = #hooks,
        Hooked = methodHooks > 0,
        MethodHooks = methodHooks,
        NamecallHook = namecallHook,
        OthHooks = othHooks,
    }
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
        if hook.Kind == "oth" then
            pcall(othLibrary.unhook, hook.Target)
        elseif hook.Kind == "metamethod" then
            pcall(hookMetaMethod, hook.Object, hook.Method, hook.Original)
        else
            local restored = pcall(hookFunction, hook.Target, hook.Original)
            if not restored and type(restoreFunction) == "function" then
                pcall(restoreFunction, hook.Target)
            end
        end
    end
    table.clear(namecallThreads)
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

local status = installHooks()
runtime.Status = status
local announced = pcall(dataEvent.Fire, dataEvent, actorId, nil, {
    GetConnections = type(getConnections) == "function",
    HookCount = status.HookCount,
    Hooked = status.Hooked,
    Kind = "ready",
    MethodHooks = status.MethodHooks,
    NamecallHook = status.NamecallHook,
    OthHooks = status.OthHooks,
    Transport = channelId and "channel" or "instance",
})

if not announced or not status.Hooked then
    restore()
    controlConnection:Disconnect()
    return
end

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

local function createSource(bridgeName, actorId, captureExecutorCalls, channelId, useOth)
    local source = actorSource
    source = source:gsub("__ACTOR_ID__", tostring(actorId))
    source = source:gsub("__BRIDGE_NAME__", function()
        return string.format("%q", bridgeName)
    end)
    source = source:gsub("__CHANNEL_ID__", channelId and tostring(channelId) or "nil")
    source = source:gsub("__CAPTURE_EXECUTOR_CALLS__", tostring(captureExecutorCalls == true))
    source = source:gsub("__USE_OTH__", tostring(useOth == true))
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
    local stateCaptureAvailable = type(getActorStates) == "function"
    local legacyCaptureAvailable = type(getActors) == "function" and type(runOnActor) == "function"
    local communicationChannelAvailable = type(createCommChannel) == "function"
        and type(getCommChannel) == "function"
    local othAvailable = type(oth) == "table"
        and type(oth.hook) == "function"
        and type(oth.unhook) == "function"
    local backend = stateCaptureAvailable and "states" or legacyCaptureAvailable and "actors" or "none"
    local transport = stateCaptureAvailable and communicationChannelAvailable and "channel" or "instance"
    local runtime = {
        Active = false,
        Attempts = 0,
        Available = backend ~= "none",
        Backend = backend,
        CommunicationChannelAvailable = communicationChannelAvailable,
        Failures = {},
        LegacyCaptureAvailable = legacyCaptureAvailable,
        MethodHookedTargets = 0,
        NamecallHookedTargets = 0,
        OthAvailable = othAvailable,
        OthHookedTargets = 0,
        ReadyActors = 0,
        ReadyStates = 0,
        ReadyTargets = 0,
        ReportedTargets = 0,
        StateCaptureAvailable = stateCaptureAvailable,
        Targets = 0,
        Transport = transport,
        UseOth = stateCaptureAvailable and othAvailable,
    }

    function runtime:GetDiagnostics()
        return {
            Active = self.Active,
            Attempts = self.Attempts,
            Available = self.Available,
            Backend = self.Backend,
            CommunicationChannelAvailable = self.CommunicationChannelAvailable,
            Failures = table.clone(self.Failures),
            LegacyCaptureAvailable = self.LegacyCaptureAvailable,
            MethodHookedTargets = self.MethodHookedTargets,
            NamecallHookedTargets = self.NamecallHookedTargets,
            OthAvailable = self.OthAvailable,
            OthHookedTargets = self.OthHookedTargets,
            ReadyActors = self.ReadyActors,
            ReadyStates = self.ReadyStates,
            ReadyTargets = self.ReadyTargets,
            ReportedTargets = self.ReportedTargets,
            StateCaptureAvailable = self.StateCaptureAvailable,
            StateEvent = self.StateConnection ~= nil,
            Targets = self.Targets,
            Transport = self.Transport,
        }
    end

    function runtime:Owns(instance)
        if instance == self.Control then
            return true
        elseif self.Bridge == nil then
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
        if self.StateConnection then
            pcall(function()
                self.StateConnection:Disconnect()
            end)
            self.StateConnection = nil
        end
        if self.Connection then
            self.Connection:Disconnect()
        end
        if self.Bridge then
            local oldBridge = self.Bridge
            task.defer(function()
                oldBridge:Destroy()
            end)
        elseif self.ChannelReceiver then
            local receiver = self.ChannelReceiver
            task.delay(1, function()
                pcall(receiver.Internal.Destroy, receiver.Internal)
            end)
        end
    end

    if not oh.Config.CaptureActors or not runtime.Available then
        return runtime
    end

    local bridgeName = "HydroxideActorBridge_"
        .. game:GetService("HttpService"):GenerateGUID(false):gsub("-", "")
    local dataSignal
    if runtime.Transport == "channel" then
        local created, channelId, receiver = pcall(createCommChannel)
        if not created or type(channelId) ~= "number" or type(receiver) ~= "table" then
            addFailure(runtime, channelId)
            return runtime
        end

        local inspected, event, internal = pcall(function()
            return receiver.Event, receiver.Internal
        end)
        if not inspected or typeof(internal) ~= "Instance" then
            addFailure(runtime, "Actor communication channel is invalid.")
            return runtime
        end

        runtime.ChannelId = channelId
        runtime.ChannelReceiver = receiver
        runtime.Control = internal
        dataSignal = event
    else
        local bridge = Instance.new("Folder")
        bridge.Name = bridgeName

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

        runtime.Bridge = bridge
        runtime.Control = controlEvent
        dataSignal = dataEvent.Event
    end

    runtime.Active = true
    runtime.BridgeName = bridgeName

    local records = {}
    local ready = {}
    runtime.Connection = dataSignal:Connect(function(captureId, instance, payload)
        if type(payload) ~= "table" then
            return
        elseif payload.Kind == "ready" then
            local hooked = payload.Hooked == true
            local previous = ready[captureId]
            local record = records[captureId]
            if record then
                record.Ready = hooked
                record.Status = payload
            end

            if previous == nil then
                runtime.ReportedTargets += 1
            end
            ready[captureId] = hooked

            if hooked and previous ~= true then
                runtime.ReadyTargets += 1
                runtime.ReadyActors = runtime.ReadyTargets
                if runtime.Backend == "states" then
                    runtime.ReadyStates += 1
                end
                if (tonumber(payload.MethodHooks) or 0) > 0 then
                    runtime.MethodHookedTargets += 1
                end
                if payload.NamecallHook == true then
                    runtime.NamecallHookedTargets += 1
                end
                if (tonumber(payload.OthHooks) or 0) > 0 then
                    runtime.OthHookedTargets += 1
                end
                if onReady then
                    onReady(captureId, payload)
                end
            elseif not hooked and previous == nil then
                addFailure(
                    runtime,
                    (record and record.Label or tostring(captureId)) .. ": no hooks installed"
                )
            end
        elseif payload.Kind == "call" and typeof(instance) == "Instance" then
            local captured, captureReason = pcall(onCall, instance, payload, captureId)
            if not captured then
                addFailure(runtime, captureReason)
            end
        end
    end)

    if oh and oh.TrackConnection then
        oh.TrackConnection(runtime.Connection)
    end

    local function attemptState(state)
        local stateId
        local inspected, inspectReason = pcall(function()
            stateId = state.Id
        end)
        if not inspected or type(stateId) ~= "number" then
            addFailure(runtime, "Lua state: " .. tostring(inspectReason or "missing numeric Id"))
            return
        end

        local record = records[stateId]
        if not record then
            record = {
                Id = stateId,
                Label = "Lua state " .. tostring(stateId),
                LastAttempt = -math.huge,
            }
            records[stateId] = record
            runtime.Targets += 1
        end
        record.Target = state

        if record.Ready or os.clock() - record.LastAttempt < 15 then
            return
        end

        local execute
        inspected, inspectReason = pcall(function()
            execute = state.Execute
        end)
        if not inspected or type(execute) ~= "function" then
            record.LastAttempt = os.clock()
            addFailure(runtime, record.Label .. ": Execute is unavailable")
            return
        end

        record.LastAttempt = os.clock()
        runtime.Attempts += 1
        local source = createSource(
            runtime.BridgeName,
            record.Id,
            oh.Config.CaptureExecutorCalls,
            runtime.ChannelId,
            runtime.UseOth
        )
        local ran, runReason = pcall(execute, state, source)
        if not ran then
            addFailure(runtime, record.Label .. ": " .. tostring(runReason))
        end
    end

    local function scanStates()
        local ok, results = pcall(getActorStates)
        if not ok or type(results) ~= "table" then
            addFailure(runtime, results)
            return
        end

        for _, state in next, results do
            attemptState(state)
        end
    end

    local function startStateCapture()
        if type(getLuaState) == "function" and actorStateCreated ~= nil then
            local connect
            local inspected = pcall(function()
                connect = actorStateCreated.Connect
            end)
            if inspected and type(connect) == "function" then
                local connected, connection = pcall(connect, actorStateCreated, function(actor)
                    if not runtime.Active then
                        return
                    end

                    local gotState, state = pcall(getLuaState, actor)
                    if gotState and state then
                        attemptState(state)
                    elseif not gotState then
                        addFailure(runtime, "New Lua state: " .. tostring(state))
                    end
                end)
                if connected and connection then
                    runtime.StateConnection = connection
                    if oh and oh.TrackConnection then
                        oh.TrackConnection(connection)
                    end
                else
                    addFailure(runtime, "Actor state event: " .. tostring(connection))
                end
            end
        end

        scanStates()
        task.spawn(function()
            while runtime.Active and oh.Active do
                task.wait(5)
                if runtime.Active and oh.Active then
                    scanStates()
                end
            end
        end)
    end

    local function startLegacyCapture()
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
                            Label = "Actor " .. tostring(actor),
                            LastAttempt = -math.huge,
                        }
                        actors[actor] = record
                        records[record.Id] = record
                        runtime.Targets += 1
                    end

                    if not record.Ready and os.clock() - record.LastAttempt >= 15 then
                        record.LastAttempt = os.clock()
                        runtime.Attempts += 1
                        local source = createSource(
                            runtime.BridgeName,
                            record.Id,
                            oh.Config.CaptureExecutorCalls,
                            runtime.ChannelId,
                            runtime.UseOth
                        )
                        local ran, runReason = pcall(runOnActor, actor, source)
                        if not ran then
                            local actorName = tostring(actor)
                            pcall(function()
                                actorName = actor:GetFullName()
                            end)
                            record.Label = "Actor " .. actorName
                            addFailure(runtime, actorName .. ": " .. tostring(runReason))
                        end
                    end
                end
            end
        end

        scanActors()
        task.spawn(function()
            while runtime.Active and oh.Active do
                task.wait(1)
                if runtime.Active and oh.Active then
                    scanActors()
                end
            end
        end)
    end

    if runtime.Backend == "states" then
        startStateCapture()
    else
        startLegacyCapture()
    end

    return runtime
end

return ActorRemoteSpy
