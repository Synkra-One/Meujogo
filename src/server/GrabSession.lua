--!strict
-- Owns animation playback, rig locking, synchronization and idempotent cleanup.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DamageSystem = require(script.Parent.DamageSystem)
local Elimination = require(script.Parent.Elimination)

local GrabSession = {}

type HumanoidSnapshot = {
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
	jumpingEnabled: boolean,
}

type RigSnapshot = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	humanoidState: HumanoidSnapshot,
	rootAnchored: boolean,
	collisions: { [BasePart]: boolean },
}

local function validAnimationId(animationId: unknown): boolean
	if type(animationId) ~= "string" then
		return false
	end
	local digits = string.match(animationId, "%d+")
	return digits ~= nil and tonumber(digits) ~= 0
end

local function animatorFor(humanoid: Humanoid): Animator
	local existing = humanoid:FindFirstChildOfClass("Animator")
	if existing then
		return existing
	end
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function loadTrack(humanoid: Humanoid, animationId: unknown): AnimationTrack?
	if not validAnimationId(animationId) then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId :: string
	local ok, track = pcall(function()
		return animatorFor(humanoid):LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or not track then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	return track
end

local function snapshotRig(character: Model, humanoid: Humanoid, root: BasePart): RigSnapshot
	return {
		character = character,
		humanoid = humanoid,
		root = root,
		humanoidState = {
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			jumpHeight = humanoid.JumpHeight,
			autoRotate = humanoid.AutoRotate,
			jumpingEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
		},
		rootAnchored = root.Anchored,
		collisions = {},
	}
end

local function lockRig(snapshot: RigSnapshot, disableCollisions: boolean)
	local humanoid = snapshot.humanoid
	local root = snapshot.root
	humanoid:UnequipTools()
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.Jump = false
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	root.Anchored = true

	if disableCollisions then
		for _, descendant in snapshot.character:GetDescendants() do
			if descendant:IsA("BasePart") then
				snapshot.collisions[descendant] = descendant.CanCollide
				descendant.CanCollide = false
			end
		end
	end
end

local function restoreRig(snapshot: RigSnapshot, player: Player, restoreMotion: boolean)
	local character = snapshot.character
	local humanoid = snapshot.humanoid
	local root = snapshot.root
	if not character.Parent then
		return
	end

	for part, canCollide in snapshot.collisions do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end

	if not restoreMotion or not humanoid.Parent or not root.Parent or humanoid.Health <= 0
		or Elimination.IsEliminated(player) then
		return
	end

	local state = snapshot.humanoidState
	root.Anchored = snapshot.rootAnchored
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	humanoid.WalkSpeed = state.walkSpeed
	humanoid.JumpPower = state.jumpPower
	humanoid.JumpHeight = state.jumpHeight
	humanoid.AutoRotate = state.autoRotate
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, state.jumpingEnabled)
	if not root.Anchored then
		pcall(function()
			root:SetNetworkOwnershipAuto()
		end)
	end
end

local function stopAndDestroy(track: AnimationTrack?)
	if not track then
		return
	end
	pcall(function()
		track:Stop(0.08)
	end)
	track:Destroy()
end

function GrabSession.StartAttempt(monsterPlayer: Player, character: Model, humanoid: Humanoid, config: any, onFinished: () -> ()): any
	local track = loadTrack(humanoid, config.AnimationIds.GrabAttempt)
	local connections: { RBXScriptConnection } = {}
	local finished = false
	local safetyThread: thread? = nil

	local function finish(_reason: string)
		if finished then
			return
		end
		finished = true
		if safetyThread then
			pcall(task.cancel, safetyThread)
			safetyThread = nil
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		if character.Parent then
			character:SetAttribute("GrabBusy", nil)
			character:SetAttribute("GrabLocked", nil)
			character:SetAttribute("GrabState", nil)
		end
		stopAndDestroy(track)
		onFinished()
	end

	character:SetAttribute("GrabBusy", true)
	character:SetAttribute("GrabLocked", true)
	character:SetAttribute("GrabState", "Attempt")

	table.insert(connections, humanoid.Died:Connect(function()
		finish("monster died")
	end))
	table.insert(connections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			finish("character removed")
		end
	end))
	table.insert(connections, monsterPlayer.CharacterRemoving:Connect(function()
		finish("character replacing")
	end))

	if track then
		table.insert(connections, track:GetMarkerReachedSignal("Finished"):Connect(function()
			finish("marker")
		end))
		table.insert(connections, track.Stopped:Connect(function()
			finish("track stopped")
		end))
		track:Play(config.AnimationFadeTime)
		safetyThread = task.delay(config.SafetyTimeout, function()
			finish("safety timeout")
		end)
	else
		safetyThread = task.delay(config.AttemptFallbackDuration, function()
			finish("attempt fallback")
		end)
	end

	return {
		Cancel = function(_self: any, reason: string?)
			finish(reason or "cancelled")
		end,
	}
end

function GrabSession.StartGrab(
	monsterPlayer: Player,
	monsterCharacter: Model,
	monsterHumanoid: Humanoid,
	monsterRoot: BasePart,
	victimPlayer: Player,
	victimCharacter: Model,
	victimHumanoid: Humanoid,
	victimRoot: BasePart,
	config: any,
	onFinished: () -> ()
): (any?, string?)
	local monsterTrack = loadTrack(monsterHumanoid, config.AnimationIds.Grab)
	if not monsterTrack then
		return nil, "AnimationIds.Grab nao foi configurado ou nao carregou"
	end
	local victimTrack = loadTrack(victimHumanoid, config.AnimationIds.VictimGrab)
	local monsterSnapshot = snapshotRig(monsterCharacter, monsterHumanoid, monsterRoot)
	local victimSnapshot = snapshotRig(victimCharacter, victimHumanoid, victimRoot)
	local connections: { RBXScriptConnection } = {}
	local weld: WeldConstraint? = nil
	local alignTween: Tween? = nil
	local safetyThread: thread? = nil
	local finished = false
	local released = false
	local killTriggered = false

	local function releaseVictim()
		if released then
			return
		end
		released = true
		if victimRoot.Parent and victimHumanoid.Health > 0 and not Elimination.IsEliminated(victimPlayer) then
			victimRoot.Anchored = true
		end
		if weld then
			weld:Destroy()
			weld = nil
		end
		if victimCharacter.Parent then
			victimCharacter:SetAttribute("GrabState", "Released")
		end
	end

	local function cleanup(_reason: string)
		if finished then
			return
		end
		finished = true
		if safetyThread then
			pcall(task.cancel, safetyThread)
			safetyThread = nil
		end
		if alignTween then
			alignTween:Cancel()
			alignTween = nil
		end
		releaseVictim()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		stopAndDestroy(monsterTrack)
		stopAndDestroy(victimTrack)

		if monsterCharacter.Parent then
			monsterCharacter:SetAttribute("GrabBusy", nil)
			monsterCharacter:SetAttribute("GrabLocked", nil)
			monsterCharacter:SetAttribute("GrabState", nil)
			monsterCharacter:SetAttribute("GrabVictimUserId", nil)
			monsterCharacter:SetAttribute("GrabAnimationStartedAt", nil)
		end
		if victimCharacter.Parent then
			victimCharacter:SetAttribute("Grabbed", nil)
			victimCharacter:SetAttribute("GrabLocked", nil)
			victimCharacter:SetAttribute("GrabState", nil)
			victimCharacter:SetAttribute("GrabbedByUserId", nil)
			victimCharacter:SetAttribute("GrabAnimationStartedAt", nil)
		end

		restoreRig(monsterSnapshot, monsterPlayer, true)
		restoreRig(victimSnapshot, victimPlayer, true)
		onFinished()
	end

	local function safeMarker(name: string, callback: () -> ())
		table.insert(connections, monsterTrack:GetMarkerReachedSignal(name):Connect(function()
			if finished then
				return
			end
			local ok, err = pcall(callback)
			if not ok then
				warn(string.format("[GrabSession] marker %s falhou: %s", name, tostring(err)))
				cleanup("marker error")
			end
		end))
	end

	monsterCharacter:SetAttribute("GrabBusy", true)
	monsterCharacter:SetAttribute("GrabLocked", true)
	monsterCharacter:SetAttribute("GrabState", "Aligning")
	monsterCharacter:SetAttribute("GrabVictimUserId", victimPlayer.UserId)
	victimCharacter:SetAttribute("Grabbed", true)
	victimCharacter:SetAttribute("GrabLocked", true)
	victimCharacter:SetAttribute("GrabState", "Aligning")
	victimCharacter:SetAttribute("GrabbedByUserId", monsterPlayer.UserId)

	lockRig(monsterSnapshot, false)
	lockRig(victimSnapshot, true)

	local function unequipAdded(humanoid: Humanoid, child: Instance)
		if child:IsA("Tool") then
			humanoid:UnequipTools()
		end
	end
	table.insert(connections, monsterCharacter.ChildAdded:Connect(function(child)
		unequipAdded(monsterHumanoid, child)
	end))
	table.insert(connections, victimCharacter.ChildAdded:Connect(function(child)
		unequipAdded(victimHumanoid, child)
	end))
	table.insert(connections, victimCharacter.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and victimSnapshot.collisions[descendant] == nil then
			victimSnapshot.collisions[descendant] = descendant.CanCollide
			descendant.CanCollide = false
		end
	end))
	table.insert(connections, monsterHumanoid.Died:Connect(function()
		cleanup("monster died")
	end))
	table.insert(connections, victimHumanoid.Died:Connect(function()
		if not killTriggered then
			cleanup("victim died early")
		end
	end))
	for _, character in { monsterCharacter, victimCharacter } do
		table.insert(connections, character.AncestryChanged:Connect(function(_, parent)
			if not parent then
				cleanup("character removed")
			end
		end))
	end
	table.insert(connections, monsterPlayer.CharacterRemoving:Connect(function()
		cleanup("monster character replacing")
	end))
	table.insert(connections, victimPlayer.CharacterRemoving:Connect(function()
		cleanup("victim character replacing")
	end))

	safeMarker("GrabStart", function()
		monsterCharacter:SetAttribute("GrabState", "GrabStart")
		victimCharacter:SetAttribute("GrabState", "GrabStart")
	end)
	safeMarker("Lift", function()
		monsterCharacter:SetAttribute("GrabState", "Lift")
		victimCharacter:SetAttribute("GrabState", "Lift")
	end)
	safeMarker("Kill", function()
		killTriggered = true
		monsterCharacter:SetAttribute("GrabState", "Kill")
		victimCharacter:SetAttribute("GrabState", "Kill")
		DamageSystem.Execute(victimPlayer, { Source = monsterPlayer, Cause = "Grab" })
	end)
	safeMarker("Release", releaseVictim)
	safeMarker("Finished", function()
		cleanup("finished marker")
	end)
	table.insert(connections, monsterTrack.Stopped:Connect(function()
		cleanup("monster track stopped")
	end))

	if victimTrack then
		table.insert(connections, RunService.Heartbeat:Connect(function()
			if finished or not monsterTrack.IsPlaying or not victimTrack.IsPlaying then
				return
			end
			if math.abs(victimTrack.TimePosition - monsterTrack.TimePosition) > 0.035 then
				victimTrack.TimePosition = monsterTrack.TimePosition
			end
		end))
	end

	safetyThread = task.delay(config.SafetyTimeout, function()
		cleanup("safety timeout")
	end)

	task.spawn(function()
		local ok, err = pcall(function()
			local target = monsterRoot.CFrame * config.VictimOffset
			alignTween = TweenService:Create(
				victimRoot,
				TweenInfo.new(config.AlignDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = target }
			)
			alignTween:Play()
			local playbackState = alignTween.Completed:Wait()
			alignTween = nil
			if finished or playbackState ~= Enum.PlaybackState.Completed then
				return
			end

			victimRoot.CFrame = monsterRoot.CFrame * config.VictimOffset
			victimRoot.Anchored = false
			weld = Instance.new("WeldConstraint")
			weld.Name = "GrabWeld"
			weld.Part0 = monsterRoot
			weld.Part1 = victimRoot
			weld.Parent = monsterRoot

			monsterCharacter:SetAttribute("GrabState", "Playing")
			victimCharacter:SetAttribute("GrabState", "Playing")
			monsterCharacter:SetAttribute("GrabAnimationStartedAt", Workspace:GetServerTimeNow())
			victimCharacter:SetAttribute("GrabAnimationStartedAt", Workspace:GetServerTimeNow())
			monsterTrack:Play(config.AnimationFadeTime)
			if victimTrack then
				victimTrack:Play(config.AnimationFadeTime)
			end
		end)
		if not ok then
			warn("[GrabSession] falha ao iniciar Grab: " .. tostring(err))
			cleanup("start error")
		end
	end)

	return {
		Cancel = function(_self: any, reason: string?)
			cleanup(reason or "cancelled")
		end,
	}, nil
end

return GrabSession
