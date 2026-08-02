local RemotePolicy = {}

function RemotePolicy.DirectionForClass(className)
    return className:find("^Bindable") and "local" or "outgoing"
end

function RemotePolicy.ShouldCapture(stopped, active, executorCall, captureExecutorCalls)
    return not stopped and active and (not executorCall or captureExecutorCalls)
end

function RemotePolicy.ShouldStore(paused, directionIgnored, argsIgnored)
    return not paused and not directionIgnored and not argsIgnored
end

return RemotePolicy
