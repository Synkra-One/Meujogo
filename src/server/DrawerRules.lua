--!strict
--[[
	DrawerRules
	Regras puras das gavetas (sem Instance): se um item cabe numa gaveta e
	deitado em que posição, quais gavetas começam a rodada com algo dentro e
	qual raridade sai. server/DrawerSystem.lua aplica; tests/drawer_rules.luau
	prova.
]]

local DrawerRules = {}

--[[
	FitOrientation(itemSize, interior) -> (cabe, ordem)
	itemSize = caixa do item nos eixos do Handle; interior = (largura,
	altura, profundidade) úteis da gaveta. `ordem[k]` = eixo do item (1 = X,
	2 = Y, 3 = Z) que vai no eixo k da gaveta (1 = largura, 2 = altura,
	3 = profundidade). O item deita: maior lado na largura, menor na altura;
	se o maior só couber na profundidade, tenta essa também.
]]
function DrawerRules.FitOrientation(size: Vector3, interior: Vector3): (boolean, { number })
	local dims = { size.X, size.Y, size.Z }
	local idx = { 1, 2, 3 }
	table.sort(idx, function(a, b)
		return dims[a] > dims[b]
	end)
	local largest, middle, smallest = idx[1], idx[2], idx[3]
	local flat = { largest, smallest, middle }
	if dims[largest] <= interior.X and dims[smallest] <= interior.Y and dims[middle] <= interior.Z then
		return true, flat
	end
	local deep = { middle, smallest, largest }
	if dims[middle] <= interior.X and dims[smallest] <= interior.Y and dims[largest] <= interior.Z then
		return true, deep
	end
	return false, flat
end

--[[
	ChooseLoot(total, min, max, rng) -> { índice }
	Quantidade aleatória por casa, limitada às gavetas existentes, sem repetição.
]]
function DrawerRules.ChooseLoot(total: number, min: number, max: number, rng: Random): { number }
	if total <= 0 then return {} end
	local count = rng:NextInteger(math.min(min, total), math.min(max, total))
	local pool = table.create(total, 0)
	for i = 1, total do
		pool[i] = i
	end
	local picked = {}
	for i = 1, count do
		local j = rng:NextInteger(i, total)
		pool[i], pool[j] = pool[j], pool[i]
		table.insert(picked, pool[i])
	end
	return picked
end

--[[
	RollRarity(weights, rarityMul, rng) -> raridade?
	Mesmo critério das caixas de loot: "Comum" mantém o peso, as outras são
	multiplicadas pela Sorte de quem abriu. Ordem alfabética = sorteio
	reproduzível pra mesma seed.
]]
function DrawerRules.RollRarity(weights: { [string]: number }, rarityMul: number, rng: Random): string?
	local names = {}
	for name, weight in weights do
		if weight > 0 then
			table.insert(names, name)
		end
	end
	table.sort(names)
	local total = 0
	local scaled = {}
	for i, name in names do
		local w = weights[name]
		if name ~= "Comum" then
			w *= rarityMul
		end
		scaled[i] = w
		total += w
	end
	if total <= 0 then
		return nil
	end
	local pick = rng:NextNumber() * total
	for i, name in names do
		pick -= scaled[i]
		if pick <= 0 then
			return name
		end
	end
	return names[#names]
end

return DrawerRules
