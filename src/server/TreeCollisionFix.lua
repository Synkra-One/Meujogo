--!strict
--[[
	TreeCollisionFix

	Primeiro ajuste isolado: somente a variante Mesh_AlpTrees4.

	A colisao original dessa mesh ocupa parte da copa e forma uma parede
	invisivel longe do tronco. A tentativa anterior removia essa colisao, mas
	centralizava o cilindro substituto pelo GetBoundingBox da arvore inteira.
	Como a copa dessa variante e assimetrica, o centro da caixa nao coincide
	com o tronco e o cilindro tambem ficava deslocado.

	O asset tem uma MeshPart grande para a copa (MeshId 1668448780) e uma Part
	com SpecialMesh separada no eixo visual do tronco (MeshId 1668447688).
	Para esta variante, as meshes ficam sem colisao e um cilindro estreito e
	vertical e colocado na posicao dessa peca real do tronco. As demais
	variantes nao sao alteradas nesta etapa; depois do teste visual podemos
	expandir a mesma estrategia.
]]

local Workspace = game:GetService("Workspace")

local TreeCollisionFix = {}

local TARGET_MODEL_NAME = "mesh_alptrees4"
local TARGET_CANOPY_MESH_ID = "1668448780"
local TARGET_TRUNK_MESH_ID = "1668447688"
local TRUNK_COLLIDER_NAME = "ColisorDoTronco"

local function normalizeContentId(contentId: string): string
	local numericId = string.match(contentId, "%d+")
	return numericId or contentId
end

local function specialMeshOf(part: BasePart): SpecialMesh?
	local mesh = part:FindFirstChildWhichIsA("SpecialMesh")
	return if mesh and mesh:IsA("SpecialMesh") then mesh else nil
end

local function isTargetPart(part: BasePart): boolean
	if part:IsA("MeshPart") and normalizeContentId(part.MeshId) == TARGET_CANOPY_MESH_ID then
		return true
	end
	local mesh = specialMeshOf(part)
	return mesh ~= nil and normalizeContentId(mesh.MeshId) == TARGET_TRUNK_MESH_ID
end

local function isTargetTree(tree: Instance): boolean
	if string.lower(tree.Name) == TARGET_MODEL_NAME then return true end
	if tree:IsA("BasePart") and isTargetPart(tree) then return true end
	for _, descendant in tree:GetDescendants() do
		if descendant:IsA("BasePart") and isTargetPart(descendant) then
			return true
		end
	end
	return false
end

local function bounds(tree: Instance): (CFrame?, Vector3?)
	if tree:IsA("Model") then
		return tree:GetBoundingBox()
	end
	if tree:IsA("BasePart") then
		return tree.CFrame, tree.Size
	end
	local part = tree:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part.CFrame, part.Size
	end
	return nil, nil
end

local function findTrunkVisualPosition(tree: Instance, fallback: Vector3): Vector3
	-- No asset original, esta peca fica no eixo do tronco e a MeshPart grande
	-- fica cerca de 4.3 studs deslocada. O nome da Part e apenas "Mesh", por
	-- isso a identificacao precisa usar o MeshId do SpecialMesh.
	if tree:IsA("BasePart") then
		local ownMesh = specialMeshOf(tree)
		if ownMesh and normalizeContentId(ownMesh.MeshId) == TARGET_TRUNK_MESH_ID then
			return tree.Position
		end
	end
	for _, descendant in tree:GetDescendants() do
		if descendant:IsA("BasePart") then
			local mesh = specialMeshOf(descendant)
			if mesh and normalizeContentId(mesh.MeshId) == TARGET_TRUNK_MESH_ID then
				return descendant.Position
			end
		end
	end
	return fallback
end

local function addTrunkCollider(tree: Instance): boolean
	-- Remove o cilindro antigo antes de medir: se ele veio salvo de uma versao
	-- anterior, nao pode contaminar o bounding box usado para achar o solo.
	local oldCollider = tree:FindFirstChild(TRUNK_COLLIDER_NAME)
	if oldCollider then
		oldCollider:Destroy()
	end

	local boundingCFrame, boundingSize = bounds(tree)
	if not boundingCFrame or not boundingSize then
		return false
	end

	local trunkPosition = findTrunkVisualPosition(tree, boundingCFrame.Position)
	local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2

	-- Escala pelo tamanho vertical, nao pela largura da copa. O teto de 2.4
	-- studs permite que um R6 chegue visualmente junto ao tronco sem atravessa-lo.
	local diameter = math.clamp(boundingSize.Y * 0.045, 1.6, 2.4)
	local height = math.clamp(boundingSize.Y * 0.46, 16, 30)
	local center = Vector3.new(trunkPosition.X, bottomY + height / 2, trunkPosition.Z)

	local collider = Instance.new("Part")
	collider.Name = TRUNK_COLLIDER_NAME
	collider.Shape = Enum.PartType.Cylinder
	-- O eixo de um Part cilindrico e X; esta rotacao o deixa vertical em Y.
	collider.Size = Vector3.new(height, diameter, diameter)
	collider.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	collider.Transparency = 1
	collider.Anchored = true
	collider.CanCollide = true
	collider.CanTouch = false
	collider.CanQuery = true
	collider.CastShadow = false
	collider:SetAttribute("VarianteDaArvore", "Mesh_AlpTrees4")
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

	local treesFixed = 0
	local partsFixed = 0
	local collidersCreated = 0
	for _, tree in floresta:GetChildren() do
		if isTargetTree(tree) then
			for _, descendant in tree:GetDescendants() do
				if descendant:IsA("BasePart")
					and descendant.Name ~= TRUNK_COLLIDER_NAME
					and descendant.CanCollide
				then
					descendant.CanCollide = false
					partsFixed += 1
				end
			end
			if addTrunkCollider(tree) then
				collidersCreated += 1
			end
			treesFixed += 1
			tree:SetAttribute("ColisaoDeArvoreCorrigida", true)
			tree:SetAttribute("VarianteDeColisao", "Mesh_AlpTrees4")
		end
	end

	return treesFixed, partsFixed, collidersCreated
end

function TreeCollisionFix.Init()
	local treesFixed, partsFixed, collidersCreated = TreeCollisionFix.Apply(nil)
	print(string.format(
		"[TreeCollisionFix] Mesh_AlpTrees4: %d arvore(s), %d mesh(es) sem colisao larga, %d colisor(es) centralizado(s).",
		treesFixed,
		partsFixed,
		collidersCreated
	))
end

return TreeCollisionFix
