--!strict
--[[
	MonsterLightWeakness
	Fraqueza do Monstro à luz: Zonas Seguras e Tochas.

	Duas fontes de fraqueza, mesmo efeito:
	  1) Zona Segura: Part estática com Attribute "ZonaSegura" == true.
	     Detecção por .Touched (evento, sem polling) -- ideal pra volumes
	     estáticos parados no mapa.
	  2) Tocha: Tool com Attribute "Tocha" == true. Enquanto equipada, cria
	     um PointLight no Handle e o Monstro é verificado por proximidade
	     num loop com intervalo (GameConfig.MonsterWeakness.TorchCheckInterval)
	     -- não dá pra usar .Touched aqui porque a "área de luz" não é um
	     volume físico, então precisa de checagem de distância periódica
	     (mas throttled, não a cada frame).

	Efeito aplicado ao Monstro: empurrão pra fora da fonte + redução de
	WalkSpeed por um tempo (renovado a cada novo contato, sem empilhar).
	Todos os valores de balanceamento vêm de GameConfig.MonsterWeakness.

	IMPORTANTE (setup no Studio, fora do escopo deste script):
	  - Crie as Parts de Zona Segura no mapa com Attribute "ZonaSegura" = true.
	  - Crie o Tool "Tocha" com um Handle (BasePart) e Attribute "Tocha" = true.

	Uso (chamar uma vez no boot do servidor):
		local MonsterLightWeakness = require(script.MonsterLightWeakness)
		MonsterLightWeakness.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)
local SafeAttribute = require(ReplicatedStorage.Modules.SafeAttribute)

local MonsterLightWeakness = {}

type WeakenState = {
	baseWalkSpeed: number,
	weakenedUntil: number,
}

-- character (Model) -> estado do enfraquecimento em andamento.
local weakenState: { [Model]: WeakenState } = {}

-- character (Model) -> os.clock() do último reforço vindo de uma Zona Segura.
local lastZoneTriggerAt: { [Model]: number } = {}

-- Tools "Tocha" atualmente equipados, e os que já têm listener conectado.
local equippedTorches: { [Tool]: true } = {}
local watchedTools: { [Tool]: true } = {}

--------------------------------------------------------------------------------
-- Efeito compartilhado: empurrão + lentidão temporária
--------------------------------------------------------------------------------

local function getMonsterCharacter(character: Model): (Humanoid?, BasePart?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoid and rootPart and rootPart:IsA("BasePart") then
		return humanoid, rootPart
	end
	return nil, nil
end

local function isMonster(character: Model): boolean
	local player = Players:GetPlayerFromCharacter(character)
	return player ~= nil and player:GetAttribute("Role") == GameConfig.Roles.Monster
end

local function weakenMonster(character: Model, sourcePosition: Vector3)
	local humanoid, rootPart = getMonsterCharacter(character)
	if not (humanoid and rootPart) then
		return
	end

	-- Empurrão: sempre aplica de novo a cada contato, mesmo se já estiver fraco.
	local horizontalOffset = Vector3.new(rootPart.Position.X - sourcePosition.X, 0, rootPart.Position.Z - sourcePosition.Z)
	local pushDirection = horizontalOffset.Magnitude > 1e-3 and horizontalOffset.Unit
		or Vector3.new(1, 0, 0) -- fonte bem em cima do Monstro: empurra numa direção arbitrária fixa

	rootPart.AssemblyLinearVelocity = pushDirection * GameConfig.MonsterWeakness.PushForce
		+ Vector3.new(0, GameConfig.MonsterWeakness.PushUpwardForce, 0)

	local state = weakenState[character]
	if not state then
		state = {
			baseWalkSpeed = if character:GetAttribute("ShadowRushBusy") == true
				then GameConfig.Movement.WalkSpeed * GameConfig.Monster.SpeedMultiplier
				else humanoid.WalkSpeed,
			weakenedUntil = 0,
		}
		weakenState[character] = state
		humanoid.WalkSpeed = math.max(0, state.baseWalkSpeed - GameConfig.MonsterWeakness.WalkSpeedReduction)

		character.AncestryChanged:Connect(function(_, parent)
			if not parent then
				weakenState[character] = nil
			end
		end)

		task.spawn(function()
			while os.clock() < state.weakenedUntil do
				task.wait(0.1)
			end

			if weakenState[character] == state then
				weakenState[character] = nil
				if humanoid.Parent and character:GetAttribute("ShadowRushBusy") ~= true then
					humanoid.WalkSpeed = state.baseWalkSpeed
				end
			end
		end)
	end

	state.weakenedUntil = os.clock() + GameConfig.MonsterWeakness.WeakenDuration
end

--[[
	IsWeakened(character)
	Usado por ConfrontSystem.lua: a Lança Ancestral só mata o Monstro
	enquanto ele está fraco pela luz.
]]
function MonsterLightWeakness.IsWeakened(character: Model): boolean
	local state = weakenState[character]
	return state ~= nil and os.clock() < state.weakenedUntil
end

--------------------------------------------------------------------------------
-- Zona Segura (.Touched -- evento, sem polling)
--------------------------------------------------------------------------------

local function onZoneTouched(zonePart: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character or not isMonster(character) then
		return
	end

	local now = os.clock()
	local last = lastZoneTriggerAt[character]
	if last and (now - last) < GameConfig.MonsterWeakness.ZoneRetriggerInterval then
		return
	end
	lastZoneTriggerAt[character] = now

	weakenMonster(character, zonePart.Position)
end

local function watchZone(zonePart: Instance)
	if not zonePart:IsA("BasePart") then
		return
	end

	zonePart.Touched:Connect(function(hit)
		onZoneTouched(zonePart, hit)
	end)
end

--------------------------------------------------------------------------------
-- Fonte de luz genérica (Tool + PointLight interno + verificação de
-- proximidade throttled), usada pela Tocha ao equipar. A lanterna
-- direcional usa FlashlightSystem e nao participa deste efeito de area.
--------------------------------------------------------------------------------

-- Combustível persiste no Attribute do próprio Tool (sobrevive a
-- equipar/desequipar/religar) e só é criado na primeira vez que acende.
local function getFuel(tool: Tool): number
	local fuel = tool:GetAttribute("CombustivelRestante")
	if type(fuel) ~= "number" then
		fuel = GameConfig.MonsterWeakness.TorchFuelDuration
		tool:SetAttribute("CombustivelRestante", fuel)
	end
	return fuel
end

--[[
	ActivateLightSource(tool)
	Liga a fraqueza do Monstro pra esse Tool (precisa ter um Handle e
	combustível > 0). Devolve se conseguiu ligar a fonte de area.
]]
local function activateLightSource(tool: Tool): boolean
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return false
	end

	if getFuel(tool) <= 0 then
		return false -- sem combustível
	end

	if not handle:FindFirstChild("MonsterWeaknessLight") then
		local light = Instance.new("PointLight")
		light.Name = "MonsterWeaknessLight"
		light.Range = GameConfig.MonsterWeakness.TorchLightRange
		light.Brightness = GameConfig.MonsterWeakness.TorchLightBrightness
		light.Parent = handle
	end

	equippedTorches[tool] = true
	return true
end

--[[
	DeactivateLightSource(tool)
	Desliga a fraqueza do Monstro pra esse Tool (não mexe em nenhum efeito
	visual próprio do item -- isso é responsabilidade de quem chamou).
]]
local function deactivateLightSource(tool: Tool)
	equippedTorches[tool] = nil

	local handle = tool:FindFirstChild("Handle")
	local light = handle and handle:FindFirstChild("MonsterWeaknessLight")
	if light then
		light:Destroy()
	end
end

MonsterLightWeakness.ActivateLightSource = activateLightSource
MonsterLightWeakness.DeactivateLightSource = deactivateLightSource

-- Tocha: liga sozinha ao equipar (comportamento original, sem toggle).
local function watchTorch(tool: Instance)
	if not tool:IsA("Tool") or watchedTools[tool] then
		return
	end
	watchedTools[tool] = true

	tool.Equipped:Connect(function()
		activateLightSource(tool)
	end)

	tool.Unequipped:Connect(function()
		deactivateLightSource(tool)
	end)

	tool.Destroying:Connect(function()
		watchedTools[tool] = nil
		equippedTorches[tool] = nil
	end)
end

-- Loop throttled: verifica todo Monstro contra toda tocha equipada.
-- Roda a cada GameConfig.MonsterWeakness.TorchCheckInterval, não por frame.
local function startTorchProximityLoop()
	task.spawn(function()
		while true do
			task.wait(GameConfig.MonsterWeakness.TorchCheckInterval)

			for tool in equippedTorches do
				local remaining = getFuel(tool) - GameConfig.MonsterWeakness.TorchCheckInterval
				tool:SetAttribute("CombustivelRestante", math.max(remaining, 0))

				if remaining <= 0 then
					deactivateLightSource(tool)
					continue
				end

				local character = tool.Parent
				local torchRoot = character and character:IsA("Model") and character:FindFirstChild("HumanoidRootPart")
				if torchRoot and torchRoot:IsA("BasePart") then
					for _, player in Players:GetPlayers() do
						if player:GetAttribute("Role") == GameConfig.Roles.Monster and player.Character then
							local _, monsterRoot = getMonsterCharacter(player.Character)
							if
								monsterRoot
								and (monsterRoot.Position - torchRoot.Position).Magnitude
									<= GameConfig.MonsterWeakness.TorchRadius
							then
								weakenMonster(player.Character, torchRoot.Position)
							end
						end
					end
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Descoberta de instâncias marcadas (existentes + futuras)
--------------------------------------------------------------------------------

local function forEachTagged(root: Instance, attributeName: string, callback: (Instance) -> ())
	for _, descendant in root:GetDescendants() do
		if SafeAttribute.Get(descendant, attributeName) == true then
			callback(descendant)
		end
	end

	root.DescendantAdded:Connect(function(descendant)
		if SafeAttribute.Get(descendant, attributeName) == true then
			callback(descendant)
		end
	end)
end

--[[
	Init()
	Conecta as Zonas Seguras existentes/futuras no Workspace e as Tochas
	existentes/futuras em todo o jogo (elas circulam entre Backpack e
	Character conforme são equipadas). Chame uma vez no boot do servidor.
]]
function MonsterLightWeakness.Init()
	forEachTagged(Workspace, "ZonaSegura", watchZone)
	forEachTagged(game, AssetRegistry.Tocha_Item.AttributeName, watchTorch)
	startTorchProximityLoop()
end

return MonsterLightWeakness
