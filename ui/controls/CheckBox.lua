local CheckBox = {}
local mark = utf8.char(10003)

function CheckBox.new(instance)
    local checkBox = {}
    local toggle = instance:FindFirstChild("Toggle") or instance
    local label = toggle.Label

    toggle.MouseButton1Click:Connect(function()
        checkBox.Enabled = not checkBox.Enabled
        if checkBox.Callback then
            checkBox.Callback(checkBox.Enabled)
        end
        label.Text = checkBox.Enabled and mark or ""
    end)

    checkBox.Enabled = label.Text == mark
    checkBox.Instance = instance
    checkBox.SetCallback = CheckBox.setCallback
    checkBox.SetEnabled = CheckBox.setEnabled
    return checkBox
end

function CheckBox.setCallback(checkBox, callback)
    checkBox.Callback = callback
end

function CheckBox.setEnabled(checkBox, enabled, notify)
    checkBox.Enabled = enabled == true
    local toggle = checkBox.Instance:FindFirstChild("Toggle") or checkBox.Instance
    toggle.Label.Text = checkBox.Enabled and mark or ""

    if notify and checkBox.Callback then
        checkBox.Callback(checkBox.Enabled)
    end
end

return CheckBox
