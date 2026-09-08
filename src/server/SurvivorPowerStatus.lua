--!strict
-- Shared combat/status API. No dependency on RoundManager or DamageSystem.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Remotes = require(game:GetService("ReplicatedStorage").Modules.Remotes)
local Status = {}
Status.BeforeStun = Instance.new("BindableEvent")
local timed: { [Model]: { [string]: { endsAt: number, previous: any, value: any } } } = {}
local stuns: { [Model]: any } = {}
local initialized = false
local rng = Random.new()

function Status.Active(character: Model?, name: string): boolean
	local entries = character and timed[character]
	local entry = entries and entries[name]
	return entry ~= nil and entry.endsAt > Workspace:GetServerTimeNow()
end

function Status.Set(character: Model, name: string, value: any, duration: number)
	local entries = timed[character]
	if not entries then entries = {}; timed[character] = entries end
	local old = entries[name]
	entries[name] = { endsAt = Workspace:GetServerTimeNow() + duration,
		previous = if old then old.previous else character:GetAttribute(name), value = value }
	character:SetAttribute(name, value)
end

function Status.Clear(character: Model, name: string)
	local entries = timed[character]
	local entry = entries and entries[name]
	if not entry then return end
	entries[name] = nil
	if character:GetAttribute(name) == entry.value then character:SetAttribute(name, entry.previous) end
	if next(entries) == nil then timed[character] = nil end
end

function Status.Emit(id: string, character: Model?, position: Vector3, duration: number?, phase: string?)
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude <= 180 then
			Remotes.SurvivorPowerFX:FireClient(player, id, character, position, duration or 0.7, phase or "Activate")
		end
	end
end

local function endStun(character: Model)
	local state = stuns[character]
	if not state then return end
	stuns[character] = nil
	Status.Clear(character, "PowerStunned")
	if state.humanoid.Parent then
		if state.humanoid.WalkSpeed == 0 then state.humanoid.WalkSpeed = state.speed end
		state.humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, state.jumpEnabled)
	end
	if state.root.Parent and state.root:CanSetNetworkOwnership() and state.root:GetNetworkOwner() == nil then
		if state.auto then state.root:SetNetworkOwnershipAuto() else state.root:SetNetworkOwner(state.owner) end
	end
end

function Status.Stun(character: Model, duration: number): boolean
	if Status.Active(character, "PowerStunImmune") or character:GetAttribute("Imune") == true
		or character:GetAttribute("Invulneravel") == true or character:GetAttribute("ShadowRushBusy") == true
		or character:GetAttribute("TeleportBusy") == true then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart")
		or root.Anchored or not root:CanSetNetworkOwnership() then return false end
	Status.BeforeStun:Fire(character) -- release a movement power's ownership before taking it
	if not stuns[character] then
		stuns[character] = { humanoid = humanoid, root = root, speed = humanoid.WalkSpeed,
			jumpEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
			auto = root:GetNetworkOwnershipAuto(), owner = root:GetNetworkOwner() }
		root:SetNetworkOwner(nil)
	end
	local entries = timed[character]
	local old = entries and entries.PowerStunned
	Status.Set(character, "PowerStunned", true, math.max(duration, if old then old.endsAt - Workspace:GetServerTimeNow() else 0))
	humanoid.WalkSpeed = 0
	humanoid.Jump = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	return true
end

-- Consume on a validated attack, including a miss; never on an invalid request.
function Status.BeginAttack(player: Player): boolean
	local character = player.Character
	if not character or not Status.Active(character, "PowerPreciseShot") then return false end
	Status.Clear(character, "PowerPreciseShot")
	return true
end

-- Returns whether the entire attack was negated (damage AND secondary effects).
function Status.BlockAttack(character: Model): boolean
	if character:GetAttribute("Imune") == true or character:GetAttribute("Invulneravel") == true
		or character:FindFirstChildOfClass("ForceField") then return true end
	if Status.Active(character, "PowerLuckyDodge") then
		Status.Clear(character, "PowerLuckyDodge")
		if rng:NextNumber() < 0.5 then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then Status.Emit("GolpeDeSorte", character, root.Position, 0.8, "Dodge") end
			return true
		end
	end
	return false
end

function Status.Reset(character: Model)
	endStun(character)
	local entries = timed[character]
	if entries then
		for name in table.clone(entries) do Status.Clear(character, name) end
	end
end

function Status.Init()
	if initialized then return end
	initialized = true
	RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for character, entries in timed do
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not character.Parent or not humanoid or humanoid.Health <= 0 then Status.Reset(character); continue end
			for name, entry in entries do
				if now >= entry.endsAt then
					if name == "PowerStunned" then endStun(character) else Status.Clear(character, name) end
				end
			end
		end
		for character, state in stuns do
			if Status.Active(character, "PowerStunImmune") then endStun(character); continue end
			state.humanoid.WalkSpeed = 0
			state.humanoid.Jump = false
			local v = state.root.AssemblyLinearVelocity
			state.root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		end
	end)
end

return Status
