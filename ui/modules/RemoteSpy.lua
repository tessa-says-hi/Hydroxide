local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local RemoteSpy = {}
local Methods = import("modules/RemoteSpy")
local ClosureSpy = import("modules/ClosureSpy")
local Closure = import("objects/Closure")

if not hasMethods(Methods.RequiredMethods) then
    return RemoteSpy
end

local Prompt = import("ui/controls/Prompt")
local CheckBox = import("ui/controls/CheckBox")
local Dropdown = import("ui/controls/Dropdown")
local List, ListButton = import("ui/controls/List")
local MessageBox, MessageType = import("ui/controls/MessageBox")
local ContextMenu, ContextMenuButton = import("ui/controls/ContextMenu")
local TabSelector = import("ui/controls/TabSelector")

local Base = import("rbxassetid://11389137937").Base
local Assets = import("rbxassetid://5042114982").RemoteSpy

local Prompts = Base.Prompts
local Page = Base.Body.Pages.RemoteSpy

local RemoteList = Page.List
local ListFlags = RemoteList.Flags
local ListQuery = RemoteList.Query
local ListSearch = ListQuery.Search
local ListRefresh = ListQuery.Refresh
local ListResults = RemoteList.Results.Clip.Content
local ListStatus = RemoteList.Results.Clip.ResultStatus

local RemoteLogs = Page.Logs
local LogsButtons = RemoteLogs.Buttons
local LogsRemote = RemoteLogs.RemoteObject
local LogsBack = RemoteLogs.Back
local LogsResults = RemoteLogs.Results.Clip.Content

local RemoteConditions = Page.Conditions
local ConditionsRemote = RemoteConditions.RemoteObject
local ConditionsButtons = RemoteConditions.Buttons
local ConditionsResults = RemoteConditions.Results.Clip.Content
local ConditionsBack = RemoteConditions.Back

local NewRemoteCondition = Prompts.NewRemoteCondition
local NewConditionInner = NewRemoteCondition.Inner
local NewConditionButtons = NewConditionInner.Buttons
local NewConditionContent = NewConditionInner.Content
local NewConditionIndex = NewConditionContent.Index

local remotesViewing = Methods.RemotesViewing
local currentRemotes = Methods.CurrentRemotes

local icons = {
    type = "rbxassetid://4702850565",
    status = "rbxassetid://4909102841",
    valueType = "rbxassetid://4702850565",
    block = "rbxassetid://4891641806",
    unblock = "rbxassetid://4891642508",
    ignore = "rbxassetid://4842578510",
    unignore = "rbxassetid://4842578818",
    RemoteEvent = "rbxassetid://4229806545",
    UnreliableRemoteEvent = "rbxassetid://4229806545",
    RemoteFunction = "rbxassetid://4229810474",
    BindableEvent = "rbxassetid://4229809371",
    BindableFunction = "rbxassetid://4229807624",
}

local constants = {
    fadeLength = TweenInfo.new(0.15),
    textWidth = Vector2.new(1337420, 20),
    normalColor = Color3.new(1, 1, 1),
    blockedColor = Color3.fromRGB(170, 0, 0),
    ignoredColor = Color3.fromRGB(100, 100, 100),
}

local newRemoteCondition = Prompt.new(NewRemoteCondition)
local conditionStatus = Dropdown.new(NewConditionContent.Status)
local conditionType = Dropdown.new(NewConditionContent.Type)
local conditionValueType = Dropdown.new(NewConditionContent.ValueType)

local remoteList = List.new(ListResults, true)
local remoteLogs = List.new(LogsResults)
local remoteConditions = List.new(ConditionsResults, true)

local currentLogs = {}
local removed = {}

local selected = {
    logs = {},
    conditions = {},
}

local function updateRemoteStatus()
    local hasLogs = next(currentLogs) ~= nil
    local hasVisibleLogs = false

    for _, log in pairs(currentLogs) do
        if log.Button.Instance.Visible then
            hasVisibleLogs = true
            break
        end
    end

    ListStatus.Text = hasLogs and "No remotes match filters" or "No remotes logged"
    ListStatus.Visible = not hasVisibleLogs
end

local function findRetainedCall(remote, callInfo)
    if type(callInfo) ~= "table" then
        return
    end

    if table.find(remote.Logs, callInfo) then
        return callInfo
    end

    local callId = callInfo.id
    if callId == nil then
        return
    end

    for index = #remote.Logs, 1, -1 do
        local retained = remote.Logs[index]
        if retained.id == callId then
            return retained
        end
    end
end

local function updateSelection(items, item, enabled)
    local index = table.find(items, item)
    if enabled and not index then
        table.insert(items, item)
    elseif not enabled and index then
        table.remove(items, index)
    end
end

local pathContext = ContextMenuButton.new("rbxassetid://4891705738", "Get Remote Path")
local conditionContext = ContextMenuButton.new("rbxassetid://4891633802", "Call Conditions")
local clearContext = ContextMenuButton.new("rbxassetid://4892169181", "Clear Calls")
local ignoreContext = ContextMenuButton.new("rbxassetid://4842578510", "Ignore Calls")
local blockContext = ContextMenuButton.new("rbxassetid://4891641806", "Block Calls")
local removeContext = ContextMenuButton.new("rbxassetid://4702831188", "Remove Log")
local pauseContext = ContextMenuButton.new("rbxassetid://4907151581", "Pause Capture")
local exportContext = ContextMenuButton.new("rbxassetid://4800244808", "Export Calls")

local scriptContext = ContextMenuButton.new("rbxassetid://4800244808", "Generate Script")
local callingScriptContext = ContextMenuButton.new("rbxassetid://4800244808", "Get Calling Script")
local spyClosureContext = ContextMenuButton.new("rbxassetid://4666593447", "Spy Calling Function")
local repeatCallContext = ContextMenuButton.new("rbxassetid://4907151581", "Repeat Call")
local viewAsHexContext = ContextMenuButton.new("rbxassetid://9058292613", "Toggle String Hex View")

local removeConditionContext = ContextMenuButton.new("rbxassetid://4702831188", "Remove Condition")

local pathContextSelected = ContextMenuButton.new("rbxassetid://4891705738", "Get Paths")
local clearContextSelected = ContextMenuButton.new("rbxassetid://4892169181", "Clear Calls")
local ignoreContextSelected = ContextMenuButton.new("rbxassetid://4842578510", "Ignore Calls")
local blockContextSelected = ContextMenuButton.new("rbxassetid://4891641806", "Block Calls")
local unignoreContextSelected = ContextMenuButton.new("rbxassetid://4842578818", "Unignore Calls")
local unblockContextSelected = ContextMenuButton.new("rbxassetid://4891642508", "Unblock Calls")
local removeContextSelected = ContextMenuButton.new("rbxassetid://4702831188", "Remove Logs")

local removeConditionContextSelected = ContextMenuButton.new("rbxassetid://4702831188", "Remove Conditions")

local remoteListMenu = ContextMenu.new({
    pathContext,
    conditionContext,
    clearContext,
    ignoreContext,
    blockContext,
    exportContext,
    pauseContext,
    removeContext,
})
local remoteListMenuSelected = ContextMenu.new({
    pathContextSelected,
    clearContextSelected,
    ignoreContextSelected,
    unignoreContextSelected,
    blockContextSelected,
    unblockContextSelected,
    removeContextSelected,
})
local remoteLogsMenu = ContextMenu.new({
    scriptContext,
    callingScriptContext,
    spyClosureContext,
    repeatCallContext,
    viewAsHexContext,
})
local remoteConditionMenu = ContextMenu.new({ removeConditionContext })
local remoteConditionMenuSelected = ContextMenu.new({ removeConditionContextSelected })

local function checkCurrentIgnored()
    if not selected.remoteLog then
        return
    end

    local selectedRemote = selected.remoteLog.Remote

    LogsButtons.Ignore.Label.Text = (selectedRemote.Ignored and "Unignore") or "Ignore"
    LogsButtons.Ignore.Icon.Image = (selectedRemote.Ignored and icons.unignore) or icons.ignore

    local newWidth = TextService:GetTextSize(
        (selectedRemote.Ignored and "Unignore") or "Ignore",
        18,
        "SourceSans",
        constants.textWidth
    ).X + 30

    LogsButtons.Ignore.Size = UDim2.new(0, newWidth, 0, 20)
end

local function checkCurrentBlocked()
    if not selected.remoteLog then
        return
    end

    local selectedRemote = selected.remoteLog.Remote

    LogsButtons.Block.Label.Text = (selectedRemote.Blocked and "Unblock") or "Block"
    LogsButtons.Block.Icon.Image = (selectedRemote.Blocked and icons.unblock) or icons.block

    local newWidth = TextService:GetTextSize(
        (selectedRemote.Blocked and "Unblock") or "Block",
        18,
        "SourceSans",
        constants.textWidth
    ).X + 30

    LogsButtons.Block.Size = UDim2.new(0, newWidth, 0, 20)
end

local Condition = {}
function Condition.new(remote, status, index, value, type)
    local condition = {}
    local instance = Assets.ConditionPod:Clone()
    local content = instance.Content
    local identifiers = instance.Identifiers
    local button = ListButton.new(instance, remoteConditions)
    local check = CheckBox.new(content.Toggle)
    local valueType = type or typeof(value)
    local typeIcons = oh.Constants.Types
    local branch = (status == "Ignore" and remote.IgnoredArgs[index]) or remote.BlockedArgs[index]

    condition.Branch = branch
    condition.Status = status
    condition.Index = index
    condition.Value = value
    condition.Type = type
    condition.Remote = remote
    condition.Enabled = true
    condition.Instance = instance
    condition.Button = button
    condition.Toggle = Condition.toggle
    condition.Remove = Condition.remove

    check:SetCallback(function()
        condition:Toggle()
    end)

    button:SetRightCallback(function()
        selected.condition = condition
    end)

    button:SetSelectedCallback(function(enabled)
        updateSelection(selected.conditions, condition, enabled)
    end)

    identifiers.ByType.Visible = type ~= nil
    identifiers.Status.Image = (status == "Ignore" and icons.ignore) or icons.block
    identifiers.Status.Border.Image = identifiers.Status.Image

    content.Index.Text = index
    content.Label.Text = (type and valueType) or toString(value)
    content.Label.TextColor3 = oh.Constants.Syntax[valueType] or oh.Constants.Syntax["userdata"]
    content.Type.Image = typeIcons[valueType] or typeIcons["userdata"]

    return condition
end

function Condition.toggle(condition)
    condition.Enabled = not condition.Enabled

    local index = condition.Index
    local value = condition.Value
    local remote = condition.Remote
    local ignoredArgs = remote.IgnoredArgs[index]
    local blockedArgs = remote.BlockedArgs[index]
    local argStatus = (condition.Status == "Ignore" and ignoredArgs) or blockedArgs

    if value ~= nil then
        argStatus.values[value] = condition.Enabled or nil
    else
        argStatus.types[condition.Type] = condition.Enabled or nil
    end
end

function Condition.remove(condition)
    local branch = condition.Branch
    condition.Button:Remove()

    if condition.Value ~= nil then
        branch.values[condition.Value] = nil
    else
        branch.types[condition.Type] = nil
    end
end

local function createConditions(remote)
    remoteConditions:Clear()

    RemoteList.Visible = false
    RemoteLogs.Visible = false
    RemoteConditions.Visible = true

    local remoteInstance = remote.Instance
    local remoteInstanceName = remoteInstance.Name
    local remoteClassName = remoteInstance.ClassName
    local nameLength = TextService:GetTextSize(remoteInstanceName, 18, "SourceSans", constants.textWidth).X
        + 20

    ConditionsRemote.Icon.Image = icons[remoteClassName] or icons.RemoteEvent
    ConditionsRemote.Label.Text = remoteInstanceName
    ConditionsRemote.Label.Size = UDim2.new(0, nameLength, 0, 20)
    ConditionsRemote.Position = UDim2.new(1, -nameLength, 0, 0)

    for index, arg in pairs(remote.IgnoredArgs) do
        for type in pairs(arg.types) do
            Condition.new(remote, "Ignore", index, nil, type)
        end

        for value in pairs(arg.values) do
            Condition.new(remote, "Ignore", index, value)
        end
    end

    for index, arg in pairs(remote.BlockedArgs) do
        for type in pairs(arg.types) do
            Condition.new(remote, "Block", index, nil, type)
        end

        for value in pairs(arg.values) do
            Condition.new(remote, "Block", index, value)
        end
    end
end

remoteList:BindContextMenu(remoteListMenu)
remoteList:BindContextMenuSelected(remoteListMenuSelected)
remoteLogs:BindContextMenu(remoteLogsMenu)
remoteConditions:BindContextMenu(remoteConditionMenu)
remoteConditions:BindContextMenuSelected(remoteConditionMenuSelected)

-- Log Objects
local Log = {}
local ArgsLog = {}

function Log.new(remote)
    local log = {}
    local button = Assets.RemoteLog:Clone()
    local remoteInstance = remote.Instance
    local remoteInstanceName = remoteInstance.Name
    local remoteClassName = remoteInstance.ClassName
    local listButton = ListButton.new(button, remoteList)

    local normalAnimation =
        TweenService:Create(button.Label, constants.fadeLength, { TextColor3 = constants.normalColor })
    local blockAnimation =
        TweenService:Create(button.Label, constants.fadeLength, { TextColor3 = constants.blockedColor })
    local ignoreAnimation =
        TweenService:Create(button.Label, constants.fadeLength, { TextColor3 = constants.ignoredColor })

    button.Name = remoteInstanceName
    button.Label.Text = remoteInstanceName
    button.Icon.Image = icons[remoteClassName] or icons.RemoteEvent

    local function viewLogs()
        if selected.remoteLog then
            remoteLogs:Clear()
        end

        local nameLength = TextService:GetTextSize(remoteInstanceName, 18, "SourceSans", constants.textWidth).X
            + 20

        selected.remoteLog = log

        for _i, call in ipairs(remote.Logs) do
            ArgsLog.new(log, call)
        end

        checkCurrentBlocked()
        checkCurrentIgnored()

        LogsRemote.Icon.Image = icons[remoteClassName] or icons.RemoteEvent
        LogsRemote.Label.Text = remoteInstanceName
        LogsRemote.Label.Size = UDim2.new(0, nameLength, 0, 20)
        LogsRemote.Position = UDim2.new(1, -nameLength, 0, 0)

        remoteLogs:Recalculate()
    end

    listButton:SetCallback(function()
        if selected.remoteLog ~= log then
            if #remote.Logs > 400 then
                MessageBox.Show(
                    "Warning",
                    "This remote seems to have a lot of calls, opening this may cause your game to freeze for a few seconds.\n\nContinue?",
                    MessageType.YesNo,
                    viewLogs
                )
            else
                viewLogs()
            end
        end

        RemoteList.Visible = false
        RemoteLogs.Visible = true
    end)

    listButton:SetRightCallback(function()
        ignoreContext:SetIcon((remote.Ignored and icons.unignore) or icons.ignore)
        ignoreContext:SetText((remote.Ignored and "Unignore Calls") or "Ignore Calls")
        blockContext:SetIcon((remote.Blocked and icons.unblock) or icons.block)
        blockContext:SetText((remote.Blocked and "Unblock Calls") or "Block Calls")

        selected.logContext = log
    end)

    listButton:SetSelectedCallback(function(enabled)
        updateSelection(selected.logs, log, enabled)
    end)

    currentLogs[remoteInstance] = log

    log.Remote = remote
    log.Button = listButton
    log.BlockAnimation = blockAnimation
    log.IgnoreAnimation = ignoreAnimation
    log.NormalAnimation = normalAnimation
    log.Clear = Log.clear
    log.PlayBlock = Log.playBlock
    log.PlayIgnore = Log.playIgnore
    log.PlayNormal = Log.playNormal
    log.Adjust = Log.adjust
    log.IncrementCalls = Log.incrementCalls
    log.DecrementCalls = Log.decrementCalls
    log.Remove = Log.remove
    updateRemoteStatus()
    return log
end

local function createArg(instance, index, value)
    local arg = Assets.RemoteArg:Clone()
    local valueType = typeof(value)
    local luaType = type(value)

    arg.Icon.Image = oh.Constants.Types[valueType]
        or oh.Constants.Types[luaType]
        or oh.Constants.Types.userdata
    arg.Index.Text = index

    if luaType == "table" then
        arg.Label.Text = toString(value)
    else
        local serialized, supported = dataToString(value)
        arg.Label.Text = supported and serialized or toString(value)
    end

    arg.Label.TextColor3 = oh.Constants.Syntax[valueType]
        or oh.Constants.Syntax[luaType]
        or oh.Constants.Syntax.userdata
    arg.Name = tostring(index)
    arg.Parent = instance.Contents

    return arg.AbsoluteSize.Y + 5
end

function ArgsLog.new(log, callInfo)
    local instance = Assets.CallPod:Clone()
    local args = callInfo.args

    if selected.remoteLog ~= log then
        instance.Visible = false
    end

    local button = ListButton.new(instance, remoteLogs)
    local height = 0

    height += createArg(instance, "DIR", callInfo.direction)
    height += createArg(instance, "OP", callInfo.method)
    if callInfo.blocked then
        height += createArg(instance, "BLOCK", true)
    end
    if callInfo.duration then
        height += createArg(instance, "SEC", callInfo.duration)
    end

    local count = args.n or #args
    if count == 0 then
        height = height + createArg(instance, 1, nil)
    else
        for i = 1, count do
            local v = args[i]
            height = height + createArg(instance, i, v)
        end
    end

    if callInfo.returns then
        local returnCount = callInfo.returns.n or #callInfo.returns
        for i = 1, returnCount do
            height = height + createArg(instance, "R" .. i, callInfo.returns[i])
        end
    elseif callInfo.error then
        height = height + createArg(instance, "ERR", callInfo.error)
    end

    button:SetRightCallback(function()
        local incoming = callInfo.direction == "incoming"

        scriptContext:SetText(incoming and "Generate Local Replay" or "Generate Script")
        callingScriptContext:SetText(incoming and "Get Receiver Scripts" or "Get Calling Script")
        spyClosureContext:SetText(incoming and "Spy Receiver Functions" or "Spy Calling Function")
        repeatCallContext:SetText(incoming and "Replay Incoming Locally" or "Repeat Call")

        selected.args = callInfo.args
        selected.callingScript = callInfo.script
        selected.func = callInfo.func
        selected.call = callInfo
        selected.callPodButton = button
    end)

    button.Instance.Size = button.Instance.Size + UDim2.new(0, 0, 0, height)
    callInfo.Button = button
    button:SetRemoveCallback(function()
        if callInfo.Button == button then
            callInfo.Button = nil
        end
    end)

    return button
end

function Log.playIgnore(log)
    log.IgnoreAnimation:Play()
end

function Log.playBlock(log)
    log.BlockAnimation:Play()
end

function Log.playNormal(log)
    log.NormalAnimation:Play()
end

function Log.adjust(log)
    local remoteClassName = log.Remote.Instance.ClassName
    local logInstance = log.Button.Instance
    local logIcon = logInstance.Icon

    local callWidth = TextService:GetTextSize(logInstance.Calls.Text, 18, "SourceSans", constants.textWidth).X
        + 10
    local iconPosition = callWidth
        - (
            (
                (
                    remoteClassName == "RemoteEvent"
                    or remoteClassName == "UnreliableRemoteEvent"
                    or remoteClassName == "BindableEvent"
                ) and 4
            ) or 0
        )
    local labelWidth = iconPosition + 21

    logInstance.Calls.Size = UDim2.new(0, callWidth, 1, 0)
    logIcon.Position = UDim2.new(
        0,
        iconPosition,
        0.5,
        ((remoteClassName == "RemoteEvent" or remoteClassName == "UnreliableRemoteEvent") and -9) or -7
    )
    logInstance.Label.Position = UDim2.new(0, labelWidth, 0, 0)
    logInstance.Label.Size = UDim2.new(1, -labelWidth, 1, 0)
end

function Log.clear(log)
    local logInstance = log.Button.Instance

    log.Remote:Clear()

    if selected.remoteLog == log then
        remoteLogs:Clear()
    end

    logInstance.Calls.Text = 0
    log:Adjust()
end

function Log.incrementCalls(log, callInfo)
    local buttonInstance = log.Button.Instance
    local remote = log.Remote
    local calls = remote.TotalCalls

    if callInfo.evicted and callInfo.evicted.Button then
        callInfo.evicted.Button:Remove()
        callInfo.evicted.Button = nil
    end

    buttonInstance.Calls.Text = (calls < 10000 and calls) or "..."

    log:Adjust()

    if selected.remoteLog == log and not callInfo.Button then
        ArgsLog.new(log, callInfo)
        remoteLogs:Recalculate()
    end
end

function Log.decrementCalls(log, call)
    local buttonInstance = log.Button.Instance
    local remote = log.Remote
    remote:DecrementCalls(call)
    local calls = remote.TotalCalls
    buttonInstance.Calls.Text = (calls < 10000 and calls) or "..."
    log:Adjust()
end

function Log.remove(log)
    local remoteInstance = log.Remote.Instance

    log.Button:Remove()
    if selected.remoteLog == log then
        remoteLogs:Clear()
        selected.remoteLog = nil
    end
    if selected.logContext == log then
        selected.logContext = nil
    end
    currentLogs[remoteInstance] = nil
    removed[remoteInstance] = true
    updateRemoteStatus()
end

-- UI Functionality

local function refreshLogs()
    for remoteInstance, log in pairs(currentLogs) do
        log.Button.Instance.Visible = remotesViewing[remoteInstance.ClassName]
    end

    remoteList:Recalculate()
    updateRemoteStatus()
end

for _i, flag in pairs(ListFlags:GetChildren()) do
    if flag:IsA("Frame") then
        local check = CheckBox.new(flag)
        check:SetEnabled(remotesViewing[flag.Name] == true)

        check:SetCallback(function(enabled)
            remotesViewing[flag.Name] = enabled
            if flag.Name == "RemoteEvent" then
                remotesViewing.UnreliableRemoteEvent = enabled
            end
            refreshLogs()
        end)
    end
end

ListSearch.FocusLost:Connect(function(returned)
    if returned then
        for remoteInstance, log in pairs(currentLogs) do
            local instance = log.Button.Instance
            instance.Visible = remotesViewing[remoteInstance.ClassName]
                and remoteInstance.Name:lower():find(ListSearch.Text:lower(), 1, true) ~= nil
        end

        remoteList:Recalculate()
        updateRemoteStatus()
        ListSearch.Text = ""
    end
end)

ListRefresh.MouseButton1Click:Connect(function()
    refreshLogs()
end)

LogsBack.MouseButton1Click:Connect(function()
    RemoteLogs.Visible = false
    RemoteList.Visible = true
    remoteLogs:Clear()
    selected.remoteLog = nil
    selected.call = nil
    selected.args = nil
    selected.callingScript = nil
    selected.func = nil
    selected.callPodButton = nil
end)

LogsButtons.Ignore.MouseButton1Click:Connect(function()
    local selectedRemote = selected.remoteLog.Remote

    selectedRemote:Ignore()

    checkCurrentIgnored()

    if selectedRemote.Blocked then
        selected.remoteLog:PlayBlock()
    elseif selectedRemote.Ignored then
        selected.remoteLog:PlayIgnore()
    else
        selected.remoteLog:PlayNormal()
    end
end)

LogsButtons.Block.MouseButton1Click:Connect(function()
    local selectedRemote = selected.remoteLog.Remote

    selectedRemote:Block()

    checkCurrentBlocked()

    if selectedRemote.Blocked then
        selected.remoteLog:PlayBlock()
    elseif selectedRemote.Ignored then
        selected.remoteLog:PlayIgnore()
    else
        selected.remoteLog:PlayNormal()
    end
end)

LogsButtons.Clear.MouseButton1Click:Connect(function()
    selected.remoteLog:Clear()
end)

LogsButtons.Conditions.MouseButton1Click:Connect(function()
    selected.conditionLog = selected.remoteLog
    selected.conditionReturnToLogs = true

    createConditions(selected.conditionLog.Remote)
end)

ConditionsBack.MouseButton1Click:Connect(function()
    RemoteConditions.Visible = false

    if selected.conditionReturnToLogs then
        RemoteLogs.Visible = true
    else
        RemoteList.Visible = true
    end
end)

ConditionsButtons.New.MouseButton1Click:Connect(function()
    newRemoteCondition:Show()
end)

NewConditionButtons.Add.MouseButton1Click:Connect(function()
    if not conditionStatus.Selected or not conditionType.Selected or not conditionValueType.Selected then
        return MessageBox.Show("Error", "Select a status, type, and value mode", MessageType.OK)
    end

    local status = conditionStatus.Selected.Name
    local type = conditionType.Selected.Name
    local valueType = conditionValueType.Selected.Name
    local value = NewConditionContent.Value.Input.Text

    if status ~= "Ignore" and status ~= "Block" then
        return MessageBox.Show("Error", "Invalid condition status", MessageType.OK)
    elseif not oh.Constants.Types[type] and not isUserdata(type) then
        return MessageBox.Show("Error", "Invalid condition type", MessageType.OK)
    elseif valueType ~= "Value" and valueType ~= "Type" then
        return MessageBox.Show("Error", "Invalid condition value association", MessageType.OK)
    elseif valueType == "Value" then
        if type == "string" then
            value = toString(value)
        elseif type == "number" then
            value = tonumber(value)

            if not value then
                return MessageBox.Show(
                    "Error",
                    "Your input does not match the type you selected",
                    MessageType.OK
                )
            end
        elseif type == "boolean" then
            if value == "true" then
                value = true
            elseif value == "false" then
                value = false
            else
                return MessageBox.Show(
                    "Error",
                    "Your input does not match the type you selected",
                    MessageType.OK
                )
            end
        else
            local success, result = pcall(loadstring("return " .. value))

            if valueType == "Value" then
                if not success then
                    return MessageBox.Show(
                        "Error",
                        "There was an error interpreting your input value",
                        MessageType.OK
                    )
                elseif typeof(result) ~= type then
                    return MessageBox.Show(
                        "Error",
                        "Your input does not match the type you selected",
                        MessageType.OK
                    )
                else
                    value = result
                end
            end
        end
    else
        value = type
    end

    local selectedRemote = selected.conditionLog.Remote
    local argIndex = tonumber(NewConditionIndex.Value.Input.Text)
    local byType = valueType == "Type"
    if not argIndex or argIndex < 1 or argIndex % 1 ~= 0 then
        return MessageBox.Show("Error", "Argument index must be a positive integer", MessageType.OK)
    end

    if status == "Block" then
        selectedRemote:BlockArg(argIndex, value, byType)
    else
        selectedRemote:IgnoreArg(argIndex, value, byType)
    end

    if byType then
        Condition.new(selectedRemote, status, argIndex, nil, value)
    else
        Condition.new(selectedRemote, status, argIndex, value)
    end

    newRemoteCondition:Hide()
    return nil
end)

NewConditionButtons.Cancel.MouseButton1Click:Connect(function()
    newRemoteCondition:Hide()
end)

NewConditionIndex.Add.MouseButton1Click:Connect(function()
    local newIndex = (tonumber(NewConditionIndex.Value.Input.Text) or 1) + 1
    NewConditionIndex.Value.Input.Text = newIndex
end)

NewConditionIndex.Sub.MouseButton1Click:Connect(function()
    local newIndex = (tonumber(NewConditionIndex.Value.Input.Text) or 1) - 1
    NewConditionIndex.Value.Input.Text = (newIndex <= 0 and 1) or newIndex
end)

NewConditionIndex.Value.Input.FocusLost:Connect(function()
    local newIndex = tonumber(NewConditionIndex.Value.Input.Text)

    if not newIndex or newIndex <= 0 then
        NewConditionIndex.Value.Input.Text = 1
    end
end)

pathContext:SetCallback(function()
    local selectedInstance = selected.logContext.Remote.Instance
    local oldStatus = oh.getStatus()

    if not setClipboard then
        return MessageBox.Show(
            "Clipboard unavailable",
            "Your executor does not expose setclipboard.",
            MessageType.OK
        )
    end

    oh.setStatus("Copying " .. selectedInstance.Name .. "'s path")
    setClipboard(getInstancePath(selectedInstance))
    task.wait(0.25)
    oh.setStatus(oldStatus)
    return nil
end)

pauseContext:SetCallback(function()
    local paused = Methods.SetPaused()
    pauseContext:SetText(paused and "Resume Capture" or "Pause Capture")
    oh.setStatus(paused and "RemoteSpy paused" or "RemoteSpy capturing")
end)

exportContext:SetCallback(function()
    if not setClipboard then
        return MessageBox.Show(
            "Clipboard unavailable",
            "Your executor does not expose setclipboard.",
            MessageType.OK
        )
    end

    setClipboard(Methods.Export(selected.logContext.Remote))
    oh.setStatus("Exported retained calls for " .. selected.logContext.Remote.Instance.Name)
    return nil
end)

conditionContext:SetCallback(function()
    selected.conditionLog = selected.logContext
    selected.conditionReturnToLogs = false

    createConditions(selected.conditionLog.Remote)
end)

clearContext:SetCallback(function()
    selected.logContext:Clear()
end)

ignoreContext:SetCallback(function()
    local selectedRemote = selected.logContext.Remote

    selected.logContext.Remote:Ignore()

    checkCurrentIgnored()

    if selectedRemote.Blocked then
        selected.logContext:PlayBlock()
    elseif selectedRemote.Ignored then
        selected.logContext:PlayIgnore()
    else
        selected.logContext:PlayNormal()
    end
end)

blockContext:SetCallback(function()
    local selectedRemote = selected.logContext.Remote

    selected.logContext.Remote:Block()

    checkCurrentBlocked()

    if selectedRemote.Blocked then
        selected.logContext:PlayBlock()
    elseif selectedRemote.Ignored then
        selected.logContext:PlayIgnore()
    else
        selected.logContext:PlayNormal()
    end
end)

removeContext:SetCallback(function()
    selected.logContext:Remove()
end)

pathContextSelected:SetCallback(function()
    if not setClipboard then
        return MessageBox.Show(
            "Clipboard unavailable",
            "Your executor does not expose setclipboard.",
            MessageType.OK
        )
    end

    local paths = ""

    for _i, log in pairs(selected.logs) do
        paths = paths .. getInstancePath(log.Remote.Instance) .. "\n"
    end

    setClipboard(paths)
    remoteList:DeselectAll()
    return nil
end)

ignoreContextSelected:SetCallback(function()
    for _i, log in pairs(selected.logs) do
        local remote = log.Remote

        remote:Ignore(true)

        if remote.Blocked then
            log:PlayBlock()
        elseif remote.Ignored then
            log:PlayIgnore()
        end
    end

    remoteList:DeselectAll()
end)

unignoreContextSelected:SetCallback(function()
    for _i, log in pairs(selected.logs) do
        local remote = log.Remote

        remote:Unignore()

        if remote.Blocked then
            log:PlayBlock()
        else
            log:PlayNormal()
        end
    end

    remoteList:DeselectAll()
end)

blockContextSelected:SetCallback(function()
    for _i, log in pairs(selected.logs) do
        local remote = log.Remote

        remote:Block(true)

        if remote.Blocked then
            log:PlayBlock()
        elseif remote.Ignored then
            log:PlayIgnore()
        end
    end

    remoteList:DeselectAll()
end)

unblockContextSelected:SetCallback(function()
    for _i, log in pairs(selected.logs) do
        local remote = log.Remote

        remote:Unblock()

        if remote.Ignored then
            log:PlayIgnore()
        else
            log:PlayNormal()
        end
    end

    remoteList:DeselectAll()
end)

clearContextSelected:SetCallback(function()
    for _i, log in pairs(selected.logs) do
        log:Clear()
    end

    remoteList:DeselectAll()
end)

removeContextSelected:SetCallback(function()
    local logs = table.clone(selected.logs)
    remoteList:DeselectAll()
    for _i, log in pairs(logs) do
        log:Remove()
    end

    remoteList:Recalculate()
end)

local function createIncomingReplaySource(remoteInstance, remotePath, call)
    local lines = {
        "local remote = " .. remotePath,
        "local args = table.pack(" .. serializeArgs(call.args) .. ")",
    }

    if remoteInstance.ClassName == "RemoteFunction" then
        table.insert(lines, 'local callback = getcallbackvalue(remote, "OnClientInvoke")')
        table.insert(lines, 'assert(type(callback) == "function", "No OnClientInvoke callback")')
        table.insert(lines, "return callback(table.unpack(args, 1, args.n))")
    else
        table.insert(lines, "for _, connection in next, getconnections(remote.OnClientEvent) do")
        table.insert(lines, "    if connection.Enabled ~= false then")
        table.insert(lines, "        connection:Fire(table.unpack(args, 1, args.n))")
        table.insert(lines, "    end")
        table.insert(lines, "end")
    end

    return table.concat(lines, "\n")
end

local function getIncomingReceivers(remoteInstance)
    if type(Methods.GetIncomingReceivers) ~= "function" then
        return {}, "This Hydroxide build cannot inspect client receivers."
    end

    return Methods.GetIncomingReceivers(remoteInstance)
end

local function getReceiverScriptPaths(receivers)
    local paths = {}
    local seen = {}

    for _, receiver in ipairs(receivers) do
        local source = receiver.Script
        if typeof(source) == "Instance" and not seen[source] then
            seen[source] = true
            table.insert(paths, getInstancePath(source))
        end
    end

    return paths
end

scriptContext:SetCallback(function()
    local script =
        "-- This script was generated by Hydroxide's RemoteSpy: https://github.com/tessa-says-hi/Hydroxide\n\n"
    local selectedRemote = selected.remoteLog.Remote.Instance
    local remotePath = getInstancePath(selectedRemote)
    local call = selected.call

    if not setClipboard then
        return MessageBox.Show(
            "Clipboard unavailable",
            "Your executor does not expose setclipboard.",
            MessageType.OK
        )
    elseif not call then
        return MessageBox.Show(
            "No call selected",
            "Select a call before generating a script.",
            MessageType.OK
        )
    end

    local oldStatus = oh.getStatus()
    local source

    if call.direction == "incoming" then
        source = createIncomingReplaySource(selectedRemote, remotePath, call)
        oh.setStatus("Generating local receiver replay ...")
    else
        source = remotePath .. ":" .. call.method .. "(" .. serializeArgs(call.args) .. ")"
        oh.setStatus("Generating RemoteSpy Pseudocode ...")
    end

    setClipboard(script .. source)
    task.wait(0.25)
    oh.setStatus(oldStatus)
    return nil
end)

callingScriptContext:SetCallback(function()
    if not setClipboard then
        return MessageBox.Show(
            "Clipboard unavailable",
            "Your executor does not expose setclipboard.",
            MessageType.OK
        )
    end

    local oldStatus = oh.getStatus()
    local call = selected.call

    if call and call.direction == "incoming" then
        local remoteInstance = selected.remoteLog.Remote.Instance
        local receivers, reason = getIncomingReceivers(remoteInstance)
        local paths = getReceiverScriptPaths(receivers)

        if #paths == 0 then
            return MessageBox.Show(
                "Receiver script unavailable",
                (reason or "No client receiver script could be resolved.")
                    .. "\n\nThe server-side calling script is not present on the client.",
                MessageType.OK
            )
        end

        oh.setStatus("Copying receiver script paths")
        setClipboard(table.concat(paths, "\n"))
        task.wait(0.25)
        oh.setStatus(oldStatus)
        return nil
    elseif not selected.callingScript then
        return MessageBox.Show(
            "Calling script unavailable",
            "The executor did not provide a calling script for this call.",
            MessageType.OK
        )
    end

    oh.setStatus("Copying " .. selected.callingScript.Name .. "'s path")
    setClipboard(getInstancePath(selected.callingScript))
    task.wait(0.25)
    oh.setStatus(oldStatus)
    return nil
end)

local SpyHook = ClosureSpy.Hook
spyClosureContext:SetCallback(function()
    local call = selected.call
    if call and call.direction == "incoming" then
        local remoteInstance = selected.remoteLog.Remote.Instance
        local receivers, reason = getIncomingReceivers(remoteInstance)
        local funcs = {}
        local seen = {}

        for _, receiver in ipairs(receivers) do
            local func = receiver.Function
            if type(func) == "function" and not seen[func] then
                seen[func] = true
                table.insert(funcs, func)
            end
        end

        if #funcs == 0 then
            return MessageBox.Show(
                "Receiver function unavailable",
                reason or "The executor did not expose any client receiver functions for this call.",
                MessageType.OK
            )
        end

        if TabSelector.SelectTab("ClosureSpy") then
            local hooked = 0
            local existing = 0
            local unavailable = 0

            for _, func in ipairs(funcs) do
                local result = SpyHook.new(Closure.new(func))
                if result == false then
                    existing += 1
                elseif result == nil then
                    unavailable += 1
                else
                    hooked += 1
                end
            end

            if hooked == 0 then
                local message
                if existing > 0 and unavailable > 0 then
                    message =
                        "Some receiver functions are already being spied; the rest expose no hookable upvalues."
                elseif existing > 0 then
                    message = "The receiver functions are already being spied."
                else
                    message = "The receiver functions cannot be hooked because they expose no upvalues."
                end
                MessageBox.Show("No new receiver hooks", message, MessageType.OK)
            else
                oh.setStatus("Spying " .. hooked .. " receiver function" .. (hooked == 1 and "" or "s"))
            end
        end
        return nil
    end

    if type(selected.func) ~= "function" then
        return MessageBox.Show(
            "Calling function unavailable",
            "The executor did not expose the calling function for this call.",
            MessageType.OK
        )
    end

    if TabSelector.SelectTab("ClosureSpy") then
        local selectedClosure = Closure.new(selected.func)
        local result = SpyHook.new(selectedClosure)

        if result == false then
            MessageBox.Show("Already hooked", "You are already spying " .. selectedClosure.Name)
        elseif result == nil then
            MessageBox.Show(
                "Cannot hook",
                ('Cannot hook "%s" because there are no upvalues'):format(selectedClosure.Name)
            )
        end
    end
    return nil
end)

repeatCallContext:SetCallback(function()
    local remoteInstance = selected.remoteLog.Remote.Instance
    local call = selected.call

    if not call then
        return MessageBox.Show("No call selected", "Select a call before repeating it.", MessageType.OK)
    end

    local oldStatus = oh.getStatus()
    local incoming = call.direction == "incoming"
    oh.setStatus((incoming and "Replaying " or "Recalling ") .. remoteInstance.Name)

    local ok, reason
    if incoming then
        if type(Methods.ReplayIncoming) == "function" then
            ok, reason = Methods.ReplayIncoming(remoteInstance, call.args)
        else
            ok, reason = false, "This Hydroxide build cannot replay client receivers."
        end
    else
        ok, reason = pcall(
            remoteInstance[call.method],
            remoteInstance,
            table.unpack(call.args, 1, call.args.n or #call.args)
        )
    end

    if not ok then
        MessageBox.Show(incoming and "Local replay failed" or "Call failed", tostring(reason), MessageType.OK)
    end

    task.wait(0.25)

    oh.setStatus(oldStatus)
    return nil
end)

viewAsHexContext:SetCallback(function()
    selected.callPodButton.hexViewEnabled = not selected.callPodButton.hexViewEnabled
    if not selected.callPodButton.oldStrings then
        selected.callPodButton.oldStrings = {}
    end

    for idx = 1, selected.args.n or #selected.args do
        local arg = selected.args[idx]
        if type(arg) == "string" then
            local textObject = selected.callPodButton.Instance.Contents[tostring(idx)].Label
            if selected.callPodButton.hexViewEnabled then
                selected.callPodButton.oldStrings[idx] = arg
                local hexString = ""
                for i = 1, #arg do
                    hexString = hexString .. string.format("%02X ", arg:byte(i, i))
                end
                textObject.Text = hexString
            else
                textObject.Text = dataToString(selected.callPodButton.oldStrings[idx])
            end
        end
    end
end)

removeConditionContext:SetCallback(function()
    selected.condition:Remove()
    selected.condition = nil
end)

removeConditionContextSelected:SetCallback(function()
    local conditions = table.clone(selected.conditions)
    remoteConditions:DeselectAll()
    for _i, condition in pairs(conditions) do
        condition:Remove()
    end
end)

conditionStatus:SetCallback(function(_dropdown, selected)
    local iconCondition = (selected.Name == "Ignore" and icons.ignore) or icons.block
    local icon = NewConditionContent.Status.Icon

    icon.Image = iconCondition
    icon.Border.Image = iconCondition
end)

conditionType:SetCallback(function(_dropdown, selected)
    local icon = NewConditionContent.Type.Icon
    local typeIcons = oh.Constants.Types
    local iconCondition = typeIcons[selected.Name] or typeIcons["userdata"]

    icon.Image = iconCondition
    icon.Border.Image = iconCondition
end)

conditionValueType:SetCallback(function(_dropdown, selected)
    local iconCondition = (selected.Name == "Type" and icons.type) or oh.Constants.Types["integral"]
    local icon = NewConditionContent.ValueType.Icon

    icon.Image = iconCondition
    icon.Border.Image = iconCondition
end)

local function addRemoteCall(remoteInstance, callInfo)
    if not removed[remoteInstance] then
        local remote = currentRemotes[remoteInstance]
        local retainedCall = remote and findRetainedCall(remote, callInfo)
        if retainedCall then
            local log = currentLogs[remoteInstance] or Log.new(remote)
            log:IncrementCalls(retainedCall)
        end
    end
end

Methods.ConnectEvent(function(remoteInstance, callInfo)
    addRemoteCall(remoteInstance, callInfo)
end)

for remoteInstance, remote in pairs(currentRemotes) do
    local newestCall = remote.Logs[#remote.Logs]
    if newestCall then
        addRemoteCall(remoteInstance, newestCall)
    end
end

remoteList:Recalculate()
updateRemoteStatus()

return RemoteSpy
