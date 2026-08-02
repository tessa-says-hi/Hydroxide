local GuiService = game:GetService("GuiService")
local UserInput = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Assets = import("rbxassetid://5042114982").Controls
local Storage = import("rbxassetid://11389137937").ContextMenus
local ContextMenuButton = {}
local ContextMenu = {}
local currentContextMenu
local constants = {
    fadeLength = TweenInfo.new(0.15),
    textWidth = Vector2.new(1337420, 20),
}

local function getGuiPoint(instance, point)
    point = Vector2.new(point.X, point.Y)

    local cam = workspace.CurrentCamera
    local viewport = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    local screenGui = instance:FindFirstAncestorWhichIsA("ScreenGui")
    if screenGui and not screenGui.IgnoreGuiInset then
        local topLeft, bottomRight = GuiService:GetGuiInset()
        return point - topLeft, viewport - topLeft - bottomRight
    end

    return point, viewport
end

local function getParentBounds(instance, viewport)
    local parent = instance.Parent
    if parent and parent:IsA("GuiObject") and parent.AbsoluteSize.X > 0 and parent.AbsoluteSize.Y > 0 then
        return parent.AbsolutePosition, parent.AbsoluteSize
    end

    return Vector2.zero, viewport
end

local function getScale(instance)
    local width = math.abs(instance.Size.X.Offset)
    if width > 0 and instance.AbsoluteSize.X > 0 then
        return instance.AbsoluteSize.X / width
    end

    return 1
end

function ContextMenuButton.new(icon, text)
    local contextMenuButton = {}
    local instance = Assets.ContextMenuButton:Clone()
    local label = instance.Label
    local enterAnimation = TweenService:Create(label, constants.fadeLength, { TextTransparency = 0 })
    local leaveAnimation = TweenService:Create(label, constants.fadeLength, { TextTransparency = 0.2 })

    label.Text = text
    instance.Icon.Image = icon
    instance.MouseButton1Click:Connect(function()
        if contextMenuButton.Callback then
            contextMenuButton.Callback()
        end
        if currentContextMenu then
            currentContextMenu:Hide()
            currentContextMenu = nil
        end
    end)
    instance.MouseEnter:Connect(function()
        enterAnimation:Play()
    end)
    instance.MouseLeave:Connect(function()
        leaveAnimation:Play()
    end)

    contextMenuButton.Instance = instance
    contextMenuButton.SetCallback = ContextMenuButton.setCallback
    contextMenuButton.SetIcon = ContextMenuButton.setIcon
    contextMenuButton.SetText = ContextMenuButton.setText
    return contextMenuButton
end

function ContextMenuButton.setIcon(contextMenuButton, newIcon)
    contextMenuButton.Instance.Icon.Image = newIcon
end

function ContextMenuButton.setText(contextMenuButton, newText)
    contextMenuButton.Instance.Label.Text = newText
    if contextMenuButton.Menu then
        contextMenuButton.Menu:Resize()
    end
end

function ContextMenuButton.setCallback(contextMenuButton, callback)
    contextMenuButton.Callback = callback
end

function ContextMenu.new(contextMenuButtons)
    local contextMenu = {}
    local instance = Assets.ContextMenu:Clone()

    instance.Parent = Storage
    for _, contextMenuButton in pairs(contextMenuButtons) do
        local button = contextMenuButton.Instance
        button.Parent = instance.List
        button.TextWrapped = false
        contextMenuButton.Menu = contextMenu
    end

    instance.Visible = false
    contextMenu.Buttons = contextMenuButtons
    contextMenu.Hide = ContextMenu.hide
    contextMenu.Instance = instance
    contextMenu.Resize = ContextMenu.resize
    contextMenu.Show = ContextMenu.show
    contextMenu.Visible = false
    contextMenu:Resize()
    return contextMenu
end

function ContextMenu.add(contextMenu, contextMenuButton)
    table.insert(contextMenu.Buttons, contextMenuButton)
    contextMenuButton.Instance.Parent = contextMenu.Instance.List
    contextMenuButton.Menu = contextMenu
    contextMenu:Resize()
end

function ContextMenu.resize(contextMenu)
    local width = 0
    local height = 0
    for _, contextMenuButton in ipairs(contextMenu.Buttons) do
        local button = contextMenuButton.Instance
        local textWidth = TextService:GetTextSize(button.Label.Text, 18, "SourceSans", constants.textWidth).X
        width = math.max(width, button.Icon.AbsoluteSize.X + textWidth + 16)
        height += button.AbsoluteSize.Y
    end

    contextMenu.Instance.Size = UDim2.new(0, width, 0, height)
end

function ContextMenu.show(contextMenu, position)
    if currentContextMenu then
        currentContextMenu:Hide()
    end

    local instance = contextMenu.Instance
    local point, viewport = getGuiPoint(instance, position or UserInput:GetMouseLocation())
    local parentPosition, parentSize = getParentBounds(instance, viewport)
    local min = Vector2.new(math.max(0, parentPosition.X), math.max(0, parentPosition.Y))
    local max = Vector2.new(
        math.min(viewport.X, parentPosition.X + parentSize.X),
        math.min(viewport.Y, parentPosition.Y + parentSize.Y)
    )
    local x = math.clamp(point.X, min.X, math.max(min.X, max.X - instance.AbsoluteSize.X))
    local y = math.clamp(point.Y, min.Y, math.max(min.Y, max.Y - instance.AbsoluteSize.Y))
    local anchorOffset = Vector2.new(
        instance.AbsoluteSize.X * instance.AnchorPoint.X,
        instance.AbsoluteSize.Y * instance.AnchorPoint.Y
    )
    local localPosition = Vector2.new(x, y) - parentPosition + anchorOffset
    local scale = getScale(instance)

    instance.Position = UDim2.fromOffset(localPosition.X / scale, localPosition.Y / scale)
    instance.Visible = true
    contextMenu.Visible = true
    currentContextMenu = contextMenu
end

function ContextMenu.hide(contextMenu)
    contextMenu.Visible = false
    contextMenu.Instance.Visible = false
    if currentContextMenu == contextMenu then
        currentContextMenu = nil
    end
end

function ContextMenu.containsPoint(point)
    if not currentContextMenu or not currentContextMenu.Visible then
        return false
    end

    local instance = currentContextMenu.Instance
    point = getGuiPoint(instance, point)
    local min = instance.AbsolutePosition
    local max = min + instance.AbsoluteSize
    return point.X >= min.X and point.Y >= min.Y and point.X <= max.X and point.Y <= max.Y
end

oh.ContextMenuContainsPoint = ContextMenu.containsPoint

oh.Events.ContextMenuInput = UserInput.InputBegan:Connect(function(input)
    if
        not currentContextMenu
        or (
            input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch
        )
    then
        return
    end

    if not ContextMenu.containsPoint(input.Position) then
        currentContextMenu:Hide()
    end
end)

return ContextMenu, ContextMenuButton
