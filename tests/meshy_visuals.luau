--!nocheck
-- `sources` e injetado por run_meshy_visuals.py com os modulos reais.
-- Prova a logica de encaixe (MonsterMeshyVisuals) sobre um R6 escalado em 1.2x
-- com dubles do Roblox. NAO prova a aparencia: isso exige o Studio.

local stub = loadstring(sources.RobloxStub, "RobloxStub")()

local function load(name)
	local env = setmetatable({}, { __index = getfenv() })
	local chunk = assert(loadstring(sources[name], name))
	setfenv(chunk, env)
	return chunk()
end

local Visuals = load("MonsterMeshyVisuals")
local AssetRegistry = load("AssetRegistry")
local AnimationConfig = load("MonsterAnimationConfig")
local config = AssetRegistry.Monstro_Modelo.Meshy

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FALHOU: " .. message)
	end
end
local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 1e-4)
end
local function nearV(a, b)
	return (a - b).Magnitude < 1e-4
end
-- O stub nao resolve instance.Nome; sempre por FindFirstChild.
local function C(instance, name)
	return instance:FindFirstChild(name)
end

--------------------------------------------------------------------------------
-- Fabricas
--------------------------------------------------------------------------------
local ServerStorage = game:GetService("ServerStorage")

-- R6 "StarterCharacter" no tamanho `k` (1.2 = depois do ScaleTo do AppearanceManager).
local function makeCharacter(k)
	local character = Instance.new("Model")
	character.Name = "Monstro"
	local function part(name, size, x, y, transparency, collide)
		local p = Instance.new("Part", character)
		p.Name = name
		p.Size = size * k
		p.CFrame = CFrame.new(x * k, y * k, 0)
		p.Transparency = transparency
		p.CanCollide = collide
		return p
	end
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), 0, 3, 1, false)
	local torso = part("Torso", Vector3.new(2, 2, 1), 0, 3, 0, true)
	part("Head", Vector3.new(2, 1, 1), 0, 4.5, 0, true)
	part("Right Arm", Vector3.new(1, 2, 1), 1.5, 3, 0, false)
	part("Left Arm", Vector3.new(1, 2, 1), -1.5, 3, 0, false)
	part("Right Leg", Vector3.new(1, 2, 1), 0.5, 1, 0, false)
	part("Left Leg", Vector3.new(1, 2, 1), -0.5, 1, 0, false)
	local humanoid = Instance.new("Humanoid", character)
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = 0
	local function motor(parent, name, p0, p1, c0, c1)
		local m = Instance.new("Motor6D", parent)
		m.Name = name
		m.Part0 = character:FindFirstChild(p0)
		m.Part1 = character:FindFirstChild(p1)
		m.C0 = c0
		m.C1 = c1
	end
	motor(root, "RootJoint", "HumanoidRootPart", "Torso", CFrame.new(0, 0, 0), CFrame.new(0, 0, 0))
	motor(torso, "Neck", "Torso", "Head", CFrame.new(0, 1 * k, 0), CFrame.new(0, -0.5 * k, 0))
	motor(torso, "Right Shoulder", "Torso", "Right Arm", CFrame.new(1 * k, 0.5 * k, 0), CFrame.new(-0.5 * k, 0.5 * k, 0))
	motor(torso, "Left Shoulder", "Torso", "Left Arm", CFrame.new(-1 * k, 0.5 * k, 0), CFrame.new(0.5 * k, 0.5 * k, 0))
	motor(torso, "Right Hip", "Torso", "Right Leg", CFrame.new(1 * k, -1 * k, 0), CFrame.new(0.5 * k, 1 * k, 0))
	motor(torso, "Left Hip", "Torso", "Left Leg", CFrame.new(-1 * k, -1 * k, 0), CFrame.new(-0.5 * k, 1 * k, 0))
	return character
end

-- Tamanhos nativos do Meshy no rig de teste (studs).
local NATIVE = {
	Head = Vector3.new(1.031, 1.222, 1.043), Torso = Vector3.new(2.011, 1.858, 0.954),
	["Left Arm"] = Vector3.new(0.888, 2.082, 0.853), ["Right Arm"] = Vector3.new(0.907, 2.076, 0.853),
	["Left Leg"] = Vector3.new(1.034, 2.32, 0.851), ["Right Leg"] = Vector3.new(1.039, 2.314, 0.851),
}

local function installTemplate(missingMeshFor, without)
	local old = ServerStorage:FindFirstChild(config.TemplateName)
	if old then old:Destroy() end
	local template = Instance.new("Model", ServerStorage)
	template.Name = config.TemplateName
	for index, name in Visuals.PART_NAMES do
		if name ~= without then
			local mesh = Instance.new("MeshPart", template)
			mesh.Name = name
			mesh.MeshId = if name == missingMeshFor then "" else ("rbxassetid://" .. (1000 + index))
			mesh.Size = NATIVE[name]
			mesh.Anchored = true
			mesh.CanCollide = true
			mesh.Transparency = 0.5
			local surface = Instance.new("SurfaceAppearance", mesh)
			surface.ColorMap = "rbxassetid://2001"
			-- Lixo que NAO pode ir junto para o monstro:
			Instance.new("Motor6D", mesh).Name = "Extra"
			Instance.new("Attachment", mesh).Name = "Extra2"
			Instance.new("Script", mesh).Name = "Extra3"
		end
	end
	return template
end

local function visibleCount(character)
	local n = 0
	for _, name in Visuals.PART_NAMES do
		if C(character, name).Transparency == 0 then n += 1 end
	end
	return n
end

--------------------------------------------------------------------------------
-- 1) Caminho feliz no tamanho do jogo (1.2x)
--------------------------------------------------------------------------------
do
	installTemplate()
	local character = makeCharacter(1.2)
	local before = Visuals.RigSnapshot(character)
	local ok, reason = Visuals.Apply(character, config)
	check(ok, "Apply devia funcionar com template completo: " .. tostring(reason))

	local problems = Visuals.Verify(character, config)
	check(#problems == 0, "Verify: " .. table.concat(problems, "; "))

	local diff = Visuals.DiffSnapshots(before, Visuals.RigSnapshot(character))
	check(#diff == 0, "o rig mudou depois do Apply:\n" .. table.concat(diff, "\n"))

	local folder = character:FindFirstChild(Visuals.FOLDER_NAME)
	check(folder ~= nil and #folder:GetChildren() == 6, "esperava 6 visuais em MeshyVisuals")
	check(#character:GetChildren() == 9, "character so ganha a pasta MeshyVisuals (9 filhos), tem " .. #character:GetChildren())

	-- Encaixe numerico por peca (Size ATUAL da parte R6 * Fit).
	local expected = {
		Torso = Vector3.new(2.4, 2.4, 1.2), ["Left Arm"] = Vector3.new(1.2, 2.4, 1.2),
		["Right Arm"] = Vector3.new(1.2, 2.4, 1.2), ["Left Leg"] = Vector3.new(1.2, 2.4, 1.2),
		["Right Leg"] = Vector3.new(1.2, 2.4, 1.2), Head = Vector3.new(1.5, 1.5, 1.5),
	}
	for name, size in expected do
		local visual = folder:FindFirstChild(Visuals.VisualName(name))
		check(visual and nearV(visual.Size, size), name .. " visual com tamanho errado: " .. tostring(visual and visual.Size))
		check(visual and visual.MeshId == "rbxassetid://" .. (1000 + table.find(Visuals.PART_NAMES, name)), name .. " perdeu o MeshId")
		check(visual and visual:FindFirstChildOfClass("SurfaceAppearance") ~= nil, name .. " perdeu o SurfaceAppearance")
		check(visual and #visual:GetChildren() == 2, name .. " deve ter so SurfaceAppearance + weld, tem " .. tostring(visual and #visual:GetChildren()))
	end

	-- Cabeca apoiada no pescoco: base do visual == base da parte Head (y = 4.5*1.2 - 0.6).
	local head = C(character, "Head")
	local headVisual = C(folder, "MeshyHead")
	check(near(headVisual.CFrame.Position.Y - headVisual.Size.Y / 2, head.CFrame.Position.Y - head.Size.Y / 2),
		"a cabeca Meshy devia apoiar no pescoco (base igual a da parte Head)")
	check(near(headVisual.CFrame.Position.X, head.CFrame.Position.X) and near(headVisual.CFrame.Position.Z, head.CFrame.Position.Z),
		"cabeca Meshy centrada em X/Z")

	-- Nunca maior que o monstro: nenhum visual passa da caixa da parte + folga da cabeca.
	local totalTop = math.huge
	for _, name in Visuals.PART_NAMES do
		local v = folder:FindFirstChild(Visuals.VisualName(name))
		local b = character:FindFirstChild(name)
		check(v.Size.Y <= b.Size.Y * 1.25 + 1e-4 and v.Size.X <= b.Size.X * 1.25 + 1e-4, name .. " visual maior que a caixa do rig")
	end

	-- Nome do visual nunca colide com a assinatura R6 do validador de animacao.
	for _, child in folder:GetChildren() do
		check(not table.find(AnimationConfig.RequiredParts, child.Name), "visual com nome de parte R6: " .. child.Name)
	end
	local motors, parts = 0, 0
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then motors += 1 end
		if d:IsA("BasePart") and table.find(AnimationConfig.RequiredParts, d.Name) then parts += 1 end
	end
	check(motors == 6, "Motor6D devem continuar 6, tem " .. motors)
	check(parts == 7, "partes R6 (incl. HRP) devem continuar 7 sem duplicata, tem " .. parts)

	check(visibleCount(character) == 0, "as partes R6 originais devem ficar invisiveis")
	check(C(character, "HumanoidRootPart").Transparency == 1, "HRP continua transparente")

	-- Idempotencia: aplicar de novo nao duplica nem acumula.
	local ok2 = Visuals.Apply(character, config)
	check(ok2 and #C(character, Visuals.FOLDER_NAME):GetChildren() == 6, "reaplicar nao pode duplicar visuais")
	check(#character:GetChildren() == 9, "reaplicar nao pode deixar pastas sobrando")
	check(#Visuals.DiffSnapshots(before, Visuals.RigSnapshot(character)) == 0, "rig mudou depois de reaplicar")

	-- Clear devolve tudo como estava.
	Visuals.Clear(character)
	check(character:FindFirstChild(Visuals.FOLDER_NAME) == nil, "Clear remove a pasta")
	check(visibleCount(character) == 6, "Clear devolve a Transparency original das 6 partes")
	check(C(character, "Torso"):GetAttribute("MonsterMeshyOriginalTransparency") == nil, "Clear limpa o attribute")
	check(#Visuals.DiffSnapshots(before, Visuals.RigSnapshot(character)) == 0, "rig mudou depois do Clear")
end

--------------------------------------------------------------------------------
-- 2) Acompanha a escala: no tamanho 1.0 o visual e 1/1.2 do de 1.2x (nao "gigante")
--------------------------------------------------------------------------------
do
	installTemplate()
	local big, small = makeCharacter(1.2), makeCharacter(1.0)
	Visuals.Apply(big, config)
	Visuals.Apply(small, config)
	for _, name in Visuals.PART_NAMES do
		local a = C(C(big, Visuals.FOLDER_NAME), Visuals.VisualName(name)).Size
		local b = C(C(small, Visuals.FOLDER_NAME), Visuals.VisualName(name)).Size
		check(nearV(a, b * 1.2), name .. ": visual nao acompanha a escala do monstro")
	end
	check(nearV(C(C(small, Visuals.FOLDER_NAME), "MeshyTorso").Size, Vector3.new(2, 2, 1)), "no R6 padrao o torso Meshy = 2x2x1")
end

--------------------------------------------------------------------------------
-- 3) Ajuste individual: mexer numa entrada mexe so naquela peca
--------------------------------------------------------------------------------
do
	installTemplate()
	local character = makeCharacter(1.2)
	local tweaked = {
		Enabled = true, TemplateName = config.TemplateName, Parts = {},
	}
	for name, entry in config.Parts do tweaked.Parts[name] = entry end
	tweaked.Parts["Left Arm"] = { Fit = Vector3.new(1.1, 1, 1), Offset = Vector3.new(0, -0.1, 0) }
	Visuals.Apply(character, tweaked)
	local folder = C(character, Visuals.FOLDER_NAME)
	check(nearV(C(folder, "MeshyLeftArm").Size, Vector3.new(1.32, 2.4, 1.2)), "Fit da Left Arm")
	check(near(C(folder, "MeshyLeftArm").CFrame.Position.Y, C(character, "Left Arm").CFrame.Position.Y - 0.24), "Offset da Left Arm")
	check(nearV(C(folder, "MeshyRightArm").Size, Vector3.new(1.2, 2.4, 1.2)), "Right Arm nao pode ser afetado")
	check(#Visuals.Verify(character, tweaked) == 0, "Verify com config ajustada")
end

--------------------------------------------------------------------------------
-- 4) Falhas: nunca deixa o monstro meio invisivel
--------------------------------------------------------------------------------
do
	local function expectRefusal(label, character, cfg, needle)
		local ok, reason = Visuals.Apply(character, cfg or config)
		check(not ok, label .. ": devia recusar")
		check(type(reason) == "string" and reason:find(needle, 1, true) ~= nil, label .. ": motivo esperado '" .. needle .. "', veio " .. tostring(reason))
		check(visibleCount(character) == #Visuals.PART_NAMES or character:FindFirstChild("Left Leg") == nil, label .. ": nenhuma parte pode ficar escondida")
		check(character:FindFirstChild(Visuals.FOLDER_NAME) == nil, label .. ": nenhuma pasta criada")
	end

	installTemplate("Torso")
	expectRefusal("MeshId vazio", makeCharacter(1.2), nil, "sem MeshId")

	installTemplate(nil, "Head")
	expectRefusal("template sem peca", makeCharacter(1.2), nil, "sem MeshPart 'Head'")

	local existing = ServerStorage:FindFirstChild(config.TemplateName)
	existing:Destroy()
	expectRefusal("sem template", makeCharacter(1.2), nil, "não existe")

	installTemplate()
	local noLeg = makeCharacter(1.2)
	C(noLeg, "Left Leg"):Destroy()
	local ok, reason = Visuals.Apply(noLeg, config)
	check(not ok and reason:find("Left Leg", 1, true), "character sem Left Leg deve recusar")
	for _, name in { "Head", "Torso", "Left Arm", "Right Arm", "Right Leg" } do
		check(C(noLeg, name).Transparency == 0, "recusa nao pode esconder " .. name)
	end

	local disabled = { Enabled = false, TemplateName = config.TemplateName, Parts = config.Parts }
	expectRefusal("desativado", makeCharacter(1.2), disabled, "Enabled")

	-- Falha depois de sucesso: remove o que tinha sido aplicado.
	local character = makeCharacter(1.2)
	check(Visuals.Apply(character, config), "aplica antes")
	installTemplate("Head")
	local ok3 = Visuals.Apply(character, config)
	check(not ok3, "template quebrado depois deve recusar")
	check(character:FindFirstChild(Visuals.FOLDER_NAME) == nil and visibleCount(character) == 6,
		"recusa apos sucesso tem que restaurar o monstro anterior")
end

--------------------------------------------------------------------------------
-- 5) Configuracao real e integracao (texto dos arquivos reais)
--------------------------------------------------------------------------------
for _, name in Visuals.PART_NAMES do
	check(config.Parts[name] ~= nil and config.Parts[name].Fit ~= nil and config.Parts[name].Offset ~= nil,
		"AssetRegistry.Monstro_Modelo.Meshy.Parts sem entrada completa para " .. name)
end
check(AssetRegistry.Monstro_Modelo.ScaleMultiplier == 1.2, "escala do monstro nao pode mudar (1.2)")

local manager = sources.AppearanceManager
local scaleAt = manager:find("setMonsterR6Scale(character, humanoid, asset.ScaleMultiplier)", 1, true)
local applyAt = manager:find("MonsterMeshyVisuals.Apply(character", 1, true)
check(scaleAt and applyAt and scaleAt < applyAt, "AppearanceManager tem que aplicar o Meshy DEPOIS de escalar o monstro")
check(manager:find("MonsterMeshyVisuals.Clear(character)", 1, true), "ApplyAppearance tem que limpar o Meshy antes de reaplicar")
check(manager:find("RustyMachete", 1, true), "o facao continua no AppearanceManager")

-- O modulo nunca cria/edita juntas nem mexe no tamanho das partes R6.
local module = sources.MonsterMeshyVisuals
check(not module:find('Instance.new("Motor6D")', 1, true), "modulo nao pode criar Motor6D")
check(not module:find("%.C[01]%s*="), "modulo nao pode atribuir C0/C1")
check(not module:find("base%.Size%s*="), "modulo nao pode alterar Size da parte R6")
check(not module:find("Humanoid%.[%w]+%s*="), "modulo nao pode alterar o Humanoid")

if failures > 0 then
	error(string.format("%d falha(s) em meshy_visuals", failures), 0)
end
print("meshy_visuals: OK")
