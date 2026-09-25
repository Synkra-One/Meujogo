-- Mesmo módulo da cena, com geometria do stub existente. Não simula render,
-- streaming real ou animação: verifica aparência, marcadores e ciclo de vida.
do
	local env = setmetatable({}, { __index = getfenv() })
	local function execute(name)
		local chunk = assert(loadstring(sources[name], name))
		setfenv(chunk, env)
		return chunk()
	end
	local stub = execute("Stub")
	local newInstance = env.Instance.new
	env.Instance.new = function(class, parent)
		local item = newInstance(class, parent)
		item.Archivable = true
		item.ChildAdded, item.ChildRemoved, item.DescendantAdded = signal(), signal(), signal()
		item.signals = {}
		function item:GetPropertyChangedSignal(name)
			self.signals[name] = self.signals[name] or signal()
			return self.signals[name]
		end
		function item:WaitForChild(name) return self:FindFirstChild(name) end
		function item:IsDescendantOf(ancestor)
			return self.Parent == ancestor or (self.Parent and self.Parent:IsDescendantOf(ancestor)) or false
		end
		return item
	end
	env.Vector2 = environment.Vector2
	env.task = { delay = environment.task.delay, defer = function(callback) table.insert(pending, callback) end }
	env.script = { Parent = { MenuConfig = "MenuConfig" } }
	local cache = {}
	env.require = function(reference)
		local name = if type(reference) == "string" then reference else reference.Name
		if not cache[name] then cache[name] = execute(name) end
		return cache[name]
	end
	local storage = env.Instance.new("Folder")
	stub.Services.ReplicatedStorage = storage
	local workspace = stub.Workspace
	function workspace:WaitForChild(name) return self:FindFirstChild(name) end
	local function make(class, name, parent)
		local item = env.Instance.new(class)
		item.Name, item.Parent = name, parent
		return item
	end
	local config = env.require("MenuConfig")
	local master = make("Model", "MenuSceneSet", workspace)
	local marker = make("Model", "MonsterMarker", master)
	local guide = make("Part", "Torso", marker)
	guide.Size = env.Vector3.new(2, 6, 1)
	guide.CFrame = env.CFrame.new(config.Scene.Origin + env.Vector3.new(2, 3, -3))
	marker.PrimaryPart = guide
	local anchor = make("Part", "CameraAnchor", master)
	anchor.CFrame = env.CFrame.new(config.Scene.Origin + config.Scene.CameraOffset)
	make("Part", "CameraLookAt", master).CFrame = env.CFrame.new(config.Scene.Origin + config.Scene.CameraLookAt)
	local Scene = env.require("MenuScene")
	local scene = Scene.new()
	assert(scene.monster.Name == "MenuRafael" and scene.monster:GetAttribute("CharacterId") == "RafaelMonteiro")
	assert(guide.Parent == marker and marker.Parent == master, "ocultar não apaga o marcador")
	assert(guide.LocalTransparencyModifier == 1 and anchor.LocalTransparencyModifier == 1, "guias rosas invisíveis")
	local bounds, size = scene.monster:GetBoundingBox()
	near(bounds.Position.Y - size.Y / 2, config.Scene.Origin.Y, "Rafael encosta no chão do marcador")

	-- CharacterData chegando depois do menu: reconstrói com o perfil real.
	local moduleFolder = make("Folder", "Modules", storage)
	local dataModule = make("ModuleScript", "CharacterData", moduleFolder)
	storage.DescendantAdded:Fire(dataModule)
	flush()
	local profile = env.require("CharacterData").GetById("RafaelMonteiro")
	local shirt = scene.monster:FindFirstChild("Torso").Color
	near(shirt.R, profile.ShirtColor.R)
	near(shirt.G, profile.ShirtColor.G)
	near(shirt.B, profile.ShirtColor.B)

	-- Um template real replicado mais tarde substitui o R6 local, sem executar conteúdo.
	local assets = make("Folder", "SelectionAssets", storage)
	local previews = make("Folder", "PreviewModels", assets)
	local template = make("Model", "RafaelMonteiro", previews)
	local torso = make("Part", "Torso", template)
	make("Script", "UnsafeScript", template)
	make("Sound", "TemplateAudio", template)
	storage.DescendantAdded:Fire(template)
	flush()
	assert(scene.characterSource == template)
	assert(not scene.monster:FindFirstChild("UnsafeScript") and not scene.monster:FindFirstChild("TemplateAudio"))
	assert(template:FindFirstChild("UnsafeScript"), "limpeza atua só no clone")
	local clonePart = scene.monster:FindFirstChild("Torso")
	assert(clonePart.Anchored and not clonePart.CanCollide and not clonePart.CanQuery)

	-- Remover/recolocar o marcador segue funcionando com Rafael.
	marker.Parent = nil
	master.ChildRemoved:Fire(marker)
	assert(scene.monster == nil)
	marker.Parent = master
	master.ChildAdded:Fire(marker)
	assert(scene.monster ~= nil)
	Scene.Destroy(scene)
	storage.DescendantAdded:Fire(template)
	flush()
	assert(scene.destroyed and scene.monster == nil and scene.folder.Parent == nil)
	print("[Menu] Rafael, chegada tardia de assets, guias ocultos e limpeza passaram")
end
