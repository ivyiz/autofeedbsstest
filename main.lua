local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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

local TREAT_SHOP_POS = CFrame.new(-220.1, 5.8, 84.5)
local WALK_SPEED = 60
local TREAT_BOND = 10
local TREAT_COST = 10000
local autoRunning = false
local targetLevel = 15
local isTweening = false

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

local function deriveLvlFromBond(totalBond)
    local curLvl = 1
    local remBond = totalBond
    for l = 1, 25 do
        local req = bondTable[l] or (bondTable[25] * 2^(l - 25))
        if remBond >= req then
            remBond = remBond - req
            curLvl = l + 1
        else
            break
        end
    end
    return curLvl, remBond
end

local function getCumulativeBond(targetLvl)
    local sum = 0
    for l = 1, targetLvl - 1 do
        sum = sum + (bondTable[l] or (bondTable[25] * 2^(l - 25)))
    end
    return sum
end

local function extractBee(b)
    if type(b) ~= "table" then return nil end
    local lvl = nil
    local bond = nil
    local name = nil
    local row = nil
    local col = nil

    local function scanTable(t)
        if type(t) ~= "table" then return end
        for k, v in pairs(t) do
            local lk = tostring(k):lower()
            if not lvl and (lk == "level" or lk == "lvl" or lk:find("level") or lk:find("lvl") or lk == "rank") then
                if type(v) == "number" or (type(v) == "string" and tonumber(v)) then
                    lvl = tonumber(v)
                end
            elseif not bond and (lk == "bond" or lk == "xp" or lk:find("bond") or lk:find("xp")) then
                if type(v) == "number" or (type(v) == "string" and tonumber(v)) then
                    bond = tonumber(v)
                end
            elseif not name and (lk == "type" or lk == "beetype" or lk == "name" or lk:find("type") or lk:find("species")) then
                if type(v) == "string" then
                    name = tostring(v)
                end
            elseif not row and (lk == "row" or lk == "x" or lk == "line") then
                if type(v) == "number" or (type(v) == "string" and tonumber(v)) then
                    row = tonumber(v)
                end
            elseif not col and (lk == "col" or lk == "column" or lk == "y") then
                if type(v) == "number" or (type(v) == "string" and tonumber(v)) then
                    col = tonumber(v)
                end
            end
        end
    end

    scanTable(b)
    if type(b.Properties) == "table" then scanTable(b.Properties) end
    if type(b.Stats) == "table" then scanTable(b.Stats) end
    if type(b.Data) == "table" then scanTable(b.Data) end

    bond = tonumber(bond) or 0
    if lvl then lvl = tonumber(lvl) end

    if (not lvl or lvl <= 1) and bond >= 1000 then
        local calcLvl, calcBond = deriveLvlFromBond(bond)
        lvl = calcLvl
        bond = calcBond
    elseif lvl and lvl > 1 then
        local reqThisLvl = bondTable[lvl] or (bondTable[25] * 2^(lvl - 25))
        if bond >= reqThisLvl then
            local cum = getCumulativeBond(lvl)
            if bond >= cum then
                bond = math.max(0, bond - cum)
            end
            if bond >= reqThisLvl then
                local calcLvl, calcBond = deriveLvlFromBond(bond + cum)
                lvl = calcLvl
                bond = calcBond
            end
        end
    end

    if row and col then
        row, col = tonumber(row), tonumber(col)
        if row and col and row <= 5 and col > 5 then row, col = col, row end
    end

    if lvl or bond > 0 or name then
        return {
            Type = tostring(name or "Bee"),
            Level = math.max(1, math.floor(tonumber(lvl) or 1)),
            Bond = math.max(0, tonumber(bond) or 0),
            row = row,
            col = col
        }
    end
    return nil
end

local function getStatData()
    local data = nil
    pcall(function()
        local cache = RS:FindFirstChild("ClientStatCache")
        if cache then
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
    if type(data) == "table" then return data end

    pcall(function()
        local rf = getRemote("RetrievePlayerStats")
        if rf then data = callRemote(rf) end
    end)
    if type(data) == "table" then return data end

    pcall(function()
        local rf = getRemote("RetrievePlayerStatsSummary")
        if rf then data = callRemote(rf) end
    end)
    return (type(data) == "table") and data or nil
end

local function findBeesTable(data)
    if not data or type(data) ~= "table" then return nil end
    local candidate = data.Bees or data.bees or data.Hive or data.hive or data.HiveSlots or data.hiveSlots or data.Slots or data.slots
    if type(candidate) == "table" then
        local result = {}
        for k, v in pairs(candidate) do
            local b = extractBee(v)
            if b then result[tonumber(k) or k] = b end
        end
        if next(result) then return result end
    end
    for _, v in pairs(data) do
        if type(v) == "table" then
            local count = 0
            local result = {}
            for subK, subV in pairs(v) do
                local b = extractBee(subV)
                if b then
                    result[tonumber(subK) or subK] = b
                    count = count + 1
                end
            end
            if count >= 3 then
                return result
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

    if player:FindFirstChild("Honeycomb") and player.Honeycomb.Value then
        local hVal = player.Honeycomb.Value
        if typeof(hVal) == "Instance" then
            myHive = hVal
        else
            myHive = honeycombs:FindFirstChild(tostring(hVal))
        end
    end

    if not myHive then
        for _, hive in ipairs(honeycombs:GetChildren()) do
            local owner = hive:FindFirstChild("Owner")
            if owner then
                local val = owner.Value
                if val == player or val == player.Name or tostring(val) == player.Name or (player.Character and val == player.Character) then
                    myHive = hive
                    break
                end
            end
            if hive:GetAttribute("Owner") == player.Name then
                myHive = hive
                break
            end
        end
    end
    if not myHive then return nil end

    local cells = myHive:FindFirstChild("Cells") or myHive:FindFirstChild("cells")
    if cells then
        for i, cell in ipairs(cells:GetChildren()) do
            local cellType = cell:FindFirstChild("CellType") or cell:FindFirstChild("BeeType") or cell:FindFirstChild("Type")
            local typeName = (cellType and tostring(cellType.Value)) or cell:GetAttribute("CellType") or cell:GetAttribute("BeeType") or ""
            if typeName == "Empty" or typeName == "None" then continue end

            local lvl = nil
            local bond = 0

            for _, child in ipairs(cell:GetChildren()) do
                local lk = child.Name:lower()
                if child:IsA("ValueBase") then
                    if lk:find("level") or lk:find("lvl") then
                        lvl = tonumber(child.Value)
                    elseif lk:find("bond") or lk:find("xp") then
                        bond = tonumber(child.Value) or 0
                    end
                end
            end

            if not lvl then
                for k, v in pairs(cell:GetAttributes()) do
                    local lk = tostring(k):lower()
                    if lk:find("level") or lk:find("lvl") then
                        lvl = tonumber(v)
                    elseif lk:find("bond") or lk:find("xp") then
                        bond = tonumber(v) or 0
                    end
                end
            end

            if not lvl then
                local bestLevel = nil
                for _, desc in ipairs(cell:GetDescendants()) do
                    if desc:IsA("TextLabel") then
                        local txt = tostring(desc.Text or "")
                        local num = tonumber(txt:match("(%d+)"))
                        if num and num >= 1 and num <= 25 then
                            local dname = desc.Name:lower()
                            if dname:find("level") or dname:find("lvl") then
                                bestLevel = num
                                break
                            elseif not bestLevel and (txt:match("^%s*Lv?%.?%s*(%d+)%s*$") or #txt <= 3) then
                                bestLevel = num
                            end
                        end
                    end
                end
                lvl = bestLevel
            end

            local row, col = cell.Name:match("C(%d+),(%d+)")
            local slotIdx = i
            if row and col then
                row, col = tonumber(row), tonumber(col)
                if row <= 5 and col > 5 then row, col = col, row end
                slotIdx = (row - 1) * 5 + col
            else
                row = math.ceil(i / 5)
                col = i - (row - 1) * 5
                slotIdx = i
            end

            if (typeName ~= "" and typeName ~= "Empty" and typeName ~= "None") or lvl then
                bees[slotIdx] = {
                    Type = (typeName ~= "" and typeName ~= "Empty" and typeName ~= "None") and typeName or ("Slot"..slotIdx),
                    Level = lvl or 1,
                    Bond = bond or 0,
                    row = row,
                    col = col
                }
            end
        end
    end
    return next(bees) and bees or nil
end

local function getAllBees(data)
    local wsBees = getBeesFromWorkspace() or {}
    local cacheBees = findBeesTable(data) or {}
    local bees = {}
    for k, v in pairs(cacheBees) do
        local sk = tonumber(k) or k
        bees[sk] = v
        if type(sk) == "number" and (not v.row or not v.col) then
            v.row = math.ceil(sk / 5)
            v.col = sk - (v.row - 1) * 5
        end
    end
    for k, v in pairs(wsBees) do
        local sk = tonumber(k) or k
        if not bees[sk] then
            bees[sk] = v
        else
            if v.Level and v.Level > 1 and (not bees[sk].Level or bees[sk].Level <= 1 or v.Level > bees[sk].Level) then
                bees[sk].Level = v.Level
            end
            if v.Bond and v.Bond > 0 and (not bees[sk].Bond or bees[sk].Bond == 0) then
                bees[sk].Bond = v.Bond
            end
            if v.row and v.col then
                bees[sk].row = v.row
                bees[sk].col = v.col
            end
            if v.Type and v.Type ~= "" and not tostring(v.Type):find("^Slot") then
                bees[sk].Type = v.Type
            end
        end
    end
    return bees
end

local function getHoney(data)
    if not data then data = getStatData() end
    if data then
        if data.Honey then return tonumber(data.Honey) or 0 end
        if data.Totals and data.Totals.Honey then return tonumber(data.Totals.Honey) or 0 end
    end
    local s = player:FindFirstChild("leaderstats")
    if s and s:FindFirstChild("Honey") then
        return tonumber(s.Honey.Value) or 0
    end
    return 0
end

local function getTreats(data)
    if not data then data = getStatData() end
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

local function calcBeeTreats(currentLvl, currentBond, targetLvl)
    local lvl = math.max(1, math.floor(tonumber(currentLvl) or 1))
    local bond = math.max(0, tonumber(currentBond) or 0)
    local tgt = math.max(1, math.floor(tonumber(targetLvl) or 1))

    if lvl >= tgt then
        return 0, 100, 100, 0, 0
    end

    local needThisLvl = bondTable[lvl] or (bondTable[25] * 2^(lvl - 25))
    local lvlPct = math.min(100, math.floor((bond / needThisLvl) * 10000) / 100)
    local remThisLvl = math.max(0, needThisLvl - bond)

    local subBond = 0
    for l = lvl + 1, tgt - 1 do
        subBond = subBond + (bondTable[l] or (bondTable[25] * 2^(l - 25)))
    end

    local totalRemainingBond = remThisLvl + subBond
    local totalReq = needThisLvl + subBond
    local doneBond = totalReq - totalRemainingBond
    local totalPct = math.min(100, math.floor((doneBond / totalReq) * 10000) / 100)
    local treats = math.ceil(totalRemainingBond / TREAT_BOND)

    return treats, totalPct, lvlPct, totalRemainingBond, totalReq
end

local function slotToRowCol(slot)
    if type(slot) == "string" then
        local r, c = slot:match("(%d+)[^%d]+(%d+)")
        if r and c then
            local nr, nc = tonumber(r), tonumber(c)
            if nr <= 5 and nc > 5 then nr, nc = nc, nr end
            return nr, nc
        end
    end
    local s = tonumber(slot) or 1
    local row = math.ceil(s / 5)
    local col = s - (row - 1) * 5
    return row, col
end

local function getTreatShopCFrame()
    local toys = workspace:FindFirstChild("Toys")
    if toys then
        local shop = toys:FindFirstChild("Treat Shop") or toys:FindFirstChild("TreatShop") or toys:FindFirstChild("Treat Dispenser")
        if shop then
            if shop:IsA("Model") and shop.PrimaryPart then
                return shop.PrimaryPart.CFrame + Vector3.new(0, 3, 0)
            elseif shop:IsA("BasePart") then
                return shop.CFrame + Vector3.new(0, 3, 0)
            end
        end
    end
    return CFrame.new(-220.1, 7.5, 84.5)
end

local function buyTreats(amount)
    local remote = getRemote("ItemPackageEvent")
    if not remote or amount <= 0 then return false end
    local amt = math.floor(amount)
    local ok = pcall(function()
        callRemote(remote, "Purchase", {
            Type = "Treat",
            Amount = amt,
            Category = "Eggs"
        })
    end)
    if not ok then
        pcall(function()
            callRemote(remote, "Purchase", {
                Type = "Treat",
                Amount = amt
            })
        end)
    end
    return ok
end

local function feedBee(r, c, amount)
    local remote = getRemote("ConstructHiveCellFromEgg")
    if not remote or not r or not c or amount <= 0 then return false end
    local nr = tonumber(r)
    local nc = tonumber(c)
    local namt = math.floor(tonumber(amount) or 0)
    if not nr or not nc or namt <= 0 then return false end
    local ok = pcall(function()
        callRemote(remote, nr, nc, "Treat", namt)
    end)
    if not ok then
        pcall(function()
            callRemote(remote, nr, nc, "Treat", namt, false)
        end)
    end
    return ok
end

local function tweenTo(targetCF)
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
mainFrame.Size = UDim2.new(0, 240, 0, 195)
mainFrame.Position = UDim2.new(0.5, -120, 0.35, 0)
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
minBtn.ZIndex = 15
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

local bodyFrame = Instance.new("Frame")
bodyFrame.Size = UDim2.new(1, -16, 1, -34)
bodyFrame.Position = UDim2.new(0, 8, 0, 30)
bodyFrame.BackgroundTransparency = 1
bodyFrame.Parent = mainFrame

local targetRow = Instance.new("Frame")
targetRow.Size = UDim2.new(1, 0, 0, 22)
targetRow.Position = UDim2.new(0, 0, 0, 0)
targetRow.BackgroundTransparency = 1
targetRow.Parent = bodyFrame

local tgtTxt = Instance.new("TextLabel")
tgtTxt.Size = UDim2.new(0, 42, 1, 0)
tgtTxt.BackgroundTransparency = 1
tgtTxt.Text = "Target:"
tgtTxt.TextColor3 = Color3.fromRGB(180, 180, 180)
tgtTxt.Font = Enum.Font.Gotham
tgtTxt.TextSize = 11
tgtTxt.TextXAlignment = Enum.TextXAlignment.Left
tgtTxt.Parent = targetRow

local targetBox = Instance.new("TextBox")
targetBox.Size = UDim2.new(0, 48, 1, 0)
targetBox.Position = UDim2.new(0, 44, 0, 0)
targetBox.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
targetBox.Text = tostring(targetLevel)
targetBox.TextColor3 = Color3.fromRGB(240, 240, 240)
targetBox.Font = Enum.Font.GothamBold
targetBox.TextSize = 11
targetBox.BorderSizePixel = 0
targetBox.ClearTextOnFocus = false
targetBox.ZIndex = 15
targetBox.Parent = targetRow
Instance.new("UICorner", targetBox).CornerRadius = UDim.new(0, 4)

local spdTxt = Instance.new("TextLabel")
spdTxt.Size = UDim2.new(0, 42, 1, 0)
spdTxt.Position = UDim2.new(0, 102, 0, 0)
spdTxt.BackgroundTransparency = 1
spdTxt.Text = "Speed:"
spdTxt.TextColor3 = Color3.fromRGB(180, 180, 180)
spdTxt.Font = Enum.Font.Gotham
spdTxt.TextSize = 11
spdTxt.TextXAlignment = Enum.TextXAlignment.Left
spdTxt.Parent = targetRow

local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.new(0, 48, 1, 0)
speedBox.Position = UDim2.new(0, 146, 0, 0)
speedBox.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
speedBox.Text = tostring(WALK_SPEED)
speedBox.TextColor3 = Color3.fromRGB(240, 240, 240)
speedBox.Font = Enum.Font.GothamBold
speedBox.TextSize = 11
speedBox.BorderSizePixel = 0
speedBox.ClearTextOnFocus = false
speedBox.ZIndex = 15
speedBox.Parent = targetRow
Instance.new("UICorner", speedBox).CornerRadius = UDim.new(0, 4)

local function makeInfoLabel(yPos)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 16)
    l.Position = UDim2.new(0, 0, 0, yPos)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(180, 180, 180)
    l.Font = Enum.Font.Gotham
    l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = bodyFrame
    return l
end

local beeCountLabel = makeInfoLabel(24)
beeCountLabel.Text = "Bees: 0"
local honeyLabel = makeInfoLabel(40)
honeyLabel.Text = "Honey: 0"
local treatsLabel = makeInfoLabel(56)
treatsLabel.Text = "Treats: 0"
local totalTreatsLabel = makeInfoLabel(72)
totalTreatsLabel.Text = "Treats Needed: 0"
local totalHoneyLabel = makeInfoLabel(88)
totalHoneyLabel.Text = "Honey Needed: 0"
local overallLabel = makeInfoLabel(104)
overallLabel.Text = "Overall: 0%"

local btnRow = Instance.new("Frame")
btnRow.Size = UDim2.new(1, 0, 0, 26)
btnRow.Position = UDim2.new(0, 0, 0, 126)
btnRow.BackgroundTransparency = 1
btnRow.Parent = bodyFrame

local calcBtn = Instance.new("TextButton")
calcBtn.Size = UDim2.new(0.48, 0, 1, 0)
calcBtn.Position = UDim2.new(0, 0, 0, 0)
calcBtn.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
calcBtn.Text = "Recalculate"
calcBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
calcBtn.Font = Enum.Font.GothamBold
calcBtn.TextSize = 11
calcBtn.BorderSizePixel = 0
calcBtn.Active = true
calcBtn.Selectable = true
calcBtn.ZIndex = 15
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
toggleBtn.Active = true
toggleBtn.Selectable = true
toggleBtn.ZIndex = 15
toggleBtn.Parent = btnRow
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 4)

local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        mainFrame.Size = UDim2.new(0, 240, 0, 28)
        minBtn.Text = "+"
        bodyFrame.Visible = false
    else
        mainFrame.Size = UDim2.new(0, 240, 0, 195)
        minBtn.Text = "—"
        bodyFrame.Visible = true
    end
end)

local isRefreshing = false

local function refreshBeeList()
    if isRefreshing then return end
    isRefreshing = true
    pcall(function()
        calcBtn.Text = "Updating..."

        local digits = string.match(tostring(targetBox.Text), "%d+")
        local val = digits and tonumber(digits)
        if val and val > 0 then targetLevel = math.floor(val) end
        targetBox.Text = tostring(targetLevel)

        local spdDigits = string.match(tostring(speedBox.Text), "%d+")
        local spd = spdDigits and tonumber(spdDigits)
        if spd and spd > 0 then WALK_SPEED = spd end
        speedBox.Text = tostring(WALK_SPEED)

        local data = getStatData()
        local bees = getAllBees(data)

        honeyLabel.Text = "Honey: " .. formatNum(getHoney(data))
        treatsLabel.Text = "Treats: " .. formatNum(getTreats(data))

        if not next(bees) then
            beeCountLabel.Text = "Bees: 0"
            totalTreatsLabel.Text = "Treats Needed: 0"
            totalHoneyLabel.Text = "Honey Needed: 0"
            overallLabel.Text = "Overall: 0%"
            calcBtn.Text = "Recalculate"
            return
        end

        local beeCount, totalTreats = 0, 0
        local totalBondDone, totalBondReq = 0, 0

        for slot, bee in pairs(bees) do
            local b = extractBee(bee) or bee
            if type(b) == "table" then
                local lvl = math.max(1, math.floor(tonumber(b.Level) or 1))
                local bond = math.max(0, tonumber(b.Bond) or 0)
                beeCount = beeCount + 1

                local treats, totalPct, lvlPct, remBond, reqBond = calcBeeTreats(lvl, bond, targetLevel)
                totalTreats = totalTreats + treats
                totalBondReq = totalBondReq + reqBond
                totalBondDone = totalBondDone + (reqBond - remBond)
            end
        end

        local overall = totalBondReq > 0 and math.floor((totalBondDone / totalBondReq) * 10000) / 100 or 100
        beeCountLabel.Text = "Bees: " .. beeCount
        overallLabel.Text = "Overall: " .. overall .. "%"
        totalTreatsLabel.Text = "Treats Needed: " .. formatNum(totalTreats)
        totalHoneyLabel.Text = "Honey Needed: " .. formatNum(totalTreats * TREAT_COST)
    end)
    calcBtn.Text = "Recalculate"
    isRefreshing = false
end

calcBtn.MouseButton1Click:Connect(refreshBeeList)
calcBtn.Activated:Connect(refreshBeeList)
targetBox.FocusLost:Connect(refreshBeeList)
speedBox.FocusLost:Connect(refreshBeeList)

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
toggleBtn.Activated:Connect(function()
    if not autoRunning then
        toggleBtn.Text = "Auto: ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(20, 42, 24)
        autoRunning = true
    else
        toggleBtn.Text = "Auto: OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(42, 20, 20)
        autoRunning = false
        isTweening = false
    end
end)

spawn(function()
    while screenGui.Parent do
        if autoRunning then
            local data = getStatData()
            local bees = getAllBees(data)

            if next(bees) then
                local totalNeeded = 0
                for _, bee in pairs(bees) do
                    local b = extractBee(bee) or bee
                    if type(b) == "table" then
                        local lvl = math.max(1, math.floor(tonumber(b.Level) or 1))
                        local bond = math.max(0, tonumber(b.Bond) or 0)
                        if lvl < targetLevel then
                            local treats = calcBeeTreats(lvl, bond, targetLevel)
                            totalNeeded = totalNeeded + treats
                        end
                    end
                end

                local owned = getTreats(data)
                local honey = getHoney(data)
                if owned < totalNeeded and honey >= TREAT_COST then
                    local maxCanBuy = math.floor(honey / TREAT_COST)
                    local toBuy = math.min(totalNeeded - owned, maxCanBuy)
                    if toBuy > 0 then
                        local char = player.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        local savedPos = root and root.CFrame
                        local arrived = tweenTo(getTreatShopCFrame())
                        if arrived and autoRunning then
                            wait(0.5)
                            buyTreats(toBuy)
                            wait(0.8)
                            if savedPos then tweenTo(savedPos) end
                        end
                    end
                end

                data = getStatData() or data
                local availableTreats = getTreats(data)
                if availableTreats > 0 then
                    for slot, bee in pairs(bees) do
                        if not autoRunning or availableTreats <= 0 then break end
                        local b = extractBee(bee) or bee
                        if type(b) == "table" then
                            local lvl = math.max(1, math.floor(tonumber(b.Level) or 1))
                            local bond = math.max(0, tonumber(b.Bond) or 0)
                            if lvl < targetLevel then
                                local treatsNeeded = calcBeeTreats(lvl, bond, targetLevel)
                                local toFeed = math.min(treatsNeeded, availableTreats)
                                if toFeed > 0 then
                                    local r = b.row or slotToRowCol(slot)
                                    local c = b.col
                                    if not c then
                                        local _, nc = slotToRowCol(slot)
                                        c = nc
                                    end
                                    feedBee(r, c, toFeed)
                                    availableTreats = availableTreats - toFeed
                                    wait(0.3)
                                end
                            end
                        end
                    end
                end
                refreshBeeList()
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
