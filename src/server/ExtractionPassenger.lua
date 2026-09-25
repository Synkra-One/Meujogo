--!strict
-- Estado reversível de um passageiro. Guarda os valores reais do corpo e
-- acessórios, inclusive os que forem adicionados depois do embarque.
local ExtractionPassenger = {}

export type Passenger = {
	character: Model,
	root: BasePart,
	wasAnchored: boolean,
	entryCFrame: CFrame,
	properties: { [Instance]: { [string]: any } },
	connection: RBXScriptConnection?,
}

function ExtractionPassenger.Hide(character: Model, root: BasePart): Passenger
	local info: Passenger = {
		character = character, root = root, wasAnchored = root.Anchored,
		entryCFrame = root.CFrame, properties = {}, connection = nil,
	}
	local function hide(object: Instance)
		local values: { [string]: any } = {}
		if object:IsA("BasePart") then
			values = { Transparency = object.Transparency, CanCollide = object.CanCollide,
				CanTouch = object.CanTouch, CanQuery = object.CanQuery }
			object.Transparency = 1
			object.CanCollide, object.CanTouch, object.CanQuery = false, false, false
		elseif object:IsA("Decal") or object:IsA("Texture") then
			values.Transparency = object.Transparency
			object.Transparency = 1
		elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
			or object:IsA("Light") or object:IsA("Highlight") or object:IsA("BillboardGui") then
			values.Enabled = (object :: any).Enabled
			;(object :: any).Enabled = false
		elseif object:IsA("Sound") then
			values.Volume = object.Volume
			object.Volume = 0
		elseif object:IsA("Humanoid") then
			values.DisplayDistanceType, values.HealthDisplayType = object.DisplayDistanceType, object.HealthDisplayType
			object.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			object.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		elseif object:IsA("ForceField") then
			values.Visible = object.Visible
			object.Visible = false
		end
		if next(values) then info.properties[object] = values end
	end
	character:SetAttribute("ExtractionBoarded", true)
	for _, object in character:GetDescendants() do hide(object) end
	info.connection = character.DescendantAdded:Connect(hide)
	root.Anchored = true
	root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	return info
end

function ExtractionPassenger.Restore(info: Passenger)
	if info.connection then info.connection:Disconnect(); info.connection = nil end
	-- Desembarque no ponto onde clicou: posição de solo já válida, sem
	-- lançar o jogador de um helicóptero que esteja voando ou sendo removido.
	if info.root.Parent then
		info.root.CFrame = info.entryCFrame
		info.root.AssemblyLinearVelocity, info.root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		info.root.Anchored = info.wasAnchored
	end
	for object, properties in info.properties do
		if object.Parent then
			for key, value in properties do (object :: any)[key] = value end
		end
	end
	table.clear(info.properties)
	info.character:SetAttribute("ExtractionBoarded", nil)
end

return ExtractionPassenger
