local HttpService = game:GetService("HttpService")

local RELEVANT_CLASSES = {
	Folder = true,
	Model = true,
	Script = true,
	LocalScript = true,
	ModuleScript = true,
	RemoteEvent = true,
	RemoteFunction = true,
	BindableEvent = true,
	BindableFunction = true,
	ScreenGui = true,
	Tool = true,
	Animation = true,
}

local roots = {
	game:GetService("Workspace"),
	game:GetService("ReplicatedStorage"),
	game:GetService("ServerScriptService"),
	game:GetService("ServerStorage"),
	game:GetService("StarterPlayer"),
	game:GetService("StarterGui"),
	game:GetService("StarterPack"),
	game:GetService("SoundService"),
}

local duplicates = {}
local animates = {}

local function describe(instance)
	local result = {
		className = instance.ClassName,
		path = instance:GetFullName(),
		debugId = instance:GetDebugId(16),
	}

	if instance:IsA("LuaSourceContainer") then
		local ok, source = pcall(function()
			return instance.Source
		end)
		result.sourceLength = if ok then #source else -1
		result.disabled = instance:IsA("BaseScript") and instance.Disabled or nil
	elseif instance:IsA("Animation") then
		result.animationId = instance.AnimationId
	end

	local children = {}
	for _, child in instance:GetChildren() do
		children[child.Name .. ":" .. child.ClassName] = (children[child.Name .. ":" .. child.ClassName] or 0) + 1
	end
	result.children = children

	return result
end

local function walk(parent)
	local groups = {}
	for _, child in parent:GetChildren() do
		if RELEVANT_CLASSES[child.ClassName] then
			groups[child.Name] = groups[child.Name] or {}
			table.insert(groups[child.Name], child)
		end

		if child:IsA("LuaSourceContainer") and string.lower(child.Name) == "animate" then
			local info = describe(child)
			info.animations = {}
			for _, descendant in child:GetDescendants() do
				if descendant:IsA("Animation") then
					table.insert(info.animations, describe(descendant))
				end
			end
			table.insert(animates, info)
		end
	end

	for name, instances in groups do
		if #instances > 1 then
			local isWorkspaceDecoration = parent:IsDescendantOf(game:GetService("Workspace"))
				and instances[1]:IsA("Model")
				and parent ~= game:GetService("Workspace")
			if isWorkspaceDecoration then
				continue
			end
			local entry = {
				parent = parent:GetFullName(),
				name = name,
				items = {},
			}
			for _, instance in instances do
				table.insert(entry.items, describe(instance))
			end
			table.insert(duplicates, entry)
		end
	end

	for _, child in parent:GetChildren() do
		walk(child)
	end
end

for _, root in roots do
	walk(root)
end

print("__DUPLICATE_REPORT__" .. HttpService:JSONEncode(duplicates))
print("__ANIMATE_REPORT__" .. HttpService:JSONEncode(animates))

return true
