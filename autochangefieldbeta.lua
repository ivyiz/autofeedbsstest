local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

-- ipairs() dung lai o phan tu nil dau tien. Bang kieu { data.Eggs, data.Items, ... }
-- thuong co "lo" nil, nen phai loc truoc khi lap.
local function compact(t, n)
    local out = {}
    for i = 1, n do
        local v = t[i]
        if v ~= nil and v ~= false then out[#out + 1] = v end
    end
    return out
end

local RECIPES = {
    ["Blue Extract"] = { { Item = "Blueberry", Amount = 50 } },
    ["Red Extract"] = { { Item = "Strawberry", Amount = 50 } },
    ["Oil"] = { { Item = "Sunflower Seed", Amount = 50 } },
    ["Enzymes"] = { { Item = "Pineapple", Amount = 50 } },
    ["Gumdrop"] = { { Item = "Strawberry", Amount = 3 }, { Item = "Blueberry", Amount = 3 }, { Item = "Pineapple", Amount = 3 } },
    ["Gumdrops"] = { { Item = "Strawberry", Amount = 3 }, { Item = "Blueberry", Amount = 3 }, { Item = "Pineapple", Amount = 3 } },
    ["Glue"] = { { Item = "Gumdrop", Amount = 50 } },
    ["Tropical Drink"] = { { Item = "Enzymes", Amount = 2 }, { Item = "Oil", Amount = 2 }, { Item = "Coconut", Amount = 10 } },
    ["Tropical Drinks"] = { { Item = "Enzymes", Amount = 2 }, { Item = "Oil", Amount = 2 }, { Item = "Coconut", Amount = 10 } }
}

local RAW_FIELD_ITEMS = {
    ["Blueberry"] = true,
    ["Strawberry"] = true,
    ["Sunflower Seed"] = true,
    ["Pineapple"] = true,
    ["Coconut"] = true
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

local function isRawFieldItem(itemName)
    if not itemName then return false end
    if RAW_FIELD_ITEMS[itemName] then return true end
    local clean = tostring(itemName):gsub("[%s%-_']", ""):lower()
    for k, _ in pairs(RAW_FIELD_ITEMS) do
        if k:gsub("[%s%-_']", ""):lower() == clean then
            return true
        end
    end
    if clean:sub(-1) == "s" then
        local sing = clean:sub(1, -2)
        for k, _ in pairs(RAW_FIELD_ITEMS) do
            if k:gsub("[%s%-_']", ""):lower() == sing then
                return true
            end
        end
    end
    return false
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
    { Bees = 25, Name = "Bucko Guard", Type = "Guard", Ingredients = { { Item = "Blueberry", Amount = 100 }, { Item = "Blue Extract", Amount = 5 }, { Item = "Stinger", Amount = 15 } } },
    { Bees = 25, Name = "Riley Guard", Type = "Guard", Ingredients = { { Item = "Strawberry", Amount = 100 }, { Item = "Red Extract", Amount = 5 }, { Item = "Stinger", Amount = 15 } } },
    { Bees = 25, Name = "Candy Planter", Type = "Planter", Ingredients = { { Item = "Gumdrop", Amount = 100 } } },
    { Bees = 25, Name = "Glider", Type = "Glider" },
    { Bees = 25, Name = "Golden Rake", Type = "Tool" },
    { Bees = 25, Name = "Porcelain Dipper", Type = "Tool" },
    { Bees = 25, Name = "Porcelain Port-O-Hive", Type = "Bag" },
    { Bees = 25, Name = "Blue Clay Planter", Type = "Planter", Ingredients = { { Item = "Blueberry", Amount = 50 }, { Item = "Soft Wax", Amount = 10 } } },
    { Bees = 25, Name = "Red Clay Planter", Type = "Planter", Ingredients = { { Item = "Strawberry", Amount = 50 }, { Item = "Soft Wax", Amount = 10 } } },
    { Bees = 20, Name = "Bubble Mask", Type = "Hat", Ingredients = { { Item = "Blueberry", Amount = 250 }, { Item = "Blue Extract", Amount = 50 }, { Item = "Oil", Amount = 25 }, { Item = "Glitter", Amount = 25 } } },
    { Bees = 20, Name = "Honey Mask", Type = "Hat", Ingredients = { { Item = "Oil", Amount = 50 }, { Item = "Enzymes", Amount = 25 }, { Item = "Golden Egg", Amount = 5 }, { Item = "Treat", Amount = 9999 } } },
    { Bees = 20, Name = "Fire Mask", Type = "Hat", Ingredients = { { Item = "Strawberry", Amount = 250 }, { Item = "Red Extract", Amount = 50 }, { Item = "Enzymes", Amount = 25 }, { Item = "Glitter", Amount = 25 } } },
    { Bees = 20, Name = "Cobalt Guard", Type = "Guard", Ingredients = { { Item = "Blue Extract", Amount = 100 }, { Item = "Stinger", Amount = 100 }, { Item = "Glue", Amount = 50 }, { Item = "Oil", Amount = 25 }, { Item = "Enzymes", Amount = 25 } } },
    { Bees = 20, Name = "Crimson Guard", Type = "Guard", Ingredients = { { Item = "Red Extract", Amount = 100 }, { Item = "Stinger", Amount = 100 }, { Item = "Glue", Amount = 50 }, { Item = "Oil", Amount = 25 }, { Item = "Enzymes", Amount = 25 } } },
    { Bees = 25, Name = "Golden Gushers", Type = "Sprinkler" },
    { Bees = 35, Name = "Tacky Planter", Type = "Planter", Ingredients = { { Item = "Sunflower Seed", Amount = 500 }, { Item = "Soft Wax", Amount = 25 }, { Item = "Hard Wax", Amount = 5 } } },
    { Bees = 20, Name = "Diamond Mask", Type = "Hat", Ingredients = { { Item = "Diamond Egg", Amount = 5 }, { Item = "Blue Extract", Amount = 250 }, { Item = "Oil", Amount = 150 }, { Item = "Glitter", Amount = 100 } } },
    { Bees = 20, Name = "Demon Mask", Type = "Hat", Ingredients = { { Item = "Red Extract", Amount = 250 }, { Item = "Stinger", Amount = 500 }, { Item = "Enzymes", Amount = 150 }, { Item = "Glitter", Amount = 100 } } },
    { Bees = 20, Name = "Gummy Mask", Type = "Hat", Ingredients = { { Item = "Glue", Amount = 250 }, { Item = "Glitter", Amount = 100 }, { Item = "Oil", Amount = 100 }, { Item = "Enzymes", Amount = 100 } } },
    { Bees = 35, Name = "Diamond Drenchers", Type = "Sprinkler" },
    { Bees = 35, Name = "Coconut Canister", Type = "Bag", Ingredients = { { Item = "Coconut", Amount = 150 }, { Item = "Tropical Drink", Amount = 150 }, { Item = "Red Extract", Amount = 250 }, { Item = "Blue Extract", Amount = 250 } } },
    { Bees = 35, Name = "Pesticide Planter", Type = "Planter", Ingredients = { { Item = "Strawberry", Amount = 500 }, { Item = "Soft Wax", Amount = 50 }, { Item = "Hard Wax", Amount = 15 } } },
    { Bees = 35, Name = "Coconut Clogs", Type = "Boots", Ingredients = { { Item = "Coconut", Amount = 150 }, { Item = "Tropical Drink", Amount = 50 }, { Item = "Glue", Amount = 100 }, { Item = "Oil", Amount = 100 } } },
    { Bees = 35, Name = "The Supreme Saturator", Type = "Sprinkler" },
    { Bees = 35, Name = "Tide Popper", Type = "Tool", Ingredients = { { Item = "Blue Extract", Amount = 1500 }, { Item = "Stinger", Amount = 150 }, { Item = "Tropical Drink", Amount = 150 }, { Item = "Swirled Wax", Amount = 75 }, { Item = "Super Smoothie", Amount = 50 } } },
    { Bees = 35, Name = "Dark Scythe", Type = "Tool", Ingredients = { { Item = "Red Extract", Amount = 1500 }, { Item = "Super Smoothie", Amount = 50 }, { Item = "Caustic Wax", Amount = 50 }, { Item = "Hard Wax", Amount = 100 }, { Item = "Stinger", Amount = 200 } } },
    { Bees = 35, Name = "Gummyballer", Type = "Tool", Ingredients = { { Item = "Glue", Amount = 1500 }, { Item = "Gumdrop", Amount = 1500 }, { Item = "Super Smoothie", Amount = 50 }, { Item = "Caustic Wax", Amount = 50 }, { Item = "Swirled Wax", Amount = 50 } } },
    { Bees = 35, Name = "Hydroponic Planter", Type = "Planter", Ingredients = { { Item = "Blue Extract", Amount = 100 }, { Item = "Soft Wax", Amount = 50 }, { Item = "Hard Wax", Amount = 15 }, { Item = "Caustic Wax", Amount = 5 } } },
    { Bees = 35, Name = "Heat-Treated Planter", Type = "Planter", Ingredients = { { Item = "Red Extract", Amount = 100 }, { Item = "Soft Wax", Amount = 50 }, { Item = "Hard Wax", Amount = 15 }, { Item = "Caustic Wax", Amount = 5 } } },
    { Bees = 35, Name = "Petal Planter", Type = "Planter", Ingredients = { { Item = "Spirit Petal", Amount = 1 }, { Item = "Enzymes", Amount = 100 }, { Item = "Soft Wax", Amount = 100 }, { Item = "Hard Wax", Amount = 30 }, { Item = "Caustic Wax", Amount = 10 }, { Item = "Swirled Wax", Amount = 5 } } },
    { Bees = 35, Name = "Gummy Boots", Type = "Boots", Ingredients = { { Item = "Glue", Amount = 500 }, { Item = "Glitter", Amount = 300 }, { Item = "Red Extract", Amount = 250 }, { Item = "Blue Extract", Amount = 250 } } },
    { Bees = 35, Name = "Coconut Belt", Type = "Belt", Ingredients = { { Item = "Coconut", Amount = 500 }, { Item = "Tropical Drink", Amount = 250 }, { Item = "Glue", Amount = 150 }, { Item = "Enzymes", Amount = 150 }, { Item = "Super Smoothie", Amount = 25 } } },
    { Bees = 35, Name = "Plenty Planter", Type = "Planter" },
    { Bees = 35, Name = "Petal Belt", Type = "Belt", Ingredients = { { Item = "Spirit Petal", Amount = 1 }, { Item = "Star Jelly", Amount = 25 }, { Item = "Glitter", Amount = 50 }, { Item = "Glue", Amount = 25 }, { Item = "Enzymes", Amount = 75 } } },
    { Bees = 35, Name = "Petal Wand", Type = "Tool", Ingredients = { { Item = "Spirit Petal", Amount = 1 }, { Item = "Star Jelly", Amount = 10 }, { Item = "Glitter", Amount = 25 }, { Item = "Enzymes", Amount = 75 } } }
}

local _serverStatsCache = nil
local _lastServerStatsFetch = 0

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
        if not _serverStatsCache or (tick() - _lastServerStatsFetch > 25) then
            local events = RS:FindFirstChild("Events")
            if events and events:FindFirstChild("RetrievePlayerStats") then
                local ok, res = pcall(function() return events.RetrievePlayerStats:InvokeServer() end)
                if ok and type(res) == "table" then
                    _serverStatsCache = res
                    _lastServerStatsFetch = tick()
                end
            end
        end
        if _serverStatsCache then
            if not data then
                data = _serverStatsCache
            else
                for k, v in pairs(_serverStatsCache) do
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
    if not data or not item then return 0 end
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

    local cItem = item:gsub("[%s%-_']", ""):lower()
    local folders = compact({ data.Eggs, data.Inventory, data.Items, data.Totals, data }, 5)
    for _, folder in ipairs(folders) do
        if type(folder) == "table" then
            for _, k in ipairs(keys) do
                if folder[k] ~= nil then
                    local num = tonumber(folder[k])
                    if num then return num end
                end
            end
            for k, v in pairs(folder) do
                if type(k) == "string" and tostring(k):gsub("[%s%-_']", ""):lower() == cItem then
                    local num = tonumber(v)
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
    ["glider"] = "Glider"
}

local function resolveItemName(raw)
    if not raw then return nil end
    local clean = tostring(raw):gsub("[%s%-_':%[%]%(%)]", ""):lower()
    if ITEM_ALIASES[clean] then return ITEM_ALIASES[clean] end
    -- khop chuoi con: chon alias DAI NHAT (xac dinh), khong phu thuoc thu tu pairs()
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

-- Chi khop CHINH XAC (alias hoac ten trong route). Dung cho text lay tu UI.
local function resolveItemNameStrict(raw)
    if not raw then return nil end
    local clean = tostring(raw):gsub("[%s%-_':%[%]%(%)]", ""):lower()
    if clean == "" then return nil end
    if ITEM_ALIASES[clean] then return ITEM_ALIASES[clean] end
    for _, m in ipairs(FullProgressionRoute) do
        if m.Name:gsub("[%s%-_':%[%]%(%)]", ""):lower() == clean then return m.Name end
    end
    return nil
end

local function canonKey(s)
    return tostring(resolveItemName(s) or s):gsub("[%s%-_']", ""):lower()
end

-- 0 / false / "" / {} khong tinh la "so huu" (trong Lua so 0 van la truthy!)
local function truthyOwned(v)
    if v == nil or v == false then return false end
    local t = type(v)
    if t == "number" then return v > 0 end
    if t == "string" then return v ~= "" and v ~= "0" end
    if t == "table" then return next(v) ~= nil end
    return true
end

local function isKnownProgressionItem(name)
    if not name or type(name) ~= "string" or #name < 2 then return false end
    local clean = name:gsub("[%s%-_':%[%]%(%)]", ""):lower()
    if ITEM_ALIASES[clean] then return true end
    for _, milestone in ipairs(FullProgressionRoute) do
        local c = milestone.Name:gsub("[%s%-_':%[%]%(%)]", ""):lower()
        if c == clean then return true end
    end
    return false
end

local function normalizeEquipSlot(val, tierTable)
    if val == nil then return nil end
    if type(val) == "table" then
        val = val.Name or val.Item or val.Type or val.Id
        if val == nil then return nil end
    end
    local c = tostring(val):gsub("[%s%-_']", ""):lower()
    if tierTable[c] then return c end
    local resolved = resolveItemName(val)
    if resolved then
        local rc = tostring(resolved):gsub("[%s%-_']", ""):lower()
        if tierTable[rc] then return rc end
    end
    return nil
end

local _cachedAtlasSettings = nil
local _gcScanAt = { settings = 0, route = 0 }

local function isAtlasSettingsTable(t)
    if type(t) ~= "table" then return false end
    local ok, hasToys = pcall(function() return t.toys end)
    local ok2, hasFarm = pcall(function() return t.autofarm or t.farming or (t.toys and t.toys.route) end)
    return ok and ok2 and type(hasToys) == "table" and (type(hasFarm) == "table" or hasFarm ~= nil)
end

local function findAtlasSettings()
    if _cachedAtlasSettings and isAtlasSettingsTable(_cachedAtlasSettings) then
        return _cachedAtlasSettings
    end

    local roots = compact({ getgenv and getgenv(), _G, shared }, 3)
    for _, root in ipairs(roots) do
        if type(root) == "table" then
            if isAtlasSettingsTable(root) then
                _cachedAtlasSettings = root
                return root
            end
            if root.Atlas and type(root.Atlas) == "table" then
                if isAtlasSettingsTable(root.Atlas.Settings) then
                    _cachedAtlasSettings = root.Atlas.Settings
                    return root.Atlas.Settings
                end
                if isAtlasSettingsTable(root.Atlas) then
                    _cachedAtlasSettings = root.Atlas
                    return root.Atlas
                end
            end
            if isAtlasSettingsTable(root.Settings) then
                _cachedAtlasSettings = root.Settings
                return root.Settings
            end
            if isAtlasSettingsTable(root.Config) then
                _cachedAtlasSettings = root.Config
                return root.Config
            end
            for k, v in pairs(root) do
                if type(v) == "table" and k ~= "_G" and k ~= "shared" and k ~= "game" and k ~= "workspace" and k ~= "Enum" then
                    if isAtlasSettingsTable(v) then
                        _cachedAtlasSettings = v
                        return v
                    end
                    if isAtlasSettingsTable(v.Settings) then
                        _cachedAtlasSettings = v.Settings
                        return v.Settings
                    end
                end
            end
        end
    end

    if getgc and (tick() - _gcScanAt.settings > 60) then
        _gcScanAt.settings = tick()
        local ok, gc = pcall(getgc, true)
        if not ok or type(gc) ~= "table" then ok, gc = pcall(getgc) end
        if ok and type(gc) == "table" then
            for _, obj in ipairs(gc) do
                if isAtlasSettingsTable(obj) then
                    _cachedAtlasSettings = obj
                    return obj
                end
            end
        end
    end

    return nil
end

local _knownOwnedPlanters = {}

local function isPlanterOwned(cleanName, rawClean, canonical, data)
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

    if _knownOwnedPlanters[cleanName] or (canonical and _knownOwnedPlanters[canonical:lower()]) then
        return true
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
                _knownOwnedPlanters[cleanName] = true
                return true
            end
        end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if matches(item.Name) then
                _knownOwnedPlanters[cleanName] = true
                return true
            end
        end
    end

    if data then
        if (canonical and getItemAmount(canonical, data) > 0)
            or getItemAmount(cleanName, data) > 0
            or getItemAmount(rawClean, data) > 0
            or (rootPlanter ~= "" and getItemAmount(rootPlanter, data) > 0)
            or (rootPlanter ~= "" and getItemAmount(rootPlanter .. " Planter", data) > 0) then
            _knownOwnedPlanters[cleanName] = true
            return true
        end

        local pTables = {
            data.Planters,
            data.PlanterTypes,
            data.PurchasedPlanters,
            data.PlanterInventory,
            data.ActivePlanters,
            data.PlantedPlanters,
            data.Eggs,
            data.Items,
            data.Inventory,
            data.Equipment,
            data.Accessories
        }
        for _, tbl in ipairs(compact(pTables, 11)) do
            if type(tbl) == "table" then
                for k, v in pairs(tbl) do
                    if matches(k) then
                        _knownOwnedPlanters[cleanName] = true
                        return true
                    end
                    if type(v) == "string" and matches(v) then
                        _knownOwnedPlanters[cleanName] = true
                        return true
                    end
                    if type(v) == "table" then
                        if matches(v.Type) or matches(v.Name) or matches(v.PlanterType) or matches(v.Item) or matches(v.Id) then
                            _knownOwnedPlanters[cleanName] = true
                            return true
                        end
                        for k2, v2 in pairs(v) do
                            if matches(k2) or (type(v2) == "string" and matches(v2)) then
                                _knownOwnedPlanters[cleanName] = true
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
                _knownOwnedPlanters[cleanName] = true
                return true
            end
            if desc:IsA("StringValue") and matches(desc.Value) then
                _knownOwnedPlanters[cleanName] = true
                return true
            end
        end
    end

    pcall(function()
        if player:FindFirstChild("PlayerGui") then
            for _, desc in ipairs(player.PlayerGui:GetDescendants()) do
                if desc:IsA("TextLabel") and matches(desc.Text) then
                    local isShop = false
                    local cur = desc
                    for _ = 1, 6 do
                        if not cur then break end
                        local n = cur.Name:lower()
                        if n:find("shop") or n:find("dapper") then isShop = true; break end
                        cur = cur.Parent
                    end
                    if not isShop then
                        _knownOwnedPlanters[cleanName] = true
                        return
                    end
                end
            end
        end
    end)
    if _knownOwnedPlanters[cleanName] then return true end

    local pName = player.Name:lower()
    local pUserId = tostring(player.UserId)
    local pDisplay = player.DisplayName and player.DisplayName:lower() or pName

    local searchContainers = {
        workspace:FindFirstChild("Planters"),
        workspace:FindFirstChild("ActivePlanters"),
        workspace:FindFirstChild("CorePlanters"),
        workspace:FindFirstChild("Fields")
    }

    for _, c in ipairs(compact(searchContainers, 4)) do
        if c then
            for _, desc in ipairs(c:GetDescendants()) do
                if desc:IsA("TextLabel") then
                    local t = desc.Text:lower()
                    if (t:find(pName, 1, true) or t:find(pDisplay, 1, true) or t:find(pUserId, 1, true))
                        and (t:find(rootPlanter, 1, true) or t:find("planter", 1, true)) then
                        _knownOwnedPlanters[cleanName] = true
                        return true
                    end
                end
                if desc:IsA("Model") then
                    local isMine = false
                    local owner = desc:FindFirstChild("Owner") or desc:FindFirstChild("Player") or desc:FindFirstChild("User")
                    if owner then
                        local ov = tostring(owner.Value):lower()
                        if ov == pName or ov == pUserId or (owner:IsA("ObjectValue") and (owner.Value == player or (char and owner.Value == char))) then
                            isMine = true
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
                            _knownOwnedPlanters[cleanName] = true
                            return true
                        end
                        local pType = desc:FindFirstChild("Type") or desc:FindFirstChild("PlanterType") or desc:FindFirstChild("PlantType")
                        if pType and matches(pType.Value) then
                            _knownOwnedPlanters[cleanName] = true
                            return true
                        end
                        local aType = desc:GetAttribute("Type") or desc:GetAttribute("PlanterType")
                        if aType and matches(aType) then
                            _knownOwnedPlanters[cleanName] = true
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
        if type(pSettings) == "table" then
            for k, v in pairs(pSettings) do
                if matches(k) or (type(v) == "string" and matches(v)) then
                    _knownOwnedPlanters[cleanName] = true
                    return true
                end
                if type(v) == "table" and (matches(v.Type) or matches(v.Name) or matches(v.Planter)) then
                    _knownOwnedPlanters[cleanName] = true
                    return true
                end
            end
        end
    end

    return false
end

local function isItemOwned(itemName, itemType, char, data)
    if not itemName then return false end
    local canonical = resolveItemName(itemName) or itemName
    local cleanName = tostring(canonical):gsub("[%s%-_']", ""):lower()
    local rawClean = tostring(itemName):gsub("[%s%-_']", ""):lower()

    if (itemType == "Planter" or cleanName:find("planter") or rawClean:find("planter")) then
        if isPlanterOwned(cleanName, rawClean, canonical, data) then
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

    curTool = normalizeEquipSlot(curTool, TOOL_TIERS)
    curBag = normalizeEquipSlot(curBag, BAG_TIERS)
    curBoots = normalizeEquipSlot(curBoots, BOOTS_TIERS)
    curBelt = normalizeEquipSlot(curBelt, BELT_TIERS)
    curHat = normalizeEquipSlot(curHat, HAT_TIERS)
    curSprinkler = normalizeEquipSlot(curSprinkler, SPRINKLER_TIERS)
    curBlueGuard = normalizeEquipSlot(curBlueGuard, BLUE_GUARD_TIERS)
    curRedGuard = normalizeEquipSlot(curRedGuard, RED_GUARD_TIERS)
    if curGlider then
        local gc = tostring(curGlider):gsub("[%s%-_']", ""):lower()
        if gc ~= "glider" then curGlider = nil end
    end

    local function checkMatch(val)
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
            checkMatch(child.Name)
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
            checkMatch(child.Name)
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
                checkMatch(v)
                if truthyOwned(v) then checkMatch(k) end
            elseif type(v) == "table" then
                for k2, v2 in pairs(v) do
                    if truthyOwned(v2) then checkMatch(k2) end
                    if type(v2) == "string" or type(v2) == "number" then checkMatch(v2) end
                end
            end
        end
    end

    local SPECIAL_MASKS = {
        ["honeymask"] = true, ["bubblemask"] = true, ["firemask"] = true,
        ["gummymask"] = true, ["demonmask"] = true, ["diamondmask"] = true, ["diamask"] = true
    }

    -- Tier cao HON moi suy ra so huu tier thap. Cung tier (Tide Popper / Dark Scythe /
    -- Gummyballer, Blue / Red Port-O-Hive...) thi phai trung chinh xac ten item.
    local function slotOwned(cur, tierTbl, skipTier)
        if not cur then return false end
        local c = tostring(cur):gsub("[%s%-_']", ""):lower()
        if c == cleanName or c == rawClean then return true end
        if canonKey(c) == cleanName then return true end
        if skipTier then return false end
        local reqTier = tierTbl[cleanName] or tierTbl[rawClean]
        local curTier = tierTbl[c]
        return (reqTier and curTier and curTier > reqTier) and true or false
    end

    if slotOwned(curTool, TOOL_TIERS)
        or slotOwned(curBag, BAG_TIERS)
        or slotOwned(curBoots, BOOTS_TIERS)
        or slotOwned(curBelt, BELT_TIERS)
        or slotOwned(curHat, HAT_TIERS, SPECIAL_MASKS[cleanName] or SPECIAL_MASKS[rawClean])
        or slotOwned(curSprinkler, SPRINKLER_TIERS)
        or slotOwned(curBlueGuard, BLUE_GUARD_TIERS)
        or slotOwned(curRedGuard, RED_GUARD_TIERS) then
        return true
    end

    if (cleanName == "glider" or rawClean == "glider") and curGlider then
        return true
    end

    local eqSources = { eq, data, data and data.Accessories, data and data.Equipment, data and data.Items, data and data.Inventory }
    for _, src in ipairs(compact(eqSources, 6)) do
        if type(src) == "table" then
            if truthyOwned(src[canonical]) or truthyOwned(src[itemName]) or truthyOwned(src[cleanName]) or truthyOwned(src[rawClean]) then return true end
            for k, val in pairs(src) do
                local kClean = tostring(k):gsub("[%s%-_']", ""):lower()
                local vClean = tostring(val):gsub("[%s%-_']", ""):lower()
                if ((kClean == cleanName or kClean == rawClean) and truthyOwned(val)) or vClean == cleanName or vClean == rawClean then
                    return true
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

local VIM = nil
pcall(function() VIM = game:GetService("VirtualInputManager") end)
local VU = nil
pcall(function() VU = game:GetService("VirtualUser") end)

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

local function isGuiVisibleOnScreen(gui)
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
    if not isGuiVisibleOnScreen(gui) then return end
    local scroll = gui:FindFirstAncestorWhichIsA("ScrollingFrame")
    if scroll and scroll.AbsoluteSize.Y > 0 then
        pcall(function()
            local relY = gui.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
            scroll.CanvasPosition = Vector2.new(0, math.max(0, relY - scroll.AbsoluteSize.Y / 2))
            task.wait(0.04)
        end)
    end
end

local function clickElement(gui)
    if not gui or not gui:IsA("GuiObject") then return false end
    local fired = false

    local clickable = gui
    if not (gui:IsA("TextButton") or gui:IsA("ImageButton")) then
        clickable = gui:FindFirstAncestorWhichIsA("TextButton")
            or gui:FindFirstAncestorWhichIsA("ImageButton")
            or gui
    end

    bringIntoView(clickable)

    pcall(function()
        if getconnections then
            if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
                for _, c in ipairs(getconnections(clickable.MouseButton1Click)) do
                    if c.Fire then c:Fire(); fired = true end
                    if c.Function then pcall(c.Function); fired = true end
                end
                for _, c in ipairs(getconnections(clickable.Activated)) do
                    if c.Fire then c:Fire(); fired = true end
                    if c.Function then pcall(c.Function); fired = true end
                end
            end
            for _, c in ipairs(getconnections(clickable.MouseButton1Down)) do
                if c.Fire then c:Fire(); fired = true end
                if c.Function then pcall(c.Function); fired = true end
            end
        end

        if firesignal then
            if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
                pcall(function() firesignal(clickable.MouseButton1Click) end)
                pcall(function() firesignal(clickable.Activated) end)
            end
            pcall(function() firesignal(clickable.MouseButton1Down) end)
            fired = true
        end

        if not fired and isGuiVisibleOnScreen(clickable) then
            local x = clickable.AbsolutePosition.X + clickable.AbsoluteSize.X / 2
            local y = clickable.AbsolutePosition.Y + clickable.AbsoluteSize.Y / 2
            if VIM then
                pcall(function()
                    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
                    task.wait(0.03)
                    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
                    fired = true
                end)
            end
            if not fired and VU then
                pcall(function()
                    VU:Button1Down(Vector2.new(x, y))
                    task.wait(0.02)
                    VU:Button1Up(Vector2.new(x, y))
                    fired = true
                end)
            end
        end
    end)
    return fired
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

local function getFarmingSectionAndDropdown(root)
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
                if txt == name and isGuiVisibleOnScreen(d) then
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

local function setAtlasFieldViaUI(targetField)
    local uiRoots = {}
    pcall(function() if gethui then table.insert(uiRoots, gethui()) end end)
    pcall(function() table.insert(uiRoots, CoreGui) end)
    pcall(function() table.insert(uiRoots, player:FindFirstChild("PlayerGui")) end)

    local targetClean = targetField:gsub("[%s%-_']", ""):lower()

    for _, root in ipairs(uiRoots) do
        if root then
            local section, farmingHeader, headerTxt = getFarmingSectionAndDropdown(root)
            local isFarmingVisible = farmingHeader and isGuiVisibleOnScreen(farmingHeader)

            local prevTabName, prevTabBtn = nil, nil
            local switchedTab = false

            if not isFarmingVisible then
                prevTabName, prevTabBtn = findActiveAtlasTab(root)
                local farmingTabBtn = findAtlasTabButton(root, "farming")
                if farmingTabBtn then
                    clickElement(farmingTabBtn)
                    task.wait(0.1)
                    switchedTab = true
                    section, farmingHeader, headerTxt = getFarmingSectionAndDropdown(root)
                end
            end

            if section and farmingHeader then
                local curVal = headerTxt and headerTxt:match("^[Ff]ield%s*:%s*(.+)")
                if curVal and curVal:gsub("[%s%-_']", ""):lower() == targetClean then
                    if switchedTab and prevTabBtn then
                        clickElement(prevTabBtn)
                    end
                    return true, "ui_already_set"
                end

                local clickTarget = farmingHeader:IsA("TextButton") and farmingHeader
                    or farmingHeader:FindFirstAncestorWhichIsA("TextButton")
                    or farmingHeader:FindFirstAncestorWhichIsA("ImageButton")
                    or farmingHeader.Parent

                clickElement(clickTarget)
                task.wait(0.12)

                local searchContainers = { section, root }
                local foundAndClicked = false

                for _, container in ipairs(searchContainers) do
                    if not foundAndClicked and container then
                        for _, btn in ipairs(container:GetDescendants()) do
                            if (btn:IsA("TextButton") or btn:IsA("TextLabel") or btn:IsA("ImageButton")) and btn ~= farmingHeader and btn ~= clickTarget and btn.Name ~= "AutoProg_HUD" then
                                local rawTxt = getGuiText(btn):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
                                if rawTxt:gsub("[%s%-_']", ""):lower() == targetClean then
                                    local clicked = clickElement(btn)
                                    if clicked then
                                        foundAndClicked = true
                                        task.wait(0.05)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end

                if switchedTab and prevTabBtn then
                    task.wait(0.04)
                    clickElement(prevTabBtn)
                end

                if foundAndClicked then
                    return true, switchedTab and "ui_switched_and_clicked" or "ui_opened_and_clicked"
                end
            elseif switchedTab and prevTabBtn then
                clickElement(prevTabBtn)
            end
        end
    end
    return false, "ui_not_found"
end

local _lastAppliedField = nil

local function setAtlasField(field)
    if not field or field == "Idle" or field == "Unchanged" then return end

    local okUI, methodUI = setAtlasFieldViaUI(field)

    local settings = findAtlasSettings()
    if settings then
        if settings.autofarm and type(settings.autofarm) == "table" then
            settings.autofarm.field1 = field
            settings.autofarm.field2 = field
            settings.autofarm.field3 = field
            settings.autofarm.field = field
            if type(settings.autofarm.fields) == "table" then
                settings.autofarm.fields[1] = field
            end
        end
        if settings.farming and type(settings.farming) == "table" then
            settings.farming.field1 = field
            settings.farming.field = field
        end
        settings["farming.field1"] = field
        settings["autofarm.field1"] = field
        settings.Field = field
        settings.field = field
    end

    if getgenv then
        if getgenv().Atlas and type(getgenv().Atlas) == "table" then
            getgenv().Atlas.Field = field
            getgenv().Atlas.CurrentField = field
            if getgenv().Atlas.Settings and type(getgenv().Atlas.Settings) == "table" then
                getgenv().Atlas.Settings.Field = field
                if getgenv().Atlas.Settings.autofarm then
                    getgenv().Atlas.Settings.autofarm.field1 = field
                    getgenv().Atlas.Settings.autofarm.field2 = field
                    getgenv().Atlas.Settings.autofarm.field3 = field
                end
            end
            if type(getgenv().Atlas.SetField) == "function" then
                pcall(getgenv().Atlas.SetField, field)
            end
        end
        if getgenv().Config and type(getgenv().Config) == "table" then
            getgenv().Config.Field = field
            if getgenv().Config.autofarm then
                getgenv().Config.autofarm.field1 = field
                getgenv().Config.autofarm.field2 = field
                getgenv().Config.autofarm.field3 = field
            end
        end
    end

    if _lastAppliedField ~= field then
        print(string.format("[Auto Prog] Switched farm field -> %s (%s)", field, okUI and methodUI or "ram_settings"))
        _lastAppliedField = field
    end
end

local _originalDefaultFields = {
    [0] = "Dandelion Field",
    [5] = "Bamboo Field",
    [10] = "Pineapple Patch",
    [15] = "Pine Tree Forest"
}

local _routeDefaultFields = {}
for k, v in pairs(_originalDefaultFields) do
    _routeDefaultFields[k] = v
end

local function getDefaultProgressionField(beeCount)
    local bestBees = -1
    local bestField = "Pine Tree Forest"
    for reqBees, fld in pairs(_routeDefaultFields) do
        if beeCount >= reqBees and reqBees > bestBees then
            bestBees = reqBees
            bestField = fld
        end
    end
    return bestField
end

local function resolveMissingMaterial(item, neededAmount, data, beeCount)
    local invCount = getItemAmount(item, data)
    local deficit = neededAmount - invCount
    if deficit <= 0 then return nil end

    local recipe = getRecipe(item)
    if recipe then
        local firstUnfarmMat, firstUnfarmAmt = nil, 0
        for _, sub in ipairs(recipe) do
            local totalSubNeeded = deficit * sub.Amount
            local missingMat, missingAmt, targetField, isUnfarm = resolveMissingMaterial(sub.Item, totalSubNeeded, data, beeCount)
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
        local field = getTargetField(item, beeCount)
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
    if st == "purchase" or st == "buy" or st == "craft" then return true end
    if step.config == "farming.field1" or step.group or step.target or step.gear then return true end
    return false
end

local function extractPurchaseList(tbl, depth)
    if type(tbl) ~= "table" or ((depth or 0) > 8) then return nil end
    local items = {}
    local seen = {}

    local function scan(t, d)
        if type(t) ~= "table" or d > 8 then return end
        if seen[t] then return end
        seen[t] = true

        if t.config == "farming.field1" and t.data and type(t.data) == "string" then
            local reqBees = tonumber(t.required_bees or t.Bees) or 0
            _routeDefaultFields[reqBees] = t.data
        end

        local p = t.purchase or t.Purchase
        if p then
            local reqBees = tonumber(t.required_bees or t.Bees or t.req_bees) or 0
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

        local stepType = tostring(t.Type or t.type or ""):lower()
        if (stepType == "purchase" or stepType == "buy" or stepType == "craft") and (t.Data or t.data) then
            local data = t.Data or t.data
            local reqBees = tonumber(t.Bees or t.required_bees or t.req_bees) or 0
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

        local directName = t.target or t.Target or t.gear or t.Gear
        if directName and type(directName) == "string" then
            local reqBees = tonumber(t.Bees or t.required_bees) or 0
            table.insert(items, { Name = directName, Bees = reqBees })
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

local function findAtlasRouteInMemory()
    local settings = findAtlasSettings()
    if settings then
        if settings.toys and type(settings.toys) == "table" and settings.toys.route then
            return settings.toys.route
        end
        if settings.route and type(settings.route) == "table" then
            return settings.route
        end
    end

    local roots = compact({ getgenv and getgenv(), _G, shared }, 3)
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

    if getgc and (tick() - _gcScanAt.route > 60) then
        _gcScanAt.route = tick()
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

local _lastRouteFile = "none"
local _routeSourceName = "none"

local function readAtlasFileRoute()
    if not (readfile and isfile) then return nil end

    local knownPaths = {
        "atlas1/preset1.json",
        "atlas1/preset 1.json",
        "atlas1/preset2.json",
        "atlas1/settings.json",
        "atlas1/config.json",
        "atlas1/routes/default.json",
        "atlas1/routes/route.json",
        "atlas1/routes/progression.json",
        "atlas1/route.json",
        "Atlas/preset1.json",
        "Atlas/settings.json",
        "Atlas/routes/default.json",
        "Atlas/routes/route.json",
        "Atlas/routes/progression.json",
        "Atlas/route.json",
        "routes/default.json",
        "routes/route.json",
        "routes/progression.json",
        "route.json",
        "default.json"
    }

    local filesToTry = {}
    local customPath = getgenv and (getgenv().AtlasConfigPath or getgenv().AtlasRouteFile or getgenv().AtlasPresetFile)
    if customPath and isfile(customPath) then
        table.insert(filesToTry, customPath)
    end

    local settings = findAtlasSettings()
    if settings then
        local prof = settings.selected_profile or settings.profile or settings.preset or settings.selected_preset or settings.config_name
        if type(prof) == "string" and prof ~= "" then
            local pName = prof:lower():find("%.json$") and prof or (prof .. ".json")
            table.insert(filesToTry, pName)
            table.insert(filesToTry, "atlas1/" .. pName)
            table.insert(filesToTry, "atlas1/routes/" .. pName)
            table.insert(filesToTry, "Atlas/" .. pName)
            table.insert(filesToTry, "Atlas/routes/" .. pName)
        end
    end

    for _, p in ipairs(knownPaths) do
        table.insert(filesToTry, p)
    end

    if listfiles then
        local dirs = { "atlas1", "atlas1/routes", "Atlas", "Atlas/routes", "routes", "presets" }
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

    local visited = {}
    for _, path in ipairs(filesToTry) do
        if not visited[path] and isfile(path) then
            visited[path] = true
            local ok, content = pcall(readfile, path)
            _lastRouteFile = path
            if ok and content and content ~= "" then
                local cLow = content:lower()
                if cLow:find('"purchase"') or cLow:find('"route"') or cLow:find('"toys"') or cLow:find('"farming.field1"') or cLow:find('"diamask"') then
                    local s, decoded = pcall(function() return HttpService:JSONDecode(content) end)
                    if s and type(decoded) == "table" then
                        if decoded.toys and decoded.toys.route then
                            return decoded.toys.route
                        elseif decoded.route then
                            return decoded.route
                        elseif #decoded > 0 then
                            for _, step in ipairs(decoded) do
                                if isRouteStep(step) then
                                    return decoded
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

local function getUserDefinedRoute()
    local roots = compact({ getgenv and getgenv(), _G, shared }, 3)
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

local _cachedParsedRoute = nil
local _lastRouteSourceTime = 0
local _routeFound = false
local _lastCustomRouteVal = nil

local function getAtlasRoute()
    local customUserRoute = getUserDefinedRoute()
    if customUserRoute ~= _lastCustomRouteVal then
        _lastCustomRouteVal = customUserRoute
        _cachedParsedRoute = nil
    end

    if _cachedParsedRoute and (tick() - _lastRouteSourceTime < 30) then
        return _cachedParsedRoute
    end

    for k in pairs(_routeDefaultFields) do
        _routeDefaultFields[k] = nil
    end
    for k, v in pairs(_originalDefaultFields) do
        _routeDefaultFields[k] = v
    end

    local rawRoute, routeSrc
    if customUserRoute then
        rawRoute, routeSrc = customUserRoute, "custom"
    else
        rawRoute = findAtlasRouteInMemory()
        if rawRoute then
            routeSrc = "memory"
        else
            rawRoute = readAtlasFileRoute()
            if rawRoute then routeSrc = "file:" .. tostring(_lastRouteFile) end
        end
    end
    _routeSourceName = routeSrc or "none"
    local rawItemsList = rawRoute and extractPurchaseList(rawRoute, 0)

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
                local rBees = tonumber(reqBees)
                local itemBees = (rBees and rBees > 0 and rBees) or (base and base.Bees) or 0
                table.insert(dynamicRoute, {
                    Name = base and base.Name or tostring(canonical),
                    Type = base and base.Type or "Gear",
                    Bees = itemBees,
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
            _routeFound = true
            _cachedParsedRoute = dynamicRoute
            _lastRouteSourceTime = tick()
            return dynamicRoute
        end
    end

    _routeFound = false
    local allowFallback = false
    local roots = compact({ getgenv and getgenv(), _G, shared }, 3)
    for _, r in ipairs(roots) do
        if type(r) == "table" and r.AllowDefaultRouteFallback == true then
            allowFallback = true
            break
        end
    end

    if allowFallback then
        _cachedParsedRoute = FullProgressionRoute
        _lastRouteSourceTime = tick()
        return FullProgressionRoute
    end

    _cachedParsedRoute = {}
    _lastRouteSourceTime = tick()
    return {}
end

local _targetSource = "none"

local function getAtlasLiveTarget()
    _targetSource = "none"

    local function accept(raw, srcName)
        if raw == nil then return nil end
        local res = resolveItemName(raw)
        if res and isKnownProgressionItem(res) then
            _targetSource = srcName
            return res
        end
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

            if type(t.route) == "table" then
                local pList = extractPurchaseList(t.route, 0)
                if pList and #pList > 0 then
                    local char = player.Character
                    local data = getStatData()
                    for _, p in ipairs(pList) do
                        local pName = (type(p) == "table" and (p.Name or p.Item or p.Target or p.Gear)) or (type(p) == "string" and p)
                        if pName then
                            local resolved = resolveItemName(pName)
                            if isKnownProgressionItem(resolved) and not isItemOwned(resolved, "Gear", char, data) then
                                _targetSource = "settings.toys.route (first not owned)"
                                return resolved
                            end
                        end
                    end
                end
            end
        end
        local r = accept(settings.target, "settings.target")
        if r then return r end
    end

    local roots = compact({ getgenv and getgenv(), _G, shared }, 3)
    local allowUI = true
    for _, r in ipairs(roots) do
        if type(r) == "table" then
            if type(r.Atlas) == "table" then
                local targets = compact({ r.Atlas.ProgressionTarget, r.Atlas.CurrentTarget, r.Atlas.Target, r.Atlas.CurrentPurchase }, 4)
                for _, tgt in ipairs(targets) do
                    local res = accept(tgt, "global Atlas.*Target")
                    if res then return res end
                end
            end
            local targets = compact({ r.ProgressionTarget, r.CurrentTarget, r.CurrentPurchase, r.Target }, 4)
            for _, tgt in ipairs(targets) do
                local res = accept(tgt, "global *Target")
                if res then return res end
            end
            if r.AutoProgUIScan == false then allowUI = false end
        end
    end

    -- Quet UI: CHI nhan text co dang "Target: <ten>", "Next: <ten>"... (bat buoc co dau : hoac -)
    -- va <ten> phai khop CHINH XAC mot item. Da bo: hard-code "diamask", khop chuoi con tren moi
    -- TextLabel, va nhanh "candidate" (nguyen nhan chinh gay sai target).
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
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                        local txt = desc.Text
                        if txt and txt ~= "" and #txt < 120 and desc.Name ~= "AutoProg_HUD" and desc.Parent and desc.Parent.Name ~= "AutoProg_HUD" then
                            for _, pat in ipairs(patterns) do
                                local m = txt:match(pat)
                                if m then
                                    local res = resolveItemNameStrict(m)
                                        or resolveItemNameStrict((m:gsub("[%s%d]+$", "")))
                                    if res then
                                        _targetSource = "ui:" .. desc:GetFullName():sub(-60) .. " = '" .. txt:sub(1, 50) .. "'"
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
    return nil
end

local _activeTargetName = nil
local _missedLive = 0

local function evaluateRoute(data, beeCount)
    local char = player.Character

    local liveTarget = getAtlasLiveTarget()
    if liveTarget then
        _missedLive = 0
    else
        _missedLive = _missedLive + 1
        if _missedLive >= 3 then _activeTargetName = nil end -- het han latch sau ~30s khong thay target
    end
    if liveTarget then
        local canonicalLive = resolveItemName(liveTarget) or liveTarget
        if canonicalLive and isKnownProgressionItem(canonicalLive) then
            _activeTargetName = canonicalLive
        end
    end

    if _activeTargetName then
        if isItemOwned(_activeTargetName, "Gear", char, data) then
            _activeTargetName = nil
        else
            local matchedMilestone = nil
            local cTarget = _activeTargetName:gsub("[%s%-_']", ""):lower()
            for _, milestone in ipairs(FullProgressionRoute) do
                local cMilestone = milestone.Name:gsub("[%s%-_']", ""):lower()
                if cTarget == cMilestone then
                    matchedMilestone = milestone
                    break
                end
            end

            if matchedMilestone then
                if matchedMilestone.Ingredients then
                    local firstUnfarmMat, firstUnfarmAmt = nil, 0
                    for _, ing in ipairs(matchedMilestone.Ingredients) do
                        local missingMat, missingAmt, targetField, isUnfarm = resolveMissingMaterial(ing.Item, ing.Amount, data, beeCount)
                        if targetField then
                            return matchedMilestone.Name, missingMat, missingAmt, targetField, false
                        elseif isUnfarm and not firstUnfarmMat then
                            firstUnfarmMat, firstUnfarmAmt = missingMat, missingAmt
                        end
                    end
                    if firstUnfarmMat then
                        return matchedMilestone.Name, firstUnfarmMat, firstUnfarmAmt, nil, true
                    end
                end
                return matchedMilestone.Name, nil, 0, nil, false
            end
        end
    end

    local activeRoute = getAtlasRoute()
    for _, milestone in ipairs(activeRoute) do
        local owned = isItemOwned(milestone.Name, milestone.Type, char, data)
        if not owned and beeCount >= milestone.Bees then
            if milestone.Ingredients then
                local firstUnfarmMat, firstUnfarmAmt = nil, 0
                for _, ing in ipairs(milestone.Ingredients) do
                    local missingMat, missingAmt, targetField, isUnfarm = resolveMissingMaterial(ing.Item, ing.Amount, data, beeCount)
                    if targetField then
                        return milestone.Name, missingMat, missingAmt, targetField, false
                    elseif isUnfarm and not firstUnfarmMat then
                        firstUnfarmMat, firstUnfarmAmt = missingMat, missingAmt
                    end
                end
                if firstUnfarmMat then
                    return milestone.Name, firstUnfarmMat, firstUnfarmAmt, nil, true
                end
            end
            return milestone.Name, nil, 0, nil, false
        end
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

local function getAllTargetIngredients(targetItem, data, beeCount)
    if not targetItem or targetItem == "None" then return "None" end
    local matched = nil
    local cTarget = targetItem:gsub("[%s%-_']", ""):lower()
    for _, m in ipairs(FullProgressionRoute) do
        local cm = m.Name:gsub("[%s%-_']", ""):lower()
        if cm == cTarget then
            matched = m
            break
        end
    end

    if not matched then
        local activeRoute = _cachedParsedRoute or getAtlasRoute()
        if type(activeRoute) == "table" then
            for _, m in ipairs(activeRoute) do
                local cm = tostring(m.Name or ""):gsub("[%s%-_']", ""):lower()
                if cm == cTarget then
                    matched = m
                    break
                end
            end
        end
    end

    if not matched or not matched.Ingredients or #matched.Ingredients == 0 then
        return "Honey Only"
    end

    local lines = {}
    for _, ing in ipairs(matched.Ingredients) do
        local invCount = getItemAmount(ing.Item, data)
        local isMissing = invCount < ing.Amount
        local isUnfarm = false
        if isMissing then
            local _, _, tf, unf = resolveMissingMaterial(ing.Item, ing.Amount, data, beeCount or 35)
            if not tf and unf then isUnfarm = true end
        end
        local status = not isMissing and "[OK]" or (isUnfarm and "[NEED - MANUAL]" or "[NEED]")
        local line = string.format("• **%s**: %d/%d (%s)", ing.Item, invCount, ing.Amount, status)
        if isMissing and RECIPES[ing.Item] then
            local def = ing.Amount - invCount
            local subParts = {}
            for _, sub in ipairs(RECIPES[ing.Item]) do
                local totalFruit = def * sub.Amount
                local curFruit = getItemAmount(sub.Item, data)
                table.insert(subParts, string.format("%d %s [have %d]", totalFruit, sub.Item, curFruit))
            end
            if #subParts > 0 then
                line = line .. "\n  └ *Raw: " .. table.concat(subParts, ", ") .. "*"
            end
        end
        table.insert(lines, line)
    end
    return table.concat(lines, "\n")
end

local _lastWebhookSendTime = 0
local _lastWebhookTarget = nil
local _lastWebhookField = nil
local _lastWebhookMat = nil

local function sendDiscordWebhook(beeCount, targetStr, fieldStr, routeStr, data, needStr, isUnfarmable, neededMat)
    local roots = compact({ getgenv and getgenv(), _G, shared }, 3)
    local webhookUrl = nil
    local interval = 600

    for _, r in ipairs(roots) do
        if type(r) == "table" then
            if r.DiscordWebhookUrl and type(r.DiscordWebhookUrl) == "string" and r.DiscordWebhookUrl ~= "" then
                webhookUrl = r.DiscordWebhookUrl
            elseif r.WebhookUrl and type(r.WebhookUrl) == "string" and r.WebhookUrl ~= "" then
                webhookUrl = r.WebhookUrl
            end
            if r.WebhookInterval and tonumber(r.WebhookInterval) then
                interval = tonumber(r.WebhookInterval)
            end
        end
    end

    if not webhookUrl or webhookUrl == "" then return end

    local now = tick()
    local stateChanged = (targetStr ~= _lastWebhookTarget or fieldStr ~= _lastWebhookField or neededMat ~= _lastWebhookMat)
    if not stateChanged and (now - _lastWebhookSendTime < interval) then
        return
    end
    if stateChanged and (now - _lastWebhookSendTime < 15) then
        return
    end

    local httpRequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not httpRequest then return end

    _lastWebhookSendTime = now
    _lastWebhookTarget = targetStr
    _lastWebhookField = fieldStr
    _lastWebhookMat = neededMat

    local needIngredients = getAllTargetIngredients(targetStr, data, beeCount)
    local noteText = isUnfarmable and string.format("\n⚠️ **Note:** Missing unfarmable item `%s` (cannot farm in fields).", tostring(needStr)) or ""

    local bodyText = string.format(
        "**Bees :** %d\n" ..
        "**Current Target:** %s%s\n" ..
        "**Need:**\n%s\n" ..
        "**Field:** %s\n" ..
        "**Route:** %s",
        beeCount,
        targetStr,
        noteText,
        needIngredients,
        fieldStr,
        routeStr
    )

    local embedColor = isUnfarmable and 16744448 or 3447003

    local payloadV2 = {
        flags = 32768,
        components = {
            {
                type = 17,
                accent_color = embedColor,
                components = {
                    {
                        type = 10,
                        content = "## Ivyiz Auto Change Field Webhook v1.0"
                    },
                    {
                        type = 14,
                        divider = true,
                        spacing = 1
                    },
                    {
                        type = 10,
                        content = bodyText
                    },
                    {
                        type = 14,
                        divider = false,
                        spacing = 1
                    },
                    {
                        type = 10,
                        content = string.format("-# Player: %s • %s", player.Name, os.date("%X"))
                    }
                }
            }
        }
    }

    local ok, encoded = pcall(function() return HttpService:JSONEncode(payloadV2) end)
    if ok and encoded then
        local reqOk, res = pcall(function()
            return httpRequest({
                Url = webhookUrl,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = encoded
            })
        end)

        if not reqOk or (type(res) == "table" and res.StatusCode and res.StatusCode >= 400) then
            local fallbackPayload = {
                username = "Ivyiz Auto Change Field",
                embeds = {
                    {
                        title = "Ivyiz Auto Change Field Webhook v1.0",
                        description = bodyText,
                        color = embedColor,
                        footer = { text = string.format("Player: %s", player.Name) },
                        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                    }
                }
            }
            local s2, enc2 = pcall(function() return HttpService:JSONEncode(fallbackPayload) end)
            if s2 and enc2 then
                pcall(function()
                    httpRequest({
                        Url = webhookUrl,
                        Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" },
                        Body = enc2
                    })
                end)
            end
        end
    end
end

local function printDebugInfo()
    local data = getStatData()
    local beeCount = getBeeCount(data)
    local liveTarget = getAtlasLiveTarget()
    local activeRoute = getAtlasRoute()
    print("========== [Auto Prog Debug] ==========")
    print("Bee Count:", beeCount)
    print("Atlas Live Target:", tostring(liveTarget))
    print("Active Latched Target:", tostring(_activeTargetName))
    print("Atlas Settings Found:", tostring(findAtlasSettings() ~= nil))
    print("Live Target Source:", tostring(_targetSource))
    print("Route Source:", tostring(_routeSourceName))
    print("Route Source Items Count:", #activeRoute)
    for i = 1, math.min(#activeRoute, 15) do
        local m = activeRoute[i]
        print(string.format("  route[%d] = %s (bees>=%s)", i, tostring(m.Name), tostring(m.Bees)))
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
    local checkList = { "Hiking Boots", "Beekeeper's Boots", "Looker Guard", "Brave Guard", "Diamond Mask" }
    for _, itm in ipairs(checkList) do
        print("  " .. itm .. ":", isItemOwned(itm, "Gear", player.Character, data))
    end
    local targetItem, neededMat, neededAmt, field, isUnfarmable = evaluateRoute(data, beeCount)
    print("Evaluation Result:")
    print("  Target:", tostring(targetItem))
    print("  Need Mat:", tostring(neededMat), "(" .. tostring(neededAmt) .. ")")
    print("  Unfarmable:", tostring(isUnfarmable))
    print("  Target Field:", tostring(field))
    print("========================================")
end

if getgenv then getgenv().AutoProgDebug = printDebugInfo end
_G.AutoProgDebug = printDebugInfo

task.spawn(function()
    local okD, errD = pcall(printDebugInfo)
    if not okD then warn("[Auto Prog] debug error: " .. tostring(errD)) end
    while true do
        local okL, errL = pcall(function()
            local data = getStatData()
            local beeCount = getBeeCount(data)
            local targetItem, neededMat, neededAmt, field, isUnfarmable = evaluateRoute(data, beeCount)

            local targetStr = targetItem or "None"
            local needStr
            if neededMat then
                needStr = string.format("%s (%s)%s", neededMat, tostring(neededAmt), isUnfarmable and " [Unfarmable]" or "")
            else
                needStr = (targetItem and "Honey" or "None")
            end
            local fieldStr = field or "Unchanged"

            local routeStr = _routeFound and "Found" or "Not Found"
            hudLabel.Text = string.format("[Auto Prog] Bees: %d | Target: %s | Need: %s | Field: %s | Route: %s", beeCount, targetStr, needStr, fieldStr, routeStr)

            if field then
                setAtlasField(field)
            end

            task.spawn(sendDiscordWebhook, beeCount, targetStr, fieldStr, routeStr, data, needStr, isUnfarmable, neededMat)
        end)
        if not okL then
            warn("[Auto Prog] loop error: " .. tostring(errL))
            hudLabel.Text = "[Auto Prog] Error: " .. tostring(errL):sub(1, 80)
        end
        task.wait(10)
    end
end)
