--!strict
--[[
	DoorSystem
	Portas que abrem e fecham. Qualquer BasePart com Attribute "Porta" == true
	(Structures.Door cria assim) ganha um ProximityPrompt "Abrir"/"Fechar".
	O servidor gira a porta em torno da dobradiça (borda esquerda) com um
	tween; o estado fica no Attribute "PortaAberta" (replica sozinho).

	Attributes usados (gravados por Structures.Door):
	  CFrameFechada  CFrame  -- pose fechada; a dobradiça é a borda -X dela
	  LarguraPorta   number
	  PortaAberta    boolean

	Não valida Role: qualquer jogador abre/fecha (o Monstro também -- no
	F13 o Jason abre porta normalmente; quebrar barricada vem depois).

	Uso (boot do servidor):
		require(script.DoorSystem).Init()
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local DoorSystem = {}

local OPEN_ANGLE = math.rad(100)
local TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local watched: { [BasePart]: true } = {}
local busy: { [BasePart]: boolean } = {}

local function targetCFrame(door: BasePart, open: boolean): CFrame?
	local closed = door:GetAttribute("CFrameFechada")
	local width = door:GetAttribute("LarguraPorta")
	if typeof(closed) ~= "CFrame" or type(width) ~= "number" then
		return nil
	end
	local hinge = closed * CFrame.new(-width / 2, 0, 0)
	local angle = if open then OPEN_ANGLE else 0
	return hinge * CFrame.Angles(0, angle, 0) * CFrame.new(width / 2, 0, 0)
end

local function setOpen(door: BasePart, open: boolean, prompt: ProximityPrompt)
	if busy[door] then
		return
	end
	local target = targetCFrame(door, open)
	if not target then
		return
	end
	busy[door] = true
	door:SetAttribute("PortaAberta", open)
	prompt.ActionText = if open then "Fechar" else "Abrir"

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/impact_generic.mp3"
	sound.Volume = 0.35
	sound.PlaybackSpeed = if open then 0.7 else 0.55
	sound.RollOffMaxDistance = 40
	sound.Parent = door
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 2)

	local tween = TweenService:Create(door, TWEEN, { CFrame = target })
	tween.Completed:Connect(function()
		busy[door] = nil
	end)
	tween:Play()
end

local function watchDoor(door: Instance)
	if not door:IsA("BasePart") or watched[door] then
		return
	end
	if typeof(door:GetAttribute("CFrameFechada")) ~= "CFrame" then
		return
	end
	watched[door] = true

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PortaPrompt"
	prompt.ObjectText = "Porta"
	prompt.ActionText = if door:GetAttribute("PortaAberta") == true then "Fechar" else "Abrir"
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = door

	prompt.Triggered:Connect(function()
		setOpen(door, door:GetAttribute("PortaAberta") ~= true, prompt)
	end)

	door.Destroying:Connect(function()
		watched[door] = nil
		busy[door] = nil
	end)
end

function DoorSystem.Init()
	for _, d in Workspace:GetDescendants() do
		if d:GetAttribute("Porta") == true then
			watchDoor(d)
		end
	end
	Workspace.DescendantAdded:Connect(function(d)
		if d:GetAttribute("Porta") == true then
			watchDoor(d)
		end
	end)
end

return DoorSystem
