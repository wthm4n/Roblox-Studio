--[[
	HitboxModule.lua  (SERVER)
	Responsible for creating spatial hitboxes and returning hit characters.
	All hit detection is done server-side – clients never touch this.

	Place in: ServerScriptService/Modules/HitboxModule
]]

local HitboxModule = {}
HitboxModule.__index = HitboxModule

-- ── Services ──────────────────────────────────────────────────────────────────
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")

-- ── Constructor ───────────────────────────────────────────────────────────────
--[[
	HitboxModule.new(attacker, size, offset, maxReach)
		attacker  : Player  — the attacking player
		size      : Vector3 — hitbox dimensions in studs
		offset    : Vector3 — local offset from attacker HRP in attacker's LookVector space
		maxReach  : number  — maximum allowed distance between HRP centres

	Returns a Hitbox object.  Call :Fire() to execute the check.
]]
function HitboxModule.new(attacker: Player, size: Vector3, offset: Vector3, maxReach: number)
	assert(RunService:IsServer(), "HitboxModule must only run on the server!")

	local self = setmetatable({}, HitboxModule)

	self._attacker = attacker
	self._size     = size
	self._offset   = offset
	self._maxReach = maxReach
	self._ignore   = { attacker.Character }  -- always ignore the attacker

	return self
end

-- ── Private ───────────────────────────────────────────────────────────────────

-- Returns the CFrame of the hitbox in world space relative to the attacker's HRP.
local function _getHitboxCFrame(character: Model, offset: Vector3): CFrame
	local hrp: BasePart = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return CFrame.identity end
	-- Offset is in the attacker's local space (forward = -Z in Roblox)
	return hrp.CFrame * CFrame.new(offset)
end

-- ── Public ────────────────────────────────────────────────────────────────────

--[[
	:Fire() → { Player }
	Casts the hitbox and returns an array of Players whose characters overlap it.
	Uses WorldRoot:GetPartBoundsInBox for an AABB sweep (no allocations on misses).
]]
function HitboxModule:Fire(): { Player }
	local character = self._attacker.Character
	if not character then return {} end

	local hrp: BasePart = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return {} end

	local hitboxCF   = _getHitboxCFrame(character, self._offset)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = self._ignore
	overlapParams.FilterType                  = Enum.RaycastFilterType.Exclude
	overlapParams.MaxParts                    = 50

	local parts: { BasePart } = workspace:GetPartBoundsInBox(hitboxCF, self._size, overlapParams)

	-- Deduplicate: collect unique victim characters
	local seen: { [Model]: boolean } = {}
	local victims: { Player }        = {}

	for _, part in ipairs(parts) do
		local victimChar = part:FindFirstAncestorOfClass("Model")
		if not victimChar or seen[victimChar] then continue end

		local victimPlayer = Players:GetPlayerFromCharacter(victimChar)
		if not victimPlayer then continue end

		-- Distance guard (server-authoritative anti-cheat)
		local victimHRP: BasePart? = victimChar:FindFirstChild("HumanoidRootPart")
		if not victimHRP then continue end

		local dist = (hrp.Position - victimHRP.Position).Magnitude
		if dist > self._maxReach then continue end

		seen[victimChar] = true
		table.insert(victims, victimPlayer)
	end

	return victims
end

--[[
	:AddIgnore(instance)
	Add extra instances (e.g. props) that should be excluded from the overlap check.
]]
function HitboxModule:AddIgnore(instance: Instance)
	table.insert(self._ignore, instance)
end

return HitboxModule
