--!strict
--[[
	FlyTest
	Modo "voar" só pra TESTE (GameConfig.Testing.Voar): atravessar a ilha
	correndo a cada teste é lento. Estilo Minecraft criativo:

	  Espaço 2x rápido   liga / desliga o voo
	  W A S D            voa pra onde a câmera olha
	  Espaço (segurado)  sobe            X (segurado)  desce
	  Shift (segurado)   turbo (VelocidadeVooRapido)

	Só existe dentro do Studio (RunService:IsStudio()): mesmo esquecido ligado
	na config, o jogo publicado não voa.

	COMO NÃO QUEBRA O RESTO
	  - PlatformStand + LinearVelocity, sem mexer no WalkSpeed: o Humanoid não
	    entra em Freefall, então o dano de queda (DamageSystem.monitorFall) e o
	    FallEffects não acumulam altura enquanto voa.
	  - Ao desligar, o boneco DESCE controlado até o chão antes de soltar o
	    PlatformStand -- soltar no ar seria uma queda de centenas de studs com
	    dano de queda.
	  - Atributo "Voando" no personagem: o MovementWatchdog não "destrava" o
	    PlatformStand de propósito.
	  - Servidor (server/FlyTest.lua) deixa o personagem Invulneravel enquanto
	    voa e 4s depois do pouso.
	  - Desliga sozinho ao morrer, sentar (barco) ou trocar de personagem.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local CFG = GameConfig.Testing
if CFG.Voar ~= true or not RunService:IsStudio() then
	return
end

local DOUBLE_TAP_WINDOW = 0.3
local LANDING_SPEED = 70 -- studs/s no máximo, na descida controlada
local LANDING_DISTANCE = 3.6 -- distância HRP -> chão em que solta (R6 em pé ~3)
local LANDING_TIMEOUT = 8 -- sem chão embaixo (vazio): solta assim mesmo
local SMOOTHING = 9

local player = Players.LocalPlayer

type Rig = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	attachment: Attachment,
	linear: LinearVelocity,
	align: AlignOrientation,
}

local rig: Rig? = nil
local landingSince: number? = nil
local velocity = Vector3.zero
local lastSpaceTap = 0

--------------------------------------------------------------------------------
-- Aviso na tela (só enquanto voa)
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "VoarTeste"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(1, 1)
label.Position = UDim2.new(1, -14, 1, -14)
label.Size = UDim2.fromOffset(330, 24)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 14
label.TextXAlignment = Enum.TextXAlignment.Right
label.TextColor3 = Color3.fromRGB(150, 210, 255)
label.TextStrokeTransparency = 0.5
label.Text = "VOANDO (teste) · Shift turbo · Espaço sobe · X desce · 2x Espaço sai"
label.Parent = gui

--------------------------------------------------------------------------------
-- Ligar / desligar
--------------------------------------------------------------------------------

local function release()
	local current = rig
	rig = nil
	landingSince = nil
	velocity = Vector3.zero
	gui.Enabled = false
	if not current then
		return
	end
	Remotes.FlyTest:FireServer(false) -- servidor tira a invulnerabilidade após a folga
	current.linear:Destroy()
	current.align:Destroy()
	current.attachment:Destroy()
	if current.character.Parent then
		current.character:SetAttribute("Voando", nil)
		if current.humanoid.Parent then
			current.humanoid.PlatformStand = false
		end
	end
end

local function canStart(character: Model, humanoid: Humanoid): boolean
	return humanoid.Health > 0
		and not humanoid.Sit
		and player:GetAttribute("IntroMenuOpen") ~= true
		and player:GetAttribute("MovementLocked") ~= true
		and character:GetAttribute("TeleportBusy") ~= true
		and character:GetAttribute("GrabLocked") ~= true
end

local function start()
	if rig then
		landingSince = nil -- estava descendo pra pousar: volta a voar
		gui.Enabled = true
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") or not canStart(character, humanoid) then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "VooAnexo"
	attachment.Parent = root

	local linear = Instance.new("LinearVelocity")
	linear.Name = "VooVelocidade"
	linear.Attachment0 = attachment
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linear.MaxForce = math.huge
	linear.VectorVelocity = Vector3.zero
	linear.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "VooOrientacao"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = false
	align.MaxTorque = math.huge
	align.Responsiveness = 25
	align.CFrame = root.CFrame.Rotation
	align.Parent = root

	humanoid.PlatformStand = true
	character:SetAttribute("Voando", true)
	rig = {
		character = character,
		humanoid = humanoid,
		root = root,
		attachment = attachment,
		linear = linear,
		align = align,
	}
	landingSince = nil
	velocity = Vector3.zero
	gui.Enabled = true
	Remotes.FlyTest:FireServer(true) -- invulnerável enquanto voa
end

local function beginLanding()
	if rig and not landingSince then
		landingSince = os.clock()
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or input.KeyCode ~= Enum.KeyCode.Space then
		return
	end
	local now = os.clock()
	if now - lastSpaceTap <= DOUBLE_TAP_WINDOW then
		lastSpaceTap = 0
		if rig and not landingSince then
			beginLanding()
		else
			start()
		end
	else
		lastSpaceTap = now
	end
end)

--------------------------------------------------------------------------------
-- Voo
--------------------------------------------------------------------------------

local function keyAxis(positive: Enum.KeyCode, negative: Enum.KeyCode): number
	local value = 0
	if UserInputService:IsKeyDown(positive) then
		value += 1
	end
	if UserInputService:IsKeyDown(negative) then
		value -= 1
	end
	return value
end

local function groundDistance(current: Rig): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { current.character }
	local hit = Workspace:Raycast(current.root.Position, Vector3.new(0, -2000, 0), params)
	return hit and (current.root.Position.Y - hit.Position.Y) or nil
end

RunService.PreSimulation:Connect(function(dt: number)
	local current = rig
	if not current then
		return
	end
	-- Personagem morreu / foi trocado / sentou (barco): larga na hora.
	if
		current.character ~= player.Character
		or not current.character.Parent
		or current.humanoid.Health <= 0
		or current.humanoid.Sit
		or not current.root.Parent
	then
		release()
		return
	end

	local target = Vector3.zero
	local facing: Vector3? = nil

	if landingSince then
		local distance = groundDistance(current)
		local timedOut = os.clock() - landingSince > LANDING_TIMEOUT
		if timedOut or (distance ~= nil and distance <= LANDING_DISTANCE) then
			release()
			return
		end
		local drop = if distance then math.min(LANDING_SPEED, 6 + distance * 2.5) else LANDING_SPEED
		target = Vector3.new(0, -drop, 0)
	else
		local camera = Workspace.CurrentCamera
		if camera then
			local look = camera.CFrame.LookVector
			local right = camera.CFrame.RightVector
			local forward = keyAxis(Enum.KeyCode.W, Enum.KeyCode.S)
			local side = keyAxis(Enum.KeyCode.D, Enum.KeyCode.A)
			local vertical = keyAxis(Enum.KeyCode.Space, Enum.KeyCode.X)
			local wish = look * forward + Vector3.new(right.X, 0, right.Z) * side + Vector3.new(0, vertical, 0)
			if wish.Magnitude > 0.01 then
				local fast = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				target = wish.Unit * (if fast then CFG.VelocidadeVooRapido else CFG.VelocidadeVoo)
				local flat = Vector3.new(wish.X, 0, wish.Z)
				if flat.Magnitude > 0.01 then
					facing = flat.Unit
				end
			end
		end
	end

	velocity = velocity:Lerp(target, 1 - math.exp(-SMOOTHING * dt))
	current.linear.VectorVelocity = velocity
	if facing then
		current.align.CFrame = CFrame.lookAt(Vector3.zero, facing)
	end
end)

player.CharacterRemoving:Connect(release)
