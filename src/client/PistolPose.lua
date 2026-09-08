--!strict
-- AimFire termina no frame 20: 0–10 ergue, 10–15 dispara, 15–20 retorna.
-- Length é medido em segundos: não depende do FPS usado pelo autor.
local Pose = {}
Pose.__index = Pose

function Pose.new(track: AnimationTrack)
	track.Looped = false
	return setmetatable({ track = track, phase = "Off", resumeTime = 0 }, Pose)
end

function Pose:SetAiming(active: boolean)
	if active then
		if self.phase ~= "Off" then return end
		self.phase, self.resumeTime = "Raise", 0
		self.track:Play(0.15, 1, 1)
		self.track.TimePosition = 0
	else
		if self.phase == "Off" then return end
		self.phase, self.resumeTime = "Off", 0
		self.track:Stop(0.15)
	end
end

function Pose:Fire()
	if self.phase == "Off" or self.track.Length <= 0 then return end
	self.phase = "Fire"
	self.resumeTime = self.track.Length * (10 / 20)
	if not self.track.IsPlaying then self.track:Play(0.05, 1, 1) end
	self.track.TimePosition = self.resumeTime
	self.track:AdjustSpeed(1)
end

-- Chamado em PreAnimation, ANTES de o Animator avançar a timeline.
function Pose:Update(dt: number)
	if self.phase == "Off" then return end
	local track = self.track
	local length = track.Length
	if length <= 0 then return end -- asset ainda carregando
	local hold = length * (10 / 20)
	local lastPose = length - math.min(0.001, length * 0.001)
	if not track.IsPlaying then
		-- Estado de mira e reprodução não podem ficar dessincronizados.
		track:Play(0.05, 1, 0)
		track.TimePosition = math.clamp(self.resumeTime, 0, lastPose)
	end
	if self.phase == "ReturnToAim" then self.phase = "Hold" end
	if self.phase == "Hold" then
		track:AdjustSpeed(0)
		track.TimePosition = hold
	else
		local boundary = if self.phase == "Raise" then hold else lastPose
		if track.TimePosition + math.max(0, dt) >= boundary then
			-- Não deixar o clipe encerrar automaticamente entre dois frames.
			track:AdjustSpeed(0)
			track.TimePosition = boundary
			self.phase = if self.phase == "Raise" then "Hold" else "ReturnToAim"
		else
			track:AdjustSpeed(1)
		end
	end
	self.resumeTime = track.TimePosition
end

export type Controller = typeof(Pose.new(nil :: any))
return Pose
