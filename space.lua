-- v2.lua (Main Script)
if not game:IsLoaded() then game.Loaded:Wait() end

-- Остановка предыдущей копии скрипта
_G.ScriptRunning = false
task.wait(0.5)
_G.ScriptRunning = true

local TeleportService = game:GetService("TeleportService")
local http = game:GetService("HttpService")
local plr = game.Players.LocalPlayer
local FileName = "SS.JSON"

-- Чистка старых соединений
_G.Connections = _G.Connections or {}
for _, conn in pairs(_G.Connections) do conn:Disconnect() end
_G.Connections = {}

-- Загрузка данных
if not isfile(FileName) then return end
local MainData = http:JSONDecode(readfile(FileName))

if not MainData.AutoFarm then 
    print("AutoFarm is disabled in config.")
    return 
end

-- Функции уведомлений и проверок
local function SendNotif(title, text, delay)
    game.StarterGui:SetCore("SendNotification", {Title = title, Text = text, Duration = delay or 3})
end

local function IsInGateway() return game.PlaceId == 5515926734 end

-- Данные планет
local Planets = {
    [5534753074] = {"LanderAscentStage", "Lunar", " Sample", "Lander2", "GatewayRemote"},
    [6669650377] = {"UpperStage", "Cererian", " Sample", "CeresLander", "DSTRemote"},
    [6119982580] = {"MidUpperStage", "Iron", " Oxide", "MarsLander", "DSTRemote"}
}

-- Поиск актуального корабля/лендера
local function GetLander()
    for _, l in pairs(workspace:GetChildren()) do
        if l:IsA("Model") and l:FindFirstChild("LanderOwner") and l.LanderOwner.Value == plr.Name then
            for _, data in pairs(Planets) do
                if l.Name == data[4] then
                    _G.PlanetInstanceNames = data
                    return l
                end
            end
        end
    end
    return nil
end

local function CollectSamples()
    local lander = GetLander()
    if not lander then return end
    
    local data = _G.PlanetInstanceNames
    local prompt = lander[data[1]].Deposit.ProximityPrompt
    local storage = lander.ResourceValues.Storage
    local capacity = lander.ResourceValues.Capacity

    print("Начинаю сбор ресурсов...")
    
    while _G.ScriptRunning and storage.Value < capacity.Value do
        local tool = plr.Backpack:FindFirstChild("Pick Up") or (plr.Character and plr.Character:FindFirstChild("Pick Up"))
        if tool then
            tool.PickUp:FireServer()
        end
        
        task.wait(0.5) -- Небольшая пауза, чтобы не спамить сервер
        
        -- Проверка на наличие камня в рюкзаке
        local rock = plr.Backpack:FindFirstChild(data[2] .. data[3])
        if rock and plr.Character then
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum:EquipTool(rock) end
            
            task.wait(0.2)
            fireproximityprompt(prompt)
        end
    end

    if storage.Value >= capacity.Value then
        print("Загрузка полная, улетаем...")
        MainData.CameFromPlanet = true
        writefile(FileName, http:JSONEncode(MainData))
        game.ReplicatedStorage[data[5]]:FireServer(plr.Name)
    end
end

-- Основная логика при загрузке на планету
if Planets[game.PlaceId] then
    local lander = nil
    -- Ждем, пока корабль появится и приземлится
    repeat 
        lander = GetLander()
        task.wait(1)
    until lander or not _G.ScriptRunning

    if lander then
        if not lander.Landed.Value then
            lander.Landed:GetPropertyChangedSignal("Value"):Wait()
        end
        
        SendNotif("AutoFarm", "Приземление завершено. Начинаю сбор.", 5)
        
        -- Поток для удержания позиции у промпта (без фанатизма, чтобы не крашило)
        task.spawn(function()
            while _G.ScriptRunning and lander:FindFirstChild("Landed") and lander.Landed.Value do
                if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
                    local target = lander[_G.PlanetInstanceNames[1]].Deposit.CFrame
                    plr.Character.HumanoidRootPart.CFrame = target * CFrame.new(0, 2, 0)
                end
                task.wait(2) -- ТП раз в 2 секунды достаточно для работы промпта
            end
        end)

        CollectSamples()
    end
elseif IsInGateway() then
    -- Логика выбора планеты в Гейтвее
    task.wait(2)
    local remotes = {"ToMoonRemote", "ToCeresRemote", "ToMarsRemote"}
    local randomRemote = remotes[math.random(1, #remotes)]
    game.ReplicatedStorage[randomRemote]:FireServer("Aresonius")
end
