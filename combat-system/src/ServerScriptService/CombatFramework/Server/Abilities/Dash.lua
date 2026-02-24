--[[
	Abilities/Dash.lua
	Directional dash with optional invincibility frames.

	Client sends: { Direction: "Forward" | "Back" | "Left" | "Right" }
	Server validates direction and applies velocity impulse.
]]

local Dash = {}
Dash.__index = Dash

-- ─── Ability Definition ───────────────────────────────────────────────────────

Dash.Name     = "Dash"
Dash.Cooldown = 4
Dash.Stamina  = 20

local DASH_FORCE    = 90
local IFRAMES_TIME  = 0.12   -- seconds of invincibility during dash
local DASH_DURATION = 0.18   -- how long the character is in Dashing state

-- Allowed direction strings from client
local VALID_DIRS = {
	Forward = true,
	Back    = true,
	Left    = true,
	Right   = true,
}

-- Local direction offsets relative to character's HRP CFrame
local DIR_VECTORS = {
	Forward = Vector3.new( 0, 0, -1),
	Back    = Vector3.new( 0, 0,  1),
	Left    = Vector3.new(-1, 0,  0),
	Right   = Vector3.new( 1, 0,  0),
}

-- ─── Execute ──────────────────────────────────────────────────────────────────

function Dash:Execute(player: Player, inputData: {}, ctx: {})
	local char = player.Character
	if not char then return end

	local root = char:FindFirstChild("HumanoidRootPart")
	local hum  = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then return end

	-- Validate direction from client — never trust raw vectors
	local dirName = inputData.Direction
	if not dirName or not VALID_DIRS[dirName] then
		dirName = "Forward"  -- fallback silently
	end

	local state = ctx.states[player.UserId]
	if not state:CanDash() then return end

	state:SetState("Dashing")

	-- Convert local direction to world space
	local worldDir = (root.CFrame * CFrame.new(DIR_VECTORS[dirName])).Position - root.Position

	-- Apply velocity impulse via VectorForce for one frame
	root:ApplyImpulse(worldDir.Unit * DASH_FORCE)

	-- Fire VFX to clients
	ctx.fireVfx("DashEffect", {
		PlayerId  = player.UserId,
		Direction = dirName,
	})

	-- Invincibility frames: temporarily make status checks fail
	local iframeActive = true
	local originalCanAct = state.CanAct
	state.CanAct = function() return false end  -- no attack during i-frames

	task.delay(IFRAMES_TIME, function()
		state.CanAct = originalCanAct
		iframeActive = false
	end)

	-- Reset state after dash ends
	task.delay(DASH_DURATION, function()
		if state:Is("Dashing") then
			state:SetState("Idle")
		end
	end)
end

return Dash