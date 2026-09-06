--!strict
--[[
	SoundManager
	Áudio do lado do servidor: música/ambiente por fase, e efeitos curtos
	posicionais de morte/amarração.

	MÚSICA POR FASE
	  RoundStateChanged é FireAllClients -- o servidor nunca recebe seu
	  próprio disparo, então escuto RoundManager.PhaseChanged (BindableEvent)
	  em vez do remote. Um único Sound "PhaseMusic", parentado direto em
	  SoundService (não numa BasePart), toca globalmente pra todo mundo sem
	  precisar de nenhum script no cliente: trocar o SoundId e dar Play já
	  replica sozinho.

	EFEITOS DE MORTE/AMARRAÇÃO
	  PlayerKilled e PlayerRestrained também são FireAllClients, então pela
	  mesma razão não dá pra "escutá-los" no servidor. Em vez de inventar
	  mais BindableEvents, os módulos que já disparam esses remotes
	  (LethalAbility.lua, ConfrontSystem.lua) chamam PlayDeathSound/
	  PlayRestrainSound diretamente, no mesmo lugar onde disparam o remote.
	  "Escutar o evento" e "reagir no exato momento em que ele acontece" dão
	  no mesmo resultado aqui, sem duplicar lógica de detecção de morte.

	  Cada efeito cria uma Part invisível ancorada na posição do evento com
	  um Sound posicional (RollOff), toca e se autodestrói -- só quem está
	  perto ouve, e nada fica sobrando no Workspace depois.

	IDs DE SOM: todos placeholder ("rbxassetid://0") em
	AssetRegistry.Sounds. Troque lá quando tiver os sons de verdade --
	nada neste arquivo precisa mudar.

	Uso (chamar uma vez no boot do servidor, DEPOIS de RoundManager.Init(),
	já que assina RoundManager.PhaseChanged):
		local SoundManager = require(script.SoundManager)
		SoundManager.Init()
]]

local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)

local SoundManager = {}

-- Tempo máximo que uma Part de efeito posicional pode viver, caso o
-- Sound.Ended nunca dispare (ex: SoundId placeholder/inválido).
local EFFECT_SAFETY_LIFETIME = 10

local EFFECT_MAX_DISTANCE = 60
local EFFECT_VOLUME = 1

local phaseMusic: Sound? = nil

--------------------------------------------------------------------------------
-- Música por fase
--------------------------------------------------------------------------------

local function getOrCreatePhaseMusic(): Sound
	if phaseMusic and phaseMusic.Parent then
		return phaseMusic
	end

	local sound = Instance.new("Sound")
	sound.Name = "PhaseMusic"
	sound.Looped = true
	sound.Volume = 0.5
	sound.Parent = SoundService

	phaseMusic = sound
	return sound
end

local function onPhaseChanged(phaseName: string)
	local soundId = AssetRegistry.Sounds.PhaseMusic[phaseName]
	local music = getOrCreatePhaseMusic()

	if not soundId or soundId == "" then
		music:Stop()
		return
	end

	if music.SoundId ~= soundId then
		music.SoundId = soundId
	end

	if not music.IsPlaying then
		music:Play()
	end
end

--------------------------------------------------------------------------------
-- Efeitos curtos posicionais
--------------------------------------------------------------------------------

local function playPositionalSound(position: Vector3, soundId: string)
	if soundId == "" then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "PositionalSoundEffect"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = EFFECT_VOLUME
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = EFFECT_MAX_DISTANCE
	sound.Parent = anchor

	local destroyed = false
	local function cleanup()
		if destroyed then
			return
		end
		destroyed = true
		anchor:Destroy()
	end

	sound.Ended:Connect(cleanup)
	task.delay(EFFECT_SAFETY_LIFETIME, cleanup)

	sound:Play()
end

--[[
	PlayDeathSound(position)
	Chamado por quem elimina um jogador (LethalAbility, ConfrontSystem),
	logo após disparar PlayerKilled.
]]
function SoundManager.PlayDeathSound(position: Vector3)
	playPositionalSound(position, AssetRegistry.Sounds.PlayerKilled)
end

--[[
	PlayRestrainSound(position)
	Chamado por ConfrontSystem ao amarrar alguém, logo após disparar
	PlayerRestrained(isRestrained = true). Não toca de novo ao soltar.
]]
function SoundManager.PlayRestrainSound(position: Vector3)
	playPositionalSound(position, AssetRegistry.Sounds.PlayerRestrained)
end

--[[
	PlayThrowSound(position)
	Chamado por WeaponSystem.lua no ponto de impacto da Pedra Afiada.
]]
function SoundManager.PlayThrowSound(position: Vector3)
	playPositionalSound(position, AssetRegistry.Sounds.ItemThrow)
end

--[[
	Init()
	Assina a troca de fase. Chame uma vez no boot do servidor, depois de
	RoundManager.Init() (precisa que RoundManager.PhaseChanged já exista).
]]
function SoundManager.Init()
	local RoundManager = require(script.Parent.RoundManager)
	RoundManager.PhaseChanged.Event:Connect(onPhaseChanged)
end

return SoundManager
