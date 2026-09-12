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

-- C -> S: "Aim", tool, unitDirection | "Toggle", tool, enabled, unitDirection, sequence.
-- No hit, target, origin, battery or damage is accepted from a client.
-- S -> C: "State", tool, enabled, battery, sequence (toggle acknowledgement).
Remotes.Flashlight = getRemote("Flashlight")

-- C -> S: slot (1 | 2), no target/character/cooldown from client.
-- S -> C: "Rejected", reason | "Direction", powerId, localUnitDirection, endsAt.
-- Cooldowns replicate as Player.SurvivorPowerReadyAt1/2 (GetServerTimeNow).
Remotes.UseSurvivorPower = getRemote("UseSurvivorPower")
-- S -> C only: powerId, character?, position, duration, phase; nearby clients.
Remotes.SurvivorPowerFX = getRemote("SurvivorPowerFX")

-- Somente Server -> Client: ("Trip", character, duration). Apresentação do
-- hook autoritativo do Fear; não existe listener OnServerEvent.
Remotes.FearPresentation = getRemote("FearPresentation")

-- Client -> Server: "Sync", "Ready", "Leave", "Skin"/"Perk" + id.
-- Server -> Client: snapshot da sala (state, endsAt, members, roster).
Remotes.WaitingRoom = getRemote("WaitingRoom")

-- Opcao secreta de teste local: cliente autorizado aperta M e pede ao servidor
-- para vestir o rig Workspace.R6 como Character, sem expor isso para todos.
Remotes.TestRigSwap = getRemote("TestRigSwap")

-- Teste secreto de calibração da Glock17. O servidor valida UserId, Tool
-- equipada e incrementos pequenos antes de mudar os Attributes do Grip.
Remotes.PistolGripTest = getRemote("PistolGripTest")

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
--   (8 studs); se tudo ok, "elimina" o alvo (placeholder: teleporta o
--   character para workspace.Eliminados e trava os controles) e dispara
--   PlayerKilled para todos os clientes -- este remote não é retransmitido.
-- Se a validação falhar (não é Espiao, fora de alcance, cooldown ativo,
--   alvo já eliminado), a ação é rejeitada em silêncio.
--------------------------------------------------------------------------------
Remotes.LethalAbilityUsed = getRemote("LethalAbilityUsed")

--------------------------------------------------------------------------------
-- PlayerRestrained
-- Disparado por: servidor, quando um jogador fica "amarrado"
--   (duração: GameConfig.Effects.AmarradoDuration = 90s).
-- Server -> Clients (FireAllClients):
--   targetUserId: number
--   isRestrained: boolean  -- true ao prender, false ao soltar/expirar
--   releasesAt: number?    -- os.time() em que solta sozinho (só quando isRestrained = true)
-- Recebido por: todos os clientes (trava animação/movimento local, atualiza UI).
--------------------------------------------------------------------------------
Remotes.PlayerRestrained = getRemote("PlayerRestrained")

--------------------------------------------------------------------------------
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
-- Validação que falha (não é Monstro, ocupado, cooldown, partida parada,
--   amarrado) é rejeitada em silêncio, exceto destino inválido (manda "cancel").
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
-- Servidor (CraftingSystem.lua) confere os ingredientes no inventário
--   pessoal (RaftObjective.GetMaterialCount); se faltar algo, rejeita em
--   silêncio. Se tiver, consome tudo de uma vez e entrega a Tool
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
--   (ex: RadioObjective, RaftObjective).
-- Server -> Clients (FireAllClients):
--   objectiveId: string     -- ex: "RadioPecas", "RadioCompleto",
--                               "TodasPecasInstaladas", "JangadaProgresso",
--                               "FugaJangada"
--   current: number
--   max: number
--   players: { Player }?    -- opcional; presente quando o objetivo precisa
--                               identificar quem participou (ex:
--                               "FugaJangada" -> jogadores a bordo)
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
-- PERSONAGENS JOGÁVEIS
--   client/CharacterSelectController <-> server/CharacterStatsApplier
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- SelectCharacter
-- Client -> Server (FireServer):
--   characterId: string   -- Id de Modules/CharacterData (ex: "SofiaRibeiro")
-- Servidor valida que o id existe e que NINGUÉM mais já escolheu esse
--   personagem nesta partida. Se ok, guarda a escolha e reemite o roster pra
--   todo mundo (CharacterRoster). Escolha inválida/tomada é ignorada em
--   silêncio -- o roster que o cliente já tem mostra o card desabilitado.
--   A escolha acontece depois do sorteio do papel. Monstro não usa este
--   remote: recebe Jason automaticamente. Depois de escolher, o servidor
--   fecha CharacterSelectOpen para evitar troca no meio da rodada.
--------------------------------------------------------------------------------
Remotes.SelectCharacter = getRemote("SelectCharacter")

--------------------------------------------------------------------------------
-- CharacterRoster
-- Server -> Clients (FireAllClients), sempre que alguém escolhe/troca/sai:
--   taken: { [characterId]: number }  -- id -> UserId de quem pegou
--   roundActive: boolean              -- true = partida rolando (a tela de
--                                        escolha fica escondida)
-- A UI usa isso pra desabilitar em tempo real os cards já tomados e marcar
--   qual é o SEU. Também é disparado só pra quem entra (FireClient) pra o
--   jogador novo receber o estado atual.
--------------------------------------------------------------------------------
Remotes.CharacterRoster = getRemote("CharacterRoster")

--------------------------------------------------------------------------------
-- SprintIntent
-- Client -> Server (FireServer):
--   holding: boolean   -- true quando aperta Shift, false quando solta
-- É só a INTENÇÃO. Quem decide se o fôlego cai é o servidor
--   (server/StaminaSystem.lua), que mede a velocidade real do personagem --
--   mentir "não estou correndo" não adianta, porque o gasto é validado pelo
--   movimento de verdade. O fôlego atual volta pro cliente como Attribute
--   "Stamina" no Player (replica sozinho, sem remote).
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
-- ARMAS DE FOGO (client/PistolController <-> FirearmServer)
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
-- FirearmHit: legado reservado, sem listener no servidor.
-- Efeitos agora nascem exclusivamente do raycast validado de FirearmShoot.
--------------------------------------------------------------------------------
Remotes.FirearmHit = getRemote("FirearmHit")

--------------------------------------------------------------------------------
-- FirearmDamage: SOMENTE Server -> Client, hitmarker confirmado.
-- kind: "Hit" | "Head" | "Armor" | "HeadArmor".
-- Não aceita FireServer. Dano/morte passam pelo DamageSystem e Elimination.
--------------------------------------------------------------------------------
Remotes.FirearmDamage = getRemote("FirearmDamage")

--------------------------------------------------------------------------------
-- FirearmReload
-- Client -> Server: tool: Tool, action: "Start" | "Cancel".
-- Server -> Client: tool, state: "Start" | "Done" | "Cancelled", duration?: number.
-- Tempo e transferência de munição são do servidor. Markers não concedem munição.
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

return Remotes
