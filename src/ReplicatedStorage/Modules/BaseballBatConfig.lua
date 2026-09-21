--!strict
-- Visual + animacao do Taco de Beisebol. Dano/alcance/cooldown ficam em
-- GameConfig.Weapons.Definitions.TacoBeisebol (o servidor e a autoridade).
return table.freeze({
	MeshId = "rbxassetid://54983181",
	-- Textura do mesh (cole o rbxassetid). "" = madeira lisa via Color/Material.
	TextureId = "",
	Color = Color3.fromRGB(168, 124, 80),
	Material = Enum.Material.Wood,
	Length = 3.4, -- studs; o maior lado do mesh e normalizado pra isto

	-- Se existir ServerStorage.<TemplateName> (Tool ou container com uma Tool),
	-- ela vira o taco no lugar do mesh: preserva Grip, textura e escala do
	-- modelo original. Exporte a Tool do Explorer como .rbxm em src/ServerStorage.
	TemplateName = "TacoBeisebol",

	-- Sem template, o Grip e calculado: o maior eixo do mesh vira o braco, a mao
	-- segura perto de uma ponta. Se o taco aparecer de cabeca pra baixo, troque o
	-- sinal de HandleEndSign. GripOverride (CFrame) ignora tudo isso.
	HandleEndSign = -1, -- -1: ponta fina no lado negativo do eixo longo; 1: no positivo
	HandleEndFraction = 0.32, -- distancia do centro ate a mao, em fracao do comprimento
	GripOverride = nil :: CFrame?,

	Animations = table.freeze({
		Idle = "rbxassetid://137364111320171",
		Hit = "rbxassetid://138409446604086",
		Finish = "rbxassetid://122663486568815",
	}),
	-- Idle compartilha a camada Movement com o Animate. Isso permite que o
	-- clip do Taco e walk/run sejam misturados em vez de o Taco bloquear o
	-- corpo inteiro com uma prioridade Action.
	IdleMovingWeight = 0.22,
	AnimationFadeTime = 0.12,
	AnimationLoadWarningDelay = 2,
	-- Espera curta pelo marker AttackStart antes de usar o fallback. Isto so
	-- controla quando o pedido e enviado; HitStart/HitEnd sao servidor-side em
	-- WeaponCombatConfig para impedir que um cliente abra a hitbox livremente.
	MarkerStartFallback = 0.04,

	-- Clique curto = Hit; segurar o botao ate HoldThreshold = Finish.
	HoldThreshold = 0.3,
	-- Momento do impacto dentro da animacao: fracao do comprimento do clip
	-- (ImpactFraction) ou, se o clip ainda nao carregou, segundos fixos.
	Swings = table.freeze({
		Hit = table.freeze({ ImpactFraction = 0.4, FallbackImpact = 0.18, FallbackLength = 0.6 }),
		Finish = table.freeze({ ImpactFraction = 0.5, FallbackImpact = 0.35, FallbackLength = 1.0 }),
	}),
	-- Folga somada ao cooldown do servidor pra o cliente nunca golpear antes
	-- dele liberar (senao a animacao toca e o dano e recusado).
	CooldownPadding = 0.08,

	PollInterval = 0.1,
})
