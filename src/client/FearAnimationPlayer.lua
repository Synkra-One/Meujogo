--!strict
-- Camada opcional R6. Só toca nossos tracks; nunca para tracks de outro sistema.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.GameConfig)
local Rules = require(ReplicatedStorage.Modules.FearPresentationRules)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)
local CFG = Config.Fear
local FearAnimationPlayer = {}

local function important(track: AnimationTrack): boolean
	-- Core tem valor numérico 1000, mas é a MENOR prioridade: não compare Value.
	local p = track.Priority
	return p == Enum.AnimationPriority.Action or p == Enum.AnimationPriority.Action2
		or p == Enum.AnimationPriority.Action3 or p == Enum.AnimationPriority.Action4
end

function FearAnimationPlayer.new(player: Player, character: Model)
	local controller = { CurrentName = "None" }
	local animator: Animator? = nil
	local connections: { RBXScriptConnection } = {}
	local tracks: { [string]: { id: string, animation: Animation, track: AnimationTrack?, failed: boolean, loadedAt: number } } = {}
	local owned: { [AnimationTrack]: boolean } = {}
	local now, onceUntil, lookCheck, lookCooldown = 0, 0, 0, 0
	local rng = Random.new()
	local destroyed = false
	local interacting = false

	local function stop(fade: number?)
		controller.CurrentName = "None"
		onceUntil = 0
		for track in owned do
			if track.IsPlaying then track:Stop(fade or 0) end
		end
	end

	local function ready(): (Humanoid?, BasePart?)
		local h = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not h or not root or not root:IsA("BasePart") then return nil, nil end
		local found = h:FindFirstChildOfClass("Animator")
		if not animator and found then
			animator = found
			table.insert(connections, found.AnimationPlayed:Connect(function(track)
				if not owned[track] and important(track) then stop(0) end
			end))
		end
		return h, root
	end

	local function blocked(h: Humanoid, root: BasePart): boolean
		if interacting or h.Health <= 0 or h.Sit or h.FloorMaterial == Enum.Material.Air or h.FloorMaterial == Enum.Material.Water
			or root.Anchored or character:GetAttribute("FirearmAiming") == true
			or player:GetAttribute("Amarrado") == true or player:GetAttribute("CursorLivre") == true
			or root:GetAttribute("IsCrouching") or root:GetAttribute("IsCrawling") or root:GetAttribute("CrawlLock")
			or character:FindFirstChildOfClass("Tool") then return true end
		local movement = h:GetState()
		if movement ~= Enum.HumanoidStateType.Running and movement ~= Enum.HumanoidStateType.RunningNoPhysics then return true end
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				if not owned[track] and important(track) then return true end
			end
		end
		return false
	end

	local function loadTrack(name: string): AnimationTrack?
		if not animator then return nil end
		local id = Rules.AssetId((CFG.FearAnimations :: any)[name])
		local record = tracks[name]
		if record and record.id ~= id then
			if record.track then
				owned[record.track] = nil
				record.track:Stop(0); record.track:Destroy()
			end
			record.animation:Destroy()
			tracks[name] = nil
			record = nil
		end
		if not id then return nil end
		if not record then
			local animation = Instance.new("Animation")
			animation.Name, animation.AnimationId = name, id
			local ok, result = pcall(function() return (animator :: Animator):LoadAnimation(animation) end)
			record = { id = id, animation = animation, track = if ok then result else nil, failed = not ok, loadedAt = now }
			tracks[name] = record
			if record.track then
				record.track.Priority = Enum.AnimationPriority.Action
				record.track.Looped = name == "FearIdle" or name == "FearWalk" or name == "FearRun"
				owned[record.track] = true
			elseif CFG.DebugMode then warn("[FearPresentation] Não carregou animação " .. name) end
		end
		if record.track and record.track.Length == 0 and now - record.loadedAt > CFG.FearAnimationLoadTimeout then
			record.failed = true
			record.track:Stop(0)
		end
		return if record.failed then nil else record.track
	end

	local function play(name: string): boolean
		local track = loadTrack(name)
		if not track then stop(CFG.FearAnimationFadeTime); return false end
		if controller.CurrentName == name then return true end
		stop(CFG.FearAnimationFadeTime)
		controller.CurrentName = name
		track:Play(CFG.FearAnimationFadeTime)
		return true
	end

	function controller.PlayTrip(duration: number)
		if destroyed then return end
		local h, root = ready()
		if not h or not root or blocked(h, root) then return end
		if play("Trip") then onceUntil = now + math.min(duration, CFG.TripDuration) end
	end

	function controller.Step(fear: number, dt: number)
		if destroyed then return end
		now += dt
		local h, root = ready()
		if not h or not root or blocked(h, root) then stop(0); lookCheck = 0; return end
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local running = speed > StatScaling.WalkSpeed(player) * Config.Characters.SprintSpeedRatio
		if controller.CurrentName == "Trip" then
			if now < onceUntil then return end
			stop(CFG.FearAnimationFadeTime)
		end
		if character:GetAttribute("FearTripping") == true then stop(0); return end
		if controller.CurrentName == "LookAround" then
			if now < onceUntil and not running and fear >= CFG.LookAroundMinFear then return end
			stop(CFG.FearAnimationFadeTime)
		end
		if fear >= CFG.LookAroundMinFear and not running and now >= lookCooldown
			and Rules.AssetId(CFG.FearAnimations.LookAround) then
			lookCheck += dt
			if lookCheck >= CFG.LookAroundCheckInterval then
				lookCheck = 0
				if rng:NextNumber() < CFG.LookAroundChance and play("LookAround") then
					onceUntil = now + CFG.LookAroundMaxDuration
					lookCooldown = now + CFG.LookAroundCooldown
					return
				end
			end
		else lookCheck = 0 end
		if fear < CFG.FearLocomotionStart then stop(CFG.FearAnimationFadeTime); return end
		play(if speed <= CFG.FearIdleSpeedThreshold then "FearIdle" elseif running then "FearRun" else "FearWalk")
	end

	function controller.Reset()
		stop(0); lookCheck = 0; lookCooldown = 0; interacting = false
	end
	function controller.SetInteracting(value: boolean)
		interacting = value
		if value then stop(0); lookCheck = 0 end
	end
	function controller.Destroy()
		if destroyed then return end
		destroyed = true
		stop(0)
		for _, connection in connections do connection:Disconnect() end
		for _, record in tracks do
			if record.track then record.track:Destroy() end
			record.animation:Destroy()
		end
		table.clear(tracks); table.clear(owned); table.clear(connections)
	end
	table.insert(connections, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then stop(0) end
	end))
	ready()
	return controller
end

return FearAnimationPlayer
