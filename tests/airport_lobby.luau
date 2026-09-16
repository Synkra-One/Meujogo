--!nocheck
-- `sources` é injetado por run_airport_lobby.py com os módulos REAIS.
-- Prova que o gerador executa e que a geometria cai onde o projeto precisa.
-- Física, renderização e replicação continuam sendo coisa de Studio.

local stub = loadstring(sources.RobloxStub, "RobloxStub")()
local Workspace = stub.Workspace

local modules = {}
local tokens = setmetatable({}, {
	__index = function(t, key)
		local v = { __module = key }
		rawset(t, key, v)
		return v
	end,
})

local env
local function loadModule(name)
	if modules[name] then
		return modules[name]
	end
	local fn = assert(loadstring(assert(sources[name], name), name))
	setfenv(fn, env)
	modules[name] = fn()
	return modules[name]
end

env = setmetatable({
	script = { Parent = tokens },
	require = function(t)
		return loadModule(t.__module)
	end,
}, { __index = getfenv() })

--------------------------------------------------------------------------------
-- As peças que LobbyManager cria no boot já existem quando o gerador roda.
--------------------------------------------------------------------------------

-- Precisa bater com LobbyManager.LOBBY_ORIGIN e AirportLobbyGenerator.ORIGIN
-- (o terminal fica ELEVADO acima do nível externo -- ver o cabeçalho do
-- gerador -- então isto não é mais Y=10).
local ORIGIN = Vector3.new(0, 40, -1500)
local GROUND_LEVEL_Y = 9 -- precisa bater com AirportLobbyGenerator.GROUND_LEVEL_Y

local lobbyFloor = Instance.new("Part", Workspace)
lobbyFloor.Name = "LobbyFloor"
lobbyFloor.Size = Vector3.new(60, 2, 60)
lobbyFloor.CFrame = CFrame.new(0, 39, -1500)

local lobbySpawn = Instance.new("SpawnLocation", Workspace)
lobbySpawn.Name = "LobbySpawn"
lobbySpawn.Size = Vector3.new(8, 1, 8)
lobbySpawn.CFrame = CFrame.new(0, 40.5, -1500)

local startPart = Instance.new("Part", Workspace)
startPart.Name = "IniciarPartida"
startPart.Size = Vector3.new(4, 1, 4)
startPart.CFrame = CFrame.new(0, 40.5, -1480)

--------------------------------------------------------------------------------

local Airport = loadModule("AirportLobbyGenerator")
local lobby = Airport.Build({ Assets = false, Terrain = true })

local function fail(message: string, ...): never
	error(string.format(message, ...), 0)
end

local function check(condition, message, ...)
	if not condition then
		fail(message, ...)
	end
end

--------------------------------------------------------------------------------
-- Inventário
--------------------------------------------------------------------------------

local parts, byName = {}, {}
for _, d in lobby:GetDescendants() do
	if d:IsA("BasePart") then
		table.insert(parts, d)
		byName[d.Name] = (byName[d.Name] or 0) + 1
	end
end
check(#parts > 350, "terminal raso demais: só %d peças", #parts)
check(#parts < 1400, "peças demais pro Roblox: %d", #parts)

for _, p in parts do
	check(p.Anchored, "peça solta (Anchored=false): %s", p.Name)
end

local function aabb(p)
	local e = stub.PartExtents(p) * 0.5
	local c = p.CFrame.Position
	return c - e, c + e
end

local function overlaps(loA, hiA, loB, hiB)
	return loA.X < hiB.X and hiA.X > loB.X
		and loA.Y < hiB.Y and hiA.Y > loB.Y
		and loA.Z < hiB.Z and hiA.Z > loB.Z
end

--------------------------------------------------------------------------------
-- 1. Não encostar em nada que já existe
--------------------------------------------------------------------------------

-- Sala de espera: WaitingRoomManager.origin (120, 10, -1500), 52 x 44.
local roomLo = Vector3.new(120 - 27, -40, -1500 - 23)
local roomHi = Vector3.new(120 + 27, 60, -1500 + 23)
for _, p in parts do
	local lo, hi = aabb(p)
	check(not overlaps(lo, hi, roomLo, roomHi), "%s invade a sala de espera", p.Name)
end

-- Terreno da ilha: IslandLayout.AreaHalf = 960.
for _, p in parts do
	local lo, hi = aabb(p)
	check(hi.Z < -960, "%s (z ate %.0f) entra na area da ilha", p.Name, hi.Z)
end

-- E a grama externa também fica fora da ilha.
check(#stub.TerrainFills > 0, "nenhum Terrain:FillBlock foi emitido")

-- A varredura de Air precisa cobrir a faixa onde a versão ANTIGA (com o bug)
-- gravava grama -- senão quem já rodou o gerador uma vez fica com resíduo
-- pra sempre, mesmo regerando com a versão corrigida.
do
	local airLo, airHi
	for _, fill in stub.TerrainFills do
		if fill.Material.Name == "Air" then
			local lo = fill.CFrame.Position - fill.Size * 0.5
			local hi = fill.CFrame.Position + fill.Size * 0.5
			airLo = if airLo then Vector3.new(math.min(airLo.X, lo.X), math.min(airLo.Y, lo.Y), math.min(airLo.Z, lo.Z)) else lo
			airHi = if airHi then Vector3.new(math.max(airHi.X, hi.X), math.max(airHi.Y, hi.Y), math.max(airHi.Z, hi.Z)) else hi
		end
	end
	check(airLo ~= nil, "nenhuma varredura de Air foi emitida -- grama de versoes antigas fica pra sempre")
	-- Z=-1400 era o ZNear da versão com bug; a varredura precisa alcançar
	-- (e passar de) esse ponto pra limpar o resíduo.
	check(airHi.Z >= -1400, "a varredura de Air nao alcanca a faixa onde a versao antiga gravava grama (z=-1400)")
	check(airLo.Z <= -2800, "a varredura de Air nao alcanca o fim da grama atual (z=-2800)")
	-- SmoothTerrain arredonda a superfície nas bordas de um FillBlock -- uma
	-- margem vertical apertada deixa essa sobra furando o piso por dentro do
	-- salão. A varredura precisa de folga generosa acima e abaixo do piso
	-- (ORIGIN.Y = 10) pra não repetir esse bug.
	check(airHi.Y >= ORIGIN.Y + 60, "a varredura de Air nao sobe o bastante acima do piso (topo em %.0f)", airHi.Y)
	check(airLo.Y <= ORIGIN.Y - 60, "a varredura de Air nao desce o bastante abaixo do piso (fundo em %.0f)", airLo.Y)
end
-- Z decresce indo pra dentro do campo de grama, então a borda MAIS PERTO do
-- prédio é a de maior Z (cfrCenter + metade da profundidade), não a menor.
local grassNearEdge = -math.huge
for _, fill in stub.TerrainFills do
	check(fill.Material.Name == "Grass" or fill.Material.Name == "Air", "material de terreno inesperado: %s", fill.Material.Name)
	if fill.Material.Name == "Grass" then
		local towardBuilding = fill.CFrame.Z + fill.Size.Z / 2
		local awayFromBuilding = fill.CFrame.Z - fill.Size.Z / 2
		check(towardBuilding < -960, "grama externa (z ate %.0f) entra na area da ilha", towardBuilding)
		grassNearEdge = math.max(grassNearEdge, towardBuilding)
	end
end
-- Bug corrigido: a grama chegava a nascer NA FRENTE da fachada de entrada
-- (z relativo +100) e passava por baixo do prédio inteiro. Ela só pode
-- começar depois do fim do pátio pavimentado, atrás do vidro.
-- L.ZGlass = -104 (nao exportado pelo modulo); mesma constante usada nas
-- checagens de vidro acima.
check(grassNearEdge <= ORIGIN.Z - 104 - 40, "grama externa (borda proxima z=%.0f) comeca perto demais do predio -- vaza pra frente/embaixo dele", grassNearEdge)

-- E nenhuma peça sólida da arquitetura pode estar dentro do volume da grama
-- (só a grama -- a varredura de Air é PRA cobrir o prédio, de propósito):
-- prova de que a grama em si não passa mais por baixo do terminal.
for _, fill in stub.TerrainFills do
	if fill.Material.Name == "Grass" then
		local gLo = fill.CFrame.Position - fill.Size * 0.5
		local gHi = fill.CFrame.Position + fill.Size * 0.5
		for _, p in parts do
			if p.CanCollide then
				local lo, hi = aabb(p)
				check(not overlaps(lo, hi, gLo, gHi), "%s cai dentro do volume da grama externa", p.Name)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- 2. As peças de LobbyManager continuam onde estavam, só ajustadas
--------------------------------------------------------------------------------

check(lobbySpawn.Parent == Workspace, "LobbySpawn saiu da raiz do Workspace (LobbyManager criaria outro)")
check(lobbyFloor.Parent == Workspace, "LobbyFloor saiu da raiz do Workspace")
check(startPart.Parent == Workspace, "IniciarPartida saiu da raiz do Workspace")
check(lobbySpawn.Transparency == 1, "LobbySpawn deveria ficar invisivel")
check(lobbySpawn.CanCollide == false, "LobbySpawn nao pode ser um bloco invisivel no caminho")
check(lobbySpawn.Duration == 0, "LobbySpawn deveria nascer sem forcefield")
check(lobbyFloor.Transparency == 1, "LobbyFloor visivel briga por profundidade com o piso novo")
-- Nasce olhando pro vidro (-Z).
local look = lobbySpawn.CFrame.LookVector
check(look.Z < -0.99, "o spawn deveria olhar pro vidro, LookVector.Z = %.2f", look.Z)

--------------------------------------------------------------------------------
-- 3. Ninguém nasce dentro de uma peça
--------------------------------------------------------------------------------

local spawnLo = Vector3.new(-2, ORIGIN.Y + 0.2, -1502)
local spawnHi = Vector3.new(2, ORIGIN.Y + 5, -1498)
for _, p in parts do
	if p.CanCollide then
		local lo, hi = aabb(p)
		check(not overlaps(lo, hi, spawnLo, spawnHi), "%s ocupa o volume do spawn", p.Name)
	end
end

--------------------------------------------------------------------------------
-- 4. O terminal é caminhável: BFS no nível do chão
--------------------------------------------------------------------------------

local STEP = 2
local X0, X1 = -60, 60
local Z0, Z1 = 72, -124 -- relativos a ORIGIN (+Z entrada, -Z pista)
local BAND_LO, BAND_HI = ORIGIN.Y + 0.6, ORIGIN.Y + 4.8 -- corpo de um R6

local cols = math.floor((X1 - X0) / STEP) + 1
local rows = math.floor((Z0 - Z1) / STEP) + 1
local blocked = {}
local function idx(cx, cz)
	return cz * cols + cx
end

-- Rasteriza só o que colide E atravessa a faixa de altura do personagem.
for _, p in parts do
	if p.CanCollide then
		local lo, hi = aabb(p)
		if lo.Y < BAND_HI and hi.Y > BAND_LO then
			local lx = math.max(0, math.floor((lo.X - X0) / STEP))
			local hx = math.min(cols - 1, math.floor((hi.X - X0) / STEP))
			local lz = math.max(0, math.floor((ORIGIN.Z + Z0 - hi.Z) / STEP))
			local hz = math.min(rows - 1, math.floor((ORIGIN.Z + Z0 - lo.Z) / STEP))
			for cx = lx, hx do
				for cz = lz, hz do
					blocked[idx(cx, cz)] = true
				end
			end
		end
	end
end

local function cellOf(x, z)
	return math.floor((x - X0) / STEP), math.floor((Z0 - z) / STEP)
end

local startX, startZ = cellOf(0, 0)
check(not blocked[idx(startX, startZ)], "a célula do spawn está bloqueada")

local seen = { [idx(startX, startZ)] = true }
local queue = { { startX, startZ } }
local head = 1
while head <= #queue do
	local cur = queue[head]
	head += 1
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local nx, nz = cur[1] + d[1], cur[2] + d[2]
		if nx >= 0 and nx < cols and nz >= 0 and nz < rows then
			local key = idx(nx, nz)
			if not seen[key] and not blocked[key] then
				seen[key] = true
				table.insert(queue, { nx, nz })
			end
		end
	end
end

local function reachable(x, z)
	local cx, cz = cellOf(x, z)
	return seen[idx(cx, cz)] == true
end

-- Tudo que o jogador precisa alcançar a pé, a partir do spawn.
local mustReach = {
	{ "vestíbulo / entrada", 0, 38 },
	{ "corredor do check-in", 0, 14 },
	{ "raia 1 da segurança", -11.5, -20 },
	{ "raia 2 da segurança", 11.5, -20 },
	{ "saída da raia 1", -11.5, -34 },
	{ "saída da raia 2", 11.5, -34 },
	{ "salão principal", 0, -40 },
	{ "corredor central das poltronas", 0, -66 },
	{ "lateral oeste (vending)", -50, -60 },
	{ "lateral leste (informações)", 50, -56 },
	{ "fila do portão A1", -28, -82 },
	{ "passeio junto ao vidro", 0, -100 },
	{ "bancada da janela", 26, -92 },
	{ "meio-fio (portas abertas)", 0, 56 },
}
for _, spot in mustReach do
	check(reachable(spot[2], spot[3]), "não dá pra andar do spawn até: %s (%d, %d)", spot[1], spot[2], spot[3])
end

-- "os bancos não devem bloquear a janela / o jogador tem que chegar perto do
-- vidro": encostar no vidro tem que ser possível ao longo dele todo.
for _, x in { -44, -20, 0, 20, 44 } do
	check(reachable(x, -100), "não dá pra encostar no vidro em x = %d", x)
end

--[[
	Nada opaco pode flutuar na altura do olho DENTRO do passeio -- o corredor
	entre a última fileira de poltronas (z = -80) e o vidro (z = -104). Móvel
	baixo (balcão do portão, bancada da janela) passa: olha-se por cima.
	Sinalização passa se estiver acima de y = +15. O que não pode é algo na
	faixa y +6..+15, porque é exatamente por ali que a futura pista, os aviões
	e os veículos vão aparecer pra quem está sentado.

	A janela do teste exclui de propósito o próprio plano do vidro (z = -104,
	onde moram montantes, peitoril e a porta da ponte de embarque) e o que
	está colado nas paredes laterais.
]]
for _, p in parts do
	if p.Transparency < 0.5 then
		local lo, hi = aabb(p)
		local midX = (lo.X + hi.X) / 2
		local inCorridor = lo.Z < ORIGIN.Z - 85 and hi.Z > ORIGIN.Z - 102
		if inCorridor and math.abs(midX) < 50 then
			check(
				lo.Y < ORIGIN.Y + 6 or lo.Y >= ORIGIN.Y + 15,
				"%s flutua na altura do olho entre as poltronas e o vidro (y %.1f..%.1f)",
				p.Name, lo.Y - ORIGIN.Y, hi.Y - ORIGIN.Y
			)
		end
	end
end

-- E o vidro precisa VEDAR: nada de atravessar pra área da pista.
local mustNotReach = {
	{ "atrás do vidro (pista futura)", 0, -114 },
	{ "atrás do vidro, lado oeste", -40, -114 },
	{ "atrás do vidro, lado leste", 40, -114 },
}
for _, spot in mustNotReach do
	check(not reachable(spot[2], spot[3]), "dá pra atravessar a parede de vidro em: %s", spot[1])
end

--------------------------------------------------------------------------------
-- 5. A parede panorâmica está inteira
--------------------------------------------------------------------------------

check(byName["GlassSlope_1"] and byName["GlassSlope_8"], "faltam painéis inclinados do vidro")
check(byName["JetBridgeDoor"] == 1, "falta a porta do portão na parede de vidro")
local panes = 0
for name, count in byName do
	if string.sub(name, 1, 11) == "GlassPane_" .. "" or string.match(name, "^GlassPane_") then
		panes += count
	end
end
check(panes == 8, "esperava 8 vãos envidraçados (7 painéis + o vão da porta), achei %d", panes)

local mullions = 0
for name, count in byName do
	if string.match(name, "^Mullion_%d+$") then
		mullions += count
	end
end
check(mullions == 9, "esperava 9 montantes verticais, achei %d", mullions)

-- Os painéis cobrem a largura interna toda (x -56..56).
local glassMinX, glassMaxX = math.huge, -math.huge
for _, p in parts do
	if string.match(p.Name, "^GlassPane") or p.Name == "JetBridgeDoor" then
		local lo, hi = aabb(p)
		glassMinX = math.min(glassMinX, lo.X)
		glassMaxX = math.max(glassMaxX, hi.X)
	end
end
check(glassMinX < -50 and glassMaxX > 50, "a janela não ocupa a parede toda (x %.0f..%.0f)", glassMinX, glassMaxX)

--------------------------------------------------------------------------------
-- 6. Programa do terminal e âncoras pro futuro
--------------------------------------------------------------------------------

local airport = lobby:FindFirstChild("Airport")
check(airport, "falta Workspace.Lobby.Airport")
for _, name in { "Architecture", "AssetPlaceholders", "CheckIn", "Security", "WaitingArea", "BoardingGate", "Lighting", "Props", "ExteriorFutureArea", "Foundation" } do
	check(airport:FindFirstChild(name), "falta a pasta %s", name)
end

local function findByAttribute(root, attribute)
	for _, d in root:GetDescendants() do
		if d:GetAttribute(attribute) then
			return d
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- 6b. Elevação: o terminal não pode estar na mesma altura da pista, e a
-- fundação precisa realmente "pousar" perto do chão, não flutuar.
--------------------------------------------------------------------------------

do
	local foundation = airport:FindFirstChild("Foundation")
	check(foundation, "falta a pasta Foundation")

	local fLo, fHi
	for _, d in foundation:GetDescendants() do
		if d:IsA("BasePart") then
			local lo, hi = aabb(d)
			fLo = if fLo then Vector3.new(math.min(fLo.X, lo.X), math.min(fLo.Y, lo.Y), math.min(fLo.Z, lo.Z)) else lo
			fHi = if fHi then Vector3.new(math.max(fHi.X, hi.X), math.max(fHi.Y, hi.Y), math.max(fHi.Z, hi.Z)) else hi
		end
	end
	check(fLo ~= nil, "a fundação não tem nenhuma peça")

	-- "não pode ficar na mesma altura que a parte onde fica os aviões":
	-- o piso do terminal precisa estar bem acima do nível do chão externo.
	check(ORIGIN.Y - GROUND_LEVEL_Y >= 25, "terminal alto demais perto do chão externo: só %.0f studs de diferença", ORIGIN.Y - GROUND_LEVEL_Y)

	-- "colocar algo baixo... pra não ficar flutuando": a fundação precisa
	-- descer até perto do nível do chão (não pode sobrar um vão embaixo dela).
	check(fLo.Y <= GROUND_LEVEL_Y + 1, "a fundação não desce até perto do chão -- ainda flutua (fundo em y=%.1f, chão em y=%.1f)", fLo.Y, GROUND_LEVEL_Y)

	-- E precisa encostar no prédio em cima -- sem vão entre "fundação" e "piso".
	-- L.FloorDepth = 3 (não exportado pelo módulo); mesma constante usada acima.
	check(fHi.Y >= ORIGIN.Y - 3 - 6, "sobra um vão entre a fundação e o piso do terminal (topo da fundação em y=%.1f)", fHi.Y)
end

local gate = findByAttribute(lobby, "PontoEmbarque")
check(gate, "falta o marcador PontoEmbarque (âncora do matchmaking)")
check(gate:GetAttribute("PortaoId") == "A1", "PontoEmbarque sem PortaoId")

local panel = findByAttribute(lobby, "PainelVoo")
check(panel, "falta o painel do voo")
local gui = panel:FindFirstChildOfClass("SurfaceGui")
check(gui, "o painel do voo não tem SurfaceGui")
local listing = gui:FindFirstChild("Linhas")
check(listing, "o painel do voo não tem as linhas")
for _, field in { "Voo", "Destino", "Status", "Passageiros" } do
	check(listing:FindFirstChild(field), "o painel do voo não tem o label %s", field)
end

check(findByAttribute(lobby, "AreaFuturaPista"), "falta o envelope reservado pra pista")

--------------------------------------------------------------------------------
-- 7. Sem assets do Toolbox, cada posição vira Part + placeholder
--------------------------------------------------------------------------------

local placeholders = airport:FindFirstChild("AssetPlaceholders")
local ids = {}
for _, m in placeholders:GetChildren() do
	local id = m:GetAttribute("AssetId")
	check(id, "placeholder %s sem AssetId", m.Name)
	check(m:GetAttribute("CFrameAlvo"), "placeholder %s sem CFrameAlvo", m.Name)
	check(m.Transparency == 1 and m.CanCollide == false, "placeholder %s deveria ser invisível e sem colisão", m.Name)
	ids[id] = (ids[id] or 0) + 1
end
for _, id in { 10183298246, 10759833003, 10131830908, 13776711189, 91305696624692, 5645721073, 8301328809, 8084763732 } do
	check(ids[id], "nenhum placeholder pro asset %d", id)
end
check(ids[10183298246] == 6, "esperava 6 fileiras de poltronas, achei %d", ids[10183298246] or 0)
check(ids[10759833003] == 2, "esperava 2 pórticos de segurança, achei %d", ids[10759833003] or 0)
check(ids[10131830908] == 2, "esperava 2 scanners de bagagem, achei %d", ids[10131830908] or 0)
check(ids[5645721073] == 2, "esperava 2 vending machines, achei %d", ids[5645721073] or 0)
check(ids[8301328809] == 10, "esperava 10 computadores (8 check-in + 2 portão), achei %d", ids[8301328809] or 0)
check(ids[8084763732] == 1, "esperava 1 relógio, achei %d", ids[8084763732] or 0)

-- Iluminação: suficiente pra enxergar, contida o bastante pra rodar.
local lights = 0
for _, d in lobby:GetDescendants() do
	if d:IsA("Light") then
		lights += 1
		check(d.Shadows == false, "luz com sombra ligada (%s) -- caro demais pro lobby", d.Parent.Name)
	end
end
check(lights >= 19 and lights <= 30, "quantidade de luzes fora do alvo: %d", lights)

--------------------------------------------------------------------------------
-- 8. Regerar é idempotente
--------------------------------------------------------------------------------

local again = Airport.Build({ Assets = false, Terrain = false })
local lobbies = 0
for _, child in Workspace:GetChildren() do
	if child.Name == "Lobby" then
		lobbies += 1
	end
end
check(lobbies == 1, "regerar deixou %d pastas Lobby", lobbies)

local partsAgain = 0
for _, d in again:GetDescendants() do
	if d:IsA("BasePart") then
		partsAgain += 1
	end
end
check(partsAgain == #parts, "regerar mudou a contagem: %d -> %d", #parts, partsAgain)

Airport.Clear()
check(Workspace:FindFirstChild("Lobby") == nil, "Clear() não removeu o lobby")

--------------------------------------------------------------------------------
-- 9. Reproduz o relato: Generate({ Terrain = false }) sozinho precisa varrer
-- o Air mesmo sem replantar grama nenhuma -- é o caso de "só tirar a grama".
--------------------------------------------------------------------------------

table.clear(stub.TerrainFills)
local noTerrainLobby = Airport.Build({ Assets = false, Terrain = false })
local sawAirSweep, sawGrass = false, false
for _, fill in stub.TerrainFills do
	if fill.Material.Name == "Air" then
		sawAirSweep = true
	elseif fill.Material.Name == "Grass" then
		sawGrass = true
	end
end
check(sawAirSweep, "Generate({ Terrain = false }) sozinho não varreu a grama residual -- exatamente o bug relatado")
check(not sawGrass, "Generate({ Terrain = false }) não deveria replantar grama nenhuma")
Airport.Clear()

-- Medidas, pra documentação não sair chutada.
local bLo, bHi
for _, p in parts do
	local lo, hi = aabb(p)
	bLo = if bLo then Vector3.new(math.min(bLo.X, lo.X), math.min(bLo.Y, lo.Y), math.min(bLo.Z, lo.Z)) else lo
	bHi = if bHi then Vector3.new(math.max(bHi.X, hi.X), math.max(bHi.Y, hi.Y), math.max(bHi.Z, hi.Z)) else hi
end
local collide, decoCount = 0, 0
for _, p in parts do
	if p.CanCollide then collide += 1 else decoCount += 1 end
end
print(string.format("airport_lobby: OK -- %d peças (%d com colisão, %d decorativas), %d luzes", #parts, collide, decoCount, lights))
print(string.format("  envelope construído: x %.0f..%.0f, y %.0f..%.0f, z %.0f..%.0f", bLo.X, bHi.X, bLo.Y, bHi.Y, bLo.Z, bHi.Z))
print(string.format("  piso caminhável: %d células de %dx%d studs (~%d studs quadrados)", #queue, STEP, STEP, #queue * STEP * STEP))
print(string.format("  vidro em z=%.0f; grama comeca em z=%.0f, ate z=%.0f", ORIGIN.Z - 104, grassNearEdge, -2800))
