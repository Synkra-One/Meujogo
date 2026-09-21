--!strict
--[[
	GeneratorErrorSoundController
	Toca o choque do gerador em 3D na posição física dele. O servidor
	(server/GeneratorErrorSound.lua) manda o evento SÓ pra quem errou e pro(s)
	Monstro(s) ao alcance; aqui o Sound nasce como FILHO DA PART DO GERADOR,
	localmente -- não em PlayerGui, SoundService nem na câmera.

	Por ser um Sound dentro de uma Part do Workspace, o Roblox faz o áudio
	espacial sozinho a partir da câmera de quem ouve (o "ouvido"):
	  - gerador atrás  -> o som vem de trás;
	  - à esquerda / direita -> vem daquele lado;
	  - volume cai com a distância (InverseTapered) até zero em
	    RollOffMaxDistance.
	Como o Sound é criado só nos clientes que receberam o evento, os outros
	sobreviventes não ouvem nada.

	ONDE EDITAR (nada disto fica hardcoded aqui):
	  SoundId ............ AssetRegistry.Sounds.RadioSite.ErroGerador
	  Volume, RollOffMaxDistance (distância máxima), RollOffMinDistance,
	  EmitterSize e Cooldown ... GameConfig.RadioSite.ErroGerador
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local SOUND_NAME = "ErroGeradorSom"

local function debugLog(message: string, ...: any)
	if GameConfig.RadioSite.ErroGerador.Debug then
		print("[GeneratorErrorSound] " .. string.format(message, ...))
	end
end

local player = Players.LocalPlayer
local lastPlayed: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any
-- Sons que este cliente criou (pra parar no fim da partida sem varrer o mapa).
local created: { [Sound]: true } = setmetatable({}, { __mode = "k" }) :: any

-- O servidor é quem escolhe os destinatários (quem errou + Monstro). Esta
-- checagem só impede um pacote fora de partida de tocar no lobby.
local function mayHear(): boolean
	return player:GetAttribute("InRound") == true
end

-- Um Sound por gerador, reaproveitado a cada erro. Aplica a config TODA vez:
-- editar o GameConfig em Studio (ou o servidor mudar) vale no próximo choque.
local function soundFor(generator: BasePart): Sound
	local existing = generator:FindFirstChild(SOUND_NAME)
	local sound = if existing and existing:IsA("Sound") then existing else Instance.new("Sound")
	local cfg = GameConfig.RadioSite.ErroGerador

	sound.Name = SOUND_NAME
	sound.SoundId = AssetRegistry.Sounds.RadioSite.ErroGerador -- <- troque o ID no AssetRegistry
	sound.Volume = cfg.Volume -- <- volume
	sound.Looped = false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = cfg.RollOffMinDistance -- <- volume máximo até aqui
	sound.RollOffMaxDistance = cfg.RollOffMaxDistance -- <- distância máxima (0 de volume)
	sound.EmitterSize = cfg.EmitterSize -- <- quão "espalhado" é o emissor
	sound.Parent = generator -- FILHO do gerador: é isso que o torna 3D

	if not created[sound] then
		created[sound] = true
		-- Pré-carrega e AVISA se o áudio não carregar. Áudio privado ou de outro
		-- dono falha em silêncio no jogo: sem isto "errei e não tocou" não tem
		-- pista nenhuma no Output.
		task.spawn(function()
			ContentProvider:PreloadAsync({ sound }, function(contentId: string, status: Enum.AssetFetchStatus)
				if status ~= Enum.AssetFetchStatus.Success then
					warn(string.format(
						"[GeneratorErrorSound] O áudio %s NÃO carregou (%s). Confira se o ID está certo e se o áudio é público ou do dono da experiência.",
						contentId,
						tostring(status)
					))
				else
					debugLog("áudio %s carregou.", contentId)
				end
			end)
		end)
	end
	return sound
end

Remotes.GeneratorErrorSound.OnClientEvent:Connect(function(generator: unknown)
	if typeof(generator) ~= "Instance" or not (generator :: Instance):IsA("BasePart") then
		return
	end
	local part = generator :: BasePart
	local cfg = GameConfig.RadioSite.ErroGerador
	if not cfg.Enabled or not mayHear() or not part:IsDescendantOf(Workspace) then
		debugLog("evento recebido mas ignorado (desligado, fora de partida ou gerador fora do Workspace)")
		return
	end

	-- Guarda local do cooldown (o servidor já garante o mesmo por gerador):
	-- mesmo com dois pacotes seguidos, o choque nunca toca por cima de si.
	local now = os.clock()
	if now - (lastPlayed[part] or -math.huge) < cfg.Cooldown then
		debugLog("ignorado pelo cooldown local")
		return
	end
	local sound = soundFor(part)
	if sound.IsPlaying then
		debugLog("ignorado: o choque anterior ainda está tocando")
		return
	end

	local camera = Workspace.CurrentCamera
	if camera then
		local distance = (camera.CFrame.Position - part.Position).Magnitude
		if distance > cfg.RollOffMaxDistance then
			debugLog("tocando, mas o gerador está a %.0f studs (máximo %d): você não vai ouvir.",
				distance, cfg.RollOffMaxDistance)
		else
			debugLog("tocando no gerador, a %.0f studs de você.", distance)
		end
	end

	lastPlayed[part] = now
	sound.TimePosition = 0
	sound:Play()
end)

-- Fim de partida: corta um choque que ainda esteja tocando.
Remotes.RoundEnded.OnClientEvent:Connect(function()
	for sound in created do
		sound:Stop()
	end
end)
