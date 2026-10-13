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
    if CoreGui:FindFirstChild("AutoTreat_ivyis") then CoreGui.AutoTreat_ivyis:Destroy() end
    if CoreGui:FindFirstChild("BSS_Final") then CoreGui.BSS_Final:Destroy() end
end)
pcall(function()
    if player.PlayerGui:FindFirstChild("AutoTreat_ivyis") then player.PlayerGui.AutoTreat_ivyis:Destroy() end
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
    [1] = 10,
    [2] = 40,
    [3] = 200,
    [4] = 750,
    [5] = 4000,
    [6] = 15000,
    [7] = 60000,
    [8] = 270000,
    [9] = 450000,
    [10] = 1200000,
    [11] = 2000000,
    [12] = 4000000,
    [13] = 7000000,
    [14] = 15000000,
    [15] = 120000000,
    [16] = 450000000,
    [17] = 1900000000,
    [18] = 7500000000,
    [19] = 15000000000,
    [20] = 475000000000,
    [21] = 4500000000000,
    [22] = 45000000000000,
    [23] = 450000000000000,
    [24] = 4500000000000000,
    [25] = 45000000000000000
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

    if (not lvl or lvl <= 1) and bond >= 10 then
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

    if name then
        local ln = name:lower():gsub("%s+", "")
        if ln == "empty" or ln == "none" or ln == "unbought" or ln == "locked" then
            return nil
        end
    end

    if (name and name ~= "") or (lvl and lvl >= 1) then
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
        local count = 0
        local result = {}
        for k, v in pairs(candidate) do
            local b = extractBee(v)
            if b then
                result[tonumber(k) or k] = b
                count = count + 1
            end
        end
        if count >= 20 then return result end
    end
    for k, v in pairs(data) do
        local lk = tostring(k):lower()
        if lk ~= "amulets" and lk ~= "eggs" and lk ~= "inventory" and lk ~= "badges" and lk ~= "accessories" and lk ~= "totals" and type(v) == "table" then
            local count = 0
            local result = {}
            for subK, subV in pairs(v) do
                local b = extractBee(subV)
                if b then
                    result[tonumber(subK) or subK] = b
                    count = count + 1
                end
            end
            if count >= 20 then
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
            if not cellType then
                for _, ch in ipairs(cell:GetChildren()) do
                    if ch:IsA("StringValue") and (ch.Name:lower():find("type") or ch.Name:lower():find("bee")) then
                        cellType = ch
                        break
                    end
                end
            end
            local typeName = (cellType and tostring(cellType.Value)) or cell:GetAttribute("CellType") or cell:GetAttribute("BeeType") or ""
            local lowerType = typeName:lower():gsub("%s+", "")
            if lowerType == "empty" or lowerType == "none" or lowerType == "unbought" or lowerType == "locked" then
                continue
            end

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
                        local txt = tostring(desc.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                        local dname = desc.Name:lower()
                        if dname:find("level") or dname:find("lvl") then
                            local num = tonumber(txt:match("(%d+)"))
                            if num and num >= 1 and num <= 25 then
                                bestLevel = num
                                break
                            end
                        else
                            local lvMatch = txt:match("^[Ll]?[Vv]?l?%.?%s*(%d+)$") or txt:match("^[Ll]evel%s*(%d+)$")
                            local num = tonumber(lvMatch)
                            if num and num >= 1 and num <= 25 then
                                bestLevel = num
                            end
                        end
                        if bond == 0 then
                            local b1 = txt:match("([%d,]+)%s*/%s*[%d,]+")
                            if b1 then
                                local bNum = tonumber(b1:gsub(",", ""))
                                if bNum and bNum > 0 then
                                    bond = bNum
                                end
                            end
                        end
                    elseif desc:IsA("ValueBase") then
                        local dname = desc.Name:lower()
                        if not bestLevel and (dname:find("level") or dname:find("lvl")) then
                            local n = tonumber(desc.Value)
                            if n and n >= 1 and n <= 25 then
                                bestLevel = n
                            end
                        elseif bond == 0 and (dname:find("bond") or dname:find("xp")) then
                            local b = tonumber(desc.Value)
                            if b and b > 0 then bond = b end
                        end
                    end
                end
                lvl = bestLevel
            end

            if lowerType == "" and (not lvl or lvl < 1) then
                continue
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

            bees[slotIdx] = {
                Type = (typeName ~= "" and typeName) or "Bee",
                Level = math.max(1, math.floor(lvl or 1)),
                Bond = math.max(0, bond or 0),
                row = row,
                col = col
            }
        end
    end
    return next(bees) and bees or nil
end

local function getAllBees(data)
    local wsBees = getBeesFromWorkspace() or {}
    local cacheBees = findBeesTable(data) or {}

    local wsCount = 0
    for _ in pairs(wsBees) do wsCount = wsCount + 1 end

    local cacheCount = 0
    for _ in pairs(cacheBees) do cacheCount = cacheCount + 1 end

    if wsCount >= 20 then
        if cacheCount >= 20 then
            for k, cb in pairs(cacheBees) do
                local sk = tonumber(k) or k
                if wsBees[sk] then
                    if cb.Bond and cb.Bond > 0 then
                        wsBees[sk].Bond = cb.Bond
                    end
                    if cb.Level and cb.Level > 1 then
                        wsBees[sk].Level = cb.Level
                    end
                    if cb.Type and cb.Type ~= "" and not tostring(cb.Type):find("^Slot") then
                        wsBees[sk].Type = cb.Type
                    end
                end
            end
        end
        return wsBees
    end

    if cacheCount >= 20 then
        for k, v in pairs(cacheBees) do
            local sk = tonumber(k) or k
            if type(sk) == "number" and (not v.row or not v.col) then
                v.row = math.ceil(sk / 5)
                v.col = sk - (v.row - 1) * 5
            end
        end
        return cacheBees
    end

    if wsCount > 0 then
        return wsBees
    end

    return cacheBees
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

local function autoDetectBFT(data, bees)
    local bft = 0

    pcall(function()
        local pg = player:FindFirstChild("PlayerGui")
        if pg then
            for _, desc in ipairs(pg:GetDescendants()) do
                if desc:IsA("TextLabel") then
                    local txt = tostring(desc.Text or ""):lower()
                    if txt:find("bond%s*from%s*treat") then
                        local pct = txt:match("%+?(%d+)%%") or txt:match("(%d+)")
                        local n = tonumber(pct)
                        if n then
                            if n > 100 then n = n - 100 end
                            if n > bft and n <= 100 then
                                bft = n
                            end
                        end
                    end
                end
            end
        end
    end)

    if bft > 0 then return bft end

    local hasGiftedPuppy = false
    if type(bees) == "table" then
        for _, b in pairs(bees) do
            local t = tostring(b.Type or ""):lower()
            if t:find("puppy") then
                if t:find("gifted") or b.Gifted or b.IsGifted then
                    hasGiftedPuppy = true
                    break
                end
                if b.row and b.col then
                    pcall(function()
                        local hVal = player:FindFirstChild("Honeycomb") and player.Honeycomb.Value
                        local honeycombs = workspace:FindFirstChild("Honeycombs")
                        local hive = (typeof(hVal) == "Instance" and hVal) or (honeycombs and honeycombs:FindFirstChild(tostring(hVal)))
                        if hive and hive:FindFirstChild("Cells") then
                            local cellName = "C" .. b.row .. "," .. b.col
                            local cell = hive.Cells:FindFirstChild(cellName)
                            if cell then
                                if cell:FindFirstChild("Gifted") or cell:GetAttribute("Gifted") then
                                    hasGiftedPuppy = true
                                else
                                    for _, desc in ipairs(cell:GetDescendants()) do
                                        local dn = desc.Name:lower()
                                        if dn:find("gifted") or dn:find("star") then
                                            hasGiftedPuppy = true
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end)
                end
                if hasGiftedPuppy then break end
            end
        end
    end
    if hasGiftedPuppy then
        bft = bft + 20
    end

    if type(data) == "table" then
        pcall(function()
            local amulets = data.Amulets or data.amulets
            if type(amulets) == "table" then
                for k, v in pairs(amulets) do
                    local lk = tostring(k):lower()
                    if lk:find("moon") or type(v) == "table" then
                        local targetTab = (type(v) == "table") and v or amulets
                        local function scanAmulet(tab)
                            for statK, statV in pairs(tab) do
                                local lsk = tostring(statK):lower()
                                if lsk:find("bond") and lsk:find("treat") then
                                    local num = tonumber(statV)
                                    if num then
                                        if num > 0 and num <= 1 then num = num * 100 end
                                        if num > 0 and num <= 50 then
                                            bft = bft + math.floor(num)
                                            return true
                                        end
                                    end
                                elseif type(statV) == "table" then
                                    if scanAmulet(statV) then return true end
                                end
                            end
                            return false
                        end
                        scanAmulet(targetTab)
                    end
                end
            end
        end)
    end

    return bft
end

local function calcBeeTreats(currentLvl, currentBond, targetLvl, bftBonus)
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

    local bonusPct = math.max(0, tonumber(bftBonus) or 0)
    local effectiveTreatBond = TREAT_BOND * (1 + bonusPct / 100)
    local treats = math.ceil(totalRemainingBond / effectiveTreatBond)

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
screenGui.Name = "AutoTreat_ivyis"
screenGui.ResetOnSpawn = false
screenGui.Parent = guiParent

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 480, 0, 310)
mainFrame.Position = UDim2.new(0.5, -240, 0.3, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = Color3.fromRGB(29, 56, 107)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

local barBottom = Instance.new("Frame")
barBottom.Size = UDim2.new(1, 0, 0, 8)
barBottom.Position = UDim2.new(0, 0, 1, -8)
barBottom.BackgroundColor3 = Color3.fromRGB(29, 56, 107)
barBottom.BorderSizePixel = 0
barBottom.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -60, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Auto Treat v1.0 by ivyis"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 13
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 22, 0, 20)
minBtn.Position = UDim2.new(1, -28, 0, 6)
minBtn.BackgroundColor3 = Color3.fromRGB(42, 70, 125)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 12
minBtn.BorderSizePixel = 0
minBtn.ZIndex = 15
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

local bodyFrame = Instance.new("Frame")
bodyFrame.Size = UDim2.new(1, 0, 1, -32)
bodyFrame.Position = UDim2.new(0, 0, 0, 32)
bodyFrame.BackgroundTransparency = 1
bodyFrame.Parent = mainFrame

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 130, 1, 0)
sidebar.Position = UDim2.new(0, 0, 0, 0)
sidebar.BackgroundColor3 = Color3.fromRGB(15, 16, 21)
sidebar.BorderSizePixel = 0
sidebar.Parent = bodyFrame

local sideBorder = Instance.new("Frame")
sideBorder.Size = UDim2.new(0, 1, 1, 0)
sideBorder.Position = UDim2.new(1, -1, 0, 0)
sideBorder.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
sideBorder.BorderSizePixel = 0
sideBorder.Parent = sidebar

local navLabel = Instance.new("TextLabel")
navLabel.Size = UDim2.new(1, -16, 0, 22)
navLabel.Position = UDim2.new(0, 10, 0, 8)
navLabel.BackgroundTransparency = 1
navLabel.Text = "NAVIGATION"
navLabel.TextColor3 = Color3.fromRGB(85, 93, 110)
navLabel.Font = Enum.Font.GothamBold
navLabel.TextSize = 10
navLabel.TextXAlignment = Enum.TextXAlignment.Left
navLabel.Parent = sidebar

local tabBtnAutoFeed = Instance.new("TextButton")
tabBtnAutoFeed.Size = UDim2.new(1, -16, 0, 32)
tabBtnAutoFeed.Position = UDim2.new(0, 8, 0, 34)
tabBtnAutoFeed.BackgroundColor3 = Color3.fromRGB(37, 72, 130)
tabBtnAutoFeed.Text = "🍯 Auto Feed"
tabBtnAutoFeed.TextColor3 = Color3.fromRGB(255, 255, 255)
tabBtnAutoFeed.Font = Enum.Font.GothamBold
tabBtnAutoFeed.TextSize = 11
tabBtnAutoFeed.TextXAlignment = Enum.TextXAlignment.Left
tabBtnAutoFeed.BorderSizePixel = 0
tabBtnAutoFeed.Parent = sidebar
Instance.new("UICorner", tabBtnAutoFeed).CornerRadius = UDim.new(0, 6)
local p1 = Instance.new("UIPadding", tabBtnAutoFeed); p1.PaddingLeft = UDim.new(0, 10)

local tabBtnSettings = Instance.new("TextButton")
tabBtnSettings.Size = UDim2.new(1, -16, 0, 32)
tabBtnSettings.Position = UDim2.new(0, 8, 0, 72)
tabBtnSettings.BackgroundColor3 = Color3.fromRGB(15, 16, 21)
tabBtnSettings.Text = "⚙️ Settings"
tabBtnSettings.TextColor3 = Color3.fromRGB(160, 165, 175)
tabBtnSettings.Font = Enum.Font.GothamBold
tabBtnSettings.TextSize = 11
tabBtnSettings.TextXAlignment = Enum.TextXAlignment.Left
tabBtnSettings.BorderSizePixel = 0
tabBtnSettings.Parent = sidebar
Instance.new("UICorner", tabBtnSettings).CornerRadius = UDim.new(0, 6)
local p2 = Instance.new("UIPadding", tabBtnSettings); p2.PaddingLeft = UDim.new(0, 10)

local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -130, 1, 0)
contentArea.Position = UDim2.new(0, 130, 0, 0)
contentArea.BackgroundColor3 = Color3.fromRGB(20, 22, 29)
contentArea.BorderSizePixel = 0
contentArea.Parent = bodyFrame

local autoFeedPage = Instance.new("Frame")
autoFeedPage.Size = UDim2.new(1, 0, 1, 0)
autoFeedPage.BackgroundTransparency = 1
autoFeedPage.Visible = true
autoFeedPage.Parent = contentArea

local afHeader = Instance.new("Frame")
afHeader.Size = UDim2.new(1, -24, 0, 24)
afHeader.Position = UDim2.new(0, 12, 0, 6)
afHeader.BackgroundTransparency = 1
afHeader.Parent = autoFeedPage

local afTitle = Instance.new("TextLabel")
afTitle.Size = UDim2.new(0, 150, 1, 0)
afTitle.BackgroundTransparency = 1
afTitle.Text = "Treat Automation"
afTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
afTitle.Font = Enum.Font.GothamBold
afTitle.TextSize = 13
afTitle.TextXAlignment = Enum.TextXAlignment.Left
afTitle.Parent = afHeader

local afBadge = Instance.new("TextLabel")
afBadge.Size = UDim2.new(0, 76, 0, 18)
afBadge.Position = UDim2.new(1, -76, 0, 3)
afBadge.BackgroundColor3 = Color3.fromRGB(28, 54, 32)
afBadge.Text = "HIVE LINKED"
afBadge.TextColor3 = Color3.fromRGB(74, 222, 128)
afBadge.Font = Enum.Font.GothamBold
afBadge.TextSize = 9
afBadge.BorderSizePixel = 0
afBadge.Parent = afHeader
Instance.new("UICorner", afBadge).CornerRadius = UDim.new(0, 4)

local afCtrlRow = Instance.new("Frame")
afCtrlRow.Size = UDim2.new(1, -24, 0, 30)
afCtrlRow.Position = UDim2.new(0, 12, 0, 32)
afCtrlRow.BackgroundTransparency = 1
afCtrlRow.Parent = autoFeedPage

local targetCard = Instance.new("Frame")
targetCard.Size = UDim2.new(0.48, 0, 1, 0)
targetCard.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
targetCard.BorderSizePixel = 0
targetCard.Parent = afCtrlRow
Instance.new("UICorner", targetCard).CornerRadius = UDim.new(0, 6)

local targetLabel = Instance.new("TextLabel")
targetLabel.Size = UDim2.new(1, -50, 1, 0)
targetLabel.Position = UDim2.new(0, 8, 0, 0)
targetLabel.BackgroundTransparency = 1
targetLabel.Text = "Target Level:"
targetLabel.TextColor3 = Color3.fromRGB(200, 205, 215)
targetLabel.Font = Enum.Font.GothamBold
targetLabel.TextSize = 11
targetLabel.TextXAlignment = Enum.TextXAlignment.Left
targetLabel.Parent = targetCard

local targetBox = Instance.new("TextBox")
targetBox.Size = UDim2.new(0, 40, 0, 20)
targetBox.Position = UDim2.new(1, -46, 0.5, -10)
targetBox.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
targetBox.Text = tostring(targetLevel)
targetBox.TextColor3 = Color3.fromRGB(255, 255, 255)
targetBox.Font = Enum.Font.GothamBold
targetBox.TextSize = 11
targetBox.BorderSizePixel = 0
targetBox.ClearTextOnFocus = false
targetBox.Parent = targetCard
Instance.new("UICorner", targetBox).CornerRadius = UDim.new(0, 4)

local autoBuyCard = Instance.new("Frame")
autoBuyCard.Size = UDim2.new(0.48, 0, 1, 0)
autoBuyCard.Position = UDim2.new(0.52, 0, 0, 0)
autoBuyCard.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
autoBuyCard.BorderSizePixel = 0
autoBuyCard.Parent = afCtrlRow
Instance.new("UICorner", autoBuyCard).CornerRadius = UDim.new(0, 6)

local autoBuyLabel = Instance.new("TextLabel")
autoBuyLabel.Size = UDim2.new(1, -50, 1, 0)
autoBuyLabel.Position = UDim2.new(0, 8, 0, 0)
autoBuyLabel.BackgroundTransparency = 1
autoBuyLabel.Text = "Auto Buy Shop:"
autoBuyLabel.TextColor3 = Color3.fromRGB(200, 205, 215)
autoBuyLabel.Font = Enum.Font.GothamBold
autoBuyLabel.TextSize = 11
autoBuyLabel.TextXAlignment = Enum.TextXAlignment.Left
autoBuyLabel.Parent = autoBuyCard

local autoBuyEnabled = true
local autoBuyBtn = Instance.new("TextButton")
autoBuyBtn.Size = UDim2.new(0, 38, 0, 20)
autoBuyBtn.Position = UDim2.new(1, -44, 0.5, -10)
autoBuyBtn.BackgroundColor3 = Color3.fromRGB(28, 54, 32)
autoBuyBtn.Text = "ON"
autoBuyBtn.TextColor3 = Color3.fromRGB(74, 222, 128)
autoBuyBtn.Font = Enum.Font.GothamBold
autoBuyBtn.TextSize = 10
autoBuyBtn.BorderSizePixel = 0
autoBuyBtn.Parent = autoBuyCard
Instance.new("UICorner", autoBuyBtn).CornerRadius = UDim.new(0, 4)

autoBuyBtn.MouseButton1Click:Connect(function()
    autoBuyEnabled = not autoBuyEnabled
    if autoBuyEnabled then
        autoBuyBtn.Text = "ON"
        autoBuyBtn.BackgroundColor3 = Color3.fromRGB(28, 54, 32)
        autoBuyBtn.TextColor3 = Color3.fromRGB(74, 222, 128)
    else
        autoBuyBtn.Text = "OFF"
        autoBuyBtn.BackgroundColor3 = Color3.fromRGB(42, 20, 20)
        autoBuyBtn.TextColor3 = Color3.fromRGB(248, 113, 113)
    end
end)

local statsBox = Instance.new("Frame")
statsBox.Size = UDim2.new(1, -24, 0, 150)
statsBox.Position = UDim2.new(0, 12, 0, 68)
statsBox.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
statsBox.BorderSizePixel = 0
statsBox.Parent = autoFeedPage
Instance.new("UICorner", statsBox).CornerRadius = UDim.new(0, 6)

local function makeStatRow(yPos, labelTxt, defaultVal)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -16, 0, 16)
    row.Position = UDim2.new(0, 8, 0, yPos)
    row.BackgroundTransparency = 1
    row.Parent = statsBox

    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.6, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.Text = labelTxt
    l.TextColor3 = Color3.fromRGB(140, 149, 166)
    l.Font = Enum.Font.Gotham
    l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = row

    local v = Instance.new("TextLabel")
    v.Size = UDim2.new(0.4, 0, 1, 0)
    v.Position = UDim2.new(0.6, 0, 0, 0)
    v.BackgroundTransparency = 1
    v.Text = defaultVal
    v.TextColor3 = Color3.fromRGB(230, 235, 245)
    v.Font = Enum.Font.GothamBold
    v.TextSize = 11
    v.TextXAlignment = Enum.TextXAlignment.Right
    v.Parent = row
    return v
end

local beeCountLabel = makeStatRow(6, "Active Bees / Buff:", "Bees: 0")
local honeyLabel = makeStatRow(24, "Honey Available:", "0")
local treatsLabel = makeStatRow(42, "Treats Owned:", "0")
local totalTreatsLabel = makeStatRow(60, "Treats Needed:", "0")
local totalHoneyLabel = makeStatRow(78, "Honey Needed:", "0")
local overallLabel = makeStatRow(96, "Overall Progression:", "0%")

local progressBg = Instance.new("Frame")
progressBg.Size = UDim2.new(1, -16, 0, 6)
progressBg.Position = UDim2.new(0, 8, 0, 122)
progressBg.BackgroundColor3 = Color3.fromRGB(13, 15, 20)
progressBg.BorderSizePixel = 0
progressBg.Parent = statsBox
Instance.new("UICorner", progressBg).CornerRadius = UDim.new(0, 3)

local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = Color3.fromRGB(37, 72, 130)
progressFill.BorderSizePixel = 0
progressFill.Parent = progressBg
Instance.new("UICorner", progressFill).CornerRadius = UDim.new(0, 3)

local afActionRow = Instance.new("Frame")
afActionRow.Size = UDim2.new(1, -24, 0, 32)
afActionRow.Position = UDim2.new(0, 12, 1, -40)
afActionRow.BackgroundTransparency = 1
afActionRow.Parent = autoFeedPage

local calcBtn = Instance.new("TextButton")
calcBtn.Size = UDim2.new(0.48, 0, 1, 0)
calcBtn.Position = UDim2.new(0, 0, 0, 0)
calcBtn.BackgroundColor3 = Color3.fromRGB(37, 72, 130)
calcBtn.Text = "↻ Recalculate"
calcBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
calcBtn.Font = Enum.Font.GothamBold
calcBtn.TextSize = 11
calcBtn.BorderSizePixel = 0
calcBtn.Parent = afActionRow
Instance.new("UICorner", calcBtn).CornerRadius = UDim.new(0, 6)

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0.48, 0, 1, 0)
toggleBtn.Position = UDim2.new(0.52, 0, 0, 0)
toggleBtn.BackgroundColor3 = Color3.fromRGB(42, 20, 20)
toggleBtn.Text = "● Auto: OFF"
toggleBtn.TextColor3 = Color3.fromRGB(248, 113, 113)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 11
toggleBtn.BorderSizePixel = 0
toggleBtn.Parent = afActionRow
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 6)

local settingsPage = Instance.new("Frame")
settingsPage.Size = UDim2.new(1, 0, 1, 0)
settingsPage.BackgroundTransparency = 1
settingsPage.Visible = false
settingsPage.Parent = contentArea

local setHeader = Instance.new("Frame")
setHeader.Size = UDim2.new(1, -24, 0, 24)
setHeader.Position = UDim2.new(0, 12, 0, 6)
setHeader.BackgroundTransparency = 1
setHeader.Parent = settingsPage

local setTitle = Instance.new("TextLabel")
setTitle.Size = UDim2.new(1, 0, 1, 0)
setTitle.BackgroundTransparency = 1
setTitle.Text = "Configuration & Safety"
setTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
setTitle.Font = Enum.Font.GothamBold
setTitle.TextSize = 13
setTitle.TextXAlignment = Enum.TextXAlignment.Left
setTitle.Parent = setHeader

local function makeSettingCard(yPos, labelTxt)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -24, 0, 38)
    card.Position = UDim2.new(0, 12, 0, yPos)
    card.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
    card.BorderSizePixel = 0
    card.Parent = settingsPage
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -70, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelTxt
    lbl.TextColor3 = Color3.fromRGB(200, 205, 215)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = card

    return card
end

local speedCard = makeSettingCard(36, "Walk Speed (Tween to Shop)")
local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.new(0, 48, 0, 22)
speedBox.Position = UDim2.new(1, -58, 0.5, -11)
speedBox.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
speedBox.Text = tostring(WALK_SPEED)
speedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBox.Font = Enum.Font.GothamBold
speedBox.TextSize = 11
speedBox.BorderSizePixel = 0
speedBox.ClearTextOnFocus = false
speedBox.Parent = speedCard
Instance.new("UICorner", speedBox).CornerRadius = UDim.new(0, 4)

local antiAfkCard = makeSettingCard(80, "Anti-AFK (20m Kick Prevention)")
local antiAfkEnabled = true
local antiAfkBtn = Instance.new("TextButton")
antiAfkBtn.Size = UDim2.new(0, 48, 0, 22)
antiAfkBtn.Position = UDim2.new(1, -58, 0.5, -11)
antiAfkBtn.BackgroundColor3 = Color3.fromRGB(28, 54, 32)
antiAfkBtn.Text = "ON"
antiAfkBtn.TextColor3 = Color3.fromRGB(74, 222, 128)
antiAfkBtn.Font = Enum.Font.GothamBold
antiAfkBtn.TextSize = 10
antiAfkBtn.BorderSizePixel = 0
antiAfkBtn.Parent = antiAfkCard
Instance.new("UICorner", antiAfkBtn).CornerRadius = UDim.new(0, 4)

antiAfkBtn.MouseButton1Click:Connect(function()
    antiAfkEnabled = not antiAfkEnabled
    if antiAfkEnabled then
        antiAfkBtn.Text = "ON"
        antiAfkBtn.BackgroundColor3 = Color3.fromRGB(28, 54, 32)
        antiAfkBtn.TextColor3 = Color3.fromRGB(74, 222, 128)
    else
        antiAfkBtn.Text = "OFF"
        antiAfkBtn.BackgroundColor3 = Color3.fromRGB(42, 20, 20)
        antiAfkBtn.TextColor3 = Color3.fromRGB(248, 113, 113)
    end
end)

local returnHiveCard = makeSettingCard(124, "Return to Hive after Shop")
local returnHiveEnabled = true
local returnHiveBtn = Instance.new("TextButton")
returnHiveBtn.Size = UDim2.new(0, 48, 0, 22)
returnHiveBtn.Position = UDim2.new(1, -58, 0.5, -11)
returnHiveBtn.BackgroundColor3 = Color3.fromRGB(28, 54, 32)
returnHiveBtn.Text = "ON"
returnHiveBtn.TextColor3 = Color3.fromRGB(74, 222, 128)
returnHiveBtn.Font = Enum.Font.GothamBold
returnHiveBtn.TextSize = 10
returnHiveBtn.BorderSizePixel = 0
returnHiveBtn.Parent = returnHiveCard
Instance.new("UICorner", returnHiveBtn).CornerRadius = UDim.new(0, 4)

returnHiveBtn.MouseButton1Click:Connect(function()
    returnHiveEnabled = not returnHiveEnabled
    if returnHiveEnabled then
        returnHiveBtn.Text = "ON"
        returnHiveBtn.BackgroundColor3 = Color3.fromRGB(28, 54, 32)
        returnHiveBtn.TextColor3 = Color3.fromRGB(74, 222, 128)
    else
        returnHiveBtn.Text = "OFF"
        returnHiveBtn.BackgroundColor3 = Color3.fromRGB(42, 20, 20)
        returnHiveBtn.TextColor3 = Color3.fromRGB(248, 113, 113)
    end
end)

tabBtnAutoFeed.MouseButton1Click:Connect(function()
    autoFeedPage.Visible = true
    settingsPage.Visible = false
    tabBtnAutoFeed.BackgroundColor3 = Color3.fromRGB(37, 72, 130)
    tabBtnAutoFeed.TextColor3 = Color3.fromRGB(255, 255, 255)
    tabBtnSettings.BackgroundColor3 = Color3.fromRGB(15, 16, 21)
    tabBtnSettings.TextColor3 = Color3.fromRGB(160, 165, 175)
end)

tabBtnSettings.MouseButton1Click:Connect(function()
    settingsPage.Visible = true
    autoFeedPage.Visible = false
    tabBtnSettings.BackgroundColor3 = Color3.fromRGB(37, 72, 130)
    tabBtnSettings.TextColor3 = Color3.fromRGB(255, 255, 255)
    tabBtnAutoFeed.BackgroundColor3 = Color3.fromRGB(15, 16, 21)
    tabBtnAutoFeed.TextColor3 = Color3.fromRGB(160, 165, 175)
end)

local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        mainFrame.Size = UDim2.new(0, 480, 0, 32)
        bodyFrame.Visible = false
        minBtn.Text = "+"
    else
        mainFrame.Size = UDim2.new(0, 480, 0, 310)
        bodyFrame.Visible = true
        minBtn.Text = "—"
    end
end)

pcall(function()
    local vu = game:GetService("VirtualUser")
    player.Idled:Connect(function()
        if antiAfkEnabled then
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end
    end)
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
        local bftBonus = autoDetectBFT(data, bees)

        honeyLabel.Text = formatNum(getHoney(data))
        treatsLabel.Text = formatNum(getTreats(data))

        if not next(bees) then
            beeCountLabel.Text = "Bees: 0"
            totalTreatsLabel.Text = "0"
            totalHoneyLabel.Text = "0"
            overallLabel.Text = "0%"
            progressFill.Size = UDim2.new(0, 0, 1, 0)
            calcBtn.Text = "↻ Recalculate"
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

                local treats, totalPct, lvlPct, remBond, reqBond = calcBeeTreats(lvl, bond, targetLevel, bftBonus)
                totalTreats = totalTreats + treats
                totalBondReq = totalBondReq + reqBond
                totalBondDone = totalBondDone + (reqBond - remBond)
            end
        end

        local overall = totalBondReq > 0 and math.floor((totalBondDone / totalBondReq) * 10000) / 100 or 100
        beeCountLabel.Text = (bftBonus > 0) and (beeCount .. " bees | +" .. bftBonus .. "% BFT") or (beeCount .. " bees")
        overallLabel.Text = overall .. "%"
        totalTreatsLabel.Text = formatNum(totalTreats)
        totalHoneyLabel.Text = formatNum(totalTreats * TREAT_COST)
        progressFill.Size = UDim2.new(math.min(1, math.max(0, overall / 100)), 0, 1, 0)
    end)
    calcBtn.Text = "↻ Recalculate"
    isRefreshing = false
end

calcBtn.MouseButton1Click:Connect(refreshBeeList)
calcBtn.Activated:Connect(refreshBeeList)
targetBox.FocusLost:Connect(refreshBeeList)
speedBox.FocusLost:Connect(refreshBeeList)

toggleBtn.MouseButton1Click:Connect(function()
    autoRunning = not autoRunning
    if autoRunning then
        toggleBtn.Text = "● Auto: RUNNING"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(28, 54, 32)
        toggleBtn.TextColor3 = Color3.fromRGB(74, 222, 128)
    else
        toggleBtn.Text = "● Auto: OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(42, 20, 20)
        toggleBtn.TextColor3 = Color3.fromRGB(248, 113, 113)
        isTweening = false
    end
end)
toggleBtn.Activated:Connect(function()
    if not autoRunning then
        toggleBtn.Text = "● Auto: RUNNING"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(28, 54, 32)
        toggleBtn.TextColor3 = Color3.fromRGB(74, 222, 128)
        autoRunning = true
    else
        toggleBtn.Text = "● Auto: OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(42, 20, 20)
        toggleBtn.TextColor3 = Color3.fromRGB(248, 113, 113)
        autoRunning = false
        isTweening = false
    end
end)

spawn(function()
    while screenGui.Parent do
        if autoRunning then
            local data = getStatData()
            local bees = getAllBees(data)
            local bftBonus = autoDetectBFT(data, bees)

            if next(bees) then
                local totalNeeded = 0
                for _, bee in pairs(bees) do
                    local b = extractBee(bee) or bee
                    if type(b) == "table" then
                        local lvl = math.max(1, math.floor(tonumber(b.Level) or 1))
                        local bond = math.max(0, tonumber(b.Bond) or 0)
                        if lvl < targetLevel then
                            local treats = calcBeeTreats(lvl, bond, targetLevel, bftBonus)
                            totalNeeded = totalNeeded + treats
                        end
                    end
                end

                local owned = getTreats(data)
                local honey = getHoney(data)
                if autoBuyEnabled and owned < totalNeeded and honey >= TREAT_COST then
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
                            if returnHiveEnabled and savedPos then tweenTo(savedPos) end
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
                                local treatsNeeded = calcBeeTreats(lvl, bond, targetLevel, bftBonus)
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
