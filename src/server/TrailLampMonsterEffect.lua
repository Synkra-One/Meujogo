--!strict
--[[
	TrailLampMonsterEffect

	Quando o Monstro se aproxima de um poste de trilha, todas as luzes daquele
	poste piscam em conjunto, criando a sensação de que a presença dele está
	interferindo na energia -- referência ao efeito de Stranger Things.

	A autoridade fica no servidor: um único loop atualiza os postes e a mudança
	replica para todos os jogadores. O módulo não cria scripts dentro dos postes
	e também funciona com o asset StreetLamp e com o fallback Lampiao.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local RoundManager = require(script.Parent.RoundManager)
local CFG = GameConfig.TrailLamps

local TrailLampMonsterEffect = {}

type LampState = {
	model: Model,
	active: boolean,
	nextToggleAt: number,
	lights: { Light },
	originalEnabled: { [Light]: boolean },
	visuals: { BasePart },
	originalTransparency: { [BasePart]: number },
}

local states: { [Model]: LampState } = {}
local scanElapsed = CFG.ScanInterval
local updateElapsed = CFG.UpdateInterval
local initialized = false
local random = Random.new()

local function findMonsterRoot(): BasePart?
	if not RoundManager.IsRoundActive() then
		return nil
	end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == GameConfig.Roles.Monster
			and player:GetAttribute("InRound") == true then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
				return root
			end
		end
	end
	return nil
end

local function isLampModel(instance: Instance): boolean
	if not instance:IsA("Model") then return false end
	if instance:GetAttribute("LuzTrilhaPoste") == true then return true end
	-- Compatibilidade com mapas salvos antes do atributo existir: só aceita
	-- os modelos antigos que estão dentro da pasta de trilhas, sem capturar
	-- lampiões decorativos de cabanas ou outros POIs.
	if instance.Name ~= "Lampiao" and instance.Name ~= "PosteRua" then return false end
	local ilha = Workspace:FindFirstChild("Ilha")
	local trilhas = ilha and ilha:FindFirstChild("Trilhas")
	return trilhas ~= nil and instance:IsDescendantOf(trilhas)
end

local function register(model: Model)
	if states[model] then return end
	states[model] = {
		model = model,
		active = false,
		nextToggleAt = 0,
		lights = {},
		originalEnabled = {},
		visuals = {},
		originalTransparency = {},
	}
end

local function scan()
	for _, instance in Workspace:GetDescendants() do
		if isLampModel(instance) then
			register(instance :: Model)
		end
	end
	for model in states do
		if not model.Parent then
			states[model] = nil
		end
	end
end

local function collectLights(state: LampState)
	table.clear(state.lights)
	table.clear(state.originalEnabled)
	table.clear(state.visuals)
	table.clear(state.originalTransparency)
	for _, descendant in state.model:GetDescendants() do
		if descendant:IsA("Light") then
			table.insert(state.lights, descendant)
			state.originalEnabled[descendant] = descendant.Enabled
		elseif descendant:IsA("BasePart") then
			local name = string.lower(descendant.Name)
			local namedBulb = string.find(name, "lamp") ~= nil
				or string.find(name, "bulb") ~= nil
				or string.find(name, "light") ~= nil
				or string.find(name, "glow") ~= nil
				or string.find(name, "luz") ~= nil
				or string.find(name, "vidro") ~= nil
			local emissive = descendant:GetAttribute("LuzTrilhaVisual") == true
				or descendant.Material == Enum.Material.Neon
			if namedBulb or emissive then
				table.insert(state.visuals, descendant)
				state.originalTransparency[descendant] = descendant.Transparency
			end
		end
	end
end

local function setVisuals(state: LampState, on: boolean)
	for _, part in state.visuals do
		if part.Parent then
			part.Transparency = if on then state.originalTransparency[part] else 1
		end
	end
end

local function restore(state: LampState)
	for light, enabled in state.originalEnabled do
		if light.Parent then
			light.Enabled = enabled
		end
	end
	setVisuals(state, true)
	state.active = false
	state.nextToggleAt = 0
	state.model:SetAttribute("MonstroPerto", false)
	table.clear(state.lights)
	table.clear(state.originalEnabled)
	table.clear(state.visuals)
	table.clear(state.originalTransparency)
end

local function beginFlicker(state: LampState, now: number)
	collectLights(state)
	if #state.lights == 0 then return end
	state.active = true
	state.nextToggleAt = now + random:NextNumber(CFG.FlickerMinInterval, CFG.FlickerMaxInterval)
	state.model:SetAttribute("MonstroPerto", true)
end

local function updateLamp(state: LampState, monsterPosition: Vector3?, now: number)
	if not state.model.Parent then return end
	-- O apagão global tem prioridade sobre o pisca de proximidade. O sistema
	-- AbyssBlackout restaura o estado anterior quando o período termina.
	if Workspace:GetAttribute("AbyssWorldBlackout") == true then return end
	local near = monsterPosition ~= nil
		and (state.model:GetPivot().Position - (monsterPosition :: Vector3)).Magnitude <= CFG.MonsterRadius
	if not near then
		if state.active then restore(state) end
		return
	end
	if not state.active then
		beginFlicker(state, now)
		return
	end
	if now < state.nextToggleAt then return end
	for _, light in state.lights do
		if light.Parent then
			light.Enabled = not light.Enabled
		end
	end
	setVisuals(state, state.lights[1] and state.lights[1].Enabled == true)
	state.nextToggleAt = now + random:NextNumber(CFG.FlickerMinInterval, CFG.FlickerMaxInterval)
end

function TrailLampMonsterEffect.Init()
	if initialized then return end
	initialized = true
	scan()
	Workspace.DescendantAdded:Connect(function(instance)
		if isLampModel(instance) then
			register(instance :: Model)
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		scanElapsed += dt
		updateElapsed += dt
		if scanElapsed >= CFG.ScanInterval then
			scanElapsed = 0
			scan()
		end
		if updateElapsed < CFG.UpdateInterval then return end
		updateElapsed = 0
		local monsterRoot = findMonsterRoot()
		local monsterPosition = monsterRoot and monsterRoot.Position
		local now = Workspace:GetServerTimeNow()
		for _, state in states do
			updateLamp(state, monsterPosition, now)
		end
	end)
end

return TrailLampMonsterEffect
