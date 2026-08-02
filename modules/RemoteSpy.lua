local RemoteSpy = {}
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
local ownConnections = {}
local ownHooks = {}
local remoteDataEvent = Instance.new("BindableEvent")
local eventSet = false
local stopped = false
local nextCallId = 0

RemoteSpy.Available = false
RemoteSpy.Paused = false

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

local function trackHook(target, original)
    local record
    if oh and oh.TrackHook then
        record = oh.TrackHook(target, original)
    else
        record = {
            Active = true,
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

local function shouldStore(remote, args)
    return not RemoteSpy.Paused and not remote.Ignored and not remote:AreArgsIgnored(args)
end

local function storeCall(instance, remote, call)
    remote:IncrementCalls(call)
    emit(instance, call, "add")
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
    if stopped or not oh.Active or checkCaller() then
        return original(instance, ...)
    end

    if typeof(instance) ~= "Instance" then
        return original(instance, ...)
    end

    local ok, className = pcall(function()
        return instance.ClassName
    end)
    local spec = ok and specs[className]
    if not spec or not remotesViewing[className] or instance == remoteDataEvent then
        return original(instance, ...)
    end

    local args = pack(...)
    local remote = getRemote(instance)
    local blocked = remote.Blocked or remote:AreArgsBlocked(args)
    local direction = className:find("^Bindable") and "local" or "outgoing"
    local call = newCall(direction, spec.Method, args, safeCallingFunction(), safeCallingScript())
    call.blocked = blocked

    if blocked then
        call.success = false
        if shouldStore(remote, args) then
            storeCall(instance, remote, call)
        end
        return
    end

    local success, results = callOriginal(original, instance, args, call)
    if shouldStore(remote, args) then
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

local function captureIncomingEvent(instance, method, args)
    if stopped or RemoteSpy.Paused then
        return
    end

    local className = instance.ClassName
    if not remotesViewing[className] then
        return
    end

    local remote = getRemote(instance)
    if remote.Ignored or remote:AreArgsIgnored(args) then
        return
    end

    local call = newCall("incoming", method, args)
    call.success = true
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

    local connection = instance.OnClientEvent:Connect(function(...)
        captureIncomingEvent(instance, "OnClientEvent", pack(...))
    end)
    incomingConnections[instance] = connection
    trackConnection(connection)
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
        if stopped or checkCaller() or not remotesViewing.RemoteFunction then
            return original(...)
        end

        local args = pack(...)
        local remote = getRemote(instance)
        local blocked = remote.Blocked or remote:AreArgsBlocked(args)
        local call = newCall("incoming", "OnClientInvoke", args, original, scriptFromFunction(original))
        call.blocked = blocked

        if blocked then
            call.success = false
            if shouldStore(remote, args) then
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

        if shouldStore(remote, args) then
            storeCall(instance, remote, call)
        end

        if results[1] then
            return unpackValues(call.returns, 1, call.returns.n)
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

local function connectEvent(callback)
    local connection = remoteDataEvent.Event:Connect(callback)
    eventSet = true
    trackConnection(connection)
    return connection
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
            "timestamp = " .. tostring(call.timestamp),
        }

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

    for _, connection in ipairs(ownConnections) do
        pcall(connection.Disconnect, connection)
    end

    for i = #ownHooks, 1, -1 do
        local record = ownHooks[i]
        if oh and oh.RestoreHook then
            oh.RestoreHook(record)
        elseif record.Active then
            pcall(hookFunction, record.Target, record.Original)
            record.Active = false
        end
    end

    remoteDataEvent:Destroy()
    table.clear(ownConnections)
    table.clear(ownHooks)
    table.clear(incomingConnections)
    table.clear(callbackConnections)
    table.clear(callbackHooks)
    table.clear(currentRemotes)
    RemoteSpy.Available = false
end

RemoteSpy.ConnectEvent = connectEvent
RemoteSpy.CurrentRemotes = currentRemotes
RemoteSpy.RemotesViewing = remotesViewing
RemoteSpy.RequiredMethods = requiredMethods

if hasMethods(requiredMethods) then
    installMethodHooks()
    startIncomingCapture()
    if oh and oh.TrackCleanup then
        oh.TrackCleanup(RemoteSpy.Stop)
    end
else
    remoteDataEvent:Destroy()
end

return RemoteSpy
