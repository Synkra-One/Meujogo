-- Injected into flashlight.luau before DamageSystem doubles are replaced.
-- Real FlashlightSystem/Targeting/Rules/SurvivorPowerStatus, simulated players.
local status = loadModule("SurvivorPowerStatus")
local sequences = {}
local function fire(owner, tool, aim, sequence)
	advance(0.16, false)
	sequences[owner] = (sequences[owner] or 0) + 1
	remote.OnServerEvent:Fire(owner, "Burst", tool, nil, aim or direction, sequence or sequences[owner])
end
local function prepare()
	system.Reset()
	status.Reset(monster.Character)
	system.Recharge(a, 100); system.Recharge(b, 100)
	wallZ, muzzleBlocked = nil, false
	for _, key in { "Head", "Torso", "HumanoidRootPart" } do
		monster.Character:FindFirstChild(key).Position = V.new(0, 2, -12)
	end
end
prepare()
local monsterHum = monster.Character:FindFirstChildOfClass("Humanoid")
local monsterRoot = monster.Character:FindFirstChild("HumanoidRootPart")
monsterRoot:SetNetworkOwner(monster)
local originalSpeed = monsterHum.WalkSpeed
fire(alice, a)
near(a:GetAttribute("Battery"), 75, "exact burst battery cost")
assert(not a:GetAttribute("FlashlightOn"), "burst works without switching normal light on")
assert(monster.Character:GetAttribute("FlashStunned") and rules.PowerBlocked(monster.Character))
assert(monsterHum.WalkSpeed == 0 and monsterRoot:GetNetworkOwner() == nil and not monsterHum:GetStateEnabled("Jumping"))
assert(monster.Character:GetAttribute("FlashBurstBlindUntil") > now)
assert(not alice.Character:GetAttribute("FlashBurstBlindUntil") and not bob.Character:GetAttribute("FlashBurstBlindUntil"),
	"survivors never receive private whiteout/tinnitus state")
local ack = remote.events[#remote.events]
assert(ack[1] == alice and ack[2] == "BurstResult" and ack[4] and ack[5] == "Hit", "hit response only to shooter")
local consumed, rayBefore = a:GetAttribute("Battery"), rayCalls
for _ = 1, 1000 do remote.OnServerEvent:Fire(alice, "Burst", a, nil, direction, 999) end
near(a:GetAttribute("Battery"), consumed, "spam does not consume again")
assert(rayCalls == rayBefore, "spam performs no raycast")
fire(alice, a)
near(a:GetAttribute("Battery"), consumed, "cooldown denial")
local swapped = lamp(alice)
fire(alice, swapped)
near(swapped:GetAttribute("Battery"), 100, "new tool cannot evade player cooldown")
move(swapped, bob.Character)
fire(bob, a)
near(a:GetAttribute("Battery"), consumed, "foreign tool denied")
advance(2, false)
near(monsterHum.WalkSpeed, originalSpeed, "speed restored by existing status manager")
assert(monsterRoot:GetNetworkOwner() == monster and monsterHum:GetStateEnabled("Jumping"), "network ownership and jump restored")
assert(not monster.Character:GetAttribute("FlashStunned"))
advance(0.5, false)
assert(not rules.PowerBlocked(monster.Character), "power block expires without resetting power cooldowns")
assert(monster.Character:GetAttribute("FlashBurstBlindUntil") > now, "blind persists longer than stun")
advance(5, false)
assert(monster.Character:GetAttribute("FlashBurstBlindUntil") == nil)
local replay = sequences[alice]
fire(alice, a, direction, replay)
near(a:GetAttribute("Battery"), consumed, "same sequence cannot replay after cooldown")
print("PASS: burst hit, private victim state, cost/cooldown, bounded spam, replay and tool-swap protection, speed/jump/ownership restoration")

prepare()
wallZ = -5
fire(alice, a)
near(a:GetAttribute("Battery"), 75, "wall miss consumes charge")
assert(not rules.PowerBlocked(monster.Character), "solid wall blocks stun")
assert(remote.events[#remote.events][5] == "Miss")
prepare()
fire(alice, a, V.new(1, 0, 0))
assert(not rules.PowerBlocked(monster.Character), "off-axis miss")
near(a:GetAttribute("Battery"), 75, "off-axis miss cost")
prepare()
for _, key in { "Head", "Torso", "HumanoidRootPart" } do monster.Character:FindFirstChild(key).Position = V.new(0, 2, -50) end
fire(alice, a)
near(a:GetAttribute("Battery"), 100, "out of range rejected without cost")
assert(remote.events[#remote.events][5] == "Range")
prepare()
monster:SetAttribute("Role", "Sobrevivente")
fire(alice, a)
near(a:GetAttribute("Battery"), 100, "no survivor can be targeted")
monster:SetAttribute("Role", "Monstro")
for _, aim in { V.new(0, 0, 1), V.new(0/0, 0, -1), V.new(math.huge, 0, -1), V.new(0, 0, -900) } do
	fire(alice, a, aim)
	near(a:GetAttribute("Battery"), 100, "invalid/impossible direction rejected")
end
for _, flag in config.BlockingFlags do
	alice.Character:SetAttribute(flag, true)
	fire(alice, a)
	near(a:GetAttribute("Battery"), 100, "condition blocks burst: " .. flag)
	alice.Character:SetAttribute(flag, nil)
end
alice.Character:FindFirstChildOfClass("Humanoid").Health = 0
fire(alice, a)
near(a:GetAttribute("Battery"), 100, "dead shooter denied")
alice.Character:FindFirstChildOfClass("Humanoid").Health = 100
move(a, alice:FindFirstChild("Backpack"))
fire(alice, a)
near(a:GetAttribute("Battery"), 100, "unequipped denied")
move(a, alice.Character)
muzzle.WorldPosition = V.new(900, 2, -1)
fire(alice, a)
near(a:GetAttribute("Battery"), 100, "forged muzzle denied")
muzzle.WorldPosition = V.new(0.5, 2, -1)
alice:SetAttribute("InRound", false)
fire(alice, a)
near(a:GetAttribute("Battery"), 100, "lobby denied")
alice:SetAttribute("InRound", true)
monster.Character:SetAttribute("Invulneravel", true)
fire(alice, a)
assert(not rules.PowerBlocked(monster.Character), "existing invulnerability respected")
monster.Character:SetAttribute("Invulneravel", nil)
print("PASS: walls/misses, range, survivor exclusion, invalid vectors, forged source, every blocking flag, lobby, death and invulnerability")

prepare()
-- Cancel callbacks must complete before stun captures speed/ownership.
local interrupts = 0
status.RegisterStunInterruptor(function(character)
	interrupts += 1
	if character:GetAttribute("ShadowRushBusy") then
		character:SetAttribute("ShadowRushBusy", nil)
		monsterHum.WalkSpeed = 19
	end
end)
monster.Character:SetAttribute("ShadowRushBusy", true)
monsterHum.WalkSpeed = 90
fire(alice, a)
assert(interrupts == 1 and not monster.Character:GetAttribute("ShadowRushBusy"))
advance(0.5, false)
fire(bob, b)
assert(interrupts == 2 and monsterHum.WalkSpeed == 0)
advance(2.1, false)
near(monsterHum.WalkSpeed, 19, "repeated hit restores pre-stun speed, never zero/rush speed")
prepare()
assert(status.Stun(monster.Character, 10), "independent stun starts")
fire(alice, a)
monster.Character:SetAttribute("MonsterCombatState", "Vulneravel")
advance(0.2, false)
assert(not monster.Character:GetAttribute("FlashBurstBlindUntil"), "state change clears flash effects")
assert(monsterHum.WalkSpeed == 0 and monster.Character:GetAttribute("PowerStunned"), "cleanup preserves unrelated stun")
advance(10, false)
assert(not monster.Character:GetAttribute("PowerStunned"))
prepare()
fire(alice, a)
monsterHum.Health = 0
advance(0.2, false)
assert(not monster.Character:GetAttribute("FlashBurstBlindUntil") and not monster.Character:GetAttribute("FlashPowerBlocked"))
monsterHum.Health = 100
prepare()
fire(alice, a)
monster:SetAttribute("InRound", false)
advance(0.2, false)
assert(not monster.Character:GetAttribute("FlashPowerBlocked"), "leaving round cleans effects")
monster:SetAttribute("InRound", true)
prepare()
fire(alice, a)
monster.CharacterRemoving:Fire(monster.Character)
assert(not monster.Character:GetAttribute("FlashBurstBlindUntil"), "respawn cleanup")
prepare()
fire(alice, a)
players.PlayerRemoving:Fire(monster)
assert(not monster.Character:GetAttribute("FlashPowerBlocked"), "disconnect cleanup")
prepare()
fire(alice, a)
round.RoundEnded.Event:Fire()
assert(not monster.Character:GetAttribute("PowerStunned") and not a:GetAttribute("FlashBurstReadyAt"), "round reset cleanup")
print("PASS: synchronous power interruption, repeated hits without stacking, overlapping stuns, state/death/round/respawn/disconnect cleanup")

prepare()
for _ = 1, 4 do fire(alice, a); advance(config.FlashBurstCooldown + 0.1, false) end
near(a:GetAttribute("Battery"), 0, "four bursts exhaust battery")
local messages = #remote.events
fire(alice, a)
assert(#remote.events == messages + 1 and remote.events[#remote.events][5] == "Battery", "empty battery explicitly rejected")
assert(not a:GetAttribute("FlashlightOn"))
prepare()
toggle(alice, a, true)
advance(0.2, true)
local before = a:GetAttribute("Battery")
fire(alice, a)
assert(a:GetAttribute("FlashlightOn"), "burst preserves normal on state")
assert(a:GetAttribute("Battery") < before - config.FlashBurstCost, "normal drain and burst cost coexist")
advance(0.2, true)
assert(monster.Character:GetAttribute("FlashlightExposure") > 0, "normal light vulnerability still accumulates")
system.Reset()
print("PASS: zero/insufficient charge, normal toggle, ongoing drain and continuous light exposure preserved")
