--!strict
-- Bancada de teste temporária; uma única Tool, sem duplicar a cada pickup.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local AmmoSystem = require(script.Parent.AmmoSystem)
local DropItemSystem = require(script.Parent.DropItemSystem)
local LobbyFiringRange = {}
local initialized = false

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame = name, size, cf
	p.Anchored, p.Material, p.Color = true, Enum.Material.Metal, color
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sign(parent: BasePart, text: string, face: Enum.NormalId): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face = "Placa", face
	gui.SizingMode, gui.PixelsPerStud = Enum.SurfaceGuiSizingMode.PixelsPerStud, 65
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency, label.Size = 1, UDim2.fromScale(1, 1)
	label.Font, label.TextScaled, label.TextWrapped = Enum.Font.GothamBold, true, true
	label.TextColor3, label.Text = Color3.fromRGB(241, 221, 174), text
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0.1, 0), UDim.new(0.1, 0)
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0.05, 0), UDim.new(0.05, 0)
	padding.Parent = label
	return label
end

function LobbyFiringRange.Init()
	if initialized or not GameConfig.Testing.LobbyPistol then return end
	initialized = true

	local oldFolder = Workspace:FindFirstChild("TestePistolaLobby")
	if oldFolder then
		oldFolder:Destroy()
	end

	local spawn = Workspace:WaitForChild("LobbySpawn", 10)
	local assets = ReplicatedStorage:WaitForChild("WeaponAssets", 10)
	local templates = assets and assets:WaitForChild("Tools", 10)
	local template = templates and templates:WaitForChild("Glock17", 10)
	if not spawn or not spawn:IsA("BasePart") or not template or not template:IsA("Tool") then
		warn("[LobbyFiringRange] LobbySpawn ou WeaponAssets/Tools/Glock17 ausente.")
		return
	end
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "TestePistolaLobby", Workspace
	-- Origem no topo do piso, relativa ao lobby existente.
	local origin = CFrame.new(spawn.Position.X, spawn.Position.Y - spawn.Size.Y / 2, spawn.Position.Z)
	local dark, accent = Color3.fromRGB(36, 43, 49), Color3.fromRGB(209, 159, 68)
	local bench = origin * CFrame.new(9, 0, -5)
	part(folder, "Bancada", Vector3.new(7, 0.4, 3), bench * CFrame.new(0, 2.6, 0), dark)
	for _, x in { -2.8, 2.8 } do
		part(folder, "Suporte", Vector3.new(0.35, 2.4, 2.4), bench * CFrame.new(x, 1.2, 0), dark)
	end
	local plaque = part(folder, "Instrucoes", Vector3.new(7, 1.6, 0.2), bench * CFrame.new(0, 6.4, -1.2), dark)
	part(folder, "SuportePlaca", Vector3.new(0.15, 5.6, 0.15), bench * CFrame.new(-3.5, 2.8, -1.2), dark)
	sign(plaque, "TESTE DE PISTOLA\nE PEGAR  •  1 EQUIPAR\nBOTÃO DIREITO MIRAR  •  R RECARREGAR", Enum.NormalId.Back)
	local pad = part(folder, "BasePistola", Vector3.new(3, 0.08, 2.4), bench * CFrame.new(-1.65, 2.85, 0), Color3.fromRGB(18, 23, 27))
	local status = sign(pad, "GLOCK 17\n17 CARTUCHOS", Enum.NormalId.Top)
	part(folder, "FaixaDeTiro", Vector3.new(6, 0.03, 0.3), origin * CFrame.new(9, 0.02, -10), accent).CanCollide = false
	part(folder, "Anteparo", Vector3.new(9, 8, 0.7), origin * CFrame.new(9, 4, -27), dark)
	for _, x in { 4.5, 13.5 } do
		part(folder, "ProtecaoLateral", Vector3.new(0.3, 6, 12), origin * CFrame.new(x, 3, -21), dark)
	end

	local function createTarget()
		if not folder.Parent then return end
		local model = Instance.new("Model")
		model.Name = "Alvo de treino"
		model:SetAttribute("FirearmTestTarget", true)
		local target = origin * CFrame.new(9, 0, -23)
		local root = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), target * CFrame.new(0, 3, 0), dark)
		root.Transparency, root.CanCollide, root.CanQuery = 1, false, false
		local torso = part(model, "Torso", Vector3.new(2.6, 2.8, 0.7), target * CFrame.new(0, 3.2, 0), Color3.fromRGB(166, 171, 167))
		sign(torso, "◎", Enum.NormalId.Back)
		local head = part(model, "Head", Vector3.new(1.3, 1.3, 0.7), target * CFrame.new(0, 5.3, 0), accent)
		sign(head, "+", Enum.NormalId.Back)
		part(model, "Left Leg", Vector3.new(0.9, 1.8, 0.7), target * CFrame.new(-0.65, 0.9, 0), dark)
		part(model, "Right Leg", Vector3.new(0.9, 1.8, 0.7), target * CFrame.new(0.65, 0.9, 0), dark)
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck, humanoid.BreakJointsOnDeath = false, false
		humanoid.MaxHealth, humanoid.Health = 100, 100
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.Parent = model
		model.PrimaryPart, model.Parent = root, folder
		local healthGui = Instance.new("BillboardGui")
		healthGui.Size, healthGui.StudsOffset = UDim2.fromOffset(190, 36), Vector3.new(0, 1.4, 0)
		healthGui.MaxDistance, healthGui.Parent = 70, head
		local health = Instance.new("TextLabel")
		health.Size, health.BackgroundTransparency = UDim2.fromScale(1, 1), 1
		health.Font, health.TextSize, health.TextColor3 = Enum.Font.GothamBold, 16, Color3.new(1, 1, 1)
		health.TextStrokeTransparency, health.Text = 0.3, "ALVO • 100 / 100"
		health.Parent = healthGui
		humanoid.HealthChanged:Connect(function(value)
			health.Text = if value > 0 then string.format("ALVO • %d / 100", math.ceil(value)) else "REINICIANDO..."
		end)
		humanoid.Died:Once(function()
			task.delay(3, function()
				model:Destroy()
				createTarget()
			end)
		end)
	end
	createTarget()

	local function createPistol()
		if not folder.Parent then return end
		local pistol = template:Clone()
		pistol:SetAttribute("LobbyTestWeapon", true)
		pistol.ToolTip = "Pistola de teste • dano somente no alvo do lobby"
		DropItemSystem.PlaceInWorld(pistol, bench * CFrame.new(-1.65, 3.2, 0) * CFrame.Angles(0, 0, math.rad(90)), folder)
		local handle = pistol:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			-- DropItemSystem guardou Anchored=false e restaura ao pegar.
			handle.Anchored, handle.CanCollide = true, false
		end
		status.Text = "GLOCK 17\n17 CARTUCHOS"
		pistol.AncestryChanged:Connect(function()
			if pistol.Parent then status.Text = if pistol.Parent == folder then "GLOCK 17\n17 CARTUCHOS" else "PISTOLA EM USO" end
		end)
		-- Só repõe ao destruir (morte/respawn); pegar não cria pistolas extras.
		pistol.Destroying:Once(function() task.delay(3, createPistol) end)
	end
	createPistol()
	local function createAmmo()
		if not folder.Parent then return end
		local box = AmmoSystem.CreatePickup((bench * CFrame.new(1.8, 3.25, 0)).Position, "Pistola", 34, folder)
		box:SetAttribute("LobbyTestPickup", true)
		box.Size, box.Color = Vector3.new(2.1, 0.8, 1.3), Color3.fromRGB(116, 113, 70)
		local text = sign(box, "9 mm\n34 CARTUCHOS", Enum.NormalId.Top)
		box:GetAttributeChangedSignal("Quantidade"):Connect(function()
			text.Text = string.format("9 mm\n%d CARTUCHOS", box:GetAttribute("Quantidade") or 0)
		end)
		box.Destroying:Once(function() task.delay(5, createAmmo) end)
	end
	createAmmo()
	print("[LobbyFiringRange] Bancada de teste criada no lobby com Glock17 e munição.")
end

return LobbyFiringRange
