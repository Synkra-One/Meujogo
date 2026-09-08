-- Actual server/Rules/Fear/Combat modules. Geometry doubles implement a floor,
-- slope, cliff and thin wall; real Roblox collision fidelity requires Studio.
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
	function self:Emit(_) end
	function self:Play(_) self.IsPlaying=true end
	function self:Stop(_) self.IsPlaying=false end
	table.insert(objects,self); return self
end
local function child(parent,class,name)
	local o=object(class); o.Name,o.Parent=name,parent; return o
end
local clock, active, wall, cliff, water, slope, steep, overlap, fault = 100, true, nil, nil, false, 0, false, false, false
local heartbeat=signal()
local world=object("Workspace")
function world:GetServerTimeNow() return clock end
function world:Raycast(origin,delta,params)
	assert(params.RespectCanCollide)
	if fault then error("injected geometry failure") end
	if math.abs(delta.X)+math.abs(delta.Z)>0.001 then
		if wall and (origin.X-wall)*(origin.X+delta.X-wall)<=0 then return { Instance={} } end
		return nil
	end
	if cliff and origin.X>cliff then return nil end
	local height=slope*origin.X
	if height>origin.Y or height<origin.Y+delta.Y then return nil end
	return { Position=v(origin.X,height,origin.Z), Material=if water then "Water" else "Ground",
		Normal=if steep then v(0,0.1,1) else v(-slope,1,0).Unit }
end
function world:Blockcast(frame,size,delta,_)
	if wall and frame.Position.X+size.X/2<wall and frame.Position.X+delta.X+size.X/2>=wall then return {} end
	return nil
end
function world:GetPartsInPart(_,_) return if overlap then {{} } else {} end
local players={ list={}, PlayerRemoving=signal(), PlayerAdded=signal() }
function players:GetPlayers() return table.clone(self.list) end
function players:GetPlayerFromCharacter(c) for _,p in self.list do if p.Character==c then return p end end end
local round={ RoundPrepared={Event=signal()}, RoundEnded={Event=signal()}, IsRoundActive=function() return active end }
local remote={ OnServerEvent=signal(), sent={} }
function remote:FireClient(p,...) table.insert(self.sent,{p,...}) end
local attack={ OnServerEvent=signal(), FireClient=function() end }
local damageCalls=0
local names=setmetatable({ Tools={IslandLayout="IslandLayout"} },{__index=function(_,k) return k end})
local modules={ RoundManager=round, IslandLayout={CONFIG={AreaHalf=960}},
	MonsterLightWeakness={IsWeakened=function(c) return c:GetAttribute("TestWeakened")==true end},
	DamageSystem={Apply=function() damageCalls+=1; return 1 end},
	LoadoutData={GetPerk=function() return nil end},
	Remotes={ShadowRush=remote, MonsterAttack=attack, SprintIntent={OnServerEvent=signal()}} }
local services={Players=players,Workspace=world,ReplicatedStorage={Modules=names},RunService={Heartbeat=heartbeat},
	TweenService={Create=function(_,target,_,properties) return {Play=function() for k,val in properties do target[k]=val end end,Cancel=function() end} end} }
local enums=setmetatable({}, {__index=function(t,k)
	local e=setmetatable({}, {__index=function(_,key) return key end}); rawset(t,k,e); return e
end})
local logs={}
local env=setmetatable({
	game={GetService=function(_,name) return assert(services[name],name) end},
	script={Parent=names}, os={clock=function() return clock end}, Enum=enums,
	Vector3={new=v,zero=zero,yAxis=v(0,1,0)}, CFrame={new=cf,lookAt=function(pos,target) local f=cf(pos); f.LookVector=(target-pos).Unit; return f end},
	RaycastParams={new=function() return {} end},OverlapParams={new=function() return {} end},
	Random={new=function() return {NextNumber=function() return 0.5 end} end},
	Instance={new=function(class)
		if class=="BindableEvent" then local e=signal(); return {Event=e,Fire=function(_,...) e:Fire(...) end} end
		return object(class)
	end},
	Color3={new=function(...) return {...} end,fromRGB=function(...) return {...} end},
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
local rules=loadModule("ShadowRushRules")
local fear=loadModule("FearSystem") -- real API/storage, no mock AddFear
local rush=loadModule("ShadowRush")
local combat=loadModule("MonsterCombat")
local stamina=loadModule("StaminaSystem")
local function newPlayer(name,role,x)
	local p=object("Player"); p.Name=name; p.CharacterAdded=signal(); p.Parent=players
	p:SetAttribute("Role",role); p:SetAttribute("InRound",true)
	local c=child(world,"Model",name); p.Character=c
	local h=child(c,"Humanoid","Humanoid")
	h.Health,h.HipHeight,h.RigType,h.WalkSpeed,h.AutoRotate,h.JumpPower,h.JumpHeight=100,0,"R6",14,true,50,7
	h.Died=signal(); function h:UnequipTools() end
	local root=child(c,"Part","HumanoidRootPart")
	root.Size,root.CFrame,root.Anchored,root.CanCollide,root.CanTouch=v(2,2,1),cf(v(x,3,0)),false,true,true
	root.AssemblyLinearVelocity=zero
	local leg=child(c,"Part","Left Leg"); leg.Size=v(1,2,1); leg.CanCollide,leg.CanTouch=false,true
	root.Transparency,leg.Transparency=1,0.3
	table.insert(players.list,p); return p,c,h,root,leg
end
local m,c,h,r,leg=newPlayer("monster",config.Roles.Monster,0)
local a,_,ha,ra=newPlayer("survivor",config.Roles.Survivor,16)
local b,_,hb,rb=newPlayer("survivor2",config.Roles.Survivor,20)
local spy=newPlayer("spy",config.Roles.Spy,18)
players.LocalPlayer=a -- observer for VFX tests, so no optional tracks
local cfg=config.Monster.ShadowRush
local function state() return c:GetAttribute("ShadowRushState") end
local function packet(p,action,token,input) remote.OnServerEvent:Fire(p,action,token,input) end
local function advance(seconds,input)
	for _=1,math.ceil(seconds*30) do
		clock+=1/30
		if input then packet(m,"Move",c:GetAttribute("ShadowRushToken"),input) end
		heartbeat:Fire(1/30)
	end
end
local function clean()
	assert(not c:GetAttribute("ShadowRushBusy") and state()=="Idle")
	assert(not r.Anchored and r.CanCollide and r.CanTouch and not leg.CanCollide and leg.CanTouch)
	assert(h.WalkSpeed==14 and h.AutoRotate and h.JumpPower==50 and h.JumpHeight==7)
	for _,o in objects do assert(not (o.Name=="ShadowRushQuery" and o.Parent),"leaked query part") end
end
local function reset()
	fault=false; rush.Cancel(m); round.RoundPrepared.Event:Fire()
	active=true; wall=nil; cliff=nil; water=false; slope=0; steep=false; overlap=false
	h.Health=100; m:SetAttribute("Eliminado",nil); c:SetAttribute("Eliminado",nil)
	m:SetAttribute("Role",config.Roles.Monster); m:SetAttribute("Amarrado",nil)
	c:SetAttribute("TeleportBusy",nil); c:SetAttribute("TestWeakened",nil)
	r.CFrame=cf(v(0,3,0)); r.Anchored=false
	clock+=1
end
local function start() packet(m,"Start",nil,v(1,0,0)) end
-- Network validation (NaN, infinity, non-vector, vertical/faster-than-unit).
assert(not rules.Direction("oops") and not rules.Direction(v(0/0,0,0)) and not rules.Direction(v(math.huge,0,0)))
assert(not rules.Direction(v(0,1,0)) and not rules.Direction(v(100,0,0)))
local velocity=zero
for _=1,300 do velocity=rules.Velocity(velocity,v(1,0,0),1/60,cfg,false); assert(velocity.Magnitude<=75.00001) end
assert(velocity.X>74)
assert(rules.Velocity(velocity,v(-1,0,0),1/60,cfg,false).X>0,"instant reversal")
for _=1,12 do velocity=rules.Velocity(velocity,zero,1/60,cfg,true) end
assert(velocity.Magnitude<1e-5,"exit must brake fully in configured time")
assert(rules.SegmentDistance(v(5,1,0),zero,v(10,0,0))==1)
rush.Init(); combat.Init(); stamina.Init()
local connections=connectionCount(); rush.Init(); assert(connectionCount()==connections,"duplicate init")
packet(a,"Start",nil,v(1,0,0)); assert(not a.Character:GetAttribute("ShadowRushBusy"))
active=false; start(); assert(not c:GetAttribute("ShadowRushBusy")); active=true; clock+=1
c:SetAttribute("TeleportBusy",true); start(); assert(not c:GetAttribute("ShadowRushBusy")); c:SetAttribute("TeleportBusy",nil); clock+=1
start(); assert(state()=="EnteringShadow" and r.Anchored and not r.CanCollide and not r.CanTouch)
attack.OnServerEvent:Fire(m); assert(damageCalls==0,"entry attack")
advance(0.5,v(1,0,0)); assert(state()=="ShadowRush")
packet(m,"Move",-999,v(0,0,1)); advance(0.6,v(1,0,0))
assert(r.Position.X>10 and r.Position.Z==0 and r.Position.Y==3)
assert(fear.GetFear(a)==cfg.ShadowPassFear and fear.GetFear(b)==cfg.ShadowPassFear,
	"real Fear integration: "..tostring(fear.GetFear(a))..", "..tostring(fear.GetFear(b)).." / "..tostring(#remote.sent).." messages")
assert(ha.Health==100 and hb.Health==100,"rush damaged survivor")
assert(fear.GetFear(spy)==0 and #remote.sent==2,"victim routing / per-activation cooldown")
attack.OnServerEvent:Fire(m); assert(damageCalls==0,"rush attack")
local token=c:GetAttribute("ShadowRushToken")
packet(m,"Stop",token)
advance(0.5); assert(state()=="Recovery"); attack.OnServerEvent:Fire(m); assert(damageCalls==0,"recovery attack")
advance(0.85); clean()
start(); assert(state()=="Idle","cooldown bypass")
assert(connectionCount()==connections,"session connections leaked")
print("PASS: authority, cooldown, motion, attacks blocked, real Fear, three-player routing, restoration")

reset(); wall=10; local passCount=#remote.sent; start(); advance(1,v(1,0,0))
assert(#remote.sent==passCount,"Shadow Pass through wall")
rush.Cancel(m); clean()
reset(); start(); advance(0.7,v(1,0,0))
local accepted=r.Position
r.CFrame=cf(v(500,100,500)); packet(m,"Move",c:GetAttribute("ShadowRushToken"),v(500,0,0))
advance(0.1)
assert((r.Position-accepted).Magnitude<=cfg.ShadowRushMaxSpeed*0.1+0.01,"position/speed injection")
rush.Cancel(m); clean()
reset(); start()
r.AssemblyLinearVelocity=v(75,0,0)
modules.Remotes.SprintIntent.OnServerEvent:Fire(m,true)
local staminaBefore=stamina.Get(m)
advance(0.3)
assert(stamina.Get(m)==staminaBefore and r:GetAttribute("CanSprint")==false,"ShadowRush consumed sprint stamina")
rush.Cancel(m); r.AssemblyLinearVelocity=zero; advance(0.3)
assert(r:GetAttribute("CanSprint")==true,"sprint gate not restored")

-- Walls and terrain: no endpoint jump even with high-speed or lagged updates.
reset(); wall=18; start(); advance(2,v(1,0,0)); assert(r.Position.X<=18-cfg.CollisionRadius,"wall tunneling")
rush.Cancel(m); clean()
reset(); cliff=10; start(); advance(2,v(1,0,0)); assert(r.Position.X<=10 and r.Position.Y==3,"cliff flight")
rush.Cancel(m); clean()
reset(); slope=0.15; start(); advance(1,v(1,0,0)); assert(math.abs(r.Position.Y-(r.Position.X*0.15+3))<1e-6,"slope follow")
rush.Cancel(m); clean()
for _,mode in {"water","steep","overlap"} do
	reset(); if mode=="water" then water=true elseif mode=="steep" then steep=true else overlap=true end
	start(); assert(not c:GetAttribute("ShadowRushBusy"),mode); clean()
end
reset(); r.CFrame=cf(v(950,3,0)); start(); advance(1,v(1,0,0)); assert(r.Position.X<=952.5,"bounds escape"); rush.Cancel(m)
reset(); start(); advance(0.9,v(1,0,0)); local before=r.Position.X
clock+=2; heartbeat:Fire(2); assert(r.Position.X-before<=cfg.ShadowRushMaxSpeed*cfg.MaxFrameDelta+0.01,"lag jump")
advance(1); local stopped=r.Position.X; advance(1); assert(r.Position.X-stopped<0.1,"stale input kept driving"); rush.Cancel(m)
print("PASS: thin wall, cliff, slope, water, overlap, bounds, lag, input timeout (geometry doubles)")

-- Every termination path shares exactly the same cleanup, repeated sessions.
for _,reason in {"enter cancel","rush cancel","materialize cancel","death","round end","respawn","role","tie","weakness","error","duration"} do
	reset(); start()
	if reason~="enter cancel" then advance(0.6,v(1,0,0)) end
	if reason=="materialize cancel" then packet(m,"Stop",c:GetAttribute("ShadowRushToken")); clock+=0.2 end
	if reason=="death" then h.Health=0; h.Died:Fire()
	elseif reason=="round end" then round.RoundEnded.Event:Fire()
	elseif reason=="respawn" then m.CharacterRemoving:Fire(c)
	elseif reason=="role" then m:SetAttribute("Role",config.Roles.Survivor); advance(0.1)
	elseif reason=="tie" then m:SetAttribute("Amarrado",true); advance(0.1)
	elseif reason=="weakness" then c:SetAttribute("TestWeakened",true); advance(1.5)
	elseif reason=="error" then fault=true; advance(0.1); fault=false
	elseif reason=="duration" then advance(7,v(1,0,0))
	else rush.Cancel(m) end
	clean(); assert(connectionCount()==connections,"connection leak: "..reason)
end
assert(#logs==1 and string.find(logs[1],"injected geometry failure"),"unexpected server errors")
print("PASS: manual cancel in all phases, death, round end, respawn, role/tie interruption, weakness, error, duration")

-- VFX lifecycle with native-object doubles: no blank-ID audio, no accumulated
-- instances/listeners, and original partially transparent appearance restored.
local vfx=loadModule("ShadowRushVFX")
local effectsFolder=child(world,"Folder","ShadowRushVFX")
reset()
for _=1,25 do
	local count=connectionCount()
	c:SetAttribute("ShadowRushState","EnteringShadow"); c:SetAttribute("ShadowRushPhaseAt",clock)
	local effect=vfx.new(c,r,effectsFolder)
	clock+=0.5; effect.Update(0.5)
	assert(leg.Transparency==1,"body did not dissolve")
	c:SetAttribute("ShadowRushState","ShadowRush"); c:SetAttribute("ShadowRushPhaseAt",clock)
	effect.Update(0.1)
	c:SetAttribute("ShadowRushState","Materializing"); c:SetAttribute("ShadowRushPhaseAt",clock)
	effect.Update(0.1)
	effect.Destroy(); effect.Destroy()
	assert(leg.Transparency==0.3 and r.Transparency==1,"appearance restoration")
	assert(#effectsFolder:GetChildren()==0 and connectionCount()==count,"VFX leak")
end
for _,o in objects do assert(not(o:IsA("Sound") and o.Parent),"empty sound IDs should not create audio") end
local effect=vfx.new(c,r,effectsFolder)
c:SetAttribute("ShadowRushState","EnteringShadow"); c:SetAttribute("ShadowRushPhaseAt",clock)
clock+=0.1; effect.Update(0.1)
local partial=leg.Transparency
c:SetAttribute("ShadowRushState","Materializing"); c:SetAttribute("ShadowRushPhaseAt",clock)
effect.Update(0)
assert(math.abs(leg.Transparency-partial)<1e-7,"early manual stop popped body invisible")
effect.Destroy()
print("PASS: 25 VFX cycles, double cleanup, exact transparency restoration, blank asset IDs")
