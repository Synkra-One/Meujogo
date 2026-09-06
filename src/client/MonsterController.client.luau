--!strict
--[[
	MonsterController
	Lado cliente do combate do Monstro (par de server/MonsterCombat.lua).
	Só faz ALGUMA coisa quando o Attribute "Role" do jogador local é "Monstro"
	-- pra todo mundo mais este script fica dormindo.

	GOLPE (botão esquerdo / R2 no controle):
	  - toca a animação de golpe na hora (responsividade -- é só visual)
	  - respeita um cooldown local (GameConfig.Monster.Attack.Cooldown); o
	    servidor tem o dele, este só evita floodar o remote
	  - dispara Remotes.MonsterAttack:FireServer()
	  - no "confirm" do servidor: aplica o lunge (dash pra frente) e, se
	    conectou em alguém, dá um kick de câmera + som de impacto

	KNOCKBACK: quando o Monstro te acerta, o servidor manda "knockback" com a
	posição dele -- aqui a gente aplica o empurrão no PRÓPRIO character (a
	física do teu boneco é tua, velocity setada pelo servidor não gruda).

	Não mexe em câmera/WalkSpeed de forma persistente -- o lunge é um impulso
	único, o kick de câmera é um efeito curto que se desfaz sozinho.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local LocalPlayer = Players.LocalPlayer
local CFG = GameConfig.Monster
local ATK = CFG.Attack

local ATTACK_ACTION = "MonsterAttack"

--------------------------------------------------------------------------------
-- Estado
--------------------------------------------------------------------------------

local isMonster = false
local bound = false
local lastSwing = 0

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local swingTrack: AnimationTrack? = nil

--------------------------------------------------------------------------------
-- Personagem
--------------------------------------------------------------------------------

local function loadSwingTrack()
	swingTrack = nil
	local hum = humanoid
	if not hum then
		return
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = CFG.SwingAnimationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		swingTrack = track
	end
end

local function bindCharacter(char: Model)
	character = char

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		local waited = char:WaitForChild("Humanoid", 10)
		hum = if waited and waited:IsA("Humanoid") then waited else nil
	end
	humanoid = hum

	local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 10)
	rootPart = if hrp and hrp:IsA("BasePart") then hrp else nil

	if isMonster then
		loadSwingTrack()
	end
end

--------------------------------------------------------------------------------
-- Efeitos locais
--------------------------------------------------------------------------------

local function cameraKick(strength: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local start = os.clock()
	local seed = math.random(0, 999)
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t >= 0.22 then
			conn:Disconnect()
			return
		end
		local env = (1 - t / 0.22) ^ 2 * strength
		local x = math.noise(t * 40, seed) * env
		local y = math.noise(t * 40, seed + 30) * env
		camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(y), math.rad(x), 0)
	end)
end

local hitSound = Instance.new("Sound")
hitSound.Name = "MonsterHit"
hitSound.SoundId = "rbxasset://sounds/impact_water.mp3" -- built-in; troque à vontade
hitSound.Volume = 0.6
hitSound.RollOffMaxDistance = 60
hitSound.Parent = game:GetService("SoundService")

local function playHitSound()
	pcall(function()
		local s = hitSound:Clone()
		s.Parent = rootPart or workspace
		s.PlaybackSpeed = 0.9 + math.random() * 0.2
		s:Play()
		game:GetService("Debris"):AddItem(s, 2)
	end)
end

local function applyLunge()
	local hrp = rootPart
	local hum = humanoid
	if not hrp or not hum or hum.Health <= 0 or ATK.LungeForce <= 0 then
		return
	end
	-- Dash na direção que o Monstro OLHA (MoveDirection cai fora se estiver
	-- parado; LookVector do HRP com shift lock segue a câmera).
	local dir = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
	if dir.Magnitude < 0.05 then
		return
	end
	local v = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, v.Z) + dir.Unit * ATK.LungeForce
end

local function applyKnockback(fromPosition: Vector3)
	local hrp = rootPart
	local hum = humanoid
	if not hrp or not hum or hum.Health <= 0 then
		return
	end
	local away = (hrp.Position - fromPosition) * Vector3.new(1, 0, 1)
	local dir = away.Magnitude > 0.05 and away.Unit or hrp.CFrame.LookVector * -1
	local v = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z) + dir * ATK.Knockback + Vector3.new(0, ATK.KnockbackUp, 0)
end

--------------------------------------------------------------------------------
-- Golpe (input local -> remote)
--------------------------------------------------------------------------------

local function tryAttack()
	if not isMonster then
		return
	end
	local hum = humanoid
	if not hum or hum.Health <= 0 then
		return
	end
	local now = os.clock()
	if (now - lastSwing) < ATK.Cooldown then
		return
	end
	lastSwing = now

	local track = swingTrack
	if track then
		track:Stop(0)
		track:Play(0.05)
	end

	Remotes.MonsterAttack:FireServer()
end

local function onAction(_actionName: string, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		tryAttack()
	end
	return Enum.ContextActionResult.Sink
end

local function setBound(shouldBind: boolean)
	if shouldBind == bound then
		return
	end
	bound = shouldBind
	if shouldBind then
		ContextActionService:BindActionAtPriority(
			ATTACK_ACTION,
			onAction,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.UserInputType.MouseButton1,
			Enum.KeyCode.ButtonR2
		)
	else
		ContextActionService:UnbindAction(ATTACK_ACTION)
	end
end

--------------------------------------------------------------------------------
-- Reação ao servidor
--------------------------------------------------------------------------------

Remotes.MonsterAttack.OnClientEvent:Connect(function(kind: string, a: any)
	if kind == "confirm" then
		applyLunge()
		local hitCount = tonumber(a) or 0
		if hitCount > 0 then
			cameraKick(2.5 + math.min(hitCount, 3))
			playHitSound()
		end
	elseif kind == "knockback" and typeof(a) == "Vector3" then
		applyKnockback(a)
	end
end)

--------------------------------------------------------------------------------
-- Ciclo de vida do papel
--------------------------------------------------------------------------------

local function refreshRole()
	isMonster = LocalPlayer:GetAttribute("Role") == GameConfig.Roles.Monster
	setBound(isMonster)
	if isMonster and character and not swingTrack then
		loadSwingTrack()
	end
end

LocalPlayer:GetAttributeChangedSignal("Role"):Connect(refreshRole)
LocalPlayer.CharacterAdded:Connect(function(char)
	bindCharacter(char)
	refreshRole()
end)
if LocalPlayer.Character then
	bindCharacter(LocalPlayer.Character)
end
refreshRole()
