--!strict
-- Local input and immediate control lock. Targeting and execution stay server-side.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local player = Players.LocalPlayer
local CFG = GameConfig.Monster.Grab
local ACTION = "MonsterGrab"

local controls: any = nil
local character: Model? = nil
local characterConnections: { RBXScriptConnection } = {}
local bound = false
local disabledByGrab = false

local function disconnectCharacter()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
end

local function grabNeedsControlLock(): boolean
	local current = character
	if not current then
		return false
	end
	if current:GetAttribute("Grabbed") == true then
		return true
	end
	return current:GetAttribute("GrabBusy") == true and current:GetAttribute("GrabState") ~= "Attempt"
end

local function refreshControls()
	if not controls then
		return
	end
	local shouldDisable = grabNeedsControlLock()
	if shouldDisable and not disabledByGrab then
		disabledByGrab = true
		controls:Disable()
	elseif not shouldDisable and disabledByGrab then
		disabledByGrab = false
		local current = character
		if not current or current:GetAttribute("TeleportBusy") ~= true then
			controls:Enable()
		end
	end
end

local function onAction(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local current = character
	if not current or UserInputService:GetFocusedTextBox() or player:GetAttribute("MapaAberto") == true
		or player:GetAttribute("CursorLivre") == true or current:GetAttribute("GrabLocked") == true
		or current:GetAttribute("TeleportBusy") == true or current:GetAttribute("ShadowRushBusy") == true
		or Workspace:GetServerTimeNow() < (player:GetAttribute("GrabReadyAt") or 0) then
		return Enum.ContextActionResult.Sink
	end
	Remotes.MonsterGrab:FireServer()
	return Enum.ContextActionResult.Sink
end

local function setBound(shouldBind: boolean)
	if shouldBind == bound then
		return
	end
	bound = shouldBind
	if shouldBind then
		ContextActionService:BindActionAtPriority(
			ACTION,
			onAction,
			true,
			Enum.ContextActionPriority.High.Value,
			CFG.InputKey,
			CFG.GamepadKey
		)
		ContextActionService:SetTitle(ACTION, "Agarrar")
		ContextActionService:SetPosition(ACTION, UDim2.fromScale(0.82, 0.68))
	else
		ContextActionService:UnbindAction(ACTION)
	end
end

local function bindCharacter(newCharacter: Model)
	disconnectCharacter()
	character = newCharacter
	for _, attribute in { "Grabbed", "GrabBusy", "GrabState" } do
		table.insert(characterConnections, newCharacter:GetAttributeChangedSignal(attribute):Connect(refreshControls))
	end
	table.insert(characterConnections, newCharacter.AncestryChanged:Connect(function(_, parent)
		if not parent then
			refreshControls()
		end
	end))
	refreshControls()
end

local function refreshRole()
	setBound(player:GetAttribute("Role") == GameConfig.Roles.Monster and player:GetAttribute("Eliminado") ~= true)
end

task.spawn(function()
	local playerScripts = player:WaitForChild("PlayerScripts")
	local playerModule = playerScripts:WaitForChild("PlayerModule", 10)
	if playerModule and playerModule:IsA("ModuleScript") then
		controls = require(playerModule):GetControls()
		refreshControls()
	end
end)

Remotes.MonsterGrab.OnClientEvent:Connect(function(kind: string, reason: unknown)
	if kind == "Rejected" and type(reason) == "string" then
		warn("[Grab] " .. reason)
	end
end)

player:GetAttributeChangedSignal("Role"):Connect(refreshRole)
player:GetAttributeChangedSignal("Eliminado"):Connect(refreshRole)
player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end
refreshRole()

script.Destroying:Connect(function()
	disconnectCharacter()
	ContextActionService:UnbindAction(ACTION)
	if disabledByGrab and controls then
		controls:Enable()
	end
end)
