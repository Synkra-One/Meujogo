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
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local PresentationRules = require(ReplicatedStorage.Modules.FearPresentationRules)
local Players = game:GetService("Players")

local SoundManager = {}

-- Tempo máximo que uma Part de efeito posicional pode viver, caso o
-- Sound.Ended nunca dispare (ex: SoundId placeholder/inválido).
local EFFECT_SAFETY_LIFETIME = 10

local EFFECT_MAX_DISTANCE = 60
local EFFECT_VOLUME = 1

local phaseMusic: Sound? = nil
local initialized = false
local panicRng = Random.new()
type PanicVoice = { anchor: BasePart, sound: Sound, sequence: number }
local panicVoices: { [Player]: PanicVoice } = {}
local panicWatches: { [Player]: { RBXScriptConnection } } = {}

local function clearPanic(player: Player)
	local voice = panicVoices[player]
	if voice then voice.anchor:Destroy(); panicVoices[player] = nil end
end

local function stopAllPanic()
	for player in panicVoices do clearPanic(player) end
end

local function panicEligible(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return player.Parent == Players and player:GetAttribute("InRound") == true
		and player:GetAttribute("Role") == GameConfig.Roles.Survivor
		and player:GetAttribute("Eliminado") ~= true and character ~= nil
		and character:GetAttribute("Eliminado") ~= true and humanoid ~= nil and humanoid.Health > 0
end

-- Consumidor do hook da Parte 2: apenas seleção de asset e reprodução espacial.
local function playPanic(player: Player, position: Vector3, radius: number)
	if not panicEligible(player) then return end
	local ids: { string } = {}
	for _, value in GameConfig.Fear.PanicSounds do
		local id = PresentationRules.AssetId(value)
		if id then table.insert(ids, id) end
	end
	if #ids == 0 then return end
	local voice = panicVoices[player]
	if not voice then
		local anchor = Instance.new("Part")
		anchor.Name, anchor.Anchored, anchor.Transparency = "FearPanicOrigin", true, 1
		anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = false, false, false
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Parent = Workspace
		local sound = Instance.new("Sound")
		sound.Name, sound.RollOffMode = "FearPanic", Enum.RollOffMode.InverseTapered
		sound.Parent = anchor
		voice = { anchor = anchor, sound = sound, sequence = 0 }
		panicVoices[player] = voice
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local deathConnection = humanoid.Died:Connect(function() clearPanic(player) end)
			anchor.Destroying:Once(function() deathConnection:Disconnect() end)
		end
	end
	voice.sequence += 1
	local sequence, current = voice.sequence, voice
	voice.sound:Stop()
	voice.anchor.Position = position
	voice.sound.SoundId = ids[panicRng:NextInteger(1, #ids)]
	voice.sound.Volume = GameConfig.Fear.PanicSoundVolume
	voice.sound.RollOffMaxDistance = radius
	voice.sound:Play()
	task.delay(GameConfig.Fear.PanicSoundMaxDuration, function()
		if panicVoices[player] == current and current.sequence == sequence then current.sound:Stop() end
	end)
end

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
	if initialized then return end
	initialized = true
	local RoundManager = require(script.Parent.RoundManager)
	RoundManager.PhaseChanged.Event:Connect(onPhaseChanged)
	local Fear = require(script.Parent.FearSystem)
	local Remotes = require(ReplicatedStorage.Modules.Remotes)
	Fear.PanicSoundTriggered.Event:Connect(function(player, position, radius)
		if RoundManager.IsRoundActive() then playPanic(player, position, radius) end
	end)
	Fear.TripTriggered.Event:Connect(function(player, _position, duration)
		if RoundManager.IsRoundActive() and panicEligible(player) then
			Remotes.FearPresentation:FireClient(player, "Trip", player.Character, duration)
		end
	end)
	RoundManager.RoundEnded.Event:Connect(stopAllPanic)
	RoundManager.RoundPrepared.Event:Connect(stopAllPanic)
	local function watch(player: Player)
		if panicWatches[player] then return end
		local connections = { player.CharacterRemoving:Connect(function() clearPanic(player) end) }
		panicWatches[player] = connections
		for _, attribute in { "Role", "InRound", "Eliminado" } do
			table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(function()
				if not panicEligible(player) then clearPanic(player) end
			end))
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do watch(player) end
	Players.PlayerRemoving:Connect(function(player)
		clearPanic(player)
		for _, connection in panicWatches[player] or {} do connection:Disconnect() end
		panicWatches[player] = nil
	end)
end

return SoundManager
