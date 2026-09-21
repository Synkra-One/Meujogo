--!strict
--[[
	Locomoção exclusiva do Monster. Só assume quando Idle/Walk/Run foram
	preenchidos em MonsterAnimationConfig; até lá o Animate existente continua
	a ser o fallback do jogo. Não cria joints nem toca em C0/C1.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Config = require(ReplicatedStorage.Modules.MonsterAnimationConfig)

local player = Players.LocalPlayer
local character: Model? = nil
local humanoid: Humanoid? = nil
local tracks: { [string]: AnimationTrack } = {}
local currentName: string? = nil
local runningConnection: RBXScriptConnection? = nil
local savedAnimate: LocalScript? = nil
local savedAnimateDisabled: boolean? = nil

local function clearTracks()
	for _, track in tracks do
		pcall(function() track:Stop(Config.Locomotion.FadeTime); track:Destroy() end)
	end
	table.clear(tracks)
	currentName = nil
end

local function restoreAnimate()
	if savedAnimate and savedAnimate.Parent and savedAnimateDisabled ~= nil then
		savedAnimate.Disabled = savedAnimateDisabled
	end
	savedAnimate, savedAnimateDisabled = nil, nil
end

local function hasCompleteLocomotion(): boolean
	return Config.IsUsableAnimationId(Config.AnimationIds.Idle)
		and Config.IsUsableAnimationId(Config.AnimationIds.Walk)
		and Config.IsUsableAnimationId(Config.AnimationIds.Run)
end

local function play(name: string)
	if currentName == name then return end
	local nextTrack = tracks[name]
	if not nextTrack then return end
	for otherName, track in tracks do
		if otherName ~= name and track.IsPlaying then track:Stop(Config.Locomotion.FadeTime) end
	end
	nextTrack:Play(Config.Locomotion.FadeTime)
	currentName = name
end

local function update(speed: number)
	if not humanoid or humanoid.Health <= 0 then return end
	if speed < Config.Locomotion.WalkSpeed then
		play("Idle")
	elseif speed < Config.Locomotion.RunSpeed then
		play("Walk")
	else
		play("Run")
	end
end

local function detach()
	if runningConnection then runningConnection:Disconnect(); runningConnection = nil end
	clearTracks()
	restoreAnimate()
	humanoid, character = nil, nil
end

local function attach(char: Model)
	detach()
	character = char
	if player:GetAttribute("Role") ~= GameConfig.Roles.Monster then return end
	local found = char:FindFirstChildOfClass("Humanoid")
	if not found or found.RigType ~= Enum.HumanoidRigType.R6 then return end
	local animator = found:FindFirstChildOfClass("Animator")
	if not animator then animator = Instance.new("Animator"); animator.Parent = found end
	humanoid = found
	if not hasCompleteLocomotion() then return end

	for _, name in { "Idle", "Walk", "Run" } do
		local animation = Instance.new("Animation")
		animation.Name = "Monster" .. name
		animation.AnimationId = (Config.AnimationIds :: { [string]: string })[name]
		local ok, result = pcall(function() return animator:LoadAnimation(animation) end)
		animation:Destroy()
		if not ok or not result then
			warn("[MonsterAnimationRig] Não foi possível carregar " .. name .. ".")
			clearTracks()
			return
		end
		local track = result :: AnimationTrack
		track.Looped = true
		track.Priority = if name == "Idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
		tracks[name] = track
	end

	-- Evita misturar poses R6 padrão com as poses publicadas pelo rig do Monster.
	local animate = char:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		savedAnimate, savedAnimateDisabled = animate, animate.Disabled
		animate.Disabled = true
	end
	runningConnection = found.Running:Connect(update)
	update(found.MoveDirection.Magnitude * found.WalkSpeed)
	refreshTestBinding()
end

local function refresh()
	if player.Character then attach(player.Character) else detach() end
end

player.CharacterAdded:Connect(attach)
player:GetAttributeChangedSignal("Role"):Connect(function()
	refresh()
end)
if player.Character then attach(player.Character) end
