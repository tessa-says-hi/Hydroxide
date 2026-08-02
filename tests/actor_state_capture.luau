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
local function newState(id, hooked)
    if hooked == nil then
        hooked = true
    end
    return {
        Id = id,
        Execute = function(_, source)
            local captureId = tonumber(source:match("local actorId = ([%-%d]+)"))
            assert(captureId == id)
            executions[id] = (executions[id] or 0) + 1
            bindables[1]:Fire(id, nil, {
                HookCount = hooked and 6 or 0,
                Hooked = hooked,
                Kind = "ready",
                MethodHooks = hooked and 5 or 0,
                NamecallHook = hooked,
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
moduleEnvironment.game = game
moduleEnvironment.getActorStates = getActorStates
moduleEnvironment.getActors = getActors
moduleEnvironment.getLuaState = getLuaState
moduleEnvironment.oh = oh
moduleEnvironment.runOnActor = runOnActor
moduleEnvironment.task = task

local ready = 0
local runtime = ActorRemoteSpy.Start(function() end, function()
    ready += 1
end)

local diagnostics = runtime:GetDiagnostics()
assert(diagnostics.Active)
assert(diagnostics.Available)
assert(diagnostics.Backend == "states")
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
assert(#diagnostics.Failures == 1)
assert(executions[10] == 1)
assert(executions[20] == 1)
assert(executions[25] == 1)
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
assert(bridge.Destroyed)

stateCreated:Fire({ State = newState(40) })
assert(executions[40] == nil)

bindables = {}
local actor = {
    IsA = function(_, className)
        return className == "Actor"
    end,
}
local legacyExecutions = 0
moduleEnvironment.actorStateCreated = nil
moduleEnvironment.getActorStates = nil
moduleEnvironment.getActors = function()
    return { actor }
end
moduleEnvironment.getLuaState = nil
moduleEnvironment.runOnActor = function(target, source)
    assert(target == actor)
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
moduleEnvironment.typeof = function(value)
    if value == actor then
        return "Instance"
    end
    return type(value)
end

runtime = ActorRemoteSpy.Start(function() end)
diagnostics = runtime:GetDiagnostics()
assert(diagnostics.Active)
assert(diagnostics.Backend == "actors")
assert(not diagnostics.StateCaptureAvailable)
assert(diagnostics.LegacyCaptureAvailable)
assert(diagnostics.Targets == 1)
assert(diagnostics.Attempts == 1)
assert(diagnostics.ReadyTargets == 1)
assert(diagnostics.ReadyActors == 1)
assert(diagnostics.ReadyStates == 0)
assert(legacyExecutions == 1)
runtime:Stop()

print("actor_state_capture: ok")
