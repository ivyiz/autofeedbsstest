local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer

local RECIPES = {
    ["Blue Extract"] = { { Item = "Blueberry", Amount = 50 } },
    ["Red Extract"] = { { Item = "Strawberry", Amount = 50 } },
    ["Oil"] = { { Item = "Sunflower Seed", Amount = 50 } },
    ["Enzymes"] = { { Item = "Pineapple", Amount = 50 } },
    ["Gumdrop"] = { { Item = "Strawberry", Amount = 3 }, { Item = "Blueberry", Amount = 3 }, { Item = "Pineapple", Amount = 3 } },
    ["Glue"] = { { Item = "Gumdrop", Amount = 50 } },
    ["Tropical Drink"] = { { Item = "Coconut", Amount = 10 }, { Item = "Enzymes", Amount = 2 }, { Item = "Oil", Amount = 2 } }
}

local FullProgressionRoute = {
    { Bees = 0, Name = "Vacuum", Type = "Tool" },
    { Bees = 3, Name = "Backpack", Type = "Bag" },
    { Bees = 3, Name = "Helmet", Type = "Hat" },
    { Bees = 3, Name = "Belt Pocket", Type = "Belt" },
    { Bees = 5, Name = "Canister", Type = "Bag" },
    { Bees = 10, Name = "Super-Scooper", Type = "Tool" },
    { Bees = 10, Name = "Mega-Jug", Type = "Bag" },
    { Bees = 10, Name = "Brave Guard", Type = "Guard" },
    { Bees = 10, Name = "Looker Guard", Type = "Guard" },
    { Bees = 10, Name = "Propeller Hat", Type = "Hat" },
    { Bees = 12, Name = "Pulsar", Type = "Tool" },
    { Bees = 12, Name = "Compressor", Type = "Bag" },
    { Bees = 12, Name = "Belt Bag", Type = "Belt" },
    { Bees = 12, Name = "Electro-Magnet", Type = "Tool" },
    { Bees = 15, Name = "Scissors", Type = "Tool" },
    { Bees = 15, Name = "Elite Barrel", Type = "Bag" },
    { Bees = 15, Name = "Honey Dipper", Type = "Tool" },
    { Bees = 15, Name = "Port-O-Hive", Type = "Bag" },
    { Bees = 20, Name = "Bubble Wand", Type = "Tool", Ingredients = { { Item = "Blueberry", Amount = 50 } } },
    { Bees = 20, Name = "Blue Port-O-Hive", Type = "Bag", Ingredients = { { Item = "Blueberry", Amount = 100 } } },
    { Bees = 20, Name = "Elite Blue Guard", Type = "Guard", Ingredients = { { Item = "Blueberry", Amount = 50 } } },
    { Bees = 20, Name = "Elite Red Guard", Type = "Guard", Ingredients = { { Item = "Strawberry", Amount = 50 } } },
    { Bees = 20, Name = "Plastic Planter", Type = "Planter" },
    { Bees = 25, Name = "Bucko Guard", Type = "Guard", Ingredients = { { Item = "Blueberry", Amount = 100 }, { Item = "Blue Extract", Amount = 5 } } },
    { Bees = 25, Name = "Riley Guard", Type = "Guard", Ingredients = { { Item = "Strawberry", Amount = 100 }, { Item = "Red Extract", Amount = 5 } } },
    { Bees = 25, Name = "Glider", Type = "Glider" },
    { Bees = 25, Name = "Beekeeper's Boots", Type = "Boots" },
    { Bees = 25, Name = "Mondo Belt Bag", Type = "Belt", Ingredients = { { Item = "Sunflower Seed", Amount = 50 }, { Item = "Pineapple", Amount = 50 } } },
    { Bees = 25, Name = "Blue Clay Planter", Type = "Planter", Ingredients = { { Item = "Blueberry", Amount = 50 } } },
    { Bees = 25, Name = "Red Clay Planter", Type = "Planter", Ingredients = { { Item = "Strawberry", Amount = 50 } } },
    { Bees = 27, Name = "Beekeeper's Mask", Type = "Hat" },
    { Bees = 27, Name = "Candy Planter", Type = "Planter", Ingredients = { { Item = "Gumdrop", Amount = 100 } } },
    { Bees = 29, Name = "Golden Rake", Type = "Tool" },
    { Bees = 29, Name = "Porcelain Dipper", Type = "Tool" },
    { Bees = 29, Name = "Porcelain Port-O-Hive", Type = "Bag" },
    { Bees = 29, Name = "Golden Gushers", Type = "Sprinkler" },
    { Bees = 35, Name = "Bubble Mask", Type = "Hat", Ingredients = { { Item = "Blueberry", Amount = 250 }, { Item = "Blue Extract", Amount = 50 } } },
    { Bees = 35, Name = "Tacky Planter", Type = "Planter", Ingredients = { { Item = "Sunflower Seed", Amount = 500 } } },
    { Bees = 35, Name = "Petal Belt", Type = "Belt", Ingredients = { { Item = "Glue", Amount = 25 }, { Item = "Enzymes", Amount = 75 } } },
    { Bees = 35, Name = "Cobalt Guard", Type = "Guard", Ingredients = { { Item = "Blue Extract", Amount = 100 }, { Item = "Glue", Amount = 50 }, { Item = "Oil", Amount = 25 }, { Item = "Enzymes", Amount = 25 } } },
    { Bees = 35, Name = "Crimson Guard", Type = "Guard", Ingredients = { { Item = "Red Extract", Amount = 100 }, { Item = "Glue", Amount = 50 }, { Item = "Oil", Amount = 25 }, { Item = "Enzymes", Amount = 25 } } },
    { Bees = 37, Name = "Pesticide Planter", Type = "Planter", Ingredients = { { Item = "Strawberry", Amount = 500 } } },
    { Bees = 37, Name = "Diamond Drenchers", Type = "Sprinkler" },
    { Bees = 39, Name = "Diamond Mask", Type = "Hat", Ingredients = { { Item = "Blue Extract", Amount = 250 }, { Item = "Oil", Amount = 150 } } },
    { Bees = 39, Name = "Coconut Canister", Type = "Bag", Ingredients = { { Item = "Coconut", Amount = 150 }, { Item = "Tropical Drink", Amount = 150 }, { Item = "Red Extract", Amount = 250 }, { Item = "Blue Extract", Amount = 250 } } },
    { Bees = 45, Name = "Gummy Boots", Type = "Boots", Ingredients = { { Item = "Glue", Amount = 500 }, { Item = "Tropical Drink", Amount = 100 }, { Item = "Red Extract", Amount = 250 }, { Item = "Blue Extract", Amount = 250 } } }
}

local function getStatData()
    local clientStat = RS:FindFirstChild("ClientStatCache")
    if clientStat then
        local myStats = clientStat:FindFirstChild(player.Name)
        if myStats then
            local data = {}
            for _, folder in ipairs(myStats:GetChildren()) do
                if folder:IsA("Folder") or folder:IsA("Configuration") then
                    data[folder.Name] = {}
                    for _, val in ipairs(folder:GetChildren()) do
                        if val:IsA("ValueBase") then data[folder.Name][val.Name] = val.Value end
                    end
                elseif folder:IsA("ValueBase") then
                    data[folder.Name] = folder.Value
                end
            end
            return data
        end
    end
    local events = RS:FindFirstChild("Events")
    if events and events:FindFirstChild("RetrievePlayerStats") then
        local ok, res = pcall(function() return events.RetrievePlayerStats:InvokeServer() end)
        if ok and type(res) == "table" then return res end
    end
    return nil
end

local function getBeeCount(data)
    local count = 0
    local honeycombs = workspace:FindFirstChild("Honeycombs")
    local hVal = player:FindFirstChild("Honeycomb") and player.Honeycomb.Value
    local hive = (typeof(hVal) == "Instance" and hVal) or (honeycombs and honeycombs:FindFirstChild(tostring(hVal)))
    if hive and hive:FindFirstChild("Cells") then
        for _, cell in ipairs(hive.Cells:GetChildren()) do
            local ct = cell:FindFirstChild("CellType") or cell:FindFirstChild("Type")
            if ct and ct.Value ~= "" and ct.Value ~= "Empty" then count = count + 1 end
        end
    end
    if count > 0 then return count end
    if data and data.Bees and type(data.Bees) == "table" then
        for _ in pairs(data.Bees) do count = count + 1 end
    end
    return count
end

local function getItemAmount(item, data)
    if not data then return 0 end
    local cleanKey = item:gsub("%s+", "")
    local keys = { item, cleanKey }
    local folders = { data.Eggs, data.Inventory, data.Items, data }
    for _, folder in ipairs(folders) do
        if type(folder) == "table" then
            for _, k in ipairs(keys) do
                if folder[k] ~= nil then
                    local num = tonumber(folder[k])
                    if num then return num end
                end
            end
        end
    end
    return 0
end

local function isItemOwned(itemName, itemType, char, data)
    if not itemName then return false end
    if char and char:FindFirstChild(itemName) then return true end
    if player.Backpack and player.Backpack:FindFirstChild(itemName) then return true end
    if char then
        for _, child in ipairs(char:GetChildren()) do
            if child.Name == itemName then return true end
        end
    end
    if data then
        local equipTables = { data.Equipped, data.Equipment }
        for _, eqTable in ipairs(equipTables) do
            if type(eqTable) == "table" then
                for _, eq in pairs(eqTable) do
                    if tostring(eq) == itemName then return true end
                end
            end
        end
        if itemType == "Planter" then
            local planterTables = { data.Planters, data.PurchasedPlanters }
            for _, pTable in ipairs(planterTables) do
                if type(pTable) == "table" and pTable[itemName] then return true end
            end
        end
    end
    return false
end

local function getTargetField(material, beeCount)
    if material == "Coconut" and beeCount >= 35 then return "Coconut Field" end
    if beeCount < 5 then
        local map = { ["Blueberry"] = "Blue Flower Field", ["Strawberry"] = "Mushroom Field", ["Sunflower Seed"] = "Sunflower Field", ["Pineapple"] = "Dandelion Field" }
        return map[material]
    elseif beeCount < 15 then
        local map = { ["Blueberry"] = "Bamboo Field", ["Strawberry"] = "Strawberry Field", ["Sunflower Seed"] = "Sunflower Field", ["Pineapple"] = "Pineapple Field" }
        return map[material]
    else
        local map = { ["Blueberry"] = "Pine Tree Field", ["Strawberry"] = "Strawberry Field", ["Sunflower Seed"] = "Sunflower Field", ["Pineapple"] = "Pineapple Field", ["Coconut"] = (beeCount >= 35) and "Coconut Field" or nil }
        return map[material]
    end
end

local function setAtlasField(field)
    if not field then return end
    if getgenv and getgenv().Atlas and getgenv().Atlas.Settings then
        getgenv().Atlas.Settings.Field = field
    elseif getgenv and getgenv().Config then
        getgenv().Config.Field = field
    end
end

local function resolveMissingMaterial(item, neededAmount, data, beeCount)
    local invCount = getItemAmount(item, data)
    local deficit = neededAmount - invCount
    if deficit <= 0 then return nil end

    local recipe = RECIPES[item]
    if recipe then
        for _, sub in ipairs(recipe) do
            local totalSubNeeded = deficit * sub.Amount
            local missingMat, missingAmt, targetField = resolveMissingMaterial(sub.Item, totalSubNeeded, data, beeCount)
            if targetField then return missingMat, missingAmt, targetField end
        end
    else
        local field = getTargetField(item, beeCount)
        if field then return item, deficit, field end
    end
    return nil
end

local function evaluateRoute(data, beeCount)
    local char = player.Character
    for _, milestone in ipairs(FullProgressionRoute) do
        local owned = isItemOwned(milestone.Name, milestone.Type, char, data)
        if not owned and beeCount >= milestone.Bees then
            if milestone.Ingredients then
                for _, ing in ipairs(milestone.Ingredients) do
                    local missingMat, missingAmt, targetField = resolveMissingMaterial(ing.Item, ing.Amount, data, beeCount)
                    if targetField then return milestone.Name, missingMat, missingAmt, targetField end
                end
            end
            return milestone.Name, nil, 0, nil
        end
    end
    return nil, nil, 0, nil
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

local hudFrame = Instance.new("Frame")
hudFrame.AnchorPoint = Vector2.new(1, 1)
hudFrame.Position = UDim2.new(1, -12, 1, -12)
hudFrame.Size = UDim2.new(0, 0, 0, 26)
hudFrame.AutomaticSize = Enum.AutomaticSize.X
hudFrame.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
hudFrame.BorderSizePixel = 0
hudFrame.Parent = hudGui
Instance.new("UICorner", hudFrame).CornerRadius = UDim.new(0, 6)

local hudStroke = Instance.new("UIStroke", hudFrame)
hudStroke.Color = Color3.fromRGB(30, 36, 48)
hudStroke.Thickness = 1

local hudPadding = Instance.new("UIPadding", hudFrame)
hudPadding.PaddingLeft = UDim.new(0, 10)
hudPadding.PaddingRight = UDim.new(0, 10)

local hudLabel = Instance.new("TextLabel")
hudLabel.Size = UDim2.new(1, 0, 1, 0)
hudLabel.BackgroundTransparency = 1
hudLabel.Font = Enum.Font.GothamBold
hudLabel.TextSize = 11
hudLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
hudLabel.TextXAlignment = Enum.TextXAlignment.Center
hudLabel.Text = "[Auto Prog] Initializing..."
hudLabel.Parent = hudFrame

task.spawn(function()
    while true do
        local data = getStatData()
        local beeCount = getBeeCount(data)
        local targetItem, neededMat, neededAmt, field = evaluateRoute(data, beeCount)

        local targetStr = targetItem or "None"
        local needStr = neededMat and string.format("%s (%s)", neededMat, tostring(neededAmt)) or "None"
        local fieldStr = field or "Idle"

        hudLabel.Text = string.format("[Auto Prog] Bees: %d | Target: %s | Need: %s | Field: %s", beeCount, targetStr, needStr, fieldStr)

        if field then
            setAtlasField(field)
        end
        task.wait(10)
    end
end)
