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
	  - UtilityItemSystem.Init() vem depois de MonsterLightWeakness.Init():
	    a Lanterna chama MonsterLightWeakness.ActivateLightSource/
	    DeactivateLightSource diretamente (não por evento, então a ordem
	    exata não quebra nada em runtime, mas documenta a dependência).
	  - O resto não tem dependência de ordem entre si.
]]

local Workspace = game:GetService("Workspace")

if not Workspace:FindFirstChild("Ilha") then
	warn(
		"[Boot] Workspace.Ilha não existe -- o mapa não foi gerado e salvo ainda.\n"
			.. "Em MODO DE EDIÇÃO (sem Play), rode na Command Bar, um bloco por vez:\n"
			.. "  local Gen = require(game.ServerScriptService.Server.Tools.IslandGenerator) Gen.Generate()\n"
			.. "  local Crash = require(game.ServerScriptService.Server.Tools.PlaneCrashGenerator) Crash.Generate()\n"
			.. "  local Spawner = require(game.ServerScriptService.Server.Tools.ItemSpawner) Spawner.Generate()\n"
			.. "e então SALVE o lugar (Ctrl+S). Depois disso, é só dar Play -- não precisa gerar de novo."
	)
end

local function safeInit(name: string, module: { Init: () -> () })
	local ok, err = pcall(function()
		module.Init()
	end)
	if not ok then
		warn(string.format("[Boot] %s.Init() falhou -- esse sistema NÃO vai funcionar, mas o resto do boot continua: %s", name, tostring(err)))
	end
end

safeInit("LobbyManager", require(script.LobbyManager))

safeInit("DataStoreManager", require(script.DataStoreManager))
safeInit("RoundManager", require(script.RoundManager))
-- CharacterStatsApplier ANTES de DamageSystem: publica os Attributes "Stat_*"
-- que o DamageSystem lê pra MaxHealth (Compostura) já no primeiro spawn.
safeInit("CharacterStatsApplier", require(script.CharacterStatsApplier))
safeInit("StaminaSystem", require(script.StaminaSystem))
-- DamageSystem antes de FirearmServer/WeaponSystem: os dois roteiam o dano por
-- ele (require no topo já resolve o módulo; Init() só liga MaxHealth + regen).
safeInit("DamageSystem", require(script.DamageSystem))
safeInit("AppearanceManager", require(script.AppearanceManager))
safeInit("SabotageSystem", require(script.SabotageSystem))
safeInit("LethalAbility", require(script.LethalAbility))
safeInit("MonsterLightWeakness", require(script.MonsterLightWeakness))
-- Depois de DamageSystem + MonsterLightWeakness: roteia o golpe do Monstro
-- pelo DamageSystem e lê IsWeakened pra dano/velocidade reduzidos na luz.
safeInit("MonsterCombat", require(script.MonsterCombat))
safeInit("UtilityItemSystem", require(script.UtilityItemSystem))
safeInit("DropItemSystem", require(script.DropItemSystem))
safeInit("AmmoSystem", require(script.AmmoSystem))
safeInit("RadioObjective", require(script.RadioObjective))
safeInit("RaftObjective", require(script.RaftObjective))
safeInit("ConfrontSystem", require(script.ConfrontSystem))
safeInit("CraftingSystem", require(script.CraftingSystem))
safeInit("WeaponSystem", require(script.WeaponSystem))
safeInit("FirearmServer", require(script.FirearmServer))
-- Depois de AmmoSystem + DropItemSystem: usa CreatePickup e PlaceInWorld.
safeInit("WeaponSpawner", require(script.WeaponSpawner))
-- Depois de CharacterStatsApplier: o sorteio da caixa lê a Sorte publicada.
safeInit("LootCrateSystem", require(script.LootCrateSystem))
safeInit("SoundManager", require(script.SoundManager))

print("[Boot] Servidor de Náufragos pronto.")
