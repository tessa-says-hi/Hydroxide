local PayloadSize = require("../methods/payloadSize")

local call = {
    args = table.pack("hello", 42, true),
    returns = table.pack("world"),
}
local size = PayloadSize.EstimateCall(call, 4096)
assert(size > 10)
assert(size <= 4096)

local cycle = {}
cycle.self = cycle
local cycleSize = PayloadSize.EstimateCall({ args = table.pack(cycle) }, 4096)
assert(cycleSize > 0)
assert(cycleSize <= 4096)

local oversized = PayloadSize.EstimateCall({ args = table.pack(string.rep("x", 2048)) }, 128)
assert(oversized == 129)

print("payload_size: ok")
