--!strict
-- A apresentação visual nasce somente no cliente do monstro. O sobrevivente
-- recebe apenas um Sound local para ouvir o próprio batimento.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CFG = require(ReplicatedStorage.Modules.HeartbeatConfig)
local Rules = require(ReplicatedStorage.Modules.HeartbeatRules)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local player = Players.LocalPlayer
type Effect = {
	player: Player, character: Model, emitter: Part, sound: Sound, equalizer: EqualizerSoundEffect,
	heart: Model, heartHighlight: Highlight, heartBaseSize: number, aura: Highlight,
	strength: number, target: number, bpm: number, targetBPM: number,
	tension: number, targetTension: number, phase: number, auraPhase: number, seenAt: number, fadingAt: number?,
}
type SelfAudio = {
	character: Model, emitter: Part, sound: Sound, equalizer: EqualizerSoundEffect,
	strength: number, target: number, bpm: number, targetBPM: number,
	tension: number, targetTension: number, phase: number, seenAt: number, fadingAt: number?,
}
local effects: { [Player]: Effect } = {}
local selfAudio: SelfAudio? = nil
local renderConnection: RBXScriptConnection? = nil

local function livingRoot(subject: Player, role: string): BasePart?
	if subject.Parent ~= Players or subject:GetAttribute("Role") ~= role
		or subject:GetAttribute("InRound") ~= true or subject:GetAttribute("Eliminado") == true
		or subject:GetAttribute("CharacterSelectOpen") == true then return nil end
	local character = subject.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not character.Parent or character:GetAttribute("Eliminado") == true
		or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil end
	return root
end

local function destroy(subject: Player)
	local effect = effects[subject]
	if not effect then return end
	effects[subject] = nil
	effect.sound:Stop()
	effect.emitter:Destroy()
	effect.heart:Destroy()
	effect.heartHighlight:Destroy()
	effect.aura:Destroy()
end

local function destroySelfAudio()
	local audio = selfAudio
	if not audio then return end
	selfAudio = nil
	audio.sound:Stop()
	audio.emitter:Destroy()
end

local function clear()
	for subject in effects do destroy(subject) end
	destroySelfAudio()
	if renderConnection then renderConnection:Disconnect(); renderConnection = nil end
end

local function clearMonsterEffects()
	for subject in effects do destroy(subject) end
end

local function heartModel(): Model
	local folder = ReplicatedStorage:FindFirstChild(CFG.AssetsFolder)
	local template = folder and folder:FindFirstChild(CFG.TemplateName)
	if template and template:IsA("Model") then return template:Clone() end
	-- Fallback 3D reconhecível: duas cúpulas e uma ponta. Sem asset remoto extra.
	local model = Instance.new("Model")
	model.Name = "ProceduralHeart"
	for _, x in { -0.32, 0.32 } do
		local lobe = Instance.new("Part")
		lobe.Shape = Enum.PartType.Ball
		lobe.Size = Vector3.new(0.9, 0.9, 0.5)
		lobe.Position = Vector3.new(x, 0.2, 0)
		lobe.Parent = model
	end
	local tip = Instance.new("Part")
	tip.Size = Vector3.new(0.85, 0.85, 0.45)
	tip.CFrame = CFrame.new(0, -0.2, 0) * CFrame.Angles(0, 0, math.pi / 4)
	tip.Parent = model
	for _, part in model:GetChildren() do
		local p = part :: BasePart
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
		p.Color = Color3.fromRGB(240, 32, 52)
	end
	return model
end

local function chestCFrame(character: Model, root: BasePart): CFrame
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local anchor = if torso and torso:IsA("BasePart") then torso else root
	return anchor.CFrame * CFrame.new(CFG.HeartChestOffset)
end

local function pulse(phase: number, duty: number): number
	if phase >= duty then return 0 end
	return math.sin(math.pi * phase / duty) ^ 2
end

local function create(subject: Player, character: Model): Effect
	local emitter = Instance.new("Part")
	emitter.Name = "LocalHeartbeatEmitter"
	emitter.Size = Vector3.new(0.1, 0.1, 0.1)
	emitter.Transparency = 1
	emitter.Anchored, emitter.CanCollide, emitter.CanTouch, emitter.CanQuery = true, false, false, false
	emitter.Parent = Workspace
	local attachment = Instance.new("Attachment")
	attachment.Parent = emitter
	local sound = Instance.new("Sound")
	sound.Name, sound.SoundId, sound.Volume = "Heartbeat", CFG.SoundId, 0
	sound.Looped = false
	-- A atenuação por distância já veio do servidor. Mantém espacialização 3D,
	-- sem duplicar o falloff nem mudar o listener global usado pelos outros sons.
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = CFG.MaxRange + 32
	sound.RollOffMaxDistance = CFG.MaxRange + 64
	sound.Parent = attachment
	local equalizer = Instance.new("EqualizerSoundEffect")
	equalizer.HighGain = -8
	equalizer.Parent = sound
	local heart = heartModel()
	heart.Name = "LocalHeartbeatHeart"
	for _, descendant in heart:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide, descendant.CanTouch, descendant.CanQuery = false, false, false
			descendant.Color = Color3.fromRGB(218, 38, 52)
			descendant.Material = Enum.Material.Neon
			descendant.Transparency = 1
		end
	end
	local _, bounds = heart:GetBoundingBox()
	local heartBaseSize = math.max(bounds.X, bounds.Y, bounds.Z, 0.01)
	heart.Parent = Workspace
	local heartHighlight = Instance.new("Highlight")
	heartHighlight.Name = "LocalHeartbeatHeartGlow"
	heartHighlight.Adornee = heart
	heartHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	heartHighlight.FillColor = Color3.fromRGB(225, 38, 52)
	heartHighlight.OutlineColor = Color3.fromRGB(255, 105, 112)
	heartHighlight.FillTransparency, heartHighlight.OutlineTransparency = 1, 1
	heartHighlight.Parent = emitter
	local aura = Instance.new("Highlight")
	aura.Name = "LocalHeartbeatAura"
	aura.Adornee = character
	aura.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	aura.FillColor = Color3.fromRGB(154, 35, 43)
	aura.OutlineColor = Color3.fromRGB(210, 74, 79)
	aura.FillTransparency, aura.OutlineTransparency = 1, 1
	aura.Parent = emitter
	local effect: Effect = { player = subject, character = character, emitter = emitter,
		sound = sound, equalizer = equalizer, heart = heart, heartHighlight = heartHighlight,
		heartBaseSize = heartBaseSize, aura = aura,
		strength = 0, target = 0, bpm = CFG.MinBPM, targetBPM = CFG.MinBPM,
		tension = 0, targetTension = 0, phase = 1, auraPhase = 1, seenAt = os.clock(), fadingAt = nil }
	effects[subject] = effect
	return effect
end

local function createSelfAudio(character: Model): SelfAudio
	local emitter = Instance.new("Part")
	emitter.Name = "LocalSelfHeartbeatEmitter"
	emitter.Size = Vector3.new(0.1, 0.1, 0.1)
	emitter.Transparency = 1
	emitter.Anchored, emitter.CanCollide, emitter.CanTouch, emitter.CanQuery = true, false, false, false
	emitter.Parent = Workspace
	local attachment = Instance.new("Attachment")
	attachment.Parent = emitter
	local sound = Instance.new("Sound")
	sound.Name, sound.SoundId, sound.Volume = "SelfHeartbeat", CFG.SoundId, 0
	sound.Looped = false
	-- Emit from the survivor's chest. This is local-only and has no visual
	-- heart/aura, so other survivors never see or hear this stream.
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 1
	sound.RollOffMaxDistance = CFG.MaxRange
	sound.Parent = attachment
	local equalizer = Instance.new("EqualizerSoundEffect")
	equalizer.HighGain = -8
	equalizer.Parent = sound
	local audio: SelfAudio = {
		character = character, emitter = emitter, sound = sound, equalizer = equalizer,
		strength = 0, target = 0, bpm = CFG.MinBPM, targetBPM = CFG.MinBPM,
		tension = 0, targetTension = 0, phase = 1, seenAt = os.clock(), fadingAt = nil,
	}
	selfAudio = audio
	return audio
end

local function fadeSelfAudio(now: number)
	local audio = selfAudio
	if audio and not audio.fadingAt then audio.target, audio.fadingAt = 0, now end
end

local function renderSelfAudio(dt: number, now: number)
	local audio = selfAudio
	if not audio then return end
	local root = livingRoot(player, GameConfig.Roles.Survivor)
	if not root or root.Parent ~= audio.character then destroySelfAudio(); return end
	if now - audio.seenAt > CFG.SnapshotTimeout then fadeSelfAudio(now) end
	if audio.fadingAt and now - audio.fadingAt >= CFG.FadeOut then destroySelfAudio(); return end
	if not audio.fadingAt then audio.emitter.CFrame = chestCFrame(audio.character, root) end
	audio.strength = Rules.Smooth(audio.strength, audio.target, dt, CFG)
	audio.bpm = Rules.Smooth(audio.bpm, audio.targetBPM, dt, CFG)
	audio.tension = Rules.Smooth(audio.tension, audio.targetTension, dt, CFG)
	audio.phase += dt * audio.bpm / 60
	local playbackSpeed = audio.bpm / CFG.AudioReferenceBPM
	local audibility = math.clamp(math.sqrt(audio.strength / CFG.AudibleStrength), 0, 1)
	audio.sound.Volume = CFG.MaxVolume * audio.strength + CFG.MinVolume * audibility
	audio.sound.PlaybackSpeed = playbackSpeed
	if audio.phase >= 1 then
		audio.phase %= 1
		if audio.strength > 0.001 then
			audio.sound:Stop()
			audio.sound.TimePosition = CFG.AudioStartTime
			audio.sound:Play()
		end
	end
	if audio.sound.TimePosition >= CFG.AudioStartTime + CFG.AudioCycleDuration then audio.sound:Stop() end
end

local function fade(effect: Effect, now: number)
	if effect.fadingAt then return end
	effect.target = 0
	effect.fadingAt = now
end

local function render(dt: number)
	if not CFG.Enabled then clear(); return end
	local now = os.clock()
	renderSelfAudio(dt, now)
	local monsterRoot = livingRoot(player, GameConfig.Roles.Monster)
	if not monsterRoot then
		clearMonsterEffects()
		if not selfAudio and renderConnection then renderConnection:Disconnect(); renderConnection = nil end
		return
	end
	for subject, effect in effects do
		local root = livingRoot(subject, GameConfig.Roles.Survivor)
		if subject.Character ~= effect.character or not root
			or effect.character:GetAttribute("PowerFearHidden") == true then destroy(subject); continue end
		if now - effect.seenAt > CFG.SnapshotTimeout
			or (root.Position - monsterRoot.Position).Magnitude >= CFG.MaxRange then fade(effect, now) end
		if effect.fadingAt and now - effect.fadingAt >= CFG.FadeOut then destroy(subject); continue end
		-- Congela a última posição autorizada ao perder o contato.
		if not effect.fadingAt then effect.emitter.CFrame = chestCFrame(effect.character, root) end
		effect.strength = Rules.Smooth(effect.strength, effect.target, dt, CFG)
		effect.bpm = Rules.Smooth(effect.bpm, effect.targetBPM, dt, CFG)
		effect.tension = Rules.Smooth(effect.tension, effect.targetTension, dt, CFG)
		effect.phase += dt * effect.bpm / 60
		effect.auraPhase += dt * effect.bpm / 60 * CFG.AuraPulseRateMultiplier
		local playbackSpeed = effect.bpm / CFG.AudioReferenceBPM
		local audibility = math.clamp(math.sqrt(effect.strength / CFG.AudibleStrength), 0, 1)
		effect.sound.Volume = CFG.MaxVolume * effect.strength + CFG.MinVolume * audibility
		effect.sound.PlaybackSpeed = playbackSpeed
		if effect.phase >= 1 then
			effect.phase %= 1 -- no máximo um ciclo por frame, inclusive em mobile lento
			if effect.strength > 0.001 then
				effect.sound:Stop()
				effect.sound.TimePosition = CFG.AudioStartTime
				effect.sound:Play()
			end
		end
		-- Um único ciclo do asset por batida; não sobrepõe gravações longas.
		if effect.sound.TimePosition >= CFG.AudioStartTime + CFG.AudioCycleDuration then effect.sound:Stop() end
		local heartPulse = Rules.Pulse(effect.phase, effect.tension, CFG)
		local heartOpacity = math.clamp(effect.strength * heartPulse, 0, 1)
		local heartSize = CFG.HeartMinSize + (CFG.HeartMaxSize - CFG.HeartMinSize) * heartPulse
		effect.heart:ScaleTo(heartSize / effect.heartBaseSize)
		effect.heart:PivotTo(effect.emitter.CFrame)
		for _, descendant in effect.heart:GetDescendants() do
			if descendant:IsA("BasePart") then descendant.Transparency = 1 - heartOpacity end
		end
		effect.heartHighlight.FillTransparency = 1 - heartOpacity * 0.72
		effect.heartHighlight.OutlineTransparency = 1 - heartOpacity
		effect.heartHighlight.Enabled = heartOpacity > 0.001
		effect.auraPhase %= 1
		local auraDuty = CFG.AuraMinPulseDuty + (CFG.AuraMaxPulseDuty - CFG.AuraMinPulseDuty) * effect.tension
		local auraOpacity = effect.strength * pulse(effect.auraPhase, auraDuty)
		effect.aura.FillTransparency = 1 - auraOpacity * CFG.AuraFillIntensity
		effect.aura.OutlineTransparency = 1 - auraOpacity * CFG.AuraOutlineIntensity
		effect.aura.Enabled = auraOpacity > 0.001
	end
	if next(effects) == nil and not selfAudio then clear() end
end

Remotes.HeartbeatDetected.OnClientEvent:Connect(function(monsterCharacter: Model, snapshot)
	if not CFG.Enabled or player.Character ~= monsterCharacter then
		clear(); return
	end
	if player:GetAttribute("Role") == GameConfig.Roles.Survivor then
		clearMonsterEffects()
		local now = os.clock()
		local entry = nil
		for _, candidate in snapshot do
			if candidate.player == player and candidate.character == player.Character then entry = candidate; break end
		end
		if not livingRoot(player, GameConfig.Roles.Survivor) or not entry then
			fadeSelfAudio(now)
		else
			local audio = selfAudio
			if audio and audio.character ~= entry.character then destroySelfAudio(); audio = nil end
			if not audio then audio = createSelfAudio(entry.character) end
			audio.target = math.clamp(entry.strength, 0, 1)
			audio.targetBPM = math.clamp(entry.bpm, CFG.MinBPM, CFG.MaxBPM)
			audio.targetTension = math.clamp(entry.tension, 0, 1)
			audio.seenAt, audio.fadingAt = now, nil
		end
		if selfAudio and not renderConnection then renderConnection = RunService.RenderStepped:Connect(render) end
		return
	end
	if not livingRoot(player, GameConfig.Roles.Monster) then clear(); return end
	local seen = {}
	local now = os.clock()
	for _, entry in snapshot do
		local subject = entry.player
		-- Instâncias ainda não recebidas pelo streaming são ignoradas até o próximo snapshot.
		if not subject or not entry.character or subject.Character ~= entry.character
			or not livingRoot(subject, GameConfig.Roles.Survivor) then continue end
		local effect = effects[subject]
		if effect and effect.character ~= entry.character then destroy(subject); effect = nil end
		if not effect then effect = create(subject, entry.character) end
		effect.target = math.clamp(entry.strength, 0, 1)
		effect.targetBPM = math.clamp(entry.bpm, CFG.MinBPM, CFG.MaxBPM)
		effect.targetTension = math.clamp(entry.tension, 0, 1)
		effect.seenAt, effect.fadingAt = now, nil
		seen[subject] = true
	end
	for subject, effect in effects do if not seen[subject] then fade(effect, now) end end
	if next(effects) and not renderConnection then renderConnection = RunService.RenderStepped:Connect(render) end
end)

for _, name in { "Role", "InRound", "Eliminado", "CharacterSelectOpen" } do
	player:GetAttributeChangedSignal(name):Connect(function()
		if not livingRoot(player, GameConfig.Roles.Monster) then clear() end
	end)
end
player.CharacterRemoving:Connect(clear)
Players.PlayerRemoving:Connect(destroy)
Remotes.RoundEnded.OnClientEvent:Connect(clear)
script.Destroying:Connect(clear)
