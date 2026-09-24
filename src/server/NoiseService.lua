--!strict
--[[
	NoiseService
	Super audição autoritativa. Reusa MovementSampled da stamina (10 Hz),
	Humanoid.StateChanged e hooks existentes; não cria loop nem remote de entrada.

	O QUE DECIDE SE UM PASSO VIRA PING (os números estão em GameConfig.Noise):

	  ESTADO      A velocidade horizontal REAL, normalizada pela base de
	              caminhada do personagem, vira Agachado / Andar / Trotar /
	              Correr (StatScaling.NoiseState). Nenhum Attribute do cliente
	              é autoridade aqui: mentir postura não silencia ninguém.

	  FURTIVIDADE O atributo do personagem define, para AQUELE estado, o
	              alcance (StatScaling.NoiseRadius) e o intervalo entre ruídos
	              (StatScaling.NoisePingInterval). Furtividade alta = alcance
	              menor E menos pings. Abaixo de MinAudibleRadius o ruído nem
	              é gerado: é o silêncio de verdade de quem é muito furtivo.

	  DISTÂNCIA   Estar dentro do alcance não garante nada. Até ClearFraction
	              do raio o Monstro ouve sempre, na posição certa; daí para a
	              borda a chance cai e a posição chega embaralhada. É o que
	              separa "pista de onde houve barulho" de wallhack.

	O cooldown anda quando o RUÍDO acontece, não quando alguém escuta -- senão
	a amostra de 10 Hz repetiria até a sorte passar e o desconto por distância
	não valeria nada.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local RoundManager = require(script.Parent.RoundManager)
local StaminaSystem = require(script.Parent.StaminaSystem)
local FearSystem = require(script.Parent.FearSystem)
local WeaponSystem = require(script.Parent.WeaponSystem)

local CFG = GameConfig.Noise
local FALLOFF = CFG.DistanceFalloff
-- Do mais silencioso ao mais barulhento. Só para relatório do Diagnose.
local STATE_ORDER = { "Crouch", "Walk", "Jog", "Sprint" }
local NoiseService = {}
local initialized = false
local firstDeliveryLogged = false
local monsters: { [Player]: boolean } = {}
local watches: { [Player]: { RBXScriptConnection } } = {}
local actionTimes: { [Player]: number } = {}

type Movement = {
	character: Model, connection: RBXScriptConnection?, bornAt: number,
	grounded: boolean, sawGround: boolean, airAt: number?, peakY: number,
	jumped: boolean, lastStep: number,
	lastJump: number, lastLanding: number,
}
local movements: { [Player]: Movement } = {}

local function finite(n: number): boolean
	return n == n and math.abs(n) < math.huge
end

local function activeRoot(player: Player, role: string): BasePart?
	if player.Parent ~= Players or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Role") ~= role or player:GetAttribute("Eliminado") == true then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or character:GetAttribute("Eliminado") == true
		or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil end
	return root
end

-- Porta de validação compartilhada com a audição de batimentos.
NoiseService.GetActiveRoot = activeRoot

-- Descarte silencioso é o comportamento normal (não revela nada pro cliente),
-- mas em desenvolvimento ele é exatamente o que esconde o motivo de "não
-- aparece nada". Com Debug.Verbose cada recusa diz por quê.
-- Formata SÓ quando Verbose está ligado: descarte é o caminho quente (toda
-- amostra de quem não é sobrevivente ativo passa por aqui, 10 Hz por jogador).
local function reject(reason: string, ...): boolean
	if CFG.Debug.Verbose then
		warn("[NoiseService] ping descartado -- " .. string.format(reason, ...))
	end
	return false
end

-- Teste solo: ver o comentário de GameConfig.Noise.Debug.SelfHear.
local function selfHearing(): boolean
	return CFG.Debug.SelfHear == true and RunService:IsStudio()
end

-- Ilha gigante + Monstro isolado na caverna: ver o comentário de
-- GameConfig.Noise.Debug.IgnoreRadius.
local function ignoringRadius(): boolean
	return CFG.Debug.IgnoreRadius == true and RunService:IsStudio()
end

-- Chance de um ruído dentro do alcance realmente chegar ao Monstro.
-- 1 até ClearFraction do raio; daí cai até EdgeChance na borda. Exponent > 1
-- faz a perda acelerar no fim, então "longe" fica bem menos confiável que
-- "no meio do caminho".
local function hearingChance(distance: number, range: number): number
	local clear = math.clamp(FALLOFF.ClearFraction, 0, 0.99)
	local t = math.clamp(distance / range, 0, 1)
	if t <= clear then return 1 end
	return 1 - (1 - FALLOFF.EdgeChance) * ((t - clear) / (1 - clear)) ^ FALLOFF.Exponent
end

-- O círculo marca a REGIÃO do barulho, não o jogador. O erro cresce com a
-- distância: colado é quase exato, na borda é um palpite. Só no plano XZ, pra
-- a onda não afundar no chão nem flutuar.
local function blur(position: Vector3, distance: number, range: number): Vector3
	local t = math.clamp(distance / range, 0, 1)
	local spread = FALLOFF.NearSpread + (FALLOFF.EdgeSpread - FALLOFF.NearSpread) * t
	if spread <= 0 then return position end
	local angle = math.random() * 2 * math.pi
	-- Raiz da uniforme = ponto uniforme no disco (sem amontoar no centro).
	local offset = math.sqrt(math.random()) * spread
	return position + Vector3.new(math.cos(angle) * offset, 0, math.sin(angle) * offset)
end

local function send(player: Player, position: Vector3, intensity: number, radius: number): boolean
	if not CFG.Enabled then return reject("GameConfig.Noise.Enabled = false") end
	if not RoundManager.IsRoundActive() then return reject("nenhuma partida em andamento") end
	if not activeRoot(player, GameConfig.Roles.Survivor) then
		return reject("%s nao e um Sobrevivente vivo dentro da partida", player.Name)
	end
	if typeof(position) ~= "Vector3" or not finite(position.X) or not finite(position.Y)
		or not finite(position.Z) then return reject("posicao invalida") end
	if type(intensity) ~= "number" or not finite(intensity) or intensity <= 0 then
		return reject("intensidade invalida")
	end
	if intensity < CFG.MinimumIntensity then
		return reject("intensidade %.1f abaixo de MinimumIntensity %.1f", intensity, CFG.MinimumIntensity)
	end
	if not finite(radius) or radius <= 0 then return reject("raio invalido") end

	local range = math.min(radius, CFG.MaxNoiseRadius)
	local bypassRange = ignoringRadius()
	local delivered, listeners = false, 0
	for monster in monsters do
		local root = activeRoot(monster, GameConfig.Roles.Monster)
		if root then
			listeners += 1
			local distance = (root.Position - position).Magnitude
			if distance > range and not bypassRange then
				reject("%s esta a %.0f studs, alcance e %.0f (ligue GameConfig.Noise.Debug.IgnoreRadius pra ignorar isso em teste)",
					monster.Name, distance, range)
				continue
			end
			-- IgnoreRadius é diagnóstico: entrega certa e exata, senão o teste
			-- passaria a depender de sorte e de posição embaralhada.
			local chance = if bypassRange then 1 else hearingChance(distance, range)
			if chance < 1 and math.random() >= chance then
				reject("%s a %.0f/%.0f studs: o ruido se perdeu no caminho (%.0f%% de chance)",
					monster.Name, distance, range, chance * 100)
				continue
			end
			local heardAt = if bypassRange then position else blur(position, distance, range)
			Remotes.NoiseDetected:FireClient(monster, heardAt, intensity)
			delivered = true
			if not firstDeliveryLogged then
				firstDeliveryLogged = true
				print(string.format("[NoiseService] Primeiro ping enviado ao Monstro (intensidade %.1f).", intensity))
			end
			if CFG.Debug.Verbose then
				local note = if distance > range then " (fora do alcance -- entregue por IgnoreRadius)" else ""
				print(string.format("[NoiseService] ping -> %s (intensidade %.1f, %.0f/%.0f studs, %.0f%% de chance)%s.",
					monster.Name, intensity, distance, range, chance * 100, note))
			end
		end
	end
	-- Depois do laço: o eco de teste não conta como "existe um Monstro".
	if selfHearing() then
		Remotes.NoiseDetected:FireClient(player, position, intensity)
		delivered = true
	end
	if listeners == 0 then
		reject("nenhum Monstro vivo na partida (teste solo cai em um papel so -- ver GameConfig.Noise.Debug.SelfHear)")
	end
	return delivered
end

-- API exclusiva do servidor. Posição pode ser um impacto longe do personagem.
-- Raio opcional para integrações com alcance próprio; sem ele escala pela intensidade.
-- Retorna true quando pelo menos um monstro recebeu o ping.
function NoiseService:EmitNoise(player: Player, position: Vector3, intensity: number, radius: number?): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player")
		or type(intensity) ~= "number" or not finite(intensity) or intensity <= 0
		or (radius ~= nil and (type(radius) ~= "number" or not finite(radius) or radius <= 0)) then return false end
	local now = os.clock()
	if now - (actionTimes[player] or -math.huge) < CFG.ActionPingInterval then return false end
	if not send(player, position, intensity, radius or intensity * CFG.RadiusPerIntensity) then return false end
	actionTimes[player] = now
	return true
end

local function clearMovement(player: Player)
	local record = movements[player]
	if record and record.connection then record.connection:Disconnect() end
	movements[player] = nil
	actionTimes[player] = nil
end

local function clearAll()
	for player in movements do clearMovement(player) end
	table.clear(actionTimes)
end

local function observeState(player: Player, record: Movement, humanoid: Humanoid, root: BasePart,
	state: Enum.HumanoidStateType)
	if movements[player] ~= record or player.Character ~= record.character then return end
	local now = os.clock()
	-- O controller customizado pode usar RunningNoPhysics enquanto anda.
	-- FloorMaterial é a fonte física de chão; excluímos estados que não são passos.
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		and state ~= Enum.HumanoidStateType.Swimming
		and state ~= Enum.HumanoidStateType.Climbing
		and state ~= Enum.HumanoidStateType.Seated
		and state ~= Enum.HumanoidStateType.Dead
	local airborne = state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall
	if grounded then
		if record.airAt and record.sawGround and now - record.bornAt >= CFG.SpawnGrace
			and now - record.airAt >= CFG.MinAirTime and record.peakY - root.Position.Y >= CFG.MinLandingDrop
			and now - record.lastLanding >= CFG.LandingPingInterval then
			record.lastLanding = now
			send(player, root.Position, CFG.LandingIntensity, CFG.LandingNoiseRadius)
		end
		record.sawGround, record.grounded = true, true
		record.airAt, record.jumped = nil, false
		record.peakY = root.Position.Y
	elseif airborne then
		record.grounded = false
		if not record.airAt then record.airAt, record.peakY = now, root.Position.Y end
		record.peakY = math.max(record.peakY, root.Position.Y)
		-- Freefall ascendente cobre transições Jumping que não chegaram ao servidor.
		-- Nunca confia em um pedido de salto/altura vindo de RemoteEvent.
		if record.sawGround and not record.jumped and now - record.bornAt >= CFG.SpawnGrace
			and root.AssemblyLinearVelocity.Y >= CFG.MinJumpVerticalSpeed
			and now - record.lastJump >= CFG.JumpPingInterval then
			record.jumped, record.lastJump = true, now
			send(player, root.Position, CFG.JumpIntensity, CFG.JumpNoiseRadius)
		end
	else
		-- Nadar, escalar, sentar e ragdoll não viram passos/aterrissagens.
		record.grounded, record.sawGround = false, false
		record.airAt, record.jumped = nil, false
	end
end

local function sample(player: Player, character: Model, humanoid: Humanoid, root: BasePart,
	speed: number, walkBase: number)
	if not CFG.Enabled or not RoundManager.IsRoundActive() or player.Character ~= character
		or activeRoot(player, GameConfig.Roles.Survivor) ~= root then
		if movements[player] then clearMovement(player) end
		return
	end
	local record = movements[player]
	if not record or record.character ~= character then
		clearMovement(player)
		record = {
			character = character, connection = nil, bornAt = os.clock(), grounded = false, sawGround = false,
			airAt = nil, peakY = root.Position.Y, jumped = false,
			lastStep = -math.huge,
			lastJump = -math.huge, lastLanding = -math.huge,
		}
		movements[player] = record
		local current = record
		record.connection = humanoid.StateChanged:Connect(function(_, newState)
			observeState(player, current, humanoid, root, newState)
		end)
	end
	observeState(player, record, humanoid, root, humanoid:GetState())
	if not record.grounded or root.Anchored or humanoid.Sit
		or character:GetAttribute("GrabLocked") == true
		or character:GetAttribute("PowerStunned") == true then return end
	local now = os.clock()
	if now - record.bornAt < CFG.SpawnGrace or now - record.lastLanding < CFG.MinAirTime then return end
	-- Os atributos IsCrouching/IsWalking/IsSprinting do pacote de movimento são
	-- LOCAIS e não mandam aqui: a classificação é acústica, pela velocidade
	-- real. Mentir SprintIntent=false não suprime ruído se a velocidade ainda
	-- for de corrida, e forçar "andando" no cliente não deixa ninguém correr
	-- em silêncio.
	local state = StatScaling.NoiseState(speed, walkBase)
	if not state then return end
	local profile = CFG.States[state]
	local interval = StatScaling.NoisePingInterval(player, state)
	if not profile or not interval then return end
	-- UM cooldown para todos os estados de solo, não um por estado: trocar de
	-- ritmo no meio do passo não pode render um ping de graça. Como o intervalo
	-- consultado é o do estado ATUAL, quem acelera para a corrida volta a fazer
	-- barulho na cadência da corrida, sem esperar a da caminhada terminar.
	if now - record.lastStep < interval then return end
	if profile.Intensity <= 0 or profile.Intensity < CFG.MinimumIntensity then return end
	local radius = StatScaling.NoiseRadius(player, state)
	-- Furtividade alta encolhe o alcance até ele não significar mais nada.
	-- Aí o ruído some na origem em vez de virar um ping curto demais para
	-- entregar alguém -- é o "anda em silêncio" do personagem furtivo.
	if not radius or radius < CFG.MinAudibleRadius then return end
	-- O barulho ACONTECEU: o cooldown anda mesmo que nenhum Monstro escute.
	-- Se dependesse da entrega, a amostra de 10 Hz repetiria até a chance por
	-- distância passar e o desconto por distância não valeria nada.
	record.lastStep = now
	send(player, root.Position, profile.Intensity, radius)
end

--[[
	Diagnose()
	Só pra desenvolvimento: rode na Command Bar durante um Play pra ver, de
	uma vez, tudo que o filtro de ruído checa antes de mandar um ping.

		require(game.ServerScriptService.Server.NoiseService).Diagnose()
]]
function NoiseService.Diagnose()
	print(string.format("[NoiseService] Enabled=%s | RodadaAtiva=%s | SelfHear=%s | IgnoreRadius=%s | Verbose=%s",
		tostring(CFG.Enabled), tostring(RoundManager.IsRoundActive()),
		tostring(selfHearing()), tostring(ignoringRadius()), tostring(CFG.Debug.Verbose)))
	local activeMonsters, activeSurvivors = {}, {}
	for _, player in Players:GetPlayers() do
		local role = player:GetAttribute("Role")
		local root = role ~= nil and activeRoot(player, role :: string) or nil
		print(string.format("  %s -> Role=%s InRound=%s Eliminado=%s ativo=%s",
			player.Name, tostring(role), tostring(player:GetAttribute("InRound")),
			tostring(player:GetAttribute("Eliminado")), tostring(root ~= nil)))
		if root then
			if role == GameConfig.Roles.Monster then
				table.insert(activeMonsters, { player = player, root = root })
			elseif role == GameConfig.Roles.Survivor then
				table.insert(activeSurvivors, { player = player, root = root })
			end
		end
	end
	-- A causa mais comum de "não aparece nada" não é código: é distância, e
	-- agora também FURTIVIDADE. A ilha tem 560-820 studs de raio de costa e o
	-- Monstro nasce sozinho numa caverna na montanha. Por isso cada linha
	-- abaixo mostra o alcance REAL do sobrevivente em cada estado, já com a
	-- Furtividade dele aplicada, e a chance de o ruído chegar dessa distância.
	if #activeMonsters == 0 or #activeSurvivors == 0 then
		print("[NoiseService]   (sem Monstro E Sobrevivente ativos ao mesmo tempo -- nenhuma distância pra medir)")
		return
	end
	for _, m in activeMonsters do
		for _, s in activeSurvivors do
			local distance = (m.root.Position - s.root.Position).Magnitude
			local report = {}
			for _, state in STATE_ORDER do
				local radius = StatScaling.NoiseRadius(s.player, state) or 0
				local silent = radius < CFG.MinAudibleRadius
				local verdict
				if silent then
					verdict = "mudo"
				elseif distance > radius then
					verdict = "fora"
				else
					verdict = string.format("%.0f%%", hearingChance(distance, radius) * 100)
				end
				table.insert(report, string.format("%s %s/%.0f a cada %.1fs", state, verdict, radius,
					StatScaling.NoisePingInterval(s.player, state) or 0))
			end
			print(string.format("  distância %s <-> %s: %.0f studs | Furtividade %s\n    %s",
				m.player.Name, s.player.Name, distance,
				tostring(StatScaling.Of(s.player, "Furtividade") or "sem personagem (vale 50)"),
				table.concat(report, "\n    ")))
		end
	end
end

function NoiseService.Init()
	if initialized then return end
	initialized = true
	local function watch(player: Player)
		if watches[player] then return end
		local function refresh()
			monsters[player] = if player:GetAttribute("Role") == GameConfig.Roles.Monster then true else nil
			clearMovement(player)
		end
		watches[player] = { player.CharacterRemoving:Connect(function() clearMovement(player) end) }
		for _, attribute in { "Role", "InRound", "Eliminado" } do
			table.insert(watches[player], player:GetAttributeChangedSignal(attribute):Connect(refresh))
		end
		refresh()
	end
	for _, player in Players:GetPlayers() do watch(player) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		clearMovement(player)
		monsters[player] = nil
		for _, connection in watches[player] or {} do connection:Disconnect() end
		watches[player] = nil
	end)
	RoundManager.RoundPrepared.Event:Connect(clearAll)
	RoundManager.RoundEnded.Event:Connect(clearAll)
	StaminaSystem.MovementSampled.Event:Connect(sample)
	WeaponSystem.NoiseMade.Event:Connect(function(position, player, intensity)
		-- Gerador legado não informa um sobrevivente; não revela ninguém.
		if player then NoiseService:EmitNoise(player, position, intensity or CFG.StoneIntensity) end
	end)
	FearSystem.PanicSoundTriggered.Event:Connect(function(player, position, radius)
		NoiseService:EmitNoise(player, position, CFG.PanicIntensity, radius)
	end)
	print("[NoiseService] Super audição pronta; agachar, andar, trotar, correr, salto e aterrissagem ativos (alcance e cadência pela Furtividade).")
end

return NoiseService
