--!strict
--[[
	AppearanceManager
	Aplica a aparência correspondente ao Role do jogador (Attribute "Role"
	no Player, definido por RoleAssignment) sempre que:
	  a) o Role muda (AssignRoles rodou), ou
	  b) o character spawna/respawna.
	Cobre os dois casos porque a ordem entre "papéis sorteados" e
	"character carregado" pode variar (ex: troca de Role no lobby, antes do
	primeiro spawn, ou respawn no meio da partida).

	Sobrevivente e Espiao: aparência humana normal, SEM nenhuma alteração
	-- de propósito, para não dar pista visual de quem é o Espião.

	Monstro: aparência de criatura. Os dados (cor, escala, e o MeshId do
	modelo real quando existir) vêm de AssetRegistry.Monstro_Modelo, não
	daqui -- este arquivo só sabe COMO aplicar, não O QUE aplicar.

	COMO TROCAR O PLACEHOLDER PELO MODELO REAL:
	Preencha AssetRegistry.Monstro_Modelo.MeshId com o rbxassetid do
	SpecialMesh. NADA neste arquivo precisa mudar -- applyMonsterAppearance
	já checa isso. Se o modelo real acabar exigindo uma abordagem diferente
	de "SpecialMesh no torso" (ex: substituir o character inteiro via
	HumanoidDescription, ou LoadCharacter com um rig customizado), aí sim
	essa função específica precisa ser reescrita -- mas o dispatch por Role
	e os listeners de spawn/attribute abaixo continuam iguais.

	Uso (chamar uma vez no boot do servidor):
		local AppearanceManager = require(script.AppearanceManager)
		AppearanceManager.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)
local LoadoutData = require(ReplicatedStorage.Modules.LoadoutData)

local AppearanceManager = {}

local function setHumanoidScale(humanoid: Humanoid, multiplier: number)
	-- Só R15 suporta escala; R6 ignora essas propriedades.
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end

	humanoid.HeadScale = multiplier
	humanoid.BodyDepthScale = multiplier
	humanoid.BodyHeightScale = multiplier
	humanoid.BodyWidthScale = multiplier
end

local function findTorso(character: Model): BasePart?
	return (character:FindFirstChild("UpperTorso") :: BasePart?) or (character:FindFirstChild("Torso") :: BasePart?)
end

-- Aplica um SpecialMesh real no torso (usado quando AssetRegistry já tem
-- um MeshId configurado).
local function applyMonsterMesh(torso: BasePart, meshId: string)
	local mesh = torso:FindFirstChildOfClass("SpecialMesh")
	if not mesh then
		mesh = Instance.new("SpecialMesh")
		mesh.Parent = torso
	end

	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = meshId
	torso.Color = Color3.new(1, 1, 1) -- a cor real vem da textura do mesh
end

local function applyMonsterAppearance(character: Model)
	local asset = AssetRegistry.Monstro_Modelo

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		setHumanoidScale(humanoid, asset.ScaleMultiplier)
	end

	local torso = findTorso(character)
	if not torso then
		return
	end

	if asset.MeshId ~= "" then
		applyMonsterMesh(torso, asset.MeshId)
	else
		-- Placeholder: sem modelo ainda, só cor.
		torso.Color = asset.Placeholder.TorsoColor
	end
end

-- Sobrevivente / Espiao: aparência humana padrão, nada a fazer.
local function applyDefaultAppearance(_character: Model) end

-- Dispatch por Role. Para adicionar um novo papel com aparência própria,
-- basta adicionar uma entrada aqui.
local roleAppearanceHandlers: { [string]: (Model) -> () } = {
	[GameConfig.Roles.Monster] = applyMonsterAppearance,
	[GameConfig.Roles.Survivor] = applyDefaultAppearance,
	[GameConfig.Roles.Spy] = applyDefaultAppearance,
}

--[[
	ApplyAppearance(player)
	Reaplica a aparência do character atual do jogador com base no Role
	que ele tem agora. Não faz nada se o jogador não tiver character ou
	Role definidos ainda.
]]
function AppearanceManager.ApplyAppearance(player: Player)
	local role = player:GetAttribute("Role")
	local character = player.Character
	if not character then
		return
	end

	local existing = character:FindFirstChild("LoadoutVest")
	if existing then existing:Destroy() end
	local skin = LoadoutData.GetSkin(player:GetAttribute("SkinId"))
	local torso = findTorso(character)
	if skin and skin.Color and torso and role ~= GameConfig.Roles.Monster then
		local vest = Instance.new("Part")
		vest.Name = "LoadoutVest"
		vest.Size = torso.Size * Vector3.new(1.04, 0.8, 1.12)
		vest.CFrame = torso.CFrame
		vest.Color = skin.Color
		vest.Material = Enum.Material.Fabric
		vest.CanCollide = false
		vest.CanTouch = false
		vest.CanQuery = false
		vest.Massless = true
		vest.Parent = character
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = vest
		weld.Parent = vest
	end
	local handler = if type(role) == "string" then roleAppearanceHandlers[role] else nil
	if handler then
		handler(character)
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		AppearanceManager.ApplyAppearance(player)
	end)
	player.CharacterAppearanceLoaded:Connect(function()
		AppearanceManager.ApplyAppearance(player)
	end)
	player:GetAttributeChangedSignal("SkinId"):Connect(function()
		AppearanceManager.ApplyAppearance(player)
	end)

	player:GetAttributeChangedSignal("Role"):Connect(function()
		AppearanceManager.ApplyAppearance(player)
	end)

	if player.Character then
		AppearanceManager.ApplyAppearance(player)
	end
end

--[[
	Init()
	Assina os eventos necessários para todo jogador presente e futuro.
	Chame uma vez no boot do servidor.
]]
function AppearanceManager.Init()
	Players.PlayerAdded:Connect(watchPlayer)

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return AppearanceManager
