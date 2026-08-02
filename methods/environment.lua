local methods = {}
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerScripts = player and player:FindFirstChildOfClass("PlayerScripts")
local control = playerScripts
    and (playerScripts:FindFirstChild("PlayerModule") or playerScripts:FindFirstChild("ControlScript"))

local function secureCall(closure, ...)
    if syn and syn.secure_call and control then
        return syn.secure_call(closure, control, ...)
    end

    return closure(...)
end

methods.secureCall = secureCall
return methods
