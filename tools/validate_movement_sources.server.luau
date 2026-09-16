local StarterPlayer = game:GetService("StarterPlayer")
local scripts = StarterPlayer:FindFirstChild("StarterCharacterScripts")
assert(scripts, "StarterCharacterScripts não encontrado")

for _, name in { "Animate", "Crouching" } do
	local source = scripts:FindFirstChild(name)
	assert(source and source:IsA("LuaSourceContainer"), name .. " não encontrado")
	local compiled, syntaxError = loadstring(source.Source, "=" .. source:GetFullName())
	assert(compiled, syntaxError)
	print(string.format("[ValidateMovementSources] %s compilado", source:GetFullName()))
end

return true
