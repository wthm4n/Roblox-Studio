--[[
	RagdollModule.lua  (SERVER)
	Converts a character into a physics ragdoll on hit, launches them backward,
	and auto-recovers after a duration.

	HOW IT WORKS:
	  1. On hit: disable the Humanoid's motor joints (R6 or R15) by setting their
	     MaxVelocity to 0, and enable pre-made BallSocketConstraints so the body
	     goes limp under gravity.
	  2. Apply a launch velocity on the HRP in the direction away from the attacker
	     + slight upward arc, so they fly back like they got punched.
	  3. Fire Ragdoll remote → all clients disable their Animate LocalScript on
	     the victim so animations don't fight the physics.
	  4. After the ragdoll duration, re-enable the joints and fire RagdollEnd.
	  5. Stun is tied to ragdoll: while ragdolled, IsStunned always returns true.

	R6 joints affected: Root, Neck, Left Shoulder, Right Shoulder, Left Hip, Right Hip
	R15: every Motor6D found under the character

	Place in: ServerScriptService/Modules/RagdollModule
]]

local RagdollModule = {}
RagdollModule.__index = RagdollModule

-- ── Services ──────────────────────────────────────────────────────────────────
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ── Module state ──────────────────────────────────────────────────────────────
local _remotes: { [string]: RemoteEvent } = {}
local _stunModule = nil -- injected; used to keep stun active during ragdoll

-- Per-player ragdoll state
type RagdollState = {
	IsRagdolled: boolean,
	RecoverTimer: thread?,
}
local _states: { [Player]: RagdollState } = {}

-- ── Init ──────────────────────────────────────────────────────────────────────
--[[
	RagdollModule.init(remotes, stunModule)
	  remotes    : { Ragdoll: RemoteEvent, RagdollEnd: RemoteEvent }
	  stunModule  : StunModule table (for keeping stun locked during ragdoll)
]]
function RagdollModule.init(remotes, stunModule)
	assert(RunService:IsServer(), "RagdollModule.init must run on server!")
	_remotes = remotes
	_stunModule = stunModule

	Players.PlayerAdded:Connect(function(p)
		_states[p] = { IsRagdolled = false, RecoverTimer = nil }
	end)
	Players.PlayerRemoving:Connect(function(p)
		local s = _states[p]
		if s and s.RecoverTimer then
			task.cancel(s.RecoverTimer)
		end
		_states[p] = nil
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		_states[p] = { IsRagdolled = false, RecoverTimer = nil }
	end
end

-- ── Private ───────────────────────────────────────────────────────────────────

-- Collects all Motor6D joints in a character model
local function _getMotors(char: Model): { Motor6D }
	local motors = {}
	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("Motor6D") then
			table.insert(motors, desc)
		end
	end
	return motors
end

-- Creates a BallSocketConstraint between part0 and part1 of a Motor6D.
-- The constraint is parented to part1 so it's cleaned up when the character resets.
local function _createBallSocket(motor: Motor6D): BallSocketConstraint?
	local p0 = motor.Part0
	local p1 = motor.Part1
	if not p0 or not p1 then
		return nil
	end

	-- Attachment at the motor's C0 / C1 offsets
	local att0 = Instance.new("Attachment")
	att0.CFrame = motor.C0
	att0.Name = "RagdollAtt0_" .. motor.Name
	att0.Parent = p0

	local att1 = Instance.new("Attachment")
	att1.CFrame = motor.C1
	att1.Name = "RagdollAtt1_" .. motor.Name
	att1.Parent = p1

	local bsc = Instance.new("BallSocketConstraint")
	bsc.Name = "RagdollBSC_" .. motor.Name
	bsc.Attachment0 = att0
	bsc.Attachment1 = att1
	bsc.LimitsEnabled = true
	bsc.UpperAngle = 45 -- reasonable joint freedom
	bsc.TwistLimitsEnabled = false
	bsc.Parent = p1

	return bsc
end

-- Removes all ragdoll constraints + attachments we created
local function _clearRagdollConstraints(char: Model)
	for _, desc in ipairs(char:GetDescendants()) do
		if desc.Name:sub(1, 7) == "Ragdoll" then
			desc:Destroy()
		end
	end
end

-- Enable ragdoll physics: disable motors, create BallSockets
local function _applyRagdoll(char: Model)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Prevent auto-step-up, which can fight ragdoll physics
		humanoid.AutoRotate = false
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	local motors = _getMotors(char)
	for _, motor in ipairs(motors) do
		-- Disable the motor so the joint goes limp
		motor.Enabled = false
		_createBallSocket(motor)
	end

	-- Make all parts in the character collidable + unanchored so they fall
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.CanCollide = true
		end
	end
	-- HRP stays unanchored but non-collidable (standard Roblox setup)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		(hrp :: BasePart).CanCollide = false
	end
end

-- Recover from ragdoll: re-enable motors, destroy constraints
local function _removeRagdoll(char: Model)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	local motors = _getMotors(char)
	for _, motor in ipairs(motors) do
		motor.Enabled = true
	end

	_clearRagdollConstraints(char)
end

-- ── Public API ────────────────────────────────────────────────────────────────

--[[
	RagdollModule.Apply(victim, attacker, duration, launchForce, launchUp)
	  victim      : Player
	  attacker    : Player  — used to calculate launch direction (away from them)
	  duration    : number  — seconds until auto-recovery
	  launchForce : number  — horizontal studs/s (how far back)
	  launchUp    : number  — vertical studs/s (how high the pop is)

	If victim is already ragdolled, refreshes the timer (keeps them down mid-combo).
]]
function RagdollModule.Apply(victim: Player, attacker: Player, duration: number, launchForce: number, launchUp: number)
	assert(RunService:IsServer())

	local s = _states[victim]
	if not s then
		return
	end

	local char = victim.Character
	if not char then
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local victimHRP = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local attackerHRP = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not victimHRP then
		return
	end

	-- ── Cancel existing recovery timer (refresh on each hit) ─────────────────
	if s.RecoverTimer then
		task.cancel(s.RecoverTimer)
		s.RecoverTimer = nil
	end

	-- ── Apply ragdoll physics if not already ragdolled ────────────────────────
	if not s.IsRagdolled then
		s.IsRagdolled = true
		_applyRagdoll(char)
	end

	-- ── Launch velocity: back + small upward pop → falls to ground ──────────────
	-- Horizontal component sends them 5-10 studs back.
	-- Vertical component gives a short arc (2-3 studs up) so they visibly get
	-- knocked back and crash down rather than just sliding flat.
	if attackerHRP then
		local launchDir = (victimHRP.Position - attackerHRP.Position)
		launchDir = Vector3.new(launchDir.X, 0, launchDir.Z)

		if launchDir.Magnitude < 0.1 then
			local look = attackerHRP.CFrame.LookVector
			launchDir = Vector3.new(look.X, 0, look.Z)
		end

		launchDir = launchDir.Unit

		-- Force server physics control
		victimHRP:SetNetworkOwner(nil)

		-- Small lift to prevent ground friction killing force
		victimHRP.CFrame += Vector3.new(0, 0.25, 0)

		-- Apply on next physics frame
		task.defer(function()
			local mass = victimHRP.AssemblyMass
			local impulse = Vector3.new(launchDir.X * launchForce, launchUp, launchDir.Z * launchForce) * mass

			victimHRP:ApplyImpulse(impulse)
		end)
	end

	-- ── Keep stun pinned for the duration ────────────────────────────────────
	if _stunModule then
		_stunModule.Apply(victim, duration)
	end

	-- ── Notify clients → disable Animate script on victim ────────────────────
	if _remotes.Ragdoll then
		_remotes.Ragdoll:FireAllClients(victim, true)
	end

	-- ── Schedule recovery ─────────────────────────────────────────────────────
	s.RecoverTimer = task.delay(duration, function()
		s.RecoverTimer = nil
		RagdollModule.Recover(victim)
	end)
end

--[[
	RagdollModule.Recover(victim)
	Force-end ragdoll immediately (death, round end, etc).
]]
function RagdollModule.Recover(victim: Player)
	local s = _states[victim]
	if not s or not s.IsRagdolled then
		return
	end

	s.IsRagdolled = false
	if s.RecoverTimer then
		task.cancel(s.RecoverTimer)
		s.RecoverTimer = nil
	end

	local char = victim.Character
	if char then
		_removeRagdoll(char)
	end

	-- Tell clients to re-enable Animate
	if _remotes.RagdollEnd then
		_remotes.RagdollEnd:FireAllClients(victim)
	end

	-- Release stun too (if it hasn't expired naturally)
	if _stunModule then
		_stunModule.Release(victim, "ragdoll_recover")
	end
end

--[[
	RagdollModule.IsRagdolled(player) → boolean
]]
function RagdollModule.IsRagdolled(player: Player): boolean
	local s = _states[player]
	return s ~= nil and s.IsRagdolled
end

return RagdollModule
