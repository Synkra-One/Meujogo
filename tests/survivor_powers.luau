-- Modules injected by runner. Authority/timing tests, not a physics simulation.
local function signal()
	local s = { listeners = {} }
	function s:Connect(fn)
		local c = { active = true, fn = fn }
		function c:Disconnect() self.active = false end
		table.insert(self.listeners, c); return c
	end
	function s:Fire(...) for _, c in table.clone(self.listeners) do if c.active then c.fn(...) end end end
	return s
end
local vm = {}
local function vec(x,y,z) return setmetatable({ X=x, Y=y, Z=z, kind="Vector3" }, vm) end
vm.__add = function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vm.__sub = function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vm.__mul = function(a,b) return vec(a.X*b,a.Y*b,a.Z*b) end
vm.__index = function(v,k)
	if k == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
	if k == "Unit" then return v * (1/v.Magnitude) end
	if k == "Dot" then return function(_,b) return v.X*b.X+v.Y*b.Y+v.Z*b.Z end end
end
local cm = {}
local function cf(a,b,c)
	return setmetatable({ Position = if type(a)=="table" then a else vec(a or 0,b or 0,c or 0), LookVector=vec(0,0,-1) },cm)
end
cm.__index = {
	PointToObjectSpace = function(a,b) return b-a.Position end,
	VectorToObjectSpace = function(_,b) return b end,
	VectorToWorldSpace = function(_,b) return b end,
	ToObjectSpace = function(a,b) return cf(b.Position-a.Position) end,
}
cm.__mul = function(a,b) return cf(a.Position+b.Position) end
local object
object = function(class)
	local methods = {}
	local fields = { ClassName=class, Name=class, children={}, attributes={}, changed={}, _instance=true,
		Destroying=signal(), ChildAdded=signal(), DescendantAdded=signal(), DescendantRemoving=signal(),
		CharacterAdded=signal(), CharacterRemoving=signal(), PlayerAdded=signal(), PlayerRemoving=signal(),
		Touched=signal(), PromptButtonHoldBegan=signal(), PromptButtonHoldEnded=signal(), Triggered=signal() }
	function methods:IsA(c) return c==class or (class=="Part" and c=="BasePart") end
	function methods:GetAttribute(k) return fields.attributes[k] end
	function methods:SetAttribute(k,v)
		local old=fields.attributes[k]; fields.attributes[k]=v
		if old~=v and fields.changed[k] then fields.changed[k]:Fire() end
	end
	function methods:GetAttributeChangedSignal(k)
		fields.changed[k]=fields.changed[k] or signal(); return fields.changed[k]
	end
	function methods:GetChildren() return table.clone(fields.children) end
	function methods:GetDescendants()
		local list={}
		for _,child in fields.children do table.insert(list,child); for _,d in child:GetDescendants() do table.insert(list,d) end end
		return list
	end
	function methods:FindFirstChild(k,recursive)
		for _,child in (if recursive then self:GetDescendants() else fields.children) do if child.Name==k then return child end end
		return nil
	end
	function methods:FindFirstChildOfClass(k)
		for _,child in fields.children do if child:IsA(k) then return child end end; return nil
	end
	function methods:IsDescendantOf(parent)
		local p=self.Parent; while p do if p==parent then return true end; p=p.Parent end; return false
	end
	function methods:Destroy() self.Destroying:Fire(); self.Parent=nil; self.destroyed=true end
	function methods:CanSetNetworkOwnership() return not self.Anchored end
	function methods:GetNetworkOwnershipAuto() return self.autoOwner end
	function methods:GetNetworkOwner() return self.owner end
	function methods:SetNetworkOwner(owner) self.owner=owner; self.autoOwner=false end
	function methods:SetNetworkOwnershipAuto() self.autoOwner=true end
	function methods:GetStateEnabled() return self.jumpEnabled~=false end
	function methods:SetStateEnabled(_,value) self.jumpEnabled=value end
	function methods:ChangeState(state) self.state=state end
	function methods:TakeDamage(amount) self.Health=math.max(0,self.Health-amount) end
	function methods:GetPivot() return self:FindFirstChild("HumanoidRootPart").CFrame end
	function methods:PivotTo(value) self:FindFirstChild("HumanoidRootPart").CFrame=value end
	return setmetatable({}, {
		__index=function(_,k) return methods[k] or fields[k] end,
		__newindex=function(self,k,v)
			if k=="Parent" then
				local old=fields.Parent
				if old then local i=table.find(old.children,self); if i then table.remove(old.children,i) end end
				fields.Parent=v
				if v then table.insert(v.children,self) end
			elseif k=="CFrame" then fields.CFrame=v; fields.Position=v.Position
			elseif k=="Position" then fields.Position=v; fields.CFrame=cf(v)
			else fields[k]=v end
		end,
	})
end
local now, active, randomValue = 100, true, 0.2
local world=object("Workspace")
local players=object("Players")
local list={}
function players:GetPlayers() return table.clone(list) end
function players:GetPlayerFromCharacter(c) for _,p in list do if p.Character==c then return p end end; return nil end
function world:GetServerTimeNow() return now end
world.Terrain=object("Terrain")
local obstacle, occupied, groundAvailable=false,false,true
function world:Raycast(origin,delta)
	if obstacle then return { Distance=1,Position=origin,Normal=vec(0,1,0),Material="Rock" } end
	if delta.Y < -4 and groundAvailable then return { Position=vec(origin.X,0,origin.Z),Normal=vec(0,1,0),Material="Grass" } end
	return nil
end
function world:Blockcast(origin,_,delta)
	if obstacle then return { Distance=1, Position=origin.Position+delta } end; return nil
end
function world:GetPartBoundsInBox() return if occupied then { object("Part") } else {} end
local heartbeat=signal()
local remoteMessages={}
local remotes=setmetatable({}, {__index=function(t,k)
	local r={OnServerEvent=signal(),OnClientEvent=signal()}
	function r:FireClient(player,...) table.insert(remoteMessages,{remote=k,player=player,args={...}}) end
	function r:FireAllClients(...) table.insert(remoteMessages,{remote=k,args={...}}) end
	rawset(t,k,r); return r
end})
local function event() local s=signal(); return {Event=s,Fire=function(_,...) s:Fire(...) end} end
local round={RoundPrepared=event(),RoundEnded=event(),IsRoundActive=function() return active end}
local moduleNames=setmetatable({}, {__index=function(_,k) return k end})
local services={Players=players,Workspace=world,RunService={Heartbeat=heartbeat},
	ReplicatedStorage={Modules=moduleNames},TweenService={},Debris={AddItem=function() end}}
local modules={ Remotes=remotes,RoundManager=round,
	MatchStateService={IsGameplayEnabled=function(p) return p.Parent==players and p:GetAttribute("InRound")==true and p:GetAttribute("ExtractionBoarded")~=true end},
	GameConfig={Roles={Survivor="Sobrevivente",Spy="Espiao",Monster="Monstro"}, RadioObjective={SuccessChance=0.2,RescueCountdownDuration=60},
		Health={Max=100,MonsterMax=1000,MonsterMinimum=1,CombatAnimationsEnabled=false,
			HurtIdleAnimationId="",HurtWalkAnimationId="",DeathAnimationId="",
			RegenPerSecond=2,RegenDelayAfterDamage=6,DisableRobloxDefaultRegen=true},
		Monster={CombatStates={Normal="Normal",Weakened="Enfraquecido",Vulnerable="Vulneravel"}}},
	ItemRegistry={Items={Tocha={Rarity="Rara",DisplayName="Tocha"}}},
	SafeAttribute={Get=function(o,k) return o:GetAttribute(k) end},
	Elimination={IsEliminated=function(p) return p:GetAttribute("Eliminado")==true end,
		Eliminate=function(p) p:SetAttribute("Eliminado",true) end},
	StatScaling={DamageDealtMultiplier=function() return 1 end,DamageTakenMultiplier=function() return 1 end, RepairMultiplier=function() return 1 end},
	-- RadioSiteSystem é preenchido mais abaixo, depois que `tower` existe.
}
local enum=setmetatable({}, {__index=function(t,k) local v=setmetatable({}, {__index=function(_,n) return n end}); rawset(t,k,v); return v end})
local environment=setmetatable({
	game={GetService=function(_,name) return assert(services[name],name) end}, workspace=world,script={Parent=moduleNames},
	Vector3={new=vec,zero=vec(0,0,0)},CFrame={new=cf,lookAt=function(p) return cf(p) end},
	Enum=enum,Color3={fromRGB=function(...) return {...} end},
	RaycastParams={new=function() return {} end},OverlapParams={new=function() return {} end},
	Random={new=function() return {NextNumber=function() return randomValue end} end},
	typeof=function(v) return if type(v)=="table" then (if v._instance then "Instance" else v.kind or "table") else type(v) end,
	Instance={new=function(class) return if class=="BindableEvent" then event() else object(class) end},
	task={defer=function(fn,...) fn(...) end},
}, {__index=getfenv()})
local function load(name)
	if modules[name] then return modules[name] end
	local chunk=assert(loadstring(assert(sources[name],name),name)); setfenv(chunk,environment)
	modules[name]=chunk(); return modules[name]
end
environment.require=load
local function player(id,role,x)
	local p=object("Player"); p.Name=id; p.UserId=#list+1; p.Parent=players
	p:SetAttribute("Role",role or "Sobrevivente"); p:SetAttribute("InRound",true); p:SetAttribute("CharacterId",id)
	local c=object("Model"); c.Parent=world; p.Character=c
	local h=object("Humanoid"); h.Parent=c; h.Health=100; h.MaxHealth=100; h.WalkSpeed=16; h.HipHeight=0; h.FloorMaterial="Grass"
	local root=object("Part"); root.Name="HumanoidRootPart"; root.Parent=c; root.Position=vec(x or 0,3,0); root.Size=vec(2,2,1)
	root.AssemblyLinearVelocity=vec(0,0,0); root.owner=p; root.autoOwner=true
	local leg=object("Part"); leg.Name="Left Leg"; leg.Size=vec(1,2,1); leg.Parent=c
	table.insert(list,p); return p,c,h,root
end
local rafael,rc,rh,rr=player("RafaelMonteiro")
local diego,dc,dh,dr=player("DiegoFerreira",nil,30)
local marina,mc,mh,mr=player("MarinaAlbuquerque",nil,60)
local kevin,kc,kh,kr=player("KevinNakamura",nil,90)
local sofia,sc,sh,sr=player("SofiaRibeiro",nil,120)
local bruno,bc,bh,br=player("BrunoCarvalho",nil,150)
local camila,cc,ch,cr=player("CamilaDuarte",nil,180)
local monster,monsterC,monsterH,monsterR=player("Jason","Monstro",200)
local spy,spyC,spyH,spyR=player("Espiao","Espiao",220)
local rare=object("Part"); rare.Name="Tocha"; rare.Position=vec(185,0,0); rare.Parent=world
local tower=object("Part"); tower.Name="TorreDeRadio"; tower.Position=vec(50,3,0); tower.Parent=world
local status=load("SurvivorPowerStatus")
local damage=load("DamageSystem")
local radio=load("RadioObjective")
-- Fake RadioSiteSystem: o módulo real puxa WeaponSystem/AssetRegistry/GameConfig
-- inteiros só pra isto, então aqui só o contrato que SurvivorPowerSystem usa
-- (ApplyPowerRepair) é reproduzido: só funciona pra quem segura o prompt da
-- torre agora, e só depois que as 3 peças já foram creditadas (visível pelo
-- próprio remote de progresso que RadioObjective já emite).
do
	local holder = nil
	local prompt = object("ProximityPrompt")
	prompt.Parent = tower
	prompt.PromptButtonHoldBegan:Connect(function(p) holder = p end)
	prompt.PromptButtonHoldEnded:Connect(function() holder = nil end)
	modules.RadioSiteSystem = {
		ApplyPowerRepair = function(player)
			if holder ~= player then return nil end
			local piecesReady = false
			for _, m in remoteMessages do
				if m.remote == "ObjectiveProgress" and m.args[1] == "RadioPecas" and m.args[2] == m.args[3] then
					piecesReady = true
				end
			end
			if not piecesReady then return nil end
			remotes.ObjectiveProgress:FireAllClients("RadioSintonia", 25, 100)
			return tower
		end,
	}
end
-- Fake RepairMinigameSystem: ninguém está com um reparo de precisão aberto
-- neste cenário, então ApplyPowerBoost sempre recusa e o Conserto Relâmpago
-- cai nos alvos atuais (rádio e reparo), que é o que este arquivo testa.
-- A cobertura do próprio minigame está em tests/repair_minigame.luau.
modules.RepairMinigameSystem = { ApplyPowerBoost = function() return nil end }
local system=load("SurvivorPowerSystem")
radio.Init(); system.Init(); system.Init()
local function tick(seconds) now+=seconds; heartbeat:Fire(seconds) end
local function use(p,slot) tick(0.2); remotes.UseSurvivorPower.OnServerEvent:Fire(p,slot) end
local function reset() round.RoundPrepared:Fire(); obstacle=false; occupied=false; groundAvailable=true end
local function ready(p,slot) return p:GetAttribute("SurvivorPowerReadyAt"..slot) or 0 end

-- Real remote authority: malformed slots, role, round, selection, restrained/dead.
use(rafael,"1"); use(rafael,0/0); use(rafael,3); assert(ready(rafael,1)==0)
use(monster,1); use(spy,2); assert(ready(monster,1)==0 and ready(spy,2)==0)
active=false; use(rafael,1); assert(ready(rafael,1)==0); active=true
rafael:SetAttribute("CharacterSelectOpen",true); use(rafael,1); assert(ready(rafael,1)==0); rafael:SetAttribute("CharacterSelectOpen",false)
rc:SetAttribute("GrabLocked",true); use(rafael,1); assert(ready(rafael,1)==0); rc:SetAttribute("GrabLocked",false)
rh.Health=0; use(rafael,1); assert(ready(rafael,1)==0); rh.Health=100
use(rafael,1); local q=ready(rafael,1); assert(q==now+90 and rc:GetAttribute("PowerSpeedMultiplier")==2)
assert(rc:GetAttribute("PowerInfiniteStamina")==true)
use(rafael,1); assert(ready(rafael,1)==q)
use(rafael,2); assert(ready(rafael,2)==now+60 and ready(rafael,1)==q)
assert(rr.owner==nil and rc:GetAttribute("PowerMoving"))
status.Stun(rc,3); assert(rc:GetAttribute("PowerMoving")==nil and rc:GetAttribute("PowerStunned"))
tick(3.1); assert(rh.WalkSpeed==16 and rh.jumpEnabled and rr.autoOwner)
tick(2); assert(rc:GetAttribute("PowerSpeedMultiplier")==nil and rc:GetAttribute("PowerInfiniteStamina")==nil)
print("PASS: request guards, independent authoritative cooldowns, expiration and movement/stun ownership restoration")

reset(); use(marina,1); assert(status.BeginAttack(marina)); assert(not status.BeginAttack(marina))
status.Set(mc,"PowerPreciseShot",true,8); local shot=status.BeginAttack(marina)
local applied=damage.Apply(monsterC,10,{Source=marina,Empowered=shot})
assert(applied==30 and monsterH.Health==70 and monsterC:GetAttribute("PowerStunned"))
tick(2.1); assert(monsterC:GetAttribute("PowerStunned")==nil and monsterH.WalkSpeed==16)
status.Set(mc,"PowerPreciseShot",true,8); tick(8.1); assert(not status.BeginAttack(marina))
reset(); use(bruno,2); assert(not status.Stun(bc,3)); assert(damage.Apply(bc,20,{Source=monster})==10)
tick(5.1); assert(damage.Apply(bc,20,{Source=monster})==20)
reset(); use(camila,1); randomValue=0.1; assert(damage.Apply(cc,20,{Source=monster})==0)
assert(damage.Apply(cc,20,{Source=monster})==20)
reset(); use(camila,1); randomValue=0.9; assert(damage.Apply(cc,20,{Source=monster})==20)
assert(not status.Active(cc,"PowerLuckyDodge"))
print("PASS: next-attack consumption, 3x damage + 2s stun, 50% damage reduction, stun immunity and one-shot lucky dodge")

reset(); br.Position=vec(124,3,0); bh.Health=20; sh.Health=20
use(sofia,1); assert(bh.Health==70 and sh.Health==70 and ready(sofia,1)==now+200)
use(sofia,2); assert(bc:GetAttribute("Imune")==true and sc:GetAttribute("Imune")==nil)
assert(damage.Apply(bc,99,{Source=monster})==0 and not status.Stun(bc,3))
assert(damage.Heal(bc,5)==5); tick(4.1); assert(bc:GetAttribute("Imune")==nil)
reset(); br.Position=vec(150,3,0); use(sofia,2); assert(sc:GetAttribute("Imune"))
print("PASS: area heal based on max health, closest ally/self shield, damage/stun rejection and shield expiry")

reset(); dr.Position=vec(49,3,0); local prompt=tower:FindFirstChildOfClass("ProximityPrompt")
prompt.PromptButtonHoldBegan:Fire(diego); use(diego,1); assert(ready(diego,1)==0)
radio.CollectPiece("Antena"); radio.CollectPiece("Bateria"); radio.CollectPiece("Transmissor")
prompt.PromptButtonHoldBegan:Fire(diego); use(diego,1); assert(ready(diego,1)==now+240)
assert(remoteMessages[#remoteMessages].remote=="SurvivorPowerFX")
local progress
for _,m in remoteMessages do if m.remote=="ObjectiveProgress" and m.args[1]=="RadioSintonia" then progress=m.args[2] end end
assert(progress==25)
reset(); prompt.PromptButtonHoldEnded:Fire(diego); use(diego,1); assert(ready(diego,1)==0)
print("PASS: real radio repair APIs add 25%, validate current interaction and preserve missing-piece requirements")

reset(); obstacle=true; use(kevin,2); assert(ready(kevin,2)==0); obstacle=false
occupied=true; use(kevin,2); assert(ready(kevin,2)==0); occupied=false
groundAvailable=false; use(kevin,2); assert(ready(kevin,2)==0); groundAvailable=true
local old=kr.Position; use(kevin,2); assert(ready(kevin,2)==now+100 and math.abs(kr.Position.Z-old.Z+15)<0.01)
use(kevin,1); assert(kc:GetAttribute("PowerFearHidden")); tick(8.1); assert(kc:GetAttribute("PowerFearHidden")==nil)
reset(); use(diego,2); local trap=world:FindFirstChild("ArmadilhaImprovisada"); assert(trap and not trap.CanCollide and trap.Transparency==1)
monsterR.Position=dr.Position; tick(0.2); assert(trap.destroyed and status.Active(monsterC,"PowerStunned")); tick(3.1)
reset(); use(diego,2); trap=world:FindFirstChild("ArmadilhaImprovisada"); monsterR.Position=vec(200,3,0); tick(60.1); assert(trap.destroyed)
reset(); use(bruno,1); monsterR.Position=br.Position+vec(0,0,-3); tick(0.1); assert(status.Active(monsterC,"PowerStunned")); tick(0.6); assert(br.autoOwner)
print("PASS: blocked/occupied/air teleport rejection, safe 15-stud teleport, cloak expiry, trap lifetime/hostile trigger and charge collision")

reset(); use(marina,2); use(camila,2); tick(0.2)
local seen={}
for _,m in remoteMessages do
	if m.remote=="UseSurvivorPower" and m.args[1]=="Direction" then
		assert(#m.args==4 and m.args[3].kind=="Vector3" and math.abs(m.args[3].Magnitude-1)<1e-6)
		seen[m.args[2]]=true
	end
end
assert(seen.InstintoDeCacadora and seen.IntuicaoSortuda)
reset(); rare.Parent=cc; use(camila,2); assert(ready(camila,2)==0)
rare.Parent=world
use(kevin,1); use(diego,2); local oldCharacter=kc
kevin.CharacterRemoving:Fire(oldCharacter); assert(oldCharacter:GetAttribute("PowerFearHidden")==nil)
active=false; round.RoundEnded:Fire(); assert(world:FindFirstChild("ArmadilhaImprovisada")==nil)
for _,p in list do assert(ready(p,1)==0 and ready(p,2)==0) end
print("PASS: private direction-only packets, inventory exclusion, respawn and round cleanup")
print("All survivor power scenarios passed (simulated services; Studio playtest still required).")
