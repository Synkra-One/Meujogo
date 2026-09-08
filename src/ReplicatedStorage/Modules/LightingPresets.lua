--!strict
--[[
	LightingPresets
	Climas prontos pra aplicar em Lighting. "Night" é uma cópia fiel do que já
	estava salvo em default.project.json (Lighting) -- existe aqui só pra não
	perder esse clima quando outro preset for aplicado por cima. "CloudyMorning"
	é o novo: manhã nublada, luz difusa, sem sol aparente.

	Uso (servidor, uma vez no boot):
		local LightingPresets = require(...)
		LightingPresets.Apply(GameConfig.Environment.LightingPreset)
]]

local Lighting = game:GetService("Lighting")

local LightingPresets = {}

export type Preset = {
	Properties: { [string]: any },
	Atmosphere: { [string]: any },
	SomberColor: { [string]: any },
	LowLightBloom: { [string]: any },
	WeakDuskRays: { [string]: any },
}

LightingPresets.Presets = {
	-- Clima atual do jogo (salvo aqui como registro -- default.project.json
	-- continua sendo a fonte de verdade do que carrega por padrão).
	-- Noite de acampamento (Friday the 13th): luar frio, neblina baixa que
	-- fecha a floresta a ~300 studs (você não vê um POI do outro num mapa
	-- de ~1500), lampiões e fogueiras como pontos de referência.
	Night = {
		Properties = {
			Ambient = Color3.new(0.16, 0.18, 0.24),
			OutdoorAmbient = Color3.new(0.26, 0.29, 0.38),
			Brightness = 1.25,
			ClockTime = 0.3,
			ExposureCompensation = -0.05,
			FogColor = Color3.new(0.14, 0.16, 0.21),
			FogEnd = 320,
			FogStart = 40,
			GlobalShadows = true,
			Outlines = false,
			Technology = Enum.Technology.Voxel,
		},
		Atmosphere = {
			Density = 0.44,
			Offset = 0.1,
			Color = Color3.new(0.4, 0.45, 0.58),
			Decay = Color3.new(0.14, 0.16, 0.24),
			Glare = 0.02,
			Haze = 3.0,
		},
		SomberColor = {
			Brightness = 0.02,
			Contrast = 0.1,
			Saturation = -0.14,
			TintColor = Color3.new(0.82, 0.88, 1),
		},
		LowLightBloom = {
			Intensity = 0.18,
			Size = 16,
			Threshold = 1.05,
		},
		WeakDuskRays = {
			Intensity = 0.01,
			Spread = 0.75,
		},
	},

	-- Manhã nublada: luz difusa e neutra, nevoeiro mais claro e mais longe
	-- (ainda dá pra ver longe, só sem sol forte), sem brilho/sunrays de sol
	-- aparente já que o céu está encoberto.
	CloudyMorning = {
		Properties = {
			Ambient = Color3.new(0.42, 0.43, 0.46),
			OutdoorAmbient = Color3.new(0.58, 0.6, 0.64),
			Brightness = 2.3,
			ClockTime = 8,
			ExposureCompensation = 0,
			FogColor = Color3.new(0.75, 0.77, 0.8),
			FogEnd = 1400, -- mapa de ~1500: dá pra ver longe pra depurar o layout
			FogStart = 200,
			GlobalShadows = true,
			Outlines = false,
			Technology = Enum.Technology.Voxel,
		},
		Atmosphere = {
			Density = 0.5,
			Offset = 0.25,
			Color = Color3.new(0.76, 0.77, 0.8),
			Decay = Color3.new(0.55, 0.56, 0.6),
			Glare = 0,
			Haze = 3.6,
		},
		SomberColor = {
			Brightness = 0,
			Contrast = -0.05,
			Saturation = -0.25,
			TintColor = Color3.new(0.92, 0.95, 1),
		},
		LowLightBloom = {
			Intensity = 0.08,
			Size = 14,
			Threshold = 1.2,
		},
		WeakDuskRays = {
			Intensity = 0, -- sem sol visível, sem raios
			Spread = 0.75,
		},
	},
} :: { [string]: Preset }

local function applyProperties(instance: Instance, values: { [string]: any })
	for key, value in values do
		local ok, err = pcall(function()
			(instance :: any)[key] = value
		end)
		if not ok then
			warn(string.format("[LightingPresets] Nao consegui aplicar %s.%s: %s", instance:GetFullName(), key, tostring(err)))
		end
	end
end

local function getOrCreate(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance
end

function LightingPresets.Apply(name: string)
	local preset = LightingPresets.Presets[name]
	if not preset then
		warn("[LightingPresets] Preset desconhecido: " .. tostring(name))
		return
	end
	applyProperties(Lighting, preset.Properties)
	applyProperties(getOrCreate("Atmosphere", "Atmosphere"), preset.Atmosphere)
	applyProperties(getOrCreate("ColorCorrectionEffect", "SomberColor"), preset.SomberColor)
	applyProperties(getOrCreate("BloomEffect", "LowLightBloom"), preset.LowLightBloom)
	applyProperties(getOrCreate("SunRaysEffect", "WeakDuskRays"), preset.WeakDuskRays)
end

return LightingPresets
