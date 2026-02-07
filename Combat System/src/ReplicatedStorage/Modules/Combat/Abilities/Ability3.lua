local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local BaseAbility = require(ReplicatedStorage.Abilities.BaseAbility)

local Uppercut = BaseAbility.new({
	Name = "Uppercut",
	Description = "Launch enemies skyward with explosive force",
	Cooldown = 10,
	Damage = 35,
	Range = 8,
	AnimationId = "rbxassetid://90994364743448",
	AnimationDuration = 1.5,
	Icon = "rbxassetid://0",
	VFXName = "ability3"
})

function Uppercut:PlayVFX(rootPart, vfx)
	local launchPosition = rootPart.CFrame

	local vfxClone = vfx:Clone()
	vfxClone.Parent = rootPart

	self:EmitParticles(vfxClone, 60)

	Debris:AddItem(vfxClone, 2)

	local pillar = Instance.new("Part")
	pillar.Size = Vector3.new(7, 2, 7)
	pillar.CFrame = launchPosition
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = Color3.fromRGB(255, 230, 0)
	pillar.Transparency = 0.3
	pillar.Parent = workspace

	local pillarMesh = Instance.new("CylinderMesh")
	pillarMesh.Parent = pillar

	TweenService:Create(pillar, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(9, 40, 9),
		CFrame = pillar.CFrame * CFrame.new(0, 20, 0),
		Transparency = 1
	}):Play()

	Debris:AddItem(pillar, 0.8)

	local burst = Instance.new("Part")
	burst.Size = Vector3.new(5, 5, 5)
	burst.CFrame = launchPosition
	burst.Anchored = true
	burst.CanCollide = false
	burst.Material = Enum.Material.Neon
	burst.Color = Color3.fromRGB(255, 200, 50)
	burst.Transparency = 0.2
	burst.Parent = workspace

	local burstMesh = Instance.new("SpecialMesh")
	burstMesh.MeshType = Enum.MeshType.Sphere
	burstMesh.Parent = burst

	TweenService:Create(burst, TweenInfo.new(0.35), {
		Size = Vector3.new(16, 16, 16),
		Transparency = 1
	}):Play()

	Debris:AddItem(burst, 0.4)

	for i = 1, 3 do
		task.delay(i * 0.08, function()
			local ring = Instance.new("Part")
			ring.Size = Vector3.new(10, 0.5, 10)
			ring.CFrame = launchPosition * CFrame.new(0, i * 1.5, 0)
			ring.Anchored = true
			ring.CanCollide = false
			ring.Material = Enum.Material.Neon
			ring.Color = Color3.fromRGB(255, 200 - i * 30, 0)
			ring.Transparency = 0.4
			ring.Parent = workspace

			local ringMesh = Instance.new("SpecialMesh")
			ringMesh.MeshType = Enum.MeshType.FileMesh
			ringMesh.MeshId = "rbxassetid://3270017"
			ringMesh.Scale = Vector3.new(3, 3, 3)
			ringMesh.Parent = ring

			task.spawn(function()
				for j = 1, 18 do
					if ring.Parent then
						ring.CFrame = ring.CFrame * CFrame.Angles(0, math.rad(18), 0) * CFrame.new(0, 0.8, 0)
						ring.Transparency = ring.Transparency + 0.035
						ring.Size = ring.Size + Vector3.new(0.5, 0, 0.5)
					end
					task.wait(0.04)
				end
				ring:Destroy()
			end)
		end)
	end

	for i = 1, 12 do
		task.delay(i * 0.03, function()
			local shard = Instance.new("Part")
			shard.Size = Vector3.new(0.8, 2.5, 0.8)
			shard.CFrame = launchPosition * CFrame.new(
				math.random(-3, 3),
				0,
				math.random(-3, 3)
			)
			shard.Material = Enum.Material.Neon
			shard.Color = Color3.fromRGB(255, 220, math.random(0, 100))
			shard.Transparency = 0.2
			shard.CanCollide = false
			shard.Anchored = false
			shard.Parent = workspace

			shard.CFrame = shard.CFrame * CFrame.Angles(
				math.rad(math.random(0, 360)),
				math.rad(math.random(0, 360)),
				0
			)

			local bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.MaxForce = Vector3.new(10000, 50000, 10000)
			bodyVelocity.Velocity = Vector3.new(
				math.random(-15, 15),
				math.random(60, 100),
				math.random(-15, 15)
			)
			bodyVelocity.Parent = shard

			local angularVelocity = Instance.new("BodyAngularVelocity")
			angularVelocity.MaxTorque = Vector3.new(50000, 50000, 50000)
			angularVelocity.AngularVelocity = Vector3.new(
				math.random(-10, 10),
				math.random(-10, 10),
				math.random(-10, 10)
			)
			angularVelocity.Parent = shard

			task.delay(0.15, function()
				if bodyVelocity.Parent then bodyVelocity:Destroy() end
				if angularVelocity.Parent then angularVelocity:Destroy() end
			end)

			TweenService:Create(shard, TweenInfo.new(0.8), {
				Transparency = 1,
				Size = Vector3.new(0.3, 1, 0.3)
			}):Play()

			Debris:AddItem(shard, 1)
		end)
	end

	for i = 1, 8 do
		self:SpawnDebris(launchPosition, {
			Name = "LaunchedRock",
			Size = Vector3.new(
				math.random(12, 25) / 10,
				math.random(12, 25) / 10,
				math.random(12, 25) / 10
			),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(
				math.random(60, 100),
				math.random(50, 80),
				math.random(40, 70)
			),
			Velocity = Vector3.new(
				math.random(-25, 25),
				math.random(70, 110),
				math.random(-25, 25)
			)
		})
	end

	local dustCloud = Instance.new("Part")
	dustCloud.Size = Vector3.new(10, 6, 10)
	dustCloud.CFrame = launchPosition * CFrame.new(0, 1, 0)
	dustCloud.Anchored = true
	dustCloud.CanCollide = false
	dustCloud.Material = Enum.Material.SmoothPlastic
	dustCloud.Color = Color3.fromRGB(150, 140, 130)
	dustCloud.Transparency = 0.65
	dustCloud.Parent = workspace

	local dustMesh = Instance.new("SpecialMesh")
	dustMesh.MeshType = Enum.MeshType.Sphere
	dustMesh.Parent = dustCloud

	TweenService:Create(dustCloud, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(18, 14, 18),
		Transparency = 1,
		CFrame = dustCloud.CFrame * CFrame.new(0, 8, 0)
	}):Play()

	Debris:AddItem(dustCloud, 1.3)

	self:CreateShockwave(launchPosition, {
		StartSize = Vector3.new(6, 1, 6),
		EndSize = Vector3.new(20, 0.5, 20),
		Color = Color3.fromRGB(255, 200, 0),
		Duration = 0.4,
		Transparency = 0.4,
		MeshType = Enum.MeshType.Sphere
	})
end

function Uppercut:OnActivate(player, character, rootPart, GetTargetsInRange, GetTargetsInCone, ApplyDamage)
	print("👊 " .. player.Name .. " used Uppercut!")

	local direction = rootPart.CFrame.LookVector

	local targets = GetTargetsInCone(
		rootPart.Position,
		direction,
		self.Range,
		60,
		character
	)

	for _, target in ipairs(targets) do
		ApplyDamage(target, self.Damage, {
			Horizontal = 25,
			Vertical = 90 
		}, rootPart)

		local targetHumanoid = target:FindFirstChild("Humanoid")
		if targetHumanoid then
			targetHumanoid.WalkSpeed = 0
			targetHumanoid.JumpPower = 0
			task.delay(1, function()
				if targetHumanoid.Parent then
					targetHumanoid.WalkSpeed = 16
					targetHumanoid.JumpPower = 50
				end
			end)
		end
	end

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(0, 100000, 0)
	bodyVelocity.Velocity = Vector3.new(0, 65, 0)
	bodyVelocity.Parent = rootPart
	game:GetService("Debris"):AddItem(bodyVelocity, 0.3)

	return true, targets
end

return Uppercut