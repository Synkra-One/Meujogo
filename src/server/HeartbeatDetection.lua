--!strict
-- Audição contínua do Fear existente. Não recebe pedidos nem valores do cliente.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CFG = require(ReplicatedStorage.Modules.HeartbeatConfig)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Rules = require(ReplicatedStorage.Modules.HeartbeatRules)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local FearSystem = require(script.Parent.FearSystem)
local NoiseService = require(script.Parent.NoiseService)
local RoundManager = require(script.Parent.RoundManager)
local Asset = require(script.Parent.HeartbeatAsset)
local Detection = {}
local initialized = false
local listeners: { [Player]: Model } = {}

local function rootFor(player: Player, role: string): BasePart?
	if player:GetAttribute("CharacterSelectOpen") == true then return nil end
	local root = NoiseService.GetActiveRoot(player, role)
	if not root or not root.Parent or not root.Parent.Parent then return nil end
	return root
end

local function clear()
	for player, character in listeners do
		if player.Parent == Players then Remotes.HeartbeatDetected:FireClient(player, character, {}) end
	end
	-- Survivors receive only their own heartbeat stream. Clear it explicitly
	-- when the round ends or the detector is disabled.
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == GameConfig.Roles.Survivor
			and player.Parent == Players
			and player.Character then
			Remotes.HeartbeatDetected:FireClient(player, player.Character, {})
		end
	end
	table.clear(listeners)
end

local function step()
	if not CFG.Enabled or not RoundManager.IsRoundActive() then clear(); return end
	local monsters, survivors = {}, {}
	local survivorHeartbeats = {}
	for _, player in Players:GetPlayers() do
		local monster = rootFor(player, GameConfig.Roles.Monster)
		if monster then monsters[player] = monster end
		local root = rootFor(player, GameConfig.Roles.Survivor)
		if root and root.Parent:GetAttribute("PowerFearHidden") ~= true then
			local fear = FearSystem.GetFear(player) -- tabela privada, nunca Player.Fear
			if fear > CFG.MinFear then
				local humanoid = root.Parent:FindFirstChildOfClass("Humanoid") :: Humanoid
				local v = root.AssemblyLinearVelocity
				local speed = if root.Anchored or humanoid.Sit then 0 else Vector3.new(v.X, 0, v.Z).Magnitude
				local target = { player = player, root = root, fear = fear,
					movement = StatScaling.NoiseState(speed, StatScaling.WalkSpeed(player)),
					injury = 1 - humanoid.Health / math.max(1, humanoid.MaxHealth),
					stealth = StatScaling.Lerp(StatScaling.Of(player, "Furtividade"), CFG.StealthMultiplier) }
				table.insert(survivors, target)
				-- The survivor hears their own heartbeat locally. It is evaluated
				-- from fear and personal modifiers, without exposing any other
				-- survivor or private fear value to the client.
				local selfStrength, selfBPM, selfTension = Rules.Evaluate(
					target.fear, GameConfig.Fear.MaxFear, 0, target.movement,
					target.injury, target.stealth, false, CFG)
				if selfStrength > 0 then
					survivorHeartbeats[player] = {
						player = player, character = root.Parent,
						strength = selfStrength, bpm = selfBPM, tension = selfTension,
					}
				end
			end
		end
	end
	for player, character in listeners do
		if not monsters[player] then
			if player.Parent == Players then Remotes.HeartbeatDetected:FireClient(player, character, {}) end
			listeners[player] = nil
		end
	end
	for monster, monsterRoot in monsters do
		local snapshot = {}
		for _, target in survivors do
			local delta = target.root.Position - monsterRoot.Position
			local distance = delta.Magnitude
			if distance >= CFG.MaxRange then continue end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { monsterRoot.Parent, target.root.Parent }
			params.RespectCanCollide, params.IgnoreWater = true, true
			local blocked = distance > 0 and Workspace:Raycast(monsterRoot.Position, delta, params) ~= nil
			local strength, bpm, tension = Rules.Evaluate(target.fear, GameConfig.Fear.MaxFear, distance,
				target.movement, target.injury, target.stealth, blocked, CFG)
			if strength > 0 then
				table.insert(snapshot, { player = target.player, character = target.root.Parent,
					strength = strength, bpm = bpm, tension = tension })
			end
		end
		listeners[monster] = monsterRoot.Parent :: Model
		Remotes.HeartbeatDetected:FireClient(monster, monsterRoot.Parent, snapshot)
	end
	for survivor, entry in survivorHeartbeats do
		if survivor.Parent == Players and survivor.Character == entry.character then
			Remotes.HeartbeatDetected:FireClient(survivor, entry.character, { entry })
		end
	end
end

function Detection.Init()
	if initialized then return end
	assert(RunService:IsServer(), "HeartbeatDetection é exclusivo do servidor")
	assert(CFG.MinFear >= 0 and CFG.MinFear < GameConfig.Fear.MaxFear and CFG.MaxRange > 0)
	assert(CFG.UpdateInterval > 0 and CFG.SnapshotTimeout > CFG.UpdateInterval)
	assert(CFG.FadeIn > 0 and CFG.FadeOut > 0 and CFG.MinBPM > 0 and CFG.MaxBPM >= CFG.MinBPM)
	assert(CFG.MinPulseDuty > 0 and CFG.MaxPulseDuty < 1 and CFG.MinPulseDuty <= CFG.MaxPulseDuty)
	assert(CFG.AudioCycleDuration > 0 and CFG.AudioCycleDuration <= 60 / CFG.AudioReferenceBPM)
	initialized = true
	task.spawn(Asset.Init) -- falha/carregamento lento não bloqueia a partida
	RoundManager.RoundPrepared.Event:Connect(clear)
	RoundManager.RoundEnded.Event:Connect(clear)
	Players.PlayerRemoving:Connect(function(player) listeners[player] = nil end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CFG.UpdateInterval then return end
		elapsed = 0 -- sem rajada de raycasts depois de um frame lento
		step()
	end)
end

return Detection
