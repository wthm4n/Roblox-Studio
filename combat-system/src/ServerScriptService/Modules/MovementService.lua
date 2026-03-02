--[[
	MovementService.lua  (SERVER — ModuleScript)
	Momentum-driven movement: Dash + Slide + WallRun + Energy.
	Place in: ServerScriptService/Modules/MovementService
	CombatService calls: MovementService.init(StunModule, RagdollModule)
]]

local MovementService = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
--  STATE TYPES
-- ══════════════════════════════════════════════════════════════════════════════

local STATE = {
	IDLE = "Idle",
	WALK = "Walk",
	SPRINT = "Sprint",
	AIRBORNE = "Airborne",
	DASHING = "Dashing",
	SLIDING = "Sliding",
	WALLRUN = "WallRun",
}

local _bufferDirs: { [Player]: string } = {}

type PlayerState = {
	State: string,
	Energy: number,
	LastDash: number,
	IFrameUntil: number,
	AirDashUsed: boolean,
	DashBuffer: number,
	SlideActive: boolean,
	SlideTimer: thread?,
	SlideSpeed: number,
	WallActive: boolean,
	WallSide: string,
	WallNormal: Vector3,
	WallStartTime: number,
	WallLastSeen: number,
	AirTime: number,
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

local function _isGrounded(hum: Humanoid): boolean
	local st = hum:GetState()
	return st == Enum.HumanoidStateType.Running
		or st == Enum.HumanoidStateType.RunningNoPhysics
		or st == Enum.HumanoidStateType.Landed
end

local function _flatSpeed(hrp: BasePart): number
	local v = hrp.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- FIX 1: Safe flatten — if looking straight down, LookVector XZ is near zero
-- which caused .Unit to produce NaN and the dash went nowhere.
local function _dashDir(hrp: BasePart, dir: string): Vector3
	local lkRaw = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	local lk = lkRaw.Magnitude > 0.01 and lkRaw.Unit or Vector3.new(0, 0, -1)
	local rtRaw = Vector3.new(hrp.CFrame.RightVector.X, 0, hrp.CFrame.RightVector.Z)
	local rt = rtRaw.Magnitude > 0.01 and rtRaw.Unit or Vector3.new(1, 0, 0)
	if dir == "Forward"  then return lk  end
	if dir == "Backward" then return -lk end
	if dir == "Left"     then return -rt end
	if dir == "Right"    then return rt  end
	return lk
end

local function _removeConstraints(hrp: BasePart, prefix: string)
	for _, c in ipairs(hrp:GetChildren()) do
		if c.Name:sub(1, #prefix) == prefix then
			c:Destroy()
		end
	end
end

local function _applyBurst(hrp: BasePart, vel: Vector3, duration: number, tag: string)
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
		if att and att.Parent then att:Destroy() end
		if lv and lv.Parent then lv:Destroy() end
	end)
end

local function _addEnergy(s: PlayerState, amount: number)
	s.Energy = math.clamp(s.Energy + amount, 0, MC.Max)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  PUBLIC: iFrame check
-- ══════════════════════════════════════════════════════════════════════════════

function MovementService.IsIFramed(player: Player): boolean
	local s = _states[player]
	return s ~= nil and os.clock() < s.IFrameUntil
end

-- ══════════════════════════════════════════════════════════════════════════════
--  SLIDE
-- ══════════════════════════════════════════════════════════════════════════════

local function _endSlide(player: Player, s: PlayerState)
	if not s.SlideActive then return end
	s.SlideActive = false

	if s.SlideTimer then
		task.cancel(s.SlideTimer)
		s.SlideTimer = nil
	end

	local hrp = _getHRP(player)
	if hrp then _removeConstraints(hrp, "Slide") end

	local hum = _getHumanoid(player)
	if hum then
		hum.HipHeight = SC.DefaultHipHeight
		hum.WalkSpeed = (s.State == STATE.SPRINT) and MS.Speed.Sprint or MS.Speed.Walk
	end

	if _remotes.SlideEnd then
		_remotes.SlideEnd:FireAllClients(player)
	end
end

local function _startSlide(player: Player, s: PlayerState)
	if s.SlideActive then return end
	if _stunModule and _stunModule.IsStunned(player) then return end
	if _ragdollModule and _ragdollModule.IsRagdolled(player) then return end

	local hum = _getHumanoid(player)
	local hrp = _getHRP(player)
	if not hum or not hrp or hum.Health <= 0 then return end
	if not _isGrounded(hum) then return end

	local speed = _flatSpeed(hrp)
	if speed < 6 then return end

	local entrySpeed = math.clamp(speed * SC.SpeedMult, SC.SpeedMin, SC.SpeedMax)
	s.SlideActive = true
	s.SlideSpeed = entrySpeed

	hum.HipHeight = SC.CrouchHipHeight
	hum.WalkSpeed = entrySpeed

	local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	_applyBurst(hrp, look * entrySpeed, SC.FrictionInterval * 2, "Slide")

	if _remotes.SlideStart then
		_remotes.SlideStart:FireAllClients(player)
	end

	s.SlideTimer = task.delay(SC.MaxDuration, function()
		local cs = _states[player]
		if cs and cs.SlideActive then _endSlide(player, cs) end
	end)
end

local function _tickSlide(player: Player, s: PlayerState, dt: number)
	if not s.SlideActive then return end

	local hum = _getHumanoid(player)
	local hrp = _getHRP(player)
	if not hum or not hrp then _endSlide(player, s) return end
	if not _isGrounded(hum) then _endSlide(player, s) return end

	s.SlideSpeed = s.SlideSpeed * (SC.FrictionMult ^ (dt / SC.FrictionInterval))
	hum.WalkSpeed = math.max(s.SlideSpeed, 0)

	if s.SlideSpeed <= SC.EndSpeed then _endSlide(player, s) end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  WALL RUN
-- ══════════════════════════════════════════════════════════════════════════════

local function _castWallRays(hrp: BasePart, side: string): (boolean, Vector3)
	local sideDir = (side == "Right") and hrp.CFrame.RightVector or -hrp.CFrame.RightVector
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = hrp.Parent and { hrp.Parent } or {}
	params.FilterType = Enum.RaycastFilterType.Exclude

	local half = (WC.RayCount - 1) * WC.RaySpreadY * 0.5
	for i = 0, WC.RayCount - 1 do
		local origin = hrp.Position + Vector3.new(0, -half + i * WC.RaySpreadY, 0)
		local hit = workspace:Raycast(origin, sideDir * WC.RayLength, params)
		if hit then
			local slope = math.deg(math.asin(math.abs(hit.Normal.Y)))
			if slope <= WC.MaxSlopeAngle then
				return true, hit.Normal
			end
		end
	end
	return false, Vector3.zero
end

local function _endWallRun(player: Player, s: PlayerState)
	if not s.WallActive then return end
	s.WallActive = false

	local hrp = _getHRP(player)
	local hum = _getHumanoid(player)

	if hrp then
		for _, name in ipairs({"WallRunLV", "WallRunVF", "WallRunAtt"}) do
			local obj = hrp:FindFirstChild(name)
			if obj then obj:Destroy() end
		end

		local flatLook = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		if flatLook.Magnitude > 0.01 then
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flatLook.Unit)
		end

		local vel = hrp.AssemblyLinearVelocity
		local flat = Vector3.new(vel.X, 0, vel.Z)
		hrp.AssemblyLinearVelocity = Vector3.new(
			flat.X * 0.85,
			math.max(vel.Y, 0),
			flat.Z * 0.85
		)
	end

	if hum then
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	if _remotes.WallRunEnd then
		_remotes.WallRunEnd:FireAllClients(player)
	end
end

local function _startWallRun(player: Player, s: PlayerState, side: string, normal: Vector3)
	local hrp = _getHRP(player)
	if not hrp then return end

	for _, name in ipairs({"WallRunLV", "WallRunVF", "WallRunAtt"}) do
		local obj = hrp:FindFirstChild(name)
		if obj then obj:Destroy() end
	end

	local now = os.clock()
	s.WallActive = true
	s.WallSide = side
	s.WallNormal = normal
	s.WallStartTime = now
	s.WallLastSeen = now

	local vel = hrp.AssemblyLinearVelocity
	local look = hrp.CFrame.LookVector
	local wallFwd = look - normal * look:Dot(normal)
	wallFwd = wallFwd.Magnitude > 0.01 and wallFwd.Unit or look
	local entrySpd = math.clamp(Vector3.new(vel.X, 0, vel.Z).Magnitude, WC.EntrySpeedMin, WC.EntrySpeedMax)

	local att = Instance.new("Attachment")
	att.Name = "WallRunAtt"
	att.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Name = "WallRunLV"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 5e4
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = wallFwd * entrySpd
	lv.Parent = hrp

	local vf = Instance.new("VectorForce")
	vf.Name = "WallRunVF"
	vf.Attachment0 = att
	vf.Force = Vector3.new(0, workspace.Gravity * (1 - WC.GravityFraction), 0)
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Parent = hrp

	local tiltAngle = math.rad(WC.TiltAngle) * (side == "Right" and 1 or -1)
	hrp.CFrame = hrp.CFrame * CFrame.Angles(0, 0, -tiltAngle)

	if _remotes.WallRunStart then
		_remotes.WallRunStart:FireAllClients(player, side)
	end
end
local function _tickWallRun(player: Player, s: PlayerState, dt: number)
	local hrp = _getHRP(player)
	local hum = _getHumanoid(player)
	if not hrp or not hum then _endWallRun(player, s) return end

	local now = os.clock()

	if _isGrounded(hum)
		or now - s.WallStartTime >= WC.MaxDuration
		or (_stunModule and _stunModule.IsStunned(player))
		or (_ragdollModule and _ragdollModule.IsRagdolled(player))
	then
		_endWallRun(player, s)
		return
	end

	local wallStill, newNormal = _castWallRays(hrp, s.WallSide)
	if wallStill then
		s.WallNormal = newNormal
		s.WallLastSeen = now
	elseif now - s.WallLastSeen > WC.CoyoteTime then
		_endWallRun(player, s)
		return
	end

	local timeOn = now - s.WallStartTime
	local rampFrac = math.min(timeOn / WC.RampTime, 1)
	local rampAdd = rampFrac * WC.RampAdd

	local look = hrp.CFrame.LookVector
	local wallFwd = look - s.WallNormal * look:Dot(s.WallNormal)
	if wallFwd.Magnitude > 0.01 then
		local lv = hrp:FindFirstChild("WallRunLV") :: LinearVelocity?
		if lv then
			local baseSpd = math.clamp(lv.VectorVelocity.Magnitude, WC.EntrySpeedMin, WC.EntrySpeedMax)
			lv.VectorVelocity = wallFwd.Unit * (baseSpd + rampAdd)
		end
	end

	_addEnergy(s, MC.WallRunGain * dt)
end

local function _tryAttachWallRun(player: Player, s: PlayerState)
	if s.WallActive or s.SlideActive then return end

	local hrp = _getHRP(player)
	local hum = _getHumanoid(player)
	if not hrp or not hum or hum.Health <= 0 then return end

	if _isGrounded(hum) then
		s.AirTime = os.clock()
		return
	end

	if os.clock() - s.AirTime < WC.MinAirTime then return end

	local vel = hrp.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local flatLook = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	if flatVel.Magnitude > 1 and flatLook.Magnitude > 0.01 then
		if flatVel.Unit:Dot(flatLook.Unit) < WC.MinForwardDot then return end
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
--  DASH
-- ══════════════════════════════════════════════════════════════════════════════

local function _executeDash(player: Player, s: PlayerState, direction: string)
	local hrp = _getHRP(player)
	local hum = _getHumanoid(player)
	if not hrp or not hum or hum.Health <= 0 then return end

	if s.SlideActive then _endSlide(player, s) end

	-- Always clear any leftover dash constraints before starting a new dash.
	-- Without this, spamming dash stacks LinearVelocity instances and freezes the player.
	_removeConstraints(hrp, "Dash")

	local now = os.clock()
	local speed = DC.BaseSpeed + s.Energy * DC.EnergyScale
	local dir = _dashDir(hrp, direction)

	s.LastDash = now
	s.IFrameUntil = now + DC.IFrameDuration
	s.State = STATE.DASHING

	_addEnergy(s, MC.DashBonus)
	_applyBurst(hrp, dir * speed, DC.Duration, "Dash")

	task.delay(DC.Duration, function()
		local cs = _states[player]
		if cs and cs.State == STATE.DASHING then
			cs.State = STATE.AIRBORNE
		end
	end)

	if _remotes.DashEffect then
		_remotes.DashEffect:FireAllClients(player, direction)
	end
end

local function _handleDashRequest(player: Player, direction: string)
	local s = _states[player]
	if not s then return end
	if _stunModule and _stunModule.IsStunned(player) then return end
	if _ragdollModule and _ragdollModule.IsRagdolled(player) then return end

	local validDirs = { Forward = true, Backward = true, Left = true, Right = true }
	if not validDirs[direction] then return end

	local hum = _getHumanoid(player)
	if not hum or hum.Health <= 0 then return end

	local now = os.clock()
	local grounded = _isGrounded(hum)

	if now - s.LastDash < DC.Cooldown then return end

	if grounded then
		_executeDash(player, s, direction)
	elseif DC.AllowAirDash and not s.AirDashUsed then
		s.AirDashUsed = true
		_executeDash(player, s, direction)
	else
		s.DashBuffer = now
		_bufferDirs[player] = direction
	end
end

local function _handleSlideRequest(player: Player)
	local s = _states[player]
	if not s then return end
	_startSlide(player, s)
end

local function _handleWallJump(player: Player)
	local s = _states[player]
	if not s or not s.WallActive then return end

	local hrp = _getHRP(player)
	if not hrp then return end

	local normal = s.WallNormal
	_endWallRun(player, s)

	hrp.AssemblyLinearVelocity = Vector3.new(normal.X * WC.WallJumpH, WC.WallJumpV, normal.Z * WC.WallJumpH)
	_addEnergy(s, MC.WallJumpBonus)
end

local function _handleDashJumpCancel(player: Player)
	local s = _states[player]
	if not s or s.State ~= STATE.DASHING then return end

	local hrp = _getHRP(player)
	if not hrp then return end

	-- Mark state immediately so a second dash can't start during the gap
	s.State = STATE.AIRBORNE

	-- Destroy ALL dash constraints synchronously right now
	_removeConstraints(hrp, "Dash")

	-- 2-frame gap: frame 1 lets physics clear, frame 2 Roblox applies jump impulse,
	-- then we carry horizontal momentum. Fixes the stuck-in-place spam bug.
	task.delay(0, function()
		task.delay(0, function()
			if not hrp or not hrp.Parent then return end
			local cs = _states[player]
			-- Abort if a brand new dash started in the gap
			if not cs or cs.State == STATE.DASHING then return end
			local vel = hrp.AssemblyLinearVelocity
			local flat = Vector3.new(vel.X, 0, vel.Z)
			if flat.Magnitude > 0.1 then
				hrp.AssemblyLinearVelocity = Vector3.new(
					flat.X * DC.JumpCancelMult,
					vel.Y,  -- preserve jump Y entirely
					flat.Z * DC.JumpCancelMult
				)
			end
		end)
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  FSM TICK + ENERGY
-- ══════════════════════════════════════════════════════════════════════════════

local function _tickFSM(player: Player, s: PlayerState, dt: number)
	local hum = _getHumanoid(player)
	local hrp = _getHRP(player)
	if not hum or not hrp then return end

	if s.WallActive then s.State = STATE.WALLRUN return end
	if s.SlideActive then s.State = STATE.SLIDING return end
	if s.State == STATE.DASHING then return end

	local grounded = _isGrounded(hum)
	local speed = _flatSpeed(hrp)

	if not grounded then
		if s.State ~= STATE.AIRBORNE then s.AirTime = os.clock() end
		s.State = STATE.AIRBORNE
	elseif speed < 1 then
		s.State = STATE.IDLE
	elseif hum.WalkSpeed >= MS.Speed.Sprint * 0.9 then
		s.State = STATE.SPRINT
	else
		s.State = STATE.WALK
	end

	if grounded then
		if s.AirDashUsed then
			s.AirDashUsed = false
			_addEnergy(s, MC.LandBonus)
		end

		local now = os.clock()
		if s.DashBuffer > 0 and now - s.DashBuffer < DC.BufferWindow then
			s.DashBuffer = -math.huge
			local buffDir = _bufferDirs[player] or "Forward"
			_bufferDirs[player] = nil
			task.defer(function()
				local cs = _states[player]
				if cs then _executeDash(player, cs, buffDir) end
			end)
		end
	end
end

local function _tickEnergy(player: Player, s: PlayerState, dt: number)
	if s.WallActive then
		-- ticked in _tickWallRun
	elseif s.State == STATE.SPRINT then
		_addEnergy(s, MC.SprintGain * dt)
	elseif s.State == STATE.AIRBORNE then
		_addEnergy(s, MC.AirGain * dt)
	elseif s.State == STATE.WALK then
		_addEnergy(s, -MC.WalkDecay * dt)
	elseif s.State == STATE.IDLE then
		_addEnergy(s, -MC.IdleDecay * dt)
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  ENERGY SYNC
-- ══════════════════════════════════════════════════════════════════════════════

local _syncAccum = 0
local SYNC_RATE = 0.1

local function _tickSync(dt: number)
	_syncAccum = _syncAccum + dt
	if _syncAccum < SYNC_RATE then return end
	_syncAccum = 0
	if not _remotes.EnergySync then return end
	for player, s in pairs(_states) do
		_remotes.EnergySync:FireClient(player, math.floor(s.Energy))
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  PLAYER LIFECYCLE
-- ══════════════════════════════════════════════════════════════════════════════

local function _setupCharacter(player: Player, char: Model)
	local s = _states[player]
	if not s then return end

	local hrp = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if hrp then
		_removeConstraints(hrp, "Dash")
		_removeConstraints(hrp, "Slide")
		_removeConstraints(hrp, "WallRun")
	end

	s.WallActive = false
	s.SlideActive = false
	s.AirDashUsed = false
	s.AirTime = os.clock()
	s.DashBuffer = -math.huge
	s.Energy = 0
	_bufferDirs[player] = nil

	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.Jumping:Connect(function(active)
		if not active then return end
		local cs = _states[player]
		if not cs then return end
		if cs.WallActive then
			_handleWallJump(player)
		elseif cs.State == STATE.DASHING then
			_handleDashJumpCancel(player)
		end
	end)
end

local function _onPlayerAdded(player: Player)
	_states[player] = _newState()
	player.CharacterAdded:Connect(function(char)
		_setupCharacter(player, char)
	end)
	if player.Character then
		_setupCharacter(player, player.Character)
	end
end

local function _onPlayerRemoving(player: Player)
	local s = _states[player]
	if s then
		_endWallRun(player, s)
		_endSlide(player, s)
	end
	_states[player] = nil
	_bufferDirs[player] = nil
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
	_r(MS.Remotes.RequestSlide).OnServerEvent:Connect(_handleSlideRequest)

	Players.PlayerAdded:Connect(_onPlayerAdded)
	Players.PlayerRemoving:Connect(_onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		_onPlayerAdded(p)
	end

	RunService.Heartbeat:Connect(function(dt)
		for player, s in pairs(_states) do
			if not player.Character then continue end
			_tickFSM(player, s, dt)
			_tickEnergy(player, s, dt)
			if s.WallActive then
				_tickWallRun(player, s, dt)
			else
				_tryAttachWallRun(player, s)
			end
			if s.SlideActive then
				_tickSlide(player, s, dt)
			end
		end
		_tickSync(dt)
	end)

	print("[MovementService] Ready.")
end

return MovementService -- changes made to this file should be replicated to ClientMovementService.lua as well!