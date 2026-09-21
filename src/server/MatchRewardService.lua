--!strict
--[[
	MatchRewardService
	PORTA ÚNICA de concessão de XP. Todo sistema do servidor que quiser
	registrar uma ação chama daqui -- e nunca escreve na sessão direto.

	A REGRA QUE SUSTENTA A SEGURANÇA DO SISTEMA INTEIRO
	    MatchRewardService.AddXP(player, actionId, context?)
	Não existe parâmetro de QUANTIDADE. O valor sai de
	MatchRewardsConfig.Actions[actionId] -- não do chamador. Um sistema (ou um
	script malicioso que de alguma forma rodasse no servidor) não consegue
	pedir "+999999 XP": ou o actionId existe na configuração, com o valor de
	lá, ou a concessão é recusada.

	Recompensa variável (dano, cura, progresso de objetivo) usa XPPerUnit e
	só aceita `context.Units`, que é CLAMPADO por MaxUnitsPerGrant antes de
	multiplicar. Mesmo um pulso absurdo de dano tem teto.

	O CLIENTE NÃO PARTICIPA DISSO
	  Os dois RemoteEvents deste sistema (MatchResults e MatchXPNotification)
	  são Server -> Client. Nenhum dos dois tem OnServerEvent conectado em
	  lugar nenhum do projeto -- procure por "MatchXPNotification.OnServerEvent"
	  e não existe. O cliente só recebe um payload já validado; ele não pede,
	  não confirma e não influencia nada.

	CAMADAS ANTI-FARM (todas configuráveis, nenhuma no código)
	  1. Papel        -- ação de Monstro não paga pra Sobrevivente e vice-versa.
	  2. Cooldown     -- por jogador E por ação.
	  3. MaxPerMatch  -- repetições por partida.
	  4. UniqueBy     -- a mesma chave (objetivo, vítima, item) nunca paga 2x.
	  5. Par cooldown -- o mesmo par (curador, alvo) / (atacante, vítima) tem
	                     um freio próprio, além do cooldown da ação. É o que
	                     mata a dupla que se cura em looping.
	  6. Teto por categoria -- rede final; a categoria inteira para de pagar.
	  7. Janela da partida -- fora dela (antes do começo, depois do
	                     congelamento) nada é aceito.
	  8. Alvo válido  -- alvo sem sessão, morto ou que saiu não paga.

	Uso (uma vez no boot, DEPOIS de MatchStatsService):
		require(script.MatchRewardService).Init()

		-- em qualquer sistema do servidor:
		MatchRewardService.AddXP(player, "MonsterStunned", { TargetUserId = id })
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local MapMarkers = require(ReplicatedStorage.Modules.MapMarkers)
local MatchRewardsConfig = require(ReplicatedStorage.Modules.MatchRewardsConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Types = require(ReplicatedStorage.Modules.MatchStatsTypes)

local DamageSystem = require(script.Parent.DamageSystem)
local DropItemSystem = require(script.Parent.DropItemSystem)
local Elimination = require(script.Parent.Elimination)
local ExtractionSystem = require(script.Parent.ExtractionSystem)
local MatchStatsService = require(script.Parent.MatchStatsService)
local RadioInstallSystem = require(script.Parent.RadioInstallSystem)
local RadioPieces = require(script.Parent.RadioPieces)
local RoundManager = require(script.Parent.RoundManager)

local MatchRewardService = {}

local Stat = Types.Stat
local Actions = MatchRewardsConfig.Actions
local AntiFarm = MatchRewardsConfig.AntiFarm

--------------------------------------------------------------------------------
-- Estado anti-farm (por UserId -- nunca compartilhado entre jogadores)
--------------------------------------------------------------------------------

type ActionState = {
	LastGrantAt: number,
	Count: number,
	UniqueKeys: { [string]: boolean },
}

-- userId -> actionId -> estado
local actionStates: { [number]: { [string]: ActionState } } = {}

-- Freios por PAR de jogadores: "origem:alvo" -> os.clock() da última vez.
local healPairCooldown: { [string]: number } = {}
local hitPairCooldown: { [string]: number } = {}

local notificationCounter = 0
local initialized = false

local verbose = RunService:IsStudio() and MatchRewardsConfig.Debug.VerboseInStudio

local function log(format: string, ...: any)
	if verbose then
		print("[MatchReward] " .. string.format(format, ...))
	end
end

-- Recusa: só aparece no Studio com Debug.VerboseInStudio ligado. É o log que
-- responde "por que essa ação não pagou?" -- sem ele, a recusa é silenciosa.
local function refuse(player: Player, actionId: string, reason: string): boolean
	log("RECUSADO %s/%s: %s", player.Name, actionId, reason)
	return false
end

local function getActionState(userId: number, actionId: string): ActionState
	local byAction = actionStates[userId]
	if not byAction then
		byAction = {}
		actionStates[userId] = byAction
	end
	local state = byAction[actionId]
	if not state then
		state = { LastGrantAt = -math.huge, Count = 0, UniqueKeys = {} }
		byAction[actionId] = state
	end
	return state
end

--------------------------------------------------------------------------------
-- Notificação (Server -> Client, só pro dono da recompensa)
--------------------------------------------------------------------------------

local function notify(player: Player, record: Types.ActionRecord, action: MatchRewardsConfig.Action)
	if not MatchRewardsConfig.Notification.Enabled then
		return
	end
	if player.Parent ~= Players then
		return
	end

	notificationCounter += 1

	-- SÓ estes cinco campos saem do servidor. Nenhuma tabela interna, nenhum
	-- dado de outro jogador, nenhum total acumulado -- a notificação não é
	-- lugar de vazar estado de partida.
	local payload: Types.NotificationPayload = {
		Id = string.format("n%d", notificationCounter),
		ActionId = record.ActionId,
		Label = record.Label,
		XP = record.XP,
		Category = record.Category,
		Priority = action.Priority or 1,
	}

	Remotes.MatchXPNotification:FireClient(player, payload)
end

--------------------------------------------------------------------------------
-- API principal
--------------------------------------------------------------------------------

export type Context = {
	Units: number?, -- quantidade pra ações com XPPerUnit (dano, cura, progresso)
	Key: string?, -- chave de unicidade pra ações com UniqueBy
	TargetUserId: number?, -- alvo da ação (validado: precisa estar na partida)
	Detail: string?, -- texto extra já seguro pra exibir
	Silent: boolean?, -- não manda notificação (ex: bônus calculados no fim)
}

--[[
	AddXP(player, actionId, context?)
	Concede o XP da ação `actionId` ao jogador, se TODAS as guardas passarem.
	Devolve true se pagou, false se foi recusada (sempre em silêncio pro
	jogador -- recusa nunca vira notificação).
]]
function MatchRewardService.AddXP(player: Player, actionId: string, context: Context?): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local action = Actions[actionId]
	if not action then
		-- Erro de programação, não de jogo: alguém escreveu um id que não
		-- existe na configuração. Avisa alto pra não passar despercebido.
		warn(string.format("[MatchReward] actionId desconhecido: '%s'", tostring(actionId)))
		return false
	end
	if action.Enabled == false then
		return refuse(player, actionId, "ação desligada na configuração")
	end

	-- (7) Janela da partida.
	if not MatchStatsService.IsAccepting(player) then
		return refuse(player, actionId, "fora da janela da partida")
	end

	local session = MatchStatsService.GetSession(player)
	if not session or session.ResultFinalized then
		return refuse(player, actionId, "sem sessão ou resultado já congelado")
	end

	-- (1) Papel.
	if action.Roles and not action.Roles[session.Role] then
		return refuse(player, actionId, "papel " .. session.Role .. " não ganha esta ação")
	end

	local ctx = context or {}
	local now = os.clock()
	local state = getActionState(session.UserId, actionId)

	-- (2) Cooldown por jogador e por ação.
	if action.Cooldown and now - state.LastGrantAt < action.Cooldown then
		return refuse(player, actionId, "cooldown")
	end

	-- (3) Limite de repetições na partida.
	if action.MaxPerMatch and state.Count >= action.MaxPerMatch then
		return refuse(player, actionId, "limite da partida atingido")
	end

	-- (4) Unicidade. Sem chave, a ação com UniqueBy paga no máximo uma vez.
	local uniqueKey: string? = nil
	if action.UniqueBy then
		uniqueKey = ctx.Key or actionId
		if state.UniqueKeys[uniqueKey :: string] then
			return refuse(player, actionId, "chave já recompensada: " .. (uniqueKey :: string))
		end
	end

	-- (8) Alvo válido: tem que ser alguém DESTA partida que ainda não saiu.
	if ctx.TargetUserId then
		local targetSession = MatchStatsService.GetSession(ctx.TargetUserId)
		if not targetSession then
			return refuse(player, actionId, "alvo fora da partida")
		end
		if targetSession.UserId == session.UserId then
			return refuse(player, actionId, "alvo é o próprio jogador")
		end
	end

	----------------------------------------------------------------------------
	-- Valor
	----------------------------------------------------------------------------
	local amount: number
	if action.XPPerUnit then
		local units = ctx.Units
		if type(units) ~= "number" or units ~= units or units <= 0 then
			return refuse(player, actionId, "Units inválido para ação variável")
		end
		-- O teto do exploit: mesmo um pulso absurdo vira MaxUnitsPerGrant.
		units = math.min(units, action.MaxUnitsPerGrant or units)
		amount = action.XPPerUnit * units
	else
		amount = action.XP or 0
	end

	amount = math.floor(amount + 0.5)
	if amount == 0 then
		return refuse(player, actionId, "valor arredondou para zero")
	end

	-- (6) Teto por categoria. Só vale pra ganho: penalidade não tem teto
	-- positivo (o freio dela é o MaxPerMatch da própria ação).
	local cap = MatchRewardsConfig.CategoryCaps[action.Category]
	if cap and amount > 0 then
		local already = session.XPBreakdown[action.Category] or 0
		if already >= cap then
			return refuse(player, actionId, "teto da categoria " .. action.Category)
		end
		-- Paga só o que cabe no teto, em vez de recusar a ação inteira.
		amount = math.min(amount, cap - already)
		if amount <= 0 then
			return refuse(player, actionId, "teto da categoria " .. action.Category)
		end
	end

	----------------------------------------------------------------------------
	-- Aplica
	----------------------------------------------------------------------------
	local record: Types.ActionRecord = {
		ActionId = actionId,
		Category = action.Category,
		Label = action.Label,
		XP = amount,
		MatchTime = MatchStatsService.MatchTime(),
		Count = 1,
		Detail = ctx.Detail,
	}

	if not MatchStatsService.ApplyReward(player, record) then
		return refuse(player, actionId, "sessão recusou a aplicação")
	end

	state.LastGrantAt = now
	state.Count += 1
	if uniqueKey then
		state.UniqueKeys[uniqueKey] = true
	end

	log("%s +%d XP (%s / %s)", player.Name, amount, actionId, action.Category)

	if not ctx.Silent then
		notify(player, record, action)
	end
	return true
end

--------------------------------------------------------------------------------
-- API de registro por tipo de ação
--------------------------------------------------------------------------------
-- Açúcar em cima do AddXP, pra os sistemas do jogo não precisarem conhecer os
-- actionIds nem montar o context na mão. Cada uma cuida também da
-- estatística correspondente.

--[[
	RecordDamage(attacker, victim, amount, died, cause)
	Chamado pelo gancho do DamageSystem. Registra dano causado/recebido, o
	acerto e -- se matou -- a eliminação. `cause` é o texto que o DamageSystem
	já carrega ("Monstro", "Faca", "Tiro"...).
]]
function MatchRewardService.RecordDamage(
	attacker: Player?,
	victim: Player?,
	amount: number,
	died: boolean,
	_cause: string?
)
	if type(amount) ~= "number" or amount <= 0 then
		return
	end

	if victim and MatchStatsService.GetSession(victim) then
		MatchStatsService.AddStat(victim, Stat.DamageTaken, amount)
	end

	if not attacker or attacker == victim then
		return -- dano de ambiente/queda/próprio: não rende nada a ninguém
	end

	local attackerSession = MatchStatsService.GetSession(attacker)
	local victimSession = if victim then MatchStatsService.GetSession(victim) else nil
	if not attackerSession or not victimSession then
		return -- alguém está fora da partida: não conta
	end

	MatchStatsService.AddStat(attacker, Stat.DamageDealt, amount)

	local monsterAttacking = MatchRewardsConfig.MonsterRoles[attackerSession.Role] == true

	-- "Acerto" tem dano mínimo e freio por par: um sistema que aplique dano em
	-- tiquinhos não vira 50 acertos, e bater sem parar na mesma vítima não paga
	-- XP a cada frame.
	if amount >= AntiFarm.MinDamageForHit then
		local pairKey = string.format("%d:%d", attackerSession.UserId, victimSession.UserId)
		local now = os.clock()
		if now - (hitPairCooldown[pairKey] or -math.huge) >= AntiFarm.SameTargetHitCooldown then
			hitPairCooldown[pairKey] = now
			MatchStatsService.AddStat(attacker, Stat.Hits, 1)
			MatchRewardService.AddXP(
				attacker,
				if monsterAttacking then "SurvivorHit" else "MonsterHit",
				{ TargetUserId = victimSession.UserId }
			)
		end
	end

	if died and monsterAttacking then
		MatchStatsService.AddStat(attacker, Stat.SurvivorsEliminated, 1)
		MatchRewardService.AddXP(attacker, "SurvivorEliminated", {
			TargetUserId = victimSession.UserId,
			-- Unicidade por vítima: matar o mesmo jogador de novo (se algum dia
			-- houver revive) não paga a eliminação duas vezes.
			Key = tostring(victimSession.UserId),
			Detail = victimSession.Name,
		})
	end
end

--[[
	RecordHeal(healer, target, healed)
	Cura de ALIADO. Curar a si mesmo não paga XP (é manutenção, não ajuda ao
	time) mas conta na estatística de cura realizada.
]]
function MatchRewardService.RecordHeal(healer: Player?, target: Player?, healed: number)
	if not healer or type(healed) ~= "number" or healed <= 0 then
		return
	end
	local healerSession = MatchStatsService.GetSession(healer)
	if not healerSession then
		return
	end

	MatchStatsService.AddStat(healer, Stat.HealingDone, healed)
	MatchStatsService.AddStat(healer, Stat.HealsPerformed, 1)

	if not target or target == healer then
		return
	end
	local targetSession = MatchStatsService.GetSession(target)
	if not targetSession then
		return
	end
	if healed < AntiFarm.MinHealForReward then
		return -- "curar" quem estava quase cheio não conta
	end

	-- Freio específico do par: é o que impede duas pessoas de se curarem em
	-- looping só pra gerar XP, mesmo com o cooldown da ação já vencido.
	local pairKey = string.format("%d:%d", healerSession.UserId, targetSession.UserId)
	local now = os.clock()
	if now - (healPairCooldown[pairKey] or -math.huge) < AntiFarm.SameTargetHealCooldown then
		return
	end
	healPairCooldown[pairKey] = now

	MatchStatsService.AddStat(healer, Stat.AlliesHelped, 1)
	MatchRewardService.AddXP(healer, "AllyHealed", {
		TargetUserId = targetSession.UserId,
		Detail = targetSession.Name,
	})
end

--[[
	RecordObjectiveContribution(player, objectiveId, amount)
	Progresso contínuo (reparo, sintonia, montagem). `amount` é a quantidade de
	progresso; o XP por unidade e o teto vêm da configuração.
]]
function MatchRewardService.RecordObjectiveContribution(player: Player, objectiveId: string, amount: number)
	if type(amount) ~= "number" or amount <= 0 then
		return
	end
	MatchStatsService.AddStat(player, Stat.ObjectiveContribution, amount)
	MatchRewardService.AddXP(player, "ObjectiveContribution", {
		Units = amount,
		Detail = objectiveId,
	})
end

--[[
	RecordObjectiveStep(player, stepId)
	Etapa concluída (peça instalada, painel religado). `stepId` é a chave de
	unicidade: a MESMA etapa nunca paga duas vezes, nem pro mesmo jogador nem
	depois de um reset mal feito.
]]
function MatchRewardService.RecordObjectiveStep(player: Player, stepId: string)
	MatchStatsService.AddStat(player, Stat.ObjectiveStepsCompleted, 1)
	MatchRewardService.AddXP(player, "ObjectiveStepCompleted", { Key = stepId, Detail = stepId })
end

--[[ RecordObjectiveCompleted(player, objectiveId) -- objetivo inteiro fechado. ]]
function MatchRewardService.RecordObjectiveCompleted(player: Player, objectiveId: string)
	MatchRewardService.AddXP(player, "ObjectiveCompleted", { Key = objectiveId, Detail = objectiveId })
end

--[[ RecordItemDelivered(player, itemKey) -- peça/item de objetivo entregue. ]]
function MatchRewardService.RecordItemDelivered(player: Player, itemKey: string)
	MatchStatsService.AddStat(player, Stat.ItemsDelivered, 1)
	MatchRewardService.AddXP(player, "ObjectiveItemDelivered", { Key = itemKey, Detail = itemKey })
end

--[[ RecordImportantItemFound(player, itemKey, label?) ]]
function MatchRewardService.RecordImportantItemFound(player: Player, itemKey: string, label: string?)
	MatchStatsService.AddStat(player, Stat.ImportantItemsFound, 1)
	MatchRewardService.AddXP(player, "ImportantItemFound", { Key = itemKey, Detail = label })
end

--[[ RecordMonsterStunned(player, monsterUserId) ]]
function MatchRewardService.RecordMonsterStunned(player: Player, monsterUserId: number?)
	MatchStatsService.AddStat(player, Stat.MonsterStuns, 1)
	MatchRewardService.AddXP(player, "MonsterStunned", { TargetUserId = monsterUserId })
end

--[[ RecordMonsterBlinded(player, monsterUserId) -- lanterna/tocha na cara. ]]
function MatchRewardService.RecordMonsterBlinded(player: Player, monsterUserId: number?)
	MatchStatsService.AddStat(player, Stat.MonsterBlinds, 1)
	MatchRewardService.AddXP(player, "MonsterBlinded", { TargetUserId = monsterUserId })
end

--[[ RecordAllySaved(player, allyUserId) ]]
function MatchRewardService.RecordAllySaved(player: Player, allyUserId: number?)
	MatchStatsService.AddStat(player, Stat.AlliesSaved, 1)
	MatchRewardService.AddXP(player, "AllySaved", { TargetUserId = allyUserId })
end

--[[ RecordSurvivorDowned(monster, survivorUserId) -- pronto pro dia em que
     existir o estado "derrubado"; nada chama isto hoje. ]]
function MatchRewardService.RecordSurvivorDowned(monster: Player, survivorUserId: number?)
	MatchStatsService.AddStat(monster, Stat.SurvivorsDowned, 1)
	MatchRewardService.AddXP(monster, "SurvivorDowned", { TargetUserId = survivorUserId })
end

--[[ RecordObjectiveInterrupted(monster, objectiveId) ]]
function MatchRewardService.RecordObjectiveInterrupted(monster: Player, objectiveId: string?)
	MatchStatsService.AddStat(monster, Stat.ObjectivesInterrupted, 1)
	MatchRewardService.AddXP(monster, "ObjectiveInterrupted", { Detail = objectiveId })
end

--[[ RecordHealInterrupted(monster, targetUserId) ]]
function MatchRewardService.RecordHealInterrupted(monster: Player, targetUserId: number?)
	MatchStatsService.AddStat(monster, Stat.HealsInterrupted, 1)
	MatchRewardService.AddXP(monster, "HealInterrupted", { TargetUserId = targetUserId })
end

--[[ RecordBarricadeDestroyed(monster, barricadeKey) ]]
function MatchRewardService.RecordBarricadeDestroyed(monster: Player, barricadeKey: string)
	MatchStatsService.AddStat(monster, Stat.BarricadesDestroyed, 1)
	MatchRewardService.AddXP(monster, "BarricadeDestroyed", { Key = barricadeKey })
end

--[[ RecordMonsterPowerUsed(monster, powerId) -- só quando o poder teve efeito. ]]
function MatchRewardService.RecordMonsterPowerUsed(monster: Player, powerId: string?)
	MatchStatsService.AddStat(monster, Stat.PowersUsed, 1)
	MatchRewardService.AddXP(monster, "MonsterPowerUsed", { Detail = powerId })
end

--[[
	RecordEscape(player, method)
	Fuga confirmada pelo servidor quando o helicóptero decola.
]]
function MatchRewardService.RecordEscape(player: Player, method: string)
	if not MatchStatsService.GetSession(player) then
		return
	end
	MatchStatsService.MarkEscaped(player, method)
	MatchRewardService.AddXP(player, "Escaped", { Key = "escape", Detail = method })
end

--------------------------------------------------------------------------------
-- Ganchos nos sistemas existentes
--------------------------------------------------------------------------------

local function connectDamage()
	-- DamageSystem.DamageApplied é o gancho que resolve combate INTEIRO de uma
	-- vez: golpe do Monstro, faca/lança, tiro da Glock e qualquer arma futura
	-- já passam todos pela porta única DamageSystem.Apply. Não foi preciso
	-- tocar em MonsterCombat, WeaponSystem nem OTSFirearmService.
	DamageSystem.DamageApplied.Event:Connect(function(attacker, victim, amount, died, cause)
		MatchRewardService.RecordDamage(attacker, victim, amount, died, cause)
	end)

	-- Mesma ideia pra cura: UtilityItemSystem (chocolate/bandagem) e qualquer
	-- cura futura passam por DamageSystem.Heal.
	--
	-- HOJE toda cura do jogo é em si mesmo, então nenhuma paga XP de
	-- "curou um aliado" -- e isso está certo. No dia em que existir cura de
	-- aliado, ela passa pelo mesmo Heal com o `source` diferente do alvo e a
	-- recompensa começa a valer sozinha, sem mudar nada aqui.
	DamageSystem.Healed.Event:Connect(function(healer, target, healed)
		MatchRewardService.RecordHeal(healer, target, healed)
	end)
end

local function connectEscapes()
	ExtractionSystem.SurvivorsExtracted.Event:Connect(function(rescued: { Player })
		for _, player in rescued do
			MatchRewardService.RecordEscape(player, "Helicoptero")
		end
	end)

end

-- Categorias de item que valem XP de "achado importante". Material solto e
-- caixa vazia não entram: senão a ilha inteira vira XP de graça.
local IMPORTANT_ITEM_CATEGORIES: { [string]: boolean } = {
	Firearm = true,
	Radio = true,
	Fuel = true,
	Rare = true,
	Light = true,
}

-- Marca no PRÓPRIO Tool que ele já pagou XP de "achado". Sem isto, largar e
-- pegar de volta (ou passar pra um colega) pagaria de novo -- e como o mesmo
-- Instance de Tool nunca é destruído entre um drop e outro, o Attribute
-- sobrevive exatamente pelo tempo que precisa: até a Tool ser consumida ou
-- destruída no fim da partida.
local ITEM_FOUND_ATTRIBUTE = "_MatchRewardItemFound"

--[[
	connectItemPickups()
	AQUI é a posse de verdade -- não confundir com ItemDiscovery.
	ItemDiscovery.ItemDiscovered é só o PING do item aparecendo no MAPA a
	distância (pra marcar o ícone); ele dispara bem antes de alguém chegar
	perto o bastante pra pegar, e às vezes nunca é seguido de um pickup real.
	"Item importante encontrado" tem que significar o jogador TER o item,
	então o gancho certo é a Tool entrando de fato no Backpack:
	  - DropItemSystem.ItemPickedUp -- Tools do ItemSpawner/WeaponSpawner
	    (Galão de Gasolina, armas do mapa, Crowbar Ancestral...) e também
	    drops de outro jogador (por isso o Attribute de dedupe abaixo).
	  - RadioPieces.PiecePickedUp -- Antena/Bateria/Transmissor, que usam o
	    próprio sistema de coleta do rádio (Part -> Tool), não DropItemSystem.
]]
local function connectItemPickups()
	DropItemSystem.ItemPickedUp.Event:Connect(function(player: Player, tool: Tool)
		if tool:GetAttribute(ITEM_FOUND_ATTRIBUTE) == true then
			return -- já pagou por esta Tool (achado antes, largada, pega de novo)
		end

		local worldItemId = tool:GetAttribute("WorldItemId")
		local category = MapMarkers.CategoryOf(tool.Name, if type(worldItemId) == "string" then worldItemId else nil)
		if not IMPORTANT_ITEM_CATEGORIES[category] then
			return
		end

		tool:SetAttribute(ITEM_FOUND_ATTRIBUTE, true)
		-- Key = a própria Tool: cada Instance só concede XP uma vez, mesmo que
		-- este actionId não tivesse UniqueBy nenhum.
		MatchRewardService.RecordImportantItemFound(player, tostring(tool), tool.Name)
	end)

	RadioPieces.PiecePickedUp.Event:Connect(function(player: Player, pieceType: string)
		-- Key = o TIPO da peça: só existe uma Antena/Bateria/Transmissor por
		-- partida, então isto sozinho já impede pagar duas vezes mesmo se a
		-- peça for largada (o carregador morreu) e pega por outro sobrevivente.
		MatchRewardService.RecordImportantItemFound(player, "RadioPeca_" .. pieceType, pieceType)
	end)
end

--[[
	connectRadioInstall()
	Cada peça instalada no rack vira uma etapa de objetivo; a torre completa
	(as três) fecha o objetivo "Radio" inteiro. UniqueBy na configuração
	(chave = pieceType / "Radio") garante que nenhuma das duas paga duas
	vezes, então mesmo uma reinstalação hipotética não duplicaria XP.
]]
local function connectRadioInstall()
	RadioInstallSystem.PieceInstalled.Event:Connect(function(player: Player, pieceType: string)
		MatchRewardService.RecordObjectiveStep(player, "Radio_" .. pieceType)
	end)

	RadioInstallSystem.AllInstalled.Event:Connect(function(player: Player)
		MatchRewardService.RecordObjectiveCompleted(player, "Radio")
	end)
end

local function connectLeaving()
	Players.PlayerRemoving:Connect(function(player)
		if not MatchStatsService.IsAccepting(player) then
			return
		end
		local session = MatchStatsService.GetSession(player)
		-- Quem já escapou ou já foi eliminado não "abandonou" nada: a partida
		-- dele tinha acabado. Penalizar isso seria punir quem jogou até o fim.
		if not session or session.Escaped or session.Eliminated then
			return
		end
		-- Silent: não adianta notificar quem já saiu do servidor.
		MatchRewardService.AddXP(player, "AbandonedMatch", { Silent = true })
	end)
end

--------------------------------------------------------------------------------
-- Bônus de fim de partida (chamado pelo MatchResultsService)
--------------------------------------------------------------------------------

--[[
	ApplyEndOfMatchBonuses(winner)
	Bônus que só dá pra saber no fim: último sobrevivente vivo, Monstro que
	eliminou todo mundo. Roda ANTES do congelamento, uma vez só -- o
	MatchResultsService garante a chamada única.
]]
function MatchRewardService.ApplyEndOfMatchBonuses(_winner: string)
	local sessions = MatchStatsService.GetAllSessions()

	local survivorsAlive: { number } = {}
	local survivorTotal = 0
	local eliminatedSurvivors = 0

	for userId, session in sessions do
		if MatchRewardsConfig.SurvivorRoles[session.Role] then
			survivorTotal += 1
			if session.Eliminated then
				eliminatedSurvivors += 1
			elseif not session.Left then
				table.insert(survivorsAlive, userId)
			end
		end
	end

	-- Último sobrevivente vivo (e só se houve mais de um para começo de
	-- conversa -- numa partida de 1 Sobrevivente isso não é feito nenhum).
	if survivorTotal > 1 and #survivorsAlive == 1 then
		local player = MatchStatsService.GetPlayer(survivorsAlive[1])
		if player then
			MatchRewardService.AddXP(player, "LastSurvivor", { Silent = true })
		end
	end

	-- Monstro eliminou todos os Sobreviventes.
	if survivorTotal > 0 and eliminatedSurvivors == survivorTotal then
		for userId, session in sessions do
			if MatchRewardsConfig.MonsterRoles[session.Role] then
				local player = MatchStatsService.GetPlayer(userId)
				if player then
					MatchRewardService.AddXP(player, "AllSurvivorsEliminated", { Silent = true })
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function MatchRewardService.Init()
	if initialized then
		return
	end
	initialized = true

	-- Fecha o ciclo sem require circular: MatchStatsService concede XP
	-- (pulso de sobrevivência, fim de perseguição, inatividade) por este
	-- gancho, sem precisar dar require neste módulo.
	MatchStatsService.SetRewardHook(function(player, actionId, context)
		return MatchRewardService.AddXP(player, actionId, context :: any)
	end)

	-- Estado anti-farm é por PARTIDA: uma partida nova não pode herdar
	-- cooldown nem contagem da anterior.
	RoundManager.RoundPrepared.Event:Connect(function()
		table.clear(actionStates)
		table.clear(healPairCooldown)
		table.clear(hitPairCooldown)
	end)

	connectDamage()
	connectEscapes()
	connectItemPickups()
	connectRadioInstall()
	connectLeaving()
end

--[[
	IsEliminatedPlayer(player)
	Reexportado do Elimination só pra deixar explícito, pra quem ler este
	arquivo, que "morto" aqui é o mesmo conceito do resto do jogo -- e não uma
	segunda definição de morte que poderia divergir.
]]
function MatchRewardService.IsEliminatedPlayer(player: Player): boolean
	return Elimination.IsEliminated(player)
end

-- Reexportado pelo mesmo motivo: papéis vêm do GameConfig, não de string solta.
MatchRewardService.Roles = GameConfig.Roles

return MatchRewardService
