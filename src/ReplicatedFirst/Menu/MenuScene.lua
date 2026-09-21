--!strict
--[[
	MenuScene
	Cenário 3D de fundo do menu. TOTALMENTE SEPARADO da lógica das telas: o
	MenuScreens só chama Show(), Hide() e Destroy(). Para trocar modelo,
	cenário, câmera ou animação você mexe AQUI e no MenuConfig.Scene, sem
	encostar em nenhuma tela.

	DUAS GARANTIAS IMPORTANTES:

	1. A versão POR CÓDIGO (sem Workspace.MenuSceneSet gerado) é TOTALMENTE
	   LOCAL: as Parts são criadas no cliente, dentro de uma pasta única,
	   longe da ilha (Config.Scene.Origin). Nenhum RemoteEvent é usado.

	2. NÃO ALTERA O LIGHTING GLOBAL. Escurecer o Lighting deixaria o gameplay
	   deste cliente escuro também. Em vez disso a cena é montada DENTRO de
	   uma caixa fechada e escura, iluminada só pelas luzes dela; o tratamento
	   de cor e o desfoque ficam presos à CÂMERA e somem com ela.

	O personagem do menu não é controlável: é um modelo clonado, sem Humanoid
	ativo, âncorado, sem colisão e sem consulta de raycast.

	EDITÁVEL NO EXPLORER, EM TEMPO REAL: se Workspace.MenuSceneSet existir
	(gerado uma vez por Tools/MenuSceneGenerator.lua), este arquivo usa
	aquela cena DIRETO -- sem clonar -- e fica ESCUTANDO mudanças nela
	enquanto o menu estiver aberto:

	  - Mover CameraAnchor/CameraLookAt reposiciona a câmera NA HORA,
	    mesmo com o Play já rodando (não precisa parar e recomeçar).
	  - Mover/girar MonsterMarker reposiciona o monstro na hora.
	  - APAGAR MonsterMarker remove o monstro da cena na hora; recriá-lo
	    (ou desfazer com Ctrl+Z) traz ele de volta.
	  - O resto (paredes, luzes, chuva, props) é conteúdo REAL do Workspace,
	    então mover/pintar/apagar qualquer peça já é instantâneo por conta
	    do próprio motor -- nenhum código watch é necessário pra isso.

	Por causa disso, o caminho "cena editável" NÃO é mais um clone privado
	por jogador: é a MESMA geometria compartilhada do Workspace (marcada
	Persistent pelo gerador, pra sempre replicar mesmo estando longe --
	ver MenuSceneGenerator.lua). Na prática ninguém chega perto dela durante
	uma partida de verdade, mas ela deixa de ser "invisível para os outros"
	no sentido estrito. Sem gerar a cena, tudo continua 100% local como
	antes (buildSet/buildWeather abaixo).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.MenuConfig)

local CFG = Config.Scene
local Scene = {}
Scene.__index = Scene

export type Controller = typeof(setmetatable({} :: {
	folder: Folder,
	monster: Model?,
	monsterBase: CFrame,
	camera: Camera?,
	colorCorrection: ColorCorrectionEffect?,
	blur: BlurEffect?,
	connection: RBXScriptConnection?,
	previousType: Enum.CameraType?,
	previousCFrame: CFrame?,
	previousFov: number?,
	previousSubject: Instance?,
	elapsed: number,
	active: boolean,
	animationTrack: AnimationTrack?,
	-- Base da câmera (sem a deriva/respiração, que é somada por cima em
	-- cameraFrame). Atualizado AO VIVO pelas conexões de watchHandBuiltSet
	-- quando a cena editável existe; senão fica fixo nos números da config.
	cameraBase: Vector3,
	lookAtBase: Vector3,
	-- CFrame de MonsterMarker, se a cena editável tiver um. nil = sem
	-- marcador -- na cena editável isso quer dizer "sem monstro"; na versão
	-- por código, cai nos números de MenuConfig.Scene.
	monsterAnchor: CFrame?,
	-- true quando a cena editável está em uso: aí a EXISTÊNCIA do
	-- MonsterMarker decide se tem monstro ou não. false = versão por
	-- código, que sempre mostra alguma coisa (rig real ou silhueta).
	requireMonsterMarker: boolean,
	-- Workspace.MenuSceneSet, guardado só pra registrar novos ouvintes
	-- quando peças são adicionadas depois (ChildAdded).
	masterSet: Instance?,
	liveConnections: { RBXScriptConnection },
	monsterMarkerConnection: RBXScriptConnection?,
}, Scene))

--------------------------------------------------------------------------------
-- Auxiliares de geometria
--------------------------------------------------------------------------------

local function decorate(part: BasePart)
	-- Nada da cena participa de física, colisão, toque ou raycast do jogo.
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function block(parent: Instance, name: string, cframe: CFrame, size: Vector3,
	color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name, part.Size, part.CFrame = name, size, cframe
	part.Color, part.Material = color, material
	decorate(part)
	part.Parent = parent
	return part
end

--------------------------------------------------------------------------------
-- CENÁRIO PROVISÓRIO (só usado quando Workspace.MenuSceneSet NÃO existe)
-- Troque livremente: chão, caixa escura, silhuetas ao fundo e um pedaço de
-- estrutura do aeroporto abandonado à esquerda.
--------------------------------------------------------------------------------

local function buildSet(self: Controller)
	local origin = CFG.Origin
	local size = CFG.SetSize
	local folder = self.folder

	-- Caixa fechada: é ela que faz a cena ser NOITE sem tocar no Lighting.
	local half = size / 2
	local wall = 4
	for _, data in {
		{ "Ceiling", CFrame.new(origin + Vector3.new(0, half.Y, 0)), Vector3.new(size.X, wall, size.Z) },
		{ "WallBack", CFrame.new(origin + Vector3.new(0, 0, -half.Z)), Vector3.new(size.X, size.Y, wall) },
		{ "WallFront", CFrame.new(origin + Vector3.new(0, 0, half.Z)), Vector3.new(size.X, size.Y, wall) },
		{ "WallLeft", CFrame.new(origin + Vector3.new(-half.X, 0, 0)), Vector3.new(wall, size.Y, size.Z) },
		{ "WallRight", CFrame.new(origin + Vector3.new(half.X, 0, 0)), Vector3.new(wall, size.Y, size.Z) },
	} do
		block(folder, data[1] :: string, data[2] :: CFrame, data[3] :: Vector3, CFG.SetColor, Enum.Material.SmoothPlastic)
	end

	-- Chão de areia/terra molhada.
	block(folder, "Floor", CFrame.new(origin - Vector3.new(0, 1, 0)),
		Vector3.new(size.X, 2, size.Z), CFG.FloorColor, CFG.FloorMaterial)

	-- Silhuetas ao fundo: troncos finos e altos, em duas fileiras, com uma
	-- variação determinística (mesma cena toda vez -- nada de sorteio).
	for index = 1, CFG.PropCount do
		local t = index / CFG.PropCount
		local x = -half.X * 0.75 + (size.X * 0.75) * t
		local z = -half.Z * 0.62 - (index % 3) * 7
		local height = 16 + ((index * 7) % 11)
		local lean = math.rad(((index * 13) % 9) - 4)
		block(folder, "Prop" .. index,
			CFrame.new(origin + Vector3.new(x, height / 2 - 1, z)) * CFrame.Angles(lean, index * 0.7, 0),
			Vector3.new(1.4 + (index % 3) * 0.4, height, 1.4), CFG.PropColor, Enum.Material.Wood)
	end

	-- Pedaço do aeroporto abandonado à esquerda (placeholder de cenário):
	-- uma parede baixa, um poste torto e a asa quebrada de um avião.
	block(folder, "HangarWall", CFrame.new(origin + Vector3.new(-16, 3, -9)),
		Vector3.new(14, 8, 1), Color3.fromRGB(28, 28, 30), Enum.Material.CorrodedMetal)
	block(folder, "Pole", CFrame.new(origin + Vector3.new(-9.5, 4.5, -6)) * CFrame.Angles(0, 0, math.rad(6)),
		Vector3.new(0.5, 11, 0.5), Color3.fromRGB(22, 22, 24), Enum.Material.Metal)
	block(folder, "BrokenWing", CFrame.new(origin + Vector3.new(-13, 0.6, 2)) * CFrame.Angles(0, math.rad(22), math.rad(-9)),
		Vector3.new(12, 0.6, 3.4), Color3.fromRGB(34, 34, 37), Enum.Material.DiamondPlate)

	-- LUZ PRINCIPAL: fria, alta e fraca -- a "lua" através do teto quebrado.
	local keyPart = block(folder, "KeyLight", CFrame.new(origin + Vector3.new(-6, 16, 6)),
		Vector3.new(1, 1, 1), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	keyPart.Transparency = 1
	local key = Instance.new("PointLight")
	key.Color, key.Brightness, key.Range = CFG.KeyLightColor, CFG.KeyLightBrightness, CFG.KeyLightRange
	key.Shadows = true
	key.Parent = keyPart

	-- CONTRALUZ vermelha atrás do monstro: é ela que desenha a silhueta.
	local rimPart = block(folder, "RimLight", CFrame.new(origin + CFG.MonsterOffset + Vector3.new(1.5, 5, -6)),
		Vector3.new(1, 1, 1), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	rimPart.Transparency = 1
	local rim = Instance.new("PointLight")
	rim.Color, rim.Brightness, rim.Range = CFG.RimLightColor, CFG.RimLightBrightness, CFG.RimLightRange
	rim.Shadows = false
	rim.Parent = rimPart
end

--------------------------------------------------------------------------------
-- CLIMA -- névoa, chuva e cinzas. Tudo em emissores presos a Parts invisíveis.
-- Só usado quando Workspace.MenuSceneSet NÃO existe.
--------------------------------------------------------------------------------

local function emitter(parent: BasePart, name: string): ParticleEmitter
	local particle = Instance.new("ParticleEmitter")
	particle.Name = name
	particle.Parent = parent
	return particle
end

local function buildWeather(self: Controller)
	local origin = CFG.Origin
	local folder = self.folder

	if CFG.Fog then
		local fogPart = block(folder, "FogVolume", CFrame.new(origin + Vector3.new(0, 2, -8)),
			Vector3.new(CFG.SetSize.X * 0.8, 6, CFG.SetSize.Z * 0.5),
			Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
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
		local rainPart = block(folder, "RainVolume", CFrame.new(origin + Vector3.new(0, 20, -6)),
			Vector3.new(CFG.SetSize.X * 0.7, 1, CFG.SetSize.Z * 0.5),
			Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
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
		local emberPart = block(folder, "EmberVolume", CFrame.new(origin + Vector3.new(2, 1, -10)),
			Vector3.new(30, 1, 18), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
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

--------------------------------------------------------------------------------
-- MONSTRO
-- Tenta clonar um modelo real (MenuConfig.Scene.MonsterSources). Se nenhum
-- existir, monta uma silhueta provisória -- assim a cena nunca fica vazia e
-- nenhum ID de asset precisa ser inventado.
--
-- spawnMonster/despawnMonster/poseMonster são usados tanto pela versão por
-- código (chamados uma vez) quanto pela cena editável (chamados de novo toda
-- vez que MonsterMarker aparece/desaparece/se move, em tempo real).
--------------------------------------------------------------------------------

local function findByPath(path: string): Instance?
	local parts = string.split(path, "/")
	local root: Instance? = if parts[1] == "Workspace" then Workspace
		elseif parts[1] == "ReplicatedStorage" then ReplicatedStorage
		else nil
	if not root then return nil end
	for index = 2, #parts do
		root = (root :: Instance):FindFirstChild(parts[index])
		if not root then return nil end
	end
	return root
end

local function buildPlaceholderMonster(parent: Instance): Model
	-- Silhueta grosseira de propósito: ela existe só para a cena ter uma
	-- presença ameaçadora enquanto você não pluga o modelo de verdade.
	local model = Instance.new("Model")
	model.Name = "MenuMonsterPlaceholder"
	model.Parent = parent
	local skin = Color3.fromRGB(16, 16, 18)
	local torso = block(model, "Torso", CFrame.new(0, 3.1, 0), Vector3.new(2.2, 2.6, 1.2), skin, Enum.Material.Slate)
	block(model, "Head", CFrame.new(0, 4.9, 0), Vector3.new(1.2, 1.2, 1.2), skin, Enum.Material.Slate)
	block(model, "LeftArm", CFrame.new(-1.7, 3.0, 0.1) * CFrame.Angles(0, 0, math.rad(7)),
		Vector3.new(0.95, 2.9, 0.95), skin, Enum.Material.Slate)
	block(model, "RightArm", CFrame.new(1.7, 3.0, 0.1) * CFrame.Angles(0, 0, math.rad(-7)),
		Vector3.new(0.95, 2.9, 0.95), skin, Enum.Material.Slate)
	block(model, "LeftLeg", CFrame.new(-0.6, 0.9, 0), Vector3.new(1, 2.4, 1), skin, Enum.Material.Slate)
	block(model, "RightLeg", CFrame.new(0.6, 0.9, 0), Vector3.new(1, 2.4, 1), skin, Enum.Material.Slate)
	model.PrimaryPart = torso
	return model
end

local function prepareMonster(model: Model)
	-- Nada de Humanoid ativo: o modelo do menu não anda, não cai e não é
	-- controlável. Só a aparência interessa.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			decorate(descendant)
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			descendant.EvaluateStateMachine = false
			descendant.PlatformStand = true
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy() -- nenhum script do modelo roda no menu
		elseif descendant:IsA("ProximityPrompt") or descendant:IsA("ClickDetector") then
			descendant:Destroy()
		end
	end
end

-- Encosta os pés no chão: cada rig tem uma altura diferente entre o pivô e
-- os pés, então medimos a caixa delimitadora DEPOIS de posicionar e
-- corrigimos a altura para o fundo dela encostar exatamente em `floorTop`.
local function snapToFloor(monster: Model, base: CFrame, floorTop: number): CFrame
	local ok, boundsCFrame, boundsSize = pcall(function() return monster:GetBoundingBox() end)
	if not ok or not boundsCFrame then return base end
	local bottom = boundsCFrame.Position.Y - boundsSize.Y / 2
	local correction = floorTop - bottom
	if math.abs(correction) > 0.01 then
		return base + Vector3.new(0, correction, 0)
	end
	return base
end

local function poseMonster(self: Controller, base: CFrame)
	local monster = self.monster
	if not monster or not monster.PrimaryPart then return end
	monster:PivotTo(base)
	local floorTop = if self.monsterAnchor then (self.monsterAnchor :: CFrame).Position.Y else CFG.Origin.Y
	base = snapToFloor(monster, base, floorTop)
	monster:PivotTo(base)
	self.monsterBase = base
end

local function despawnMonster(self: Controller)
	if self.animationTrack then
		pcall(function() (self.animationTrack :: AnimationTrack):Stop() end)
		self.animationTrack = nil
	end
	if self.monster then
		self.monster:Destroy()
		self.monster = nil
	end
end

--[[
	spawnMonster(self)
	Chamado no início E toda vez que MonsterMarker aparece/some/muda na cena
	editável (tempo real). Na versão por código sempre mostra alguma coisa;
	na cena editável, requireMonsterMarker = true faz "sem marcador" virar
	"sem monstro" de propósito -- é exatamente o "se eu tiro o monstro ele
	tira o monstro" que a cena editável pede.
]]
local function spawnMonster(self: Controller)
	despawnMonster(self)
	if self.requireMonsterMarker and not self.monsterAnchor then
		return
	end

	local model: Model? = nil
	for _, path in CFG.MonsterSources do
		local found = findByPath(path)
		if found and found:IsA("Model") then
			local ok, clone = pcall(function() return found:Clone() end)
			if ok and clone then
				model = clone
				break
			end
		end
	end
	if model then
		model.Name = "MenuMonster"
		model.Parent = self.folder
		if not model.PrimaryPart then
			local candidate = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart", true)
			if candidate and candidate:IsA("BasePart") then model.PrimaryPart = candidate end
		end
	else
		-- SEM MODELO: entra a silhueta provisória. Ponha o caminho do seu
		-- modelo em MenuConfig.Scene.MonsterSources para substituí-la.
		model = buildPlaceholderMonster(self.folder)
	end
	local monster = model :: Model
	prepareMonster(monster)
	self.monster = monster
	if not monster.PrimaryPart then return end

	if CFG.MonsterScale ~= 1 then
		pcall(function() monster:ScaleTo(CFG.MonsterScale) end)
	end
	-- MonsterMarker (cena editável) vence quando existe; senão os números
	-- de MenuConfig.Scene, como antes.
	local base = self.monsterAnchor
		or (CFrame.new(CFG.Origin + CFG.MonsterOffset) * CFrame.Angles(0, math.rad(CFG.MonsterFacing), 0))
	poseMonster(self, base)

	-- ANIMAÇÃO REAL (opcional): se você puser um id em
	-- MenuConfig.Scene.MonsterAnimationId e o modelo tiver Humanoid/Animator,
	-- ela toca em loop e substitui a respiração procedural.
	local animationId = Config.AssetId(CFG.MonsterAnimationId)
	local humanoid = monster:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animationId and animator then
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		animation.Parent = monster
		local ok, track = pcall(function() return (animator :: Animator):LoadAnimation(animation) end)
		if ok and track then
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Idle
			track:Play()
			self.animationTrack = track
		end
	end
end

--------------------------------------------------------------------------------
-- CENA EDITÁVEL NO EXPLORER, AO VIVO
-- Se Tools/MenuSceneGenerator.lua já rodou, Workspace.MenuSceneSet existe.
-- Em vez de clonar, USAMOS a pasta real e ESCUTAMOS mudanças nela: mover uma
-- âncora, ou apagar/recriar MonsterMarker, reflete na hora, com o Play já
-- rodando -- sem precisar parar e recomeçar.
--------------------------------------------------------------------------------

local function bindPositionAnchor(self: Controller, anchor: Instance?, setter: (Vector3) -> ())
	if not (anchor and anchor:IsA("BasePart")) then return end
	local part = anchor :: BasePart
	local function apply()
		setter(part.Position)
	end
	apply()
	table.insert(self.liveConnections, part:GetPropertyChangedSignal("CFrame"):Connect(apply))
end

local function bindMonsterMarker(self: Controller, marker: Instance?)
	if self.monsterMarkerConnection then
		self.monsterMarkerConnection:Disconnect()
		self.monsterMarkerConnection = nil
	end
	if marker and marker:IsA("Model") and (marker :: Model).PrimaryPart then
		local model = marker :: Model
		self.monsterAnchor = model:GetPivot()
		self.monsterMarkerConnection = (model.PrimaryPart :: BasePart):GetPropertyChangedSignal("CFrame")
			:Connect(function()
				self.monsterAnchor = model:GetPivot()
				poseMonster(self, self.monsterAnchor :: CFrame)
			end)
	else
		self.monsterAnchor = nil
	end
end

local function watchHandBuiltSet(self: Controller, master: Instance)
	self.masterSet = master
	self.requireMonsterMarker = true

	bindPositionAnchor(self, master:FindFirstChild("CameraAnchor"), function(pos) self.cameraBase = pos end)
	bindPositionAnchor(self, master:FindFirstChild("CameraLookAt"), function(pos) self.lookAtBase = pos end)
	bindMonsterMarker(self, master:FindFirstChild("MonsterMarker"))

	-- Segurança no que já existe: qualquer Part ali ganha as mesmas travas
	-- do resto da cena -- nada pode colidir, tocar ou aparecer em raycast
	-- do jogo de verdade. decorate() não mexe em cor/material/transparência,
	-- então não estraga a aparência de edição das âncoras.
	for _, descendant in master:GetDescendants() do
		if descendant:IsA("BasePart") then
			decorate(descendant)
		end
	end

	-- E no que for adicionado/removido DEPOIS, ao vivo -- é isto que faz
	-- criar/apagar MonsterMarker (ou recolocar CameraAnchor) funcionar com
	-- o Play já rodando, sem reiniciar nada.
	table.insert(self.liveConnections, master.ChildAdded:Connect(function(child: Instance)
		if child.Name == "MonsterMarker" then
			bindMonsterMarker(self, child)
			spawnMonster(self)
		elseif child.Name == "CameraAnchor" then
			bindPositionAnchor(self, child, function(pos) self.cameraBase = pos end)
		elseif child.Name == "CameraLookAt" then
			bindPositionAnchor(self, child, function(pos) self.lookAtBase = pos end)
		elseif child:IsA("BasePart") then
			decorate(child)
		end
	end))
	table.insert(self.liveConnections, master.ChildRemoved:Connect(function(child: Instance)
		if child.Name == "MonsterMarker" then
			bindMonsterMarker(self, nil) -- monsterAnchor vira nil
			spawnMonster(self) -- requireMonsterMarker + sem âncora = despawn
		end
	end))
end

--------------------------------------------------------------------------------
-- CICLO DE VIDA
--------------------------------------------------------------------------------

function Scene.new(): Controller
	local folder = Instance.new("Folder")
	folder.Name = "MenuScene"
	-- Só no cliente: este Folder nunca sai desta máquina (mesmo quando a
	-- cena editável é usada, o monstro clonado e os efeitos moram aqui).
	folder.Parent = Workspace

	local self: Controller = setmetatable({
		folder = folder, monster = nil, monsterBase = CFrame.new(),
		camera = nil, colorCorrection = nil, blur = nil, connection = nil,
		previousType = nil, previousCFrame = nil, previousFov = nil, previousSubject = nil,
		elapsed = 0, active = false, animationTrack = nil,
		-- Padrão dos números da config; watchHandBuiltSet troca por âncoras
		-- reais (e passa a atualizar ao vivo) se Workspace.MenuSceneSet existir.
		cameraBase = CFG.Origin + CFG.CameraOffset,
		lookAtBase = CFG.Origin + CFG.CameraLookAt,
		monsterAnchor = nil,
		requireMonsterMarker = false,
		masterSet = nil,
		liveConnections = {},
		monsterMarkerConnection = nil,
	}, Scene)

	if not CFG.Enabled then return self end

	-- WaitForChild, NUNCA FindFirstChild: este script roda em ReplicatedFirst,
	-- o código mais cedo que existe no carregamento -- ele executa ANTES de
	-- o Workspace ter tido tempo de replicar do servidor pro cliente (bug
	-- real, já confirmado: nesse instante o cliente só tinha "Camera" e a
	-- própria pasta local no Workspace, nada mais). FindFirstChild olha só o
	-- que já chegou e desiste na hora; WaitForChild espera de verdade.
	-- 2s é de sobra pro replicar (é Persistent, chega cedo) e ainda cabe
	-- atrás da tela de carregamento padrão da Roblox, que só some depois.
	local master = Workspace:WaitForChild("MenuSceneSet", 2)

	-- Diagnóstico permanente e barato: diz no Output do CLIENTE, toda vez,
	-- exatamente qual cena está sendo usada. Se você editou
	-- Workspace.MenuSceneSet e o Play continua igual, a primeira pergunta é
	-- "apareceu a segunda linha (fallback) mesmo com a pasta existindo?" --
	-- se sim, o cliente não está recebendo a pasta, não é um problema de
	-- posição.
	if master then
		print(string.format("[MenuScene] Usando a cena editada em Workspace.MenuSceneSet (%s, %d peça(s)), ao vivo.",
			master.ClassName, #master:GetChildren()))
		watchHandBuiltSet(self, master)
	else
		-- Sem chute: lista TUDO que o cliente vê direto dentro de Workspace
		-- nesse instante, pra comparar com o Explorer sem precisar rodar mais
		-- nada na Command Bar.
		local names = {}
		for _, child in Workspace:GetChildren() do
			table.insert(names, child.Name)
		end
		print("[MenuScene] Workspace.MenuSceneSet NÃO encontrado no cliente -- usando a cena por código (MenuConfig.Scene).")
		print("[MenuScene] Filhos de Workspace vistos pelo cliente agora (" .. #names .. "): " .. table.concat(names, ", "))
		buildSet(self)
		buildWeather(self)
	end
	spawnMonster(self)
	return self
end

local function cameraFrame(self: Controller, time: number): CFrame
	-- Deriva lenta em duas frequências: nunca repete exatamente no mesmo
	-- ponto, então não parece um loop. self.cameraBase/lookAtBase já
	-- carregam a posição das âncoras (ao vivo) ou dos números da config.
	local driftX = math.sin(time * CFG.CameraDriftSpeed * math.pi * 2) * CFG.CameraDriftRadius
	local driftY = math.sin(time * CFG.CameraDriftSpeed * math.pi * 2 * 0.73) * CFG.CameraBreath
	local driftZ = math.cos(time * CFG.CameraDriftSpeed * math.pi * 2 * 0.41) * CFG.CameraDriftRadius * 0.5
	local position = self.cameraBase + Vector3.new(driftX, driftY, driftZ)
	return CFrame.lookAt(position, self.lookAtBase)
end

--[[
	Show(camera)
	Assume a câmera. Guarda o estado anterior INTEIRO (tipo, CFrame, FOV e
	sujeito) para devolver exatamente como estava quando o menu fechar --
	o Crouching continua sendo o dono do FieldOfView durante o jogo.
]]
function Scene.Show(self: Controller, camera: Camera)
	if self.active or not CFG.Enabled then return end
	self.active = true
	self.camera = camera
	self.previousType = camera.CameraType
	self.previousCFrame = camera.CFrame
	self.previousFov = camera.FieldOfView
	self.previousSubject = camera.CameraSubject

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = CFG.CameraFieldOfView
	camera.CFrame = cameraFrame(self, 0)

	-- Tratamento de cor e desfoque PRESOS À CÂMERA: são locais, não tocam no
	-- Lighting compartilhado e morrem junto com a cena.
	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "MenuColor"
	color.TintColor, color.Contrast = CFG.ColorTint, CFG.ColorContrast
	color.Saturation, color.Brightness = CFG.ColorSaturation, CFG.ColorBrightness
	color.Parent = camera
	self.colorCorrection = color

	local blur = Instance.new("BlurEffect")
	blur.Name, blur.Size = "MenuBlur", CFG.BlurSize
	blur.Parent = camera
	self.blur = blur

	self.connection = RunService.RenderStepped:Connect(function(dt: number)
		self.elapsed += dt
		-- O respawn devolve a câmera para Custom e pode até TROCAR a
		-- CurrentCamera. Enquanto a cena está ativa ela reassume as duas
		-- coisas todo frame -- senão o menu "cai" no lobby ao nascer.
		local current = Workspace.CurrentCamera
		if current and current ~= self.camera then
			local effects = { self.colorCorrection, self.blur }
			for _, effect in effects do
				if effect then effect.Parent = current end
			end
			self.camera = current
		end
		local camera = self.camera
		if camera then
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Scriptable
			end
			if camera.FieldOfView ~= CFG.CameraFieldOfView then
				camera.FieldOfView = CFG.CameraFieldOfView
			end
			camera.CFrame = cameraFrame(self, self.elapsed)
		end
		-- Respiração procedural: só quando não há animação de verdade.
		local monster = self.monster
		if monster and monster.PrimaryPart and not self.animationTrack then
			local breath = math.sin(self.elapsed * CFG.BreathSpeed * math.pi * 2) * CFG.BreathHeight
			local sway = math.sin(self.elapsed * CFG.SwaySpeed * math.pi * 2) * math.rad(CFG.SwayDegrees)
			monster:PivotTo(self.monsterBase * CFrame.new(0, breath, 0) * CFrame.Angles(0, sway, sway * 0.35))
		end
	end)
end

-- Desfoque de fundo some quando a cena "entra em foco" (depois do clique).
function Scene.Focus(self: Controller, blurSize: number, seconds: number)
	local blur = self.blur
	if not blur then return end
	local tween = game:GetService("TweenService"):Create(blur,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = blurSize })
	tween:Play()
end

--[[
	Hide()
	Devolve a câmera ao jogo exatamente como estava. Chamado antes de o menu
	sair -- daí em diante quem manda na câmera são os sistemas do gameplay.
]]
function Scene.Hide(self: Controller)
	if not self.active then return end
	self.active = false
	if self.connection then self.connection:Disconnect(); self.connection = nil end
	if self.colorCorrection then self.colorCorrection:Destroy(); self.colorCorrection = nil end
	if self.blur then self.blur:Destroy(); self.blur = nil end
	local camera = self.camera
	if camera and camera.Parent then
		camera.CameraType = self.previousType or Enum.CameraType.Custom
		if self.previousFov then camera.FieldOfView = self.previousFov end
		if self.previousSubject then camera.CameraSubject = self.previousSubject end
		if self.previousCFrame then camera.CFrame = self.previousCFrame end
	end
	self.camera = nil
end

function Scene.Destroy(self: Controller)
	Scene.Hide(self)
	despawnMonster(self)
	if self.monsterMarkerConnection then
		self.monsterMarkerConnection:Disconnect()
		self.monsterMarkerConnection = nil
	end
	for _, connection in self.liveConnections do
		connection:Disconnect()
	end
	table.clear(self.liveConnections)
	self.folder:Destroy()
end

return Scene
