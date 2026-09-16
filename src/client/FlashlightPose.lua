--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.FlashlightConfig)

local Pose = {}
Pose.__index = Pose

type JointSet = {
	right: Motor6D?,
	left: Motor6D?,
	neck: Motor6D?,
}

type TrackSet = { [string]: AnimationTrack }

local BLOCKING_FLAGS = {
	"GrabLocked",
	"ShadowRushBusy",
	"TeleportBusy",
	"PowerStunned",
	"Amarrado",
	"FearTripping",
}

local function smooth(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * math.min(dt, 0.1)))
end

local function findJoint(character: Model?, torso: BasePart?, name: string): Motor6D?
	local found = torso and torso:FindFirstChild(name)
	if found and found:IsA("Motor6D") then return found end
	found = character and character:FindFirstChild(name, true)
	return if found and found:IsA("Motor6D") then found else nil
end

local function jointsFor(character: Model?): JointSet
	if not character then return { right = nil, left = nil, neck = nil } end
	local torso = character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then torso = character:FindFirstChild("UpperTorso") end
	local torsoPart = if torso and torso:IsA("BasePart") then torso else nil
	return {
		right = findJoint(character, torsoPart, "Right Shoulder") or findJoint(character, torsoPart, "RightShoulder"),
		left = findJoint(character, torsoPart, "Left Shoulder") or findJoint(character, torsoPart, "LeftShoulder"),
		neck = findJoint(character, torsoPart, "Neck"),
	}
end

local function animationId(value: unknown): string?
	if type(value) ~= "string" or value == "" then return nil end
	if string.match(value, "^rbxassetid://%d+$") then return value end
	if string.match(value, "^%d+$") then return "rbxassetid://" .. value end
	return nil
end

local function humanoidFor(character: Model?): Humanoid?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid:IsA("Humanoid") then humanoid else nil
end

local function blocked(character: Model, humanoid: Humanoid): boolean
	if humanoid.Health <= 0 then return true end
	local combatState = character:GetAttribute("CombatAnimationState")
	if combatState == "Hurt" or combatState == "Death" then return true end
	for _, flag in BLOCKING_FLAGS do
		if character:GetAttribute(flag) == true then return true end
	end
	return false
end

local function stateFor(character: Model, humanoid: Humanoid, root: BasePart?, speed: number, previous: string): string
	if blocked(character, humanoid) then return "Blocked" end
	if root and root:GetAttribute("IsCrawling") == true then return "Crawl" end
	-- Separate intent from physics so a sliding/root-velocity remainder cannot
	-- kick the authored idle out. The two thresholds provide hysteresis for
	-- thumbsticks and short direction changes around zero.
	local wasMoving = previous == "Walk" or previous == "Sprint" or previous == "CrouchWalk"
	local moving = humanoid.MoveDirection.Magnitude > (if wasMoving then 0.035 else 0.12)
		and speed > (if wasMoving then 0.35 else 0.9)
	local humanoidState = humanoid:GetState()
	if humanoidState == Enum.HumanoidStateType.Jumping
		or humanoidState == Enum.HumanoidStateType.Freefall
		or humanoidState == Enum.HumanoidStateType.FallingDown then
		return "Air"
	end
	if root and root:GetAttribute("IsCrouching") == true then
		return if moving then "CrouchWalk" else "CrouchIdle"
	end
	if moving and root and (root:GetAttribute("IsSprinting") == true or speed >= 18) then return "Sprint" end
	return if moving then "Walk" else "Idle"
end

function Pose.new(playTracks: boolean?)
	return setmetatable({
		playTracks = playTracks ~= false,
		tool = nil :: Tool?,
		character = nil :: Model?,
		humanoid = nil :: Humanoid?,
		joints = { right = nil, left = nil, neck = nil } :: JointSet,
		tracks = {} :: TrackSet,
		animations = {} :: { Animation },
		failedStates = {} :: { [string]: boolean },
		currentState = "None",
		candidateState = "None",
		candidateTime = 0,
		equipBlend = 0,
		aimBlend = 0,
		movementBlend = 0,
		pitch = 0,
		yaw = 0,
		rightPose = CFrame.identity,
		leftPose = CFrame.identity,
		neckPose = CFrame.identity,
		stepTime = 0,
	}, Pose)
end

local function priorityFor(name: string): Enum.AnimationPriority
	if name == "Click" then return Enum.AnimationPriority.Action3 end
	if name == "Equip" then return Enum.AnimationPriority.Action2 end
	return Enum.AnimationPriority.Action
end

function Pose:_stopTrack(name: string, fadeTime: number)
	local track = self.tracks[name]
	if track and track.IsPlaying then track:Stop(fadeTime) end
end

function Pose:_warnIfUnloaded(name: string, track: AnimationTrack)
	task.delay(Config.AnimationLoadWarningDelay, function()
		if self.tracks[name] == track and track.IsPlaying and track.Length == 0 then
			self.failedStates[name] = true
			track:Stop(Config.AnimationFadeTime)
			warn(string.format(
				"[Lanterna] A animacao %s nao carregou. Confirme R6 e a permissao do asset para esta experiencia.",
				name
			))
		end
	end)
end

function Pose:_loadTracks()
	if not self.playTracks then return end
	local humanoid = self.humanoid
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	for state, rawId in Config.Animations do
		local id = animationId(rawId)
		if id then
			local animation = Instance.new("Animation")
			animation.Name = "Flashlight" .. state
			animation.AnimationId = id
			local ok, loaded = pcall(function()
				return (animator :: Animator):LoadAnimation(animation)
			end)
			if ok and loaded then
				local track = loaded :: AnimationTrack
				track.Priority = priorityFor(state)
				track.Looped = state == "Idle"
				self.tracks[state] = track
				table.insert(self.animations, animation)
			else
				self.failedStates[state] = true
				warn(string.format("[Lanterna] Nao foi possivel carregar a animacao %s (%s): %s", state, id, tostring(loaded)))
				animation:Destroy()
			end
		end
	end
end

function Pose:_ensureIdle()
	local track = self.tracks.Idle
	if track and not track.IsPlaying and not self.failedStates.Idle then
		track:Play(Config.AnimationFadeTime, 1, 1)
		self:_warnIfUnloaded("Idle", track)
	end
end

function Pose:_playOnce(name: string)
	local track = self.tracks[name]
	if not track or self.failedStates[name] then return end
	track:Stop(0)
	track:Play(Config.AnimationFadeTime, 1, 1)
	self:_warnIfUnloaded(name, track)
end

function Pose:SetTool(tool: Tool?)
	if self.tool == tool then return end
	self:Clear()
	if not tool then return end
	local character = tool.Parent
	if not character or not character:IsA("Model") then return end
	self.tool = tool
	self.character = character
	self.humanoid = humanoidFor(character)
	self.joints = jointsFor(character)
	self:_loadTracks()
	self:_playOnce("Equip")
	self:_ensureIdle()
end

function Pose:Clear()
	for _, track in self.tracks do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(self.tracks)
	for _, animation in self.animations do animation:Destroy() end
	table.clear(self.animations)
	table.clear(self.failedStates)
	for _, joint in self.joints do
		if joint and joint.Parent then joint.Transform = CFrame.identity end
	end
	self.tool = nil
	self.character = nil
	self.humanoid = nil
	self.joints = { right = nil, left = nil, neck = nil }
	self.currentState = "None"
	self.candidateState = "None"
	self.candidateTime = 0
	self.equipBlend = 0
	self.aimBlend = 0
	self.movementBlend = 0
	self.pitch = 0
	self.yaw = 0
	self.rightPose = CFrame.identity
	self.leftPose = CFrame.identity
	self.neckPose = CFrame.identity
	self.stepTime = 0
end

function Pose:PlayClick()
	self:_playOnce("Click")
end

function Pose:_stableState(rawState: string, dt: number): string
	if self.currentState == "None" or rawState == "Blocked" or rawState == "Crawl"
		or string.find(rawState, "Crouch", 1, true) then
		self.candidateState, self.candidateTime = rawState, 0
		return rawState
	end
	if rawState == self.currentState then
		self.candidateState, self.candidateTime = rawState, 0
		return rawState
	end
	if self.candidateState ~= rawState then
		self.candidateState, self.candidateTime = rawState, 0
	else
		self.candidateTime += math.min(dt, 0.1)
	end
	local delay = if rawState == "Air" then Config.AnimationAirDebounce else Config.AnimationStateDebounce
	return if self.candidateTime >= delay then rawState else self.currentState
end

local function statePose(state: string, authoredIdle: boolean): (Vector3, Vector3, number)
	if authoredIdle then
		-- The authored Idle clip is the flashlight hold layer. Keep walk/run/
		-- crouch locomotion underneath it and add only aim/breathing/sway.
		return Vector3.zero, Vector3.zero, 0
	end
	if state == "Walk" then
		return Vector3.new(-31, 8, 20), Vector3.new(-14, -7, -12), 1
	elseif state == "Sprint" then
		return Vector3.new(-25, 14, 27), Vector3.new(-4, -11, -18), 1.35
	elseif state == "CrouchIdle" then
		return Vector3.new(-34, 10, 22), Vector3.new(-19, -8, -14), 0.4
	elseif state == "CrouchWalk" then
		return Vector3.new(-36, 11, 23), Vector3.new(-21, -8, -15), 0.65
	elseif state == "Air" then
		return Vector3.new(-28, 12, 23), Vector3.new(-13, -8, -14), 0.2
	end
	return Vector3.new(-31, 8, 20), Vector3.new(-15, -7, -13), 0
end

local function applyAdditive(joint: Motor6D?, delta: CFrame)
	if not joint or not joint.Parent then return end
	-- Animator escreve a pose-base em Transform antes do RenderStep; a mira
	-- entra depois, sem apagar o idle publicado nem a locomocao do pacote.
	joint.Transform = joint.Transform * delta
end

function Pose:Update(direction: Vector3, aiming: boolean, dt: number)
	local tool, character, humanoid = self.tool, self.character, self.humanoid
	if not tool then return end
	if not tool.Parent or tool.Parent ~= character or not character or not humanoid then
		self:Clear()
		return
	end
	if not self.joints.right and not self.joints.left then self.joints = jointsFor(character) end

	local root = character:FindFirstChild("HumanoidRootPart")
	local rootPart = if root and root:IsA("BasePart") then root else nil
	local speed = if rootPart then (rootPart.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude else 0
	local rawState = stateFor(character, humanoid, rootPart, speed, self.currentState)
	local state = self:_stableState(rawState, dt)
	self.currentState = state
	if state == "Blocked" or state == "Crawl" then
		self:_stopTrack("Idle", Config.AnimationFadeTime)
		self.equipBlend = 0
		self.aimBlend = 0
		self.rightPose = CFrame.identity
		self.leftPose = CFrame.identity
		self.neckPose = CFrame.identity
		return
	end
	self:_ensureIdle()

	self.equipBlend = smooth(self.equipBlend, 1, 12, dt)
	self.aimBlend = smooth(self.aimBlend, if aiming then 1 else 0, 16, dt)
	self.movementBlend = smooth(self.movementBlend, math.clamp(speed / 12, 0, 1), 9, dt)

	local localAim = if rootPart then rootPart.CFrame:VectorToObjectSpace(direction) else direction
	-- In Roblox, a positive X rotation raises the -Z look axis.  Keep this
	-- sign aligned with Camera.CFrame.LookVector: looking up lifts the arms
	-- and head; looking down lowers them.  The prior inverse sign made the
	-- visual beam follow the camera while the held Tool pose lagged/opposed it.
	local targetPitch = math.clamp(math.asin(math.clamp(localAim.Y, -1, 1)), math.rad(-65), math.rad(65))
	local targetYaw = math.clamp(math.atan2(-localAim.X, -localAim.Z), math.rad(-55), math.rad(55))
	self.pitch = smooth(self.pitch, targetPitch, Config.PoseAimResponsiveness, dt)
	self.yaw = smooth(self.yaw, targetYaw, Config.PoseAimResponsiveness, dt)
	local pitch, yaw = self.pitch, self.yaw
	local localVelocity = if rootPart then rootPart.CFrame:VectorToObjectSpace(rootPart.AssemblyLinearVelocity) else Vector3.zero
	local side = math.clamp(localVelocity.X / 12, -1, 1)
	local forward = math.clamp(-localVelocity.Z / 14, -1, 1)
	local backpedal = math.clamp(-forward, 0, 1)
	local idleTrack = self.tracks.Idle
	local authoredIdle = idleTrack ~= nil and idleTrack.IsPlaying and not self.failedStates.Idle
	local rightBase, leftBase, bobScale = statePose(state, authoredIdle)
	local frequency = if state == "Sprint" then 11 elseif state == "Walk" then 7 elseif state == "CrouchWalk" then 5 else 1.25
	self.stepTime += dt * frequency
	local stride = math.sin(self.stepTime) * math.rad(5.8) * bobScale * self.movementBlend
	local counter = math.cos(self.stepTime * 2) * math.rad(2.4) * bobScale * self.movementBlend
	local sway = math.sin(self.stepTime + math.pi / 3) * math.rad(4.5) * side * self.movementBlend
	local breathe = math.sin(os.clock() * 1.25) * math.rad(1.2) * (1 - self.movementBlend * 0.45)
	local aim, hold = self.aimBlend, self.equipBlend

	local right = CFrame.Angles(
		math.rad(rightBase.X) + stride + breathe + pitch * Config.RightAimPitch * aim + math.rad(5) * backpedal,
		math.rad(rightBase.Y) + yaw * Config.RightAimYaw * aim + counter + sway,
		math.rad(rightBase.Z) + math.rad(10) * aim - math.rad(10) * side
	)
	local left = CFrame.Angles(
		math.rad(leftBase.X) - stride * 0.68 + pitch * Config.LeftAimPitch * aim + math.rad(3) * backpedal,
		math.rad(leftBase.Y) + yaw * Config.LeftAimYaw * aim - counter * 0.7 - sway * 0.45,
		math.rad(leftBase.Z) - math.rad(6) * aim + math.rad(6) * side
	)
	local neck = CFrame.Angles(pitch * Config.NeckAimPitch * aim, yaw * Config.NeckAimYaw * aim,
		-math.rad(2) * side * self.movementBlend)
	local poseAlpha = 1 - math.exp(-Config.PoseBlendResponsiveness * math.min(dt, 0.1))
	self.rightPose = self.rightPose:Lerp(CFrame.identity:Lerp(right, hold), poseAlpha)
	self.leftPose = self.leftPose:Lerp(CFrame.identity:Lerp(left, hold), poseAlpha)
	self.neckPose = self.neckPose:Lerp(CFrame.identity:Lerp(neck, hold), poseAlpha)

	local joints = self.joints
	applyAdditive(joints.right, self.rightPose)
	applyAdditive(joints.left, self.leftPose)
	applyAdditive(joints.neck, self.neckPose)
end

function Pose:Destroy()
	self:Clear()
end

export type Controller = typeof(Pose.new())
return Pose
