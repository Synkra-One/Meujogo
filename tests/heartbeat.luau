-- Engine mocks: tests authority, recipient isolation, lifecycle and frame-rate independence.
local function signal()
	local s = { listeners = {} }
	function s:Connect(fn)
		local c = { connected = true, fn = fn }
		function c:Disconnect() self.connected = false end
		table.insert(self.listeners, c); return c
	end
	function s:Fire(...) for _, c in table.clone(self.listeners) do if c.connected then c.fn(...) end end end
	function s:Count() local n=0; for _,c in self.listeners do if c.connected then n+=1 end end; return n end
	return s
end
local vm = {}
local function vec(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},vm) end
vm.__sub = function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vm.__add = function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vm.__index = function(v,k) if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end end
local cf = {}; cf.__mul = function(a) return a end
local function frame(x,y,z) return setmetatable({Position=if type(x)=="table" then x else vec(x,y,z)},cf) end
local made = {}
local function object(class)
	local props = {ClassName=class,Name=class,children={},attrs={},changes={},Destroying=signal(),
		ChildAdded=signal(),CharacterRemoving=signal(),CharacterAdded=signal(),Health=100,MaxHealth=100,
		Position=vec(),CFrame=frame(),AssemblyLinearVelocity=vec(),Anchored=false,IsLoaded=true,TimePosition=0,plays=0}
	local methods = {}
	local o = setmetatable({}, {__index=function(_,k) return methods[k] or props[k] end,
		__newindex=function(t,k,v)
			if k=="Parent" then
				if props.Parent then local i=table.find(props.Parent.children,t); if i then table.remove(props.Parent.children,i) end end
				if v then table.insert(v.children,t) end
			end
			props[k]=v
		end})
	function methods:IsA(c) return c==class or (c=="BasePart" and class=="Part") end
	function methods:GetAttribute(k) return props.attrs[k] end
	function methods:GetAttributeChangedSignal(k) props.changes[k]=props.changes[k] or signal(); return props.changes[k] end
	function methods:SetAttribute(k,v) props.attrs[k]=v; self:GetAttributeChangedSignal(k):Fire() end
	function methods:FindFirstChild(k) for _,c in props.children do if c.Name==k then return c end end end
	function methods:WaitForChild(k) return assert(self:FindFirstChild(k),k) end
	function methods:FindFirstChildOfClass(k) for _,c in props.children do if c:IsA(k) then return c end end end
	function methods:GetChildren() return table.clone(props.children) end
	function methods:GetDescendants()
		local list={}; for _,c in props.children do table.insert(list,c); for _,d in c:GetDescendants() do table.insert(list,d) end end; return list
	end
	function methods:ClearAllChildren() for _,c in self:GetChildren() do c:Destroy() end end
	function methods:Destroy() self:ClearAllChildren(); self.Parent=nil; self.destroyed=true end
	function methods:Clone()
		local c=object(class); c.Name=self.Name
		for _,child in self:GetChildren() do local cc=child:Clone(); cc.Parent=c end
		return c
	end
	function methods:GetBoundingBox() return frame(),vec(2,2,1) end
	function methods:ScaleTo(scale) self.scale=scale end
	function methods:PivotTo(value) self.CFrame=value end
	function methods:Play() self.plays+=1; self.IsPlaying=true end
	function methods:Stop() self.IsPlaying=false end
	if class=="BindableEvent" then props.Event=signal(); function methods:Fire(...) props.Event:Fire(...) end end
	table.insert(made,o); return o
end
local names=setmetatable({}, {__index=function(_,k) return k end})
local now,active,blocked,raycasts=0,true,false,0
local world,storage,serverStorage,players=object("Workspace"),object("ReplicatedStorage"),object("ServerStorage"),object("Players")
storage.Modules=names; players.PlayerRemoving=signal(); players.PlayerAdded=signal()
function players:GetPlayers() return self:GetChildren() end
function world:Raycast(_,_,params)
	raycasts+=1; assert(params.RespectCanCollide and params.IgnoreWater and #params.FilterDescendantsInstances==2)
	return if blocked then {} else nil
end
local heartbeat,render=signal(),signal()
local round={IsRoundActive=function() return active end,RoundPrepared=object("BindableEvent"),RoundEnded=object("BindableEvent")}
local fears={}
local remote={OnClientEvent=signal(),packets={}}
function remote:FireClient(p,char,snapshot) table.insert(self.packets,{player=p,character=char,snapshot=snapshot}) end
local remotes={HeartbeatDetected=remote,RoundEnded={OnClientEvent=signal()}}
local modules={RoundManager=round,Remotes=remotes,LoadoutData={GetPerk=function() return nil end},
	FearSystem={GetFear=function(p) return fears[p] or 0 end},StaminaSystem={},WeaponSystem={}}
local loadingFails=true
local services={Players=players,Workspace=world,ReplicatedStorage=storage,ServerStorage=serverStorage,
	InsertService={LoadAsset=function(_,id) assert(id==1994009448); if loadingFails then error("asset denied") end; return object("Model") end},
	RunService={Heartbeat=heartbeat,RenderStepped=render,IsServer=function() return true end}}
local env=setmetatable({game={GetService=function(_,k) return assert(services[k],k) end},
	script={Parent=names,Destroying=signal()},Instance={new=object},Vector3={new=vec},
	CFrame={new=frame,Angles=frame,lookAt=frame},Color3={new=function(...) return {...} end,fromRGB=function(...) return {...} end},
	UDim2={fromScale=function(x,y) return {X=x,Y=y} end},RaycastParams={new=function() return {} end},
	Enum={KeyCode=names,RaycastFilterType=names,PartType=names,Material=names,RollOffMode=names,HighlightDepthMode=names},
	task={spawn=function(fn) fn() end},os={clock=function() return now end},warn=function() end,
},{__index=getfenv()})
local function loadModule(name)
	if modules[name] then return modules[name] end
	local fn=assert(loadstring(sources[name],name)); setfenv(fn,env); modules[name]=fn(); return modules[name]
end
env.require=loadModule
local config=loadModule("GameConfig")
local cfg,rules=loadModule("HeartbeatConfig"),loadModule("HeartbeatRules")
local function character(p,x)
	local c=object("Model"); c.Parent=world; p.Character=c
	local h=object("Humanoid"); h.Parent=c
	local r=object("Part"); r.Name="HumanoidRootPart"; r.Position=vec(x or 0); r.Parent=c
	return c,h,r
end
local function player(role,x)
	local p=object("Player"); p.Parent=players; p:SetAttribute("Role",role); p:SetAttribute("InRound",true)
	character(p,x); return p
end
local monster=player(config.Roles.Monster,0)
local target=player(config.Roles.Survivor,12)
local other=player(config.Roles.Survivor,20)
local spy=player(config.Roles.Spy,10)
local spectator=player(config.Roles.Monster,0); spectator:SetAttribute("InRound",false)
local farMonster=player(config.Roles.Monster,800)
local targetRoot=target.Character:FindFirstChild("HumanoidRootPart")
local targetHum=target.Character:FindFirstChildOfClass("Humanoid")
local detector=loadModule("HeartbeatDetection")
detector.Init(); detector.Init(); assert(heartbeat:Count()==1,"idempotent loop")
assert(not remote.OnServerEvent,"no client authority")
local function tick()
	now+=cfg.UpdateInterval; remote.packets={}; heartbeat:Fire(cfg.UpdateInterval)
	local monsterSnapshot = {}
	for _,packet in remote.packets do
		assert(packet.player==monster or packet.player==farMonster or packet.player==target or packet.player==other,
			"only monsters and the matching survivor may receive heartbeat packets")
		if packet.player==monster then monsterSnapshot = packet.snapshot end
	end
	return monsterSnapshot
end
local function strength() local s=tick(); return if s[1] then s[1].strength else 0 end
target:SetAttribute("Fear",100); assert(#tick()==0,"replicated attribute is not authority")
fears[target]=25; assert(#tick()==0,"threshold")
fears[target]=26; local low=strength(); local lowBPM=tick()[1].bpm
local targetSelfPackets = {}
for _, packet in remote.packets do if packet.player == target then targetSelfPackets = packet.snapshot end end
assert(#targetSelfPackets == 1 and targetSelfPackets[1].player == target, "survivor hears only their own heartbeat")
fears[target]=60; local middle=strength(); local midBPM=tick()[1].bpm
fears[target]=100; local high=strength(); local highBPM=tick()[1].bpm
assert(low>0 and low<middle and middle<high)
assert(lowBPM<midBPM and midBPM<highBPM and highBPM==cfg.MaxBPM,"fear drives beat interval")
blocked=true; local wall=strength(); assert(wall>0 and wall<high,"wall attenuates without suppressing")
blocked=false
targetRoot.Position=vec(80); assert(strength()<high,"distance attenuation")
targetRoot.Position=vec(cfg.MaxRange); local raysBefore=raycasts; assert(strength()==0 and raysBefore==raycasts,"range before raycast")
targetRoot.Position=vec(12)
local scaling=loadModule("StatScaling")
targetRoot.AssemblyLinearVelocity=vec(scaling.WalkSpeed(target)*2); assert(strength()>high,"sprint")
targetRoot.AssemblyLinearVelocity=vec(scaling.WalkSpeed(target)*0.4); assert(strength()<high,"crouch")
targetRoot.AssemblyLinearVelocity=vec()
targetHum.Health=35; assert(strength()>high,"injury"); targetHum.Health=100
target:SetAttribute(scaling.AttributePrefix.."Furtividade",100); assert(strength()<high,"existing stealth stat")
target:SetAttribute(scaling.AttributePrefix.."Furtividade",nil)
fears[other]=80; fears[spy]=100; assert(#tick()==2,"multiple survivors, spy excluded")
for _, packet in remote.packets do assert(packet.player ~= spy, "spy must not receive survivor heartbeat") end
target.Character:SetAttribute("PowerFearHidden",true); assert(#tick()==1,"cloak respected")
target.Character:SetAttribute("PowerFearHidden",false)
targetHum.Health=0; assert(#tick()==1,"death"); targetHum.Health=100
target:SetAttribute("Role",config.Roles.Spy); assert(#tick()==1,"role change")
target:SetAttribute("Role",config.Roles.Survivor)
target:SetAttribute("Eliminado",true); assert(#tick()==1); target:SetAttribute("Eliminado",false)
target:SetAttribute("CharacterSelectOpen",true); assert(#tick()==1); target:SetAttribute("CharacterSelectOpen",false)
active=false; assert(#tick()==0); active=true
local oldCharacter=target.Character; character(target,12); assert(tick()[1].character~=oldCharacter,"respawn identity")
round.RoundEnded:Fire(); assert(#remote.packets[#remote.packets].snapshot==0)
print("PASS heartbeat server: private fear, range, walls, stealth, movement, injury, recipients, lifecycle")

-- Asset denied -> fallback; manual template -> only inert geometry is published.
local manual=object("Model"); manual.Name=cfg.TemplateName; manual.Parent=serverStorage
local part=object("Part"); part.Parent=manual
local malicious=object("Script"); malicious.Parent=part
local mesh=object("DataModelMesh"); mesh.Parent=part
loadModule("HeartbeatAsset").Init()
local template=storage:FindFirstChild(cfg.AssetsFolder):FindFirstChild(cfg.TemplateName)
assert(#template:GetChildren()==1 and #template:GetChildren()[1]:GetChildren()==1)
assert(template:GetChildren()[1]:GetChildren()[1].ClassName=="DataModelMesh")
print("PASS heartbeat asset: denied loading is nonblocking, manual template sanitized")

players.LocalPlayer=monster
local pg=object("PlayerGui"); pg.Parent=monster
local assetFolder=storage:FindFirstChild(cfg.AssetsFolder); assetFolder.Parent=nil -- exercise procedural fallback
loadModule("HeartbeatController")
local function live(name)
	local result={}; for _,o in made do if o.Name==name and o.Parent and not o.destroyed then table.insert(result,o) end end; return result
end
local function send(snapshot) remote.OnClientEvent:Fire(monster.Character,snapshot) end
local function entry(p,strengthValue)
	return {player=p,character=p.Character,strength=strengthValue or 0.7,bpm=120,tension=0.8}
end
local function frames(seconds,hz)
	for _=1,math.ceil(seconds*hz) do now+=1/hz; render:Fire(1/hz) end
end
send({entry(target),entry(other)}); send({entry(target),entry(other)})
assert(#live("Heartbeat")==2 and #live("LocalHeartbeatHeart")==2 and render:Count()==1,"no duplicates")
frames(0.2,60)
local sound=live("Heartbeat")[1]
assert(sound.plays>0 and sound.Parent.ClassName=="Attachment" and sound.Parent.Parent.Parent==world,"3D sound")
assert(live("LocalHeartbeatHeart")[1].Parent==world and live("LocalHeartbeatHeart")[1].scale > 0,
	"heart is a physical model at the chest")
assert(live("LocalHeartbeatHeartGlow")[1].DepthMode=="AlwaysOnTop")
assert(live("LocalHeartbeatAura")[1].DepthMode=="AlwaysOnTop")
local volume=sound.Volume
send({entry(target,0.01),entry(other)}); frames(0.05,60)
assert(sound.Volume<volume and sound.Volume>0,"sound remains audible while fear falls")
local playsBeforeLoad = sound.plays
sound.IsLoaded = false
frames(0.3,60)
assert(sound.plays > playsBeforeLoad, "audio play must not wait for IsLoaded")
sound.IsLoaded = true
local lit,dark=false,false
for _=1,60 do frames(1/60,60); local a=live("LocalHeartbeatAura")[1]; lit=lit or a.Enabled; dark=dark or not a.Enabled end
assert(lit and dark,"pulses never become a permanent marker")
send({}); frames(cfg.FadeOut/2,30); assert(#live("Heartbeat")==2,"fade not abrupt")
frames(cfg.FadeOut,30); assert(#live("Heartbeat")==0 and render:Count()==0,"fade cleanup")
assetFolder.Parent=storage -- subsequent contacts use actual sanitized template
-- 20 Hz/mobile-like cadence and reentry reuse.
send({entry(target)}); frames(0.1,20); send({}); frames(0.1,20); send({entry(target)})
assert(#live("Heartbeat")==1,"reentry reuses effect")
frames(0.15,20); target.Character:FindFirstChildOfClass("Humanoid").Health=0
frames(0.05,20); assert(#live("Heartbeat")==0,"death immediate")
character(target,12); send({entry(target)}); frames(0.1,20)
local previous=target.Character; character(target,12); frames(0.05,20)
assert(#live("Heartbeat")==0,"old character cleaned on respawn")
send({{player=target,character=previous,strength=1,bpm=100,tension=1}}); assert(#live("Heartbeat")==0)
send({entry(target)}); frames(cfg.SnapshotTimeout+cfg.FadeOut+0.2,20)
assert(#live("Heartbeat")==0,"stale stream cannot mark forever")
send({entry(target)}); monster:SetAttribute("Role",config.Roles.Survivor)
assert(#live("Heartbeat")==0); send({entry(target)}); assert(#live("Heartbeat")==0,"survivor never renders")
monster:SetAttribute("Role",config.Roles.Monster)
send({entry(target)}); remotes.RoundEnded.OnClientEvent:Fire(); assert(#live("Heartbeat")==0)
send({entry(target)}); players.PlayerRemoving:Fire(target); assert(#live("Heartbeat")==0)
send({entry(other)}); monster.CharacterRemoving:Fire(); assert(#live("Heartbeat")==0)
send({entry(other)}); monster.Character:FindFirstChildOfClass("Humanoid").Health=0
frames(0.05,20); assert(#live("Heartbeat")==0,"monster death")
monster.Character:FindFirstChildOfClass("Humanoid").Health=100
send({entry(other)}); other:SetAttribute("Role",config.Roles.Spy)
frames(0.05,20); assert(#live("Heartbeat")==0,"target stops being survivor")
other:SetAttribute("Role",config.Roles.Survivor)
send({entry(other)}); other.Character:FindFirstChild("HumanoidRootPart").Position=vec(cfg.MaxRange+1)
frames(cfg.FadeOut+0.1,20); assert(#live("Heartbeat")==0,"local range exit fades")
other.Character:FindFirstChild("HumanoidRootPart").Position=vec(20)
-- One low-FPS frame cannot cause a catch-up burst of sounds.
send({entry(other)}); frames(0.1,20)
local slowSound=live("Heartbeat")[1]; local playCount=slowSound.plays
now+=0.9; render:Fire(0.9); assert(slowSound.plays<=playCount+1)
remotes.RoundEnded.OnClientEvent:Fire()
local smooth20,smooth60=0,0
for _=1,20 do smooth20=rules.Smooth(smooth20,1,1/20,cfg) end
for _=1,60 do smooth60=rules.Smooth(smooth60,1,1/60,cfg) end
assert(math.abs(smooth20-smooth60)<1e-6,"frame-rate independent smoothing")
print("PASS heartbeat client: local 3D audio/model/aura, pulse gaps, fade, duplicates, stale packets, death/respawn/role/exit, 20/60 Hz")
