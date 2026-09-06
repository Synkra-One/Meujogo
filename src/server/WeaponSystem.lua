--!strict
--[[
	WeaponSystem
	Efeitos de uso das armas fracas (Faca Improvisada, Lança de Bambu,
	Pedra Afiada) -- dados de cada uma em ReplicatedStorage/Modules/ItemRegistry.lua.

	Nenhuma delas mata: não existe sistema de dano/Health no jogo ainda (só
	Elimination.Eliminate, que é definitivo e não tem "ferido"). Então "dano
	fraco/leve/mínimo" vira EMPURRÃO no Monstro + log no console, mesmo
	espírito de placeholder do resto do projeto -- até você ter uma barra
	de vida de verdade pra plugar números.

	FACA IMPROVISADA / LANÇA DE BAMBU: Tool.Activated -> acha o Monstro mais
	próximo dentro de um cone à frente do jogador (GameConfig.Weapons.
	MeleeConeCos -- precisa mirar, não só estar perto) e do alcance da arma
	(KnifeRange 6 / SpearRange 10), e empurra ele pra longe.

	PEDRA AFIADA: Tool.Activated -> ponto de impacto na direção que o
	jogador olha (ThrowDistance), som posicional (SoundManager, placeholder)
	e dispara o hook WeaponSystem.NoiseMade(position) -- gancho pronto pra
	uma futura IA do Monstro reagir a barulho, ninguém escuta ainda.

	IMPORTANTE (setup no Studio, fora do escopo deste script): Tools com
	Attribute "FacaImprovisada" / "LancaDeBambu" / "PedraAfiada" = true
	(ItemSpawner.lua também cria essas Tools ao spawnar pickups no mapa).

	Uso (chamar uma vez no boot do servidor):
		local WeaponSystem = require(script.WeaponSystem)
		WeaponSystem.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local ItemRegistry = require(ReplicatedStorage.Modules.ItemRegistry)
local SafeAttribute = require(ReplicatedStorage.Modules.SafeAttribute)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local SoundManager = require(script.Parent.SoundManager)
local DamageSystem = require(script.Parent.DamageSystem)

local WeaponSystem = {}

-- Hook público: nenhuma IA de Monstro escuta isso ainda.
WeaponSystem.NoiseMade = Instance.new("BindableEvent")

local watchedTools: { [Tool]: true } = {}

local function getRootPart(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Monstro mais próximo dentro do alcance E de um cone à frente do atacante.
local function findMonsterInFrontOf(attackerRoot: BasePart, range: number): BasePart?
	local best: BasePart? = nil
	local bestDistance = range

	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == GameConfig.Roles.Monster and player.Character then
			local targetRoot = getRootPart(player.Character)
			if targetRoot then
				local offset = targetRoot.Position - attackerRoot.Position
				local distance = offset.Magnitude
				if distance > 0.01 and distance <= bestDistance then
					local facing = offset.Unit:Dot(attackerRoot.CFrame.LookVector)
					if facing >= GameConfig.Weapons.MeleeConeCos then
						best = targetRoot
						bestDistance = distance
					end
				end
			end
		end
	end

	return best
end

local function pushMonster(monsterRoot: BasePart, fromPosition: Vector3, attacker: Player?)
	local direction = monsterRoot.Position - fromPosition
	if direction.Magnitude < 0.01 then
		direction = Vector3.new(1, 0, 0)
	else
		direction = direction.Unit
	end

	-- FORÇA -> empurrão mais forte. Bruno (Força 94) joga o Monstro bem mais
	-- longe que Sofia (Força 10) com a mesma faca. O dano em si já escala
	-- sozinho, dentro do DamageSystem.
	local force = GameConfig.Weapons.MeleePushForce * StatScaling.DamageDealtMultiplier(attacker)
	monsterRoot.AssemblyLinearVelocity = direction * force + Vector3.new(0, force * 0.2, 0)
end

local function onMeleeActivated(player: Player, range: number, weaponName: string, damage: number)
	local character = player.Character
	local root = character and getRootPart(character)
	if not root then
		return
	end

	local monsterRoot = findMonsterInFrontOf(root, range)
	if not monsterRoot then
		return
	end

	pushMonster(monsterRoot, root.Position, player)

	-- Dano de verdade só se configurado (GameConfig.Weapons.*Damage > 0);
	-- senão a arma continua sendo só empurrão, como era antes.
	if damage > 0 then
		local monsterModel = monsterRoot:FindFirstAncestorOfClass("Model")
		local applied = DamageSystem.Apply(monsterModel, damage, { Source = player, Cause = weaponName })
		print(string.format("[WeaponSystem] %s acertou o Monstro com %s (-%d HP).", player.Name, weaponName, applied))
	else
		print(string.format("[WeaponSystem] %s acertou o Monstro com %s (empurrão placeholder).", player.Name, weaponName))
	end
end

local function onPedraActivated(player: Player)
	local character = player.Character
	local root = character and getRootPart(character)
	if not root then
		return
	end

	local impact = root.Position + root.CFrame.LookVector * GameConfig.Weapons.ThrowDistance
	SoundManager.PlayThrowSound(impact)
	WeaponSystem.NoiseMade:Fire(impact)
	print(string.format("[WeaponSystem] %s arremessou uma Pedra Afiada -- barulho perto de (%.0f, %.0f, %.0f).", player.Name, impact.X, impact.Y, impact.Z))
end

local HANDLERS: { [string]: (Player) -> () } = {
	FacaImprovisada = function(player: Player)
		onMeleeActivated(player, GameConfig.Weapons.KnifeRange, "Faca Improvisada", GameConfig.Weapons.KnifeDamage)
	end,
	LancaDeBambu = function(player: Player)
		onMeleeActivated(player, GameConfig.Weapons.SpearRange, "Lança de Bambu", GameConfig.Weapons.SpearDamage)
	end,
	PedraAfiada = onPedraActivated,
}

local WEAPON_ITEM_IDS = { "FacaImprovisada", "LancaDeBambu", "PedraAfiada" }

local function watchWeapon(tool: Instance)
	if not tool:IsA("Tool") or watchedTools[tool] then
		return
	end

	for _, itemId in WEAPON_ITEM_IDS do
		local def = ItemRegistry.Items[itemId]
		local attributeName = def.AttributeName :: string
		if SafeAttribute.Get(tool, attributeName) == true then
			watchedTools[tool] = true
			local handler = HANDLERS[itemId]

			tool.Activated:Connect(function()
				local character = tool.Parent
				local player = character and character:IsA("Model") and Players:GetPlayerFromCharacter(character)
				if player then
					handler(player)
				end
			end)

			tool.Destroying:Connect(function()
				watchedTools[tool] = nil
			end)

			return
		end
	end
end

local function forEachTool(root: Instance, callback: (Instance) -> ())
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Tool") then
			callback(descendant)
		end
	end

	root.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Tool") then
			callback(descendant)
		end
	end)
end

--[[
	Init()
	Conecta as três armas em qualquer Tool existente/futura no jogo
	(circulam entre Backpack e Character). Chame uma vez no boot do servidor.
]]
function WeaponSystem.Init()
	forEachTool(game, watchWeapon)
end

return WeaponSystem
