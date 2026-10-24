local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")

local function copyToClipboard(text)
    if setclipboard then
        pcall(setclipboard, text)
        return true
    elseif toclipboard then
        pcall(toclipboard, text)
        return true
    end
    return false
end

local player = Players.LocalPlayer

-- ===== Doi Atlas load xong truoc khi doc/bam UI cua no =====
-- Mac dinh: cho it nhat 10s, toi da 20s (hoac som hon neu thay cua so Atlas).
-- Chinh bang getgenv().IvyisAtlasBootMin / IvyisAtlasBootMax.
do
    local g = (getgenv and getgenv()) or _G
    if type(g) == "table" then
        -- reset moi lan execute: at = thoi diem script vua chay
        local st = { at = tick(), min = 10, max = 20 }
        local a, b = tonumber(g.IvyisAtlasBootMin), tonumber(g.IvyisAtlasBootMax)
        if a then st.min = math.clamp(a, 0, 60) end
        if b then st.max = math.clamp(b, st.min, 90) end
        g._IvyisAtlasBoot = st
    end
end

-- ===== Executor detection (safe, lazy) =====
-- Mot so executor implement getexecutorname()/identifyexecutor() kieu yield.
-- Vi vay probe duoc chay trong thread rieng + timeout, khong block script.
local EXECUTOR_NAME = nil
local EXECUTOR_VERSION = nil
local EXECUTOR_PLATFORM = nil

local function getPlatformLabel()
    if EXECUTOR_PLATFORM then return EXECUTOR_PLATFORM end
    local platform = "Unknown"
    if UserInputService then
        pcall(function()
            local rawPlatform = tostring(UserInputService:GetPlatform() or "")
            if rawPlatform:find("Android", 1, true) then
                platform = "Android"
            elseif rawPlatform:find("IOS", 1, true) or rawPlatform:find("iOS", 1, true) then
                platform = "iOS"
            elseif rawPlatform:find("Windows", 1, true) then
                platform = "Windows"
            elseif rawPlatform:find("OSX", 1, true) or rawPlatform:find("Mac", 1, true) then
                platform = "macOS"
            elseif rawPlatform:find("ChromeOS", 1, true) then
                platform = "ChromeOS"
            end
        end)
        if platform == "Unknown" and UserInputService.TouchEnabled then
            platform = "Mobile"
        end
    end
    EXECUTOR_PLATFORM = platform
    if getgenv then
        pcall(function()
            getgenv().IvyisExecutorPlatform = platform
        end)
    end
    return platform
end

local function cleanExecutorText(value, maxLen)
    local text = tostring(value or "")
    text = text:gsub("[\r\n\t]", " "):gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if maxLen and #text > maxLen then
        text = text:sub(1, maxLen)
    end
    return text
end

local function envTable()
    if not getgenv then return nil end
    local ok, env = pcall(getgenv)
    if ok and type(env) == "table" then return env end
    return nil
end

-- Some executors expose getgenv() as a proxy; read through both rawget and a
-- normal index so a metatable-based environment is still detected.
local function readMarker(env, key)
    local ok, value = pcall(rawget, env, key)
    if not ok then return nil end
    if value ~= nil then return value end
    ok, value = pcall(function() return env[key] end)
    if not ok then return nil end
    return value
end

local function hasMarker(env, keys)
    if type(env) ~= "table" then return false end
    for _, key in ipairs(keys) do
        local value = readMarker(env, key)
        if value ~= nil and value ~= false then return true end
    end
    return false
end

-- Arceus X keys differ per build ("Arceus", "ArceusX", "arceus_loader"...).
-- Scan case-insensitively so a version bump cannot silently turn Arceus back
-- into "Fluxus" (Arceus is a Fluxus fork and keeps its globals).
local function hasArceusMarker(env)
    if hasMarker(env, {
        "Arceus", "ArceusX", "arceus", "arceusx", "is_arceus",
        "ArceusXLoaded", "ArceusX_Version", "ArceusX_Loaded",
    }) then
        return true
    end
    if type(env) ~= "table" then return false end
    local ok, keys = pcall(function()
        local list = {}
        for key in pairs(env) do
            list[#list + 1] = key
        end
        return list
    end)
    if not ok or type(keys) ~= "table" then return false end
    for _, key in ipairs(keys) do
        if type(key) == "string" and key:lower():find("arceus", 1, true) then
            local value = readMarker(env, key)
            if value ~= nil and value ~= false then return true end
        end
    end
    return false
end

local function detectExecutor()
    if EXECUTOR_NAME then
        return EXECUTOR_NAME, EXECUTOR_VERSION
    end

    -- Cho phep override thu cong neu executor khong expose ten:
    -- getgenv().IvyisExecutorNameOverride = "Madium"
    local startEnv = envTable()
    if startEnv then
        local override = readMarker(startEnv, "IvyisExecutorNameOverride")
        if type(override) == "string" and override ~= "" then
            EXECUTOR_NAME = cleanExecutorText(override, 48)
            EXECUTOR_VERSION = nil
            return EXECUTOR_NAME, nil
        end
    end

    local name, version = nil, nil

    -- Cheap globals first: no function calls, no yields.
    --
    -- Order matters. Arceus X, Delta, Hydrogen, Codex... are Fluxus forks on
    -- Android and keep Fluxus compatibility globals, so checking "fluxus" first
    -- labelled every fork as Fluxus (e.g. Arceus X shown as "Fluxus").
    -- Fork-specific markers are therefore checked before the base executor.
    local env = envTable()
    if env then
        if hasMarker(env, { "MadiumSignal", "MadiumConnection" }) then
            name = "Madium"
        end
        if not name and hasArceusMarker(env) then
            name = "Arceus X"
        end
        if not name then
            local direct = readMarker(env, "ExecutorName")
                or readMarker(env, "Executor")
                or readMarker(env, "executor")
            if type(direct) == "string" and direct ~= "" then
                name = direct
            end
        end
        if not name and hasMarker(env, { "delta", "Delta", "DeltaX" }) then name = "Delta" end
        if not name and hasMarker(env, { "hydrogen", "Hydrogen" }) then name = "Hydrogen" end
        if not name and hasMarker(env, { "codex", "Codex" }) then name = "Codex" end
        if not name and hasMarker(env, { "cryptic", "Cryptic" }) then name = "Cryptic" end
        if not name and hasMarker(env, { "vega", "Vega", "VegaX" }) then name = "Vega X" end
        if not name and hasMarker(env, { "karma", "Karma" }) then name = "Karma" end
        if not name and hasMarker(env, { "wave", "Wave" }) then name = "Wave" end
        if not name and hasMarker(env, { "solara", "Solara" }) then name = "Solara" end
        if not name and hasMarker(env, { "xeno", "Xeno" }) then name = "Xeno" end
        -- Base executors last: their globals are inherited by the forks above.
        if not name and hasMarker(env, { "KRNL_LOADED" }) then name = "Krnl" end
        if not name and hasMarker(env, { "syn", "Synapse" }) then name = "Synapse X" end
        if not name and hasMarker(env, { "Fluxus", "fluxus", "is_fluxus_closure", "FLUXUS_LOADED" }) then name = "Fluxus" end
    end
    if not name and (type(MadiumSignal) ~= "nil" or type(MadiumConnection) ~= "nil") then
        name = "Madium"
    end

    -- Fallback chuan UNC. Chay async de executor nao yield cung khong treo webhook.
    local function probe(fn)
        if type(fn) ~= "function" then return end
        local done = false
        task.spawn(function()
            local ok, a, b = pcall(fn)
            if ok and type(a) == "string" and a ~= "" and a:lower() ~= "unknown" then
                name = a
                if type(b) == "string" or type(b) == "number" then
                    version = tostring(b)
                end
            end
            done = true
        end)
        local waited = 0
        while not done and waited < 0.75 do
            task.wait(0.05)
            waited = waited + 0.05
        end
    end

    if not name and type(identifyexecutor) == "function" then
        pcall(probe, identifyexecutor)
    end
    if not name and type(getexecutorname) == "function" then
        pcall(probe, getexecutorname)
    end

    EXECUTOR_NAME = cleanExecutorText(name or "Unknown", 48)
    if EXECUTOR_NAME == "" then EXECUTOR_NAME = "Unknown" end
    EXECUTOR_VERSION = version and cleanExecutorText(version, 24) or nil
    if EXECUTOR_VERSION == "" then EXECUTOR_VERSION = nil end
    EXECUTOR_PLATFORM = getPlatformLabel()

    if getgenv then
        pcall(function()
            getgenv().IvyisExecutorName = EXECUTOR_NAME
            getgenv().IvyisExecutorVersion = EXECUTOR_VERSION
            getgenv().IvyisExecutorPlatform = EXECUTOR_PLATFORM
        end)
    end
    return EXECUTOR_NAME, EXECUTOR_VERSION
end

local function getExecutorLabel(includeVersion)
    local name, version = detectExecutor()
    if includeVersion and version and version ~= "" then
        return string.format("%s (%s)", name, version)
    end
    return name
end

local function getWebhookTitle()
    return "Webhook From Ivyis BSS - " .. getExecutorLabel(false)
end

if getgenv and getgenv()._AutoFeedCleanup then
    pcall(getgenv()._AutoFeedCleanup)
    getgenv()._AutoFeedCleanup = nil
end

local scriptAlive = true
local scriptConnections = {}
local function trackConn(c)
    table.insert(scriptConnections, c)
    return c
end

-- Only remove GUIs that belong to this script. A ScreenGui named "IvyisUI" is
-- shared by other scripts too, so check the window title before deleting it.
-- "WindUI" is the old name: keep removing it so an upgrade does not leave the
-- previous version's window on screen.
local function isOurIvyisUI(child)
    if not child then return false end
    if child.Name ~= "IvyisUI" and child.Name ~= "WindUI" then return false end
    local ok, ours = pcall(function()
        for _, d in ipairs(child:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                -- Match current and previous window branding.
                if tostring(d.Text or ""):find("^Ivyis") then return true end
            end
        end
        return false
    end)
    return ok and ours
end

local function destroyOldGuis(parent)
    if not parent then return end
    for _, child in ipairs(parent:GetChildren()) do
        local name = tostring(child.Name or "")
        if name:find("AutoFeed") or name:find("AutoTreat") or name:find("AutoProg") or isOurIvyisUI(child) then
            pcall(function() child:Destroy() end)
        end
    end
end
destroyOldGuis(CoreGui)
if gethui then destroyOldGuis(gethui()) end
destroyOldGuis(player.PlayerGui)


-- =====================================================================================
--  IvyisUI: thu vien giao dien phong cach Atlas, do truc tiep tu UI Atlas that.
--  Dat inline de script chi con mot file, khong phu thuoc WindUI nua.
-- =====================================================================================
--[[
=====================================================================================
 IvyisUI - thu vien UI phong cach ATLAS  (ban demo de kiem chung)
-------------------------------------------------------------------------------------
 Toan bo thong so duoi day duoc DO TRUC TIEP tu UI Atlas that dang chay trong client
 (dump property tung doi tuong + anh chup man hinh), khong phai phong doan:

   Window        : 450x280, pos (0,5),(0,100), bg #151617, UICorner 0/5, clip
   Bar (title)   : cao 25, bg #294A7A, UICorner 0/5
     Title       : (0.5,-10)x25 tai (0,10),(0,0), ts14 trang, GothamBold, trai
     Indicator   : 20x20 tai (1,-25),(0,2) - mui ten thu gon cua so
     Frame       : (1,0)x4 tai y=0.85 - vet nhan mau
   Rail TabButtons: rong 90, (0,90)x(1,-25) tai (0,0),(0,25)
     ScrollingFrame: le 5, UIPadding bottom 10 right 10, UIListLayout pad (0,4)
     SearchBox   : cao 23, #FFFFFF@0.96, corner 4, chu ts11 #EDEDED, icon 12x12
     Divider     : (1,0)x2, #383838
     Tab         : cao 23, #FFFFFF@0.96 (dang chon @0.85), corner 4,
                   chu = 8 dau cach + ten, ts11 #EDEDED GothamBold, icon 12x12 tai (0,5),(0,5)
   Tab (noi dung): (1,-95)x(1,-30) tai (0,95),(0,30), UIPadding bottom 5
     Frame       : (1,-5)x(1,0), UIListLayout pad (0,5)
   Section (the) : header (1,0)x23 #2A2A2A corner 4, chu "   " + tieu de ts13 #C8C8C8 GothamBold
                   caret 20x20 tai (1,-25),(0,1), rotation 90 (mo) / 180 (thu gon)
                   body (1,0)x(1,-21) tai (0,21), #FFFFFF@0.96 corner 4,
                   UIListLayout pad (0,4), UIPadding top 12 left 10 bottom 0 right 0
                   separator (1,0)x5 #2A2A2A tai y=18 (bi header che, giong Atlas)
                   thu gon: folder cao dung 23 (chi con header), body an
   Label         : (1,0)x17, ts13 #FFFFFF GothamMedium, trai
   Switch        : hang (1,-20)x20, o tick 20x20 #294A7A LUON @0.4, corner 4,
                   chu "✓" (U+2713) ts18 trang SourceSans khi bat, rong khi tat;
                   Title ts13 #C8C8C8 GothamMedium nam ngay phai o tick (x = 1.2 cua o tick)
   Slider        : (1,-15)x20 #343538 corner 4; Title (0,0)x20 can le trai, chu "   "+tieu de
                   ts13 GothamBold #C8C8C8; phan da keo "Indicator" #414347 corner 4;
                   Value (0,45)x20 tai (1,-45) ts13 GothamBold #C8C8C8 giua
   Dropdown      : rong 200px (Atlas: 22/24 cai la 200, 2 cai 250), header cao 20
                   #343538 corner 4, chu "   " + tieu de + ": " + gia tri ts13 GothamBold #C8C8C8
                   caret 15x15 tai (1,-20),(0,3) rot -90
                   Box #343538 corner 4 tai (0,0),(0,24) -> ScrollingFrame "Objects" UIListLayout pad (0,0)
                   option (1,0)x20 #294A7A @1.0 (trong suot), chu 7 dau cach + gia tri ts14 GothamBold
   Input         : (1,-15)x20 #343538, TextBox (1,-10)x(1,0) tai (0,10),(0,0)
                   ts13 GothamBold #C8C8C8, placeholder = tieu de
   Button        : cao 20, #294A7A corner 4, ts13 #FFFFFF GothamBold giua, tu gian theo chu
                   (Atlas do duoc 86 / 100 / 130px), co the ep rong bang Width
   Floating btn  : 44x44 tai (0.5,-22),(0,12), iconBase + logo 28x28
   Font          : GothamBold (tieu de/nut/tab), GothamMedium (hang/nhan)

 API tuong thich voi cac call site Ivyis dang dung (WindUI):
   IvyisUI:CreateWindow{...} / :Notify{...} / :SetTheme / :GetCurrentTheme / :GetThemes
   :AddTheme / :OnThemeChange / :SetFont
   Window:Tab{Title,Icon} / :SetUIScale / :DisableTopbarButtons / :Open / :Destroy / :OnClose
   Tab:Section{Title} / :Paragraph / :Toggle / :Slider / :Dropdown / :Input / :Button / :Select
   Doi tuong con: Paragraph:SetTitle/SetDesc, Toggle:Set, Dropdown:SetValues

 Chay file nay trong executor la ra UI demo. Chay lai se xoa ban cu.
=====================================================================================
]]

local IvyisUI
do
    local TweenService = game:GetService("TweenService")
    local UserInputService = game:GetService("UserInputService")
    local TextService = game:GetService("TextService")

    -- ================== 1. HANG SO / ICON (Lucide - cung bo Atlas dung) ==================
    local ICON = {
        search = "rbxassetid://121018724060431",
        cookie = "rbxassetid://73159504540002",
        grid = "rbxassetid://81344910161871",
        route = "rbxassetid://89968303228953",
        backpack = "rbxassetid://140420225386018",
        settings = "rbxassetid://80758916183665",
        sparkles = "rbxassetid://138635884129147",
        chevronDown = "rbxassetid://134243273101015",
        chevronRight = "rbxassetid://92473583511724",
        x = "rbxassetid://110786993356448",
    }
    -- Hai asset caret dung dung nhu Atlas (thay o dump property).
    local CARET_TRIANGLE = "https://www.roblox.com/Thumbs/Asset.ashx?width=420&height=420&assetId=4731371541"
    local CARET_DROPDOWN = "https://www.roblox.com/Thumbs/Asset.ashx?width=420&height=420&assetId=4744658743"
    local FLOAT_BASE = "rbxasset://textures/ui/TopBar/iconBase.png"

    local FONT_BOLD = Enum.Font.GothamBold
    local FONT_MEDIUM = Enum.Font.GothamMedium

    local function hex(s) return Color3.fromHex(s) end

    -- ================== 2. BANG MAU (nhieu theme, giu key kieu WindUI) ==================
    local THEMES = {
        ["Atlas"] = {
            Name = "Atlas",
            Background = "#151617",
            PanelBackground = "#1E1F20", PanelBackgroundTransparency = 0,
            ElementBackground = "#FFFFFF", ElementBackgroundTransparency = 0.96,
            LabelBackground = "#FFFFFF", LabelBackgroundTransparency = 0.96,
            Text = "#FFFFFF",
            Placeholder = "#7D858B",
            Icon = "#C8C8C8",
            Outline = "#383838",
            Accent = "#294A7A",
            Button = "#2A2A2A",
            Primary = "#294A7A",
            Toggle = "#294A7A",
            Checkbox = "#294A7A",
            Slider = "#414347",
            SliderIcon = "#414347",
            Dialog = "#151617",
            TabBackground = "#1E1F20", TabBackgroundTransparency = 0,
            TabBackgroundHover = "#26282A", TabBackgroundHoverTransparency = 0,
            TabBackgroundActive = "#393B3D", TabBackgroundActiveTransparency = 0,
            TabText = "#EDEDED",
            DropdownTabBackground = "#343538",
            DropdownBackground = "#343538",
        },
        ["Atlas Light"] = {
            Name = "Atlas Light",
            Background = "#F1F2F4",
            PanelBackground = "#FFFFFF", PanelBackgroundTransparency = 0,
            ElementBackground = "#FFFFFF", ElementBackgroundTransparency = 0,
            LabelBackground = "#FFFFFF", LabelBackgroundTransparency = 0,
            Text = "#151617",
            Placeholder = "#8A9099",
            Icon = "#4A5057",
            Outline = "#D9DCE1",
            Accent = "#294A7A",
            Button = "#E4E6EA",
            Primary = "#294A7A",
            Toggle = "#294A7A",
            Checkbox = "#294A7A",
            Slider = "#294A7A",
            SliderIcon = "#C3C7CE",
            Dialog = "#FFFFFF",
            TabBackground = "#FFFFFF", TabBackgroundTransparency = 0,
            TabBackgroundHover = "#EDEFF2", TabBackgroundHoverTransparency = 0,
            TabBackgroundActive = "#DDE1E7", TabBackgroundActiveTransparency = 0,
            TabText = "#3A4048",
            DropdownTabBackground = "#E8EAEE",
            DropdownBackground = "#E8EAEE",
        },
        ["Atlas Midnight"] = {
            Name = "Atlas Midnight",
            Background = "#0D0E10",
            PanelBackground = "#141517", PanelBackgroundTransparency = 0,
            ElementBackground = "#FFFFFF", ElementBackgroundTransparency = 0.965,
            LabelBackground = "#FFFFFF", LabelBackgroundTransparency = 0.965,
            Text = "#FFFFFF",
            Placeholder = "#6D747C",
            Icon = "#B9BEC5",
            Outline = "#26282B",
            Accent = "#1F3A63",
            Button = "#1D1E21",
            Primary = "#1F3A63",
            Toggle = "#1F3A63",
            Checkbox = "#1F3A63",
            Slider = "#333639",
            SliderIcon = "#333639",
            Dialog = "#0D0E10",
            TabBackground = "#151618", TabBackgroundTransparency = 0,
            TabBackgroundHover = "#1B1D20", TabBackgroundHoverTransparency = 0,
            TabBackgroundActive = "#2B2E31", TabBackgroundActiveTransparency = 0,
            TabText = "#E4E7EA",
            DropdownTabBackground = "#282A2D",
            DropdownBackground = "#282A2D",
        },
    }

    local function normalizePalette(pal)
        local out = {}
        for k, v in pairs(pal) do
            if type(v) == "string" and v:sub(1, 1) == "#" then
                out[k] = hex(v)
            else
                out[k] = v
            end
        end
        -- alias noi bo (clone doc truc tiep)
        out.windowBg = out.Background
        out.bar = out.Accent
        out.sectionHead = out.Button
        out.card = out.ElementBackground
        out.cardTr = out.ElementBackgroundTransparency or 0
        out.field = out.DropdownBackground
        out.fieldText = out.Icon
        out.sliderTrack = out.DropdownBackground
        out.sliderFill = out.Slider
        out.checkOn = out.Checkbox or out.Toggle
        out.checkOffTr = 0.4
        out.rowText = out.Icon
        out.valueText = out.Text
        out.muted = out.Placeholder
        out.divider = out.Outline
        out.tabText = out.TabText or out.Text
        return out
    end

    local S = normalizePalette(THEMES["Atlas"])
    local currentTheme = "Atlas"
    local themeListeners = {}
    local PAINT = {}
    local PAINT_TABS = {}
    local GLOBAL_CONNS = {}

    local function trackConn(c)
        GLOBAL_CONNS[#GLOBAL_CONNS + 1] = c
        return c
    end

    local function paint(inst, prop, key)
        local v = S[key]
        if v ~= nil then inst[prop] = v end
        PAINT[#PAINT + 1] = { inst = inst, prop = prop, key = key }
        return inst
    end

    local function repaint()
        for i = #PAINT, 1, -1 do
            local e = PAINT[i]
            if e.inst and e.inst.Parent then
                local v = S[e.key]
                if v ~= nil then e.inst[e.prop] = v end
            else
                table.remove(PAINT, i)
            end
        end
        for _, e in ipairs(PAINT_TABS) do
            if e.btn and e.btn.Parent then
                e.btn.BackgroundColor3 = S.TabBackground
                e.btn.BackgroundTransparency = e.isActive() and (S.TabBackgroundActiveTransparency or 0) or (S.TabBackgroundTransparency or 0)
                if e.isActive() then e.btn.BackgroundColor3 = S.TabBackgroundActive end
            end
        end
    end

    -- ================== 3. HELPER DUNG INSTANCE ==================
    local function mk(class, props, parent)
        local o = Instance.new(class)
        if props then
            for k, v in pairs(props) do o[k] = v end
        end
        if parent then o.Parent = parent end
        return o
    end

    local function rounded(inst, px)
        return mk("UICorner", { CornerRadius = UDim.new(0, px) }, inst)
    end

    local function pad(inst, t, b, l, r)
        return mk("UIPadding", {
            PaddingTop = UDim.new(0, t or 0),
            PaddingBottom = UDim.new(0, b or 0),
            PaddingLeft = UDim.new(0, l or 0),
            PaddingRight = UDim.new(0, r or 0),
        }, inst)
    end

    local function vlist(inst, padY)
        return mk("UIListLayout", {
            Padding = UDim.new(0, padY or 0),
            FillDirection = Enum.FillDirection.Vertical,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, inst)
    end

    local function scroll(props, parent)
        local sf = mk("ScrollingFrame", props, parent)
        sf.BackgroundTransparency = props and props.BackgroundTransparency or 1
        sf.BorderSizePixel = 0
        sf.CanvasSize = UDim2.new()
        sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
        sf.ScrollBarThickness = props and props.ScrollBarThickness or 2
        sf.ScrollBarImageColor3 = Color3.fromRGB(80, 84, 88)
        return sf
    end

    local function textLabel(props, parent)
        local l = mk("TextLabel", props, parent)
        l.BackgroundTransparency = 1
        if props and props["Font"] == nil then l.Font = FONT_MEDIUM end
        if props and props["TextSize"] == nil then l.TextSize = 13 end
        return l
    end

    -- ================== 4. API CHUNG ==================
    local API = {}
    IvyisUI = API

    local notifyFolder = nil
    local notifyLayout = nil

    function API:GetThemes()
        return THEMES
    end

    function API:GetThemeNames()
        local names = {}
        for name in pairs(THEMES) do names[#names + 1] = name end
        table.sort(names)
        return names
    end

    function API:GetCurrentTheme()
        return currentTheme
    end

    function API:SetTheme(name)
        local pal = THEMES[name]
        if not pal then return end
        currentTheme = name
        local norm = normalizePalette(pal)
        for k in pairs(S) do S[k] = nil end
        for k, v in pairs(norm) do S[k] = v end
        repaint()
        for _, fn in ipairs(themeListeners) do pcall(fn, name) end
    end

    function API:AddTheme(pal)
        if type(pal) ~= "table" or not pal.Name then return end
        THEMES[pal.Name] = pal
    end

    function API:OnThemeChange(fn)
        if type(fn) == "function" then
            themeListeners[#themeListeners + 1] = fn
            pcall(fn, currentTheme)
        end
    end

    -- Atlas dung font rieng cua no; giu nguyen de giong Atlas, khong doi theo tham so.
    function API:SetFont(_) end

    function API:Notify(o)
        o = o or {}
        local parent = (gethui and gethui()) or game:GetService("CoreGui")
        if not notifyFolder or not notifyFolder.Parent then
            -- don the thong bao cu (ke ca ban chay truoc do)
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("ScreenGui") and child.Name == "IvyisUI_Notifications" then
                    pcall(function() child:Destroy() end)
                end
            end
            local holder = mk("ScreenGui", {
                Name = "IvyisUI_Notifications",
                ResetOnSpawn = false,
                ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
                IgnoreGuiInset = true,
                DisplayOrder = 100,
            }, parent)
            notifyFolder = holder
            local gv = getgenv and getgenv() or _G
            if gv.__IvyisUINotifyGui and gv.__IvyisUINotifyGui ~= holder then
                pcall(function() gv.__IvyisUINotifyGui:Destroy() end)
            end
            gv.__IvyisUINotifyGui = holder
            -- Khung chua thong bao: neo goc phai tren, chay xuong. Khong dung
            -- AutomaticSize cho chinh khung nay (tranh lech vi tri khi rong).
            local col = mk("Frame", {
                Name = "Stack",
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0, 0),
                Size = UDim2.new(0, 268, 1, 0),
                BackgroundTransparency = 1,
            }, holder)
            vlist(col, 6)
            pad(col, 12, 12, 0, 0)
            notifyLayout = col
        end

        local duration = tonumber(o.Duration) or 3
        local card = mk("Frame", {
            Name = "Notify",
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundColor3 = S.sectionHead,
            BorderSizePixel = 0,
        }, notifyLayout)
        card.AutomaticSize = Enum.AutomaticSize.Y
        rounded(card, 4)
        paint(card, "BackgroundColor3", "sectionHead")

        local strip = mk("Frame", {
            Name = "Accent",
            Size = UDim2.new(0, 3, 1, 0),
            BackgroundColor3 = S.bar,
            BorderSizePixel = 0,
        }, card)
        paint(strip, "BackgroundColor3", "bar")
        rounded(strip, 4)

        local body = mk("Frame", {
            Name = "Body",
            Size = UDim2.new(1, -8, 0, 0),
            Position = UDim2.new(0, 8, 0, 0),
            BackgroundTransparency = 1,
        }, card)
        body.AutomaticSize = Enum.AutomaticSize.Y
        vlist(body, 1)
        pad(body, 8, 8, 5, 6)

        local title = textLabel({
            Name = "Title",
            Size = UDim2.new(1, 0, 0, 15),
            Text = tostring(o.Title or ""),
            TextSize = 13,
            Font = FONT_BOLD,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, body)
        paint(title, "TextColor3", "valueText")

        local content = nil
        if o.Content and tostring(o.Content) ~= "" then
            content = textLabel({
                Name = "Content",
                Size = UDim2.new(1, 0, 0, 14),
                Text = tostring(o.Content),
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextWrapped = true,
            }, body)
            content.AutomaticSize = Enum.AutomaticSize.Y
            paint(content, "TextColor3", "muted")
        end

        local scale = mk("UIScale", { Scale = 0.92 }, card)
        card.BackgroundTransparency = 1
        if strip then strip.BackgroundTransparency = 1 end
        title.TextTransparency = 1
        if content then content.TextTransparency = 1 end

        local tweenInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        TweenService:Create(scale, tweenInfo, { Scale = 1 }):Play()
        TweenService:Create(card, tweenInfo, { BackgroundTransparency = 0 }):Play()
        TweenService:Create(strip, tweenInfo, { BackgroundTransparency = 0 }):Play()
        TweenService:Create(title, tweenInfo, { TextTransparency = 0 }):Play()
        if content then
            TweenService:Create(content, tweenInfo, { TextTransparency = 0 }):Play()
        end

        task.delay(duration, function()
            if not card.Parent then return end
            local out = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            TweenService:Create(card, out, { BackgroundTransparency = 1 }):Play()
            TweenService:Create(strip, out, { BackgroundTransparency = 1 }):Play()
            TweenService:Create(title, out, { TextTransparency = 1 }):Play()
            if content then TweenService:Create(content, out, { TextTransparency = 1 }):Play() end
            task.delay(0.25, function()
                pcall(function() card:Destroy() end)
            end)
        end)
        return card
    end

    -- ================== 5. CUA SO ==================
    function API:CreateWindow(cfg)
        cfg = cfg or {}
        local gv = getgenv and getgenv() or _G
        if gv.__IvyisUIScreenGui then
            pcall(function() gv.__IvyisUIScreenGui:Destroy() end)
        end
        if gv.__IvyisUINotifyGui then
            pcall(function() gv.__IvyisUINotifyGui:Destroy() end)
            gv.__IvyisUINotifyGui = nil
            notifyFolder, notifyLayout = nil, nil
        end
        -- Don sach moi ScreenGui cua ban chay truoc (khong phu thuoc getgenv)
        local huiParent = (gethui and gethui()) or game:GetService("CoreGui")
        for _, child in ipairs(huiParent:GetChildren()) do
            if child:IsA("ScreenGui") and (child.Name == "IvyisUI" or child.Name == "IvyisUI_Notifications") then
                pcall(function() child:Destroy() end)
            end
        end
        for _, c in ipairs(GLOBAL_CONNS) do pcall(function() c:Disconnect() end) end
        GLOBAL_CONNS = {}
        PAINT = {}
        PAINT_TABS = {}

        local parent = (gethui and gethui()) or game:GetService("CoreGui")
        local screen = mk("ScreenGui", {
            Name = "IvyisUI",
            ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            IgnoreGuiInset = true,
        }, parent)
        gv.__IvyisUIScreenGui = screen

        local size = cfg.Size or UDim2.fromOffset(450, 280)
        local window = mk("Frame", {
            Name = "Window",
            Size = size,
            Position = UDim2.new(0, 5, 0, 100),
            BackgroundColor3 = S.windowBg,
            BorderSizePixel = 0,
            ClipsDescendants = true,
        }, screen)
        paint(window, "BackgroundColor3", "windowBg")
        rounded(window, 5)

        local uiScale = mk("UIScale", { Scale = 1 }, window)
        local winScale = 1

        -- ---- Bar ----
        local bar = mk("Frame", {
            Name = "Bar",
            Size = UDim2.new(1, 0, 0, 25),
            BackgroundColor3 = S.bar,
            BorderSizePixel = 0,
        }, window)
        paint(bar, "BackgroundColor3", "bar")
        rounded(bar, 5)

        local titleLbl = textLabel({
            Name = "Title",
            Size = UDim2.new(0.5, -10, 0, 25),
            Position = UDim2.new(0, 10, 0, 0),
            Text = tostring(cfg.Title or "Ivyis BSS"),
            TextSize = 14,
            Font = FONT_BOLD,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, bar)
        titleLbl.TextColor3 = Color3.new(1, 1, 1)

        mk("Frame", {
            Name = "Accent",
            Size = UDim2.new(1, 0, 0, 4),
            Position = UDim2.new(0, 0, 0.85, 0),
            BackgroundColor3 = S.bar,
            BorderSizePixel = 0,
        }, bar)

        -- nut thu gon cua so (giong Atlas: tam giac trang quay 90 do o goc phai thanh tieu de)
        local collapse = mk("ImageButton", {
            Name = "Indicator",
            Size = UDim2.fromOffset(20, 20),
            Position = UDim2.new(1, -25, 0, 2),
            BackgroundTransparency = 1,
            Image = CARET_TRIANGLE,
            ImageColor3 = Color3.new(1, 1, 1),
            Rotation = 90,
            AutoButtonColor = false,
        }, bar)

        -- ---- Rail ----
        local rail = mk("Frame", {
            Name = "TabButtons",
            Size = UDim2.new(0, 90, 1, -25),
            Position = UDim2.new(0, 0, 0, 25),
            BackgroundTransparency = 1,
        }, window)

        local railScroll = scroll({
            Name = "ScrollingFrame",
            Size = UDim2.new(1, 0, 1, 0),
            Position = UDim2.fromOffset(5, 5),
            BackgroundTransparency = 1,
        }, rail)
        pad(railScroll, 0, 10, 0, 10)
        vlist(railScroll, 4)

        local searchBox = mk("Frame", {
            Name = "SearchBox",
            Size = UDim2.new(1, 0, 0, 23),
            BackgroundColor3 = S.TabBackground,
            BorderSizePixel = 0,
        }, railScroll)
        paint(searchBox, "BackgroundColor3", "TabBackground")
        rounded(searchBox, 4)

        local searchInput = mk("TextBox", {
            Name = "Input",
            Size = UDim2.new(1, 0, 0, 23),
            BackgroundTransparency = 1,
            Text = "",
            PlaceholderText = "Search",
            TextSize = 11,
            Font = FONT_BOLD,
            TextXAlignment = Enum.TextXAlignment.Center,
            ClearTextOnFocus = false,
        }, searchBox)
        paint(searchInput, "TextColor3", "tabText")
        paint(searchInput, "PlaceholderColor3", "tabText")

        local searchIcon = mk("ImageLabel", {
            Name = "SearchIcon",
            Size = UDim2.fromOffset(12, 12),
            Position = UDim2.fromOffset(5, 5),
            BackgroundTransparency = 1,
            Image = ICON.search,
            ImageColor3 = S.tabText,
        }, searchBox)
        paint(searchIcon, "ImageColor3", "tabText")

        local divider = mk("Frame", {
            Name = "Divider",
            Size = UDim2.new(1, 0, 0, 2),
            BackgroundColor3 = S.divider,
            BorderSizePixel = 0,
        }, railScroll)
        paint(divider, "BackgroundColor3", "divider")

        -- ---- Vung noi dung (moi tab 1 ScrollingFrame rieng) ----
        local tabButtons = {}
        local pages = {}
        local activeIndex = 0

        local Window = {}
        Window.ScreenGui = screen
        Window.Frame = window
        Window.Tabs = {}

        local onCloseListeners = {}
        local function fireClose()
            for _, fn in ipairs(onCloseListeners) do pcall(fn) end
        end

        local allRailButtons = {}

        local function applySearch()
            local q = string.lower(searchInput.Text or "")
            for _, entry in ipairs(allRailButtons) do
                local label = string.lower(entry.label or "")
                entry.btn.Visible = (q == "") or (string.find(label, q, 1, true) ~= nil)
            end
        end

        local function setActive(index)
            activeIndex = index
            for i, entry in ipairs(allRailButtons) do
                local isActive = (i == index)
                entry.isActive = isActive
                entry.btn.BackgroundColor3 = isActive and S.TabBackgroundActive or S.TabBackground
                entry.btn.BackgroundTransparency = isActive and (S.TabBackgroundActiveTransparency or 0) or (S.TabBackgroundTransparency or 0)
                entry.labelLbl.TextColor3 = S.tabText
                if entry.page then entry.page.Visible = isActive end
            end
        end

        function Window:SelectTab(index)
            if type(index) == "string" then
                for i, entry in ipairs(allRailButtons) do
                    if entry.label == index then index = i break end
                end
            end
            index = tonumber(index)
            if not index or index < 1 or index > #allRailButtons then return end
            setActive(index)
        end

        function Window:SetUIScale(n)
            winScale = tonumber(n) or 1
            uiScale.Scale = winScale
        end

        function Window:DisableTopbarButtons(_) end

        function Window:Open()
            window.Visible = true
        end

        function Window:Hide()
            window.Visible = false
            fireClose()
        end

        function Window:OnClose(fn)
            if type(fn) == "function" then onCloseListeners[#onCloseListeners + 1] = fn end
        end

        function Window:Destroy()
            screen:Destroy()
            for _, c in ipairs(GLOBAL_CONNS) do pcall(function() c:Disconnect() end) end
            GLOBAL_CONNS = {}
        end

        -- ---- keo cua so bang thanh tieu de ----
        do
            local dragging, dragStart, startPos = false, nil, nil
            bar.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    dragStart = input.Position
                    startPos = window.Position
                end
            end)
            trackConn(UserInputService.InputChanged:Connect(function(input)
                if not dragging then return end
                if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                    local d = (input.Position - dragStart) / winScale
                    window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
                end
            end))
            trackConn(UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = false
                end
            end))
        end

        -- ---- keo goc duoi phai de doi kich thuoc (giong o Resize cua Atlas) ----
        local resizeHandle = nil
        do
            local handle = mk("TextButton", {
                Name = "Resize",
                Size = UDim2.fromOffset(20, 20),
                Position = UDim2.new(1, -20, 1, -20),
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
            }, window)
            resizeHandle = handle
            local resizing, rStart, rSize = false, nil, nil
            handle.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    resizing = true
                    rStart = input.Position
                    rSize = window.Size
                end
            end)
            trackConn(UserInputService.InputChanged:Connect(function(input)
                if not resizing then return end
                if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                    local d = (input.Position - rStart) / winScale
                    window.Size = UDim2.new(
                        rSize.X.Scale, math.max(320, rSize.X.Offset + d.X),
                        rSize.Y.Scale, math.max(200, rSize.Y.Offset + d.Y)
                    )
                end
            end))
            trackConn(UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    resizing = false
                end
            end))
        end

        -- ---- nut noi (kieu Atlas) ----
        local floating = nil
        if cfg.FloatingButton ~= false then
            floating = mk("ImageButton", {
                Name = "Button",
                Size = UDim2.fromOffset(44, 44),
                Position = UDim2.new(0.5, -22, 0, 12),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Image = FLOAT_BASE,
                AutoButtonColor = false,
                ZIndex = 5,
            }, screen)
            rounded(floating, 6)
            local logo = mk("ImageLabel", {
                Name = "Logo",
                Size = UDim2.fromOffset(28, 28),
                Position = UDim2.fromOffset(8, 8),
                BackgroundTransparency = 1,
                Image = cfg.FloatingIcon or "rbxassetid://4503856569",
            }, floating)
            floating.MouseButton1Click:Connect(function()
                window.Visible = not window.Visible
                if not window.Visible then fireClose() end
            end)
        end

        -- ---- thu nho cua so: chi giu thanh tieu de, khong an ca tab ----
        local minimized = false
        local expandedSize = nil
        local function setMinimized(value)
            value = value and true or false
            if minimized == value then return end
            minimized = value
            if value then
                expandedSize = window.Size
                for _, entry in ipairs(allRailButtons) do
                    if entry.page then entry.page.Visible = false end
                end
                rail.Visible = false
                if resizeHandle then resizeHandle.Visible = false end
                window.Size = UDim2.new(expandedSize.X.Scale, expandedSize.X.Offset, 0, 25)
                collapse.Rotation = 270
            else
                rail.Visible = true
                if resizeHandle then resizeHandle.Visible = true end
                window.Size = expandedSize or UDim2.fromOffset(450, 280)
                collapse.Rotation = 90
                local active = allRailButtons[activeIndex]
                if active and active.page then active.page.Visible = true end
            end
        end
        Window.SetMinimized = setMinimized

        collapse.MouseButton1Click:Connect(function()
            setMinimized(not minimized)
        end)

        searchInput:GetPropertyChangedSignal("Text"):Connect(applySearch)
        searchInput.Focused:Connect(function() end)

        -- ---- Tab ----
        function Window:Tab(o)
            o = o or {}
            local index = #allRailButtons + 1

            local btn = mk("TextButton", {
                Name = "TextButton",
                Size = UDim2.new(1, 0, 0, 23),
                BackgroundColor3 = S.TabBackground,
                BackgroundTransparency = S.TabBackgroundTransparency or 0,
                BorderSizePixel = 0,
                Text = string.rep(" ", 8) .. tostring(o.Title or ("Tab " .. index)),
                TextSize = 11,
                Font = FONT_BOLD,
                TextXAlignment = Enum.TextXAlignment.Left,
                AutoButtonColor = false,
                LayoutOrder = index,
            }, railScroll)
            paint(btn, "TextColor3", "tabText")
            rounded(btn, 4)

            local icon = mk("ImageLabel", {
                Name = "TabIcon",
                Size = UDim2.fromOffset(12, 12),
                Position = UDim2.fromOffset(5, 5),
                BackgroundTransparency = 1,
                Image = ICON[o.Icon] or (type(o.Icon) == "string" and o.Icon:match("^rbxasset") and o.Icon) or ICON.sparkles,
                ImageColor3 = S.tabText,
            }, btn)
            paint(icon, "ImageColor3", "tabText")

            local scroller = scroll({
                Name = "Tab",
                Size = UDim2.new(1, -95, 1, -30),
                Position = UDim2.new(0, 95, 0, 30),
                BackgroundTransparency = 1,
                Visible = false,
            }, window)
            pad(scroller, 0, 5, 0, 0)

            local page = mk("Frame", {
                Name = "Frame",
                Size = UDim2.new(1, -5, 0, 0),
                BackgroundTransparency = 1,
            }, scroller)
            page.AutomaticSize = Enum.AutomaticSize.Y
            vlist(page, 5)

            local entry = {
                btn = btn,
                label = tostring(o.Title or ("Tab " .. index)),
                page = scroller,
                isActive = false,
                labelLbl = btn,
            }
            allRailButtons[#allRailButtons + 1] = entry
            PAINT_TABS[#PAINT_TABS + 1] = { btn = btn, isActive = function() return entry.isActive end }

            local Tab = {}
            Tab.Page = page
            Tab.Scroller = scroller
            -- Tuong thich WindUI: code cu chen GUI tu ve vao tab qua
            -- tab.UIElements.ContainerFrame (gear list). Luon tro vao the dang mo.
            Tab.UIElements = { ContainerFrame = page, Main = scroller }
            Tab.__currentCard = nil
            Tab.__index = index
            Tab.__cards = {}

            local function nextOrder(card)
                card.__order = (card.__order or 0) + 1
                return card.__order
            end

            local function setCollapsed(card, value)
                card.collapsed = value
                if card.box then card.box.Visible = not value end
                if card.caret then card.caret.Rotation = value and 180 or 90 end
                if card.folder then
                    if value then
                        card.folder.AutomaticSize = Enum.AutomaticSize.None
                        card.folder.Size = UDim2.new(1, 0, 0, card.head and 23 or 0)
                    else
                        card.folder.AutomaticSize = Enum.AutomaticSize.Y
                        card.folder.Size = UDim2.new(1, 0, 0, 0)
                    end
                end
            end

            local function newCard(title)
                local folder = mk("Frame", {
                    Name = "Folder",
                    Size = UDim2.new(1, 0, 0, 0),
                    BackgroundTransparency = 1,
                    LayoutOrder = 1000 + #Tab.__cards,
                }, page)
                folder.AutomaticSize = Enum.AutomaticSize.Y

                local card = { folder = folder }
                local boxY = 0

                if title and tostring(title) ~= "" then
                    local head = mk("TextButton", {
                        Name = "TextButton",
                        Size = UDim2.new(1, 0, 0, 23),
                        BackgroundColor3 = S.sectionHead,
                        BorderSizePixel = 0,
                        Text = "   " .. tostring(title),
                        TextSize = 13,
                        Font = FONT_BOLD,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        AutoButtonColor = false,
                        LayoutOrder = 0,
                    }, folder)
                    paint(head, "BackgroundColor3", "sectionHead")
                    paint(head, "TextColor3", "rowText")
                    rounded(head, 4)

                    local caret = mk("ImageLabel", {
                        Name = "Indicator",
                        Size = UDim2.fromOffset(20, 20),
                        Position = UDim2.new(1, -25, 0, 1),
                        BackgroundTransparency = 1,
                        Image = CARET_TRIANGLE,
                        Rotation = 90,
                    }, head)
                    card.head, card.caret = head, caret
                    boxY = 21
                    head.MouseButton1Click:Connect(function()
                        setCollapsed(card, not card.collapsed)
                    end)
                end

                local box = mk("Frame", {
                    Name = "Box",
                    Size = UDim2.new(1, 0, 0, 0),
                    Position = UDim2.new(0, 0, 0, boxY),
                    BackgroundColor3 = S.card,
                    BackgroundTransparency = S.cardTr,
                    BorderSizePixel = 0,
                }, folder)
                paint(box, "BackgroundColor3", "card")
                paint(box, "BackgroundTransparency", "cardTr")
                box.AutomaticSize = Enum.AutomaticSize.Y
                rounded(box, 4)
                -- Atlas do duoc top=12 bottom=0 left=10 right=0, nhung de bottom=0 thi
                -- nut / dropdown / o input nam cuoi the bi cham vao vien duoi. Them 10px
                -- duoi cho can voi khoang trong o tren.
                pad(box, 12, 10, 10, 0)
                vlist(box, 4)
                card.box = box
                if Tab.UIElements then Tab.UIElements.ContainerFrame = box end

                -- Atlas cung dat mot thanh 5px mau #2A2A2A ngay duoi header (y=18) nen bi
                -- header che khuat, khong anh huong bo cuc. Giu lai cho giong cay UI Atlas.
                local sep = mk("Frame", {
                    Name = "Frame",
                    Size = UDim2.new(1, 0, 0, 5),
                    Position = UDim2.new(0, 0, 0, 18),
                    BackgroundColor3 = S.sectionHead,
                    BorderSizePixel = 0,
                }, folder)
                paint(sep, "BackgroundColor3", "sectionHead")

                Tab.__cards[#Tab.__cards + 1] = card
                Tab.__currentCard = card
                return card
            end

            local function currentCard()
                if Tab.__currentCard then return Tab.__currentCard end
                return newCard(nil)
            end

            -- ===== cac loai element =====
            function Tab:Section(o)
                return newCard(o and o.Title or "")
            end

            function Tab:Paragraph(o)
                o = o or {}
                local card = currentCard()
                local order = nextOrder(card)
                local titleLbl = textLabel({
                    Name = "Label",
                    Size = UDim2.new(1, 0, 0, 17),
                    Text = tostring(o.Title or ""),
                    TextSize = 13,
                    Font = FONT_MEDIUM,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    LayoutOrder = order,
                }, card.box)
                paint(titleLbl, "TextColor3", "valueText")

                local descLbl = nil
                if o.Desc and tostring(o.Desc) ~= "" then
                    descLbl = textLabel({
                        Name = "Desc",
                        Size = UDim2.new(1, 0, 0, 14),
                        Text = tostring(o.Desc),
                        TextSize = 12,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextWrapped = true,
                        LayoutOrder = order + 1,
                    }, card.box)
                    descLbl.AutomaticSize = Enum.AutomaticSize.Y
                    paint(descLbl, "TextColor3", "muted")
                    card.__order = order + 1
                end

                local obj = {}
                function obj:SetTitle(v)
                    titleLbl.Text = tostring(v or "")
                end
                function obj:SetDesc(v)
                    if descLbl then
                        descLbl.Text = tostring(v or "")
                    elseif v and tostring(v) ~= "" then
                        descLbl = textLabel({
                            Name = "Desc",
                            Size = UDim2.new(1, 0, 0, 14),
                            Text = tostring(v),
                            TextSize = 12,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            TextWrapped = true,
                            LayoutOrder = order + 1,
                        }, card.box)
                        descLbl.AutomaticSize = Enum.AutomaticSize.Y
                        paint(descLbl, "TextColor3", "muted")
                        -- Giu cho LayoutOrder cua cac element sau khong bi trung.
                        card.__order = order + 1
                    end
                end
                obj.Label = titleLbl
                return obj
            end

            function Tab:Label(o)
                return Tab:Paragraph(o)
            end

            function Tab:Toggle(o)
                o = o or {}
                local card = currentCard()
                local order = nextOrder(card)
                local hasDesc = o.Desc and tostring(o.Desc) ~= ""

                local row = mk("Frame", {
                    Name = "Switch",
                    Size = UDim2.new(1, -20, 0, hasDesc and 32 or 20),
                    BackgroundTransparency = 1,
                    LayoutOrder = order,
                }, card.box)

                local check = mk("TextButton", {
                    Name = "Switch",
                    Size = UDim2.fromOffset(20, 20),
                    Position = UDim2.fromOffset(0, 0),
                    BackgroundColor3 = S.checkOn,
                    BorderSizePixel = 0,
                    Text = "",
                    TextSize = 18,
                    Font = Enum.Font.SourceSans,
                    TextColor3 = Color3.new(1, 1, 1),
                    AutoButtonColor = false,
                }, row)
                paint(check, "BackgroundColor3", "checkOn")
                paint(check, "BackgroundTransparency", "checkOffTr")
                rounded(check, 4)

                local title = textLabel({
                    Name = "Title",
                    Size = UDim2.new(0, 240, 0, 20),
                    Position = UDim2.new(1.2, 0, 0, 0),
                    Text = tostring(o.Title or ""),
                    TextSize = 13,
                    Font = FONT_MEDIUM,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }, check)
                paint(title, "TextColor3", "rowText")

                local desc = nil
                if hasDesc then
                    desc = textLabel({
                        Name = "Desc",
                        Size = UDim2.new(0, 240, 0, 14),
                        Position = UDim2.new(1.2, 0, 0, 15),
                        Text = tostring(o.Desc),
                        TextSize = 12,
                        TextXAlignment = Enum.TextXAlignment.Left,
                    }, check)
                    paint(desc, "TextColor3", "muted")
                end

                local value = o.Value and true or false
                local obj = { Value = value }

                local function apply(v, fire)
                    value = v and true or false
                    obj.Value = value
                    -- Atlas: o tick LUON giu do mo 0.40, chi khac nhau o dau "✓" khi bat
                    check.Text = value and "✓" or ""
                    check.BackgroundTransparency = S.checkOffTr or 0.4
                    if fire and type(o.Callback) == "function" then
                        task.spawn(o.Callback, value)
                    end
                end

                function obj:Set(v)
                    apply(v, false)
                end

                check.MouseButton1Click:Connect(function()
                    apply(not value, true)
                end)

                apply(value, false)
                return obj
            end

            function Tab:Slider(o)
                o = o or {}
                local card = currentCard()
                local order = nextOrder(card)

                local minV = tonumber(o.Min) or (type(o.Value) == "table" and tonumber(o.Value.Min)) or 0
                local maxV = tonumber(o.Max) or (type(o.Value) == "table" and tonumber(o.Value.Max)) or 100
                local curV = (type(o.Value) == "table" and tonumber(o.Value.Default))
                    or (type(o.Value) == "number" and tonumber(o.Value))
                    or minV
                local step = tonumber(o.Step) or 0
                if maxV <= minV then maxV = minV + 1 end

                local row = mk("Frame", {
                    Name = "Slider",
                    Size = UDim2.new(1, -15, 0, 20),
                    BackgroundColor3 = S.sliderTrack,
                    BorderSizePixel = 0,
                    LayoutOrder = order,
                }, card.box)
                paint(row, "BackgroundColor3", "sliderTrack")
                rounded(row, 4)

                local fill = mk("Frame", {
                    Name = "Indicator",
                    Size = UDim2.new(0, 0, 1, 0),
                    BackgroundColor3 = S.sliderFill,
                    BorderSizePixel = 0,
                    ZIndex = 2,
                }, row)
                paint(fill, "BackgroundColor3", "sliderFill")
                rounded(fill, 4)

                local title = textLabel({
                    Name = "Title",
                    Size = UDim2.new(0, 0, 0, 20),
                    Position = UDim2.new(0, 0, 0.5, -10),
                    Text = "   " .. tostring(o.Title or ""),
                    TextSize = 13,
                    Font = FONT_BOLD,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 3,
                }, row)
                paint(title, "TextColor3", "rowText")

                local valueLbl = textLabel({
                    Name = "Value",
                    Size = UDim2.new(0, 45, 0, 20),
                    Position = UDim2.new(1, -45, 0.5, -10),
                    Text = "",
                    TextSize = 13,
                    Font = FONT_BOLD,
                    TextXAlignment = Enum.TextXAlignment.Center,
                    ZIndex = 3,
                }, row)
                paint(valueLbl, "TextColor3", "rowText")

                -- Atlas dat ten nut keo nay la "Button" (ts8 Legacy) de trong suot.
                local drag = mk("TextButton", {
                    Name = "Button",
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Text = "",
                    TextSize = 8,
                    Font = Enum.Font.Legacy,
                    TextColor3 = Color3.fromRGB(27, 42, 53),
                    ZIndex = 4,
                }, row)

                local value = math.clamp(curV, minV, maxV)

                local function refreshText()
                    if type(o.Format) == "function" then
                        valueLbl.Text = tostring(o.Format(value))
                    elseif step >= 1 then
                        valueLbl.Text = tostring(math.floor(value + 0.5))
                    else
                        valueLbl.Text = tostring(math.floor(value * 100 + 0.5) / 100)
                    end
                end

                local function setValue(v, fire)
                    v = math.clamp(tonumber(v) or minV, minV, maxV)
                    if step > 0 then v = minV + math.floor((v - minV) / step + 0.5) * step end
                    value = v
                    fill.Size = UDim2.new((value - minV) / (maxV - minV), 0, 1, 0)
                    refreshText()
                    if fire and type(o.Callback) == "function" then
                        task.spawn(o.Callback, value)
                    end
                end

                local dragging = false
                local function fromX(x)
                    local rel = math.clamp((x - row.AbsolutePosition.X) / math.max(row.AbsoluteSize.X, 1), 0, 1)
                    setValue(minV + (maxV - minV) * rel, true)
                end

                drag.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        dragging = true
                        fromX(input.Position.X)
                    end
                end)
                trackConn(UserInputService.InputChanged:Connect(function(input)
                    if not dragging then return end
                    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                        fromX(input.Position.X)
                    end
                end))
                trackConn(UserInputService.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        dragging = false
                    end
                end))

                local obj = {}
                function obj:Set(v) setValue(v, false) end
                function obj:Get() return value end
                setValue(value, false)
                return obj
            end

            function Tab:Dropdown(o)
                o = o or {}
                local card = currentCard()
                local order = nextOrder(card)
                local values = {}
                for _, v in ipairs(o.Values or {}) do values[#values + 1] = tostring(v) end
                local multi = o.Multi == true
                -- Atlas: dropdown mac dinh rong 200px (22/24 cai trong UI Atlas), co the doi bang o.Width
                local rowX
                if o.Width == "full" then
                    rowX = UDim.new(1, 0)
                elseif type(o.Width) == "number" then
                    rowX = UDim.new(0, o.Width)
                else
                    rowX = UDim.new(0, 200)
                end

                local row = mk("Frame", {
                    Name = "Dropdown",
                    Size = UDim2.new(rowX.Scale, rowX.Offset, 0, 20),
                    BackgroundTransparency = 1,
                    LayoutOrder = order,
                }, card.box)

                local head = mk("TextButton", {
                    Name = "TextButton",
                    Size = UDim2.new(1, 0, 0, 20),
                    BackgroundColor3 = S.field,
                    BorderSizePixel = 0,
                    Text = "",
                    TextSize = 13,
                    Font = FONT_BOLD,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    AutoButtonColor = false,
                }, row)
                paint(head, "BackgroundColor3", "field")
                paint(head, "TextColor3", "fieldText")
                rounded(head, 4)

                local caret = mk("ImageLabel", {
                    Name = "Indicator",
                    Size = UDim2.fromOffset(15, 15),
                    Position = UDim2.new(1, -20, 0, 3),
                    BackgroundTransparency = 1,
                    Image = CARET_DROPDOWN,
                    Rotation = -90,
                }, head)

                local dropdownBox = mk("Frame", {
                    Name = "Box",
                    Size = UDim2.new(1, 0, 0, 0),
                    Position = UDim2.new(0, 0, 0, 24),
                    BackgroundColor3 = S.field,
                    BorderSizePixel = 0,
                    Visible = false,
                    ClipsDescendants = true,
                    ZIndex = 3,
                }, row)
                paint(dropdownBox, "BackgroundColor3", "field")
                rounded(dropdownBox, 4)

                local objects = scroll({
                    Name = "Objects",
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    ZIndex = 3,
                }, dropdownBox)
                vlist(objects, 0)
                rounded(objects, 4)

                local selected = o.Value
                local selectedSet = {}
                if type(selected) == "table" then
                    for _, v in ipairs(selected) do selectedSet[tostring(v)] = true end
                elseif selected ~= nil and tostring(selected) ~= "" then
                    selectedSet[tostring(selected)] = true
                end

                local obj = { Value = selected, Values = values }

                local function headerText()
                    local titleTxt = tostring(o.Title or "")
                    if multi then
                        local picked = {}
                        for _, v in ipairs(values) do
                            if selectedSet[v] then picked[#picked + 1] = v end
                        end
                        local tail = (#picked == 0) and "" or (": " .. (#picked <= 2 and table.concat(picked, ", ") or (#picked .. " selected")))
                        return "   " .. titleTxt .. tail
                    end
                    local first = nil
                    for _, v in ipairs(values) do
                        if selectedSet[v] then first = v break end
                    end
                    if not first and type(obj.Value) == "string" then first = obj.Value end
                    return "   " .. titleTxt .. (first and (": " .. first) or "")
                end

                local open = false
                local function applyOpen()
                    -- Do tu Atlas that: box = min(so lua chon * 20, 155); dropdown = box + 25
                    -- (header 20 + khe 4 + 1px duoi cung) -> luon thua 5px truoc element ke tiep.
                    local height = math.min(#values * 20, 155)
                    if open then
                        dropdownBox.Visible = true
                        dropdownBox.Size = UDim2.new(1, 0, 1, -25)
                        row.Size = UDim2.new(rowX.Scale, rowX.Offset, 0, math.max(height, 20) + 25)
                        caret.Rotation = 90
                    else
                        dropdownBox.Visible = false
                        dropdownBox.Size = UDim2.new(1, 0, 1, -20)
                        row.Size = UDim2.new(rowX.Scale, rowX.Offset, 0, 20)
                        caret.Rotation = -90
                    end
                    head.Text = headerText()
                end

                local optionButtons = {}

                local function rebuild()
                    for _, b in ipairs(optionButtons) do
                        pcall(function() b:Destroy() end)
                    end
                    optionButtons = {}
                    for i, v in ipairs(values) do
                        local opt = mk("TextButton", {
                            Name = "DropdownButton",
                            Size = UDim2.new(1, 0, 0, 20),
                            BackgroundColor3 = S.bar,
                            BackgroundTransparency = 1,
                            BorderSizePixel = 0,
                            Text = "       " .. v,
                            TextSize = 14,
                            Font = FONT_BOLD,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            AutoButtonColor = false,
                            LayoutOrder = i,
                            ZIndex = 3,
                        }, objects)
                        paint(opt, "TextColor3", "fieldText")
                        rounded(opt, 4)
                        opt.MouseEnter:Connect(function()
                            opt.BackgroundTransparency = 0.85
                        end)
                        opt.MouseLeave:Connect(function()
                            opt.BackgroundTransparency = 1
                        end)
                        opt.MouseButton1Click:Connect(function()
                            local changed = false
                            if multi then
                                if selectedSet[v] then
                                    selectedSet[v] = nil
                                else
                                    selectedSet[v] = true
                                end
                                local list = {}
                                for _, x in ipairs(values) do
                                    if selectedSet[x] then list[#list + 1] = x end
                                end
                                obj.Value = list
                                changed = true
                                opt.Text = (selectedSet[v] and "   ✓   " or "       ") .. v
                            else
                                selectedSet = { [v] = true }
                                obj.Value = v
                                changed = true
                                open = false
                                applyOpen()
                            end
                            head.Text = headerText()
                            if changed and type(o.Callback) == "function" then
                                task.spawn(o.Callback, obj.Value)
                            end
                        end)
                        if multi and selectedSet[v] then opt.Text = "   ✓   " .. v end
                        optionButtons[#optionButtons + 1] = opt
                    end
                    local n = #values
                    objects.CanvasSize = UDim2.new(0, 0, 0, n * 20)
                    if open then applyOpen() end
                end

                function obj:SetValues(list)
                    values = {}
                    for _, v in ipairs(list or {}) do values[#values + 1] = tostring(v) end
                    obj.Values = values
                    -- Lua chon cu co the da bi xoa khoi danh sach moi: bo chon va cap
                    -- nhat lai dong header, neu khong header se hien gia tri cu.
                    local stillThere = false
                    for _, v in ipairs(values) do
                        if selectedSet[v] then stillThere = true break end
                    end
                    if not stillThere then
                        selectedSet = {}
                        obj.Value = nil
                    end
                    rebuild()
                    head.Text = headerText()
                end

                function obj:Set(v)
                    if type(v) == "table" then
                        selectedSet = {}
                        for _, x in ipairs(v) do selectedSet[tostring(x)] = true end
                        obj.Value = v
                    elseif v ~= nil then
                        selectedSet = { [tostring(v)] = true }
                        obj.Value = tostring(v)
                    end
                    rebuild()
                    head.Text = headerText()
                end

                head.MouseButton1Click:Connect(function()
                    open = not open
                    applyOpen()
                end)

                rebuild()
                head.Text = headerText()
                return obj
            end

            function Tab:Input(o)
                o = o or {}
                local card = currentCard()
                local order = nextOrder(card)

                local rowSize
                if type(o.Width) == "number" then
                    rowSize = UDim2.fromOffset(o.Width, 20)
                elseif o.Width == "full" then
                    rowSize = UDim2.new(1, -15, 0, 20)
                else
                    -- Atlas: o nhap lieu thuong la (1,-15) full chieu rong, co cai (0,200)
                    rowSize = UDim2.new(1, -15, 0, 20)
                end

                local row = mk("Frame", {
                    Name = "TextBox",
                    Size = rowSize,
                    BackgroundColor3 = S.field,
                    BorderSizePixel = 0,
                    LayoutOrder = order,
                }, card.box)
                paint(row, "BackgroundColor3", "field")
                rounded(row, 4)

                local tb = mk("TextBox", {
                    Name = "TextBox",
                    Size = UDim2.new(1, -10, 1, 0),
                    Position = UDim2.fromOffset(10, 0),
                    BackgroundTransparency = 1,
                    Text = tostring(o.Value or ""),
                    PlaceholderText = tostring(o.Placeholder or o.Title or ""),
                    TextSize = 13,
                    Font = FONT_BOLD,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ClearTextOnFocus = false,
                }, row)
                paint(tb, "TextColor3", "fieldText")
                paint(tb, "PlaceholderColor3", "muted")

                local obj = { Value = o.Value }
                local function commit()
                    obj.Value = tb.Text
                    if type(o.Callback) == "function" then
                        task.spawn(o.Callback, tb.Text)
                    end
                end
                tb.FocusLost:Connect(commit)

                function obj:Set(v)
                    tb.Text = tostring(v or "")
                    obj.Value = tb.Text
                end
                function obj:Get() return tb.Text end
                obj.TextBox = tb
                return obj
            end

            function Tab:Button(o)
                o = o or {}
                local card = currentCard()
                local order = nextOrder(card)

                local btn = mk("TextButton", {
                    Name = "Button",
                    Size = UDim2.fromOffset(130, 20),
                    BackgroundColor3 = S.bar,
                    BorderSizePixel = 0,
                    Text = tostring(o.Title or "Button"),
                    TextSize = 13,
                    Font = FONT_BOLD,
                    TextXAlignment = Enum.TextXAlignment.Center,
                    AutoButtonColor = false,
                    ClipsDescendants = true,
                    LayoutOrder = order,
                }, card.box)
                paint(btn, "BackgroundColor3", "bar")
                rounded(btn, 4)
                btn.TextColor3 = Color3.new(1, 1, 1)

                -- Atlas: nut tu co gian theo do dai chu (do duoc 86 / 100 / 130px)
                local function fitWidth()
                    if type(o.Width) == "number" then
                        btn.Size = UDim2.fromOffset(o.Width, 20)
                    elseif o.Width == "full" then
                        btn.Size = UDim2.new(1, 0, 0, 20)
                    else
                        local measured = TextService:GetTextSize(btn.Text, btn.TextSize, btn.Font, Vector2.new(1000, 20))
                        btn.Size = UDim2.fromOffset(math.max(86, math.ceil(measured.X) + 25), 20)
                    end
                end
                fitWidth()
                btn:GetPropertyChangedSignal("Text"):Connect(fitWidth)
                btn.MouseButton1Click:Connect(function()
                    if type(o.Callback) == "function" then task.spawn(o.Callback) end
                end)

                local obj = {}
                function obj:SetTitle(v) btn.Text = tostring(v or "") end
                obj.Button = btn
                return obj
            end

            function Tab:Divider()
                local card = currentCard()
                local order = nextOrder(card)
                local d = mk("Frame", {
                    Name = "Divider",
                    Size = UDim2.new(1, 0, 0, 1),
                    BackgroundColor3 = S.divider,
                    BorderSizePixel = 0,
                    LayoutOrder = order,
                }, card.box)
                paint(d, "BackgroundColor3", "divider")
                return d
            end

            function Tab:Select()
                Window:SelectTab(index)
                return Tab
            end

            Window.Tabs[#Window.Tabs + 1] = Tab
            btn.MouseButton1Click:Connect(function()
                setActive(index)
            end)
            return Tab
        end

        task.defer(function()
            if #allRailButtons > 0 then setActive(1) end
        end)
        return Window
    end
end

local Events = RS:FindFirstChild("Events") or RS:WaitForChild("Events", 5)

local remoteCache = {}
local function getRemote(name)
    if remoteCache[name] then return remoteCache[name] end
    if Events and Events:FindFirstChild(name) then
        remoteCache[name] = Events[name]
        return Events[name]
    end
    for _, desc in ipairs(RS:GetDescendants()) do
        if desc.Name == name and (desc:IsA("RemoteFunction") or desc:IsA("RemoteEvent")) then
            remoteCache[name] = desc
            return desc
        end
    end
    return nil
end

local function callRemote(remote, ...)
    if not remote then return nil end
    if remote:IsA("RemoteFunction") then
        return remote:InvokeServer(...)
    elseif remote:IsA("RemoteEvent") then
        remote:FireServer(...)
        return true
    end
    return nil
end

local function safeClientCall(eventName, ...)
    local args = { ... }
    local done = false
    pcall(function()
        local evMod = require(RS.Events)
        if evMod and type(evMod.ClientCall) == "function" then
            evMod.ClientCall(eventName, unpack(args))
            done = true
        end
    end)
    if done then return end
    local r = getRemote(eventName)
    if r then callRemote(r, unpack(args)) end
end

local TREAT_SHOP_POS = CFrame.new(-220.1, 5.8, 84.5)
local RJ_SHOP_POS = CFrame.new(-291.6, 52.4, 66.6)
local TREAT_BOND = 10
local TREAT_COST = 10000

local feedRunning = false
local rollRunning = false
local targetLevel = 15
local targetBeeCount = 50
local walkSpeed = 60
local autoBuyEnabled = true
local returnHiveEnabled = true
local autoPauseAtlas = true
local activeTween = nil
local feedToggle = nil
local rollToggle = nil
local autoSyncToggle = nil
local pauseAtlas
local stopAutoFeed
local stopAutoRoll
local restoreRollSettings
local captureRollSettings

function stopAutoFeed(keepAtlas)
    feedRunning = false
    local hold = getgenv and getgenv().IvyisAtlasHold
    if hold and hold.release then pcall(hold.release) end
    if activeTween then
        pcall(function() activeTween:Cancel() end)
        activeTween = nil
    end
    if not keepAtlas and pauseAtlas then
        pauseAtlas(false)
    end
    if feedToggle then
        pcall(function() feedToggle:Set(false) end)
    end
end

function stopAutoRoll(keepAtlas)
    rollRunning = false
    local hold = getgenv and getgenv().IvyisAtlasHold
    if hold and hold.release then pcall(hold.release) end
    if activeTween then
        pcall(function() activeTween:Cancel() end)
        activeTween = nil
    end
    if not keepAtlas and pauseAtlas then
        pauseAtlas(false)
    end
    if rollToggle then
        pcall(function() rollToggle:Set(false) end)
    end
    -- Put the game's own roll settings back where they were before auto-roll.
    if restoreRollSettings then
        pcall(restoreRollSettings)
    end
end
local HIVE_CONFIGS_DIR = "AutoFeedBSS/HiveConfigs"
local currentBuildMode = "Composition"
local selectedHiveSlots = {}
local exactSlotTargets = {}
local compositionTargets = {}
local selectedBeeId = "BuoyantBee"
local selectedTargetQty = 5
local selectedTargetGifted = "Any"
local hasUserConfiguredTargets = false
local autoSyncSettings = true
local autoBuyRJ = true
local minRJThreshold = 1000
local buyRJAmount = 10000
-- The two "roll until" controls from the web pages (/selectbee and /buildhive):
--   untilGifted  = Bee Swarm's "Until gifted" must stay on for this account.
--   syncSettings = the script may turn on "Until mythic" / "Until legendary"
--                  by itself while rolling that rarity.
--   rev          = revision of the stored choice; echoed back in every state
--                  post so the server can tell stale reads from fresh ones.
--   stopOnMythic = select bee page only: hand the roll back as soon as a mythic
--                  shows up so it is not rolled away by accident.
--   keepMythics  = map of mythic bee ids that may stop that roll. Empty means
--                  any mythic stops it; otherwise the others are rolled past.
local forcedRollFlags = {
    untilGifted = false,
    syncSettings = true,
    stopOnMythic = false,
    keepMythics = {},
    rev = 0,
}
local configNameInput = "MyHiveBuild"
local importJsonInput = ""
local selectedSavedConfig = "None"

local function ensureHiveConfigDir()
    if not makefolder then return end
    if isfolder and not isfolder("AutoFeedBSS") then
        pcall(makefolder, "AutoFeedBSS")
    end
    if isfolder and not isfolder(HIVE_CONFIGS_DIR) then
        pcall(makefolder, HIVE_CONFIGS_DIR)
    end
end

local function listHiveConfigs()
    ensureHiveConfigDir()
    local list = {}
    if listfiles then
        local ok, files = pcall(listfiles, HIVE_CONFIGS_DIR)
        if ok and type(files) == "table" then
            for _, f in ipairs(files) do
                local name = tostring(f):match("([^/\\]+)%.json$")
                if name then
                    table.insert(list, name)
                end
            end
        end
    end
    table.sort(list)
    if #list == 0 then
        table.insert(list, "None")
    end
    return list
end

local function serializeHiveConfig(name)
    local data = {
        name = name or configNameInput or "MyHiveBuild",
        version = 2,
        buildMode = currentBuildMode,
        composition = compositionTargets,
        exactSlots = exactSlotTargets,
        selectedSlots = selectedHiveSlots,
        settings = {
            autoSyncSettings = autoSyncSettings,
            autoBuyRJ = autoBuyRJ,
            buyRJAmount = buyRJAmount
        }
    }
    local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if ok and encoded then return encoded end
    return nil
end

local function applyLoadedHiveConfig(data)
    if type(data) ~= "table" then return false end
    if data.buildMode then
        currentBuildMode = (data.buildMode == "Exact" or data.buildMode == "Exact (100% Slot Order)") and "Exact" or "Composition"
    end
    if type(data.composition) == "table" then
        compositionTargets = {}
        for _, item in ipairs(data.composition) do
            if type(item) == "table" and item.beeId and tonumber(item.count) then
                table.insert(compositionTargets, {
                    beeId = item.beeId,
                    gifted = item.gifted or "Any",
                    count = tonumber(item.count)
                })
            end
        end
    end
    if type(data.exactSlots) == "table" then
        exactSlotTargets = {}
        for k, v in pairs(data.exactSlots) do
            if type(v) == "table" and v.beeId then
                exactSlotTargets[tostring(k)] = {
                    beeId = v.beeId,
                    gifted = v.gifted or "Any"
                }
            end
        end
    end
    if type(data.selectedSlots) == "table" then
        selectedHiveSlots = {}
        for k, v in pairs(data.selectedSlots) do
            if v then selectedHiveSlots[tostring(k)] = true end
        end
    end
    if type(data.settings) == "table" then
        if data.settings.autoSyncSettings ~= nil then autoSyncSettings = data.settings.autoSyncSettings end
        if data.settings.autoBuyRJ ~= nil then autoBuyRJ = data.settings.autoBuyRJ end
        if data.settings.buyRJAmount ~= nil then buyRJAmount = tonumber(data.settings.buyRJAmount) or buyRJAmount end
    end
    hasUserConfiguredTargets = (#compositionTargets > 0) or (next(exactSlotTargets) ~= nil)
    return true
end

local BOND_TABLE = {
    [1] = 10, [2] = 40, [3] = 200, [4] = 750, [5] = 4000,
    [6] = 15000, [7] = 60000, [8] = 270000, [9] = 450000,
    [10] = 1200000, [11] = 2000000, [12] = 4000000, [13] = 7000000,
    [14] = 15000000, [15] = 120000000, [16] = 450000000, [17] = 1900000000,
    [18] = 7500000000, [19] = 15000000000, [20] = 475000000000,
    [21] = 4500000000000, [22] = 45000000000000, [23] = 450000000000000,
    [24] = 4500000000000000, [25] = 45000000000000000
}

local function formatNum(n)
    if not n or n ~= n then return "0" end
    if n >= 1e12 then return string.format("%.2fT", n/1e12)
    elseif n >= 1e9 then return string.format("%.2fB", n/1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n/1e6)
    elseif n >= 1e3 then return string.format("%.1fK", n/1e3)
    else return tostring(math.floor(n)) end
end

local function getCumulativeBond(lvl)
    local total = 0
    for i = 1, lvl - 1 do
        total = total + (BOND_TABLE[i] or (BOND_TABLE[25] * 2^(i - 25)))
    end
    return total
end


local decodeBase64
do
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local lookup = {}
    for i = 1, #alphabet do lookup[alphabet:byte(i)] = i - 1 end

    decodeBase64 = function(text)
        if crypt and crypt.base64decode then
            local ok, res = pcall(crypt.base64decode, text)
            if ok and res then return res end
        end
        if base64_decode then
            local ok, res = pcall(base64_decode, text)
            if ok and res then return res end
        end
        local synCrypt = syn and syn.crypt and syn.crypt.base64 and syn.crypt.base64.decode
        if synCrypt then
            local ok, res = pcall(synCrypt, text)
            if ok and res then return res end
        end
        local out, buffer, bits = {}, 0, 0
        for i = 1, #text do
            local v = lookup[text:byte(i)]
            if v then
                buffer = buffer * 64 + v
                bits = bits + 6
                if bits >= 8 then
                    bits = bits - 8
                    local divisor = 2 ^ bits
                    out[#out + 1] = string.char(math.floor(buffer / divisor) % 256)
                    buffer = buffer % divisor
                end
            end
        end
        return table.concat(out)
    end
end

local ROUTE_ICON_B64 = {
    backpack = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVfUiUWHwqSbCkqORI3ZyhVVwJCizlqPCtFlEAbKw8ocCRgfEKojTolORU7hDMA/wCji0QuSB5IbCT//wAsRxadf0T//3////8AAACUPDw8lTyZdTBFZignORIvSBiMZyhQdDByViguRRlHXCY7WiMzVRtzVRoAVQBGSBYlNRdBkz2wmESKQzqlhzUcMgw7ZSUS+kslAAAAMHRSTlP6Jf/Q9QP/2f9aBP//nP8B/1SvAbL/AgEA/v/+/vv4/v3+1/7+/P4D/i///v7++/10plUkAAACdUlEQVR42s2WiZKiMBBAO8iosLg6O3swAwQTEnR1MP//d9sdbpegTtUer5TLfulOSKxA/EHg34sHFo7uf4Qhu0Pc2iMbUD8Pb2ZkwUZK3pBxLqVcbIJbGVmA0VoVaYNWaVEUSmstA+YSD/FPiREYvu9or/Gh4ld5OzGMn4uhhOF7M2pEf2VT4lPMoItpUKq5aH74glEOsRVIUSlW3vU3teL3qT4yoN8Li7JwrhoKamAPg/cyGFXmp43Dr9BkGpMC62sdipIsTYE0ukVqmoYaOTXmOWZTpUqrKK0MiQZT1BQ6VbXrEBeZorEzxscP0fYY6tNRMgybzGiWpxN+WtafBLz3AEzPHCu+DUHxdcD7yjXlrsXTA+LpYxn1cv3XxcdLfUIx+0Pi6yPi+73i+u10euw9WpEv1zTVGm1Yaj3nnOLFX9rZ7X+2LPcChjgzXjJaO9r0K6oHVwdfOEWujA0BOI7AbPTn4TtF/HOCNrIUPWVZkusWeQqihDxJkmh33lVVtTvXRFWUJCDdooZdVLXBUVRVUXTugJk+arE7U7zFQ+hU2VNVTYsHKwIkRFXhwbOX7QmZFUWS53kbmedC5ERijzOiDxjo5R1iBe1lcktMRoj8W5OcROkulYs+XZ0Z6CXWiHmxiytxUEetzA0OL/syaZC8Yd13iV5yDQ7VzODwsh7CKwctzxOujIwyHmlKi9wTff/wHic8LRi3mPGMFqwYgfdwXOFS5S5xkaFI2GVVc0SlYV7k2QwL5hQ7LpdLd7Tp6Dsp4h7gtwycSrDIzWYTBIG7VFnj13FB0G0fZzeBjqjtdhtvw+2NbefLS0hgG4f/fk9+L78ABto4Ha80LjkAAAAASUVORK5CYII=",
    basicboots = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVfXCApJAlvbBxzcRxYPQ9iXxmCfR///1WBfSCqqhWRiyT///9VVVWFgB3/qlUAAACJhSJ7eSCDfSF4dh5/fwCCex6WkiZMShNVVQJsahp/fy45OQNZVhR4dh7//wBKSRFraRtaWBaGgyFubRuZmTM5OQxZWBdkZwtqZxpqaRp3dB16eB55dyCHgh+/vz///3917CPyAAAAMHRSTlMeFYvgHFubA8wEqgEDzwMA/v7++wL6+1MFjgUJTa0BNnJt0MkFMTYOTbJzy7D7BAIVrH0qAAACdUlEQVR42u2WaXOjMAyGgVy9dm35CBAgIeQ+tvn//66yDAYCTdJ+6041zOTAj19Jli177Jvm/YI/B1TRUHnr9eSV/V3vokdBdbn+Z/I8Uw+6ukn3x+N4HGTBcb+4qThXaHP8iFiaFUXBncmieHkJUv++YiiEsMw/eqzFHTDxvcUizePsD+fT6TlNNtIaEIuzaHza4BaHP9VOcZDI8oILCwIhwpjmyxqcsPEUDWfVWgttRkgQRnZq5kBQW4rAtAZnLAaNClPeYygKlVwXzAGds6odECVFbZpvazBhIRjSjeUunUYRjKQoc6O5V4OK+RgHgOh3tS3ZBNkrGxjJT0A03QDzpAbf2Ul0FPGXGYcTQulq9eacsrkF1yzruloqWLCVLf5kwjPgjAW0XDXiOGG4GqSJRFYpKhbKxnvRzAVVDkbJTUpxCA7jZwyurFX/M1CQKxJs2o0gghn6aME5o5oUfWYVCbQmRexA1Q9WFS9bIEBuqBI8wBXIW5vFgfRtyXYODKCW7CtXImkIwGnBIreRQ0qA6KlxkxRD0I4GeY6HrRNgQ6+uIEuBWK04nQOD7GgOrItqgEl9SLglqcLiyySXfBDnRM2ilqI/MNkpSdFMIaYfTwtvRPtwnXSOx5SCKJNnK9SBIZ6XpjKj3nM1Fq3laoGYd6X6e4eaRyu4Wmc3RXir6bwxT/aCuP9HN7vVMxv1kIjx24oYu09116KAi1W+v9MfFds5RbslcDcGe+9+Y43K/VzVsjxsd9S/7nbkiC21tHKgVyE1NKUea+UHYUoZTsuv3gGGJy6zeEMhf+3ysAhMKb8n37l1XNpF+SCoHhD7vcv9R+AH98jLDbIyV0kAAAAASUVORK5CYII=",
    beekeepersboots = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAACWl5bn5+eYEQseSan19fUYPY+UjV2GeB4MJ3RwcHCqmid0DQl7bx7W1tbIW1e4Y2AlYeCZmpreIBrW1tYYPI5eXmB4j6ZtktqMjIy2AgKHh4f2CgATMXIdOaMYPIwTQ5tgAwJqDQiIEQzQrKkaX693d3lQc73eEgoAY2Mmdu4AAP8eSKkA//9LdcuJIBsvRBULAAAAMHRSTlMA/Pj8+wj4/v4QC/+Y/5///P4b2FqoUvz8oxJCDVkYbGkRZq/+BJ7/twIDAZMB/1EO3zSKAAABsklEQVR42u2VaWKCMBBGBwU10bKDioK71P3+t+uQBQJO7QHK84eS5M0XhqgAPT3/Cu4IOIJvatBpICVq3IHYdQcGLpElFsZxLEqHIedCrDRLI0yifGysGriuy5UIphl3zJXekl6ArLqJhOkYk0dVYBDiROsOJbETGubZegMTAZbv41Yr8myNNX+L7cQJMhWMP4tn4IaYCnHyhUy64njagHOpKTqp3Oq0itViqERRTtEW8emneiPNTTaiAU6aBwti3Wuzqyi+VK2x0bq6qRy41X1WQgTIIqqp3BBbZ0PnQrGOju8HoDnfAERd67gItqToGs+REheBTYuDtDavtBdss8gnppZKvFGJ6Nk2yyKPEFMZdwEGi/mc8mBHiiD7ymBjC8qy1H7lBVt4wLc3//XbwSAfKYQfPMtn5d2hgF/EeqsjG18GlX8Xk5To48GQiZDYMsw04XZZoxj5nu/7nsQXeFEGO5Wa50mS6L1W+XaBBVE8DCleMrKG5Rvho7ytNoLMSHGnExkrTlen0TcbOMkLMvHQ+V1lWOD0kJ8L+CiuiX8Chpyu+mqPzDoM93Vvenp6CH4AWg8g0QgaWggAAAAASUVORK5CYII=",
    beekeepersmask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUjHh5kY2UkISArKCfm5eolJCOgn6NWVVdXV1h+foC9vMGmpqWmpahYWFpCQT7OztVAPj6QkZPJyMxBPkDAv8M+PkA/QEE/P38/P0IAAP9GRT9mZpl/f4J/f/+Af4P//wAAAABGRkY5ODgsKipVVVZ2dniHh4mop6uWlZjo6Oy2tbnHxstpaGvV1dk4ODj////agrNVAAAAMHRSTlMfD+mi9V744qv7+QacWv0F/mys/f///wRQAbwFnAL/AQD+/vz+/v7+/vz+/v3+BALMERQcAAACzklEQVR42rWXiZajIBBFQUUSjSbpZfYFcckq/v/fTRVIQIPd6Tkz7yTpLFxfUVUgTcRfivxrkG4H1Db/EEi37v2Q/34YHOBZbJ5Qezp+fsyx2GTZpe+T0yk5JRvykONXCDQ9gy6XG/qkHnGk+/QAOmcjCEoSeh/uHCSbwxFJY2lAcN2L/E2Qih9pdzSW5xFMEny985w5FsfuCLLgjUySfEZOwWLdgUZSz/Jkg03yYVgCB8Hb1pDpnOxPm8VQlSjatl0by9TmxyQo6fueLoFU8OuMfNGo1qXfT2bpwM/iy/VqyW4kM0vC32QB/C5W7Zwc0VFU0BA4aLBtHWmqcs4w4MtLdtkHQSoIb68z9GBawSjb+O1DXE6JYRCzlqnHIbgNZrVAv6apfDUgDAIuk57TYDkIi6WsreSd8CIxI3cgwR/vx++eq6kYnYBUMecW9hyvwGlOHfhTCGbsdm5qIH7V4pybz/BLDMNz50iKlRljstqNOlqlWviu2xe3UHOxWrczrbspnOrFjcU5HFJdFgN2U+zXzNJSYyd5YKvjbELidqZXHQc2ogWpYHEUYSJvGa0DldGKohiLOXgNEEehsZWsSniisAdWs86hiigWbpepVpQqpfzOgXArr0kCTFXDV4VQ971qxzb6UYVAyQIgrevJmmhCjizoOAVDjpy4PWDBMRwqJ6H1GEvfMQCWYVDEoYx4ya13fhnfAT1uV1dBEAq5k34hsZbyk6ye3YZS8jAoZSl17U2vGZm9QF+rrqPgHJnfrJWjbEvAIwwCGbl+HZfJdK/kC/dHEsewvvQK0167Waqa1RuHB4YsQK+vgSQvgoTonRlNMaFzNd/eOueQEcU1LKf3giZ2Pb5weiTatLxtsLrrS1hV7x874zryklqWmGffcPmgCzehaLwVwCtuUuTxEzLAKMYY+cjRWvnnE6rUR87kSsEGSJR69KD7X/8L+AO5g4BOcMPB9wAAAABJRU5ErkJggg==",
    beltbag = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWpqqwnKiuam55YWFyZmZxaW1ydnJ+/v8PMzNFiX2FVVapVqlXMzNEAAADExMinqKpNSktVUlR/f3+1tbjU1Nh3dXf///+IiIqZmZmqqqpqa26lp6hoZmh/f7GIiIqlpqi1tbm8vcBVVVW1tbh5eXuZmpy/v7+8vMDMzMyOjpGdnqC6ur4oJii+vsFUVVdsbW/m8YqIAAAAMHRSTlNbHJUpPET/18j/AwOTAP77//8D+///AlYFBDjS/wX/r7H7B9ZWbQSPBXVyjSJWPECZRpsoAAABSklEQVR42u2VaXODIBBA8UrSAy+qgsSmHmlMtPr//10XrUZtMh5tP9U3CjMujwV1FoQXglZxFf+1aFcwxh6Z4L3C7YkQDmiaulemZbw3TIJbUXzfV5GqqugDQIOlSr6HEMpOpyyDBrq3hlhABPqLDtfBthvRtZ93222ow+Mb6AO23Yy7b+H7xJoWwd4QtrEnk+meHhrGGVMQGb7M8YToVSLFRyNcIgY/EeeslfyCeJkrJvApFol+TyQb4w7XABmIxIA/0THHsEwnhIGNyODlCBzTGsN06sS1CL/cMjFoxXH2t8TNa4vTYV/zIBrrZsYZ9Pc4g7IRecyBbogM6MW4gqO25uRSXmhFkQBnQAYOX3B+4N2JQyOvMk5CknKlLP3E87yjjKSqdLSlN3qKItFTSkURZmlaF9rFRwCUQ5jVbialjK7H3Cqu4p+InyBTthKNGqRwAAAAAElFTkSuQmCC",
    beltpocket = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUrJBtfDwpsbAxycnL/AAD///8/NiE6OkAA/wBHOyNgTy5fUC6Aa0D/f38AAABbTC1tWjVGOyU8OTxXRyp4YjpVVVVANR07Mhw8PDxWRyr//wBDOCFcTS1/fzxVVQBgTi4/PwA+NB1WSCpGOyNuNzcvJhc4LRpVVSpoVTJmZjOqqlVoVjRFOSJJPCNeUC8kHBQdybS1AAAAMHRSTlMYBQMDAQFs/wHBvtX/AgD+/f3/b/8DalAErgFuzwQD/gR7jLAEME4GrwUD0liG/zGy+DifAAABeElEQVR42u3W2XKDIBQGYEy6LwcsGrQGadxqNGnf/+0Kak2IjkLai1zkv3DGi2+Oy4EDgjODrvAS4Q0gahJ0Cm+d0jPIS8l16D+UHjGJR08qUjMno8PclBGvhMURrIl5GMQd5FB65s6rUdVCHyixCoWsgbfwRPAhRGAhhLzKCIJHYN29I4fwGM6GhPDawO00FCOQN/ATEtuK21/4ZQUTSRTMgOKzYAA7K4ij7ncEwGxh0MAYvu1gIXtGQccW5qpZ2yZf23ybGh1Whw3Ez/16rOzguofcFlZ/hbLLtZ5zDVq1gZkG30bjjsEA9tgc4lA1zjlw38NYa9ZZGPXQgUJYwMP26EC+noPdh1Epeqh28t0unIL3bcWE0iTJ5Wg7no8b7A7TPWeXdDgf42UQjUE9j4gveKVPKx/u5mEKy8FEDmC+Ik6BD6BvBrORisw1eNQpOLEwUrWhDo4riDFWFIxFKz3yftNkFbU9838HpI82/mkW732up8dLhT9AqsOZU2D96AAAAABJRU5ErkJggg==",
    blueclayplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEU3NzkwLzJBT4FAXMEAAAA4WLdCZs41NTYzSpA+UH5Qc9g8UYo+ZMwyOEs5SHVDW6hHY7QpKSkyTaI4ODgzNDM1NTVBVJA0NDUoKCgrKyw8XcFVVVUcGhwxPWIYGBc1NTUsLC4vLjBRduB/f38pLCz///8JCQ5ATnxAUH8kHh4cHBwfHyofHyMA//8mGSYiHiJaZfG7AAAAMHRSTlNYzv//AP7/+v7//v7//P3+/gf/BLTM/odTb/4DMPsSfYix/wIzASH//ylIGEEBFEIwrD57AAADE0lEQVR42p2Xi3ajIBCGu7sKJCgY7+baNM22e3//t9t/AI147el/jg0inwMzME6fgk/qafFptoOyD4IZdB92HrJsGcwO3m1dXS5V3T6bB//gOjZNU+VWBTeiZtMsWqzbsZzHD9mOIq/nwLqwhFKi1IkVY4nWQlm6aMZgFhyBxUroZNvqZfvyst0yUpJIRWw1BA9BjW4FiMba0WRQa13iSsy9AJqfPfBGXFxuHQOglFIKRdpg5lJqxrZMg2x8i5XlaEVSOkbKjVGJCyy9s4z5lx6YBc/gNDAYEsqMlmTSggJ38p2WwZji/PwAd0FBy2MspKFEOKRTKUqhHXj0QclYlEhQmynJr0IyAuUEGEVMqk3PnHR6xxKV5SZAxSIsUSqh3vum3t7e8LKyTAwXsZLzf0PQhMp4FHJBgEpLGXsRuTWfADFbE0Qns+NYG1xgkYlkcOiDMbNyu+3RaqnIoD5IcYw1LdKnHWMI9+ODQfC9AyPWe4FHzYC89MaS2EiToOrePA2x1qseSN5J2AeELVd4YI3DwaJVTsLgb+9YnTmZXCGj8MT51T+Pu8KsMrJuGa+ROsIwhMEfg5yDjBPLh0fHbAQOM73uhlnuFSb3c97ch0Y4G9fzKD1e+ck83e+dyb1V+JDgvB7n1YrH4YrEI1f18irynFgD4ZzRGoNzztUKJxCO1yF4w1xXQTUB3gGeZNoOSsO0bafICKnhaKqv449OjkgK0Y0VjhS2TV2Y6XiNNFV4x5CGQ4MMpdYcwFTEE161blU6NYAzjIbj2mh035zeVDMbSTO2iwum2HGh4vFT90HvgzApl7yqaOMcxs65/y2WA3Jqc+oAzJAHTnoBjGdBZMlyP8vJOTAIfvKFuQqAVXCfLlfoNE9CzjeXYDcNHo1JGw37NxUtKE34s5mS7Ird820MOq443+ZquR/cbIIH2M7VVDn1QvXYDI+zDqWlfG4E/oJ/UKpg15lPrFKntpbLj0tl541MdmVg1+TF83G10H3mvoqJmnO6tK4vqG6dujI3+0BpHazX1dMWTQXfKfvUfwEL+g9RzWEXG83N9QAAAABJRU5ErkJggg==",
    blueguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUZIFQeSacSFCojLFUNEyQTMHMQFSMZO44gPYMlQXslW9QfTbYAf38Af/8A//8RGB8UL20ZOIIAVaoZQZJVVVUAAAALDRAjV8gZQZYLEBMLFi0aRqojQ40ZPpIHCgsVJ00kO3QhTLMbNWsLDSUjUroAAH8AAP8ZPIseVsQHCg8FCxELGCsHBwoQFy8OJVUdUbauKTaPAAAAMHRSTlMlqyj+oFXeo+z/7swCAgFJl1oDWQMA/fz+/vr9/vw2/f77/Pv+AgFs+2yQFE5OLf0jNO+UAAACGUlEQVR42u2WWXObMBSFQWy246RJWwRa2Bcb7MT//9/1SoKAAWHXnb75+MHDSB/n6ErDleE/KOMJ3gtWv6vK0L2r+g+OyBBCCMVLQkgPWkIuJXhJ9FMDxrFNCxDWqLBPy2ALY1grgguwNBbAGK8K4lN7VNkBPK9zZJLVGCdd9SPX5RlA94YfllnnYHybw9RdAM/45hoxoT/mYKOHCkopARJ+Q3l6MLaJFkoSK6FYoKPyGOOkhFyFI4JJkjxPt6mrRudgo6aqGlCqkCQFbTnnmzQRYWG4mYJ270GpBdFysNkAwcMwjKIw4rmrwHYKtrTzsaRHGErmW3wrLeHt52lVP8FFJOt9wAislOCf51QukrTXYO0bEZcM55FSjwgxYVnIg9dMHR0xNxqli1iny6UsmbQUdZhFfQ8VKFk2QMdAiDGeKnDqaGzC74CKyYKRLmCZ4PF+9KDDwEvOz7KyLMdQcARXAC26VFUnCADJLtfIoFLuCMZuPAG/TFNl05Al41AeOgd9//Rh7gK9MihPQsgMrN/Eg3MwtSRYwumx55+OWj1rWWFJSbv0Ja/rWrHmIssysGzXmw46LKw3Y2FOm9vd6uvwMi1stkE+WgdfX+Xmwnp36ggcBci8oUtqHeu9tP0F693tutMDYF3d0Virn28ysmm+dCfdu7sj72XkU7fezPv7Vq5Y76E7AHI859HLw+kxcP+8BD7Bfwf/AGZYDwz66w4TAAAAAElFTkSuQmCC",
    blueportohive = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAAAUL6GSPDg7lTtRkjMRM8cbLG2joliZVS4qScqfmzZrahErR62YPEDIqF0aKWNqXDcRGWVja26hZEY7lUAdKl46R25XkUVZZIaFeiaWjS8AAP9iWxuVlJcAf3/DqDgpO4wwR6QA//+tjUKgbCOqqlXEsI///18NEy0pO5CxsRX/qlX//wBFNRJ/f39pa0LHAnRoAAAAMHRSTlMA/P7+/f34/Pz97w/y//5X/Rr+/v+b+v//XZQBTP8C+pOjAaIQA/8CTGIDAwEoAp+LGEG1AAACQUlEQVR42u2W2XabMBBABwMGhGxZxoAXGry2rpsm//93HS2AQGynDz19yD0JIT5cjdCMNAb44j/nJK9PliLsqT7j81SWLg1Shh+9zdGWFum0yUFGc9osl2xitif0nF7YqPcGfMBznIn1SZsnfUH9Hz2PTfbKmRnEr8D76DK+PnxgohTFq/V0fI8lD52LPpGOZuRp5K5rMviwIxaF/FtssmETE/LetiAmikCRb7fb/X4ryQRqnCxLO+HgNyGeafaSBMH2M44LXApD9GyqkQhZVwTBel2W5QHuWiy8XjaLsCZBxDUMCTlArMWD57k713V3O3FVeF6+WXSRY5ACHobYwWuJobLkXRjGVsS26NkRpU+mxE2fiBFJk44pcSWpxNvfiKvEEF8A9eLUep7n7alqcbUIAX4p8QccK7FJx26XW++IlhCPXdFIouuNiLeuaBXOQDpuuuKE2KlVF8fB/G9wRRL8SYygC/GOVeGgKGpZ1DSuyUBErDX8TWQaH9W6Fkd0CQG9gSBQ4zQlHpqFc7APjk/cuUm1/9ZrYzslandIqoqT6DMhzfRez/aSb4rviB6jLElL1G/Lz5Tax5s6RcQsbkfSJwrQpFEU+e1THPVsn8kHDvfe05inIkQk8f3Ij2roZUbr8A2hBhvHx3scv14DIlUtQ/u+HEN0Dsr5aHfkDm1aTYNoOaNcgVGnx4yin5OdnNHI77rCO01+d+AXKl6rkXBJ53hCFdlUpSBvzhyuM0TRBTkz4DAvHtid9/T1dfPf8AcsHDKGWxrGkAAAAABJRU5ErkJggg==",
    bomberguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUWFyJWVladnZ0WFxmVlZUSFBWenp7k5uW+wcAfISA+RD48QD9xcnJeYGB/f4DQ0NAAAADLzMsTFRbV1tYHCQn////k5eUmKCe1t7YUFBVHSEmVlpaVl5alp6e4uLjLy8s1Nzd/f393eXnMzMwGCQlVV1epqqrFxcVUVFRmZ2eGiIi2trYPEhIRExR5enqFhYUj0bjvAAAAMHRSTlMZIBlmYqeP/uf/Jf+w//9dAP39/f4B/v36Wfx2/PjKW/wC+wVR+6zTMPz8sI3QU1IqSdHFAAACH0lEQVR42u2W2XKjQAxF2fFktm6EGsLiMQ5mtfH//10a46XVQFKVqsyT71PKlWPpSi3JBvuijCf4faD1hvg2yTLHzwzjuyP+/XeTM9hl+Wrbr3etg8g8ECAmQd5GQRgoso31iOYW+FUAELdRGCrsybVXPXp3cCQh/pPQqKdjuQyeuaoR7SRKWPeCIlLQrICiPuT7A804cBW3978cwTUB8C6JAqpjYxIQmcPnkmiWEC7c5f3AUI2o5zpJQEt8hgmHioDIUpiTMfADBQ/AU1YoYKG2Ukk2i1Qw/NEJbpDiyOjeUqqdblFstKoiGzjMq7On4GFztfgALWbWM9CPE2px73NHA8eXPsvUz3fEYpSJ7Ys+j8iaWa56bZJYVPNBRlbrr0daJGDLIV0CPS2i1sUw6KA2l8CGtlKOyE9qMReVsbhzKg0kFsNAWkyXltX47NQHDtRiGOy57yxvOXWDzC1GGXCL4eJ6TAWxqHUxBs9YAc+wanEcqYdFHVTrqlkMghbgLJ/m8iZ31C7+DjSLW/Myi3MQmcWV8lCLO2lx7XYgM/sHmFOLcviHW2kWjo4zhRy72GldhLpZBQvW1DeQt+pSlcPv1+xucR7RuOUKdIjlSMnJwNX7iPIYwNXijqwN17I+OqzyKy+tlNcje1g8uUf7s4uMrBfjht30vyZEMuXlv4riQ9Bi523dp85gMFvetvL//FxBtLD4AojP33JP8FO9AwtW1P41A8zLAAAAAElFTkSuQmCC",
    braveguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVoaGirq6udnZ05OTlLS0uJiYm1tbXV1dXIyMgAAACGhobMzMzS0tKVlZX///+2trbMzMzLy8vh4eF/f3+lpaV2dnZ9fX1paWkZGRl5eXliYmJHR0eFhYU5OTlUVFRdXV2Hh4cpKSknJyeZmZlVVVVFRUVVVVVmZmZ6enqzs7Ozs7NsbGxsbGyTk5OTk5OqqqqkpwCwAAAAMHRSTlOZEZgWG2TVXNsA/P7+/QH9BVz+Av6y8o0RzHZHVilSbNcUKwUDJzIFVVy0OUxbdQOsKVdXAAAB6ElEQVR42u3W2VKDMBQGYFrXnCxoQwiUbki1i9v7v51JpDVr0c5443juyvSbH8IhJxk6s7J/+PvwfcNHXdfdRavrNnzD1+sQsrMSOUPs8mW7fd3t7mN1c797nal6fq5syHXaQ1bSIseETNwyvwnOqSqoMyvRqKVYUaoYjpRW0Jc0f+8TK6VAham0EBKbATRWoqwBaJFg2GEg7MVZUSihiCg/DaBsviBDUl8qSEThvLAZUGG9Do4WBkbWxU3TtUR2YgIWAaOidRIbc9GDBAcO6NTtnAegGvrLGTioH2Mwx0OJKpB5EL4FYaGey2ly8yLzwVuV3tfBkAAN3Q6IwOYYeIDTyPsIb1VUzP8e47BIBzqQnoa0treIHjblMFTdxgM4r4ehiO05lYhAUniBLAHBh7nTbfNEYnka0mV8e5SmdU4lPiUhnISyTcCwA9Ruo+//GMiiUHdASdNQXCTgXPaJJLoJq++JpWbHIhM0uVWJyu6aYFq95BNXHuE0mGRfcD1i6O1zL/UTad2ygcE6mo2vyYT4zyjR+/Aof5q97fsZclhV1W18AJoxiR6vxnusgg+J08isTh0e5rP9LR4LPcVoGQlMQKYT2q3afRditZLVT44rxpo7bKofnnO4tuqh2/V5ByT+fwj8y/ADYWKFxriXkAkAAAAASUVORK5CYII=",
    bubblemask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVok6UgUWaLrsYuaZhNYW9bd4uDpLoGMy52rcQVJCQPa2xoam2d2OljlaIZLC4sT1QeSVL///9JZnIA//+p7vMdOEgmOkQKJlgfPEhYe4pep6dnpOAfNzoJRD1jf7FOe4alpd0AAP9Ebnh+wNAbSD8URD0/f788gIF/fwBfkZ15uMJ///+qqqqBtsYAAABzl6wYcWV1AAAAMHRSTlP8+f7++vr++vofCAP6rVZYnAGuAQRbmRfZqAMEmfwFYgQBaf8cmQT8Anu1AgOeAP7pt4HTAAADTUlEQVR42rWX13bbMAyGQUmUSIq2LO/YcdIm3YN8/7crwKVh6pykp8WFNchPPwCCw2D+0uCfgEpNG5WS8W5vjFwCv8zRdtJTmt2SolxPP2pkh28UfUGuWHPMKmLbtmIN60Y6K82aM5LtTtZ42zwadQe2RoGGBu2IrdQu5Vrbhnqbq3kRjNrWoziTq5XWrhFbL+T1mVWcMXZmB2zcxKZ7UELgbht8eGSVN7yy48F01MZgPYojgmvmuab5bBKGZjn+HKmV6d9mf58cGTD07jjiOPfCSKKgzGRVBkFRsIiQxQ9grGSbYTAT6OJnQgMbsDGMSSf0FIckZRXJ2w20jXLgLaLWcTe2yVRO57wJcjCYQ4uCefuUnx3HQc6iJbTiVQBPGRAnQ+JstChaOfIrkxnwZNYOHHMetQ7FEdFVbna0BiOMbtbOPFrXgMmpkBNdHI9pjBUvCg/Wg+G95QWgrwDD5JmBWltyDPsWZAEkd2lMNqf8RL5Iri138XkuwRQnt1qapwyIvkuXGcqHFWST7NhiNV52Jlk9VCUZhzJnWKqbg5yDO3PY4Di5HiIPEnrOgEcWQCEWOQTbdu7qIQouG/a4i1G16Gk5KlORjNIKMU1YQHIE4tLIU70UGYtVROM5AVOl2Tw5Ardj0DjFZdBRCHXZcZSVZwHmbO1fQ2X6fd/eF8CW+3qbgyE3qGh6NVc8qad+yyGC1ibMQhFA+2D6jKutU3RO1ZYxHjhgJURwNVqR82DNEwklK20dwQ8ZUJmuiksU6bDgbUnf8AXwkAWlOUCqAD4By5CfJVdlmsEWqzaAtNeVdeGczYMKtzpXAeQoCpbgP0G3YSDzrtJDWOCABLkvNFIEXzgIXvNgWlIprrhA8pLHBeSBNut78OcAhiULYg3SBX+22cUK3dimLgCCZMlNIeJbLncqB34zkidQQNhkkIzg+CgziXFnukGxdImlYD1JldounuXMi40gcULjaDAr/OemR7TpFvDLrGjxjSBY0gUPKvNxGcSmFQyuOguuPs/OhLMdmY5mPqkQOVzv8EmNpuLSQbdb4RCIV+2ExCveo9wbTsgtoWSE/8Dr9+f50XVBsb3O3/SXN57JL/u+9yH1+/3lqt55mFdKqf/wL+AP/hNLLir1cGMAAAAASUVORK5CYII=",
    bubblewand = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAABGb3VkkpwmNtGenwAiM7RQdowJEW6Irc9xkMtmaAIfLKUaJpU4VZodKKkVFfODrLYsXmCSlAEmNMlJcHZ4eHhxcf9Ugn2fyNz29gAUH3YAZf////8AVaoA//9tbRJbdsOlpQBLeHtgnp5hiow1Zxo2XGk7ZG0uQPJhYQFLdJS///8wO3EmM8VVVapcgH7Qv5iiAAAAMHRSTlMA/vn09/T8F/7+E6Je/QwC/yGnq20CAv//AkwCAQMB7/4EngSkHmH//024BNh9A43/fvgfAAAB5klEQVR42sXW3U7jMBAF4LFdOz+22ySEBtqybWmBBXaX9387zjipugWJ2OGCEQJuPp3M9ARB9INzfXh9PVynu3/9jzrVbYiOx+MbglNlK8PUdEja7+SkpE39K4XewwiDby0lPW7JYSZ8tUkHsl4WPHmeh0XjZkFW613O6gYQqRS1ZkYrrT2z/AZwtyvkI8VcKATyXSqGeORd8RL5pHBCGGMkXNjV1G1bjz8paS94nhBbVVWeFwUf+X4EzslpMUyAVX9aiU1HVzzDXvaRL2NNOMOwKHAPJVc/EmJRDh4iv4ZLssqLixlg+3UP5oBafJAm4qoojtIfIoW3D+OFXZJW3ABhzjfSDtcem7uFU5AdXsfuFKgzrBBTVkiPt7HDx2FE5zVgFtHWu0yxxEW6ThrjtbIRTxoOZFmCYjycQuI67mV2q6tgNZRzTulVrBxilbK83Bw8Xv63NGUsl7GRfJB1NsirBHlRRAoymyR/W6J0mX1H/kUTIqtwUcUNOTUpE1d1KrK2n/8EslxMkyrqHfssUb/VNBnqN2HWoUQl/3qb+LGw/LOdNSXtk2Ot385YlkmqLMstXJAPaYHPs2FSM4nOMulCCDrJ52TZDDLxtFitmbhlL5vUFvS9aZpJ/0TvaeqU+9uSfmjeATnxGN2hxoSoAAAAAElFTkSuQmCC",
    buckoguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVUZmmcnWYQKV0iS58LHlJnZigRKF8xTHIIDywfSaQRK2MkW8oYOogTOIsAef94hnQA//8AZWUAVaoeQo+QhyRTbIwMGjYXO4hVVapwhIwAAKp/f/+EfR/BpEH///8AAAAmWMooVbK0ozATOIoaSKgUNHkMKm+qmy8YQpkAAP+xpk0LFzQAAH8iTK44WJARK27qFIh3AAAAMHRSTlP7/lvpJv2f9SOo2PJe4QL+AQIDZf//RKcD+AMC//8BAP78//z5+fv/+QH/FgL1/dGxmPLMAAACX0lEQVR42u2W2XLjIBREETBol5fEdjIbwiBZ1ub//7u5oM1yJMfWU6om/eAHV51q6L4CEF8o9A1+BbBcBpbLHMuIc1o8C5Zb/Yvxk+DZUCxkztNLxeySSkIf3qOxcjSVyqzCPHoIbCnM0lBKWQnM1w84dpSXJsApJYTb/jkHbt/KNsM989I0kbBGIeLY5evznR7LbjV7ZjYmMwVQLGJS/P1k5Bhk7jAwSxKZCe2lNQQ6A+5ZmnjMgwVKVVUtFccKX83bBFjgS+qBl15gD4GgiHtfh8ZSHQcByr/iREgpLbScgt6AG8ieaUp7iWsKuExeQJ4HP8ml0KV0II0A85IkI20aIz8ltRK9bxliUybqy8bMBtV1LYQYba/hkkbSo+M9gh1q1LIDp1Rn13CbaxDbNvqh1dJo16MklL2ykPKRo5vVDdcJrXa16Aw7ZZr7OdRRcocIG1nW6RX0W3OvlrVC433CCiaGPKg0mR9BJ6Njbo1BkEsnBiAwnrlBj380fgu6wdTkrDluVns8GfQjqO2mZnXLqVuR3hOUr+qBFFV/SN3OatSSVkfm1q4HKwhU4Zkh33DHFcRedREdrbYQIXQR6kDnvg4I+gXIJlzYqoUMKHSBSrH7l04ghlpMk77fc+e7t9WLb8LNYa2mSd+PCZwDhw/cDQgRNbXk0AeAvusSotShaCd73vENwhUEQUS59V4rKL2g+p45f3qxRoaEcC1kE/zxWpw/5eAkgHDr94aDk3nDJ/ymjkdTi6gFwQveAAFMS7Dg8XCGWgL+a4FjZOZ+yXNlPVyET75zyu9H4P8B/gMGVWhVRLND0QAAAABJRU5ErkJggg==",
    candyplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEXc4fPQpNu6odAwLjErKywzMzO5zNdfUWMtLS7VZVCfkKllZWXa01RXZpqZdZxIO0pJedQ1N0fgk57///9P1G3mx6RhgdndhVw7RVlzkodw0IqwXVb/AP/FwzpjEmNcrnMkJEgAAP8AVQA+WI07vllIJCRISCS6TD6/gGiw07/hf5kAAADGitA2NjfstvTj+f7Aj5SDAAAAMHRSTlP+/v7yE57//WT//gL//v77//z/Af/////9/v//Af8E/wcBA/7/Bwf/////AP/6/v8CtmSyAAADrklEQVR42p2XiXabOhCGtbFYFDA4dpykaW+Xu2KZ93+7/qORhExxm9zJOebE0aeR/lmYiOl/mvjtCpPsDSAWHYhoDocm+zr/5SewWW9d13XhrTa/9Wh4KRMumS4KMzV3QDBaY42On9oNfV/BevrGmTseC7/a9ZW11dBXbWetklJeYdJ2lV7IHDSEuaq1SpDReiGui4lrRiawmRiTIhqcZMbsQkbwAE5XncyYy41J/EkKNWB3L5BYjqmDt+uaCaTfrx3IpclAcMHXZdv8feXp7Fwx/bWAhev9lnc56dWS+5bAzCMc8vXvc+NuNyoG/0ggbtix8lsepb/8Dtbtzzcea+fOJ8Vx3pLTh5XAHcTRKRzNhLzan/YqBEvexC8GaCTupcrC8RWSum8nIq8bJv59fn4usd1u9/fLS+9cHT1+wg2Hdg/whHXH4zFcdhxH/3yAPeMw8r/d2CHPU8r9GcA9gccPMB+WR5yMSEHgQ+n3EJ2GNBE0DLZtq5j7cLzSlR4fE/j9IZwCuVpnSY47Dm17UtcFhMMAXsunz58ta9a5m+rgwkDmEPj6+ho8QsOR5SlliFI3rMuKSJ8Bx3BScvnPKFN0OKQKR9W39Qiyt7x/rN0QQymV4lRQci4rCkdeVlPRc1n5/UWIvpjxI1IyCDFbzRmXwAYFWakSq3AieqiQ2lg8z4KfW6BBvlZKljOB2GAW/lpKlaXIzcdjDfZWsssLulUgPRrhsrTnLHMS6ACWs1BeP49KLg+VjJrV9DEHGwI7f0iZSEKzIkOHbSlXP636KtSRMuizoIlVXmS4REdcg729eDEiqYKWIsZGbIDGtw8sToqyvMRyTGZSZwusnW5lHovkNVpZPrm1ONzLERBcBuScNFlQXMLq2DkykM7qVMycOVMzhYPKUa9fOtgHZelPyXrKVa+DrBbgxmvuMGn9NJMv6eUUsSpSS1YuOcxBgy7pLEVOqRh+tZQUvilji1u/kWt68xDJXZirQi5BLM8AP269yuld57MlNvB55gDyHtbdAydcgg47Uz3K25JCaVS6r6cvm2C9kKSj4qJis2cd+8bGuEK9R4k55jcFD590y46mleLegNQYhLgKdZHyG9JSCDNNNyYrkA5DhAxcUNaPOM5wfm9PVnRN9PVOLbJyGVLsza88GiJ1X3X2IuNLlYoim+PuDoE0+GldsbmhGnQuyy/n1UK7OAOGydG8dUKui8DwBPrW0dowi4m1fu9MbpISB8zX5l3D/MYI/57/Au7YD9N6YPT00PT3AAAAAElFTkSuQmCC",
    canister = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVhmV+PkpJfiaGdaGeHh4evwa9hZWc9eJo8ijqLmp9QVFdsa0RBfKGXPUB2TDZBkz2Cf4JXc4iKQj0nKyslXmGOlHq3t7d5NjJ+h4k9b4t7hYmCgn/Mr7IAAFU/k0A+gKZ3fIJ/v7+Afn6qqv+8vsCq//8AAACztbSbqK2SOzs7lTunrLB/f3/////FtLJHeZign1jvAAAAMHRSTlP+mf7+Z/9N///wH//8////YKr/FBv/BP+EoHFg/wP//2IEXwP/AwD9/P///QIC/f4N3k4JAAAByUlEQVR42uWXa3eCIBiAQR0Nqm3eqrX7TdQX6v//u0GiGVBa24eds+eERzg8vhzkRULFhSB/sxCZKkKXbKwoxNtC9hukXDA2KArjpOpHet3lBxuKmJH1Cu+g2LB+HYyYrTAtS2gwN1wV9QxySmSU6/42WuawOiGS8jgApBDnic24ofxjIvhF1c4vEcvLxDbmZSKMnBxKaaCg1NT5QERa7voHwbajqesnkIIdE9N4p0y2LgGN00Iez44s1uLMMJk08YJZEA+l1X2wVf1bXvZiMSj2PI0Z6WnxKWVx4Mc7VNnwJRnu5n8P51y/XYqZXDQdPa9jn8Zgw4FYEUXBIgMGbgPQ3WDTKTKiLDA/C6yD/SvxyoVvPByKn5wilzz0QK2I6NrhdnqzrGyW4cYSFc+14ralRtObJOk583lVJZUjXiNUH6LF0BJDS7xSYl27YuXiiPUoce4O9T+Io2Z17hE9TKdJ0i21pF051pKjKHeWap6PWKtufqgWNzceH8flI/T2rHazs0TwenBQ0VV96Yu789O4/PeIYAXrxnYwcPiNPSfyzsGgqE+m0fvDg97e7zqiPoS03wiMo+YciX52JhcLMYqjn7mf/wsY5hvWAZn/anYlHwAAAABJRU5ErkJggg==",
    clippers = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVYVwCbmABZWVmYlZefnpgtLRelogCNi4xubAOppgCgnZ7k4ABxcHGdmwDAvQLZzwDFwgB2dACAfoDAvADMzMwoQF54f4t7g4OBfX2fnFH/AAD/qgD/v/8AAACppqj//wDLyADZ1gB/fgC2s7OqqgD///+sqQB9fH2ZmZm5tgC5tQG5tgWqqqq4tQCqqADLxwBvE6lMAAAAMHRSTlMkYx+f5RQVY1DhJP5UlvoFpo13ogX+/h1HsgEDBAD4Afn8A/sDAbMHBa7W9gORi84ChUgKAAACYUlEQVR42s3W6XaiMBQA4ABJZFW7zD43C2sBgfd/u7kJWukcy/ar6mnRw+fd0jQEdj7I44/TvRDkiefpHjhqyTdBCXw4d46/I1UeKa3UMAzORuiop6cgaI96+LRPj2Gp7C9fnTHvDZCpwQKuezhtgUSXCCRm7N8zlXIJSkzRgRyvEs0mnwJfgCkkithIwfBeooS6gz9LEZuxN0TVtyjoItVNO/WwRtXYW8g1Y1Nep4NAd5PhkAeZEpXIPM9TR48ZGxcl4Le6ZuM3PYS5beZkmr8l9LrENvmBfiGfRzxBrWvH4QSOY8Yn4wjk0siaz0UsAx0dm1Il4xAc68yVH0TO7JIjjlMqZTM2yyCwzlzqjsm5Pyuz7JoWp2krbtKbi87z40hzLklzVETCGC+9uheQ6fwOkIOFwHuFlRpoXHd3C5A3um11T4Bgi6J6xZ5zAZdS+qtV+CxNU62Ty9BFKETWtqohgBL7+dHNQJEJQdue4f29KtV51dZRAPMEFRnFSfJUQmLqSxdhBfBTZN+/Cc+1t+PLJ/9vWuRRuMrDNDEim5QlF1MtIKToDHW3bMivEAvDvI3wLxxMOOq62+AFQpOjx+CwCRbW0Rg7G2+BuNAwTRxCUUFM10PjMhOugDeTKl0JQ6gwHDPztzDz1v1/fINQiGe7bq4wXgVDdKa627cgfH83B3EO1DPgDsWPFRErCL34muYNUrYmVTeuzBAmMDusOjww9qGgERbbzzkm1XAPfAUPx19thxfwPNgT0cIC9tToHXBN7In4fMAf22EB8XxvPj92MnffQRfYzhPy7qP1F4T/ANGCVijIvN1xAAAAAElFTkSuQmCC",
    cobaltguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUSIaJjYmKgoaWeptmqqrGLjJMhISEIHspZZa1ebMpycnKtq644Rqa6w+IAAP93h9DQ0+y9wL0PHHjBvrsdH2R6fJeQl8fQ0NBrbJJncbIA//9jYxt9greAfXyHhH/Cv8EnNYwzTMZsZ2x/f/+BgX2qqv//AAD//38AAADHxsf///+8vLvV1NPDwrwEF7LQ1u4Ptv5AAAAAMHRSTlP4JJ/w2WQV/fb7TBD6/AHz//n77x1anB0fsAEP8V1j+G3/ogI3AwECAPoB9f76/P1zLNzkAAAChklEQVR42uWW6W6jQBCE54ThxmfsnHsvMwzw/m+31WC8UYJtyI/VSunEkWLpc1XXdJth1QeLfSbQneqfKSZ3SXJHr6Ryi0BtbW1RXlXzyLPVZ5CE1iJeogiRJ0VkDU0dLEq14orskqxYlGpScUF2Z5KvjsNVwUh6atQtOce49gOpbpFvB0ATaV+kt4jo93zQVTEiklZu0GiAvmcrIiLlx4j4FbfvZtUN4a6GE10y5BARK7sCmaHRixFNbAeniKxdNSs6l0vkhbVCRE2NH+8vNXppHxERuKZBRDjRvH8vd7dBigjhNk1tyxqNfs/z/B7vb28r9vO3gWbjz6N72PFJ0P16E27TF5ZUbINg++UYST3avvKdA83n2vect9IwxkIWycMY1at91EJzHgSvNWn+MHwvtpNR27aMyWQKVNZvhHiKOSoYw7W2F+1kyljLot1kODRsqKZWSggdx8C/1X4kGTQjwacWuaoCrTzK4rdRhOOPtRlQX0pIhlJPKdL3ONfiJIIPKL1VRmUd/d+VEQKaBoE5UhWQ7U1jRZRZR1n/SQiIsbPXd8eRkONYbOypMrNmETSHgNap3A25TpwjGQ64tidRhMKMhNs+oHWxvwiOrrWgjAgksiTf3eM6ksHNpxVQBZWvbdiyVGadR0AmLYY9uwL2zcoyw8yAZAUa9Z00Rt+7W89HBKURZRuGIdktpCw7qdSMB2vi9GPPEcpYmqbGSBlv3S2QV/yY/gVRxijRD/J1MMc6Ry0ZpWIp3Io4mGGVdqaAV9JKIymxdzMvDwnS6depKI47/jD/1nGouIyMMfu95ouuKw9oUu31D+rL8WX3nKEt99MtvSAhfMfdh25W+ae/r/7/4B8XWrgGWJ3z3QAAAABJRU5ErkJggg==",
    coconutbelt = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAADuDiNHNSePcWGdm5vi4+NuX1QDDZ1eRzg4Kh0acOj4Cwsum97pXWH///8AA/sDHc50b2xtZVYDFZOkKSgBCHBgHBUzKhoAIKvRJy+qs7RQSDhkc2kCD2UIGpUAFssQYBQLT2sziq8dm8p7g4RBqdj/AHHkN0PSqq87aXQZXeUgoepRSjO/Oz+wJyCkRDOF+ja4AAAAMHRSTlMA+vz7+v36+vjx/QLu/QEB7wefX1sZEZoDriRdX1iwqxEa+Gv6/wL///4EmxYS7vxR9KDTAAABsElEQVR42u2U2VbCMBRFb5P0ktqRzsggAirO//93niTFtooLfXV1Q+lws5uTNIVoYmLiP3Ef1peazL9fqqnEbxiGF7SQ6lGTeyo9b1G6k0HldJgklGC3PJOTyPOMa+MmY7U7zaWUVJce0euwvl14nnPN5ZclmnE+NwHhXQP9/u4ajMaTvOTSO4HMsiOv7dB8Q1cdWG36lC4l92Yc48xB8+TaeX5sa1+nfqm1On56fPLQJ/pTVjy+oVb2c/dExU1BJFh194xjzdyrREo5E5EWg6fRUpEB4i7NQ6y1ZpK4EQIzG09ZV72Vt8OUKVXZLLshlI4P8FhooXxlbqQh6l5cmQc6oKI1xNUBJRXHSjvRbMisdQ5LGvXcclojK0qspDwIoNnkNZ/dLrqLzBfbfr+nUVikLbKCDoowKbkRRSB9nwXEKLr6BPbzF7EiTOwqh7aiphe14KtZz6b4njV1q39rjl2XzAF2j71YVF3DMW2LRWJenq3rUgTBUNxYrf3xlXOvKszAqkLsrEjGStvL/waNFUETZbPZupuGX9EgadAQPW/o7Mh+Q/VHKzkt5YmJif/KB5nvGRmb/A7wAAAAAElFTkSuQmCC",
    coconutcanister = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAACMaVbu7+90W0liSzgXDwqhoaFMNSk5kTlQllGLODhmYGNsGRX7+/uesdOJZVQGCG6chXSUO0HTqKigzKe3yeNsbBihp6UoHRQ3LBsLKdFaWVdEljyhXV13VEaPRjzXXHM7UjA7lEFlTTyJbGLUxL5/f79edoq/v7+grK+r7u7/AAD/qqoAALQAEI4NGq5gFq3NAAAAMHRSTlMA/f79/vz7+/79/BATAf2lDPz++Pj6Clheid1b/gSu/938/KJw/wRQBKcEAQMDRIRJsvgLAAACgElEQVR42u2W65KiMBCFEzp0QATEG46M4+p4dy7v/3bbSQcBxdv82605BRam8tXpdDcJQvzq31A0/gE0iz74IY6iJ7Cxpbqnv4+GGBO0St+kTEkr4j8eQk1oqawpLXjwvsxsAAtp3/dBpt1HMAoRaLqviFO+e0prS77DGafaU3rP793FR7IRK+3Mb5Jd8W7WZqa6NUqZgebHNzHbHeJdGxeTn5kEPmBmIXNnZXavlz0WAM6Jf5XWUJUFojwXefsCCYOqGHalugIzj9RGjgHYkn21Rs8Dv+ZpQK/ZC1EuPA8VqJI0DnYe+JXlwAyYXFTKzRCqypLm2WlEVpZ2ZNBoz30LmDGIJxDQY8tK3yMzIh0ILlQ7byDPskOW8dFSvbg3tWB2Al1uJWJWe02As/On7Nse3RyUUmWwrpr1ol6Cn+LLgZpBxbGCbArUheMXh7pWpaWsqlm1UVuo04Qzz6ByLKfILZrsEM7BXgMsF1o2Edghk2J2lGUHNMEaVvrSmrmCiFzG2amOU84OUHbo/dMK2FnVKaNRkiT7quU+j98VSDlCPBkirr2aEDEpmm/GiOth34irSgjEqLZrmRagKEaoroHrAdpNoHexwRZJggnCJTgwzao7Hbrmadt2I0wcdXA4HIZhqAggGbuOTONZ286/3W4L2mS8ESNhQHqF+VzOZb/TN/TqxlGgAcNFYEXsMgRFRL/f7zDY5njYbDZCTHxE40QKgmUQwpwguuzOGrWBZcATHIbBa+BEjtznoujePrF2IsdwScQytCKQukc/dKoORcCMbV1Nh8fkkVOOCrMXhYDFYkG7MVEvhB2f+A6YvBiJyRMfAfHh7Aj7ibriV/+3/gJtsiIyPi795gAAAABJRU5ErkJggg==",
    coconutclogs = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAABfSDdLOClzWkqKaVTZ4esfGRSgnai0yNyttMhmGhVvXyloWlZyVkM1JRtINigAAnABEuiuCR34AAZJNilbRjeeXVn//wA6Kx8FEZ9EV9+bAhL///8AD/+XAxAIItlvU0GaAw2RhHoaDXk7MkoqVao0SupkSzmBYEqNa1Syq6vEDSDQLEjORVvLxL7IzdFC7HBaAAAAMHRSTlMA+/v+/P76/P76DxQSnliXC/HxAmlUDQGQ4ficAQJlnV0j/2PlBvybd7EU7f//7Kd/E3BiAAACaUlEQVR42u2V2XbjIAyGJcDGJrbjOEuTJs0kaaf78v5vVwmBt7QXczvH/zl1auCDX0JggEmTJnVa/t5VzFgOwMkrvxf8XK9PBcDsF2ozfD/A2pC0yJgTxAkH8rPNHK8YWm5ghcQpERK6+XlR91yiQqS/8qV84pYV8nD0HDUbU/J0Iz2/sC3ieKzW6MjqnN6iWSM6jTAeEkSD+MfR3PMwj4Qq3SNQYcgBercelOlUjNGPQDUCtzbJsjzPbWYDuT7MCOTYlLZJ1CUdgRXkoizRtDqDAF/az6F0EjptrrdjkKO3Xn5FjSvIE6v8kjqzUboachuQ/FFaJRzUn182Sy6K32NWNe3puAJKE6X9nmmKh2yz75AZ6cXBPhZQdhtF+43qwonIMiIxFE1UOeDWPY7dShaBSevBAfkaKw0KzQFqI3GgCalvLC9pQlVwnydXXaUbnaYaUxVq4FO4R/jwZpOWDL5eyaMci1IRmKap1IbJhFvcv1kJMxSiDmR7KKhAaDUVQC11crsAOL5TNSW8m0JysLQ5JWwiSHlMuwK3nvtzA66h/OTWSA16T0jeymCVjp1SvlHEOSXu7x0t+ZYTqEPZ0xhFD3zqTrMH5bTSwwpXw/Kw/yCQGtH3cTD0T5vWAh6YjOfnAW4XFGDNQZwbf1ykeLgyaE3sleu9IALvdszdyX24f2errTgiBf1Lbd72wW63q4WD8/LcgGn6XKqqNjdk6wDVnNu3K/Amuyv42DSNwg5UowPpepXbRx3s9/tj50dVV5dj3FSo6/p6ysqHn26h57O7kp37+Xsh34yqklv6n7407jqkSZP+d30D3WAczIbIcEAAAAAASUVORK5CYII=",
    compressor = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVlZ2MeKSofIyoZHyVXNDdnZmgVHiU5VEVeXl8mTjJWj1FaWlyWZmX///82O0MAXV1+foA9lkFyUDlePEEAAGo0OEJGQj5GkD6RQT9JJCN9gouAfYAAAP83jTYA//9KKSWAgIH/AAAAAACJiYsXIytVVFY8lTyTOj1MTE6QREVJmEwUGySWPUCQkZUpJy9oaGmeYnizAAAAMHRSTlPy8hti/Kig/g/7/1r/Af4C8v///wKlnf//Sv//Af8Bgt0BAP38/v//+v///v/+/f7ha9E6AAADDklEQVR42tWW2XLrIAyGBd7txHGW7me1IcHx9v5vdyTAa+O0cy460z+TGGf4ECAhAfl/Cr4zGG639NiG1Lb/bT9rkfOxxceXO+A2Dz0UAP6EeUItoJfkA3CbJ0VTNE2B36bwdIvUFMlyuguL3LNdTfdRGV+QSxCKFSVfDWbhfTD8swLCB2v0OpBane0vpfkDHu+6g3tSoaRU0oLKSj7yu+54NPakshYz+y7Bu2vxRS1AkAP5wu+ALpiJqgEcpqrc3/nf2yDPfVeHZoeybsk6KwCX8RWLu9xP5SzOpn6UrPJzfhMMc19BtuZHqYSTr05VwppFBFtndXMepII1UCG446fdHPxlTv0DtLfBBlolWb8VU4uOz0ipUK+6I51mfYobI8VSyXwHhftzGkDHF71algaBohAFeIVON9Cx7dCB+aNFzsSoyor6tMPrpINgDtnUFn1xS5WYA4P8Yaq+YAEpigIdOhGLUEHqukeXtW3LWly/brU0Z4c2CHTECAbx1SiOY/qh1oaE47iubm0OrgvHlkCuQZ47lYDr03W/P6Oerv0QUJdLbWAJBtfzTD/P+6fDZa7n8lK6uJHcrhFBMQPRGtrGqV7qsq5rRIxpbCFYsTEAFqCGz+f4cKl7Y7UVWfTzHz3IGYsW4PkeuBtCjokVsJ6DJbQEngbQF9He7OmofTzZHByBVqtBZ1gjOTKKrwvwfJjuqt6iS3lsq/fgUnB4pr284HaWGi4JFDb19KCgaIsw6iDWUQcBPssSys3o/Wf0RiWmp4P8wZhgM0URc1HgasHRPMUUREciJqr+UAh9jhirJsJIZybG/XnO4fxBBUFqrWGPNO1Pw+JsOctklVC6V7LTFUCncjz72MCEEKR6zJQ5mGIWIF4xTKF6g26oc2/S1JKue194RpAr6qYw92eQmbyc9eVgYwqPl4fDpWcKanVF8+7O0cAA3rIIfSXUBQe8JAGTGwsze3UTpDIO+h7l5GGCoi48oWuWl/RVcgW0V7fJNauXg+PRMpxJufrUtROHc2wW/7qLbsjx803v5P8AUVd5IijV/WQAAAAASUVORK5CYII=",
    crimsonguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAADOysi5trWqDSbapqv9/f1kZGPKBCKmoJ7Owryek5LMXm5xcG6qVWGrM0auqKnZdIbavMO8wL29xMH/f3+rdnWTc3XFN0v/q6tgJiVHQjeUFSigeoH/AADlOXLdTmv/f7/YkJvMoKD8tcbKy8o3S0R/AAB7Chx8Okl/gYG/AD+2Hz+5coC6vMC9wLv/f56cyX+EAAAAMHRSTlMA++779gEZ/qH4ZPxN+PsO/Pfu9wIXVv8EWxedlQEEWwRlrFhZJQKQZGwEWPz8WloaqKfSAAACH0lEQVR42u2W547qMBCFY3sycUtCYCnb6+3t/d/uzowD7CYE8P1xpZX2SCAj5cuZZpui+NC7ELassv1ffmXZvvz23r94zAQLq0T2itY5nNcspTGTI0MBfRZH8omzWOYliFpACjSzNlYwHXMD/aadBJrLpUCVzu6+TVzMbX1MLcwMFCXQX8yNwfLErEmgo9aX8htjnAyUwPlwZDBh0WqlhmS5/LydtbmzVyW+2ppCrSxjY5B0QZxTg9mWF6DvKedHY79a0dcSqPVd5/kde8Weol3mB15t0UK4vry0xIGCN+n5HlJcsWIwvbQBZ8aYAgC0gvrLtvRo54I4/thxR24LvAnGBAoUVEer676G84Xa2cUDnUyGDQWpoaNVZb76XV577JAe6fEZKE6QQqZlR08vxK/jKHFy0oKpCSI1Rrz5+a24lhPj5gM97IDQmg0D9MhCWkfYlONTkMo4CJzgHmQ7PDLdqBsyJEfuCYGw68HBWr6qad3MiFOcYFVJiql1pw5yqGsAxwlWJC6TY87GU3sXuKKcYCVgUOSuwB/furx3f1IbnOPCCMiGMmB43JAntKPPlltDKkp7+nSqSWHdg9Wa3P106/aGN0Ak973q1QTAcnnGyeathhCaHWsae+6tgZ5yDMGYNADBn30fMvtErNg2gG/PjiPohuFP0dLU8dgWGfeb3KHt8/Of+x/3j3nXxi0W/6yLzebh7vvdw8cfxPelvzgcFbOpghXIAAAAAElFTkSuQmCC",
    darkscythe = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAAAMCgqPICANBw36bppjAmdPBWsKCAlnGRlpEBB6GxuqVGQ1CEPxdXsbBmn/c/b///88CUtnFxe2PXH/AADldd9cDqJmWKTfY5DeYog4BE1fAYWpSWebV5f/AP/JaMQAAP9GAWJOAG1/f3+HHx+5YLPNWH7kZYf/oeVzU6yZMzOqWqeFWMfMM2bDU23JZsR2+gZ+AAAAMHRSTlMA9Plf9grxp/kNpRanAwkDAfJhFwH2BAx8oHL+UyMBkAFklgKxmpAxBJIFVxcFdG15htVYAAABmUlEQVR42u2W2XKDIBSGDyIoGuMWo2Ztkmbp/v5vV1ATjaaytJc9F46D8/H9HBgV4A9qZkxexOVJGwsBIhNdBNttdTPV9X1lWTaH/GUNuaYwy44E8vdce4lvx/UvOvuw8PjjTfgThw2FyJQzFDqGQmwqRIrCKIVDeAk6nLIwuF8gUjt3fpmCXxSrBsdX4fhWzuDjZNvFyrZPkDZBUc07EqVv11XUIKqFjnSdpKLKdO1ffagTd6xKAZ7bjiLkKLaHr6+EcHPtDEJIjeMRP88z/45T28cgup20WymegCBoNh65GlHb88I5y3L1QNxgojSiQot5CROTOMo6V3DP0DkEar4KSwAYY/VEWK0tVUiOtRGwUlC34gLWmctRCVpz2i+PCvQGg1gB5EIGrJffUQIT8Puj8UIKujzoof/JmtAJzKVg0gsqvtBxjIGMb6NlDYJyRCgl++h68DoEcUzx+O8I8x6NzuVKNlhhk0QoDWrKlVTW2IfvW1jQ5d5ESYDS5W5DDLISysMSE+VuScGMJHRvAoq8C+0/xP/Sq2+6gA7xaChR2gAAAABJRU5ErkJggg==",
    demonmask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUhHBwoJyYeIiMpJSVaGBlYAABiAAAtQ0FCQD5VVVU1QT4AVVVfAABDQT9FQkOZAAD///8AAABsAAAKCAgUFBRRBQYvBweJAAJ4AAA7OjlmAAA2AABXAABSAAFLAQIHBQMtAQJPKClmAAD/AABnAAAIBwYMCAgDFBMJCAcKCQhXAABGMjJmFReuAAAmFBQ4NTS5HDBVAAAAMHRSTlNanhbs8DVd//8D/gOxdf8FAQD8/v7+//4D/LEMbwdKLy7+iQHTUK0Rk9CS/v4D/cs9DazDAAACUElEQVR42u2W2ZqjIBBGcel09+yU4BKixiSms+f9326KRdyioedibmb+Cz4UjlVUFQihfyjyH5wDc1p8khZCgSndwOe4cIHWJFjACltHpXQFBbaECgRh7WxvSwFBoda43sEOXzgaXMJurVylV+zD0s1ZGRCcu1XpyNFr+eSgq+Rgg4jOYwmaTB0CA3KJBpR+S1JQ4cLt0HADrsGQMzbTreZM7oj+1DdNvsx6u1GToFer2iTAQrlhVNZ12bqp1wNw0h9vyvRkyI2lDsdjFEXHPdFpbzgQ/d0hzGtY6iI6RFbHWrq5M+Or/rZqFm6GymPU1SHd2NF8tB+XLbmOhrJjRVObDZjTFzsI8QiMoYnM6AQQdGHBaCxuMp2mI1fTlnwAapOdPJNRRQHwKbC7hbrHzU86DUY6MteJU241ERu9yFO3IAcH3KkBYxTvKOaDU2IA5rJAOIeH6u06MthxxXC2tTk40fqgKgPlmVZ/mftDPQWKev8wMhadAg/93HX7KkdkCtz3uIR3+6ye+1uV5Z61qUsgZkrYY0zM/+YIa8UBDSmOs5h9uIIcrUhLqr0l/AlYWhDNxRrEYkJnn/yRPwJrMUGB7T2zSL0GjEFON13gzBlkNyyhTqioM8jiuI2Ui8WomY2O3hQVvFaQ+bPgOyVBYFAug8lZECYQXuD+dd7iL+p/vwc3XS5wqaCqkkt1gaRwuCD53o8sy6pLWGWvIe7J85fsHObPQVyM95YZnSGpsuzt7jteyYhnyTM2xHe/y/nEu3ueRwjxff9v3R7f//Eb8m87o+DVQBcpwAAAAABJRU5ErkJggg==",
    diamondmask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWb3O5glqba6u55yOD7+/tqcXRwtsrf3+CkpKTPzs9PeYYwZWxWoaUaHCCO0+ddjZujpKVObXVnnK1xd7Ol7u5/9vahrrIWGmEA//+OvMo1YW9FaHNGa3Y+X2g9XGWIr7ohMDQgOkd/VSpTfYxYfYl/f/9mmcx7t8h/w9mZAADJv7vfv98AAAD4+/uK2vJ7yuNKr4ddAAAAMHRSTlP7++78BBT9pxpg+hcMEq9dUmGcCgQCoxEB+mCU8Yrf/URPBkOCAgWZiAVMCAD9/v6Yj0wUAAADB0lEQVR42r2WiXajMAxF5RUIkK1plraz7zOW+f+/mycTINMmhPTMjJrTKOBrWU+yjym80uhfgNb934g2FA7/XgOyvh20Ng8Fswu5uwnM8bEZc5aHS0Hp/CptkQcNMCCyvSViwdmSmXWR6Xp6RFdoGMsfPlnhJoIubLkAnBVLrYsk0STQhlwX+M54WTCcXE8GM9QvtwiFYPZXWJ5N8xyos/S1YhZJbY61uilgrTEaQyGrOMHq5RTQhZpz66RxMg2vRLbZmVrSy2arkSNM81aLOKHWk0ARh4t6lbFW75i3H/BzkqrOOqhJYEh59IBCF0zKUQJqqYQ2xhMnX0/KEWVUaDgyRMYIqQ9cyn4ZB6VvSCIhYtOQdKv3vK3tFXBn6zkf2hVGgLJm8qwfwt04eB8eDkzEOoKIMgF8gKoM5RiIhlFewsXmqEtsNFjynzHnKPigDklS7kzrtFqEdKPibAfk1DQtLufoNlA0DRKLyZLblvXnx7A/C0K2paZIDcrQNGYw/MJjnCE/TqWlQc9yQd43TTzGSuM7w0ye1uGEpF6WT8p4Q8Z7r56b9+ihxvt1NWhL3S5EHdS4AVfui/sT3IdVejmTAcZoamJaJ0X4sobZLL1fhep5jm/wDi+N5IiiN5IjDD7jUZPYmXp8KY6AysQ0Gl1DHWlko4hOXsBVv8H6HMun2ZOKSfu0mUw7hUlNi5qYqJ5ms1XfsoOq9eNbgGLU9opUsPVZtmZUbx93w47ul7rDqbRGMkdORpsTvyFavw8n/XrSclVYiJLd4BS9bTfsMghchsqFEZAitVzbM7rl8NTVF5r8CCImBmMgyeiYxIltxGtglBOgcxGydcmNgF1PQ5iu15Hy0b0YsRzAtNB+R14D78La9KQUUqiUbpoqXlzq17CmZgD7g6eLuLoE7kO1jnRKnnBkFmOHVf2N4jOyy7QaO5Bd2M2pD9q1TDqx7sJm7FzFJhHyhc1dqK7fcxbzZJSaHM73adeVTb9xatcRdrOfcrOq7q1YdyXYbKrbLrqlqypX/v07+W9TmLHvFkXCMwAAAABJRU5ErkJggg==",
    electromagnet = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAADX2QSrz9fP2t729gD7/f0Vb1+X52dr4+J0dADR2l2sqwLMzQNw75qmpgCgr7Scpqmj3aQdemVXXWEni3CytQSep6cJ//+43jDN1qAorp9qqKhq//+8xMUGB1gwtZ5f082pvMjIzgsAH6YAAP8RSzozmXIuwq0uz69ttVVnp6RauJ5WyKK/f3+0v8SYxMvfco/SAAAAMHRSTlMA+vr7AgEf/PoR+g6i/WKfKP1VG2mPWgH8+hwHA28Nmnq4WQYBHAdslZ1VjKYE35foE/9HAAACOUlEQVR42s2W2XKDMAxF5QUbY3ZCCtmT7vv//10lQzvpJKwPnd6ZBCejk6tIwgbgP2hz87d+HjytZoGYZ76Gx0dYTfR7gIW6gf0TbDxvNFbQm8pX+MqV+5mRbkmyTNEQHnI4+Mu0GJ0mF+IjeXsBtYBPIXhSkKcagXInH02LIy5EgthiEFRnICzd6gjvKh8E39toBLEnglZtnt7dUG1cNH/FD2WQNaBq2d45ZIELP+S3lqEC8FICi3TdZ2gQdOGZv9+d3BK/vVeQcwHUpo3qAmMXzfQCdjGrWM0TeMHgBdVX8H2Xo4XScdkbloaxSAsK56n8bEt26HCUEDo/ffJun5mOMhfNt1D7Pi5Q+fVZaECtmQV4zbTmgsLFsQwQJ3alVI9jxcIdwLNmDiQFVC7fTdF9X6osNGDI2iXKeYbrKEM47WrkDwgOrCg7Z4j/F/9AjAEDoDFNXzJHEofS3QMgv/sYt33REQvqgFWRpiHqlnUZktorAZSzu/bNnAT2S7pqwYiysH2WJbsiLAwLrZR9U26uggOJntX1Qu7W6ddV0oCEQc/4AgvHbJDSXpAh9BX03NMGZ1gZj+SAzotvMrYWRtSl0RqWQjSkbTIYfQyAQMGdwVpKOeWYIzCRU0/VNRS4RQk8poyceK5uRQNOfgAgMJnBFQmCKXiTwRQ5PgOU2EWxnPOwMi9TMCFyH+l0PxMguJ1siHcjgTAZNLhbBXU9B3Qb5AmmTqqFdie3M9oRh+WfPuQaa6WEf6ovzpIZN2cZTkUAAAAASUVORK5CYII=",
    elitebarrel = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUQHB0bICQmUi8aHyMZHB5iYjtVj1xXV0c4bEMAAF89k0AAW1tINilXOjJsPUJBkz2PUlZDLyQAAP///wBVVVUAAABQOy5XQjOVPDw7lTssJicWHCIXIiYUGBs3NS9JlUqQREZxQ0YNJBqLQDsVOCQPFRoQFxwNExNFfEsAADWTPkAQFRcOGBoiHBsSFhxGJyzTpwd/AAAAMHRSTlMi4vuiW//9/vsC/wKi3vr//3QBAQMA/f7///39/fz9/v7++f7+aqwX/gT/TpH6x/+w2YDpAAAC7UlEQVR42r2XAVurIBSGIVyumrfVvYPFEFdL3dSt///v7uGAqJt4fXqe7pfBprweoAMfkc03RX4APHnNBU9PYy1fT7MiElLnXhEhcyLmTVFc0p1S6a5VuqOsaPJoEmygfepkEMOlDm8mwLyFJE3P8gySEiu8WYfBi5SaGwkuobSfUVpLWQRBooUVh4vbCi+8xykJgZF5jPFsKXhfQkQhcCXwuX2/ozG07cJiFQBJsmi5a9DeWZUBkLuIvAWFu9xYEzIORi5GN1APumEGwJXoZOO4GfadeBkFy0S4QQ3msu0GDnIUrKUTJKfNMwW/FFMP71Mp6zEwt2lqkzP1Gd6mKj5remCdwxqKQFT1tFMj2ilaEw8y9WHUbwBfU+VCmleYSkFfzefIUAYsC6XvUMu7z04yIOojlsXnMbvP4Lq/P3aK30fFaelB9rnMnrPHDIqe4kNVVfvq0Gpv9XVpwadNA+DbtZ4X21tV+0MHkhB4qKBlNeAGYDDi4SqaKYZdZWNgdg1uD7egWmaPs0HajTH6uJsDuq6y74G/vorNAHybC1K2efgWKAfg0ibLI+h5CqwALFoQinQJWQo/KJ9ykF9bk2SmvYu3rZIBSJU268EukRjL43GxSN7XkNX79XrvtX7vumpAFC7JDyeFy0+bdaS5KWPYd75+xb3J6Zup0mAtxl3gMus5xVWPa3mHO4Kk6hYEFcqgIgYJqGFr060kvgoclm3+jOzk6IKwl2FbY3La9gE4ittIHTAdBn7q3BhLGKzb5+DL+axZ0Oa4MJ1Ke35uX4OT1G3kt8aaLIS1XzND2tiw5lS3HsuDxmoN0rSLvd8J50Ki53LX4G+wZO5d8dopOX+BFoGIJBE9q3Fm7J2dTJxzmOjc30d0tsymDki55G3rzt1sJevJI1kB8ygGssccqZrN0xRYNilmTuesaBnnS1T+6/QYNRf4k6NZoXVBAlyKhsw6dtY5Y4UTY3lNfv5ofSJ+Il4fRk7X5L//F/AXoLwcBskFr3QAAAAASUVORK5CYII=",
    eliteblueguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUnMl8LGDAPI0guRH42YLk4Y8YAGQAQEA4UKVMAAAALDA8PExYnWssNFCkWO40UJk0FBggGBwoJCgwwV7EpSJIGDSYQEhQbN3AICgwICxIjOHIYQI8KCw8LG0YbSKwiPIUPERMbMlwXJTUVK2MmS6kOEBQJFiw0U5YTEhMMHjAJFCUKGi8VKlAdULceWsUgLFlLzgBLAAAAMHRSTlP/nmb///8KfJ8A+/z//f79LU1z/f760f6M0P//q/v//7D8//3/k078Wi1t0qb///9BSNcbAAAB60lEQVR42u2W23KbMBCGSdL0IFXWIiGQMCCDsZ1Tk/d/u67ApgqoMXgy0174Hy75WO3q312iHxcquoJX8HPAGC4DY/K8vwQEQhv+8vL99nb/+Ph1AagJZQ13Kp9vbp6e9gCzQEFOUkoxJ2pMoYUQWsSDpiAYMkNmCuo5HCkmYDyLI2IMQkrpHHCSo57FUQojECjFKqrz6Pg6Csbr3F2guwVFw8KIegQKwuo8tzkqQ7xpulucajMyABjGsxXKWpuh8ryuOweN8N3YOQVhUWJXg9brJFmv3Se4D+qx5QSent8lbVu1laOOND53kZewmHh14/LmifyJ+lVV+JxgmzN1jJnGAZN/cyUre7KXbKsKo9volGUKwe6IU0pUmXlkjydvLBTQN0CBMdm2xbdfXz3y7VQcYsRf+tF5TvHky/uQQ1VdY0C4kYWzOZbo3gdrNnDEK+v7CRAbV6KVlIGIXkuFhhUmqtTWO27yxwBDSwXn6q5PVAZALA98MMmFI0srQxGLD1dAnHb3cjiCpddT4szu2FBGMFHZGaA0Quw2KYoQOLd0uuPyHEm5Yl0YQAl9flv1x7XyXm4VLFpz4PqFZYdDaRbuR9jRhuIYYnrxYhWukszA8o3sEh2G07JVXvhTZgkIDw/w//51XMF/Cf4GOd+FSIsEQqoAAAAASUVORK5CYII=",
    eliteredguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVeHSBTFxSGIR/JICgAAAAREhMTDRC6GRTDGBMvCAkKBAQNCwuRJSWvIiMLCAiuIhsMCgsSDAtKCg1wGBgzFRYPCwxTExOJGhp/AACPHCIQEBE1CAZuJCVVIySUGxuIJBxKBARJCwlIGBa1HiEXEBA3GRkuEQxVEgx0IBz/AAAJEAkOEA4iCQQgDAYoIB5GDwyRsvXcAAAAMHRSTlPnu8H/APz7/v77L479/FD7bM78+/mu9/4C/NLX+vzB/ijRKP6zJ6rS+wFNezS+97iCi39GAAABw0lEQVR42u3V13KrMBAGYJKAFHUk2oHgOI7T6/u/3VkhO1YhxbnJDf+MPcPFN7vSCpTlv0y2wAX+DaQ2v4ElapqGQUobSX9eERVBWIIfH+fXWIawQMUwNIx+vzlU7wDkwDW0L6mXmV1lh1qTdw8EcgHZbO7vN+93dx89eOPQO+bDum0rl/War/lYI5lCNrWJ9h3bP5JxYaOmCD4SVKaQahQuEGAvzs4hSmGI6A3RM63CLEMHsNueT7EO84oQOXfkbElPIQvVwYmHljSzZ5W+WvixyiKEirdEyxn4L789IeEqAeI9VKojiOWz8DozBPknwIdi3R52JoanlYNBRYwtVPyBkDKfh1eX3AS9ItMJ7KDgYcEYrkiwRtML7CKgGZl/AevgAJgeu1FsO5h9/hm8vqx8hxy0e6N4XDAahyFFBLc7aLzZJwfg5YJEL7Pp3M70wewTyIr4K9ByMcEqHEUEn4sEmgkKbsJRhPApdVARpji9FeUXH+Sk06JecYGVSHcmfh8ZawYfvq3GkfOxrYn87gqgUpbsZhj246zrOoPfzQ/vDuBMa+0+W3ae8phLh1LJmmY69Oz42wo0rJwuV/kCF3hE/gMoYUdTI+9ziQAAAABJRU5ErkJggg==",
    firemask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUrGxqhbR5hWlpaDwVnGg1KEg1oaGivqi9QS0s2HhpTTk1HGhQ7BwGVb17oo2k4BwGqAACCGAmDFQb///9tdBpmYBoAVTgAVVVsXhuZZmarclWqqlW7hGT/AP///1X/xm8AAABwDAKKEgSLCgG1pS1SCQKRJwp6EQR7AACsiSeTNg6wlyqZVhj/AABVAACVRhPi3AREAAAAMHRSTlMa/e+f5FgF+GNRoSma8PfpA9i2AQukCQNnBWsD+AED/gD9/v7++f79Av79/v4BA/7Uq21sAAACfElEQVR42rWW2ZKbMBBFW0iAwevEnuzJCMQiCTD//3fpFvaME1uAqcp9oQp0uL1JAHKhwP8oWgoudlytl4IpwLJQYaHjUaapv0Kjb00DWBROtA78liNgiH4rDPhJMIIwWK38z8FfmiQIAj858sY0SLCVUfRsqOSYwPOhRnIVBEv6GEnAFI+woI+wzFEeEdx+j74tynGbPj1yp1+w3e62QQqeaL2Oa7ndvSHpGwEPeO7k5x3qZ7DqngEP8suaCyFehEg8ax7e7GTIywxVlqUI0X8meJAhUTUJrzyZ6dhJnv2lMnngeQ/qgcsHDSTck3B/I7zhLiTH8KfAAxnmN6JEMViYAMmwrnP1ocESuglQ/3AZqjyvrqLSCjjBOPhb8tr2jBnTFIMaw1hL3ZzI8SszRexU3CiOX0GPgac4JgfGemvfY7W271v2OurIW1vdVuamRDX3g8AzWkQ9yOrsTsIDdlKoy2SjrovF9QbqdvQ+wLOEK1Krig3dV5WxisanLPf7PUj9yFHDvtyXbmwUa9pKOdSYy6TvN4k/x2QjaD8pZYqGnFTeNnHv8hUTAxC6salYUbQOxDFgDtxgRH5QE1hnlTG4nsCKwCpz4JjjAKJPXMQDSGPjLKfANe1F1RvDqDhKMZy8wREmQNcNHAI3B5hk3+YuRy6nwSy3+dALZ1rVc3IcwIZdLNG7NZfTY0aOmS2sMtgPZW3e2Ky+b+O/fezOVNZctbi5mh67YZqWRoLD1EamhlBurFe26VmrLBWKS6mnTgAkhUsO4zSM6lsLPuskx1eH/IUkPpF4SDtuzifA7Tn6T7k+6/Tcr5V+P7e7rjucn/mw6vNZa/1ffub/ALirdz2Aw/qWAAAAAElFTkSuQmCC",
    glider = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVjXh5mXR4LEBMQFhkqLycZICB0aiJfWiWJfCiklC9fX19SUlKIeyby5Rm4uCqQgyr///8AAGoAampIPRiqqlUAAP8A/wC/fwCMfyePgyv/fwD//1UAAAAZGRkQGiKWiCsoKCimly8OFh04ODZ/fwAOFhsAADWShCoGCgwRFRgOFRs4OBANFRssKQ8kKiRsZie2uak6AAAAMHRSTlMVYFqZIu+Y7uz5G2iiAwOrAQICHQMBAQRgQAIDAAv8+wz99wgC0QTRLjSsCWkS/PLKjV10AAAB0klEQVR42u2VaXObMBCGhbjBsXP2XFkSEpcN4f//u+6K0CYu4DTT6YcOC8MwYh/evRAMPmhsAzfwvwGt/XOwmm5uH5l9J8i+v9y07MVlf34HaG8I4V13Kos4iSLP8wKAx2sg2wN4kR8eRxu0RIsjDvBpFUQ175DK5+NksSPl4PMril4ttUZwknyWoyVxyRfBW8RSjZY6xQKPCUxkEoZls6TIE+1Mhg4rSr9rsTZRFMXJUKD586Afj5jUQ1j6vHWLTz/filU+FnwG9MM01SnGVR8YxQ2KVhUI2zNLTWr8U1E0l2CDXSNK1ztcD6oAhMBlg2f2a5Y4h7u3IHLHJJU6+YKrjAZFKQF0mFdjeH+Z4z1gEEUsd1/R7eHsolQwgmtDXkFXUP29HgM7G3QeTwevfh1NiVzZQtWThhr9hQEl1j8rc8K2nQRQjJSUcSEKNdZnGfzWoR711ihyny6IXVPEBDlUyjiUGKNQzlwFoyFsqT2umAaFBImR7nqoD1p7b4cBUUV5BsHKZsWg1ofPF9MnVED5ZiugBU/K/rdHQuV5Bnm2CFpgNQY6swuaPF9qI7ip3On6AxuyhWAn2fyum70e75ni9OzmH/877H77sW7gBv498AcaxlLUWpeJPwAAAABJRU5ErkJggg==",
    goldenrake = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVeXytfYjMjKxpocURhYmBkaTl5hUuCfTr//wBgaEt3hExrckwiZhmmpi+Ggj2rq253czeAfEL///+LiU6LjVBVLhL//39mmFiBezsxMSo7Pk1+gD1zg02h5V0AAH8/QVEA/wBmmTO/fz+AfUCBkFOqqqqGiaz/qlUAAACKiUeVlEp5djl6dzpaZDp/fwBSWjb9wGEvAAAAMHRSTlMcXhSmB5rj7gFjqtUWBPAE0uoBoN4kAg2mQlXtYgQCjQEFBK9DA/8DAPv+sPqMAmxzhDlMAAACQ0lEQVR42r2W6ZbaMAyF5TUrYYfO1uleycT4/d+uMjAFhpI4OT3jnzn+cq2rxQYcueA/gfvpYhQI4xT3iHK5HKW4XK1Ioh4AshhKQxk5EjhJBjU7AoYoy4hakRbpaROIlto2ggo36TFGLGszEqyaKBh3TXHHau2cF9E8LcIDqFG0x0XUqAEgB2VmswPp6CnR1FNA8LYsVTjA1XPGa8G2JpHv9uQIbilTyIM5xVlygoKYTAIlFo94SbpSjmlkYHKHeZ1kjr4lBymeTrg5kuskUOND9Xr+LNynY6/1gj+x+FVdZKWXPCtK9Xg5RQ7k8PGY/0bf7dAFeO3tFE0n2VVcB7IeM8l3kbypZrnuBSWT8spbjgZmq2heF5ifyMvApWhciS89ijrXO/f9LwkLhJ0jW/IPejpPo45xLt7sEE+uqozCr73NvuWQTmSO6x1Z65UpItXX61PUzSmforFWGV9VInZD75Bg/zKaAftErvRGGeXrmNz+6RLJJjMNxVNGMPkq/YaCLxWnVPBKKUi+g6OZc6es8N5HX/aJ4ITNdHZVBMOclJt9sqLIOOXBG28CJD8XYtE1biWUYD24KtvuWo1yxJgPXtR49TiAjjTw9e7IWIiggHcTCO6XaZSrLJQihKK42Qh3jxlfE9VD+RyC4Jx/SZwAesHFTUGVhZJK1lqnjg6+6Wypwo9SKij0kJnzguUzWjDArvxzMN8Dt7nyYGUoUOpBU65GWW1DuP+ug/sdbAXKEQP5M0Kdf8DT+iqXe/xgxe71BysrvkQ2hXSbAAAAAElFTkSuQmCC",
    gummyballer = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAADac+Tqh/IL+egH9LrrdfKnXar//P8C/eumWK1nMGubpuv/AP9wZHEAomkGdGpK1umuZ7fTc90C5LD/r/8Hs6O4c8rGbdQD66/hhem5Z8UA/39cWpEGtKMF7K5/f+mwP62qZ8cAAP8Afz8BvrgA/wAD/9l3PoJ8WoJ/kapxk7x+uPS7Zciqqqq3gL7/AFXhBbXKAAAAMHRSTlMA+fv98goTAQZaE/0BEh4O+aCfpQMX7nBfp5kCGUkZBBwTAQSCAYAxWqbj/HED4wM2F+WcAAAB4klEQVR42q2WR4LbMAxFQVIs6lS14/G09GRK7n+7ACq2sjKgyV9w9wQQHwAF8D9UWmvdDs5OZ19KOQ9waA9u/YCAOyhSm4nIzx5atchRcK76Jd5CFlyugOzKqUZSULsBVcYGHVi9F9wXsYDzFixFLm5yFfiIZb34qFJJ4zj4sXInWcthQVp5vFVpmm2b3FnvvT3z5so/XbC1ZW8Xuciug0xU+olU8lsXAh0nvagEgbF/Un0VDg9Tw9eotyBvQIO/N6grp5igBeJMroiZwZ7HHWYujyYSiYNteUtEv5iIHOGRWv8nMLbtm5/LqXScEkaQVxvcdktJ4pwwraDH29wzrP5NqRKnSxAFVDrPMc9RN9x5vrhHGpU+c0DMSi3xyAfi4j3T/HYKtSwgjV4Oc8vfBJ+VXimt8yRJBvb2SZvpdu/Nr8mQJ+Y4TmZndVnifauqHnE9e+6m/GcLUQPseN8dvNLey+SkhRM+mL2Vkz3Qiu7lYAGOkrV7kk3pdX+8E4csoJlf9ztxZd2omvCAvopJTDYmXSUlvxTV7zExphtCEIEBjga7PTGd8JoX0BxhkIADVMlMHuFBGLIzc6pQi8A61AnNZlcFGYhxqq7DdCthRIBvRH8/7vitqCYLA+xRHQb4uP4C2PAS6azc0hsAAAAASUVORK5CYII=",
    gummyboots = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAACkZKwjqHa6bMXBacoix4hV+/QTcWgruYVgo5ytlsyW1dpsXHGMi7All20jmW2TXJr///846aliPWRl7/UgsGskw4YK//RQxZ8A/wBvbIuRX5kkZE4luoMO8H9sTXL/AP8AYAodd1kawX4+/vVMNlFVqlVV2Nf/qv/HjNw/KlUmwIRoTW57VX96SYFjdoULcikWAAAAMHRSTlMA+/j+/vv/D/r++v4S/l+npQEEEQgNqAH/AfhfTKMDYwES//7/RwNgA/8Mf434bLOYfIj3AAABvUlEQVR42u2W2XaDIBBAB9CAGybu2Zum2br+/98VVASNmrRvOSf3wROOXGYccAzAkyePx8vI6BYHiFuyf4fj+/7nFyqZTr+3YnjWN999P47j6tLxzrBECkKIuG7larBcTiVI04kHiWtJgzQTpks5n1gWIZZ5A2ammMDJKz1Lgcjl4tYQZEactWOeXEIaU8RwAtdrEO5ARNgukPakyAJvovHcfvFQ10SLiE0mb4Y5IBLl1ZkKERd3iYraE0+EHTPVfpGKiERnWtZh8bpw29W5Fn2ZqhGxFut5gUAW9VqksPtBev9ah6CmV6RzCJkjCGR9KrcrInOtua8CArbxfm/bjFULBGgUXRkhMrsFwyMip40YimAtEQ+LjlNgYx8p5+t1ljWRB0VHLBo2Wm4u8JFl6xAj6NUKhk0RdpRGmzxqxivWVyKnEOEk4iXsQNM0iqIkwQxflThwbFZ5K0gH2g/FGuVXWUroSOMKcQdm11maD9gn2rgfthpvlTzDWJ6krhdSON5qs5yHYWkbHi+PyxjHXO0qN2wOOb3Z18XGRmqLSpuJNJN7vySUprn6Rf/8DaObTfM2/IP5/Pk34MmD8gtKZhnFLfDKUgAAAABJRU5ErkJggg==",
    gummymask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAADNbdcY6Ju5bMataLhJyZ6fkcvWhOBlsK6mZK7//P9kImaHmrlvYXKPXZWZYZ7/AP/6pfpMp3F3r8PkdecKf39oV3EG6J8A///PhNoAAP8mn2cky5FVqmp///+7bMUbWiU2to0A/wB7VYOqqqrRedQmV0kuoXgurYdqPGZwdZBVoaNoi6N//793w8Ilh2a1CXTAAAAAMHRSTlMA/v779/3+9/yfAQ77EFkaAQSj/gQCV6wBsQEaDwQCqxHpAWIDm0OhrEqTH04E/3ovzAzCAAACaUlEQVR42s2W7XajIBCGB1FARFxNmo+mSZO023bbbff+724HjEoSoORf3+OJmsPDzDDMIMCP0d32U8Luc3t3I7edHje3cBKg6/DqusVN9nYAhSisRNGlc6vjHjJUcWLTFwY2B3EYwew1Nc4dfDA2O4Fo+QAPqeDfmRAi67Ese0sFpQWLPkz8eU1ORg1fTAyOZtk/N61xvau8lzKWXyBx/1Rl7kq9wHMSt8jpGUjzCubfQb8A9DlmyRqa77xEDkHay94NSRszZUTP0FCPcpI3UsbyIOuSTOMJISOpoyalcdQCjk4oREljkFyqt/4UXdLmGhvYPAYenzgNglW4flfg83RA/8TSkUfAQPdZASyXS1tIQswYox7w3t8ubJtxVRQ4ARvJxSoQ5SYLCF1ADwIx1iW8Y+kVWVhvD74GsuB8iAXdmwnvDEuA/bXFsrzcbGaGcx/2H95WUAYSgRP0Hix9MbZzGQDHfDClffYaxyKdsnABa7gqy/kEMpMDPg0/3bATcH3dfVxQIMmcF/ucQ12BZw+07uKICbTLYoyGCrKdSoMx16IBFT5Uwbbx6A4dQWJeRBIo7AZ14zWzhAoZS+bM4lmIxtMy2ImBOuDoaDHMokP9bQLRvSn/aggxeAa08Mh9u0VZi5SEDwEJJSeWpaJwbBLbRvLI6TGSalgQXGCh+ggQvI+cADiCc86GpbSpyBT+xctaxjq55oYkXIwfDkboho6fjnPQxiI/ZcHSuKac13CMkxhGaUjebzvDMMY5pH0EWJQp/Fj5Mtb5GqBKwOr+puH3em0unf7x2LTtxda4QXU1h1ai2qaCn6H/0YEdRgl97U4AAAAASUVORK5CYII=",
    hastyguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWrqqdubm6SkZAvMCfd3dl3d3bDslLCvoO7tnCnp6a5ubDS0qVhWhuclmK+sSSYjCasnzLPxGCDeh+ysnb//wD//3/PzpbGxsZvbBy+vsH/AADCtC/GvmLMzJnMzMwAAADLy8vCsTDDrjHT08+9rDHQzK7///+8sE65rUrNxZSZmTPU0bbGunG+si/Swi69rC01fKJ1AAAAMHRSTlOiGWYT9U3//fsV0uomXlyVy/9eBAECV1pQ3QFcWwUFAPz+/v76/AH+/f0F/v7+/1yhXS6dAAACV0lEQVR42u3WWZOjIBAAYPDIeMQcm2tvMQjCqjP//99tg2IgHplJ1b5sTT9MWZbfNISmAeVPBvqE/x7iw6/T4c90HOL4dxxjPAHxUxk557kfn8/nn9lbF5vNxjz92LxlmXe5XGLI6UDM1d8QyTTd7/dFUbya6J9WjaQ0oAlCNtQqQ2kqo0iIUse10HGFx6IUVSMZUUEJ1p+bjCFKWJ3uK2BtC0qHhiA1qynVEPlDRp576BuhLBI6Udt9b2ApmkaC6hwhYW5BFMDbRIDqPm+L/qEQijHt+oS5DT31TlZtn6c1sK06Rm7hWRDnIcyZyFVhQ0hXwdxqh1GEnYy4g1cL6nSQjRE7Ai+fhmqIRR9lJSlxgybdWgxwDZB28BZlxUYQ+dwtOQVZsyqXIYWfJrYhrAd8whrxABJYfO5CtR4Poak2JyO8r+/gdQSRtfOsjPV+GVKoNn6/H1UF1HK1DJHlDMQpJewBhJ90FooFSBN/onX4yRR0Koc6CYeNjAKYY3SDUERQcnaBJ3iyWSnIXNiKF2usAcrnIGP3GW1I8AyEOULpXOegaTUjGELJsZdbBdxB6q7FByDCs5AqODNUOrSaEfQ9BH21msmoZojnzg4/Q4kYWrgDxzO0oPqH653qUcaWVdMXAFQbXzitYug9251qcOq4UN0xYnW/83O+eLDi3F9/2ZavmpZlFcnaVBt+x1EOdqeHKiLG2GgjTsPvx8GWxSqSQaDKNJw4q2cvD/7X7S7LoIRpgD5w6zgezbQ9FIQTI124rqxPOT/xp+85mPOnL0j48xL4H8O/8Ft3+9DgwekAAAAASUVORK5CYII=",
    heattreatedplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUZFx+GLyGbVCMxMjJ/f39rLyYvLy////8AAP9+RBcAAABWFgw3NjYXERCMKRdqGw50IxGnSRQSCwuoUxiUNRY0DAeiOBI0NTWTRhcvFQ9LNSspKSkyMjM3NzdLKiUuKSlLIhpqNyVxQyQqKikzNDN1MxFVVVUnJSUnJyaHSCIYGBguLS4yMzRDDwcuLi6aUhyPUVyNAAAAMHRSTlMP+/5VAvrNAQH/AP77//7//v7//v7+/8///vwGiAT7/fz7/XKy/wMvVf0qinr/tv4aE3jwAAADXElEQVR42p2Wi3abMAyGadeuGxhfsEMMCQSaQm5d+v5vt182ycjmQM50To4J6LNkWbIVxf8p0cS3auWlehAk/T40xyRYjZD9+nO9xm//oMU9tD+WEHaR5cf6dDptp8Bv56t+WZb1a9u2dV1e+OM9cDsQBDxBDCcxRr7WNX35iPsA2Edrgtonp82lECIhEUJC8NCw5S5gsY8/GWuNQ6D1a3ErNAVj63gVcPWD1ZyLfxlHSZ4kG/YZV0Gw8c45+QXxrkpJruMTRacPg1dMeu1BpPM+QXCCUR2DCInwhLh4IVu2DIK776wduZqMrLvBHoJgFX9j5QGgsHIAumG01uH6HUGtwuCzIYWBxIN32upOJFLplp3+7MYNyA7aJJ1WqgMqrXZTSKsUXml9KMfbeAVf4t2SlVDWKoeWtddR58Za25XI2H3AVbzaUsb9tAZiYcaNX5asFkWWbhjbhqujik6MbdKCZFEkpO4kc5L+xd1UR7RnDHOnaTaW1L2AweNEPTqT6b8yC57ZptiEOAKjCXBLYBEAEZtzfx/s4WvYU8TmPHVYHbHI7AZJfbAKt4t3wN6dOZurETcUTUZ/uucSKf4jDL7EyJ1y4/U7vy+pNYuMQKQ4TPZ3XF2Wz7ZxYPLcOTDRFjNkhVFfJeq4CmZOvGflV84pOhmVBoCFVEpmGEyub+t4BK7iNXvXORcgF53KeVIsEo6cTQocVTl8nQKhL5CkiVGGjifBc6UEnXG5OsxadMU7AlEefBaERXkDGqUlhkdAAhATB7rFcQfOBEflziRA7n0GIYFPbQeBpfYmCZQXsKMlUgJswwlAZ0d5ULmhi+riqgNppS7l4vsp13qTAIfwckMgDG4mjg5K8ndPWj2EFxkghVEW1XG/rKgcywORwmhvEg8m8Ss8TdXjDuQXIc5XCq9BUDkZXEaTXQecpWXKBCb9vuAeMLTC/Uy7cnLL5C4FrqBqcYuvpkFy1iI9hdKG1kig5BJNx24ajL5TJ4CdNEOyIg9wmTezIK6exjcowot0z/Pgcekv9IHwE6DFmQVX6Mjq5vYub6itOk9vxxu1SYhPTdIAqX0zdtNU3eke96O28U/7GD3UIW9HbSe1nMcHO+RLnD6vTe5b9VhPXo31Xv7qqR9o5u828nPgpPwGULSv07vZKugAAAAASUVORK5CYII=",
    helmet = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEViUQJtWwUqJAFYHQFmWgOFcAM5MQGscgBfUAP/AADysABHOAC/vwB/f38AAACPdwObgQF5ZQJtWgGCbAN/fwBVVQD//wBqWANXRwKKdQNpWANrWANHPARZSAJoVQZ4ZAUvJwJqWAN5ZQQXFwGiiAMwKwE3MwJMRAN6PQBoWASCbAWqqgAdGAFENwBIPAFYSgUHsW/NAAAAMHRSTlPbYBYMHaVSBKEBBJsEAgD9/v77/QIEAZJn0W/RMbAtjCyvsRH/Ei40BFPLAyZNbE/GVjg2AAAC+0lEQVR42p2X6WKqMBCFI4va9t4JCQFlUUTrvr3/291JWEzCUnvnR5GQjzMZspwS+M8gw4/cKBK/ByPvU14+Z0K8D0anmboeDjd1/SOid8BKIZ/4CYbvpxt1//GG4m6ZXhJKAxnfAaVJUjx/UkS1Q0m1qOmAnttc+sAruGloUXV8+2uT1ECswLqkYReqZQsP4j4QX3dmDdcFEU3cP6ILClhvaTjCBfTb1yQbUAhP43pBRD042eAVJjRko4oBDTTJ1xgLFBwHleTVBAV4F8o0xaFRRmCDRqYDqWJMmo/ZpLrH0qAiHVOU7YU9Ro8qMKRjmth88SzwHCCng3RAc22BKtM3wCA1QVdlqg1SjVPCrzdUrVsTxJpWYGiBprS8yw0w7QFfjNG0/EmxRfABfwXLf0zVRmpwb4DLFqxIvNP6yqh+4B/HBtVjLGvbzeBUy3LBWAkDIGMW+WrI4MjZcgCUyYY6yZrgLNvBg61tsMmU1qPtBIIADrfBqnNdzF6U8wXAhluTfKMqxtrvoJNt7neB/SYm6JigUtWiSrWA2GFPa3XM8YH+8XtAzlKY2mOEpQStiWq8ht+/OM87xYF7B9wuXvE85HvYE14+MnsHcDPO6/mGx1p+2HXOtQ/YEM7Knb2vYq6SC/1zs7VrUR9Kd8LmO3t7zHHwISmOAPGn6D/4XawNiWzF/Qq/xh0P/NOw07jCqrNZQewueFjG0Zi3if+W9malzv6MsU08CsI2oK4NRrDkbA4jmk7sXALqdBRjIJxPAWb9luj0KXcYSvo8wBTX3wLr6vWWFPbI0bTXrnwRHrLJBuKZbaYiOPsXOT2efWAMX3KJJNVbY9HYKfGBx2kSULlg1wPO6kHk4kr84nwz2jcoh9OZlmLIkh1Iuyz99Jgfj3n+LNKtxDAbshvxctOMqRVo7s2cE55l7YHc71fnGcnMHY6vpm/4VTV7po/HakUwVjKmuiUdVjzN6pnn3G51jTped9CTR85JVJ4G3bVwfmPmlZ93o9//FzAe/wAGLMO/N49yPQAAAABJRU5ErkJggg==",
    hikingboots = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVOMy5PJiMnIiAjHh5/cXFNNTBlQjv/f39xcQAdFRUiHBxlQzlsRz6qVVWqqlX///9AKij/AAAAAABoRD1uSEElHR4sIiJRNzI5OTkjHBxxSkIbFRUoIB4UFxQYEhIkGxsrJydaOzQlHR1SNTBYOjRVVVU7AAAjHBtePjdqNTUmGRd/AAAmFhYiGhk7JiNMLS2n9uU9AAAAMHRSTlNZISfnA/SnAgJvsE/MAwMBiwEA/v37/f4EsdJR+g8vbwi2y3ONAwSQ0QQwAhNPSRCXOL72AAACKklEQVR42u2Wx7riMAxGU+G2aa4ppJBCSALM+7/dyHYKhFRWs7jahC/2QbL0K5aGXjTtG1wP1tYLYF7uxSPW/4JdguASrADz8od86lp6ts9gR2EpelvjUf/Ujpjcm4f2C2Cga7udhPC9fYk1pywdx8lzva6fQeMZEuYF6DTvMcajRgxYS7MsS1NNu91uVVUNz3gko6QWZLgNpTt5isoeTMdAgs/4+T3RkNOD+rhHgvHw7OQBdHS8zkSoBsobUBR/4pAjHKmELBqP2m61P+KFKqtvyMg8TNY79Jpy5KL6G07YgSDH3UbwlwItlG0E9wo00G20gNPgz05yHhlinNlkEQwLju/TSghn1OTToNWC1GSM85aVGOOToX61WbXQB6NgihUY/J5JDqcRiBXAGBUSFPsZt+kCh1kLIuQngMD2hp4HGWU+fBcarfpuIlB6UEFTm0wHyg49+AeqGbnSrYjXDbOplGJYNwOrb2RoTVRFwi1LInhNpgNl0eN3VaDoWtAiBC1+ToAQKDMhnYO7QxT2gkR//ybPopPcgbFw5rZyRU2HqKwEJGDmmoubmvIHtauMsmDufvxgnSA6JWLFvc9erO+KorKytmoBFWgSz4I+a0t66B0LDkQzCwbXVg0ijU3UItAirpdmgIvfsf1/0HDd8AAs6LZtHakZZ+3U4btm7zjZNq5A5yiWXXuHy6Dc6heu1Iy+yeNJlu4auWG9ebI6Oa+PZKfvsfN/Bv8BIcLrj9FUJfUAAAAASUVORK5CYII=",
    honeycombbelt = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEXi0avIuqXUmBHn2cr8/PizewLXr1W7hQ5wWAR0cW6gWAD/+wNeMAOloZ/Zyqe8sKHz5ambbAOvrXOpnJW4rKXLjwrgwXkoGwSuXV2pnHX/AACfcAj/fwDEtJFwSgCxhB6uoX/loaHEt7ZfOwNvaG9/f/9VqgCGe2a/rHz/vwAAAADWx7T+/fzGiQS3qozTlAhnGLO5AAAAMHRSTlP2+ef8Avn9/B0UDQEbEJ/uBFwMYqGq9RQDWQGTAmRopv8EqUBHAgNIoAQA/f/7/vz2o9PhAAACMElEQVR42u2VaXPjIAyGBRjwfedO2m73xqH8/3+3EtjZOM1M0372m4TMIB50IGMwXxQs4AIu4EVRkkR3waIotsU2uQ9F0QjfgkUx7Rbd4cblOZnra7Cl1UnXdUmyuUN+M0X52vd91XfvPP7oXytGEt07MokKJoIGVpb/wa3ZwTDglyTE6YbE9HrBghUARG/aEYwMkMjA6NNiTps8z+OcBlzQiZEKo6kDmOEI3mFgcUsTSyu1tdJaezDF6G10OfymYgGlvvP+gIV4KM2DlVJq/9OHagSxArQMSsoFKNKSOMbe3sZMhmdkyCGOWlrmIyV7RXsDJKZAEJMAsuD8RDLnOOfKizur/Vx1sUMbbYPHDiYwWLRVVPszSShnFUCwUtACVlQdqmpt/lzIF0xXSR6gIOWkAvZCgfp4ePMzDWAcfVdiCoc4B1fcWWirkazG2inue893TmYcpUmNg0FJq84zDdppLB/zp6EcN3+nljuaFceTFL7WT3buEIUFfqLKYxprbhvz6/qx2pzKEk073GOWIWmt+bM5lTvf4c2sybPM/+1i07jbSBG0mof100N15TGpa+rttuHW3oQKOMXTum63uL1v3turI2nbLG6stus5px2PTfzhnYPB6vU1Jx3PTfbRZbXPTIyhqalA4JAzJn3olttwTm2GZ7pWVrrVo9fj3mxWbpK9z933eMzoNEetTLZ/+ELGCsZeaZxOZ/zYTZ7NIv/MK2CfBh3T5f24gAv4Sf0D3H3G/Tg5otYAAAAASUVORK5CYII=",
    honeydipper = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUpGwhvIA9hWyRgNBxtTxeulmmIdE9va2U7JwyPdU9uOx9dUxBRMxJ6aEilY1mrq2NcUgiAUByIdVP/AAD/f3+qVQCqqgD///8AfwC/Pz+XgVz/fwDBp3b//38AAABuUxJ3ThlbUgdsOR5vOyB/fwBVVQCHXShQSQZUSwZXTgf//wA7OwBUTAZJRARZUAhmNxwRLy/tAAAAMHRSTlMgAxiV6f6eDUbuzH5bVAQDjP5qAQIDAwECBLEC/QIA/f76+fYCBf5uiPgBBbFOt7G6L/isAAAByklEQVR42p2W2XaDMAxEzRoCJM3Wpus4AQKELPz/31UG2hc2y4In4J4ZybKRgGGIqZeXLiwmeDFWLKJoU5ZR9EDGACsUsouryDKGojiruKq77NseBTPcCZMKPJ/vsHXBCwLCTnQp9knGNUESbNIj8KRA3eJkJCi3ilLBUHxDKTuKQj7xqgdmEG7r9KRuqV3VGx7XpjKdYkxPNMHi3FSmVXS1W+6iumb7pykHlnE0x+JfkC6BPQfcdmWl0mS6Vq1WsSsNY1tRVVWjuo3RgrMfq9tTXt1cLeadtZErbKTMc0myQ7t4quU6cExwvMlLBVKidr9ppkAbj1aw6Lf3zH4UrgLLEb1xcA1/mbsF/3g84tOLBP9cXcBeegt8scEX7DzfzviKR/jeyuCn0zldsMHWKQyswv/e4YdttXG6Gjgv5sGV54tJp2NWfc+nRNng3lkuV9R1bFCkieuYKAZpkjqwuKAFJ0lSMT0eDL2tQII1Dtw5x1IpzjodBJXTYHrKGQLXCNM0nHM6lCM5Teo5p32wcZoEeOeCH6gJ7A8LcyDVNFSLYfHBuKkpe149wKHaCD64R+3S6vPBNeIwjA1Haw2jQx9VAAwVLVNQK34BD4FpV3QxXUEAAAAASUVORK5CYII=",
    honeymask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVtXxdXVCOklCmmoCitmSa0kRjIoRsiJRtzZRgnKxCccxbbqiOMdhnFsS+Eeifx6jjkyjM8QSz//2oSHStGPhFBPBiacQj/AAAUHCRnYyn/fwAAVVWqqlX///8AAADItDC7qi7Ari4WIi0PHSz//wDWwTOomi0EBg4vNyx/fwFsZiUiLCwXGBE4NReShyqyewEwnITfAAAAMHRSTlMg/WURmufo7k8PGgVXl/8E8f4CqSL/qgFlugIDAwEA/f3+/v4B/v7//gL+//////g9HeURAAAC3klEQVR42p2Xh7aiMBCGAyGhiPX2u7uZ4KUsLOX9324nCSjSFP9zFAN8mZJJkYgnRZYf55sgeAbM1ddmPRgLETqhuqwDY0F4xJv3tRY/BGEH3jD+blx+GFQGecMZa6acXYyRsIY1DWPrXW1Q7MBWWcwp3ROPcX4AbwWY7801dN4db0VWqXpibx2bXMrgQYve9gCQJACHbfhoyWE8HleMEf7yxESQZMz59hUzsoMxOQTjPXEGGFp16D6/A1Jhw4Qcna8F8CQCmJQ9dJYMAqQcojGGt+hgVIagncgpgzIZmhy46jsglYFIqWc7AklvSTLwFKSMbnQxGS4mJwQZTZISE3sXHAn7ugdiiO27Vy87Z31/ETS50HDaEzYXs/pVF4WFOv5V+ncVttyXz0nwl/h0z+efvs4/54uwdXb93B+BhNCX84T6Hbkzrr70bBkZH42Ox6PlUUKG4CsJviyrKFSMu12NYl1WujTrKx2AlLFUTk8MaCtB4mqQQFd5F1Ae8K5cFLNR+cAiCfCmMw1E2qqMvNlxfJ0xqYtIgrfZUzoC4/g7FtAz0ZVpN5MjIP25TG5mlckcyMKqoe0EoLZ2eoqCPw8y9TakVZZlbymYTizVkBgkzNbqt5kcgFxZlJXyFiQ2qrq0cLrNg7jiaFDZqOVOzcwI3rLMBZmqKGfBD+FpEK24qY4xUq5WtR6OBVAYEF/GIpJmDWmTKmEZJCaVkBa9+oSiMKV3FwTplnqxMMORWFm1UyZv1scBmKiwUrcsrbor+dQqq6qSav+YBWPfSfTQsZ2blZWaZBb+KFS9AVverRzQBQeyRqYsS9fayURXanCKl0C1B+iMtEG2hSoTZ3HTwYdEj0TUlrrB8MNelzcds7FGHaqHUtGcit93zgAnYXPj5XUt5874+ECmDreho9cXXEsiyfh26z9y6hAiwFMVriNblG2HpDswPXJAIqd+688+f/xkFWyMKAnyp/4FzOs/5k9nDSBMF+AAAAAASUVORK5CYII=",
    hydroponicplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVwlJlnbW6dzdEgIB8sLCzN1thhk9KSrsg3SF1oaGguLS60wL1QcJ1FfMc1PEWUnp47ec7///8YTBg4WIY9QD49gNl5gH4AAP+qqqoAAACwu7w2Nja0xMWGsbQsLC2uvMOMqawoKCiPl5fN19g3NzdTV1ec09U0NDOjrKza4+VFSEgrKyuDiYo1NTQ5OTlMhM9QUgI2AAAAMHRSTlP//f8rXf////gClv/+//z+/wEF9f3//wEDAP/7/v/7/v8I/v+F/P+u///8a/7PBP/iXf10AAAEAUlEQVR42p2XC3eiPBCGg4Aoam339n1mIkQiC3KR///v9p0EVKBd251zPFrxyTuZW1Jx+EcT73+9Pj3a58Dr+p11noNX9+afg+A8WOB/SrEuirZI6NHasz8TnYJxy8xLVeVsHluOL4LBlY9An6jymibLSmmtLLWUuqLzM7CgXBlZ6mywUhojPwMmnrlcLsaY0Jq5hMY0yXOwJvKgwTAsxAqh1HlCwfoJeGop8XhzSineIn/ce8nz4Bz8lnKpXGS0BqikbmxY356AUOw5VrUfy6xi8kk6kmoQvJvar4j8v4Hg8pIDMrVfRMVh5K2YchIRNVKm0r7SgURk6w8UT/8fUDbSphFEj6QyZc9VRgkVtX8PrnjonJhorwbQUYNu1K1eyLo7V6wLBDQyoQNvtmF1Fb0uZVYl1Poz8Axf8kxFC4BKKrc/mw617KI0KqUqsdFbcAcQbjap3ES7bhGaNF1GjKTLJS/QvUZqo1kdNVSMQdToHoDCT0MD4LUDCQeByDSKUq1zbzMKrnCBoaQJw7Lk7Sh2btdBahN1y4gllcwEZ0ptSlSCGwYOrKkypvSqRvUpiKyrKu2zss8wBpKqTJU3SAo7oAoISg+Lqj556lZ2TOrM49HDmmjq1koK5gIiZbgHqFGjRDhSw1GiGnEX0XJLFB9OFnzjvg9Tz042odJpnWKAIIPx4dDStvu55TKwIAu+bJdiRS2UE28zbg6lMx4Brb/+r6bv3XL7MoAn5H61+9mtMFh8emjHm6ec9wAbC2jVLXcMfnOg/cKCTFI2JkPeQ83VbRUfwfMNfMMiSTPxNcNi8akHu/sereJuUCxoNgEUx7uGqzV5/LPxHl93FkTpZRczJVkTxd1i/5wY/+0wRJVcVH2UnmdCM01I2LBMi0WNHZW3kmupssVUxLTCyFFTsw9bG3DMu1uRX62DrtvwTC3Yfvdm/1BKcHX8UureV32tUo68N16OVr5Dv4cFFgrHBzrA7fARrCnZWp8QiUUvc9NbLI5Sew0Kn8MbjxuZ+LCx+5FHa5F70/wSR3TpIizRIj/iyczhKs09HKhyg9/pwSwqBM5XHD2odCpO68nMYRIPXkolxHFkWmiZ5ZV9HM/G4/pwqsk1pAap7xgEj3Yy0sNsHB8BuAm15KlUjDWFSEtEs639vxw6MVfqcQC14zimyfSwmp9WAnEFofWgp3Gy/hi7OQdPXI+hchhHFRwKA3V2nt6QJgdr4BIqQTjTLu0zwdlRXvP8xAzQjjum0k5G/9ldbm1JwijuGyPccvr8T91Xcf7kexRLqXHB8mh+b/jwoouDkipa2eGdfMC9f0MuHq6cRfCVq3VwttdcXHaDL93JH1O2/vYVxevtHn/94n8Bz+0P9Rw4A2/t2esAAAAASUVORK5CYII=",
    jar = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWKWlBdYVctKChVjFZkUzhLSU09lEA8O0SIRTluHRxRMCY7Q0w9bURXVlefgmJgOS5Ckz1paRY3MTNuPDA2OUGEODL/AAD///83Zj2lNzf/f39aQzSFOSyqVVWqqqpEPkBbVloAAACJdleTPDs8ljxNSlB1aFJqaWtQUlRJlUtuQ0paQzFsRzh/f3+QPUGMe2FXzyr2AAAAMHRSTlP+9h//7E//LvwHYEr/DP+c/wNI5ELKAQH/BAKTqQMDb5MA/v7//P78+//7+PwC//60SOKxAAACJ0lEQVR42t2WbXOjIBCAWYoe0FobTZpc23sBKyVRk///724xSauIxtxc++GeyWRIxscFhd0l6i8h/1hMqKO5RqTJz+7PddNcFZFGDnpNxAgcby3t8DedITYqefOBaJYYwZeLgamKGeIjBdIHCFU/ZjzVdMXrHnmxkurxopgWnHsheVHIQMyuKJxHtL7/QGvtVKEWE6JQsuD6oH3uSfGinibE72pVEB2AkFwqOi4+qVXQQ5NLvO2YKNY0HxE1f5kQ8Ujk5BBEk3T8qeK5zXZgwgCjZ3yRgoVyEuuAW7X2RGvLGaDYDESAO+hjd47TDnLD0ka++M3am+2Nh+G8swP3ZL8bEeNtH1N02e9Hxdc+D+xonAKiuhuucUr8iPk/iPEnicXMqW4D4vA9lp4YxzGKnLv3jpynellEdTtco70NijGuchu7YHH8+uC2HO5P9zmFJOPiEdzf7YY3u+OheKcMiSXA5q7DZgO2PF7eOc3D81jOYznIAOClAPsBnmjIaJYtl8tsmHOiKPlVgnlPV5gAzsnxoOF5uugwGMmrLE0amjiGYoNtCorBlGzY86Dq9IoOq427DvzArJZTIlVpVbdit97gFEzN6JSIdZdVTiLdhO68Op0scy5oVTFjCOl4xtRVRcWlUi7xKgadiIB/VFJdErEoVy2nzqEdMzqvCUzZ0XTfOWqShpqOcPeYSZmyNE+lpNc0uguv2bqiXxUJFQshRLL4up78E8U/KKl3yT+45usAAAAASUVORK5CYII=",
    lookerguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUgZyceViMVJCAKHw0ldS4mgjFCgkgLIhAAVQA6kERAc0QRDxF/f38AAAAQFhQnhjIKJREveTcmVy4taTYQNxcGCAg3hkILEw4qkjUoeS4A/wAUSBgAfwA4eUQLKQwKCwsMFBAaRCMODA8EFwQOOBEXWBwICgoVRBwcaCQjSikjYygmbCsOEBEEJwYSRBQdVSYQiLFvAAAAMHRSTlOkY/1v0+L/JwP9+rACAP39/Pj6/fkt/cv+0gFLAvwoa6/6jBcwcE/5kPuYspYUNf8giXS6AAAB4UlEQVR42u2W23KCMBCGA2itthASDhrOgngAte//do06SjaE4HS86Yx7wd032X//PYDsPwZ6g2/wFWC+DWbBJZ4GTxX/VJbrLC9RFMdjHjwFGow1TYOo7zqPWOZPgDFeYUwI8eiuQ5df5XYMrFp8jTD06Fp8ttwG+uIYnJpe0TSla4HkGQc6cINW+B484wMQe9xq7Nh34IX1QMJOr8h3MLrmKpK8TgBdWoEaPE/wGFpYlapz9rgXoQfK5PiNcZLB5GalBKYHAB7m5CyDn3bG+iAxRc6lczZTNLkiVw886Hq47muM7E3/SQiaKTsrx2oig+QHSvxAlQJMZCs5uBM5h340thKMmeyGD8xYhIZ6A1RSeUI5UxLzUqhWRw1FpgB0adhuBsAzkySKoO8RNLisEDQD1MYn2LC/B8CYgNECtVnj6YY3mBoEPZBSKBGjEy/9wELuxpmE6VrqN6TZ5DURRsOEElmsATMk2O9CiSx7mNEDI7vuNFLXNEWJreZ28NUzETrcFF3kI5VortUJDTTqRaIO7DYI9aV+y3T3MbGz6Q0kkoupYevBe9stAFhk4xe5xqsVX6qT3X2bFmVZBqOnPOJWTlmLDMPiB7bM87FrJTZsfMtLe9Bf+9cRJe8/q38G/gKZJbGrrZKkdwAAAABJRU5ErkJggg==",
    magnet = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVaWlyaIBacmp9jEgqXGwqTmp+kpKVram0yHh6OHBOlMCeNkZV2FA6kYF91dHb/ZWXnMzO0xtB9goeUWFSZmcytucP//wAAAH8aUF15eHx7e4t+foB8fIB7ipGSeoDBKhv/AP//fwD/qqrMzMwAAACwJBmMi42UlJf/////AAB/AACos7ususN/f3+tGw+rIheGiog8AAAAMHRSTlMboekiGZwIXRJp6mpa+p0DBf94rAXOAQImxyGp1SO6/wECBgUA/Pn9AQED+foD/dJSKdYrAAACFUlEQVR42q2W15qkIBCFERTDaNsTdnYnbJopAQP6/m+3gN2mwUB/W1eN+vepOkVCcGOg/waKT3SzoqDIFRQQBQEyP1xBWjf1tyB0V7y7x3VdNwFQtxrJr0ZJ1jXeTXYGluAXSYaxVnyavpByTzEu2lazCL7vOD0fVl2hom0zJT6t/Kdxmq6DpOjDg2oGBk3fpRWwUpn2QWYFwituGt2lddDruY7YenQ/s9oKpvOsokesJZsHkHawhK4H/ak3qkdtq5vUwB9YAwsLCJD+Vka3ySPkq65awTIxD9t0o489l1TWHqFV8FqjF9kc87b66H0Bq0FwUbi1HaQcvjmTi9MJgY1U00VWlX/9r6XgylwlZ98Mn4cnMVSby2o04tnXX8bddRLmm+Awd7wYJphO1N9cyKOHRed5A6Ymr7+zA4wraxrpwhjbhpxbyPTQTl4CSfTGMwY5eATkgLMsGSslljxtIIKQc84yT0ccmboPgU8QcMY4/tEP/56rY6cVEhHWYAAfkJ99cviYoypTxbFw78hdvhaXTN3ODrWhAWIafHM9rSjcKY7x/SP5izmnY5kuQAnICJ6Es2KIVY08cr51INPEF/frSp9p6A5qaxhDzmDEjDXuN6vwkqlwAyWcNPeO3BXZYcEpKCHUoFoY0g2kcFmJwi1VBBHWmT7sLowFqKzBnGPVREdz1K3ExM13cuEOSiolRTcrHox/BRmky18BqI4AAAAASUVORK5CYII=",
    megajug = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWVPTxda01ZmVYfOCGYlHUlLCFTVDi7sY2XXVczWjErSyvEtZB3d3QeZR4eMh4hNiFmahk7k0GKRjwnRCmlmHf///9wa1X//wCxo4A9bEVmmWZ+s4GbPkGFe2K0tGqOgWTUqn///7QAVVU+jD8A//9/AABISDB//3+q/6qJwIkAAAAhOyUyVDG0qIQtSis8ljxQ4mvWAAAAMHRSTlP+/f7z+B3++v7jnfoGBGShDP79YKQBVAGq9wn//2cDeQYDA/8BAn8CA/8A/f79/P+yjaZUAAACYElEQVR42p2WibajIAyG3YJFcald5+539kGk7/92E4Ra7EXF/np6LCffCYQQEvAHFbiH6xqggAdAI1gNwu+yqkpY7RFi2bZSxiU/rATbuO1V8mIdKGNNVpPLdILfFai0DoSffABjfvIGGedlpVeowBXBuWImOt5g1bsaVIEnaLvT8wUvsJT3IEbWA4TWodIDrFxg60qfYNmh22WwtMKpxBuDlRuMl8DTJMgWPMbSRcpFkMVGgyujp7ng1Ay6hBApZTwIc09KQsI9/K2LKfCNszxPuy5RisJeiVbXHZXFqOxZHiFL0lwpHYTf/b8uzHYw4fHAM0G0j86WGghDIYSkI9gKTiZwfVIIXBPppSZLSD+Kw0oZuMGrpC1hKZvyKGYlvUD7G+feBxnB4gvIzFSpMboKY5MmyQbfTSh2DvAPgt+i6DnSev6HP8raUijLW7YPYKHBsZpmExg1QUMkODwqUETRxdI2anpmY2hCXQlQ8B2ClzFIAltuEPhO0nuwGYMZf/IESfBy4xpi7cYYFNsReLGn+rKZABkHKrYWGW3RYzNsBe4usXbDDg6C9lb8iPBQKnOd8io5wOURRUWIQEjVQ6nAF82xJJhTIylM1Bw6n+OCcg9wdKxolpUlALjBE4I3Y32Mw6ivOcfZKwCPBw0Haywauuyo8nEsivm6Cqkqc7m2vtYcfOqFgnzgaa7rUzcWLNxWNXvPO5eWL1bYu8hXV7Nz3wN8JfN3v66j3qdJbmgMVb73bFdUm/m6P+s743w+miEPj+xNrxZMpnz+8u8e2cencf9R1ytba9br8WZ+Rv8BT0Gwe6TJh4YAAAAASUVORK5CYII=",
    mondobeltbag = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAACioqZEduZgX2BgYGE5atU6ODmxFA4eKWoxV6xiAwO8vMFwcHIXLmEAAP9vb3CZFRD////Dw8c7ac9NhP6dY2L/AAAcNnEmVK8xV65we/ZzhKIoSZU+eO47ac9rDAiMDQeSEws/P78Af39wfp1Tmv9q//+DhIoAAxcfP4hAPT5CPkBAbtquQTyAf4DJGhPn7mNFAAAAMHRSTlMA+/r8G/r/9A7qDP5VZwGYogH/pP/7AZoYYA35qRVgWRZUBALjDAJyS8j//2////9y5vM8AAABPElEQVR42u2U13KEIBSGQUSx97Wsuro1Pe//djlYNmKZ7CS55LsRRz74OXMQIYlEIvk1u0cnuu7kxey0HTxsVUAwTkXRj9ioIfPQNiYfqhZecFPd07G6DJPZpXCYy0bzoOt+2zboJiiWZYVWiMcNsqrOI0WhJbpOguifOsh4DRuxvH6LwInjmJZPaHJKyOmD+L6iWXgfUQqOAlDDQegoFtUEM1kXlRGuBbMqd+dMMCETJQxDXqw9HbR0UtE7PKmeEI1DvsEhxmd61wLmzsWmi7onry/aFJ5AAZFSI8+yrabwE/xBBDSeHCzap43qnC01M0CzunRZe5FXFHY1eHkWLMQBiMqVMnU2G9j2PLIUjefUGZ3r5jmhs21bXMAbPlXskdvD1G4JzztjuCMF+1Hi84M/3u1A/t4kEsl/8wWWlRCJpQBv3AAAAABJRU5ErkJggg==",
    pesticideplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVYYSynpSwtLi3g3SdS1mEbHhsyMTI0MzM2jjxGjEplZWU7ckM6dz1giDWCfS/CujX///8+sEtAe0MZGV2em0Y9O0AuRS49xU5APTJ/AH+qqqoAAAA6mEQ1NTQ8pUZLx1hEqE5HtlRN01tDl0w0Ry82WTU5OTk8h0NRVypydisqKiouLS6KiC40NTU3Zjno5iwCQrp4AAAAMHRSTlP+/mX//iOn1P/+Avz+///+Af/+BP5jC//+AgMA/vv//v7+//77/QX+/f4G9/+J/f8YcGAwAAADoUlEQVR42p2WiZajKhCGC8UtptPpnrmrICAQNW7v/3a3wNycRM0yU32STp/2y19VUD9A8ZsBj/5xnuP0a+D5x/Xj8fQ+6B6NgiGIB3writ37itEQJx330cXB24pR3HXGZlIqJTPLefImGHButaCUVhiUSoPkj5fgDjmjaSVKxtIUX4xKzoM3FE+JUfSvNE3rOVJBbcejf1+ARxTMRVV9oVzqFEtBq6zhQ3F6oRhx3oBy9Qkx11iJD+KSPT0HAw4h6BmSkgoM+tF3PF6tJiwFSdhmHlAfraYeJGSjP7AUJH2TeaEav0K6jCWZmm5F3oL/RMnfP/uw3ztQ7ElIQDlpzB44jx6Cp2LAzuDjo3A6AORwAEyWwidpDJb5CNwVCYfe6TjBrCctmaBGUkKj9TJZuOGizmZwIL1VosL8pgYmX6ZiqhLjQhJuMg26UehxtNicSvchaQ74Yq4/opTfz0DOa6WU76mGFgNG7bojGdP2IVjsopibWpZlibTSTOJgZUKpEjc8+1629X4dExyN8hJSfkk5f/SC/OmW43yU5SpSlq/2znqT1yuSsQyX8fx8HoObZK+gHrvlxlk5wJ/xKlnGas6H8+6F58S4JHecTMvMbZvdy1SV+LpvjUIP6F6kGiWdpX7N5xVx74pmPXTxKwdowA2hn2S53/uNVNX9T/5kOlx0/LNnF5Dm8JE6+Uq7eeTR7jE4dO3UXkCaQRj6sapkQwg83quz5bSgPVhJQ8KQGEy8UiYMzaKzdw4Qc445yTlT009hOLXODoTtCfYneTxWxnmVV8QCezJNPQBaXVXD5Nzj1pfhbhzRHOcaK2l7SEgI3QENC4vsjdY8iYotcODQYFmtVxxbgqPcECBkxP58W02VwSrPK/CIY9wSVxWC2JlPrLBvJ3wHPRu0tJjrGkTHyXG9CGncBhhbJAj+GYbhp/XuWtZ3RwhcM/0Dzyml93bEx7zgRNDXp5BgeRRtB00g2exqlHDcYcJ7lbLQAEaDP8bkUl1m61FXDZuNCiWzfLQWrM1zZ1roVgwFo+OW4rG4zrC7N2DIOZzJecH49pBc+qr/ch//j/8cK5tbHDpoOGwzcv5sk6OvWrnJ1S/mMXK+ugWaZ+fj5XaUrZPVI396IvtRxjIXFMvtKtE1iMnyMa9rR2vNdO0o7uZi9+pKluBzBsNaO1rjqTiI3rk9BnGS8GtsUlugz8hdcwcM/BVdbr5vKJ7uqzmdfuUyfz7/3mX+jfgPWcNDL/UDOZcAAAAASUVORK5CYII=",
    petalbelt = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVq8Wjf2u7kzY3axHv7+v2U4JyfnajW0uZycHhz9XObmKpg2V7SvXV4doiyrcUPGRJ4dJ+52slLqUtRrFCn9KfOyt+sqtnCvdcXahQA/wBktGeLipyhtLC4tMzBu9QAAP87fzt96oC6uc3/cv8AAH82SEg/vz9ZP3J/f///AP/Xv4DUqtTDv9cAAADa1vDi3PhOSSthAAAAMHRSTlP7+f7+A/kamxQFV6b/S54UGfthDgRkD6UeAZqU2FZgAUj//AMCDgQUAgH/Bu0A/f5eCup8AAACnklEQVR42u3W6XLbIBAAYFYCdMSW5Tt3mqR3C7z/23V3AQlkO3Xcmf7KZiaZWP7YZYVAwlwY4gP+K/wuKd4LdRRSn4KaB5Z9nXzGifT2Ue56/Gf3dAj1r7GWcWxJqrIAzsJW80B1CmUYuMJ41B7QB8Y8VIDhHDgAWz0cKbXe08AY1kKloyPmrMOw+DnS6rHnUYWvB69bHNRy4NhQ1cRaHgcv+OBLLim1Nh3YLBxUC0nODSpYaP00GP4wc2cnAVujcxNkPscjEGpuShZgoctgM4W+FQcZEeprmWbsqXM5hIJhiumWvJpNM8Lr1saWM2NXFgcZLSxXi7HUjblSkElyRVGWWbF8Q5UQ4so0EQoBNquVHMeA/EKw6MTKfGV4g78Fp/RNSVxZFjmkhCKunLX5FKCLSyuokiQERm4pGDYeNuZKeBmmOeTDH27RUOiziFMkKBmOkr4eMnLSgvtCjgtFuMmgUHGZ+hrLmZelf6wGN2ZsAhRqGWQxi/mOOJzjZgJjiyz8LIdKw620SzF8aVxyCzGGUgpz+jJnsyI8bks1fuOenkOGNd2PhFJjPWSnRB5zcmGtLpKLz7wQihk5nvIEquRBlov75ELo0Mw7jBze+W2O4ZNpX9TQnzCtIro8parzXU63t763tzDdC5KGorvLtw4ue71erRqzd3Aaqvtvk331ddhf93YKx1Jv7/qwVWdnx80Nb7HTjK4zKz+N1RunlabNdJKxw7V5zTtGI0/Cz3Jx0J25WSOVTbN+63yUB5OEL7S66r+dyFrWkBfbyfOO8h0eJJDu6O257wDSJCnB/tZGngvnUdLf4+7Ey8PcQ/wdT7XzoEbJ2V66E/lOZdzxmQpdy8f5OyC+SrQPLTLZX/Zm1V/wSnbwDvbxvvof4B/wt6n7fqr6BAAAAABJRU5ErkJggg==",
    petalplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWkpJ1iYlfk46cyMjGs161jY2MbGxqopXLu68ns4XZRTjf///8uLi643MPAuXfBu5MqKio/PUFVVQBwlHt5pYGBd0e/v8D/AAAAAADs6uvi25g1NjX08/IrKyvKysnX19TQyYzu6cwpKSnu567252/Y1ZPv5pM3Nzc6OjqY26k1NTU3NzfYzHTn2HInJyZYWFfdQlkrAAAAMHRSTlP9/P5u/wMs/f7//QGQ////zoAD///6/wEA///7/vz+/v7/Bv7///+HBP+yzv/+TvoYTgyxAAADwElEQVR42p2Xi3qjNhCFJXG1k2za7rY1IMQdYxvD+79dz0gYhBNsb8eXLwZ+nZE0F4Ud/qexrRulsZdBTz/udfOFrjMjdI9Bb/7LOeL1p+Mv97qHisORbHAuibELeG3OQ0X/kqTakoRzxhjnYOkXPhdnG/TN83zkCVMZmWK4xGiIRKPeV7AjLh2Zfj4UYVgURQXLWVWEuMRI/H0hLcUhSbnKlMqKMKzamKxtWyHwVVXCoMO8RGxZFcNlhaji3LKGBqgIhduX4V4R00vAZfCvjZv8kwUw/RX8AFyJqsoihmVy7sAhGZmKIhlFIFtytGkaIylEFRZVEUkZMZ4m/j3Iogy3YLQoLV60QKE2OFrQnUgqeHsPcqaxyLCL0dIWxXRDspvkDXQSnhE4fcxbPyqLYhmRJN/1yrIbl1qCWWSZlPavaISv5QzSFlo3s9Wz0uDmmuTpAnaHMzhbUK4V9duQ92DCllndgfidaUUipbRc9e48VWytiAtMhUZTZtwGzwmfJ5G5bA1GCF+yTHuM7ZhXtdSeUlJEWfih/lFqDSpmUFoyya19JDDh48jHoHJPGeWHvQWTIElqwfPhbQK7w6ATP0n3wnUVZcgNlBan3A8ZjatYfTv4Dgxp7BKomJh8Jc51meHE6cMIWrFKky3h76/T6UOxTyFMkEnM2T2ZwUTunn4iky/+Kq28skOwMjzTIIvieIrpEBwMoGh6wVB2ki+JjGhFoQraukYuCsyxQNFp20aDrojzqwg0561BT5eAdF/D4rhC+RAoNvghNNkA3FGwfVce/TMiVtRaEqIT2BLpimZX7/5Op534Wlf/2F9hO13fiKzraxy7pJhf612wBXqo47yHaRBe1tdr38SQdPMe422Cfx3eEez9VYMxzbbvoS7A5TuQfNtV/0zkLp4kay2OaCLBH3vafG+rW2kyNpK7um90mSQuMJvYbbY58ra5SeohiOuRFHOwbbRyaAZT46i106jjwd4q4Rvgv1R/hAGv2tO8oektTWMDLBF7+9xIxsbTBn6e/btO/tXVN+wmqxYQzWNPZb98dlxBBUoDG2yCW/F+DJaHow3C02DO+scHpPJigzlN8WJt/OYBCdFjzzHPP/fYwe4Z6FHbYkVjgdTAnysCRNuShWjmORZsHWvbitRG5oaK5phR1HQvKa4aQKReBLE2cjJTXhE4wwv7iMDBAYRNTbnI2PjS4uiep/vBaEwfAZ3n26EL5fFsDp2pOXkeh9eP1v50SMUx9egfvtH7HrxLhK77jcN8uZj3m/8FPLP/ABnCMKwSKgHHAAAAAElFTkSuQmCC",
    petalwand = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAADSzefkz49taWv6+v3OuXqkoK+2s8qnnHCXlKLYwnyemquopqzMuI1xbiSnomLNyeGkmG/AvNSnnG1mZlR4eZy1sclTIyG3tMvp8KjJtnh7dYd/f/+srNnQu4X//wA5OUlMLkxndVGbeGOIfVb//3/cxXvWxYfDwNZNi02/fz+CdVmqVaqq/6r/AAD/AP+3VgO9AAAAMHRSTlMA/fwUAfzy9PNZ+6MX9w4Qrpz7bFgYVxGiBpxfAha3ARcKgwxCA7daUpgE1QMDAQE67F6FAAACEUlEQVR42u2W15KjMBBFG0kgCQkw0fZ6bE9Om/7/77ZFWJJAuGprn+Y+GIvicDsoAPClf6Hr9VZiDw97+vJws9M+AUrxmiTxLVjNGKWE4GhzkEa5ersQVAiw1dMYXCLSKAwL+GF/jk3Gn/BGeoUk35rfE80HXEi+wdEaFpX0nrbq7l56zievVhDY75030EFJCbLnQj98Bfhlj21E1uo5BP3lfiyRPnIIPi/0A6uqrCBSRljWo91Q2h2xLg1oLSu1BdqAfisE2YwrgXpWERINwGmSlC1xCPotKURuqYr2lhRFCOKP5+FTswQrb0VRROrrbpaiDLwt2tEpqN+r6sCd4AEYs81yXUl1yFYtp3PuTp+7V2mtpZEK+CCErP1vWbR4ZxRHcYLTwIvzrI32bmGa1ziDMgjUqGK8ReUi2Uw/GaBG5cp4M6ZrW51uwEmT0JQ3eTrBaYcUJmCmAVsOlVpB0BTO72uWDBQ35Lir/H7DTnwyhhNLTmnJluM0hvpYIKhUocag6/D4CVJ8PNbre+jJgVFHoEkUiJwxWkK/3jg2n60bMppGItUsrhvzl1PuU+45EqLNpyMzT5VOQwiESOGpG8mGoy4ugdRw7anakQpcnJk1QhTIw4B0cwgIYxgPVxqoar7BTfQCOYIDPwC3GZiNOhGmohOdXWjMTGUeb//swm8hIb5vCW3ew7iI4T/rCl9q9AdTvRdQdk5YUAAAAABJRU5ErkJggg==",
    plasticplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUrKippXzLv4pMdHR1iYmLk1mZDPCackE7DrD0tLS0xLiGGeDXawjvEsFBwak6ShTg9PUBOThwkSCSCekkAAFU9QDt/f/8AAAD+4T395EY3NjWtm0Py2EeqmDstLCnjykf73TvbxETLt0f///83Nze6pjs0NDVMRyopKSk0NDI6Ojq3pkX65mz+9ZbQuDz++KiKX7NFAAAAMHRSTlNk/f4rA/78/v+N8/z///z98gUH+wP/AgD///r+///8/////gGz/8/8B4sE/v////8VumKkAAADoUlEQVR42p2X2ZqqMBCEWURxm+VskhACZAQUEN//7U51WAQEnG/qAhf86aS7k5TG6YcyZr6/tPrzfTDP86/ex69Oq3wJzFd0ta+Gcb3iYtj9m6vFiEDOKW+Vnh8y5iPaxvaDcyklX68zaK1hWYvz7Qxob2vI/O2rOAyFCGNVQP5+b+79/a5P9kAb4yNoY1k3h02oWMv1dgz+O10/pDQB3UmlCBuJRszziOxiGm26rpwwMJZlOccieCghuVXIIqfAaI0+mJ+uf+WbRRQgUP5I+CYAyQrOz4OIiAfOKhVBgV/4T6QfuABZJvnpqwVzPU7rXpbJU6geeiyZx8w++HVKpVneSlYtcYFzKyO26YMngIWDxB2COSgoNhaefGD+COSKJsCqpMtLm1O8LZSD0oJjBwHQ7iUnXSuMH5USceVS8pVSTi1Ux7rfblbJhAZ3qEfeAx1E9CKKqqvN2K0nxMIteqw4Uts9wF1mlZFHEXEFpS8lVPeap4U36KQMhRyC9T0PYb05ARQZT3V2NGjLJuILsTAWpkzb5FxQ/+z+LVAcqAN0dgxq8DN/s9hrLqK8ATyfPltQvt11OZaoCBkQcfFG4EWDn3XEKIrEBNvLqTi4gZ9xfm0i/gKYHVG7xYSKkNpKoVf5pcmqBjdFFYuuZKOYoqaCQol32azkJqvc9GmpV6HuGl305lVDid4JYnQOwHp3bZtcmippNgq3ivVeE1ZV5brNJpKoUDBRidGyslOZoaFi5SbBk5JExXogAhFH4MnmWaxHh0BYGfX+RGtEtYPXCVJP4IrAyIu8dmLNGmH9fE2BF75W9cLSJdG56Qr/AOPQHIE5l4ETsZc9Hmcj8DOVvhO9XBzhEafQADwZ/J3pQS6A4kBTTPt1JNBklBuxONLQlMMjgEAegGRLi7ESPucT4O6dsWhxhrFJIx2Cv3Cm7vaMzcdELfayC9g7WI2U70xBXcBmAm4w0G0+eSLLDG0QTc8wPuJY5faUByCSGmgKw0DVmrjVpOvAcYdyivHhTy4CizHrMvNsV7j02SHuDn5SawWY2vHUngEvqdyzCHkfiJ6DdG92H9eHtxpFNPQqEQOhn+hEURnV4jILSnO8SdbTDLAuUns1a8k47T6PpNAclRu8mxnX3ZbPmkCbfmDCgjXSdk77ODoY593jSpNSdrbv4SJTe9Hogmw9J2xk6ze3hvEda22Tx4XLvfZvDuzxJDj4RWOq4ba/ZeZbI5//4F/AS/0H4B4xQvsU4+EAAAAASUVORK5CYII=",
    porcelaindipper = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAABOVl6hpajX2t1pbW4nUaysHxtXYWmYjCpcZW1kXxE9Q0onXdYyNjxnGxH///8hJlRbbpb7AwPPHxopZ2h3h56iTVI6Pki9wcSZEg2ZEQyEeSVoXhp3bCF/f/8YMW4ZPYwjY7EcRqF1DAueniKhoVCYkEz//wAcPpEAAP84SmAcS7UiWMtxNjhXaaOwDAydCDCJAAAAMHRSTlMA+Pz+CvT1YPibFPz1/BUBD/IC9g75/v//Zp3kZpsCWqMEmkYEBOwBKwFkZ6j/EBZIkj8fAAAB9klEQVR42s2WW3fqIBBGB0IgJDEx5uqlalu19/b//7szA9E+OvDQdWYtfXK7v2GABOB/LBVJqb+TUXXGGGnD/gB/bARVb6ELa86KuUwYJ24VkFXVyBXCf0jZsYXWUYWQcgxQKlqXYiRZQ1KroGY3iL8fF+O1ySXPuLRiISCRUnjUWtkzsLp2A5QJFqKFXyBOl0o0MEnpyATdwpqGlRSFE9k8yt8BS4zpGUmFy2TuH5IVfVF7MzpJigp7xgboMGn/GxSXB6fxfQfatGuA6prUBaUe79sqTSRN4qqTkrPhVvCsWzQWvsnEj4Mh/FlVG922okDR5KMmSf/OGsWP1u3wJWbhhItq7zIYFNaw1nrQX/NAaIicE1VtWo0FQzsIMtIMTc06imvtanAy4bg9A8Nt83zj+nGxEPbtkbdNEd14sEnT1B+JRxZbEUm+1NXTxzLgarSzME3Lskw/4ZXJrToEvfB4PD6hFrhXzpy0/PTH85UdV0rzfXBJ303I5Y89kuhAJBi1fwsQ+n12QLKpmNTZCd29vQfTlB/8pxQKb/e94fZ4VnBxHf7ezuzFyS6X6vZMVuxncZ5l2S78XeGMwmybB3MvscIX2DlhuDLfZtlDzGtR7oSniDcpEuZR3LYKB3N4IOEpYk0hw/MfkxRgB3FcdJ3+2BdS/wD+yhdEIyxGGQAAAABJRU5ErkJggg==",
    porcelainportohive = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAACanpyWNjU7lTujnVlhZmmbWStakTKgljlnaGeWPEBsYjbIzdJ6gon///9iXTW6wshkYSBgZmS2vMR4e4JcCwtgZGGQmqUlJyoWLmlPjkI2OTonMVgSKFoRNHgXOIiXFA3BupYwMzQgWFg8lkFgCwdVVaqFFQ+Iei8AAP+eTSOEgimPhVC0tLT//wA/P79Oy7lMAAAAMHRSTlMA+/z+/Pn8/voL///+9gFQ/hdh/f4bpKtZa//HJY799KP/own/UQN2bAG7cKQDAQRsCEcVAAABqUlEQVR42u2W2XaDIBBAQSFqIsYFt9Y0mqXZ2///uyImUZQopq/eB485cJ0A44wATEy8wLLekL5vDrs6Y2WHX7PmD1X8OIaMOPZHLS6GQeC6rm3bAYTKFvDhncC2XTcIYrVdqb0n8VZhnc4WQEIpJaRh+uC3z/EshmcRIkgQEhhZfGggZjm32hmbr5FH7GXJ8VFF6Rc8IkJXPiKPaJ2AaZoImcjscn/Wi1zwTNMQWMxa8GmhIK3SNPORoTdg4kJrUopheNg3tBNI12CNkcHM3dP8YOK8honnnPliRGZ+VaIuiGLEmQbyzgrTUtztBkSt661KUR+KqB3yvSiu1mpiJ+Q2W0nEubg5My2XHGMl1qeoG5KIB8nxg6h1/p0EMM/7UJo6dW7JYKPSZPWAd7xclq3ZxfPuejwuWeK8fENw9VrcKYrHHeork86P40UQUygBe2y496WMcAWluEFUFrEBEtwlUShyDiCQtP+oNaKqsopcFx2FPmCBDJNORP/RR3q4AR9TTBsuIZFi44nae6PcdISNBcmoNpdsPks2m+SNxvruF8B/HzAxIeMPCnYem6r1aR4AAAAASUVORK5CYII=",
    portohive = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAAC2qWaSOzvPy8g8lDzCtG5Plk2cWlrMxrWrq4vIr55sbWypyaetrappZi2dkVdCkD2XPUD///+EfEpockU9kUCOhFGJQjmZmpRvVjeuczmvr2t1b0X//wCwcnCxsbFgGxBqZDq2wLb//3HpqlXNwHN4LCl/gn+zfYCqqgC//7++wsDMmZnBv7j//6rLwbkPUYAAAAAAMHRSTlMA/P7+/v79/P38+Q36mRmg/v8BYf3+Zv9l/wQDTQEJBBBEvAIE/vla/wME6AVsA2e73wviAAACWUlEQVR42s2WiZKjIBCGQYPRoOCROJnommNmdmf2fP+32+YQieCRqdqq/a0kHvn8G2hoEPpfdKGUneCgl0coxn4PF6+MruW+KLoSYtadFY4Vx0acX9cwJUItx0RqYMHYb1pSpTO4cYvo9YbBtSzLGccKuxiI4Ho20O6Y7BKpnZY6i+HI/vw6ZkLH/t8UUbi8ZbdbmsYhHFrhhHYA9OCPMLUEhhgnWu/be+23FojSJMrzyCiXivbPT4GjrzZIYwA3eX7YHEBwshHK989BUBT33DawwWOYgI3xg48ApaMBtXlhgWcJbhx5QxXgcQ04RFoIafD8WccBxPlKcCvBnzqvs9BjaDqnGIMZKi3w4IC5ciyCWXAYPk0dIhVqoQZE9kwAmWOB3xWYKxCcTQbtn2SWjRyTzMzdLI0OfSut1NtLcAhVZ6sAqZrzGeSqpcTkuphTiclvPddCDcInC2N7doQLshzDhzS08Vv6EEettSeL12kXJ6PludXLTCKn/4Tg0a4dL6ccrxJ3aklNFhD5nHCnXDD9hJDZN9Dxkv4CS/EKtchTuvhbb+k1JSpQp4ZAzcCLrSTYrT7LnGIdQ+/f3KBJNQJbPJQpcsfYMARbexynhsLuLscR1TMNszjO1pbUUcb5qmrLTWZNqZooyEuJjpB3F9C44CiNIDE9+ujz3D8vxE8FL/cZXsU4kcnhIJCqr/42TvaNfl2Luok2koU8ndwh8b4/3IgJnmhiP5acY99wwn22vHlE16qqQeq7rthlcfPZsRd/O8qGLTuKXfXp1DQdfHdd15zoCujf6y85FzCmG7ZTfgAAAABJRU5ErkJggg==",
    pulsar = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUNIgsRpQqqqgATawvc2gFWUwCkqAASGAkGVgIIqwMMowS4ugDR0wANHBkPHgwO2gMbYAsJAl8dcAsQogbQ0QDFxwAS0wBsbQNv2wOmpwgTBUReYAVV/wAAAAABAAABAAABAAAE2gIA/wD//wD7/AACAQHW1wACBAED5AIJ+wUQyAgA1gB/fwAAfQACAAAMOgBFDPgVAAAAMHRSTlPn+hf23htZHCsMZaObcLDfZhKapBNYBm/n7O2vAwAwTXH5AgL+jPb/9vr6swIFqAesybq9AAAB6ElEQVR42s2WfY+jIBDGQW21Wm237b7d3QygYq3dbb//t9uB9jaXnK7A5pLjD9GEX+Z5mHGAQeBg/yH44AsKKYTUTHtGlAIR6SkYe/AA8RZHCHpllTuI8o9JonYF7xzIqw37+T0L3ta9k8dfmQGtZAdQoOVA7nYAVxQwGnIMtM90G2/UPieLRjw6gHZRAzlXauBxedEUc0TrBIiSxYwdGY+ZSajULqAQmrCBs+OR9bw0VVdecB7UZtGKn/iRBudVBlj+0JDOghdpxO6G3kaMWUm77OaRQMSKnxSP1cCym3yXdBg7dRrzE41YP6WfqXUqAEy3fBj2FRWCcwHYCjDwdnsnRgKOg2jAw+F31ToXuSmzFNZtJOQkN/EjCyHSpH2Wtxbi0zqE/pm8VraMhF/PwdeO2YR6tscI1snz1b+vvsEiaR8DGnIEy66LaPIFG3hsiwUF9j8CirYIODvIYkEWG2+wgajrll8qnQKXbbIIAIHA9ddKJ0CyGALeLR5CQGMxCpA6b3ECLALBq7EYBYCLpJvJ4ihI6U+SOaUjYA3Z5uXlval9wRXslVIZzd4Rz0ptoA6QulH92R9cQUZK8zmlf4NPkCvVZ/aw8QLJYq/6gGsngad+fm/GwPx8zgPAb9yQV3UdBv7jy/wHJQdcgn5sBNEAAAAASUVORK5CYII=",
    rake = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEXT0tehoaRhXmIaGBlgXWCmp6hJSEmqqq7KyspSUFGysLM9Oz1CP0IqKCq/vsM+PEBAPDxAPD5BPz9fP19CP0J/f4yZmcy9vcD/AP/AvsTDw8cAAABXVFfJyM3////U09hNSk1LSEtPTE9/f39IRUdVVVU3NjepqatGQ0U6ODosLC04ODgsJik0NDNKR0m3trqeRr1XAAAAMHRSTlPsZCIc9B5Vjgah2peXROZ7N26QCNkUBZgB1LkA/PcB/M2w8QKWA1EGdWoyDhIxLq7T7Er5AAACCklEQVR42rWWaXMaMQyGvSeEkKRNekvW+tiDPfn//64ybaYUSLCYVh+WYcbPvLL02paCG0PFL+3WdBvIQbeAlCbHpEBRVfuUvBQkWFWVTmAtBD2kWlc/1kRCkFKltU6hE+5xDQkLrv4kGgkSFKrSGry0j0W2V1olIDUAQVLpai+2HEH3yIkWRGJwpR5PEo0BuTKc6Kb4qzQxYAMbbsWp4HXQ/64MCc+jp+A1XUAhBAn27LXVmeA18EvwmlafycvABpbgteTI3HEg+a+KW3GBex/sDonqRXrL+a5TbO6V9HpsCkg40e/+vKTvglzHkjt47pmrim2OG/YMUTwYmjYbDJGn3JNIMCycLf4KC17wdiw1vsbd5R1eAP0xJgHTps7R3QAS1O5I0ca/j8eJRoPfDl24d3LFEtG1D3LFHaLJZv44CTgGzkKKWIN5LWwE2AWuhjTnxbvc9AcyN1fBBkqH99DY3EwZ4lKi3aKp+2tgQx8cfspgi24Ay8p3OGT4EDPnjLaeoEXXh8+4oKUdwlu+Oa1q5lhrMtjzLkuu0FtH4wx8RpdxjQyMzszAv7FgSHQwOECZ1/yvjgZ3bTCBfWHDtjBgLxgC08zmLUyh8T0rx4J+ZLfaketah2MyScbO8WkG2DrO2Tj5vOoMN9AYOdh/hC5jA94wITeQmVYONuFuHaZ/NJPHv1bwXxR/Ah64SrO2xHP5AAAAAElFTkSuQmCC",
    redclayplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAACwSzTiVDM2NTXWVTaROibqY0RPNC6TRjVuOzApKSk1NTWtUDo0NDQ2NjY6OjrCTjJ4QTYrKispJyc3Li00NDL///8tLCxVVVUXGRccGxrlXkEjJCN/f3/TY0rqYD6yVkMwLi41MzPTX0YnHR0hHBwvLy8PBwcdHR0eIx4wMDCiPykAAAAAAAAAAAAAAAD7XXwzAAAAMHRSTlMA///7//7/+/79Bsv+tYUE//5xVPp0AYsDEi3/MAL///28Ov8ZNMIgTTNP/wAAAAATnIyXAAACs0lEQVR42q2WiXKjMAyGfcixCXc4crbJbrr3+7/fSpgbG7Kd/dMZzJQPyZIsxNh/VbqfKn0BSWv3P97SVapdVEmVDMK7TZQdkjiOQzlXGMfFCnUMW0RrHaDy3BiDV23h0MPewgYJTPR4PN/fd60AIEJcl8ReXE5KWQbm0QNWT+RACAFgGsM3F6ejhrre6TmADDJulVmWB0ieZ27GaA4xcbUMnyuDnbgDkocJdwkb7ooM94l84VJ+H6ePxVKb5044LA0C9Ae0jEfgnoUyuG5wFgwmmyTQCBCwxQmRS3mZgbAOInfHdy9BZQPuoYDShA8IU8pvsz0SiKnIpvvMMIUNRbnFn5FuUIhrU2Od6NZSgmoABC/nrmp6H2k3lxgLE5lM603zFmy1QJqdiAjrlZ1GpJRcbGsJ/pCYyG0OyNW5xQBeMEhRPU6qfBSdNZGn07NcoK+w7eryQJ4lxXWD4wYNFo4GAOvmOIHhedHhZGkAfJA94Fipx0XP+cCyiyDri60DYFS/uXSALMFmNdQ2aXFKKDbzPZ5YhYHl61J62nMsWGyCSmFr/TL3dE+Nzkt4wTf2FatOjR4d1kbZu4bzgP2rlepRNUgvg9OAHWmhlqQbYy8U1IPjG9eSvbHm2nKc/1GUxvjMnKS2jhkejbzs9hoF5Ojys/zWfAgW8VS8LwuqVMeEsK+x0E20ksfph2NQfaZy9XPGB6bUB/inwONq1WG/iZlnCpIekxhmYzAbFfPMOnSaHbs0ynrqB8mk4V3+KXftGldoMLxNeuq09ZR5ZAbQGkPMUL0lXoPsw7lLY2ccealXZjkp80fU7TNqgtKNZL/WhsBbP8nleY5TnNbdGFisjqsn9ls6FMY/t0fdA86dcY/gOjkUr8/Wt6Sq6K9F6hdma3bC0A3Rq2luTl+3eHp9iv9X/QXRISjDNoauuAAAAABJRU5ErkJggg==",
    redguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWEDwphExGcEA+bHBoYDQ4RDhJsAABqFhQ0EhIoCwldGRyqAADlHRUAAAAREhS4FxHEFxEYCgsrCAhICwtVFhOqJSSSIx3/AABRCAdsDQqrFA6tIRpsGReTJCOOHBgLBggLCgx6IyNlCgl3DgqXEg0KCgsPCw2MDQwQDA47BwNqFRJvIRw4ExCQEgswBQV3FxJPslKdAAAAMHRSTlN0XLDbpdYI7iJsowP/AP75/vz9/v3+/gEpUdH+/f76M2z+NmivSI+QsCVS/PuLFY9jpk3TAAAB8klEQVR42u3WW3OqMBAAYNRWe84pbriFcAtUQBCr/v9/d5KALSSBQjvTJ+OLw8w3u7ntxjC/OYwHfEB5+Oz3k4hplmVlugCegtXqJU2z5z0b9TEryzJNJ6FIkNwopbFr25a17426PjLs+74K+ScS3DZJErsOc/v9QFr202hEEhQQYRbNsnrh2r+W7exuTXMgVwWe8hCA0p1jDyJ14WwnxsBGmEvw5RICgog68uTaoLabbLhDKJAggVcE4L2NxHOxBwKGRIYhcwJqnBMnHiAB19vZkE8viaCFYJjzobNLRJ6IZ9rMhnxdPL4qiMOCyPDAINJDB3/Ci3IADjAOaSRgO0V/Poy7VJnbHEahPQmLkxbCCPQE5JnmpnaOAMlZOTg9iCAwlWsVCIhjFTq020Rx3vQwwu4UhMo0tyqEKXjPVJ3jBMQgVnyY6cyI7c0ozGURabcZaN2vt19Dl97XxlgIcQcLooP5OEygXZ1KWx4FhCmIci1cjUFbpCrvYi8iv6leokB2VFsIH/VNKh1VtS42Whi1sBptOtdT81epxneIIJ9sc2ltSTX8/Rzdz9tkf0yz4/HpeQCxet7GOnKZcWx9RIRBffuilbNGXvPdeD97fMHDYMmrI2Wh/6wao1rzMvWN5woxwst1MeRt3/+3fbzlfgP+B5h6uDuPJSe4AAAAAElFTkSuQmCC",
    redportohive = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWWXyhdGRAsDQZyYC2SHA2bizRjZh5nCgNKGRJOExAuCgqWPEBYVxdkZAlQjEI7lUGma0C5iEQ2Cgj/AAAmcBdodkT//wA5DgtVqlWqqgD///9LgiuqVQCqqlX//3+qAACq/1X/fwAAAACMCAyVPDt0Cw47ljtxExKMRC5QijKphzdFkziWZixUDAtxhy2qeDasPtTjAAAAMHRSTlP+7B/2/vygBWmeX/9kA/////6ZAQz/AekDAwHVAwMCAwMCAP7//f78//r8/v76/f1XCXyhAAACzUlEQVR42s2W63LaMBCFJRnbkoCSGpqUNElbQ5AvGL//23V3JRnbyBCaPzlAmCHz6aylvYjl/yn2tUAhUhD8/YTj+h5Qa50ppaTW4g5HnfGmad5JpuEqEx8CddZwR1nUvDdK53l6A8ys2a4TsVyJMxkEtY1xNxSiaUeGQPEU4gjlwu/vJSgw0BE4A+G3MWo6VALNkPQgkPpaqE13EONgjZFXQP3Ez2fYyT3kGHz+8/b2+rrdLi2HJOyiGcHwk5hyFJkLdPiYLgtgc9IzuMwXCWoBSiJOMqQ+SD9wOI9lB4p8cUJFoBMDHZ2YE26qW4pzfXbc5IvS6uQUo6pOLcgvwiJJngj+zJO6rOu67OkUWeMHUIvsd1SFb0bRevBwOODHqS6//Yj2hZN1wmXAuYqZxA3qgU4rBOsyivZnFfgpcCXWxkzlL/44+qC1RMeQijY+Sh/qcwgcOO7nc3jP5w97VsVJLwFugt6vIPDRgptc/LoNgp8FqyTfWnCZi/LDjkcElwPH1Wo1AIsiCMbxgtKVHDflGIRNLXBHLkgWwzP+9Y6L8mDBegTOA6fBepuDqUoZV6M6MHyMkDgvPlRbHCebpcQi6Mm+LSROJPw5YjlGVFI9PIooTceOACaDDgCjDIoYeCoowCGn2QWJiVMlodYheITlBLXQQjW1VBKM+SqBXCfwMdBzMmoas9kea6nFQqziuMcfp0DBfWMDemYLEYoQ6pciOFKqrkNdTihOTbHfw+0KaB/DS001ZEXtdNTBLY0t4CjDYJorjq0Ygw0MK86nR4DiXTvuGc/wBcNKTE8r1SH+23SS03eANTzj5ZhyfdzI6VGerulEdiFdBSFz5RQJg/z5yq0jteQlOgPD39euKylkgTEjFp+yF2h4IsO/paLp5PaVtobL2zcrTEbhWDfdlLzjEiiElnAHlPKuS+Doprm+776aCrznfuqi+wXAf3djgAp/jbliAAAAAElFTkSuQmCC",
    rileyguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWXFQ2rJRLOHxZuEgxWDgV4EAqsTxbEYyyMEQzMl0QvAgS9iDLHhzaRWB/TGRd5CwCiERGqVQCKbir/PwD//3////8AAACvFg7HGROUEg20mTL/AAC0pS6QDQh+AACuIwVQCQetFg2NEQ3FojhpCwisFQvDaSbFmTiZAACPCgewVxkwBASMEgexAAC5aSdaCwdshXUNAAAAMHRSTlOj+vdUI5j0+2b7Jv3+mlr4LAN9BAIBAPz9+/0B//sC/TFbzv9o0v//BdD5EpMD+07W02w7AAACUklEQVR42u2W63KbMBCFxc1gfEnbpBJC5lICIQSw3//tupKMEEYGJzP91ZwZe+wZPs7RarWA8BeFvsF/CPbvfd+/D3pmjH3ZkT0GBn90HY/HHyvkAHqEK4rkt23bKFwmVVRENEUgO3jEkeG8uAUj9FBVcXlrGUXIvV8jNNawm5NVwG+5vMYUh8UMBNN0dR8ZdqiBrFzM0uUGYKawsrrpcucwdxLWVnFzQ4km4HxPrnGd1V51BEJvSVLeAd22dd08v1w8QoyePK4JLJuiKChXIi6/AfkvHvcnL9O1xkitjUpdL7cnXAb/qg7jl9/z00GpIjlh2+MCff+Da8M7ENRqILiXlNCp6aDsbVvXcRzv9ptfh8MBdS2/Hg0Nhy8FNZMAvp5OpzjeAr31bXLRQMz4Qgcw0StKsreaY1Jbn1S5DsrcEhOmOigNhc4ZcUQfTRugpJrpGHUEdxtSGTtHLTQZSQkKcqsMZ+ORk4kA6bBQosCdb5HO3Ks9Dj1pmKjijuB+k1UuMw9kl/dCkui9oMDd2YqCu5Oc4dZ5ekqEaSJMh+LUvpVB87CFR4BnJVcBqLZj/6EqYwZT7FgQ07Is+EDa7PwqDKGi3Th/DCBrkQCG85WdeafWfAvzcfqYogbaWZSOwNUQNNBmD5o/3LqbsUHO0ORQGYL0mTUHc3IdAMORzPx9XO8hqKOPyVnUtC0pmcrawCnmlUlXnsil5zVNIzaDh5Z0VuWPPMrDMC/LEqGmkbegxHY+/dYRXhy4BWofBFNQv/DuseqY8luw+evL90vgfw7+Bc4JGEFgO1faAAAAAElFTkSuQmCC",
    scissors = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUOZHGxKkORk51pam0DZmgVKCxjEBcNWWSFh5CbJTqjJjyenp8KT1r///9hYmgQMV1xHCr5CwuVLDQA///3EXgQdIJvcHd6fIR0eoZ9g4qQITaqCFXCL0p1hY+dncr/dHQAqqp/f6iZZHIAAP9qAGoLPkYAf/8Aqv9Dcn16fYR+gIeoKkCTW2v/AP8AAACHiJF0ypxoAAAAMHRSTlPy9fURDBQUpo6k3QZjAVMSXQEbAQP/lpbpqmkD//AGAgQI9gECRQID+WxvlpYBAPf0jh69AAACWElEQVR42s3W15aiQBAAUDpLS1DMaR2d2bxb/P/fbVWBKxOQpp+mHwycc61A0XYCkSv58Gp1sHEQV748VNaOhHZ/E/ORUHifpul+NjqiEMfjUeCawSEczmEm/Cz1HqEFGw4tpBgJ360Xnct6EC5BCEMfjBD37nyDcrjGFliRQvU/nnkd8z18oRIxLJU6u5WoIUsy+P4QWthjJMulWri7JHGPI87b3iwBe/OXLz2xY1n2wzOWaC3VyBlTk8hl2qE0sOiDlnuDgc+WMyanmzRRJvom38ED9aYiQL3hu2HYYU8p4a/9EVOcGBzVvW97w07rttSsD75AlaZe8KhajuOwtIWmj5rc4tHzaKs9xvVY3QLcKimBXUmu7J+cw5leCVruiNPNzDQpPxy5uV1WvxlikHtVmPLT88DWccaI3t/uO42pcUOT0+w48Od6vbqkWZhs+cb1QrWTJ3kilZlk5bRbuaGng9cUJrKu6x8UDLNcUV8WAREVqNMJYU3lUX0r9+Zx7ItYyG2yreuCHweUmQnYOnKANeaJTrWPkX6/5XwAc1CS6sNFvxG8r16gqFtXmxH/HQodLjnZyVEQ24lA1r/4dqhgmDdug55gOSIiOwNfOGJoqjkYqg9v3rSZHB0GuT45MfQLDLdh/8iK79+mM6vrIKhys5OyQHKD+CUAqinsKE3ViajgeRDmCnbUFQWvYEiqazkl3oFrEwDVenPpjjTBIuScU3bSvMN8/AGJoAI1HuLI1bFwayLhJOoQeCE4hZjmbH6CioJFEQVzKFQUxH2/jDwhRx+tPx/8B44C4xe4td57AAAAAElFTkSuQmCC",
    scythe = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAAC2AQFok83HAgClmaVyAAD4AADetaD45Y7Y2AOkBACuBAGXAgP//wD///96dnn84XhybwhshrekqABVYKCYdmOmpAC0tgP0sHdMb5+gbWSfngKSpcrUmXgSFmKweGOTRmJpAAB7egJYc6Runs6kpKT/fwD/pKRgYmt1eaphjMqYMkmwhGS0gmajj4e7xAZh8l7aAAAAMHRSTlMA+Pn69hAC+Pv5D6dfAQEH+RbxDxVfn9T7bxJq/50Ilv5JTpsFAwIDUf+z/3iUZadThZVJAAAB2UlEQVR42s2VW3OCMBCFl9yAEJCbCrZarbbeWv3//667KepTKctDp+chE2b4PGeXZAX4T9pnf+uXwXI6Gef58gnjwGm0hLcRScMIQbYWCObNEvZMzmCFTRRNYcHj3mGxbHIC2TV+hMhFBUxYFL2dEzgFLvfS5ER+cGvsuBwyOxxKV4vPRqkwjEJFUYeieDyVKoUQfgWHn0Yjbc0vP1BncCBMPKMQDBJCzZC+bIXn6EmUgZQe3SS09h3QWnyLalRiLYPAs7gGPdyq45Si5oRheVwHJOlX3Ud2fiWBvjvHc4f1gZMa3zy17VbdOVRw0+bHhkJ7av2OckZRiN1BnW9gAr3N3dV1dkBHdaGnthTrB9hT5W7VTY0Lfphsh7vtHQzADLkdkE38zt05N+Tcve1vkyC5NdX+bviQBS2/Qek43MNQoqFmzR4CyZRnWEB1jcEleFSt4Rim8BTPaeMsa4CkUMXxK1gKqXngLJ5VKVLW8GaWD1rw/z+KOH6Cio/BPJ5hXK4qH5Sfs0oL6ihfvqMjOB+0SNkVvoMPyuY0FFfqKL+lLoF5xW+pwdvLvYD32yuZF8kX6NBQarBMzgeVCRh2UKAK2Rwm1QkF1SOODWzcKE4bGOdHowL+ob4Af3IXvD5jFoEAAAAASUVORK5CYII=",
    sparkstaff = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUrIAZtXCBbKhArGBBeWAdjWg8pFhJiIjhGAEhlWwY0BTBIPAhALhBcJFL//wAAAH8+A0F/AH9JBkJwRUuqVQCCeyT/AP///38AAAA1ATUsAS4tJwFTAFMYGAAuADBORQAsAC8xATQyADUtJQM7OQBEPAJzZzMRABJQRgRXVQYPAA87NAV/AAB/fwAYBRAQAC5160O/AAAAMHRSTlMm6AujapRR62Qr2UWQ7AEC/wKp/wP/AQIACnUwAw9OUjCQrA4HNvpzKwctRwICSAm93QX+AAABUUlEQVR42t2Wx3LDMAxESYqU3J0ekFRvliyX//+7MMkxccHeEszoJL1ZErNaQBBY4q+DDQi2AlX0MNh9v8y44NzQC1EnOIqjGgPiPY3acI+6aScvFMmCAQpf6PB9s/I0L1oGmKmhkFq0y1Udsbs6TD5ePCxiLrgJj3V1larmyPdqS08zOpPKDkyv+mE2090QfJAx/47CrKWUcdaRYoBiWZjX57XsezO8cxQbpQOUSGnmvOYcSfe9TJJgPlZzMjFpMwmRWDpC0RGdgMz5kopaLKzGa5JX02UfofG424PgKSKLBfJlyVvgDgT3IJiSi8GhUzoLgZaqHBxzlyRvgZbqEhyspXsDJ3KNjvLcgeC5BsHHIGmhrcPWwULQuvKb5B3glsoKAkO5HDpqSnn145Z3KabnYPUUAC05h90xtVUJgZ+SCgEPJKIG2lcP5LN/tlrfUR9/ZiWhbSCqEAAAAABJRU5ErkJggg==",
    superscooper = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVZVVjb2gUAAGsqKSZqagKvrwVgXWBLSEmlpQEAAJ8NDaoJCc8uL6pLSEmmpg4AAKxNTovKzQCrqy0AANkAAM+oIRqOjk7NzQDS0gD///8FBclXPVeTGxQeHl9VDwCtXhk/PT9SEU9BPk5/KqpCDZJIRDSqVVXakQDGvgAAAAABANfY2AEAAOzn5wAAAP///wD+jrGIAAAAMHRSTlPl5xMcFw4LYWRfod7xoo0R6K/1aar9/AVrATIepEYJ3nhXuAb/cAMHegD7+/z7AgE1bipJAAAB8UlEQVR42r2W15LbMAxFwaLebbnFW9ITSCT1/38XqNgvK+8SmtngQW3mDMAL8IqAGwPWPgZ6I7g5Y6yHU/BB2hVwQFHOT6Fz4006X7DvRVPGml9q31vb06Vuk0RKmSYovUA1UmPkpjOm60yKlQeoUd/Bbo7ECwwwXjjRsUCN5czZ3Q2UXms8YWPfgD6qUhsX8GgWEH3BfguoUd1AuIPOAwxQL6LaegEzL/CE8TQ2vbiBJvPMGDdCEGYFLJWmK91Yn1UdnM9/m9fDT0MxTpz03B1zPB2+7ZMkzWhwPHfHoINg+HN5OryMb1XFsg73gzK+OLfBc8LXg5rkdAzQ4Zd9nndtxXU5h/tJz9V98QHYQd1l5pkJXrCkLbKDmp444ICqEWRYVtyb6gtqAnfHnguSB6d5nhkoaXQ5IHXDTL7YouOCWQ7kqRkTHDDYCXuEOnnYjUdrjMX0G4iZaxxBUlXYkg3KFMCkpebOquwmVVvJAx1WbUZt7IzkinPSsT1m6Z75Y6VujJ4smvPjiXsEToYsLBOkUoOzqPMyZoNkrXGabDgghcPz9+KX5oO/MQIAtSEjFgDFlrNcBNcCwg0ZKZ2CiAteEGCqlp3x6/RVvasOrAgTQRFelcJ35XkLXkdFl2CWqpSK5lD/62gdhpQ0pPiMw/w/Na3UFHoC7iAAAAAASUVORK5CYII=",
    tackyplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWWppkzMzOqw4zgzhAZY97X4uLqnRwsLCzMpFmsqW1aYVgtLCy6zM5tmqo1NDTQzV/wNwRubm7M0Z1slGzeViNPh8ZYUjWLZ5lib6AxOlJId8iotTXUd0S0xXU7QTc2YbCTb2Ovt85EOC23wDkeZWU+SERBPTzEt5v///88PEs+PkA/gdpAPjyaez3BsswAAABDP4+BAAAAMHRSTlP+9f////7/D/7++13//pz//wP//v7/+//+/P///v/9/v//+f8J+YD/ARF+/37//wDHINMiAAADoElEQVR42p2XiXbiMAxFhbN4iU02IOyUdrrM2v//u5Fkh4SQQGd0Ttvg+PpJsmxU+PxPg4nxUvbsi6CU5e3QQ7CFZPYjm6O9vf2aZzzwUFFm2Xw2n12ZZ++BWUsYMiAzxrPyDph5BmcnPbPgmJVTYOapDrAkaPkZzJBswfKTnDReYWiM4ut+hi6K86AGY0YkasqPWzDzcgB3wc9yCMq7HINrzGzP1wCWsyNgNuwYxempwGwQLG9Bw+CQtSHDeRQ9TSjO1lChJSNmax1FkZ4CG0jxdV4lrUryBz3M8yh3dU1vXsddnUFCYFRZqA80PYF1c0YXo5daCAINlp0c2Q5HgUS0PrzQAzTQNPSwc5ZeHXA/ss7XDjQefKmtf3hqsIbYCWEtjuzMVZA3YCQSyw+aYmUfEnum7JjZ8zhoq8gH6UFMcNDGwiBwNeXqOWnBKih6MAUPmqvz0YJYc2CvwB0Ga0O0TVAcBx3sgouaQ6udFTzy3jSQ53QiR86jnM9egZVUAk8Mito5Bu15u3WCzvK8uwChd/4NkGca1w8+11RrOcRkW6E5O+UQpIMVx+gSbnyVc/FVohaHg3Bx/BPJtUqfe1H2FWGJpMAzIYRKyZTGT4JGgUmWvE2OEfh6KRATQCD9aEGDsf+9hmMn2QNxEi7uRBDU4bej1fhPvDS34HcEQdG66KwmPeFJhYRTiz17e6JbYKh4BFUolvQcGT6pLa6limKv9CmONxfJruRWsCgWLOld1JQanSryFMGFSvVyFDQKwXd0bE0c4OQFZQnIBw+mwo2C+6IoFOVHczL3OBcThStphWvuCdRd2V0rIogKJ8yPoE9I4kJbDBTDp7jrbiO75PgYDypsJnpXFJrWccSoFhxuxzcsHIUKmMc1RcXggrfP8a5QgoWZKADNO+g30zvO9SZCHU2BRnGpKV8rYk+Crd++dGEEpI1MteYdJEncAkqNY7dD0au6943eA5/bshbeWdzLUIKB1KZ3IPvncRVKjTcvpuneaQiaq34L0X2V44H8jWEAT+SaFbBtBXGYLoDe/XgBS5LUfnURwoRWEDluH7qbo3O19LeOJ4Oz4XiSFwO9frsiqX8gTWDW8RXVesqNTjbadWDxSOp0auFDau82OpX1LTdoyYg0NVzCpFPdtWTlnV5O0pyjqTUa1uzJrEJvlz3sV7OuZ9xsppvHsUYX207qO+eByXzOH4KyvwBDH6X8amstJz58pZn3jPz3/wIe2l9YehszJ6kM4AAAAABJRU5ErkJggg==",
    tidepopper = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVaoKZh1eui7e0qWmJRZWVSnaxUuM3b19alpaWa5OjY7u8SKSxUs8l50u2T0dGR290tZnY8h5hty9nb2dk/v79OsMLc3t48eaJHp75hsOwzzP9VqlV2wci0tLSExrwAAAD///9k1u0Af39Qu9Cs/v6V9Plt6Pz6/f1YwtcA//9///9mydlq6v5Gmq1/f39MpruchNkrAAAAMHRSTlMd7BgeDGeclRfn4hDgC1eYQl6iJgRzXxz+BQUDdEsbAAH3Avr9/c/7+gED+/6FAm3CtxOoAAABh0lEQVR42tXWV2+DMBAAYNsMswLZo+vOLENCwv//dzWkfYpI43uI0hNIYOnDdx7IDIjBXgk6LhU6JJjDjgYZ9Oy5cA3+k+EbLGlwBrX3dNhT4YYEBdQ+CR6BU2HNqVCRYUwaHKw7B0kbue4oqcYiVd2HcKG1gheIs7KqytAB17JHdJdVdW9/sMn2mPPFZKLTcH3xVOcHR2t4wI3quJkU++noB2hZYwtCpMuOKy8VVvAIrIrMdFRllAFapeqmWWhgmDJLaCJpins7cgLORN8URdN4FtC9VunzwtBIHh9MFWUUQGAeBtgUoXysRoSV1nJIdVOM0WRfpjGQn2bd3+8xkNHWtJalOg2hypCBK/VPGtMQrzWySOtyjDATyAxcIf5R43jFUuuQhyd1cob3YLu6KfVmVPEy3Futk/0+SeYgLr8ffGzlrDyuGsXjMXNEtFg5i4Qni9h6P+IBPOUR/gCwaz11bnN7+A4LfgYCzMFRRDj/N7B1zHQQoFlkvkM7r+bkozW2L3WY/wYQI3D1zIetEQAAAABJRU5ErkJggg==",
    vacuum = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVrZ2NcUDofIyaRk54hIydnZ2odKC1SRTldVVFEOi+WmVMUHydlIR5hYBpRRDpRU1ubpi3Q1UV8fYQ0PERJPDH///85O0Q7PUcAAP8Uamw8Qkmqqqo9QEmhoV25xCz//380Qys/RU97hip/goiqVVWAfYWMjpn//wDCyDEAAABkVUYXIy1TUleJi5NVTUlUV2HSl79BAAAAMHRSTlP1+Bb8WBHrnaJh/5kWDF9d///u/5ABYIsBE/8DXgT/Av+x//8D/74B/wD9/P3++/6xQms4AAACKklEQVR42p3WiXKjMAwGYMsYcxdyN7132z1wjHj/t1sZOzRDsrFB05mm0/nyG1kGWLuw2P1/x4/L4DPRZYl8wLMhT6PfcbubD+OIql6QWEcdVTwXPlJi1627egk0ck4ir6oqpoq6aB3vXp9f39s/M68xSmftY5Y8JGmSMIIstZWFwAqUKewMVLa2IZAjKa00wY7RlyD9EQZdSkddPSdm86BNtHAXCoGZRMtQPUzOyb1EFo1QqSoMaspQZjd+KVCgNYOyrcKXSonUG40ACsu2DF7q0Bu3UuAzunoJk0BIVwgW0hzQj0qCZlWY5jgIiOYaAyG72v8wmA27qMx9Qzk43f87ECfwKxSCheoMywC4tRNH7vM7kXth2SYjXDuIgVCDNofDQHc6yoDmVJQIgANktIsa0EycH8YEEbSDwwAoCLnLxS2M12gSlb4xODe7ykWWZcl2gP8bnCtIvdsjsh+HvUgNFHR3pfC0fb8PY3omaqq+7zUzo3qoXwQV9yYeWa9tYc8Y600h3c1fPHCvz85QtL/JstQDDz2OzoSNn+vpE30ChUaW5znT32G2as8ACCnZarXKL1c6dEr44ElC07zBZvNkXG7TUaPwDDk/kYQG5IlKbnKX3m8CoBEnV/DW/G2eKFyGwbHgZ9PA8FXcsx0TSOLDrto3OZyLQp6uq2iP/tNBWMgrGPQIcNEXUARDt62FlLd743tfHY51URTzX3T5cdkbssUL4eLE2/UPbtnJbqND0+4AAAAASUVORK5CYII=",
}

-- decodeBase64 defined above

local ICON_DIR = "AutoFeedBSS/icons"
local routeIconCache = {}

-- tra ve asset cua icon gear (nil neu khong co anh hoac executor khong ho tro)
local function getRouteIcon(key)
    local cached = routeIconCache[key]
    if cached ~= nil then return cached or nil end
    local asset = false
    local b64 = ROUTE_ICON_B64[key]
    if b64 and getcustomasset and isfile and writefile then
        pcall(function()
            if makefolder and isfolder then
                if not isfolder("AutoFeedBSS") then makefolder("AutoFeedBSS") end
                if not isfolder(ICON_DIR) then makefolder(ICON_DIR) end
            end
        end)
        local path = ICON_DIR .. "/" .. key .. ".png"
        if not isfile(path) then
            pcall(writefile, path, decodeBase64(b64))
        end
        local ok, res = pcall(getcustomasset, path)
        if ok and res then asset = res end
    end
    routeIconCache[key] = asset
    return asset or nil
end

local Progression = (function()
    local autoProgressionEnabled = true
    local autoFieldSwitchEnabled = true
    local autoHuntViciousEnabled = true
    local showProgressionHud = false
    local progTargetLabel = nil
    local gearListRoot = nil
    local gearListGrid = nil
    local gearProgressLabel = nil
    local gearProgressText = nil
    local gearProgressFill = nil
    local gearHideOwned = false
    local gearListMounted = false
    local openGearListFn = nil
    local routePills = {}

-- bo nil ra khoi list (ipairs dung lai o nil dau tien)
local function dropNils(t, n)
    local out = {}
    for i = 1, n do
        local v = t[i]
        if v ~= nil and v ~= false then out[#out + 1] = v end
    end
    return out
end

-- Cong thuc Blender (cap nhat theo game 2026). Thu tu item quyet dinh field uu tien
-- khi thieu: dat nguyen lieu farm duoc len truoc de findMissingMaterial chon dung field.
local RECIPES = {
    ["Blue Extract"] = { { Item = "Blueberry", Amount = 50 }, { Item = "Royal Jelly", Amount = 10 } },
    ["Red Extract"] = { { Item = "Strawberry", Amount = 50 }, { Item = "Royal Jelly", Amount = 10 } },
    ["Oil"] = { { Item = "Sunflower Seed", Amount = 50 }, { Item = "Royal Jelly", Amount = 10 } },
    ["Enzymes"] = { { Item = "Pineapple", Amount = 50 }, { Item = "Royal Jelly", Amount = 10 } },
    ["Gumdrop"] = { { Item = "Strawberry", Amount = 3 }, { Item = "Blueberry", Amount = 3 }, { Item = "Pineapple", Amount = 3 } },
    ["Gumdrops"] = { { Item = "Strawberry", Amount = 3 }, { Item = "Blueberry", Amount = 3 }, { Item = "Pineapple", Amount = 3 } },
    ["Glue"] = { { Item = "Gumdrop", Amount = 50 }, { Item = "Royal Jelly", Amount = 10 } },
    ["Tropical Drink"] = { { Item = "Coconut", Amount = 10 }, { Item = "Enzymes", Amount = 2 }, { Item = "Oil", Amount = 2 } },
    ["Tropical Drinks"] = { { Item = "Coconut", Amount = 10 }, { Item = "Enzymes", Amount = 2 }, { Item = "Oil", Amount = 2 } },
    ["Soft Wax"] = { { Item = "Oil", Amount = 1 }, { Item = "Enzymes", Amount = 1 }, { Item = "Honeysuckle", Amount = 5 }, { Item = "Royal Jelly", Amount = 10 } },
    ["Hard Wax"] = { { Item = "Soft Wax", Amount = 3 }, { Item = "Enzymes", Amount = 3 }, { Item = "Bitterberry", Amount = 33 }, { Item = "Royal Jelly", Amount = 33 } },
    ["Purple Potion"] = { { Item = "Red Extract", Amount = 3 }, { Item = "Blue Extract", Amount = 3 }, { Item = "Glue", Amount = 3 }, { Item = "Neonberry", Amount = 3 } },
    ["Swirled Wax"] = { { Item = "Hard Wax", Amount = 3 }, { Item = "Soft Wax", Amount = 9 }, { Item = "Purple Potion", Amount = 6 }, { Item = "Royal Jelly", Amount = 3333 } },
    ["Caustic Wax"] = { { Item = "Hard Wax", Amount = 5 }, { Item = "Enzymes", Amount = 5 }, { Item = "Neonberry", Amount = 25 }, { Item = "Royal Jelly", Amount = 5252 } },
    ["Super Smoothie"] = { { Item = "Purple Potion", Amount = 3 }, { Item = "Tropical Drink", Amount = 6 }, { Item = "Neonberry", Amount = 3 }, { Item = "Star Jelly", Amount = 3 } }
}

local function getRecipe(itemName)
    if not itemName then return nil end
    if RECIPES[itemName] then return RECIPES[itemName] end
    local clean = tostring(itemName):gsub("[%s%-_']", ""):lower()
    for k, v in pairs(RECIPES) do
        if k:gsub("[%s%-_']", ""):lower() == clean then
            return v
        end
    end
    if clean:sub(-1) == "s" then
        local sing = clean:sub(1, -2)
        for k, v in pairs(RECIPES) do
            if k:gsub("[%s%-_']", ""):lower() == sing then
                return v
            end
        end
    end
    return nil
end


local TOOL_TIERS = {
    ["scooper"] = 1, ["rake"] = 2, ["clipper"] = 3, ["clippers"] = 3, ["magnet"] = 4, ["vacuum"] = 5,
    ["superscooper"] = 6, ["pulsar"] = 7, ["pulser"] = 7, ["electromagnet"] = 8, ["scissors"] = 9,
    ["honeydipper"] = 10, ["bubblewand"] = 11, ["scythe"] = 11, ["goldenrake"] = 12,
    ["porcelaindipper"] = 13, ["porcdipper"] = 13, ["pdipper"] = 13, ["petalwand"] = 14,
    ["tidepopper"] = 15, ["darkscythe"] = 15, ["gummyballer"] = 15
}

local BAG_TIERS = {
    ["pouch"] = 1, ["backpack"] = 2, ["jar"] = 3, ["canister"] = 4, ["jug"] = 5,
    ["megajug"] = 6, ["barrel"] = 7, ["compressor"] = 8, ["elitebarrel"] = 9,
    ["portohive"] = 10, ["blueportohive"] = 11, ["redportohive"] = 11,
    ["porcelainportohive"] = 12, ["coconutcanister"] = 13, ["cococanister"] = 13, ["cocanister"] = 13
}

local BOOTS_TIERS = {
    ["basicboots"] = 1, ["hikingboots"] = 2, ["cleanboots"] = 3,
    ["beekeepersboots"] = 4, ["beekeeperboots"] = 4, ["beekboots"] = 4,
    ["coconutclogs"] = 5, ["cococlogs"] = 5, ["clogs"] = 5, ["gummyboots"] = 6
}

local BELT_TIERS = {
    ["beltpocket"] = 1, ["utilitybelt"] = 2, ["beltbag"] = 3,
    ["mondobeltbag"] = 4, ["mondobelt"] = 4, ["honeycombbelt"] = 5, ["honeycomb"] = 5,
    ["petalbelt"] = 6, ["coconutbelt"] = 7, ["cocobelt"] = 7
}

local HAT_TIERS = {
    ["helmet"] = 1, ["propellerhat"] = 2, ["beekeepersmask"] = 3, ["beekeepermask"] = 3, ["beekmask"] = 3,
    ["honeymask"] = 4, ["bubblemask"] = 4, ["firemask"] = 4,
    ["gummymask"] = 5, ["demonmask"] = 5, ["diamondmask"] = 5, ["diamask"] = 5
}

local SPRINKLER_TIERS = {
    ["basicsprinkler"] = 1, ["silversoakers"] = 2, ["goldengushers"] = 3,
    ["diamonddrenchers"] = 4, ["thesupremesaturator"] = 5, ["supremesaturator"] = 5, ["saturator"] = 5
}

local BLUE_GUARD_TIERS = {
    ["lookerguard"] = 1,
    ["eliteblueguard"] = 2,
    ["buckoguard"] = 3,
    ["cobaltguard"] = 4
}

local RED_GUARD_TIERS = {
    ["braveguard"] = 1,
    ["eliteredguard"] = 2,
    ["rileyguard"] = 3,
    ["crimsonguard"] = 4
}

-- Route + cost nguyen lieu cap nhat theo game (placeVersion 1993 / wiki 09-2026).
-- Honey = tien honey bat buoc khi mua; Ingredients = nguyen lieu chinh (crafted/rare truoc, raw sau).
local DEFAULT_ROUTE = {
    { Bees = 0, Name = "Backpack", Type = "Bag", Honey = 5500 },
    { Bees = 0, Name = "Magnet", Type = "Tool", Honey = 5500 },
    { Bees = 0, Name = "Canister", Type = "Bag", Honey = 22000 },
    { Bees = 0, Name = "Vacuum", Type = "Tool", Honey = 14000 },
    { Bees = 3, Name = "Belt Pocket", Type = "Belt", Honey = 14000, Ingredients = { { Item = "Sunflower Seed", Amount = 10 } } },
    { Bees = 3, Name = "Basic Boots", Type = "Boots", Honey = 4400, Ingredients = { { Item = "Sunflower Seed", Amount = 3 }, { Item = "Blueberry", Amount = 3 } } },
    { Bees = 5, Name = "Compressor", Type = "Bag", Honey = 160000 },
    { Bees = 5, Name = "Super-Scooper", Type = "Tool", Honey = 40000 },
    { Bees = 5, Name = "Helmet", Type = "Hat", Honey = 30000, Ingredients = { { Item = "Moon Charm", Amount = 1 }, { Item = "Pineapple", Amount = 5 } } },
    { Bees = 10, Name = "Port-O-Hive", Type = "Bag", Honey = 1250000 },
    { Bees = 10, Name = "Mega-Jug", Type = "Bag", Honey = 50000 },
    { Bees = 10, Name = "Electro-Magnet", Type = "Tool", Honey = 300000 },
    { Bees = 10, Name = "Honey Dipper", Type = "Tool", Honey = 1500000 },
    { Bees = 10, Name = "Propeller Hat", Type = "Hat", Honey = 2500000, Ingredients = { { Item = "Gumdrop", Amount = 25 }, { Item = "Moon Charm", Amount = 5 }, { Item = "Pineapple", Amount = 100 } } },
    { Bees = 10, Name = "Looker Guard", Type = "Guard", Honey = 300000, Ingredients = { { Item = "Sunflower Seed", Amount = 25 } } },
    { Bees = 10, Name = "Brave Guard", Type = "Guard", Honey = 300000, Ingredients = { { Item = "Stinger", Amount = 3 } } },
    { Bees = 10, Name = "Hiking Boots", Type = "Boots", Honey = 2200000, Ingredients = { { Item = "Blueberry", Amount = 50 }, { Item = "Strawberry", Amount = 50 } } },
    { Bees = 12, Name = "Pulsar", Type = "Tool", Honey = 125000 },
    { Bees = 12, Name = "Belt Bag", Type = "Belt", Honey = 440000, Ingredients = { { Item = "Stinger", Amount = 3 }, { Item = "Pineapple", Amount = 50 }, { Item = "Sunflower Seed", Amount = 50 } } },
    { Bees = 15, Name = "Scissors", Type = "Tool", Honey = 850000 },
    { Bees = 15, Name = "Elite Barrel", Type = "Bag", Honey = 650000 },
    { Bees = 20, Name = "Bubble Wand", Type = "Tool", Honey = 3500000 },
    { Bees = 20, Name = "Basic Sprinkler", Type = "Sprinkler", Honey = 1111111 },
    { Bees = 0, Name = "Plastic Planter", Type = "Planter", Honey = 750000, Ingredients = { { Item = "Soft Wax", Amount = 1 }, { Item = "Magic Bean", Amount = 3 } } },
    { Bees = 20, Name = "Beekeeper's Mask", Type = "Hat", Honey = 20000000, Ingredients = { { Item = "Glue", Amount = 3 }, { Item = "Enzymes", Amount = 5 }, { Item = "Glitter", Amount = 1 } } },
    { Bees = 20, Name = "Beekeeper's Boots", Type = "Boots", Honey = 15000000, Ingredients = { { Item = "Blue Extract", Amount = 3 }, { Item = "Red Extract", Amount = 3 }, { Item = "Oil", Amount = 5 } } },
    { Bees = 25, Name = "Mondo Belt Bag", Type = "Belt", Honey = 12400000, Ingredients = { { Item = "Soft Wax", Amount = 1 }, { Item = "Stinger", Amount = 10 }, { Item = "Pineapple", Amount = 150 }, { Item = "Sunflower Seed", Amount = 150 } } },
    { Bees = 20, Name = "Blue Port-O-Hive", Type = "Bag", Honey = 12500000, Ingredients = { { Item = "Blue Extract", Amount = 2 }, { Item = "Soft Wax", Amount = 2 } } },
    { Bees = 20, Name = "Silver Soakers", Type = "Sprinkler", Honey = 22222222 },
    { Bees = 20, Name = "Elite Blue Guard", Type = "Guard", Honey = 5000000, Ingredients = { { Item = "Blue Extract", Amount = 3 }, { Item = "Royal Jelly", Amount = 5 }, { Item = "Moon Charm", Amount = 15 }, { Item = "Blueberry", Amount = 50 } } },
    { Bees = 20, Name = "Elite Red Guard", Type = "Guard", Honey = 5000000, Ingredients = { { Item = "Red Extract", Amount = 3 }, { Item = "Royal Jelly", Amount = 5 }, { Item = "Stinger", Amount = 5 }, { Item = "Strawberry", Amount = 50 } } },
    { Bees = 25, Name = "Bucko Guard", Type = "Guard", Honey = 30000000, Ingredients = { { Item = "Blue Extract", Amount = 10 }, { Item = "Glue", Amount = 5 }, { Item = "Moon Charm", Amount = 75 }, { Item = "Blueberry", Amount = 100 } } },
    { Bees = 25, Name = "Riley Guard", Type = "Guard", Honey = 30000000, Ingredients = { { Item = "Red Extract", Amount = 10 }, { Item = "Glue", Amount = 5 }, { Item = "Stinger", Amount = 25 }, { Item = "Strawberry", Amount = 100 } } },
    { Bees = 0, Name = "Candy Planter", Type = "Planter", Honey = 5000000, Ingredients = { { Item = "Soft Wax", Amount = 5 }, { Item = "Gumdrop", Amount = 30 }, { Item = "Jelly Beans", Amount = 3 }, { Item = "Magic Bean", Amount = 5 } } },
    { Bees = 25, Name = "Glider", Type = "Glider", Honey = 5000000 },
    { Bees = 25, Name = "Golden Rake", Type = "Tool", Honey = 20000000 },
    { Bees = 25, Name = "Porcelain Dipper", Type = "Tool", Honey = 150000000 },
    { Bees = 25, Name = "Porcelain Port-O-Hive", Type = "Bag", Honey = 250000000, Ingredients = { { Item = "Soft Wax", Amount = 3 }, { Item = "Glitter", Amount = 3 }, { Item = "Moon Charm", Amount = 10 } } },
    { Bees = 0, Name = "Blue Clay Planter", Type = "Planter", Honey = 10000000, Ingredients = { { Item = "Blue Extract", Amount = 15 }, { Item = "Soft Wax", Amount = 20 }, { Item = "Magic Bean", Amount = 5 } } },
    { Bees = 0, Name = "Red Clay Planter", Type = "Planter", Honey = 10000000, Ingredients = { { Item = "Red Extract", Amount = 15 }, { Item = "Soft Wax", Amount = 20 }, { Item = "Magic Bean", Amount = 5 } } },
    { Bees = 20, Name = "Bubble Mask", Type = "Hat", Honey = 100000000, Ingredients = { { Item = "Blue Extract", Amount = 50 }, { Item = "Oil", Amount = 25 }, { Item = "Glitter", Amount = 15 }, { Item = "Blueberry", Amount = 500 } } },
    { Bees = 20, Name = "Honey Mask", Type = "Hat", Honey = 100000000, Ingredients = { { Item = "Enzymes", Amount = 25 }, { Item = "Oil", Amount = 50 }, { Item = "Gold Egg", Amount = 5 }, { Item = "Treat", Amount = 9999 } } },
    { Bees = 20, Name = "Fire Mask", Type = "Hat", Honey = 100000000, Ingredients = { { Item = "Red Extract", Amount = 50 }, { Item = "Enzymes", Amount = 25 }, { Item = "Glue", Amount = 15 }, { Item = "Strawberry", Amount = 500 } } },
    { Bees = 20, Name = "Cobalt Guard", Type = "Guard", Honey = 200000000, Ingredients = { { Item = "Blue Extract", Amount = 100 }, { Item = "Enzymes", Amount = 50 }, { Item = "Glitter", Amount = 25 }, { Item = "Stinger", Amount = 100 } } },
    { Bees = 20, Name = "Crimson Guard", Type = "Guard", Honey = 200000000, Ingredients = { { Item = "Red Extract", Amount = 100 }, { Item = "Oil", Amount = 50 }, { Item = "Glitter", Amount = 25 }, { Item = "Stinger", Amount = 100 } } },
    { Bees = 25, Name = "Golden Gushers", Type = "Sprinkler", Honey = 333333333 },
    { Bees = 35, Name = "Tacky Planter", Type = "Planter", Honey = 50000000, Ingredients = { { Item = "Soft Wax", Amount = 20 }, { Item = "Hard Wax", Amount = 5 }, { Item = "Purple Potion", Amount = 1 }, { Item = "Magic Bean", Amount = 10 } } },
    { Bees = 20, Name = "Diamond Mask", Type = "Hat", Honey = 5000000000, Ingredients = { { Item = "Blue Extract", Amount = 250 }, { Item = "Oil", Amount = 150 }, { Item = "Glitter", Amount = 100 }, { Item = "Diamond Egg", Amount = 5 }, { Item = "Comforting Vial", Amount = 1 } } },
    { Bees = 20, Name = "Demon Mask", Type = "Hat", Honey = 5000000000, Ingredients = { { Item = "Red Extract", Amount = 250 }, { Item = "Enzymes", Amount = 150 }, { Item = "Glue", Amount = 100 }, { Item = "Stinger", Amount = 500 }, { Item = "Invigorating Vial", Amount = 1 } } },
    { Bees = 20, Name = "Gummy Mask", Type = "Hat", Honey = 5000000000, Ingredients = { { Item = "Glue", Amount = 250 }, { Item = "Enzymes", Amount = 100 }, { Item = "Oil", Amount = 100 }, { Item = "Glitter", Amount = 100 }, { Item = "Satisfying Vial", Amount = 1 } } },
    { Bees = 0, Name = "Honeycomb Belt", Type = "Belt", Honey = 75000000, Ingredients = { { Item = "Enzymes", Amount = 50 }, { Item = "Glue", Amount = 50 }, { Item = "Oil", Amount = 25 } } },
    { Bees = 35, Name = "Diamond Drenchers", Type = "Sprinkler", Honey = 4444444444 },
    { Bees = 35, Name = "Coconut Canister", Type = "Bag", Honey = 25000000000, Ingredients = { { Item = "Blue Extract", Amount = 150 }, { Item = "Red Extract", Amount = 150 }, { Item = "Tropical Drink", Amount = 150 }, { Item = "Coconut", Amount = 250 }, { Item = "Refreshing Vial", Amount = 2 } } },
    { Bees = 35, Name = "Pesticide Planter", Type = "Planter", Honey = 750000000, Ingredients = { { Item = "Glue", Amount = 15 }, { Item = "Caustic Wax", Amount = 3 }, { Item = "Hard Wax", Amount = 10 }, { Item = "Neonberry", Amount = 25 }, { Item = "Magic Bean", Amount = 25 } } },
    { Bees = 35, Name = "Coconut Clogs", Type = "Boots", Honey = 10000000000, Ingredients = { { Item = "Glue", Amount = 100 }, { Item = "Oil", Amount = 100 }, { Item = "Tropical Drink", Amount = 50 }, { Item = "Coconut", Amount = 150 }, { Item = "Refreshing Vial", Amount = 1 } } },
    { Bees = 35, Name = "The Supreme Saturator", Type = "Sprinkler", Honey = 55555555555 },
    { Bees = 50, Name = "Tide Popper", Type = "Tool", Honey = 2500000000000, Ingredients = { { Item = "Blue Extract", Amount = 1500 }, { Item = "Swirled Wax", Amount = 75 }, { Item = "Super Smoothie", Amount = 50 }, { Item = "Tropical Drink", Amount = 150 }, { Item = "Stinger", Amount = 150 }, { Item = "Comforting Vial", Amount = 3 } } },
    { Bees = 50, Name = "Dark Scythe", Type = "Tool", Honey = 2500000000000, Ingredients = { { Item = "Red Extract", Amount = 1500 }, { Item = "Hard Wax", Amount = 100 }, { Item = "Caustic Wax", Amount = 50 }, { Item = "Super Smoothie", Amount = 50 }, { Item = "Stinger", Amount = 150 }, { Item = "Invigorating Vial", Amount = 3 } } },
    { Bees = 50, Name = "Gummyballer", Type = "Tool", Honey = 10000000000000, Ingredients = { { Item = "Glue", Amount = 1500 }, { Item = "Gumdrop", Amount = 2000 }, { Item = "Caustic Wax", Amount = 50 }, { Item = "Super Smoothie", Amount = 50 }, { Item = "Turpentine", Amount = 5 }, { Item = "Satisfying Vial", Amount = 3 } } },
    { Bees = 50, Name = "Hydroponic Planter", Type = "Planter", Honey = 750000000000, Ingredients = { { Item = "Blue Extract", Amount = 750 }, { Item = "Soft Wax", Amount = 500 }, { Item = "Caustic Wax", Amount = 25 }, { Item = "Turpentine", Amount = 1 }, { Item = "Magic Bean", Amount = 75 } } },
    { Bees = 50, Name = "Heat-Treated Planter", Type = "Planter", Honey = 750000000000, Ingredients = { { Item = "Red Extract", Amount = 750 }, { Item = "Hard Wax", Amount = 150 }, { Item = "Swirled Wax", Amount = 25 }, { Item = "Turpentine", Amount = 1 }, { Item = "Magic Bean", Amount = 75 } } },
    { Bees = 50, Name = "Petal Planter", Type = "Planter", Honey = 5000000000000, Ingredients = { { Item = "Glitter", Amount = 100 }, { Item = "Soft Wax", Amount = 250 }, { Item = "Swirled Wax", Amount = 50 }, { Item = "Super Smoothie", Amount = 25 }, { Item = "Magic Bean", Amount = 100 } } },
    { Bees = 35, Name = "Gummy Boots", Type = "Boots", Honey = 100000000000, Ingredients = { { Item = "Glue", Amount = 500 }, { Item = "Glitter", Amount = 250 }, { Item = "Red Extract", Amount = 250 }, { Item = "Blue Extract", Amount = 250 }, { Item = "Satisfying Vial", Amount = 1 }, { Item = "Motivating Vial", Amount = 1 } } },
    { Bees = 50, Name = "Coconut Belt", Type = "Belt", Honey = 7500000000000, Ingredients = { { Item = "Tropical Drink", Amount = 1500 }, { Item = "Purple Potion", Amount = 200 }, { Item = "Hard Wax", Amount = 200 }, { Item = "Turpentine", Amount = 3 }, { Item = "Coconut", Amount = 500 }, { Item = "Refreshing Vial", Amount = 3 } } },
    { Bees = 50, Name = "Plenty Planter", Type = "Planter", Honey = 100000000000000, Ingredients = { { Item = "Super Smoothie", Amount = 100 }, { Item = "Swirled Wax", Amount = 100 }, { Item = "Caustic Wax", Amount = 100 }, { Item = "Turpentine", Amount = 25 }, { Item = "Magic Bean", Amount = 500 } } },
    { Bees = 35, Name = "Petal Belt", Type = "Belt", Honey = 15000000000, Ingredients = { { Item = "Glue", Amount = 100 }, { Item = "Glitter", Amount = 50 }, { Item = "Star Jelly", Amount = 25 }, { Item = "Spirit Petal", Amount = 1 } } },
    { Bees = 35, Name = "Petal Wand", Type = "Tool", Honey = 1500000000, Ingredients = { { Item = "Enzymes", Amount = 75 }, { Item = "Glitter", Amount = 25 }, { Item = "Star Jelly", Amount = 10 }, { Item = "Spirit Petal", Amount = 1 } } }
}

-- Kept on a getgenv table instead of top-level locals to save registers in the
-- main chunk (Luau has a 200-local limit). It cannot live on Progression: this
-- initializer runs before the Progression local is assigned, so indexing it
-- here would crash the whole script with "attempt to index nil".
getgenv().IvyisStatCache = getgenv().IvyisStatCache or { stats = nil, time = 0 }

local function getStatData()
    local data = nil

    pcall(function()
        local cache = RS:FindFirstChild("ClientStatCache")
        if cache and cache:IsA("ModuleScript") then
            local mod = require(cache)
            if type(mod) == "table" then
                if type(mod.Get) == "function" then
                    data = mod:Get() or mod.Get() or mod:Get(player)
                elseif type(mod.Stats) == "table" then
                    data = mod.Stats
                elseif type(mod.Cache) == "table" then
                    data = mod.Cache
                end
            end
        end
    end)

    if not (data and (data.Collector or data.Bag or data.Boots or data.Equipped)) then
        if not getgenv().IvyisStatCache.stats or (tick() - getgenv().IvyisStatCache.time > 25) then
            local events = RS:FindFirstChild("Events")
            if events and events:FindFirstChild("RetrievePlayerStats") then
                local ok, res = pcall(function() return events.RetrievePlayerStats:InvokeServer() end)
                if ok and type(res) == "table" then
                    getgenv().IvyisStatCache.stats = res
                    getgenv().IvyisStatCache.time = tick()
                end
            end
        end
        if getgenv().IvyisStatCache.stats then
            if not data then
                data = getgenv().IvyisStatCache.stats
            else
                for k, v in pairs(getgenv().IvyisStatCache.stats) do
                    if data[k] == nil then data[k] = v end
                end
            end
        end
    end

    local clientStat = RS:FindFirstChild("ClientStatCache")
    if clientStat then
        local myStats = clientStat:FindFirstChild(player.Name)
        if myStats then
            if not data then data = {} end
            for _, folder in ipairs(myStats:GetChildren()) do
                if folder:IsA("Folder") or folder:IsA("Configuration") then
                    if not data[folder.Name] or type(data[folder.Name]) ~= "table" then data[folder.Name] = {} end
                    for _, val in ipairs(folder:GetChildren()) do
                        if val:IsA("ValueBase") then data[folder.Name][val.Name] = val.Value end
                    end
                elseif folder:IsA("ValueBase") then
                    data[folder.Name] = folder.Value
                end
            end
        end
    end

    return data
end

local function getBeeCount(data)
    local count = 0
    local honeycombs = workspace:FindFirstChild("Honeycombs")
    local hVal = player:FindFirstChild("Honeycomb") and player.Honeycomb.Value
    local hive = (typeof(hVal) == "Instance" and hVal) or (honeycombs and honeycombs:FindFirstChild(tostring(hVal)))
    if hive and hive:FindFirstChild("Cells") then
        for _, cell in ipairs(hive.Cells:GetChildren()) do
            local ct = cell:FindFirstChild("CellType") or cell:FindFirstChild("Type")
            local tv = ct and tostring(ct.Value):lower() or ""
            if tv ~= "" and tv ~= "empty" and tv ~= "none" and tv ~= "nil" then count = count + 1 end
        end
    end
    if count > 0 then return count end
    if data and data.Bees and type(data.Bees) == "table" then
        for _ in pairs(data.Bees) do count = count + 1 end
    end
    return count
end

local function readAmount(val)
    if type(val) == "number" then return val end
    if type(val) == "string" then return tonumber(val) end
    if typeof and typeof(val) == "Instance" then
        if val:IsA("ValueBase") then return tonumber(val.Value) end
        local v = val:FindFirstChild("Value")
        if v and v:IsA("ValueBase") then return tonumber(v.Value) end
    end
    if type(val) == "table" then
        return tonumber(val.Amount or val.amount or val.Value or val.value or val.Count or val.count or val.Quantity or val.quantity or val[1])
    end
    return nil
end

local function collectItemTables(rootData)
    if type(rootData) ~= "table" then return {} end
    local list = {}
    local seen = {}
    local function addFolder(t, depth)
        if type(t) ~= "table" or (depth or 0) > 3 or seen[t] then return end
        seen[t] = true
        table.insert(list, t)
        for k, v in pairs(t) do
            local lk = tostring(k):lower()
            if type(v) == "table" and not seen[v] and (depth or 0) < 2 then
                if lk == "items" or lk == "eggs" or lk == "inventory" or lk == "supplies"
                    or lk == "collectibles" or lk == "totals" or lk == "boosts" or lk == "buffs"
                    or lk == "materials" or lk == "other" or lk == "resources" or lk == "crafting" then
                    addFolder(v, (depth or 0) + 1)
                end
            end
        end
    end
    addFolder(rootData.Eggs, 1)
    addFolder(rootData.Inventory, 1)
    addFolder(rootData.Items, 1)
    addFolder(rootData.Supplies, 1)
    addFolder(rootData.Materials, 1)
    addFolder(rootData.Collectibles, 1)
    addFolder(rootData.Totals, 1)
    addFolder(rootData, 1)
    return list
end

local function nameVariants(item, cleanKey)
    local cItem = item:gsub("[%s%-_']", ""):lower()
    local variants = { [cItem] = true }
    if cleanKey then variants[cleanKey:lower()] = true end
    if cItem:sub(-1) == "s" then
        variants[cItem:sub(1, -2)] = true
    else
        variants[cItem .. "s"] = true
    end
    if cItem:sub(-1) == "y" then
        variants[cItem:sub(1, -2) .. "ies"] = true
    elseif cItem:sub(-3) == "ies" then
        variants[cItem:sub(1, -4) .. "y"] = true
    end
    if cItem:sub(-1) == "x" or cItem:sub(-2) == "sh" or cItem:sub(-2) == "ch" then
        variants[cItem .. "es"] = true
    elseif cItem:sub(-2) == "es" and not cItem:sub(-3):find("[aeiou]es") then
        variants[cItem:sub(1, -3)] = true
    end
    variants[cItem .. "item"] = true
    return variants, cItem
end

local function countItemInGui(variants)
    local count = nil
    pcall(function()
        local pg = player:FindFirstChild("PlayerGui")
        if not pg then return end
        for _, desc in ipairs(pg:GetDescendants()) do
            if (desc:IsA("Frame") or desc:IsA("ImageLabel") or desc:IsA("TextButton")) and desc.Visible then
                local dName = desc.Name:gsub("[%s%-_']", ""):lower()
                if variants[dName] then
                    for _, sub in ipairs(desc:GetDescendants()) do
                        if sub:IsA("TextLabel") and sub.Visible then
                            local num = tonumber(sub.Text:match("^[xX]?%s*(%d+)%s*$"))
                            if num and (not count or num > count) then
                                count = num
                            end
                        end
                    end
                end
            end
        end
    end)
    return count
end

local function countItem(item, data)
    if not item then return 0 end
    local cleanKey = item:gsub("%s+", "")
    local keys = { item, cleanKey }

    local eggBase = item:match("^(.+)%s+[Ee]gg$") or item:match("^(.+)[Ee]gg$")
    if eggBase then
        table.insert(keys, eggBase)
        table.insert(keys, eggBase .. "Egg")
        table.insert(keys, eggBase .. " Egg")
        if eggBase:lower() == "golden" then
            table.insert(keys, "Gold")
            table.insert(keys, "GoldEgg")
        end
    end

    local variants, cItem = nameVariants(item, cleanKey)

    -- Honey hien tai nam o data.Honey; data.Totals.Honey la all-time (Honey Badge).
    -- Uu tien data.Honey truoc khi quet cac folder de khong lay nham chi so badge.
    -- Neu khong tim thay current honey thi tra 0, khong fallback ve Totals.Honey.
    if cItem == "honey" and type(data) == "table" then
        local currentHoney = readAmount(data.Honey)
        if currentHoney ~= nil then return currentHoney end
        local currency = data.Currency
        if type(currency) == "table" then
            currentHoney = readAmount(currency.Honey)
            if currentHoney ~= nil then return currentHoney end
        end
        currentHoney = readAmount(data.CurrentHoney or data.currentHoney)
        if currentHoney ~= nil then return currentHoney end
        return 0
    end

    if getgenv then
        local g = getgenv()
        if g.OwnedItems and type(g.OwnedItems) == "table" then
            local n = readAmount(g.OwnedItems[item] or g.OwnedItems[cleanKey] or g.OwnedItems[cItem])
            if n then return n end
        end
        if (cItem == "glitter" or variants["glitter"]) and (g.SkipGlitter or g.HasGlitter) then
            return 999999
        end
        if g["Has" .. cleanKey] or g["Skip" .. cleanKey] then
            return 999999
        end
    end

    if data then
        local folders = collectItemTables(data)
        for _, folder in ipairs(folders) do
            if type(folder) == "table" then
                for _, k in ipairs(keys) do
                    if folder[k] ~= nil then
                        local num = readAmount(folder[k])
                        if num then return num end
                    end
                end
                for k, v in pairs(folder) do
                    if type(k) == "string" then
                        local ck = tostring(k):gsub("[%s%-_']", ""):lower()
                        if variants[ck] then
                            local num = readAmount(v)
                            if num then return num end
                        end
                    end
                end
            end
        end
    end

    if getgenv then
        local atlas = getgenv().Atlas
        if type(atlas) == "table" then
            local aFolders = collectItemTables(atlas.Stats or atlas.Inventory or atlas.Data or atlas.Items or atlas)
            for _, folder in ipairs(aFolders) do
                if type(folder) == "table" then
                    for _, k in ipairs(keys) do
                        if folder[k] ~= nil then
                            local num = readAmount(folder[k])
                            if num then return num end
                        end
                    end
                    for k, v in pairs(folder) do
                        if type(k) == "string" then
                            local ck = tostring(k):gsub("[%s%-_']", ""):lower()
                            if variants[ck] then
                                local num = readAmount(v)
                                if num then return num end
                            end
                        end
                    end
                end
            end
        end
    end

    local guiAmount = countItemInGui(variants)
    if guiAmount then return guiAmount end

    return 0
end

local ITEM_ALIASES = {
    ["diamask"] = "Diamond Mask",
    ["diamondmask"] = "Diamond Mask",
    ["demonmask"] = "Demon Mask",
    ["gummymask"] = "Gummy Mask",
    ["bubblemask"] = "Bubble Mask",
    ["honeymask"] = "Honey Mask",
    ["firemask"] = "Fire Mask",
    ["beekeepersmask"] = "Beekeeper's Mask",
    ["beekeepermask"] = "Beekeeper's Mask",
    ["beekmask"] = "Beekeeper's Mask",
    ["propellerhat"] = "Propeller Hat",
    ["helmet"] = "Helmet",
    ["beekeepersboots"] = "Beekeeper's Boots",
    ["beekeeperboots"] = "Beekeeper's Boots",
    ["beekboots"] = "Beekeeper's Boots",
    ["hikingboots"] = "Hiking Boots",
    ["basicboots"] = "Basic Boots",
    ["cleanboots"] = "Basic Boots",
    ["coconutclogs"] = "Coconut Clogs",
    ["cococlogs"] = "Coconut Clogs",
    ["clogs"] = "Coconut Clogs",
    ["gummyboots"] = "Gummy Boots",
    ["beltpocket"] = "Belt Pocket",
    ["beltbag"] = "Belt Bag",
    ["mondobeltbag"] = "Mondo Belt Bag",
    ["mondobelt"] = "Mondo Belt Bag",
    ["honeycombbelt"] = "Honeycomb Belt",
    ["petalbelt"] = "Petal Belt",
    ["coconutbelt"] = "Coconut Belt",
    ["cocobelt"] = "Coconut Belt",
    ["porcelaindipper"] = "Porcelain Dipper",
    ["porcdipper"] = "Porcelain Dipper",
    ["pdipper"] = "Porcelain Dipper",
    ["goldenrake"] = "Golden Rake",
    ["petalwand"] = "Petal Wand",
    ["tidepopper"] = "Tide Popper",
    ["darkscythe"] = "Dark Scythe",
    ["gummyballer"] = "Gummyballer",
    ["bubblewand"] = "Bubble Wand",
    ["scythe"] = "Scythe",
    ["clipper"] = "Clippers",
    ["clippers"] = "Clippers",
    ["vacuum"] = "Vacuum",
    ["magnet"] = "Magnet",
    ["electromagnet"] = "Electro-Magnet",
    ["honeydipper"] = "Honey Dipper",
    ["superscooper"] = "Super-Scooper",
    ["pulsar"] = "Pulsar",
    ["pulser"] = "Pulsar",
    ["porcelainportohive"] = "Porcelain Port-O-Hive",
    ["porcportohive"] = "Porcelain Port-O-Hive",
    ["porcport"] = "Porcelain Port-O-Hive",
    ["blueportohive"] = "Blue Port-O-Hive",
    ["redportohive"] = "Red Port-O-Hive",
    ["portohive"] = "Port-O-Hive",
    ["coconutcanister"] = "Coconut Canister",
    ["cococanister"] = "Coconut Canister",
    ["cocanister"] = "Coconut Canister",
    ["elitebarrel"] = "Elite Barrel",
    ["megajug"] = "Mega-Jug",
    ["compressor"] = "Compressor",
    ["canister"] = "Canister",
    ["backpack"] = "Backpack",
    ["cobaltguard"] = "Cobalt Guard",
    ["crimsonguard"] = "Crimson Guard",
    ["buckoguard"] = "Bucko Guard",
    ["rileyguard"] = "Riley Guard",
    ["eliteblueguard"] = "Elite Blue Guard",
    ["eliteredguard"] = "Elite Red Guard",
    ["lookerguard"] = "Looker Guard",
    ["braveguard"] = "Brave Guard",
    ["basicsprinkler"] = "Basic Sprinkler",
    ["silversoakers"] = "Silver Soakers",
    ["goldengushers"] = "Golden Gushers",
    ["diamonddrenchers"] = "Diamond Drenchers",
    ["supremesaturator"] = "The Supreme Saturator",
    ["thesupremesaturator"] = "The Supreme Saturator",
    ["plasticplanter"] = "Plastic Planter",
    ["candyplanter"] = "Candy Planter",
    ["blueclayplanter"] = "Blue Clay Planter",
    ["redclayplanter"] = "Red Clay Planter",
    ["tackyplanter"] = "Tacky Planter",
    ["pesticideplanter"] = "Pesticide Planter",
    ["hydroponicplanter"] = "Hydroponic Planter",
    ["petalplanter"] = "Petal Planter",
    ["heattreatedplanter"] = "Heat-Treated Planter",
    ["plentyplanter"] = "Plenty Planter",
    ["planterofplenty"] = "Plenty Planter",
    ["glider"] = "Glider"
}

local function toItemName(raw)
    if not raw then return nil end
    local clean = tostring(raw):gsub("[%s%-_':%[%]%(%)]", ""):lower()
    if ITEM_ALIASES[clean] then return ITEM_ALIASES[clean] end
    -- khop chuoi con, uu tien alias dai nhat
    local bestK, bestV = nil, nil
    for k, v in pairs(ITEM_ALIASES) do
        if #k >= 6 and clean:find(k, 1, true) then
            if not bestK or #k > #bestK or (#k == #bestK and k < bestK) then
                bestK, bestV = k, v
            end
        end
    end
    return bestV or raw
end

-- chi khop dung ten, dung cho text lay tu UI
local function toItemNameExact(raw)
    if not raw then return nil end
    local clean = tostring(raw):gsub("[%s%-_':%[%]%(%)]", ""):lower()
    if clean == "" then return nil end
    if ITEM_ALIASES[clean] then return ITEM_ALIASES[clean] end
    for _, m in ipairs(DEFAULT_ROUTE) do
        if m.Name:gsub("[%s%-_':%[%]%(%)]", ""):lower() == clean then return m.Name end
    end
    return nil
end

local function itemKey(s)
    return tostring(toItemName(s) or s):gsub("[%s%-_']", ""):lower()
end

-- 0, false, "", {} deu tinh la khong co (Lua coi so 0 la truthy)
local function hasValue(v)
    if v == nil or v == false then return false end
    local t = type(v)
    if t == "number" then return v > 0 end
    if t == "string" then return v ~= "" and v ~= "0" end
    if t == "table" then return next(v) ~= nil end
    return true
end

local function isRouteItem(name)
    if not name or type(name) ~= "string" or #name < 2 then return false end
    local clean = name:gsub("[%s%-_':%[%]%(%)]", ""):lower()
    if ITEM_ALIASES[clean] then return true end
    for _, milestone in ipairs(DEFAULT_ROUTE) do
        local c = milestone.Name:gsub("[%s%-_':%[%]%(%)]", ""):lower()
        if c == clean then return true end
    end
    return false
end

local function normalizeGearSlot(val, tierTable)
    if val == nil then return nil end
    if type(val) == "table" then
        val = val.Name or val.Item or val.Type or val.Id
        if val == nil then return nil end
    end
    local c = tostring(val):gsub("[%s%-_']", ""):lower()
    if tierTable[c] then return c end
    local resolved = toItemName(val)
    if resolved then
        local rc = tostring(resolved):gsub("[%s%-_']", ""):lower()
        if tierTable[rc] then return rc end
    end
    return nil
end

local atlasSettingsCache = nil
local lastGcScan = { settings = 0, route = 0 }

local function isAtlasSettingsTable(t)
    if type(t) ~= "table" then return false end
    if type(t.autofarm) == "table" and (t.autofarm.field1 ~= nil or t.autofarm.field ~= nil or t.autofarm.fields ~= nil) then
        return true
    end
    if type(t.farming) == "table" and (t.farming.field1 ~= nil or t.farming.field ~= nil) then
        return true
    end
    local ok, hasToys = pcall(function() return t.toys end)
    local ok2, hasFarm = pcall(function() return t.autofarm or t.farming or (t.toys and t.toys.route) end)
    return ok and ok2 and (type(hasFarm) == "table" or (type(hasToys) == "table" and t.toys.route ~= nil))
end

local function findAtlasSettings()
    if atlasSettingsCache and isAtlasSettingsTable(atlasSettingsCache) then
        return atlasSettingsCache
    end

    local roots = dropNils({ getgenv and getgenv(), _G, shared }, 3)
    for _, root in ipairs(roots) do
        if type(root) == "table" then
            if isAtlasSettingsTable(root) then
                atlasSettingsCache = root
                return root
            end
            if root.Atlas and type(root.Atlas) == "table" then
                if isAtlasSettingsTable(root.Atlas.Settings) then
                    atlasSettingsCache = root.Atlas.Settings
                    return root.Atlas.Settings
                end
                if isAtlasSettingsTable(root.Atlas) then
                    atlasSettingsCache = root.Atlas
                    return root.Atlas
                end
            end
            if isAtlasSettingsTable(root.Settings) then
                atlasSettingsCache = root.Settings
                return root.Settings
            end
            if isAtlasSettingsTable(root.Config) then
                atlasSettingsCache = root.Config
                return root.Config
            end
            for k, v in pairs(root) do
                if type(v) == "table" and k ~= "_G" and k ~= "shared" and k ~= "game" and k ~= "workspace" and k ~= "Enum" then
                    if isAtlasSettingsTable(v) then
                        atlasSettingsCache = v
                        return v
                    end
                    if isAtlasSettingsTable(v.Settings) then
                        atlasSettingsCache = v.Settings
                        return v.Settings
                    end
                end
            end
        end
    end

    local minInterval = atlasSettingsCache and 60 or 30
    if getgc and (tick() - lastGcScan.settings > minInterval) then
        lastGcScan.settings = tick()
        local ok, gc = pcall(getgc, true)
        if not ok or type(gc) ~= "table" then ok, gc = pcall(getgc) end
        if ok and type(gc) == "table" then
            for _, obj in ipairs(gc) do
                if isAtlasSettingsTable(obj) then
                    atlasSettingsCache = obj
                    return obj
                end
            end
        end
    end

    return nil
end

local ownedPlanterCache = {}

local function ownsPlanter(cleanName, rawClean, canonical, data)
    local rootPlanter = cleanName:gsub("planter", "")
    if rootPlanter == "" then rootPlanter = cleanName end

    if getgenv then
        local g = getgenv()
        if g.SkipPlanters then return true end
        if g.SkipCandyPlanter and rootPlanter == "candy" then return true end
        local skipVar = "Skip" .. tostring(canonical or cleanName):gsub("[%s%-_']", "")
        if g[skipVar] then return true end
        if type(g.OwnedPlanters) == "table" then
            if g.OwnedPlanters[canonical] or g.OwnedPlanters[cleanName] or g.OwnedPlanters[rawClean] or g.OwnedPlanters[rootPlanter] then
                return true
            end
        end
    end

    -- Planter vinh vien (mua 1 lan, dung lai vo han; thu hoach xong quay lai tui).
    -- Ghim "da so huu" theo tai khoan de khong bao "da mua" lai va khong farm lai
    -- trong luc planter dang duoc trong duoi dat (khong con nam trong Backpack).
    local isPermanent = rootPlanter == "plastic" or rootPlanter == "candy"
        or rootPlanter == "redclay" or rootPlanter == "blueclay" or rootPlanter == "tacky"
        or rootPlanter == "pesticide" or rootPlanter == "heattreated"
        or rootPlanter == "hydroponic" or rootPlanter == "petal"
        or (rootPlanter:find("plenty", 1, true) ~= nil)

    local planterStore = _G.__IvyisOwnedPlanters
    if type(planterStore) ~= "table" then
        planterStore = {
            loaded = false,
            dirty = false,
            owned = {},
            path = "AutoFeedBSS/planters_" .. tostring(player.Name):gsub("[^%w_%-]", "_") .. ".json",
        }
        _G.__IvyisOwnedPlanters = planterStore
    end
    if not planterStore.loaded then
        planterStore.loaded = true
        pcall(function()
            if not (readfile and isfile and isfile(planterStore.path)) then return end
            local decoded = HttpService:JSONDecode(readfile(planterStore.path))
            if type(decoded) == "table" then
                for k, v in pairs(decoded) do
                    if v == true and type(k) == "string" then planterStore.owned[k] = true end
                end
            end
        end)
    end

    if isPermanent then
        if planterStore.owned[cleanName] or ownedPlanterCache[cleanName]
            or (canonical and ownedPlanterCache[canonical:lower()]) then
            if not planterStore.owned[cleanName] then
                planterStore.owned[cleanName] = true
                if not planterStore.dirty and writefile then
                    planterStore.dirty = true
                    task.delay(2, function()
                        planterStore.dirty = false
                        pcall(function()
                            if makefolder and isfolder and not isfolder("AutoFeedBSS") then makefolder("AutoFeedBSS") end
                            writefile(planterStore.path, HttpService:JSONEncode(planterStore.owned))
                        end)
                    end)
                end
            end
            return true
        end
    end

    local function matches(s)
        if not s then return false end
        local c = tostring(s):gsub("[%s%-_':%[%]%(%)]", ""):lower()
        if c == cleanName or c == rawClean or (canonical and c == canonical:gsub("[%s%-_']", ""):lower()) then
            return true
        end
        if rootPlanter ~= "" then
            if c == rootPlanter or c == rootPlanter .. "planter" or c == "planter" .. rootPlanter then
                return true
            end
            if c:find(rootPlanter, 1, true) and (c:find("planter", 1, true) or #c <= #rootPlanter + 3) then
                return true
            end
        end
        return false
    end

    if player.Backpack then
        for _, item in ipairs(player.Backpack:GetChildren()) do
            if matches(item.Name) then
                ownedPlanterCache[cleanName] = true
                return true
            end
        end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if matches(item.Name) then
                ownedPlanterCache[cleanName] = true
                return true
            end
        end
    end

    if data then
        if (canonical and countItem(canonical, data) > 0)
            or countItem(cleanName, data) > 0
            or countItem(rawClean, data) > 0
            or (rootPlanter ~= "" and countItem(rootPlanter, data) > 0)
            or (rootPlanter ~= "" and countItem(rootPlanter .. " Planter", data) > 0) then
            ownedPlanterCache[cleanName] = true
            return true
        end

        local pTables = {
            data.Planters,
            data.PlanterTypes,
            -- PurchasedPlanters la so ghi "tung mua": voi planter dung-1-lan (Paper/
            -- Ticket/Festive/Sticker) no bao sai sau khi thu hoach, nen chi tin voi planter vinh vien.
            (isPermanent and data.PurchasedPlanters or nil),
            data.PlanterInventory,
            data.ActivePlanters,
            data.PlantedPlanters,
            data.Eggs,
            data.Items,
            data.Inventory,
            data.Equipment,
            data.Accessories
        }
        for _, tbl in ipairs(dropNils(pTables, 11)) do
            if type(tbl) == "table" then
                for k, v in pairs(tbl) do
                    if matches(k) and hasValue(v) then
                        ownedPlanterCache[cleanName] = true
                        return true
                    end
                    if type(v) == "string" and matches(v) then
                        ownedPlanterCache[cleanName] = true
                        return true
                    end
                    if type(v) == "table" then
                        if matches(v.Type) or matches(v.Name) or matches(v.PlanterType) or matches(v.Item) or matches(v.Id) then
                            ownedPlanterCache[cleanName] = true
                            return true
                        end
                        for k2, v2 in pairs(v) do
                            if (matches(k2) and hasValue(v2)) or (type(v2) == "string" and matches(v2)) then
                                ownedPlanterCache[cleanName] = true
                                return true
                            end
                        end
                    end
                end
            end
        end
    end

    local clientStat = RS:FindFirstChild("ClientStatCache")
    local myStats = clientStat and clientStat:FindFirstChild(player.Name)
    if myStats then
        for _, desc in ipairs(myStats:GetDescendants()) do
            if matches(desc.Name) then
                ownedPlanterCache[cleanName] = true
                return true
            end
            if desc:IsA("StringValue") and matches(desc.Value) then
                ownedPlanterCache[cleanName] = true
                return true
            end
        end
    end

    local guiScanHit = false
    pcall(function()
        if not (getgenv and getgenv().AutoProgPlanterGuiScan == true) then return end
        if player:FindFirstChild("PlayerGui") then
            for _, desc in ipairs(player.PlayerGui:GetDescendants()) do
                if desc:IsA("TextLabel") and desc.Visible and #desc.Text <= 40 and matches(desc.Text) and not desc:FindFirstAncestor("AutoProg_HUD") then
                    local isShop = false
                    local cur = desc
                    for _ = 1, 6 do
                        if not cur then break end
                        local n = cur.Name:lower()
                        if n:find("shop") or n:find("dapper") then isShop = true; break end
                        cur = cur.Parent
                    end
                    if not isShop then
                        ownedPlanterCache[cleanName] = true
                        guiScanHit = true
                        return
                    end
                end
            end
        end
    end)
    -- Cache chi con y nghia "dinh" voi planter vinh vien; planter dung-1-lan phai
    -- duoc kiem tra lai tu Backpack/du lieu song de con mua lai sau khi thu hoach.
    if guiScanHit or (isPermanent and ownedPlanterCache[cleanName]) then return true end

    local pName = player.Name:lower()
    local pUserId = tostring(player.UserId)
    local pDisplay = player.DisplayName and player.DisplayName:lower() or pName

    local searchContainers = {
        workspace:FindFirstChild("Planters"),
        workspace:FindFirstChild("ActivePlanters"),
        workspace:FindFirstChild("CorePlanters"),
        workspace:FindFirstChild("Fields")
    }

    for _, c in ipairs(dropNils(searchContainers, 4)) do
        if c then
            for _, desc in ipairs(c:GetDescendants()) do
                if desc:IsA("TextLabel") then
                    local t = desc.Text:lower()
                    local tc = (t:gsub("[%s%-_']", ""))
                    if (t:find(pName, 1, true) or t:find(pDisplay, 1, true) or t:find(pUserId, 1, true))
                        and tc:find(rootPlanter, 1, true) then
                        ownedPlanterCache[cleanName] = true
                        return true
                    end
                end
                if desc:IsA("Model") then
                    local isMine = false
                    local owner = desc:FindFirstChild("Owner") or desc:FindFirstChild("Player") or desc:FindFirstChild("User")
                    if owner then
                        local okV, rawV = pcall(function() return owner.Value end)
                        if okV then
                            local ov = tostring(rawV):lower()
                            if ov == pName or ov == pUserId or rawV == player or (char and rawV == char) then
                                isMine = true
                            end
                        end
                    end
                    local attr = desc:GetAttribute("Owner") or desc:GetAttribute("OwnerId") or desc:GetAttribute("Player")
                    if attr and (tostring(attr):lower() == pName or tostring(attr) == pUserId) then
                        isMine = true
                    end
                    if desc.Name:lower():find(pName, 1, true) then
                        isMine = true
                    end

                    if isMine then
                        if matches(desc.Name) then
                            ownedPlanterCache[cleanName] = true
                            return true
                        end
                        local pType = desc:FindFirstChild("Type") or desc:FindFirstChild("PlanterType") or desc:FindFirstChild("PlantType")
                        if pType and matches(pType.Value) then
                            ownedPlanterCache[cleanName] = true
                            return true
                        end
                        local aType = desc:GetAttribute("Type") or desc:GetAttribute("PlanterType")
                        if aType and matches(aType) then
                            ownedPlanterCache[cleanName] = true
                            return true
                        end
                    end
                end
            end
        end
    end

    local settings = findAtlasSettings()
    if settings then
        local pSettings = settings.planters or settings.Planters or (settings.toys and settings.toys.planters)
        if type(pSettings) == "table" and getgenv and getgenv().AutoProgTrustAtlasPlanters == true then
            for k, v in pairs(pSettings) do
                if matches(k) or (type(v) == "string" and matches(v)) then
                    ownedPlanterCache[cleanName] = true
                    return true
                end
                if type(v) == "table" and (matches(v.Type) or matches(v.Name) or matches(v.Planter)) then
                    ownedPlanterCache[cleanName] = true
                    return true
                end
            end
        end
    end

    return false
end

local function ownsItem(itemName, itemType, char, data)
    if not itemName then return false end
    local canonical = toItemName(itemName) or itemName
    local cleanName = tostring(canonical):gsub("[%s%-_']", ""):lower()
    local rawClean = tostring(itemName):gsub("[%s%-_']", ""):lower()

    if (itemType == "Planter" or cleanName:find("planter") or rawClean:find("planter")) then
        if ownsPlanter(cleanName, rawClean, canonical, data) then
            return true
        end
    end

    if char and (char:FindFirstChild(canonical) or char:FindFirstChild(itemName) or char:FindFirstChild(cleanName)) then return true end
    if player.Backpack and (player.Backpack:FindFirstChild(canonical) or player.Backpack:FindFirstChild(itemName) or player.Backpack:FindFirstChild(cleanName)) then return true end
    if char then
        for _, child in ipairs(char:GetChildren()) do
            local cName = child.Name:gsub("[%s%-_']", ""):lower()
            if cName == cleanName or cName == rawClean then return true end
        end
    end

    local eq = (data and (data.Equipped or data.Equipment)) or {}

    local curTool = (data and (data.Collector or data.Tool)) or eq.Collector or eq.Tool
    local curBag = (data and (data.Bag or data.Backpack)) or eq.Bag or eq.Backpack
    local curBoots = (data and (data.Boots or data.Shoes)) or eq.Boots or eq.Shoes
    local curBelt = (data and (data.Belt or data.BeltBag)) or eq.Belt or eq.BeltBag
    local curHat = (data and (data.Hat or data.Mask)) or eq.Hat or eq.Mask
    local curSprinkler = (data and data.Sprinkler) or eq.Sprinkler
    local curBlueGuard = (data and (data.BlueGuard or data.LeftGuard)) or eq.BlueGuard or eq.LeftGuard
    local curRedGuard = (data and (data.RedGuard or data.RightGuard)) or eq.RedGuard or eq.RightGuard
    local curGlider = (data and data.Glider) or eq.Glider

    curTool = normalizeGearSlot(curTool, TOOL_TIERS)
    curBag = normalizeGearSlot(curBag, BAG_TIERS)
    curBoots = normalizeGearSlot(curBoots, BOOTS_TIERS)
    curBelt = normalizeGearSlot(curBelt, BELT_TIERS)
    curHat = normalizeGearSlot(curHat, HAT_TIERS)
    curSprinkler = normalizeGearSlot(curSprinkler, SPRINKLER_TIERS)
    curBlueGuard = normalizeGearSlot(curBlueGuard, BLUE_GUARD_TIERS)
    curRedGuard = normalizeGearSlot(curRedGuard, RED_GUARD_TIERS)
    if curGlider then
        local gc = tostring(curGlider):gsub("[%s%-_']", ""):lower()
        if gc ~= "glider" then curGlider = nil end
    end

    local function trackBestGear(val)
        if type(val) ~= "string" and type(val) ~= "number" then return end
        local c = tostring(val):gsub("[%s%-_']", ""):lower()
        if TOOL_TIERS[c] and (not curTool or (TOOL_TIERS[curTool] and TOOL_TIERS[c] > TOOL_TIERS[curTool])) then curTool = c end
        if BAG_TIERS[c] and (not curBag or (BAG_TIERS[curBag] and BAG_TIERS[c] > BAG_TIERS[curBag])) then curBag = c end
        if BOOTS_TIERS[c] and (not curBoots or (BOOTS_TIERS[curBoots] and BOOTS_TIERS[c] > BOOTS_TIERS[curBoots])) then curBoots = c end
        if BELT_TIERS[c] and (not curBelt or (BELT_TIERS[curBelt] and BELT_TIERS[c] > BELT_TIERS[curBelt])) then curBelt = c end
        if HAT_TIERS[c] and (not curHat or (HAT_TIERS[curHat] and HAT_TIERS[c] > HAT_TIERS[curHat])) then curHat = c end
        if SPRINKLER_TIERS[c] and (not curSprinkler or (SPRINKLER_TIERS[curSprinkler] and SPRINKLER_TIERS[c] > SPRINKLER_TIERS[curSprinkler])) then curSprinkler = c end
        if BLUE_GUARD_TIERS[c] and (not curBlueGuard or (BLUE_GUARD_TIERS[curBlueGuard] and BLUE_GUARD_TIERS[c] > BLUE_GUARD_TIERS[curBlueGuard])) then curBlueGuard = c end
        if RED_GUARD_TIERS[c] and (not curRedGuard or (RED_GUARD_TIERS[curRedGuard] and RED_GUARD_TIERS[c] > RED_GUARD_TIERS[curRedGuard])) then curRedGuard = c end
        if not curGlider and c == "glider" then curGlider = c end
    end

    if char then
        for _, child in ipairs(char:GetChildren()) do
            trackBestGear(child.Name)
            if child:IsA("Tool") then
                local c = child.Name:gsub("[%s%-_']", ""):lower()
                if TOOL_TIERS[c] and (not curTool or (TOOL_TIERS[curTool] and TOOL_TIERS[c] > TOOL_TIERS[curTool])) then
                    curTool = c
                end
            end
        end
    end

    if player.Backpack then
        for _, child in ipairs(player.Backpack:GetChildren()) do
            trackBestGear(child.Name)
            if child:IsA("Tool") then
                local c = child.Name:gsub("[%s%-_']", ""):lower()
                if TOOL_TIERS[c] and (not curTool or (TOOL_TIERS[curTool] and TOOL_TIERS[c] > TOOL_TIERS[curTool])) then
                    curTool = c
                end
            end
        end
    end

    if data then
        for k, v in pairs(data) do
            if type(v) == "string" or type(v) == "number" then
                trackBestGear(v)
                if hasValue(v) then trackBestGear(k) end
            elseif type(v) == "table" then
                for k2, v2 in pairs(v) do
                    if hasValue(v2) then trackBestGear(k2) end
                    if type(v2) == "string" or type(v2) == "number" then trackBestGear(v2) end
                end
            end
        end
    end

    local SPECIAL_MASKS = {
        ["honeymask"] = true, ["bubblemask"] = true, ["firemask"] = true,
        ["gummymask"] = true, ["demonmask"] = true, ["diamondmask"] = true, ["diamask"] = true
    }

    -- tier cao hon thi coi nhu co tier thap, cung tier thi phai dung ten
    local function slotCovers(cur, tierTbl, skipTier)
        if not cur then return false end
        local c = tostring(cur):gsub("[%s%-_']", ""):lower()
        if c == cleanName or c == rawClean then return true end
        if itemKey(c) == cleanName then return true end
        if skipTier then return false end
        local reqTier = tierTbl[cleanName] or tierTbl[rawClean]
        local curTier = tierTbl[c]
        return (reqTier and curTier and curTier > reqTier) and true or false
    end

    if slotCovers(curTool, TOOL_TIERS)
        or slotCovers(curBag, BAG_TIERS)
        or slotCovers(curBoots, BOOTS_TIERS)
        or slotCovers(curBelt, BELT_TIERS)
        or slotCovers(curHat, HAT_TIERS, SPECIAL_MASKS[cleanName] or SPECIAL_MASKS[rawClean])
        or slotCovers(curSprinkler, SPRINKLER_TIERS)
        or slotCovers(curBlueGuard, BLUE_GUARD_TIERS)
        or slotCovers(curRedGuard, RED_GUARD_TIERS) then
        return true
    end

    if (cleanName == "glider" or rawClean == "glider") and curGlider then
        return true
    end

    local eqSources = { eq, data, data and data.Accessories, data and data.Equipment, data and data.Items, data and data.Inventory }
    for _, src in ipairs(dropNils(eqSources, 6)) do
        if type(src) == "table" then
            if hasValue(src[canonical]) or hasValue(src[itemName]) or hasValue(src[cleanName]) or hasValue(src[rawClean]) then return true end
            for k, val in pairs(src) do
                local kClean = tostring(k):gsub("[%s%-_']", ""):lower()
                local vClean = tostring(val):gsub("[%s%-_']", ""):lower()
                if ((kClean == cleanName or kClean == rawClean) and hasValue(val)) or vClean == cleanName or vClean == rawClean then
                    return true
                end
            end
        end
    end

    return false
end

local BASE_ROUTE_FIELDS = {
    [0] = "Dandelion Field",
    [5] = "Bamboo Field",
    [10] = "Pineapple Patch",
    [15] = "Pine Tree Forest"
}

local routeFields = {}
for k, v in pairs(BASE_ROUTE_FIELDS) do
    routeFields[k] = v
end

local function getRouteField(beeCount)
    local bestBees = -1
    local bestField = "Pine Tree Forest"
    for reqBees, fld in pairs(routeFields) do
        if beeCount >= reqBees and reqBees > bestBees then
            bestBees = reqBees
            bestField = fld
        end
    end
    return bestField
end

local function getFarmField(material, beeCount)
    if material == "Stinger" then
        return getRouteField(beeCount)
    end
    if material == "Coconut" and beeCount >= 35 then return "Coconut Field" end
    if beeCount < 5 then
        local map = { ["Blueberry"] = "Blue Flower Field", ["Strawberry"] = "Mushroom Field", ["Sunflower Seed"] = "Sunflower Field", ["Pineapple"] = "Dandelion Field" }
        return map[material]
    elseif beeCount < 15 then
        local map = { ["Blueberry"] = "Bamboo Field", ["Strawberry"] = "Strawberry Field", ["Sunflower Seed"] = "Sunflower Field", ["Pineapple"] = "Pineapple Patch" }
        return map[material]
    else
        local map = { ["Blueberry"] = "Pine Tree Forest", ["Strawberry"] = "Strawberry Field", ["Sunflower Seed"] = "Sunflower Field", ["Pineapple"] = "Pineapple Patch", ["Coconut"] = (beeCount >= 35) and "Coconut Field" or nil }
        return map[material]
    end
end


local function fireConnections(sig)
    local n = 0
    if not sig then return n end
    local ok, conns = pcall(getconnections, sig)
    if ok and type(conns) == "table" then
        for _, c in ipairs(conns) do
            if c.Fire then
                local fok = pcall(function() c:Fire() end)
                if fok then n = n + 1 end
            elseif c.Function then
                local fok = pcall(c.Function)
                if fok then n = n + 1 end
            end
        end
    end
    return n
end

local function getGuiText(gui)
    if not gui then return "" end
    if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
        local t = gui.Text
        if type(t) == "string" and t ~= "" then return t end
    end
    local lbl = gui:FindFirstChildWhichIsA("TextLabel")
    if lbl and type(lbl.Text) == "string" and lbl.Text ~= "" then
        return lbl.Text
    end
    return tostring(gui.Name or "")
end

local function isOnScreen(gui)
    if not gui or not gui:IsA("GuiObject") then return false end
    local cur = gui
    while cur and cur:IsA("GuiObject") do
        if not cur.Visible then return false end
        cur = cur.Parent
    end
    return gui.AbsoluteSize.X > 0 and gui.AbsoluteSize.Y > 0
end

local function bringIntoView(gui)
    if not gui or not gui:IsA("GuiObject") then return end
    if not isOnScreen(gui) then return end
    local scroll = gui:FindFirstAncestorWhichIsA("ScrollingFrame")
    if not scroll or scroll.AbsoluteSize.X <= 0 or scroll.AbsoluteSize.Y <= 0 then return end
    pcall(function()
        local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
        local view = scroll.AbsoluteSize
        local sp = scroll.AbsolutePosition
        local cx, cy = scroll.CanvasPosition.X, scroll.CanvasPosition.Y
        -- truc ngang (thanh tab cua Atlas)
        if pos.X < sp.X or pos.X + size.X > sp.X + view.X then
            local relX = pos.X - sp.X + cx
            cx = math.max(0, relX - math.max(0, (view.X - size.X) / 2))
        end
        -- truc doc
        if pos.Y < sp.Y or pos.Y + size.Y > sp.Y + view.Y then
            local relY = pos.Y - sp.Y + cy
            cy = math.max(0, relY - math.max(0, (view.Y - size.Y) / 2))
        end
        if cx ~= scroll.CanvasPosition.X or cy ~= scroll.CanvasPosition.Y then
            scroll.CanvasPosition = Vector2.new(cx, cy)
            task.wait(0.04)
        end
    end)
end

local function clickElement(gui, forceTap)
    if not gui or not gui:IsA("GuiObject") then return false end

    local clickable = gui
    if not gui:IsA("GuiButton") then
        clickable = gui:FindFirstAncestorWhichIsA("GuiButton") or gui
    end

    bringIntoView(clickable)

    -- forceTap = bo qua connection, tap thang vao toa do (Android: handler "la")
    if clickable:IsA("GuiButton") and not forceTap then
        local fired = false
        if getconnections then
            for _, sigName in ipairs({ "MouseButton1Click", "Activated" }) do
                local ok, cnt = pcall(function() return fireConnections(clickable[sigName]) end)
                if ok and cnt and cnt > 0 then
                    fired = true
                end
            end
        end
        if fired then return true end

        if firesignal then
            for _, sigName in ipairs({ "MouseButton1Click", "Activated" }) do
                if pcall(firesignal, clickable[sigName]) then return true end
            end
        end
    end

    if not isOnScreen(clickable) then return false end

    local size = clickable.AbsoluteSize
    local pos = clickable.AbsolutePosition
    local sg = clickable:FindFirstAncestorWhichIsA("ScreenGui")
    local inset = Vector2.new(0, 0)
    if not (sg and sg.IgnoreGuiInset) then
        local okI, v = pcall(function() return game:GetService("GuiService"):GetGuiInset() end)
        if okI and v then inset = v end
    end
    local x = pos.X + size.X / 2 + inset.X
    local y = pos.Y + size.Y / 2 + inset.Y

    local okVirtualInput, virtualInput = pcall(function() return game:GetService("VirtualInputManager") end)
    if okVirtualInput and virtualInput then
        local ok = pcall(function()
            virtualInput:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.03)
            virtualInput:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        if ok then return true end
    end
    if VirtualUser then
        local ok = pcall(function()
            VirtualUser:Button1Down(Vector2.new(x, y))
            task.wait(0.02)
            VirtualUser:Button1Up(Vector2.new(x, y))
        end)
        if ok then return true end
    end
    return false
end

local function findFarmingSection(root)
    if not root then return nil end
    local descs = root:GetDescendants()
    for _, obj in ipairs(descs) do
        if obj:IsA("Frame") or obj:IsA("ImageLabel") or obj:IsA("ScrollingFrame") then
            local hasTitle = false
            for _, ch in ipairs(obj:GetChildren()) do
                local t = getGuiText(ch):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
                if t == "farming" then
                    hasTitle = true
                    break
                end
            end
            if not hasTitle then
                for _, d in ipairs(obj:GetDescendants()) do
                    if d:IsA("TextLabel") or d:IsA("TextButton") then
                        local t = getGuiText(d):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
                        if t == "farming" then
                            local p = d.Parent
                            if p == obj or (p and p.Parent == obj) then
                                hasTitle = true
                                break
                            end
                        end
                    end
                end
            end

            if hasTitle then
                local hasAutofarm = false
                local hasField = false
                local isQuestSection = false

                for _, d in ipairs(obj:GetDescendants()) do
                    local t = getGuiText(d):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
                    if t == "autofarm" then
                        hasAutofarm = true
                    elseif t:match("^field%s*:") then
                        hasField = true
                    elseif t:match("^best") or t:match("quest") then
                        isQuestSection = true
                    end
                end

                if hasTitle and hasAutofarm and hasField and not isQuestSection then
                    return obj
                end
            end
        end
    end
    return nil
end

local function getFarmingHeader(root)
    if not root then return nil, nil, nil end

    local section = findFarmingSection(root)
    if section then
        for _, d in ipairs(section:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Name ~= "AutoProg_HUD" then
                local txt = getGuiText(d):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
                local low = txt:lower()
                if low:match("^field%s*:") and not (low:match("^best") or low:match("^allowed") or low:match("^quest") or low:match("^sprout")) then
                    return section, d, txt
                end
            end
        end
    end

    for _, d in ipairs(root:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Name ~= "AutoProg_HUD" then
            local txt = getGuiText(d):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
            local low = txt:lower()
            if low:match("^field%s*:") and not (low:match("^best") or low:match("^allowed") or low:match("^quest") or low:match("^sprout")) then
                local p = d.Parent
                for _ = 1, 3 do
                    if not p or p.Name == "Tabs" or p.Name == "Window" or p:IsA("ScreenGui") then break end
                    local hasAuto = false
                    local hasFarmTitle = false
                    local hasQuest = false
                    for _, desc in ipairs(p:GetDescendants()) do
                        local dt = getGuiText(desc):lower():gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
                        if dt == "autofarm" then hasAuto = true end
                        if dt == "farming" then hasFarmTitle = true end
                        if dt:match("^best") or dt:match("quest") then hasQuest = true end
                    end
                    if hasAuto and (hasFarmTitle or not hasQuest) then
                        return p, d, txt
                    end
                    p = p.Parent
                end
            end
        end
    end

    return nil, nil, nil
end

local farmHeaderCache = nil

local function getFarmingHeaderCached(root)
    local c = farmHeaderCache
    if c and c.header and c.section and c.header:IsDescendantOf(root) and c.section:IsDescendantOf(root) then
        local txt = getGuiText(c.header):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if txt:lower():match("^field%s*:") then
            return c.section, c.header, txt
        end
    end
    local section, header, txt = getFarmingHeader(root)
    if section and header then farmHeaderCache = { section = section, header = header } end
    return section, header, txt
end

local ATLAS_TAB_NAMES = {
    "home", "farming", "combat", "quests", "planters", "toys", "rbc", "webhook", "config"
}

local function findAtlasTabButton(root, tabName)
    if not root then return nil end
    local clean = tabName:gsub("[%s%-_']", ""):lower()
    for _, d in ipairs(root:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("ImageButton") or d:IsA("TextLabel")) and d.Name ~= "AutoProg_HUD" then
            local txt = getGuiText(d):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
            if txt == clean then
                local btn = (d:IsA("TextButton") or d:IsA("ImageButton")) and d
                    or d:FindFirstAncestorWhichIsA("TextButton")
                    or d:FindFirstAncestorWhichIsA("ImageButton")
                if btn then
                    return btn
                end
            end
        end
    end
    return nil
end

local function getActiveAtlasTabButton(root)
    if not root then return nil end
    local bestBtn = nil
    local bestScore = -1

    for _, name in ipairs(ATLAS_TAB_NAMES) do
        local btn = findAtlasTabButton(root, name)
        if btn then
            local score = 0
            if btn.BackgroundTransparency and btn.BackgroundTransparency < 0.95 then
                score = score + (1 - btn.BackgroundTransparency) * 5
            end
            if btn:IsA("ImageButton") and btn.ImageTransparency and btn.ImageTransparency < 0.95 then
                score = score + (1 - btn.ImageTransparency) * 5
            end
            for _, ch in ipairs(btn:GetChildren()) do
                if ch:IsA("GuiObject") and ch.BackgroundTransparency and ch.BackgroundTransparency < 0.95 then
                    score = score + 3
                end
            end
            if score > bestScore then
                bestScore = score
                bestBtn = btn
            end
        end
    end
    return bestBtn
end

local function findActiveAtlasTab(root)
    if not root then return nil, nil end
    for _, name in ipairs(ATLAS_TAB_NAMES) do
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("TextLabel") and d.Name ~= "AutoProg_HUD" then
                local txt = getGuiText(d):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
                if txt == name and isOnScreen(d) then
                    local btn = findAtlasTabButton(root, name)
                    if btn and d ~= btn and not d:IsDescendantOf(btn) then
                        return name, btn
                    end
                end
            end
        end
    end
    local fallbackBtn = getActiveAtlasTabButton(root)
    return nil, fallbackBtn
end

local configState = {
    path = nil, content = nil, route = nil, routeN = 0, routePath = nil,
    profile = nil, scannedAt = 0, reasons = {}, candidates = {}, ambiguous = false,
}

local function triggerButtonHeadless(btn)
    if not btn or not btn:IsA("GuiButton") then return false end
    local fired = false
    if getconnections then
        for _, sigName in ipairs({ "MouseButton1Click", "Activated" }) do
            if btn[sigName] then
                local n = fireConnections(btn[sigName])
                if n > 0 then fired = true end
            end
        end
    end
    if not fired and firesignal then
        for _, sigName in ipairs({ "MouseButton1Click", "Activated" }) do
            if pcall(firesignal, btn[sigName]) then fired = true break end
        end
    end
    return fired
end

local lastFileSync = { field = nil, vicious = false, at = 0 }

-- sua truc tiep text trong file config (khong decode/encode lai JSON,
-- vi JSONEncode doi {} thanh [] va lam hong config cua Atlas)
local function syncFieldAndViciousToActiveFile(targetField, enableVicious)
    if not (readfile and writefile and configState.path and isfile and isfile(configState.path)) then return end
    local wantField = targetField and targetField ~= "" and targetField ~= "Idle" and targetField ~= "Unchanged"
    if not wantField and not enableVicious then return end
    if (not wantField or lastFileSync.field == targetField)
        and (not enableVicious or lastFileSync.vicious)
        and tick() - lastFileSync.at < 20 then
        return
    end
    pcall(function()
        local content = readfile(configState.path)
        if type(content) ~= "string" or #content == 0 then return end
        local patched = content
        if wantField then
            local safe = targetField:gsub("%%", "%%%%")
            patched = patched:gsub('("field1"%s*:%s*)"[^"]*"', '%1"' .. safe .. '"')
            patched = patched:gsub('("field2"%s*:%s*)"[^"]*"', '%1"None"')
            patched = patched:gsub('("field3"%s*:%s*)"[^"]*"', '%1"None"')
        end
        if enableVicious then
            patched = patched:gsub('("killvicious"%s*:%s*)false', "%1true")
            patched = patched:gsub('("vicious"%s*:%s*)false', "%1true")
        end
        if patched ~= content then
            writefile(configState.path, patched)
        end
        lastFileSync.at = tick()
        if wantField then lastFileSync.field = targetField end
        if enableVicious then lastFileSync.vicious = true end
    end)
end

local function syncFieldAndViciousToMemory(targetField, enableVicious)
    local synced = false
    local settings = findAtlasSettings()
    if settings then
        if targetField and targetField ~= "" and targetField ~= "Idle" and targetField ~= "Unchanged" then
            if settings.autofarm and type(settings.autofarm) == "table" then
                settings.autofarm.field1 = targetField
                settings.autofarm.field2 = "None"
                settings.autofarm.field3 = "None"
                settings.autofarm.field = targetField
                if type(settings.autofarm.fields) == "table" then
                    settings.autofarm.fields[1] = targetField
                end
                synced = true
            end
            if settings.farming and type(settings.farming) == "table" then
                settings.farming.field1 = targetField
                settings.farming.field2 = "None"
                settings.farming.field = targetField
                synced = true
            end
        end
        if enableVicious then
            if not settings.combat or type(settings.combat) ~= "table" then settings.combat = {} end
            settings.combat.killvicious = true
            settings.combat.vicious = true
            settings.combat.giftedvicious = true
            if settings.combat.viciousmin == nil or settings.combat.viciousmin == 0 then settings.combat.viciousmin = 1 end
            if settings.combat.viciousmax == nil or settings.combat.viciousmax < 6 then settings.combat.viciousmax = 6 end
            synced = true
        end
    end

    local roots = dropNils({ getgenv and getgenv(), _G, shared }, 3)
    for _, root in ipairs(roots) do
        if type(root) == "table" then
            if root.Atlas and type(root.Atlas) == "table" then
                if targetField and targetField ~= "" and targetField ~= "Idle" and targetField ~= "Unchanged" then
                    root.Atlas.Field = targetField
                    root.Atlas.CurrentField = targetField
                    if root.Atlas.Settings and type(root.Atlas.Settings) == "table" then
                        root.Atlas.Settings.Field = targetField
                        if root.Atlas.Settings.autofarm then
                            root.Atlas.Settings.autofarm.field1 = targetField
                            root.Atlas.Settings.autofarm.field2 = "None"
                            root.Atlas.Settings.autofarm.field3 = "None"
                        end
                    end
                    if type(root.Atlas.SetField) == "function" then
                        pcall(root.Atlas.SetField, targetField)
                        synced = true
                    end
                end
                if enableVicious then
                    if not root.Atlas.Settings or type(root.Atlas.Settings) ~= "table" then root.Atlas.Settings = {} end
                    if not root.Atlas.Settings.combat or type(root.Atlas.Settings.combat) ~= "table" then root.Atlas.Settings.combat = {} end
                    root.Atlas.Settings.combat.killvicious = true
                    root.Atlas.Settings.combat.vicious = true
                    if type(root.Atlas.Toggle) == "function" then
                        pcall(root.Atlas.Toggle, "killvicious", true)
                        synced = true
                    end
                end
            end
            if root.Config and type(root.Config) == "table" then
                if targetField and targetField ~= "" and targetField ~= "Idle" and targetField ~= "Unchanged" and root.Config.autofarm then
                    root.Config.autofarm.field1 = targetField
                    root.Config.autofarm.field2 = "None"
                    root.Config.Field = targetField
                    synced = true
                end
                if enableVicious then
                    if not root.Config.combat or type(root.Config.combat) ~= "table" then root.Config.combat = {} end
                    root.Config.combat.killvicious = true
                    root.Config.combat.vicious = true
                    synced = true
                end
            end
            if enableVicious and type(root.Toggles) == "table" then
                for k, tog in pairs(root.Toggles) do
                    local lk = tostring(k):lower():gsub("[%s%-_']", "")
                    if lk == "killvicious" or lk == "vicious" or lk == "viciousbee" or lk == "autokillvicious" then
                        if type(tog) == "table" and type(tog.SetValue) == "function" then
                            pcall(function() tog:SetValue(true) end)
                            synced = true
                        end
                    end
                end
            end
            if targetField and targetField ~= "" and targetField ~= "Idle" and targetField ~= "Unchanged" and type(root.Options) == "table" then
                for k, opt in pairs(root.Options) do
                    local lk = tostring(k):lower():gsub("[%s%-_']", "")
                    if lk == "field1" or lk == "field" or lk == "autofarmfield" or lk == "farmingfield" or lk == "fields" then
                        if type(opt) == "table" and type(opt.SetValue) == "function" then
                            pcall(function() opt:SetValue(targetField) end)
                            synced = true
                        end
                    end
                end
            end
        end
    end
    return synced
end

local function setFieldViaUI(targetField)
    local uiRoots = {}
    pcall(function() if gethui then table.insert(uiRoots, gethui()) end end)
    pcall(function() table.insert(uiRoots, CoreGui) end)
    pcall(function() table.insert(uiRoots, player:FindFirstChild("PlayerGui")) end)

    local targetClean = targetField:gsub("[%s%-_']", ""):lower()

    for _, root in ipairs(uiRoots) do
        if root then
            for _, btn in ipairs(root:GetDescendants()) do
                if btn:IsA("TextButton") or btn:IsA("ImageButton") then
                    local rawTxt = getGuiText(btn):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower():gsub("[%s%-_']", "")
                    if rawTxt == targetClean then
                        local bName = tostring(btn.Name):lower()
                        local pName = tostring(btn.Parent and btn.Parent.Name or ""):lower()
                        if bName:find("dropdown") or pName:find("objects") or pName:find("dropdown") or bName == "dropdownbutton" then
                            if triggerButtonHeadless(btn) then
                                return true, "headless_dropdown_item"
                            end
                        end
                    end
                end
            end

            local section, farmingHeader, headerTxt = getFarmingHeaderCached(root)
            if farmingHeader and headerTxt then
                local cur = headerTxt:match("^[Ff]ield%s*:%s*(.+)")
                if cur and (cur:gsub("[%s%-_']", "")):lower() == targetClean then
                    return true, "ui_already_set"
                end
            end

            local isFarmingVisible = farmingHeader and isOnScreen(farmingHeader)
            local prevTabName, prevTabBtn = nil, nil
            local switchedTab = false

            if farmingHeader then
                local curVal = headerTxt and headerTxt:match("^[Ff]ield%s*:%s*(.+)")
                if curVal and curVal:gsub("[%s%-_']", ""):lower() == targetClean then
                    if switchedTab and prevTabBtn then triggerButtonHeadless(prevTabBtn) end
                    return true, "ui_already_set"
                end

                local clickTarget = farmingHeader:IsA("TextButton") and farmingHeader
                    or farmingHeader:FindFirstAncestorWhichIsA("TextButton")
                    or farmingHeader:FindFirstAncestorWhichIsA("ImageButton")
                    or farmingHeader.Parent

                triggerButtonHeadless(clickTarget)
                task.wait(0.08)

                local foundAndClicked = false
                for _, container in ipairs(dropNils({ section, root }, 2)) do
                    if not foundAndClicked and container then
                        for _, btn in ipairs(container:GetDescendants()) do
                            if (btn:IsA("TextButton") or btn:IsA("TextLabel") or btn:IsA("ImageButton")) and btn ~= farmingHeader and btn ~= clickTarget and btn.Name ~= "AutoProg_HUD" then
                                local rawTxt = getGuiText(btn):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
                                if rawTxt:gsub("[%s%-_']", ""):lower() == targetClean then
                                    if triggerButtonHeadless(btn:IsA("GuiButton") and btn or btn:FindFirstAncestorWhichIsA("GuiButton")) then
                                        foundAndClicked = true
                                        task.wait(0.04)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end

                if switchedTab and prevTabBtn then
                    task.wait(0.04)
                    triggerButtonHeadless(prevTabBtn)
                end

                if foundAndClicked then
                    return true, "ui_field_set"
                end
            elseif switchedTab and prevTabBtn then
                triggerButtonHeadless(prevTabBtn)
            end
        end
    end
    return false, "ui_not_found"
end

local lastSetField = nil
local lastFieldUiTime = 0

local function setField(field)
    if not field or field == "Idle" or field == "Unchanged" then return end

    local memOk = syncFieldAndViciousToMemory(field, nil)
    syncFieldAndViciousToActiveFile(field, nil)

    if not memOk and ((field ~= lastSetField) or (tick() - lastFieldUiTime > 60)) then
        lastFieldUiTime = tick()
        lastSetField = field
        pcall(setFieldViaUI, field)
    end
end

local viciousUiDone = false
local lastViciousCheck = 0

local function isViciousToggleText(txt)
    if not txt or type(txt) ~= "string" then return false end
    local low = txt:lower():gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if low:find("gifted") or low:find("min") or low:find("max") or low:find("level") or low:find("whitelist") then
        return false
    end
    return low == "auto kill vicious bee" or low == "auto kill vicious" or low == "kill vicious bee" or low:find("auto kill vicious")
end

local function isViciousSectionText(txt)
    if not txt or type(txt) ~= "string" then return false end
    local low = txt:lower():gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return low == "vicious bee"
end

local function isToggleOn(btn, row)
    if btn and btn:IsA("TextButton") and btn.Text == "✓" then
        return true
    end

    local objs = {}
    if row then
        for _, d in ipairs(row:GetDescendants()) do table.insert(objs, d) end
        table.insert(objs, row)
    end
    if btn then
        for _, d in ipairs(btn:GetDescendants()) do table.insert(objs, d) end
        table.insert(objs, btn)
    end

    for _, obj in ipairs(objs) do
        for _, attr in ipairs({ "Toggled", "Value", "Checked", "State", "Enabled" }) do
            local val = obj:GetAttribute(attr)
            if val == true then return true end
        end

        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local t = getGuiText(obj):lower():gsub("%s+", "")
            if t == "on" or t == "true" or t == "enabled" or t == "[x]" or t == "✓" or t == "✔" or t == "☑" then
                return true
            end
        end

        if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
            local img = tostring(obj.Image or ""):lower()
            if (img:find("check") or img:find("tick") or img:find("checkmark")) and obj.ImageTransparency < 0.5 and obj.Visible then
                return true
            end
        end

        if obj:IsA("GuiObject") and obj.BackgroundTransparency < 0.5 and obj.Visible then
            local c = obj.BackgroundColor3
            if c and c.G > 0.55 and c.G > c.R * 1.25 and c.G > c.B * 1.25 then
                return true
            end
        end
    end

    return false
end

local function findViciousSwitch(root)
    if not root then return nil, nil end

    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and d.Name ~= "AutoProg_HUD" then
            local t = getGuiText(d)
            if isViciousToggleText(t) then
                local btn = (d.Parent and d.Parent:IsA("TextButton") and d.Parent)
                    or (d:IsA("TextButton") and d)
                    or (d.Parent and d.Parent.Parent and d.Parent.Parent:FindFirstChildWhichIsA("TextButton", true))
                if btn then return btn, d.Parent end
            end
        end
    end

    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextButton") and isViciousSectionText(d.Text) then
            local box = d.Parent and d.Parent:FindFirstChild("Box")
            if box then
                for _, s in ipairs(box:GetDescendants()) do
                    if s:IsA("TextLabel") and isViciousToggleText(getGuiText(s)) then
                        local btn = (s.Parent and s.Parent:IsA("TextButton") and s.Parent)
                            or (s:IsA("TextButton") and s)
                            or (s.Parent and s.Parent:FindFirstChildWhichIsA("TextButton"))
                        if btn then return btn, s.Parent end
                    end
                end
                local firstSwitch = box:FindFirstChild("Switch")
                if firstSwitch then
                    local btn = firstSwitch:FindFirstChildWhichIsA("TextButton", true)
                    if btn then return btn, firstSwitch end
                end
            end
        end
    end

    return nil, nil
end

local function setViciousViaUI(enable)
    local uiRoots = {}
    pcall(function() if gethui then table.insert(uiRoots, gethui()) end end)
    pcall(function() table.insert(uiRoots, CoreGui) end)
    pcall(function() table.insert(uiRoots, player:FindFirstChild("PlayerGui")) end)

    for _, root in ipairs(uiRoots) do
        if root then
            local switchBtn, switchRow = findViciousSwitch(root)
            local prevTabName, prevTabBtn = nil, nil
            local switchedTab = false

            -- Khong tu dong chuyen tab combat de khong lam lo UI
            -- switchBtn chi duoc tim neu da co san tren UI hien tai

            if switchBtn then
                local isChecked = isToggleOn(switchBtn, switchRow)
                if enable and not isChecked then
                    triggerButtonHeadless(switchBtn)
                    task.wait(0.05)
                    viciousUiDone = true
                elseif isChecked then
                    viciousUiDone = true
                end

                if switchedTab and prevTabBtn then
                    task.wait(0.04)
                    triggerButtonHeadless(prevTabBtn)
                end

                return true, "ui_vicious_set"
            elseif switchedTab and prevTabBtn then
                task.wait(0.04)
                triggerButtonHeadless(prevTabBtn)
            end
        end
    end
    return false, "ui_vicious_not_found"
end

local function enableViciousKill()
    syncFieldAndViciousToMemory(nil, true)
    syncFieldAndViciousToActiveFile(nil, true)

    if not viciousUiDone or (tick() - lastViciousCheck > 30) then
        lastViciousCheck = tick()
        pcall(setViciousViaUI, true)
    end
end

local function needsStinger(targetItem, data)
    if not targetItem or targetItem == "None" then return false, 0 end
    local matched = nil
    local cTarget = targetItem:gsub("[%s%-_']", ""):lower()
    for _, m in ipairs(DEFAULT_ROUTE) do
        local cm = m.Name:gsub("[%s%-_']", ""):lower()
        if cm == cTarget then
            matched = m
            break
        end
    end
    if not matched or not matched.Ingredients then return false, 0 end
    for _, ing in ipairs(matched.Ingredients) do
        if ing.Item == "Stinger" then
            local invCount = countItem("Stinger", data)
            local deficit = ing.Amount - invCount
            if deficit > 0 then
                return true, deficit
            end
        end
    end
    return false, 0
end

local function findMissingMaterial(item, neededAmount, data, beeCount)
    local invCount = countItem(item, data)
    local deficit = neededAmount - invCount
    if deficit <= 0 then return nil end

    if getgenv then
        local g = getgenv()
        local cleanKey = tostring(item):gsub("%s+", "")
        local cItem = tostring(item):gsub("[%s%-_']", ""):lower()
        if (cItem == "glitter" or cItem == "glitters") and (g.SkipGlitter or g.HasGlitter) then
            return nil
        end
        if g["Skip" .. cleanKey] or g["Has" .. cleanKey] then
            return nil
        end
        if g.SkipUnfarmable and not getRecipe(item) and not getFarmField(item, beeCount) then
            return nil
        end
    end

    local recipe = getRecipe(item)
    if recipe then
        local firstUnfarmMat, firstUnfarmAmt = nil, 0
        for _, sub in ipairs(recipe) do
            local totalSubNeeded = deficit * sub.Amount
            local missingMat, missingAmt, targetField, isUnfarm = findMissingMaterial(sub.Item, totalSubNeeded, data, beeCount)
            if targetField then
                return missingMat, missingAmt, targetField, false
            elseif isUnfarm and not firstUnfarmMat then
                firstUnfarmMat, firstUnfarmAmt = missingMat, missingAmt
            end
        end
        if firstUnfarmMat then
            return firstUnfarmMat, firstUnfarmAmt, nil, true
        end
    else
        local field = getFarmField(item, beeCount)
        if field then
            return item, deficit, field, false
        else
            return item, deficit, nil, true
        end
    end
    return nil
end

local function isRouteStep(step)
    if type(step) ~= "table" then return false end
    if step.purchase or step.Purchase then return true end
    local st = tostring(step.Type or step.type or ""):lower()
    if st == "purchase" or st == "buy" or st == "craft" or st == "field" or st == "event bee" or st == "eventbee" or st == "codes" then return true end
    if step.config == "farming.field1" or step.group or step.target or step.gear or step.data or step.Data then return true end
    return false
end

local function collectPurchases(tbl, depth)
    if type(tbl) ~= "table" or ((depth or 0) > 8) then return nil end
    local items = {}
    local seen = {}

    -- chi nhan item co trong DEFAULT_ROUTE; bo qua icon/asset id/field name
    local function addItem(raw, bees)
        if type(raw) == "string" then
            local canonical = toItemName(raw)
            if canonical and isRouteItem(canonical) then
                items[#items + 1] = { Name = canonical, Bees = bees }
            end
        elseif type(raw) == "table" then
            local nm = raw.Name or raw.Item or raw.Target or raw.Gear
            if type(nm) == "string" then
                local canonical = toItemName(nm)
                if canonical and isRouteItem(canonical) then
                    local copy = {}
                    for k, v in pairs(raw) do copy[k] = v end
                    copy.Name = canonical
                    items[#items + 1] = copy
                end
            end
        end
    end

    local function scan(t, d)
        if type(t) ~= "table" or d > 8 then return end
        if seen[t] then return end
        seen[t] = true

        if t.config == "farming.field1" and t.data and type(t.data) == "string" then
            local reqBees = tonumber(t.required_bees or t.Bees) or 0
            routeFields[reqBees] = t.data
        end

        local p = t.purchase or t.Purchase
        if p then
            local reqBees = tonumber(t.required_bees or t.Bees or t.req_bees) or 0
            if type(p) == "table" then
                for _, itm in ipairs(p) do
                    addItem(itm, reqBees)
                end
            elseif type(p) == "string" then
                addItem(p, reqBees)
            end
        end

        local stepType = tostring(t.Type or t.type or ""):lower()
        if (stepType == "purchase" or stepType == "buy" or stepType == "craft") and (t.Data or t.data) then
            local data = t.Data or t.data
            local reqBees = tonumber(t.Bees or t.required_bees or t.req_bees) or 0
            if type(data) == "table" then
                for _, itm in ipairs(data) do
                    addItem(itm, reqBees)
                end
            elseif type(data) == "string" then
                addItem(data, reqBees)
            end
        end

        local directName = t.target or t.Target or t.gear or t.Gear
        if directName and type(directName) == "string" then
            local reqBees = tonumber(t.Bees or t.required_bees) or 0
            addItem(directName, reqBees)
        end

        if #t > 0 then
            for i = 1, #t do
                if type(t[i]) == "table" then
                    scan(t[i], d + 1)
                end
            end
        end

        local keys = {}
        for k, v in pairs(t) do
            if type(k) ~= "number" and type(v) == "table" and k ~= "_G" and k ~= "shared" and k ~= "game" and k ~= "workspace" and k ~= "Enum" then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            scan(t[k], d + 1)
        end
    end

    scan(tbl, 0)
    if #items > 0 then return items end

    if #tbl > 0 and type(tbl[1]) == "string" then
        return tbl
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Atlas route steps: giu dung thu tu va dung loai buoc
-- (Codes / Field / Event Bee / Purchase) thay vi chi lay gear.
-- Gom vao 1 bang de khong vuot gioi han 200 local cua chunk chinh.
-- ---------------------------------------------------------------------------
-- Global on purpose: this block is inside the Progression IIFE, but the roll
-- loop and event-jelly helpers below run at chunk scope and need the same table.
RouteSteps = { cache = {} }
-- countItem/getStatData are locals of this Progression IIFE, but the event
-- jelly helpers below run at chunk scope. Expose the two they need.
RouteSteps.countItem = countItem
RouteSteps.getStatData = getStatData

RouteSteps.kindByType = {
    codes = "Code", code = "Code",
    field = "Field", fields = "Field",
    ["event bee"] = "EventBee", eventbee = "EventBee", ["event bees"] = "EventBee",
    purchase = "Purchase", purchases = "Purchase", buy = "Purchase", craft = "Purchase",
}

function RouteSteps.kindOf(group)
    if type(group) ~= "table" then return nil end
    return RouteSteps.kindByType[tostring(group.Type or group.type or ""):lower()]
end

function RouteSteps.push(steps, seen, kind, rawName, bees)
    if not kind or type(rawName) ~= "string" then return end
    local name = rawName:gsub("^%s+", ""):gsub("%s+$", "")
    if #name < 1 or #name > 80 then return end
    local key = kind .. "\0" .. name:lower()
    if seen[key] then return end
    seen[key] = true
    steps[#steps + 1] = { Kind = kind, Name = name, Bees = tonumber(bees) or 0 }
end

function RouteSteps.build(rawRoute)
    local steps, seen = {}, {}
    for _, group in ipairs(type(rawRoute) == "table" and rawRoute or {}) do
        local kind = RouteSteps.kindOf(group)
        if kind then
            local bees = group.Bees
            local d = group.Data
            if type(d) == "string" then
                RouteSteps.push(steps, seen, kind, d, bees)
            elseif type(d) == "table" then
                for _, v in ipairs(d) do
                    if type(v) == "string" then RouteSteps.push(steps, seen, kind, v, bees) end
                end
                if #d == 0 then
                    for k, v in pairs(d) do
                        if type(v) == "string" then
                            RouteSteps.push(steps, seen, kind, v, bees)
                        elseif type(v) == "table" and type(v.Name) == "string" then
                            RouteSteps.push(steps, seen, kind, v.Name, bees)
                        elseif type(k) == "string" then
                            RouteSteps.push(steps, seen, kind, k, bees)
                        end
                    end
                end
            end
        end
    end
    return steps
end

function RouteSteps.findByName(rawName)
    if not rawName then return nil end
    local low = tostring(rawName):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if low == "" then return nil end
    for _, s in ipairs(RouteSteps.cache) do
        if s.Name:lower() == low then return s end
    end
    return nil
end

local function findRouteInMemory()
    local settings = findAtlasSettings()
    if settings then
        if settings.toys and type(settings.toys) == "table" and settings.toys.route then
            return settings.toys.route
        end
        if settings.route and type(settings.route) == "table" then
            return settings.route
        end
    end

    local roots = dropNils({ getgenv and getgenv(), _G, shared }, 3)
    for _, r in ipairs(roots) do
        if type(r) == "table" then
            if r.Atlas and type(r.Atlas) == "table" then
                if r.Atlas.Route and type(r.Atlas.Route) == "table" then return r.Atlas.Route end
                if r.Atlas.Toys and type(r.Atlas.Toys) == "table" and r.Atlas.Toys.route then return r.Atlas.Toys.route end
                if r.Atlas.Settings and type(r.Atlas.Settings) == "table" then
                    if r.Atlas.Settings.toys and r.Atlas.Settings.toys.route then return r.Atlas.Settings.toys.route end
                    if r.Atlas.Settings.route then return r.Atlas.Settings.route end
                end
            end
            if r.AtlasRoute and type(r.AtlasRoute) == "table" then return r.AtlasRoute end
            if r.Route and type(r.Route) == "table" and (#r.Route > 0 or r.Route.purchase) then return r.Route end
            if r.ProgressionRoute and type(r.ProgressionRoute) == "table" then return r.ProgressionRoute end
        end
    end

    if getgc and (tick() - lastGcScan.route > 60) then
        lastGcScan.route = tick()
        local ok, gc = pcall(getgc, true)
        if not ok or type(gc) ~= "table" then ok, gc = pcall(getgc) end
        if ok and type(gc) == "table" then
            for _, obj in ipairs(gc) do
                if type(obj) == "table" then
                    if obj.toys and type(obj.toys) == "table" and obj.toys.route then
                        return obj.toys.route
                    end
                    if obj.route and type(obj.route) == "table" then
                        local rt = obj.route
                        if type(rt) == "table" and #rt > 0 then
                            for _, step in ipairs(rt) do
                                if isRouteStep(step) then return rt end
                            end
                        end
                    end
                    if #obj > 0 and type(obj[1]) == "table" then
                        for _, step in ipairs(obj) do
                            if isRouteStep(step) then return obj end
                        end
                    end
                end
            end
        end
    end

    return nil
end

local lastRouteFile = "none"
local routeSourceName = "none"

-- doc config cua Atlas trong workspace de lay route

configState = configState or {
    path = nil, content = nil, route = nil, routeN = 0, routePath = nil,
    profile = nil, scannedAt = 0, reasons = {}, candidates = {}, ambiguous = false,
}

local POINTER_KEYS = {
    selected = true, current = true, last = true, autoload = true, lastconfig = true,
    selected_profile = true, selected_preset = true, profile = true, preset = true,
    config = true, config_name = true, currentconfig = true, currentprofile = true,
}

local function normPath(p)
    p = tostring(p):gsub("\\", "/"):gsub("^%./", ""):gsub("/+$", "")
    return p
end

local function baseName(p)
    return tostring(p):match("([^/]+)$") or tostring(p)
end

local function stripExt(n)
    return (tostring(n):gsub("%.[%w_]+$", ""))
end

local function cleanKey(s)
    return (tostring(s):lower():gsub("[%s%-_%.]", ""))
end

local function listDir(path)
    if not listfiles then return {} end
    local ok, res = pcall(listfiles, path)
    if not ok or type(res) ~= "table" then return {} end
    local out = {}
    for _, f in ipairs(res) do out[#out + 1] = normPath(f) end
    return out
end

local function fsIsFile(p)
    if not isfile then return false end
    local ok, r = pcall(isfile, p)
    return ok and r == true
end

local function fsIsFolder(p)
    if isfolder then
        local ok, r = pcall(isfolder, p)
        if ok then return r == true end
    end
    return not fsIsFile(p) and #listDir(p) > 0
end

local function safeRead(p)
    if not readfile then return nil end
    local ok, c = pcall(readfile, p)
    if ok and type(c) == "string" then return c end
    return nil
end

local function discoverAtlasRoots()
    local roots, seen = {}, {}
    local function add(p)
        p = normPath(p)
        if not seen[p] then seen[p] = true; roots[#roots + 1] = p end
    end

    local g = getgenv and getgenv() or nil
    if g and type(g.AtlasConfigDir) == "string" then add(g.AtlasConfigDir) end

    add("")
    add(".")
    add("atlas")
    add("Atlas")

    local top = listDir("")
    if #top == 0 then top = listDir(".") end
    for _, entry in ipairs(top) do
        if baseName(entry):lower():find("atlas", 1, true) and not fsIsFile(entry) then
            add(entry)
        end
    end

    for _, name in ipairs({ "atlas1", "Atlas", "atlas", "AtlasBSS", "Atlas BSS" }) do
        if not seen[name] and fsIsFolder(name) then add(name) end
    end
    return roots
end

local function collectFiles(dir, depth, out)
    if depth > 4 or #out >= 200 then return end
    for _, entry in ipairs(listDir(dir)) do
        if #out >= 200 then return end
        if fsIsFile(entry) then
            out[#out + 1] = entry
        else
            collectFiles(entry, depth + 1, out)
        end
    end
end

local function decodeConfig(content)
    if type(content) ~= "string" or #content < 2 or #content > 2000000 then return nil end
    content = content:gsub("^\239\187\191", "")
    local first = content:match("^%s*(.)")
    if first ~= "{" and first ~= "[" then return nil end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(content) end)
    if ok and type(decoded) == "table" then return decoded end
    return nil
end

local function countRouteSteps(arr)
    local n = 0
    for i = 1, #arr do
        if isRouteStep(arr[i]) then n = n + 1 end
    end
    return n
end

-- tim route trong cay json: uu tien key "route", sau do la mang nhieu step nhat
local function findRouteInTree(tree)
    if type(tree) ~= "table" then return nil, 0, nil end
    if tree.toys and type(tree.toys) == "table" and type(tree.toys.route) == "table" and #tree.toys.route > 0 then
        return tree.toys.route, countRouteSteps(tree.toys.route), "$.toys.route"
    end
    if type(tree.route) == "table" and #tree.route > 0 then
        return tree.route, countRouteSteps(tree.route), "$.route"
    end
    local best, bestScore, bestN, bestPath = nil, 0, 0, nil
    local seen = {}
    local function walk(t, key, path, d)
        if type(t) ~= "table" or seen[t] or d > 10 then return end
        seen[t] = true
        local n = (#t > 0) and countRouteSteps(t) or 0
        local score = n
        local isRouteKey = type(key) == "string" and key:lower():find("route", 1, true) ~= nil
        if isRouteKey and next(t) ~= nil then score = score + 500 end
        if score > bestScore and (n > 0 or isRouteKey) then
            best, bestScore, bestN, bestPath = t, score, n, path
        end
        for k, v in pairs(t) do
            if type(v) == "table" then walk(v, k, path .. "." .. tostring(k), d + 1) end
        end
    end
    walk(tree, nil, "$", 0)
    return best, bestN, bestPath
end

-- gom gia tri don gian de so voi settings dang chay
local function flattenScalars(t, prefix, out, d, seen)
    if type(t) ~= "table" or d > 4 or seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
        local ks = tostring(k):lower()
        if not ks:find("field", 1, true) and not ks:find("route", 1, true) then
            local p = prefix .. "." .. ks
            local tv = type(v)
            if tv == "string" or tv == "number" or tv == "boolean" then
                out[p] = v
            elseif tv == "table" then
                flattenScalars(v, p, out, d + 1, seen)
            end
        end
    end
end

local function similarityToLive(decoded, live)
    if type(live) ~= "table" then return 0, 0 end
    local a, b = {}, {}
    pcall(flattenScalars, decoded, "", a, 0, {})
    pcall(flattenScalars, live, "", b, 0, {})
    local same, total = 0, 0
    for p, v in pairs(b) do
        if a[p] ~= nil then
            total = total + 1
            if a[p] == v then same = same + 1 end
        end
    end
    return same, total
end

local function getLiveProfileName()
    local settings = findAtlasSettings()
    if not settings then return nil end
    for _, k in ipairs({ "selected_profile", "profile", "preset", "selected_preset", "config_name" }) do
        local v = settings[k]
        if type(v) == "string" and v ~= "" then return v end
    end
    return nil
end

local function scanAtlasConfigs()
    local roots = discoverAtlasRoots()
    local files = {}
    for _, r in ipairs(roots) do collectFiles(r, 0, files) end
    for _, entry in ipairs(listDir("")) do
        if fsIsFile(entry) and entry:lower():match("%.json$") then
            local low = baseName(entry):lower()
            if not low:match("^atlas%-") and not low:match("^atlascache") then
                files[#files + 1] = entry
            end
        end
    end

    local g = getgenv and getgenv() or nil
    local customPath = g and (g.AtlasConfigPath or g.AtlasRouteFile or g.AtlasPresetFile)
    if type(customPath) == "string" and fsIsFile(customPath) then
        table.insert(files, 1, normPath(customPath))
    end

    local liveSettings = findAtlasSettings()
    local liveProfile = getLiveProfileName()
    local liveProfileKey = liveProfile and cleanKey(stripExt(baseName(liveProfile))) or nil

    local cands, pointers, seenPath = {}, {}, {}
    for _, path in ipairs(files) do
        if not seenPath[path] then
            seenPath[path] = true
            local content = safeRead(path)
            local decoded = content and decodeConfig(content)
            if decoded then
                for k, v in pairs(decoded) do
                    if type(k) == "string" and POINTER_KEYS[k:lower()] and type(v) == "string" and v ~= "" then
                        pointers[cleanKey(stripExt(baseName(v)))] = k
                    end
                end
                local route, n, rpath = findRouteInTree(decoded)
                if route then
                    cands[#cands + 1] = {
                        path = path, content = content, decoded = decoded,
                        route = route, routeN = n, routePath = rpath,
                        key = cleanKey(stripExt(baseName(path))), score = 0, reasons = {},
                    }
                end
            end
        end
    end

    for _, c in ipairs(cands) do
        if type(customPath) == "string" and c.path == normPath(customPath) then
            c.score = c.score + 10000; c.reasons[#c.reasons + 1] = "user override (AtlasConfigPath)"
        end
        if liveProfileKey and c.key == liveProfileKey then
            c.score = c.score + 1000; c.reasons[#c.reasons + 1] = "matches the live profile name: " .. tostring(liveProfile)
        end
        if pointers[c.key] then
            c.score = c.score + 600; c.reasons[#c.reasons + 1] = "pointed to by key '" .. pointers[c.key] .. "'"
        end
        if liveSettings then
            local same, total = similarityToLive(c.decoded, liveSettings)
            if total >= 3 then
                local ratio = same / total
                c.score = c.score + math.floor(ratio * 300)
                c.reasons[#c.reasons + 1] = string.format("matches live settings %d/%d", same, total)
            end
        end
        if c.key == "default" then c.score = c.score - 500 end
        c.score = c.score + math.min(c.routeN, 50) * 0.1
    end

    table.sort(cands, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.path < b.path
    end)

    local ambiguous = #cands > 1 and (cands[1].score - cands[2].score) < 1
    return cands, ambiguous, liveProfile, roots, #files
end


-- Atlas luu preset dang chon vao file atlas-<id>.json (noi dung la ten file preset)
local function findPointerFiles()
    local found, seen = {}, {}
    local function scan(dir)
        for _, entry in ipairs(listDir(dir)) do
            local low = baseName(entry):lower()
            if low:match("^atlas%-.+%.json$") and not seen[entry] and fsIsFile(entry) then
                seen[entry] = true
                found[#found + 1] = entry
            end
        end
    end
    scan("")
    if #found == 0 then scan(".") end
    return found
end

local function pickPointerFile(files)
    if #files == 0 then return nil, false end
    if #files == 1 then return files[1], false end
    local pn = tostring(player.Name):lower()
    local uid = tostring(player.UserId)
    for _, f in ipairs(files) do
        local low = baseName(f):lower()
        if low == "atlas-" .. pn .. ".json" then return f, false end
    end
    for _, f in ipairs(files) do
        local low = baseName(f):lower()
        if low == "atlas-" .. uid .. ".json" then return f, false end
    end
    for _, f in ipairs(files) do
        local low = baseName(f):lower()
        if low:find(pn, 1, true) then return f, false end
    end
    for _, f in ipairs(files) do
        local low = baseName(f):lower()
        if low:find(uid, 1, true) then return f, false end
    end
    table.sort(files)
    return files[1], true
end

local function resolvePresetFromPointer()
    local g = getgenv and getgenv() or nil
    local files = findPointerFiles()
    if g and type(g.AtlasPointerFile) == "string" and fsIsFile(g.AtlasPointerFile) then
        files = { normPath(g.AtlasPointerFile) }
    end
    local ptr, amb = pickPointerFile(files)
    if not ptr then return nil end
    local raw = safeRead(ptr)
    if not raw then return nil end
    local name = raw:gsub("^\239\187\191", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    name = name:gsub('^"(.*)"$', "%1")
    if name == "" then return nil end
    if not name:lower():find("%.json$") then name = name .. ".json" end

    local base = baseName(name)
    local tries = { name, base, "atlas/" .. base, "Atlas/" .. base }
    for _, r in ipairs(discoverAtlasRoots()) do
        if r ~= "" and r ~= "." then
            tries[#tries + 1] = r .. "/" .. base
        end
    end
    for _, p in ipairs(tries) do
        if fsIsFile(p) then return p, ptr, amb, base end
    end
    return nil, ptr, amb, base
end

local warnedNoRoute = nil

local function readRouteFile()
    if not (readfile and isfile) then return nil end

    local now = tick()

    -- uu tien doc file con tro de biet preset dang dung
    local okP, presetPath, ptrPath, ptrAmb, presetName = pcall(resolvePresetFromPointer)
    if okP and ptrPath then
        configState.pointer = ptrPath
        configState.pointerAmbiguous = ptrAmb
        configState.roots = configState.roots or discoverAtlasRoots()
        if presetPath then
            local content = safeRead(presetPath)
            if content and configState.viaPointer and configState.path == presetPath and configState.content == content and configState.route then
                lastRouteFile = presetPath
                return configState.route
            end
            local decoded = content and decodeConfig(content)
            local route, n, rpath
            if decoded then route, n, rpath = findRouteInTree(decoded) end

            local diag
            if not route then
                if not content then diag = "readfile failed"
                elseif #content == 0 then diag = "file is empty"
                elseif not decoded then diag = string.format("bad / half-written JSON (len=%d, head=%q)", #content, content:sub(1, 40))
                else diag = "JSON ok but no route found" end
            end

            -- Atlas co the dang ghi file, giu route cu va thu lai
            if not route and configState.path == presetPath and configState.route and (configState.failCount or 0) < 3 then
                configState.failCount = (configState.failCount or 0) + 1
                configState.lastFail = diag
                lastRouteFile = presetPath
                warn(string.format("[Auto Prog] Temporary preset read error (%s) - keeping the previous route, attempt %d/3", diag, configState.failCount))
                return configState.route
            end
            configState.failCount = route and 0 or ((configState.failCount or 0) + 1)
            configState.lastFail = diag
            local changed = configState.path ~= presetPath
            configState.viaPointer = true
            configState.path, configState.content = presetPath, content
            configState.route, configState.routeN, configState.routePath = route, n or 0, rpath
            configState.reasons = { "pointer file " .. ptrPath .. " -> " .. tostring(presetName) }
            configState.candidates = {}
            configState.ambiguous = ptrAmb == true
            lastRouteFile = presetPath
            if changed then
                print(string.format("[Auto Prog] Atlas preset in use: %s (via %s)", presetPath, ptrPath))
            end
            if route then
                if changed then print(string.format("[Auto Prog] Route @ %s (%d step)", tostring(rpath), tonumber(n) or 0)) end
                return route
            end
            if warnedNoRoute ~= presetPath then
                warnedNoRoute = presetPath
                warn("[Auto Prog] Active preset has no recognizable route: " .. presetPath .. " (" .. tostring(diag) .. ")")
            end
            return nil
        end
        warn("[Auto Prog] Pointer file points to a missing preset: " .. tostring(presetName))
    end
    configState.viaPointer = false

    local liveProfile = getLiveProfileName()

    -- file chua doi thi khoi quet lai
    if configState.path and configState.route and now - configState.scannedAt < 120 and configState.profile == liveProfile then
        local cur = safeRead(configState.path)
        if cur and cur == configState.content then
            lastRouteFile = configState.path
            return configState.route
        end
    end

    local cands, ambiguous, profile, roots, nFiles = scanAtlasConfigs()
    configState.scannedAt = now
    configState.profile = profile
    configState.candidates = cands
    configState.ambiguous = ambiguous
    configState.roots = roots
    configState.fileCount = nFiles

    local top = cands[1]
    if not top then
        configState.path, configState.content, configState.route, configState.reasons = nil, nil, nil, {}
        return nil
    end

    local changed = configState.path ~= top.path
    configState.path, configState.content = top.path, top.content
    configState.route, configState.routeN, configState.routePath = top.route, top.routeN, top.routePath
    configState.reasons = top.reasons
    lastRouteFile = top.path

    if changed then
        print(string.format("[Auto Prog] Active Atlas config: %s (route @ %s, %d steps)", tostring(top.path), tostring(top.routePath), tonumber(top.routeN) or 0))
        if ambiguous then
            warn("[Auto Prog] Several configs have routes and the active one is ambiguous. Set getgenv().AtlasConfigPath = \"path/to/file.json\" to pick one manually.")
        end
    end
    return top.route
end

local function getCustomRoute()
    local roots = dropNils({ getgenv and getgenv(), _G, shared }, 3)
    for _, r in ipairs(roots) do
        if type(r) == "table" then
            local cr = r.CustomRoute or r.UserRoute or r.AtlasCustomRoute
            if cr ~= nil then
                if type(cr) == "string" then
                    local s, decoded = pcall(function() return HttpService:JSONDecode(cr) end)
                    if s and type(decoded) == "table" then
                        return decoded
                    end
                elseif type(cr) == "table" then
                    return cr
                end
            end
        end
    end
    return nil
end

local routeCache = nil
local routeCacheTime = 0
local routeFound = false
local lastCustomRoute = nil

local function getRoute()
    local customUserRoute = getCustomRoute()
    if customUserRoute ~= lastCustomRoute then
        lastCustomRoute = customUserRoute
        routeCache = nil
    end

    if routeCache and (tick() - routeCacheTime < 30) then
        return routeCache
    end

    for k in pairs(routeFields) do
        routeFields[k] = nil
    end
    for k, v in pairs(BASE_ROUTE_FIELDS) do
        routeFields[k] = v
    end

    local rawRoute, routeSrc
    if customUserRoute then
        rawRoute, routeSrc = customUserRoute, "custom"
    else
        local preferMemory = getgenv and getgenv().AtlasRouteSource == "memory"
        local function tryFile()
            local okF, r = pcall(readRouteFile)
            if okF and r then return r, "file:" .. tostring(lastRouteFile) end
            if not okF then warn("[Auto Prog] config scan error: " .. tostring(r)) end
            return nil
        end
        local function tryMemory()
            local okM, r = pcall(findRouteInMemory)
            if okM and r then return r, "memory" end
            return nil
        end
        -- Uu tien doc route ngam tu memory (nhanh, khong can doc file)
        rawRoute, routeSrc = tryMemory()
        if not rawRoute then rawRoute, routeSrc = tryFile() end
    end
    routeSourceName = routeSrc or "none"
    RouteSteps.cache = rawRoute and RouteSteps.build(rawRoute) or {}
    local rawItemsList = rawRoute and collectPurchases(rawRoute, 0)

    if rawItemsList and type(rawItemsList) == "table" and #rawItemsList > 0 then
        local itemMap = {}
        for _, entry in ipairs(DEFAULT_ROUTE) do
            local clean = entry.Name:gsub("[%s%-_']", ""):lower()
            itemMap[clean] = entry
        end

        local dynamicRoute = {}
        for _, rawItem in ipairs(rawItemsList) do
            local name = (type(rawItem) == "table" and (rawItem.Name or rawItem.Item or rawItem.Target or rawItem.Gear)) or (type(rawItem) == "string" and rawItem)
            local reqBees = (type(rawItem) == "table" and (rawItem.Bees or rawItem.BeeCount or rawItem.ReqBees))
            if name then
                local canonical = toItemName(name) or name
                local cleanName = tostring(canonical):gsub("[%s%-_']", ""):lower()
                local base = itemMap[cleanName]
                local rBees = tonumber(reqBees)
                local itemBees = (rBees and rBees > 0 and rBees) or (base and base.Bees) or 0
                table.insert(dynamicRoute, {
                    Name = base and base.Name or tostring(canonical),
                    Type = base and base.Type or "Gear",
                    Bees = itemBees,
                    Honey = base and base.Honey or nil,
                    Ingredients = base and base.Ingredients or nil
                })
            end
        end
        do
            local dedup, seenN = {}, {}
            for _, m in ipairs(dynamicRoute) do
                local ck = tostring(m.Name):gsub("[%s%-_']", ""):lower()
                if not seenN[ck] then
                    seenN[ck] = true
                    dedup[#dedup + 1] = m
                end
            end
            dynamicRoute = dedup
        end
        if #dynamicRoute > 0 then
            routeFound = true
            routeCache = dynamicRoute
            routeCacheTime = tick()
            return dynamicRoute
        end
    end

    routeFound = true
    routeCache = DEFAULT_ROUTE
    routeCacheTime = tick()
    routeSourceName = "default_fallback"
    return DEFAULT_ROUTE
end

local targetSource = "none"
local liveNonGear = false

local nextItemCache = { at = 0, val = nil, raw = nil, nonGear = false }

local function isOwnUI(obj)
    if not obj then return false end
    local name = tostring(obj.Name or "")
    if name == "AutoProg_HUD" or name == "AutoProg_RouteFlowModal" or name == "IvyisUI" or name == "AutoProg" then
        return true
    end
    if obj:FindFirstAncestor("IvyisUI") or obj:FindFirstAncestor("AutoProg_HUD") or obj:FindFirstAncestor("AutoProg_RouteFlowModal") then
        return true
    end
    return false
end

-- doc dong "Next item: ..." trong text cua Atlas
local function parseNextItemLine(line)
    local m = line:match("[Nn]ext%s+[Ii]tem%s*[:%-]%s*(.+)")
    if not m then return nil end
    m = m:gsub("^%s+", ""):gsub("%s+$", "")
    local cleanPart = m:match("^[^\r\n:]+") or m
    cleanPart = cleanPart:gsub("%s+[Nn]ext.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if cleanPart == "" or cleanPart == "?" then return nil end
    local bare = cleanPart:gsub("%s*%b()%s*$", ""):gsub("%s+$", "")
    if bare == "" then bare = cleanPart end

    -- 1) buoc Purchase trong route Atlas (bo qua Codes / Field / Event Bee)
    local step = RouteSteps.findByName(bare) or RouteSteps.findByName(cleanPart) or RouteSteps.findByName(m)
    if step then
        if step.Kind == "Purchase" then return (toItemName(step.Name) or step.Name), m end
        -- nhan nay la buoc khac gear (code / field / event bee): Atlas dang khong che gear
        return nil, m, true
    end

    -- 1b) Atlas co the hien "Event Bee: Tabby", "Field: ..." hoac "Code: ..."
    -- thay vi ten buoc. Cac tien to nay khong bao gio la gear.
    local lowPart = cleanPart:lower()
    if lowPart:find("^event%s*bee") or lowPart:find("^code") or lowPart:find("^field")
        or lowPart:find("field$") then
        return nil, m, true
    end

    -- 2) gear item (alias / DEFAULT_ROUTE)
    local res = toItemNameExact(cleanPart)
        or toItemNameExact((cleanPart:gsub("[%s%d]+$", "")))
        or toItemNameExact(m)
        or toItemNameExact((m:gsub("[%s%d]+$", "")))
    if not res then
        local candidate = toItemName(cleanPart) or toItemName(m)
        if candidate and isRouteItem(candidate) then res = candidate end
    end
    if res then return res, m end
    return nil
end

local function scanNextItemIn(root)
    if not root then return nil end
    local okD, descs = pcall(function() return root:GetDescendants() end)
    if not okD or type(descs) ~= "table" then return nil end
    for _, d in ipairs(descs) do
        if not isOwnUI(d) then
            local okC, isText = pcall(function()
                return d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")
            end)
            if okC and isText then
                local okT, rawTxt = pcall(function() return d.Text end)
                if okT and type(rawTxt) == "string" and rawTxt ~= "" and #rawTxt < 2000 then
                    local txt = rawTxt:gsub("<br%s*/?>", "\n"):gsub("<[^>]+>", " ")
                    for line in txt:gmatch("[^\r\n]+") do
                        local res, m, nonGear = parseNextItemLine(line)
                        if res then return res, m, false end
                        if nonGear then return nil, m, true end
                    end
                end
            end
        end
    end
    return nil
end

local function getUiRoots()
    local uiRoots = {}
    pcall(function() if gethui then table.insert(uiRoots, gethui()) end end)
    pcall(function() table.insert(uiRoots, CoreGui) end)
    pcall(function() table.insert(uiRoots, player:FindFirstChild("PlayerGui")) end)
    return uiRoots
end

-- cua so Atlas: Frame co TabButtons + Tab (noi dung chi duoc dung khi mo tab)
local atlasWindowCache = nil
local function findAtlasWindow()
    if atlasWindowCache and atlasWindowCache.Parent then return atlasWindowCache end
    atlasWindowCache = nil
    for _, root in ipairs(getUiRoots()) do
        local okD, descs = pcall(function() return root:GetDescendants() end)
        if okD then
            for _, d in ipairs(descs) do
                if d.Name == "TabButtons" and d.Parent and d.Parent:FindFirstChild("Tab") and not isOwnUI(d) then
                    atlasWindowCache = d.Parent
                    return atlasWindowCache
                end
            end
        end
    end
    return nil
end

local function atlasTabButtons(win)
    local list = {}
    local holder = win and win:FindFirstChild("TabButtons")
    if not holder then return list end
    for _, b in ipairs(holder:GetDescendants()) do
        if b:IsA("TextButton") then
            local key = (b.Text:gsub("<[^>]+>", ""):gsub("[%s%-_']", "")):lower()
            if key ~= "" then list[#list + 1] = { key = key, btn = b } end
        end
    end
    return list
end

local lastPressMethod = "none"

-- Atlas can ~10-20s de load xong UI. Trong luc do khong bam tab de tranh truot.
pcall(function()
    local g = getgenv and getgenv()
    if type(g) ~= "table" then return end
    g.IvyisAtlasBootReady = function()
        local st = g._IvyisAtlasBoot
        if type(st) ~= "table" then return true end
        local elapsed = tick() - (tonumber(st.at) or 0)
        if elapsed < (tonumber(st.min) or 0) then return false end
        if elapsed >= (tonumber(st.max) or 0) then return true end
        return findAtlasWindow() ~= nil
    end
    g.IvyisAtlasBootWaitText = function()
        local st = g._IvyisAtlasBoot
        if type(st) ~= "table" then return "ready" end
        local left = (tonumber(st.min) or 0) - (tick() - (tonumber(st.at) or 0))
        if left > 0 then return string.format("%.0fs (min delay)", left) end
        return "waiting for the Atlas window"
    end
end)

local function pressAtlasButton(btn)
    if not btn then return false end
    local bootFn = getgenv and getgenv().IvyisAtlasBootReady
    if bootFn and not bootFn() then
        local wt = getgenv().IvyisAtlasBootWaitText
        lastPressMethod = "boot delay: " .. tostring(wt and wt() or "waiting for Atlas")
        return false
    end
    -- ban ca 2 signal: co ban Atlas chi connect Activated, co ban chi MouseButton1Click
    local nClick = fireConnections(btn.MouseButton1Click)
    local nAct = fireConnections(btn.Activated)
    if nClick + nAct > 0 then
        lastPressMethod = nClick > 0 and "MouseButton1Click connections" or "Activated connections"
        return true
    end
    if triggerButtonHeadless(btn) then
        lastPressMethod = "Activated/firesignal"
        return true
    end
    -- Android / executor khong co getconnections: tap that vao toa do nut
    if clickElement(btn) then
        lastPressMethod = "synthetic tap (coords)"
        return true
    end
    lastPressMethod = "failed (no click backend)"
    return false
end

-- Atlas chi dung muc "Progression" (nhan Next item) khi tab Toys dang mo.
-- Mo Toys 1 chut, doc nhan roi tra lai tab cu.
local lastTabPeek = 0
local peekFailStreak = 0
local lastGoodNext = { val = nil, raw = nil, at = 0 }
local lastPeekInfo = "not tried yet"
local lastPeekNoWindow = false
local forcePeekNext = false

local function peekNextItemFromToysTab()
    local bootFn = getgenv and getgenv().IvyisAtlasBootReady
    if bootFn and not bootFn() then
        local wt = getgenv().IvyisAtlasBootWaitText
        lastPeekInfo = "boot wait: " .. tostring(wt and wt() or "waiting for Atlas")
        return nil
    end
    local win = findAtlasWindow()
    if not win then
        lastPeekNoWindow = true
        lastPeekInfo = "no Atlas window found"
        return nil
    end
    lastPeekNoWindow = false
    local tabs = atlasTabButtons(win)
    local toysBtn, activeBtn, bestBg = nil, nil, 2
    for _, t in ipairs(tabs) do
        if t.key == "toys" then toysBtn = t.btn end
        local bg = t.btn.BackgroundTransparency
        if bg < bestBg then bestBg = bg; activeBtn = t.btn end
    end
    if not toysBtn then
        lastPeekInfo = "no Toys tab in Atlas window"
        return nil
    end

    local switched = (activeBtn ~= toysBtn)
    local pressUsed = "tab already open"
    if switched then
        if not pressAtlasButton(toysBtn) then
            lastPeekInfo = "cannot press the Toys tab (" .. tostring(lastPressMethod) .. ")"
            return nil
        end
        pressUsed = lastPressMethod
        task.wait(0.5)
    end
    local res, raw, nonGear = scanNextItemIn(win)

    -- At-lan 2: neu chua thay nhan thi tap toa do that (bo qua connection)
    if switched and not res and not nonGear then
        if clickElement(toysBtn, true) then
            task.wait(0.6)
            res, raw, nonGear = scanNextItemIn(win)
            if res or nonGear then pressUsed = "retry: synthetic tap" end
        end
    end

    if switched and activeBtn then
        pressAtlasButton(activeBtn)
        task.wait(0.05)
    end
    lastPressMethod = pressUsed
    if res then
        lastPeekInfo = "read gear: " .. tostring(res)
    elseif nonGear then
        lastPeekInfo = "read route step (not gear): " .. tostring(raw)
    else
        lastPeekInfo = "label empty after switching to Toys"
    end
    return res, raw, nonGear
end

local function readNextItemLabel()
    if tick() - nextItemCache.at < 2 then return nextItemCache.val, nextItemCache.nonGear end
    nextItemCache.at = tick()

    -- nap route Atlas truoc de nhan dien ten gear trong route
    if #RouteSteps.cache == 0 then pcall(getRoute) end

    -- 1) nhan dang hien san tren man hinh (tab Toys dang mo)
    for _, root in ipairs(getUiRoots()) do
        local res, raw, nonGear = scanNextItemIn(root)
        if res then
            nextItemCache.val, nextItemCache.raw, nextItemCache.nonGear = res, raw, false
            lastGoodNext = { val = res, raw = raw, nonGear = false, at = tick() }
            return res, false
        elseif nonGear then
            nextItemCache.val, nextItemCache.raw, nextItemCache.nonGear = nil, raw, true
            -- Remember "non-gear" too (not just gear): a later fallback must not
            -- resurrect an old gear target while Atlas is still on a code/field.
            lastGoodNext = { val = nil, raw = raw, nonGear = true, at = tick() }
            return nil, true
        end
    end

    -- 2) tab Toys dong -> mo ra doc roi dong lai (8s/lan, hoac ngay sau khi vua mua gear)
    -- Trong thoi gian cho Atlas load: khong bam tab.
    local bootFn = getgenv and getgenv().IvyisAtlasBootReady
    if bootFn and not bootFn() then
        nextItemCache.val, nextItemCache.raw, nextItemCache.nonGear = nil, nil, false
        return nil, false
    end
    -- Atlas chua mo -> thu lai nhanh (2.5s) de bat duoc ngay khi Atlas vua load
    local peekInterval = math.min(8 + peekFailStreak * 4, 30)
    if lastPeekNoWindow then peekInterval = 2.5 end
    if forcePeekNext or (tick() - lastTabPeek > peekInterval) then
        forcePeekNext = false
        lastTabPeek = tick()
        local ok, res, raw, nonGear = pcall(peekNextItemFromToysTab)
        if ok and (res or nonGear) then
            peekFailStreak = 0
        elseif lastPeekNoWindow then
            peekFailStreak = 0 -- khong phai loi, chi la Atlas chua mo
        else
            peekFailStreak = peekFailStreak + 1
        end
        if ok and res then
            nextItemCache.val, nextItemCache.raw, nextItemCache.nonGear = res, raw, false
            lastGoodNext = { val = res, raw = raw, nonGear = false, at = tick() }
            return res, false
        elseif ok and nonGear then
            nextItemCache.val, nextItemCache.raw, nextItemCache.nonGear = nil, raw, true
            lastGoodNext = { val = nil, raw = raw, nonGear = true, at = tick() }
            return nil, true
        end
    end

    -- 3) giu trang thai doc duoc gan nhat (toi da 90s) de khong nhay sang nguon khac
    if lastGoodNext.nonGear and tick() - lastGoodNext.at < 90 then
        nextItemCache.val, nextItemCache.raw, nextItemCache.nonGear = nil, lastGoodNext.raw, true
        return nil, true
    end
    if lastGoodNext.val and tick() - lastGoodNext.at < 90 then
        nextItemCache.val, nextItemCache.raw, nextItemCache.nonGear = lastGoodNext.val, lastGoodNext.raw, false
        return lastGoodNext.val, false
    end
    nextItemCache.val, nextItemCache.raw, nextItemCache.nonGear = nil, nil, false
    return nil, false
end

local function getLiveTarget()
    targetSource = "none"
    liveNonGear = false

    local function accept(raw, srcName)
        if raw == nil then return nil end
        local step = RouteSteps.findByName(tostring(raw))
        if step and step.Kind == "Purchase" then
            targetSource = srcName
            return toItemName(step.Name) or step.Name
        end
        local res = toItemName(raw)
        if res and isRouteItem(res) then
            targetSource = srcName
            return res
        end
        return nil
    end

    local uiNext, uiNonGear = readNextItemLabel()
    if uiNext then
        targetSource = "ui: Atlas 'Next item' label"
        return uiNext
    end
    if uiNonGear then
        -- Atlas dang o buoc code / field / event bee: khong tu doan gear theo route
        targetSource = "ui: Atlas next step is not gear"
        liveNonGear = true
        return nil
    end

    local settings = findAtlasSettings()
    if settings then
        local t = settings.toys
        if type(t) == "table" then
            local r = accept(t.target, "settings.toys.target")
                or accept(t.current, "settings.toys.current")
                or accept(t.current_target, "settings.toys.current_target")
                or accept(t.current_purchase, "settings.toys.current_purchase")
            if r then return r end

            -- ten key co the doi giua cac ban Atlas: quet moi key lien quan
            for k, v in pairs(t) do
                if type(v) == "string" then
                    local lk = tostring(k):lower()
                    if lk:find("target", 1, true) or lk:find("current", 1, true) or lk:find("next", 1, true)
                        or lk:find("prog", 1, true) or lk:find("craft", 1, true)
                        or lk:find("purchase", 1, true) or lk:find("item", 1, true) then
                        local rr = accept(v, "settings.toys." .. tostring(k))
                        if rr then return rr end
                    end
                end
            end
        end
        -- cac bang trang thai auto progression (ten goi khac nhau tuy ban Atlas)
        for k, v in pairs(settings) do
            if type(v) == "table" and tostring(k):lower():find("prog", 1, true) then
                for k2, v2 in pairs(v) do
                    if type(v2) == "string" then
                        local rr = accept(v2, "settings." .. tostring(k) .. "." .. tostring(k2))
                        if rr then return rr end
                    end
                end
            end
        end
        local r = accept(settings.target, "settings.target")
        if r then return r end
    end

    local roots = dropNils({ getgenv and getgenv(), _G, shared }, 3)
    local allowUI = true
    for _, r in ipairs(roots) do
        if type(r) == "table" then
            if type(r.Atlas) == "table" then
                local targets = dropNils({ r.Atlas.ProgressionTarget, r.Atlas.CurrentTarget, r.Atlas.Target, r.Atlas.CurrentPurchase }, 4)
                for _, tgt in ipairs(targets) do
                    local res = accept(tgt, "global Atlas.*Target")
                    if res then return res end
                end
            end
            local targets = dropNils({ r.ProgressionTarget, r.CurrentTarget, r.CurrentPurchase, r.Target }, 4)
            for _, tgt in ipairs(targets) do
                local res = accept(tgt, "global *Target")
                if res then return res end
            end
            if r.AutoProgUIScan == false then allowUI = false end
        end
    end

    if settings and settings.toys and type(settings.toys.route) == "table" then
        local pList = collectPurchases(settings.toys.route, 0)
        if pList and #pList > 0 then
            local char = player.Character
            local data = getStatData()
            for _, p in ipairs(pList) do
                local pName = (type(p) == "table" and (p.Name or p.Item or p.Target or p.Gear)) or (type(p) == "string" and p)
                if pName then
                    local resolved = toItemName(pName)
                    if isRouteItem(resolved) and not ownsItem(resolved, "Gear", char, data) then
                        targetSource = "settings.toys.route (first not owned)"
                        return resolved
                    end
                end
            end
        end
    end

    if allowUI then
        local uiRoots = {}
        pcall(function() if gethui then table.insert(uiRoots, gethui()) end end)
        pcall(function() table.insert(uiRoots, CoreGui) end)
        pcall(function() table.insert(uiRoots, player:FindFirstChild("PlayerGui")) end)

        local patterns = {
            "[Tt]arget%s*[:%-]%s*([%w%s%-_']+)",
            "[Cc]urrent%s*[:%-]%s*([%w%s%-_']+)",
            "[Bb]uying%s*[:%-]%s*([%w%s%-_']+)",
            "[Cc]rafting%s*[:%-]%s*([%w%s%-_']+)",
            "[Nn]ext%s*[:%-]%s*([%w%s%-_']+)",
            "[Pp]rogression%s*[:%-]%s*([%w%s%-_']+)",
        }
        for _, root in ipairs(uiRoots) do
            if root then
                for _, desc in ipairs(root:GetDescendants()) do
                    if not isOwnUI(desc) then
                        local okC, isText = pcall(function()
                            return desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox")
                        end)
                        if okC and isText then
                            local rawTxt = desc.Text
                            if rawTxt and rawTxt ~= "" and #rawTxt < 2000 then
                                local txt = rawTxt:gsub("<br%s*/?>", "\n"):gsub("<[^>]+>", " ")
                                for line in txt:gmatch("[^\r\n]+") do
                                    for _, pat in ipairs(patterns) do
                                        local m = line:match(pat)
                                        if m then
                                            local res = toItemNameExact(m)
                                                or toItemNameExact((m:gsub("[%s%d]+$", "")))
                                            if not res then
                                                local candidate = toItemName(m)
                                                if candidate and isRouteItem(candidate) then
                                                    res = candidate
                                                end
                                            end
                                            if res then
                                                targetSource = "ui:" .. desc:GetFullName():sub(-60) .. " = '" .. txt:sub(1, 50) .. "'"
                                                return res
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local lockedTarget = nil
local liveMisses = 0

local function checkIngredients(milestone, data, beeCount)
    if not milestone.Ingredients or #milestone.Ingredients == 0 then
        return nil, 0, nil, false, true
    end

    local firstFarmMat, firstFarmAmt, farmField = nil, 0, nil
    local firstUnfarmMat, firstUnfarmAmt = nil, 0
    local anyMissing = false

    for _, ing in ipairs(milestone.Ingredients) do
        local missingMat, missingAmt, targetField, isUnfarm = findMissingMaterial(ing.Item, ing.Amount, data, beeCount)
        if missingAmt and missingAmt > 0 then
            anyMissing = true
            if targetField then
                if not farmField then
                    firstFarmMat = missingMat
                    firstFarmAmt = missingAmt
                    farmField = targetField
                    break
                end
            elseif isUnfarm and not firstUnfarmMat then
                firstUnfarmMat = missingMat
                firstUnfarmAmt = missingAmt
            end
        end
    end

    if farmField then
        return firstFarmMat, firstFarmAmt, farmField, false, false
    elseif firstUnfarmMat then
        return firstUnfarmMat, firstUnfarmAmt, nil, true, false
    elseif not anyMissing then
        return nil, 0, nil, false, true
    else
        return nil, 0, nil, false, false
    end
end

-- chi con thieu Honey (nguyen lieu da du) thi khong doi field, chi bao thieu Honey
local function honeyDeficitFor(milestone, data)
    local need = tonumber(milestone and milestone.Honey) or 0
    if need <= 0 then return 0 end
    return math.max(0, need - countItem("Honey", data))
end

local function hasTopLevelDeficit(milestone, data)
    for _, ing in ipairs(milestone and milestone.Ingredients or {}) do
        if countItem(ing.Item, data) < ing.Amount then return true end
    end
    return false
end

local function pickNextTarget(data, beeCount)
    local char = player.Character

    local liveTarget = getLiveTarget()
    if liveTarget then
        liveMisses = 0
    elseif liveNonGear then
        -- Atlas dang chay buoc khac (code/field/event bee): giu nguyen gear dang bam
        liveMisses = 0
    else
        liveMisses = liveMisses + 1
        if liveMisses >= 3 then lockedTarget = nil end
    end
    if liveTarget then
        local canonicalLive = toItemName(liveTarget) or liveTarget
        if canonicalLive and isRouteItem(canonicalLive) then
            lockedTarget = canonicalLive
        end
    end

    local firstPendingUnfarm = nil

    if lockedTarget then
        if ownsItem(lockedTarget, "Gear", char, data) then
            lockedTarget = nil
            -- vua mua xong: doc lai nhan Atlas ngay de bam dung item tiep theo.
            -- Xoa cache cu, neu khong no tra lai dung mon vua mua moi tick va
            -- ep peek lien tuc (bam tab Atlas lap lai).
            lastGoodNext = { val = nil, raw = nil, nonGear = false, at = 0 }
            forcePeekNext = true
            nextItemCache.at = 0
        else
            local matchedMilestone = nil
            local cTarget = lockedTarget:gsub("[%s%-_']", ""):lower()
            for _, milestone in ipairs(DEFAULT_ROUTE) do
                local cMilestone = milestone.Name:gsub("[%s%-_']", ""):lower()
                if cTarget == cMilestone then
                    matchedMilestone = milestone
                    break
                end
            end

            if matchedMilestone then
                local mat, amt, field, isUnfarm, isReady = checkIngredients(matchedMilestone, data, beeCount)
                if field then
                    return matchedMilestone.Name, mat, amt, field, false
                elseif isUnfarm then
                    local progField = getRouteField(beeCount)
                    return matchedMilestone.Name, mat, amt, progField, true
                else
                    local honeyDef = honeyDeficitFor(matchedMilestone, data)
                    if isReady and honeyDef > 0 and not hasTopLevelDeficit(matchedMilestone, data) then
                        return matchedMilestone.Name, "Honey", honeyDef, nil, false
                    end
                    local progField = getRouteField(beeCount)
                    return matchedMilestone.Name, nil, 0, progField, false
                end
            else
                local progField = getRouteField(beeCount)
                return lockedTarget, nil, 0, progField, false
            end
        end
    end

    local activeRoute = getRoute()
    for _, milestone in ipairs(activeRoute) do
        local owned = ownsItem(milestone.Name, milestone.Type, char, data)
        if not owned and beeCount >= milestone.Bees then
            local mat, amt, field, isUnfarm, isReady = checkIngredients(milestone, data, beeCount)
            if field then
                return milestone.Name, mat, amt, field, false
            elseif isReady then
                local honeyDef = honeyDeficitFor(milestone, data)
                if honeyDef > 0 and not hasTopLevelDeficit(milestone, data) then
                    return milestone.Name, "Honey", honeyDef, nil, false
                end
                local progField = getRouteField(beeCount)
                return milestone.Name, nil, 0, progField, false
            elseif isUnfarm then
                if not firstPendingUnfarm then
                    firstPendingUnfarm = {
                        Target = milestone.Name,
                        Mat = mat,
                        Amt = amt
                    }
                end
            else
                local progField = getRouteField(beeCount)
                return milestone.Name, mat, amt, progField, false
            end
        end
    end

    if firstPendingUnfarm then
        local progField = getRouteField(beeCount)
        return firstPendingUnfarm.Target, firstPendingUnfarm.Mat, firstPendingUnfarm.Amt, progField, true
    end

    return nil, nil, 0, nil, false
end

local guiParent
pcall(function()
    guiParent = (gethui and gethui()) or CoreGui
end)
if not guiParent then guiParent = player:WaitForChild("PlayerGui") end

pcall(function()
    if guiParent:FindFirstChild("AutoProg_HUD") then guiParent.AutoProg_HUD:Destroy() end
    if CoreGui:FindFirstChild("AutoProg_HUD") then CoreGui.AutoProg_HUD:Destroy() end
end)

local hudGui = Instance.new("ScreenGui")
hudGui.Name = "AutoProg_HUD"
hudGui.ResetOnSpawn = false
hudGui.Parent = guiParent

local hudLabel = Instance.new("TextLabel")
hudLabel.Name = "AutoProg_HUD"
hudLabel.AnchorPoint = Vector2.new(1, 1)
hudLabel.Position = UDim2.new(1, -15, 1, -10)
hudLabel.Size = UDim2.new(0, 600, 0, 20)
hudLabel.BackgroundTransparency = 1
hudLabel.Font = Enum.Font.GothamBold
hudLabel.TextSize = 13
hudLabel.TextColor3 = Color3.fromRGB(255, 65, 65)
hudLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
hudLabel.TextStrokeTransparency = 0
hudLabel.TextXAlignment = Enum.TextXAlignment.Right
hudLabel.Text = "[Auto Prog] Initializing..."
hudLabel.Parent = hudGui

-- dinh dang so de doc: 9,999 / 12.5K / 2.31M / 12.5M / 2.5B / 1.2T
local function formatAmount(value)
    local n = tonumber(value) or 0
    local sign = n < 0 and "-" or ""
    n = math.abs(n)
    if n < 100000 then
        local s = tostring(math.floor(n + 0.5))
        local k
        repeat
            s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        until k == 0
        return sign .. s
    end
    local scaled, suffix
    if n >= 1e12 then
        scaled, suffix = n / 1e12, "T"
    elseif n >= 1e9 then
        scaled, suffix = n / 1e9, "B"
    elseif n >= 1e6 then
        scaled, suffix = n / 1e6, "M"
    else
        scaled, suffix = n / 1e3, "K"
    end
    local text = string.format("%.2f", scaled):gsub("0+$", ""):gsub("%.$", "")
    return sign .. text .. suffix
end

local function findRouteEntry(targetItem)
    if not targetItem or targetItem == "None" then return nil end
    local cTarget = tostring(targetItem):gsub("[%s%-_']", ""):lower()
    for _, m in ipairs(DEFAULT_ROUTE) do
        if tostring(m.Name or ""):gsub("[%s%-_']", ""):lower() == cTarget then
            return m
        end
    end
    local activeRoute = routeCache or getRoute()
    if type(activeRoute) == "table" then
        for _, m in ipairs(activeRoute) do
            if tostring(m.Name or ""):gsub("[%s%-_']", ""):lower() == cTarget then
                return m
            end
        end
    end
    return nil
end

-- tra ve (thieu, dang co, can) cua Honey cho 1 item
local function getHoneyInfo(targetItem, data)
    local matched = findRouteEntry(targetItem)
    local need = tonumber(matched and matched.Honey) or 0
    if need <= 0 then return 0, 0, 0 end
    local have = countItem("Honey", data)
    return math.max(0, need - have), have, need
end

-- thieu nguyen lieu chinh (khong tinh nguyen lieu tho dung de craft)
local function topLevelMissing(targetItem, data)
    local matched = findRouteEntry(targetItem)
    if not matched then return nil end
    for _, ing in ipairs(matched.Ingredients or {}) do
        local have = countItem(ing.Item, data)
        if have < ing.Amount then
            return ing.Item, ing.Amount - have
        end
    end
    local honeyDef, honeyHave, honeyNeed = getHoneyInfo(targetItem, data)
    if honeyDef > 0 then return "Honey", honeyDef, honeyHave, honeyNeed end
    return nil
end

local function describeIngredients(targetItem, data, beeCount, plain)
    if not targetItem or targetItem == "None" then return "None" end
    local matched = findRouteEntry(targetItem)
    if not matched then return "Honey Only" end

    local honeyNeed = tonumber(matched.Honey) or 0
    local hasIngredients = matched.Ingredients and #matched.Ingredients > 0
    if not hasIngredients and honeyNeed <= 0 then return "Honey Only" end

    local lines = {}
    local missing = {}
    local missingSeen = {}
    local honeyLine = nil

    local function markMissing(item, deficit)
        local key = tostring(item)
        if not missingSeen[key] then
            missingSeen[key] = true
            missing[#missing + 1] = string.format("%s %s", key, formatAmount(deficit))
        end
    end

    -- depth 0 = nguyen lieu chinh; depth > 0 = nguyen lieu tho de craft mon chinh
    local function addLine(item, need, depth)
        local have = countItem(item, data)
        local name = plain and tostring(item) or ("**" .. tostring(item) .. "**")
        local pad = depth == 0 and "• " or (string.rep("   ", depth) .. "-> ")
        local deficit = need - have
        if deficit <= 0 then
            lines[#lines + 1] = string.format("%s%s: %s/%s - Enough", pad, name, formatAmount(have), formatAmount(need))
            return
        end
        if depth == 0 then markMissing(item, deficit) end
        local recipe = getRecipe(item)
        if recipe and depth < 4 then
            lines[#lines + 1] = string.format("%s%s: %s/%s - Need %s", pad, name, formatAmount(have), formatAmount(need), formatAmount(deficit))
            for _, sub in ipairs(recipe) do
                addLine(sub.Item, deficit * sub.Amount, depth + 1)
            end
        elseif item == "Stinger" then
            -- stinger lay tu Vicious Bee, script da ho tro
            lines[#lines + 1] = string.format("%s%s: %s/%s - Need %s (Vicious Bee)", pad, name, formatAmount(have), formatAmount(need), formatAmount(deficit))
        elseif getFarmField(item, beeCount or 35) then
            lines[#lines + 1] = string.format("%s%s: %s/%s - Need %s", pad, name, formatAmount(have), formatAmount(need), formatAmount(deficit))
        else
            -- mon khong ho tro (khong craft, khong farm): chi bao thieu
            lines[#lines + 1] = string.format("%s%s: %s/%s - Need %s (can't farm)", pad, name, formatAmount(have), formatAmount(need), formatAmount(deficit))
        end
    end

    if hasIngredients then
        for _, ing in ipairs(matched.Ingredients) do
            addLine(ing.Item, ing.Amount, 0)
        end
    end

    if honeyNeed > 0 then
        local honeyHave = countItem("Honey", data)
        local honeyName = plain and "Honey" or "**Honey**"
        if honeyHave >= honeyNeed then
            honeyLine = string.format("• %s: %s/%s - Enough", honeyName, formatAmount(honeyHave), formatAmount(honeyNeed))
        else
            local deficit = honeyNeed - honeyHave
            honeyLine = string.format("• %s: %s/%s - Need %s", honeyName, formatAmount(honeyHave), formatAmount(honeyNeed), formatAmount(deficit))
            missing[#missing + 1] = string.format("Honey %s", formatAmount(deficit))
        end
        lines[#lines + 1] = honeyLine
    end

    local status
    if #missing == 0 then
        status = "READY TO BUY"
    else
        status = "MISSING: " .. table.concat(missing, ", ")
    end

    -- gioi han so dong de webhook khong vuot gioi han Discord
    if #lines > 38 then
        local kept = {}
        for i = 1, 38 do kept[i] = lines[i] end
        if honeyLine then
            local hasHoney = false
            for _, l in ipairs(kept) do
                if l == honeyLine then hasHoney = true break end
            end
            if not hasHoney then kept[#kept + 1] = honeyLine end
        end
        kept[#kept + 1] = string.format("… +%d more", #lines - 38)
        lines = kept
    end
    lines[#lines + 1] = status
    return table.concat(lines, "\n")
end

local lastWebhookTime = 0
local lastWebhookTarget = nil
local lastWebhookField = nil
local lastWebhookMat = nil

-- lay link webhook + thoi gian gui lai tu getgenv/_G/shared
-- gia tri nhap tu UI (uu tien hon getgenv)
local WebhookState = { url = "", interval = nil, notifyBuy = true, notifyConfig = true, owned = nil, seen = {} }

local function getWebhookSettings()
    local url, interval = nil, 600
    for _, r in ipairs(dropNils({ getgenv and getgenv(), _G, shared }, 3)) do
        if type(r) == "table" then
            if type(r.DiscordWebhookUrl) == "string" and r.DiscordWebhookUrl ~= "" then
                url = r.DiscordWebhookUrl
            elseif type(r.WebhookUrl) == "string" and r.WebhookUrl ~= "" then
                url = r.WebhookUrl
            end
            if tonumber(r.WebhookInterval) then interval = tonumber(r.WebhookInterval) end
        end
    end
    if WebhookState.url ~= "" then url = WebhookState.url end
    if WebhookState.interval then interval = WebhookState.interval end
    return url, interval
end

local function getHttpRequest()
    return (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
end

-- Discord rejects a message over 4000 chars per text display (4096 for an
-- embed description). Ingredients can grow past that, so clip before sending.
function RouteSteps.clip(text, maxLen)
    local s = tostring(text or "")
    local limit = tonumber(maxLen) or 3500
    if #s <= limit then return s end
    return s:sub(1, limit - 3) .. "..."
end

-- Components V2: 1 container gom cac khoi text, phan cach bang separator.
-- blocks = { "## tieu de", "noi dung", "-# footer" } (khoi dau/cuoi khong can separator)
local function buildV2Payload(blocks, color)
    local inner = {}
    for i, text in ipairs(blocks) do
        if i > 1 then
            inner[#inner + 1] = { type = 14, divider = (i == 2), spacing = 1 }
        end
        inner[#inner + 1] = { type = 10, content = text }
    end
    return {
        username = getWebhookTitle(),
        flags = 32768, -- IS_COMPONENTS_V2
        components = { { type = 17, accent_color = color, components = inner } },
    }
end

-- gui V2 truoc, neu Discord tu choi thi gui lai bang embed thuong
local function postWebhook(url, v2Payload, embedPayload)
    local httpRequest = getHttpRequest()
    if not httpRequest or not url or url == "" then return false end

    local function send(target, payload)
        local okEnc, body = pcall(function() return HttpService:JSONEncode(payload) end)
        if not okEnc then return false end
        local ok, res = pcall(httpRequest, {
            Url = target,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
        if not ok then return false end
        if type(res) == "table" then
            local code = tonumber(res.StatusCode)
            if code and code >= 400 then return false end
            if res.Success == false then return false end
        end
        return true
    end

    local v2Url = url .. (url:find("?", 1, true) and "&" or "?") .. "with_components=true"
    if send(v2Url, v2Payload) then return true end
    if embedPayload then return send(url, embedPayload) end
    return false
end

-- bao su kien (mua do, doi config...). kind = "buy" | "config" | nil
local function sendEventWebhook(kind, title, body, color)
    if kind == "buy" and not WebhookState.notifyBuy then return false end
    if kind == "config" and not WebhookState.notifyConfig then return false end
    local url = getWebhookSettings()
    if not url then return false end
    local bodyText = RouteSteps.clip(body, 3500)
    local footer = "Ivyis BSS-" .. tostring(player.Name)
    return postWebhook(url,
        buildV2Payload({
            "## " .. title,
            bodyText,
            string.format("-# %s • <t:%d:R>", footer, os.time()),
        }, color or 3447003),
        {
            username = getWebhookTitle(),
            embeds = { {
                title = title, description = bodyText, color = color or 3447003,
                footer = { text = footer },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            } },
        })
end

local function sendProgressWebhook(beeCount, targetStr, fieldStr, routeStr, data, needStr, isUnfarmable, neededMat)
    local webhookUrl, interval = getWebhookSettings()
    if not webhookUrl or not getHttpRequest() then return end

    local now = tick()
    local stateChanged = (targetStr ~= lastWebhookTarget or fieldStr ~= lastWebhookField or neededMat ~= lastWebhookMat)
    if not stateChanged and (now - lastWebhookTime < interval) then return end
    if stateChanged and (now - lastWebhookTime < 15) then return end

    lastWebhookTime = now
    lastWebhookTarget = targetStr
    lastWebhookField = fieldStr
    lastWebhookMat = neededMat

    local needIngredients = describeIngredients(targetStr, data, beeCount)
    local noteText = ""
    if isUnfarmable then
        noteText = string.format("\n⚠️ **Note:** can't farm `%s` in a field, you need to get it yourself.", tostring(needStr or targetStr or "this item"))
    end

    local bodyText = RouteSteps.clip(string.format(
        "**Bees:** %d\n**Next item:** %s%s\n**Need:**\n%s\n**Field:** %s\n**Route:** %s",
        tonumber(beeCount) or 0, tostring(targetStr), noteText,
        tostring(needIngredients), tostring(fieldStr), tostring(routeStr)
    ), 3500)
    local color = isUnfarmable and 16744448 or 3447003
    local title = getWebhookTitle()
    local footer = "Ivyis BSS-" .. tostring(player.Name)

    postWebhook(webhookUrl,
        buildV2Payload({
            "## " .. title,
            bodyText,
            string.format("-# %s • <t:%d:R>", footer, os.time()),
        }, color),
        {
            username = title,
            embeds = { {
                title = title, description = bodyText, color = color,
                footer = { text = footer },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            } },
        })
end

local function printDebug()
    local data = getStatData()
    local beeCount = getBeeCount(data)
    local liveTarget = getLiveTarget()
    local activeRoute = getRoute()
    print("========== [Auto Prog Debug] ==========")
    print("Bee Count:", beeCount)
    print("Atlas Live Target:", tostring(liveTarget))
    print("Active Latched Target:", tostring(lockedTarget))
    print("Atlas Settings Found:", tostring(findAtlasSettings() ~= nil))
    print("Atlas Window Found:", tostring(findAtlasWindow() ~= nil))
    print("Live Target Source:", tostring(targetSource))
    print("Atlas UI 'Next item' raw:", tostring(nextItemCache.raw), "-> resolved:", tostring(nextItemCache.val))
    print("Atlas Label State:", nextItemCache.nonGear and "not gear (code/field/event bee)" or (nextItemCache.val and "gear" or "none"))
    print("Atlas Peek:", tostring(lastPeekInfo))
    local bootState = (getgenv and getgenv()._IvyisAtlasBoot) or {}
    local bootElapsed = tick() - (tonumber(bootState.at) or tick())
    local bootReadyFn = getgenv and getgenv().IvyisAtlasBootReady
    print(string.format("Atlas Boot: %.1fs elapsed | min %ss, max %ss | ready=%s",
        bootElapsed, tostring(bootState.min), tostring(bootState.max),
        tostring(not bootReadyFn or bootReadyFn())))
    print("Atlas Tab Press:", tostring(lastPressMethod))
    local hasVirtualInput = false
    pcall(function() hasVirtualInput = game:GetService("VirtualInputManager") ~= nil end)
    print("Peek Backend:", (getconnections and "getconnections" or "no getconnections"),
        "| firesignal:", tostring(firesignal ~= nil),
        "| VirtualUser:", tostring(VirtualUser ~= nil),
        "| VirtualInput:", tostring(hasVirtualInput))
    print("Route Source:", tostring(routeSourceName))
    print("Atlas Route Steps (all types):", #RouteSteps.cache)
    for i = 1, math.min(#RouteSteps.cache, 30) do
        local s = RouteSteps.cache[i]
        print(string.format("  step[%d] = [%s] %s (bees>=%s)", tonumber(i) or 0, tostring(s.Kind), tostring(s.Name), tostring(s.Bees)))
    end
    print("Pointer File:", tostring(configState.pointer), "| via pointer:", tostring(configState.viaPointer), "| last read problem:", tostring(configState.lastFail))
    print("Atlas Folders:", table.concat(configState.roots or {}, ", "), "| files scanned:", tostring(configState.fileCount))
    print("Active Config File:", tostring(configState.path), "| route @", tostring(configState.routePath))
    for _, why in ipairs(configState.reasons or {}) do print("  why: " .. why) end
    print("Config candidates with route:", #(configState.candidates or {}), "| ambiguous:", tostring(configState.ambiguous))
    for i, c in ipairs(configState.candidates or {}) do
        if i > 5 then break end
        print(string.format("  cand[%d] %s score=%.1f steps=%d", tonumber(i) or 0, tostring(c.path), tonumber(c.score) or 0, tonumber(c.routeN) or 0))
    end
    print("Route Source Items Count:", #activeRoute)
    for i = 1, math.min(#activeRoute, 15) do
        local m = activeRoute[i]
        print(string.format("  route[%d] = %s (bees>=%s)", tonumber(i) or 0, tostring(m.Name), tostring(m.Bees)))
    end
    if data then
        print("Equipped/Stats:")
        print("  Collector:", tostring(data.Collector or data.Tool))
        print("  Bag:", tostring(data.Bag or data.Backpack))
        print("  Boots:", tostring(data.Boots or data.Shoes))
        print("  Belt:", tostring(data.Belt or data.BeltBag))
        print("  Hat:", tostring(data.Hat or data.Mask))
        print("  Sprinkler:", tostring(data.Sprinkler))
        print("  BlueGuard:", tostring(data.BlueGuard or data.LeftGuard))
        print("  RedGuard:", tostring(data.RedGuard or data.RightGuard))
    else
        print("ClientStatCache: nil")
    end
    print("Ownership Checks:")
    local checkList = { "Hiking Boots", "Beekeeper's Boots", "Looker Guard", "Brave Guard", "Diamond Mask", "Blue Clay Planter", "Red Clay Planter", "Tacky Planter", "Candy Planter", "Petal Planter" }
    for _, itm in ipairs(checkList) do
        print("  " .. itm .. ":", ownsItem(itm, "Gear", player.Character, data))
    end
    print("Material Counts:")
    local matList = { "Glitter", "Oil", "Enzymes", "Glue", "Blue Extract", "Red Extract", "Stinger", "Star Jelly", "Moon Charm" }
    for _, m in ipairs(matList) do
        print("  " .. m .. ":", countItem(m, data))
    end
    local targetItem, neededMat, neededAmt, field, isUnfarmable = pickNextTarget(data, beeCount)
    print("Evaluation Result:")
    print("  Target:", tostring(targetItem))
    print("  Need Mat:", tostring(neededMat), "(" .. tostring(neededAmt) .. ")")
    print("  Unfarmable:", tostring(isUnfarmable))
    print("  Target Field:", tostring(field))
    print("========================================")
end


local STAGE1_CONFIG_RAW = [===[{"hive":{"beetypes":false,"bee":false,"mutas3":false,"stoprjgifted":false,"amount":50,"rjbeetypes":false,"feedtype":"Bitterberry","neonberry":false,"rjrarity":false},"misc":{"mobiletoggle":true,"console":false,"bqbuyconf":false,"followfieldblacklist":false,"anonymous":false,"follow":false,"rolldouble":false,"autorejoin2":false,"bqbuy":false,"bqdel2":false,"realpot":false,"farmmultiplefields":false,"dapperslots":5,"custompatterns":false,"bqdelconf":false},"combat":{"mondochicktime":15,"killmondochick":true,"crabmethod":"Tween","killkingbeetle":true,"killcrab":false,"babylove":true,"donatevials":false,"wlstingers":false,"killScorpion":false,"killtunnelbear":false,"craboil":false,"giftedvicious":false,"killWerewolf":false,"snail":false,"windymax":25,"viciousmin":1,"killMantis":false,"demonmask":false,"lootmondo":true,"killRhinoBeetle":false,"killSpider":false,"windymin":1,"killcommando":false,"viciousmax":6,"stingers":false,"starsaw":false,"killwindy":false,"commandomethod":"Walk","avoidmobs":true,"commandoshell":true,"killvicious":true,"killAphid":true,"commandohelp":false,"dmwhitelist":false,"mondopreptime":20,"mondoprep":false,"killLadybug":false,"wlstarsaw":false},"dispensers":{"coconut":false,"blueberry":false,"royaljelly":false,"treat":false,"strawberry":false,"robopass":false,"glue":false,"honey":false,"antpass":true},"autoquest":{"planters":true,"feedbees":true,"windshrine":true,"rileybee":false,"ragetokens":true,"gummybear":false,"buckobee":false,"treats":true,"enabled":true,"memorymatch":true,"onett":true,"beebear":false,"blackbear2":false,"pollen":true,"sciencebear":true,"puffshrooms":true,"oldtool":false,"goomethod":"Gumdrops","levelbees":true,"sharebeans":true,"pandabear":true,"bestwhitefield":"Sunflower Field","bestredfield":"Mushroom Field","toys":true,"claim2":{"Mother Bear":true,"Polar Bear":true,"Panda Bear":true,"Science Bear":true},"tools":true,"brownbear":false,"ants":true,"blackbear":false,"dapperbear":false,"dupedtokens":true,"mobs":true,"blooms":true,"rj":true,"honeybee":false,"allowedplanters":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true},"craft":true,"goo":true,"xmas":false,"bestbluefield":"Blue Flower Field","stickbug":false,"motherbear":true,"spiritbear":true,"rjbl":false,"polarbear":true},"face":{"balloons":false,"blooms":false,"bubbles":false,"refresh":false,"shiftlock":false,"gballoons":false,"gbubbles":false,"fires":false,"sldirection":"South","center":false,"method":"Shift Lock"},"convert":{"standInPreciseAt":75,"convertHiveBalloon":true,"instantType":false,"convertHoneyAt":100,"coconutAt":85,"convertHoney":true,"resetWhenConverting":false,"convert6xBubbleBloat":false,"festivegift":false,"autoHoneyMask":false,"alwaysConvertBalloon":false,"timeToWait":15,"coconut":false,"waitBeforeConverting":false,"standInPrecise":true,"useEnzymesBalloon":false,"convertField":false,"convertHiveBalloonAt":5,"defaultMask":"Diamond Mask","instantToggle":false},"boosters":{"min":1,"wanted":1,"required":false,"enabled2":false,"allowed":false,"fieldsblacklist":false},"vars":{"walkspeedenabled":true,"movement":"Tween","cannon":false,"tweenspeed":6,"walkspeed":48,"jumpshortcuts":false,"walkspeed2":1.5,"walkdynamic":false},"sprouts":{"enabled":true,"plant":false,"plantday":false,"collect":true,"amount":false,"fieldsblacklist":false,"rarity3":false,"left":0,"plantnight":false},"stickbug":{"enabled":false,"loot":false,"totem":true,"maintain":false,"circle":true,"tickets":false,"spawn":false},"amulet":{"ant":false,"rbc3":false,"kb3":"Bronze","rbc4":false,"ant4":false,"sb3":false,"kb2":false,"star3":false,"sb4":false,"sb":false,"snail4":false,"rbc":false,"sb2":false,"moon4":false,"kb4":{"P2":[],"P3":[],"P1":[]},"rbc2":false,"ant2":false,"snail":false,"ant3":false,"snail2":false,"star4":false,"kb":false,"snail3":false},"memorymatch":{"night":false,"basic":false,"mega":false,"extreme":false,"blacklist":false},"rbc":{"passcooldown":0,"rerollmin":10,"upgrades":false,"mask":false,"rerollquests":false,"redtool":"Dark Scythe","bluemask":"Diamond Mask","cogconvert":false,"cogupgrades":true,"rerollupgrades":false,"materialsenabled":false,"buypass":false,"whitemask":"Gummy Mask","trackmobs":false,"preset":"Blue","disableroundend":false,"maskround":5,"homepage":false,"stoproundend":false,"whitetool":"Gummyballer","highestcogmax":9,"maxround":15,"highestcog":false,"precise":false,"rerollbees":false,"bestwhitefield":"Sunflower Field","bestredfield":"Mushroom Field","bestbluefield":"Blue Flower Field","buydrives":{"Glitched":true,"Red":true,"Blue":true,"White":true},"rerollbeesmax":2,"tool":false,"goldcogmowers":true,"homepagemin":1,"precisemin":5,"enabled":false,"toolround":4,"upgradesenabled":false,"materials":false,"rerollupgmax":2,"goomethod":"Gumdrops","redmask":"Demon Mask","usedrives":{"Glitched":true,"Red":true,"Blue":true,"White":true},"bluetool":"Tide Popper"},"beesmas":[],"detected":[],"antilag":{"stations":true,"precise":true,"balloons":true,"flowers":false,"norender":false,"bssui":false,"dupedtokens":true,"tokens":true,"main":true,"textures":true,"bees":true,"decorations":true,"particles":true,"players":true},"toys":{"windshrine":false,"conversions":2,"stickerprinter":false,"stackselect":false,"enabled":true,"sproutsummoner":false,"meteor":false,"route":[{"Data":["38217","BeesBuzz123","BopMaster","Connoisseur","Crawlers","777","Nectar","Roof","Wax"],"Type":"Codes"},{"Bees":15,"Type":"Codes","Data":"ClubBean"},{"Bees":35,"Type":"Codes","Data":"ThreeBeeVee"},{"Data":["Dandelion Field","Bamboo Field","Pineapple Patch","Pine Tree Forest"],"Type":"Field"},{"Data":["Tabby","Festive","Gummy","Vicious","Puppy"],"Type":"Event Bee"},{"Type":"Purchase","Data":["Backpack","Magnet","Canister","Vacuum","Belt Pocket","Compressor","Super-Scooper","Helmet","Port-O-Hive","Electro-Magnet","Honey Dipper","Propeller Hat","Looker Guard","Brave Guard","Hiking Boots","Belt Bag","Bubble Wand","Basic Sprinkler","PlasticPlanter","Beekeeper's Mask","Beekeeper's Boots","Mondo Belt Bag","Blue Port-O-Hive","Silver Soakers","Elite Blue Guard","Elite Red Guard","CandyPlanter","Glider","Porcelain Dipper","Porcelain Port-O-Hive","Blue ClayPlanter","Red ClayPlanter","Bubble Mask","Cobalt Guard","Golden Gushers","TackyPlanter","Diamond Mask","Honeycomb Belt","Crimson Guard","Diamond Drenchers","Coconut Canister","PesticidePlanter","The Supreme Saturator","Gummy Boots","PetalPlanter"],"Craft":true}],"hiddenstickers":true,"discardselect":false,"stickerstacker":false,"intwhitelist":false,"wealthclock":true,"prog":true,"farmwinds":false,"shrineamount":1,"interrupt":true,"stackmethod":"Tickets","materials2":false,"printereggs":false,"discardstickers":false,"windsblacklist":false,"materials":false,"nectarcondenser":false,"honeystorm":false,"nectars":false,"progblender":true,"shrineitem":""},"ant":{"enabled":false,"antpass":false},"planters":{"manual":{"farmfield":false,"planter3":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4},"planter2":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4},"planter1":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4}},"method":"Nectar","cycles":{"cycle2":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle4":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle1":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"started":false,"lastcycle":false,"cycle3":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle5":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2}},"rewards":{"enabled":true,"swirledwax":true,"causticwaxp":false,"smoothie":false,"causticwax":false,"swirledwaxp":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true}},"enabled":true,"nectar":{"satisfying":true,"ignoresmoking":false,"invigoratinglastfield":"","motivating":true,"motivatingp":2,"comfortingp":1,"invigorating":false,"comforting":true,"harvestat":100,"invigoratingmin2":10,"satisfyinglastfield":"","comfortinglastfield":"","harvestaftertime":true,"timetoharvest":2,"farmfield":false,"harvestatpercentage":false,"blacklistedfields":false,"ignorefielddeg":true,"satisfyingmin2":18,"preset":"Custom","motivatingmin2":18,"invigoratingp":5,"refreshing":true,"refreshinglastfield":"","satisfyingp":3,"refreshingmin2":15,"motivatinglastfield":"","refreshingp":4,"comfortingmin2":18,"allowedplanters":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true}}},"webhook":[],"autofarm":{"patternblacklist":false,"smileytime":4,"farmshowers":true,"badgebl":false,"farmfires":true,"farmbadges":false,"guidingfieldblacklist":false,"enabled":true,"autosprinkler":true,"farmcoconuts":true,"farmprecisemark":true,"farmblooms":true,"patternstart":"Center","scorchingscore":0,"farmfireflies":true,"badgep":"Lowest Pollen Needed","autopopstar":true,"badgesclaim":true,"farmprecise":true,"farmtriangulate":true,"autoscorchingstar":true,"farmdupedtokens":true,"pattern":"CornerXSnake","dupedtokens":false,"prioritytokens":false,"farmpetals":true,"farmfuzzbombs":true,"farmcombococonuts":true,"farmleaves":true,"farmbubbles":true,"autogummystar":true,"combofield":false,"ignorehoneytokens":false,"field3":"None","farmballoons2":false,"sprinklerpos":"Center","farmposition":false,"farmmarks":true,"farmpuppyball":true,"autoxflame":false,"field1":"Pine Tree Forest","field2":"None","farmmeteorshowers":true,"farmclouds":true,"fieldinterval":10,"trackprecise":false,"autoguidingstar":false,"comboamount":0,"farmposenabled":false,"patternenabled":false,"autodig":true,"precisemin":30},"puffshrooms":{"enabled":true,"rarity":"Common","max":15,"maintain":false,"highlvlpriority":false,"mintime":30,"blacklistedfields":false,"min":1,"priorityfields":false}}]===]

local STAGE2_CONFIG_RAW = [===[{"hive":{"beetypes":false,"bee":false,"mutas3":false,"stoprjgifted":false,"amount":50,"rjbeetypes":false,"feedtype":"Bitterberry","neonberry":false,"rjrarity":false},"misc":{"mobiletoggle":true,"console":false,"bqbuyconf":false,"followfieldblacklist":false,"anonymous":false,"follow":false,"rolldouble":false,"autorejoin2":false,"bqbuy":false,"bqdel2":false,"realpot":false,"farmmultiplefields":false,"dapperslots":5,"custompatterns":false,"bqdelconf":false},"combat":{"mondochicktime":15,"killmondochick":true,"crabmethod":"Tween","killkingbeetle":true,"killcrab":false,"babylove":true,"donatevials":false,"wlstingers":false,"killScorpion":false,"killtunnelbear":true,"craboil":false,"giftedvicious":false,"killWerewolf":false,"snail":false,"windymax":25,"viciousmin":1,"killMantis":false,"demonmask":false,"lootmondo":true,"killRhinoBeetle":false,"killSpider":false,"windymin":1,"killcommando":false,"viciousmax":6,"stingers":false,"starsaw":false,"killwindy":false,"commandomethod":"Walk","avoidmobs":true,"commandoshell":true,"killvicious":true,"killAphid":true,"commandohelp":false,"dmwhitelist":false,"mondopreptime":20,"mondoprep":false,"killLadybug":false,"wlstarsaw":false},"dispensers":{"coconut":false,"blueberry":false,"royaljelly":false,"treat":false,"strawberry":false,"robopass":false,"glue":false,"honey":false,"antpass":true},"autoquest":{"planters":true,"feedbees":true,"windshrine":true,"rileybee":false,"ragetokens":true,"gummybear":false,"buckobee":false,"treats":true,"enabled":true,"memorymatch":true,"onett":true,"beebear":false,"blackbear2":false,"pollen":true,"sciencebear":true,"puffshrooms":true,"oldtool":false,"goomethod":"Gumdrops","levelbees":true,"sharebeans":true,"pandabear":true,"bestwhitefield":"Sunflower Field","bestredfield":"Mushroom Field","toys":true,"claim2":{"Mother Bear":true,"Polar Bear":true,"Panda Bear":true,"Science Bear":true},"tools":true,"brownbear":false,"ants":true,"blackbear":false,"dapperbear":false,"dupedtokens":true,"mobs":true,"blooms":true,"rj":true,"honeybee":false,"allowedplanters":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true},"craft":true,"goo":true,"xmas":false,"bestbluefield":"Blue Flower Field","stickbug":false,"motherbear":true,"spiritbear":true,"rjbl":false,"polarbear":true},"face":{"balloons":false,"blooms":false,"bubbles":false,"refresh":false,"shiftlock":false,"gballoons":false,"gbubbles":false,"fires":false,"sldirection":"South","center":false,"method":"Shift Lock"},"convert":{"standInPreciseAt":75,"convertHiveBalloon":true,"instantType":false,"convertHoneyAt":100,"coconutAt":85,"convertHoney":true,"resetWhenConverting":false,"convert6xBubbleBloat":false,"festivegift":false,"autoHoneyMask":false,"alwaysConvertBalloon":false,"timeToWait":15,"coconut":false,"waitBeforeConverting":false,"standInPrecise":true,"useEnzymesBalloon":false,"convertField":false,"convertHiveBalloonAt":5,"defaultMask":"Diamond Mask","instantToggle":false},"boosters":{"min":1,"wanted":1,"required":false,"enabled2":false,"allowed":false,"fieldsblacklist":false},"vars":{"walkspeedenabled":true,"movement":"Tween","cannon":false,"tweenspeed":6,"walkspeed":48,"jumpshortcuts":false,"walkspeed2":1.5,"walkdynamic":false},"sprouts":{"enabled":true,"plant":false,"plantday":false,"collect":true,"amount":false,"fieldsblacklist":false,"rarity3":false,"left":0,"plantnight":false},"stickbug":{"enabled":false,"loot":false,"totem":true,"maintain":false,"circle":true,"tickets":false,"spawn":false},"amulet":{"ant":false,"rbc3":false,"kb3":"Bronze","rbc4":false,"ant4":false,"sb3":false,"kb2":false,"star3":false,"sb4":false,"sb":false,"snail4":false,"rbc":false,"sb2":false,"moon4":false,"kb4":{"P2":[],"P3":[],"P1":[]},"rbc2":false,"ant2":false,"snail":false,"ant3":false,"snail2":false,"star4":false,"kb":false,"snail3":false},"memorymatch":{"night":false,"basic":false,"mega":false,"extreme":false,"blacklist":false},"rbc":{"passcooldown":0,"rerollmin":10,"upgrades":false,"mask":false,"rerollquests":false,"redtool":"Dark Scythe","bluemask":"Diamond Mask","cogconvert":false,"cogupgrades":true,"rerollupgrades":false,"materialsenabled":false,"buypass":false,"whitemask":"Gummy Mask","trackmobs":false,"preset":"Blue","disableroundend":false,"maskround":5,"homepage":false,"stoproundend":false,"whitetool":"Gummyballer","highestcogmax":9,"maxround":15,"highestcog":false,"precise":false,"rerollbees":false,"bestwhitefield":"Sunflower Field","bestredfield":"Mushroom Field","bestbluefield":"Blue Flower Field","buydrives":{"Glitched":true,"Red":true,"Blue":true,"White":true},"rerollbeesmax":2,"tool":false,"goldcogmowers":true,"homepagemin":1,"precisemin":5,"enabled":false,"toolround":4,"upgradesenabled":false,"materials":false,"rerollupgmax":2,"goomethod":"Gumdrops","redmask":"Demon Mask","usedrives":{"Glitched":true,"Red":true,"Blue":true,"White":true},"bluetool":"Tide Popper"},"beesmas":[],"detected":[],"antilag":{"stations":true,"precise":true,"balloons":true,"flowers":false,"norender":false,"bssui":false,"dupedtokens":true,"tokens":true,"main":true,"textures":true,"bees":true,"decorations":true,"particles":true,"players":true},"toys":{"windshrine":false,"conversions":2,"stickerprinter":false,"stackselect":false,"enabled":true,"sproutsummoner":false,"meteor":false,"route":[{"Data":["38217","BeesBuzz123","BopMaster","Connoisseur","Crawlers","777","Nectar","Roof","Wax"],"Type":"Codes"},{"Bees":15,"Type":"Codes","Data":"ClubBean"},{"Bees":35,"Type":"Codes","Data":"ThreeBeeVee"},{"Data":["Dandelion Field","Bamboo Field","Pineapple Patch","Pine Tree Forest"],"Type":"Field"},{"Data":["Tabby","Festive","Gummy","Vicious","Puppy"],"Type":"Event Bee"},{"Type":"Purchase","Data":["Backpack","Magnet","Canister","Vacuum","Belt Pocket","Compressor","Super-Scooper","Helmet","Port-O-Hive","Electro-Magnet","Honey Dipper","Propeller Hat","Looker Guard","Brave Guard","Hiking Boots","Belt Bag","Bubble Wand","Basic Sprinkler","PlasticPlanter","Beekeeper's Mask","Beekeeper's Boots","Mondo Belt Bag","Blue Port-O-Hive","Silver Soakers","Elite Blue Guard","Elite Red Guard","CandyPlanter","Glider","Porcelain Dipper","Porcelain Port-O-Hive","Blue ClayPlanter","Red ClayPlanter","Bubble Mask","Cobalt Guard","Golden Gushers","TackyPlanter","Diamond Mask","Honeycomb Belt","Crimson Guard","Diamond Drenchers","Coconut Canister","PesticidePlanter","The Supreme Saturator","Gummy Boots","PetalPlanter"],"Craft":true}],"hiddenstickers":true,"discardselect":false,"stickerstacker":false,"intwhitelist":false,"wealthclock":true,"prog":true,"farmwinds":false,"shrineamount":1,"interrupt":true,"stackmethod":"Tickets","materials2":false,"printereggs":false,"discardstickers":false,"windsblacklist":false,"materials":false,"nectarcondenser":false,"honeystorm":false,"nectars":false,"progblender":true,"shrineitem":""},"ant":{"enabled":false,"antpass":false},"planters":{"manual":{"farmfield":false,"planter3":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4},"planter2":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4},"planter1":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4}},"method":"Nectar","cycles":{"cycle2":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle4":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle1":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"started":false,"lastcycle":false,"cycle3":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle5":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2}},"rewards":{"enabled":true,"swirledwax":true,"causticwaxp":false,"smoothie":false,"causticwax":false,"swirledwaxp":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true}},"enabled":true,"nectar":{"satisfying":true,"ignoresmoking":false,"invigoratinglastfield":"","motivating":true,"motivatingp":2,"comfortingp":1,"invigorating":false,"comforting":true,"harvestat":100,"invigoratingmin2":10,"satisfyinglastfield":"","comfortinglastfield":"","harvestaftertime":true,"timetoharvest":2,"farmfield":false,"harvestatpercentage":false,"blacklistedfields":false,"ignorefielddeg":true,"satisfyingmin2":18,"preset":"Custom","motivatingmin2":18,"invigoratingp":5,"refreshing":true,"refreshinglastfield":"","satisfyingp":3,"refreshingmin2":15,"motivatinglastfield":"","refreshingp":4,"comfortingmin2":18,"allowedplanters":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true}}},"webhook":[],"autofarm":{"patternblacklist":false,"smileytime":4,"farmshowers":true,"badgebl":false,"farmfires":true,"farmbadges":false,"guidingfieldblacklist":false,"enabled":true,"autosprinkler":true,"farmcoconuts":true,"farmprecisemark":true,"farmblooms":true,"patternstart":"Center","scorchingscore":0,"farmfireflies":true,"badgep":"Lowest Pollen Needed","autopopstar":true,"badgesclaim":true,"farmprecise":true,"farmtriangulate":true,"autoscorchingstar":true,"farmdupedtokens":true,"pattern":"CornerXSnake","dupedtokens":false,"prioritytokens":false,"farmpetals":true,"farmfuzzbombs":true,"farmcombococonuts":true,"farmleaves":true,"farmbubbles":true,"autogummystar":true,"combofield":false,"ignorehoneytokens":false,"field3":"None","farmballoons2":false,"sprinklerpos":"Center","farmposition":false,"farmmarks":true,"farmpuppyball":true,"autoxflame":false,"field1":"Pine Tree Forest","field2":"None","farmmeteorshowers":true,"farmclouds":true,"fieldinterval":10,"trackprecise":false,"autoguidingstar":false,"comboamount":0,"farmposenabled":false,"patternenabled":false,"autodig":true,"precisemin":30},"puffshrooms":{"enabled":true,"rarity":"Common","max":15,"maintain":false,"highlvlpriority":false,"mintime":30,"blacklistedfields":false,"min":1,"priorityfields":false}}]===]

local STAGE3_CONFIG_RAW = [===[{"hive":{"beetypes":false,"bee":false,"mutas3":false,"stoprjgifted":false,"amount":50,"rjbeetypes":false,"feedtype":"Bitterberry","neonberry":false,"rjrarity":false},"misc":{"mobiletoggle":true,"console":false,"bqbuyconf":false,"followfieldblacklist":false,"anonymous":false,"follow":false,"rolldouble":false,"autorejoin2":false,"bqbuy":false,"bqdel2":false,"realpot":false,"farmmultiplefields":false,"dapperslots":5,"custompatterns":false,"bqdelconf":false},"combat":{"mondochicktime":15,"killmondochick":true,"crabmethod":"Tween","killkingbeetle":true,"killcrab":true,"babylove":true,"donatevials":false,"wlstingers":false,"killScorpion":false,"killtunnelbear":true,"craboil":false,"giftedvicious":false,"killWerewolf":false,"snail":false,"windymax":25,"viciousmin":1,"killMantis":false,"demonmask":false,"lootmondo":true,"killRhinoBeetle":false,"killSpider":false,"windymin":1,"killcommando":false,"viciousmax":6,"stingers":false,"starsaw":false,"killwindy":false,"commandomethod":"Walk","avoidmobs":true,"commandoshell":true,"killvicious":true,"killAphid":true,"commandohelp":false,"dmwhitelist":false,"mondopreptime":20,"mondoprep":false,"killLadybug":false,"wlstarsaw":false},"dispensers":{"coconut":false,"blueberry":false,"royaljelly":false,"treat":false,"strawberry":false,"robopass":false,"glue":false,"honey":false,"antpass":true},"autoquest":{"planters":true,"feedbees":true,"windshrine":true,"rileybee":false,"ragetokens":true,"gummybear":false,"buckobee":false,"treats":true,"enabled":true,"memorymatch":true,"onett":true,"beebear":false,"blackbear2":false,"pollen":true,"sciencebear":true,"puffshrooms":true,"oldtool":false,"goomethod":"Gumdrops","levelbees":true,"sharebeans":true,"pandabear":true,"bestwhitefield":"Sunflower Field","bestredfield":"Mushroom Field","toys":true,"claim2":{"Mother Bear":true,"Polar Bear":true,"Panda Bear":true,"Science Bear":true},"tools":true,"brownbear":false,"ants":true,"blackbear":false,"dapperbear":false,"dupedtokens":true,"mobs":true,"blooms":true,"rj":true,"honeybee":false,"allowedplanters":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true},"craft":true,"goo":true,"xmas":false,"bestbluefield":"Blue Flower Field","stickbug":false,"motherbear":true,"spiritbear":true,"rjbl":false,"polarbear":true},"face":{"balloons":false,"blooms":false,"bubbles":false,"refresh":false,"shiftlock":false,"gballoons":false,"gbubbles":false,"fires":false,"sldirection":"South","center":false,"method":"Shift Lock"},"convert":{"standInPreciseAt":75,"convertHiveBalloon":true,"instantType":false,"convertHoneyAt":100,"coconutAt":85,"convertHoney":true,"resetWhenConverting":false,"convert6xBubbleBloat":false,"festivegift":false,"autoHoneyMask":false,"alwaysConvertBalloon":false,"timeToWait":15,"coconut":false,"waitBeforeConverting":false,"standInPrecise":true,"useEnzymesBalloon":false,"convertField":false,"convertHiveBalloonAt":5,"defaultMask":"Diamond Mask","instantToggle":false},"boosters":{"min":1,"wanted":1,"required":false,"enabled2":false,"allowed":false,"fieldsblacklist":false},"vars":{"walkspeedenabled":true,"movement":"Tween","cannon":false,"tweenspeed":6,"walkspeed":48,"jumpshortcuts":false,"walkspeed2":1.5,"walkdynamic":false},"sprouts":{"enabled":true,"plant":false,"plantday":false,"collect":true,"amount":false,"fieldsblacklist":false,"rarity3":false,"left":0,"plantnight":false},"stickbug":{"enabled":false,"loot":false,"totem":true,"maintain":false,"circle":true,"tickets":false,"spawn":false},"amulet":{"ant":false,"rbc3":false,"kb3":"Bronze","rbc4":false,"ant4":false,"sb3":false,"kb2":false,"star3":false,"sb4":false,"sb":false,"snail4":false,"rbc":false,"sb2":false,"moon4":false,"kb4":{"P2":[],"P3":[],"P1":[]},"rbc2":false,"ant2":false,"snail":false,"ant3":false,"snail2":false,"star4":false,"kb":false,"snail3":false},"memorymatch":{"night":false,"basic":false,"mega":false,"extreme":false,"blacklist":false},"rbc":{"passcooldown":0,"rerollmin":10,"upgrades":false,"mask":false,"rerollquests":false,"redtool":"Dark Scythe","bluemask":"Diamond Mask","cogconvert":false,"cogupgrades":true,"rerollupgrades":false,"materialsenabled":false,"buypass":false,"whitemask":"Gummy Mask","trackmobs":false,"preset":"Blue","disableroundend":false,"maskround":5,"homepage":false,"stoproundend":false,"whitetool":"Gummyballer","highestcogmax":9,"maxround":15,"highestcog":false,"precise":false,"rerollbees":false,"bestwhitefield":"Sunflower Field","bestredfield":"Mushroom Field","bestbluefield":"Blue Flower Field","buydrives":{"Glitched":true,"Red":true,"Blue":true,"White":true},"rerollbeesmax":2,"tool":false,"goldcogmowers":true,"homepagemin":1,"precisemin":5,"enabled":false,"toolround":4,"upgradesenabled":false,"materials":false,"rerollupgmax":2,"goomethod":"Gumdrops","redmask":"Demon Mask","usedrives":{"Glitched":true,"Red":true,"Blue":true,"White":true},"bluetool":"Tide Popper"},"beesmas":[],"detected":[],"antilag":{"stations":true,"precise":true,"balloons":true,"flowers":false,"norender":false,"bssui":false,"dupedtokens":true,"tokens":true,"main":true,"textures":true,"bees":true,"decorations":true,"particles":true,"players":true},"toys":{"windshrine":false,"conversions":2,"stickerprinter":false,"stackselect":false,"enabled":true,"sproutsummoner":false,"meteor":false,"route":[{"Data":["38217","BeesBuzz123","BopMaster","Connoisseur","Crawlers","777","Nectar","Roof","Wax"],"Type":"Codes"},{"Bees":15,"Type":"Codes","Data":"ClubBean"},{"Bees":35,"Type":"Codes","Data":"ThreeBeeVee"},{"Data":["Dandelion Field","Bamboo Field","Pineapple Patch","Pine Tree Forest"],"Type":"Field"},{"Data":["Tabby","Festive","Gummy","Vicious","Puppy"],"Type":"Event Bee"},{"Type":"Purchase","Data":["Backpack","Magnet","Canister","Vacuum","Belt Pocket","Compressor","Super-Scooper","Helmet","Port-O-Hive","Electro-Magnet","Honey Dipper","Propeller Hat","Looker Guard","Brave Guard","Hiking Boots","Belt Bag","Bubble Wand","Basic Sprinkler","PlasticPlanter","Beekeeper's Mask","Beekeeper's Boots","Mondo Belt Bag","Blue Port-O-Hive","Silver Soakers","Elite Blue Guard","Elite Red Guard","CandyPlanter","Glider","Porcelain Dipper","Porcelain Port-O-Hive","Blue ClayPlanter","Red ClayPlanter","Bubble Mask","Cobalt Guard","Golden Gushers","TackyPlanter","Diamond Mask","Honeycomb Belt","Crimson Guard","Diamond Drenchers","Coconut Canister","PesticidePlanter","The Supreme Saturator","Gummy Boots","PetalPlanter"],"Craft":true}],"hiddenstickers":true,"discardselect":false,"stickerstacker":false,"intwhitelist":false,"wealthclock":true,"prog":true,"farmwinds":false,"shrineamount":1,"interrupt":true,"stackmethod":"Tickets","materials2":false,"printereggs":false,"discardstickers":false,"windsblacklist":false,"materials":false,"nectarcondenser":false,"honeystorm":false,"nectars":false,"progblender":true,"shrineitem":""},"ant":{"enabled":false,"antpass":false},"planters":{"manual":{"farmfield":false,"planter3":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4},"planter2":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4},"planter1":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4}},"method":"Nectar","cycles":{"cycle2":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle4":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle1":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"started":false,"lastcycle":false,"cycle3":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle5":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2}},"rewards":{"enabled":true,"swirledwax":true,"causticwaxp":false,"smoothie":false,"causticwax":false,"swirledwaxp":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true}},"enabled":true,"nectar":{"satisfying":true,"ignoresmoking":false,"invigoratinglastfield":"","motivating":true,"motivatingp":2,"comfortingp":1,"invigorating":false,"comforting":true,"harvestat":100,"invigoratingmin2":10,"satisfyinglastfield":"","comfortinglastfield":"","harvestaftertime":true,"timetoharvest":2,"farmfield":false,"harvestatpercentage":false,"blacklistedfields":false,"ignorefielddeg":true,"satisfyingmin2":18,"preset":"Custom","motivatingmin2":18,"invigoratingp":5,"refreshing":true,"refreshinglastfield":"","satisfyingp":3,"refreshingmin2":15,"motivatinglastfield":"","refreshingp":4,"comfortingmin2":18,"allowedplanters":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true}}},"webhook":[],"autofarm":{"patternblacklist":false,"smileytime":4,"farmshowers":true,"badgebl":false,"farmfires":true,"farmbadges":false,"guidingfieldblacklist":false,"enabled":true,"autosprinkler":true,"farmcoconuts":true,"farmprecisemark":true,"farmblooms":true,"patternstart":"Center","scorchingscore":0,"farmfireflies":true,"badgep":"Lowest Pollen Needed","autopopstar":true,"badgesclaim":true,"farmprecise":true,"farmtriangulate":true,"autoscorchingstar":true,"farmdupedtokens":true,"pattern":"CornerXSnake","dupedtokens":false,"prioritytokens":false,"farmpetals":true,"farmfuzzbombs":true,"farmcombococonuts":true,"farmleaves":true,"farmbubbles":true,"autogummystar":true,"combofield":false,"ignorehoneytokens":false,"field3":"None","farmballoons2":false,"sprinklerpos":"Center","farmposition":false,"farmmarks":true,"farmpuppyball":true,"autoxflame":false,"field1":"Pine Tree Forest","field2":"None","farmmeteorshowers":true,"farmclouds":true,"fieldinterval":10,"trackprecise":false,"autoguidingstar":false,"comboamount":0,"farmposenabled":false,"patternenabled":false,"autodig":true,"precisemin":30},"puffshrooms":{"enabled":true,"rarity":"Common","max":15,"maintain":false,"highlvlpriority":false,"mintime":30,"blacklistedfields":false,"min":1,"priorityfields":false}}]===]

local CONFIG_STAGES = {
    {
        Stage = 1,
        Name = "Stage 1 (King Beetle)",
        FileName = "Stage1_KingBeetle.json",
        Raw = STAGE1_CONFIG_RAW,
        MinBees = 20,
        MinLevel = 7,
    },
    {
        Stage = 2,
        Name = "Stage 2 (Tunnel Bear)",
        FileName = "Stage2_TunnelBear.json",
        Raw = STAGE2_CONFIG_RAW,
        MinBees = 28,
        MinLevel = 9,
    },
    {
        Stage = 3,
        Name = "Stage 3 (Coconut Crab)",
        FileName = "Stage3_CoconutCrab.json",
        Raw = STAGE3_CONFIG_RAW,
        MinBees = 35,
        MinLevel = 10,
    }
}

local currentStage = nil
local lastStageSwitch = 0
local pendingStage = nil
local pendingStageTime = 0

local function getHiveStats(data)
    local beeCount = 0
    local minLevel = 25
    local foundAny = false

    if data and type(data.Honeycomb) == "table" then
        for col = 1, 5 do
            local colTable = data.Honeycomb["x" .. col]
            if type(colTable) == "table" then
                for row = 1, 10 do
                    local bee = colTable["y" .. row]
                    local bt = type(bee) == "table" and tostring(bee.Type or ""):lower() or ""
                    if bt ~= "" and bt ~= "empty" and bt ~= "none" and bt ~= "nil" then
                        beeCount = beeCount + 1
                        local lvl = tonumber(bee.Lvl) or 1
                        if lvl < minLevel then minLevel = lvl end
                        foundAny = true
                    end
                end
            end
        end
    end

    if not foundAny or beeCount == 0 then
        local honeycombs = workspace:FindFirstChild("Honeycombs")
        local hVal = player:FindFirstChild("Honeycomb") and player.Honeycomb.Value
        local hive = (typeof(hVal) == "Instance" and hVal) or (honeycombs and honeycombs:FindFirstChild(tostring(hVal)))
        if not hive and honeycombs then
            for _, h in ipairs(honeycombs:GetChildren()) do
                local o = h:FindFirstChild("Owner")
                if o and (o.Value == player or o.Value == player.Name or tostring(o.Value) == player.Name or (player.Character and o.Value == player.Character)) then
                    hive = h
                    break
                end
            end
        end
        if hive and hive:FindFirstChild("Cells") then
            local pCount = 0
            local pMin = 25
            local pFound = false
            for _, cell in ipairs(hive.Cells:GetChildren()) do
                local ct = cell:FindFirstChild("CellType") or cell:FindFirstChild("Type")
                local ctv = ct and tostring(ct.Value):lower() or ""
                if ctv ~= "" and ctv ~= "empty" and ctv ~= "none" and ctv ~= "nil" then
                    pCount = pCount + 1
                    local lVal = cell:FindFirstChild("CellLevel") or cell:FindFirstChild("Level") or cell:FindFirstChild("Lvl")
                    local lvl = lVal and tonumber(lVal.Value) or nil
                    if not lvl then
                        local lp = cell:FindFirstChild("LevelPart")
                        local tl = lp and lp:FindFirstChildWhichIsA("TextLabel", true)
                        local digits = tl and tostring(tl.Text or ""):match("(%d+)")
                        lvl = digits and tonumber(digits) or 1
                    end
                    if lvl < pMin then pMin = lvl end
                    pFound = true
                end
            end
            if pFound and pCount > 0 then
                beeCount = pCount
                minLevel = pMin
                foundAny = true
            end
        end
    end

    if not foundAny then
        minLevel = 1
        beeCount = getBeeCount(data)
    end

    return beeCount, minLevel
end

local function pickStage(beeCount, minLevel)
    for i = #CONFIG_STAGES, 1, -1 do
        local s = CONFIG_STAGES[i]
        if beeCount >= s.MinBees and minLevel >= s.MinLevel then
            return s.Stage, s
        end
    end
    return nil, nil
end

local function writeStageFiles()
    if not writefile then return end
    local roots = discoverAtlasRoots()
    local targetDir = roots[1] or "atlas"
    if makefolder and not fsIsFolder(targetDir) then
        pcall(makefolder, targetDir)
    end
    for _, s in ipairs(CONFIG_STAGES) do
        local path = targetDir .. "/" .. s.FileName
        if not fsIsFile(path) then
            pcall(writefile, path, s.Raw)
        end
        if not fsIsFile(s.FileName) then
            pcall(writefile, s.FileName, s.Raw)
        end
    end
end

local function applyStagePreset(stageInfo)
    if not stageInfo then return false end
    local fileName = stageInfo.FileName
    local raw = stageInfo.Raw

    if writefile then
        local roots = discoverAtlasRoots()
        for _, r in ipairs(roots) do
            pcall(writefile, r .. "/" .. fileName, raw)
        end
        pcall(writefile, fileName, raw)
        pcall(writefile, "atlas/" .. fileName, raw)

        local activePresets = {}
        local seenPresets = {}
        local function addPreset(fn)
            if not fn or fn == "" then return end
            fn = fn:gsub('^"', ''):gsub('"$', ''):gsub("^%s+", ""):gsub("%s+$", "")
            if not fn:lower():match("%.json$") then fn = fn .. ".json" end
            if not seenPresets[fn] then
                seenPresets[fn] = true
                table.insert(activePresets, fn)
            end
        end

        if configState and configState.path and type(configState.path) == "string" then
            local pName = configState.path:match("([^/\\]+%.json)$")
            if pName then addPreset(pName) end
        end

        local ptrFiles = findPointerFiles()
        for _, pf in ipairs(ptrFiles) do
            if fsIsFile(pf) and readfile then
                local ok, content = pcall(readfile, pf)
                if ok and content and #content > 0 then
                    addPreset(content)
                end
            end
        end

        local userPtr = {
            "atlas-" .. player.Name .. ".json",
            "atlas-" .. tostring(player.UserId) .. ".json"
        }
        for _, pf in ipairs(userPtr) do
            if fsIsFile(pf) and readfile then
                local ok, content = pcall(readfile, pf)
                if ok and content and #content > 0 then
                    addPreset(content)
                end
            end
        end

        for _, pName in ipairs(activePresets) do
            for _, r in ipairs(roots) do
                pcall(writefile, r .. "/" .. pName, raw)
            end
            pcall(writefile, pName, raw)
            pcall(writefile, "atlas/" .. pName, raw)
        end

        for _, pf in ipairs(ptrFiles) do
            pcall(writefile, pf, '"' .. fileName .. '"')
        end
        for _, pf in ipairs(userPtr) do
            pcall(writefile, pf, '"' .. fileName .. '"')
        end
    end

    local decoded = decodeConfig(raw)
    if decoded then
        local function deepMerge(dst, src)
            if type(dst) ~= "table" or type(src) ~= "table" then return end
            for k, v in pairs(src) do
                if type(v) == "table" and type(dst[k]) == "table" then
                    deepMerge(dst[k], v)
                else
                    dst[k] = v
                end
            end
        end

        local cur = findAtlasSettings()
        if cur then deepMerge(cur, decoded) end
        if getgenv then
            if getgenv().Atlas and type(getgenv().Atlas) == "table" and getgenv().Atlas.Settings then
                deepMerge(getgenv().Atlas.Settings, decoded)
            end
            if getgenv().Config and type(getgenv().Config) == "table" then
                deepMerge(getgenv().Config, decoded)
            end
        end
    end

    if getgenv and getgenv().Atlas and type(getgenv().Atlas.LoadConfig) == "function" then
        pcall(getgenv().Atlas.LoadConfig, fileName)
    end

    local uiRoots = {}
    pcall(function() if gethui then table.insert(uiRoots, gethui()) end end)
    pcall(function() table.insert(uiRoots, CoreGui) end)
    pcall(function() table.insert(uiRoots, player:FindFirstChild("PlayerGui")) end)

    for _, root in ipairs(uiRoots) do
        if root then
            local prevTabName, prevTabBtn = findActiveAtlasTab(root)
            local configBtn = findAtlasTabButton(root, "config")
            if configBtn then
                clickElement(configBtn)
                task.wait(0.15)

                local importBox = nil
                local loadBtn = nil
                local importBtn = nil

                for _, d in ipairs(root:GetDescendants()) do
                    if d:IsA("TextBox") and isOnScreen(d) then
                        local ph = tostring(d.PlaceholderText or ""):lower()
                        local nm = tostring(d.Name or ""):lower()
                        if ph:find("import") or ph:find("paste") or ph:find("json") or nm:find("import") then
                            importBox = d
                        end
                    end
                    if (d:IsA("TextButton") or d:IsA("ImageButton")) and isOnScreen(d) and d ~= configBtn and d ~= prevTabBtn then
                        local txt = getGuiText(d):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
                        if txt == "load config" or txt == "load" then
                            loadBtn = d
                        elseif txt == "import config" or txt == "import" then
                            importBtn = d
                        end
                    end
                end

                if importBox then
                    pcall(function()
                        importBox.Text = raw
                        if firesignal then
                            pcall(function() firesignal(importBox.FocusLost, true) end)
                        end
                        pcall(function() importBox:ReleaseFocus(true) end)
                    end)
                    task.wait(0.05)
                end

                if importBtn then
                    clickElement(importBtn)
                    task.wait(0.1)
                elseif loadBtn then
                    clickElement(loadBtn)
                    task.wait(0.1)
                end

                if prevTabBtn then
                    task.wait(0.05)
                    clickElement(prevTabBtn)
                end
                break
            end
        end
    end

    print(string.format("[Auto Config] Switched to %s (%s)", stageInfo.Name, fileName))
    return true
end

local function sendStageWebhook(oldStage, newStageInfo, beeCount, minLvl)
    if not WebhookState.notifyConfig then return end
    local webhookUrl = getWebhookSettings()
    if not webhookUrl or not getHttpRequest() then return end

    local title = "Auto Change Config - Stage Up!"
    local bodyText = RouteSteps.clip(string.format(
        "**New stage:** %s\n**Config file:** `%s`\n**Bees:** %d\n**Min Level:** %d",
        tostring(newStageInfo.Name), tostring(newStageInfo.FileName), tonumber(beeCount) or 0, tonumber(minLvl) or 0
    ), 3500)
    local footer = "Ivyis BSS-" .. tostring(player.Name)
    postWebhook(webhookUrl,
        buildV2Payload({
            "## " .. title,
            bodyText,
            string.format("-# %s • <t:%d:R>", footer, os.time()),
        }, 65280),
        {
            username = getWebhookTitle(),
            embeds = { {
                title = title, description = bodyText, color = 65280,
                footer = { text = footer },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            } },
        })
end

local function checkConfigStage(data, beeCount, minLvl)
    if getgenv and getgenv().AutoChangeConfigEnabled == false then return end

    local targetStageIdx, targetStage = pickStage(beeCount, minLvl)
    if not targetStageIdx then return end

    if currentStage == nil then
        currentStage = targetStageIdx
        writeStageFiles()
        applyStagePreset(targetStage)
        return
    end

    if targetStageIdx ~= currentStage then
        if pendingStage ~= targetStageIdx then
            pendingStage = targetStageIdx
            pendingStageTime = tick()
            local debounce = (getgenv and tonumber(getgenv().AutoChangeConfigDebounce)) or 15
            task.spawn(sendEventWebhook, "config", "Eligible for config change",
                string.format("**Switching to:** %s\n**Bees:** %d (need %d)\n**Min Level:** %d (need %d)\nWill switch in about %d seconds if still eligible.",
                    tostring(targetStage.Name), tonumber(beeCount) or 0, targetStage.MinBees, tonumber(minLvl) or 0, targetStage.MinLevel, debounce),
                16776960)
            return
        end

        local debounceSec = (getgenv and tonumber(getgenv().AutoChangeConfigDebounce)) or 15
        if tick() - (pendingStageTime or 0) < debounceSec then
            return
        end

        if tick() - lastStageSwitch < 45 then
            return
        end

        local oldStage = currentStage
        currentStage = targetStageIdx
        lastStageSwitch = tick()
        pendingStage = nil

        applyStagePreset(targetStage)
        task.spawn(sendStageWebhook, oldStage, targetStage, beeCount, minLvl)
    else
        pendingStage = nil
    end
end

if getgenv then getgenv().AutoProgDebug = printDebug end
_G.AutoProgDebug = printDebug


    if hudGui then
        hudGui.Enabled = showProgressionHud
    end

    local lastMapArgs = nil

    local ROUTE_MAP_ROWS = {
        {"Backpack", "Magnet", "Canister", "Vacuum"},
        {"Belt Pocket", "Compressor", "Super-Scooper"},
        {"Helmet", "Port-O-Hive", "Electro-Magnet"},
        {"Honey Dipper", "Propeller Hat", "Looker Guard"},
        {"Brave Guard", "Hiking Boots", "Belt Bag"},
        {"Bubble Wand", "Basic Sprinkler", "Plastic Planter"},
        {"Beekeeper's Mask", "Beekeeper's Boots"},
        {"Mondo Belt Bag", "Blue Port-O-Hive", "Silver Soakers"},
        {"Elite Blue Guard", "Elite Red Guard", "Candy Planter"},
        {"Glider", "Porcelain Dipper", "Porcelain Port-O-Hive"},
        {"Blue Clay Planter", "Red Clay Planter", "Bubble Mask"},
        {"Cobalt Guard", "Golden Gushers", "Tacky Planter"},
        {"Diamond Mask", "Honeycomb Belt", "Crimson Guard"},
        {"Diamond Drenchers", "Coconut Canister"},
        {"Pesticide Planter", "The Supreme Saturator"},
        {"Gummy Boots", "Petal Planter"}
    }

    local MAP_COLORS = {
        background = Color3.fromHex("#101010"),
        panel = Color3.fromHex("#2A2A2C"),
        panelSoft = Color3.fromHex("#202022"),
        outline = Color3.fromHex("#3F3F46"),
        text = Color3.fromHex("#FFFFFF"),
        muted = Color3.fromHex("#A1A1A1"),
        done = Color3.fromHex("#33C759"),
        accent = Color3.fromHex("#0091FF"),
    }
    -- Cung ho font Gotham voi giao dien Atlas: moi chu trong tool deu dong nhat.
    local MAP_FONT = Enum.Font.GothamMedium

    -- Mau cua gear tile bam theo theme IvyisUI dang dung. Theme co the doi luc
    -- chay qua Settings > UI Theme, nen khong hard-code mau toi nua.
    -- Gom state + helper vao mot table de khong vuot gioi han local cua Luau.
    local routeCountLabel = nil
    local gearVisual = {
        progressTrack = nil,
        orderSignature = nil,
        theme = {
            background = MAP_COLORS.background,
            panel = MAP_COLORS.panel,
            panelSoft = MAP_COLORS.panelSoft,
            panelTransparency = 0,
            outline = MAP_COLORS.outline,
            text = MAP_COLORS.text,
            muted = MAP_COLORS.muted,
            done = MAP_COLORS.done,
            accent = MAP_COLORS.accent,
        },
    }

    function gearVisual.color(theme, keys, fallback)
        for _, key in ipairs(keys) do
            local v = theme[key]
            if typeof(v) == "Color3" then return v end
            if type(v) == "string" and v:sub(1, 1) == "#" then
                return Color3.fromHex(v)
            end
        end
        return Color3.fromHex(fallback)
    end

    function gearVisual.refresh()
        if not IvyisUI or not IvyisUI.GetCurrentTheme or not IvyisUI.GetThemes then return end
        local ok, themeName = pcall(function() return IvyisUI:GetCurrentTheme() end)
        if not ok or not themeName then return end
        local themes = IvyisUI:GetThemes()
        local theme = type(themes) == "table" and themes[themeName] or nil
        if type(theme) ~= "table" then return end

        local t = gearVisual.theme
        t.background = gearVisual.color(theme, { "Background" }, "#101010")
        t.panel = gearVisual.color(theme, { "ElementBackground", "PanelBackground" }, "#2A2A2C")
        t.panelTransparency = tonumber(theme.ElementBackgroundTransparency) or 0
        t.text = gearVisual.color(theme, { "Text" }, "#FFFFFF")
        t.muted = gearVisual.color(theme, { "Placeholder", "Icon" }, "#A1A1A1")
        t.outline = gearVisual.color(theme, { "Placeholder", "Outline" }, "#3F3F46")
        t.done = gearVisual.color(theme, { "Toggle", "Primary", "Slider", "Accent", "Button" }, "#33C759")
        t.accent = gearVisual.color(theme, { "Primary", "Slider", "Accent", "Button", "Toggle" }, "#0091FF")
        t.panelSoft = t.panel:Lerp(t.background, 0.35)
    end

    function gearVisual.paint(obj)
        if not obj or not obj.item then return end
        local t = gearVisual.theme
        local state = obj.state or "locked"

        obj.item.BackgroundColor3 = (state == "owned") and t.panelSoft or t.panel
        obj.item.BackgroundTransparency = t.panelTransparency
        obj.tag.TextColor3 = t.muted
        obj.status.TextColor3 = t.muted
        obj.icon.ImageTransparency = (state == "owned") and 0.55 or 0
        if obj.initialLbl then obj.initialLbl.TextColor3 = t.muted end

        if state == "owned" then
            obj.stroke.Color = t.done
            obj.stroke.Transparency = 0.15
            obj.nameLbl.TextColor3 = t.muted
            obj.status.Text = "OWN"
            obj.status.TextColor3 = t.done
        elseif state == "target" then
            obj.stroke.Color = t.accent
            obj.stroke.Transparency = 0
            obj.nameLbl.TextColor3 = t.text
            obj.status.Text = "NEXT"
            obj.status.TextColor3 = t.accent
        else
            obj.stroke.Color = t.outline
            obj.stroke.Transparency = 0.65
            obj.nameLbl.TextColor3 = t.text
            obj.status.Text = ""
        end

        obj.item.Visible = not (gearHideOwned and state == "owned")
    end

    function gearVisual.applyTheme()
        gearVisual.refresh()
        local t = gearVisual.theme
        if gearProgressText then gearProgressText.TextColor3 = t.text end
        if routeCountLabel then routeCountLabel.TextColor3 = t.muted end
        if gearVisual.progressTrack then gearVisual.progressTrack.BackgroundColor3 = t.outline end
        if gearProgressFill then gearProgressFill.BackgroundColor3 = t.done end
        for _, obj in pairs(routePills) do gearVisual.paint(obj) end
    end

    -- Sap xep tile theo dung thu tu route Atlas vua doc duoc. Mon nao khong
    -- nam trong route hien tai thi giu thu tu goc va nam sau cac mon cua route.
    function gearVisual.applyOrder(activeRoute)
        if not gearListMounted or next(routePills) == nil then return end
        if type(activeRoute) ~= "table" then activeRoute = getRoute() end
        if type(activeRoute) ~= "table" then return end

        local ordered, used, signatureParts = {}, {}, {}
        local function add(obj)
            if not obj or used[obj.key] then return end
            used[obj.key] = true
            ordered[#ordered + 1] = obj
            signatureParts[#signatureParts + 1] = obj.key
        end

        for _, milestone in ipairs(activeRoute) do
            local rawName = (type(milestone) == "table" and (milestone.Name or milestone.Item or milestone.Target)) or nil
            if rawName then add(routePills[itemKey(rawName)]) end
        end

        local leftovers = {}
        for key, obj in pairs(routePills) do
            if not used[key] then leftovers[#leftovers + 1] = obj end
        end
        table.sort(leftovers, function(a, b)
            return (a.baseOrder or 0) < (b.baseOrder or 0)
        end)
        for _, obj in ipairs(leftovers) do add(obj) end

        local signature = table.concat(signatureParts, "|")
        if signature == gearVisual.orderSignature then return end
        gearVisual.orderSignature = signature

        for index, obj in ipairs(ordered) do
            obj.item.LayoutOrder = index
            obj.tag.Text = tostring(index)
        end
    end

    local function makeLabel(parent, props)
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.BorderSizePixel = 0
        lbl.Font = MAP_FONT
        lbl.TextColor3 = MAP_COLORS.text
        for k, v in pairs(props) do lbl[k] = v end
        lbl.Parent = parent
        return lbl
    end

    local function getItemIcon(rawName)
        if not rawName then return "" end
        local key = (rawName:gsub("[%s%-_']", "")):lower()
        return getRouteIcon(key) or ""
    end

    -- Build the gear list inside a IvyisUI tab, so it uses the same window,
    -- theme, font and scrolling behaviour as the main tabs.
    local function buildGearList(tab, progressLabel)
        if gearListMounted then return end

        local parent = tab and tab.UIElements and tab.UIElements.ContainerFrame
        if not parent then return end

        gearListMounted = true
        gearProgressLabel = progressLabel

        gearListRoot = Instance.new("Frame")
        gearListRoot.Name = "GearList"
        gearListRoot.BackgroundTransparency = 1
        gearListRoot.BorderSizePixel = 0
        gearListRoot.Size = UDim2.new(1, 0, 0, 0)
        gearListRoot.AutomaticSize = Enum.AutomaticSize.Y
        gearListRoot.LayoutOrder = 50
        gearListRoot.Parent = parent

        local rootLayout = Instance.new("UIListLayout", gearListRoot)
        rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
        rootLayout.Padding = UDim.new(0, 8)
        rootLayout.FillDirection = Enum.FillDirection.Vertical
        rootLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

        local summary = Instance.new("Frame")
        summary.Name = "Summary"
        summary.BackgroundTransparency = 1
        summary.Size = UDim2.new(1, 0, 0, 18)
        summary.LayoutOrder = 1
        summary.Parent = gearListRoot

        gearProgressText = makeLabel(summary, {
            Size = UDim2.new(1, -82, 1, 0),
            Text = "0/0 gear owned",
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        routeCountLabel = makeLabel(summary, {
            Size = UDim2.fromOffset(76, 18),
            Position = UDim2.new(1, -76, 0, 0),
            Text = "0/0",
            TextSize = 13,
            TextColor3 = MAP_COLORS.muted,
            TextXAlignment = Enum.TextXAlignment.Right,
        })

        local bar = Instance.new("Frame")
        bar.Name = "ProgressBar"
        bar.Size = UDim2.new(1, 0, 0, 4)
        bar.BackgroundColor3 = gearVisual.theme.outline
        bar.BorderSizePixel = 0
        bar.LayoutOrder = 2
        bar.Parent = gearListRoot
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
        gearVisual.progressTrack = bar

        gearProgressFill = Instance.new("Frame")
        gearProgressFill.Name = "Fill"
        gearProgressFill.Size = UDim2.new(0, 0, 1, 0)
        gearProgressFill.BackgroundColor3 = MAP_COLORS.done
        gearProgressFill.BorderSizePixel = 0
        gearProgressFill.Parent = bar
        Instance.new("UICorner", gearProgressFill).CornerRadius = UDim.new(1, 0)

        gearListGrid = Instance.new("Frame")
        gearListGrid.Name = "Grid"
        gearListGrid.BackgroundTransparency = 1
        gearListGrid.BorderSizePixel = 0
        gearListGrid.Size = UDim2.new(1, 0, 0, 0)
        gearListGrid.AutomaticSize = Enum.AutomaticSize.Y
        gearListGrid.LayoutOrder = 3
        gearListGrid.Parent = gearListRoot

        local grid = Instance.new("UIGridLayout", gearListGrid)
        grid.Name = "GridLayout"
        grid.SortOrder = Enum.SortOrder.LayoutOrder
        grid.CellSize = UDim2.fromOffset(86, 92)
        grid.CellPadding = UDim2.fromOffset(6, 6)
        grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
        grid.VerticalAlignment = Enum.VerticalAlignment.Top

        routePills = {}
        local step = 0
        for _, row in ipairs(ROUTE_MAP_ROWS) do
            for _, rawName in ipairs(row) do
                step = step + 1

                local tile = Instance.new("Frame")
                tile.Name = "Item_" .. step
                tile.LayoutOrder = step
                tile.BackgroundColor3 = gearVisual.theme.panel
                tile.BorderSizePixel = 0
                tile.Parent = gearListGrid
                Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 10)

                local stroke = Instance.new("UIStroke", tile)
                stroke.Color = gearVisual.theme.outline
                stroke.Thickness = 1
                stroke.Transparency = 0.65

                local tag = makeLabel(tile, {
                    Size = UDim2.fromOffset(34, 13),
                    Position = UDim2.new(0, 6, 0, 5),
                    Text = tostring(step),
                    TextSize = 9,
                    TextColor3 = gearVisual.theme.muted,
                    TextXAlignment = Enum.TextXAlignment.Left,
                })
                local status = makeLabel(tile, {
                    Size = UDim2.new(1, -48, 0, 13),
                    Position = UDim2.new(0, 42, 0, 5),
                    Text = "",
                    TextSize = 8,
                    TextColor3 = gearVisual.theme.muted,
                    TextXAlignment = Enum.TextXAlignment.Right,
                })

                local icon = Instance.new("ImageLabel")
                icon.Name = "Icon"
                icon.Size = UDim2.fromOffset(38, 38)
                icon.Position = UDim2.new(0.5, -19, 0, 9)
                icon.BackgroundTransparency = 1
                icon.BorderSizePixel = 0
                icon.ScaleType = Enum.ScaleType.Fit
                icon.Parent = tile

                local asset = getItemIcon(rawName)
                local initialLbl = nil
                if asset ~= "" then
                    icon.Image = asset
                else
                    initialLbl = makeLabel(tile, {
                        Size = UDim2.fromOffset(38, 38),
                        Position = UDim2.new(0.5, -19, 0, 9),
                        Text = rawName:sub(1, 1),
                        TextSize = 21,
                        TextColor3 = gearVisual.theme.muted,
                    })
                end

                local nameLbl = makeLabel(tile, {
                    Size = UDim2.new(1, -8, 0, 30),
                    Position = UDim2.new(0, 4, 0, 55),
                    Text = rawName,
                    TextSize = 10,
                    TextWrapped = true,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    TextXAlignment = Enum.TextXAlignment.Center,
                })

                local key = (rawName:gsub("[%s%-_']", "")):lower()
                routePills[key] = {
                    item = tile, stroke = stroke, nameLbl = nameLbl, tag = tag,
                    status = status, icon = icon, initialLbl = initialLbl,
                    name = rawName, key = key, baseOrder = step, state = "locked",
                }
            end
        end
        gearVisual.applyTheme()
        gearVisual.applyOrder(getRoute())
    end

    local function paintGearFilter()
        for _, obj in pairs(routePills) do
            obj.item.Visible = not (gearHideOwned and obj.state == "owned")
        end
    end
    local function setItemState(obj, state)
        if obj.state == state then return end
        obj.state = state
        gearVisual.paint(obj)
    end

    local function updateRouteMap(activeTarget, char, data)
        lastMapArgs = { activeTarget, char, data }
        if not gearListMounted then return end

        gearVisual.applyOrder(getRoute())

        local targetKey = activeTarget and (activeTarget:gsub("[%s%-_']", "")):lower()
        local owned, total = 0, 0
        for key, obj in pairs(routePills) do
            total = total + 1
            if targetKey and key == targetKey then
                setItemState(obj, "target")
            elseif ownsItem(obj.name, "Gear", char, data) then
                owned = owned + 1
                setItemState(obj, "owned")
            else
                setItemState(obj, "locked")
            end
        end

        if routeCountLabel then routeCountLabel.Text = string.format("%d/%d", owned, total) end
        if gearProgressText then
            gearProgressText.Text = string.format("%d/%d gear owned", owned, total)
        end
        if gearProgressFill then
            gearProgressFill.Size = UDim2.new(total > 0 and owned / total or 0, 0, 1, 0)
        end
        if gearProgressLabel then
            gearProgressLabel:SetTitle(string.format("Gear %d/%d", owned, total))
            gearProgressLabel:SetDesc(activeTarget and ("Next: " .. activeTarget)
                or (liveNonGear and "Atlas step is not gear" or "All route gear owned"))
        end
    end

    local function toggleRouteMap()
        if openGearListFn then
            pcall(openGearListFn)
        end
    end

    -- phat hien mon do moi so huu de bao webhook (lan doc dau chi ghi nho, khong bao)
    local function trackPurchases(p)
        if not p or not p.data then return end
        local char = player.Character
        local total, ownedCount, fresh = 0, 0, {}
        local firstRun = (WebhookState.owned == nil)
        if firstRun then WebhookState.owned = {} end
        for _, row in ipairs(ROUTE_MAP_ROWS) do
            for _, name in ipairs(row) do
                total = total + 1
                if ownsItem(name, "Gear", char, p.data) then
                    ownedCount = ownedCount + 1
                    -- Planter vinh vien thu hoach xong quay lai tui, khong phai "mua moi":
                    -- ghi nho luon va khong bao webhook "Da mua xong do moi".
                    local isPlanterItem = name:lower():find("planter", 1, true) ~= nil
                    if not WebhookState.owned[name] then
                        if firstRun or isPlanterItem then
                            WebhookState.owned[name] = true
                        else
                            -- phai thay 2 lan lien tiep cho chac, tranh bao nham
                            WebhookState.seen[name] = (WebhookState.seen[name] or 0) + 1
                            if WebhookState.seen[name] >= 2 then
                                WebhookState.owned[name] = true
                                fresh[#fresh + 1] = name
                            end
                        end
                    end
                end
            end
        end
        if #fresh > 0 then
            task.spawn(sendEventWebhook, "buy", "New gear purchased",
                string.format("**Owned:** %s\n**Progress:** %d/%d items\n**Next item:** %s",
                    table.concat(fresh, ", "), ownedCount, total, tostring(p.targetItem or "route complete")),
                5763719)
        end
    end

    -- doc 1 lan roi dung chung cho UI, webhook va doi field
    local function snapshotProgress()
        local data = getStatData()
        local beeCount, minBeeLvl = getHiveStats(data)
        local targetItem, neededMat, neededAmt, field, isUnfarmable = pickNextTarget(data, beeCount)
        return {
            data = data, beeCount = beeCount, minBeeLvl = minBeeLvl,
            targetItem = targetItem, neededMat = neededMat, neededAmt = neededAmt,
            field = field, isUnfarmable = isUnfarmable,
        }
    end

    local function describeNeed(p)
        if p.neededMat == "Honey" and p.targetItem then
            local deficit, have, need = getHoneyInfo(p.targetItem, p.data)
            if deficit <= 0 then deficit = tonumber(p.neededAmt) or 0 end
            return string.format("Honey %s (have %s/%s)", formatAmount(deficit), formatAmount(have), formatAmount(need))
        end
        if p.neededMat then
            return string.format("%s %s%s", tostring(p.neededMat), formatAmount(p.neededAmt),
                p.isUnfarmable and " [Unfarmable]" or "")
        end
        if p.targetItem then
            local mat, amt, have, need = topLevelMissing(p.targetItem, p.data)
            if mat == "Honey" then
                return string.format("Honey %s (have %s/%s)", formatAmount(amt), formatAmount(have), formatAmount(need))
            elseif mat then
                return string.format("%s %s", tostring(mat), formatAmount(amt))
            end
            return "READY"
        end
        return "None"
    end

    local function refreshProgressionUI(p)
        local ok, err = pcall(function()
            p = p or snapshotProgress()
            local targetTitle = liveNonGear and "Atlas step: not gear"
                or string.format("Next item: %s", tostring(p.targetItem or "nothing left"))
            local needBody = describeIngredients(p.targetItem, p.data, p.beeCount, true)
            local targetDesc = string.format("Field: %s\nBees: %d, lowest level %d\n\nNeed:\n%s",
                tostring(p.field or (p.targetItem and "Unchanged" or "None")),
                tonumber(p.beeCount) or 0,
                tonumber(p.minBeeLvl) or 0,
                tostring(needBody)
            )
            if progTargetLabel then
                pcall(function()
                    progTargetLabel:SetTitle(targetTitle)
                    progTargetLabel:SetDesc(targetDesc)
                end)
            end

            updateRouteMap(p.targetItem, player.Character, p.data)

            if hudLabel then
                local stage = currentStage and CONFIG_STAGES[currentStage]
                hudLabel.Text = string.format("%s | bees %d, min lv %d | next %s | need %s | field %s",
                    stage and stage.Name or "Auto Prog",
                    tonumber(p.beeCount) or 0,
                    tonumber(p.minBeeLvl) or 0,
                    tostring(p.targetItem or (liveNonGear and "non-gear step" or "None")),
                    describeNeed(p),
                    tostring(p.field or "Unchanged")
                )
            end
        end)
        if not ok then warn("[Auto Prog UI] error: " .. tostring(err)) end
    end

    local function progressionTick()
        if not autoProgressionEnabled then return end
        -- Doi Atlas load xong (10-20s) truoc khi doc/bam UI va ghi preset.
        local bootReady = getgenv and getgenv().IvyisAtlasBootReady
        if bootReady and not bootReady() then return end
        local ok, err = pcall(function()
            local p = snapshotProgress()
            refreshProgressionUI(p)

            if autoFieldSwitchEnabled and p.field then
                setField(p.field)
            end

            if autoHuntViciousEnabled then
                local wantStinger = p.neededMat == "Stinger" and (p.neededAmt or 0) > 0
                if not wantStinger then
                    wantStinger = needsStinger(p.targetItem, p.data)
                end
                if wantStinger then
                    pcall(enableViciousKill)
                end
            end

            checkConfigStage(p.data, p.beeCount, p.minBeeLvl)

            trackPurchases(p)

            task.spawn(sendProgressWebhook, p.beeCount, p.targetItem or "None", p.field or "Unchanged",
                routeFound and "Found" or "Not Found", p.data, describeNeed(p), p.isUnfarmable, p.neededMat)
        end)
        if not ok then
            warn("[Auto Prog] tick error: " .. tostring(err))
        end
    end

    local function rescanProgression()
        routeCache = nil
        routeCacheTime = 0
        progressionTick()
    end

    local function setHudVisible(visible)
        showProgressionHud = visible
        if hudGui then
            hudGui.Enabled = visible
        end
    end

    local function cleanupProgression()
        autoProgressionEnabled = false
        if hudGui and hudGui.Destroy then
            pcall(function() hudGui:Destroy() end)
        end
        if gearListRoot and gearListRoot.Destroy then
            pcall(function() gearListRoot:Destroy() end)
        end
        gearListRoot = nil
        gearListGrid = nil
        gearProgressLabel = nil
        gearProgressText = nil
        gearProgressFill = nil
        routePills = {}
        gearListMounted = false
        gearVisual.orderSignature = nil
        gearVisual.progressTrack = nil
    end

    return {
        getStatData = getStatData,
        refreshProgressionUI = refreshProgressionUI,
        progressionTick = progressionTick,
        rescanProgression = rescanProgression,
        setHudVisible = setHudVisible,
        toggleRouteMap = toggleRouteMap,
        openGearList = toggleRouteMap,
        mountGearList = buildGearList,
        applyGearTheme = function() gearVisual.applyTheme() end,
        setGearHideOwned = function(v)
            gearHideOwned = v and true or false
            paintGearFilter()
        end,
        setOpenGearList = function(fn)
            openGearListFn = fn
        end,
        cleanupProgression = cleanupProgression,
        setTargetLabel = function(targetP)
            progTargetLabel = targetP
        end,
        setAutoProgression = function(v) autoProgressionEnabled = v end,
        setAutoFieldSwitch = function(v) autoFieldSwitchEnabled = v end,
        setAutoHuntVicious = function(v) autoHuntViciousEnabled = v end,
        setWebhookUrl = function(url) WebhookState.url = url or "" end,
        setWebhookInterval = function(seconds) WebhookState.interval = tonumber(seconds) end,
        setNotifyBuy = function(v) WebhookState.notifyBuy = v and true or false end,
        setNotifyConfig = function(v) WebhookState.notifyConfig = v and true or false end,
        sendTestWebhook = function()
            local url = getWebhookSettings()
            if not url then return false, "no link" end
            if not getHttpRequest() then return false, "executor has no http request" end
            local ok = sendEventWebhook(nil, "Test message", "Webhook is working. This came from Ivyis BSS.", 5763719)
            return ok, ok and "sent" or "Discord refused it"
        end,
    }
end)()

local function getStatData(...)
    return Progression.getStatData(...)
end

local function getHoney(data)
    if not data then data = getStatData() end
    return (data and tonumber(data.Honey)) or 0
end

local function getTreats(data)
    if not data then data = getStatData() end
    if data and data.Eggs and data.Eggs.Treat then
        return tonumber(data.Eggs.Treat) or 0
    end
    return 0
end

local function getRoyalJellies(data)
    if not data then data = getStatData() end
    if data and data.Eggs and data.Eggs.RoyalJelly then
        return tonumber(data.Eggs.RoyalJelly) or 0
    end
    return 0
end

local function calcHoneyNeeded(tgtLvl, tgtBees)
    local data = getStatData()
    if not data or not data.Honeycomb then return 0, 0, 0, 0 end
    local tgtCum = getCumulativeBond(tgtLvl)
    local bft = (data.Modifiers and data.Modifiers["Bond From Treats"]) or 0
    local effBond = TREAT_BOND * (1 + bft / 100)

    local bees = {}
    for col = 1, 5 do
        local xKey = "x" .. col
        if data.Honeycomb[xKey] then
            for row = 1, 10 do
                local yKey = "y" .. row
                local b = data.Honeycomb[xKey][yKey]
                if b and b.Type then
                    table.insert(bees, {
                        lvl = tonumber(b.Lvl) or 1,
                        bond = tonumber(b.Bond) or 0
                    })
                end
            end
        end
    end

    table.sort(bees, function(a, b)
        if a.lvl == b.lvl then
            return a.bond > b.bond
        end
        return a.lvl > b.lvl
    end)

    local totalTreats = 0
    local alreadyAtTarget = 0
    local count = 0
    local limit = math.min(tgtBees or 50, #bees)

    for _, b in ipairs(bees) do
        if count >= limit then break end
        count = count + 1
        if b.lvl >= tgtLvl then
            alreadyAtTarget = alreadyAtTarget + 1
        else
            local remBond = math.max(0, tgtCum - b.bond)
            totalTreats = totalTreats + math.ceil(remBond / effBond)
        end
    end

    local totalHoney = totalTreats * TREAT_COST
    return totalHoney, totalTreats, alreadyAtTarget, limit
end


local function getMyHive()
    local honeycombs = workspace:FindFirstChild("Honeycombs")
    if not honeycombs then return nil end

    if player:FindFirstChild("Honeycomb") and player.Honeycomb.Value then
        local hVal = player.Honeycomb.Value
        if typeof(hVal) == "Instance" then return hVal end
        local h = honeycombs:FindFirstChild(tostring(hVal))
        if h then return h end
    end

    for _, hive in ipairs(honeycombs:GetChildren()) do
        local owner = hive:FindFirstChild("Owner")
        if owner and (owner.Value == player or owner.Value == player.Name or tostring(owner.Value) == player.Name or (player.Character and owner.Value == player.Character)) then
            return hive
        end
    end
    return nil
end

local function getRarityColor(beeType, isGifted)
    local t = tostring(beeType or ""):lower()
    if t:find("spicy") or t:find("buoyant") or t:find("precise") or t:find("vector") or t:find("tadpole") or t:find("fuzzy") then
        return Color3.fromRGB(189, 164, 255)
    elseif t:find("bear") or t:find("tabby") or t:find("vicious") or t:find("gummy") or t:find("photon") or t:find("festive") or t:find("windy") or t:find("digital") or t:find("puppy") or t:find("cobalt") or t:find("crimson") then
        return Color3.fromRGB(158, 234, 106)
    elseif t:find("music") or t:find("baby") or t:find("carpenter") or t:find("ninja") or t:find("demon") or t:find("diamond") or t:find("lion") or t:find("shy") then
        return Color3.fromRGB(75, 246, 224)
    elseif t:find("commander") or t:find("frosty") or t:find("fire") or t:find("rage") or t:find("honey") or t:find("riley") or t:find("bucko") or t:find("shocked") or t:find("exhausted") or t:find("demo") or t:find("bubble") then
        return Color3.fromRGB(245, 208, 16)
    elseif t:find("bomber") or t:find("brave") or t:find("bumble") or t:find("cool") or t:find("hasty") or t:find("looker") or t:find("rad") or t:find("rascal") or t:find("stubborn") then
        return Color3.fromRGB(220, 221, 228)
    elseif t:find("basic") then
        return Color3.fromRGB(174, 121, 47)
    end
    return Color3.fromRGB(35, 38, 48)
end

local function getCellData(cell)
    if not cell then return nil end
    local cellTypeVal = cell:FindFirstChild("CellType") or cell:FindFirstChild("Type")
    local rawType = tostring((cellTypeVal and cellTypeVal.Value) or cell:GetAttribute("CellType") or "Empty")
    -- BSS reports the short type ("Basic", "Bomber") while the rest of the tool
    -- (web catalogue, roll targets) uses ids ("BasicBee"). Normalise here once.
    local typeName = RouteSteps.canonicalBeeId(rawType)
    local lowType = typeName:lower()
    if lowType == "" or lowType == "none" or lowType == "nil" then typeName = "Empty" end

    local col, row = cell.Name:match("C(%d+),(%d+)")
    col = tonumber(col) or (cell:FindFirstChild("CellX") and cell.CellX.Value) or 1
    row = tonumber(row) or (cell:FindFirstChild("CellY") and cell.CellY.Value) or 1

    local fp = cell:FindFirstChild("Faceplate")
    local decal = fp and fp:FindFirstChildOfClass("Decal")
    local faceTexture = decal and decal.Texture or "rbxassetid://1471882621"
    local faceColor = decal and decal.Color3 or Color3.fromRGB(0, 0, 0)
    
    local bp = cell:FindFirstChild("Backplate")
    local bgColor = (bp and bp:IsA("BasePart") and bp.Color) or getRarityColor(typeName, false)

    local lp = cell:FindFirstChild("LevelPart")
    local lvlVal = 1
    if lp then
        local tl = lp:FindFirstChildWhichIsA("TextLabel", true)
        if tl then
            local digits = tostring(tl.Text or ""):match("(%d+)")
            if digits then lvlVal = tonumber(digits) or 1 end
        end
    end

    -- Gifted is stored in different ways across BSS updates: a "Gifted" attribute,
    -- a marker child, a "GiftedCell" model, a type name, or the golden star
    -- particle. Check every source so a gifted bee is never missed.
    local isGifted = false
    local okA, attrs = pcall(function() return cell:GetAttributes() end)
    if okA and type(attrs) == "table" then
        for k, v in pairs(attrs) do
            local vs = tostring(v):lower()
            local lk = tostring(k):lower()
            if (lk:find("gift", 1, true) or lk == "star" or lk == "isstar")
                and (v == true or (type(v) == "number" and v > 0)
                    or vs == "true" or vs == "gifted" or vs == "yes" or vs == "1") then
                isGifted = true
                break
            end
        end
    end
    local giftChild = cell:FindFirstChild("Gifted") or cell:FindFirstChild("IsGifted")
    if giftChild then
        if giftChild:IsA("ValueBase") then
            local gv = giftChild.Value
            local gvs = tostring(gv):lower()
            if gv == true or (type(gv) == "number" and gv > 0)
                or gvs == "true" or gvs == "gifted" or gvs == "yes" or gvs == "1" then
                isGifted = true
            end
        else
            isGifted = true
        end
    end
    if not isGifted and typeName:lower():find("gifted") then isGifted = true end
    if not isGifted then
        for _, desc in ipairs(cell:GetDescendants()) do
            local n = desc.Name:lower()
            if n:find("gifted") or ((desc:IsA("Decal") or desc:IsA("ParticleEmitter")) and n:find("star")) then
                isGifted = true
                break
            end
        end
    end
    if not isGifted and cell:FindFirstChild("GiftedCell") then
        isGifted = true
    end

    return {
        cell = cell,
        cellName = cell.Name,
        col = col,
        row = row,
        beeType = typeName,
        faceTexture = faceTexture,
        faceColor = faceColor,
        bgColor = bgColor,
        level = lvlVal,
        gifted = isGifted
    }
end

local gridCache = nil
local gridCacheTime = 0
local function readHiveGrid(force)
    if not force and gridCache and (os.clock() - gridCacheTime < 0.5) then
        return gridCache
    end
    local myHive = getMyHive()
    local cellsFolder = myHive and myHive:FindFirstChild("Cells") or nil
    local statOk, statData = pcall(getStatData)
    local honeycomb = statOk and statData and statData.Honeycomb
    -- If both the view and the stat cache are missing there is nothing to read.
    if not cellsFolder and type(honeycomb) ~= "table" then return {} end

    -- Some BSS builds keep the gifted flag in the stat cache instead of the
    -- rendered cell. Treat any boolean-ish "gift" field as gifted; the field
    -- name has changed over updates ("Gifted", "IsGifted", "GiftedType").
    local function statGifted(entry)
        if type(entry) ~= "table" then return false end
        for k, v in pairs(entry) do
            local lk = tostring(k):lower()
            if lk:find("gift", 1, true) or lk == "star" or lk == "isstar" then
                local vs = tostring(v):lower()
                if v == true or (type(v) == "number" and v > 0)
                    or vs == "true" or vs == "gifted" or vs == "yes" or vs == "1" then
                    return true
                end
            end
        end
        if type(entry.Type) == "string" and entry.Type:lower():find("gifted") then return true end
        return false
    end

    local grid = {}
    for r = 1, 10 do
        grid[r] = {}
        for c = 1, 5 do
            local cellName = string.format("C%d,%d", c, r)
            local cell = cellsFolder and (cellsFolder:FindFirstChild(cellName)
                or cellsFolder:FindFirstChild(string.format("C%d,R%d", c, r))) or nil
            if cell then
                grid[r][c] = getCellData(cell)
            end
        end
    end

    -- The stat cache is authoritative and is also available while the hive is
    -- streamed out. Overlay gifted/level there and fill cells the workspace did
    -- not provide, so hive counts and SSA never depend on rendering.
    if type(honeycomb) == "table" then
        for r = 1, 10 do
            grid[r] = grid[r] or {}
            for c = 1, 5 do
                local colTable = honeycomb["x" .. c]
                local entry = type(colTable) == "table" and colTable["y" .. r] or nil
                if type(entry) == "table" and entry.Type and entry.Type ~= "" and entry.Type ~= "Empty" then
                    local gifted = statGifted(entry)
                    local existing = grid[r][c]
                    if existing then
                        if gifted then existing.gifted = true end
                        local lvl = tonumber(entry.Lvl)
                        if lvl then existing.level = lvl end
                        if not existing.beeType or existing.beeType == "Empty" then
                            existing.beeType = RouteSteps.canonicalBeeId(entry.Type)
                        end
                    else
                        grid[r][c] = {
                            cell = nil,
                            cellName = string.format("C%d,%d", c, r),
                            col = c,
                            row = r,
                            beeType = RouteSteps.canonicalBeeId(entry.Type),
                            faceTexture = nil,
                            faceColor = Color3.fromRGB(0, 0, 0),
                            bgColor = getRarityColor(tostring(entry.Type or ""), gifted),
                            level = tonumber(entry.Lvl) or 1,
                            gifted = gifted,
                        }
                    end
                end
            end
        end
    end

    gridCache = grid
    gridCacheTime = os.clock()
    return grid
end

local function tweenTo(cf, speed)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChild("Humanoid")
    if not root or not hum or not cf then return false end

    local targetCFrame = if typeof(cf) == "CFrame" then cf else CFrame.new(cf)
    local spd = math.max(tonumber(speed) or tonumber(walkSpeed) or 65, 1)
    local startPos = root.Position
    local endPos = targetCFrame.Position
    local dist = (startPos - endPos).Magnitude
    if dist < 2 then return true end

    if activeTween then
        pcall(function() activeTween:Cancel() end)
        activeTween = nil
    end

    local noclipConn = RunService.Stepped:Connect(function()
        if char and char.Parent then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end)

    hum.PlatformStand = true
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero

    local dir = endPos - startPos
    local flatDir = Vector3.new(dir.X, 0, dir.Z)
    local targetRot = if flatDir.Magnitude > 0.1 then CFrame.lookAt(endPos, endPos + flatDir).Rotation else targetCFrame.Rotation
    local finalCFrame = CFrame.new(endPos) * targetRot

    local duration = math.max(0.15, dist / spd)
    local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = finalCFrame })
    activeTween = tween
    tween:Play()

    local done = false
    local conn = tween.Completed:Connect(function() done = true end)
    while not done do
        if not scriptAlive or (not feedRunning and not rollRunning) or not char.Parent or not root.Parent then
            tween:Cancel()
            break
        end
        task.wait(0.03)
    end
    conn:Disconnect()

    noclipConn:Disconnect()
    hum.PlatformStand = false
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    if activeTween == tween then activeTween = nil end

    return root.Parent ~= nil and (root.Position - endPos).Magnitude <= 5
end

local atlasPauseObj = nil
local atlasPauseBtn = nil
local lastPauseState = nil
local userPauseState = nil
local lastPauseSearch = 0

function pauseAtlas(enable)
    if not autoPauseAtlas then return false end
    if lastPauseState == enable then return true end

    -- A stop/cleanup call must never resume a pause the user set before we
    -- ever paused Atlas.
    if not enable and lastPauseState ~= true and userPauseState == nil then
        return true
    end

    if enable and userPauseState == nil and atlasPauseObj then
        userPauseState = rawget(atlasPauseObj, "Value") or rawget(atlasPauseObj, "State")
    end

    local targetState = enable
    if not enable and userPauseState == true then
        targetState = true
    end

    if atlasPauseObj then
        local currentState = rawget(atlasPauseObj, "Value") or rawget(atlasPauseObj, "State")
        if currentState == targetState then
            lastPauseState = enable and true or false
            if not enable then userPauseState = nil end
            return true
        end
        if type(rawget(atlasPauseObj, "Set")) == "function" then
            local ok = pcall(function() atlasPauseObj:Set(targetState) end)
            if ok then
                lastPauseState = enable and true or false
                if not enable then userPauseState = nil end
                return true
            end
        elseif type(rawget(atlasPauseObj, "Callback")) == "function" then
            local ok = pcall(function() atlasPauseObj.Callback(targetState) end)
            if ok then
                lastPauseState = enable and true or false
                if not enable then userPauseState = nil end
                return true
            end
        end
    end

    -- A tab switch can repurpose the shared switch control, so only trust a
    -- cached button while its label still says "Stop Everything".
    if atlasPauseBtn then
        local title = atlasPauseBtn.Parent and atlasPauseBtn:FindFirstChild("Title")
        if not atlasPauseBtn.Parent or not title or not tostring(title.Text or ""):lower():find("stop everything", 1, true) then
            atlasPauseBtn = nil
            lastPauseSearch = 0
        end
    end

    local restoreAtlasTab = nil
    if not atlasPauseObj and not atlasPauseBtn then
        if os.clock() - lastPauseSearch < 10 then
            return false
        end
        lastPauseSearch = os.clock()

        if getgc then
            local success, gc = pcall(getgc, true)
            if success and type(gc) == "table" then
                for _, obj in ipairs(gc) do
                    if typeof(obj) == "table" then
                        local name = rawget(obj, "Title") or rawget(obj, "Name") or rawget(obj, "Text")
                        if type(name) == "string" and name:lower():find("stop everything") and not name:lower():find("auto pause") then
                            if type(rawget(obj, "Set")) == "function" then
                                atlasPauseObj = obj
                                local currentState = rawget(obj, "Value") or rawget(obj, "State")
                                if enable and userPauseState == nil then
                                    userPauseState = currentState
                                end
                                local target = enable and true or (userPauseState == true)
                                if currentState ~= target then
                                    pcall(function() obj:Set(target) end)
                                end
                                lastPauseState = enable and true or false
                                if not enable then userPauseState = nil end
                                return true
                            elseif type(rawget(obj, "Callback")) == "function" then
                                atlasPauseObj = obj
                                local currentState = rawget(obj, "Value") or rawget(obj, "State")
                                if enable and userPauseState == nil then
                                    userPauseState = currentState
                                end
                                local target = enable and true or (userPauseState == true)
                                if currentState ~= target then
                                    pcall(function() obj.Callback(target) end)
                                end
                                lastPauseState = enable and true or false
                                if not enable then userPauseState = nil end
                                return true
                            end
                        end
                    end
                end
            end
        end

        local roots = {}
        local hui = (gethui and gethui()) or game:GetService("CoreGui")
        roots[#roots + 1] = hui
        local playerGui = player:FindFirstChild("PlayerGui")
        if playerGui and playerGui ~= hui then
            roots[#roots + 1] = playerGui
        end

        local function findStopButton()
            for _, root in ipairs(roots) do
                for _, desc in ipairs(root:GetDescendants()) do
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                        local text = tostring(desc.Text or ""):lower()
                        if text:find("stop everything", 1, true) and not text:find("auto pause", 1, true) then
                            -- Atlas puts the label inside the switch button;
                            -- the button itself is the parent, not a child.
                            local btn = nil
                            if desc:IsA("GuiButton") then
                                btn = desc
                            elseif desc.Parent and desc.Parent:IsA("GuiButton") then
                                btn = desc.Parent
                            elseif desc.Parent then
                                btn = desc.Parent:FindFirstChildWhichIsA("GuiButton", true)
                            end
                            if btn then return btn end
                        end
                    end
                end
            end
            return nil
        end

        -- The Atlas pause switch only exists while its Home tab is selected.
        -- Switch there briefly and remember the tab to restore afterwards.
        local function switchAtlasToHome()
            if not firesignal then return nil, false end
            local atlasRoot = nil
            for _, root in ipairs(roots) do
                for _, desc in ipairs(root:GetDescendants()) do
                    if desc:IsA("TextLabel") and tostring(desc.Text or ""):find("Atlas v", 1, true) then
                        atlasRoot = desc:FindFirstAncestorOfClass("ScreenGui")
                        break
                    end
                end
                if atlasRoot then break end
            end
            if not atlasRoot then return nil, false end
            local window = atlasRoot:FindFirstChild("Window")
            local tabButtons = window and window:FindFirstChild("TabButtons")
            local bar = tabButtons and tabButtons:FindFirstChild("ScrollingFrame")
            if not bar then return nil, false end

            local homeBtn = nil
            local activeBtn = nil
            local lowest = 2
            for _, b in ipairs(bar:GetChildren()) do
                if b:IsA("TextButton") then
                    local label = tostring(b.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if label == "Home" then homeBtn = b end
                    local trans = tonumber(b.BackgroundTransparency) or 1
                    if trans < lowest then
                        lowest = trans
                        activeBtn = b
                    end
                end
            end
            if not homeBtn or activeBtn == homeBtn then return nil, false end
            local ok = pcall(firesignal, homeBtn.MouseButton1Click)
            if not ok then return nil, false end
            return activeBtn, true
        end

        atlasPauseBtn = findStopButton()
        if not atlasPauseBtn then
            local activeBtn, switched = switchAtlasToHome()
            if switched then
                restoreAtlasTab = activeBtn
                atlasPauseBtn = findStopButton()
                if not atlasPauseBtn then
                    if restoreAtlasTab and restoreAtlasTab.Parent then
                        pcall(firesignal, restoreAtlasTab.MouseButton1Click)
                    end
                    restoreAtlasTab = nil
                end
            end
        end
    end

    if atlasPauseBtn and firesignal then
        -- Atlas v1.0 marks the active "Stop Everything" switch with a check
        -- mark. Other builds may keep the switch value inside the click
        -- callback, so use that only when the text does not tell us the state.
        local function buttonState(btn)
            if not btn then return nil end
            local text = tostring(btn.Text or "")
            if text:find("✓", 1, true) then return true end
            if text ~= "" then return true end
            if getconnections and debug and type(debug.getupvalues) == "function" then
                local ok, list = pcall(getconnections, btn.MouseButton1Click)
                if ok and type(list) == "table" then
                    for _, conn in ipairs(list) do
                        local okState, ups = pcall(debug.getupvalues, conn.Function)
                        if okState and type(ups) == "table" then
                            local state = ups[1]
                            if type(state) == "table" and type(state[1]) == "boolean" then
                                return state[1]
                            end
                        end
                    end
                end
            end
            return false
        end
        local function restoreAtlasTabs()
            if restoreAtlasTab then
                if restoreAtlasTab.Parent then
                    pcall(firesignal, restoreAtlasTab.MouseButton1Click)
                end
                restoreAtlasTab = nil
                atlasPauseBtn = nil
                lastPauseSearch = 0
            end
        end

        local currentState = buttonState(atlasPauseBtn)
        if enable and userPauseState == nil then
            userPauseState = currentState
        end
        if not enable then
            targetState = (userPauseState == true)
        end

        -- If Atlas is already in the requested state, do not click the toggle.
        if currentState ~= nil and currentState == targetState then
            lastPauseState = enable and true or false
            if not enable then userPauseState = nil end
            restoreAtlasTabs()
            return true
        end

        -- Atlas versions differ: some connect "Activated", some connect
        -- "MouseButton1Click". Firing both can toggle twice (pause then resume)
        -- on versions that connect both signals, so fire only the one that is
        -- actually connected when getconnections is available.
        local fired = false
        local function isConnected(signal)
            if not getconnections then return nil end
            local ok, list = pcall(getconnections, signal)
            if not ok or type(list) ~= "table" then return nil end
            return #list > 0
        end

        local activated = isConnected(atlasPauseBtn.Activated)
        local clicked = isConnected(atlasPauseBtn.MouseButton1Click)
        local signal = nil
        if clicked == true then
            signal = atlasPauseBtn.MouseButton1Click
        elseif activated == true then
            signal = atlasPauseBtn.Activated
        else
            -- No getconnections, or neither signal reports a connection:
            -- MouseButton1Click is the signal most Atlas buttons use.
            signal = atlasPauseBtn.MouseButton1Click
        end

        if signal then
            fired = pcall(firesignal, signal)
        end
        if fired then
            lastPauseState = enable and true or false
            if not enable then userPauseState = nil end
            restoreAtlasTabs()
            return true
        end
        restoreAtlasTabs()
    end

    return false
end

-- While auto feed / auto roll is working, keep the character exactly where it
-- is. Pausing Atlas is not always enough: a tween or a queued Atlas action can
-- still move the character for a moment. The hold anchors the root and zeroes
-- movement until stopAutoFeed / stopAutoRoll releases it. State lives on
-- getgenv so the main chunk does not exceed Luau's 200-local register limit.
getgenv().IvyisAtlasHold = getgenv().IvyisAtlasHold or {}

getgenv().IvyisAtlasHold.start = function()
    if not autoPauseAtlas then return false end

    local hold = getgenv().IvyisAtlasHold
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChild("Humanoid")
    if not root or not hum then return false end

    if not hold.active then
        hold.prevAnchored = root.Anchored
        hold.prevWalkSpeed = hum.WalkSpeed
        hold.prevJumpPower = hum.JumpPower
        hold.prevJumpHeight = hum.JumpHeight
    end

    hold.active = true
    hold.root = root
    hold.humanoid = hum
    hold.cframe = root.CFrame
    root.Anchored = true
    hum.WalkSpeed = 0
    hum.JumpPower = 0
    hum.JumpHeight = 0
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero

    if not hold.conn then
        hold.conn = RunService.Heartbeat:Connect(function()
            if not hold.active then return end

            local currentChar = player.Character
            local currentRoot = currentChar and currentChar:FindFirstChild("HumanoidRootPart")
            local currentHum = currentChar and currentChar:FindFirstChild("Humanoid")
            if not currentRoot then return end

            -- Respawned while holding: let the next loop re-acquire the hive
            -- instead of teleporting the new character back to the old one.
            if currentRoot ~= hold.root then
                hold.release()
                return
            end

            if hold.cframe and (currentRoot.Position - hold.cframe.Position).Magnitude > 0.05 then
                currentRoot.CFrame = hold.cframe
            end
            currentRoot.AssemblyLinearVelocity = Vector3.zero
            currentRoot.AssemblyAngularVelocity = Vector3.zero
            if currentHum then
                currentHum.WalkSpeed = 0
                currentHum.JumpPower = 0
                currentHum.JumpHeight = 0
                currentHum:Move(Vector3.zero)
            end
        end)
    end

    return true
end

getgenv().IvyisAtlasHold.release = function()
    local hold = getgenv().IvyisAtlasHold
    if not hold then return end
    hold.active = false
    if hold.conn then
        pcall(function() hold.conn:Disconnect() end)
        hold.conn = nil
    end

    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChild("Humanoid")
    if root and hold.root == root then
        root.Anchored = hold.prevAnchored
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
    if hum and hold.humanoid == hum then
        hum.WalkSpeed = hold.prevWalkSpeed or 16
        hum.JumpPower = hold.prevJumpPower or 50
        hum.JumpHeight = hold.prevJumpHeight or 0
    end

    hold.root = nil
    hold.humanoid = nil
    hold.cframe = nil
end

local function getHiveStandPos()
    local myHive = getMyHive()
    if not myHive then return nil end
    local platVal = myHive:FindFirstChild("Platform") and myHive.Platform.Value
    if platVal and platVal:IsA("PVInstance") then
        return platVal:GetPivot() + Vector3.new(0, 3.5, 0)
    end
    return myHive:GetPivot() + Vector3.new(0, 3.5, 0)
end

local function getShopFloorPos(shopFolderName, fallbackCFrame)
    local shops = workspace:FindFirstChild("Shops")
    local shopFolder = shops and shops:FindFirstChild(shopFolderName)
    local floorVal = shopFolder and shopFolder:FindFirstChild("Floor")
    local floorPart = floorVal and floorVal.Value
    if floorPart and floorPart:IsA("PVInstance") then
        return floorPart:GetPivot() + Vector3.new(0, 3.5, 0)
    end
    return fallbackCFrame
end

local function getTreatShopPos()
    return getShopFloorPos("TreatShop", TREAT_SHOP_POS)
end

local function getRJShopPos()
    return getShopFloorPos("JellyDispenser", RJ_SHOP_POS)
end

local function goToHive()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local standPos = getHiveStandPos()
    if not standPos then return false end
    local dist = (root.Position - standPos.Position).Magnitude
    if dist > 20 then
        return tweenTo(standPos)
    end
    return true
end

local function goToPos(targetPos, maxDist)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root or not targetPos then return false end
    local dist = (root.Position - targetPos.Position).Magnitude
    if dist > (maxDist or 20) then
        return tweenTo(targetPos)
    end
    return true
end

local function buyTreats(amount)
    local remote = getRemote("ItemPackageEvent")
    if not remote or amount <= 0 then return false end
    local amt = math.floor(amount)
    return pcall(function()
        callRemote(remote, "Purchase", {
            Type = "Treat",
            Amount = amt,
            Category = "Eggs"
        })
    end)
end

local function buyRoyalJellies(amount)
    local remote = getRemote("ItemPackageEvent")
    if not remote or amount <= 0 then return false end
    local amt = math.floor(amount)
    return pcall(function()
        callRemote(remote, "Purchase", {
            Type = "RoyalJelly",
            Amount = amt,
            Category = "Eggs"
        })
    end)
end

local function feedBee(col, row, amount)
    local remote = getRemote("ConstructHiveCellFromEgg")
    if not remote or not col or not row or amount <= 0 then return false end
    local c = tonumber(col)
    local r = tonumber(row)
    local amt = math.floor(tonumber(amount) or 0)
    if not c or not r or amt <= 0 then return false end
    return pcall(function()
        callRemote(remote, c, r, "Treat", amt)
    end)
end

local function rollBee(col, row, rjCount, eggType)
    local remote = getRemote("ConstructHiveCellFromEgg")
    if not remote or not col or not row or rjCount <= 0 then return false, nil end
    local c = tonumber(col)
    local r = tonumber(row)
    local amt = math.floor(tonumber(rjCount) or 1)
    local item = tostring(eggType or "RoyalJelly")
    local ok, res = pcall(function()
        return callRemote(remote, c, r, item, amt)
    end)
    return ok, res
end

local function setGameSetting(settingName, val)
    local cache = RS:FindFirstChild("ClientStatCache")
    if cache then
        pcall(function()
            local data = require(cache):Get()
            if data and data.Settings then
                data.Settings[settingName] = val
            end
        end)
    end
    safeClientCall("PlayerSettingsEvent", settingName, val)
end

-- Bee Swarm's "Until gifted" auto-jelly switch is stored as "RollToGifted" in
-- current builds. Very old builds used "UntilGifted"; writing that dead key is
-- silently ignored, so the switch never turned on even though the web asked for
-- it. Detect the key the running game actually uses.
local function giftedRollKey()
    local data = getStatData()
    local settings = data and data.Settings
    if type(settings) == "table" and settings.RollToGifted == nil and settings.UntilGifted ~= nil then
        return "UntilGifted"
    end
    return "RollToGifted"
end

local function setUntilGifted(value)
    pcall(setGameSetting, giftedRollKey(), value == true)
end

local function rollSettingKeys()
    return { "RollToMythic", "RollToLegendary", giftedRollKey() }
end

-- What the game currently has for those three switches. Sent with every state
-- post so the web checkboxes show the real in-game values, not a guess.
local function readRollSettings()
    local data = getStatData()
    local settings = data and data.Settings
    if type(settings) ~= "table" then return nil end
    return {
        untilGifted = settings.RollToGifted == true or settings.UntilGifted == true,
        untilMythic = settings.RollToMythic == true,
        untilLegendary = settings.RollToLegendary == true,
    }
end

local originalRollSettings = nil

-- Web ("select bee" page) roll state, shared with the batch loop further down.
-- "Stop on mythic" keeps Bee Swarm's own Until mythic switch on while the roll
-- runs, so the batch halts on the mythic instead of rolling straight past it.
-- The switch is ours in that case, so the restore below always hands the
-- player's own value back - even when "sync settings" is off.
local webRollRunning = false
local webMythicSwitchOwned = false

captureRollSettings = function()
    if originalRollSettings then return end
    local data = getStatData()
    local settings = data and data.Settings
    if not settings then return end
    local saved = {}
    for _, key in ipairs(rollSettingKeys()) do
        local value = settings[key]
        if type(value) == "boolean" then
            saved[key] = value
        end
    end
    if next(saved) then
        originalRollSettings = saved
    end
end

restoreRollSettings = function()
    local saved = originalRollSettings
    originalRollSettings = nil
    if not saved then return end
    -- With sync off the roll never touched Until mythic/legendary, so restoring
    -- those keys would only overwrite a change the player made in the meantime.
    -- A web "stop on mythic" roll is the exception: that switch was ours.
    local sync = forcedRollFlags.syncSettings ~= false
    local giftedKey = giftedRollKey()
    for key, value in pairs(saved) do
        if key == giftedKey or sync or (webMythicSwitchOwned and key == "RollToMythic") then
            pcall(setGameSetting, key, value)
        end
    end
    webMythicSwitchOwned = false
    -- A finished roll puts the player's own switches back, but the web's
    -- "Until gifted" must survive that restore.
    if forcedRollFlags.untilGifted then
        setUntilGifted(true)
    end
end

-- IvyisUI chi co 3 theme theo Atlas: "Atlas", "Atlas Light", "Atlas Midnight".

-- ===== In-game UI scale (readable on phones) =====
-- IvyisUI lays the window out in unscaled units and multiplies every element by
-- IvyisUI.UIScale. The default 1x is far too small to read on a phone, so the
-- window grows to fill most of the screen when the device is touch-only.
-- NOTE: the main chunk of this file is close to Luau's limit of 200 locals per
-- function, so these helpers all live in one table instead of each taking a
-- local slot of its own. Keep it that way when editing.
local IVYIS_UI = {}
IVYIS_UI.BASE = Vector2.new(560, 350)
IVYIS_UI.CHOICES = { "Auto", "100%", "125%", "150%", "175%", "200%", "250%", "300%" }
IVYIS_UI.window = nil
IVYIS_UI.choice = "Auto"

IVYIS_UI.isTouchDevice = function()
    local ok, touch, keyboard = pcall(function()
        return UserInputService.TouchEnabled, UserInputService.KeyboardEnabled
    end)
    if not ok then return false end
    -- Touch-only device (phone/tablet). Desktop touchscreens still have a keyboard.
    return touch == true and keyboard ~= true
end

IVYIS_UI.viewport = function()
    local cam = workspace.CurrentCamera
    if cam and cam.ViewportSize and cam.ViewportSize.X > 0 and cam.ViewportSize.Y > 0 then
        return cam.ViewportSize
    end
    return Vector2.new(1280, 720)
end

-- How much the base window can grow before it no longer fits on screen.
IVYIS_UI.fitScale = function()
    local vp = IVYIS_UI.viewport()
    return math.min((vp.X - 40) / IVYIS_UI.BASE.X, (vp.Y - 40) / IVYIS_UI.BASE.Y)
end

IVYIS_UI.scaleForChoice = function(choice)
    local percent = tostring(choice or "Auto"):match("^(%d+)%%$")
    if percent then
        return math.clamp(tonumber(percent) / 100, 0.5, 4)
    end
    local fit = IVYIS_UI.fitScale()
    if IVYIS_UI.isTouchDevice() then
        -- Fill 70% of the screen (the second number is the floor for tiny screens).
        return math.clamp(fit * 0.70, 0.85, 2.8)
    end
    -- PC keeps the old behaviour: never larger than 1x, shrink only if needed.
    return math.clamp(fit, 0.6, 1)
end

-- The script's plain ScreenGuis (status HUD, hive-slot picker, mobile button)
-- grow with the same setting so the whole in-game UI stays readable together.
IVYIS_UI.scaledGuis = {}
IVYIS_UI.refreshers = {}

IVYIS_UI.panelScale = function()
    return IVYIS_UI.scaleForChoice(IVYIS_UI.choice)
end

-- Same boost as the panel, but never bigger than what still fits on screen.
IVYIS_UI.guiScaleFor = function(designW, designH, maxScale)
    local vp = IVYIS_UI.viewport()
    local fitX = (vp.X * 0.92) / math.max(tonumber(designW) or 1, 1)
    local fitY = (vp.Y * 0.92) / math.max(tonumber(designH) or 1, 1)
    return math.clamp(math.min(IVYIS_UI.panelScale(), math.min(fitX, fitY)), 0.5, maxScale or 2.5)
end

IVYIS_UI.registerGuiScale = function(screenGui, designW, designH, maxScale)
    if not screenGui then return end
    IVYIS_UI.scaledGuis[#IVYIS_UI.scaledGuis + 1] = { gui = screenGui, w = designW, h = designH, max = maxScale }
    local uiScale = screenGui:FindFirstChildOfClass("UIScale")
    if not uiScale then
        uiScale = Instance.new("UIScale")
        uiScale.Parent = screenGui
    end
    uiScale.Scale = IVYIS_UI.guiScaleFor(designW, designH, maxScale)
    return uiScale
end

IVYIS_UI.registerScaleRefresher = function(fn)
    if type(fn) == "function" then
        IVYIS_UI.refreshers[#IVYIS_UI.refreshers + 1] = fn
        pcall(fn)
    end
end

IVYIS_UI.refreshGuiScales = function()
    for _, entry in ipairs(IVYIS_UI.scaledGuis) do
        local gui = entry.gui
        if gui and gui.Parent then
            local uiScale = gui:FindFirstChildOfClass("UIScale")
            if uiScale then
                uiScale.Scale = IVYIS_UI.guiScaleFor(entry.w, entry.h, entry.max)
            end
        end
    end
    for _, fn in ipairs(IVYIS_UI.refreshers) do
        pcall(fn)
    end
end

IVYIS_UI.apply = function(choice)
    if choice ~= nil then IVYIS_UI.choice = choice end
    if not IVYIS_UI.window then return end
    pcall(function()
        local scale = IVYIS_UI.scaleForChoice(IVYIS_UI.choice)
        pcall(function() IVYIS_UI.window:SetUIScale(scale) end)
        pcall(IVYIS_UI.refreshGuiScales)
        if getgenv then
            pcall(function() getgenv().IvyisUiScale = scale end)
        end
    end)
end

local Window = IvyisUI:CreateWindow({
    Title = "Ivyis BSS",
    Size = UDim2.fromOffset(IVYIS_UI.BASE.X, IVYIS_UI.BASE.Y),
    -- Ivyis da co nut bee rieng (AutoFeed_MobileToggle) nen khong dung nut noi cua Atlas
    FloatingButton = false
})

-- Set the scale before the tabs are built so every element is laid out with it.
IVYIS_UI.window = Window
pcall(IVYIS_UI.apply, IVYIS_UI.choice)

-- The status HUD lives in its own ScreenGui, created earlier inside another scope,
-- so it is looked up by name instead of by local variable.
IVYIS_UI.findHudGui = function()
    local ok, found = pcall(function()
        local roots = {}
        if gethui then
            local okHui, huiRoot = pcall(gethui)
            if okHui and huiRoot then roots[#roots + 1] = huiRoot end
        end
        roots[#roots + 1] = CoreGui
        roots[#roots + 1] = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
        for _, root in ipairs(roots) do
            local hud = root and root:FindFirstChild("AutoProg_HUD")
            if hud and hud:IsA("ScreenGui") then return hud end
        end
        return nil
    end)
    if ok then return found end
    return nil
end

-- Keep the HUD readable too (it is a separate ScreenGui made in another scope).
do
    local hudGuiForScale = IVYIS_UI.findHudGui()
    if hudGuiForScale then
        pcall(IVYIS_UI.registerGuiScale, hudGuiForScale, 600, 20, 2.5)
    end
end

-- IvyisUI: theme mac dinh la Atlas; khong co nut close / minimize / fullscreen.
pcall(function() IvyisUI:SetTheme("Atlas") end)

local FeedTab = Window:Tab({ Title = "Feed", Icon = "cookie" })
local HiveTab = Window:Tab({ Title = "Hive", Icon = "grid" })
local ProgTab = Window:Tab({ Title = "Progress", Icon = "route" })
local GearTab = Window:Tab({ Title = "Gear", Icon = "backpack" })
local SettingsTab = Window:Tab({ Title = "Settings", Icon = "settings" })

-- luu cai dat vao workspace cua executor, lan sau execute tu nap lai
local SettingsStore = {
    path = "AutoFeedBSS/settings_" .. tostring(player.Name):gsub("[^%w_%-]", "_") .. ".json",
    sharedPath = "AutoFeedBSS/settings.json", -- file chung cu, chi doc de lam mau lan dau
    data = {},
    pending = {},
    ready = false,
    queued = false,
    skip = {
        ["Auto feed"] = true, ["Auto roll"] = true,
        ["Show info text on screen"] = true, ["Paste layout text"] = true,
        ["Discord link code"] = true,
    },
}

do
    if isfile and readfile then
        local source = isfile(SettingsStore.path) and SettingsStore.path
            or (isfile(SettingsStore.sharedPath) and SettingsStore.sharedPath)
        if source then
            local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(source)) end)
            if ok and type(decoded) == "table" then SettingsStore.data = decoded end
        end
    end

    local function writeNow()
        if not writefile then return end
        pcall(function()
            if makefolder and isfolder and not isfolder("AutoFeedBSS") then makefolder("AutoFeedBSS") end
        end)
        pcall(writefile, SettingsStore.path, HttpService:JSONEncode(SettingsStore.data))
    end

    local function queueWrite()
        if SettingsStore.queued then return end
        SettingsStore.queued = true
        task.delay(1.5, function()
            SettingsStore.queued = false
            writeNow()
        end)
    end

    local function hasValue(list, v)
        if type(list) ~= "table" then return false end
        for _, x in ipairs(list) do if x == v then return true end end
        return false
    end

    local function hook(tab, tabName)
        for _, kind in ipairs({ "Toggle", "Slider", "Dropdown", "Input" }) do
            local original = tab[kind]
            tab[kind] = function(self, opts)
                if not opts.Callback or SettingsStore.skip[opts.Title] then
                    return original(self, opts)
                end
                local key = tabName .. "/" .. tostring(opts.Title)
                local callback = opts.Callback
                local saved = SettingsStore.data[key]
                local usable = false
                if saved ~= nil then
                    if kind == "Toggle" and type(saved) == "boolean" then
                        opts.Value = saved; usable = true
                    elseif kind == "Slider" and type(saved) == "number" and type(opts.Value) == "table" then
                        saved = math.max(opts.Value.Min, math.min(opts.Value.Max, saved))
                        opts.Value.Default = saved; usable = true
                    elseif kind == "Dropdown" and type(saved) == "string" and hasValue(opts.Values, saved) then
                        opts.Value = saved; usable = true
                    elseif kind == "Input" and type(saved) == "string" then
                        opts.Value = saved; usable = true
                    end
                end
                local wrapped = function(v, ...)
                    if SettingsStore.ready then
                        SettingsStore.data[key] = v
                        queueWrite()
                    end
                    return callback(v, ...)
                end
                opts.Callback = wrapped
                if usable then
                    SettingsStore.pending[#SettingsStore.pending + 1] = { wrapped, saved }
                end
                return original(self, opts)
            end
        end
    end

    hook(FeedTab, "Feed")
    hook(HiveTab, "Hive")
    hook(ProgTab, "Progress")
    hook(GearTab, "Gear")
    hook(SettingsTab, "Settings")
end
FeedTab:Section({ Title = "Feed settings" })

local treatStatusLabel = FeedTab:Paragraph({
    Title = "Status",
    Desc = "checking..."
})

local function refreshTreatStatus()
    local totalHoney, totalTreats, alreadyAtTarget, limit = calcHoneyNeeded(targetLevel, targetBeeCount)
    if limit == 0 then
        treatStatusLabel:SetDesc(string.format("Target Lvl: %d | Bees: %d | Honey Needed: 0", targetLevel, targetBeeCount))
        return
    end
    if alreadyAtTarget >= limit then
        treatStatusLabel:SetDesc(string.format("Target Lvl: %d | Bees: %d | Honey Needed: 0 (Done)", targetLevel, targetBeeCount))
    else
        treatStatusLabel:SetDesc(string.format("Target Lvl: %d | Bees: %d | Honey Needed: %s", targetLevel, targetBeeCount, formatNum(totalHoney)))
    end
end

FeedTab:Slider({
    Title = "Target Level",
    Step = 1,
    Value = { Min = 1, Max = 25, Default = 15 },
    Callback = function(v)
        targetLevel = v
        refreshTreatStatus()
    end
})

FeedTab:Slider({
    Title = "Target Bee Count",
    Step = 1,
    Value = { Min = 1, Max = 50, Default = 50 },
    Callback = function(v)
        targetBeeCount = v
        refreshTreatStatus()
    end
})

refreshTreatStatus()

FeedTab:Toggle({
    Title = "Buy treats when out",
    Value = true,
    Callback = function(v) autoBuyEnabled = v end
})

FeedTab:Toggle({
    Title = "Go back to hive after buying",
    Value = true,
    Callback = function(v) returnHiveEnabled = v end
})

FeedTab:Slider({
    Title = "Walk speed",
    Step = 5,
    Value = { Min = 20, Max = 120, Default = 60 },
    Callback = function(v) walkSpeed = v end
})

FeedTab:Section({ Title = "Run" })

feedToggle = FeedTab:Toggle({
    Title = "Auto feed",
    Value = false,
    Callback = function(v)
        if v == feedRunning then return end
        feedRunning = v
        if feedRunning then
            if rollRunning then
                stopAutoRoll(true)
            end
            pauseAtlas(true)
            IvyisUI:Notify({ Title = "Auto Feed", Content = "Feeding started", Duration = 3 })
        else
            stopAutoFeed()
            IvyisUI:Notify({ Title = "Auto Feed", Content = "Feeding stopped", Duration = 3 })
            refreshTreatStatus()
        end
    end
})

HiveTab:Section({ Title = "Hive layout" })

local builderStatusLabel = HiveTab:Paragraph({
    Title = "Slots",
    Desc = "picked 0/50 slots, 0 bees wanted"
})

local function getShortBeeName(id)
    if not id then return "?" end
    return (id:gsub("Bee$", ""):gsub("^%s+", ""))
end

local ALL_BEES = {
    { id = "BuoyantBee", name = "Buoyant Bee", rarity = "Mythic" },
    { id = "FuzzyBee", name = "Fuzzy Bee", rarity = "Mythic" },
    { id = "PreciseBee", name = "Precise Bee", rarity = "Mythic" },
    { id = "SpicyBee", name = "Spicy Bee", rarity = "Mythic" },
    { id = "TadpoleBee", name = "Tadpole Bee", rarity = "Mythic" },
    { id = "VectorBee", name = "Vector Bee", rarity = "Mythic" },
    { id = "BabyBee", name = "Baby Bee", rarity = "Legendary" },
    { id = "CarpenterBee", name = "Carpenter Bee", rarity = "Legendary" },
    { id = "DemonBee", name = "Demon Bee", rarity = "Legendary" },
    { id = "DiamondBee", name = "Diamond Bee", rarity = "Legendary" },
    { id = "LionBee", name = "Lion Bee", rarity = "Legendary" },
    { id = "MusicBee", name = "Music Bee", rarity = "Legendary" },
    { id = "NinjaBee", name = "Ninja Bee", rarity = "Legendary" },
    { id = "ShyBee", name = "Shy Bee", rarity = "Legendary" },
    { id = "BubbleBee", name = "Bubble Bee", rarity = "Epic" },
    { id = "BuckoBee", name = "Bucko Bee", rarity = "Epic" },
    { id = "CommanderBee", name = "Commander Bee", rarity = "Epic" },
    { id = "DemoBee", name = "Demo Bee", rarity = "Epic" },
    { id = "ExhaustedBee", name = "Exhausted Bee", rarity = "Epic" },
    { id = "FireBee", name = "Fire Bee", rarity = "Epic" },
    { id = "FrostyBee", name = "Frosty Bee", rarity = "Epic" },
    { id = "HoneyBee", name = "Honey Bee", rarity = "Epic" },
    { id = "RageBee", name = "Rage Bee", rarity = "Epic" },
    { id = "RileyBee", name = "Riley Bee", rarity = "Epic" },
    { id = "ShockedBee", name = "Shocked Bee", rarity = "Epic" },
    { id = "BomberBee", name = "Bomber Bee", rarity = "Rare" },
    { id = "BraveBee", name = "Brave Bee", rarity = "Rare" },
    { id = "BumbleBee", name = "Bumble Bee", rarity = "Rare" },
    { id = "CoolBee", name = "Cool Bee", rarity = "Rare" },
    { id = "HastyBee", name = "Hasty Bee", rarity = "Rare" },
    { id = "LookerBee", name = "Looker Bee", rarity = "Rare" },
    { id = "RadBee", name = "Rad Bee", rarity = "Rare" },
    { id = "RascalBee", name = "Rascal Bee", rarity = "Rare" },
    { id = "StubbornBee", name = "Stubborn Bee", rarity = "Rare" },
    { id = "BasicBee", name = "Basic Bee", rarity = "Common" },
    { id = "BearBee", name = "Bear Bee", rarity = "Event" },
    { id = "CobaltBee", name = "Cobalt Bee", rarity = "Event" },
    { id = "CrimsonBee", name = "Crimson Bee", rarity = "Event" },
    { id = "DigitalBee", name = "Digital Bee", rarity = "Event" },
    { id = "FestiveBee", name = "Festive Bee", rarity = "Event" },
    { id = "GummyBee", name = "Gummy Bee", rarity = "Event" },
    { id = "PhotonBee", name = "Photon Bee", rarity = "Event" },
    { id = "PuppyBee", name = "Puppy Bee", rarity = "Event" },
    { id = "TabbyBee", name = "Tabby Bee", rarity = "Event" },
    { id = "ViciousBee", name = "Vicious Bee", rarity = "Event" },
    { id = "WindyBee", name = "Windy Bee", rarity = "Event" }
}

local beeMapById = {}
local beeMapByOption = {}
local beeDropdownOptions = {}

for _, b in ipairs(ALL_BEES) do
    beeMapById[b.id] = b
    local opt = b.name
    beeMapByOption[opt] = b.id
    beeMapByOption[b.id] = b.id
    -- Basic Bee is the starter bee and can never be rolled/applied as a target.
    -- Keep it resolvable (existing layouts, hive scans) but out of the picker.
    if b.id ~= "BasicBee" then
        table.insert(beeDropdownOptions, opt)
    end
end

-- CellType can be short ("Basic"), a full name ("Basic Bee") or an id
-- ("BasicBee"). Resolve all three without adding another chunk-level local.
RouteSteps.beeByKey = {}
for _, b in ipairs(ALL_BEES) do
    local idKey = b.id:lower()
    local nameKey = b.name:lower()
    RouteSteps.beeByKey[idKey] = b.id
    RouteSteps.beeByKey[idKey:gsub("bee$", "")] = b.id
    RouteSteps.beeByKey[nameKey] = b.id
    RouteSteps.beeByKey[nameKey:gsub("%s*bee$", "")] = b.id
end

function RouteSteps.canonicalBeeId(raw)
    if raw == nil then return "Empty" end
    local s = tostring(raw)
    local key = s:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" or key == "none" or key == "nil" then return "Empty" end
    local map = RouteSteps.beeByKey
    if map then
        local id = map[key]
            or map[key:gsub("%s+", "")]
            or map[key:gsub("%s*bee$", "")]
        if id then return id end
    end
    return s
end

local refreshHiveGrid
local refreshBuilderStatus
local refreshQuotaText
local refreshSsaStatus

local hui = (gethui and gethui()) or game:GetService("CoreGui")
if hui:FindFirstChild("AutoFeed_HiveModalGui") then
    hui:FindFirstChild("AutoFeed_HiveModalGui"):Destroy()
end
if hui:FindFirstChild("AutoFeed_MobileToggle") then
    hui:FindFirstChild("AutoFeed_MobileToggle"):Destroy()
end

-- bat/tat cua so ngay lap tuc, khong chay animation cua IvyisUI
local function findIvyisGui()
    for _, root in ipairs({ (gethui and gethui()) or false, CoreGui, player:FindFirstChild("PlayerGui") }) do
        if root then
            local g = root:FindFirstChild("IvyisUI")
            if g and g:IsA("ScreenGui") then return g end
        end
    end
    return nil
end

local function toggleMainWindow()
    local g = findIvyisGui()
    if g then
        g.Enabled = not g.Enabled
        return
    end
    local winFrame = Window.Frame
    if winFrame then winFrame.Visible = not winFrame.Visible end
end

-- Mobile toggle button. Wrapped in "do ... end" on purpose: the main chunk of
-- this script sits at Luau's limit of 200 locals per function and none of these
-- locals (mobileGui, mobileBtn, ...) are used again further down the file.
do
local mobileGui = Instance.new("ScreenGui")
mobileGui.Name = "AutoFeed_MobileToggle"
mobileGui.ResetOnSpawn = false
mobileGui.DisplayOrder = 999999
mobileGui.Parent = hui

local mobileBtn = Instance.new("TextButton")
mobileBtn.Name = "MobileToggleBtn"
mobileBtn.Size = UDim2.new(0, 48, 0, 48)
mobileBtn.Position = UDim2.new(0, 16, 0.45, 0)
mobileBtn.BackgroundColor3 = Color3.fromRGB(24, 26, 36)
mobileBtn.BackgroundTransparency = 0.1
mobileBtn.BorderSizePixel = 0
mobileBtn.Text = ""
mobileBtn.AutoButtonColor = false
mobileBtn.Parent = mobileGui
local mobileCorner = Instance.new("UICorner", mobileBtn)
mobileCorner.CornerRadius = UDim.new(0, 14)

local mobileStroke = Instance.new("UIStroke")
mobileStroke.Thickness = 1.8
mobileStroke.Color = Color3.fromRGB(0, 200, 255)
mobileStroke.Parent = mobileBtn

local mobileIcon = Instance.new("ImageLabel")
mobileIcon.Size = UDim2.new(0, 30, 0, 30)
mobileIcon.Position = UDim2.new(0.5, -15, 0.5, -15)
mobileIcon.BackgroundTransparency = 1
mobileIcon.Image = "rbxassetid://4503856569"
mobileIcon.Parent = mobileBtn

-- Bigger tap target on phones, following the same "UI size" setting as the
-- panel. The button keeps plain offset sizes so the drag maths stays in real
-- screen pixels.
IVYIS_UI.registerScaleRefresher(function()
    local s = math.clamp(IVYIS_UI.panelScale(), 1, 1.9)
    local size = math.floor(48 * s + 0.5)
    local icon = math.floor(30 * s + 0.5)
    mobileBtn.Size = UDim2.new(0, size, 0, size)
    mobileIcon.Size = UDim2.new(0, icon, 0, icon)
    mobileIcon.Position = UDim2.new(0.5, -icon / 2, 0.5, -icon / 2)
    mobileCorner.CornerRadius = UDim.new(0, math.floor(14 * s + 0.5))
    mobileStroke.Thickness = 1.8 * s
end)

local btnDragging = false
local btnDragStart = nil
local btnStartPos = nil
local btnMoved = false

trackConn(mobileBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        btnDragging = true
        btnDragStart = input.Position
        btnStartPos = mobileBtn.Position
        btnMoved = false
    end
end))

trackConn(UserInputService.InputChanged:Connect(function(input)
    if btnDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - btnDragStart
        if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then btnMoved = true end
        local camera = workspace.CurrentCamera
        local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local curAbsX = btnStartPos.X.Scale * vp.X + btnStartPos.X.Offset
        local curAbsY = btnStartPos.Y.Scale * vp.Y + btnStartPos.Y.Offset
        local btnPx = math.max(mobileBtn.AbsoluteSize.X, 1)
        local newX = math.clamp(curAbsX + delta.X, 0, math.max(vp.X - btnPx - 4, 0))
        local newY = math.clamp(curAbsY + delta.Y, 0, math.max(vp.Y - btnPx - 4, 0))
        mobileBtn.Position = UDim2.new(0, newX, 0, newY)
    end
end))

trackConn(mobileBtn.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        btnDragging = false
    end
end))

trackConn(mobileBtn.Activated:Connect(function()
    if not btnMoved then toggleMainWindow() end
    btnMoved = false
end))

trackConn(UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightControl then toggleMainWindow() end
end))
pcall(function()
    Window:OnClose(function()
        if mobileGui then mobileGui.Enabled = true end
        IvyisUI:Notify({ Title = "Hidden", Content = "Tap the bee button to bring it back", Duration = 3 })
    end)
end)
end -- /mobile toggle button

-- Hive-slot picker modal. Same "do ... end" trick as above: these locals are not
-- referenced after this block, so their registers are released here (200-local limit).
do
local pickerGui = Instance.new("ScreenGui")
pickerGui.Name = "AutoFeed_HiveModalGui"
pickerGui.ResetOnSpawn = false
pickerGui.DisplayOrder = 200000
pickerGui.Parent = hui

-- Grow the hive-slot picker with the same "UI size" setting (never past the
-- screen edges).
pcall(IVYIS_UI.registerGuiScale, pickerGui, 264, 570, 2.5)

local pickerFrame = Instance.new("Frame")
pickerFrame.Name = "HiveSelectionModal"
pickerFrame.Size = UDim2.new(0, 264, 0, 570)
pickerFrame.Position = UDim2.new(0.5, -132, 0.5, -285)
pickerFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
pickerFrame.BackgroundTransparency = 0.05
pickerFrame.BorderSizePixel = 0
pickerFrame.Visible = false
pickerFrame.Parent = pickerGui
Instance.new("UICorner", pickerFrame).CornerRadius = UDim.new(0, 10)

local pickerStroke = Instance.new("UIStroke")
pickerStroke.Color = Color3.fromRGB(40, 45, 60)
pickerStroke.Thickness = 1.5
pickerStroke.Parent = pickerFrame

local headerBar = Instance.new("Frame")
headerBar.Name = "HeaderBar"
headerBar.Size = UDim2.new(1, 0, 0, 36)
headerBar.BackgroundTransparency = 1
headerBar.Parent = pickerFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -24, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Select Hive Slots (0/50)"
titleLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 13
titleLabel.TextXAlignment = Enum.TextXAlignment.Center
titleLabel.Parent = headerBar

local hiveScroll = Instance.new("ScrollingFrame")
hiveScroll.Size = UDim2.new(1, -16, 0, 485)
hiveScroll.Position = UDim2.new(0, 8, 0, 40)
hiveScroll.BackgroundTransparency = 1
hiveScroll.BorderSizePixel = 0
hiveScroll.ScrollBarThickness = 3
hiveScroll.ScrollBarImageColor3 = Color3.fromRGB(50, 60, 80)
hiveScroll.CanvasSize = UDim2.new(0, 0, 0, 475)
hiveScroll.Parent = pickerFrame

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 44, 0, 44)
gridLayout.CellPadding = UDim2.new(0, 3, 0, 3)
gridLayout.FillDirection = Enum.FillDirection.Horizontal
gridLayout.FillDirectionMaxCells = 5
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.Parent = hiveScroll

local bottomCloseBtn = Instance.new("TextButton")
bottomCloseBtn.Size = UDim2.new(1, -16, 0, 32)
bottomCloseBtn.Position = UDim2.new(0, 8, 1, -40)
bottomCloseBtn.BackgroundColor3 = Color3.fromRGB(32, 64, 120)
bottomCloseBtn.BorderSizePixel = 0
bottomCloseBtn.Text = "Close"
bottomCloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
bottomCloseBtn.Font = Enum.Font.GothamBold
bottomCloseBtn.TextSize = 12
bottomCloseBtn.Parent = pickerFrame
Instance.new("UICorner", bottomCloseBtn).CornerRadius = UDim.new(0, 6)
bottomCloseBtn.MouseButton1Click:Connect(function() pickerFrame.Visible = false end)

local slotTiles = {}

function refreshBuilderStatus()
    local selectedCount = 0
    for _, state in pairs(selectedHiveSlots) do
        if state then selectedCount = selectedCount + 1 end
    end
    local totalTargets = 0
    for _, item in ipairs(compositionTargets) do
        totalTargets = totalTargets + (tonumber(item.count) or 0)
    end
    if builderStatusLabel then
        builderStatusLabel:SetDesc(string.format("Selected Slots: %d / 50 | Total Targets Desired: %d", tonumber(selectedCount) or 0, tonumber(totalTargets) or 0))
    end
    if titleLabel then
        titleLabel.Text = string.format("Select Hive Slots (%d/50)", tonumber(selectedCount) or 0)
    end
end

function refreshHiveGrid()
    local cellsGrid = readHiveGrid()
    for _, tile in pairs(slotTiles) do
        if tile and tile.Parent then tile:Destroy() end
    end
    slotTiles = {}

    local layoutIndex = 0
    for r = 10, 1, -1 do
        for c = 1, 5 do
            layoutIndex = layoutIndex + 1
            local cellData = cellsGrid[r] and cellsGrid[r][c]
            local slotKey = string.format("C%d,%d", c, r)

            local isOccupied = cellData and cellData.beeType and cellData.beeType ~= "Empty" and cellData.beeType ~= ""

            local tile = Instance.new("TextButton")
            tile.Name = slotKey
            tile.Text = ""
            tile.AutoButtonColor = false
            tile.BackgroundColor3 = isOccupied and cellData.bgColor or Color3.fromRGB(30, 32, 40)
            tile.BorderSizePixel = 0
            tile.LayoutOrder = layoutIndex
            tile.Parent = hiveScroll
            Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 2)

            local stroke = Instance.new("UIStroke")
            stroke.Thickness = selectedHiveSlots[slotKey] and 2 or 1
            stroke.Color = selectedHiveSlots[slotKey] and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(25, 28, 36)
            stroke.Parent = tile

            if isOccupied then
                if cellData.faceTexture then
                    local faceImg = Instance.new("ImageLabel")
                    faceImg.Size = UDim2.new(1, 0, 1, 0)
                    faceImg.Position = UDim2.new(0, 0, 0, 0)
                    faceImg.BackgroundTransparency = 1
                    faceImg.ScaleType = Enum.ScaleType.Fit
                    faceImg.Image = cellData.faceTexture
                    faceImg.ImageColor3 = cellData.faceColor
                    faceImg.Parent = tile
                end

                if cellData.gifted then
                    local star = Instance.new("TextLabel")
                    star.Size = UDim2.new(0, 14, 0, 14)
                    star.Position = UDim2.new(0, 1, 0, 0)
                    star.BackgroundTransparency = 1
                    star.Text = "★"
                    star.TextColor3 = Color3.fromRGB(255, 235, 40)
                    star.TextStrokeTransparency = 0
                    star.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                    star.Font = Enum.Font.GothamBold
                    star.TextSize = 12
                    star.TextXAlignment = Enum.TextXAlignment.Left
                    star.TextYAlignment = Enum.TextYAlignment.Top
                    star.Parent = tile
                end

                local lvlLabel = Instance.new("TextLabel")
                lvlLabel.Size = UDim2.new(0, 22, 0, 12)
                lvlLabel.Position = UDim2.new(0, 2, 1, -12)
                lvlLabel.BackgroundTransparency = 1
                lvlLabel.Text = tostring(cellData.level or 1)
                lvlLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                lvlLabel.TextStrokeTransparency = 0
                lvlLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                lvlLabel.Font = Enum.Font.GothamBold
                lvlLabel.TextSize = 11
                lvlLabel.TextXAlignment = Enum.TextXAlignment.Left
                lvlLabel.TextYAlignment = Enum.TextYAlignment.Bottom
                lvlLabel.Parent = tile
            end

            local selLabel = Instance.new("TextLabel")
            selLabel.Name = "SelLabel"
            selLabel.Size = UDim2.new(0, 20, 0, 12)
            selLabel.Position = UDim2.new(1, -21, 1, -12)
            selLabel.BackgroundTransparency = 1
            selLabel.Text = selectedHiveSlots[slotKey] and "Sel" or ""
            selLabel.TextColor3 = Color3.fromRGB(80, 255, 120)
            selLabel.TextStrokeTransparency = 0
            selLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            selLabel.Font = Enum.Font.GothamBold
            selLabel.TextSize = 10
            selLabel.TextXAlignment = Enum.TextXAlignment.Right
            selLabel.TextYAlignment = Enum.TextYAlignment.Bottom
            selLabel.Parent = tile

            tile.MouseButton1Click:Connect(function()
                selectedHiveSlots[slotKey] = not selectedHiveSlots[slotKey]
                stroke.Color = selectedHiveSlots[slotKey] and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(25, 28, 36)
                stroke.Thickness = selectedHiveSlots[slotKey] and 2 or 1
                selLabel.Text = selectedHiveSlots[slotKey] and "Sel" or ""
                refreshBuilderStatus()
            end)

            slotTiles[slotKey] = tile
        end
    end
    refreshBuilderStatus()
end



local function toggleSlotPicker()
    pickerFrame.Visible = not pickerFrame.Visible
    if pickerFrame.Visible then
        refreshHiveGrid()
    end
end

HiveTab:Button({
    Title = "Pick slots",
    Icon = "crosshair",
    Callback = function()
        toggleSlotPicker()
    end
})
end -- /hive-slot picker

HiveTab:Button({
    Title = "Copy my hive",
    Icon = "camera",
    Callback = function()
        local cells = readHiveGrid(true)
        exactSlotTargets = {}
        local counts = {}
        for r = 1, 10 do
            for c = 1, 5 do
                local cd = cells[r] and cells[r][c]
                if cd and cd.beeType and cd.beeType ~= "Empty" then
                    local k = string.format("C%d,%d", c, r)
                    local gStatus = cd.gifted and "Gifted" or "Normal"
                    exactSlotTargets[k] = { beeId = cd.beeType, gifted = gStatus }
                    local tag = cd.beeType .. "|" .. gStatus
                    counts[tag] = (counts[tag] or 0) + 1
                end
            end
        end
        compositionTargets = {}
        for tag, cnt in pairs(counts) do
            local bId, g = tag:match("^(.-)|(.*)$")
            table.insert(compositionTargets, { beeId = bId, gifted = g, count = cnt })
        end
        hasUserConfiguredTargets = true
        refreshHiveGrid()
        refreshBuilderStatus()
        refreshQuotaText()
        IvyisUI:Notify({ Title = "Done", Content = "Hive copied into the layout", Duration = 2 })
        if refreshSsaStatus then pcall(refreshSsaStatus) end
    end
})

local SSA_CANONICAL_BEE_IDS = {
    [1] = "Basic Bee",
    [2] = "Bomber Bee",
    [3] = "Brave Bee",
    [4] = "Bumble Bee",
    [5] = "Cool Bee",
    [6] = "Hasty Bee",
    [7] = "Looker Bee",
    [8] = "Rad Bee",
    [9] = "Rascal Bee",
    [10] = "Stubborn Bee",
    [11] = "Bubble Bee",
    [12] = "Bucko Bee",
    [13] = "Commander Bee",
    [14] = "Demo Bee",
    [15] = "Exhausted Bee",
    [16] = "Fire Bee",
    [17] = "Frosty Bee",
    [18] = "Honey Bee",
    [19] = "Rage Bee",
    [20] = "Riley Bee",
    [21] = "Shocked Bee",
    [22] = "Baby Bee",
    [23] = "Carpenter Bee",
    [24] = "Demon Bee",
    [25] = "Diamond Bee",
    [26] = "Lion Bee",
    [27] = "Music Bee",
    [28] = "Ninja Bee",
    [29] = "Shy Bee",
    [30] = "Buoyant Bee",
    [31] = "Fuzzy Bee",
    [32] = "Precise Bee",
    [33] = "Spicy Bee",
    [34] = "Tadpole Bee",
    [35] = "Vector Bee",
    [36] = "Bear Bee",
    [37] = "Cobalt Bee",
    [38] = "Crimson Bee",
    [39] = "Digital Bee",
    [40] = "Festive Bee",
    [41] = "Gummy Bee",
    [42] = "Photon Bee",
    [43] = "Puppy Bee",
    [44] = "Tabby Bee",
    [45] = "Vicious Bee",
    [46] = "Windy Bee"
}

local function ssaExtractBeeName(str)
    if not str or type(str) ~= "string" then return nil end
    local lower = str:lower()
    local clean = lower:gsub("[^%a%s]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if not clean or #clean < 3 then return nil end

    for _, bee in ipairs(ALL_BEES) do
        local bLower = bee.name:lower()
        local bShort = bLower:gsub("%s*bee$", "")

        if clean == bLower or clean == bShort or clean == bee.id:lower() then
            return bee.name
        end
        if clean:find("%f[%a]" .. bLower .. "%f[%A]") or clean:find("%f[%a]" .. bShort .. "%f[%A]") then
            return bee.name
        end
    end
    return nil
end

local function ssaBuildBeeIdMap()
    local idMap = {}
    for id, name in pairs(SSA_CANONICAL_BEE_IDS) do
        idMap[id] = name
    end

    pcall(function()
        local etMod = RS:FindFirstChild("EggTypes")
        if etMod and etMod:IsA("ModuleScript") then
            local et = require(etMod)
            if type(et) == "table" and type(et.GetOrderedNames) == "function" then
                local ord = et:GetOrderedNames() or et.GetOrderedNames()
                if type(ord) == "table" then
                    for idx, name in pairs(ord) do
                        local nIdx = tonumber(idx)
                        if nIdx and nIdx >= 112 and nIdx <= 249 and (nIdx - 112) % 3 == 0 then
                            local beeId = math.floor((nIdx - 112) / 3) + 1
                            local bName = ssaExtractBeeName(tostring(name))
                            if bName and beeId >= 1 and beeId <= 46 then
                                idMap[beeId] = bName
                            end
                        end
                    end
                end
            end
        end
    end)

    return idMap
end

local function ssaGetGiftedDiscoveredMap()
    local discovered = {}
    local data = getStatData()
    local idMap = ssaBuildBeeIdMap()

    -- Resolve one entry: bee id, index, name ("Basic Bee"/"Basic Bee - Gifted")
    -- or a small table that wraps the value.
    local function idToName(key)
        local n = tonumber(key)
        if not n then return nil end
        if idMap[n] then return idMap[n] end
        -- Some caches key gifted types by egg index (112, 115, ...), not bee id.
        if n >= 112 and n <= 249 and (n - 112) % 3 == 0 then
            return idMap[math.floor((n - 112) / 3) + 1]
        end
        return nil
    end

    local function addValue(val, depth)
        if val == nil or (depth or 0) > 2 then return end
        local matchedName = nil
        if type(val) == "number" then
            matchedName = idToName(val)
        elseif type(val) == "string" then
            local nId = tonumber(val)
            matchedName = (nId and idToName(nId)) or ssaExtractBeeName(val)
        elseif type(val) == "table" then
            addValue(val.Name or val.Bee or val.Type or val.Id or val.id, (depth or 0) + 1)
            return
        end
        if matchedName then discovered[matchedName] = true end
    end

    -- Gifted discovery is a map (name -> true/count), an array of names/ids, or
    -- a nested list. Accept every shape; unknown keys simply resolve to nil.
    local function addContainer(tbl, depth)
        if type(tbl) ~= "table" or depth > 2 then return end
        for k, v in pairs(tbl) do
            local truthy = type(v) ~= "table" and v ~= nil and v ~= false and v ~= 0 and tostring(v) ~= ""
            if type(k) == "string" then
                local name = ssaExtractBeeName(k)
                if name and truthy then discovered[name] = true end
            elseif type(k) == "number" and (v == true or v == 1) then
                -- Boolean map keyed by bee id / egg index: {[3] = true}.
                local name = idToName(k)
                if name then discovered[name] = true end
            end
            if type(v) == "table" then
                local wrapped = v.Name or v.Bee or v.Type or v.Id or v.id
                if wrapped ~= nil then
                    addValue(wrapped, 0)
                else
                    -- Nested list/map (e.g. {Gifted = {...}}). Gift tables are
                    -- small, so one more level is safe and catches shape changes.
                    addContainer(v, depth + 1)
                end
            else
                local vk = type(k) == "string" and k:lower() or ""
                local looksBeeKey = vk:find("bee", 1, true) or vk == "id" or vk == "type"
                    or vk == "name" or vk == "value" or vk == "index" or vk == "item"
                if type(k) == "number" or looksBeeKey then
                    addValue(v, 0)
                elseif type(v) == "string" then
                    -- Plain list value under an unknown key: only accept strings
                    -- that actually name a bee, so metadata like Amount = "5"
                    -- is not mistaken for bee id 5.
                    local name = ssaExtractBeeName(v)
                    if name then discovered[name] = true end
                end
            end
        end
    end

    if type(data) == "table" then
        -- The cache key is not stable across updates, so scan any table-valued
        -- key containing "gift" (and one nested level for Discoveries.Gifted).
        for k, v in pairs(data) do
            if type(v) == "table" then
                if tostring(k):lower():find("gift", 1, true) then
                    addContainer(v, 0)
                else
                    for k2, v2 in pairs(v) do
                        if type(v2) == "table" and tostring(k2):lower():find("gift", 1, true) then
                            addContainer(v2, 0)
                        end
                    end
                end
            end
        end
    end

    -- A gifted bee currently in the hive is always a discovered gifted type.
    -- This also keeps SSA progress correct when the stat key is unknown.
    local grid = (readHiveGrid and readHiveGrid()) or {}
    for r = 1, 10 do
        for c = 1, 5 do
            local cell = grid[r] and grid[r][c]
            if cell and cell.gifted and cell.beeType then
                local bee = beeMapById[cell.beeType]
                local name = bee and bee.name or ssaExtractBeeName(cell.beeType)
                if name then discovered[name] = true end
            end
        end
    end

    return discovered
end

HiveTab:Section({ Title = "Gifted bees (SSA)" })

local ssaStatusLabel = HiveTab:Paragraph({
    Title = "SSA Progress",
    Desc = "Calculating..."
})

local ssaGiftedLabel = HiveTab:Paragraph({
    Title = "Gifted bees owned (0)",
    Desc = "Calculating..."
})

local ssaMissingLabel = HiveTab:Paragraph({
    Title = "Gifted bees needed for SSA (0)",
    Desc = "Calculating..."
})

function refreshSsaStatus()
    local discOk, disc = pcall(ssaGetGiftedDiscoveredMap)
    if not discOk or type(disc) ~= "table" then disc = {} end
    local giftedCount, missingCount = 0, 0
    local rarityDiscovered = { Common = 0, Rare = 0, Epic = 0, Legendary = 0, Mythic = 0, Event = 0 }
    local missingByRarity = { Event = {}, Mythic = {}, Legendary = {}, Epic = {}, Rare = {}, Common = {} }
    local discoveredByRarity = { Event = {}, Mythic = {}, Legendary = {}, Epic = {}, Rare = {}, Common = {} }

    for _, bee in ipairs(ALL_BEES) do
        if disc[bee.name] then
            giftedCount = giftedCount + 1
            if rarityDiscovered[bee.rarity] ~= nil then
                rarityDiscovered[bee.rarity] = rarityDiscovered[bee.rarity] + 1
            end
            table.insert(discoveredByRarity[bee.rarity], bee.name)
        else
            missingCount = missingCount + 1
            table.insert(missingByRarity[bee.rarity], bee.name)
        end
    end

    local ssaPct = math.clamp(math.floor((giftedCount / 40) * 100), 0, 100)
    local tierStr = "No Star Amulet"
    local neededStr = string.format("Need %d for Bronze", math.max(0, 5 - giftedCount))
    if giftedCount >= 40 then
        tierStr = "Supreme Star Amulet (SSA)"
        neededStr = "SSA Unlocked!"
    elseif giftedCount >= 35 then
        tierStr = "Diamond Star Amulet (DSA)"
        neededStr = string.format("Need %d more for Supreme (40)", 40 - giftedCount)
    elseif giftedCount >= 25 then
        tierStr = "Gold Star Amulet (GSA)"
        neededStr = string.format("Need %d more for Diamond (35)", 35 - giftedCount)
    elseif giftedCount >= 15 then
        tierStr = "Silver Star Amulet"
        neededStr = string.format("Need %d more for Gold (25)", 25 - giftedCount)
    elseif giftedCount >= 5 then
        tierStr = "Bronze Star Amulet"
        neededStr = string.format("Need %d more for Silver (15)", 15 - giftedCount)
    end

    local rarityDesc = string.format("Common: %d/1 | Rare: %d/9 | Epic: %d/11 | Leg: %d/8 | Mythic: %d/6 | Event: %d/11",
        rarityDiscovered.Common, rarityDiscovered.Rare, rarityDiscovered.Epic,
        rarityDiscovered.Legendary, rarityDiscovered.Mythic, rarityDiscovered.Event)

    if ssaStatusLabel then
        ssaStatusLabel:SetTitle(string.format("SSA: %d / 40 (%d%%) - %s", math.min(giftedCount, 40), ssaPct, tierStr))
        ssaStatusLabel:SetDesc(string.format("%s\n%s", neededStr, rarityDesc))
    end

    if ssaGiftedLabel then
        ssaGiftedLabel:SetTitle(string.format("Gifted bees owned (%d)", giftedCount))
        local lines = {}
        for _, rar in ipairs({ "Event", "Mythic", "Legendary", "Epic", "Rare", "Common" }) do
            local list = discoveredByRarity[rar]
            if list and #list > 0 then
                table.insert(lines, string.format("• %s (%d): %s", rar, #list, table.concat(list, ", ")))
            end
        end
        if #lines == 0 then
            ssaGiftedLabel:SetDesc("None discovered yet.")
        else
            ssaGiftedLabel:SetDesc(table.concat(lines, "\n"))
        end
    end

    if ssaMissingLabel then
        ssaMissingLabel:SetTitle(string.format("Gifted bees needed for SSA (%d)", missingCount))
        local lines = {}
        for _, rar in ipairs({ "Event", "Mythic", "Legendary", "Epic", "Rare", "Common" }) do
            local list = missingByRarity[rar]
            if list and #list > 0 then
                table.insert(lines, string.format("• %s (%d): %s", rar, #list, table.concat(list, ", ")))
            end
        end
        if #lines == 0 then
            ssaMissingLabel:SetDesc("✓ Complete! All 46 gifted bee types discovered.")
        else
            ssaMissingLabel:SetDesc(table.concat(lines, "\n"))
        end
    end
end

local function copySsaMissingReport()
    local discOk, disc = pcall(ssaGetGiftedDiscoveredMap)
    if not discOk or type(disc) ~= "table" then disc = {} end
    local missingByRarity = {}
    local totalMissing = 0
    local totalGifted = 0

    for _, bee in ipairs(ALL_BEES) do
        if disc[bee.name] then
            totalGifted = totalGifted + 1
        else
            totalMissing = totalMissing + 1
            if not missingByRarity[bee.rarity] then
                missingByRarity[bee.rarity] = {}
            end
            table.insert(missingByRarity[bee.rarity], bee.name)
        end
    end

    local lines = {}
    table.insert(lines, string.format("=== SSA Missing Gifted Bees (%d/40 SSA Progress | %d Missing) ===", math.min(totalGifted, 40), totalMissing))
    local order = { "Event", "Mythic", "Legendary", "Epic", "Rare", "Common" }
    for _, rar in ipairs(order) do
        local list = missingByRarity[rar]
        if list and #list > 0 then
            table.insert(lines, string.format("[%s - %d]: %s", rar, #list, table.concat(list, ", ")))
        end
    end
    local text = table.concat(lines, "\n")
    local ok = copyToClipboard(text)
    if ok then
        IvyisUI:Notify({ Title = "Copied", Content = "Missing gifted bees copied to clipboard!", Duration = 3 })
    else
        print(text)
        IvyisUI:Notify({ Title = "Printed to Console", Content = "Printed missing bees to console (F9)!", Duration = 3 })
    end
end

HiveTab:Button({
    Title = "Refresh SSA status",
    Icon = "refresh-cw",
    Callback = function()
        refreshSsaStatus()
        IvyisUI:Notify({ Title = "SSA Status", Content = "Gifted bees status refreshed!", Duration = 2 })
    end
})

HiveTab:Button({
    Title = "Copy needed bees to clipboard",
    Icon = "clipboard-copy",
    Callback = function()
        copySsaMissingReport()
    end
})

HiveTab:Section({ Title = "Bees I want" })

local quotaLabel = HiveTab:Paragraph({
    Title = "Wanted list",
    Desc = "nothing added yet"
})

function refreshQuotaText()
    local list = {}
    local total = 0
    for _, item in ipairs(compositionTargets) do
        local b = beeMapById[item.beeId]
        local name = b and b.name or item.beeId
        local gStr = (item.gifted == "Gifted" and "[Gifted]" or (item.gifted == "Normal" and "[Normal]" or "[Any]"))
        table.insert(list, string.format("%dx %s %s", item.count, name, gStr))
        total = total + item.count
    end
    if #list == 0 then
        quotaLabel:SetDesc("No quota target bees configured | Total quota: 0")
    else
        quotaLabel:SetDesc(string.format("Quota: %s (Total: %d)", table.concat(list, " | "), tonumber(total) or 0))
    end
    refreshBuilderStatus()
end

HiveTab:Dropdown({
    Title = "Bee",
    Values = beeDropdownOptions,
    Value = "Buoyant Bee",
    Callback = function(val)
        selectedBeeId = beeMapByOption[val] or "BuoyantBee"
    end
})

HiveTab:Dropdown({
    Title = "Gifted",
    Values = { "Any", "Gifted", "Normal" },
    Value = "Any",
    Callback = function(val)
        selectedTargetGifted = val or "Any"
    end
})

HiveTab:Slider({
    Title = "How many",
    Step = 1,
    Value = { Min = 1, Max = 50, Default = 5 },
    Callback = function(v)
        selectedTargetQty = v
    end
})

HiveTab:Button({
    Title = "Add to list",
    Icon = "plus-circle",
    Callback = function()
        local found = false
        for _, item in ipairs(compositionTargets) do
            if item.beeId == selectedBeeId and item.gifted == selectedTargetGifted then
                item.count = selectedTargetQty
                found = true
                break
            end
        end
        if not found then
            table.insert(compositionTargets, {
                beeId = selectedBeeId,
                gifted = selectedTargetGifted,
                count = selectedTargetQty
            })
        end
        hasUserConfiguredTargets = true
        refreshQuotaText()
        local b = beeMapById[selectedBeeId]
        IvyisUI:Notify({
            Title = "Added",
            Content = string.format("%dx %s (%s)", selectedTargetQty, b and b.name or selectedBeeId, selectedTargetGifted),
            Duration = 2
        })
    end
})

HiveTab:Button({
    Title = "Remove this bee",
    Icon = "minus-circle",
    Callback = function()
        for i = #compositionTargets, 1, -1 do
            local item = compositionTargets[i]
            if item.beeId == selectedBeeId and item.gifted == selectedTargetGifted then
                table.remove(compositionTargets, i)
            end
        end
        refreshQuotaText()
    end
})

HiveTab:Button({
    Title = "Clear list",
    Icon = "trash-2",
    Callback = function()
        compositionTargets = {}
        refreshQuotaText()
        IvyisUI:Notify({ Title = "Cleared", Content = "List is empty now", Duration = 2 })
    end
})

HiveTab:Section({ Title = "Saved layouts" })

HiveTab:Input({
    Title = "Name",
    Value = "MyHiveBuild",
    Placeholder = "Enter config name...",
    Callback = function(v)
        if v and v ~= "" then configNameInput = v end
    end
})

local savedConfigsDropdown = nil

HiveTab:Button({
    Title = "Save",
    Icon = "save",
    Callback = function()
        ensureHiveConfigDir()
        local name = configNameInput or "MyHiveBuild"
        local raw = serializeHiveConfig(name)
        if raw and writefile then
            local path = HIVE_CONFIGS_DIR .. "/" .. name .. ".json"
            local ok, err = pcall(writefile, path, raw)
            if ok then
                IvyisUI:Notify({ Title = "Saved", Content = "Saved to " .. path, Duration = 3 })
            else
                IvyisUI:Notify({ Title = "Could not save", Content = tostring(err), Duration = 3 })
            end
        end
    end
})

savedConfigsDropdown = HiveTab:Dropdown({
    Title = "Saved layout",
    Values = listHiveConfigs(),
    Value = listHiveConfigs()[1] or "None",
    Callback = function(val)
        selectedSavedConfig = val
    end
})

HiveTab:Button({
    Title = "Load",
    Icon = "folder-open",
    Callback = function()
        if not selectedSavedConfig or selectedSavedConfig == "None" then
            IvyisUI:Notify({ Title = "Load", Content = "Pick a layout first", Duration = 2 })
            return
        end
        local path = HIVE_CONFIGS_DIR .. "/" .. selectedSavedConfig .. ".json"
        if isfile and isfile(path) and readfile then
            local ok, content = pcall(readfile, path)
            if ok and content then
                local sOk, decoded = pcall(function() return HttpService:JSONDecode(content) end)
                if sOk and decoded then
                    applyLoadedHiveConfig(decoded)
                    refreshQuotaText()
                    refreshHiveGrid()
                    refreshBuilderStatus()
                    IvyisUI:Notify({ Title = "Loaded", Content = selectedSavedConfig, Duration = 3 })
                    return
                end
            end
        end
        IvyisUI:Notify({ Title = "Could not load", Content = "Can't read " .. tostring(selectedSavedConfig), Duration = 3 })
    end
})

HiveTab:Button({
    Title = "Refresh",
    Icon = "rotate-cw",
    Callback = function()
        local list = listHiveConfigs()
        if savedConfigsDropdown and savedConfigsDropdown.SetValues then
            pcall(function() savedConfigsDropdown:SetValues(list) end)
        end
        IvyisUI:Notify({ Title = "Layouts", Content = string.format("%d saved", #list), Duration = 2 })
    end
})

HiveTab:Button({
    Title = "Copy as text",
    Icon = "clipboard-copy",
    Callback = function()
        local raw = serializeHiveConfig(configNameInput)
        if raw then
            local copied = copyToClipboard(raw)
            if copied then
                IvyisUI:Notify({ Title = "Copied", Content = "Layout text is in your clipboard", Duration = 3 })
            else
                print("[HiveBuilder Export]\n" .. raw)
                IvyisUI:Notify({ Title = "Printed", Content = "Check the console (F9)", Duration = 4 })
            end
        end
    end
})

HiveTab:Input({
    Title = "Paste layout text",
    Value = "",
    Placeholder = "Paste config JSON string here...",
    Callback = function(v)
        importJsonInput = v
    end
})

HiveTab:Button({
    Title = "Use pasted layout",
    Icon = "download",
    Callback = function()
        local text = importJsonInput
        if not text or text == "" then
            IvyisUI:Notify({ Title = "Nothing pasted", Content = "Paste the layout text first", Duration = 3 })
            return
        end
        local ok, decoded = pcall(function() return HttpService:JSONDecode(text) end)
        if ok and decoded and type(decoded) == "table" then
            applyLoadedHiveConfig(decoded)
            refreshQuotaText()
            refreshHiveGrid()
            refreshBuilderStatus()
            IvyisUI:Notify({ Title = "Imported", Content = tostring(decoded.name or "layout"), Duration = 3 })
        else
            IvyisUI:Notify({ Title = "Bad text", Content = "That is not a valid layout", Duration = 3 })
        end
    end
})

HiveTab:Section({ Title = "Royal jelly" })

autoSyncToggle = HiveTab:Toggle({
    Title = "Copy roll settings from game",
    Value = autoSyncSettings,
    Callback = function(v) autoSyncSettings = v end
})

HiveTab:Toggle({
    Title = "Buy royal jelly when low",
    Value = true,
    Callback = function(v) autoBuyRJ = v end
})

HiveTab:Slider({
    Title = "Buy this many at a time",
    Step = 1000,
    Value = { Min = 1000, Max = 50000, Default = 10000 },
    Callback = function(v) buyRJAmount = v end
})

HiveTab:Section({ Title = "Rolling" })

local rollStatusLabel = HiveTab:Paragraph({
    Title = "Roll status",
    Desc = "not running"
})

rollToggle = HiveTab:Toggle({
    Title = "Auto roll",
    Value = false,
    Callback = function(v)
        if v == rollRunning then return end
        rollRunning = v
        if rollRunning then
            if feedRunning then stopAutoFeed(true) end
            pauseAtlas(true)
            IvyisUI:Notify({ Title = "Auto Roll", Content = "On (" .. currentBuildMode .. ")", Duration = 2 })
        else
            stopAutoRoll()
            IvyisUI:Notify({ Title = "Auto Roll", Content = "Off", Duration = 2 })
        end
    end
})


ProgTab:Section({ Title = "Right now" })

local progTargetLabel = ProgTab:Paragraph({
    Title = "Next item: ...",
    Desc = "reading your Atlas route..."
})

ProgTab:Section({ Title = "Gear" })

ProgTab:Button({
    Title = "Open gear list",
    Callback = function()
        Progression.openGearList()
    end
})

ProgTab:Section({ Title = "Options" })

ProgTab:Toggle({
    Title = "Follow the route and switch fields",
    Value = true,
    Callback = function(v)
        Progression.setAutoProgression(v)
        Progression.setAutoFieldSwitch(v)
    end
})

ProgTab:Toggle({
    Title = "Kill Vicious Bee when I need stingers",
    Value = true,
    Callback = function(v)
        Progression.setAutoHuntVicious(v)
    end
})

ProgTab:Toggle({
    Title = "Show info text on screen",
    Value = true,
    Callback = function(v)
        Progression.setHudVisible(v)
    end
})

ProgTab:Button({
    Title = "Scan route again",
    Callback = function()
        Progression.rescanProgression()
        IvyisUI:Notify({
            Title = "Auto Progression",
            Content = "Scanned again",
            Duration = 3
        })
    end
})

Progression.setTargetLabel(progTargetLabel)

-- Gear list lives in a normal IvyisUI tab now, instead of a separate raw GUI.
-- This keeps the same theme, font, sidebar and scrolling as the main tabs.
GearTab:Section({ Title = "Collection" })
local gearProgressLabel = GearTab:Paragraph({
    Title = "Gear 0/0",
    Desc = "reading route..."
})
GearTab:Toggle({
    Title = "Hide owned gear",
    Value = false,
    Callback = function(v)
        Progression.setGearHideOwned(v)
    end
})
Progression.mountGearList(GearTab, gearProgressLabel)
pcall(function()
    if IvyisUI.OnThemeChange then
        IvyisUI:OnThemeChange(function()
            Progression.applyGearTheme()
        end)
    end
end)
Progression.setOpenGearList(function()
    Window:Open()
    GearTab:Select()
end)
pcall(function()
    FeedTab:Select()
end)

SettingsTab:Section({ Title = "General" })

SettingsTab:Toggle({
    Title = "Pause Atlas while I work",
    Value = true,
    Callback = function(v) autoPauseAtlas = v end
})

local antiAfkConn = nil
local function setAntiAfk(enabled)
    if antiAfkConn then
        antiAfkConn:Disconnect()
        antiAfkConn = nil
    end
    if enabled then
        antiAfkConn = player.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end
end
setAntiAfk(true)

SettingsTab:Toggle({
    Title = "Anti-AFK",
    Value = true,
    Callback = function(v)
        setAntiAfk(v)
    end
})

local stripConn = nil
local savedPartProperties = {}
local savedMeshTextures = {}
local savedParticles = {}
local savedLighting = nil

local function isProtected(inst)
    if not inst then return true end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and inst:IsDescendantOf(p.Character) then
            return true
        end
    end
    local fz = workspace:FindFirstChild("FlowerZones")
    if fz and (inst == fz or inst:IsDescendantOf(fz)) then return true end
    local fl = workspace:FindFirstChild("Flowers")
    if fl and (inst == fl or inst:IsDescendantOf(fl)) then return true end
    local hc = workspace:FindFirstChild("Honeycombs")
    if hc and (inst == hc or inst:IsDescendantOf(hc)) then return true end
    return false
end

local function stripInstance(inst)
    if isProtected(inst) then return end
    if inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("SurfaceAppearance") then
        pcall(function() inst:Destroy() end)
    elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Smoke") or inst:IsA("Fire") or inst:IsA("Sparkles") then
        if savedParticles[inst] == nil then
            savedParticles[inst] = inst.Enabled
        end
        inst.Enabled = false
    elseif inst:IsA("SpecialMesh") then
        if inst.TextureId ~= "" then
            if savedMeshTextures[inst] == nil then
                savedMeshTextures[inst] = inst.TextureId
            end
            inst.TextureId = ""
        end
    elseif inst:IsA("MeshPart") then
        if inst.TextureID ~= "" then
            if savedMeshTextures[inst] == nil then
                savedMeshTextures[inst] = inst.TextureID
            end
            pcall(function() inst.TextureID = "" end)
        end
        if not savedPartProperties[inst] then
            savedPartProperties[inst] = { Material = inst.Material, Reflectance = inst.Reflectance, CastShadow = inst.CastShadow, Transparency = inst.Transparency }
        end
        inst.Material = Enum.Material.SmoothPlastic
        inst.Reflectance = 0
        inst.CastShadow = false
        inst.Transparency = 1
    elseif inst:IsA("BasePart") then
        if not savedPartProperties[inst] then
            savedPartProperties[inst] = { Material = inst.Material, Reflectance = inst.Reflectance, CastShadow = inst.CastShadow, Transparency = inst.Transparency }
        end
        inst.Material = Enum.Material.SmoothPlastic
        inst.Reflectance = 0
        inst.CastShadow = false
        inst.Transparency = 1
    end
end

local function setMapRemoval(enabled)
    if stripConn then
        stripConn:Disconnect()
        stripConn = nil
    end
    local Lighting = game:GetService("Lighting")
    local fz = workspace:FindFirstChild("FlowerZones")
    local fl = workspace:FindFirstChild("Flowers")
    local hc = workspace:FindFirstChild("Honeycombs")
    if enabled then
        if not savedLighting then
            savedLighting = { GlobalShadows = Lighting.GlobalShadows, FogEnd = Lighting.FogEnd }
        end
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        pcall(function()
            if sethiddenproperty then
                sethiddenproperty(workspace.Terrain, "Decoration", false)
            end
        end)
        for _, desc in ipairs(Lighting:GetChildren()) do
            if desc:IsA("PostEffect") or desc:IsA("Atmosphere") then
                if savedParticles[desc] == nil then
                    savedParticles[desc] = desc.Enabled
                end
                desc.Enabled = false
            end
        end
        for _, child in ipairs(workspace:GetChildren()) do
            if child ~= fz and child ~= fl and child ~= hc and not Players:GetPlayerFromCharacter(child) then
                for _, desc in ipairs(child:GetDescendants()) do
                    stripInstance(desc)
                end
                stripInstance(child)
            end
        end
        stripConn = workspace.DescendantAdded:Connect(function(desc)
            task.wait()
            stripInstance(desc)
        end)
    else
        if savedLighting then
            Lighting.GlobalShadows = savedLighting.GlobalShadows
            Lighting.FogEnd = savedLighting.FogEnd
            savedLighting = nil
        end
        pcall(function()
            if sethiddenproperty then
                sethiddenproperty(workspace.Terrain, "Decoration", true)
            end
        end)
        for desc, state in pairs(savedParticles) do
            if desc and desc.Parent then
                pcall(function() desc.Enabled = state end)
            end
        end
        table.clear(savedParticles)
        for mesh, tex in pairs(savedMeshTextures) do
            if mesh and mesh.Parent then
                pcall(function()
                    if mesh:IsA("MeshPart") then
                        mesh.TextureID = tex
                    else
                        mesh.TextureId = tex
                    end
                end)
            end
        end
        table.clear(savedMeshTextures)
        for part, props in pairs(savedPartProperties) do
            if part and part.Parent then
                pcall(function()
                    part.Material = props.Material
                    part.Reflectance = props.Reflectance
                    part.CastShadow = props.CastShadow
                    part.Transparency = props.Transparency
                end)
            end
        end
        table.clear(savedPartProperties)
    end
end

SettingsTab:Toggle({
    Title = "Remove map textures",
    Desc = "less lag; fields and players stay",
    Value = false,
    Callback = function(v)
        setMapRemoval(v)
    end
})

SettingsTab:Dropdown({
    Title = "UI Theme",
    Values = IvyisUI:GetThemeNames(),
    Value = IvyisUI:GetCurrentTheme(),
    Callback = function(theme)
        pcall(function() IvyisUI:SetTheme(theme) end)
    end
})

SettingsTab:Dropdown({
    Title = "UI size",
    Desc = "bigger in-game menu (useful on phones)",
    Values = IVYIS_UI.CHOICES,
    Value = IVYIS_UI.choice,
    Callback = function(choice)
        pcall(IVYIS_UI.apply, choice)
    end
})

SettingsTab:Section({ Title = "Discord webhook" })

SettingsTab:Input({
    Title = "Webhook link",
    Value = "",
    Placeholder = "https://discord.com/api/webhooks/...",
    Callback = function(v)
        v = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if v == "" or v:match("^https://[%w%.]*discord%.com/api/webhooks/") or v:match("^https://[%w%.]*discordapp%.com/api/webhooks/") then
            Progression.setWebhookUrl(v)
        else
            Progression.setWebhookUrl("")
            IvyisUI:Notify({ Title = "Webhook", Content = "That doesn't look like a Discord webhook link", Duration = 3 })
        end
    end
})

SettingsTab:Slider({
    Title = "Send status every (minutes)",
    Step = 1,
    Value = { Min = 1, Max = 60, Default = 10 },
    Callback = function(v) Progression.setWebhookInterval(v * 60) end
})

SettingsTab:Toggle({
    Title = "Tell me when I buy gear",
    Value = true,
    Callback = function(v) Progression.setNotifyBuy(v) end
})

SettingsTab:Toggle({
    Title = "Tell me when config changes",
    Value = true,
    Callback = function(v) Progression.setNotifyConfig(v) end
})

SettingsTab:Button({
    Title = "Send test message",
    Icon = "send",
    Callback = function()
        task.spawn(function()
            local ok, why = Progression.sendTestWebhook()
            IvyisUI:Notify({
                Title = "Webhook",
                Content = ok and "Test message sent" or ("Not sent: " .. tostring(why)),
                Duration = 3,
            })
        end)
    end
})

SettingsTab:Section({ Title = "Discord remote" })

getgenv().IvyisDiscordStatusLabel = SettingsTab:Paragraph({
    Title = "Discord bridge",
    Desc = "not connected"
})

getgenv().IvyisDiscordCodeInput = ""

-- Show the current panel address even if getgenv still holds the old default
-- from a previous execution (the bridge migrates it on start).
local initialBridgeUrl = tostring((getgenv and getgenv().IvyisBridgeUrl) or "")
if
    initialBridgeUrl == ""
    or initialBridgeUrl == "http://78.154.103.24:14873"
    or initialBridgeUrl == "http://78.154.103.8:16573"
then
    initialBridgeUrl = "http://78.154.103.12:16477"
end

SettingsTab:Input({
    Title = "Bridge URL",
    Value = initialBridgeUrl,
    Placeholder = "https://your-tunnel.trycloudflare.com",
    Callback = function(v)
        local bridge = getgenv().IvyisDiscordBridge
        if bridge then
            bridge.setUrl(v)
        end
    end
})

SettingsTab:Input({
    Title = "Discord link code",
    Value = "",
    Placeholder = "IVY-XXXXXXXX",
    Callback = function(v)
        getgenv().IvyisDiscordCodeInput = tostring(v or "")
    end
})

SettingsTab:Button({
    Title = "Connect Discord",
    Icon = "link",
    Callback = function()
        local bridge = getgenv().IvyisDiscordBridge
        if not bridge then
            IvyisUI:Notify({ Title = "Discord", Content = "Bridge is still loading", Duration = 3 })
            return
        end
        task.spawn(function()
            local ok, why = bridge.connect(getgenv().IvyisDiscordCodeInput)
            IvyisUI:Notify({
                Title = "Discord",
                Content = ok and "Linked" or ("Failed: " .. tostring(why or "unknown")),
                Duration = 4,
            })
        end)
    end
})

SettingsTab:Button({
    Title = "Disconnect Discord",
    Icon = "unlink",
    Callback = function()
        local bridge = getgenv().IvyisDiscordBridge
        if not bridge then return end
        bridge.disconnect()
        IvyisUI:Notify({ Title = "Discord", Content = "Disconnected", Duration = 3 })
    end
})

SettingsTab:Section({ Title = "Executor" })

local detectedExecutorName = tostring(select(1, detectExecutor()) or "Unknown")

getgenv().IvyisExecutorLabel = SettingsTab:Paragraph({
    Title = "Detected executor",
    Desc = detectedExecutorName
})

-- Mobile forks often keep the base executor's globals (Arceus X is built on
-- Fluxus), so detection can still be wrong on a new build. This field lets the
-- player correct the name that appears in Discord /status without editing code.
SettingsTab:Input({
    Title = "Executor name override",
    Value = tostring((getgenv and getgenv().IvyisExecutorNameOverride) or ""),
    Placeholder = "Auto: " .. detectedExecutorName,
    Callback = function(v)
        local text = tostring(v or "")
        text = text:gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then
            if getgenv then getgenv().IvyisExecutorNameOverride = nil end
            EXECUTOR_NAME = nil
            EXECUTOR_VERSION = nil
            detectExecutor()
        else
            if getgenv then getgenv().IvyisExecutorNameOverride = text end
            EXECUTOR_NAME = cleanExecutorText(text, 48)
            EXECUTOR_VERSION = nil
        end
        if getgenv then
            getgenv().IvyisExecutorName = EXECUTOR_NAME
            getgenv().IvyisExecutorVersion = EXECUTOR_VERSION
        end
        local label = getgenv and getgenv().IvyisExecutorLabel
        if label then
            pcall(function() label:SetDesc(tostring(getExecutorLabel(true))) end)
        end
        local bridge = getgenv and getgenv().IvyisDiscordBridge
        if bridge and bridge.sendState then
            task.spawn(function() pcall(bridge.sendState) end)
        end
        IvyisUI:Notify({
            Title = "Executor",
            Content = "Name set to " .. tostring(EXECUTOR_NAME or "Unknown"),
            Duration = 3,
        })
    end
})

task.spawn(function()
    while scriptAlive do
        if feedRunning then
            local ok, err = pcall(function()
                local data = getStatData()
                local myHive = getMyHive()
                if not myHive then return end

                local cellsGrid = readHiveGrid()
                local candidates = {}
                local alreadyAtTarget = 0
                local totalBees = 0

                local tgtCum = getCumulativeBond(targetLevel)
                local bft = (data and data.Modifiers and data.Modifiers["Bond From Treats"]) or 0
                local effBond = TREAT_BOND * (1 + bft / 100)

                for r = 1, 10 do
                    for c = 1, 5 do
                        local cd = cellsGrid[r] and cellsGrid[r][c]
                        if cd and cd.beeType ~= "Empty" then
                            totalBees = totalBees + 1
                            local bData = data and data.Honeycomb and data.Honeycomb["x"..c] and data.Honeycomb["x"..c]["y"..r]
                            local currentBond = (bData and tonumber(bData.Bond)) or 0
                            local currentLvl = (bData and tonumber(bData.Lvl)) or cd.level or 1

                            if currentLvl >= targetLevel then
                                alreadyAtTarget = alreadyAtTarget + 1
                            else
                                local remBond = math.max(0, tgtCum - currentBond)
                                table.insert(candidates, {
                                    col = c,
                                    row = r,
                                    level = currentLvl,
                                    bond = currentBond,
                                    remBond = remBond,
                                    treatsNeeded = math.ceil(remBond / effBond)
                                })
                            end
                        end
                    end
                end

                local effectiveTarget = math.min(targetBeeCount, totalBees)
                local needToUpgrade = math.max(0, effectiveTarget - alreadyAtTarget)
                local totalHoney = calcHoneyNeeded(targetLevel, targetBeeCount)

                if needToUpgrade <= 0 or #candidates == 0 then
                    treatStatusLabel:SetDesc(string.format("All %d bees reached Lvl %d! Done.", effectiveTarget, targetLevel))
                    stopAutoFeed()
                    IvyisUI:Notify({
                        Title = "Feeding done",
                        Content = string.format("%d bees reached level %d", effectiveTarget, targetLevel),
                        Duration = 5
                    })
                    return
                end

                pauseAtlas(true)

                treatStatusLabel:SetDesc(string.format("At Target Lvl %d: %d/%d (%d left) | Honey Needed: %s", tonumber(targetLevel) or 0, tonumber(alreadyAtTarget) or 0, tonumber(effectiveTarget) or 0, tonumber(needToUpgrade) or 0, formatNum(totalHoney)))

                table.sort(candidates, function(a, b)
                    if a.level == b.level then
                        return a.bond > b.bond
                    end
                    return a.level > b.level
                end)

                local ownedTreats = getTreats(data)
                local honey = getHoney(data)
                local firstCand = candidates[1]
                local treatsNeeded = firstCand.treatsNeeded

                if ownedTreats == 0 and honey < TREAT_COST then
                    stopAutoFeed()
                    treatStatusLabel:SetDesc(string.format("Out of Honey! Needs %s | Stopped.", formatNum(totalHoney)))
                    IvyisUI:Notify({
                        Title = "Feeding stopped",
                        Content = "Not enough honey for treats",
                        Duration = 5
                    })
                    return
                end

                if autoBuyEnabled and ownedTreats < treatsNeeded and honey >= TREAT_COST then
                    local toBuy = math.min(treatsNeeded - ownedTreats, math.floor(honey / TREAT_COST))
                    if toBuy > 0 then
                        treatStatusLabel:SetDesc("Moving to Treat Shop...")
                        if getgenv and getgenv().IvyisAtlasHold then getgenv().IvyisAtlasHold.release() end
                        local shopPos = getTreatShopPos()
                        if goToPos(shopPos, 20) then
                            task.wait(0.5)
                            if not feedRunning or not scriptAlive then return end
                            treatStatusLabel:SetDesc(string.format("Buying %s Treats...", formatNum(toBuy)))
                            buyTreats(toBuy)
                            task.wait(0.5)
                            if not feedRunning or not scriptAlive then return end
                            data = getStatData()
                            ownedTreats = getTreats(data)
                        end
                    end
                end

                if returnHiveEnabled then
                    if not goToHive() then
                        treatStatusLabel:SetDesc("Moving to Hive platform...")
                        return
                    end
                    task.wait(0.5)
                    if not feedRunning or not scriptAlive then return end
                end

                data = getStatData()
                ownedTreats = getTreats(data)
                if ownedTreats > 0 then
                    local toFeed = math.min(treatsNeeded, ownedTreats)
                    if toFeed > 0 then
                        if getgenv and getgenv().IvyisAtlasHold then getgenv().IvyisAtlasHold.start() end
                        treatStatusLabel:SetDesc(string.format("Feeding %s Treats to C%d,R%d (Lvl %d)...", formatNum(toFeed), tonumber(firstCand.col) or 0, tonumber(firstCand.row) or 0, tonumber(firstCand.level) or 0))
                        feedBee(firstCand.col, firstCand.row, toFeed)
                        task.wait(0.5)
                        if not feedRunning or not scriptAlive then return end
                    end
                elseif not autoBuyEnabled and ownedTreats == 0 then
                    stopAutoFeed()
                    treatStatusLabel:SetDesc("Out of Treats (Auto-Buy is OFF) | Stopped.")
                    IvyisUI:Notify({
                        Title = "Feeding stopped",
                        Content = "No treats left and auto buy is off",
                        Duration = 5
                    })
                    return
                end
            end)
            if not ok then warn("[AutoTreat] Error: " .. tostring(err)) end
        end
        task.wait(2)
    end
end)

local rollFailCount = 0

-- Event bees cannot come from Royal Jelly. Bee Swarm gives each event bee its
-- own permanent jelly (TabbyBeeJelly, PuppyBeeJelly, ...). The jelly always
-- produces the normal event bee, never a gifted one. These helpers live on the
-- existing RouteSteps table so they do not add top-level locals.
function RouteSteps.getEventJellyInfo(beeId)
    local bee = beeId and beeMapById and beeMapById[beeId]
    if not bee or bee.rarity ~= "Event" then return nil end
    return {
        beeId = bee.id,
        name = bee.name,
        item = bee.id .. "Jelly",
        display = bee.name .. " Jelly",
    }
end

function RouteSteps.getEventJellyCount(beeId, data)
    local info = RouteSteps.getEventJellyInfo(beeId)
    if not info then return nil end
    data = data or RouteSteps.getStatData()
    local n = RouteSteps.countItem(info.display, data)
    return tonumber(n) or 0
end

-- true  -> this target can be rolled/hatched now
-- false -> skip it and try the next target (missing jelly / gifted event)
function RouteSteps.eventTargetReady(target, data)
    local info = RouteSteps.getEventJellyInfo(target and target.beeId)
    if not info then return true, nil, nil end
    if tostring(target.gifted or "Any"):lower() == "gifted" then
        return false, info, "gifted"
    end
    local count = RouteSteps.getEventJellyCount(target.beeId, data)
    if (count or 0) <= 0 then
        return false, info, "missing"
    end
    return true, info, nil
end

function RouteSteps.skippedEventText(skipped)
    local names = {}
    for name in pairs(skipped or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    return table.concat(names, ", ")
end

function RouteSteps.hiveContainsBee(grid, beeId)
    if not grid or not beeId then return false end
    for r = 1, 10 do
        for c = 1, 5 do
            local cell = grid[r] and grid[r][c]
            if cell and cell.beeType == beeId then return true end
        end
    end
    return false
end

local function cellMatches(cellData, target)
    if not cellData or not target or cellData.beeType == "Empty" then return false end
    local typeOk = (cellData.beeType == target.beeId) or (cellData.beeType:gsub("%s+",""):lower() == target.beeId:gsub("%s+",""):lower())
    if not typeOk then return false end
    if target.gifted == "Gifted" then
        return cellData.gifted == true
    elseif target.gifted == "Normal" then
        return cellData.gifted == false
    end
    return true
end

-- Royal Jelly is consumed by a successful roll. Poll the stat cache instead of
-- sleeping a full second, so the next roll can start as soon as the server has
-- processed the previous one.
function RouteSteps.waitForRoyalJellyDrop(beforeRJ, timeout)
    local deadline = os.clock() + (timeout or 1.2)
    while os.clock() < deadline do
        task.wait(0.08)
        if not rollRunning or not scriptAlive then return nil end
        local data = getStatData()
        local rj = getRoyalJellies(data)
        if beforeRJ > 0 and rj < beforeRJ then
            return data, rj
        end
    end
    return nil
end

-- Event jellies are permanent (their count does not drop), so wait for the
-- target cell to become the event bee instead of watching the inventory.
function RouteSteps.waitForEventHatch(col, row, target, timeout)
    local deadline = os.clock() + (timeout or 1.2)
    while os.clock() < deadline do
        task.wait(0.1)
        if not rollRunning or not scriptAlive then return nil end
        local grid = readHiveGrid(true)
        local cell = grid[row] and grid[row][col]
        if cell and cellMatches(cell, target) then
            return cell
        end
    end
    return nil
end

task.spawn(function()
    while scriptAlive do
        if rollRunning then
            local ok, err = pcall(function()
                pauseAtlas(true)

                local cellsGrid = readHiveGrid()
                local nextTargetSlot = nil
                local currentTargetObj = nil

                if currentBuildMode == "Exact" then
                    local totalExact = 0
                    local incompleteExact = {}

                    for r = 1, 10 do
                        for c = 1, 5 do
                            local key = string.format("C%d,%d", c, r)
                            local target = exactSlotTargets[key]
                            if target then
                                totalExact = totalExact + 1
                                local cd = cellsGrid[r] and cellsGrid[r][c]
                                if not cellMatches(cd, target) then
                                    table.insert(incompleteExact, { col = c, row = r, key = key, target = target, cd = cd })
                                end
                            end
                        end
                    end

                    if totalExact == 0 then
                        rollStatusLabel:SetDesc("No exact slot targets configured! Open grid to assign slots.")
                        stopAutoRoll()
                        return
                    end

                    if #incompleteExact == 0 then
                        rollStatusLabel:SetDesc(string.format("All %d exact slots completed 100%! Stopped.", totalExact))
                        stopAutoRoll()
                        IvyisUI:Notify({ Title = "Hive done", Content = "Every slot matches", Duration = 5 })
                        return
                    end

                    local jellyData = getStatData()
                    local availableExact = {}
                    local skippedExact = {}
                    for _, item in ipairs(incompleteExact) do
                        local ready, info, reason = RouteSteps.eventTargetReady(item.target, jellyData)
                        if ready and info and RouteSteps.hiveContainsBee(cellsGrid, item.target.beeId) then
                            ready = false
                            reason = "already"
                        end
                        if ready then
                            availableExact[#availableExact + 1] = item
                        elseif info then
                            skippedExact[info.name] = reason or true
                        end
                    end

                    if #availableExact == 0 then
                        local names = RouteSteps.skippedEventText(skippedExact)
                        rollStatusLabel:SetDesc("Event bee skipped (missing jelly / gifted / already in hive): " .. (names ~= "" and names or "event target") .. ".")
                        stopAutoRoll()
                        return
                    end

                    nextTargetSlot = availableExact[1]
                    currentTargetObj = nextTargetSlot.target

                    local skipNote = ""
                    if next(skippedExact) ~= nil then
                        skipNote = string.format(" | Skipped: %s", RouteSteps.skippedEventText(skippedExact))
                    end
                    rollStatusLabel:SetDesc(string.format("Exact Mode: Slot %s needs %s (%s) | Remaining: %d/%d%s",
                        tostring(nextTargetSlot.key), tostring(getShortBeeName(currentTargetObj.beeId)), tostring(currentTargetObj.gifted), tonumber(#availableExact) or 0, tonumber(totalExact) or 0, skipNote))

                else
                    if #compositionTargets == 0 then
                        rollStatusLabel:SetDesc("No quota targets configured! Add target bees first.")
                        stopAutoRoll()
                        return
                    end

                    local remainingNeeded = {}
                    local totalNeeded = 0
                    for _, item in ipairs(compositionTargets) do
                        local tag = item.beeId .. "|" .. (item.gifted or "Any")
                        remainingNeeded[tag] = item.count
                        totalNeeded = totalNeeded + item.count
                    end

                    local protectedSlots = {}
                    for r = 1, 10 do
                        for c = 1, 5 do
                            local cd = cellsGrid[r] and cellsGrid[r][c]
                            if cd and cd.beeType ~= "Empty" then
                                local slotKey = string.format("C%d,%d", c, r)
                                for tag, rem in pairs(remainingNeeded) do
                                    if rem > 0 then
                                        local bId, g = tag:match("^(.-)|(.*)$")
                                        if cellMatches(cd, { beeId = bId, gifted = g }) then
                                            remainingNeeded[tag] = rem - 1
                                            protectedSlots[slotKey] = true
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end

                    local jellyData = getStatData()
                    local sumRemaining = 0
                    local usableRemaining = 0
                    local skippedTargets = {}
                    local primaryNeededTarget = nil
                    local rarityRank = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5, Event = 6 }
                    local primaryRank = -1
                    for tag, rem in pairs(remainingNeeded) do
                        sumRemaining = sumRemaining + rem
                        if rem > 0 then
                            local bId, g = tag:match("^(.-)|(.*)$")
                            local ready, info, reason = RouteSteps.eventTargetReady({ beeId = bId, gifted = g }, jellyData)
                            if ready and info and RouteSteps.hiveContainsBee(cellsGrid, bId) then
                                ready = false
                                reason = "already"
                            end
                            if ready then
                                usableRemaining = usableRemaining + rem
                                local bee = beeMapById and beeMapById[bId]
                                local rank = bee and (rarityRank[bee.rarity] or 0) or 0
                                if not primaryNeededTarget or rank > primaryRank then
                                    primaryNeededTarget = { beeId = bId, gifted = g }
                                    primaryRank = rank
                                end
                            elseif info then
                                skippedTargets[info.name] = reason or true
                            end
                        end
                    end

                    if sumRemaining <= 0 then
                        rollStatusLabel:SetDesc("All composition quota targets satisfied! Stopped.")
                        stopAutoRoll()
                        IvyisUI:Notify({ Title = "Hive done", Content = "Got every bee on the list", Duration = 5 })
                        return
                    elseif usableRemaining <= 0 then
                        local names = RouteSteps.skippedEventText(skippedTargets)
                        rollStatusLabel:SetDesc("Event bee skipped (missing jelly / gifted / already in hive): " .. (names ~= "" and names or "event target") .. ".")
                        stopAutoRoll()
                        return
                    end

                    local candidates = {}
                    for r = 1, 10 do
                        for c = 1, 5 do
                            local key = string.format("C%d,%d", c, r)
                            if selectedHiveSlots[key] and not protectedSlots[key] then
                                local cd = cellsGrid[r] and cellsGrid[r][c]
                                table.insert(candidates, { col = c, row = r, key = key, cd = cd })
                            end
                        end
                    end

                    if #candidates == 0 then
                        rollStatusLabel:SetDesc("No eligible slots selected to roll! Select slots in grid.")
                        stopAutoRoll()
                        return
                    end

                    nextTargetSlot = candidates[1]
                    currentTargetObj = primaryNeededTarget

                    local skipNote = ""
                    if next(skippedTargets) ~= nil then
                        skipNote = string.format(" | Skipped: %s", RouteSteps.skippedEventText(skippedTargets))
                    end
                    rollStatusLabel:SetDesc(string.format("Comp Mode: Rolling %s | Next needed: %s (%s) | Left: %d/%d%s",
                        tostring(nextTargetSlot.key), tostring(getShortBeeName(currentTargetObj.beeId)), tostring(currentTargetObj.gifted), tonumber(usableRemaining) or 0, tonumber(totalNeeded) or 0, skipNote))
                end

                if not nextTargetSlot then
                    stopAutoRoll()
                    return
                end

                local eventInfo = RouteSteps.getEventJellyInfo(currentTargetObj and currentTargetObj.beeId)
                local isEventTarget = eventInfo ~= nil

                local keepGifted = forcedRollFlags.untilGifted == true
                -- A target that must be gifted always needs the game's own stop
                -- condition, even with both web toggles off. Without it one
                -- remote call burns the whole 25k Royal Jelly batch.
                local needGifted = not isEventTarget and currentTargetObj ~= nil
                    and tostring(currentTargetObj.gifted or ""):lower() == "gifted"
                -- Auto switch: the Until gifted switch follows the slot being
                -- rolled. A plan that mixes one gifted bee with one plain bee
                -- turns the switch on for the gifted slot, then back off for the
                -- plain one, instead of keeping one stop condition for the whole
                -- plan. The player's own "Until gifted" toggle still wins: with it
                -- on the switch never drops.
                local wantGifted = (keepGifted or needGifted) and not isEventTarget
                local wantMythic = false
                local wantLegendary = false
                if currentTargetObj then
                    if captureRollSettings then pcall(captureRollSettings) end
                    if autoSyncSettings then
                        -- Sync on: the script may turn on Until mythic/legendary so a
                        -- 25k Royal Jelly batch stops as soon as that rarity appears.
                        local b = beeMapById[currentTargetObj.beeId]
                        local r = b and b.rarity or "Mythic"
                        if r == "Mythic" then
                            wantMythic = true
                        elseif r == "Legendary" then
                            wantLegendary = true
                            wantMythic = true
                        end
                        setGameSetting("RollToMythic", wantMythic)
                        setGameSetting("RollToLegendary", wantLegendary)
                    end
                    -- Select bee page "stop on mythic": the game's own switch has
                    -- to stay on for that whole roll, otherwise the next batch
                    -- rolls past the mythic before the bridge can look at the
                    -- slot. It must hold even with sync settings off - the player
                    -- asked for it from the web - and the restore hands their own
                    -- value back afterwards.
                    if not isEventTarget and webRollRunning and forcedRollFlags.stopOnMythic == true then
                        wantMythic = true
                        webMythicSwitchOwned = true
                        setGameSetting("RollToMythic", true)
                    end
                    -- The gifted switch is per-bee, so it follows the target even
                    -- when "sync settings" is off (sync only governs the rarity
                    -- switches: Until mythic / Until legendary).
                    setUntilGifted(wantGifted)
                end

                local data = getStatData()
                local currentRJ = getRoyalJellies(data)

                if isEventTarget then
                    local jellyCount = RouteSteps.getEventJellyCount(currentTargetObj.beeId, data)
                    if (jellyCount or 0) <= 0 then
                        rollStatusLabel:SetDesc("No " .. tostring(eventInfo.display) .. " - skipping event target.")
                        task.wait(0.4)
                        return
                    end
                else
                    if currentRJ < minRJThreshold and autoBuyRJ then
                        rollStatusLabel:SetDesc("Moving to Royal Jelly Shop...")
                        if getgenv and getgenv().IvyisAtlasHold then getgenv().IvyisAtlasHold.release() end
                        local rjShopPos = getRJShopPos()
                        if goToPos(rjShopPos, 20) then
                            task.wait(0.5)
                            if not rollRunning or not scriptAlive then return end
                            rollStatusLabel:SetDesc(string.format("Buying %s Royal Jellies...", formatNum(buyRJAmount)))
                            buyRoyalJellies(buyRJAmount)
                            task.wait(0.5)
                            if not rollRunning or not scriptAlive then return end
                            data = getStatData()
                            currentRJ = getRoyalJellies(data)
                        else
                            return
                        end
                    end

                    if currentRJ <= 0 then
                        rollStatusLabel:SetDesc("Out of Royal Jellies! Stopped.")
                        stopAutoRoll()
                        return
                    end
                end

                if not goToHive() then
                    rollStatusLabel:SetDesc("Moving to Hive platform...")
                    return
                end
                task.wait(0.5)
                if not rollRunning or not scriptAlive then return end

                if getgenv and getgenv().IvyisAtlasHold then getgenv().IvyisAtlasHold.start() end

                local beforeRollRJ = currentRJ
                -- The 25k batch only pays off while one of the game's own stop
                -- switches is on: the game then stops early the moment the bee
                -- turns gifted / mythic / legendary. With no stop switch the whole
                -- batch is spent on a single random result, so roll one jelly at a
                -- time and let the plan check decide after each one. Event jellies
                -- are always one use and do not consume Royal Jelly.
                local hasStop = wantGifted or wantMythic or wantLegendary
                local rollBatch = isEventTarget and 1
                    or (hasStop and math.min(currentRJ, 25000) or math.min(currentRJ, 1))
                local rollType = isEventTarget and eventInfo.item or "RoyalJelly"
                local okR = rollBee(nextTargetSlot.col, nextTargetSlot.row, rollBatch, rollType)
                if not okR then
                    rollFailCount = rollFailCount + 1
                    if rollFailCount >= 5 then
                        rollStatusLabel:SetDesc("Roll remote failed 5 times! Stopped.")
                        stopAutoRoll()
                        return
                    end
                    rollStatusLabel:SetDesc(string.format("Roll remote failed (%d/5)! Retrying...", rollFailCount))
                    task.wait(0.35)
                    return
                end

                local newCell = nil
                if isEventTarget then
                    -- The event jelly stays in the inventory, so the cell itself
                    -- is the only reliable "hatch finished" signal.
                    newCell = RouteSteps.waitForEventHatch(nextTargetSlot.col, nextTargetSlot.row, currentTargetObj, 1.4)
                    if not newCell then
                        rollFailCount = rollFailCount + 1
                        if rollFailCount >= 5 then
                            rollStatusLabel:SetDesc("Event jelly did not hatch after 5 tries! Stopped.")
                            stopAutoRoll()
                            return
                        end
                        rollStatusLabel:SetDesc(string.format("Event jelly not applied (%d/5)! Retrying...", rollFailCount))
                        task.wait(0.35)
                        return
                    end
                else
                    -- RemoteEvent does not report a rejected roll. If Royal Jelly
                    -- was not consumed, count it as a failed attempt.
                    local afterRollData, afterRollRJ = RouteSteps.waitForRoyalJellyDrop(beforeRollRJ, 1.4)
                    if not afterRollData then
                        rollFailCount = rollFailCount + 1
                        if rollFailCount >= 5 then
                            rollStatusLabel:SetDesc("Game rejected 5 rolls (RJ not used)! Stopped.")
                            stopAutoRoll()
                            return
                        end
                        rollStatusLabel:SetDesc(string.format("Game did not use RJ (%d/5)! Retrying...", rollFailCount))
                        task.wait(0.35)
                        return
                    end
                    task.wait(0.2)
                    local refreshedGrid = readHiveGrid(true)
                    newCell = refreshedGrid[nextTargetSlot.row] and refreshedGrid[nextTargetSlot.row][nextTargetSlot.col]
                end
                rollFailCount = 0

                local newType = newCell and newCell.beeType or "Unknown"

                if currentBuildMode == "Exact" then
                    if cellMatches(newCell, currentTargetObj) then
                        -- Some executors resume this coroutine after InvokeServer
                        -- without Plugin capability. Notifications/grid rebuilds
                        -- are cosmetic, so never let them abort a good hatch.
                        pcall(function()
                            IvyisUI:Notify({
                                Title = "Slot done",
                                Content = string.format("slot %s: %s (%s)", tostring(nextTargetSlot.key), tostring(newType), (newCell and newCell.gifted) and "Gifted" or "Normal"),
                                Duration = 4
                            })
                        end)
                        pcall(refreshHiveGrid)
                    end
                else
                    for _, item in ipairs(compositionTargets) do
                        if cellMatches(newCell, item) then
                            pcall(function()
                                IvyisUI:Notify({
                                    Title = "Got one",
                                    Content = string.format("%s (%s) in slot %s", tostring(newType), (newCell and newCell.gifted) and "Gifted" or "Normal", tostring(nextTargetSlot.key)),
                                    Duration = 4
                                })
                            end)
                            pcall(refreshHiveGrid)
                            break
                        end
                    end
                end
            end)
            if not ok then warn("[AutoRoll] Error: " .. tostring(err)) end
        end
        task.wait(0.15)
    end
end)


task.spawn(function()
    task.wait(2)
    while scriptAlive do
        Progression.progressionTick()
        task.wait(8)
    end
end)

refreshHiveGrid()
pcall(function()
    Progression.refreshProgressionUI()
end)

pcall(function()
    if refreshSsaStatus then refreshSsaStatus() end
end)

getgenv().IvyisDiscordBridge = (function()
    local DEFAULT_BRIDGE_URL = "http://78.154.103.12:16477"
    -- Panel hosts rotate. Saved sessions keep the URL they were linked with, so
    -- old defaults are rewritten on load instead of leaving the client pointed
    -- at a host that no longer exists.
    local LEGACY_BRIDGE_URLS = {
        ["http://78.154.103.24:14873"] = true,
        ["http://78.154.103.8:16573"] = true,
    }
    local bridgeUrl = tostring((getgenv and getgenv().IvyisBridgeUrl) or DEFAULT_BRIDGE_URL)
    local sessionToken = nil
    local linkedDiscordId = nil
    local statusSink = nil
    local started = false
    local generation = 0
    local remoteRollJob = nil
    local connectedOnce = false
    local lastRollFlagsSignature = ""
    -- False until the stored flags reached this client, so a fresh reload never
    -- overwrites the web setting with the game's pre-sync value.
    local rollFlagsSynced = false

    -- Keep the local mirror and (when idle) the game's own switches in sync with
    -- the three toggles on /selectbee and /buildhive. force=true is used for
    -- explicit commands so the in-game UI updates even if nothing changed.
    local function applyRollFlags(flags, force)
        if type(flags) ~= "table" then return forcedRollFlags end
        local wasGifted = forcedRollFlags.untilGifted == true
        forcedRollFlags.untilGifted = flags.untilGifted == true
        forcedRollFlags.syncSettings = flags.syncSettings ~= false
        forcedRollFlags.stopOnMythic = flags.stopOnMythic == true
        -- The keep list is a list of mythic bee ids; anything else the web (or a
        -- hand edited payload) sends is dropped here so the roll loop can trust
        -- the map without checking rarities again.
        forcedRollFlags.keepMythics = {}
        if type(flags.keepMythics) == "table" then
            for _, value in ipairs(flags.keepMythics) do
                local item = beeMapById and beeMapById[tostring(value or "")]
                if item and item.rarity == "Mythic" then
                    forcedRollFlags.keepMythics[item.id] = true
                end
            end
        end
        forcedRollFlags.rev = tonumber(flags.rev) or 0

        -- The sync switch is the same setting as the script's own "Copy roll
        -- settings from game" toggle, so the web and the Lua UI always agree.
        autoSyncSettings = forcedRollFlags.syncSettings
        pcall(function()
            if autoSyncToggle then autoSyncToggle:Set(autoSyncSettings) end
        end)
        rollFlagsSynced = true

        local keepIds = {}
        for id in pairs(forcedRollFlags.keepMythics) do
            table.insert(keepIds, id)
        end
        table.sort(keepIds)
        local signature = string.format(
            "%s|%s|%s|%s",
            tostring(forcedRollFlags.untilGifted),
            tostring(forcedRollFlags.syncSettings),
            tostring(forcedRollFlags.stopOnMythic),
            table.concat(keepIds, ",")
        )
        if not force and signature == lastRollFlagsSignature then
            return forcedRollFlags
        end
        lastRollFlagsSignature = signature

        -- While a roll runs the batch loop writes these switches before every
        -- roll; touching them here as well would fight with it.
        local rolling = rollRunning == true or (remoteRollJob and remoteRollJob.active == true)
        if rolling then return forcedRollFlags end

        -- Idle: mirror the web's "Until gifted" into the game, on or off. Until
        -- mythic/legendary are only ever touched while a roll is running.
        if forcedRollFlags.untilGifted then
            if captureRollSettings then pcall(captureRollSettings) end
            setUntilGifted(true)
        elseif wasGifted then
            setUntilGifted(false)
        end
        -- The switch the web just set is the new baseline. Drop any snapshot
        -- taken before it, otherwise a much later roll would restore stale
        -- values (and could silently re-enable a switch the player turned off).
        originalRollSettings = nil
        return forcedRollFlags
    end
    local executorRequest = (getgenv and getgenv().request)
        or (type(_G) == "table" and _G.request)
        or (syn and syn.request)
        or (http and http.request)
        or http_request
        or (fluxus and fluxus.request)

    local function trim(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function normalizeBridgeUrl(value)
        local url = trim(value):gsub("/+$", "")
        if LEGACY_BRIDGE_URLS[url] then return DEFAULT_BRIDGE_URL end
        return url
    end

    local function sessionPath()
        local safe = tostring(player.Name or "player"):gsub("[^%w_%-]", "_")
        return "AutoFeedBSS/discord_session_" .. safe .. ".json"
    end

    local function setStatus(text)
        if statusSink then pcall(statusSink, text) end
        if getgenv then pcall(function() getgenv().IvyisDiscordStatus = text end) end
    end

    local function ensureDir()
        if ensureHiveConfigDir then pcall(ensureHiveConfigDir) end
    end

    local function saveSession()
        if not writefile then return end
        ensureDir()
        local ok, raw = pcall(function()
            return HttpService:JSONEncode({
                url = bridgeUrl,
                token = sessionToken,
                discordId = linkedDiscordId,
            })
        end)
        if ok and raw then pcall(writefile, sessionPath(), raw) end
    end

    local function loadSession()
        if not (isfile and readfile) then return end
        local path = sessionPath()
        if not isfile(path) then return end
        local ok, content = pcall(readfile, path)
        if not ok or not content then return end
        local decodedOk, decoded = pcall(function() return HttpService:JSONDecode(content) end)
        if not decodedOk or type(decoded) ~= "table" then return end
        local urlChanged = false
        if type(decoded.url) == "string" and decoded.url ~= "" then
            local rawUrl = trim(decoded.url):gsub("/+$", "")
            local restored = normalizeBridgeUrl(rawUrl)
            urlChanged = restored ~= rawUrl
            bridgeUrl = restored
        end
        if type(decoded.token) == "string" and decoded.token ~= "" then sessionToken = decoded.token end
        if decoded.discordId then linkedDiscordId = tostring(decoded.discordId) end
        if urlChanged then saveSession() end
    end

    local function clearSession()
        sessionToken = nil
        linkedDiscordId = nil
        if writefile and isfile and isfile(sessionPath()) then
            pcall(writefile, sessionPath(), "{}")
        end
    end

    local function request(method, path, body, token)
        local httpRequest = getHttpRequest and getHttpRequest() or nil
        httpRequest = httpRequest
            or (syn and syn.request)
            or (http and http.request)
            or http_request
            or (fluxus and fluxus.request)
            or executorRequest
        if type(httpRequest) ~= "function" then return nil, "executor_has_no_http" end
        local base = trim(bridgeUrl):gsub("/+$", "")
        if base == "" then return nil, "bridge_url_missing" end

        local headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
        }
        if token and token ~= "" then headers.Authorization = "Bearer " .. token end

        local opts = {
            Url = base .. path,
            Method = method,
            Headers = headers,
        }
        if body ~= nil then
            local okEnc, encoded = pcall(function() return HttpService:JSONEncode(body) end)
            if not okEnc or not encoded then return nil, "json_encode_failed" end
            opts.Body = encoded
        end

        -- Executor request functions can hang forever on a half-open socket
        -- (phone sleeps, Wi-Fi drops). Run the call in its own thread so one
        -- stuck request cannot freeze the heartbeat/poll loops and make
        -- /status report a false "offline".
        local timeout = 20
        if method == "GET" and path:find("/poll", 1, true) then
            timeout = 30 -- the server long-polls for up to 25s
        end
        local finished = false
        local ok, res = false, nil
        task.spawn(function()
            ok, res = pcall(httpRequest, opts)
            finished = true
        end)
        local waited = 0
        while not finished and waited < timeout do
            task.wait(0.1)
            waited = waited + 0.1
        end
        if not finished then return nil, "timeout" end
        if not ok then return nil, tostring(res) end
        local code = type(res) == "table" and (tonumber(res.StatusCode) or 0) or 0
        if code == 401 or code == 403 then return nil, "unauthorized", code end
        if code == 204 then return {}, nil, code end

        local raw = type(res) == "table" and res.Body or nil
        if type(raw) ~= "string" or raw == "" then
            if code >= 400 then return nil, "http_" .. tostring(code), code end
            return {}, nil, code
        end
        local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
        if not decodeOk or type(decoded) ~= "table" then return nil, "bad_json", code end
        if code >= 400 then return nil, tostring(decoded.error or ("http_" .. tostring(code))), code end
        return decoded, nil, code
    end

    local function buildState()
        local dataOk, data = pcall(function()
            return getStatData and getStatData() or nil
        end)
        if not dataOk then data = nil end
        local hive = {}
        local beesInHive = 0
        local gridOk, grid = pcall(function()
            return (readHiveGrid and readHiveGrid()) or {}
        end)
        if not gridOk or type(grid) ~= "table" then grid = {} end
        for r = 1, 10 do
            for c = 1, 5 do
                local cell = grid[r] and grid[r][c]
                local beeId = tostring((cell and cell.beeType) or "Empty")
                if beeId ~= "Empty" then beesInHive = beesInHive + 1 end
                hive[#hive + 1] = {
                    slot = string.format("C%d,%d", c, r),
                    beeId = beeId,
                    gifted = (cell and cell.gifted == true) or false,
                }
            end
        end

        local gifted = {}
        if ssaGetGiftedDiscoveredMap then
            local mapOk, map = pcall(ssaGetGiftedDiscoveredMap)
            if mapOk and type(map) == "table" then
                for name, value in pairs(map) do
                    if value then gifted[tostring(name)] = true end
                end
            end
        end

        local rollText = ""
        if rollStatusLabel then
            pcall(function() rollText = tostring(rollStatusLabel.Desc or "") end)
        end
        local executorName = "Unknown"
        if detectExecutor then
            pcall(function() executorName = select(1, detectExecutor()) or "Unknown" end)
        end
        local platform = "Unknown"
        if getPlatformLabel then pcall(function() platform = getPlatformLabel() end) end

        return {
            schema = 1,
            player = tostring(player.Name),
            placeId = tostring(game.PlaceId),
            jobId = tostring(game.JobId),
            executor = executorName,
            platform = platform,
            beeCount = beesInHive,
            honey = (getHoney and getHoney(data)) or 0,
            rj = (getRoyalJellies and getRoyalJellies(data)) or 0,
            gifted = gifted,
            hive = hive,
            roll = {
                running = rollRunning == true,
                mode = tostring(currentBuildMode or "Composition"),
                status = rollText,
            },
            rollSettings = readRollSettings(),
            flagsSynced = rollFlagsSynced,
            flagsRev = forcedRollFlags.rev,
            remote = remoteRollJob and {
                active = remoteRollJob.active == true,
                target = remoteRollJob.target,
                targetName = remoteRollJob.targetName,
                reason = remoteRollJob.reason,
                detail = remoteRollJob.detail,
                startedAt = remoteRollJob.startedAt,
                finishedAt = remoteRollJob.finishedAt,
                slots = remoteRollJob.eligible,
                slot = remoteRollJob.slot,
            } or nil,
            updatedAt = os.time(),
        }
    end

    local stateFailures = 0
    local unauthorizedHits = 0

    local function sendState()
        if not sessionToken or sessionToken == "" then return false end
        -- A broken hive/stat reader used to throw here, the heartbeat swallowed
        -- the error, and the bridge went "offline" forever while the game was
        -- still running. Report it instead of failing silently.
        local builtOk, state = pcall(buildState)
        if not builtOk or type(state) ~= "table" then
            stateFailures = stateFailures + 1
            if stateFailures == 3 then
                warn("[DiscordBridge] buildState failed: " .. tostring(state))
                setStatus("State error: " .. tostring(state))
            end
            return false
        end
        local res, err = request("POST", "/api/v1/state", state, sessionToken)
        if not res then
            if err == "unauthorized" then
                -- A single 401 can be a transient server hiccup (restart, busy
                -- DB). Only wipe the saved session once it repeats.
                unauthorizedHits = unauthorizedHits + 1
                if unauthorizedHits >= 2 then
                    connectedOnce = false
                    clearSession()
                    setStatus("Discord session expired. Run /link again.")
                else
                    setStatus("Session rejected, retrying...")
                end
                return false
            end
            stateFailures = stateFailures + 1
            if stateFailures == 3 then
                warn("[DiscordBridge] state failed: " .. tostring(err or "network"))
                setStatus("Bridge unreachable: " .. tostring(err or "network"))
            end
            return false
        end
        if stateFailures > 0 or not connectedOnce then
            setStatus("Connected")
        end
        stateFailures = 0
        unauthorizedHits = 0
        connectedOnce = true
        if type(res.rollFlags) == "table" then
            pcall(applyRollFlags, res.rollFlags, false)
        end
        return true
    end

    local function copyTable(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for key, item in pairs(value) do
            out[key] = copyTable(item)
        end
        return out
    end

    local function discoveredIdSet()
        local set = {}
        if not ssaGetGiftedDiscoveredMap then return set end
        local mapOk, map = pcall(ssaGetGiftedDiscoveredMap)
        if not mapOk or type(map) ~= "table" then return set end
        for _, bee in ipairs(ALL_BEES or {}) do
            if map[bee.name] then set[bee.id] = true end
        end
        return set
    end

    local function finishRemoteRoll(reason, detail)
        local job = remoteRollJob
        if not job or not job.active then return end
        job.active = false
        webRollRunning = false
        job.reason = tostring(reason or "finished")
        job.detail = detail and tostring(detail) or ""
        job.finishedAt = os.time()

        pcall(stopAutoRoll)
        local snapshot = job.snapshot
        if snapshot then
            currentBuildMode = snapshot.mode or "Composition"
            compositionTargets = snapshot.composition or {}
            exactSlotTargets = snapshot.exact or {}
            selectedHiveSlots = snapshot.selected or {}
            autoSyncSettings = snapshot.autoSync ~= false
            autoBuyRJ = snapshot.autoBuy ~= false
            buyRJAmount = tonumber(snapshot.buyAmount) or buyRJAmount
        end
        -- The web owns the sync permission, so a job snapshot must not revive a
        -- value the player already changed there.
        autoSyncSettings = forcedRollFlags.syncSettings ~= false
        pcall(function() if autoSyncToggle then autoSyncToggle:Set(autoSyncSettings) end end)
        hasUserConfiguredTargets = (#compositionTargets > 0) or (next(exactSlotTargets) ~= nil)

        if refreshQuotaText then pcall(refreshQuotaText) end
        if refreshHiveGrid then pcall(refreshHiveGrid) end
        if refreshBuilderStatus then pcall(refreshBuilderStatus) end
        if refreshSsaStatus then pcall(refreshSsaStatus) end

        local label = string.format("Discord roll finished: %s", tostring(reason or "done"))
        if detail and detail ~= "" then label = label .. " (" .. tostring(detail) .. ")" end
        if rollStatusLabel then
            pcall(function() rollStatusLabel:SetDesc(label) end)
        end
        pcall(function()
            IvyisUI:Notify({
                Title = "Discord roll",
                Content = label,
                Duration = 6,
            })
        end)
        task.spawn(function()
            task.wait(0.5)
            sendState()
        end)
    end

    local function startRemoteRoll(beeId, slot, options)
        options = type(options) == "table" and options or {}
        local targetOrder = {}
        local targets = {}
        local function addTarget(value)
            local item = beeMapById and beeMapById[tostring(value or "")]
            if item and not targets[item.id] then
                targets[item.id] = item
                table.insert(targetOrder, item.id)
            end
        end
        if type(options.beeIds) == "table" then
            for _, value in ipairs(options.beeIds) do
                addTarget(value)
            end
        end
        addTarget(beeId)
        if #targetOrder == 0 then return false, "unknown_bee" end

        local primaryBee = targets[targetOrder[1]]
        local ignoreNewGifted = options.ignoreNewGifted == true
        local skipExistingGiftedCheck = type(options.beeIds) == "table"
        if remoteRollJob and remoteRollJob.active then return false, "already_running" end

        local wantedSlot = nil
        if slot ~= nil and tostring(slot) ~= "" then
            local rawSlot = tostring(slot):upper():gsub("%s+", "")
            local col, row = rawSlot:match("^C([1-5]),([1-9][0-9]?)$")
            col = tonumber(col)
            row = tonumber(row)
            if not col or not row or row < 1 or row > 10 then
                return false, "invalid_slot"
            end
            wantedSlot = string.format("C%d,%d", col, row)
        end

        local grid = (readHiveGrid and readHiveGrid()) or {}
        local eligible = {}
        local eligibleCount = 0
        local existingGiftedSlot = nil
        local selectedSlotGifted = nil
        for r = 1, 10 do
            for c = 1, 5 do
                local cell = grid[r] and grid[r][c]
                local key = string.format("C%d,%d", c, r)
                if not skipExistingGiftedCheck and cell and cell.beeType and targets[cell.beeType] and cell.gifted == true then
                    existingGiftedSlot = key
                end
                if wantedSlot then
                    if key == wantedSlot then
                        if cell and cell.gifted == true then
                            selectedSlotGifted = key
                        else
                            eligible[key] = true
                            eligibleCount = 1
                        end
                    end
                elseif not (cell and cell.gifted == true) then
                    eligible[key] = true
                    eligibleCount = eligibleCount + 1
                end
            end
        end

        if existingGiftedSlot then
            return false, "already_gifted_in_" .. existingGiftedSlot
        end
        if selectedSlotGifted then
            return false, "slot_gifted"
        end
        if eligibleCount == 0 then return false, "no_eligible_slots" end

        if rollRunning then pcall(stopAutoRoll) end

        local snapshot = {
            mode = currentBuildMode,
            composition = copyTable(compositionTargets),
            exact = copyTable(exactSlotTargets),
            selected = copyTable(selectedHiveSlots),
            autoSync = autoSyncSettings,
            autoBuy = autoBuyRJ,
            buyAmount = buyRJAmount,
        }

        local targetNames = {}
        local rarityRank = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }
        local topRarity = "Common"
        local topRank = 0
        for _, id in ipairs(targetOrder) do
            local item = targets[id]
            table.insert(targetNames, item.name)
            local rank = rarityRank[item.rarity] or 0
            if rank > topRank then
                topRank = rank
                topRarity = item.rarity
            end
        end
        local targetName = table.concat(targetNames, ", ")

        remoteRollJob = {
            active = true,
            target = primaryBee.id,
            targetName = targetName,
            targetIds = targetOrder,
            targets = targets,
            ignoreNewGifted = ignoreNewGifted,
            startedAt = os.time(),
            snapshot = snapshot,
            discovered = discoveredIdSet(),
            eligible = eligibleCount,
            slot = wantedSlot,
        }
        currentBuildMode = "Composition"
        compositionTargets = {}
        for _, id in ipairs(targetOrder) do
            table.insert(compositionTargets, { beeId = id, gifted = "Gifted", count = 1 })
        end
        exactSlotTargets = {}
        selectedHiveSlots = eligible
        -- The web owns the "sync game settings" permission: a queue/remote roll
        -- must not re-enable Until mythic/legendary when the player turned sync
        -- off. With sync on this keeps the historical behaviour.
        autoSyncSettings = forcedRollFlags.syncSettings ~= false
        autoBuyRJ = true
        buyRJAmount = math.max(25000, tonumber(buyRJAmount) or 25000)
        hasUserConfiguredTargets = true

        if feedRunning then pcall(stopAutoFeed, true) end
        pcall(pauseAtlas, true)
        rollRunning = true
        webRollRunning = true
        if rollToggle then
            pcall(function() rollToggle:Set(true) end)
        end
        if rollStatusLabel then
            pcall(function()
                rollStatusLabel:SetDesc(string.format("Discord: rolling %s until gifted", targetName))
            end)
        end
        if refreshQuotaText then pcall(refreshQuotaText) end
        if refreshBuilderStatus then pcall(refreshBuilderStatus) end
        task.spawn(function()
            task.wait(0.4)
            sendState()
        end)
        return true, {
            target = primaryBee.id,
            targetName = targetName,
            targets = targetOrder,
            slots = eligibleCount,
            slot = wantedSlot,
        }
    end

    -- Mythic bees are the only ones the web "stop on mythic" toggle watches, and
    -- Bee Swarm reports them by id, so one lookup is enough.
    local function mythicBeeName(beeType)
        local bee = beeMapById and beeMapById[tostring(beeType or "")]
        if bee and bee.rarity == "Mythic" then return bee end
        return nil
    end

    local function checkRemoteRoll()
        local job = remoteRollJob
        if not job or not job.active then return end

        local grid = (readHiveGrid and readHiveGrid()) or {}

        local function isTargetCell(cell)
            return cell
                and cell.beeType
                and cell.beeType ~= "Empty"
                and cell.gifted == true
                and job.targets
                and job.targets[cell.beeType] ~= nil
        end

        local targetSlot = nil
        if job.slot then
            local col, row = tostring(job.slot):match("^C(%d+),(%d+)$")
            col = tonumber(col)
            row = tonumber(row)
            local cell = col and row and grid[row] and grid[row][col]
            if isTargetCell(cell) then
                local bee = beeMapById and beeMapById[cell.beeType]
                local name = bee and bee.name or cell.beeType
                finishRemoteRoll("target_gifted", string.format("%s in %s", name, job.slot))
                return
            end
        else
            for r = 1, 10 do
                for c = 1, 5 do
                    local cell = grid[r] and grid[r][c]
                    if isTargetCell(cell) then
                        targetSlot = string.format("C%d,%d", c, r)
                        break
                    end
                end
                if targetSlot then break end
            end
        end

        if targetSlot then
            finishRemoteRoll("target_gifted", string.format("%s in %s", job.targetName, targetSlot))
            return
        end

        -- Select bee page "stop on mythic". The batch loop holds the game's Until
        -- mythic switch on, so the mythic stays in the slot long enough to be
        -- seen here. No keep list means any mythic stops the roll; with a list,
        -- only those bees do and the other mythics are rolled past.
        if forcedRollFlags.stopOnMythic == true then
            local keep = forcedRollFlags.keepMythics
            local keepAny = not (type(keep) == "table" and next(keep) ~= nil)
            local mythicBee = nil
            local mythicSlot = nil
            if job.slot then
                local col, row = tostring(job.slot):match("^C(%d+),(%d+)$")
                col = tonumber(col)
                row = tonumber(row)
                local cell = col and row and grid[row] and grid[row][col]
                local bee = cell and cell.beeType and cell.beeType ~= "Empty"
                    and mythicBeeName(cell.beeType) or nil
                if bee and (keepAny or keep[cell.beeType]) then
                    mythicBee = bee
                    mythicSlot = job.slot
                end
            else
                for r = 1, 10 do
                    for c = 1, 5 do
                        local cell = grid[r] and grid[r][c]
                        local bee = cell and cell.beeType and cell.beeType ~= "Empty"
                            and mythicBeeName(cell.beeType) or nil
                        if bee and (keepAny or keep[cell.beeType]) then
                            mythicBee = bee
                            mythicSlot = string.format("C%d,%d", c, r)
                            break
                        end
                    end
                    if mythicBee then break end
                end
            end
            if mythicBee then
                finishRemoteRoll(
                    "mythic_found",
                    string.format("%s in %s", mythicBee.name, tostring(mythicSlot))
                )
                return
            end
        end

        if not job.ignoreNewGifted then
            local newGifted = nil
            local newGiftedSlot = nil
            for r = 1, 10 do
                for c = 1, 5 do
                    local cell = grid[r] and grid[r][c]
                    if isTargetCell(cell) then
                        -- Target is handled above, including slot-specific jobs.
                    elseif cell and cell.beeType and cell.beeType ~= "Empty" and cell.gifted == true then
                        local key = string.format("C%d,%d", c, r)
                        if not job.discovered[cell.beeType] then
                            newGifted = cell.beeType
                            newGiftedSlot = key
                            break
                        end
                    end
                end
                if newGifted then break end
            end
            if newGifted then
                local bee = beeMapById and beeMapById[newGifted]
                local name = bee and bee.name or newGifted
                finishRemoteRoll("new_gifted", string.format("%s in %s", name, tostring(newGiftedSlot)))
                return
            end
        end
        if not rollRunning then
            finishRemoteRoll("stopped", "auto roll is off")
            return
        end
        if os.time() - (tonumber(job.startedAt) or os.time()) > 1800 then
            finishRemoteRoll("timeout", "30 minutes")
        end
    end

    local function report(command, ok, result, err)
        if not command or not command.id then return end
        request("POST", "/api/v1/result", {
            commandId = command.id,
            ok = ok and true or false,
            result = result or {},
            error = err and tostring(err) or "",
        }, sessionToken)
    end

    local function applyRemoteConfig(payload)
        if type(payload) ~= "table" then return false, "bad_config" end
        local config = type(payload.config) == "table" and payload.config or payload
        local name = trim(config.name or "DiscordHive"):gsub("[^%w_%- ]", ""):gsub("%s+", " ")
        if name == "" then name = "DiscordHive" end
        name = name:sub(1, 48)
        config.name = name

        ensureDir()
        local path = HIVE_CONFIGS_DIR .. "/" .. name .. ".json"
        if writefile then
            local okEnc, raw = pcall(function() return HttpService:JSONEncode(config) end)
            if okEnc and raw then pcall(writefile, path, raw) end
        end

        local ok, err = applyLoadedHiveConfig(config)
        if not ok then return false, err or "apply_failed" end
        if refreshQuotaText then pcall(refreshQuotaText) end
        if refreshHiveGrid then pcall(refreshHiveGrid) end
        if refreshBuilderStatus then pcall(refreshBuilderStatus) end
        if refreshSsaStatus then pcall(refreshSsaStatus) end
        return true, { name = name, path = path }
    end

    -- /startroll and the web "Roll" button: roll the hive plan that is already
    -- applied (Composition / Exact targets), the same thing the in-game
    -- "Auto roll" switch does. A targeted /rollssa job owns the roll loop while
    -- it runs, so refuse instead of fighting it.
    local function startBuilderRoll()
        if remoteRollJob and remoteRollJob.active then
            return false, "targeted_roll_running"
        end
        if rollRunning then
            return true, { started = true, already = true, mode = tostring(currentBuildMode or "Composition") }
        end
        if not hasUserConfiguredTargets then
            return false, "no_targets_configured"
        end
        if feedRunning then pcall(stopAutoFeed, true) end
        pcall(pauseAtlas, true)
        rollRunning = true
        if rollToggle then
            pcall(function() rollToggle:Set(true) end)
        end
        if rollStatusLabel then
            pcall(function()
                rollStatusLabel:SetDesc(string.format("Rolling %s plan", tostring(currentBuildMode or "Composition")))
            end)
        end
        if refreshQuotaText then pcall(refreshQuotaText) end
        if refreshBuilderStatus then pcall(refreshBuilderStatus) end
        task.spawn(function()
            task.wait(0.3)
            sendState()
        end)
        return true, { started = true, mode = tostring(currentBuildMode or "Composition") }
    end

    local function applyCommand(command)
        local kind = tostring(command.type or "")
        if kind == "PING" then
            return true, { pong = true }
        elseif kind == "REQUEST_STATE" then
            sendState()
            return true, { sent = true }
        elseif kind == "APPLY_HIVE_CONFIG" then
            return applyRemoteConfig(command.payload)
        elseif kind == "START_ROLL" then
            -- The web Roll button sends the plan along with the start request so
            -- pressing it once both applies the hive and starts rolling.
            local payload = command.payload or {}
            if type(payload.config) == "table" then
                local configOk, configError = applyRemoteConfig(payload.config)
                if not configOk then return false, configError or "apply_failed" end
            end
            return startBuilderRoll()
        elseif kind == "STOP_ROLL" then
            -- Builder stop. Finishing the targeted job first keeps it from being
            -- stranded (its roll loop is the same one stopAutoRoll switches off).
            if remoteRollJob and remoteRollJob.active then
                finishRemoteRoll("stopped_by_user", "/stoproll")
            elseif stopAutoRoll then
                pcall(stopAutoRoll)
            end
            return true, { stopped = true }
        elseif kind == "STOP_SSA" then
            if not (remoteRollJob and remoteRollJob.active) then
                return false, "no_targeted_roll"
            end
            finishRemoteRoll("stopped_by_user", "/stoprollssa")
            return true, { stopped = true }
        elseif kind == "ROLL_SSA" then
            local payload = command.payload or {}
            if type(payload.rollFlags) == "table" then
                pcall(applyRollFlags, payload.rollFlags, true)
            end
            return startRemoteRoll(payload.beeId or payload.bee or payload.name, payload.slot, payload)
        elseif kind == "SET_ROLL_FLAGS" then
            local flags = applyRollFlags(command.payload or {}, true)
            return true, { rollFlags = flags }
        end
        return false, "unknown_command"
    end

    local function handleCommand(command)
        local ok, result, detail = pcall(function()
            return applyCommand(command)
        end)
        if not ok then
            report(command, false, nil, result)
            return
        end

        local success = result == true
        local payload = success and (type(detail) == "table" and detail or {}) or nil
        local errorText = success and "" or tostring(detail or "command_failed")
        report(command, success, payload, errorText)
        if success then sendState() end
    end

    local function pollOnce()
        local res, err = request("GET", "/api/v1/poll?timeout=20", nil, sessionToken)
        if not res then
            if err == "unauthorized" then
                -- Do not wipe the session from here: sendState() confirms a 401
                -- twice before clearing, so a transient server error cannot
                -- permanently unlink a healthy client.
                setStatus("Session rejected, retrying...")
            end
            return
        end
        if type(res.command) == "table" and res.command.id then
            handleCommand(res.command)
        end
    end

    local function startLoops()
        generation = generation + 1
        local myGeneration = generation
        task.spawn(function()
            while scriptAlive and myGeneration == generation do
                if sessionToken and sessionToken ~= "" then
                    local ok, err = pcall(pollOnce)
                    if not ok then warn("[DiscordBridge] poll: " .. tostring(err)) end
                else
                    task.wait(2)
                end
            end
        end)
        task.spawn(function()
            while scriptAlive and myGeneration == generation do
                if sessionToken and sessionToken ~= "" then
                    pcall(sendState)
                end
                task.wait(8)
            end
        end)
    end

    local function stopLoops()
        generation = generation + 1
    end

    local function shutdown()
        local job = remoteRollJob
        if job and job.active then
            job.active = false
            webRollRunning = false
            job.reason = "script_reloaded"
            job.detail = "cleanup"
            job.finishedAt = os.time()
            local snapshot = job.snapshot
            if snapshot then
                currentBuildMode = snapshot.mode or "Composition"
                compositionTargets = snapshot.composition or {}
                exactSlotTargets = snapshot.exact or {}
                selectedHiveSlots = snapshot.selected or {}
                autoSyncSettings = snapshot.autoSync ~= false
                autoBuyRJ = snapshot.autoBuy ~= false
                buyRJAmount = tonumber(snapshot.buyAmount) or buyRJAmount
            end
            autoSyncSettings = forcedRollFlags.syncSettings ~= false
            pcall(function() if autoSyncToggle then autoSyncToggle:Set(autoSyncSettings) end end)
            hasUserConfiguredTargets = (#compositionTargets > 0) or (next(exactSlotTargets) ~= nil)
        end
        stopLoops()
    end

    local function connect(code)
        code = trim(code)
        if code == "" then
            setStatus("Enter the code from /link")
            return false, "code_missing"
        end
        if trim(bridgeUrl) == "" then
            setStatus("Set the bridge URL first")
            return false, "url_missing"
        end
        connectedOnce = false
        setStatus("Linking...")

        local executorName = "Unknown"
        if detectExecutor then pcall(function() executorName = select(1, detectExecutor()) or "Unknown" end) end
        local platform = "Unknown"
        if getPlatformLabel then pcall(function() platform = getPlatformLabel() end) end

        local res, err = request("POST", "/api/v1/link", {
            code = code,
            playerName = tostring(player.Name),
            placeId = tostring(game.PlaceId),
            jobId = tostring(game.JobId),
            executor = executorName,
            platform = platform,
        })

        if not res or type(res.token) ~= "string" or res.token == "" then
            local why = tostring(err or (type(res) == "table" and res.error) or "unknown")
            setStatus("Link failed: " .. why)
            return false, why
        end

        sessionToken = res.token
        linkedDiscordId = res.discordId and tostring(res.discordId) or nil
        saveSession()
        setStatus("Linked to Discord " .. tostring(linkedDiscordId or ""))
        startLoops()
        task.spawn(function()
            task.wait(0.5)
            sendState()
        end)
        return true
    end

    local function disconnect()
        connectedOnce = false
        generation = generation + 1
        if sessionToken and sessionToken ~= "" then
            pcall(function() request("POST", "/api/v1/unlink", nil, sessionToken) end)
        end
        clearSession()
        setStatus("Disconnected")
    end

    local function setUrl(value)
        bridgeUrl = normalizeBridgeUrl(value)
        if getgenv then pcall(function() getgenv().IvyisBridgeUrl = bridgeUrl end) end
        if sessionToken and sessionToken ~= "" then
            saveSession()
        end
    end

    local function start()
        if started then return end
        started = true
        loadSession()
        if getgenv then
            local g = getgenv()
            if type(g) == "table" then
                if type(g.IvyisBridgeUrl) == "string" and g.IvyisBridgeUrl ~= "" then
                    bridgeUrl = normalizeBridgeUrl(g.IvyisBridgeUrl)
                end
            end
        end
        if sessionToken and sessionToken ~= "" then
            setStatus("Reconnecting...")
            startLoops()
            task.spawn(function()
                task.wait(2)
                sendState()
            end)
        else
            setStatus(bridgeUrl ~= "" and "Not linked. Run /link." or "Set the bridge URL.")
        end
    end

    task.spawn(function()
        while scriptAlive do
            if remoteRollJob and remoteRollJob.active then
                local ok, err = pcall(checkRemoteRoll)
                if not ok then warn("[DiscordBridge] remote roll: " .. tostring(err)) end
            end
            task.wait(0.25)
        end
    end)

    if getgenv then
        pcall(function()
            getgenv().IvyisDiscordBridge = {
                connect = connect,
                disconnect = disconnect,
                sendState = sendState,
                setUrl = setUrl,
                start = start,
                stopLoops = stopLoops,
                shutdown = shutdown,
                startRoll = startRemoteRoll,
                stopRoll = function(reason)
                    finishRemoteRoll(reason or "manual", "bridge")
                end,
                getRemoteJob = function() return remoteRollJob end,
            }
        end)
    end

    return {
        connect = connect,
        disconnect = disconnect,
        sendState = sendState,
        setStatusSink = function(fn) statusSink = fn end,
        setUrl = setUrl,
        start = start,
        stopLoops = stopLoops,
        shutdown = shutdown,
        startRoll = startRemoteRoll,
        stopRoll = function(reason)
            finishRemoteRoll(reason or "manual", "bridge")
        end,
        getRemoteJob = function() return remoteRollJob end,
        getUrl = function() return bridgeUrl end,
        isLinked = function() return sessionToken ~= nil and sessionToken ~= "" end,
    }
end)()

getgenv().IvyisDiscordBridge.setStatusSink(function(text)
    local label = getgenv().IvyisDiscordStatusLabel
    if label then
        pcall(function() label:SetDesc(tostring(text or "")) end)
    end
end)

-- ap dung cai dat da luu, roi moi bat dau ghi lai thay doi
for _, item in ipairs(SettingsStore.pending) do
    pcall(item[1], item[2])
end
SettingsStore.pending = {}
SettingsStore.ready = true
pcall(function()
    local bridge = getgenv().IvyisDiscordBridge
    if bridge then bridge.start() end
end)
pcall(function() Progression.setHudVisible(true) end)

-- Push a fresh state as soon as the player comes back to the game, so /status
-- leaves "Idle" immediately instead of waiting for the next heartbeat tick.
if UserInputService then
    local okFocus, focusConnection = pcall(function()
        return UserInputService.WindowFocused:Connect(function()
            local bridge = getgenv().IvyisDiscordBridge
            if bridge and bridge.sendState then
                task.spawn(function() pcall(bridge.sendState) end)
            end
        end)
    end)
    if okFocus and focusConnection then
        table.insert(scriptConnections, focusConnection)
    end
end

IvyisUI:Notify({ Title = "Ivyis BSS", Content = "Ready", Duration = 3 })

if getgenv then
    getgenv()._AutoFeedCleanup = function()
        scriptAlive = false
        feedRunning = false
        rollRunning = false
        pcall(function()
            local bridge = getgenv().IvyisDiscordBridge
            if bridge and bridge.shutdown then
                bridge.shutdown()
            elseif bridge and bridge.stopLoops then
                bridge.stopLoops()
            end
        end)
        if restoreRollSettings then pcall(restoreRollSettings) end
        Progression.cleanupProgression()
        local hold = getgenv and getgenv().IvyisAtlasHold
        if hold and hold.release then pcall(hold.release) end
        if pauseAtlas then pcall(function() pauseAtlas(false) end) end
        if activeTween then pcall(function() activeTween:Cancel() end) activeTween = nil end
        if antiAfkConn then pcall(function() antiAfkConn:Disconnect() end) antiAfkConn = nil end
        if stripConn then pcall(function() setMapRemoval(false) end) end
        for _, c in ipairs(scriptConnections) do
            pcall(function() c:Disconnect() end)
        end
        table.clear(scriptConnections)
        pcall(function()
            if Window and Window.Destroy then
                task.spawn(function() pcall(function() Window:Destroy() end) end)
            end
        end)
        destroyOldGuis(CoreGui)
        if gethui then destroyOldGuis(gethui()) end
        destroyOldGuis(player.PlayerGui)
    end
end
