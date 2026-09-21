--!strict
--[[
	LevelSystem
	Curva de nível da CONTA do jogador, derivada do XP total persistente
	(DataStoreManager.GetXP). Puramente funcional: não lê nem escreve nada,
	só transforma um número de XP em nível/progresso. De propósito -- quem
	persiste XP (DataStoreManager) não precisa saber como o nível é
	calculado, e quem calcula nível não precisa saber onde o XP mora. Um dia
	pra trocar a curva, mexa SÓ neste arquivo.

	CURVA (dois números pra ajustar, ver abaixo)
	  XP acumulado pra alcançar o nível N (N >= 1, nível 1 = 0 XP):
	    XPToReach(N) = BaseXP * (N - 1) ^ GrowthExponent

	  BaseXP           XP entre o nível 1 e o nível 2.
	  GrowthExponent   > 1 faz cada nível pedir progressivamente mais XP que
	                   o anterior (curva "RPG" clássica, a que se quer aqui).
	                   = 1 seria linear (todo nível custa o mesmo). < 1
	                   ficaria mais fácil no fim do que no começo.

	!! NÚMEROS AINDA PROVISÓRIOS !! Calibrados só pela ordem de grandeza já
	documentada em MatchRewardsConfig (uma partida boa rende ~600-900 XP):
	nessa curva, os primeiros níveis caem em 1-2 partidas e o nível 100
	(teto) fica perto de ~100 partidas. Não passou por teste de
	balanceamento real -- ajuste BaseXP/GrowthExponent à vontade. Ninguém
	copia esta curva: servidor e cliente sempre chamam as funções daqui.

	Uso:
		local LevelSystem = require(ReplicatedStorage.Modules.LevelSystem)
		local level = LevelSystem.GetLevel(totalXP)
		local level, intoLevel, forNextLevel, atMax = LevelSystem.GetProgress(totalXP)
]]

local LevelSystem = {}

-- Ajuste livre: ver o cabeçalho acima pro efeito de cada constante.
LevelSystem.BaseXP = 150
LevelSystem.GrowthExponent = 1.35
LevelSystem.MaxLevel = 100

--[[
	XPToReach(level)
	XP TOTAL acumulado necessário pra estar EXATAMENTE no início deste
	nível. Nível 1 = 0 (todo mundo começa nele). Clampa em [1, MaxLevel]:
	pedir um nível fora da faixa devolve o valor da borda, nunca extrapola.
]]
function LevelSystem.XPToReach(level: number): number
	local clamped = math.clamp(math.floor(level), 1, LevelSystem.MaxLevel)
	if clamped <= 1 then
		return 0
	end
	return math.floor(LevelSystem.BaseXP * (clamped - 1) ^ LevelSystem.GrowthExponent + 0.5)
end

--[[
	GetLevel(totalXP)
	Nível atual pra este tanto de XP acumulado. Nunca passa de MaxLevel,
	nunca fica abaixo de 1, e ignora XP negativo (não deveria existir, mas
	um valor sujo não pode gerar nível fracionário/negativo).
]]
function LevelSystem.GetLevel(totalXP: number): number
	local xp = math.max(0, totalXP)
	-- Busca linear é suficiente: MaxLevel é pequeno (100) e isto não roda em
	-- loop quente -- só quando o XP muda (fim de partida) ou a UI abre.
	for level = LevelSystem.MaxLevel, 1, -1 do
		if xp >= LevelSystem.XPToReach(level) then
			return level
		end
	end
	return 1
end

--[[
	GetProgress(totalXP)
	Devolve (nível, xpDentroDoNível, xpParaOPróximoNível, noTeto).
	  xpDentroDoNível      quanto do XP total já foi "gasto" neste nível.
	  xpParaOPróximoNível  largura do nível atual (o que falta pra subir).
	No teto (nível == MaxLevel) os dois últimos valores voltam 0 -- não tem
	"próximo nível" pra uma barra de progresso mostrar.
]]
function LevelSystem.GetProgress(totalXP: number): (number, number, number, boolean)
	local xp = math.max(0, totalXP)
	local level = LevelSystem.GetLevel(xp)
	local atMax = level >= LevelSystem.MaxLevel

	if atMax then
		return level, 0, 0, true
	end

	local floor = LevelSystem.XPToReach(level)
	local ceiling = LevelSystem.XPToReach(level + 1)
	return level, xp - floor, ceiling - floor, false
end

return LevelSystem
