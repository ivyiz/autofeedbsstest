local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer

local guiParent
pcall(function()
    if gethui then
        guiParent = gethui()
    else
        local test = Instance.new("ScreenGui")
        test.Parent = CoreGui
        test:Destroy()
        guiParent = CoreGui
    end
end)
if not guiParent then
    guiParent = player:WaitForChild("PlayerGui")
end

pcall(function()
    if CoreGui:FindFirstChild("BSS_Final") then CoreGui.BSS_Final:Destroy() end
end)
pcall(function()
    if player.PlayerGui:FindFirstChild("BSS_Final") then player.PlayerGui.BSS_Final:Destroy() end
end)

local Events = RS:FindFirstChild("Events") or RS:WaitForChild("Events", 5)

local function getRemote(name)
    if Events and Events:FindFirstChild(name) then return Events[name] end
    for _, desc in ipairs(RS:GetDescendants()) do
        if desc.Name == name and (desc:IsA("RemoteFunction") or desc:IsA("RemoteEvent")) then
            return desc
        end
    end
    return nil
end

local TREAT_BOND = 10
local TREAT_COST = 10000
local autoRunning = false
local targetLevel = 15

local bondTable = {
    [1]=1000,[2]=5000,[3]=25000,[4]=100000,[5]=400000,
    [6]=1500000,[7]=5000000,[8]=25000000,[9]=100000000,[10]=250000000,
    [11]=500000000,[12]=1000000000,[13]=2500000000,[14]=5000000000,[15]=12500000000,
    [16]=25000000000,[17]=50000000000,[18]=100000000000,[19]=250000000000,[20]=500000000000,
    [21]=1000000000000,[22]=2500000000000,[23]=5000000000000,
    [24]=10000000000000,[25]=25000000000000
}

local function formatNum(n)
    if not n or n ~= n then return "0" end
    if n >= 1e12 then return string.format("%.2fT", n/1e12)
    elseif n >= 1e9 then return string.format("%.2fB", n/1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n/1e6)
    elseif n >= 1e3 then return string.format("%.1fK", n/1e3)
    else return tostring(math.floor(n)) end
end

local function getStatData()
    local data = nil
    pcall(function()
        local cache = RS:FindFirstChild("ClientStatCache")
        if cache then
            local mod = require(cache)
            if type(mod) == "table" and type(mod.Get) == "function" then
                data = mod:Get()
            end
        end
    end)
    if type(data) == "table" then return data end

    pcall(function()
        local rf = getRemote("RetrievePlayerStats")
        if rf then data = rf:InvokeServer() end
    end)
    if type(data) == "table" then return data end

    pcall(function()
        local rf = getRemote("RetrievePlayerStatsSummary")
        if rf then data = rf:InvokeServer() end
    end)
    return (type(data) == "table") and data or nil
end

local function findBeesTable(data)
    if not data or type(data) ~= "table" then return nil end
    if type(data.Bees) == "table" then return data.Bees end
    if type(data.Hive) == "table" then return data.Hive end
    if type(data.HiveSlots) == "table" then return data.HiveSlots end
    for _, v in pairs(data) do
        if type(v) == "table" then
            for _, subV in pairs(v) do
                if type(subV) == "table" and (subV.Level or subV.Bond) then
                    return v
                end
            end
        end
    end
    return nil
end

local function getBeesFromWorkspace()
    local bees = {}
    local honeycombs = workspace:FindFirstChild("Honeycombs")
    if not honeycombs then return nil end
    local myHive = nil
    for _, hive in ipairs(honeycombs:GetChildren()) do
        local owner = hive:FindFirstChild("Owner")
        if owner and (owner.Value == player or owner.Value == player.Name) then
            myHive = hive
            break
        end
    end
    if not myHive then return nil end
    local cells = myHive:FindFirstChild("Cells")
    if cells then
        for i, cell in ipairs(cells:GetChildren()) do
            local cellType = cell:FindFirstChild("CellType") or cell:FindFirstChild("BeeType") or cell:FindFirstChild("Type")
            local cellLevel = cell:FindFirstChild("CellLevel") or cell:FindFirstChild("Level")
            local cellBond = cell:FindFirstChild("Bond") or cell:FindFirstChild("CellBond")
            if cellType and cellType.Value and tostring(cellType.Value) ~= "" and tostring(cellType.Value) ~= "Empty" then
                bees[i] = {
                    Type = tostring(cellType.Value),
                    Level = cellLevel and tonumber(cellLevel.Value) or 1,
                    Bond = cellBond and tonumber(cellBond.Value) or 0
                }
            end
        end
    end
    return next(bees) and bees or nil
end

local function getHoney(data)
    if data and data.Honey then return data.Honey end
    local s = player:FindFirstChild("leaderstats")
    return (s and s:FindFirstChild("Honey") and s.Honey.Value) or 0
end

local function getTreats(data)
    if data then
        if data.Eggs and type(data.Eggs) == "table" and data.Eggs.Treat then
            return tonumber(data.Eggs.Treat) or 0
        end
        if data.Inventory and type(data.Inventory) == "table" and data.Inventory.Treat then
            return tonumber(data.Inventory.Treat) or 0
        end
        if data.Treats then return tonumber(data.Treats) or 0 end
        if data.Treat then return tonumber(data.Treat) or 0 end
    end
    return 0
end

local function getBondProgress(lvl, bond, tgt)
    local total = 0
    for i = lvl, tgt - 1 do
        total = total + (bondTable[i] or bondTable[25] * 2^(i-25))
    end
    if total <= 0 then return 100, 0 end
    local rem = math.max(0, total - (bond or 0))
    return math.floor(((total-rem)/total)*10000)/100, rem
end

local function getLvlPct(lvl, bond)
    local need = bondTable[lvl] or bondTable[25]*2^(lvl-25)
    return math.floor(((bond or 0)/need)*10000)/100
end

local function slotToRowCol(slot)
    local s = tonumber(slot) or 1
    local row = math.ceil(s / 10)
    local col = s - (row - 1) * 10
    return row, col
end

local function buyTreats(amount)
    local remote = getRemote("ItemPackageEvent")
    if not remote or amount <= 0 then return false end
    local ok = pcall(function()
        remote:InvokeServer("Purchase", {
            Type = "Treat",
            Amount = math.floor(amount),
            Category = "Eggs"
        })
    end)
    return ok
end

local function feedBee(slot, amount)
    local remote = getRemote("ConstructHiveCellFromEgg")
    if not remote or amount <= 0 then return false end
    local row, col = slotToRowCol(slot)
    local ok = pcall(function()
        remote:InvokeServer(row, col, "Treat", math.floor(amount), false)
    end)
    return ok
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BSS_Final"
screenGui.ResetOnSpawn = false
screenGui.Parent = guiParent

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 450, 0, 190)
mainFrame.Position = UDim2.new(0.5, -225, 0.35, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 28)
titleBar.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -36, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "BSS Auto Treat"
titleLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 12
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 22, 0, 20)
minBtn.Position = UDim2.new(1, -26, 0, 4)
minBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 12
minBtn.BorderSizePixel = 0
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

local bodyFrame = Instance.new("Frame")
bodyFrame.Size = UDim2.new(1, -16, 1, -34)
bodyFrame.Position = UDim2.new(0, 8, 0, 30)
bodyFrame.BackgroundTransparency = 1
bodyFrame.Parent = mainFrame

local leftCol = Instance.new("Frame")
leftCol.Size = UDim2.new(0, 210, 1, 0)
leftCol.Position = UDim2.new(0, 0, 0, 0)
leftCol.BackgroundTransparency = 1
leftCol.Parent = bodyFrame

local targetRow = Instance.new("Frame")
targetRow.Size = UDim2.new(1, 0, 0, 20)
targetRow.Position = UDim2.new(0, 0, 0, 0)
targetRow.BackgroundTransparency = 1
targetRow.Parent = leftCol

local tgtTxt = Instance.new("TextLabel")
tgtTxt.Size = UDim2.new(0, 80, 1, 0)
tgtTxt.BackgroundTransparency = 1
tgtTxt.Text = "Target Level:"
tgtTxt.TextColor3 = Color3.fromRGB(180, 180, 180)
tgtTxt.Font = Enum.Font.Gotham
tgtTxt.TextSize = 11
tgtTxt.TextXAlignment = Enum.TextXAlignment.Left
tgtTxt.Parent = targetRow

local targetBox = Instance.new("TextBox")
targetBox.Size = UDim2.new(0, 50, 1, 0)
targetBox.Position = UDim2.new(0, 82, 0, 0)
targetBox.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
targetBox.Text = tostring(targetLevel)
targetBox.TextColor3 = Color3.fromRGB(240, 240, 240)
targetBox.Font = Enum.Font.GothamBold
targetBox.TextSize = 11
targetBox.BorderSizePixel = 0
targetBox.ClearTextOnFocus = false
targetBox.Parent = targetRow
Instance.new("UICorner", targetBox).CornerRadius = UDim.new(0, 4)

local function makeInfoLabel(yPos)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 16)
    l.Position = UDim2.new(0, 0, 0, yPos)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(180, 180, 180)
    l.Font = Enum.Font.Gotham
    l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = leftCol
    return l
end

local beeCountLabel = makeInfoLabel(22)
beeCountLabel.Text = "Bees: 0"
local honeyLabel = makeInfoLabel(38)
honeyLabel.Text = "Honey: 0"
local treatsLabel = makeInfoLabel(54)
treatsLabel.Text = "Treats: 0"
local totalTreatsLabel = makeInfoLabel(70)
totalTreatsLabel.Text = "Treats Needed: 0"
local totalHoneyLabel = makeInfoLabel(86)
totalHoneyLabel.Text = "Honey Needed: 0"
local overallLabel = makeInfoLabel(102)
overallLabel.Text = "Overall: 0%"

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 15)
statusLabel.Position = UDim2.new(0, 0, 0, 118)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Status: Idle"
statusLabel.TextColor3 = Color3.fromRGB(140, 140, 140)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 10
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = leftCol

local btnRow = Instance.new("Frame")
btnRow.Size = UDim2.new(1, 0, 0, 22)
btnRow.Position = UDim2.new(0, 0, 0, 134)
btnRow.BackgroundTransparency = 1
btnRow.Parent = leftCol

local calcBtn = Instance.new("TextButton")
calcBtn.Size = UDim2.new(0.48, 0, 1, 0)
calcBtn.Position = UDim2.new(0, 0, 0, 0)
calcBtn.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
calcBtn.Text = "Recalculate"
calcBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
calcBtn.Font = Enum.Font.GothamBold
calcBtn.TextSize = 11
calcBtn.BorderSizePixel = 0
calcBtn.Parent = btnRow
Instance.new("UICorner", calcBtn).CornerRadius = UDim.new(0, 4)

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0.48, 0, 1, 0)
toggleBtn.Position = UDim2.new(0.52, 0, 0, 0)
toggleBtn.BackgroundColor3 = Color3.fromRGB(42, 20, 20)
toggleBtn.Text = "Auto: OFF"
toggleBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 11
toggleBtn.BorderSizePixel = 0
toggleBtn.Parent = btnRow
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 4)

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(0, 214, 1, 0)
scrollFrame.Position = UDim2.new(1, -214, 0, 0)
scrollFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 16)
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 3
scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60)
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.Parent = bodyFrame
Instance.new("UICorner", scrollFrame).CornerRadius = UDim.new(0, 6)
Instance.new("UIListLayout", scrollFrame).Padding = UDim.new(0, 2)

local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        mainFrame.Size = UDim2.new(0, 450, 0, 28)
        minBtn.Text = "+"
        bodyFrame.Visible = false
    else
        mainFrame.Size = UDim2.new(0, 450, 0, 190)
        minBtn.Text = "—"
        bodyFrame.Visible = true
    end
end)

local function refreshBeeList()
    for _, c in pairs(scrollFrame:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    local val = tonumber(targetBox.Text)
    if val and val > 0 then targetLevel = math.floor(val) end

    local data = getStatData()
    local bees = findBeesTable(data) or getBeesFromWorkspace()

    honeyLabel.Text = "Honey: " .. formatNum(getHoney(data))
    treatsLabel.Text = "Treats: " .. formatNum(getTreats(data))

    if not bees then
        beeCountLabel.Text = "Bees: 0"
        totalTreatsLabel.Text = "Treats Needed: 0"
        totalHoneyLabel.Text = "Honey Needed: 0"
        overallLabel.Text = "Overall: 0%"
        return
    end

    local beeCount, totalTreats = 0, 0
    local totalBondDone, totalBondReq = 0, 0
    local beeList = {}

    for slot, bee in pairs(bees) do
        if type(bee) == "table" and (bee.Level or bee.Bond) then
            beeCount = beeCount + 1
            local lvl = tonumber(bee.Level) or 1
            local bond = tonumber(bee.Bond) or 0
            local pct, rem = getBondProgress(lvl, bond, targetLevel)
            local lvlPct = getLvlPct(lvl, bond)
            local treats = math.ceil(rem / TREAT_BOND)
            totalTreats = totalTreats + treats
            local bondNeeded = 0
            for i = lvl, targetLevel - 1 do
                bondNeeded = bondNeeded + (bondTable[i] or bondTable[25]*2^(i-25))
            end
            totalBondDone = totalBondDone + (bondNeeded - rem)
            totalBondReq = totalBondReq + bondNeeded
            table.insert(beeList, {
                slot=slot, name=bee.Type or ("Slot"..slot),
                lvl=lvl, lvlPct=lvlPct, pct=pct, treats=treats
            })
        end
    end

    table.sort(beeList, function(a,b) return a.lvl < b.lvl end)

    for i, info in ipairs(beeList) do
        local done = info.pct >= 100
        local row = Instance.new("TextLabel")
        row.Size = UDim2.new(1, -6, 0, 16)
        row.BackgroundTransparency = 1
        row.Text = string.format(" %s Lv%d(%.0f%%) [%.0f%%] %s",
            info.name, info.lvl, info.lvlPct,
            info.pct, done and "[DONE]" or formatNum(info.treats))
        row.TextColor3 = done and Color3.fromRGB(120, 200, 120) or Color3.fromRGB(180, 180, 180)
        row.Font = Enum.Font.Gotham
        row.TextSize = 10
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.LayoutOrder = i
        row.Parent = scrollFrame
    end

    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #beeList * 18)
    local overall = totalBondReq > 0 and math.floor((totalBondDone/totalBondReq)*10000)/100 or 100
    beeCountLabel.Text = "Bees: " .. beeCount
    overallLabel.Text = "Overall: " .. overall .. "%"
    totalTreatsLabel.Text = "Treats Needed: " .. formatNum(totalTreats)
    totalHoneyLabel.Text = "Honey Needed: " .. formatNum(totalTreats * TREAT_COST)
end

calcBtn.MouseButton1Click:Connect(refreshBeeList)
targetBox.FocusLost:Connect(refreshBeeList)

toggleBtn.MouseButton1Click:Connect(function()
    autoRunning = not autoRunning
    if autoRunning then
        toggleBtn.Text = "Auto: ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(20, 42, 24)
    else
        toggleBtn.Text = "Auto: OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(42, 20, 20)
    end
end)

spawn(function()
    while screenGui.Parent do
        if autoRunning then
            local data = getStatData()
            local bees = findBeesTable(data) or getBeesFromWorkspace()
            if bees then
                local totalNeeded = 0
                for _, bee in pairs(bees) do
                    if type(bee) == "table" and (bee.Level or bee.Bond) then
                        local lvl = tonumber(bee.Level) or 1
                        if lvl < targetLevel then
                            local _, rem = getBondProgress(lvl, tonumber(bee.Bond) or 0, targetLevel)
                            totalNeeded = totalNeeded + math.ceil(rem / TREAT_BOND)
                        end
                    end
                end

                local owned = getTreats(data)
                local honey = getHoney(data)
                if owned < totalNeeded and honey >= TREAT_COST then
                    local maxCanBuy = math.floor(honey / TREAT_COST)
                    local toBuy = math.min(totalNeeded - owned, maxCanBuy)
                    if toBuy > 0 then
                        statusLabel.Text = "Status: Buying treats..."
                        buyTreats(toBuy)
                        wait(0.5)
                    end
                end

                data = getStatData() or data
                local availableTreats = getTreats(data)
                if availableTreats > 0 then
                    statusLabel.Text = "Status: Feeding bees..."
                    for slot, bee in pairs(bees) do
                        if not autoRunning or availableTreats <= 0 then break end
                        if type(bee) == "table" and (bee.Level or bee.Bond) then
                            local lvl = tonumber(bee.Level) or 1
                            if lvl < targetLevel then
                                local _, rem = getBondProgress(lvl, tonumber(bee.Bond) or 0, targetLevel)
                                local treatsNeeded = math.ceil(rem / TREAT_BOND)
                                local toFeed = math.min(treatsNeeded, availableTreats)
                                if toFeed > 0 then
                                    feedBee(slot, toFeed)
                                    availableTreats = availableTreats - toFeed
                                    statusLabel.Text = "Status: Fed " .. (bee.Type or "bee") .. " " .. formatNum(toFeed)
                                    wait(0.3)
                                end
                            end
                        end
                    end
                end
                refreshBeeList()
                statusLabel.Text = "Status: Idle"
            end
        end
        wait(3)
    end
end)

local dragging, dragStart, startPos
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

refreshBeeList()
