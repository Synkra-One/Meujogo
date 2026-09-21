-- Deterministic orchestration tests. Visual factories are doubled, controller is real.
local function signal()
	local callbacks = {}
	local result = {}
	function result:Connect(callback)
		local connection = { Connected = true }
		function connection:Disconnect() self.Connected = false end
		table.insert(callbacks, { callback, connection })
		return connection
	end
	function result:Fire(...)
		for _, pair in table.clone(callbacks) do if pair[2].Connected then pair[1](...) end end
	end
	return result
end
local clock = 100
local jobs = {}
local function advance(seconds)
	local target = clock + seconds
	while true do
		table.sort(jobs, function(a,b) return a.at < b.at end)
		if #jobs == 0 or jobs[1].at > target then break end
		local job = table.remove(jobs, 1)
		clock = job.at
		job.callback()
	end
	clock = target
end
local function delay(seconds, callback) table.insert(jobs, { at = clock + seconds, callback = callback }) end
local enums = setmetatable({}, { __index = function(t, name)
	local category = setmetatable({}, { __index = function(c, item)
		local value = { Name = item }; rawset(c, item, value); return value
	end })
	rawset(t, name, category); return category
end })
local Vector2Mock = { new = function(x,y) return { X=x or 0, Y=y or 0 } end, zero = { X=0,Y=0 } }
local UDim2Mock = {
	new = function(xs,x,ys,y) return { X={Scale=xs or 0,Offset=x or 0},Y={Scale=ys or 0,Offset=y or 0} } end,
	fromScale = function(x,y) return { X={Scale=x,Offset=0},Y={Scale=y,Offset=0} } end,
	fromOffset = function(x,y) return { X={Scale=0,Offset=x},Y={Scale=0,Offset=y} } end,
}
local nodes = {}
local function node(class, parent, properties)
	local item = { ClassName = class, Parent = parent, Children = {}, Attributes = {},
		AbsoluteSize = Vector2Mock.new(1280,720), AbsoluteCanvasSize = Vector2Mock.new(1800,1100),
		AbsolutePosition = Vector2Mock.zero, CanvasPosition = Vector2Mock.zero,
		Destroying = signal(), properties = {}, attributes = {} }
	for _, event in {"Activated","MouseEnter","MouseLeave","SelectionGained","SelectionLost"} do item[event] = signal() end
	function item:GetPropertyChangedSignal(key) self.properties[key] = self.properties[key] or signal(); return self.properties[key] end
	function item:GetAttributeChangedSignal(key) self.attributes[key] = self.attributes[key] or signal(); return self.attributes[key] end
	function item:SetAttribute(key,value)
		if self.Attributes[key] == value then return end
		self.Attributes[key] = value
		self:GetAttributeChangedSignal(key):Fire()
	end
	function item:GetAttribute(key) return self.Attributes[key] end
	function item:WaitForChild(name) return assert(self.Children[name], name) end
	function item:IsDescendantOf(ancestor) return self.Parent == ancestor or (self.Parent and self.Parent:IsDescendantOf(ancestor)) or false end
	function item:Destroy() self.Destroyed = true; self.Parent = nil end
	function item:Play() self.Played = (self.Played or 0) + 1 end
	for key,value in properties or {} do item[key] = value end
	if parent then parent.Children[item.Name or class] = item end
	if item.Name then nodes[item.Name] = item end
	return item
end
local player = node("Player",nil,{UserId=7})
node("PlayerGui",player,{Name="PlayerGui"})
local modules = {}
local registry = setmetatable({}, {__index=function(_,name) return name end})
local storage = {Modules=registry}
local input = { LastInputTypeChanged=signal(), InputChanged=signal(), MouseEnabled=true,
	MouseBehavior=enums.MouseBehavior.LockCenter, MouseIconEnabled=false }
function input:GetLastInputType() return enums.UserInputType.MouseMovement end
function input:GetFocusedTextBox() return nil end
local actions = { bound={} }
function actions:BindActionAtPriority(name,callback) self.bound[name]=callback end
function actions:UnbindAction(name) self.bound[name]=nil end
local run = { RenderStepped=signal(), Heartbeat=signal() }
local guiService = {}
local remotes = {}
for _, name in { "SelectCharacter", "CharacterRoster", "LobbyMessage" } do
	local remote = { OnClientEvent=signal(), Sent={} }
	function remote:FireServer(...) table.insert(self.Sent,{...}) end
	remotes[name]=remote
end
modules.Remotes = remotes
modules.SurvivorSelectionTheme = {
	Create=node, Frame=function(parent,name) return node("Frame",parent,{Name=name}) end,
	Label=function(parent,name,text,size) return node("TextLabel",parent,{Name=name,Text=text,TextSize=size}) end,
	Corner=function() end, Accent={},Panel={},Muted={},Text={},
	Tween=function(item,properties) for key,value in properties do item[key]=value end; return { Cancel=function() end } end,
}
modules.SurvivorSelectionAssets = {Content=function(_,value) return value end}
local cardRefs = {}
modules.SurvivorCard = {
	Create=function(parent,character,index)
		local card={Root=node("TextButton",parent,{Name=character.Id,AbsolutePosition=Vector2Mock.new(index*110,0),AbsoluteSize=Vector2Mock.new(100,90)})}
		cardRefs[character.Id]=card
		return card
	end,
	SetState=function(card,state,selected,hovered,confirmed)
		card.State,card.Selected,card.Hovered,card.Confirmed=state,selected,hovered,confirmed
	end,
}
local details
modules.SurvivorDetails = {
	Create=function(parent) details={Root=node("ScrollingFrame",parent,{}),Name=node("TextLabel",parent,{})}; return details end,
	Update=function(view,character,mode) view.Character,view.Mode=character,mode end,
}
local preview
modules.SurvivorPreview = {Create=function(parent)
	preview={Root=node("Frame",parent,{})}
	function preview.Set(id) preview.Id=id end
	function preview.Clear() preview.Id=nil end
	function preview.Step() end
	return preview
end}
modules.SurvivorBackdrop = {Create=function(parent) return {Root=node("Frame",parent,{}),Update=function() end} end}
local scriptMock = {Parent=registry,Destroying=signal()}
local services = {Players={LocalPlayer=player},ReplicatedStorage=storage,UserInputService=input,
	ContextActionService=actions,GuiService=guiService,RunService=run,Workspace={GetServerTimeNow=function() return clock end}}
local environment = setmetatable({
	game={GetService=function(_,name) return assert(services[name],name) end},script=scriptMock,
	Color3={fromRGB=function(...) return {...} end},Enum=enums,UDim2=UDim2Mock,UDim={new=function(...)return {...}end},Vector2=Vector2Mock,
	task={delay=delay,defer=function(callback) delay(0,callback) end}, os={clock=function()return clock end},
},{__index=getfenv()})
local function load(name)
	if modules[name] then return modules[name] end
	local chunk=assert(loadstring(assert(sources[name],name),name))
	setfenv(chunk,environment)
	local result=chunk()
	modules[name]=result
	return result
end
environment.require=load
load("Controller")
local confirmButton = nodes.Footer.Children.Confirm
advance(0)
local state = load("SurvivorSelectionState")
local data = load("CharacterData")
local config = load("SurvivorSelectionConfig")
local requests = remotes.SelectCharacter.Sent
assert(#requests == 1 and requests[1][1] == "Sync")
local first,second,third=data.Characters[1].Id,data.Characters[2].Id,data.Characters[3].Id
local function snapshot(choice,confirmed,roster,deadline)
	return {state="Selecting",endsAt=deadline or 130,choices=if choice then {[7]=choice} else {},
		confirmed=if confirmed then {[7]=true} else {},roster=roster or {},availability={}}
end
player:SetAttribute("Role","Sobrevivente")
player:SetAttribute("InWaitingRoom",true)
player:SetAttribute("CharacterSelectOpen",true)
remotes.CharacterRoster.OnClientEvent:Fire(snapshot())
assert(nodes.SurvivorSelectionUI.Enabled and nodes.SurvivorSelectionBackdrop.Enabled)
assert(not confirmButton.Active and preview.Id == first)
assert(player:GetAttribute("CursorLivre") == true)
cardRefs[second].Root.MouseEnter:Fire()
assert(preview.Id == second and details.Character.Id == second and #requests == 1,"hover must not send a request")
cardRefs[second].Root.MouseLeave:Fire()
assert(preview.Id == first and not cardRefs[first].Selected,"fallback preview must not select")
-- Touch/click uses Activated once; wait for the authoritative acknowledgment.
cardRefs[second].Root.Activated:Fire()
advance(0)
assert(#requests == 2 and requests[2][1] == "Select" and requests[2][2] == second)
assert(confirmButton.Text == "PRONTO", "the button must change immediately after choosing")
assert(confirmButton.Active and cardRefs[second].Selected and preview.Id == second,
	"a local click must immediately remain selected and ready")
cardRefs[second].Root.MouseLeave:Fire()
assert(preview.Id == second, "mouse leave must not replace the clicked survivor")
cardRefs[third].Root.MouseEnter:Fire()
assert(preview.Id == third and cardRefs[second].Selected, "hover may preview without replacing the clicked survivor")
confirmButton.Activated:Fire()
assert(requests[#requests][1] == "Confirm", "ready must send the confirmation immediately")
remotes.CharacterRoster.OnClientEvent:Fire(snapshot(second))
assert(cardRefs[second].Selected)
assert(confirmButton.Text == "CONFIRMANDO…", "queued ready must enter the pending state")
assert(requests[#requests][1] == "Confirm" and preview.Id == second,"confirmation must lock the clicked survivor, not the hover")
assert(confirmButton.Text == "CONFIRMANDO…", "ready click must enter the pending state")
local count = #requests
cardRefs[first].Root.Activated:Fire()
confirmButton.Activated:Fire()
advance(0.2)
assert(#requests == count,"pending confirmation must block repeated input")
-- Conflict rejection returns control and indicates the authoritative reservation.
remotes.LobbyMessage.OnClientEvent:Fire("Esse sobrevivente foi reservado.")
remotes.CharacterRoster.OnClientEvent:Fire(snapshot(second,false,{[second]=99}))
assert(not confirmButton.Active and cardRefs[second].State == "Taken")
cardRefs[third].Root.Activated:Fire()
advance(0.2)
remotes.CharacterRoster.OnClientEvent:Fire(snapshot(third))
confirmButton.Activated:Fire()
player:SetAttribute("CharacterSelectionConfirmed",true)
player:SetAttribute("CharacterSelectOpen",nil)
-- Attribute and roster replication may cross in flight; an older Select
-- snapshot must not roll the confirmed state back to PRONTO.
remotes.CharacterRoster.OnClientEvent:Fire(snapshot(third,false))
assert(confirmButton.Text == "✓  ESCOLHA CONFIRMADA")
remotes.CharacterRoster.OnClientEvent:Fire(snapshot(third,true))
assert(nodes.SurvivorSelectionUI.Enabled and cardRefs[third].Confirmed and nodes.Confirmed.Visible)
count=#requests
cardRefs[first].Root.MouseEnter:Fire()
cardRefs[first].Root.Activated:Fire()
advance(0.2)
assert(#requests == count and preview.Id == third,"confirmed choice must remain immutable")
remotes.CharacterRoster.OnClientEvent:Fire({state="Closed",endsAt=0,choices={[7]=third},confirmed={[7]=true}})
assert(not nodes.SurvivorSelectionUI.Enabled and preview.Id == nil)
assert(actions.bound.SurvivorSelectionKeys == nil and player:GetAttribute("CursorLivre") == nil)
assert(input.MouseBehavior == enums.MouseBehavior.LockCenter and not input.MouseIconEnabled)
-- A new round clears old hover/choice/confirmation. Fast navigation coalesces.
player:SetAttribute("CharacterSelectionConfirmed",nil)
player:SetAttribute("CharacterSelectOpen",true)
remotes.CharacterRoster.OnClientEvent:Fire(snapshot(nil,false,nil,200))
assert(not confirmButton.Active and not cardRefs[third].Selected)
local action=assert(actions.bound.SurvivorSelectionKeys)
count=#requests
for _=1,3 do action("keys",enums.UserInputState.Begin,{KeyCode=enums.KeyCode.Right}) end
advance(0.2)
assert(#requests >= count+1 and requests[#requests][1] == "Select" and requests[#requests][2] == third,
	"fast arrows must leave the latest desired choice selected")
remotes.CharacterRoster.OnClientEvent:Fire(snapshot(third,false,nil,200))
action("keys",enums.UserInputState.Begin,{KeyCode=enums.KeyCode.Return})
assert(requests[#requests][1] == "Confirm")
-- Deadline never emits a client-side automatic confirmation.
remotes.LobbyMessage.OnClientEvent:Fire("Tente novamente")
count=#requests
advance(100)
run.Heartbeat:Fire()
assert(nodes.Seconds.Text == "00" and #requests == count,"timeout belongs to the server")
-- State and metadata invariants: gameplay stats, 14 powers and availability.
for _, character in data.Characters do
	assert(data.SumStats(character) == 350 and character.PreviewModel and character.ThemeColor)
	assert(character.Description and character.PowerDescription1 and character.PowerDescription2)
	assert(character.PowerCooldown1 > 0 and character.PowerCooldown2 > 0)
	assert(config.GetPortrait(character.Id).RigName == character.PreviewModel)
end
data.Characters[1].Availability="Locked"
assert(not config.IsSelectable(first),"CharacterData availability must be server-readable")
data.Characters[1].Availability="Available"
assert(not config.IsSelectable("Jason") and not config.IsSelectable("Invalid"))
assert(state.Preview(first,second,third,true) == first)
assert(not state.CanConfirm(first,"Taken",false,false))
-- Project every bounding-box corner through the actual orbit limits. No cropping
-- for narrow/mobile, square, ultrawide viewports or tall/wide/deep imported rigs.
for _, aspect in {0.3,0.5,1,1.777,3} do
	for _, size in {{4.2,5.7,1.2},{12,5,3},{2,18,2},{4,5,8}} do
		local distance=state.CameraDistance(size[1],size[2],size[3],aspect,34)
		for _, angle in {math.rad(4),math.rad(8)} do
			for _, sx in {-1,1} do for _, sy in {-1,1} do for _, sz in {-1,1} do
				local x,y,z=sx*size[1]/2,sy*size[2]/2,sz*size[3]/2
				local cameraX=x*math.cos(angle)+z*math.sin(angle)
				local depth=distance-x*math.sin(angle)+z*math.cos(angle)
				local limit=depth*math.tan(math.rad(17))
				assert(math.abs(cameraX) < limit*aspect and math.abs(y)+size[2]*0.006 < limit,"camera cropped a bound")
			end end end
		end
	end
end
scriptMock.Destroying:Fire()
assert(nodes.SurvivorSelectionUI.Destroyed and nodes.SurvivorSelectionBackdrop.Destroyed)
print("PASS: real controller hover/click/confirmation, conflicts, pending lock, reopening, rapid keyboard, server timeout, cleanup, metadata and 320 camera projections")
