--!strict
--[[
	Autoridade de ataques dos Sobreviventes. O cliente pede somente o inicio do
	golpe (Tool + variante); o servidor abre a hitbox na janela configurada,
	amostra GetPartBoundsInBox varias vezes e encaminha o dano confirmado para
	DamageSystem.Apply. Pistola e sinalizador preservam seus fluxos proprios.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Rules = require(ReplicatedStorage.Modules.CombatRules)
local CombatConfig = require(ReplicatedStorage.Modules.WeaponCombatConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local DamageSystem = require(script.Parent.DamageSystem)
local PowerStatus = require(script.Parent.SurvivorPowerStatus)

local WeaponSystem = {}
WeaponSystem.NoiseMade = Instance.new("BindableEvent")
WeaponSystem.SignalFired = Instance.new("BindableEvent")

type AttackState = {
	id: number, player: Player, tool: Tool, baseDefinition: Rules.WeaponDefinition, definition: Rules.WeaponDefinition, profile: CombatConfig.Profile,
	startedAt: number, hitStartAt: number, hitEndAt: number, endsAt: number, lastSampleAt: number,
	hitTargets: { [Model]: boolean },
}

local readyAt: { [Player]: number } = {}
local activeAttacks: { [Player]: AttackState } = {}
local nextAttackId = 0
local initialized = false

local function debugLog(message: string)
	if CombatConfig.Debug.Enabled and CombatConfig.Debug.VerboseRejections then warn("[WeaponCombat] " .. message) end
end

function WeaponSystem.IsReady(player: Player): boolean
	return Rules.IsReady(os.clock(), readyAt[player])
end

function WeaponSystem.UseCooldown(player: Player, duration: number): boolean
	if not WeaponSystem.IsReady(player) then return false end
	readyAt[player] = os.clock() + duration
	return true
end

function WeaponSystem.Equip(player: Player, tool: Tool): boolean
	if not Rules.CanAttack(player) or not Rules.Definition(tool) then return false end
	local character = player.Character :: Model
	if tool.Parent ~= character and tool.Parent ~= player:FindFirstChildOfClass("Backpack") then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	humanoid:EquipTool(tool)
	return tool.Parent == character
end

function WeaponSystem.ValidateAttack(player: Player, candidate: unknown): (Tool?, Rules.WeaponDefinition?)
	local definition = Rules.Definition(candidate)
	if not definition or definition.Kind == "Firearm" or not Rules.CanAttack(player) then
		debugLog(string.format("%s rejeitado: arma/estado invalido", player.Name)); return nil, nil
	end
	if activeAttacks[player] then debugLog(string.format("%s rejeitado: ataque ainda ativo", player.Name)); return nil, nil end
	if not WeaponSystem.IsReady(player) then debugLog(string.format("%s rejeitado: cooldown", player.Name)); return nil, nil end
	local tool = candidate :: Tool
	if tool.Parent ~= player.Character or not tool.Enabled then
		debugLog(string.format("%s rejeitado: Tool nao equipada", player.Name)); return nil, nil
	end
	return tool, definition
end

local function rayParams(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType, params.FilterDescendantsInstances, params.IgnoreWater = Enum.RaycastFilterType.Exclude, { character }, true
	return params
end

local function overlapParams(character: Model): OverlapParams
	local params = OverlapParams.new()
	params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { character }
	params.RespectCanCollide, params.MaxParts = false, 32
	return params
end

local function attackSound(tool: Tool)
	local handle = tool:FindFirstChild("Handle")
	local sound = handle and handle:FindFirstChild("AttackSound")
	if sound and sound:IsA("Sound") and sound.SoundId ~= "" then sound:Play() end
end

local function showDebugBox(cframe: CFrame, size: Vector3, label: string)
	if not CombatConfig.Debug.Enabled then return end
	local box = Instance.new("Part")
	box.Name, box.Size, box.CFrame = "DebugMeleeHitbox_" .. label, size, cframe
	box.Anchored, box.CanCollide, box.CanTouch, box.CanQuery = true, false, false, false
	box.Material, box.Color, box.Transparency = Enum.Material.ForceField, Color3.fromRGB(80, 210, 255), 0.72
	box.Parent = Workspace
	Debris:AddItem(box, CombatConfig.Debug.DrawLifetime)
end

local function finishAttack(state: AttackState, reason: string)
	if activeAttacks[state.player] ~= state then return end
	activeAttacks[state.player] = nil
	local character = state.player.Character
	if character and character:GetAttribute("WeaponAttackId") == state.id then
		character:SetAttribute("WeaponAttackId", nil)
		character:SetAttribute("WeaponAttackActive", nil)
	end
	if CombatConfig.Debug.Enabled then print(string.format("[WeaponCombat] ataque %d de %s terminou: %s", state.id, state.player.Name, reason)) end
end

local function validDuringAttack(state: AttackState): (Model?, BasePart?)
	local player, tool = state.player, state.tool
	if not Rules.CanAttack(player) then return nil, nil end
	local character = player.Character
	if not character or tool.Parent ~= character or not tool.Enabled then return nil, nil end
	-- Perfil Heavy e uma copia de balanceamento; a identidade da Tool deve ser
	-- comparada com a definicao base, senao um golpe pesado seria cancelado no
	-- primeiro Heartbeat por nao ser a mesma tabela.
	if Rules.Definition(tool) ~= state.baseDefinition then return nil, nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return nil, nil end
	return character, root
end

local function eligibleMonster(attacker: Player, model: Model): boolean
	local target = Players:GetPlayerFromCharacter(model)
	return target ~= nil and target ~= attacker and target:GetAttribute("Role") == GameConfig.Roles.Monster
		and target:GetAttribute("InRound") == true and target:GetAttribute("Eliminado") ~= true
		and target:GetAttribute("InWaitingRoom") ~= true and DamageSystem.IsDamageable(model)
end

local function lineOfSight(character: Model, origin: Vector3, targetPart: BasePart, target: Model): boolean
	local offset = targetPart.Position - origin
	if offset.Magnitude < 0.05 then return true end
	local hit = Workspace:Raycast(origin, offset, rayParams(character))
	return not hit or hit.Instance:IsDescendantOf(target)
end

local function selectTarget(state: AttackState, character: Model, root: BasePart, cframe: CFrame): (Model?, BasePart?)
	local parts = Workspace:GetPartBoundsInBox(cframe, state.profile.HitboxSize, overlapParams(character))
	local selectedModel: Model? = nil
	local selectedPart: BasePart? = nil
	local bestDistance = math.huge
	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not state.hitTargets[model] and eligibleMonster(state.player, model) then
			local targetRoot = model:FindFirstChild("HumanoidRootPart")
			if targetRoot and targetRoot:IsA("BasePart") then
				local offset, distance = targetRoot.Position - root.Position, (targetRoot.Position - root.Position).Magnitude
				local front = if distance > 0.05 then offset.Unit:Dot(root.CFrame.LookVector) else 1
				if distance <= state.profile.MaxTargetDistance and front >= state.profile.MinimumForwardDot
					and lineOfSight(character, root.Position, part, model) and distance < bestDistance then
					selectedModel, selectedPart, bestDistance = model, part, distance
				end
			end
		end
	end
	return selectedModel, selectedPart
end

local function profileKey(profile: CombatConfig.Profile): string
	if profile.WeaponId == "PedraAfiada" then return "Wrench" end
	if profile.WeaponId == "LancaDeBambu" then return "Crowbar" end
	return "BaseballBat"
end

local function applyMeleeHit(state: AttackState, character: Model, root: BasePart, cframe: CFrame)
	showDebugBox(cframe, state.profile.HitboxSize, tostring(state.id))
	local target, hitPart = selectTarget(state, character, root, cframe)
	if not target or not hitPart then return end
	state.hitTargets[target] = true -- tambem quando DamageSystem bloqueia: nunca repete no mesmo golpe.
	local applied, _, blocked = DamageSystem.Apply(target, state.definition.Damage, {
		Source = state.player, Cause = state.definition.DisplayName, FixedDamage = true,
	})
	if applied <= 0 or blocked then
		if CombatConfig.Debug.Enabled then print(string.format("[WeaponCombat] %s acertou %s, bloqueado", state.player.Name, target.Name)) end
		return
	end
	local stunned = state.definition.StunDuration ~= nil and state.definition.StunDuration > 0
	if stunned then PowerStatus.Stun(target, state.definition.StunDuration :: number) end
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if state.definition.PushForce and state.definition.PushForce > 0 and targetRoot and targetRoot:IsA("BasePart")
		and not targetRoot.Anchored and not PowerStatus.Active(target, "PowerStunImmune") then
		local direction = targetRoot.Position - root.Position
		if direction.Magnitude < 0.05 then direction = root.CFrame.LookVector end
		targetRoot.AssemblyLinearVelocity += direction.Unit * state.definition.PushForce + Vector3.new(0, 2, 0)
	end
	Remotes.WeaponImpact:FireAllClients(state.player, profileKey(state.profile), hitPart.Position, stunned)
	if CombatConfig.Debug.Enabled then print(string.format("[WeaponCombat] ataque %d acertou %s em %s", state.id, target.Name, hitPart.Name)) end
end

local function startMeleeAttack(player: Player, tool: Tool, baseDefinition: Rules.WeaponDefinition, definition: Rules.WeaponDefinition, variant: unknown): boolean
	local profile = CombatConfig.ForTool(tool, variant)
	if not profile then debugLog(string.format("%s rejeitado: Tool melee sem perfil", player.Name)); return false end
	if not WeaponSystem.UseCooldown(player, definition.Cooldown) then return false end
	nextAttackId += 1
	local now = os.clock()
	local state: AttackState = {
		id = nextAttackId, player = player, tool = tool, baseDefinition = baseDefinition, definition = definition, profile = profile,
		startedAt = now, hitStartAt = now + profile.HitStart, hitEndAt = now + profile.HitEnd,
		endsAt = now + profile.AttackEnd, lastSampleAt = 0, hitTargets = {},
	}
	activeAttacks[player] = state
	local character = player.Character
	if character then character:SetAttribute("WeaponAttackId", state.id); character:SetAttribute("WeaponAttackActive", true) end
	attackSound(tool)
	task.delay(profile.AttackEnd + 0.1, function() finishAttack(state, "fim da janela") end)
	return true
end

function WeaponSystem.Attack(player: Player, candidate: unknown, variant: unknown?): boolean
	local tool, baseDefinition = WeaponSystem.ValidateAttack(player, candidate)
	if not tool or not baseDefinition then return false end
	local definition = Rules.Profile(baseDefinition, variant)
	local character = player.Character :: Model
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return false end
	if definition.Kind == "Signal" then
		if not WeaponSystem.UseCooldown(player, definition.Cooldown) then return false end
		attackSound(tool)
		local direction = root.CFrame.LookVector * definition.Range
		local hit = Workspace:Raycast(root.Position, direction, rayParams(character))
		local position = if hit then hit.Position else root.Position + direction
		local flash = Instance.new("Part")
		flash.Name, flash.Shape, flash.Size = "SignalImpact", Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5)
		flash.Material, flash.Color = Enum.Material.Neon, Color3.fromRGB(255, 100, 45)
		flash.Anchored, flash.CanCollide, flash.CanTouch, flash.CanQuery = true, false, false, false
		flash.Position, flash.Parent = position, Workspace
		Debris:AddItem(flash, 0.25)
		WeaponSystem.SignalFired:Fire(player, position)
		return true
	end
	if definition.Kind ~= "Melee" then return false end
	return startMeleeAttack(player, tool, baseDefinition, definition, variant)
end

function WeaponSystem.Init()
	if initialized then return end
	initialized = true
	Remotes.WeaponAttack.OnServerEvent:Connect(WeaponSystem.Attack)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, state in activeAttacks do
			if now > state.endsAt then finishAttack(state, "tempo esgotado"); continue end
			if now < state.hitStartAt or now > state.hitEndAt or now - state.lastSampleAt < CombatConfig.SampleInterval then continue end
			state.lastSampleAt = now
			local character, root = validDuringAttack(state)
			if not character or not root then finishAttack(state, "estado/equipamento mudou"); continue end
			applyMeleeHit(state, character, root, root.CFrame * CFrame.new(0, 0, -state.profile.ForwardOffset))
		end
	end)
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			readyAt[player] = nil
			local active = activeAttacks[player]
			if active then finishAttack(active, "personagem trocado") end
		end)
	end
	for _, player in Players:GetPlayers() do watchPlayer(player) end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
		local active = activeAttacks[player]
		if active then finishAttack(active, "jogador saiu") end
	end)
end

return WeaponSystem
