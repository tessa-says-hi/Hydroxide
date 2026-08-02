local function newSignal()
    local handlers = {}
    local signal = {}

    function signal:Connect(callback)
        local slot = {
            Callback = callback,
            Connected = true,
        }
        table.insert(handlers, slot)
        return {
            Disconnect = function()
                slot.Connected = false
            end,
        }
    end

    function signal:Fire(...)
        for _, slot in ipairs(handlers) do
            if slot.Connected then
                slot.Callback(...)
            end
        end
    end

    return signal
end

local bindables = {}
local bridge
local channelDestroyed = false
local channelSignal = newSignal()
local channelInternal = {
    Destroy = function()
        channelDestroyed = true
    end,
    Event = channelSignal,
    Fire = function(_, ...)
        channelSignal:Fire(...)
    end,
}
local channelReceiver = {
    Event = channelSignal,
    Internal = channelInternal,
}
local transportFire = function(...)
    channelSignal:Fire(...)
end
local legacyActor

Instance = {
    new = function(className)
        if className == "Folder" then
            bridge = {
                Destroy = function(self)
                    self.Destroyed = true
                end,
            }
            return bridge
        end

        local signal = newSignal()
        local event = {
            Event = signal,
            Fire = function(_, ...)
                signal:Fire(...)
            end,
        }
        table.insert(bindables, event)
        return event
    end,
}

game = {
    GetService = function(_, service)
        if service == "HttpService" then
            return {
                GenerateGUID = function()
                    return "actor-state-test"
                end,
            }
        end
        return {}
    end,
}

task = {
    delay = function(_, callback)
        callback()
    end,
    defer = function(callback)
        callback()
    end,
    spawn = function() end,
    wait = function() end,
}

oh = {
    Active = true,
    Config = {
        CaptureActors = true,
        CaptureExecutorCalls = false,
    },
    TrackConnection = function(connection)
        return connection
    end,
}

local stateCreated = newSignal()
actorStateCreated = stateCreated
getActors = nil
runOnActor = nil

local executions = {}
local executedSources = {}
local function newState(id, hooked)
    if hooked == nil then
        hooked = true
    end
    return {
        Id = id,
        Execute = function(_, source)
            local captureId = tonumber(source:match("local actorId = ([%-%d]+)"))
            assert(captureId == id)
            executedSources[id] = source
            executions[id] = (executions[id] or 0) + 1
            transportFire(id, nil, {
                HookCount = hooked and 6 or 0,
                Hooked = hooked,
                Kind = "ready",
                MethodHooks = hooked and 5 or 0,
                NamecallHook = hooked,
                OthHooks = hooked and 5 or 0,
                Transport = "channel",
            })
        end,
    }
end

getActorStates = function()
    return {
        newState(10),
        newState(10),
        newState(20),
        newState(25, false),
    }
end
getLuaState = function(actor)
    return actor.State
end

local ActorRemoteSpy = require("../modules/ActorRemoteSpy")
local moduleEnvironment = getfenv(ActorRemoteSpy.Start)
moduleEnvironment.Instance = Instance
moduleEnvironment.actorStateCreated = actorStateCreated
moduleEnvironment.createCommChannel = function()
    return 77, channelReceiver
end
moduleEnvironment.game = game
moduleEnvironment.getActorStates = getActorStates
moduleEnvironment.getActors = getActors
moduleEnvironment.getCommChannel = function()
    return channelInternal
end
moduleEnvironment.getLuaState = getLuaState
moduleEnvironment.oh = oh
moduleEnvironment.oth = {
    hook = function() end,
    unhook = function() end,
}
moduleEnvironment.runOnActor = runOnActor
moduleEnvironment.task = task
moduleEnvironment.typeof = function(value)
    if value == channelInternal or value == legacyActor then
        return "Instance"
    end
    return type(value)
end

local ready = 0
local runtime = ActorRemoteSpy.Start(function() end, function()
    ready += 1
end)

local diagnostics = runtime:GetDiagnostics()
assert(diagnostics.Active)
assert(diagnostics.Available)
assert(diagnostics.Backend == "states")
assert(diagnostics.CommunicationChannelAvailable)
assert(diagnostics.Transport == "channel")
assert(diagnostics.OthAvailable)
assert(diagnostics.StateCaptureAvailable)
assert(diagnostics.StateEvent)
assert(diagnostics.Targets == 3)
assert(diagnostics.Attempts == 3)
assert(diagnostics.ReportedTargets == 3)
assert(diagnostics.ReadyTargets == 2)
assert(diagnostics.ReadyStates == 2)
assert(diagnostics.ReadyActors == 2)
assert(diagnostics.MethodHookedTargets == 2)
assert(diagnostics.NamecallHookedTargets == 2)
assert(diagnostics.OthHookedTargets == 2)
assert(#diagnostics.Failures == 1)
assert(executions[10] == 1)
assert(executions[20] == 1)
assert(executions[25] == 1)
assert(executedSources[10]:find("local channelId = 77", 1, true))
assert(executedSources[10]:find("local useOth = true", 1, true))
assert(executedSources[10]:find("pcall(othHook, currentGroup.Target, replacement)", 1, true))
assert(executedSources[10]:find("pcall(othLibrary.unhook, hook.Target)", 1, true))
assert(executedSources[10]:find('(not useOth and type(hookFunction) == "function")', 1, true))
assert(executedSources[10]:find("ArgCount = args.n", 1, true))
assert(executedSources[10]:find("payload.ReturnCount = results.n - 1", 1, true))
assert(ready == 2)

stateCreated:Fire({ State = newState(10) })
diagnostics = runtime:GetDiagnostics()
assert(diagnostics.Targets == 3)
assert(diagnostics.Attempts == 3)
assert(executions[10] == 1)

local newActor = {
    State = newState(30),
}
stateCreated:Fire(newActor)

diagnostics = runtime:GetDiagnostics()
assert(diagnostics.Targets == 4)
assert(diagnostics.Attempts == 4)
assert(diagnostics.ReadyStates == 3)
assert(executions[30] == 1)
assert(ready == 3)

runtime:Stop()
assert(not runtime.Active)
assert(runtime.StateConnection == nil)
assert(channelDestroyed)

stateCreated:Fire({ State = newState(40) })
assert(executions[40] == nil)

bindables = {}
transportFire = function(...)
    bindables[1]:Fire(...)
end
local actor = {
    IsA = function(_, className)
        return className == "Actor"
    end,
}
legacyActor = actor
local legacyExecutions = 0
moduleEnvironment.actorStateCreated = nil
moduleEnvironment.createCommChannel = nil
moduleEnvironment.getActorStates = nil
moduleEnvironment.getActors = function()
    return { actor }
end
moduleEnvironment.getCommChannel = nil
moduleEnvironment.getLuaState = nil
moduleEnvironment.oth = nil
moduleEnvironment.runOnActor = function(target, source)
    assert(target == actor)
    assert(source:find("local channelId = nil", 1, true))
    assert(source:find("local useOth = false", 1, true))
    local captureId = tonumber(source:match("local actorId = ([%-%d]+)"))
    legacyExecutions += 1
    bindables[1]:Fire(captureId, nil, {
        HookCount = 6,
        Hooked = true,
        Kind = "ready",
        MethodHooks = 5,
        NamecallHook = true,
    })
end
runtime = ActorRemoteSpy.Start(function() end)
diagnostics = runtime:GetDiagnostics()
assert(diagnostics.Active)
assert(diagnostics.Backend == "actors")
assert(not diagnostics.StateCaptureAvailable)
assert(diagnostics.LegacyCaptureAvailable)
assert(not diagnostics.CommunicationChannelAvailable)
assert(not diagnostics.OthAvailable)
assert(diagnostics.Transport == "instance")
assert(diagnostics.Targets == 1)
assert(diagnostics.Attempts == 1)
assert(diagnostics.ReadyTargets == 1)
assert(diagnostics.ReadyActors == 1)
assert(diagnostics.ReadyStates == 0)
assert(legacyExecutions == 1)
runtime:Stop()
assert(bridge.Destroyed)

print("actor_state_capture: ok")
