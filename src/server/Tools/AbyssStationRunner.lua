--!strict
--[[
	AbyssStationRunner (ferramenta de editor)
	Um comando só, em UMA linha, para a Command Bar do Studio (modo de edição):

		require(game.ServerScriptService.Server.Tools.AbyssStationRunner).Run()

	Faz sozinho o que o guia pedia em vários passos: carrega uma cópia nova de
	Tools (o `require` do Studio guarda o gerador antigo em cache), usa a seed
	da ilha e chama Build(). O relatório vai para o Output E para
	ServerStorage.DiagAbismo (StringValue): se o painel Output estiver
	filtrando mensagens, leia a propriedade Value dele no Explorer.
]]
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Runner = {}

local function publish(lines: { string }): string
	local text = table.concat(lines, "\n")
	local old = ServerStorage:FindFirstChild("DiagAbismo")
	if old then old:Destroy() end
	local value = Instance.new("StringValue")
	value.Name = "DiagAbismo"
	value.Value = text
	value.Parent = ServerStorage
	print(text)
	warn("[Abismo] Relatório completo em ServerStorage.DiagAbismo (propriedade Value).")
	return text
end

function Runner.Run(seed: number?): string
	local lines: { string } = {}
	local function say(text: string) table.insert(lines, text) end
	local started = os.clock()
	local tools = script.Parent :: any
	say("[Abismo] Runner iniciado.")
	if RunService:IsRunning() then
		say("ERRO: o Studio está em Play/Run. Pare a simulação e rode em modo de edição.")
		return publish(lines)
	end

	local fresh: any = nil
	local cloned = pcall(function()
		local copy = tools:Clone()
		copy.Name = "AbismoEditorAtualizado"
		copy.Parent = tools.Parent
		fresh = copy
	end)
	say(if fresh then "Cópia nova de Tools carregada (sem cache do gerador antigo)."
		else "Sem cópia de Tools; usando os módulos já carregados (cloned=" .. tostring(cloned) .. ").")
	local source = fresh or tools

	local ok, result = xpcall(function()
		local layout = require(tools.IslandLayout)
		local plan = require(source.AbyssStationPlan)
		local furnishings = require(source.AbyssLabFurnishings)
		say("Plan.Version: " .. tostring(plan.Version))
		say("Frog Generator disponível: " .. tostring(furnishings.TestHall ~= nil))
		local usedSeed = seed or layout.Seed()
		say("Seed: " .. tostring(usedSeed))
		return require(source.AbyssStationGenerator).Build(usedSeed)
	end, function(problem: any)
		return tostring(problem) .. "\n" .. debug.traceback()
	end)
	if fresh then fresh:Destroy() end

	if not ok then
		say("FALHOU:")
		say(tostring(result))
		return publish(lines)
	end

	local station: any = result
	local frame = station:GetAttribute("AbismoFrame")
	local parts, frog = 0, false
	for _, item in station:GetDescendants() do
		if item:IsA("BasePart") then parts += 1 end
		if item:GetAttribute("FrogGenerator") == true then frog = true end
	end
	say("OK: estação construída em " .. string.format("%.1fs", os.clock() - started) .. ".")
	say("AbismoVersion: " .. tostring(station:GetAttribute("AbismoVersion")))
	say("Posição do frame: " .. (if frame then tostring(frame.Position) else "?"))
	say("Peças: " .. tostring(parts))
	say("FrogGenerator no modelo: " .. tostring(frog))
	say("Salve o lugar (Ctrl+S) para manter a estação.")
	return publish(lines)
end

return Runner
