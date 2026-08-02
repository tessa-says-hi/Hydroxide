local environment = getgenv()
local report = {
    executor = "Unknown",
    tests = {},
}

if type(identifyexecutor) == "function" then
    local ok, name, version = pcall(identifyexecutor)
    if ok then
        report.executor = tostring(name) .. (version and (" " .. tostring(version)) or "")
    end
end

local checkCaller = checkcaller
local getConnections = getconnections or get_signal_cons
local getActors = getactors or get_actors or (syn and syn.getactors)
local hookFunction = hookfunction or replaceclosure or detour_function
local hookMetaMethod = hookmetamethod
local getNamecallMethod = getnamecallmethod or get_namecall_method
local runOnActor = run_on_actor or runonactor or (syn and syn.run_on_actor)
local callerChecked, callerResult = pcall(checkCaller)
report.tests.checkcaller = callerChecked and callerResult == true
report.tests.getactors = type(getActors) == "function"
report.tests.getnamecallmethod = type(getNamecallMethod) == "function"
report.tests.hookmetamethod = type(hookMetaMethod) == "function"
report.tests.run_on_actor = type(runOnActor) == "function"

local event = Instance.new("BindableEvent")
local cachedFire = event.Fire
local hookSeen = false
local hookCaller
local original
local replacement = function(instance, ...)
    if instance == event then
        hookSeen = true
        hookCaller = type(checkCaller) == "function" and checkCaller() or nil
    end
    return original(instance, ...)
end

local hooked, hookReason = pcall(function()
    original = hookFunction(cachedFire, newcclosure and newcclosure(replacement) or replacement)
end)
if hooked and type(original) == "function" then
    cachedFire(event, "cached")
    report.tests.cached_method_hook = hookSeen
    report.tests.hook_checkcaller = hookCaller == true
    report.tests.hook_restored = pcall(hookFunction, cachedFire, original)
else
    report.tests.cached_method_hook = false
    report.tests.hook_error = tostring(hookReason)
end

if type(hookMetaMethod) == "function" and type(getNamecallMethod) == "function" then
    local namecallSeen = false
    local originalNamecall
    local namecallHooked, namecallReason = pcall(function()
        originalNamecall = hookMetaMethod(game, "__namecall", function(instance, ...)
            if instance == event and getNamecallMethod() == "Fire" then
                namecallSeen = true
            end
            return originalNamecall(instance, ...)
        end)
    end)
    if namecallHooked and type(originalNamecall) == "function" then
        event:Fire("namecall")
        report.tests.namecall_hook = namecallSeen
        report.tests.namecall_hook_restored = pcall(hookMetaMethod, game, "__namecall", originalNamecall)
    else
        report.tests.namecall_hook = false
        report.tests.namecall_error = tostring(namecallReason)
    end
end

local deliveries = 0
local receiver = function()
    deliveries += 1
end
local connection = event.Event:Connect(receiver)
if type(getConnections) == "function" then
    local inspected, wrappers = pcall(getConnections, event.Event)
    local wrapper
    if inspected and type(wrappers) == "table" then
        for _, candidate in next, wrappers do
            local func
            pcall(function()
                func = candidate.Function
            end)
            if func == receiver then
                wrapper = candidate
                break
            end
        end
    end

    local disable
    local enable
    pcall(function()
        disable = wrapper and wrapper.Disable
        enable = wrapper and wrapper.Enable
    end)
    if type(disable) == "function" and type(enable) == "function" then
        local disabled = pcall(disable, wrapper)
        event:Fire()
        local blocked = disabled and deliveries == 0
        local enabled = pcall(enable, wrapper)
        event:Fire()
        report.tests.connection_disable_enable = blocked and enabled and deliveries == 1
    else
        report.tests.connection_disable_enable = false
    end
else
    report.tests.connection_disable_enable = false
end

connection:Disconnect()
event:Destroy()

if type(getActors) == "function" and type(runOnActor) == "function" then
    local listed, actors = pcall(getActors)
    local actor
    if listed and type(actors) == "table" then
        _, actor = next(actors)
    end
    if typeof(actor) == "Instance" then
        local bridge = Instance.new("Folder")
        bridge.Name = "HydroxideActorSmoke_"
            .. game:GetService("HttpService"):GenerateGUID(false):gsub("-", "")
        local handshakeEvent = Instance.new("BindableEvent")
        handshakeEvent.Name = "Data"
        handshakeEvent.Parent = bridge
        local parented, parentReason = pcall(function()
            bridge.Parent = game:GetService("CoreGui")
        end)
        if parented then
            local handshook = false
            local handshakeConnection = handshakeEvent.Event:Connect(function(value)
                handshook = value == "ready"
            end)
            local source = ([=[
local bridge = game:GetService("CoreGui"):FindFirstChild(%s, true)
if bridge then
    bridge.Data:Fire("ready")
end
]=]):format(string.format("%q", bridge.Name))
            local ran, actorReason = pcall(runOnActor, actor, source)
            if ran then
                task.wait(0.5)
            end
            report.tests.actor_bridge = ran and handshook
            if not ran then
                report.tests.actor_error = tostring(actorReason)
            end

            handshakeConnection:Disconnect()
        else
            report.tests.actor_bridge = false
            report.tests.actor_error = tostring(parentReason)
        end
        bridge:Destroy()
    else
        report.tests.actor_bridge = "no_actor"
    end
else
    report.tests.actor_bridge = "unsupported"
end

if environment.oh and type(environment.oh.RemoteSpyDiagnostics) == "function" then
    report.hydroxide = environment.oh.RemoteSpyDiagnostics()
end

environment.HydroxideExecutorSmokeReport = report
print("[Hydroxide executor smoke]", report.executor)
return report
