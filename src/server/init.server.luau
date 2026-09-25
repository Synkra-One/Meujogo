--!strict
--[[
	Boot do servidor de "Náufragos". Cada sistema é seu próprio módulo com
	uma função Init() -- este script só decide QUANDO cada um liga.

	O MUNDO NÃO É GERADO AQUI -- de propósito. Os geradores (Tools/) usam
	InsertService:LoadAsset/game:GetObjects pra baixar os modelos do Toolbox
	(árvores, pedras, avião, lanterna, chocolate), e isso só funciona
	direito em MODO DE EDIÇÃO. Num jogo rodando (Play ou servidor de
	verdade) essas chamadas são restritas: falham em silêncio e cada modelo
	cai no placeholder -- ilha com árvores/pedras genéricas e nenhum avião.

	Por isso o fluxo certo é gerar UMA VEZ em modo de edição e SALVAR
	(Ctrl+S): o mundo vira parte do arquivo do lugar, e daí em diante todo
	Play só usa o que já está salvo, sem gerar nada e sem precisar de
	Command Bar. Se o mundo estiver faltando, este script avisa no Output em
	vez de tentar gerar (o que produziria justamente a versão degradada).

	POR QUE CADA Init() PASSA POR safeInit(): um `require(...).Init()` direto
	quebra o script INTEIRO se der erro -- em Luau, um erro não tratado para
	a execução do chunk, e TUDO que vem depois na lista simplesmente nunca
	roda. Isso já aconteceu de verdade nesta conversa: um erro em algum
	sistema no meio da lista impediu LobbyManager.Init() (o último) de
	rodar, e por tabela o Lobby inteiro (posição de spawn E o prompt
	"IniciarPartida") ficou sem ser configurado -- parecendo dois bugs
	sem relação nenhuma, quando era um erro só, silencioso, no meio do
	caminho. safeInit() isola cada sistema: um quebrado avisa no Output
	(nome + erro) e os outros continuam ligando normalmente.

	ORDEM QUE IMPORTA:
	  - LobbyManager vem PRIMEIRO, antes de qualquer coisa que possa falhar:
	    ele não depende de nenhum outro Init() ter rodado (só precisa dos
	    MÓDULOS RoundManager/GameConfig/Remotes, que o `require` no topo de
	    cada arquivo já resolve, não da função Init() deles). Mesmo que
	    tudo mais quebre, pelo menos o spawn e o botão de iniciar funcionam.
	  - RoundManager.Init() vem antes de SoundManager: escuta
	    RoundManager.PhaseChanged.
	  - UtilityItemSystem e FlashlightSystem usam DamageSystem.
	    FlashlightSystem tambem observa o ciclo de vida do RoundManager.
	  - O resto não tem dependência de ordem entre si.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- O sistema antigo de jangada foi removido, mas mapas salvos anteriormente
-- ainda podem carregar sua área de construção e o kit de teste neon. Limpa
-- somente os nomes/atributos exclusivos daquele sistema; as peças atuais do
-- rádio usam peças metálicas próprias e permanecem intactas.
local function removeLegacyRaftObjects()
	local legacyStructureNames = {
		PraiaJangada = true,
		Jangada = true,
		LocalJangada = true,
		KitTesteJangada = true,
		KitJangada = true,
	}
	local legacyItemNames = {
		Madeira = true,
		Corda = true,
		Lona = true,
		PecaMadeira = true,
		PecaCorda = true,
		PecaLona = true,
	}
	local ilha = Workspace:FindFirstChild("Ilha")

	local function isInsideGeneratedItems(descendant: Instance): boolean
		local itemsFolder = descendant:FindFirstAncestor("Itens")
		return ilha ~= nil and itemsFolder ~= nil and itemsFolder:IsDescendantOf(ilha)
	end

	for _, descendant in Workspace:GetDescendants() do
		if descendant.Parent and legacyStructureNames[descendant.Name] then
			descendant:Destroy()
		elseif descendant.Parent and (
			descendant:GetAttribute("MaterialJangada") == true
				or descendant:GetAttribute("TipoMaterial") ~= nil
		) then
			-- Esses atributos eram exclusivos dos materiais da jangada; podem ser
			-- apagados mesmo se o mapa antigo os tiver salvo fora de Itens.
			descendant:Destroy()
		elseif descendant.Parent and isInsideGeneratedItems(descendant) then
			local oldRadioBlock = descendant:IsA("BasePart")
				and descendant:GetAttribute("PecaRadio") == true
				and descendant.Material == Enum.Material.Neon
			if legacyItemNames[descendant.Name] or oldRadioBlock then
				descendant:Destroy()
			end
		end
	end
end

removeLegacyRaftObjects()

-- Remove pickups/tools de itens aposentados que possam ter ficado salvos no
-- mapa ou sido gerados por uma versão anterior do ItemSpawner. A limpeza é
-- deliberadamente baseada em IDs/Attributes explícitos para não confundir
-- pedras e tábuas que são apenas parte da decoração do mapa.
local function removeRetiredItemObjects()
	local retiredIds = {
		FacaImprovisada = true,
		PedraAfiada = true,
	}
	local retiredNames = {
		FacaImprovisada = true,
		["Faca Improvisada"] = true,
		PedraAfiada = true,
		["Pedra Afiada"] = true,
		["Chave inglesa"] = true,
		Wrench = true,
	}

	for _, descendant in Workspace:GetDescendants() do
		if not descendant.Parent then
			continue
		end
		local worldItemId = descendant:GetAttribute("WorldItemId")
		if (typeof(worldItemId) == "string" and retiredIds[worldItemId]) or retiredNames[descendant.Name] then
			descendant:Destroy()
			continue
		end
		if descendant:IsA("Tool") then
			for itemId in retiredIds do
				if descendant:GetAttribute(itemId) == true then
					descendant:Destroy()
					break
				end
			end
		end
	end
end

removeRetiredItemObjects()

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local LightingPresets = require(ReplicatedStorage.Modules.LightingPresets)
local lightingOk, lightingErr = pcall(function()
	LightingPresets.Apply(GameConfig.Environment.LightingPreset)
end)
if not lightingOk then
	warn("[Boot] LightingPresets.Apply falhou, continuando boot: " .. tostring(lightingErr))
end

if not Workspace:FindFirstChild("Ilha") then
	warn(
		"[Boot] Workspace.Ilha não existe -- o mapa não foi gerado e salvo ainda.\n"
			.. "Em MODO DE EDIÇÃO (sem Play), rode na Command Bar, um bloco por vez:\n"
			.. "  local Gen = require(game.ServerScriptService.Server.Tools.IslandGenerator) Gen.Generate()\n"
			.. "  local Crash = require(game.ServerScriptService.Server.Tools.PlaneCrashGenerator) Crash.Generate()\n"
			.. "  local ok, result = pcall(function() return require(game.ServerScriptService.Server.Tools.AbyssStationGenerator).Build() end) print('[Abismo]', ok, result)\n"
			.. "  local Spawner = require(game.ServerScriptService.Server.Tools.ItemSpawner) Spawner.Generate()\n"
			.. "e então SALVE o lugar (Ctrl+S). Depois disso, é só dar Play -- não precisa gerar de novo.\n"
			.. "(O barco de fuga, o píer e as boias do limite são montados no boot -- ver docs/Barco.md.)"
	)
end

-- O lobby é independente da ilha: outro gerador, outra área do mundo. Avisado
-- em separado pra não somer dentro do aviso do mapa.
if not Workspace:FindFirstChild("Lobby") then
	warn(
		"[Boot] Workspace.Lobby não existe -- o terminal do aeroporto não foi gerado e salvo ainda.\n"
			.. "Em MODO DE EDIÇÃO (sem Play), rode na Command Bar:\n"
			.. "  local Lobby = require(game.ServerScriptService.Server.Tools.AirportLobbyGenerator) Lobby.Generate()\n"
			.. "e SALVE o lugar (Ctrl+S). Sem ele o jogador ainda nasce certo, só que numa laje vazia."
	)
end

local function safeInit(name: string, moduleScript: ModuleScript)
	local loaded, module = pcall(require, moduleScript)
	if not loaded then
		warn(string.format("[Boot] require(%s) falhou -- esse sistema NÃO vai funcionar, mas o boot continua: %s", name, tostring(module)))
		return
	end

	local ok, err = pcall(function()
		(module :: { Init: () -> () }).Init()
	end)
	if not ok then
		warn(string.format("[Boot] %s.Init() falhou -- esse sistema NÃO vai funcionar, mas o resto do boot continua: %s", name, tostring(err)))
	end
end

safeInit("WaterRepair", script.WaterRepair)
safeInit("AnimationRigReference", script.AnimationRigReference)
safeInit("MonsterAnimationRigValidation", script.MonsterAnimationRigValidation)
-- Primeiro teste isolado: Mesh_AlpTrees4 tem colisao de copa muito maior que
-- o tronco visual. Corrige todas as copias salvas somente dessa variante.
safeInit("TreeCollisionFix", script.TreeCollisionFix)
-- Estado de partida vem antes de qualquer sistema de interação/combate:
-- durante Lobby, sorteio e carregamento o servidor também assume a raiz do
-- personagem e publica GameplayEnabled=false.
safeInit("MatchStateService", script.MatchStateService)
safeInit("LobbyManager", script.LobbyManager)

safeInit("DataStoreManager", script.DataStoreManager)
safeInit("RoundManager", script.RoundManager)
-- A rodada começa no preset Night e clareia gradualmente até o amanhecer.
safeInit("DayNightCycle", script.DayNightCycle)
-- CharacterStatsApplier ANTES de DamageSystem: publica os Attributes "Stat_*"
-- que o DamageSystem lê pra MaxHealth (Compostura) já no primeiro spawn.
safeInit("CharacterStatsApplier", script.CharacterStatsApplier)
safeInit("WaitingRoomManager", script.WaitingRoomManager)
safeInit("TestRigSwap", script.TestRigSwap)
safeInit("StaminaSystem", script.StaminaSystem)
safeInit("FearSystem", script.FearSystem)
safeInit("NoiseService", script.NoiseService)
safeInit("HeartbeatDetection", script.HeartbeatDetection)
-- DamageSystem antes de OTSFirearmService/WeaponSystem: os dois roteiam o dano por
-- ele (require no topo já resolve o módulo; Init() só liga MaxHealth + regen).
safeInit("DamageSystem", script.DamageSystem)
safeInit("AppearanceManager", script.AppearanceManager)
-- Antes de SabotageSystem/RadioSiteSystem: os dois penduram os pontos
-- reparáveis deles no minigame de precisão no Init(). O Init() daqui faz
-- requires tardios de RoundManager/DamageSystem de propósito (o topo do
-- arquivo fecharia ciclo com RadioSiteSystem) -- ver o cabeçalho do módulo.
safeInit("RepairMinigameSystem", script.RepairMinigameSystem)
safeInit("SabotageSystem", script.SabotageSystem)
safeInit("LethalAbility", script.LethalAbility)
safeInit("MonsterLightWeakness", script.MonsterLightWeakness)
-- Os postes das trilhas reagem à proximidade do Monstro e replicam o pisca
-- para todos os jogadores. O módulo encontra os postes já salvos no mapa.
safeInit("TrailLampMonsterEffect", script.TrailLampMonsterEffect)
-- Depois de DamageSystem + MonsterLightWeakness: roteia o golpe do Monstro
-- pelo DamageSystem e lê IsWeakened pra dano/velocidade reduzidos na luz.
safeInit("MonsterCombat", script.MonsterCombat)
-- Grab usa DamageSystem para a finalizacao e compartilha os busy states dos
-- outros poderes do Monstro.
safeInit("GrabService", script.GrabService)
-- Mapa da ilha (visão de cima) gerado de IslandLayout e publicado em
-- ReplicatedStorage. É o que o Monstro abre com Q pra escolher o destino do
-- teleporte -- proporção 1:1 com o mundo, então o clique vira um (x, z) real.
safeInit("IslandMap", script.IslandMap)
-- Poder de teleporte do Monstro (fenda -> engolido -> emerge no destino).
-- Depois de RoundManager (escuta RoundEnded/RoundPrepared) e MonsterCombat
-- (que lê o Attribute TeleportBusy pra bloquear o golpe). As fendas são
-- procedurais no cliente, sincronizadas pelos beats do servidor.
safeInit("MonsterTeleport", script.MonsterTeleport)
safeInit("ShadowRush", script.ShadowRush)
safeInit("UtilityItemSystem", script.UtilityItemSystem)
safeInit("FlashlightSystem", script.FlashlightSystem)
-- Apagão do Abismo (Monstro). Depois de FearSystem (usa AddFear) e de
-- FlashlightSystem (usa ForceOff pro corte imediato da luz); os requires no
-- topo do arquivo já resolvem os dois módulos, a ordem aqui é só clareza.
safeInit("AbyssBlackout", script.AbyssBlackout)
safeInit("DropItemSystem", script.DropItemSystem)
safeInit("AmmoSystem", script.AmmoSystem)
safeInit("RadioObjective", script.RadioObjective)
-- RadioPieces e carregado sob demanda pelo RoundManager no preparo da rodada;
-- se ele falhar, nao deve impedir a partida de iniciar.
-- Consome as Tools de peça no rack da TorreDeRadio e emite
-- "TodasPecasInstaladas"; RadioSiteSystem (linha de baixo) e quem escuta.
safeInit("RadioInstallSystem", script.RadioInstallSystem)
-- Depois de RadioInstallSystem (que garante a TorreDeRadio no mapa): roda a
-- estacao de radio -- combustivel, fusivel, gerador, painel e o pedido de
-- socorro. Ver docs/Radio.md.
safeInit("RadioSiteSystem", script.RadioSiteSystem)
-- Fim da linha do radio: a zona de pouso na praia e o helicoptero do
-- resgate. Fica parado ate RoundManager chamar Begin(). Ver docs/Extracao.md.
safeInit("ExtractionSystem", script.ExtractionSystem)
-- Segunda rota de fuga: o barco (montar motor, gasolina, chave, pilotar até
-- as boias do limite). Depois de DropItemSystem (as peças são itens do chão),
-- RepairMinigameSystem (montar o motor é reparo de precisão) e SabotageSystem
-- (a fiação do motor é Sabotavel). Ver docs/Barco.md.
safeInit("BoatSystem", script.BoatSystem)
safeInit("SurvivorPowerSystem", script.SurvivorPowerSystem)
safeInit("ConfrontSystem", script.ConfrontSystem)
safeInit("WeaponSystem", script.WeaponSystem)
safeInit("OTSFirearmService", script.OTSFirearmService)
-- Depois de AmmoSystem + DropItemSystem: usa CreatePickup e PlaceInWorld.
safeInit("WeaponSpawner", script.WeaponSpawner)
-- Depois de RoundManager (escuta RoundPrepared): taco de beisebol ao entrar na partida.
safeInit("StartingItems", script.StartingItems)
safeInit("LobbyFiringRange", script.LobbyFiringRange)
-- Portas das cabanas/lodge/celeiro (Parts com Attribute "Porta", ver
-- Tools/Structures.lua): prompt Abrir/Fechar.
safeInit("DoorSystem", script.DoorSystem)
-- Depois de CharacterStatsApplier: o sorteio da caixa lê a Sorte publicada.
safeInit("LootCrateSystem", script.LootCrateSystem)
-- Gavetas das casas grandes (Tools/Houses): abrir/fechar, loot por rodada e
-- "Guardar item". Depois de DropItemSystem (o item dentro é um pickup dele)
-- e de CharacterStatsApplier (a Sorte de quem abre decide a raridade).
safeInit("DrawerSystem", script.DrawerSystem)
-- Depois de WeaponSpawner/LootCrateSystem/DropItemSystem: marca no mapa de
-- cada jogador os itens do mundo que ele passar perto (Q do Monstro / M do
-- Sobrevivente-Espião). Observa o Workspace por evento, então pega tanto o
-- que já existe quanto o que aparecer depois (drop de jogador, etc).
safeInit("ItemDiscovery", script.ItemDiscovery)
-- XP / ESTATÍSTICAS / RESULTADO DA PARTIDA -- nesta ordem, e por ÚLTIMO:
--   MatchStatsService guarda os dados e escuta RoundManager.RoundPrepared/
--     RoundEnded (ciclo de vida) e StaminaSystem.MovementSampled (distância);
--   MatchRewardService registra o gancho de XP no Stats e escuta os sistemas
--     de jogo (DamageSystem.DamageApplied/Healed, ExtractionSystem,
--     ItemDiscovery.ItemDiscovered);
--   MatchResultsService fecha a partida e manda o relatório individual.
-- Vêm depois de TODOS os sistemas que eles observam: se um deles falhar ao
-- ligar, o jogo inteiro continua funcionando -- só o relatório some.
safeInit("MatchStatsService", script.MatchStatsService)
safeInit("MatchRewardService", script.MatchRewardService)
safeInit("MatchResultsService", script.MatchResultsService)
safeInit("SoundManager", script.SoundManager)
safeInit("FlyTest", script.FlyTest) -- modo voar de teste (só Studio)

-- Diagnóstico da cena editável do menu inicial: avisa no Output do
-- SERVIDOR se Workspace.MenuSceneSet (gerado por Tools/MenuSceneGenerator)
-- não existir NESTE momento -- assim dá pra comparar com o que o cliente vê
-- (MenuScene.lua imprime a mesma checagem do lado dele) sem precisar rodar
-- nada na Command Bar: as duas linhas já aparecem juntas no Output ao dar Play.
do
	local menuScene = workspace:FindFirstChild("MenuSceneSet")
	if menuScene then
		print(string.format("[Boot] Workspace.MenuSceneSet presente no SERVIDOR (%s, %d peça(s)).",
			menuScene.ClassName, #menuScene:GetChildren()))
	else
		print("[Boot] Workspace.MenuSceneSet NÃO existe no servidor. "
			.. "Rode Tools/MenuSceneGenerator.Generate() em modo de edição e salve (Ctrl+S).")
	end
end

print("[Boot] Servidor de Náufragos pronto.")
