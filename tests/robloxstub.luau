--!nocheck
--[[
	Dublês determinísticos das APIs do Roblox usadas pelos geradores de mapa.
	Só existe o necessário pra RODAR a geometria fora do Studio: Vector3,
	CFrame (matriz 3x4 de verdade), Color3, Enum, Instance e Terrain.

	Não simula física, renderização nem replicação -- o que ele prova é que o
	módulo executa e que as peças caem nas coordenadas esperadas.
]]

local stub = {}

--------------------------------------------------------------------------------
-- Vector3
--------------------------------------------------------------------------------

local Vector3M = {}
Vector3M.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m < 1e-9 then
			return Vector3.new(0, 0, 0)
		end
		return Vector3.new(self.X / m, self.Y / m, self.Z / m)
	end
	return rawget(Vector3M, key)
end

function Vector3M.Cross(a, b)
	return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function Vector3M.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
Vector3M.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3M.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3M.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
Vector3M.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
Vector3M.__mul = function(a, b)
	if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
	if type(a) == "number" then return Vector3.new(b.X * a, b.Y * a, b.Z * a) end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3M.__div = function(a, b)
	if type(b) == "number" then return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
	return Vector3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
Vector3M.__tostring = function(a) return string.format("(%.2f, %.2f, %.2f)", a.X, a.Y, a.Z) end

Vector3 = {}
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3M)
end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)

--------------------------------------------------------------------------------
-- CFrame (posição + matriz de rotação 3x3, colunas Right/Up/Back)
--------------------------------------------------------------------------------

local CFrameM = {}

local function newCF(px, py, pz, r)
	return setmetatable({
		X = px, Y = py, Z = pz,
		R = r or { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, -- R00 R01 R02 R10 R11 R12 R20 R21 R22
	}, CFrameM)
end

local function rotMul(a, b)
	local out = {}
	for row = 0, 2 do
		for col = 0, 2 do
			local sum = 0
			for k = 0, 2 do
				sum += a[row * 3 + k + 1] * b[k * 3 + col + 1]
			end
			out[row * 3 + col + 1] = sum
		end
	end
	return out
end

local function rotApply(r, x, y, z)
	return r[1] * x + r[2] * y + r[3] * z,
		r[4] * x + r[5] * y + r[6] * z,
		r[7] * x + r[8] * y + r[9] * z
end

CFrameM.__index = function(self, key)
	if key == "Position" or key == "p" then
		return Vector3.new(self.X, self.Y, self.Z)
	elseif key == "RightVector" then
		return Vector3.new(self.R[1], self.R[4], self.R[7])
	elseif key == "UpVector" then
		return Vector3.new(self.R[2], self.R[5], self.R[8])
	elseif key == "LookVector" then
		return Vector3.new(-self.R[3], -self.R[6], -self.R[9])
	end
	return rawget(CFrameM, key)
end

CFrameM.__mul = function(a, b)
	if getmetatable(b) == Vector3M then
		local x, y, z = rotApply(a.R, b.X, b.Y, b.Z)
		return Vector3.new(a.X + x, a.Y + y, a.Z + z)
	end
	local x, y, z = rotApply(a.R, b.X, b.Y, b.Z)
	return newCF(a.X + x, a.Y + y, a.Z + z, rotMul(a.R, b.R))
end
CFrameM.__add = function(a, v) return newCF(a.X + v.X, a.Y + v.Y, a.Z + v.Z, a.R) end
CFrameM.__sub = function(a, v) return newCF(a.X - v.X, a.Y - v.Y, a.Z - v.Z, a.R) end
CFrameM.__tostring = function(a) return string.format("CF(%.2f, %.2f, %.2f)", a.X, a.Y, a.Z) end

CFrame = {}
function CFrame.new(x, y, z)
	if type(x) == "table" then
		return newCF(x.X, x.Y, x.Z, nil)
	end
	return newCF(x or 0, y or 0, z or 0, nil)
end

function CFrame.Angles(rx, ry, rz)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local mx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local my = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local mz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return newCF(0, 0, 0, rotMul(rotMul(mx, my), mz))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles

function CFrame.fromMatrix(pos, vX, vY, vZ)
	local z = vZ or vX:Cross(vY)
	return newCF(pos.X, pos.Y, pos.Z, {
		vX.X, vY.X, z.X,
		vX.Y, vY.Y, z.Y,
		vX.Z, vY.Z, z.Z,
	})
end

function CFrame.lookAt(pos, target, up)
	up = up or Vector3.new(0, 1, 0)
	local forward = (target - pos).Unit
	local back = -forward
	local right = up:Cross(back)
	if right.Magnitude < 1e-6 then
		right = Vector3.new(1, 0, 0):Cross(back)
	end
	right = right.Unit
	local realUp = back:Cross(right)
	return CFrame.fromMatrix(pos, right, realUp, back)
end
CFrame.identity = CFrame.new(0, 0, 0)

--------------------------------------------------------------------------------
-- Color3 / UDim / UDim2
--------------------------------------------------------------------------------

Color3 = {}
function Color3.new(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end
function Color3.fromRGB(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end

UDim = {}
function UDim.new(s, o) return { Scale = s, Offset = o } end
UDim2 = {}
function UDim2.fromScale(x, y) return { X = UDim.new(x, 0), Y = UDim.new(y, 0) } end
function UDim2.new(xs, xo, ys, yo) return { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) } end

--------------------------------------------------------------------------------
-- Enum (qualquer Enum.Categoria.Membro devolve um objeto com .Name)
--------------------------------------------------------------------------------

local enumCategories = {}
Enum = setmetatable({}, {
	__index = function(_, category)
		local cached = enumCategories[category]
		if cached then
			return cached
		end
		local members = {}
		cached = setmetatable({}, {
			__index = function(_, member)
				if not members[member] then
					members[member] = { Name = member, Category = category, Value = 0 }
				end
				return members[member]
			end,
		})
		enumCategories[category] = cached
		return cached
	end,
})

--------------------------------------------------------------------------------
-- Instance
--------------------------------------------------------------------------------

local InstanceM = {}
InstanceM.__index = InstanceM

local CLASS_PARENTS = {
	Part = { "BasePart", "PVInstance", "Instance" },
	WedgePart = { "BasePart", "PVInstance", "Instance" },
	SpawnLocation = { "Part", "BasePart", "PVInstance", "Instance" },
	Model = { "PVInstance", "Instance" },
	Folder = { "Instance" },
	PointLight = { "Light", "Instance" },
	SpotLight = { "Light", "Instance" },
	SurfaceGui = { "LayerCollector", "GuiBase", "Instance" },
	TextLabel = { "GuiObject", "GuiBase2d", "Instance" },
	Frame = { "GuiObject", "GuiBase2d", "Instance" },
	UIListLayout = { "UILayout", "Instance" },
	Script = { "LuaSourceContainer", "Instance" },
	ModuleScript = { "LuaSourceContainer", "Instance" },
}

function InstanceM:IsA(className)
	if self.ClassName == className then
		return true
	end
	for _, ancestor in CLASS_PARENTS[self.ClassName] or {} do
		if ancestor == className then
			return true
		end
	end
	return false
end

function InstanceM:GetChildren()
	return table.clone(self._children)
end

function InstanceM:GetDescendants()
	local out = {}
	local function walk(node)
		for _, child in node._children do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

function InstanceM:FindFirstChild(name)
	for _, child in self._children do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function InstanceM:FindFirstChildOfClass(className)
	for _, child in self._children do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

function InstanceM:FindFirstChildWhichIsA(className, recursive)
	for _, child in self._children do
		if child:IsA(className) then
			return child
		end
	end
	if recursive then
		for _, child in self._children do
			local found = child:FindFirstChildWhichIsA(className, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function InstanceM:SetAttribute(name, value)
	self._attributes[name] = value
end
function InstanceM:GetAttribute(name)
	return self._attributes[name]
end
function InstanceM:GetAttributes()
	return table.clone(self._attributes)
end

function InstanceM:Destroy()
	self.Parent = nil
	self._destroyed = true
end

function InstanceM:Clone()
	local copy = Instance.new(self.ClassName)
	for key, value in self._props do
		copy._props[key] = value
	end
	for key, value in self._attributes do
		copy._attributes[key] = value
	end
	for _, child in self._children do
		local childCopy = child:Clone()
		childCopy.Parent = copy
	end
	return copy
end

-- PVInstance
function InstanceM:GetPivot()
	if self.ClassName == "Model" then
		if self.PrimaryPart then
			return self.PrimaryPart.CFrame
		end
		local cf = self:GetBoundingBox()
		return cf
	end
	return self.CFrame
end

local function partExtents(p)
	local cf, s = p.CFrame, p.Size
	local ex = math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z
	local ey = math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
	local ez = math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z
	return Vector3.new(ex, ey, ez)
end
stub.PartExtents = partExtents

function InstanceM:GetBoundingBox()
	local minV, maxV
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			local e = partExtents(d) * 0.5
			local lo = d.CFrame.Position - e
			local hi = d.CFrame.Position + e
			minV = if minV then Vector3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z)) else lo
			maxV = if maxV then Vector3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z)) else hi
		end
	end
	if not minV then
		return CFrame.new(0, 0, 0), Vector3.new(0, 0, 0)
	end
	local center = (minV + maxV) * 0.5
	return CFrame.new(center.X, center.Y, center.Z), maxV - minV
end

function InstanceM:PivotTo(target)
	local current = self:GetPivot()
	local delta = Vector3.new(target.X - current.X, target.Y - current.Y, target.Z - current.Z)
	if self.ClassName == "Model" then
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = d.CFrame + delta
			end
		end
	else
		self.CFrame = target
	end
end

function InstanceM:GetScale()
	return self._scale or 1
end
function InstanceM:ScaleTo(scale)
	self._scale = scale
end

local DEFAULTS = {
	Anchored = false,
	CanCollide = true,
	CanQuery = true,
	CanTouch = true,
	CastShadow = true,
	Transparency = 0,
	Reflectance = 0,
	Duration = 10,
}

Instance = {}
function Instance.new(className, parent)
	local self = setmetatable({
		ClassName = className,
		_children = {},
		_props = {},
		_attributes = {},
	}, {
		__index = function(t, key)
			if key == "Parent" then
				return rawget(t, "_parent")
			end
			local props = rawget(t, "_props")
			if props[key] ~= nil then
				return props[key]
			end
			if key == "Name" then
				return rawget(t, "ClassName")
			end
			if key == "Size" then
				return Vector3.new(4, 1.2, 2)
			end
			if key == "CFrame" then
				return CFrame.new(0, 0, 0)
			end
			if key == "Position" then
				local cf = props.CFrame
				return if cf then cf.Position else Vector3.new(0, 0, 0)
			end
			if DEFAULTS[key] ~= nil then
				return DEFAULTS[key]
			end
			return InstanceM[key]
		end,
		__newindex = function(t, key, value)
			if key == "Parent" then
				local old = rawget(t, "_parent")
				if old then
					local siblings = old._children
					local index = table.find(siblings, t)
					if index then
						table.remove(siblings, index)
					end
				end
				rawset(t, "_parent", value)
				if value then
					table.insert(value._children, t)
				end
				return
			end
			if key == "Position" then
				rawget(t, "_props").CFrame = CFrame.new(value.X, value.Y, value.Z)
				return
			end
			rawget(t, "_props")[key] = value
		end,
	})
	if parent then
		self.Parent = parent
	end
	return self
end

--------------------------------------------------------------------------------
-- Terrain / Workspace / game
--------------------------------------------------------------------------------

local terrainFills = {}
stub.TerrainFills = terrainFills

local Terrain = Instance.new("Terrain")
Terrain.Name = "Terrain"
function Terrain.FillBlock(_, cf, size, material)
	table.insert(terrainFills, { CFrame = cf, Size = size, Material = material })
end

local Workspace = Instance.new("Workspace")
Workspace.Name = "Workspace"
Terrain.Parent = Workspace
rawget(Workspace, "_props").Terrain = Terrain
stub.Workspace = Workspace

local services = {
	Workspace = Workspace,
	RunService = { IsRunning = function() return false end, IsStudio = function() return true end },
	ServerStorage = Instance.new("Folder"),
	InsertService = {
		LoadAsset = function()
			error("InsertService indisponível fora do Studio", 0)
		end,
	},
}
stub.Services = services

game = {
	GetService = function(_, name)
		local service = services[name]
		if not service then
			service = Instance.new("Folder")
			service.Name = name
			services[name] = service
		end
		return service
	end,
	GetObjects = function()
		error("GetObjects indisponível fora do Studio", 0)
	end,
}

warn = function(...)
	local parts = {}
	for _, v in { ... } do
		table.insert(parts, tostring(v))
	end
	table.insert(stub.Warnings, table.concat(parts, " "))
end
stub.Warnings = {}

return stub
