--!strict
-- Feedback local para ProximityPrompt de pegar item/municao.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local PICK_ANIMATION_ID = "rbxassetid://136848191306492"
local PICK_SOUND_ID = "rbxassetid://619578856"
local COOLDOWN = 0.35
local PICK_ANIMATION_SPEED = 0.78

local animation = Instance.new("Animation")
animation.Name = "Pick"
animation.AnimationId = PICK_ANIMATION_ID

local lastPlayed = 0
local currentTrack: AnimationTrack? = nil

local function isPickupPrompt(prompt: ProximityPrompt): boolean
	local action = string.lower(prompt.ActionText or "")
	if action == "pegar" or string.find(action, "pegar", 1, true) ~= nil
		or string.find(action, "colet", 1, true) ~= nil then
		return true
	end
	return (prompt.KeyboardKeyCode == Enum.KeyCode.E or prompt.KeyboardKeyCode == Enum.KeyCode.F) and (
		prompt.Name == "PegarPrompt" or prompt.Name == "MunicaoPrompt"
	)
end

local function animator(): Animator?
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil end
	local found = humanoid:FindFirstChildOfClass("Animator")
	if found then return found end
	return Instance.new("Animator", humanoid)
end

local function playPickAnimation()
	local now = os.clock()
	if now - lastPlayed < COOLDOWN then return end
	lastPlayed = now
	local animator = animator()
	if not animator then return end
	if currentTrack then currentTrack:Stop(0.05); currentTrack:Destroy() end
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	if not ok or not track then return end
	currentTrack = track
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	track:Play(0.04, 1, PICK_ANIMATION_SPEED)
	track.Stopped:Once(function()
		if currentTrack == track then currentTrack = nil end
		track:Destroy()
	end)
	task.delay(2.5, function()
		if currentTrack == track then
			currentTrack = nil
			track:Stop(0.05)
			track:Destroy()
		end
	end)
end

local function playPickSound()
	local sound = Instance.new("Sound")
	sound.Name = "PickInteractionSound"
	sound.SoundId = PICK_SOUND_ID
	sound.Volume = 0.28
	sound.RollOffMode = Enum.RollOffMode.Inverse
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 2)
end

-- No cliente, PromptTriggered recebe (prompt, inputType). O segundo
-- argumento NÃO é um Player (esse formato só existe em Prompt.Triggered no
-- servidor); comparar com LocalPlayer fazia a animação ser descartada sempre.
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, _inputType: Enum.ProximityPromptInputType)
	if not isPickupPrompt(prompt) then return end
	playPickAnimation()
	playPickSound()
end)
