--!strict
-- Rojo maps src/server to ServerScriptService.Server. Server owns all 14 powers.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterData = require(ReplicatedStorage.Modules.CharacterData)
local Config = require(ReplicatedStorage.Modules.GameConfig)
local Items = require(ReplicatedStorage.Modules.ItemRegistry)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Round = require(script.Parent.RoundManager)
local Elimination = require(script.Parent.Elimination)
local Damage = require(script.Parent.DamageSystem)
local Status = require(script.Parent.SurvivorPowerStatus)
local RadioSite = require(script.Parent.RadioSiteSystem)
local Raft = require(script.Parent.RaftObjective)
local System = {}
local initialized = false
local cooldowns: { [Player]: { number } } = {}
local requests: { [Player]: number } = {}
local motions: { [Player]: any } = {}
local senses: { [Player]: any } = {}
local traps: { [Part]: any } = {}
local rareItems: { [Instance]: boolean } = {}

local function living(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if player.Parent ~= Players or player:GetAttribute("InRound") ~= true
		or Elimination.IsEliminated(player) or not character or not character.Parent
		or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil, nil, nil end
	return character, humanoid, root
end

local function enemy(player: Player): boolean
	local role = player:GetAttribute("Role")
	return role == Config.Roles.Monster or role == Config.Roles.Spy
end

local function rayParams(character: Model, ignoreCharacters: boolean?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: { Instance } = { character }
	if ignoreCharacters then
		for _, player in Players:GetPlayers() do if player.Character then table.insert(ignored, player.Character) end end
	end
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true
	return params
end

local function clearLine(a: BasePart, b: BasePart): boolean
	local params = rayParams(a.Parent :: Model, true)
	return Workspace:Raycast(a.Position, b.Position - a.Position, params) == nil
end

local function forward(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

local function stopMotion(player: Player)
	local motion = motions[player]
	if not motion then return end
	motions[player] = nil
	if motion.velocity then motion.velocity:Destroy() end
	if motion.attachment then motion.attachment:Destroy() end
	Status.Clear(motion.character, "PowerMoving")
	local root = motion.root
	if root.Parent and root:CanSetNetworkOwnership() and root:GetNetworkOwner() == nil
		and not Status.Active(motion.character, "PowerStunned") then
		if motion.auto then root:SetNetworkOwnershipAuto() else root:SetNetworkOwner(motion.owner) end
	end
end

local function startMotion(player: Player, character: Model, humanoid: Humanoid, root: BasePart, id: string): boolean
	if motions[player] or humanoid.FloorMaterial == Enum.Material.Air
		or humanoid.FloorMaterial == Enum.Material.Water or not root:CanSetNetworkOwnership() then return false end
	local direction = forward(root)
	local params = rayParams(character, true)
	if Workspace:Blockcast(root.CFrame, Vector3.new(2, 3, 2), direction * 3, params) then return false end
	local jump = id == "SaltoLongo"
	local motion = { character = character, root = root, humanoid = humanoid, id = id,
		endsAt = Workspace:GetServerTimeNow() + (if jump then 2 else 0.5),
		startedAt = Workspace:GetServerTimeNow(), direction = direction, last = root.Position,
		auto = root:GetNetworkOwnershipAuto(), owner = root:GetNetworkOwner(), params = params,
		airborne = false, hit = {} }
	motions[player] = motion
	root:SetNetworkOwner(nil)
	Status.Set(character, "PowerMoving", true, if jump then 2 else 0.5)
	local attachment = Instance.new("Attachment")
	attachment.Name = "SurvivorPowerImpulse"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.ForceLimitsEnabled = false
	velocity.VectorVelocity = direction * (if jump then 48 else 56) + Vector3.new(0, if jump then 38 else 0, 0)
	velocity.Parent = root
	motion.attachment, motion.velocity = attachment, velocity
	if jump then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
	return true
end

local function teleport(character: Model, humanoid: Humanoid, root: BasePart): boolean
	local direction = forward(root)
	local params = rayParams(character)
	local size = Vector3.new(math.max(2.5, root.Size.X), 3.5, math.max(2.5, root.Size.Z))
	local hit = Workspace:Blockcast(root.CFrame, size, direction * 15, params)
	local distance = if hit then math.max(0, hit.Distance - 0.6) else 15
	if distance < 3 then return false end
	local candidate = root.Position + direction * distance
	local ground = Workspace:Raycast(candidate + Vector3.new(0, 2, 0), Vector3.new(0, -9, 0), params)
	if not ground or ground.Material == Enum.Material.Water or ground.Normal.Y < 0.65 then return false end
	local leg = character:FindFirstChild("Left Leg")
	local height = humanoid.HipHeight + root.Size.Y / 2 + (if leg and leg:IsA("BasePart") then leg.Size.Y else 0)
	local destination = ground.Position + Vector3.new(0, height + 0.15, 0)
	local cf = CFrame.lookAt(destination, destination + direction)
	-- Recheck the full path after ground adjustment, then the destination volume.
	if Workspace:Blockcast(root.CFrame, size, destination - root.Position, params) then return false end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.RespectCanCollide = true
	if #Workspace:GetPartBoundsInBox(cf, size, overlap) > 0 then return false end
	Status.Emit("PassoFantasma", nil, root.Position, 0.7, "Origin")
	character:PivotTo(cf * root.CFrame:ToObjectSpace(character:GetPivot()))
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

local function rarePosition(item: Instance): Vector3?
	if not item:IsDescendantOf(Workspace) then return nil end
	-- Never reveal an item inside a character/inventory, even when equipped.
	local parent = item.Parent
	while parent and parent ~= Workspace do
		if parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then return nil end
		parent = parent.Parent
	end
	if item:IsA("BasePart") then return item.Position end
	if item:IsA("Tool") then
		local handle = item:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then return handle.Position end
	end
	return nil
end

local function senseTarget(id: string, root: BasePart): Vector3?
	local closest, best = nil, math.huge
	if id == "InstintoDeCacadora" then
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Role") == Config.Roles.Monster then
				local _, _, target = living(player)
				if target then
					local distance = (target.Position - root.Position).Magnitude
					if distance < best then closest, best = target.Position, distance end
				end
			end
		end
	else
		for item in rareItems do
			local position = rarePosition(item)
			if position then
				local distance = (position - root.Position).Magnitude
				if distance < best then closest, best = position, distance end
			end
		end
	end
	return closest
end

local durations = { RajadaFinal = 5, MantoDeSombras = 8, TiroCerteiro = 8,
	InstintoDeCacadora = 4, IntuicaoSortuda = 6, EscudoProtetor = 4,
	PosturaInabalavel = 5, GolpeDeSorte = 10 }

local function activate(player: Player, character: Model, humanoid: Humanoid, root: BasePart, id: string): (boolean, string?)
	if id == "RajadaFinal" then
		Status.Set(character, "PowerSpeedMultiplier", 2, 5)
		Status.Set(character, "PowerInfiniteStamina", true, 5)
	elseif id == "SaltoLongo" or id == "InvestidaBrutal" then
		if not startMotion(player, character, humanoid, root, id) then return false, "Precisa de chão firme e espaço à frente." end
	elseif id == "PassoFantasma" then
		if not teleport(character, humanoid, root) then return false, "Não há um destino seguro à frente." end
	elseif id == "ConsertoRelampago" then
		local target = RadioSite.ApplyPowerRepair(player) or Raft.ApplyPowerRepair(player)
		if not target then return false, "Interaja com o rádio após coletar as 3 peças, ou entre na área da jangada." end
		Status.Emit(id, nil, target.Position, 1)
	elseif id == "ArmadilhaImprovisada" then
		local ground = Workspace:Raycast(root.Position, Vector3.new(0, -7, 0), rayParams(character))
		if not ground or ground.Normal.Y < 0.65 or ground.Material == Enum.Material.Water then return false, "Precisa de chão firme." end
		local trap = Instance.new("Part")
		trap.Name = "ArmadilhaImprovisada"
		trap.Size = Vector3.new(5, 1, 5)
		trap.Position = ground.Position + Vector3.new(0, 0.5, 0)
		trap.Anchored, trap.CanCollide, trap.CanQuery, trap.CanTouch = true, false, false, true
		trap.Transparency = 1
		trap.Parent = Workspace
		traps[trap] = { owner = player, character = character, endsAt = Workspace:GetServerTimeNow() + 60 }
	elseif id == "TiroCerteiro" then
		Status.Set(character, "PowerPreciseShot", true, 8)
	elseif id == "MantoDeSombras" then
		Status.Set(character, "PowerFearHidden", true, 8)
	elseif id == "InstintoDeCacadora" or id == "IntuicaoSortuda" then
		if not senseTarget(id, root) then return false, if id == "IntuicaoSortuda" then "Nenhum item raro disponível na ilha." else "Nenhum monstro ativo." end
		senses[player] = { id = id, character = character, endsAt = Workspace:GetServerTimeNow() + durations[id] }
	elseif id == "AdrenalinaDeEmergencia" then
		local healed = false
		for _, ally in Players:GetPlayers() do
			local model, health, allyRoot = living(ally)
			if ally:GetAttribute("Role") == Config.Roles.Survivor and model and health and allyRoot
				and (allyRoot.Position - root.Position).Magnitude <= 15 then
				if Damage.Heal(model, health.MaxHealth * 0.5) > 0 then
					healed = true
					Status.Emit(id, model, allyRoot.Position, 1.5)
				end
			end
		end
		if not healed then return false, "Você e os aliados próximos já estão com a vida cheia." end
		return true, nil
	elseif id == "EscudoProtetor" then
		local target, targetRoot, best = character, root, 10
		for _, ally in Players:GetPlayers() do
			local model, _, allyRoot = living(ally)
			if ally ~= player and ally:GetAttribute("Role") == Config.Roles.Survivor and model and allyRoot then
				local distance = (allyRoot.Position - root.Position).Magnitude
				if distance <= best and clearLine(root, allyRoot) then target, targetRoot, best = model, allyRoot, distance end
			end
		end
		Status.Set(target, "Imune", true, 4)
		Status.Emit(id, target, targetRoot.Position, 4)
		return true, nil
	elseif id == "PosturaInabalavel" then
		Status.Set(character, "PowerStunImmune", true, 5)
		Status.Set(character, "PowerDamageReduction", 0.5, 5)
	elseif id == "GolpeDeSorte" then
		Status.Set(character, "PowerLuckyDodge", true, 10)
	else return false, "Poder não cadastrado." end
	Status.Emit(id, character, root.Position, durations[id] or 0.8)
	return true, nil
end

local function onRequest(player: Player, slot: unknown)
	if slot ~= 1 and slot ~= 2 then return end
	local now = Workspace:GetServerTimeNow()
	if now - (requests[player] or -math.huge) < 0.15 then return end
	requests[player] = now
	local character, humanoid, root = living(player)
	if not Round.IsRoundActive() or player:GetAttribute("Role") ~= Config.Roles.Survivor
		or player:GetAttribute("CharacterSelectOpen") == true or not character or not humanoid or not root then return end
	if player:GetAttribute("Amarrado") == true or character:GetAttribute("Amarrado") == true
		or character:GetAttribute("PowerStunned") == true or character:GetAttribute("PowerMoving") == true
		or character:GetAttribute("FearTripping") == true or character:GetAttribute("TeleportBusy") == true
		or character:GetAttribute("ShadowRushBusy") == true or character:GetAttribute("GrabLocked") == true
		or humanoid.Sit or humanoid.PlatformStand
		or root.Anchored or character:FindFirstChild("Ragdoll") then
		Remotes.UseSurvivorPower:FireClient(player, "Rejected", "Você não pode usar poderes neste estado.")
		return
	end
	local data = CharacterData.GetById(player:GetAttribute("CharacterId"))
	if not data then return end
	local id = if slot == 1 then data.PowerId1 else data.PowerId2
	local cooldown = if slot == 1 then data.PowerCooldown1 else data.PowerCooldown2
	if not id or not cooldown then return end
	local ready = cooldowns[player] or { 0, 0 }
	cooldowns[player] = ready
	if now < ready[slot :: number] then return end
	local success, reason = activate(player, character, humanoid, root, id)
	if not success then Remotes.UseSurvivorPower:FireClient(player, "Rejected", reason); return end
	ready[slot :: number] = now + cooldown
	player:SetAttribute("SurvivorPowerReadyAt" .. tostring(slot), ready[slot :: number])
end

local function clearPlayer(player: Player, character: Model?)
	stopMotion(player)
	senses[player] = nil
	if character then Status.Reset(character) end
	for trap, state in traps do
		if state.owner == player then traps[trap] = nil; trap:Destroy() end
	end
end

local function resetAll()
	for _, player in Players:GetPlayers() do
		clearPlayer(player, player.Character)
		player:SetAttribute("SurvivorPowerReadyAt1", 0)
		player:SetAttribute("SurvivorPowerReadyAt2", 0)
	end
	table.clear(cooldowns)
	table.clear(requests)
end

function System.Init()
	if initialized then return end
	initialized = true
	Status.Init()
	Status.BeforeStun.Event:Connect(function(character)
		local player = Players:GetPlayerFromCharacter(character)
		if player then stopMotion(player) end
	end)
	local function indexRare(item: Instance)
		if not item:IsA("BasePart") and not item:IsA("Tool") then return end
		for id, def in Items.Items do
			if (def.Rarity == "Rara" or id == "LancaAncestral") and
				(item.Name == id or item.Name == def.DisplayName or (def.AttributeName and item:GetAttribute(def.AttributeName) == true)) then
				rareItems[item] = true; break
			end
		end
	end
	for _, item in Workspace:GetDescendants() do indexRare(item) end
	Workspace.DescendantAdded:Connect(function(item) task.defer(indexRare, item) end)
	Workspace.DescendantRemoving:Connect(function(item) rareItems[item] = nil end)
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function(character) clearPlayer(player, character) end)
		for _, name in { "Role", "CharacterId", "InRound", "Eliminado" } do
			player:GetAttributeChangedSignal(name):Connect(function() clearPlayer(player, player.Character) end)
		end
	end
	for _, player in Players:GetPlayers() do watch(player) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		clearPlayer(player, player.Character); cooldowns[player] = nil; requests[player] = nil
	end)
	Round.RoundPrepared.Event:Connect(resetAll)
	Round.RoundEnded.Event:Connect(resetAll)
	Remotes.UseSurvivorPower.OnServerEvent:Connect(onRequest)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = Workspace:GetServerTimeNow()
		for player, motion in motions do
			local character, humanoid, root = living(player)
			if character ~= motion.character or not humanoid or not root or not Round.IsRoundActive()
				or character:GetAttribute("PowerStunned") == true or root.Anchored then stopMotion(player); continue end
			local jump = motion.id == "SaltoLongo"
			if jump and now - motion.startedAt > 0.18 and motion.velocity then
				motion.velocity:Destroy(); motion.velocity = nil
			end
			if humanoid.FloorMaterial == Enum.Material.Air then motion.airborne = true end
			local landed = jump and motion.airborne and humanoid.FloorMaterial ~= Enum.Material.Air
			local delta = root.Position - motion.last
			local probe = delta + motion.direction * 1.2
			local wall = Workspace:Blockcast(CFrame.new(motion.last), Vector3.new(2, 2, 2), probe, motion.params)
			if not jump then
				for _, target in Players:GetPlayers() do
					local model, _, targetRoot = living(target)
					if enemy(target) and model and targetRoot and not motion.hit[target] then
						local length = delta:Dot(delta)
						local t = if length > 0 then math.clamp((targetRoot.Position - motion.last):Dot(delta) / length, 0, 1) else 0
						if (targetRoot.Position - (motion.last + delta * t)).Magnitude <= 3.5 and clearLine(root, targetRoot) then
							motion.hit[target] = true
							if Status.Stun(model, 3) then Status.Emit(motion.id, model, targetRoot.Position, 0.7, "Impact") end
						end
					end
				end
			end
			motion.last = root.Position
			if wall or landed or now >= motion.endsAt then
				if landed or not jump then Status.Emit(motion.id, character, root.Position, 0.7, "Impact") end
				if wall then root.AssemblyLinearVelocity = Vector3.new(0, math.min(0, root.AssemblyLinearVelocity.Y), 0) end
				stopMotion(player)
			end
		end
		elapsed += dt
		if elapsed < 0.1 then return end
		elapsed = 0
		for trap, state in traps do
			local character = living(state.owner)
			if not trap.Parent or now >= state.endsAt or character ~= state.character or not Round.IsRoundActive() then
				traps[trap] = nil; trap:Destroy(); continue
			end
			-- Server overlap of the trigger volume; cannot be forged via Touched.
			for _, target in Players:GetPlayers() do
				local model, _, root = living(target)
				if enemy(target) and model and root then
					local p = trap.CFrame:PointToObjectSpace(root.Position)
					if math.abs(p.X) <= 3.2 and math.abs(p.Z) <= 3.2 and p.Y >= -1 and p.Y <= 4
						and Workspace:Raycast(trap.Position + Vector3.new(0, 1, 0), root.Position - trap.Position - Vector3.new(0, 1, 0), rayParams(model, true)) == nil then
						Status.Stun(model, 3)
						Status.Emit("ArmadilhaImprovisada", model, trap.Position, 0.8, "Impact")
						traps[trap] = nil; trap:Destroy(); break
					end
				end
			end
		end
		for player, sense in senses do
			local character, _, root = living(player)
			if now >= sense.endsAt or character ~= sense.character or not root then senses[player] = nil; continue end
			local target = senseTarget(sense.id, root)
			local direction = Vector3.zero
			if target and (target - root.Position).Magnitude > 0.01 then
				direction = root.CFrame:VectorToObjectSpace((target - root.Position).Unit)
			end
			-- Direction ONLY: no target instance, distance, or world position in the packet.
			Remotes.UseSurvivorPower:FireClient(player, "Direction", sense.id, direction, sense.endsAt)
		end
	end)
end

return System
