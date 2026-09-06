--!strict
--[[
	WeaponSpawner
	Espalha as armas de fogo (hoje só a Glock17) e as caixas de munição pelo
	mapa, no CHÃO -- ninguém nasce armado (GameConfig.Testing.GiveTestWeapons
	é nil). Quantidades em GameConfig.Firearms.WorldSpawns.

	A arma no chão é a Tool de verdade (clone de WeaponAssets/Tools), colocada
	por DropItemSystem.PlaceInWorld -- então ganha o MESMO ProximityPrompt
	"Pegar" dos itens largados por jogador, e ao pegar vai direto pro Backpack
	com o pente cheio (Settings/Config/Ammo do template). A munição extra só
	vem das caixas (AmmoSystem.CreatePickup).

	ONDE ELAS NASCEM (na ordem, o primeiro que existir vence):
	  1. Parts com Attribute "SpawnArma" == true -- se você quiser escolher os
	     lugares na mão no Studio, é só marcar Parts com esse Attribute.
	  2. Workspace.Ilha (mapa gerado): pontos de praia achados por raycast,
	     mesma amostragem que o ItemSpawner.lua usa.
	  3. Workspace.IlhaSpawns (sempre existe, vem do default.project.json).
	  4. Workspace.LobbySpawn -- último recurso, pra dar pra testar mesmo com
	     o mapa não gerado.

	Cada ponto ganha um desvio aleatório de até WorldSpawns.SpreadRadius studs,
	e a altura final vem de um raycast pro chão (não fica boiando/enterrado).

	Init() gera uma vez no boot. Generate() dá pra chamar de novo na Command
	Bar pra reposicionar tudo sem reiniciar o servidor.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local SafeWait = require(ReplicatedStorage.Modules.SafeWait)
local AmmoSystem = require(script.Parent.AmmoSystem)
local DropItemSystem = require(script.Parent.DropItemSystem)

local WeaponSpawner = {}

local FOLDER_NAME = "ArmasNoChao"
local GROUND_PROBE_HEIGHT = 400
local GROUND_PROBE_DEPTH = 900

local ToolsFolder = SafeWait.Child(SafeWait.Child(ReplicatedStorage, "WeaponAssets"), "Tools")

--------------------------------------------------------------------------------
-- Chão
--------------------------------------------------------------------------------

-- Só terreno e partes ancoradas contam como "chão" -- senão a arma nasceria
-- em cima de outra arma/jogador.
local function groundY(x: number, z: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	params.FilterDescendantsInstances = if existing then { existing } else {}

	local result = Workspace:Raycast(
		Vector3.new(x, GROUND_PROBE_HEIGHT, z),
		Vector3.new(0, -GROUND_PROBE_DEPTH, 0),
		params
	)
	return if result then result.Position.Y else nil
end

--------------------------------------------------------------------------------
-- Pontos-âncora
--------------------------------------------------------------------------------

local function taggedSpawnPoints(): { Vector3 }
	local points: { Vector3 } = {}
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("SpawnArma") == true then
			table.insert(points, descendant.Position)
		end
	end
	return points
end

local function beachPoints(rng: Random, count: number): { Vector3 }
	local points: { Vector3 } = {}
	if not Workspace:FindFirstChild("Ilha") then
		return points
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	params.IgnoreWater = true

	local attempts = 0
	while #points < count and attempts < count * 40 do
		attempts += 1
		local x, z = rng:NextNumber(-260, 260), rng:NextNumber(-260, 260)
		local result = Workspace:Raycast(
			Vector3.new(x, GROUND_PROBE_HEIGHT, z),
			Vector3.new(0, -GROUND_PROBE_DEPTH, 0),
			params
		)
		if result and (result.Material == Enum.Material.Sand or result.Material == Enum.Material.Grass) then
			table.insert(points, result.Position)
		end
	end
	return points
end

local function islandSpawnPoints(): { Vector3 }
	local points: { Vector3 } = {}
	local folder = Workspace:FindFirstChild("IlhaSpawns")
	if not folder then
		return points
	end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(points, child.Position)
		end
	end
	return points
end

local function lobbyPoints(): { Vector3 }
	local spawn = Workspace:FindFirstChild("LobbySpawn")
	if spawn and spawn:IsA("BasePart") then
		return { spawn.Position }
	end
	return {}
end

local function anchorPoints(rng: Random): ({ Vector3 }, string)
	local tagged = taggedSpawnPoints()
	if #tagged > 0 then
		return tagged, "Parts com Attribute SpawnArma"
	end

	local beach = beachPoints(rng, 12)
	if #beach > 0 then
		return beach, "praia da Ilha"
	end

	local spawns = islandSpawnPoints()
	if #spawns > 0 then
		return spawns, "IlhaSpawns"
	end

	return lobbyPoints(), "LobbySpawn (mapa não gerado ainda)"
end

--------------------------------------------------------------------------------
-- Geração
--------------------------------------------------------------------------------

local function getFolder(): Folder
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

-- Ponto final = âncora sorteada + desvio aleatório, altura vinda do raycast.
local function scatterPoint(anchors: { Vector3 }, rng: Random): Vector3?
	if #anchors == 0 then
		return nil
	end
	local anchor = anchors[rng:NextInteger(1, #anchors)]
	local radius = GameConfig.Firearms.WorldSpawns.SpreadRadius
	local x = anchor.X + rng:NextNumber(-radius, radius)
	local z = anchor.Z + rng:NextNumber(-radius, radius)
	local y = groundY(x, z)
	return Vector3.new(x, (y or anchor.Y) + 1.5, z)
end

--[[ ClearSpawns() -- apaga Workspace.ArmasNoChao (armas E caixas geradas). ]]
function WeaponSpawner.ClearSpawns()
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
end

--[[
	Generate(seed?)
	Recria todas as armas e caixas de munição do mapa. Pode ser chamada de
	novo a qualquer momento (limpa as anteriores antes).
]]
function WeaponSpawner.Generate(seed: number?)
	WeaponSpawner.ClearSpawns()

	local rng = Random.new(seed or 20260905)
	local anchors, source = anchorPoints(rng)
	if #anchors == 0 then
		warn("[WeaponSpawner] Nenhum ponto de spawn encontrado -- nada foi colocado no chão.")
		return
	end

	local folder = getFolder()
	local spawns = GameConfig.Firearms.WorldSpawns
	local allowed = GameConfig.Firearms.Allowed

	-- Armas
	local placedWeapons = 0
	for _ = 1, spawns.Weapons do
		local weaponName = allowed[rng:NextInteger(1, #allowed)]
		local template = ToolsFolder:FindFirstChild(weaponName)
		if not template or not template:IsA("Tool") then
			warn(string.format("[WeaponSpawner] '%s' não existe em WeaponAssets/Tools -- pulando.", tostring(weaponName)))
			continue
		end

		local position = scatterPoint(anchors, rng)
		if not position then
			continue
		end

		local tool = template:Clone()
		-- lifetime nil: arma do MAPA fica até alguém pegar.
		DropItemSystem.PlaceInWorld(tool, CFrame.new(position), folder, nil)
		placedWeapons += 1
	end

	-- Caixas de munição
	local placedAmmo = 0
	for _ = 1, spawns.AmmoBoxes do
		local position = scatterPoint(anchors, rng)
		if position then
			AmmoSystem.CreatePickup(position, GameConfig.Firearms.DefaultAmmoType, nil, folder)
			placedAmmo += 1
		end
	end

	print(string.format(
		"[WeaponSpawner] %d arma(s) e %d caixa(s) de munição no chão (âncoras: %s).",
		placedWeapons,
		placedAmmo,
		source
	))
end

--[[
	Init()
	Gera uma vez no boot. Chame DEPOIS de AmmoSystem.Init() e
	DropItemSystem.Init().
]]
function WeaponSpawner.Init()
	WeaponSpawner.Generate()
end

return WeaponSpawner
