--!strict
-- Invisible original rig, no replacement meshes, particles or animation tracks.
-- Each observer owns a reversible presentation handle for streamed characters.
local Workspace = game:GetService("Workspace")
local Config = require(script.Parent.GameConfig)
local Rules = require(script.Parent.ShadowRushRules)
local AssetRules = require(script.Parent.FearPresentationRules)
local CFG = Config.Monster.ShadowRush
local VFX = {}

function VFX.new(character: Model, root: BasePart)
	local transparency: { [Instance]: number } = {}
	local shadows: { [BasePart]: boolean } = {}
	local enabled: { [Instance]: boolean } = {}
	local volumes: { [Sound]: number } = {}
	local sounds: { Sound } = {}
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local display = if humanoid then humanoid.DisplayDistanceType else nil
	local destroyed, currentPhase, hidden = false, "", 0
	local loop: Sound? = nil

	local function capture(d: Instance)
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			if transparency[d] == nil then transparency[d] = d.Transparency end
			d.Transparency = transparency[d] + (1 - transparency[d]) * hidden
			if d:IsA("BasePart") then
				if shadows[d] == nil then shadows[d] = d.CastShadow end
			end
		elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam")
			or d:IsA("Light") or d:IsA("Highlight") or d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			if enabled[d] == nil then enabled[d] = (d :: any).Enabled end
			(d :: any).Enabled = false
			if d:IsA("ParticleEmitter") or d:IsA("Trail") then d:Clear() end
		elseif d:IsA("Sound") and d:GetAttribute("ShadowRushAudio") ~= true then
			if volumes[d] == nil then volumes[d] = d.Volume end
		end
	end
	for _, d in character:GetDescendants() do capture(d) end
	local connection = character.DescendantAdded:Connect(capture)

	local function playSound(value: string, looped: boolean): Sound?
		local id = AssetRules.AssetId(value)
		if not id then return nil end
		local sound = Instance.new("Sound")
		sound.Name, sound.SoundId, sound.Volume = "ShadowRushAudio", id, CFG.SoundVolume
		sound.Looped, sound.RollOffMaxDistance = looped, CFG.SoundMaxDistance
		sound:SetAttribute("ShadowRushAudio", true)
		sound.Parent = root
		table.insert(sounds, sound)
		sound:Play()
		return sound
	end

	local handle = {}
	function handle.Update(_dt: number)
		if destroyed then return end
		local state = character:GetAttribute("ShadowRushState") or "Idle"
		if state ~= currentPhase then
			currentPhase = state
			if state == "EnteringShadow" then
				playSound(CFG.ShadowRushEnterSoundId, false)
			elseif state == "ShadowRush" then
				loop = playSound(CFG.ShadowRushLoopSoundId, true)
			elseif state == "Materializing" then
				playSound(CFG.ShadowRushExitSoundId, false)
			end
		end
		local elapsed = math.max(0, Workspace:GetServerTimeNow() - (character:GetAttribute("ShadowRushPhaseAt") or Workspace:GetServerTimeNow()))
		hidden = Rules.Hidden(state, elapsed, character:GetAttribute("ShadowRushExitHidden") or hidden, CFG)
		for d, original in transparency do
			if d.Parent then (d :: any).Transparency = original + (1 - original) * hidden end
		end
		for d, original in shadows do if d.Parent then d.CastShadow = original and hidden < 0.5 end end
		for d, original in enabled do
			if d.Parent then (d :: any).Enabled = original and state == "Recovery" end
		end
		for sound, original in volumes do if sound.Parent then sound.Volume = original * (1 - hidden) end end
		if humanoid then
			humanoid.DisplayDistanceType = if hidden > 0 then Enum.HumanoidDisplayDistanceType.None else display
		end
		if loop then loop.Volume = CFG.SoundVolume * hidden end
	end
	function handle.Destroy()
		if destroyed then return end
		destroyed = true
		connection:Disconnect()
		for _, sound in sounds do sound:Destroy() end
		for d, original in transparency do if d.Parent then (d :: any).Transparency = original end end
		for d, original in shadows do if d.Parent then d.CastShadow = original end end
		for d, original in enabled do if d.Parent then (d :: any).Enabled = original end end
		for sound, original in volumes do if sound.Parent then sound.Volume = original end end
		if humanoid and humanoid.Parent and display then humanoid.DisplayDistanceType = display end
	end
	handle.Update(0)
	return handle
end

return VFX
