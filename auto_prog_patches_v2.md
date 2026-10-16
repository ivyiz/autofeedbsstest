# Auto Prog — bản vá cho phiên bản mới

Mình chưa test được trong Roblox/Atlas. Các đoạn code đầy đủ bên dưới đã được kiểm tra cú pháp Lua, còn các chỉnh sửa một dòng chỉ là đọc code.

Phần A là lỗi mới hoặc đổi dạng ở bản này. Phần B liệt kê lỗi cũ vẫn còn, tham chiếu đến số mục trong `auto_prog_patches.md`.

---

# A. Lỗi mới / đổi dạng trong bản này

## A1. `isPlanterOwned` nhận nhầm "đã có planter" (nghiêm trọng)

Hàm này giờ trả `true` cho gần như mọi tín hiệu yếu, và `_knownOwnedPlanters` cache `true` **vĩnh viễn**, nên một lần nhận nhầm là planter đó bị bỏ qua đến khi rejoin. Có 5 chỗ.

**A1a. Mất kiểm tra giá trị.** Ở vòng `for _, tbl in ipairs(compact(pTables, 11))`, key trùng tên là coi như sở hữu dù value là `0` / `false` / `{}`. Bản cũ có `truthyOwned`.
- Đổi `if matches(k) then` thành `if matches(k) and truthyOwned(v) then`
- Đổi `if matches(k2) or (type(v2) == "string" and matches(v2)) then` thành `if (matches(k2) and truthyOwned(v2)) or (type(v2) == "string" and matches(v2)) then`

**A1b. Quét workspace: điều kiện `or t:find("planter")`.** Billboard của bạn dạng `"<Tên>'s Plastic Planter"` luôn chứa chữ "planter", nên chỉ cần đang đặt **một** planter bất kỳ là **mọi** planter khác đều bị coi là đã có.
Ngoài ra `rootPlanter` đã bỏ khoảng trắng (`blueclay`) nên không khớp text thật (`blue clay`), vì vậy phải so với bản text đã bỏ khoảng trắng.

Thay khối `if desc:IsA("TextLabel") then ... end` (trong vòng `for _, desc in ipairs(c:GetDescendants())`) bằng:
```lua
                if desc:IsA("TextLabel") then
                    local t = desc.Text:lower()
                    local tc = (t:gsub("[%s%-_']", ""))
                    if (t:find(pName, 1, true) or t:find(pDisplay, 1, true) or t:find(pUserId, 1, true))
                        and tc:find(rootPlanter, 1, true) then
                        _knownOwnedPlanters[cleanName] = true
                        return true
                    end
                end
```

**A1c. `owner.Value` không có guard.** `FindFirstChild("Owner"/"Player"/"User")` có thể trả về Folder/Model → `.Value` ném lỗi → cả vòng lặp chính lỗi. Thay đoạn `if owner then ... end` (trước `local attr = ...`) bằng:
```lua
                    if owner then
                        local okV, rawV = pcall(function() return owner.Value end)
                        if okV then
                            local ov = tostring(rawV):lower()
                            if ov == pName or ov == pUserId or rawV == player or (char and rawV == char) then
                                isMine = true
                            end
                        end
                    end
```

**A1d. Quét `PlayerGui` mọi TextLabel.** Giờ bất kỳ label nào chứa tên planter (ẩn, thông báo, hướng dẫn, tooltip, kể cả HUD của script nếu `guiParent` rơi về PlayerGui) cũng đánh dấu đã sở hữu. Đây là nguồn dương tính giả lớn nhất. Khuyến nghị tắt mặc định:
- Thêm dòng đầu trong `pcall(function()` của khối này: `if not (getgenv and getgenv().AutoProgPlanterGuiScan == true) then return end`
- Nếu bật, siết điều kiện: đổi `if desc:IsA("TextLabel") and matches(desc.Text) then` thành `if desc:IsA("TextLabel") and desc.Visible and #desc.Text <= 40 and matches(desc.Text) and not desc:FindFirstAncestor("AutoProg_HUD") then`

**A1e. `settings.planters` của Atlas là danh sách planter mà bot *dùng*, chưa chắc là đã sở hữu.** Đổi `if type(pSettings) == "table" then` thành `if type(pSettings) == "table" and getgenv and getgenv().AutoProgTrustAtlasPlanters == true then` (tắt mặc định).

---

## A2. `clickElement`: non-button không bao giờ click được, và đường VIM gần như là code chết

- `getconnections(clickable.MouseButton1Down)` chạy cho mọi `clickable` dù là Frame/TextLabel → ném lỗi "not a valid member", pcall nuốt, hàm trả `false` trước khi tới bước chuột. Với dropdown/option dạng label tự bắt `InputBegan`, nó không bao giờ click được.
- `firesignal` đặt `fired = true` vô điều kiện, nên khi executor có `firesignal`, nhánh VIM (`if not fired`) không bao giờ chạy.
- Vẫn gọi cả `c:Fire()` lẫn `c.Function` → handler chạy 2 lần; sau đó còn bắn thêm `Activated` và `MouseButton1Down`.

**Thay toàn bộ hàm `clickElement`** (giữ nguyên `isGuiVisibleOnScreen` và `bringIntoView` phía trên):
```lua
local GuiService = nil
pcall(function() GuiService = game:GetService("GuiService") end)

local function fireConnections(sig)
    local n = 0
    for _, c in ipairs(getconnections(sig)) do
        if c.Fire then
            c:Fire(); n = n + 1
        elseif c.Function then
            pcall(c.Function); n = n + 1
        end
    end
    return n
end

local function clickElement(gui)
    if not gui or not gui:IsA("GuiObject") then return false end

    local clickable = gui
    if not gui:IsA("GuiButton") then
        clickable = gui:FindFirstAncestorWhichIsA("GuiButton") or gui
    end

    bringIntoView(clickable)

    -- 1) Handler cua nut: chi voi GuiButton, moi connection dung 1 lan
    if clickable:IsA("GuiButton") then
        if getconnections then
            for _, sigName in ipairs({ "MouseButton1Click", "Activated" }) do
                local ok, cnt = pcall(function() return fireConnections(clickable[sigName]) end)
                if ok and cnt and cnt > 0 then return true end
            end
        elseif firesignal then
            if pcall(firesignal, clickable.MouseButton1Click) then return true end
        end
    end

    -- 2) Khong co connection (Frame / label tu bat InputBegan): click chuot that, chi khi dang hien
    if not isGuiVisibleOnScreen(clickable) then return false end

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

    if VIM then
        local ok = pcall(function()
            VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.03)
            VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        if ok then return true end
    end
    if VU then
        local ok = pcall(function()
            VU:Button1Down(Vector2.new(x, y))
            task.wait(0.02)
            VU:Button1Up(Vector2.new(x, y))
        end)
        if ok then return true end
    end
    return false
end
```
> Nếu click chuột bị lệch khoảng 36px thì đặt `inset = Vector2.new(0, 0)`.

---

## A3. UI Atlas: nhấp nháy tab mỗi 10s và quét nặng

Vòng lặp chính gọi `setAtlasField` mỗi 10s, nên `setAtlasFieldViaUI` chạy mỗi 10s với:
- `findFarmingSection`: với mỗi Frame/ScrollingFrame lại gọi `GetDescendants()` của nó + `gsub` cho từng label → chi phí ≈ số node × độ sâu, cho cả 3 root (gồm CoreGui).
- `findActiveAtlasTab`: 9 lần `root:GetDescendants()` (mỗi tab một lần), chạy cả với root không chứa Atlas.
- Khi header "Field:" đang ẩn, script **luôn** click sang tab Farming rồi click về, kể cả khi field đã đúng. UI Atlas sẽ nhấp nháy mỗi 10s và có thể phá thao tác của bạn.

**A3a.** Thêm ngay sau hàm `getFarmingSectionAndDropdown` (cache kết quả tìm, chỉ tìm nặng khi cache hỏng):
```lua
local _farmUICache = nil

local function getFarmingSectionAndDropdownCached(root)
    local c = _farmUICache
    if c and c.header and c.section and c.header:IsDescendantOf(root) and c.section:IsDescendantOf(root) then
        local txt = getGuiText(c.header):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if txt:lower():match("^field%s*:") then
            return c.section, c.header, txt
        end
    end
    local section, header, txt = getFarmingSectionAndDropdown(root)
    if section and header then _farmUICache = { section = section, header = header } end
    return section, header, txt
end
```

**A3b.** Trong `setAtlasFieldViaUI`, thay đoạn từ `local section, farmingHeader, headerTxt = getFarmingSectionAndDropdown(root)` đến hết khối `if not isFarmingVisible then ... end` bằng:
```lua
            local section, farmingHeader, headerTxt = getFarmingSectionAndDropdownCached(root)

            -- Header dang an van doc duoc text: da dung field thi khong can doi tab / click gi
            if farmingHeader and headerTxt then
                local cur = headerTxt:match("^[Ff]ield%s*:%s*(.+)")
                if cur and (cur:gsub("[%s%-_']", "")):lower() == targetClean then
                    return true, "ui_already_set"
                end
            end

            local isFarmingVisible = farmingHeader and isGuiVisibleOnScreen(farmingHeader)

            local prevTabName, prevTabBtn = nil, nil
            local switchedTab = false

            if not isFarmingVisible then
                -- chi quet tab khi root nay thuc su co nut Farming
                local farmingTabBtn = findAtlasTabButton(root, "farming")
                if farmingTabBtn then
                    prevTabName, prevTabBtn = findActiveAtlasTab(root)
                    clickElement(farmingTabBtn)
                    task.wait(0.1)
                    switchedTab = true
                    section, farmingHeader, headerTxt = getFarmingSectionAndDropdownCached(root)
                end
            end
```

**A3c.** Áp dụng thêm **mục 4 của `auto_prog_patches.md`** (thay `setAtlasField`) để chỉ gọi UI khi đổi field hoặc mỗi 60s. Mục này vẫn cần dù đã có A3a/A3b.

---

## A4. Dọn code chết (không bắt buộc)

- `RAW_FIELD_ITEMS` và `isRawFieldItem` không được gọi ở đâu.
- `getDefaultProgressionField` vẫn chưa được nối (xem mục 11 của `auto_prog_patches.md`).

---

# B. Lỗi cũ vẫn còn trong bản này

Số mục tham chiếu đến `auto_prog_patches.md`:

| Mục | Vấn đề | Ghi chú cho bản mới |
|---|---|---|
| 1 | HUD label không đặt tên `AutoProg_HUD` | Ít nghiêm trọng hơn trước nhờ các regex `^field` có neo đầu chuỗi, nhưng vẫn nên thêm `hudLabel.Name = "AutoProg_HUD"` (1 dòng) |
| 2 | Chạy lại script nhân đôi vòng lặp | Chưa có |
| 4 | `setAtlasField` quét UI mỗi 10s + ghi key rác vào settings | Vẫn nguyên, áp dụng được như cũ |
| 5 | `GetDescendants` không có pcall | Chỉ còn ở `getAtlasLiveTarget`; phần UI sẽ được pcall nếu áp dụng mục 4 |
| 6 | Quét `getgc` mỗi 5s + truy cập table không bảo vệ | Vẫn nguyên |
| 7 | Live target bỏ qua điều kiện số bee | Vẫn nguyên |
| 8 | Item lạ trong route làm kẹt tiến trình | Vẫn nguyên |
| 9c | Webhook V2 thiếu `?with_components=true` | Còn. Mục 9a/9b **không cần nữa** vì bản mới đã so sánh theo `neededMat` |
| 10 | `getStatData` sửa trực tiếp cache của game | Vẫn nguyên |
| 11 | `getDefaultProgressionField` không được gọi | Vẫn nguyên |

Mục 3 của `auto_prog_patches.md` được thay bằng **A2** ở trên, vì `clickElement` trong bản mới đã khác.
