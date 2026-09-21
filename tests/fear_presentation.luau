-- All modules are real. Services, rendering, loading and physics are simulated.
local function near(a,b) assert(math.abs(a-b)<1e-6, tostring(a).." != "..tostring(b)) end
local function signal()
	local s={listeners={}}
	function s:Connect(f)
		local c={Connected=true,f=f}
		function c:Disconnect() self.Connected=false end
		table.insert(self.listeners,c); return c
	end
	function s:Once(f)
		local c; c=self:Connect(function(...) c:Disconnect(); f(...) end); return c
	end
	function s:Fire(...) for _,c in table.clone(self.listeners) do if c.Connected then c.f(...) end end end
	function s:Count() local n=0; for _,c in self.listeners do if c.Connected then n+=1 end end; return n end
	return s
end
local made={}
local function object(class)
	local props={ClassName=class,Name=class,children={},attributes={},attributeSignals={},propertySignals={},
		ChildAdded=signal(),Destroying=signal(),Destroyed=false}
	local methods={}
	local self=setmetatable({}, {
		__index=function(_,key) return methods[key] or props[key] end,
		__newindex=function(t,key,value)
			local old=props[key]; props[key]=value
			if key=="Parent" then
				if old then local i=table.find(old.children,t); if i then table.remove(old.children,i) end end
				if value then table.insert(value.children,t); value.ChildAdded:Fire(t) end
			end
			if old~=value and props.propertySignals[key] then props.propertySignals[key]:Fire() end
		end,
	})
	function methods:IsA(c) return c==class or (c=="BasePart" and class=="Part") end
	function methods:GetAttribute(k) return props.attributes[k] end
	function methods:SetAttribute(k,v)
		local old=props.attributes[k]; props.attributes[k]=v
		if old~=v and props.attributeSignals[k] then props.attributeSignals[k]:Fire() end
	end
	function methods:GetAttributeChangedSignal(k)
		if not props.attributeSignals[k] then props.attributeSignals[k]=signal() end
		return props.attributeSignals[k]
	end
	function methods:GetPropertyChangedSignal(k)
		if not props.propertySignals[k] then props.propertySignals[k]=signal() end
		return props.propertySignals[k]
	end
	function methods:FindFirstChild(k) for _,c in props.children do if c.Name==k then return c end end end
	function methods:WaitForChild(k) return assert(self:FindFirstChild(k),k) end
	function methods:FindFirstChildOfClass(k) for _,c in props.children do if c:IsA(k) then return c end end end
	function methods:Destroy()
		if props.Destroyed then return end
		props.Destroyed=true; props.Destroying:Fire()
		for _,c in table.clone(props.children) do c:Destroy() end
		self.Parent=nil
	end
	if class=="Sound" then
		props.SoundId=""; props.Volume=0; props.IsPlaying=false; props.Ended=signal(); props.PlaybackSpeed=1; props.plays=0
		function methods:Play() assert(self.SoundId~="" and self.SoundId~="rbxassetid://0"); self.IsPlaying=true; self.plays+=1 end
		function methods:Stop() self.IsPlaying=false end
	elseif class=="Humanoid" then
		props.Health=100; props.Died=signal(); props.FloorMaterial="Ground"; props.Sit=false; props.State="Running"
		function methods:GetState() return self.State end
	elseif class=="Animator" then
		props.AnimationPlayed=signal(); props.tracks={}; props.loads=0
		function methods:GetPlayingAnimationTracks()
			local list={}; for _,t in props.tracks do if t.IsPlaying then table.insert(list,t) end end; return list
		end
		function methods:LoadAnimation(animation)
			assert(animation.AnimationId~=""); props.loads+=1
			local track=object("AnimationTrack")
			track.Length=1; track.IsPlaying=false; track.Priority="Core"; track.Animation=animation
			function track:Play() self.IsPlaying=true; props.AnimationPlayed:Fire(self) end
			function track:Stop() self.IsPlaying=false end
			table.insert(props.tracks,track); return track
		end
	end
	table.insert(made,self); return self
end
local function vec(x,y,z) return {X=x,Y=y,Z=z,Magnitude=math.sqrt(x*x+y*y+z*z)} end
local cframeMeta={}
cframeMeta.__mul=function(a,b) return a end
local function cframe() return setmetatable({},cframeMeta) end
local function bindable() local s=signal(); return {Event=s,Fire=function(_,...) s:Fire(...) end} end
local world,storage,soundService=object("Workspace"),object("ReplicatedStorage"),object("SoundService")
world.CurrentCamera=object("Camera"); world.CurrentCamera.FieldOfView=77
local otherBlur=object("BlurEffect"); otherBlur.Name="OtherBlur"; otherBlur.Size=9; otherBlur.Parent=world.CurrentCamera
local players=object("Players"); players.PlayerAdded=signal(); players.PlayerRemoving=signal()
local p=object("Player"); p.Name="Survivor"; p.Parent=players
local pg=object("PlayerGui"); pg.Parent=p
p.CharacterAdded=signal(); p.CharacterRemoving=signal()
players.LocalPlayer=p
function players:GetPlayers() return {p} end
local function character()
	local c=object("Model"); c.Parent=world
	local h=object("Humanoid"); h.Parent=c
	local root=object("Part"); root.Name="HumanoidRootPart"; root.Position=vec(0,0,0); root.AssemblyLinearVelocity=vec(0,0,0); root.Parent=c
	local animator=object("Animator"); animator.Parent=h
	return c,h,root,animator
end
local c,h,root,animator=character(); p.Character=c
local heartbeat=signal()
local names=setmetatable({}, {__index=function(_,k) return k end}); storage.Modules=names
local round={PhaseChanged=bindable(),RoundPrepared=bindable(),RoundEnded=bindable(),IsRoundActive=function() return true end}
local fear={PanicSoundTriggered=bindable(),TripTriggered=bindable()}
local remote={OnClientEvent=signal(),OnServerEvent=signal(),sent=0}
function remote:FireClient(player,...) self.sent+=1; assert(player==p); self.OnClientEvent:Fire(...) end
local remotes={FearPresentation=remote,RoundEnded={OnClientEvent=signal()}}
local prompts={PromptButtonHoldBegan=signal(),PromptButtonHoldEnded=signal(),PromptHidden=signal(),PromptTriggered=signal()}
local services={Players=players,ReplicatedStorage=storage,RunService={Heartbeat=heartbeat},SoundService=soundService,Workspace=world,
	ProximityPromptService=prompts}
local delayed,logs={},{}
local modules={Remotes=remotes,RoundManager=round,FearSystem=fear,LoadoutData={GetPerk=function() return nil end},
	AssetRegistry={Sounds={PhaseMusic={}}}}
local env=setmetatable({
	game={GetService=function(_,name) return assert(services[name],name) end},script={Parent=names},
	Instance={new=object}, Vector3={new=vec}, Color3={new=function(...) return {...} end,fromRGB=function(...) return {...} end},
	CFrame={new=cframe,Angles=cframe},
	UDim2={fromScale=function(...) return {...} end},NumberSequence={new=function(...) return {...} end},
	NumberSequenceKeypoint={new=function(...) return {...} end},
	Enum={AnimationPriority={Core="Core",Movement="Movement",Action="Action",Action2="Action2",Action3="Action3",Action4="Action4"},
		Material={Air="Air",Water="Water"},HumanoidStateType={Running="Running",RunningNoPhysics="RunningNoPhysics"},
		RollOffMode={InverseTapered="InverseTapered"},
		KeyCode={E="E",X="X",ButtonX="ButtonX",ButtonB="ButtonB"}},
	Random={new=function() return {NextNumber=function() return 0 end,NextInteger=function(_,a) return a end} end},
	task={delay=function(_,f) table.insert(delayed,f) end},
	print=function(message) table.insert(logs,message) end,warn=function(message) table.insert(logs,message) end,
},{__index=getfenv()})
local function loadModule(name)
	if modules[name] then return modules[name] end
	local f=assert(loadstring(sources[name],name)); setfenv(f,env); modules[name]=f(); return modules[name]
end
env.require=loadModule
local config=loadModule("GameConfig"); local cfg=config.Fear
local rules=loadModule("FearPresentationRules")
for _,id in {"","0","rbxassetid://0","not an id","-1"} do assert(rules.AssetId(id)==nil) end
-- Synthetic IDs are interpreted only by the mocks, never uploaded or used in game.
assert(rules.AssetId("123")=="rbxassetid://123")
local last=0
for value=0,100,0.1 do
	local t=rules.Targets(value,cfg)
	assert(t.HeartbeatVolume>=last and t.HeartbeatPlaybackSpeed<=cfg.HeartbeatMaxPlaybackSpeed)
	assert(t.VignetteOpacity<=0.4 and t.BlurSize<=4 and t.FearFOVOffset==0)
	last=t.HeartbeatVolume
end
near(rules.Targets(29,cfg).HeartbeatVolume,0)
near(rules.Targets(49,cfg).VignetteOpacity,0)
near(rules.Targets(74,cfg).BlurSize,0)
near(rules.Targets(100,cfg).BlurSize,4)
for _,v in {25,50,75,90} do
	local before,after=rules.Targets(v-0.0001,cfg),rules.Targets(v+0.0001,cfg)
	for k,val in before do assert(math.abs(val-after[k])<0.0001) end
end
local smoothed=0; for _=1,20 do smoothed=rules.Smooth(smoothed,100,0.05,0.35) end
near(smoothed,rules.Smooth(0,100,1,0.35))

-- ESCURECIMENTO ANIMADO: desligado em calma, respira em pânico, nunca apaga
-- a tela. Rules.Darken é puro, então o pulso é reproduzível.
local ceiling=math.clamp(cfg.DarkenMaxOpacity,0,0.6)
near(rules.Darken(0,0,cfg),0)
near(rules.Darken(cfg.DarkenStartFear,0,cfg),0,"comeca exatamente no limiar")
near(rules.Darken(cfg.DarkenStartFear-1,12.34,cfg),0,"abaixo do limiar a camada fica desligada")
local lowest,highest=math.huge,-math.huge
for step=0,400 do
	local value=rules.Darken(cfg.MaxFear,step/40,cfg)
	assert(value>0 and value<=ceiling,"nunca passa do teto nem apaga a tela")
	lowest=math.min(lowest,value); highest=math.max(highest,value)
end
assert(highest-lowest>0.01,"a camada respira em vez de ficar estatica")
assert(highest<=ceiling+1e-9 and lowest>=ceiling*(1-math.clamp(cfg.DarkenPulseAmount,0,0.5))-1e-9)
local previousDark=-1
for value=cfg.DarkenStartFear,cfg.MaxFear,0.5 do
	-- No mesmo instante do pulso, mais medo nunca escurece menos.
	local now=rules.Darken(value,0.25,cfg)
	assert(now>=previousDark-1e-9,"monotonico no Fear")
	previousDark=now
end

-- HUD SUMINDO: proporcoes 0..1, sem pular de estado e sem esconder em calma.
local calm=rules.HudFade(0,cfg)
assert(calm.Vitals==0 and calm.Hotbar==0 and not calm.FullMapBlocked,"HUD inteiro em calma")
local panic=rules.HudFade(cfg.MaxFear,cfg)
assert(panic.Vitals==1 and panic.Hotbar==1 and panic.FullMapBlocked,"HUD some no topo")
assert(cfg.HudFadeStartFear<cfg.HudFadeFullFear and cfg.HotbarFadeStartFear<cfg.HotbarFadeFullFear,
	"limiares crescentes")
assert(cfg.HudFadeStartFear>=cfg.FearStates.Panicked-10,"so some em panico, nao em tensao normal")
near(rules.HudFade(cfg.HudFadeStartFear,cfg).Vitals,0)
near(rules.HudFade(cfg.HotbarFadeStartFear,cfg).Hotbar,0)
assert(not rules.HudFade(cfg.FullMapBlockFear-0.001,cfg).FullMapBlocked)
assert(rules.HudFade(cfg.FullMapBlockFear,cfg).FullMapBlocked)
local previousVitals,previousHotbar=-1,-1
for value=0,cfg.MaxFear,0.25 do
	local hud=rules.HudFade(value,cfg)
	assert(hud.Vitals>=previousVitals-1e-9 and hud.Hotbar>=previousHotbar-1e-9,"so esconde, nunca revela")
	assert(hud.Vitals>=0 and hud.Vitals<=1 and hud.Hotbar>=0 and hud.Hotbar<=1)
	previousVitals,previousHotbar=hud.Vitals,hud.Hotbar
end
-- O inventario e o ultimo a sair: o jogador perde a leitura calma da tela
-- antes de perder a barra de itens.
assert(cfg.HotbarFadeStartFear>=cfg.HudFadeStartFear,"mapa/folego somem antes do inventario")

local presentation=loadModule("FearPresentation")
presentation.Init(); presentation.Init()
assert(heartbeat:Count()==1 and remote.OnClientEvent:Count()==1)
local heart=soundService:FindFirstChild("FearHeartbeat")
local breath=soundService:FindFirstChild("FearBreathing")
local gui=pg:FindFirstChild("FearPresentation")
local blur=world.CurrentCamera:FindFirstChild("FearBlur")
local function tick(n) for _=1,n do heartbeat:Fire(0.05) end end
tick(20); assert(not gui.Enabled and heart.plays==0)
p:SetAttribute("Role",config.Roles.Survivor); p:SetAttribute("InRound",true)
storage:SetAttribute("MatchState","Playing"); p:SetAttribute("Fear",100); p:SetAttribute("FearState","ExtremePanic")
local count=#made
tick(60)
assert(gui.Enabled and blur.Size>3.9 and blur.Size<=4)
-- Camada de escurecimento: existe, esta atras da vinheta e reage ao Fear.
local darken=gui:FindFirstChild("FearDarken")
assert(darken and darken.ZIndex==0,"camada de escurecimento por baixo da vinheta")
assert(darken.BackgroundTransparency<1,"escurece em panico")
local darkAt100=darken.BackgroundTransparency
p:SetAttribute("Fear",0); tick(120)
assert(darken.BackgroundTransparency>darkAt100,"clareia junto com o Fear")
p:SetAttribute("Fear",100); tick(120)
assert(heart.plays==0 and breath.plays==0 and animator.loads==0,"blank assets never load/play")
assert(#made==count,"effects reused across updates")
near(world.CurrentCamera.FieldOfView,77); near(otherBlur.Size,9)
cfg.HeartbeatSoundId="123"; cfg.BreathingSoundId="456"
tick(20); assert(heart.plays==1 and breath.plays==1 and heart.Volume>0)
tick(20); assert(heart.plays==1,"loop not restarted every update")
cfg.HeartbeatSoundId=""; tick(1); assert(not heart.IsPlaying and heart.Volume==0)
p:SetAttribute("Role",config.Roles.Monster)
assert(not gui.Enabled and not breath.IsPlaying and blur.Size==0,"role cleanup is immediate")
p:SetAttribute("Role",config.Roles.Survivor); tick(40)
for _,attribute in {"InRound","CharacterSelectOpen","Eliminado"} do
	local value=if attribute=="InRound" then false else true
	p:SetAttribute(attribute,value)
	assert(not gui.Enabled and blur.Size==0 and not breath.IsPlaying,"cleanup on "..attribute)
	p:SetAttribute(attribute,if attribute=="InRound" then true else nil); tick(40)
end
remotes.RoundEnded.OnClientEvent:Fire(); assert(not gui.Enabled and blur.Size==0)
assert(darken.BackgroundTransparency==1,"nada de escurecimento residual no reset")
tick(5); assert(not gui.Enabled,"no lingering frame after RoundEnded")
storage:SetAttribute("MatchState","Intermission"); storage:SetAttribute("MatchState","Playing")
tick(40); assert(gui.Enabled)
world.CurrentCamera=object("Camera"); world.CurrentCamera.FieldOfView=66
assert(blur.Parent==world.CurrentCamera)
near(otherBlur.Size,9)

cfg.FearAnimations.FearIdle="1001"; cfg.FearAnimations.FearWalk="1002"; cfg.FearAnimations.FearRun="1003"
cfg.FearAnimations.Trip="1004"; cfg.FearAnimations.LookAround="1005"
tick(1); assert(animator.tracks[#animator.tracks].IsPlaying)
local idle=animator.tracks[#animator.tracks]
assert(idle.Animation.Name=="FearIdle" and idle.Priority=="Action")
local prompt=object("ProximityPrompt")
prompts.PromptButtonHoldBegan:Fire(prompt,p); assert(not idle.IsPlaying)
tick(10); assert(not idle.IsPlaying,"holding a prompt blocks Fear locomotion")
prompts.PromptButtonHoldEnded:Fire(prompt,p); tick(1); assert(idle.IsPlaying)
prompts.PromptTriggered:Fire(prompt,p); tick(3); assert(not idle.IsPlaying)
tick(6); assert(idle.IsPlaying,"prompt grace ends")
local pick=animator:LoadAnimation({AnimationId="2000"}); pick.Priority="Action"; pick:Play()
assert(not idle.IsPlaying,"pick action preempts immediately")
tick(3); assert(pick.IsPlaying and not idle.IsPlaying)
pick:Stop(); tick(1); assert(idle.IsPlaying)
for _,priority in {"Action2","Action3","Action4"} do
	local track=animator:LoadAnimation({AnimationId="2001"}); track.Priority=priority; track:Play()
	tick(1); assert(track.IsPlaying and not idle.IsPlaying,"weapon action wins")
	track:Stop(); tick(1)
end
local tool=object("Tool"); tool.Parent=c
assert(not idle.IsPlaying,"equipping tool suppresses Fear immediately")
remote:FireClient(p,"Trip",c,0.65); tick(1)
assert(not idle.IsPlaying,"Trip animation cannot interrupt an equipped weapon")
tool:Destroy(); root:SetAttribute("IsCrouching",true); tick(1); assert(not idle.IsPlaying)
root:SetAttribute("IsCrouching",nil)
root.AssemblyLinearVelocity=vec(6,0,0); tick(1)
assert(animator.tracks[#animator.tracks].Animation.Name=="FearWalk")
root.AssemblyLinearVelocity=vec(30,0,0); tick(1)
assert(animator.tracks[#animator.tracks].Animation.Name=="FearRun")
local loads=animator.loads
root.AssemblyLinearVelocity=vec(0,0,0); tick(1); assert(animator.loads==loads,"cached idle track reused")
remote:FireClient(p,"Trip",c,0.65); c:SetAttribute("FearTripping",true); tick(1)
local trip=animator.tracks[#animator.tracks]; assert(trip.Animation.Name=="Trip" and trip.IsPlaying)
tick(14); assert(not trip.IsPlaying,"trip presentation limited to duration")
c:SetAttribute("FearTripping",nil)
cfg.LookAroundCheckInterval=0.1; cfg.LookAroundChance=1
tick(3)
local look=animator.tracks[#animator.tracks]; assert(look.Animation.Name=="LookAround")
root.AssemblyLinearVelocity=vec(30,0,0); tick(1); assert(not look.IsPlaying,"running cancels LookAround")
h.Health=0; h.Died:Fire()
assert(blur.Size==0 and not gui.Enabled and not breath.IsPlaying)
local old=c; p.CharacterRemoving:Fire(c)
c,h,root,animator=character(); p.Character=c; p.CharacterAdded:Fire(c)
remote:FireClient(p,"Trip",old,0.65); assert(animator.loads==0,"old-character event ignored")
tick(1); assert(animator.loads==1)
presentation.Destroy(); assert(heartbeat:Count()==0 and remote.OnClientEvent:Count()==0)
assert(gui.Destroyed and heart.Destroyed and blur.Destroyed)
near(world.CurrentCamera.FieldOfView,66); near(otherBlur.Size,9)

-- Server hook consumers: no new Fear RNG or inbound requests.
local manager=loadModule("SoundManager"); manager.Init(); manager.Init()
assert(fear.TripTriggered.Event:Count()==1 and fear.PanicSoundTriggered.Event:Count()==1)
assert(remote.OnServerEvent:Count()==0)
local function countVoices()
	local n=0; for _,v in world.children do if v.Name=="FearPanicOrigin" then n+=1 end end; return n
end
fear.PanicSoundTriggered:Fire(p,root.Position,100); assert(countVoices()==0,"empty panic list creates nothing")
cfg.PanicSounds={"","0","123"}
fear.PanicSoundTriggered:Fire(p,root.Position,100)
local anchor=world:FindFirstChild("FearPanicOrigin"); local voice=anchor:FindFirstChild("FearPanic")
assert(voice.SoundId=="rbxassetid://123" and voice.IsPlaying and voice.RollOffMaxDistance==100)
fear.PanicSoundTriggered:Fire(p,vec(40,0,0),100)
assert(countVoices()==1 and voice.plays==2 and anchor.Position.X==40,"voice reused at event origin")
delayed[1](); assert(voice.IsPlaying,"old timer cannot stop a new cry")
delayed[2](); assert(not voice.IsPlaying)
local sent=remote.sent; fear.TripTriggered:Fire(p,root.Position,0.65); assert(remote.sent==sent+1)
p:SetAttribute("Role",config.Roles.Monster); assert(countVoices()==0)
fear.PanicSoundTriggered:Fire(p,root.Position,100); assert(countVoices()==0)
p:SetAttribute("Role",config.Roles.Survivor)
fear.PanicSoundTriggered:Fire(p,root.Position,100); h.Health=0; h.Died:Fire(); assert(countVoices()==0)
h.Health=100; fear.PanicSoundTriggered:Fire(p,root.Position,100)
round.RoundEnded:Fire(); assert(countVoices()==0)
players.PlayerRemoving:Fire(p); assert(p:GetAttributeChangedSignal("Role"):Count()==0)
print("PASS Part 3: smooth numerical effects, silent placeholders, reusable sounds/GUI/blur/tracks, priority gates, Trip bridge, LookAround, spatial panic pool, no inbound gameplay, cleanup and idempotent initialization")
