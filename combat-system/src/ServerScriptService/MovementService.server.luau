--[[
	MovementService.server.lua  (SERVER)
	Server authority for Phase 2 movement: Dash + Wall Run.

	Responsibilities:
	  • Validate all dash requests (cooldown, grounded, not stunned/ragdolled)
	  • Apply authoritative dash velocity via LinearVelocity
	  • Manage wall run state per-player (detect, activate, tick, detach)
	  • Broadcast state changes to all clients for animation playback

	Place in: ServerScriptService/MovementService  (Script, RunContext = Server)

	Dependencies:
	  • ReplicatedStorage/Shared/MovementSettings
	  • ServerScriptService/Modules/StunModule     (already init'd by CombatService)
	  • ServerScriptService/Modules/RagdollModule  (already init'd by CombatService)
	  • ReplicatedStorage/Remotes/*                (created by MovementRemoteSetup)
]]

-- ── Services ──────────────────────────────────────────────────────────────────
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ── Settings & Modules ────────────────────────────────────────────────────────
local Shared           = ReplicatedStorage:WaitForChild("Shared")
local Modules          = ServerScriptService:WaitForChild("Modules")
local MovementSettings = require(Shared:WaitForChild("MovementSettings"))
local StunModule       = require(Modules:WaitForChild("StunModule"))
local RagdollModule    = require(Modules:WaitForChild("RagdollModule"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local function _remote(name: string): RemoteEvent
	return Remotes:WaitForChild(name) :: RemoteEvent
end

local RE_RequestDash  = _remote(MovementSettings.Remotes.RequestDash)
local RE_DashEffect   = _remote(MovementSettings.Remotes.DashEffect)
local RE_WallRunStart = _remote(MovementSettings.Remotes.WallRunStart)
local RE_WallRunEnd   = _remote(MovementSettings.Remotes.WallRunEnd)

local DC = MovementSettings.Dash
local WC = MovementSettings.WallRun

-- ══════════════════════════════════════════════════════════════════════════════
--  PER-PLAYER STATE
-- ══════════════════════════════════════════════════════════════════════════════

type DashState = {
	LastDash    : number,    -- os.clock()
	IsDashing   : boolean,
	IFrameUntil : number,    -- os.clock() — invincibility window end
}

type WallRunState = {
	Active       : boolean,
	Side         : string,           -- "Left" | "Right"
	WallNormal   : Vector3,
	StartTime    : number,           -- os.clock()
	AirTime      : number,           -- os.clock() when player left ground
	VelConstraint: LinearVelocity?,  -- physics constraint handle
	GravConstraint: VectorForce?,    -- anti-gravity handle
}

type PlayerMovState = {
	Dash    : DashState,
	WallRun : WallRunState,
}

local _states: { [Player]: PlayerMovState } = {}

local function _newState(): PlayerMovState
	return {
		Dash = {
			LastDash    = -math.huge,
			IsDashing   = false,
			IFrameUntil = -math.huge,
		},
		WallRun = {
			Active        = false,
			Side          = "",
			WallNormal    = Vector3.zero,
			StartTime     = 0,
			AirTime       = 0,
			VelConstraint = nil,
			GravConstraint = nil,
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

-- Returns true if player is protected by iFrames (dash invincibility)
function IsIFramed(player: Player): boolean
	local s = _states[player]
	return s ~= nil and os.clock() < s.Dash.IFrameUntil
end

-- ══════════════════════════════════════════════════════════════════════════════
--  DASH SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════

--[[
	Direction string → unit vector in world space based on HRP CFrame.
	"Forward"  = camera forward (HRP LookVector)
	"Backward" = opposite
	"Left/Right" = strafe relative to HRP
]]
local function _dashVector(hrp: BasePart, direction: string): Vector3
	local look  = hrp.CFrame.LookVector
	local right = hrp.CFrame.RightVector
	-- Flatten to XZ so diagonal input doesn't launch them up/down
	local flatLook  = Vector3.new(look.X,  0, look.Z).Unit
	local flatRight = Vector3.new(right.X, 0, right.Z).Unit

	if direction == "Forward"  then return flatLook            end
	if direction == "Backward" then return -flatLook           end
	if direction == "Left"     then return -flatRight          end
	if direction == "Right"    then return  flatRight          end
	return flatLook  -- fallback
end

--[[
	Creates a LinearVelocity to drive the dash, then destroys it after duration.
	Using a constraint is better than setting AssemblyLinearVelocity directly
	because it plays nice with Humanoid physics and naturally fades.
]]
local function _applyDashVelocity(hrp: BasePart, direction: Vector3, speed: number, duration: number)
	-- Attachment at HRP center
	local att = Instance.new("Attachment")
	att.Name   = "DashAttachment"
	att.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Name              = "DashVelocity"
	lv.Attachment0       = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce          = 1e5
	lv.RelativeTo        = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity    = direction * speed
	lv.Parent            = hrp

	-- After dash duration, destroy constraint so normal movement resumes
	task.delay(duration, function()
		if att and att.Parent then att:Destroy() end
		if lv  and lv.Parent  then lv:Destroy()  end
	end)
end

-- Main dash handler — called from RE_RequestDash
local function _handleDashRequest(player: Player, direction: string)
	local s = _states[player]
	if not s then return end

	-- ── Gate checks ───────────────────────────────────────────────────────────
	if StunModule.IsStunned(player)    then return end
	if RagdollModule.IsRagdolled(player) then return end
	if s.WallRun.Active               then return end  -- no dash while wall running

	local now = os.clock()
	if now - s.Dash.LastDash < DC.Cooldown then return end  -- cooldown

	local humanoid = _getHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then return end
	if not _isGrounded(humanoid) then return end  -- must be grounded

	-- ── Validate direction string (never trust client) ────────────────────────
	local validDirs = { Forward = true, Backward = true, Left = true, Right = true }
	if not validDirs[direction] then return end

	local hrp = _getHRP(player)
	if not hrp then return end

	-- ── Commit ────────────────────────────────────────────────────────────────
	s.Dash.LastDash    = now
	s.Dash.IsDashing   = true
	s.Dash.IFrameUntil = now + DC.IFrameDuration

	local dashDir = _dashVector(hrp, direction)
	_applyDashVelocity(hrp, dashDir, DC.Speed, DC.Duration)

	-- Clear dashing flag after duration
	task.delay(DC.Duration, function()
		s.Dash.IsDashing = false
	end)

	-- ── Notify clients: play dash animation + VFX ─────────────────────────────
	RE_DashEffect:FireAllClients(player, direction)
end

RE_RequestDash.OnServerEvent:Connect(_handleDashRequest)

-- ══════════════════════════════════════════════════════════════════════════════
--  WALL RUN SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════

--[[
	Cast WC.RayCount rays spread vertically from HRP on the given side.
	Returns (hit: bool, normal: Vector3, hitPart: BasePart?) for the best hit.
	"Best" = closest hit that passes slope validation.
]]
local function _castWallRays(hrp: BasePart, side: string): (boolean, Vector3, BasePart?)
	local right   = hrp.CFrame.RightVector
	local sideDir = (side == "Right") and right or -right
	local origin  = hrp.Position

	local params = RaycastParams.new()
	local char   = hrp.Parent
	params.FilterDescendantsInstances = char and { char } or {}
	params.FilterType                  = Enum.RaycastFilterType.Exclude

	-- Spread rays vertically to handle uneven terrain
	local halfSpread = (WC.RayCount - 1) * WC.RaySpreadY * 0.5
	for i = 0, WC.RayCount - 1 do
		local yOffset = -halfSpread + i * WC.RaySpreadY
		local rayOrigin = origin + Vector3.new(0, yOffset, 0)
		local result    = workspace:Raycast(rayOrigin, sideDir * WC.RayLength, params)
		if result then
			-- Validate wall is nearly vertical (surface normal is mostly horizontal)
			local normalY = math.abs(result.Normal.Y)
			local slopeAngle = math.deg(math.asin(normalY))
			if slopeAngle <= WC.MaxSlopeAngle then
				return true, result.Normal, result.Instance
			end
		end
	end

	return false, Vector3.zero, nil
end

--[[
	While wall running, we override gravity and drive forward velocity with
	two constraints parented to HRP. Both are cleaned up on wall run end.

	VectorForce  → cancels gravity
	LinearVelocity → drives forward + slight up along the wall surface
]]
local function _startWallRunConstraints(hrp: BasePart, wallNormal: Vector3, side: string): (LinearVelocity, VectorForce)
	-- "forward along wall" = HRP forward projected onto the wall plane
	local look       = hrp.CFrame.LookVector
	local wallForward = (look - wallNormal * look:Dot(wallNormal)).Unit
	local velocity    = wallForward * WC.ForwardSpeed + Vector3.new(0, WC.UpForce, 0)

	local att = Instance.new("Attachment")
	att.Name   = "WallRunAttachment"
	att.Parent = hrp

	-- Drive forward velocity
	local lv = Instance.new("LinearVelocity")
	lv.Name                   = "WallRunVelocity"
	lv.Attachment0            = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce               = 4e4
	lv.RelativeTo             = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity         = velocity
	lv.Parent                 = hrp

	-- Cancel most of gravity (not all — slight downward drift looks natural)
	local gravCancel = workspace.Gravity + WC.Gravity  -- residual = WC.Gravity (negative = up)
	local vf = Instance.new("VectorForce")
	vf.Name        = "WallRunGrav"
	vf.Attachment0 = att
	vf.Force       = Vector3.new(0, gravCancel, 0)
	vf.RelativeTo  = Enum.ActuatorRelativeTo.World
	vf.Parent      = hrp

	return lv, vf
end

local function _stopWallRunConstraints(hrp: BasePart?)
	if not hrp then return end
	local att = hrp:FindFirstChild("WallRunAttachment")
	if att then att:Destroy() end  -- destroys both lv + vf as children
	-- Belt-and-suspenders: destroy by name too
	for _, child in ipairs(hrp:GetChildren()) do
		if child.Name == "WallRunVelocity" or child.Name == "WallRunGrav" then
			child:Destroy()
		end
	end
end

-- Tilt character CFrame toward the wall during wall run
local function _tiltTowardWall(hrp: BasePart, side: string)
	local angle = math.rad(WC.TiltAngle) * (side == "Right" and 1 or -1)
	-- We rotate around the HRP's look axis (roll)
	local tiltCF = hrp.CFrame * CFrame.Angles(0, 0, -angle)
	hrp.CFrame   = tiltCF
end

local function _untilt(hrp: BasePart)
	-- Strip roll — keep position and yaw only
	local pos   = hrp.Position
	local lookH = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	hrp.CFrame  = CFrame.lookAt(pos, pos + lookH)
end

-- End wall run for a player — centralized so every exit path goes through here
local function _endWallRun(player: Player, reason: string?)
	local s = _states[player]
	if not s or not s.WallRun.Active then return end

	s.WallRun.Active = false

	local hrp = _getHRP(player)
	_stopWallRunConstraints(hrp)
	if hrp then _untilt(hrp) end

	RE_WallRunEnd:FireAllClients(player)
end

-- Attempt to attach a wall run — called each physics step while player is airborne
local function _tryAttachWallRun(player: Player, s: PlayerMovState)
	if s.WallRun.Active then return end
	if s.Dash.IsDashing then return end

	local hrp      = _getHRP(player)
	local humanoid = _getHumanoid(player)
	if not hrp or not humanoid then return end
	if humanoid.Health <= 0 then return end

	-- Must be airborne
	if _isGrounded(humanoid) then
		s.WallRun.AirTime = os.clock()  -- reset air clock while grounded
		return
	end

	-- Must have been airborne long enough (prevents instant attach on tiny hops)
	if os.clock() - s.WallRun.AirTime < WC.MinAirTime then return end

	-- Must be moving forward (not drifting sideways into a wall)
	local vel      = hrp.AssemblyLinearVelocity
	local flatVel  = Vector3.new(vel.X, 0, vel.Z)
	local flatLook = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	if flatLook.Magnitude > 0.01 and flatVel.Magnitude > 0.5 then
		local dot = flatVel.Unit:Dot(flatLook.Unit)
		if dot < WC.MinForwardDot then return end
	end

	-- Check both sides for a wall
	local sides = { "Left", "Right" }
	for _, side in ipairs(sides) do
		local hit, normal, _ = _castWallRays(hrp, side)
		if hit then
			-- Start wall run!
			s.WallRun.Active     = true
			s.WallRun.Side       = side
			s.WallRun.WallNormal = normal
			s.WallRun.StartTime  = os.clock()

			local lv, vf = _startWallRunConstraints(hrp, normal, side)
			s.WallRun.VelConstraint  = lv
			s.WallRun.GravConstraint = vf

			_tiltTowardWall(hrp, side)

			RE_WallRunStart:FireAllClients(player, side)
			return
		end
	end
end

-- Tick an active wall run each physics step
local function _tickWallRun(player: Player, s: PlayerMovState)
	if not s.WallRun.Active then return end

	local hrp      = _getHRP(player)
	local humanoid = _getHumanoid(player)
	if not hrp or not humanoid then
		_endWallRun(player, "no_character")
		return
	end

	-- ── Exit conditions ───────────────────────────────────────────────────────

	-- 1. Landed on ground
	if _isGrounded(humanoid) then
		_endWallRun(player, "landed")
		return
	end

	-- 2. Max duration exceeded
	if os.clock() - s.WallRun.StartTime >= WC.MaxDuration then
		_endWallRun(player, "timeout")
		return
	end

	-- 3. Wall disappeared (re-cast to confirm wall is still there)
	local wallStillPresent, _, _ = _castWallRays(hrp, s.WallRun.Side)
	if not wallStillPresent then
		_endWallRun(player, "wall_ended")
		return
	end

	-- 4. Stunned or ragdolled mid-wall-run
	if StunModule.IsStunned(player) or RagdollModule.IsRagdolled(player) then
		_endWallRun(player, "interrupted")
		return
	end

	-- Still running — update forward velocity direction (player may be turning)
	-- Re-project look onto wall plane each tick so turning feels responsive
	local look       = hrp.CFrame.LookVector
	local normal     = s.WallRun.WallNormal
	local wallFwd    = (look - normal * look:Dot(normal))
	if wallFwd.Magnitude > 0.01 then
		wallFwd = wallFwd.Unit
		local lv = hrp:FindFirstChild("WallRunVelocity") :: LinearVelocity?
		if lv then
			lv.VectorVelocity = wallFwd * WC.ForwardSpeed + Vector3.new(0, WC.UpForce, 0)
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  PLAYER LIFECYCLE
-- ══════════════════════════════════════════════════════════════════════════════

local function _onPlayerAdded(player: Player)
	_states[player] = _newState()

	-- Track when character spawns to reset air timer
	player.CharacterAdded:Connect(function(char)
		local s = _states[player]
		if not s then return end
		s.WallRun.AirTime = os.clock()
		s.WallRun.Active  = false

		-- Clean up any stale constraints from previous life
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		if hrp then
			_stopWallRunConstraints(hrp :: BasePart)
		end
	end)
end

local function _onPlayerRemoving(player: Player)
	_endWallRun(player, "leaving")
	_states[player] = nil
end

Players.PlayerAdded:Connect(_onPlayerAdded)
Players.PlayerRemoving:Connect(_onPlayerRemoving)
for _, p in ipairs(Players:GetPlayers()) do _onPlayerAdded(p) end

-- ══════════════════════════════════════════════════════════════════════════════
--  PHYSICS STEP — wall run detection + tick
--  Heartbeat runs every frame on the server. We use it to continuously check
--  if airborne players should attach to a wall, and to tick active wall runs.
-- ══════════════════════════════════════════════════════════════════════════════

RunService.Heartbeat:Connect(function()
	for player, s in pairs(_states) do
		if not player.Character then continue end

		if s.WallRun.Active then
			_tickWallRun(player, s)
		else
			_tryAttachWallRun(player, s)
		end
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  EXPOSE iFrame check for DamageModule to use (optional integration)
-- ══════════════════════════════════════════════════════════════════════════════

-- Other server modules can require this script and call IsIFramed(player).
-- Since server scripts can't normally be required, we store the function
-- in a shared table on _G so CombatService can gate damage.
-- (If you prefer module pattern, move this whole file to Modules/ as a ModuleScript.)
_G.MovementService = {
	IsIFramed = IsIFramed,
}

print("[MovementService] Phase 2 Movement ready.")