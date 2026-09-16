--!strict
--[[
	StatScaling
	Traduz atributo de personagem (0..100) em número de jogo, usando as faixas
	de GameConfig.Characters. É o ÚNICO lugar que faz essa conta -- servidor e
	cliente (UI) usam o mesmo módulo, então o que o card promete é o que o jogo
	entrega.

	Toda função aqui aceita `stat` nil (jogador que ainda não escolheu
	personagem) e devolve o valor neutro (fator 1 / o meio da faixa), pra
	nenhum sistema precisar de `if temPersonagem then`.

	FAIXA INVERTIDA é proposital em alguns casos (Min > Max): quanto MAIOR o
	atributo, MENOR o número. Ex: StaminaDrain {26, 11} -- Stamina 100 gasta
	11 por segundo, Stamina 0 gasta 26.

	LEITURA DOS ATRIBUTOS JÁ APLICADOS: CharacterStatsApplier publica cada
	atributo como Attribute no Player ("Stat_Velocidade", "Stat_Forca", ...).
	StatScaling.Of(player, "Forca") lê de lá -- é como os sistemas antigos
	consultam sem precisar saber qual personagem é.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local LoadoutData = require(ReplicatedStorage.Modules.LoadoutData)

local StatScaling = {}

local CFG = GameConfig.Characters

local function perkMultiplier(player: Player?, key: string): number
	if not player or player:GetAttribute("InRound") ~= true then return 1 end
	local perk = LoadoutData.GetPerk(player:GetAttribute("PerkId"))
	return if perk then (perk :: any)[key] or 1 else 1
end

-- Prefixo dos Attributes no Player (ver CharacterStatsApplier).
StatScaling.AttributePrefix = "Stat_"

--[[
	Lerp(stat, range)
	Mapeia 0..100 linearmente em range.Min..range.Max. stat nil = 50 (meio).
]]
function StatScaling.Lerp(stat: number?, range: { Min: number, Max: number }): number
	local t = math.clamp((stat or 50) / 100, 0, 1)
	return range.Min + (range.Max - range.Min) * t
end

--[[
	Of(player, statName)
	Lê o atributo já aplicado no Player. Devolve nil se o jogador ainda não
	tem personagem (aí quem chamou cai no valor neutro pelo Lerp).
]]
function StatScaling.Of(player: Player?, statName: string): number?
	if not player then
		return nil
	end
	local value = player:GetAttribute(StatScaling.AttributePrefix .. statName)
	return if type(value) == "number" then value else nil
end

-- Aceita Player, Model (character) ou Humanoid e resolve pro Player dono.
function StatScaling.PlayerFrom(target: unknown): Player?
	if typeof(target) ~= "Instance" then
		return nil
	end
	local inst = target :: Instance
	if inst:IsA("Player") then
		return inst
	end
	local model = if inst:IsA("Model") then inst else inst:FindFirstAncestorOfClass("Model")
	return if model then Players:GetPlayerFromCharacter(model) else nil
end

--------------------------------------------------------------------------------
-- Fatores por atributo (a API que os sistemas do jogo usam)
--------------------------------------------------------------------------------

--[[ Velocidade -> WalkSpeed base em studs/s. ]]
function StatScaling.WalkSpeed(player: Player?): number
	return StatScaling.Lerp(StatScaling.Of(player, "Velocidade"), CFG.WalkSpeed)
end

--[[
	Velocidade -> multiplicador sobre o WalkSpeed de referência do pacote de
	movimento. É ISSO que o script Crouching multiplica (Attribute "SpeedMul").
]]
function StatScaling.SpeedMultiplier(player: Player?): number
	return StatScaling.WalkSpeed(player) / CFG.ReferenceWalkSpeed
end

--[[ Stamina -> quanto de fôlego some por segundo correndo. ]]
function StatScaling.StaminaDrain(player: Player?): number
	return StatScaling.Lerp(StatScaling.Of(player, "Stamina"), CFG.StaminaDrain)
end

--[[ Stamina -> quanto de fôlego volta por segundo. ]]
function StatScaling.StaminaRegen(player: Player?): number
	return StatScaling.Lerp(StatScaling.Of(player, "Stamina"), CFG.StaminaRegen) * perkMultiplier(player, "StaminaRegen")
end

--[[ Compostura -> vida máxima. ]]
function StatScaling.MaxHealth(player: Player?): number
	return StatScaling.Lerp(StatScaling.Of(player, "Compostura"), CFG.MaxHealth)
end

--[[ Compostura -> multiplicador do dano RECEBIDO (menor = mais resistente). ]]
function StatScaling.DamageTakenMultiplier(player: Player?): number
	return StatScaling.Lerp(StatScaling.Of(player, "Compostura"), CFG.DamageTaken) * perkMultiplier(player, "DamageTaken")
end

-- Fear usa a mesma escala/prefixo/fallback dos demais atributos. Não publica
-- outro Composure e não muda as faixas existentes de vida/dano.
function StatScaling.FearGainMultiplier(player: Player?): number
	local t = StatScaling.Lerp(StatScaling.Of(player, "Compostura"), { Min = 0, Max = 1 })
	local range = GameConfig.Fear.ComposureGain
	return range.Min + (range.Max - range.Min) * t ^ GameConfig.Fear.ComposureGainExponent
end

function StatScaling.FearRecoveryMultiplier(player: Player?): number
	local t = StatScaling.Lerp(StatScaling.Of(player, "Compostura"), { Min = 0, Max = 1 })
	local range = GameConfig.Fear.ComposureRecovery
	return range.Min + (range.Max - range.Min) * t ^ GameConfig.Fear.ComposureRecoveryExponent
end

--[[ Força -> multiplicador do dano CAUSADO. ]]
function StatScaling.DamageDealtMultiplier(player: Player?): number
	return StatScaling.Lerp(StatScaling.Of(player, "Forca"), CFG.DamageDealt)
end

--[[ Furtividade -> multiplicador do tempo até a tensão começar a subir. ]]
function StatScaling.StealthThresholdMultiplier(player: Player?): number
	return StatScaling.Lerp(StatScaling.Of(player, "Furtividade"), CFG.StealthThreshold)
end

--[[
	NoiseState(speed, walkBase)
	Classifica o movimento pela velocidade horizontal REAL, normalizada pela
	base de caminhada do personagem. Devolve a chave de GameConfig.Noise.States
	("Crouch" | "Walk" | "Jog" | "Sprint") ou nil quando está parado.

	É medição física de propósito: é o que impede o cliente de mentir postura
	para andar em silêncio na velocidade de corrida. Ver Characters.MovementBands.
]]
function StatScaling.NoiseState(speed: number, walkBase: number): string?
	if speed <= GameConfig.Noise.MinMovingSpeed or walkBase <= 0 then
		return nil
	end
	local ratio = speed / walkBase
	if ratio <= CFG.MovementBands.Crouch then
		return "Crouch"
	elseif ratio <= CFG.MovementBands.Walk then
		return "Walk"
	elseif ratio <= CFG.SprintSpeedRatio then
		return "Jog"
	end
	return "Sprint"
end

-- Toda leitura de Furtividade passa por aqui, então o "0 = nada muda" e o
-- "personagem ainda não escolhido = meio da faixa" valem para os dois números.
local function stealthLerp(player: Player?, state: string, field: string): number?
	local profile = GameConfig.Noise.States[state]
	if not profile then
		return nil
	end
	return StatScaling.Lerp(StatScaling.Of(player, "Furtividade"), (profile :: any)[field])
end

--[[
	NoiseRadius(player, state)
	Furtividade -> até onde o Monstro pode ouvir este estado de movimento, em
	studs. FAIXA INVERTIDA: Furtividade alta devolve um raio MENOR.
	Devolve nil se o estado não existe.
]]
function StatScaling.NoiseRadius(player: Player?, state: string): number?
	return stealthLerp(player, state, "Radius")
end

--[[
	NoisePingInterval(player, state)
	Furtividade -> segundos entre um ruído e o próximo deste mesmo estado.
	FAIXA INVERTIDA ao contrário das outras: Furtividade alta devolve um
	intervalo MAIOR (menos pings). Devolve nil se o estado não existe.
]]
function StatScaling.NoisePingInterval(player: Player?, state: string): number?
	return stealthLerp(player, state, "Interval")
end

--[[ Reparo -> multiplicador de progresso de objetivo (Jangada / Rádio). ]]
function StatScaling.RepairMultiplier(player: Player?): number
	return StatScaling.Lerp(StatScaling.Of(player, "Reparo"), CFG.RepairSpeed) * perkMultiplier(player, "Repair")
end

--[[ Sorte -> multiplicador da QUANTIDADE de itens que sai de uma caixa. ]]
function StatScaling.LootQuantityMultiplier(player: Player?): number
	return StatScaling.Lerp(StatScaling.Of(player, "Sorte"), CFG.LootQuantity)
end

--[[ Sorte -> multiplicador do PESO dos itens raros no sorteio da caixa. ]]
function StatScaling.LootRarityMultiplier(player: Player?): number
	return StatScaling.Lerp(StatScaling.Of(player, "Sorte"), CFG.LootRarity)
end

return StatScaling
