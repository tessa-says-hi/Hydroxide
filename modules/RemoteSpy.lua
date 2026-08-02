local RemoteSpy = {}
local ActorRemoteSpy = import("modules/ActorRemoteSpy")
local PayloadSize = import("methods/payloadSize")
local RemotePolicy = import("methods/remotePolicy")
local Remote = import("objects/Remote")
local pack = table.pack or function(...)
    return { n = select("#", ...), ... }
end
local unpackValues = table.unpack or unpack

local requiredMethods = {
    checkCaller = true,
    hookFunction = true,
}

local remotesViewing = {
    BindableEvent = false,
    BindableFunction = false,
    RemoteEvent = true,
    RemoteFunction = true,
    UnreliableRemoteEvent = true,
}

local currentRemotes = setmetatable({}, { __mode = "k" })
local incomingConnections = setmetatable({}, { __mode = "k" })
local callbackConnections = setmetatable({}, { __mode = "k" })
local callbackHooks = setmetatable({}, { __mode = "k" })
local disabledIncomingConnections = setmetatable({}, { __mode = "k" })
local internalReceiverFunctions = setmetatable({}, { __mode = "k" })
local namecallThreads = setmetatable({}, { __mode = "k" })
local ownConnections = {}
local ownHooks = {}
local remoteDataEvent = Instance.new("BindableEvent")
local eventSet = false
local incomingBlockMonitorRunning = false
local actorRuntime
local namecallHookInstalled = false
local stopped = false
local nextCallId = 0

RemoteSpy.Available = false
RemoteSpy.ActorCaptureAvailable = false
RemoteSpy.Paused = false

local function isExecutorCaller()
    local ok, result = pcall(checkCaller)
    return ok and result == true
end

local function trackConnection(connection)
    table.insert(ownConnections, connection)
    if oh and oh.TrackConnection then
        oh.TrackConnection(connection)
    end
    return connection
end

local function untrackConnection(connection)
    pcall(connection.Disconnect, connection)

    local index = table.find(ownConnections, connection)
    if index then
        table.remove(ownConnections, index)
    end

    if oh and oh.Events and oh.Events[connection] == connection then
        oh.Events[connection] = nil
    end
end

local function trackHook(target, original, method, object)
    local record
    if oh and oh.TrackHook then
        record = oh.TrackHook(target, original, method, object)
    else
        record = {
            Active = true,
            Kind = method and "metamethod" or "function",
            Method = method,
            Object = object,
            Original = original,
            Target = target,
        }
    end

    table.insert(ownHooks, record)
    return record
end

local function safeCallingScript()
    if not getCallingScript then
        return
    end

    local ok, result = pcall(getCallingScript)
    if ok and typeof(result) == "Instance" then
        return result
    end

    return nil
end

local function safeCallingFunction()
    if not getInfo then
        return
    end

    for level = 3, 8 do
        local ok, info = pcall(getInfo, level)
        if ok and info and type(info.func) == "function" then
            if not isXClosure then
                return info.func
            end

            local checked, executorClosure = pcall(isXClosure, info.func)
            if not checked or not executorClosure then
                return info.func
            end
        end
    end

    return nil
end

local function scriptFromFunction(func)
    if type(func) ~= "function" or not getfenv then
        return
    end

    local ok, env = pcall(getfenv, func)
    if ok and type(env) == "table" then
        local source = rawget(env, "script")
        if typeof(source) == "Instance" then
            return source
        end
    end

    return nil
end

local function isInternalReceiver(func)
    if type(func) ~= "function" then
        return false
    elseif internalReceiverFunctions[func] then
        return true
    elseif not getInfo then
        return false
    end

    local ok, info = pcall(getInfo, func)
    local source = ok and info and (info.source or info.short_src)
    return type(source) == "string" and source:find("modules/RemoteSpy.lua", 1, true) ~= nil
end

local function getIncomingReceivers(instance)
    local receivers = {}
    if typeof(instance) ~= "Instance" then
        return receivers, "Invalid remote instance."
    end

    local className = instance.ClassName
    if className == "RemoteEvent" or className == "UnreliableRemoteEvent" then
        if not getConnections then
            return receivers, "Your executor does not expose getconnections."
        end

        local ok, connections = pcall(getConnections, instance.OnClientEvent)
        if not ok or type(connections) ~= "table" then
            return receivers, "The receiver connections could not be inspected."
        end

        for _, connection in next, connections do
            local func
            pcall(function()
                func = connection.Function
            end)

            if not isInternalReceiver(func) then
                local enabled = true
                pcall(function()
                    enabled = connection.Enabled ~= false
                end)
                table.insert(receivers, {
                    Connection = connection,
                    Enabled = enabled,
                    Function = func,
                    Script = scriptFromFunction(func),
                })
            end
        end
    elseif className == "RemoteFunction" then
        local current = callbackHooks[instance]
        local callback = current and current.Record.Original

        if not callback and getCallbackValue then
            local ok, result = pcall(getCallbackValue, instance, "OnClientInvoke")
            if ok then
                callback = result
            end
        end

        if type(callback) ~= "function" then
            return receivers, "No client OnClientInvoke callback is available."
        end

        table.insert(receivers, {
            Enabled = true,
            Function = callback,
            Script = scriptFromFunction(callback),
        })
    else
        return receivers, "This remote does not receive server calls."
    end

    if #receivers == 0 then
        return receivers, "No client receiver callbacks were found."
    end

    return receivers
end

local function setConnectionEnabled(connection, enabled)
    local method
    local ok = pcall(function()
        method = enabled and connection.Enable or connection.Disable
    end)
    if not ok or type(method) ~= "function" then
        return false
    end

    return pcall(method, connection)
end

local function syncIncomingBlock(instance, enabled)
    local disabled = disabledIncomingConnections[instance]
    if not enabled then
        if not disabled then
            return true, 0
        end

        local restored = 0
        for connection in pairs(disabled) do
            if setConnectionEnabled(connection, true) then
                restored += 1
            end
        end
        disabledIncomingConnections[instance] = nil
        return true, restored
    end

    local receivers, reason = getIncomingReceivers(instance)
    if reason and #receivers == 0 then
        if reason == "No client receiver callbacks were found." then
            return true, 0
        end
        return false, reason
    end

    if not disabled then
        disabled = {}
        disabledIncomingConnections[instance] = disabled
    end

    local changed = 0
    for _, receiver in ipairs(receivers) do
        local connection = receiver.Connection
        if connection and receiver.Enabled and not disabled[connection] then
            if setConnectionEnabled(connection, false) then
                disabled[connection] = true
                changed += 1
            end
        end
    end

    return true, changed
end

local function restoreIncomingBlocks()
    for instance in pairs(disabledIncomingConnections) do
        syncIncomingBlock(instance, false)
    end
end

local function replayIncoming(instance, args)
    if type(args) ~= "table" then
        return false, "The retained arguments are unavailable."
    end

    local receivers, reason = getIncomingReceivers(instance)
    if #receivers == 0 then
        return false, reason
    end

    local count = args.n or #args
    if instance.ClassName == "RemoteFunction" then
        local ok, result = pcall(receivers[1].Function, unpackValues(args, 1, count))
        return ok, ok and 1 or tostring(result)
    end

    local fired = 0
    local lastError
    for _, receiver in ipairs(receivers) do
        if receiver.Enabled then
            local fire
            if receiver.Connection then
                pcall(function()
                    fire = receiver.Connection.Fire
                end)
            end

            if type(fire) == "function" then
                local ok, result = pcall(fire, receiver.Connection, unpackValues(args, 1, count))
                if ok then
                    fired += 1
                else
                    lastError = tostring(result)
                end
            elseif type(receiver.Function) == "function" then
                task.spawn(receiver.Function, unpackValues(args, 1, count))
                fired += 1
            end
        end
    end

    if fired == 0 then
        return false, lastError or "No enabled client receiver callbacks could be replayed."
    end

    return true, fired
end

local function getRemote(instance)
    local remote = currentRemotes[instance]
    if not remote then
        remote = Remote.new(instance)
        currentRemotes[instance] = remote
    end

    return remote
end

local function emit(instance, call, eventType)
    if eventSet and not stopped then
        task.defer(function()
            if not stopped and oh and oh.Active then
                remoteDataEvent:Fire(instance, call, eventType or "add")
            end
        end)
    end
end

local function newCall(direction, method, args, func, source)
    nextCallId = nextCallId + 1
    return {
        args = args,
        direction = direction,
        func = func,
        id = nextCallId,
        method = method,
        script = source,
        timestamp = DateTime.now().UnixTimestampMillis,
    }
end

local function shouldStore(remote, args, direction)
    return RemotePolicy.ShouldStore(
        RemoteSpy.Paused,
        remote:IsIgnored(direction),
        remote:AreArgsIgnored(args)
    )
end

local function getRetainedBytes()
    local bytes = 0
    for _, remote in pairs(currentRemotes) do
        bytes += remote.RetainedBytes
    end

    return bytes
end

local function getOldestRetainedCall()
    local oldestRemote
    local oldestCall
    for _, remote in pairs(currentRemotes) do
        local call = remote.Logs[1]
        if call and (not oldestCall or call.id < oldestCall.id) then
            oldestRemote = remote
            oldestCall = call
        end
    end

    return oldestRemote, oldestCall
end

local function storeCall(instance, remote, call)
    local byteBudget = oh.Config.MaxRemoteLogBytes or 8 * 1024 * 1024
    call.bytes = PayloadSize.EstimateCall(call, byteBudget)
    if call.bytes > byteBudget then
        call.payloadBytes = call.bytes
        call.payloadDropped = true
        call.args = { n = 0 }
        call.returns = nil
        call.error = nil
        call.bytes = 0
    end

    local evicted = remote:IncrementCalls(call)
    if evicted then
        emit(instance, { id = evicted.id }, "remove")
    end

    while getRetainedBytes() > byteBudget do
        local oldestRemote, oldestCall = getOldestRetainedCall()
        if not oldestCall then
            break
        end

        oldestRemote:DecrementCalls(oldestCall)
        emit(oldestRemote.Instance, { id = oldestCall.id }, "remove")
    end

    emit(instance, call, "add")
end

local function captureActorCall(instance, payload, actorId)
    if stopped or RemoteSpy.Paused or type(payload) ~= "table" then
        return
    end

    local className = instance.ClassName
    if not remotesViewing[className] then
        return
    end

    local direction = payload.Direction
    if direction ~= "incoming" and direction ~= "outgoing" and direction ~= "local" then
        return
    elseif payload.Executor and not oh.Config.CaptureExecutorCalls then
        return
    end

    local args = type(payload.Args) == "table" and payload.Args or { n = 0 }
    local remote = getRemote(instance)
    if not shouldStore(remote, args, direction) then
        return
    end

    local call = newCall(direction, tostring(payload.Method or "Unknown"), args)
    call.actor = actorId
    call.blocked = payload.Blocked == true
    call.blockMissed = remote:IsBlocked(direction) and not call.blocked
    call.conditionMatched = remote:AreArgsBlocked(args)
    call.duration = payload.Duration
    call.error = payload.Error
    call.executor = payload.Executor == true
    call.payloadDropped = payload.PayloadDropped == true
    call.returns = type(payload.Returns) == "table" and payload.Returns or nil
    call.success = payload.Success == true
    storeCall(instance, remote, call)
end

local function callOriginal(original, instance, args, call)
    local started = os.clock()
    local results = pack(pcall(original, instance, unpackValues(args, 1, args.n)))
    call.duration = os.clock() - started

    if results[1] then
        call.success = true
        call.returns = { n = results.n - 1 }
        for i = 2, results.n do
            call.returns[i - 1] = results[i]
        end
        return true, call.returns
    end

    call.success = false
    call.error = tostring(results[2])
    return false, results[2]
end

local function handleOutgoing(original, specs, instance, ...)
    local executorCall = isExecutorCaller()
    if not RemotePolicy.ShouldCapture(stopped, oh.Active, executorCall, oh.Config.CaptureExecutorCalls) then
        return original(instance, ...)
    end

    if typeof(instance) ~= "Instance" then
        return original(instance, ...)
    end

    local ok, className = pcall(function()
        return instance.ClassName
    end)
    local spec = ok and specs[className]
    if
        not spec
        or not remotesViewing[className]
        or instance == remoteDataEvent
        or (actorRuntime and actorRuntime:Owns(instance))
    then
        return original(instance, ...)
    end

    local args = pack(...)
    local remote = getRemote(instance)
    local direction = RemotePolicy.DirectionForClass(className)
    local blocked = remote:IsBlocked(direction) or remote:AreArgsBlocked(args)
    local call = newCall(direction, spec.Method, args, safeCallingFunction(), safeCallingScript())
    call.blocked = blocked
    call.executor = executorCall

    if blocked then
        call.success = false
        if shouldStore(remote, args, direction) then
            storeCall(instance, remote, call)
        end
        return
    end

    local success, results = callOriginal(original, instance, args, call)
    if shouldStore(remote, args, direction) then
        storeCall(instance, remote, call)
    end

    if success then
        return unpackValues(results, 1, results.n)
    end

    error(results, 0)
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

    group.Specs[className] = {
        Method = method,
    }
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

    local results = pack(pcall(handleOutgoing, original, specs, instance, ...))
    if thread then
        local depth = namecallThreads[thread] - 1
        namecallThreads[thread] = depth > 0 and depth or nil
    end

    if results[1] then
        return unpackValues(results, 2, results.n)
    end

    error(results[2], 0)
end

local function installMethodHooks()
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
            local thread = coroutine.running()
            if thread and namecallThreads[thread] then
                return original(instance, ...)
            end

            return handleOutgoing(original, currentGroup.Specs, instance, ...)
        end

        if not currentGroup.Yields and newCClosure then
            replacement = newCClosure(replacement)
        end

        local ok, result = pcall(hookFunction, currentGroup.Target, replacement)
        if ok and type(result) == "function" then
            original = result
            trackHook(currentGroup.Target, original)
            RemoteSpy.Available = true
        elseif oh and oh.Failures then
            oh.Failures["RemoteSpy." .. next(currentGroup.Specs)] = tostring(result)
        end
    end
end

local function installNamecallHook()
    if type(hookMetaMethod) ~= "function" or type(getNamecallMethod) ~= "function" then
        return
    end

    local original
    local replacement = function(instance, ...)
        local specs = namecallSpecs[getNamecallMethod()]
        if not specs then
            return original(instance, ...)
        end

        return runNamecall(original, specs, instance, ...)
    end

    local ok, result = pcall(hookMetaMethod, game, "__namecall", replacement)
    if ok and type(result) == "function" then
        original = result
        trackHook(nil, original, "__namecall", game)
        namecallHookInstalled = true
        RemoteSpy.Available = true
    elseif oh and oh.Failures then
        oh.Failures["RemoteSpy.__namecall"] = tostring(result)
    end
end

local function captureIncomingEvent(instance, method, args)
    if stopped or RemoteSpy.Paused then
        return
    end

    local className = instance.ClassName
    if not remotesViewing[className] then
        return
    end

    local remote = getRemote(instance)
    if remote:IsIgnored("incoming") or remote:AreArgsIgnored(args) then
        return
    end

    local call = newCall("incoming", method, args)
    call.blocked = remote:IsBlocked("incoming")
    call.conditionMatched = remote:AreArgsBlocked(args)
    call.executor = false
    call.success = not call.blocked
    storeCall(instance, remote, call)
end

local function trackIncomingEvent(instance)
    if incomingConnections[instance] then
        return
    end

    local className = instance.ClassName
    if className ~= "RemoteEvent" and className ~= "UnreliableRemoteEvent" then
        return
    end

    local receiver = function(...)
        captureIncomingEvent(instance, "OnClientEvent", pack(...))
    end
    internalReceiverFunctions[receiver] = true
    local connection = instance.OnClientEvent:Connect(receiver)
    incomingConnections[instance] = connection
    trackConnection(connection)

    local remote = currentRemotes[instance]
    if remote and remote:IsBlocked("incoming") then
        syncIncomingBlock(instance, true)
    end
end

local function restoreCallbackHook(instance)
    local current = callbackHooks[instance]
    if not current then
        return
    end

    if oh and oh.RestoreHook then
        oh.RestoreHook(current.Record)
    elseif current.Record.Active then
        pcall(hookFunction, current.Record.Target, current.Record.Original)
        current.Record.Active = false
    end

    callbackHooks[instance] = nil
end

local function trackIncomingFunction(instance)
    if instance.ClassName ~= "RemoteFunction" or not getCallbackValue then
        return
    end

    local ok, callback = pcall(getCallbackValue, instance, "OnClientInvoke")
    if not ok or type(callback) ~= "function" then
        restoreCallbackHook(instance)
        return
    end

    local current = callbackHooks[instance]
    if current and current.Callback == callback then
        return
    end

    restoreCallbackHook(instance)

    local original
    local replacement = function(...)
        if stopped or not remotesViewing.RemoteFunction then
            return original(...)
        end

        local args = pack(...)
        local remote = getRemote(instance)
        local blocked = remote:IsBlocked("incoming") or remote:AreArgsBlocked(args)
        local call = newCall("incoming", "OnClientInvoke", args, original, scriptFromFunction(original))
        call.blocked = blocked
        call.executor = false

        if blocked then
            call.success = false
            if shouldStore(remote, args, "incoming") then
                storeCall(instance, remote, call)
            end
            return
        end

        local started = os.clock()
        local results = pack(pcall(original, ...))
        call.duration = os.clock() - started

        if results[1] then
            call.success = true
            call.returns = { n = results.n - 1 }
            for i = 2, results.n do
                call.returns[i - 1] = results[i]
            end
        else
            call.success = false
            call.error = tostring(results[2])
        end

        local returnValues = call.returns
        if shouldStore(remote, args, "incoming") then
            storeCall(instance, remote, call)
        end

        if results[1] then
            return unpackValues(returnValues, 1, returnValues.n)
        end

        error(results[2], 0)
    end

    local hooked, result = pcall(hookFunction, callback, replacement)
    if hooked and type(result) == "function" then
        original = result
        callbackHooks[instance] = {
            Callback = callback,
            Record = trackHook(callback, original),
        }
    elseif oh and oh.Failures then
        oh.Failures["RemoteSpy.OnClientInvoke"] = tostring(result)
    end
end

local function trackRemote(instance)
    local className = instance.ClassName
    if className == "RemoteEvent" or className == "UnreliableRemoteEvent" then
        trackIncomingEvent(instance)
    elseif className == "RemoteFunction" then
        trackIncomingFunction(instance)

        if not callbackConnections[instance] then
            local ok, signal = pcall(instance.GetPropertyChangedSignal, instance, "OnClientInvoke")
            if ok then
                local connection = signal:Connect(function()
                    task.defer(trackIncomingFunction, instance)
                end)
                callbackConnections[instance] = connection
                trackConnection(connection)
            end
        end
    end
end

local function removeRemote(instance)
    syncIncomingBlock(instance, false)

    local incoming = incomingConnections[instance]
    if incoming then
        untrackConnection(incoming)
        incomingConnections[instance] = nil
    end

    local changed = callbackConnections[instance]
    if changed then
        untrackConnection(changed)
        callbackConnections[instance] = nil
    end

    restoreCallbackHook(instance)
end

local function isIncomingEvent(instance)
    local ok, className = pcall(function()
        return instance.ClassName
    end)
    return ok and (className == "RemoteEvent" or className == "UnreliableRemoteEvent")
end

local function startIncomingBlockMonitor()
    if incomingBlockMonitorRunning then
        return
    end

    incomingBlockMonitorRunning = true
    task.spawn(function()
        while not stopped and oh.Active do
            local hasBlockedRemote = false
            for instance, remote in pairs(currentRemotes) do
                if remote:IsBlocked("incoming") and isIncomingEvent(instance) then
                    hasBlockedRemote = true
                    syncIncomingBlock(instance, true)
                end
            end

            if not hasBlockedRemote then
                break
            end
            task.wait(0.25)
        end

        incomingBlockMonitorRunning = false
    end)
end

local function startIncomingCapture()
    if not oh.Config.CaptureIncoming then
        return
    end

    for _, instance in ipairs(game:GetDescendants()) do
        trackRemote(instance)
    end

    trackConnection(game.DescendantAdded:Connect(trackRemote))
    trackConnection(game.DescendantRemoving:Connect(removeRemote))
end

local function resolveRetainedCall(instance, call)
    if type(call) ~= "table" then
        return call
    end

    local remote = currentRemotes[instance]
    if not remote or table.find(remote.Logs, call) then
        return call
    end

    local callId = call.id
    if callId == nil then
        return call
    end

    for index = #remote.Logs, 1, -1 do
        local retained = remote.Logs[index]
        if retained.id == callId then
            return retained
        end
    end

    return call
end

local function connectEvent(callback)
    local connection = remoteDataEvent.Event:Connect(function(instance, call, eventType)
        callback(instance, resolveRetainedCall(instance, call), eventType)
    end)
    eventSet = true
    trackConnection(connection)
    return connection
end

local function resolveRemote(remoteOrInstance)
    if typeof(remoteOrInstance) == "Instance" then
        return getRemote(remoteOrInstance)
    elseif type(remoteOrInstance) == "table" and remoteOrInstance.Instance then
        return remoteOrInstance
    end

    return nil
end

local function syncActorState(remote, direction)
    if not actorRuntime or not actorRuntime.Active then
        return
    end

    if direction then
        actorRuntime:SetState(
            remote.Instance,
            direction,
            remote:IsBlocked(direction),
            remote:IsIgnored(direction)
        )
        return
    end

    for _, currentDirection in ipairs(Remote.Directions) do
        syncActorState(remote, currentDirection)
    end
end

function RemoteSpy.SetBlocked(remoteOrInstance, enabled, direction)
    local remote = resolveRemote(remoteOrInstance)
    if not remote then
        return false, false, "Invalid remote."
    end

    local state = remote:Block(enabled, direction)
    local synced = true
    local reason
    if direction == nil or direction == "incoming" then
        local instance = remote.Instance
        if isIncomingEvent(instance) then
            synced, reason = syncIncomingBlock(instance, remote:IsBlocked("incoming"))
            if remote:IsBlocked("incoming") then
                startIncomingBlockMonitor()
            end
        end
    end

    if not synced and oh and oh.Failures then
        oh.Failures["RemoteSpy.IncomingBlock"] = tostring(reason)
    end

    syncActorState(remote, direction)

    return state, synced, reason
end

function RemoteSpy.SetIgnored(remoteOrInstance, enabled, direction)
    local remote = resolveRemote(remoteOrInstance)
    if not remote then
        return false, "Invalid remote."
    end

    local state = remote:Ignore(enabled, direction)
    syncActorState(remote, direction)
    return state
end

function RemoteSpy.GetRetainedBytes()
    return getRetainedBytes()
end

function RemoteSpy.GetDiagnostics()
    local actorDiagnostics = actorRuntime and actorRuntime:GetDiagnostics()
        or {
            Active = false,
            Available = type(getActors) == "function" and type(runOnActor) == "function",
            ReadyActors = 0,
        }

    local activeHooks = 0
    for _, record in ipairs(ownHooks) do
        if record.Active then
            activeHooks += 1
        end
    end

    return {
        Active = not stopped and oh.Active,
        Actor = actorDiagnostics,
        CaptureActors = oh.Config.CaptureActors,
        CaptureExecutorCalls = oh.Config.CaptureExecutorCalls,
        CaptureIncoming = oh.Config.CaptureIncoming,
        Hooks = activeHooks,
        IncomingConnectionControl = type(getConnections) == "function",
        NamecallHook = namecallHookInstalled,
        RetainedBytes = getRetainedBytes(),
        RetainedByteLimit = oh.Config.MaxRemoteLogBytes,
    }
end

function RemoteSpy.SetPaused(enabled)
    if enabled == nil then
        RemoteSpy.Paused = not RemoteSpy.Paused
    else
        RemoteSpy.Paused = enabled == true
    end

    return RemoteSpy.Paused
end

function RemoteSpy.RefreshIncoming()
    for _, instance in ipairs(game:GetDescendants()) do
        trackRemote(instance)
    end
end

function RemoteSpy.Export(remote)
    local path = getInstancePath(remote.Instance)
    local lines = {
        "-- Hydroxide RemoteSpy export",
        "return {",
        "    remote = " .. path .. ",",
        "    calls = {",
    }

    for _, call in ipairs(remote.Logs) do
        local fields = {
            "id = " .. tostring(call.id),
            "direction = " .. dataToString(call.direction),
            "method = " .. dataToString(call.method),
            "args = table.pack(" .. serializeArgs(call.args) .. ")",
            "success = " .. tostring(call.success == true),
            "blocked = " .. tostring(call.blocked == true),
            "executor = " .. tostring(call.executor == true),
            "bytes = " .. tostring(call.bytes or 0),
            "timestamp = " .. tostring(call.timestamp),
        }

        if call.actor then
            table.insert(fields, "actor = " .. tostring(call.actor))
        end

        if call.returns then
            table.insert(fields, "returns = table.pack(" .. serializeArgs(call.returns) .. ")")
        end
        if call.error then
            table.insert(fields, "error = " .. dataToString(call.error))
        end
        if call.duration then
            table.insert(fields, "duration = " .. string.format("%.9f", call.duration))
        end
        if call.script then
            table.insert(fields, "script = " .. getInstancePath(call.script))
        end
        if call.payloadDropped then
            table.insert(fields, "payloadDropped = true")
            table.insert(fields, "payloadBytes = " .. tostring(call.payloadBytes or 0))
        end

        table.insert(lines, "        { " .. table.concat(fields, ", ") .. " },")
    end

    table.insert(lines, "    },")
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

function RemoteSpy.Stop()
    if stopped then
        return
    end

    stopped = true
    RemoteSpy.Paused = true
    if actorRuntime then
        actorRuntime:Stop()
    end
    restoreIncomingBlocks()

    for _, connection in ipairs(ownConnections) do
        pcall(connection.Disconnect, connection)
    end

    for i = #ownHooks, 1, -1 do
        local record = ownHooks[i]
        if oh and oh.RestoreHook then
            oh.RestoreHook(record)
        elseif record.Active then
            if record.Kind == "metamethod" and hookMetaMethod then
                pcall(hookMetaMethod, record.Object, record.Method, record.Original)
            else
                pcall(hookFunction, record.Target, record.Original)
            end
            record.Active = false
        end
    end

    namecallHookInstalled = false
    remoteDataEvent:Destroy()
    table.clear(ownConnections)
    table.clear(ownHooks)
    table.clear(incomingConnections)
    table.clear(callbackConnections)
    table.clear(callbackHooks)
    table.clear(disabledIncomingConnections)
    table.clear(internalReceiverFunctions)
    table.clear(namecallThreads)
    table.clear(currentRemotes)
    RemoteSpy.Available = false
end

RemoteSpy.ConnectEvent = connectEvent
RemoteSpy.CurrentRemotes = currentRemotes
RemoteSpy.GetIncomingReceivers = getIncomingReceivers
RemoteSpy.RemotesViewing = remotesViewing
RemoteSpy.ReplayIncoming = replayIncoming
RemoteSpy.RequiredMethods = requiredMethods

if hasMethods(requiredMethods) then
    installMethodHooks()
    installNamecallHook()
    startIncomingCapture()
    actorRuntime = ActorRemoteSpy.Start(captureActorCall, function()
        task.defer(function()
            for _, remote in pairs(currentRemotes) do
                syncActorState(remote)
            end
        end)
    end)
    RemoteSpy.ActorCaptureAvailable = actorRuntime.Available
    oh.RemoteSpy = RemoteSpy
    oh.RemoteSpyDiagnostics = RemoteSpy.GetDiagnostics
    if oh and oh.TrackCleanup then
        oh.TrackCleanup(RemoteSpy.Stop)
    end
else
    remoteDataEvent:Destroy()
end

return RemoteSpy
