-- RarelyWinUI.lua
-- Runtime UI library for Roblox/Luau.
-- The library only creates interface objects; game-specific behavior belongs in callbacks.

local Library = {}
Library.__index = Library
Library.Version = "0.01"

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local StatsService = game:GetService("Stats")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer and LocalPlayer:GetMouse()

Library.Theme = {
    BackgroundStart = Color3.fromRGB(14, 15, 17),
    BackgroundEnd = Color3.fromRGB(25, 26, 29),
    Surface = Color3.fromRGB(29, 30, 33),
    Surface2 = Color3.fromRGB(38, 39, 42),
    Surface3 = Color3.fromRGB(48, 49, 52),
    Accent = Color3.fromRGB(210, 212, 216),
    AccentDark = Color3.fromRGB(92, 94, 99),
    Text = Color3.fromRGB(242, 243, 245),
    Muted = Color3.fromRGB(158, 160, 165),
    Stroke = Color3.fromRGB(7, 8, 9),
    Success = Color3.fromRGB(73, 183, 118),
    Warning = Color3.fromRGB(202, 173, 94),
    Error = Color3.fromRGB(190, 75, 110),
    Info = Color3.fromRGB(113, 110, 151),
}

local T = Library.Theme
local connections = {}
local iconCache = {}

local SUB_HEIGHT, SECTION_GAP, SUB_STAGGER = 38, 3, .035

-- Asset folders, relative to the executor workspace. .ttf/.otf files go into FONT_DIR and
-- .mp3/.ogg/.wav files into SOUND_DIR; the UI Font and sound dropdowns re-scan them when they open.
local FONT_DIR, SOUND_DIR, CACHE_DIR = "RarelyWinUI/fonts", "RarelyWinUI/sounds", "RarelyWinUI/cache"
local DEFAULT_TOGGLE_SOUND = "rbxassetid://6895079853"
-- Every built-in Roblox font (Enum.Font) is a preset, e.g. ArialBold, GothamBold, SourceSans...
local BUILTIN_FONT_ORDER, BUILTIN_FONTS = {}, {}
for _, item in ipairs(Enum.Font:GetEnumItems()) do
    if item ~= Enum.Font.Unknown then
        BUILTIN_FONTS[item.Name] = item
        table.insert(BUILTIN_FONT_ORDER, item.Name)
    end
end
local TEXT_CLASSES = {TextLabel = true, TextButton = true, TextBox = true}
local fontFiles, soundFiles = {}, {}                   -- display name -> file name inside its folder
local fontAssets, familyFonts, soundIds = {}, {}, {}   -- caches (false = tried and failed)
local originalFonts = setmetatable({}, {__mode = "k"}) -- text object -> Enum.Font it was created with
local ActiveFont = nil -- nil: elements keep their own fonts; {enum = Enum.Font} preset; {regular = Font, bold = Font} file

local function ensureFolder(path)
    if not (makefolder and isfolder) then return end
    local built
    for part in string.gmatch(path, "[^/]+") do
        built = built and (built .. "/" .. part) or part
        if not isfolder(built) then pcall(makefolder, built) end
    end
end

local function fileExists(path)
    return isfile ~= nil and isfile(path) == true
end

-- Writes a .font descriptor for the faces that exist and returns its getcustomasset id (or nil)
local function faceAsset(key, faces)
    if fontAssets[key] ~= nil then return fontAssets[key] or nil end
    fontAssets[key] = false
    local present = {}
    for _, face in ipairs(faces) do
        if fileExists(FONT_DIR .. "/" .. face.file) then table.insert(present, face) end
    end
    if #present == 0 or not (getcustomasset and writefile) then return nil end
    local ok, result = pcall(function()
        local list = {}
        for _, face in ipairs(present) do
            table.insert(list, {
                name = face.weight >= 600 and "Bold" or "Regular", weight = face.weight, style = "normal",
                assetId = getcustomasset(FONT_DIR .. "/" .. face.file),
            })
        end
        ensureFolder(CACHE_DIR)
        local descriptor = CACHE_DIR .. "/font_" .. (key:gsub("[^%w]", "")) .. ".font"
        writefile(descriptor, HttpService:JSONEncode({name = key, faces = list}))
        return getcustomasset(descriptor)
    end)
    if ok and result and result ~= "" then
        fontAssets[key] = result
    else
        warn("[RarelyWinUI] font '" .. key .. "' could not be loaded: " .. tostring(result))
    end
    return fontAssets[key] or nil
end

local function familyFont(key, faces, bold)
    local cacheKey = key .. (bold and ":bold" or ":regular")
    if familyFonts[cacheKey] ~= nil then return familyFonts[cacheKey] or nil end
    familyFonts[cacheKey] = false
    local asset = faceAsset(key, faces)
    if asset then
        local ok, font = pcall(Font.new, asset, bold and Enum.FontWeight.Bold or Enum.FontWeight.Regular)
        if ok then familyFonts[cacheKey] = font end
    end
    return familyFonts[cacheKey] or nil
end

local function fileFont(name)
    local file = fontFiles[name]
    if not file then return nil end
    local regular = familyFont("file_" .. name, {{file = file, weight = 400}}, false)
    return regular and {regular = regular, bold = regular} or nil
end

local function isBoldFont(enumFont)
    local name = string.lower(enumFont and enumFont.Name or "")
    return string.find(name, "bold") ~= nil or string.find(name, "black") ~= nil or string.find(name, "heavy") ~= nil
end

-- Puts the active UI font on a text object. Bold elements stay bold when a file font is chosen.
local function applyFont(object, originalFont)
    if not ActiveFont then
        if originalFont then object.Font = originalFont end
        return
    end
    if ActiveFont.enum then
        object.Font = ActiveFont.enum
    else
        object.FontFace = isBoldFont(originalFont) and ActiveFont.bold or ActiveFont.regular
    end
end

local function scanFolder(dir, extensions, store)
    table.clear(store)
    local names = {}
    if not (listfiles and isfolder and isfolder(dir)) then return names end
    for _, path in ipairs(listfiles(dir)) do
        local file = tostring(path):match("[^/\\]+$") or ""
        local base, ext = file:match("^(.+)%.([^%.]+)$")
        if base and extensions[string.lower(ext)] then
            store[base] = file
            table.insert(names, base)
        end
    end
    table.sort(names)
    return names
end

local function soundIdFor(name)
    if name == nil or name == "Default" then return DEFAULT_TOGGLE_SOUND end
    local file = soundFiles[name]
    if not file then return nil end
    if soundIds[name] == nil then
        local ok, asset = pcall(getcustomasset, SOUND_DIR .. "/" .. file)
        soundIds[name] = (ok and asset and asset ~= "" and asset) or false
    end
    return soundIds[name] or nil
end

local function create(className, props, children)
    local object = Instance.new(className)
    local originalFont = TEXT_CLASSES[className] and props and props.Font
    for key, value in pairs(props or {}) do
        object[key] = value
    end
    if originalFont then
        originalFonts[object] = originalFont
        if ActiveFont then applyFont(object, originalFont) end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = object
    end
    return object
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function tween(object, time, props, style, direction)
    local info = TweenInfo.new(time or .18, style or Enum.EasingStyle.Quart, direction or Enum.EasingDirection.Out)
    local animation = TweenService:Create(object, info, props)
    animation:Play()
    return animation
end

local function round(parent, radius)
    return create("UICorner", {CornerRadius = UDim.new(0, radius)}, {}), parent
end

local function addRound(parent, radius)
    local corner = create("UICorner", {CornerRadius = UDim.new(0, radius)})
    corner.Parent = parent
    return corner
end


local function stroke(parent, color, thickness, transparency)
    local item = create("UIStroke", {
        Color = color or T.Stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
    item.Parent = parent
    return item
end

local function padding(parent, left, right, top, bottom)
    local item = create("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0), PaddingRight = UDim.new(0, right or left or 0),
        PaddingTop = UDim.new(0, top or 0), PaddingBottom = UDim.new(0, bottom or top or 0),
    })
    item.Parent = parent
    return item
end

local function gradient(parent, first, last, rotation)
    local item = create("UIGradient", {
        Color = ColorSequence.new(first or T.BackgroundStart, last or T.BackgroundEnd),
        Rotation = rotation or 90,
    })
    item.Parent = parent
    return item
end

local function label(parent, text, size, font, color, align)
    local item = create("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = text or "",
        TextColor3 = color or T.Text,
        TextSize = size or 16,
        Font = font or Enum.Font.GothamMedium,
        TextXAlignment = align or Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    item.Parent = parent
    return item
end

local function autoCanvas(scroller, layout, extra)
    local function update()
        scroller.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + (extra or 0))
    end
    connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), update)
    update()
end

local function dragify(handle, target)
    local dragging, dragStart, startPosition
    connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPosition = true, input.Position, target.Position
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local function safeCallback(callback, ...)
    if type(callback) ~= "function" then return end
    local ok, err = pcall(callback, ...)
    if not ok then warn("[RarelyWinUI callback] " .. tostring(err)) end
end

-- Lucide icon loader supplied by the library design. The source is cached in RarelyWinUI/cache,
-- so icons load without a download; delete that file to fetch a fresh copy.
local LUCIDE_URL = "https://raw.githubusercontent.com/mstudio45/lucide-roblox-direct/refs/heads/main/source.lua"
local LUCIDE_CACHE = CACHE_DIR .. "/lucide.lua"
local function loadLucide()
    if fileExists(LUCIDE_CACHE) then
        local ok, module = pcall(function() return (loadstring(readfile(LUCIDE_CACHE)))() end)
        if ok and type(module) == "table" then return true, module end
    end
    local ok, source = pcall(game.HttpGet, game, LUCIDE_URL)
    if not ok or type(source) ~= "string" then return false, source end
    local compiled, module = pcall(function() return (loadstring(source))() end)
    if not compiled then return false, module end
    if writefile then
        ensureFolder(CACHE_DIR)
        pcall(writefile, LUCIDE_CACHE, source)
    end
    return true, module
end
local _lucideOk, _lucideModule = loadLucide()

function Library:GetIcon(name)
    if iconCache[name] then return iconCache[name] end
    if not _lucideOk or type(_lucideModule) ~= "table" then return nil end
    local getter = _lucideModule.GetAsset or _lucideModule.getAsset
    if type(getter) ~= "function" then return nil end
    local ok, result = pcall(getter, name)
    if not ok then ok, result = pcall(getter, _lucideModule, name) end
    local asset = result
    if type(result)=="string" then asset={Url=result,ImageRectOffset=Vector2.zero,ImageRectSize=Vector2.zero} end
    if ok and type(asset)=="table" and type(asset.Url)=="string" then iconCache[name]=asset; return asset end
    return nil
end

function Library:GetIconStatus()
    if _lucideOk and type(_lucideModule)=="table" then return true,nil end
    return false,tostring(_lucideModule)
end

local function icon(parent, name, size, color)
    local asset = Library:GetIcon(name)
    local image = create("ImageLabel", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Image = asset and asset.Url or "",
        ImageRectOffset = asset and asset.ImageRectOffset or Vector2.zero,
        ImageRectSize = asset and asset.ImageRectSize or Vector2.zero,
        ImageColor3 = color or T.Text,
        Size = UDim2.fromOffset(size or 20, size or 20),
    })
    image.Parent = parent
    return image
end

local function brand(parent, short, size)
    local holder = create("Frame", {BackgroundTransparency = 1, Size = size or UDim2.fromOffset(270, 58)})
    holder.Parent = parent
    local text = short and "RW" or "RARELYWIN"
    local shadow = label(holder, text, short and 52 or 46, Enum.Font.GothamBlack, T.Accent)
    shadow.Position = UDim2.fromOffset(-3, 3)
    shadow.Size = UDim2.fromScale(1, 1)
    shadow.TextScaled = true
    local shadowConstraint=create("UITextSizeConstraint",{MinTextSize=12,MaxTextSize=short and 52 or 46}); shadowConstraint.Parent=shadow
    local front = label(holder, text, short and 52 or 46, Enum.Font.GothamBlack, T.Text)
    front.Size = UDim2.fromScale(1, 1)
    front.TextScaled = true
    local frontConstraint=create("UITextSizeConstraint",{MinTextSize=12,MaxTextSize=short and 52 or 46}); frontConstraint.Parent=front
    return holder
end

local function oneCornerCard(frame, radius)
    addRound(frame, radius or 15)
end

function Library:CreateWindow(options)
    options = options or {}
    local self = setmetatable({}, Library)
    self.Tabs, self.Keybinds, self.Flags, self.HUDRegistry = {}, {}, {}, {}
    self.ValueBinds = {} -- shared registry for the Toggle/Checkbox keybind-value feature
    self.Visible = true

    local parent = options.Parent
    if not parent then
        local ok, hui = pcall(function() return gethui and gethui() end)
        parent = (ok and hui) or game:GetService("CoreGui")
    end

    local gui = create("ScreenGui", {
        Name = options.Name or ("RarelyWinUI_" .. HttpService:GenerateGUID(false)),
        ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    pcall(function() gui.Parent = parent end)
    if not gui.Parent and LocalPlayer then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
    self.Gui = gui

    local main = create("CanvasGroup", {
        Name = "Window", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        Size = options.Size or UDim2.fromOffset(980, 610), BackgroundColor3 = T.BackgroundStart,
        BorderSizePixel = 0, ClipsDescendants = true, ZIndex=50, GroupTransparency = .08,
    })
    main.Parent = gui
    addRound(main, 15); stroke(main, T.Stroke, 2)
    local mainGradientBackground=create("Frame",{Name="MainGradientBackground",BackgroundColor3=T.BackgroundStart,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=0})
    mainGradientBackground.Parent=main
    self.Main, self.OriginalSize = main, main.Size
    self.Visible = true
    self.HUDElements = {}

    local sidebar = create("Frame", {BackgroundColor3 = T.BackgroundStart, BackgroundTransparency = .03, BorderSizePixel = 0, Size = UDim2.new(0, 260, 1, 0), ClipsDescendants = true})
    sidebar.Parent = main
    self.Sidebar = sidebar
    local divider = create("Frame", {BackgroundColor3 = T.Stroke, BorderSizePixel = 0, Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0)})
    divider.Parent = sidebar

    local titleBrand = brand(sidebar, options.CompactTitle == true, UDim2.new(1, -34, 0, 58))
    titleBrand.Position = UDim2.fromOffset(20, 13)
    local version = label(sidebar, "V. " .. tostring(options.Version or Library.Version), 18, Enum.Font.GothamBold)
    version.Position = UDim2.fromOffset(22, 67); version.Size = UDim2.fromOffset(125, 26)
    local uid = label(sidebar, "UID: " .. tostring(options.UID or 1), 18, Enum.Font.GothamBold, T.Text, Enum.TextXAlignment.Right)
    uid.Position = UDim2.new(1, -130, 0, 67); uid.Size = UDim2.fromOffset(105, 26)

    -- Scrolls instead of running into the pinned Configs/Settings buttons: the list ends 8px above Configs
    -- (Configs sits 164px from the bottom), so an expanded section can never overlap them.
    local tabList = create("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(18, 105), Size = UDim2.new(1, -36, 1, -277), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 2, ScrollBarImageColor3 = T.Muted, ScrollBarImageTransparency = .5, VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar})
    tabList.Parent = sidebar
    local tabLayout = create("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder})
    tabLayout.Parent = tabList

    local settings = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = UDim2.new(0, 18, 1, -112), Size = UDim2.new(1, -36, 0, 46)})
    settings.Parent = sidebar; settings.BackgroundColor3=T.Surface3; addRound(settings,9); self.SettingsButton=settings
    local settingsIcon = icon(settings, "settings", 25, T.Muted); settingsIcon.AnchorPoint=Vector2.new(.5,.5); settingsIcon.Position = UDim2.fromOffset(23,23)
    local settingsText = label(settings, "Settings", 18, Enum.Font.GothamBold); settingsText.Position = UDim2.fromOffset(47, 0); settingsText.Size = UDim2.new(1, -47, 1, 0)

    local profile = create("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -64), Size = UDim2.new(1, 0, 0, 64)})
    profile.Parent = sidebar
    local profileLine = create("Frame", {BackgroundColor3 = T.Stroke, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1)})
    profileLine.Parent = profile
    local username = label(profile, "@" .. tostring(options.Username or (LocalPlayer and LocalPlayer.Name) or "username"), 15, Enum.Font.GothamBold)
    username.Position = UDim2.fromOffset(20, 9); username.Size = UDim2.new(1, -70, 0, 23)
    local detectedPlace="Unknown Place"; pcall(function() detectedPlace=MarketplaceService:GetProductInfo(game.PlaceId).Name end)
    local gameName = label(profile, options.Game or detectedPlace, 14, Enum.Font.GothamBold)
    gameName.Position = UDim2.fromOffset(20, 31); gameName.Size = UDim2.new(1, -70, 0, 20)
    self.UsernameLabel,self.GameLabel,self.OriginalUsername=username,gameName,username.Text
    local bottomCollapse = create("TextButton", {Text="", AutoButtonColor=false, BackgroundColor3=T.Surface3, BorderSizePixel=0, Position=UDim2.new(1,-45,0,18), Size=UDim2.fromOffset(28,28), ZIndex=12})
    bottomCollapse.Parent=profile; addRound(bottomCollapse,7)
    local bottomCollapseIcon=icon(bottomCollapse,"chevron-left",17,T.Text); bottomCollapseIcon.AnchorPoint=Vector2.new(.5,.5); bottomCollapseIcon.Position=UDim2.fromScale(.5,.5); bottomCollapseIcon.ZIndex=13

    local collapse = create("TextButton", {Text = "‹", TextColor3 = T.Text, TextSize = 25, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundColor3 = T.Surface3, BorderSizePixel = 0, Position = UDim2.new(1, -31, 0, 13), Size = UDim2.fromOffset(25, 25), ZIndex = 12})
    collapse.Parent = sidebar; collapse.Visible=false; addRound(collapse, 7)

    local topbar = create("Frame", {BackgroundColor3 = T.BackgroundStart, BackgroundTransparency = .04, BorderSizePixel = 0, Position = UDim2.fromOffset(260, 0), Size = UDim2.new(1, -260, 0, 64)})
    topbar.Parent = main
    local search = create("TextBox", {
        PlaceholderText = "Search...", PlaceholderColor3 = T.Muted, Text = "", ClearTextOnFocus = false,
        TextColor3 = T.Text, TextSize = 16, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundColor3 = Color3.fromRGB(130, 128, 145), BackgroundTransparency = .15, BorderSizePixel = 0,
        Position = UDim2.fromOffset(44, 14), Size = UDim2.new(1, -62, 0, 36),
    })
    search.Parent = topbar; addRound(search, 7); padding(search, 12, 12, 0, 0)
    local searchIcon = icon(topbar, "search", 22, T.Text); searchIcon.Position = UDim2.fromOffset(16, 21)
    local content = create("Frame", {BackgroundColor3 = T.BackgroundStart, BackgroundTransparency = 0, Position = UDim2.fromOffset(260, 64), Size = UDim2.new(1, -260, 1, -64), ClipsDescendants = true})
    content.Parent = main
    gradient(content, T.BackgroundStart, T.BackgroundEnd, 125)
    local backgroundImage=create("ImageLabel",{Name="CustomBackground",BackgroundTransparency=1,Image="",ImageTransparency=.35,ScaleType=Enum.ScaleType.Crop,Size=UDim2.fromScale(1,1),Visible=false,ZIndex=0})
    backgroundImage.Parent=content; self.BackgroundImage=backgroundImage

    self.Sidebar, self.TabList, self.Content, self.Search = sidebar, tabList, content, search
    self.Topbar, self.SidebarCollapsed = topbar, false
    dragify(topbar, main)

    function self:SetSidebarCollapsed(collapsed)
        self.SidebarCollapsed = collapsed == true
        local width = self.SidebarCollapsed and 72 or 260
        local collapseAsset=self:GetIcon(self.SidebarCollapsed and "chevron-right" or "chevron-left")
        if collapseAsset then bottomCollapseIcon.Image=collapseAsset.Url; bottomCollapseIcon.ImageRectOffset=collapseAsset.ImageRectOffset; bottomCollapseIcon.ImageRectSize=collapseAsset.ImageRectSize end
        tween(sidebar, .28, {Size = UDim2.new(0, width, 1, 0)}, Enum.EasingStyle.Quint)
        tween(topbar, .28, {Position = UDim2.fromOffset(width, 0), Size = UDim2.new(1, -width, 0, 64)}, Enum.EasingStyle.Quint)
        tween(content, .28, {Position = UDim2.fromOffset(width, 64), Size = UDim2.new(1, -width, 1, -64)}, Enum.EasingStyle.Quint)
        titleBrand.Visible = not self.SidebarCollapsed; version.Visible = not self.SidebarCollapsed; uid.Visible = not self.SidebarCollapsed
        settingsText.Visible = not self.SidebarCollapsed; username.Visible=not self.SidebarCollapsed; gameName.Visible=not self.SidebarCollapsed; profile.Visible=true
        settings.Size = self.SidebarCollapsed and UDim2.fromOffset(36,46) or UDim2.new(1,-36,0,46)
        settingsIcon.Position = self.SidebarCollapsed and UDim2.new(.5,0,.5,0) or UDim2.fromOffset(23,23)
        for _, tab in ipairs(self.Tabs) do
            tab.Title.Visible = not self.SidebarCollapsed
            if tab.Icon then tab.Icon.Position = self.SidebarCollapsed and UDim2.new(.5,-12,.5,-12) or UDim2.fromOffset(11,9) end
            for _,sub in ipairs(tab.Subcategories) do
                sub.Title.Visible=not self.SidebarCollapsed
                sub.Icon.Position=self.SidebarCollapsed and UDim2.new(.5,-10,.5,-10) or UDim2.fromOffset(28,9)
            end
        end
    end
    connect(collapse.MouseButton1Click, function() self:SetSidebarCollapsed(not self.SidebarCollapsed) end)
    connect(bottomCollapse.MouseButton1Click, function() self:SetSidebarCollapsed(not self.SidebarCollapsed) end)

    connect(search:GetPropertyChangedSignal("Text"), function()
        for _, tab in ipairs(self.Tabs) do
            if tab.Page.Visible then tab:ApplyFilter() end
        end
    end)

    connect(UserInputService.InputBegan, function(input, processed)
        local point=input.Position
        if self.OpenDropdown then
            local open=self.OpenDropdown; local bp,bs=open.Button.AbsolutePosition,open.Button.AbsoluteSize; local mp,ms=open.Menu.AbsolutePosition,open.Menu.AbsoluteSize
            local insideButton=point.X>=bp.X and point.X<=bp.X+bs.X and point.Y>=bp.Y and point.Y<=bp.Y+bs.Y
            local insideMenu=point.X>=mp.X and point.X<=mp.X+ms.X and point.Y>=mp.Y and point.Y<=mp.Y+ms.Y
            if not insideButton and not insideMenu then open:Close() end
        end
        if self.OpenColorPicker then
            local picker=self.OpenColorPicker; local sp,ss=picker.Swatch.AbsolutePosition,picker.Swatch.AbsoluteSize; local pp,ps=picker.Popup.AbsolutePosition,picker.Popup.AbsoluteSize
            local insideSwatch=point.X>=sp.X and point.X<=sp.X+ss.X and point.Y>=sp.Y and point.Y<=sp.Y+ss.Y
            local insidePopup=point.X>=pp.X and point.X<=pp.X+ps.X and point.Y>=pp.Y and point.Y<=pp.Y+ps.Y
            if not insideSwatch and not insidePopup then picker:Close() end
        end
        if self.OpenBindPopup then
            local bp2=self.OpenBindPopup; local bbp,bbs=bp2.Button.AbsolutePosition,bp2.Button.AbsoluteSize; local bpp,bps=bp2.Popup.AbsolutePosition,bp2.Popup.AbsoluteSize
            local insideBindButton=point.X>=bbp.X and point.X<=bbp.X+bbs.X and point.Y>=bbp.Y and point.Y<=bbp.Y+bbs.Y
            local insideBindPopup=point.X>=bpp.X and point.X<=bpp.X+bps.X and point.Y>=bpp.Y and point.Y<=bpp.Y+bps.Y
            if not insideBindButton and not insideBindPopup then bp2:Close() end
        end
        local toggleKey = options.ToggleKey or Enum.KeyCode.RightShift
        if input.KeyCode == toggleKey then
            if not UserInputService:GetFocusedTextBox() then
                self:ToggleUI()
                return
            end
        end

        if processed then return end
        for _, bind in ipairs(self.Keybinds) do
            if input.KeyCode == bind.Key or input.UserInputType == bind.Key then safeCallback(bind.Callback, bind.Key) end
        end
        for _, entry in ipairs(self.ValueBinds) do
            for _, vbind in ipairs(entry.Binds) do
                if vbind.Key and (input.KeyCode == vbind.Key or input.UserInputType == vbind.Key) then
                    if vbind.Mode == "Toggle" then
                        entry.Control:Set(not entry.Control.Value)
                    elseif vbind.Mode == "Hold" and not vbind.HoldActive then
                        vbind.HoldActive = true
                        vbind.PriorValue = entry.Control.Value
                        entry.Control:Set(vbind.Value)
                    end
                end
            end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        for _, entry in ipairs(self.ValueBinds) do
            for _, vbind in ipairs(entry.Binds) do
                if vbind.Mode == "Hold" and vbind.HoldActive and vbind.Key and (input.KeyCode == vbind.Key or input.UserInputType == vbind.Key) then
                    vbind.HoldActive = false
                    entry.Control:Set(vbind.PriorValue)
                end
            end
        end
    end)
    pcall(function()
        connect(GuiService.MenuOpened, function() self._hiddenByRobloxMenu=self.Visible; if self._hiddenByRobloxMenu then self.Main.Visible=false end end)
        connect(GuiService.MenuClosed, function() if self._hiddenByRobloxMenu and self.Visible then self.Main.Visible=true end; self._hiddenByRobloxMenu=false end)
    end)

    connect(settings.MouseButton1Click, function()
        if self.SettingsTab then self.SettingsTab:Select() end
    end)

    if options.ToggleButton ~= false then self:_createToggle(options.ToggleVariant or 1) end
    self:_buildSettingsSection()
    return self
end

function Library:_createToggle(variant)
    local oldPosition=self.ToggleButton and self.ToggleButton.Position or UDim2.fromOffset(18,18)
    if self.ToggleButton then self.ToggleButton:Destroy() end
    local button = create("TextButton", {
        Name = "UIToggle", Text = "", AutoButtonColor = false,
        BackgroundColor3 = T.BackgroundStart, BorderSizePixel = 0,
        Position = oldPosition, Size = variant == 2 and UDim2.fromOffset(255, 62) or UDim2.fromOffset(72, 72),
    })
    button.Parent = self.Gui; addRound(button, variant == 2 and 31 or 22); gradient(button, T.BackgroundStart, T.BackgroundEnd, 35)
    local word = variant == 2 and "RARELYWIN" or "RW"
    local wordSize = variant == 2 and 32 or 34
    local accent = label(button, word, wordSize, Enum.Font.GothamBlack, T.Accent, Enum.TextXAlignment.Center)
    accent.Position = UDim2.fromOffset(-1, 1); accent.Size = UDim2.fromScale(1, 1); accent.ZIndex = button.ZIndex + 1
    local front = label(button, word, wordSize, Enum.Font.GothamBlack, T.Text, Enum.TextXAlignment.Center)
    front.Size = UDim2.fromScale(1,1); front.ZIndex = button.ZIndex + 2
    connect(button.MouseButton1Click, function() self:ToggleUI() end)
    dragify(button, button)
    self.ToggleButton = button
    if self.HUDElements then self.HUDElements["Toggle UI Button"] = button end
    if self._selectedElements and self._selectedElements["Toggle UI Button"] ~= nil then
        button.Visible = self._selectedElements["Toggle UI Button"] == true
    end
end

function Library:ToggleUI(state)
    if state == nil then state = not self.Visible end
    self.Visible = state
    local target = self.OriginalSize or self.Main.Size
    if state then
        self.Main.Visible = true
        self.Main.Size = UDim2.new(target.X.Scale, math.floor(target.X.Offset*.94), target.Y.Scale, math.floor(target.Y.Offset*.94))
        self.Main.GroupTransparency = 1
        tween(self.Main, .22, {Size = target, GroupTransparency = 0.08}, Enum.EasingStyle.Back)
    else
        tween(self.Main, .18, {Size = UDim2.new(target.X.Scale, math.floor(target.X.Offset*.94), target.Y.Scale, math.floor(target.Y.Offset*.94)), GroupTransparency = 1})
        task.delay(.19, function() if not self.Visible then self.Main.Visible = false end end)
    end
end

-- A card is shown when it has no subcategory, or belongs to the active one of its section.
local function subcategoryMatches(tab, subcategory)
    return subcategory == nil or tab.ActiveSub == nil or subcategory == tab.ActiveSub.Name
end

-- Animates one subcategory row open (height + fade + slide) or closed. A newer call on the same row
-- cancels the older tweens and delayed steps through the token, so fast clicks never fight each other.
-- time == nil applies the state instantly.
local function setSubState(sub, shown, active, time, delay)
    sub.Token = (sub.Token or 0) + 1
    local token = sub.Token
    for _, animation in ipairs(sub.Tweens) do animation:Cancel() end
    table.clear(sub.Tweens)
    local item, image, title = sub.Button, sub.Icon, sub.Title
    title.TextColor3 = active and T.Text or T.Muted
    local function play()
        if sub.Token ~= token then return end
        local height = shown and SUB_HEIGHT or 0
        local background = shown and (active and .06 or 1) or 1
        local fade = shown and 0 or 1
        local slide = shown and 60 or 68
        if not time then
            item.Size = UDim2.new(1, 0, 0, height)
            item.BackgroundTransparency = background
            image.ImageTransparency = fade
            title.TextTransparency = fade
            title.Position = UDim2.fromOffset(slide, 0)
            item.Visible = shown
            return
        end
        if shown and not item.Visible then
            -- Start collapsed so the row grows open instead of popping in
            item.Size = UDim2.new(1, 0, 0, 0)
            image.ImageTransparency = 1
            title.TextTransparency = 1
            title.Position = UDim2.fromOffset(68, 0)
            item.Visible = true
        end
        table.insert(sub.Tweens, tween(item, time, {Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = background}, Enum.EasingStyle.Quint))
        table.insert(sub.Tweens, tween(image, time, {ImageTransparency = fade}))
        table.insert(sub.Tweens, tween(title, time, {TextTransparency = fade, Position = UDim2.fromOffset(slide, 0)}, Enum.EasingStyle.Quint))
        if not shown then
            task.delay(time, function() if sub.Token == token then item.Visible = false end end)
        end
    end
    if delay and delay > 0 then task.delay(delay, play) else play() end
end

function Library:Tab(options)
    options = type(options) == "string" and {Name = options} or (options or {})
    local tab = {Library = self, Name = options.Name or "Tab", Cards = {}, Subcategories = {}, Panels = {}}
    -- Gap above every section except the first one. Pinned (Configs) and hidden tabs get none.
    if #self.Tabs > 0 and not options.Hidden and not options.Pinned then
        local gap = create("Frame", {Name = "SectionGap", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, SECTION_GAP), LayoutOrder = (#self.Tabs + 1) * 10 - 1})
        gap.Parent = self.TabList
    end
    local button = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = T.Surface3, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 42)})
    button.Parent = self.TabList; button.LayoutOrder=(#self.Tabs+1)*10; addRound(button, 9)
    local image = icon(button, options.Icon or "menu", 24, T.Muted); image.Position = UDim2.fromOffset(11, 9)
    local title = label(button, tab.Name, 18, Enum.Font.GothamBold); title.Position = UDim2.fromOffset(48, 0); title.Size = UDim2.new(1, -48, 1, 0)
    local page = create("CanvasGroup", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 1, -28), Visible = false, GroupTransparency=1})
    page.Parent = self.Content
    local left = create("ScrollingFrame", {Name="Left", BackgroundTransparency=1, BorderSizePixel=0, Size=UDim2.new(.5,-6,1,0), CanvasSize=UDim2.fromOffset(0,0), ScrollBarThickness=0, ScrollBarImageTransparency=1}); left.Parent=page
    local right = create("ScrollingFrame", {Name="Right", BackgroundTransparency=1, BorderSizePixel=0, Position=UDim2.new(.5,6,0,0), Size=UDim2.new(.5,-6,1,0), CanvasSize=UDim2.fromOffset(0,0), ScrollBarThickness=0, ScrollBarImageTransparency=1}); right.Parent=page
    local leftLayout = create("UIListLayout", {Padding=UDim.new(0,12), SortOrder=Enum.SortOrder.LayoutOrder}); leftLayout.Parent=left
    local rightLayout = create("UIListLayout", {Padding=UDim.new(0,12), SortOrder=Enum.SortOrder.LayoutOrder}); rightLayout.Parent=right
    autoCanvas(left,leftLayout,6); autoCanvas(right,rightLayout,6)
    tab.Button, tab.Title, tab.Icon, tab.Page, tab.Left, tab.Right, tab.LeftLayout, tab.RightLayout = button, title, image, page, left, right, leftLayout, rightLayout
    if options.Hidden then button.Visible=false; button.Size=UDim2.fromOffset(0,0) end
    table.insert(self.Tabs, tab)

    function tab:ApplyFilter()
        local query = string.lower(self.Library.Search.Text)
        for _, card in ipairs(self.Cards) do
            local searchMatch = query == "" or string.find(string.lower(card.SearchText), query, 1, true) ~= nil
            card.Frame.Visible = searchMatch and subcategoryMatches(self, card.Subcategory)
        end
        for _, entry in ipairs(self.Panels) do
            entry.Frame.Visible = self.ActiveSub ~= nil and entry.Subcategory == self.ActiveSub.Name
        end
    end
    function tab:_setSubsShown(shown, time)
        for index, sub in ipairs(self.Subcategories) do
            setSubState(sub, shown, sub == self.ActiveSub, time, shown and (index - 1) * SUB_STAGGER or 0)
        end
    end
    function tab:ActivateSubcategory(sub)
        if self.ActiveSub == sub then return end -- same subsection: nothing to animate
        self.ActiveSub = sub
        -- Switching inside an open section is instant: only opening a section is animated
        for _, other in ipairs(self.Subcategories) do
            setSubState(other, true, other == sub)
        end
        self:ApplyFilter()
    end
    function tab:Select()
        local library = self.Library
        if library.ActiveTab == self then return end -- section already open: keep focus, no animation
        local previous = library.ActiveTab
        for _, other in ipairs(library.Tabs) do
            other.Page.Visible = false
            tween(other.Button, .16, {BackgroundTransparency = 1})
        end
        if previous then previous:_setSubsShown(false, .2) end
        self.Page.Visible = true
        self.Page.GroupTransparency = 1
        tween(self.Page, .22, {GroupTransparency = 0})
        tween(self.Button, .16, {BackgroundTransparency = .05})
        if not self.ActiveSub then self.ActiveSub = self.Subcategories[1] end
        self:ApplyFilter()
        self:_setSubsShown(true, .26)
        if library.SettingsButton then tween(library.SettingsButton, .16, {BackgroundTransparency = self == library.SettingsTab and .05 or 1}) end
        library.ActiveTab = self
    end
    function tab:Subcategory(name, iconName)
        local index=#self.Subcategories+1
        local item=create("TextButton",{Name="Subcategory_"..name,Text="",AutoButtonColor=false,BackgroundColor3=T.Surface3,BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.new(1,0,0,SUB_HEIGHT),Visible=false,ClipsDescendants=true,LayoutOrder=self.Button.LayoutOrder+index})
        item.Parent=self.Library.TabList; addRound(item,8)
        local image=icon(item,iconName or "menu",20,T.Muted); image.Position=UDim2.fromOffset(28,9)
        local title=label(item,name,16,Enum.Font.GothamBold,T.Muted); title.Position=UDim2.fromOffset(60,0); title.Size=UDim2.new(1,-60,1,0)
        local sub={Button=item,Title=title,Icon=image,Name=name,Tweens={}}
        table.insert(self.Subcategories,sub)
        connect(item.MouseButton1Click,function() self:ActivateSubcategory(sub) end)
        if self.Library.ActiveTab == self then
            -- Section is already open (its subsections were added after it was selected): show without animating
            if not self.ActiveSub then self.ActiveSub = sub end
            setSubState(sub,true,sub==self.ActiveSub)
            self:ApplyFilter()
        else
            setSubState(sub,false,false)
        end
        return sub
    end
    connect(button.MouseButton1Click, function() tab:Select() end)
    connect(button.MouseEnter, function() if self.ActiveTab ~= tab then tween(button, .12, {BackgroundTransparency = .7}) end end)
    connect(button.MouseLeave, function() if self.ActiveTab ~= tab then tween(button, .12, {BackgroundTransparency = 1}) end end)
    if not self.ActiveTab and not options.Hidden then tab:Select() end
    return tab
end

function Library:SelectTab(name)
    for _, tab in ipairs(self.Tabs) do if tab.Name == name then tab:Select(); return tab end end
end

local function newRow(card, height, name)
    local row = create("Frame", {Name = name or "Control", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, height or 34)})
    row.Parent = card.Body
    return row
end

local function createCard(tab, options)
    options = type(options) == "string" and {Title = options} or (options or {})
    local card = {Tab = tab, SearchText = (options.Title or "Function") .. " ", Controls = {}, Subcategory = options.Subcategory}
    local frame = create("Frame", {BackgroundColor3 = T.Surface, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 43), AutomaticSize = Enum.AutomaticSize.Y})
    local side = string.lower(options.Side or ((#tab.Cards % 2 == 0) and "left" or "right"))
    frame.Parent = side == "right" and tab.Right or tab.Left; oneCornerCard(frame, 15)
    frame.Visible = subcategoryMatches(tab, options.Subcategory)
    frame.BackgroundTransparency = .08
    stroke(frame, Color3.fromRGB(68, 69, 73), 1, .35)
    local header = create("Frame", {BackgroundColor3 = T.BackgroundStart, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 43), ZIndex = 2})
    header.Parent = frame; header.BackgroundTransparency = .03
    oneCornerCard(header, 10)
    stroke(header, Color3.fromRGB(72, 73, 77), 1, .55)
    -- Collapse/expand chevron: reserves the rightmost 26px, everything else (Risky label, Keybind
    -- state/bind buttons) shifts left by that much so nothing overlaps.
    local collapseReserve = 26
    local title = label(header, options.Title or "Function", 19, Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(12, 0); title.Size = UDim2.new(1, -(collapseReserve + (options.Keybind and 205 or 60)), 1, 0); title.ZIndex = 3
    if options.Risky then
        local risky = label(header, "!  Risky", 14, Enum.Font.GothamBold, T.Warning, Enum.TextXAlignment.Right)
        risky.Position = UDim2.new(1, -(collapseReserve + (options.Keybind and 200 or 130)), 0, 0); risky.Size = UDim2.fromOffset(90, 43); risky.ZIndex = 3
    end
    if options.Keybind then
        local state = options.Default ~= false
        local stateButton = create("TextButton", {Text="", AutoButtonColor=false, BackgroundColor3=state and T.Success or T.Error, BorderSizePixel=0, Position=UDim2.new(1,-(collapseReserve+31),0,11), Size=UDim2.fromOffset(21,21), ZIndex=5}); stateButton.Parent=header; addRound(stateButton,11)
        local bindButton = create("TextButton", {Text=options.BindName or "...", TextColor3=T.Muted, TextSize=12, Font=Enum.Font.GothamBold, AutoButtonColor=false, BackgroundColor3=T.Surface3, BorderSizePixel=0, Position=UDim2.new(1,-(collapseReserve+93),0,10), Size=UDim2.fromOffset(54,23), ZIndex=5}); bindButton.Parent=header; addRound(bindButton,6)
        connect(stateButton.MouseButton1Click,function() state=not state; tween(stateButton,.15,{BackgroundColor3=state and T.Success or T.Error}); safeCallback(options.ToggleCallback,state) end)
        connect(bindButton.MouseButton1Click,function() bindButton.Text="..."; local input=UserInputService.InputBegan:Wait(); local chosen=input.KeyCode~=Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType; bindButton.Text=chosen.Name; safeCallback(options.BindChanged,chosen) end)
        card.StateButton, card.BindButton = stateButton, bindButton
    end
    local body = create("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 43), Size = UDim2.new(1, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.Y})
    body.Parent = frame; padding(body, 12, 12, 7, 9)
    local layout = create("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder})
    layout.Parent = body

    -- Card collapse: the chevrons-up-down button sits in the header's right reserve (26px), so it
    -- never overlaps the Risky label, the keybind state or the bind button.
    local collapseButton = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -2, .5, 0), Size = UDim2.fromOffset(24, 24), ZIndex = 5})
    collapseButton.Parent = header
    local collapseIcon = icon(collapseButton, "chevrons-up-down", 15, T.Muted); collapseIcon.AnchorPoint = Vector2.new(.5, .5); collapseIcon.Position = UDim2.fromScale(.5, .5); collapseIcon.ZIndex = 6
    local collapsed = false
    local function setBodyCollapsed(value)
        collapsed = value == true
        body.Visible = not collapsed -- AutomaticSize excludes invisible children, so the card just shrinks to header height
    end
    connect(collapseButton.MouseButton1Click, function() setBodyCollapsed(not collapsed) end)

    card.Frame, card.Header, card.Body, card.Layout, card.CollapseButton = frame, header, body, layout, collapseButton
    function card:SetCollapsed(value) setBodyCollapsed(value) end
    function card:IsCollapsed() return collapsed end
    table.insert(tab.Cards, card)
    return card
end

function Library:Card(tab, options) return createCard(tab, options) end
function Library:Section(tab, options) return createCard(tab, options) end

function Library:ESPPreview(tab, options)
    options=options or {}
    local card=createCard(tab,{Title=options.Title or "ESP Preview",Side=options.Side or "left"})
    local preview=create("Frame",{BackgroundColor3=Color3.fromRGB(13,12,27),BorderSizePixel=0,Size=UDim2.new(1,0,0,220)}); preview.Parent=card.Body; addRound(preview,9); stroke(preview,T.Accent,1,.55)
    local caption=label(preview,"PREVIEW",12,Enum.Font.BuilderSansExtraBold,T.Muted,Enum.TextXAlignment.Center); caption.Position=UDim2.fromOffset(0,8); caption.Size=UDim2.new(1,0,0,18)
    local viewport=create("ViewportFrame",{BackgroundTransparency=1,BorderSizePixel=0,Position=UDim2.fromOffset(0,25),Size=UDim2.new(1,0,1,-25),Ambient=Color3.fromRGB(170,160,220),LightColor=Color3.fromRGB(255,255,255),LightDirection=Vector3.new(-1,-1,-1)}); viewport.Parent=preview
    local world=Instance.new("WorldModel"); world.Parent=viewport
    local camera=Instance.new("Camera"); camera.Parent=viewport; viewport.CurrentCamera=camera
    task.spawn(function()
        local ok,description=pcall(function() return Players:GetHumanoidDescriptionFromUserId((LocalPlayer and LocalPlayer.UserId) or 1) end)
        if not ok then return end
        local made,rig=pcall(function() return Players:CreateHumanoidModelFromDescription(description,Enum.HumanoidRigType.R6) end)
        if made and rig then
            rig.Parent=world
            local root=rig:FindFirstChild("HumanoidRootPart")
            if root then root.CFrame=CFrame.new(0,-2,0); camera.CFrame=CFrame.new(0,1.6,7)*CFrame.Angles(0,math.rad(180),0) end
        end
    end)
    return card
end

local ToggleOnColor = Color3.fromRGB(58, 137, 255)
local ToggleOffColor = Color3.fromRGB(58, 59, 64)
local ToggleKnobColor = Color3.fromRGB(240, 241, 245)

-- Shared "bind a key to this control" popup used by Toggle and Checkbox (keyboard icon in the row).
-- Borderless popup with a list of binds. Per bind: Mode (Toggle / Hold / Always), key, and target
-- value (On/Off) for Hold/Always. Toggle: key flips the control. Hold: control takes the value while
-- the key is held and returns to its previous value on release. Always: control is forced to the
-- value with no key needed, and returns to its previous value when the bind is removed/changed.
-- Multiple binds per control are allowed (multibind). Key handling lives in CreateWindow.
local function attachValueBindButton(library, row, control, xOffset, labelText)
    control.Binds = control.Binds or {}
    local button = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(26, 29), Position = UDim2.new(1, xOffset, 0, 0)})
    button.Parent = row
    local buttonIcon = icon(button, "keyboard", 15, T.Muted)
    buttonIcon.AnchorPoint = Vector2.new(.5, .5); buttonIcon.Position = UDim2.fromScale(.5, .5)

    -- Borderless popup (no outline), positioned from the keyboard button on every open.
    local popup = create("Frame", {BackgroundColor3 = Color3.fromRGB(22, 23, 27), BackgroundTransparency = .03, BorderSizePixel = 0, Size = UDim2.fromOffset(236, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 520})
    popup.Parent = library.Gui
    addRound(popup, 10); padding(popup, 10, 10, 10, 10)
    local popupLayout = create("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})
    popupLayout.Parent = popup

    local title = label(popup, "Bind: " .. tostring(labelText or "Value"), 13, Enum.Font.GothamBold)
    title.Size = UDim2.new(1, 0, 0, 16); title.LayoutOrder = 1; title.ZIndex = 521

    local rowsHolder = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 521})
    rowsHolder.Parent = popup
    local rowsLayout = create("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder})
    rowsLayout.Parent = rowsHolder

    local addButton = create("TextButton", {Text = "+ Add Bind", TextColor3 = T.Muted, TextSize = 13, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundColor3 = T.Surface3, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 3, ZIndex = 521})
    addButton.Parent = popup; addRound(addButton, 6)

    local entries = {}
    local modes = {"Toggle", "Hold", "Always"}

    -- the Keybinds HUD lists every control that has a key bound (all keys of it, e.g. "H/V")
    local hudName = tostring(labelText or "Value")
    local function syncHud()
        local hud = library.KeybindHUDInstance
        if not hud then return end
        local keys = {}
        for _, b in ipairs(control.Binds) do
            if b.Key and b.Mode ~= "Always" then table.insert(keys, b.Key.Name) end
        end
        if #keys == 0 then
            if hud.Rows[hudName] then hud:Remove(hudName) end
            return
        end
        local text = table.concat(keys, "/")
        if hud.Rows[hudName] then hud:SetKey(hudName, text) else hud:Add(hudName, text) end
        hud:SetActive(hudName, control.Value == true)
    end
    control.SyncBindHud = syncHud

    local function refreshTint()
        buttonIcon.ImageColor3 = (#control.Binds > 0) and T.Accent or T.Muted
        syncHud()
    end

    local function restoreIfActive(data)
        if data.Mode == "Always" and data.Active then
            data.Active = false
            control:Set(data.PriorValue)
        end
        if data.Mode == "Hold" and data.HoldActive then
            data.HoldActive = false
            control:Set(data.PriorValue)
        end
    end

    local function removeEntry(entry)
        restoreIfActive(entry.Data)
        for i, b in ipairs(control.Binds) do if b == entry.Data then table.remove(control.Binds, i) break end end
        for i, e in ipairs(entries) do if e == entry then table.remove(entries, i) break end end
        entry.Row:Destroy()
        refreshTint()
    end

    local function addEntry()
        local data = {Mode = "Toggle", Key = nil, Value = true, HoldActive = false, PriorValue = nil, Active = false}
        table.insert(control.Binds, data)

        local bindRow = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), ZIndex = 522})
        bindRow.Parent = rowsHolder
        local bindLayout = create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
        bindLayout.Parent = bindRow

        local keyButton = create("TextButton", {Text = "...", TextColor3 = T.Text, TextSize = 12, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundColor3 = T.Surface3, BorderSizePixel = 0, Size = UDim2.fromOffset(56, 26), LayoutOrder = 1, ZIndex = 523})
        keyButton.Parent = bindRow; addRound(keyButton, 6)
        local modeButton = create("TextButton", {Text = "Toggle", TextColor3 = T.Text, TextSize = 12, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundColor3 = T.Surface3, BorderSizePixel = 0, Size = UDim2.fromOffset(62, 26), LayoutOrder = 2, ZIndex = 523})
        modeButton.Parent = bindRow; addRound(modeButton, 6)
        local valueButton = create("TextButton", {Text = "On", TextColor3 = T.Text, TextSize = 12, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundColor3 = T.Surface3, BorderSizePixel = 0, Size = UDim2.fromOffset(42, 26), LayoutOrder = 3, Visible = false, ZIndex = 523})
        valueButton.Parent = bindRow; addRound(valueButton, 6)
        local removeButton = create("TextButton", {Text = "x", TextColor3 = T.Muted, TextSize = 14, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 26), LayoutOrder = 4, ZIndex = 523})
        removeButton.Parent = bindRow

        local entry = {Row = bindRow, Data = data}
        table.insert(entries, entry)

        connect(keyButton.MouseButton1Click, function()
            keyButton.Text = "..."
            local input = UserInputService.InputBegan:Wait()
            local chosen = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType
            data.Key = chosen
            keyButton.Text = chosen.Name
            syncHud()
        end)
        connect(modeButton.MouseButton1Click, function()
            restoreIfActive(data) -- leaving a mode puts the value back where it was
            local idx = (table.find(modes, data.Mode) or 1) % #modes + 1
            data.Mode = modes[idx]
            modeButton.Text = data.Mode
            syncHud()
            valueButton.Visible = data.Mode ~= "Toggle"
            keyButton.Visible = data.Mode ~= "Always"
            if data.Mode == "Always" then
                data.PriorValue = control.Value
                data.Active = true
                control:Set(data.Value)
            end
        end)
        connect(valueButton.MouseButton1Click, function()
            data.Value = not data.Value
            valueButton.Text = data.Value and "On" or "Off"
            if data.Mode == "Always" and data.Active then control:Set(data.Value) end
        end)
        connect(removeButton.MouseButton1Click, function() removeEntry(entry) end)
        refreshTint()
    end

    connect(addButton.MouseButton1Click, function()
        if #entries < 4 then addEntry() end
    end)

    local bindPopup = {Button = button, Popup = popup, Open = false}
    function bindPopup:Close()
        popup.Visible = false; self.Open = false
        if library.OpenBindPopup == self then library.OpenBindPopup = nil end
    end
    function bindPopup:OpenPopup()
        if library.OpenBindPopup and library.OpenBindPopup ~= self then library.OpenBindPopup:Close() end
        if library.OpenDropdown then library.OpenDropdown:Close() end
        if library.OpenColorPicker then library.OpenColorPicker:Close() end
        local p = button.AbsolutePosition - library.Gui.AbsolutePosition
        local viewW = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X or 1920
        local x = math.clamp(p.X - 205, 8, viewW - 236 - 8)
        popup.Position = UDim2.fromOffset(x, p.Y + button.AbsoluteSize.Y + 6)
        popup.Visible = true; self.Open = true; library.OpenBindPopup = self
    end
    connect(button.MouseButton1Click, function()
        if bindPopup.Open then bindPopup:Close() else bindPopup:OpenPopup() end
    end)

    table.insert(library.ValueBinds, {Control = control, Binds = control.Binds})
    return button
end

local attachColorPicker -- defined with the ColorPicker control below

local function createToggleControl(card, options)
    options = type(options) == "string" and {Name = options} or (options or {})
    local state = options.Default == true
    local row = newRow(card, 29, "Toggle")
    local bindable = options.Bindable ~= false
    -- lay out right-to-left: [switch][keyboard bind icon][settings dots]
    local cursor = 38
    local bindX, settingsX
    if bindable then cursor = cursor + 4; bindX = -(cursor + 26); cursor = cursor + 26 end
    if options.Settings then cursor = cursor + 2; settingsX = -(cursor + 28); cursor = cursor + 28 end
    -- inline colour swatches (options.Colors) sit left of everything else
    local swatchRights = {}
    for i = 1, #(options.Colors or {}) do cursor = cursor + 5; swatchRights[i] = cursor; cursor = cursor + 22 end
    local text = label(row, options.Name or "Toggle", 16, Enum.Font.GothamMedium); text.Size = UDim2.new(1, -(cursor + 14), 1, 0)
    if options.Settings then
        local settingsButton = create("TextButton", {Text="⋯", TextColor3=T.Muted, TextSize=20, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.fromOffset(28,29), Position=UDim2.new(1,settingsX,0,0), AutoButtonColor=false})
        settingsButton.Parent = row
        connect(settingsButton.MouseButton1Click, function() safeCallback(options.Settings, row) end)
    end
    -- Pill-style switch: rounded track + sliding knob (instead of a checkbox)
    local track = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = state and ToggleOnColor or ToggleOffColor, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, 0, .5, 0), Size = UDim2.fromOffset(38, 22)})
    track.Parent = row; addRound(track, 11)
    local knob = create("Frame", {BackgroundColor3 = ToggleKnobColor, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, .5), Position = state and UDim2.new(1, -19, .5, 0) or UDim2.new(0, 3, .5, 0), Size = UDim2.fromOffset(16, 16)})
    knob.Parent = track; addRound(knob, 8)
    local control = {Row = row, Value = state, Binds = {}, Colors = {}}
    if bindable then attachValueBindButton(card.Tab.Library, row, control, bindX, options.Name) end
    for i, color in ipairs(options.Colors or {}) do
        control.Colors[i] = attachColorPicker(card.Tab.Library, row, color, UDim2.new(1, -swatchRights[i], .5, 0), UDim2.fromOffset(22, 16))
    end
    function control:Set(value, silent)
        state, self.Value = value == true, value == true
        local hud = card.Tab.Library.KeybindHUDInstance
        if hud and hud.Rows[tostring(options.Name or "Value")] then hud:SetActive(tostring(options.Name or "Value"), state) end
        tween(track, .16, {BackgroundColor3 = state and ToggleOnColor or ToggleOffColor})
        tween(knob, .16, {Position = state and UDim2.new(1, -19, .5, 0) or UDim2.new(0, 3, .5, 0)}, Enum.EasingStyle.Quad)
        if options.ShowInModuleList and card.Tab.Library.ModuleListControl then
            local modName = options.ModuleName or options.Name or "Toggle"
            if state then
                card.Tab.Library.ModuleListControl:Add(modName)
            else
                card.Tab.Library.ModuleListControl:Remove(modName)
            end
        end
        if not silent then
            if card.Tab.Library.SoundOnToggle then card.Tab.Library:PlayToggleSound() end
            safeCallback(options.Callback, state)
        end
    end
    connect(track.MouseButton1Click, function() control:Set(not state) end)
    card.SearchText ..= (options.Name or "Toggle") .. " "
    table.insert(card.Controls, control)
    if options.ShowInModuleList and state and card.Tab.Library.ModuleListControl then
        card.Tab.Library.ModuleListControl:Add(options.ModuleName or options.Name or "Toggle")
    end
    if options.Flag then card.Tab.Library.Flags[options.Flag] = control end
    return control
end

function Library:Toggle(card, options) return createToggleControl(card, options) end

-- Classic square checkbox (kept separate from the pill-style Toggle above).
local function createCheckboxControl(card, options)
    options = type(options) == "string" and {Name = options} or (options or {})
    local state = options.Default == true
    local row = newRow(card, 29, "Checkbox")
    local bindable = options.Bindable ~= false
    -- lay out right-to-left: [switch][keyboard bind icon][settings dots]
    local cursor = 25
    local bindX, settingsX
    if bindable then cursor = cursor + 4; bindX = -(cursor + 26); cursor = cursor + 26 end
    if options.Settings then cursor = cursor + 2; settingsX = -(cursor + 28); cursor = cursor + 28 end
    local text = label(row, options.Name or "Checkbox", 16, Enum.Font.GothamMedium); text.Size = UDim2.new(1, -(cursor + 14), 1, 0)
    if options.Settings then
        local settingsButton = create("TextButton", {Text="⋯", TextColor3=T.Muted, TextSize=20, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.fromOffset(28,29), Position=UDim2.new(1,settingsX,0,0), AutoButtonColor=false})
        settingsButton.Parent = row
        connect(settingsButton.MouseButton1Click, function() safeCallback(options.Settings, row) end)
    end
    local box = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = state and T.AccentDark or T.Surface3, BorderSizePixel = 0, Position = UDim2.new(1, -25, .5, -11), Size = UDim2.fromOffset(23, 23)})
    box.Parent = row; addRound(box, 6); stroke(box, state and T.Accent or T.Muted, 1, .25)
    local check=icon(box,"check",15,T.Text); check.AnchorPoint=Vector2.new(.5,.5); check.Position=UDim2.fromScale(.5,.5); check.Visible=state
    local control = {Row = row, Value = state, Binds = {}}
    if bindable then attachValueBindButton(card.Tab.Library, row, control, bindX, options.Name) end
    function control:Set(value, silent)
        state, self.Value = value == true, value == true
        local hud = card.Tab.Library.KeybindHUDInstance
        if hud and hud.Rows[tostring(options.Name or "Value")] then hud:SetActive(tostring(options.Name or "Value"), state) end
        check.Visible = state
        tween(box, .15, {BackgroundColor3 = state and T.AccentDark or T.Surface3})
        if options.ShowInModuleList and card.Tab.Library.ModuleListControl then
            local modName = options.ModuleName or options.Name or "Checkbox"
            if state then
                card.Tab.Library.ModuleListControl:Add(modName)
            else
                card.Tab.Library.ModuleListControl:Remove(modName)
            end
        end
        if not silent then
            if card.Tab.Library.SoundOnToggle then card.Tab.Library:PlayToggleSound() end
            safeCallback(options.Callback, state)
        end
    end
    connect(box.MouseButton1Click, function() control:Set(not state) end)
    card.SearchText ..= (options.Name or "Checkbox") .. " "
    table.insert(card.Controls, control)
    if options.ShowInModuleList and state and card.Tab.Library.ModuleListControl then
        card.Tab.Library.ModuleListControl:Add(options.ModuleName or options.Name or "Checkbox")
    end
    if options.Flag then card.Tab.Library.Flags[options.Flag] = control end
    return control
end

function Library:Checkbox(card, options) return createCheckboxControl(card, options) end

local function createSlider(card, options)
    options = options or {}; local minimum, maximum = options.Min or 0, options.Max or 100
    local value = math.clamp(options.Default or minimum, minimum, maximum)
    local row = newRow(card, 48, "Slider")
    local text = label(row, options.Name or "Slider", 16, Enum.Font.GothamMedium); text.Size = UDim2.new(1, -70, 0, 23)
    local valueText = label(row, tostring(value) .. (options.Suffix or ""), 15, Enum.Font.GothamBold, T.Text, Enum.TextXAlignment.Right)
    valueText.Position = UDim2.new(1, -70, 0, 0); valueText.Size = UDim2.fromOffset(70, 23)
    local bar = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(150, 150, 162), BorderSizePixel = 0, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 9)})
    bar.Parent = row; addRound(bar, 5)
    local fill = create("Frame", {BackgroundColor3 = T.AccentDark, BorderSizePixel = 0, Size = UDim2.fromScale((value-minimum)/(maximum-minimum), 1)})
    fill.Parent = bar; addRound(fill, 5)
    local control = {Row = row, Value = value}
    function control:Set(newValue, silent)
        local step = options.Step or 1
        newValue = math.clamp(math.floor((newValue / step) + .5) * step, minimum, maximum)
        value, self.Value = newValue, newValue
        valueText.Text = tostring(newValue) .. (options.Suffix or "")
        tween(fill, .08, {Size = UDim2.fromScale((newValue-minimum)/(maximum-minimum), 1)})
        if not silent then safeCallback(options.Callback, newValue) end
    end
    local sliding = false
    local function update(input)
        local alpha = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        control:Set(minimum + (maximum - minimum) * alpha)
    end
    connect(bar.InputBegan, function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then sliding = true; update(input) end end)
    connect(UserInputService.InputChanged, function(input) if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then update(input) end end)
    connect(UserInputService.InputEnded, function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then sliding = false end end)
    card.SearchText ..= (options.Name or "Slider") .. " "; table.insert(card.Controls, control)
    if options.Flag then card.Tab.Library.Flags[options.Flag] = control end
    return control
end

function Library:Slider(card, options) return createSlider(card, options) end

local function createButton(card, options)
    options = type(options) == "string" and {Name = options} or (options or {})
    local row = newRow(card, 30, "Button")
    local background = create("Frame", {BackgroundColor3=options.Disabled and Color3.fromRGB(100,100,105) or T.AccentDark, BorderSizePixel=0, Size=UDim2.fromScale(1,1)}); background.Parent=row; addRound(background,6); gradient(background, background.BackgroundColor3, options.Disabled and Color3.fromRGB(140,140,142) or Color3.fromRGB(120,122,128),90)
    local button = create("TextButton", {Text = options.Name or "Click me!", TextColor3 = options.Disabled and T.Muted or T.Text, TextSize = 15, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundTransparency=1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex=background.ZIndex+1})
    button.Parent = background
    connect(button.MouseButton1Click, function() if not options.Disabled then tween(background, .07, {BackgroundColor3 = T.Accent}); task.delay(.08, function() tween(background, .12, {BackgroundColor3 = T.AccentDark}) end); safeCallback(options.Callback) end end)
    card.SearchText ..= (options.Name or "Button") .. " "; local control = {Row = row, Button = button}; table.insert(card.Controls, control); return control
end

function Library:Button(card, options) return createButton(card, options) end

local function createTextbox(card, options)
    options = options or {}; local row = newRow(card, 31, "Textbox")
    local text = label(row, options.Name or "TextBox", 16, Enum.Font.GothamMedium); text.Size = UDim2.new(.42, 0, 1, 0)
    local box = create("TextBox", {Text = options.Default or "", PlaceholderText = options.Placeholder or "text...", PlaceholderColor3 = T.Muted, TextColor3 = T.Text, TextSize = 14, Font = Enum.Font.GothamMedium, ClearTextOnFocus = false, BackgroundColor3 = Color3.fromRGB(67,65,68), BorderSizePixel = 0, Position = UDim2.new(.42, 0, 0, 1), Size = UDim2.new(.58, 0, 1, -2)})
    box.Parent = row; addRound(box, 6); padding(box, 7, 7, 0, 0); stroke(box, T.Muted, 1, .45)
    local control = {Row = row, Value = box.Text}
    function control:Set(value, silent) box.Text = tostring(value); self.Value = box.Text; if not silent then safeCallback(options.Callback, box.Text) end end
    connect(box.FocusLost, function(enter) control.Value = box.Text; safeCallback(options.Callback, box.Text, enter) end)
    card.SearchText ..= (options.Name or "Textbox") .. " "; table.insert(card.Controls, control); if options.Flag then card.Tab.Library.Flags[options.Flag] = control end; return control
end

function Library:Textbox(card, options) return createTextbox(card, options) end

-- Colour swatch + HSV popup inside an existing row. Used by ColorPicker rows and by the inline swatches of
-- Toggle (options.Colors) and Label rows. position/size place the swatch (AnchorPoint is the right-middle).
attachColorPicker = function(library, row, options, position, size)
    options=options or {}; local value=options.Default or T.Accent
    local h,s,v=value:ToHSV()
    local swatch=create("TextButton",{Text="",AutoButtonColor=false,BackgroundColor3=value,BorderSizePixel=0,AnchorPoint=Vector2.new(1,.5),Position=position,Size=size}); swatch.Parent=row; addRound(swatch,5); stroke(swatch,T.Text,1,.6)
    local popup=create("Frame",{BackgroundColor3=T.Surface2,BorderSizePixel=0,Size=UDim2.fromOffset(260,220),Visible=false,ZIndex=500}); popup.Parent=library.Gui; addRound(popup,12); stroke(popup,T.Accent,1,.3)
    local drag=label(popup,options.Name or "Color Picker",15,Enum.Font.GothamBold); drag.Position=UDim2.fromOffset(12,4); drag.Size=UDim2.new(1,-24,0,28); drag.ZIndex=501; drag.Active=true; dragify(drag,popup)
    local sv=create("TextButton",{Text="",AutoButtonColor=false,BackgroundColor3=Color3.fromHSV(h,1,1),BorderSizePixel=0,Position=UDim2.fromOffset(12,36),Size=UDim2.fromOffset(205,132),ZIndex=501}); sv.Parent=popup; addRound(sv,7); stroke(sv,Color3.fromRGB(95,97,102),1,.25)
    local white=create("Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=0,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=502}); white.Parent=sv; addRound(white,7)
    local whiteGrad=create("UIGradient",{Color=ColorSequence.new(Color3.new(1,1,1),Color3.new(1,1,1)),Transparency=NumberSequence.new(0,1)}); whiteGrad.Parent=white
    local black=create("Frame",{BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=503}); black.Parent=sv; addRound(black,7); local blackGrad=create("UIGradient",{Rotation=90,Color=ColorSequence.new(Color3.new(0,0,0),Color3.new(0,0,0)),Transparency=NumberSequence.new(1,0)}); blackGrad.Parent=black
    local svMarker=create("Frame",{BackgroundColor3=T.Text,BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(s,0,1-v,0),Size=UDim2.fromOffset(9,9),ZIndex=504}); svMarker.Parent=sv; addRound(svMarker,9); stroke(svMarker,T.Stroke,1)
    local hue=create("TextButton",{Text="",AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Position=UDim2.fromOffset(226,36),Size=UDim2.fromOffset(22,132),ZIndex=501}); hue.Parent=popup; addRound(hue,7)
    create("UIGradient",{Rotation=90,Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromHSV(0,1,1)),ColorSequenceKeypoint.new(.17,Color3.fromHSV(.17,1,1)),ColorSequenceKeypoint.new(.33,Color3.fromHSV(.33,1,1)),ColorSequenceKeypoint.new(.5,Color3.fromHSV(.5,1,1)),ColorSequenceKeypoint.new(.67,Color3.fromHSV(.67,1,1)),ColorSequenceKeypoint.new(.83,Color3.fromHSV(.83,1,1)),ColorSequenceKeypoint.new(1,Color3.fromHSV(1,1,1))})}).Parent=hue
    local hueMarker=create("Frame",{BackgroundColor3=T.Text,BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,h,0),Size=UDim2.fromOffset(28,4),ZIndex=504}); hueMarker.Parent=hue; addRound(hueMarker,3); stroke(hueMarker,T.Stroke,1)
    local hex=create("TextBox",{Text="",ClearTextOnFocus=false,TextColor3=T.Text,TextSize=14,Font=Enum.Font.Code,BackgroundColor3=T.Surface3,BorderSizePixel=0,Position=UDim2.fromOffset(12,178),Size=UDim2.fromOffset(236,30),ZIndex=501}); hex.Parent=popup; addRound(hex,7)
    local control={Row=row,Value=value,Swatch=swatch,Popup=popup,Open=false}
    function control:Set(color,silent)
        if typeof(color)~="Color3" then return end
        value,self.Value=color,color
        -- Bug fix: Color3:ToHSV() returns hue=0 (red) for any color with ~0 saturation (white/gray),
        -- since hue is mathematically undefined there. Re-deriving h unconditionally on every Set()
        -- meant dragging into the white corner (or a white hex code) silently reset the hue slider
        -- to red. Only trust the new hue when the color is actually saturated enough to have one.
        local nh,ns,nv=color:ToHSV()
        if ns>0.02 then h=nh end
        s,v=ns,nv
        swatch.BackgroundColor3=color; sv.BackgroundColor3=Color3.fromHSV(h,1,1); svMarker.Position=UDim2.new(s,0,1-v,0); hueMarker.Position=UDim2.new(.5,0,h,0)
        hex.Text=string.format("#%02X%02X%02X",math.floor(color.R*255+.5),math.floor(color.G*255+.5),math.floor(color.B*255+.5))
        if not silent then safeCallback(options.Callback,color) end
    end
    function control:Close() popup.Visible=false; self.Open=false; if library.OpenColorPicker==self then library.OpenColorPicker=nil end end
    function control:OpenPopup() if library.OpenColorPicker and library.OpenColorPicker~=self then library.OpenColorPicker:Close() end; if library.OpenDropdown then library.OpenDropdown:Close() end; local p=swatch.AbsolutePosition-library.Gui.AbsolutePosition; popup.Position=UDim2.fromOffset(math.max(8,p.X-225),p.Y+38); popup.Visible=true; self.Open=true; library.OpenColorPicker=self end
    local mode
    local function pick(input) if mode=="sv" then s=math.clamp((input.Position.X-sv.AbsolutePosition.X)/sv.AbsoluteSize.X,0,1); v=1-math.clamp((input.Position.Y-sv.AbsolutePosition.Y)/sv.AbsoluteSize.Y,0,1) else h=math.clamp((input.Position.Y-hue.AbsolutePosition.Y)/hue.AbsoluteSize.Y,0,1); sv.BackgroundColor3=Color3.fromHSV(h,1,1) end; control:Set(Color3.fromHSV(h,s,v)) end
    connect(sv.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 then mode="sv"; pick(input) end end); connect(hue.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 then mode="hue"; pick(input) end end)
    connect(UserInputService.InputChanged,function(input) if mode and input.UserInputType==Enum.UserInputType.MouseMovement then pick(input) end end); connect(UserInputService.InputEnded,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 then mode=nil end end)
    connect(hex.FocusLost,function() local raw=hex.Text:gsub("#",""); if #raw==6 then local n=tonumber(raw,16); if n then control:Set(Color3.fromRGB(math.floor(n/65536)%256,math.floor(n/256)%256,n%256)); return end end; control:Set(value,true) end)
    connect(swatch.MouseButton1Click,function() if control.Open then control:Close() else control:OpenPopup() end end)
    control:Set(value,true); return control
end

local function createColorPicker(card, options)
    options=options or {}
    local row=newRow(card,36,"ColorPicker")
    local text=label(row,options.Name or "Color",16,Enum.Font.GothamMedium); text.Size=UDim2.new(1,-48,1,0)
    local control=attachColorPicker(card.Tab.Library,row,options,UDim2.new(1,-3,.5,0),UDim2.fromOffset(31,29))
    card.SearchText ..=(options.Name or "Color").." "; table.insert(card.Controls,control); return control
end

function Library:ColorPicker(card,options) return createColorPicker(card,options) end

-- Text row with colour swatches on the right (femhax-style label():colorpicker()).
-- options.Colors = {{Name, Default, Callback}, ...}
local INLINE_SWATCH_W, INLINE_SWATCH_H, INLINE_SWATCH_GAP = 22, 16, 5
local function createLabel(card, options)
    options = type(options) == "string" and {Name = options} or (options or {})
    local row = newRow(card, 29, "Label")
    local colors = options.Colors or {}
    local width = #colors * (INLINE_SWATCH_W + INLINE_SWATCH_GAP)
    local text = label(row, options.Name or "Label", 16, Enum.Font.GothamMedium); text.Size = UDim2.new(1, -(width + 8), 1, 0)
    local control = {Row = row, Colors = {}}
    for i, color in ipairs(colors) do
        local right = (i - 1) * (INLINE_SWATCH_W + INLINE_SWATCH_GAP)
        control.Colors[i] = attachColorPicker(card.Tab.Library, row, color, UDim2.new(1, -right, .5, 0), UDim2.fromOffset(INLINE_SWATCH_W, INLINE_SWATCH_H))
    end
    card.SearchText ..= (options.Name or "Label") .. " "
    table.insert(card.Controls, control)
    return control
end

function Library:Label(card, options) return createLabel(card, options) end

-- Dark glow behind floating elements (HUD, menus, popups). Roblox has no box-shadow or blur, so it is built
-- from stacked rounded layers that fade out evenly on every side. The layers are siblings in the ScreenGui
-- (a child always draws above its parent's background) and follow the element's absolute position, size,
-- visibility and, for CanvasGroups, its fade every frame.
local GLOW_LAYERS, GLOW_STEP, GLOW_BASE, GLOW_FADE = 7, 2, .76, .03
local GLOW_COLOR = Color3.fromRGB(6, 6, 9)

local function hudBackdrop(library, frame, radius, zBase)
    zBase = zBase or frame.ZIndex
    local layers = {}
    for i = 1, GLOW_LAYERS do
        local pad = i * GLOW_STEP
        local base = GLOW_BASE + i * GLOW_FADE
        local layer = create("Frame", {Name = "Glow" .. i, BackgroundColor3 = GLOW_COLOR, BackgroundTransparency = base, BorderSizePixel = 0, ZIndex = math.max(1, zBase - i), Visible = false})
        layer.Parent = library.Gui
        addRound(layer, radius + pad)
        table.insert(layers, {Frame = layer, Pad = pad, Base = base})
    end
    local wasShown = false
    connect(RunService.RenderStepped, function()
        -- Shown only while the element and every container above it are visible
        local shown = frame.Parent ~= nil
        local node = frame
        while shown and node and node ~= library.Gui do
            if node:IsA("GuiObject") and not node.Visible then shown = false end
            node = node.Parent
        end
        if not shown and not wasShown then return end
        wasShown = shown
        -- AbsolutePosition starts below the topbar inset while this ScreenGui ignores the inset,
        -- so positions are taken relative to the ScreenGui itself
        local pos, size = frame.AbsolutePosition - library.Gui.AbsolutePosition, frame.AbsoluteSize
        local fade = frame:IsA("CanvasGroup") and frame.GroupTransparency or 0
        for _, layer in ipairs(layers) do
            local p = layer.Pad
            layer.Frame.Visible = shown
            if shown then
                layer.Frame.Position = UDim2.fromOffset(pos.X - p, pos.Y - p)
                layer.Frame.Size = UDim2.fromOffset(size.X + p * 2, size.Y + p * 2)
                layer.Frame.BackgroundTransparency = layer.Base + (1 - layer.Base) * fade
            end
        end
    end)
    return layers
end

-- Position of a GUI object inside the library ScreenGui (corrects for the topbar inset, see hudBackdrop)
local function guiPosition(library, object)
    return object.AbsolutePosition - library.Gui.AbsolutePosition
end

local DROPDOWN_ITEM_H, DROPDOWN_PAD = 28, 4

local function createDropdown(card, options)
    options = options or {}
    local library = card.Tab.Library
    local values = options.Values or {}
    local multi = options.Multi == true
    local selected = multi and (options.Default or {}) or (options.Default or values[1])

    local row = newRow(card, 31, "Dropdown")
    local text = label(row, options.Name or "Dropdown", 16, Enum.Font.GothamMedium)
    text.Size = UDim2.new(.48, 0, 1, 0)

    local button = create("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(34, 36, 41), BorderSizePixel = 0,
        Position = UDim2.new(.48, 0, 0, 1), Size = UDim2.new(.52, 0, 1, -2), ZIndex = 5,
    })
    button.Parent = row; addRound(button, 6); stroke(button, Color3.fromRGB(255, 255, 255), 1, .9)

    local buttonText = label(button, "", 13, Enum.Font.GothamMedium, T.Text)
    buttonText.Size = UDim2.new(1, -30, 1, 0); buttonText.Position = UDim2.fromOffset(9, 0)
    buttonText.TextTruncate = Enum.TextTruncate.AtEnd; buttonText.ZIndex = 6
    local chevron = icon(button, "chevron-down", 13, T.Muted)
    chevron.AnchorPoint = Vector2.new(1, .5); chevron.Position = UDim2.new(1, -8, .5, 0); chevron.ZIndex = 6

    -- Popup: lives on the ScreenGui (above every card), is placed from the button each time it opens and
    -- unrolls from the button edge. Dark panel with the same glow as the HUD.
    local menu = create("Frame", {
        Name = "DropdownMenu", BackgroundColor3 = Color3.fromRGB(18, 19, 23), BorderSizePixel = 0,
        Size = UDim2.fromOffset(160, 0), Visible = false, ZIndex = 450, ClipsDescendants = true,
    })
    menu.Parent = library.Gui
    addRound(menu, 8)
    hudBackdrop(library, menu, 8)
    local menuScroll = create("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 2, ScrollBarImageColor3 = T.Muted, ScrollBarImageTransparency = .4, ZIndex = 451,
    })
    menuScroll.Parent = menu
    padding(menuScroll, DROPDOWN_PAD, DROPDOWN_PAD, DROPDOWN_PAD, DROPDOWN_PAD)

    -- Search box on top of longer lists: typing keeps only the options that contain the text
    local SEARCH_H = 26
    local searchBox = create("TextBox", {
        Text = "", PlaceholderText = "Search...", PlaceholderColor3 = T.Muted, ClearTextOnFocus = false,
        TextColor3 = T.Text, TextSize = 13, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundColor3 = Color3.fromRGB(30, 32, 37), BorderSizePixel = 0, Visible = false, ZIndex = 452,
        Position = UDim2.fromOffset(DROPDOWN_PAD, DROPDOWN_PAD), Size = UDim2.new(1, -DROPDOWN_PAD * 2, 0, SEARCH_H),
    })
    searchBox.Parent = menu; addRound(searchBox, 5); padding(searchBox, 8, 8, 0, 0)
    local query = ""
    local function searchable() return options.Search == true or (options.Search ~= false and #values > 5) end
    local menuLayout = create("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder})
    menuLayout.Parent = menuScroll

    local control = {Row = row, Button = button, Menu = menu, Value = selected, Open = false, Choices = {}}
    local BOX_OFF = Color3.fromRGB(40, 42, 48)

    -- Multi: up to two names, then "+N"
    local function selectedText()
        if not multi then return tostring(selected or "Select") end
        local list = {}
        for _, v in ipairs(values) do if selected[v] then table.insert(list, tostring(v)) end end
        if #list == 0 then return "None" end
        if #list <= 2 then return table.concat(list, ", ") end
        return list[1] .. ", " .. list[2] .. "  +" .. (#list - 2)
    end

    local function paintChoice(value, choice, instant)
        local isSel = (multi and selected[value] == true) or (not multi and selected == value)
        local t = instant and 0 or .12
        tween(choice.Text, t, {TextColor3 = isSel and T.Text or T.Muted})
        tween(choice.Mark, t, {ImageTransparency = isSel and 0 or 1})
        if choice.Box then tween(choice.Box, t, {BackgroundColor3 = isSel and T.Accent or BOX_OFF}) end
    end

    local function refreshChoices(instant)
        for value, choice in pairs(control.Choices) do paintChoice(value, choice, instant) end
        buttonText.Text = selectedText()
    end

    local function shownCount()
        local count = 0
        local q = string.lower(query)
        for value, choice in pairs(control.Choices) do
            local show = q == "" or string.find(string.lower(tostring(value)), q, 1, true) ~= nil
            choice.Button.Visible = show
            if show then count += 1 end
        end
        return count
    end

    local function menuHeight(count)
        local head = searchable() and (SEARCH_H + DROPDOWN_PAD) or 0
        return head + math.max(math.min(count, 7), 1) * (DROPDOWN_ITEM_H + 2) + DROPDOWN_PAD * 2
    end

    function control:Close()
        if not self.Open then return end
        self.Open = false
        menu.Visible = false
        tween(chevron, .12, {Rotation = 0})
        if library.OpenDropdown == self then library.OpenDropdown = nil end
    end

    function control:OpenPopup()
        if options.OnOpen then safeCallback(options.OnOpen, self) end
        if library.OpenDropdown and library.OpenDropdown ~= self then library.OpenDropdown:Close() end
        if library.OpenColorPicker then library.OpenColorPicker:Close() end
        if library.OpenBindPopup then library.OpenBindPopup:Close() end

        local p = guiPosition(library, button)
        local w = button.AbsoluteSize.X
        local withSearch = searchable()
        query = ""; searchBox.Text = ""
        searchBox.Visible = withSearch
        menuScroll.Position = UDim2.fromOffset(0, withSearch and (SEARCH_H + DROPDOWN_PAD) or 0)
        menuScroll.Size = UDim2.new(1, 0, 1, withSearch and -(SEARCH_H + DROPDOWN_PAD) or 0)
        local naturalH = menuHeight(shownCount())
        -- Flip upward if there isn't room below the button on screen.
        local viewH = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 1080
        local below = p.Y + button.AbsoluteSize.Y + 4
        local openUp = (below + naturalH) > viewH - 8
        menu.Size = UDim2.fromOffset(w, 0)
        menu.Position = UDim2.fromOffset(p.X, openUp and (p.Y - 4) or below)
        menu.Visible = true
        local goal = {Size = UDim2.fromOffset(w, naturalH)}
        if openUp then goal.Position = UDim2.fromOffset(p.X, p.Y - naturalH - 4) end
        tween(menu, .14, goal, Enum.EasingStyle.Quint)
        tween(chevron, .12, {Rotation = 180})
        self.Open = true
        self._openUp, self._anchorY = openUp, p.Y
        library.OpenDropdown = self
    end

    connect(searchBox:GetPropertyChangedSignal("Text"), function()
        query = searchBox.Text
        if not control.Open then return end
        local h = menuHeight(shownCount())
        local w = menu.AbsoluteSize.X
        menu.Size = UDim2.fromOffset(w, h)
        if control._openUp then menu.Position = UDim2.fromOffset(menu.Position.X.Offset, control._anchorY - h - 4) end
        menuScroll.CanvasPosition = Vector2.zero
    end)

    function control:Set(value, silent)
        selected, self.Value = value, value
        refreshChoices()
        if not multi then self:Close() end
        if not silent then safeCallback(options.Callback, value) end
    end

    -- Multi: check box on the left. Single: check mark on the right of the chosen value.
    local function addChoice(value)
        local choice = {}
        local rowButton = create("TextButton", {
            Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 1,
            BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, DROPDOWN_ITEM_H), ZIndex = 452,
        })
        rowButton.Parent = menuScroll; addRound(rowButton, 5)
        local textX = 9
        if multi then
            local box = create("Frame", {BackgroundColor3 = BOX_OFF, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 8, .5, 0), Size = UDim2.fromOffset(14, 14), ZIndex = 453})
            box.Parent = rowButton; addRound(box, 4)
            local mark = icon(box, "check", 10, Color3.fromRGB(18, 19, 23))
            mark.AnchorPoint = Vector2.new(.5, .5); mark.Position = UDim2.fromScale(.5, .5); mark.ZIndex = 454
            choice.Box, choice.Mark = box, mark
            textX = 30
        else
            local mark = icon(rowButton, "check", 12, T.Accent)
            mark.AnchorPoint = Vector2.new(1, .5); mark.Position = UDim2.new(1, -8, .5, 0); mark.ZIndex = 453
            choice.Mark = mark
        end
        local text = label(rowButton, tostring(value), 13, Enum.Font.GothamMedium, T.Muted)
        text.Position = UDim2.fromOffset(textX, 0); text.Size = UDim2.new(1, -textX - 26, 1, 0)
        text.TextTruncate = Enum.TextTruncate.AtEnd; text.ZIndex = 453
        choice.Button, choice.Text = rowButton, text
        control.Choices[value] = choice
        connect(rowButton.MouseEnter, function() tween(rowButton, .1, {BackgroundTransparency = .94}) end)
        connect(rowButton.MouseLeave, function() tween(rowButton, .1, {BackgroundTransparency = 1}) end)
        connect(rowButton.MouseButton1Click, function()
            if multi then
                selected[value] = not selected[value]
                control:Set(selected)
            else
                control:Set(value)
            end
        end)
        paintChoice(value, choice, true)
    end
    for _, value in ipairs(values) do addChoice(value) end

    -- Replaces the option list (for dropdowns whose options come from a folder)
    function control:SetValues(list)
        for _, choice in pairs(self.Choices) do choice.Button:Destroy() end
        table.clear(self.Choices)
        values = list or {}
        for _, value in ipairs(values) do addChoice(value) end
        if not multi and not table.find(values, selected) then
            selected = values[1]
            self.Value = selected
        end
        refreshChoices()
    end
    refreshChoices(true)
    connect(button.MouseButton1Click, function()
        if control.Open then control:Close() else control:OpenPopup() end
    end)

    card.SearchText ..= (options.Name or "Dropdown") .. " " .. table.concat(values, " ") .. " "
    table.insert(card.Controls, control)
    if options.Flag then library.Flags[options.Flag] = control end
    return control
end

function Library:Dropdown(card, options) return createDropdown(card, options) end

local function createKeybind(card, options)
    options = options or {}; local key = options.Default or Enum.KeyCode.Unknown
    local row = newRow(card, 31, "Keybind"); row.ZIndex = 4
    local text = label(row, options.Name or "Keybind", 16, Enum.Font.GothamMedium); text.Size = UDim2.new(1, -100, 1, 0)
    local button = create("TextButton", {Text = key.Name, TextColor3 = T.Text, TextSize = 14, Font = Enum.Font.GothamBold, AutoButtonColor = false, BackgroundColor3 = T.Surface3, BorderSizePixel = 0, Position = UDim2.new(1, -96, 0, 1), Size = UDim2.fromOffset(96, 29)})
    button.Parent = row; addRound(button, 7)
    local control = {Row = row, Key = key, Callback = options.Callback, Held = false}
    if card.Tab.Library.KeybindHUDInstance and key ~= Enum.KeyCode.Unknown then
        card.Tab.Library.KeybindHUDInstance:Add(options.Name or "Keybind", key.Name)
    end
    connect(button.MouseButton1Click, function()
        button.Text = "..."
        local input = UserInputService.InputBegan:Wait()
        key = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType
        control.Key = key; button.Text = key.Name
        if card.Tab.Library.KeybindHUDInstance then
            card.Tab.Library.KeybindHUDInstance:Remove(options.Name or "Keybind")
            if key ~= Enum.KeyCode.Unknown then
                card.Tab.Library.KeybindHUDInstance:Add(options.Name or "Keybind", key.Name)
            end
        end
        safeCallback(options.Changed, key)
    end)
    connect(UserInputService.InputBegan, function(input, processed)
        local pressed = input.KeyCode == control.Key or input.UserInputType == control.Key
        if pressed and not processed then
            control.Held = true
            if card.Tab.Library.KeybindHUDInstance then
                card.Tab.Library.KeybindHUDInstance:SetActive(options.Name or "Keybind", true)
            end
            safeCallback(options.Callback, true)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        local released = input.KeyCode == control.Key or input.UserInputType == control.Key
        if released then
            control.Held = false
            if card.Tab.Library.KeybindHUDInstance then
                card.Tab.Library.KeybindHUDInstance:SetActive(options.Name or "Keybind", false)
            end
            safeCallback(options.Callback, false)
        end
    end)
    table.insert(card.Tab.Library.Keybinds, control); card.SearchText ..= (options.Name or "Keybind") .. " "; table.insert(card.Controls, control); return control
end

function Library:Keybind(card, options) return createKeybind(card, options) end

local function setHudStyle(frame, style)
    if not frame or typeof(frame)~="Instance" then return end
    if frame:IsA("TextLabel") or frame.Name=="Indicator" then frame.BackgroundTransparency=1; return end
    if frame.Name=="Watermark" then for _,child in ipairs(frame:GetChildren()) do if child.Name=="StyleTarget" then setHudStyle(child,style) end end; return end
    style=string.lower(style or "dark")
    for _,child in ipairs(frame:GetChildren()) do if child:IsA("UIGradient") then child:Destroy() end end
    if style=="glass" then frame.BackgroundTransparency=.16; frame.BackgroundColor3=Color3.fromRGB(94,90,112); gradient(frame,Color3.fromRGB(126,120,150),Color3.fromRGB(37,34,62),25); if not frame:FindFirstChildOfClass("UIStroke") then stroke(frame,T.Text,1,.75) end
    elseif style=="gradient" or style=="rarely" or style=="default" then frame.BackgroundTransparency=0; frame.BackgroundColor3=T.BackgroundStart; gradient(frame,T.BackgroundStart,T.BackgroundEnd,25)
    else frame.BackgroundTransparency=0; frame.BackgroundColor3=T.BackgroundStart; gradient(frame,T.BackgroundStart,T.BackgroundEnd,25) end
end

function Library:SetHUDStyle(frame, style)
    if type(frame)=="table" then frame=frame.Frame or frame.Instance end
    if frame and typeof(frame)=="Instance" and frame:IsA("GuiObject") then setHudStyle(frame,style) end
end

local HUD_MENU_TITLES = {Watermark = "Watermark", Keybinds = "Keybinds", Indicators = "Indicators", Crosshair = "Crosshair"}
local HUD_MENU_ICONS = {Watermark = "monitor", Keybinds = "keyboard", Indicators = "activity", Crosshair = "scan-eye"}
local WATERMARK_METRICS = {"FPS", "BPS", "TPS", "PING", "CPU", "RAM USAGE", "LOGIN"}

-- Right-click menu of a HUD element: a dark glowing panel with a titled header, check rows (watermark
-- metrics) and actions. Opening is detected from UserInputService instead of frame.InputBegan, so it works
-- no matter which child is under the cursor; the click that opens the menu is never taken as "outside".
local function attachHudMenu(library, frame, options)
    options = options or {}
    table.insert(library.HUDRegistry, {Frame = frame, Type = options.Element or "HUD"})
    frame.Active = true
    local homePosition = frame.Position
    local ROW_H = 28
    local order = 0
    local function nextOrder() order += 1; return order end

    local menu = create("CanvasGroup", {Name = "HUDContextMenu", BackgroundColor3 = Color3.fromRGB(16, 17, 21), BackgroundTransparency = .02, BorderSizePixel = 0, Size = UDim2.fromOffset(212, 0), AutomaticSize = Enum.AutomaticSize.Y, GroupTransparency = 1, Visible = false, ZIndex = 700})
    menu.Parent = library.Gui; addRound(menu, 9)
    padding(menu, 6, 6, 6, 6)
    local list = create("UIListLayout", {Padding = UDim.new(0, 2), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder})
    list.Parent = menu
    hudBackdrop(library, menu, 9)

    local header = create("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder()})
    header.Parent = menu
    local headerIcon = icon(header, HUD_MENU_ICONS[options.Element] or "layout-dashboard", 14, T.Accent)
    headerIcon.Position = UDim2.fromOffset(8, 8)
    local headerTitle = label(header, HUD_MENU_TITLES[options.Element] or tostring(options.Element or "HUD element"), 13, Enum.Font.GothamBold, T.Text)
    headerTitle.Position = UDim2.fromOffset(30, 0); headerTitle.Size = UDim2.new(1, -36, 1, 0)

    local function divider()
        local line = create("Frame", {BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = .92, BorderSizePixel = 0, Size = UDim2.new(1, -12, 0, 1), LayoutOrder = nextOrder()})
        line.Parent = menu
    end
    local function section(text)
        local caption = label(menu, string.upper(text), 10, Enum.Font.GothamBold, T.Muted)
        caption.Size = UDim2.new(1, 0, 0, 20); caption.LayoutOrder = nextOrder()
        padding(caption, 8, 8, 4, 0)
    end
    local function row(text, iconName)
        local b = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = nextOrder()})
        b.Parent = menu; addRound(b, 6)
        local x = 10
        if iconName then
            local image = icon(b, iconName, 14, T.Muted); image.Position = UDim2.fromOffset(9, (ROW_H - 14) / 2)
            x = 31
        end
        local text = label(b, text, 12, Enum.Font.GothamMedium, T.Text)
        text.Position = UDim2.fromOffset(x, 0); text.Size = UDim2.new(1, -x - 30, 1, 0)
        connect(b.MouseEnter, function() tween(b, .1, {BackgroundTransparency = .94}) end)
        connect(b.MouseLeave, function() tween(b, .1, {BackgroundTransparency = 1}) end)
        return b
    end
    local function checkRow(text, active, onToggle)
        local b = row(text)
        local box = create("Frame", {BackgroundColor3 = active and T.Accent or Color3.fromRGB(40, 42, 48), BorderSizePixel = 0, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -9, .5, 0), Size = UDim2.fromOffset(14, 14)})
        box.Parent = b; addRound(box, 4)
        local mark = icon(box, "check", 10, Color3.fromRGB(16, 17, 21))
        mark.AnchorPoint = Vector2.new(.5, .5); mark.Position = UDim2.fromScale(.5, .5); mark.ImageTransparency = active and 0 or 1
        connect(b.MouseButton1Click, function()
            active = not active
            tween(box, .12, {BackgroundColor3 = active and T.Accent or Color3.fromRGB(40, 42, 48)})
            tween(mark, .12, {ImageTransparency = active and 0 or 1})
            onToggle(active)
        end)
    end

    local function close()
        if not menu.Visible then return end
        menu.Visible = false
        menu.GroupTransparency = 1
        if library.OpenHUDMenu == menu then library.OpenHUDMenu = nil end
    end
    local function open()
        if library.OpenHUDMenu and library.OpenHUDMenu ~= menu then library.OpenHUDMenu.Visible = false end
        menu.Visible = true
        local view = workspace.CurrentCamera.ViewportSize
        local p, size = guiPosition(library, frame), menu.AbsoluteSize
        menu.Position = UDim2.fromOffset(math.clamp(p.X, 8, view.X - size.X - 8), math.clamp(p.Y + frame.AbsoluteSize.Y + 10, 8, view.Y - size.Y - 8))
        menu.GroupTransparency = 1
        tween(menu, .14, {GroupTransparency = 0})
        library.OpenHUDMenu = menu
    end

    if options.Element == "Watermark" then
        divider()
        section("Metrics")
        for _, name in ipairs(WATERMARK_METRICS) do
            checkRow(name, options["Show" .. name] ~= false, function(active)
                options["Show" .. name] = active
                if options.WatermarkControl then options.WatermarkControl:SetStat(name, active) end
            end)
        end
    end
    divider()
    section("Actions")
    connect(row("Reset position", "locate-fixed").MouseButton1Click, function() frame.Position = homePosition; close() end)
    connect(row("Hide element", "eye-off").MouseButton1Click, function() frame.Visible = false; close() end)

    local function inside(object, pos)
        local a, s = object.AbsolutePosition, object.AbsoluteSize
        return pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y
    end
    connect(UserInputService.InputBegan, function(input)
        local kind = input.UserInputType
        if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.MouseButton2 then return end
        local pos = Vector2.new(input.Position.X, input.Position.Y)
        local onFrame = frame.Visible and frame.Parent ~= nil and inside(frame, pos)
        if kind == Enum.UserInputType.MouseButton2 and onFrame then open(); return end
        if menu.Visible and not onFrame and not inside(menu, pos) then close() end
    end)
    return menu
end

function Library:Notify(options)
    options = type(options) == "string" and {Message = options} or (options or {})
    -- Hit-log notification: a translucent dark pill with a soft glow, one line "Title  message",
    -- the title tinted by the type and numbers in the message highlighted.
    do
        if not self.NotificationHolder then
            local holder=create("Frame",{Name="Notifications",BackgroundTransparency=1,AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-22,1,-22),Size=UDim2.fromOffset(420,460)}); holder.Parent=self.Gui
            local layout=create("UIListLayout",{Padding=UDim.new(0,10),VerticalAlignment=Enum.VerticalAlignment.Bottom,HorizontalAlignment=Enum.HorizontalAlignment.Right,SortOrder=Enum.SortOrder.LayoutOrder}); layout.Parent=holder; self.NotificationHolder=holder
        end
        local kind=string.lower(options.Type or "info")
        local colors={success=Color3.fromRGB(120,220,150),warning=Color3.fromRGB(240,200,110),error=Color3.fromRGB(240,105,125),info=T.Accent}
        local color=colors[kind] or colors.info
        local function hex(c) return string.format("#%02x%02x%02x",math.floor(c.R*255+.5),math.floor(c.G*255+.5),math.floor(c.B*255+.5)) end
        local function escape(text) return (string.gsub(string.gsub(string.gsub(tostring(text),"&","&amp;"),"<","&lt;"),">","&gt;")) end
        local titleText=options.Title or ({success="Success",warning="Warning",error="Error",info="Info"})[kind]
        local messageText=escape(options.Message or ({success="Function enabled.",warning="Please check this action.",error="An error occurred.",info="Information received."})[kind])
        messageText=string.gsub(messageText,"([%+%-]?%d[%d%.,]*)",'<font color="'..hex(color)..'">%1</font>')
        local rich='<b><font color="'..hex(color)..'">'..escape(titleText)..'</font></b>  '..messageText
        local HEIGHT=36
        local slot=create("Frame",{BackgroundTransparency=1,Size=UDim2.fromOffset(0,HEIGHT),AutomaticSize=Enum.AutomaticSize.X}); slot.Parent=self.NotificationHolder
        local pill=create("Frame",{Name="Notification",BackgroundColor3=Color3.fromRGB(12,13,16),BackgroundTransparency=.38,BorderSizePixel=0,Size=UDim2.fromOffset(0,HEIGHT),AutomaticSize=Enum.AutomaticSize.X,ZIndex=202}); pill.Parent=slot
        addRound(pill,HEIGHT/2); padding(pill,14,14,0,0)
        -- glow: rounded layers behind the pill, fading out (the pill does not clip, so they spill around it)
        local glows={}
        for i=1,5 do
            local pad=i*3
            local layer=create("Frame",{Name="Glow"..i,BackgroundColor3=Color3.fromRGB(0,0,0),BackgroundTransparency=.82+i*.03,BorderSizePixel=0,Position=UDim2.fromOffset(-14-pad,-pad),Size=UDim2.new(1,28+pad*2,1,pad*2),ZIndex=201-i})
            layer.Parent=pill; addRound(layer,HEIGHT/2+pad); glows[i]=layer
        end
        local text=label(pill,rich,16,Enum.Font.GothamBold,Color3.fromRGB(236,238,242)); text.RichText=true; text.AutomaticSize=Enum.AutomaticSize.X; text.Size=UDim2.fromOffset(0,HEIGHT); text.ZIndex=203
        local textStroke=create("UIStroke",{Color=Color3.fromRGB(0,0,0),Transparency=.55,Thickness=1}); textStroke.Parent=text
        local all={pill,text}; for _,g in ipairs(glows) do table.insert(all,g) end
        local function fade(t,out)
            for _,o in ipairs(all) do
                if o==text then tween(o,t,{TextTransparency=out and 1 or 0}) ; tween(textStroke,t,{Transparency=out and 1 or .55})
                elseif o==pill then tween(o,t,{BackgroundTransparency=out and 1 or .38})
                else local i=tonumber(string.match(o.Name,"%d+")); tween(o,t,{BackgroundTransparency=out and 1 or (.82+i*.03)}) end
            end
        end
        for _,o in ipairs(all) do if o==text then o.TextTransparency=1; textStroke.Transparency=1 else o.BackgroundTransparency=1 end end
        pill.Position=UDim2.fromOffset(40,0); tween(pill,.25,{Position=UDim2.fromOffset(0,0)},Enum.EasingStyle.Quint); fade(.2,false)
        local duration=options.Duration or 4
        task.delay(duration,function() if slot.Parent then fade(.3,true); tween(pill,.3,{Position=UDim2.fromOffset(40,0)},Enum.EasingStyle.Quint); task.wait(.32); slot:Destroy() end end)
        return pill
    end
    --[[ Previous notification implementation (including glass) is intentionally disabled.
    if not self.NotificationHolder then
        local holder = create("Frame", {Name = "Notifications", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -22, 1, -22), Size = UDim2.fromOffset(390, 500)})
        holder.Parent = self.Gui
        local layout = create("UIListLayout", {Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder})
        layout.Parent = holder; self.NotificationHolder = holder
    end
    local kind = string.lower(options.Type or "info")
    local colors = {success = T.Success, warning = T.Warning, error = T.Error, info = T.Info}
    local icons = {success = "circle-check", warning = "triangle-alert", error = "circle-x", info = "info"}
    local color = colors[kind] or T.Info
    local glass = string.lower(options.Style or "default") == "glass"
    local itemHeight=options.Title and 94 or 58
    local slot=create("Frame",{BackgroundTransparency=1,Size=UDim2.new(1,0,0,itemHeight)}); slot.Parent=self.NotificationHolder
    local item = create("Frame", {BackgroundColor3 = glass and Color3.fromRGB(94,90,112) or T.BackgroundStart, BackgroundTransparency=glass and .18 or 0, BorderSizePixel = 0, Position=UDim2.fromOffset(420,0), Size = UDim2.new(1, 0, 0, itemHeight), ClipsDescendants = true})
    item.Parent = slot; addRound(item, 15); stroke(item, T.Stroke, 1)
    if glass then gradient(item,Color3.fromRGB(120,116,140),Color3.fromRGB(45,42,65),25) end
    local image = icon(item, icons[kind] or "info", 26, T.Text); image.Position = UDim2.fromOffset(16, 15)
    local title = label(item, options.Title or ({success="Success", warning="Warning", error="Error", info="Information"})[kind], 17, Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(54, 8); title.Size = UDim2.new(1, -65, 0, 29)
    if options.Message then local message = label(item, options.Message, 14, Enum.Font.GothamMedium, T.Text); message.Position = UDim2.fromOffset(54, 37); message.Size = UDim2.new(1, -65, 0, 35); message.TextWrapped = true end
    local progressTrack = create("Frame", {BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=.86,BorderSizePixel=0,Position=UDim2.new(0,9,1,-9),Size=UDim2.new(1,-18,0,3)}); progressTrack.Parent=item; addRound(progressTrack,2)
    local progress = create("Frame", {BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0)}); progress.Parent = progressTrack; addRound(progress,2)
    tween(item, .28, {Position = UDim2.fromOffset(0, 0)}, Enum.EasingStyle.Back)
    local duration = options.Duration or 4; tween(progress, duration, {Size = UDim2.new(0, 0, 1, 0)}, Enum.EasingStyle.Linear)
    task.delay(duration, function() if item.Parent then tween(item, .25, {Position = UDim2.fromOffset(420, 0), BackgroundTransparency = 1}); task.wait(.26); slot:Destroy() end end)
    return item
    ]]
end

function Library:Watermark(options)
    options=options or {}; options.Element="Watermark"
    local defaults={"FPS","BPS","TPS","PING","CPU","RAM USAGE","LOGIN"}; local criteria=options.Criteria or defaults; local enabled=options.Enabled or {}
    for _,name in ipairs(defaults) do
        if enabled[name]==nil then enabled[name]=(name=="FPS" or name=="PING") end
        if options["Show"..name]==nil then options["Show"..name]=enabled[name] end
    end

    -- Translucent pill bar with a dark glow behind it and no outline; icons tint with the live theme accent.
    local BAR_HEIGHT = 26
    local TEXT_COLOR = Color3.fromRGB(226, 228, 233)

    local frame = create("Frame", {
        Name = "Watermark", BackgroundColor3 = Color3.fromRGB(15, 16, 19), BackgroundTransparency = .32,
        BorderSizePixel = 0, Position = options.Position or UDim2.fromOffset(20, 20),
        Size = UDim2.fromOffset(0, BAR_HEIGHT), AutomaticSize = Enum.AutomaticSize.X, Active = true, ZIndex = 200,
    })
    frame.Parent = self.Gui
    addRound(frame, BAR_HEIGHT / 2)
    hudBackdrop(self, frame, BAR_HEIGHT / 2)
    padding(frame, 12, 12, 0, 0)
    local barLayout = create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder})
    barLayout.Parent = frame

    -- Plain "RW" mark in its own fixed-size cell (kept separate from the auto-sizing bar layout).
    local logoCell = create("Frame", {Name = "Logo", BackgroundTransparency = 1, Size = UDim2.fromOffset(24, BAR_HEIGHT), LayoutOrder = 1, ZIndex = 201})
    logoCell.Parent = frame
    local logo = label(logoCell, "RW", 13, Enum.Font.GothamBlack, Color3.fromRGB(240, 242, 247), Enum.TextXAlignment.Center)
    logo.Size = UDim2.fromScale(1, 1); logo.ZIndex = 202

    local afterLogoDivider = create("Frame", {BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = .84, BorderSizePixel = 0, Size = UDim2.fromOffset(1, 12), LayoutOrder = 2, ZIndex = 202})
    afterLogoDivider.Parent = frame

    local statIcons = {FPS = "monitor", BPS = "activity", TPS = "gauge", PING = "wifi", CPU = "cpu", ["RAM USAGE"] = "memory-stick", LOGIN = "user"}
    local cells = {}
    for index, name in ipairs(criteria) do
        local key = string.upper(name)
        local divider = nil
        if index > 1 then
            divider = create("Frame", {Name = key .. "_Divider", BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = .88, BorderSizePixel = 0, Size = UDim2.fromOffset(1, 12), LayoutOrder = index * 10 + 1, Visible = false, ZIndex = 202})
            divider.Parent = frame
        end
        local cell = create("Frame", {Name = key, BackgroundTransparency = 1, Size = UDim2.fromOffset(0, BAR_HEIGHT), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = index * 10 + 2, Visible = false, ZIndex = 202})
        cell.Parent = frame
        local cellLayout = create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
        cellLayout.Parent = cell
        local image = icon(cell, statIcons[key] or "circle", 11, T.Accent); image.LayoutOrder = 1; image.ZIndex = 203
        local value = label(cell, "", 12, Enum.Font.GothamMedium, TEXT_COLOR); value.AutomaticSize = Enum.AutomaticSize.X; value.Size = UDim2.fromOffset(0, BAR_HEIGHT); value.LayoutOrder = 2; value.ZIndex = 203
        cells[key] = {Cell = cell, Divider = divider, Icon = image, Text = value}
    end

    local watermark = {Frame = frame, Criteria = criteria, Enabled = enabled}
    function watermark:SetCriteria(list) if type(list) == "table" then criteria = list; self.Criteria = list end end
    function watermark:SetStat(name, value) enabled[string.upper(name)] = value == true end
    function watermark:SetCompact(value) self.Compact = value == true end
    options.WatermarkControl = watermark

    local started, frameCount, fps, lastTps = os.clock(), 0, 0, 0
    connect(RunService.RenderStepped, function(dt)
        frameCount += 1
        if os.clock() - started >= .5 then
            fps = math.floor(frameCount / (os.clock() - started)); frameCount, started = 0, os.clock()
            lastTps = math.floor(1 / math.max(dt, .001) + .5)
        end
        local ping = math.floor((LocalPlayer and LocalPlayer:GetNetworkPing() or 0) * 1000)
        local values = {
            FPS = function() return fps .. " FPS" end,
            BPS = function() local r = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"); return r and string.format("%.0f BPS", r.AssemblyLinearVelocity.Magnitude) or "0 BPS" end,
            TPS = function() return lastTps .. " TPS" end,
            PING = function() return ping .. " MS" end,
            CPU = function() return string.format("%.0f%% CPU", math.clamp((1 - dt / .0167) * 100, 0, 100)) end,
            ["RAM USAGE"] = function() local ok, v = pcall(function() return StatsService:GetTotalMemoryUsageMb() end); return ok and string.format("%.0f MB", v) or "-- MB" end,
            LOGIN = function() return "@" .. tostring(LocalPlayer and LocalPlayer.Name or "player") end,
        }
        local seenVisible = false
        for _, name in ipairs(criteria) do
            local key = string.upper(name)
            local entry = cells[key]
            if entry then
                local text = (enabled[key] and values[key]) and values[key]() or ""
                local visible = text ~= ""
                entry.Cell.Visible = visible
                if visible then
                    entry.Text.Text = text
                    entry.Icon.ImageColor3 = T.Accent
                end
                if entry.Divider then entry.Divider.Visible = visible and seenVisible end
                if visible then seenVisible = true end
            end
        end
        afterLogoDivider.Visible = seenVisible
    end)

    dragify(frame, frame); watermark.Menu = attachHudMenu(self, frame, options)
    self.WatermarkInstance = watermark
    if self.HUDElements then self.HUDElements["Watermark"] = watermark end
    if self._selectedElements and self._selectedElements["Watermark"] ~= nil then
        frame.Visible = self._selectedElements["Watermark"] == true
    end
    return watermark
end

function Library:KeybindHUD(options)
    -- Same visual language as the watermark: one dark translucent panel with the dark glow and no outline.
    -- Every bound key is listed; a held key lights up (bright name, accent chip).
    options = options or {}; options.Element = options.Element or "Keybinds"; local hud = {Rows = {}}
    local WIDTH, TITLE_H, ROW_H = options.Width or 172, 28, 20
    local TEXT_COLOR, DIM_COLOR = Color3.fromRGB(226, 228, 233), Color3.fromRGB(140, 142, 148)
    local CHIP, CHIP_ACTIVE = Color3.fromRGB(34, 36, 41), Color3.fromRGB(56, 58, 66)
    local order = 0

    local frame = create("Frame", {Name = "KeybindHUD", BackgroundColor3 = Color3.fromRGB(16, 17, 21), BackgroundTransparency = .12, BorderSizePixel = 0, Position = options.Position or UDim2.fromOffset(20, 165), Size = UDim2.fromOffset(WIDTH, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 200})
    frame.Parent = self.Gui; addRound(frame, 8)
    local frameLayout = create("UIListLayout", {HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder})
    frameLayout.Parent = frame
    hudBackdrop(self, frame, 8)

    local header = create("Frame", {Name = "Title", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, TITLE_H), LayoutOrder = 0, Active = true})
    header.Parent = frame
    local headerIcon = icon(header, "keyboard", 13, T.Accent); headerIcon.Position = UDim2.fromOffset(11, (TITLE_H - 13) / 2)
    local title = label(header, options.Title or "Keybinds", 13, Enum.Font.GothamBold, T.Text)
    title.Position = UDim2.fromOffset(31, 0); title.Size = UDim2.new(1, -42, 1, 0)

    local divider = create("Frame", {Name = "Divider", BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = .9, BorderSizePixel = 0, Size = UDim2.new(1, -20, 0, 1), LayoutOrder = 1, Visible = false})
    divider.Parent = frame
    local rows = create("Frame", {Name = "Rows", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Visible = false})
    rows.Parent = frame; padding(rows, 11, 9, 5, 7)
    local rowsLayout = create("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder})
    rowsLayout.Parent = rows

    local function refresh()
        local any = next(hud.Rows) ~= nil
        rows.Visible = any; divider.Visible = any
    end
    local function paint(entry, time)
        local active = entry.Active
        tween(entry.NameLabel, time, {TextColor3 = active and TEXT_COLOR or DIM_COLOR})
        tween(entry.KeyLabel, time, {TextColor3 = active and T.Accent or DIM_COLOR})
        tween(entry.Badge, time, {BackgroundColor3 = active and CHIP_ACTIVE or CHIP})
    end

    function hud:Add(name, key)
        if self.Rows[name] then self:Remove(name) end
        order += 1
        local row = create("Frame", {Name = "Bind", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = order})
        row.Parent = rows
        local nameLabel = label(row, name, 12, Enum.Font.GothamMedium, DIM_COLOR)
        nameLabel.Position = UDim2.fromOffset(0, 0); nameLabel.Size = UDim2.new(1, -56, 1, 0); nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        local badge = create("Frame", {BackgroundColor3 = CHIP, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, 0, .5, 0), Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X})
        badge.Parent = row; addRound(badge, 4); padding(badge, 6, 6, 0, 0)
        local keyLabel = label(badge, tostring(key), 11, Enum.Font.GothamBold, DIM_COLOR, Enum.TextXAlignment.Center)
        keyLabel.Position = UDim2.fromOffset(0, 0); keyLabel.Size = UDim2.fromOffset(0, 16); keyLabel.AutomaticSize = Enum.AutomaticSize.X
        self.Rows[name] = {Frame = row, NameLabel = nameLabel, KeyLabel = keyLabel, Badge = badge, Name = name, Key = key, Active = false}
        refresh()
        return row
    end
    function hud:Remove(name)
        if self.Rows[name] then self.Rows[name].Frame:Destroy(); self.Rows[name] = nil end
        refresh()
    end
    function hud:SetKey(name, key)
        local entry = self.Rows[name]; if entry then entry.Key = key; entry.KeyLabel.Text = tostring(key) end
    end
    function hud:SetActive(name, active)
        local entry = self.Rows[name]; if not entry then return end
        entry.Active = active == true
        paint(entry, .15)
    end
    function hud:SetStyle(style) title.Text = options.Title or "Keybinds" end -- legacy compatibility shim

    hud.Frame = frame; dragify(header, frame); options.KeybindControl = function(style) hud:SetStyle(style) end; attachHudMenu(self, frame, options)
    self.KeybindHUDInstance = hud
    if self.HUDElements then self.HUDElements["Keybinds"] = hud end
    if self._selectedElements and self._selectedElements["Keybinds"] ~= nil then
        frame.Visible = self._selectedElements["Keybinds"] == true
    end
    return hud
end

function Library:AltKeybinds(options)
    -- The former alternative style is retained only as an API alias.
    options=options or {}; options.Element="Keybinds"
    return self:KeybindHUD(options)
end

function Library:Indicator(options)
    options=options or {}; options.Element="Indicators"; local color=options.Color or Color3.fromRGB(226,77,77)
    -- Neverlose-style stack: small dark pills, one per active state, grouped so they stay together on-screen.
    if not self.IndicatorGroup then
        local group=create("Frame",{Name="IndicatorGroup",BackgroundTransparency=1,BorderSizePixel=0,Position=options.GroupPosition or UDim2.fromOffset(20,350),Size=UDim2.fromOffset(0,0),AutomaticSize=Enum.AutomaticSize.XY,Active=true,ZIndex=200})
        group.Parent=self.Gui
        local groupLayout=create("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
        groupLayout.Parent=group
        dragify(group,group)
        self.IndicatorGroup=group
        self._indicatorCount=0
        attachHudMenu(self,group,{Element="Indicators",Position=options.GroupPosition})
    end
    local group=self.IndicatorGroup
    self._indicatorCount=(self._indicatorCount or 0)+1

    local entry=create("Frame",{Name="IndicatorEntry",BackgroundColor3=Color3.fromRGB(16,17,21),BackgroundTransparency=.12,BorderSizePixel=0,Size=UDim2.fromOffset(0,24),AutomaticSize=Enum.AutomaticSize.X,LayoutOrder=self._indicatorCount,Visible=options.Persistent~=false,ZIndex=201})
    entry.Parent=group; addRound(entry,7)
    padding(entry,8,11,0,0)
    local rowLayout=create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder})
    rowLayout.Parent=entry
    -- Coloured state bar and icon; the text stays neutral so every pill reads the same. Same glow as the watermark
    local bar=create("Frame",{BackgroundColor3=color,BorderSizePixel=0,Size=UDim2.fromOffset(2,12),LayoutOrder=0,ZIndex=202}); bar.Parent=entry; addRound(bar,1)
    local image=icon(entry,options.Icon or "swords",13,color); image.LayoutOrder=1; image.ZIndex=202
    local text=label(entry,options.Text or "INDICATOR",options.Size or 12,Enum.Font.GothamBold,Color3.fromRGB(226,228,233)); text.AutomaticSize=Enum.AutomaticSize.X; text.Size=UDim2.fromOffset(0,24); text.LayoutOrder=2; text.ZIndex=202
    hudBackdrop(self,entry,7,group.ZIndex)

    local control={Instance=entry,TextLabel=text}
    function control:Set(value,newColor)
        text.Text=tostring(value)
        if newColor then color=newColor; image.ImageColor3=color; bar.BackgroundColor3=color end
    end
    function control:SetVisible(value) entry.Visible=value==true end
    function control:SetActive(value) entry.Visible=value==true end

    self.IndicatorInstance = control
    if self.HUDElements then self.HUDElements["Indicators"] = group end
    if self._selectedElements and self._selectedElements["Indicators"] ~= nil then
        group.Visible = self._selectedElements["Indicators"] == true
    end
    return control
end

function Library:Crosshair(options)
    options = options or {}; options.Element=options.Element or "Crosshair"; local holder = create("Frame", {BackgroundTransparency = 1, AnchorPoint = Vector2.new(.5,.5), Position = UDim2.fromScale(.5,.5), Size = UDim2.fromOffset(80,80), ZIndex=1})
    holder.Parent = self.Gui
    local radius, thick, color, opacity = options.Radius or options.Size or 10, options.Thickness or 2, options.Color or T.Text, options.Opacity or 0
    if string.lower(options.Style or "cross")=="circle" then
        local ring=create("Frame",{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(radius*2,radius*2)}); ring.Parent=holder; addRound(ring,radius); stroke(ring,color,thick,opacity)
    else
        local gap=options.Gap or 4
        for _, data in ipairs({
            {UDim2.new(.5,-gap-radius,.5,-thick/2), UDim2.fromOffset(radius,thick)}, {UDim2.new(.5,gap,.5,-thick/2), UDim2.fromOffset(radius,thick)},
            {UDim2.new(.5,-thick/2,.5,-gap-radius), UDim2.fromOffset(thick,radius)}, {UDim2.new(.5,-thick/2,.5,gap), UDim2.fromOffset(thick,radius)},
        }) do local line=create("Frame",{BackgroundColor3=color,BackgroundTransparency=opacity,BorderSizePixel=0,Position=data[1],Size=data[2]}); line.Parent=holder; addRound(line,thick) end
        if options.Dot then local dot=create("Frame",{BackgroundColor3=color,BackgroundTransparency=opacity,BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(thick+1,thick+1)}); dot.Parent=holder; addRound(dot,thick) end
    end
    self.CrosshairElement=holder
    attachHudMenu(self,holder,options); return holder
end

function Library:ModuleList(options)
    -- Layout (no circular sizing, no measured-text hacks):
    --   [ panel: AutomaticSize XY ]
    --       [ column: names, right-aligned, one per row ] [ single accent bar on the RIGHT ]
    -- The bar's height is computed from the row count (rows have a fixed height), so it always
    -- spans exactly the list. The panel width is just the widest name plus paddings.
    options = options or {}; options.Element = "ModuleList"
    local hud = {Entries = {}}
    local ROW_H, GAP, BAR_W = 25, 0, 3
    -- colour wave running down the list (and the bar): blue -> white -> lavender -> blue
    local WAVE = {Color3.fromRGB(105, 160, 225), Color3.fromRGB(232, 233, 242), Color3.fromRGB(162, 160, 246)}
    local function waveColor(t)
        t = t % 1
        local scaled = t * #WAVE
        local i = math.floor(scaled)
        local a, b = WAVE[i + 1], WAVE[(i + 1) % #WAVE + 1]
        local k = scaled - i
        k = k * k * (3 - 2 * k)
        return a:Lerp(b, k)
    end
    local WAVE_SPEED, WAVE_STEP = 0.18, 0.11
    -- Colour modes (Settings -> Module List):
    --   Wave   - the blue / white / lavender wave
    --   Client - the UI accent colour (follows an animated accent too)
    --   Fade   - Color 1 and Color 2 fading into each other down the list
    --   Pulse  - Color 1 pulsing towards a darker shade of itself
    local style = self.ModuleListStyle or {Mode = "Wave", Color1 = Color3.fromRGB(165, 194, 255), Color2 = Color3.fromRGB(255, 120, 200), Speed = 1}
    self.ModuleListStyle = style
    local function modeColor(t)
        local mode = style.Mode
        if mode == "Client" then return T.Accent end
        if mode == "Fade" then
            local k = 0.5 - 0.5 * math.cos(t * math.pi * 2)
            return style.Color1:Lerp(style.Color2, k)
        end
        if mode == "Pulse" then
            local h, sat, v = style.Color1:ToHSV()
            local dark = Color3.fromHSV(h, sat, v * 0.45)
            local k = 0.5 - 0.5 * math.cos(t * math.pi * 2)
            return style.Color1:Lerp(dark, k)
        end
        return waveColor(t)
    end

    local frame = create("Frame", {
        Name = "ModuleListHUD",
        BackgroundColor3 = Color3.fromRGB(18, 20, 42),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0),
        Position = options.Position or UDim2.new(1, -20, 0, 70),
        Size = UDim2.fromOffset(0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        Visible = false,
        ZIndex = 200,
    })
    frame.Parent = self.Gui
    addRound(frame, 4)
    padding(frame, 12, 0, 0, 0) -- no right padding: the accent bar sits on the panel's right edge

    local outer = create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    outer.Parent = frame

    local column = create("Frame", {
        Name = "Column",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.XY,
        LayoutOrder = 1,
        ZIndex = 201,
    })
    column.Parent = frame
    local columnLayout = create("UIListLayout", {
        Padding = UDim.new(0, GAP),
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    columnLayout.Parent = column
    padding(column, 0, 0, 4, 4)

    local bar = create("Frame", {
        Name = "AccentBar",
        BackgroundColor3 = T.Accent,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(BAR_W, 0),
        LayoutOrder = 2,
        ZIndex = 201,
    })
    bar.Parent = frame
    addRound(bar, 2)
    local barGradient = create("UIGradient", {Rotation = 90})
    barGradient.Parent = bar

    -- Accent Shine (FemHook style): a soft white band that sweeps down the accent line
    local shine = create("Frame", {Name = "AccentShine", BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 202, Visible = false})
    shine.Parent = bar
    local shineGradient = create("UIGradient", {Rotation = 90, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1), NumberSequenceKeypoint.new(0.5, 0.2),
        NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1),
    })})
    shineGradient.Parent = shine
    connect(RunService.RenderStepped, function()
        local enabled = self.AccentShineEnabled ~= false and frame.Visible and bar.Size.Y.Offset > 0
        shine.Visible = enabled
        if enabled then
            shineGradient.Offset = Vector2.new(0, -1.5 + 3 * ((os.clock() % 2.4) / 2.4))
        end
        if not frame.Visible then return end
        -- each row takes the colour at its position; the bar shows the same colours along its length
        local now = os.clock() * WAVE_SPEED * (style.Speed or 1)
        local count = 0
        for _, entry in pairs(hud.Entries) do
            count += 1
            entry.Label.TextColor3 = modeColor((entry.Label.LayoutOrder - 1) * WAVE_STEP - now)
            if style.Font and entry.Label.FontFace ~= style.Font then entry.Label.FontFace = style.Font end
        end
        count = math.max(count, 1)
        local keys = {}
        for i = 0, 4 do
            keys[#keys + 1] = ColorSequenceKeypoint.new(i / 4, modeColor((i / 4) * count * WAVE_STEP - now))
        end
        barGradient.Color = ColorSequence.new(keys)
    end)

    function hud:Add(name, order)
        local existing = self.Entries[name]
        if existing then
            existing.Label.LayoutOrder = order or 100
            return
        end
        local lbl = label(column, name, 18, Enum.Font.Arial, T.Text, Enum.TextXAlignment.Right)
        lbl.AutomaticSize = Enum.AutomaticSize.X
        lbl.Size = UDim2.fromOffset(0, ROW_H)
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lbl.TextStrokeTransparency = 0.75
        lbl.LayoutOrder = order or 100
        lbl.ZIndex = 202
        self.Entries[name] = {Label = lbl, Name = name}
    end

    function hud:Remove(name)
        local entry = self.Entries[name]
        if entry then
            entry.Label:Destroy()
            self.Entries[name] = nil
        end
    end

    function hud:Update(activeList)
        if type(activeList) ~= "table" then return end

        for name in pairs(self.Entries) do
            if not activeList[name] then
                self:Remove(name)
            end
        end

        -- Same ordering as before: explicit Priority first, then longer names first, then alphabetical.
        local sorted, count = {}, 0
        for name, val in pairs(activeList) do
            count += 1
            local customPriority = (typeof(val) == "table" and val.Priority) or nil
            table.insert(sorted, {Name = name, Priority = customPriority, Length = #name})
        end

        table.sort(sorted, function(a, b)
            if a.Priority and b.Priority and a.Priority ~= b.Priority then
                return a.Priority < b.Priority
            elseif a.Priority and not b.Priority then
                return true
            elseif not a.Priority and b.Priority then
                return false
            end
            if a.Length == b.Length then
                return a.Name < b.Name
            end
            return a.Length > b.Length
        end)

        for order, item in ipairs(sorted) do
            self:Add(item.Name, order)
        end

        -- Bar: one line for the whole list, height = rows + gaps, color = top module's color.
        local barH = count * ROW_H + math.max(count - 1, 0) * GAP
        bar.Size = UDim2.fromOffset(BAR_W, barH + 8) -- +8 = the column's top/bottom padding, so the line spans the whole panel
        bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255) -- coloured by the wave gradient

        local shouldShow = count > 0
        if self.Library and self.Library._selectedElements and self.Library._selectedElements["Module List"] == false then
            shouldShow = false
        end
        frame.Visible = shouldShow
    end

    -- the module list's own font: "Default" = the interface font the script starts with (Gotham)
    function hud:SetFont(name)
        local face = nil
        if name and name ~= "Default" then
            if BUILTIN_FONTS[name] then
                face = Font.fromEnum(BUILTIN_FONTS[name])
            else
                local file = fileFont(name)
                face = file and file.regular or nil
            end
        end
        style.Font = face or Font.fromEnum(Enum.Font.GothamBold)
    end
    if not style.Font then style.Font = Font.fromEnum(Enum.Font.GothamBold) end

    hud.Frame = frame
    hud.Library = self
    dragify(frame, frame)
    self.ModuleListControl = hud
    if self.HUDElements then self.HUDElements["Module List"] = hud end
    return hud
end

function Library:SaveConfig(name)
    name=tostring(name or ""):gsub("[^%w%-%_]",""); if name=="" or not writefile or not HttpService then return false,"Invalid name or filesystem unavailable" end
    local folder="RarelyWinUI/configs"; if makefolder then pcall(makefolder,"RarelyWinUI"); pcall(makefolder,folder) end
    local data={}; for flag,control in pairs(self.Flags) do if control and control.Value~=nil then data[flag]=control.Value end end
    local ok,result=pcall(function() writefile(folder.."/"..name..".json",HttpService:JSONEncode(data)) end); return ok,result
end

function Library:LoadConfig(name)
    name=tostring(name or ""):gsub("[^%w%-%_]",""); local path="RarelyWinUI/configs/"..name..".json"; if name=="" or not readfile or not isfile or not isfile(path) then return false,"Config not found" end
    local ok,data=pcall(function() return HttpService:JSONDecode(readfile(path)) end); if not ok then return false,data end
    for flag,value in pairs(data) do local control=self.Flags[flag]; if control and control.Set then control:Set(value) end end; return true
end

function Library:DeleteConfig(name)
    name=tostring(name or ""):gsub("[^%w%-%_]",""); local path="RarelyWinUI/configs/"..name..".json"; if name=="" or not delfile or not isfile or not isfile(path) then return false,"Config not found" end
    return pcall(delfile,path)
end

function Library:_buildSettingsSection()
    if self.SettingsPanel then self.SettingsPanel:Destroy(); self.SettingsPanel=nil end
    local configTab=self:Tab({Name="Configs",Icon="folder",Pinned=true})
    local tab=self:Tab({Name="Settings",Icon="settings",Hidden=true}); self.SettingsTab=tab
    -- Configs belongs to the lower sidebar area, immediately above Settings.
    configTab.Button.Parent=self.Sidebar; configTab.Button.Position=UDim2.new(0,18,1,-164); configTab.Button.Size=UDim2.new(1,-36,0,46); configTab.Button.BackgroundColor3=T.Surface3; configTab.Button.Visible=true; self.ConfigButton=configTab.Button

    -- Full-width configuration panel on its own Configs tab.
    local configs=create("Frame",{Name="Configs",BackgroundTransparency=1,BorderSizePixel=0,Position=UDim2.fromOffset(0,0),Size=UDim2.new(1,0,0,142)}); configs.Parent=configTab.Page
    local createBar=create("Frame",{BackgroundColor3=Color3.fromRGB(34,35,39),BorderSizePixel=0,Size=UDim2.new(1,0,0,54)}); createBar.Parent=configs; addRound(createBar,18); gradient(createBar,Color3.fromRGB(48,49,54),Color3.fromRGB(27,28,32),0)
    local configName=create("TextBox",{Text="",PlaceholderText="config name...",PlaceholderColor3=Color3.fromRGB(155,157,162),TextColor3=T.Text,TextSize=17,Font=Enum.Font.GothamBold,ClearTextOnFocus=false,BackgroundColor3=Color3.fromRGB(36,37,41),BorderSizePixel=0,Position=UDim2.fromOffset(14,11),Size=UDim2.new(.46,0,0,32)}); configName.Parent=createBar; addRound(configName,8); stroke(configName,Color3.fromRGB(119,121,126),2,.18); padding(configName,10,10,0,0)
    local function configButton(parent,text,x,width,color,callback)
        local b=create("TextButton",{Text=text,TextColor3=T.Text,TextSize=17,Font=Enum.Font.GothamBold,AutoButtonColor=false,BackgroundColor3=color,BorderSizePixel=0,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,x,0,11),Size=UDim2.fromOffset(width,32)}); b.Parent=parent; addRound(b,8); gradient(b,color,Color3.fromRGB(math.max(0,color.R*255-32),math.max(0,color.G*255-32),math.max(0,color.B*255-32)),0); connect(b.MouseButton1Click,callback); return b
    end
    configButton(createBar,"Save",-14,104,Color3.fromRGB(57,52,132),function() local ok,err=self:SaveConfig(configName.Text); self:Notify({Type=ok and "success" or "error",Title=ok and "Successful" or "Config error",Message=ok and "Config saved." or tostring(err)}) end)
    local entry=create("Frame",{BackgroundColor3=Color3.fromRGB(34,35,39),BorderSizePixel=0,Position=UDim2.fromOffset(0,64),Size=UDim2.new(1,0,0,78)}); entry.Parent=configs; addRound(entry,18); gradient(entry,Color3.fromRGB(49,50,55),Color3.fromRGB(27,28,32),0)
    local configTitle=label(entry,"Selected config",20,Enum.Font.GothamBold,T.Text); configTitle.Position=UDim2.fromOffset(14,8); configTitle.Size=UDim2.new(.58,0,0,29)
    local configInfo=label(entry,"Save, load or remove the name entered above.",13,Enum.Font.GothamMedium,T.Muted); configInfo.Position=UDim2.fromOffset(14,39); configInfo.Size=UDim2.new(.58,0,0,22)
    configButton(entry,"Load",-126,104,Color3.fromRGB(39,69,109),function() local ok,err=self:LoadConfig(configName.Text); self:Notify({Type=ok and "success" or "error",Title=ok and "Successful" or "Config error",Message=ok and "Config loaded." or tostring(err)}) end)
    configButton(entry,"Delete",-14,104,Color3.fromRGB(125,51,55),function() local ok,err=self:DeleteConfig(configName.Text); self:Notify({Type=ok and "success" or "error",Title=ok and "Successful" or "Config error",Message=ok and "Config deleted." or tostring(err)}) end)

    local interface=self:Card(tab,{Title="Interface",Side="left"})
    local selectedElements={Watermark=true,Keybinds=true,Indicators=true,["Module List"]=true,["Toggle UI Button"]=true}
    self._selectedElements=selectedElements

    if not self.WatermarkInstance then self.WatermarkInstance = self:Watermark() end
    if not self.KeybindHUDInstance then self.KeybindHUDInstance = self:KeybindHUD() end
    -- Indicators are game-specific (e.g. a PixelSurf status pill) and are created by the script that uses this library.
    if not self.ModuleListControl then self.ModuleListControl = self:ModuleList() end

    local function applyHudVisibility(values)
        if self.WatermarkInstance and self.WatermarkInstance.Frame then
            self.WatermarkInstance.Frame.Visible = values["Watermark"] == true
        end
        if self.KeybindHUDInstance and self.KeybindHUDInstance.Frame then
            self.KeybindHUDInstance.Frame.Visible = values["Keybinds"] == true
        end
        if self.IndicatorGroup then
            self.IndicatorGroup.Visible = values["Indicators"] == true
        end
        if self.ModuleListControl and self.ModuleListControl.Frame then
            self.ModuleListControl.Frame.Visible = values["Module List"] == true
        end
        if self.ToggleButton then
            self.ToggleButton.Visible = values["Toggle UI Button"] == true
        end
    end

    self:Dropdown(interface,{
        Name="Elements",
        Values={"Watermark","Keybinds","Indicators","Module List","Toggle UI Button"},
        Default=selectedElements,
        Multi=true,
        Callback=function(value)
            selectedElements=value
            self._selectedElements=value
            applyHudVisibility(value)
        end
    })
    applyHudVisibility(selectedElements)
    self:Dropdown(interface,{Name="Toggle UI Button Style",Values={"Var. 1 (Square)","Var. 2 (wide, full name)"},Default="Var. 1 (Square)",Callback=function(value) self:_createToggle(string.find(value,"Var. 2",1,true) and 2 or 1) end})

    local moduleCard=self:Card(tab,{Title="Module List",Side="right"})
    local mlStyle=self.ModuleListStyle or {Mode="Wave",Color1=Color3.fromRGB(165,194,255),Color2=Color3.fromRGB(255,120,200),Speed=1}
    self.ModuleListStyle=mlStyle
    self:Dropdown(moduleCard,{Name="Color Mode",Values={"Wave","Client","Fade","Pulse"},Default=mlStyle.Mode,Callback=function(value) mlStyle.Mode=value end})
    self:ColorPicker(moduleCard,{Name="Color 1",Default=mlStyle.Color1,Callback=function(value) mlStyle.Color1=value end})
    self:ColorPicker(moduleCard,{Name="Color 2 (Fade)",Default=mlStyle.Color2,Callback=function(value) mlStyle.Color2=value end})
    self:Slider(moduleCard,{Name="Color Speed",Min=0.2,Max=4,Default=1,Step=0.1,Callback=function(value) mlStyle.Speed=value end})
    self:Dropdown(moduleCard,{Name="Font",Values=self:ListFonts(),Default="Default",OnOpen=function(control) control:SetValues(self:ListFonts()) end,Callback=function(value)
        if self.ModuleListControl and self.ModuleListControl.SetFont then self.ModuleListControl:SetFont(value) end
    end})

    local notifications=self:Card(tab,{Title="Notification Test",Side="right"})
    self:Button(notifications,{Name="Default notification",Callback=function() self:Notify({Type="success",Title="Successful",Message="Function enabled.",Style="default"}) end})
    self:Button(notifications,{Name="Warning notification",Callback=function() self:Notify({Type="warning",Title="Hold up!",Message="This is a warning preview."}) end})

    local ui=self:Card(tab,{Title="UI Settings",Side="left"})
    -- Accent: one colour, or two colours fading into each other ("Accent Fade").
    -- Every element painted with the accent is tracked (rescanned every 2 s, so new elements join) and
    -- recoloured ~20 times a second while the fade runs.
    local ACCENT_PROPS = {GuiObject = "BackgroundColor3", TextLabel = "TextColor3", ImageLabel = "ImageColor3", UIStroke = "Color"}
    local accent = {Color1 = T.Accent, Color2 = Color3.fromRGB(150, 120, 255), Fade = false, Speed = 1}
    self.AccentStyle = accent
    local tracked = setmetatable({}, {__mode = "k"})
    local function nearSegment(c)
        local a, b = accent.Color1, accent.Color2
        local ab = Vector3.new(b.R - a.R, b.G - a.G, b.B - a.B)
        local ac = Vector3.new(c.R - a.R, c.G - a.G, c.B - a.B)
        local len = ab:Dot(ab)
        local k = len > 0 and math.clamp(ac:Dot(ab) / len, 0, 1) or 0
        return (ac - ab * k).Magnitude < 0.012
    end
    local function scanAccent()
        for _, object in ipairs(self.Gui:GetDescendants()) do
            for class, prop in pairs(ACCENT_PROPS) do
                if object:IsA(class) then
                    local ok, value = pcall(function() return object[prop] end)
                    if ok and typeof(value) == "Color3" and (value == T.Accent or (accent.Fade and nearSegment(value))) then
                        tracked[object] = tracked[object] or {}
                        tracked[object][prop] = true
                    end
                end
            end
        end
    end
    local function paintAccent(color)
        local previous = T.Accent
        T.Accent = color
        for object, props in pairs(tracked) do
            if object.Parent then
                for prop in pairs(props) do pcall(function() object[prop] = color end) end
            end
        end
        return previous
    end
    local lastScan, lastPaint = 0, 0
    connect(RunService.Heartbeat, function()
        if not accent.Fade then return end
        local now = os.clock()
        if now - lastScan > 2 then lastScan = now; scanAccent() end
        if now - lastPaint < 0.05 then return end
        lastPaint = now
        local k = 0.5 - 0.5 * math.cos(now * 0.9 * accent.Speed)
        paintAccent(accent.Color1:Lerp(accent.Color2, k))
    end)
    self:ColorPicker(ui,{Name="Accent Color",Default=T.Accent,Callback=function(color)
        accent.Color1 = color
        if accent.Fade then return end
        table.clear(tracked); scanAccent(); paintAccent(color)
    end})
    self:ColorPicker(ui,{Name="Accent Color 2",Default=accent.Color2,Callback=function(color) accent.Color2 = color end})
    self:Toggle(ui,{Name="Accent Fade",Default=false,Bindable=false,Callback=function(value)
        accent.Fade = value
        table.clear(tracked); scanAccent()
        if not value then paintAccent(accent.Color1) end
    end})
    self:Slider(ui,{Name="Accent Fade Speed",Min=0.2,Max=4,Default=1,Step=0.1,Callback=function(value) accent.Speed = value end})
    -- Fonts and sounds come from RarelyWinUI/fonts and RarelyWinUI/sounds; the lists refresh when a dropdown opens
    self:Dropdown(ui,{Name="UI Font",Values=self:ListFonts(),Default="Default",OnOpen=function(control) control:SetValues(self:ListFonts()) end,Callback=function(value) self:SetFont(value) end})
    local backgroundBox=self:Textbox(ui,{Name="Custom UI Background",Placeholder="rbxassetid://... or URL"})
    self:Button(ui,{Name="Apply background",Callback=function()
        local source=tostring(backgroundBox.Value or "")
        if source~="" then
            if string.match(source,"^https?://") and writefile and (getcustomasset or getsynasset) then
                local ok,asset=pcall(function()
                    local fileName="RarelyWinUI_Background_"..HttpService:GenerateGUID(false)..".png"
                    writefile(fileName,game:HttpGet(source)); return (getcustomasset or getsynasset)(fileName)
                end)
                if ok then source=asset else self:Notify({Type="error",Title="Background error",Message=tostring(asset)}); return end
            end
            self.BackgroundImage.Image=source; self.BackgroundImage.Visible=true
        end
    end})
    self:Button(ui,{Name="Reset to default",Callback=function() self.BackgroundImage.Image=""; self.BackgroundImage.Visible=false end})
    self:Toggle(ui,{Name="Sound on Func Toggle",Default=false,Callback=function(value) self.SoundOnToggle=value end})
    self.ToggleSoundName = "Default"
    self:Dropdown(ui,{Name="Toggle Sound",Values=self:ListSounds(),Default="Default",OnOpen=function(control) control:SetValues(self:ListSounds()) end,Callback=function(value) self.ToggleSoundName=value end})
    self:Button(ui,{Name="Test toggle sound",Callback=function() self:PlayToggleSound() end})
    self.AccentShineEnabled = true
    self:Toggle(ui,{Name="Accent Shine",Default=true,Callback=function(value) self.AccentShineEnabled=value end})
    self:Toggle(ui,{Name="Streamer Mode",Default=false,Callback=function(value)
        self.StreamerMode=value; if self.UsernameLabel then self.UsernameLabel.Text=value and "@hidden" or self.OriginalUsername end
    end})

    local crosshair=self:Card(tab,{Title="Crosshair",Side="right"})
    local crosshairOptions={Style="Circle",Radius=10,Thickness=2,Opacity=0,Dot=false,Color=T.Text}
    local function refresh()
        if self.CrosshairElement then self.CrosshairElement:Destroy() end
        self:Crosshair(crosshairOptions)
    end
    self:Dropdown(crosshair,{Name="Style",Values={"Circle","Cross"},Default="Circle",Callback=function(value) crosshairOptions.Style=value; refresh() end})
    self:Slider(crosshair,{Name="Radius",Min=3,Max=30,Default=10,Callback=function(value) crosshairOptions.Radius=value; refresh() end})
    self:Slider(crosshair,{Name="Thickness",Min=1,Max=8,Default=2,Callback=function(value) crosshairOptions.Thickness=value; refresh() end})
    self:Slider(crosshair,{Name="Opacity",Min=0,Max=100,Default=0,Suffix="%",Callback=function(value) crosshairOptions.Opacity=value/100; refresh() end})
    self:Toggle(crosshair,{Name="Dot",Default=false,Callback=function(value) crosshairOptions.Dot=value; refresh() end})
    self:ColorPicker(crosshair,{Name="Color",Default=T.Text,Callback=function(value) crosshairOptions.Color=value; refresh() end})
end

function Library:Destroy()
    for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    table.clear(connections)
    if self.Gui then self.Gui:Destroy() end
end

-- Fonts -------------------------------------------------------------------------------------------
function Library:ListFonts()
    ensureFolder(FONT_DIR)
    local list = {"Default"}
    for _, name in ipairs(BUILTIN_FONT_ORDER) do table.insert(list, name) end
    for _, name in ipairs(scanFolder(FONT_DIR, {ttf = true, otf = true}, fontFiles)) do
        if not BUILTIN_FONTS[name] then table.insert(list, name) end
    end
    return list
end

-- "Default" restores each element's own font; presets apply one font everywhere; file fonts keep bold/regular
function Library:SetFont(name)
    if name == nil or name == "Default" then
        ActiveFont = nil
    elseif BUILTIN_FONTS[name] then
        ActiveFont = {enum = BUILTIN_FONTS[name]}
    else
        ActiveFont = fileFont(name)
    end
    for _, object in ipairs(self.Gui:GetDescendants()) do
        if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
            pcall(applyFont, object, originalFonts[object])
        end
    end
end

-- Sounds ------------------------------------------------------------------------------------------
function Library:ListSounds()
    ensureFolder(SOUND_DIR)
    local list = {"Default"}
    for _, name in ipairs(scanFolder(SOUND_DIR, {mp3 = true, ogg = true, wav = true}, soundFiles)) do
        table.insert(list, name)
    end
    return list
end

function Library:PlayToggleSound(name)
    name = name or self.ToggleSoundName or "Default"
    local id = soundIdFor(name)
    if not id then
        warn("[RarelyWinUI] toggle sound '" .. tostring(name) .. "' was not found in " .. SOUND_DIR)
        return
    end
    local sound = self.ToggleSound
    if not (sound and sound.Parent) then
        sound = Instance.new("Sound")
        sound.Volume = .22
        sound.Parent = self.Gui
        self.ToggleSound = sound
    end
    sound.SoundId = id
    sound:Play()
end

-- Custom panels & previews -------------------------------------------------------------------------
-- Panel: free-form content for one subcategory. Shown only while that subcategory is active.
function Library:Panel(tab, options)
    options = options or {}
    local frame = create("Frame", {Name = "Panel_" .. tostring(options.Subcategory), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false})
    frame.Parent = tab.Page
    table.insert(tab.Panels, {Frame = frame, Subcategory = options.Subcategory})
    tab:ApplyFilter()
    return frame
end

-- Preview: spins a model (cloned into a ViewportFrame) and can play an Animation on it.
-- Nothing here touches the server; it only renders local copies.
function Library:Preview(parent, options)
    options = options or {}
    local frame = create("Frame", {BackgroundColor3 = Color3.fromRGB(13, 12, 27), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, -(options.Inset or 0))})
    frame.Parent = parent
    addRound(frame, 12); stroke(frame, T.Accent, 1, .6)
    local viewport = create("ViewportFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 1, -40), Ambient = Color3.fromRGB(170, 160, 220), LightColor = Color3.fromRGB(255, 255, 255), LightDirection = Vector3.new(-1, -1, -1)})
    viewport.Parent = frame
    local world = Instance.new("WorldModel")
    world.Parent = viewport
    local camera = Instance.new("Camera")
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    local caption = label(frame, "", 14, Enum.Font.GothamBold, T.Text, Enum.TextXAlignment.Center)
    caption.Position = UDim2.new(0, 8, 1, -30); caption.Size = UDim2.new(1, -16, 0, 24)

    local preview = {Frame = frame}
    local model, track = nil, nil
    local angle = 0
    connect(RunService.RenderStepped, function(dt)
        if not (model and model.Parent) then return end
        angle += dt * 0.5
        local center, size = model:GetBoundingBox()
        local distance = math.max(size.Y, 3) * 1.8
        local origin = center.Position
        camera.CFrame = CFrame.lookAt(origin + Vector3.new(math.sin(angle) * distance, size.Y * 0.1, math.cos(angle) * distance), origin)
    end)

    function preview:SetCaption(text)
        caption.Text = tostring(text or "")
    end
    function preview:SetModel(source)
        if track then track:Stop(); track = nil end
        if model then model:Destroy(); model = nil end
        if not source then return end
        model = source:Clone()
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Anchored = true
                descendant.CanCollide = false
            elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
                descendant:Destroy()
            end
        end
        model.Parent = world
        if model:IsA("Model") then model:PivotTo(CFrame.new(0, 0, 0)) end
    end
    function preview:PlayAnimation(animation)
        if track then track:Stop(); track = nil end
        local humanoid = model and model:FindFirstChildOfClass("Humanoid")
        if not (humanoid and animation) then return end
        local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
        animator.Parent = humanoid
        track = animator:LoadAnimation(animation)
        track.Looped = true
        track:Play()
    end
    function preview:Stop()
        if track then track:Stop(); track = nil end
    end
    return preview
end

-- Gallery: grid of selectable tiles. OnSelect(item) runs when a tile is clicked.
function Library:Gallery(parent, options)
    options = options or {}
    local scroll = create("ScrollingFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = T.Accent})
    scroll.Parent = parent
    local grid = create("UIGridLayout", {CellSize = UDim2.fromOffset(options.CellWidth or 160, options.CellHeight or 44), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder})
    grid.Parent = scroll
    padding(scroll, 4, 6, 4, 4)

    local gallery = {Tiles = {}, Selected = nil}
    function gallery:SetItems(items)
        for _, tile in ipairs(self.Tiles) do tile:Destroy() end
        table.clear(self.Tiles)
        self.Selected = nil
        for index, item in ipairs(items) do
            local tile = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = T.Surface2, BackgroundTransparency = .1, BorderSizePixel = 0, LayoutOrder = index})
            tile.Parent = scroll
            addRound(tile, 8)
            local name = label(tile, item.Name, 14, Enum.Font.GothamBold, T.Text)
            name.Position = UDim2.fromOffset(10, 0); name.Size = UDim2.new(1, -20, 1, 0); name.TextTruncate = Enum.TextTruncate.AtEnd
            connect(tile.MouseButton1Click, function() gallery:Select(tile, item) end)
            table.insert(self.Tiles, tile)
        end
    end
    function gallery:Select(tile, item)
        for _, other in ipairs(self.Tiles) do
            tween(other, .15, {BackgroundColor3 = other == tile and T.AccentDark or T.Surface2})
        end
        self.Selected = item
        safeCallback(options.OnSelect, item)
    end
    return gallery
end

return Library