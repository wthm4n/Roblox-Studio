--[[
	Ability1_GroundSlam.lua
	
	A powerful ground slam that damages and knocks back enemies in a radius.
	Creates impressive visual effects with debris and shockwaves.
	
	Author: [Your Name]
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local AbilityBase = require(ReplicatedStorage.Modules.Combat.Abilities.AbilityBase)

-- ========================================
-- ABILITY CONFIGURATION
-- ========================================

local GroundSlam = AbilityBase.new({
	Name = "Ground Slam",
	Description = "Slam the ground with devastating force, damaging all nearby enemies",

	-- Stats
	Cooldown = 8,
	Damage = 30,
	Range = 15,

	-- Animation
	AnimationId = "rbxassetid://127216885144368",
	AnimationDuration = 1.2,

	-- UI
	Icon = "rbxassetid://0", -- Replace with your icon
	VFXName = "ability1",

	-- Custom
	CustomProperties = {
		KnockbackHorizontal = 35,
		KnockbackVertical = 45,
		DebrisCount = 12,
		ShockwaveCount = 3,
		CrackCount = 6,
	},
})

-- ========================================
-- SERVER-SIDE ACTIVATION
-- ========================================

function GroundSlam:OnActivate(player, character, rootPart, utilities)
	print("💥", player.Name, "used Ground Slam!")

	-- Get impact position
	local impactPosition = rootPart.Position - Vector3.new(0, 3, 0)

	-- Find targets in radius
	local targets = utilities.GetTargetsInRange(impactPosition, self.Range)

	-- Apply damage to all targets
	for _, targetData in targets do
		utilities.ApplyDamage(targetData, self.Damage, {
			Horizontal = self.CustomProperties.KnockbackHorizontal,
			Vertical = self.CustomProperties.KnockbackVertical,
		})
	end

	-- Return success and target characters (for VFX)
	local targetCharacters = {}
	for _, targetData in targets do
		table.insert(targetCharacters, targetData.Character)
	end

	return true, targetCharacters
end

-- ========================================
-- CLIENT-SIDE VFX
-- ========================================

function GroundSlam:PlayVFX(rootPart, vfxTemplate, targets)
	local impactPosition = rootPart.CFrame * CFrame.new(0, -3, 0)

	-- ========================================
	-- MAIN VFX EMITTER
	-- ========================================

	if vfxTemplate then
		local vfxClone = vfxTemplate:Clone()
		vfxClone.Parent = workspace
		vfxClone:PivotTo(impactPosition)

		self:EmitParticles(vfxClone, 80)
		Debris:AddItem(vfxClone, 2)
	end

	-- ========================================
	-- CRATER
	-- ========================================

	local crater = Instance.new("Part")
	crater.Name = "Crater"
	crater.Size = Vector3.new(18, 1, 18)
	crater.CFrame = impactPosition
	crater.Anchored = true
	crater.CanCollide = false
	crater.Material = Enum.Material.Slate
	crater.Color = Color3.fromRGB(70, 55, 45)
	crater.Transparency = 0.2
	crater.Parent = workspace

	local craterMesh = Instance.new("CylinderMesh")
	craterMesh.Parent = crater
	craterMesh.Scale = Vector3.new(1, 0.2, 1)

	TweenService:Create(crater, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(25, 0.5, 25),
		Transparency = 1,
		CFrame = crater.CFrame * CFrame.new(0, -0.8, 0),
	}):Play()

	Debris:AddItem(crater, 2.5)

	-- ========================================
	-- EXPANDING SHOCKWAVES
	-- ========================================

	for i = 1, self.CustomProperties.ShockwaveCount do
		task.delay(i * 0.1, function()
			self:CreateShockwave(impactPosition, {
				StartSize = Vector3.new(5, 2, 5),
				EndSize = Vector3.new(35 + i * 5, 1, 35 + i * 5),
				Color = Color3.fromRGB(255, 180 - i * 30, 50),
				Duration = 0.6,
				Transparency = 0.4 + i * 0.1,
			})
		end)
	end

	-- ========================================
	-- FLYING DEBRIS
	-- ========================================

	for i = 1, self.CustomProperties.DebrisCount do
		local size = math.random(15, 35) / 10
		self:SpawnDebris(impactPosition, {
			Name = "GroundRock",
			Size = Vector3.new(size, size, size),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(math.random(50, 90), math.random(40, 70), math.random(30, 60)),
			Velocity = Vector3.new(math.random(-40, 40), math.random(50, 90), math.random(-40, 40)),
		})
	end

	-- ========================================
	-- GROUND CRACKS
	-- ========================================

	for i = 1, self.CustomProperties.CrackCount do
		local angle = (i / self.CustomProperties.CrackCount) * math.pi * 2
		local crack = Instance.new("Part")
		crack.Name = "GroundCrack"
		crack.Size = Vector3.new(2.5, 0.1, math.random(10, 18))
		crack.CFrame = impactPosition
			* CFrame.new(math.cos(angle) * 5, 0, math.sin(angle) * 5)
			* CFrame.Angles(0, angle, 0)
		crack.Anchored = true
		crack.CanCollide = false
		crack.Material = Enum.Material.Slate
		crack.Color = Color3.fromRGB(25, 20, 18)
		crack.Transparency = 0.15
		crack.Parent = workspace

		TweenService:Create(crack, TweenInfo.new(3.5), { Transparency = 1 }):Play()

		Debris:AddItem(crack, 4)
	end

	-- ========================================
	-- IMPACT FLASH
	-- ========================================

	local flash = Instance.new("Part")
	flash.Size = Vector3.new(20, 20, 20)
	flash.CFrame = impactPosition
	flash.Anchored = true
	flash.CanCollide = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 220, 100)
	flash.Transparency = 0.3
	flash.Shape = Enum.PartType.Ball
	flash.Parent = workspace

	TweenService:Create(flash, TweenInfo.new(0.15), {
		Size = Vector3.new(35, 35, 35),
		Transparency = 1,
	}):Play()

	Debris:AddItem(flash, 0.2)

	-- ========================================
	-- SCREEN SHAKE & SOUND
	-- ========================================

	self:CreateScreenShake(0.5, 0.3)
	self:PlaySound("rbxassetid://9114366058", rootPart, 0.7)

	-- ========================================
	-- HIT EFFECTS ON TARGETS
	-- ========================================

	if targets then
		for _, targetChar in targets do
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				local hitEffect = Instance.new("Part")
				hitEffect.Size = Vector3.new(4, 4, 0.2)
				hitEffect.Transparency = 0.5
				hitEffect.Color = Color3.fromRGB(255, 200, 0)
				hitEffect.Anchored = true
				hitEffect.CanCollide = false
				hitEffect.CFrame = targetRoot.CFrame
				hitEffect.Parent = workspace

				TweenService:Create(hitEffect, TweenInfo.new(0.5), {
					Transparency = 1,
					Size = Vector3.new(6, 6, 0.2),
				}):Play()

				Debris:AddItem(hitEffect, 0.5)
			end
		end
	end
end

return GroundSlam
