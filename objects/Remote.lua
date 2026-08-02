local Remote = {}

local directions = { "incoming", "outgoing", "local" }

local function newDirectionState()
    return {
        incoming = false,
        ["local"] = false,
        outgoing = false,
    }
end

local function updateSummary(remote, name, storage)
    local enabled = false
    for _, direction in ipairs(directions) do
        if storage[direction] then
            enabled = true
            break
        end
    end

    remote[name] = enabled
    return enabled
end

local function setDirectionState(remote, name, storage, enabled, direction)
    if direction ~= nil then
        if storage[direction] == nil then
            return false
        end

        if enabled == nil then
            storage[direction] = not storage[direction]
        else
            storage[direction] = enabled == true
        end
    else
        local nextState = enabled
        if nextState == nil then
            nextState = not remote[name]
        end

        for _, currentDirection in ipairs(directions) do
            storage[currentDirection] = nextState == true
        end
    end

    updateSummary(remote, name, storage)
    return direction and storage[direction] or remote[name]
end

function Remote.new(instance)
    local remote = {
        Blocked = false,
        BlockedArgs = {},
        BlockedDirections = newDirectionState(),
        Calls = 0,
        Ignored = false,
        IgnoredArgs = {},
        IgnoredDirections = newDirectionState(),
        Instance = instance,
        Logs = {},
        MaxLogs = (oh and oh.Config and oh.Config.MaxRemoteLogs) or 500,
        RetainedBytes = 0,
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
    remote.IsBlocked = Remote.isBlocked
    remote.IsIgnored = Remote.isIgnored
    remote.Unblock = Remote.unblock
    remote.Unignore = Remote.unignore
    return remote
end

function Remote.clear(remote)
    remote.Calls = 0
    remote.RetainedBytes = 0
    remote.TotalCalls = 0
    table.clear(remote.Logs)
end

function Remote.block(remote, enabled, direction)
    return setDirectionState(remote, "Blocked", remote.BlockedDirections, enabled, direction)
end

function Remote.unblock(remote, direction)
    return remote:Block(false, direction)
end

function Remote.isBlocked(remote, direction)
    if direction == nil then
        return remote.Blocked
    end

    return remote.BlockedDirections[direction] == true
end

function Remote.ignore(remote, enabled, direction)
    return setDirectionState(remote, "Ignored", remote.IgnoredDirections, enabled, direction)
end

function Remote.unignore(remote, direction)
    return remote:Ignore(false, direction)
end

function Remote.isIgnored(remote, direction)
    if direction == nil then
        return remote.Ignored
    end

    return remote.IgnoredDirections[direction] == true
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
    remote.TotalCalls += 1

    local evicted
    if #remote.Logs >= remote.MaxLogs then
        evicted = table.remove(remote.Logs, 1)
        remote.RetainedBytes = math.max(0, remote.RetainedBytes - (evicted.bytes or 0))
    end

    table.insert(remote.Logs, call)
    remote.Calls = #remote.Logs
    remote.RetainedBytes += call.bytes or 0
    return evicted
end

function Remote.decrementCalls(remote, call)
    local index = table.find(remote.Logs, call)
    if index then
        local removed = table.remove(remote.Logs, index)
        remote.RetainedBytes = math.max(0, remote.RetainedBytes - (removed.bytes or 0))
    end

    remote.Calls = #remote.Logs
end

Remote.Directions = directions

return Remote
