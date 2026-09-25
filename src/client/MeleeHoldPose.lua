--!strict
--[[
	MeleeHoldPose
	Mantem a pose do Taco/Pe de cabra nos bracos (e pescoco) SEM tocar nas pernas.

	O clip Idle do Taco tem keyframes de corpo inteiro: tocado sobre a
	locomocao ele congela as pernas, e misturado com peso baixo o braco volta a
	balancar com o walk/run. O Roblox nao mascara animacao por membro, entao:
	  1. Seed: na primeira vez, o Idle toca com peso 1 por poucos quadros e a
	     Transform de Right/Left Shoulder e Neck e copiada (pose compartilhada por
	     todos os R6).
	  2. Depois, todo quadro, pra QUALQUER personagem segurando a arma, essas tres
	     juntas recebem a pose copiada por cima da animacao. Pernas e tronco
	     ficam 100% com o Animate/pacote de movimento (idle, walk, run, crouch).
	O override roda em cada cliente (tambem nos outros jogadores), pois so as
	tracks replicam, nao as Transforms.

	Golpes (Hit/Finish) têm prioridade no corpo; durante eles, as ancas recebem
	a passada Walk/Run de um rig local invisível. Reset em PreAnimation e escrita
	em PreSimulation garantem que o Animator já avaliou o quadro.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BatConfig = require(ReplicatedStorage.Modules.BaseballBatConfig)

local HoldPose = {}

local JOINT_NAMES = { "Right Shoulder", "Left Shoulder", "Neck" }
local ITEM_ATTRIBUTES = { "TacoBeisebol", "LancaDeBambu" }
local BLOCKING_FLAGS = { "GrabLocked", "ShadowRushBusy", "TeleportBusy", "PowerStunned", "FearTripping" }
local SEED_FRAMES = 3
local SEED_TIMEOUT = 2
local BLEND_RATE = 14

type Applied = { base: CFrame, result: CFrame }
type LocomotionMirror = {
	model: Model,
	tracks: { [string]: AnimationTrack },
	hips: { [string]: Motor6D },
}
type CharacterState = {
	joints: { [string]: Motor6D },
	legs: { [string]: Motor6D },
	blend: number,
	locomotion: LocomotionMirror?,
}

local LOCOMOTION = BatConfig.Animations.Locomotion
local LOCOMOTION_NAMES = { "Idle", "Walk", "Jog", "Run" }
local LEG_JOINT_NAMES = { "Left Hip", "Right Hip" }

local held: { [string]: CFrame }? = nil
local seeding = false
local applied: { [Motor6D]: Applied } = {}
local states: { [Model]: CharacterState } = {}
local started = false

local function smooth(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * math.min(dt, 0.1)))
end

local function findJoints(character: Model): { [string]: Motor6D }
	local found: { [string]: Motor6D } = {}
	local torso = character:FindFirstChild("Torso")
	if not torso then
		return found
	end
	for _, name in JOINT_NAMES do
		local joint = torso:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") then
			found[name] = joint
		end
	end
	return found
end

local function findLegJoints(character: Model): { [string]: Motor6D }
	local found: { [string]: Motor6D } = {}
	local torso = character:FindFirstChild("Torso")
	if torso then
		for _, name in LEG_JOINT_NAMES do
			local joint = torso:FindFirstChild(name)
			if joint and joint:IsA("Motor6D") then
				found[name] = joint
			end
		end
	end
	return found
end

local function holdingWeapon(character: Model): boolean
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			for _, attribute in ITEM_ATTRIBUTES do
				if child:GetAttribute(attribute) == true then
					return true
				end
			end
		end
	end
	return false
end

local function blockedFor(character: Model, humanoid: Humanoid): boolean
	if humanoid.Health <= 0 then
		return true
	end
	local combatState = character:GetAttribute("CombatAnimationState")
	if combatState == "Hurt" or combatState == "Death" then
		return true
	end
	for _, flag in BLOCKING_FLAGS do
		if character:GetAttribute(flag) == true then
			return true
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:GetAttribute("IsCrawling") == true
end

-- Um rig local e invisível reproduz apenas o ciclo Walk/Run. Os golpes são
-- animações de corpo inteiro (Action3), então copiamos suas ancas por cima
-- durante o golpe, sem interferir nos braços, tronco ou rede do personagem.
local function makeLocomotionMirror(character: Model): LocomotionMirror?
	local model = Instance.new("Model")
	model.Name = "_MeleeLocomotionMirror"
	local partNames = { "HumanoidRootPart", "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
	local parts: { [string]: BasePart } = {}
	for _, name in partNames do
		local source = character:FindFirstChild(name)
		if not source or not source:IsA("BasePart") then
			model:Destroy()
			return nil
		end
		local part = source:Clone()
		for _, child in part:GetChildren() do
			if child:IsA("JointInstance") or child:IsA("Constraint") then
				child:Destroy()
			end
		end
		part.Transparency = 1
		part.LocalTransparencyModifier = 1
		part.CastShadow = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Anchored = name == "HumanoidRootPart"
		part.Parent = model
		parts[name] = part
	end
	for _, source in character:GetDescendants() do
		if source:IsA("Motor6D") and source.Part0 and source.Part1 then
			local part0 = parts[source.Part0.Name]
			local part1 = parts[source.Part1.Name]
			if part0 and part1 then
				local joint = Instance.new("Motor6D")
				joint.Name = source.Name
				joint.C0 = source.C0
				joint.C1 = source.C1
				joint.Part0 = part0
				joint.Part1 = part1
				joint.Parent = part0
			end
		end
	end
	model.PrimaryPart = parts.HumanoidRootPart
	local controller = Instance.new("AnimationController")
	controller.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = controller
	model.Parent = workspace
	model:PivotTo(character:GetPivot())

	local tracks: { [string]: AnimationTrack } = {}
	for _, name in LOCOMOTION_NAMES do
		local animation = Instance.new("Animation")
		animation.AnimationId = LOCOMOTION[name]
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		animation:Destroy()
		if ok and track then
			track.Priority = if name == "Idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
			track.Looped = true
			tracks[name] = track
		end
	end
	local hips: { [string]: Motor6D } = {}
	for _, name in LEG_JOINT_NAMES do
		local joint = parts.Torso:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") then
			hips[name] = joint
		end
	end
	if not tracks.Walk or not tracks.Run or not hips["Left Hip"] or not hips["Right Hip"] then
		model:Destroy()
		return nil
	end
	return { model = model, tracks = tracks, hips = hips }
end

local function destroyLocomotionMirror(state: CharacterState)
	local mirror = state.locomotion
	if mirror then
		for _, track in mirror.tracks do
			track:Stop(0)
		end
		mirror.model:Destroy()
		state.locomotion = nil
	end
end

local function removeCharacter(character: Model?)
	if not character then
		return
	end
	local state = states[character]
	if state then
		destroyLocomotionMirror(state)
		states[character] = nil
	end
end

local function locomotionName(character: Model, humanoid: Humanoid): string
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return "Idle"
	end
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if speed <= 0.5 then
		return "Idle"
	end
	if root:GetAttribute("IsSprinting") == true and humanoid.WalkSpeed >= 20 then
		return "Run"
	end
	if root:GetAttribute("IsJogging") == true and humanoid.WalkSpeed >= 10 then
		return "Jog"
	end
	return "Walk"
end

local function syncLocomotion(state: CharacterState, character: Model, humanoid: Humanoid)
	local mirror = state.locomotion
	if not mirror then
		mirror = makeLocomotionMirror(character)
		state.locomotion = mirror
	end
	if not mirror then
		return
	end
	mirror.model:PivotTo(character:GetPivot())
	local sourceTracks: { [string]: AnimationTrack } = {}
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			local animation = track.Animation
			if animation then
				for _, name in LOCOMOTION_NAMES do
					if animation.AnimationId == LOCOMOTION[name] then
						sourceTracks[name] = track
						break
					end
				end
			end
		end
	end
	local fallback = locomotionName(character, humanoid)
	for _, name in LOCOMOTION_NAMES do
		local track = mirror.tracks[name]
		if track then
			local source = sourceTracks[name]
			local weight = if source then math.clamp(source.WeightCurrent, 0, 1) else (if name == fallback then 1 else 0)
			if weight > 0.001 then
				if not track.IsPlaying then
					track:Play(0, weight, 1)
				else
					track:AdjustWeight(weight, 0)
				end
				if source then
					pcall(function()
						track.TimePosition = source.TimePosition
					end)
				end
				local root = character:FindFirstChild("HumanoidRootPart")
				if name == "Run" then
					track:AdjustSpeed(1.3)
				elseif name == "Walk" or name == "Jog" then
					local velocity = if root and root:IsA("BasePart") then root.AssemblyLinearVelocity else Vector3.zero
					track:AdjustSpeed(Vector3.new(velocity.X, 0, velocity.Z).Magnitude / 14.5)
				else
					track:AdjustSpeed(1)
				end
			else
				track:Stop(0)
			end
		end
	end
end

local function syncAllLocomotion()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local state = character and states[character]
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if state and state.locomotion and character and humanoid then
			syncLocomotion(state, character, humanoid)
		end
	end
end

-- Maior peso atual entre os golpes tocando (0 = nenhum).
local function swingWeight(humanoid: Humanoid): number
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return 0
	end
	local weight = 0
	for _, track in animator:GetPlayingAnimationTracks() do
		local animation = track.Animation
		if animation and (animation.AnimationId == BatConfig.Animations.Hit
			or animation.AnimationId == BatConfig.Animations.Finish) then
			weight = math.max(weight, track.WeightCurrent)
		end
	end
	return weight
end

function HoldPose.HasPose(): boolean
	return held ~= nil
end

-- Copia a pose do Idle. `idle` ja carregado no Animator de `character`.
function HoldPose.Seed(character: Model, idle: AnimationTrack)
	if held or seeding then
		return
	end
	seeding = true
	idle.Priority = Enum.AnimationPriority.Action4
	idle.Looped = true
	idle:Play(0, 1, 1)
	local frames = 0
	local startedAt = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.PreSimulation:Connect(function()
		frames += 1
		local timedOut = os.clock() - startedAt > SEED_TIMEOUT
		local ready = frames >= SEED_FRAMES and idle.Length > 0 and idle.WeightCurrent > 0.99
		if not ready and not timedOut then
			return
		end
		if ready and character.Parent then
			local pose: { [string]: CFrame } = {}
			for name, joint in findJoints(character) do
				pose[name] = joint.Transform
			end
			if next(pose) then
				held = pose
			end
		end
		idle:Stop(0)
		seeding = false
		if connection then
			connection:Disconnect()
		end
	end)
end

-- Reset (PreAnimation): devolve so o que ESTE modulo escreveu.
local function reset()
	for joint, entry in applied do
		if joint.Parent and joint.Transform == entry.result then
			joint.Transform = entry.base
		end
	end
	table.clear(applied)
end

local function update(dt: number)
	local pose = held
	if not pose or seeding then
		return
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid then
			continue
		end
		local state = states[character]
		if not holdingWeapon(character) then
			if state then
				destroyLocomotionMirror(state)
				states[character] = nil
			end
			continue
		end
		if not state then
			state = { joints = findJoints(character), legs = findLegJoints(character), blend = 0, locomotion = nil }
			state.locomotion = makeLocomotionMirror(character)
			states[character] = state
		end
		local target = if blockedFor(character, humanoid) then 0 else 1
		state.blend = smooth(state.blend, target, BLEND_RATE, dt)
		local weight = state.blend * (1 - swingWeight(humanoid))
		if weight >= 0.001 then
			for name, joint in state.joints do
				local goal = pose[name]
				if goal and joint.Parent then
					local base = joint.Transform
					local result = if weight >= 0.999 then goal else base:Lerp(goal, weight)
					applied[joint] = { base = base, result = result }
					joint.Transform = result
				end
			end
		end
		if swingWeight(humanoid) > 0.001 and not blockedFor(character, humanoid) then
			local mirror = state.locomotion
			if mirror then
				for name, joint in mirror.hips do
					local target = state.legs[name]
					if target and target.Parent then
						local base = target.Transform
						local result = joint.Transform
						applied[target] = { base = base, result = result }
						target.Transform = result
					end
				end
			end
		end
	end
end

function HoldPose.Start()
	if started then
		return
	end
	started = true
	RunService.PreAnimation:Connect(reset)
	RunService.PreAnimation:Connect(syncAllLocomotion)
	RunService.PreSimulation:Connect(update)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(removeCharacter)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(removeCharacter)
	end
	Players.PlayerRemoving:Connect(function(player)
		removeCharacter(player.Character)
	end)
end

return HoldPose
