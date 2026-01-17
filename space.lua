local TeleportService = game:GetService("TeleportService")

function SendNotif(title, text, delay)
    game.StarterGui:SetCore("SendNotification", {Title = title, Text = text, Duration = delay})
end

function IsInGateway()
    return game.PlaceId == 5515926734
end

function TpToGateway()
    TeleportService:Teleport(5515926734)
end

local function GetChildrenOfClass(parent, ClassName)
    local childrenOfClass = {}
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA(ClassName) then
            table.insert(childrenOfClass, child)
        end
    end
    return childrenOfClass
end

_G.Connections = _G.Connections or {}
for _, Connection in pairs(_G.Connections) do 
    Connection:Disconnect()
end 
_G.Connections = {}

local Collected = false
local FileName = "SS.JSON"
local plr = game.Players.LocalPlayer
local http = game:GetService("HttpService")

local DefaultData = {
    AutoFarm = false,
    CameFromPlanet = false
}
local MainData
local AutoFarm
local CameFromPlanet

if game.GameId ~= 1722988797 then
    print("this isnt space sailors")
    return
end

if not isfile(FileName) then
    writefile(FileName, http:JSONEncode(DefaultData))
end
MainData = http:JSONDecode(readfile(FileName))
AutoFarm = MainData.AutoFarm
CameFromPlanet = MainData.CameFromPlanet

function SaveData()
    writefile(FileName, http:JSONEncode(MainData))
end

if not game:IsLoaded() then game.Loaded:Wait() end

local Planets = {
    [5534753074] = {
        {"LanderAscentStage", "Lunar", " Sample", "Lander2", "GatewayRemote"},
        {"LLAMA", "Lunar", " Sample", "LLAMA", "GatewayRemote"},
        {"AftCargoHold", "Lunar", " Sample", "Aresonius", "GatewayRemote"},
    }, 
    [6669650377] = {
        {"UpperStage", "Cererian", " Sample", "CeresLander", "DSTRemote"},
        {"AftCargoHold", "Cererian", " Sample", "Aresonius", "DSTRemote"}
    },
    [6119982580] = {
        {"MidUpperStage", "Iron", " Oxide", "MarsLander", "DSTRemote"},
        {"AftCargoHold", "Iron", " Oxide", "Aresonius", "DSTRemote"}
    }
} 

local function Get_Names()
    return Planets[game.PlaceId] or false
end

-- Логика получения промпта
local function GetLander()
    if _G.lander and _G.PlanetInstanceNames then return _G.lander end
    for _, l in pairs(workspace:GetChildren()) do
        if l:IsA("Model") and l:FindFirstChild("LanderOwner") and l.LanderOwner.Value == plr.Name then
            local names = Get_Names()
            for _, opt in pairs(names) do
                if l.Name == opt[4] then
                    _G.lander = l
                    _G.PlanetInstanceNames = opt
                    return l
                end
            end
        end
    end
end

local function GetPrompt() 
    local l = GetLander()
    if not l then return nil end
    return l[_G.PlanetInstanceNames[1]].Deposit.ProximityPrompt 
end

local function GetPrompt2()
    local l = GetLander()
    if l and l.Name == "Aresonius" then
        return l[_G.PlanetInstanceNames[1]].Deposit2.ProximityPrompt 
    end
    return nil
end

local function GetTool()
    for _, v in pairs(plr.Backpack:GetChildren()) do
        if v.Name:sub(1, 7) == "Pick Up" then return v end 
    end
    return plr.Character and plr.Character:FindFirstChild("Pick Up")
end

-- Основной цикл сбора
function CollectSamples()
    local lander = GetLander()
    if not lander then return end
    
    local AmountStored = lander.ResourceValues.Storage
    local Capacity = lander.ResourceValues.Capacity
    
    repeat
        Collected = false
        local Tool = GetTool()
        if Tool then
            Tool.PickUp:FireServer()
        end
        
        -- Ждем пока RockAdded сработает и установит Collected = true
        local timeout = 0
        while not Collected and timeout < 10 do
            timeout = timeout + 1
            task.wait(0.2)
        end
        
        task.wait(0.3) -- Пауза перед следующим подбором
    until not AmountStored or AmountStored.Value >= Capacity.Value 
    
    MainData.CameFromPlanet = true
    SaveData()
    game:GetService("ReplicatedStorage")[_G.PlanetInstanceNames[5]]:FireServer(plr.Name)
end

-- Телепорт
local function QuickTpToPrompt(Prompt)
    task.spawn(function() 
        local lander = GetLander()
        while task.wait(0.1) do
            local Char = plr.Character
            if Char and Char:FindFirstChild("HumanoidRootPart") and Prompt.Parent then
                Char.HumanoidRootPart.CFrame = Prompt.Parent.CFrame
                if Char:FindFirstChild("Humanoid") then Char.Humanoid.Sit = false end
            end
            if lander.ResourceValues.Storage.Value >= lander.ResourceValues.Capacity.Value then break end
        end
    end)
end

-- Ивент на добавление камня в инвентарь
local function RockAdded(child)
    local names = _G.PlanetInstanceNames
    if not names then return end
    
    if child.Name == (names[2] .. names[3]) then
        task.wait(0.1)
        local Char = plr.Character
        local hum = Char and Char:FindFirstChild("Humanoid")
        
        if hum then
            -- Берем в руки
            hum:EquipTool(child)
            task.wait(0.5) -- Ждем анимации взятия
            
            -- Выбираем куда сдавать
            local Prompt = (GetLander().Name == "Aresonius") and GetPrompt2() or GetPrompt()
            
            if Prompt then
                fireproximityprompt(Prompt)
                task.wait(0.3)
                Collected = true -- Сигналим циклу CollectSamples, что можно подбирать следующий
            end
        end
    end
end

-- Запуск
local lander = GetLander()
if lander then
    if not lander.Landed.Value then lander.Landed:GetPropertyChangedSignal("Value"):Wait() end
    
    local p = GetPrompt()
    if p then QuickTpToPrompt(p) end
    
    table.insert(_G.Connections, plr.Backpack.ChildAdded:Connect(RockAdded))
    
    SendNotif('Autofarming', 'Started', 5)
    CollectSamples()
end
