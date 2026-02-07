--[[
	AbilityBase.lua
	
	Base class for all combat abilities using proper OOP.
	Provides common functionality and enforces structure.
	
	Author: [Your Name]
]]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- ========================================
-- BASE ABILITY CLASS
-- ========================================

local AbilityBase = {}
AbilityBase.__index = AbilityBase

-- Constructor
function AbilityBase.new(config: { [string]: any })
	local self = setmetatable({}, AbilityBase)

	-- Core Properties
	self.Name = config.Name or "Unnamed Ability"
	self.Description = config.Description or "No description"
	self.Cooldown = config.Cooldown or 5
	self.Damage = config.Damage or 20
	self.Range = config.Range or 15

	-- Animation
	self.AnimationId = config.AnimationId or ""
	self.AnimationDuration = config.AnimationDuration or 1.0

	-- UI
	self.Icon = config.Icon or "rbxassetid://0"
	self.VFXName = config.VFXName or ""

	-- Custom properties
	self.CustomProperties = config.CustomProperties or {}

	return self
end

-- ========================================
-- LIFECYCLE METHODS (Override these)
-- ========================================

--[[
	Called when ability is activated (SERVER ONLY)
	@param player - Player who used the ability
	@param character - Player's character model
	@param rootPart - Character's HumanoidRootPart
	@param utilities - Table of utility functions
	@return success: boolean, targets: {Model}
]]
function AbilityBase:OnActivate(player, character, rootPart, utilities)
	warn(self.Name .. " - OnActivate not implemented!")
	return false, {}
end

--[[
	Called to play VFX (CLIENT ONLY)
	@param rootPart - Player's HumanoidRootPart
	@param vfxTemplate - VFX template from ReplicatedStorage
	@param targets - Array of hit targets (optional)
]]
function AbilityBase:PlayVFX(rootPart, vfxTemplate, targets)
	warn(self.Name .. " - PlayVFX not implemented!")
end

--[[
	Called when ability goes on cooldown (CLIENT ONLY)
	Useful for custom UI updates
]]
function AbilityBase:OnCooldownStart()
	-- Optional override
end

--[[
	Called when ability is cancelled/interrupted
	Useful for cleanup
]]
function AbilityBase:OnCancel()
	-- Optional override
end

-- ========================================
-- HELPER METHODS
-- ========================================

-- Spawn physics debris
function AbilityBase:SpawnDebris(position: CFrame, config: { [string]: any })
	local debris = Instance.new("Part")
	debris.Name = config.Name or "Debris"
	debris.Size = config.Size or Vector3.new(2, 2, 2)
	debris.Material = config.Material or Enum.Material.Slate
	debris.Color = config.Color or Color3.fromRGB(100, 100, 100)
	debris.CanCollide = true
	debris.CFrame = position
		* CFrame.new(math.random(-5, 5), math.random(0, 2), math.random(-5, 5))
		* CFrame.Angles(math.rad(math.random(0, 360)), math.rad(math.random(0, 360)), math.rad(math.random(0, 360)))
	debris.Parent = workspace

	-- Apply physics
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(50000, 50000, 50000)
	bodyVelocity.Velocity = config.Velocity
		or Vector3.new(math.random(-30, 30), math.random(40, 70), math.random(-30, 30))
	bodyVelocity.Parent = debris

	local bodyAngularVelocity = Instance.new("BodyAngularVelocity")
	bodyAngularVelocity.MaxTorque = Vector3.new(50000, 50000, 50000)
	bodyAngularVelocity.AngularVelocity = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))
	bodyAngularVelocity.Parent = debris

	-- Cleanup physics after short time
	task.delay(0.2, function()
		if bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
		if bodyAngularVelocity.Parent then
			bodyAngularVelocity:Destroy()
		end
	end)

	-- Fade out
	task.delay(config.FadeDelay or 1.5, function()
		if debris.Parent then
			TweenService:Create(debris, TweenInfo.new(1), { Transparency = 1 }):Play()
		end
	end)

	Debris:AddItem(debris, config.Lifetime or 2.5)

	return debris
end

-- Create expanding shockwave effect
function AbilityBase:CreateShockwave(position: CFrame, config: { [string]: any })
	local shockwave = Instance.new("Part")
	shockwave.Name = "Shockwave"
	shockwave.Size = config.StartSize or Vector3.new(1, 1, 1)
	shockwave.CFrame = position
	shockwave.Anchored = true
	shockwave.CanCollide = false
	shockwave.Material = config.Material or Enum.Material.Neon
	shockwave.Color = config.Color or Color3.fromRGB(255, 200, 100)
	shockwave.Transparency = config.Transparency or 0.5
	shockwave.Parent = workspace

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = config.MeshType or Enum.MeshType.Sphere
	mesh.Parent = shockwave

	local duration = config.Duration or 0.5

	TweenService:Create(shockwave, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = config.EndSize or Vector3.new(30, 15, 30),
		Transparency = 1,
	}):Play()

	Debris:AddItem(shockwave, duration + 0.1)

	return shockwave
end

-- Emit particles from VFX template
function AbilityBase:EmitParticles(vfxClone, emitCount: number?)
	for _, descendant in vfxClone:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local count = descendant:GetAttribute("EmitCount") or emitCount or 50
			descendant:Emit(count)
		elseif descendant:IsA("Beam") then
			descendant.Enabled = true
			task.delay(1, function()
				if descendant and descendant.Parent then
					descendant.Enabled = false
				end
			end)
		end
	end
end

-- Enable continuous particle effects for duration
function AbilityBase:EnableContinuousVFX(vfxClone, duration: number)
	for _, descendant in vfxClone:GetDescendants() do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			descendant.Enabled = true
		end
	end

	task.delay(duration, function()
		for _, descendant in vfxClone:GetDescendants() do
			if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
				descendant.Enabled = false
			end
		end
	end)
end

-- Play sound effect
function AbilityBase:PlaySound(soundId: string, parent: Instance, volume: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.5
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 5)
	return sound
end

-- Create screen shake effect (CLIENT ONLY)
function AbilityBase:CreateScreenShake(magnitude: number, duration: number)
	local camera = workspace.CurrentCamera
	local originalCFrame = camera.CFrame

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			local shake = Vector3.new(
				math.random(-100, 100) / 100 * magnitude,
				math.random(-100, 100) / 100 * magnitude,
				math.random(-100, 100) / 100 * magnitude
			)
			camera.CFrame = camera.CFrame * CFrame.new(shake)
			elapsed += task.wait()
		end
	end)
end

-- ========================================
-- VALIDATION
-- ========================================

function AbilityBase:Validate(): (boolean, string?)
	if not self.Name or self.Name == "" then
		return false, "Ability has no name"
	end

	if self.Cooldown < 0 then
		return false, "Cooldown cannot be negative"
	end

	if self.Damage < 0 then
		return false, "Damage cannot be negative"
	end

	if self.Range <= 0 then
		return false, "Range must be positive"
	end

	return true
end

-- ========================================
-- SERIALIZATION (for debugging)
-- ========================================

function AbilityBase:ToTable(): { [string]: any }
	return {
		Name = self.Name,
		Description = self.Description,
		Cooldown = self.Cooldown,
		Damage = self.Damage,
		Range = self.Range,
		AnimationId = self.AnimationId,
		AnimationDuration = self.AnimationDuration,
		Icon = self.Icon,
		VFXName = self.VFXName,
	}
end

function AbilityBase:ToString(): string
	return string.format("%s (DMG: %d, RNG: %d, CD: %.1fs)", self.Name, self.Damage, self.Range, self.Cooldown)
end

return AbilityBase
