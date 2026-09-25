-- Matrix math only; engine scheduling, rendering and asset permissions need Studio.
local env = setmetatable({}, { __index = getfenv() })
local stub = assert(loadstring(sources.RobloxStub))
setfenv(stub, env)
stub()
local V, CF = env.Vector3, env.CFrame
V.xAxis, V.yAxis, V.zAxis = V.new(1, 0, 0), V.new(0, 1, 0), V.new(0, 0, 1)
local mt = getmetatable(CF.identity)
local originalIndex = mt.__index
mt.__index = function(self, key)
	if key == "Rotation" then return self - self.Position end
	return originalIndex(self, key)
end
function mt:VectorToWorldSpace(v) return self * v - self.Position end
function mt:Inverse()
	local r = self.R
	local rotation = CF.fromMatrix(V.zero, V.new(r[1], r[2], r[3]),
		V.new(r[4], r[5], r[6]), V.new(r[7], r[8], r[9]))
	return rotation + rotation:VectorToWorldSpace(-self.Position)
end
function mt:VectorToObjectSpace(v) return self:Inverse():VectorToWorldSpace(v) end
function mt:ToObjectSpace(cf) return self:Inverse() * cf end
function CF.fromAxisAngle(axis, angle)
	local function rotate(v)
		return v * math.cos(angle) + axis:Cross(v) * math.sin(angle)
			+ axis * axis:Dot(v) * (1 - math.cos(angle))
	end
	return CF.fromMatrix(V.zero, rotate(V.xAxis), rotate(V.yAxis), rotate(V.zAxis))
end
function mt:Lerp(other, alpha)
	if alpha <= 0 then return self end
	if alpha >= 1 then return other end
	local delta = self:Inverse() * other
	local r = delta.R
	local angle = math.acos(math.clamp((r[1] + r[5] + r[9] - 1) / 2, -1, 1))
	local axis = V.new(r[8] - r[6], r[3] - r[7], r[4] - r[2])
	local rotation = CF.identity
	if axis.Magnitude > 1e-8 then rotation = CF.fromAxisAngle(axis.Unit, angle * alpha) end
	return self.Rotation * rotation + self.Position * (1 - alpha) + other.Position * alpha
end

local function node(class, name, parent)
	local n = { ClassName = class, Name = name, Parent = parent, children = {}, attributes = {} }
	if parent then parent.children[name] = n end
	function n:IsA(kind) return kind == class or (kind == "BasePart" and class == "Part") end
	function n:FindFirstChild(key, recursive)
		if self.children[key] then return self.children[key] end
		if recursive then
			for _, child in self.children do
				local found = child:FindFirstChild(key, true)
				if found then return found end
			end
		end
		return nil
	end
	function n:FindFirstChildOfClass(kind)
		for _, child in self.children do if child:IsA(kind) then return child end end
		return nil
	end
	function n:GetAttribute(key) return self.attributes[key] end
	function n:SetAttribute(key, value) self.attributes[key] = value end
	function n:WaitForChild(key) return assert(self:FindFirstChild(key), key) end
	function n:Play() self.IsPlaying = true; self.playCount = (self.playCount or 0) + 1 end
	function n:Stop() self.IsPlaying = false end
	function n:Destroy() self.Parent = nil; self.destroyed = true end
	return n
end
local function vectorNear(a, b, label)
	assert((a - b).Magnitude < 0.002, label .. ": " .. tostring(a) .. " / " .. tostring(b))
end
local function frameNear(a, b, label)
	vectorNear(a.Position, b.Position, label .. " position")
	vectorNear(a.LookVector, b.LookVector, label .. " forward")
	vectorNear(a.UpVector, b.UpVector, label .. " up")
end
local modules = {}
local services = { ReplicatedStorage = { Modules = {
	FlashlightConfig = "FlashlightConfig", FlashlightRules = "FlashlightRules", GameConfig = "GameConfig",
} }, Lighting = {}, SoundService = {}, ContentProvider = { PreloadAsync = function() end } }
env.game = { GetService = function(_, name) return assert(services[name], name) end }
env.require = function(name) return assert(modules[name]) end
env.script = { Parent = { FlashlightConfig = "FlashlightConfig" } }
local created = {}
env.Instance = { new = function(class)
	local instance = node(class, class)
	table.insert(created, instance)
	return instance
end }
local now = 100
env.os = { clock = function() return now end }
env.task = { spawn = function(fn, ...) fn(...) end, delay = function() end }
env.workspace = { CurrentCamera = { CFrame = CF.new(0, 4, 8) } }
function env.workspace:GetServerTimeNow() return now end
env.RaycastParams = { new = function() return {} end }
env.NumberRange = { new = function(...) return { ... } end }
local function load(name)
	local fn = assert(loadstring(sources[name], name))
	setfenv(fn, env)
	modules[name] = fn()
	return modules[name]
end
local config = load("FlashlightConfig")
load("FlashlightRules")
local Pose, Visuals = load("FlashlightPose"), load("FlashlightVisuals")

local character = node("Model", "Character")
local torso = node("Part", "Torso", character)
torso.CFrame = CF.new(0, 3, 0)
local root = node("Part", "HumanoidRootPart", character)
root.CFrame, root.AssemblyLinearVelocity = torso.CFrame, V.zero
local head = node("Part", "Head", character)
head.Position = V.new(0, 4.5, 0)
local humanoid = node("Humanoid", "Humanoid", character)
humanoid.Health, humanoid.MoveDirection = 100, V.zero
function humanoid:GetState() return env.Enum.HumanoidStateType.Running end
local arm = node("Part", "Right Arm", character)
local shoulder = node("Motor6D", "Right Shoulder", torso)
shoulder.C0 = CF.new(1, 0.5, 0) * CF.Angles(0, math.pi / 2, 0)
shoulder.C1 = CF.new(-0.5, 0.5, 0) * CF.Angles(0, math.pi / 2, 0)
shoulder.Part0, shoulder.Part1, shoulder.Transform = torso, arm, CF.identity
local neck = node("Motor6D", "Neck", torso)
neck.C0, neck.Transform = CF.Angles(-math.pi / 2, 0, math.pi), CF.identity
local tool = node("Tool", "Lanterna", character)
local handle = node("Part", "Handle", tool)
handle.Size = V.new(0.4, 1.8, 0.4)
local origin = node("Attachment", "FlashlightOrigin", handle)
-- A rotated lens exercises model calibration instead of assuming Handle -Z.
origin.CFrame = CF.new(0, 0.8, 0) * CF.Angles(math.pi / 2, 0, 0)
local grip = CF.new(0, -1, 0) * CF.Angles(0.3, 0.2, -0.1)
local function simulate()
	arm.CFrame = torso.CFrame * shoulder.C0 * shoulder.Transform * shoulder.C1:Inverse()
	handle.CFrame = arm.CFrame * grip
	handle.Position = handle.CFrame.Position
	origin.WorldCFrame = handle.CFrame * origin.CFrame
	origin.WorldPosition = origin.WorldCFrame.Position
end
simulate()
local pose = Pose.new(false)
pose:SetTool(tool)

for _, fps in { 30, 60, 144 } do
	for _, angles in { { 0, 0 }, { 70, 0 }, { -70, 0 }, { 0, 65 }, { 0, -65 }, { 55, 55 } } do
		local desired = (CF.Angles(0, math.rad(angles[2]), 0) * CF.Angles(math.rad(angles[1]), 0, 0)).LookVector
		for _ = 1, fps * 3 do
			pose:Reset() -- PreAnimation; no Animator writes to these test joints.
			pose:Update(desired, true, 1 / fps) -- PreSimulation
			simulate() -- Motor6D batch
		end
		vectorNear(origin.WorldCFrame.LookVector, desired, "physical lens follows aim at " .. fps .. " FPS")
		local headForward = (neck.C0 * neck.Transform * neck.C0:Inverse()).LookVector
		if angles[1] > 0 then assert(headForward.Y > 0.1, "R6 head looks up") end
		if angles[1] < 0 then assert(headForward.Y < -0.1, "R6 head looks down") end
		if angles[2] > 0 then assert(headForward.X < -0.1, "R6 head looks left") end
		if angles[2] < 0 then assert(headForward.X > 0.1, "R6 head looks right") end
		local stable = shoulder.Transform
		for _ = 1, fps * 3 do pose:Reset(); pose:Update(desired, true, 1 / fps); simulate() end
		frameNear(shoulder.Transform, stable, "no drift with unkeyed joints")
	end
end
print("PASS: physical R6 lens/head aim up, down and sideways; no accumulated drift at 30/60/144 FPS")

pose:Reset()
local animation = CF.Angles(0.2, -0.4, 0.1)
shoulder.Transform = animation
pose:Update(V.new(0, 0, -1), true, 1 / 60)
pose:Reset()
frameNear(shoulder.Transform, animation, "authored animation survives reset")
pose:Update(V.new(0, 0, -1), true, 1 / 60)
local otherWriter = CF.Angles(0.5, 0, 0)
neck.Transform = otherWriter
pose:Reset()
assert(neck.Transform == otherWriter, "cleanup preserves newer writer")
character:SetAttribute("GrabLocked", true)
pose:Update(V.new(0, 1, 0), true, 1 / 60)
assert(next(pose.applied) == nil, "blocked pose releases joints")
character:SetAttribute("GrabLocked", nil)
pose:Update(V.new(0, 1, 0), true, 1 / 60)
pose:Clear()
frameNear(shoulder.Transform, animation, "unequip preserves base animation")
print("PASS: animation layering, ownership of joint writes, grab blocking and unequip cleanup")

local emitter = node("Attachment", "FlashlightEmitter", handle)
local endpoint = node("Attachment", "FlashlightEnd", handle)
local light = node("SpotLight", "LanternaLuz", emitter)
local spill = node("SpotLight", "LanternaSpill", emitter)
local fill = node("PointLight", "LanternaFill", emitter)
local beam = node("Beam", "FlashlightBeam", emitter)
local obstacleDistance, handBlocked, rays = nil, false, 0
function env.workspace:Raycast(position, direction)
	rays += 1
	if (position - head.Position).Magnitude < 0.001 then
		return if handBlocked then { Position = position } else nil
	end
	return if obstacleDistance then { Position = position + direction.Unit * obstacleDistance } else nil
end
for _, rotation in { CF.identity, CF.Angles(1.2, 0.7, 0), CF.Angles(-1.2, -0.8, 0.4) } do
	handle.CFrame = CF.new(1, 3, 0) * rotation
	handle.Position = handle.CFrame.Position
	origin.WorldCFrame = handle.CFrame * origin.CFrame
	origin.WorldPosition = origin.WorldCFrame.Position
	local oldRays = rays
	Visuals.Update(tool, true)
	assert(rays > oldRays, "rotation invalidates wall cache even before interval expires")
	frameNear(emitter.CFrame, origin.CFrame, "emitter fixed to lens")
	local endWorld = handle.CFrame * endpoint.CFrame
	vectorNear((endWorld.Position - origin.WorldPosition).Unit, origin.WorldCFrame.LookVector, "beam axis matches lens")
	assert(math.abs((endWorld.Position - origin.WorldPosition).Magnitude - config.LightRange) < 0.002)
	assert(light.Enabled and spill.Enabled and fill.Enabled and beam.Enabled)
end
obstacleDistance, now = 3, now + 1
Visuals.Update(tool, true)
local endWorld = handle.CFrame * endpoint.CFrame
assert(math.abs((endWorld.Position - origin.WorldPosition).Magnitude - 3) < 0.002, "beam stops at wall")
handBlocked, now = true, now + 1
Visuals.Update(tool, true)
assert(light.Enabled and spill.Enabled and fill.Enabled,
	"clipped muzzle keeps all light layers active")
vectorNear((handle.CFrame * emitter.CFrame).Position, head.Position,
	"clipped visual emitter moves back to the player's side")
assert(not light.Shadows, "fallback source cannot shadow itself inside the player")
handBlocked, obstacleDistance, now = false, 0.1, now + 1
Visuals.Update(tool, true)
assert(light.Enabled and fill.Enabled and not beam.Enabled,
	"very close walls keep illumination even when the beam is too short to draw")
obstacleDistance, now = nil, now + 1
Visuals.Update(tool, true)
assert(light.Enabled and light.Shadows, "unobstructed source restores normal shadows")
Visuals.Update(tool, false)
assert(not spill.Enabled and not fill.Enabled, "all layers turn off")
print("PASS: lens/beam alignment, wall fallback, close-surface light and manual off")

handBlocked, obstacleDistance = false, nil
tool:SetAttribute("FlashBurstAt", now)
Visuals.Update(tool, false)
assert(light.Enabled and beam.Enabled and light.Brightness == config.FlashBurstBrightness, "burst flashes while normal lamp is off")
local allocations = #created
for _ = 1, 10 do Visuals.Update(tool, false) end
assert(#created == allocations and created[#created].playCount == 1, "one sound per discharge")
now += config.FlashBurstVisualDuration + 0.1
Visuals.Update(tool, false)
assert(not light.Enabled and not beam.Enabled, "burst expires without relighting normal lamp")
assert(created[#created].destroyed, "discharge sound cleaned")

modules.GameConfig = { Roles = { Monster = "Monstro" } }
local ExposureFX = load("FlashlightExposureFX")
local survivor, monster = node("Player", "Survivor"), node("Player", "Monster")
survivor.Character = character
monster.Character = node("Model", "MonsterCharacter")
local monsterHum = node("Humanoid", "Humanoid", monster.Character)
monsterHum.Health = 100
for _, player in { survivor, monster } do
	node("PlayerGui", "PlayerGui", player)
	player:SetAttribute("InRound", true)
end
survivor:SetAttribute("Role", "Sobrevivente")
monster:SetAttribute("Role", "Monstro")
local survivorFX, monsterFX = ExposureFX.new(survivor), ExposureFX.new(monster)
monster.Character:SetAttribute("FlashBurstAt", now)
monster.Character:SetAttribute("FlashBurstBlindUntil", now + config.FlashBurstBlindDuration)
now += 0.1
survivorFX:Update(1 / 60); monsterFX:Update(1 / 60)
assert(monsterFX.gui.Enabled and monsterFX.ring.IsPlaying and monsterFX.ring.Volume > 0)
assert(not survivorFX.gui.Enabled and not survivorFX.ring.IsPlaying, "only hit monster sees white/hears ringing")
local beforeRehits = #created
for _ = 1, 10 do
	monster.Character:SetAttribute("FlashBurstAt", now - 0.1)
	monster.Character:SetAttribute("FlashBurstBlindUntil", now + config.FlashBurstBlindDuration)
	monsterFX:Update(1 / 60)
end
assert(#created == beforeRehits and monsterFX.ring.playCount == 1, "repeated hits reuse one overlay and one tinnitus sound")
now += config.FlashBurstBlindDuration + 0.1
monsterFX:Update(1 / 60)
assert(not monsterFX.gui.Enabled and not monsterFX.ring.IsPlaying and not monsterFX.bloom.Enabled, "personal effects expire")
for _, condition in { "death", "leave", "role", "respawn", "state" } do
	monster.Character:SetAttribute("FlashBurstAt", now - 0.1)
	monster.Character:SetAttribute("FlashBurstBlindUntil", now + 4)
	monsterFX:Update(1 / 60)
	assert(monsterFX.ring.IsPlaying)
	local old = monster.Character
	if condition == "death" then monsterHum.Health = 0
	elseif condition == "leave" then monster:SetAttribute("InRound", false)
	elseif condition == "role" then monster:SetAttribute("Role", "Sobrevivente")
	elseif condition == "respawn" then monster.Character = nil
	else monster.Character:SetAttribute("FlashBurstBlindUntil", nil) end
	monsterFX:Update(1 / 60)
	assert(not monsterFX.ring.IsPlaying and not monsterFX.gui.Enabled, "personal cleanup: " .. condition)
	monster.Character, monsterHum.Health = old, 100
	monster:SetAttribute("InRound", true); monster:SetAttribute("Role", "Monstro")
end
survivorFX:Destroy(); monsterFX:Destroy()
assert(monsterFX.ring.destroyed and monsterFX.gui.destroyed and monsterFX.bloom.destroyed)
print("PASS: accepted flash while off, one-shot sound, private whiteout/tinnitus, no duplicate effects, expiry/death/leave/role/respawn cleanup")
