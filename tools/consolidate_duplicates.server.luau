-- One-time Studio migration for places where the movement .rbxm was imported
-- manually and then synced with Rojo. The canonical implementations are the
-- instances already represented by default.project.json.

local actions = {}
local expectedIslandDescendantCount = nil
local expectedIslandParent = nil

local function note(message)
	table.insert(actions, message)
	print("[ConsolidateDuplicates] " .. message)
end

local function childrenNamed(parent, name)
	local result = {}
	for _, child in parent:GetChildren() do
		if child.Name == name then
			table.insert(result, child)
		end
	end
	return result
end

local function sourceLength(instance)
	if not instance:IsA("LuaSourceContainer") then
		return -1
	end
	return #instance.Source
end

local function assertChild(parent, name, className)
	local child = parent and parent:FindFirstChild(name)
	assert(child, string.format("esperado %s em %s", name, parent and parent:GetFullName() or "nil"))
	if className then
		assert(
			child.ClassName == className,
			string.format("esperado %s.%s como %s; encontrado %s", parent:GetFullName(), name, className, child.ClassName)
		)
	end
	return child
end

local function countAnimates()
	local count = 0
	local activeAnimate = nil
	for _, descendant in game:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") and string.lower(descendant.Name) == "animate" then
			count += 1
			if descendant:GetFullName() == "StarterPlayer.StarterCharacterScripts.Animate" then
				activeAnimate = descendant
			end
		end
	end
	return count, activeAnimate
end

local function richestChild(parent, name)
	local matches = childrenNamed(parent, name)
	table.sort(matches, function(a, b)
		return #a:GetDescendants() > #b:GetDescendants()
	end)
	return matches[1], matches
end

local function rememberIsland()
	local island = workspace:FindFirstChild("Ilha")
	if island then
		expectedIslandParent = island.Parent
		expectedIslandDescendantCount = #island:GetDescendants()
	end
end

local function assertIslandUntouched()
	local island = workspace:FindFirstChild("Ilha")
	if expectedIslandDescendantCount then
		assert(island, "Workspace.Ilha existia antes da limpeza e desapareceu")
		assert(island.Parent == expectedIslandParent, "Workspace.Ilha mudou de Parent durante a limpeza")
		assert(
			#island:GetDescendants() == expectedIslandDescendantCount,
			string.format(
				"Workspace.Ilha mudou durante a limpeza: antes %d descendentes, depois %d",
				expectedIslandDescendantCount,
				#island:GetDescendants()
			)
		)
	end
end

local function preflight()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local StarterPlayer = game:GetService("StarterPlayer")
	local SoundService = game:GetService("SoundService")

	rememberIsland()

	local modules = richestChild(ReplicatedStorage, "Modules")
	assert(modules, "ReplicatedStorage.Modules não encontrado")
	assertChild(modules, "GameConfig", "ModuleScript")
	local remotesModule = assertChild(modules, "Remotes", "ModuleScript")
	assertChild(modules, "FootstepModule", "ModuleScript")

	local remotes = richestChild(ReplicatedStorage, "Remotes")
	assert(remotes, "ReplicatedStorage.Remotes não encontrado")
	for _, remoteName in {
		"SprintIntent",
		"RoundStateChanged",
		"NoiseDetected",
		"Flashlight",
		"FirearmShoot",
	} do
		assert(
			remotesModule.Source:find(remoteName, 1, true),
			"Remote esperado ausente em ReplicatedStorage.Modules.Remotes: " .. remoteName
		)
	end

	assertChild(ReplicatedStorage, "FallSystem", "Folder")
	assertChild(SoundService, "FallSounds", "Folder")

	local serverContainer = assertChild(ServerScriptService, "Server")
	assert(
		serverContainer:IsA("LuaSourceContainer") or serverContainer:IsA("Folder"),
		"ServerScriptService.Server precisa ser Script ou Folder"
	)
	assertChild(serverContainer, "StaminaSystem", "ModuleScript")

	local starterPlayerScripts = assertChild(StarterPlayer, "StarterPlayerScripts")
	local clientContainer = assertChild(starterPlayerScripts, "Client")
	assert(
		clientContainer:IsA("LuaSourceContainer") or clientContainer:IsA("Folder"),
		"StarterPlayerScripts.Client precisa ser LocalScript, Script ou Folder"
	)
	assertChild(clientContainer, "StaminaHUD", "LocalScript")

	for _, requiredName in {
		"RbxCharacterSounds",
		"IK",
		"DamageScreen",
		"DeathScreenUI",
		"PlayerModule",
		"Footsteps",
	} do
		assert(starterPlayerScripts:FindFirstChild(requiredName), "StarterPlayerScripts." .. requiredName .. " não encontrado")
	end

	for _, requiredName in {
		"R6Ragdoll",
		"DisableDefaultShiftLock",
		"DeathRespawnHandler",
		"NoCollision",
	} do
		assert(ServerScriptService:FindFirstChild(requiredName), "ServerScriptService." .. requiredName .. " não encontrado")
	end

	local starterCharacterScripts = assertChild(StarterPlayer, "StarterCharacterScripts")
	local animate = assertChild(starterCharacterScripts, "Animate", "LocalScript")
	local crouching = assertChild(starterCharacterScripts, "Crouching", "LocalScript")
	assert(animate.Source:find("Previous", 1, true), "Animate consolidado não contém o perfil Previous")
	assert(animate.Source:find("ImportedArczis", 1, true), "Animate consolidado não contém o perfil ImportedArczis")
	assert(animate.Source:find("109143561038911", 1, true), "Animate consolidado não contém a animação idle atual")
	assert(animate.Source:find("77181920794051", 1, true), "Animate consolidado não contém a animação idle importada")
	assert(crouching.Source:find("Previous", 1, true), "Crouching consolidado não contém o perfil Previous")
	assert(crouching.Source:find("ImportedArczis", 1, true), "Crouching consolidado não contém o perfil ImportedArczis")
	assert(crouching.Source:find("125168404409395", 1, true), "Crouching consolidado não contém a animação CrouchWalk atual")
	assert(crouching.Source:find("75389389155590", 1, true), "Crouching consolidado não contém a animação CrouchWalk importada")

	local animateCount = countAnimates()
	assert(animateCount >= 1, "nenhum Animate encontrado antes da consolidação")
end

local function beginRecording()
	local ChangeHistoryService = game:GetService("ChangeHistoryService")
	local ok, recording = pcall(function()
		return ChangeHistoryService:TryBeginRecording(
			"ConsolidateDuplicateSystems",
			"Consolidar sistemas duplicados"
		)
	end)
	if ok and recording then
		return ChangeHistoryService, recording
	end

	warn("[ConsolidateDuplicates] ChangeHistoryService indisponível neste contexto; pré-validação continua ativa.")
	return nil, nil
end

local function finishRecording(service, recording, operation)
	if service and recording then
		pcall(function()
			service:FinishRecording(recording, operation)
		end)
	end
end

local function mergeFolders(parent, name)
	local folders = childrenNamed(parent, name)
	if #folders < 2 then
		return folders[1]
	end

	table.sort(folders, function(a, b)
		return #a:GetDescendants() > #b:GetDescendants()
	end)
	local canonical = folders[1]

	for index = 2, #folders do
		local duplicate = folders[index]
		for _, child in duplicate:GetChildren() do
			local existing = canonical:FindFirstChild(child.Name)
			if existing and existing.ClassName == child.ClassName then
				child:Destroy()
			else
				child.Parent = canonical
			end
		end
		duplicate:Destroy()
		note(string.format("mesclado %s.%s", parent:GetFullName(), name))
	end

	return canonical
end

local function keepOne(parent, name, expectedSourceLength, requireDisabled)
	local matches = childrenNamed(parent, name)
	if #matches < 2 then
		return matches[1]
	end

	local canonical
	for _, instance in matches do
		local sourceMatches = expectedSourceLength == nil or sourceLength(instance) == expectedSourceLength
		local disabledMatches = requireDisabled == nil
			or (instance:IsA("BaseScript") and instance.Disabled == requireDisabled)
		if sourceMatches and disabledMatches then
			canonical = instance
			break
		end
	end
	canonical = canonical or matches[1]

	for _, instance in matches do
		if instance ~= canonical then
			instance:Destroy()
			note(string.format("removida cópia de %s.%s", parent:GetFullName(), name))
		end
	end

	return canonical
end

local function removeAll(parent, name, reason)
	for _, instance in childrenNamed(parent, name) do
		instance:Destroy()
		note(string.format("removido %s.%s (%s)", parent:GetFullName(), name, reason))
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local SoundService = game:GetService("SoundService")

preflight()
local changeHistoryService, recording = beginRecording()

local ok, err = xpcall(function()
	-- Pastas do jogo e do pacote importado: preserva filhos únicos no contêiner
	-- mais completo e descarta apenas a segunda cópia de cada filho.
	mergeFolders(ReplicatedStorage, "Modules")
	mergeFolders(ReplicatedStorage, "Remotes")
	mergeFolders(ReplicatedStorage, "FallSystem")
	mergeFolders(SoundService, "FallSounds")

	-- Instâncias montadas pelo Rojo. Os comprimentos identificam as versões
	-- canônicas do repositório quando as cópias possuem código diferente.
	keepOne(ReplicatedStorage, "FallDamageEvent")
	keepOne(ReplicatedStorage, "ViewModel")

	keepOne(ServerScriptService, "R6Ragdoll", 2283)
	keepOne(ServerScriptService, "DisableDefaultShiftLock", 148)
	keepOne(ServerScriptService, "DeathRespawnHandler", 2170)
	keepOne(ServerScriptService, "NoCollision", 765)

	local starterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	if starterPlayerScripts then
		keepOne(starterPlayerScripts, "RbxCharacterSounds", 12989)
		keepOne(starterPlayerScripts, "IK", 7457)
		keepOne(starterPlayerScripts, "DamageScreen", 4457, true)
		keepOne(starterPlayerScripts, "DeathScreenUI", 18020)
		keepOne(starterPlayerScripts, "PlayerModule", 793)
		keepOne(starterPlayerScripts, "Footsteps", 9341)

		-- O cliente antigo permitia alterar stamina localmente. O módulo
		-- Server.StaminaSystem e o Client.StaminaHUD são os únicos donos atuais.
		removeAll(starterPlayerScripts, "StaminaSystem", "substituído pelo sistema autoritativo do servidor")
	end

	removeAll(ReplicatedStorage, "UpdateRunningState", "remote legado sem consumidores")

	-- As animações exportadas deste pacote já foram incorporadas ao único
	-- StarterCharacterScripts.Animate e ao Crouching canônico. O .rbxm original
	-- continua em Arczis animations/ como backup editável dos AnimSaves.
	local importedPackage = workspace:FindFirstChild("Ultimate R6 Movement System by Arczi")
	if importedPackage then
		importedPackage:Destroy()
		note("removido o pacote importado do Workspace após incorporar suas animações")
	end

	-- Rigs auxiliares podem continuar no mapa para edição, mas não precisam de
	-- controladores Animate executáveis. Assim existe apenas um Animate no jogo.
	for _, rigName in { "click animation editor and click me", "Anim", "Rig" } do
		local rig = workspace:FindFirstChild(rigName)
		local animate = rig and rig:FindFirstChild("Animate")
		if animate and animate:IsA("LuaSourceContainer") then
			animate:Destroy()
			note(string.format("removido Animate auxiliar de Workspace.%s", rigName))
		end
	end

	-- Restos vazios e sem nome semântico deixados por imports manuais.
	for _, child in workspace:GetChildren() do
		if (child.Name == "Folder" or child.Name == "Model") and #child:GetDescendants() == 0 then
			child:Destroy()
			note("removido contêiner vazio Workspace." .. child.Name)
		end
	end

	local animateCount, activeAnimate = countAnimates()
	assert(activeAnimate, "StarterPlayer.StarterCharacterScripts.Animate não encontrado após a limpeza")
	assert(animateCount == 1, string.format("esperado 1 Animate; encontrados %d", animateCount))
	assertIslandUntouched()
end, debug.traceback)

if not ok then
	finishRecording(changeHistoryService, recording, Enum.FinishRecordingOperation.Cancel)
	error(err)
end

finishRecording(changeHistoryService, recording, Enum.FinishRecordingOperation.Commit)

local animateCount = countAnimates()
print(string.format("[ConsolidateDuplicates] concluído: %d ações; %d Animate", #actions, animateCount))

return true
