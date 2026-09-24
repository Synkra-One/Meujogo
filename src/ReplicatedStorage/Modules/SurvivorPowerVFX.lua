--!strict
-- Client presentation only. Replace handlers/assets without touching power rules.
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local Assets = require(script.Parent.AssetRegistry).SurvivorPowers
local VFX = {}
local sessions: { any } = {}
local watchedAttributes = { RajadaFinal = "PowerSpeedMultiplier", TiroCerteiro = "PowerPreciseShot",
	MantoDeSombras = "PowerFearHidden", EscudoProtetor = "Imune",
	PosturaInabalavel = "PowerStunImmune", GolpeDeSorte = "PowerLuckyDodge" }

local function keep(session: any, object: Instance): any
	table.insert(session.objects, object)
	return object
end

local function clean(session: any)
	for _, connection in session.connections do connection:Disconnect() end
	for part, transparency in session.faded do
		if part.Parent and part.LocalTransparencyModifier == 0.65 then part.LocalTransparencyModifier = transparency end
	end
	for _, object in session.objects do object:Destroy() end
	if session.track then session.track:Stop(0.1); session.track:Destroy() end
end

local function anchor(session: any, position: Vector3): BasePart
	local part = keep(session, Instance.new("Part"))
	part.Name = "SurvivorPowerFX"
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Transparency = 1
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.Position = position
	part.Parent = Workspace
	return part
end

local function particles(session: any, parent: BasePart, color: Color3, smoke: boolean, rate: number, count: number, feet: boolean?)
	local attachment = keep(session, Instance.new("Attachment"))
	attachment.Position = if feet then Vector3.new(0, -2.5, 0) else Vector3.zero
	attachment.Parent = parent
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = if smoke then "rbxasset://textures/particles/smoke_main.dds" else "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = if smoke then 0.1 else 0.6
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.3, 0.8)
	emitter.Speed = NumberRange.new(1, if smoke then 5 else 8)
	emitter.SpreadAngle = Vector2.new(130, 130)
	emitter.Acceleration = Vector3.new(0, if smoke then 2 else 6, 0)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, if smoke then 0.6 else 0.12), NumberSequenceKeypoint.new(1, if smoke then 2.3 else 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = attachment
	emitter:Emit(count)
end

local function flash(session: any, position: Vector3, color: Color3, size: number)
	local part = anchor(session, position)
	part.Shape, part.Material, part.Color = Enum.PartType.Ball, Enum.Material.Neon, color
	part.Transparency = 0.72
	TweenService:Create(part, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(size, size, size), Transparency = 1,
	}):Play()
end

local function highlight(session: any, target: Instance, color: Color3, opacity: number)
	local h = keep(session, Instance.new("Highlight"))
	h.Adornee = target
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.FillColor, h.OutlineColor = color, color
	h.FillTransparency, h.OutlineTransparency = 1, 1
	h.Parent = target
	TweenService:Create(h, TweenInfo.new(0.18), { FillTransparency = opacity, OutlineTransparency = 0.4 }):Play()
end

local function trails(session: any, root: BasePart, color: Color3)
	for _, x in { -0.85, 0.85 } do
		local a = keep(session, Instance.new("Attachment"))
		local b = keep(session, Instance.new("Attachment"))
		a.Position, b.Position = Vector3.new(x, 0.6, 0.3), Vector3.new(x, -0.5, 0.3)
		a.Parent, b.Parent = root, root
		local trail = keep(session, Instance.new("Trail"))
		trail.Attachment0, trail.Attachment1 = a, b
		trail.Color = ColorSequence.new(color)
		trail.Transparency = NumberSequence.new(0.55, 1)
		trail.Lifetime, trail.MinLength, trail.LightEmission = 0.22, 0.15, 0.5
		trail.FaceCamera = true
		trail.Parent = root
	end
end

local function fadeShadow(session: any, character: Model)
	local function fade(object: Instance)
		if object:IsA("BasePart") and object.Name ~= "HumanoidRootPart" and object.Transparency < 1 then
			session.faded[object] = object.LocalTransparencyModifier
			object.LocalTransparencyModifier = 0.65
		end
	end
	for _, object in character:GetDescendants() do fade(object) end
	table.insert(session.connections, character.DescendantAdded:Connect(fade))
end

function VFX.Play(id: string, character: Model?, position: Vector3, duration: number, phase: string)
	local asset = Assets[id]
	if not asset then return end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and not root:IsA("BasePart") then root = nil end
	local persistent = phase == "Activate" and watchedAttributes[id] ~= nil and root ~= nil
	if persistent then
		for index = #sessions, 1, -1 do
			local old = sessions[index]
			if old.character == character and old.id == id then clean(old); table.remove(sessions, index) end
		end
	end
	local session: any = { objects = {}, connections = {}, faded = {}, character = character, id = id,
		endsAt = os.clock() + math.max(0.9, duration), born = os.clock(), persistent = persistent }
	table.insert(sessions, session)
	local emitterRoot = if root then root :: BasePart else anchor(session, position)
	local color, style = asset.Color, asset.Style
	if phase == "Impact" or phase == "Dodge" then
		local source = anchor(session, position)
		particles(session, source, color, style == "Dust" or style == "Charge", 0, 18)
		flash(session, position, color, if style == "Charge" then 9 else 5)
	elseif style == "Trail" or style == "Charge" then
		trails(session, emitterRoot, color)
		particles(session, emitterRoot, color, true, if style == "Trail" then 4 else 0, 8, root ~= nil)
	elseif style == "Shadow" and character then
		fadeShadow(session, character)
		particles(session, emitterRoot, color, true, 5, 10)
	elseif style == "Shield" and root then
		local bubble = keep(session, Instance.new("Part"))
		bubble.Name = "PowerShieldVisual"
		bubble.Shape, bubble.Material = Enum.PartType.Ball, Enum.Material.ForceField
		bubble.Size, bubble.Color, bubble.Transparency = Vector3.new(6.5, 7.5, 6.5), color, 1
		bubble.Anchored, bubble.CanCollide, bubble.CanTouch, bubble.CanQuery = true, false, false, false
		bubble.CFrame = (root :: BasePart).CFrame
		bubble.Parent = Workspace
		session.bubble, session.root = bubble, root
		TweenService:Create(bubble, TweenInfo.new(0.2), { Transparency = 0.5 }):Play()
	elseif style == "Weapon" and character then
		local tool = character:FindFirstChildOfClass("Tool")
		local handle = tool and tool:FindFirstChild("Handle")
		highlight(session, handle or character, color, 0.7)
		table.insert(session.connections, character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				local weaponPart = child:FindFirstChild("Handle")
				if weaponPart then highlight(session, weaponPart, color, 0.7) end
			end
		end))
		particles(session, emitterRoot, color, false, 2, 5)
	elseif style == "Stone" or style == "Gold" then
		if character then highlight(session, character, color, if style == "Stone" then 0.65 else 0.88) end
		particles(session, emitterRoot, color, style == "Stone", 4, 10)
	elseif style == "Heal" then
		particles(session, emitterRoot, color, false, 8, 16, root ~= nil)
		if character then highlight(session, character, color, 0.83) end
	else
		particles(session, emitterRoot, color, style == "Smoke" or style == "Dust", 0, if style == "Sense" then 5 else 18, style == "Dust" and root ~= nil)
	end
	if asset.SoundId and asset.SoundId ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId, sound.Volume, sound.PlaybackSpeed = asset.SoundId, 0.24, if style == "Stone" then 0.6 else 1.2
		sound.RollOffMaxDistance, sound.RollOffMinDistance = 60, 5
		sound.Parent = emitterRoot
		sound:Play()
		Debris:AddItem(sound, 2)
	end
	if phase == "Activate" and character and asset.AnimationId and asset.AnimationId ~= "" then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local animation = keep(session, Instance.new("Animation"))
			animation.AnimationId = asset.AnimationId
			local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
			if ok and track then
				session.track = track
				-- Colocar a armadilha precisa dominar a locomoção e os braços
				-- precisam ficar livres durante todo o gesto.
				track.Priority = if id == "ArmadilhaImprovisada"
					then Enum.AnimationPriority.Action4
					else Enum.AnimationPriority.Action
				track.Looped = false
				-- O começo precisa manter o ritmo original. No Diego, a parte
				-- de sentar e trabalhar com os braços fica mais lenta somente
				-- depois da metade do asset.
				track:Play(0.12, 1, 1)
				if id == "ArmadilhaImprovisada" then
					session.trapOriginalLength = track.Length
					session.trapSlowed = false
				end
				-- O servidor coloca a trap no meio do gesto; mantenha o track
				-- vivo até o fim mesmo quando a duração enviada for curta.
				if track.Length > 0 then
					local playedLength = if id == "ArmadilhaImprovisada"
						then track.Length * 1.5 -- metade normal + metade a 0.5x
						else track.Length
					session.endsAt = math.max(session.endsAt, os.clock() + playedLength + 0.15)
				end
			elseif not ok then
				warn(string.format("[SurvivorPowerVFX] Não foi possível carregar a animação de %s (%s).", id, asset.AnimationId))
			end
		elseif id == "ArmadilhaImprovisada" then
			warn("[SurvivorPowerVFX] Diego não possui Animator; a armadilha será colocada sem animação.")
		end
	end
end

function VFX.Step()
	local now = os.clock()
	for index = #sessions, 1, -1 do
		local session = sessions[index]
		local character = session.character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if session.id == "ArmadilhaImprovisada" and session.track and not session.trapSlowed then
			local originalLength = session.trapOriginalLength
			if (not originalLength or originalLength <= 0) and session.track.Length > 0 then
				originalLength = session.track.Length
				session.trapOriginalLength = originalLength
				session.endsAt = math.max(session.endsAt, now + originalLength * 1.5 + 0.15)
			end
			if originalLength and originalLength > 0 and session.track.TimePosition >= originalLength * 0.5 then
				session.track:AdjustSpeed(0.5)
				session.trapSlowed = true
			end
		end
		local expired = now >= session.endsAt or (character and (not character.Parent or not humanoid or humanoid.Health <= 0))
		if session.persistent and now - session.born > 0.3 and not character:GetAttribute(watchedAttributes[session.id]) then expired = true end
		if expired then clean(session); table.remove(sessions, index)
		elseif session.bubble and session.root.Parent then session.bubble.CFrame = session.root.CFrame end
	end
end

function VFX.Clear()
	for _, session in sessions do clean(session) end
	table.clear(sessions)
end

return VFX
