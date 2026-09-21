local config = loadModule("GameConfig")
env.os.time = function() return clock end
local rules = loadModule("FlashlightRules")
local players = { PlayerRemoving = signal(), PlayerAdded = signal(), list = {} }
function players:GetPlayers() return self.list end
function players:GetPlayerFromCharacter(character)
	for _, player in self.list do if player.Character == character then return player end end
end
services.Players = players
services.RunService = { Heartbeat = signal() }
services.TweenService, services.InsertService = {}, {}
env.task = { spawn = function() end } -- Asset preloading/teleport coroutine excluded.
local round = { IsRoundActive = function() return true end,
	RoundEnded = { Event = signal() }, RoundPrepared = { Event = signal() } }
modules.RoundManager = round
modules.Elimination = { IsEliminated = function() return false end }
modules.MonsterLightWeakness = { IsWeakened = function() return false end }
modules.FearSystem, modules.AssetRegistry = {}, {}
modules.IslandLayout = { CONFIG = { AreaHalf = 1000 } }
names.Tools = { IslandLayout = "IslandLayout" }
local interrupts = {}
modules.SurvivorPowerStatus = { RegisterStunInterruptor = function(callback) table.insert(interrupts, callback) end }
modules.DamageSystem = { Apply = function() error("blocked attack applied damage") end }
local grabStarts, grabCancels = 0, 0
modules.GrabTargeting = { FindBest = function() return nil end }
modules.GrabSession = { StartAttempt = function(_, character, _, _, finish)
	grabStarts += 1
	character:SetAttribute("GrabLocked", true)
	return { Cancel = function()
		grabCancels += 1; character:SetAttribute("GrabLocked", nil); finish()
	end }
end }
local remotes = {}
for _, name in { "ShadowRush", "MonsterTeleport", "MonsterAttack", "MonsterGrab" } do
	remotes[name] = { OnServerEvent = signal(), sent = {} }
	remotes[name].FireClient = function(self, player, ...)
		table.insert(self.sent, { player, ... })
	end
end
modules.Remotes = remotes
local monster = object("Player")
monster.UserId, monster.Parent = 10, players
monster.Character = child(world, "Model", "Monster")
monster:SetAttribute("Role", config.Roles.Monster); monster:SetAttribute("InRound", true)
players.list = { monster }
local c = monster.Character
local h, root = child(c, "Humanoid", "Humanoid"), child(c, "Part", "HumanoidRootPart")
h.Health, h.WalkSpeed, h.JumpPower, h.JumpHeight, h.HipHeight = 100, 19, 50, 7.2, 0
function h:UnequipTools() end
function h:GetState() return "Running" end
root.CFrame, root.Size, root.AssemblyLinearVelocity = cf(0, 3, 0), v(2, 2, 1), zero
root.CFrame.RightVector, root.CFrame.UpVector = v(1, 0, 0), v(0, 1, 0)
function root:FindFirstAncestorOfClass() return nil end
function c:GetScale() return 1 end
function world:Raycast() return nil end
local rush = loadModule("ShadowRush")
local teleport = loadModule("MonsterTeleport")
local combat = loadModule("MonsterCombat")
local grab = loadModule("GrabService")
for _, system in { rush, teleport, combat, grab } do system.Init(); system.Init() end
for _, remote in remotes do assert(#remote.OnServerEvent.list == 1, "one listener per existing remote") end
assert(#interrupts == 3, "one cleanup registration per movement power")
for _, flag in { "PowerStunned", "FlashPowerBlocked" } do
	c:SetAttribute(flag, true)
	local beforeGrab, beforeAttack, beforeTeleport, beforeRush = grabStarts,
		#remotes.MonsterAttack.sent, #remotes.MonsterTeleport.sent, #remotes.ShadowRush.sent
	clock += 1
	remotes.ShadowRush.OnServerEvent:Fire(monster, "Start")
	remotes.MonsterTeleport.OnServerEvent:Fire(monster, nil)
	remotes.MonsterAttack.OnServerEvent:Fire(monster)
	remotes.MonsterGrab.OnServerEvent:Fire(monster)
	assert(grabStarts == beforeGrab and #remotes.MonsterAttack.sent == beforeAttack)
	assert(#remotes.MonsterTeleport.sent == beforeTeleport and #remotes.ShadowRush.sent == beforeRush)
	assert(not c:GetAttribute("ShadowRushBusy"), "server denies forged F request")
	c:SetAttribute(flag, nil)
end
clock += 1
remotes.ShadowRush.OnServerEvent:Fire(monster, "Start")
assert(remotes.ShadowRush.sent[#remotes.ShadowRush.sent][2] == "Rejected", "unblocked F reaches ground validation again")
remotes.MonsterTeleport.OnServerEvent:Fire(monster, nil)
assert(#remotes.MonsterTeleport.sent == 2, "unblocked teleport validates destination and replies")
remotes.MonsterAttack.OnServerEvent:Fire(monster)
assert(remotes.MonsterAttack.sent[#remotes.MonsterAttack.sent][2] == "confirm", "attack restores")
remotes.MonsterGrab.OnServerEvent:Fire(monster)
assert(grabStarts == 1)
for _, interrupt in interrupts do interrupt(c) end
assert(grabCancels == 1 and not c:GetAttribute("GrabLocked"), "active grab uses existing cancellation")

-- Actually start F, then synchronously interrupt its real session.
local ground = object("Part")
function world:Raycast() return { Instance = ground, Position = zero, Normal = v(0, 1, 0), Material = "Ground" } end
clock += 1
remotes.ShadowRush.OnServerEvent:Fire(monster, "Start")
assert(c:GetAttribute("ShadowRushBusy") and h.JumpPower == 0)
local ready = monster:GetAttribute("ShadowRushReadyAt")
for _, interrupt in interrupts do interrupt(c) end
assert(not c:GetAttribute("ShadowRushBusy") and h.WalkSpeed == 19 and h.JumpPower == 50,
	"interrupt restores original motion before flash stun")
assert(monster:GetAttribute("ShadowRushReadyAt") == ready, "interrupt preserves F cooldown")
clock += 1
remotes.ShadowRush.OnServerEvent:Fire(monster, "Start")
assert(not c:GetAttribute("ShadowRushBusy"), "stun cleanup cannot refund F cooldown")
assert(#logs == 0, "no hidden errors: " .. tostring(logs[1]))
print("PASS: real server F/teleport/grab/attack gates, input restoration, no duplicate listeners, active F/grab cleanup and cooldown preservation")
