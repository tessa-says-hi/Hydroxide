local UserInput = game:GetService("UserInputService")

local Dropdown = {}
local dropdownCache = {}

function Dropdown.new(instance)
    local dropdown = {}
    local selection = instance.Selection

    instance.Collapse.MouseButton1Click:Connect(function()
        local collapsed = not dropdown.Collapsed

        selection.Visible = not collapsed
        dropdown.Collapsed = collapsed
    end)

    for _i, v in pairs(instance.Selection.Clip.List:GetChildren()) do
        if v:IsA("TextButton") then
            v.MouseButton1Click:Connect(function()
                dropdown:Collapse(v.Name)
            end)
        end
    end

    dropdown.Collapse = Dropdown.collapse
    dropdown.Collapsed = true
    dropdown.Instance = instance
    dropdown.SetSelected = Dropdown.setSelected
    dropdown.SetCallback = Dropdown.setCallback
    selection.Visible = false

    table.insert(dropdownCache, dropdown)

    return dropdown
end

function Dropdown.setSelected(dropdown, buttonName)
    local instance = dropdown.Instance
    local selection = instance.Selection.Clip.List
    local button = selection:FindFirstChild(buttonName)

    if button then
        instance.Label.Text = buttonName

        instance.Selection.Visible = false
        dropdown.Collapsed = true
        dropdown.Selected = button
        if dropdown.Callback then
            dropdown:Callback(button)
        end
    end
end

function Dropdown.collapse(dropdown, name)
    local instance = dropdown.Instance
    local selection = instance.Selection

    if name then
        local button = selection.Clip.List:FindFirstChild(name)

        if button then
            instance.Label.Text = button.Name

            dropdown.Selected = button
            if dropdown.Callback then
                dropdown:Callback(button)
            end
        end
    end

    selection.Visible = false
    dropdown.Collapsed = true
end

function Dropdown.setCallback(dropdown, callback)
    dropdown.Callback = callback
end

local function containsPoint(instance, point)
    local min = instance.AbsolutePosition
    local max = min + instance.AbsoluteSize
    return point.X >= min.X and point.Y >= min.Y and point.X <= max.X and point.Y <= max.Y
end

oh.Events.DropdownCollapse = UserInput.InputBegan:Connect(function(input)
    if
        input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch
    then
        return
    end

    for _, dropdown in ipairs(dropdownCache) do
        if not dropdown.Collapsed then
            local instance = dropdown.Instance
            local selection = instance.Selection
            if
                not containsPoint(instance, input.Position) and not containsPoint(selection, input.Position)
            then
                dropdown:Collapse()
            end
        end
    end
end)

return Dropdown
