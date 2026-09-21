--!strict
--[[
	MonsterMeshyVisuals
	Veste o Monstro atual com as MeshParts do modelo Meshy SEM tocar no rig.

	O que NÃO muda: HumanoidRootPart, Humanoid, Motor6D (C0/C1), Size/CFrame/
	colisão das partes R6, animações, poderes, hitbox e a escala 1.2 aplicada
	pelo AppearanceManager. As partes R6 continuam existindo e mandando no
	movimento; elas só ficam invisíveis (Transparency = 1).

	O que muda: para cada uma de Head, Torso, Left Arm, Right Arm, Left Leg e
	Right Leg, clona a MeshPart de mesmo nome do template
	ServerStorage.MonsterMeshyVisuals (MeshId, TextureID e SurfaceAppearance
	vêm junto no clone), encaixa na caixa da parte R6 correspondente e solda
	nela com WeldConstraint. Os visuais moram em character.MeshyVisuals com
	nomes "Meshy<Parte>" -- nunca com o nome de uma parte R6, para o validador
	MonsterAnimationRigValidation não achar parte duplicada.

	ENCAIXE (por peça, em AssetRegistry.Monstro_Modelo.Meshy.Parts):
	  tamanho do visual = Size ATUAL da parte R6 * Fit (por eixo)
	  centro do visual  = CFrame da parte R6 * (Size ATUAL * Offset)
	Como parte do Size que a parte tem agora (já em 1.2x), o visual acompanha
	a escala do monstro e não fica gigante. Fit/Offset = 1/0 preenchem a caixa
	da parte inteira; ajuste só uma peça mexendo só na entrada dela.

	Sem template válido (MeshId vazio em alguma peça, peça faltando) NADA é
	aplicado e o Monstro continua com a aparência anterior: nunca fica meio
	invisível.

	Uso:
		local ok, reason = MonsterMeshyVisuals.Apply(character, config)
		MonsterMeshyVisuals.Clear(character)
]]

local ServerStorage = game:GetService("ServerStorage")

local MonsterMeshyVisuals = {}

export type PartFit = { Fit: Vector3?, Offset: Vector3? }
export type Config = {
	Enabled: boolean,
	TemplateName: string,
	Parts: { [string]: PartFit },
}

MonsterMeshyVisuals.PART_NAMES = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
MonsterMeshyVisuals.FOLDER_NAME = "MeshyVisuals"

local ORIGINAL_TRANSPARENCY_ATTRIBUTE = "MonsterMeshyOriginalTransparency"
local TOLERANCE = 1e-3

local function visualName(partName: string): string
	return "Meshy" .. (partName:gsub("%s", ""))
end
MonsterMeshyVisuals.VisualName = visualName

local function fitOf(config: Config, partName: string): (Vector3, Vector3)
	local entry = config.Parts[partName]
	return (entry and entry.Fit) or Vector3.new(1, 1, 1), (entry and entry.Offset) or Vector3.new(0, 0, 0)
end

-- Caixa do visual em relação à parte R6 ATUAL: (Size do visual, deslocamento do centro).
local function fitBox(config: Config, partName: string, base: BasePart): (Vector3, Vector3)
	local fit, offset = fitOf(config, partName)
	local size = base.Size
	return Vector3.new(size.X * fit.X, size.Y * fit.Y, size.Z * fit.Z),
		Vector3.new(size.X * offset.X, size.Y * offset.Y, size.Z * offset.Z)
end

local function findTemplate(config: Config): Instance?
	return ServerStorage:FindFirstChild(config.TemplateName)
end

-- Template pronto = as 6 MeshParts existem e todas têm MeshId.
function MonsterMeshyVisuals.CheckTemplate(config: Config): (boolean, string?)
	if not config.Enabled then
		return false, "Meshy.Enabled = false"
	end
	local template = findTemplate(config)
	if not template then
		return false, "ServerStorage." .. config.TemplateName .. " não existe"
	end
	for _, name in MonsterMeshyVisuals.PART_NAMES do
		local source = template:FindFirstChild(name)
		if not (source and source:IsA("MeshPart")) then
			return false, "template sem MeshPart '" .. name .. "'"
		end
		if (source :: MeshPart).MeshId == "" then
			return false, "MeshPart '" .. name .. "' do template sem MeshId (importe as malhas e preencha asset_ids.json)"
		end
	end
	return true, nil
end

function MonsterMeshyVisuals.Clear(character: Model)
	local folder = character:FindFirstChild(MonsterMeshyVisuals.FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
	for _, name in MonsterMeshyVisuals.PART_NAMES do
		local base = character:FindFirstChild(name)
		if base and base:IsA("BasePart") then
			local original = base:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE)
			if type(original) == "number" then
				base.Transparency = original
				base:SetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE, nil)
			end
		end
	end
end

-- Devolve (true) se aplicou; (false, motivo) se não mexeu em nada.
function MonsterMeshyVisuals.Apply(character: Model, config: Config): (boolean, string?)
	MonsterMeshyVisuals.Clear(character)

	local ready, reason = MonsterMeshyVisuals.CheckTemplate(config)
	if not ready then
		return false, reason
	end
	local template = findTemplate(config) :: Instance

	-- Tudo validado ANTES de esconder qualquer parte.
	local bases: { [string]: BasePart } = {}
	for _, name in MonsterMeshyVisuals.PART_NAMES do
		local base = character:FindFirstChild(name)
		if not (base and base:IsA("BasePart")) then
			return false, "character sem a parte R6 '" .. name .. "'"
		end
		bases[name] = base :: BasePart
	end

	local folder = Instance.new("Folder")
	folder.Name = MonsterMeshyVisuals.FOLDER_NAME
	for _, name in MonsterMeshyVisuals.PART_NAMES do
		local base = bases[name]
		local size, offset = fitBox(config, name, base)

		local visual = (template:FindFirstChild(name) :: MeshPart):Clone()
		visual.Name = visualName(name)
		-- O clone só serve de aparência: nada de juntas/scripts/attachments herdados.
		for _, child in visual:GetChildren() do
			if not (child:IsA("SurfaceAppearance") or child:IsA("Decal") or child:IsA("Texture")) then
				child:Destroy()
			end
		end
		visual.Anchored = false
		visual.CanCollide = false
		visual.CanTouch = false
		visual.CanQuery = false
		visual.Massless = true
		visual.Transparency = 0
		visual.Size = size
		visual.CFrame = base.CFrame * CFrame.new(offset.X, offset.Y, offset.Z)
		visual.Parent = folder

		local weld = Instance.new("WeldConstraint")
		weld.Name = "MeshyWeld"
		weld.Part0 = base
		weld.Part1 = visual
		weld.Parent = visual

		base:SetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE, base.Transparency)
		base.Transparency = 1
	end
	folder.Parent = character
	return true, nil
end

--------------------------------------------------------------------------------
-- Verificação
--------------------------------------------------------------------------------

local function fmt(v: Vector3): string
	return string.format("%.4f,%.4f,%.4f", v.X, v.Y, v.Z)
end

local function fmtCFrame(cf: CFrame): string
	return fmt(cf.Position) .. "|" .. fmt(cf.RightVector) .. "|" .. fmt(cf.UpVector)
end

--[[
	Foto do rig: tudo que NÃO pode mudar ao aplicar a aparência. Só olha os
	filhos diretos do character (as partes R6, o Humanoid e os Motor6D dentro
	delas) -- os visuais ficam em MeshyVisuals e não entram. Transparency fica
	de fora de propósito: é o que a aparência muda.
]]
function MonsterMeshyVisuals.RigSnapshot(character: Model): { [string]: string }
	local snapshot: { [string]: string } = {}
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") then
			local part = child :: BasePart
			snapshot["Part:" .. part.Name] = string.format(
				"size=%s cf=%s collide=%s query=%s touch=%s anchored=%s massless=%s",
				fmt(part.Size), fmtCFrame(part.CFrame), tostring(part.CanCollide), tostring(part.CanQuery),
				tostring(part.CanTouch), tostring(part.Anchored), tostring(part.Massless)
			)
			for _, sub in part:GetChildren() do
				if sub:IsA("Motor6D") then
					local motor = sub :: Motor6D
					snapshot["Motor6D:" .. motor.Name] = string.format(
						"%s->%s C0=%s C1=%s",
						motor.Part0 and motor.Part0.Name or "nil", motor.Part1 and motor.Part1.Name or "nil",
						fmtCFrame(motor.C0), fmtCFrame(motor.C1)
					)
				end
			end
		elseif child:IsA("Humanoid") then
			local humanoid = child :: Humanoid
			snapshot["Humanoid"] = string.format("rig=%s hip=%.4f", humanoid.RigType.Name, humanoid.HipHeight)
		end
	end
	return snapshot
end

function MonsterMeshyVisuals.DiffSnapshots(before: { [string]: string }, after: { [string]: string }): { string }
	local problems = {}
	for key, value in before do
		if after[key] == nil then
			table.insert(problems, "sumiu: " .. key)
		elseif after[key] ~= value then
			table.insert(problems, "mudou: " .. key .. "\n    antes:  " .. value .. "\n    depois: " .. after[key])
		end
	end
	for key in after do
		if before[key] == nil then
			table.insert(problems, "apareceu: " .. key)
		end
	end
	table.sort(problems)
	return problems
end

-- Confere o resultado de Apply em um character: visual certo, no lugar certo, soldado.
function MonsterMeshyVisuals.Verify(character: Model, config: Config): { string }
	local problems = {}
	local folder = character:FindFirstChild(MonsterMeshyVisuals.FOLDER_NAME)
	if not folder then
		return { "character sem a pasta " .. MonsterMeshyVisuals.FOLDER_NAME }
	end
	for _, name in MonsterMeshyVisuals.PART_NAMES do
		local base = character:FindFirstChild(name)
		local visual = folder:FindFirstChild(visualName(name))
		if not (base and base:IsA("BasePart")) then
			table.insert(problems, name .. ": parte R6 ausente")
		elseif not (visual and visual:IsA("MeshPart")) then
			table.insert(problems, name .. ": MeshPart visual ausente")
		else
			local part, mesh = base :: BasePart, visual :: MeshPart
			local size, offset = fitBox(config, name, part)
			local expected = part.CFrame * CFrame.new(offset.X, offset.Y, offset.Z)
			if (mesh.Size - size).Magnitude > TOLERANCE then
				table.insert(problems, string.format("%s: Size %s, esperado %s", name, fmt(mesh.Size), fmt(size)))
			end
			if (mesh.CFrame.Position - expected.Position).Magnitude > TOLERANCE
				or (mesh.CFrame.LookVector - expected.LookVector).Magnitude > TOLERANCE
				or (mesh.CFrame.UpVector - expected.UpVector).Magnitude > TOLERANCE
			then
				table.insert(problems, name .. ": visual fora da posição/rotação esperada")
			end
			if mesh.MeshId == "" then
				table.insert(problems, name .. ": visual sem MeshId")
			end
			local weld = mesh:FindFirstChildOfClass("WeldConstraint")
			if not (weld and weld.Part0 == part and weld.Part1 == mesh) then
				table.insert(problems, name .. ": visual não está soldado à parte R6")
			end
			if part.Transparency ~= 1 then
				table.insert(problems, name .. ": parte R6 ainda visível (vai aparecer por baixo do visual)")
			end
			if mesh.CanCollide or mesh.CanQuery or mesh.CanTouch or not mesh.Massless then
				table.insert(problems, name .. ": visual não é puramente cosmético (colisão/massa)")
			end
		end
	end
	return problems
end

return MonsterMeshyVisuals
