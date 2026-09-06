--!strict
-- Opções iniciais da sala. Skins são cosméticas; um perk por jogador.
local LoadoutData = {}

export type Skin = { Id: string, Nome: string, Descricao: string, Color: Color3? }
export type Perk = {
	Id: string, Nome: string, Descricao: string,
	StaminaRegen: number?, Repair: number?, DamageTaken: number?,
}

LoadoutData.Skins = {
	{ Id = "Padrao", Nome = "Original", Descricao = "Seu avatar, sem colete." },
	{ Id = "Explorador", Nome = "Explorador", Descricao = "Colete marrom de expedição.", Color = Color3.fromRGB(128, 91, 55) },
	{ Id = "Noturno", Nome = "Noturno", Descricao = "Colete azul-escuro.", Color = Color3.fromRGB(34, 48, 72) },
} :: { Skin }

LoadoutData.Perks = {
	{ Id = "Nenhum", Nome = "Sem perk", Descricao = "Sem bônus adicional." },
	{ Id = "Folego", Nome = "Fôlego", Descricao = "Recupera stamina 10% mais rápido.", StaminaRegen = 1.1 },
	{ Id = "Tecnico", Nome = "Técnico", Descricao = "Repara objetivos 10% mais rápido.", Repair = 1.1 },
	{ Id = "Resistente", Nome = "Resistente", Descricao = "Recebe 5% menos dano.", DamageTaken = 0.95 },
} :: { Perk }

function LoadoutData.GetSkin(id: unknown): Skin?
	for _, option in LoadoutData.Skins do
		if option.Id == id then return option end
	end
	return nil
end

function LoadoutData.GetPerk(id: unknown): Perk?
	for _, option in LoadoutData.Perks do
		if option.Id == id then return option end
	end
	return nil
end

return LoadoutData
