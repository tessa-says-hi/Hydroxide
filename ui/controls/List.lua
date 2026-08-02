local UserInput = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local List = {}
local ListButton = {}
local lists = {}
local ctrlHeld = false
local constants = {
    deselected = Color3.fromRGB(35, 35, 35),
    selected = Color3.fromRGB(55, 35, 35),
    tweenTime = TweenInfo.new(0.15),
}

function List.new(instance, multiClick)
    local list = {
        Buttons = {},
        Instance = instance,
        MultiClickEnabled = multiClick,
    }

    instance.CanvasSize = UDim2.new(0, 0, 0, 15)
    list.BindContextMenu = List.bindContextMenu
    list.BindContextMenuSelected = List.bindContextMenuSelected
    list.Clear = List.clear
    list.DeselectAll = List.deselectAll
    list.Recalculate = List.recalculate
    table.insert(lists, list)
    return list
end

local function showContextMenu(listButton, position)
    local list = listButton.List
    if listButton.RightCallback then
        listButton.RightCallback()
    end

    local menu = list.Selected and list.BoundContextMenuSelected or list.BoundContextMenu
    if menu then
        menu:Show(position)
    end
end

function ListButton.new(instance, list)
    local listButton = {
        Instance = instance,
        List = list,
    }
    local suppressClick = false
    local touchId = 0

    list.Buttons[instance] = listButton
    if instance.Visible then
        list.Instance.CanvasSize += UDim2.new(0, 0, 0, instance.AbsoluteSize.Y + 5)
    end
    instance.Parent = list.Instance

    instance.MouseButton1Click:Connect(function()
        if suppressClick then
            suppressClick = false
            return
        end

        if not ctrlHeld and listButton.Callback then
            listButton.Callback()
        elseif list.MultiClickEnabled and ctrlHeld then
            list.Selected = list.Selected or {}
            local found = table.find(list.Selected, listButton)
            if found then
                table.remove(list.Selected, found)
                listButton.DeselectAnimation:Play()
                if listButton.SelectedCallback then
                    listButton.SelectedCallback(false)
                end
                if #list.Selected == 0 then
                    list.Selected = nil
                end
            else
                table.insert(list.Selected, listButton)
                listButton.SelectAnimation:Play()
                if listButton.SelectedCallback then
                    listButton.SelectedCallback(true)
                end
            end
        end
    end)

    instance.MouseButton2Click:Connect(function()
        if not ctrlHeld then
            showContextMenu(listButton, UserInput:GetMouseLocation())
        end
    end)

    instance.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        touchId += 1
        local id = touchId
        local start = input.Position

        local changed
        changed = input.Changed:Connect(function()
            local ended = input.UserInputState == Enum.UserInputState.End
            if ended or (input.Position - start).Magnitude > 14 then
                touchId += 1
                changed:Disconnect()
                if suppressClick then
                    task.delay(0.2, function()
                        suppressClick = false
                    end)
                end
            end
        end)

        task.delay(0.55, function()
            if id == touchId then
                suppressClick = true
                showContextMenu(listButton, input.Position)
            end
        end)
    end)

    listButton.DeselectAnimation = TweenService:Create(instance, constants.tweenTime, {
        ImageColor3 = constants.deselected,
    })
    listButton.Remove = ListButton.remove
    listButton.SelectAnimation = TweenService:Create(instance, constants.tweenTime, {
        ImageColor3 = constants.selected,
    })
    listButton.SetCallback = ListButton.setCallback
    listButton.SetRemoveCallback = ListButton.setRemoveCallback
    listButton.SetRightCallback = ListButton.setRightCallback
    listButton.SetSelectedCallback = ListButton.setSelectedCallback
    return listButton
end

function List.clear(list)
    list:DeselectAll()

    local buttons = {}
    for _, listButton in pairs(list.Buttons) do
        table.insert(buttons, listButton)
    end
    for _, listButton in ipairs(buttons) do
        listButton:Remove()
    end

    for _, child in pairs(list.Instance:GetChildren()) do
        if child:IsA("ImageButton") then
            child:Destroy()
        end
    end

    list.Instance.CanvasSize = UDim2.new(0, 0, 0, 15)
    list.Buttons = {}
    list.Selected = nil
end

function List.deselectAll(list)
    local selected = list.Selected
    if not selected then
        return
    end

    list.Selected = nil
    for _, listButton in ipairs(selected) do
        listButton.DeselectAnimation:Play()
        if listButton.SelectedCallback then
            listButton.SelectedCallback(false)
        end
    end
end

function List.recalculate(list)
    local height = 15
    for instance in pairs(list.Buttons) do
        if instance.Visible then
            height += instance.AbsoluteSize.Y + 5
        end
    end
    list.Instance.CanvasSize = UDim2.new(0, 0, 0, height)
end

function List.bindContextMenu(list, contextMenu)
    list.BoundContextMenu = contextMenu
end

function List.bindContextMenuSelected(list, contextMenu)
    list.BoundContextMenuSelected = contextMenu
end

function ListButton.setCallback(listButton, callback)
    listButton.Callback = callback
end

function ListButton.setRemoveCallback(listButton, callback)
    listButton.RemoveCallback = callback
end

function ListButton.setRightCallback(listButton, callback)
    listButton.RightCallback = callback
end

function ListButton.setSelectedCallback(listButton, callback)
    listButton.SelectedCallback = callback
end

function ListButton.remove(listButton)
    if listButton.Removed then
        return
    end
    listButton.Removed = true

    local list = listButton.List
    local instance = listButton.Instance
    if instance.Visible and list.Buttons[instance] == listButton then
        list.Instance.CanvasSize -= UDim2.new(0, 0, 0, instance.AbsoluteSize.Y + 5)
    end
    list.Buttons[instance] = nil

    if list.Selected then
        local index = table.find(list.Selected, listButton)
        if index then
            table.remove(list.Selected, index)
            if listButton.SelectedCallback then
                listButton.SelectedCallback(false)
            end
        end
        if #list.Selected == 0 then
            list.Selected = nil
        end
    end

    if listButton.RemoveCallback then
        listButton.RemoveCallback()
    end
    instance:Destroy()
end

oh.Events.ListInputBegan = UserInput.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        ctrlHeld = true
    elseif
        not ctrlHeld
        and (
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        )
    then
        if oh.ContextMenuContainsPoint and oh.ContextMenuContainsPoint(input.Position) then
            return
        end

        for _, list in pairs(lists) do
            list:DeselectAll()
        end
    end
end)

oh.Events.ListInputEnded = UserInput.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        ctrlHeld = false
    end
end)

return List, ListButton
