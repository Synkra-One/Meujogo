--!strict
--[[
	MenuSceneGenerator (ferramenta de editor)

	Monta a CENA DE FUNDO do menu inicial como peças REAIS no Workspace, pra
	você poder arrastar tudo no Explorer (paredes, luzes, chuva, e as âncoras
	de câmera/monstro) em vez de digitar números em MenuConfig.lua.

	USO (Command Bar do Studio, em MODO DE EDIÇÃO, e salve com Ctrl+S depois):

		local Menu = require(game.ServerScriptService.Server.Tools.MenuSceneGenerator)
		Menu.Generate()                    -- só cria; RECUSA se já existir algo (protege suas edições)
		Menu.Generate({ Confirm = true })  -- apaga e refaz do zero, de propósito
		Menu.UpdateLighting()              -- só cor/luz, PRESERVA posições que você editou
		Menu.FixStreaming()                -- só corrige o tipo (Folder -> Model), PRESERVA tudo
		Menu.Clear()                       -- remove tudo

	SE VOCÊ JÁ GEROU A CENA ANTES desta versão: rode Menu.FixStreaming() uma
	vez (ver função abaixo). Sem isso, Workspace.StreamingEnabled = true faz
	o cliente nunca receber a cena durante o Play -- por estar tão longe de
	tudo, ela cai fora do raio de streaming -- e mover CameraAnchor/
	MonsterMarker parece "não fazer efeito" nenhum.

	ATENÇÃO: Generate() DESTRÓI Workspace.MenuSceneSet antes de refazer. Se
	você já mexeu nas posições à mão, elas vão junto -- rode só uma vez e
	depois edite livremente. Rodar de novo é só pra "resetar" a cena.

	COMO O MENU USA ISTO
	  src/ReplicatedFirst/Menu/MenuScene.lua procura Workspace.MenuSceneSet
	  toda vez que o menu abre e CLONA ele localmente -- cada jogador recebe
	  sua própria cópia, nada aqui é compartilhado nem visível para outros
	  jogadores durante o jogo. Se você NUNCA rodou este gerador, o menu cai
	  de volta sozinho na versão 100% por código que já existia -- nunca fica
	  sem cenário.

	MARCADORES DE EDIÇÃO (magenta, somem no jogo de verdade)
	  CameraAnchor   -- onde a câmera do menu fica (só a Position importa)
	  CameraLookAt   -- pra onde ela olha (só a Position importa)
	  MonsterMarker  -- um BONECO (torso/cabeça/braços/pernas, com uma seta
	                    apontando a frente), não uma bolinha -- selecione
	                    igual selecionaria um NPC, arraste com Move, gire com
	                    Rotate pra mudar a direção. É só um guia: o rig de
	                    verdade é clonado por cima na hora de jogar.
	Tudo fica direto na raiz de MenuSceneSet -- uma pasta só, sem subpastas
	-- pra você achar qualquer peça de primeira no Explorer.

	Tudo fica ancorado em MenuConfig.Scene.Origin -- longe da ilha e do lobby
	de propósito, pra nunca ser visto por acidente andando pelo mapa.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local S = require(script.Parent.Structures)
local MenuConfig = require(ReplicatedFirst:WaitForChild("Menu"):WaitForChild("MenuConfig"))

local MenuSceneGenerator = {}

local CFG = MenuConfig.Scene
local ANCHOR_COLOR = Color3.fromRGB(230, 40, 200)

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Decoração: sem colisão, sem toque, fora do raycast -- a cena inteira é só
-- pano de fundo, nunca deve interferir com nada do jogo real.
local DECO = { CanCollide = false, CastShadow = true }

local function deco(parent: Instance, name: string, size: Vector3, cf: CFrame, mat: Enum.Material, col: Color3): Part
	local p = S.Part(parent, name, size, cf, mat, col, DECO)
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function anchor(parent: Instance, name: string, cf: CFrame, size: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(size or 3, size or 3, size or 3)
	p.Shape = Enum.PartType.Ball
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Color = ANCHOR_COLOR
	p.Material = Enum.Material.Neon
	p.Transparency = 0.35
	p.Parent = parent
	return p
end

--[[
	monsterMarker(root, cf)
	Um BONECO de verdade (torso/cabeça/braços/pernas), não uma bolinha --
	você seleciona ele no Explorer igual selecionaria qualquer NPC do mapa,
	vê exatamente o tamanho/pose que o monstro vai ocupar, e arrasta com a
	ferramenta Move normal. Gire pelo eixo Y (Rotate) pra mudar a direção.
	É só um guia de edição: MenuScene.lua lê a posição dele e depois o
	descarta -- o monstro DE VERDADE (seu rig real) é clonado por cima na
	hora de jogar.
]]
local function monsterMarker(root: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "MonsterMarker"
	model.Parent = root
	local function limb(name: string, size: Vector3, offset: CFrame): Part
		local p = Instance.new("Part")
		p.Name, p.Size = name, size
		p.CFrame = cf * offset
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Color, p.Material, p.Transparency = ANCHOR_COLOR, Enum.Material.Neon, 0.35
		p.Parent = model
		return p
	end
	local torso = limb("Torso", Vector3.new(2.2, 2.6, 1.2), CFrame.new(0, 3.1, 0))
	limb("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 4.9, 0))
	limb("LeftArm", Vector3.new(0.95, 2.9, 0.95), CFrame.new(-1.7, 3.0, 0.1))
	limb("RightArm", Vector3.new(0.95, 2.9, 0.95), CFrame.new(1.7, 3.0, 0.1))
	limb("LeftLeg", Vector3.new(1, 2.4, 1), CFrame.new(-0.6, 0.9, 0))
	limb("RightLeg", Vector3.new(1, 2.4, 1), CFrame.new(0.6, 0.9, 0))
	-- Seta apontando pra FRENTE (-Z local), pra ficar óbvio qual lado é o
	-- rosto antes mesmo de girar a peça.
	limb("FacingArrow", Vector3.new(0.3, 0.3, 1.6), CFrame.new(0, 3.1, -1.4))
	model.PrimaryPart = torso
	return model
end

--------------------------------------------------------------------------------
-- CENÁRIO -- mesma geometria que MenuScene.lua já desenhava por código,
-- agora como peças reais.
--------------------------------------------------------------------------------

local function buildSet(root: Instance)
	local origin, size = CFG.Origin, CFG.SetSize
	local half = size / 2
	local wall = 4
	for _, data in {
		{ "Ceiling", CFrame.new(origin + Vector3.new(0, half.Y, 0)), Vector3.new(size.X, wall, size.Z) },
		{ "WallBack", CFrame.new(origin + Vector3.new(0, 0, -half.Z)), Vector3.new(size.X, size.Y, wall) },
		{ "WallFront", CFrame.new(origin + Vector3.new(0, 0, half.Z)), Vector3.new(size.X, size.Y, wall) },
		{ "WallLeft", CFrame.new(origin + Vector3.new(-half.X, 0, 0)), Vector3.new(wall, size.Y, size.Z) },
		{ "WallRight", CFrame.new(origin + Vector3.new(half.X, 0, 0)), Vector3.new(wall, size.Y, size.Z) },
	} do
		deco(root, data[1] :: string, data[3] :: Vector3, data[2] :: CFrame, Enum.Material.SmoothPlastic, CFG.SetColor)
	end

	deco(root, "Floor", Vector3.new(size.X, 2, size.Z), CFrame.new(origin - Vector3.new(0, 1, 0)),
		CFG.FloorMaterial, CFG.FloorColor)

	-- Tudo direto na raiz -- sem subpastas, pra achar qualquer peça num
	-- único lugar do Explorer.
	for index = 1, CFG.PropCount do
		local t = index / CFG.PropCount
		local x = -half.X * 0.75 + (size.X * 0.75) * t
		local z = -half.Z * 0.62 - (index % 3) * 7
		local height = 16 + ((index * 7) % 11)
		local lean = math.rad(((index * 13) % 9) - 4)
		deco(root, "Prop" .. index,
			Vector3.new(1.4 + (index % 3) * 0.4, height, 1.4),
			CFrame.new(origin + Vector3.new(x, height / 2 - 1, z)) * CFrame.Angles(lean, index * 0.7, 0),
			Enum.Material.Wood, CFG.PropColor)
	end

	deco(root, "HangarWall", Vector3.new(14, 8, 1), CFrame.new(origin + Vector3.new(-16, 3, -9)),
		Enum.Material.CorrodedMetal, Color3.fromRGB(28, 28, 30))
	deco(root, "Pole", Vector3.new(0.5, 11, 0.5),
		CFrame.new(origin + Vector3.new(-9.5, 4.5, -6)) * CFrame.Angles(0, 0, math.rad(6)),
		Enum.Material.Metal, Color3.fromRGB(22, 22, 24))
	deco(root, "BrokenWing", Vector3.new(12, 0.6, 3.4),
		CFrame.new(origin + Vector3.new(-13, 0.6, 2)) * CFrame.Angles(0, math.rad(22), math.rad(-9)),
		Enum.Material.DiamondPlate, Color3.fromRGB(34, 34, 37))
end

local function buildLighting(root: Instance)
	local origin = CFG.Origin
	local keyPart = deco(root, "KeyLight", Vector3.new(1, 1, 1), CFrame.new(origin + Vector3.new(-6, 16, 6)),
		Enum.Material.SmoothPlastic, Color3.new(0, 0, 0))
	keyPart.Transparency = 1
	local key = Instance.new("PointLight")
	key.Color, key.Brightness, key.Range, key.Shadows = CFG.KeyLightColor, CFG.KeyLightBrightness, CFG.KeyLightRange, true
	key.Parent = keyPart

	local rimPart = deco(root, "RimLight", Vector3.new(1, 1, 1),
		CFrame.new(origin + CFG.MonsterOffset + Vector3.new(1.5, 5, -6)),
		Enum.Material.SmoothPlastic, Color3.new(0, 0, 0))
	rimPart.Transparency = 1
	local rim = Instance.new("PointLight")
	rim.Color, rim.Brightness, rim.Range, rim.Shadows = CFG.RimLightColor, CFG.RimLightBrightness, CFG.RimLightRange, false
	rim.Parent = rimPart
end

local function emitter(parent: BasePart, name: string): ParticleEmitter
	local particle = Instance.new("ParticleEmitter")
	particle.Name = name
	particle.Parent = parent
	return particle
end

local function buildWeather(root: Instance)
	local origin = CFG.Origin

	if CFG.Fog then
		local fogPart = deco(root, "FogVolume", Vector3.new(CFG.SetSize.X * 0.8, 6, CFG.SetSize.Z * 0.5),
			CFrame.new(origin + Vector3.new(0, 2, -8)), Enum.Material.SmoothPlastic, Color3.new(0, 0, 0))
		fogPart.Transparency = 1
		local fog = emitter(fogPart, "Fog")
		fog.Texture = "rbxasset://textures/particles/smoke_main.dds"
		fog.Color = ColorSequence.new(Color3.fromRGB(120, 128, 140))
		fog.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.87),
			NumberSequenceKeypoint.new(1, 1) })
		fog.Size = NumberSequence.new(22, 34)
		fog.Lifetime = NumberRange.new(9, 15)
		fog.Rate = 7
		fog.Speed = NumberRange.new(0.5, 1.4)
		fog.SpreadAngle = Vector2.new(180, 180)
		fog.Rotation = NumberRange.new(0, 360)
		fog.RotSpeed = NumberRange.new(-4, 4)
		fog.EmissionDirection = Enum.NormalId.Front
		fog.LightInfluence = 1
		fog.ZOffset = -2
	end

	if CFG.Rain then
		local rainPart = deco(root, "RainVolume", Vector3.new(CFG.SetSize.X * 0.7, 1, CFG.SetSize.Z * 0.5),
			CFrame.new(origin + Vector3.new(0, 20, -6)), Enum.Material.SmoothPlastic, Color3.new(0, 0, 0))
		rainPart.Transparency = 1
		local rain = emitter(rainPart, "Rain")
		rain.Color = ColorSequence.new(Color3.fromRGB(150, 165, 185))
		rain.Transparency = NumberSequence.new(0.55)
		rain.Size = NumberSequence.new(0.06, 0.03)
		rain.Lifetime = NumberRange.new(1.1, 1.6)
		rain.Rate = 260
		rain.Speed = NumberRange.new(58, 74)
		rain.SpreadAngle = Vector2.new(4, 4)
		rain.EmissionDirection = Enum.NormalId.Bottom
		rain.Acceleration = Vector3.new(-3, -22, 0)
		rain.LightEmission = 0.25
		rain.LightInfluence = 0.6
	end

	if CFG.Embers then
		local emberPart = deco(root, "EmberVolume", Vector3.new(30, 1, 18),
			CFrame.new(origin + Vector3.new(2, 1, -10)), Enum.Material.SmoothPlastic, Color3.new(0, 0, 0))
		emberPart.Transparency = 1
		local embers = emitter(emberPart, "Embers")
		embers.Color = ColorSequence.new(Color3.fromRGB(190, 96, 52))
		embers.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.25),
			NumberSequenceKeypoint.new(1, 1) })
		embers.Size = NumberSequence.new(0.14, 0.05)
		embers.Lifetime = NumberRange.new(4, 7)
		embers.Rate = 9
		embers.Speed = NumberRange.new(1.5, 3.5)
		embers.SpreadAngle = Vector2.new(40, 40)
		embers.EmissionDirection = Enum.NormalId.Top
		embers.Acceleration = Vector3.new(1.2, 0.6, 0)
		embers.LightEmission = 1
	end
end

local function buildAnchors(root: Instance)
	local origin = CFG.Origin
	anchor(root, "CameraAnchor", CFrame.new(origin + CFG.CameraOffset))
	anchor(root, "CameraLookAt", CFrame.new(origin + CFG.CameraLookAt))
	monsterMarker(root, CFrame.new(origin + CFG.MonsterOffset) * CFrame.Angles(0, math.rad(CFG.MonsterFacing), 0))
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function MenuSceneGenerator.Clear()
	local existing = Workspace:FindFirstChild("MenuSceneSet")
	if existing then
		existing:Destroy()
	end
end

--[[
	UpdateLighting()
	Reaplica SÓ cor/luz (paredes, chão, props, as duas PointLight) usando os
	valores ATUAIS de MenuConfig.lua -- sem mexer em CameraAnchor,
	CameraLookAt, MonsterMarker nem em nada que você já posicionou à mão.
	Use isto depois de ajustar brilho/cor na config, em vez de Generate()
	(que apaga e refaz tudo do zero).
]]
function MenuSceneGenerator.UpdateLighting()
	local root = Workspace:FindFirstChild("MenuSceneSet")
	if not root then
		warn("[MenuSceneGenerator] Workspace.MenuSceneSet não existe -- rode Generate() primeiro.")
		return
	end

	local function setLight(partName: string, color: Color3, brightness: number, range: number)
		local part = root:FindFirstChild(partName)
		local light = part and (part :: Instance):FindFirstChildOfClass("PointLight")
		if light then
			light.Color, light.Brightness, light.Range = color, brightness, range
		end
	end
	setLight("KeyLight", CFG.KeyLightColor, CFG.KeyLightBrightness, CFG.KeyLightRange)
	setLight("RimLight", CFG.RimLightColor, CFG.RimLightBrightness, CFG.RimLightRange)

	local floor = root:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then floor.Color = CFG.FloorColor end
	for _, name in { "Ceiling", "WallBack", "WallFront", "WallLeft", "WallRight" } do
		local wallPart = root:FindFirstChild(name)
		if wallPart and wallPart:IsA("BasePart") then wallPart.Color = CFG.SetColor end
	end
	for _, child in root:GetChildren() do
		if child:IsA("BasePart") and string.match(child.Name, "^Prop%d+$") then
			child.Color = CFG.PropColor
		end
	end
	print("[MenuSceneGenerator] Cor/luz atualizadas -- posições preservadas.")
end

export type GenerateOptions = {
	-- Generate() DESTRÓI qualquer MenuSceneSet existente. Sem isto = true,
	-- se já existir alguma coisa lá, ele RECUSA e não apaga nada -- proteção
	-- contra rodar Generate() de novo sem querer e perder posições editadas
	-- à mão. Só passe true quando você quiser mesmo resetar tudo do zero.
	Confirm: boolean?,
}

function MenuSceneGenerator.Generate(options: GenerateOptions?): Model?
	local opts: GenerateOptions = options or {}
	local existing = Workspace:FindFirstChild("MenuSceneSet")
	if existing and opts.Confirm ~= true then
		warn(string.format(
			"[MenuSceneGenerator] Workspace.MenuSceneSet já existe (%d peças) -- Generate() APAGARIA suas posições editadas.",
			#existing:GetChildren()))
		warn("[MenuSceneGenerator] Só cor/luz? Menu.UpdateLighting(). Só streaming? Menu.FixStreaming().")
		warn("[MenuSceneGenerator] Tem certeza que quer apagar e recomeçar do zero? Menu.Generate({ Confirm = true })")
		return nil
	end
	MenuSceneGenerator.Clear()

	-- Model, não Folder: só Model aceita ModelStreamingMode. A cena fica de
	-- propósito longe de tudo (Origin), e Workspace.StreamingEnabled = true
	-- faria o cliente NUNCA receber essa pasta nessa distância -- Persistent
	-- diz pro motor "sempre replica isto, não importa onde o jogador esteja".
	local root = Instance.new("Model")
	root.Name = "MenuSceneSet"
	root:SetAttribute("Gerado", true)
	local streamOk, streamErr = pcall(function()
		root.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	if not streamOk then
		warn("[MenuSceneGenerator] Não consegui definir ModelStreamingMode: " .. tostring(streamErr))
		warn("[MenuSceneGenerator] A cena foi criada mesmo assim, mas pode não replicar pro cliente se ficar longe demais (StreamingEnabled).")
	end
	root.Parent = Workspace

	buildSet(root)
	buildLighting(root)
	buildWeather(root)
	buildAnchors(root)

	local parts = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then parts += 1 end
	end
	print(string.format(
		"[MenuSceneGenerator] Cena do menu montada em (%.0f, %.0f, %.0f) -- %d peças.",
		CFG.Origin.X, CFG.Origin.Y, CFG.Origin.Z, parts))
	print("[MenuSceneGenerator] Mova CameraAnchor, CameraLookAt e o boneco MonsterMarker à vontade no Explorer.")
	print("[MenuSceneGenerator] Salve o lugar (Ctrl+S) -- geometria gerada não volta pelo Rojo.")
	return root
end

--[[
	FixStreaming()
	Se você gerou a cena ANTES desta correção existir, Workspace.MenuSceneSet
	é uma Folder comum -- e por estar longe de tudo, com
	Workspace.StreamingEnabled = true, o cliente nunca recebe ela durante o
	Play (o motor só sincroniza o que está dentro do raio de streaming do
	jogador). É por isso que mover CameraAnchor/MonsterMarker "não fazia
	efeito": o script nem chegava a ver a sua edição.

	Isto converte a Folder existente pra Model + ModelStreamingMode
	Persistent SEM APAGAR NADA -- todas as posições que você já ajustou são
	preservadas. Rode uma vez só; depois disso Generate() já cria certo.
]]
function MenuSceneGenerator.FixStreaming()
	local existing = Workspace:FindFirstChild("MenuSceneSet")
	if not existing then
		warn("[MenuSceneGenerator] Workspace.MenuSceneSet não existe. Rode Generate() para criar a cena.")
		return
	end
	if existing:IsA("Model") then
		local ok, err = pcall(function()
			(existing :: Model).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		end)
		if ok then
			print("[MenuSceneGenerator] Já era um Model -- confirmei o modo de streaming Persistent.")
		else
			warn("[MenuSceneGenerator] Não consegui definir ModelStreamingMode: " .. tostring(err))
		end
		return
	end

	-- pcall em volta da parte que pode falhar (ModelStreamingMode), ANTES de
	-- mexer em `existing`: se algo der errado aqui, a pasta original com
	-- suas posições continua 100% intacta, nada é movido nem apagado.
	local model = Instance.new("Model")
	model.Name = "MenuSceneSetTemp" -- nome provisório: só vira "MenuSceneSet" no final, com tudo dentro
	model:SetAttribute("Gerado", true)
	local ok, err = pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	if not ok then
		model:Destroy()
		warn("[MenuSceneGenerator] Não consegui definir ModelStreamingMode: " .. tostring(err))
		warn("[MenuSceneGenerator] Nada foi alterado -- Workspace.MenuSceneSet (Folder) continua intacto.")
		return
	end

	local moved = 0
	for _, child in existing:GetChildren() do
		child.Parent = model
		moved += 1
	end
	model.Name = "MenuSceneSet"
	model.Parent = Workspace
	existing:Destroy()
	print(string.format("[MenuSceneGenerator] Convertido para Model persistente -- %d peça(s) preservada(s).", moved))
	print("[MenuSceneGenerator] Salve o lugar (Ctrl+S).")
end

return MenuSceneGenerator
