local ClosureSpy = {}

local requiredMethods = {
    getConstant = true,
    getConstants = true,
    getContext = true,
    getInfo = true,
    getProtos = true,
    getUpvalue = true,
    getUpvalues = true,
    hookFunction = true,
    isLClosure = true,
    setConstant = true,
    setContext = true,
    setUpvalue = true,
}

local Hook = {}
local eventCallback
local hookCache = setmetatable({}, { __mode = "k" })

local function setEvent(callback)
    eventCallback = callback
end

local function getConditionBranch(storage, index)
    local branch = storage[index]
    if not branch then
        branch = {
            types = {},
            values = {},
        }
        storage[index] = branch
    end
    return branch
end

local function matchesConditions(storage, args)
    local count = args.n or #args
    for index = 1, count do
        local branch = storage[index]
        if branch then
            local value = args[index]
            if branch.types[typeof(value)] or (value ~= nil and branch.values[value] == true) then
                return true
            end
        end
    end
    return false
end

function Hook.new(closure)
    local target = closure.Data
    if hookCache[target] then
        return false
    end

    local ok, info = pcall(getInfo, target)
    if not ok or (info.nups or 0) < 1 then
        return
    end

    local hook = {
        Blocked = false,
        BlockedArgs = {},
        Calls = 0,
        Closure = closure,
        Ignored = false,
        IgnoredArgs = {},
        Logs = {},
        MaxLogs = (oh and oh.Config and oh.Config.MaxRemoteLogs) or 500,
        Target = target,
        TotalCalls = 0,
    }

    hook.AreArgsBlocked = Hook.areArgsBlocked
    hook.AreArgsIgnored = Hook.areArgsIgnored
    hook.Block = Hook.block
    hook.BlockArg = Hook.blockArg
    hook.Clear = Hook.clear
    hook.DecrementCalls = Hook.decrementCalls
    hook.Ignore = Hook.ignore
    hook.IgnoreArg = Hook.ignoreArg
    hook.IncrementCalls = Hook.incrementCalls
    hook.Log = Hook.log
    hook.Remove = Hook.remove

    local wrap = { hook }
    local original
    local hooked, result = pcall(hookFunction, target, function(...)
        local current = wrap[1]
        local args = table.pack(...)

        if not current.Ignored and not current:AreArgsIgnored(args) then
            current:Log(args)
        end

        if not current.Blocked and not current:AreArgsBlocked(args) then
            return wrap[2](...)
        end

        return nil
    end)

    if not hooked or type(result) ~= "function" then
        return
    end

    original = result
    wrap[2] = original
    hook.Original = original
    hookCache[target] = hook
    closure.Data = original

    if oh and oh.TrackHook then
        hook.HookRecord = oh.TrackHook(target, original)
    end

    return hook
end

function Hook.log(hook, args)
    local source
    if getCallingScript then
        local ok, result = pcall(getCallingScript)
        if ok and typeof(result) == "Instance" then
            source = result
        end
    end

    local call = {
        args = args,
        script = source,
    }
    hook:IncrementCalls(call)

    if eventCallback then
        task.defer(function()
            if oh and oh.Active and eventCallback then
                eventCallback(hook, call)
            end
        end)
    end
end

function Hook.remove(hook)
    if hook.HookRecord and oh and oh.RestoreHook then
        oh.RestoreHook(hook.HookRecord)
    else
        pcall(hookFunction, hook.Target, hook.Original)
    end

    hookCache[hook.Target] = nil
    hook.Closure.Data = hook.Target
end

function Hook.clear(hook)
    hook.Calls = 0
    hook.TotalCalls = 0
    table.clear(hook.Logs)
end

function Hook.block(hook, enabled)
    hook.Blocked = enabled == nil and not hook.Blocked or enabled == true
end

function Hook.ignore(hook, enabled)
    hook.Ignored = enabled == nil and not hook.Ignored or enabled == true
end

function Hook.blockArg(hook, index, value, byType)
    local branch = getConditionBranch(hook.BlockedArgs, index)
    if byType then
        branch.types[value] = true
    elseif value ~= nil then
        branch.values[value] = true
    end
end

function Hook.ignoreArg(hook, index, value, byType)
    local branch = getConditionBranch(hook.IgnoredArgs, index)
    if byType then
        branch.types[value] = true
    elseif value ~= nil then
        branch.values[value] = true
    end
end

function Hook.areArgsBlocked(hook, args)
    return matchesConditions(hook.BlockedArgs, args)
end

function Hook.areArgsIgnored(hook, args)
    return matchesConditions(hook.IgnoredArgs, args)
end

function Hook.incrementCalls(hook, call)
    hook.TotalCalls = hook.TotalCalls + 1
    if #hook.Logs >= hook.MaxLogs then
        call.evicted = table.remove(hook.Logs, 1)
    end
    table.insert(hook.Logs, call)
    hook.Calls = #hook.Logs
end

function Hook.decrementCalls(hook, call)
    local index = table.find(hook.Logs, call)
    if index then
        table.remove(hook.Logs, index)
    end
    hook.Calls = #hook.Logs
end

ClosureSpy.Hook = Hook
ClosureSpy.RequiredMethods = requiredMethods
ClosureSpy.SetEvent = setEvent
return ClosureSpy
