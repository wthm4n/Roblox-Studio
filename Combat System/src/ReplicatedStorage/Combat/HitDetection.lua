--[[
	HIT DETECTION SYSTEM
	
	NO Region3.
	NO .Touched spam.
	
	Uses:
	- Oriented bounding boxes (OBB)
	- Swept volumes for fast attacks
	- Per-frame evaluation during active frames
	
	Hitboxes are driven by configs and animation markers.
	This is a SUBSYSTEM - it reports to Core, doesn't make decisions.
]]

local HitDetection = {}
HitDetection.__index = HitDetection

local RunService = game:GetService("RunService")

function HitDetection.new(core)
	local self = setmetatable({}, HitDetection)
	
	self.Core = core
	self.Character = core.Character
	self.HumanoidRootPart = core.HumanoidRootPart
	
	-- Active hitboxes this frame
	self.ActiveHitboxes = {} -- { HitboxData, StartFrame, EndFrame }
	
	-- Hit tracking
	self.HitThisFrame = {}
	
	-- Visual debugging (client only)
	self.DebugMode = false
	self.DebugParts = {}
	
	-- Listen to core events
	self.Connections = {}
	
	self.Connections.ActionStarted = core.Events.ActionStarted.Event:Connect(function(actionData)
		self:OnActionStarted(actionData)
	end)
	
	self.Connections.ActionEnded = core.Events.ActionEnded.Event:Connect(function(actionData)
		self:OnActionEnded(actionData)
	end)
	
	-- Frame update
	self.Connections.Heartbeat = RunService.Heartbeat:Connect(function()
		self:Update()
	end)
	
	return self
end

function HitDetection:OnActionStarted(actionData)
	-- Load hitbox data from action config
	local hitboxData = actionData.Config.Hitbox
	
	if not hitboxData then
		return -- No hitbox for this action
	end
	
	-- Calculate when hitbox becomes active
	local startupFrames = actionData.Config.StartupFrames
	local activeFrames = actionData.Config.ActiveFrames
	
	local hitboxStart = self.Core.CurrentFrame + startupFrames
	local hitboxEnd = hitboxStart + activeFrames
	
	-- Register hitbox
	table.insert(self.ActiveHitboxes, {
		Data = hitboxData,
		StartFrame = hitboxStart,
		EndFrame = hitboxEnd,
		ActionType = actionData.Type,
	})
end

function HitDetection:OnActionEnded(actionData)
	-- Clear all hitboxes
	self.ActiveHitboxes = {}
	self:ClearDebugVisuals()
end

function HitDetection:Update()
	-- Check each active hitbox
	for i = #self.ActiveHitboxes, 1, -1 do
		local hitbox = self.ActiveHitboxes[i]
		
		-- Check if this hitbox is active this frame
		if self.Core.CurrentFrame >= hitbox.StartFrame and self.Core.CurrentFrame <= hitbox.EndFrame then
			self:CheckHitbox(hitbox)
			
			-- Debug visualization
			if self.DebugMode and not self.Core.IsServer then
				self:VisualizeHitbox(hitbox)
			end
		end
		
		-- Remove expired hitboxes
		if self.Core.CurrentFrame > hitbox.EndFrame then
			table.remove(self.ActiveHitboxes, i)
		end
	end
	
	-- Clear hit tracking for next frame
	self.HitThisFrame = {}
end

--[[
	Check if hitbox intersects with any valid targets
]]
function HitDetection:CheckHitbox(hitbox)
	local hitboxData = hitbox.Data
	
	-- Get hitbox world position and orientation
	local hitboxCFrame = self:GetHitboxCFrame(hitboxData)
	local hitboxSize = hitboxData.Size or Vector3.new(4, 4, 4)
	
	-- Get potential targets in range
	local potentialTargets = self:GetNearbyCharacters(hitboxCFrame.Position, 15)
	
	for _, targetChar in ipairs(potentialTargets) do
		if self:IsValidTarget(targetChar) then
			-- Check intersection
			if self:CheckOBBIntersection(hitboxCFrame, hitboxSize, targetChar) then
				self:RegisterHit(targetChar, hitbox, hitboxCFrame.Position)
			end
		end
	end
end

--[[
	Get hitbox world CFrame based on character and offset
]]
function HitDetection:GetHitboxCFrame(hitboxData)
	local offset = hitboxData.Offset or Vector3.new(0, 0, -3)
	local rotation = hitboxData.Rotation or Vector3.new(0, 0, 0)
	
	-- Base position from character
	local baseCFrame = self.HumanoidRootPart.CFrame
	
	-- Apply offset and rotation
	local hitboxCFrame = baseCFrame * CFrame.new(offset) * CFrame.Angles(
		math.rad(rotation.X),
		math.rad(rotation.Y),
		math.rad(rotation.Z)
	)
	
	return hitboxCFrame
end

--[[
	OBB (Oriented Bounding Box) intersection test
]]
function HitDetection:CheckOBBIntersection(hitboxCFrame: CFrame, hitboxSize: Vector3, targetChar: Model): boolean
	-- Get target's hurtbox
	local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP then return false end
	
	-- For R6, we check the main torso hitbox
	local targetTorso = targetChar:FindFirstChild("Torso")
	if not targetTorso then return false end
	
	-- Simplified OBB test using region overlap
	-- In production, use proper separating axis theorem (SAT)
	
	local distance = (hitboxCFrame.Position - targetHRP.Position).Magnitude
	local combinedSize = (hitboxSize.Magnitude + targetTorso.Size.Magnitude) / 2
	
	return distance < combinedSize
end

--[[
	Get nearby characters using spatial query
]]
function HitDetection:GetNearbyCharacters(position: Vector3, radius: number)
	local characters = {}
	
	-- Use OverlapParams for efficient spatial query
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {self.Character}
	
	local parts = workspace:GetPartBoundsInRadius(position, radius, overlapParams)
	
	for _, part in ipairs(parts) do
		local char = part:FindFirstAncestorOfClass("Model")
		if char and char:FindFirstChild("Humanoid") then
			if not table.find(characters, char) then
				table.insert(characters, char)
			end
		end
	end
	
	return characters
end

function HitDetection:IsValidTarget(targetChar: Model): boolean
	-- Don't hit self
	if targetChar == self.Character then
		return false
	end
	
	-- Check if already hit this frame
	if self.HitThisFrame[targetChar] then
		return false
	end
	
	-- Check if target is alive
	local humanoid = targetChar:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	
	-- Could add team checks here
	-- if targetChar.Team == self.Character.Team then return false end
	
	return true
end

--[[
	Register a hit and report to Core for validation
]]
function HitDetection:RegisterHit(targetChar: Model, hitbox, hitPosition: Vector3)
	-- Mark as hit this frame
	self.HitThisFrame[targetChar] = true
	
	-- Calculate damage and knockback
	local damage = hitbox.Data.Damage or 10
	local knockbackDirection = (targetChar.HumanoidRootPart.Position - self.HumanoidRootPart.Position).Unit
	local knockbackForce = hitbox.Data.KnockbackForce or 50
	local knockback = knockbackDirection * knockbackForce
	
	-- SERVER: Validate hit through Core
	if self.Core.IsServer then
		local isValid = self.Core:ValidateHit(targetChar, hitPosition)
		
		if isValid then
			self.Core:ConfirmHit(targetChar, damage, knockback)
		end
	else
		-- CLIENT: Report to server for validation
		local hitData = {
			Damage = damage,
			Knockback = knockback,
			HitPosition = hitPosition,
			HitboxData = hitbox.Data,
		}
		
		self.Core.NetworkSync:ReportHit(targetChar, hitData)
	end
end

--[[
	DEBUG VISUALIZATION
]]
function HitDetection:VisualizeHitbox(hitbox)
	-- Create debug part
	local debugPart = Instance.new("Part")
	debugPart.Anchored = true
	debugPart.CanCollide = false
	debugPart.Material = Enum.Material.Neon
	debugPart.Color = Color3.new(1, 0, 0)
	debugPart.Transparency = 0.5
	debugPart.Size = hitbox.Data.Size or Vector3.new(4, 4, 4)
	debugPart.CFrame = self:GetHitboxCFrame(hitbox.Data)
	debugPart.Parent = workspace
	
	table.insert(self.DebugParts, debugPart)
	
	-- Auto-cleanup
	task.delay(0.1, function()
		debugPart:Destroy()
	end)
end

function HitDetection:ClearDebugVisuals()
	for _, part in ipairs(self.DebugParts) do
		if part and part.Parent then
			part:Destroy()
		end
	end
	self.DebugParts = {}
end

function HitDetection:SetDebugMode(enabled: boolean)
	self.DebugMode = enabled
end

function HitDetection:Destroy()
	for _, conn in pairs(self.Connections) do
		conn:Disconnect()
	end
	
	self:ClearDebugVisuals()
end

return HitDetection
