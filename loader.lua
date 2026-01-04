-- [[ KEY SYSTEM DATA ]] --
local keyData = {
    {102, 117, 110, 107, 121, 108, 111, 120, 105, 108, 117, 115, 101, 114},
    {100, 101, 118, 115, 99, 114, 105, 112, 116, 50, 50, 50, 50, 50}
}

local function getValidKeys()
    local keys = {}
    for _, keyArray in ipairs(keyData) do
        local key = ""
        for _, byte in ipairs(keyArray) do
            key = key .. string.char(byte)
        end
        table.insert(keys, key)
    end
    return keys
end

local validKeys = getValidKeys()
local maxAttempts = 3
local currentAttempts = 0

-- [[ MAIN SCRIPT LOADER ]] --
function loadMainScript()
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
    
    -- Services
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    local RunService = game:GetService("RunService")
    local Camera = workspace.CurrentCamera

    local Options = Library.Options
    local Toggles = Library.Toggles

    Library.ForceCheckbox = false
    Library.ShowToggleFrameInKeybinds = true

    local Window = Library:CreateWindow({
        Title = "Desync",
        Footer = "Desync",
        Icon = 6031302934,
        NotifySide = "Right",
        ShowCustomCursor = true,
    })

    local Tabs = {
        Main = Window:AddTab("Main", "user"),
        ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
    }

    -- [[ DESYNC SETTINGS ]] --
    local isFrozen = false
    local frozenTick = 0
    local workingOffset = 4 -- SEQUENCE ID (FIX)

    -- [[ VISUALS: HIGHLIGHTS ]] --
    local desyncGhostModel = nil
    local serverHighlight = nil
    local ghostNoclipLoop = nil -- Переменная для цикла ноклипа

    -- Создаем красивый текст над головой
    local function addLabel(parent, color, text)
        local head = parent:FindFirstChild("Head")
        if not head then return end
        
        if head:FindFirstChild("DesyncLabel") then head.DesyncLabel:Destroy() end

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "DesyncLabel"
        billboard.Adornee = head
        billboard.Size = UDim2.new(0, 150, 0, 40)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = head

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.Text = text
        label.TextColor3 = color
        label.TextStrokeTransparency = 0.2
        label.TextStrokeColor3 = Color3.new(0,0,0)
        label.Font = Enum.Font.GothamBlack
        label.TextSize = 13
        label.Parent = billboard
    end

    -- Создаем копию персонажа (Призрак)
    local function createDesyncGhost()
        local char = LocalPlayer.Character
        if not char then return end

        char.Archivable = true
        local ghost = char:Clone()
        ghost.Name = "DesyncGhost"
        ghost.Parent = Camera

        -- 1. Удаляем скрипты и лишнее
        for _, v in pairs(ghost:GetDescendants()) do
            if v:IsA("Script") or v:IsA("LocalScript") or v:IsA("Sound") or v:IsA("JointInstance") then
                v:Destroy()
            end
        end

        -- 2. Настраиваем визуал (Голограмма)
        for _, v in pairs(ghost:GetDescendants()) do
            if v:IsA("BasePart") then
                v.Anchored = true -- Фиксируем намертво
                v.Material = Enum.Material.ForceField
                v.Color = Color3.fromRGB(0, 255, 255)
                v.Transparency = 0.5
                v.Massless = true
            elseif v:IsA("Humanoid") then
                v.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            end
        end

        -- 3. ВКЛЮЧАЕМ NOCLIP LOOP (Решение проблемы с коллизией)
        -- Гуманоид пытается вернуть коллизию каждый кадр, поэтому мы выключаем её каждый кадр.
        if ghostNoclipLoop then ghostNoclipLoop:Disconnect() end
        
        ghostNoclipLoop = RunService.Stepped:Connect(function()
            if not ghost or not ghost.Parent then
                if ghostNoclipLoop then ghostNoclipLoop:Disconnect() end
                return
            end
            
            for _, v in pairs(ghost:GetDescendants()) do
                if v:IsA("BasePart") then
                    v.CanCollide = false
                    v.CanTouch = false
                    v.CanQuery = false
                end
            end
        end)

        -- Добавляем подсветку (Highlight)
        local hl = Instance.new("Highlight")
        hl.Adornee = ghost
        hl.FillColor = Color3.fromRGB(0, 255, 255)
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.6
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = ghost

        addLabel(ghost, Color3.fromRGB(0, 255, 255), "DESYNC POSITION")

        return ghost
    end

    -- Обновляем визуалы на реальном игроке
    local function updateServerVisuals()
        local char = LocalPlayer.Character
        if not char then return end
        
        if not serverHighlight or serverHighlight.Parent ~= char then
            if serverHighlight then serverHighlight:Destroy() end
            
            serverHighlight = Instance.new("Highlight")
            serverHighlight.Name = "ServerPosHighlight"
            serverHighlight.Adornee = char
            serverHighlight.FillColor = Color3.fromRGB(255, 100, 0)
            serverHighlight.OutlineColor = Color3.fromRGB(255, 255, 0)
            serverHighlight.FillTransparency = 1
            serverHighlight.OutlineTransparency = 0
            serverHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            serverHighlight.Parent = char
            
            addLabel(char, Color3.fromRGB(255, 120, 0), "SERVER POSITION")
        end
    end

    -- Хук на RenderStepped
    local visualConnection = RunService.RenderStepped:Connect(function()
        if isFrozen then
            updateServerVisuals()
        else
            -- Очистка при выключении
            if ghostNoclipLoop then 
                ghostNoclipLoop:Disconnect() 
                ghostNoclipLoop = nil 
            end
            if desyncGhostModel then 
                desyncGhostModel:Destroy() 
                desyncGhostModel = nil 
            end
            if serverHighlight then
                serverHighlight:Destroy()
                serverHighlight = nil
            end
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head") and LocalPlayer.Character.Head:FindFirstChild("DesyncLabel") then
                LocalPlayer.Character.Head.DesyncLabel:Destroy()
            end
        end
    end)

    local function setupDesyncHook()
        raknet.add_send_hook(function(packetData)
            local packetid = buffer.readu8(packetData, 0)
            
            if packetid == 0x1B then
                if buffer.len(packetData) >= workingOffset + 4 then
                    if isFrozen then
                        buffer.writeu32(packetData, workingOffset, frozenTick)
                    else
                        frozenTick = buffer.readu32(packetData, workingOffset)
                    end
                end
            end
            
            return true
        end)
    end

    local LeftGroupBox = Tabs.Main:AddLeftGroupbox("Desync Controls")

    LeftGroupBox:AddToggle("DesyncToggle", {
        Text = "Enable Desync",
        Tooltip = "Freezes Sequence ID (Offset 4)",
        Default = false,
        Callback = function(Value)
            isFrozen = Value
            
            if isFrozen then
                if desyncGhostModel then desyncGhostModel:Destroy() end
                desyncGhostModel = createDesyncGhost()
            end
        end,
    })

    LeftGroupBox:AddLabel("Keybind"):AddKeyPicker("DesyncKeybind", {
        Default = "None",
        SyncToggleState = false,
        Mode = "Toggle",
        Text = "Desync Keybind",
        NoUI = false,
        Callback = function(Value)
            if Options.DesyncKeybind.Mode == "Toggle" then
                isFrozen = Value
                Toggles.DesyncToggle:SetValue(Value)
            end
        end,
    })

    -- Логика HOLD режима
    task.spawn(function()
        while true do
            wait()
            if Options.DesyncKeybind.Mode == "Hold" then
                local state = Options.DesyncKeybind:GetState()
                if state ~= isFrozen then
                    isFrozen = state
                    Toggles.DesyncToggle:SetValue(state)
                end
            end
            if Library.Unloaded then break end
        end
    end)

    local statusLabel = LeftGroupBox:AddLabel("Status: Active")

    task.spawn(function()
        while true do
            wait(0.2)
            if isFrozen then
                statusLabel:SetText("Status: Frozen")
                statusLabel.TextColor3 = Color3.fromRGB(0, 255, 255)
            else
                statusLabel:SetText("Status: Active")
                statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
            end
        end
    end)

    setupDesyncHook()

    -- [[ UI SETTINGS ]] --
    local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")
    MenuGroup:AddToggle("KeybindMenuOpen", { Default = Library.KeybindFrame.Visible, Text = "Open Keybind Menu", Callback = function(value) Library.KeybindFrame.Visible = value end })
    MenuGroup:AddToggle("ShowCustomCursor", { Text = "Custom Cursor", Default = true, Callback = function(Value) Library.ShowCustomCursor = Value end })
    MenuGroup:AddDropdown("NotificationSide", { Values = { "Left", "Right" }, Default = "Right", Text = "Notification Side", Callback = function(Value) Library:SetNotifySide(Value) end })
    MenuGroup:AddDropdown("DPIDropdown", { Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" }, Default = "100%", Text = "DPI Scale", Callback = function(Value) Value = Value:gsub("%%", ""); local DPI = tonumber(Value); Library:SetDPIScale(DPI) end })
    MenuGroup:AddDivider()
    MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
    MenuGroup:AddButton("Unload", function() Library:Unload() end)

    Library.ToggleKeybind = Options.MenuKeybind
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
    ThemeManager:SetFolder("LoveHub")
    SaveManager:SetFolder("LoveHub/desync_final_v3")
    SaveManager:BuildConfigSection(Tabs["UI Settings"])
    ThemeManager:ApplyToTab(Tabs["UI Settings"])
    SaveManager:LoadAutoloadConfig()

    Library:OnUnload(function()
        if visualConnection then visualConnection:Disconnect() end
        if ghostNoclipLoop then ghostNoclipLoop:Disconnect() end
        if desyncGhostModel then desyncGhostModel:Destroy() end
        if serverHighlight then serverHighlight:Destroy() end
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head") and LocalPlayer.Character.Head:FindFirstChild("DesyncLabel") then
            LocalPlayer.Character.Head.DesyncLabel:Destroy()
        end
        raknet.clear_all_send_hooks()
    end)
end

-- [[ KEY AUTHENTICATION LOGIC ]] --
local function checkExistingKey()
    local success, savedKey = pcall(function() return readfile("lovehub_key.txt") end)
    if success and savedKey then
        for _, validKey in pairs(validKeys) do
            if savedKey:lower() == validKey:lower() then return true end
        end
        pcall(function() delfile("lovehub_key.txt") end)
    end
    return false
end

local function checkKey(inputKey)
    currentAttempts = currentAttempts + 1
    local attemptsLeft = maxAttempts - currentAttempts
    local isValid = false
    for _, validKey in pairs(validKeys) do
        if inputKey:lower() == validKey:lower() then
            isValid = true
            break
        end
    end
    if isValid then
        pcall(function() writefile("lovehub_key.txt", inputKey:lower()) end)
    end
    return isValid, attemptsLeft
end

if getgenv().LoveHubKey then
    local isValid = false
    for _, validKey in pairs(validKeys) do
        if getgenv().LoveHubKey:lower() == validKey:lower() then
            isValid = true
            break
        end
    end
    if isValid then
        pcall(function() writefile("lovehub_key.txt", getgenv().LoveHubKey:lower()) end)
        loadMainScript()
        return
    end
end

if checkExistingKey() then
    loadMainScript()
    return
end

-- [[ GUI CREATION ]] --
local keyGui = Instance.new("ScreenGui")
keyGui.Name = "LoveHubKeySystem"
keyGui.Parent = game:GetService("CoreGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 400, 0, 250)
frame.Position = UDim2.new(0.5, -200, 0.5, -125)
frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
frame.BorderSizePixel = 0
frame.Parent = keyGui
local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 50)
title.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
title.Text = "LoveHub Key System"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.Parent = frame
local titleCorner = Instance.new("UICorner"); titleCorner.CornerRadius = UDim.new(0, 12); titleCorner.Parent = title

local attemptsLabel = Instance.new("TextLabel")
attemptsLabel.Size = UDim2.new(1, 0, 0, 20)
attemptsLabel.Position = UDim2.new(0, 0, 0.2, 0)
attemptsLabel.BackgroundTransparency = 1
attemptsLabel.Text = "Attempts: " .. currentAttempts .. "/" .. maxAttempts
attemptsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
attemptsLabel.Font = Enum.Font.Gotham
attemptsLabel.TextSize = 14
attemptsLabel.Parent = frame

local inputBox = Instance.new("TextBox")
inputBox.Size = UDim2.new(0.8, 0, 0, 40)
inputBox.Position = UDim2.new(0.1, 0, 0.35, 0)
inputBox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
inputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
inputBox.PlaceholderText = "Enter your key..."
inputBox.Text = ""
inputBox.Font = Enum.Font.Gotham
inputBox.TextSize = 16
inputBox.Parent = frame
local inputCorner = Instance.new("UICorner"); inputCorner.CornerRadius = UDim.new(0, 8); inputCorner.Parent = inputBox

local submitButton = Instance.new("TextButton")
submitButton.Size = UDim2.new(0.8, 0, 0, 40)
submitButton.Position = UDim2.new(0.1, 0, 0.6, 0)
submitButton.BackgroundColor3 = Color3.fromRGB(80, 80, 255)
submitButton.Text = "Submit Key"
submitButton.TextColor3 = Color3.fromRGB(255, 255, 255)
submitButton.Font = Enum.Font.GothamBold
submitButton.TextSize = 16
submitButton.Parent = frame
local buttonCorner = Instance.new("UICorner"); buttonCorner.CornerRadius = UDim.new(0, 8); buttonCorner.Parent = submitButton

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0.8, 0, 0, 30)
statusLabel.Position = UDim2.new(0.1, 0, 0.85, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 14
statusLabel.TextWrapped = true
statusLabel.Parent = frame

local function updateUI()
    attemptsLabel.Text = "Attempts: " .. currentAttempts .. "/" .. maxAttempts
    if currentAttempts >= maxAttempts then
        submitButton.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
        submitButton.Text = "No Attempts Left"
        submitButton.Active = false
    end
end

submitButton.MouseButton1Click:Connect(function()
    if currentAttempts >= maxAttempts then
        statusLabel.Text = "No attempts left. Please restart."
        statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        return
    end
    local key = inputBox.Text
    if key == "" then
        statusLabel.Text = "Please enter a key"
        statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        return
    end
    local isValid, attemptsLeft = checkKey(key)
    if isValid then
        statusLabel.Text = "Key accepted! Loading..."
        statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        submitButton.Active = false
        wait(1.5)
        keyGui:Destroy()
        loadMainScript()
    else
        if attemptsLeft > 0 then
            statusLabel.Text = "Invalid key. " .. attemptsLeft .. " attempts left"
            statusLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
        else
            statusLabel.Text = "No attempts left. Please restart the script."
            statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        end
        inputBox.Text = ""
    end
    updateUI()
end)

inputBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then submitButton.MouseButton1Click:Wait() end
end)

updateUI()
