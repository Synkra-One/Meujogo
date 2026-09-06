--!strict
--[[
	AssetLoader
	Carrega um asset do Roblox (InsertService:LoadAsset, com fallback via
	game:GetObjects) e normaliza pra um único Model: remove qualquer Script/
	LocalScript/ModuleScript embutido (um free model pode trazer qualquer
	coisa junto -- isso impede que rode no seu jogo) e ancora as Parts.

	Cacheia por assetId -- chamadas repetidas devolvem o MESMO Model (quem
	usa deve :Clone() antes de mexer, pra não estragar o cache).

	Existe uma cópia quase idêntica desta lógica em Tools/IslandGenerator.lua
	(loadTemplate, local e não exportada) -- não refatorei aquele arquivo pra
	usar este módulo porque já está testado e funcionando; duplicar essa
	função pequena é mais seguro do que arriscar quebrar o gerador de ilha
	só por reuso. Este módulo é a versão pra quem precisar do carregamento
	fora do Tools/ (hoje: ToolFactory.lua, pra Lanterna e Chocolate).
]]

local InsertService = game:GetService("InsertService")

local AssetLoader = {}

local templates: { [number]: Model } = {}
local failedTemplates: { [number]: boolean } = {}

--[[
	Load(assetId)
	Devolve o Model cacheado (carregando na primeira vez), ou nil se o
	asset já falhou antes ou falhar agora. NÃO clona.
]]
function AssetLoader.Load(assetId: number): Model?
	if templates[assetId] then
		return templates[assetId]
	end
	if failedTemplates[assetId] then
		return nil
	end

	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or typeof(container) ~= "Instance" then
		ok, container = pcall(function()
			local objects = game:GetObjects("rbxassetid://" .. assetId)
			local holder = Instance.new("Model")
			for _, obj in objects do
				obj.Parent = holder
			end
			return holder
		end)
	end
	if not ok or typeof(container) ~= "Instance" then
		failedTemplates[assetId] = true
		warn(string.format("[AssetLoader] Não consegui carregar o asset %d: %s", assetId, tostring(container)))
		return nil
	end

	local holder = container :: Instance
	local children = holder:GetChildren()
	local model: Model
	if #children == 1 and children[1]:IsA("Model") then
		model = children[1]
	else
		model = Instance.new("Model")
		model.Name = "Asset_" .. assetId
		for _, child in children do
			child.Parent = model
		end
	end
	model.Parent = nil
	holder:Destroy()

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	if not model.PrimaryPart then
		local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			model.PrimaryPart = firstPart
		end
	end

	templates[assetId] = model
	return model
end

return AssetLoader
