--!strict
--[[
	Valida a assinatura do template contra o Monster real após ele nascer.
	Só lê dados; nunca cria Motor6D nem altera C0/C1/escala.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Config = require(ReplicatedStorage.Modules.MonsterAnimationConfig)

local MonsterAnimationRigValidation = {}

type Signature = {
	parts: { [string]: BasePart },
	motors: { [string]: Motor6D },
	humanoid: Humanoid?,
	animator: Animator?,
}

local function collect(model: Model): Signature
	local signature: Signature = { parts = {}, motors = {}, humanoid = model:FindFirstChildOfClass("Humanoid"), animator = nil }
	if signature.humanoid then
		signature.animator = signature.humanoid:FindFirstChildOfClass("Animator")
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and table.find(Config.RequiredParts, descendant.Name) then
			if signature.parts[descendant.Name] then
				warn(string.format("[MonsterAnimationRig] %s tem parte R6 duplicada: %s", model:GetFullName(), descendant.Name))
			else
				signature.parts[descendant.Name] = descendant
			end
		elseif descendant:IsA("Motor6D") and table.find(Config.RequiredMotors, descendant.Name) then
			if signature.motors[descendant.Name] then
				warn(string.format("[MonsterAnimationRig] %s tem Motor6D duplicado: %s", model:GetFullName(), descendant.Name))
			else
				signature.motors[descendant.Name] = descendant
			end
		end
	end
	return signature
end

local function sameCFrame(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-4
		and (a.RightVector - b.RightVector).Magnitude < 1e-4
		and (a.UpVector - b.UpVector).Magnitude < 1e-4
		and (a.LookVector - b.LookVector).Magnitude < 1e-4
end

local function validateTemplate(template: Model): boolean
	local signature = collect(template)
	local ok = true
	if not signature.humanoid or signature.humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		warn("[MonsterAnimationRig] Template não possui Humanoid R6.")
		ok = false
	end
	if not signature.animator then
		warn("[MonsterAnimationRig] Template não possui Animator dentro do Humanoid.")
		ok = false
	end
	for _, name in Config.RequiredParts do
		if not signature.parts[name] then warn("[MonsterAnimationRig] Parte ausente no template: " .. name); ok = false end
	end
	for _, name in Config.RequiredMotors do
		if not signature.motors[name] then warn("[MonsterAnimationRig] Motor6D ausente no template: " .. name); ok = false end
	end
	local root = signature.parts.HumanoidRootPart
	if template.PrimaryPart ~= root then
		warn("[MonsterAnimationRig] PrimaryPart deve ser HumanoidRootPart.")
		ok = false
	end
	local rootJoint = signature.motors.RootJoint
	if not rootJoint or rootJoint.Part0 ~= root or rootJoint.Part1 ~= signature.parts.Torso then
		warn("[MonsterAnimationRig] RootJoint deve ligar HumanoidRootPart -> Torso.")
		ok = false
	end
	return ok
end

local function validateAgainstTemplate(template: Model, character: Model)
	local expected, actual = collect(template), collect(character)
	local ok = true
	for _, name in Config.RequiredParts do
		local wanted, found = expected.parts[name], actual.parts[name]
		if not found then
			warn("[MonsterAnimationRig] Monster real sem parte: " .. name)
			ok = false
		elseif wanted and (wanted.Size - found.Size).Magnitude > 1e-4 then
			warn("[MonsterAnimationRig] Tamanho divergente em " .. name)
			ok = false
		end
	end
	for _, name in Config.RequiredMotors do
		local wanted, found = expected.motors[name], actual.motors[name]
		if not found then
			warn("[MonsterAnimationRig] Monster real sem Motor6D: " .. name)
			ok = false
		elseif wanted then
			local expectedPart0, expectedPart1 = wanted.Part0, wanted.Part1
			if not expectedPart0 or not expectedPart1
				or not sameCFrame(wanted.C0, found.C0) or not sameCFrame(wanted.C1, found.C1)
				or expectedPart0 ~= actual.parts[expectedPart0.Name]
				or expectedPart1 ~= actual.parts[expectedPart1.Name] then
				warn("[MonsterAnimationRig] Joint divergente: " .. name .. " (C0/C1 ou ligação)")
				ok = false
			end
		end
	end
	if not actual.animator then
		warn("[MonsterAnimationRig] Monster real está sem Animator.")
		ok = false
	end
	if character.PrimaryPart ~= actual.parts.HumanoidRootPart then
		warn("[MonsterAnimationRig] Monster real está com PrimaryPart incorreto.")
		ok = false
	end
	if ok then print("[MonsterAnimationRig] Validado: template e Monster real têm a mesma assinatura R6.") end
end

function MonsterAnimationRigValidation.Init()
	local template = ReplicatedStorage:FindFirstChild(Config.TemplateName)
	if not template or not template:IsA("Model") then
		warn("[MonsterAnimationRig] ReplicatedStorage." .. Config.TemplateName .. " não foi encontrado.")
		return
	end
	if not validateTemplate(template) then return end
	local function validateWhenAppearanceIsReady(player: Player, character: Model)
		task.spawn(function()
			-- AppearanceManager aplica Model:ScaleTo e o atributo no mesmo spawn.
			-- Esperar esse marco evita comparar o StarterCharacter 1.0x cedo demais.
			for _ = 1, 50 do
				if player:GetAttribute("Role") == GameConfig.Roles.Monster
					and character:GetAttribute("MonsterScaleMultiplier") ~= nil then
					validateAgainstTemplate(template, character)
					return
				end
				task.wait(0.1)
			end
		end)
	end
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			validateWhenAppearanceIsReady(player, character)
		end)
		player:GetAttributeChangedSignal("Role"):Connect(function()
			if player.Character then validateWhenAppearanceIsReady(player, player.Character) end
		end)
		if player.Character then validateWhenAppearanceIsReady(player, player.Character) end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do watch(player) end
	print("[MonsterAnimationRig] Template R6 validado; aguardando spawn do Monster real.")
end

return MonsterAnimationRigValidation
