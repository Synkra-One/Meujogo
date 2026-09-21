--!strict
--[[
	Apagão do Abismo -- habilidade do Monstro.

	REGRA CENTRAL: a área existe por UM instante. No disparo o servidor lê
	quem está dentro do raio e guarda essa lista; daí em diante a posição do
	jogador não importa mais. Sair não tira o efeito, entrar depois não pega.

	O que ela NÃO faz: não acelera o Monstro, não causa dano, não teleporta,
	não cria um segundo Fear e não cria uma segunda lanterna. Ao disparar,
	também apaga globalmente as luzes do mapa por WorldLightOffDuration.

	REAPROVEITAMENTO (nada disso é novo aqui):
	  - Fear: FearSystem.AddFear(player, pontos, "AbyssBlackout") -- a MESMA
	    tabela autoritativa do servidor, o mesmo teto (GameConfig.Fear.MaxFear
	    = 100) e a mesma recuperação passiva. Uma única aplicação por ativação.
	  - Compostura: StatScaling.FearGainMultiplier, o multiplicador que o
	    próprio FearSystem usa por segundo, aqui misturado por
	    ComposureInfluence (ver AbyssBlackoutRules.FearAmount).
	  - Lanterna: Attribute "AbyssBlackout" no character. Ele já está em
	    FlashlightConfig.BlockingFlags, que servidor (FlashlightSystem.canUse)
	    e cliente (FlashlightController.blockedReason) leem -- a Tool fica no
	    inventário, só não acende. FlashlightSystem.ForceOff apaga na hora.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PowerStatus = require(script.Parent.SurvivorPowerStatus)
local FlashlightRules = require(ReplicatedStorage.Modules.FlashlightRules)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Modules.GameConfig)
local Rules = require(ReplicatedStorage.Modules.AbyssBlackoutRules)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local FearSystem = require(script.Parent.FearSystem)
local FlashlightSystem = require(script.Parent.FlashlightSystem)
local Elimination = require(script.Parent.Elimination)
local RoundManager = require(script.Parent.RoundManager)

local CFG = Config.Monster.AbyssBlackout
local AbyssBlackout = {}

type Session = {
	player: Player, character: Model, endsAt: number, token: number,
	connections: { RBXScriptConnection },
}
type WorldLightSession = {
	endsAt: number,
	originalEnabled: { [Light]: boolean },
	originalTransparency: { [BasePart]: number },
}
-- Uma sessão por VÍTIMA. Uma ativação nova sobre alguém já afetado substitui
-- a anterior (o Fear é aplicado uma vez por ativação, nunca por frame).
local sessions: { [Player]: Session } = {}
local cooldowns: { [Player]: number } = {}
local requestAt: { [Player]: number } = {}
local casting: { [Player]: number } = {}
local castTokens: { [Player]: number } = {}
local worldToken: number? = nil
local worldLights: WorldLightSession? = nil
local serial, initialized = 0, false

local function setAttribute(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then instance:SetAttribute(name, value) end
end

local function clear(session: Session, reason: string)
	if sessions[session.player] ~= session then return end
	sessions[session.player] = nil
	for _, connection in session.connections do connection:Disconnect() end
	table.clear(session.connections)
	local character = session.character
	-- Some o bloqueio mesmo se o corpo já saiu do Workspace: a Tool volta a
	-- funcionar no próximo character sem nenhum resíduo.
	setAttribute(character, "AbyssBlackout", nil)
	setAttribute(character, "AbyssBlackoutUntil", nil)
	setAttribute(character, "AbyssBlackoutToken", nil)
	if session.player.Parent == Players then
		Remotes.AbyssBlackout:FireClient(session.player, "End", reason)
	end
end

local function clearAll(reason: string)
	for _, session in sessions do clear(session, reason) end
	table.clear(casting)
	table.clear(castTokens)
end

local function rememberWorldLight(light: Light)
	local session = worldLights
	if not session then return end
	if session.originalEnabled[light] == nil then
		session.originalEnabled[light] = light.Enabled
	end
	light.Enabled = false
end

local function isTrailLampVisual(part: BasePart): boolean
	if part:GetAttribute("LuzTrilhaVisual") == true then
		return true
	end

	local lamp = part:FindFirstAncestorOfClass("Model")
	if not lamp or lamp:GetAttribute("LuzTrilhaPoste") ~= true then
		return false
	end

	-- Alguns assets de poste usam material Neon ou nomes de peça diferentes,
	-- e por isso não recebem o atributo no gerador. Identifique somente a
	-- luminária, sem apagar a haste/estrutura inteira do poste.
	if part.Material == Enum.Material.Neon then
		return true
	end
	local name = string.lower(part.Name)
	return string.find(name, "lamp") ~= nil
		or string.find(name, "bulb") ~= nil
		or string.find(name, "light") ~= nil
		or string.find(name, "glow") ~= nil
		or string.find(name, "luz") ~= nil
		or string.find(name, "vidro") ~= nil
		or string.find(name, "glass") ~= nil
		or string.find(name, "lantern") ~= nil
end

local function rememberWorldVisual(part: BasePart)
	local session = worldLights
	if not session or not isTrailLampVisual(part) then return end
	if session.originalTransparency[part] == nil then
		session.originalTransparency[part] = part.Transparency
	end
	part.Transparency = 1
end

local function enforceWorldLightsOff()
	if not worldLights then return end
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Light") then
			rememberWorldLight(descendant)
		elseif descendant:IsA("BasePart") then
			rememberWorldVisual(descendant)
		end
	end
end

local function endWorldLights()
	local session = worldLights
	if not session then return end
	worldLights = nil
	Workspace:SetAttribute("AbyssWorldBlackout", false)
	for light, enabled in session.originalEnabled do
		if light.Parent then light.Enabled = enabled end
	end
	for part, transparency in session.originalTransparency do
		if part.Parent then part.Transparency = transparency end
	end
end

local function beginWorldLights(serverNow: number)
	endWorldLights()
	worldLights = {
		endsAt = serverNow + Config.Monster.AbyssBlackout.WorldLightOffDuration,
		originalEnabled = {},
		originalTransparency = {},
	}
	Workspace:SetAttribute("AbyssWorldBlackout", true)
	enforceWorldLightsOff()
end

local function livingCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character or not character:IsDescendantOf(Workspace) then return nil, nil, nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil, nil, nil end
	return character, humanoid, root
end

-- Vítima válida NO INSTANTE da ativação. Depois disso nada aqui é reavaliado.
local function eligibleVictim(player: Player): (Model?, BasePart?)
	if player:GetAttribute("Role") ~= Config.Roles.Survivor or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("CharacterSelectOpen") == true or Elimination.IsEliminated(player) then
		return nil, nil
	end
	local character, _, root = livingCharacter(player)
	return character, root
end

local function affect(victim: Player, character: Model, endsAt: number, token: number)
	local previous = sessions[victim]
	if previous then clear(previous, "reapplied") end
	local session: Session = { player = victim, character = character,
		endsAt = endsAt, token = token, connections = {} }
	sessions[victim] = session
	setAttribute(character, "AbyssBlackout", true)
	setAttribute(character, "AbyssBlackoutUntil", endsAt)
	setAttribute(character, "AbyssBlackoutToken", token)
	-- Corte imediato: o passo do FlashlightSystem também apagaria, mas só no
	-- próximo tick. Aqui a luz morre no mesmo frame do grito.
	FlashlightSystem.ForceOff(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(session.connections, humanoid.Died:Connect(function() clear(session, "death") end))
	end
	table.insert(session.connections, victim.CharacterRemoving:Connect(function() clear(session, "respawn") end))
	Remotes.AbyssBlackout:FireClient(victim, "Hit", CFG.Duration, endsAt)
end

local function cast(player: Player)
	local now = os.clock()
	if now < (casting[player] or 0) then return end -- trava anti-duplo-clique
	if not RoundManager.IsRoundActive() or player:GetAttribute("Role") ~= Config.Roles.Monster
		or player:GetAttribute("InRound") ~= true or Elimination.IsEliminated(player)
		or player:GetAttribute("Amarrado") == true then return end
	local character, humanoid, root = livingCharacter(player)
	if not character or not humanoid or not root or FlashlightRules.PowerBlocked(character) then return end
	for _, flag in { "Amarrado", "TeleportBusy", "GrabLocked", "PowerStunned", "ShadowRushBusy" } do
		if character:GetAttribute(flag) == true then return end
	end
	if now < (cooldowns[player] or 0) then
		local remaining = math.ceil(cooldowns[player] - now)
		Remotes.AbyssBlackout:FireClient(player, "Rejected", string.format("Apagão em %ds.", remaining))
		return
	end
	serial += 1
	local token = serial
	castTokens[player] = token
	local serverNow = Workspace:GetServerTimeNow()
	local endsAt = serverNow + CFG.Duration
	casting[player] = now + CFG.ActivationLockout
	cooldowns[player] = now + CFG.Cooldown
	player:SetAttribute("AbyssBlackoutReadyAt", serverNow + CFG.Cooldown)
	-- Diferente da área de vítimas da lanterna: o apagão ambiental vale para
	-- todas as luzes da ilha, mesmo que ninguém esteja perto delas. Ele começa
	-- junto do áudio do grito, não no instante em que o pedido R é aceito.
	task.delay(CFG.CastSoundDelay, function()
		if serial == token and castTokens[player] == token and RoundManager.IsRoundActive()
			and player.Character == character and humanoid.Health > 0 and not FlashlightRules.PowerBlocked(character) then
			beginWorldLights(Workspace:GetServerTimeNow())
			worldToken = token
		end
	end)
	-- Janela reservada pra animação de conjuração entrar depois; não muda
	-- gameplay nenhum: o registro abaixo acontece AGORA, no instante 0.
	character:SetAttribute("AbyssBlackoutCasting", true)
	character:SetAttribute("AbyssBlackoutCastAt", serverNow)
	task.delay(CFG.CastDuration, function()
		if character:GetAttribute("AbyssBlackoutCastAt") == serverNow then
			setAttribute(character, "AbyssBlackoutCasting", nil)
		end
	end)
	local origin = root.Position
	-- FOTOGRAFIA ÚNICA DA ÁREA: esta é a única leitura de posição da
	-- habilidade. Ninguém entra nesta lista depois.
	local caught = 0
	for _, victim in Players:GetPlayers() do
		if victim == player then continue end
		local victimCharacter, victimRoot = eligibleVictim(victim)
		if not victimCharacter or not victimRoot then continue end
		if not Rules.InRadius(origin, victimRoot.Position, CFG.Radius) then continue end
		caught += 1
		affect(victim, victimCharacter, endsAt, token)
		-- Uma aplicação de Fear, aqui, e só aqui. O teto de 100 é do FearSystem.
		local amount = Rules.FearAmount(CFG.Fear, StatScaling.FearGainMultiplier(victim),
			CFG.ComposureInfluence, Config.Fear.MaxFear)
		FearSystem.AddFear(victim, amount, "AbyssBlackout")
	end
	Remotes.AbyssBlackout:FireAllClients("Cast", character, serverNow + CFG.CastSoundDelay)
	Remotes.AbyssBlackout:FireClient(player, "Result", caught)
end

local function step()
	local serverNow = Workspace:GetServerTimeNow()
	if worldLights then
		if serverNow >= worldLights.endsAt then
			endWorldLights()
		else
			enforceWorldLightsOff()
		end
	end
	local roundActive = RoundManager.IsRoundActive()
	for victim, session in sessions do
		if not roundActive or serverNow >= session.endsAt or victim.Parent ~= Players
			or victim.Character ~= session.character or Elimination.IsEliminated(victim) then
			clear(session, if serverNow >= session.endsAt then "expired" else "interrupted")
		end
	end
end

-- Cancelamento externo (morte por outro sistema, fim de rodada, admin).
function AbyssBlackout.Cancel(player: Player)
	local session = sessions[player]
	if session then clear(session, "external cancel") end
end

function AbyssBlackout.IsBlinded(player: Player): boolean
	return sessions[player] ~= nil
end

function AbyssBlackout.Init()
	if initialized then return end -- protege contra conexões duplicadas
	assert(RunService:IsServer(), "AbyssBlackout só pode iniciar no servidor")
	assert(CFG.Radius > 0 and CFG.Duration > 0 and CFG.ServerInterval > 0,
		"AbyssBlackout: raio/duração/intervalo inválidos")
	assert(CFG.WorldLightOffDuration > 0,
		"AbyssBlackout: duração do apagão global inválida")
	assert(CFG.CastSoundDelay >= 0,
		"AbyssBlackout: atraso do grito inválido")
	assert(CFG.Cooldown >= CFG.Duration and CFG.Cooldown >= 60 and CFG.Cooldown <= 90,
		"AbyssBlackout: cooldown deve ficar entre 60 e 90 segundos e cobrir a duração")
	assert(CFG.Fear > 0 and CFG.Fear <= Config.Fear.MaxFear
		and CFG.ComposureInfluence >= 0 and CFG.ComposureInfluence <= 1,
		"AbyssBlackout: Fear fora da escala do GameConfig.Fear")
	assert(table.find(require(ReplicatedStorage.Modules.FlashlightConfig).BlockingFlags, "AbyssBlackout") ~= nil,
		"AbyssBlackout: a flag precisa estar em FlashlightConfig.BlockingFlags")
	initialized = true
	PowerStatus.RegisterStunInterruptor(function(character)
		local owner = Players:GetPlayerFromCharacter(character)
		local token = owner and castTokens[owner]
		if not owner or not token then return end
		castTokens[owner], casting[owner] = nil, nil
		setAttribute(character, "AbyssBlackoutCasting", nil)
		for _, session in sessions do
			if session.token == token then clear(session, "caster flash stunned") end
		end
		if worldToken == token then endWorldLights(); worldToken = nil end
	end)
	Remotes.AbyssBlackout.OnServerEvent:Connect(function(player, action)
		if action ~= "Use" then return end
		local now = os.clock()
		if now - (requestAt[player] or -math.huge) < CFG.InputInterval then return end
		requestAt[player] = now
		local ok, err = pcall(cast, player)
		if not ok then warn("[AbyssBlackout] Use: " .. tostring(err)) end
	end)
	Players.PlayerRemoving:Connect(function(player)
		AbyssBlackout.Cancel(player)
		cooldowns[player], requestAt[player], casting[player], castTokens[player] = nil, nil, nil, nil
		player:SetAttribute("AbyssBlackoutReadyAt", nil)
	end)
	local function reset()
		clearAll("round reset")
		endWorldLights()
		table.clear(cooldowns); table.clear(requestAt)
		for _, player in Players:GetPlayers() do player:SetAttribute("AbyssBlackoutReadyAt", nil) end
	end
	RoundManager.RoundPrepared.Event:Connect(reset)
	RoundManager.RoundEnded.Event:Connect(reset)
	local accumulated = 0
	-- ÚNICA conexão de atualização, e ela só EXPIRA sessões: nenhum Fear é
	-- somado aqui, nenhuma posição é lida.
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < CFG.ServerInterval then return end
		accumulated = 0
		local ok, err = pcall(step)
		if not ok then warn("[AbyssBlackout] Step: " .. tostring(err)) end
	end)
	Workspace.DescendantAdded:Connect(function(descendant)
		if not worldLights then return end
		if descendant:IsA("Light") then
			rememberWorldLight(descendant)
		elseif descendant:IsA("BasePart") then
			rememberWorldVisual(descendant)
		end
	end)
end

return AbyssBlackout
