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

local ORIGINAL_SCALE_ATTRIBUTE = "MonsterR6OriginalScale"
local ORIGINAL_HIP_HEIGHT_ATTRIBUTE = "MonsterR6OriginalHipHeight"
local ACTIVE_SCALE_ATTRIBUTE = "MonsterScaleMultiplier"
local SCALE_EPSILON = 1e-4

local function findTorso(character: Model): BasePart?
	return (character:FindFirstChild("UpperTorso") :: BasePart?) or (character:FindFirstChild("Torso") :: BasePart?)
end

local function findPart(character: Model, name: string): BasePart?
	local part = character:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

-- Model:ScaleTo e a operacao correta para um rig R6: alem de redimensionar
-- as BaseParts, o engine escala os offsets posicionais de Motor6D/joints,
-- attachments e meshes de forma uniforme. Alterar Size parte por parte
-- separaria ombros, quadris, pescoco e RootJoint.
--
-- A escala e sempre calculada a partir do tamanho original deste spawn e
-- aplicada como valor absoluto. Assim CharacterAdded +
-- CharacterAppearanceLoaded + mudanca de Role podem chamar esta funcao sem
-- transformar 1.2x em 1.44x. Ao deixar de ser Monstro, somente um rig que
-- tenha sido escalado aqui volta ao tamanho que possuia antes.
local function setMonsterR6Scale(character: Model, humanoid: Humanoid, multiplier: number?)
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return
	end

	local originalScale = character:GetAttribute(ORIGINAL_SCALE_ATTRIBUTE)
	local originalHipHeight = character:GetAttribute(ORIGINAL_HIP_HEIGHT_ATTRIBUTE)

	if multiplier == nil then
		if type(originalScale) ~= "number" or type(originalHipHeight) ~= "number" then
			return -- Survivor novo: nunca foi tocado por este sistema.
		end
	else
		if type(originalScale) ~= "number" then
			originalScale = character:GetScale()
			character:SetAttribute(ORIGINAL_SCALE_ATTRIBUTE, originalScale)
		end
		if type(originalHipHeight) ~= "number" then
			originalHipHeight = humanoid.HipHeight
			character:SetAttribute(ORIGINAL_HIP_HEIGHT_ATTRIBUTE, originalHipHeight)
		end
	end

	local targetScale = originalScale :: number
	if multiplier ~= nil then
		targetScale *= multiplier
	end

	if math.abs(character:GetScale() - targetScale) > SCALE_EPSILON then
		-- O StarterCharacter tem PrimaryPart = HumanoidRootPart e o pivot fica
		-- nela. A correcao elimina deriva caso esse detalhe do template mude;
		-- ScaleTo preserva a rotacao do rig.
		local root = findPart(character, "HumanoidRootPart")
		local rootPosition = if root then root.Position else nil
		character:ScaleTo(targetScale)
		if root and rootPosition then
			local correction = rootPosition - root.Position
			if correction.Magnitude > SCALE_EPSILON then
				character:PivotTo(character:GetPivot() + correction)
			end
		end
	end

	-- R6 padrao usa HipHeight 0. Se o template ganhar um valor customizado,
	-- ele acompanha a mesma proporcao e os pes continuam apoiados no chao.
	local relativeScale = targetScale / (originalScale :: number)
	humanoid.HipHeight = (originalHipHeight :: number) * relativeScale
	character:SetAttribute(ACTIVE_SCALE_ATTRIBUTE, multiplier)
end

local function weldAccessory(name: string, part0: BasePart, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = part0.CFrame * offset
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Parent = parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function paintPart(character: Model, name: string, color: Color3, material: Enum.Material?)
	local part = findPart(character, name)
	if not part then return end
	part.Color = color
	if material then
		part.Material = material
	end
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
	local oldCosmetic = character:FindFirstChild("MonsterCosmetic")
	if oldCosmetic then oldCosmetic:Destroy() end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		setMonsterR6Scale(character, humanoid, asset.ScaleMultiplier)
		humanoid.DisplayName = "Jason"
	end

	local torso = findTorso(character)
	if not torso then
		return
	end

	paintPart(character, "Torso", Color3.fromRGB(24, 26, 24), Enum.Material.Fabric)
	paintPart(character, "Left Arm", Color3.fromRGB(42, 44, 42), Enum.Material.Fabric)
	paintPart(character, "Right Arm", Color3.fromRGB(42, 44, 42), Enum.Material.Fabric)
	paintPart(character, "Left Leg", Color3.fromRGB(19, 22, 25), Enum.Material.Fabric)
	paintPart(character, "Right Leg", Color3.fromRGB(19, 22, 25), Enum.Material.Fabric)
	paintPart(character, "Head", Color3.fromRGB(70, 63, 54), Enum.Material.SmoothPlastic)

	local head = findPart(character, "Head")
	local rightArm = findPart(character, "Right Arm")
	local cosmetic = Instance.new("Folder")
	cosmetic.Name = "MonsterCosmetic"
	cosmetic.Parent = character

	if head then
		local face = head:FindFirstChild("face")
		if face and face:IsA("Decal") then
			face.Transparency = 1
		end

		local mask = weldAccessory(
			"JasonMask",
			head,
			Vector3.new(head.Size.X * 0.9, head.Size.Y * 0.82, 0.12),
			CFrame.new(0, 0, -head.Size.Z * 0.52),
			Color3.fromRGB(218, 211, 188),
			Enum.Material.SmoothPlastic,
			cosmetic
		)
		local maskCorner = Instance.new("SpecialMesh")
		maskCorner.MeshType = Enum.MeshType.Brick
		maskCorner.Scale = Vector3.new(1, 1, 0.55)
		maskCorner.Parent = mask

		for index, x in { -0.18, 0.18 } do
			local eye = weldAccessory(
				"MaskEye" .. index,
				head,
				Vector3.new(0.16, 0.1, 0.04),
				CFrame.new(x, 0.12, -head.Size.Z * 0.59),
				Color3.fromRGB(10, 6, 5),
				Enum.Material.SmoothPlastic,
				cosmetic
			)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.new(1, 0.55, 0.35)
			mesh.Parent = eye
		end

		weldAccessory("MaskScratch", head, Vector3.new(0.04, 0.48, 0.035), CFrame.new(0.28, 0.02, -head.Size.Z * 0.61) * CFrame.Angles(0, 0, math.rad(-22)), Color3.fromRGB(125, 16, 12), Enum.Material.Neon, cosmetic)
	end

	weldAccessory("MonsterBelt", torso, Vector3.new(torso.Size.X * 1.08, 0.16, torso.Size.Z * 1.16), CFrame.new(0, -torso.Size.Y * 0.23, 0), Color3.fromRGB(18, 14, 10), Enum.Material.Fabric, cosmetic)
	weldAccessory("ChestGash", torso, Vector3.new(0.08, 0.75, 0.04), CFrame.new(0.34, 0.08, -torso.Size.Z * 0.54) * CFrame.Angles(0, 0, math.rad(24)), Color3.fromRGB(100, 7, 5), Enum.Material.Neon, cosmetic)

	if rightArm then
		weldAccessory(
			"RustyMachete",
			rightArm,
			Vector3.new(0.16, 1.45, 0.08),
			CFrame.new(0.26, -0.76, -0.38) * CFrame.Angles(math.rad(0), math.rad(0), math.rad(-12)),
			Color3.fromRGB(116, 116, 108),
			Enum.Material.Metal,
			cosmetic
		)
	end

	if asset.MeshId ~= "" then
		applyMonsterMesh(torso, asset.MeshId)
	else
		torso.Color = asset.Placeholder.TorsoColor:Lerp(Color3.fromRGB(24, 26, 24), 0.65)
	end
end

-- Survivor/Espiao novos nunca sao redimensionados. O reset abaixo so age no
-- raro caso de o Role mudar no mesmo Model que antes era o Monstro.
local function applyDefaultAppearance(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		setMonsterR6Scale(character, humanoid, nil)
	end
end

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
	local monsterCosmetic = character:FindFirstChild("MonsterCosmetic")
	if monsterCosmetic then monsterCosmetic:Destroy() end
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
