-- Real DataStoreManager + LevelSystem against a deterministic DataStore
-- double. The whole point of this suite: prove the delta-merge save path
-- actually protects XP under the exact conditions that would have lost it
-- with a naive "overwrite the whole document" save.

local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback) table.insert(listeners, callback) end,
		Fire = function(_, ...) for _, callback in listeners do callback(...) end end,
	}
end

-- "A nuvem": um único DataStore compartilhado por TODAS as instâncias de
-- servidor criadas por newServer(). É isso que permite simular dois
-- servidores reais com o mesmo jogador.
local cloud: { [string]: any } = {}

-- Falhas injetadas: as próximas N chamadas de Get/UpdateAsync (de QUALQUER
-- servidor) erram, pra exercitar o retry/backoff e a trava de canSave.
local faultsRemaining = 0
local function maybeFault()
	if faultsRemaining > 0 then
		faultsRemaining -= 1
		error("simulated DataStore outage", 0)
	end
end

-- Hook de uma tirada: setado por Join(userId, onDuringLoad), consumido pelo
-- próximo GetAsync (que é exatamente onde loadProfileAsync está "em voo").
local duringGetHook: (() -> ())? = nil

local function makeStore()
	return {
		GetAsync = function(_, key)
			maybeFault()
			local hook = duringGetHook
			if hook then
				duringGetHook = nil
				hook()
			end
			return cloud[key]
		end,
		UpdateAsync = function(_, key, transform)
			maybeFault()
			local newValue = transform(cloud[key])
			cloud[key] = newValue
			return newValue
		end,
	}
end

local LevelSystem = assert(loadstring(sources.LevelSystem, "LevelSystem"))()

--[[
	newServer()
	Uma instância INDEPENDENTE de DataStoreManager (seu próprio `profiles`
	interno), como se fosse outro processo de servidor Roblox -- mas lendo e
	gravando na mesma `cloud` acima. Real duplicação de estado; sem isso não
	daria pra testar dois servidores com o mesmo jogador de verdade.
]]
local function newServer()
	local Players = { PlayerAdded = signal(), PlayerRemoving = signal() }
	function Players:GetPlayers() return {} end

	local ReplicatedStorage = { Modules = setmetatable({}, { __index = function(_, k) return k end }) }
	local services = {
		DataStoreService = { GetDataStore = function(_, _name) return makeStore() end },
		Players = Players,
		ReplicatedStorage = ReplicatedStorage,
	}

	local boundToClose: (() -> ())? = nil
	local modules = {}
	local env
	env = setmetatable({
		game = {
			GetService = function(_, name) return assert(services[name], name) end,
			BindToClose = function(_, fn) boundToClose = fn end,
		},
		task = {
			spawn = function(callback, ...)
				-- Roblox isola erro de dentro de um task.spawn do chamador;
				-- espelhado aqui pra combinar com o truque do task.wait abaixo.
				pcall(callback, ...)
			end,
			wait = function(seconds)
				if seconds and seconds >= 60 then
					-- Só o laço de autosave espera um intervalo tão longo. Os
					-- testes disparam gravação na mão (saída/shutdown), então
					-- esse laço nunca precisa completar de verdade -- ele
					-- morre aqui (isolado pelo pcall do task.spawn acima) em
					-- vez de girar num "while true" sem yield real.
					error("test double: autosave interval never elapses on its own", 0)
				end
			end,
		},
		warn = function() end,
		print = function() end,
		typeof = function(value) return type(value) end,
	}, { __index = getfenv() })

	local function load(name)
		if modules[name] then return modules[name] end
		local chunk = assert(loadstring(sources[name], name))
		setfenv(chunk, env)
		modules[name] = chunk()
		return modules[name]
	end
	env.require = load

	local DataStoreManager = load("DataStoreManager")
	DataStoreManager.Init()

	return {
		Module = DataStoreManager,
		-- onDuringLoad dispara de DENTRO do GetAsync desta chamada -- ou
		-- seja, depois que onPlayerAdded já criou o perfil padrão, mas
		-- ANTES do load aplicar o que estava salvo. É a janela exata em
		-- que ganhar XP não pode sumir.
		Join = function(userId: number, onDuringLoad: ((Player) -> ())?)
			local player = { UserId = userId, Name = "Player" .. userId } :: any
			if onDuringLoad then
				duringGetHook = function() onDuringLoad(player) end
			end
			Players.PlayerAdded:Fire(player)
			return player
		end,
		Leave = function(player) Players.PlayerRemoving:Fire(player) end,
		Shutdown = function() (assert(boundToClose, "Init() não registrou BindToClose"))() end,
	}
end

local function key(userId: number): string
	return "Player_" .. tostring(userId)
end

--------------------------------------------------------------------------------
-- 1) Sessão nova: sem save prévio, ganha XP, sai -- grava.
--------------------------------------------------------------------------------
do
	local server = newServer()
	local alice = server.Join(1)
	assert(server.Module.IsLoaded(alice), "sem falha injetada, o load síncrono deste dublê já terminou")
	assert(server.Module.GetXP(alice) == 0)

	server.Module.AddXP(alice, 120)
	assert(server.Module.GetXP(alice) == 120)

	server.Leave(alice)
	assert(cloud[key(1)].xp == 120, "sair deve gravar o XP ganho na sessão")
end
print("PASS: sessão nova ganha XP e grava ao sair")

--------------------------------------------------------------------------------
-- 2) DOIS SERVIDORES, MESMO JOGADOR: a gravação por delta SOMA, nunca
--    sobrescreve. É a limitação documentada que este redesenho resolve.
--------------------------------------------------------------------------------
do
	local serverA = newServer()
	local serverB = newServer()

	local playerA = serverA.Join(3)
	local playerB = serverB.Join(3) -- mesmo UserId, "outro servidor"

	serverA.Module.AddXP(playerA, 100)
	serverB.Module.AddXP(playerB, 50)

	serverA.Leave(playerA) -- grava primeiro: cloud vai a 100
	assert(cloud[key(3)].xp == 100)

	serverB.Leave(playerB) -- grava depois: soma 50 em cima do 100 do outro servidor
	assert(cloud[key(3)].xp == 150, "o save do segundo servidor tem que SOMAR, não sobrescrever com o próprio total")
end
print("PASS: dois servidores com o mesmo jogador somam XP em vez de um apagar o outro")

--------------------------------------------------------------------------------
-- 3) Cosméticos: união de conjuntos no mesmo cenário de dois servidores.
--------------------------------------------------------------------------------
do
	local serverA = newServer()
	local serverB = newServer()
	local playerA = serverA.Join(4)
	local playerB = serverB.Join(4)

	serverA.Module.UnlockCosmetic(playerA, "ChapeuPirata")
	serverB.Module.UnlockCosmetic(playerB, "OculosNeon")

	serverA.Leave(playerA)
	serverB.Leave(playerB)

	local saved = cloud[key(4)]
	assert(saved.cosmetics.ChapeuPirata and saved.cosmetics.OculosNeon,
		"os dois cosméticos, de servidores diferentes, têm que sobreviver os dois")
end
print("PASS: cosméticos de servidores diferentes se unem em vez de um substituir o outro")

--------------------------------------------------------------------------------
-- 4) XP ganho ENQUANTO o load ainda está "em voo" não pode sumir quando o
--    load termina e descobre o que já estava salvo.
--------------------------------------------------------------------------------
do
	cloud[key(2)] = { version = 1, xp = 50, cosmetics = {} }
	local server = newServer()

	local bob = server.Join(2, function(player)
		-- Neste ponto o perfil padrão (xp=0) já existe mas o load (que vai
		-- achar xp=50 salvo) ainda não rodou. A versão antiga do módulo
		-- perderia isto ao mesclar; a atual soma baseXP + unsavedXP sempre.
		server.Module.AddXP(player, 30)
	end)

	assert(server.Module.GetXP(bob) == 80, "50 já salvos + 30 ganhos durante o load, sem perder nenhum dos dois")
end
print("PASS: XP ganho durante o load em voo soma com o que já estava salvo")

--------------------------------------------------------------------------------
-- 5) Falha de LEITURA em todas as tentativas: canSave trava em false, nada
--    é sobrescrito -- perder a sessão é aceitável, perder o histórico não.
--------------------------------------------------------------------------------
do
	cloud[key(5)] = { version = 1, xp = 999, cosmetics = {} }
	faultsRemaining = 10 -- mais que MAX_ATTEMPTS: todas as tentativas de load falham
	local server = newServer()
	local carl = server.Join(5)
	faultsRemaining = 0

	assert(server.Module.IsLoaded(carl))
	assert(server.Module.GetXP(carl) == 0, "load falhou: joga com o padrão, não inventa o XP salvo")

	server.Module.AddXP(carl, 40)
	server.Leave(carl)

	assert(cloud[key(5)].xp == 999, "canSave=false depois de falha de load: NUNCA grava por cima do que já existe")
end
print("PASS: falha de load trava a gravação em vez de arriscar sobrescrever o save real")

--------------------------------------------------------------------------------
-- 6) Falha de ESCRITA transitória: retryAsync tenta de novo e consegue.
--------------------------------------------------------------------------------
do
	local server = newServer()
	local dora = server.Join(6)
	server.Module.AddXP(dora, 10)

	faultsRemaining = 2 -- as duas primeiras tentativas de save falham; a 3ª (de 4) resolve
	server.Leave(dora)
	faultsRemaining = 0

	assert(cloud[key(6)].xp == 10, "retry com backoff deve conseguir gravar depois de falhas transitórias")
end
print("PASS: falha transitória de gravação se recupera via retry")

--------------------------------------------------------------------------------
-- 7) Nada mudou desde a última gravação confirmada -> não tenta gravar de
--    novo (economiza cota do DataStore).
--------------------------------------------------------------------------------
do
	local server = newServer()
	local erin = server.Join(7)
	server.Module.AddXP(erin, 5)
	server.Leave(erin) -- primeira gravação de verdade: xp = 5

	-- Se uma segunda gravação (sem NENHUMA alteração) fosse tentada, ela
	-- chamaria UpdateAsync de novo -- e com faultsRemaining alto isso
	-- deixaria o valor gravado poluído/inconsistente. Como dirtyGeneration
	-- não mudou, saveProfile deve nem tentar.
	faultsRemaining = 99
	server.Leave(erin) -- "sai" de novo sem ter ganhado nada no meio
	faultsRemaining = 0

	assert(cloud[key(7)].xp == 5, "perfil sem alteração não deveria ter gerado uma gravação nova")
end
print("PASS: perfil sem alteração não gera gravação nova")

--------------------------------------------------------------------------------
-- 8) Shutdown do servidor (BindToClose) grava TODOS os perfis pendentes,
--    não só quem saiu explicitamente.
--------------------------------------------------------------------------------
do
	local server = newServer()
	local gina = server.Join(9)
	local henry = server.Join(90)
	server.Module.AddXP(gina, 15)
	server.Module.AddXP(henry, 25)

	server.Shutdown()

	assert(cloud[key(9)].xp == 15 and cloud[key(90)].xp == 25, "BindToClose deve gravar todo mundo, não só quem saiu")
end
print("PASS: shutdown do servidor grava todos os perfis pendentes")

--------------------------------------------------------------------------------
-- 9) Nível da conta: os atalhos de DataStoreManager batem com a curva
--    "crua" de LevelSystem pro mesmo total de XP.
--------------------------------------------------------------------------------
do
	local server = newServer()
	local finn = server.Join(8)
	server.Module.AddXP(finn, 5000)

	local expectedLevel, expectedInto, expectedForNext, expectedAtMax = LevelSystem.GetProgress(5000)
	local level, into, forNext, atMax = server.Module.GetProgress(finn)

	assert(level == expectedLevel and server.Module.GetLevel(finn) == expectedLevel)
	assert(into == expectedInto and forNext == expectedForNext and atMax == expectedAtMax)
end
print("PASS: GetLevel/GetProgress da conta batem com a curva de LevelSystem")

print("Todos os cenários de DataStoreManager passaram (dublê determinístico; não substitui teste real de DataStore no Studio publicado).")
