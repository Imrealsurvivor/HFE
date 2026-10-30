local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local player = Players.LocalPlayer

local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)

print("[HFE] Starting 1.9...")

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
local NoticeRemote = waitFor(Remotes, "Notice", 5)

local Eggs
local function getEggsFolder()
    if Eggs and Eggs.Parent then return Eggs end
    local ln = workspace:FindFirstChild("LocalNests")
    Eggs = ln and ln:FindFirstChild("Eggs")
    return Eggs
end

-- fire an Action remote (selfFiring lets the spy ignore our own calls)
local selfFiring = false
local function fire(remote, ...)
    if not remote then return false, "remote missing" end
    local args = { ... }
    selfFiring = true
    local ok, err = pcall(function() remote:FireServer(unpack(args)) end)
    selfFiring = false
    return ok, err
end

-- SETTINGS
local HOME = Vector3.new(-176, 20, 620)      -- world 1 safe zone
local HOME2 = Vector3.new(-9, 1603, 4595)    -- world 2 (areas 48-57)
local WORLD2_FIRST_AREA = 48
local DELAY_GUARDIAN = 1
local DELAY_EGG = 1
local DELAY_GRAB = 0.2
local DELAY_LOOP = 1
local LOAD_CHECK_DELAY = 1
local EGG_LOAD_TIMEOUT = 3
local MAX_GRAB_TRIES = 5
local SECURE_WAIT = 1.5      -- wait this long for the "Egg secured!" notice after a grab
local SCAN_RANGE = 80
local MAX_AREA, MAX_RARITY = 57, 4

local PLACE_DELAY = 0        -- 0 = spam
local PLACE_PER_PASS = 200
local HATCH_INTERVAL = 0.2
local HATCH_COOLDOWN = 1     -- seconds between OpenEgg calls for the same id
local ID_SCAN_EVERY = 10
local ID_TTL = { scan = 90, remote = 600, manual = 10 }
local RECORD_RANGE = 200

local running = true
local busy = false
local state = {
    AutoSteal = false,
    AutoClick = false,
    AutoHatch = false,
    AutoPlace = false,
    PlaceClick = false,
    ReturnHome = false,
    LoadedOnly = false,
    Treadmill = true,
    AntiAFK = true,
    ESP = false,
    ESPSelected = false,
    FilterArea = 0,
    TpArea = 57,
    PlaceSpread = 8,
    Speed = 450,
}
local selected = {}
local placePos = Vector3.new(-16.860450744628906, 17.349998474121094, 595.48828125)
local refreshPosLabel = function() end -- replaced when the UI is built

-- AREA POSITIONS
local GUARDIAN_POS = {
    [1] = Vector3.new(109.3, 19.9, 574.5),
    [2] = Vector3.new(-5.1, 26.5, 437.5),
    [3] = Vector3.new(-5.1, 26.5, 437.5),
    [4] = Vector3.new(-0.2, 47.5, 210.5),
    [5] = Vector3.new(-0.2, 47.5, 210.5),
    [6] = Vector3.new(-2.1, 77.3, -12.9),
    [7] = Vector3.new(-9.9, 77.7, -46.8),
    [8] = Vector3.new(32.5, 116.3, -211.6),
    [9] = Vector3.new(17.9, 162.2, -507.7),
    [10] = Vector3.new(17.9, 162.2, -507.7),
    [11] = Vector3.new(18.4, 215.8, -782.6),
    [12] = Vector3.new(18.4, 215.8, -782.6),
    [13] = Vector3.new(8.9, 247.6, -1013.4),
    [14] = Vector3.new(19.4, 278.0, -1135.5),
    [15] = Vector3.new(29.2, 310.9, -1267.5),
    [16] = Vector3.new(8.7, 345.0, -1483.0),
    [17] = Vector3.new(-0.0, 406.1, -1673.0),
    [18] = Vector3.new(30.9, 468.4, -1998.3),
    [19] = Vector3.new(30.9, 468.4, -1998.3),
    [20] = Vector3.new(20.2, 540.5, -2301.7),
    [21] = Vector3.new(20.2, 540.5, -2301.7),
    [22] = Vector3.new(25.0, 584.3, -2523.4),
    [23] = Vector3.new(-38.2, 675.3, -2787.9),
    [24] = Vector3.new(-38.2, 675.3, -2787.9),
    [25] = Vector3.new(109.3, 19.9, 574.5),
    [26] = Vector3.new(405.2, 80.9, 668.8),
    [27] = Vector3.new(602.7, 125.4, 667.4),
    [28] = Vector3.new(785.0, 172.9, 673.0),
    [29] = Vector3.new(963.8, 226.9, 648.2),
    [30] = Vector3.new(1124.3, 282.4, 652.8),
    [31] = Vector3.new(1412.3, 346.4, 649.9),
    [32] = Vector3.new(1731.5, 446.2, 651.2),
    [33] = Vector3.new(2022.5, 542.2, 646.1),
    [34] = Vector3.new(2386.8, 614.6, 648.1),
    [35] = Vector3.new(-238.0, 57.6, 659.7),
    [36] = Vector3.new(-436.8, 83.0, 672.2),
    [37] = Vector3.new(-709.2, 174.8, 663.4),
    [38] = Vector3.new(-981.1, 263.2, 658.1),
    [39] = Vector3.new(-1256.6, 353.6, 668.1),
    [40] = Vector3.new(-1539.0, 428.1, 652.3),
    [41] = Vector3.new(-1830.1, 501.0, 669.0),
    [42] = Vector3.new(-2131.3, 576.1, 658.4),
    [43] = Vector3.new(-2427.9, 653.7, 653.1),
    [44] = Vector3.new(-2723.7, 730.5, 658.4),
    [45] = Vector3.new(-3009.2, 810.3, 650.9),
    [46] = Vector3.new(-3295.4, 891.5, 664.5),
    [47] = Vector3.new(-3587.2, 974.1, 674.6),
    [48] = Vector3.new(9.2, 1701.6, 4966.6),
    [49] = Vector3.new(-15.2, 1785.5, 5183.2),
    [50] = Vector3.new(-37.8, 1908.8, 5530.5),
    [51] = Vector3.new(22.9, 1979.3, 5946.6),
    [52] = Vector3.new(22.9, 1979.3, 5946.6),
    [53] = Vector3.new(24.7, 2065.3, 6270.6),
    [54] = Vector3.new(20.7, 2142.7, 6584.5),
    [55] = Vector3.new(-7.3, 2231.3, 6914.8),
    [56] = Vector3.new(40.9, 2352.0, 7288.8),
    [57] = Vector3.new(3.0, 2510.0, 7763.0),
}
local savedPos = {}          -- auto recorded positions (only for areas missing above)
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
    print(string.format("[HFE] Auto recorded area %d: [%d] = Vector3.new(%.1f, %.1f, %.1f),",
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

-- built-in position > auto recorded > old guardian folder (if it ever comes back)
local function getGuardianCFrame(area)
    local p = GUARDIAN_POS[area] or savedPos[area]
    if p then return CFrame.new(p) end
    local lw = SwimAdventure and SwimAdventure:FindFirstChild("LocalWorld")
    local gs = lw and lw:FindFirstChild("Guardians")
    local g = gs and gs:FindFirstChild("Guardian" .. area)
    if g then
        local cf = guardianCFrameOf(g)
        if cf then return cf end
    end
end

local function homeFor(area)
    if area and area >= WORLD2_FIRST_AREA then return HOME2 end
    return HOME
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

-- "EGG SECURED" DETECTION (Notice remote)
local securedCount = 0
if NoticeRemote and NoticeRemote:IsA("RemoteEvent") then
    NoticeRemote.OnClientEvent:Connect(function(msg)
        if running and type(msg) == "string" and msg:lower():find("egg secured", 1, true) then
            securedCount = securedCount + 1
            print("[HFE] Egg secured detected (#" .. securedCount .. ")")
        end
    end)
else
    warn("[HFE] Notice remote not found: using fallback checks instead of 'Egg secured'")
end

-- =========================
-- HATCH IDS
-- =========================
local function isGuid(s)
    return type(s) == "string" and #s == 36
        and s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

local knownIds = {}
local function countIds()
    local n = 0
    for _ in pairs(knownIds) do n = n + 1 end
    return n
end

local function addId(id, src, kind)
    local e = knownIds[id]
    if e then
        e.t = os.clock()
        if kind == "scan" then e.kind = "scan" end
        return
    end
    knownIds[id] = { t = os.clock(), last = 0, src = src, kind = kind or "scan" }
    print("[HFE] Hatch id found:", id, "|", src)
end

local function extractIds(v, src, kind, depth)
    depth = depth or 0
    local tv = type(v)
    if tv == "string" then
        if isGuid(v) then addId(v, src, kind) end
    elseif tv == "table" and depth < 5 then
        for k, x in pairs(v) do
            extractIds(k, src, kind, depth + 1)
            extractIds(x, src, kind, depth + 1)
        end
    end
end

local ID_KEYS = { "Id", "ID", "Guid", "GUID", "EggId", "EggID", "Uuid", "UUID" }

local function idFromInstance(d)
    if #d.Name == 36 and isGuid(d.Name) then return d.Name end
    if d:IsA("StringValue") and isGuid(d.Value) then return d.Value end
    if d:IsA("Model") or d:IsA("Folder") or d:IsA("Tool") or d:IsA("GuiButton") then
        for _, k in ipairs(ID_KEYS) do
            local v = d:GetAttribute(k)
            if isGuid(v) then return v end
        end
    end
end

local function scanRoot(root, label, nearOnly)
    local n = 0
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    for _, d in ipairs(root:GetDescendants()) do
        n = n + 1
        if n % 2000 == 0 then task.wait() end
        local id = idFromInstance(d)
        if id then
            local ok = true
            if nearOnly then
                local cf = (d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder")) and getCFrame(d)
                ok = cf and ((cf.Position - placePos).Magnitude <= 200
                    or (hrp ~= nil and (cf.Position - hrp.Position).Magnitude <= 200)) or false
            end
            if ok then addId(id, label .. ": " .. d:GetFullName(), "scan") end
        end
    end
end

local function scanForIds(deep)
    local ln = workspace:FindFirstChild("LocalNests")
    if ln then scanRoot(ln, "LocalNests", false) end
    scanRoot(player, "player", false)
    if SwimAdventure then
        for _, c in ipairs(SwimAdventure:GetChildren()) do
            if c ~= Remotes then scanRoot(c, "SwimAdventure." .. c.Name, false) end
        end
    end
    if deep then scanRoot(workspace, "workspace", true) end
end

-- finds where an id lives in the game (runs once, after you hatch an egg by hand)
local idSourceDone = false
local function findIdSource(id)
    if idSourceDone then return end
    idSourceDone = true
    local hits, n = 0, 0
    local function check(root)
        for _, d in ipairs(root:GetDescendants()) do
            n = n + 1
            if n % 2000 == 0 then task.wait() end
            local how
            if d.Name == id then
                how = "name"
            elseif d:IsA("StringValue") and d.Value == id then
                how = "StringValue"
            elseif (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text:find(id, 1, true) then
                how = "text"
            else
                for k, v in pairs(d:GetAttributes()) do
                    if v == id then how = "attribute " .. k end
                end
            end
            if how then
                hits = hits + 1
                if hits <= 15 then print("[HFE] ID source:", how, "|", d:GetFullName()) end
            end
        end
    end
    check(player)
    if SwimAdventure then check(SwimAdventure) end
    check(workspace)
    print("[HFE] ID source search done. matches:", hits,
        hits == 0 and "(the id is only sent by remotes)" or "")
end

-- listen to every remote event: the server may send egg ids through them
local hooked = {}
local function hookRemote(r)
    if hooked[r] then return end
    hooked[r] = true
    pcall(function()
        r.OnClientEvent:Connect(function(...)
            if running then extractIds({ ... }, "remote " .. r.Name, "remote") end
        end)
    end)
end

task.spawn(function()
    if not Remotes then return end
    for _, r in ipairs(Remotes:GetDescendants()) do
        if r:IsA("RemoteEvent") then hookRemote(r) end
    end
    Remotes.DescendantAdded:Connect(function(r)
        if r:IsA("RemoteEvent") then hookRemote(r) end
    end)
end)

-- SPY: learns from eggs you hatch / place by hand
local function learnPlace(v)
    placePos = v
    refreshPosLabel()
    print(string.format("[HFE] Learned place position from your placement: %.1f, %.1f, %.1f", v.X, v.Y, v.Z))
end

local function installSpy()
    if not (hookmetamethod and getnamecallmethod) then
        print("[HFE] Spy not supported by this executor (hookmetamethod missing). Skipping.")
        return
    end
    local old
    local wrap = newcclosure or function(f) return f end
    local ok, err = pcall(function()
        old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            local method = getnamecallmethod()
            if running and self == ActionRemote and not selfFiring
                and (method == "FireServer" or method == "fireServer")
                and not (checkcaller and checkcaller()) then
                local a, b, c = ...
                if a == "OpenEgg" and isGuid(b) then
                    task.defer(function()
                        addId(b, "your OpenEgg", "manual")
                        findIdSource(b)
                    end)
                elseif a == "Place" and b == "Egg" and typeof(c) == "Vector3" then
                    task.defer(learnPlace, c)
                end
            end
            return old(self, ...)
        end))
    end)
    if not ok then warn("[HFE] Spy failed: " .. tostring(err)) end
end
installSpy()

-- =========================
-- STEAL
-- =========================
-- AREA POSITION > 1s > EGG > 1s > GRAB > "Egg secured!" > next egg (no trip home)
local function stealEgg(eggName, requireAuto)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local area = parse(eggName)
    local guardianCF = getGuardianCFrame(area)
    if not guardianCF then
        warn("[HFE] No position for area " .. tostring(area) .. " yet. Walk near its eggs and it records automatically.")
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
        local securedBefore = securedCount
        hrp.CFrame = eggCF
        if not holdAt(hrp, eggCF, DELAY_EGG, requireAuto) then return false end

        local prompt = findPrompt(eggObj, eggName, hrp)
        if prompt then triggerPrompt(prompt, hrp) end

        local ok, result = pcall(function()
            return EggGrab:InvokeServer(unpack({ eggName }))
        end)
        print("[HFE] Grab", eggName, "try", try, "| ok:", ok, "| result:", result,
            "| prompt:", prompt and "yes" or "no")

        -- wait for the "Egg secured!" notice
        local t0 = os.clock()
        while securedCount == securedBefore and os.clock() - t0 < SECURE_WAIT do
            if not running or (requireAuto and not state.AutoSteal) then return false end
            task.wait(0.05)
        end
        task.wait(DELAY_GRAB)

        local reason
        if securedCount > securedBefore then
            reason = "Egg secured notice"
        elseif ok and result == true then
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
        if state.ReturnHome and running and (not requireAuto or state.AutoSteal) then
            tweenTo(hrp, homeFor(area))
        end
    else
        print("[HFE] Egg not obtained, staying here")
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

-- =========================
-- PLACE EGGS (reads your hotbar)
-- =========================
local KEYS = {
    Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
    Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}

local function tapKey(kc)
    if not (VIM and kc) then return false end
    return pcall(function()
        VIM:SendKeyEvent(true, kc, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, kc, false, game)
    end)
end

local function isShown(obj)
    local n = obj
    while n and n ~= game do
        if n:IsA("GuiObject") and not n.Visible then return false end
        if n:IsA("ScreenGui") and not n.Enabled then return false end
        n = n.Parent
    end
    return true
end

-- hotbar slots: finds the "x1", "x2" count labels and the slot number next to each
local function scanHotbar()
    local out, seen = {}, {}
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return out end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") then
            local c = d.Text:match("^%s*[xX]%s*(%d+)%s*$")
            if c and isShown(d) then
                local node = d.Parent
                for _ = 1, 3 do
                    if not node or node == pg then break end
                    local counts, digit = 0, nil
                    for _, c2 in ipairs(node:GetDescendants()) do
                        if c2:IsA("TextLabel") then
                            if c2.Text:match("^%s*[xX]%s*%d+%s*$") then
                                counts = counts + 1
                            elseif not digit then
                                local dg = c2.Text:match("^%s*(%d)%s*$")
                                if dg then digit = tonumber(dg) end
                            end
                        end
                    end
                    if counts > 1 then break end
                    if digit then
                        if not seen[digit] then
                            seen[digit] = true
                            table.insert(out, { slot = digit, count = tonumber(c) })
                        end
                        break
                    end
                    node = node.Parent
                end
            end
        end
    end
    -- fallback: no slot numbers found, rank the count labels left to right
    if #out == 0 then
        local labels = {}
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("TextLabel") then
                local c = d.Text:match("^%s*[xX]%s*(%d+)%s*$")
                if c and isShown(d) then
                    table.insert(labels, { x = d.AbsolutePosition.X, y = d.AbsolutePosition.Y, count = tonumber(c) })
                end
            end
        end
        table.sort(labels, function(a, b)
            if math.abs(a.y - b.y) > 20 then return a.y < b.y end
            return a.x < b.x
        end)
        for i, l in ipairs(labels) do table.insert(out, { slot = i, count = l.count }) end
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end

local function slotCount(slot)
    for _, s in ipairs(scanHotbar()) do
        if s.slot == slot then return s.count end
    end
    return 0
end

local function randPos()
    local r = math.max(state.PlaceSpread, 0)
    return placePos + Vector3.new((math.random() * 2 - 1) * r, 0, (math.random() * 2 - 1) * r)
end

-- click the ground: camera looks down at the target, then a click on the screen center
local savedCamType
local function clickPlace(pos)
    local cam = workspace.CurrentCamera
    if not (cam and VIM) then return false end
    if not savedCamType then
        savedCamType = cam.CameraType
        cam.CameraType = Enum.CameraType.Scriptable
    end
    cam.CFrame = CFrame.new(pos + Vector3.new(0, 35, 10), pos)
    task.wait(0.08)
    local vs = cam.ViewportSize
    return pcall(function()
        VIM:SendMouseButtonEvent(vs.X / 2, vs.Y / 2, 0, true, game, 0)
        task.wait(0.03)
        VIM:SendMouseButtonEvent(vs.X / 2, vs.Y / 2, 0, false, game, 0)
    end)
end

local function restoreCam()
    local cam = workspace.CurrentCamera
    if cam and savedCamType then
        cam.CameraType = savedCamType
        savedCamType = nil
    end
end

local function placeMany(method, n)
    for i = 1, n do
        if not running then return end
        local p = randPos()
        if method == "click" then
            clickPlace(p)
            task.wait(0.12)
        else
            fire(ActionRemote, "Place", "Egg", p)
            if PLACE_DELAY > 0 then
                task.wait(PLACE_DELAY)
            elseif i % 25 == 0 then
                task.wait()
            end
        end
    end
end

-- places one hotbar slot until it is empty; switches method when nothing changes
local function placeSlot(slot, startCount)
    if not KEYS[slot] then
        print("[HFE] Slot", slot, "has no number key, skipping")
        return 0
    end
    local order = state.PlaceClick and { "click", "remote", "click", "remote" }
        or { "remote", "remote", "click", "click" }
    local mi, total, count = 1, 0, startCount
    local needSelect = true
    while running and count > 0 and mi <= #order do
        if needSelect then
            tapKey(KEYS[slot])
            task.wait(0.2)
            needSelect = false
        end
        placeMany(order[mi], math.min(count, PLACE_PER_PASS))
        task.wait(0.4)
        local after = slotCount(slot)
        if after < count then
            total = total + (count - after)
            count = after
        else
            mi = mi + 1
            needSelect = true
            print("[HFE] Slot", slot, "no progress, trying again with", order[math.min(mi, #order)])
        end
    end
    if count > 0 then
        print("[HFE] Slot", slot, "still has", count, "eggs. Check the place position (SET PLACE POS, or place one egg by hand).")
    end
    return total
end

local placing = false
local function placeAllEggs(silent)
    if placing or busy then
        if not silent then print("[HFE] Busy, try again in a moment") end
        return
    end
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local slots = scanHotbar()
    if #slots == 0 then
        if not silent then
            print("[HFE] No egg counts (x1, x2...) found in the hotbar. Press DUMP INFO and send me the console lines.")
        end
        return
    end

    placing, busy = true, true
    local origin = hrp.CFrame
    hrp.CFrame = CFrame.new(placePos + Vector3.new(0, 5, 0))
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.3)

    local placed = 0
    local ok, err = pcall(function()
        for _, s in ipairs(slots) do
            if not running then break end
            placed = placed + placeSlot(s.slot, s.count)
        end
    end)
    if not ok then warn("[HFE] Place error:", err) end

    restoreCam()
    hrp.CFrame = origin
    hrp.AssemblyLinearVelocity = Vector3.zero
    print("[HFE] Place all done, placed:", placed)
    placing, busy = false, false
end

-- =========================
-- LOOPS
-- =========================
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
                if any and state.AutoPlace and running and state.AutoSteal then
                    placeAllEggs(true)
                end
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

-- AUTO RECORD (only fills areas that have no position)
task.spawn(function()
    while running do
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp and not busy then
            for name, obj in pairs(getLoaded()) do
                local a = parse(name)
                if a and not savedPos[a] and not GUARDIAN_POS[a] then
                    local cf = obj.Parent and getCFrame(obj)
                    if cf and (cf.Position - hrp.Position).Magnitude <= RECORD_RANGE then
                        savePosition(a, hrp.Position)
                    end
                end
            end
        end
        task.wait(1)
    end
end)

-- AUTO HATCH (spams OpenEgg for every known id)
task.spawn(function()
    local lastScan, scans = 0, 0
    while running do
        if state.AutoHatch then
            local now = os.clock()
            if now - lastScan >= ID_SCAN_EVERY then
                lastScan = now
                scans = scans + 1
                pcall(scanForIds, scans % 3 == 1)
            end
            now = os.clock()
            for id, e in pairs(knownIds) do
                if now - e.t > (ID_TTL[e.kind] or 90) then
                    knownIds[id] = nil
                elseif e.kind ~= "manual" and now - e.last >= HATCH_COOLDOWN then
                    e.last = now
                    fire(ActionRemote, "OpenEgg", id)
                end
            end
        end
        task.wait(HATCH_INTERVAL)
    end
end)

local function dumpInfo()
    print("[HFE] ===== DUMP =====")
    print("[HFE] Place position:", placePos)
    local slots = scanHotbar()
    print("[HFE] Hotbar slots read:", #slots)
    for _, s in ipairs(slots) do print("[HFE]    slot", s.slot, "count", s.count) end
    local pg = player:FindFirstChild("PlayerGui")
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text:match("^%s*[xX]%s*%d+%s*$") then
                print("[HFE]    count label:", d:GetFullName(), "=", d.Text, "| shown:", isShown(d))
            end
        end
    end
    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do print("[HFE]    backpack item:", t.Name, t.ClassName) end
    end
    if player.Character then
        for _, t in ipairs(player.Character:GetChildren()) do
            if t:IsA("Tool") then print("[HFE]    equipped item:", t.Name) end
        end
    end
    pcall(scanForIds, true)
    print("[HFE] Hatch ids known:", countIds())
    for id, e in pairs(knownIds) do print("[HFE]    id", id, "|", e.kind, "|", e.src) end
    print("[HFE] ===== END =====")
end

local function allPositions()
    local merged = {}
    for a, p in pairs(savedPos) do merged[a] = p end
    for a, p in pairs(GUARDIAN_POS) do merged[a] = p end
    return merged
end

local function teleportToArea(a)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local cf = getGuardianCFrame(a)
    if not cf then
        warn("[HFE] No position for area " .. tostring(a) .. " yet")
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
if not pcall(function() gui.Parent = parent end) or not gui.Parent then
    gui.Parent = player:WaitForChild("PlayerGui")
end

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

-- title bar: logo, minimize, drag
do
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
local DIM = Color3.fromRGB(170, 170, 185)

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

do
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
end

local exitBtn = makeButton(nav, "EXIT", 6, 204, NAV_W - 12, 26, Color3.fromRGB(120, 40, 40))
makeLabel(nav, "Version 1.9 by imrealsurvivor", 6, 236, NAV_W - 12, 28, 9, DIM)

local updateList
local idsLabel, securedLabel

-- =========================
-- MAIN TAB (stealing area)
-- =========================
do
    local main = pages.MAIN
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
    makeLabel(main, "Flow: area position > egg > grab > 'Egg secured!' detected > next egg. No trip home unless SETTING > Return home is ON. Highest area goes first.",
        226, 152, 256, 56, 10, DIM)
    securedLabel = makeLabel(main, "", 226, 214, 256, 14, 10, Color3.fromRGB(90, 220, 110))
end

-- =========================
-- AUTO TAB (treadmill, hatch, place)
-- =========================
do
    local auto = pages.AUTO
    makeLabel(auto, "AUTOMATION", 6, 4, 230, 16, 11, nil, true)
    makeToggle(auto, "Treadmill (while waiting)", 6, 22, 230, "Treadmill", function(on)
        if not on then setTreadmill(false) end
    end)
    makeToggle(auto, "Auto Hatch", 6, 56, 230, "AutoHatch")
    makeToggle(auto, "Auto Place (after steals)", 6, 90, 230, "AutoPlace")
    makeToggle(auto, "Auto Click", 6, 124, 230, "AutoClick")
    idsLabel = makeLabel(auto, "", 6, 160, 230, 14, 10, DIM)
    local clearIdsBtn = makeButton(auto, "CLEAR HATCH IDS", 6, 178, 230, 26, GRAY)
    clearIdsBtn.MouseButton1Click:Connect(function() knownIds = {} end)
    makeLabel(auto, "Hatch ids are read from the game and from eggs you hatch by hand. If the count stays 0, hatch one egg yourself once.",
        6, 210, 230, 50, 10, DIM)

    makeLabel(auto, "PLACE EGGS", 246, 4, 230, 16, 11, nil, true)
    local placeBtn = makeButton(auto, "PLACE EGG ALL", 246, 22, 230, 28, BLUE)
    placeBtn.MouseButton1Click:Connect(function() task.spawn(placeAllEggs) end)

    local posLabel = makeLabel(auto, "", 246, 56, 230, 14, 10, DIM)
    refreshPosLabel = function()
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

    makeToggle(auto, "Click ground first", 246, 108, 230, "PlaceClick")
    makeInput(auto, "Place spread (0-40 studs)", 246, 144, 230, "PlaceSpread", 0, 40)

    local dumpBtn = makeButton(auto, "DUMP INFO (F9)", 246, 190, 230, 28, GRAY)
    dumpBtn.MouseButton1Click:Connect(function() task.spawn(dumpInfo) end)
    makeLabel(auto, "Tip: place one egg by hand once and the script learns the exact spot.", 246, 224, 230, 34, 10, DIM)
end

-- =========================
-- TELEPORT TAB (positions)
-- =========================
do
    local tp = pages.TELEPORT
    makeLabel(tp, "AUTO RECORD: ON", 6, 4, 230, 16, 11, Color3.fromRGB(90, 220, 110), true)
    makeLabel(tp, "All 57 areas are built in. If a new area has no position, walk near its eggs and it records by itself.",
        6, 22, 230, 50, 10, DIM)

    local savedLabel = makeLabel(tp, "", 6, 76, 230, 14, 10, DIM)
    refreshSaved = function()
        local n = 0
        for _ in pairs(allPositions()) do n = n + 1 end
        savedLabel.Text = "Areas with a position: " .. n .. " / " .. MAX_AREA
    end
    refreshSaved()

    local copyBtn = makeButton(tp, "COPY ALL POSITIONS", 6, 96, 230, 28, GRAY)
    copyBtn.MouseButton1Click:Connect(function()
        local keys = {}
        local all = allPositions()
        for a in pairs(all) do table.insert(keys, a) end
        table.sort(keys)
        local lines = {}
        for _, a in ipairs(keys) do
            local p = all[a]
            table.insert(lines, string.format("[%d] = Vector3.new(%.1f, %.1f, %.1f),", a, p.X, p.Y, p.Z))
        end
        local text = table.concat(lines, "\n")
        print("[HFE] ===== POSITIONS =====\n" .. text)
        if setclipboard then pcall(setclipboard, text) end
    end)

    local resetBtn = makeButton(tp, "RESET RECORDED", 6, 130, 230, 28, Color3.fromRGB(120, 40, 40))
    resetBtn.MouseButton1Click:Connect(function()
        for a in pairs(savedPos) do savedPos[a] = nil end
        persistPositions()
        refreshSaved()
        print("[HFE] Recorded positions cleared (built-in ones stay)")
    end)

    makeLabel(tp, "GO TO", 246, 4, 230, 14, 11, nil, true)
    makeInput(tp, "Teleport area (1-57)", 246, 22, 110, "TpArea", 1, MAX_AREA)
    local goBtn = makeButton(tp, "TELEPORT", 362, 35, 114, 24, BLUE)
    goBtn.TextSize = 11
    goBtn.MouseButton1Click:Connect(function()
        teleportToArea(state.TpArea)
    end)

    local home1Btn = makeButton(tp, "GO HOME 1 (tween)", 246, 68, 230, 28, GRAY)
    home1Btn.MouseButton1Click:Connect(function()
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then task.spawn(tweenTo, hrp, HOME) end
    end)

    local home2Btn = makeButton(tp, "GO HOME 2 (world 2)", 246, 102, 230, 28, GRAY)
    home2Btn.MouseButton1Click:Connect(function()
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then task.spawn(tweenTo, hrp, HOME2) end
    end)

    local placeGoBtn = makeButton(tp, "GO TO PLACE POS", 246, 136, 230, 28, GRAY)
    placeGoBtn.MouseButton1Click:Connect(function()
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = CFrame.new(placePos + Vector3.new(0, 5, 0)) end
    end)
end

-- =========================
-- SETTING TAB
-- =========================
do
    local setting = pages.SETTING
    makeLabel(setting, "SETTINGS", 6, 4, 230, 16, 11, nil, true)
    makeToggle(setting, "Anti AFK", 6, 22, 230, "AntiAFK")
    makeToggle(setting, "Return home after steal", 6, 56, 230, "ReturnHome")
    makeLabel(setting, "Anti AFK stops the idle kick (for example while the treadmill runs). Return home is OFF by default: after 'Egg secured!' the script goes straight to the next egg.",
        6, 92, 230, 70, 10, DIM)
end

-- =========================
-- VISUAL TAB (ESP)
-- =========================
do
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
        6, 92, 230, 70, 10, DIM)

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
end

-- live labels
task.spawn(function()
    while running do
        pcall(function()
            if securedLabel then securedLabel.Text = "Eggs secured this session: " .. securedCount end
            if idsLabel then idsLabel.Text = "Hatch ids known: " .. countIds() end
        end)
        task.wait(1)
    end
end)

-- EXIT
exitBtn.MouseButton1Click:Connect(function()
    state.AutoSteal = false
    state.AutoClick = false
    state.AutoHatch = false
    state.AutoPlace = false
    state.ESP = false
    setTreadmill(false)
    running = false
    restoreCam()
    if currentTween then currentTween:Cancel() end
    if idledConn then idledConn:Disconnect() end
    gui:Destroy()
    print("[HFE] Exited")
end)

showPage("MAIN")
print("[HFE] Menu loaded (1.9)")