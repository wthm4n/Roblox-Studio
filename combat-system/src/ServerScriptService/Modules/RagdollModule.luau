--[[
	RagdollModule.lua  (SERVER)
	Converts a character into a physics ragdoll on hit, launches them like they
	got actually picked up and thrown — full body blast + tumble spin.

	HOW THE LAUNCH WORKS:
	  1. Ragdoll activates (motors off, BallSockets on, Humanoid → Physics)
	  2. SetNetworkOwner(nil) so server fully owns physics
	  3. Lift HRP 0.4 studs off ground to break floor friction
	  4. task.defer waits ONE physics frame for the engine to fully detach motors
	  5. Every BasePart in the character gets a DIRECT velocity set (not impulse)
	     → This bypasses mass entirely — all limbs fly together
	  6. HRP gets an extra upward pop for arc height
	  7. A random angular velocity is applied to HRP for tumble spin
	  8. A secondary task.delay(0.05) re-applies velocity in case the engine
	     clamped it on the first frame (happens sometimes with Humanoid states)

	Place in: ServerScriptService/Modules/RagdollModule
]]

local RagdollModule = {}
RagdollModule.__index = RagdollModule

-- ── Services ──────────────────────────────────────────────────────────────────
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ── Module state ──────────────────────────────────────────────────────────────
local _remotes: { [string]: RemoteEvent } = {}
local _stunModule = nil

type RagdollState = {
	IsRagdolled: boolean,
	RecoverTimer: thread?,
}
local _states: { [Player]: RagdollState } = {}

-- ── Init ──────────────────────────────────────────────────────────────────────
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

local function _getMotors(char: Model): { Motor6D }
	local motors = {}
	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("Motor6D") then
			table.insert(motors, desc)
		end
	end
	return motors
end

local function _createBallSocket(motor: Motor6D): BallSocketConstraint?
	local p0 = motor.Part0
	local p1 = motor.Part1
	if not p0 or not p1 then
		return nil
	end

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
	bsc.UpperAngle = 45
	bsc.TwistLimitsEnabled = false
	bsc.Parent = p1

	return bsc
end

local function _clearRagdollConstraints(char: Model)
	for _, desc in ipairs(char:GetDescendants()) do
		if desc.Name:sub(1, 7) == "Ragdoll" then
			desc:Destroy()
		end
	end
end

local function _applyRagdoll(char: Model)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	for _, motor in ipairs(_getMotors(char)) do
		motor.Enabled = false
		_createBallSocket(motor)
	end

	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.CanCollide = true
		end
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		(hrp :: BasePart).CanCollide = false
	end
end

local function _removeRagdoll(char: Model)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local hrp: BasePart? = char:FindFirstChild("HumanoidRootPart")

	-- ── Kill all velocity first so nothing is sliding when we reposition ─────
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end

	-- ── Re-enable motors before snapping upright ─────────────────────────────
	for _, motor in ipairs(_getMotors(char)) do
		motor.Enabled = true
	end

	_clearRagdollConstraints(char)

	-- ── Snap HRP upright ─────────────────────────────────────────────────────
	-- The ragdoll leaves the HRP (and whole body) in whatever orientation it
	-- landed in. We reset the HRP rotation to face the same horizontal direction
	-- but perfectly vertical, then lift it so the feet clear the floor.
	if hrp then
		local pos = hrp.Position
		local look = hrp.CFrame.LookVector
		-- Flatten look vector — keep horizontal facing, strip any pitch/roll
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 0.01 then
			flatLook = Vector3.new(0, 0, -1) -- fallback direction
		end
		flatLook = flatLook.Unit

		-- Lift by ~3 studs above current position so feet land on ground cleanly.
		-- The Humanoid will handle settling them down naturally.
		local standPos = Vector3.new(pos.X, pos.Y + 3, pos.Z)
		hrp.CFrame = CFrame.lookAt(standPos, standPos + flatLook)
	end

	-- ── Now restore Humanoid state ────────────────────────────────────────────
	if humanoid then
		humanoid.AutoRotate = true
		-- Running snaps them to a clean upright stance immediately
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
end

--[[
	_blastCharacter(char, launchVel, tumbleSpin)
	Sets velocity directly on EVERY BasePart so the whole body flies as one unit.
	Direct velocity assignment beats ApplyImpulse here because:
	  • No mass math needed — everyone gets the same velocity regardless of limb weight
	  • Guaranteed to override whatever the Humanoid physics engine set last frame
	  • Looks physically correct — limbs don't stretch or separate
]]
local function _blastCharacter(char: Model, launchVel: Vector3, tumbleSpin: Vector3)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = launchVel
			part.AssemblyAngularVelocity = tumbleSpin
		end
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

--[[
	RagdollModule.Apply(victim, attacker, duration, launchForce, launchUp)
	  victim      : Player
	  attacker    : Player  — used to calculate throw direction (away from them)
	  duration    : number  — seconds until auto-recovery
	  launchForce : number  — horizontal speed (studs/s) — how far they travel
	  launchUp    : number  — vertical speed (studs/s) — height of the arc
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

	local victimHRP: BasePart? = char:FindFirstChild("HumanoidRootPart")
	local attackerChar = attacker.Character
	local attackerHRP: BasePart? = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart")
	if not victimHRP then
		return
	end

	-- ── Cancel any existing recovery timer (combo extension) ─────────────────
	if s.RecoverTimer then
		task.cancel(s.RecoverTimer)
		s.RecoverTimer = nil
	end

	-- ── Activate ragdoll physics (only if not already ragdolled) ─────────────
	if not s.IsRagdolled then
		s.IsRagdolled = true
		_applyRagdoll(char)
	end

	-- ── Build launch direction ────────────────────────────────────────────────
	local launchDir: Vector3
	if attackerHRP then
		local raw = victimHRP.Position - attackerHRP.Position
		launchDir = Vector3.new(raw.X, 0, raw.Z)
		if launchDir.Magnitude < 0.1 then
			local look = attackerHRP.CFrame.LookVector
			launchDir = Vector3.new(look.X, 0, look.Z)
		end
		launchDir = launchDir.Unit
	else
		launchDir = victimHRP.CFrame.LookVector * -1 -- fallback: backward
		launchDir = Vector3.new(launchDir.X, 0, launchDir.Z).Unit
	end

	-- ── Final velocity vector: horizontal throw + upward arc ─────────────────
	--   We combine them so the body actually arcs upward and forward, not just
	--   flies straight horizontally. The Y component is what gives the "picked up"
	--   feeling before they crash back down.
	local throwVelocity = Vector3.new(launchDir.X * launchForce, launchUp, launchDir.Z * launchForce)

	-- ── Tumble spin: rotate around the axis perpendicular to throw direction ──
	--   This makes the body visually spin/flip as it flies — not just slide.
	--   Spin axis = cross of launchDir and UP = roughly the "left/right" axis
	--   relative to the throw. Random sign for variation.
	local spinAxis = launchDir:Cross(Vector3.new(0, 1, 0)).Unit
	local spinSign = (math.random() > 0.5) and 1 or -1
	local spinSpeed = math.random(4, 8) -- radians/sec — good visible tumble
	local tumbleSpin = spinAxis * spinSpeed * spinSign

	-- ── Give server full physics ownership ───────────────────────────────────
	victimHRP:SetNetworkOwner(nil)

	-- ── Lift off the ground to break floor friction + contact constraints ─────
	victimHRP.CFrame = victimHRP.CFrame + Vector3.new(0, 0.5, 0)

	-- ── Apply on next physics step (motor detach needs one frame to settle) ───
	task.defer(function()
		-- Check character is still valid
		if not victim.Character or victim.Character ~= char then
			return
		end
		_blastCharacter(char, throwVelocity, tumbleSpin)
	end)

	-- ── Re-apply 1 tick later as insurance (Humanoid sometimes clamps vel) ────
	task.delay(0.05, function()
		if not s.IsRagdolled then
			return
		end
		if not victim.Character or victim.Character ~= char then
			return
		end
		-- Only re-blast if they're suspiciously slow (got clamped)
		local curSpeed = victimHRP.AssemblyLinearVelocity.Magnitude
		if curSpeed < launchForce * 0.5 then
			_blastCharacter(char, throwVelocity, tumbleSpin)
		end
	end)

	-- ── Pin stun for the full ragdoll duration ────────────────────────────────
	if _stunModule then
		_stunModule.Apply(victim, duration)
	end

	-- ── Notify clients → disable Animate on victim ───────────────────────────
	if _remotes.Ragdoll then
		_remotes.Ragdoll:FireAllClients(victim, true)
	end

	-- ── Schedule auto-recovery ────────────────────────────────────────────────
	s.RecoverTimer = task.delay(duration, function()
		s.RecoverTimer = nil
		RagdollModule.Recover(victim)
	end)
end

--[[
	RagdollModule.Recover(victim)
	Force-end ragdoll (death, round end, tech roll).
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

	if _remotes.RagdollEnd then
		_remotes.RagdollEnd:FireAllClients(victim)
	end

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
