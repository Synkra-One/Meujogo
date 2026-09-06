--!strict
--[[
	SafeWait
	WaitForChild com timeout + erro alto, em vez de travar pra sempre em
	silêncio se o projeto não tiver sido sincronizado (rojo build/serve) e a
	instância esperada não existir. Usado pelos scripts de HUD, que
	dependem de ScreenGuis vindas de StarterGui/*.model.json.

	Sem isso, um "rojo build" desatualizado faz o script inteiro travar na
	primeira linha, sem nenhum erro no Output -- e do ponto de vista de quem
	tá jogando, "a HUD simplesmente não aparece".
]]

local TIMEOUT = 10

local SafeWait = {}

function SafeWait.Child(parent: Instance, name: string): Instance
	local child = parent:WaitForChild(name, TIMEOUT)
	if not child then
		error(
			string.format(
				"[SafeWait] '%s' não encontrado em %s após %ds. "
					.. "Rode 'rojo build -o Meujogo.rbxlx' de novo (ou confira se 'rojo serve' está conectado no Studio).",
				name,
				parent:GetFullName(),
				TIMEOUT
			),
			0
		)
	end
	return child
end

return SafeWait
