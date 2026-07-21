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
local Char = plr.Character or plr.CharacterAdded:Wait()
local hum = Char:WaitForChild("Humanoid")

local DefaultData = {
    AutoFarm = true,
    CameFromPlanet = true
}
local MainData
local AutoFarm
local CameFromPlanet
local http = game:GetService("HttpService")

if game.GameId ~= 1722988797 then
    print("this isnt space sailors")
    return
end

if not isfile(FileName) then
    local data = http:JSONEncode(DefaultData)
    writefile(FileName, data)
    MainData = http:JSONDecode(readfile(FileName))
else
    MainData = http:JSONDecode(readfile(FileName))
    AutoFarm = MainData.AutoFarm
    CameFromPlanet = MainData.CameFromPlanet
end

function SaveData()
    local data = http:JSONEncode(MainData)
    -- delfile убран для предотвращения краша при записи
    writefile(FileName, data)
    MainData = http:JSONDecode(readfile(FileName))
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
    local OrbiterIds = {
        6458953928,
        6686215787 
    }
    for _, id in pairs(OrbiterIds) do
        if game.PlaceId == id then
            return true
        end
    end
    return false
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
        for _, Table in pairs(SpecialLanders) do
           table.insert(t, Table[2])
        end
        local RemoteName = t[math.random(1, #t)]
        local CustomLander = GetSpecialLanderByRemote(tostring(RemoteName))[1]
        game.ReplicatedStorage[RemoteName]:FireServer(CustomLander)
    else
        local spec = GetSpecialLanderName()
        if spec then
            game.ReplicatedStorage[spec[2]]:FireServer(spec[1])
        end
    end
    return
end 

local function GetLander()
    if _G.lander and _G.PlanetInstanceNames then 
        return _G.lander 
    end

    for _, l in pairs(workspace:GetChildren()) do
        if l:IsA("Model") then
            local names = Get_Names()
            for _, LanderOption in pairs(names) do
                if l.Name == LanderOption[4] and l:FindFirstChild("LanderOwner") and l.LanderOwner.Value == plr.Name then
                    _G.lander = l 
                    _G.PlanetInstanceNames = LanderOption
                    return _G.lander
                end
            end
        end
    end
end

local function GetTool()
    for _, v in pairs(plr.Backpack:GetChildren()) do
        if v.Name:sub(1, 7) == "Pick Up" then
            return v
        end 
    end
end

local function GetNames() 
    return _G.PlanetInstanceNames
end

local function GetPrompt() 
    local lander = GetLander()
    return lander and lander[GetNames()[1]].Deposit.ProximityPrompt 
end

local function GetPrompt2()
    local val=false
    local lander = GetLander()
    if lander and lander.Name == "Aresonius" then
        val=lander[GetNames()[1]].Deposit2.ProximityPrompt 
    end
    return val
end

function CollectSamples()
    local Prompt = GetPrompt()
    if not Prompt then return end
    
    local Tool = GetTool()
    if not Tool then return end
    
    local PickUp = Tool.PickUp
    local AmountStored = Prompt.Parent.Parent.Parent.ResourceValues.Storage
    local Capacity = AmountStored.Parent.Capacity
    
    repeat
        if GetLander().Name == "Aresonius" then
            local character = plr.Character
            if character and character:FindFirstChild("Humanoid") then
                character.Humanoid.Sit = false
            end
        end
        PickUp:FireServer()
        
        local timer = 0
        while task.wait() do
            timer = timer + 1
            if Collected or timer > 100 then break end
        end
        
        task.wait()
        Collected = false
    until not AmountStored or AmountStored.Value >= Capacity.Value 
    
    MainData.CameFromPlanet = true
    SaveData()
    game:GetService("ReplicatedStorage")[GetNames()[5]]:FireServer(plr.Name)
end

local Warp
for _, v in pairs(game.ReplicatedStorage:GetDescendants()) do
    if v.Name == "WarpLandRemote" then
        Warp = v.Parent:FindFirstChild(v.Name)
        break
    end
end

if Warp then
    Warp:FireServer(plr.Name)
end

SendNotif('Waiting to land', 'autofarm will begin when you land', 5)

local function QuickTpToPrompt(Prompt)
    local lander = GetLander()
    if not lander then return end
    local AmountStored = Prompt.Parent.Parent.Parent.ResourceValues.Storage
    local Capacity = AmountStored.Parent.Capacity
    
    task.spawn(function() 
        if lander.Name == "Aresonius" then
            repeat
                task.wait()
                local character = plr.Character
                if character and character:FindFirstChild("HumanoidRootPart") then
                    character.HumanoidRootPart.CFrame = Prompt.Parent.CFrame
                end
            until not AmountStored or AmountStored.Value >= Capacity.Value  
        end
    end)
end

local lander = GetLander()
if lander and lander:FindFirstChild("Landed") then
    if not lander.Landed.Value then 
        lander.Landed:GetPropertyChangedSignal("Value"):Wait()
    end
end

SendNotif('Autofarming', 'started to autofarm', 5)

local p = GetPrompt()
if p then QuickTpToPrompt(p) end

local function RockAdded(child)
    local Prompt = GetPrompt()
    local names = GetNames()
    if not names or child.Name ~= (names[2] .. names[3]) then return end
    
    local character = plr.Character
    if character and character:FindFirstChild("Humanoid") then
        character.Humanoid:EquipTool(child)
    end
    
    if GetLander().Name == "Aresonius" then
        Prompt = GetPrompt2()
    end
    
    if Prompt then
        fireproximityprompt(Prompt)
    end
    
    Collected = true 
end

table.insert(_G.Connections, plr.Backpack.ChildAdded:Connect(RockAdded))
CollectSamples()
