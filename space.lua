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

local MainData = http:JSONDecode(readfile(FileName))
if not MainData.AutoFarm then return end

-- ПЛАНЕТЫ (Церера удалена)
local Planets = {
    [5534753074] = { -- Moon
        {"LanderAscentStage", "Lunar", " Sample", "Lander2", "GatewayRemote"},
        {"LLAMA", "Lunar", " Sample", "LLAMA", "GatewayRemote"},
        {"AftCargoHold", "Lunar", " Sample", "Aresonius", "GatewayRemote"},
    }, 
    [6119982580] = { -- Mars
        {"MidUpperStage", "Iron", " Oxide", "MarsLander", "DSTRemote"},
        {"AftCargoHold", "Iron", " Oxide", "Aresonius", "DSTRemote"}
    }
} 

-- ЛОГИКА ТЕЛЕПОРТАЦИИ ИЗ МЕНЮ
local SpecialLanders = {
    [6458953928] = {"Aresonius", "ToMarsRemote"},
    [6686215787] = {"Aresonius", "ToMarsRemote"}, -- Заглушка для орбитера
    [5515926734] = {"Aresonius", "ToMoonRemote"}
}

local function IsInOrbiter()
    return (game.PlaceId == 6458953928 or game.PlaceId == 6686215787)
end

-- Обработка перемещений между локациями
if IsInOrbiter() and MainData.CameFromPlanet then
    MainData.CameFromPlanet = false
    writefile(FileName, http:JSONEncode(MainData))
    TpToGateway()
    return
elseif IsInGateway() or IsInOrbiter() then
    MainData.CameFromPlanet = false
    writefile(FileName, http:JSONEncode(MainData))
end

local function Get_Names()
    return Planets[game.PlaceId] or false
end

local function GetLander()
    if _G.lander and _G.PlanetInstanceNames then return _G.lander end
    local names = Get_Names()
    if not names then return nil end
    for _, l in pairs(workspace:GetChildren()) do
        if l:IsA("Model") and l:FindFirstChild("LanderOwner") and l.LanderOwner.Value == plr.Name then
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
    return l and l[_G.PlanetInstanceNames[1]].Deposit.ProximityPrompt 
end

local function GetPrompt2()
    local l = GetLander()
    if l and l.Name == "Aresonius" then
        return l[_G.PlanetInstanceNames[1]].Deposit2.ProximityPrompt 
    end
    return nil
end

local function GetTool()
    return plr.Backpack:FindFirstChild("Pick Up") or (plr.Character and plr.Character:FindFirstChild("Pick Up"))
end

-- УЛЬТРА СКОРОСТЬ СБОРА
function CollectSamples()
    local lander = GetLander()
    if not lander then return end
    local storage = lander.ResourceValues.Storage
    local capacity = lander.ResourceValues.Capacity
    
    while storage.Value < capacity.Value do
        Collected = false
        local Tool = GetTool()
        if Tool then Tool.PickUp:FireServer() end
        
        local t = 0
        while not Collected and t < 60 do 
            t = t + 1
            task.wait() 
        end
    end 
    MainData.CameFromPlanet = true
    writefile(FileName, http:JSONEncode(MainData))
    game:GetService("ReplicatedStorage")[_G.PlanetInstanceNames[5]]:FireServer(plr.Name)
end

-- МОМЕНТАЛЬНЫЙ ТЕЛЕПОРТ К ЯЩИКУ
local function QuickTpToPrompt(Prompt)
    task.spawn(function() 
        local lander = GetLander()
        while task.wait() do 
            local Char = plr.Character
            if Char and Char:FindFirstChild("HumanoidRootPart") and Prompt.Parent then
                Char.HumanoidRootPart.CFrame = Prompt.Parent.CFrame
                if Char:FindFirstChild("Humanoid") then Char.Humanoid.Sit = false end
            end
            if lander.ResourceValues.Storage.Value >= lander.ResourceValues.Capacity.Value then break end
        end
    end)
end

-- МОМЕНТАЛЬНАЯ СДАЧА (E)
local function RockAdded(child)
    local names = _G.PlanetInstanceNames
    if names and child.Name == (names[2] .. names[3]) then
        local Char = plr.Character
        local hum = Char and Char:FindFirstChild("Humanoid")
        if hum then
            hum:EquipTool(child)
            task.wait(0.15) 
            local Prompt = (GetLander().Name == "Aresonius") and GetPrompt2() or GetPrompt()
            if Prompt then fireproximityprompt(Prompt) end
            Collected = true 
        end
    end
end

-- ЛОГИКА ЗАПУСКА
task.wait(2)
if not Get_Names() then
    -- Если мы в Гейтвее или Орбитере - летим на планету
    if IsInGateway() then
        local target = math.random(1,2) == 1 and "ToMoonRemote" or "ToMarsRemote"
        game.ReplicatedStorage[target]:FireServer("Aresonius")
    elseif IsInOrbiter() then
        game.ReplicatedStorage.ToMarsRemote:FireServer("Aresonius")
    end
    return
end 

local lander = GetLander()
if lander then
    if not lander.Landed.Value then lander.Landed:GetPropertyChangedSignal("Value"):Wait() end
    local p = GetPrompt()
    if p then QuickTpToPrompt(p) end
    table.insert(_G.Connections, plr.Backpack.ChildAdded:Connect(RockAdded))
    SendNotif('AutoFarm', 'Луна/Марс Активен', 2)
    CollectSamples()
end
