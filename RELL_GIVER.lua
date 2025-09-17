

-- Hezoq Hub Full SL2 (Rell-Giver z Info tabem + Toggle UI button)
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local distanceBehind = 3

-- Window
local Window = Fluent:CreateWindow({
    Title = "Hezoq Hub",
    SubTitle = "Shinobi Life 2 | Rell-Giver",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Light",
    MinimizeKey = Enum.KeyCode.LeftControl
})

-- Tabs (Info na samej górze)
local Tabs = {
    Info = Window:AddTab({ Title = "Info", Icon = "info" }),
    Main = Window:AddTab({ Title = "Main", Icon = "" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

-- Info Tab content
Tabs.Info:AddParagraph({
    Title = "How does it work?",
    Content = "1. Select the player you want to give Rell Coins to.\n" ..
              "2. Enable the 'Rell Giver' toggle.\n\n" ..
              "What does it do?\n" ..
              "- Teleports you behind the selected player.\n" ..
              "- Automatically presses 'V' (⚠️ make sure your Rell attack is bound to the V key).\n" ..
              "- After attacking, the script rejoins you to the same server.\n" ..
              "- This allows you to attack again without cooldown."
})

-- Dropdown graczy
local function getPlayers()
    local a = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(a, p.Name)
        end
    end
    return a
end

local PlayerDropdown = Tabs.Main:AddDropdown("PlayerDropdown", {
    Title = "Select Player",
    Description = "Choose a player to follow and give Rell Coins to.",
    Values = getPlayers(),
    Multi = false,
    Default = ""
})

-- Toggle Rell Giver 
local AutoFarmToggle = Tabs.Main:AddToggle("AutoTPBandV", {
    Title = "Rell Giver",
    Description = "Teleports behind the selected player, auto-presses V, then rejoins for no cooldown.",
    Default = false
})

local selectedUser = nil
PlayerDropdown:OnChanged(function(selected)
    selectedUser = Players:FindFirstChild(selected)
    print("Selected player:", selected)
end)

-- AutoV zmienna sterująca pętlą
local AutoVEnabled = false
local CameraLockName = "CameraLock"

-- Funkcja start/stop autopress V
local function handleAutoV(enable)
    AutoVEnabled = enable
    if enable then
        spawn(function()
            while AutoVEnabled do
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.V, false, game)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.V, false, game)
                task.wait(0.1)
            end
        end)
    end
end

-- Funkcja start/stop Camera Lock
local function startCameraLock(targetHRP)
    RunService:BindToRenderStep(CameraLockName, Enum.RenderPriority.Camera.Value + 1, function()
        if targetHRP and AutoFarmToggle.Value then
            Camera.CFrame = CFrame.new(Camera.CFrame.Position, targetHRP.Position)
        end
    end)
end

local function stopCameraLock()
    RunService:UnbindFromRenderStep(CameraLockName)
end

-- Funkcja autopilota: TP → 5s → AutoV → 7s → Band → teleport
local function autopilot(target)
    if not target then return end
    local myChar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local myHRP = myChar:WaitForChild("HumanoidRootPart")
    local targetChar = target.Character or target.CharacterAdded:Wait()
    local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
    if not targetHRP then return end

    local behindPos = targetHRP.Position - targetHRP.CFrame.LookVector * distanceBehind
    myHRP.CFrame = CFrame.new(behindPos, targetHRP.Position)

    startCameraLock(targetHRP)
    task.wait(5)
    handleAutoV(true)

    local elapsed = 0
    while elapsed < 7 and AutoFarmToggle.Value do
        task.wait(0.1)
        elapsed = elapsed + 0.1
    end

    handleAutoV(false)
    stopCameraLock()

    if not AutoFarmToggle.Value then return end

    pcall(function()
        if LocalPlayer:FindFirstChild("startevent") then
            LocalPlayer.startevent:FireServer("band", "\128")
        end
        task.wait()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
end

-- Loop toggle autopilot
task.spawn(function()
    while true do
        task.wait(1)
        if Fluent.Unloaded then break end
        if AutoFarmToggle.Value and selectedUser then
            autopilot(selectedUser)
        end
    end
end)

-- Loop: teleport co 2 sekundy
task.spawn(function()
    while true do
        task.wait(2)
        if Fluent.Unloaded then break end
        if selectedUser and AutoFarmToggle.Value then
            local myChar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            local myHRP = myChar:WaitForChild("HumanoidRootPart")
            local targetChar = selectedUser.Character or selectedUser.CharacterAdded:Wait()
            local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
            if targetHRP then
                myHRP.CFrame = CFrame.new(targetHRP.Position - targetHRP.CFrame.LookVector * distanceBehind, targetHRP.Position)
            end
        end
    end
end)

-- Odświeżanie dropdown co 3 sekundy
task.spawn(function()
    while true do
        task.wait(3)
        if Fluent.Unloaded then break end
        PlayerDropdown:SetValues(getPlayers())
    end
end)

-- Settings Tab: config manager
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
InterfaceManager:SetFolder("HezoqHub")
SaveManager:SetFolder("HezoqHub/ShinobiLife2")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
Window:SelectTab(1)

-- Notification
Fluent:Notify({
    Title = "Hezoq Hub",
    Content = "Shinobi Life 2 | Rell-Giver script loaded.",
    Duration = 5
})

SaveManager:LoadAutoloadConfig()

--------------------------------------------------
-- 🔘 Mobile/PC Toggle UI button
--------------------------------------------------
local ScreenGui = Instance.new("ScreenGui", game:GetService("CoreGui"))
local Button = Instance.new("TextButton", ScreenGui)
Button.Size = UDim2.new(0, 100, 0, 40)
Button.Position = UDim2.new(0.05, 0, 0.2, 0)
Button.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
Button.Text = "Toggle UI"
Button.TextColor3 = Color3.new(1,1,1)
Button.Font = Enum.Font.SourceSansBold
Button.TextSize = 18
Button.Active = true
Button.Draggable = false -- custom drag

-- toggle działa poprawnie
Button.MouseButton1Click:Connect(function()
    local gui = Window.Window or Window.Main or Window.Root
    if gui then
        local isVisible = gui.Visible
        gui.Visible = not isVisible
        Button.Text = isVisible and "Show UI" or "Hide UI"
    else
        Fluent:Notify({Title="Hezoq Hub", Content="Cannot find GUI to toggle.", Duration=3})
    end
end)

-- draggable fix (procenty ekranu)
local dragging, dragInput, dragStart, startPos

Button.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Button.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

Button.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging and dragStart and startPos then
        local delta = input.Position - dragStart
        local viewport = workspace.CurrentCamera.ViewportSize
        local newX = (startPos.X.Offset + delta.X) / viewport.X
        local newY = (startPos.Y.Offset + delta.Y) / viewport.Y
        newX = math.clamp(newX, 0, 1)
        newY = math.clamp(newY, 0, 1)
        Button.Position = UDim2.new(newX, 0, newY, 0)
    end
end)SaveManager:SetFolder("HezoqHub/ShinobiLife2")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)

-- Notification
Fluent:Notify({
    Title = "Hezoq Hub",
    Content = "Shinobi Life 2 script loaded.",
    Duration = 5
})

-- Auto-load saved config
SaveManager:LoadAutoloadConfig()
