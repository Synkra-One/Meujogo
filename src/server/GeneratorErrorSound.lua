--!strict
--[[
	GeneratorErrorSound
	Decide QUEM ouve o choque do gerador e QUANDO. Quem toca são os clientes
	(client/GeneratorErrorSoundController.client.luau), que criam o Sound como
	filho da Part do gerador -- assim o áudio é 3D de verdade (direção e
	volume calculados pelo Roblox a partir da posição do gerador).

	QUEM OUVE: (1) o jogador que ERROU e (2) o(s) Monstro(s) ao alcance.
	Ninguém mais: os outros sobreviventes não recebem nada.

	POR QUE NÃO TOCAR AQUI NO SERVIDOR: um Sound criado/tocado no servidor
	dentro do Workspace replica pra TODOS os jogadores. Por isso o servidor só
	valida e avisa os destinatários; cada um cria o Sound só no próprio cliente.

	O QUE É EDITÁVEL (nada disto fica hardcoded aqui):
	  SoundId ............ AssetRegistry.Sounds.RadioSite.ErroGerador
	  Volume, distância máxima/mínima, EmitterSize e COOLDOWN:
	                       GameConfig.RadioSite.ErroGerador

	COOLDOWN: por gerador (não por jogador). Três jogadores errando juntos ou o
	mesmo jogador errando em sequência não empilham o som; dentro da janela só
	o primeiro toca.

	QUANDO TOCA: em QUALQUER erro de minigame de reparo (nota vermelha ou teste
	ignorado) -- instalar peça, ligar gerador, painel, fio cortado --, sempre
	na posição do GERADOR. RepairMinigameSystem chama Play() a cada erro.
	Quem registra qual Part é o gerador é o RadioSiteSystem (SetGenerator).
	Uma tarefa pode ficar de fora com `GeneratorShock = false` em
	RepairMinigameConfig.Tasks.

	DIAGNÓSTICO: GameConfig.RadioSite.ErroGerador.Debug = true imprime no Output
	do servidor cada envio e cada motivo de o som NÃO ter tocado.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local GeneratorErrorSound = {}

-- A Part do gerador (atributo MotorGerador). Registrada por RadioSiteSystem.
local registered: BasePart? = nil

local function debugLog(message: string, ...: any)
	if GameConfig.RadioSite.ErroGerador.Debug then
		print("[GeneratorErrorSound] " .. string.format(message, ...))
	end
end

--[[
	SetGenerator(part)
	Diz onde fica o gerador. Sem isso, Play() não toca nada (mapa antigo sem
	estação de rádio).
]]
function GeneratorErrorSound.SetGenerator(part: BasePart?)
	registered = part
end

-- Última vez (os.clock) em que o choque tocou em cada gerador. Chave fraca: se
-- a Part sumir (mapa regerado) a entrada some junto.
local lastPlayed: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Monstro vivo, na partida e com corpo -- mesmo critério do NoiseService.
local function activeMonsterRoot(player: Player): BasePart?
	if player.Parent ~= Players or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Role") ~= GameConfig.Roles.Monster
		or player:GetAttribute("Eliminado") == true then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

--[[
	Play(generator?, source?)
	Toca o choque do gerador pra quem errou (`source`) e pro(s) Monstro(s) ao
	alcance. `generator` omitido = o gerador registrado com SetGenerator.
	Devolve true se tocou.
]]
function GeneratorErrorSound.Play(generator: BasePart?, source: Player?): boolean
	local cfg = GameConfig.RadioSite.ErroGerador
	if not cfg.Enabled then
		debugLog("desligado (GameConfig.RadioSite.ErroGerador.Enabled = false)")
		return false
	end
	local part = generator or registered
	if not part then
		debugLog("nenhum gerador registrado (RadioSiteSystem não achou a Part com MotorGerador)")
		return false
	end
	if not part:IsDescendantOf(Workspace) then
		debugLog("a Part do gerador não está mais no Workspace")
		return false
	end

	local now = os.clock()
	local since = now - (lastPlayed[part] or -math.huge)
	if since < cfg.Cooldown then
		debugLog("suprimido pelo cooldown (faltam %.1fs)", cfg.Cooldown - since)
		return false
	end

	local recipients: { Player } = {}

	-- Quem errou SEMPRE recebe o evento: o choque é o feedback do próprio erro.
	-- Se estiver longe do gerador (além de RollOffMaxDistance) o Roblox o deixa
	-- mudo pela distância -- o som vem do gerador, não de quem errou.
	if source and source.Parent == Players then
		table.insert(recipients, source)
	end

	-- Monstro(s): além de RollOffMaxDistance o Roblox já deixaria o som mudo;
	-- nem enviar poupa tráfego e evita criar Sound à toa no cliente.
	local reach = cfg.RollOffMaxDistance
	for _, player in Players:GetPlayers() do
		if player ~= source then
			local root = activeMonsterRoot(player)
			if root and (root.Position - part.Position).Magnitude <= reach then
				table.insert(recipients, player)
			end
		end
	end

	if #recipients == 0 then
		debugLog("ninguém pra ouvir (sem jogador que errou e sem Monstro no alcance)")
		return false
	end

	lastPlayed[part] = now
	for _, player in recipients do
		debugLog("enviado pra %s (gerador em %s)", player.Name, tostring(part.Position))
		Remotes.GeneratorErrorSound:FireClient(player, part)
	end
	return true
end

return GeneratorErrorSound
