--!strict
--[[
	DataStoreManager
	Persistência de progressão do jogador (XP total e cosméticos
	desbloqueados), com cache em memória durante a sessão.

	COMO FUNCIONA
	  - Ao entrar, o jogador JÁ recebe um perfil em memória com valores
	    padrão e pode jogar na hora. O carregamento do DataStore acontece em
	    paralelo; quando termina, o XP/cosméticos confirmados substituem os
	    padrões SEM apagar nada ganho nesse meio tempo -- ver "GRAVAÇÃO POR
	    DELTA" abaixo. Ninguém fica travado esperando.

	  - Se o carregamento falhar em TODAS as tentativas, o perfil fica com
	    canSave = false pelo resto da sessão. Isso é de propósito: gravar
	    por cima de um save que existe mas não conseguimos ler poderia
	    apagar progresso real. Melhor perder a sessão do que o histórico.

	  - Salva automaticamente a cada AUTOSAVE_INTERVAL, ao sair, e no
	    BindToClose (shutdown do servidor). Perfis sem alteração desde a
	    última gravação confirmada são pulados, pra não queimar cota do
	    DataStore à toa.

	GRAVAÇÃO POR DELTA (o motivo do jogador nunca perder XP)
	  Cada gravação NÃO manda o perfil inteiro por cima do que está salvo.
	  Ela lê o valor atual do DataStore (via UpdateAsync) e SOMA só o que
	  foi ganho NESTA sessão desde a última gravação confirmada -- cosmético
	  usa união de conjuntos (idempotente: marcar o mesmo duas vezes não
	  perde nada). Isso resolve de propósito a limitação clássica de "dois
	  servidores com o mesmo jogador ao mesmo tempo, o último save vence":
	  aqui o último save só ADICIONA em cima do que o outro servidor já
	  tinha gravado, nunca apaga. Ainda não existe session locking (tipo
	  ProfileService) impedindo os DOIS servidores de deixar o jogador
	  jogar ao mesmo tempo -- só que agora, se isso acontecer, o XP dos
	  dois períodos soma em vez de um sobrescrever o outro.

	FORMATO VERSIONADO
	  Todo save carrega um campo `version`. Pra mudar o formato no futuro:
	    1) suba DATA_VERSION,
	    2) adicione uma função em MIGRATIONS[versaoAntiga] que recebe a
	       tabela antiga e devolve a nova.
	  migrateData() aplica as migrações em sequência, então um save v1 pula
	  pra v2, v3... sem quebrar. Note que o NOME do DataStore não é
	  versionado de propósito -- versionar o nome jogaria fora os saves
	  antigos, que é justamente o que a migração existe pra evitar.

	NÍVEL DA CONTA: este módulo só guarda e soma XP. Quem transforma XP em
	nível é Modules/LevelSystem (GetLevel/GetProgress) -- ver
	DataStoreManager.GetLevel/GetProgress abaixo, que são só um atalho.

	Uso (chamar uma vez no boot do servidor):
		local DataStoreManager = require(script.DataStoreManager)
		DataStoreManager.Init()

		DataStoreManager.AddXP(player, 50)
		DataStoreManager.UnlockCosmetic(player, "ChapeuPirata")
		local level = DataStoreManager.GetLevel(player)
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LevelSystem = require(ReplicatedStorage.Modules.LevelSystem)

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

-- Formato gravado no DataStore.
export type PlayerData = {
	version: number,
	xp: number,
	cosmetics: { [string]: boolean }, -- set: id -> true (dedupe e busca O(1))
}

-- Estado em memória de UM jogador durante a sessão.
type Profile = {
	loaded: boolean, -- o DataStore já respondeu?
	canSave: boolean, -- false = carregamento falhou, não sobrescrever

	baseXP: number, -- XP confirmado gravado no DataStore na última carga/gravação
	unsavedXP: number, -- ganho NESTA sessão, ainda não confirmado (nunca negativo)

	cosmetics: { [string]: boolean }, -- TODOS os conhecidos (confirmados + novos);
	-- a gravação sempre manda o conjunto inteiro porque união é idempotente e
	-- barata -- não precisa rastrear individualmente quais são "novos".

	-- Geração: incrementa a cada AddXP/UnlockCosmetic. Uma gravação bem
	-- sucedida marca savedGeneration = a geração que ela mandou. Enquanto
	-- dirtyGeneration ~= savedGeneration, tem algo não confirmado.
	dirtyGeneration: number,
	savedGeneration: number,
}

local function makeDefaultData(): PlayerData
	return {
		version = DATA_VERSION,
		xp = 0,
		cosmetics = {},
	}
end

local function makeDefaultProfile(): Profile
	return {
		loaded = false,
		canSave = false, -- só libera depois de saber o que já existia
		baseXP = 0,
		unsavedXP = 0,
		cosmetics = {},
		dirtyGeneration = 0,
		savedGeneration = 0,
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
			-- baseXP passa a refletir o que JÁ está gravado. unsavedXP não é
			-- tocado: preserva o que foi ganho enquanto o load estava em voo
			-- (GetXP já soma os dois, então o jogador nunca viu o número cair).
			profile.baseXP = migrated.xp
			for cosmeticId in migrated.cosmetics do
				profile.cosmetics[cosmeticId] = true
			end
			profile.canSave = true
		else
			profile.canSave = false
			warn(string.format("[DataStoreManager] Save de %s ilegível/incompatível -- sessão não será salva.", player.Name))
		end
	end

	profile.loaded = true
end

local function onPlayerAdded(player: Player)
	profiles[player] = makeDefaultProfile()
	task.spawn(loadProfileAsync, player)
end

--------------------------------------------------------------------------------
-- Save
--------------------------------------------------------------------------------

--[[
	saveProfile(player, reason)
	Grava por DELTA via UpdateAsync: lê o que já está no DataStore (`old`,
	possivelmente escrito por outro servidor) e só ADICIONA o que esta
	sessão ganhou desde a última gravação confirmada. Nunca sobrescreve o
	documento inteiro com o snapshot local -- é isso que impede um segundo
	servidor de apagar o progresso que o primeiro já tinha salvo.
]]
local function saveProfile(player: Player, reason: string): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end

	if not profile.canSave then
		return false -- load falhou: nunca sobrescrever
	end

	if profile.dirtyGeneration == profile.savedGeneration then
		return true -- nada mudou desde a última gravação confirmada
	end

	-- Snapshot ANTES da chamada assíncrona: qualquer AddXP/UnlockCosmetic
	-- que aconteça enquanto isto está em voo entra na PRÓXIMA gravação, não
	-- se perde nem se mistura com esta.
	local generationBeingSaved = profile.dirtyGeneration
	local deltaXP = profile.unsavedXP
	local cosmeticsSnapshot = table.clone(profile.cosmetics)

	local ok = retryAsync(string.format("Save de %s (%s)", player.Name, reason), function()
		return playerStore:UpdateAsync(getKey(player), function(old)
			local data = migrateData(old) or makeDefaultData()
			data.xp += deltaXP
			for cosmeticId in cosmeticsSnapshot do
				data.cosmetics[cosmeticId] = true
			end
			return data
		end)
	end)

	if ok then
		profile.baseXP += deltaXP
		profile.unsavedXP -= deltaXP
		profile.savedGeneration = generationBeingSaved
		print(string.format("[DataStoreManager] Save de %s ok (%s).", player.Name, reason))
	else
		warn(string.format("[DataStoreManager] Save de %s FALHOU (%s) -- tentando de novo no próximo ciclo.", player.Name, reason))
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
	Soma XP ao total do jogador. Funciona a qualquer momento -- antes do
	load terminar, depois, não importa -- porque GetXP sempre soma
	baseXP + unsavedXP. amount pode ser negativo (não é usado hoje, mas a
	geração de "sujo" cobre o caso mesmo assim).
]]
function DataStoreManager.AddXP(player: Player, amount: number)
	local profile = profiles[player]
	if not profile or amount == 0 then
		return
	end

	profile.unsavedXP += amount
	profile.dirtyGeneration += 1
end

--[[
	UnlockCosmetic(player, cosmeticId)
	Marca um cosmético como desbloqueado. Repetir o mesmo id é inofensivo
	(idempotente) e não gera gravação nova desnecessária.
]]
function DataStoreManager.UnlockCosmetic(player: Player, cosmeticId: string)
	local profile = profiles[player]
	if not profile or profile.cosmetics[cosmeticId] then
		return
	end

	profile.cosmetics[cosmeticId] = true
	profile.dirtyGeneration += 1
end

--[[
	GetXP(player)
	XP total, incluindo o que ainda não foi confirmado no DataStore.
]]
function DataStoreManager.GetXP(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 0
	end

	return profile.baseXP + profile.unsavedXP
end

--[[
	GetLevel(player) / GetProgress(player)
	Atalhos pra Modules/LevelSystem já aplicado ao XP total deste jogador.
	Quem quiser a curva "crua" (pra UI de outro jogador, por exemplo) chama
	LevelSystem diretamente com o número de DataStoreManager.GetXP.
]]
function DataStoreManager.GetLevel(player: Player): number
	return LevelSystem.GetLevel(DataStoreManager.GetXP(player))
end

function DataStoreManager.GetProgress(player: Player): (number, number, number, boolean)
	return LevelSystem.GetProgress(DataStoreManager.GetXP(player))
end

--[[
	HasCosmetic(player, cosmeticId)
]]
function DataStoreManager.HasCosmetic(player: Player, cosmeticId: string): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.cosmetics[cosmeticId] == true
end

--[[
	GetCosmetics(player)
	Lista (array, ordenada) dos cosméticos desbloqueados.
]]
function DataStoreManager.GetCosmetics(player: Player): { string }
	local profile = profiles[player]
	if not profile then
		return {}
	end

	local result = {}
	for cosmeticId in profile.cosmetics do
		table.insert(result, cosmeticId)
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
