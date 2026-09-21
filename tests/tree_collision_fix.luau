--!nocheck
-- `sources` e injetado por run_tree_collision_fix.py com os modulos reais.

local stub = loadstring(sources.RobloxStub, "RobloxStub")()

local env = setmetatable({}, { __index = getfenv() })
local chunk = assert(loadstring(sources.TreeCollisionFix, "TreeCollisionFix"))
setfenv(chunk, env)
local Fix = chunk()

local forest = Instance.new("Folder")
forest.Name = "Floresta"

-- Simula Mesh_AlpTrees4 com a mesma estrutura do asset real: uma MeshPart
-- grande e colidível para a copa e uma Part com SpecialMesh no eixo visual
-- do tronco. O PrimaryPart é a copa, reproduzindo o pivô deslocado que não
-- pode ser usado como centro do novo colisor.
local targetTree = Instance.new("Model", forest)
targetTree.Name = "Arvore_1"

local mesh = Instance.new("MeshPart", targetTree)
mesh.Name = "MeshPart"
mesh.MeshId = "rbxassetid://1668448780"
mesh.Size = Vector3.new(24, 40, 20)
mesh.CFrame = CFrame.new(18, 20, 20)
mesh.CanCollide = true
targetTree.PrimaryPart = mesh

local trunkVisual = Instance.new("Part", targetTree)
trunkVisual.Name = "Mesh"
trunkVisual.Size = Vector3.new(0.4, 0.4, 0.4)
trunkVisual.CFrame = CFrame.new(10, 8, 20)
trunkVisual.CanCollide = false
local trunkMesh = Instance.new("SpecialMesh", trunkVisual)
trunkMesh.MeshId = "rbxassetid://1668447688"

-- Colisor errado salvo por uma versão anterior. Ele precisa ser removido
-- antes da nova medição para não deslocar nem aumentar o bounding box.
local stale = Instance.new("Part", targetTree)
stale.Name = "ColisorDoTronco"
stale.Size = Vector3.new(20, 20, 20)
stale.CFrame = CFrame.new(100, 10, 100)
stale.CanCollide = true

local otherTree = Instance.new("Model", forest)
otherTree.Name = "OutraVariante"
local otherMesh = Instance.new("MeshPart", otherTree)
otherMesh.Name = "Mesh_AlpTrees3"
otherMesh.MeshId = "rbxassetid://999999999"
otherMesh.Size = Vector3.new(20, 35, 20)
otherMesh.CFrame = CFrame.new(-30, 17.5, 0)
otherMesh.CanCollide = true

local trees, parts, colliders = Fix.Apply(forest)
assert(trees == 1, "somente Mesh_AlpTrees4 deve ser alterada")
assert(parts == 1, "somente a colisao visual do alvo deve ser desligada")
assert(colliders == 1, "a árvore alvo precisa de um colisor de tronco")
assert(mesh.CanCollide == false, "a colisao larga da mesh precisa ser removida")
assert(otherMesh.CanCollide == true, "outras variantes ainda nao devem ser alteradas")
assert(stale.Parent == nil, "o colisor antigo e deslocado precisa ser destruido")

local collider = targetTree:FindFirstChild("ColisorDoTronco")
assert(collider and collider.CanCollide, "o tronco substituto deve bloquear o personagem")
assert(collider.Transparency == 1 and collider.CanTouch == false and collider.CanQuery == true)
assert(math.abs(collider.Position.X - 10) < 0.001, "colisor deve usar o X da mesh visual do tronco")
assert(math.abs(collider.Position.Z - 20) < 0.001, "colisor deve usar o Z da mesh visual do tronco")
assert(collider.Size.Y <= 2.4 and collider.Size.Z <= 2.4, "tronco nao pode virar parede larga")
assert(collider.Size.Y >= 1.6 and collider.Size.Z >= 1.6, "tronco deve continuar solido")
assert(collider:GetAttribute("VarianteDaArvore") == "Mesh_AlpTrees4")

-- Rodar novamente representa cada novo Play no Studio. Não pode duplicar o
-- cilindro nem voltar a usar o colisor antigo.
local treesAgain, _, collidersAgain = Fix.Apply(forest)
assert(treesAgain == 1 and collidersAgain == 1)
local colliderCount = 0
for _, child in targetTree:GetChildren() do
	if child.Name == "ColisorDoTronco" then colliderCount += 1 end
end
assert(colliderCount == 1, "a correção deve ser idempotente")

print("PASS: Mesh_AlpTrees4 usa colisor estreito na mesh visual do tronco; outras variantes ficam intactas")
