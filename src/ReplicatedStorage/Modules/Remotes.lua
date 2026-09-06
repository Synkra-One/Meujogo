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
--                               "JangadaProgresso", "FugaJangada"
--   current: number
--   max: number
--   players: { Player }?    -- opcional; presente quando o objetivo precisa
--                               identificar quem participou (ex:
--                               "FugaJangada" -> jogadores a bordo)
-- Recebido por: todos os clientes (barra de progresso / resultado na UI).
--------------------------------------------------------------------------------
Remotes.ObjectiveProgress = getRemote("ObjectiveProgress")

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
--   Trocar de personagem antes da partida começar é permitido (libera o
--   anterior). Depois que a rodada começa, o remote é ignorado.
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
-- Client -> Server (FireServer): sem argumentos. O servidor acha a arma
--   equipada do jogador, desconta 1 de Settings/Config/Ammo (autoridade do
--   servidor sobre munição), aplica cadência mínima (Delay * 0.75), toca o
--   som da arma e o flash no Muzzle (replicam pra todos).
--------------------------------------------------------------------------------
Remotes.FirearmShoot = getRemote("FirearmShoot")

--------------------------------------------------------------------------------
-- FirearmHit
-- Client -> Server (FireServer):
--   position: Vector3      -- onde a bala parou (impacto ou alcance máximo)
--   instance: Instance?    -- o que acertou (nil = nada)
--   normal: Vector3?       -- normal do impacto
-- Servidor cria tracer + efeito de impacto (WeaponEffects) a partir do
--   Muzzle da PRÓPRIA Tool do jogador -- o CFrame do cano não é confiado do
--   cliente. Um pedido por bala.
--------------------------------------------------------------------------------
Remotes.FirearmHit = getRemote("FirearmHit")

--------------------------------------------------------------------------------
-- FirearmDamage
-- Client -> Server (FireServer):
--   targetPart: BasePart   -- parte do personagem acertada
-- Servidor valida (arma equipada, alvo com Humanoid, não é o atirador,
--   alcance) e aplica Settings/Damage por parte (Head/Torso/Limbs) ou na
--   armadura. Morte: Elimination.Eliminate + PlayerKilled (cause "Tiro").
-- Server -> Client (FireClient), só pro atirador:
--   kind: string           -- "Hit" | "Head" | "Armor" | "HeadArmor" (hitmarker)
--------------------------------------------------------------------------------
Remotes.FirearmDamage = getRemote("FirearmDamage")

--------------------------------------------------------------------------------
-- FirearmReload
-- Client -> Server (FireServer):
--   stage: string  -- "Start" | "MagOut" | "MagIn" | "BoltPull" | "BoltRelease" | "End" | "ShellIn"
-- Disparado pelos markers da animação de recarga. Servidor toca os sons do
--   Handle, derruba o pente, e em "End" enche Ammo (ou +1 em "ShellIn").
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
