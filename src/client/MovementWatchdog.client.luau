--!strict
--[[
	MovementWatchdog
	Rede de segurança contra o boneco "andando parado" -- animação de andar
	tocando, corpo inclinando, mas sem sair do lugar. O "Ultimate R6 Movement
	System" tem vários jeitos de causar isso: WalkSpeed preso em 0 (FallSystem/
	Crouching erram no meio de uma sequência), o personagem ancorado ou
	grudado num Weld pra parte ancorada (IK / ragdoll / import manual em
	dobro), ou PlatformStand ligado e não desligado.

	Este script observa o jogador local. Se ele estiver TENTANDO andar
	(Humanoid.MoveDirection != 0) mas a velocidade real for ~0 por mais de
	STUCK_SECONDS, e não for uma parada proposital do jogo, ele:
	  1. loga no Output EXATAMENTE o que estava travando (pra achar a causa)
	  2. desfaz: desancora a HRP, desliga PlatformStand, quebra Welds da HRP
	     pra partes ancoradas, e devolve WalkSpeed.

	Paradas propositais que ele respeita (não age):
	  - Attribute "Amarrado" / "Eliminado" no Player ou character
	  - Humanoid morto, Seated, PlatformStand vindo de assento de verdade,
	    ou state Physics (ragdoll ativo de propósito)
	  - "CrawlLock" na HRP (transição de rastejar) -- tolerância maior
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local LocalPlayer = Players.LocalPlayer

local STUCK_SECONDS = 1.5
local CRAWL_STUCK_SECONDS = 5
local WANT_MOVE = 0.1 -- MoveDirection acima disso = jogador quer andar
local REAL_MOVE = 1.5 -- velocidade horizontal abaixo disso = "não está andando"
local RESTORE_SPEED = GameConfig.Movement.WalkSpeed

local stuckSince: number? = nil
local lastReport = 0

local function horizSpeed(hrp: BasePart): number
	local v = hrp.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- nil = ficar parado aqui é proposital. número = segundos de tolerância.
local function graceFor(character: Model, humanoid: Humanoid, hrp: BasePart): number?
	if character:GetAttribute("PowerStunned") == true or character:GetAttribute("PowerMoving") == true then return nil end
	if LocalPlayer:GetAttribute("Amarrado") == true or character:GetAttribute("Amarrado") == true then
		return nil
	end
	if LocalPlayer:GetAttribute("Eliminado") == true or character:GetAttribute("Eliminado") == true then
		return nil
	end
	-- Teleporte do Monstro: o HRP fica ancorado e é movido por TweenService de
	-- propósito (server/MonsterTeleport). Não "destravar".
	if character:GetAttribute("TeleportBusy") == true or character:GetAttribute("ShadowRushBusy") == true then
		return nil
	end
	if humanoid.Health <= 0 or humanoid.Sit then
		return nil
	end
	local state = humanoid:GetState()
	if
		state == Enum.HumanoidStateType.Seated
		or state == Enum.HumanoidStateType.Dead
		or state == Enum.HumanoidStateType.Physics
		or state == Enum.HumanoidStateType.Swimming -- nadar é lento de propósito
		or state == Enum.HumanoidStateType.Climbing
	then
		return nil
	end
	if humanoid.FloorMaterial == Enum.Material.Water then
		return nil
	end
	if character:FindFirstChild("Ragdoll") then
		return nil -- ragdoll do pacote ligado de propósito
	end
	if hrp:GetAttribute("CrawlLock") == true then
		return CRAWL_STUCK_SECONDS
	end
	return STUCK_SECONDS
end

local function weldsHoldingHRP(character: Model, hrp: BasePart): { Instance }
	local held = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") then
			local anyD = d :: any
			local other = if anyD.Part0 == hrp then anyD.Part1 elseif anyD.Part1 == hrp then anyD.Part0 else nil
			if other and other:IsA("BasePart") and other.Anchored and not other:IsDescendantOf(character) then
				table.insert(held, d)
			end
		end
	end
	return held
end

local function unstick(character: Model, humanoid: Humanoid, hrp: BasePart)
	local found = {}

	if hrp.Anchored then
		table.insert(found, "HRP estava Anchored")
		hrp.Anchored = false
	end
	if humanoid.PlatformStand then
		table.insert(found, "PlatformStand estava true")
		humanoid.PlatformStand = false
	end
	local welds = weldsHoldingHRP(character, hrp)
	for _, w in welds do
		local other = if (w :: any).Part0 == hrp then (w :: any).Part1 else (w :: any).Part0
		table.insert(found, `{w.ClassName} prendia a HRP em '{other and other:GetFullName()}' (ancorada)`)
		w:Destroy()
	end
	if humanoid.WalkSpeed <= 0.15 then
		table.insert(found, `WalkSpeed estava {humanoid.WalkSpeed}`)
		humanoid.WalkSpeed = RESTORE_SPEED
	end
	if humanoid:GetState() == Enum.HumanoidStateType.Physics then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		table.insert(found, "estava em state Physics")
	end

	if #found == 0 then
		table.insert(found, "nada óbvio -- pode ser conveyor/parte girando embaixo, ou o control não está lendo input (ver [DIAG])")
	end
	warn("[MovementWatchdog] boneco travado destravado. Causa(s):\n   - " .. table.concat(found, "\n   - "))
end

RunService.Heartbeat:Connect(function()
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not hrp or not hrp:IsA("BasePart") then
		stuckSince = nil
		return
	end

	local wantsToMove = humanoid.MoveDirection.Magnitude > WANT_MOVE
	local actuallyMoving = horizSpeed(hrp) > REAL_MOVE
	local frozen = wantsToMove and not actuallyMoving

	if not frozen then
		stuckSince = nil
		return
	end

	local grace = graceFor(character, humanoid, hrp)
	if grace == nil then
		stuckSince = nil
		return
	end

	stuckSince = stuckSince or os.clock()
	if (os.clock() - stuckSince) >= grace then
		if os.clock() - lastReport > 3 then -- não spammar
			unstick(character, humanoid, hrp)
			lastReport = os.clock()
		end
		stuckSince = nil
	end
end)
