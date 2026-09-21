--!strict
-- Regras compartilhadas; servidor consulta somente suas próprias instâncias.
local GameConfig = require(game:GetService("ReplicatedStorage").Modules.GameConfig)
local Rules = {}
export type WeaponDefinition = {
	DisplayName: string, Kind: string, Damage: number, Range: number, Cooldown: number,
	PushForce: number?, StunDuration: number?, Ammo: number?, ReloadEnabled: boolean?,
	AnimationsEnabled: boolean?, Recoil: number?, Spread: number?,
	RevealMonster: boolean?, RepelMonster: boolean?,
	ClientDriven: boolean?, Heavy: { [string]: any }?,
}
-- Golpe pedido pelo cliente: "Heavy" só vale se a arma definir Heavy; qualquer
-- outro valor cai no golpe leve. Nunca aceita números do cliente.
function Rules.Profile(definition: WeaponDefinition, variant: unknown): WeaponDefinition
	local heavy = definition.Heavy
	if variant ~= "Heavy" or not heavy then return definition end
	local merged = table.clone(definition)
	for key, value in heavy do (merged :: any)[key] = value end
	return merged
end
function Rules.Definition(candidate: unknown): WeaponDefinition?
	if typeof(candidate) ~= "Instance" or not (candidate :: Instance):IsA("Tool") then return nil end
	local tool = candidate :: Tool
	if tool.Name == "Glock17" then
		local flag = tool:FindFirstChild("Weapon")
		if flag and flag:IsA("BoolValue") and flag.Value then return GameConfig.Weapons.Definitions.Glock17 end
		return nil
	end
	local found: WeaponDefinition? = nil
	for id, definition in GameConfig.Weapons.Definitions do
		if definition.Kind ~= "Firearm" and tool:GetAttribute(id) == true then
			if found then return nil end -- rejeita identidade ambígua
			found = definition
		end
	end
	return found
end
function Rules.CanAttack(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local role = player:GetAttribute("Role")
	if not character or not humanoid or humanoid.Health <= 0
		or (role ~= GameConfig.Roles.Survivor and role ~= GameConfig.Roles.Spy)
		or player:GetAttribute("InRound") ~= true or player:GetAttribute("InWaitingRoom") == true
		or character:FindFirstChild("Dead") then return false end
	-- O servidor respeita estados de animacao que tomam o corpo; o cliente ja
	-- os usa para UX, mas nao e autoridade para liberar um golpe durante dano/
	-- morte. WeaponAttackActive e tratado separadamente pelo WeaponSystem.
	local animationState = character:GetAttribute("CombatAnimationState")
	if animationState == "Hurt" or animationState == "Death" then return false end
	for _, name in { "Eliminado", "Amarrado", "GrabLocked", "PowerStunned", "ShadowRushBusy", "TeleportBusy" } do
		if player:GetAttribute(name) == true or character:GetAttribute(name) == true then return false end
	end
	return true
end
function Rules.IsReady(now: number, readyAt: number?): boolean
	return readyAt == nil or now >= readyAt
end
return table.freeze(Rules)
