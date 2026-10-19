local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
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

local scriptAlive = true
local scriptConnections = {}
local function trackConn(c)
    table.insert(scriptConnections, c)
    return c
end

local function destroyOldGuis(parent)
    if not parent then return end
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name:find("AutoFeed") or child.Name:find("AutoTreat") or child.Name:find("WindUI") or child.Name:find("AutoProg") then
            pcall(function() child:Destroy() end)
        end
    end
end
destroyOldGuis(CoreGui)
if gethui then destroyOldGuis(gethui()) end
destroyOldGuis(player.PlayerGui)

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

local feedRunning = false
local rollRunning = false
local targetLevel = 15
local targetBeeCount = 50
local walkSpeed = 60
local autoBuyEnabled = true
local returnHiveEnabled = true
local autoPauseAtlas = true
local activeTween = nil
local feedToggle = nil
local rollToggle = nil
local pauseAtlas
local stopAutoFeed
local stopAutoRoll

function stopAutoFeed(keepAtlas)
    feedRunning = false
    if not keepAtlas and pauseAtlas then
        pauseAtlas(false)
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
    rollRunning = false
    if not keepAtlas and pauseAtlas then
        pauseAtlas(false)
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

local BOND_TABLE = {
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
        total = total + (BOND_TABLE[i] or (BOND_TABLE[25] * 2^(i - 25)))
    end
    return total
end


local ICON_B64 = "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"
local iconAsset = nil
local function loadIcon()
    if iconAsset then return iconAsset end
    local filename = "ivyis_bg.png"
    if getcustomasset and isfile and isfile(filename) then
        local ok, asset = pcall(getcustomasset, filename)
        if ok and asset then
            iconAsset = asset
            return asset
        end
    end
    filename = "ivyis_icon.png"
    if isfile and writefile and (not isfile(filename)) then
        if crypt and crypt.base64decode then
            pcall(function() writefile(filename, crypt.base64decode(ICON_B64)) end)
        elseif base64_decode then
            pcall(function() writefile(filename, base64_decode(ICON_B64)) end)
        end
    end
    if getcustomasset and isfile and isfile(filename) then
        local ok, asset = pcall(getcustomasset, filename)
        if ok and asset then
            iconAsset = asset
            return asset
        end
    end
    return "rbxassetid://4503856569"
end

local ROUTE_ICON_B64 = {
    backpack = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVfUiUWHwqSbCkqORI3ZyhVVwJCizlqPCtFlEAbKw8ocCRgfEKojTolORU7hDMA/wCji0QuSB5IbCT//wAsRxadf0T//3////8AAACUPDw8lTyZdTBFZignORIvSBiMZyhQdDByViguRRlHXCY7WiMzVRtzVRoAVQBGSBYlNRdBkz2wmESKQzqlhzUcMgw7ZSUS+kslAAAAMHRSTlP6Jf/Q9QP/2f9aBP//nP8B/1SvAbL/AgEA/v/+/vv4/v3+1/7+/P4D/i///v7++/10plUkAAACdUlEQVR42s2WiZKiMBBAO8iosLg6O3swAwQTEnR1MP//d9sdbpegTtUer5TLfulOSKxA/EHg34sHFo7uf4Qhu0Pc2iMbUD8Pb2ZkwUZK3pBxLqVcbIJbGVmA0VoVaYNWaVEUSmstA+YSD/FPiREYvu9or/Gh4ld5OzGMn4uhhOF7M2pEf2VT4lPMoItpUKq5aH74glEOsRVIUSlW3vU3teL3qT4yoN8Li7JwrhoKamAPg/cyGFXmp43Dr9BkGpMC62sdipIsTYE0ukVqmoYaOTXmOWZTpUqrKK0MiQZT1BQ6VbXrEBeZorEzxscP0fYY6tNRMgybzGiWpxN+WtafBLz3AEzPHCu+DUHxdcD7yjXlrsXTA+LpYxn1cv3XxcdLfUIx+0Pi6yPi+73i+u10euw9WpEv1zTVGm1Yaj3nnOLFX9rZ7X+2LPcChjgzXjJaO9r0K6oHVwdfOEWujA0BOI7AbPTn4TtF/HOCNrIUPWVZkusWeQqihDxJkmh33lVVtTvXRFWUJCDdooZdVLXBUVRVUXTugJk+arE7U7zFQ+hU2VNVTYsHKwIkRFXhwbOX7QmZFUWS53kbmedC5ERijzOiDxjo5R1iBe1lcktMRoj8W5OcROkulYs+XZ0Z6CXWiHmxiytxUEetzA0OL/syaZC8Yd13iV5yDQ7VzODwsh7CKwctzxOujIwyHmlKi9wTff/wHic8LRi3mPGMFqwYgfdwXOFS5S5xkaFI2GVVc0SlYV7k2QwL5hQ7LpdLd7Tp6Dsp4h7gtwycSrDIzWYTBIG7VFnj13FB0G0fZzeBjqjtdhtvw+2NbefLS0hgG4f/fk9+L78ABto4Ha80LjkAAAAASUVORK5CYII=",
    basicboots = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVfXCApJAlvbBxzcRxYPQ9iXxmCfR///1WBfSCqqhWRiyT///9VVVWFgB3/qlUAAACJhSJ7eSCDfSF4dh5/fwCCex6WkiZMShNVVQJsahp/fy45OQNZVhR4dh7//wBKSRFraRtaWBaGgyFubRuZmTM5OQxZWBdkZwtqZxpqaRp3dB16eB55dyCHgh+/vz///3917CPyAAAAMHRSTlMeFYvgHFubA8wEqgEDzwMA/v7++wL6+1MFjgUJTa0BNnJt0MkFMTYOTbJzy7D7BAIVrH0qAAACdUlEQVR42u2WaXOjMAyGgVy9dm35CBAgIeQ+tvn//66yDAYCTdJ+6041zOTAj19Jli177Jvm/YI/B1TRUHnr9eSV/V3vokdBdbn+Z/I8Uw+6ukn3x+N4HGTBcb+4qThXaHP8iFiaFUXBncmieHkJUv++YiiEsMw/eqzFHTDxvcUizePsD+fT6TlNNtIaEIuzaHza4BaHP9VOcZDI8oILCwIhwpjmyxqcsPEUDWfVWgttRkgQRnZq5kBQW4rAtAZnLAaNClPeYygKlVwXzAGds6odECVFbZpvazBhIRjSjeUunUYRjKQoc6O5V4OK+RgHgOh3tS3ZBNkrGxjJT0A03QDzpAbf2Ul0FPGXGYcTQulq9eacsrkF1yzruloqWLCVLf5kwjPgjAW0XDXiOGG4GqSJRFYpKhbKxnvRzAVVDkbJTUpxCA7jZwyurFX/M1CQKxJs2o0gghn6aME5o5oUfWYVCbQmRexA1Q9WFS9bIEBuqBI8wBXIW5vFgfRtyXYODKCW7CtXImkIwGnBIreRQ0qA6KlxkxRD0I4GeY6HrRNgQ6+uIEuBWK04nQOD7GgOrItqgEl9SLglqcLiyySXfBDnRM2ilqI/MNkpSdFMIaYfTwtvRPtwnXSOx5SCKJNnK9SBIZ6XpjKj3nM1Fq3laoGYd6X6e4eaRyu4Wmc3RXir6bwxT/aCuP9HN7vVMxv1kIjx24oYu09116KAi1W+v9MfFds5RbslcDcGe+9+Y43K/VzVsjxsd9S/7nbkiC21tHKgVyE1NKUea+UHYUoZTsuv3gGGJy6zeEMhf+3ysAhMKb8n37l1XNpF+SCoHhD7vcv9R+AH98jLDbIyV0kAAAAASUVORK5CYII=",
    beekeepersboots = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAACWl5bn5+eYEQseSan19fUYPY+UjV2GeB4MJ3RwcHCqmid0DQl7bx7W1tbIW1e4Y2AlYeCZmpreIBrW1tYYPI5eXmB4j6ZtktqMjIy2AgKHh4f2CgATMXIdOaMYPIwTQ5tgAwJqDQiIEQzQrKkaX693d3lQc73eEgoAY2Mmdu4AAP8eSKkA//9LdcuJIBsvRBULAAAAMHRSTlMA/Pj8+wj4/v4QC/+Y/5///P4b2FqoUvz8oxJCDVkYbGkRZq/+BJ7/twIDAZMB/1EO3zSKAAABsklEQVR42u2VaWKCMBBGBwU10bKDioK71P3+t+uQBQJO7QHK84eS5M0XhqgAPT3/Cu4IOIJvatBpICVq3IHYdQcGLpElFsZxLEqHIedCrDRLI0yifGysGriuy5UIphl3zJXekl6ArLqJhOkYk0dVYBDiROsOJbETGubZegMTAZbv41Yr8myNNX+L7cQJMhWMP4tn4IaYCnHyhUy64njagHOpKTqp3Oq0itViqERRTtEW8emneiPNTTaiAU6aBwti3Wuzqyi+VK2x0bq6qRy41X1WQgTIIqqp3BBbZ0PnQrGOju8HoDnfAERd67gItqToGs+REheBTYuDtDavtBdss8gnppZKvFGJ6Nk2yyKPEFMZdwEGi/mc8mBHiiD7ymBjC8qy1H7lBVt4wLc3//XbwSAfKYQfPMtn5d2hgF/EeqsjG18GlX8Xk5To48GQiZDYMsw04XZZoxj5nu/7nsQXeFEGO5Wa50mS6L1W+XaBBVE8DCleMrKG5Rvho7ytNoLMSHGnExkrTlen0TcbOMkLMvHQ+V1lWOD0kJ8L+CiuiX8Chpyu+mqPzDoM93Vvenp6CH4AWg8g0QgaWggAAAAASUVORK5CYII=",
    beekeepersmask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUjHh5kY2UkISArKCfm5eolJCOgn6NWVVdXV1h+foC9vMGmpqWmpahYWFpCQT7OztVAPj6QkZPJyMxBPkDAv8M+PkA/QEE/P38/P0IAAP9GRT9mZpl/f4J/f/+Af4P//wAAAABGRkY5ODgsKipVVVZ2dniHh4mop6uWlZjo6Oy2tbnHxstpaGvV1dk4ODj////agrNVAAAAMHRSTlMfD+mi9V744qv7+QacWv0F/mys/f///wRQAbwFnAL/AQD+/vz+/v7+/vz+/v3+BALMERQcAAACzklEQVR42rWXiZajIBBFQUUSjSbpZfYFcckq/v/fTRVIQIPd6Tkz7yTpLFxfUVUgTcRfivxrkG4H1Db/EEi37v2Q/34YHOBZbJ5Qezp+fsyx2GTZpe+T0yk5JRvykONXCDQ9gy6XG/qkHnGk+/QAOmcjCEoSeh/uHCSbwxFJY2lAcN2L/E2Qih9pdzSW5xFMEny985w5FsfuCLLgjUySfEZOwWLdgUZSz/Jkg03yYVgCB8Hb1pDpnOxPm8VQlSjatl0by9TmxyQo6fueLoFU8OuMfNGo1qXfT2bpwM/iy/VqyW4kM0vC32QB/C5W7Zwc0VFU0BA4aLBtHWmqcs4w4MtLdtkHQSoIb68z9GBawSjb+O1DXE6JYRCzlqnHIbgNZrVAv6apfDUgDAIuk57TYDkIi6WsreSd8CIxI3cgwR/vx++eq6kYnYBUMecW9hyvwGlOHfhTCGbsdm5qIH7V4pybz/BLDMNz50iKlRljstqNOlqlWviu2xe3UHOxWrczrbspnOrFjcU5HFJdFgN2U+zXzNJSYyd5YKvjbELidqZXHQc2ogWpYHEUYSJvGa0DldGKohiLOXgNEEehsZWsSniisAdWs86hiigWbpepVpQqpfzOgXArr0kCTFXDV4VQ971qxzb6UYVAyQIgrevJmmhCjizoOAVDjpy4PWDBMRwqJ6H1GEvfMQCWYVDEoYx4ya13fhnfAT1uV1dBEAq5k34hsZbyk6ye3YZS8jAoZSl17U2vGZm9QF+rrqPgHJnfrJWjbEvAIwwCGbl+HZfJdK/kC/dHEsewvvQK0167Waqa1RuHB4YsQK+vgSQvgoTonRlNMaFzNd/eOueQEcU1LKf3giZ2Pb5weiTatLxtsLrrS1hV7x874zryklqWmGffcPmgCzehaLwVwCtuUuTxEzLAKMYY+cjRWvnnE6rUR87kSsEGSJR69KD7X/8L+AO5g4BOcMPB9wAAAABJRU5ErkJggg==",
    beltbag = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWpqqwnKiuam55YWFyZmZxaW1ydnJ+/v8PMzNFiX2FVVapVqlXMzNEAAADExMinqKpNSktVUlR/f3+1tbjU1Nh3dXf///+IiIqZmZmqqqpqa26lp6hoZmh/f7GIiIqlpqi1tbm8vcBVVVW1tbh5eXuZmpy/v7+8vMDMzMyOjpGdnqC6ur4oJii+vsFUVVdsbW/m8YqIAAAAMHRSTlNbHJUpPET/18j/AwOTAP77//8D+///AlYFBDjS/wX/r7H7B9ZWbQSPBXVyjSJWPECZRpsoAAABSklEQVR42u2VaXODIBBA8UrSAy+qgsSmHmlMtPr//10XrUZtMh5tP9U3CjMujwV1FoQXglZxFf+1aFcwxh6Z4L3C7YkQDmiaulemZbw3TIJbUXzfV5GqqugDQIOlSr6HEMpOpyyDBrq3hlhABPqLDtfBthvRtZ93222ow+Mb6AO23Yy7b+H7xJoWwd4QtrEnk+meHhrGGVMQGb7M8YToVSLFRyNcIgY/EeeslfyCeJkrJvApFol+TyQb4w7XABmIxIA/0THHsEwnhIGNyODlCBzTGsN06sS1CL/cMjFoxXH2t8TNa4vTYV/zIBrrZsYZ9Pc4g7IRecyBbogM6MW4gqO25uRSXmhFkQBnQAYOX3B+4N2JQyOvMk5CknKlLP3E87yjjKSqdLSlN3qKItFTSkURZmlaF9rFRwCUQ5jVbialjK7H3Cqu4p+InyBTthKNGqRwAAAAAElFTkSuQmCC",
    beltpocket = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUrJBtfDwpsbAxycnL/AAD///8/NiE6OkAA/wBHOyNgTy5fUC6Aa0D/f38AAABbTC1tWjVGOyU8OTxXRyp4YjpVVVVANR07Mhw8PDxWRyr//wBDOCFcTS1/fzxVVQBgTi4/PwA+NB1WSCpGOyNuNzcvJhc4LRpVVSpoVTJmZjOqqlVoVjRFOSJJPCNeUC8kHBQdybS1AAAAMHRSTlMYBQMDAQFs/wHBvtX/AgD+/f3/b/8DalAErgFuzwQD/gR7jLAEME4GrwUD0liG/zGy+DifAAABeElEQVR42u3W2XKDIBQGYEy6LwcsGrQGadxqNGnf/+0Kak2IjkLai1zkv3DGi2+Oy4EDgjODrvAS4Q0gahJ0Cm+d0jPIS8l16D+UHjGJR08qUjMno8PclBGvhMURrIl5GMQd5FB65s6rUdVCHyixCoWsgbfwRPAhRGAhhLzKCIJHYN29I4fwGM6GhPDawO00FCOQN/ATEtuK21/4ZQUTSRTMgOKzYAA7K4ij7ncEwGxh0MAYvu1gIXtGQccW5qpZ2yZf23ybGh1Whw3Ez/16rOzguofcFlZ/hbLLtZ5zDVq1gZkG30bjjsEA9tgc4lA1zjlw38NYa9ZZGPXQgUJYwMP26EC+noPdh1Epeqh28t0unIL3bcWE0iTJ5Wg7no8b7A7TPWeXdDgf42UQjUE9j4gveKVPKx/u5mEKy8FEDmC+Ik6BD6BvBrORisw1eNQpOLEwUrWhDo4riDFWFIxFKz3yftNkFbU9838HpI82/mkW732up8dLhT9AqsOZU2D96AAAAABJRU5ErkJggg==",
    blueclayplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEU3NzkwLzJBT4FAXMEAAAA4WLdCZs41NTYzSpA+UH5Qc9g8UYo+ZMwyOEs5SHVDW6hHY7QpKSkyTaI4ODgzNDM1NTVBVJA0NDUoKCgrKyw8XcFVVVUcGhwxPWIYGBc1NTUsLC4vLjBRduB/f38pLCz///8JCQ5ATnxAUH8kHh4cHBwfHyofHyMA//8mGSYiHiJaZfG7AAAAMHRSTlNYzv//AP7/+v7//v7//P3+/gf/BLTM/odTb/4DMPsSfYix/wIzASH//ylIGEEBFEIwrD57AAADE0lEQVR42p2Xi3ajIBCGu7sKJCgY7+baNM22e3//t9t/AI147el/jg0inwMzME6fgk/qafFptoOyD4IZdB92HrJsGcwO3m1dXS5V3T6bB//gOjZNU+VWBTeiZtMsWqzbsZzHD9mOIq/nwLqwhFKi1IkVY4nWQlm6aMZgFhyBxUroZNvqZfvyst0yUpJIRWw1BA9BjW4FiMba0WRQa13iSsy9AJqfPfBGXFxuHQOglFIKRdpg5lJqxrZMg2x8i5XlaEVSOkbKjVGJCyy9s4z5lx6YBc/gNDAYEsqMlmTSggJ38p2WwZji/PwAd0FBy2MspKFEOKRTKUqhHXj0QclYlEhQmynJr0IyAuUEGEVMqk3PnHR6xxKV5SZAxSIsUSqh3vum3t7e8LKyTAwXsZLzf0PQhMp4FHJBgEpLGXsRuTWfADFbE0Qns+NYG1xgkYlkcOiDMbNyu+3RaqnIoD5IcYw1LdKnHWMI9+ODQfC9AyPWe4FHzYC89MaS2EiToOrePA2x1qseSN5J2AeELVd4YI3DwaJVTsLgb+9YnTmZXCGj8MT51T+Pu8KsMrJuGa+ROsIwhMEfg5yDjBPLh0fHbAQOM73uhlnuFSb3c97ch0Y4G9fzKD1e+ck83e+dyb1V+JDgvB7n1YrH4YrEI1f18irynFgD4ZzRGoNzztUKJxCO1yF4w1xXQTUB3gGeZNoOSsO0bafICKnhaKqv449OjkgK0Y0VjhS2TV2Y6XiNNFV4x5CGQ4MMpdYcwFTEE161blU6NYAzjIbj2mh035zeVDMbSTO2iwum2HGh4vFT90HvgzApl7yqaOMcxs65/y2WA3Jqc+oAzJAHTnoBjGdBZMlyP8vJOTAIfvKFuQqAVXCfLlfoNE9CzjeXYDcNHo1JGw37NxUtKE34s5mS7Ird820MOq443+ZquR/cbIIH2M7VVDn1QvXYDI+zDqWlfG4E/oJ/UKpg15lPrFKntpbLj0tl541MdmVg1+TF83G10H3mvoqJmnO6tK4vqG6dujI3+0BpHazX1dMWTQXfKfvUfwEL+g9RzWEXG83N9QAAAABJRU5ErkJggg==",
    blueguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUZIFQeSacSFCojLFUNEyQTMHMQFSMZO44gPYMlQXslW9QfTbYAf38Af/8A//8RGB8UL20ZOIIAVaoZQZJVVVUAAAALDRAjV8gZQZYLEBMLFi0aRqojQ40ZPpIHCgsVJ00kO3QhTLMbNWsLDSUjUroAAH8AAP8ZPIseVsQHCg8FCxELGCsHBwoQFy8OJVUdUbauKTaPAAAAMHRSTlMlqyj+oFXeo+z/7swCAgFJl1oDWQMA/fz+/vr9/vw2/f77/Pv+AgFs+2yQFE5OLf0jNO+UAAACGUlEQVR42u2WWXObMBSFQWy246RJWwRa2Bcb7MT//9/1SoKAAWHXnb75+MHDSB/n6ErDleE/KOMJ3gtWv6vK0L2r+g+OyBBCCMVLQkgPWkIuJXhJ9FMDxrFNCxDWqLBPy2ALY1grgguwNBbAGK8K4lN7VNkBPK9zZJLVGCdd9SPX5RlA94YfllnnYHybw9RdAM/45hoxoT/mYKOHCkopARJ+Q3l6MLaJFkoSK6FYoKPyGOOkhFyFI4JJkjxPt6mrRudgo6aqGlCqkCQFbTnnmzQRYWG4mYJ270GpBdFysNkAwcMwjKIw4rmrwHYKtrTzsaRHGErmW3wrLeHt52lVP8FFJOt9wAislOCf51QukrTXYO0bEZcM55FSjwgxYVnIg9dMHR0xNxqli1iny6UsmbQUdZhFfQ8VKFk2QMdAiDGeKnDqaGzC74CKyYKRLmCZ4PF+9KDDwEvOz7KyLMdQcARXAC26VFUnCADJLtfIoFLuCMZuPAG/TFNl05Al41AeOgd9//Rh7gK9MihPQsgMrN/Eg3MwtSRYwumx55+OWj1rWWFJSbv0Ja/rWrHmIssysGzXmw46LKw3Y2FOm9vd6uvwMi1stkE+WgdfX+Xmwnp36ggcBci8oUtqHeu9tP0F693tutMDYF3d0Virn28ysmm+dCfdu7sj72XkU7fezPv7Vq5Y76E7AHI859HLw+kxcP+8BD7Bfwf/AGZYDwz66w4TAAAAAElFTkSuQmCC",
    blueportohive = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAAAUL6GSPDg7lTtRkjMRM8cbLG2joliZVS4qScqfmzZrahErR62YPEDIqF0aKWNqXDcRGWVja26hZEY7lUAdKl46R25XkUVZZIaFeiaWjS8AAP9iWxuVlJcAf3/DqDgpO4wwR6QA//+tjUKgbCOqqlXEsI///18NEy0pO5CxsRX/qlX//wBFNRJ/f39pa0LHAnRoAAAAMHRSTlMA/P7+/f34/Pz97w/y//5X/Rr+/v+b+v//XZQBTP8C+pOjAaIQA/8CTGIDAwEoAp+LGEG1AAACQUlEQVR42u2W2XabMBBABwMGhGxZxoAXGry2rpsm//93HS2AQGynDz19yD0JIT5cjdCMNAb44j/nJK9PliLsqT7j81SWLg1Shh+9zdGWFum0yUFGc9osl2xitif0nF7YqPcGfMBznIn1SZsnfUH9Hz2PTfbKmRnEr8D76DK+PnxgohTFq/V0fI8lD52LPpGOZuRp5K5rMviwIxaF/FtssmETE/LetiAmikCRb7fb/X4ryQRqnCxLO+HgNyGeafaSBMH2M44LXApD9GyqkQhZVwTBel2W5QHuWiy8XjaLsCZBxDUMCTlArMWD57k713V3O3FVeF6+WXSRY5ACHobYwWuJobLkXRjGVsS26NkRpU+mxE2fiBFJk44pcSWpxNvfiKvEEF8A9eLUep7n7alqcbUIAX4p8QccK7FJx26XW++IlhCPXdFIouuNiLeuaBXOQDpuuuKE2KlVF8fB/G9wRRL8SYygC/GOVeGgKGpZ1DSuyUBErDX8TWQaH9W6Fkd0CQG9gSBQ4zQlHpqFc7APjk/cuUm1/9ZrYzslandIqoqT6DMhzfRez/aSb4rviB6jLElL1G/Lz5Tax5s6RcQsbkfSJwrQpFEU+e1THPVsn8kHDvfe05inIkQk8f3Ij2roZUbr8A2hBhvHx3scv14DIlUtQ/u+HEN0Dsr5aHfkDm1aTYNoOaNcgVGnx4yin5OdnNHI77rCO01+d+AXKl6rkXBJ53hCFdlUpSBvzhyuM0TRBTkz4DAvHtid9/T1dfPf8AcsHDKGWxrGkAAAAABJRU5ErkJggg==",
    bomberguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUWFyJWVladnZ0WFxmVlZUSFBWenp7k5uW+wcAfISA+RD48QD9xcnJeYGB/f4DQ0NAAAADLzMsTFRbV1tYHCQn////k5eUmKCe1t7YUFBVHSEmVlpaVl5alp6e4uLjLy8s1Nzd/f393eXnMzMwGCQlVV1epqqrFxcVUVFRmZ2eGiIi2trYPEhIRExR5enqFhYUj0bjvAAAAMHRSTlMZIBlmYqeP/uf/Jf+w//9dAP39/f4B/v36Wfx2/PjKW/wC+wVR+6zTMPz8sI3QU1IqSdHFAAACH0lEQVR42u2W2XKjQAxF2fFktm6EGsLiMQ5mtfH//10a46XVQFKVqsyT71PKlWPpSi3JBvuijCf4faD1hvg2yTLHzwzjuyP+/XeTM9hl+Wrbr3etg8g8ECAmQd5GQRgoso31iOYW+FUAELdRGCrsybVXPXp3cCQh/pPQqKdjuQyeuaoR7SRKWPeCIlLQrICiPuT7A804cBW3978cwTUB8C6JAqpjYxIQmcPnkmiWEC7c5f3AUI2o5zpJQEt8hgmHioDIUpiTMfADBQ/AU1YoYKG2Ukk2i1Qw/NEJbpDiyOjeUqqdblFstKoiGzjMq7On4GFztfgALWbWM9CPE2px73NHA8eXPsvUz3fEYpSJ7Ys+j8iaWa56bZJYVPNBRlbrr0daJGDLIV0CPS2i1sUw6KA2l8CGtlKOyE9qMReVsbhzKg0kFsNAWkyXltX47NQHDtRiGOy57yxvOXWDzC1GGXCL4eJ6TAWxqHUxBs9YAc+wanEcqYdFHVTrqlkMghbgLJ/m8iZ31C7+DjSLW/Myi3MQmcWV8lCLO2lx7XYgM/sHmFOLcviHW2kWjo4zhRy72GldhLpZBQvW1DeQt+pSlcPv1+xucR7RuOUKdIjlSMnJwNX7iPIYwNXijqwN17I+OqzyKy+tlNcje1g8uUf7s4uMrBfjht30vyZEMuXlv4riQ9Bi523dp85gMFvetvL//FxBtLD4AojP33JP8FO9AwtW1P41A8zLAAAAAElFTkSuQmCC",
    braveguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVoaGirq6udnZ05OTlLS0uJiYm1tbXV1dXIyMgAAACGhobMzMzS0tKVlZX///+2trbMzMzLy8vh4eF/f3+lpaV2dnZ9fX1paWkZGRl5eXliYmJHR0eFhYU5OTlUVFRdXV2Hh4cpKSknJyeZmZlVVVVFRUVVVVVmZmZ6enqzs7Ozs7NsbGxsbGyTk5OTk5OqqqqkpwCwAAAAMHRSTlOZEZgWG2TVXNsA/P7+/QH9BVz+Av6y8o0RzHZHVilSbNcUKwUDJzIFVVy0OUxbdQOsKVdXAAAB6ElEQVR42u3W2VKDMBQGYFrXnCxoQwiUbki1i9v7v51JpDVr0c5443juyvSbH8IhJxk6s7J/+PvwfcNHXdfdRavrNnzD1+sQsrMSOUPs8mW7fd3t7mN1c797nal6fq5syHXaQ1bSIseETNwyvwnOqSqoMyvRqKVYUaoYjpRW0Jc0f+8TK6VAham0EBKbATRWoqwBaJFg2GEg7MVZUSihiCg/DaBsviBDUl8qSEThvLAZUGG9Do4WBkbWxU3TtUR2YgIWAaOidRIbc9GDBAcO6NTtnAegGvrLGTioH2Mwx0OJKpB5EL4FYaGey2ly8yLzwVuV3tfBkAAN3Q6IwOYYeIDTyPsIb1VUzP8e47BIBzqQnoa0treIHjblMFTdxgM4r4ehiO05lYhAUniBLAHBh7nTbfNEYnka0mV8e5SmdU4lPiUhnISyTcCwA9Ruo+//GMiiUHdASdNQXCTgXPaJJLoJq++JpWbHIhM0uVWJyu6aYFq95BNXHuE0mGRfcD1i6O1zL/UTad2ygcE6mo2vyYT4zyjR+/Aof5q97fsZclhV1W18AJoxiR6vxnusgg+J08isTh0e5rP9LR4LPcVoGQlMQKYT2q3afRditZLVT44rxpo7bKofnnO4tuqh2/V5ByT+fwj8y/ADYWKFxriXkAkAAAAASUVORK5CYII=",
    bubblemask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVok6UgUWaLrsYuaZhNYW9bd4uDpLoGMy52rcQVJCQPa2xoam2d2OljlaIZLC4sT1QeSVL///9JZnIA//+p7vMdOEgmOkQKJlgfPEhYe4pep6dnpOAfNzoJRD1jf7FOe4alpd0AAP9Ebnh+wNAbSD8URD0/f788gIF/fwBfkZ15uMJ///+qqqqBtsYAAABzl6wYcWV1AAAAMHRSTlP8+f7++vr++vofCAP6rVZYnAGuAQRbmRfZqAMEmfwFYgQBaf8cmQT8Anu1AgOeAP7pt4HTAAADTUlEQVR42rWX13bbMAyGQUmUSIq2LO/YcdIm3YN8/7crwKVh6pykp8WFNchPPwCCw2D+0uCfgEpNG5WS8W5vjFwCv8zRdtJTmt2SolxPP2pkh28UfUGuWHPMKmLbtmIN60Y6K82aM5LtTtZ42zwadQe2RoGGBu2IrdQu5Vrbhnqbq3kRjNrWoziTq5XWrhFbL+T1mVWcMXZmB2zcxKZ7UELgbht8eGSVN7yy48F01MZgPYojgmvmuab5bBKGZjn+HKmV6d9mf58cGTD07jjiOPfCSKKgzGRVBkFRsIiQxQ9grGSbYTAT6OJnQgMbsDGMSSf0FIckZRXJ2w20jXLgLaLWcTe2yVRO57wJcjCYQ4uCefuUnx3HQc6iJbTiVQBPGRAnQ+JstChaOfIrkxnwZNYOHHMetQ7FEdFVbna0BiOMbtbOPFrXgMmpkBNdHI9pjBUvCg/Wg+G95QWgrwDD5JmBWltyDPsWZAEkd2lMNqf8RL5Iri138XkuwRQnt1qapwyIvkuXGcqHFWST7NhiNV52Jlk9VCUZhzJnWKqbg5yDO3PY4Di5HiIPEnrOgEcWQCEWOQTbdu7qIQouG/a4i1G16Gk5KlORjNIKMU1YQHIE4tLIU70UGYtVROM5AVOl2Tw5Ardj0DjFZdBRCHXZcZSVZwHmbO1fQ2X6fd/eF8CW+3qbgyE3qGh6NVc8qad+yyGC1ibMQhFA+2D6jKutU3RO1ZYxHjhgJURwNVqR82DNEwklK20dwQ8ZUJmuiksU6bDgbUnf8AXwkAWlOUCqAD4By5CfJVdlmsEWqzaAtNeVdeGczYMKtzpXAeQoCpbgP0G3YSDzrtJDWOCABLkvNFIEXzgIXvNgWlIprrhA8pLHBeSBNut78OcAhiULYg3SBX+22cUK3dimLgCCZMlNIeJbLncqB34zkidQQNhkkIzg+CgziXFnukGxdImlYD1JldounuXMi40gcULjaDAr/OemR7TpFvDLrGjxjSBY0gUPKvNxGcSmFQyuOguuPs/OhLMdmY5mPqkQOVzv8EmNpuLSQbdb4RCIV+2ExCveo9wbTsgtoWSE/8Dr9+f50XVBsb3O3/SXN57JL/u+9yH1+/3lqt55mFdKqf/wL+AP/hNLLir1cGMAAAAASUVORK5CYII=",
    bubblewand = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAABGb3VkkpwmNtGenwAiM7RQdowJEW6Irc9xkMtmaAIfLKUaJpU4VZodKKkVFfODrLYsXmCSlAEmNMlJcHZ4eHhxcf9Ugn2fyNz29gAUH3YAZf////8AVaoA//9tbRJbdsOlpQBLeHtgnp5hiow1Zxo2XGk7ZG0uQPJhYQFLdJS///8wO3EmM8VVVapcgH7Qv5iiAAAAMHRSTlMA/vn09/T8F/7+E6Je/QwC/yGnq20CAv//AkwCAQMB7/4EngSkHmH//024BNh9A43/fvgfAAAB5klEQVR42sXW3U7jMBAF4LFdOz+22ySEBtqybWmBBXaX9387zjipugWJ2OGCEQJuPp3M9ARB9INzfXh9PVynu3/9jzrVbYiOx+MbglNlK8PUdEja7+SkpE39K4XewwiDby0lPW7JYSZ8tUkHsl4WPHmeh0XjZkFW613O6gYQqRS1ZkYrrT2z/AZwtyvkI8VcKATyXSqGeORd8RL5pHBCGGMkXNjV1G1bjz8paS94nhBbVVWeFwUf+X4EzslpMUyAVX9aiU1HVzzDXvaRL2NNOMOwKHAPJVc/EmJRDh4iv4ZLssqLixlg+3UP5oBafJAm4qoojtIfIoW3D+OFXZJW3ABhzjfSDtcem7uFU5AdXsfuFKgzrBBTVkiPt7HDx2FE5zVgFtHWu0yxxEW6ThrjtbIRTxoOZFmCYjycQuI67mV2q6tgNZRzTulVrBxilbK83Bw8Xv63NGUsl7GRfJB1NsirBHlRRAoymyR/W6J0mX1H/kUTIqtwUcUNOTUpE1d1KrK2n/8EslxMkyrqHfssUb/VNBnqN2HWoUQl/3qb+LGw/LOdNSXtk2Ot385YlkmqLMstXJAPaYHPs2FSM4nOMulCCDrJ52TZDDLxtFitmbhlL5vUFvS9aZpJ/0TvaeqU+9uSfmjeATnxGN2hxoSoAAAAAElFTkSuQmCC",
    buckoguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVUZmmcnWYQKV0iS58LHlJnZigRKF8xTHIIDywfSaQRK2MkW8oYOogTOIsAef94hnQA//8AZWUAVaoeQo+QhyRTbIwMGjYXO4hVVapwhIwAAKp/f/+EfR/BpEH///8AAAAmWMooVbK0ozATOIoaSKgUNHkMKm+qmy8YQpkAAP+xpk0LFzQAAH8iTK44WJARK27qFIh3AAAAMHRSTlP7/lvpJv2f9SOo2PJe4QL+AQIDZf//RKcD+AMC//8BAP78//z5+fv/+QH/FgL1/dGxmPLMAAACX0lEQVR42u2W2XLjIBREETBol5fEdjIbwiBZ1ub//7u5oM1yJMfWU6om/eAHV51q6L4CEF8o9A1+BbBcBpbLHMuIc1o8C5Zb/Yvxk+DZUCxkztNLxeySSkIf3qOxcjSVyqzCPHoIbCnM0lBKWQnM1w84dpSXJsApJYTb/jkHbt/KNsM989I0kbBGIeLY5evznR7LbjV7ZjYmMwVQLGJS/P1k5Bhk7jAwSxKZCe2lNQQ6A+5ZmnjMgwVKVVUtFccKX83bBFjgS+qBl15gD4GgiHtfh8ZSHQcByr/iREgpLbScgt6AG8ieaUp7iWsKuExeQJ4HP8ml0KV0II0A85IkI20aIz8ltRK9bxliUybqy8bMBtV1LYQYba/hkkbSo+M9gh1q1LIDp1Rn13CbaxDbNvqh1dJo16MklL2ykPKRo5vVDdcJrXa16Aw7ZZr7OdRRcocIG1nW6RX0W3OvlrVC433CCiaGPKg0mR9BJ6Njbo1BkEsnBiAwnrlBj380fgu6wdTkrDluVns8GfQjqO2mZnXLqVuR3hOUr+qBFFV/SN3OatSSVkfm1q4HKwhU4Zkh33DHFcRedREdrbYQIXQR6kDnvg4I+gXIJlzYqoUMKHSBSrH7l04ghlpMk77fc+e7t9WLb8LNYa2mSd+PCZwDhw/cDQgRNbXk0AeAvusSotShaCd73vENwhUEQUS59V4rKL2g+p45f3qxRoaEcC1kE/zxWpw/5eAkgHDr94aDk3nDJ/ymjkdTi6gFwQveAAFMS7Dg8XCGWgL+a4FjZOZ+yXNlPVyET75zyu9H4P8B/gMGVWhVRLND0QAAAABJRU5ErkJggg==",
    candyplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEXc4fPQpNu6odAwLjErKywzMzO5zNdfUWMtLS7VZVCfkKllZWXa01RXZpqZdZxIO0pJedQ1N0fgk57///9P1G3mx6RhgdndhVw7RVlzkodw0IqwXVb/AP/FwzpjEmNcrnMkJEgAAP8AVQA+WI07vllIJCRISCS6TD6/gGiw07/hf5kAAADGitA2NjfstvTj+f7Aj5SDAAAAMHRSTlP+/v7yE57//WT//gL//v77//z/Af/////9/v//Af8E/wcBA/7/Bwf/////AP/6/v8CtmSyAAADrklEQVR42p2XiXabOhCGtbFYFDA4dpykaW+Xu2KZ93+7/qORhExxm9zJOebE0aeR/lmYiOl/mvjtCpPsDSAWHYhoDocm+zr/5SewWW9d13XhrTa/9Wh4KRMumS4KMzV3QDBaY42On9oNfV/BevrGmTseC7/a9ZW11dBXbWetklJeYdJ2lV7IHDSEuaq1SpDReiGui4lrRiawmRiTIhqcZMbsQkbwAE5XncyYy41J/EkKNWB3L5BYjqmDt+uaCaTfrx3IpclAcMHXZdv8feXp7Fwx/bWAhev9lnc56dWS+5bAzCMc8vXvc+NuNyoG/0ggbtix8lsepb/8Dtbtzzcea+fOJ8Vx3pLTh5XAHcTRKRzNhLzan/YqBEvexC8GaCTupcrC8RWSum8nIq8bJv59fn4usd1u9/fLS+9cHT1+wg2Hdg/whHXH4zFcdhxH/3yAPeMw8r/d2CHPU8r9GcA9gccPMB+WR5yMSEHgQ+n3EJ2GNBE0DLZtq5j7cLzSlR4fE/j9IZwCuVpnSY47Dm17UtcFhMMAXsunz58ta9a5m+rgwkDmEPj6+ho8QsOR5SlliFI3rMuKSJ8Bx3BScvnPKFN0OKQKR9W39Qiyt7x/rN0QQymV4lRQci4rCkdeVlPRc1n5/UWIvpjxI1IyCDFbzRmXwAYFWakSq3AieqiQ2lg8z4KfW6BBvlZKljOB2GAW/lpKlaXIzcdjDfZWsssLulUgPRrhsrTnLHMS6ACWs1BeP49KLg+VjJrV9DEHGwI7f0iZSEKzIkOHbSlXP636KtSRMuizoIlVXmS4REdcg729eDEiqYKWIsZGbIDGtw8sToqyvMRyTGZSZwusnW5lHovkNVpZPrm1ONzLERBcBuScNFlQXMLq2DkykM7qVMycOVMzhYPKUa9fOtgHZelPyXrKVa+DrBbgxmvuMGn9NJMv6eUUsSpSS1YuOcxBgy7pLEVOqRh+tZQUvilji1u/kWt68xDJXZirQi5BLM8AP269yuld57MlNvB55gDyHtbdAydcgg47Uz3K25JCaVS6r6cvm2C9kKSj4qJis2cd+8bGuEK9R4k55jcFD590y46mleLegNQYhLgKdZHyG9JSCDNNNyYrkA5DhAxcUNaPOM5wfm9PVnRN9PVOLbJyGVLsza88GiJ1X3X2IuNLlYoim+PuDoE0+GldsbmhGnQuyy/n1UK7OAOGydG8dUKui8DwBPrW0dowi4m1fu9MbpISB8zX5l3D/MYI/57/Au7YD9N6YPT00PT3AAAAAElFTkSuQmCC",
    canister = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVhmV+PkpJfiaGdaGeHh4evwa9hZWc9eJo8ijqLmp9QVFdsa0RBfKGXPUB2TDZBkz2Cf4JXc4iKQj0nKyslXmGOlHq3t7d5NjJ+h4k9b4t7hYmCgn/Mr7IAAFU/k0A+gKZ3fIJ/v7+Afn6qqv+8vsCq//8AAACztbSbqK2SOzs7lTunrLB/f3/////FtLJHeZign1jvAAAAMHRSTlP+mf7+Z/9N///wH//8////YKr/FBv/BP+EoHFg/wP//2IEXwP/AwD9/P///QIC/f4N3k4JAAAByUlEQVR42uWXa3eCIBiAQR0Nqm3eqrX7TdQX6v//u0GiGVBa24eds+eERzg8vhzkRULFhSB/sxCZKkKXbKwoxNtC9hukXDA2KArjpOpHet3lBxuKmJH1Cu+g2LB+HYyYrTAtS2gwN1wV9QxySmSU6/42WuawOiGS8jgApBDnic24ofxjIvhF1c4vEcvLxDbmZSKMnBxKaaCg1NT5QERa7voHwbajqesnkIIdE9N4p0y2LgGN00Iez44s1uLMMJk08YJZEA+l1X2wVf1bXvZiMSj2PI0Z6WnxKWVx4Mc7VNnwJRnu5n8P51y/XYqZXDQdPa9jn8Zgw4FYEUXBIgMGbgPQ3WDTKTKiLDA/C6yD/SvxyoVvPByKn5wilzz0QK2I6NrhdnqzrGyW4cYSFc+14ralRtObJOk583lVJZUjXiNUH6LF0BJDS7xSYl27YuXiiPUoce4O9T+Io2Z17hE9TKdJ0i21pF051pKjKHeWap6PWKtufqgWNzceH8flI/T2rHazs0TwenBQ0VV96Yu789O4/PeIYAXrxnYwcPiNPSfyzsGgqE+m0fvDg97e7zqiPoS03wiMo+YciX52JhcLMYqjn7mf/wsY5hvWAZn/anYlHwAAAABJRU5ErkJggg==",
    clippers = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVYVwCbmABZWVmYlZefnpgtLRelogCNi4xubAOppgCgnZ7k4ABxcHGdmwDAvQLZzwDFwgB2dACAfoDAvADMzMwoQF54f4t7g4OBfX2fnFH/AAD/qgD/v/8AAACppqj//wDLyADZ1gB/fgC2s7OqqgD///+sqQB9fH2ZmZm5tgC5tQG5tgWqqqq4tQCqqADLxwBvE6lMAAAAMHRSTlMkYx+f5RQVY1DhJP5UlvoFpo13ogX+/h1HsgEDBAD4Afn8A/sDAbMHBa7W9gORi84ChUgKAAACYUlEQVR42s3W6XaiMBQA4ABJZFW7zD43C2sBgfd/u7kJWukcy/ar6mnRw+fd0jQEdj7I44/TvRDkiefpHjhqyTdBCXw4d46/I1UeKa3UMAzORuiop6cgaI96+LRPj2Gp7C9fnTHvDZCpwQKuezhtgUSXCCRm7N8zlXIJSkzRgRyvEs0mnwJfgCkkithIwfBeooS6gz9LEZuxN0TVtyjoItVNO/WwRtXYW8g1Y1Nep4NAd5PhkAeZEpXIPM9TR48ZGxcl4Le6ZuM3PYS5beZkmr8l9LrENvmBfiGfRzxBrWvH4QSOY8Yn4wjk0siaz0UsAx0dm1Il4xAc68yVH0TO7JIjjlMqZTM2yyCwzlzqjsm5Pyuz7JoWp2krbtKbi87z40hzLklzVETCGC+9uheQ6fwOkIOFwHuFlRpoXHd3C5A3um11T4Bgi6J6xZ5zAZdS+qtV+CxNU62Ty9BFKETWtqohgBL7+dHNQJEJQdue4f29KtV51dZRAPMEFRnFSfJUQmLqSxdhBfBTZN+/Cc+1t+PLJ/9vWuRRuMrDNDEim5QlF1MtIKToDHW3bMivEAvDvI3wLxxMOOq62+AFQpOjx+CwCRbW0Rg7G2+BuNAwTRxCUUFM10PjMhOugDeTKl0JQ6gwHDPztzDz1v1/fINQiGe7bq4wXgVDdKa627cgfH83B3EO1DPgDsWPFRErCL34muYNUrYmVTeuzBAmMDusOjww9qGgERbbzzkm1XAPfAUPx19thxfwPNgT0cIC9tToHXBN7In4fMAf22EB8XxvPj92MnffQRfYzhPy7qP1F4T/ANGCVijIvN1xAAAAAElFTkSuQmCC",
    cobaltguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUSIaJjYmKgoaWeptmqqrGLjJMhISEIHspZZa1ebMpycnKtq644Rqa6w+IAAP93h9DQ0+y9wL0PHHjBvrsdH2R6fJeQl8fQ0NBrbJJncbIA//9jYxt9greAfXyHhH/Cv8EnNYwzTMZsZ2x/f/+BgX2qqv//AAD//38AAADHxsf///+8vLvV1NPDwrwEF7LQ1u4Ptv5AAAAAMHRSTlP4JJ/w2WQV/fb7TBD6/AHz//n77x1anB0fsAEP8V1j+G3/ogI3AwECAPoB9f76/P1zLNzkAAAChklEQVR42uWW6W6jQBCE54ThxmfsnHsvMwzw/m+31WC8UYJtyI/VSunEkWLpc1XXdJth1QeLfSbQneqfKSZ3SXJHr6Ryi0BtbW1RXlXzyLPVZ5CE1iJeogiRJ0VkDU0dLEq14orskqxYlGpScUF2Z5KvjsNVwUh6atQtOce49gOpbpFvB0ATaV+kt4jo93zQVTEiklZu0GiAvmcrIiLlx4j4FbfvZtUN4a6GE10y5BARK7sCmaHRixFNbAeniKxdNSs6l0vkhbVCRE2NH+8vNXppHxERuKZBRDjRvH8vd7dBigjhNk1tyxqNfs/z/B7vb28r9vO3gWbjz6N72PFJ0P16E27TF5ZUbINg++UYST3avvKdA83n2vect9IwxkIWycMY1at91EJzHgSvNWn+MHwvtpNR27aMyWQKVNZvhHiKOSoYw7W2F+1kyljLot1kODRsqKZWSggdx8C/1X4kGTQjwacWuaoCrTzK4rdRhOOPtRlQX0pIhlJPKdL3ONfiJIIPKL1VRmUd/d+VEQKaBoE5UhWQ7U1jRZRZR1n/SQiIsbPXd8eRkONYbOypMrNmETSHgNap3A25TpwjGQ64tidRhMKMhNs+oHWxvwiOrrWgjAgksiTf3eM6ksHNpxVQBZWvbdiyVGadR0AmLYY9uwL2zcoyw8yAZAUa9Z00Rt+7W89HBKURZRuGIdktpCw7qdSMB2vi9GPPEcpYmqbGSBlv3S2QV/yY/gVRxijRD/J1MMc6Ry0ZpWIp3Io4mGGVdqaAV9JKIymxdzMvDwnS6depKI47/jD/1nGouIyMMfu95ouuKw9oUu31D+rL8WX3nKEt99MtvSAhfMfdh25W+ae/r/7/4B8XWrgGWJ3z3QAAAABJRU5ErkJggg==",
    coconutbelt = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAADuDiNHNSePcWGdm5vi4+NuX1QDDZ1eRzg4Kh0acOj4Cwsum97pXWH///8AA/sDHc50b2xtZVYDFZOkKSgBCHBgHBUzKhoAIKvRJy+qs7RQSDhkc2kCD2UIGpUAFssQYBQLT2sziq8dm8p7g4RBqdj/AHHkN0PSqq87aXQZXeUgoepRSjO/Oz+wJyCkRDOF+ja4AAAAMHRSTlMA+vz7+v36+vjx/QLu/QEB7wefX1sZEZoDriRdX1iwqxEa+Gv6/wL///4EmxYS7vxR9KDTAAABsElEQVR42u2U2VbCMBRFb5P0ktqRzsggAirO//93niTFtooLfXV1Q+lws5uTNIVoYmLiP3Ef1peazL9fqqnEbxiGF7SQ6lGTeyo9b1G6k0HldJgklGC3PJOTyPOMa+MmY7U7zaWUVJce0euwvl14nnPN5ZclmnE+NwHhXQP9/u4ajMaTvOTSO4HMsiOv7dB8Q1cdWG36lC4l92Yc48xB8+TaeX5sa1+nfqm1On56fPLQJ/pTVjy+oVb2c/dExU1BJFh194xjzdyrREo5E5EWg6fRUpEB4i7NQ6y1ZpK4EQIzG09ZV72Vt8OUKVXZLLshlI4P8FhooXxlbqQh6l5cmQc6oKI1xNUBJRXHSjvRbMisdQ5LGvXcclojK0qspDwIoNnkNZ/dLrqLzBfbfr+nUVikLbKCDoowKbkRRSB9nwXEKLr6BPbzF7EiTOwqh7aiphe14KtZz6b4njV1q39rjl2XzAF2j71YVF3DMW2LRWJenq3rUgTBUNxYrf3xlXOvKszAqkLsrEjGStvL/waNFUETZbPZupuGX9EgadAQPW/o7Mh+Q/VHKzkt5YmJif/KB5nvGRmb/A7wAAAAAElFTkSuQmCC",
    coconutcanister = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAACMaVbu7+90W0liSzgXDwqhoaFMNSk5kTlQllGLODhmYGNsGRX7+/uesdOJZVQGCG6chXSUO0HTqKigzKe3yeNsbBihp6UoHRQ3LBsLKdFaWVdEljyhXV13VEaPRjzXXHM7UjA7lEFlTTyJbGLUxL5/f79edoq/v7+grK+r7u7/AAD/qqoAALQAEI4NGq5gFq3NAAAAMHRSTlMA/f79/vz7+/79/BATAf2lDPz++Pj6Clheid1b/gSu/938/KJw/wRQBKcEAQMDRIRJsvgLAAACgElEQVR42u2W65KiMBCFEzp0QATEG46M4+p4dy7v/3bbSQcBxdv82605BRam8tXpdDcJQvzq31A0/gE0iz74IY6iJ7Cxpbqnv4+GGBO0St+kTEkr4j8eQk1oqawpLXjwvsxsAAtp3/dBpt1HMAoRaLqviFO+e0prS77DGafaU3rP793FR7IRK+3Mb5Jd8W7WZqa6NUqZgebHNzHbHeJdGxeTn5kEPmBmIXNnZXavlz0WAM6Jf5XWUJUFojwXefsCCYOqGHalugIzj9RGjgHYkn21Rs8Dv+ZpQK/ZC1EuPA8VqJI0DnYe+JXlwAyYXFTKzRCqypLm2WlEVpZ2ZNBoz30LmDGIJxDQY8tK3yMzIh0ILlQ7byDPskOW8dFSvbg3tWB2Al1uJWJWe02As/On7Nse3RyUUmWwrpr1ol6Cn+LLgZpBxbGCbArUheMXh7pWpaWsqlm1UVuo04Qzz6ByLKfILZrsEM7BXgMsF1o2Edghk2J2lGUHNMEaVvrSmrmCiFzG2amOU84OUHbo/dMK2FnVKaNRkiT7quU+j98VSDlCPBkirr2aEDEpmm/GiOth34irSgjEqLZrmRagKEaoroHrAdpNoHexwRZJggnCJTgwzao7Hbrmadt2I0wcdXA4HIZhqAggGbuOTONZ286/3W4L2mS8ESNhQHqF+VzOZb/TN/TqxlGgAcNFYEXsMgRFRL/f7zDY5njYbDZCTHxE40QKgmUQwpwguuzOGrWBZcATHIbBa+BEjtznoujePrF2IsdwScQytCKQukc/dKoORcCMbV1Nh8fkkVOOCrMXhYDFYkG7MVEvhB2f+A6YvBiJyRMfAfHh7Aj7ibriV/+3/gJtsiIyPi795gAAAABJRU5ErkJggg==",
    coconutclogs = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAABfSDdLOClzWkqKaVTZ4esfGRSgnai0yNyttMhmGhVvXyloWlZyVkM1JRtINigAAnABEuiuCR34AAZJNilbRjeeXVn//wA6Kx8FEZ9EV9+bAhL///8AD/+XAxAIItlvU0GaAw2RhHoaDXk7MkoqVao0SupkSzmBYEqNa1Syq6vEDSDQLEjORVvLxL7IzdFC7HBaAAAAMHRSTlMA+/v+/P76/P76DxQSnliXC/HxAmlUDQGQ4ficAQJlnV0j/2PlBvybd7EU7f//7Kd/E3BiAAACaUlEQVR42u2V2XbjIAyGJcDGJrbjOEuTJs0kaaf78v5vVwmBt7QXczvH/zl1auCDX0JggEmTJnVa/t5VzFgOwMkrvxf8XK9PBcDsF2ozfD/A2pC0yJgTxAkH8rPNHK8YWm5ghcQpERK6+XlR91yiQqS/8qV84pYV8nD0HDUbU/J0Iz2/sC3ieKzW6MjqnN6iWSM6jTAeEkSD+MfR3PMwj4Qq3SNQYcgBercelOlUjNGPQDUCtzbJsjzPbWYDuT7MCOTYlLZJ1CUdgRXkoizRtDqDAF/az6F0EjptrrdjkKO3Xn5FjSvIE6v8kjqzUboachuQ/FFaJRzUn182Sy6K32NWNe3puAJKE6X9nmmKh2yz75AZ6cXBPhZQdhtF+43qwonIMiIxFE1UOeDWPY7dShaBSevBAfkaKw0KzQFqI3GgCalvLC9pQlVwnydXXaUbnaYaUxVq4FO4R/jwZpOWDL5eyaMci1IRmKap1IbJhFvcv1kJMxSiDmR7KKhAaDUVQC11crsAOL5TNSW8m0JysLQ5JWwiSHlMuwK3nvtzA66h/OTWSA16T0jeymCVjp1SvlHEOSXu7x0t+ZYTqEPZ0xhFD3zqTrMH5bTSwwpXw/Kw/yCQGtH3cTD0T5vWAh6YjOfnAW4XFGDNQZwbf1ykeLgyaE3sleu9IALvdszdyX24f2errTgiBf1Lbd72wW63q4WD8/LcgGn6XKqqNjdk6wDVnNu3K/Amuyv42DSNwg5UowPpepXbRx3s9/tj50dVV5dj3FSo6/p6ysqHn26h57O7kp37+Xsh34yqklv6n7407jqkSZP+d30D3WAczIbIcEAAAAAASUVORK5CYII=",
    compressor = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVlZ2MeKSofIyoZHyVXNDdnZmgVHiU5VEVeXl8mTjJWj1FaWlyWZmX///82O0MAXV1+foA9lkFyUDlePEEAAGo0OEJGQj5GkD6RQT9JJCN9gouAfYAAAP83jTYA//9KKSWAgIH/AAAAAACJiYsXIytVVFY8lTyTOj1MTE6QREVJmEwUGySWPUCQkZUpJy9oaGmeYnizAAAAMHRSTlPy8hti/Kig/g/7/1r/Af4C8v///wKlnf//Sv//Af8Bgt0BAP38/v//+v///v/+/f7ha9E6AAADDklEQVR42tWW2XLrIAyGBd7txHGW7me1IcHx9v5vdyTAa+O0cy460z+TGGf4ECAhAfl/Cr4zGG639NiG1Lb/bT9rkfOxxceXO+A2Dz0UAP6EeUItoJfkA3CbJ0VTNE2B36bwdIvUFMlyuguL3LNdTfdRGV+QSxCKFSVfDWbhfTD8swLCB2v0OpBane0vpfkDHu+6g3tSoaRU0oLKSj7yu+54NPakshYz+y7Bu2vxRS1AkAP5wu+ALpiJqgEcpqrc3/nf2yDPfVeHZoeybsk6KwCX8RWLu9xP5SzOpn6UrPJzfhMMc19BtuZHqYSTr05VwppFBFtndXMepII1UCG446fdHPxlTv0DtLfBBlolWb8VU4uOz0ipUK+6I51mfYobI8VSyXwHhftzGkDHF71algaBohAFeIVON9Cx7dCB+aNFzsSoyor6tMPrpINgDtnUFn1xS5WYA4P8Yaq+YAEpigIdOhGLUEHqukeXtW3LWly/brU0Z4c2CHTECAbx1SiOY/qh1oaE47iubm0OrgvHlkCuQZ47lYDr03W/P6Oerv0QUJdLbWAJBtfzTD/P+6fDZa7n8lK6uJHcrhFBMQPRGtrGqV7qsq5rRIxpbCFYsTEAFqCGz+f4cKl7Y7UVWfTzHz3IGYsW4PkeuBtCjokVsJ6DJbQEngbQF9He7OmofTzZHByBVqtBZ1gjOTKKrwvwfJjuqt6iS3lsq/fgUnB4pr284HaWGi4JFDb19KCgaIsw6iDWUQcBPssSys3o/Wf0RiWmp4P8wZhgM0URc1HgasHRPMUUREciJqr+UAh9jhirJsJIZybG/XnO4fxBBUFqrWGPNO1Pw+JsOctklVC6V7LTFUCncjz72MCEEKR6zJQ5mGIWIF4xTKF6g26oc2/S1JKue194RpAr6qYw92eQmbyc9eVgYwqPl4fDpWcKanVF8+7O0cAA3rIIfSXUBQe8JAGTGwsze3UTpDIO+h7l5GGCoi48oWuWl/RVcgW0V7fJNauXg+PRMpxJufrUtROHc2wW/7qLbsjx803v5P8AUVd5IijV/WQAAAAASUVORK5CYII=",
    crimsonguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAADOysi5trWqDSbapqv9/f1kZGPKBCKmoJ7Owryek5LMXm5xcG6qVWGrM0auqKnZdIbavMO8wL29xMH/f3+rdnWTc3XFN0v/q6tgJiVHQjeUFSigeoH/AADlOXLdTmv/f7/YkJvMoKD8tcbKy8o3S0R/AAB7Chx8Okl/gYG/AD+2Hz+5coC6vMC9wLv/f56cyX+EAAAAMHRSTlMA++779gEZ/qH4ZPxN+PsO/Pfu9wIXVv8EWxedlQEEWwRlrFhZJQKQZGwEWPz8WloaqKfSAAACH0lEQVR42u2W547qMBCFY3sycUtCYCnb6+3t/d/uzowD7CYE8P1xpZX2SCAj5cuZZpui+NC7ELassv1ffmXZvvz23r94zAQLq0T2itY5nNcspTGTI0MBfRZH8omzWOYliFpACjSzNlYwHXMD/aadBJrLpUCVzu6+TVzMbX1MLcwMFCXQX8yNwfLErEmgo9aX8htjnAyUwPlwZDBh0WqlhmS5/LydtbmzVyW+2ppCrSxjY5B0QZxTg9mWF6DvKedHY79a0dcSqPVd5/kde8Weol3mB15t0UK4vry0xIGCN+n5HlJcsWIwvbQBZ8aYAgC0gvrLtvRo54I4/thxR24LvAnGBAoUVEer676G84Xa2cUDnUyGDQWpoaNVZb76XV577JAe6fEZKE6QQqZlR08vxK/jKHFy0oKpCSI1Rrz5+a24lhPj5gM97IDQmg0D9MhCWkfYlONTkMo4CJzgHmQ7PDLdqBsyJEfuCYGw68HBWr6qad3MiFOcYFVJiql1pw5yqGsAxwlWJC6TY87GU3sXuKKcYCVgUOSuwB/furx3f1IbnOPCCMiGMmB43JAntKPPlltDKkp7+nSqSWHdg9Wa3P106/aGN0Ak973q1QTAcnnGyeathhCaHWsae+6tgZ5yDMGYNADBn30fMvtErNg2gG/PjiPohuFP0dLU8dgWGfeb3KHt8/Of+x/3j3nXxi0W/6yLzebh7vvdw8cfxPelvzgcFbOpghXIAAAAAElFTkSuQmCC",
    darkscythe = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAAAMCgqPICANBw36bppjAmdPBWsKCAlnGRlpEBB6GxuqVGQ1CEPxdXsbBmn/c/b///88CUtnFxe2PXH/AADldd9cDqJmWKTfY5DeYog4BE1fAYWpSWebV5f/AP/JaMQAAP9GAWJOAG1/f3+HHx+5YLPNWH7kZYf/oeVzU6yZMzOqWqeFWMfMM2bDU23JZsR2+gZ+AAAAMHRSTlMA9Plf9grxp/kNpRanAwkDAfJhFwH2BAx8oHL+UyMBkAFklgKxmpAxBJIFVxcFdG15htVYAAABmUlEQVR42u2W2XKDIBSGDyIoGuMWo2Ztkmbp/v5vV1ATjaaytJc9F46D8/H9HBgV4A9qZkxexOVJGwsBIhNdBNttdTPV9X1lWTaH/GUNuaYwy44E8vdce4lvx/UvOvuw8PjjTfgThw2FyJQzFDqGQmwqRIrCKIVDeAk6nLIwuF8gUjt3fpmCXxSrBsdX4fhWzuDjZNvFyrZPkDZBUc07EqVv11XUIKqFjnSdpKLKdO1ffagTd6xKAZ7bjiLkKLaHr6+EcHPtDEJIjeMRP88z/45T28cgup20WymegCBoNh65GlHb88I5y3L1QNxgojSiQot5CROTOMo6V3DP0DkEar4KSwAYY/VEWK0tVUiOtRGwUlC34gLWmctRCVpz2i+PCvQGg1gB5EIGrJffUQIT8Puj8UIKujzoof/JmtAJzKVg0gsqvtBxjIGMb6NlDYJyRCgl++h68DoEcUzx+O8I8x6NzuVKNlhhk0QoDWrKlVTW2IfvW1jQ5d5ESYDS5W5DDLISysMSE+VuScGMJHRvAoq8C+0/xP/Sq2+6gA7xaChR2gAAAABJRU5ErkJggg==",
    demonmask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUhHBwoJyYeIiMpJSVaGBlYAABiAAAtQ0FCQD5VVVU1QT4AVVVfAABDQT9FQkOZAAD///8AAABsAAAKCAgUFBRRBQYvBweJAAJ4AAA7OjlmAAA2AABXAABSAAFLAQIHBQMtAQJPKClmAAD/AABnAAAIBwYMCAgDFBMJCAcKCQhXAABGMjJmFReuAAAmFBQ4NTS5HDBVAAAAMHRSTlNanhbs8DVd//8D/gOxdf8FAQD8/v7+//4D/LEMbwdKLy7+iQHTUK0Rk9CS/v4D/cs9DazDAAACUElEQVR42u2W2ZqjIBBGcel09+yU4BKixiSms+f9326KRdyioedibmb+Cz4UjlVUFQihfyjyH5wDc1p8khZCgSndwOe4cIHWJFjACltHpXQFBbaECgRh7WxvSwFBoda43sEOXzgaXMJurVylV+zD0s1ZGRCcu1XpyNFr+eSgq+Rgg4jOYwmaTB0CA3KJBpR+S1JQ4cLt0HADrsGQMzbTreZM7oj+1DdNvsx6u1GToFer2iTAQrlhVNZ12bqp1wNw0h9vyvRkyI2lDsdjFEXHPdFpbzgQ/d0hzGtY6iI6RFbHWrq5M+Or/rZqFm6GymPU1SHd2NF8tB+XLbmOhrJjRVObDZjTFzsI8QiMoYnM6AQQdGHBaCxuMp2mI1fTlnwAapOdPJNRRQHwKbC7hbrHzU86DUY6MteJU241ERu9yFO3IAcH3KkBYxTvKOaDU2IA5rJAOIeH6u06MthxxXC2tTk40fqgKgPlmVZ/mftDPQWKev8wMhadAg/93HX7KkdkCtz3uIR3+6ye+1uV5Z61qUsgZkrYY0zM/+YIa8UBDSmOs5h9uIIcrUhLqr0l/AlYWhDNxRrEYkJnn/yRPwJrMUGB7T2zSL0GjEFON13gzBlkNyyhTqioM8jiuI2Ui8WomY2O3hQVvFaQ+bPgOyVBYFAug8lZECYQXuD+dd7iL+p/vwc3XS5wqaCqkkt1gaRwuCD53o8sy6pLWGWvIe7J85fsHObPQVyM95YZnSGpsuzt7jteyYhnyTM2xHe/y/nEu3ueRwjxff9v3R7f//Eb8m87o+DVQBcpwAAAAABJRU5ErkJggg==",
    diamondmask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWb3O5glqba6u55yOD7+/tqcXRwtsrf3+CkpKTPzs9PeYYwZWxWoaUaHCCO0+ddjZujpKVObXVnnK1xd7Ol7u5/9vahrrIWGmEA//+OvMo1YW9FaHNGa3Y+X2g9XGWIr7ohMDQgOkd/VSpTfYxYfYl/f/9mmcx7t8h/w9mZAADJv7vfv98AAAD4+/uK2vJ7yuNKr4ddAAAAMHRSTlP7++78BBT9pxpg+hcMEq9dUmGcCgQCoxEB+mCU8Yrf/URPBkOCAgWZiAVMCAD9/v6Yj0wUAAADB0lEQVR42r2WiXajMAxF5RUIkK1plraz7zOW+f+/mycTINMmhPTMjJrTKOBrWU+yjym80uhfgNb934g2FA7/XgOyvh20Ng8Fswu5uwnM8bEZc5aHS0Hp/CptkQcNMCCyvSViwdmSmXWR6Xp6RFdoGMsfPlnhJoIubLkAnBVLrYsk0STQhlwX+M54WTCcXE8GM9QvtwiFYPZXWJ5N8xyos/S1YhZJbY61uilgrTEaQyGrOMHq5RTQhZpz66RxMg2vRLbZmVrSy2arkSNM81aLOKHWk0ARh4t6lbFW75i3H/BzkqrOOqhJYEh59IBCF0zKUQJqqYQ2xhMnX0/KEWVUaDgyRMYIqQ9cyn4ZB6VvSCIhYtOQdKv3vK3tFXBn6zkf2hVGgLJm8qwfwt04eB8eDkzEOoKIMgF8gKoM5RiIhlFewsXmqEtsNFjynzHnKPigDklS7kzrtFqEdKPibAfk1DQtLufoNlA0DRKLyZLblvXnx7A/C0K2paZIDcrQNGYw/MJjnCE/TqWlQc9yQd43TTzGSuM7w0ye1uGEpF6WT8p4Q8Z7r56b9+ihxvt1NWhL3S5EHdS4AVfui/sT3IdVejmTAcZoamJaJ0X4sobZLL1fhep5jm/wDi+N5IiiN5IjDD7jUZPYmXp8KY6AysQ0Gl1DHWlko4hOXsBVv8H6HMun2ZOKSfu0mUw7hUlNi5qYqJ5ms1XfsoOq9eNbgGLU9opUsPVZtmZUbx93w47ul7rDqbRGMkdORpsTvyFavw8n/XrSclVYiJLd4BS9bTfsMghchsqFEZAitVzbM7rl8NTVF5r8CCImBmMgyeiYxIltxGtglBOgcxGydcmNgF1PQ5iu15Hy0b0YsRzAtNB+R14D78La9KQUUqiUbpoqXlzq17CmZgD7g6eLuLoE7kO1jnRKnnBkFmOHVf2N4jOyy7QaO5Bd2M2pD9q1TDqx7sJm7FzFJhHyhc1dqK7fcxbzZJSaHM73adeVTb9xatcRdrOfcrOq7q1YdyXYbKrbLrqlqypX/v07+W9TmLHvFkXCMwAAAABJRU5ErkJggg==",
    electromagnet = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAADX2QSrz9fP2t729gD7/f0Vb1+X52dr4+J0dADR2l2sqwLMzQNw75qmpgCgr7Scpqmj3aQdemVXXWEni3CytQSep6cJ//+43jDN1qAorp9qqKhq//+8xMUGB1gwtZ5f082pvMjIzgsAH6YAAP8RSzozmXIuwq0uz69ttVVnp6RauJ5WyKK/f3+0v8SYxMvfco/SAAAAMHRSTlMA+vr7AgEf/PoR+g6i/WKfKP1VG2mPWgH8+hwHA28Nmnq4WQYBHAdslZ1VjKYE35foE/9HAAACOUlEQVR42s2W2XKDMAxF5QUbY3ZCCtmT7vv//10lQzvpJKwPnd6ZBCejk6tIwgbgP2hz87d+HjytZoGYZ76Gx0dYTfR7gIW6gf0TbDxvNFbQm8pX+MqV+5mRbkmyTNEQHnI4+Mu0GJ0mF+IjeXsBtYBPIXhSkKcagXInH02LIy5EgthiEFRnICzd6gjvKh8E39toBLEnglZtnt7dUG1cNH/FD2WQNaBq2d45ZIELP+S3lqEC8FICi3TdZ2gQdOGZv9+d3BK/vVeQcwHUpo3qAmMXzfQCdjGrWM0TeMHgBdVX8H2Xo4XScdkbloaxSAsK56n8bEt26HCUEDo/ffJun5mOMhfNt1D7Pi5Q+fVZaECtmQV4zbTmgsLFsQwQJ3alVI9jxcIdwLNmDiQFVC7fTdF9X6osNGDI2iXKeYbrKEM47WrkDwgOrCg7Z4j/F/9AjAEDoDFNXzJHEofS3QMgv/sYt33REQvqgFWRpiHqlnUZktorAZSzu/bNnAT2S7pqwYiysH2WJbsiLAwLrZR9U26uggOJntX1Qu7W6ddV0oCEQc/4AgvHbJDSXpAh9BX03NMGZ1gZj+SAzotvMrYWRtSl0RqWQjSkbTIYfQyAQMGdwVpKOeWYIzCRU0/VNRS4RQk8poyceK5uRQNOfgAgMJnBFQmCKXiTwRQ5PgOU2EWxnPOwMi9TMCFyH+l0PxMguJ1siHcjgTAZNLhbBXU9B3Qb5AmmTqqFdie3M9oRh+WfPuQaa6WEf6ovzpIZN2cZTkUAAAAASUVORK5CYII=",
    elitebarrel = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUQHB0bICQmUi8aHyMZHB5iYjtVj1xXV0c4bEMAAF89k0AAW1tINilXOjJsPUJBkz2PUlZDLyQAAP///wBVVVUAAABQOy5XQjOVPDw7lTssJicWHCIXIiYUGBs3NS9JlUqQREZxQ0YNJBqLQDsVOCQPFRoQFxwNExNFfEsAADWTPkAQFRcOGBoiHBsSFhxGJyzTpwd/AAAAMHRSTlMi4vuiW//9/vsC/wKi3vr//3QBAQMA/f7///39/fz9/v7++f7+aqwX/gT/TpH6x/+w2YDpAAAC7UlEQVR42r2XAVurIBSGIVyumrfVvYPFEFdL3dSt///v7uGAqJt4fXqe7pfBprweoAMfkc03RX4APHnNBU9PYy1fT7MiElLnXhEhcyLmTVFc0p1S6a5VuqOsaPJoEmygfepkEMOlDm8mwLyFJE3P8gySEiu8WYfBi5SaGwkuobSfUVpLWQRBooUVh4vbCi+8xykJgZF5jPFsKXhfQkQhcCXwuX2/ozG07cJiFQBJsmi5a9DeWZUBkLuIvAWFu9xYEzIORi5GN1APumEGwJXoZOO4GfadeBkFy0S4QQ3msu0GDnIUrKUTJKfNMwW/FFMP71Mp6zEwt2lqkzP1Gd6mKj5remCdwxqKQFT1tFMj2ilaEw8y9WHUbwBfU+VCmleYSkFfzefIUAYsC6XvUMu7z04yIOojlsXnMbvP4Lq/P3aK30fFaelB9rnMnrPHDIqe4kNVVfvq0Gpv9XVpwadNA+DbtZ4X21tV+0MHkhB4qKBlNeAGYDDi4SqaKYZdZWNgdg1uD7egWmaPs0HajTH6uJsDuq6y74G/vorNAHybC1K2efgWKAfg0ibLI+h5CqwALFoQinQJWQo/KJ9ykF9bk2SmvYu3rZIBSJU268EukRjL43GxSN7XkNX79XrvtX7vumpAFC7JDyeFy0+bdaS5KWPYd75+xb3J6Zup0mAtxl3gMus5xVWPa3mHO4Kk6hYEFcqgIgYJqGFr060kvgoclm3+jOzk6IKwl2FbY3La9gE4ittIHTAdBn7q3BhLGKzb5+DL+axZ0Oa4MJ1Ke35uX4OT1G3kt8aaLIS1XzND2tiw5lS3HsuDxmoN0rSLvd8J50Ki53LX4G+wZO5d8dopOX+BFoGIJBE9q3Fm7J2dTJxzmOjc30d0tsymDki55G3rzt1sJevJI1kB8ygGssccqZrN0xRYNilmTuesaBnnS1T+6/QYNRf4k6NZoXVBAlyKhsw6dtY5Y4UTY3lNfv5ofSJ+Il4fRk7X5L//F/AXoLwcBskFr3QAAAAASUVORK5CYII=",
    eliteblueguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUnMl8LGDAPI0guRH42YLk4Y8YAGQAQEA4UKVMAAAALDA8PExYnWssNFCkWO40UJk0FBggGBwoJCgwwV7EpSJIGDSYQEhQbN3AICgwICxIjOHIYQI8KCw8LG0YbSKwiPIUPERMbMlwXJTUVK2MmS6kOEBQJFiw0U5YTEhMMHjAJFCUKGi8VKlAdULceWsUgLFlLzgBLAAAAMHRSTlP/nmb///8KfJ8A+/z//f79LU1z/f760f6M0P//q/v//7D8//3/k078Wi1t0qb///9BSNcbAAAB60lEQVR42u2W23KbMBCGSdL0IFXWIiGQMCCDsZ1Tk/d/u67ApgqoMXgy0174Hy75WO3q312iHxcquoJX8HPAGC4DY/K8vwQEQhv+8vL99nb/+Ph1AagJZQ13Kp9vbp6e9gCzQEFOUkoxJ2pMoYUQWsSDpiAYMkNmCuo5HCkmYDyLI2IMQkrpHHCSo57FUQojECjFKqrz6Pg6Csbr3F2guwVFw8KIegQKwuo8tzkqQ7xpulucajMyABjGsxXKWpuh8ryuOweN8N3YOQVhUWJXg9brJFmv3Se4D+qx5QSent8lbVu1laOOND53kZewmHh14/LmifyJ+lVV+JxgmzN1jJnGAZN/cyUre7KXbKsKo9volGUKwe6IU0pUmXlkjydvLBTQN0CBMdm2xbdfXz3y7VQcYsRf+tF5TvHky/uQQ1VdY0C4kYWzOZbo3gdrNnDEK+v7CRAbV6KVlIGIXkuFhhUmqtTWO27yxwBDSwXn6q5PVAZALA98MMmFI0srQxGLD1dAnHb3cjiCpddT4szu2FBGMFHZGaA0Quw2KYoQOLd0uuPyHEm5Yl0YQAl9flv1x7XyXm4VLFpz4PqFZYdDaRbuR9jRhuIYYnrxYhWukszA8o3sEh2G07JVXvhTZgkIDw/w//51XMF/Cf4GOd+FSIsEQqoAAAAASUVORK5CYII=",
    eliteredguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVeHSBTFxSGIR/JICgAAAAREhMTDRC6GRTDGBMvCAkKBAQNCwuRJSWvIiMLCAiuIhsMCgsSDAtKCg1wGBgzFRYPCwxTExOJGhp/AACPHCIQEBE1CAZuJCVVIySUGxuIJBxKBARJCwlIGBa1HiEXEBA3GRkuEQxVEgx0IBz/AAAJEAkOEA4iCQQgDAYoIB5GDwyRsvXcAAAAMHRSTlPnu8H/APz7/v77L479/FD7bM78+/mu9/4C/NLX+vzB/ijRKP6zJ6rS+wFNezS+97iCi39GAAABw0lEQVR42u3V13KrMBAGYJKAFHUk2oHgOI7T6/u/3VkhO1YhxbnJDf+MPcPFN7vSCpTlv0y2wAX+DaQ2v4ElapqGQUobSX9eERVBWIIfH+fXWIawQMUwNIx+vzlU7wDkwDW0L6mXmV1lh1qTdw8EcgHZbO7vN+93dx89eOPQO+bDum0rl/War/lYI5lCNrWJ9h3bP5JxYaOmCD4SVKaQahQuEGAvzs4hSmGI6A3RM63CLEMHsNueT7EO84oQOXfkbElPIQvVwYmHljSzZ5W+WvixyiKEirdEyxn4L789IeEqAeI9VKojiOWz8DozBPknwIdi3R52JoanlYNBRYwtVPyBkDKfh1eX3AS9ItMJ7KDgYcEYrkiwRtML7CKgGZl/AevgAJgeu1FsO5h9/hm8vqx8hxy0e6N4XDAahyFFBLc7aLzZJwfg5YJEL7Pp3M70wewTyIr4K9ByMcEqHEUEn4sEmgkKbsJRhPApdVARpji9FeUXH+Sk06JecYGVSHcmfh8ZawYfvq3GkfOxrYn87gqgUpbsZhj246zrOoPfzQ/vDuBMa+0+W3ae8phLh1LJmmY69Oz42wo0rJwuV/kCF3hE/gMoYUdTI+9ziQAAAABJRU5ErkJggg==",
    firemask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUrGxqhbR5hWlpaDwVnGg1KEg1oaGivqi9QS0s2HhpTTk1HGhQ7BwGVb17oo2k4BwGqAACCGAmDFQb///9tdBpmYBoAVTgAVVVsXhuZZmarclWqqlW7hGT/AP///1X/xm8AAABwDAKKEgSLCgG1pS1SCQKRJwp6EQR7AACsiSeTNg6wlyqZVhj/AABVAACVRhPi3AREAAAAMHRSTlMa/e+f5FgF+GNRoSma8PfpA9i2AQukCQNnBWsD+AED/gD9/v7++f79Av79/v4BA/7Uq21sAAACfElEQVR42rWW2ZKbMBBFW0iAwevEnuzJCMQiCTD//3fpFvaME1uAqcp9oQp0uL1JAHKhwP8oWgoudlytl4IpwLJQYaHjUaapv0Kjb00DWBROtA78liNgiH4rDPhJMIIwWK38z8FfmiQIAj858sY0SLCVUfRsqOSYwPOhRnIVBEv6GEnAFI+woI+wzFEeEdx+j74tynGbPj1yp1+w3e62QQqeaL2Oa7ndvSHpGwEPeO7k5x3qZ7DqngEP8suaCyFehEg8ax7e7GTIywxVlqUI0X8meJAhUTUJrzyZ6dhJnv2lMnngeQ/qgcsHDSTck3B/I7zhLiTH8KfAAxnmN6JEMViYAMmwrnP1ocESuglQ/3AZqjyvrqLSCjjBOPhb8tr2jBnTFIMaw1hL3ZzI8SszRexU3CiOX0GPgac4JgfGemvfY7W271v2OurIW1vdVuamRDX3g8AzWkQ9yOrsTsIDdlKoy2SjrovF9QbqdvQ+wLOEK1Krig3dV5WxisanLPf7PUj9yFHDvtyXbmwUa9pKOdSYy6TvN4k/x2QjaD8pZYqGnFTeNnHv8hUTAxC6salYUbQOxDFgDtxgRH5QE1hnlTG4nsCKwCpz4JjjAKJPXMQDSGPjLKfANe1F1RvDqDhKMZy8wREmQNcNHAI3B5hk3+YuRy6nwSy3+dALZ1rVc3IcwIZdLNG7NZfTY0aOmS2sMtgPZW3e2Ky+b+O/fezOVNZctbi5mh67YZqWRoLD1EamhlBurFe26VmrLBWKS6mnTgAkhUsO4zSM6lsLPuskx1eH/IUkPpF4SDtuzifA7Tn6T7k+6/Tcr5V+P7e7rjucn/mw6vNZa/1ffub/ALirdz2Aw/qWAAAAAElFTkSuQmCC",
    glider = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVjXh5mXR4LEBMQFhkqLycZICB0aiJfWiWJfCiklC9fX19SUlKIeyby5Rm4uCqQgyr///8AAGoAampIPRiqqlUAAP8A/wC/fwCMfyePgyv/fwD//1UAAAAZGRkQGiKWiCsoKCimly8OFh04ODZ/fwAOFhsAADWShCoGCgwRFRgOFRs4OBANFRssKQ8kKiRsZie2uak6AAAAMHRSTlMVYFqZIu+Y7uz5G2iiAwOrAQICHQMBAQRgQAIDAAv8+wz99wgC0QTRLjSsCWkS/PLKjV10AAAB0klEQVR42u2VaXObMBCGhbjBsXP2XFkSEpcN4f//u+6K0CYu4DTT6YcOC8MwYh/evRAMPmhsAzfwvwGt/XOwmm5uH5l9J8i+v9y07MVlf34HaG8I4V13Kos4iSLP8wKAx2sg2wN4kR8eRxu0RIsjDvBpFUQ175DK5+NksSPl4PMril4ttUZwknyWoyVxyRfBW8RSjZY6xQKPCUxkEoZls6TIE+1Mhg4rSr9rsTZRFMXJUKD586Afj5jUQ1j6vHWLTz/filU+FnwG9MM01SnGVR8YxQ2KVhUI2zNLTWr8U1E0l2CDXSNK1ztcD6oAhMBlg2f2a5Y4h7u3IHLHJJU6+YKrjAZFKQF0mFdjeH+Z4z1gEEUsd1/R7eHsolQwgmtDXkFXUP29HgM7G3QeTwevfh1NiVzZQtWThhr9hQEl1j8rc8K2nQRQjJSUcSEKNdZnGfzWoR711ihyny6IXVPEBDlUyjiUGKNQzlwFoyFsqT2umAaFBImR7nqoD1p7b4cBUUV5BsHKZsWg1ofPF9MnVED5ZiugBU/K/rdHQuV5Bnm2CFpgNQY6swuaPF9qI7ip3On6AxuyhWAn2fyum70e75ni9OzmH/877H77sW7gBv498AcaxlLUWpeJPwAAAABJRU5ErkJggg==",
    goldenrake = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVeXytfYjMjKxpocURhYmBkaTl5hUuCfTr//wBgaEt3hExrckwiZhmmpi+Ggj2rq253czeAfEL///+LiU6LjVBVLhL//39mmFiBezsxMSo7Pk1+gD1zg02h5V0AAH8/QVEA/wBmmTO/fz+AfUCBkFOqqqqGiaz/qlUAAACKiUeVlEp5djl6dzpaZDp/fwBSWjb9wGEvAAAAMHRSTlMcXhSmB5rj7gFjqtUWBPAE0uoBoN4kAg2mQlXtYgQCjQEFBK9DA/8DAPv+sPqMAmxzhDlMAAACQ0lEQVR42r2W6ZbaMAyF5TUrYYfO1uleycT4/d+uMjAFhpI4OT3jnzn+cq2rxQYcueA/gfvpYhQI4xT3iHK5HKW4XK1Ioh4AshhKQxk5EjhJBjU7AoYoy4hakRbpaROIlto2ggo36TFGLGszEqyaKBh3TXHHau2cF9E8LcIDqFG0x0XUqAEgB2VmswPp6CnR1FNA8LYsVTjA1XPGa8G2JpHv9uQIbilTyIM5xVlygoKYTAIlFo94SbpSjmlkYHKHeZ1kjr4lBymeTrg5kuskUOND9Xr+LNynY6/1gj+x+FVdZKWXPCtK9Xg5RQ7k8PGY/0bf7dAFeO3tFE0n2VVcB7IeM8l3kbypZrnuBSWT8spbjgZmq2heF5ifyMvApWhciS89ijrXO/f9LwkLhJ0jW/IPejpPo45xLt7sEE+uqozCr73NvuWQTmSO6x1Z65UpItXX61PUzSmforFWGV9VInZD75Bg/zKaAftErvRGGeXrmNz+6RLJJjMNxVNGMPkq/YaCLxWnVPBKKUi+g6OZc6es8N5HX/aJ4ITNdHZVBMOclJt9sqLIOOXBG28CJD8XYtE1biWUYD24KtvuWo1yxJgPXtR49TiAjjTw9e7IWIiggHcTCO6XaZSrLJQihKK42Qh3jxlfE9VD+RyC4Jx/SZwAesHFTUGVhZJK1lqnjg6+6Wypwo9SKij0kJnzguUzWjDArvxzMN8Dt7nyYGUoUOpBU65GWW1DuP+ug/sdbAXKEQP5M0Kdf8DT+iqXe/xgxe71BysrvkQ2hXSbAAAAAElFTkSuQmCC",
    gummyballer = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAADac+Tqh/IL+egH9LrrdfKnXar//P8C/eumWK1nMGubpuv/AP9wZHEAomkGdGpK1umuZ7fTc90C5LD/r/8Hs6O4c8rGbdQD66/hhem5Z8UA/39cWpEGtKMF7K5/f+mwP62qZ8cAAP8Afz8BvrgA/wAD/9l3PoJ8WoJ/kapxk7x+uPS7Zciqqqq3gL7/AFXhBbXKAAAAMHRSTlMA+fv98goTAQZaE/0BEh4O+aCfpQMX7nBfp5kCGUkZBBwTAQSCAYAxWqbj/HED4wM2F+WcAAAB4klEQVR42q2WR4LbMAxFQVIs6lS14/G09GRK7n+7ACq2sjKgyV9w9wQQHwAF8D9UWmvdDs5OZ19KOQ9waA9u/YCAOyhSm4nIzx5atchRcK76Jd5CFlyugOzKqUZSULsBVcYGHVi9F9wXsYDzFixFLm5yFfiIZb34qFJJ4zj4sXInWcthQVp5vFVpmm2b3FnvvT3z5so/XbC1ZW8Xuciug0xU+olU8lsXAh0nvagEgbF/Un0VDg9Tw9eotyBvQIO/N6grp5igBeJMroiZwZ7HHWYujyYSiYNteUtEv5iIHOGRWv8nMLbtm5/LqXScEkaQVxvcdktJ4pwwraDH29wzrP5NqRKnSxAFVDrPMc9RN9x5vrhHGpU+c0DMSi3xyAfi4j3T/HYKtSwgjV4Oc8vfBJ+VXimt8yRJBvb2SZvpdu/Nr8mQJ+Y4TmZndVnifauqHnE9e+6m/GcLUQPseN8dvNLey+SkhRM+mL2Vkz3Qiu7lYAGOkrV7kk3pdX+8E4csoJlf9ztxZd2omvCAvopJTDYmXSUlvxTV7zExphtCEIEBjga7PTGd8JoX0BxhkIADVMlMHuFBGLIzc6pQi8A61AnNZlcFGYhxqq7DdCthRIBvRH8/7vitqCYLA+xRHQb4uP4C2PAS6azc0hsAAAAASUVORK5CYII=",
    gummyboots = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAACkZKwjqHa6bMXBacoix4hV+/QTcWgruYVgo5ytlsyW1dpsXHGMi7All20jmW2TXJr///846aliPWRl7/UgsGskw4YK//RQxZ8A/wBvbIuRX5kkZE4luoMO8H9sTXL/AP8AYAodd1kawX4+/vVMNlFVqlVV2Nf/qv/HjNw/KlUmwIRoTW57VX96SYFjdoULcikWAAAAMHRSTlMA+/j+/vv/D/r++v4S/l+npQEEEQgNqAH/AfhfTKMDYwES//7/RwNgA/8Mf434bLOYfIj3AAABvUlEQVR42u2W2XaDIBBAB9CAGybu2Zum2br+/98VVASNmrRvOSf3wROOXGYccAzAkyePx8vI6BYHiFuyf4fj+/7nFyqZTr+3YnjWN999P47j6tLxzrBECkKIuG7larBcTiVI04kHiWtJgzQTpks5n1gWIZZ5A2ammMDJKz1Lgcjl4tYQZEactWOeXEIaU8RwAtdrEO5ARNgukPakyAJvovHcfvFQ10SLiE0mb4Y5IBLl1ZkKERd3iYraE0+EHTPVfpGKiERnWtZh8bpw29W5Fn2ZqhGxFut5gUAW9VqksPtBev9ah6CmV6RzCJkjCGR9KrcrInOtua8CArbxfm/bjFULBGgUXRkhMrsFwyMip40YimAtEQ+LjlNgYx8p5+t1ljWRB0VHLBo2Wm4u8JFl6xAj6NUKhk0RdpRGmzxqxivWVyKnEOEk4iXsQNM0iqIkwQxflThwbFZ5K0gH2g/FGuVXWUroSOMKcQdm11maD9gn2rgfthpvlTzDWJ6krhdSON5qs5yHYWkbHi+PyxjHXO0qN2wOOb3Z18XGRmqLSpuJNJN7vySUprn6Rf/8DaObTfM2/IP5/Pk34MmD8gtKZhnFLfDKUgAAAABJRU5ErkJggg==",
    gummymask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAADNbdcY6Ju5bMataLhJyZ6fkcvWhOBlsK6mZK7//P9kImaHmrlvYXKPXZWZYZ7/AP/6pfpMp3F3r8PkdecKf39oV3EG6J8A///PhNoAAP8mn2cky5FVqmp///+7bMUbWiU2to0A/wB7VYOqqqrRedQmV0kuoXgurYdqPGZwdZBVoaNoi6N//793w8Ilh2a1CXTAAAAAMHRSTlMA/v779/3+9/yfAQ77EFkaAQSj/gQCV6wBsQEaDwQCqxHpAWIDm0OhrEqTH04E/3ovzAzCAAACaUlEQVR42s2W7XajIBCGB1FARFxNmo+mSZO023bbbff+724HjEoSoORf3+OJmsPDzDDMIMCP0d32U8Luc3t3I7edHje3cBKg6/DqusVN9nYAhSisRNGlc6vjHjJUcWLTFwY2B3EYwew1Nc4dfDA2O4Fo+QAPqeDfmRAi67Ese0sFpQWLPkz8eU1ORg1fTAyOZtk/N61xvau8lzKWXyBx/1Rl7kq9wHMSt8jpGUjzCubfQb8A9DlmyRqa77xEDkHay94NSRszZUTP0FCPcpI3UsbyIOuSTOMJISOpoyalcdQCjk4oREljkFyqt/4UXdLmGhvYPAYenzgNglW4flfg83RA/8TSkUfAQPdZASyXS1tIQswYox7w3t8ubJtxVRQ4ARvJxSoQ5SYLCF1ADwIx1iW8Y+kVWVhvD74GsuB8iAXdmwnvDEuA/bXFsrzcbGaGcx/2H95WUAYSgRP0Hix9MbZzGQDHfDClffYaxyKdsnABa7gqy/kEMpMDPg0/3bATcH3dfVxQIMmcF/ucQ12BZw+07uKICbTLYoyGCrKdSoMx16IBFT5Uwbbx6A4dQWJeRBIo7AZ14zWzhAoZS+bM4lmIxtMy2ImBOuDoaDHMokP9bQLRvSn/aggxeAa08Mh9u0VZi5SEDwEJJSeWpaJwbBLbRvLI6TGSalgQXGCh+ggQvI+cADiCc86GpbSpyBT+xctaxjq55oYkXIwfDkboho6fjnPQxiI/ZcHSuKac13CMkxhGaUjebzvDMMY5pH0EWJQp/Fj5Mtb5GqBKwOr+puH3em0unf7x2LTtxda4QXU1h1ai2qaCn6H/0YEdRgl97U4AAAAASUVORK5CYII=",
    hastyguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWrqqdubm6SkZAvMCfd3dl3d3bDslLCvoO7tnCnp6a5ubDS0qVhWhuclmK+sSSYjCasnzLPxGCDeh+ysnb//wD//3/PzpbGxsZvbBy+vsH/AADCtC/GvmLMzJnMzMwAAADLy8vCsTDDrjHT08+9rDHQzK7///+8sE65rUrNxZSZmTPU0bbGunG+si/Swi69rC01fKJ1AAAAMHRSTlOiGWYT9U3//fsV0uomXlyVy/9eBAECV1pQ3QFcWwUFAPz+/v76/AH+/f0F/v7+/1yhXS6dAAACV0lEQVR42u3WWZOjIBAAYPDIeMQcm2tvMQjCqjP//99tg2IgHplJ1b5sTT9MWZbfNISmAeVPBvqE/x7iw6/T4c90HOL4dxxjPAHxUxk557kfn8/nn9lbF5vNxjz92LxlmXe5XGLI6UDM1d8QyTTd7/dFUbya6J9WjaQ0oAlCNtQqQ2kqo0iIUse10HGFx6IUVSMZUUEJ1p+bjCFKWJ3uK2BtC0qHhiA1qynVEPlDRp576BuhLBI6Udt9b2ApmkaC6hwhYW5BFMDbRIDqPm+L/qEQijHt+oS5DT31TlZtn6c1sK06Rm7hWRDnIcyZyFVhQ0hXwdxqh1GEnYy4g1cL6nSQjRE7Ai+fhmqIRR9lJSlxgybdWgxwDZB28BZlxUYQ+dwtOQVZsyqXIYWfJrYhrAd8whrxABJYfO5CtR4Poak2JyO8r+/gdQSRtfOsjPV+GVKoNn6/H1UF1HK1DJHlDMQpJewBhJ90FooFSBN/onX4yRR0Koc6CYeNjAKYY3SDUERQcnaBJ3iyWSnIXNiKF2usAcrnIGP3GW1I8AyEOULpXOegaTUjGELJsZdbBdxB6q7FByDCs5AqODNUOrSaEfQ9BH21msmoZojnzg4/Q4kYWrgDxzO0oPqH653qUcaWVdMXAFQbXzitYug9251qcOq4UN0xYnW/83O+eLDi3F9/2ZavmpZlFcnaVBt+x1EOdqeHKiLG2GgjTsPvx8GWxSqSQaDKNJw4q2cvD/7X7S7LoIRpgD5w6zgezbQ9FIQTI124rqxPOT/xp+85mPOnL0j48xL4H8O/8Ft3+9DgwekAAAAASUVORK5CYII=",
    heattreatedplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUZFx+GLyGbVCMxMjJ/f39rLyYvLy////8AAP9+RBcAAABWFgw3NjYXERCMKRdqGw50IxGnSRQSCwuoUxiUNRY0DAeiOBI0NTWTRhcvFQ9LNSspKSkyMjM3NzdLKiUuKSlLIhpqNyVxQyQqKikzNDN1MxFVVVUnJSUnJyaHSCIYGBguLS4yMzRDDwcuLi6aUhyPUVyNAAAAMHRSTlMP+/5VAvrNAQH/AP77//7//v7//v7+/8///vwGiAT7/fz7/XKy/wMvVf0qinr/tv4aE3jwAAADXElEQVR42p2Wi3abMAyGadeuGxhfsEMMCQSaQm5d+v5vt182ycjmQM50To4J6LNkWbIVxf8p0cS3auWlehAk/T40xyRYjZD9+nO9xm//oMU9tD+WEHaR5cf6dDptp8Bv56t+WZb1a9u2dV1e+OM9cDsQBDxBDCcxRr7WNX35iPsA2Edrgtonp82lECIhEUJC8NCw5S5gsY8/GWuNQ6D1a3ErNAVj63gVcPWD1ZyLfxlHSZ4kG/YZV0Gw8c45+QXxrkpJruMTRacPg1dMeu1BpPM+QXCCUR2DCInwhLh4IVu2DIK776wduZqMrLvBHoJgFX9j5QGgsHIAumG01uH6HUGtwuCzIYWBxIN32upOJFLplp3+7MYNyA7aJJ1WqgMqrXZTSKsUXml9KMfbeAVf4t2SlVDWKoeWtddR58Za25XI2H3AVbzaUsb9tAZiYcaNX5asFkWWbhjbhqujik6MbdKCZFEkpO4kc5L+xd1UR7RnDHOnaTaW1L2AweNEPTqT6b8yC57ZptiEOAKjCXBLYBEAEZtzfx/s4WvYU8TmPHVYHbHI7AZJfbAKt4t3wN6dOZurETcUTUZ/uucSKf4jDL7EyJ1y4/U7vy+pNYuMQKQ4TPZ3XF2Wz7ZxYPLcOTDRFjNkhVFfJeq4CmZOvGflV84pOhmVBoCFVEpmGEyub+t4BK7iNXvXORcgF53KeVIsEo6cTQocVTl8nQKhL5CkiVGGjifBc6UEnXG5OsxadMU7AlEefBaERXkDGqUlhkdAAhATB7rFcQfOBEflziRA7n0GIYFPbQeBpfYmCZQXsKMlUgJswwlAZ0d5ULmhi+riqgNppS7l4vsp13qTAIfwckMgDG4mjg5K8ndPWj2EFxkghVEW1XG/rKgcywORwmhvEg8m8Ss8TdXjDuQXIc5XCq9BUDkZXEaTXQecpWXKBCb9vuAeMLTC/Uy7cnLL5C4FrqBqcYuvpkFy1iI9hdKG1kig5BJNx24ajL5TJ4CdNEOyIg9wmTezIK6exjcowot0z/Pgcekv9IHwE6DFmQVX6Mjq5vYub6itOk9vxxu1SYhPTdIAqX0zdtNU3eke96O28U/7GD3UIW9HbSe1nMcHO+RLnD6vTe5b9VhPXo31Xv7qqR9o5u828nPgpPwGULSv07vZKugAAAAASUVORK5CYII=",
    helmet = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEViUQJtWwUqJAFYHQFmWgOFcAM5MQGscgBfUAP/AADysABHOAC/vwB/f38AAACPdwObgQF5ZQJtWgGCbAN/fwBVVQD//wBqWANXRwKKdQNpWANrWANHPARZSAJoVQZ4ZAUvJwJqWAN5ZQQXFwGiiAMwKwE3MwJMRAN6PQBoWASCbAWqqgAdGAFENwBIPAFYSgUHsW/NAAAAMHRSTlPbYBYMHaVSBKEBBJsEAgD9/v77/QIEAZJn0W/RMbAtjCyvsRH/Ei40BFPLAyZNbE/GVjg2AAAC+0lEQVR42p2X6WKqMBCFI4va9t4JCQFlUUTrvr3/291JWEzCUnvnR5GQjzMZspwS+M8gw4/cKBK/ByPvU14+Z0K8D0anmboeDjd1/SOid8BKIZ/4CYbvpxt1//GG4m6ZXhJKAxnfAaVJUjx/UkS1Q0m1qOmAnttc+sAruGloUXV8+2uT1ECswLqkYReqZQsP4j4QX3dmDdcFEU3cP6ILClhvaTjCBfTb1yQbUAhP43pBRD042eAVJjRko4oBDTTJ1xgLFBwHleTVBAV4F8o0xaFRRmCDRqYDqWJMmo/ZpLrH0qAiHVOU7YU9Ro8qMKRjmth88SzwHCCng3RAc22BKtM3wCA1QVdlqg1SjVPCrzdUrVsTxJpWYGiBprS8yw0w7QFfjNG0/EmxRfABfwXLf0zVRmpwb4DLFqxIvNP6yqh+4B/HBtVjLGvbzeBUy3LBWAkDIGMW+WrI4MjZcgCUyYY6yZrgLNvBg61tsMmU1qPtBIIADrfBqnNdzF6U8wXAhluTfKMqxtrvoJNt7neB/SYm6JigUtWiSrWA2GFPa3XM8YH+8XtAzlKY2mOEpQStiWq8ht+/OM87xYF7B9wuXvE85HvYE14+MnsHcDPO6/mGx1p+2HXOtQ/YEM7Knb2vYq6SC/1zs7VrUR9Kd8LmO3t7zHHwISmOAPGn6D/4XawNiWzF/Qq/xh0P/NOw07jCqrNZQewueFjG0Zi3if+W9malzv6MsU08CsI2oK4NRrDkbA4jmk7sXALqdBRjIJxPAWb9luj0KXcYSvo8wBTX3wLr6vWWFPbI0bTXrnwRHrLJBuKZbaYiOPsXOT2efWAMX3KJJNVbY9HYKfGBx2kSULlg1wPO6kHk4kr84nwz2jcoh9OZlmLIkh1Iuyz99Jgfj3n+LNKtxDAbshvxctOMqRVo7s2cE55l7YHc71fnGcnMHY6vpm/4VTV7po/HakUwVjKmuiUdVjzN6pnn3G51jTped9CTR85JVJ4G3bVwfmPmlZ93o9//FzAe/wAGLMO/N49yPQAAAABJRU5ErkJggg==",
    hikingboots = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVOMy5PJiMnIiAjHh5/cXFNNTBlQjv/f39xcQAdFRUiHBxlQzlsRz6qVVWqqlX///9AKij/AAAAAABoRD1uSEElHR4sIiJRNzI5OTkjHBxxSkIbFRUoIB4UFxQYEhIkGxsrJydaOzQlHR1SNTBYOjRVVVU7AAAjHBtePjdqNTUmGRd/AAAmFhYiGhk7JiNMLS2n9uU9AAAAMHRSTlNZISfnA/SnAgJvsE/MAwMBiwEA/v37/f4EsdJR+g8vbwi2y3ONAwSQ0QQwAhNPSRCXOL72AAACKklEQVR42u2Wx7riMAxGU+G2aa4ppJBCSALM+7/dyHYKhFRWs7jahC/2QbL0K5aGXjTtG1wP1tYLYF7uxSPW/4JdguASrADz8od86lp6ts9gR2EpelvjUf/Ujpjcm4f2C2Cga7udhPC9fYk1pywdx8lzva6fQeMZEuYF6DTvMcajRgxYS7MsS1NNu91uVVUNz3gko6QWZLgNpTt5isoeTMdAgs/4+T3RkNOD+rhHgvHw7OQBdHS8zkSoBsobUBR/4pAjHKmELBqP2m61P+KFKqtvyMg8TNY79Jpy5KL6G07YgSDH3UbwlwItlG0E9wo00G20gNPgz05yHhlinNlkEQwLju/TSghn1OTToNWC1GSM85aVGOOToX61WbXQB6NgihUY/J5JDqcRiBXAGBUSFPsZt+kCh1kLIuQngMD2hp4HGWU+fBcarfpuIlB6UEFTm0wHyg49+AeqGbnSrYjXDbOplGJYNwOrb2RoTVRFwi1LInhNpgNl0eN3VaDoWtAiBC1+ToAQKDMhnYO7QxT2gkR//ybPopPcgbFw5rZyRU2HqKwEJGDmmoubmvIHtauMsmDufvxgnSA6JWLFvc9erO+KorKytmoBFWgSz4I+a0t66B0LDkQzCwbXVg0ijU3UItAirpdmgIvfsf1/0HDd8AAs6LZtHakZZ+3U4btm7zjZNq5A5yiWXXuHy6Dc6heu1Iy+yeNJlu4auWG9ebI6Oa+PZKfvsfN/Bv8BIcLrj9FUJfUAAAAASUVORK5CYII=",
    honeycombbelt = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEXi0avIuqXUmBHn2cr8/PizewLXr1W7hQ5wWAR0cW6gWAD/+wNeMAOloZ/Zyqe8sKHz5ambbAOvrXOpnJW4rKXLjwrgwXkoGwSuXV2pnHX/AACfcAj/fwDEtJFwSgCxhB6uoX/loaHEt7ZfOwNvaG9/f/9VqgCGe2a/rHz/vwAAAADWx7T+/fzGiQS3qozTlAhnGLO5AAAAMHRSTlP2+ef8Avn9/B0UDQEbEJ/uBFwMYqGq9RQDWQGTAmRopv8EqUBHAgNIoAQA/f/7/vz2o9PhAAACMElEQVR42u2VaXPjIAyGBRjwfedO2m73xqH8/3+3EtjZOM1M0372m4TMIB50IGMwXxQs4AIu4EVRkkR3waIotsU2uQ9F0QjfgkUx7Rbd4cblOZnra7Cl1UnXdUmyuUN+M0X52vd91XfvPP7oXytGEt07MokKJoIGVpb/wa3ZwTDglyTE6YbE9HrBghUARG/aEYwMkMjA6NNiTps8z+OcBlzQiZEKo6kDmOEI3mFgcUsTSyu1tdJaezDF6G10OfymYgGlvvP+gIV4KM2DlVJq/9OHagSxArQMSsoFKNKSOMbe3sZMhmdkyCGOWlrmIyV7RXsDJKZAEJMAsuD8RDLnOOfKizur/Vx1sUMbbYPHDiYwWLRVVPszSShnFUCwUtACVlQdqmpt/lzIF0xXSR6gIOWkAvZCgfp4ePMzDWAcfVdiCoc4B1fcWWirkazG2inue893TmYcpUmNg0FJq84zDdppLB/zp6EcN3+nljuaFceTFL7WT3buEIUFfqLKYxprbhvz6/qx2pzKEk073GOWIWmt+bM5lTvf4c2sybPM/+1i07jbSBG0mof100N15TGpa+rttuHW3oQKOMXTum63uL1v3turI2nbLG6stus5px2PTfzhnYPB6vU1Jx3PTfbRZbXPTIyhqalA4JAzJn3olttwTm2GZ7pWVrrVo9fj3mxWbpK9z933eMzoNEetTLZ/+ELGCsZeaZxOZ/zYTZ7NIv/MK2CfBh3T5f24gAv4Sf0D3H3G/Tg5otYAAAAASUVORK5CYII=",
    honeydipper = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUpGwhvIA9hWyRgNBxtTxeulmmIdE9va2U7JwyPdU9uOx9dUxBRMxJ6aEilY1mrq2NcUgiAUByIdVP/AAD/f3+qVQCqqgD///8AfwC/Pz+XgVz/fwDBp3b//38AAABuUxJ3ThlbUgdsOR5vOyB/fwBVVQCHXShQSQZUSwZXTgf//wA7OwBUTAZJRARZUAhmNxwRLy/tAAAAMHRSTlMgAxiV6f6eDUbuzH5bVAQDjP5qAQIDAwECBLEC/QIA/f76+fYCBf5uiPgBBbFOt7G6L/isAAAByklEQVR42p2W2XaDMAxEzRoCJM3Wpus4AQKELPz/31UG2hc2y4In4J4ZybKRgGGIqZeXLiwmeDFWLKJoU5ZR9EDGACsUsouryDKGojiruKq77NseBTPcCZMKPJ/vsHXBCwLCTnQp9knGNUESbNIj8KRA3eJkJCi3ilLBUHxDKTuKQj7xqgdmEG7r9KRuqV3VGx7XpjKdYkxPNMHi3FSmVXS1W+6iumb7pykHlnE0x+JfkC6BPQfcdmWl0mS6Vq1WsSsNY1tRVVWjuo3RgrMfq9tTXt1cLeadtZErbKTMc0myQ7t4quU6cExwvMlLBVKidr9ppkAbj1aw6Lf3zH4UrgLLEb1xcA1/mbsF/3g84tOLBP9cXcBeegt8scEX7DzfzviKR/jeyuCn0zldsMHWKQyswv/e4YdttXG6Gjgv5sGV54tJp2NWfc+nRNng3lkuV9R1bFCkieuYKAZpkjqwuKAFJ0lSMT0eDL2tQII1Dtw5x1IpzjodBJXTYHrKGQLXCNM0nHM6lCM5Teo5p32wcZoEeOeCH6gJ7A8LcyDVNFSLYfHBuKkpe149wKHaCD64R+3S6vPBNeIwjA1Haw2jQx9VAAwVLVNQK34BD4FpV3QxXUEAAAAASUVORK5CYII=",
    honeymask = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVtXxdXVCOklCmmoCitmSa0kRjIoRsiJRtzZRgnKxCccxbbqiOMdhnFsS+Eeifx6jjkyjM8QSz//2oSHStGPhFBPBiacQj/AAAUHCRnYyn/fwAAVVWqqlX///8AAADItDC7qi7Ari4WIi0PHSz//wDWwTOomi0EBg4vNyx/fwFsZiUiLCwXGBE4NReShyqyewEwnITfAAAAMHRSTlMg/WURmufo7k8PGgVXl/8E8f4CqSL/qgFlugIDAwEA/f3+/v4B/v7//gL+//////g9HeURAAAC3klEQVR42p2Xh7aiMBCGAyGhiPX2u7uZ4KUsLOX9324nCSjSFP9zFAN8mZJJkYgnRZYf55sgeAbM1ddmPRgLETqhuqwDY0F4xJv3tRY/BGEH3jD+blx+GFQGecMZa6acXYyRsIY1DWPrXW1Q7MBWWcwp3ROPcX4AbwWY7801dN4db0VWqXpibx2bXMrgQYve9gCQJACHbfhoyWE8HleMEf7yxESQZMz59hUzsoMxOQTjPXEGGFp16D6/A1Jhw4Qcna8F8CQCmJQ9dJYMAqQcojGGt+hgVIagncgpgzIZmhy46jsglYFIqWc7AklvSTLwFKSMbnQxGS4mJwQZTZISE3sXHAn7ugdiiO27Vy87Z31/ETS50HDaEzYXs/pVF4WFOv5V+ncVttyXz0nwl/h0z+efvs4/54uwdXb93B+BhNCX84T6Hbkzrr70bBkZH42Ox6PlUUKG4CsJviyrKFSMu12NYl1WujTrKx2AlLFUTk8MaCtB4mqQQFd5F1Ae8K5cFLNR+cAiCfCmMw1E2qqMvNlxfJ0xqYtIgrfZUzoC4/g7FtAz0ZVpN5MjIP25TG5mlckcyMKqoe0EoLZ2eoqCPw8y9TakVZZlbymYTizVkBgkzNbqt5kcgFxZlJXyFiQ2qrq0cLrNg7jiaFDZqOVOzcwI3rLMBZmqKGfBD+FpEK24qY4xUq5WtR6OBVAYEF/GIpJmDWmTKmEZJCaVkBa9+oSiMKV3FwTplnqxMMORWFm1UyZv1scBmKiwUrcsrbor+dQqq6qSav+YBWPfSfTQsZ2blZWaZBb+KFS9AVverRzQBQeyRqYsS9fayURXanCKl0C1B+iMtEG2hSoTZ3HTwYdEj0TUlrrB8MNelzcds7FGHaqHUtGcit93zgAnYXPj5XUt5874+ECmDreho9cXXEsiyfh26z9y6hAiwFMVriNblG2HpDswPXJAIqd+688+f/xkFWyMKAnyp/4FzOs/5k9nDSBMF+AAAAAASUVORK5CYII=",
    hydroponicplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVwlJlnbW6dzdEgIB8sLCzN1thhk9KSrsg3SF1oaGguLS60wL1QcJ1FfMc1PEWUnp47ec7///8YTBg4WIY9QD49gNl5gH4AAP+qqqoAAACwu7w2Nja0xMWGsbQsLC2uvMOMqawoKCiPl5fN19g3NzdTV1ec09U0NDOjrKza4+VFSEgrKyuDiYo1NTQ5OTlMhM9QUgI2AAAAMHRSTlP//f8rXf////gClv/+//z+/wEF9f3//wEDAP/7/v/7/v8I/v+F/P+u///8a/7PBP/iXf10AAAEAUlEQVR42p2XC3eiPBCGg4Aoam339n1mIkQiC3KR///v9p0EVKBd251zPFrxyTuZW1Jx+EcT73+9Pj3a58Dr+p11noNX9+afg+A8WOB/SrEuirZI6NHasz8TnYJxy8xLVeVsHluOL4LBlY9An6jymibLSmmtLLWUuqLzM7CgXBlZ6mywUhojPwMmnrlcLsaY0Jq5hMY0yXOwJvKgwTAsxAqh1HlCwfoJeGop8XhzSineIn/ce8nz4Bz8lnKpXGS0BqikbmxY356AUOw5VrUfy6xi8kk6kmoQvJvar4j8v4Hg8pIDMrVfRMVh5K2YchIRNVKm0r7SgURk6w8UT/8fUDbSphFEj6QyZc9VRgkVtX8PrnjonJhorwbQUYNu1K1eyLo7V6wLBDQyoQNvtmF1Fb0uZVYl1Poz8Axf8kxFC4BKKrc/mw617KI0KqUqsdFbcAcQbjap3ES7bhGaNF1GjKTLJS/QvUZqo1kdNVSMQdToHoDCT0MD4LUDCQeByDSKUq1zbzMKrnCBoaQJw7Lk7Sh2btdBahN1y4gllcwEZ0ptSlSCGwYOrKkypvSqRvUpiKyrKu2zss8wBpKqTJU3SAo7oAoISg+Lqj556lZ2TOrM49HDmmjq1koK5gIiZbgHqFGjRDhSw1GiGnEX0XJLFB9OFnzjvg9Tz042odJpnWKAIIPx4dDStvu55TKwIAu+bJdiRS2UE28zbg6lMx4Brb/+r6bv3XL7MoAn5H61+9mtMFh8emjHm6ec9wAbC2jVLXcMfnOg/cKCTFI2JkPeQ83VbRUfwfMNfMMiSTPxNcNi8akHu/sereJuUCxoNgEUx7uGqzV5/LPxHl93FkTpZRczJVkTxd1i/5wY/+0wRJVcVH2UnmdCM01I2LBMi0WNHZW3kmupssVUxLTCyFFTsw9bG3DMu1uRX62DrtvwTC3Yfvdm/1BKcHX8UureV32tUo68N16OVr5Dv4cFFgrHBzrA7fARrCnZWp8QiUUvc9NbLI5Sew0Kn8MbjxuZ+LCx+5FHa5F70/wSR3TpIizRIj/iyczhKs09HKhyg9/pwSwqBM5XHD2odCpO68nMYRIPXkolxHFkWmiZ5ZV9HM/G4/pwqsk1pAap7xgEj3Yy0sNsHB8BuAm15KlUjDWFSEtEs639vxw6MVfqcQC14zimyfSwmp9WAnEFofWgp3Gy/hi7OQdPXI+hchhHFRwKA3V2nt6QJgdr4BIqQTjTLu0zwdlRXvP8xAzQjjum0k5G/9ldbm1JwijuGyPccvr8T91Xcf7kexRLqXHB8mh+b/jwoouDkipa2eGdfMC9f0MuHq6cRfCVq3VwttdcXHaDL93JH1O2/vYVxevtHn/94n8Bz+0P9Rw4A2/t2esAAAAASUVORK5CYII=",
    jar = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWKWlBdYVctKChVjFZkUzhLSU09lEA8O0SIRTluHRxRMCY7Q0w9bURXVlefgmJgOS5Ckz1paRY3MTNuPDA2OUGEODL/AAD///83Zj2lNzf/f39aQzSFOSyqVVWqqqpEPkBbVloAAACJdleTPDs8ljxNSlB1aFJqaWtQUlRJlUtuQ0paQzFsRzh/f3+QPUGMe2FXzyr2AAAAMHRSTlP+9h//7E//LvwHYEr/DP+c/wNI5ELKAQH/BAKTqQMDb5MA/v7//P78+//7+PwC//60SOKxAAACJ0lEQVR42t2WbXOjIBCAWYoe0FobTZpc23sBKyVRk///724xSauIxtxc++GeyWRIxscFhd0l6i8h/1hMqKO5RqTJz+7PddNcFZFGDnpNxAgcby3t8DedITYqefOBaJYYwZeLgamKGeIjBdIHCFU/ZjzVdMXrHnmxkurxopgWnHsheVHIQMyuKJxHtL7/QGvtVKEWE6JQsuD6oH3uSfGinibE72pVEB2AkFwqOi4+qVXQQ5NLvO2YKNY0HxE1f5kQ8Ujk5BBEk3T8qeK5zXZgwgCjZ3yRgoVyEuuAW7X2RGvLGaDYDESAO+hjd47TDnLD0ka++M3am+2Nh+G8swP3ZL8bEeNtH1N02e9Hxdc+D+xonAKiuhuucUr8iPk/iPEnicXMqW4D4vA9lp4YxzGKnLv3jpynellEdTtco70NijGuchu7YHH8+uC2HO5P9zmFJOPiEdzf7YY3u+OheKcMiSXA5q7DZgO2PF7eOc3D81jOYznIAOClAPsBnmjIaJYtl8tsmHOiKPlVgnlPV5gAzsnxoOF5uugwGMmrLE0amjiGYoNtCorBlGzY86Dq9IoOq427DvzArJZTIlVpVbdit97gFEzN6JSIdZdVTiLdhO68Op0scy5oVTFjCOl4xtRVRcWlUi7xKgadiIB/VFJdErEoVy2nzqEdMzqvCUzZ0XTfOWqShpqOcPeYSZmyNE+lpNc0uguv2bqiXxUJFQshRLL4up78E8U/KKl3yT+45usAAAAASUVORK5CYII=",
    lookerguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUgZyceViMVJCAKHw0ldS4mgjFCgkgLIhAAVQA6kERAc0QRDxF/f38AAAAQFhQnhjIKJREveTcmVy4taTYQNxcGCAg3hkILEw4qkjUoeS4A/wAUSBgAfwA4eUQLKQwKCwsMFBAaRCMODA8EFwQOOBEXWBwICgoVRBwcaCQjSikjYygmbCsOEBEEJwYSRBQdVSYQiLFvAAAAMHRSTlOkY/1v0+L/JwP9+rACAP39/Pj6/fkt/cv+0gFLAvwoa6/6jBcwcE/5kPuYspYUNf8giXS6AAAB4UlEQVR42u2W23KCMBCGA2itthASDhrOgngAte//do06SjaE4HS86Yx7wd032X//PYDsPwZ6g2/wFWC+DWbBJZ4GTxX/VJbrLC9RFMdjHjwFGow1TYOo7zqPWOZPgDFeYUwI8eiuQ5df5XYMrFp8jTD06Fp8ttwG+uIYnJpe0TSla4HkGQc6cINW+B484wMQe9xq7Nh34IX1QMJOr8h3MLrmKpK8TgBdWoEaPE/wGFpYlapz9rgXoQfK5PiNcZLB5GalBKYHAB7m5CyDn3bG+iAxRc6lczZTNLkiVw886Hq47muM7E3/SQiaKTsrx2oig+QHSvxAlQJMZCs5uBM5h340thKMmeyGD8xYhIZ6A1RSeUI5UxLzUqhWRw1FpgB0adhuBsAzkySKoO8RNLisEDQD1MYn2LC/B8CYgNECtVnj6YY3mBoEPZBSKBGjEy/9wELuxpmE6VrqN6TZ5DURRsOEElmsATMk2O9CiSx7mNEDI7vuNFLXNEWJreZ28NUzETrcFF3kI5VortUJDTTqRaIO7DYI9aV+y3T3MbGz6Q0kkoupYevBe9stAFhk4xe5xqsVX6qT3X2bFmVZBqOnPOJWTlmLDMPiB7bM87FrJTZsfMtLe9Bf+9cRJe8/q38G/gKZJbGrrZKkdwAAAABJRU5ErkJggg==",
    magnet = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVaWlyaIBacmp9jEgqXGwqTmp+kpKVram0yHh6OHBOlMCeNkZV2FA6kYF91dHb/ZWXnMzO0xtB9goeUWFSZmcytucP//wAAAH8aUF15eHx7e4t+foB8fIB7ipGSeoDBKhv/AP//fwD/qqrMzMwAAACwJBmMi42UlJf/////AAB/AACos7ususN/f3+tGw+rIheGiog8AAAAMHRSTlMboekiGZwIXRJp6mpa+p0DBf94rAXOAQImxyGp1SO6/wECBgUA/Pn9AQED+foD/dJSKdYrAAACFUlEQVR42q2W15qkIBCFERTDaNsTdnYnbJopAQP6/m+3gN2mwUB/W1eN+vepOkVCcGOg/waKT3SzoqDIFRQQBQEyP1xBWjf1tyB0V7y7x3VdNwFQtxrJr0ZJ1jXeTXYGluAXSYaxVnyavpByTzEu2lazCL7vOD0fVl2hom0zJT6t/Kdxmq6DpOjDg2oGBk3fpRWwUpn2QWYFwituGt2lddDruY7YenQ/s9oKpvOsokesJZsHkHawhK4H/ak3qkdtq5vUwB9YAwsLCJD+Vka3ySPkq65awTIxD9t0o489l1TWHqFV8FqjF9kc87b66H0Bq0FwUbi1HaQcvjmTi9MJgY1U00VWlX/9r6XgylwlZ98Mn4cnMVSby2o04tnXX8bddRLmm+Awd7wYJphO1N9cyKOHRed5A6Ymr7+zA4wraxrpwhjbhpxbyPTQTl4CSfTGMwY5eATkgLMsGSslljxtIIKQc84yT0ccmboPgU8QcMY4/tEP/56rY6cVEhHWYAAfkJ99cviYoypTxbFw78hdvhaXTN3ODrWhAWIafHM9rSjcKY7x/SP5izmnY5kuQAnICJ6Es2KIVY08cr51INPEF/frSp9p6A5qaxhDzmDEjDXuN6vwkqlwAyWcNPeO3BXZYcEpKCHUoFoY0g2kcFmJwi1VBBHWmT7sLowFqKzBnGPVREdz1K3ExM13cuEOSiolRTcrHox/BRmky18BqI4AAAAASUVORK5CYII=",
    megajug = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWVPTxda01ZmVYfOCGYlHUlLCFTVDi7sY2XXVczWjErSyvEtZB3d3QeZR4eMh4hNiFmahk7k0GKRjwnRCmlmHf///9wa1X//wCxo4A9bEVmmWZ+s4GbPkGFe2K0tGqOgWTUqn///7QAVVU+jD8A//9/AABISDB//3+q/6qJwIkAAAAhOyUyVDG0qIQtSis8ljxQ4mvWAAAAMHRSTlP+/f7z+B3++v7jnfoGBGShDP79YKQBVAGq9wn//2cDeQYDA/8BAn8CA/8A/f79/P+yjaZUAAACYElEQVR42p2WibajIAyG3YJFcald5+539kGk7/92E4Ra7EXF/np6LCffCYQQEvAHFbiH6xqggAdAI1gNwu+yqkpY7RFi2bZSxiU/rATbuO1V8mIdKGNNVpPLdILfFai0DoSffABjfvIGGedlpVeowBXBuWImOt5g1bsaVIEnaLvT8wUvsJT3IEbWA4TWodIDrFxg60qfYNmh22WwtMKpxBuDlRuMl8DTJMgWPMbSRcpFkMVGgyujp7ng1Ay6hBApZTwIc09KQsI9/K2LKfCNszxPuy5RisJeiVbXHZXFqOxZHiFL0lwpHYTf/b8uzHYw4fHAM0G0j86WGghDIYSkI9gKTiZwfVIIXBPppSZLSD+Kw0oZuMGrpC1hKZvyKGYlvUD7G+feBxnB4gvIzFSpMboKY5MmyQbfTSh2DvAPgt+i6DnSev6HP8raUijLW7YPYKHBsZpmExg1QUMkODwqUETRxdI2anpmY2hCXQlQ8B2ClzFIAltuEPhO0nuwGYMZf/IESfBy4xpi7cYYFNsReLGn+rKZABkHKrYWGW3RYzNsBe4usXbDDg6C9lb8iPBQKnOd8io5wOURRUWIQEjVQ6nAF82xJJhTIylM1Bw6n+OCcg9wdKxolpUlALjBE4I3Y32Mw6ivOcfZKwCPBw0Haywauuyo8nEsivm6Cqkqc7m2vtYcfOqFgnzgaa7rUzcWLNxWNXvPO5eWL1bYu8hXV7Nz3wN8JfN3v66j3qdJbmgMVb73bFdUm/m6P+s743w+miEPj+xNrxZMpnz+8u8e2cencf9R1ytba9br8WZ+Rv8BT0Gwe6TJh4YAAAAASUVORK5CYII=",
    mondobeltbag = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAACioqZEduZgX2BgYGE5atU6ODmxFA4eKWoxV6xiAwO8vMFwcHIXLmEAAP9vb3CZFRD////Dw8c7ac9NhP6dY2L/AAAcNnEmVK8xV65we/ZzhKIoSZU+eO47ac9rDAiMDQeSEws/P78Af39wfp1Tmv9q//+DhIoAAxcfP4hAPT5CPkBAbtquQTyAf4DJGhPn7mNFAAAAMHRSTlMA+/r8G/r/9A7qDP5VZwGYogH/pP/7AZoYYA35qRVgWRZUBALjDAJyS8j//2////9y5vM8AAABPElEQVR42u2U13KEIBSGQUSx97Wsuro1Pe//djlYNmKZ7CS55LsRRz74OXMQIYlEIvk1u0cnuu7kxey0HTxsVUAwTkXRj9ioIfPQNiYfqhZecFPd07G6DJPZpXCYy0bzoOt+2zboJiiWZYVWiMcNsqrOI0WhJbpOguifOsh4DRuxvH6LwInjmJZPaHJKyOmD+L6iWXgfUQqOAlDDQegoFtUEM1kXlRGuBbMqd+dMMCETJQxDXqw9HbR0UtE7PKmeEI1DvsEhxmd61wLmzsWmi7onry/aFJ5AAZFSI8+yrabwE/xBBDSeHCzap43qnC01M0CzunRZe5FXFHY1eHkWLMQBiMqVMnU2G9j2PLIUjefUGZ3r5jmhs21bXMAbPlXskdvD1G4JzztjuCMF+1Hi84M/3u1A/t4kEsl/8wWWlRCJpQBv3AAAAABJRU5ErkJggg==",
    pesticideplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVYYSynpSwtLi3g3SdS1mEbHhsyMTI0MzM2jjxGjEplZWU7ckM6dz1giDWCfS/CujX///8+sEtAe0MZGV2em0Y9O0AuRS49xU5APTJ/AH+qqqoAAAA6mEQ1NTQ8pUZLx1hEqE5HtlRN01tDl0w0Ry82WTU5OTk8h0NRVypydisqKiouLS6KiC40NTU3Zjno5iwCQrp4AAAAMHRSTlP+/mX//iOn1P/+Avz+///+Af/+BP5jC//+AgMA/vv//v7+//77/QX+/f4G9/+J/f8YcGAwAAADoUlEQVR42p2WiZajKhCGC8UtptPpnrmrICAQNW7v/3a3wNycRM0yU32STp/2y19VUD9A8ZsBj/5xnuP0a+D5x/Xj8fQ+6B6NgiGIB3writ37itEQJx330cXB24pR3HXGZlIqJTPLefImGHButaCUVhiUSoPkj5fgDjmjaSVKxtIUX4xKzoM3FE+JUfSvNE3rOVJBbcejf1+ARxTMRVV9oVzqFEtBq6zhQ3F6oRhx3oBy9Qkx11iJD+KSPT0HAw4h6BmSkgoM+tF3PF6tJiwFSdhmHlAfraYeJGSjP7AUJH2TeaEav0K6jCWZmm5F3oL/RMnfP/uw3ztQ7ElIQDlpzB44jx6Cp2LAzuDjo3A6AORwAEyWwidpDJb5CNwVCYfe6TjBrCctmaBGUkKj9TJZuOGizmZwIL1VosL8pgYmX6ZiqhLjQhJuMg26UehxtNicSvchaQ74Yq4/opTfz0DOa6WU76mGFgNG7bojGdP2IVjsopibWpZlibTSTOJgZUKpEjc8+1629X4dExyN8hJSfkk5f/SC/OmW43yU5SpSlq/2znqT1yuSsQyX8fx8HoObZK+gHrvlxlk5wJ/xKlnGas6H8+6F58S4JHecTMvMbZvdy1SV+LpvjUIP6F6kGiWdpX7N5xVx74pmPXTxKwdowA2hn2S53/uNVNX9T/5kOlx0/LNnF5Dm8JE6+Uq7eeTR7jE4dO3UXkCaQRj6sapkQwg83quz5bSgPVhJQ8KQGEy8UiYMzaKzdw4Qc445yTlT009hOLXODoTtCfYneTxWxnmVV8QCezJNPQBaXVXD5Nzj1pfhbhzRHOcaK2l7SEgI3QENC4vsjdY8iYotcODQYFmtVxxbgqPcECBkxP58W02VwSrPK/CIY9wSVxWC2JlPrLBvJ3wHPRu0tJjrGkTHyXG9CGncBhhbJAj+GYbhp/XuWtZ3RwhcM/0Dzyml93bEx7zgRNDXp5BgeRRtB00g2exqlHDcYcJ7lbLQAEaDP8bkUl1m61FXDZuNCiWzfLQWrM1zZ1roVgwFo+OW4rG4zrC7N2DIOZzJecH49pBc+qr/ch//j/8cK5tbHDpoOGwzcv5sk6OvWrnJ1S/mMXK+ugWaZ+fj5XaUrZPVI396IvtRxjIXFMvtKtE1iMnyMa9rR2vNdO0o7uZi9+pKluBzBsNaO1rjqTiI3rk9BnGS8GtsUlugz8hdcwcM/BVdbr5vKJ7uqzmdfuUyfz7/3mX+jfgPWcNDL/UDOZcAAAAASUVORK5CYII=",
    petalbelt = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVq8Wjf2u7kzY3axHv7+v2U4JyfnajW0uZycHhz9XObmKpg2V7SvXV4doiyrcUPGRJ4dJ+52slLqUtRrFCn9KfOyt+sqtnCvdcXahQA/wBktGeLipyhtLC4tMzBu9QAAP87fzt96oC6uc3/cv8AAH82SEg/vz9ZP3J/f///AP/Xv4DUqtTDv9cAAADa1vDi3PhOSSthAAAAMHRSTlP7+f7+A/kamxQFV6b/S54UGfthDgRkD6UeAZqU2FZgAUj//AMCDgQUAgH/Bu0A/f5eCup8AAACnklEQVR42u3W6XLbIBAAYFYCdMSW5Tt3mqR3C7z/23V3AQlkO3Xcmf7KZiaZWP7YZYVAwlwY4gP+K/wuKd4LdRRSn4KaB5Z9nXzGifT2Ue56/Gf3dAj1r7GWcWxJqrIAzsJW80B1CmUYuMJ41B7QB8Y8VIDhHDgAWz0cKbXe08AY1kKloyPmrMOw+DnS6rHnUYWvB69bHNRy4NhQ1cRaHgcv+OBLLim1Nh3YLBxUC0nODSpYaP00GP4wc2cnAVujcxNkPscjEGpuShZgoctgM4W+FQcZEeprmWbsqXM5hIJhiumWvJpNM8Lr1saWM2NXFgcZLSxXi7HUjblSkElyRVGWWbF8Q5UQ4so0EQoBNquVHMeA/EKw6MTKfGV4g78Fp/RNSVxZFjmkhCKunLX5FKCLSyuokiQERm4pGDYeNuZKeBmmOeTDH27RUOiziFMkKBmOkr4eMnLSgvtCjgtFuMmgUHGZ+hrLmZelf6wGN2ZsAhRqGWQxi/mOOJzjZgJjiyz8LIdKw620SzF8aVxyCzGGUgpz+jJnsyI8bks1fuOenkOGNd2PhFJjPWSnRB5zcmGtLpKLz7wQihk5nvIEquRBlov75ELo0Mw7jBze+W2O4ZNpX9TQnzCtIro8parzXU63t763tzDdC5KGorvLtw4ue71erRqzd3Aaqvtvk331ddhf93YKx1Jv7/qwVWdnx80Nb7HTjK4zKz+N1RunlabNdJKxw7V5zTtGI0/Cz3Jx0J25WSOVTbN+63yUB5OEL7S66r+dyFrWkBfbyfOO8h0eJJDu6O257wDSJCnB/tZGngvnUdLf4+7Ey8PcQ/wdT7XzoEbJ2V66E/lOZdzxmQpdy8f5OyC+SrQPLTLZX/Zm1V/wSnbwDvbxvvof4B/wt6n7fqr6BAAAAABJRU5ErkJggg==",
    petalplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWkpJ1iYlfk46cyMjGs161jY2MbGxqopXLu68ns4XZRTjf///8uLi643MPAuXfBu5MqKio/PUFVVQBwlHt5pYGBd0e/v8D/AAAAAADs6uvi25g1NjX08/IrKyvKysnX19TQyYzu6cwpKSnu567252/Y1ZPv5pM3Nzc6OjqY26k1NTU3NzfYzHTn2HInJyZYWFfdQlkrAAAAMHRSTlP9/P5u/wMs/f7//QGQ////zoAD///6/wEA///7/vz+/v7/Bv7///+HBP+yzv/+TvoYTgyxAAADwElEQVR42p2Xi3qjNhCFJXG1k2za7rY1IMQdYxvD+79dz0gYhBNsb8eXLwZ+nZE0F4Ud/qexrRulsZdBTz/udfOFrjMjdI9Bb/7LOeL1p+Mv97qHisORbHAuibELeG3OQ0X/kqTakoRzxhjnYOkXPhdnG/TN83zkCVMZmWK4xGiIRKPeV7AjLh2Zfj4UYVgURQXLWVWEuMRI/H0hLcUhSbnKlMqKMKzamKxtWyHwVVXCoMO8RGxZFcNlhaji3LKGBqgIhduX4V4R00vAZfCvjZv8kwUw/RX8AFyJqsoihmVy7sAhGZmKIhlFIFtytGkaIylEFRZVEUkZMZ4m/j3Iogy3YLQoLV60QKE2OFrQnUgqeHsPcqaxyLCL0dIWxXRDspvkDXQSnhE4fcxbPyqLYhmRJN/1yrIbl1qCWWSZlPavaISv5QzSFlo3s9Wz0uDmmuTpAnaHMzhbUK4V9duQ92DCllndgfidaUUipbRc9e48VWytiAtMhUZTZtwGzwmfJ5G5bA1GCF+yTHuM7ZhXtdSeUlJEWfih/lFqDSpmUFoyya19JDDh48jHoHJPGeWHvQWTIElqwfPhbQK7w6ATP0n3wnUVZcgNlBan3A8ZjatYfTv4Dgxp7BKomJh8Jc51meHE6cMIWrFKky3h76/T6UOxTyFMkEnM2T2ZwUTunn4iky/+Kq28skOwMjzTIIvieIrpEBwMoGh6wVB2ki+JjGhFoQraukYuCsyxQNFp20aDrojzqwg0561BT5eAdF/D4rhC+RAoNvghNNkA3FGwfVce/TMiVtRaEqIT2BLpimZX7/5Op534Wlf/2F9hO13fiKzraxy7pJhf612wBXqo47yHaRBe1tdr38SQdPMe422Cfx3eEez9VYMxzbbvoS7A5TuQfNtV/0zkLp4kay2OaCLBH3vafG+rW2kyNpK7um90mSQuMJvYbbY58ra5SeohiOuRFHOwbbRyaAZT46i106jjwd4q4Rvgv1R/hAGv2tO8oektTWMDLBF7+9xIxsbTBn6e/btO/tXVN+wmqxYQzWNPZb98dlxBBUoDG2yCW/F+DJaHow3C02DO+scHpPJigzlN8WJt/OYBCdFjzzHPP/fYwe4Z6FHbYkVjgdTAnysCRNuShWjmORZsHWvbitRG5oaK5phR1HQvKa4aQKReBLE2cjJTXhE4wwv7iMDBAYRNTbnI2PjS4uiep/vBaEwfAZ3n26EL5fFsDp2pOXkeh9eP1v50SMUx9egfvtH7HrxLhK77jcN8uZj3m/8FPLP/ABnCMKwSKgHHAAAAAElFTkSuQmCC",
    petalwand = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAADSzefkz49taWv6+v3OuXqkoK+2s8qnnHCXlKLYwnyemquopqzMuI1xbiSnomLNyeGkmG/AvNSnnG1mZlR4eZy1sclTIyG3tMvp8KjJtnh7dYd/f/+srNnQu4X//wA5OUlMLkxndVGbeGOIfVb//3/cxXvWxYfDwNZNi02/fz+CdVmqVaqq/6r/AAD/AP+3VgO9AAAAMHRSTlMA/fwUAfzy9PNZ+6MX9w4Qrpz7bFgYVxGiBpxfAha3ARcKgwxCA7daUpgE1QMDAQE67F6FAAACEUlEQVR42u2W15KjMBBFG0kgCQkw0fZ6bE9Om/7/77ZFWJJAuGprn+Y+GIvicDsoAPClf6Hr9VZiDw97+vJws9M+AUrxmiTxLVjNGKWE4GhzkEa5ersQVAiw1dMYXCLSKAwL+GF/jk3Gn/BGeoUk35rfE80HXEi+wdEaFpX0nrbq7l56zievVhDY75030EFJCbLnQj98Bfhlj21E1uo5BP3lfiyRPnIIPi/0A6uqrCBSRljWo91Q2h2xLg1oLSu1BdqAfisE2YwrgXpWERINwGmSlC1xCPotKURuqYr2lhRFCOKP5+FTswQrb0VRROrrbpaiDLwt2tEpqN+r6sCd4AEYs81yXUl1yFYtp3PuTp+7V2mtpZEK+CCErP1vWbR4ZxRHcYLTwIvzrI32bmGa1ziDMgjUqGK8ReUi2Uw/GaBG5cp4M6ZrW51uwEmT0JQ3eTrBaYcUJmCmAVsOlVpB0BTO72uWDBQ35Lir/H7DTnwyhhNLTmnJluM0hvpYIKhUocag6/D4CVJ8PNbre+jJgVFHoEkUiJwxWkK/3jg2n60bMppGItUsrhvzl1PuU+45EqLNpyMzT5VOQwiESOGpG8mGoy4ugdRw7anakQpcnJk1QhTIw4B0cwgIYxgPVxqoar7BTfQCOYIDPwC3GZiNOhGmohOdXWjMTGUeb//swm8hIb5vCW3ew7iI4T/rCl9q9AdTvRdQdk5YUAAAAABJRU5ErkJggg==",
    plasticplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUrKippXzLv4pMdHR1iYmLk1mZDPCackE7DrD0tLS0xLiGGeDXawjvEsFBwak6ShTg9PUBOThwkSCSCekkAAFU9QDt/f/8AAAD+4T395EY3NjWtm0Py2EeqmDstLCnjykf73TvbxETLt0f///83Nze6pjs0NDVMRyopKSk0NDI6Ojq3pkX65mz+9ZbQuDz++KiKX7NFAAAAMHRSTlNk/f4rA/78/v+N8/z///z98gUH+wP/AgD///r+///8/////gGz/8/8B4sE/v////8VumKkAAADoUlEQVR42p2X2ZqqMBCEWURxm+VskhACZAQUEN//7U51WAQEnG/qAhf86aS7k5TG6YcyZr6/tPrzfTDP86/ex69Oq3wJzFd0ta+Gcb3iYtj9m6vFiEDOKW+Vnh8y5iPaxvaDcyklX68zaK1hWYvz7Qxob2vI/O2rOAyFCGNVQP5+b+79/a5P9kAb4yNoY1k3h02oWMv1dgz+O10/pDQB3UmlCBuJRszziOxiGm26rpwwMJZlOccieCghuVXIIqfAaI0+mJ+uf+WbRRQgUP5I+CYAyQrOz4OIiAfOKhVBgV/4T6QfuABZJvnpqwVzPU7rXpbJU6geeiyZx8w++HVKpVneSlYtcYFzKyO26YMngIWDxB2COSgoNhaefGD+COSKJsCqpMtLm1O8LZSD0oJjBwHQ7iUnXSuMH5USceVS8pVSTi1Ux7rfblbJhAZ3qEfeAx1E9CKKqqvN2K0nxMIteqw4Uts9wF1mlZFHEXEFpS8lVPeap4U36KQMhRyC9T0PYb05ARQZT3V2NGjLJuILsTAWpkzb5FxQ/+z+LVAcqAN0dgxq8DN/s9hrLqK8ATyfPltQvt11OZaoCBkQcfFG4EWDn3XEKIrEBNvLqTi4gZ9xfm0i/gKYHVG7xYSKkNpKoVf5pcmqBjdFFYuuZKOYoqaCQol32azkJqvc9GmpV6HuGl305lVDid4JYnQOwHp3bZtcmippNgq3ivVeE1ZV5brNJpKoUDBRidGyslOZoaFi5SbBk5JExXogAhFH4MnmWaxHh0BYGfX+RGtEtYPXCVJP4IrAyIu8dmLNGmH9fE2BF75W9cLSJdG56Qr/AOPQHIE5l4ETsZc9Hmcj8DOVvhO9XBzhEafQADwZ/J3pQS6A4kBTTPt1JNBklBuxONLQlMMjgEAegGRLi7ESPucT4O6dsWhxhrFJIx2Cv3Cm7vaMzcdELfayC9g7WI2U70xBXcBmAm4w0G0+eSLLDG0QTc8wPuJY5faUByCSGmgKw0DVmrjVpOvAcYdyivHhTy4CizHrMvNsV7j02SHuDn5SawWY2vHUngEvqdyzCHkfiJ6DdG92H9eHtxpFNPQqEQOhn+hEURnV4jILSnO8SdbTDLAuUns1a8k47T6PpNAclRu8mxnX3ZbPmkCbfmDCgjXSdk77ODoY593jSpNSdrbv4SJTe9Hogmw9J2xk6ze3hvEda22Tx4XLvfZvDuzxJDj4RWOq4ba/ZeZbI5//4F/AS/0H4B4xQvsU4+EAAAAASUVORK5CYII=",
    porcelaindipper = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAABOVl6hpajX2t1pbW4nUaysHxtXYWmYjCpcZW1kXxE9Q0onXdYyNjxnGxH///8hJlRbbpb7AwPPHxopZ2h3h56iTVI6Pki9wcSZEg2ZEQyEeSVoXhp3bCF/f/8YMW4ZPYwjY7EcRqF1DAueniKhoVCYkEz//wAcPpEAAP84SmAcS7UiWMtxNjhXaaOwDAydCDCJAAAAMHRSTlMA+Pz+CvT1YPibFPz1/BUBD/IC9g75/v//Zp3kZpsCWqMEmkYEBOwBKwFkZ6j/EBZIkj8fAAAB9klEQVR42s2WW3fqIBBGB0IgJDEx5uqlalu19/b//7szA9E+OvDQdWYtfXK7v2GABOB/LBVJqb+TUXXGGGnD/gB/bARVb6ELa86KuUwYJ24VkFXVyBXCf0jZsYXWUYWQcgxQKlqXYiRZQ1KroGY3iL8fF+O1ySXPuLRiISCRUnjUWtkzsLp2A5QJFqKFXyBOl0o0MEnpyATdwpqGlRSFE9k8yt8BS4zpGUmFy2TuH5IVfVF7MzpJigp7xgboMGn/GxSXB6fxfQfatGuA6prUBaUe79sqTSRN4qqTkrPhVvCsWzQWvsnEj4Mh/FlVG922okDR5KMmSf/OGsWP1u3wJWbhhItq7zIYFNaw1nrQX/NAaIicE1VtWo0FQzsIMtIMTc06imvtanAy4bg9A8Nt83zj+nGxEPbtkbdNEd14sEnT1B+JRxZbEUm+1NXTxzLgarSzME3Lskw/4ZXJrToEvfB4PD6hFrhXzpy0/PTH85UdV0rzfXBJ303I5Y89kuhAJBi1fwsQ+n12QLKpmNTZCd29vQfTlB/8pxQKb/e94fZ4VnBxHf7ezuzFyS6X6vZMVuxncZ5l2S78XeGMwmybB3MvscIX2DlhuDLfZtlDzGtR7oSniDcpEuZR3LYKB3N4IOEpYk0hw/MfkxRgB3FcdJ3+2BdS/wD+yhdEIyxGGQAAAABJRU5ErkJggg==",
    porcelainportohive = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAACanpyWNjU7lTujnVlhZmmbWStakTKgljlnaGeWPEBsYjbIzdJ6gon///9iXTW6wshkYSBgZmS2vMR4e4JcCwtgZGGQmqUlJyoWLmlPjkI2OTonMVgSKFoRNHgXOIiXFA3BupYwMzQgWFg8lkFgCwdVVaqFFQ+Iei8AAP+eTSOEgimPhVC0tLT//wA/P79Oy7lMAAAAMHRSTlMA+/z+/Pn8/voL///+9gFQ/hdh/f4bpKtZa//HJY799KP/own/UQN2bAG7cKQDAQRsCEcVAAABqUlEQVR42u2W2XaDIBBAQSFqIsYFt9Y0mqXZ2///uyImUZQopq/eB485cJ0A44wATEy8wLLekL5vDrs6Y2WHX7PmD1X8OIaMOPZHLS6GQeC6rm3bAYTKFvDhncC2XTcIYrVdqb0n8VZhnc4WQEIpJaRh+uC3z/EshmcRIkgQEhhZfGggZjm32hmbr5FH7GXJ8VFF6Rc8IkJXPiKPaJ2AaZoImcjscn/Wi1zwTNMQWMxa8GmhIK3SNPORoTdg4kJrUopheNg3tBNI12CNkcHM3dP8YOK8honnnPliRGZ+VaIuiGLEmQbyzgrTUtztBkSt661KUR+KqB3yvSiu1mpiJ+Q2W0nEubg5My2XHGMl1qeoG5KIB8nxg6h1/p0EMM/7UJo6dW7JYKPSZPWAd7xclq3ZxfPuejwuWeK8fENw9VrcKYrHHeork86P40UQUygBe2y496WMcAWluEFUFrEBEtwlUShyDiCQtP+oNaKqsopcFx2FPmCBDJNORP/RR3q4AR9TTBsuIZFi44nae6PcdISNBcmoNpdsPks2m+SNxvruF8B/HzAxIeMPCnYem6r1aR4AAAAASUVORK5CYII=",
    portohive = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAAC2qWaSOzvPy8g8lDzCtG5Plk2cWlrMxrWrq4vIr55sbWypyaetrappZi2dkVdCkD2XPUD///+EfEpockU9kUCOhFGJQjmZmpRvVjeuczmvr2t1b0X//wCwcnCxsbFgGxBqZDq2wLb//3HpqlXNwHN4LCl/gn+zfYCqqgC//7++wsDMmZnBv7j//6rLwbkPUYAAAAAAMHRSTlMA/P7+/v79/P38+Q36mRmg/v8BYf3+Zv9l/wQDTQEJBBBEvAIE/vla/wME6AVsA2e73wviAAACWUlEQVR42s2WiZKjIBCGQYPRoOCROJnommNmdmf2fP+32+YQieCRqdqq/a0kHvn8G2hoEPpfdKGUneCgl0coxn4PF6+MruW+KLoSYtadFY4Vx0acX9cwJUItx0RqYMHYb1pSpTO4cYvo9YbBtSzLGccKuxiI4Ho20O6Y7BKpnZY6i+HI/vw6ZkLH/t8UUbi8ZbdbmsYhHFrhhHYA9OCPMLUEhhgnWu/be+23FojSJMrzyCiXivbPT4GjrzZIYwA3eX7YHEBwshHK989BUBT33DawwWOYgI3xg48ApaMBtXlhgWcJbhx5QxXgcQ04RFoIafD8WccBxPlKcCvBnzqvs9BjaDqnGIMZKi3w4IC5ciyCWXAYPk0dIhVqoQZE9kwAmWOB3xWYKxCcTQbtn2SWjRyTzMzdLI0OfSut1NtLcAhVZ6sAqZrzGeSqpcTkuphTiclvPddCDcInC2N7doQLshzDhzS08Vv6EEettSeL12kXJ6PludXLTCKn/4Tg0a4dL6ccrxJ3aklNFhD5nHCnXDD9hJDZN9Dxkv4CS/EKtchTuvhbb+k1JSpQp4ZAzcCLrSTYrT7LnGIdQ+/f3KBJNQJbPJQpcsfYMARbexynhsLuLscR1TMNszjO1pbUUcb5qmrLTWZNqZooyEuJjpB3F9C44CiNIDE9+ujz3D8vxE8FL/cZXsU4kcnhIJCqr/42TvaNfl2Luok2koU8ndwh8b4/3IgJnmhiP5acY99wwn22vHlE16qqQeq7rthlcfPZsRd/O8qGLTuKXfXp1DQdfHdd15zoCujf6y85FzCmG7ZTfgAAAABJRU5ErkJggg==",
    pulsar = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUNIgsRpQqqqgATawvc2gFWUwCkqAASGAkGVgIIqwMMowS4ugDR0wANHBkPHgwO2gMbYAsJAl8dcAsQogbQ0QDFxwAS0wBsbQNv2wOmpwgTBUReYAVV/wAAAAABAAABAAABAAAE2gIA/wD//wD7/AACAQHW1wACBAED5AIJ+wUQyAgA1gB/fwAAfQACAAAMOgBFDPgVAAAAMHRSTlPn+hf23htZHCsMZaObcLDfZhKapBNYBm/n7O2vAwAwTXH5AgL+jPb/9vr6swIFqAesybq9AAAB6ElEQVR42s2WfY+jIBDGQW21Wm237b7d3QygYq3dbb//t9uB9jaXnK7A5pLjD9GEX+Z5mHGAQeBg/yH44AsKKYTUTHtGlAIR6SkYe/AA8RZHCHpllTuI8o9JonYF7xzIqw37+T0L3ta9k8dfmQGtZAdQoOVA7nYAVxQwGnIMtM90G2/UPieLRjw6gHZRAzlXauBxedEUc0TrBIiSxYwdGY+ZSajULqAQmrCBs+OR9bw0VVdecB7UZtGKn/iRBudVBlj+0JDOghdpxO6G3kaMWUm77OaRQMSKnxSP1cCym3yXdBg7dRrzE41YP6WfqXUqAEy3fBj2FRWCcwHYCjDwdnsnRgKOg2jAw+F31ToXuSmzFNZtJOQkN/EjCyHSpH2Wtxbi0zqE/pm8VraMhF/PwdeO2YR6tscI1snz1b+vvsEiaR8DGnIEy66LaPIFG3hsiwUF9j8CirYIODvIYkEWG2+wgajrll8qnQKXbbIIAIHA9ddKJ0CyGALeLR5CQGMxCpA6b3ECLALBq7EYBYCLpJvJ4ihI6U+SOaUjYA3Z5uXlval9wRXslVIZzd4Rz0ptoA6QulH92R9cQUZK8zmlf4NPkCvVZ/aw8QLJYq/6gGsngad+fm/GwPx8zgPAb9yQV3UdBv7jy/wHJQdcgn5sBNEAAAAASUVORK5CYII=",
    rake = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEXT0tehoaRhXmIaGBlgXWCmp6hJSEmqqq7KyspSUFGysLM9Oz1CP0IqKCq/vsM+PEBAPDxAPD5BPz9fP19CP0J/f4yZmcy9vcD/AP/AvsTDw8cAAABXVFfJyM3////U09hNSk1LSEtPTE9/f39IRUdVVVU3NjepqatGQ0U6ODosLC04ODgsJik0NDNKR0m3trqeRr1XAAAAMHRSTlPsZCIc9B5Vjgah2peXROZ7N26QCNkUBZgB1LkA/PcB/M2w8QKWA1EGdWoyDhIxLq7T7Er5AAACCklEQVR42rWWaXMaMQyGvSeEkKRNekvW+tiDPfn//64ybaYUSLCYVh+WYcbPvLL02paCG0PFL+3WdBvIQbeAlCbHpEBRVfuUvBQkWFWVTmAtBD2kWlc/1kRCkFKltU6hE+5xDQkLrv4kGgkSFKrSGry0j0W2V1olIDUAQVLpai+2HEH3yIkWRGJwpR5PEo0BuTKc6Kb4qzQxYAMbbsWp4HXQ/64MCc+jp+A1XUAhBAn27LXVmeA18EvwmlafycvABpbgteTI3HEg+a+KW3GBex/sDonqRXrL+a5TbO6V9HpsCkg40e/+vKTvglzHkjt47pmrim2OG/YMUTwYmjYbDJGn3JNIMCycLf4KC17wdiw1vsbd5R1eAP0xJgHTps7R3QAS1O5I0ca/j8eJRoPfDl24d3LFEtG1D3LFHaLJZv44CTgGzkKKWIN5LWwE2AWuhjTnxbvc9AcyN1fBBkqH99DY3EwZ4lKi3aKp+2tgQx8cfspgi24Ay8p3OGT4EDPnjLaeoEXXh8+4oKUdwlu+Oa1q5lhrMtjzLkuu0FtH4wx8RpdxjQyMzszAv7FgSHQwOECZ1/yvjgZ3bTCBfWHDtjBgLxgC08zmLUyh8T0rx4J+ZLfaketah2MyScbO8WkG2DrO2Tj5vOoMN9AYOdh/hC5jA94wITeQmVYONuFuHaZ/NJPHv1bwXxR/Ah64SrO2xHP5AAAAAElFTkSuQmCC",
    redclayplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAACwSzTiVDM2NTXWVTaROibqY0RPNC6TRjVuOzApKSk1NTWtUDo0NDQ2NjY6OjrCTjJ4QTYrKispJyc3Li00NDL///8tLCxVVVUXGRccGxrlXkEjJCN/f3/TY0rqYD6yVkMwLi41MzPTX0YnHR0hHBwvLy8PBwcdHR0eIx4wMDCiPykAAAAAAAAAAAAAAAD7XXwzAAAAMHRSTlMA///7//7/+/79Bsv+tYUE//5xVPp0AYsDEi3/MAL///28Ov8ZNMIgTTNP/wAAAAATnIyXAAACs0lEQVR42q2WiXKjMAyGfcixCXc4crbJbrr3+7/fSpgbG7Kd/dMZzJQPyZIsxNh/VbqfKn0BSWv3P97SVapdVEmVDMK7TZQdkjiOQzlXGMfFCnUMW0RrHaDy3BiDV23h0MPewgYJTPR4PN/fd60AIEJcl8ReXE5KWQbm0QNWT+RACAFgGsM3F6ejhrre6TmADDJulVmWB0ieZ27GaA4xcbUMnyuDnbgDkocJdwkb7ooM94l84VJ+H6ePxVKb5044LA0C9Ae0jEfgnoUyuG5wFgwmmyTQCBCwxQmRS3mZgbAOInfHdy9BZQPuoYDShA8IU8pvsz0SiKnIpvvMMIUNRbnFn5FuUIhrU2Od6NZSgmoABC/nrmp6H2k3lxgLE5lM603zFmy1QJqdiAjrlZ1GpJRcbGsJ/pCYyG0OyNW5xQBeMEhRPU6qfBSdNZGn07NcoK+w7eryQJ4lxXWD4wYNFo4GAOvmOIHhedHhZGkAfJA94Fipx0XP+cCyiyDri60DYFS/uXSALMFmNdQ2aXFKKDbzPZ5YhYHl61J62nMsWGyCSmFr/TL3dE+Nzkt4wTf2FatOjR4d1kbZu4bzgP2rlepRNUgvg9OAHWmhlqQbYy8U1IPjG9eSvbHm2nKc/1GUxvjMnKS2jhkejbzs9hoF5Ojys/zWfAgW8VS8LwuqVMeEsK+x0E20ksfph2NQfaZy9XPGB6bUB/inwONq1WG/iZlnCpIekxhmYzAbFfPMOnSaHbs0ynrqB8mk4V3+KXftGldoMLxNeuq09ZR5ZAbQGkPMUL0lXoPsw7lLY2ccealXZjkp80fU7TNqgtKNZL/WhsBbP8nleY5TnNbdGFisjqsn9ls6FMY/t0fdA86dcY/gOjkUr8/Wt6Sq6K9F6hdma3bC0A3Rq2luTl+3eHp9iv9X/QXRISjDNoauuAAAAABJRU5ErkJggg==",
    redguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWEDwphExGcEA+bHBoYDQ4RDhJsAABqFhQ0EhIoCwldGRyqAADlHRUAAAAREhS4FxHEFxEYCgsrCAhICwtVFhOqJSSSIx3/AABRCAdsDQqrFA6tIRpsGReTJCOOHBgLBggLCgx6IyNlCgl3DgqXEg0KCgsPCw2MDQwQDA47BwNqFRJvIRw4ExCQEgswBQV3FxJPslKdAAAAMHRSTlN0XLDbpdYI7iJsowP/AP75/vz9/v3+/gEpUdH+/f76M2z+NmivSI+QsCVS/PuLFY9jpk3TAAAB8klEQVR42u3WW3OqMBAAYNRWe84pbriFcAtUQBCr/v9/d5KALSSBQjvTJ+OLw8w3u7ntxjC/OYwHfEB5+Oz3k4hplmVlugCegtXqJU2z5z0b9TEryzJNJ6FIkNwopbFr25a17426PjLs+74K+ScS3DZJErsOc/v9QFr202hEEhQQYRbNsnrh2r+W7exuTXMgVwWe8hCA0p1jDyJ14WwnxsBGmEvw5RICgog68uTaoLabbLhDKJAggVcE4L2NxHOxBwKGRIYhcwJqnBMnHiAB19vZkE8viaCFYJjzobNLRJ6IZ9rMhnxdPL4qiMOCyPDAINJDB3/Ci3IADjAOaSRgO0V/Poy7VJnbHEahPQmLkxbCCPQE5JnmpnaOAMlZOTg9iCAwlWsVCIhjFTq020Rx3vQwwu4UhMo0tyqEKXjPVJ3jBMQgVnyY6cyI7c0ozGURabcZaN2vt19Dl97XxlgIcQcLooP5OEygXZ1KWx4FhCmIci1cjUFbpCrvYi8iv6leokB2VFsIH/VNKh1VtS42Whi1sBptOtdT81epxneIIJ9sc2ltSTX8/Rzdz9tkf0yz4/HpeQCxet7GOnKZcWx9RIRBffuilbNGXvPdeD97fMHDYMmrI2Wh/6wao1rzMvWN5woxwst1MeRt3/+3fbzlfgP+B5h6uDuPJSe4AAAAAElFTkSuQmCC",
    redportohive = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWWXyhdGRAsDQZyYC2SHA2bizRjZh5nCgNKGRJOExAuCgqWPEBYVxdkZAlQjEI7lUGma0C5iEQ2Cgj/AAAmcBdodkT//wA5DgtVqlWqqgD///9LgiuqVQCqqlX//3+qAACq/1X/fwAAAACMCAyVPDt0Cw47ljtxExKMRC5QijKphzdFkziWZixUDAtxhy2qeDasPtTjAAAAMHRSTlP+7B/2/vygBWmeX/9kA/////6ZAQz/AekDAwHVAwMCAwMCAP7//f78//r8/v76/f1XCXyhAAACzUlEQVR42s2W63LaMBCFJRnbkoCSGpqUNElbQ5AvGL//23V3JRnbyBCaPzlAmCHz6aylvYjl/yn2tUAhUhD8/YTj+h5Qa50ppaTW4g5HnfGmad5JpuEqEx8CddZwR1nUvDdK53l6A8ys2a4TsVyJMxkEtY1xNxSiaUeGQPEU4gjlwu/vJSgw0BE4A+G3MWo6VALNkPQgkPpaqE13EONgjZFXQP3Ez2fYyT3kGHz+8/b2+rrdLi2HJOyiGcHwk5hyFJkLdPiYLgtgc9IzuMwXCWoBSiJOMqQ+SD9wOI9lB4p8cUJFoBMDHZ2YE26qW4pzfXbc5IvS6uQUo6pOLcgvwiJJngj+zJO6rOu67OkUWeMHUIvsd1SFb0bRevBwOODHqS6//Yj2hZN1wmXAuYqZxA3qgU4rBOsyivZnFfgpcCXWxkzlL/44+qC1RMeQijY+Sh/qcwgcOO7nc3jP5w97VsVJLwFugt6vIPDRgptc/LoNgp8FqyTfWnCZi/LDjkcElwPH1Wo1AIsiCMbxgtKVHDflGIRNLXBHLkgWwzP+9Y6L8mDBegTOA6fBepuDqUoZV6M6MHyMkDgvPlRbHCebpcQi6Mm+LSROJPw5YjlGVFI9PIooTceOACaDDgCjDIoYeCoowCGn2QWJiVMlodYheITlBLXQQjW1VBKM+SqBXCfwMdBzMmoas9kea6nFQqziuMcfp0DBfWMDemYLEYoQ6pciOFKqrkNdTihOTbHfw+0KaB/DS001ZEXtdNTBLY0t4CjDYJorjq0Ygw0MK86nR4DiXTvuGc/wBcNKTE8r1SH+23SS03eANTzj5ZhyfdzI6VGerulEdiFdBSFz5RQJg/z5yq0jteQlOgPD39euKylkgTEjFp+yF2h4IsO/paLp5PaVtobL2zcrTEbhWDfdlLzjEiiElnAHlPKuS+Doprm+776aCrznfuqi+wXAf3djgAp/jbliAAAAAElFTkSuQmCC",
    rileyguard = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWXFQ2rJRLOHxZuEgxWDgV4EAqsTxbEYyyMEQzMl0QvAgS9iDLHhzaRWB/TGRd5CwCiERGqVQCKbir/PwD//3////8AAACvFg7HGROUEg20mTL/AAC0pS6QDQh+AACuIwVQCQetFg2NEQ3FojhpCwisFQvDaSbFmTiZAACPCgewVxkwBASMEgexAAC5aSdaCwdshXUNAAAAMHRSTlOj+vdUI5j0+2b7Jv3+mlr4LAN9BAIBAPz9+/0B//sC/TFbzv9o0v//BdD5EpMD+07W02w7AAACUklEQVR42u2W63KbMBCFxc1gfEnbpBJC5lICIQSw3//tupKMEEYGJzP91ZwZe+wZPs7RarWA8BeFvsF/CPbvfd+/D3pmjH3ZkT0GBn90HY/HHyvkAHqEK4rkt23bKFwmVVRENEUgO3jEkeG8uAUj9FBVcXlrGUXIvV8jNNawm5NVwG+5vMYUh8UMBNN0dR8ZdqiBrFzM0uUGYKawsrrpcucwdxLWVnFzQ4km4HxPrnGd1V51BEJvSVLeAd22dd08v1w8QoyePK4JLJuiKChXIi6/AfkvHvcnL9O1xkitjUpdL7cnXAb/qg7jl9/z00GpIjlh2+MCff+Da8M7ENRqILiXlNCp6aDsbVvXcRzv9ptfh8MBdS2/Hg0Nhy8FNZMAvp5OpzjeAr31bXLRQMz4Qgcw0StKsreaY1Jbn1S5DsrcEhOmOigNhc4ZcUQfTRugpJrpGHUEdxtSGTtHLTQZSQkKcqsMZ+ORk4kA6bBQosCdb5HO3Ks9Dj1pmKjijuB+k1UuMw9kl/dCkui9oMDd2YqCu5Oc4dZ5ekqEaSJMh+LUvpVB87CFR4BnJVcBqLZj/6EqYwZT7FgQ07Is+EDa7PwqDKGi3Th/DCBrkQCG85WdeafWfAvzcfqYogbaWZSOwNUQNNBmD5o/3LqbsUHO0ORQGYL0mTUHc3IdAMORzPx9XO8hqKOPyVnUtC0pmcrawCnmlUlXnsil5zVNIzaDh5Z0VuWPPMrDMC/LEqGmkbegxHY+/dYRXhy4BWofBFNQv/DuseqY8luw+evL90vgfw7+Bc4JGEFgO1faAAAAAElFTkSuQmCC",
    scissors = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUOZHGxKkORk51pam0DZmgVKCxjEBcNWWSFh5CbJTqjJjyenp8KT1r///9hYmgQMV1xHCr5CwuVLDQA///3EXgQdIJvcHd6fIR0eoZ9g4qQITaqCFXCL0p1hY+dncr/dHQAqqp/f6iZZHIAAP9qAGoLPkYAf/8Aqv9Dcn16fYR+gIeoKkCTW2v/AP8AAACHiJF0ypxoAAAAMHRSTlPy9fURDBQUpo6k3QZjAVMSXQEbAQP/lpbpqmkD//AGAgQI9gECRQID+WxvlpYBAPf0jh69AAACWElEQVR42s3W15aiQBAAUDpLS1DMaR2d2bxb/P/fbVWBKxOQpp+mHwycc61A0XYCkSv58Gp1sHEQV748VNaOhHZ/E/ORUHifpul+NjqiEMfjUeCawSEczmEm/Cz1HqEFGw4tpBgJ360Xnct6EC5BCEMfjBD37nyDcrjGFliRQvU/nnkd8z18oRIxLJU6u5WoIUsy+P4QWthjJMulWri7JHGPI87b3iwBe/OXLz2xY1n2wzOWaC3VyBlTk8hl2qE0sOiDlnuDgc+WMyanmzRRJvom38ED9aYiQL3hu2HYYU8p4a/9EVOcGBzVvW97w07rttSsD75AlaZe8KhajuOwtIWmj5rc4tHzaKs9xvVY3QLcKimBXUmu7J+cw5leCVruiNPNzDQpPxy5uV1WvxlikHtVmPLT88DWccaI3t/uO42pcUOT0+w48Od6vbqkWZhs+cb1QrWTJ3kilZlk5bRbuaGng9cUJrKu6x8UDLNcUV8WAREVqNMJYU3lUX0r9+Zx7ItYyG2yreuCHweUmQnYOnKANeaJTrWPkX6/5XwAc1CS6sNFvxG8r16gqFtXmxH/HQodLjnZyVEQ24lA1r/4dqhgmDdug55gOSIiOwNfOGJoqjkYqg9v3rSZHB0GuT45MfQLDLdh/8iK79+mM6vrIKhys5OyQHKD+CUAqinsKE3ViajgeRDmCnbUFQWvYEiqazkl3oFrEwDVenPpjjTBIuScU3bSvMN8/AGJoAI1HuLI1bFwayLhJOoQeCE4hZjmbH6CioJFEQVzKFQUxH2/jDwhRx+tPx/8B44C4xe4td57AAAAAElFTkSuQmCC",
    scythe = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUAAAC2AQFok83HAgClmaVyAAD4AADetaD45Y7Y2AOkBACuBAGXAgP//wD///96dnn84XhybwhshrekqABVYKCYdmOmpAC0tgP0sHdMb5+gbWSfngKSpcrUmXgSFmKweGOTRmJpAAB7egJYc6Runs6kpKT/fwD/pKRgYmt1eaphjMqYMkmwhGS0gmajj4e7xAZh8l7aAAAAMHRSTlMA+Pn69hAC+Pv5D6dfAQEH+RbxDxVfn9T7bxJq/50Ilv5JTpsFAwIDUf+z/3iUZadThZVJAAAB2UlEQVR42s2VW3OCMBCFl9yAEJCbCrZarbbeWv3//667KepTKctDp+chE2b4PGeXZAX4T9pnf+uXwXI6Gef58gnjwGm0hLcRScMIQbYWCObNEvZMzmCFTRRNYcHj3mGxbHIC2TV+hMhFBUxYFL2dEzgFLvfS5ER+cGvsuBwyOxxKV4vPRqkwjEJFUYeieDyVKoUQfgWHn0Yjbc0vP1BncCBMPKMQDBJCzZC+bIXn6EmUgZQe3SS09h3QWnyLalRiLYPAs7gGPdyq45Si5oRheVwHJOlX3Ud2fiWBvjvHc4f1gZMa3zy17VbdOVRw0+bHhkJ7av2OckZRiN1BnW9gAr3N3dV1dkBHdaGnthTrB9hT5W7VTY0Lfphsh7vtHQzADLkdkE38zt05N+Tcve1vkyC5NdX+bviQBS2/Qek43MNQoqFmzR4CyZRnWEB1jcEleFSt4Rim8BTPaeMsa4CkUMXxK1gKqXngLJ5VKVLW8GaWD1rw/z+KOH6Cio/BPJ5hXK4qH5Sfs0oL6ihfvqMjOB+0SNkVvoMPyuY0FFfqKL+lLoF5xW+pwdvLvYD32yuZF8kX6NBQarBMzgeVCRh2UKAK2Rwm1QkF1SOODWzcKE4bGOdHowL+ob4Af3IXvD5jFoEAAAAASUVORK5CYII=",
    sparkstaff = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEUrIAZtXCBbKhArGBBeWAdjWg8pFhJiIjhGAEhlWwY0BTBIPAhALhBcJFL//wAAAH8+A0F/AH9JBkJwRUuqVQCCeyT/AP///38AAAA1ATUsAS4tJwFTAFMYGAAuADBORQAsAC8xATQyADUtJQM7OQBEPAJzZzMRABJQRgRXVQYPAA87NAV/AAB/fwAYBRAQAC5160O/AAAAMHRSTlMm6AujapRR62Qr2UWQ7AEC/wKp/wP/AQIACnUwAw9OUjCQrA4HNvpzKwctRwICSAm93QX+AAABUUlEQVR42t2Wx3LDMAxESYqU3J0ekFRvliyX//+7MMkxccHeEszoJL1ZErNaQBBY4q+DDQi2AlX0MNh9v8y44NzQC1EnOIqjGgPiPY3acI+6aScvFMmCAQpf6PB9s/I0L1oGmKmhkFq0y1Udsbs6TD5ePCxiLrgJj3V1larmyPdqS08zOpPKDkyv+mE2090QfJAx/47CrKWUcdaRYoBiWZjX57XsezO8cxQbpQOUSGnmvOYcSfe9TJJgPlZzMjFpMwmRWDpC0RGdgMz5kopaLKzGa5JX02UfofG424PgKSKLBfJlyVvgDgT3IJiSi8GhUzoLgZaqHBxzlyRvgZbqEhyspXsDJ3KNjvLcgeC5BsHHIGmhrcPWwULQuvKb5B3glsoKAkO5HDpqSnn145Z3KabnYPUUAC05h90xtVUJgZ+SCgEPJKIG2lcP5LN/tlrfUR9/ZiWhbSCqEAAAAABJRU5ErkJggg==",
    superscooper = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVZVVjb2gUAAGsqKSZqagKvrwVgXWBLSEmlpQEAAJ8NDaoJCc8uL6pLSEmmpg4AAKxNTovKzQCrqy0AANkAAM+oIRqOjk7NzQDS0gD///8FBclXPVeTGxQeHl9VDwCtXhk/PT9SEU9BPk5/KqpCDZJIRDSqVVXakQDGvgAAAAABANfY2AEAAOzn5wAAAP///wD+jrGIAAAAMHRSTlPl5xMcFw4LYWRfod7xoo0R6K/1aar9/AVrATIepEYJ3nhXuAb/cAMHegD7+/z7AgE1bipJAAAB8UlEQVR42r2W15LbMAxFwaLebbnFW9ITSCT1/38XqNgvK+8SmtngQW3mDMAL8IqAGwPWPgZ6I7g5Y6yHU/BB2hVwQFHOT6Fz4006X7DvRVPGml9q31vb06Vuk0RKmSYovUA1UmPkpjOm60yKlQeoUd/Bbo7ECwwwXjjRsUCN5czZ3Q2UXms8YWPfgD6qUhsX8GgWEH3BfguoUd1AuIPOAwxQL6LaegEzL/CE8TQ2vbiBJvPMGDdCEGYFLJWmK91Yn1UdnM9/m9fDT0MxTpz03B1zPB2+7ZMkzWhwPHfHoINg+HN5OryMb1XFsg73gzK+OLfBc8LXg5rkdAzQ4Zd9nndtxXU5h/tJz9V98QHYQd1l5pkJXrCkLbKDmp444ICqEWRYVtyb6gtqAnfHnguSB6d5nhkoaXQ5IHXDTL7YouOCWQ7kqRkTHDDYCXuEOnnYjUdrjMX0G4iZaxxBUlXYkg3KFMCkpebOquwmVVvJAx1WbUZt7IzkinPSsT1m6Z75Y6VujJ4smvPjiXsEToYsLBOkUoOzqPMyZoNkrXGabDgghcPz9+KX5oO/MQIAtSEjFgDFlrNcBNcCwg0ZKZ2CiAteEGCqlp3x6/RVvasOrAgTQRFelcJ35XkLXkdFl2CWqpSK5lD/62gdhpQ0pPiMw/w/Na3UFHoC7iAAAAAASUVORK5CYII=",
    tackyplanter = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEWWppkzMzOqw4zgzhAZY97X4uLqnRwsLCzMpFmsqW1aYVgtLCy6zM5tmqo1NDTQzV/wNwRubm7M0Z1slGzeViNPh8ZYUjWLZ5lib6AxOlJId8iotTXUd0S0xXU7QTc2YbCTb2Ovt85EOC23wDkeZWU+SERBPTzEt5v///88PEs+PkA/gdpAPjyaez3BsswAAABDP4+BAAAAMHRSTlP+9f////7/D/7++13//pz//wP//v7/+//+/P///v/9/v//+f8J+YD/ARF+/37//wDHINMiAAADoElEQVR42p2XiXbiMAxFhbN4iU02IOyUdrrM2v//u5Fkh4SQQGd0Ttvg+PpJsmxU+PxPg4nxUvbsi6CU5e3QQ7CFZPYjm6O9vf2aZzzwUFFm2Xw2n12ZZ++BWUsYMiAzxrPyDph5BmcnPbPgmJVTYOapDrAkaPkZzJBswfKTnDReYWiM4ut+hi6K86AGY0YkasqPWzDzcgB3wc9yCMq7HINrzGzP1wCWsyNgNuwYxempwGwQLG9Bw+CQtSHDeRQ9TSjO1lChJSNmax1FkZ4CG0jxdV4lrUryBz3M8yh3dU1vXsddnUFCYFRZqA80PYF1c0YXo5daCAINlp0c2Q5HgUS0PrzQAzTQNPSwc5ZeHXA/ss7XDjQefKmtf3hqsIbYCWEtjuzMVZA3YCQSyw+aYmUfEnum7JjZ8zhoq8gH6UFMcNDGwiBwNeXqOWnBKih6MAUPmqvz0YJYc2CvwB0Ga0O0TVAcBx3sgouaQ6udFTzy3jSQ53QiR86jnM9egZVUAk8Mito5Bu15u3WCzvK8uwChd/4NkGca1w8+11RrOcRkW6E5O+UQpIMVx+gSbnyVc/FVohaHg3Bx/BPJtUqfe1H2FWGJpMAzIYRKyZTGT4JGgUmWvE2OEfh6KRATQCD9aEGDsf+9hmMn2QNxEi7uRBDU4bej1fhPvDS34HcEQdG66KwmPeFJhYRTiz17e6JbYKh4BFUolvQcGT6pLa6limKv9CmONxfJruRWsCgWLOld1JQanSryFMGFSvVyFDQKwXd0bE0c4OQFZQnIBw+mwo2C+6IoFOVHczL3OBcThStphWvuCdRd2V0rIogKJ8yPoE9I4kJbDBTDp7jrbiO75PgYDypsJnpXFJrWccSoFhxuxzcsHIUKmMc1RcXggrfP8a5QgoWZKADNO+g30zvO9SZCHU2BRnGpKV8rYk+Crd++dGEEpI1MteYdJEncAkqNY7dD0au6943eA5/bshbeWdzLUIKB1KZ3IPvncRVKjTcvpuneaQiaq34L0X2V44H8jWEAT+SaFbBtBXGYLoDe/XgBS5LUfnURwoRWEDluH7qbo3O19LeOJ4Oz4XiSFwO9frsiqX8gTWDW8RXVesqNTjbadWDxSOp0auFDau82OpX1LTdoyYg0NVzCpFPdtWTlnV5O0pyjqTUa1uzJrEJvlz3sV7OuZ9xsppvHsUYX207qO+eByXzOH4KyvwBDH6X8amstJz58pZn3jPz3/wIe2l9YehszJ6kM4AAAAABJRU5ErkJggg==",
    tidepopper = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVaoKZh1eui7e0qWmJRZWVSnaxUuM3b19alpaWa5OjY7u8SKSxUs8l50u2T0dGR290tZnY8h5hty9nb2dk/v79OsMLc3t48eaJHp75hsOwzzP9VqlV2wci0tLSExrwAAAD///9k1u0Af39Qu9Cs/v6V9Plt6Pz6/f1YwtcA//9///9mydlq6v5Gmq1/f39MpruchNkrAAAAMHRSTlMd7BgeDGeclRfn4hDgC1eYQl6iJgRzXxz+BQUDdEsbAAH3Avr9/c/7+gED+/6FAm3CtxOoAAABh0lEQVR42tXWV2+DMBAAYNsMswLZo+vOLENCwv//dzWkfYpI43uI0hNIYOnDdx7IDIjBXgk6LhU6JJjDjgYZ9Oy5cA3+k+EbLGlwBrX3dNhT4YYEBdQ+CR6BU2HNqVCRYUwaHKw7B0kbue4oqcYiVd2HcKG1gheIs7KqytAB17JHdJdVdW9/sMn2mPPFZKLTcH3xVOcHR2t4wI3quJkU++noB2hZYwtCpMuOKy8VVvAIrIrMdFRllAFapeqmWWhgmDJLaCJpins7cgLORN8URdN4FtC9VunzwtBIHh9MFWUUQGAeBtgUoXysRoSV1nJIdVOM0WRfpjGQn2bd3+8xkNHWtJalOg2hypCBK/VPGtMQrzWySOtyjDATyAxcIf5R43jFUuuQhyd1cob3YLu6KfVmVPEy3Futk/0+SeYgLr8ffGzlrDyuGsXjMXNEtFg5i4Qni9h6P+IBPOUR/gCwaz11bnN7+A4LfgYCzMFRRDj/N7B1zHQQoFlkvkM7r+bkozW2L3WY/wYQI3D1zIetEQAAAABJRU5ErkJggg==",
    vacuum = "iVBORw0KGgoAAAANSUhEUgAAADgAAAA4CAMAAACfWMssAAAAkFBMVEVrZ2NcUDofIyaRk54hIydnZ2odKC1SRTldVVFEOi+WmVMUHydlIR5hYBpRRDpRU1ubpi3Q1UV8fYQ0PERJPDH///85O0Q7PUcAAP8Uamw8Qkmqqqo9QEmhoV25xCz//380Qys/RU97hip/goiqVVWAfYWMjpn//wDCyDEAAABkVUYXIy1TUleJi5NVTUlUV2HSl79BAAAAMHRSTlP1+Bb8WBHrnaJh/5kWDF9d///u/5ABYIsBE/8DXgT/Av+x//8D/74B/wD9/P3++/6xQms4AAACKklEQVR42p3WiXKjMAwGYMsYcxdyN7132z1wjHj/t1sZOzRDsrFB05mm0/nyG1kGWLuw2P1/x4/L4DPRZYl8wLMhT6PfcbubD+OIql6QWEcdVTwXPlJi1627egk0ck4ir6oqpoq6aB3vXp9f39s/M68xSmftY5Y8JGmSMIIstZWFwAqUKewMVLa2IZAjKa00wY7RlyD9EQZdSkddPSdm86BNtHAXCoGZRMtQPUzOyb1EFo1QqSoMaspQZjd+KVCgNYOyrcKXSonUG40ACsu2DF7q0Bu3UuAzunoJk0BIVwgW0hzQj0qCZlWY5jgIiOYaAyG72v8wmA27qMx9Qzk43f87ECfwKxSCheoMywC4tRNH7vM7kXth2SYjXDuIgVCDNofDQHc6yoDmVJQIgANktIsa0EycH8YEEbSDwwAoCLnLxS2M12gSlb4xODe7ykWWZcl2gP8bnCtIvdsjsh+HvUgNFHR3pfC0fb8PY3omaqq+7zUzo3qoXwQV9yYeWa9tYc8Y600h3c1fPHCvz85QtL/JstQDDz2OzoSNn+vpE30ChUaW5znT32G2as8ACCnZarXKL1c6dEr44ElC07zBZvNkXG7TUaPwDDk/kYQG5IlKbnKX3m8CoBEnV/DW/G2eKFyGwbHgZ9PA8FXcsx0TSOLDrto3OZyLQp6uq2iP/tNBWMgrGPQIcNEXUARDt62FlLd743tfHY51URTzX3T5cdkbssUL4eLE2/UPbtnJbqND0+4AAAAASUVORK5CYII=",
}

local B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LOOKUP = {}
for i = 1, #B64_ALPHABET do B64_LOOKUP[B64_ALPHABET:byte(i)] = i - 1 end

local function decodeBase64(text)
    if crypt and crypt.base64decode then
        local ok, res = pcall(crypt.base64decode, text)
        if ok and res then return res end
    end
    if base64_decode then
        local ok, res = pcall(base64_decode, text)
        if ok and res then return res end
    end
    local out, buffer, bits = {}, 0, 0
    for i = 1, #text do
        local v = B64_LOOKUP[text:byte(i)]
        if v then
            buffer = buffer * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                local divisor = 2 ^ bits
                out[#out + 1] = string.char(math.floor(buffer / divisor) % 256)
                buffer = buffer % divisor
            end
        end
    end
    return table.concat(out)
end

local ICON_DIR = "AutoFeedBSS/icons"
local routeIconCache = {}

-- tra ve asset cua icon gear (nil neu khong co anh hoac executor khong ho tro)
local function getRouteIcon(key)
    local cached = routeIconCache[key]
    if cached ~= nil then return cached or nil end
    local asset = false
    local b64 = ROUTE_ICON_B64[key]
    if b64 and getcustomasset and isfile and writefile then
        pcall(function()
            if makefolder and isfolder then
                if not isfolder("AutoFeedBSS") then makefolder("AutoFeedBSS") end
                if not isfolder(ICON_DIR) then makefolder(ICON_DIR) end
            end
        end)
        local path = ICON_DIR .. "/" .. key .. ".png"
        if not isfile(path) then
            pcall(writefile, path, decodeBase64(b64))
        end
        local ok, res = pcall(getcustomasset, path)
        if ok and res then asset = res end
    end
    routeIconCache[key] = asset
    return asset or nil
end

local Progression = (function()
    local autoProgressionEnabled = true
    local autoFieldSwitchEnabled = true
    local autoHuntViciousEnabled = true
    local showProgressionHud = false
    local progTargetLabel = nil
    local routeMapGui = nil
    local routeMapFrame = nil
    local routeList = nil
    local routePills = {}

-- bo nil ra khoi list (ipairs dung lai o nil dau tien)
local function dropNils(t, n)
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

local DEFAULT_ROUTE = {
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
    { Bees = 0, Name = "Plastic Planter", Type = "Planter" },
    { Bees = 20, Name = "Beekeeper's Mask", Type = "Hat" },
    { Bees = 20, Name = "Beekeeper's Boots", Type = "Boots" },
    { Bees = 25, Name = "Mondo Belt Bag", Type = "Belt", Ingredients = { { Item = "Sunflower Seed", Amount = 50 }, { Item = "Pineapple", Amount = 50 } } },
    { Bees = 20, Name = "Blue Port-O-Hive", Type = "Bag", Ingredients = { { Item = "Blueberry", Amount = 100 } } },
    { Bees = 20, Name = "Silver Soakers", Type = "Sprinkler" },
    { Bees = 20, Name = "Elite Blue Guard", Type = "Guard", Ingredients = { { Item = "Blueberry", Amount = 50 } } },
    { Bees = 20, Name = "Elite Red Guard", Type = "Guard", Ingredients = { { Item = "Strawberry", Amount = 50 } } },
    { Bees = 25, Name = "Bucko Guard", Type = "Guard", Ingredients = { { Item = "Blueberry", Amount = 100 }, { Item = "Blue Extract", Amount = 5 }, { Item = "Stinger", Amount = 15 } } },
    { Bees = 25, Name = "Riley Guard", Type = "Guard", Ingredients = { { Item = "Strawberry", Amount = 100 }, { Item = "Red Extract", Amount = 5 }, { Item = "Stinger", Amount = 15 } } },
    { Bees = 0, Name = "Candy Planter", Type = "Planter", Ingredients = { { Item = "Gumdrop", Amount = 100 } } },
    { Bees = 25, Name = "Glider", Type = "Glider" },
    { Bees = 25, Name = "Golden Rake", Type = "Tool" },
    { Bees = 25, Name = "Porcelain Dipper", Type = "Tool" },
    { Bees = 25, Name = "Porcelain Port-O-Hive", Type = "Bag" },
    { Bees = 0, Name = "Blue Clay Planter", Type = "Planter", Ingredients = { { Item = "Blueberry", Amount = 50 }, { Item = "Soft Wax", Amount = 10 } } },
    { Bees = 0, Name = "Red Clay Planter", Type = "Planter", Ingredients = { { Item = "Strawberry", Amount = 50 }, { Item = "Soft Wax", Amount = 10 } } },
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
    { Bees = 50, Name = "Tide Popper", Type = "Tool", Ingredients = { { Item = "Blue Extract", Amount = 1500 }, { Item = "Stinger", Amount = 150 }, { Item = "Tropical Drink", Amount = 150 }, { Item = "Swirled Wax", Amount = 75 }, { Item = "Super Smoothie", Amount = 50 } } },
    { Bees = 50, Name = "Dark Scythe", Type = "Tool", Ingredients = { { Item = "Red Extract", Amount = 1500 }, { Item = "Super Smoothie", Amount = 50 }, { Item = "Caustic Wax", Amount = 50 }, { Item = "Hard Wax", Amount = 100 }, { Item = "Stinger", Amount = 200 } } },
    { Bees = 50, Name = "Gummyballer", Type = "Tool", Ingredients = { { Item = "Glue", Amount = 1500 }, { Item = "Gumdrop", Amount = 1500 }, { Item = "Super Smoothie", Amount = 50 }, { Item = "Caustic Wax", Amount = 50 }, { Item = "Swirled Wax", Amount = 50 } } },
    { Bees = 50, Name = "Hydroponic Planter", Type = "Planter", Ingredients = { { Item = "Blue Extract", Amount = 100 }, { Item = "Soft Wax", Amount = 50 }, { Item = "Hard Wax", Amount = 15 }, { Item = "Caustic Wax", Amount = 5 } } },
    { Bees = 50, Name = "Heat-Treated Planter", Type = "Planter", Ingredients = { { Item = "Red Extract", Amount = 100 }, { Item = "Soft Wax", Amount = 50 }, { Item = "Hard Wax", Amount = 15 }, { Item = "Caustic Wax", Amount = 5 } } },
    { Bees = 50, Name = "Petal Planter", Type = "Planter", Ingredients = { { Item = "Spirit Petal", Amount = 1 }, { Item = "Enzymes", Amount = 100 }, { Item = "Soft Wax", Amount = 100 }, { Item = "Hard Wax", Amount = 30 }, { Item = "Caustic Wax", Amount = 10 }, { Item = "Swirled Wax", Amount = 5 } } },
    { Bees = 35, Name = "Gummy Boots", Type = "Boots", Ingredients = { { Item = "Glue", Amount = 500 }, { Item = "Glitter", Amount = 300 }, { Item = "Red Extract", Amount = 250 }, { Item = "Blue Extract", Amount = 250 } } },
    { Bees = 50, Name = "Coconut Belt", Type = "Belt", Ingredients = { { Item = "Coconut", Amount = 500 }, { Item = "Tropical Drink", Amount = 250 }, { Item = "Glue", Amount = 150 }, { Item = "Enzymes", Amount = 150 }, { Item = "Super Smoothie", Amount = 25 } } },
    { Bees = 50, Name = "Plenty Planter", Type = "Planter" },
    { Bees = 35, Name = "Petal Belt", Type = "Belt", Ingredients = { { Item = "Spirit Petal", Amount = 1 }, { Item = "Star Jelly", Amount = 25 }, { Item = "Glitter", Amount = 50 }, { Item = "Glue", Amount = 25 }, { Item = "Enzymes", Amount = 75 } } },
    { Bees = 35, Name = "Petal Wand", Type = "Tool", Ingredients = { { Item = "Spirit Petal", Amount = 1 }, { Item = "Star Jelly", Amount = 10 }, { Item = "Glitter", Amount = 25 }, { Item = "Enzymes", Amount = 75 } } }
}

local serverStats = nil
local serverStatsTime = 0

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
        if not serverStats or (tick() - serverStatsTime > 25) then
            local events = RS:FindFirstChild("Events")
            if events and events:FindFirstChild("RetrievePlayerStats") then
                local ok, res = pcall(function() return events.RetrievePlayerStats:InvokeServer() end)
                if ok and type(res) == "table" then
                    serverStats = res
                    serverStatsTime = tick()
                end
            end
        end
        if serverStats then
            if not data then
                data = serverStats
            else
                for k, v in pairs(serverStats) do
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

local function readAmount(val)
    if type(val) == "number" then return val end
    if type(val) == "string" then return tonumber(val) end
    if typeof and typeof(val) == "Instance" then
        if val:IsA("ValueBase") then return tonumber(val.Value) end
        local v = val:FindFirstChild("Value")
        if v and v:IsA("ValueBase") then return tonumber(v.Value) end
    end
    if type(val) == "table" then
        return tonumber(val.Amount or val.amount or val.Value or val.value or val.Count or val.count or val.Quantity or val.quantity or val[1])
    end
    return nil
end

local function collectItemTables(rootData)
    if type(rootData) ~= "table" then return {} end
    local list = {}
    local seen = {}
    local function addFolder(t, depth)
        if type(t) ~= "table" or (depth or 0) > 3 or seen[t] then return end
        seen[t] = true
        table.insert(list, t)
        for k, v in pairs(t) do
            local lk = tostring(k):lower()
            if type(v) == "table" and not seen[v] and (depth or 0) < 2 then
                if lk == "items" or lk == "eggs" or lk == "inventory" or lk == "supplies"
                    or lk == "collectibles" or lk == "totals" or lk == "boosts" or lk == "buffs"
                    or lk == "materials" or lk == "other" or lk == "resources" or lk == "crafting" then
                    addFolder(v, (depth or 0) + 1)
                end
            end
        end
    end
    addFolder(rootData.Eggs, 1)
    addFolder(rootData.Inventory, 1)
    addFolder(rootData.Items, 1)
    addFolder(rootData.Supplies, 1)
    addFolder(rootData.Materials, 1)
    addFolder(rootData.Collectibles, 1)
    addFolder(rootData.Totals, 1)
    addFolder(rootData, 1)
    return list
end

local function nameVariants(item, cleanKey)
    local cItem = item:gsub("[%s%-_']", ""):lower()
    local variants = { [cItem] = true }
    if cleanKey then variants[cleanKey:lower()] = true end
    if cItem:sub(-1) == "s" then
        variants[cItem:sub(1, -2)] = true
    else
        variants[cItem .. "s"] = true
    end
    if cItem:sub(-1) == "y" then
        variants[cItem:sub(1, -2) .. "ies"] = true
    elseif cItem:sub(-3) == "ies" then
        variants[cItem:sub(1, -4) .. "y"] = true
    end
    if cItem:sub(-1) == "x" or cItem:sub(-2) == "sh" or cItem:sub(-2) == "ch" then
        variants[cItem .. "es"] = true
    elseif cItem:sub(-2) == "es" and not cItem:sub(-3):find("[aeiou]es") then
        variants[cItem:sub(1, -3)] = true
    end
    variants[cItem .. "item"] = true
    return variants, cItem
end

local function countItemInGui(variants)
    local count = nil
    pcall(function()
        local pg = player:FindFirstChild("PlayerGui")
        if not pg then return end
        for _, desc in ipairs(pg:GetDescendants()) do
            if (desc:IsA("Frame") or desc:IsA("ImageLabel") or desc:IsA("TextButton")) and desc.Visible then
                local dName = desc.Name:gsub("[%s%-_']", ""):lower()
                if variants[dName] then
                    for _, sub in ipairs(desc:GetDescendants()) do
                        if sub:IsA("TextLabel") and sub.Visible then
                            local num = tonumber(sub.Text:match("^[xX]?%s*(%d+)%s*$"))
                            if num and (not count or num > count) then
                                count = num
                            end
                        end
                    end
                end
            end
        end
    end)
    return count
end

local function countItem(item, data)
    if not item then return 0 end
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

    local variants, cItem = nameVariants(item, cleanKey)

    if getgenv then
        local g = getgenv()
        if g.OwnedItems and type(g.OwnedItems) == "table" then
            local n = readAmount(g.OwnedItems[item] or g.OwnedItems[cleanKey] or g.OwnedItems[cItem])
            if n then return n end
        end
        if (cItem == "glitter" or variants["glitter"]) and (g.SkipGlitter or g.HasGlitter) then
            return 999999
        end
        if g["Has" .. cleanKey] or g["Skip" .. cleanKey] then
            return 999999
        end
    end

    if data then
        local folders = collectItemTables(data)
        for _, folder in ipairs(folders) do
            if type(folder) == "table" then
                for _, k in ipairs(keys) do
                    if folder[k] ~= nil then
                        local num = readAmount(folder[k])
                        if num then return num end
                    end
                end
                for k, v in pairs(folder) do
                    if type(k) == "string" then
                        local ck = tostring(k):gsub("[%s%-_']", ""):lower()
                        if variants[ck] then
                            local num = readAmount(v)
                            if num then return num end
                        end
                    end
                end
            end
        end
    end

    if getgenv then
        local atlas = getgenv().Atlas
        if type(atlas) == "table" then
            local aFolders = collectItemTables(atlas.Stats or atlas.Inventory or atlas.Data or atlas.Items or atlas)
            for _, folder in ipairs(aFolders) do
                if type(folder) == "table" then
                    for _, k in ipairs(keys) do
                        if folder[k] ~= nil then
                            local num = readAmount(folder[k])
                            if num then return num end
                        end
                    end
                    for k, v in pairs(folder) do
                        if type(k) == "string" then
                            local ck = tostring(k):gsub("[%s%-_']", ""):lower()
                            if variants[ck] then
                                local num = readAmount(v)
                                if num then return num end
                            end
                        end
                    end
                end
            end
        end
    end

    local guiAmount = countItemInGui(variants)
    if guiAmount then return guiAmount end

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
    ["planterofplenty"] = "Plenty Planter",
    ["glider"] = "Glider"
}

local function toItemName(raw)
    if not raw then return nil end
    local clean = tostring(raw):gsub("[%s%-_':%[%]%(%)]", ""):lower()
    if ITEM_ALIASES[clean] then return ITEM_ALIASES[clean] end
    -- khop chuoi con, uu tien alias dai nhat
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

-- chi khop dung ten, dung cho text lay tu UI
local function toItemNameExact(raw)
    if not raw then return nil end
    local clean = tostring(raw):gsub("[%s%-_':%[%]%(%)]", ""):lower()
    if clean == "" then return nil end
    if ITEM_ALIASES[clean] then return ITEM_ALIASES[clean] end
    for _, m in ipairs(DEFAULT_ROUTE) do
        if m.Name:gsub("[%s%-_':%[%]%(%)]", ""):lower() == clean then return m.Name end
    end
    return nil
end

local function itemKey(s)
    return tostring(toItemName(s) or s):gsub("[%s%-_']", ""):lower()
end

-- 0, false, "", {} deu tinh la khong co (Lua coi so 0 la truthy)
local function hasValue(v)
    if v == nil or v == false then return false end
    local t = type(v)
    if t == "number" then return v > 0 end
    if t == "string" then return v ~= "" and v ~= "0" end
    if t == "table" then return next(v) ~= nil end
    return true
end

local function isRouteItem(name)
    if not name or type(name) ~= "string" or #name < 2 then return false end
    local clean = name:gsub("[%s%-_':%[%]%(%)]", ""):lower()
    if ITEM_ALIASES[clean] then return true end
    for _, milestone in ipairs(DEFAULT_ROUTE) do
        local c = milestone.Name:gsub("[%s%-_':%[%]%(%)]", ""):lower()
        if c == clean then return true end
    end
    return false
end

local function normalizeGearSlot(val, tierTable)
    if val == nil then return nil end
    if type(val) == "table" then
        val = val.Name or val.Item or val.Type or val.Id
        if val == nil then return nil end
    end
    local c = tostring(val):gsub("[%s%-_']", ""):lower()
    if tierTable[c] then return c end
    local resolved = toItemName(val)
    if resolved then
        local rc = tostring(resolved):gsub("[%s%-_']", ""):lower()
        if tierTable[rc] then return rc end
    end
    return nil
end

local atlasSettingsCache = nil
local lastGcScan = { settings = 0, route = 0 }

local function isAtlasSettingsTable(t)
    if type(t) ~= "table" then return false end
    if type(t.autofarm) == "table" and (t.autofarm.field1 ~= nil or t.autofarm.field ~= nil or t.autofarm.fields ~= nil) then
        return true
    end
    if type(t.farming) == "table" and (t.farming.field1 ~= nil or t.farming.field ~= nil) then
        return true
    end
    local ok, hasToys = pcall(function() return t.toys end)
    local ok2, hasFarm = pcall(function() return t.autofarm or t.farming or (t.toys and t.toys.route) end)
    return ok and ok2 and (type(hasFarm) == "table" or (type(hasToys) == "table" and t.toys.route ~= nil))
end

local function findAtlasSettings()
    if atlasSettingsCache and isAtlasSettingsTable(atlasSettingsCache) then
        return atlasSettingsCache
    end

    local roots = dropNils({ getgenv and getgenv(), _G, shared }, 3)
    for _, root in ipairs(roots) do
        if type(root) == "table" then
            if isAtlasSettingsTable(root) then
                atlasSettingsCache = root
                return root
            end
            if root.Atlas and type(root.Atlas) == "table" then
                if isAtlasSettingsTable(root.Atlas.Settings) then
                    atlasSettingsCache = root.Atlas.Settings
                    return root.Atlas.Settings
                end
                if isAtlasSettingsTable(root.Atlas) then
                    atlasSettingsCache = root.Atlas
                    return root.Atlas
                end
            end
            if isAtlasSettingsTable(root.Settings) then
                atlasSettingsCache = root.Settings
                return root.Settings
            end
            if isAtlasSettingsTable(root.Config) then
                atlasSettingsCache = root.Config
                return root.Config
            end
            for k, v in pairs(root) do
                if type(v) == "table" and k ~= "_G" and k ~= "shared" and k ~= "game" and k ~= "workspace" and k ~= "Enum" then
                    if isAtlasSettingsTable(v) then
                        atlasSettingsCache = v
                        return v
                    end
                    if isAtlasSettingsTable(v.Settings) then
                        atlasSettingsCache = v.Settings
                        return v.Settings
                    end
                end
            end
        end
    end

    local minInterval = atlasSettingsCache and 60 or 30
    if getgc and (tick() - lastGcScan.settings > minInterval) then
        lastGcScan.settings = tick()
        local ok, gc = pcall(getgc, true)
        if not ok or type(gc) ~= "table" then ok, gc = pcall(getgc) end
        if ok and type(gc) == "table" then
            for _, obj in ipairs(gc) do
                if isAtlasSettingsTable(obj) then
                    atlasSettingsCache = obj
                    return obj
                end
            end
        end
    end

    return nil
end

local ownedPlanterCache = {}

local function ownsPlanter(cleanName, rawClean, canonical, data)
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

    if ownedPlanterCache[cleanName] or (canonical and ownedPlanterCache[canonical:lower()]) then
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
                ownedPlanterCache[cleanName] = true
                return true
            end
        end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if matches(item.Name) then
                ownedPlanterCache[cleanName] = true
                return true
            end
        end
    end

    if data then
        if (canonical and countItem(canonical, data) > 0)
            or countItem(cleanName, data) > 0
            or countItem(rawClean, data) > 0
            or (rootPlanter ~= "" and countItem(rootPlanter, data) > 0)
            or (rootPlanter ~= "" and countItem(rootPlanter .. " Planter", data) > 0) then
            ownedPlanterCache[cleanName] = true
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
        for _, tbl in ipairs(dropNils(pTables, 11)) do
            if type(tbl) == "table" then
                for k, v in pairs(tbl) do
                    if matches(k) and hasValue(v) then
                        ownedPlanterCache[cleanName] = true
                        return true
                    end
                    if type(v) == "string" and matches(v) then
                        ownedPlanterCache[cleanName] = true
                        return true
                    end
                    if type(v) == "table" then
                        if matches(v.Type) or matches(v.Name) or matches(v.PlanterType) or matches(v.Item) or matches(v.Id) then
                            ownedPlanterCache[cleanName] = true
                            return true
                        end
                        for k2, v2 in pairs(v) do
                            if (matches(k2) and hasValue(v2)) or (type(v2) == "string" and matches(v2)) then
                                ownedPlanterCache[cleanName] = true
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
                ownedPlanterCache[cleanName] = true
                return true
            end
            if desc:IsA("StringValue") and matches(desc.Value) then
                ownedPlanterCache[cleanName] = true
                return true
            end
        end
    end

    pcall(function()
        if not (getgenv and getgenv().AutoProgPlanterGuiScan == true) then return end
        if player:FindFirstChild("PlayerGui") then
            for _, desc in ipairs(player.PlayerGui:GetDescendants()) do
                if desc:IsA("TextLabel") and desc.Visible and #desc.Text <= 40 and matches(desc.Text) and not desc:FindFirstAncestor("AutoProg_HUD") then
                    local isShop = false
                    local cur = desc
                    for _ = 1, 6 do
                        if not cur then break end
                        local n = cur.Name:lower()
                        if n:find("shop") or n:find("dapper") then isShop = true; break end
                        cur = cur.Parent
                    end
                    if not isShop then
                        ownedPlanterCache[cleanName] = true
                        return
                    end
                end
            end
        end
    end)
    if ownedPlanterCache[cleanName] then return true end

    local pName = player.Name:lower()
    local pUserId = tostring(player.UserId)
    local pDisplay = player.DisplayName and player.DisplayName:lower() or pName

    local searchContainers = {
        workspace:FindFirstChild("Planters"),
        workspace:FindFirstChild("ActivePlanters"),
        workspace:FindFirstChild("CorePlanters"),
        workspace:FindFirstChild("Fields")
    }

    for _, c in ipairs(dropNils(searchContainers, 4)) do
        if c then
            for _, desc in ipairs(c:GetDescendants()) do
                if desc:IsA("TextLabel") then
                    local t = desc.Text:lower()
                    local tc = (t:gsub("[%s%-_']", ""))
                    if (t:find(pName, 1, true) or t:find(pDisplay, 1, true) or t:find(pUserId, 1, true))
                        and tc:find(rootPlanter, 1, true) then
                        ownedPlanterCache[cleanName] = true
                        return true
                    end
                end
                if desc:IsA("Model") then
                    local isMine = false
                    local owner = desc:FindFirstChild("Owner") or desc:FindFirstChild("Player") or desc:FindFirstChild("User")
                    if owner then
                        local okV, rawV = pcall(function() return owner.Value end)
                        if okV then
                            local ov = tostring(rawV):lower()
                            if ov == pName or ov == pUserId or rawV == player or (char and rawV == char) then
                                isMine = true
                            end
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
                            ownedPlanterCache[cleanName] = true
                            return true
                        end
                        local pType = desc:FindFirstChild("Type") or desc:FindFirstChild("PlanterType") or desc:FindFirstChild("PlantType")
                        if pType and matches(pType.Value) then
                            ownedPlanterCache[cleanName] = true
                            return true
                        end
                        local aType = desc:GetAttribute("Type") or desc:GetAttribute("PlanterType")
                        if aType and matches(aType) then
                            ownedPlanterCache[cleanName] = true
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
        if type(pSettings) == "table" and getgenv and getgenv().AutoProgTrustAtlasPlanters == true then
            for k, v in pairs(pSettings) do
                if matches(k) or (type(v) == "string" and matches(v)) then
                    ownedPlanterCache[cleanName] = true
                    return true
                end
                if type(v) == "table" and (matches(v.Type) or matches(v.Name) or matches(v.Planter)) then
                    ownedPlanterCache[cleanName] = true
                    return true
                end
            end
        end
    end

    return false
end

local function ownsItem(itemName, itemType, char, data)
    if not itemName then return false end
    local canonical = toItemName(itemName) or itemName
    local cleanName = tostring(canonical):gsub("[%s%-_']", ""):lower()
    local rawClean = tostring(itemName):gsub("[%s%-_']", ""):lower()

    if (itemType == "Planter" or cleanName:find("planter") or rawClean:find("planter")) then
        if ownsPlanter(cleanName, rawClean, canonical, data) then
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

    curTool = normalizeGearSlot(curTool, TOOL_TIERS)
    curBag = normalizeGearSlot(curBag, BAG_TIERS)
    curBoots = normalizeGearSlot(curBoots, BOOTS_TIERS)
    curBelt = normalizeGearSlot(curBelt, BELT_TIERS)
    curHat = normalizeGearSlot(curHat, HAT_TIERS)
    curSprinkler = normalizeGearSlot(curSprinkler, SPRINKLER_TIERS)
    curBlueGuard = normalizeGearSlot(curBlueGuard, BLUE_GUARD_TIERS)
    curRedGuard = normalizeGearSlot(curRedGuard, RED_GUARD_TIERS)
    if curGlider then
        local gc = tostring(curGlider):gsub("[%s%-_']", ""):lower()
        if gc ~= "glider" then curGlider = nil end
    end

    local function trackBestGear(val)
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
            trackBestGear(child.Name)
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
            trackBestGear(child.Name)
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
                trackBestGear(v)
                if hasValue(v) then trackBestGear(k) end
            elseif type(v) == "table" then
                for k2, v2 in pairs(v) do
                    if hasValue(v2) then trackBestGear(k2) end
                    if type(v2) == "string" or type(v2) == "number" then trackBestGear(v2) end
                end
            end
        end
    end

    local SPECIAL_MASKS = {
        ["honeymask"] = true, ["bubblemask"] = true, ["firemask"] = true,
        ["gummymask"] = true, ["demonmask"] = true, ["diamondmask"] = true, ["diamask"] = true
    }

    -- tier cao hon thi coi nhu co tier thap, cung tier thi phai dung ten
    local function slotCovers(cur, tierTbl, skipTier)
        if not cur then return false end
        local c = tostring(cur):gsub("[%s%-_']", ""):lower()
        if c == cleanName or c == rawClean then return true end
        if itemKey(c) == cleanName then return true end
        if skipTier then return false end
        local reqTier = tierTbl[cleanName] or tierTbl[rawClean]
        local curTier = tierTbl[c]
        return (reqTier and curTier and curTier > reqTier) and true or false
    end

    if slotCovers(curTool, TOOL_TIERS)
        or slotCovers(curBag, BAG_TIERS)
        or slotCovers(curBoots, BOOTS_TIERS)
        or slotCovers(curBelt, BELT_TIERS)
        or slotCovers(curHat, HAT_TIERS, SPECIAL_MASKS[cleanName] or SPECIAL_MASKS[rawClean])
        or slotCovers(curSprinkler, SPRINKLER_TIERS)
        or slotCovers(curBlueGuard, BLUE_GUARD_TIERS)
        or slotCovers(curRedGuard, RED_GUARD_TIERS) then
        return true
    end

    if (cleanName == "glider" or rawClean == "glider") and curGlider then
        return true
    end

    local eqSources = { eq, data, data and data.Accessories, data and data.Equipment, data and data.Items, data and data.Inventory }
    for _, src in ipairs(dropNils(eqSources, 6)) do
        if type(src) == "table" then
            if hasValue(src[canonical]) or hasValue(src[itemName]) or hasValue(src[cleanName]) or hasValue(src[rawClean]) then return true end
            for k, val in pairs(src) do
                local kClean = tostring(k):gsub("[%s%-_']", ""):lower()
                local vClean = tostring(val):gsub("[%s%-_']", ""):lower()
                if ((kClean == cleanName or kClean == rawClean) and hasValue(val)) or vClean == cleanName or vClean == rawClean then
                    return true
                end
            end
        end
    end

    return false
end

local BASE_ROUTE_FIELDS = {
    [0] = "Dandelion Field",
    [5] = "Bamboo Field",
    [10] = "Pineapple Patch",
    [15] = "Pine Tree Forest"
}

local routeFields = {}
for k, v in pairs(BASE_ROUTE_FIELDS) do
    routeFields[k] = v
end

local function getRouteField(beeCount)
    local bestBees = -1
    local bestField = "Pine Tree Forest"
    for reqBees, fld in pairs(routeFields) do
        if beeCount >= reqBees and reqBees > bestBees then
            bestBees = reqBees
            bestField = fld
        end
    end
    return bestField
end

local function getFarmField(material, beeCount)
    if material == "Stinger" then
        return getRouteField(beeCount)
    end
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


local VirtualInput = nil
pcall(function() VirtualInput = game:GetService("VirtualInputManager") end)
local GuiService = nil
pcall(function() GuiService = game:GetService("GuiService") end)

local function fireConnections(sig)
    local n = 0
    if not sig then return n end
    local ok, conns = pcall(getconnections, sig)
    if ok and type(conns) == "table" then
        for _, c in ipairs(conns) do
            if c.Fire then
                local fok = pcall(function() c:Fire() end)
                if fok then n = n + 1 end
            elseif c.Function then
                local fok = pcall(c.Function)
                if fok then n = n + 1 end
            end
        end
    end
    return n
end

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

local function isOnScreen(gui)
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
    if not isOnScreen(gui) then return end
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

    local clickable = gui
    if not gui:IsA("GuiButton") then
        clickable = gui:FindFirstAncestorWhichIsA("GuiButton") or gui
    end

    bringIntoView(clickable)

    if clickable:IsA("GuiButton") then
        local fired = false
        if getconnections then
            for _, sigName in ipairs({ "MouseButton1Click", "Activated" }) do
                local ok, cnt = pcall(function() return fireConnections(clickable[sigName]) end)
                if ok and cnt and cnt > 0 then
                    fired = true
                end
            end
        end
        if fired then return true end

        if firesignal then
            for _, sigName in ipairs({ "MouseButton1Click", "Activated" }) do
                if pcall(firesignal, clickable[sigName]) then return true end
            end
        end
    end

    if not isOnScreen(clickable) then return false end

    local size = clickable.AbsoluteSize
    local pos = clickable.AbsolutePosition
    local sg = clickable:FindFirstAncestorWhichIsA("ScreenGui")
    local inset = Vector2.new(0, 0)
    if GuiService and not (sg and sg.IgnoreGuiInset) then
        local okI, v = pcall(function() return GuiService:GetGuiInset() end)
        if okI and v then inset = v end
    end
    local x = pos.X + size.X / 2 + inset.X
    local y = pos.Y + size.Y / 2 + inset.Y

    if VirtualInput then
        local ok = pcall(function()
            VirtualInput:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.03)
            VirtualInput:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        if ok then return true end
    end
    if VirtualUser then
        local ok = pcall(function()
            VirtualUser:Button1Down(Vector2.new(x, y))
            task.wait(0.02)
            VirtualUser:Button1Up(Vector2.new(x, y))
        end)
        if ok then return true end
    end
    return false
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

local function getFarmingHeader(root)
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

local farmHeaderCache = nil

local function getFarmingHeaderCached(root)
    local c = farmHeaderCache
    if c and c.header and c.section and c.header:IsDescendantOf(root) and c.section:IsDescendantOf(root) then
        local txt = getGuiText(c.header):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if txt:lower():match("^field%s*:") then
            return c.section, c.header, txt
        end
    end
    local section, header, txt = getFarmingHeader(root)
    if section and header then farmHeaderCache = { section = section, header = header } end
    return section, header, txt
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
                if txt == name and isOnScreen(d) then
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

local configState = {
    path = nil, content = nil, route = nil, routeN = 0, routePath = nil,
    profile = nil, scannedAt = 0, reasons = {}, candidates = {}, ambiguous = false,
}

local function triggerButtonHeadless(btn)
    if not btn or not btn:IsA("GuiButton") then return false end
    local fired = false
    if getconnections then
        for _, sigName in ipairs({ "MouseButton1Click", "Activated" }) do
            if btn[sigName] then
                local n = fireConnections(btn[sigName])
                if n > 0 then fired = true end
            end
        end
    end
    if not fired and firesignal then
        for _, sigName in ipairs({ "MouseButton1Click", "Activated" }) do
            if pcall(firesignal, btn[sigName]) then fired = true break end
        end
    end
    return fired
end

local lastFileSync = { field = nil, vicious = false, at = 0 }

-- sua truc tiep text trong file config (khong decode/encode lai JSON,
-- vi JSONEncode doi {} thanh [] va lam hong config cua Atlas)
local function syncFieldAndViciousToActiveFile(targetField, enableVicious)
    if not (readfile and writefile and configState.path and isfile and isfile(configState.path)) then return end
    local wantField = targetField and targetField ~= "" and targetField ~= "Idle" and targetField ~= "Unchanged"
    if not wantField and not enableVicious then return end
    if (not wantField or lastFileSync.field == targetField)
        and (not enableVicious or lastFileSync.vicious)
        and tick() - lastFileSync.at < 20 then
        return
    end
    pcall(function()
        local content = readfile(configState.path)
        if type(content) ~= "string" or #content == 0 then return end
        local patched = content
        if wantField then
            local safe = targetField:gsub("%%", "%%%%")
            patched = patched:gsub('("field1"%s*:%s*)"[^"]*"', '%1"' .. safe .. '"')
            patched = patched:gsub('("field2"%s*:%s*)"[^"]*"', '%1"None"')
            patched = patched:gsub('("field3"%s*:%s*)"[^"]*"', '%1"None"')
        end
        if enableVicious then
            patched = patched:gsub('("killvicious"%s*:%s*)false', "%1true")
            patched = patched:gsub('("vicious"%s*:%s*)false', "%1true")
        end
        if patched ~= content then
            writefile(configState.path, patched)
        end
        lastFileSync.at = tick()
        if wantField then lastFileSync.field = targetField end
        if enableVicious then lastFileSync.vicious = true end
    end)
end

local function syncFieldAndViciousToMemory(targetField, enableVicious)
    local synced = false
    local settings = findAtlasSettings()
    if settings then
        if targetField and targetField ~= "" and targetField ~= "Idle" and targetField ~= "Unchanged" then
            if settings.autofarm and type(settings.autofarm) == "table" then
                settings.autofarm.field1 = targetField
                settings.autofarm.field2 = "None"
                settings.autofarm.field3 = "None"
                settings.autofarm.field = targetField
                if type(settings.autofarm.fields) == "table" then
                    settings.autofarm.fields[1] = targetField
                end
                synced = true
            end
            if settings.farming and type(settings.farming) == "table" then
                settings.farming.field1 = targetField
                settings.farming.field2 = "None"
                settings.farming.field = targetField
                synced = true
            end
        end
        if enableVicious then
            if not settings.combat or type(settings.combat) ~= "table" then settings.combat = {} end
            settings.combat.killvicious = true
            settings.combat.vicious = true
            settings.combat.giftedvicious = true
            if settings.combat.viciousmin == nil or settings.combat.viciousmin == 0 then settings.combat.viciousmin = 1 end
            if settings.combat.viciousmax == nil or settings.combat.viciousmax < 6 then settings.combat.viciousmax = 6 end
            synced = true
        end
    end

    local roots = dropNils({ getgenv and getgenv(), _G, shared }, 3)
    for _, root in ipairs(roots) do
        if type(root) == "table" then
            if root.Atlas and type(root.Atlas) == "table" then
                if targetField and targetField ~= "" and targetField ~= "Idle" and targetField ~= "Unchanged" then
                    root.Atlas.Field = targetField
                    root.Atlas.CurrentField = targetField
                    if root.Atlas.Settings and type(root.Atlas.Settings) == "table" then
                        root.Atlas.Settings.Field = targetField
                        if root.Atlas.Settings.autofarm then
                            root.Atlas.Settings.autofarm.field1 = targetField
                            root.Atlas.Settings.autofarm.field2 = "None"
                            root.Atlas.Settings.autofarm.field3 = "None"
                        end
                    end
                    if type(root.Atlas.SetField) == "function" then
                        pcall(root.Atlas.SetField, targetField)
                        synced = true
                    end
                end
                if enableVicious then
                    if not root.Atlas.Settings or type(root.Atlas.Settings) ~= "table" then root.Atlas.Settings = {} end
                    if not root.Atlas.Settings.combat or type(root.Atlas.Settings.combat) ~= "table" then root.Atlas.Settings.combat = {} end
                    root.Atlas.Settings.combat.killvicious = true
                    root.Atlas.Settings.combat.vicious = true
                    if type(root.Atlas.Toggle) == "function" then
                        pcall(root.Atlas.Toggle, "killvicious", true)
                        synced = true
                    end
                end
            end
            if root.Config and type(root.Config) == "table" then
                if targetField and targetField ~= "" and targetField ~= "Idle" and targetField ~= "Unchanged" and root.Config.autofarm then
                    root.Config.autofarm.field1 = targetField
                    root.Config.autofarm.field2 = "None"
                    root.Config.Field = targetField
                    synced = true
                end
                if enableVicious then
                    if not root.Config.combat or type(root.Config.combat) ~= "table" then root.Config.combat = {} end
                    root.Config.combat.killvicious = true
                    root.Config.combat.vicious = true
                    synced = true
                end
            end
            if enableVicious and type(root.Toggles) == "table" then
                for k, tog in pairs(root.Toggles) do
                    local lk = tostring(k):lower():gsub("[%s%-_']", "")
                    if lk == "killvicious" or lk == "vicious" or lk == "viciousbee" or lk == "autokillvicious" then
                        if type(tog) == "table" and type(tog.SetValue) == "function" then
                            pcall(function() tog:SetValue(true) end)
                            synced = true
                        end
                    end
                end
            end
            if targetField and targetField ~= "" and targetField ~= "Idle" and targetField ~= "Unchanged" and type(root.Options) == "table" then
                for k, opt in pairs(root.Options) do
                    local lk = tostring(k):lower():gsub("[%s%-_']", "")
                    if lk == "field1" or lk == "field" or lk == "autofarmfield" or lk == "farmingfield" or lk == "fields" then
                        if type(opt) == "table" and type(opt.SetValue) == "function" then
                            pcall(function() opt:SetValue(targetField) end)
                            synced = true
                        end
                    end
                end
            end
        end
    end
    return synced
end

local function setFieldViaUI(targetField)
    local uiRoots = {}
    pcall(function() if gethui then table.insert(uiRoots, gethui()) end end)
    pcall(function() table.insert(uiRoots, CoreGui) end)
    pcall(function() table.insert(uiRoots, player:FindFirstChild("PlayerGui")) end)

    local targetClean = targetField:gsub("[%s%-_']", ""):lower()

    for _, root in ipairs(uiRoots) do
        if root then
            for _, btn in ipairs(root:GetDescendants()) do
                if btn:IsA("TextButton") or btn:IsA("ImageButton") then
                    local rawTxt = getGuiText(btn):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower():gsub("[%s%-_']", "")
                    if rawTxt == targetClean then
                        local bName = tostring(btn.Name):lower()
                        local pName = tostring(btn.Parent and btn.Parent.Name or ""):lower()
                        if bName:find("dropdown") or pName:find("objects") or pName:find("dropdown") or bName == "dropdownbutton" then
                            if triggerButtonHeadless(btn) then
                                return true, "headless_dropdown_item"
                            end
                        end
                    end
                end
            end

            local section, farmingHeader, headerTxt = getFarmingHeaderCached(root)
            if farmingHeader and headerTxt then
                local cur = headerTxt:match("^[Ff]ield%s*:%s*(.+)")
                if cur and (cur:gsub("[%s%-_']", "")):lower() == targetClean then
                    return true, "ui_already_set"
                end
            end

            local isFarmingVisible = farmingHeader and isOnScreen(farmingHeader)
            local prevTabName, prevTabBtn = nil, nil
            local switchedTab = false

            if farmingHeader then
                local curVal = headerTxt and headerTxt:match("^[Ff]ield%s*:%s*(.+)")
                if curVal and curVal:gsub("[%s%-_']", ""):lower() == targetClean then
                    if switchedTab and prevTabBtn then triggerButtonHeadless(prevTabBtn) end
                    return true, "ui_already_set"
                end

                local clickTarget = farmingHeader:IsA("TextButton") and farmingHeader
                    or farmingHeader:FindFirstAncestorWhichIsA("TextButton")
                    or farmingHeader:FindFirstAncestorWhichIsA("ImageButton")
                    or farmingHeader.Parent

                triggerButtonHeadless(clickTarget)
                task.wait(0.08)

                local foundAndClicked = false
                for _, container in ipairs(dropNils({ section, root }, 2)) do
                    if not foundAndClicked and container then
                        for _, btn in ipairs(container:GetDescendants()) do
                            if (btn:IsA("TextButton") or btn:IsA("TextLabel") or btn:IsA("ImageButton")) and btn ~= farmingHeader and btn ~= clickTarget and btn.Name ~= "AutoProg_HUD" then
                                local rawTxt = getGuiText(btn):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
                                if rawTxt:gsub("[%s%-_']", ""):lower() == targetClean then
                                    if triggerButtonHeadless(btn:IsA("GuiButton") and btn or btn:FindFirstAncestorWhichIsA("GuiButton")) then
                                        foundAndClicked = true
                                        task.wait(0.04)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end

                if switchedTab and prevTabBtn then
                    task.wait(0.04)
                    triggerButtonHeadless(prevTabBtn)
                end

                if foundAndClicked then
                    return true, "ui_field_set"
                end
            elseif switchedTab and prevTabBtn then
                triggerButtonHeadless(prevTabBtn)
            end
        end
    end
    return false, "ui_not_found"
end

local lastSetField = nil
local lastFieldUiTime = 0

local function setField(field)
    if not field or field == "Idle" or field == "Unchanged" then return end

    local memOk = syncFieldAndViciousToMemory(field, nil)
    syncFieldAndViciousToActiveFile(field, nil)

    if not memOk and ((field ~= lastSetField) or (tick() - lastFieldUiTime > 60)) then
        lastFieldUiTime = tick()
        lastSetField = field
        pcall(setFieldViaUI, field)
    end
end

local viciousUiDone = false
local lastViciousCheck = 0

local function isViciousToggleText(txt)
    if not txt or type(txt) ~= "string" then return false end
    local low = txt:lower():gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if low:find("gifted") or low:find("min") or low:find("max") or low:find("level") or low:find("whitelist") then
        return false
    end
    return low == "auto kill vicious bee" or low == "auto kill vicious" or low == "kill vicious bee" or low:find("auto kill vicious")
end

local function isViciousSectionText(txt)
    if not txt or type(txt) ~= "string" then return false end
    local low = txt:lower():gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return low == "vicious bee"
end

local function isToggleOn(btn, row)
    if btn and btn:IsA("TextButton") and btn.Text == "✓" then
        return true
    end

    local objs = {}
    if row then
        for _, d in ipairs(row:GetDescendants()) do table.insert(objs, d) end
        table.insert(objs, row)
    end
    if btn then
        for _, d in ipairs(btn:GetDescendants()) do table.insert(objs, d) end
        table.insert(objs, btn)
    end

    for _, obj in ipairs(objs) do
        for _, attr in ipairs({ "Toggled", "Value", "Checked", "State", "Enabled" }) do
            local val = obj:GetAttribute(attr)
            if val == true then return true end
        end

        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local t = getGuiText(obj):lower():gsub("%s+", "")
            if t == "on" or t == "true" or t == "enabled" or t == "[x]" or t == "✓" or t == "✔" or t == "☑" then
                return true
            end
        end

        if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
            local img = tostring(obj.Image or ""):lower()
            if (img:find("check") or img:find("tick") or img:find("checkmark")) and obj.ImageTransparency < 0.5 and obj.Visible then
                return true
            end
        end

        if obj:IsA("GuiObject") and obj.BackgroundTransparency < 0.5 and obj.Visible then
            local c = obj.BackgroundColor3
            if c and c.G > 0.55 and c.G > c.R * 1.25 and c.G > c.B * 1.25 then
                return true
            end
        end
    end

    return false
end

local function findViciousSwitch(root)
    if not root then return nil, nil end

    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and d.Name ~= "AutoProg_HUD" then
            local t = getGuiText(d)
            if isViciousToggleText(t) then
                local btn = (d.Parent and d.Parent:IsA("TextButton") and d.Parent)
                    or (d:IsA("TextButton") and d)
                    or (d.Parent and d.Parent.Parent and d.Parent.Parent:FindFirstChildWhichIsA("TextButton", true))
                if btn then return btn, d.Parent end
            end
        end
    end

    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextButton") and isViciousSectionText(d.Text) then
            local box = d.Parent and d.Parent:FindFirstChild("Box")
            if box then
                for _, s in ipairs(box:GetDescendants()) do
                    if s:IsA("TextLabel") and isViciousToggleText(getGuiText(s)) then
                        local btn = (s.Parent and s.Parent:IsA("TextButton") and s.Parent)
                            or (s:IsA("TextButton") and s)
                            or (s.Parent and s.Parent:FindFirstChildWhichIsA("TextButton"))
                        if btn then return btn, s.Parent end
                    end
                end
                local firstSwitch = box:FindFirstChild("Switch")
                if firstSwitch then
                    local btn = firstSwitch:FindFirstChildWhichIsA("TextButton", true)
                    if btn then return btn, firstSwitch end
                end
            end
        end
    end

    return nil, nil
end

local function setViciousViaUI(enable)
    local uiRoots = {}
    pcall(function() if gethui then table.insert(uiRoots, gethui()) end end)
    pcall(function() table.insert(uiRoots, CoreGui) end)
    pcall(function() table.insert(uiRoots, player:FindFirstChild("PlayerGui")) end)

    for _, root in ipairs(uiRoots) do
        if root then
            local switchBtn, switchRow = findViciousSwitch(root)
            local prevTabName, prevTabBtn = nil, nil
            local switchedTab = false

            -- Khong tu dong chuyen tab combat de khong lam lo UI
            -- switchBtn chi duoc tim neu da co san tren UI hien tai

            if switchBtn then
                local isChecked = isToggleOn(switchBtn, switchRow)
                if enable and not isChecked then
                    triggerButtonHeadless(switchBtn)
                    task.wait(0.05)
                    viciousUiDone = true
                elseif isChecked then
                    viciousUiDone = true
                end

                if switchedTab and prevTabBtn then
                    task.wait(0.04)
                    triggerButtonHeadless(prevTabBtn)
                end

                return true, "ui_vicious_set"
            elseif switchedTab and prevTabBtn then
                task.wait(0.04)
                triggerButtonHeadless(prevTabBtn)
            end
        end
    end
    return false, "ui_vicious_not_found"
end

local function enableViciousKill()
    syncFieldAndViciousToMemory(nil, true)
    syncFieldAndViciousToActiveFile(nil, true)

    if not viciousUiDone or (tick() - lastViciousCheck > 30) then
        lastViciousCheck = tick()
        pcall(setViciousViaUI, true)
    end
end

local function needsStinger(targetItem, data)
    if not targetItem or targetItem == "None" then return false, 0 end
    local matched = nil
    local cTarget = targetItem:gsub("[%s%-_']", ""):lower()
    for _, m in ipairs(DEFAULT_ROUTE) do
        local cm = m.Name:gsub("[%s%-_']", ""):lower()
        if cm == cTarget then
            matched = m
            break
        end
    end
    if not matched or not matched.Ingredients then return false, 0 end
    for _, ing in ipairs(matched.Ingredients) do
        if ing.Item == "Stinger" then
            local invCount = countItem("Stinger", data)
            local deficit = ing.Amount - invCount
            if deficit > 0 then
                return true, deficit
            end
        end
    end
    return false, 0
end

local function findMissingMaterial(item, neededAmount, data, beeCount)
    local invCount = countItem(item, data)
    local deficit = neededAmount - invCount
    if deficit <= 0 then return nil end

    if getgenv then
        local g = getgenv()
        local cleanKey = tostring(item):gsub("%s+", "")
        local cItem = tostring(item):gsub("[%s%-_']", ""):lower()
        if (cItem == "glitter" or cItem == "glitters") and (g.SkipGlitter or g.HasGlitter) then
            return nil
        end
        if g["Skip" .. cleanKey] or g["Has" .. cleanKey] then
            return nil
        end
        if g.SkipUnfarmable and not getRecipe(item) and not getFarmField(item, beeCount) then
            return nil
        end
    end

    local recipe = getRecipe(item)
    if recipe then
        local firstUnfarmMat, firstUnfarmAmt = nil, 0
        for _, sub in ipairs(recipe) do
            local totalSubNeeded = deficit * sub.Amount
            local missingMat, missingAmt, targetField, isUnfarm = findMissingMaterial(sub.Item, totalSubNeeded, data, beeCount)
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
        local field = getFarmField(item, beeCount)
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
    if st == "purchase" or st == "buy" or st == "craft" or st == "field" or st == "event bee" or st == "eventbee" or st == "codes" then return true end
    if step.config == "farming.field1" or step.group or step.target or step.gear or step.data or step.Data then return true end
    return false
end

local function collectPurchases(tbl, depth)
    if type(tbl) ~= "table" or ((depth or 0) > 8) then return nil end
    local items = {}
    local seen = {}

    local function scan(t, d)
        if type(t) ~= "table" or d > 8 then return end
        if seen[t] then return end
        seen[t] = true

        if t.config == "farming.field1" and t.data and type(t.data) == "string" then
            local reqBees = tonumber(t.required_bees or t.Bees) or 0
            routeFields[reqBees] = t.data
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

local function findRouteInMemory()
    local settings = findAtlasSettings()
    if settings then
        if settings.toys and type(settings.toys) == "table" and settings.toys.route then
            return settings.toys.route
        end
        if settings.route and type(settings.route) == "table" then
            return settings.route
        end
    end

    local roots = dropNils({ getgenv and getgenv(), _G, shared }, 3)
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

    if getgc and (tick() - lastGcScan.route > 60) then
        lastGcScan.route = tick()
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

local lastRouteFile = "none"
local routeSourceName = "none"

-- doc config cua Atlas trong workspace de lay route

configState = configState or {
    path = nil, content = nil, route = nil, routeN = 0, routePath = nil,
    profile = nil, scannedAt = 0, reasons = {}, candidates = {}, ambiguous = false,
}

local POINTER_KEYS = {
    selected = true, current = true, last = true, autoload = true, lastconfig = true,
    selected_profile = true, selected_preset = true, profile = true, preset = true,
    config = true, config_name = true, currentconfig = true, currentprofile = true,
}

local function normPath(p)
    p = tostring(p):gsub("\\", "/"):gsub("^%./", ""):gsub("/+$", "")
    return p
end

local function baseName(p)
    return tostring(p):match("([^/]+)$") or tostring(p)
end

local function stripExt(n)
    return (tostring(n):gsub("%.[%w_]+$", ""))
end

local function cleanKey(s)
    return (tostring(s):lower():gsub("[%s%-_%.]", ""))
end

local function listDir(path)
    if not listfiles then return {} end
    local ok, res = pcall(listfiles, path)
    if not ok or type(res) ~= "table" then return {} end
    local out = {}
    for _, f in ipairs(res) do out[#out + 1] = normPath(f) end
    return out
end

local function fsIsFile(p)
    if not isfile then return false end
    local ok, r = pcall(isfile, p)
    return ok and r == true
end

local function fsIsFolder(p)
    if isfolder then
        local ok, r = pcall(isfolder, p)
        if ok then return r == true end
    end
    return not fsIsFile(p) and #listDir(p) > 0
end

local function safeRead(p)
    if not readfile then return nil end
    local ok, c = pcall(readfile, p)
    if ok and type(c) == "string" then return c end
    return nil
end

local function discoverAtlasRoots()
    local roots, seen = {}, {}
    local function add(p)
        p = normPath(p)
        if not seen[p] then seen[p] = true; roots[#roots + 1] = p end
    end

    local g = getgenv and getgenv() or nil
    if g and type(g.AtlasConfigDir) == "string" then add(g.AtlasConfigDir) end

    add("")
    add(".")
    add("atlas")
    add("Atlas")

    local top = listDir("")
    if #top == 0 then top = listDir(".") end
    for _, entry in ipairs(top) do
        if baseName(entry):lower():find("atlas", 1, true) and not fsIsFile(entry) then
            add(entry)
        end
    end

    for _, name in ipairs({ "atlas1", "Atlas", "atlas", "AtlasBSS", "Atlas BSS" }) do
        if not seen[name] and fsIsFolder(name) then add(name) end
    end
    return roots
end

local function collectFiles(dir, depth, out)
    if depth > 4 or #out >= 200 then return end
    for _, entry in ipairs(listDir(dir)) do
        if #out >= 200 then return end
        if fsIsFile(entry) then
            out[#out + 1] = entry
        else
            collectFiles(entry, depth + 1, out)
        end
    end
end

local function decodeConfig(content)
    if type(content) ~= "string" or #content < 2 or #content > 2000000 then return nil end
    content = content:gsub("^\239\187\191", "")
    local first = content:match("^%s*(.)")
    if first ~= "{" and first ~= "[" then return nil end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(content) end)
    if ok and type(decoded) == "table" then return decoded end
    return nil
end

local function countRouteSteps(arr)
    local n = 0
    for i = 1, #arr do
        if isRouteStep(arr[i]) then n = n + 1 end
    end
    return n
end

-- tim route trong cay json: uu tien key "route", sau do la mang nhieu step nhat
local function findRouteInTree(tree)
    if type(tree) ~= "table" then return nil, 0, nil end
    if tree.toys and type(tree.toys) == "table" and type(tree.toys.route) == "table" and #tree.toys.route > 0 then
        return tree.toys.route, countRouteSteps(tree.toys.route), "$.toys.route"
    end
    if type(tree.route) == "table" and #tree.route > 0 then
        return tree.route, countRouteSteps(tree.route), "$.route"
    end
    local best, bestScore, bestN, bestPath = nil, 0, 0, nil
    local seen = {}
    local function walk(t, key, path, d)
        if type(t) ~= "table" or seen[t] or d > 10 then return end
        seen[t] = true
        local n = (#t > 0) and countRouteSteps(t) or 0
        local score = n
        local isRouteKey = type(key) == "string" and key:lower():find("route", 1, true) ~= nil
        if isRouteKey and next(t) ~= nil then score = score + 500 end
        if score > bestScore and (n > 0 or isRouteKey) then
            best, bestScore, bestN, bestPath = t, score, n, path
        end
        for k, v in pairs(t) do
            if type(v) == "table" then walk(v, k, path .. "." .. tostring(k), d + 1) end
        end
    end
    walk(tree, nil, "$", 0)
    return best, bestN, bestPath
end

-- gom gia tri don gian de so voi settings dang chay
local function flattenScalars(t, prefix, out, d, seen)
    if type(t) ~= "table" or d > 4 or seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
        local ks = tostring(k):lower()
        if not ks:find("field", 1, true) and not ks:find("route", 1, true) then
            local p = prefix .. "." .. ks
            local tv = type(v)
            if tv == "string" or tv == "number" or tv == "boolean" then
                out[p] = v
            elseif tv == "table" then
                flattenScalars(v, p, out, d + 1, seen)
            end
        end
    end
end

local function similarityToLive(decoded, live)
    if type(live) ~= "table" then return 0, 0 end
    local a, b = {}, {}
    pcall(flattenScalars, decoded, "", a, 0, {})
    pcall(flattenScalars, live, "", b, 0, {})
    local same, total = 0, 0
    for p, v in pairs(b) do
        if a[p] ~= nil then
            total = total + 1
            if a[p] == v then same = same + 1 end
        end
    end
    return same, total
end

local function getLiveProfileName()
    local settings = findAtlasSettings()
    if not settings then return nil end
    for _, k in ipairs({ "selected_profile", "profile", "preset", "selected_preset", "config_name" }) do
        local v = settings[k]
        if type(v) == "string" and v ~= "" then return v end
    end
    return nil
end

local function scanAtlasConfigs()
    local roots = discoverAtlasRoots()
    local files = {}
    for _, r in ipairs(roots) do collectFiles(r, 0, files) end
    for _, entry in ipairs(listDir("")) do
        if fsIsFile(entry) and entry:lower():match("%.json$") then
            local low = baseName(entry):lower()
            if not low:match("^atlas%-") and not low:match("^atlascache") then
                files[#files + 1] = entry
            end
        end
    end

    local g = getgenv and getgenv() or nil
    local customPath = g and (g.AtlasConfigPath or g.AtlasRouteFile or g.AtlasPresetFile)
    if type(customPath) == "string" and fsIsFile(customPath) then
        table.insert(files, 1, normPath(customPath))
    end

    local liveSettings = findAtlasSettings()
    local liveProfile = getLiveProfileName()
    local liveProfileKey = liveProfile and cleanKey(stripExt(baseName(liveProfile))) or nil

    local cands, pointers, seenPath = {}, {}, {}
    for _, path in ipairs(files) do
        if not seenPath[path] then
            seenPath[path] = true
            local content = safeRead(path)
            local decoded = content and decodeConfig(content)
            if decoded then
                for k, v in pairs(decoded) do
                    if type(k) == "string" and POINTER_KEYS[k:lower()] and type(v) == "string" and v ~= "" then
                        pointers[cleanKey(stripExt(baseName(v)))] = k
                    end
                end
                local route, n, rpath = findRouteInTree(decoded)
                if route then
                    cands[#cands + 1] = {
                        path = path, content = content, decoded = decoded,
                        route = route, routeN = n, routePath = rpath,
                        key = cleanKey(stripExt(baseName(path))), score = 0, reasons = {},
                    }
                end
            end
        end
    end

    for _, c in ipairs(cands) do
        if type(customPath) == "string" and c.path == normPath(customPath) then
            c.score = c.score + 10000; c.reasons[#c.reasons + 1] = "user override (AtlasConfigPath)"
        end
        if liveProfileKey and c.key == liveProfileKey then
            c.score = c.score + 1000; c.reasons[#c.reasons + 1] = "ten trung profile dang chay: " .. tostring(liveProfile)
        end
        if pointers[c.key] then
            c.score = c.score + 600; c.reasons[#c.reasons + 1] = "duoc tro toi boi key '" .. pointers[c.key] .. "'"
        end
        if liveSettings then
            local same, total = similarityToLive(c.decoded, liveSettings)
            if total >= 3 then
                local ratio = same / total
                c.score = c.score + math.floor(ratio * 300)
                c.reasons[#c.reasons + 1] = string.format("khop settings dang chay %d/%d", same, total)
            end
        end
        if c.key == "default" then c.score = c.score - 500 end
        c.score = c.score + math.min(c.routeN, 50) * 0.1
    end

    table.sort(cands, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.path < b.path
    end)

    local ambiguous = #cands > 1 and (cands[1].score - cands[2].score) < 1
    return cands, ambiguous, liveProfile, roots, #files
end


-- Atlas luu preset dang chon vao file atlas-<id>.json (noi dung la ten file preset)
local function findPointerFiles()
    local found, seen = {}, {}
    local function scan(dir)
        for _, entry in ipairs(listDir(dir)) do
            local low = baseName(entry):lower()
            if low:match("^atlas%-.+%.json$") and not seen[entry] and fsIsFile(entry) then
                seen[entry] = true
                found[#found + 1] = entry
            end
        end
    end
    scan("")
    if #found == 0 then scan(".") end
    return found
end

local function pickPointerFile(files)
    if #files == 0 then return nil, false end
    if #files == 1 then return files[1], false end
    local pn = tostring(player.Name):lower()
    local uid = tostring(player.UserId)
    for _, f in ipairs(files) do
        local low = baseName(f):lower()
        if low == "atlas-" .. pn .. ".json" then return f, false end
    end
    for _, f in ipairs(files) do
        local low = baseName(f):lower()
        if low == "atlas-" .. uid .. ".json" then return f, false end
    end
    for _, f in ipairs(files) do
        local low = baseName(f):lower()
        if low:find(pn, 1, true) then return f, false end
    end
    for _, f in ipairs(files) do
        local low = baseName(f):lower()
        if low:find(uid, 1, true) then return f, false end
    end
    table.sort(files)
    return files[1], true
end

local function resolvePresetFromPointer()
    local g = getgenv and getgenv() or nil
    local files = findPointerFiles()
    if g and type(g.AtlasPointerFile) == "string" and fsIsFile(g.AtlasPointerFile) then
        files = { normPath(g.AtlasPointerFile) }
    end
    local ptr, amb = pickPointerFile(files)
    if not ptr then return nil end
    local raw = safeRead(ptr)
    if not raw then return nil end
    local name = raw:gsub("^\239\187\191", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    name = name:gsub('^"(.*)"$', "%1")
    if name == "" then return nil end
    if not name:lower():find("%.json$") then name = name .. ".json" end

    local base = baseName(name)
    local tries = { name, base, "atlas/" .. base, "Atlas/" .. base }
    for _, r in ipairs(discoverAtlasRoots()) do
        if r ~= "" and r ~= "." then
            tries[#tries + 1] = r .. "/" .. base
        end
    end
    for _, p in ipairs(tries) do
        if fsIsFile(p) then return p, ptr, amb, base end
    end
    return nil, ptr, amb, base
end

local warnedNoRoute = nil

local function readRouteFile()
    if not (readfile and isfile) then return nil end

    local now = tick()

    -- uu tien doc file con tro de biet preset dang dung
    local okP, presetPath, ptrPath, ptrAmb, presetName = pcall(resolvePresetFromPointer)
    if okP and ptrPath then
        configState.pointer = ptrPath
        configState.pointerAmbiguous = ptrAmb
        configState.roots = configState.roots or discoverAtlasRoots()
        if presetPath then
            local content = safeRead(presetPath)
            if content and configState.viaPointer and configState.path == presetPath and configState.content == content and configState.route then
                lastRouteFile = presetPath
                return configState.route
            end
            local decoded = content and decodeConfig(content)
            local route, n, rpath
            if decoded then route, n, rpath = findRouteInTree(decoded) end

            local diag
            if not route then
                if not content then diag = "readfile loi"
                elseif #content == 0 then diag = "file rong"
                elseif not decoded then diag = string.format("JSON loi/dang ghi do (len=%d, dau=%q)", #content, content:sub(1, 40))
                else diag = "JSON ok nhung khong thay route" end
            end

            -- Atlas co the dang ghi file, giu route cu va thu lai
            if not route and configState.path == presetPath and configState.route and (configState.failCount or 0) < 3 then
                configState.failCount = (configState.failCount or 0) + 1
                configState.lastFail = diag
                lastRouteFile = presetPath
                warn(string.format("[Auto Prog] Doc preset loi tam thoi (%s) - dung route cu, lan %d/3", diag, configState.failCount))
                return configState.route
            end
            configState.failCount = route and 0 or ((configState.failCount or 0) + 1)
            configState.lastFail = diag
            local changed = configState.path ~= presetPath
            configState.viaPointer = true
            configState.path, configState.content = presetPath, content
            configState.route, configState.routeN, configState.routePath = route, n or 0, rpath
            configState.reasons = { "file con tro " .. ptrPath .. " -> " .. tostring(presetName) }
            configState.candidates = {}
            configState.ambiguous = ptrAmb == true
            lastRouteFile = presetPath
            if changed then
                print(string.format("[Auto Prog] Preset Atlas dang dung: %s (qua %s)", presetPath, ptrPath))
            end
            if route then
                if changed then print(string.format("[Auto Prog] Route @ %s (%d step)", tostring(rpath), tonumber(n) or 0)) end
                return route
            end
            if warnedNoRoute ~= presetPath then
                warnedNoRoute = presetPath
                warn("[Auto Prog] Preset dang dung khong co route nhan dien duoc: " .. presetPath .. " (" .. tostring(diag) .. ")")
            end
            return nil
        end
        warn("[Auto Prog] File con tro tro toi preset khong ton tai: " .. tostring(presetName))
    end
    configState.viaPointer = false

    local liveProfile = getLiveProfileName()

    -- file chua doi thi khoi quet lai
    if configState.path and configState.route and now - configState.scannedAt < 120 and configState.profile == liveProfile then
        local cur = safeRead(configState.path)
        if cur and cur == configState.content then
            lastRouteFile = configState.path
            return configState.route
        end
    end

    local cands, ambiguous, profile, roots, nFiles = scanAtlasConfigs()
    configState.scannedAt = now
    configState.profile = profile
    configState.candidates = cands
    configState.ambiguous = ambiguous
    configState.roots = roots
    configState.fileCount = nFiles

    local top = cands[1]
    if not top then
        configState.path, configState.content, configState.route, configState.reasons = nil, nil, nil, {}
        return nil
    end

    local changed = configState.path ~= top.path
    configState.path, configState.content = top.path, top.content
    configState.route, configState.routeN, configState.routePath = top.route, top.routeN, top.routePath
    configState.reasons = top.reasons
    lastRouteFile = top.path

    if changed then
        print(string.format("[Auto Prog] Config Atlas dang dung: %s (route @ %s, %d step)", tostring(top.path), tostring(top.routePath), tonumber(top.routeN) or 0))
        if ambiguous then
            warn("[Auto Prog] Nhieu config co route va khong phan biet duoc cai dang dung. Dat getgenv().AtlasConfigPath = \"duong/dan/file.json\" de chon tay.")
        end
    end
    return top.route
end

local function getCustomRoute()
    local roots = dropNils({ getgenv and getgenv(), _G, shared }, 3)
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

local routeCache = nil
local routeCacheTime = 0
local routeFound = false
local lastCustomRoute = nil

local function getRoute()
    local customUserRoute = getCustomRoute()
    if customUserRoute ~= lastCustomRoute then
        lastCustomRoute = customUserRoute
        routeCache = nil
    end

    if routeCache and (tick() - routeCacheTime < 30) then
        return routeCache
    end

    for k in pairs(routeFields) do
        routeFields[k] = nil
    end
    for k, v in pairs(BASE_ROUTE_FIELDS) do
        routeFields[k] = v
    end

    local rawRoute, routeSrc
    if customUserRoute then
        rawRoute, routeSrc = customUserRoute, "custom"
    else
        local preferMemory = getgenv and getgenv().AtlasRouteSource == "memory"
        local function tryFile()
            local okF, r = pcall(readRouteFile)
            if okF and r then return r, "file:" .. tostring(lastRouteFile) end
            if not okF then warn("[Auto Prog] config scan error: " .. tostring(r)) end
            return nil
        end
        local function tryMemory()
            local okM, r = pcall(findRouteInMemory)
            if okM and r then return r, "memory" end
            return nil
        end
        -- Uu tien doc route ngam tu memory (nhanh, khong can doc file)
        rawRoute, routeSrc = tryMemory()
        if not rawRoute then rawRoute, routeSrc = tryFile() end
    end
    routeSourceName = routeSrc or "none"
    local rawItemsList = rawRoute and collectPurchases(rawRoute, 0)

    if rawItemsList and type(rawItemsList) == "table" and #rawItemsList > 0 then
        local itemMap = {}
        for _, entry in ipairs(DEFAULT_ROUTE) do
            local clean = entry.Name:gsub("[%s%-_']", ""):lower()
            itemMap[clean] = entry
        end

        local dynamicRoute = {}
        for _, rawItem in ipairs(rawItemsList) do
            local name = (type(rawItem) == "table" and (rawItem.Name or rawItem.Item or rawItem.Target or rawItem.Gear)) or (type(rawItem) == "string" and rawItem)
            local reqBees = (type(rawItem) == "table" and (rawItem.Bees or rawItem.BeeCount or rawItem.ReqBees))
            if name then
                local canonical = toItemName(name) or name
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
            routeFound = true
            routeCache = dynamicRoute
            routeCacheTime = tick()
            return dynamicRoute
        end
    end

    routeFound = true
    routeCache = DEFAULT_ROUTE
    routeCacheTime = tick()
    routeSourceName = "default_fallback"
    return DEFAULT_ROUTE
end

local targetSource = "none"

local nextItemCache = { at = 0, val = nil, raw = nil }

-- doc dong "Next item: <ten>" tren UI Atlas, day la nguon dang tin nhat
local function readNextItemLabel()
    if tick() - nextItemCache.at < 4 then return nextItemCache.val end
    nextItemCache.at = tick()
    nextItemCache.val, nextItemCache.raw = nil, nil

    local uiRoots = {}
    pcall(function() if gethui then table.insert(uiRoots, gethui()) end end)
    pcall(function() table.insert(uiRoots, CoreGui) end)
    pcall(function() table.insert(uiRoots, player:FindFirstChild("PlayerGui")) end)

    for _, root in ipairs(uiRoots) do
        if root then
            local okD, descs = pcall(function() return root:GetDescendants() end)
            if okD and type(descs) == "table" then
                for _, d in ipairs(descs) do
                    local okC, isText = pcall(function() return d:IsA("TextLabel") or d:IsA("TextButton") end)
                    if okC and isText and d.Name ~= "AutoProg_HUD" then
                        local okT, txt = pcall(function() return d.Text end)
                        if okT and type(txt) == "string" and #txt < 120 then
                            txt = txt:gsub("<[^>]+>", "")
                            local m = txt:match("[Nn]ext%s+[Ii]tem%s*[:%-]%s*([^\n\r:]+)")
                            if m then
                                m = m:gsub("^%s+", "")
                                m = m:gsub("%s+$", "")
                                nextItemCache.raw = m
                                local res = toItemNameExact(m) or toItemNameExact((m:gsub("[%s%d]+$", "")))
                                if res then
                                    nextItemCache.val = res
                                    return res
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

local function getLiveTarget()
    targetSource = "none"

    local function accept(raw, srcName)
        if raw == nil then return nil end
        local res = toItemName(raw)
        if res and isRouteItem(res) then
            targetSource = srcName
            return res
        end
        return nil
    end

    -- 1. Uu tien doc ngam tu memory (settings / globals / Atlas objects)
    local settings = findAtlasSettings()
    if settings then
        local t = settings.toys
        if type(t) == "table" then
            local r = accept(t.target, "settings.toys.target")
                or accept(t.current, "settings.toys.current")
                or accept(t.current_target, "settings.toys.current_target")
                or accept(t.current_purchase, "settings.toys.current_purchase")
            if r then return r end
        end
        local r = accept(settings.target, "settings.target")
        if r then return r end
    end

    local roots = dropNils({ getgenv and getgenv(), _G, shared }, 3)
    local allowUI = true
    for _, r in ipairs(roots) do
        if type(r) == "table" then
            if type(r.Atlas) == "table" then
                local targets = dropNils({ r.Atlas.ProgressionTarget, r.Atlas.CurrentTarget, r.Atlas.Target, r.Atlas.CurrentPurchase }, 4)
                for _, tgt in ipairs(targets) do
                    local res = accept(tgt, "global Atlas.*Target")
                    if res then return res end
                end
            end
            local targets = dropNils({ r.ProgressionTarget, r.CurrentTarget, r.CurrentPurchase, r.Target }, 4)
            for _, tgt in ipairs(targets) do
                local res = accept(tgt, "global *Target")
                if res then return res end
            end
            if r.AutoProgUIScan == false then allowUI = false end
        end
    end

    -- 2. Neu memory chua co truc tiep target, doc label Next Item tren UI Atlas
    local uiNext = readNextItemLabel()
    if uiNext then
        targetSource = "ui: nhan 'Next item' cua Atlas"
        return uiNext
    end

    -- 3. Quet route trong memory de lay mon dau tien chua mua
    if settings and settings.toys and type(settings.toys.route) == "table" then
        local pList = collectPurchases(settings.toys.route, 0)
        if pList and #pList > 0 then
            local char = player.Character
            local data = getStatData()
            for _, p in ipairs(pList) do
                local pName = (type(p) == "table" and (p.Name or p.Item or p.Target or p.Gear)) or (type(p) == "string" and p)
                if pName then
                    local resolved = toItemName(pName)
                    if isRouteItem(resolved) and not ownsItem(resolved, "Gear", char, data) then
                        targetSource = "settings.toys.route (first not owned)"
                        return resolved
                    end
                end
            end
        end
    end

    -- quet UI: chi nhan dang "Target: <ten>" va ten phai khop dung 1 item
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
                                    local res = toItemNameExact(m)
                                        or toItemNameExact((m:gsub("[%s%d]+$", "")))
                                    if res then
                                        targetSource = "ui:" .. desc:GetFullName():sub(-60) .. " = '" .. txt:sub(1, 50) .. "'"
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

local lockedTarget = nil
local liveMisses = 0

local function checkIngredients(milestone, data, beeCount)
    if not milestone.Ingredients or #milestone.Ingredients == 0 then
        return nil, 0, nil, false, true
    end

    local firstFarmMat, firstFarmAmt, farmField = nil, 0, nil
    local firstUnfarmMat, firstUnfarmAmt = nil, 0
    local anyMissing = false

    for _, ing in ipairs(milestone.Ingredients) do
        local missingMat, missingAmt, targetField, isUnfarm = findMissingMaterial(ing.Item, ing.Amount, data, beeCount)
        if missingAmt and missingAmt > 0 then
            anyMissing = true
            if targetField then
                if not farmField then
                    firstFarmMat = missingMat
                    firstFarmAmt = missingAmt
                    farmField = targetField
                    break
                end
            elseif isUnfarm and not firstUnfarmMat then
                firstUnfarmMat = missingMat
                firstUnfarmAmt = missingAmt
            end
        end
    end

    if farmField then
        return firstFarmMat, firstFarmAmt, farmField, false, false
    elseif firstUnfarmMat then
        return firstUnfarmMat, firstUnfarmAmt, nil, true, false
    elseif not anyMissing then
        return nil, 0, nil, false, true
    else
        return nil, 0, nil, false, false
    end
end

local function pickNextTarget(data, beeCount)
    local char = player.Character

    local liveTarget = getLiveTarget()
    if liveTarget then
        liveMisses = 0
    else
        liveMisses = liveMisses + 1
        if liveMisses >= 3 then lockedTarget = nil end
    end
    if liveTarget then
        local canonicalLive = toItemName(liveTarget) or liveTarget
        if canonicalLive and isRouteItem(canonicalLive) then
            lockedTarget = canonicalLive
        end
    end

    local firstPendingUnfarm = nil

    if lockedTarget then
        if ownsItem(lockedTarget, "Gear", char, data) then
            lockedTarget = nil
        else
            local matchedMilestone = nil
            local cTarget = lockedTarget:gsub("[%s%-_']", ""):lower()
            for _, milestone in ipairs(DEFAULT_ROUTE) do
                local cMilestone = milestone.Name:gsub("[%s%-_']", ""):lower()
                if cTarget == cMilestone then
                    matchedMilestone = milestone
                    break
                end
            end

            if matchedMilestone then
                local mat, amt, field, isUnfarm, isReady = checkIngredients(matchedMilestone, data, beeCount)
                if field then
                    return matchedMilestone.Name, mat, amt, field, false
                elseif isUnfarm then
                    local progField = getRouteField(beeCount)
                    return matchedMilestone.Name, mat, amt, progField, true
                else
                    local progField = getRouteField(beeCount)
                    return matchedMilestone.Name, nil, 0, progField, false
                end
            else
                local progField = getRouteField(beeCount)
                return lockedTarget, nil, 0, progField, false
            end
        end
    end

    local activeRoute = getRoute()
    for _, milestone in ipairs(activeRoute) do
        local owned = ownsItem(milestone.Name, milestone.Type, char, data)
        if not owned and beeCount >= milestone.Bees then
            local mat, amt, field, isUnfarm, isReady = checkIngredients(milestone, data, beeCount)
            if field then
                return milestone.Name, mat, amt, field, false
            elseif isReady then
                local progField = getRouteField(beeCount)
                return milestone.Name, nil, 0, progField, false
            elseif isUnfarm then
                if not firstPendingUnfarm then
                    firstPendingUnfarm = {
                        Target = milestone.Name,
                        Mat = mat,
                        Amt = amt
                    }
                end
            else
                local progField = getRouteField(beeCount)
                return milestone.Name, mat, amt, progField, false
            end
        end
    end

    if firstPendingUnfarm then
        local progField = getRouteField(beeCount)
        return firstPendingUnfarm.Target, firstPendingUnfarm.Mat, firstPendingUnfarm.Amt, progField, true
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
hudLabel.Name = "AutoProg_HUD"
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

local function describeIngredients(targetItem, data, beeCount)
    if not targetItem or targetItem == "None" then return "None" end
    local matched = nil
    local cTarget = targetItem:gsub("[%s%-_']", ""):lower()
    for _, m in ipairs(DEFAULT_ROUTE) do
        local cm = m.Name:gsub("[%s%-_']", ""):lower()
        if cm == cTarget then
            matched = m
            break
        end
    end

    if not matched then
        local activeRoute = routeCache or getRoute()
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
        local invCount = countItem(ing.Item, data)
        local isMissing = invCount < ing.Amount
        local isUnfarm = false
        if isMissing then
            local _, _, tf, unf = findMissingMaterial(ing.Item, ing.Amount, data, beeCount or 35)
            if not tf and unf then isUnfarm = true end
        end
        local status = not isMissing and "[OK]" or (isUnfarm and "[NEED - MANUAL]" or "[NEED]")
        local line = string.format("• **%s**: %d/%d (%s)", ing.Item, invCount, ing.Amount, status)
        if isMissing and RECIPES[ing.Item] then
            local def = ing.Amount - invCount
            local subParts = {}
            for _, sub in ipairs(RECIPES[ing.Item]) do
                local totalFruit = def * sub.Amount
                local curFruit = countItem(sub.Item, data)
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

local lastWebhookTime = 0
local lastWebhookTarget = nil
local lastWebhookField = nil
local lastWebhookMat = nil

local function sendProgressWebhook(beeCount, targetStr, fieldStr, routeStr, data, needStr, isUnfarmable, neededMat)
    local roots = dropNils({ getgenv and getgenv(), _G, shared }, 3)
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
    local stateChanged = (targetStr ~= lastWebhookTarget or fieldStr ~= lastWebhookField or neededMat ~= lastWebhookMat)
    if not stateChanged and (now - lastWebhookTime < interval) then
        return
    end
    if stateChanged and (now - lastWebhookTime < 15) then
        return
    end

    local httpRequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not httpRequest then return end

    lastWebhookTime = now
    lastWebhookTarget = targetStr
    lastWebhookField = fieldStr
    lastWebhookMat = neededMat

    local needIngredients = describeIngredients(targetStr, data, beeCount)
    local noteText = isUnfarmable and string.format("\n⚠️ **Note:** Missing unfarmable item `%s` (cannot farm in fields).", tostring(needStr or targetStr or "Item")) or ""

    local bodyText = string.format(
        "**Bees :** %d\n" ..
        "**Current Target:** %s%s\n" ..
        "**Need:**\n%s\n" ..
        "**Field:** %s\n" ..
        "**Route:** %s",
        tonumber(beeCount) or 0,
        tostring(targetStr),
        tostring(noteText),
        tostring(needIngredients),
        tostring(fieldStr),
        tostring(routeStr)
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
        local v2Url = webhookUrl .. (webhookUrl:find("?", 1, true) and "&with_components=true" or "?with_components=true")
        local reqOk, res = pcall(function()
            return httpRequest({
                Url = v2Url,
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

local function printDebug()
    local data = getStatData()
    local beeCount = getBeeCount(data)
    local liveTarget = getLiveTarget()
    local activeRoute = getRoute()
    print("========== [Auto Prog Debug] ==========")
    print("Bee Count:", beeCount)
    print("Atlas Live Target:", tostring(liveTarget))
    print("Active Latched Target:", tostring(lockedTarget))
    print("Atlas Settings Found:", tostring(findAtlasSettings() ~= nil))
    print("Live Target Source:", tostring(targetSource))
    print("Atlas UI 'Next item' raw:", tostring(nextItemCache.raw), "-> resolved:", tostring(nextItemCache.val))
    print("Route Source:", tostring(routeSourceName))
    print("Pointer File:", tostring(configState.pointer), "| via pointer:", tostring(configState.viaPointer), "| last read problem:", tostring(configState.lastFail))
    print("Atlas Folders:", table.concat(configState.roots or {}, ", "), "| files scanned:", tostring(configState.fileCount))
    print("Active Config File:", tostring(configState.path), "| route @", tostring(configState.routePath))
    for _, why in ipairs(configState.reasons or {}) do print("  why: " .. why) end
    print("Config candidates with route:", #(configState.candidates or {}), "| ambiguous:", tostring(configState.ambiguous))
    for i, c in ipairs(configState.candidates or {}) do
        if i > 5 then break end
        print(string.format("  cand[%d] %s score=%.1f steps=%d", tonumber(i) or 0, tostring(c.path), tonumber(c.score) or 0, tonumber(c.routeN) or 0))
    end
    print("Route Source Items Count:", #activeRoute)
    for i = 1, math.min(#activeRoute, 15) do
        local m = activeRoute[i]
        print(string.format("  route[%d] = %s (bees>=%s)", tonumber(i) or 0, tostring(m.Name), tostring(m.Bees)))
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
    local checkList = { "Hiking Boots", "Beekeeper's Boots", "Looker Guard", "Brave Guard", "Diamond Mask", "Blue Clay Planter", "Red Clay Planter", "Tacky Planter", "Candy Planter", "Petal Planter" }
    for _, itm in ipairs(checkList) do
        print("  " .. itm .. ":", ownsItem(itm, "Gear", player.Character, data))
    end
    print("Material Counts:")
    local matList = { "Glitter", "Oil", "Enzymes", "Glue", "Blue Extract", "Red Extract", "Stinger", "Star Jelly", "Moon Charm" }
    for _, m in ipairs(matList) do
        print("  " .. m .. ":", countItem(m, data))
    end
    local targetItem, neededMat, neededAmt, field, isUnfarmable = pickNextTarget(data, beeCount)
    print("Evaluation Result:")
    print("  Target:", tostring(targetItem))
    print("  Need Mat:", tostring(neededMat), "(" .. tostring(neededAmt) .. ")")
    print("  Unfarmable:", tostring(isUnfarmable))
    print("  Target Field:", tostring(field))
    print("========================================")
end


local STAGE1_CONFIG_RAW = [===[{"hive":{"beetypes":false,"bee":false,"mutas3":false,"stoprjgifted":false,"amount":50,"rjbeetypes":false,"feedtype":"Bitterberry","neonberry":false,"rjrarity":false},"misc":{"mobiletoggle":true,"console":false,"bqbuyconf":false,"followfieldblacklist":false,"anonymous":false,"follow":false,"rolldouble":false,"autorejoin2":false,"bqbuy":false,"bqdel2":false,"realpot":false,"farmmultiplefields":false,"dapperslots":5,"custompatterns":false,"bqdelconf":false},"combat":{"mondochicktime":15,"killmondochick":true,"crabmethod":"Tween","killkingbeetle":true,"killcrab":false,"babylove":true,"donatevials":false,"wlstingers":false,"killScorpion":false,"killtunnelbear":false,"craboil":false,"giftedvicious":false,"killWerewolf":false,"snail":false,"windymax":25,"viciousmin":1,"killMantis":false,"demonmask":false,"lootmondo":true,"killRhinoBeetle":false,"killSpider":false,"windymin":1,"killcommando":false,"viciousmax":6,"stingers":false,"starsaw":false,"killwindy":false,"commandomethod":"Walk","avoidmobs":true,"commandoshell":true,"killvicious":true,"killAphid":true,"commandohelp":false,"dmwhitelist":false,"mondopreptime":20,"mondoprep":false,"killLadybug":false,"wlstarsaw":false},"dispensers":{"coconut":false,"blueberry":false,"royaljelly":false,"treat":false,"strawberry":false,"robopass":false,"glue":false,"honey":false,"antpass":true},"autoquest":{"planters":true,"feedbees":true,"windshrine":true,"rileybee":false,"ragetokens":true,"gummybear":false,"buckobee":false,"treats":true,"enabled":true,"memorymatch":true,"onett":true,"beebear":false,"blackbear2":false,"pollen":true,"sciencebear":true,"puffshrooms":true,"oldtool":false,"goomethod":"Gumdrops","levelbees":true,"sharebeans":true,"pandabear":true,"bestwhitefield":"Sunflower Field","bestredfield":"Mushroom Field","toys":true,"claim2":{"Mother Bear":true,"Polar Bear":true,"Panda Bear":true,"Science Bear":true},"tools":true,"brownbear":false,"ants":true,"blackbear":false,"dapperbear":false,"dupedtokens":true,"mobs":true,"blooms":true,"rj":true,"honeybee":false,"allowedplanters":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true},"craft":true,"goo":true,"xmas":false,"bestbluefield":"Blue Flower Field","stickbug":false,"motherbear":true,"spiritbear":true,"rjbl":false,"polarbear":true},"face":{"balloons":false,"blooms":false,"bubbles":false,"refresh":false,"shiftlock":false,"gballoons":false,"gbubbles":false,"fires":false,"sldirection":"South","center":false,"method":"Shift Lock"},"convert":{"standInPreciseAt":75,"convertHiveBalloon":true,"instantType":false,"convertHoneyAt":100,"coconutAt":85,"convertHoney":true,"resetWhenConverting":false,"convert6xBubbleBloat":false,"festivegift":false,"autoHoneyMask":false,"alwaysConvertBalloon":false,"timeToWait":15,"coconut":false,"waitBeforeConverting":false,"standInPrecise":true,"useEnzymesBalloon":false,"convertField":false,"convertHiveBalloonAt":5,"defaultMask":"Diamond Mask","instantToggle":false},"boosters":{"min":1,"wanted":1,"required":false,"enabled2":false,"allowed":false,"fieldsblacklist":false},"vars":{"walkspeedenabled":true,"movement":"Tween","cannon":false,"tweenspeed":6,"walkspeed":48,"jumpshortcuts":false,"walkspeed2":1.5,"walkdynamic":false},"sprouts":{"enabled":true,"plant":false,"plantday":false,"collect":true,"amount":false,"fieldsblacklist":false,"rarity3":false,"left":0,"plantnight":false},"stickbug":{"enabled":false,"loot":false,"totem":true,"maintain":false,"circle":true,"tickets":false,"spawn":false},"amulet":{"ant":false,"rbc3":false,"kb3":"Bronze","rbc4":false,"ant4":false,"sb3":false,"kb2":false,"star3":false,"sb4":false,"sb":false,"snail4":false,"rbc":false,"sb2":false,"moon4":false,"kb4":{"P2":[],"P3":[],"P1":[]},"rbc2":false,"ant2":false,"snail":false,"ant3":false,"snail2":false,"star4":false,"kb":false,"snail3":false},"memorymatch":{"night":false,"basic":false,"mega":false,"extreme":false,"blacklist":false},"rbc":{"passcooldown":0,"rerollmin":10,"upgrades":false,"mask":false,"rerollquests":false,"redtool":"Dark Scythe","bluemask":"Diamond Mask","cogconvert":false,"cogupgrades":true,"rerollupgrades":false,"materialsenabled":false,"buypass":false,"whitemask":"Gummy Mask","trackmobs":false,"preset":"Blue","disableroundend":false,"maskround":5,"homepage":false,"stoproundend":false,"whitetool":"Gummyballer","highestcogmax":9,"maxround":15,"highestcog":false,"precise":false,"rerollbees":false,"bestwhitefield":"Sunflower Field","bestredfield":"Mushroom Field","bestbluefield":"Blue Flower Field","buydrives":{"Glitched":true,"Red":true,"Blue":true,"White":true},"rerollbeesmax":2,"tool":false,"goldcogmowers":true,"homepagemin":1,"precisemin":5,"enabled":false,"toolround":4,"upgradesenabled":false,"materials":false,"rerollupgmax":2,"goomethod":"Gumdrops","redmask":"Demon Mask","usedrives":{"Glitched":true,"Red":true,"Blue":true,"White":true},"bluetool":"Tide Popper"},"beesmas":[],"detected":[],"antilag":{"stations":true,"precise":true,"balloons":true,"flowers":false,"norender":false,"bssui":false,"dupedtokens":true,"tokens":true,"main":true,"textures":true,"bees":true,"decorations":true,"particles":true,"players":true},"toys":{"windshrine":false,"conversions":2,"stickerprinter":false,"stackselect":false,"enabled":true,"sproutsummoner":false,"meteor":false,"route":[{"Data":["38217","BeesBuzz123","BopMaster","Connoisseur","Crawlers","777","Nectar","Roof","Wax"],"Type":"Codes"},{"Bees":15,"Type":"Codes","Data":"ClubBean"},{"Bees":35,"Type":"Codes","Data":"ThreeBeeVee"},{"Data":["Dandelion Field","Bamboo Field","Pineapple Patch","Pine Tree Forest"],"Type":"Field"},{"Data":["Tabby","Festive","Gummy","Vicious","Puppy"],"Type":"Event Bee"},{"Type":"Purchase","Data":["Backpack","Magnet","Canister","Vacuum","Belt Pocket","Compressor","Super-Scooper","Helmet","Port-O-Hive","Electro-Magnet","Honey Dipper","Propeller Hat","Looker Guard","Brave Guard","Hiking Boots","Belt Bag","Bubble Wand","Basic Sprinkler","PlasticPlanter","Beekeeper's Mask","Beekeeper's Boots","Mondo Belt Bag","Blue Port-O-Hive","Silver Soakers","Elite Blue Guard","Elite Red Guard","CandyPlanter","Glider","Porcelain Dipper","Porcelain Port-O-Hive","Blue ClayPlanter","Red ClayPlanter","Bubble Mask","Cobalt Guard","Golden Gushers","TackyPlanter","Diamond Mask","Honeycomb Belt","Crimson Guard","Diamond Drenchers","Coconut Canister","PesticidePlanter","The Supreme Saturator","Gummy Boots","PetalPlanter"],"Craft":true}],"hiddenstickers":true,"discardselect":false,"stickerstacker":false,"intwhitelist":false,"wealthclock":true,"prog":true,"farmwinds":false,"shrineamount":1,"interrupt":true,"stackmethod":"Tickets","materials2":false,"printereggs":false,"discardstickers":false,"windsblacklist":false,"materials":false,"nectarcondenser":false,"honeystorm":false,"nectars":false,"progblender":true,"shrineitem":""},"ant":{"enabled":false,"antpass":false},"planters":{"manual":{"farmfield":false,"planter3":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4},"planter2":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4},"planter1":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4}},"method":"Nectar","cycles":{"cycle2":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle4":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle1":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"started":false,"lastcycle":false,"cycle3":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle5":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2}},"rewards":{"enabled":true,"swirledwax":true,"causticwaxp":false,"smoothie":false,"causticwax":false,"swirledwaxp":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true}},"enabled":true,"nectar":{"satisfying":true,"ignoresmoking":false,"invigoratinglastfield":"","motivating":true,"motivatingp":2,"comfortingp":1,"invigorating":false,"comforting":true,"harvestat":100,"invigoratingmin2":10,"satisfyinglastfield":"","comfortinglastfield":"","harvestaftertime":true,"timetoharvest":2,"farmfield":false,"harvestatpercentage":false,"blacklistedfields":false,"ignorefielddeg":true,"satisfyingmin2":18,"preset":"Custom","motivatingmin2":18,"invigoratingp":5,"refreshing":true,"refreshinglastfield":"","satisfyingp":3,"refreshingmin2":15,"motivatinglastfield":"","refreshingp":4,"comfortingmin2":18,"allowedplanters":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true}}},"webhook":[],"autofarm":{"patternblacklist":false,"smileytime":4,"farmshowers":true,"badgebl":false,"farmfires":true,"farmbadges":false,"guidingfieldblacklist":false,"enabled":true,"autosprinkler":true,"farmcoconuts":true,"farmprecisemark":true,"farmblooms":true,"patternstart":"Center","scorchingscore":0,"farmfireflies":true,"badgep":"Lowest Pollen Needed","autopopstar":true,"badgesclaim":true,"farmprecise":true,"farmtriangulate":true,"autoscorchingstar":true,"farmdupedtokens":true,"pattern":"CornerXSnake","dupedtokens":false,"prioritytokens":false,"farmpetals":true,"farmfuzzbombs":true,"farmcombococonuts":true,"farmleaves":true,"farmbubbles":true,"autogummystar":true,"combofield":false,"ignorehoneytokens":false,"field3":"None","farmballoons2":false,"sprinklerpos":"Center","farmposition":false,"farmmarks":true,"farmpuppyball":true,"autoxflame":false,"field1":"Pine Tree Forest","field2":"None","farmmeteorshowers":true,"farmclouds":true,"fieldinterval":10,"trackprecise":false,"autoguidingstar":false,"comboamount":0,"farmposenabled":false,"patternenabled":false,"autodig":true,"precisemin":30},"puffshrooms":{"enabled":true,"rarity":"Common","max":15,"maintain":false,"highlvlpriority":false,"mintime":30,"blacklistedfields":false,"min":1,"priorityfields":false}}]===]

local STAGE2_CONFIG_RAW = [===[{"hive":{"beetypes":false,"bee":false,"mutas3":false,"stoprjgifted":false,"amount":50,"rjbeetypes":false,"feedtype":"Bitterberry","neonberry":false,"rjrarity":false},"misc":{"mobiletoggle":true,"console":false,"bqbuyconf":false,"followfieldblacklist":false,"anonymous":false,"follow":false,"rolldouble":false,"autorejoin2":false,"bqbuy":false,"bqdel2":false,"realpot":false,"farmmultiplefields":false,"dapperslots":5,"custompatterns":false,"bqdelconf":false},"combat":{"mondochicktime":15,"killmondochick":true,"crabmethod":"Tween","killkingbeetle":true,"killcrab":false,"babylove":true,"donatevials":false,"wlstingers":false,"killScorpion":false,"killtunnelbear":true,"craboil":false,"giftedvicious":false,"killWerewolf":false,"snail":false,"windymax":25,"viciousmin":1,"killMantis":false,"demonmask":false,"lootmondo":true,"killRhinoBeetle":false,"killSpider":false,"windymin":1,"killcommando":false,"viciousmax":6,"stingers":false,"starsaw":false,"killwindy":false,"commandomethod":"Walk","avoidmobs":true,"commandoshell":true,"killvicious":true,"killAphid":true,"commandohelp":false,"dmwhitelist":false,"mondopreptime":20,"mondoprep":false,"killLadybug":false,"wlstarsaw":false},"dispensers":{"coconut":false,"blueberry":false,"royaljelly":false,"treat":false,"strawberry":false,"robopass":false,"glue":false,"honey":false,"antpass":true},"autoquest":{"planters":true,"feedbees":true,"windshrine":true,"rileybee":false,"ragetokens":true,"gummybear":false,"buckobee":false,"treats":true,"enabled":true,"memorymatch":true,"onett":true,"beebear":false,"blackbear2":false,"pollen":true,"sciencebear":true,"puffshrooms":true,"oldtool":false,"goomethod":"Gumdrops","levelbees":true,"sharebeans":true,"pandabear":true,"bestwhitefield":"Sunflower Field","bestredfield":"Mushroom Field","toys":true,"claim2":{"Mother Bear":true,"Polar Bear":true,"Panda Bear":true,"Science Bear":true},"tools":true,"brownbear":false,"ants":true,"blackbear":false,"dapperbear":false,"dupedtokens":true,"mobs":true,"blooms":true,"rj":true,"honeybee":false,"allowedplanters":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true},"craft":true,"goo":true,"xmas":false,"bestbluefield":"Blue Flower Field","stickbug":false,"motherbear":true,"spiritbear":true,"rjbl":false,"polarbear":true},"face":{"balloons":false,"blooms":false,"bubbles":false,"refresh":false,"shiftlock":false,"gballoons":false,"gbubbles":false,"fires":false,"sldirection":"South","center":false,"method":"Shift Lock"},"convert":{"standInPreciseAt":75,"convertHiveBalloon":true,"instantType":false,"convertHoneyAt":100,"coconutAt":85,"convertHoney":true,"resetWhenConverting":false,"convert6xBubbleBloat":false,"festivegift":false,"autoHoneyMask":false,"alwaysConvertBalloon":false,"timeToWait":15,"coconut":false,"waitBeforeConverting":false,"standInPrecise":true,"useEnzymesBalloon":false,"convertField":false,"convertHiveBalloonAt":5,"defaultMask":"Diamond Mask","instantToggle":false},"boosters":{"min":1,"wanted":1,"required":false,"enabled2":false,"allowed":false,"fieldsblacklist":false},"vars":{"walkspeedenabled":true,"movement":"Tween","cannon":false,"tweenspeed":6,"walkspeed":48,"jumpshortcuts":false,"walkspeed2":1.5,"walkdynamic":false},"sprouts":{"enabled":true,"plant":false,"plantday":false,"collect":true,"amount":false,"fieldsblacklist":false,"rarity3":false,"left":0,"plantnight":false},"stickbug":{"enabled":false,"loot":false,"totem":true,"maintain":false,"circle":true,"tickets":false,"spawn":false},"amulet":{"ant":false,"rbc3":false,"kb3":"Bronze","rbc4":false,"ant4":false,"sb3":false,"kb2":false,"star3":false,"sb4":false,"sb":false,"snail4":false,"rbc":false,"sb2":false,"moon4":false,"kb4":{"P2":[],"P3":[],"P1":[]},"rbc2":false,"ant2":false,"snail":false,"ant3":false,"snail2":false,"star4":false,"kb":false,"snail3":false},"memorymatch":{"night":false,"basic":false,"mega":false,"extreme":false,"blacklist":false},"rbc":{"passcooldown":0,"rerollmin":10,"upgrades":false,"mask":false,"rerollquests":false,"redtool":"Dark Scythe","bluemask":"Diamond Mask","cogconvert":false,"cogupgrades":true,"rerollupgrades":false,"materialsenabled":false,"buypass":false,"whitemask":"Gummy Mask","trackmobs":false,"preset":"Blue","disableroundend":false,"maskround":5,"homepage":false,"stoproundend":false,"whitetool":"Gummyballer","highestcogmax":9,"maxround":15,"highestcog":false,"precise":false,"rerollbees":false,"bestwhitefield":"Sunflower Field","bestredfield":"Mushroom Field","bestbluefield":"Blue Flower Field","buydrives":{"Glitched":true,"Red":true,"Blue":true,"White":true},"rerollbeesmax":2,"tool":false,"goldcogmowers":true,"homepagemin":1,"precisemin":5,"enabled":false,"toolround":4,"upgradesenabled":false,"materials":false,"rerollupgmax":2,"goomethod":"Gumdrops","redmask":"Demon Mask","usedrives":{"Glitched":true,"Red":true,"Blue":true,"White":true},"bluetool":"Tide Popper"},"beesmas":[],"detected":[],"antilag":{"stations":true,"precise":true,"balloons":true,"flowers":false,"norender":false,"bssui":false,"dupedtokens":true,"tokens":true,"main":true,"textures":true,"bees":true,"decorations":true,"particles":true,"players":true},"toys":{"windshrine":false,"conversions":2,"stickerprinter":false,"stackselect":false,"enabled":true,"sproutsummoner":false,"meteor":false,"route":[{"Data":["38217","BeesBuzz123","BopMaster","Connoisseur","Crawlers","777","Nectar","Roof","Wax"],"Type":"Codes"},{"Bees":15,"Type":"Codes","Data":"ClubBean"},{"Bees":35,"Type":"Codes","Data":"ThreeBeeVee"},{"Data":["Dandelion Field","Bamboo Field","Pineapple Patch","Pine Tree Forest"],"Type":"Field"},{"Data":["Tabby","Festive","Gummy","Vicious","Puppy"],"Type":"Event Bee"},{"Type":"Purchase","Data":["Backpack","Magnet","Canister","Vacuum","Belt Pocket","Compressor","Super-Scooper","Helmet","Port-O-Hive","Electro-Magnet","Honey Dipper","Propeller Hat","Looker Guard","Brave Guard","Hiking Boots","Belt Bag","Bubble Wand","Basic Sprinkler","PlasticPlanter","Beekeeper's Mask","Beekeeper's Boots","Mondo Belt Bag","Blue Port-O-Hive","Silver Soakers","Elite Blue Guard","Elite Red Guard","CandyPlanter","Glider","Porcelain Dipper","Porcelain Port-O-Hive","Blue ClayPlanter","Red ClayPlanter","Bubble Mask","Cobalt Guard","Golden Gushers","TackyPlanter","Diamond Mask","Honeycomb Belt","Crimson Guard","Diamond Drenchers","Coconut Canister","PesticidePlanter","The Supreme Saturator","Gummy Boots","PetalPlanter"],"Craft":true}],"hiddenstickers":true,"discardselect":false,"stickerstacker":false,"intwhitelist":false,"wealthclock":true,"prog":true,"farmwinds":false,"shrineamount":1,"interrupt":true,"stackmethod":"Tickets","materials2":false,"printereggs":false,"discardstickers":false,"windsblacklist":false,"materials":false,"nectarcondenser":false,"honeystorm":false,"nectars":false,"progblender":true,"shrineitem":""},"ant":{"enabled":false,"antpass":false},"planters":{"manual":{"farmfield":false,"planter3":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4},"planter2":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4},"planter1":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4}},"method":"Nectar","cycles":{"cycle2":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle4":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle1":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"started":false,"lastcycle":false,"cycle3":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle5":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2}},"rewards":{"enabled":true,"swirledwax":true,"causticwaxp":false,"smoothie":false,"causticwax":false,"swirledwaxp":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true}},"enabled":true,"nectar":{"satisfying":true,"ignoresmoking":false,"invigoratinglastfield":"","motivating":true,"motivatingp":2,"comfortingp":1,"invigorating":false,"comforting":true,"harvestat":100,"invigoratingmin2":10,"satisfyinglastfield":"","comfortinglastfield":"","harvestaftertime":true,"timetoharvest":2,"farmfield":false,"harvestatpercentage":false,"blacklistedfields":false,"ignorefielddeg":true,"satisfyingmin2":18,"preset":"Custom","motivatingmin2":18,"invigoratingp":5,"refreshing":true,"refreshinglastfield":"","satisfyingp":3,"refreshingmin2":15,"motivatinglastfield":"","refreshingp":4,"comfortingmin2":18,"allowedplanters":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true}}},"webhook":[],"autofarm":{"patternblacklist":false,"smileytime":4,"farmshowers":true,"badgebl":false,"farmfires":true,"farmbadges":false,"guidingfieldblacklist":false,"enabled":true,"autosprinkler":true,"farmcoconuts":true,"farmprecisemark":true,"farmblooms":true,"patternstart":"Center","scorchingscore":0,"farmfireflies":true,"badgep":"Lowest Pollen Needed","autopopstar":true,"badgesclaim":true,"farmprecise":true,"farmtriangulate":true,"autoscorchingstar":true,"farmdupedtokens":true,"pattern":"CornerXSnake","dupedtokens":false,"prioritytokens":false,"farmpetals":true,"farmfuzzbombs":true,"farmcombococonuts":true,"farmleaves":true,"farmbubbles":true,"autogummystar":true,"combofield":false,"ignorehoneytokens":false,"field3":"None","farmballoons2":false,"sprinklerpos":"Center","farmposition":false,"farmmarks":true,"farmpuppyball":true,"autoxflame":false,"field1":"Pine Tree Forest","field2":"None","farmmeteorshowers":true,"farmclouds":true,"fieldinterval":10,"trackprecise":false,"autoguidingstar":false,"comboamount":0,"farmposenabled":false,"patternenabled":false,"autodig":true,"precisemin":30},"puffshrooms":{"enabled":true,"rarity":"Common","max":15,"maintain":false,"highlvlpriority":false,"mintime":30,"blacklistedfields":false,"min":1,"priorityfields":false}}]===]

local STAGE3_CONFIG_RAW = [===[{"hive":{"beetypes":false,"bee":false,"mutas3":false,"stoprjgifted":false,"amount":50,"rjbeetypes":false,"feedtype":"Bitterberry","neonberry":false,"rjrarity":false},"misc":{"mobiletoggle":true,"console":false,"bqbuyconf":false,"followfieldblacklist":false,"anonymous":false,"follow":false,"rolldouble":false,"autorejoin2":false,"bqbuy":false,"bqdel2":false,"realpot":false,"farmmultiplefields":false,"dapperslots":5,"custompatterns":false,"bqdelconf":false},"combat":{"mondochicktime":15,"killmondochick":true,"crabmethod":"Tween","killkingbeetle":true,"killcrab":true,"babylove":true,"donatevials":false,"wlstingers":false,"killScorpion":false,"killtunnelbear":true,"craboil":false,"giftedvicious":false,"killWerewolf":false,"snail":false,"windymax":25,"viciousmin":1,"killMantis":false,"demonmask":false,"lootmondo":true,"killRhinoBeetle":false,"killSpider":false,"windymin":1,"killcommando":false,"viciousmax":6,"stingers":false,"starsaw":false,"killwindy":false,"commandomethod":"Walk","avoidmobs":true,"commandoshell":true,"killvicious":true,"killAphid":true,"commandohelp":false,"dmwhitelist":false,"mondopreptime":20,"mondoprep":false,"killLadybug":false,"wlstarsaw":false},"dispensers":{"coconut":false,"blueberry":false,"royaljelly":false,"treat":false,"strawberry":false,"robopass":false,"glue":false,"honey":false,"antpass":true},"autoquest":{"planters":true,"feedbees":true,"windshrine":true,"rileybee":false,"ragetokens":true,"gummybear":false,"buckobee":false,"treats":true,"enabled":true,"memorymatch":true,"onett":true,"beebear":false,"blackbear2":false,"pollen":true,"sciencebear":true,"puffshrooms":true,"oldtool":false,"goomethod":"Gumdrops","levelbees":true,"sharebeans":true,"pandabear":true,"bestwhitefield":"Sunflower Field","bestredfield":"Mushroom Field","toys":true,"claim2":{"Mother Bear":true,"Polar Bear":true,"Panda Bear":true,"Science Bear":true},"tools":true,"brownbear":false,"ants":true,"blackbear":false,"dapperbear":false,"dupedtokens":true,"mobs":true,"blooms":true,"rj":true,"honeybee":false,"allowedplanters":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true},"craft":true,"goo":true,"xmas":false,"bestbluefield":"Blue Flower Field","stickbug":false,"motherbear":true,"spiritbear":true,"rjbl":false,"polarbear":true},"face":{"balloons":false,"blooms":false,"bubbles":false,"refresh":false,"shiftlock":false,"gballoons":false,"gbubbles":false,"fires":false,"sldirection":"South","center":false,"method":"Shift Lock"},"convert":{"standInPreciseAt":75,"convertHiveBalloon":true,"instantType":false,"convertHoneyAt":100,"coconutAt":85,"convertHoney":true,"resetWhenConverting":false,"convert6xBubbleBloat":false,"festivegift":false,"autoHoneyMask":false,"alwaysConvertBalloon":false,"timeToWait":15,"coconut":false,"waitBeforeConverting":false,"standInPrecise":true,"useEnzymesBalloon":false,"convertField":false,"convertHiveBalloonAt":5,"defaultMask":"Diamond Mask","instantToggle":false},"boosters":{"min":1,"wanted":1,"required":false,"enabled2":false,"allowed":false,"fieldsblacklist":false},"vars":{"walkspeedenabled":true,"movement":"Tween","cannon":false,"tweenspeed":6,"walkspeed":48,"jumpshortcuts":false,"walkspeed2":1.5,"walkdynamic":false},"sprouts":{"enabled":true,"plant":false,"plantday":false,"collect":true,"amount":false,"fieldsblacklist":false,"rarity3":false,"left":0,"plantnight":false},"stickbug":{"enabled":false,"loot":false,"totem":true,"maintain":false,"circle":true,"tickets":false,"spawn":false},"amulet":{"ant":false,"rbc3":false,"kb3":"Bronze","rbc4":false,"ant4":false,"sb3":false,"kb2":false,"star3":false,"sb4":false,"sb":false,"snail4":false,"rbc":false,"sb2":false,"moon4":false,"kb4":{"P2":[],"P3":[],"P1":[]},"rbc2":false,"ant2":false,"snail":false,"ant3":false,"snail2":false,"star4":false,"kb":false,"snail3":false},"memorymatch":{"night":false,"basic":false,"mega":false,"extreme":false,"blacklist":false},"rbc":{"passcooldown":0,"rerollmin":10,"upgrades":false,"mask":false,"rerollquests":false,"redtool":"Dark Scythe","bluemask":"Diamond Mask","cogconvert":false,"cogupgrades":true,"rerollupgrades":false,"materialsenabled":false,"buypass":false,"whitemask":"Gummy Mask","trackmobs":false,"preset":"Blue","disableroundend":false,"maskround":5,"homepage":false,"stoproundend":false,"whitetool":"Gummyballer","highestcogmax":9,"maxround":15,"highestcog":false,"precise":false,"rerollbees":false,"bestwhitefield":"Sunflower Field","bestredfield":"Mushroom Field","bestbluefield":"Blue Flower Field","buydrives":{"Glitched":true,"Red":true,"Blue":true,"White":true},"rerollbeesmax":2,"tool":false,"goldcogmowers":true,"homepagemin":1,"precisemin":5,"enabled":false,"toolround":4,"upgradesenabled":false,"materials":false,"rerollupgmax":2,"goomethod":"Gumdrops","redmask":"Demon Mask","usedrives":{"Glitched":true,"Red":true,"Blue":true,"White":true},"bluetool":"Tide Popper"},"beesmas":[],"detected":[],"antilag":{"stations":true,"precise":true,"balloons":true,"flowers":false,"norender":false,"bssui":false,"dupedtokens":true,"tokens":true,"main":true,"textures":true,"bees":true,"decorations":true,"particles":true,"players":true},"toys":{"windshrine":false,"conversions":2,"stickerprinter":false,"stackselect":false,"enabled":true,"sproutsummoner":false,"meteor":false,"route":[{"Data":["38217","BeesBuzz123","BopMaster","Connoisseur","Crawlers","777","Nectar","Roof","Wax"],"Type":"Codes"},{"Bees":15,"Type":"Codes","Data":"ClubBean"},{"Bees":35,"Type":"Codes","Data":"ThreeBeeVee"},{"Data":["Dandelion Field","Bamboo Field","Pineapple Patch","Pine Tree Forest"],"Type":"Field"},{"Data":["Tabby","Festive","Gummy","Vicious","Puppy"],"Type":"Event Bee"},{"Type":"Purchase","Data":["Backpack","Magnet","Canister","Vacuum","Belt Pocket","Compressor","Super-Scooper","Helmet","Port-O-Hive","Electro-Magnet","Honey Dipper","Propeller Hat","Looker Guard","Brave Guard","Hiking Boots","Belt Bag","Bubble Wand","Basic Sprinkler","PlasticPlanter","Beekeeper's Mask","Beekeeper's Boots","Mondo Belt Bag","Blue Port-O-Hive","Silver Soakers","Elite Blue Guard","Elite Red Guard","CandyPlanter","Glider","Porcelain Dipper","Porcelain Port-O-Hive","Blue ClayPlanter","Red ClayPlanter","Bubble Mask","Cobalt Guard","Golden Gushers","TackyPlanter","Diamond Mask","Honeycomb Belt","Crimson Guard","Diamond Drenchers","Coconut Canister","PesticidePlanter","The Supreme Saturator","Gummy Boots","PetalPlanter"],"Craft":true}],"hiddenstickers":true,"discardselect":false,"stickerstacker":false,"intwhitelist":false,"wealthclock":true,"prog":true,"farmwinds":false,"shrineamount":1,"interrupt":true,"stackmethod":"Tickets","materials2":false,"printereggs":false,"discardstickers":false,"windsblacklist":false,"materials":false,"nectarcondenser":false,"honeystorm":false,"nectars":false,"progblender":true,"shrineitem":""},"ant":{"enabled":false,"antpass":false},"planters":{"manual":{"farmfield":false,"planter3":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4},"planter2":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4},"planter1":{"harvestatpercentage":true,"plant":false,"ignoresmoking":false,"lastfield":false,"field2":"None","field1":"Dandelion Field","harvest":false,"harvestat":100,"planter":"Plastic Planter","field4":"None","field3":"None","harvestaftertime":false,"timetoharvest":4}},"method":"Nectar","cycles":{"cycle2":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle4":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle1":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"started":false,"lastcycle":false,"cycle3":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2},"cycle5":{"planter2":{"planter":"None","field":"Dandelion Field"},"planter1":{"planter":"None","field":"Dandelion Field"},"harvestat":100,"ignoresmoking":false,"harvestatpercentage":true,"planter3":{"planter":"None","field":"Dandelion Field"},"harvestaftertime":false,"timetoharvest":2}},"rewards":{"enabled":true,"swirledwax":true,"causticwaxp":false,"smoothie":false,"causticwax":false,"swirledwaxp":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true}},"enabled":true,"nectar":{"satisfying":true,"ignoresmoking":false,"invigoratinglastfield":"","motivating":true,"motivatingp":2,"comfortingp":1,"invigorating":false,"comforting":true,"harvestat":100,"invigoratingmin2":10,"satisfyinglastfield":"","comfortinglastfield":"","harvestaftertime":true,"timetoharvest":2,"farmfield":false,"harvestatpercentage":false,"blacklistedfields":false,"ignorefielddeg":true,"satisfyingmin2":18,"preset":"Custom","motivatingmin2":18,"invigoratingp":5,"refreshing":true,"refreshinglastfield":"","satisfyingp":3,"refreshingmin2":15,"motivatinglastfield":"","refreshingp":4,"comfortingmin2":18,"allowedplanters":{"Tacky Planter":true,"Candy Planter":true,"Blue Clay Planter":true,"Red Clay Planter":true,"Plastic Planter":true}}},"webhook":[],"autofarm":{"patternblacklist":false,"smileytime":4,"farmshowers":true,"badgebl":false,"farmfires":true,"farmbadges":false,"guidingfieldblacklist":false,"enabled":true,"autosprinkler":true,"farmcoconuts":true,"farmprecisemark":true,"farmblooms":true,"patternstart":"Center","scorchingscore":0,"farmfireflies":true,"badgep":"Lowest Pollen Needed","autopopstar":true,"badgesclaim":true,"farmprecise":true,"farmtriangulate":true,"autoscorchingstar":true,"farmdupedtokens":true,"pattern":"CornerXSnake","dupedtokens":false,"prioritytokens":false,"farmpetals":true,"farmfuzzbombs":true,"farmcombococonuts":true,"farmleaves":true,"farmbubbles":true,"autogummystar":true,"combofield":false,"ignorehoneytokens":false,"field3":"None","farmballoons2":false,"sprinklerpos":"Center","farmposition":false,"farmmarks":true,"farmpuppyball":true,"autoxflame":false,"field1":"Pine Tree Forest","field2":"None","farmmeteorshowers":true,"farmclouds":true,"fieldinterval":10,"trackprecise":false,"autoguidingstar":false,"comboamount":0,"farmposenabled":false,"patternenabled":false,"autodig":true,"precisemin":30},"puffshrooms":{"enabled":true,"rarity":"Common","max":15,"maintain":false,"highlvlpriority":false,"mintime":30,"blacklistedfields":false,"min":1,"priorityfields":false}}]===]

local CONFIG_STAGES = {
    {
        Stage = 1,
        Name = "Stage 1 (King Beetle)",
        FileName = "Stage1_KingBeetle.json",
        Raw = STAGE1_CONFIG_RAW,
        MinBees = 20,
        MinLevel = 7,
    },
    {
        Stage = 2,
        Name = "Stage 2 (Tunnel Bear)",
        FileName = "Stage2_TunnelBear.json",
        Raw = STAGE2_CONFIG_RAW,
        MinBees = 28,
        MinLevel = 9,
    },
    {
        Stage = 3,
        Name = "Stage 3 (Coconut Crab)",
        FileName = "Stage3_CoconutCrab.json",
        Raw = STAGE3_CONFIG_RAW,
        MinBees = 35,
        MinLevel = 10,
    }
}

local currentStage = nil
local lastStageSwitch = 0
local pendingStage = nil
local pendingStageTime = 0

local function getHiveStats(data)
    local beeCount = 0
    local minLevel = 25
    local foundAny = false

    if data and type(data.Honeycomb) == "table" then
        for col = 1, 5 do
            local colTable = data.Honeycomb["x" .. col]
            if type(colTable) == "table" then
                for row = 1, 10 do
                    local bee = colTable["y" .. row]
                    if type(bee) == "table" and bee.Type and bee.Type ~= "" and bee.Type ~= "Empty" then
                        beeCount = beeCount + 1
                        local lvl = tonumber(bee.Lvl) or 1
                        if lvl < minLevel then minLevel = lvl end
                        foundAny = true
                    end
                end
            end
        end
    end

    if not foundAny or beeCount == 0 then
        local honeycombs = workspace:FindFirstChild("Honeycombs")
        local hVal = player:FindFirstChild("Honeycomb") and player.Honeycomb.Value
        local hive = (typeof(hVal) == "Instance" and hVal) or (honeycombs and honeycombs:FindFirstChild(tostring(hVal)))
        if not hive and honeycombs then
            for _, h in ipairs(honeycombs:GetChildren()) do
                local o = h:FindFirstChild("Owner")
                if o and (o.Value == player or o.Value == player.Name or tostring(o.Value) == player.Name or (player.Character and o.Value == player.Character)) then
                    hive = h
                    break
                end
            end
        end
        if hive and hive:FindFirstChild("Cells") then
            local pCount = 0
            local pMin = 25
            local pFound = false
            for _, cell in ipairs(hive.Cells:GetChildren()) do
                local ct = cell:FindFirstChild("CellType") or cell:FindFirstChild("Type")
                if ct and ct.Value ~= "" and ct.Value ~= "Empty" then
                    pCount = pCount + 1
                    local lVal = cell:FindFirstChild("CellLevel") or cell:FindFirstChild("Level") or cell:FindFirstChild("Lvl")
                    local lvl = lVal and tonumber(lVal.Value) or 1
                    if lvl < pMin then pMin = lvl end
                    pFound = true
                end
            end
            if pFound and pCount > 0 then
                beeCount = pCount
                minLevel = pMin
                foundAny = true
            end
        end
    end

    if not foundAny then
        minLevel = 1
        beeCount = getBeeCount(data)
    end

    return beeCount, minLevel
end

local function pickStage(beeCount, minLevel)
    for i = #CONFIG_STAGES, 1, -1 do
        local s = CONFIG_STAGES[i]
        if beeCount >= s.MinBees and minLevel >= s.MinLevel then
            return s.Stage, s
        end
    end
    return nil, nil
end

local function writeStageFiles()
    if not writefile then return end
    local roots = discoverAtlasRoots()
    local targetDir = roots[1] or "atlas"
    if makefolder and not fsIsFolder(targetDir) then
        pcall(makefolder, targetDir)
    end
    for _, s in ipairs(CONFIG_STAGES) do
        local path = targetDir .. "/" .. s.FileName
        if not fsIsFile(path) then
            pcall(writefile, path, s.Raw)
        end
        if not fsIsFile(s.FileName) then
            pcall(writefile, s.FileName, s.Raw)
        end
    end
end

local function applyStagePreset(stageInfo)
    if not stageInfo then return false end
    local fileName = stageInfo.FileName
    local raw = stageInfo.Raw

    if writefile then
        local roots = discoverAtlasRoots()
        for _, r in ipairs(roots) do
            pcall(writefile, r .. "/" .. fileName, raw)
        end
        pcall(writefile, fileName, raw)
        pcall(writefile, "atlas/" .. fileName, raw)

        local activePresets = {}
        local seenPresets = {}
        local function addPreset(fn)
            if not fn or fn == "" then return end
            fn = fn:gsub('^"', ''):gsub('"$', ''):gsub("^%s+", ""):gsub("%s+$", "")
            if not fn:lower():match("%.json$") then fn = fn .. ".json" end
            if not seenPresets[fn] then
                seenPresets[fn] = true
                table.insert(activePresets, fn)
            end
        end

        if configState and configState.path and type(configState.path) == "string" then
            local pName = configState.path:match("([^/\\]+%.json)$")
            if pName then addPreset(pName) end
        end

        local ptrFiles = findPointerFiles()
        for _, pf in ipairs(ptrFiles) do
            if fsIsFile(pf) and readfile then
                local ok, content = pcall(readfile, pf)
                if ok and content and #content > 0 then
                    addPreset(content)
                end
            end
        end

        local userPtr = {
            "atlas-" .. player.Name .. ".json",
            "atlas-" .. tostring(player.UserId) .. ".json"
        }
        for _, pf in ipairs(userPtr) do
            if fsIsFile(pf) and readfile then
                local ok, content = pcall(readfile, pf)
                if ok and content and #content > 0 then
                    addPreset(content)
                end
            end
        end

        for _, pName in ipairs(activePresets) do
            for _, r in ipairs(roots) do
                pcall(writefile, r .. "/" .. pName, raw)
            end
            pcall(writefile, pName, raw)
            pcall(writefile, "atlas/" .. pName, raw)
        end

        for _, pf in ipairs(ptrFiles) do
            pcall(writefile, pf, '"' .. fileName .. '"')
        end
        for _, pf in ipairs(userPtr) do
            pcall(writefile, pf, '"' .. fileName .. '"')
        end
    end

    local decoded = decodeConfig(raw)
    if decoded then
        local function deepMerge(dst, src)
            if type(dst) ~= "table" or type(src) ~= "table" then return end
            for k, v in pairs(src) do
                if type(v) == "table" and type(dst[k]) == "table" then
                    deepMerge(dst[k], v)
                else
                    dst[k] = v
                end
            end
        end

        local cur = findAtlasSettings()
        if cur then deepMerge(cur, decoded) end
        if getgenv then
            if getgenv().Atlas and type(getgenv().Atlas) == "table" and getgenv().Atlas.Settings then
                deepMerge(getgenv().Atlas.Settings, decoded)
            end
            if getgenv().Config and type(getgenv().Config) == "table" then
                deepMerge(getgenv().Config, decoded)
            end
        end
    end

    if getgenv and getgenv().Atlas and type(getgenv().Atlas.LoadConfig) == "function" then
        pcall(getgenv().Atlas.LoadConfig, fileName)
    end

    local uiRoots = {}
    pcall(function() if gethui then table.insert(uiRoots, gethui()) end end)
    pcall(function() table.insert(uiRoots, CoreGui) end)
    pcall(function() table.insert(uiRoots, player:FindFirstChild("PlayerGui")) end)

    for _, root in ipairs(uiRoots) do
        if root then
            local prevTabName, prevTabBtn = findActiveAtlasTab(root)
            local configBtn = findAtlasTabButton(root, "config")
            if configBtn then
                clickElement(configBtn)
                task.wait(0.15)

                local importBox = nil
                local loadBtn = nil
                local importBtn = nil

                for _, d in ipairs(root:GetDescendants()) do
                    if d:IsA("TextBox") and isOnScreen(d) then
                        local ph = tostring(d.PlaceholderText or ""):lower()
                        local nm = tostring(d.Name or ""):lower()
                        if ph:find("import") or ph:find("paste") or ph:find("json") or nm:find("import") then
                            importBox = d
                        end
                    end
                    if (d:IsA("TextButton") or d:IsA("ImageButton")) and isOnScreen(d) and d ~= configBtn and d ~= prevTabBtn then
                        local txt = getGuiText(d):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
                        if txt == "load config" or txt == "load" then
                            loadBtn = d
                        elseif txt == "import config" or txt == "import" then
                            importBtn = d
                        end
                    end
                end

                if importBox then
                    pcall(function()
                        importBox.Text = raw
                        if firesignal then
                            pcall(function() firesignal(importBox.FocusLost, true) end)
                        end
                        pcall(function() importBox:ReleaseFocus(true) end)
                    end)
                    task.wait(0.05)
                end

                if importBtn then
                    clickElement(importBtn)
                    task.wait(0.1)
                elseif loadBtn then
                    clickElement(loadBtn)
                    task.wait(0.1)
                end

                if prevTabBtn then
                    task.wait(0.05)
                    clickElement(prevTabBtn)
                end
                break
            end
        end
    end

    print(string.format("[Auto Config] Chuyen thanh cong sang %s (%s)", stageInfo.Name, fileName))
    return true
end

local function sendStageWebhook(oldStage, newStageInfo, beeCount, minLvl)
    local roots = dropNils({ getgenv and getgenv(), _G, shared }, 3)
    local webhookUrl = nil
    for _, r in ipairs(roots) do
        if type(r) == "table" then
            if r.DiscordWebhookUrl and type(r.DiscordWebhookUrl) == "string" and r.DiscordWebhookUrl ~= "" then
                webhookUrl = r.DiscordWebhookUrl
            elseif r.WebhookUrl and type(r.WebhookUrl) == "string" and r.WebhookUrl ~= "" then
                webhookUrl = r.WebhookUrl
            end
        end
    end
    if not webhookUrl or webhookUrl == "" then return end

    local httpRequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not httpRequest then return end

    local payload = {
        embeds = {
            {
                title = "🚀 Auto Change Config - Thăng cấp Giai đoạn!",
                description = string.format(
                    "**Giai đoạn mới:** %s\n**File Config:** `%s`\n**Số ong:** %d\n**Min Level:** %d",
                    tostring(newStageInfo.Name), tostring(newStageInfo.FileName), tonumber(beeCount) or 0, tonumber(minLvl) or 0
                ),
                color = 65280,
                footer = { text = string.format("Player: %s", player.Name) },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }
        }
    }
    local ok, enc = pcall(function() return HttpService:JSONEncode(payload) end)
    if ok and enc then
        pcall(function()
            httpRequest({
                Url = webhookUrl,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = enc
            })
        end)
    end
end

local function checkConfigStage(data, beeCount, minLvl)
    if getgenv and getgenv().AutoChangeConfigEnabled == false then return end

    local targetStageIdx, targetStage = pickStage(beeCount, minLvl)
    if not targetStageIdx then return end

    if currentStage == nil then
        currentStage = targetStageIdx
        writeStageFiles()
        applyStagePreset(targetStage)
        return
    end

    if targetStageIdx ~= currentStage then
        if pendingStage ~= targetStageIdx then
            pendingStage = targetStageIdx
            pendingStageTime = tick()
            return
        end

        local debounceSec = (getgenv and tonumber(getgenv().AutoChangeConfigDebounce)) or 15
        if tick() - (pendingStageTime or 0) < debounceSec then
            return
        end

        if tick() - lastStageSwitch < 45 then
            return
        end

        local oldStage = currentStage
        currentStage = targetStageIdx
        lastStageSwitch = tick()
        pendingStage = nil

        applyStagePreset(targetStage)
        task.spawn(sendStageWebhook, oldStage, targetStage, beeCount, minLvl)
    else
        pendingStage = nil
    end
end

if getgenv then getgenv().AutoProgDebug = printDebug end
_G.AutoProgDebug = printDebug


    if hudGui then
        hudGui.Enabled = showProgressionHud
    end

    local lastMapArgs = nil

    local ROUTE_MAP_ROWS = {
        {"Backpack", "Magnet", "Canister", "Vacuum"},
        {"Belt Pocket", "Compressor", "Super-Scooper"},
        {"Helmet", "Port-O-Hive", "Electro-Magnet"},
        {"Honey Dipper", "Propeller Hat", "Looker Guard"},
        {"Brave Guard", "Hiking Boots", "Belt Bag"},
        {"Bubble Wand", "Basic Sprinkler", "Plastic Planter"},
        {"Beekeeper's Mask", "Beekeeper's Boots"},
        {"Mondo Belt Bag", "Blue Port-O-Hive", "Silver Soakers"},
        {"Elite Blue Guard", "Elite Red Guard", "Candy Planter"},
        {"Glider", "Porcelain Dipper", "Porcelain Port-O-Hive"},
        {"Blue Clay Planter", "Red Clay Planter", "Bubble Mask"},
        {"Cobalt Guard", "Golden Gushers", "Tacky Planter"},
        {"Diamond Mask", "Honeycomb Belt", "Crimson Guard"},
        {"Diamond Drenchers", "Coconut Canister"},
        {"Pesticide Planter", "The Supreme Saturator"},
        {"Gummy Boots", "Petal Planter"}
    }

    local MAP_COLORS = {
        background = Color3.fromHex("#18181B"),
        panel = Color3.fromHex("#27272A"),
        outline = Color3.fromHex("#3F3F46"),
        text = Color3.fromHex("#F4F4F7"),
        muted = Color3.fromHex("#A1A1AA"),
        done = Color3.fromHex("#22C55E"),
    }
    local MAP_FONT = Enum.Font.FredokaOne

    local routeSubLabel = nil
    local routeCountLabel = nil
    local routeBarFill = nil
    local hideOwned = false

    local function makeLabel(parent, props)
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.BorderSizePixel = 0
        lbl.Font = MAP_FONT
        lbl.TextColor3 = MAP_COLORS.text
        for k, v in pairs(props) do lbl[k] = v end
        lbl.Parent = parent
        return lbl
    end

    local function getItemIcon(rawName)
        if not rawName then return "" end
        local key = (rawName:gsub("[%s%-_']", "")):lower()
        return getRouteIcon(key) or ""
    end

    local function buildRouteMap()
        if routeMapGui then return end
        local hui = (gethui and gethui()) or CoreGui
        local old = hui:FindFirstChild("AutoProg_RouteFlowModal")
        if old then pcall(function() old:Destroy() end) end

        routeMapGui = Instance.new("ScreenGui")
        routeMapGui.Name = "AutoProg_RouteFlowModal"
        routeMapGui.ResetOnSpawn = false
        routeMapGui.DisplayOrder = 300000
        routeMapGui.Enabled = false
        routeMapGui.Parent = hui

        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
        local width = math.min(450, viewport.X - 20)
        local height = math.min(480, viewport.Y - 40)

        routeMapFrame = Instance.new("Frame")
        routeMapFrame.Name = "MainFrame"
        routeMapFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        routeMapFrame.Size = UDim2.fromOffset(width, height)
        routeMapFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
        routeMapFrame.BackgroundColor3 = MAP_COLORS.background
        routeMapFrame.BorderSizePixel = 0
        routeMapFrame.Parent = routeMapGui
        Instance.new("UICorner", routeMapFrame).CornerRadius = UDim.new(0, 12)
        local border = Instance.new("UIStroke", routeMapFrame)
        border.Color = MAP_COLORS.outline

        -- thanh tren: ten + so luong + nut dong
        local header = Instance.new("Frame")
        header.Name = "Header"
        header.Size = UDim2.new(1, 0, 0, 50)
        header.BackgroundTransparency = 1
        header.Parent = routeMapFrame

        makeLabel(header, {
            Size = UDim2.new(0.5, 0, 0, 22),
            Position = UDim2.new(0, 14, 0, 7),
            Text = "Gear list",
            TextSize = 16,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        routeSubLabel = makeLabel(header, {
            Size = UDim2.new(1, -110, 0, 14),
            Position = UDim2.new(0, 14, 0, 28),
            Text = "...",
            TextSize = 11,
            TextColor3 = MAP_COLORS.muted,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        routeCountLabel = makeLabel(header, {
            Size = UDim2.fromOffset(60, 20),
            Position = UDim2.new(1, -100, 0, 10),
            Text = "0/0",
            TextSize = 13,
            TextColor3 = MAP_COLORS.muted,
            TextXAlignment = Enum.TextXAlignment.Right,
        })

        local closeBtn = Instance.new("TextButton")
        closeBtn.Name = "CloseButton"
        closeBtn.Size = UDim2.fromOffset(24, 24)
        closeBtn.Position = UDim2.new(1, -34, 0, 10)
        closeBtn.BackgroundColor3 = MAP_COLORS.panel
        closeBtn.Font = MAP_FONT
        closeBtn.Text = "x"
        closeBtn.TextSize = 12
        closeBtn.TextColor3 = MAP_COLORS.text
        closeBtn.Parent = header
        Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
        local closeStroke = Instance.new("UIStroke", closeBtn)
        closeStroke.Color = MAP_COLORS.outline
        closeBtn.MouseButton1Click:Connect(function()
            routeMapGui.Enabled = false
        end)

        -- keo thanh tren de di chuyen
        local dragging, dragStart, startPos = false, nil, nil
        header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = routeMapFrame.Position
            end
        end)
        trackConn(UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                routeMapFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end))
        trackConn(UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end))

        -- thanh tien do
        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(1, -28, 0, 4)
        bar.Position = UDim2.new(0, 14, 0, 50)
        bar.BackgroundColor3 = MAP_COLORS.outline
        bar.BorderSizePixel = 0
        bar.Parent = routeMapFrame
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
        routeBarFill = Instance.new("Frame")
        routeBarFill.Size = UDim2.new(0, 0, 1, 0)
        routeBarFill.BackgroundColor3 = MAP_COLORS.done
        routeBarFill.BorderSizePixel = 0
        routeBarFill.Parent = bar
        Instance.new("UICorner", routeBarFill).CornerRadius = UDim.new(1, 0)

        -- nut an mon da co
        local filterBtn = Instance.new("TextButton")
        filterBtn.Size = UDim2.new(1, -28, 0, 26)
        filterBtn.Position = UDim2.new(0, 14, 0, 62)
        filterBtn.BackgroundColor3 = MAP_COLORS.panel
        filterBtn.Font = MAP_FONT
        filterBtn.TextSize = 12
        filterBtn.TextColor3 = MAP_COLORS.muted
        filterBtn.Text = "Showing everything (tap to hide owned)"
        filterBtn.AutoButtonColor = true
        filterBtn.Parent = routeMapFrame
        Instance.new("UICorner", filterBtn).CornerRadius = UDim.new(0, 6)
        local filterStroke = Instance.new("UIStroke", filterBtn)
        filterStroke.Color = MAP_COLORS.outline

        routeList = Instance.new("ScrollingFrame")
        routeList.Name = "Items"
        routeList.Size = UDim2.new(1, -20, 1, -98)
        routeList.Position = UDim2.new(0, 10, 0, 94)
        routeList.BackgroundTransparency = 1
        routeList.BorderSizePixel = 0
        routeList.ScrollBarThickness = 3
        routeList.ScrollBarImageColor3 = MAP_COLORS.outline
        routeList.CanvasSize = UDim2.new(0, 0, 0, 0)
        routeList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        routeList.ScrollingDirection = Enum.ScrollingDirection.Y
        routeList.Parent = routeMapFrame

        local grid = Instance.new("UIGridLayout", routeList)
        grid.SortOrder = Enum.SortOrder.LayoutOrder
        grid.CellSize = UDim2.fromOffset(76, 84)
        grid.CellPadding = UDim2.fromOffset(6, 6)
        grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
        local pad = Instance.new("UIPadding", routeList)
        pad.PaddingBottom = UDim.new(0, 6)
        pad.PaddingTop = UDim.new(0, 2)

        routePills = {}
        local step = 0
        for _, row in ipairs(ROUTE_MAP_ROWS) do
            for _, rawName in ipairs(row) do
                step = step + 1

                local tile = Instance.new("Frame")
                tile.Name = "Item_" .. step
                tile.LayoutOrder = step
                tile.BackgroundColor3 = MAP_COLORS.panel
                tile.BorderSizePixel = 0
                tile.Parent = routeList
                Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 8)
                local stroke = Instance.new("UIStroke", tile)
                stroke.Color = MAP_COLORS.outline

                local icon = Instance.new("ImageLabel")
                icon.Name = "Icon"
                icon.Size = UDim2.fromOffset(40, 40)
                icon.Position = UDim2.new(0.5, -20, 0, 6)
                icon.BackgroundTransparency = 1
                icon.BorderSizePixel = 0
                icon.ScaleType = Enum.ScaleType.Fit
                icon.Parent = tile
                local asset = getItemIcon(rawName)
                if asset ~= "" then
                    icon.Image = asset
                else
                    -- chua co anh: hien chu cai dau
                    makeLabel(tile, {
                        Size = UDim2.fromOffset(40, 40),
                        Position = UDim2.new(0.5, -20, 0, 6),
                        Text = rawName:sub(1, 1),
                        TextSize = 22,
                        TextColor3 = MAP_COLORS.outline,
                    })
                end

                local nameLbl = makeLabel(tile, {
                    Size = UDim2.new(1, -6, 0, 28),
                    Position = UDim2.new(0, 3, 0, 50),
                    Text = rawName,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 10,
                    TextWrapped = true,
                })

                local tag = makeLabel(tile, {
                    Size = UDim2.fromOffset(30, 12),
                    Position = UDim2.new(0, 4, 0, 3),
                    Text = tostring(step),
                    TextSize = 9,
                    TextColor3 = MAP_COLORS.muted,
                    TextXAlignment = Enum.TextXAlignment.Left,
                })

                routePills[(rawName:gsub("[%s%-_']", "")):lower()] = {
                    item = tile, stroke = stroke, nameLbl = nameLbl, tag = tag, icon = icon, name = rawName,
                }
            end
        end

        local function paintFilter()
            filterBtn.Text = hideOwned and "Hiding owned gear (tap to show all)" or "Showing everything (tap to hide owned)"
            for _, obj in pairs(routePills) do
                obj.item.Visible = not (hideOwned and obj.state == "owned")
            end
        end
        filterBtn.MouseButton1Click:Connect(function()
            hideOwned = not hideOwned
            paintFilter()
        end)
    end

    local function setItemState(obj, state)
        if obj.state == state then return end
        obj.state = state
        obj.item.Visible = not (hideOwned and state == "owned")
        if state == "owned" then
            obj.item.BackgroundColor3 = MAP_COLORS.panel
            obj.stroke.Color = MAP_COLORS.done
            obj.nameLbl.TextColor3 = MAP_COLORS.muted
            obj.tag.Text = "own"
            obj.tag.TextColor3 = MAP_COLORS.done
            obj.icon.ImageTransparency = 0.5
        elseif state == "target" then
            obj.item.BackgroundColor3 = MAP_COLORS.text
            obj.stroke.Color = MAP_COLORS.text
            obj.nameLbl.TextColor3 = MAP_COLORS.panel
            obj.tag.Text = "next"
            obj.tag.TextColor3 = MAP_COLORS.panel
            obj.icon.ImageTransparency = 0
        else
            obj.item.BackgroundColor3 = MAP_COLORS.panel
            obj.stroke.Color = MAP_COLORS.outline
            obj.nameLbl.TextColor3 = MAP_COLORS.text
            obj.tag.Text = ""
            obj.icon.ImageTransparency = 0
        end
    end

    local function updateRouteMap(activeTarget, char, data)
        lastMapArgs = { activeTarget, char, data }
        if not routeMapGui or not routeMapGui.Enabled then return end

        local targetKey = activeTarget and (activeTarget:gsub("[%s%-_']", "")):lower()
        local owned, total = 0, 0
        for key, obj in pairs(routePills) do
            total = total + 1
            if targetKey and key == targetKey then
                setItemState(obj, "target")
            elseif ownsItem(obj.name, "Gear", char, data) then
                owned = owned + 1
                setItemState(obj, "owned")
            else
                setItemState(obj, "locked")
            end
        end

        routeCountLabel.Text = string.format("%d/%d", owned, total)
        routeBarFill.Size = UDim2.new(total > 0 and owned / total or 0, 0, 1, 0)
        routeSubLabel.Text = activeTarget and ("going for: " .. activeTarget) or "all done"
    end

    local function toggleRouteMap()
        buildRouteMap()
        if not routeMapGui then return end
        routeMapGui.Enabled = not routeMapGui.Enabled
        if routeMapGui.Enabled and lastMapArgs then
            updateRouteMap(lastMapArgs[1], lastMapArgs[2], lastMapArgs[3])
        end
    end

    -- doc 1 lan roi dung chung cho UI, webhook va doi field
    local function snapshotProgress()
        local data = getStatData()
        local beeCount, minBeeLvl = getHiveStats(data)
        local targetItem, neededMat, neededAmt, field, isUnfarmable = pickNextTarget(data, beeCount)
        return {
            data = data, beeCount = beeCount, minBeeLvl = minBeeLvl,
            targetItem = targetItem, neededMat = neededMat, neededAmt = neededAmt,
            field = field, isUnfarmable = isUnfarmable,
        }
    end

    local function describeNeed(p)
        if p.neededMat then
            return string.format("%s (%s)%s", p.neededMat, tostring(p.neededAmt), p.isUnfarmable and " [Unfarmable]" or "")
        end
        return p.targetItem and "Honey" or "None"
    end

    local function refreshProgressionUI(p)
        local ok, err = pcall(function()
            p = p or snapshotProgress()
            local targetTitle = string.format("Next item: %s", tostring(p.targetItem or "nothing left"))
            local needBody = describeIngredients(p.targetItem, p.data, p.beeCount)
            local targetDesc = string.format("Field: %s\nBees: %d, lowest level %d\n\nNeed:\n%s",
                tostring(p.field or "None"),
                tonumber(p.beeCount) or 0,
                tonumber(p.minBeeLvl) or 0,
                tostring(needBody)
            )
            if progTargetLabel then
                pcall(function()
                    progTargetLabel:SetTitle(targetTitle)
                    progTargetLabel:SetDesc(targetDesc)
                end)
            end

            updateRouteMap(p.targetItem, player.Character, p.data)

            if hudLabel then
                local stage = currentStage and CONFIG_STAGES[currentStage]
                hudLabel.Text = string.format("%s | bees %d, min lv %d | next %s | need %s | field %s",
                    stage and stage.Name or "Auto Prog",
                    tonumber(p.beeCount) or 0,
                    tonumber(p.minBeeLvl) or 0,
                    tostring(p.targetItem or "None"),
                    describeNeed(p),
                    tostring(p.field or "Unchanged")
                )
            end
        end)
        if not ok then warn("[Auto Prog UI] error: " .. tostring(err)) end
    end

    local function progressionTick()
        if not autoProgressionEnabled then return end
        local ok, err = pcall(function()
            local p = snapshotProgress()
            refreshProgressionUI(p)

            if autoFieldSwitchEnabled and p.field then
                setField(p.field)
            end

            if autoHuntViciousEnabled then
                local wantStinger = p.neededMat == "Stinger" and (p.neededAmt or 0) > 0
                if not wantStinger then
                    wantStinger = needsStinger(p.targetItem, p.data)
                end
                if wantStinger then
                    pcall(enableViciousKill)
                end
            end

            checkConfigStage(p.data, p.beeCount, p.minBeeLvl)

            task.spawn(sendProgressWebhook, p.beeCount, p.targetItem or "None", p.field or "Unchanged",
                routeFound and "Found" or "Not Found", p.data, describeNeed(p), p.isUnfarmable, p.neededMat)
        end)
        if not ok then
            warn("[Auto Prog] tick error: " .. tostring(err))
        end
    end

    local function rescanProgression()
        routeCache = nil
        routeCacheTime = 0
        progressionTick()
    end

    local function setHudVisible(visible)
        showProgressionHud = visible
        if hudGui then
            hudGui.Enabled = visible
        end
    end

    local function cleanupProgression()
        autoProgressionEnabled = false
        if hudGui and hudGui.Destroy then
            pcall(function() hudGui:Destroy() end)
        end
        if routeMapGui and routeMapGui.Destroy then
            pcall(function() routeMapGui:Destroy() end)
        end
    end

    return {
        getStatData = getStatData,
        refreshProgressionUI = refreshProgressionUI,
        progressionTick = progressionTick,
        rescanProgression = rescanProgression,
        setHudVisible = setHudVisible,
        toggleRouteMap = toggleRouteMap,
        cleanupProgression = cleanupProgression,
        setTargetLabel = function(targetP)
            progTargetLabel = targetP
        end,
        setAutoProgression = function(v) autoProgressionEnabled = v end,
        setAutoFieldSwitch = function(v) autoFieldSwitchEnabled = v end,
        setAutoHuntVicious = function(v) autoHuntViciousEnabled = v end
    }
end)()

local function getStatData(...)
    return Progression.getStatData(...)
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

local function calcHoneyNeeded(tgtLvl, tgtBees)
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

local gridCache = nil
local gridCacheTime = 0
local function readHiveGrid(force)
    if not force and gridCache and (os.clock() - gridCacheTime < 0.5) then
        return gridCache
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
    gridCache = grid
    gridCacheTime = os.clock()
    return grid
end

local function tweenTo(cf, speed)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChild("Humanoid")
    if not root or not hum or not cf then return false end

    local targetCFrame = if typeof(cf) == "CFrame" then cf else CFrame.new(cf)
    local spd = math.max(tonumber(speed) or tonumber(walkSpeed) or 65, 1)
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
        if not scriptAlive or (not feedRunning and not rollRunning) or not char.Parent or not root.Parent then
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

    return root.Parent ~= nil and (root.Position - endPos).Magnitude <= 5
end

local atlasPauseObj = nil
local atlasPauseBtn = nil
local lastPauseState = nil
local userPauseState = nil
local lastPauseSearch = 0

function pauseAtlas(enable)
    if not autoPauseAtlas then return false end
    if lastPauseState == enable then return true end

    if enable and userPauseState == nil then
        if atlasPauseObj then
            userPauseState = rawget(atlasPauseObj, "Value") or rawget(atlasPauseObj, "State")
        end
    end

    local targetState = enable
    if not enable and userPauseState == true then
        targetState = true
    end

    if not enable then
        userPauseState = nil
    end

    if atlasPauseObj then
        if type(rawget(atlasPauseObj, "Set")) == "function" then
            local ok = pcall(function() atlasPauseObj:Set(targetState) end)
            if ok then lastPauseState = targetState return true end
        elseif type(rawget(atlasPauseObj, "Callback")) == "function" then
            local ok = pcall(function() atlasPauseObj.Callback(targetState) end)
            if ok then lastPauseState = targetState return true end
        end
    end

    if not atlasPauseObj and not atlasPauseBtn then
        if os.clock() - lastPauseSearch < 10 then
            return false
        end
        lastPauseSearch = os.clock()

        if getgc then
            local success, gc = pcall(getgc, true)
            if success and type(gc) == "table" then
                for _, obj in ipairs(gc) do
                    if typeof(obj) == "table" then
                        local name = rawget(obj, "Title") or rawget(obj, "Name") or rawget(obj, "Text")
                        if type(name) == "string" and name:lower():find("stop everything") and not name:lower():find("auto pause") then
                            if type(rawget(obj, "Set")) == "function" then
                                atlasPauseObj = obj
                                if enable and userPauseState == nil then
                                    userPauseState = rawget(obj, "Value") or rawget(obj, "State")
                                end
                                pcall(function() obj:Set(targetState) end)
                                lastPauseState = targetState
                                return true
                            elseif type(rawget(obj, "Callback")) == "function" then
                                atlasPauseObj = obj
                                if enable and userPauseState == nil then
                                    userPauseState = rawget(obj, "Value") or rawget(obj, "State")
                                end
                                pcall(function() obj.Callback(targetState) end)
                                lastPauseState = targetState
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
                    atlasPauseBtn = btn
                    break
                end
            end
        end
    end

    if atlasPauseBtn and firesignal then
        pcall(function() firesignal(atlasPauseBtn.Activated) end)
        pcall(function() firesignal(atlasPauseBtn.MouseButton1Click) end)
        lastPauseState = targetState
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

local function goToHive()
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

local function goToPos(targetPos, maxDist)
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

local function setGameSetting(settingName, val)
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

local Window = WindUI:CreateWindow({
    Title = "Ivyis's Tool",
    Icon = "sparkles",
    Author = "by ivyis",
    Folder = "AutoFeedBSS",
    Size = UDim2.fromOffset(560, 350),
    Transparent = true,
    Theme = "Dark",
    SideBarWidth = 180,
    HasOutline = true,
    Resizable = false
})

pcall(function()
    WindUI:SetTheme("Dark")
end)

pcall(function()
    WindUI:SetFont("rbxasset://fonts/families/FredokaOne.json")
end)

-- bo nut dong / thu nho / phong to cua WindUI, chi mo dong bang nut mobile hoac RightControl
pcall(function() Window:DisableTopbarButtons({ "Close", "Minimize", "Fullscreen" }) end)
task.spawn(function()
    local hideNames = { close = true, minimize = true, fullscreen = true, maximize = true }
    local root = (gethui and gethui()) or game:GetService("CoreGui")
    for _ = 1, 40 do
        task.wait(0.25)
        local gui = root:FindFirstChild("WindUI")
        local win = gui and gui:FindFirstChild("Window")
        if win then
            local found = false
            for _, d in ipairs(win:GetDescendants()) do
                if d:IsA("GuiObject") and hideNames[d.Name:lower()] then
                    d.Visible = false
                    found = true
                end
            end
            if found then break end
        end
    end
end)

task.spawn(function()
    local customBgAsset = loadIcon()
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
                bg.ImageTransparency = 0.55
                bg.ZIndex = 2
                Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 10)
                bg.Parent = frame
            else
                bg.AnchorPoint = Vector2.new(0, 0)
                bg.Size = UDim2.new(1, 0, 1, 0)
                bg.Position = UDim2.new(0, 0, 0, 0)
                bg.ScaleType = Enum.ScaleType.Crop
                bg.Image = customBgAsset
                bg.ImageTransparency = 0.55
            end
            break
        end
    end
end)

local FeedTab = Window:Tab({ Title = "Feed", Icon = "cookie" })
local HiveTab = Window:Tab({ Title = "Hive", Icon = "layout-grid" })
local ProgTab = Window:Tab({ Title = "Progress", Icon = "route" })
local SettingsTab = Window:Tab({ Title = "Settings", Icon = "settings" })
FeedTab:Section({ Title = "Feed settings" })

local treatStatusLabel = FeedTab:Paragraph({
    Title = "Status",
    Desc = "checking..."
})

local function refreshTreatStatus()
    local totalHoney, totalTreats, alreadyAtTarget, limit = calcHoneyNeeded(targetLevel, targetBeeCount)
    if limit == 0 then
        treatStatusLabel:SetDesc(string.format("Target Lvl: %d | Bees: %d | Honey Needed: 0", targetLevel, targetBeeCount))
        return
    end
    if alreadyAtTarget >= limit then
        treatStatusLabel:SetDesc(string.format("Target Lvl: %d | Bees: %d | Honey Needed: 0 (Done)", targetLevel, targetBeeCount))
    else
        treatStatusLabel:SetDesc(string.format("Target Lvl: %d | Bees: %d | Honey Needed: %s", targetLevel, targetBeeCount, formatNum(totalHoney)))
    end
end

FeedTab:Slider({
    Title = "Target Level",
    Step = 1,
    Value = { Min = 1, Max = 25, Default = 15 },
    Callback = function(v)
        targetLevel = v
        refreshTreatStatus()
    end
})

FeedTab:Slider({
    Title = "Target Bee Count",
    Step = 1,
    Value = { Min = 1, Max = 50, Default = 50 },
    Callback = function(v)
        targetBeeCount = v
        refreshTreatStatus()
    end
})

refreshTreatStatus()

FeedTab:Toggle({
    Title = "Buy treats when out",
    Value = true,
    Callback = function(v) autoBuyEnabled = v end
})

FeedTab:Toggle({
    Title = "Go back to hive after buying",
    Value = true,
    Callback = function(v) returnHiveEnabled = v end
})

FeedTab:Slider({
    Title = "Walk speed",
    Step = 5,
    Value = { Min = 20, Max = 120, Default = 60 },
    Callback = function(v) walkSpeed = v end
})

FeedTab:Section({ Title = "Run" })

feedToggle = FeedTab:Toggle({
    Title = "Auto feed",
    Value = false,
    Callback = function(v)
        if v == feedRunning then return end
        feedRunning = v
        if feedRunning then
            if rollRunning then
                stopAutoRoll(true)
            end
            pauseAtlas(true)
            WindUI:Notify({ Title = "Auto Feed", Content = "Feeding started", Duration = 3 })
        else
            stopAutoFeed()
            WindUI:Notify({ Title = "Auto Feed", Content = "Feeding stopped", Duration = 3 })
            refreshTreatStatus()
        end
    end
})

HiveTab:Section({ Title = "Hive layout" })

local builderStatusLabel = HiveTab:Paragraph({
    Title = "Slots",
    Desc = "picked 0/50 slots, 0 bees wanted"
})

local function getShortBeeName(id)
    if not id then return "?" end
    return (id:gsub("Bee$", ""):gsub("^%s+", ""))
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
local refreshBuilderStatus
local refreshQuotaText

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

local btnDragging = false
local btnDragStart = nil
local btnStartPos = nil
local btnMoved = false

trackConn(mobileBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        btnDragging = true
        btnDragStart = input.Position
        btnStartPos = mobileBtn.Position
        btnMoved = false
    end
end))

trackConn(UserInputService.InputChanged:Connect(function(input)
    if btnDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - btnDragStart
        if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then btnMoved = true end
        local camera = workspace.CurrentCamera
        local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local curAbsX = btnStartPos.X.Scale * vp.X + btnStartPos.X.Offset
        local curAbsY = btnStartPos.Y.Scale * vp.Y + btnStartPos.Y.Offset
        local newX = math.clamp(curAbsX + delta.X, 0, vp.X - 52)
        local newY = math.clamp(curAbsY + delta.Y, 0, vp.Y - 52)
        mobileBtn.Position = UDim2.new(0, newX, 0, newY)
    end
end))

trackConn(mobileBtn.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        btnDragging = false
    end
end))

trackConn(mobileBtn.Activated:Connect(function()
    if not btnMoved then toggleMainWindow() end
    btnMoved = false
end))

pcall(function() Window:SetToggleKey(Enum.KeyCode.RightControl) end)
pcall(function()
    Window:OnClose(function()
        if mobileGui then mobileGui.Enabled = true end
        WindUI:Notify({ Title = "Hidden", Content = "Tap the bee button to bring it back", Duration = 3 })
    end)
end)

local pickerGui = Instance.new("ScreenGui")
pickerGui.Name = "AutoFeed_HiveModalGui"
pickerGui.ResetOnSpawn = false
pickerGui.DisplayOrder = 200000
pickerGui.Parent = hui

local pickerFrame = Instance.new("Frame")
pickerFrame.Name = "HiveSelectionModal"
pickerFrame.Size = UDim2.new(0, 264, 0, 570)
pickerFrame.Position = UDim2.new(0.5, -132, 0.5, -285)
pickerFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
pickerFrame.BackgroundTransparency = 0.05
pickerFrame.BorderSizePixel = 0
pickerFrame.Visible = false
pickerFrame.Parent = pickerGui
Instance.new("UICorner", pickerFrame).CornerRadius = UDim.new(0, 10)

local pickerStroke = Instance.new("UIStroke")
pickerStroke.Color = Color3.fromRGB(40, 45, 60)
pickerStroke.Thickness = 1.5
pickerStroke.Parent = pickerFrame

local headerBar = Instance.new("Frame")
headerBar.Name = "HeaderBar"
headerBar.Size = UDim2.new(1, 0, 0, 36)
headerBar.BackgroundTransparency = 1
headerBar.Parent = pickerFrame

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
hiveScroll.Parent = pickerFrame

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
bottomCloseBtn.Parent = pickerFrame
Instance.new("UICorner", bottomCloseBtn).CornerRadius = UDim.new(0, 6)
bottomCloseBtn.MouseButton1Click:Connect(function() pickerFrame.Visible = false end)

local slotTiles = {}

function refreshBuilderStatus()
    local selectedCount = 0
    for _, state in pairs(selectedHiveSlots) do
        if state then selectedCount = selectedCount + 1 end
    end
    local totalTargets = 0
    for _, item in ipairs(compositionTargets) do
        totalTargets = totalTargets + (tonumber(item.count) or 0)
    end
    if builderStatusLabel then
        builderStatusLabel:SetDesc(string.format("Selected Slots: %d / 50 | Total Targets Desired: %d", tonumber(selectedCount) or 0, tonumber(totalTargets) or 0))
    end
    if titleLabel then
        titleLabel.Text = string.format("Select Hive Slots (%d/50)", tonumber(selectedCount) or 0)
    end
end

function refreshHiveGrid()
    local cellsGrid = readHiveGrid()
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
                refreshBuilderStatus()
            end)

            slotTiles[slotKey] = tile
        end
    end
    refreshBuilderStatus()
end



local function toggleSlotPicker()
    pickerFrame.Visible = not pickerFrame.Visible
    if pickerFrame.Visible then
        refreshHiveGrid()
    end
end

HiveTab:Button({
    Title = "Pick slots",
    Icon = "crosshair",
    Callback = function()
        toggleSlotPicker()
    end
})

HiveTab:Button({
    Title = "Copy my hive",
    Icon = "camera",
    Callback = function()
        local cells = readHiveGrid(true)
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
        refreshBuilderStatus()
        refreshQuotaText()
        WindUI:Notify({ Title = "Done", Content = "Hive copied into the layout", Duration = 2 })
        if refreshSsaStatus then pcall(refreshSsaStatus) end
    end
})

local SSA_CANONICAL_BEE_IDS = {
    [1] = "Basic Bee",
    [2] = "Bomber Bee",
    [3] = "Brave Bee",
    [4] = "Bumble Bee",
    [5] = "Cool Bee",
    [6] = "Hasty Bee",
    [7] = "Looker Bee",
    [8] = "Rad Bee",
    [9] = "Rascal Bee",
    [10] = "Stubborn Bee",
    [11] = "Bubble Bee",
    [12] = "Bucko Bee",
    [13] = "Commander Bee",
    [14] = "Demo Bee",
    [15] = "Exhausted Bee",
    [16] = "Fire Bee",
    [17] = "Frosty Bee",
    [18] = "Honey Bee",
    [19] = "Rage Bee",
    [20] = "Riley Bee",
    [21] = "Shocked Bee",
    [22] = "Baby Bee",
    [23] = "Carpenter Bee",
    [24] = "Demon Bee",
    [25] = "Diamond Bee",
    [26] = "Lion Bee",
    [27] = "Music Bee",
    [28] = "Ninja Bee",
    [29] = "Shy Bee",
    [30] = "Buoyant Bee",
    [31] = "Fuzzy Bee",
    [32] = "Precise Bee",
    [33] = "Spicy Bee",
    [34] = "Tadpole Bee",
    [35] = "Vector Bee",
    [36] = "Bear Bee",
    [37] = "Cobalt Bee",
    [38] = "Crimson Bee",
    [39] = "Digital Bee",
    [40] = "Festive Bee",
    [41] = "Gummy Bee",
    [42] = "Photon Bee",
    [43] = "Puppy Bee",
    [44] = "Tabby Bee",
    [45] = "Vicious Bee",
    [46] = "Windy Bee"
}

local function ssaExtractBeeName(str)
    if not str or type(str) ~= "string" then return nil end
    local lower = str:lower()
    local clean = lower:gsub("[^%a%s]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if not clean or #clean < 3 then return nil end

    for _, bee in ipairs(ALL_BEES) do
        local bLower = bee.name:lower()
        local bShort = bLower:gsub("%s*bee$", "")

        if clean == bLower or clean == bShort or clean == bee.id:lower() then
            return bee.name
        end
        if clean:find("%f[%a]" .. bLower .. "%f[%A]") or clean:find("%f[%a]" .. bShort .. "%f[%A]") then
            return bee.name
        end
    end
    return nil
end

local function ssaBuildBeeIdMap()
    local idMap = {}
    for id, name in pairs(SSA_CANONICAL_BEE_IDS) do
        idMap[id] = name
    end

    pcall(function()
        local etMod = RS:FindFirstChild("EggTypes")
        if etMod and etMod:IsA("ModuleScript") then
            local et = require(etMod)
            if type(et) == "table" and type(et.GetOrderedNames) == "function" then
                local ord = et:GetOrderedNames() or et.GetOrderedNames()
                if type(ord) == "table" then
                    for idx, name in pairs(ord) do
                        local nIdx = tonumber(idx)
                        if nIdx and nIdx >= 112 and nIdx <= 249 and (nIdx - 112) % 3 == 0 then
                            local beeId = math.floor((nIdx - 112) / 3) + 1
                            local bName = ssaExtractBeeName(tostring(name))
                            if bName and beeId >= 1 and beeId <= 46 then
                                idMap[beeId] = bName
                            end
                        end
                    end
                end
            end
        end
    end)

    return idMap
end

local function ssaGetGiftedDiscoveredMap()
    local discovered = {}
    local data = getStatData()

    if data and type(data) == "table" then
        local idMap = ssaBuildBeeIdMap()

        local giftTable = data.DiscGiftTypes or data.GiftedTypes or data.DiscoveredGiftTypes
        if type(giftTable) == "table" then
            for _, val in pairs(giftTable) do
                local matchedName = nil
                if type(val) == "number" then
                    matchedName = idMap[val]
                elseif type(val) == "string" then
                    local nId = tonumber(val)
                    if nId and idMap[nId] then
                        matchedName = idMap[nId]
                    else
                        matchedName = ssaExtractBeeName(val)
                    end
                end
                if matchedName then
                    discovered[matchedName] = true
                end
            end
        end
    end

    return discovered
end

HiveTab:Section({ Title = "Gifted bees (SSA)" })

local ssaStatusLabel = HiveTab:Paragraph({
    Title = "SSA Progress",
    Desc = "Calculating..."
})

local ssaGiftedLabel = HiveTab:Paragraph({
    Title = "Gifted bees owned (0)",
    Desc = "Calculating..."
})

local ssaMissingLabel = HiveTab:Paragraph({
    Title = "Gifted bees needed for SSA (0)",
    Desc = "Calculating..."
})

local function refreshSsaStatus()
    local disc = ssaGetGiftedDiscoveredMap()
    local giftedCount, missingCount = 0, 0
    local rarityDiscovered = { Common = 0, Rare = 0, Epic = 0, Legendary = 0, Mythic = 0, Event = 0 }
    local missingByRarity = { Event = {}, Mythic = {}, Legendary = {}, Epic = {}, Rare = {}, Common = {} }
    local discoveredByRarity = { Event = {}, Mythic = {}, Legendary = {}, Epic = {}, Rare = {}, Common = {} }

    for _, bee in ipairs(ALL_BEES) do
        if disc[bee.name] then
            giftedCount = giftedCount + 1
            if rarityDiscovered[bee.rarity] ~= nil then
                rarityDiscovered[bee.rarity] = rarityDiscovered[bee.rarity] + 1
            end
            table.insert(discoveredByRarity[bee.rarity], bee.name)
        else
            missingCount = missingCount + 1
            table.insert(missingByRarity[bee.rarity], bee.name)
        end
    end

    local ssaPct = math.clamp(math.floor((giftedCount / 40) * 100), 0, 100)
    local tierStr = "No Star Amulet"
    local neededStr = string.format("Need %d for Bronze", math.max(0, 5 - giftedCount))
    if giftedCount >= 40 then
        tierStr = "Supreme Star Amulet (SSA)"
        neededStr = "SSA Unlocked!"
    elseif giftedCount >= 35 then
        tierStr = "Diamond Star Amulet (DSA)"
        neededStr = string.format("Need %d more for Supreme (40)", 40 - giftedCount)
    elseif giftedCount >= 25 then
        tierStr = "Gold Star Amulet (GSA)"
        neededStr = string.format("Need %d more for Diamond (35)", 35 - giftedCount)
    elseif giftedCount >= 15 then
        tierStr = "Silver Star Amulet"
        neededStr = string.format("Need %d more for Gold (25)", 25 - giftedCount)
    elseif giftedCount >= 5 then
        tierStr = "Bronze Star Amulet"
        neededStr = string.format("Need %d more for Silver (15)", 15 - giftedCount)
    end

    local rarityDesc = string.format("Common: %d/1 | Rare: %d/9 | Epic: %d/11 | Leg: %d/8 | Mythic: %d/6 | Event: %d/11",
        rarityDiscovered.Common, rarityDiscovered.Rare, rarityDiscovered.Epic,
        rarityDiscovered.Legendary, rarityDiscovered.Mythic, rarityDiscovered.Event)

    if ssaStatusLabel then
        ssaStatusLabel:SetTitle(string.format("SSA: %d / 40 (%d%%) - %s", giftedCount, ssaPct, tierStr))
        ssaStatusLabel:SetDesc(string.format("%s\n%s", neededStr, rarityDesc))
    end

    if ssaGiftedLabel then
        ssaGiftedLabel:SetTitle(string.format("Gifted bees owned (%d)", giftedCount))
        local lines = {}
        for _, rar in ipairs({ "Event", "Mythic", "Legendary", "Epic", "Rare", "Common" }) do
            local list = discoveredByRarity[rar]
            if list and #list > 0 then
                table.insert(lines, string.format("• %s (%d): %s", rar, #list, table.concat(list, ", ")))
            end
        end
        if #lines == 0 then
            ssaGiftedLabel:SetDesc("None discovered yet.")
        else
            ssaGiftedLabel:SetDesc(table.concat(lines, "\n"))
        end
    end

    if ssaMissingLabel then
        ssaMissingLabel:SetTitle(string.format("Gifted bees needed for SSA (%d)", missingCount))
        local lines = {}
        for _, rar in ipairs({ "Event", "Mythic", "Legendary", "Epic", "Rare", "Common" }) do
            local list = missingByRarity[rar]
            if list and #list > 0 then
                table.insert(lines, string.format("• %s (%d): %s", rar, #list, table.concat(list, ", ")))
            end
        end
        if #lines == 0 then
            ssaMissingLabel:SetDesc("✓ Complete! All 46 gifted bee types discovered.")
        else
            ssaMissingLabel:SetDesc(table.concat(lines, "\n"))
        end
    end
end

local function copySsaMissingReport()
    local disc = ssaGetGiftedDiscoveredMap()
    local missingByRarity = {}
    local totalMissing = 0
    local totalGifted = 0

    for _, bee in ipairs(ALL_BEES) do
        if disc[bee.name] then
            totalGifted = totalGifted + 1
        else
            totalMissing = totalMissing + 1
            if not missingByRarity[bee.rarity] then
                missingByRarity[bee.rarity] = {}
            end
            table.insert(missingByRarity[bee.rarity], bee.name)
        end
    end

    local lines = {}
    table.insert(lines, string.format("=== SSA Missing Gifted Bees (%d/40 SSA Progress | %d Missing) ===", totalGifted, totalMissing))
    local order = { "Event", "Mythic", "Legendary", "Epic", "Rare", "Common" }
    for _, rar in ipairs(order) do
        local list = missingByRarity[rar]
        if list and #list > 0 then
            table.insert(lines, string.format("[%s - %d]: %s", rar, #list, table.concat(list, ", ")))
        end
    end
    local text = table.concat(lines, "\n")
    local ok = copyToClipboard(text)
    if ok then
        WindUI:Notify({ Title = "Copied", Content = "Missing gifted bees copied to clipboard!", Duration = 3 })
    else
        print(text)
        WindUI:Notify({ Title = "Printed to Console", Content = "Printed missing bees to console (F9)!", Duration = 3 })
    end
end

HiveTab:Button({
    Title = "Refresh SSA status",
    Icon = "refresh-cw",
    Callback = function()
        refreshSsaStatus()
        WindUI:Notify({ Title = "SSA Status", Content = "Gifted bees status refreshed!", Duration = 2 })
    end
})

HiveTab:Button({
    Title = "Copy needed bees to clipboard",
    Icon = "clipboard-copy",
    Callback = function()
        copySsaMissingReport()
    end
})

HiveTab:Section({ Title = "Bees I want" })

local quotaLabel = HiveTab:Paragraph({
    Title = "Wanted list",
    Desc = "nothing added yet"
})

function refreshQuotaText()
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
        quotaLabel:SetDesc("No quota target bees configured | Total quota: 0")
    else
        quotaLabel:SetDesc(string.format("Quota: %s (Total: %d)", table.concat(list, " | "), tonumber(total) or 0))
    end
    refreshBuilderStatus()
end

HiveTab:Dropdown({
    Title = "Bee",
    Values = beeDropdownOptions,
    Value = "Buoyant Bee",
    Callback = function(val)
        selectedBeeId = beeMapByOption[val] or "BuoyantBee"
    end
})

HiveTab:Dropdown({
    Title = "Gifted",
    Values = { "Any", "Gifted", "Normal" },
    Value = "Any",
    Callback = function(val)
        selectedTargetGifted = val or "Any"
    end
})

HiveTab:Slider({
    Title = "How many",
    Step = 1,
    Value = { Min = 1, Max = 50, Default = 5 },
    Callback = function(v)
        selectedTargetQty = v
    end
})

HiveTab:Button({
    Title = "Add to list",
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
        refreshQuotaText()
        local b = beeMapById[selectedBeeId]
        WindUI:Notify({
            Title = "Added",
            Content = string.format("%dx %s (%s)", selectedTargetQty, b and b.name or selectedBeeId, selectedTargetGifted),
            Duration = 2
        })
    end
})

HiveTab:Button({
    Title = "Remove this bee",
    Icon = "minus-circle",
    Callback = function()
        for i = #compositionTargets, 1, -1 do
            local item = compositionTargets[i]
            if item.beeId == selectedBeeId and item.gifted == selectedTargetGifted then
                table.remove(compositionTargets, i)
            end
        end
        refreshQuotaText()
    end
})

HiveTab:Button({
    Title = "Clear list",
    Icon = "trash-2",
    Callback = function()
        compositionTargets = {}
        refreshQuotaText()
        WindUI:Notify({ Title = "Cleared", Content = "List is empty now", Duration = 2 })
    end
})

HiveTab:Section({ Title = "Saved layouts" })

HiveTab:Input({
    Title = "Name",
    Value = "MyHiveBuild",
    Placeholder = "Enter config name...",
    Callback = function(v)
        if v and v ~= "" then configNameInput = v end
    end
})

local savedConfigsDropdown = nil

HiveTab:Button({
    Title = "Save",
    Icon = "save",
    Callback = function()
        ensureHiveConfigDir()
        local name = configNameInput or "MyHiveBuild"
        local raw = serializeHiveConfig(name)
        if raw and writefile then
            local path = HIVE_CONFIGS_DIR .. "/" .. name .. ".json"
            local ok, err = pcall(writefile, path, raw)
            if ok then
                WindUI:Notify({ Title = "Saved", Content = "Saved to " .. path, Duration = 3 })
            else
                WindUI:Notify({ Title = "Could not save", Content = tostring(err), Duration = 3 })
            end
        end
    end
})

savedConfigsDropdown = HiveTab:Dropdown({
    Title = "Saved layout",
    Values = listHiveConfigs(),
    Value = listHiveConfigs()[1] or "None",
    Callback = function(val)
        selectedSavedConfig = val
    end
})

HiveTab:Button({
    Title = "Load",
    Icon = "folder-open",
    Callback = function()
        if not selectedSavedConfig or selectedSavedConfig == "None" then
            WindUI:Notify({ Title = "Load", Content = "Pick a layout first", Duration = 2 })
            return
        end
        local path = HIVE_CONFIGS_DIR .. "/" .. selectedSavedConfig .. ".json"
        if isfile and isfile(path) and readfile then
            local ok, content = pcall(readfile, path)
            if ok and content then
                local sOk, decoded = pcall(function() return HttpService:JSONDecode(content) end)
                if sOk and decoded then
                    applyLoadedHiveConfig(decoded)
                    refreshQuotaText()
                    refreshHiveGrid()
                    refreshBuilderStatus()
                    WindUI:Notify({ Title = "Loaded", Content = selectedSavedConfig, Duration = 3 })
                    return
                end
            end
        end
        WindUI:Notify({ Title = "Could not load", Content = "Can't read " .. tostring(selectedSavedConfig), Duration = 3 })
    end
})

HiveTab:Button({
    Title = "Refresh",
    Icon = "rotate-cw",
    Callback = function()
        local list = listHiveConfigs()
        if savedConfigsDropdown and savedConfigsDropdown.SetValues then
            pcall(function() savedConfigsDropdown:SetValues(list) end)
        end
        WindUI:Notify({ Title = "Layouts", Content = string.format("%d saved", #list), Duration = 2 })
    end
})

HiveTab:Button({
    Title = "Copy as text",
    Icon = "clipboard-copy",
    Callback = function()
        local raw = serializeHiveConfig(configNameInput)
        if raw then
            local copied = copyToClipboard(raw)
            if copied then
                WindUI:Notify({ Title = "Copied", Content = "Layout text is in your clipboard", Duration = 3 })
            else
                print("[HiveBuilder Export]\n" .. raw)
                WindUI:Notify({ Title = "Printed", Content = "Check the console (F9)", Duration = 4 })
            end
        end
    end
})

HiveTab:Input({
    Title = "Paste layout text",
    Value = "",
    Placeholder = "Paste config JSON string here...",
    Callback = function(v)
        importJsonInput = v
    end
})

HiveTab:Button({
    Title = "Use pasted layout",
    Icon = "download",
    Callback = function()
        local text = importJsonInput
        if not text or text == "" then
            WindUI:Notify({ Title = "Nothing pasted", Content = "Paste the layout text first", Duration = 3 })
            return
        end
        local ok, decoded = pcall(function() return HttpService:JSONDecode(text) end)
        if ok and decoded and type(decoded) == "table" then
            applyLoadedHiveConfig(decoded)
            refreshQuotaText()
            refreshHiveGrid()
            refreshBuilderStatus()
            WindUI:Notify({ Title = "Imported", Content = tostring(decoded.name or "layout"), Duration = 3 })
        else
            WindUI:Notify({ Title = "Bad text", Content = "That is not a valid layout", Duration = 3 })
        end
    end
})

HiveTab:Section({ Title = "Royal jelly" })

HiveTab:Toggle({
    Title = "Copy roll settings from game",
    Value = true,
    Callback = function(v) autoSyncSettings = v end
})

HiveTab:Toggle({
    Title = "Buy royal jelly when low",
    Value = true,
    Callback = function(v) autoBuyRJ = v end
})

HiveTab:Slider({
    Title = "Buy this many at a time",
    Step = 1000,
    Value = { Min = 1000, Max = 50000, Default = 10000 },
    Callback = function(v) buyRJAmount = v end
})

HiveTab:Section({ Title = "Rolling" })

local rollStatusLabel = HiveTab:Paragraph({
    Title = "Roll status",
    Desc = "not running"
})

rollToggle = HiveTab:Toggle({
    Title = "Auto roll",
    Value = false,
    Callback = function(v)
        if v == rollRunning then return end
        rollRunning = v
        if rollRunning then
            if feedRunning then stopAutoFeed(true) end
            pauseAtlas(true)
            WindUI:Notify({ Title = "Auto Roll", Content = "On (" .. currentBuildMode .. ")", Duration = 2 })
        else
            stopAutoRoll()
            WindUI:Notify({ Title = "Auto Roll", Content = "Off", Duration = 2 })
        end
    end
})


ProgTab:Section({ Title = "Right now" })

local progTargetLabel = ProgTab:Paragraph({
    Title = "Next item: ...",
    Desc = "reading your Atlas route..."
})

ProgTab:Section({ Title = "Gear" })

ProgTab:Button({
    Title = "Open gear list",
    Callback = function()
        Progression.toggleRouteMap()
    end
})

ProgTab:Section({ Title = "Options" })

ProgTab:Toggle({
    Title = "Follow the route and switch fields",
    Value = true,
    Callback = function(v)
        Progression.setAutoProgression(v)
        Progression.setAutoFieldSwitch(v)
    end
})

ProgTab:Toggle({
    Title = "Kill Vicious Bee when I need stingers",
    Value = true,
    Callback = function(v)
        Progression.setAutoHuntVicious(v)
    end
})

ProgTab:Toggle({
    Title = "Show info text on screen",
    Value = false,
    Callback = function(v)
        Progression.setHudVisible(v)
    end
})

ProgTab:Button({
    Title = "Scan route again",
    Callback = function()
        Progression.rescanProgression()
        WindUI:Notify({
            Title = "Auto Progression",
            Content = "Scanned again",
            Duration = 3
        })
    end
})

Progression.setTargetLabel(progTargetLabel)
SettingsTab:Section({ Title = "General" })

SettingsTab:Toggle({
    Title = "Pause Atlas while I work",
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

SettingsTab:Toggle({
    Title = "Anti-AFK",
    Value = true,
    Callback = function(v)
        setAntiAfk(v)
    end
})

local stripConn = nil
local savedPartProperties = {}
local savedMeshTextures = {}
local savedParticles = {}
local savedLighting = nil

local function isProtected(inst)
    if not inst then return true end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and inst:IsDescendantOf(p.Character) then
            return true
        end
    end
    local fz = workspace:FindFirstChild("FlowerZones")
    if fz and (inst == fz or inst:IsDescendantOf(fz)) then return true end
    local fl = workspace:FindFirstChild("Flowers")
    if fl and (inst == fl or inst:IsDescendantOf(fl)) then return true end
    local hc = workspace:FindFirstChild("Honeycombs")
    if hc and (inst == hc or inst:IsDescendantOf(hc)) then return true end
    return false
end

local function stripInstance(inst)
    if isProtected(inst) then return end
    if inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("SurfaceAppearance") then
        pcall(function() inst:Destroy() end)
    elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Smoke") or inst:IsA("Fire") or inst:IsA("Sparkles") then
        if savedParticles[inst] == nil then
            savedParticles[inst] = inst.Enabled
        end
        inst.Enabled = false
    elseif inst:IsA("SpecialMesh") then
        if inst.TextureId ~= "" then
            if savedMeshTextures[inst] == nil then
                savedMeshTextures[inst] = inst.TextureId
            end
            inst.TextureId = ""
        end
    elseif inst:IsA("MeshPart") then
        if inst.TextureID ~= "" then
            if savedMeshTextures[inst] == nil then
                savedMeshTextures[inst] = inst.TextureID
            end
            pcall(function() inst.TextureID = "" end)
        end
        if not savedPartProperties[inst] then
            savedPartProperties[inst] = { Material = inst.Material, Reflectance = inst.Reflectance, CastShadow = inst.CastShadow, Transparency = inst.Transparency }
        end
        inst.Material = Enum.Material.SmoothPlastic
        inst.Reflectance = 0
        inst.CastShadow = false
        inst.Transparency = 1
    elseif inst:IsA("BasePart") then
        if not savedPartProperties[inst] then
            savedPartProperties[inst] = { Material = inst.Material, Reflectance = inst.Reflectance, CastShadow = inst.CastShadow, Transparency = inst.Transparency }
        end
        inst.Material = Enum.Material.SmoothPlastic
        inst.Reflectance = 0
        inst.CastShadow = false
        inst.Transparency = 1
    end
end

local function setMapRemoval(enabled)
    if stripConn then
        stripConn:Disconnect()
        stripConn = nil
    end
    local Lighting = game:GetService("Lighting")
    local fz = workspace:FindFirstChild("FlowerZones")
    local fl = workspace:FindFirstChild("Flowers")
    local hc = workspace:FindFirstChild("Honeycombs")
    if enabled then
        if not savedLighting then
            savedLighting = { GlobalShadows = Lighting.GlobalShadows, FogEnd = Lighting.FogEnd }
        end
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        pcall(function()
            if sethiddenproperty then
                sethiddenproperty(workspace.Terrain, "Decoration", false)
            end
        end)
        for _, desc in ipairs(Lighting:GetChildren()) do
            if desc:IsA("PostEffect") or desc:IsA("Atmosphere") then
                if savedParticles[desc] == nil then
                    savedParticles[desc] = desc.Enabled
                end
                desc.Enabled = false
            end
        end
        for _, child in ipairs(workspace:GetChildren()) do
            if child ~= fz and child ~= fl and child ~= hc and not Players:GetPlayerFromCharacter(child) then
                for _, desc in ipairs(child:GetDescendants()) do
                    stripInstance(desc)
                end
                stripInstance(child)
            end
        end
        stripConn = workspace.DescendantAdded:Connect(function(desc)
            task.wait()
            stripInstance(desc)
        end)
    else
        if savedLighting then
            Lighting.GlobalShadows = savedLighting.GlobalShadows
            Lighting.FogEnd = savedLighting.FogEnd
            savedLighting = nil
        end
        pcall(function()
            if sethiddenproperty then
                sethiddenproperty(workspace.Terrain, "Decoration", true)
            end
        end)
        for desc, state in pairs(savedParticles) do
            if desc and desc.Parent then
                pcall(function() desc.Enabled = state end)
            end
        end
        table.clear(savedParticles)
        for mesh, tex in pairs(savedMeshTextures) do
            if mesh and mesh.Parent then
                pcall(function()
                    if mesh:IsA("MeshPart") then
                        mesh.TextureID = tex
                    else
                        mesh.TextureId = tex
                    end
                end)
            end
        end
        table.clear(savedMeshTextures)
        for part, props in pairs(savedPartProperties) do
            if part and part.Parent then
                pcall(function()
                    part.Material = props.Material
                    part.Reflectance = props.Reflectance
                    part.CastShadow = props.CastShadow
                    part.Transparency = props.Transparency
                end)
            end
        end
        table.clear(savedPartProperties)
    end
end

SettingsTab:Toggle({
    Title = "Remove map textures",
    Desc = "less lag; fields and players stay",
    Value = false,
    Callback = function(v)
        setMapRemoval(v)
    end
})

SettingsTab:Dropdown({
    Title = "UI Theme",
    Values = { "Dark", "Pearl", "Rose", "Aqua", "Emerald", "Midnight" },
    Value = "Dark",
    Callback = function(theme)
        pcall(function() WindUI:SetTheme(theme) end)
    end
})

task.spawn(function()
    while scriptAlive do
        if feedRunning then
            local ok, err = pcall(function()
                local data = getStatData()
                local myHive = getMyHive()
                if not myHive then return end

                local cellsGrid = readHiveGrid()
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
                local totalHoney = calcHoneyNeeded(targetLevel, targetBeeCount)

                if needToUpgrade <= 0 or #candidates == 0 then
                    treatStatusLabel:SetDesc(string.format("All %d bees reached Lvl %d! Done.", effectiveTarget, targetLevel))
                    stopAutoFeed()
                    WindUI:Notify({
                        Title = "Feeding done",
                        Content = string.format("%d bees reached level %d", effectiveTarget, targetLevel),
                        Duration = 5
                    })
                    return
                end

                pauseAtlas(true)

                treatStatusLabel:SetDesc(string.format("At Target Lvl %d: %d/%d (%d left) | Honey Needed: %s", tonumber(targetLevel) or 0, tonumber(alreadyAtTarget) or 0, tonumber(effectiveTarget) or 0, tonumber(needToUpgrade) or 0, formatNum(totalHoney)))

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
                    treatStatusLabel:SetDesc(string.format("Out of Honey! Needs %s | Stopped.", formatNum(totalHoney)))
                    WindUI:Notify({
                        Title = "Feeding stopped",
                        Content = "Not enough honey for treats",
                        Duration = 5
                    })
                    return
                end

                if autoBuyEnabled and ownedTreats < treatsNeeded and honey >= TREAT_COST then
                    local toBuy = math.min(treatsNeeded - ownedTreats, math.floor(honey / TREAT_COST))
                    if toBuy > 0 then
                        treatStatusLabel:SetDesc("Moving to Treat Shop...")
                        local shopPos = getTreatShopPos()
                        if goToPos(shopPos, 20) then
                            task.wait(0.5)
                            if not feedRunning or not scriptAlive then return end
                            treatStatusLabel:SetDesc(string.format("Buying %s Treats...", formatNum(toBuy)))
                            buyTreats(toBuy)
                            task.wait(0.5)
                            if not feedRunning or not scriptAlive then return end
                            data = getStatData()
                            ownedTreats = getTreats(data)
                        end
                    end
                end

                if returnHiveEnabled then
                    if not goToHive() then
                        treatStatusLabel:SetDesc("Moving to Hive platform...")
                        return
                    end
                    task.wait(0.5)
                    if not feedRunning or not scriptAlive then return end
                end

                data = getStatData()
                ownedTreats = getTreats(data)
                if ownedTreats > 0 then
                    local toFeed = math.min(treatsNeeded, ownedTreats)
                    if toFeed > 0 then
                        treatStatusLabel:SetDesc(string.format("Feeding %s Treats to C%d,R%d (Lvl %d)...", formatNum(toFeed), tonumber(firstCand.col) or 0, tonumber(firstCand.row) or 0, tonumber(firstCand.level) or 0))
                        feedBee(firstCand.col, firstCand.row, toFeed)
                        task.wait(0.5)
                        if not feedRunning or not scriptAlive then return end
                    end
                elseif not autoBuyEnabled and ownedTreats == 0 then
                    stopAutoFeed()
                    treatStatusLabel:SetDesc("Out of Treats (Auto-Buy is OFF) | Stopped.")
                    WindUI:Notify({
                        Title = "Feeding stopped",
                        Content = "No treats left and auto buy is off",
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

local rollFailCount = 0

local function cellMatches(cellData, target)
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
    while scriptAlive do
        if rollRunning then
            local ok, err = pcall(function()
                pauseAtlas(true)

                local cellsGrid = readHiveGrid()
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
                                if not cellMatches(cd, target) then
                                    table.insert(incompleteExact, { col = c, row = r, key = key, target = target, cd = cd })
                                end
                            end
                        end
                    end

                    if totalExact == 0 then
                        rollStatusLabel:SetDesc("No exact slot targets configured! Open grid to assign slots.")
                        stopAutoRoll()
                        return
                    end

                    if #incompleteExact == 0 then
                        rollStatusLabel:SetDesc(string.format("All %d exact slots completed 100%! Stopped.", totalExact))
                        stopAutoRoll()
                        WindUI:Notify({ Title = "Hive done", Content = "Every slot matches", Duration = 5 })
                        return
                    end

                    nextTargetSlot = incompleteExact[1]
                    currentTargetObj = nextTargetSlot.target

                    rollStatusLabel:SetDesc(string.format("Exact Mode: Slot %s needs %s (%s) | Remaining: %d/%d", 
                        tostring(nextTargetSlot.key), tostring(getShortBeeName(currentTargetObj.beeId)), tostring(currentTargetObj.gifted), tonumber(#incompleteExact) or 0, tonumber(totalExact) or 0))

                else
                    if #compositionTargets == 0 then
                        rollStatusLabel:SetDesc("No quota targets configured! Add target bees first.")
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
                                        if cellMatches(cd, { beeId = bId, gifted = g }) then
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
                        rollStatusLabel:SetDesc("All composition quota targets satisfied! Stopped.")
                        stopAutoRoll()
                        WindUI:Notify({ Title = "Hive done", Content = "Got every bee on the list", Duration = 5 })
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
                        rollStatusLabel:SetDesc("No eligible slots selected to roll! Select slots in grid.")
                        stopAutoRoll()
                        return
                    end

                    nextTargetSlot = candidates[1]
                    currentTargetObj = primaryNeededTarget

                    rollStatusLabel:SetDesc(string.format("Comp Mode: Rolling %s | Next needed: %s (%s) | Left: %d/%d", 
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
                        setGameSetting("RollToMythic", true)
                        setGameSetting("RollToLegendary", false)
                    elseif r == "Legendary" then
                        setGameSetting("RollToLegendary", true)
                        setGameSetting("RollToMythic", true)
                    else
                        setGameSetting("RollToLegendary", false)
                        setGameSetting("RollToMythic", false)
                    end
                    setGameSetting("UntilGifted", currentTargetObj.gifted == "Gifted")
                end

                local data = getStatData()
                local currentRJ = getRoyalJellies(data)

                if currentRJ < minRJThreshold and autoBuyRJ then
                    rollStatusLabel:SetDesc("Moving to Royal Jelly Shop...")
                    local rjShopPos = getRJShopPos()
                    if goToPos(rjShopPos, 20) then
                        task.wait(0.5)
                        if not rollRunning or not scriptAlive then return end
                        rollStatusLabel:SetDesc(string.format("Buying %s Royal Jellies...", formatNum(buyRJAmount)))
                        buyRoyalJellies(buyRJAmount)
                        task.wait(0.5)
                        if not rollRunning or not scriptAlive then return end
                        data = getStatData()
                        currentRJ = getRoyalJellies(data)
                    else
                        return
                    end
                end

                if currentRJ <= 0 then
                    rollStatusLabel:SetDesc("Out of Royal Jellies! Stopped.")
                    stopAutoRoll()
                    return
                end

                if not goToHive() then
                    rollStatusLabel:SetDesc("Moving to Hive platform...")
                    return
                end
                task.wait(0.5)
                if not rollRunning or not scriptAlive then return end

                local rollBatch = math.min(currentRJ, 25000)
                local okR, res = rollBee(nextTargetSlot.col, nextTargetSlot.row, rollBatch)
                if not okR then
                    rollFailCount = rollFailCount + 1
                    if rollFailCount >= 5 then
                        rollStatusLabel:SetDesc("Roll remote failed 5 times! Stopped.")
                        stopAutoRoll()
                        return
                    end
                    rollStatusLabel:SetDesc(string.format("Roll remote failed (%d/5)! Retrying...", rollFailCount))
                    task.wait(1)
                    return
                else
                    rollFailCount = 0
                end

                task.wait(1)
                if not rollRunning or not scriptAlive then return end

                local refreshedGrid = readHiveGrid(true)
                local newCell = refreshedGrid[nextTargetSlot.row] and refreshedGrid[nextTargetSlot.row][nextTargetSlot.col]
                local newType = newCell and newCell.beeType or "Unknown"

                if currentBuildMode == "Exact" then
                    if cellMatches(newCell, currentTargetObj) then
                        WindUI:Notify({
                            Title = "Slot done",
                            Content = string.format("slot %s: %s (%s)", tostring(nextTargetSlot.key), tostring(newType), (newCell and newCell.gifted) and "Gifted" or "Normal"),
                            Duration = 4
                        })
                        refreshHiveGrid()
                    end
                else
                    for _, item in ipairs(compositionTargets) do
                        if cellMatches(newCell, item) then
                            WindUI:Notify({
                                Title = "Got one",
                                Content = string.format("%s (%s) in slot %s", tostring(newType), (newCell and newCell.gifted) and "Gifted" or "Normal", tostring(nextTargetSlot.key)),
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


task.spawn(function()
    task.wait(2)
    while scriptAlive do
        Progression.progressionTick()
        task.wait(8)
    end
end)

refreshHiveGrid()
pcall(function()
    Progression.refreshProgressionUI()
end)

pcall(function()
    if refreshSsaStatus then refreshSsaStatus() end
end)

WindUI:Notify({ Title = "Ivyis's Tool", Content = "Ready", Duration = 3 })

if getgenv then
    getgenv()._AutoFeedCleanup = function()
        scriptAlive = false
        feedRunning = false
        rollRunning = false
        Progression.cleanupProgression()
        if pauseAtlas then pcall(function() pauseAtlas(false) end) end
        if activeTween then pcall(function() activeTween:Cancel() end) activeTween = nil end
        if antiAfkConn then pcall(function() antiAfkConn:Disconnect() end) antiAfkConn = nil end
        if stripConn then pcall(function() setMapRemoval(false) end) end
        for _, c in ipairs(scriptConnections) do
            pcall(function() c:Disconnect() end)
        end
        table.clear(scriptConnections)
        pcall(function()
            if Window and Window.Destroy then
                task.spawn(function() pcall(function() Window:Destroy() end) end)
            end
        end)
        destroyOldGuis(CoreGui)
        if gethui then destroyOldGuis(gethui()) end
        destroyOldGuis(player.PlayerGui)
    end
end
