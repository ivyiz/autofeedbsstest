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
    ["glider"] = "Glider"
}

local function resolveItemName(raw)
    if not raw then return nil end
    local clean = tostring(raw):gsub("[%s%-_':%[%]%(%)]", ""):lower()
    if ITEM_ALIASES[clean] then return ITEM_ALIASES[clean] end
    if clean:find("diamask", 1, true) then return "Diamond Mask" end
    for k, v in pairs(ITEM_ALIASES) do
        if #k >= 6 and clean:find(k, 1, true) then
            return v
        end
    end
    return raw
end

local function isItemOwned(itemName, itemType, char, data)
    if not itemName then return false end
    local canonical = resolveItemName(itemName) or itemName
    local cleanName = tostring(canonical):gsub("[%s%-_']", ""):lower()
    local rawClean = tostring(itemName):gsub("[%s%-_']", ""):lower()

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

    local function checkMatch(val)
        if type(val) ~= "string" and type(val) ~= "number" then return end
        local c = tostring(val):gsub("[%s%-_']", ""):lower()
        if not curTool and TOOL_TIERS[c] then curTool = c end
        if not curBag and BAG_TIERS[c] then curBag = c end
        if not curBoots and BOOTS_TIERS[c] then curBoots = c end
        if not curBelt and BELT_TIERS[c] then curBelt = c end
        if not curHat and HAT_TIERS[c] then curHat = c end
        if not curSprinkler and SPRINKLER_TIERS[c] then curSprinkler = c end
        if not curBlueGuard and BLUE_GUARD_TIERS[c] then curBlueGuard = c end
        if not curRedGuard and RED_GUARD_TIERS[c] then curRedGuard = c end
        if not curGlider and c == "glider" then curGlider = c end
    end

    if char then
        for _, child in ipairs(char:GetChildren()) do
            checkMatch(child.Name)
            if child:IsA("Tool") and not curTool then
                local c = child.Name:gsub("[%s%-_']", ""):lower()
                if TOOL_TIERS[c] then curTool = c end
            end
        end
    end

    if player.Backpack then
        for _, child in ipairs(player.Backpack:GetChildren()) do
            checkMatch(child.Name)
            if child:IsA("Tool") and not curTool then
                local c = child.Name:gsub("[%s%-_']", ""):lower()
                if TOOL_TIERS[c] then curTool = c end
            end
        end
    end

    if data then
        for k, v in pairs(data) do
            if type(v) == "string" or type(v) == "number" then
                checkMatch(v)
                checkMatch(k)
            elseif type(v) == "table" then
                for k2, v2 in pairs(v) do
                    checkMatch(k2)
                    if type(v2) == "string" or type(v2) == "number" then checkMatch(v2) end
                end
            end
        end
    end

    if curTool then
        local c = tostring(curTool):gsub("[%s%-_']", ""):lower()
        if c == cleanName or c == rawClean then return true end
        local reqTier = TOOL_TIERS[cleanName] or TOOL_TIERS[rawClean]
        if reqTier and TOOL_TIERS[c] and TOOL_TIERS[c] >= reqTier then return true end
    end

    if curBag then
        local c = tostring(curBag):gsub("[%s%-_']", ""):lower()
        if c == cleanName or c == rawClean then return true end
        local reqTier = BAG_TIERS[cleanName] or BAG_TIERS[rawClean]
        if reqTier and BAG_TIERS[c] and BAG_TIERS[c] >= reqTier then return true end
    end

    if curBoots then
        local c = tostring(curBoots):gsub("[%s%-_']", ""):lower()
        if c == cleanName or c == rawClean then return true end
        local reqTier = BOOTS_TIERS[cleanName] or BOOTS_TIERS[rawClean]
        if reqTier and BOOTS_TIERS[c] and BOOTS_TIERS[c] >= reqTier then return true end
    end

    if curBelt then
        local c = tostring(curBelt):gsub("[%s%-_']", ""):lower()
        if c == cleanName or c == rawClean then return true end
        local reqTier = BELT_TIERS[cleanName] or BELT_TIERS[rawClean]
        if reqTier and BELT_TIERS[c] and BELT_TIERS[c] >= reqTier then return true end
    end

    local SPECIAL_MASKS = {
        ["honeymask"] = true, ["bubblemask"] = true, ["firemask"] = true,
        ["gummymask"] = true, ["demonmask"] = true, ["diamondmask"] = true, ["diamask"] = true
    }

    if curHat then
        local c = tostring(curHat):gsub("[%s%-_']", ""):lower()
        if c == cleanName or c == rawClean then return true end
        if not SPECIAL_MASKS[cleanName] and not SPECIAL_MASKS[rawClean] then
            local reqTier = HAT_TIERS[cleanName] or HAT_TIERS[rawClean]
            if reqTier and HAT_TIERS[c] and HAT_TIERS[c] >= reqTier then return true end
        end
    end

    if curSprinkler then
        local c = tostring(curSprinkler):gsub("[%s%-_']", ""):lower()
        if c == cleanName or c == rawClean then return true end
        local reqTier = SPRINKLER_TIERS[cleanName] or SPRINKLER_TIERS[rawClean]
        if reqTier and SPRINKLER_TIERS[c] and SPRINKLER_TIERS[c] >= reqTier then return true end
    end

    if curBlueGuard then
        local c = tostring(curBlueGuard):gsub("[%s%-_']", ""):lower()
        if c == cleanName or c == rawClean then return true end
        local reqTier = BLUE_GUARD_TIERS[cleanName] or BLUE_GUARD_TIERS[rawClean]
        if reqTier and BLUE_GUARD_TIERS[c] and BLUE_GUARD_TIERS[c] >= reqTier then return true end
    end

    if curRedGuard then
        local c = tostring(curRedGuard):gsub("[%s%-_']", ""):lower()
        if c == cleanName or c == rawClean then return true end
        local reqTier = RED_GUARD_TIERS[cleanName] or RED_GUARD_TIERS[rawClean]
        if reqTier and RED_GUARD_TIERS[c] and RED_GUARD_TIERS[c] >= reqTier then return true end
    end

    if (cleanName == "glider" or rawClean == "glider") and curGlider then
        return true
    end

    local eqSources = { eq, data, data and data.Accessories, data and data.Equipment, data and data.Items, data and data.Inventory }
    for _, src in ipairs(eqSources) do
        if type(src) == "table" then
            if src[canonical] or src[itemName] or src[cleanName] or src[rawClean] then return true end
            for k, val in pairs(src) do
                local kClean = tostring(k):gsub("[%s%-_']", ""):lower()
                local vClean = tostring(val):gsub("[%s%-_']", ""):lower()
                if kClean == cleanName or kClean == rawClean or vClean == cleanName or vClean == rawClean then
                    return true
                end
            end
        end
    end

    if (itemType == "Planter" or cleanName:find("planter") or rawClean:find("planter")) and data then
        local planterTables = { data.Planters, data.PurchasedPlanters, data.Items, data.Inventory }
        for _, pTable in ipairs(planterTables) do
            if type(pTable) == "table" then
                for pName in pairs(pTable) do
                    local pClean = tostring(pName):gsub("[%s%-_']", ""):lower()
                    if pClean == cleanName or pClean == rawClean then return true end
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
                local canonical = resolveItemName(name) or name
                local cleanName = tostring(canonical):gsub("[%s%-_']", ""):lower()
                local base = itemMap[cleanName]
                table.insert(dynamicRoute, {
                    Name = base and base.Name or tostring(canonical),
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

local function getAtlasLiveTarget()
    local settings = findAtlasSettings()
    if settings then
        if settings.toys and type(settings.toys) == "table" then
            if settings.toys.target then
                local res = resolveItemName(settings.toys.target)
                if res then return res end
            end
            if settings.toys.current then
                local res = resolveItemName(settings.toys.current)
                if res then return res end
            end
        end
        if settings.target then
            local res = resolveItemName(settings.target)
            if res then return res end
        end
    end

    local roots = { getgenv and getgenv(), _G, shared }
    for _, r in ipairs(roots) do
        if type(r) == "table" then
            if r.Atlas and type(r.Atlas) == "table" then
                if r.Atlas.ProgressionTarget then
                    local res = resolveItemName(r.Atlas.ProgressionTarget)
                    if res then return res end
                end
                if r.Atlas.CurrentTarget then
                    local res = resolveItemName(r.Atlas.CurrentTarget)
                    if res then return res end
                end
                if r.Atlas.Target then
                    local res = resolveItemName(r.Atlas.Target)
                    if res then return res end
                end
                if r.Atlas.CurrentPurchase then
                    local res = resolveItemName(r.Atlas.CurrentPurchase)
                    if res then return res end
                end
                if r.Atlas.Settings and type(r.Atlas.Settings) == "table" and r.Atlas.Settings.toys then
                    if r.Atlas.Settings.toys.target then
                        local res = resolveItemName(r.Atlas.Settings.toys.target)
                        if res then return res end
                    end
                end
            end
            if r.ProgressionTarget then
                local res = resolveItemName(r.ProgressionTarget)
                if res then return res end
            end
            if r.CurrentTarget then
                local res = resolveItemName(r.CurrentTarget)
                if res then return res end
            end
            if r.CurrentPurchase then
                local res = resolveItemName(r.CurrentPurchase)
                if res then return res end
            end
        end
    end

    local uiRoots = {}
    pcall(function() if gethui then table.insert(uiRoots, gethui()) end end)
    pcall(function() table.insert(uiRoots, CoreGui) end)
    pcall(function() table.insert(uiRoots, player:FindFirstChild("PlayerGui")) end)

    local candidate = nil
    for _, root in ipairs(uiRoots) do
        if root then
            for _, desc in ipairs(root:GetDescendants()) do
                if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                    local txt = desc.Text
                    if txt and txt ~= "" and #txt < 120 and desc.Name ~= "AutoProg_HUD" and desc.Parent and desc.Parent.Name ~= "AutoProg_HUD" then
                        local matched = txt:match("[Tt]arget%s*[:%-]?%s*([%w%s%-_']+)")
                            or txt:match("[Cc]urrent%s*[:%-]?%s*([%w%s%-_']+)")
                            or txt:match("[Pp]rog%w*%s*[:%-]?%s*([%w%s%-_']+)")
                            or txt:match("[Aa]uto%s*[Pp]rog%w*%s*[:%-]?%s*([%w%s%-_']+)")
                            or txt:match("[Bb]uying%s*[:%-]?%s*([%w%s%-_']+)")
                            or txt:match("[Cc]rafting%s*[:%-]?%s*([%w%s%-_']+)")
                            or txt:match("[Nn]ext%s*[:%-]?%s*([%w%s%-_']+)")
                        if matched then
                            local resolved = resolveItemName(matched)
                            if resolved and resolved ~= matched then
                                return resolved
                            end
                        end

                        local tLow = txt:lower()
                        if tLow:find("diamask") then
                            return "Diamond Mask"
                        end

                        local resolved = resolveItemName(txt)
                        if resolved and resolved ~= txt then
                            local pName = desc.Parent and desc.Parent.Name:lower() or ""
                            local dName = desc.Name:lower()
                            if pName:find("prog") or pName:find("target") or pName:find("gear") or pName:find("hud") or pName:find("main") or
                               dName:find("prog") or dName:find("target") or dName:find("gear") or dName:find("hud") or dName:find("main") or
                               dName:find("status") or pName:find("status") then
                                return resolved
                            end
                            if not candidate then candidate = resolved end
                        end
                    end
                end
            end
        end
    end
    if candidate then return candidate end
    return nil
end

local function evaluateRoute(data, beeCount)
    local char = player.Character

    local liveTarget = getAtlasLiveTarget()
    if liveTarget then
        local canonicalLive = resolveItemName(liveTarget) or liveTarget
        for _, milestone in ipairs(FullProgressionRoute) do
            local c1 = milestone.Name:gsub("[%s%-_']", ""):lower()
            local c2 = canonicalLive:gsub("[%s%-_']", ""):lower()
            if c1 == c2 then
                if milestone.Ingredients then
                    for _, ing in ipairs(milestone.Ingredients) do
                        local missingMat, missingAmt, targetField = resolveMissingMaterial(ing.Item, ing.Amount, data, beeCount)
                        if targetField then return milestone.Name, missingMat, missingAmt, targetField end
                    end
                end
                return milestone.Name, nil, 0, nil
            end
        end
    end

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
