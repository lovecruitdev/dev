-- v2.lua (Агрессивный, но стабильный)
if not game:IsLoaded() then game.Loaded:Wait() end

_G.ScriptRunning = false
task.wait(0.2)
_G.ScriptRunning = true

local plr = game.Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local root = char:WaitForChild("HumanoidRootPart")
local hum = char:WaitForChild("Humanoid")
local http = game:GetService("HttpService")
local FileName = "SS.JSON"

-- Чистка старых циклов
_G.Connections = _G.Connections or {}
for _, v in pairs(_G.Connections) do v:Disconnect() end
_G.Connections = {}

local MainData = http:JSONDecode(readfile(FileName))
if not MainData.AutoFarm then return end

local Planets = {
    [5534753074] = {"LanderAscentStage", "Lunar", " Sample", "Lander2", "GatewayRemote"},
    [6669650377] = {"UpperStage", "Cererian", " Sample", "CeresLander", "DSTRemote"},
    [6119982580] = {"MidUpperStage", "Iron", " Oxide", "MarsLander", "DSTRemote"}
}

-- Поиск лендера (твоего корабля)
local function GetLander()
    for _, l in pairs(workspace:GetChildren()) do
        if l:IsA("Model") and l:FindFirstChild("LanderOwner") and l.LanderOwner.Value == plr.Name then
            for id, data in pairs(Planets) do
                if l.Name == data[4] or (l.Name == "Aresonius" and game.PlaceId == id) then
                    _G.PlanetData = data
                    return l
                end
            end
        end
    end
    return nil
end

-- Функция для получения актуальной кнопки сбора (учитывая Aresonius)
local function GetCurrentPrompt(lander)
    local data = _G.PlanetData
    if not lander or not data then return nil end
    
    if lander.Name == "Aresonius" then
        -- У Aresonius может быть Deposit2
        local dep2 = lander[data[1]]:FindFirstChild("Deposit2")
        if dep2 then return dep2.ProximityPrompt end
    end
    return lander[data[1]].Deposit.ProximityPrompt
end

-- ЦИКЛ ТЕЛЕПОРТА (Тут была проблема)
local function StartFastTP(targetPrompt)
    task.spawn(function()
        print("Телепорт запущен на цель: ", targetPrompt:GetFullName())
        while _G.ScriptRunning and targetPrompt and targetPrompt.Parent do
            if char and root then
                -- Телепортируем ПРЯМО ВНУТРЬ промпта
                root.CFrame = targetPrompt.Parent.CFrame
                hum.Sit = false -- Чтобы не садился в кресла случайно
            end
            task.wait(0.1) -- 10 раз в секунду - идеально для стабильности
        end
    end)
end

-- СБОР РЕСУРСОВ
local function CollectSamples(lander)
    local data = _G.PlanetData
    local storage = lander.ResourceValues.Storage
    local capacity = lander.ResourceValues.Capacity
    local prompt = GetCurrentPrompt(lander)

    if not prompt then return end
    StartFastTP(prompt) -- Включаем прилипание к кнопке

    while _G.ScriptRunning and storage.Value < capacity.Value do
        -- 1. Спамим подбор
        local tool = plr.Backpack:FindFirstChild("Pick Up") or char:FindFirstChild("Pick Up")
        if tool then
            tool.PickUp:FireServer()
        end
        
        task.wait(0.2)

        -- 2. Экипируем и сдаем
        local rockName = data[2] .. data[3]
        local rock = plr.Backpack:FindFirstChild(rockName)
        if rock then
            hum:EquipTool(rock)
            task.wait(0.1)
            fireproximityprompt(prompt)
        end
    end

    if storage.Value >= capacity.Value then
        MainData.CameFromPlanet = true
        writefile(FileName, http:JSONEncode(MainData))
        task.wait(1)
        game.ReplicatedStorage[data[5]]:FireServer(plr.Name)
    end
end

-- ОСНОВНАЯ ЛОГИКА
if Planets[game.PlaceId] then
    local lander = nil
    repeat 
        lander = GetLander()
        task.wait(1)
    until lander or not _G.ScriptRunning

    if lander then
        -- Ждем посадки
        if not lander.Landed.Value then
            print("Ждем приземления...")
            lander.Landed:GetPropertyChangedSignal("Value"):Wait()
        end
        
        task.wait(2) -- Даем физике прогрузиться
        CollectSamples(lander)
    end
elseif game.PlaceId == 5515926734 then -- Gateway
    task.wait(3)
    local remotes = {"ToMoonRemote", "ToCeresRemote", "ToMarsRemote"}
    game.ReplicatedStorage[remotes[math.random(1, #remotes)]]:FireServer("Aresonius")
end
