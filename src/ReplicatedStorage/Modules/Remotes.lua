--!strict
--[[
	Remotes
	Ponto único de acesso aos RemoteEvents de "Náufragos".

	Os RemoteEvents em si são instâncias reais definidas em
	src/ReplicatedStorage/Remotes/*.model.json (sincronizadas pelo Rojo direto
	no ReplicatedStorage.Remotes, sem precisar de script para criá-las).
	Este módulo só referencia essas instâncias e documenta o contrato de cada
	uma, porque arquivo .model.json (JSON) não aceita comentário.

	Uso:
		local Remotes = require(game.ReplicatedStorage.Modules.Remotes)
		Remotes.SabotageAction:FireServer(sabotageType)

	Regra geral: nomes e formatos dos parâmetros abaixo são um contrato entre
	client e server. Se mudar a assinatura de um remote, atualize o comentário
	correspondente.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Timeout + error alto de propósito: sem isso, se o projeto não tiver sido
-- sincronizado (rojo build/serve) e um Remote não existir, TODO script que
-- faz `require(Remotes)` travaria pra sempre em silêncio, sem nenhum erro
-- no Output -- e como quase todo módulo do jogo depende deste arquivo,
-- o jogo inteiro pareceria simplesmente "não fazer nada".
local WAIT_TIMEOUT = 10

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes", WAIT_TIMEOUT)
if not RemotesFolder then
	error(
		"[Remotes] Folder 'ReplicatedStorage.Remotes' não encontrado. "
			.. "Rode 'rojo build -o Meujogo.rbxlx' de novo (ou confira se 'rojo serve' está conectado no Studio).",
		0
	)
end

local function getRemote(name: string): RemoteEvent
	local remote = (RemotesFolder :: Instance):WaitForChild(name, WAIT_TIMEOUT)
	if not remote then
		error(
			string.format(
				"[Remotes] RemoteEvent '%s' não encontrado em ReplicatedStorage.Remotes. "
					.. "Rode 'rojo build -o Meujogo.rbxlx' de novo (ou confira se 'rojo serve' está conectado no Studio).",
				name
			),
			0
		)
	end
	return remote :: RemoteEvent
end

local Remotes = {}

-- C -> S: Tool equipada, sem dano/alvo/alcance enviados pelo cliente.
-- Somente WeaponSystem atende; pistola mantém FirearmShoot.
Remotes.WeaponAttack = getRemote("WeaponAttack")

-- S -> C somente: atacante, chave da arma, posicao de impacto, atordoou.
-- WeaponImpactController so apresenta confirmacoes feitas pelo servidor.
Remotes.WeaponImpact = getRemote("WeaponImpact")

-- S -> C SOMENTE para monstros vivos/ativos que detectaram o som.
-- (noisePosition: Vector3, intensity: number). Sem identidade/alvo/posição futura.
-- Não possui OnServerEvent: só sistemas do servidor podem produzir ruído.
Remotes.NoiseDetected = getRemote("NoiseDetected")

-- S -> C SOMENTE ao monstro ativo: (monsterCharacter, snapshot completo).
-- Entradas: { player, character, strength, bpm, tension }. Ausência inicia fade.
-- Sem OnServerEvent; medo/alcance nunca são informados pelo cliente.
Remotes.HeartbeatDetected = getRemote("HeartbeatDetected")

-- C -> S: "Aim", tool, unitDirection | "Toggle", tool, enabled, unitDirection, sequence.
-- No hit, target, origin, battery or damage is accepted from a client.
-- S -> C: "State", tool, enabled, battery, sequence (toggle acknowledgement).
-- C -> S: "Burst", tool, nil, unitDirection, increasingSequence.
-- S -> C (shooter only): "BurstResult", tool, accepted, Hit/Miss/rejection, sequence.
-- Server attributes carry FlashBurstAt/ReadyAt and victim-only blind/stun state.
Remotes.Flashlight = getRemote("Flashlight")

-- C -> S: slot (1 | 2), no target/character/cooldown from client.
-- S -> C: "Rejected", reason | "Direction", powerId, localUnitDirection, endsAt.
-- Cooldowns replicate as Player.SurvivorPowerReadyAt1/2 (GetServerTimeNow).
Remotes.UseSurvivorPower = getRemote("UseSurvivorPower")
-- S -> C only: powerId, character?, position, duration, phase; nearby clients.
Remotes.SurvivorPowerFX = getRemote("SurvivorPowerFX")

-- Apagão do Abismo (habilidade do Monstro).
-- C -> S: "Use" -- só isso. Nenhum alvo, raio, duração ou cooldown vem do
--   cliente; o servidor lê a área UMA vez, no instante da ativação.
-- S -> C: "Cast", casterCharacter, position -- para todos (VFX de mundo);
--         "Hit", duration, endsAt          -- só para quem foi registrado;
--         "End"                            -- fim do efeito daquela vítima;
--         "Result", caughtCount            -- retorno só para o Monstro;
--         "Rejected", reason               -- só para o Monstro.
-- Ver server/AbyssBlackout.lua e docs/ApagaoDoAbismo.md.
Remotes.AbyssBlackout = getRemote("AbyssBlackout")

-- Somente Server -> Client: ("Trip", character, duration). Apresentação do
-- hook autoritativo do Fear; não existe listener OnServerEvent.
Remotes.FearPresentation = getRemote("FearPresentation")

-- Client -> Server: "Sync", "Ready", "Leave", "Skin"/"Perk" + id.
-- Server -> Client: snapshot da sala (state, endsAt, members, roster).
Remotes.WaitingRoom = getRemote("WaitingRoom")

-- C -> S: token numérico do character atual. O cliente só confirma depois
-- de câmera, HumanoidRootPart e controlador de movimento estarem ligados ao
-- corpo novo. O servidor valida character + token antes de iniciar o teleporte.
Remotes.CharacterPresentationReady = getRemote("CharacterPresentationReady")

-- Opcao secreta de teste local: cliente autorizado aperta M e pede ao servidor
-- para vestir o rig Workspace.R6 como Character, sem expor isso para todos.
Remotes.TestRigSwap = getRemote("TestRigSwap")

--------------------------------------------------------------------------------
-- SabotageAction
-- Disparado por: cliente do Espião, ao interagir com um objeto Sabotável
--   (ProximityPrompt em src/client/SabotageProximity.client.luau).
-- Client -> Server (FireServer):
--   target: Instance       -- objeto com Attribute "Sabotavel" == true
-- Server (SabotageSystem.lua) valida Role == Espiao, cooldown
--   (GameConfig.Spy.SabotageCooldownDefault) e o alvo; se tudo ok, define
--   target:SetAttribute("Sabotado", true).
-- Não há retransmissão por este remote: Attributes replicam sozinhos para
--   todos os clientes, então quem precisar reagir (ex: objetivo do Rádio)
--   escuta target:GetAttributeChangedSignal("Sabotado") diretamente.
-- Se a validação falhar (não é Espiao, alvo inválido, cooldown ativo), a
--   ação é rejeitada em silêncio: nada é enviado de volta ao cliente.
--------------------------------------------------------------------------------
Remotes.SabotageAction = getRemote("SabotageAction")

--------------------------------------------------------------------------------
-- LethalAbilityUsed
-- Disparado por: cliente do Espião, ao usar a habilidade letal contra um
--   alvo a curto alcance (cooldown: GameConfig.Spy.LethalCooldown = 180s).
-- Client -> Server (FireServer):
--   target: Player          -- jogador-alvo
-- Server (LethalAbility.lua) valida Role == Espiao, cooldown e alcance
--   (8 studs); se tudo ok, executa o alvo pelo DamageSystem, preserva o
--   cadáver durante a apresentação e dispara PlayerKilled para todos os
--   clientes -- este remote não é retransmitido.
-- Se a validação falhar (não é Espiao, fora de alcance, cooldown ativo,
--   alvo já eliminado), a ação é rejeitada em silêncio. A morte passa pelo
--   DamageSystem, portanto também dispara Humanoid.Died, animação e tela.
--------------------------------------------------------------------------------
Remotes.LethalAbilityUsed = getRemote("LethalAbilityUsed")

-- PlayerKilled
-- Disparado por: servidor, quando um jogador morre (Monstro, Espião ou hazard).
-- Server -> Clients (FireAllClients):
--   victimUserId: number
--   killerUserId: number?  -- nil se morte não teve autor direto (ex: ambiente)
--   cause: string          -- ex: "Monstro", "Espiao", "Ambiente"
-- Recebido por: todos os clientes (killfeed, efeitos, atualização de HUD).
--------------------------------------------------------------------------------
Remotes.PlayerKilled = getRemote("PlayerKilled")

--------------------------------------------------------------------------------
-- MonsterAttack
-- Combate do Monstro (client/MonsterController <-> server/MonsterCombat).
-- Client -> Server (FireServer): sem argumentos.
--   O cliente do Monstro pede um golpe (botão esquerdo). O servidor valida
--   Role == "Monstro", vivo, partida ativa e cooldown (GameConfig.Monster.
--   Attack.Cooldown), faz um hitbox em cone à frente do HumanoidRootPart
--   (Range / ConeCos) e aplica dano por DamageSystem (Cause = "Monstro").
-- Server -> Client (FireClient):
--   ("hit", hitCount: number)           -> só pro Monstro: quantos acertou
--     (feedback de câmera/som no golpe que conectou).
--   ("knockback", fromPosition: Vector3) -> pra cada vítima: empurrão
--     aplicado no PRÓPRIO cliente da vítima (network ownership), pra o
--     "pop" do golpe ficar consistente.
--------------------------------------------------------------------------------
Remotes.MonsterAttack = getRemote("MonsterAttack")

--------------------------------------------------------------------------------
-- MonsterGrab
-- Client -> Server: sem argumentos. O cliente apenas pede a habilidade.
-- O servidor valida papel/estado/cooldown, encontra a vitima por alcance,
-- cone e linha de visao e executa toda a sincronizacao.
-- Server -> Client: ("Rejected", reason) somente para feedback local.
--------------------------------------------------------------------------------
Remotes.MonsterGrab = getRemote("MonsterGrab")

-- C -> S: ("Start", nil, direção horizontal), ("Move", token, direção),
-- ("Stop", token). Nenhuma posição/velocidade é aceita. Estado, token e
-- cooldown replicam por Attributes. S -> C: ("Pass") ou ("Rejected", motivo).
Remotes.ShadowRush = getRemote("ShadowRush")

--------------------------------------------------------------------------------
-- MonsterTeleport
-- Poder de teleporte do Monstro (client/MonsterTeleportController <->
--   server/MonsterTeleport). Ver a sequência completa no cabeçalho de
--   MonsterTeleport.lua.
-- Client -> Server (FireServer):
--   aimPoint: Vector3   -- ponto mirado (câmera). É só uma SUGESTÃO: o
--     servidor clampa a distância (GameConfig.Monster.Teleport.Min/MaxRange),
--     faz raycast pro chão, checa rampa/limites/água/espaço livre e decide a
--     posição final. Cliente NUNCA teleporta sozinho.
-- Server -> Client (FireClient), só pro Monstro:
--   ("cooldown", readyAt: number)   -- cooldown iniciado (ativação aceita ou falha)
--   ("cancel", motivo: string)      -- destino inválido / habilidade cancelada
-- Validação que falha (não é Monstro, ocupado, cooldown ou partida parada) é
-- rejeitada em silêncio, exceto destino inválido (manda "cancel").
--------------------------------------------------------------------------------
Remotes.MonsterTeleport = getRemote("MonsterTeleport")

--------------------------------------------------------------------------------
-- RiftVFX
-- Apresentação da(s) fenda(s) do teleporte. O servidor manda por FireClient
--   SÓ pros jogadores a até GameConfig.Monster.Teleport.VFXBroadcastRadius da
--   fenda (jogador muito longe não recebe nada). O cliente
--   (client/RiftVFXController) constrói/anima/limpa a fenda com TweenService e
--   as partículas -- o servidor não controla efeito nenhum frame a frame.
-- Server -> Client (FireClient):
--   (op: string, data: table)
--     op "open":   data = { id, cframe: CFrame, width: number, kind: "entrada"|"destino" }
--     op "enter":  data = { id }                 -- monstro sendo engolido (puxa partículas + som)
--     op "emerge": data = { id }                 -- monstro emergindo (jato + som)
--     op "close":  data = { id }
--     op "cancel": data = { id }                 -- aborta a fenda no meio da abertura
-- Timings/escala/cores vêm de GameConfig.Monster.Teleport + Modules/RiftVFX
--   (os dois lados leem a mesma config -- nada hardcoded aqui).
--------------------------------------------------------------------------------
Remotes.RiftVFX = getRemote("RiftVFX")

--------------------------------------------------------------------------------
-- DetectSuspect
-- Usado nos DOIS sentidos, pelo mesmo remote (ver ConfrontSystem.lua).
-- Client -> Server (FireServer): pedido de leitura do Cristal Ancestral.
--   target: Player         -- suspeito apontado
--   Servidor exige: Tool com Attribute "CristalAncestral" equipada pelo
--   solicitante e alvo dentro de GameConfig.Confront.DetectRange.
-- Server -> Client (FireClient): resposta SÓ para quem pediu.
--   target: Player
--   isSpy: boolean         -- se target tem Role == "Espiao"
-- Pedido inválido (sem cristal, fora de alcance) é ignorado em silêncio:
--   nenhuma resposta é enviada.
--------------------------------------------------------------------------------
Remotes.DetectSuspect = getRemote("DetectSuspect")

--------------------------------------------------------------------------------
-- ConfrontKill
-- Disparado por: cliente que porta a Tool "ArmaRara", ao executar um
--   suspeito a curta distância (GameConfig.Confront.KillRange).
-- Client -> Server (FireServer):
--   target: Player
-- Servidor (ConfrontSystem.lua) valida arma equipada, alcance e alvo vivo;
--   se ok, elimina o alvo e dispara PlayerKilled com cause = "Confronto".
--   Se o alvo NÃO for o Espião, dispara também o hook interno
--   ConfrontSystem.PunicaoInocente (BindableEvent) -- este remote não é
--   retransmitido.
--------------------------------------------------------------------------------
Remotes.ConfrontKill = getRemote("ConfrontKill")

--------------------------------------------------------------------------------
-- CooldownUpdate
-- Disparado por: servidor, sempre que uma habilidade com cooldown do
--   próprio jogador é usada com sucesso (hoje: SabotageSystem, LethalAbility).
-- Server -> Client (FireClient), só para quem usou a habilidade:
--   abilityName: string    -- "Sabotagem" | "HabilidadeLetal"
--   readyAt: number        -- os.time() em que a habilidade libera de novo
-- Recebido por: apenas o próprio jogador (HUDController usa pra mostrar o
--   cooldown restante do Espião).
--------------------------------------------------------------------------------
Remotes.CooldownUpdate = getRemote("CooldownUpdate")

--------------------------------------------------------------------------------
-- CraftItem
-- Disparado por: cliente, ao pedir pra craftar um item (ver ItemRegistry.lua,
--   campo Craft -- hoje: LancaDeBambu, Tocha).
-- Client -> Server (FireServer):
--   itemId: string   -- chave em ItemRegistry.Items (ex: "Tocha")
-- Servidor confere os ingredientes no inventário pessoal; se faltar algo,
--   rejeita em silêncio. Se tiver, consome tudo de uma vez e entrega a Tool
--   (ToolFactory.lua) no Backpack. Este remote não é retransmitido -- quem
--   quiser saber que craftou algo escuta o próprio Backpack no cliente.
--------------------------------------------------------------------------------
Remotes.CraftItem = getRemote("CraftItem")

--------------------------------------------------------------------------------
-- RoundStateChanged
-- Disparado por: servidor, ao trocar de fase da partida
--   (fases e durações: GameConfig.Phases / GameConfig.PhaseOrder).
-- Server -> Clients (FireAllClients):
--   phase: string           -- "Queda" | "Exploracao" | "Corrida" | "Desfecho"
--   phaseEndsAt: number      -- os.time() previsto de término da fase
-- Recebido por: todos os clientes (atualiza timer e UI de fase).
--------------------------------------------------------------------------------
Remotes.RoundStateChanged = getRemote("RoundStateChanged")

--------------------------------------------------------------------------------
-- RoundEnded
-- Disparado por: servidor (RoundManager.lua), quando a partida termina de
--   vez -- é o par de fechamento do RoundStateChanged.
-- Server -> Clients (FireAllClients):
--   winner: string   -- "Sobreviventes" | "Monstro" | "Espiao" | "Ninguem"
--   reason: string   -- texto pronto explicando como terminou
-- Recebido por: todos os clientes. Hoje HUDController/ObjectivesController
--   usam pra ESCONDER a HUD (que só deve aparecer durante a partida, não no
--   Lobby) -- sem isso o cliente não teria como saber que acabou, porque
--   RoundManager.RoundEnded é um BindableEvent, só do lado do servidor.
--------------------------------------------------------------------------------
Remotes.RoundEnded = getRemote("RoundEnded")

--------------------------------------------------------------------------------
-- ObjectiveProgress
-- Disparado por: servidor, ao atualizar progresso de um objetivo da rodada
--   (ex: RadioObjective).
-- Server -> Clients (FireAllClients):
--   objectiveId: string     -- ex: "RadioPecas", "RadioCompleto",
--                               "TodasPecasInstaladas"
--   current: number
--   max: number
--   players: { Player }?    -- opcional; presente quando o objetivo precisa
--                               identificar quem participou (ex:
--                               (players pode identificar participantes)
-- Recebido por: todos os clientes (barra de progresso / resultado na UI).
--------------------------------------------------------------------------------
Remotes.ObjectiveProgress = getRemote("ObjectiveProgress")

--------------------------------------------------------------------------------
-- MapDiscovery
-- Disparado por: servidor (server/ItemDiscovery.lua), quando um jogador passa
--   perto o suficiente (GameConfig.MapDiscovery.Radius) de um item ainda não
--   descoberto POR ELE. Cada jogador tem seu próprio progresso de descoberta.
-- Server -> Client (FireClient), só para quem descobriu:
--   entry: {
--     key: string,          -- id estável da instância (nunca repete pro mesmo jogador)
--     x: number, z: number, -- posição no mundo
--     itemId: string?,      -- chave de ItemRegistry.Items, quando existir
--     category: string,     -- Modules/MapMarkers.Category (Firearm/Melee/...)
--     label: string?,       -- nome pra mostrar (ex: "Faca Improvisada")
--   }
-- Recebido por: client/DiscoveredItemsStore.lua (ModuleScript), consumido
--   pelos dois mapas (client/MonsterTeleportController e
--   client/SurvivorMapController) via Modules/IslandMapUI:AddDiscoveredItem.
--   Não existe direção Client -> Server neste remote.
--------------------------------------------------------------------------------
Remotes.MapDiscovery = getRemote("MapDiscovery")

--------------------------------------------------------------------------------
-- LobbyMessage
-- Disparado por: servidor (LobbyManager.lua), em resposta a uma interação
--   com o prompt "IniciarPartida" que não pôde ser atendida.
-- Server -> Client (FireClient), só para quem interagiu:
--   message: string    -- texto pronto pra mostrar (ex: "Faltam 3 jogadores...")
-- Recebido por: apenas o jogador que interagiu.
--------------------------------------------------------------------------------
Remotes.LobbyMessage = getRemote("LobbyMessage")

--------------------------------------------------------------------------------
-- ExtractionChoice
-- Embarque no helicóptero do resgate (server/ExtractionSystem.lua <->
-- client/ExtractionController.client.luau).
--
-- Server -> Client (FireClient), só pra quem embarcou:
--   "Abrir"    -- mostra as duas opções na tela (partir agora / esperar)
--   "Fechar"   -- esconde a UI (desembarcou, morreu, ou o voo começou)
--
-- Client -> Server (FireServer):
--   "Partir"   -- decolar agora
--   "Esperar"  -- fica a bordo e some com a UI; sair exige o prompt "Sair"
--
-- O servidor valida que quem mandou está REALMENTE a bordo; pedido de quem
-- não está é ignorado em silêncio.
--------------------------------------------------------------------------------
Remotes.ExtractionChoice = getRemote("ExtractionChoice")

--------------------------------------------------------------------------------
-- BoatControl
-- Barco de fuga (server/BoatSystem.lua <-> client/BoatController.client.luau).
-- O estado do barco (peças, motor, encalhe, piloto) vive em Attributes do
-- Model do barco, que replicam sozinhos; este remote só carrega o que não é
-- estado: o pedido do piloto e o início da cena de fuga.
--
-- Client -> Server (FireServer):
--   "Motor"   -- piloto liga/desliga o motor. O servidor confere que quem
--                mandou é o OCUPANTE do assento do piloto, a montagem, a
--                chave (na ignição ou no inventário dele), sabotagem e
--                encalhe. Pedido inválido volta como LobbyMessage com o motivo.
--
-- Server -> Client:
--   "Assento", boat: Model, role: "Piloto" | "Passageiro"  -- só pra quem sentou
--   "Saiu"                                                  -- levantou do barco
--   "Fuga", boat: Model, start: CFrame, speed: number, duration: number,
--           rescued: { number }  -- TODOS os clientes. `start` é o QuadroBarco
--           no instante em que cruzou o limite; cada cliente anima o barco
--           seguindo pro mar (o servidor o ancora) e quem está em `rescued`
--           (UserIds) ganha a câmera de cinema.
--
-- A física do barco NÃO passa por aqui: o piloto é dono de rede do conjunto
-- e o servidor valida a posição (anti-teleporte) a cada tique.
--------------------------------------------------------------------------------
Remotes.BoatControl = getRemote("BoatControl")

--------------------------------------------------------------------------------
-- FlyTest
-- Modo voar de teste (client/FlyTest.client.luau <-> server/FlyTest.lua).
-- Client -> Server (FireServer): flying: boolean -- ligou/desligou o voo.
-- O servidor deixa o personagem Invulneravel enquanto voa (e alguns segundos
-- depois do pouso). Só responde dentro do Studio e com GameConfig.Testing.Voar.
--------------------------------------------------------------------------------
Remotes.FlyTest = getRemote("FlyTest")

--------------------------------------------------------------------------------
-- DropItem
-- Disparado por: cliente (HotbarController.client.luau), ao pedir pra largar
--   uma Tool no chão (tecla G, ou o botão de largar no slot da hotbar).
-- Client -> Server (FireServer):
--   tool: Tool   -- a Tool a ser largada; precisa estar no Backpack OU no
--                   Character do próprio jogador nesse instante.
-- Servidor (DropItemSystem.lua) valida a posse, desequipa, joga a Tool no
--   Workspace à frente do personagem e pendura um ProximityPrompt "Pegar"
--   (mesmo contrato dos pickups de ItemSpawner.lua) pra qualquer um pegar de
--   volta. Pedido inválido (não é Tool, não é do jogador) é ignorado em
--   silêncio. Este remote não é retransmitido.
--------------------------------------------------------------------------------
Remotes.DropItem = getRemote("DropItem")

--------------------------------------------------------------------------------
-- TransmissionMinigame
-- Server -> Client:
--   "OpenFuse", hasFuse: boolean -- abre a caixa; o item so aparece se tiver.
--   "FuseResult", success: boolean, reason: string? -- resposta da instalacao.
--   "OpenPanel" -- abre a arte do painel; minigame do painel vira etapa futura.
-- Client -> Server:
--   "InstallFuse" -- servidor revalida papel, vida, distancia e posse.
--------------------------------------------------------------------------------
Remotes.TransmissionMinigame = getRemote("TransmissionMinigame")

--------------------------------------------------------------------------------
-- RepairMinigame
-- Reparo de precisão dos pontos reparáveis (server/RepairMinigameSystem.lua
--   <-> client/RepairMinigameController.client.luau). Ver docs/ReparoMinigame.md.
--
-- Server -> Client (FireClient), SÓ pra quem está reparando:
--   "Start", token: number, part: BasePart, label: string,
--            streak: number, required: number
--   "Test", token, test: RepairMinigameConfig.Test
--       Os parâmetros do teste (velocidade, centro, larguras, estilo) são
--       sorteados SÓ no servidor; o cliente desenha o marcador a partir deles.
--   "Result", token, testId: number,
--             grade: "Perfect"|"Green"|"Yellow"|"Red"|"Miss",
--             streak: number, required: number, stall: number, accuracy: number
--       O reparo só conclui com `required` acertos SEGUIDOS (verde/azul);
--       qualquer outra nota zera `streak`. `stall` = segundos até o próximo teste.
--   "Streak", token, streak: number, required: number  -- Conserto Relâmpago
--   "Stop", token, reason: string, completed: boolean, streak, required
--
-- Client -> Server (FireServer):
--   "Hold", token           -- confirma que ainda está segurando (~4 Hz)
--   "Release", token        -- soltou a tecla / botão: cancela
--   "Hit", token, testId: number, elapsed: number
--       `elapsed` é o instante do teste em que o jogador apertou, medido no
--       relógio do SERVIDOR (Workspace:GetServerTimeNow). O servidor só o
--       aceita se bater com a hora de chegada dentro de
--       RepairMinigameConfig.Scoring.MaxInputLag -- fora disso usa a chegada.
--
-- O CLIENTE NUNCA MANDA SEQUÊNCIA, NOTA, ALVO NEM RUÍDO. Token de sessão
--   descarta mensagem de um reparo anterior; distância, linha de visão,
--   papel, vida e estado da partida são revalidados a cada tique no servidor.
--------------------------------------------------------------------------------
Remotes.RepairMinigame = getRemote("RepairMinigame")

--------------------------------------------------------------------------------
-- GeneratorErrorSound
-- Som 3D do choque do gerador quando alguém erra o minigame de reparo dele
--   (server/GeneratorErrorSound.lua -> client/GeneratorErrorSoundController).
-- SOMENTE Server -> Client (FireClient), SÓ pra quem errou e pro Monstro vivo
--   dentro do alcance de GameConfig.RadioSite.ErroGerador.RollOffMaxDistance:
--   generator: BasePart   -- a Part do gerador (atributo MotorGerador)
-- Cada cliente cria o Sound LOCALMENTE como filho dessa Part (não replica, então
--   os outros sobreviventes não ouvem). Não existe OnServerEvent: o cliente não pede som.
--------------------------------------------------------------------------------
Remotes.GeneratorErrorSound = getRemote("GeneratorErrorSound")

--------------------------------------------------------------------------------
-- PERSONAGENS JOGÁVEIS
--   client/SurvivorSelectionController <-> server/CharacterStatsApplier
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- SelectCharacter
-- Client -> Server (FireServer):
--   "Select", characterId -- escolha tentativa, validada no servidor
--   "Confirm"             -- trava a escolha atual para aquele jogador
--   "Sync"                -- pede o snapshot atual somente para o remetente
-- O servidor valida fase, prazo, papel, disponibilidade e exclusividade.
-- Monstro recebe Jason automaticamente. No fim dos 30s, o servidor confirma
-- a escolha atual (ou um fallback livre) sem depender de mensagem do cliente.
--------------------------------------------------------------------------------
Remotes.SelectCharacter = getRemote("SelectCharacter")

--------------------------------------------------------------------------------
-- CharacterRoster
-- Server -> Clients, sempre que alguém escolhe/confirma/sai:
--   snapshot.state: "Selecting" | "Closed"
--   snapshot.endsAt: number (Workspace:GetServerTimeNow)
--   snapshot.roster: { [characterId]: UserId }       -- confirmados
--   snapshot.choices: { [UserId]: characterId }      -- escolhas atuais
--   snapshot.confirmed: { [UserId]: true }
--   snapshot.availability: { [characterId]: estado }
--------------------------------------------------------------------------------
Remotes.CharacterRoster = getRemote("CharacterRoster")

--------------------------------------------------------------------------------
-- SprintIntent
-- Client -> Server (FireServer):
--   holding: boolean   -- true enquanto o pacote de movimento está EM CORRIDA
--                         (IsSprinting local do HumanoidRootPart; sem o
--                         pacote, Shift apertado), false quando para.
-- É só a INTENÇÃO. Quem decide se o fôlego cai é o servidor
--   (server/StaminaSystem.lua), que também mede a velocidade real do
--   personagem. O fôlego volta pro cliente como Attributes "Stamina" e
--   "StaminaMax" no Player (replicam sozinhos, sem remote).
--------------------------------------------------------------------------------
Remotes.SprintIntent = getRemote("SprintIntent")

--------------------------------------------------------------------------------
-- OpenCrate
-- Client -> Server (FireServer):
--   crate: BasePart    -- a caixa que o jogador acionou (ProximityPrompt)
-- Servidor (server/LootCrateSystem.lua) valida distância e se a caixa ainda
--   não foi aberta, sorteia o loot com o peso da SORTE do personagem e
--   entrega os itens no Backpack.
-- Server -> Client (FireClient), só pra quem abriu:
--   itemIds: { string }  -- o que saiu (pra UI de "você achou X")
--------------------------------------------------------------------------------
Remotes.OpenCrate = getRemote("OpenCrate")

--------------------------------------------------------------------------------
-- DIGITAL'S OTS (client/OTSController <-> server/OTSFirearmService)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- FirearmShoot
-- Client -> Server: tool: Tool, aimPoint: Vector3, aiming: boolean, sequence: number.
-- Servidor valida posse, vida, espera/recarga, cadência e origem; gasta uma bala
-- e calcula o raycast, obstáculo, dano e efeitos. Cliente nunca escolhe o alvo.
-- Server -> Client: tool, sequence, accepted: boolean, magazine: number (ack da HUD).
--------------------------------------------------------------------------------
Remotes.FirearmShoot = getRemote("FirearmShoot")

--------------------------------------------------------------------------------
-- FirearmDamage: SOMENTE Server -> Client, hitmarker confirmado.
-- kind: "Hit" | "Head" | "Armor" | "HeadArmor".
-- Não aceita FireServer. Dano/morte passam pelo DamageSystem e Elimination.
--------------------------------------------------------------------------------
Remotes.FirearmDamage = getRemote("FirearmDamage")

--------------------------------------------------------------------------------
-- FirearmReload
-- Client -> Server: tool: Tool, action: "Start" | "Cancel" | "Marker", marker?: string.
-- Server -> Client: tool, state: "Start" | "Done" | "Cancelled", duration?: number.
-- Tempo e transferência de munição são do servidor. Markers sincronizam apenas
-- os sons/peças da animação; não concedem munição.
-- Desequipar/largar/morrer cancela e restaura o pente visível.
--------------------------------------------------------------------------------
Remotes.FirearmReload = getRemote("FirearmReload")

--------------------------------------------------------------------------------
-- FirearmFeed
-- Server -> Client (FireClient), só pro atirador:
--   kind: string        -- "Kill" | "Armour"
--   victimName: string
-- Alimenta o kill feed da HUD "Weapon".
--------------------------------------------------------------------------------
Remotes.FirearmFeed = getRemote("FirearmFeed")

--------------------------------------------------------------------------------
-- XP, ESTATÍSTICAS E RESULTADO DA PARTIDA
--   server/MatchStatsService + MatchRewardService + MatchResultsService
--   <-> client/XPNotificationController + MatchResultsController
--
-- OS DOIS REMOTES ABAIXO SÃO SOMENTE SERVER -> CLIENT.
-- Nenhum dos dois tem OnServerEvent conectado em lugar nenhum do projeto, e
-- não deve ganhar um. XP é 100% autoritativo do servidor: o cliente não pede,
-- não confirma e não influencia recompensa nenhuma -- ele só desenha o que
-- chega. Um FireServer aqui não é "ignorado em silêncio", ele literalmente
-- não tem ouvinte.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- MatchResults
-- Disparado por: servidor (MatchResultsService.FinalizeMatch), uma vez por
--   jogador, quando a partida termina e os resultados são congelados.
-- Server -> Client (FireClient), SÓ pro dono do relatório:
--   payload: MatchStatsTypes.ResultsPayload
--     Winner, Reason        -- mesmos valores do RoundEnded
--     Role                  -- papel DELE na partida
--     MatchXP               -- XP total DELE
--     PerformanceScore      -- pontuação de desempenho DELE
--     XPBreakdown           -- XP por categoria (Survival, Objectives, ...)
--     Actions               -- ações DELE, já AGRUPADAS por ação
--                              ("Acertou o Monstro" ×4 vira uma linha só)
--     Stats                 -- { Key, Label, Value } já formatados pra tela
--     Highlights            -- destaques da partida (públicos: nome + valor)
--     MVPUserId, IsMVP
-- Cada jogador recebe um payload DIFERENTE, montado a partir da sessão dele.
-- Estatística, histórico e XP de outro jogador NÃO entram no payload -- só os
-- destaques, que são o placar público da partida.
--------------------------------------------------------------------------------
Remotes.MatchResults = getRemote("MatchResults")

--------------------------------------------------------------------------------
-- MatchXPNotification
-- Disparado por: servidor (MatchRewardService), toda vez que uma concessão de
--   XP é APROVADA por todas as guardas (papel, cooldown, limite, teto, alvo
--   válido, janela da partida). Recusa nunca vira notificação.
-- Server -> Client (FireClient), SÓ pro jogador que ganhou/perdeu o XP:
--   payload: MatchStatsTypes.NotificationPayload
--     Id        -- identificador único; o cliente descarta repetição
--     ActionId  -- id estável da ação (chave de MatchRewardsConfig.Actions)
--     Label     -- descrição pronta ("Curou um aliado")
--     XP        -- positivo (ganho) ou negativo (penalidade)
--     Category  -- MatchStatsTypes.Category
--     Priority  -- 1..5; ordena a fila no cliente
-- São só esses seis campos: nenhuma tabela interna, nenhum total acumulado,
-- nenhum dado de outro jogador. Ninguém mais vê a notificação de ninguém.
-- A fila, o agrupamento de repetições, a animação e o som são 100% do
-- cliente (client/XPNotificationController); o servidor só confirma O QUE
-- aconteceu e QUANTO valeu.
--------------------------------------------------------------------------------
Remotes.MatchXPNotification = getRemote("MatchXPNotification")

return Remotes
