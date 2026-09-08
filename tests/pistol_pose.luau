-- Run: luau tests/pistol_pose.luau. Playback lifecycle is simulated.
local Pose = require("../src/client/PistolPose")
local function track(length)
	local t = { Length=length, TimePosition=0, IsPlaying=false, Speed=1, Looped=false, ended=0, plays=0 }
	function t:Play(_, _, speed) self.IsPlaying=true; self.Speed=speed or 1; self.TimePosition=0; self.plays+=1 end
	function t:Stop() self.IsPlaying=false; self.TimePosition=0 end
	function t:AdjustSpeed(speed) self.Speed=speed end
	function t:Advance(dt)
		if not self.IsPlaying or self.Length <= 0 then return end
		self.TimePosition += dt*self.Speed
		if self.TimePosition >= self.Length then self.ended+=1; self:Stop() end
	end
	return t
end
local function step(pose, animation, dt)
	pose:Update(dt) -- PreAnimation precedes the Animator's time advancement.
	animation:Advance(dt)
end

for _, length in { 0.25, 1/3, 2/3, 1 } do
	local t = track(length)
	local p = Pose.new(t)
	p:SetAiming(true)
	for _=1,180 do step(p,t,1/60) end
	assert(t.IsPlaying and t.Speed==0 and math.abs(t.TimePosition-length/2)<1e-6, "Must hold frame 10 irrespective of author FPS")
	assert(t.plays==1 and t.ended==0, "Holding aim must not restart or finish the clip")
	for _=1,5 do
		p:Fire()
		local sawReturn = false
		for _=1,120 do
			step(p,t,1/120)
			if t.TimePosition > length*0.75 then sawReturn=true end
		end
		assert(sawReturn, "Fire must include frames 15–20, not stop at frame 15")
		assert(t.IsPlaying and t.Speed==0 and math.abs(t.TimePosition-length/2)<1e-6, "After recoil return to held aim")
		assert(t.ended==0, "Nonlooped clip must never reach its automatic ending")
	end
	t:Stop() -- An outside interruption must not strand aiming=true/IsPlaying=false.
	step(p,t,1/60)
	assert(t.IsPlaying and math.abs(t.TimePosition-length/2)<1e-6)
	p:SetAiming(false)
	for _=1,60 do step(p,t,1/60) end
	assert(not t.IsPlaying, "Release/unequip/reload must not restart aim")
end

local t=track(0.25)
local p=Pose.new(t)
p:SetAiming(true)
step(p,t,0.8)
assert(t.IsPlaying and t.TimePosition==0.125, "Long frame must not overshoot held pose")
p:Fire(); step(p,t,0.8); step(p,t,1/60)
assert(t.IsPlaying and t.TimePosition==0.125 and t.ended==0, "Long frame during shot must recover without finishing")
p:Fire(); p:SetAiming(false); step(p,t,1)
assert(not t.IsPlaying, "Releasing mid-shot must stop")

t=track(0); p=Pose.new(t); p:SetAiming(true)
for _=1,120 do step(p,t,1/60) end
t.Length=0.5
for _=1,120 do step(p,t,1/60) end
assert(t.IsPlaying and t.TimePosition==0.25, "Delayed loading must still reach held aim")
print("PASS: frame 10 hold, full 10–20 shot/return, varying durations, repeat shots, release, interruptions, stalls and delayed loading")
