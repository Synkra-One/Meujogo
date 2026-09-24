-- Service doubles do not assert Roblox rendering or real mesh collision.
for name, source in sources do assert(loadstring(source, name), name) end
print("PASS camera and edited embedded scripts parse")
local env = setmetatable({}, { __index = getfenv() })
setfenv(assert(loadstring(sources.Stub)), env)()
local V, CF = env.Vector3, env.CFrame
local cfMeta = getmetatable(CF.new())
local cfIndex = cfMeta.__index
cfMeta.__index = function(self, key)
	if key == "Rotation" then return self - self.Position end
	return cfIndex(self, key)
end
function cfMeta:VectorToWorldSpace(v) return self * v - self.Position end
function cfMeta:PointToObjectSpace(v)
	local d = v - self.Position
	return V.new(d:Dot(self.RightVector), d:Dot(self.UpVector), -d:Dot(self.LookVector))
end
local function load(name) return setfenv(assert(loadstring(sources[name], name)), env)() end
local config, collision = load("Config"), load("Occlusion")
local function near(a, b, epsilon) assert(math.abs(a-b) < (epsilon or 1e-5), tostring(a).." != "..tostring(b)) end
local world = { room = false }
function world:Spherecast(_, _, _) return if self.sphere then { Distance = self.sphere } else nil end
function world:Raycast(_, direction)
	if self.ray then return { Distance = self.ray } end
	if self.room then return { Distance = direction.Magnitude * 0.8 } end
	return nil
end
function world:GetPartBoundsInRadius() return if self.overlap then { self.overlap } else {} end
local function distance() return collision.Distance(world, V.zero, V.new(0,0,5), 0.4, 0.1, {}, {}) end
near(distance(), 5)
world.sphere = 2
near(distance(), 1.9)
world.ray = 1
near(distance(), 0.9)
world.sphere = nil
near(distance(), 0.9) -- ray-only result must not be lost after a nil sphere hit
world.ray = nil
world.overlap = { CFrame = CF.new(0,0,5), Size = V.new(4,4,1) }
assert(distance() < 4.2, "overlap fallback must retreat even without a cast hit")
world.overlap = { CFrame = CF.new(4,0,5), Size = V.new(1,1,1) }
near(distance(), 5) -- broad-phase corner false positives
world.overlap = nil
near(collision.Distance(world, V.zero, V.zero, 0.4, 0.1, {}, {}), 0)
near(collision.Release(5, 1, 4.5, 1/60), 1)
local function release(fps)
	local d=1; for _=1,fps do d=collision.Release(d,5,4.5,1/fps) end; return d
end
near(release(30), release(144))
assert(release(60) < 5 and release(60) > 4.9)
print("PASS wall/near-plane limits, thin-wall ray fallback, initial overlap and frame-independent release")

local function signal()
	local s={ connections={} }
	function s:Connect(fn)
		local c={ fn=fn, active=true }; function c:Disconnect() self.active=false end
		table.insert(self.connections,c); return c
	end
	function s:Fire(...) for _,c in self.connections do if c.active then c.fn(...) end end end
	return s
end
local function object(class)
	local o={ ClassName=class, attributes={}, children={}, DescendantAdded=signal(), Destroying=signal() }
	function o:GetAttribute(k) return self.attributes[k] end
	function o:SetAttribute(k,v) self.attributes[k]=v end
	function o:IsA(c) return c==class or (class=="Part" and c=="BasePart") end
	function o:WaitForChild(k) return self.children[k] end
	function o:GetDescendants() local r={}; for _,v in self.children do table.insert(r,v) end; return r end
	return o
end
local player=object("Player")
player.CharacterAdded, player.CharacterRemoving = signal(),signal()
local camera={ CameraType="Custom", CFrame=CF.new(0,2,9), Focus=CF.new(), FieldOfView=68,
	NearPlaneZ=-0.5, ViewportSize={X=1920,Y=1080} }
world.CurrentCamera=camera
local players={LocalPlayer=player}; function players:GetPlayers() return {player} end
local callbacks={}
local run={}
function run:BindToRenderStep(name, priority, fn) callbacks[name]={ priority=priority,fn=fn } end
function run:UnbindFromRenderStep(name) callbacks[name]=nil end
local actions={}
function actions:BindAction(_,fn) self.switch=fn end
function actions:UnbindAction() self.switch=nil end
function actions:SetTitle() end
function actions:SetPosition() end
local input={}; function input:GetFocusedTextBox() return self.focused end
local vr={VREnabled=false}
local modules=object("Folder"); modules.children.ShoulderCameraConfig=config
local storage=object("Folder"); storage.children.Modules=modules
local services={Players=players,ReplicatedStorage=storage,RunService=run,Workspace=world,
	ContextActionService=actions,UserInputService=input,VRService=vr}
env.game={GetService=function(_,name) return assert(services[name],name) end}
env.require=function(value) return value end
env.script=object("LocalScript"); env.script.Parent={CameraOcclusion=collision}
env.task={spawn=function(fn,...) fn(...) end}
env.RaycastParams={new=function() return {} end}; env.OverlapParams=env.RaycastParams
env.Enum={RaycastFilterType={Exclude="Exclude"},RenderPriority={Camera={Value=200}},
	CameraType={Custom="Custom"},Material={Air="Air"},UserInputState={Begin="Begin"},
	ContextActionResult={Pass="Pass",Sink="Sink"},KeyCode={V="V",ButtonR3="R3"}}
local function character()
	local c,h,r=object("Model"),object("Humanoid"),object("Part")
	r.Parent=c; r.Position=V.zero; r.LocalTransparencyModifier=0
	h.Parent=c; h.Health=100; h.CameraOffset=V.zero; h.MoveDirection=V.zero; h.FloorMaterial="Ground"
	c.children={Humanoid=h,HumanoidRootPart=r}; return c,h,r
end
local c,h,r=character(); player.Character=c; camera.CameraSubject=h
load("Controller")
local function step(frames)
	for _=1,frames or 1 do
		-- Emulate PlayerModule writing its camera before the post-camera stages.
		camera.CFrame=CF.new(0,2,9)
		callbacks.AdaptiveShoulderCamera.fn(1/60)
		callbacks.AdaptiveCameraSafety.fn()
	end
end
step(120)
assert(player:GetAttribute("AdaptiveShoulderCameraActive"))
near(camera.CFrame.Position.Z, config.Distance, 0.01)
assert(camera.CFrame.Position.Y < 1.5 and camera.CFrame.Position.X > 1)
near(camera.FieldOfView,68,0.01)
player:SetAttribute("MovementLocked",true); step()
near(camera.CFrame.Position.Z,9)
assert(not player:GetAttribute("AdaptiveShoulderCameraActive"))
player:SetAttribute("MovementLocked",false); step(100)
c:SetAttribute("FirearmAiming",true); step(120)
near(camera.CFrame.Position.Z,config.AimDistance,0.01)
near(camera.FieldOfView,60,0.01)
actions.switch(nil,"Begin"); step(120)
assert(camera.CFrame.Position.X < -1)
input.focused=true; assert(actions.switch(nil,"Begin")=="Pass"); input.focused=nil
c:SetAttribute("FirearmAiming",false); step(120)
world.sphere=1.8; step()
assert((camera.CFrame.Position - V.new(0,config.PivotHeight,0)).Magnitude <= 1.68+1e-5)
world.sphere=nil; step()
assert(camera.CFrame.Position.Z < 2.1, "camera must not snap out of a wall")
step(120)
world.room=true; step(120)
assert(math.abs(camera.CFrame.Position.X) < 0.8 and camera.FieldOfView < 66.1)
world.room=false; step(150)
near(camera.CFrame.Position.Z,config.Distance,0.02)
r:SetAttribute("IsCrouching",true); h.CameraOffset=V.new(0,-1.5,0); step(120)
near(camera.CFrame.Position.Z,config.CrouchDistance,0.01)
assert(camera.CFrame.Position.Y < 0.6)
c:SetAttribute("PowerFearHidden",true); step(); assert(r.LocalTransparencyModifier>=0.65)
c:SetAttribute("PowerFearHidden",nil)
camera.CameraType="Scriptable"; step(); near(camera.CFrame.Position.Z,9)
camera.CameraType="Custom"; step(); assert(player:GetAttribute("AdaptiveShoulderCameraActive"))
camera.CameraSubject={}; step(); assert(not player:GetAttribute("AdaptiveShoulderCameraActive"))
camera.CameraSubject=h; vr.VREnabled=true; step(); assert(not player:GetAttribute("AdaptiveShoulderCameraActive"))
vr.VREnabled=false
player.CharacterRemoving:Fire(c)
local newC,newH,newR=character(); player.Character=newC; camera.CameraSubject=newH
player.CharacterAdded:Fire(newC); step(120)
near(camera.CFrame.Position.Z,config.Distance,0.01)
newR.Position=V.new(500,0,0); step()
assert(camera.CFrame.Position.X > 490, "teleport must not drag camera across the world")
env.script.Destroying:Fire()
assert(next(callbacks)==nil and actions.switch==nil)
print("PASS actual controller: lobby unlocked, preparation lock, aiming, shoulder switch, interior, crouch, wall release, powers, menus, spectator, VR, respawn, teleport and cleanup")
