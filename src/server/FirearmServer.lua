--!strict
--[[
	FirearmServer
	Lado servidor das armas de fogo (par do cliente PistolController). Port do
	ServerHandler do OTS com validação básica e integrado ao jogo. O cliente
	OTS original (CameraWeapon/WeaponController) foi REMOVIDO junto com a
	câmera de ombro -- este lado servidor não mudou, só quem dispara os
	remotes é que é outro:

	  FirearmShoot   -> desconta munição (autoridade do servidor), toca o som
	                    da arma e o flash no Muzzle (replicam pra todos).
	  FirearmHit     -> tracer + impacto (WeaponEffects). O Muzzle é lido da
	                    Tool do jogador AQUI, não confiado do cliente.
	  FirearmDamage  -> dano por parte (Head/Torso/Limbs, Settings/Damage),
	                    armadura (pasta "Armour" com Health), hitmarker de
	                    volta pro atirador. O dano na vida e a morte passam
	                    pelo DamageSystem.Apply (marca "Dead", Elimination.
	                    Eliminate, PlayerKilled cause "Tiro"); aqui fica só o
	                    kill feed quando Apply avisa que matou.
	  FirearmReload  -> etapas da recarga vindas dos markers da animação
	                    (Start/MagOut/MagIn/BoltPull/BoltRelease/End/ShellIn):
	                    sons do Handle, pente caindo, munição.

	VALIDAÇÃO (anti-abuso simples): só aceita se o jogador tiver uma arma de
	fogo equipada; cadência mínima (Delay * 0.75); alvo precisa ter Humanoid,
	não ser o próprio atirador e estar dentro de Config MaxRange + folga.
	Hitscan continua no cliente (feel), como no OTS.

	MODO DE TESTE: GameConfig.Testing.GiveTestWeapons = { "M4A1", ... } dá
	essas Tools (de ReplicatedStorage/WeaponAssets/Tools) no Backpack a cada
	spawn. nil desliga.

	Uso: safeInit("FirearmServer", require(script.FirearmServer)) no boot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local SafeWait = require(ReplicatedStorage.Modules.SafeWait)
local SafeAttribute = require(ReplicatedStorage.Modules.SafeAttribute)
local WeaponEffects = require(ReplicatedStorage.Modules.WeaponEffects)
local Ammo = require(ReplicatedStorage.Modules.Ammo)
local DamageSystem = require(script.Parent.DamageSystem)
local AmmoSystem = require(script.Parent.AmmoSystem)

local FirearmServer = {}

local WeaponAssets = SafeWait.Child(ReplicatedStorage, "WeaponAssets")
local Audios = SafeWait.Child(WeaponAssets, "Audios")
local ToolsFolder = SafeWait.Child(WeaponAssets, "Tools")

local MAX_RANGE = 1000
local RANGE_SLACK = 60

local HEAD_PARTS = { Head = true }
local TORSO_PARTS = { Torso = true, UpperTorso = true, LowerTorso = true, HumanoidRootPart = true }

local lastShotAt: { [Player]: number } = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function isFirearm(instance: Instance): boolean
	if not instance:IsA("Tool") then
		return false
	end
	local flag = instance:FindFirstChild("Weapon")
	if flag and flag:IsA("BoolValue") and flag.Value then
		return true
	end
	return SafeAttribute.Get(instance, "Firearm") == true
end

local function getEquippedFirearm(player: Player): Tool?
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		if isFirearm(child) then
			return child :: Tool
		end
	end
	return nil
end

local function settingsValue(tool: Tool, folderName: string, name: string): ValueBase?
	local settings = tool:FindFirstChild("Settings")
	local folder = settings and settings:FindFirstChild(folderName)
	local value = folder and folder:FindFirstChild(name)
	if value and value:IsA("ValueBase") then
		return value
	end
	return nil
end

local function numberValue(tool: Tool, folderName: string, name: string, default: number): number
	local value = settingsValue(tool, folderName, name)
	if value and value:IsA("NumberValue") then
		return value.Value
	elseif value and value:IsA("IntValue") then
		return value.Value
	end
	return default
end

local function getMuzzle(tool: Tool): BasePart?
	local components = tool:FindFirstChild("Components")
	local muzzle = components and components:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("BasePart") then
		return muzzle
	end
	return nil
end

local function getRootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function playHandleSound(tool: Tool, name: string)
	local handle = tool:FindFirstChild("Handle")
	local sound = handle and handle:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

--------------------------------------------------------------------------------
-- Tiro
--------------------------------------------------------------------------------

local function onShoot(player: Player)
	local tool = getEquippedFirearm(player)
	if not tool then
		return
	end

	local ammo = settingsValue(tool, "Config", "Ammo")
	if ammo and ammo:IsA("NumberValue") and ammo.Value <= 0 then
		return
	end

	local delay = numberValue(tool, "Config", "Delay", 0.1)
	local now = os.clock()
	if now - (lastShotAt[player] or 0) < delay * 0.75 then
		return
	end
	lastShotAt[player] = now

	if ammo and ammo:IsA("NumberValue") then
		ammo.Value -= 1
	end

	local muzzle = getMuzzle(tool)
	if not muzzle then
		return
	end

	local soundName = SafeAttribute.Get(tool, "SoundName")
	local weaponsAudio = Audios:FindFirstChild("Weapons")
	local template = weaponsAudio and weaponsAudio:FindFirstChild(if type(soundName) == "string" and soundName ~= "" then soundName else tool.Name)
	if template and template:IsA("Sound") then
		local sound = template:Clone()
		sound.PlayOnRemove = false
		sound.Parent = muzzle
		sound:Play()
		-- TimeLength pode ser 0 antes do áudio carregar; Ended é confiável,
		-- e o delay longo é só rede de segurança pra som que nunca toca.
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		task.delay(10, function()
			if sound.Parent then
				sound:Destroy()
			end
		end)
	end

	for _, descendant in muzzle:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant:Emit(10)
		end
	end
end

local function onHit(player: Player, position: unknown, instance: unknown, normal: unknown)
	if typeof(position) ~= "Vector3" then
		return
	end
	local tool = getEquippedFirearm(player)
	if not tool then
		return
	end

	local muzzle = getMuzzle(tool)
	local head = player.Character and player.Character:FindFirstChild("Head")
	local muzzleCFrame = if muzzle then muzzle.CFrame elseif head and head:IsA("BasePart") then head.CFrame else nil
	if not muzzleCFrame then
		return
	end

	if ((position :: Vector3) - muzzleCFrame.Position).Magnitude > MAX_RANGE + RANGE_SLACK then
		return
	end

	WeaponEffects.CreateTracer(muzzleCFrame, position :: Vector3)

	if typeof(instance) == "Instance" and typeof(normal) == "Vector3" then
		WeaponEffects.CreateImpact(position :: Vector3, instance :: Instance, normal :: Vector3)
	end
end

--------------------------------------------------------------------------------
-- Dano
--------------------------------------------------------------------------------

local function onDamage(player: Player, targetPart: unknown)
	if typeof(targetPart) ~= "Instance" or not (targetPart :: Instance):IsA("BasePart") then
		return
	end
	local part = targetPart :: BasePart

	local model = part:FindFirstAncestorOfClass("Model")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not model or not humanoid or humanoid.Health <= 0 then
		return
	end
	if model == player.Character then
		return
	end

	local tool = getEquippedFirearm(player)
	if not tool then
		return
	end

	local shooterPosition = getRootPosition(player)
	if not shooterPosition or (part.Position - shooterPosition).Magnitude > MAX_RANGE + RANGE_SLACK then
		return
	end

	local damage: number
	local isHead = HEAD_PARTS[part.Name] == true
	if isHead then
		damage = numberValue(tool, "Damage", "HeadDamage", 25)
	elseif TORSO_PARTS[part.Name] then
		damage = numberValue(tool, "Damage", "TorsoDamage", 17)
	else
		damage = numberValue(tool, "Damage", "LimbsDamage", 11)
	end

	-- Armadura (pasta "Armour" com NumberValue "Health") absorve primeiro.
	local armour = model:FindFirstChild("Armour")
	local armourHealth = armour and armour:FindFirstChild("Health")
	if armour and armourHealth and armourHealth:IsA("NumberValue") and armourHealth.Value > 0 then
		armourHealth.Value -= damage
		Remotes.FirearmDamage:FireClient(player, if isHead then "HeadArmor" else "Armor")
		if armourHealth.Value <= 0 then
			armour:Destroy()
			Remotes.FirearmFeed:FireClient(player, "Armour", model.Name)
		end
		return
	end

	-- DamageSystem aplica o dano e, se matar, marca "Dead" + Elimination +
	-- PlayerKilled. Aqui só cuidamos do feedback específico da arma.
	local _, died = DamageSystem.Apply(humanoid, damage, { Source = player, Cause = "Tiro" })
	Remotes.FirearmDamage:FireClient(player, if isHead then "Head" else "Hit")

	if died then
		Remotes.FirearmFeed:FireClient(player, "Kill", model.Name)
	end
end

--------------------------------------------------------------------------------
-- Recarga
--------------------------------------------------------------------------------

local function dropMagazine(tool: Tool)
	local components = tool:FindFirstChild("Components")
	local mag = components and components:FindFirstChild("Mag")
	if not mag or not mag:IsA("BasePart") then
		return
	end

	local clone = mag:Clone()
	local weld = clone:FindFirstChildOfClass("WeldConstraint")
	if weld then
		weld:Destroy()
	end
	clone.Anchored = false
	clone.CanCollide = true
	clone.Massless = true
	clone.Transparency = 0

	local system = workspace:FindFirstChild("System")
	local misc = system and system:FindFirstChild("Misc")
	clone.Parent = misc or workspace
	mag.Transparency = 1

	task.delay(5, function()
		clone:Destroy()
	end)
end

local function onReload(player: Player, stage: unknown)
	if type(stage) ~= "string" then
		return
	end
	local tool = getEquippedFirearm(player)
	if not tool then
		return
	end

	local reloading = settingsValue(tool, "Config", "Reloading")
	local ammo = settingsValue(tool, "Config", "Ammo")
	local maxAmmo = numberValue(tool, "Config", "MaxAmmo", 30)

	if stage == "Start" then
		if reloading and reloading:IsA("BoolValue") then
			reloading.Value = true
		end
	elseif stage == "MagOut" then
		playHandleSound(tool, "MagOut")
		dropMagazine(tool)
	elseif stage == "MagIn" then
		playHandleSound(tool, "MagIn")
		local components = tool:FindFirstChild("Components")
		local mag = components and components:FindFirstChild("Mag")
		if mag and mag:IsA("BasePart") then
			mag.Transparency = 0
		end
	elseif stage == "BoltPull" then
		playHandleSound(tool, "BoltIn")
	elseif stage == "BoltRelease" then
		playHandleSound(tool, "BoltOut")
	elseif stage == "ShellIn" then
		-- Shotgun: entra 1 cartucho por vez, cada um sai da reserva.
		playHandleSound(tool, "MagIn")
		if ammo and ammo:IsA("NumberValue") and ammo.Value < maxAmmo then
			ammo.Value += AmmoSystem.TakeReserve(player, Ammo.TypeFor(tool), 1)
		end
		task.delay(0.2, function()
			if reloading and reloading:IsA("BoolValue") then
				reloading.Value = false
			end
		end)
	elseif stage == "End" then
		-- Recarga normal: o pente só enche até onde a RESERVA dá.
		if ammo and ammo:IsA("NumberValue") then
			local needed = maxAmmo - ammo.Value
			if needed > 0 then
				ammo.Value += AmmoSystem.TakeReserve(player, Ammo.TypeFor(tool), needed)
			end
		end
		if reloading and reloading:IsA("BoolValue") then
			reloading.Value = false
		end
	end
end

--------------------------------------------------------------------------------
-- Modo de teste: armas no Backpack
--------------------------------------------------------------------------------

local function giveTestWeapons(player: Player)
	local names = GameConfig.Testing.GiveTestWeapons
	if type(names) ~= "table" then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		return
	end
	for _, name in names do
		local template = ToolsFolder:FindFirstChild(name)
		if template and template:IsA("Tool") then
			if not backpack:FindFirstChild(name) then
				template:Clone().Parent = backpack
			end
		else
			warn(string.format("[FirearmServer] Arma de teste '%s' não existe em WeaponAssets/Tools.", tostring(name)))
		end
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function FirearmServer.Init()
	Remotes.FirearmShoot.OnServerEvent:Connect(onShoot)
	Remotes.FirearmHit.OnServerEvent:Connect(onHit)
	Remotes.FirearmDamage.OnServerEvent:Connect(onDamage)
	Remotes.FirearmReload.OnServerEvent:Connect(onReload)

	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(giveTestWeapons, player)
		end)
		if player.Character then
			giveTestWeapons(player)
		end
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		lastShotAt[player] = nil
	end)
end

return FirearmServer
