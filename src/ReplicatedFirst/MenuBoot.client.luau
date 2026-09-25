--!strict
--[[
	MenuBoot -- LocalScript da tela inicial (ReplicatedFirst)

	Fica em ReplicatedFirst de propósito: é o único lugar que roda ANTES de o
	jogo terminar de carregar, então dá para substituir a tela de carregamento
	padrão da Roblox pela nossa sem o jogador ver a tela azul primeiro.

	FLUXO
	  1. Carregamento próprio (rápido -- MenuConfig.Loading)
	  2. Cena 3D assume a câmera + "clique para começar"
	  3. Menu principal entra com os botões
	4. ENTRAR devolve câmera/controles e deixa o personagem visível no lobby

	ONDE ESTÁ CADA COISA
	  Menu/MenuConfig  -- TODA a configuração (cores, tempos, IDs, textos)
	  Menu/MenuTheme   -- aparência e tweens
	  Menu/MenuSounds  -- áudio
	  Menu/MenuScene   -- a cena 3D (troque modelo/cenário/câmera lá)
	  Menu/MenuScreens -- as telas e a navegação

	NADA AQUI AFETA OS OUTROS JOGADORES: a cena é local, a interface é local, e
	ENTRAR apenas libera o lobby. A fila e a seleção continuam nos sistemas
	existentes, sem pedidos ao servidor feitos por esta tela.

	IMPORTANTE SOBRE ORDEM DE CARGA: em ReplicatedFirst o ReplicatedStorage
	ainda não replicou. Por isso nenhum módulo do jogo é exigido no topo deste
	arquivo -- só quando o jogador realmente clica.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Menu = script.Parent:WaitForChild("Menu")
local Config = require(Menu.MenuConfig)
local Sounds = require(Menu.MenuSounds)
local Scene = require(Menu.MenuScene)
local Screens = require(Menu.MenuScreens)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- Controles e CoreGui
--------------------------------------------------------------------------------

-- Mesma abordagem do RoleRevealController: o ControlModule oficial, que não
-- briga com o WalkSpeed controlado pelo Crouching/StaminaSystem.
local function setControlsEnabled(enabled: boolean)
	if not Config.Flow.LockControls then return end
	local ok, controls = pcall(function()
		local scripts = player:WaitForChild("PlayerScripts", 5)
		local playerModule = scripts and scripts:WaitForChild("PlayerModule", 5)
		return playerModule and require(playerModule :: ModuleScript):GetControls()
	end)
	if ok and controls then
		if enabled then (controls :: any):Enable() else (controls :: any):Disable() end
	end
end

local coreGuiTypes = { Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.EmotesMenu }
local function setCoreGuiEnabled(enabled: boolean)
	if not Config.Flow.HideCoreGui then return end
	for _, coreType in coreGuiTypes do
		pcall(function() StarterGui:SetCoreGuiEnabled(coreType, enabled) end)
	end
end

--[[
	setCursorFree(free)
	MESMO padrão do MonsterTeleportController (mapa do Monstro) e do
	CharacterSelectController: CustomShiftLock reprende o mouse no centro e
	gira a câmera TODO FRAME, mas respeita o Attribute "CursorLivre" no
	LocalPlayer -- é o gancho oficial do projeto pra "soltar" o shift-lock sem
	precisar mexer no script dele. Sem isto, o cursor fica preso no meio da
	tela e a câmera da cena treme (as duas câmeras brigando pelo CFrame).
	O RenderStepped é só rede de segurança contra um re-lock do PlayerModule.
]]
local cursorConnection: RBXScriptConnection? = nil
local function setCursorFree(free: boolean)
	if free then
		player:SetAttribute("CursorLivre", true)
		if cursorConnection then return end
		cursorConnection = RunService.RenderStepped:Connect(function()
			if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			UserInputService.MouseIconEnabled = true
		end)
	else
		player:SetAttribute("CursorLivre", nil)
		if cursorConnection then
			cursorConnection:Disconnect()
			cursorConnection = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Estado do menu
--------------------------------------------------------------------------------

local sounds = Sounds.new()
local scene = Scene.new()
local screens: Screens.Controller
local closed = false

local function leaveMenu(afterwards: (() -> ())?)
	if closed then return end
	closed = true
	Sounds.FadeMusic(sounds, 1.2)
	Screens.Close(screens, function()
		-- A ORDEM importa: solta a câmera antes de devolver o controle, senão
		-- o jogador anda um frame com a câmera ainda presa na cena.
		Scene.Hide(scene)
		local camera = Workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if camera then
			camera.CameraType = Enum.CameraType.Custom
			if humanoid then camera.CameraSubject = humanoid end
		end
		setControlsEnabled(true)
		setCoreGuiEnabled(true)
		setCursorFree(false)
		player:SetAttribute("IntroMenuOpen", nil)
		task.delay(1.2, function()
			-- A cena só é destruída depois da transição: se ela sumisse junto
			-- com a câmera, dava para ver o cenário piscando.
			Scene.Destroy(scene)
		end)
		if afterwards then afterwards() end
	end)
end

--------------------------------------------------------------------------------
-- Ações dos botões
--------------------------------------------------------------------------------

local function onPlay()
	-- Só fecha o menu. O jogador já nasceu dentro do lobby do aeroporto e
	-- continua vendo o personagem enquanto decide iniciar a partida.
	leaveMenu()
end

--------------------------------------------------------------------------------
-- Fluxo
--------------------------------------------------------------------------------

screens = Screens.new(playerGui, sounds, {
	OnPlay = onPlay,
})

-- Tira a tela de carregamento padrão da Roblox: a nossa entra no lugar.
pcall(function() ReplicatedFirst:RemoveDefaultLoadingScreen() end)

-- Sinal pros outros LocalScripts do jogo (StaminaHUD, HotbarController):
-- enquanto a tela inicial estiver aberta, o HUD de partida (minimapa, fôlego,
-- itens) não pode aparecer por baixo dela.
setControlsEnabled(false)
setCoreGuiEnabled(false)
setCursorFree(true)
player:SetAttribute("IntroMenuOpen", true)

local function runLoading()
	Screens.ShowLoading(screens)
	local started = os.clock()
	local minimum, maximum = Config.Loading.MinSeconds, Config.Loading.MaxSeconds
	while true do
		local elapsed = os.clock() - started
		Screens.SetLoadingProgress(screens, elapsed / maximum)
		-- Sai assim que o jogo estiver carregado E o mínimo tiver passado;
		-- o máximo é uma rédea curta para não segurar ninguém.
		if elapsed >= maximum then break end
		if elapsed >= minimum and game:IsLoaded() then break end
		task.wait(0.05)
	end
	Screens.SetLoadingProgress(screens, 1)
	task.wait(0.15)
end

task.spawn(function()
	runLoading()
	if closed then return end

	-- A cena assume a câmera ANTES de a tela de carregamento sair: assim o
	-- jogador nunca vê o lobby por trás.
	local camera = Workspace.CurrentCamera
	if camera then Scene.Show(scene, camera) end

	Screens.HideLoading(screens, function()
		Sounds.StartMusic(sounds)
		Screens.ShowStart(screens, function()
			-- Clicou: a cena sai do desfoque e o menu entra.
			Scene.Focus(scene, 0, 1.1)
			Screens.ShowMenu(screens)
		end)
	end)
end)

--------------------------------------------------------------------------------
-- Rede de segurança
--------------------------------------------------------------------------------

-- Respawn NÃO reabre o menu (MenuConfig.Flow.ReopenOnRespawn). O ScreenGui já
-- tem ResetOnSpawn = false; isto cobre o caso de a rodada começar enquanto o
-- menu ainda está aberto -- aí ele sai do caminho sozinho.
player.CharacterAdded:Connect(function()
	if closed then
		return
	end
	-- O PlayerModule RELIGA os controles a cada spawn, e o nascimento no lobby
	-- acontece com o menu ainda aberto. Sem isto o jogador sai andando por trás
	-- da tela inicial. (A câmera é reassumida pelo próprio MenuScene.)
	task.defer(setControlsEnabled, false)
	if Config.Flow.ReopenOnRespawn then return end
	if player:GetAttribute("InRound") == true then leaveMenu() end
end)

player:GetAttributeChangedSignal("InRound"):Connect(function()
	if player:GetAttribute("InRound") == true then leaveMenu() end
end)

-- Sair do jogo com o menu aberto não pode deixar controle/CoreGui travados.
script.Destroying:Connect(function()
	setControlsEnabled(true)
	setCoreGuiEnabled(true)
	setCursorFree(false)
	player:SetAttribute("IntroMenuOpen", nil)
	Scene.Destroy(scene)
	Sounds.Destroy(sounds)
	Screens.Destroy(screens)
end)
