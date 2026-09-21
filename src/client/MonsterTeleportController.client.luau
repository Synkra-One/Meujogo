--!strict
--[[
	MonsterTeleportController
	Lado do Monstro para o poder de teleporte (par de server/MonsterTeleport).
	Só faz algo quando o Role local é "Monstro".

	  - tecla Q / gamepad ButtonY: mira (centro da tela) e PEDE o teleporte.
	    O servidor valida destino/alcance/cooldown/estado -- o cliente nunca
	    teleporta sozinho.
	  - enquanto TeleportState != Idle: desliga o controle de movimento
	    (jeito oficial, ControlModule -- não briga com o Crouching) e faz uma
	    câmera pesada/cinematográfica só para o Monstro.
	  - toca TeleportChargeSound na ativação.
	  - mostra um aviso curto quando o destino é inválido.

	As fendas em si são apresentadas por client/RiftVFXController para todo
	mundo que estiver perto; aqui é só o input + a câmera/áudio do próprio
	Monstro.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FlashlightRules = require(ReplicatedStorage.Modules.FlashlightRules)
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)
local DiscoveredItemsStore = require(script.Parent.DiscoveredItemsStore)

local LocalPlayer = Players.LocalPlayer
local CFG = GameConfig.Monster.Teleport
local ACTION = "MonsterTeleport"

-- CurrentCamera pode ser recriada (respawn) -- lê fresco sempre.
local function cam(): Camera
	return Workspace.CurrentCamera
end

--------------------------------------------------------------------------------
-- Estado
--------------------------------------------------------------------------------

local isMonster = false
local bound = false
local readyAt = 0
local character: Model? = nil
local stateConn: RBXScriptConnection? = nil

--------------------------------------------------------------------------------
-- Controle de movimento (ControlModule oficial -- igual RoleRevealController)
--------------------------------------------------------------------------------

local controlsDisabled = false
local reenableGuard: thread? = nil

local function getControls()
	local ok, controls = pcall(function()
		local scripts = LocalPlayer:WaitForChild("PlayerScripts", 5)
		local pm = scripts and scripts:WaitForChild("PlayerModule", 5)
		return pm and require(pm :: ModuleScript):GetControls()
	end)
	return ok and controls or nil
end

local function setControls(enabled: boolean)
	if enabled == not controlsDisabled then
		return
	end
	controlsDisabled = not enabled
	local controls = getControls()
	if controls then
		if enabled then
			(controls :: any):Enable()
		else
			(controls :: any):Disable()
		end
	end
	if not enabled then
		if reenableGuard then
			task.cancel(reenableGuard)
		end
		reenableGuard = task.delay(CFG.SafetyTimeout + 4, function()
			setControls(true)
		end)
	elseif reenableGuard then
		task.cancel(reenableGuard)
		reenableGuard = nil
	end
end

--------------------------------------------------------------------------------
-- Câmera cinematográfica (aditiva -- não substitui a câmera do pacote)
--------------------------------------------------------------------------------

local camPitch = 0 -- graus, aplicados por render step
local camFov = 0 -- delta de FieldOfView
local camActive = false
local baseFov = 0 -- FieldOfView de antes do teleporte (o delta é somado A ISTO, não acumulado)
local camRenderName = "MonsterTeleportCam"
local colorFx: ColorCorrectionEffect? = nil
local camTween: Tween? = nil
local pitchValue = Instance.new("NumberValue")
local fovValue = Instance.new("NumberValue")

local function ensureColorFx(): ColorCorrectionEffect
	if colorFx and colorFx.Parent then
		return colorFx
	end
	local fx = Instance.new("ColorCorrectionEffect")
	fx.Name = "MonsterTeleportVoid"
	fx.Enabled = true
	fx.Brightness = 0
	fx.Contrast = 0
	fx.Saturation = 0
	fx.TintColor = Color3.fromRGB(215, 205, 210)
	fx.Parent = Lighting
	colorFx = fx
	return fx
end

local function startCamRender()
	if camActive then
		return
	end
	camActive = true
	local c0 = cam()
	baseFov = (c0 and c0.FieldOfView) or 70
	RunService:BindToRenderStep(camRenderName, Enum.RenderPriority.Camera.Value + 2, function()
		local c = cam()
		if not c then
			return
		end
		camPitch = pitchValue.Value
		camFov = fovValue.Value
		if math.abs(camPitch) > 0.01 then
			c.CFrame = c.CFrame * CFrame.Angles(math.rad(-camPitch), 0, 0)
		end
		-- FOV ABSOLUTO: base + delta. Nada de "c.FieldOfView + camFov" -- o
		-- pacote (Crouching) só escreve FieldOfView na troca de estado, então
		-- somar frame a frame estourava o zoom até o mínimo (1°).
		if math.abs(camFov) > 0.01 then
			c.FieldOfView = baseFov + camFov
		end
	end)
end

local function stopCamRender()
	if not camActive then
		return
	end
	camActive = false
	pcall(function()
		RunService:UnbindFromRenderStep(camRenderName)
	end)
	-- devolve o FieldOfView ao valor de antes do teleporte (o Crouching só o
	-- reescreve na próxima troca de sprint/agachar, então precisa ser explícito)
	local c = cam()
	if c and baseFov > 0 then
		c.FieldOfView = baseFov
	end
end

-- alvo por fase: { pitch, fovDelta, brightness, contrast, saturation }
local CAM_PHASES: { [string]: { number } } = {
	OpeningRift = { 1.5, -2, -0.05, 0.03, -0.1 },
	Entering = { 7, -7, -0.22, 0.09, -0.35 },
	Traveling = { 3, -3, -0.62, 0.12, -0.55 },
	Exiting = { 4, -5, -0.14, 0.06, -0.25 },
	Recovery = { 0, 0, 0, 0, 0 },
}

local function applyCamPhase(state: string?)
	local target = state and CAM_PHASES[state] or { 0, 0, 0, 0, 0 }
	local dur = 0.5
	if state == "Entering" then
		dur = CFG.EnterDuration
	elseif state == "Exiting" then
		dur = CFG.ExitDuration
	elseif state == "OpeningRift" then
		dur = CFG.RiftOpenDuration
	elseif state == "Traveling" then
		dur = CFG.TravelDuration
	end

	if camTween then
		camTween:Cancel()
	end
	local info = TweenInfo.new(math.max(dur, 0.2), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(pitchValue, info, { Value = target[1] }):Play()
	TweenService:Create(fovValue, info, { Value = target[2] }):Play()
	local fx = ensureColorFx()
	camTween = TweenService:Create(fx, info, {
		Brightness = target[3],
		Contrast = target[4],
		Saturation = target[5],
	})
	camTween:Play()
end

local function clearCam()
	applyCamPhase(nil)
	task.delay(0.7, function()
		if not camActive or math.abs(pitchValue.Value) < 0.05 then
			stopCamRender()
			-- FOV: o pacote (Crouching) reescreve todo frame, então basta parar
			-- de somar o delta; não precisa forçar valor nenhum.
			if colorFx then
				colorFx:Destroy()
				colorFx = nil
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Aviso curto (destino inválido)
--------------------------------------------------------------------------------

local warnGui: ScreenGui? = nil

local function showWarn(text: string)
	if not warnGui then
		local gui = Instance.new("ScreenGui")
		gui.Name = "TeleportWarn"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(0, 460, 0, 40)
		label.Position = UDim2.new(0.5, 0, 0.62, 0)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.BackgroundColor3 = Color3.new(0, 0, 0)
		label.BackgroundTransparency = 0.35
		label.TextColor3 = Color3.fromRGB(220, 180, 180)
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 18
		label.Text = ""
		label.Visible = false
		label.Parent = gui
		warnGui = gui
	end
	local label = (warnGui :: ScreenGui):FindFirstChild("Label") :: TextLabel
	label.Text = "Teleporte: " .. text
	label.Visible = true
	label.TextTransparency = 0
	label.BackgroundTransparency = 0.35
	TweenService:Create(label, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.6), {
		TextTransparency = 1,
		BackgroundTransparency = 1,
	}):Play()
	task.delay(2.2, function()
		if label.TextTransparency >= 1 then
			label.Visible = false
		end
	end)
end

--------------------------------------------------------------------------------
-- Ativação
--------------------------------------------------------------------------------

local function chargeSound()
	local id = AssetRegistry.RiftTeleport.Sounds.TeleportCharge
	if type(id) ~= "string" or id == "" or id == "rbxassetid://0" then
		return
	end
	local char = character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 70
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, 8)
end

local function aimPoint(): Vector3?
	local char = character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local c = cam()
	if not c then
		return nil
	end
	local vp = c.ViewportSize
	local ray = c:ViewportPointToRay(vp.X / 2, vp.Y / 2)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { char }
	local elim = Workspace:FindFirstChild("Eliminados")
	if elim then
		table.insert(ignore, elim)
	end
	local rifts = Workspace:FindFirstChild("RiftVFX")
	if rifts then
		table.insert(ignore, rifts)
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true

	local hit = Workspace:Raycast(ray.Origin, ray.Direction.Unit * (CFG.MaxRange + 60), params)
	if hit then
		return hit.Position
	end
	-- sem acerto: um ponto longe na direção da mira, na altura do monstro
	-- (o servidor faz o raycast pro chão a partir daí)
	local far = ray.Origin + ray.Direction.Unit * CFG.MaxRange
	return Vector3.new(far.X, root.Position.Y, far.Z)
end

--------------------------------------------------------------------------------
-- MAPA: Q abre o mapa da ilha; clicar nele escolhe o destino
--------------------------------------------------------------------------------
-- O mapa (Modules/IslandMapUI, modo "teleport") é desenhado a partir da grade que
-- server/IslandMap amostrou de IslandLayout -- proporção 1:1 com o mundo.
-- O clique vira um (x, z) REAL, o servidor valida e teleporta pra lá.

local mapUI: any = nil
local mouseForceConn: RBXScriptConnection? = nil

local function formatCooldown(): string
	local remaining = readyAt - os.time()
	if remaining <= 0 then
		return "pronto"
	end
	return string.format("%ds", math.ceil(remaining))
end

-- Enquanto o mapa está aberto o mouse precisa sair do centro. O CustomShiftLock
-- reprende a mira no centro TODO FRAME e gira o personagem pela câmera -- mas ele
-- respeita o atributo "CursorLivre" no LocalPlayer (é o mesmo gancho que a tela
-- de escolha de personagem usa). Setando o atributo, o próprio shift-lock solta
-- o cursor e para de brigar; o render step abaixo é só uma rede de segurança
-- contra re-locks do PlayerModule.
local function setMouseFree(free: boolean)
	if free then
		LocalPlayer:SetAttribute("CursorLivre", true)
		if mouseForceConn then
			return
		end
		mouseForceConn = RunService.RenderStepped:Connect(function()
			if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			UserInputService.MouseIconEnabled = true
		end)
	else
		LocalPlayer:SetAttribute("CursorLivre", nil)
		if mouseForceConn then
			mouseForceConn:Disconnect()
			mouseForceConn = nil
		end
	end
end

local function closeMap()
	if mapUI and mapUI:IsOpen() then
		mapUI:Hide()
	end
	setMouseFree(false)
	LocalPlayer:SetAttribute("MapaAberto", nil)
	-- Só devolve o controle se não estivermos no meio do teleporte.
	local char = character
	if not (char and char:GetAttribute("TeleportBusy") == true) then
		setControls(true)
	end
end

local function onMapPick(point: Vector3)
	local char = character
	if not char or FlashlightRules.PowerBlocked(char) or char:GetAttribute("TeleportBusy") == true or char:GetAttribute("ShadowRushBusy") == true
		or char:GetAttribute("GrabLocked") == true then
		closeMap()
		return
	end
	if os.time() < readyAt then
		return -- ainda em cooldown; o mapa fica aberto
	end
	closeMap()
	Remotes.MonsterTeleport:FireServer(point)
end

local function ensureMapUI()
	if mapUI then
		return
	end
	local IslandMapUI = require(ReplicatedStorage.Modules.IslandMapUI)
	mapUI = IslandMapUI.new(LocalPlayer:WaitForChild("PlayerGui"), { mode = "teleport", onPick = onMapPick })
	task.spawn(function()
		mapUI:Prepare() -- monta em background pra Q abrir instantâneo
	end)
end

-- Item novo descoberto (server/ItemDiscovery.lua) enquanto o mapa já existe:
-- entra direto, mesmo com o mapa fechado no momento (fica pronto pra próxima
-- vez que abrir).
DiscoveredItemsStore.Changed:Connect(function(entry)
	if mapUI then
		mapUI:AddDiscoveredItem(entry :: any)
	end
end)

-- Reserva: se o mapa não puder ser montado (dados não chegaram), volta pro
-- teleporte mirando com a câmera, pra a habilidade nunca ficar inutilizável.
local function aimPointFallback(): Vector3?
	local char = character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local c = cam()
	if not c then
		return nil
	end
	local vp = c.ViewportSize
	local ray = c:ViewportPointToRay(vp.X / 2, vp.Y / 2)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { char }
	for _, name in { "Eliminados", "RiftVFX" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true

	local hit = Workspace:Raycast(ray.Origin, ray.Direction.Unit * (CFG.MaxRange + 60), params)
	if hit then
		return hit.Position
	end
	local far = ray.Origin + ray.Direction.Unit * CFG.MaxRange
	return Vector3.new(far.X, root.Position.Y, far.Z)
end

local function toggleMap()
	if not isMonster then
		return
	end
	local char = character
	if not char or FlashlightRules.PowerBlocked(char) or char:GetAttribute("TeleportBusy") == true or char:GetAttribute("ShadowRushBusy") == true
		or char:GetAttribute("GrabLocked") == true then
		return
	end

	if mapUI and mapUI:IsOpen() then
		closeMap()
		return
	end

	ensureMapUI()
	local root = char:FindFirstChild("HumanoidRootPart")
	local pos = (root and root:IsA("BasePart")) and root.Position or nil
	local status = if os.time() < readyAt
		then "recarregando: " .. formatCooldown()
		else "pronto"

	if mapUI:Show(pos, status) then
		mapUI:SetDiscoveredItems(DiscoveredItemsStore.GetAll())
		setControls(false) -- não anda enquanto escolhe
		setMouseFree(true)
		LocalPlayer:SetAttribute("MapaAberto", true) -- MonsterController não ataca
		-- mantém o marcador e o cooldown vivos enquanto o mapa está aberto
		task.spawn(function()
			while mapUI and mapUI:IsOpen() do
				local c = character
				local r = c and c:FindFirstChild("HumanoidRootPart")
				mapUI:UpdateMonster((r and r:IsA("BasePart")) and r.Position or nil)
				mapUI:SetStatus(if os.time() < readyAt then "recarregando: " .. formatCooldown() else "pronto")
				task.wait(0.25)
			end
		end)
	else
		-- sem dados do mapa: teleporte mirando com a câmera
		showWarn("mapa indisponível — mirando com a câmera")
		if os.time() >= readyAt then
			local point = aimPointFallback()
			if point then
				Remotes.MonsterTeleport:FireServer(point)
			end
		end
	end
end

local function onAction(_name: string, inputState: Enum.UserInputState, input: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		-- botão direito só fecha (fora do mapa ele é a mira da arma/câmera)
		if mapUI and mapUI:IsOpen() then
			closeMap()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end
	toggleMap()
	return Enum.ContextActionResult.Sink
end

local function setBound(shouldBind: boolean)
	if shouldBind == bound then
		return
	end
	bound = shouldBind
	if shouldBind then
		ContextActionService:BindActionAtPriority(
			ACTION,
			onAction,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.Q,
			Enum.KeyCode.ButtonY,
			Enum.UserInputType.MouseButton2
		)
	else
		ContextActionService:UnbindAction(ACTION)
		closeMap()
	end
end

--------------------------------------------------------------------------------
-- Reação ao servidor
--------------------------------------------------------------------------------

Remotes.MonsterTeleport.OnClientEvent:Connect(function(kind: string, value: any)
	if kind == "cooldown" then
		readyAt = tonumber(value) or 0
	elseif kind == "cancel" then
		showWarn(tostring(value or "destino inválido"))
	end
end)

--------------------------------------------------------------------------------
-- Estado do teleporte -> controle + câmera
--------------------------------------------------------------------------------

local function onStateChanged()
	local char = character
	local state = char and char:GetAttribute("TeleportState")
	if type(state) == "string" then
		closeMap() -- a habilidade começou: o mapa sai da frente
		setControls(false)
		startCamRender()
		applyCamPhase(state)
		if state == "OpeningRift" then
			chargeSound()
		end
	else
		setControls(true)
		clearCam()
	end
end

local function bindCharacter(char: Model)
	character = char
	if stateConn then
		stateConn:Disconnect()
	end
	stateConn = char:GetAttributeChangedSignal("TeleportState"):Connect(onStateChanged)
	-- estado pode já existir (respawn no meio -- raríssimo, mas cobre)
	onStateChanged()
end

local function refreshRole()
	isMonster = LocalPlayer:GetAttribute("Role") == GameConfig.Roles.Monster
	setBound(isMonster)
	if isMonster then
		ensureMapUI() -- monta o mapa em background: Q abre na hora
	else
		closeMap()
		setControls(true)
		clearCam()
	end
end

LocalPlayer:GetAttributeChangedSignal("Role"):Connect(refreshRole)
LocalPlayer.CharacterAdded:Connect(function(char)
	-- character novo: garante que nada ficou preso do teleporte anterior
	closeMap()
	setControls(true)
	stopCamRender()
	pitchValue.Value = 0
	fovValue.Value = 0
	if colorFx then
		colorFx:Destroy()
		colorFx = nil
	end
	bindCharacter(char)
	refreshRole()
end)

if LocalPlayer.Character then
	bindCharacter(LocalPlayer.Character)
end
refreshRole()
