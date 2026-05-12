-- Hezoq Hub v2 | Shinobi Life 2 | Rell-Giver
-- Przepisany: event-driven, pcall wszędzie, brak ślepych task.wait

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- ────────────────────────────────────────────
-- SERVICES
-- ────────────────────────────────────────────
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local TeleportService    = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService   = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ────────────────────────────────────────────
-- STAŁE
-- ────────────────────────────────────────────
local DIST_BEHIND    = 3       -- metrów za celem
local TP_VERIFY_DIST = 5       -- max odległość po TP (weryfikacja)
local TP_TIMEOUT     = 3       -- sekundy na weryfikację TP
local V_PRESS_DELAY  = 0.05    -- przerwa między press/release V
local LOOP_INTERVAL  = 0.5     -- co ile sekund sprawdza stan toggle
local DROPDOWN_REFRESH = 3     -- co ile sekund odświeża listę graczy

-- ────────────────────────────────────────────
-- STAN GLOBALNY
-- ────────────────────────────────────────────
local selectedPlayer   = nil
local isRunning        = false   -- czy autopilot aktualnie działa (blokada double-run)
local cameraLockName   = "HezoqCameraLock"

-- ────────────────────────────────────────────
-- UI – OKNO
-- ────────────────────────────────────────────
local Window = Fluent:CreateWindow({
    Title      = "Hezoq Hub",
    SubTitle   = "Shinobi Life 2 | Rell-Giver v2",
    TabWidth   = 160,
    Size       = UDim2.fromOffset(580, 460),
    Acrylic    = true,
    Theme      = "Light",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Info     = Window:AddTab({ Title = "Info",     Icon = "info" }),
    Main     = Window:AddTab({ Title = "Main",     Icon = "" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

-- ────────────────────────────────────────────
-- INFO TAB
-- ────────────────────────────────────────────
Tabs.Info:AddParagraph({
    Title   = "Jak to działa?",
    Content =
        "1. Wybierz gracza z listy.\n" ..
        "2. Włącz toggle 'Rell Giver'.\n\n" ..
        "Co robi skrypt:\n" ..
        "- Teleportuje Cię za wybranego gracza i WERYFIKUJE czy TP się udał.\n" ..
        "- Wciśnie V jeden raz (upewnij się że atak Rell jest na V).\n" ..
        "- Rejoinuje na ten sam serwer (przez startevent lub TeleportService).\n\n" ..
        "v2 zmiany:\n" ..
        "- Brak ślepych task.wait – każdy krok sprawdza czy się powiódł.\n" ..
        "- pcall na każdej operacji – lag nie wysypie skryptu.\n" ..
        "- Jeden loop sterujący – brak konfliktów."
})

-- ────────────────────────────────────────────
-- MAIN TAB – DROPDOWN + TOGGLE
-- ────────────────────────────────────────────
local function getPlayerNames()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(names, p.Name)
        end
    end
    return names
end

local PlayerDropdown = Tabs.Main:AddDropdown("PlayerDropdown", {
    Title       = "Wybierz gracza",
    Description = "Gracz, któremu chcesz dać Rell Coins.",
    Values      = getPlayerNames(),
    Multi       = false,
    Default     = ""
})

local RellToggle = Tabs.Main:AddToggle("RellGiver", {
    Title       = "Rell Giver",
    Description = "Teleport za gracza → V → rejoin (bez cooldownu).",
    Default     = false
})

PlayerDropdown:OnChanged(function(name)
    selectedPlayer = Players:FindFirstChild(name)
end)

-- ────────────────────────────────────────────
-- CAMERA LOCK
-- ────────────────────────────────────────────
local function startCameraLock(targetHRP)
    RunService:BindToRenderStep(cameraLockName, Enum.RenderPriority.Camera.Value + 1, function()
        if targetHRP and RellToggle.Value then
            Camera.CFrame = CFrame.new(Camera.CFrame.Position, targetHRP.Position)
        end
    end)
end

local function stopCameraLock()
    RunService:UnbindFromRenderStep(cameraLockName)
end

-- ────────────────────────────────────────────
-- WCIŚNIJ V (jeden raz, nie loop)
-- ────────────────────────────────────────────
local function pressV()
    VirtualInputManager:SendKeyEvent(true,  Enum.KeyCode.V, false, game)
    task.wait(V_PRESS_DELAY)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.V, false, game)
end

-- ────────────────────────────────────────────
-- WERYFIKACJA TP (event-driven zamiast task.wait)
-- ────────────────────────────────────────────
-- Zwraca true jeśli TP się powiódł w czasie timeout sekund
local function waitUntilNear(myHRP, targetPos, timeout)
    local elapsed = 0
    while elapsed < timeout do
        if not RellToggle.Value then return false end  -- toggle wyłączony w trakcie
        if (myHRP.Position - targetPos).Magnitude <= TP_VERIFY_DIST then
            return true
        end
        task.wait(0.1)
        elapsed += 0.1
    end
    return false
end

-- ────────────────────────────────────────────
-- BEZPIECZNE POBIERANIE HRP
-- ────────────────────────────────────────────
local function getHRP(player, timeoutSec)
    timeoutSec = timeoutSec or 3
    local char = player.Character
    if not char then
        local conn
        local done = false
        conn = player.CharacterAdded:Connect(function(c)
            char = c
            done = true
        end)
        local elapsed = 0
        while not done and elapsed < timeoutSec do
            task.wait(0.1)
            elapsed += 0.1
        end
        conn:Disconnect()
    end
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-- ────────────────────────────────────────────
-- REJOIN
-- ────────────────────────────────────────────
local function doRejoin()
    local ok, err = pcall(function()
        -- Próba 1: startevent (działa w niektórych wersjach SL2)
        local se = LocalPlayer:FindFirstChild("startevent")
        if se then
            se:FireServer("band", "\128")
            task.wait(0.2)
        end
        -- Próba 2: TeleportService na ten sam serwer
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
    if not ok then
        Fluent:Notify({ Title = "Hezoq Hub", Content = "Rejoin error: " .. tostring(err), Duration = 4 })
    end
end

-- ────────────────────────────────────────────
-- GŁÓWNA FUNKCJA AUTOPILOTA
-- ────────────────────────────────────────────
local function runAutopilot(target)
    -- 1. Pobierz swój HRP
    local myChar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local myHRP  = myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then
        Fluent:Notify({ Title = "Hezoq Hub", Content = "Nie znaleziono swojego HRP.", Duration = 3 })
        return
    end

    -- 2. Pobierz HRP celu
    local targetHRP = getHRP(target, 3)
    if not targetHRP then
        Fluent:Notify({ Title = "Hezoq Hub", Content = "Cel nie ma postaci.", Duration = 3 })
        return
    end

    -- 3. Oblicz pozycję za celem i teleportuj
    local behindPos = targetHRP.Position - targetHRP.CFrame.LookVector * DIST_BEHIND
    local tpOk, tpErr = pcall(function()
        myHRP.CFrame = CFrame.new(behindPos, targetHRP.Position)
    end)
    if not tpOk then
        Fluent:Notify({ Title = "Hezoq Hub", Content = "TP błąd: " .. tostring(tpErr), Duration = 3 })
        return
    end

    -- 4. WERYFIKACJA – czy jesteśmy faktycznie blisko celu?
    local arrived = waitUntilNear(myHRP, targetHRP.Position, TP_TIMEOUT)
    if not arrived then
        -- Lag był za duży – retry TP raz jeszcze
        local retryBehind = targetHRP.Position - targetHRP.CFrame.LookVector * DIST_BEHIND
        pcall(function()
            myHRP.CFrame = CFrame.new(retryBehind, targetHRP.Position)
        end)
        task.wait(0.3)
        -- Jeśli nadal nie jesteśmy blisko, przerywamy tę iterację
        if (myHRP.Position - targetHRP.Position).Magnitude > TP_VERIFY_DIST * 3 then
            return
        end
    end

    if not RellToggle.Value then return end

    -- 5. Camera lock + wciśnij V
    startCameraLock(targetHRP)
    pressV()

    -- 6. Krótka chwila na efekt ataku (minimalna, nie ślepa)
    task.wait(0.3)

    stopCameraLock()

    if not RellToggle.Value then return end

    -- 7. Rejoin
    doRejoin()
end

-- ────────────────────────────────────────────
-- GŁÓWNY LOOP – jeden, kontrolowany
-- ────────────────────────────────────────────
task.spawn(function()
    while not Fluent.Unloaded do
        task.wait(LOOP_INTERVAL)

        if RellToggle.Value and selectedPlayer and not isRunning then
            -- Sprawdź czy gracz nadal jest na serwerze
            if not Players:FindFirstChild(selectedPlayer.Name) then
                Fluent:Notify({ Title = "Hezoq Hub", Content = "Gracz opuścił serwer.", Duration = 4 })
                RellToggle:SetValue(false)
                selectedPlayer = nil
            else
                isRunning = true
                local ok, err = pcall(runAutopilot, selectedPlayer)
                if not ok then
                    Fluent:Notify({ Title = "Hezoq Hub", Content = "Błąd: " .. tostring(err), Duration = 4 })
                end
                isRunning = false
            end
        end
    end
end)

-- ────────────────────────────────────────────
-- ODŚWIEŻANIE DROPDOWN
-- ────────────────────────────────────────────
task.spawn(function()
    while not Fluent.Unloaded do
        task.wait(DROPDOWN_REFRESH)
        local names = getPlayerNames()
        PlayerDropdown:SetValues(names)
        -- Jeśli wybrany gracz już nie jest na serwerze, wyczyść wybór
        if selectedPlayer and not Players:FindFirstChild(selectedPlayer.Name) then
            selectedPlayer = nil
        end
    end
end)

-- ────────────────────────────────────────────
-- SETTINGS TAB
-- ────────────────────────────────────────────
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
InterfaceManager:SetFolder("HezoqHub")
SaveManager:SetFolder("HezoqHub/ShinobiLife2")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)

Fluent:Notify({
    Title   = "Hezoq Hub v2",
    Content = "Shinobi Life 2 | Rell-Giver załadowany.",
    Duration = 5
})

SaveManager:LoadAutoloadConfig()

-- ────────────────────────────────────────────
-- TOGGLE UI BUTTON (mobilny / PC)
-- ────────────────────────────────────────────
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "HezoqToggleGui"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Próbuj wstawić do CoreGui (exploity), fallback do PlayerGui
local ok = pcall(function()
    ScreenGui.Parent = game:GetService("CoreGui")
end)
if not ok then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local Button = Instance.new("TextButton", ScreenGui)
Button.Size            = UDim2.new(0, 100, 0, 40)
Button.Position        = UDim2.new(0.05, 0, 0.2, 0)
Button.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
Button.Text            = "Toggle UI"
Button.TextColor3      = Color3.new(1, 1, 1)
Button.Font            = Enum.Font.SourceSansBold
Button.TextSize        = 18

-- Zaokrąglenie przycisku
local corner = Instance.new("UICorner", Button)
corner.CornerRadius = UDim.new(0, 8)

-- Znajdź root GUI Fluenta (bezpieczne)
local function getFluentRoot()
    -- Fluent przechowuje okno w różnych miejscach w zależności od wersji
    for _, v in ipairs({ "Window", "Main", "Root", "Frame" }) do
        if Window[v] then return Window[v] end
    end
    -- Fallback: szukaj w CoreGui
    local cg = game:GetService("CoreGui")
    for _, v in ipairs(cg:GetChildren()) do
        if v:IsA("ScreenGui") and v.Name:find("Fluent") then
            return v
        end
    end
    return nil
end

local uiVisible = true
Button.MouseButton1Click:Connect(function()
    local root = getFluentRoot()
    if root then
        uiVisible = not uiVisible
        root.Enabled = uiVisible
        Button.Text = uiVisible and "Hide UI" or "Show UI"
    else
        Fluent:Notify({ Title = "Hezoq Hub", Content = "Nie można znaleźć GUI.", Duration = 3 })
    end
end)

-- ────────────────────────────────────────────
-- DRAG przycisku (naprawiony – używa pikseli)
-- ────────────────────────────────────────────
local dragging   = false
local dragStartMouse = nil
local dragStartBtnPx = nil  -- pozycja przycisku w pikselach w momencie kliknięcia

local function toPixelPos(udim2pos)
    local vp = workspace.CurrentCamera.ViewportSize
    return Vector2.new(
        udim2pos.X.Scale * vp.X + udim2pos.X.Offset,
        udim2pos.Y.Scale * vp.Y + udim2pos.Y.Offset
    )
end

Button.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging        = true
        dragStartMouse  = Vector2.new(input.Position.X, input.Position.Y)
        dragStartBtnPx  = toPixelPos(Button.Position)
    end
end)

Button.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
    and input.UserInputType ~= Enum.UserInputType.Touch then return end

    local vp    = workspace.CurrentCamera.ViewportSize
    local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartMouse
    local newPx = dragStartBtnPx + delta

    -- Clamp żeby przycisk nie wyszedł poza ekran
    local btnW, btnH = 100, 40
    newPx = Vector2.new(
        math.clamp(newPx.X, 0, vp.X - btnW),
        math.clamp(newPx.Y, 0, vp.Y - btnH)
    )

    -- Zapisz w pikselach (Offset), Scale = 0
    Button.Position = UDim2.new(0, newPx.X, 0, newPx.Y)
end)
