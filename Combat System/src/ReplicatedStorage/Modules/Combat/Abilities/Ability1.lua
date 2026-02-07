local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local BaseAbility = require(ReplicatedStorage.Modules.Combat.Abilities.BaseAbility)

local GroundSlam = BaseAbility.new({
	Name = "Ground Slam",
	Description = "Slam the ground, creating a massive shockwave",
	Cooldown = 8,
	Damage = 30,
	Range = 15,
	AnimationId = "rbxassetid://127216885144368",
	AnimationDuration = 1.2,
	Icon = "rbxassetid://0",
	VFXName = "ability1"
})

function GroundSlam:PlayVFX(rootPart, vfx)
	local slamPosition = rootPart.CFrame * CFrame.new(0, -3, 0)

	-- VFX ATTACHMENT
	local groundPoint = Instance.new("Part")
	groundPoint.Size = Vector3.new(0.1, 0.1, 0.1)
	groundPoint.Transparency = 1
	groundPoint.Anchored = true
	groundPoint.CanCollide = false
	groundPoint.CFrame = slamPosition
	groundPoint.Parent = workspace

	local vfxClone = vfx:Clone()
	vfxClone.Parent = groundPoint
	self:EmitParticles(vfxClone, 80)

	Debris:AddItem(groundPoint, 2)

	local crater = Instance.new("Part")
	crater.Name = "Crater"
	crater.Size = Vector3.new(18, 1, 18)
	crater.CFrame = slamPosition
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
		CFrame = crater.CFrame * CFrame.new(0, -0.8, 0)
	}):Play()

	Debris:AddItem(crater, 2.5)
	for i = 1, 3 do
		task.delay(i * 0.1, function()
			self:CreateShockwave(slamPosition, {
				StartSize = Vector3.new(5, 2, 5),
				EndSize = Vector3.new(35 + i * 5, 1, 35 + i * 5),
				Color = Color3.fromRGB(255, 180 - i * 30, 50),
				Duration = 0.6,
				Transparency = 0.4 + i * 0.1
			})
		end)
	end
	for i = 1, 12 do
		local size = math.random(15, 35) / 10
		self:SpawnDebris(slamPosition, {
			Name = "GroundRock",
			Size = Vector3.new(size, size, size),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(
				math.random(50, 90),
				math.random(40, 70),
				math.random(30, 60)
			),
			Velocity = Vector3.new(
				math.random(-40, 40),
				math.random(50, 90),
				math.random(-40, 40)
			)
		})
	end
	for i = 1, 6 do
		local angle = (i / 6) * math.pi * 2
		local crack = Instance.new("Part")
		crack.Name = "GroundCrack"
		crack.Size = Vector3.new(2.5, 0.1, math.random(10, 18))
		crack.CFrame = slamPosition * CFrame.new(
			math.cos(angle) * 5,
			0,
			math.sin(angle) * 5
		) * CFrame.Angles(0, angle, 0)
		crack.Anchored = true
		crack.CanCollide = false
		crack.Material = Enum.Material.Slate
		crack.Color = Color3.fromRGB(25, 20, 18)
		crack.Transparency = 0.15
		crack.Parent = workspace

		TweenService:Create(crack, TweenInfo.new(3.5), {
			Transparency = 1
		}):Play()

		Debris:AddItem(crack, 4)
	end
	for i = 1, 3 do
		local dustCloud = Instance.new("Part")
		dustCloud.Name = "DustCloud"
		dustCloud.Size = Vector3.new(12 + i * 3, 6 + i * 2, 12 + i * 3)
		dustCloud.CFrame = slamPosition * CFrame.new(
			math.random(-2, 2),
			2 + i,
			math.random(-2, 2)
		)
		dustCloud.Anchored = true
		dustCloud.CanCollide = false
		dustCloud.Material = Enum.Material.SmoothPlastic
		dustCloud.Color = Color3.fromRGB(140 + i * 10, 130 + i * 10, 120 + i * 5)
		dustCloud.Transparency = 0.6 + i * 0.05
		dustCloud.Parent = workspace

		local dustMesh = Instance.new("SpecialMesh")
		dustMesh.MeshType = Enum.MeshType.Sphere
		dustMesh.Parent = dustCloud

		TweenService:Create(dustCloud, TweenInfo.new(1.5 + i * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(22 + i * 5, 10 + i * 3, 22 + i * 5),
			Transparency = 1,
			CFrame = dustCloud.CFrame * CFrame.new(0, 4 + i, 0)
		}):Play()

		Debris:AddItem(dustCloud, 2 + i * 0.3)
	end

	local flash = Instance.new("Part")
	flash.Size = Vector3.new(20, 20, 20)
	flash.CFrame = slamPosition
	flash.Anchored = true
	flash.CanCollide = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 220, 100)
	flash.Transparency = 0.3
	flash.Parent = workspace

	local flashMesh = Instance.new("SpecialMesh")
	flashMesh.MeshType = Enum.MeshType.Sphere
	flashMesh.Parent = flash

	TweenService:Create(flash, TweenInfo.new(0.15), {
		Size = Vector3.new(35, 35, 35),
		Transparency = 1
	}):Play()

	Debris:AddItem(flash, 0.2)
end

function GroundSlam:OnActivate(player, character, rootPart, GetTargetsInRange, GetTargetsInCone, ApplyDamage)
	print("💥 " .. player.Name .. " used Ground Slam!")

	local targets = GetTargetsInRange(rootPart.Position, self.Range, character)
	for _, target in ipairs(targets) do
		ApplyDamage(target, self.Damage, {
			Horizontal = 35,
			Vertical = 45
		}, rootPart)
	end
	local shockwave = Instance.new("Part")
	shockwave.Size = Vector3.new(self.Range * 2, 1, self.Range * 2)
	shockwave.Position = rootPart.Position - Vector3.new(0, 3, 0)
	shockwave.Anchored = true
	shockwave.CanCollide = false
	shockwave.Transparency = 0.7
	shockwave.Color = Color3.fromRGB(139, 69, 19)
	shockwave.Material = Enum.Material.Slate
	shockwave.Parent = workspace

	local mesh = Instance.new("CylinderMesh")
	mesh.Parent = shockwave

	task.spawn(function()
		for i = 1, 20 do
			shockwave.Transparency = shockwave.Transparency + 0.015
			shockwave.Size = shockwave.Size + Vector3.new(2, 0, 2)
			task.wait(0.05)
		end
		shockwave:Destroy()
	end)

	return true, targets
end

return GroundSlam