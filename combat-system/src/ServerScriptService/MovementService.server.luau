--[[
	MovementService.lua  (SERVER — ModuleScript)
	Titanfall-tier momentum movement: Dash + Slide + WallRun + Energy system.

	Architecture:
	  • One PlayerState per player with full movement data
	  • Energy (0-100) accumulates from active movement, scales abilities
	  • Dash: speed = base + energy*scale, air dash allowed, jump-cancel, buffered input
	  • Slide: momentum-driven speed, exponential friction decay
	  • WallRun: velocity-projected entry speed, ramp acceleration, partial gravity
	  • All states are additive — dash→wallrun, slide→dash, etc. are all valid

	Place in: ServerScriptService/Modules/MovementService  (ModuleScript)
	CombatService calls: MovementService.init(StunModule, RagdollModule)
]]

local MovementService = {}

-- ── Services ──────────────────────────────────────────────────────────────────
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── Settings ──────────────────────────────────────────────────────────────────
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MS = require(Shared:WaitForChild("MovementSettings"))
local DC = MS.Dash
local WC = MS.WallRun
local SC = MS.Slide
local MC = MS.Momentum

local _stunModule = nil
local _ragdollModule = nil
local _remotes: { [string]: RemoteEvent } = {}
local _initialized = false

-- ══════════════════════════════════════════════════════════════════════════════
--  PLAYER STATE
-- ══════════════════════════════════════════════════════════════════════════════

-- Movement FSM states
local STATE = {
	IDLE = "Idle",
	WALK = "Walk",
	SPRINT = "Sprint",
	AIRBORNE = "Airborne",
	DASHING = "Dashing",
	SLIDING = "Sliding",
	WALLRUN = "WallRun",
}

type PlayerState = {
	-- FSM
	State: string,
	-- Energy
	Energy: number,
	-- Dash
	LastDash: number,
	IFrameUntil: number,
	AirDashUsed: boolean,
	DashBuffer: number, -- os.clock() of buffered Q press (pre-land)
	-- Slide
	SlideActive: boolean,
	SlideTimer: thread?,
	SlideSpeed: number,
	-- Wall run
	WallActive: boolean,
	WallSide: string,
	WallNormal: Vector3,
	WallStartTime: number,
	WallLastSeen: number, -- os.clock() of last successful wall ray (coyote)
	-- Timing
	AirTime: number, -- os.clock() when last left ground
	LastGrounded: number, -- os.clock() of last ground contact
	LastYVel: number, -- previous frame Y velocity (landing impact)
}

local _states: { [Player]: PlayerState } = {}

local function _newState(): PlayerState
	return {
		State = STATE.IDLE,
		Energy = 0,
		LastDash = -math.huge,
		IFrameUntil = -math.huge,
		AirDashUsed = false,
		DashBuffer = -math.huge,
		SlideActive = false,
		SlideTimer = nil,
		SlideSpeed = 0,
		WallActive = false,
		WallSide = "",
		WallNormal = Vector3.zero,
		WallStartTime = 0,
		WallLastSeen = -math.huge,
		AirTime = 0,
		LastGrounded = 0,
		LastYVel = 0,
	}
end

-- ══════════════════════════════════════════════════════════════════════════════
--  HELPERS
-- ══════════════════════════════════════════════════════════════════════════════

local function _getHRP(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function _getHumanoid(player: Player): Humanoid?
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

local function _isGrounded(humanoid: Humanoid): boolean
	local st = humanoid:GetState()
	return st == Enum.HumanoidStateType.Running
		or st == Enum.HumanoidStateType.RunningNoPhysics
		or st == Enum.HumanoidStateType.Landed
end

local function _flatVel(hrp: BasePart): number
	local v = hrp.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- Build dash direction from HRP orientation (camera-relative already, since
-- HRP yaw tracks camera yaw in default Roblox setup)
local function _dashDir(hrp: BasePart, direction: string): Vector3
	local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	local right = Vector3.new(hrp.CFrame.RightVector.X, 0, hrp.CFrame.RightVector.Z).Unit
	if direction == "Forward" then
		return look
	end
	if direction == "Backward" then
		return -look
	end
	if direction == "Left" then
		return -right
	end
	if direction == "Right" then
		return right
	end
	return look
end

-- Remove a named constraint set from HRP
local function _removeConstraints(hrp: BasePart, prefix: string)
	for _, c in ipairs(hrp:GetChildren()) do
		if c.Name:sub(1, #prefix) == prefix then
			c:Destroy()
		end
	end
end

-- Apply a LinearVelocity burst for `duration` seconds then destroy it
local function _applyLinearBurst(hrp: BasePart, vel: Vector3, duration: number, tag: string)
	-- Clean any existing burst of same tag
	_removeConstraints(hrp, tag)

	local att = Instance.new("Attachment")
	att.Name = tag .. "Att"
	att.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Name = tag .. "LV"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e5
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = vel
	lv.Parent = hrp

	task.delay(duration, function()
		if att and att.Parent then
			att:Destroy()
		end
		if lv and lv.Parent then
			lv:Destroy()
		end
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  PUBLIC: iFrame check
-- ══════════════════════════════════════════════════════════════════════════════

function MovementService.IsIFramed(player: Player): boolean
	local s = _states[player]
	return s ~= nil and os.clock() < s.IFrameUntil
end

-- ══════════════════════════════════════════════════════════════════════════════
--  ENERGY SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════

local function _addEnergy(s: PlayerState, amount: number)
	s.Energy = math.clamp(s.Energy + amount, MC.Min, MC.Max)
end

local function _tickEnergy(player: Player, s: PlayerState, dt: number)
	if s.WallActive then
		_addEnergy(s, MC.WallRunGain * dt)
	elseif s.State == STATE.SPRINT then
		_addEnergy(s, MC.SprintGain * dt)
	elseif s.State == STATE.AIRBORNE then
		_addEnergy(s, MC.AirGain * dt)
	elseif s.State == STATE.WALK then
		_addEnergy(s, -MC.WalkDecay * dt)
	elseif s.State == STATE.IDLE then
		_addEnergy(s, -MC.IdleDecay * dt)
	end

	-- Sync energy to owning client periodically (not every frame — every ~8 frames)
	-- We do this via a simple modulo on a global counter handled in Heartbeat
end

-- ══════════════════════════════════════════════════════════════════════════════
--  DASH SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════

local function _executeDash(player: Player, s: PlayerState, direction: string)
	local hrp = _getHRP(player)
	local humanoid = _getHumanoid(player)
	if not hrp or not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local dashDir = _dashDir(hrp, direction)
	local speed = DC.BaseSpeed + s.Energy * DC.EnergyScale

	-- Cancel any active slide
	if s.SlideActive then
		_endSlide(player, s)
	end

	s.LastDash = now
	s.IFrameUntil = now + DC.IFrameDuration
	s.State = STATE.DASHING

	-- Instant energy bonus
	_addEnergy(s, MC.DashBonus)

	-- Apply velocity burst
	_applyLinearBurst(hrp, dashDir * speed, DC.Duration, "Dash")

	task.delay(DC.Duration, function()
		local cs = _states[player]
		if cs and cs.State == STATE.DASHING then
			cs.State = STATE.AIRBORNE -- let FSM re-classify next tick
		end
	end)

	if _remotes.DashEffect then
		_remotes.DashEffect:FireAllClients(player, direction)
	end
end

local function _handleDashRequest(player: Player, direction: string)
	local s = _states[player]
	if not s then
		return
	end
	if _stunModule and _stunModule.IsStunned(player) then
		return
	end
	if _ragdollModule and _ragdollModule.IsRagdolled(player) then
		return
	end

	local validDirs = { Forward = true, Backward = true, Left = true, Right = true }
	if not validDirs[direction] then
		return
	end

	local now = os.clock()
	local humanoid = _getHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local grounded = _isGrounded(humanoid)

	-- Cooldown gate
	if now - s.LastDash < DC.Cooldown then
		return
	end

	if grounded then
		-- Normal ground dash — always allowed
		_executeDash(player, s, direction)
	elseif DC.AllowAirDash and not s.AirDashUsed then
		-- Air dash — consume the charge
		s.AirDashUsed = true
		_executeDash(player, s, direction)
	else
		-- Store as buffer so it auto-fires on next ground touch
		s.DashBuffer = now
		-- Also store direction in a way the buffer can use it
		s._bufferDir = direction
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  DASH JUMP CANCEL (Space during dash → convert horiz vel upward)
-- ══════════════════════════════════════════════════════════════════════════════

local function _handleJumpCancel(player: Player)
	local s = _states[player]
	if not s or s.State ~= STATE.DASHING then
		return
	end

	local hrp = _getHRP(player)
	if not hrp then
		return
	end

	-- Kill dash constraint
	_removeConstraints(hrp, "Dash")

	-- Convert current horizontal momentum into upward burst
	local vel = hrp.AssemblyLinearVelocity
	local flatMag = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local upVel = flatMag * DC.JumpCancelMult

	hrp.AssemblyLinearVelocity = Vector3.new(vel.X * 0.4, upVel, vel.Z * 0.4)
	s.State = STATE.AIRBORNE
end

-- ══════════════════════════════════════════════════════════════════════════════
--  SLIDE SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════

-- Forward-declare so _handleSlideRequest can reference it
function _endSlide(player: Player, s: PlayerState)
	if not s.SlideActive then
		return
	end
	s.SlideActive = false
	if s.SlideTimer then
		task.cancel(s.SlideTimer)
		s.SlideTimer = nil
	end

	local hrp = _getHRP(player)
	if hrp then
		_removeConstraints(hrp, "Slide")
	end

	local humanoid = _getHumanoid(player)
	if humanoid then
		humanoid.HipHeight = SC.DefaultHipHeight
		-- Restore speed based on current FSM state
		local spd = (s.State == STATE.SPRINT) and MS.Speed.Sprint or MS.Speed.Walk
		humanoid.WalkSpeed = spd
	end

	if _remotes.SlideEnd then
		_remotes.SlideEnd:FireAllClients(player)
	end
end

local function _handleSlideRequest(player: Player)
	local s = _states[player]
	if not s or s.SlideActive then
		return
	end
	if _stunModule and _stunModule.IsStunned(player) then
		return
	end
	if _ragdollModule and _ragdollModule.IsRagdolled(player) then
		return
	end

	local humanoid = _getHumanoid(player)
	local hrp = _getHRP(player)
	if not humanoid or not hrp or humanoid.Health <= 0 then
		return
	end
	if not _isGrounded(humanoid) then
		return
	end

	-- Need to be moving to slide
	local currentFlat = _flatVel(hrp)
	if currentFlat < 6 then
		return
	end

	-- Entry speed: current velocity * mult, clamped
	local entrySpeed = math.clamp(currentFlat * SC.SpeedMult, SC.SpeedMin, SC.SpeedMax)
	s.SlideSpeed = entrySpeed
	s.SlideActive = true

	-- Crouch
	humanoid.HipHeight = SC.CrouchHipHeight
	humanoid.WalkSpeed = entrySpeed

	-- Drive initial momentum in current facing direction
	local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	_applyLinearBurst(hrp, look * entrySpeed, SC.FrictionInterval * 1.5, "Slide")

	-- Fire event to clients for animation
	if _remotes.SlideStart then
		_remotes.SlideStart:FireAllClients(player)
	end

	-- Max duration guard
	local slideStartTime = os.clock()
	s.SlideTimer = task.delay(SC.MaxDuration, function()
		local cs = _states[player]
		if cs and cs.SlideActive then
			_endSlide(player, cs)
		end
	end)
end

-- Friction tick (called from Heartbeat, not task.delay loop)
local function _tickSlide(player: Player, s: PlayerState, dt: number)
	if not s.SlideActive then
		return
	end

	local hrp = _getHRP(player)
	local humanoid = _getHumanoid(player)
	if not hrp or not humanoid then
		_endSlide(player, s)
		return
	end

	-- Auto-end if not grounded anymore
	if not _isGrounded(humanoid) then
		_endSlide(player, s)
		return
	end

	-- Exponential friction: reduce speed each tick
	s.SlideSpeed = s.SlideSpeed * (SC.FrictionMult ^ (dt / SC.FrictionInterval))
	humanoid.WalkSpeed = math.max(s.SlideSpeed, 0)

	if s.SlideSpeed <= SC.EndSpeed then
		_endSlide(player, s)
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  WALL RUN SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════

local function _castWallRays(hrp: BasePart, side: string): (boolean, Vector3)
	local right = hrp.CFrame.RightVector
	local sideDir = (side == "Right") and right or -right
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { hrp.Parent }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local half = (WC.RayCount - 1) * WC.RaySpreadY * 0.5
	for i = 0, WC.RayCount - 1 do
		local origin = hrp.Position + Vector3.new(0, -half + i * WC.RaySpreadY, 0)
		local result = workspace:Raycast(origin, sideDir * WC.RayLength, params)
		if result then
			local slope = math.deg(math.asin(math.abs(result.Normal.Y)))
			if slope <= WC.MaxSlopeAngle then
				return true, result.Normal
			end
		end
	end
	return false, Vector3.zero
end

local function _startWallRun(player: Player, s: PlayerState, side: string, normal: Vector3)
	local hrp = _getHRP(player)
	if not hrp then
		return
	end

	-- Remove any stale constraints
	_removeConstraints(hrp, "WallRun")

	local now = os.clock()
	s.WallActive = true
	s.WallSide = side
	s.WallNormal = normal
	s.WallStartTime = now
	s.WallLastSeen = now

	-- Entry speed: current velocity projected onto wall plane, clamped
	local vel = hrp.AssemblyLinearVelocity
	local look = hrp.CFrame.LookVector
	local wallFwd = (look - normal * look:Dot(normal))
	wallFwd = wallFwd.Magnitude > 0.01 and wallFwd.Unit or look.Unit
	local projSpeed =
		math.clamp(math.abs(Vector3.new(vel.X, 0, vel.Z):Dot(wallFwd)), WC.EntrySpeedMin, WC.EntrySpeedMax)

	-- Create attachment
	local att = Instance.new("Attachment")
	att.Name = "WallRunAtt"
	att.Parent = hrp

	-- Forward velocity constraint (updated each tick for turning)
	local lv = Instance.new("LinearVelocity")
	lv.Name = "WallRunLV"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 5e4
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = wallFwd * projSpeed
	lv.Parent = hrp

	-- Partial gravity cancel: let player drift down naturally (WC.GravityFraction of gravity remains)
	local gravCancel = workspace.Gravity * (1 - WC.GravityFraction)
	local vf = Instance.new("VectorForce")
	vf.Name = "WallRunVF"
	vf.Attachment0 = att
	vf.Force = Vector3.new(0, gravCancel, 0)
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Parent = hrp

	-- Body tilt
	local angle = math.rad(WC.TiltAngle) * (side == "Right" and 1 or -1)
	hrp.CFrame = hrp.CFrame * CFrame.Angles(0, 0, -angle)

	if _remotes.WallRunStart then
		_remotes.WallRunStart:FireAllClients(player, side)
	end
end

local function _endWallRun(player: Player, s: PlayerState)
	if not s.WallActive then
		return
	end
	s.WallActive = false

	local hrp = _getHRP(player)
	if hrp then
		_removeConstraints(hrp, "WallRun")
		-- Untilt
		local pos = hrp.Position
		local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		if look.Magnitude > 0.01 then
			hrp.CFrame = CFrame.lookAt(pos, pos + look.Unit)
		end
	end

	if _remotes.WallRunEnd then
		_remotes.WallRunEnd:FireAllClients(player)
	end
end

local function _handleWallJump(player: Player)
	local s = _states[player]
	if not s or not s.WallActive then
		return
	end

	local hrp = _getHRP(player)
	if not hrp then
		return
	end

	local normal = s.WallNormal
	_endWallRun(player, s)

	-- Jump away from wall with horizontal + vertical force
	local jumpVel = Vector3.new(normal.X * WC.WallJumpH, WC.WallJumpV, normal.Z * WC.WallJumpH)
	hrp.AssemblyLinearVelocity = jumpVel
	_addEnergy(s, MC.WallJumpBonus)
end

local function _tickWallRun(player: Player, s: PlayerState, dt: number)
	if not s.WallActive then
		return
	end

	local hrp = _getHRP(player)
	local humanoid = _getHumanoid(player)
	if not hrp or not humanoid then
		_endWallRun(player, s)
		return
	end

	local now = os.clock()

	-- Exit conditions
	if
		_isGrounded(humanoid)
		or now - s.WallStartTime >= WC.MaxDuration
		or (_stunModule and _stunModule.IsStunned(player))
		or (_ragdollModule and _ragdollModule.IsRagdolled(player))
	then
		_endWallRun(player, s)
		return
	end

	-- Re-cast wall rays to confirm wall still present (coyote time)
	local wallStill, newNormal = _castWallRays(hrp, s.WallSide)
	if wallStill then
		s.WallNormal = newNormal
		s.WallLastSeen = now
	elseif now - s.WallLastSeen > WC.CoyoteTime then
		-- Wall gone past coyote window
		_endWallRun(player, s)
		return
	end

	-- Acceleration ramp: speed increases over WC.RampTime seconds
	local timeOnWall = now - s.WallStartTime
	local rampFrac = math.min(timeOnWall / WC.RampTime, 1)
	local rampBonus = rampFrac * WC.RampAdd

	-- Re-project look onto wall plane each tick so turning feels responsive
	local look = hrp.CFrame.LookVector
	local normal = s.WallNormal
	local wallFwd = look - normal * look:Dot(normal)
	if wallFwd.Magnitude > 0.01 then
		wallFwd = wallFwd.Unit
		local lv = hrp:FindFirstChild("WallRunLV") :: LinearVelocity?
		if lv then
			-- Base speed = entry speed (stored implicitly via initial set),
			-- we re-derive it from current constraint + ramp
			local baseSpeed = lv.VectorVelocity.Magnitude -- last set value
			baseSpeed = math.clamp(baseSpeed, WC.EntrySpeedMin, WC.EntrySpeedMax + WC.RampAdd)
			lv.VectorVelocity = wallFwd * (baseSpeed + rampBonus)
		end
	end
end

local function _tryAttachWallRun(player: Player, s: PlayerState, dt: number)
	if s.WallActive or s.SlideActive then
		return
	end
	-- Allow dash→wallrun transition (State == DASHING is OK)

	local hrp = _getHRP(player)
	local humanoid = _getHumanoid(player)
	if not hrp or not humanoid or humanoid.Health <= 0 then
		return
	end

	if _isGrounded(humanoid) then
		s.AirTime = os.clock()
		return
	end

	if os.clock() - s.AirTime < WC.MinAirTime then
		return
	end

	-- Moving forward check
	local vel = hrp.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local flatLook = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	if flatVel.Magnitude > 1 and flatLook.Magnitude > 0.01 then
		if flatVel.Unit:Dot(flatLook.Unit) < WC.MinForwardDot then
			return
		end
	end

	for _, side in ipairs({ "Left", "Right" }) do
		local hit, normal = _castWallRays(hrp, side)
		if hit then
			_startWallRun(player, s, side, normal)
			return
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  FSM STATE CLASSIFICATION  (runs each Heartbeat, drives energy)
-- ══════════════════════════════════════════════════════════════════════════════

local function _classifyState(player: Player, s: PlayerState, dt: number)
	local humanoid = _getHumanoid(player)
	local hrp = _getHRP(player)
	if not humanoid or not hrp then
		return
	end

	if s.WallActive then
		s.State = STATE.WALLRUN
		return
	end
	if s.SlideActive then
		s.State = STATE.SLIDING
		return
	end
	if s.State == STATE.DASHING then
		return -- dash manages its own exit
	end

	local grounded = _isGrounded(humanoid)
	local speed = _flatVel(hrp)

	if not grounded then
		if s.State ~= STATE.AIRBORNE then
			s.AirTime = os.clock()
		end
		s.State = STATE.AIRBORNE
	elseif speed < 1 then
		s.State = STATE.IDLE
	elseif humanoid.WalkSpeed >= MS.Speed.Sprint * 0.9 then
		s.State = STATE.SPRINT
	else
		s.State = STATE.WALK
	end

	-- Reset air dash on landing
	if grounded and s.State ~= STATE.AIRBORNE then
		local wasAir = s.AirDashUsed
		if wasAir then
			s.AirDashUsed = false
			-- Landing energy bonus
			_addEnergy(s, MC.LandBonus)
		end

		-- Buffered dash: fire automatically if buffer window still valid
		local now = os.clock()
		if s.DashBuffer > 0 and now - s.DashBuffer < DC.BufferWindow then
			s.DashBuffer = -math.huge
			local dir = s._bufferDir or "Forward"
			s._bufferDir = nil
			task.defer(function()
				_executeDash(player, s, dir)
			end)
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  ENERGY SYNC  (fire to client every ~0.1s)
-- ══════════════════════════════════════════════════════════════════════════════

local _syncTimer = 0
local SYNC_INTERVAL = 0.1

local function _syncEnergy(dt: number)
	_syncTimer = _syncTimer + dt
	if _syncTimer < SYNC_INTERVAL then
		return
	end
	_syncTimer = 0

	if not _remotes.EnergySync then
		return
	end
	for player, s in pairs(_states) do
		_remotes.EnergySync:FireClient(player, s.Energy)
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  PLAYER LIFECYCLE
-- ══════════════════════════════════════════════════════════════════════════════

local function _onPlayerAdded(player: Player)
	_states[player] = _newState()
	player.CharacterAdded:Connect(function(char)
		local s = _states[player]
		if s then
			-- Reset movement state on respawn
			_endWallRun(player, s)
			_endSlide(player, s)
			s.AirDashUsed = false
			s.AirTime = os.clock()
			s.Energy = 0
		end
		local hrp = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if hrp then
			_removeConstraints(hrp, "Dash")
			_removeConstraints(hrp, "Slide")
			_removeConstraints(hrp, "WallRun")
		end
	end)
end

local function _onPlayerRemoving(player: Player)
	local s = _states[player]
	if s then
		_endWallRun(player, s)
		_endSlide(player, s)
	end
	_states[player] = nil
end

-- ══════════════════════════════════════════════════════════════════════════════
--  INIT
-- ══════════════════════════════════════════════════════════════════════════════

function MovementService.init(stunModule, ragdollModule)
	assert(not _initialized, "MovementService.init called twice!")
	_initialized = true
	_stunModule = stunModule
	_ragdollModule = ragdollModule

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local function _r(n)
		return Remotes:WaitForChild(n) :: RemoteEvent
	end

	_remotes.DashEffect = _r(MS.Remotes.DashEffect)
	_remotes.SlideStart = _r(MS.Remotes.SlideStart)
	_remotes.SlideEnd = _r(MS.Remotes.SlideEnd)
	_remotes.WallRunStart = _r(MS.Remotes.WallRunStart)
	_remotes.WallRunEnd = _r(MS.Remotes.WallRunEnd)
	_remotes.EnergySync = _r(MS.Remotes.EnergySync)

	_r(MS.Remotes.RequestDash).OnServerEvent:Connect(_handleDashRequest)
	_r(MS.Remotes.RequestSlide).OnServerEvent:Connect(function(p)
		_handleSlideRequest(p)
	end)

	-- Wall jump: client fires jump while wall running → server handles force
	-- We detect this via Humanoid jump state change on server
	Players.PlayerAdded:Connect(function(player)
		_onPlayerAdded(player)
		player.CharacterAdded:Connect(function(char)
			local humanoid = char:WaitForChild("Humanoid") :: Humanoid
			humanoid.Jumping:Connect(function(active)
				if not active then
					return
				end
				local s = _states[player]
				if s and s.WallActive then
					_handleWallJump(player)
				elseif s and s.State == STATE.DASHING then
					_handleJumpCancel(player)
				end
			end)
		end)
	end)

	Players.PlayerRemoving:Connect(_onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		_onPlayerAdded(p)
	end

	-- Main tick
	RunService.Heartbeat:Connect(function(dt)
		for player, s in pairs(_states) do
			if not player.Character then
				continue
			end
			_classifyState(player, s, dt)
			_tickEnergy(player, s, dt)
			if s.WallActive then
				_tickWallRun(player, s, dt)
			else
				_tryAttachWallRun(player, s, dt)
			end
			if s.SlideActive then
				_tickSlide(player, s, dt)
			end
		end
		_syncEnergy(dt)
	end)

	print("[MovementService] Momentum system initialized.")
end

return MovementService
