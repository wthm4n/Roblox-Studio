--[[
	MovementService.lua  (SERVER — ModuleScript)
	Server authority for Phase 2 movement: Dash + Wall Run.

	Now a ModuleScript so CombatService can require it directly — no _G hacks,
	no race conditions.

	Place in: ServerScriptService/Modules/MovementService  (ModuleScript)

	CombatService calls:
		local MovementService = require(Modules:WaitForChild("MovementService"))
		MovementService.init(StunModule, RagdollModule)

	Then in DamageModule:Apply(), gate with:
		if MovementService.IsIFramed(victim) then return false end
]]

local MovementService = {}

-- ── Services ──────────────────────────────────────────────────────────────────
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── Settings ──────────────────────────────────────────────────────────────────
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MovementSettings = require(Shared:WaitForChild("MovementSettings"))
local DC = MovementSettings.Dash
local WC = MovementSettings.WallRun

-- ── Lazy deps (set via init) ──────────────────────────────────────────────────
local _stunModule = nil
local _ragdollModule = nil
local _remotes: { [string]: RemoteEvent } = {}
local _initialized = false

-- ══════════════════════════════════════════════════════════════════════════════
--  PER-PLAYER STATE
-- ══════════════════════════════════════════════════════════════════════════════

type DashState = {
	LastDash: number,
	IsDashing: boolean,
	IFrameUntil: number,
}

type WallRunState = {
	Active: boolean,
	Side: string,
	WallNormal: Vector3,
	StartTime: number,
	AirTime: number,
}

type PlayerMovState = {
	Dash: DashState,
	WallRun: WallRunState,
}

local _states: { [Player]: PlayerMovState } = {}

local function _newState(): PlayerMovState
	return {
		Dash = {
			LastDash = -math.huge,
			IsDashing = false,
			IFrameUntil = -math.huge,
		},
		WallRun = {
			Active = false,
			Side = "",
			WallNormal = Vector3.zero,
			StartTime = 0,
			AirTime = 0,
		},
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
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Running
		or state == Enum.HumanoidStateType.RunningNoPhysics
		or state == Enum.HumanoidStateType.Landed
end

-- ══════════════════════════════════════════════════════════════════════════════
--  PUBLIC: iFrame check (used by DamageModule)
-- ══════════════════════════════════════════════════════════════════════════════

function MovementService.IsIFramed(player: Player): boolean
	local s = _states[player]
	return s ~= nil and os.clock() < s.Dash.IFrameUntil
end

-- ══════════════════════════════════════════════════════════════════════════════
--  DASH SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════

local function _dashVector(hrp: BasePart, direction: string): Vector3
	local look = hrp.CFrame.LookVector
	local right = hrp.CFrame.RightVector
	local flatLook = Vector3.new(look.X, 0, look.Z).Unit
	local flatRight = Vector3.new(right.X, 0, right.Z).Unit

	if direction == "Forward" then
		return flatLook
	end
	if direction == "Backward" then
		return -flatLook
	end
	if direction == "Left" then
		return -flatRight
	end
	if direction == "Right" then
		return flatRight
	end
	return flatLook
end

local function _applyDashVelocity(hrp: BasePart, direction: Vector3, speed: number, duration: number)
	local att = Instance.new("Attachment")
	att.Name = "DashAttachment"
	att.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DashVelocity"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e5
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = direction * speed
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

local function _handleDashRequest(player: Player, direction: string)
	local s = _states[player]
	if not s then
		return
	end

	-- Gate checks
	if _stunModule and _stunModule.IsStunned(player) then
		return
	end
	if _ragdollModule and _ragdollModule.IsRagdolled(player) then
		return
	end
	if s.WallRun.Active then
		return
	end

	local now = os.clock()
	if now - s.Dash.LastDash < DC.Cooldown then
		return
	end

	local humanoid = _getHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if not _isGrounded(humanoid) then
		return
	end

	local validDirs = { Forward = true, Backward = true, Left = true, Right = true }
	if not validDirs[direction] then
		return
	end

	local hrp = _getHRP(player)
	if not hrp then
		return
	end

	-- Commit
	s.Dash.LastDash = now
	s.Dash.IsDashing = true
	s.Dash.IFrameUntil = now + DC.IFrameDuration

	_applyDashVelocity(hrp, _dashVector(hrp, direction), DC.Speed, DC.Duration)

	task.delay(DC.Duration, function()
		if _states[player] then
			_states[player].Dash.IsDashing = false
		end
	end)

	if _remotes.DashEffect then
		_remotes.DashEffect:FireAllClients(player, direction)
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  WALL RUN SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════

local function _castWallRays(hrp: BasePart, side: string): (boolean, Vector3, BasePart?)
	local right = hrp.CFrame.RightVector
	local sideDir = (side == "Right") and right or -right
	local origin = hrp.Position

	local params = RaycastParams.new()
	local char = hrp.Parent
	params.FilterDescendantsInstances = char and { char } or {}
	params.FilterType = Enum.RaycastFilterType.Exclude

	local halfSpread = (WC.RayCount - 1) * WC.RaySpreadY * 0.5
	for i = 0, WC.RayCount - 1 do
		local yOffset = -halfSpread + i * WC.RaySpreadY
		local result = workspace:Raycast(origin + Vector3.new(0, yOffset, 0), sideDir * WC.RayLength, params)
		if result then
			local slopeAngle = math.deg(math.asin(math.abs(result.Normal.Y)))
			if slopeAngle <= WC.MaxSlopeAngle then
				return true, result.Normal, result.Instance
			end
		end
	end
	return false, Vector3.zero, nil
end

local function _stopWallRunConstraints(hrp: BasePart?)
	if not hrp then
		return
	end
	for _, child in ipairs(hrp:GetChildren()) do
		if child.Name == "WallRunAttachment" or child.Name == "WallRunVelocity" or child.Name == "WallRunGrav" then
			child:Destroy()
		end
	end
end

local function _startWallRunConstraints(hrp: BasePart, wallNormal: Vector3)
	local look = hrp.CFrame.LookVector
	local wallFwd = (look - wallNormal * look:Dot(wallNormal))
	if wallFwd.Magnitude < 0.01 then
		wallFwd = look
	end
	wallFwd = wallFwd.Unit

	local velocity = wallFwd * WC.ForwardSpeed -- flat forward only; gravity cancelled below

	local att = Instance.new("Attachment")
	att.Name = "WallRunAttachment"
	att.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Name = "WallRunVelocity"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 4e4
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = velocity
	lv.Parent = hrp

	-- Cancel most of gravity
	local vf = Instance.new("VectorForce")
	vf.Name = "WallRunGrav"
	vf.Attachment0 = att
	vf.Force = Vector3.new(0, workspace.Gravity, 0) -- full gravity cancel = flat wall run
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Parent = hrp
end

local function _untilt(hrp: BasePart)
	local pos = hrp.Position
	local lookH = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	if lookH.Magnitude < 0.01 then
		return
	end
	hrp.CFrame = CFrame.lookAt(pos, pos + lookH.Unit)
end

local function _endWallRun(player: Player)
	local s = _states[player]
	if not s or not s.WallRun.Active then
		return
	end
	s.WallRun.Active = false

	local hrp = _getHRP(player)
	_stopWallRunConstraints(hrp)
	if hrp then
		_untilt(hrp)
	end

	if _remotes.WallRunEnd then
		_remotes.WallRunEnd:FireAllClients(player)
	end
end

local function _tryAttachWallRun(player: Player, s: PlayerMovState)
	if s.WallRun.Active or s.Dash.IsDashing then
		return
	end

	local hrp = _getHRP(player)
	local humanoid = _getHumanoid(player)
	if not hrp or not humanoid or humanoid.Health <= 0 then
		return
	end

	if _isGrounded(humanoid) then
		s.WallRun.AirTime = os.clock()
		return
	end

	if os.clock() - s.WallRun.AirTime < WC.MinAirTime then
		return
	end

	-- Must be moving forward
	local vel = hrp.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local flatLook = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	if flatLook.Magnitude > 0.01 and flatVel.Magnitude > 0.5 then
		if flatVel.Unit:Dot(flatLook.Unit) < WC.MinForwardDot then
			return
		end
	end

	for _, side in ipairs({ "Left", "Right" }) do
		local hit, normal = _castWallRays(hrp, side)
		if hit then
			s.WallRun.Active = true
			s.WallRun.Side = side
			s.WallRun.WallNormal = normal
			s.WallRun.StartTime = os.clock()

			_startWallRunConstraints(hrp, normal)

			-- Tilt
			local angle = math.rad(WC.TiltAngle) * (side == "Right" and 1 or -1)
			hrp.CFrame = hrp.CFrame * CFrame.Angles(0, 0, -angle)

			if _remotes.WallRunStart then
				_remotes.WallRunStart:FireAllClients(player, side)
			end
			return
		end
	end
end

local function _tickWallRun(player: Player, s: PlayerMovState)
	if not s.WallRun.Active then
		return
	end

	local hrp = _getHRP(player)
	local humanoid = _getHumanoid(player)
	if not hrp or not humanoid then
		_endWallRun(player)
		return
	end

	if
		_isGrounded(humanoid)
		or os.clock() - s.WallRun.StartTime >= WC.MaxDuration
		or (_stunModule and _stunModule.IsStunned(player))
		or (_ragdollModule and _ragdollModule.IsRagdolled(player))
	then
		_endWallRun(player)
		return
	end

	-- Wall gone?
	local wallStill = _castWallRays(hrp, s.WallRun.Side)
	if not wallStill then
		_endWallRun(player)
		return
	end

	-- Update velocity direction each tick (player may be turning)
	local look = hrp.CFrame.LookVector
	local normal = s.WallRun.WallNormal
	local wallFwd = look - normal * look:Dot(normal)
	if wallFwd.Magnitude > 0.01 then
		local lv = hrp:FindFirstChild("WallRunVelocity") :: LinearVelocity?
		if lv then
			lv.VectorVelocity = wallFwd.Unit * WC.ForwardSpeed + Vector3.new(0, WC.UpForce, 0)
		end
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
			s.WallRun.Active = false
			s.WallRun.AirTime = os.clock()
		end
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		if hrp then
			_stopWallRunConstraints(hrp :: BasePart)
		end
	end)
end

local function _onPlayerRemoving(player: Player)
	_endWallRun(player)
	_states[player] = nil
end

-- ══════════════════════════════════════════════════════════════════════════════
--  MODULE INIT  (called by CombatService after StunModule + RagdollModule init)
-- ══════════════════════════════════════════════════════════════════════════════

function MovementService.init(stunModule, ragdollModule)
	assert(not _initialized, "MovementService.init called twice!")
	_initialized = true
	_stunModule = stunModule
	_ragdollModule = ragdollModule

	-- Wire up remotes
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local function _r(name)
		return Remotes:WaitForChild(name) :: RemoteEvent
	end

	_remotes.DashEffect = _r(MovementSettings.Remotes.DashEffect)
	_remotes.WallRunStart = _r(MovementSettings.Remotes.WallRunStart)
	_remotes.WallRunEnd = _r(MovementSettings.Remotes.WallRunEnd)

	local RE_RequestDash = _r(MovementSettings.Remotes.RequestDash)
	RE_RequestDash.OnServerEvent:Connect(_handleDashRequest)

	-- Player lifecycle
	Players.PlayerAdded:Connect(_onPlayerAdded)
	Players.PlayerRemoving:Connect(_onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		_onPlayerAdded(p)
	end

	-- Physics tick
	RunService.Heartbeat:Connect(function()
		for player, s in pairs(_states) do
			if not player.Character then
				continue
			end
			if s.WallRun.Active then
				_tickWallRun(player, s)
			else
				_tryAttachWallRun(player, s)
			end
		end
	end)

	print("[MovementService] Initialized.")
end

return MovementService
