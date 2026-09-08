--!strict
--[[
	UtilityItemSystem
	Efeitos de uso da Lanterna e do Chocolate -- os dois únicos itens desta
	leva com modelo REAL do Toolbox (ToolFactory.lua/AssetLoader.lua), não
	placeholder.

	LANTERNA: Tool.Activated alterna o SpotLight "LanternaLuz" (visual,
	criado por ToolFactory) E a fraqueza do Monstro (MonsterLightWeakness.
	ActivateLightSource/DeactivateLightSource -- mesmo raio/empurrão/
	combustível de 120s que a Tocha usa, só acionado por escolha do
	jogador em vez de automático ao equipar). Sem combustível, Activate
	devolve false e a luz visual nem acende -- os dois efeitos ficam
	sempre em sincronia (nunca ilumina sem also contar como fraqueza, nem
	o contrário). Desequipar força as duas coisas a desligar, pra não
	sobrar luz acesa "esquecida" na Backpack.

	CHOCOLATE: Tool.Activated cura GameConfig.Health.ChocolateHeal na hora e
	se destrói (consumível, um uso só).

	BANDAGEM: Tool.Activated começa uma CANALIZAÇÃO (estilo Left 4 Dead) --
	GameConfig.Bandagem.ChannelTime segundos tocando a animação "Healing
	(L4D2)", e SÓ NO FIM cura GameConfig.Bandagem.Heal e consome a Tool.
	Tomar dano (CancelOnDamage), desequipar/dropar, morrer ou -- se
	CancelOnMove -- andar demais no meio CANCELA sem gastar a bandagem.
	Vida cheia não deixa nem começar. A passiva da Sofia ("+40% de cura")
	multiplica o resultado. O ID da animação vai em GameConfig.Bandagem.
	AnimationId -- enquanto for "0", a cura funciona igual, só sem animação.

	Os dois passam pela porta única de cura (DamageSystem.Heal), que respeita
	MaxHealth e não ressuscita ninguém.

	Uso (chamar uma vez no boot do servidor, depois de MonsterLightWeakness.Init()):
		local UtilityItemSystem = require(script.UtilityItemSystem)
		UtilityItemSystem.Init()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local ItemRegistry = require(ReplicatedStorage.Modules.ItemRegistry)
local SafeAttribute = require(ReplicatedStorage.Modules.SafeAttribute)
local MonsterLightWeakness = require(script.Parent.MonsterLightWeakness)
local DamageSystem = require(script.Parent.DamageSystem)

local UtilityItemSystem = {}

local watchedTools: { [Tool]: true } = {}

--------------------------------------------------------------------------------
-- Lanterna
--------------------------------------------------------------------------------

local function getLanternaLight(tool: Tool): Light?
	local handle = tool:FindFirstChild("Handle")
	local light = handle and handle:FindFirstChild("LanternaLuz")
	if light and light:IsA("Light") then
		return light
	end
	return nil
end

local function turnLanternaOff(tool: Tool)
	local light = getLanternaLight(tool)
	if light then
		light.Enabled = false
	end
	MonsterLightWeakness.DeactivateLightSource(tool)
end

local function onLanternaActivated(tool: Tool)
	if tool.Parent and tool.Parent:GetAttribute("ShadowRushBusy") == true then return end
	local light = getLanternaLight(tool)
	if not light then
		return
	end

	if light.Enabled then
		turnLanternaOff(tool)
	else
		local turnedOn = MonsterLightWeakness.ActivateLightSource(tool)
		light.Enabled = turnedOn -- sem combustível, nem acende
	end
end

--------------------------------------------------------------------------------
-- Chocolate
--------------------------------------------------------------------------------

local function onChocolateActivated(player: Player, tool: Tool)
	local character = player.Character
	if character and character:GetAttribute("ShadowRushBusy") == true then return end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Cura FIXA (GameConfig.Health.ChocolateHeal), não mais cura total.
	-- PASSIVA da Sofia ("cura 40% mais eficaz"): multiplica só pra ela.
	local amount = GameConfig.Health.ChocolateHeal
	if player:GetAttribute("PassivaCuraExtra") == true then
		amount *= GameConfig.Health.PassivaCuraExtraMultiplier
	end

	local healed = DamageSystem.Heal(humanoid, amount)
	print(string.format("[UtilityItemSystem] %s comeu o Chocolate (+%d HP).", player.Name, healed))
	tool:Destroy()
end

--------------------------------------------------------------------------------
-- Bandagem (cura com canalização, estilo Left 4 Dead)
--------------------------------------------------------------------------------

local BANDAGE = GameConfig.Bandagem

-- player -> true enquanto está no meio de uma canalização (trava usar 2x).
local healingNow: { [Player]: true } = {}

local function getAnimator(humanoid: Humanoid): Animator?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	return if animator then animator else nil
end

local function playHealAnimation(humanoid: Humanoid): AnimationTrack?
	if BANDAGE.AnimationId == "rbxassetid://0" or BANDAGE.AnimationId == "" then
		return nil -- ID ainda não colado -- cura funciona, só sem animação
	end
	local animator = getAnimator(humanoid)
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = BANDAGE.AnimationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true -- segura a pose durante toda a canalização
	track:Play(BANDAGE.AnimationFadeTime)
	return track
end

local function onBandagemActivated(player: Player, tool: Tool)
	if player.Character and player.Character:GetAttribute("ShadowRushBusy") == true then return end
	if healingNow[player] then
		return -- já está usando uma
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	if humanoid.Health <= 0 then
		return
	end
	if humanoid.Health >= humanoid.MaxHealth - 0.5 then
		return -- vida cheia: não desperdiça a bandagem
	end

	healingNow[player] = true
	local track = playHealAnimation(humanoid)

	local function stopAnim()
		if track then
			track:Stop(BANDAGE.AnimationFadeTime)
			track:Destroy()
		end
	end

	-- Canalização: espera ChannelTime checando cancelamento em pedaços.
	local startHealth = humanoid.Health
	local startPos = root.Position
	local elapsed = 0
	local cancelled: string? = nil

	while elapsed < BANDAGE.ChannelTime do
		local slice = math.min(0.1, BANDAGE.ChannelTime - elapsed)
		task.wait(slice)
		elapsed += slice

		if not character.Parent or not humanoid.Parent or humanoid.Health <= 0 then
			cancelled = "morreu"
			break
		end
		if tool.Parent ~= character then
			cancelled = "desequipou" -- guardou / dropou / trocou de item
			break
		end
		if BANDAGE.CancelOnDamage and humanoid.Health < startHealth - 0.01 then
			cancelled = "tomou dano"
			break
		end
		if BANDAGE.CancelOnMove and (root.Position - startPos).Magnitude > BANDAGE.MoveCancelDistance then
			cancelled = "se moveu"
			break
		end
	end

	healingNow[player] = nil
	stopAnim()

	if cancelled then
		print(string.format("[UtilityItemSystem] %s cancelou a bandagem (%s) -- não gastou.", player.Name, cancelled))
		return
	end

	-- Terminou: cura e consome. PASSIVA da Sofia multiplica.
	local amount = BANDAGE.Heal
	if player:GetAttribute("PassivaCuraExtra") == true then
		amount *= GameConfig.Health.PassivaCuraExtraMultiplier
	end
	local healed = DamageSystem.Heal(humanoid, amount)
	print(string.format("[UtilityItemSystem] %s usou a Bandagem (+%d HP).", player.Name, healed))
	tool:Destroy()
end

--------------------------------------------------------------------------------
-- Descoberta de Tools (existentes + futuras)
--------------------------------------------------------------------------------

local function watchUtilityItem(tool: Instance)
	if not tool:IsA("Tool") or watchedTools[tool] then
		return
	end

	if SafeAttribute.Get(tool, ItemRegistry.Items.Lanterna.AttributeName) == true then
		watchedTools[tool] = true

		tool.Activated:Connect(function()
			onLanternaActivated(tool)
		end)
		tool.Unequipped:Connect(function()
			turnLanternaOff(tool)
		end)
		tool.Destroying:Connect(function()
			watchedTools[tool] = nil
		end)
	elseif SafeAttribute.Get(tool, ItemRegistry.Items.Chocolate.AttributeName) == true then
		watchedTools[tool] = true

		tool.Activated:Connect(function()
			local character = tool.Parent
			local player = character and character:IsA("Model") and Players:GetPlayerFromCharacter(character)
			if player then
				onChocolateActivated(player, tool)
			end
		end)
		tool.Destroying:Connect(function()
			watchedTools[tool] = nil
		end)
	elseif SafeAttribute.Get(tool, ItemRegistry.Items.Bandagem.AttributeName) == true then
		watchedTools[tool] = true

		tool.Activated:Connect(function()
			local character = tool.Parent
			local player = character and character:IsA("Model") and Players:GetPlayerFromCharacter(character)
			if player then
				onBandagemActivated(player, tool :: Tool)
			end
		end)
		tool.Destroying:Connect(function()
			watchedTools[tool] = nil
		end)
	end
end

local function forEachTool(root: Instance, callback: (Instance) -> ())
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Tool") then
			callback(descendant)
		end
	end

	root.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Tool") then
			callback(descendant)
		end
	end)
end

--[[
	Init()
	Conecta Lanterna e Chocolate em qualquer Tool existente/futura no jogo.
	Chame uma vez no boot do servidor, depois de MonsterLightWeakness.Init().
]]
function UtilityItemSystem.Init()
	forEachTool(game, watchUtilityItem)

	-- Solta o lock de canalização se o jogador/personagem some no meio.
	Players.PlayerRemoving:Connect(function(player)
		healingNow[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			healingNow[player] = nil
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(function()
			healingNow[player] = nil
		end)
	end
end

return UtilityItemSystem
