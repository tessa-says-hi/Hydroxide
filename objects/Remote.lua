local Remote = {}

function Remote.new(instance)
    local remote = {
        Blocked = false,
        BlockedArgs = {},
        Calls = 0,
        Ignored = false,
        IgnoredArgs = {},
        Instance = instance,
        Logs = {},
        MaxLogs = (oh and oh.Config and oh.Config.MaxRemoteLogs) or 500,
        TotalCalls = 0,
    }

    remote.AreArgsBlocked = Remote.areArgsBlocked
    remote.AreArgsIgnored = Remote.areArgsIgnored
    remote.Block = Remote.block
    remote.BlockArg = Remote.blockArg
    remote.Clear = Remote.clear
    remote.DecrementCalls = Remote.decrementCalls
    remote.Ignore = Remote.ignore
    remote.IgnoreArg = Remote.ignoreArg
    remote.IncrementCalls = Remote.incrementCalls
    remote.Unblock = Remote.unblock
    remote.Unignore = Remote.unignore
    return remote
end

function Remote.clear(remote)
    remote.Calls = 0
    remote.TotalCalls = 0
    table.clear(remote.Logs)
end

function Remote.block(remote, enabled)
    if enabled == nil then
        remote.Blocked = not remote.Blocked
    else
        remote.Blocked = enabled == true
    end

    return remote.Blocked
end

function Remote.unblock(remote)
    remote.Blocked = false
end

function Remote.ignore(remote, enabled)
    if enabled == nil then
        remote.Ignored = not remote.Ignored
    else
        remote.Ignored = enabled == true
    end

    return remote.Ignored
end

function Remote.unignore(remote)
    remote.Ignored = false
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

function Remote.blockArg(remote, index, value, byType)
    local branch = getConditionBranch(remote.BlockedArgs, index)
    if byType then
        branch.types[value] = true
    elseif value ~= nil then
        branch.values[value] = true
    end
end

function Remote.ignoreArg(remote, index, value, byType)
    local branch = getConditionBranch(remote.IgnoredArgs, index)
    if byType then
        branch.types[value] = true
    elseif value ~= nil then
        branch.values[value] = true
    end
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

function Remote.areArgsBlocked(remote, args)
    return matchesConditions(remote.BlockedArgs, args)
end

function Remote.areArgsIgnored(remote, args)
    return matchesConditions(remote.IgnoredArgs, args)
end

function Remote.incrementCalls(remote, call)
    remote.TotalCalls = remote.TotalCalls + 1

    if #remote.Logs >= remote.MaxLogs then
        call.evicted = table.remove(remote.Logs, 1)
    end

    table.insert(remote.Logs, call)
    remote.Calls = #remote.Logs
    return call.evicted
end

function Remote.decrementCalls(remote, call)
    local index = table.find(remote.Logs, call)
    if index then
        table.remove(remote.Logs, index)
    end

    remote.Calls = #remote.Logs
end

return Remote
