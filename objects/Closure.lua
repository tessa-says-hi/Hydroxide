local Closure = {}
local closureCache = {}

function Closure.new(data)
    if closureCache[data] then
        return closureCache[data]
    end

    local closure = {}
    local ok, info = pcall(getInfo, data)
    local name = ok and info and info.name or ""

    closure.Name = (name ~= "" and name) or "Unnamed function"
    closure.Data = data
    local envOk, env = pcall(getfenv, data)
    closure.Environment = envOk and env or {}

    closure.Upvalues = {}
    closure.Constants = {}

    closure.TemporaryUpvalues = {}
    closure.TemporaryConstants = {}

    closureCache[data] = closure
    return closure
end

return Closure
