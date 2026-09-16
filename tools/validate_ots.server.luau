local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

local function compile(container: Instance)
	assert(container:IsA("LuaSourceContainer"), container:GetFullName() .. " não é script")
	local chunk, syntaxError = loadstring(container.Source, "=" .. container:GetFullName())
	assert(chunk, syntaxError)
	print("[ValidateOTS] compilado: " .. container:GetFullName())
end

local modules = ReplicatedStorage:WaitForChild("Modules")
local server = ServerScriptService:WaitForChild("Server")
local client = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Client")
for _, container in {
	modules:WaitForChild("OTSAmmo"),
	modules:WaitForChild("OTSEffects"),
	modules:WaitForChild("OTSRules"),
	server:WaitForChild("OTSFirearmService"),
	client:WaitForChild("OTSHUD"),
	client:WaitForChild("OTSController"),
} do
	compile(container)
end

for _, obsolete in { "Ammo", "FirearmRules", "WeaponEffects", "PistolGrip" } do
	assert(not modules:FindFirstChild(obsolete), "módulo legado ainda existe: " .. obsolete)
end
for _, obsolete in { "FirearmServer", "PistolGripCalibration" } do
	assert(not server:FindFirstChild(obsolete), "serviço legado ainda existe: " .. obsolete)
end
for _, obsolete in { "PistolController", "PistolHUD", "PistolPose", "PistolGripTest" } do
	assert(not client:FindFirstChild(obsolete), "cliente legado ainda existe: " .. obsolete)
end

local assets = ReplicatedStorage:WaitForChild("WeaponAssets")
local tools = assets:WaitForChild("Tools"):GetChildren()
assert(#tools == 1 and tools[1]:IsA("Tool") and tools[1].Name == "Glock17", "somente Glock17 deve estar ativa")
local pistolAnimations = assets:WaitForChild("Animations"):WaitForChild("PistolAnimations")
for _, name in { "Holster", "Aim", "Fire", "Reload" } do
	assert(pistolAnimations:FindFirstChild(name) and pistolAnimations[name]:IsA("Animation"), "animação OTS ausente: " .. name)
end
assert(#pistolAnimations:GetChildren() == 4, "há animações de arma extras na pasta ativa")
assert(StarterGui:FindFirstChild("Weapon") and StarterGui.Weapon:IsA("ScreenGui"), "HUD original do OTS ausente")
assert(not ReplicatedStorage.Remotes:FindFirstChild("FirearmHit"), "remote legado FirearmHit ainda existe")
assert(not ReplicatedStorage.Remotes:FindFirstChild("PistolGripTest"), "remote de calibração ainda existe")

print("[ValidateOTS] estrutura consolidada: uma Glock, um HUD e um controlador")
return true
