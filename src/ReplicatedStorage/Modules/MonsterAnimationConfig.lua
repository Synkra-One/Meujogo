--!strict
--[[
	MonsterAnimationConfig

	ÚNICO lugar para colar os ids publicados das animações do Monster.
	Todas devem ser exportadas pelo Animation Editor usando
	ReplicatedStorage.MonsterAnimationRig (ou sua cópia de autoria no Workspace).
	Não use assets R15 nem animações feitas em outro R6 com joints alterados.
]]

local MonsterAnimationConfig = {}

MonsterAnimationConfig.TemplateName = "MonsterAnimationRig"
MonsterAnimationConfig.AuthoringRigName = "Monster Animation Rig (Authoring)"

-- A ordem é deliberada: é também a assinatura que o validador compara.
MonsterAnimationConfig.RequiredParts = {
	"HumanoidRootPart",
	"Torso",
	"Head",
	"Right Arm",
	"Left Arm",
	"Right Leg",
	"Left Leg",
}

MonsterAnimationConfig.RequiredMotors = {
	"RootJoint",
	"Neck",
	"Right Shoulder",
	"Left Shoulder",
	"Right Hip",
	"Left Hip",
}

-- COLE OS NOVOS IDS AQUI, após publicar pelo dono/grupo deste jogo.
-- Vazio = a camada correspondente não toca; nunca há fallback para animação R15.
MonsterAnimationConfig.AnimationIds = {
	Idle = "",
	Walk = "",
	Run = "",
	Attack = "",
	Damage = "",
	Death = "",
}

MonsterAnimationConfig.Locomotion = {
	WalkSpeed = 0.75,
	RunSpeed = 17,
	FadeTime = 0.14,
}

MonsterAnimationConfig.Preview = {
	EnabledInStudioOnly = true,
	SpawnCFrame = CFrame.new(0, 3.6, 0),
	CameraOffset = CFrame.new(10, 6, 15),
}

function MonsterAnimationConfig.IsUsableAnimationId(value: unknown): boolean
	return type(value) == "string" and value ~= "" and value ~= "rbxassetid://0"
end

return MonsterAnimationConfig
