-- Client lifecycle doubles. No physics, rendering or network replication is simulated.
local signals = {}
local function signal()
	local s = { list = {} }
	function s:Connect(fn)
		local c = { Connected = true, fn = fn }
		function c:Disconnect() self.Connected = false end
		table.insert(self.list, c); return c
	end
	function s:Fire(...)
		for _, c in table.clone(self.list) do if c.Connected then c.fn(...) end end
	end
	table.insert(signals, s); return s
end
local function connectionCount()
	local n = 0
	for _, s in signals do for _, c in s.list do if c.Connected then n += 1 end end end
	return n
end
local vec = {}
local function v(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, vec) end
vec.__add = function(a, b) return v(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
vec.__sub = function(a, b) return v(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
vec.__unm = function(a) return v(-a.X,-a.Y,-a.Z) end
vec.__mul = function(a, b)
	if type(b) == "number" then return v(a.X*b,a.Y*b,a.Z*b) end
	return v(a.X*b.X,a.Y*b.Y,a.Z*b.Z)
end
vec.__div = function(a,b) return v(a.X/b,a.Y/b,a.Z/b) end
vec.__index = function(a, key)
	if key == "Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
	if key == "Unit" then return a/a.Magnitude end
	if key == "Dot" then return function(_,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
	if key == "Cross" then return function(_,b) return v(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X) end end
end
local zero = v(0,0,0)
local cfmeta = {}
local function cf(a,y,z)
	return setmetatable({ Position = if type(a)=="number" then v(a,y,z) else a or zero, LookVector = v(1,0,0) },cfmeta)
end
cfmeta.__mul = function(a,b) return cf(a.Position+b.Position) end
local objects = {}
local object
object = function(class)
	local props = { ClassName = class, Name = class, Transparency = 0, Enabled = true }
	local self = { props=props, attrs={}, changed={} }
	setmetatable(self, {
		__index=function(_,k) return props[k] end,
		__newindex=function(_,k,val)
			props[k]=val
			if k=="CFrame" then props.Position=val.Position end
		end,
	})
	self.ChildAdded, self.DescendantAdded, self.CharacterRemoving = signal(), signal(), signal()
	self.DescendantRemoving, self.Destroying, self.Died = signal(), signal(), signal()
	function self:IsA(name) return name==class or class=="Part" and name=="BasePart" end
	function self:GetChildren()
		local found={}; for _,o in objects do if o.Parent==self then table.insert(found,o) end end; return found
	end
	function self:IsDescendantOf(parent)
		local p=self.Parent; while p do if p==parent then return true end; p=p.Parent end; return false
	end
	function self:GetDescendants()
		local found={}; for _,o in objects do if o:IsDescendantOf(self) then table.insert(found,o) end end; return found
	end
	function self:FindFirstChild(name)
		for _,o in self:GetChildren() do if o.Name==name then return o end end; return nil
	end
	function self:FindFirstChildOfClass(name)
		for _,o in self:GetChildren() do if o:IsA(name) then return o end end; return nil
	end
	function self:WaitForChild(name) return assert(self:FindFirstChild(name),name) end
	function self:GetAttribute(name) return self.attrs[name] end
	function self:SetAttribute(name,value)
		local previous=self.attrs[name]; self.attrs[name]=value
		if previous~=value and self.changed[name] then self.changed[name]:Fire() end
	end
	function self:GetAttributeChangedSignal(name)
		if not self.changed[name] then self.changed[name]=signal() end; return self.changed[name]
	end
	function self:Destroy()
		for _,o in self:GetChildren() do o:Destroy() end
		self.Parent=nil; self.destroyed=true
	end
	function self:Emit(count) self.Emitted = (self.Emitted or 0) + count end
	function self:Clear() self.Emitted = 0 end
	function self:Play(_) self.IsPlaying=true end
	function self:Stop(_) self.IsPlaying=false end
	table.insert(objects,self); return self
end
local function child(parent,class,name)
	local o=object(class); o.Name,o.Parent=name,parent; return o
end
local clock = 100
local world=object("Workspace")
function world:GetServerTimeNow() return clock end
local names=setmetatable({}, {__index=function(_,k) return k end})
local modules={}
local services={Workspace=world,ReplicatedStorage={Modules=names}}
local enums=setmetatable({}, {__index=function(t,k)
	local e=setmetatable({}, {__index=function(_,key) return key end}); rawset(t,k,e); return e
end})
local logs={}
local colorMeta = {}
colorMeta.__index = colorMeta
function colorMeta:Lerp(other, t) return setmetatable({R=self.R+(other.R-self.R)*t,G=self.G+(other.G-self.G)*t,B=self.B+(other.B-self.B)*t},colorMeta) end
local function color(r,g,b) return setmetatable({R=r,G=g,B=b},colorMeta) end
local env=setmetatable({
	game={GetService=function(_,name) return assert(services[name],name) end},
	script={Parent=names}, os={clock=function() return clock end}, Enum=enums,
	Vector3={new=v,zero=zero,yAxis=v(0,1,0)}, CFrame={new=cf,Angles=function() return cf(zero) end,lookAt=function(pos,target) local f=cf(pos); f.LookVector=(target-pos).Unit; return f end},
	RaycastParams={new=function() return {} end},OverlapParams={new=function() return {} end},
	Random={new=function() return {NextNumber=function() return 0.5 end} end},
	Instance={new=function(class)
		if class=="BindableEvent" then local e=signal(); return {Event=e,Fire=function(_,...) e:Fire(...) end} end
		return object(class)
	end},
	Color3={new=color,fromRGB=function(r,g,b) return color(r/255,g/255,b/255) end},
	Vector2={new=function(...) return {...} end},
	NumberRange={new=function(...) return {...} end},NumberSequence={new=function(...) return {...} end},
	NumberSequenceKeypoint={new=function(...) return {...} end}, ColorSequence={new=function(...) return {...} end},
	TweenInfo={new=function(...) return {...} end},
	typeof=function(value) return if getmetatable(value)==vec then "Vector3" else typeof(value) end,
	print=function(...) end, warn=function(message) table.insert(logs,message) end,
},{__index=getfenv()})
local function loadModule(name)
	if modules[name] then return modules[name] end
	local chunk=assert(loadstring(assert(sources[name],name),name)); setfenv(chunk,env)
	modules[name]=chunk(); return modules[name]
end
env.require=loadModule
local config=loadModule("GameConfig")
local cfg=config.Monster.ShadowRush
local vfx=loadModule("ShadowRushVFX")
local rules=loadModule("ShadowRushRules")
local folder=child(world,"Folder","ShadowRushVFX")
local c=child(world,"Model","Monster")
local h=child(c,"Humanoid","Humanoid")
h.Health,h.DisplayDistanceType=100,"Viewer"
local r=child(c,"Part","HumanoidRootPart")
r.CFrame,r.Size,r.Transparency,r.Color,r.CastShadow=cf(v(0,3,0)),v(2,2,1),1,color(1,1,1),false
r.AssemblyLinearVelocity=v(75,0,0)
local body=child(c,"Part","Torso")
local originalColor=color(0.5,0.25,0.1)
body.Color,body.Transparency,body.CastShadow,body.Size=originalColor,0.3,true,v(2,2,1)
local decal=child(body,"Decal","face")
decal.Transparency=0.2
local normalParticles=child(body,"ParticleEmitter","NormalParticles")
local ordinarySound=child(r,"Sound","Footsteps")
ordinarySound.Volume=0.6
local rootJoint=child(c,"Motor6D","RootJoint")
rootJoint.Part0,rootJoint.Transform=r,cf(zero)
local originalRootTransform=rootJoint.Transform
local function phase(name)
	c:SetAttribute("ShadowRushState",name)
	c:SetAttribute("ShadowRushPhaseAt",clock)
end
local function step(effect,dt,distance)
	clock+=dt
	return effect.Update(dt,distance or 10)
end
local function named(name)
	for _,o in objects do if o.Parent and o.Name==name then return o end end
end
local function liveCount()
	local count=0
	for _,o in objects do if o.Parent then count+=1 end end
	return count
end
local function restored()
	assert(body.Transparency==0.3 and decal.Transparency==0.2 and r.Transparency==1,"exact transparency restoration")
	assert(body.Color==originalColor and body.CastShadow and normalParticles.Enabled,"appearance restoration")
	assert(ordinarySound.Volume==0.6 and h.DisplayDistanceType=="Viewer","audio/name restoration")
end
local baseline,connections=liveCount(),connectionCount()
assert(cfg.ShadowRushEnterDuration==0.16 and cfg.ShadowRushDuration==5 and cfg.ShadowRushMaterializeDuration==0.24)
assert(cfg.ShadowRushMaxSpeed==75 and cfg.ShadowRushCooldown==25 and cfg.ShadowPassFear==8)
assert(cfg.ShadowRushLoopSoundId=="rbxassetid://9120699200" and cfg.ShadowRushAnimationId=="")
-- Actual existing envelope remains authoritative and continuous on early exit.
assert(rules.Speed("ShadowRush",1,14,14,cfg)==75)
local partialHidden=rules.Hidden("EnteringShadow",0.08,0,cfg)
assert(partialHidden>0 and partialHidden<1)
assert(rules.Hidden("Materializing",0,partialHidden,cfg)==partialHidden)

for _=1,25 do
	phase("EnteringShadow")
	local effect=vfx.new(c,r,folder,true,false)
	step(effect,0.05)
	assert(named("RuptureLight").Brightness>0 and named("Rupture").Emitted>0,"entry burst/light missing")
	assert(named("BrokenWave").Enabled,"wave did not start")
	phase("ShadowRush"); step(effect,0.2)
	assert(body.Transparency==1,"material body must disappear completely into smoke")
	assert(decal.Transparency==1 and not normalParticles.Enabled,"normal appearance was not consumed")
	assert(named("UnboundShadow").Rate>0 and named("TornShadow").Enabled,"motion residues missing")
	assert(named("LivingPlume").Rate>0 and named("DraggingSmoke").Rate>0,"layered moving smoke missing")
	assert(rootJoint.Transform.Position.Y>0,"shadow body must float through its root joint")
	phase("Materializing"); c:SetAttribute("ShadowRushExitHidden",1); step(effect,0.01)
	assert(named("Rupture").ShapeInOut=="Inward","exit must converge")
	step(effect,0.3); phase("Recovery"); step(effect,0.1)
	effect.Finish(); assert(step(effect,0.3))
	effect.Destroy(); effect.Destroy(); restored()
	assert(rootJoint.Transform == originalRootTransform,"floating pose was not restored")
	assert(liveCount()==baseline and connectionCount()==connections,"session leaked objects/listeners")
end
print("PASS: 25 near cycles, entry wave, layered smoke/wake, dissolved body, inward exit, exact restoration")

-- Cancellation mid-entry must interpolate from current appearance.
phase("EnteringShadow"); c:SetAttribute("ShadowRushExitHidden",nil)
local effect=vfx.new(c,r,folder,false,false)
step(effect,0.08)
local before=body.Transparency
c:SetAttribute("ShadowRushExitHidden",rules.Hidden("EnteringShadow",0.08,0,cfg))
phase("Materializing"); effect.Update(0,10)
assert(math.abs(before-body.Transparency)<0.001,"early stop visually jumped")
phase("Idle"); effect.Update(0,10); step(effect,0.12) -- Idle may replicate before Busy
assert(body.Transparency>0.3 and body.Transparency<before,"external cancel should fade")
assert(step(effect,0.2)); effect.Destroy(); restored()

-- Late streaming starts in the active state without replaying the entry blast.
phase("ShadowRush")
effect=vfx.new(c,r,folder,false,false)
step(effect,0.2,500)
assert(#folder:GetChildren()==0 and body.Transparency==1,"far LOD must not leave the material body visible")
step(effect,0.25,100)
assert(named("UnboundShadow").Rate>0 and not named("TornShadow").Enabled,"medium LOD too detailed")
assert(not named("Rupture").Emitted,"late observer replayed activation")
step(effect,0.25,10)
assert(named("TornShadow").Enabled,"near LOD failed to resume")
step(effect,0.25,500)
assert(#folder:GetChildren()==0,"far LOD retained details")
step(effect,0.25,10)
local newDecal=child(body,"Decal","StreamedDecal"); newDecal.Transparency=0.4
c.DescendantAdded:Fire(newDecal); step(effect,0.1)
assert(newDecal.Transparency==1,"streamed item escaped fade")
c.DescendantRemoving:Fire(newDecal); newDecal.Parent=nil
assert(newDecal.Transparency==0.4,"streamed-out item wasn't restored")
effect.Destroy(); restored()
assert(liveCount()==baseline and connectionCount()==connections)
phase("ShadowRush")
effect=vfx.new(c,r,folder,true,true); step(effect,0.2)
assert(not named("TornShadow").Enabled and #named("ShadowDetails"):GetDescendants()<100,"mobile detail budget")
effect.Destroy(); restored()
print("PASS: early/external cancellation, late streams, LOD near/mid/far, mobile, streamed item cleanup")

-- Configurable sound IDs are local, spatial, attenuated and owned by the handle.
cfg.ShadowRushEnterSoundId="123"; cfg.ShadowRushLoopSoundId="456"; cfg.ShadowRushExitSoundId="789"
phase("EnteringShadow"); effect=vfx.new(c,r,folder,true); step(effect,0.04)
local entry=named("ShadowRushAudio")
assert(entry and entry.Parent==r and entry.PlaybackSpeed==cfg.EnterSoundPlaybackSpeed)
assert(entry.RollOffMaxDistance==cfg.SoundMaxDistance and entry:FindFirstChildOfClass("EqualizerSoundEffect"))
phase("ShadowRush"); step(effect,0.1)
local loopSound
for _,o in objects do if o.Parent and o.Name=="ShadowRushAudio" and o.Looped then loopSound=o end end
assert(loopSound and loopSound.IsPlaying and loopSound.SoundId=="rbxassetid://456","loop audio did not play during movement")
phase("Materializing"); step(effect,0.1)
local audioCount=0
for _,o in objects do if o.Parent and o.Name=="ShadowRushAudio" then audioCount+=1 end end
assert(not loopSound.Parent and audioCount==2,"loop audio should stop when materializing starts")
step(effect,0.3); phase("Recovery"); step(effect,0.1); effect.Finish()
local afterCount=0
for _,o in objects do if o.Parent and o.Name=="ShadowRushAudio" then afterCount+=1 end end
assert(afterCount==2,"normal completion replayed exit audio")
effect.Destroy(); restored()
assert(liveCount()==baseline and connectionCount()==connections)
print("PASS: spatial audio, movement loop, bass EQ, no duplicate completion sound, cleanup")

local cam=child(world,"Camera","Camera"); cam.CFrame=cf(v(1,2,3)); world.CurrentCamera=cam
local ambient=child(cam,"ColorCorrectionEffect","OtherEffect")
ambient.Brightness=0.1
local view=vfx.newView()
view.Update(0.1,0,0,false)
assert(not named("ShadowRushVision"),"observer/idle client allocated vision")
clock+=0.02; view.Update(0.05,0.6,0.5,true)
assert(named("ShadowRushVision").Parent==cam and named("ShadowRushVision").Saturation<0)
assert(ambient.Brightness==0.1,"overwrote another postprocess")
local camBase=cam.CFrame
view.Unshake(); camBase=cam.CFrame
clock+=0.02; view.Update(0.02,1,1,false); view.Unshake()
assert(cam.CFrame==camBase,"camera impulse drifted")
local cam2=child(world,"Camera","Camera2"); cam2.CFrame=cf(zero); world.CurrentCamera=cam2
view.Update(0.1,1,1,false)
assert(named("ShadowRushVision").Parent==cam2 and #cam:GetChildren()==1,"camera replacement leaked effects")
for _=1,30 do clock+=0.05; view.Unshake(); view.Update(0.05,0,0,false) end
assert(not named("ShadowRushVision") and not named("ShadowRushBlur") and not named("ShadowRushBloom"),"view effects leaked after end/death")
view.Destroy(); view.Destroy()
assert(ambient.Parent==cam and ambient.Brightness==0.1)
print("PASS: private vision, idle allocation, camera replacement, nonaccumulating impulse, postprocess cleanup")

-- Use the real Animate integration with the existing Animator, once per rig.
local animator=child(h,"Animator","Animator")
local tracks,loads={},0
function animator:LoadAnimation(animation)
	loads+=1
	local track=object("AnimationTrack"); track.Animation=animation
	function track:Stop(fade) self.IsPlaying=false; self.Fade=fade end
	table.insert(tracks,track)
	return track
end
local animate=object("LocalScript")
local resumes,stops=0,0
local animationEnv=setmetatable({Figure=c,Humanoid=h,script=animate,
	onRunning=function() resumes+=1 end, horizontalSpeed=function() return 10 end,
	stopAllAnimations=function() stops+=1 end},{__index=env})
phase("Idle"); c:SetAttribute("ShadowRushBusy",nil)
local chunk=assert(loadstring(sources.ShadowAnimation,"Animate.ShadowRush")); setfenv(chunk,animationEnv); chunk()
phase("EnteringShadow"); c:SetAttribute("ShadowRushBusy",true)
assert(loads==0 and stops>0,"empty animation ID must suppress normal locomotion")
phase("Idle"); c:SetAttribute("ShadowRushBusy",nil)
	cfg.ShadowRushAnimationId="rbxassetid://12345" -- synthetic; doubles only
	for _=1,25 do
		phase("EnteringShadow"); c:SetAttribute("ShadowRushBusy",true)
		assert(loads == (if _ == 1 then 0 else 1), "locomotion animation must wait until the rush actually starts")
		phase("ShadowRush")
		assert(loads==1 and tracks[1].IsPlaying and tracks[1].Priority=="Action" and tracks[1].Looped)
		assert(tracks[1].Animation.AnimationId==cfg.ShadowRushAnimationId)
		phase("Materializing"); assert(not tracks[1].IsPlaying and tracks[1].Fade==cfg.ShadowRushMaterializeDuration)
	phase("Idle"); c:SetAttribute("ShadowRushBusy",nil)
end
assert(resumes>=25 and stops>=25)
h.Died:Fire(); animate.Destroying:Fire()
assert(tracks[1].destroyed and connectionCount()==connections,"animation lifecycle leaked")
print("PASS: existing animation owner, one cached Action track over 25 activations, fade, normal locomotion resume/death cleanup")

-- Run the real controller on an observer, then the owner, including render cleanup.
local localPlayer=object("Player")
local otherPlayer=object("Player"); otherPlayer.Character=c
local localChar=child(world,"Model","LocalCharacter")
local localHum=child(localChar,"Humanoid","Humanoid"); localHum.Health=100
local localRoot=child(localChar,"Part","HumanoidRootPart")
localRoot.AssemblyLinearVelocity=zero; localRoot.CFrame=cf(zero)
localPlayer.Character=localChar
local playerGui=child(localPlayer,"PlayerGui","PlayerGui")
localPlayer:SetAttribute("Role",config.Roles.Survivor)
services.Players={LocalPlayer=localPlayer,GetPlayers=function() return {localPlayer,otherPlayer} end}
local callbacks={}
services.RunService={BindToRenderStep=function(_,name,_,fn) callbacks[name]=fn end,
	UnbindFromRenderStep=function(_,name) callbacks[name]=nil end}
local boundAction
services.ContextActionService={BindAction=function(_,_,fn) boundAction=fn end,UnbindAction=function() boundAction=nil end,
	SetTitle=function() end,SetPosition=function() end}
services.UserInputService={TouchEnabled=false,KeyboardEnabled=true,GetFocusedTextBox=function() return nil end}
services.Debris={AddItem=function() end}
local remote={OnClientEvent=signal(),sent={}}
function remote:FireServer(...) table.insert(self.sent,{...}) end
modules.Remotes={ShadowRush=remote}
env.UDim2={fromScale=function(...) return {...} end,fromOffset=function(...) return {...} end}
enums.RenderPriority.Camera={Value=200}
local controllerScript=object("LocalScript")
local controllerEnv=setmetatable({script=controllerScript,UserSettings=function() error("no quality settings in doubles") end},{__index=env})
local controller=assert(loadstring(sources.ShadowController,"ShadowRushController")); setfenv(controller,controllerEnv); controller()
local function frame()
	clock+=0.05
	callbacks.ShadowRushUnshake()
	callbacks.ShadowRushPresentation(0.05)
end
phase("ShadowRush"); c:SetAttribute("ShadowRushBusy",true); c:SetAttribute("ShadowRushToken",1)
for _=1,6 do frame() end
assert(named("ShadowDetails") and not named("ShadowRushVision"),"observer received private postprocess")
assert(#remote.sent==0,"presentation emitted obsolete Move requests")
localPlayer.Character=c; otherPlayer.Character=nil; localPlayer:SetAttribute("Role",config.Roles.Monster)
for _=1,6 do frame() end
assert(named("ShadowRushVision") and c:GetAttribute("ShadowRushFOV")>0,"owner missing private vision/FOV")
assert(boundAction,"monster input binding missing")
boundAction(nil,"Begin"); assert(remote.sent[#remote.sent][1]=="Stop" and remote.sent[#remote.sent][2]==1)
local sentBeforeStun = #remote.sent
c:SetAttribute("FlashPowerBlocked", true)
boundAction(nil,"Begin")
assert(#remote.sent == sentBeforeStun, "F must not send activation while flash blocked")
c:SetAttribute("FlashPowerBlocked", nil)
boundAction(nil,"Begin")
assert(#remote.sent == sentBeforeStun + 1, "F input recovers after block")
localPlayer:SetAttribute("Eliminado",true); h.Health=0
for _=1,30 do frame() end
assert(not named("ShadowRushVision") and c:GetAttribute("ShadowRushFOV")==nil,"death retained private effects")
assert(not named("ShadowDetails"),"death retained world effects")
controllerScript.Destroying:Fire()
assert(not callbacks.ShadowRushPresentation and not callbacks.ShadowRushUnshake)
assert(not named("ShadowRushHUD"),"controller HUD leaked")
print("PASS: actual controller observer/owner isolation, existing F input/token, zero Move spam, death and render/HUD cleanup")
