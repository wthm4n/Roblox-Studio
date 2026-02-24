--[[
	HitboxService.lua
	Server-side hitbox creation and overlap detection.
	Works for players AND NPCs.

	Supports:
	  - Box hitboxes (melee)
	  - Sphere hitboxes (AOE)
	  - Raycast (hitscan projectiles)
]]

local HitboxService = {}
HitboxService.__index = HitboxService

local Players    = game:GetService("Players")
local MAX_HITS   = 8

function HitboxService.new()
	return setmetatable({}, HitboxService)
end

-- ─── Helpers ──────────────────────────────────────────────────────────────────

-- Resolve a hit part to either a Player or an NPC model {_isNPC, Character, UserId-like}
-- Returns nil if the target is dead or not hittable
local function ResolveTarget(part: BasePart, excludeChar: Model?)
	local char = part:FindFirstAncestorOfClass("Model")
	if not char or char == excludeChar then return nil end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end

	-- Player hit
	local player = Players:GetPlayerFromCharacter(char)
	if player then return player end

	-- NPC hit — wrap in a table that callers can identify
	if char:FindFirstChild("HumanoidRootPart") then
		return { _isNPC = true, Character = char, UserId = char:GetAttribute("NpcId") }
	end

	return nil
end

local function BuildOverlapParams(excludeChar: Model?): OverlapParams
	local p = OverlapParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = excludeChar and { excludeChar } or {}
	p.MaxParts = MAX_HITS * 10
	return p
end

-- ─── Box Hitbox ───────────────────────────────────────────────────────────────

--[[
	CreateMeleeHitbox(opts)

	opts = {
		Caster            : Player?      -- nil for NPCs
		Caster_Character  : Model?       -- the caster's char model (required)
		Origin            : CFrame       -- hitbox world transform
		Size              : Vector3
	}

	Returns: { Player | NpcProxy }
]]
function HitboxService:CreateMeleeHitbox(opts)
	local excludeChar = opts.Caster_Character
		or (opts.Caster and opts.Caster.Character)

	local params = BuildOverlapParams(excludeChar)
	local parts  = workspace:GetPartBoundsInBox(opts.Origin, opts.Size, params)

	local results = {}
	local seen    = {}

	for _, part in ipairs(parts) do
		if #results >= MAX_HITS then break end
		local target = ResolveTarget(part, excludeChar)
		if target then
			local key = target._isNPC and target.Character or target
			if not seen[key] then
				seen[key] = true
				table.insert(results, target)
			end
		end
	end

	return results
end

-- ─── Sphere Hitbox ────────────────────────────────────────────────────────────

function HitboxService:CreateSphereHitbox(opts)
	local excludeChar = opts.Caster_Character
		or (opts.Caster and opts.Caster.Character)

	local params = BuildOverlapParams(excludeChar)
	local parts  = workspace:GetPartBoundsInRadius(opts.Center, opts.Radius, params)

	local results = {}
	local seen    = {}

	for _, part in ipairs(parts) do
		if #results >= MAX_HITS then break end
		local target = ResolveTarget(part, excludeChar)
		if target then
			local key = target._isNPC and target.Character or target
			if not seen[key] then
				seen[key] = true
				table.insert(results, target)
			end
		end
	end

	return results
end

-- ─── Raycast ──────────────────────────────────────────────────────────────────

function HitboxService:CastRay(opts)
	local excludeChar = opts.Caster_Character
		or (opts.Caster and opts.Caster.Character)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = excludeChar and { excludeChar } or {}

	local result = workspace:Raycast(opts.Origin, opts.Direction * opts.Range, rayParams)
	if not result then return nil end

	return ResolveTarget(result.Instance, excludeChar)
end

-- ─── Distance Validation ──────────────────────────────────────────────────────

function HitboxService:ValidateDistance(attackerChar: Model, targetChar: Model, maxRange: number): boolean
	local aRoot = attackerChar:FindFirstChild("HumanoidRootPart")
	local tRoot = targetChar:FindFirstChild("HumanoidRootPart")
	if not aRoot or not tRoot then return false end
	return (aRoot.Position - tRoot.Position).Magnitude <= maxRange
end

return HitboxService