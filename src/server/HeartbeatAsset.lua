--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local InsertService = game:GetService("InsertService")
local CFG = require(ReplicatedStorage.Modules.HeartbeatConfig)
local Asset = {}

function Asset.Init()
	-- Ponto manual: ServerStorage.HeartbeatHeart (Model/Part) do asset 1994009448.
	-- Publica só geometria inerte; scripts do catálogo nunca entram no DataModel.
	local source = ServerStorage:FindFirstChild(CFG.TemplateName)
	local loaded: Instance? = nil
	if not source then
		local ok, result = pcall(function() return InsertService:LoadAsset(CFG.ModelAssetId) end)
		if ok then source = result; loaded = result end
	end
	if not source then
		warn("[Heartbeat] Modelo indisponível; usando coração procedural. Insira o asset 1994009448 em ServerStorage." .. CFG.TemplateName)
		return
	end
	local clean = Instance.new("Model")
	clean.Name = CFG.TemplateName
	local candidates = source:GetDescendants()
	table.insert(candidates, source)
	for _, descendant in candidates do
		if descendant:IsA("BasePart") then
			local part = descendant:Clone()
			-- Apenas malha/textura; remove scripts, sons, constraints e emissores.
			for _, child in part:GetChildren() do
				if child:IsA("DataModelMesh") or child:IsA("SurfaceAppearance")
					or child:IsA("Decal") or child:IsA("Texture") then
					child:ClearAllChildren()
				else child:Destroy() end
			end
			part.Anchored = true
			part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
			part.Parent = clean
		end
	end
	if loaded then loaded:Destroy() end
	if #clean:GetChildren() == 0 then clean:Destroy(); warn("[Heartbeat] Modelo sem geometria; fallback ativo"); return end
	local folder = ReplicatedStorage:FindFirstChild(CFG.AssetsFolder)
	if not folder then folder = Instance.new("Folder"); folder.Name = CFG.AssetsFolder; folder.Parent = ReplicatedStorage end
	if folder:FindFirstChild(CFG.TemplateName) then clean:Destroy(); return end
	clean.Parent = folder -- template apenas, nunca um efeito no Workspace
end

return Asset
