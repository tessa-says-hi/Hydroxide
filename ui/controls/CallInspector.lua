local TextService = game:GetService("TextService")

local SyntaxHighlighter = import("ui/controls/SyntaxHighlighter")
local CallInspector = {}

local colors = {
    accent = Color3.fromRGB(175, 35, 35),
    background = Color3.fromRGB(12, 12, 12),
    border = Color3.fromRGB(65, 65, 65),
    button = Color3.fromRGB(28, 28, 28),
    buttonHover = Color3.fromRGB(40, 40, 40),
    muted = Color3.fromRGB(135, 135, 135),
    panel = Color3.fromRGB(17, 17, 17),
    row = Color3.fromRGB(26, 26, 26),
    selected = Color3.fromRGB(42, 42, 42),
    text = Color3.fromRGB(220, 220, 220),
}

local function create(className, properties, parent)
    local instance = Instance.new(className)
    for name, value in pairs(properties) do
        instance[name] = value
    end
    instance.Parent = parent
    return instance
end

local function addCorner(parent, radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius or 3),
    }, parent)
end

local function addStroke(parent, color, thickness)
    return create("UIStroke", {
        Color = color or colors.border,
        Thickness = thickness or 1,
    }, parent)
end

local function createTab(parent, name, text, position, size)
    local button = create("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = colors.button,
        BorderSizePixel = 0,
        Font = Enum.Font.SourceSans,
        Name = name,
        Position = position,
        Size = size,
        Text = text,
        TextColor3 = colors.text,
        TextSize = 14,
        ZIndex = 84,
    }, parent)
    addCorner(button, 3)
    return button
end

local function createFooterButton(parent, name, text)
    local button = create("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = colors.button,
        BorderSizePixel = 0,
        Font = Enum.Font.SourceSans,
        Name = name,
        Size = UDim2.fromOffset(104, 25),
        Text = text,
        TextColor3 = colors.text,
        TextSize = 14,
        ZIndex = 84,
    }, parent)
    addCorner(button, 3)
    addStroke(button)
    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = colors.buttonHover
    end)
    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = colors.button
    end)
    return button
end

local function countLines(text)
    local lines = 0
    local maxWidth = 0
    for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        lines += 1
        local width = TextService:GetTextSize(line, 13, Enum.Font.Code, Vector2.new(100000, 20)).X
        maxWidth = math.max(maxWidth, width)
    end
    return math.max(lines, 1), maxWidth
end

local function updateTextCanvas(inspector)
    local text = inspector.RawText or inspector.TextBox.Text
    local lines, maxWidth = countLines(text)
    local viewport = inspector.TextContent.AbsoluteSize
    local width = math.max(viewport.X - 12, maxWidth + 14)
    local height = math.max(viewport.Y - 12, lines * 16 + 12)
    inspector.TextBox.Size = UDim2.fromOffset(width, height)
    inspector.Highlight.Size = inspector.TextBox.Size
    inspector.TextContent.CanvasSize = UDim2.fromOffset(width + 8, height + 8)
end

local function renderText(inspector, text, mode)
    text = tostring(text or "")
    inspector.RawText = text
    inspector.TextBox.Text = text

    local highlighter = mode == "FunctionInfo" and SyntaxHighlighter.highlightFunctionInfo
        or SyntaxHighlighter.highlight
    local ok, highlighted = pcall(highlighter, text)
    inspector.Highlight.Text = ok and highlighted or SyntaxHighlighter.escape(text)
    updateTextCanvas(inspector)
end

local function setSelectionMode(inspector, enabled)
    inspector.Highlight.Visible = not enabled
    inspector.TextBox.TextTransparency = enabled and 0 or 1
end

local function updateArgumentCanvas(inspector)
    inspector.Arguments.CanvasSize = UDim2.fromOffset(0, inspector.ArgumentLayout.AbsoluteContentSize.Y + 12)
end

local function clearArguments(inspector)
    for _, child in ipairs(inspector.Arguments:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end
end

local function renderArguments(inspector, arguments)
    clearArguments(inspector)

    if #arguments == 0 then
        create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Enum.Font.SourceSans,
            LayoutOrder = 1,
            Name = "Empty",
            Size = UDim2.new(1, -10, 0, 28),
            Text = "No arguments",
            TextColor3 = colors.muted,
            TextSize = 14,
            ZIndex = 84,
        }, inspector.Arguments)
        task.defer(updateArgumentCanvas, inspector)
        return
    end

    for order, argument in ipairs(arguments) do
        local row = create("Frame", {
            BackgroundColor3 = colors.row,
            BorderSizePixel = 0,
            LayoutOrder = order,
            Name = "Argument_" .. tostring(argument.Index),
            Size = UDim2.new(1, -10, 0, 23),
            ZIndex = 83,
        }, inspector.Arguments)
        addCorner(row, 2)

        create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Enum.Font.Code,
            Name = "Index",
            Position = UDim2.fromOffset(7, 0),
            Size = UDim2.fromOffset(27, 23),
            Text = tostring(argument.Index),
            TextColor3 = colors.muted,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 84,
        }, row)

        create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Enum.Font.Code,
            Name = "Value",
            Position = UDim2.fromOffset(34, 0),
            Size = UDim2.new(1, -112, 1, 0),
            Text = tostring(argument.Value),
            TextColor3 = argument.Color or colors.text,
            TextSize = 13,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 84,
        }, row)

        create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Enum.Font.SourceSans,
            Name = "Type",
            Position = UDim2.new(1, -76, 0, 0),
            Size = UDim2.fromOffset(68, 23),
            Text = tostring(argument.Type),
            TextColor3 = colors.muted,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 84,
        }, row)
    end

    task.defer(updateArgumentCanvas, inspector)
end

local function closeMenu(inspector)
    inspector.ActionMenu.Visible = false
    inspector.MenuGroup = nil
end

local function clearMenu(inspector)
    for _, child in ipairs(inspector.ActionMenu:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
end

local function showMenu(inspector, group, anchor)
    if inspector.MenuGroup == group and inspector.ActionMenu.Visible then
        closeMenu(inspector)
        return
    end

    clearMenu(inspector)
    local data = inspector.Data
    local actions = data and data.GetActions and data.GetActions(group, data) or {}
    if #actions == 0 then
        closeMenu(inspector)
        return
    end

    local width = 132
    for _, action in ipairs(actions) do
        local textWidth =
            TextService:GetTextSize(action.Text, 14, Enum.Font.SourceSans, Vector2.new(300, 20)).X
        width = math.max(width, math.min(205, textWidth + 42))
    end

    inspector.ActionMenu.Size = UDim2.fromOffset(width, #actions * 24 + 8)
    local scale = inspector.Window.AbsoluteSize.X / inspector.Window.Size.X.Offset
    local x = (anchor.AbsolutePosition.X + anchor.AbsoluteSize.X / 2 - inspector.Window.AbsolutePosition.X)
        / scale
    local y = (anchor.AbsolutePosition.Y - inspector.Window.AbsolutePosition.Y) / scale - 4
    inspector.ActionMenu.Position = UDim2.fromOffset(x, y)

    for order, action in ipairs(actions) do
        local item = create("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = colors.background,
            BorderSizePixel = 0,
            Font = Enum.Font.SourceSans,
            LayoutOrder = order,
            Name = action.Id,
            Size = UDim2.new(1, -8, 0, 24),
            Text = "",
            ZIndex = 93,
        }, inspector.ActionMenu)
        addCorner(item, 2)

        create("ImageLabel", {
            BackgroundTransparency = 1,
            Image = action.Icon or "",
            Name = "Icon",
            Position = UDim2.fromOffset(6, 5),
            Size = UDim2.fromOffset(14, 14),
            ZIndex = 94,
        }, item)

        create("TextLabel", {
            BackgroundTransparency = 1,
            Font = Enum.Font.SourceSans,
            Name = "Label",
            Position = UDim2.fromOffset(26, 0),
            Size = UDim2.new(1, -31, 1, 0),
            Text = action.Text,
            TextColor3 = colors.text,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 94,
        }, item)

        item.MouseEnter:Connect(function()
            item.BackgroundColor3 = colors.buttonHover
        end)
        item.MouseLeave:Connect(function()
            item.BackgroundColor3 = colors.background
        end)
        item.MouseButton1Click:Connect(function()
            closeMenu(inspector)
            local current = inspector.Data
            if current and current.OnAction then
                current.OnAction(action.Id, inspector, current)
            end
        end)
    end

    inspector.MenuGroup = group
    inspector.ActionMenu.Visible = true
end

function CallInspector.new(parent)
    local inspector = {}
    local overlay = create("TextButton", {
        Active = true,
        AutoButtonColor = false,
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Name = "CallInspector",
        Size = UDim2.fromScale(1, 1),
        Text = "",
        Visible = false,
        ZIndex = 80,
    }, parent)

    local window = create("Frame", {
        Active = true,
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = colors.background,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        Name = "Window",
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(460, 306),
        ZIndex = 81,
    }, overlay)
    addCorner(window, 4)
    addStroke(window, colors.accent, 1)

    local header = create("Frame", {
        BackgroundColor3 = Color3.fromRGB(20, 20, 20),
        BorderSizePixel = 0,
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 31),
        ZIndex = 82,
    }, window)
    addCorner(header, 4)

    local remoteIcon = create("ImageLabel", {
        BackgroundTransparency = 1,
        Name = "Icon",
        Position = UDim2.fromOffset(10, 8),
        Size = UDim2.fromOffset(15, 15),
        ZIndex = 84,
    }, header)

    local title = create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.SourceSans,
        Name = "Title",
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -64, 1, 0),
        Text = "Remote call",
        TextColor3 = colors.text,
        TextSize = 15,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 84,
    }, header)

    local close = create("TextButton", {
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        Font = Enum.Font.SourceSans,
        Name = "Close",
        Position = UDim2.new(1, -31, 0, 0),
        Size = UDim2.fromOffset(31, 31),
        Text = "x",
        TextColor3 = colors.muted,
        TextSize = 18,
        ZIndex = 85,
    }, header)

    local tabs = create("Frame", {
        BackgroundTransparency = 1,
        Name = "Tabs",
        Position = UDim2.fromOffset(8, 36),
        Size = UDim2.new(1, -16, 0, 26),
        ZIndex = 83,
    }, window)
    local argumentTab =
        createTab(tabs, "Arguments", "...  Arguments", UDim2.fromOffset(0, 0), UDim2.new(0.34, -2, 1, 0))
    local codeTab = createTab(tabs, "Code", "<>  Code", UDim2.new(0.34, 1, 0, 0), UDim2.new(0.26, -2, 1, 0))
    local functionTab = createTab(
        tabs,
        "FunctionInfo",
        "()  Function Info",
        UDim2.new(0.6, 2, 0, 0),
        UDim2.new(0.4, -2, 1, 0)
    )

    local arguments = create("ScrollingFrame", {
        Active = true,
        BackgroundColor3 = colors.panel,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        Name = "Arguments",
        Position = UDim2.fromOffset(8, 67),
        ScrollBarImageColor3 = colors.border,
        ScrollBarThickness = 4,
        Size = UDim2.new(1, -16, 0, 196),
        ZIndex = 82,
    }, window)
    addCorner(arguments, 3)
    addStroke(arguments, Color3.fromRGB(35, 35, 35), 1)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 5),
        PaddingTop = UDim.new(0, 5),
    }, arguments)
    local argumentLayout = create("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, arguments)

    local textContent = create("ScrollingFrame", {
        Active = true,
        BackgroundColor3 = colors.panel,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        Name = "TextContent",
        Position = arguments.Position,
        ScrollBarImageColor3 = colors.border,
        ScrollBarThickness = 5,
        ScrollingDirection = Enum.ScrollingDirection.XY,
        Size = arguments.Size,
        Visible = false,
        ZIndex = 82,
    }, window)
    addCorner(textContent, 3)
    addStroke(textContent, Color3.fromRGB(35, 35, 35), 1)

    local highlight = create("TextLabel", {
        BackgroundTransparency = 1,
        Font = Enum.Font.Code,
        Name = "Highlight",
        Position = UDim2.fromOffset(6, 6),
        RichText = true,
        Size = UDim2.new(1, -12, 1, -12),
        Text = "",
        TextColor3 = colors.text,
        TextSize = 13,
        TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 83,
    }, textContent)

    local textBox = create("TextBox", {
        BackgroundTransparency = 1,
        ClearTextOnFocus = false,
        Font = Enum.Font.Code,
        MultiLine = true,
        Name = "Text",
        Position = UDim2.fromOffset(6, 6),
        Size = UDim2.new(1, -12, 1, -12),
        Text = "",
        TextColor3 = colors.text,
        TextEditable = false,
        TextSize = 13,
        TextTransparency = 1,
        TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 84,
    }, textContent)

    local footer = create("Frame", {
        BackgroundTransparency = 1,
        Name = "Footer",
        Position = UDim2.fromOffset(8, 270),
        Size = UDim2.new(1, -16, 0, 28),
        ZIndex = 83,
    }, window)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
    }, footer)
    local codeButton = createFooterButton(footer, "Code", "<>  Code")
    codeButton.LayoutOrder = 1
    local originButton = createFooterButton(footer, "Origin", "[]  Origin")
    originButton.LayoutOrder = 2
    local eventButton = createFooterButton(footer, "Event", "o-o  Event")
    eventButton.LayoutOrder = 3

    local actionMenu = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor3 = colors.background,
        BorderSizePixel = 0,
        Name = "ActionMenu",
        Size = UDim2.fromOffset(140, 32),
        Visible = false,
        ZIndex = 91,
    }, window)
    addCorner(actionMenu, 3)
    addStroke(actionMenu, colors.border, 1)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 4),
        PaddingTop = UDim.new(0, 4),
    }, actionMenu)
    create("UIListLayout", {
        Padding = UDim.new(0, 0),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, actionMenu)

    inspector.ActionMenu = actionMenu
    inspector.ArgumentLayout = argumentLayout
    inspector.Arguments = arguments
    inspector.CloseMenu = closeMenu
    inspector.Data = nil
    inspector.GetData = CallInspector.getData
    inspector.Hide = CallInspector.hide
    inspector.Highlight = highlight
    inspector.Instance = overlay
    inspector.IsVisible = CallInspector.isVisible
    inspector.RemoteIcon = remoteIcon
    inspector.SelectTab = CallInspector.selectTab
    inspector.SetCode = CallInspector.setCode
    inspector.SetFunctionInfo = CallInspector.setFunctionInfo
    inspector.Show = CallInspector.show
    inspector.Tabs = {
        Arguments = argumentTab,
        Code = codeTab,
        FunctionInfo = functionTab,
    }
    inspector.TextBox = textBox
    inspector.TextContent = textContent
    inspector.Title = title
    inspector.Window = window

    argumentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        updateArgumentCanvas(inspector)
    end)
    textContent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        updateTextCanvas(inspector)
    end)
    textBox.Focused:Connect(function()
        setSelectionMode(inspector, true)
    end)
    textBox.FocusLost:Connect(function()
        setSelectionMode(inspector, false)
    end)

    argumentTab.MouseButton1Click:Connect(function()
        inspector:SelectTab("Arguments")
    end)
    codeTab.MouseButton1Click:Connect(function()
        inspector:SelectTab("Code")
    end)
    functionTab.MouseButton1Click:Connect(function()
        inspector:SelectTab("FunctionInfo")
    end)
    codeButton.MouseButton1Click:Connect(function()
        showMenu(inspector, "Code", codeButton)
    end)
    originButton.MouseButton1Click:Connect(function()
        showMenu(inspector, "Origin", originButton)
    end)
    eventButton.MouseButton1Click:Connect(function()
        showMenu(inspector, "Event", eventButton)
    end)
    close.MouseButton1Click:Connect(function()
        inspector:Hide()
    end)

    return inspector
end

function CallInspector.selectTab(inspector, name)
    if not inspector.Tabs[name] then
        return
    end

    inspector.ActiveTab = name
    if inspector.TextBox:IsFocused() then
        inspector.TextBox:ReleaseFocus()
    end
    setSelectionMode(inspector, false)
    inspector.Arguments.Visible = name == "Arguments"
    inspector.TextContent.Visible = name ~= "Arguments"
    for tabName, tab in pairs(inspector.Tabs) do
        tab.BackgroundColor3 = tabName == name and colors.selected or colors.button
    end

    if name ~= "Arguments" then
        local data = inspector.Data or {}
        renderText(
            inspector,
            name == "Code" and (data.Code or "Code unavailable")
                or (data.FunctionInfo or "Function information unavailable"),
            name
        )
    end

    closeMenu(inspector)
end

function CallInspector.setCode(inspector, source, selectTab)
    if inspector.Data then
        inspector.Data.Code = tostring(source or "")
    end
    if selectTab ~= false then
        inspector:SelectTab("Code")
    elseif inspector.ActiveTab == "Code" then
        renderText(inspector, source, "Code")
    end
end

function CallInspector.setFunctionInfo(inspector, information, selectTab)
    if inspector.Data then
        inspector.Data.FunctionInfo = tostring(information or "")
    end
    if selectTab ~= false then
        inspector:SelectTab("FunctionInfo")
    elseif inspector.ActiveTab == "FunctionInfo" then
        renderText(inspector, information, "FunctionInfo")
    end
end

function CallInspector.show(inspector, data)
    inspector.Data = data
    inspector.Title.Text = tostring(data.Title or "Remote call")
    inspector.RemoteIcon.Image = data.Icon or ""
    setSelectionMode(inspector, false)
    renderArguments(inspector, data.Arguments or {})
    inspector.Instance.Visible = true
    inspector:SelectTab(data.InitialTab or "Arguments")
end

function CallInspector.hide(inspector)
    closeMenu(inspector)
    if inspector.TextBox:IsFocused() then
        inspector.TextBox:ReleaseFocus()
    end
    setSelectionMode(inspector, false)
    inspector.Instance.Visible = false
    inspector.Data = nil
end

function CallInspector.isVisible(inspector)
    return inspector.Instance.Visible
end

function CallInspector.getData(inspector)
    return inspector.Data
end

return CallInspector
