--!strict
-- Separado de FirearmServer: nenhuma alteração no protocolo ou cálculo de dano.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Grip = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PistolGrip"))
local Remotes = require(ReplicatedStorage.Modules.Remotes)

local ALLOWED_USER_IDS: { [number]: boolean } = { [11555748600] = true }
local MAX_ROTATION_STEP = 5
local MAX_POSITION_STEP = 0.1

local function watch(instance: Instance)
	if instance:IsA("Tool") and instance.Name == "Glock17" then
		Grip.Bind(instance)
	end
end

-- Inclui template, armas do mapa, mochila e Character, inclusive depois do M/respawn.
game.DescendantAdded:Connect(watch)
for _, instance in game:GetDescendants() do watch(instance) end

local function equippedPistol(player: Player): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChild("Glock17")
	return if tool and tool:IsA("Tool") then tool else nil
end

Remotes.PistolGripTest.OnServerEvent:Connect(function(player: Player, action: unknown, delta: unknown)
	if not ALLOWED_USER_IDS[player.UserId] and not RunService:IsStudio() then return end
	local tool = equippedPistol(player)
	if not tool then return end
	if action == "Reset" then
		Grip.Reset(tool, true)
		return
	end
	if (action ~= "AdjustRotation" and action ~= "AdjustPosition") or typeof(delta) ~= "Vector3" then return end
	local value = delta :: Vector3
	if value.X ~= value.X or value.Y ~= value.Y or value.Z ~= value.Z then return end
	local currentPosition, currentRotation = Grip.GetOffset(tool, true)
	-- Um eixo por mensagem: rotacao em graus ou posicao em studs; evita abusos.
	local components = { value.X, value.Y, value.Z }
	local nonzero = 0
	for _, component in components do if component ~= 0 then nonzero += 1 end end
	if nonzero ~= 1 then return end
	if action == "AdjustRotation" and math.abs(value.X) <= MAX_ROTATION_STEP and value.Y == 0 and value.Z == 0 then
		Grip.Set(tool, currentPosition, currentRotation + value, true)
	elseif action == "AdjustRotation" and math.abs(value.Y) <= MAX_ROTATION_STEP and value.X == 0 and value.Z == 0 then
		Grip.Set(tool, currentPosition, currentRotation + value, true)
	elseif action == "AdjustRotation" and math.abs(value.Z) <= MAX_ROTATION_STEP and value.X == 0 and value.Y == 0 then
		Grip.Set(tool, currentPosition, currentRotation + value, true)
	elseif action == "AdjustPosition" and math.abs(value.X) <= MAX_POSITION_STEP and value.Y == 0 and value.Z == 0 then
		Grip.Set(tool, currentPosition + value, currentRotation, true)
	elseif action == "AdjustPosition" and math.abs(value.Y) <= MAX_POSITION_STEP and value.X == 0 and value.Z == 0 then
		Grip.Set(tool, currentPosition + value, currentRotation, true)
	elseif action == "AdjustPosition" and math.abs(value.Z) <= MAX_POSITION_STEP and value.X == 0 and value.Y == 0 then
		Grip.Set(tool, currentPosition + value, currentRotation, true)
	end
end)
