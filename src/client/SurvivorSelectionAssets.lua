--!strict
-- References may be a Roblox URI or an instance name in the organized folders.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = {}
function Assets.Find(folderName: string, reference: string?): Instance?
	if not reference or reference == "" then return nil end
	local root = ReplicatedStorage:FindFirstChild("SelectionAssets")
	local folder = root and root:FindFirstChild(folderName)
	return folder and folder:FindFirstChild(reference)
end
function Assets.Content(folderName: string, reference: string?): string
	if not reference or reference == "" or reference == "rbxassetid://0" then return "" end
	if string.match(reference, "^rbxasset") then return reference end
	local asset = Assets.Find(folderName, reference)
	if not asset then return "" end
	if asset:IsA("StringValue") then return asset.Value end
	if asset:IsA("Decal") or asset:IsA("Texture") then return asset.Texture end
	if asset:IsA("ImageLabel") or asset:IsA("ImageButton") then return asset.Image end
	if asset:IsA("Sound") then return asset.SoundId end
	if asset:IsA("Animation") then return asset.AnimationId end
	return ""
end
return Assets
