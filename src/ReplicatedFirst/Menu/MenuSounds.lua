--!strict
--[[
	MenuSounds
	Áudio do menu -- 2D, local, criado uma vez e reutilizado.

	NÃO mexe no SoundManager do servidor (que cuida de som 3D de gameplay) nem
	no SoundService.Main do pacote de movimento. Tudo o que este módulo cria
	fica dentro de UMA pasta própria e é destruído junto com o menu.

	Todo ID vem do MenuConfig. ID vazio ou inválido = silêncio, sem erro e sem
	Sound órfão tocando nada.
]]

local SoundService = game:GetService("SoundService")

local Config = require(script.Parent.MenuConfig)
local Theme = require(script.Parent.MenuTheme)

local Sounds = {}
Sounds.__index = Sounds

export type Controller = typeof(setmetatable({} :: {
	folder: Folder,
	effects: { [string]: Sound },
	music: Sound?,
}, Sounds))

local function makeSound(parent: Instance, name: string, id: string, volume: number,
	looped: boolean, playbackSpeed: number?): Sound?
	local asset = Config.AssetId(id)
	if not asset then return nil end -- ID vazio: nada é criado
	local sound = Instance.new("Sound")
	sound.Name, sound.SoundId = name, asset
	sound.Volume, sound.Looped = volume, looped
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.Parent = parent
	return sound
end

function Sounds.new(): Controller
	local folder = Instance.new("Folder")
	folder.Name = "MenuAudio"
	folder.Parent = SoundService

	local cfg = Config.Sounds
	local effects: { [string]: Sound } = {}
	for name, data in {
		Hover = { cfg.Hover, cfg.HoverVolume },
		Click = { cfg.Click, cfg.ClickVolume },
		Back = { cfg.Back, cfg.BackVolume },
		Start = { cfg.Start, cfg.StartVolume, cfg.StartPlaybackSpeed },
	} do
		local sound = makeSound(folder, name, data[1] :: string, data[2] :: number, false, data[3] :: number?)
		if sound then effects[name] = sound end
	end

	-- TROQUE A MÚSICA em MenuConfig.Sounds.Music. Vazia = menu em silêncio.
	local music = makeSound(folder, "Music", cfg.Music, 0, true)

	local self = setmetatable({ folder = folder, effects = effects, music = music }, Sounds)
	return self
end

function Sounds.Play(self: Controller, name: string)
	local sound = self.effects[name]
	if not sound then return end
	-- TimePosition zerado: dois hovers seguidos reiniciam em vez de ignorar.
	sound.TimePosition = 0
	sound:Play()
end

-- Hover em celular seria um tapa a cada toque: só toca onde existe ponteiro.
function Sounds.Hover(self: Controller)
	if Theme.IsTouch() then return end
	Sounds.Play(self, "Hover")
end

function Sounds.StartMusic(self: Controller)
	local music = self.music
	if not music or music.IsPlaying then return end
	music.Volume = 0
	music:Play()
	Theme.Tween(music, Theme.Info(Config.Sounds.MusicFade, Enum.EasingStyle.Linear),
		{ Volume = Config.Sounds.MusicVolume })
end

function Sounds.FadeMusic(self: Controller, seconds: number?)
	local music = self.music
	if not music or not music.IsPlaying then return end
	Theme.Tween(music, Theme.Info(seconds or Config.Sounds.MusicFade, Enum.EasingStyle.Linear),
		{ Volume = 0 }, function()
			if music.Parent then music:Stop() end
		end)
end

function Sounds.Destroy(self: Controller)
	self.folder:Destroy()
	table.clear(self.effects)
	self.music = nil
end

return Sounds
