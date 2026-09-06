--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Modules.Remotes)

local LOCAL_TEST_USER_IDS: { [number]: boolean } = {
	[11555748600] = true,
}

local player = game:GetService("Players").LocalPlayer
local debounce = false

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode ~= Enum.KeyCode.M then
		return
	end
	if not LOCAL_TEST_USER_IDS[player.UserId] then
		return
	end
	if debounce then
		return
	end

	debounce = true
	Remotes.TestRigSwap:FireServer()
	task.delay(1, function()
		debounce = false
	end)
end)
