--!strict
-- Calibracao fixa no espaco do Grip. Nenhum offset de camera/ombro/animacao.
local Grip = {}
local BASE = "PistolGripBase"
local POSITION = "PistolGripPosition"
local ROTATION = "PistolGripRotation"
local AIM_POSITION = "PistolAimGripPosition"
local AIM_ROTATION = "PistolAimGripRotation"
local DEFAULT_AIM_POSITION = Vector3.new(0, 0.04, -0.08)
local DEFAULT_AIM_ROTATION = Vector3.new(-13, -318, 0)
local bound: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function finiteVector(value: unknown): boolean
	if typeof(value) ~= "Vector3" then return false end
	local v = value :: Vector3
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < math.huge and math.abs(v.Y) < math.huge and math.abs(v.Z) < math.huge
end

function Grip.EnsureBase(tool: Tool)
	if typeof(tool:GetAttribute(BASE)) ~= "CFrame" then tool:SetAttribute(BASE, tool.Grip) end
end

local function offsetAttributes(useAimGrip: boolean?): (string, string)
	if useAimGrip then return AIM_POSITION, AIM_ROTATION end
	return POSITION, ROTATION
end

function Grip.GetOffset(tool: Tool, useAimGrip: boolean?): (Vector3, Vector3)
	local positionName, rotationName = offsetAttributes(useAimGrip)
	local p = tool:GetAttribute(positionName)
	local r = tool:GetAttribute(rotationName)
	local defaultPosition = if useAimGrip then DEFAULT_AIM_POSITION else Vector3.zero
	local defaultRotation = if useAimGrip then DEFAULT_AIM_ROTATION else Vector3.zero
	return if finiteVector(p) then p :: Vector3 else defaultPosition,
		if finiteVector(r) then r :: Vector3 else defaultRotation
end

function Grip.Resolve(tool: Tool, useAimGrip: boolean?): CFrame
	local stored = tool:GetAttribute(BASE)
	local base = if typeof(stored) == "CFrame" then stored :: CFrame else tool.Grip
	local position, rotation = Grip.GetOffset(tool, useAimGrip)
	return base * CFrame.new(position)
		* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
end

function Grip.Bind(tool: Tool)
	if bound[tool] then return end
	bound[tool] = true
	-- Attribute e copiado com Clone: uma Tool ja calibrada nao recebe offset duas vezes.
	Grip.EnsureBase(tool)
	local connections: { RBXScriptConnection } = {}
	local function apply() tool.Grip = Grip.Resolve(tool, false) end
	for _, name in { BASE, POSITION, ROTATION } do
		table.insert(connections, tool:GetAttributeChangedSignal(name):Connect(apply))
	end
	tool.Destroying:Once(function()
		for _, connection in connections do connection:Disconnect() end
		bound[tool] = nil
	end)
	apply()
end

-- Command Bar no contexto SERVIDOR. Valores absolutos em studs/graus, nao incrementais.
function Grip.Set(tool: Tool, position: Vector3, degrees: Vector3, useAimGrip: boolean?)
	assert(finiteVector(position) and finiteVector(degrees), "Use Vector3 finitos para posicao e rotacao")
	Grip.EnsureBase(tool)
	local positionName, rotationName = offsetAttributes(useAimGrip)
	tool:SetAttribute(positionName, position)
	tool:SetAttribute(rotationName, degrees)
	if not useAimGrip then Grip.Bind(tool) end
end

function Grip.Reset(tool: Tool, useAimGrip: boolean?)
	Grip.Set(tool, Vector3.zero, Vector3.zero, useAimGrip)
end

function Grip.Export(tool: Tool, useAimGrip: boolean?): string
	local values = { Grip.Resolve(tool, useAimGrip):GetComponents() }
	local formatted = {}
	for _, value in values do table.insert(formatted, string.format("%.9g", value)) end
	return "CFrame.new(" .. table.concat(formatted, ", ") .. ")"
end

return Grip
