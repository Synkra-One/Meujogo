--!strict
-- Server authority for Monster Grab requests, cooldowns and active sessions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local Elimination = require(script.Parent.Elimination)
local RoundManager = require(script.Parent.RoundManager)
local GrabSession = require(script.Parent.GrabSession)
local GrabTargeting = require(script.Parent.GrabTargeting)

local GrabService = {}
local CFG = GameConfig.Monster.Grab

local activeByPlayer: { [Player]: any } = {}
local cooldowns: { [Player]: number } = {}
local requests: { [Player]: number } = {}
local initialized = false

local function reject(player: Player, reason: string)
	Remotes.MonsterGrab:FireClient(player, "Rejected", reason)
end

local function livingMonster(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart")
		or root.Anchored or humanoid.Sit or humanoid.PlatformStand or character:FindFirstChild("Ragdoll")
		or character:GetAttribute("Eliminado") == true or Elimination.IsEliminated(player) then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function canStart(player: Player, character: Model): (boolean, string?)
	if not RoundManager.IsRoundActive() or player:GetAttribute("InRound") ~= true then
		return false, "A partida nao esta ativa."
	end
	if player:GetAttribute("Role") ~= GameConfig.Roles.Monster then
		return false, "Apenas o Monstro pode usar Grab."
	end
	if player:GetAttribute("Amarrado") == true or character:GetAttribute("Amarrado") == true
		or character:GetAttribute("PowerStunned") == true then
		return false, "O Monstro esta impedido de agir."
	end
	if character:GetAttribute("TeleportBusy") == true or character:GetAttribute("ShadowRushBusy") == true
		or character:GetAttribute("GrabLocked") == true or activeByPlayer[player] then
		return false, "Outra acao esta em andamento."
	end
	if os.clock() < (cooldowns[player] or 0) then
		return false, "Grab em cooldown."
	end
	return true, nil
end

local function reserveCooldown(player: Player)
	cooldowns[player] = os.clock() + CFG.GrabCooldown
	player:SetAttribute("GrabReadyAt", Workspace:GetServerTimeNow() + CFG.GrabCooldown)
end

local function registerSession(monster: Player, victim: Player?, session: any)
	activeByPlayer[monster] = session
	if victim then
		activeByPlayer[victim] = session
	end
end

local function clearSession(monster: Player, victim: Player?, expected: any)
	if activeByPlayer[monster] == expected then
		activeByPlayer[monster] = nil
	end
	if victim and activeByPlayer[victim] == expected then
		activeByPlayer[victim] = nil
	end
end

local function onRequest(player: Player)
	local now = os.clock()
	if now - (requests[player] or -math.huge) < 0.12 then
		return
	end
	requests[player] = now

	local character, humanoid, root = livingMonster(player)
	if not character or not humanoid or not root then
		return
	end
	local allowed, reason = canStart(player, character)
	if not allowed then
		if reason then
			reject(player, reason)
		end
		return
	end

	local target = GrabTargeting.FindBest(player, character, root, CFG)
	local session: any = nil
	local finishedBeforeRegistration = false
	local function onFinished()
		if session then
			clearSession(player, if target then target.player else nil, session)
		else
			finishedBeforeRegistration = true
		end
	end

	if target then
		local failure: string?
		session, failure = GrabSession.StartGrab(
			player,
			character,
			humanoid,
			root,
			target.player,
			target.character,
			target.humanoid,
			target.root,
			CFG,
			onFinished
		)
		if not session then
			warn("[GrabService] Grab recusado: " .. tostring(failure))
			reject(player, failure or "Nao foi possivel carregar a animacao Grab.")
			return
		end
		registerSession(player, target.player, session)
	else
		session = GrabSession.StartAttempt(player, character, humanoid, CFG, onFinished)
		registerSession(player, nil, session)
	end

	if finishedBeforeRegistration then
		clearSession(player, if target then target.player else nil, session)
	end
	reserveCooldown(player)
end

local function cancelPlayerSession(player: Player, reason: string)
	local session = activeByPlayer[player]
	if session then
		session:Cancel(reason)
	end
end

local function cancelAll(reason: string)
	local seen: { [any]: true } = {}
	for _, session in activeByPlayer do
		if not seen[session] then
			seen[session] = true
			session:Cancel(reason)
		end
	end
	table.clear(activeByPlayer)
end

function GrabService.Init()
	if initialized then
		return
	end
	initialized = true

	assert(CFG.GrabRange > 0 and CFG.GrabAngle > 0 and CFG.GrabAngle < 180
		and CFG.GrabCooldown >= 0 and CFG.AlignDuration >= 0 and CFG.SafetyTimeout > 0,
		"GrabService: configuracao invalida")

	Remotes.MonsterGrab.OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player)
		cancelPlayerSession(player, "player left")
		activeByPlayer[player] = nil
		cooldowns[player] = nil
		requests[player] = nil
	end)
	RoundManager.RoundEnded.Event:Connect(function()
		cancelAll("round ended")
		table.clear(cooldowns)
	end)
	RoundManager.RoundPrepared.Event:Connect(function()
		cancelAll("round prepared")
		table.clear(cooldowns)
		for _, player in Players:GetPlayers() do
			player:SetAttribute("GrabReadyAt", 0)
		end
	end)
end

return GrabService
