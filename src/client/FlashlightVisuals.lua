--!strict
local Config = require(game:GetService("ReplicatedStorage").Modules.FlashlightConfig)
local Visuals = {}
local entries: { [Tool]: any } = {}
local impacts: { [Model]: Highlight } = {}

function Visuals.Remove(tool: Tool)
	local entry = entries[tool]
	if not entry then return end
	if entry.light.Parent then entry.light.Enabled = false end
	if entry.spill and entry.spill.Parent then entry.spill.Enabled = false end
	if entry.fill and entry.fill.Parent then entry.fill.Enabled = false end
	if entry.beam.Parent then entry.beam.Enabled = false end
	if entry.sound then entry.sound:Destroy() end
	entries[tool] = nil
end

local function get(tool: Tool): any
	if entries[tool] then return entries[tool] end
	local handle = tool:FindFirstChild("Handle")
	local origin = handle and handle:FindFirstChild("FlashlightOrigin")
	local emitter = handle and handle:FindFirstChild("FlashlightEmitter")
	local endpoint = handle and handle:FindFirstChild("FlashlightEnd")
	local light = emitter and emitter:FindFirstChild("LanternaLuz")
	local spill = emitter and emitter:FindFirstChild("LanternaSpill")
	local fill = emitter and emitter:FindFirstChild("LanternaFill")
	local beam = emitter and emitter:FindFirstChild("FlashlightBeam")
	if not handle or not handle:IsA("BasePart") or not origin or not emitter or not endpoint or not light or not beam then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local entry = { handle = handle, origin = origin, emitter = emitter, endpoint = endpoint,
		light = light, spill = spill, fill = fill, beam = beam, rayAt = 0, distance = 0,
		clipped = false, source = nil, params = params,
		flickerSeed = (#tool.Name * 7 + math.floor(handle.Size.Magnitude * 10)) }
	local sound = Instance.new("Sound")
	sound.Name, sound.SoundId, sound.Volume = "FlashBurstDischarge", Config.FlashBurstSound, Config.FlashBurstSoundVolume
	sound.RollOffMinDistance, sound.RollOffMaxDistance, sound.Parent = 5, 65, handle
	entry.sound = sound
	entries[tool] = entry
	return entry
end

function Visuals.Update(tool: Tool, enabled: boolean)
	local elapsed = workspace:GetServerTimeNow() - (tool:GetAttribute("FlashBurstAt") or -math.huge)
	local burst = if elapsed >= 0 and elapsed < Config.FlashBurstVisualDuration
		then (1 - elapsed / Config.FlashBurstVisualDuration) ^ 2 else 0
	if not enabled and burst == 0 then Visuals.Remove(tool); return end
	local entry = get(tool)
	local character = tool.Parent
	if not entry or not character or not character:IsA("Model") then return end
	local camera = workspace.CurrentCamera
	if not camera or (entry.handle.Position - camera.CFrame.Position).Magnitude > Config.VisualDistance then
		Visuals.Remove(tool)
		return
	end
	local burstAt = tool:GetAttribute("FlashBurstAt")
	if burst > 0 and entry.burstAt ~= burstAt then
		entry.burstAt = burstAt
		entry.sound:Play()
	end
	-- The shoulder aims the physical flashlight. Both ends stay in Handle
	-- space, so camera motion cannot swing the cone away from the lens.
	local position = entry.origin.WorldPosition
	local aim = entry.origin.WorldCFrame.LookVector
	local now = os.clock()
	if now >= entry.rayAt or not entry.lastPosition
		or (position - entry.lastPosition).Magnitude > 0.05
		or aim:Dot(entry.lastAim) < 0.99995 then
		entry.rayAt = now + Config.VisualRayInterval
		entry.params.FilterDescendantsInstances = { character }
		local head = character:FindFirstChild("Head")
		local obstruction = if head and head:IsA("BasePart")
			then workspace:Raycast(head.Position, position - head.Position, entry.params) else nil
		-- Quando a mao atravessa uma parede, a lente fica dentro da geometria.
		-- Mover so a luz visual para o lado do jogador evita o blackout; o
		-- servidor continua validando a origem real para acertar o monstro.
		entry.clipped = obstruction ~= nil
		entry.source = if entry.clipped then head.Position else position
		entry.lastPosition, entry.lastAim = position, aim
		local result = workspace:Raycast(entry.source, aim * Config.LightRange, entry.params)
		entry.distance = if result then (result.Position - entry.source).Magnitude else Config.LightRange
	end
	entry.emitter.CFrame = if entry.clipped
		then entry.handle.CFrame:ToObjectSpace(CFrame.lookAt(entry.source, entry.source + aim))
		else entry.origin.CFrame
	entry.endpoint.CFrame = entry.emitter.CFrame * CFrame.new(0, 0, -entry.distance)
	entry.beam.Width1 = math.min(4.8, entry.distance * 0.18)
	local battery = tool:GetAttribute("Battery")
	local low = if type(battery) == "number"
		then 1 - math.clamp(battery / Config.LowBatteryThreshold, 0, 1) else 0
	local flicker = 1 - low * Config.LowBatteryFlicker
		* (0.5 + 0.5 * math.abs(math.sin(now * 31 + entry.flickerSeed)))
	local normal = if enabled then flicker else 0
	entry.light.Brightness = Config.Brightness * normal + Config.FlashBurstBrightness * burst
	if entry.spill then entry.spill.Brightness = Config.SpillBrightness * normal + 3 * burst end
	if entry.fill then entry.fill.Brightness = Config.FillBrightness * normal + 2 * burst end
	entry.light.Shadows = not entry.clipped
	entry.light.Enabled, entry.beam.Enabled = true, entry.distance > 0.2
	if entry.spill then entry.spill.Enabled = true end
	if entry.fill then entry.fill.Enabled = true end
end

function Visuals.UpdateImpacts(players: { Player })
	local seen: { [Model]: boolean } = {}
	local now, camera = workspace:GetServerTimeNow(), workspace.CurrentCamera
	for _, player in players do
		local character = player.Character
		local at = character and character:GetAttribute("FlashBurstAt")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and type(at) == "number" and now >= at and now - at < 0.6
			and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") and camera
			and (root.Position - camera.CFrame.Position).Magnitude < Config.VisualDistance then
			seen[character] = true
			local highlight = impacts[character]
			if not highlight then
				highlight = Instance.new("Highlight")
				highlight.Name, highlight.Adornee = "FlashBurstImpact", character
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.FillColor, highlight.OutlineColor = Color3.fromRGB(250, 255, 225), Color3.new(1, 1, 1)
				highlight.Parent = character
				impacts[character] = highlight
			end
			highlight.FillTransparency = 0.15 + 0.85 * math.clamp((now - at) / 0.6, 0, 1)
			highlight.OutlineTransparency = highlight.FillTransparency
		end
	end
	for character, highlight in impacts do
		if not seen[character] then highlight:Destroy(); impacts[character] = nil end
	end
end

function Visuals.ClearImpacts()
	for character, highlight in impacts do highlight:Destroy(); impacts[character] = nil end
end

return Visuals
