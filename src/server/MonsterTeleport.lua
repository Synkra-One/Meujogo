--!strict
--[[
	MonsterTeleport
	Poder sobrenatural do Monstro: uma FENDA se abre nos pés dele, ele é
	engolido, e emerge de uma SEGUNDA fenda no destino. O servidor é a
	autoridade sobre ativação, destino, cooldown, posição final e estado; os
	clientes próximos só APRESENTAM as fendas (client/RiftVFXController +
	Modules/RiftVFX). Nada de efeito controlado pelo servidor frame a frame:
	a posição do rig usa TweenService nativo, e as fases usam task.wait.

	SEQUÊNCIA (tempos em GameConfig.Monster.Teleport):
	  ativação (server valida destino + inicia cooldown)
	  -> [OpeningRift]  fenda de entrada abre (RiftOpenDuration), monstro travado
	  -> [Entering]     monstro afunda + some (EnterDuration)
	  -> [Traveling]    "vazio" (TravelDuration). No meio: fecha a fenda de
	                    entrada e, DestRiftLeadTime antes do fim, a fenda do
	                    DESTINO começa a abrir -- antecipação pra quem está lá.
	  -> teleporte real (monstro já invisível e enterrado, ninguém vê o "pop")
	  -> [Exiting]      monstro emerge + reaparece (ExitDuration)
	  -> fecha a fenda do destino (RiftCloseDuration, assíncrono)
	  -> [Recovery]     tonto: sem atacar/reativar (PostTeleportRecovery)
	  -> [Idle]

	ESTADO (Attributes no CHARACTER, replicam sozinhos):
	  TeleportState : "OpeningRift"|"Entering"|"Traveling"|"Exiting"|"Recovery"
	                  (ausente/nil = Idle)
	  TeleportBusy  : true durante toda a habilidade
	    -> MonsterCombat.lua bloqueia o golpe enquanto TeleportBusy
	    -> client/MonsterTeleportController desliga o controle e faz a câmera
	    -> client/MovementWatchdog respeita (não "destrava" o boneco)

	RIG: R6. O HumanoidRootPart é ANCORADO e movido por TweenService; os
	membros seguem pelos Motor6D. Nenhuma animação é obrigatória -- o
	afundar+fade funciona em qualquer rig. Se você tiver animações R6
	próprias, cole os ids em GameConfig...Teleport.TeleportEnter/ExitAnimationId.

	ASSET DA FENDA: AssetRegistry.RiftTeleport.AssetId, carregado UMA vez aqui
	(InsertService só roda no servidor) e publicado em
	ReplicatedStorage.RiftAssets.Template pros clientes clonarem. Se falhar,
	o cliente monta uma fenda primitiva de reserva.

	Uso (uma vez no boot, DEPOIS de RoundManager.Init()):
		require(script.MonsterTeleport).Init()
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local InsertService = game:GetService("InsertService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)
local Elimination = require(script.Parent.Elimination)
local RoundManager = require(script.Parent.RoundManager)
local IslandLayout = require(script.Parent.Tools.IslandLayout)

local MonsterTeleport = {}

local CFG = GameConfig.Monster.Teleport

--------------------------------------------------------------------------------
-- Asset da fenda (carrega uma vez, publica pros clientes)
--------------------------------------------------------------------------------

local function normalizeModel(container: Instance): Model
	local children = container:GetChildren()
	local model: Model
	if #children == 1 and children[1]:IsA("Model") then
		model = children[1] :: Model
	else
		model = Instance.new("Model")
		for _, c in children do
			c.Parent = model
		end
	end
	model.Parent = nil
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
	return model
end

local function publishRiftAsset()
	local folder = ReplicatedStorage:FindFirstChild("RiftAssets")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "RiftAssets"
	folder.Parent = ReplicatedStorage

	local assetId = AssetRegistry.RiftTeleport.AssetId
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
		warn(string.format(
			"[MonsterTeleport] Asset da fenda %d não carregou (%s). O cliente vai usar a fenda de reserva.",
			assetId, tostring(container)
		))
		folder:SetAttribute("Loaded", false)
		return
	end

	local model = normalizeModel(container :: Instance)
	pcall(function()
		(container :: Instance):Destroy() -- sobra vazia depois do normalize
	end)
	local _, size = model:GetBoundingBox()

	-- Eixo "face": o MENOR lado é o que deita no chão (a menos que a config force).
	local faceAxis = CFG.RiftAssetFaceAxis
	if faceAxis == "auto" then
		local smallest = math.min(size.X, size.Y, size.Z)
		faceAxis = if smallest == size.Y then "Y" elseif smallest == size.Z then "Z" else "X"
	end
	local naturalWidth: number
	if faceAxis == "Y" then
		naturalWidth = math.max(size.X, size.Z)
	elseif faceAxis == "Z" then
		naturalWidth = math.max(size.X, size.Y)
	else
		naturalWidth = math.max(size.Y, size.Z)
	end

	model.Name = "Template"
	model:SetAttribute("FaceAxis", faceAxis)
	model:SetAttribute("NaturalWidth", naturalWidth)
	model.Parent = folder
	folder:SetAttribute("Loaded", true)

	print(string.format(
		"[MonsterTeleport] Fenda: asset %d carregado -- tamanho (%.1f, %.1f, %.1f), faceAxis=%s, largura natural %.1f.",
		assetId, size.X, size.Y, size.Z, faceAxis, naturalWidth
	))
end

--------------------------------------------------------------------------------
-- Helpers de mundo
--------------------------------------------------------------------------------

local function isMonster(player: Player): boolean
	return player:GetAttribute("Role") == GameConfig.Roles.Monster
end

local function livingMonster(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character or Elimination.IsEliminated(player) then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root :: BasePart
end

-- (Y do ponto mais baixo, Y do mais alto) do RIG em si -- ignora cosméticos
-- soldados (máscara, facão) que esticam a caixa e bagunçam o "assentar no chão".
local function isRigPart(part: BasePart): boolean
	if part:FindFirstAncestorOfClass("Accessory") then
		return false
	end
	local node: Instance? = part
	while node do
		if node.Name == "MonsterCosmetic" or node.Name == "LoadoutVest" then
			return false
		end
		node = node.Parent
	end
	return true
end

local function characterBounds(character: Model): (number, number)
	local minY, maxY = math.huge, -math.huge
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and isRigPart(d) then
			local cf, s = d.CFrame, d.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local extY = math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z
			minY = math.min(minY, cf.Position.Y - extY * 0.5)
			maxY = math.max(maxY, cf.Position.Y + extY * 0.5)
		end
	end
	if minY == math.huge then
		local p = character:GetPivot().Position
		return p.Y - 3, p.Y + 2
	end
	return minY, maxY
end

local function allCharacters(): { Instance }
	local list: { Instance } = {}
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	local elim = Workspace:FindFirstChild("Eliminados")
	if elim then
		table.insert(list, elim)
	end
	local rifts = Workspace:FindFirstChild("RiftVFX")
	if rifts then
		table.insert(list, rifts)
	end
	return list
end

--------------------------------------------------------------------------------
-- Validação do destino (servidor É a autoridade)
--------------------------------------------------------------------------------

-- Devolve (standCF, ok) ou (nil, motivo). standCF = onde o HumanoidRootPart
-- deve ficar (pés no chão), virado pra mesma direção que o monstro estava.
local function resolveDestination(monsterRoot: BasePart, hrpAboveFeet: number, rigScale: number, rawPoint: unknown): (CFrame?, string?)
	if typeof(rawPoint) ~= "Vector3" then
		return nil, "ponto inválido"
	end
	local point = rawPoint :: Vector3
	if point ~= point or point.Magnitude > 1e6 then
		return nil, "ponto inválido"
	end

	local origin = monsterRoot.Position
	local flat = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	local dist = flat.Magnitude
	if dist < 1 then
		return nil, "muito perto"
	end
	local clamped = math.clamp(dist, CFG.MinRange, CFG.MaxRange)
	local targetXZ = origin + flat.Unit * clamped

	local ignore = allCharacters()

	local downParams = RaycastParams.new()
	downParams.FilterType = Enum.RaycastFilterType.Exclude
	downParams.FilterDescendantsInstances = ignore
	downParams.IgnoreWater = true
	local from = Vector3.new(targetXZ.X, origin.Y + CFG.GroundSnapUp, targetXZ.Z)
	local hit = Workspace:Raycast(from, Vector3.new(0, -(CFG.GroundSnapUp + CFG.GroundSnapDown), 0), downParams)
	if not hit then
		return nil, "sem chão no destino"
	end
	local groundPos = hit.Position
	local normal = hit.Normal

	if normal.Y < CFG.MaxSlopeCos then
		return nil, "terreno muito inclinado"
	end

	local half = IslandLayout.AreaHalf() - CFG.BoundsMargin
	if math.abs(groundPos.X) > half or math.abs(groundPos.Z) > half then
		return nil, "fora dos limites do mapa"
	end
	if groundPos.Y < IslandLayout.CONFIG.SeaLevel + 1 then
		return nil, "destino na água"
	end

	-- Cabe o rig? A configuracao descreve um R6 de escala 1; a caixa acompanha
	-- o ScaleTo real do Monstro para nao aprovar um destino onde o corpo 1.2x
	-- atravessaria parede ou teto.
	local clearanceRadius = CFG.ClearanceRadius * rigScale
	local clearanceHeight = CFG.ClearanceHeight * rigScale
	local boxCenter = groundPos + Vector3.new(0, clearanceHeight / 2 + 0.3, 0)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	local overlapIgnore = table.clone(ignore)
	table.insert(overlapIgnore, Workspace.Terrain)
	overlap.FilterDescendantsInstances = overlapIgnore
	local parts = Workspace:GetPartBoundsInBox(
		CFrame.new(boxCenter),
		Vector3.new(clearanceRadius * 2, clearanceHeight, clearanceRadius * 2),
		overlap
	)
	for _, p in parts do
		if p.CanCollide then
			return nil, "espaço bloqueado no destino"
		end
	end

	-- Dentro de terreno / teto muito baixo? Raio pra cima tem que passar limpo.
	local upParams = RaycastParams.new()
	upParams.FilterType = Enum.RaycastFilterType.Exclude
	upParams.FilterDescendantsInstances = ignore
	upParams.IgnoreWater = true
	local upHit = Workspace:Raycast(groundPos + Vector3.new(0, 0.4, 0), Vector3.new(0, clearanceHeight, 0), upParams)
	if upHit then
		return nil, "teto baixo no destino"
	end

	local facing = monsterRoot.CFrame.LookVector * Vector3.new(1, 0, 1)
	facing = if facing.Magnitude > 0.1 then facing.Unit else Vector3.new(0, 0, 1)
	local hrpPos = groundPos + Vector3.new(0, hrpAboveFeet, 0)
	return CFrame.lookAt(hrpPos, hrpPos + facing), nil
end

--------------------------------------------------------------------------------
-- Broadcast de VFX (só pra quem está perto)
--------------------------------------------------------------------------------

local nextRiftId = 0

local function fireNear(position: Vector3, monster: Player, op: string, data: { [string]: any })
	local radiusSq = CFG.VFXBroadcastRadius * CFG.VFXBroadcastRadius
	for _, plr in Players:GetPlayers() do
		local send = plr == monster
		if not send then
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - position).Magnitude ^ 2 <= radiusSq then
				send = true
			end
		end
		if send then
			Remotes.RiftVFX:FireClient(plr, op, data)
		end
	end
end

--------------------------------------------------------------------------------
-- Sessão (só uma por vez -- só existe um Monstro)
--------------------------------------------------------------------------------

type Rift = { id: string, position: Vector3, cframe: CFrame, width: number, kind: string }
type Session = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	cancelled: boolean,
	origAutoRotate: boolean,
	origTransparency: { [BasePart]: number },
	tweens: { Tween },
	connections: { RBXScriptConnection },
	safetyThread: thread?,
	entrada: Rift?,
	destino: Rift?,
	enterAnim: AnimationTrack?,
}

local activeSession: Session? = nil
local lastUseAt: { [number]: number } = {} -- UserId -> os.clock()

local function newRift(session: Session, kind: string, cf: CFrame, width: number): Rift
	nextRiftId += 1
	local rift: Rift = {
		id = kind .. "_" .. nextRiftId,
		position = cf.Position,
		cframe = cf,
		width = width,
		kind = kind,
	}
	fireNear(rift.position, session.player, "open", {
		id = rift.id,
		cframe = cf,
		width = width,
		kind = kind,
	})
	return rift
end

local function riftOp(session: Session, rift: Rift?, op: string)
	if not rift then
		return
	end
	fireNear(rift.position, session.player, op, { id = rift.id })
end

local function trackTween(session: Session, tween: Tween)
	table.insert(session.tweens, tween)
	tween:Play()
end

local function cancelTweens(session: Session)
	for _, t in session.tweens do
		pcall(function()
			t:Cancel()
		end)
	end
	table.clear(session.tweens)
end

-- Coloca o HumanoidRootPart EXATAMENTE em targetCF, movendo o rig inteiro
-- (2 PivotTo: o 1º aproxima, o 2º corrige o resíduo -- funciona com ou sem
-- PrimaryPart definido no character).
local function placeRoot(character: Model, root: BasePart, targetCF: CFrame)
	character:PivotTo(targetCF)
	local err = targetCF.Position - root.Position
	if err.Magnitude > 0.01 then
		character:PivotTo(character:GetPivot() + err)
	end
end

-- Move o HRP ancorado com easing; os membros seguem pelos Motor6D.
local function tweenRoot(session: Session, targetCF: CFrame, duration: number, style: Enum.EasingStyle, dir: Enum.EasingDirection)
	trackTween(session, TweenService:Create(
		session.root,
		TweenInfo.new(math.max(duration, 0.05), style, dir),
		{ CFrame = targetCF }
	))
end

-- Fade de TODAS as BaseParts do character (um tween nativo por parte).
local function fadeCharacter(session: Session, alpha: number, duration: number, style: Enum.EasingStyle, dir: Enum.EasingDirection)
	local info = TweenInfo.new(math.max(duration, 0.05), style, dir)
	for part, orig in session.origTransparency do
		if part.Parent then
			local target = 1 - (1 - orig) * (1 - alpha)
			trackTween(session, TweenService:Create(part, info, { Transparency = target }))
		end
	end
end

local function playOptionalAnim(session: Session, animId: string): AnimationTrack?
	if animId == "" or animId == "rbxassetid://0" then
		return nil
	end
	local animator = session.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action4
		track:Play(0.15)
		return track
	end
	return nil
end

local function setState(session: Session, state: string?)
	session.character:SetAttribute("TeleportState", state)
	if state == nil then
		session.character:SetAttribute("TeleportBusy", nil)
	else
		session.character:SetAttribute("TeleportBusy", true)
	end
end

--------------------------------------------------------------------------------
-- Encerramento / restauração
--------------------------------------------------------------------------------

local function restoreMonster(session: Session)
	local character = session.character
	local humanoid = session.humanoid
	local root = session.root

	if not character.Parent or Elimination.IsEliminated(session.player) or humanoid.Health <= 0 then
		-- Eliminado/morto: quem cuida do corpo agora é o Elimination/Died.
		-- Só garante que o estado do teleporte saiu.
		character:SetAttribute("TeleportState", nil)
		character:SetAttribute("TeleportBusy", nil)
		return
	end

	-- Restaura transparência exata.
	for part, orig in session.origTransparency do
		if part.Parent then
			part.Transparency = orig
		end
	end

	-- Não deixa o monstro enterrado/no ar: assenta no chão sob a posição atual.
	local downParams = RaycastParams.new()
	downParams.FilterType = Enum.RaycastFilterType.Exclude
	downParams.FilterDescendantsInstances = allCharacters()
	downParams.IgnoreWater = true
	local pos = root.Position
	local hit = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -260, 0), downParams)
	if hit then
		local minY = select(1, characterBounds(character))
		local feetOffset = pos.Y - minY -- HRP acima dos pés
		local targetRootY = hit.Position.Y + feetOffset + 0.2
		placeRoot(character, root, root.CFrame - Vector3.new(0, pos.Y - targetRootY, 0))
	end

	root.Anchored = false
	humanoid.AutoRotate = session.origAutoRotate

	character:SetAttribute("TeleportState", nil)
	character:SetAttribute("TeleportBusy", nil)
end

local function endSession(session: Session)
	if session.safetyThread then
		pcall(task.cancel, session.safetyThread)
		session.safetyThread = nil
	end
	for _, c in session.connections do
		c:Disconnect()
	end
	table.clear(session.connections)
	if session.enterAnim then
		session.enterAnim:Stop(0.2)
	end
	if activeSession == session then
		activeSession = nil
	end
end

local function abortSession(session: Session, reason: string)
	if session.cancelled then
		return
	end
	session.cancelled = true
	warn(string.format("[MonsterTeleport] Teleporte abortado: %s", reason))

	cancelTweens(session)
	riftOp(session, session.entrada, "cancel")
	riftOp(session, session.destino, "cancel")
	Remotes.MonsterTeleport:FireClient(session.player, "cancel", reason)

	restoreMonster(session)
	endSession(session)
end

--------------------------------------------------------------------------------
-- Sequência
--------------------------------------------------------------------------------

local function checkAlive(session: Session): boolean
	if session.cancelled then
		return false
	end
	if not RoundManager.IsRoundActive() then
		abortSession(session, "partida terminou")
		return false
	end
	local character = session.character
	if not character.Parent or Elimination.IsEliminated(session.player) or session.humanoid.Health <= 0 then
		abortSession(session, "monstro morreu/eliminado")
		return false
	end
	return true
end

-- espera `t` segundos em pedaços, checando cancelamento
local function safeWait(session: Session, t: number): boolean
	local deadline = os.clock() + t
	while os.clock() < deadline do
		if not checkAlive(session) then
			return false
		end
		task.wait(math.min(0.1, deadline - os.clock()))
	end
	return not session.cancelled
end

local function runSequence(session: Session, destCF: CFrame)
	local character = session.character
	local humanoid = session.humanoid
	local root = session.root

	-- Medidas do rig (pra escalar a fenda e assentar no destino).
	local minY, maxY = characterBounds(character)
	local rigHeight = maxY - minY
	local hrpAboveFeet = root.Position.Y - minY
	local riftWidth = math.max(rigHeight * CFG.RiftWidthFactor * CFG.RiftScale, 3)

	-- Congela o monstro: HRP ancorado (não anda mesmo com o Crouching mexendo
	-- no WalkSpeed) + AutoRotate off. O controle de movimento em si o cliente
	-- desliga (ControlModule), e MovementWatchdog respeita TeleportBusy.
	session.origAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	root.Anchored = true

	-- Guarda a transparência original de cada parte.
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			session.origTransparency[d] = d.Transparency
		end
	end

	--------------------------------------------------------------------------
	-- 1) OpeningRift -- fenda de entrada
	--------------------------------------------------------------------------
	setState(session, "OpeningRift")
	local feetCF = root.CFrame - Vector3.new(0, hrpAboveFeet, 0)
	session.entrada = newRift(session, "entrada", feetCF, riftWidth)
	if not safeWait(session, CFG.RiftOpenDuration) then
		return
	end

	--------------------------------------------------------------------------
	-- 2) Entering -- afunda + some
	--------------------------------------------------------------------------
	setState(session, "Entering")
	riftOp(session, session.entrada, "enter")
	session.enterAnim = playOptionalAnim(session, CFG.TeleportEnterAnimationId)

	local sunkCF = root.CFrame - Vector3.new(0, CFG.SinkDepth, 0)
	tweenRoot(session, sunkCF, CFG.EnterDuration, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
	fadeCharacter(session, 1, CFG.EnterDuration * 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if not safeWait(session, CFG.EnterDuration) then
		return
	end
	if session.enterAnim then
		session.enterAnim:Stop(0.2)
		session.enterAnim = nil
	end
	-- Garante invisível.
	for part in session.origTransparency do
		if part.Parent then
			part.Transparency = 1
		end
	end

	--------------------------------------------------------------------------
	-- 3) Traveling -- fecha a entrada, abre o destino um pouco antes de sair
	--------------------------------------------------------------------------
	setState(session, "Traveling")
	riftOp(session, session.entrada, "close")
	cancelTweens(session)

	local destFeet = destCF - Vector3.new(0, hrpAboveFeet, 0)
	local lead = math.clamp(CFG.DestRiftLeadTime, 0, CFG.TravelDuration)
	task.delay(CFG.TravelDuration - lead, function()
		if session.cancelled or not session.character.Parent or session.destino then
			return
		end
		session.destino = newRift(session, "destino", destFeet, riftWidth)
	end)

	if not safeWait(session, CFG.TravelDuration) then
		return
	end

	-- TELEPORTE REAL: monstro invisível e enterrado, ninguém vê o "pop".
	placeRoot(character, root, destCF - Vector3.new(0, CFG.SinkDepth, 0))
	root.Anchored = true -- PivotTo pode desancorar; garante

	if not session.destino then
		session.destino = newRift(session, "destino", destFeet, riftWidth)
		task.wait(0.15)
	end

	--------------------------------------------------------------------------
	-- 4) Exiting -- emerge + reaparece
	--------------------------------------------------------------------------
	setState(session, "Exiting")
	riftOp(session, session.destino, "emerge")
	local exitAnim = playOptionalAnim(session, CFG.TeleportExitAnimationId)

	tweenRoot(session, destCF, CFG.ExitDuration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	fadeCharacter(session, 0, CFG.ExitDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if not safeWait(session, CFG.ExitDuration) then
		if exitAnim then
			exitAnim:Stop(0.2)
		end
		return
	end
	if exitAnim then
		exitAnim:Stop(0.25)
	end
	cancelTweens(session)
	placeRoot(character, root, destCF) -- snap exato

	for part, orig in session.origTransparency do
		if part.Parent then
			part.Transparency = orig
		end
	end
	riftOp(session, session.destino, "close")

	--------------------------------------------------------------------------
	-- 5) Recovery -> Idle
	--------------------------------------------------------------------------
	setState(session, "Recovery")
	root.Anchored = false
	humanoid.AutoRotate = session.origAutoRotate
	if not safeWait(session, CFG.PostTeleportRecovery) then
		return
	end

	setState(session, nil)
	session.cancelled = true -- sessão concluída; libera
	endSession(session)
end

--------------------------------------------------------------------------------
-- Ativação
--------------------------------------------------------------------------------

local function onTeleportRequest(player: Player, rawPoint: unknown)
	if player.Character and player.Character:GetAttribute("PowerStunned") == true then return end
	if not RoundManager.IsRoundActive() or not isMonster(player) then
		return
	end
	if activeSession or player:GetAttribute("Amarrado") == true then
		return
	end

	local character, humanoid, root = livingMonster(player)
	if not character or not humanoid or not root then
		return
	end
	if character:GetAttribute("TeleportBusy") == true or character:GetAttribute("ShadowRushBusy") == true then
		return
	end

	local last = lastUseAt[player.UserId]
	if last and (os.clock() - last) < CFG.TeleportCooldown then
		return -- cliente também segura; isto é a rede de segurança
	end

	local minY = select(1, characterBounds(character))
	local hrpAboveFeet = root.Position.Y - minY

	local destCF, reason = resolveDestination(root, hrpAboveFeet, character:GetScale(), rawPoint)
	if not destCF then
		Remotes.MonsterTeleport:FireClient(player, "cancel", reason or "destino inválido")
		lastUseAt[player.UserId] = os.clock() - (CFG.TeleportCooldown - CFG.FailureCooldown)
		Remotes.MonsterTeleport:FireClient(player, "cooldown", os.time() + CFG.FailureCooldown)
		return
	end

	lastUseAt[player.UserId] = os.clock()
	Remotes.MonsterTeleport:FireClient(player, "cooldown", os.time() + CFG.TeleportCooldown)

	local session: Session = {
		player = player,
		character = character,
		humanoid = humanoid,
		root = root,
		cancelled = false,
		origAutoRotate = humanoid.AutoRotate,
		origTransparency = {},
		tweens = {},
		connections = {},
		safetyThread = nil,
		entrada = nil,
		destino = nil,
		enterAnim = nil,
	}
	activeSession = session

	-- Hooks de cancelamento.
	table.insert(session.connections, humanoid.Died:Connect(function()
		abortSession(session, "monstro morreu")
	end))
	table.insert(session.connections, character:GetAttributeChangedSignal("Eliminado"):Connect(function()
		if character:GetAttribute("Eliminado") == true then
			abortSession(session, "monstro eliminado")
		end
	end))
	table.insert(session.connections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			abortSession(session, "character removido")
		end
	end))
	session.safetyThread = task.delay(CFG.SafetyTimeout, function()
		if activeSession == session and not session.cancelled then
			abortSession(session, "timeout de segurança")
		end
	end)

	task.spawn(function()
		local ok, err = pcall(runSequence, session, destCF)
		if not ok then
			warn("[MonsterTeleport] runSequence erro: " .. tostring(err))
			abortSession(session, "erro interno")
		end
	end)
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function MonsterTeleport.Init()
	task.spawn(publishRiftAsset)

	Remotes.MonsterTeleport.OnServerEvent:Connect(onTeleportRequest)

	RoundManager.RoundEnded.Event:Connect(function()
		if activeSession then
			abortSession(activeSession, "fim de partida")
		end
		table.clear(lastUseAt)
	end)
	RoundManager.RoundPrepared.Event:Connect(function()
		if activeSession then
			abortSession(activeSession, "nova partida")
		end
		table.clear(lastUseAt)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastUseAt[player.UserId] = nil
		if activeSession and activeSession.player == player then
			abortSession(activeSession, "monstro saiu")
		end
	end)
end

return MonsterTeleport
