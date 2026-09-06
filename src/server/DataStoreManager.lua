--!strict
--[[
	DataStoreManager
	Persistência de progressão do jogador (XP total e cosméticos
	desbloqueados), com cache em memória durante a sessão.

	COMO FUNCIONA
	  - Ao entrar, o jogador JÁ recebe um perfil em memória com valores
	    padrão e pode jogar na hora. O carregamento do DataStore acontece em
	    paralelo; quando termina, os dados salvos substituem os padrões e
	    qualquer XP/cosmético ganho nesse meio tempo é reaplicado por cima
	    (pendingXP / pendingCosmetics). Ninguém fica travado esperando.

	  - Se o carregamento falhar em TODAS as tentativas, o perfil fica com
	    canSave = false pelo resto da sessão. Isso é de propósito: salvar
	    por cima de um save que existe mas não conseguimos ler apagaria o
	    progresso real do jogador. Melhor perder a sessão do que o histórico.

	  - Salva automaticamente a cada AUTOSAVE_INTERVAL, ao sair, e no
	    BindToClose (shutdown do servidor). Perfis sem alteração desde o
	    último save são pulados, pra não queimar cota do DataStore à toa.

	FORMATO VERSIONADO
	  Todo save carrega um campo `version`. Pra mudar o formato no futuro:
	    1) suba DATA_VERSION,
	    2) adicione uma função em MIGRATIONS[versaoAntiga] que recebe a
	       tabela antiga e devolve a nova.
	  migrateData() aplica as migrações em sequência, então um save v1 pula
	  pra v2, v3... sem quebrar. Note que o NOME do DataStore não é
	  versionado de propósito -- versionar o nome jogaria fora os saves
	  antigos, que é justamente o que a migração existe pra evitar.

	LIMITAÇÃO CONHECIDA: não há session locking (tipo ProfileService). Se o
	mesmo jogador ficar em dois servidores ao mesmo tempo, o último save
	vence. Pra um jogo de partidas curtas isso raramente acontece, mas é bom
	saber antes de escalar.

	Uso (chamar uma vez no boot do servidor):
		local DataStoreManager = require(script.DataStoreManager)
		DataStoreManager.Init()

		DataStoreManager.AddXP(player, 50)
		DataStoreManager.UnlockCosmetic(player, "ChapeuPirata")
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local DataStoreManager = {}

--------------------------------------------------------------------------------
-- Configuração
--------------------------------------------------------------------------------

local STORE_NAME = "PlayerData" -- não versionar aqui: ver nota no cabeçalho
local KEY_PREFIX = "Player_"

local DATA_VERSION = 1

local MAX_ATTEMPTS = 4 -- tentativas por operação (load ou save)
local RETRY_INITIAL_DELAY = 1 -- segundos; dobra a cada falha (1, 2, 4...)

local AUTOSAVE_INTERVAL = 120 -- segundos entre autosaves

local playerStore = DataStoreService:GetDataStore(STORE_NAME)

--------------------------------------------------------------------------------
-- Tipos e formato dos dados
--------------------------------------------------------------------------------

export type PlayerData = {
	version: number,
	xp: number,
	cosmetics: { [string]: boolean }, -- set: id -> true (dedupe e busca O(1))
}

type Profile = {
	data: PlayerData,
	loaded: boolean, -- o DataStore já respondeu?
	canSave: boolean, -- false = carregamento falhou, não sobrescrever
	dirty: boolean, -- mudou algo desde o último save?
	pendingXP: number, -- ganho antes do load terminar
	pendingCosmetics: { string },
}

local function makeDefaultData(): PlayerData
	return {
		version = DATA_VERSION,
		xp = 0,
		cosmetics = {},
	}
end

-- MIGRATIONS[n] recebe dados na versão n e devolve na versão n + 1.
-- Ainda vazio porque só existe a versão 1; a máquina está pronta pro dia
-- em que o formato mudar.
local MIGRATIONS: { [number]: (any) -> any } = {}

local function migrateData(raw: any): PlayerData?
	if typeof(raw) ~= "table" then
		return nil
	end

	local data = raw
	local version = tonumber(data.version) or 0

	while version < DATA_VERSION do
		local migration = MIGRATIONS[version]
		if not migration then
			-- Sem caminho de migração: melhor recusar do que carregar
			-- dados num formato que o código atual não entende.
			warn(string.format("[DataStoreManager] Sem migração da versão %d para %d.", version, version + 1))
			return nil
		end

		data = migration(data)
		version += 1
		data.version = version
	end

	-- Saneamento: um save corrompido/editado não pode derrubar o servidor.
	return {
		version = DATA_VERSION,
		xp = tonumber(data.xp) or 0,
		cosmetics = (typeof(data.cosmetics) == "table") and data.cosmetics or {},
	}
end

--------------------------------------------------------------------------------
-- Estado em memória
--------------------------------------------------------------------------------

local profiles: { [Player]: Profile } = {}

local function getKey(player: Player): string
	return KEY_PREFIX .. tostring(player.UserId)
end

--------------------------------------------------------------------------------
-- pcall + backoff exponencial
--------------------------------------------------------------------------------

local function retryAsync(label: string, operation: () -> any): (boolean, any)
	local waitTime = RETRY_INITIAL_DELAY

	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end

		warn(string.format("[DataStoreManager] %s falhou (tentativa %d/%d): %s", label, attempt, MAX_ATTEMPTS, tostring(result)))

		if attempt < MAX_ATTEMPTS then
			task.wait(waitTime)
			waitTime *= 2
		end
	end

	return false, nil
end

--------------------------------------------------------------------------------
-- Load
--------------------------------------------------------------------------------

local function loadProfileAsync(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	local ok, raw = retryAsync(string.format("Load de %s", player.Name), function()
		return playerStore:GetAsync(getKey(player))
	end)

	-- O jogador pode ter saído enquanto o DataStore respondia.
	profile = profiles[player]
	if not profile then
		return
	end

	if not ok then
		profile.loaded = true
		profile.canSave = false
		warn(string.format("[DataStoreManager] %s vai jogar com dados padrão e NÃO terá o progresso salvo (load falhou).", player.Name))
		return
	end

	if raw == nil then
		-- Jogador novo: nada salvo ainda, os padrões valem e podem ser salvos.
		profile.canSave = true
	else
		local migrated = migrateData(raw)
		if migrated then
			-- Preserva o que foi ganho enquanto o load estava em voo.
			migrated.xp += profile.pendingXP
			for _, cosmeticId in profile.pendingCosmetics do
				migrated.cosmetics[cosmeticId] = true
			end

			profile.data = migrated
			profile.canSave = true
		else
			profile.canSave = false
			warn(string.format("[DataStoreManager] Save de %s ilegível/incompatível -- sessão não será salva.", player.Name))
		end
	end

	profile.loaded = true
	profile.pendingXP = 0
	table.clear(profile.pendingCosmetics)
end

local function onPlayerAdded(player: Player)
	profiles[player] = {
		data = makeDefaultData(),
		loaded = false,
		canSave = false, -- só libera depois de saber o que já existia
		dirty = false,
		pendingXP = 0,
		pendingCosmetics = {},
	}

	task.spawn(loadProfileAsync, player)
end

--------------------------------------------------------------------------------
-- Save
--------------------------------------------------------------------------------

local function saveProfile(player: Player, reason: string): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end

	if not profile.canSave then
		return false -- load falhou: nunca sobrescrever
	end

	if not profile.dirty then
		return true -- nada mudou, não gasta requisição
	end

	local data = profile.data

	-- UpdateAsync em vez de SetAsync: respeita melhor escrita concorrente e
	-- é o caminho recomendado pela Roblox pra dados de jogador.
	local ok = retryAsync(string.format("Save de %s (%s)", player.Name, reason), function()
		return playerStore:UpdateAsync(getKey(player), function()
			return data
		end)
	end)

	if ok then
		profile.dirty = false
		print(string.format("[DataStoreManager] Save de %s ok (%s).", player.Name, reason))
	else
		warn(string.format("[DataStoreManager] Save de %s FALHOU (%s).", player.Name, reason))
	end

	return ok
end

local function onPlayerRemoving(player: Player)
	saveProfile(player, "saída")
	profiles[player] = nil
end

local function startAutosaveLoop()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)

			for player in profiles do
				task.spawn(saveProfile, player, "autosave")
			end
		end
	end)
end

local function saveEveryoneOnClose()
	local pending = 0

	for player in profiles do
		pending += 1
		task.spawn(function()
			saveProfile(player, "shutdown")
			pending -= 1
		end)
	end

	-- BindToClose segura o desligamento enquanto isto não retornar.
	while pending > 0 do
		task.wait()
	end
end

--------------------------------------------------------------------------------
-- API pública
--------------------------------------------------------------------------------

--[[
	AddXP(player, amount)
	Soma XP ao total do jogador. Funciona mesmo antes do load terminar (o
	valor fica pendente e é reaplicado quando os dados salvos chegam).
]]
function DataStoreManager.AddXP(player: Player, amount: number)
	local profile = profiles[player]
	if not profile or amount == 0 then
		return
	end

	if profile.loaded then
		profile.data.xp += amount
	else
		profile.pendingXP += amount
	end

	profile.dirty = true
end

--[[
	UnlockCosmetic(player, cosmeticId)
	Marca um cosmético como desbloqueado. Repetir o mesmo id é inofensivo.
]]
function DataStoreManager.UnlockCosmetic(player: Player, cosmeticId: string)
	local profile = profiles[player]
	if not profile then
		return
	end

	if profile.loaded then
		profile.data.cosmetics[cosmeticId] = true
	else
		table.insert(profile.pendingCosmetics, cosmeticId)
	end

	profile.dirty = true
end

--[[
	GetXP(player)
	XP total, incluindo o que ainda está pendente de merge com o save.
]]
function DataStoreManager.GetXP(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 0
	end

	return profile.data.xp + profile.pendingXP
end

--[[
	HasCosmetic(player, cosmeticId)
]]
function DataStoreManager.HasCosmetic(player: Player, cosmeticId: string): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end

	if profile.data.cosmetics[cosmeticId] then
		return true
	end

	return table.find(profile.pendingCosmetics, cosmeticId) ~= nil
end

--[[
	GetCosmetics(player)
	Lista (array) dos cosméticos desbloqueados.
]]
function DataStoreManager.GetCosmetics(player: Player): { string }
	local profile = profiles[player]
	if not profile then
		return {}
	end

	local result = {}
	for cosmeticId in profile.data.cosmetics do
		table.insert(result, cosmeticId)
	end
	for _, cosmeticId in profile.pendingCosmetics do
		if not table.find(result, cosmeticId) then
			table.insert(result, cosmeticId)
		end
	end

	table.sort(result)
	return result
end

--[[
	IsLoaded(player)
	Se o DataStore já respondeu para este jogador. Útil pra UI que não deve
	mostrar "0 XP" antes da hora.
]]
function DataStoreManager.IsLoaded(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.loaded
end

--[[
	Init()
	Assina entrada/saída de jogadores, autosave e shutdown.
	Chame uma vez no boot do servidor.
]]
function DataStoreManager.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Jogadores que entraram antes deste Init rodar.
	for _, player in Players:GetPlayers() do
		if not profiles[player] then
			onPlayerAdded(player)
		end
	end

	startAutosaveLoop()
	game:BindToClose(saveEveryoneOnClose)
end

return DataStoreManager
