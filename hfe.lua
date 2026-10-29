local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local player = Players.LocalPlayer

print("[HFE] Starting 1.7...")

-- safe wait: never hangs forever, so the menu always loads
local function waitFor(par, name, t)
    if not par then return nil end
    local o = par:WaitForChild(name, t or 8)
    if not o then warn("[HFE] Not found: " .. par:GetFullName() .. "." .. name) end
    return o
end

local SwimAdventure = waitFor(RS, "SwimAdventure")
local Remotes = waitFor(SwimAdventure, "Remotes")
local EggGrab = waitFor(Remotes, "EggGrab")
local ClickRemote = waitFor(Remotes, "Click")
local ActionRemote = waitFor(Remotes, "Action")

local Eggs
local function getEggsFolder()
    if Eggs and Eggs.Parent then return Eggs end
    local ln = workspace:FindFirstChild("LocalNests")
    Eggs = ln and ln:FindFirstChild("Eggs")
    return Eggs
end

local function fire(remote, ...)
    if not remote then return false, "remote missing" end
    local args = { ... }
    return pcall(function() remote:FireServer(unpack(args)) end)
end

-- SETTINGS
local HOME = Vector3.new(-176, 20, 620)
local DELAY_GUARDIAN = 1
local DELAY_EGG = 1
local DELAY_GRAB = 0.2
local DELAY_LOOP = 1
local LOAD_CHECK_DELAY = 1
local EGG_LOAD_TIMEOUT = 3
local MAX_GRAB_TRIES = 5
local SCAN_RANGE = 80
local MAX_AREA, MAX_RARITY = 57, 4

local PLACE_DELAY = 0        -- 0 = spam. If eggs get skipped, try 0.05
local PLACE_SPACING = 3
local HATCH_INTERVAL = 0.1
local RECORD_RANGE = 200

local running = true
local busy = false
local state = {
    AutoSteal = false,
    AutoClick = false,
    AutoHatch = false,
    LoadedOnly = false,
    Treadmill = true,
    Record = false,
    AntiAFK = true,
    ESP = false,
    ESPSelected = false,
    FilterArea = 0,
    SaveArea = 57,
    TpArea = 57,
    Speed = 450,
}
local selected = {}
local placePos = Vector3.new(-0.5714530944824219, 17.35000228881836, 648.2745361328125)

-- AREA POSITIONS (the guardians were removed, so positions live here)
local GUARDIAN_POS = {
    [57] = Vector3.new(3, 2510, 7763),
    -- [56] = Vector3.new(x, y, z),
}
local savedPos = {}
local POS_FILE = "HFE_positions.json"

local function persistPositions()
    if not writefile then return end
    local t = {}
    for a, p in pairs(savedPos) do t[tostring(a)] = { p.X, p.Y, p.Z } end
    pcall(function() writefile(POS_FILE, HttpService:JSONEncode(t)) end)
end

local function loadPositions()
    if not (isfile and readfile) then return end
    local ok = pcall(function()
        if isfile(POS_FILE) then
            local t = HttpService:JSONDecode(readfile(POS_FILE))
            for k, v in pairs(t) do
                local a = tonumber(k)
                if a and type(v) == "table" and #v == 3 then
                    savedPos[a] = Vector3.new(v[1], v[2], v[3])
                end
            end
        end
    end)
    if not ok then warn("[HFE] Could not read " .. POS_FILE) end
end
loadPositions()

local refreshSaved = function() end -- replaced when the UI is built

local function savePosition(area, pos)
    savedPos[area] = pos
    persistPositions()
    refreshSaved()
    print(string.format("[HFE] Saved area %d: [%d] = Vector3.new(%.1f, %.1f, %.1f),",
        area, area, pos.X, pos.Y, pos.Z))
end

-- HELPERS
local function getCFrame(obj)
    if obj:IsA("BasePart") then return obj.CFrame end
    if obj:IsA("Model") then return obj:GetPivot() end
    if obj:IsA("Attachment") then return obj.WorldCFrame end
    local p = obj:FindFirstChildWhichIsA("BasePart", true)
    return p and p.CFrame
end

local function guardianCFrameOf(obj)
    if obj:IsA("CFrameValue") then return obj.Value end
    if obj:IsA("Vector3Value") then return CFrame.new(obj.Value) end
    local cf = getCFrame(obj)
    if cf then return cf end
    local p = obj:GetAttribute("Position")
    if typeof(p) == "Vector3" then return CFrame.new(p) end
end

-- saved position > built-in position > old guardian folder (if it comes back)
local function getGuardianCFrame(area)
    local p = savedPos[area] or GUARDIAN_POS[area]
    if p then return CFrame.new(p) end
    local lw = SwimAdventure and SwimAdventure:FindFirstChild("LocalWorld")
    local gs = lw and lw:FindFirstChild("Guardians")
    local g = gs and gs:FindFirstChild("Guardian" .. area)
    if g then
        local cf = guardianCFrameOf(g)
        if cf then return cf end
    end
end

local function parse(name)
    local a, r = name:match("^Egg_(%d+)_(%d+)")
    if a then return tonumber(a), tonumber(r) end
end

local function getLoaded()
    local t = {}
    local folder = getEggsFolder()
    if not folder then return t end
    for _, v in ipairs(folder:GetChildren()) do
        local a, r = parse(v.Name)
        if a then t["Egg_" .. a .. "_" .. r] = v end
    end
    return t
end

local function eggNameOf(obj)
    local a = obj
    while a and a ~= workspace do
        local n = a.Name:match("^(Egg_%d+_%d+)")
        if n then return n end
        a = a.Parent
    end
end

local function findPrompt(eggObj, eggName, hrp)
    local p = eggObj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if p then return p end
    local best, bestDist, any, anyDist
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("ProximityPrompt") and v.Enabled and v.ActionText:lower():find("steal") then
            local cf = v.Parent and getCFrame(v.Parent)
            if cf then
                local d = (cf.Position - hrp.Position).Magnitude
                if d <= SCAN_RANGE then
                    if eggNameOf(v.Parent) == eggName and (not bestDist or d < bestDist) then
                        best, bestDist = v, d
                    end
                    if not anyDist or d < anyDist then any, anyDist = v, d end
                end
            end
        end
    end
    return best or any
end

local function triggerPrompt(prompt, hrp)
    prompt.RequiresLineOfSight = false
    prompt.MaxActivationDistance = 60
    local hold = prompt.HoldDuration
    local cf = getCFrame(prompt.Parent)
    if cf then
        hrp.CFrame = cf + Vector3.new(0, 2, 0)
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
    task.wait(0.2)
    for _ = 1, 3 do
        if not running then return end
        if fireproximityprompt then pcall(fireproximityprompt, prompt) end
        pcall(function()
            prompt:InputHoldBegin()
            task.wait(math.max(hold, 0) + 0.15)
            prompt:InputHoldEnd()
        end)
        task.wait(0.2)
    end
end

local currentTween
local function tweenTo(hrp, pos)
    local dist = (hrp.Position - pos).Magnitude
    local time = math.max(dist / math.clamp(state.Speed, 1, 1000), 0.05)
    currentTween = TweenService:Create(hrp, TweenInfo.new(time, Enum.EasingStyle.Linear), {CFrame = CFrame.new(pos)})
    currentTween:Play()
    currentTween.Completed:Wait()
end

local function holdAt(hrp, cf, seconds, requireAuto)
    local t = os.clock()
    while os.clock() - t < seconds do
        if not running or (requireAuto and not state.AutoSteal) then return false end
        hrp.CFrame = cf
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.1)
    end
    return true
end

local function itemCount()
    local n = 0
    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then n = n + #bp:GetChildren() end
    local char = player.Character
    if char then
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Tool") then n = n + 1 end
        end
    end
    return n
end

-- ANTI AFK
local idledConn = player.Idled:Connect(function()
    if state.AntiAFK then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
        print("[HFE] Anti AFK: kept you in the game")
    end
end)

-- TREADMILL (the remote is a toggle)
local treadmillOn = false
local function setTreadmill(want)
    if want and not state.Treadmill then return end
    if want == treadmillOn then return end
    local ok, err = fire(ActionRemote, "PortableTreadmill")
    if ok then treadmillOn = want end
    print("[HFE] Treadmill", want and "ON" or "OFF", "| ok:", ok, err or "")
end

-- turn the treadmill off the moment a selected egg spawns
task.spawn(function()
    local folder
    for _ = 1, 30 do
        folder = getEggsFolder()
        if folder then break end
        task.wait(1)
    end
    if not folder then
        warn("[HFE] workspace.LocalNests.Eggs not found")
        return
    end
    folder.ChildAdded:Connect(function(child)
        if state.AutoSteal and selected[child.Name] then
            setTreadmill(false)
        end
    end)
end)

-- AREA POSITION > 1s > EGG > 1s > GRAB (verified) > 0.2s > TWEEN HOME only if obtained
local function stealEgg(eggName, requireAuto)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local area = parse(eggName)
    local guardianCF = getGuardianCFrame(area)
    if not guardianCF then
        warn("[HFE] No position for area " .. tostring(area) .. ". Use SAVE POSITION or RECORD COORDS.")
        return false
    end

    local guardianPos = guardianCF + Vector3.new(0, 3, 0)
    hrp.CFrame = guardianPos
    if not holdAt(hrp, guardianPos, DELAY_GUARDIAN, requireAuto) then return false end

    local eggObj = getLoaded()[eggName]
    local deadline = os.clock() + EGG_LOAD_TIMEOUT
    while not eggObj and os.clock() < deadline do
        if not running or (requireAuto and not state.AutoSteal) then return false end
        hrp.CFrame = guardianPos
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.2)
        eggObj = getLoaded()[eggName]
    end
    if not (eggObj and eggObj.Parent) then
        print("[HFE]", eggName, "did not load at area", area)
        return false
    end

    setTreadmill(false)

    local got = false
    for try = 1, MAX_GRAB_TRIES do
        if not running or (requireAuto and not state.AutoSteal) then return false end
        if not eggObj.Parent then
            print("[HFE]", eggName, "is gone (taken or unloaded)")
            break
        end

        local eggCF = getCFrame(eggObj)
        if not eggCF then break end

        local before = itemCount()
        hrp.CFrame = eggCF
        if not holdAt(hrp, eggCF, DELAY_EGG, requireAuto) then return false end

        local prompt = findPrompt(eggObj, eggName, hrp)
        if prompt then triggerPrompt(prompt, hrp) end

        local ok, result = pcall(function()
            return EggGrab:InvokeServer(unpack({ eggName }))
        end)
        print("[HFE] Grab", eggName, "try", try, "| ok:", ok, "| result:", result,
            "| prompt:", prompt and "yes" or "no")

        task.wait(DELAY_GRAB)

        local reason
        if ok and result == true then
            reason = "server returned true"
        elseif itemCount() > before then
            reason = "new item in inventory"
        elseif not eggObj.Parent then
            reason = "egg removed after grab"
        end
        if reason then
            print("[HFE] Egg obtained (" .. reason .. ")")
            got = true
            break
        end
        print("[HFE] Egg NOT obtained, retrying...")
    end

    if got then
        if running and (not requireAuto or state.AutoSteal) then
            tweenTo(hrp, HOME)
        end
    else
        print("[HFE] Egg not obtained, staying here (no tween)")
    end
    return got
end

local function sortedSelected()
    local arr = {}
    for name in pairs(selected) do table.insert(arr, name) end
    table.sort(arr, function(x, y)
        local a1, r1 = parse(x)
        local a2, r2 = parse(y)
        if a1 ~= a2 then return a1 > a2 end
        return r1 > r2
    end)
    return arr
end

-- AUTO STEAL LOOP
task.spawn(function()
    while running do
        if state.AutoSteal and not busy then
            local list = sortedSelected()
            if #list == 0 then
                setTreadmill(true)
                task.wait(0.2)
            else
                busy = true
                local any = false
                for _, name in ipairs(list) do
                    if not running or not state.AutoSteal then break end
                    if selected[name] then
                        local ok, res = pcall(stealEgg, name, true)
                        if not ok then
                            warn("[HFE] Error:", res)
                        elseif res then
                            any = true
                        end
                        task.wait(DELAY_LOOP)
                    end
                end
                busy = false
                if not any and running and state.AutoSteal then
                    setTreadmill(true)
                end
            end
        else
            task.wait(0.2)
        end
    end
end)

task.spawn(function()
    while running do
        if state.AutoClick and ClickRemote then
            pcall(function() ClickRemote:FireServer() end)
            task.wait()
        else
            task.wait(0.1)
        end
    end
end)

-- RECORD COORDS: while ON, saves your position for any area whose egg is loaded near you
local recorded = {}
task.spawn(function()
    while running do
        if state.Record then
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                for name, obj in pairs(getLoaded()) do
                    local a = parse(name)
                    local cf = obj.Parent and getCFrame(obj)
                    if a and cf and not recorded[a]
                        and (cf.Position - hrp.Position).Magnitude <= RECORD_RANGE then
                        recorded[a] = true
                        savePosition(a, hrp.Position)
                    end
                end
            end
        end
        task.wait(1)
    end
end)

-- =========================
-- PLACE EGG ALL + AUTO HATCH
-- =========================
local function isGuid(s)
    return type(s) == "string"
        and s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

local ID_KEYS = { "Id", "ID", "Guid", "GUID", "EggId", "Uuid", "UUID" }

local function findGuid(obj)
    if isGuid(obj.Name) then return obj.Name end
    for _, v in pairs(obj:GetAttributes()) do
        if isGuid(v) then return v end
    end
    for _, c in ipairs(obj:GetDescendants()) do
        if c:IsA("StringValue") and isGuid(c.Value) then return c.Value end
        for _, v in pairs(c:GetAttributes()) do
            if isGuid(v) then return v end
        end
    end
end

local function getEggTools()
    local list = {}
    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t.Name:lower():find("egg") then table.insert(list, t) end
        end
    end
    local char = player.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and t.Name:lower():find("egg") then table.insert(list, t) end
        end
    end
    return list
end

local function getAmount(tool)
    for _, k in ipairs({ "Amount", "Count", "Quantity", "Stack" }) do
        local v = tool:GetAttribute(k)
        if type(v) == "number" then return v end
        local c = tool:FindFirstChild(k)
        if c and (c:IsA("IntValue") or c:IsA("NumberValue")) then return c.Value end
    end
    local n = tool.Name:match("x(%d+)%s*$")
    return n and tonumber(n) or nil
end

local function totalAmount(tools)
    local n = 0
    for _, t in ipairs(tools) do n = n + (getAmount(t) or 1) end
    return n
end

-- PLACE EGG ALL (spam, no delay)
local placing = false
local function placeAllEggs()
    if placing or busy then
        print("[HFE] Busy, try again in a moment")
        return
    end
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return end

    placing, busy = true, true
    local origin = hrp.CFrame
    hrp.CFrame = CFrame.new(placePos + Vector3.new(0, 5, 0))
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.2)

    local placed = 0
    for _ = 1, 10 do
        local tools = getEggTools()
        if #tools == 0 then break end
        local before = totalAmount(tools)

        for _, tool in ipairs(tools) do
            if not running then break end
            if tool.Parent then
                pcall(function() hum:EquipTool(tool) end)
                task.wait(0.1)
                for _ = 1, math.min(getAmount(tool) or 1, 200) do
                    if not running or not tool.Parent then break end
                    local offset = Vector3.new((placed % 5) * PLACE_SPACING, 0, math.floor(placed / 5) * PLACE_SPACING)
                    fire(ActionRemote, "Place", "Egg", placePos + offset)
                    placed = placed + 1
                    if PLACE_DELAY > 0 then task.wait(PLACE_DELAY) end
                end
            end
        end

        task.wait(0.1)
        if totalAmount(getEggTools()) >= before then break end
    end

    hrp.CFrame = origin
    hrp.AssemblyLinearVelocity = Vector3.zero
    print("[HFE] Place all done, placed:", placed)
    placing, busy = false, false
end

-- AUTO HATCH: ids from your tools AND from placed eggs in the world
local worldIds, lastWorldScan = {}, 0
local function scanWorldIds()
    if os.clock() - lastWorldScan < 2 then return worldIds end
    lastWorldScan = os.clock()
    local ids = {}
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    for _, d in ipairs(workspace:GetDescendants()) do
        local id
        if #d.Name == 36 and isGuid(d.Name) then
            id = d.Name
        elseif d:IsA("Model") or d:IsA("Folder") then
            for _, k in ipairs(ID_KEYS) do
                local v = d:GetAttribute(k)
                if isGuid(v) then id = v break end
            end
        end
        if id then
            local near = true
            if d:IsA("BasePart") or d:IsA("Model") then
                local cf = getCFrame(d)
                if cf then
                    near = (cf.Position - placePos).Magnitude <= 150
                        or (hrp ~= nil and (cf.Position - hrp.Position).Magnitude <= 150)
                end
            end
            if near then ids[id] = true end
        end
    end
    worldIds = ids
    return ids
end

local hatchLogged = {}
task.spawn(function()
    while running do
        if state.AutoHatch then
            local ids = {}
            for _, tool in ipairs(getEggTools()) do
                local id = findGuid(tool)
                if id then ids[id] = true end
            end
            for id in pairs(scanWorldIds()) do ids[id] = true end

            for id in pairs(ids) do
                if not running or not state.AutoHatch then break end
                fire(ActionRemote, "OpenEgg", id)
                if not hatchLogged[id] then
                    hatchLogged[id] = true
                    print("[HFE] OpenEgg id:", id)
                end
                task.wait()
            end
        end
        task.wait(HATCH_INTERVAL)
    end
end)

local function dumpEggs()
    print("[HFE] ===== EGG DUMP =====")
    for _, t in ipairs(getEggTools()) do
        print("[HFE] Tool:", t:GetFullName(), "| amount:", getAmount(t), "| id:", findGuid(t))
        for k, v in pairs(t:GetAttributes()) do print("[HFE]    attr", k, "=", v) end
        for _, c in ipairs(t:GetChildren()) do print("[HFE]    child", c.Name, c.ClassName) end
    end
    lastWorldScan = 0
    for id in pairs(scanWorldIds()) do print("[HFE] World egg id:", id) end
    local roots = { player }
    if player.Character then table.insert(roots, player.Character) end
    for _, root in ipairs(roots) do
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("StringValue") and isGuid(d.Value) then
                print("[HFE] GUID value:", d:GetFullName(), "=", d.Value)
            end
            for k, v in pairs(d:GetAttributes()) do
                if isGuid(v) then print("[HFE] GUID attr:", d:GetFullName(), k, "=", v) end
            end
        end
    end
    print("[HFE] Place position:", placePos)
    print("[HFE] ===== END =====")
end

local function allPositions()
    local merged = {}
    for a, p in pairs(GUARDIAN_POS) do merged[a] = p end
    for a, p in pairs(savedPos) do merged[a] = p end
    return merged
end

local function teleportToArea(a)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local cf = getGuardianCFrame(a)
    if not cf then
        warn("[HFE] No position for area " .. tostring(a))
        return
    end
    hrp.CFrame = cf + Vector3.new(0, 3, 0)
    hrp.AssemblyLinearVelocity = Vector3.zero
end

-- =========================
-- UI (landscape, left nav bar)
-- =========================
local parent
do
    local ok, h = pcall(function() return gethui and gethui() end)
    if ok and h then parent = h end
    if not parent then
        local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
        if ok2 then parent = cg end
    end
    if not parent then parent = player:WaitForChild("PlayerGui") end
end
for _, p in ipairs({ parent, player:FindFirstChild("PlayerGui") }) do
    local old = p and p:FindFirstChild("HFE_UI")
    if old then old:Destroy() end
end

local gui = Instance.new("ScreenGui")
gui.Name = "HFE_UI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
local okParent = pcall(function() gui.Parent = parent end)
if not okParent or not gui.Parent then gui.Parent = player:WaitForChild("PlayerGui") end

local FULL_SIZE = UDim2.fromOffset(600, 300)
local MINI_SIZE = UDim2.fromOffset(120, 28)
local NAV_W = 110

local frame = Instance.new("Frame")
frame.Size = FULL_SIZE
frame.Position = UDim2.fromOffset(40, 20)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local content = Instance.new("Frame")
content.Size = UDim2.fromScale(1, 1)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.Parent = frame

-- title bar
local title = Instance.new("Frame")
title.Size = UDim2.new(1, 0, 0, 28)
title.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
title.BorderSizePixel = 0
title.ZIndex = 5
title.Parent = frame
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

local logo = Instance.new("TextLabel")
logo.Size = UDim2.fromOffset(46, 20)
logo.Position = UDim2.fromOffset(6, 4)
logo.BackgroundColor3 = Color3.fromRGB(150, 100, 30)
logo.BorderSizePixel = 0
logo.Text = "HFE"
logo.TextColor3 = Color3.new(1, 1, 1)
logo.Font = Enum.Font.GothamBlack
logo.TextSize = 14
logo.ZIndex = 6
logo.Parent = title
Instance.new("UICorner", logo).CornerRadius = UDim.new(0, 5)

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(1, -120, 1, 0)
titleText.Position = UDim2.fromOffset(58, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "Egg Hub (drag me)"
titleText.TextColor3 = Color3.new(1, 1, 1)
titleText.Font = Enum.Font.GothamBold
titleText.TextSize = 13
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.ZIndex = 6
titleText.Parent = title

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.fromOffset(30, 20)
minBtn.Position = UDim2.new(1, -36, 0, 4)
minBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
minBtn.BorderSizePixel = 0
minBtn.Text = "-"
minBtn.TextColor3 = Color3.new(1, 1, 1)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 18
minBtn.ZIndex = 6
minBtn.Parent = title
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 5)

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    titleText.Visible = not minimized
    frame.Size = minimized and MINI_SIZE or FULL_SIZE
    minBtn.Text = minimized and "+" or "-"
end)

do
    local dragging, dragStart, startPos
    title.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, frame.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local ON, OFF = Color3.fromRGB(60, 170, 90), Color3.fromRGB(170, 60, 60)
local GRAY = Color3.fromRGB(70, 70, 90)
local BLUE = Color3.fromRGB(50, 100, 170)
local GOLD = Color3.fromRGB(150, 100, 30)

-- UI helpers (take a parent so each tab has its own page)
local function makeButton(par, text, x, y, w, h, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, h)
    b.Position = UDim2.fromOffset(x, y)
    b.BackgroundColor3 = color
    b.BorderSizePixel = 0
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Parent = par
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local function makeLabel(par, text, x, y, w, h, size, color, bold)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromOffset(w, h)
    l.Position = UDim2.fromOffset(x, y)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or Color3.new(1, 1, 1)
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextSize = size or 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Top
    l.TextWrapped = true
    l.Parent = par
    return l
end

local function makeToggle(par, text, x, y, w, key, onChange)
    local b = makeButton(par, "", x, y, w, 28, OFF)
    if w < 150 then b.TextSize = 11 end
    local function refresh()
        b.Text = text .. ": " .. (state[key] and "ON" or "OFF")
        b.BackgroundColor3 = state[key] and ON or OFF
    end
    b.MouseButton1Click:Connect(function()
        state[key] = not state[key]
        if onChange then onChange(state[key]) end
        refresh()
    end)
    refresh()
    return b
end

local function makeInput(par, labelText, x, y, w, key, minV, maxV, onChange)
    makeLabel(par, labelText, x, y, w, 12, 10)
    local box = Instance.new("TextBox")
    box.Size = UDim2.fromOffset(w, 24)
    box.Position = UDim2.fromOffset(x, y + 13)
    box.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    box.BorderSizePixel = 0
    box.Text = tostring(state[key])
    box.TextColor3 = Color3.new(1, 1, 1)
    box.Font = Enum.Font.Gotham
    box.TextSize = 14
    box.ClearTextOnFocus = false
    box.Parent = par
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then state[key] = math.clamp(math.floor(n), minV, maxV) end
        box.Text = tostring(state[key])
        if onChange then onChange() end
    end)
end

-- LEFT NAV BAR + PAGES
local nav = Instance.new("Frame")
nav.Size = UDim2.new(0, NAV_W, 1, -28)
nav.Position = UDim2.fromOffset(0, 28)
nav.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
nav.BorderSizePixel = 0
nav.Parent = content

local pagesHolder = Instance.new("Frame")
pagesHolder.Size = UDim2.new(1, -NAV_W, 1, -28)
pagesHolder.Position = UDim2.fromOffset(NAV_W, 28)
pagesHolder.BackgroundTransparency = 1
pagesHolder.BorderSizePixel = 0
pagesHolder.Parent = content

local pages, navBtns = {}, {}
local function showPage(name)
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, b in pairs(navBtns) do
        b.BackgroundColor3 = (n == name) and GOLD or Color3.fromRGB(45, 45, 58)
    end
end

local TABS = { "MAIN", "AUTO", "TELEPORT", "SETTING", "VISUAL" }
for i, name in ipairs(TABS) do
    local p = Instance.new("Frame")
    p.Size = UDim2.fromScale(1, 1)
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.Visible = false
    p.Parent = pagesHolder
    pages[name] = p

    local b = makeButton(nav, name, 6, 6 + (i - 1) * 38, NAV_W - 12, 32, Color3.fromRGB(45, 45, 58))
    b.TextSize = 12
    b.MouseButton1Click:Connect(function() showPage(name) end)
    navBtns[name] = b
end

-- nav bottom: EXIT + version
local exitBtn = makeButton(nav, "EXIT", 6, 204, NAV_W - 12, 26, Color3.fromRGB(120, 40, 40))
makeLabel(nav, "Version 1.7 by imrealsurvivor", 6, 236, NAV_W - 12, 28, 9, Color3.fromRGB(170, 170, 185))

-- =========================
-- MAIN TAB (stealing area)
-- =========================
local main = pages.MAIN
local updateList

makeLabel(main, "STEAL EGG  (● = loaded now)", 6, 4, 210, 16, 11, nil, true)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.fromOffset(210, 196)
scroll.Position = UDim2.fromOffset(6, 22)
scroll.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = main
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)
local layout = Instance.new("UIListLayout", scroll)
layout.Padding = UDim.new(0, 3)
layout.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new("UIPadding", scroll)
pad.PaddingTop, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 3), UDim.new(0, 3), UDim.new(0, 8)

local buttons = {}
for a = MAX_AREA, 1, -1 do
    for r = MAX_RARITY, 1, -1 do
        local name = "Egg_" .. a .. "_" .. r
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 26)
        b.BorderSizePixel = 0
        b.Font = Enum.Font.Gotham
        b.TextSize = 13
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Parent = scroll
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        b.MouseButton1Click:Connect(function()
            selected[name] = not selected[name] or nil
            updateList()
        end)
        buttons[name] = {btn = b, area = a, rarity = r}
    end
end

updateList = function()
    local loaded = getLoaded()
    for name, d in pairs(buttons) do
        local isLoaded = loaded[name] ~= nil
        local show = (state.FilterArea == 0 or d.area == state.FilterArea)
            and (not state.LoadedOnly or isLoaded or selected[name])
        d.btn.Visible = show and true or false
        d.btn.LayoutOrder = (isLoaded and 0 or 100000) + (MAX_AREA + 1 - d.area) * 10 + (MAX_RARITY + 1 - d.rarity)
        d.btn.Text = (isLoaded and "● " or "   ") .. name:upper() .. (selected[name] and "  ✔" or "")
        d.btn.BackgroundColor3 = selected[name] and ON
            or (isLoaded and Color3.fromRGB(50, 85, 60) or Color3.fromRGB(55, 55, 68))
        d.btn.TextTransparency = isLoaded and 0 or 0.35
    end
end

task.spawn(function()
    while running do
        pcall(updateList)
        task.wait(LOAD_CHECK_DELAY)
    end
end)

local clearBtn = makeButton(main, "Clear Selection", 6, 224, 210, 28, GRAY)
clearBtn.MouseButton1Click:Connect(function()
    selected = {}
    updateList()
end)

makeToggle(main, "Auto Steal Egg", 226, 4, 256, "AutoSteal", function(on)
    if not on then
        if currentTween then currentTween:Cancel() end
        setTreadmill(false)
    end
end)

local stealNow = makeButton(main, "STEAL SELECTED NOW", 226, 38, 256, 28, BLUE)
stealNow.MouseButton1Click:Connect(function()
    if busy then return end
    task.spawn(function()
        busy = true
        for _, name in ipairs(sortedSelected()) do
            if not running then break end
            local ok, err = pcall(stealEgg, name, false)
            if not ok then warn("[HFE] Error:", err) end
            task.wait(DELAY_LOOP)
        end
        busy = false
    end)
end)

makeToggle(main, "Loaded Only", 226, 72, 256, "LoadedOnly", function() updateList() end)
makeInput(main, "Show Area (0=all)", 226, 108, 124, "FilterArea", 0, MAX_AREA, function() updateList() end)
makeInput(main, "Tween Speed (1-1000)", 358, 108, 124, "Speed", 1, 1000)
makeLabel(main, "Flow: area position > egg > grab > tween home. Highest area goes first. Areas need a saved position (TELEPORT tab).",
    226, 152, 256, 60, 10, Color3.fromRGB(170, 170, 185))

-- =========================
-- AUTO TAB (treadmill, hatch, place)
-- =========================
local auto = pages.AUTO
makeLabel(auto, "AUTOMATION", 6, 4, 230, 16, 11, nil, true)
makeToggle(auto, "Treadmill (while waiting)", 6, 22, 230, "Treadmill", function(on)
    if not on then setTreadmill(false) end
end)
makeToggle(auto, "Auto Hatch", 6, 56, 230, "AutoHatch")
makeToggle(auto, "Auto Click", 6, 90, 230, "AutoClick")
makeLabel(auto, "Treadmill turns on while Auto Steal waits for an egg and turns off when your egg spawns.",
    6, 126, 230, 50, 10, Color3.fromRGB(170, 170, 185))

makeLabel(auto, "PLACE EGGS", 246, 4, 230, 16, 11, nil, true)
local placeBtn = makeButton(auto, "PLACE EGG ALL (spam)", 246, 22, 230, 28, BLUE)
placeBtn.MouseButton1Click:Connect(function()
    task.spawn(placeAllEggs)
end)

local posLabel = makeLabel(auto, "", 246, 56, 230, 14, 10, Color3.fromRGB(170, 170, 185))
local function refreshPosLabel()
    posLabel.Text = string.format("Place at: %.1f, %.1f, %.1f", placePos.X, placePos.Y, placePos.Z)
end
refreshPosLabel()

local setPosBtn = makeButton(auto, "SET PLACE POS (here)", 246, 74, 230, 28, GRAY)
setPosBtn.MouseButton1Click:Connect(function()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = { char }
    params.FilterType = Enum.RaycastFilterType.Exclude
    local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -20, 0), params)
    placePos = hit and hit.Position or (hrp.Position - Vector3.new(0, 3, 0))
    refreshPosLabel()
    print("[HFE] Place position set:", placePos)
end)

local dumpBtn = makeButton(auto, "DUMP EGG INFO (F9)", 246, 108, 230, 28, GRAY)
dumpBtn.MouseButton1Click:Connect(function()
    task.spawn(dumpEggs)
end)

-- =========================
-- TELEPORT TAB (positions)
-- =========================
local tp = pages.TELEPORT
makeLabel(tp, "SAVE / RECORD", 6, 4, 230, 14, 11, nil, true)
makeInput(tp, "Save area (1-57)", 6, 22, 110, "SaveArea", 1, MAX_AREA)
local saveBtn = makeButton(tp, "SAVE POSITION", 122, 35, 114, 24, GOLD)
saveBtn.TextSize = 11
saveBtn.MouseButton1Click:Connect(function()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    savePosition(state.SaveArea, hrp.Position)
end)

makeToggle(tp, "Record Coords", 6, 68, 230, "Record", function(on)
    if on then recorded = {} end
end)

local copyBtn = makeButton(tp, "COPY ALL POSITIONS", 6, 102, 230, 28, GRAY)
copyBtn.MouseButton1Click:Connect(function()
    local keys = {}
    for a in pairs(allPositions()) do table.insert(keys, a) end
    table.sort(keys)
    local lines = {}
    local all = allPositions()
    for _, a in ipairs(keys) do
        local p = all[a]
        table.insert(lines, string.format("[%d] = Vector3.new(%.1f, %.1f, %.1f),", a, p.X, p.Y, p.Z))
    end
    local text = table.concat(lines, "\n")
    print("[HFE] ===== POSITIONS =====\n" .. text)
    if setclipboard then pcall(setclipboard, text) end
end)

local savedLabel = makeLabel(tp, "", 6, 136, 230, 14, 10, Color3.fromRGB(170, 170, 185))
refreshSaved = function()
    local n = 0
    for _ in pairs(allPositions()) do n = n + 1 end
    savedLabel.Text = "Areas with a position: " .. n .. " / " .. MAX_AREA
end
refreshSaved()

makeLabel(tp, "GO TO", 246, 4, 230, 14, 11, nil, true)
makeInput(tp, "Teleport area (1-57)", 246, 22, 110, "TpArea", 1, MAX_AREA)
local goBtn = makeButton(tp, "TELEPORT", 362, 35, 114, 24, BLUE)
goBtn.TextSize = 11
goBtn.MouseButton1Click:Connect(function()
    teleportToArea(state.TpArea)
end)

local homeBtn = makeButton(tp, "GO HOME (tween)", 246, 68, 230, 28, GRAY)
homeBtn.MouseButton1Click:Connect(function()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    task.spawn(tweenTo, hrp, HOME)
end)

local placeGoBtn = makeButton(tp, "GO TO PLACE POS", 246, 102, 230, 28, GRAY)
placeGoBtn.MouseButton1Click:Connect(function()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    hrp.CFrame = CFrame.new(placePos + Vector3.new(0, 5, 0))
end)

makeLabel(tp, "Stand in an area, pick its number and tap SAVE POSITION. Or turn Record Coords on and walk near eggs.",
    246, 138, 230, 50, 10, Color3.fromRGB(170, 170, 185))

-- =========================
-- SETTING TAB
-- =========================
local setting = pages.SETTING
makeLabel(setting, "SETTINGS", 6, 4, 230, 16, 11, nil, true)
makeToggle(setting, "Anti AFK", 6, 22, 230, "AntiAFK")
makeLabel(setting, "Anti AFK stops the game from kicking you for being idle (for example while the treadmill runs).",
    6, 56, 230, 50, 10, Color3.fromRGB(170, 170, 185))

-- =========================
-- VISUAL TAB (ESP)
-- =========================
local visual = pages.VISUAL
local espFolder = Instance.new("Folder")
espFolder.Name = "HFE_ESP"
espFolder.Parent = gui
local espItems = {}
local RARITY_COLORS = {
    Color3.fromRGB(230, 230, 230),
    Color3.fromRGB(90, 220, 110),
    Color3.fromRGB(100, 160, 255),
    Color3.fromRGB(255, 200, 60),
}

local function clearESP()
    for _, it in pairs(espItems) do it.gui:Destroy() end
    espItems = {}
end

local function espPart(obj)
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChildWhichIsA("BasePart", true)
end

makeLabel(visual, "ESP", 6, 4, 230, 16, 11, nil, true)
makeToggle(visual, "Egg ESP", 6, 22, 230, "ESP", function(on)
    if not on then clearESP() end
end)
makeToggle(visual, "Selected eggs only", 6, 56, 230, "ESPSelected")
makeLabel(visual, "Shows every loaded egg through walls with its name and distance. Colors: white = rarity 1, green = 2, blue = 3, gold = 4.",
    6, 92, 230, 70, 10, Color3.fromRGB(170, 170, 185))

task.spawn(function()
    while running do
        if state.ESP then
            pcall(function()
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                local wanted = {}
                for name, obj in pairs(getLoaded()) do
                    if not state.ESPSelected or selected[name] then
                        wanted[obj] = name
                    end
                end
                for obj, it in pairs(espItems) do
                    if not wanted[obj] or not obj.Parent then
                        it.gui:Destroy()
                        espItems[obj] = nil
                    end
                end
                for obj, name in pairs(wanted) do
                    local it = espItems[obj]
                    if not it then
                        local part = espPart(obj)
                        if part then
                            local _, r = parse(name)
                            local color = RARITY_COLORS[r] or RARITY_COLORS[1]
                            local b = Instance.new("BillboardGui")
                            b.Name = "esp"
                            b.Adornee = part
                            b.AlwaysOnTop = true
                            b.Size = UDim2.fromOffset(150, 30)
                            b.StudsOffset = Vector3.new(0, 4, 0)
                            local l = Instance.new("TextLabel")
                            l.Size = UDim2.fromScale(1, 1)
                            l.BackgroundTransparency = 1
                            l.TextColor3 = color
                            l.TextStrokeTransparency = 0
                            l.Font = Enum.Font.GothamBold
                            l.TextSize = 14
                            l.Text = name:upper()
                            l.Parent = b
                            b.Parent = espFolder
                            it = { gui = b, label = l, part = part, name = name }
                            espItems[obj] = it
                        end
                    end
                    if it and hrp then
                        local d = (it.part.Position - hrp.Position).Magnitude
                        it.label.Text = string.format("%s  [%dm]", it.name:upper(), d)
                    end
                end
            end)
        else
            if next(espItems) then clearESP() end
        end
        task.wait(0.5)
    end
end)

-- EXIT
exitBtn.MouseButton1Click:Connect(function()
    state.AutoSteal = false
    state.AutoClick = false
    state.AutoHatch = false
    state.Record = false
    state.ESP = false
    setTreadmill(false)
    running = false
    if currentTween then currentTween:Cancel() end
    if idledConn then idledConn:Disconnect() end
    gui:Destroy()
    print("[HFE] Exited")
end)

showPage("MAIN")
print("[HFE] Menu loaded (1.7)")