--!strict
-- Roblox Studio plugin: Monster Animation Preview.
-- Instale como Local Plugin e use o botão "Monster Preview" na toolbar.
-- Não é um LocalScript: não aparece para jogadores durante Play.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local TOOLBAR_NAME = "Monster Animation"
local BUTTON_NAME = "Monster Preview"
local WIDGET_ID = "MonsterAnimationPreviewWidget_v1"
local PREVIEW_NAME = "MonsterAnimationPreview_Studio"
local AUTHORING_NAME = "Monster Animation Rig (Authoring)"
local TEMPLATE_NAME = "MonsterAnimationRig"

local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)
local toggleButton = toolbar:CreateButton(BUTTON_NAME, "Abrir/fechar o preview local do Monster", "")
toggleButton.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(WIDGET_ID, DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false,
	false,
	390,
	252,
	300,
	220
))
widget.Title = "Monster Animation Preview"

local previewRig: Model? = nil
local previewTrack: AnimationTrack? = nil
local savedCameraCFrame: CFrame? = nil
local selected = "Idle"

local function make(className: string, properties: { [string]: any }, parent: Instance?): Instance
	local object = Instance.new(className)
	for property, value in properties do object[property] = value end
	object.Parent = parent
	return object
end

local background = make("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(18, 20, 27), BorderSizePixel = 0,
}, widget)
make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, background)

local layout = make("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, background) :: UIListLayout

make("TextLabel", {
	LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
	Text = "MONSTER ANIMATION PREVIEW", TextColor3 = Color3.fromRGB(240, 240, 245),
	Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
}, background)

local idBox = make("TextBox", {
	LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(38, 42, 55), BorderSizePixel = 0,
	ClearTextOnFocus = false, PlaceholderText = "rbxassetid:// animação publicada", Text = "",
	TextColor3 = Color3.fromRGB(245, 245, 245), Font = Enum.Font.Code, TextSize = 13,
}, background) :: TextBox
make("UICorner", { CornerRadius = UDim.new(0, 5) }, idBox)

local kindsFrame = make("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1 }, background)
make("UIGridLayout", {
	CellSize = UDim2.new(1 / 3, -5, 0, 27), CellPadding = UDim2.fromOffset(7, 7), SortOrder = Enum.SortOrder.LayoutOrder,
}, kindsFrame)

local controlsFrame = make("Frame", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, background)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, controlsFrame)

local status = make("TextLabel", {
	LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 35), BackgroundTransparency = 1,
	Text = "Abra o painel apenas quando quiser testar. Nada é criado durante Play.",
	TextColor3 = Color3.fromRGB(184, 194, 208), Font = Enum.Font.Gotham, TextSize = 11,
	TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, background) :: TextLabel

local function setStatus(text: string) status.Text = text end

local function configId(kind: string): string
	local configModule = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("MonsterAnimationConfig")
	if not configModule or not configModule:IsA("ModuleScript") then return "" end
	local ok, config = pcall(require, configModule)
	if not ok or type(config) ~= "table" or type(config.AnimationIds) ~= "table" then return "" end
	return if type(config.AnimationIds[kind]) == "string" then config.AnimationIds[kind] else ""
end

local function makeButton(parent: Instance, label: string, width: number): TextButton
	local button = make("TextButton", {
		Size = UDim2.fromOffset(width, 28), BackgroundColor3 = Color3.fromRGB(54, 60, 78), BorderSizePixel = 0,
		Text = label, TextColor3 = Color3.fromRGB(245, 245, 245), Font = Enum.Font.GothamSemibold, TextSize = 11,
	}, parent) :: TextButton
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, button)
	return button
end

local function stopTrack()
	if previewTrack then
		pcall(function() previewTrack:Stop(0.1); previewTrack:Destroy() end)
		previewTrack = nil
	end
end

local function restoreCamera()
	local camera = Workspace.CurrentCamera
	if camera and savedCameraCFrame then camera.CFrame = savedCameraCFrame end
	savedCameraCFrame = nil
end

local function clearPreview()
	stopTrack()
	if previewRig then previewRig:Destroy(); previewRig = nil end
	local leftOver = Workspace:FindFirstChild(PREVIEW_NAME)
	if leftOver and leftOver:IsA("Model") then leftOver:Destroy() end
	restoreCamera()
end

local function createAuthoringRig()
	local existing = Workspace:FindFirstChild(AUTHORING_NAME)
	if existing and existing:IsA("Model") then
		Selection:Set({ existing })
		setStatus("O rig de autoria já existe e foi selecionado.")
		return
	end
	local template = ReplicatedStorage:FindFirstChild(TEMPLATE_NAME)
	if not template or not template:IsA("Model") then
		setStatus("ReplicatedStorage.MonsterAnimationRig não foi encontrado.")
		return
	end
	local rig = template:Clone()
	rig.Name = AUTHORING_NAME
	rig:SetAttribute("AnimationRig", true)
	rig:SetAttribute("SourceTemplate", template:GetFullName())
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		rig:Destroy()
		setStatus("Template inválido: Humanoid ausente.")
		return
	end
	if not humanoid:FindFirstChildOfClass("Animator") then Instance.new("Animator").Parent = humanoid end
	for _, item in rig:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = item.Name == "HumanoidRootPart"
			item.CanCollide, item.CanTouch, item.CanQuery, item.Massless = false, false, false, true
		end
	end
	rig.Parent = Workspace
	rig:PivotTo(CFrame.new(0, rig:GetExtentsSize().Y * 0.5, 0))
	Selection:Set({ rig })
	ChangeHistoryService:SetWaypoint("Criar Monster Animation Rig")
	setStatus("Rig criado no Workspace e selecionado para o Animation Editor.")
end

local function spawn()
	clearPreview()
	local template = ReplicatedStorage:FindFirstChild(TEMPLATE_NAME)
	if not template or not template:IsA("Model") then
		setStatus("ReplicatedStorage.MonsterAnimationRig não foi encontrado.")
		return
	end
	previewRig = template:Clone()
	previewRig.Name = PREVIEW_NAME
	for _, item in previewRig:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = item.Name == "HumanoidRootPart"
			item.CanCollide, item.CanTouch, item.CanQuery, item.Massless = false, false, false, true
		end
	end
	previewRig.Parent = Workspace
	previewRig:PivotTo(CFrame.new(0, 3.6, 0))

	local camera = Workspace.CurrentCamera
	if camera then
		savedCameraCFrame = camera.CFrame
		local focus = previewRig:GetPivot().Position + Vector3.new(0, 2.2, 0)
		camera.CFrame = CFrame.lookAt(previewRig:GetPivot().Position + Vector3.new(10, 6, 15), focus)
	end
	setStatus("Clone local de Studio criado. Use Limpar ao terminar; ele não entra no gameplay.")
end

local function play()
	if not previewRig then spawn() end
	if not previewRig then return end
	local id = idBox.Text
	if id == "" or id == "rbxassetid://0" then setStatus("Informe um AnimationId publicado."); return end
	local humanoid = previewRig:FindFirstChildOfClass("Humanoid")
	if not humanoid then setStatus("Humanoid ausente no template."); return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then animator = Instance.new("Animator"); animator.Parent = humanoid end
	stopTrack()
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	animation:Destroy()
	if not ok or not track then setStatus("Falha ao carregar o AnimationId. Confira dono/permissão/R6."); return end
	previewTrack = track
	previewTrack.Priority = if selected == "Idle" or selected == "Walk" or selected == "Run"
		then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action
	previewTrack.Looped = selected == "Idle" or selected == "Walk" or selected == "Run"
	previewTrack:Play(0.12)
	setStatus(selected .. " tocando no clone exato do Monster.")
end

for _, kind in { "Idle", "Walk", "Run", "Attack", "Damage", "Death" } do
	local button = makeButton(kindsFrame, kind, 1)
	button.Size = UDim2.new(1 / 3, -5, 0, 27) -- UIGridLayout controla a disposição.
	button.MouseButton1Click:Connect(function()
		selected = kind
		idBox.Text = configId(kind)
		setStatus("Categoria selecionada: " .. kind)
	end)
end

makeButton(controlsFrame, "Criar Rig", 62).MouseButton1Click:Connect(createAuthoringRig)
makeButton(controlsFrame, "Spawn", 52).MouseButton1Click:Connect(spawn)
makeButton(controlsFrame, "Play", 43).MouseButton1Click:Connect(play)
makeButton(controlsFrame, "Pause", 49).MouseButton1Click:Connect(function()
	if previewTrack then previewTrack:AdjustSpeed(0); setStatus("Pausado.") end
end)
makeButton(controlsFrame, "Reiniciar", 62).MouseButton1Click:Connect(function()
	if previewTrack then previewTrack.TimePosition = 0; previewTrack:AdjustSpeed(1); previewTrack:Play(0) else play() end
end)
makeButton(controlsFrame, "Limpar", 48).MouseButton1Click:Connect(function()
	clearPreview()
	setStatus("Preview removido e câmera restaurada.")
end)

toggleButton.Click:Connect(function()
	if widget.Enabled then
		widget.Enabled = false
		clearPreview()
	else
		widget.Enabled = true
	end
end)
plugin.Unloading:Connect(clearPreview)
