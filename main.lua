local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Events = RS:WaitForChild("Events")
local guiParent = (pcall(function() return CoreGui.Name end) and CoreGui) or player:WaitForChild("PlayerGui")

if guiParent:FindFirstChild("BSS_Final") then guiParent.BSS_Final:Destroy() end

local TREAT_SHOP_POS = CFrame.new(-220.1, 5.8, 84.5)
local WALK_SPEED = 60
local TREAT_BOND = 10
local TREAT_COST = 10000
local autoRunning = false
local targetLevel = 15
local isTweening = false

local ItemPackageEvent = Events:WaitForChild("ItemPackageEvent")
local ConstructHiveCellFromEgg = Events:WaitForChild("ConstructHiveCellFromEgg")

local bondTable = {
    [1]=1000,[2]=5000,[3]=25000,[4]=100000,[5]=400000,
    [6]=1500000,[7]=5000000,[8]=25000000,[9]=100000000,[10]=250000000,
    [11]=500000000,[12]=1000000000,[13]=2500000000,[14]=5000000000,[15]=12500000000,
    [16]=25000000000,[17]=50000000000,[18]=100000000000,[19]=250000000000,[20]=500000000000,
    [21]=1000000000000,[22]=2500000000000,[23]=5000000000000,
    [24]=10000000000000,[25]=25000000000000
}

local function formatNum(n)
    if n >= 1e12 then return string.format("%.2fT", n/1e12)
    elseif n >= 1e9 then return string.format("%.2fB", n/1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n/1e6)
    elseif n >= 1e3 then return string.format("%.1fK", n/1e3)
    else return tostring(math.floor(n)) end
end

local function getStatData()
    local ok, data = pcall(function() return require(RS.ClientStatCache):Get() end)
    return (ok and type(data) == "table") and data or nil
end

local function getHoney(data)
    if data and data.Honey then return data.Honey end
    local s = player:FindFirstChild("leaderstats")
    return (s and s:FindFirstChild("Honey") and s.Honey.Value) or 0
end

local function getTreats(data)
    return (data and data.Inventory and data.Inventory.Treat) or 0
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
    local row = math.ceil(slot / 10)
    local col = slot - (row - 1) * 10
    return row, col
end

local function buyTreats(amount)
    pcall(function()
        ItemPackageEvent:InvokeServer("Purchase", {
            Type = "Treat", Amount = amount, Category = "Eggs"
        })
    end)
end

local function feedBee(slot, amount)
    local row, col = slotToRowCol(slot)
    pcall(function()
        ConstructHiveCellFromEgg:InvokeServer(row, col, "Treat", amount, false)
    end)
end

local function tweenTo(targetCF, statusLabel)
    local char = player.Character
    if not char then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local dist = (root.Position - targetCF.Position).Magnitude
    if dist < 5 then return true end
    local duration = dist / WALK_SPEED
    isTweening = true
    local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = targetCF})
    local humanoid = char:FindFirstChildWhichIsA("Humanoid")
    if humanoid then humanoid.WalkSpeed = 0 end
    local done = false
    tween:Play()
    tween.Completed:Connect(function() done = true end)
    while not done and isTweening and autoRunning do wait(0.1) end
    if not done then tween:Cancel() end
    if humanoid then humanoid.WalkSpeed = 16 end
    isTweening = false
    return done
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BSS_Final"
screenGui.ResetOnSpawn = false
screenGui.Parent = guiParent

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 380, 0, 490)
mainFrame.Position = UDim2.new(0.5, -190, 0.3, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -40, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "BSS Auto Treat"
titleLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 13
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 26, 0, 24)
minBtn.Position = UDim2.new(1, -32, 0, 6)
minBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 12
minBtn.BorderSizePixel = 0
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

local function makeLabel(text, yPos)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -24, 0, 22)
    l.Position = UDim2.new(0, 12, 0, yPos)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Color3.fromRGB(190, 190, 190)
    l.Font = Enum.Font.Gotham
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = mainFrame
    return l
end

local beeCountLabel = makeLabel("Bees: 0", 44)
local honeyLabel = makeLabel("Honey: 0", 66)
local treatsLabel = makeLabel("Treats: 0", 88)
local overallLabel = makeLabel("Overall: 0%", 110)

local targetFrame = Instance.new("Frame")
targetFrame.Size = UDim2.new(1, -24, 0, 28)
targetFrame.Position = UDim2.new(0, 12, 0, 140)
targetFrame.BackgroundTransparency = 1
targetFrame.Parent = mainFrame

local tgtTxt = Instance.new("TextLabel")
tgtTxt.Size = UDim2.new(0, 90, 1, 0)
tgtTxt.BackgroundTransparency = 1
tgtTxt.Text = "Target Level:"
tgtTxt.TextColor3 = Color3.fromRGB(190, 190, 190)
tgtTxt.Font = Enum.Font.Gotham
tgtTxt.TextSize = 12
tgtTxt.TextXAlignment = Enum.TextXAlignment.Left
tgtTxt.Parent = targetFrame

local targetBox = Instance.new("TextBox")
targetBox.Size = UDim2.new(0, 50, 1, 0)
targetBox.Position = UDim2.new(0, 95, 0, 0)
targetBox.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
targetBox.Text = tostring(targetLevel)
targetBox.TextColor3 = Color3.fromRGB(240, 240, 240)
targetBox.Font = Enum.Font.GothamBold
targetBox.TextSize = 13
targetBox.BorderSizePixel = 0
targetBox.ClearTextOnFocus = false
targetBox.Parent = targetFrame
Instance.new("UICorner", targetBox).CornerRadius = UDim.new(0, 4)

local spdTxt = Instance.new("TextLabel")
spdTxt.Size = UDim2.new(0, 60, 1, 0)
spdTxt.Position = UDim2.new(0, 158, 0, 0)
spdTxt.BackgroundTransparency = 1
spdTxt.Text = "Speed:"
spdTxt.TextColor3 = Color3.fromRGB(190, 190, 190)
spdTxt.Font = Enum.Font.Gotham
spdTxt.TextSize = 12
spdTxt.TextXAlignment = Enum.TextXAlignment.Left
spdTxt.Parent = targetFrame

local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.new(0, 50, 1, 0)
speedBox.Position = UDim2.new(0, 215, 0, 0)
speedBox.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
speedBox.Text = tostring(WALK_SPEED)
speedBox.TextColor3 = Color3.fromRGB(240, 240, 240)
speedBox.Font = Enum.Font.GothamBold
speedBox.TextSize = 13
speedBox.BorderSizePixel = 0
speedBox.ClearTextOnFocus = false
speedBox.Parent = targetFrame
Instance.new("UICorner", speedBox).CornerRadius = UDim.new(0, 4)

local totalTreatsLabel = makeLabel("Treats Needed: 0", 176)
local totalHoneyLabel = makeLabel("Honey Needed: 0", 198)

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -24, 0, 150)
scrollFrame.Position = UDim2.new(0, 12, 0, 226)
scrollFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 16)
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 3
scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60)
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.Parent = mainFrame
Instance.new("UICorner", scrollFrame).CornerRadius = UDim.new(0, 6)
Instance.new("UIListLayout", scrollFrame).Padding = UDim.new(0, 2)

local statusLabel = makeLabel("Status: Idle", 384)
statusLabel.TextColor3 = Color3.fromRGB(160, 160, 160)

local function makeBtn(text, yPos, color)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -24, 0, 34)
    btn.Position = UDim2.new(0, 12, 0, yPos)
    btn.BackgroundColor3 = color
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(230, 230, 230)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.BorderSizePixel = 0
    btn.Parent = mainFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

local calcBtn = makeBtn("Recalculate", 410, Color3.fromRGB(26, 26, 26))
local toggleBtn = makeBtn("Auto: OFF", 450, Color3.fromRGB(42, 20, 20))

local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        mainFrame.Size = UDim2.new(0, 380, 0, 36)
        minBtn.Text = "+"
    else
        mainFrame.Size = UDim2.new(0, 380, 0, 490)
        minBtn.Text = "—"
    end
    for _, obj in pairs(mainFrame:GetChildren()) do
        if obj ~= titleBar and not obj:IsA("UICorner") then
            obj.Visible = not isMinimized
        end
    end
end)

local function refreshBeeList()
    for _, c in pairs(scrollFrame:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    local val = tonumber(targetBox.Text)
    if val and val > 0 then targetLevel = math.floor(val) end
    local spd = tonumber(speedBox.Text)
    if spd and spd > 0 then WALK_SPEED = spd end

    local data = getStatData()
    if not data or not data.Bees then return end

    local beeCount, totalTreats = 0, 0
    local totalBondDone, totalBondReq = 0, 0
    local beeList = {}

    for slot, bee in pairs(data.Bees) do
        if type(bee) == "table" and bee.Level then
            beeCount = beeCount + 1
            local pct, rem = getBondProgress(bee.Level, bee.Bond or 0, targetLevel)
            local lvlPct = getLvlPct(bee.Level, bee.Bond or 0)
            local treats = math.ceil(rem / TREAT_BOND)
            totalTreats = totalTreats + treats
            local bondNeeded = 0
            for i = bee.Level, targetLevel - 1 do
                bondNeeded = bondNeeded + (bondTable[i] or bondTable[25]*2^(i-25))
            end
            totalBondDone = totalBondDone + (bondNeeded - rem)
            totalBondReq = totalBondReq + bondNeeded
            table.insert(beeList, {
                slot=slot, name=bee.Type or ("Slot"..slot),
                lvl=bee.Level, lvlPct=lvlPct, pct=pct, treats=treats
            })
        end
    end

    table.sort(beeList, function(a,b) return a.lvl < b.lvl end)

    for i, info in ipairs(beeList) do
        local done = info.pct >= 100
        local row = Instance.new("TextLabel")
        row.Size = UDim2.new(1, -8, 0, 18)
        row.BackgroundTransparency = 1
        row.Text = string.format(" %s Lv%d(%.0f%%) -> Lv%d [%.1f%%] %s",
            info.name, info.lvl, info.lvlPct, targetLevel,
            info.pct, done and "[DONE]" or (formatNum(info.treats) .. " Treats"))
        row.TextColor3 = done and Color3.fromRGB(120, 200, 120) or Color3.fromRGB(180, 180, 180)
        row.Font = Enum.Font.Gotham
        row.TextSize = 11
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.LayoutOrder = i
        row.Parent = scrollFrame
    end

    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #beeList * 20)
    local overall = totalBondReq > 0 and math.floor((totalBondDone/totalBondReq)*10000)/100 or 100
    beeCountLabel.Text = "Bees: " .. beeCount
    honeyLabel.Text = "Honey: " .. formatNum(getHoney(data))
    treatsLabel.Text = "Treats: " .. formatNum(getTreats(data))
    overallLabel.Text = "Overall: " .. overall .. "%"
    totalTreatsLabel.Text = "Treats Needed: " .. formatNum(totalTreats)
    totalHoneyLabel.Text = "Honey Needed: " .. formatNum(totalTreats * TREAT_COST)
end

calcBtn.MouseButton1Click:Connect(refreshBeeList)
targetBox.FocusLost:Connect(refreshBeeList)
speedBox.FocusLost:Connect(function()
    local spd = tonumber(speedBox.Text)
    if spd and spd > 0 then WALK_SPEED = spd end
end)

toggleBtn.MouseButton1Click:Connect(function()
    autoRunning = not autoRunning
    if autoRunning then
        toggleBtn.Text = "Auto: ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(20, 42, 24)
    else
        toggleBtn.Text = "Auto: OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(42, 20, 20)
        isTweening = false
    end
end)

spawn(function()
    while screenGui.Parent do
        if autoRunning then
            local data = getStatData()
            if data and data.Bees then
                local totalNeeded = 0
                for _, bee in pairs(data.Bees) do
                    if type(bee) == "table" and bee.Level and bee.Level < targetLevel then
                        local _, rem = getBondProgress(bee.Level, bee.Bond or 0, targetLevel)
                        totalNeeded = totalNeeded + math.ceil(rem / TREAT_BOND)
                    end
                end

                local owned = getTreats(data)
                if owned < totalNeeded then
                    local char = player.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    local savedPos = root and root.CFrame
                    statusLabel.Text = "Status: Moving to shop..."
                    local arrived = tweenTo(TREAT_SHOP_POS, statusLabel)
                    if arrived and autoRunning then
                        statusLabel.Text = "Status: Buying treats..."
                        wait(0.5)
                        buyTreats(totalNeeded - owned)
                        wait(0.8)
                        statusLabel.Text = "Status: Returning..."
                        if savedPos then tweenTo(savedPos, statusLabel) end
                    end
                end

                if autoRunning then
                    statusLabel.Text = "Status: Feeding bees..."
                    for slot, bee in pairs(data.Bees) do
                        if not autoRunning then break end
                        if type(bee) == "table" and bee.Level and bee.Level < targetLevel then
                            local _, rem = getBondProgress(bee.Level, bee.Bond or 0, targetLevel)
                            local treats = math.ceil(rem / TREAT_BOND)
                            if treats > 0 then
                                feedBee(slot, treats)
                                statusLabel.Text = "Status: Fed " .. (bee.Type or "bee") .. " " .. formatNum(treats)
                                wait(0.3)
                            end
                        end
                    end
                    refreshBeeList()
                    statusLabel.Text = "Status: Done, next in 3s..."
                end
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
