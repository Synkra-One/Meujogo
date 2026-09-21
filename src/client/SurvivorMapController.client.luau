--!strict
--[[
	SurvivorMapController
	Mapa da ilha pro Sobrevivente/Espião -- tecla M (Q já é o Poder 1 do
	sobrevivente, ver SurvivorPowersController.client.luau). Mesmo mapa que o
	Monstro abre com Q (Modules/IslandMapUI), em modo "view": só orientação,
	sem escolher destino nenhum.

	Mostra POIs, trilhas, um marcador verde de "você" e os itens que este
	jogador já descobriu (client/DiscoveredItemsStore.lua) -- NÃO mostra a
	Caverna (spawn do Monstro).

	NÃO pausa o movimento nem prende o mouse: é um overlay. O personagem
	continua andando e vulnerável com o mapa aberto (o Monstro pode te pegar
	de qualquer jeito). Fecha com M de novo, botão direito, ou no fim da
	partida.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local FearRules = require(ReplicatedStorage.Modules.FearPresentationRules)
local Remotes = require(ReplicatedStorage.Modules.Remotes)
local DiscoveredItemsStore = require(script.Parent.DiscoveredItemsStore)

local LocalPlayer = Players.LocalPlayer
local ACTION = "SurvivorMap"
local UPDATE_INTERVAL = 0.25

local isEligible = false -- Sobrevivente ou Espião (nunca o Monstro -- ele usa Q/MonsterTeleportController)
local bound = false
local character: Model? = nil
local mapUI: any = nil
local mapLoop: thread? = nil

local function ensureMapUI()
	if mapUI then
		return
	end
	local IslandMapUI = require(ReplicatedStorage.Modules.IslandMapUI)
	mapUI = IslandMapUI.new(LocalPlayer:WaitForChild("PlayerGui"), { mode = "view" })
	task.spawn(function()
		mapUI:Prepare() -- monta em background pra M abrir instantâneo
	end)
end

local function selfPosition(): Vector3?
	local char = character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function closeMap()
	if mapLoop then
		task.cancel(mapLoop)
		mapLoop = nil
	end
	if mapUI and mapUI:IsOpen() then
		mapUI:Hide()
	end
end

local function openMap()
	ensureMapUI()
	if not mapUI:Show(selfPosition(), "") then
		return -- dados do mapa ainda não chegaram; sem fallback aqui (não há destino pra mirar)
	end
	mapUI:SetDiscoveredItems(DiscoveredItemsStore.GetAll())

	if mapLoop then
		task.cancel(mapLoop)
	end
	mapLoop = task.spawn(function()
		while mapUI and mapUI:IsOpen() do
			mapUI:UpdateSelf(selfPosition())
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

--[[
	panicking()
	Em Fear alto o mapa grande não abre -- e fecha se já estiver aberto. Lê o
	Attribute "Fear" replicado pelo servidor e o MESMO limiar que apaga o
	minimapa (FearPresentationRules.HudFade). Não altera o mapa nem os itens
	descobertos: passado o pânico, M volta a funcionar normalmente.
]]
local function panicking(): boolean
	local raw = LocalPlayer:GetAttribute("Fear")
	local fear = if type(raw) == "number" and raw == raw
		then math.clamp(raw, 0, GameConfig.Fear.MaxFear) else 0
	return FearRules.HudFade(fear, GameConfig.Fear).FullMapBlocked
end

local function toggleMap()
	if not isEligible or panicking() then
		return
	end
	if mapUI and mapUI:IsOpen() then
		closeMap()
	else
		openMap()
	end
end

local function onAction(_name: string, inputState: Enum.UserInputState, input: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		-- botão direito só fecha (fora do mapa ele é a mira normal do jogo)
		if mapUI and mapUI:IsOpen() then
			closeMap()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end
	toggleMap()
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
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.M,
			Enum.KeyCode.ButtonSelect,
			Enum.UserInputType.MouseButton2
		)
	else
		ContextActionService:UnbindAction(ACTION)
		closeMap()
	end
end

local function refreshRole()
	local role = LocalPlayer:GetAttribute("Role")
	isEligible = role == GameConfig.Roles.Survivor or role == GameConfig.Roles.Spy
	setBound(isEligible)
	if isEligible then
		ensureMapUI() -- monta em background assim que o papel é sorteado
	else
		closeMap()
	end
end

LocalPlayer:GetAttributeChangedSignal("Role"):Connect(refreshRole)
-- Uma conexão só, por evento: o Fear já replica como Attribute, então não
-- existe loop de polling aqui.
LocalPlayer:GetAttributeChangedSignal("Fear"):Connect(function()
	if panicking() then
		closeMap()
	end
end)
LocalPlayer.CharacterAdded:Connect(function(char)
	closeMap()
	character = char
	refreshRole()
end)

if LocalPlayer.Character then
	character = LocalPlayer.Character
end
refreshRole()

-- Item novo descoberto enquanto o mapa já existe: entra direto (o mapa não
-- trava o movimento, então dá pra continuar andando e ver o ícone aparecer).
DiscoveredItemsStore.Changed:Connect(function(entry)
	if mapUI then
		mapUI:AddDiscoveredItem(entry :: any)
	end
end)

-- Fim de partida: não faz sentido o mapa continuar aberto voltando pro Lobby.
Remotes.RoundEnded.OnClientEvent:Connect(closeMap)
