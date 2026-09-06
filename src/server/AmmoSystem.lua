--!strict
--[[
	AmmoSystem
	Dono da RESERVA de munição de cada jogador (o pente da arma é do
	FirearmServer -- ver o cabeçalho de Modules/Ammo.lua pra diferença entre
	os dois estoques).

	ONDE FICA: Attribute "Municao_<Tipo>" no Player. Só o servidor escreve;
	o cliente (PistolController) lê pela replicação normal de Attributes, sem
	RemoteEvent. Reseta pro GameConfig.Firearms.StartingReserve a cada spawn.

	CAIXAS DE MUNIÇÃO NO CHÃO: qualquer BasePart com os Attributes
	  MunicaoPickup = true
	  TipoMunicao   = "Pistola"   (opcional; padrão DefaultAmmoType)
	  Quantidade    = 17          (opcional; padrão PickupAmount do tipo)
	ganha um ProximityPrompt "Pegar munição" automaticamente -- funciona tanto
	pras caixas que o WeaponSpawner.lua espalha quanto pras que você colocar
	na mão no Studio. Pegar com a reserva já cheia não consome a caixa.

	Uso (uma vez no boot do servidor, ANTES de FirearmServer):
		local AmmoSystem = require(script.AmmoSystem)
		AmmoSystem.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Ammo = require(ReplicatedStorage.Modules.Ammo)

local AmmoSystem = {}

local PICKUP_DISTANCE = 8

local watchedPickups: { [BasePart]: true } = {}

--------------------------------------------------------------------------------
-- Reserva
--------------------------------------------------------------------------------

--[[ Reserva atual (atalho de leitura; mesma coisa que Ammo.GetReserve). ]]
function AmmoSystem.GetReserve(player: Player, ammoType: string): number
	return Ammo.GetReserve(player, ammoType)
end

local function setReserve(player: Player, ammoType: string, value: number)
	player:SetAttribute(Ammo.AttributeName(ammoType), math.max(0, math.floor(value)))
end

--[[
	AddReserve(player, ammoType, amount)
	Soma na reserva respeitando o teto. Devolve quanto ENTROU de fato (0 se
	já estava cheia) -- quem chama usa isso pra decidir se consome a caixa.
]]
function AmmoSystem.AddReserve(player: Player, ammoType: string, amount: number): number
	if amount <= 0 then
		return 0
	end
	local current = Ammo.GetReserve(player, ammoType)
	local newValue = math.min(current + amount, Ammo.MaxReserve(ammoType))
	local gained = newValue - current
	if gained > 0 then
		setReserve(player, ammoType, newValue)
	end
	return gained
end

--[[
	TakeReserve(player, ammoType, amount)
	Tira até `amount` da reserva. Devolve quanto SAIU de fato (pode ser menos
	que o pedido, ou 0). É o que a recarga usa pra encher o pente.
]]
function AmmoSystem.TakeReserve(player: Player, ammoType: string, amount: number): number
	if amount <= 0 then
		return 0
	end
	local current = Ammo.GetReserve(player, ammoType)
	local taken = math.min(current, math.floor(amount))
	if taken > 0 then
		setReserve(player, ammoType, current - taken)
	end
	return taken
end

--[[ Zera e reaplica a reserva inicial de TODOS os tipos configurados. ]]
function AmmoSystem.ResetReserves(player: Player)
	for ammoType, amount in GameConfig.Firearms.StartingReserve do
		setReserve(player, ammoType, amount)
	end
	-- Tipos que só aparecem em MaxReserve/PickupAmount começam zerados.
	for ammoType in GameConfig.Firearms.MaxReserve do
		if GameConfig.Firearms.StartingReserve[ammoType] == nil then
			setReserve(player, ammoType, 0)
		end
	end
end

--------------------------------------------------------------------------------
-- Caixas de munição no chão
--------------------------------------------------------------------------------

--[[
	CreatePickup(position, ammoType?, amount?, parent?)
	Cria uma caixa de munição no mundo. O prompt é ligado por watchPickup
	(via Attribute), então não precisa conectar nada aqui.
]]
function AmmoSystem.CreatePickup(position: Vector3, ammoType: string?, amount: number?, parent: Instance?): BasePart
	local kind = ammoType or GameConfig.Firearms.DefaultAmmoType
	local qty = amount or GameConfig.Firearms.PickupAmount[kind] or 17

	local part = Instance.new("Part")
	part.Name = "Municao_" .. kind
	part.Size = Vector3.new(1.4, 0.8, 1)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Metal
	part.Color = Color3.fromRGB(190, 160, 60)
	part:SetAttribute("MunicaoPickup", true)
	part:SetAttribute("TipoMunicao", kind)
	part:SetAttribute("Quantidade", qty)
	part.Parent = parent or workspace
	return part
end

local function watchPickup(part: BasePart)
	if watchedPickups[part] or part:GetAttribute("MunicaoPickup") ~= true then
		return
	end
	watchedPickups[part] = true

	local kindAttr = part:GetAttribute("TipoMunicao")
	local kind = if type(kindAttr) == "string" then kindAttr else GameConfig.Firearms.DefaultAmmoType
	local qtyAttr = part:GetAttribute("Quantidade")
	local qty = if type(qtyAttr) == "number" then qtyAttr else (GameConfig.Firearms.PickupAmount[kind] or 17)

	local existing = part:FindFirstChild("MunicaoPrompt")
	if existing then
		existing:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MunicaoPrompt"
	prompt.ActionText = "Pegar munição"
	prompt.ObjectText = string.format("%s (%d)", kind, qty)
	prompt.MaxActivationDistance = PICKUP_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		if part.Parent == nil then
			return -- outro jogador pegou no mesmo frame
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0
			or (root.Position - part.Position).Magnitude > PICKUP_DISTANCE + 2 then return end
		if part:GetAttribute("LobbyTestPickup") == true
			and (player:GetAttribute("InRound") == true or player:GetAttribute("InWaitingRoom") == true) then return end
		local gained = AmmoSystem.AddReserve(player, kind, qty)
		if gained <= 0 then
			return -- reserva cheia: a caixa FICA no chão pra quem precisar
		end
		qty -= gained
		if qty <= 0 then
			part:Destroy()
		else
			part:SetAttribute("Quantidade", qty)
			prompt.ObjectText = string.format("%s (%d)", kind, qty)
		end
	end)

	part.Destroying:Connect(function()
		watchedPickups[part] = nil
	end)
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

--[[
	Init()
	Reserva inicial a cada spawn + prompts em toda caixa de munição
	existente/futura. Chame uma vez no boot, ANTES de FirearmServer.
]]
function AmmoSystem.Init()
	local function watchPlayer(player: Player)
		AmmoSystem.ResetReserves(player)
		player.CharacterAdded:Connect(function()
			AmmoSystem.ResetReserves(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("BasePart") then
			watchPickup(descendant)
		end
	end
	workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			-- Tenta agora e de novo no fim do frame: uma caixa colocada por
			-- outro script pode ganhar o Attribute depois do Parent.
			watchPickup(descendant)
			task.defer(watchPickup, descendant)
		end
	end)
end

return AmmoSystem
