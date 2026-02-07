
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local BaseAbility = require(ReplicatedStorage.Modules.Combat.Abilities.BaseAbility)

local CrushingBlow = BaseAbility.new({
	Name = "Crushing Blow",
	Description = "Leap up and slam down with earth-shattering force",
	Cooldown = 8,
	Damage = 40,
	Range = 25,
	AnimationId = "rbxassetid://110375425721763",
	AnimationDuration = 0.8,
	Icon = "rbxassetid://0",
	VFXName = "crushingblow"
})

function CrushingBlow:PlayVFX(rootPart, vfx)
	local impactPoint = rootPart.CFrame * CFrame.new(0, -3, -8) -- Slam point in front

	local flash = Instance.new("Part")
	flash.Size = Vector3.new(50, 50, 50)
	flash.CFrame = impactPoint
	flash.Anchored = true
	flash.CanCollide = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 255, 255)
	flash.Transparency = 0.3
	flash.Shape = Enum.PartType.Ball
	flash.Parent = workspace

	TweenService:Create(flash, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(80, 80, 80),
		Transparency = 1
	}):Play()
	Debris:AddItem(flash, 0.2)
	local shockwave = Instance.new("Part")
	shockwave.Size = Vector3.new(20, 0.5, 20)
	shockwave.CFrame = impactPoint * CFrame.Angles(0, 0, 0)
	shockwave.Anchored = true
	shockwave.CanCollide = false
	shockwave.Material = Enum.Material.SmoothPlastic
	shockwave.Color = Color3.fromRGB(200, 200, 200)
	shockwave.Transparency = 0.2
	shockwave.Parent = workspace

	local shockMesh = Instance.new("SpecialMesh")
	shockMesh.MeshType = Enum.MeshType.Cylinder
	shockMesh.Parent = shockwave

	shockwave.CFrame = shockwave.CFrame * CFrame.Angles(0, 0, math.rad(90))

	TweenService:Create(shockwave, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(60, 0.5, 60),
		Transparency = 1
	}):Play()
	Debris:AddItem(shockwave, 0.5)
	task.delay(0.1, function()
		local wave2 = Instance.new("Part")
		wave2.Size = Vector3.new(25, 0.3, 25)
		wave2.CFrame = impactPoint
		wave2.Anchored = true
		wave2.CanCollide = false
		wave2.Material = Enum.Material.SmoothPlastic
		wave2.Color = Color3.fromRGB(180, 180, 180)
		wave2.Transparency = 0.4
		wave2.Parent = workspace

		local wave2Mesh = Instance.new("SpecialMesh")
		wave2Mesh.MeshType = Enum.MeshType.Cylinder
		wave2Mesh.Parent = wave2

		wave2.CFrame = wave2.CFrame * CFrame.Angles(0, 0, math.rad(90))

		TweenService:Create(wave2, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(70, 0.3, 70),
			Transparency = 1
		}):Play()
		Debris:AddItem(wave2, 0.6)
	end)
	local crater = Instance.new("Part")
	crater.Size = Vector3.new(18, 0.1, 18)
	crater.CFrame = impactPoint * CFrame.new(0, -0.5, 0)
	crater.Anchored = true
	crater.CanCollide = false
	crater.Material = Enum.Material.Slate
	crater.Color = Color3.fromRGB(60, 60, 60)
	crater.Transparency = 0.3
	crater.Parent = workspace

	local craterMesh = Instance.new("SpecialMesh")
	craterMesh.MeshType = Enum.MeshType.Cylinder
	craterMesh.Parent = crater

	crater.CFrame = crater.CFrame * CFrame.Angles(0, 0, math.rad(90))
	TweenService:Create(crater, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1
	}):Play()
	Debris:AddItem(crater, 3)
	for i = 1, 4 do
		local angle = math.rad(i * 90)
		local dustOffset = Vector3.new(math.cos(angle) * 8, 1, math.sin(angle) * 8)

		local dust = Instance.new("Part")
		dust.Size = Vector3.new(4, 4, 4)
		dust.CFrame = impactPoint * CFrame.new(dustOffset)
		dust.Anchored = true
		dust.CanCollide = false
		dust.Material = Enum.Material.SmoothPlastic
		dust.Color = Color3.fromRGB(150, 150, 150)
		dust.Transparency = 0.5
		dust.Shape = Enum.PartType.Ball
		dust.Parent = workspace

		TweenService:Create(dust, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(10, 10, 10),
			Transparency = 1,
			Position = dust.Position + Vector3.new(dustOffset.X * 0.5, 4, dustOffset.Z * 0.5)
		}):Play()
		Debris:AddItem(dust, 0.7)
	end

	for i = 1, 12 do
		local rock = Instance.new("Part")
		rock.Size = Vector3.new(
			math.random(10, 20) / 10,
			math.random(10, 25) / 10,
			math.random(10, 20) / 10
		)
		rock.CFrame = impactPoint * CFrame.new(
			math.random(-10, 10),
			0,
			math.random(-10, 10)
		) * CFrame.Angles(
			math.rad(math.random(0, 360)),
			math.rad(math.random(0, 360)),
			math.rad(math.random(0, 360))
		)
		rock.Material = Enum.Material.Slate
		rock.Color = Color3.fromRGB(
			math.random(70, 100),
			math.random(70, 100),
			math.random(70, 100)
		)
		rock.CanCollide = false
		rock.Parent = workspace

		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(50000, 50000, 50000)
		bv.Velocity = Vector3.new(
			math.random(-20, 20),
			math.random(25, 45),
			math.random(-20, 20)
		)
		bv.Parent = rock

		local av = Instance.new("BodyAngularVelocity")
		av.MaxTorque = Vector3.new(50000, 50000, 50000)
		av.AngularVelocity = Vector3.new(
			math.random(-10, 10),
			math.random(-10, 10),
			math.random(-10, 10)
		)
		av.Parent = rock

		task.delay(0.1, function()
			if bv.Parent then bv:Destroy() end
			if av.Parent then av:Destroy() end
			rock.Anchored = false 
		end)

		task.delay(0.8, function()
			TweenService:Create(rock, TweenInfo.new(0.4), {
				Transparency = 1
			}):Play()
		end)

		Debris:AddItem(rock, 1.3)
	end

	for i = 1, 8 do
		local angle = math.rad(i * 45)
		local lineStart = impactPoint.Position + Vector3.new(
			math.cos(angle) * 5,
			0.5,
			math.sin(angle) * 5
		)
		local lineEnd = lineStart + Vector3.new(
			math.cos(angle) * 15,
			0,
			math.sin(angle) * 15
		)

		local line = Instance.new("Part")
		line.Size = Vector3.new(0.4, 0.4, 15)
		line.CFrame = CFrame.new(lineStart, lineEnd) * CFrame.new(0, 0, -7.5)
		line.Anchored = true
		line.CanCollide = false
		line.Material = Enum.Material.Neon
		line.Color = Color3.fromRGB(255, 200, 100)
		line.Transparency = 0.2
		line.Parent = workspace

		TweenService:Create(line, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.2, 0.2, 20),
			Transparency = 1
		}):Play()
		Debris:AddItem(line, 0.3)
	end

	local windBurst = Instance.new("Part")
	windBurst.Size = Vector3.new(15, 0.2, 15)
	windBurst.CFrame = impactPoint * CFrame.new(0, 0.5, 0)
	windBurst.Anchored = true
	windBurst.CanCollide = false
	windBurst.Material = Enum.Material.SmoothPlastic
	windBurst.Color = Color3.fromRGB(220, 220, 220)
	windBurst.Transparency = 0.6
	windBurst.Parent = workspace

	local burstMesh = Instance.new("SpecialMesh")
	burstMesh.MeshType = Enum.MeshType.Cylinder
	burstMesh.Parent = windBurst

	windBurst.CFrame = windBurst.CFrame * CFrame.Angles(0, 0, math.rad(90))

	TweenService:Create(windBurst, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(55, 0.2, 55),
		Transparency = 1
	}):Play()
	Debris:AddItem(windBurst, 0.4)
end

function CrushingBlow:OnActivate(player, character, rootPart, GetTargetsInRange, GetTargetsInCone, ApplyDamage)
	print("💥 " .. player.Name .. " used CRUSHING BLOW!")

	local impactPoint = rootPart.CFrame * CFrame.new(0, -3, -8)

	local targets = GetTargetsInRange(impactPoint.Position, self.Range, character)

	for _, target in ipairs(targets) do
		local targetRoot = target:FindFirstChild("HumanoidRootPart")
		if targetRoot then
			local direction = (targetRoot.Position - impactPoint.Position).Unit

			ApplyDamage(target, self.Damage, {
				Horizontal = 85,
				Vertical = 50,
				Direction = direction
			}, rootPart)
		end
	end

	return true, targets
end

return CrushingBlow