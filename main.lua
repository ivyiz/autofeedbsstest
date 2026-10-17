local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local UserInputService = UIS
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

if getgenv and getgenv()._AutoFeedCleanup then
    pcall(getgenv()._AutoFeedCleanup)
    getgenv()._AutoFeedCleanup = nil
end

local isScriptRunning = true
local scriptConnections = {}
local function trackConn(c)
    table.insert(scriptConnections, c)
    return c
end

local function cleanupOldInstances(parent)
    if not parent then return end
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name:find("AutoFeed") or child.Name:find("AutoTreat") or child.Name:find("WindUI") then
            pcall(function() child:Destroy() end)
        end
    end
end
cleanupOldInstances(CoreGui)
if gethui then cleanupOldInstances(gethui()) end
cleanupOldInstances(player.PlayerGui)

local WindUI = nil
pcall(function()
    if isfile and isfile("ui-libraries/windui.lua") then
        WindUI = loadfile("ui-libraries/windui.lua")()
    end
end)
if not WindUI then
    WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
end
if WindUI then
    pcall(function()
        WindUI:SetFont("rbxasset://fonts/families/FredokaOne.json")
    end)
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

local autoRunning = false
local autoRollRunning = false
local targetLevel = 15
local targetBeeCount = 50
local walkSpeed = 60
local autoBuyEnabled = true
local returnHiveEnabled = true
local autoPauseAtlas = true
local activeTween = nil
local feedToggle = nil
local rollToggle = nil
local setAtlasStopEverything
local stopAutoFeed
local stopAutoRoll

function stopAutoFeed(keepAtlas)
    autoRunning = false
    if not keepAtlas and setAtlasStopEverything then
        setAtlasStopEverything(false)
    end
    if activeTween then
        pcall(function() activeTween:Cancel() end)
        activeTween = nil
    end
    if feedToggle then
        pcall(function() feedToggle:Set(false) end)
    end
end

function stopAutoRoll(keepAtlas)
    autoRollRunning = false
    if not keepAtlas and setAtlasStopEverything then
        setAtlasStopEverything(false)
    end
    if activeTween then
        pcall(function() activeTween:Cancel() end)
        activeTween = nil
    end
    if rollToggle then
        pcall(function() rollToggle:Set(false) end)
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

local bondTable = {
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
        total = total + (bondTable[i] or (bondTable[25] * 2^(i - 25)))
    end
    return total
end

local function calcBeeTreats(currentLvl, currentBond, targetLvl, bftBonus)
    local lvl = math.max(1, math.floor(tonumber(currentLvl) or 1))
    local bond = math.max(0, tonumber(currentBond) or 0)
    local tgt = math.max(1, math.floor(tonumber(targetLvl) or 1))

    if lvl >= tgt then return 0 end

    local totalRemainingBond = 0
    local reqThisLvl = bondTable[lvl] or (bondTable[25] * 2^(lvl - 25))
    totalRemainingBond = totalRemainingBond + math.max(0, reqThisLvl - bond)

    for l = lvl + 1, tgt - 1 do
        totalRemainingBond = totalRemainingBond + (bondTable[l] or (bondTable[25] * 2^(l - 25)))
    end

    local bonusPct = math.max(0, tonumber(bftBonus) or 0)
    local effectiveTreatBond = TREAT_BOND * (1 + bonusPct / 100)
    local treats = math.ceil(totalRemainingBond / effectiveTreatBond)
    return treats
end

local function getStatData()
    local data = nil
    pcall(function()
        local cache = RS:FindFirstChild("ClientStatCache")
        if cache then
            local mod = require(cache)
            if type(mod) == "table" and type(mod.Get) == "function" then
                data = mod:Get() or mod:Get(player)
            end
        end
    end)
    if type(data) == "table" then return data end
    pcall(function()
        local rf = getRemote("RetrievePlayerStats")
        if rf then data = callRemote(rf) end
    end)
    return (type(data) == "table") and data or nil
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

local function getHoneyNeededForTarget(tgtLvl, tgtBees)
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
    local typeName = tostring((cellTypeVal and cellTypeVal.Value) or cell:GetAttribute("CellType") or "Empty")

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
        if tl and tonumber(tl.Text) then
            lvlVal = tonumber(tl.Text)
        end
    end

    local isGifted = false
    if typeName:lower():find("gifted") then isGifted = true end
    for _, desc in ipairs(cell:GetDescendants()) do
        local n = desc.Name:lower()
        if n:find("gifted") or ((desc:IsA("Decal") or desc:IsA("ParticleEmitter")) and n:find("star")) then
            isGifted = true
            break
        end
    end
    if cell:FindFirstChild("GiftedCell") then
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

local cachedGrid = nil
local lastGridFetch = 0
local function getAllHiveCells(force)
    if not force and cachedGrid and (os.clock() - lastGridFetch < 0.5) then
        return cachedGrid
    end
    local myHive = getMyHive()
    if not myHive then return {} end
    local cellsFolder = myHive:FindFirstChild("Cells")
    if not cellsFolder then return {} end

    local grid = {}
    for r = 1, 10 do
        grid[r] = {}
        for c = 1, 5 do
            local cellName = string.format("C%d,%d", c, r)
            local cell = cellsFolder:FindFirstChild(cellName)
            if cell then
                grid[r][c] = getCellData(cell)
            end
        end
    end
    cachedGrid = grid
    lastGridFetch = os.clock()
    return grid
end

local function tweenTo(cf, speed)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChild("Humanoid")
    if not root or not hum or not cf then return false end

    local targetCFrame = if typeof(cf) == "CFrame" then cf else CFrame.new(cf)
    local spd = speed or walkSpeed or 65
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
        if not isScriptRunning or (not autoRunning and not autoRollRunning) then
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

    return (root.Position - endPos).Magnitude <= 5
end

local cachedAtlasObj = nil
local cachedAtlasBtn = nil
local lastAtlasState = nil
local originalAtlasState = nil
local atlasLastSearched = 0

function setAtlasStopEverything(enable)
    if not autoPauseAtlas then return false end
    if lastAtlasState == enable then return true end

    if enable and originalAtlasState == nil then
        if cachedAtlasObj then
            originalAtlasState = rawget(cachedAtlasObj, "Value") or rawget(cachedAtlasObj, "State")
        end
    end

    local targetState = enable
    if not enable and originalAtlasState == true then
        targetState = true
    end

    if not enable then
        originalAtlasState = nil
    end

    if cachedAtlasObj then
        if type(rawget(cachedAtlasObj, "Set")) == "function" then
            local ok = pcall(function() cachedAtlasObj:Set(targetState) end)
            if ok then lastAtlasState = targetState return true end
        elseif type(rawget(cachedAtlasObj, "Callback")) == "function" then
            local ok = pcall(function() cachedAtlasObj.Callback(targetState) end)
            if ok then lastAtlasState = targetState return true end
        end
    end

    if not cachedAtlasObj and not cachedAtlasBtn then
        if os.clock() - atlasLastSearched < 10 then
            return false
        end
        atlasLastSearched = os.clock()

        if getgc then
            local success, gc = pcall(getgc, true)
            if success and type(gc) == "table" then
                for _, obj in ipairs(gc) do
                    if typeof(obj) == "table" then
                        local name = rawget(obj, "Title") or rawget(obj, "Name") or rawget(obj, "Text")
                        if type(name) == "string" and name:lower():find("stop everything") and not name:lower():find("auto pause") then
                            if type(rawget(obj, "Set")) == "function" then
                                cachedAtlasObj = obj
                                if enable and originalAtlasState == nil then
                                    originalAtlasState = rawget(obj, "Value") or rawget(obj, "State")
                                end
                                pcall(function() obj:Set(targetState) end)
                                lastAtlasState = targetState
                                return true
                            elseif type(rawget(obj, "Callback")) == "function" then
                                cachedAtlasObj = obj
                                if enable and originalAtlasState == nil then
                                    originalAtlasState = rawget(obj, "Value") or rawget(obj, "State")
                                end
                                pcall(function() obj.Callback(targetState) end)
                                lastAtlasState = targetState
                                return true
                            end
                        end
                    end
                end
            end
        end

        local hui = (gethui and gethui()) or game:GetService("CoreGui")
        for _, desc in ipairs(hui:GetDescendants()) do
            if (desc:IsA("TextLabel") or desc:IsA("TextButton")) and desc.Text:lower():find("stop everything") and not desc.Text:lower():find("auto pause") then
                local btn = desc:IsA("GuiButton") and desc or desc.Parent:FindFirstChildWhichIsA("GuiButton", true)
                if btn then
                    cachedAtlasBtn = btn
                    break
                end
            end
        end
    end

    if cachedAtlasBtn and firesignal then
        pcall(function() firesignal(cachedAtlasBtn.Activated) end)
        pcall(function() firesignal(cachedAtlasBtn.MouseButton1Click) end)
        lastAtlasState = targetState
        return true
    end

    return false
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

local function ensureAtHive()
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

local function ensureAtPos(targetPos, maxDist)
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

local function rollBee(col, row, rjCount)
    local remote = getRemote("ConstructHiveCellFromEgg")
    if not remote or not col or not row or rjCount <= 0 then return false, nil end
    local c = tonumber(col)
    local r = tonumber(row)
    local amt = math.floor(tonumber(rjCount) or 1)
    local ok, res = pcall(function()
        return callRemote(remote, c, r, "RoyalJelly", amt)
    end)
    return ok, res
end

local function setBSSSetting(settingName, val)
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

local IVYIS_ICON_B64 = "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"
local ivyisIconAsset = nil
local function getIvyisIcon()
    if ivyisIconAsset then return ivyisIconAsset end
    local filename = "ivyis_bg.png"
    if getcustomasset and isfile and isfile(filename) then
        local ok, asset = pcall(getcustomasset, filename)
        if ok and asset then
            ivyisIconAsset = asset
            return asset
        end
    end
    filename = "ivyis_icon.png"
    if isfile and writefile and (not isfile(filename)) then
        if crypt and crypt.base64decode then
            pcall(function() writefile(filename, crypt.base64decode(IVYIS_ICON_B64)) end)
        elseif base64_decode then
            pcall(function() writefile(filename, base64_decode(IVYIS_ICON_B64)) end)
        end
    end
    if getcustomasset and isfile and isfile(filename) then
        local ok, asset = pcall(getcustomasset, filename)
        if ok and asset then
            ivyisIconAsset = asset
            return asset
        end
    end
    return "rbxassetid://4503856569"
end

WindUI:AddTheme({
    Name = "Pearl",
    Accent = Color3.fromHex("#18181B"),
    Dialog = Color3.fromHex("#F4F4F7"),
    Outline = Color3.fromHex("#D9D9E1"),
    Text = Color3.fromHex("#18181B"),
    Placeholder = Color3.fromHex("#85858F"),
    Background = Color3.fromHex("#F4F4F7"),
    Button = Color3.fromHex("#E8E8EE"),
    Icon = Color3.fromHex("#45454F"),
    Toggle = Color3.fromHex("#18181B"),
    Slider = Color3.fromHex("#18181B"),
    Checkbox = Color3.fromHex("#18181B"),
    PanelBackground = Color3.fromHex("#FFFFFF"),
    PanelBackgroundTransparency = 0.1,
    SliderIcon = Color3.fromHex("#45454F"),
    Primary = Color3.fromHex("#18181B"),
    LabelBackground = Color3.fromHex("#FFFFFF"),
    LabelBackgroundTransparency = 0.1,
    DropdownTabBackground = Color3.fromHex("#E8E8EE"),
    DropdownBackground = Color3.fromHex("#FFFFFF"),
    TabBackground = Color3.fromHex("#FFFFFF"),
    TabBackgroundHover = Color3.fromHex("#E8E8EE"),
    TabBackgroundHoverTransparency = 0,
    TabBackgroundActive = Color3.fromHex("#D9D9E1"),
    TabBackgroundActiveTransparency = 0,
    ElementBackground = Color3.fromHex("#FFFFFF"),
    ElementBackgroundTransparency = 0,
})

pcall(function()
    WindUI.Window = nil
end)

local Window = WindUI:CreateWindow({
    Title = "Ivyis's Tool",
    Icon = "sparkles",
    Author = "by ivyis",
    Folder = "AutoFeedBSS",
    Size = UDim2.fromOffset(560, 350),
    Transparent = true,
    Theme = "Pearl",
    SideBarWidth = 180,
    HasOutline = true,
    Resizable = false
})

pcall(function()
    WindUI:SetTheme("Pearl")
end)

pcall(function()
    WindUI:SetFont("rbxasset://fonts/families/FredokaOne.json")
end)

task.spawn(function()
    local customBgAsset = getIvyisIcon()
    local hui = (gethui and gethui()) or game:GetService("CoreGui")
    for _ = 1, 40 do
        task.wait(0.25)
        local win = hui:FindFirstChild("WindUI")
        local window = win and win:FindFirstChild("Window")
        local frame = window and window:FindFirstChild("Frame")
        if frame then
            local bg = frame:FindFirstChild("IvyisBackground")
            if not bg then
                bg = Instance.new("ImageLabel")
                bg.Name = "IvyisBackground"
                bg.AnchorPoint = Vector2.new(0, 0)
                bg.Size = UDim2.new(1, 0, 1, 0)
                bg.Position = UDim2.new(0, 0, 0, 0)
                bg.BackgroundTransparency = 1
                bg.ScaleType = Enum.ScaleType.Crop
                bg.Image = customBgAsset
                bg.ImageTransparency = 0.2
                bg.ZIndex = 2
                Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 10)
                bg.Parent = frame
            else
                bg.AnchorPoint = Vector2.new(0, 0)
                bg.Size = UDim2.new(1, 0, 1, 0)
                bg.Position = UDim2.new(0, 0, 0, 0)
                bg.ScaleType = Enum.ScaleType.Crop
                bg.Image = customBgAsset
                bg.ImageTransparency = 0.2
            end
            break
        end
    end
end)

local TabTreat = Window:Tab({ Title = "Auto Treat", Icon = "cookie" })
local TabHive = Window:Tab({ Title = "Hive Builder", Icon = "layout-grid" })
local TabSettings = Window:Tab({ Title = "Settings", Icon = "settings" })

TabTreat:Section({ Title = "Treat Configuration" })

local treatStatusParagraph = TabTreat:Paragraph({
    Title = "Status",
    Desc = "Calculating..."
})

local function updateTreatStatus()
    local totalHoney, totalTreats, alreadyAtTarget, limit = getHoneyNeededForTarget(targetLevel, targetBeeCount)
    if limit == 0 then
        treatStatusParagraph:SetDesc(string.format("Target Lvl: %d | Bees: %d | Honey Needed: 0", targetLevel, targetBeeCount))
        return
    end
    if alreadyAtTarget >= limit then
        treatStatusParagraph:SetDesc(string.format("Target Lvl: %d | Bees: %d | Honey Needed: 0 (Done)", targetLevel, targetBeeCount))
    else
        treatStatusParagraph:SetDesc(string.format("Target Lvl: %d | Bees: %d | Honey Needed: %s", targetLevel, targetBeeCount, formatNum(totalHoney)))
    end
end

TabTreat:Slider({
    Title = "Target Level",
    Step = 1,
    Value = { Min = 1, Max = 25, Default = 15 },
    Callback = function(v)
        targetLevel = v
        updateTreatStatus()
    end
})

TabTreat:Slider({
    Title = "Target Bee Count",
    Step = 1,
    Value = { Min = 1, Max = 50, Default = 50 },
    Callback = function(v)
        targetBeeCount = v
        updateTreatStatus()
    end
})

updateTreatStatus()

TabTreat:Toggle({
    Title = "Auto Buy Treats",
    Value = true,
    Callback = function(v) autoBuyEnabled = v end
})

TabTreat:Toggle({
    Title = "Return to Hive After Buying",
    Value = true,
    Callback = function(v) returnHiveEnabled = v end
})

TabTreat:Slider({
    Title = "Walk/Tween Speed",
    Step = 5,
    Value = { Min = 20, Max = 120, Default = 60 },
    Callback = function(v) walkSpeed = v end
})

TabTreat:Section({ Title = "Automation" })

feedToggle = TabTreat:Toggle({
    Title = "Start Auto Feed",
    Value = false,
    Callback = function(v)
        if v == autoRunning then return end
        autoRunning = v
        if autoRunning then
            if autoRollRunning then
                stopAutoRoll(true)
            end
            setAtlasStopEverything(true)
            WindUI:Notify({ Title = "Auto Feed", Content = "Auto Feed has been STARTED", Duration = 3 })
        else
            stopAutoFeed()
            WindUI:Notify({ Title = "Auto Feed", Content = "Auto Feed has been STOPPED", Duration = 3 })
            updateTreatStatus()
        end
    end
})

TabHive:Section({ Title = "Hive Builder Mode" })

local builderStatusParagraph = TabHive:Paragraph({
    Title = "Builder Status",
    Desc = "Selected Slots: 0 / 50 | Total Targets Desired: 0"
})

local function getShortBeeName(id)
    if not id then return "?" end
    return id:gsub("Bee$", ""):gsub("^%s+", "")
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
    table.insert(beeDropdownOptions, opt)
end

local refreshHiveGrid
local updateStatusUI

local hui = (gethui and gethui()) or game:GetService("CoreGui")
if hui:FindFirstChild("AutoFeed_HiveModalGui") then
    hui:FindFirstChild("AutoFeed_HiveModalGui"):Destroy()
end
if hui:FindFirstChild("AutoFeed_MobileToggle") then
    hui:FindFirstChild("AutoFeed_MobileToggle"):Destroy()
end

local function toggleMainWindow()
    local winFrame = Window.UIElements and Window.UIElements.Main
    local isHidden = Window.Closed or (winFrame and winFrame.Size.Y.Offset < 50) or (winFrame and not winFrame.Visible) or (winFrame and winFrame:FindFirstChild("Main") and not winFrame.Main.Visible)
    if isHidden then
        if Window.Open then pcall(function() Window:Open() end) end
        if winFrame then
            winFrame.Visible = true
            if winFrame:FindFirstChild("Main") then winFrame.Main.Visible = true end
        end
    else
        if Window.Close then
            pcall(function() Window:Close() end)
        elseif winFrame then
            winFrame.Visible = false
        end
    end
end

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
Instance.new("UICorner", mobileBtn).CornerRadius = UDim.new(0, 14)

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

local mDragging = false
local mDragStart = nil
local mStartPos = nil
local mHasMoved = false

trackConn(mobileBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        mDragging = true
        mDragStart = input.Position
        mStartPos = mobileBtn.Position
        mHasMoved = false
    end
end))

trackConn(UserInputService.InputChanged:Connect(function(input)
    if mDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - mDragStart
        if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then mHasMoved = true end
        local camera = workspace.CurrentCamera
        local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local curAbsX = mStartPos.X.Scale * vp.X + mStartPos.X.Offset
        local curAbsY = mStartPos.Y.Scale * vp.Y + mStartPos.Y.Offset
        local newX = math.clamp(curAbsX + delta.X, 0, vp.X - 52)
        local newY = math.clamp(curAbsY + delta.Y, 0, vp.Y - 52)
        mobileBtn.Position = UDim2.new(0, newX, 0, newY)
    end
end))

trackConn(mobileBtn.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        mDragging = false
    end
end))

trackConn(mobileBtn.Activated:Connect(function()
    if not mHasMoved then toggleMainWindow() end
    mHasMoved = false
end))

pcall(function() Window:SetToggleKey(Enum.KeyCode.RightControl) end)
pcall(function()
    Window:OnClose(function()
        if mobileGui then mobileGui.Enabled = true end
        WindUI:Notify({ Title = "Window Minimized", Content = "Tap the floating bee button to reopen!", Duration = 3 })
    end)
end)

local modalGui = Instance.new("ScreenGui")
modalGui.Name = "AutoFeed_HiveModalGui"
modalGui.ResetOnSpawn = false
modalGui.DisplayOrder = 200000
modalGui.Parent = hui

local modalFrame = Instance.new("Frame")
modalFrame.Name = "HiveSelectionModal"
modalFrame.Size = UDim2.new(0, 264, 0, 570)
modalFrame.Position = UDim2.new(0.5, -132, 0.5, -285)
modalFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
modalFrame.BackgroundTransparency = 0.05
modalFrame.BorderSizePixel = 0
modalFrame.Visible = false
modalFrame.Parent = modalGui
Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 10)

local modalStroke = Instance.new("UIStroke")
modalStroke.Color = Color3.fromRGB(40, 45, 60)
modalStroke.Thickness = 1.5
modalStroke.Parent = modalFrame

local headerBar = Instance.new("Frame")
headerBar.Name = "HeaderBar"
headerBar.Size = UDim2.new(1, 0, 0, 36)
headerBar.BackgroundTransparency = 1
headerBar.Parent = modalFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -24, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Select Hive Slots (0/50)"
titleLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
titleLabel.Font = Enum.Font.FredokaOne
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
hiveScroll.Parent = modalFrame

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
bottomCloseBtn.Font = Enum.Font.FredokaOne
bottomCloseBtn.TextSize = 12
bottomCloseBtn.Parent = modalFrame
Instance.new("UICorner", bottomCloseBtn).CornerRadius = UDim.new(0, 6)
bottomCloseBtn.MouseButton1Click:Connect(function() modalFrame.Visible = false end)

local slotTiles = {}

function updateStatusUI()
    local selectedCount = 0
    for _, state in pairs(selectedHiveSlots) do
        if state then selectedCount = selectedCount + 1 end
    end
    local totalTargets = 0
    for _, item in ipairs(compositionTargets) do
        totalTargets = totalTargets + (tonumber(item.count) or 0)
    end
    if builderStatusParagraph then
        builderStatusParagraph:SetDesc(string.format("Selected Slots: %d / 50 | Total Targets Desired: %d", tonumber(selectedCount) or 0, tonumber(totalTargets) or 0))
    end
    if titleLabel then
        titleLabel.Text = string.format("Select Hive Slots (%d/50)", tonumber(selectedCount) or 0)
    end
end

function refreshHiveGrid()
    local cellsGrid = getAllHiveCells()
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

            local isOccupied = cellData and cellData.beeType and cellData.beeType ~= "Empty" and cellData.beeType ~= "" and cellData.faceTexture ~= "rbxassetid://1471882621"

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
                lvlLabel.Font = Enum.Font.FredokaOne
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
            selLabel.Font = Enum.Font.FredokaOne
            selLabel.TextSize = 10
            selLabel.TextXAlignment = Enum.TextXAlignment.Right
            selLabel.TextYAlignment = Enum.TextYAlignment.Bottom
            selLabel.Parent = tile

            tile.MouseButton1Click:Connect(function()
                selectedHiveSlots[slotKey] = not selectedHiveSlots[slotKey]
                stroke.Color = selectedHiveSlots[slotKey] and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(25, 28, 36)
                stroke.Thickness = selectedHiveSlots[slotKey] and 2 or 1
                selLabel.Text = selectedHiveSlots[slotKey] and "Sel" or ""
                updateStatusUI()
            end)

            slotTiles[slotKey] = tile
        end
    end
    updateStatusUI()
end



local function toggleHiveModal()
    modalFrame.Visible = not modalFrame.Visible
    if modalFrame.Visible then
        refreshHiveGrid()
    end
end

TabHive:Button({
    Title = "Select Position",
    Icon = "crosshair",
    Callback = function()
        toggleHiveModal()
    end
})

TabHive:Button({
    Title = "Snapshot Current Hive",
    Icon = "camera",
    Callback = function()
        local cells = getAllHiveCells(true)
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
        updateStatusUI()
        if updateTargetsListText then updateTargetsListText() end
        WindUI:Notify({ Title = "Snapshot Created", Content = "Copied hive layout to builder", Duration = 2 })
    end
})

TabHive:Section({ Title = "Bee Selection & Targets" })

local targetsListParagraph = TabHive:Paragraph({
    Title = "Active Quota Targets",
    Desc = "No quota target bees configured | Total quota: 0"
})

local function updateTargetsListText()
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
        targetsListParagraph:SetDesc("No quota target bees configured | Total quota: 0")
    else
        targetsListParagraph:SetDesc(string.format("Quota: %s (Total: %d)", table.concat(list, " | "), tonumber(total) or 0))
    end
    updateStatusUI()
end

TabHive:Dropdown({
    Title = "Select Bee to Configure",
    Values = beeDropdownOptions,
    Value = "Buoyant Bee",
    Callback = function(val)
        selectedBeeId = beeMapByOption[val] or "BuoyantBee"
    end
})

TabHive:Dropdown({
    Title = "Gifted",
    Values = { "Any", "Gifted", "Normal" },
    Value = "Any",
    Callback = function(val)
        selectedTargetGifted = val or "Any"
    end
})

TabHive:Slider({
    Title = "Target Quantity",
    Step = 1,
    Value = { Min = 1, Max = 50, Default = 5 },
    Callback = function(v)
        selectedTargetQty = v
    end
})

TabHive:Button({
    Title = "Add / Update Quota",
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
        updateTargetsListText()
        local b = beeMapById[selectedBeeId]
        WindUI:Notify({
            Title = "Quota Added",
            Content = string.format("Set quota: %dx %s (%s)", selectedTargetQty, b and b.name or selectedBeeId, selectedTargetGifted),
            Duration = 2
        })
    end
})

TabHive:Button({
    Title = "Remove Quota",
    Icon = "minus-circle",
    Callback = function()
        for i = #compositionTargets, 1, -1 do
            local item = compositionTargets[i]
            if item.beeId == selectedBeeId and item.gifted == selectedTargetGifted then
                table.remove(compositionTargets, i)
            end
        end
        updateTargetsListText()
    end
})

TabHive:Button({
    Title = "Clear All Targets",
    Icon = "trash-2",
    Callback = function()
        compositionTargets = {}
        updateTargetsListText()
        WindUI:Notify({ Title = "Targets Cleared", Content = "All quotas reset", Duration = 2 })
    end
})

TabHive:Section({ Title = "Hive Configs" })

TabHive:Input({
    Title = "Config Name",
    Value = "MyHiveBuild",
    Placeholder = "Enter config name...",
    Callback = function(v)
        if v and v ~= "" then configNameInput = v end
    end
})

local savedConfigsDropdown = nil

local function getSavedConfigList()
    return listHiveConfigs()
end

TabHive:Button({
    Title = "Save Config",
    Icon = "save",
    Callback = function()
        ensureHiveConfigDir()
        local name = configNameInput or "MyHiveBuild"
        local raw = serializeHiveConfig(name)
        if raw and writefile then
            local path = HIVE_CONFIGS_DIR .. "/" .. name .. ".json"
            local ok, err = pcall(writefile, path, raw)
            if ok then
                WindUI:Notify({ Title = "Config Saved", Content = "Saved hive build to " .. path, Duration = 3 })
            else
                WindUI:Notify({ Title = "Save Failed", Content = tostring(err), Duration = 3 })
            end
        end
    end
})

savedConfigsDropdown = TabHive:Dropdown({
    Title = "Select Saved Config",
    Values = getSavedConfigList(),
    Value = getSavedConfigList()[1] or "None",
    Callback = function(val)
        selectedSavedConfig = val
    end
})

TabHive:Button({
    Title = "Load Config",
    Icon = "folder-open",
    Callback = function()
        if not selectedSavedConfig or selectedSavedConfig == "None" then
            WindUI:Notify({ Title = "Load Config", Content = "No config selected!", Duration = 2 })
            return
        end
        local path = HIVE_CONFIGS_DIR .. "/" .. selectedSavedConfig .. ".json"
        if isfile and isfile(path) and readfile then
            local ok, content = pcall(readfile, path)
            if ok and content then
                local sOk, decoded = pcall(function() return HttpService:JSONDecode(content) end)
                if sOk and decoded then
                    applyLoadedHiveConfig(decoded)
                    updateTargetsListText()
                    refreshHiveGrid()
                    updateStatusUI()
                    WindUI:Notify({ Title = "Config Loaded", Content = "Loaded " .. selectedSavedConfig .. " successfully!", Duration = 3 })
                    return
                end
            end
        end
        WindUI:Notify({ Title = "Load Failed", Content = "Could not read " .. tostring(selectedSavedConfig), Duration = 3 })
    end
})

TabHive:Button({
    Title = "Refresh List",
    Icon = "rotate-cw",
    Callback = function()
        local list = getSavedConfigList()
        if savedConfigsDropdown and savedConfigsDropdown.SetValues then
            pcall(function() savedConfigsDropdown:SetValues(list) end)
        end
        WindUI:Notify({ Title = "Config List", Content = string.format("Found %d saved configs", #list), Duration = 2 })
    end
})

TabHive:Button({
    Title = "Export to Clipboard",
    Icon = "clipboard-copy",
    Callback = function()
        local raw = serializeHiveConfig(configNameInput)
        if raw then
            local copied = copyToClipboard(raw)
            if copied then
                WindUI:Notify({ Title = "Config Exported", Content = "Copied JSON to clipboard", Duration = 3 })
            else
                print("[HiveBuilder Export]\n" .. raw)
                WindUI:Notify({ Title = "Export Printed", Content = "Printed JSON to console (F9)!", Duration = 4 })
            end
        end
    end
})

TabHive:Input({
    Title = "Import Config JSON",
    Value = "",
    Placeholder = "Paste config JSON string here...",
    Callback = function(v)
        importJsonInput = v
    end
})

TabHive:Button({
    Title = "Import Config",
    Icon = "download",
    Callback = function()
        local text = importJsonInput
        if not text or text == "" then
            WindUI:Notify({ Title = "Import Error", Content = "Please paste a config JSON first!", Duration = 3 })
            return
        end
        local ok, decoded = pcall(function() return HttpService:JSONDecode(text) end)
        if ok and decoded and type(decoded) == "table" then
            applyLoadedHiveConfig(decoded)
            updateTargetsListText()
            refreshHiveGrid()
            updateStatusUI()
            WindUI:Notify({ Title = "Config Imported", Content = "Imported " .. tostring(decoded.name or "Config") .. " successfully!", Duration = 3 })
        else
            WindUI:Notify({ Title = "Import Failed", Content = "Invalid JSON format!", Duration = 3 })
        end
    end
})

TabHive:Section({ Title = "Auto Settings & Royal Jelly" })

TabHive:Toggle({
    Title = "Auto Sync Roll Settings",
    Value = true,
    Callback = function(v) autoSyncSettings = v end
})

TabHive:Toggle({
    Title = "Auto Buy Royal Jelly When Low",
    Value = true,
    Callback = function(v) autoBuyRJ = v end
})

TabHive:Slider({
    Title = "RJ Buy Batch Amount",
    Step = 1000,
    Value = { Min = 1000, Max = 50000, Default = 10000 },
    Callback = function(v) buyRJAmount = v end
})

TabHive:Section({ Title = "Start Auto Roll Engine" })

local rollStatusParagraph = TabHive:Paragraph({
    Title = "Engine Status",
    Desc = "Idle - Waiting to start"
})

rollToggle = TabHive:Toggle({
    Title = "Start Auto Roll",
    Value = false,
    Callback = function(v)
        if v == autoRollRunning then return end
        autoRollRunning = v
        if autoRollRunning then
            if autoRunning then stopAutoFeed(true) end
            setAtlasStopEverything(true)
            WindUI:Notify({ Title = "Auto Roll", Content = "Started in " .. currentBuildMode .. " mode", Duration = 2 })
        else
            stopAutoRoll()
            WindUI:Notify({ Title = "Auto Roll", Content = "Stopped", Duration = 2 })
        end
    end
})

TabSettings:Section({ Title = "Preferences" })

TabSettings:Toggle({
    Title = "Auto Pause Atlas",
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

TabSettings:Toggle({
    Title = "Anti-AFK (Prevent Idle Disconnect)",
    Value = true,
    Callback = function(v)
        setAntiAfk(v)
    end
})

TabSettings:Toggle({
    Title = "Mobile Floating Button",
    Value = true,
    Callback = function(v)
        if mobileGui then mobileGui.Enabled = v end
    end
})

TabSettings:Dropdown({
    Title = "UI Theme",
    Values = { "Pearl", "Dark", "Rose", "Aqua", "Emerald", "Midnight" },
    Value = "Pearl",
    Callback = function(theme)
        pcall(function() WindUI:SetTheme(theme) end)
    end
})

task.spawn(function()
    while isScriptRunning do
        if autoRunning then
            local ok, err = pcall(function()
                local data = getStatData()
                local myHive = getMyHive()
                if not myHive then return end

                local cellsGrid = getAllHiveCells()
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
                local totalHoney = getHoneyNeededForTarget(targetLevel, targetBeeCount)

                if needToUpgrade <= 0 or #candidates == 0 then
                    treatStatusParagraph:SetDesc(string.format("All %d bees reached Lvl %d! Done.", effectiveTarget, targetLevel))
                    stopAutoFeed()
                    WindUI:Notify({
                        Title = "Auto Feed Finished",
                        Content = string.format("All %d target bees reached Level %d!", effectiveTarget, targetLevel),
                        Duration = 5
                    })
                    return
                end

                setAtlasStopEverything(true)

                treatStatusParagraph:SetDesc(string.format("At Target Lvl %d: %d/%d (%d left) | Honey Needed: %s", tonumber(targetLevel) or 0, tonumber(alreadyAtTarget) or 0, tonumber(effectiveTarget) or 0, tonumber(needToUpgrade) or 0, formatNum(totalHoney)))

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
                    treatStatusParagraph:SetDesc(string.format("Out of Honey! Needs %s | Stopped.", formatNum(totalHoney)))
                    WindUI:Notify({
                        Title = "Auto Feed Stopped",
                        Content = "Out of Honey! Cannot afford treats.",
                        Duration = 5
                    })
                    return
                end

                if autoBuyEnabled and ownedTreats < treatsNeeded and honey >= TREAT_COST then
                    local toBuy = math.min(treatsNeeded - ownedTreats, math.floor(honey / TREAT_COST))
                    if toBuy > 0 then
                        treatStatusParagraph:SetDesc("Moving to Treat Shop...")
                        local shopPos = getTreatShopPos()
                        if ensureAtPos(shopPos, 20) then
                            task.wait(0.5)
                            if not autoRunning or not isScriptRunning then return end
                            treatStatusParagraph:SetDesc(string.format("Buying %s Treats...", formatNum(toBuy)))
                            buyTreats(toBuy)
                            task.wait(0.5)
                            if not autoRunning or not isScriptRunning then return end
                            data = getStatData()
                            ownedTreats = getTreats(data)
                        end
                    end
                end

                if returnHiveEnabled then
                    if not ensureAtHive() then
                        treatStatusParagraph:SetDesc("Moving to Hive platform...")
                        return
                    end
                    task.wait(0.5)
                    if not autoRunning or not isScriptRunning then return end
                end

                data = getStatData()
                ownedTreats = getTreats(data)
                if ownedTreats > 0 then
                    local toFeed = math.min(treatsNeeded, ownedTreats)
                    if toFeed > 0 then
                        treatStatusParagraph:SetDesc(string.format("Feeding %s Treats to C%d,R%d (Lvl %d)...", formatNum(toFeed), tonumber(firstCand.col) or 0, tonumber(firstCand.row) or 0, tonumber(firstCand.level) or 0))
                        feedBee(firstCand.col, firstCand.row, toFeed)
                        task.wait(0.5)
                        if not autoRunning or not isScriptRunning then return end
                    end
                elseif not autoBuyEnabled and ownedTreats == 0 then
                    stopAutoFeed()
                    treatStatusParagraph:SetDesc("Out of Treats (Auto-Buy is OFF) | Stopped.")
                    WindUI:Notify({
                        Title = "Auto Feed Stopped",
                        Content = "Out of Treats and Auto Buy is OFF.",
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

local consecutiveRollFails = 0

local function checkCellMatchesTarget(cellData, target)
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

task.spawn(function()
    while isScriptRunning do
        if autoRollRunning then
            local ok, err = pcall(function()
                setAtlasStopEverything(true)

                local cellsGrid = getAllHiveCells()
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
                                if not checkCellMatchesTarget(cd, target) then
                                    table.insert(incompleteExact, { col = c, row = r, key = key, target = target, cd = cd })
                                end
                            end
                        end
                    end

                    if totalExact == 0 then
                        rollStatusParagraph:SetDesc("No exact slot targets configured! Open grid to assign slots.")
                        stopAutoRoll()
                        return
                    end

                    if #incompleteExact == 0 then
                        rollStatusParagraph:SetDesc(string.format("All %d exact slots completed 100%! Stopped.", totalExact))
                        stopAutoRoll()
                        WindUI:Notify({ Title = "Hive Build Complete", Content = "All 100% exact slot targets matched successfully!", Duration = 5 })
                        return
                    end

                    nextTargetSlot = incompleteExact[1]
                    currentTargetObj = nextTargetSlot.target

                    rollStatusParagraph:SetDesc(string.format("Exact Mode: Slot %s needs %s (%s) | Remaining: %d/%d", 
                        tostring(nextTargetSlot.key), tostring(getShortBeeName(currentTargetObj.beeId)), tostring(currentTargetObj.gifted), tonumber(#incompleteExact) or 0, tonumber(totalExact) or 0))

                else
                    if #compositionTargets == 0 then
                        rollStatusParagraph:SetDesc("No quota targets configured! Add target bees first.")
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
                                        if checkCellMatchesTarget(cd, { beeId = bId, gifted = g }) then
                                            remainingNeeded[tag] = rem - 1
                                            protectedSlots[slotKey] = true
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end

                    local sumRemaining = 0
                    local primaryNeededTarget = nil
                    for tag, rem in pairs(remainingNeeded) do
                        sumRemaining = sumRemaining + rem
                        if rem > 0 and not primaryNeededTarget then
                            local bId, g = tag:match("^(.-)|(.*)$")
                            primaryNeededTarget = { beeId = bId, gifted = g }
                        end
                    end

                    if sumRemaining <= 0 then
                        rollStatusParagraph:SetDesc("All composition quota targets satisfied! Stopped.")
                        stopAutoRoll()
                        WindUI:Notify({ Title = "Hive Build Complete", Content = "All composition bee quotas have been satisfied!", Duration = 5 })
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
                        rollStatusParagraph:SetDesc("No eligible slots selected to roll! Select slots in grid.")
                        stopAutoRoll()
                        return
                    end

                    nextTargetSlot = candidates[1]
                    currentTargetObj = primaryNeededTarget

                    rollStatusParagraph:SetDesc(string.format("Comp Mode: Rolling %s | Next needed: %s (%s) | Left: %d/%d", 
                        tostring(nextTargetSlot.key), tostring(getShortBeeName(currentTargetObj.beeId)), tostring(currentTargetObj.gifted), tonumber(sumRemaining) or 0, tonumber(totalNeeded) or 0))
                end

                if not nextTargetSlot then
                    stopAutoRoll()
                    return
                end

                if autoSyncSettings and currentTargetObj then
                    local b = beeMapById[currentTargetObj.beeId]
                    local r = b and b.rarity or "Mythic"
                    if r == "Mythic" then
                        setBSSSetting("RollToMythic", true)
                        setBSSSetting("RollToLegendary", false)
                    elseif r == "Legendary" then
                        setBSSSetting("RollToLegendary", true)
                        setBSSSetting("RollToMythic", true)
                    else
                        setBSSSetting("RollToLegendary", false)
                        setBSSSetting("RollToMythic", false)
                    end
                    if currentTargetObj.gifted == "Gifted" then
                        setBSSSetting("UntilGifted", true)
                    end
                end

                local data = getStatData()
                local currentRJ = getRoyalJellies(data)

                if currentRJ < minRJThreshold and autoBuyRJ then
                    rollStatusParagraph:SetDesc("Moving to Royal Jelly Shop...")
                    local rjShopPos = getRJShopPos()
                    if ensureAtPos(rjShopPos, 20) then
                        task.wait(0.5)
                        if not autoRollRunning or not isScriptRunning then return end
                        rollStatusParagraph:SetDesc(string.format("Buying %s Royal Jellies...", formatNum(buyRJAmount)))
                        buyRoyalJellies(buyRJAmount)
                        task.wait(0.5)
                        if not autoRollRunning or not isScriptRunning then return end
                        data = getStatData()
                        currentRJ = getRoyalJellies(data)
                    else
                        return
                    end
                end

                if currentRJ <= 0 then
                    rollStatusParagraph:SetDesc("Out of Royal Jellies! Stopped.")
                    stopAutoRoll()
                    return
                end

                if not ensureAtHive() then
                    rollStatusParagraph:SetDesc("Moving to Hive platform...")
                    return
                end
                task.wait(0.5)
                if not autoRollRunning or not isScriptRunning then return end

                local rollBatch = math.min(currentRJ, 25000)
                local okR, res = rollBee(nextTargetSlot.col, nextTargetSlot.row, rollBatch)
                if not okR then
                    consecutiveRollFails = consecutiveRollFails + 1
                    if consecutiveRollFails >= 5 then
                        rollStatusParagraph:SetDesc("Roll remote failed 5 times! Stopped.")
                        stopAutoRoll()
                        return
                    end
                    rollStatusParagraph:SetDesc(string.format("Roll remote failed (%d/5)! Retrying...", consecutiveRollFails))
                    task.wait(1)
                    return
                else
                    consecutiveRollFails = 0
                end

                task.wait(1)
                if not autoRollRunning or not isScriptRunning then return end

                local refreshedGrid = getAllHiveCells(true)
                local newCell = refreshedGrid[nextTargetSlot.row] and refreshedGrid[nextTargetSlot.row][nextTargetSlot.col]
                local newType = newCell and newCell.beeType or "Unknown"

                if currentBuildMode == "Exact" then
                    if checkCellMatchesTarget(newCell, currentTargetObj) then
                        WindUI:Notify({
                            Title = "Exact Target Reached!",
                            Content = string.format("Slot %s is now %s (%s)!", tostring(nextTargetSlot.key), tostring(newType), (newCell and newCell.gifted) and "Gifted" or "Normal"),
                            Duration = 4
                        })
                        refreshHiveGrid()
                    end
                else
                    for _, item in ipairs(compositionTargets) do
                        if checkCellMatchesTarget(newCell, item) then
                            WindUI:Notify({
                                Title = "Quota Bee Obtained!",
                                Content = string.format("Obtained %s (%s) in slot %s!", tostring(newType), (newCell and newCell.gifted) and "Gifted" or "Normal", tostring(nextTargetSlot.key)),
                                Duration = 4
                            })
                            refreshHiveGrid()
                            break
                        end
                    end
                end
            end)
            if not ok then warn("[AutoRoll] Error: " .. tostring(err)) end
        end
        task.wait(1)
    end
end)

refreshHiveGrid()
WindUI:Notify({ Title = "Ivyis's Tool", Content = "Loaded successfully!", Duration = 3 })

if getgenv then
    getgenv()._AutoFeedCleanup = function()
        isScriptRunning = false
        autoRunning = false
        autoRollRunning = false
        if setAtlasStopEverything then pcall(function() setAtlasStopEverything(false) end) end
        if activeTween then pcall(function() activeTween:Cancel() end) activeTween = nil end
        if antiAfkConn then pcall(function() antiAfkConn:Disconnect() end) antiAfkConn = nil end
        for _, c in ipairs(scriptConnections) do
            pcall(function() c:Disconnect() end)
        end
        table.clear(scriptConnections)
        pcall(function()
            if Window and Window.Destroy then
                task.spawn(function() pcall(function() Window:Destroy() end) end)
            end
        end)
        cleanupOldInstances(CoreGui)
        if gethui then cleanupOldInstances(gethui()) end
        cleanupOldInstances(player.PlayerGui)
    end
end


