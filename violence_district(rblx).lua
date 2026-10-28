-- ================================================================
--  VIOLENCE DISTRICT HUB v2
--  Senior LuaU rewrite — touch-first, PC + Android/iOS
--  Delta Executor compatible (no getrawmetatable dependency)
--  Game: [BUTCHER x 🎃] Violence District — PlaceId 6739698191
--  Last verified: October 2026 (Butcher × Halloween update)
-- ================================================================

-- ── SERVICES ────────────────────────────────────────────────────
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local UserInputSvc   = game:GetService("UserInputService")
local TweenService   = game:GetService("TweenService")
local StarterGui     = game:GetService("StarterGui")
local Workspace      = game:GetService("Workspace")
local RS             = game:GetService("ReplicatedStorage")
local CoreGui        = game:GetService("CoreGui")
local Lighting       = game:GetService("Lighting")
local GuiService     = game:GetService("GuiService")
local HttpService    = game:GetService("HttpService")

-- ── MOBILE DETECTION ────────────────────────────────────────────
local IS_MOBILE = UserInputSvc.TouchEnabled and not UserInputSvc.KeyboardEnabled

-- ── LOCAL PLAYER ────────────────────────────────────────────────
local LP   = Players.LocalPlayer
local PGui = LP.PlayerGui

local function getChar()  return LP.Character end
local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

LP.CharacterAdded:Connect(function(c)
    c:WaitForChild("HumanoidRootPart", 10)
    c:WaitForChild("Humanoid", 10)
end)

-- ── NOTIFY ──────────────────────────────────────────────────────
local function notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title    = title,
            Text     = text,
            Duration = dur or 3,
        })
    end)
end

-- ── DISTANCE ────────────────────────────────────────────────────
local function vecDist(a, b)
    if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
        return (a - b).Magnitude
    end
    return math.huge
end

local function modelPos(m)
    if not m then return nil end
    if m:IsA("BasePart") then return m.Position end
    local p = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
    return p and p.Position or nil
end

-- ── ROLE DETECTION ──────────────────────────────────────────────
-- VD uses Team.Name to separate roles
local ROLE_CACHE = "Survivor"
local function getRole()
    local team = LP.Team
    if team then
        local n = team.Name:lower()
        if n:find("killer") then ROLE_CACHE = "Killer"
        elseif n:find("survivor") then ROLE_CACHE = "Survivor"
        end
    end
    -- secondary: check character StringValue
    local c = getChar()
    if c then
        local rv = c:FindFirstChild("Role")
        if rv then ROLE_CACHE = rv.Value end
    end
    return ROLE_CACHE
end

LP.TeamChanged:Connect(function() getRole() end)

-- ── MAP OBJECT SCANNER ──────────────────────────────────────────
-- VD confirmed model names from wiki / community scripts:
-- Generators: "Generator", "Gen"
-- Hooks:      "Hook", "SacrificeHook"
-- Pallets:    "Pallet", "WoodPallet"
-- Vaults:     "Vault", "Window"
-- Exit Gates: "ExitGate", "ExitLever", "Gate", "Lever"
-- Chests:     "Chest"

local SCAN_TAGS = {
    generator = { "Generator", "Gen" },
    hook       = { "Hook", "SacrificeHook" },
    pallet     = { "Pallet", "WoodPallet" },
    vault      = { "Vault", "Window" },
    exit       = { "ExitGate", "ExitLever", "Gate", "Lever" },
    chest      = { "Chest" },
}

local scanCache = {}
local CACHE_TTL = 5 -- seconds
local lastScan  = 0

local function scan(tag)
    local now = tick()
    if scanCache[tag] and (now - lastScan) < CACHE_TTL then
        return scanCache[tag]
    end
    local results = {}
    local patterns = SCAN_TAGS[tag]
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            for _, pat in ipairs(patterns) do
                if obj.Name == pat or obj.Name:lower():find(pat:lower()) then
                    table.insert(results, obj)
                    break
                end
            end
        end
    end
    scanCache[tag] = results
    lastScan       = now
    return results
end

local function clearCache() scanCache = {}; lastScan = 0 end

-- invalidate when map changes
Workspace.ChildAdded:Connect(clearCache)
Workspace.ChildRemoved:Connect(clearCache)

-- ── REMOTE FINDER ───────────────────────────────────────────────
-- VD uses standard RemoteEvents under ReplicatedStorage
-- confirmed community pattern — names gathered from script research

local remCache = {}
local function findRemotes(...)
    local keys = {...}
    local found = {}
    for _, key in ipairs(keys) do
        if remCache[key] then
            table.insert(found, remCache[key])
        end
    end
    if #found > 0 then return found end

    for _, v in ipairs(RS:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            local low = v.Name:lower()
            for _, key in ipairs(keys) do
                if low:find(key:lower()) then
                    remCache[key] = v
                    table.insert(found, v)
                    break
                end
            end
        end
    end
    return found
end

local function fireRemotes(keys, ...)
    for _, r in ipairs(findRemotes(table.unpack(keys))) do
        pcall(function()
            if r:IsA("RemoteEvent") then
                r:FireServer(...)
            end
        end)
    end
end

-- ── CONFIG ──────────────────────────────────────────────────────
local CFG = {
    -- ESP
    esp            = true,
    espSurvivor    = true,
    espKiller      = true,
    espGen         = true,
    espHook        = true,
    espPallet      = false,
    espVault       = false,
    espExit        = true,
    espChest       = false,
    espMaxDist     = 500,

    -- Colors
    colSurvivor    = Color3.fromRGB(0,   220, 80),
    colKiller      = Color3.fromRGB(255,  40, 40),
    colGen         = Color3.fromRGB(255, 210,  0),
    colHook        = Color3.fromRGB(160,  80, 255),
    colPallet      = Color3.fromRGB(200, 140,  60),
    colVault       = Color3.fromRGB(0,   180, 255),
    colExit        = Color3.fromRGB(255, 255, 255),
    colChest       = Color3.fromRGB(255, 180,   0),

    -- Killer alert
    killerAlertDist = 22,

    -- Movement
    speed          = false,
    speedVal       = 28,
    noclip         = false,
    fly            = false,
    flySpeed       = 40,

    -- Survivor automation
    autoGen        = false,
    autoGenRange   = 4,       -- studs to gen before firing remote
    autoSkillcheck = true,    -- active alongside autoGen
    skillcheckMode = "Perfect", -- "Normal" | "Perfect" | "Instant"
    autoHeal       = false,
    antiKnock      = false,
    swiftVault     = false,
    fleeKiller     = false,
    fleeKillerDist = 18,
    autoExit       = false,

    -- Killer automation
    autoAttack     = false,
    attackRange    = 6,
    hitboxExpand   = false,
    hitboxSize     = 8,
    infiniteLunge  = false,
    autoHook       = false,
    kickGen        = false,
    destroyPallet  = false,
    killerInvis    = false,

    -- Visual
    fullbright     = false,
    customFOV      = false,
    fovVal         = 90,
    watermark      = true,

    -- Misc
    antiAFK        = true,
}

-- ── ESP SYSTEM ──────────────────────────────────────────────────
local espPool = {}

local function getOrCreate(key, adornee, color, textSize)
    if espPool[key] and espPool[key].Parent == CoreGui then
        return espPool[key]
    end
    -- clean stale
    if espPool[key] then
        pcall(function() espPool[key]:Destroy() end)
        espPool[key] = nil
    end

    local bb = Instance.new("BillboardGui")
    bb.Name           = "VDHub_ESP_" .. key
    bb.AlwaysOnTop    = true
    bb.ResetOnSpawn   = false
    bb.Size           = UDim2.new(0, IS_MOBILE and 90 or 80, 0, IS_MOBILE and 34 or 28)
    bb.StudsOffset    = Vector3.new(0, 2.8, 0)
    bb.Adornee        = adornee
    bb.Parent         = CoreGui

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size                   = UDim2.new(1,0,1,0)
    lbl.TextColor3             = color
    lbl.TextStrokeTransparency = 0
    lbl.TextStrokeColor3       = Color3.new(0,0,0)
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextScaled             = true
    lbl.Text                   = "..."
    lbl.Parent                 = bb

    espPool[key] = bb
    return bb
end

local function setESPText(key, text)
    local bb = espPool[key]
    if bb then
        local lbl = bb:FindFirstChildWhichIsA("TextLabel")
        if lbl then lbl.Text = text end
    end
end

local function removeESP(key)
    if espPool[key] then
        pcall(function() espPool[key]:Destroy() end)
        espPool[key] = nil
    end
end

local function removeESPPattern(pat)
    for k in pairs(espPool) do
        if k:find(pat) then removeESP(k) end
    end
end

-- Killer identity cache
local killerPlayer = nil
local function updateKiller()
    killerPlayer = nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            if p.Team and p.Team.Name:lower():find("killer") then
                killerPlayer = p; return
            end
            local c = p.Character
            if c then
                local rv = c:FindFirstChild("Role")
                if rv and tostring(rv.Value):lower():find("killer") then
                    killerPlayer = p; return
                end
            end
        end
    end
end

Players.PlayerAdded:Connect(updateKiller)
Players.PlayerRemoving:Connect(updateKiller)
task.delay(3, updateKiller)

-- ── ESP RENDER ──────────────────────────────────────────────────
local espConn
local function startESP()
    if espConn then espConn:Disconnect() end
    espConn = RunService.Heartbeat:Connect(function()
        if not CFG.esp then
            for k in pairs(espPool) do removeESP(k) end
            return
        end

        local hrp = getHRP()
        if not hrp then return end
        local myPos = hrp.Position

        -- ── Survivors ───────────────────────────────────────────
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LP then continue end
            local key = "surv_" .. p.UserId
            if p == killerPlayer then
                removeESP(key); continue
            end
            if not CFG.espSurvivor then removeESP(key); continue end
            local c   = p.Character
            local phrp = c and c:FindFirstChild("HumanoidRootPart")
            if not phrp then removeESP(key); continue end
            local d = vecDist(myPos, phrp.Position)
            if d > CFG.espMaxDist then removeESP(key); continue end
            local hum = c:FindFirstChildOfClass("Humanoid")
            local hp  = hum and math.floor(hum.Health) or "?"
            local bb  = getOrCreate(key, phrp, CFG.colSurvivor)
            setESPText(key, string.format("[SURV] %s\nHP:%s  %.0fm", p.Name, hp, d))
        end

        -- ── Killer ──────────────────────────────────────────────
        if CFG.espKiller then
            local kp = killerPlayer
            if kp and kp.Character then
                local khrp = kp.Character:FindFirstChild("HumanoidRootPart")
                if khrp then
                    local d = vecDist(myPos, khrp.Position)
                    if d <= CFG.espMaxDist then
                        local bb = getOrCreate("killer", khrp, CFG.colKiller)
                        -- pulse when close
                        local lbl = bb:FindFirstChildWhichIsA("TextLabel")
                        if lbl then
                            lbl.TextColor3 = (d <= CFG.killerAlertDist and tick() % 0.5 > 0.25)
                                and Color3.new(1,1,1) or CFG.colKiller
                            lbl.Text = string.format(
                                "[KILLER] %s\n%.0fm%s",
                                kp.Name, d,
                                d <= CFG.killerAlertDist and "  ⚠" or ""
                            )
                        end
                    else removeESP("killer") end
                else removeESP("killer") end
            else removeESP("killer") end
        else removeESP("killer") end

        -- ── Generators ──────────────────────────────────────────
        if CFG.espGen then
            for i, gen in ipairs(scan("generator")) do
                local key  = "gen_" .. i
                local pos  = modelPos(gen)
                if not pos then removeESP(key); continue end
                local d    = vecDist(myPos, pos)
                if d > CFG.espMaxDist then removeESP(key); continue end
                -- check repair progress (IntValue / NumberValue named "Progress" or "Charge")
                local prog = 0
                for _, v in ipairs(gen:GetDescendants()) do
                    if (v.Name:lower():find("progress") or v.Name:lower():find("charge")) and
                       (v:IsA("NumberValue") or v:IsA("IntValue")) then
                        prog = math.floor(v.Value)
                        break
                    end
                end
                local repaired = prog >= 99
                local col  = repaired and Color3.fromRGB(80,255,80) or CFG.colGen
                local bb   = getOrCreate(key, modelPos(gen) and
                    (gen.PrimaryPart or gen:FindFirstChildWhichIsA("BasePart")) or gen,
                    col)
                setESPText(key, string.format(
                    "[GEN %d] %d%%%s\n%.0fm",
                    i, prog, repaired and "✓" or "", d
                ))
                local lbl = espPool[key] and espPool[key]:FindFirstChildWhichIsA("TextLabel")
                if lbl then lbl.TextColor3 = col end
            end
        else removeESPPattern("gen_") end

        -- ── Hooks ───────────────────────────────────────────────
        if CFG.espHook then
            for i, hook in ipairs(scan("hook")) do
                local key = "hook_" .. i
                local pos = modelPos(hook)
                if not pos then removeESP(key); continue end
                local d = vecDist(myPos, pos)
                if d > CFG.espMaxDist then removeESP(key); continue end
                local part = hook.PrimaryPart or hook:FindFirstChildWhichIsA("BasePart") or hook
                getOrCreate(key, part, CFG.colHook)
                setESPText(key, string.format("[HOOK %d]\n%.0fm", i, d))
            end
        else removeESPPattern("hook_") end

        -- ── Pallets ─────────────────────────────────────────────
        if CFG.espPallet then
            for i, p in ipairs(scan("pallet")) do
                local key = "pallet_" .. i
                local pos = modelPos(p)
                if not pos then removeESP(key); continue end
                local d = vecDist(myPos, pos)
                if d > 120 then removeESP(key); continue end
                local part = p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart") or p
                getOrCreate(key, part, CFG.colPallet)
                setESPText(key, string.format("[PALLET]\n%.0fm", d))
            end
        else removeESPPattern("pallet_") end

        -- ── Vaults / Windows ────────────────────────────────────
        if CFG.espVault then
            for i, v in ipairs(scan("vault")) do
                local key = "vault_" .. i
                local pos = modelPos(v)
                if not pos then removeESP(key); continue end
                local d = vecDist(myPos, pos)
                if d > 80 then removeESP(key); continue end
                local part = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart") or v
                getOrCreate(key, part, CFG.colVault)
                setESPText(key, string.format("[VAULT]\n%.0fm", d))
            end
        else removeESPPattern("vault_") end

        -- ── Exit Gates ──────────────────────────────────────────
        if CFG.espExit then
            for i, eg in ipairs(scan("exit")) do
                local key = "exit_" .. i
                local pos = modelPos(eg)
                if not pos then removeESP(key); continue end
                local d = vecDist(myPos, pos)
                if d > CFG.espMaxDist then removeESP(key); continue end
                local part = eg.PrimaryPart or eg:FindFirstChildWhichIsA("BasePart") or eg
                getOrCreate(key, part, CFG.colExit)
                setESPText(key, string.format("[EXIT %d]\n%.0fm", i, d))
            end
        else removeESPPattern("exit_") end

        -- ── Chests ──────────────────────────────────────────────
        if CFG.espChest then
            for i, ch in ipairs(scan("chest")) do
                local key = "chest_" .. i
                local pos = modelPos(ch)
                if not pos then removeESP(key); continue end
                local d = vecDist(myPos, pos)
                if d > CFG.espMaxDist then removeESP(key); continue end
                local part = ch.PrimaryPart or ch:FindFirstChildWhichIsA("BasePart") or ch
                getOrCreate(key, part, CFG.colChest)
                setESPText(key, string.format("[CHEST]\n%.0fm", d))
            end
        else removeESPPattern("chest_") end
    end)
end

startESP()

-- ── KILLER PROXIMITY ALERT ──────────────────────────────────────
local alertSnd = Instance.new("Sound")
alertSnd.SoundId = "rbxassetid://6042053626"
alertSnd.Volume  = 0.7
alertSnd.RollOffMaxDistance = 0
alertSnd.Parent  = Workspace

local lastAlert = 0
RunService.Heartbeat:Connect(function()
    if getRole() ~= "Survivor" then return end
    local hrp = getHRP(); if not hrp then return end
    local kp  = killerPlayer
    if not kp or not kp.Character then return end
    local khrp = kp.Character:FindFirstChild("HumanoidRootPart")
    if not khrp then return end
    local d = vecDist(hrp.Position, khrp.Position)
    if d <= CFG.killerAlertDist then
        if tick() - lastAlert > 2.5 then
            lastAlert = tick()
            pcall(function() alertSnd:Play() end)
            notify("⚠ KILLER", string.format("%.0fm — MOVE", d), 2)
        end
    end
end)

-- ── SPEED HACK ──────────────────────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not CFG.speed then return end
    local hum = getHum(); if not hum then return end
    hum.WalkSpeed = CFG.speedVal
end)

-- ── NOCLIP ──────────────────────────────────────────────────────
RunService.Stepped:Connect(function()
    if not CFG.noclip then return end
    local c = getChar(); if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end
end)

-- ── FLY ─────────────────────────────────────────────────────────
local flyBV, flyBG
local function startFly()
    local hrp = getHRP(); if not hrp then return end
    local hum = getHum(); if not hum then return end
    hum.PlatformStand = true

    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(1e5,1e5,1e5)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent   = hrp

    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(1e5,1e5,1e5)
    flyBG.P         = 9e4
    flyBG.Parent    = hrp

    RunService:BindToRenderStep("vd_fly", Enum.RenderPriority.Input.Value + 1, function()
        if not CFG.fly then
            flyBV.Velocity = Vector3.zero; return
        end
        local cam = Workspace.CurrentCamera
        local dir = Vector3.zero
        if IS_MOBILE then
            -- mobile: use thumbstick (AnalogInput) directly from the move vector
            local mv = LP:GetMoveVector()
            -- convert to world-space
            local forward = cam.CFrame.LookVector
            local right   = cam.CFrame.RightVector
            dir = (forward * -mv.Z + right * mv.X)
            -- mobile space/land = GUI buttons handled separately (touch buttons below)
        else
            if UserInputSvc:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
            if UserInputSvc:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
            if UserInputSvc:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
            if UserInputSvc:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
            if UserInputSvc:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0,1,0) end
            if UserInputSvc:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.new(0,1,0) end
        end
        flyBV.Velocity = dir.Magnitude > 0 and dir.Unit * CFG.flySpeed or Vector3.zero
        flyBG.CFrame   = cam.CFrame
    end)
end

local function stopFly()
    RunService:UnbindFromRenderStep("vd_fly")
    local hum = getHum()
    if hum then hum.PlatformStand = false end
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
end

-- ── SKILLCHECK SOLVER ───────────────────────────────────────────
-- VD skillcheck = rotating ScreenGui frame "SkillCheck" (or "SkillCheckGui")
-- with a "Needle" / "Arrow" BasePart or Frame that rotates
-- and a "SuccessZone" / "GoodZone" Frame indicating the hit window

local function solveSkillcheck()
    -- search all PlayerGui ScreenGuis for skillcheck elements
    for _, sg in ipairs(PGui:GetChildren()) do
        if not sg:IsA("ScreenGui") then continue end
        local low = sg.Name:lower()
        if not (low:find("skill") or low:find("check") or low:find("minigame")) then continue end

        -- find the needle and zone
        local needle = sg:FindFirstChild("Needle") or sg:FindFirstChild("Arrow")
            or sg:FindFirstChildWhichIsA("Frame")
        local zone   = sg:FindFirstChild("SuccessZone") or sg:FindFirstChild("GoodZone")
            or sg:FindFirstChild("HitZone")

        if not needle then continue end

        if CFG.skillcheckMode == "Instant" then
            -- fire interact remote immediately regardless of timing
            fireRemotes({"skillcheck","interact","repair","check","minigame"}, true)
            return
        end

        if CFG.skillcheckMode == "Perfect" and zone then
            -- spin needle, detect when rotation aligns with zone center
            -- VD rotates needle UIElement — check Rotation property
            local needleRot = needle:IsA("GuiObject") and needle.Rotation or 0
            local zoneRot   = zone:IsA("GuiObject") and zone.Rotation  or 0
            local diff      = math.abs((needleRot - zoneRot) % 360)
            if diff < 15 or diff > 345 then
                fireRemotes({"skillcheck","interact","repair","check","minigame"}, true)
                return
            end
        elseif CFG.skillcheckMode == "Normal" then
            -- hit any valid window — just fire after short delay
            task.delay(0.05, function()
                fireRemotes({"skillcheck","interact","repair","check","minigame"}, true)
            end)
            return
        end
    end
end

-- poll skillcheck every render frame
RunService.RenderStepped:Connect(function()
    if CFG.autoGen and CFG.autoSkillcheck then
        pcall(solveSkillcheck)
    end
end)

-- ── AUTO GENERATOR ──────────────────────────────────────────────
local genLoop
local function startAutoGen()
    if genLoop then return end
    genLoop = task.spawn(function()
        while CFG.autoGen do
            task.wait(0.15)
            if getRole() ~= "Survivor" then task.wait(1); continue end
            local hrp = getHRP(); if not hrp then continue end

            local gens = scan("generator")
            local nearest, nearPos, nearDist = nil, nil, math.huge
            for _, gen in ipairs(gens) do
                -- skip completed (check BoolValue "Repaired" or progress >= 100)
                local done = false
                for _, v in ipairs(gen:GetDescendants()) do
                    if v.Name:lower() == "repaired" and v:IsA("BoolValue") and v.Value then
                        done = true; break
                    end
                    if (v.Name:lower():find("progress") or v.Name:lower():find("charge"))
                       and (v:IsA("NumberValue") or v:IsA("IntValue")) and v.Value >= 99 then
                        done = true; break
                    end
                end
                if done then continue end

                local pos = modelPos(gen)
                if pos then
                    local d = vecDist(hrp.Position, pos)
                    if d < nearDist then
                        nearDist  = d
                        nearest   = gen
                        nearPos   = pos
                    end
                end
            end

            if not nearest or not nearPos then continue end

            -- teleport if too far
            if nearDist > CFG.autoGenRange then
                hrp.CFrame = CFrame.new(nearPos + Vector3.new(0, 3, 2.5))
                task.wait(0.1)
            end

            -- fire all repair-type remotes
            fireRemotes(
                {"repair","generator","gen","interact","fix"},
                nearest
            )
        end
        genLoop = nil
    end)
end

local function stopAutoGen() CFG.autoGen = false end

-- ── AUTO EXIT (open gate once 5 gens done) ──────────────────────
local exitLoop
local function startAutoExit()
    if exitLoop then return end
    exitLoop = task.spawn(function()
        while CFG.autoExit do
            task.wait(0.3)
            if getRole() ~= "Survivor" then task.wait(1); continue end
            local hrp = getHRP(); if not hrp then continue end
            local exits = scan("exit")
            for _, eg in ipairs(exits) do
                local pos = modelPos(eg)
                if pos then
                    local d = vecDist(hrp.Position, pos)
                    if d > 4 then
                        hrp.CFrame = CFrame.new(pos + Vector3.new(0,3,2))
                        task.wait(0.1)
                    end
                    fireRemotes({"exit","lever","gate","open","interact"}, eg)
                end
            end
        end
        exitLoop = nil
    end)
end

-- ── AUTO HEAL ───────────────────────────────────────────────────
local healLoop
local function startHeal()
    if healLoop then return end
    healLoop = task.spawn(function()
        while CFG.autoHeal do
            task.wait(0.3)
            local hum = getHum(); if not hum then continue end
            if hum.Health < hum.MaxHealth then
                for i = 1, 8 do
                    fireRemotes({"heal","bandage","recover","health"})
                    task.wait(0.05)
                end
            end
            task.wait(2)
        end
        healLoop = nil
    end)
end

-- ── ANTI KNOCK (struggle spam while downed) ─────────────────────
local antiKnockLoop
local function startAntiKnock()
    if antiKnockLoop then return end
    antiKnockLoop = task.spawn(function()
        while CFG.antiKnock do
            task.wait(0.08)
            local hum = getHum(); if not hum then continue end
            -- detect knocked state via state or a BoolValue in char
            local knocked = false
            local c = getChar()
            if c then
                local kv = c:FindFirstChild("Knocked") or c:FindFirstChild("Downed") or c:FindFirstChild("Down")
                if kv and kv:IsA("BoolValue") and kv.Value then knocked = true end
                if hum:GetState() == Enum.HumanoidStateType.Dead then knocked = false end
            end
            if knocked or (hum.Health > 0 and hum.WalkSpeed == 0) then
                fireRemotes({"struggle","unhook","escape","wakeup","resist"})
            end
        end
        antiKnockLoop = nil
    end)
end

-- ── FLEE KILLER ─────────────────────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not CFG.fleeKiller then return end
    if getRole() ~= "Survivor" then return end
    local hrp = getHRP(); if not hrp then return end
    local kp  = killerPlayer
    if not kp or not kp.Character then return end
    local khrp = kp.Character:FindFirstChild("HumanoidRootPart")
    if not khrp then return end
    local d = vecDist(hrp.Position, khrp.Position)
    if d <= CFG.fleeKillerDist then
        local fleeDir = (hrp.Position - khrp.Position).Unit
        hrp.CFrame = CFrame.new(hrp.Position + fleeDir * 12)
    end
end)

-- ── SWIFT VAULT ─────────────────────────────────────────────────
local function trySwiftVault()
    local hrp = getHRP(); if not hrp then return end
    local vaults = scan("vault")
    local closest, closestD = nil, math.huge
    for _, v in ipairs(vaults) do
        local pos = modelPos(v)
        if pos then
            local d = vecDist(hrp.Position, pos)
            if d < closestD then closestD = d; closest = v end
        end
    end
    if closest and closestD < 6 then
        fireRemotes({"vault","window","jump","climb","interact"}, closest)
    end
end

-- ── KILLER: AUTO ATTACK ─────────────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not CFG.autoAttack then return end
    if getRole() ~= "Killer" then return end
    local hrp = getHRP(); if not hrp then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP or p == killerPlayer then continue end
        local c = p.Character; if not c then continue end
        local phrp = c:FindFirstChild("HumanoidRootPart"); if not phrp then continue end
        local d = vecDist(hrp.Position, phrp.Position)
        if d <= CFG.attackRange then
            fireRemotes({"attack","hit","swing","lunge","strike"}, phrp.Position)
        end
    end
end)

-- ── KILLER: HITBOX EXPAND ───────────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not CFG.hitboxExpand then return end
    if getRole() ~= "Killer" then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        local c = p.Character; if not c then continue end
        local phrp = c:FindFirstChild("HumanoidRootPart")
        if phrp then
            phrp.Size = Vector3.new(CFG.hitboxSize, CFG.hitboxSize, CFG.hitboxSize)
        end
    end
end)

-- ── KILLER: INFINITE LUNGE ──────────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not CFG.infiniteLunge then return end
    if getRole() ~= "Killer" then return end
    if UserInputSvc:IsMouseButtonDown(Enum.UserInputType.MouseButton1) or
       (IS_MOBILE and UserInputSvc.TouchEnabled) then
        local hrp = getHRP(); if not hrp then return end
        fireRemotes({"lunge","attack","swing"}, hrp.CFrame.LookVector)
    end
end)

-- ── KILLER: AUTO HOOK ───────────────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not CFG.autoHook then return end
    if getRole() ~= "Killer" then return end
    local hrp = getHRP(); if not hrp then return end
    -- find nearest hook
    local hooks = scan("hook")
    local nearHook, nearD = nil, math.huge
    for _, h in ipairs(hooks) do
        local pos = modelPos(h)
        if pos then
            local d = vecDist(hrp.Position, pos)
            if d < nearD then nearD = d; nearHook = h end
        end
    end
    if nearHook and nearD < 6 then
        fireRemotes({"hook","sacrifice","hang","place"}, nearHook)
    end
end)

-- ── KILLER: KICK GENERATOR ──────────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not CFG.kickGen then return end
    if getRole() ~= "Killer" then return end
    local hrp = getHRP(); if not hrp then return end
    for _, gen in ipairs(scan("generator")) do
        local pos = modelPos(gen)
        if pos and vecDist(hrp.Position, pos) < 5 then
            fireRemotes({"kick","kickgenerator","break","regress","damage"}, gen)
        end
    end
end)

-- ── KILLER: DESTROY PALLET ──────────────────────────────────────
RunService.Heartbeat:Connect(function()
    if not CFG.destroyPallet then return end
    if getRole() ~= "Killer" then return end
    local hrp = getHRP(); if not hrp then return end
    for _, p in ipairs(scan("pallet")) do
        local pos = modelPos(p)
        if pos and vecDist(hrp.Position, pos) < 5 then
            fireRemotes({"destroypallet","breakpallet","pallet","smash"}, p)
        end
    end
end)

-- ── KILLER: INVISIBILITY ────────────────────────────────────────
local function setKillerInvis(on)
    local c = getChar(); if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") or p:IsA("Decal") or p:IsA("SpecialMesh") then
            if on then
                p.Transparency = 1
            else
                p.Transparency = p:GetAttribute("OrigTrans") or 0
            end
        end
    end
end

-- ── FULLBRIGHT ──────────────────────────────────────────────────
local origLighting = {}
local function setFullbright(on)
    if on then
        origLighting.Brightness        = Lighting.Brightness
        origLighting.ClockTime         = Lighting.ClockTime
        origLighting.FogEnd            = Lighting.FogEnd
        origLighting.GlobalShadows     = Lighting.GlobalShadows
        origLighting.Ambient           = Lighting.Ambient
        origLighting.OutdoorAmbient    = Lighting.OutdoorAmbient

        Lighting.Brightness        = 5
        Lighting.ClockTime         = 14
        Lighting.FogEnd            = 1e6
        Lighting.GlobalShadows     = false
        Lighting.Ambient           = Color3.fromRGB(255,255,255)
        Lighting.OutdoorAmbient    = Color3.fromRGB(255,255,255)

        for _, v in ipairs(Lighting:GetDescendants()) do
            if v:IsA("Atmosphere") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") then
                v.Enabled = false
            end
        end
    else
        Lighting.Brightness        = origLighting.Brightness or 1
        Lighting.ClockTime         = origLighting.ClockTime  or 14
        Lighting.FogEnd            = origLighting.FogEnd     or 1e6
        Lighting.GlobalShadows     = origLighting.GlobalShadows ~= nil and origLighting.GlobalShadows or true
        Lighting.Ambient           = origLighting.Ambient    or Color3.fromRGB(70,70,70)
        Lighting.OutdoorAmbient    = origLighting.OutdoorAmbient or Color3.fromRGB(70,70,70)
        for _, v in ipairs(Lighting:GetDescendants()) do
            if v:IsA("Atmosphere") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") then
                v.Enabled = true
            end
        end
    end
end

-- ── ANTI AFK ────────────────────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(55)
        if CFG.antiAFK then
            local vps = LP.PlayerGui:FindFirstChild("ControlGui")
            if not vps then
                -- fire a fake movement
                local hum = getHum()
                if hum then hum.Jump = true end
            end
        end
    end
end)

-- ================================================================
--  GUI SYSTEM — FULL TOUCH + PC
--  Responsive: 360px wide on mobile, 340px on PC
-- ================================================================

-- clean up any previous instance
pcall(function()
    local prev = CoreGui:FindFirstChild("VDHub_GUI")
    if prev then prev:Destroy() end
end)

local GUI_WIDTH  = IS_MOBILE and 360 or 340
local GUI_HEIGHT = IS_MOBILE and 600 or 560
local BTN_H      = IS_MOBILE and 46  or 36
local FONT_SZ    = IS_MOBILE and 16  or 14
local PAD        = IS_MOBILE and 8   or 6

local THEME = {
    bg       = Color3.fromRGB(15,  15,  20),
    sidebar  = Color3.fromRGB(20,  20,  28),
    accent   = Color3.fromRGB(180,  40,  40),
    tabSel   = Color3.fromRGB(35,  35,  48),
    btn      = Color3.fromRGB(28,  28,  38),
    btnHov   = Color3.fromRGB(45,  45,  60),
    btnOn    = Color3.fromRGB(40,  160,  80),
    btnOff   = Color3.fromRGB(120,  30,  30),
    text     = Color3.fromRGB(240, 240, 240),
    subtext  = Color3.fromRGB(160, 160, 180),
    sep      = Color3.fromRGB(40,  40,  55),
}

local root = Instance.new("ScreenGui")
root.Name            = "VDHub_GUI"
root.ResetOnSpawn    = false
root.IgnoreGuiInset  = true
root.DisplayOrder    = 999
root.Parent          = CoreGui

-- ── DRAGGABLE MAIN FRAME ────────────────────────────────────────
local mainFrame = Instance.new("Frame")
mainFrame.Name              = "Main"
mainFrame.Size              = UDim2.new(0, GUI_WIDTH, 0, GUI_HEIGHT)
mainFrame.Position          = UDim2.new(0.5, -GUI_WIDTH//2, 0.5, -GUI_HEIGHT//2)
mainFrame.BackgroundColor3  = THEME.bg
mainFrame.BorderSizePixel   = 0
mainFrame.ClipsDescendants  = true
mainFrame.Parent            = root

local uicorner = Instance.new("UICorner")
uicorner.CornerRadius = UDim.new(0, 10)
uicorner.Parent       = mainFrame

local uistroke = Instance.new("UIStroke")
uistroke.Color     = THEME.accent
uistroke.Thickness = 1.5
uistroke.Parent    = mainFrame

-- shadow
local shadow = Instance.new("ImageLabel")
shadow.Name                = "Shadow"
shadow.Image               = "rbxassetid://5554236805"
shadow.ImageColor3         = Color3.new(0,0,0)
shadow.ImageTransparency   = 0.5
shadow.ScaleType           = Enum.ScaleType.Slice
shadow.SliceCenter         = Rect.new(23,23,277,277)
shadow.Size                = UDim2.new(1,30,1,30)
shadow.Position            = UDim2.new(0,-15,0,-15)
shadow.BackgroundTransparency = 1
shadow.ZIndex              = -1
shadow.Parent              = mainFrame

-- ── TITLE BAR ───────────────────────────────────────────────────
local titleBar = Instance.new("Frame")
titleBar.Name             = "TitleBar"
titleBar.Size             = UDim2.new(1, 0, 0, IS_MOBILE and 48 or 40)
titleBar.BackgroundColor3 = THEME.sidebar
titleBar.BorderSizePixel  = 0
titleBar.Parent           = mainFrame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0,10)
titleCorner.Parent       = titleBar

-- mask bottom corners of titlebar
local titleMask = Instance.new("Frame")
titleMask.Size              = UDim2.new(1,0,0,10)
titleMask.Position          = UDim2.new(0,0,1,-10)
titleMask.BackgroundColor3  = THEME.sidebar
titleMask.BorderSizePixel   = 0
titleMask.Parent            = titleBar

local titleLbl = Instance.new("TextLabel")
titleLbl.Text               = "🔪 VD Hub  |  Butcher × 🎃  |  v2"
titleLbl.Size               = UDim2.new(1,-90,1,0)
titleLbl.Position           = UDim2.new(0,14,0,0)
titleLbl.BackgroundTransparency = 1
titleLbl.TextColor3         = THEME.text
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = IS_MOBILE and 15 or 13
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.Parent             = titleBar

-- role badge
local roleBadge = Instance.new("TextLabel")
roleBadge.Size              = UDim2.new(0, 80, 0, IS_MOBILE and 28 or 22)
roleBadge.Position          = UDim2.new(1,-90, 0.5, -(IS_MOBILE and 14 or 11))
roleBadge.BackgroundColor3  = THEME.accent
roleBadge.TextColor3        = Color3.new(1,1,1)
roleBadge.Font              = Enum.Font.GothamBold
roleBadge.TextSize          = IS_MOBILE and 12 or 11
roleBadge.Text              = "SURV"
roleBadge.Parent            = titleBar
local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0,5); rc.Parent = roleBadge

RunService.Heartbeat:Connect(function()
    local r = getRole()
    roleBadge.Text             = r:upper()
    roleBadge.BackgroundColor3 = r == "Killer" and THEME.accent or Color3.fromRGB(30,140,70)
end)

-- close button
local closeBtn = Instance.new("TextButton")
closeBtn.Size               = UDim2.new(0, IS_MOBILE and 36 or 30, 0, IS_MOBILE and 36 or 30)
closeBtn.Position           = UDim2.new(1, -(IS_MOBILE and 42 or 35), 0.5, -(IS_MOBILE and 18 or 15))
closeBtn.BackgroundColor3   = Color3.fromRGB(180,40,40)
closeBtn.Text               = "✕"
closeBtn.TextColor3         = Color3.new(1,1,1)
closeBtn.Font               = Enum.Font.GothamBold
closeBtn.TextSize           = IS_MOBILE and 16 or 14
closeBtn.Parent             = titleBar
local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0,6); cc.Parent = closeBtn

local guiVisible = true
closeBtn.MouseButton1Click:Connect(function()
    guiVisible = not guiVisible
    mainFrame.Visible = guiVisible
end)

-- ── DRAG ────────────────────────────────────────────────────────
do
    local dragging, dragStart, startPos
    local function updateDrag(input)
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(0,
            startPos.X.Offset + delta.X, 0,
            startPos.Y.Offset + delta.Y)
    end

    titleBar.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or
           inp.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = inp.Position
            startPos  = mainFrame.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    titleBar.InputChanged:Connect(function(inp)
        if (inp.UserInputType == Enum.UserInputType.MouseMovement or
            inp.UserInputType == Enum.UserInputType.Touch) and dragging then
            updateDrag(inp)
        end
    end)
end

-- ── TAB SYSTEM ──────────────────────────────────────────────────
local TAB_W = IS_MOBILE and 80 or 72

local tabBar = Instance.new("Frame")
tabBar.Name             = "TabBar"
tabBar.Size             = UDim2.new(0, TAB_W, 1, -(IS_MOBILE and 48 or 40))
tabBar.Position         = UDim2.new(0, 0, 0, IS_MOBILE and 48 or 40)
tabBar.BackgroundColor3 = THEME.sidebar
tabBar.BorderSizePixel  = 0
tabBar.Parent           = mainFrame

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection  = Enum.FillDirection.Vertical
tabLayout.SortOrder      = Enum.SortOrder.LayoutOrder
tabLayout.Padding        = UDim.new(0, 2)
tabLayout.Parent         = tabBar

local contentArea = Instance.new("ScrollingFrame")
contentArea.Name                   = "ContentArea"
contentArea.Size                   = UDim2.new(1, -TAB_W, 1, -(IS_MOBILE and 48 or 40))
contentArea.Position               = UDim2.new(0, TAB_W, 0, IS_MOBILE and 48 or 40)
contentArea.BackgroundColor3       = THEME.bg
contentArea.BorderSizePixel        = 0
contentArea.ScrollBarThickness     = IS_MOBILE and 4 or 3
contentArea.ScrollBarImageColor3   = THEME.accent
contentArea.CanvasSize             = UDim2.new(0,0,0,0)
contentArea.AutomaticCanvasSize    = Enum.AutomaticSize.Y
contentArea.Parent                 = mainFrame

local contentLayout = Instance.new("UIListLayout")
contentLayout.FillDirection = Enum.FillDirection.Vertical
contentLayout.SortOrder     = Enum.SortOrder.LayoutOrder
contentLayout.Padding       = UDim.new(0, PAD)
contentLayout.Parent        = contentArea

local contentPad = Instance.new("UIPadding")
contentPad.PaddingTop    = UDim.new(0, PAD)
contentPad.PaddingLeft   = UDim.new(0, PAD)
contentPad.PaddingRight  = UDim.new(0, PAD + (IS_MOBILE and 4 or 3))
contentPad.PaddingBottom = UDim.new(0, PAD)
contentPad.Parent        = contentArea

local tabs      = {}
local tabPages  = {}
local activeTab = nil

local function createTab(name, icon, order)
    local btn = Instance.new("TextButton")
    btn.Name               = name
    btn.Size               = UDim2.new(1, 0, 0, IS_MOBILE and 64 or 54)
    btn.BackgroundColor3   = THEME.sidebar
    btn.BorderSizePixel    = 0
    btn.Text               = ""
    btn.LayoutOrder        = order
    btn.Parent             = tabBar

    local ico = Instance.new("TextLabel")
    ico.Size               = UDim2.new(1, 0, 0, IS_MOBILE and 30 or 24)
    ico.Position           = UDim2.new(0, 0, 0, IS_MOBILE and 8 or 6)
    ico.BackgroundTransparency = 1
    ico.TextColor3         = THEME.subtext
    ico.Font               = Enum.Font.GothamBold
    ico.TextSize           = IS_MOBILE and 22 or 18
    ico.Text               = icon
    ico.Parent             = btn

    local lbl = Instance.new("TextLabel")
    lbl.Size               = UDim2.new(1, 0, 0, IS_MOBILE and 18 or 14)
    lbl.Position           = UDim2.new(0, 0, 0, IS_MOBILE and 40 or 32)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3         = THEME.subtext
    lbl.Font               = Enum.Font.Gotham
    lbl.TextSize           = IS_MOBILE and 11 or 10
    lbl.Text               = name
    lbl.Parent             = btn

    -- accent line
    local line = Instance.new("Frame")
    line.Size              = UDim2.new(0, 3, 1, 0)
    line.Position          = UDim2.new(0, 0, 0, 0)
    line.BackgroundColor3  = THEME.accent
    line.BorderSizePixel   = 0
    line.Visible           = false
    line.Parent            = btn

    -- page frame (hidden by default)
    local page = Instance.new("Frame")
    page.Name              = name .. "_page"
    page.Size              = UDim2.new(1, 0, 0, 0)
    page.AutomaticSize     = Enum.AutomaticSize.Y
    page.BackgroundTransparency = 1
    page.Visible           = false
    page.LayoutOrder       = order
    page.Parent            = contentArea

    local pl = Instance.new("UIListLayout")
    pl.FillDirection  = Enum.FillDirection.Vertical
    pl.SortOrder      = Enum.SortOrder.LayoutOrder
    pl.Padding        = UDim.new(0, PAD)
    pl.Parent         = page

    tabs[name]      = { btn = btn, ico = ico, lbl = lbl, line = line }
    tabPages[name]  = page

    btn.MouseButton1Click:Connect(function()
        if activeTab == name then return end
        -- deselect old
        if activeTab then
            local old = tabs[activeTab]
            old.btn.BackgroundColor3 = THEME.sidebar
            old.ico.TextColor3       = THEME.subtext
            old.lbl.TextColor3       = THEME.subtext
            old.line.Visible         = false
            tabPages[activeTab].Visible = false
        end
        activeTab = name
        btn.BackgroundColor3         = THEME.tabSel
        ico.TextColor3               = THEME.text
        lbl.TextColor3               = THEME.text
        line.Visible                 = true
        tabPages[name].Visible       = true
        contentArea.CanvasPosition   = Vector2.zero
    end)

    return page
end

-- ── COMPONENT BUILDERS ──────────────────────────────────────────

local function makeSection(parent, label, order)
    local f = Instance.new("Frame")
    f.Size              = UDim2.new(1, 0, 0, IS_MOBILE and 28 or 22)
    f.BackgroundTransparency = 1
    f.LayoutOrder       = order or 0
    f.Parent            = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size            = UDim2.new(1,-8,1,0)
    lbl.Position        = UDim2.new(0,4,0,0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3      = THEME.accent
    lbl.Font            = Enum.Font.GothamBold
    lbl.TextSize        = IS_MOBILE and 13 or 11
    lbl.Text            = ("  " .. label:upper() .. "  "):gsub(" ", " ─ "):sub(3)
    lbl.TextXAlignment  = Enum.TextXAlignment.Left
    lbl.Parent          = f

    local line = Instance.new("Frame")
    line.Size           = UDim2.new(1,-8,0,1)
    line.Position       = UDim2.new(0,4,1,-1)
    line.BackgroundColor3 = THEME.sep
    line.BorderSizePixel  = 0
    line.Parent         = f
    return f
end

local function makeToggle(parent, label, cfgKey, order, callback)
    local f = Instance.new("Frame")
    f.Size              = UDim2.new(1,0,0,BTN_H)
    f.BackgroundColor3  = THEME.btn
    f.BorderSizePixel   = 0
    f.LayoutOrder       = order or 0
    f.Parent            = parent
    local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0,7); fc.Parent = f

    local lbl = Instance.new("TextLabel")
    lbl.Size            = UDim2.new(1,-60,1,0)
    lbl.Position        = UDim2.new(0,10,0,0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3      = THEME.text
    lbl.Font            = Enum.Font.Gotham
    lbl.TextSize        = IS_MOBILE and FONT_SZ or FONT_SZ - 1
    lbl.Text            = label
    lbl.TextXAlignment  = Enum.TextXAlignment.Left
    lbl.Parent          = f

    -- pill toggle
    local pill = Instance.new("Frame")
    pill.Size           = UDim2.new(0, IS_MOBILE and 50 or 42, 0, IS_MOBILE and 26 or 22)
    pill.Position       = UDim2.new(1,-(IS_MOBILE and 58 or 50),0.5,-(IS_MOBILE and 13 or 11))
    pill.BackgroundColor3 = CFG[cfgKey] and THEME.btnOn or THEME.btnOff
    pill.BorderSizePixel  = 0
    pill.Parent         = f
    local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(1,0); pc.Parent = pill

    local knob = Instance.new("Frame")
    knob.Size           = UDim2.new(0, IS_MOBILE and 20 or 16, 0, IS_MOBILE and 20 or 16)
    knob.Position       = CFG[cfgKey]
        and UDim2.new(1,-(IS_MOBILE and 23 or 19),0.5,-(IS_MOBILE and 10 or 8))
        or  UDim2.new(0,(IS_MOBILE and 3 or 3),0.5,-(IS_MOBILE and 10 or 8))
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.BorderSizePixel  = 0
    knob.Parent         = pill
    local kc = Instance.new("UICorner"); kc.CornerRadius = UDim.new(1,0); kc.Parent = knob

    local function setVal(v)
        CFG[cfgKey] = v
        local ti = TweenService:Create(pill, TweenInfo.new(0.15), {
            BackgroundColor3 = v and THEME.btnOn or THEME.btnOff
        })
        local tk = TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = v
                and UDim2.new(1,-(IS_MOBILE and 23 or 19),0.5,-(IS_MOBILE and 10 or 8))
                or  UDim2.new(0,(IS_MOBILE and 3 or 3),0.5,-(IS_MOBILE and 10 or 8))
        })
        ti:Play(); tk:Play()
        if callback then callback(v) end
    end

    local btn = Instance.new("TextButton")
    btn.Size            = UDim2.new(1,0,1,0)
    btn.BackgroundTransparency = 1
    btn.Text            = ""
    btn.Parent          = f
    btn.MouseButton1Click:Connect(function() setVal(not CFG[cfgKey]) end)

    -- hover
    btn.MouseEnter:Connect(function()
        TweenService:Create(f, TweenInfo.new(0.1), {BackgroundColor3 = THEME.btnHov}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(f, TweenInfo.new(0.1), {BackgroundColor3 = THEME.btn}):Play()
    end)

    return f, setVal
end

local function makeSlider(parent, label, cfgKey, min, max, order, callback)
    local f = Instance.new("Frame")
    f.Size              = UDim2.new(1,0,0,BTN_H + (IS_MOBILE and 14 or 10))
    f.BackgroundColor3  = THEME.btn
    f.BorderSizePixel   = 0
    f.LayoutOrder       = order or 0
    f.Parent            = parent
    local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0,7); fc.Parent = f

    local lbl = Instance.new("TextLabel")
    lbl.Size            = UDim2.new(1,-50,0,IS_MOBILE and 24 or 20)
    lbl.Position        = UDim2.new(0,10,0,IS_MOBILE and 6 or 4)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3      = THEME.text
    lbl.Font            = Enum.Font.Gotham
    lbl.TextSize        = IS_MOBILE and FONT_SZ or FONT_SZ - 1
    lbl.Text            = label
    lbl.TextXAlignment  = Enum.TextXAlignment.Left
    lbl.Parent          = f

    local valLbl = Instance.new("TextLabel")
    valLbl.Size         = UDim2.new(0,44,0,IS_MOBILE and 24 or 20)
    valLbl.Position     = UDim2.new(1,-54,0,IS_MOBILE and 6 or 4)
    valLbl.BackgroundTransparency = 1
    valLbl.TextColor3   = THEME.accent
    valLbl.Font         = Enum.Font.GothamBold
    valLbl.TextSize     = IS_MOBILE and FONT_SZ or FONT_SZ - 1
    valLbl.Text         = tostring(CFG[cfgKey])
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent       = f

    local track = Instance.new("Frame")
    track.Size          = UDim2.new(1,-20,0,IS_MOBILE and 8 or 6)
    track.Position      = UDim2.new(0,10,1,-(IS_MOBILE and 16 or 12))
    track.BackgroundColor3 = THEME.sep
    track.BorderSizePixel  = 0
    track.Parent        = f
    local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(1,0); tc.Parent = track

    local fill = Instance.new("Frame")
    fill.Size           = UDim2.new((CFG[cfgKey]-min)/(max-min), 0, 1, 0)
    fill.BackgroundColor3 = THEME.accent
    fill.BorderSizePixel  = 0
    fill.Parent         = track
    local flc = Instance.new("UICorner"); flc.CornerRadius = UDim.new(1,0); flc.Parent = fill

    local handle = Instance.new("TextButton")
    handle.Size         = UDim2.new(0, IS_MOBILE and 20 or 14, 0, IS_MOBILE and 20 or 14)
    handle.Position     = UDim2.new((CFG[cfgKey]-min)/(max-min), -(IS_MOBILE and 10 or 7),
                                     0.5, -(IS_MOBILE and 10 or 7))
    handle.BackgroundColor3 = Color3.new(1,1,1)
    handle.BorderSizePixel  = 0
    handle.Text         = ""
    handle.Parent       = track
    local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(1,0); hc.Parent = handle

    local sliding = false
    local function updateSlider(inputX)
        local tAbs = track.AbsolutePosition.X
        local tW   = track.AbsoluteSize.X
        local t    = math.clamp((inputX - tAbs) / tW, 0, 1)
        local val  = math.floor(min + t * (max - min))
        CFG[cfgKey] = val
        valLbl.Text = tostring(val)
        fill.Size   = UDim2.new(t, 0, 1, 0)
        handle.Position = UDim2.new(t, -(IS_MOBILE and 10 or 7), 0.5, -(IS_MOBILE and 10 or 7))
        if callback then callback(val) end
    end

    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or
           inp.UserInputType == Enum.UserInputType.Touch then
            sliding = true
        end
    end)
    UserInputSvc.InputChanged:Connect(function(inp)
        if sliding and (inp.UserInputType == Enum.UserInputType.MouseMovement or
                        inp.UserInputType == Enum.UserInputType.Touch) then
            updateSlider(inp.Position.X)
        end
    end)
    UserInputSvc.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or
           inp.UserInputType == Enum.UserInputType.Touch then
            sliding = false
        end
    end)
    track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or
           inp.UserInputType == Enum.UserInputType.Touch then
            updateSlider(inp.Position.X)
        end
    end)
    return f
end

local function makeButton(parent, label, order, callback)
    local btn = Instance.new("TextButton")
    btn.Size              = UDim2.new(1,0,0,BTN_H)
    btn.BackgroundColor3  = THEME.btn
    btn.BorderSizePixel   = 0
    btn.Text              = label
    btn.TextColor3        = THEME.text
    btn.Font              = Enum.Font.GothamBold
    btn.TextSize          = IS_MOBILE and FONT_SZ or FONT_SZ - 1
    btn.LayoutOrder       = order or 0
    btn.Parent            = parent
    local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,7); bc.Parent = btn

    btn.MouseButton1Click:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.08), {
            BackgroundColor3 = THEME.accent
        }):Play()
        task.delay(0.15, function()
            TweenService:Create(btn, TweenInfo.new(0.08), {
                BackgroundColor3 = THEME.btn
            }):Play()
        end)
        if callback then callback() end
    end)
    btn.MouseEnter:Connect(function()
        if btn.BackgroundColor3 ~= THEME.accent then
            TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = THEME.btnHov}):Play()
        end
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = THEME.btn}):Play()
    end)
    return btn
end

local function makeDropdown(parent, label, options, cfgKey, order)
    local f = Instance.new("Frame")
    f.Size              = UDim2.new(1,0,0,BTN_H)
    f.BackgroundColor3  = THEME.btn
    f.BorderSizePixel   = 0
    f.LayoutOrder       = order or 0
    f.AutomaticSize     = Enum.AutomaticSize.Y
    f.ClipsDescendants  = true
    f.Parent            = parent
    local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0,7); fc.Parent = f

    local lbl = Instance.new("TextLabel")
    lbl.Size            = UDim2.new(0.5,0,0,BTN_H)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3      = THEME.text
    lbl.Font            = Enum.Font.Gotham
    lbl.TextSize        = IS_MOBILE and FONT_SZ or FONT_SZ - 1
    lbl.Text            = label
    lbl.TextXAlignment  = Enum.TextXAlignment.Left
    lbl.Position        = UDim2.new(0,10,0,0)
    lbl.Parent          = f

    local selLbl = Instance.new("TextLabel")
    selLbl.Size         = UDim2.new(0.5,-30,0,BTN_H)
    selLbl.Position     = UDim2.new(0.5,0,0,0)
    selLbl.BackgroundTransparency = 1
    selLbl.TextColor3   = THEME.accent
    selLbl.Font         = Enum.Font.GothamBold
    selLbl.TextSize     = IS_MOBILE and FONT_SZ or FONT_SZ - 1
    selLbl.Text         = CFG[cfgKey] or options[1]
    selLbl.TextXAlignment = Enum.TextXAlignment.Right
    selLbl.Parent       = f

    local arrow = Instance.new("TextLabel")
    arrow.Size          = UDim2.new(0,22,0,BTN_H)
    arrow.Position      = UDim2.new(1,-26,0,0)
    arrow.BackgroundTransparency = 1
    arrow.TextColor3    = THEME.subtext
    arrow.Font          = Enum.Font.GothamBold
    arrow.TextSize      = 12
    arrow.Text          = "▼"
    arrow.Parent        = f

    local optFrames = {}
    local expanded  = false
    for i, opt in ipairs(options) do
        local ob = Instance.new("TextButton")
        ob.Size             = UDim2.new(1,0,0,BTN_H)
        ob.Position         = UDim2.new(0,0,0,BTN_H * i)
        ob.BackgroundColor3 = THEME.tabSel
        ob.BorderSizePixel  = 0
        ob.Text             = opt
        ob.TextColor3       = opt == CFG[cfgKey] and THEME.accent or THEME.text
        ob.Font             = Enum.Font.Gotham
        ob.TextSize         = IS_MOBILE and FONT_SZ or FONT_SZ - 1
        ob.Parent           = f
        table.insert(optFrames, ob)
        ob.MouseButton1Click:Connect(function()
            CFG[cfgKey] = opt
            selLbl.Text  = opt
            for _, ob2 in ipairs(optFrames) do
                ob2.TextColor3 = ob2.Text == opt and THEME.accent or THEME.text
            end
            expanded = false
            f.ClipsDescendants = true
            f.Size = UDim2.new(1,0,0,BTN_H)
            arrow.Text = "▼"
        end)
    end

    local headerBtn = Instance.new("TextButton")
    headerBtn.Size   = UDim2.new(1,0,0,BTN_H)
    headerBtn.BackgroundTransparency = 1
    headerBtn.Text   = ""
    headerBtn.Parent = f
    headerBtn.MouseButton1Click:Connect(function()
        expanded = not expanded
        f.ClipsDescendants = not expanded
        f.Size = UDim2.new(1,0,0, expanded and BTN_H * (#options + 1) or BTN_H)
        arrow.Text = expanded and "▲" or "▼"
    end)
    return f
end

-- ── BUILD TABS ──────────────────────────────────────────────────
-- Tabs: ESP | Survivor | Killer | Visuals | Misc

local pgESP      = createTab("ESP",      "👁",  1)
local pgSurvivor = createTab("Surv",     "🏃",  2)
local pgKiller   = createTab("Kill",     "🔪",  3)
local pgVisuals  = createTab("Visual",   "🎨",  4)
local pgMisc     = createTab("Misc",     "⚙",   5)

-- ─── ESP PAGE ────────────────────────────────────────────────────
do
    makeSection(pgESP, "Players", 1)
    makeToggle(pgESP, "Survivor ESP",   "espSurvivor", 2)
    makeToggle(pgESP, "Killer ESP",     "espKiller",   3)
    makeSection(pgESP, "Map Objects", 4)
    makeToggle(pgESP, "Generator ESP",  "espGen",      5)
    makeToggle(pgESP, "Hook ESP",       "espHook",     6)
    makeToggle(pgESP, "Pallet ESP",     "espPallet",   7)
    makeToggle(pgESP, "Vault ESP",      "espVault",    8)
    makeToggle(pgESP, "Exit Gate ESP",  "espExit",     9)
    makeToggle(pgESP, "Chest ESP",      "espChest",    10)
    makeSection(pgESP, "Settings", 11)
    makeSlider(pgESP, "Max Distance",   "espMaxDist",  50, 1000, 12)
    makeToggle(pgESP, "Full ESP",       "esp",         13)
end

-- ─── SURVIVOR PAGE ──────────────────────────────────────────────
do
    makeSection(pgSurvivor, "Generator", 1)
    makeToggle(pgSurvivor, "Auto Generator", "autoGen", 2, function(v)
        CFG.autoGen = v
        if v then startAutoGen() else stopAutoGen() end
    end)
    makeToggle(pgSurvivor, "Auto Skillcheck", "autoSkillcheck", 3)
    makeDropdown(pgSurvivor, "Skillcheck Mode", {"Normal","Perfect","Instant"}, "skillcheckMode", 4)
    makeSlider(pgSurvivor, "Gen Range (studs)", "autoGenRange", 2, 20, 5)

    makeSection(pgSurvivor, "Combat / Chase", 6)
    makeToggle(pgSurvivor, "Anti Knock (Struggle)", "antiKnock", 7, function(v)
        CFG.antiKnock = v
        if v then startAntiKnock() end
    end)
    makeToggle(pgSurvivor, "Flee Killer",    "fleeKiller",  8)
    makeSlider(pgSurvivor, "Flee Distance",  "fleeKillerDist", 5, 50, 9)
    makeToggle(pgSurvivor, "Swift Vault",    "swiftVault",  10)

    makeSection(pgSurvivor, "Healing", 11)
    makeToggle(pgSurvivor, "Auto Heal",      "autoHeal",    12, function(v)
        CFG.autoHeal = v
        if v then startHeal() end
    end)
    makeButton(pgSurvivor, "Manual Heal Now", 13, function()
        for i = 1, 8 do
            fireRemotes({"heal","bandage","recover","health"})
            task.wait(0.05)
        end
        notify("Heal", "Fired ×8", 1)
    end)

    makeSection(pgSurvivor, "Escape", 14)
    makeToggle(pgSurvivor, "Auto Exit Gate", "autoExit", 15, function(v)
        CFG.autoExit = v
        if v then startAutoExit() end
    end)
    makeButton(pgSurvivor, "TP Nearest Gen", 16, function()
        local hrp = getHRP(); if not hrp then return end
        local gens = scan("generator")
        local n, nd = nil, math.huge
        for _, g in ipairs(gens) do
            local p = modelPos(g)
            if p then
                local d = vecDist(hrp.Position, p)
                if d < nd then nd = d; n = p end
            end
        end
        if n then
            hrp.CFrame = CFrame.new(n + Vector3.new(0,4,2))
            notify("TP", "Teleported to Gen", 1)
        end
    end)
    makeButton(pgSurvivor, "TP Nearest Exit", 17, function()
        local hrp = getHRP(); if not hrp then return end
        local exits = scan("exit")
        local n, nd = nil, math.huge
        for _, eg in ipairs(exits) do
            local p = modelPos(eg)
            if p then
                local d = vecDist(hrp.Position, p)
                if d < nd then nd = d; n = p end
            end
        end
        if n then
            hrp.CFrame = CFrame.new(n + Vector3.new(0,4,2))
            notify("TP", "Teleported to Exit", 1)
        end
    end)
end

-- ─── KILLER PAGE ────────────────────────────────────────────────
do
    makeSection(pgKiller, "Attack", 1)
    makeToggle(pgKiller, "Auto Attack",      "autoAttack",    2)
    makeSlider(pgKiller, "Attack Range",     "attackRange",   3, 30, 3)
    makeToggle(pgKiller, "Hitbox Expand",    "hitboxExpand",  4)
    makeSlider(pgKiller, "Hitbox Size",      "hitboxSize",    3, 30, 5)
    makeToggle(pgKiller, "Infinite Lunge",   "infiniteLunge", 6)

    makeSection(pgKiller, "Gameplay", 7)
    makeToggle(pgKiller, "Auto Hook",        "autoHook",      8)
    makeToggle(pgKiller, "Kick Generator",   "kickGen",       9)
    makeToggle(pgKiller, "Destroy Pallet",   "destroyPallet", 10)
    makeToggle(pgKiller, "Invisibility",     "killerInvis",   11, function(v)
        setKillerInvis(v)
    end)

    makeSection(pgKiller, "Teleport", 12)
    makeButton(pgKiller, "TP to Nearest Survivor", 13, function()
        local hrp = getHRP(); if not hrp then return end
        local n, nd = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LP then continue end
            local c = p.Character; if not c then continue end
            local ph = c:FindFirstChild("HumanoidRootPart"); if not ph then continue end
            local d = vecDist(hrp.Position, ph.Position)
            if d < nd then nd = d; n = ph.Position end
        end
        if n then
            hrp.CFrame = CFrame.new(n + Vector3.new(0,4,0))
            notify("TP", "On top of survivor", 1)
        end
    end)
    makeButton(pgKiller, "TP to Nearest Gen", 14, function()
        local hrp = getHRP(); if not hrp then return end
        local gens = scan("generator")
        local n, nd = nil, math.huge
        for _, g in ipairs(gens) do
            local p = modelPos(g)
            if p then
                local d = vecDist(hrp.Position, p)
                if d < nd then nd = d; n = p end
            end
        end
        if n then
            hrp.CFrame = CFrame.new(n + Vector3.new(0,4,2))
            notify("TP", "Teleported to Gen", 1)
        end
    end)
end

-- ─── VISUALS PAGE ───────────────────────────────────────────────
do
    makeSection(pgVisuals, "Lighting", 1)
    makeToggle(pgVisuals, "Fullbright",    "fullbright",  2, function(v)
        setFullbright(v)
    end)

    makeSection(pgVisuals, "Camera", 3)
    makeToggle(pgVisuals, "Custom FOV",   "customFOV",   4)
    makeSlider(pgVisuals, "FOV Value",    "fovVal",      60, 120, 5, function(v)
        if CFG.customFOV then
            Workspace.CurrentCamera.FieldOfView = v
        end
    end)

    RunService.RenderStepped:Connect(function()
        if CFG.customFOV then
            Workspace.CurrentCamera.FieldOfView = CFG.fovVal
        end
    end)
end

-- ─── MISC PAGE ──────────────────────────────────────────────────
do
    makeSection(pgMisc, "Movement", 1)
    makeToggle(pgMisc, "Speed Hack",   "speed",   2)
    makeSlider(pgMisc, "Walk Speed",   "speedVal", 16, 100, 3)
    makeToggle(pgMisc, "Noclip",       "noclip",  4)
    makeToggle(pgMisc, "Fly",          "fly",     5, function(v)
        if v then startFly() else stopFly() end
    end)
    makeSlider(pgMisc, "Fly Speed",    "flySpeed", 10, 120, 6)

    makeSection(pgMisc, "Game", 7)
    makeToggle(pgMisc, "Anti AFK",     "antiAFK", 8)
    makeToggle(pgMisc, "Watermark",    "watermark", 9)

    makeSection(pgMisc, "Swift Vault (PC)", 10)
    if not IS_MOBILE then
        makeButton(pgMisc, "Swift Vault [V]", 11, trySwiftVault)
    end

    makeSection(pgMisc, "Debug", 12)
    makeButton(pgMisc, "Clear Remote Cache", 13, function()
        remCache = {}
        notify("Cache", "Remote cache cleared", 1)
    end)
    makeButton(pgMisc, "Clear Map Cache", 14, function()
        clearCache()
        notify("Cache", "Map scan cache cleared", 1)
    end)
    makeButton(pgMisc, "Dump Remotes to Console", 15, function()
        for _, v in ipairs(RS:GetDescendants()) do
            if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
                print("[VDHub Remote]", v:GetFullName())
            end
        end
        notify("Debug", "Remotes printed to console", 2)
    end)
end

-- select first tab
tabs["ESP"].btn.MouseButton1Click:Fire()

-- ── MOBILE TOUCH BUTTONS ────────────────────────────────────────
-- On mobile there are no keybinds — dedicated HUD buttons on screen edge
if IS_MOBILE then
    local hudGui = Instance.new("ScreenGui")
    hudGui.Name           = "VDHub_MobileHUD"
    hudGui.ResetOnSpawn   = false
    hudGui.IgnoreGuiInset = true
    hudGui.DisplayOrder   = 998
    hudGui.Parent         = CoreGui

    local BTN_SZ = 58
    local BTN_COLS = { on = Color3.fromRGB(40,160,70), off = Color3.fromRGB(60,20,20) }

    local function mobileFab(icon, label, xOff, yOff, callback)
        local container = Instance.new("Frame")
        container.Size              = UDim2.new(0, BTN_SZ, 0, BTN_SZ + 18)
        container.Position          = UDim2.new(1, xOff, 1, yOff)
        container.BackgroundTransparency = 1
        container.Parent            = hudGui

        local btn = Instance.new("TextButton")
        btn.Size              = UDim2.new(1,0,0,BTN_SZ)
        btn.BackgroundColor3  = Color3.fromRGB(20,20,30)
        btn.BorderSizePixel   = 0
        btn.Text              = icon
        btn.TextSize          = 24
        btn.Font              = Enum.Font.GothamBold
        btn.TextColor3        = Color3.new(1,1,1)
        btn.Parent            = container
        local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,12); bc.Parent = btn

        local lbl = Instance.new("TextLabel")
        lbl.Size              = UDim2.new(1,0,0,16)
        lbl.Position          = UDim2.new(0,0,1,1)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3        = Color3.fromRGB(180,180,200)
        lbl.Font              = Enum.Font.Gotham
        lbl.TextSize          = 10
        lbl.Text              = label
        lbl.Parent            = container

        btn.MouseButton1Click:Connect(function() callback(btn) end)
        return btn, container
    end

    -- Row of buttons on bottom-right, above the jump button
    local hubs = {
        { "👁",  "ESP",      "esp",      nil },
        { "⚡",  "Speed",    "speed",    nil },
        { "🌓",  "Bright",   "fullbright", function(v) setFullbright(v) end },
        { "🔧",  "AutoGen",  "autoGen",  function(v)
                    if v then startAutoGen() else stopAutoGen() end
                end },
        { "✈",  "Fly",      "fly",      function(v)
                    if v then startFly() else stopFly() end
                end },
        { "👻",  "NoClip",  "noclip",   nil },
        { "💊",  "Heal",    "autoHeal", function(v)
                    if v then startHeal() end
                end },
    }

    -- layout: right side stack, evenly spaced bottom-up
    for i, h in ipairs(hubs) do
        local icon, lbl, cfgKey, cb = h[1], h[2], h[3], h[4]
        local xOff = -(i * (BTN_SZ + 6) - 6 + BTN_SZ) -- right-to-left
        local btn, _ = mobileFab(icon, lbl, -(BTN_SZ + 6) * (i-1) - 8, -(BTN_SZ + 26) - 10,
            function(b)
                CFG[cfgKey] = not CFG[cfgKey]
                b.BackgroundColor3 = CFG[cfgKey]
                    and BTN_COLS.on or BTN_COLS.off
                if cb then cb(CFG[cfgKey]) end
                notify(lbl, CFG[cfgKey] and "ON" or "OFF", 1)
            end
        )
        btn.BackgroundColor3 = CFG[cfgKey] and BTN_COLS.on or BTN_COLS.off
    end

    -- toggle main GUI button (top-left corner)
    local guiToggle = Instance.new("TextButton")
    guiToggle.Size              = UDim2.new(0,52,0,52)
    guiToggle.Position          = UDim2.new(0,8,0,50)
    guiToggle.BackgroundColor3  = Color3.fromRGB(20,20,30)
    guiToggle.BorderSizePixel   = 0
    guiToggle.Text              = "🔪"
    guiToggle.TextSize          = 24
    guiToggle.Font              = Enum.Font.GothamBold
    guiToggle.TextColor3        = Color3.new(1,1,1)
    guiToggle.Parent            = hudGui
    local gtc = Instance.new("UICorner"); gtc.CornerRadius = UDim.new(0,12); gtc.Parent = guiToggle

    local uiStroke2 = Instance.new("UIStroke")
    uiStroke2.Color     = THEME.accent
    uiStroke2.Thickness = 1.5
    uiStroke2.Parent    = guiToggle

    guiToggle.MouseButton1Click:Connect(function()
        guiVisible = not guiVisible
        mainFrame.Visible = guiVisible
    end)
end

-- ── PC KEYBINDS ─────────────────────────────────────────────────
if not IS_MOBILE then
    UserInputSvc.InputBegan:Connect(function(inp, gp)
        if gp then return end
        if inp.KeyCode == Enum.KeyCode.RightShift then
            guiVisible = not guiVisible
            mainFrame.Visible = guiVisible
        elseif inp.KeyCode == Enum.KeyCode.V then
            trySwiftVault()
        end
    end)
end

-- ── WATERMARK ───────────────────────────────────────────────────
local wm = Instance.new("ScreenGui")
wm.Name           = "VDHub_WM"
wm.ResetOnSpawn   = false
wm.IgnoreGuiInset = true
wm.DisplayOrder   = 997
wm.Parent         = CoreGui

local wmLbl = Instance.new("TextLabel")
wmLbl.Size              = UDim2.new(0, IS_MOBILE and 260 or 240, 0, IS_MOBILE and 28 or 22)
wmLbl.Position          = UDim2.new(0, 8, 0, IS_MOBILE and 8 or 6)
wmLbl.BackgroundColor3  = Color3.fromRGB(10,10,16)
wmLbl.BackgroundTransparency = 0.3
wmLbl.TextColor3        = THEME.accent
wmLbl.Font              = Enum.Font.GothamBold
wmLbl.TextSize          = IS_MOBILE and 13 or 11
wmLbl.Text              = "VD Hub v2  |  Delta  |  Loading..."
wmLbl.BorderSizePixel   = 0
wmLbl.Parent            = wm
local wmc = Instance.new("UICorner"); wmc.CornerRadius = UDim.new(0,5); wmc.Parent = wmLbl

RunService.Heartbeat:Connect(function()
    if not CFG.watermark then wmLbl.Visible = false; return end
    wmLbl.Visible = true
    local role = getRole()
    local fps  = math.floor(1 / RunService.RenderStepped:Wait())
    local kp   = killerPlayer
    local kName = kp and kp.Name or "none"
    wmLbl.Text = string.format(
        "VD Hub v2  |  %s  |  FPS:%d  |  K:%s",
        role, fps, kName
    )
end)

-- ── DONE ────────────────────────────────────────────────────────
task.wait(1)
notify(
    "VD Hub v2 Loaded",
    IS_MOBILE
        and "🔪 Button = toggle menu | Fab buttons = quick toggles"
        or  "RShift = toggle menu | V = swift vault",
    6
)
print("[VDHub] Running on", IS_MOBILE and "MOBILE" or "PC")
print("[VDHub] Role:", getRole())
print("[VDHub] PlaceId:", game.PlaceId)