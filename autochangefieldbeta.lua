local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
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

local TOOL_TIERS = {
    ["scooper"] = 1, ["rake"] = 2, ["clipper"] = 3, ["magnet"] = 4, ["vacuum"] = 5,
    ["superscooper"] = 6, ["pulsar"] = 7, ["electromagnet"] = 8, ["scissors"] = 9,
    ["honeydipper"] = 10, ["bubblewand"] = 11, ["scythe"] = 11, ["goldenrake"] = 12,
    ["porcelaindipper"] = 13, ["petalwand"] = 14, ["tidepopper"] = 15, ["darkscythe"] = 15,
    ["gummyballer"] = 15
}

local BAG_TIERS = {
    ["pouch"] = 1, ["backpack"] = 2, ["jar"] = 3, ["canister"] = 4, ["jug"] = 5,
    ["megajug"] = 6, ["barrel"] = 7, ["compressor"] = 8, ["elitebarrel"] = 9,
    ["portohive"] = 10, ["blueportohive"] = 11, ["redportohive"] = 11,
    ["porcelainportohive"] = 12, ["coconutcanister"] = 13
}

local BOOTS_TIERS = {
    ["basicboots"] = 1, ["hikingboots"] = 2, ["cleanboots"] = 3,
    ["beekeepersboots"] = 4, ["coconutclogs"] = 5, ["gummyboots"] = 6
}

local BELT_TIERS = {
    ["beltpocket"] = 1, ["utilitybelt"] = 2, ["beltbag"] = 3,
    ["mondobeltbag"] = 4, ["honeycombbelt"] = 5, ["petalbelt"] = 6,
    ["coconutbelt"] = 7
}

local HAT_TIERS = {
    ["helmet"] = 1, ["propellerhat"] = 2, ["beekeepersmask"] = 3,
    ["honeymask"] = 4, ["bubblemask"] = 4, ["firemask"] = 4,
    ["gummymask"] = 5, ["demonmask"] = 5, ["diamondmask"] = 5
}

local SPRINKLER_TIERS = {
    ["basicsprinkler"] = 1, ["silversoakers"] = 2, ["goldengushers"] = 3,
    ["diamonddrenchers"] = 4, ["thesupremesaturator"] = 5, ["supremesaturator"] = 5
}

local FullProgressionRoute = {
    { Bees = 0, Name = "Backpack", Type = "Bag" },
    { Bees = 0, Name = "Magnet", Type = "Tool" },
    { Bees = 0, Name = "Canister", Type = "Bag" },
    { Bees = 0, Name = "Vacuum", Type = "Tool" },
    { Bees = 3, Name = "Belt Pocket", Type = "Belt" },
    { Bees = 3, Name = "Basic Boots", Type = "Boots" },
    { Bees = 5, Name = "Compressor", Type = "Bag" },
    { Bees = 5, Name = "Super-Scooper", Type = "Tool" },
    { Bees = 5, Name = "Helmet", Type = "Hat" },
    { Bees = 10, Name = "Port-O-Hive", Type = "Bag" },
    { Bees = 10, Name = "Mega-Jug", Type = "Bag" },
    { Bees = 10, Name = "Electro-Magnet", Type = "Tool" },
    { Bees = 10, Name = "Honey Dipper", Type = "Tool" },
    { Bees = 10, Name = "Propeller Hat", Type = "Hat" },
    { Bees = 10, Name = "Looker Guard", Type = "Guard" },
    { Bees = 10, Name = "Brave Guard", Type = "Guard" },
    { Bees = 10, Name = "Hiking Boots", Type = "Boots" },
    { Bees = 12, Name = "Pulsar", Type = "Tool" },
    { Bees = 12, Name = "Belt Bag", Type = "Belt" },
    { Bees = 15, Name = "Scissors", Type = "Tool" },
    { Bees = 15, Name = "Elite Barrel", Type = "Bag" },
    { Bees = 20, Name = "Bubble Wand", Type = "Tool", Ingredients = { { Item = "Blueberry", Amount = 50 } } },
    { Bees = 20, Name = "Basic Sprinkler", Type = "Sprinkler" },
    { Bees = 20, Name = "Plastic Planter", Type = "Planter" },
    { Bees = 20, Name = "Beekeeper's Mask", Type = "Hat" },
    { Bees = 20, Name = "Beekeeper's Boots", Type = "Boots" },
    { Bees = 25, Name = "Mondo Belt Bag", Type = "Belt", Ingredients = { { Item = "Sunflower Seed", Amount = 50 }, { Item = "Pineapple", Amount = 50 } } },
    { Bees = 20, Name = "Blue Port-O-Hive", Type = "Bag", Ingredients = { { Item = "Blueberry", Amount = 100 } } },
    { Bees = 20, Name = "Silver Soakers", Type = "Sprinkler" },
    { Bees = 20, Name = "Elite Blue Guard", Type = "Guard", Ingredients = { { Item = "Blueberry", Amount = 50 } } },
    { Bees = 20, Name = "Elite Red Guard", Type = "Guard", Ingredients = { { Item = "Strawberry", Amount = 50 } } },
    { Bees = 25, Name = "Bucko Guard", Type = "Guard", Ingredients = { { Item = "Blueberry", Amount = 100 }, { Item = "Blue Extract", Amount = 5 } } },
    { Bees = 25, Name = "Riley Guard", Type = "Guard", Ingredients = { { Item = "Strawberry", Amount = 100 }, { Item = "Red Extract", Amount = 5 } } },
    { Bees = 25, Name = "Candy Planter", Type = "Planter", Ingredients = { { Item = "Gumdrop", Amount = 100 } } },
    { Bees = 25, Name = "Glider", Type = "Glider" },
    { Bees = 25, Name = "Golden Rake", Type = "Tool" },
    { Bees = 25, Name = "Porcelain Dipper", Type = "Tool" },
    { Bees = 25, Name = "Porcelain Port-O-Hive", Type = "Bag" },
    { Bees = 25, Name = "Blue Clay Planter", Type = "Planter", Ingredients = { { Item = "Blueberry", Amount = 50 } } },
    { Bees = 25, Name = "Red Clay Planter", Type = "Planter", Ingredients = { { Item = "Strawberry", Amount = 50 } } },
    { Bees = 20, Name = "Bubble Mask", Type = "Hat", Ingredients = { { Item = "Blueberry", Amount = 250 }, { Item = "Blue Extract", Amount = 50 } } },
    { Bees = 20, Name = "Cobalt Guard", Type = "Guard", Ingredients = { { Item = "Blue Extract", Amount = 100 }, { Item = "Glue", Amount = 50 }, { Item = "Oil", Amount = 25 }, { Item = "Enzymes", Amount = 25 } } },
    { Bees = 25, Name = "Golden Gushers", Type = "Sprinkler" },
    { Bees = 35, Name = "Tacky Planter", Type = "Planter", Ingredients = { { Item = "Sunflower Seed", Amount = 500 } } },
    { Bees = 20, Name = "Diamond Mask", Type = "Hat", Ingredients = { { Item = "Blue Extract", Amount = 250 }, { Item = "Oil", Amount = 150 } } },
    { Bees = 20, Name = "Crimson Guard", Type = "Guard", Ingredients = { { Item = "Red Extract", Amount = 100 }, { Item = "Glue", Amount = 50 }, { Item = "Oil", Amount = 25 }, { Item = "Enzymes", Amount = 25 } } },
    { Bees = 35, Name = "Diamond Drenchers", Type = "Sprinkler" },
    { Bees = 35, Name = "Coconut Canister", Type = "Bag", Ingredients = { { Item = "Coconut", Amount = 150 }, { Item = "Tropical Drink", Amount = 150 }, { Item = "Red Extract", Amount = 250 }, { Item = "Blue Extract", Amount = 250 } } },
    { Bees = 35, Name = "Pesticide Planter", Type = "Planter", Ingredients = { { Item = "Strawberry", Amount = 500 } } },
    { Bees = 35, Name = "Coconut Clogs", Type = "Boots", Ingredients = { { Item = "Coconut", Amount = 150 }, { Item = "Tropical Drink", Amount = 50 }, { Item = "Glue", Amount = 100 }, { Item = "Oil", Amount = 100 } } },
    { Bees = 35, Name = "The Supreme Saturator", Type = "Sprinkler" },
    { Bees = 35, Name = "Tide Popper", Type = "Tool", Ingredients = { { Item = "Blue Extract", Amount = 1500 }, { Item = "Tropical Drink", Amount = 150 } } },
    { Bees = 35, Name = "Hydroponic Planter", Type = "Planter", Ingredients = { { Item = "Blue Extract", Amount = 100 } } },
    { Bees = 35, Name = "Petal Planter", Type = "Planter", Ingredients = { { Item = "Enzymes", Amount = 100 } } },
    { Bees = 35, Name = "Heat-Treated Planter", Type = "Planter", Ingredients = { { Item = "Red Extract", Amount = 100 } } },
    { Bees = 35, Name = "Gummy Boots", Type = "Boots", Ingredients = { { Item = "Glue", Amount = 500 }, { Item = "Tropical Drink", Amount = 100 }, { Item = "Red Extract", Amount = 250 }, { Item = "Blue Extract", Amount = 250 } } },
    { Bees = 35, Name = "Coconut Belt", Type = "Belt", Ingredients = { { Item = "Coconut", Amount = 500 }, { Item = "Tropical Drink", Amount = 250 }, { Item = "Glue", Amount = 150 }, { Item = "Enzymes", Amount = 150 } } },
    { Bees = 35, Name = "Plenty Planter", Type = "Planter" },
    { Bees = 35, Name = "Petal Belt", Type = "Belt", Ingredients = { { Item = "Glue", Amount = 25 }, { Item = "Enzymes", Amount = 75 } } },
    { Bees = 35, Name = "Petal Wand", Type = "Tool", Ingredients = { { Item = "Enzymes", Amount = 75 } } }
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
    local cleanName = tostring(itemName):gsub("[%s%-_']", ""):lower()

    if char and (char:FindFirstChild(itemName) or char:FindFirstChild(cleanName)) then return true end
    if player.Backpack and (player.Backpack:FindFirstChild(itemName) or player.Backpack:FindFirstChild(cleanName)) then return true end
    if char then
        for _, child in ipairs(char:GetChildren()) do
            local cName = child.Name:gsub("[%s%-_']", ""):lower()
            if cName == cleanName then return true end
        end
    end

    local eq = (data and (data.Equipped or data.Equipment)) or {}

    local curTool = eq.Collector or eq.Tool
    if not curTool then
        local toolContainers = { char, player.Backpack }
        for _, cont in ipairs(toolContainers) do
            if cont then
                local t = cont:FindFirstChildWhichIsA("Tool")
                if t then
                    local c = t.Name:gsub("[%s%-_']", ""):lower()
                    if TOOL_TIERS[c] then curTool = t.Name break end
                end
                for _, ch in ipairs(cont:GetChildren()) do
                    local c = ch.Name:gsub("[%s%-_']", ""):lower()
                    if TOOL_TIERS[c] then curTool = ch.Name break end
                end
            end
            if curTool then break end
        end
    end
    if curTool then
        local curToolClean = tostring(curTool):gsub("[%s%-_']", ""):lower()
        if curToolClean == cleanName then return true end
        if TOOL_TIERS[curToolClean] and TOOL_TIERS[cleanName] then
            if TOOL_TIERS[curToolClean] >= TOOL_TIERS[cleanName] then return true end
        end
    end

    local curBag = eq.Bag or eq.Backpack
    local curBoots = eq.Boots or eq.Shoes
    local curBelt = eq.Belt
    local curHat = eq.Hat or eq.Mask
    local curSprinkler = eq.Sprinkler

    if char then
        for _, child in ipairs(char:GetChildren()) do
            local c = child.Name:gsub("[%s%-_']", ""):lower()
            if not curBag and BAG_TIERS[c] then curBag = child.Name end
            if not curBoots and BOOTS_TIERS[c] then curBoots = child.Name end
            if not curBelt and BELT_TIERS[c] then curBelt = child.Name end
            if not curHat and HAT_TIERS[c] then curHat = child.Name end
            if not curSprinkler and SPRINKLER_TIERS[c] then curSprinkler = child.Name end
        end
    end

    if player.Backpack then
        for _, child in ipairs(player.Backpack:GetChildren()) do
            local c = child.Name:gsub("[%s%-_']", ""):lower()
            if not curSprinkler and SPRINKLER_TIERS[c] then curSprinkler = child.Name end
        end
    end

    if curBag then
        local curBagClean = tostring(curBag):gsub("[%s%-_']", ""):lower()
        if curBagClean == cleanName then return true end
        if BAG_TIERS[curBagClean] and BAG_TIERS[cleanName] then
            if BAG_TIERS[curBagClean] >= BAG_TIERS[cleanName] then return true end
        end
    end

    if curBoots then
        local curBootsClean = tostring(curBoots):gsub("[%s%-_']", ""):lower()
        if curBootsClean == cleanName then return true end
        if BOOTS_TIERS[curBootsClean] and BOOTS_TIERS[cleanName] then
            if BOOTS_TIERS[curBootsClean] >= BOOTS_TIERS[cleanName] then return true end
        end
    end

    if curBelt then
        local curBeltClean = tostring(curBelt):gsub("[%s%-_']", ""):lower()
        if curBeltClean == cleanName then return true end
        if BELT_TIERS[curBeltClean] and BELT_TIERS[cleanName] then
            if BELT_TIERS[curBeltClean] >= BELT_TIERS[cleanName] then return true end
        end
    end

    local SPECIAL_MASKS = {
        ["honeymask"] = true, ["bubblemask"] = true, ["firemask"] = true,
        ["gummymask"] = true, ["demonmask"] = true, ["diamondmask"] = true
    }

    if curHat then
        local curHatClean = tostring(curHat):gsub("[%s%-_']", ""):lower()
        if curHatClean == cleanName then return true end
        if not SPECIAL_MASKS[cleanName] and HAT_TIERS[curHatClean] and HAT_TIERS[cleanName] then
            if HAT_TIERS[curHatClean] >= HAT_TIERS[cleanName] then return true end
        end
    end

    if curSprinkler then
        local curSprinklerClean = tostring(curSprinkler):gsub("[%s%-_']", ""):lower()
        if curSprinklerClean == cleanName then return true end
        if SPRINKLER_TIERS[curSprinklerClean] and SPRINKLER_TIERS[cleanName] then
            if SPRINKLER_TIERS[curSprinklerClean] >= SPRINKLER_TIERS[cleanName] then return true end
        end
    end

    local eqSources = { eq, data and data.Accessories, data and data.Equipment, data and data.Items, data and data.Inventory }
    for _, src in ipairs(eqSources) do
        if type(src) == "table" then
            if src[itemName] or src[cleanName] then return true end
            for k, val in pairs(src) do
                local kClean = tostring(k):gsub("[%s%-_']", ""):lower()
                local vClean = tostring(val):gsub("[%s%-_']", ""):lower()
                if kClean == cleanName or vClean == cleanName then return true end
            end
        end
    end

    if (itemType == "Planter" or cleanName:find("planter")) and data then
        local planterTables = { data.Planters, data.PurchasedPlanters, data.Items, data.Inventory }
        for _, pTable in ipairs(planterTables) do
            if type(pTable) == "table" then
                for pName in pairs(pTable) do
                    if tostring(pName):gsub("[%s%-_']", ""):lower() == cleanName then return true end
                end
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
        local map = { ["Blueberry"] = "Bamboo Field", ["Strawberry"] = "Strawberry Field", ["Sunflower Seed"] = "Sunflower Field", ["Pineapple"] = "Pineapple Patch" }
        return map[material]
    else
        local map = { ["Blueberry"] = "Pine Tree Forest", ["Strawberry"] = "Strawberry Field", ["Sunflower Seed"] = "Sunflower Field", ["Pineapple"] = "Pineapple Patch", ["Coconut"] = (beeCount >= 35) and "Coconut Field" or nil }
        return map[material]
    end
end

local _cachedAtlasSettings = nil

local function findAtlasSettings()
    if _cachedAtlasSettings and type(_cachedAtlasSettings) == "table" and _cachedAtlasSettings.toys and _cachedAtlasSettings.autofarm then
        return _cachedAtlasSettings
    end

    local roots = { getgenv and getgenv(), _G, shared }
    for _, root in ipairs(roots) do
        if type(root) == "table" then
            if rawget(root, "toys") and rawget(root, "autofarm") then
                _cachedAtlasSettings = root
                return root
            end
            for k, v in pairs(root) do
                if type(v) == "table" and k ~= "_G" and k ~= "shared" and k ~= "game" and k ~= "workspace" and k ~= "Enum" then
                    if rawget(v, "toys") and rawget(v, "autofarm") then
                        _cachedAtlasSettings = v
                        return v
                    end
                    if rawget(v, "Settings") and type(v.Settings) == "table" and rawget(v.Settings, "toys") and rawget(v.Settings, "autofarm") then
                        _cachedAtlasSettings = v.Settings
                        return v.Settings
                    end
                end
            end
        end
    end

    if getgc then
        local ok, gc = pcall(getgc, true)
        if not ok or type(gc) ~= "table" then ok, gc = pcall(getgc) end
        if ok and type(gc) == "table" then
            for _, obj in ipairs(gc) do
                if type(obj) == "table" and rawget(obj, "toys") and rawget(obj, "autofarm") then
                    _cachedAtlasSettings = obj
                    return obj
                end
            end
        end
    end

    return nil
end

local function setAtlasField(field)
    if not field then return end
    local settings = findAtlasSettings()
    if settings then
        if settings.autofarm and type(settings.autofarm) == "table" then
            settings.autofarm.field1 = field
            settings.autofarm.field2 = field
            settings.autofarm.field3 = field
        end
        settings.Field = field
    end
    if getgenv then
        if getgenv().Atlas and getgenv().Atlas.Settings then
            getgenv().Atlas.Settings.Field = field
            if getgenv().Atlas.Settings.autofarm then
                getgenv().Atlas.Settings.autofarm.field1 = field
                getgenv().Atlas.Settings.autofarm.field2 = field
                getgenv().Atlas.Settings.autofarm.field3 = field
            end
        end
        if getgenv().Config then
            getgenv().Config.Field = field
            if getgenv().Config.autofarm then
                getgenv().Config.autofarm.field1 = field
            end
        end
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

local function extractPurchaseList(tbl, depth)
    if type(tbl) ~= "table" or ((depth or 0) > 6) then return nil end
    local items = {}

    local function scan(t, d)
        if type(t) ~= "table" or d > 6 then return end

        local p = t.purchase or t.Purchase
        if p then
            local reqBees = t.required_bees or t.Bees or t.req_bees or 0
            if type(p) == "table" then
                for _, itm in ipairs(p) do
                    if type(itm) == "string" then
                        table.insert(items, { Name = itm, Bees = reqBees })
                    elseif type(itm) == "table" then
                        table.insert(items, itm)
                    end
                end
            elseif type(p) == "string" then
                table.insert(items, { Name = p, Bees = reqBees })
            end
        end

        if (t.Type == "Purchase" or t.type == "purchase" or t.type == "Purchase") and (t.Data or t.data) then
            local data = t.Data or t.data
            local reqBees = t.Bees or t.required_bees or 0
            if type(data) == "table" then
                for _, itm in ipairs(data) do
                    if type(itm) == "string" then
                        table.insert(items, { Name = itm, Bees = reqBees })
                    elseif type(itm) == "table" then
                        table.insert(items, itm)
                    end
                end
            elseif type(data) == "string" then
                table.insert(items, { Name = data, Bees = reqBees })
            end
        end

        for k, v in pairs(t) do
            if type(v) == "table" and k ~= "_G" and k ~= "shared" and k ~= "game" and k ~= "workspace" and k ~= "Enum" then
                scan(v, d + 1)
            end
        end
    end

    scan(tbl, 0)
    if #items > 0 then return items end

    if #tbl > 0 and type(tbl[1]) == "string" then
        return tbl
    end
    return nil
end

local function readAtlasFileRoute()
    if not (readfile and isfile) then return nil end

    local testPaths = {
        "atlas1/preset1.json",
        "atlas1/preset 1.json",
        "atlas1/preset_1.json",
        "atlas1/1.json",
        "atlas1/config.json",
        "atlas1/settings.json",
        "Atlas1/preset1.json",
        "Atlas1/preset 1.json",
        "Atlas1/config.json",
        "Atlas/preset1.json",
        "Atlas/preset 1.json",
        "Atlas/configs/preset1.json",
        "Atlas/settings/preset1.json",
        "Atlas/config.json",
        "Atlas/settings.json",
        "preset1.json",
        "preset 1.json",
        "config.json",
        "route.json"
    }

    local filesToTry = {}
    if getgenv and getgenv().AtlasConfigPath and isfile(getgenv().AtlasConfigPath) then
        table.insert(filesToTry, getgenv().AtlasConfigPath)
    end
    for _, p in ipairs(testPaths) do
        table.insert(filesToTry, p)
    end

    if listfiles then
        local dirs = { "atlas1", "Atlas", "Atlas/configs", "Atlas/settings", "Atlas1", "atlas1/configs", "atlas1/settings", "" }
        for _, dir in ipairs(dirs) do
            local ok, list = pcall(listfiles, dir)
            if ok and type(list) == "table" then
                for _, f in ipairs(list) do
                    if tostring(f):lower():find("%.json$") then
                        table.insert(filesToTry, f)
                    end
                end
            end
        end
    end

    for _, path in ipairs(filesToTry) do
        if isfile(path) then
            local ok, content = pcall(readfile, path)
            if ok and content and content ~= "" then
                local s, decoded = pcall(function() return HttpService:JSONDecode(content) end)
                if s and type(decoded) == "table" then
                    if decoded.toys and decoded.toys.route then
                        return decoded.toys.route
                    elseif decoded.route then
                        return decoded.route
                    elseif #decoded > 0 then
                        return decoded
                    end
                end
            end
        end
    end
    return nil
end

local function getAtlasRoute()
    local rawItemsList = nil

    local settings = findAtlasSettings()
    if settings and settings.toys and settings.toys.route then
        rawItemsList = extractPurchaseList(settings.toys.route, 0) or extractPurchaseList(settings.toys, 0)
    end

    if not rawItemsList and getgenv then
        if getgenv().AtlasRoute then
            rawItemsList = extractPurchaseList(getgenv().AtlasRoute, 0) or (type(getgenv().AtlasRoute) == "table" and getgenv().AtlasRoute)
        end
        if not rawItemsList and getgenv().Atlas then
            rawItemsList = extractPurchaseList(getgenv().Atlas, 0)
        end
    end

    if not rawItemsList then
        local fileRoute = readAtlasFileRoute()
        if fileRoute then
            rawItemsList = extractPurchaseList(fileRoute, 0)
        end
    end

    if rawItemsList and type(rawItemsList) == "table" and #rawItemsList > 0 then
        local itemMap = {}
        for _, entry in ipairs(FullProgressionRoute) do
            local clean = entry.Name:gsub("[%s%-_']", ""):lower()
            itemMap[clean] = entry
        end

        local dynamicRoute = {}
        for _, rawItem in ipairs(rawItemsList) do
            local name = (type(rawItem) == "table" and (rawItem.Name or rawItem.Item or rawItem.Target or rawItem.Gear)) or (type(rawItem) == "string" and rawItem)
            local reqBees = (type(rawItem) == "table" and (rawItem.Bees or rawItem.BeeCount or rawItem.ReqBees))
            if name then
                local cleanName = tostring(name):gsub("[%s%-_']", ""):lower()
                local base = itemMap[cleanName]
                table.insert(dynamicRoute, {
                    Name = base and base.Name or tostring(name),
                    Type = base and base.Type or "Gear",
                    Bees = tonumber(reqBees) or (base and base.Bees) or 0,
                    Ingredients = base and base.Ingredients or nil
                })
            end
        end
        if #dynamicRoute > 0 then
            return dynamicRoute
        end
    end

    return FullProgressionRoute
end

local function evaluateRoute(data, beeCount)
    local char = player.Character
    local activeRoute = getAtlasRoute()
    for _, milestone in ipairs(activeRoute) do
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

local hudLabel = Instance.new("TextLabel")
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
