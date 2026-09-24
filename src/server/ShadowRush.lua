--!strict
-- Server owns phases/eligibility and validates movement. Native character physics
-- keeps steering, gravity and collisions; the ability never anchors the body.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PowerStatus = require(script.Parent.SurvivorPowerStatus)
local FlashlightRules = require(ReplicatedStorage.Modules.FlashlightRules)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Modules.GameConfig)
local Rules = require(ReplicatedStorage.Modules.ShadowRushRules)
local FearSystem = require(script.Parent.FearSystem)
local Elimination = require(script.Parent.Elimination)
local RoundManager = require(script.Parent.RoundManager)
local Weakness = require(script.Parent.MonsterLightWeakness)
local Layout = require(script.Parent.Tools.IslandLayout)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local CFG = Config.Monster.ShadowRush
local ShadowRush = {}

type Session = {
	player: Player, character: Model, humanoid: Humanoid, root: BasePart,
	token: number, state: string, phaseAt: number, startedAt: number,
	position: Vector3, safeFrame: CFrame, distanceBudget: number,
	baseSpeed: number, exitSpeed: number, ray: RaycastParams,
	origWalkSpeed: number, origJumpPower: number, origJumpHeight: number,
	connections: { RBXScriptConnection }, passAt: { [Player]: number },
}
local sessions: { [Player]: Session } = {}
local cooldowns: { [Player]: number } = {}
local requestAt: { [Player]: number } = {}
local serial, initialized = 0, false

local function stop(s: Session, _reason: string)
	if sessions[s.player] ~= s then return end
	sessions[s.player] = nil
	for _, connection in s.connections do connection:Disconnect() end
	if s.humanoid.Parent and not Elimination.IsEliminated(s.player) then
		s.humanoid.WalkSpeed = s.origWalkSpeed
		s.humanoid.JumpPower, s.humanoid.JumpHeight = s.origJumpPower, s.origJumpHeight
	end
	if s.character.Parent then
		s.character:SetAttribute("ShadowRushState", "Idle")
		s.character:SetAttribute("ShadowRushBusy", nil)
		s.character:SetAttribute("ShadowRushBaseSpeed", nil)
		s.character:SetAttribute("ShadowRushExitSpeed", nil)
		s.character:SetAttribute("ShadowRushExitHidden", nil)
	end
end

local function phase(s: Session, state: string)
	local now = os.clock()
	if state == "Materializing" then
		s.exitSpeed = Rules.Speed(s.state, now - s.phaseAt, s.baseSpeed, s.exitSpeed, CFG)
		s.character:SetAttribute("ShadowRushExitSpeed", s.exitSpeed)
		s.character:SetAttribute("ShadowRushExitHidden", Rules.Hidden(s.state, now - s.phaseAt, 1, CFG))
	end
	s.state, s.phaseAt = state, now
	s.character:SetAttribute("ShadowRushPhaseAt", Workspace:GetServerTimeNow())
	s.character:SetAttribute("ShadowRushState", state)
end

local function refreshFilters(s: Session)
	local ignore: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then table.insert(ignore, p.Character) end
	end
	s.ray.FilterDescendantsInstances = ignore
	s.ray.CollisionGroup = s.root.CollisionGroup
end

local function shadowPass(s: Session, before: Vector3, now: number)
	if (s.position - before).Magnitude < 0.02 then return end
	for _, p in Players:GetPlayers() do
		if p == s.player or p:GetAttribute("Role") ~= Config.Roles.Survivor
			or p:GetAttribute("InRound") ~= true or Elimination.IsEliminated(p)
			or now < (s.passAt[p] or 0) then continue end
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not hum or hum.Health <= 0 then continue end
		if Rules.SegmentDistance(root.Position, before, s.position) > CFG.ShadowPassDistance then continue end
		local offset = root.Position - s.position
		if offset.Magnitude > 0.01 and Workspace:Raycast(s.position, offset, s.ray) then continue end
		s.passAt[p] = now + CFG.ShadowPassCooldown
		FearSystem.AddFear(p, CFG.ShadowPassFear, "ShadowRush")
		Remotes.ShadowRush:FireClient(p, "Pass")
	end
end

local function valid(s: Session): boolean
	return s.player.Character == s.character and s.character:IsDescendantOf(Workspace)
		and s.root:IsDescendantOf(s.character) and s.humanoid.Health > 0
		and not s.root.Anchored and not s.humanoid.PlatformStand
		and not Elimination.IsEliminated(s.player) and RoundManager.IsRoundActive()
		and s.player:GetAttribute("Role") == Config.Roles.Monster
		and s.player:GetAttribute("InRound") == true
		and not FlashlightRules.PowerBlocked(s.character)
		and s.character:GetAttribute("TeleportBusy") ~= true
		and s.character:GetAttribute("GrabLocked") ~= true
		and not s.character:FindFirstChild("Ragdoll") and not s.humanoid.Sit
end

local function validateMovement(s: Session, dt: number): boolean
	local position = s.root.Position
	local delta = position - s.position
	local speedLimit = CFG.ShadowRushMaxSpeed * CFG.ValidationSpeedMargin
	-- Tolerate batched physics replication, not sustained extra speed.
	s.distanceBudget = math.min(speedLimit * CFG.ReplicationSlack, s.distanceBudget + speedLimit * dt)
	local distance = delta.Magnitude
	local finite = position.X == position.X and position.Y == position.Y and position.Z == position.Z
	local rejected = not finite or distance > s.distanceBudget
		or not Rules.InBounds(position, Layout.CONFIG.AreaHalf, CFG.BoundsMargin + CFG.CollisionRadius)
	if not rejected and distance > 0.05 then
		-- A root segment catches wall tunneling without a full-height box that
		-- scrapes the ground. Native body collision handles width and sliding.
		rejected = Workspace:Raycast(s.position, delta, s.ray) ~= nil
	end
	if rejected then
		s.root.CFrame = s.safeFrame
		s.root.AssemblyLinearVelocity = Vector3.zero
		return false
	end
	s.distanceBudget -= distance
	s.position, s.safeFrame = position, s.root.CFrame
	return true
end

local function tickSession(s: Session, dt: number)
	local now = os.clock()
	if not valid(s) or now - s.startedAt > CFG.ShadowRushSafetyTimeout then stop(s, "interrupted"); return end
	refreshFilters(s)
	local before = s.position
	if not validateMovement(s, dt) then stop(s, "invalid movement"); return end
	local elapsed = now - s.phaseAt
	if s.state == "EnteringShadow" then
		if elapsed >= CFG.ShadowRushEnterDuration then phase(s, "ShadowRush") end
	elseif s.state == "ShadowRush" then
		if elapsed >= CFG.ShadowRushDuration or Weakness.IsWeakened(s.character)
			or s.humanoid:GetState() == Enum.HumanoidStateType.Swimming then
			phase(s, "Materializing")
		else shadowPass(s, before, now) end
	elseif s.state == "Materializing" then
		if elapsed >= CFG.ShadowRushMaterializeDuration then phase(s, "Recovery") end
	elseif s.state == "Recovery" and elapsed >= CFG.ShadowRushRecovery then
		stop(s, "complete"); return
	end
	s.humanoid.WalkSpeed = Rules.Speed(s.state, now - s.phaseAt, s.baseSpeed, s.exitSpeed, CFG)
	s.humanoid.JumpPower, s.humanoid.JumpHeight, s.humanoid.Jump = 0, 0, false
end

local function start(player: Player)
	if FlashlightRules.PowerBlocked(player.Character) then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not RoundManager.IsRoundActive() or player:GetAttribute("Role") ~= Config.Roles.Monster
		or player:GetAttribute("InRound") ~= true or Elimination.IsEliminated(player)
		or not char or not hum or hum.Health <= 0
		or not root or not root:IsA("BasePart") then return end
	if char:GetAttribute("TeleportBusy") or char:GetAttribute("ShadowRushBusy") or char:GetAttribute("GrabLocked")
		or root.Anchored or hum.Sit or hum.PlatformStand or char:FindFirstChild("Ragdoll")
		or root:GetAttribute("IsCrouching") or root:GetAttribute("IsCrawling") or root:GetAttribute("CrawlLock")
		or Weakness.IsWeakened(char) or os.clock() < (cooldowns[player] or 0) then return end
	local ray = RaycastParams.new()
	ray.FilterType, ray.RespectCanCollide, ray.IgnoreWater = Enum.RaycastFilterType.Exclude, true, false
	serial += 1
	local s: Session = {
		player = player, character = char, humanoid = hum, root = root,
		token = serial, state = "Idle", phaseAt = os.clock(), startedAt = os.clock(),
		position = root.Position, safeFrame = root.CFrame,
		distanceBudget = CFG.ShadowRushMaxSpeed * CFG.ValidationSpeedMargin * CFG.ReplicationSlack,
		baseSpeed = Config.Characters.ReferenceWalkSpeed
			* (char:GetAttribute("MonsterSpeedMul") or Config.Monster.SpeedMultiplier)
			* (char:GetAttribute("SpeedMul") or 1),
		exitSpeed = hum.WalkSpeed, ray = ray, connections = {}, passAt = {},
		origWalkSpeed = hum.WalkSpeed, origJumpPower = hum.JumpPower, origJumpHeight = hum.JumpHeight,
	}
	refreshFilters(s)
	local leg = char:FindFirstChild("Left Leg")
	local height = hum.HipHeight + root.Size.Y / 2
	if hum.RigType == Enum.HumanoidRigType.R6 and leg and leg:IsA("BasePart") then height += leg.Size.Y end
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -height - 1, 0), ray)
	if not hit or hit.Material == Enum.Material.Water or hit.Normal.Y < CFG.MinGroundNormalY
		or not Rules.InBounds(root.Position, Layout.CONFIG.AreaHalf, CFG.BoundsMargin + CFG.CollisionRadius) then
		Remotes.ShadowRush:FireClient(player, "Rejected", "Precisa de chão firme."); return
	end
	sessions[player] = s
	cooldowns[player] = os.clock() + CFG.ShadowRushCooldown
	player:SetAttribute("ShadowRushReadyAt", Workspace:GetServerTimeNow() + CFG.ShadowRushCooldown)
	char:SetAttribute("ShadowRushToken", serial)
	char:SetAttribute("ShadowRushBaseSpeed", s.baseSpeed)
	phase(s, "EnteringShadow")
	char:SetAttribute("ShadowRushBusy", true)
	hum.JumpPower, hum.JumpHeight, hum.Jump = 0, 0, false
	hum:UnequipTools()
	table.insert(s.connections, char.ChildAdded:Connect(function(d)
		if d:IsA("Tool") then hum:UnequipTools() end
	end))
	table.insert(s.connections, hum.Died:Connect(function() stop(s, "death") end))
	table.insert(s.connections, player.CharacterRemoving:Connect(function() stop(s, "respawn") end))
end

function ShadowRush.Cancel(player: Player)
	local s = sessions[player]
	if s then stop(s, "external cancel") end
end

function ShadowRush.Init()
	if initialized then return end
	initialized = true
	PowerStatus.RegisterStunInterruptor(function(character)
		local owner = Players:GetPlayerFromCharacter(character)
		if owner then ShadowRush.Cancel(owner) end
	end)
	assert(CFG.ShadowRushMaxSpeed > 0 and CFG.ShadowRushMaxSpeed <= 150
		and CFG.ShadowRushAcceleration > 0 and CFG.ShadowRushEnterDuration > 0
		and CFG.ShadowRushExitDeceleration > 0 and CFG.ServerInterval > 0
		and CFG.ShadowRushMaterializeDuration >= CFG.ShadowRushExitDeceleration,
		"ShadowRush: configuração de movimento inválida")
	Remotes.ShadowRush.OnServerEvent:Connect(function(player, action, token)
		if action ~= "Start" and action ~= "Stop" then return end
		local now, s = os.clock(), sessions[player]
		if now - (requestAt[player] or -math.huge) < 0.1 then return end
		requestAt[player] = now
		if action == "Stop" and s and token == s.token then
			if s.state == "ShadowRush" or s.state == "EnteringShadow" then phase(s, "Materializing") end
		elseif action == "Start" and not s then
			local ok, err = pcall(start, player)
			if not ok then ShadowRush.Cancel(player); warn("[ShadowRush] Start: " .. tostring(err)) end
		end
	end)
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < CFG.ServerInterval then return end
		local stepDt = accumulated
		accumulated = 0
		for _, s in sessions do
			local ok, err = pcall(tickSession, s, stepDt)
			if not ok then stop(s, "error"); warn("[ShadowRush] Tick: " .. tostring(err)) end
		end
	end)
	local function reset()
		for _, s in sessions do stop(s, "round end") end
		table.clear(cooldowns); table.clear(requestAt)
		for _, player in Players:GetPlayers() do player:SetAttribute("ShadowRushReadyAt", nil) end
	end
	RoundManager.RoundEnded.Event:Connect(reset)
	RoundManager.RoundPrepared.Event:Connect(reset)
	Players.PlayerRemoving:Connect(function(player)
		ShadowRush.Cancel(player)
		cooldowns[player], requestAt[player] = nil, nil
	end)
end

return ShadowRush
