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
local first = { bytes = 10 }
local second = { bytes = 20 }
local third = { bytes = 30 }
assert(remote:IncrementCalls(first) == nil)
assert(remote:IncrementCalls(second) == nil)
assert(remote.RetainedBytes == 30)
assert(remote:IncrementCalls(third) == first)
assert(remote.RetainedBytes == 50)
remote:DecrementCalls(second)
assert(remote.RetainedBytes == 30)
remote:Clear()
assert(remote.RetainedBytes == 0)
assert(#remote.Logs == 0)

print("remote_state: ok")
