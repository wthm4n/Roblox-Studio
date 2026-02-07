local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local BaseAbility = require(ReplicatedStorage.Modules.Combat.Abilities.BaseAbility)

local DashStrike = BaseAbility.new({
	Name = "Dash Strike",
	Description = "Blitz forward with lightning speed",
	Cooldown = 5,
	Damage = 20,
	Range = 5,
	AnimationId = "rbxassetid://125062631276156",
	AnimationDuration = 0.8,
	Icon = "rbxassetid://0",
	VFXName = "ability4"
})

function DashStrike:PlayVFX(rootPart, vfx)
	local dashDuration = 0.6

	local vfxClone = vfx:Clone()
	vfxClone.Parent = rootPart

	self:EnableContinuousVFX(vfxClone, dashDuration)

	Debris:AddItem(vfxClone, dashDuration + 0.5)

	local blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = workspace.CurrentCamera

	TweenService:Create(blur, TweenInfo.new(0.08), {
		Size = 15
	}):Play()

	task.delay(dashDuration, function()
		TweenService:Create(blur, TweenInfo.new(0.25), {
			Size = 0
		}):Play()
		Debris:AddItem(blur, 0.3)
	end)

	for i = 1, 8 do
		task.delay(i * (dashDuration / 8), function()
			if rootPart.Parent then
				local afterimage = Instance.new("Part")
				afterimage.Size = Vector3.new(2.5, 3, 1.5)
				afterimage.CFrame = rootPart.CFrame
				afterimage.Anchored = true
				afterimage.CanCollide = false
				afterimage.Material = Enum.Material.Neon
				afterimage.Color = Color3.fromRGB(100 + i * 15, 180 + i * 8, 255)
				afterimage.Transparency = 0.5 + (i * 0.04)
				afterimage.Parent = workspace

				TweenService:Create(afterimage, TweenInfo.new(0.35), {
					Transparency = 1,
					Size = Vector3.new(3, 3.5, 1.8)
				}):Play()

				Debris:AddItem(afterimage, 0.4)
			end
		end)
	end

	for side = -1, 1, 2 do
		for i = 1, 6 do
			task.delay(i * (dashDuration / 6), function()
				if rootPart.Parent then
					local streak = Instance.new("Part")
					streak.Size = Vector3.new(0.8, 0.4, 6)
					streak.CFrame = rootPart.CFrame * CFrame.new(side * (2.5 + i * 0.2), 0, -3)
					streak.Anchored = true
					streak.CanCollide = false
					streak.Material = Enum.Material.Neon
					streak.Color = Color3.fromRGB(80 + i * 10, 150 + i * 10, 255)
					streak.Transparency = 0.3
					streak.Parent = workspace

					task.spawn(function()
						for j = 1, 12 do
							if streak.Parent then
								streak.CFrame = streak.CFrame * CFrame.new(0, 0, 2.5)
								streak.Transparency = streak.Transparency + 0.06
							end
							task.wait(0.025)
						end
						streak:Destroy()
					end)
				end
			end)
		end
	end

	local trailPart = Instance.new("Part")
	trailPart.Size = Vector3.new(2, 2, 2)
	trailPart.Transparency = 1
	trailPart.CanCollide = false
	trailPart.Anchored = false
	trailPart.Parent = rootPart

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = trailPart
	weld.Parent = trailPart

	local trail = Instance.new("Trail")
	trail.Lifetime = 0.5
	trail.MinLength = 0
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(120, 200, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1)
	})
	trail.WidthScale = NumberSequence.new(1)

	local att0 = Instance.new("Attachment")
	att0.Parent = rootPart
	att0.Position = Vector3.new(0, 1, 0)

	local att1 = Instance.new("Attachment")
	att1.Parent = rootPart
	att1.Position = Vector3.new(0, -1, 0)

	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Parent = trailPart

	Debris:AddItem(trailPart, dashDuration + 0.5)

	for i = 1, 10 do
		task.delay(i * (dashDuration / 10), function()
			if rootPart.Parent then
				local spark = Instance.new("Part")
				spark.Size = Vector3.new(1, 1, 1)
				spark.CFrame = rootPart.CFrame * CFrame.new(
					math.random(-2, 2),
					math.random(-1, 2),
					math.random(-2, 2)
				)
				spark.Anchored = true
				spark.CanCollide = false
				spark.Material = Enum.Material.Neon
				spark.Color = Color3.fromRGB(200, 230, 255)
				spark.Transparency = 0.2
				spark.Parent = workspace

				local sparkMesh = Instance.new("SpecialMesh")
				sparkMesh.MeshType = Enum.MeshType.Sphere
				sparkMesh.Parent = spark

				TweenService:Create(spark, TweenInfo.new(0.15), {
					Size = Vector3.new(0.3, 0.3, 0.3),
					Transparency = 1
				}):Play()

				Debris:AddItem(spark, 0.2)
			end
		end)
	end

	task.delay(dashDuration, function()
		if rootPart.Parent then
			local burst = Instance.new("Part")
			burst.Size = Vector3.new(6, 6, 2)
			burst.CFrame = rootPart.CFrame
			burst.Anchored = true
			burst.CanCollide = false
			burst.Material = Enum.Material.Neon
			burst.Color = Color3.fromRGB(150, 220, 255)
			burst.Transparency = 0.2
			burst.Parent = workspace

			local burstMesh = Instance.new("SpecialMesh")
			burstMesh.MeshType = Enum.MeshType.Sphere
			burstMesh.Parent = burst

			TweenService:Create(burst, TweenInfo.new(0.3), {
				Size = Vector3.new(12, 12, 4),
				Transparency = 1
			}):Play()

			Debris:AddItem(burst, 0.4)

			self:CreateShockwave(rootPart.CFrame, {
				StartSize = Vector3.new(4, 0.5, 4),
				EndSize = Vector3.new(14, 0.3, 14),
				Color = Color3.fromRGB(120, 200, 255),
				Duration = 0.35,
				Transparency = 0.5,
				MeshType = Enum.MeshType.Sphere
			})

			for i = 1, 8 do
				local fragment = Instance.new("Part")
				fragment.Size = Vector3.new(0.6, 1.2, 0.6)
				fragment.CFrame = rootPart.CFrame
				fragment.Material = Enum.Material.Neon
				fragment.Color = Color3.fromRGB(150, 220, 255)
				fragment.Transparency = 0.3
				fragment.CanCollide = false
				fragment.Parent = workspace

				local bodyVelocity = Instance.new("BodyVelocity")
				bodyVelocity.MaxForce = Vector3.new(50000, 50000, 50000)
				bodyVelocity.Velocity = Vector3.new(
					math.random(-35, 35),
					math.random(10, 40),
					math.random(-35, 35)
				)
				bodyVelocity.Parent = fragment

				task.delay(0.1, function()
					if bodyVelocity.Parent then bodyVelocity:Destroy() end
				end)

				TweenService:Create(fragment, TweenInfo.new(0.5), {
					Transparency = 1,
					Size = Vector3.new(0.2, 0.6, 0.2)
				}):Play()

				Debris:AddItem(fragment, 0.6)
			end
		end
	end)
end

function DashStrike:OnActivate(player, character, rootPart, GetTargetsInRange, GetTargetsInCone, ApplyDamage)
	print("💨 " .. player.Name .. " used Dash Strike!")

	local direction = rootPart.CFrame.LookVector

	-- Dash player forward
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(100000, 0, 100000)
	bodyVelocity.Velocity = direction * 150
	bodyVelocity.Parent = rootPart

	game:GetService("Debris"):AddItem(bodyVelocity, 0.3)

	local targets = {}
	task.spawn(function()
		for i = 1, 6 do
			local nearbyTargets = GetTargetsInRange(rootPart.Position, self.Range, character)

			for _, target in ipairs(nearbyTargets) do
				-- Only hit each target once
				local alreadyHit = false
				for _, hitTarget in ipairs(targets) do
					if hitTarget == target then
						alreadyHit = true
						break
					end
				end

				if not alreadyHit then
					table.insert(targets, target)
					ApplyDamage(target, self.Damage, {
						Horizontal = 65,
						Vertical = 35
					}, rootPart)
				end
			end

			task.wait(0.05)
		end
	end)

	return true, targets
end

return DashStrike