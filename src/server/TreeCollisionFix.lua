--!strict
--[[
	TreeCollisionFix

	Arvore_597 e Arvore_428 usam duas variantes de mesh cuja colisao forma uma
	parede muito maior que o visual da arvore. Elas sao usadas varias vezes na
	ilha, por isso corrigir somente essas duas instancias nao basta.

	Em vez de depender da posicao ou do numero sequencial, usamos as duas
	arvores como amostras. Qualquer arvore que compartilhe uma das MeshIds dessas
	amostras fica com as meshes sem colisao e
	recebe um cilindro invisivel, estreito, somente no tronco. Assim a copa nao
	cria uma parede distante, mas o personagem ainda bate fisicamente na arvore.
]]

local Workspace = game:GetService("Workspace")

local TreeCollisionFix = {}

local REFERENCE_NAMES = {
	"Arvore_597",
	"Arvore_428",
}

local TRUNK_COLLIDER_NAME = "ColisorDoTronco"

local function normalizeContentId(contentId: string): string
	local numericId = string.match(contentId, "%d+")
	return numericId or contentId
end

local function meshIdOf(part: BasePart): string?
	if part:IsA("MeshPart") then
		return normalizeContentId(part.MeshId)
	end

	local mesh = part:FindFirstChildWhichIsA("SpecialMesh")
	if mesh and mesh.MeshId ~= "" then
		return normalizeContentId(mesh.MeshId)
	end

	return nil
end

local function collectMeshIds(model: Instance, destination: { [string]: boolean })
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local meshId = meshIdOf(descendant)
			if meshId and meshId ~= "" then
				destination[meshId] = true
			end
		end
	end
end

local function usesAnyMeshId(model: Instance, meshIds: { [string]: boolean }): boolean
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local meshId = meshIdOf(descendant)
			if meshId and meshIds[meshId] then
				return true
			end
		end
	end
	return false
end

local function findTrunk(tree: Instance): BasePart?
	for _, descendant in tree:GetDescendants() do
		if descendant:IsA("BasePart") then
			local lowerName = string.lower(descendant.Name)
			if string.find(lowerName, "trunk", 1, true)
				or string.find(lowerName, "tronco", 1, true)
				or string.find(lowerName, "stem", 1, true)
			then
				return descendant
			end
		end
	end
	return nil
end

local function bounds(tree: Instance): (CFrame?, Vector3?)
	if tree:IsA("Model") then
		return tree:GetBoundingBox()
	end

	local part = tree:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part.CFrame, part.Size
	end
	return nil, nil
end

local function addTrunkCollider(tree: Instance): boolean
	local oldCollider = tree:FindFirstChild(TRUNK_COLLIDER_NAME)
	if oldCollider then
		oldCollider:Destroy()
	end

	local boundingCFrame, boundingSize = bounds(tree)
	if not boundingCFrame or not boundingSize then
		return false
	end

	local trunk = findTrunk(tree)
	local trunkPosition = if trunk then trunk.Position else boundingCFrame.Position

	-- Usa a escala da arvore inteira, nao os eixos da MeshPart: algumas variantes
	-- importam o tronco rotacionado e Size.Y nao representa sua altura. O limite
	-- de 3.25 studs garante que o colisor nunca volte a ser uma parede distante.
	local diameter = math.clamp(math.min(boundingSize.X, boundingSize.Z) * 0.10, 1.75, 3.25)
	local height = math.clamp(boundingSize.Y * 0.54, 8, 34)
	local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
	local center = Vector3.new(trunkPosition.X, bottomY + height / 2, trunkPosition.Z)

	local collider = Instance.new("Part")
	collider.Name = TRUNK_COLLIDER_NAME
	collider.Shape = Enum.PartType.Cylinder
	-- O eixo do cilindro de Part e X; a rotacao o deixa vertical em Y.
	collider.Size = Vector3.new(height, diameter, diameter)
	collider.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	collider.Transparency = 1
	collider.Anchored = true
	collider.CanCollide = true
	collider.CanTouch = false
	collider.CanQuery = true
	collider.CastShadow = false
	collider.Parent = tree
	return true
end

function TreeCollisionFix.Apply(floresta: Instance?): (number, number, number)
	if not floresta then
		local ilha = Workspace:FindFirstChild("Ilha")
		floresta = if ilha then ilha:FindFirstChild("Floresta") else nil
	end
	if not floresta then
		return 0, 0, 0
	end

	local badMeshIds: { [string]: boolean } = {}
	for _, name in REFERENCE_NAMES do
		local reference = floresta:FindFirstChild(name)
		if reference then
			collectMeshIds(reference, badMeshIds)
		else
			warn(string.format("[TreeCollisionFix] Referencia %s nao encontrada em Workspace.Ilha.Floresta.", name))
		end
	end
	local idList = {}
	for meshId in badMeshIds do
		table.insert(idList, meshId)
	end
	table.sort(idList)
	if #idList == 0 then
		warn("[TreeCollisionFix] Nenhuma MeshId foi encontrada nas arvores de referencia.")
		return 0, 0, 0
	end
	print("[TreeCollisionFix] MeshIds problemáticas: " .. table.concat(idList, ", "))

	local treesFixed = 0
	local partsFixed = 0
	local collidersCreated = 0
	for _, tree in floresta:GetChildren() do
		if usesAnyMeshId(tree, badMeshIds) then
			for _, descendant in tree:GetDescendants() do
				if descendant:IsA("BasePart") and descendant.Name ~= TRUNK_COLLIDER_NAME and descendant.CanCollide then
					descendant.CanCollide = false
					partsFixed += 1
				end
			end
			if addTrunkCollider(tree) then
				collidersCreated += 1
			end
			treesFixed += 1
			tree:SetAttribute("ColisaoDeArvoreCorrigida", true)
		end
	end

	return treesFixed, partsFixed, collidersCreated
end

function TreeCollisionFix.Init()
	local treesFixed, partsFixed, collidersCreated = TreeCollisionFix.Apply(nil)
	print(string.format(
		"[TreeCollisionFix] %d arvore(s), %d mesh(es) sem colisao larga, %d colisor(es) de tronco.",
		treesFixed,
		partsFixed,
		collidersCreated
	))
end

return TreeCollisionFix
