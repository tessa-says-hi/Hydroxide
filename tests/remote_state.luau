local Remote = require("../objects/Remote")

local remote = Remote.new("Remote")
assert(not remote.Blocked)
assert(not remote:IsBlocked("incoming"))
assert(not remote:IsBlocked("outgoing"))

assert(remote:Block(true, "incoming"))
assert(remote.Blocked)
assert(remote:IsBlocked("incoming"))
assert(not remote:IsBlocked("outgoing"))

remote:Block(true, "outgoing")
remote:Block(false, "incoming")
assert(remote.Blocked)
assert(not remote:IsBlocked("incoming"))
assert(remote:IsBlocked("outgoing"))

remote:Block()
assert(not remote.Blocked)
for _, direction in ipairs(Remote.Directions) do
    assert(not remote:IsBlocked(direction))
end

remote:Ignore(true)
for _, direction in ipairs(Remote.Directions) do
    assert(remote:IsIgnored(direction))
end
remote:Unignore("local")
assert(not remote:IsIgnored("local"))
assert(remote.Ignored)

remote.MaxLogs = 2
local first = { bytes = 10, direction = "outgoing" }
local second = { bytes = 20, direction = "incoming" }
local third = { bytes = 30, direction = "local" }
assert(remote:IncrementCalls(first) == nil)
assert(remote:IncrementCalls(second) == nil)
assert(remote.RetainedBytes == 30)
assert(remote:IncrementCalls(third) == first)
assert(remote.RetainedBytes == 50)
assert(remote.TotalCallsByDirection.outgoing == 1)
assert(remote.TotalCallsByDirection.incoming == 1)
assert(remote.TotalCallsByDirection["local"] == 1)
remote:DecrementCalls(second)
assert(remote.RetainedBytes == 30)
remote:Clear()
assert(remote.RetainedBytes == 0)
assert(#remote.Logs == 0)
assert(remote.TotalCallsByDirection.outgoing == 0)
assert(remote.TotalCallsByDirection.incoming == 0)
assert(remote.TotalCallsByDirection["local"] == 0)

print("remote_state: ok")
