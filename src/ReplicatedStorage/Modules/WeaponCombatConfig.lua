--!strict
--[[
	WeaponCombatConfig
	Perfil espacial e temporal do combate corpo a corpo. Dano, alcance e
	cooldown continuam com GameConfig.Weapons.Definitions: este modulo os expoe
	para que cada arma tenha UM perfil completo, sem copiar numeros de balance.

	A janela do servidor usa HitStart/HitEnd. Os nomes de Markers ficam aqui para
	as animacoes poderem iniciar no marker AttackStart quando ele existir; clips
	sem markers usam os tempos abaixo como fallback autoritativo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

export type Profile = {
	WeaponId: string,
	AttributeName: string,
	Damage: number,
	Range: number,
	Cooldown: number,
	HitboxSize: Vector3,
	ForwardOffset: number,
	HitStart: number,
	HitEnd: number,
	AttackEnd: number,
	MaxTargetDistance: number,
	MinimumForwardDot: number,
	ImpactSound: string,
	ImpactColor: Color3,
	ImpactShake: number,
	Knockback: number,
	StunDuration: number,
	Markers: { [string]: string },
	Heavy: Profile?,
}

local definitions = GameConfig.Weapons.Definitions
local markers = table.freeze({
	AttackStart = "AttackStart",
	HitStart = "HitStart",
	HitEnd = "HitEnd",
	AttackEnd = "AttackEnd",
})

local function profile(weaponId: string, values: { [string]: any }): Profile
	local definition = definitions[weaponId]
	assert(definition, string.format("[WeaponCombatConfig] Definicao ausente: %s", weaponId))
	local balance = values.Balance or definition
	return table.freeze({
		WeaponId = weaponId,
		AttributeName = weaponId,
		Damage = balance.Damage,
		Range = balance.Range,
		Cooldown = balance.Cooldown,
		HitboxSize = values.HitboxSize,
		ForwardOffset = values.ForwardOffset,
		HitStart = values.HitStart,
		HitEnd = values.HitEnd,
		AttackEnd = values.AttackEnd,
		MaxTargetDistance = values.MaxTargetDistance or balance.Range,
		MinimumForwardDot = values.MinimumForwardDot or GameConfig.Weapons.MeleeConeCos,
		ImpactSound = values.ImpactSound,
		ImpactColor = values.ImpactColor,
		ImpactShake = values.ImpactShake,
		Knockback = balance.PushForce or 0,
		StunDuration = balance.StunDuration or 0,
		Markers = markers,
		Heavy = values.Heavy,
	}) :: Profile
end

-- Os SoundIds abaixo ja existem em WeaponAssets/Audios.rbxmx (Metal/Wood).
-- HitboxSize e largura/altura/profundidade; ForwardOffset desloca a caixa para
-- a frente do HumanoidRootPart. Todos os tempos sao segundos desde AttackStart.
local wrench = profile("PedraAfiada", {
	HitboxSize = Vector3.new(2.4, 2.8, 4.2), ForwardOffset = 2.8,
	HitStart = 0.12, HitEnd = 0.27, AttackEnd = 0.58,
	ImpactSound = "rbxassetid://1565756818", ImpactColor = Color3.fromRGB(205, 225, 255), ImpactShake = 0.10,
})

local crowbar = profile("LancaDeBambu", {
	HitboxSize = Vector3.new(3.1, 3.2, 5.7), ForwardOffset = 3.4,
	HitStart = 0.18, HitEnd = 0.39, AttackEnd = 0.92,
	ImpactSound = "rbxassetid://282954576", ImpactColor = Color3.fromRGB(235, 180, 88), ImpactShake = 0.14,
})

local batHeavy = profile("TacoBeisebol", {
	Balance = definitions.TacoBeisebol.Heavy,
	HitboxSize = Vector3.new(5.2, 4.2, 7.8), ForwardOffset = 3.6,
	HitStart = 0.34, HitEnd = 0.62, AttackEnd = 1.35,
	ImpactSound = "rbxassetid://142082171", ImpactColor = Color3.fromRGB(255, 196, 92), ImpactShake = 0.24,
})

local bat = profile("TacoBeisebol", {
	HitboxSize = Vector3.new(4.4, 3.8, 7.0), ForwardOffset = 3.6,
	HitStart = 0.20, HitEnd = 0.47, AttackEnd = 0.88,
	ImpactSound = "rbxassetid://142082171", ImpactColor = Color3.fromRGB(255, 214, 144), ImpactShake = 0.18,
	Heavy = batHeavy,
})

-- Mantem a faca legado funcional sem criar uma quarta configuracao publica.
local fallback = profile("FacaImprovisada", {
	HitboxSize = Vector3.new(2.2, 2.6, 3.2), ForwardOffset = 2.3,
	HitStart = 0.11, HitEnd = 0.25, AttackEnd = 0.55,
	ImpactSound = "rbxassetid://1565756818", ImpactColor = Color3.fromRGB(220, 220, 220), ImpactShake = 0.09,
})

local byAttribute: { [string]: Profile } = {
	PedraAfiada = wrench,
	LancaDeBambu = crowbar,
	TacoBeisebol = bat,
	FacaImprovisada = fallback,
}

local WeaponCombatConfig = {
	Wrench = wrench,
	Crowbar = crowbar,
	BaseballBat = bat,
	Debug = table.freeze({
		Enabled = false,
		DrawLifetime = 0.08,
		VerboseRejections = false,
	}),
	SampleInterval = 1 / 30,
}

function WeaponCombatConfig.ForTool(tool: Tool, variant: unknown): Profile?
	for attributeName, candidate in byAttribute do
		if tool:GetAttribute(attributeName) == true then
			if variant == "Heavy" and candidate.Heavy then
				return candidate.Heavy
			end
			return candidate
		end
	end
	return nil
end

return table.freeze(WeaponCombatConfig)
