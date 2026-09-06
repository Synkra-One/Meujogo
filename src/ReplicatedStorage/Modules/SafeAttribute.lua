--!strict
--[[
	SafeAttribute
	GetAttribute embrulhado em pcall.

	Instâncias vindas de InsertService:LoadAsset (Toolbox -- árvores, pedras,
	avião, Lanterna, Chocolate, Lança Ancestral) podem ter capacidades
	restritas que fazem GetAttribute lançar
	"cannot access 'SerializationService' (lacking capability ...)" em vez
	de simplesmente devolver nil. Sem isso, um
	`for _, descendant in root:GetDescendants() do descendant:GetAttribute(...) end`
	quebra o LOOP INTEIRO (e o Init() do sistema todo) na primeira instância
	problemática que encontrar -- e como a ilha agora tem centenas de
	descendentes vindos do Toolbox, isso já aconteceu de verdade (derrubou
	MonsterLightWeakness.Init() inteiro).

	Usado por todo `forEachTagged`/checagem de Tool do projeto que varre
	`game` ou `Workspace` inteiro: MonsterLightWeakness, RaftObjective,
	RadioObjective, SabotageSystem, WeaponSystem, UtilityItemSystem,
	ConfrontSystem.
]]

local SafeAttribute = {}

function SafeAttribute.Get(instance: Instance, name: string): any
	local ok, value = pcall(function()
		return instance:GetAttribute(name)
	end)
	if ok then
		return value
	end
	return nil
end

return SafeAttribute
