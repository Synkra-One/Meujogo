--!strict
--[[
	RiftVFXController
	Apresenta as fendas do teleporte do Monstro pro jogador local. O servidor
	(server/MonsterTeleport) manda os "beats" por Remotes.RiftVFX -- SÓ pra
	quem está perto -- e este script constrói / anima / limpa a fenda com
	Modules/RiftVFX (que usa TweenService, nada de loop por frame) e toca os
	sons 3D. Um Sobrevivente perto do destino ouve/vê a fenda surgindo antes
	do Monstro sair -- isso é de propósito (antecipação).

	Não decide nada de gameplay: posição, timing e estado são do servidor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local RiftVFX = require(ReplicatedStorage.Modules.RiftVFX)
local AssetRegistry = require(ReplicatedStorage.Modules.AssetRegistry)

local CFG = GameConfig.Monster.Teleport
local SOUNDS = AssetRegistry.RiftTeleport.Sounds

--------------------------------------------------------------------------------
-- Template do asset (publicado pelo servidor; pode não existir -> reserva)
--------------------------------------------------------------------------------

local function getTemplate(): Model?
	local folder = ReplicatedStorage:FindFirstChild("RiftAssets")
	if not folder then
		folder = ReplicatedStorage:WaitForChild("RiftAssets", 20) :: Folder?
	end
	local tpl = folder and folder:FindFirstChild("Template")
	return (tpl and tpl:IsA("Model")) and tpl or nil
end

local function templateFaceAxis(template: Model?): string
	if CFG.RiftAssetFaceAxis ~= "auto" then
		return CFG.RiftAssetFaceAxis
	end
	local a = template and template:GetAttribute("FaceAxis")
	return (type(a) == "string") and a or "Y"
end

--------------------------------------------------------------------------------
-- Som 3D na fenda
--------------------------------------------------------------------------------

local function isRealSound(id: unknown): boolean
	return type(id) == "string" and id ~= "" and id ~= "rbxassetid://0"
end

local function playAt(core: BasePart?, soundId: string)
	if not core or not core.Parent or not isRealSound(soundId) then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 95
	sound.Parent = core
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, 12)
end

--------------------------------------------------------------------------------
-- Fendas ativas
--------------------------------------------------------------------------------

type Entry = { handle: any, kind: string }
local rifts: { [string]: Entry } = {}

local function destroyRift(id: string)
	local entry = rifts[id]
	if not entry then
		return
	end
	rifts[id] = nil
	pcall(function()
		entry.handle:Destroy()
	end)
end

local function onOpen(data: { [string]: any })
	local id = data.id
	if type(id) ~= "string" or typeof(data.cframe) ~= "CFrame" then
		return
	end
	-- nunca duplica: se já existe uma fenda com esse id, some com a antiga
	destroyRift(id)

	local template = getTemplate()
	local kind = tostring(data.kind or "entrada")
	local width = tonumber(data.width) or 6

	local ok, handle = pcall(function()
		return RiftVFX.new({
			template = template,
			cframe = data.cframe,
			width = width,
			faceAxis = templateFaceAxis(template),
			upright = CFG.RiftUpright,
			groundOffset = CFG.RiftGroundOffset,
			extraRotDeg = CFG.RiftExtraRotationDeg,
			lightBrightness = CFG.RiftLightBrightness,
			lightRangeFactor = CFG.RiftLightRangeFactor,
			into = -data.cframe.UpVector,
		})
	end)
	if not ok or not handle then
		warn("[RiftVFXController] falha ao montar a fenda: " .. tostring(handle))
		return
	end

	rifts[id] = { handle = handle, kind = kind }
	handle:Open(CFG.RiftOpenDuration)

	-- entrada -> som de abertura; destino -> som de "viagem"/surgindo (antecipação)
	playAt(handle.Core, if kind == "destino" then SOUNDS.RiftTravel else SOUNDS.RiftOpen)
end

local function onBeat(op: string, data: { [string]: any })
	local entry = rifts[data.id]
	if not entry then
		return
	end
	if op == "enter" then
		entry.handle:Enter()
		playAt(entry.handle.Core, SOUNDS.RiftEnter)
	elseif op == "emerge" then
		entry.handle:Emerge()
		playAt(entry.handle.Core, SOUNDS.RiftExit)
	elseif op == "close" then
		entry.handle:Close(CFG.RiftCloseDuration)
		playAt(entry.handle.Core, SOUNDS.RiftClose)
		rifts[data.id] = nil -- o handle se autodestrói depois do rastro
	elseif op == "cancel" then
		entry.handle:Cancel()
		rifts[data.id] = nil
	end
end

Remotes.RiftVFX.OnClientEvent:Connect(function(op: string, data: any)
	if type(op) ~= "string" or type(data) ~= "table" then
		return
	end
	if op == "open" then
		onOpen(data)
	else
		onBeat(op, data)
	end
end)

-- Rede de segurança: se sobrar alguma fenda "presa" (evento de fechar perdido),
-- limpa tudo quando a partida acaba.
Remotes.RoundEnded.OnClientEvent:Connect(function()
	for id in rifts do
		destroyRift(id)
	end
	local folder = workspace:FindFirstChild("RiftVFX")
	if folder then
		folder:ClearAllChildren()
	end
end)
