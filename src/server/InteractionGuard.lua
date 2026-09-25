--!strict
-- Autoridade de alcance/oclusao para itens e tasks. RequiresLineOfSight
-- cuida do prompt no cliente; esta checagem protege a acao no servidor.
local Workspace = game:GetService("Workspace")
local MatchStateService = require(script.Parent.MatchStateService)

local InteractionGuard = {}

-- `ignore`: instancias extras que nao contam como obstaculo (ex.: o corpo do
-- proprio gerador, cujo bocal/painel ficam encostados ou embutidos nele).
function InteractionGuard.CanReach(player: Player, target: BasePart, maxDistance: number, ignore: { Instance }?): boolean
	if not MatchStateService.IsGameplayEnabled(player) then return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0
		or not target:IsDescendantOf(Workspace) then return false end
	if (root.Position - target.Position).Magnitude > maxDistance then return false end

	local head = character:FindFirstChild("Head")
	local origin = if head and head:IsA("BasePart") then head.Position else root.Position
	local excluded: { Instance } = { character, target }
	-- Exclui somente o proprio item, nunca a construcao que o abriga.
	local tool = target:FindFirstAncestorOfClass("Tool")
	if tool then table.insert(excluded, tool) end
	if ignore then
		for _, instance in ignore do table.insert(excluded, instance) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true
	-- Vidro, portas e paredes solidas bloqueiam; fios/decoracoes sem colisao
	-- nao tornam os botoes do painel impossiveis de acessar.
	params.RespectCanCollide = true
	return Workspace:Raycast(origin, target.Position - origin, params) == nil
end

return InteractionGuard
