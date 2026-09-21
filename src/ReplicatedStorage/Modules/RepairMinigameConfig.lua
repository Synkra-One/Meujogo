--!strict
--[[
	RepairMinigameConfig
	Números e matemática do minigame de precisão que substituiu o "segure E
	por alguns segundos" dos pontos reparáveis (server/RepairMinigameSystem.lua
	e client/RepairMinigameController.client.luau). Ver docs/ReparoMinigame.md.

	ESTE MÓDULO É COMPARTILHADO DE PROPÓSITO. O servidor é quem decide o
	resultado de cada teste, mas o cliente precisa desenhar o marcador
	exatamente onde o servidor acha que ele está -- senão o jogador vê o
	marcador no verde e o servidor conta amarelo. Por isso MarkerAt/Grade
	ficam aqui, puros, e os dois lados chamam as MESMAS funções sobre os
	MESMOS parâmetros de teste (que só o servidor sorteia).

	O cliente nunca manda progresso: ele manda "apertei no instante t do teste
	N" e o servidor recalcula a posição do marcador a partir disso.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local StatScaling = require(ReplicatedStorage.Modules.StatScaling)

local RepairMinigameConfig = {}

--------------------------------------------------------------------------------
-- Geometria do teste de precisão (tudo em fração da barra, 0 = esquerda, 1 = direita)
--------------------------------------------------------------------------------

RepairMinigameConfig.Bar = {
	-- Segundos que o marcador leva pra atravessar a barra UMA vez. Sorteado
	-- por teste dentro da faixa e depois escalado pelo Reparo do personagem
	-- (Tuning.speedScale) -- é o que impede "decorar" o ritmo.
	SweepPeriod = { Min = 0.72, Max = 1.15 },

	-- Quantas travessias o teste dura antes de expirar. Mínimo 2 pra sempre
	-- haver uma segunda chance quando a área nasce perto da borda.
	Sweeps = { Min = 2, Max = 3 },

	-- Respiro entre o teste aparecer na tela e o marcador começar a andar.
	LeadIn = 0.28,

	-- Meia-largura da área VERDE (acerto normal), antes do Reparo.
	GreenHalfWidth = { Min = 0.055, Max = 0.085 },
	-- Teto/piso depois do Reparo. O teto existe pra que nem Reparo 100 torne
	-- o minigame automático: 0.17 de meia-largura = 34% da barra, e o
	-- marcador ainda passa 66% do tempo fora dela.
	GreenHalfWidthClamp = { Min = 0.012, Max = 0.17 },

	-- Quanto a faixa AMARELA (acerto parcial) se estende além do verde, de
	-- cada lado. Fora disso é vermelho.
	YellowPad = { Min = 0.05, Max = 0.09 },

	-- Área AZUL de acerto perfeito: uma fatia no meio do verde. Não aparece
	-- em todo teste -- quando aparece, o painel muda de cara.
	PerfectChance = 0.55,
	PerfectFraction = 0.32, -- do verde

	-- Margem mínima entre a faixa amarela e as pontas da barra.
	EdgeMargin = 0.06,

	-- Intervalo entre o fim de um teste e o começo do próximo (segundos).
	-- Sorteado a cada vez: os testes NÃO caem em cadência fixa.
	Gap = { Min = 0.7, Max = 1.8 },
	-- Folga antes do primeiro teste, pra ninguém ser surpreendido no frame
	-- em que o reparo começa.
	FirstGap = { Min = 0.7, Max = 1.4 },
}

--------------------------------------------------------------------------------
-- Conclusão: SEQUÊNCIA de acertos
--------------------------------------------------------------------------------
-- NÃO existe progresso passivo. O reparo só termina quando o jogador acerta o
-- teste `Required` vezes SEGUIDAS; qualquer erro zera a sequência. Esperar
-- segurando a tecla não conclui nada -- só gera testes que expiram, e cada
-- teste expirado faz barulho.

RepairMinigameConfig.Streak = {
	-- Acertos seguidos (verde ou azul) pra concluir. Uma tarefa pode
	-- sobrescrever com `Required` em RepairMinigameConfig.Tasks.
	Required = 3,

	-- Amarelo NÃO conta como acerto. true = zera a sequência (sem barulho e
	-- sem travar); false = só não avança.
	YellowBreaks = true,

	-- "Conserto Relâmpago" (SurvivorPowerSystem): quantos acertos o poder
	-- dá de graça. Nunca completa sozinho -- sobra sempre pelo menos um
	-- acerto de verdade. Fixo pra todos, de propósito: o poder do Diego não
	-- multiplica de novo a vantagem que o atributo dele já dá.
	PowerBoostSteps = 1,
}

RepairMinigameConfig.Scoring = {
	-- Segundos que o próximo teste demora depois de um erro, ANTES de
	-- multiplicar pelo Reparo (Tuning.stallScale). Vermelho e teste expirado
	-- travam igual.
	RedStall = 1.2,
	MissStall = 1.2,

	-- Latência tolerada entre o instante que o cliente diz ter apertado e o
	-- instante em que o pedido chegou. Acima disso o servidor usa a hora de
	-- CHEGADA; um instante no FUTURO (além de FutureSlack) também é descartado.
	-- Com a área verde de personagem sem Reparo em ~30 ms, uma tolerância
	-- larga deixaria um cliente alterado acertar sempre.
	MaxInputLag = 0.22,
	FutureSlack = 0.05,
}

--------------------------------------------------------------------------------
-- Ruído da falha (server/NoiseService.lua -- mesmas regras de furtividade)
--------------------------------------------------------------------------------

RepairMinigameConfig.Noise = {
	-- Intensidade do estrondo de uma ferramenta caindo. Entre o passo
	-- corrido (3) e a pedra jogada (4) de GameConfig.Noise.
	FailIntensity = 3,

	-- Alcance em studs {Furtividade 0, Furtividade 100}. Errar SEMPRE faz
	-- barulho -- Furtividade só decide o quão longe ele chega. Começar ou
	-- terminar um reparo não gera ruído nenhum.
	FailRadius = { Min = 240, Max = 70 },
}

--------------------------------------------------------------------------------
-- Tarefas reparáveis (quem liga cada uma é o sistema dono do objetivo)
--------------------------------------------------------------------------------
-- Enabled = liga/desliga o minigame daquele ponto (desligado, o objetivo
-- resolve na hora). Required = acertos seguidos, se diferir de Streak.Required.
-- GeneratorShock = false tira ESTA tarefa do choque 3D no gerador (por padrão
-- todo erro de reparo toca -- ver GameConfig.RadioSite.ErroGerador).

RepairMinigameConfig.Tasks = {
	SabotagemFio = { Enabled = true, Label = "Fio cortado" },
	RadioInstalar = { Enabled = true, Label = "Instalando peça" },
	RadioPartida = { Enabled = true, Label = "Partida do gerador" },
	RadioPainel = { Enabled = true, Label = "Painel de controle" },
}

--------------------------------------------------------------------------------
-- Aparência (o cliente desenha tudo por código -- nenhuma imagem externa)
--------------------------------------------------------------------------------

RepairMinigameConfig.Theme = {
	Panel = Color3.fromRGB(13, 13, 14),
	PanelEdge = Color3.fromRGB(46, 44, 42),
	Rust = Color3.fromRGB(96, 52, 34),
	Track = Color3.fromRGB(26, 25, 25),
	Green = Color3.fromRGB(92, 186, 108),
	Yellow = Color3.fromRGB(226, 182, 62),
	Red = Color3.fromRGB(150, 46, 38),
	Perfect = Color3.fromRGB(104, 196, 233),
	Marker = Color3.fromRGB(246, 241, 226),
	Text = Color3.fromRGB(206, 198, 186),
	TextDim = Color3.fromRGB(132, 126, 118),
}

--------------------------------------------------------------------------------
-- Reparo -> vantagem (justa, nunca automática)
--------------------------------------------------------------------------------

--[[
	Tuning(player)
	Traduz o atributo Reparo em três alavancas de DIFICULDADE. Tudo passa por
	StatScaling.RepairMultiplier -- o multiplicador compartilhado do reparo e da
	sintonia já usavam --, então o card do personagem continua valendo e o
	Diego (Reparo 96) segue sendo o melhor reparador sem nenhuma regra
	especial em cima do nome dele.

	Reparo NÃO acelera nada: o reparo só conclui acertando a sequência, então
	o atributo decide o quão difícil é acertar.

	greenScale   largura da área verde (Reparo alto = área maior)
	periodScale  multiplica os SEGUNDOS por travessia: > 1 = marcador MAIS LENTO
	             (Reparo alto = mais lento, Reparo baixo = mais rápido)
	stallScale   quanto tempo trava depois de um erro (Reparo alto = menos)

	JANELA = quanto tempo o marcador fica dentro do verde: 2 * meia-largura *
	segundos por travessia. É o número que o jogador sente. Um humano prevê um
	marcador de velocidade constante com erro de ~40 ms, então:
	  Reparo 10  (Marina/Bruno)         ~30 ms -> acerta ~20% dos toques
	  Reparo 20  (Rafael/Sofia/Camila)  ~45 ms -> acerta ~40% dos toques
	  Reparo 96  (Diego)                ~125 ms -> acerta ~85% dos toques
	Três SEGUIDOS elevam isso ao cubo (Rafael ~6%, Diego ~60%). O marcador de
	quem tem Reparo baixo ainda OSCILA de velocidade (wobbleAmp), o que impede
	de decorar o ritmo e piora esses números. É o botão principal de
	dificuldade -- ajuste aqui depois do playtest.

	wobbleAmp    oscilação de velocidade do marcador (0 = velocidade constante)
]]
RepairMinigameConfig.TuningRange = {
	GreenScale = { Min = 0.27, Max = 0.85 },
	PeriodScale = { Min = 0.8, Max = 1.2 },
	StallScale = { Min = 1.7, Max = 0.6 },
	WobbleAmp = { Min = 0.13, Max = 0.02 },
}

-- Frequência da oscilação, em ciclos por travessia. Sorteada por teste.
RepairMinigameConfig.WobbleFreq = { Min = 0.6, Max = 1.1 }

function RepairMinigameConfig.Tuning(player: Player?): { greenScale: number, periodScale: number, stallScale: number, wobbleAmp: number }
	local efficiency = StatScaling.RepairMultiplier(player)
	local range = GameConfig.Characters.RepairSpeed
	local span = range.Max - range.Min
	local t = if span > 0 then math.clamp((efficiency - range.Min) / span, 0, 1) else 0.5
	local r = RepairMinigameConfig.TuningRange
	return {
		greenScale = r.GreenScale.Min + (r.GreenScale.Max - r.GreenScale.Min) * t,
		periodScale = r.PeriodScale.Min + (r.PeriodScale.Max - r.PeriodScale.Min) * t,
		stallScale = r.StallScale.Min + (r.StallScale.Max - r.StallScale.Min) * t,
		wobbleAmp = r.WobbleAmp.Min + (r.WobbleAmp.Max - r.WobbleAmp.Min) * t,
	}
end

--------------------------------------------------------------------------------
-- Matemática do marcador (servidor e cliente chamam exatamente isto)
--------------------------------------------------------------------------------

export type Test = {
	id: number,
	startsAt: number, -- Workspace:GetServerTimeNow() em que o marcador começa
	period: number, -- segundos por travessia
	sweeps: number,
	center: number,
	greenHalf: number,
	yellowHalf: number,
	perfectHalf: number, -- 0 quando este teste não tem área perfeita
	style: number, -- 1..3, variação visual
	-- Oscilação de velocidade (opcionais; ausentes = velocidade constante).
	wobbleAmp: number?,
	wobbleFreq: number?,
	wobblePhase: number?,
}

export type Grade = "Perfect" | "Green" | "Yellow" | "Red"

--[[
	MarkerAt(test, elapsed)
	Posição do marcador (0..1) `elapsed` segundos depois do início do teste.
	Vai e volta (ping-pong) entre as pontas. Com `wobbleAmp` a velocidade
	oscila ao longo da travessia (o marcador acelera, freia e pode até recuar
	um instante), então o ritmo não dá pra decorar. A oscilação é subtraída no
	instante 0 pra o marcador sempre nascer na ponta esquerda.
]]
function RepairMinigameConfig.MarkerAt(test: Test, elapsed: number): number
	if elapsed <= 0 or test.period <= 0 then
		return 0
	end
	local travel = elapsed / test.period
	local amp = test.wobbleAmp or 0
	if amp > 0 then
		local theta = test.wobblePhase or 0
		travel += amp * (math.sin(2 * math.pi * (test.wobbleFreq or 1) * travel + theta) - math.sin(theta))
	end
	local phase = travel % 2
	return if phase <= 1 then phase else 2 - phase
end

--[[ Duração total do teste antes de expirar. ]]
function RepairMinigameConfig.TestWindow(test: Test): number
	return test.period * test.sweeps
end

--[[ Grade(test, x) -- em que faixa caiu a posição x (0..1). ]]
function RepairMinigameConfig.Grade(test: Test, x: number): Grade
	local distance = math.abs(x - test.center)
	if test.perfectHalf > 0 and distance <= test.perfectHalf then
		return "Perfect"
	elseif distance <= test.greenHalf then
		return "Green"
	elseif distance <= test.yellowHalf then
		return "Yellow"
	end
	return "Red"
end

return RepairMinigameConfig
