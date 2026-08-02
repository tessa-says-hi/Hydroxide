local CoreGui = game:GetService("CoreGui")
local UserInput = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Interface = import("rbxassetid://11389137937")

if oh.Cache["ui/main"] then
    return Interface
end

import("ui/controls/TabSelector")
local MessageBox, MessageType = import("ui/controls/MessageBox")

xpcall(function()
    import("ui/modules/RemoteSpy")
    import("ui/modules/ClosureSpy")
    import("ui/modules/ScriptScanner")
    import("ui/modules/ModuleScanner")
    import("ui/modules/UpvalueScanner")
    import("ui/modules/ConstantScanner")
end, function(err)
    err = tostring(err)
    local message
    if err:find("valid member") then
        message = "The UI has updated, please rejoin and restart. If you get this message more than once, screenshot this message and report it in the Hydroxide server.\n\n"
            .. err
    else
        message = "Report this error at " .. oh.Repository .. "/issues:\n\n" .. err
    end

    MessageBox.Show("An error has occurred", message, MessageType.OK, function()
        Interface:Destroy()
    end)
end)

local Open = Interface.Open
local Base = Interface.Base
local Drag = Base.Drag
local Status = Base.Status
local Collapse = Drag.Collapse

local camera = workspace.CurrentCamera
local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
local desiredScale = 1.3
local fitScale = math.min((viewport.X - 40) / Base.Size.X.Offset, (viewport.Y - 40) / Base.Size.Y.Offset)
local scale = math.min(desiredScale, math.max(0.8, fitScale))
local interfaceScale = Instance.new("UIScale")
interfaceScale.Name = "HydroxideScale"
interfaceScale.Scale = scale
interfaceScale.Parent = Base

local constants = {
    opened = UDim2.new(0.5, -325 * scale, 0.5, -175 * scale),
    closed = UDim2.new(0.5, -325 * scale, 0, -400 * scale),
    reveal = UDim2.new(0.5, -15, 0, 20),
    conceal = UDim2.new(0.5, -15, 0, -75),
}

Base.Position = constants.opened

function oh.setStatus(text)
    Status.Text = "• Status: " .. text
end

function oh.getStatus()
    return Status.Text:gsub("• Status: ", "")
end

local dragging
local dragStart
local startPos
local dragInput

Drag.InputBegan:Connect(function(input)
    if
        input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        local dragEnded

        dragging = true
        dragStart = input.Position
        startPos = Base.Position
        dragInput = input

        dragEnded = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                dragEnded:Disconnect()
            end
        end)
    end
end)

oh.Events.Drag = UserInput.InputChanged:Connect(function(input)
    if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = input.Position - dragStart
        Base.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

Open.MouseButton1Click:Connect(function()
    TweenService:Create(
        Open,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = constants.conceal }
    ):Play()
    TweenService:Create(
        Base,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = constants.opened }
    ):Play()
end)

Collapse.MouseButton1Click:Connect(function()
    TweenService:Create(
        Base,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = constants.closed }
    ):Play()
    TweenService:Create(
        Open,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = constants.reveal }
    ):Play()
end)

Interface.Name = HttpService:GenerateGUID(false)
if getHui then
    local ok, parent = pcall(getHui)
    Interface.Parent = ok and parent or CoreGui
else
    if syn and syn.protect_gui then
        pcall(syn.protect_gui, Interface)
    end

    Interface.Parent = CoreGui
end

return Interface
