--!strict
--[[
	RadioSiteSystem
	Faz a ESTAÇÃO DE RÁDIO funcionar. O local é construído por
	Tools/RadioTowerGenerator.lua; aqui roda a corrente de interações que
	transforma aquele cenário no objetivo de fuga:

	  1. PEÇAS       Antena + Bateria + Transmissor no rack (RadioInstallSystem)
	  2. COMBUSTÍVEL despeja um galão no gerador            (segurar E)
	  3. FUSÍVEL     pega o reserva no abrigo e põe na caixa (duas interações)
	  4. LIGAR       dá partida no gerador -- FAZ BARULHO    (segurar E)
	  5. PAINEL      energiza o transmissor no painel        (segurar E)
	  6. SOCORRO     transmite o pedido, parado no console   (canalizado)

	COMBUSTÍVEL tem DUAS fontes, e o bocal aceita as duas: os galões fixos já
	no pátio (`GalaoCombustivel`, ver Tools/RadioTowerGenerator.lua) e o item
	"Gasolina" (ItemRegistry/ToolFactory), achado espalhado pelo mapa e
	carregado como Tool. `onRefuel` prefere a Gasolina carregada -- assim
	achar combustível longe da estação ainda vale a pena.

	Cada etapa é um ProximityPrompt criado a partir do Attribute
	"InteracaoRadio" das Parts geradas -- o mapa não guarda configuração de
	prompt, então mapa salvo antigo e mapa novo se comportam igual.

	ESTADO (Attributes no Model TorreDeRadio, replicam sozinhos pro cliente):
	  Combustivel       number   segundos de gerador que ainda dá pra queimar
	  FusivelInstalado  boolean
	  GeradorLigado     boolean
	  PainelAtivo       boolean
	  SocorroEmAndamento boolean
	  SocorroEnviado    boolean
	  SinalProgresso    number   0..100
	E no jogador: LevandoFusivel = true enquanto carrega o fusível reserva.

	TENSÃO (é de propósito):
	  - o gerador é barulhento: enquanto roda, dispara WeaponSystem.NoiseMade
	    e avisa o Monstro por mensagem, num intervalo fixo;
	  - o combustível queima: parar no meio obriga a voltar pro galão;
	  - o Espião sabota gerador/painel (Attribute "Sabotavel", SabotageSystem
	    já põe o prompt "Reparar") e a energia cai na hora;
	  - o chamado de socorro é canalizado e cancela se quem transmite sair de
	    perto, morrer ou a energia cair. O progresso vai por ObjectiveProgress
	    pra TODO mundo -- inclusive pro Monstro, que sabe que tem alguém lá.

	Uso (boot do servidor, DEPOIS de RadioInstallSystem):
		require(script.RadioSiteSystem).Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local RadioObjective = require(script.Parent.RadioObjective)
local WeaponSystem = require(script.Parent.WeaponSystem)

local RadioSiteSystem = {}

local CFG = GameConfig.RadioSite
local PIECE_TYPES = { "Antena", "Bateria", "Transmissor" }
local UPDATE_INTERVAL = 0.2
local PROGRESS_INTERVAL = 0.25

type PoweredPart = { part: BasePart, material: Enum.Material, color: Color3 }

local station: Model? = nil
local hosts: { [string]: BasePart } = {} -- InteracaoRadio -> Part
local prompts: { [string]: ProximityPrompt } = {}
local cans: { BasePart } = {}
local beacons: { BasePart } = {}
local powered: { PoweredPart } = {}
local exhaust: BasePart? = nil
local engine: BasePart? = nil
local engineSound: Sound? = nil
local radioSound: Sound? = nil -- rádio energizado (a partir do painel)
local callSound: Sound? = nil -- pedido de socorro no ar (durante a canalização)
local smoke: ParticleEmitter? = nil
local fuseHome: CFrame? = nil

local fuseCarrier: Player? = nil
local signalPlayer: Player? = nil
local signalProgress = 0
local lastNoise = 0
local noiseTicks = 0
local lastProgressSent = 0
local initialized = false

--------------------------------------------------------------------------------
-- Estado
--------------------------------------------------------------------------------

local function getFlag(name: string): boolean
	local model = station
	return model ~= nil and model:GetAttribute(name) == true
end

local function getNumber(name: string): number
	local model = station
	local value = model and model:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function setAttr(name: string, value: any)
	local model = station
	if model then
		model:SetAttribute(name, value)
	end
end

local function piecesInstalled(): boolean
	local model = station
	if not model then
		return false
	end
	for _, pieceType in PIECE_TYPES do
		if model:GetAttribute(pieceType .. "Instalada") ~= true then
			return false
		end
	end
	return true
end

local function isSabotaged(): boolean
	local body = engine
	local panel = hosts.Painel
	return (body ~= nil and body:GetAttribute("Sabotado") == true)
		or (panel ~= nil and panel:GetAttribute("Sabotado") == true)
end

local function tellEveryone(message: string)
	for _, player in Players:GetPlayers() do
		Remotes.LobbyMessage:FireClient(player, message)
	end
end

local function tellMonster(message: string)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == GameConfig.Roles.Monster then
			Remotes.LobbyMessage:FireClient(player, message)
		end
	end
end

--------------------------------------------------------------------------------
-- Validação de quem interage (mesmo contrato de RadioObjective.canInteract)
--------------------------------------------------------------------------------

local function canAct(player: Player, target: BasePart?): boolean
	if not target or not target:IsDescendantOf(Workspace) then
		return false
	end
	if player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then
		Remotes.LobbyMessage:FireClient(player, "Só os Sobreviventes mexem na estação de rádio.")
		return false
	end
	if player:GetAttribute("Eliminado") == true or player:GetAttribute("Amarrado") == true then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end
	if character:GetAttribute("PowerStunned") == true or character:GetAttribute("GrabLocked") == true then
		return false
	end
	return (root.Position - target.Position).Magnitude <= CFG.AlcanceInteracao
end

local function distanceTo(player: Player, target: BasePart?): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not target or not root or not root:IsA("BasePart") then
		return math.huge
	end
	return (root.Position - target.Position).Magnitude
end

--------------------------------------------------------------------------------
-- Energia: luzes, som, fumaça
--------------------------------------------------------------------------------

local function setLights(on: boolean)
	for _, entry in powered do
		local p = entry.part
		if not p.Parent then
			continue
		end
		p.Material = if on then entry.material else Enum.Material.SmoothPlastic
		p.Color = if on then entry.color else entry.color:Lerp(Color3.new(0, 0, 0), 0.65)
		for _, child in p:GetDescendants() do
			if child:IsA("Light") and child.Name == "LuzRadio" then
				child.Enabled = on
			end
		end
	end
end

local function setGenerator(on: boolean, reason: string?)
	if getFlag("GeradorLigado") == on then
		return
	end
	setAttr("GeradorLigado", on)
	setLights(on)

	if smoke then
		smoke.Enabled = on
	end
	local sound = engineSound
	if sound then
		if on then
			sound:Play()
		else
			sound:Stop()
		end
	end

	if on then
		lastNoise = 0 -- faz barulho já no primeiro tick
		noiseTicks = 0
		tellEveryone("O gerador da estação de rádio está ligado.")
	else
		-- Sem energia, o transmissor cai junto.
		if getFlag("PainelAtivo") then
			setAttr("PainelAtivo", false)
		end
		if reason then
			tellEveryone(reason)
		end
	end
end

--------------------------------------------------------------------------------
-- Ações
--------------------------------------------------------------------------------

local function nearestFullCan(): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	local body = engine
	if not body then
		return nil
	end
	for _, can in cans do
		if can.Parent and can:GetAttribute("Cheio") == true then
			local d = (can.Position - body.Position).Magnitude
			if d < bestDist then
				bestDist = d
				best = can
			end
		end
	end
	return best
end

-- Tool "Gasolina" que o jogador está carregando: equipada tem prioridade,
-- senão a primeira que aparecer na mochila. Mesmo padrão de
-- RadioInstallSystem.installableTool (equipado antes de vasculhar a mochila).
local function carriedGasolina(player: Player): Tool?
	local character = player.Character
	if character then
		local equipped = character:FindFirstChildOfClass("Tool")
		if equipped and equipped:GetAttribute("Gasolina") == true then
			return equipped
		end
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, item in backpack:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute("Gasolina") == true then
				return item :: Tool
			end
		end
	end
	return nil
end

-- Pra decidir se o prompt "Abastecer" aparece pra ALGUÉM: ProximityPrompt.
-- Enabled é global (não por jogador), então "tem combustível disponível"
-- precisa considerar todo mundo carregando Gasolina, não só quem apertou.
local function anyPlayerCarriesGasolina(): boolean
	for _, player in Players:GetPlayers() do
		if carriedGasolina(player) then
			return true
		end
	end
	return false
end

local function onRefuel(player: Player)
	if not canAct(player, hosts.Abastecer) then
		return
	end
	if getNumber("Combustivel") >= CFG.CombustivelMaximo then
		Remotes.LobbyMessage:FireClient(player, "O tanque do gerador já está cheio.")
		return
	end

	-- Prefere a Gasolina que o jogador está carregando ao galão fixo do
	-- local -- carregar combustível de longe precisa valer o esforço, e
	-- assim ela nunca fica "presa" atrás de um galão que ainda sobrou.
	local carried = carriedGasolina(player)
	if carried then
		carried:Destroy()
		setAttr("Combustivel", math.min(CFG.CombustivelMaximo, getNumber("Combustivel") + CFG.CombustivelPorGalao))
		Remotes.LobbyMessage:FireClient(player, "Gerador abastecido com a gasolina que você trouxe.")
		print(string.format("[RadioSite] %s abasteceu o gerador com Gasolina carregada (%.0fs de combustível).", player.Name, getNumber("Combustivel")))
		return
	end

	local can = nearestFullCan()
	if not can then
		Remotes.LobbyMessage:FireClient(player, "Não sobrou combustível: nem galão no local, nem Gasolina no inventário.")
		return
	end

	-- Galão vazio fica caído do lado, pra dar pra ver o que já foi gasto.
	can:SetAttribute("Cheio", false)
	can.Color = Color3.fromRGB(96, 52, 44)
	can.CFrame = can.CFrame * CFrame.new(0, -0.6, -1.2) * CFrame.Angles(math.rad(88), 0, 0)

	setAttr("Combustivel", math.min(CFG.CombustivelMaximo, getNumber("Combustivel") + CFG.CombustivelPorGalao))
	Remotes.LobbyMessage:FireClient(player, "Gerador abastecido.")
	print(string.format("[RadioSite] %s abasteceu o gerador (%.0fs de combustível).", player.Name, getNumber("Combustivel")))
end

local function dropFuse(position: Vector3?)
	local fuse = hosts.PegarFusivel
	local carrier = fuseCarrier
	if carrier then
		carrier:SetAttribute("LevandoFusivel", nil)
	end
	fuseCarrier = nil
	if not fuse then
		return
	end
	fuse.Transparency = 0
	if position then
		fuse.CFrame = CFrame.new(position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	elseif fuseHome then
		fuse.CFrame = fuseHome
	end
end

local function onTakeFuse(player: Player)
	if not canAct(player, hosts.PegarFusivel) then
		return
	end
	if getFlag("FusivelInstalado") or fuseCarrier ~= nil then
		return
	end
	local fuse = hosts.PegarFusivel
	if not fuse then
		return
	end

	fuseCarrier = player
	player:SetAttribute("LevandoFusivel", true)
	fuse.Transparency = 1
	Remotes.LobbyMessage:FireClient(player, "Fusível reserva no bolso. A caixa fica na parede, do lado de fora.")
end

local function installFuse(player: Player): (boolean, string?)
	if not canAct(player, hosts.Fusivel) then
		return false, "Voce se afastou da caixa."
	end
	if getFlag("FusivelInstalado") then
		return false, "O fusivel ja foi instalado."
	end
	if player:GetAttribute("LevandoFusivel") ~= true or fuseCarrier ~= player then
		return false, "Falta o fusivel."
	end

	player:SetAttribute("LevandoFusivel", nil)
	fuseCarrier = nil
	setAttr("FusivelInstalado", true)

	-- O fusível reaparece encaixado no soquete da caixa.
	local fuse = hosts.PegarFusivel
	local box = hosts.Fusivel
	if fuse and box then
		fuse.Transparency = 0
		fuse.CFrame = box.CFrame * CFrame.new(0, 0.4, -0.45) * CFrame.Angles(0, 0, math.rad(90))
	end
	Remotes.LobbyMessage:FireClient(player, "Fusível instalado. Dá pra dar partida no gerador.")
	print(string.format("[RadioSite] %s instalou o fusível.", player.Name))
	return true, nil
end

local function onOpenFuse(player: Player)
	if not canAct(player, hosts.Fusivel) or getFlag("FusivelInstalado") then
		return
	end
	Remotes.TransmissionMinigame:FireClient(
		player,
		"OpenFuse",
		player:GetAttribute("LevandoFusivel") == true and fuseCarrier == player
	)
end

local function onStarter(player: Player)
	if not canAct(player, hosts.Partida) then
		return
	end

	if getFlag("GeradorLigado") then
		setGenerator(false, "O gerador foi desligado.")
		print(string.format("[RadioSite] %s desligou o gerador.", player.Name))
		return
	end
	if isSabotaged() then
		Remotes.LobbyMessage:FireClient(player, "Tem cabo cortado aqui. Repare antes de dar partida.")
		return
	end
	if not getFlag("FusivelInstalado") then
		Remotes.LobbyMessage:FireClient(player, "Sem fusível na caixa, o gerador não arranca.")
		return
	end
	if getNumber("Combustivel") <= 0 then
		Remotes.LobbyMessage:FireClient(player, "Tanque seco. Despeje um galão primeiro.")
		return
	end

	setGenerator(true)
	tellMonster("Um gerador acabou de ligar na estação de rádio.")
	WeaponSystem.NoiseMade:Fire((engine or hosts.Partida :: BasePart).Position)
	print(string.format("[RadioSite] %s ligou o gerador.", player.Name))
end

local function onPanel(player: Player)
	if not canAct(player, hosts.Painel) then
		return
	end
	Remotes.TransmissionMinigame:FireClient(player, "OpenPanel")
	if getFlag("PainelAtivo") then
		return
	end
	if not getFlag("GeradorLigado") then
		Remotes.LobbyMessage:FireClient(player, "O painel está morto. Ligue o gerador.")
		return
	end
	if not piecesInstalled() then
		Remotes.LobbyMessage:FireClient(player, "Faltam peças no rack: antena, bateria e transmissor.")
		return
	end

	setAttr("PainelAtivo", true)
	Remotes.LobbyMessage:FireClient(player, "Transmissor energizado. Use o rádio na mesa.")
	print(string.format("[RadioSite] %s ativou o painel.", player.Name))
end

local function onSignal(player: Player)
	if not canAct(player, hosts.Socorro) then
		return
	end
	if getFlag("SocorroEnviado") then
		return
	end
	if not getFlag("PainelAtivo") then
		Remotes.LobbyMessage:FireClient(player, "O rádio está sem energia. Ative o painel primeiro.")
		return
	end
	if signalPlayer == player then
		return
	end

	signalPlayer = player
	setAttr("SocorroEmAndamento", true)
	Remotes.LobbyMessage:FireClient(player, "Transmitindo. Fique no rádio até o fim.")
	tellMonster("Alguém começou a transmitir um pedido de socorro.")
	print(string.format("[RadioSite] %s começou a transmitir o pedido de socorro.", player.Name))
end

local function abortSignal(message: string?)
	if signalPlayer == nil then
		return
	end
	local who = signalPlayer
	signalPlayer = nil
	setAttr("SocorroEmAndamento", false)
	if message and who and who.Parent == Players then
		Remotes.LobbyMessage:FireClient(who, message)
	end
end

local function completeSignal(player: Player)
	signalPlayer = nil
	signalProgress = 100
	setAttr("SocorroEmAndamento", false)
	setAttr("SocorroEnviado", true)
	setAttr("SinalProgresso", 100)
	Remotes.ObjectiveProgress:FireAllClients("RadioSocorro", 100, 100)
	tellEveryone("Pedido de socorro enviado. O resgate está a caminho.")
	RadioObjective.CompleteRescueCall(player)
	print(string.format("[RadioSite] %s completou o pedido de socorro.", player.Name))
end

--------------------------------------------------------------------------------
-- Prompts (criados a partir do Attribute "InteracaoRadio")
--------------------------------------------------------------------------------

type PromptSpec = {
	name: string,
	action: string,
	object: string,
	hold: number,
	handler: (Player) -> (),
}

local PROMPT_SPECS: { [string]: PromptSpec } = {
	Abastecer = { name = "AbastecerGerador", action = "Abastecer", object = "Gerador", hold = CFG.HoldAbastecer, handler = onRefuel },
	Partida = { name = "LigarGerador", action = "Ligar gerador", object = "Gerador", hold = CFG.HoldPartida, handler = onStarter },
	Fusivel = { name = "InstalarFusivel", action = "Abrir", object = "Caixa de fusíveis", hold = 0, handler = onOpenFuse },
	PegarFusivel = { name = "PegarFusivel", action = "Pegar", object = "Fusível reserva", hold = 0, handler = onTakeFuse },
	Painel = { name = "AtivarPainel", action = "Ativar painel", object = "Painel de controle", hold = CFG.HoldPainel, handler = onPanel },
	Socorro = { name = "EnviarSocorro", action = "Enviar socorro", object = "Rádio de emergência", hold = 0, handler = onSignal },
}

local function ensurePrompt(host: BasePart, key: string): ProximityPrompt?
	local spec = PROMPT_SPECS[key]
	if not spec then
		return nil
	end
	local existing = host:FindFirstChild(spec.name)
	local prompt = if existing and existing:IsA("ProximityPrompt") then existing else Instance.new("ProximityPrompt")
	prompt.Name = spec.name
	prompt.ActionText = spec.action
	prompt.ObjectText = spec.object
	prompt.HoldDuration = spec.hold
	prompt.MaxActivationDistance = math.max(4, CFG.AlcanceInteracao - 2)
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.ClickablePrompt = true
	prompt.Enabled = false
	prompt.Parent = host
	prompt.Triggered:Connect(spec.handler)
	return prompt
end

local function refreshPrompts()
	local sent = getFlag("SocorroEnviado")
	local running = getFlag("GeradorLigado")
	local hasFuse = getFlag("FusivelInstalado")
	local sabotaged = isSabotaged()
	local fuel = getNumber("Combustivel")

	local refuel = prompts.Abastecer
	if refuel then
		refuel.Enabled = not sent and fuel < CFG.CombustivelMaximo and (nearestFullCan() ~= nil or anyPlayerCarriesGasolina())
	end

	local starter = prompts.Partida
	if starter then
		starter.ActionText = if running then "Desligar gerador" else "Ligar gerador"
		starter.Enabled = not sent and (running or (hasFuse and fuel > 0 and not sabotaged))
	end

	local install = prompts.Fusivel
	if install then
		install.Enabled = not sent and not hasFuse
	end

	local take = prompts.PegarFusivel
	if take then
		take.Enabled = not hasFuse and fuseCarrier == nil
	end

	local panel = prompts.Painel
	if panel then
		panel.Enabled = not sent and not getFlag("PainelAtivo") and running and piecesInstalled() and not sabotaged
	end

	local signal = prompts.Socorro
	if signal then
		signal.Enabled = not sent and getFlag("PainelAtivo") and signalPlayer == nil
	end
end

--------------------------------------------------------------------------------
-- Coleta das Parts do local + efeitos
--------------------------------------------------------------------------------

local canHome: { [BasePart]: { cf: CFrame, color: Color3 } } = {}

local function collect(model: Model)
	table.clear(hosts)
	table.clear(cans)
	table.clear(beacons)
	table.clear(powered)
	table.clear(canHome)
	engine = nil
	exhaust = nil

	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local key = d:GetAttribute("InteracaoRadio")
		if type(key) == "string" then
			hosts[key] = d
		end
		if d:GetAttribute("GalaoCombustivel") == true then
			table.insert(cans, d)
			canHome[d] = { cf = d.CFrame, color = d.Color }
		end
		if d:GetAttribute("BalizaRadio") == true then
			table.insert(beacons, d)
		end
		if d:GetAttribute("LuzRadio") == true then
			table.insert(powered, { part = d, material = d.Material, color = d.Color })
		end
		if d:GetAttribute("MotorGerador") == true then
			engine = d
		end
		if d:GetAttribute("EscapeGerador") == true then
			exhaust = d
		end
	end
end

local function setupEffects()
	local body = engine
	if body then
		local existing = body:FindFirstChild("SomGerador")
		local sound = if existing and existing:IsA("Sound") then existing else Instance.new("Sound")
		sound.Name = "SomGerador"
		sound.SoundId = AssetRegistry.Sounds.RadioSite.Gerador
		sound.Looped = true
		sound.Volume = 0.9
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 18
		-- Bem alto de propósito: o gerador é um chamariz audível de longe.
		sound.RollOffMaxDistance = 320
		sound.Parent = body
		engineSound = sound
	end

	-- Sons do console: o rádio energizado (loop a partir do painel) e o
	-- pedido de socorro indo ao ar (loop durante a canalização).
	local console = hosts.Socorro
	if console then
		local existingRadio = console:FindFirstChild("SomRadio")
		local radio = if existingRadio and existingRadio:IsA("Sound") then existingRadio else Instance.new("Sound")
		radio.Name = "SomRadio"
		radio.SoundId = AssetRegistry.Sounds.RadioSite.RadioLigado
		radio.Looped = true
		radio.Volume = 0.55
		radio.RollOffMode = Enum.RollOffMode.InverseTapered
		radio.RollOffMinDistance = 8
		radio.RollOffMaxDistance = 70
		radio.Parent = console
		radioSound = radio

		local existingCall = console:FindFirstChild("SomSocorro")
		local call = if existingCall and existingCall:IsA("Sound") then existingCall else Instance.new("Sound")
		call.Name = "SomSocorro"
		call.SoundId = AssetRegistry.Sounds.RadioSite.PedidoSocorro
		call.Looped = true
		call.Volume = 0.85
		call.RollOffMode = Enum.RollOffMode.InverseTapered
		call.RollOffMinDistance = 10
		-- Mais longe que o rádio parado: o chamado no ar dá pra ouvir de fora
		-- do abrigo, e é assim que o Monstro sabe que tem alguém no console.
		call.RollOffMaxDistance = 140
		call.Parent = console
		callSound = call
	end

	local pipe = exhaust
	if pipe then
		local existing = pipe:FindFirstChild("Fumaca")
		local emitter = if existing and existing:IsA("ParticleEmitter") then existing else Instance.new("ParticleEmitter")
		emitter.Name = "Fumaca"
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromRGB(58, 58, 60))
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(1, 4.5),
		})
		emitter.Rate = 12
		emitter.Lifetime = NumberRange.new(2.5, 4)
		emitter.Speed = NumberRange.new(5, 8)
		emitter.SpreadAngle = Vector2.new(12, 12)
		emitter.Acceleration = Vector3.new(1, 3, 0)
		emitter.Enabled = false
		emitter.Parent = pipe
		smoke = emitter
	end
end

--------------------------------------------------------------------------------
-- Loop: combustível, baliza, ruído e a canalização do socorro
--------------------------------------------------------------------------------

-- Checagem silenciosa (canAct manda mensagem; isto roda todo tick).
local function stillTransmitting(player: Player): boolean
	if player.Parent ~= Players or player:GetAttribute("Role") ~= GameConfig.Roles.Survivor then
		return false
	end
	if player:GetAttribute("Eliminado") == true or player:GetAttribute("Amarrado") == true then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if character:GetAttribute("PowerStunned") == true or character:GetAttribute("GrabLocked") == true then
		return false
	end
	return distanceTo(player, hosts.Socorro) <= CFG.SinalRaio
end

local function updateBeacons(now: number)
	local running = getFlag("GeradorLigado")
	-- Sem energia a baliza ainda pisca devagar (bateria de emergência): é o
	-- ponto de referência que faz o jogador achar a estação no escuro.
	local period = if running then 1.6 else 3.4
	local duty = if running then 0.5 else 0.22
	local on = (now % period) < period * duty

	for _, lamp in beacons do
		if not lamp.Parent then
			continue
		end
		lamp.Color = if on then Color3.fromRGB(255, 62, 52) else Color3.fromRGB(72, 16, 14)
		lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		local light = lamp:FindFirstChild("LuzBaliza")
		if light and light:IsA("PointLight") then
			light.Enabled = on
			light.Brightness = if running then 3 else 1.2
		end
	end
end

-- Liga/desliga os sons do console a partir do estado. Fica num lugar só (e
-- roda no tique) em vez de espalhar Play/Stop por toda transição de estado --
-- assim nenhum caminho de saída (sabotagem, combustível acabando, reset)
-- esquece de calar o rádio.
local function syncSounds()
	local radio = radioSound
	if radio then
		local shouldPlay = getFlag("PainelAtivo")
		if shouldPlay ~= radio.IsPlaying then
			if shouldPlay then
				radio:Play()
			else
				radio:Stop()
			end
		end
	end

	local call = callSound
	if call then
		local shouldPlay = signalPlayer ~= nil
		if shouldPlay ~= call.IsPlaying then
			if shouldPlay then
				call:Play()
			else
				call:Stop()
			end
		end
	end
end

local function step(dt: number)
	local now = Workspace:GetServerTimeNow()
	updateBeacons(now)

	-- Combustível queimando.
	if getFlag("GeradorLigado") then
		local fuel = math.max(0, getNumber("Combustivel") - dt)
		setAttr("Combustivel", fuel)
		if fuel <= 0 then
			setGenerator(false, "O gerador engasgou e morreu: acabou o combustível.")
		elseif now - lastNoise >= CFG.IntervaloRuido then
			lastNoise = now
			noiseTicks += 1
			local source = engine or hosts.Partida
			if source then
				WeaponSystem.NoiseMade:Fire(source.Position)
			end
			-- O ruído em si vai todo tique (pro gancho NoiseMade e pro som);
			-- o aviso escrito só de vez em quando, senão vira spam.
			if noiseTicks % 3 == 1 then
				tellMonster("O gerador da estação de rádio continua roncando.")
			end
		end
	end

	-- Canalização do pedido de socorro.
	if not getFlag("SocorroEnviado") then
		local who = signalPlayer
		local transmitting = false
		if who then
			if not getFlag("PainelAtivo") or not getFlag("GeradorLigado") or isSabotaged() then
				abortSignal("A transmissão caiu junto com a energia.")
			elseif not stillTransmitting(who) then
				abortSignal("Você saiu do rádio. A transmissão parou.")
			else
				transmitting = true
			end
		end

		local before = signalProgress
		if transmitting then
			signalProgress = math.min(100, signalProgress + (100 / CFG.SinalDuracao) * dt)
		elseif signalProgress > 0 then
			signalProgress = math.max(0, signalProgress - CFG.SinalDecaimento * dt)
		end

		if signalProgress >= 100 and who then
			completeSignal(who)
		elseif signalProgress ~= before then
			setAttr("SinalProgresso", math.floor(signalProgress))
			if now - lastProgressSent >= PROGRESS_INTERVAL then
				lastProgressSent = now
				Remotes.ObjectiveProgress:FireAllClients("RadioSocorro", math.floor(signalProgress), 100)
			end
		end
	end

	syncSounds()
	refreshPrompts()
end

--------------------------------------------------------------------------------
-- Vigias: morte de quem carrega o fusível / transmite, e sabotagem
--------------------------------------------------------------------------------

local watchedCharacters: { [Model]: boolean } = {}

local function watchCharacter(player: Player, character: Model)
	if watchedCharacters[character] then
		return
	end
	watchedCharacters[character] = true

	local function onHumanoid(humanoid: Humanoid)
		humanoid.Died:Once(function()
			watchedCharacters[character] = nil
			if signalPlayer == player then
				abortSignal(nil)
			end
			if fuseCarrier == player then
				-- O fusível cai onde o portador morreu: dá pra recuperar.
				local root = character:FindFirstChild("HumanoidRootPart")
				dropFuse(if root and root:IsA("BasePart") then root.Position else nil)
				tellEveryone("Quem levava o fusível caiu. Ele ficou no chão.")
			end
		end)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		onHumanoid(humanoid)
	else
		character.ChildAdded:Connect(function(child)
			if child:IsA("Humanoid") then
				onHumanoid(child)
			end
		end)
	end
end

local function watchPlayer(player: Player)
	if player.Character then
		watchCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
end

local function watchSabotage()
	local body = engine
	if body then
		body:GetAttributeChangedSignal("Sabotado"):Connect(function()
			if body:GetAttribute("Sabotado") == true then
				setGenerator(false, "Sabotaram o gerador da estação de rádio.")
			end
		end)
	end
	local panel = hosts.Painel
	if panel then
		panel:GetAttributeChangedSignal("Sabotado"):Connect(function()
			if panel:GetAttribute("Sabotado") == true then
				setAttr("PainelAtivo", false)
				abortSignal("Sabotaram o painel. A transmissão caiu.")
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--[[
	ApplyPowerRepair(player)
	Gancho pra SurvivorPowerSystem ("Conserto Relâmpago"): dá um empurrão
	instantâneo (GameConfig.RadioSite.PowerBoostPercent) no chamado de
	socorro em andamento. Só funciona em quem ESTÁ transmitindo agora
	(mesmo contrato de antes: a habilidade acelera uma barra contínua que
	você já está segurando, não teleporta progresso de fora). Devolve a
	Part do console pro VFX da habilidade, ou nil se não deu.
]]
function RadioSiteSystem.ApplyPowerRepair(player: Player): BasePart?
	if signalPlayer ~= player or getFlag("SocorroEnviado") or not stillTransmitting(player) then
		return nil
	end

	signalProgress = math.min(100, signalProgress + CFG.PowerBoostPercent)
	setAttr("SinalProgresso", math.floor(signalProgress))
	Remotes.ObjectiveProgress:FireAllClients("RadioSocorro", math.floor(signalProgress), 100)

	if signalProgress >= 100 then
		completeSignal(player)
	end
	return hosts.Socorro
end

--[[
	Reset()
	Volta a estação pro estado de início de rodada: sem combustível, sem
	fusível, gerador desligado, galões cheios de novo. RoundManager chama no
	preparo da partida.
]]
function RadioSiteSystem.Reset()
	if not station then
		return
	end

	setGenerator(false)
	setLights(false)
	setAttr("Combustivel", 0)
	setAttr("FusivelInstalado", false)
	setAttr("PainelAtivo", false)
	setAttr("SocorroEmAndamento", false)
	setAttr("SocorroEnviado", false)
	setAttr("SinalProgresso", 0)
	signalPlayer = nil
	signalProgress = 0

	for _, player in Players:GetPlayers() do
		player:SetAttribute("LevandoFusivel", nil)
	end
	fuseCarrier = nil
	dropFuse(nil)

	for _, can in cans do
		local home = canHome[can]
		if can.Parent and home then
			can:SetAttribute("Cheio", true)
			can.CFrame = home.cf
			can.Color = home.color
		end
	end

	if engine then
		engine:SetAttribute("Sabotado", false)
	end
	local panel = hosts.Painel
	if panel then
		panel:SetAttribute("Sabotado", false)
	end

	Remotes.ObjectiveProgress:FireAllClients("RadioSocorro", 0, 100)
	syncSounds()
	refreshPrompts()
end

function RadioSiteSystem.Init()
	if initialized then
		return
	end

	local ilha = Workspace:FindFirstChild("Ilha")
	local model = ilha and ilha:FindFirstChild("TorreDeRadio")
	if not (model and model:IsA("Model")) then
		warn("[RadioSiteSystem] Sem Workspace.Ilha.TorreDeRadio. Rode Tools/RadioTowerGenerator.Build() no Studio e salve.")
		return
	end

	initialized = true
	station = model :: Model
	collect(model :: Model)

	local missing: { string } = {}
	for key in PROMPT_SPECS do
		local host = hosts[key]
		if host then
			prompts[key] = ensurePrompt(host, key) :: ProximityPrompt
		else
			table.insert(missing, key)
		end
	end
	if #missing > 0 then
		warn(string.format(
			"[RadioSiteSystem] A estação salva não tem os pontos: %s. Regere com Tools/RadioTowerGenerator.Build().",
			table.concat(missing, ", ")
		))
	end

	local fuse = hosts.PegarFusivel
	fuseHome = if fuse then fuse.CFrame else nil
	setupEffects()
	watchSabotage()

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		if signalPlayer == player then
			abortSignal(nil)
		end
		if fuseCarrier == player then
			dropFuse(nil)
		end
	end)

	Remotes.TransmissionMinigame.OnServerEvent:Connect(function(player: Player, action: unknown)
		if action ~= "InstallFuse" then
			return
		end
		local success, reason = installFuse(player)
		Remotes.TransmissionMinigame:FireClient(player, "FuseResult", success, reason)
	end)

	RadioSiteSystem.Reset()

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < UPDATE_INTERVAL then
			return
		end
		local slice = elapsed
		elapsed = 0
		step(slice)
	end)

	print("[RadioSiteSystem] Estação de rádio pronta: combustível -> fusível -> gerador -> painel -> socorro.")
end

return RadioSiteSystem
