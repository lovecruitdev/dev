-- [[ CONFIGURATION ]] --
local serverUrl = "http://192.168.0.111:5000/verify" -- ТВОЙ IP
local scriptName = "LoveHub_Final_HWID"

-- [[ SERVICES ]] --
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local CoreGui = game:GetService("CoreGui")

-- [[ UTILS ]] --
local function getExecutorHWID()
    if gethwid then
        return gethwid()
    else
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end
end

-- [[ MAIN SCRIPT ]] --
function loadMainScript()
    -- ЗАГРУЗКА LINORIA LIB
    local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'
    local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
    local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
    local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

    local Window = Library:CreateWindow({
        Title = 'LoveHub | Final Release',
        Center = true,
        AutoShow = true,
        TabPadding = 8,
        MenuFadeTime = 0.2
    })

    local Tabs = {
        Main = Window:AddTab('Main'),
        Visuals = Window:AddTab('Visuals'),
        Settings = Window:AddTab('Settings'),
    }

    -- ==================================================================
    -- [[ 1. DESYNC SYSTEM ]] --
    -- ==================================================================
    local DesyncState = {
        Enabled = false,
        VisualizeLocal = true,  
        VisualizeServer = true, 
        FrozenTick = 0
    }
    
    local workingOffset = 4 
    local desyncGhostModel = nil
    local serverHighlight = nil
    local ghostNoclipLoop = nil

    local function addLabel(parent, color, text)
        local head = parent:FindFirstChild("Head")
        if not head then return end
        if head:FindFirstChild("DesyncLabel") then head.DesyncLabel:Destroy() end
        local billboard = Instance.new("BillboardGui"); billboard.Name = "DesyncLabel"; billboard.Adornee = head; billboard.Size = UDim2.new(0, 150, 0, 40); billboard.StudsOffset = Vector3.new(0, 3, 0); billboard.AlwaysOnTop = true; billboard.Parent = head
        local label = Instance.new("TextLabel"); label.BackgroundTransparency = 1; label.Size = UDim2.new(1, 0, 1, 0); label.Text = text; label.TextColor3 = color; label.TextStrokeTransparency = 0.2; label.TextStrokeColor3 = Color3.new(0,0,0); label.Font = Enum.Font.GothamBlack; label.TextSize = 13; label.Parent = billboard
    end

    local function createDesyncGhost()
        local char = LocalPlayer.Character; if not char then return end; char.Archivable = true; local ghost = char:Clone(); ghost.Name = "DesyncGhost"; ghost.Parent = Camera
        for _, v in pairs(ghost:GetDescendants()) do if v:IsA("Script") or v:IsA("LocalScript") or v:IsA("Sound") or v:IsA("JointInstance") then v:Destroy() end end
        for _, v in pairs(ghost:GetDescendants()) do if v:IsA("BasePart") then v.Anchored = true; v.Material = Enum.Material.ForceField; v.Color = Color3.fromRGB(0, 255, 255); v.Transparency = 0.5; v.Massless = true elseif v:IsA("Humanoid") then v.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end end
        if ghostNoclipLoop then ghostNoclipLoop:Disconnect() end
        ghostNoclipLoop = RunService.Stepped:Connect(function() if not ghost or not ghost.Parent then if ghostNoclipLoop then ghostNoclipLoop:Disconnect() end return end for _, v in pairs(ghost:GetDescendants()) do if v:IsA("BasePart") then v.CanCollide = false; v.CanTouch = false; v.CanQuery = false end end end)
        local hl = Instance.new("Highlight"); hl.Adornee = ghost; hl.FillColor = Color3.fromRGB(0, 255, 255); hl.OutlineColor = Color3.fromRGB(255, 255, 255); hl.FillTransparency = 0.6; hl.OutlineTransparency = 0; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent = ghost
        addLabel(ghost, Color3.fromRGB(0, 255, 255), "DESYNC POSITION"); return ghost
    end

    local function updateServerVisuals()
        local char = LocalPlayer.Character; if not char then return end
        if not serverHighlight or serverHighlight.Parent ~= char then if serverHighlight then serverHighlight:Destroy() end serverHighlight = Instance.new("Highlight"); serverHighlight.Name = "ServerPosHighlight"; serverHighlight.Adornee = char; serverHighlight.FillColor = Color3.fromRGB(255, 100, 0); serverHighlight.OutlineColor = Color3.fromRGB(255, 255, 0); serverHighlight.FillTransparency = 1; serverHighlight.OutlineTransparency = 0; serverHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; serverHighlight.Parent = char; addLabel(char, Color3.fromRGB(255, 120, 0), "SERVER POSITION") end
    end

    RunService.RenderStepped:Connect(function()
        if DesyncState.Enabled then
            if not desyncGhostModel then desyncGhostModel = createDesyncGhost() end
            updateServerVisuals()
        else
            if ghostNoclipLoop then ghostNoclipLoop:Disconnect(); ghostNoclipLoop = nil end
            if desyncGhostModel then desyncGhostModel:Destroy(); desyncGhostModel = nil end
            if serverHighlight then serverHighlight:Destroy(); serverHighlight = nil end
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head") and LocalPlayer.Character.Head:FindFirstChild("DesyncLabel") then LocalPlayer.Character.Head.DesyncLabel:Destroy() end
        end
    end)

    if raknet then
        raknet.add_send_hook(function(packetData)
            local packetid = buffer.readu8(packetData, 0)
            if packetid == 0x1B and buffer.len(packetData) >= workingOffset + 4 then
                if DesyncState.Enabled then buffer.writeu32(packetData, workingOffset, DesyncState.FrozenTick) else DesyncState.FrozenTick = buffer.readu32(packetData, workingOffset) end
            end
            return true
        end)
    else 
        Library:Notify("RakNet not found! Desync will not work.", 10) 
    end

    -- ==================================================================
    -- [[ 2. ADVANCED VISUALS ]] --
    -- ==================================================================
    local ESP_Config = {
        Enabled = false,
        Box3D = false, BoxColor = Color3.fromRGB(255, 0, 0),
        Tracers = false, TracerColor = Color3.fromRGB(255, 0, 0), TracerLength = 2.1,
        Skeletons = false, SkeletonColor = Color3.fromRGB(255, 255, 255),
        Chams = false, ChamsFill = Color3.fromRGB(255, 0, 0), ChamsOutline = Color3.fromRGB(255, 255, 255),
        Names = false, NameColor = Color3.fromRGB(255, 255, 255), NameFont = Enum.Font.GothamBlack, NameSize = 14
    }

    local ESP_Cache = {}
    local FontsTable = { ["Gotham Black"] = Enum.Font.GothamBlack, ["Gotham Bold"] = Enum.Font.GothamBold, ["Luckiest Guy"] = Enum.Font.LuckiestGuy, ["Fredoka One"] = Enum.Font.FredokaOne, ["Bangers"] = Enum.Font.Bangers, ["Creepster"] = Enum.Font.Creepster, ["Amatic SC"] = Enum.Font.AmaticSC, ["Cartoon"] = Enum.Font.Cartoon, ["Arcade"] = Enum.Font.Arcade, ["SciFi"] = Enum.Font.SciFi, ["Fantasy"] = Enum.Font.Fantasy, ["Michroma"] = Enum.Font.Michroma, ["Sarpanch"] = Enum.Font.Sarpanch, ["Code"] = Enum.Font.Code, ["SourceSansBold"] = Enum.Font.SourceSansBold }
    local FontKeys = {}; for k, v in pairs(FontsTable) do table.insert(FontKeys, k) end; table.sort(FontKeys)
    local SkeletonJoints = {{"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"}, {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"}, {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"}, {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"}, {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}}
    local function NewLine() local l = Drawing.new("Line"); l.Visible = false; l.Thickness = 1; l.Transparency = 1; l.Color = Color3.new(1,1,1); return l end

    local function ClearESP(plr)
        if ESP_Cache[plr] then
            for _, l in pairs(ESP_Cache[plr].BoxLines) do l:Remove() end
            for _, l in pairs(ESP_Cache[plr].SkeletonLines) do l:Remove() end
            if ESP_Cache[plr].Tracer then ESP_Cache[plr].Tracer:Remove() end
            if ESP_Cache[plr].NameTag then ESP_Cache[plr].NameTag:Destroy() end
            if plr.Character and plr.Character:FindFirstChild("LoveHubChams") then plr.Character.LoveHubChams:Destroy() end
            ESP_Cache[plr] = nil
        end
    end

    local function InitESP(plr)
        if ESP_Cache[plr] then ClearESP(plr) end
        local boxLines = {}; for i=1,12 do table.insert(boxLines, NewLine()) end
        local skelLines = {}; for i=1,14 do table.insert(skelLines, NewLine()) end
        ESP_Cache[plr] = { BoxLines = boxLines, SkeletonLines = skelLines, Tracer = NewLine(), NameTag = nil }
    end

    RunService.RenderStepped:Connect(function()
        for plr, data in pairs(ESP_Cache) do
            local char = plr.Character; local root = char and char:FindFirstChild("HumanoidRootPart"); local head = char and char:FindFirstChild("Head")
            if ESP_Config.Enabled and char and root and head and plr ~= LocalPlayer then
                local vector, onScreen = Camera:WorldToViewportPoint(root.Position)
                if ESP_Config.Chams then local hl = char:FindFirstChild("LoveHubChams"); if not hl then hl = Instance.new("Highlight", char); hl.Name = "LoveHubChams" end; hl.FillColor = ESP_Config.ChamsFill; hl.OutlineColor = ESP_Config.ChamsOutline; hl.FillTransparency = 0.5; hl.Enabled = true else if char:FindFirstChild("LoveHubChams") then char.LoveHubChams:Destroy() end end
                if onScreen then
                    if ESP_Config.Box3D then
                        local size = char:GetExtentsSize(); local cf = root.CFrame * CFrame.new(0, -0.5, 0); local corners = { Vector3.new(size.X/2, size.Y/2, size.Z/2), Vector3.new(size.X/2, size.Y/2, -size.Z/2), Vector3.new(-size.X/2, size.Y/2, size.Z/2), Vector3.new(-size.X/2, size.Y/2, -size.Z/2), Vector3.new(size.X/2, -size.Y/2, size.Z/2), Vector3.new(size.X/2, -size.Y/2, -size.Z/2), Vector3.new(-size.X/2, -size.Y/2, size.Z/2), Vector3.new(-size.X/2, -size.Y/2, -size.Z/2) }
                        local points = {}; for _, c in pairs(corners) do local p = Camera:WorldToViewportPoint(cf:PointToWorldSpace(c)); table.insert(points, Vector2.new(p.X, p.Y)) end
                        local conns = {{1,2},{1,3},{1,5},{2,4},{2,6},{3,4},{3,7},{4,8},{5,6},{5,7},{6,8},{7,8}}
                        for i, conn in pairs(conns) do local l = data.BoxLines[i]; l.Visible = true; l.Color = ESP_Config.BoxColor; l.From = points[conn[1]]; l.To = points[conn[2]] end
                    else for _, l in pairs(data.BoxLines) do l.Visible = false end end
                    if ESP_Config.Tracers then local headPos = Camera:WorldToViewportPoint(head.Position); local lookPos = head.Position + (head.CFrame.LookVector * ESP_Config.TracerLength); local endPos = Camera:WorldToViewportPoint(lookPos); data.Tracer.Visible = true; data.Tracer.Color = ESP_Config.TracerColor; data.Tracer.From = Vector2.new(headPos.X, headPos.Y); data.Tracer.To = Vector2.new(endPos.X, endPos.Y) else data.Tracer.Visible = false end
                    if ESP_Config.Skeletons then for i, joint in pairs(SkeletonJoints) do local p1 = char:FindFirstChild(joint[1]); local p2 = char:FindFirstChild(joint[2]); local line = data.SkeletonLines[i]; if p1 and p2 then local v1, os1 = Camera:WorldToViewportPoint(p1.Position); local v2, os2 = Camera:WorldToViewportPoint(p2.Position); if os1 and os2 then line.Visible = true; line.Color = ESP_Config.SkeletonColor; line.From = Vector2.new(v1.X, v1.Y); line.To = Vector2.new(v2.X, v2.Y) else line.Visible = false end else line.Visible = false end end else for _, l in pairs(data.SkeletonLines) do l.Visible = false end end
                    if ESP_Config.Names then if not data.NameTag then local bg = Instance.new("BillboardGui"); bg.Name = "LoveHubName"; bg.Size = UDim2.new(0, 200, 0, 50); bg.StudsOffset = Vector3.new(0, 3.5, 0); bg.AlwaysOnTop = true; local tl = Instance.new("TextLabel", bg); tl.BackgroundTransparency = 1; tl.Size = UDim2.new(1,0,1,0); tl.TextStrokeTransparency = 0.2; tl.TextStrokeColor3 = Color3.new(0,0,0); bg.Parent = game.CoreGui; bg.Adornee = head; data.NameTag = bg end; local tag = data.NameTag; if tag and tag.Adornee ~= head then tag.Adornee = head end; local lbl = tag:FindFirstChild("TextLabel"); if lbl then lbl.Text = plr.Name; lbl.TextColor3 = ESP_Config.NameColor; lbl.Font = ESP_Config.NameFont; lbl.TextSize = ESP_Config.NameSize end; tag.Enabled = true else if data.NameTag then data.NameTag.Enabled = false end end
                else for _, l in pairs(data.BoxLines) do l.Visible = false end; for _, l in pairs(data.SkeletonLines) do l.Visible = false end; data.Tracer.Visible = false; if data.NameTag then data.NameTag.Enabled = false end end
            else for _, l in pairs(data.BoxLines) do l.Visible = false end; for _, l in pairs(data.SkeletonLines) do l.Visible = false end; data.Tracer.Visible = false; if data.NameTag then data.NameTag:Destroy(); data.NameTag = nil end; if char and char:FindFirstChild("LoveHubChams") then char.LoveHubChams:Destroy() end end
        end
    end)

    Players.PlayerAdded:Connect(InitESP); Players.PlayerRemoving:Connect(ClearESP); for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then InitESP(p) end end

    local MainGroup = Tabs.Main:AddLeftGroupbox('Desync Controls'); MainGroup:AddToggle('DesyncToggle', { Text = 'Enable Desync', Default = false, Tooltip = 'Freezes Sequence ID (Offset 4)', Callback = function(V) DesyncState.Enabled = V end }):AddKeyPicker('DesyncKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Desync Bind' })
    local EspGroup = Tabs.Visuals:AddLeftGroupbox('Global Settings'); EspGroup:AddToggle('EspMaster', { Text = 'Master Switch', Default = false, Callback = function(V) ESP_Config.Enabled = V end })
    local ElementsGroup = Tabs.Visuals:AddLeftGroupbox('ESP Elements'); ElementsGroup:AddToggle('EspBox3D', { Text = '3D Box', Default = false, Callback = function(V) ESP_Config.Box3D = V end }):AddColorPicker('BoxCol', { Default = ESP_Config.BoxColor, Title = 'Box Color', Callback = function(V) ESP_Config.BoxColor = V end }); ElementsGroup:AddToggle('EspSkel', { Text = 'Skeletons', Default = false, Callback = function(V) ESP_Config.Skeletons = V end }):AddColorPicker('SkelCol', { Default = ESP_Config.SkeletonColor, Title = 'Skeleton Color', Callback = function(V) ESP_Config.SkeletonColor = V end }); ElementsGroup:AddToggle('EspTracers', { Text = 'View Tracers', Default = false, Callback = function(V) ESP_Config.Tracers = V end }):AddColorPicker('TraceCol', { Default = ESP_Config.TracerColor, Title = 'Tracer Color', Callback = function(V) ESP_Config.TracerColor = V end }); ElementsGroup:AddSlider('TraceLen', { Text = 'Tracer Length', Default = 2.1, Min = 0.5, Max = 10, Rounding = 1, Callback = function(V) ESP_Config.TracerLength = V end })
    local TextGroup = Tabs.Visuals:AddRightGroupbox('Text & Chams'); TextGroup:AddToggle('EspNames', { Text = 'Nicknames', Default = false, Callback = function(V) ESP_Config.Names = V end }):AddColorPicker('NameCol', { Default = ESP_Config.NameColor, Title = 'Name Color', Callback = function(V) ESP_Config.NameColor = V end }); TextGroup:AddDropdown('FontSelect', { Values = FontKeys, Default = "Gotham Black", Multi = false, Text = 'Name Font', Callback = function(V) ESP_Config.NameFont = FontsTable[V] end }); TextGroup:AddSlider('TxtSize', { Text = 'Text Size', Default = 14, Min = 10, Max = 30, Rounding = 0, Callback = function(V) ESP_Config.NameSize = V end }); TextGroup:AddDivider(); TextGroup:AddToggle('EspChams', { Text = 'Chams', Default = false, Callback = function(V) ESP_Config.Chams = V end }):AddColorPicker('ChamFill', { Default = ESP_Config.ChamsFill, Title = 'Fill', Callback = function(V) ESP_Config.ChamsFill = V end }):AddColorPicker('ChamOut', { Default = ESP_Config.ChamsOutline, Title = 'Outline', Callback = function(V) ESP_Config.ChamsOutline = V end })
    local MenuSettings = Tabs.Settings:AddRightGroupbox('Menu'); MenuSettings:AddLabel('Menu Keybind'):AddKeyPicker('MenuKey', { Default = 'RightShift', NoUI = true, Text = 'Menu Keybind' }); MenuSettings:AddButton('Unload Script', function() Library:Unload() end)
    Library.ToggleKeybind = Options.MenuKey; ThemeManager:SetLibrary(Library); SaveManager:SetLibrary(Library); SaveManager:IgnoreThemeSettings(); SaveManager:SetFolder('LoveHub_Final'); SaveManager:BuildConfigSection(Tabs.Settings); ThemeManager:ApplyToTab(Tabs.Settings)

    Library:OnUnload(function()
        if raknet then raknet.clear_all_send_hooks() end
        for plr, _ in pairs(ESP_Cache) do ClearESP(plr) end
        if desyncGhostModel then desyncGhostModel:Destroy() end
        if serverHighlight then serverHighlight:Destroy() end
        if LocalPlayer.Character.Head:FindFirstChild("DesyncLabel") then LocalPlayer.Character.Head.DesyncLabel:Destroy() end
    end)
end

-- [[ ONLINE KEY AUTHENTICATION ]] --
local function checkExistingKey()
    if not isfile("lovehub_key.txt") then return false end
    local savedKey = readfile("lovehub_key.txt")
    local hwid = getExecutorHWID()
    
    local success, response = pcall(function()
        return request({
            Url = serverUrl,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({key = savedKey, hwid = hwid})
        })
    end)

    if success and response.StatusCode == 200 then
        local data = HttpService:JSONDecode(response.Body)
        return data.valid
    else
        return false
    end
end

local function verifyKeyOnline(inputKey)
    local hwid = getExecutorHWID()
    local success, response = pcall(function()
        return request({
            Url = serverUrl,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({key = inputKey, hwid = hwid})
        })
    end)

    if success and response.StatusCode == 200 then
        local data = HttpService:JSONDecode(response.Body)
        if data.valid then
            writefile("lovehub_key.txt", inputKey)
            return true, data.message
        else
            return false, data.message
        end
    else
        return false, "Connection Error"
    end
end

-- Check Saved Key
if checkExistingKey() then
    loadMainScript()
    return
end

-- [[ AUTH GUI ]] --
local keyGui = Instance.new("ScreenGui", game:GetService("CoreGui")); local frame = Instance.new("Frame", keyGui); frame.Size = UDim2.new(0, 400, 0, 250); frame.Position = UDim2.new(0.5, -200, 0.5, -125); frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30); Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
local title = Instance.new("TextLabel", frame); title.Size = UDim2.new(1, 0, 0, 50); title.BackgroundColor3 = Color3.fromRGB(20, 20, 20); title.Text = "LoveHub | HWID Login"; title.TextColor3 = Color3.fromRGB(255, 255, 255); title.Font = Enum.Font.GothamBold; title.TextSize = 18
local status = Instance.new("TextLabel", frame); status.Size = UDim2.new(0.8, 0, 0, 30); status.Position = UDim2.new(0.1, 0, 0.85, 0); status.BackgroundTransparency = 1; status.TextColor3 = Color3.fromRGB(255,255,255); status.Font = Enum.Font.Gotham; status.TextSize = 14; status.Text = ""
local input = Instance.new("TextBox", frame); input.Size = UDim2.new(0.8, 0, 0, 40); input.Position = UDim2.new(0.1, 0, 0.35, 0); input.BackgroundColor3 = Color3.fromRGB(40, 40, 40); input.TextColor3 = Color3.fromRGB(255, 255, 255); input.PlaceholderText = "Enter Key..."; input.Font = Enum.Font.Gotham; input.TextSize = 16
local btn = Instance.new("TextButton", frame); btn.Size = UDim2.new(0.8, 0, 0, 40); btn.Position = UDim2.new(0.1, 0, 0.6, 0); btn.BackgroundColor3 = Color3.fromRGB(0, 150, 255); btn.Text = "Connect"; btn.TextColor3 = Color3.fromRGB(255, 255, 255); btn.Font = Enum.Font.GothamBold; btn.TextSize = 16

btn.MouseButton1Click:Connect(function()
    status.Text = "Verifying..."
    status.TextColor3 = Color3.fromRGB(255, 255, 0)
    
    local key = input.Text
    local valid, msg = verifyKeyOnline(key)
    
    if valid then
        status.Text = "Success! Loading..."
        status.TextColor3 = Color3.fromRGB(0, 255, 0)
        btn.Active = false
        wait(1)
        keyGui:Destroy()
        loadMainScript()
    else
        status.Text = msg or "Invalid Key/HWID"
        status.TextColor3 = Color3.fromRGB(255, 0, 0)
    end
end)
