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
    writefile(FileName, http:JSONEncode(MainData)) -- Убрал delfile, он вызывает ошибки
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

local function GetCeresRemote()
    local b = "ToMarsRemote" 
    if IsInGateway() then 
        b = "ToCeresRemote" 
    elseif game.PlaceId == 6458953928 then 
        b = "ToMarsRemote" 
    end
    return b
end

local SpecialLanders = {
    [6458953928] = {"Aresonius", "ToMarsRemote"},
    [6686215787] = {"Aresonius", GetCeresRemote()},
    [5515926734] = {"Aresonius", "ToMoonRemote"}
}

local function Get_Names()
    return Planets[game.PlaceId] or false
end

local function GetSpecialLanderName()
    for id, name in pairs(SpecialLanders) do
        if game.PlaceId == id then
            return name
        end
    end
end

local Cashout = game:GetService("ReplicatedStorage"):FindFirstChild("Cashout")
if Cashout then 
    Cashout:FireServer()
    SendNotif('Cashout Success', 'Cashed out ignore the green button', 3) 
end

if AutoFarm==false then
    print("wont autofarm")
    return false
end

if game.PlaceId == 5000143962 then 
    MainData.CameFromPlanet = false
    SaveData()
    TpToGateway()
    return
end

local function GetSpecialLanderByRemote(RemoteName)
    for _, Name in pairs(SpecialLanders) do
        if Name[2] == RemoteName then
            return Name
        end
    end
end

local function IsInOrbiter()
    return (game.PlaceId == 6458953928 or game.PlaceId == 6686215787)
end

if IsInOrbiter() and CameFromPlanet then
    MainData.CameFromPlanet = false
    SaveData()
    TpToGateway()
    return
else
    MainData.CameFromPlanet = false
    SaveData()
end

task.wait(3)

if not Get_Names() then
    if IsInOrbiter() == false and IsInGateway() == true then
        local t = {}
        for _, Table in pairs(SpecialLanders) do table.insert(t, Table[2]) end
        local RemoteName = t[math.random(1, #t)]
        local CustomLander = GetSpecialLanderByRemote(tostring(RemoteName))[1]
        game.ReplicatedStorage[RemoteName]:FireServer(CustomLander)
    else
        local spec = GetSpecialLanderName()
        if spec then game.ReplicatedStorage[spec[2]]:FireServer(spec[1]) end
    end
    return
end 

local function GetLander()
    if _G.lander and _G.PlanetInstanceNames then return _G.lander end
    for _, l in pairs(workspace:GetChildren()) do
        if l:IsA("Model") and l:FindFirstChild("LanderOwner") and l.LanderOwner.Value == plr.Name then
            local names = Get_Names()
            if typeof(names[1]) == "table" then
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
end

local function GetTool()
    for _, v in pairs(plr.Backpack:GetChildren()) do
        if v.Name:sub(1, 7) == "Pick Up" then return v end 
    end
    if plr.Character and plr.Character:FindFirstChildOfClass("Tool") and plr.Character:FindFirstChildOfClass("Tool").Name:sub(1,7) == "Pick Up" then
        return plr.Character:FindFirstChildOfClass("Tool")
    end
end

local function GetPrompt() 
    local l = GetLander()
    return l and l[_G.PlanetInstanceNames[1]].Deposit.ProximityPrompt 
end

local function GetPrompt2()
    local l = GetLander()
    if l and l.Name == "Aresonius" then
        return l[_G.PlanetInstanceNames[1]].Deposit2.ProximityPrompt 
    end
    return false
end

function CollectSamples()
    local lander = GetLander()
    if not lander then return end
    
    local Prompt = GetPrompt()
    local AmountStored = lander.ResourceValues.Storage
    local Capacity = lander.ResourceValues.Capacity
    
    repeat
        local Char = plr.Character
        local hum = Char and Char:FindFirstChild("Humanoid")
        if hum and lander.Name == "Aresonius" then hum.Sit = false end
        
        local Tool = GetTool()
        if Tool and Tool:FindFirstChild("PickUp") then
            Tool.PickUp:FireServer()
        end
        
        -- Фикс краша: таймаут на ожидание подбора (5 секунд)
        local t = 0
        while task.wait(0.1) do
            t = t + 0.1
            if Collected or t > 5 then break end
        end
        
        Collected = false
    until not AmountStored or AmountStored.Value >= Capacity.Value 
    
    MainData.CameFromPlanet = true
    SaveData()
    game:GetService("ReplicatedStorage")[_G.PlanetInstanceNames[5]]:FireServer(plr.Name)
end

-- Авто-посадка
task.spawn(function()
    local Warp = game.ReplicatedStorage:FindFirstChild("WarpLandRemote", true)
    if Warp then Warp:FireServer(plr.Name) end
end)

local function QuickTpToPrompt(Prompt)
    local lander = GetLander()
    local AmountStored = lander.ResourceValues.Storage
    local Capacity = lander.ResourceValues.Capacity
    
    task.spawn(function() 
        while task.wait(0.05) do -- Добавил задержку, чтобы не вешать физику
            local Char = plr.Character
            if Char and Char:FindFirstChild("HumanoidRootPart") and Prompt.Parent then
                Char.HumanoidRootPart.CFrame = Prompt.Parent.CFrame
            end
            if not AmountStored or AmountStored.Value >= Capacity.Value then break end
        end
    end)
end

local lander = GetLander()
if lander and lander:FindFirstChild("Landed") then
    if not lander.Landed.Value then lander.Landed:GetPropertyChangedSignal("Value"):Wait() end
end

SendNotif('Autofarming', 'started', 5)
local p = GetPrompt()
if p then QuickTpToPrompt(p) end

local function RockAdded(child)
    local names = _G.PlanetInstanceNames
    if child.Name == (names[2] .. names[3]) then
        local Char = plr.Character
        local hum = Char and Char:FindFirstChild("Humanoid")
        if hum then
            hum:EquipTool(child)
            task.wait(0.1)
            local Prompt = (GetLander().Name == "Aresonius") and GetPrompt2() or GetPrompt()
            fireproximityprompt(Prompt)
            Collected = true
        end
    end
end

table.insert(_G.Connections, plr.Backpack.ChildAdded:Connect(RockAdded))
CollectSamples()
