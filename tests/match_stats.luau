--!nocheck
-- Executado por tests/run_match_stats.py contra os módulos REAIS de XP,
-- estatísticas e resultado de partida, com relógio virtual.
--
-- O que é real aqui: MatchStatsTypes, MatchRewardsConfig, MatchStatsService,
-- MatchRewardService e MatchResultsService -- os arquivos de produção.
-- O que é dublê: Roblox (Players, RunService, Instance, Vector3) e os sistemas
-- que os serviços observam (RoundManager, DamageSystem, StaminaSystem,
-- ExtractionSystem, ItemDiscovery), que nestes testes só
-- precisam disparar eventos.

--------------------------------------------------------------------------------
-- Dublês do Roblox
--------------------------------------------------------------------------------

local function fixture()
	local now = 0
	local deferred = {}

	local function signal()
		local listeners = {}
		return {
			Connect = function(_, callback)
				table.insert(listeners, callback)
				return { Disconnect = function() end }
			end,
			Fire = function(_, ...)
				for _, callback in table.clone(listeners) do
					callback(...)
				end
			end,
			listeners = listeners,
		}
	end

	local function bindable()
		local event = signal()
		return { Event = event, Fire = function(_, ...) event:Fire(...) end }
	end

	----------------------------------------------------------------------------
	-- Vector3 com aritmética de verdade: os testes de distância dependem dela.
	----------------------------------------------------------------------------
	local Vector3M = {}
	Vector3M.__index = function(self, key)
		if key == "Magnitude" then
			return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		end
		return rawget(Vector3M, key)
	end
	local Vector3 = {}
	function Vector3.new(x, y, z)
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3M)
	end
	Vector3M.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
	Vector3M.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
	Vector3.zero = Vector3.new(0, 0, 0)

	----------------------------------------------------------------------------
	-- Players + jogadores
	----------------------------------------------------------------------------
	local Players = { __isInstance = true }
	Players.PlayerRemoving = signal()
	Players.PlayerAdded = signal()
	local people = {}
	function Players:GetPlayers() return people end
	function Players:GetPlayerFromCharacter() return nil end

	local function player(userId, name)
		local attributes = {}
		local root = {
			__isInstance = true,
			Position = Vector3.new(0, 0, 0),
			IsA = function(_, class) return class == "BasePart" end,
		}
		local humanoid = { __isInstance = true, Health = 100, MaxHealth = 100 }
		local character = {
			__isInstance = true,
			FindFirstChildOfClass = function(_, class)
				return if class == "Humanoid" then humanoid else nil
			end,
			FindFirstChild = function(_, childName)
				return if childName == "HumanoidRootPart" then root else nil
			end,
			GetAttribute = function(_, key) return attributes["c_" .. key] end,
			SetAttribute = function(_, key, value) attributes["c_" .. key] = value end,
		}

		local p = {
			__isInstance = true,
			UserId = userId,
			Name = name or ("Player" .. userId),
			DisplayName = name or ("Player" .. userId),
			Parent = Players,
			Character = character,
			Root = root,
			Humanoid = humanoid,
			IsA = function(_, class) return class == "Player" end,
			GetAttribute = function(_, key) return attributes[key] end,
			SetAttribute = function(_, key, value) attributes[key] = value end,
		}
		table.insert(people, p)
		return p
	end

	----------------------------------------------------------------------------
	-- Remotes: registram tudo que foi enviado, e se alguém conectou OnServerEvent
	----------------------------------------------------------------------------
	local Remotes = setmetatable({}, {
		__index = function(t, key)
			local remote = { sent = {}, OnServerEvent = signal() }
			function remote:FireClient(target, ...)
				table.insert(self.sent, { player = target, args = { ... } })
			end
			function remote:FireAllClients(...)
				table.insert(self.sent, { player = nil, args = { ... } })
			end
			rawset(t, key, remote)
			return remote
		end,
	})

	----------------------------------------------------------------------------
	-- Módulos dublados
	----------------------------------------------------------------------------
	local RunService = {
		Heartbeat = signal(),
		IsStudio = function() return false end,
	}

	local GameConfig = {
		Roles = { Survivor = "Sobrevivente", Monster = "Monstro", Spy = "Espiao" },
		Characters = { SprintSpeedRatio = 1.35 },
	}

	local RoundManager = { RoundPrepared = bindable(), RoundEnded = bindable() }
	local StaminaSystem = { MovementSampled = bindable() }
	local DamageSystem = { DamageApplied = bindable(), Healed = bindable() }
	local ExtractionSystem = { SurvivorsExtracted = bindable() }
	local DropItemSystem = { ItemPickedUp = bindable() }
	local RadioPieces = { PiecePickedUp = bindable() }
	local RadioInstallSystem = { PieceInstalled = bindable(), AllInstalled = bindable() }
	local Elimination = {
		IsEliminated = function(p) return p:GetAttribute("Eliminado") == true end,
		Reset = function(p) p:SetAttribute("Eliminado", nil) end,
	}

	-- Dublê de MapMarkers.CategoryOf: só as poucas categorias que os testes
	-- realmente precisam distinguir (importante x não-importante).
	local ITEM_CATEGORY_BY_ID = { Gasolina = "Fuel", FacaImprovisada = "Melee" }
	local ITEM_CATEGORY_BY_NAME = { Glock17 = "Firearm" }
	local MapMarkers = {
		CategoryOf = function(toolName, itemId)
			return (itemId and ITEM_CATEGORY_BY_ID[itemId])
				or (toolName and ITEM_CATEGORY_BY_NAME[toolName])
				or "Material"
		end,
	}

	-- Persistência não é o que esta suíte testa (isso é DataStoreManager, com
	-- seu próprio teste); aqui só precisa não quebrar o require de
	-- MatchResultsService. XP creditado fica só na memória do teste.
	local persistedXP: { [Player]: number } = {}
	local DataStoreManager = {
		GetXP = function(player) return persistedXP[player] or 0 end,
		AddXP = function(player, amount) persistedXP[player] = (persistedXP[player] or 0) + amount end,
	}

	local modules = {
		GameConfig = GameConfig,
		MapMarkers = MapMarkers,
		Remotes = Remotes,
		Elimination = Elimination,
		RoundManager = RoundManager,
		StaminaSystem = StaminaSystem,
		DamageSystem = DamageSystem,
		ExtractionSystem = ExtractionSystem,
		DropItemSystem = DropItemSystem,
		RadioPieces = RadioPieces,
		RadioInstallSystem = RadioInstallSystem,
		DataStoreManager = DataStoreManager,
	}

	local ReplicatedStorage = { __isInstance = true }
	ReplicatedStorage.Modules = setmetatable({}, { __index = function(_, name) return name end })

	local env
	env = setmetatable({
		game = {
			GetService = function(_, serviceName)
				return ({
					Players = Players,
					ReplicatedStorage = ReplicatedStorage,
					RunService = RunService,
				})[serviceName]
			end,
		},
		script = { Parent = setmetatable({}, { __index = function(_, name) return name end }) },
		os = { clock = function() return now end, time = function() return math.floor(now) end },
		task = {
			spawn = function(callback, ...) callback(...) end,
			delay = function(_, callback) callback() end,
			wait = function() end,
			-- Fila de verdade: o MatchStatsService usa defer justamente pra
			-- rodar DEPOIS dos listeners síncronos do RoundEnded. Se aqui o
			-- defer fosse imediato, o teste não exercitaria essa ordem.
			defer = function(callback, ...) table.insert(deferred, { callback, ... }) end,
		},
		print = function() end,
		warn = function() end,
		Vector3 = Vector3,
		typeof = function(value)
			if type(value) == "table" and rawget(value, "__isInstance") then
				return "Instance"
			end
			return type(value)
		end,
		Instance = {
			new = function(class)
				if class == "BindableEvent" then
					return bindable()
				end
				return { __isInstance = true }
			end,
		},
	}, { __index = getfenv() })

	env.require = function(name)
		if not modules[name] then
			local chunk = assert(loadstring(sources[name], name))
			setfenv(chunk, env)
			modules[name] = chunk()
		end
		return modules[name]
	end

	local Stats = env.require("MatchStatsService")
	local Rewards = env.require("MatchRewardService")
	local Results = env.require("MatchResultsService")
	local Config = env.require("MatchRewardsConfig")
	local Types = env.require("MatchStatsTypes")

	Stats.Init()
	Rewards.Init()
	Results.Init()

	--[[ advance(seconds) -- anda com o relógio e dispara o Heartbeat que os
	     serviços usam pra medir (tempo vivo, perseguição, ociosidade). ]]
	local function advance(seconds, steps)
		local slices = steps or math.max(1, math.floor(seconds / 0.5 + 0.5))
		local slice = seconds / slices
		for _ = 1, slices do
			now += slice
			RunService.Heartbeat:Fire(slice)
		end
	end

	--[[ sample(p, position, speed) -- uma amostra de movimento como o
	     StaminaSystem produz (ele mede a 20 Hz e publica isso). ]]
	local function sample(p, position, speed)
		p.Root.Position = position
		StaminaSystem.MovementSampled:Fire(p, p.Character, p.Humanoid, p.Root, speed or 8, 16)
	end

	local function kill(p)
		p:SetAttribute("Eliminado", true)
		p.Humanoid.Health = 0
		Stats.MarkEliminated(p)
	end

	local function leave(p)
		p.Parent = nil
		local index = table.find(people, p)
		if index then
			table.remove(people, index)
		end
		Players.PlayerRemoving:Fire(p)
	end

	local function startMatch(roster)
		RoundManager.RoundPrepared:Fire(roster)
	end

	--[[ flush() -- roda o que o task.defer enfileirou, como o Roblox faria no
	     próximo ponto de retomada. ]]
	local function flush()
		while #deferred > 0 do
			local job = table.remove(deferred, 1)
			job[1](table.unpack(job, 2))
		end
	end

	local function endMatch(winner, reason)
		RoundManager.RoundEnded:Fire(winner or "Sobreviventes", reason or "teste")
		flush()
	end

	--[[ resultsFor(p) -- payload que o servidor ENVIOU para `p`, se enviou. ]]
	local function resultsFor(p)
		for _, entry in Remotes.MatchResults.sent do
			if entry.player == p then
				return entry.args[1]
			end
		end
		return nil
	end

	local function notificationsFor(p)
		local out = {}
		for _, entry in Remotes.MatchXPNotification.sent do
			if entry.player == p then
				table.insert(out, entry.args[1])
			end
		end
		return out
	end

	-- Tool falso o bastante pra passar pelos dois caminhos de pickup: tem
	-- Attributes e Name, que é tudo que MatchRewardService lê de uma Tool.
	local function tool(name, worldItemId)
		local attributes = { WorldItemId = worldItemId }
		return {
			__isInstance = true,
			Name = name,
			GetAttribute = function(_, key) return attributes[key] end,
			SetAttribute = function(_, key, value) attributes[key] = value end,
		}
	end

	return {
		Stats = Stats,
		Rewards = Rewards,
		Results = Results,
		Config = Config,
		Types = Types,
		Remotes = Remotes,
		DamageSystem = DamageSystem,
		ExtractionSystem = ExtractionSystem,
		DropItemSystem = DropItemSystem,
		RadioPieces = RadioPieces,
		RadioInstallSystem = RadioInstallSystem,
		player = player,
		tool = tool,
		advance = advance,
		sample = sample,
		kill = kill,
		leave = leave,
		startMatch = startMatch,
		endMatch = endMatch,
		resultsFor = resultsFor,
		notificationsFor = notificationsFor,
		Vector3 = Vector3,
		clock = function() return now end,
	}
end

--------------------------------------------------------------------------------
-- Runner
--------------------------------------------------------------------------------

local passed = 0
local function test(name, callback)
	callback()
	passed += 1
	print("PASS " .. name)
end

local function survivorAndMonster(f)
	local survivor = f.player(1, "Sobrevivente1")
	local monster = f.player(2, "Monstro1")
	survivor:SetAttribute("Role", "Sobrevivente")
	monster:SetAttribute("Role", "Monstro")
	f.startMatch({ survivor, monster })
	return survivor, monster
end

--------------------------------------------------------------------------------
-- 1. Dois jogadores recebendo XP diferente ao mesmo tempo
--------------------------------------------------------------------------------

test("dois jogadores acumulam XP de forma independente", function()
	local f = fixture()
	local a = f.player(1, "A")
	local b = f.player(2, "B")
	a:SetAttribute("Role", "Sobrevivente")
	b:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ a, b })

	assert(f.Rewards.AddXP(a, "MonsterStunned"), "A deveria ganhar XP")
	assert(f.Rewards.AddXP(b, "AllySaved"), "B deveria ganhar XP")

	local sessionA = f.Stats.GetSession(a)
	local sessionB = f.Stats.GetSession(b)

	assert(sessionA.MatchXP == f.Config.Actions.MonsterStunned.XP, "XP de A errado: " .. sessionA.MatchXP)
	assert(sessionB.MatchXP == f.Config.Actions.AllySaved.XP, "XP de B errado: " .. sessionB.MatchXP)
	assert(sessionA.MatchXP ~= sessionB.MatchXP, "os dois ficaram com o mesmo XP")

	-- Nenhuma ação de um aparece no histórico do outro.
	assert(#sessionA.ActionHistory == 1 and sessionA.ActionHistory[1].ActionId == "MonsterStunned")
	assert(#sessionB.ActionHistory == 1 and sessionB.ActionHistory[1].ActionId == "AllySaved")

	-- Nem na categoria.
	assert(sessionA.XPBreakdown.Teamwork == 0, "XP de B vazou pra categoria de A")
	assert(sessionB.XPBreakdown.Combat == 0, "XP de A vazou pra categoria de B")
end)

--------------------------------------------------------------------------------
-- 2. Sobrevivente e Monstro usam tabelas de recompensa diferentes
--------------------------------------------------------------------------------

test("cada papel só ganha as ações do próprio papel", function()
	local f = fixture()
	local survivor, monster = survivorAndMonster(f)

	-- Ação de Monstro não paga pra Sobrevivente...
	assert(not f.Rewards.AddXP(survivor, "SurvivorEliminated", { TargetUserId = 99 }))
	-- ...e ação de Sobrevivente não paga pro Monstro.
	assert(not f.Rewards.AddXP(monster, "MonsterStunned"))

	-- Cada um ganha a sua.
	assert(f.Rewards.AddXP(survivor, "MonsterStunned"))
	assert(f.Rewards.AddXP(monster, "MonsterPowerUsed"))

	assert(f.Stats.GetSession(survivor).XPBreakdown.Combat > 0)
	assert(f.Stats.GetSession(monster).XPBreakdown.Monster > 0)
	assert(f.Stats.GetSession(survivor).XPBreakdown.Monster == 0)
end)

--------------------------------------------------------------------------------
-- 3. Ação repetida respeita cooldown e limite por partida
--------------------------------------------------------------------------------

test("ação repetida respeita cooldown e limite da partida", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	local action = f.Config.Actions.MonsterStunned
	assert(action.Cooldown and action.Cooldown > 0, "o teste supõe cooldown configurado")

	assert(f.Rewards.AddXP(survivor, "MonsterStunned"), "primeira concessão deveria passar")
	assert(not f.Rewards.AddXP(survivor, "MonsterStunned"), "cooldown não segurou a segunda")

	-- Depois do cooldown, paga de novo.
	f.advance(action.Cooldown + 1)
	assert(f.Rewards.AddXP(survivor, "MonsterStunned"), "cooldown não liberou")

	-- Limite da partida: gasta todas as concessões restantes.
	local granted = 2
	for _ = 1, action.MaxPerMatch + 5 do
		f.advance(action.Cooldown + 1)
		if f.Rewards.AddXP(survivor, "MonsterStunned") then
			granted += 1
		end
	end
	assert(granted == action.MaxPerMatch,
		string.format("limite da partida ignorado: %d concessões (máximo %d)", granted, action.MaxPerMatch))
end)

--------------------------------------------------------------------------------
-- 4. Objetivo não concede XP duplicado
--------------------------------------------------------------------------------

test("o mesmo objetivo nunca paga duas vezes", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	f.Rewards.RecordObjectiveStep(survivor, "Radio_Antena")
	local afterFirst = f.Stats.GetSession(survivor).MatchXP

	-- Mesma etapa de novo -- inclusive depois de qualquer cooldown possível.
	f.advance(120)
	f.Rewards.RecordObjectiveStep(survivor, "Radio_Antena")
	assert(f.Stats.GetSession(survivor).MatchXP == afterFirst, "a mesma etapa pagou duas vezes")

	-- Uma etapa DIFERENTE continua pagando.
	f.Rewards.RecordObjectiveStep(survivor, "Radio_Bateria")
	assert(f.Stats.GetSession(survivor).MatchXP > afterFirst, "etapa nova não pagou")

	-- E o objetivo inteiro também é único.
	f.Rewards.RecordObjectiveCompleted(survivor, "Radio")
	local afterObjective = f.Stats.GetSession(survivor).MatchXP
	f.advance(120)
	f.Rewards.RecordObjectiveCompleted(survivor, "Radio")
	assert(f.Stats.GetSession(survivor).MatchXP == afterObjective, "o objetivo pagou duas vezes")
end)

--------------------------------------------------------------------------------
-- 5. Jogador morre e mantém o relatório
--------------------------------------------------------------------------------

test("jogador eliminado mantém o relatório até o fim da partida", function()
	local f = fixture()
	local survivor, monster = survivorAndMonster(f)

	f.Rewards.AddXP(survivor, "MonsterStunned")
	local xpBeforeDeath = f.Stats.GetSession(survivor).MatchXP
	assert(xpBeforeDeath > 0)

	f.advance(10)
	local aliveAtDeath = f.Stats.GetStat(survivor, "AliveTime")
	f.kill(survivor)

	local session = f.Stats.GetSession(survivor)
	assert(session ~= nil, "a sessão do morto foi apagada")
	assert(session.Eliminated and not session.IsAlive)
	assert(session.MatchXP == xpBeforeDeath, "o XP do morto mudou")

	-- Morto não acumula mais tempo vivo.
	f.advance(10)
	assert(math.abs(f.Stats.GetStat(survivor, "AliveTime") - aliveAtDeath) < 0.6,
		"o morto continuou acumulando tempo vivo")

	f.endMatch("Monstro", "fim")
	local payload = f.resultsFor(survivor)
	assert(payload ~= nil, "o jogador morto não recebeu relatório")
	assert(payload.MatchXP == xpBeforeDeath)
	assert(#payload.Actions > 0, "o histórico do morto sumiu")
	assert(f.resultsFor(monster) ~= nil)
end)

--------------------------------------------------------------------------------
-- 6. Jogador escapa e mantém o relatório
--------------------------------------------------------------------------------

test("jogador que escapa é marcado e mantém o relatório", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	f.ExtractionSystem.SurvivorsExtracted:Fire({ survivor })

	local session = f.Stats.GetSession(survivor)
	assert(session.Escaped, "não marcou a fuga")
	assert(session.EscapeMethod == "Helicoptero", "método de fuga errado: " .. tostring(session.EscapeMethod))
	assert(session.XPBreakdown.Survival >= f.Config.Actions.Escaped.XP, "não pagou o XP de fuga")

	-- Fugir de novo (dois eventos pro mesmo jogador) não paga duas vezes.
	local xpAfterEscape = session.MatchXP
	f.ExtractionSystem.SurvivorsExtracted:Fire({ survivor })
	assert(session.MatchXP == xpAfterEscape, "a fuga pagou duas vezes")

	f.endMatch("Sobreviventes", "fuga")
	local payload = f.resultsFor(survivor)
	assert(payload ~= nil and payload.MatchXP == xpAfterEscape)
end)

--------------------------------------------------------------------------------
-- 7. Jogador sai no meio da partida
--------------------------------------------------------------------------------

test("quem sai no meio é penalizado e mantém a sessão", function()
	local f = fixture()
	local a = f.player(1, "Fica")
	local b = f.player(2, "Sai")
	a:SetAttribute("Role", "Sobrevivente")
	b:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ a, b })

	f.Rewards.AddXP(b, "MonsterStunned")
	local before = f.Stats.GetSession(b).MatchXP

	f.leave(b)

	local session = f.Stats.GetSession(b)
	assert(session ~= nil, "a sessão de quem saiu foi apagada")
	assert(session.Left, "não marcou que saiu")
	assert(session.MatchXP == before + f.Config.Actions.AbandonedMatch.XP,
		"penalidade de abandono não aplicada: " .. session.MatchXP)
	assert(session.XPBreakdown.Penalties < 0, "a penalidade não foi para a categoria Penalties")

	-- A penalidade é silenciosa: não adianta notificar quem já saiu.
	assert(#f.notificationsFor(b) == 1, "mandou notificação da penalidade pra quem saiu")

	-- Quem ficou não é afetado.
	assert(f.Stats.GetSession(a).MatchXP == 0)

	f.endMatch("Monstro", "fim")
	-- Quem saiu não recebe relatório (não há pra quem mandar), quem ficou sim.
	assert(f.resultsFor(b) == nil, "mandou relatório pra quem já tinha saído")
	assert(f.resultsFor(a) ~= nil)
end)

test("quem já tinha escapado não leva penalidade ao sair", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	f.ExtractionSystem.SurvivorsExtracted:Fire({ survivor })
	local afterEscape = f.Stats.GetSession(survivor).MatchXP

	f.leave(survivor)
	assert(f.Stats.GetSession(survivor).MatchXP == afterEscape,
		"penalizou quem já tinha terminado a partida")
end)

--------------------------------------------------------------------------------
-- 8. Encerramento normal da partida
--------------------------------------------------------------------------------

test("encerramento normal congela, pontua e envia relatório individual", function()
	local f = fixture()
	local survivor, monster = survivorAndMonster(f)

	f.advance(60)
	f.Rewards.RecordObjectiveStep(survivor, "Radio_Antena")
	f.DamageSystem.DamageApplied:Fire(monster, survivor, 30, false, "Monstro")

	f.endMatch("Monstro", "tempo esgotado")

	local survivorPayload = f.resultsFor(survivor)
	local monsterPayload = f.resultsFor(monster)
	assert(survivorPayload and monsterPayload, "faltou relatório")

	assert(survivorPayload.Winner == "Monstro" and survivorPayload.Reason == "tempo esgotado")
	assert(survivorPayload.Role == "Sobrevivente")
	assert(monsterPayload.Role == "Monstro")
	assert(survivorPayload.PerformanceScore >= 0 and monsterPayload.PerformanceScore >= 0)
	assert(#survivorPayload.Stats > 0, "payload sem estatísticas")

	-- Congelado: nada mais entra depois do fim.
	assert(not f.Rewards.AddXP(survivor, "MonsterStunned"), "concedeu XP depois do fim da partida")
	assert(not f.Stats.AddStat(survivor, "Hits", 1), "aceitou estatística depois do fim")
end)

--------------------------------------------------------------------------------
-- 9. Finalização chamada duas vezes não duplica nada
--------------------------------------------------------------------------------

test("finalizar duas vezes não duplica XP nem relatório", function()
	local f = fixture()
	local survivor, _ = survivorAndMonster(f)

	f.Rewards.AddXP(survivor, "MonsterStunned")

	f.endMatch("Monstro", "fim")
	local xpAfterFirst = f.Stats.GetSession(survivor).MatchXP
	local sentAfterFirst = #f.Remotes.MatchResults.sent

	-- Segunda chamada, pelas duas portas: o evento e a API direta.
	f.endMatch("Monstro", "fim")
	f.Results.FinalizeMatch("Monstro", "fim")

	assert(f.Stats.GetSession(survivor).MatchXP == xpAfterFirst, "o XP mudou na segunda finalização")
	assert(#f.Remotes.MatchResults.sent == sentAfterFirst, "o relatório foi enviado de novo")
end)

test("o bônus de último sobrevivente é aplicado uma vez só", function()
	local f = fixture()
	local a = f.player(1)
	local b = f.player(2)
	local monster = f.player(3)
	a:SetAttribute("Role", "Sobrevivente")
	b:SetAttribute("Role", "Sobrevivente")
	monster:SetAttribute("Role", "Monstro")
	f.startMatch({ a, b, monster })

	f.kill(b)
	f.endMatch("Sobreviventes", "fim")

	local bonus = f.Config.Actions.LastSurvivor.XP
	assert(f.Stats.GetSession(a).XPBreakdown.Bonuses == bonus,
		"bônus de último sobrevivente errado: " .. f.Stats.GetSession(a).XPBreakdown.Bonuses)

	f.Results.FinalizeMatch("Sobreviventes", "fim")
	assert(f.Stats.GetSession(a).XPBreakdown.Bonuses == bonus, "o bônus foi aplicado duas vezes")
end)

--------------------------------------------------------------------------------
-- 10. Próxima partida começa zerada
--------------------------------------------------------------------------------

test("a partida seguinte começa com tudo zerado", function()
	local f = fixture()
	local survivor, monster = survivorAndMonster(f)

	f.advance(30)
	f.Rewards.AddXP(survivor, "MonsterStunned")
	f.Rewards.RecordObjectiveStep(survivor, "Radio_Antena")
	f.kill(survivor)
	f.endMatch("Monstro", "fim")

	assert(f.Stats.GetSession(survivor).MatchXP > 0)

	-- Partida nova.
	survivor:SetAttribute("Eliminado", nil)
	survivor.Humanoid.Health = 100
	f.startMatch({ survivor, monster })

	local session = f.Stats.GetSession(survivor)
	assert(session.MatchXP == 0, "XP passou de uma partida pra outra")
	assert(#session.ActionHistory == 0, "histórico passou de uma partida pra outra")
	assert(session.Stats.AliveTime == 0, "tempo vivo passou de uma partida pra outra")
	assert(not session.Eliminated and session.IsAlive, "o estado de morte passou pra partida nova")
	assert(not session.ResultFinalized, "a sessão nova já nasceu finalizada")

	-- O estado ANTI-FARM também zera: a mesma etapa de objetivo paga de novo
	-- numa partida nova (senão o jogador seria punido pela partida anterior).
	f.Rewards.RecordObjectiveStep(survivor, "Radio_Antena")
	assert(session.MatchXP > 0, "o limite de unicidade vazou da partida anterior")
end)

--------------------------------------------------------------------------------
-- 11. O relatório de cada jogador só tem os dados dele
--------------------------------------------------------------------------------

test("o payload de cada jogador contém só os dados dele", function()
	local f = fixture()
	local a = f.player(1, "Curandeiro")
	local b = f.player(2, "Lutador")
	local monster = f.player(3, "Caçador")
	a:SetAttribute("Role", "Sobrevivente")
	b:SetAttribute("Role", "Sobrevivente")
	monster:SetAttribute("Role", "Monstro")
	f.startMatch({ a, b, monster })

	f.Rewards.AddXP(a, "AllySaved", { TargetUserId = 2 })
	f.Rewards.AddXP(b, "MonsterStunned")
	f.DamageSystem.DamageApplied:Fire(b, monster, 40, false, "Faca")

	f.endMatch("Sobreviventes", "fim")

	local payloadA = f.resultsFor(a)
	local payloadB = f.resultsFor(b)

	-- O XP total é o de cada um.
	assert(payloadA.MatchXP == f.Stats.GetSession(a).MatchXP)
	assert(payloadB.MatchXP == f.Stats.GetSession(b).MatchXP)
	assert(payloadA.MatchXP ~= payloadB.MatchXP, "os dois payloads têm o mesmo XP")

	-- A ação de um não aparece na lista do outro.
	local function hasAction(payload, actionId)
		for _, record in payload.Actions do
			if record.ActionId == actionId then
				return true
			end
		end
		return false
	end
	assert(hasAction(payloadA, "AllySaved") and not hasAction(payloadA, "MonsterStunned"))
	assert(hasAction(payloadB, "MonsterStunned") and not hasAction(payloadB, "AllySaved"))

	-- O payload não carrega sessão, estatística nem histórico de terceiros.
	assert(payloadA.Stats ~= nil and payloadA.ActionHistory == nil)
	for key in payloadA do
		assert(key ~= "Sessions" and key ~= "AllStats", "vazou estado global no payload: " .. key)
	end

	-- Só os destaques são compartilhados -- e eles só levam nome e valor.
	for _, highlight in payloadA.Highlights do
		assert(highlight.Name and highlight.PlayerName and highlight.Value ~= nil)
		assert(highlight.Stats == nil and highlight.ActionHistory == nil, "destaque vazou a sessão do vencedor")
	end
end)

test("as ações repetidas chegam agrupadas no payload", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	local cooldown = f.Config.Actions.MonsterHit.Cooldown + 0.1
	for _ = 1, 4 do
		f.Rewards.AddXP(survivor, "MonsterHit", { TargetUserId = nil })
		f.advance(cooldown, 1)
	end

	f.endMatch("Sobreviventes", "fim")
	local payload = f.resultsFor(survivor)

	local hit
	for _, record in payload.Actions do
		if record.ActionId == "MonsterHit" then
			hit = record
		end
	end
	assert(hit, "a ação não apareceu no payload")
	assert(hit.Count == 4, "não agrupou as repetições: Count = " .. tostring(hit.Count))
	assert(hit.XP == f.Config.Actions.MonsterHit.XP * 4, "o XP agrupado está errado: " .. hit.XP)
end)

--------------------------------------------------------------------------------
-- 12. Distância ignora teleporte
--------------------------------------------------------------------------------

test("distância percorrida ignora teleporte e conta andar e correr separado", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	local V = f.Vector3

	-- Primeira amostra: só ancora, não mede.
	f.sample(survivor, V.new(0, 0, 0), 8)
	assert(f.Stats.GetStat(survivor, "DistanceWalked") == 0)

	-- Caminhada plausível: 8 studs em 0.6s, abaixo do limiar de sprint.
	f.advance(0.6, 1)
	f.sample(survivor, V.new(8, 0, 0), 8)
	local walked = f.Stats.GetStat(survivor, "DistanceWalked")
	assert(math.abs(walked - 8) < 0.01, "andar não foi medido: " .. walked)
	assert(f.Stats.GetStat(survivor, "DistanceRan") == 0, "andar entrou como corrida")

	-- TELEPORTE: 2000 studs num piscar de olhos. Tem que ser descartado
	-- inteiro -- nem em "andou", nem em "correu".
	f.advance(0.6, 1)
	f.sample(survivor, V.new(2000, 0, 2000), 8)
	assert(math.abs(f.Stats.GetStat(survivor, "DistanceWalked") - walked) < 0.01,
		"o teleporte virou distância andando")
	assert(f.Stats.GetStat(survivor, "DistanceRan") == 0, "o teleporte virou distância correndo")

	-- Corrida de verdade a partir da nova âncora: velocidade acima de
	-- walkBase * SprintSpeedRatio (16 * 1.35 = 21.6).
	f.advance(0.6, 1)
	f.sample(survivor, V.new(2000, 0, 2014), 25)
	local ran = f.Stats.GetStat(survivor, "DistanceRan")
	assert(math.abs(ran - 14) < 0.01, "correr não foi medido: " .. ran)
	assert(f.Stats.GetStat(survivor, "TimeRunning") > 0, "tempo correndo não acumulou")

	-- Tremida parado não conta.
	local before = f.Stats.GetStat(survivor, "DistanceWalked")
	f.advance(0.6, 1)
	f.sample(survivor, V.new(2000.05, 0, 2014), 1)
	assert(f.Stats.GetStat(survivor, "DistanceWalked") == before, "ruído de física virou distância")
end)

test("movimento fora da partida não conta", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")

	local V = f.Vector3
	-- Antes de começar: nem sessão existe.
	f.sample(survivor, V.new(0, 0, 0), 8)
	f.advance(0.6, 1)
	f.sample(survivor, V.new(10, 0, 0), 8)
	assert(f.Stats.GetSession(survivor) == nil, "criou sessão fora da partida")

	f.startMatch({ survivor })
	f.sample(survivor, V.new(0, 0, 0), 8)
	f.advance(0.6, 1)
	f.sample(survivor, V.new(8, 0, 0), 8)
	local during = f.Stats.GetStat(survivor, "DistanceWalked")
	assert(during > 0)

	-- Depois do fim: congelado.
	f.endMatch("Sobreviventes", "fim")
	f.advance(0.6, 1)
	f.sample(survivor, V.new(100, 0, 0), 8)
	assert(f.Stats.GetStat(survivor, "DistanceWalked") == during, "mediu movimento depois do fim")
end)

--------------------------------------------------------------------------------
-- 13. O cliente não tem como criar XP
--------------------------------------------------------------------------------

test("os remotes de XP não aceitam nada do cliente", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	f.Rewards.AddXP(survivor, "MonsterStunned")

	-- Nenhum dos dois remotes tem ouvinte de FireServer: o servidor nunca
	-- conectou OnServerEvent, então um pedido do cliente não tem pra onde ir.
	assert(#f.Remotes.MatchXPNotification.OnServerEvent.listeners == 0,
		"alguém conectou OnServerEvent no remote de notificação")
	assert(#f.Remotes.MatchResults.OnServerEvent.listeners == 0,
		"alguém conectou OnServerEvent no remote de resultados")

	-- E mesmo pelo lado do servidor, não existe caminho pra passar uma
	-- QUANTIDADE de XP: a API só aceita actionId, e um id inventado é recusado.
	assert(not f.Rewards.AddXP(survivor, "XPInfinito"), "aceitou um actionId inventado")
	assert(not f.Rewards.AddXP(survivor, "MonsterStunned", { Units = 999999999 }),
		"aceitou Units numa ação de valor fixo (deveria estar em cooldown)")

	-- Ação variável tem teto: Units absurdo vira MaxUnitsPerGrant.
	local contribution = f.Config.Actions.ObjectiveContribution
	local before = f.Stats.GetSession(survivor).MatchXP
	f.Rewards.RecordObjectiveContribution(survivor, "Radio", 10 ^ 9)
	local gained = f.Stats.GetSession(survivor).MatchXP - before
	local ceiling = math.floor(contribution.XPPerUnit * contribution.MaxUnitsPerGrant + 0.5)
	assert(gained == ceiling, string.format("teto de unidades furado: ganhou %d, teto %d", gained, ceiling))
end)

--------------------------------------------------------------------------------
-- Guardas extras
--------------------------------------------------------------------------------

test("teto de categoria segura o XP mesmo com a ação liberada", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	local cap = f.Config.CategoryCaps.Combat
	local cooldown = f.Config.Actions.MonsterHit.Cooldown + 0.1
	for _ = 1, f.Config.Actions.MonsterHit.MaxPerMatch + 5 do
		f.Rewards.AddXP(survivor, "MonsterHit")
		f.advance(cooldown, 1)
	end
	for _ = 1, f.Config.Actions.MonsterStunned.MaxPerMatch + 5 do
		f.Rewards.AddXP(survivor, "MonsterStunned")
		f.advance(f.Config.Actions.MonsterStunned.Cooldown + 0.1, 1)
	end

	local combat = f.Stats.GetSession(survivor).XPBreakdown.Combat
	assert(combat <= cap, string.format("o teto da categoria foi furado: %d > %d", combat, cap))
end)

test("cura de aliado tem freio por par; curar a si mesmo não paga", function()
	local f = fixture()
	local a = f.player(1)
	local b = f.player(2)
	a:SetAttribute("Role", "Sobrevivente")
	b:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ a, b })

	-- Curar a si mesmo conta na estatística, mas não paga XP de equipe.
	f.DamageSystem.Healed:Fire(a, a, 40)
	assert(f.Stats.GetStat(a, "HealingDone") == 40)
	assert(f.Stats.GetSession(a).XPBreakdown.Teamwork == 0, "auto-cura pagou XP de equipe")

	-- Curar um aliado paga.
	f.DamageSystem.Healed:Fire(a, b, 40)
	local afterFirst = f.Stats.GetSession(a).MatchXP
	assert(afterFirst > 0, "cura de aliado não pagou")

	-- O MESMO par curando de novo logo em seguida NÃO paga -- é o freio contra
	-- duas pessoas se curando em looping pra farmar.
	f.advance(f.Config.Actions.AllyHealed.Cooldown + 1)
	f.DamageSystem.Healed:Fire(a, b, 40)
	assert(f.Stats.GetSession(a).MatchXP == afterFirst, "o par conseguiu farmar cura")

	-- Cura insignificante nunca paga.
	f.advance(120)
	f.DamageSystem.Healed:Fire(a, b, 1)
	assert(f.Stats.GetSession(a).MatchXP == afterFirst, "cura irrelevante pagou XP")
end)

test("dano contra alvo fora da partida não rende nada", function()
	local f = fixture()
	local monster = f.player(1)
	monster:SetAttribute("Role", "Monstro")
	f.startMatch({ monster })

	local outsider = f.player(99)
	f.DamageSystem.DamageApplied:Fire(monster, outsider, 50, true, "Monstro")

	assert(f.Stats.GetStat(monster, "DamageDealt") == 0, "contou dano contra quem não está na partida")
	assert(f.Stats.GetSession(monster).MatchXP == 0, "pagou XP por alvo fora da partida")
end)

test("eliminar o mesmo jogador duas vezes paga uma vez só", function()
	local f = fixture()
	local survivor, monster = survivorAndMonster(f)

	f.DamageSystem.DamageApplied:Fire(monster, survivor, 100, true, "Monstro")
	local afterKill = f.Stats.GetSession(monster).MatchXP
	assert(f.Stats.GetStat(monster, "SurvivorsEliminated") == 1)

	f.advance(60)
	f.DamageSystem.DamageApplied:Fire(monster, survivor, 100, true, "Monstro")
	local kills = f.Stats.GetStat(monster, "SurvivorsEliminated")
	local eliminationXP = f.Config.Actions.SurvivorEliminated.XP
	assert(f.Stats.GetSession(monster).MatchXP < afterKill + eliminationXP,
		"a eliminação do mesmo alvo pagou duas vezes (kills = " .. kills .. ")")
end)

test("destaque sem ninguém acima do mínimo não é concedido", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	-- Partida em que ninguém curou nada.
	f.endMatch("Sobreviventes", "fim")
	local payload = f.resultsFor(survivor)

	for _, highlight in payload.Highlights do
		assert(highlight.Id ~= "Medic", "concedeu 'Médico da Equipe' numa partida sem cura nenhuma")
	end
end)

test("o melhor da partida sai do desempenho, não do XP total", function()
	local f = fixture()
	local grinder = f.player(1, "Acumulador")
	local worker = f.player(2, "Trabalhador")
	grinder:SetAttribute("Role", "Sobrevivente")
	worker:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ grinder, worker })

	-- O "acumulador" ganha muito XP repetindo uma ação barata de combate.
	local cooldown = f.Config.Actions.MonsterHit.Cooldown + 0.1
	for _ = 1, f.Config.Actions.MonsterHit.MaxPerMatch do
		f.Rewards.AddXP(grinder, "MonsterHit")
		f.advance(cooldown, 1)
	end

	-- O "trabalhador" contribui de verdade nos objetivos.
	for index = 1, 6 do
		f.Rewards.RecordObjectiveStep(worker, "Etapa" .. index)
		f.Rewards.RecordItemDelivered(worker, "Peca" .. index)
	end

	f.endMatch("Sobreviventes", "fim")

	local payload = f.resultsFor(worker)
	assert(payload.MVPUserId == worker.UserId,
		"o MVP saiu do XP total em vez do desempenho (MVP = " .. tostring(payload.MVPUserId) .. ")")
	assert(payload.IsMVP, "o payload não marcou o MVP")
	assert(not f.resultsFor(grinder).IsMVP, "marcou dois MVPs")
end)

test("tempo vivo e perseguição são medidos e ficam no payload", function()
	local f = fixture()
	local survivor, monster = survivorAndMonster(f)
	local V = f.Vector3

	-- Longe um do outro: sem perseguição.
	survivor.Root.Position = V.new(0, 0, 0)
	monster.Root.Position = V.new(500, 0, 0)
	f.advance(4)
	assert(f.Stats.GetStat(survivor, "ChasesStarted") == 0)

	-- Monstro chega perto: começa a perseguição.
	monster.Root.Position = V.new(20, 0, 0)
	f.advance(6)
	assert(f.Stats.GetStat(survivor, "ChasesStarted") == 1, "a perseguição não começou")
	assert(f.Stats.GetStat(survivor, "TimesDetected") == 1)
	assert(f.Stats.GetStat(survivor, "TimeChased") > 0, "não acumulou tempo perseguido")

	-- Sobrevivente foge: depois da carência, a perseguição fecha como escapada.
	monster.Root.Position = V.new(600, 0, 0)
	f.advance(f.Config.Timing.ChaseEndGrace + 2)
	assert(f.Stats.GetStat(survivor, "ChasesEscaped") == 1, "não registrou a fuga da perseguição")
	assert(f.Stats.GetSession(survivor).XPBreakdown.Stealth > 0, "não pagou o XP de escapar")

	assert(f.Stats.GetStat(survivor, "AliveTime") > 0, "não mediu tempo vivo")

	f.endMatch("Sobreviventes", "fim")
	local payload = f.resultsFor(survivor)
	local found = false
	for _, stat in payload.Stats do
		if stat.Key == "TimeChased" then
			found = true
			assert(stat.Value:match("s"), "tempo não foi formatado: " .. stat.Value)
		end
	end
	assert(found, "TimeChased não apareceu no payload do Sobrevivente")
end)

test("estatística com nome inválido é recusada", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	assert(not f.Stats.AddStat(survivor, "MonsterHitsTypo", 1), "aceitou uma estatística inexistente")
	assert(f.Stats.AddStat(survivor, "Hits", 1), "recusou uma estatística válida")
end)

test("GetPlayerMatchData devolve cópia, não a sessão viva", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })
	f.Rewards.AddXP(survivor, "MonsterStunned")

	local copy = f.Stats.GetPlayerMatchData(survivor)
	copy.MatchXP = 999999
	copy.Stats.Hits = 999999
	copy.ActionHistory[1].XP = 999999

	local session = f.Stats.GetSession(survivor)
	assert(session.MatchXP ~= 999999, "a cópia alterou o XP de verdade")
	assert(session.Stats.Hits ~= 999999, "a cópia alterou a estatística de verdade")
	assert(session.ActionHistory[1].XP ~= 999999, "a cópia alterou o histórico de verdade")
end)

--------------------------------------------------------------------------------
-- Pickup de itens (regressão: XP não aparecia ao pegar Galão/peças do rádio)
--------------------------------------------------------------------------------
-- ItemDiscovery.ItemDiscovered é só o PING do item aparecendo no MAPA a
-- distância -- não a posse. A XP de "item importante encontrado" tem que
-- disparar quando a Tool entra de fato no inventário, o que só os dois
-- eventos abaixo (DropItemSystem.ItemPickedUp / RadioPieces.PiecePickedUp)
-- representam.

test("pegar um item importante do chão concede XP (ex: Galão de Gasolina)", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	local gasolina = f.tool("Gasolina", "Gasolina")
	f.DropItemSystem.ItemPickedUp:Fire(survivor, gasolina)

	local session = f.Stats.GetSession(survivor)
	assert(session.MatchXP == f.Config.Actions.ImportantItemFound.XP,
		"não pagou XP pelo Galão: " .. session.MatchXP)
	assert(session.Stats.ImportantItemsFound == 1)
	assert(gasolina:GetAttribute("_MatchRewardItemFound") == true, "não marcou a Tool como já paga")
end)

test("item comum (material/melee) não paga XP de achado importante", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	f.DropItemSystem.ItemPickedUp:Fire(survivor, f.tool("PedraAfiada", "PedraAfiada"))
	f.DropItemSystem.ItemPickedUp:Fire(survivor, f.tool("FacaImprovisada", "FacaImprovisada"))

	assert(f.Stats.GetSession(survivor).MatchXP == 0, "material/faca pagou XP de item importante")
end)

test("largar e pegar de volta o mesmo item não paga XP duas vezes", function()
	local f = fixture()
	local a = f.player(1)
	local b = f.player(2)
	a:SetAttribute("Role", "Sobrevivente")
	b:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ a, b })

	local rifle = f.tool("Glock17", nil) -- categoria vem do NOME (arma de fogo)
	f.DropItemSystem.ItemPickedUp:Fire(a, rifle)
	local xpAfterFirst = f.Stats.GetSession(a).MatchXP
	assert(xpAfterFirst > 0, "arma de fogo não pagou XP")

	-- A largou, B pegou a MESMA instância de Tool (drop -> pickup real do jogo).
	f.DropItemSystem.ItemPickedUp:Fire(b, rifle)
	assert(f.Stats.GetSession(b).MatchXP == 0, "o segundo jogador farmou XP pegando o drop do primeiro")
	assert(f.Stats.GetSession(a).MatchXP == xpAfterFirst, "o XP de A mudou quando B pegou a Tool dele")
end)

test("pegar uma peça do rádio paga XP; a mesma peça não paga duas vezes", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	f.RadioPieces.PiecePickedUp:Fire(survivor, "Bateria")
	local afterFirst = f.Stats.GetSession(survivor).MatchXP
	assert(afterFirst == f.Config.Actions.ImportantItemFound.XP, "não pagou XP pela peça do rádio")

	-- Mesma peça (carregador morreu, outro sobrevivente pegou e a devolveu,
	-- ou qualquer replay do mesmo tipo): não paga de novo, mesmo depois do
	-- cooldown da ação -- quem bloqueia aqui é a chave única, não o tempo.
	f.advance(f.Config.Actions.ImportantItemFound.Cooldown + 1)
	f.RadioPieces.PiecePickedUp:Fire(survivor, "Bateria")
	assert(f.Stats.GetSession(survivor).MatchXP == afterFirst, "a mesma peça pagou XP duas vezes")

	-- Uma peça DIFERENTE continua pagando (já fora do cooldown da ação).
	f.RadioPieces.PiecePickedUp:Fire(survivor, "Antena")
	assert(f.Stats.GetSession(survivor).MatchXP > afterFirst, "uma peça diferente não pagou")
end)

test("instalar peça do rádio conta como etapa; instalar as três fecha o objetivo", function()
	local f = fixture()
	local survivor = f.player(1)
	survivor:SetAttribute("Role", "Sobrevivente")
	f.startMatch({ survivor })

	f.RadioInstallSystem.PieceInstalled:Fire(survivor, "Antena")
	local afterOne = f.Stats.GetSession(survivor).MatchXP
	assert(afterOne == f.Config.Actions.ObjectiveStepCompleted.XP, "instalar a peça não pagou a etapa")
	assert(f.Stats.GetSession(survivor).Stats.ObjectiveStepsCompleted == 1)

	f.RadioInstallSystem.PieceInstalled:Fire(survivor, "Bateria")
	f.RadioInstallSystem.PieceInstalled:Fire(survivor, "Transmissor")
	f.RadioInstallSystem.AllInstalled:Fire(survivor)

	local total = f.Stats.GetSession(survivor).MatchXP
	local expected = afterOne * 3 + f.Config.Actions.ObjectiveCompleted.XP
	assert(total == expected, string.format("XP do rádio completo errado: %d (esperado %d)", total, expected))

	-- Reinstalar a mesma peça (hipotético) não paga de novo.
	f.RadioInstallSystem.PieceInstalled:Fire(survivor, "Antena")
	assert(f.Stats.GetSession(survivor).MatchXP == total, "reinstalar a mesma peça pagou XP de novo")
end)

print(string.format("\n%d testes passaram.", passed))
