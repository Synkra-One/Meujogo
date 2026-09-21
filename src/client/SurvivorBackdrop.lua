--!strict
-- Entirely native night forest: layered silhouettes, diffuse moonlight and mist.
-- Optional art is rendered behind the readability veil; no world Lighting changes.
local UI = require(script.Parent.SurvivorSelectionTheme)
local Assets = require(script.Parent.SurvivorSelectionAssets)
local Backdrop = {}
function Backdrop.Create(parent: Instance): any
	local root = UI.Frame(parent, "NightForest")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 0
	root.BackgroundColor3 = Color3.fromRGB(12, 26, 33)
	root.ClipsDescendants = true
	UI.Create("UIGradient", root, { Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(19, 38, 49)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(13, 30, 36)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 10, 14)),
	}) })
	local glow = UI.Frame(root, "Moonlight")
	glow.Position = UDim2.fromScale(0.28, 0.18)
	glow.Size = UDim2.fromScale(0.5, 0.65)
	for i = 10, 1, -1 do
		local halo = UI.Frame(glow, "Diffuse" .. i)
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = UDim2.fromScale(0.5, 0.5)
		halo.Size = UDim2.fromScale(i / 10, i / 10)
		halo.BackgroundTransparency = 0.975
		halo.BackgroundColor3 = Color3.fromRGB(100, 170, 184)
		UI.Create("UICorner", halo, { CornerRadius = UDim.new(1, 0) })
	end
	local random = Random.new(482)
	for layer = 1, 3 do
		for i = 1, 13 do
			local tree = UI.Frame(root, "Forest" .. layer .. "_" .. i)
			tree.AnchorPoint = Vector2.new(0.5, 1)
			tree.Position = UDim2.fromScale((i - 1) / 12 + random:NextNumber(-0.025, 0.025), 0.8 + layer * 0.045)
			tree.Size = UDim2.fromScale(0.007 + layer * 0.002, random:NextNumber(0.28, 0.7))
			tree.Rotation = random:NextNumber(-5, 5)
			tree.BackgroundColor3 = Color3.fromRGB(4 + (3 - layer) * 4, 13 + (3 - layer) * 5, 18 + (3 - layer) * 6)
			tree.BackgroundTransparency = 0.12 + (3 - layer) * 0.12
			for branch = 1, 5 do
				for _, direction in { -1, 1 } do
					local limb = UI.Frame(tree, "Branch")
					limb.AnchorPoint = Vector2.new(0.5, 0.5)
					limb.Position = UDim2.fromScale(0.5 + direction * (0.7 + branch * 0.32), 0.12 + branch * 0.12)
					limb.Size = UDim2.new(2 + branch * 0.45, 0, 0, 3 + layer * 2)
					limb.Rotation = direction * 32
					limb.BackgroundColor3 = tree.BackgroundColor3
					limb.BackgroundTransparency = tree.BackgroundTransparency
				end
			end
		end
	end
	local art = UI.Create("ImageLabel", root, { Name = "CustomBackground", Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Crop, Visible = false })
	local mist = UI.Frame(root, "Mist")
	mist.Position = UDim2.fromScale(0, 0.48)
	mist.Size = UDim2.fromScale(1, 0.45)
	mist.BackgroundColor3 = Color3.fromRGB(71, 111, 122)
	mist.BackgroundTransparency = 0.77
	UI.Create("UIGradient", mist, { Rotation = 90, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.4), NumberSequenceKeypoint.new(1, 1),
	}) })
	for _, rotation in { 0, 90, 180, 270 } do
		local veil = UI.Frame(root, "Vignette" .. rotation)
		veil.Size = UDim2.fromScale(1, 1)
		veil.BackgroundTransparency = 0
		veil.BackgroundColor3 = Color3.fromRGB(3, 8, 12)
		UI.Create("UIGradient", veil, { Rotation = rotation, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.36, 0.94), NumberSequenceKeypoint.new(1, 1),
		}) })
	end
	local result = { Root = root }
	function result.Update(reference: string?, accent: Color3)
		local content = Assets.Content("Backgrounds", reference)
		if art.Image ~= content then
			art.Image = content
			art.Visible = content ~= ""
			art.ImageTransparency = 1
			UI.Tween(art, { ImageTransparency = 0.35 }, 0.4)
		end
		UI.Tween(mist, { BackgroundColor3 = accent:Lerp(Color3.fromRGB(61, 89, 103), 0.65) }, 0.4)
	end
	return result
end
return Backdrop
