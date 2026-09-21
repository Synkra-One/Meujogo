--!strict
-- All dimensions are in studs. X is lateral, +Z runs toward the coast;
-- Y values are absolute world heights. Geometry and excavation share this plan.
local Plan = {}
Plan.Version = 4
-- Da origem da estação até a linha da costa. O corpo inteiro cabe entre a
-- caverna de entrada (Z negativo) e o pátio seco da saída (Z positivo).
Plan.CoastDistance = 222
Plan.Floor = -16
Plan.Height = 16
Plan.HallHeight = 18 -- salão de testes: o único ambiente com pé-direito maior
Plan.Wall = 2
Plan.Slab = 2
Plan.TerrainMargin = 8 -- two terrain voxels, including diagonal sites
-- Acima do teto basta um voxel: perto da praia o terreno é raso, e cavar dois
-- deixaria a escavação encostar na superfície.
Plan.CeilingMargin = 4
Plan.DoorHeight = 10
Plan.StairHeadroom = 12
Plan.StairHalf = 8 -- meia largura LIVRE de um lance (as paredes ficam fora dela)
-- Degraus mais altos e mais fundos: o mesmo desnível cabe em menos degraus,
-- e os dois lances ficam curtos perto do corpo do laboratório.
Plan.MaxRiser = 0.95
-- Com a entrada na cota típica (~22) a pisada passa de 1,5; o mínimo só é
-- alcançado num sítio bem alto, onde o lance fecha em 44 graus.
Plan.MinTread = 0.95
Plan.EntryDoorZ = -56
Plan.ExitDoorZ = 208
Plan.CaveZ0 = -100 -- piso rochoso da caverna de entrada
Plan.PatioZ1 = 222 -- pátio seco na costa
Plan.EntryStairZ = { -48, 12 }
Plan.ExitStairZ = { 164, 200 }
-- Faixas de terreno aceitáveis na escolha automática do local.
Plan.EntryGround = { Min = 14, Max = 32 }
Plan.ExitGround = { Min = 6, Max = 12.25 }
Plan.BodyGroundMin = 18 -- rocha suficiente sobre o teto das salas
Plan.CaveClearance = 340 -- distância mínima até a boca da caverna do Monstro
-- Pontos amostrados ao procurar local (Z local, do fundo da caverna ao pátio).
Plan.SiteSamples = { -96, -72, -48, -16, 20, 60, 100, 140, 180, 214 }
-- Onde o gerador mede o chão: boca da caverna e soleira da saída.
Plan.EntryProbeZ = -88
Plan.ExitProbeZ = 208

local function gap(center: number, width: number): { number }
	return { center - width / 2, center + width / 2 }
end

function Plan.Create(entryGround: number, exitGround: number): any
	local y = Plan.Floor
	local entry, exit = entryGround + 0.15, exitGround + 0.15
	local function room(name: string, kind: string, x0: number, x1: number, z0: number, z1: number, height: number?): any
		return { Name = name, Kind = kind, X0 = x0, X1 = x1, Z0 = z0, Z1 = z1,
			Floor = y, Height = height or Plan.Height, Openings = {}, Skip = {} }
	end

	-- Recepção no pé da escada de entrada. `Openings` descreve TODAS as
	-- passagens do ambiente, inclusive as das paredes que o vizinho constrói
	-- (`Skip`): o mobiliário usa essa lista para não ficar no caminho.
	local atrium = room("Recepcao", "Recepcao", -24, 24, 12, 44)
	atrium.Openings = { ZMin = { gap(0, 16) }, ZMax = { gap(0, 24) }, XMin = { gap(28, 10) } }

	-- Corredor central de 24 studs: duas pessoas passam de lado a lado sem
	-- esbarrar nas portas abertas.
	local spine = room("Corredor", "Corredor", -12, 12, 44, 164)
	spine.Openings = {
		XMin = { gap(72, 10), gap(116, 10), gap(150, 10) },
		XMax = { gap(86, 14), gap(146, 10) },
		ZMin = { gap(0, 24) },
		ZMax = { gap(0, 16) },
	}
	spine.Skip.ZMin = true -- the atrium owns the shared partition

	-- Salas laterais grandes: 48 studs de frente, fundo de 28 a 48.
	local lab = room("Laboratorio", "Laboratorio", -60, -12, 48, 96)
	lab.Openings = { XMax = { gap(72, 10) } }
	lab.Skip.XMax = true
	local archive = room("Arquivo", "Arquivo", -60, -12, 100, 132)
	archive.Openings = { XMax = { gap(116, 10) } }
	archive.Skip.XMax = true
	local clinic = room("Clinica", "Clinica", -60, -12, 136, 164)
	clinic.Openings = { XMax = { gap(150, 10) } }
	clinic.Skip.XMax = true
	local control = room("Controle", "Controle", 12, 60, 128, 164)
	control.Openings = { XMin = { gap(146, 10) } }
	control.Skip.XMin = true
	local utilities = room("Utilidades", "Utilidades", -66, -24, 12, 44)
	utilities.Openings = { XMax = { gap(28, 10) } }
	utilities.Skip.XMax = true

	-- Salão de testes: 76x76 com pé-direito de 18. É a maior ala do
	-- laboratório -- onde ficam as celas, as mesas e o Frog Generator.
	-- O corredor levanta a parede compartilhada até a própria altura; o salão
	-- fecha só a faixa acima dela.
	local hall = room("Bioteste", "Bioteste", 12, 88, 48, 124, Plan.HallHeight)
	hall.Openings = { XMin = { gap(86, 14) } }
	hall.Skip.XMin = Plan.Height

	local function stair(name: string, span: { number }, y0: number, y1: number): any
		local z0, z1 = span[1], span[2]
		local count = math.ceil(math.abs(y1 - y0) / Plan.MaxRiser)
		-- O vão de cada lance é fixo pelas salas vizinhas: um terreno alto
		-- demais falha aqui, antes de apagar a estação ou mexer no terreno.
		assert(count > 0 and count <= 240 and z0 + count * Plan.MinTread <= z1 + 0.001,
			string.format("Abismo: terreno alto demais para a escada segura (%s, %d degraus em %d studs)",
				name, count, z1 - z0))
		return { Name = name, X0 = -Plan.StairHalf, X1 = Plan.StairHalf, Z0 = z0, Z1 = z1,
			Y0 = y0, Y1 = y1, Count = count, Tread = (z1 - z0) / count, Riser = (y1 - y0) / count }
	end

	return {
		EntryFloor = entry, ExitFloor = exit,
		Rooms = { atrium, spine, lab, control, clinic, archive, utilities, hall },
		Stairs = {
			stair("EscadaPrincipal", Plan.EntryStairZ, entry, y),
			stair("EscadaSaida", Plan.ExitStairZ, y, exit),
		},
		Doors = {
			{ Name = "Entrada", X = 0, Z = Plan.EntryDoorZ, Floor = entry, Width = 12, Side = false, Main = true },
			{ Name = "Utilidades", X = -24, Z = 28, Floor = y, Width = 10, Side = true },
			{ Name = "Laboratorio", X = -12, Z = 72, Floor = y, Width = 10, Side = true },
			{ Name = "Bioteste", X = 12, Z = 86, Floor = y, Width = 14, Side = true },
			{ Name = "Arquivo", X = -12, Z = 116, Floor = y, Width = 10, Side = true },
			{ Name = "Controle", X = 12, Z = 146, Floor = y, Width = 10, Side = true },
			{ Name = "Clinica", X = -12, Z = 150, Floor = y, Width = 10, Side = true },
			{ Name = "Saida", X = 0, Z = Plan.ExitDoorZ, Floor = exit, Width = 12, Side = false, Exit = true },
		},
	}
end
return Plan
