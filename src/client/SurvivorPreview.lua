--!strict
-- Owns one active viewport and at most one retiring viewport during crossfade.
local UI = require(script.Parent.SurvivorSelectionTheme)
local Portrait = require(script.Parent.SurvivorPortrait)
local Preview = {}
function Preview.Create(parent: Instance): any
	local root = UI.Frame(parent, "HeroPreview")
	local stage = UI.Frame(root, "Stage")
	stage.Position = UDim2.fromScale(0.1, 0)
	stage.Size = UDim2.fromScale(0.8, 1)
	local active: any = nil
	local retiring: any = nil
	local generation = 0
	local result: any = { Root = root, Id = nil }
	function result.Set(id: string)
		if result.Id == id then return end
		result.Id = id
		generation += 1
		local token = generation
		if retiring then retiring.Destroy(); retiring = nil end
		retiring = active
		if retiring then UI.Tween(retiring.Root, { ImageTransparency = 1 }, 0.18) end
		active = Portrait.Viewport(stage, id)
		active.Root.ImageTransparency = 1
		active.Root.Position = UDim2.fromOffset(12, 0)
		UI.Tween(active.Root, { ImageTransparency = 0, Position = UDim2.new() }, 0.28)
		active.PlayIdle()
		task.delay(0.3, function()
			if token == generation and retiring then retiring.Destroy(); retiring = nil end
		end)
	end
	function result.Step(time: number)
		if active then active.Step(time) end
	end
	function result.Clear()
		generation += 1
		if active then active.Destroy(); active = nil end
		if retiring then retiring.Destroy(); retiring = nil end
		result.Id = nil
	end
	return result
end
return Preview
