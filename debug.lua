local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer

print("==================== [BSS AUTO PROG DEBUG] ====================")

local clientStat = RS:FindFirstChild("ClientStatCache")
local myStats = clientStat and clientStat:FindFirstChild(player.Name)
print("1. ClientStatCache:")
if myStats then
    print("   [+] ClientStatCache found for: " .. player.Name)
    local rootSlots = { "Collector", "Tool", "Bag", "Backpack", "Boots", "Shoes", "Belt", "BeltBag", "Hat", "Mask", "Sprinkler", "Glider", "BlueGuard", "RedGuard", "LeftGuard", "RightGuard" }
    for _, slot in ipairs(rootSlots) do
        local obj = myStats:FindFirstChild(slot)
        if obj then
            print(string.format("   - %s: %s (%s)", slot, tostring(obj.Value), obj.ClassName))
        end
    end

    local eggs = myStats:FindFirstChild("Eggs")
    if eggs then
        print("   Fruits/Seeds (in Eggs):")
        local fruits = { "Blueberry", "Strawberry", "SunflowerSeed", "Pineapple", "Coconut" }
        for _, f in ipairs(fruits) do
            local itemObj = eggs:FindFirstChild(f)
            if itemObj then
                print(string.format("     * %s: %s", f, tostring(itemObj.Value)))
            end
        end
    end

    local itemsFolder = myStats:FindFirstChild("Items") or myStats:FindFirstChild("Inventory")
    if itemsFolder then
        print("   Materials (in Items):")
        local mats = { "BlueExtract", "Blue Extract", "RedExtract", "Red Extract", "Oil", "Enzymes", "Glue", "Gumdrop", "TropicalDrink" }
        for _, m in ipairs(mats) do
            local itemObj = itemsFolder:FindFirstChild(m)
            if itemObj then
                print(string.format("     * %s: %s", m, tostring(itemObj.Value)))
            end
        end
    end
else
    print("   [-] ClientStatCache NOT found for: " .. player.Name)
end

print("2. Character & Backpack:")
if player.Character then
    for _, ch in ipairs(player.Character:GetChildren()) do
        if ch:IsA("Tool") or ch:IsA("Accessory") or ch:IsA("Model") then
            print(string.format("   - Character: %s (%s)", ch.Name, ch.ClassName))
        end
    end
end
if player.Backpack then
    for _, ch in ipairs(player.Backpack:GetChildren()) do
        print(string.format("   - Backpack: %s (%s)", ch.Name, ch.ClassName))
    end
end

print("3. Atlas Settings & Environment:")
local atlasSettings = nil
local roots = { getgenv and getgenv(), _G, shared }
for _, r in ipairs(roots) do
    if type(r) == "table" then
        if rawget(r, "toys") and rawget(r, "autofarm") then
            atlasSettings = r
            break
        end
        if r.Atlas and type(r.Atlas) == "table" and r.Atlas.Settings then
            atlasSettings = r.Atlas.Settings
            break
        end
    end
end

if atlasSettings then
    print("   [+] Atlas settings found!")
    if atlasSettings.toys then
        print("   - toys.prog:", tostring(atlasSettings.toys.prog))
        print("   - toys.target:", tostring(atlasSettings.toys.target))
        print("   - toys.current:", tostring(atlasSettings.toys.current))
    end
    if atlasSettings.autofarm then
        print("   - autofarm.field1:", tostring(atlasSettings.autofarm.field1))
    end
else
    print("   [-] Atlas settings table not found in memory.")
end

for _, r in ipairs(roots) do
    if type(r) == "table" and r.Atlas and type(r.Atlas) == "table" then
        print("   - getgenv().Atlas fields:")
        for k, v in pairs(r.Atlas) do
            if type(v) ~= "table" and type(v) ~= "function" then
                print(string.format("     * %s = %s", tostring(k), tostring(v)))
            end
        end
    end
end

print("4. UI Text Scan (matching 'diamask', 'target', 'prog'):")
local uiRoots = {}
pcall(function() if gethui then table.insert(uiRoots, gethui()) end end)
pcall(function() table.insert(uiRoots, CoreGui) end)
pcall(function() table.insert(uiRoots, player:FindFirstChild("PlayerGui")) end)

for _, uRoot in ipairs(uiRoots) do
    if uRoot then
        for _, desc in ipairs(uRoot:GetDescendants()) do
            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                local txt = desc.Text
                if txt and txt ~= "" and #txt < 120 and desc.Name ~= "AutoProg_HUD" and desc.Parent and desc.Parent.Name ~= "AutoProg_HUD" then
                    local tLow = txt:lower()
                    if tLow:find("diamask") or tLow:find("diamond") or tLow:find("target") or tLow:find("prog") then
                        print(string.format("   [UI Match] Parent: %s | Name: %s | Text: '%s'", desc.Parent and desc.Parent.Name or "nil", desc.Name, txt))
                    end
                end
            end
        end
    end
end

print("5. Global Function Call:")
if getgenv and getgenv().AutoProgDebug then
    print("   Running AutoProgDebug()...")
    getgenv().AutoProgDebug()
elseif _G.AutoProgDebug then
    print("   Running _G.AutoProgDebug()...")
    _G.AutoProgDebug()
else
    print("   [-] AutoProgDebug is not loaded yet. Make sure autochangefieldbeta.lua is running.")
end

print("================================================================")
