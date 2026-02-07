local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local BaseAbility = {}
BaseAbility.__index = BaseAbility

function BaseAbility.new(config)
	local self = setmetatable({}, BaseAbility)

	self.Name = config.Name or "Unnamed Ability"
	self.Description = config.Description or ""
	self.Cooldown = config.Cooldown or 5
	self.Damage = config.Damage or 20
	self.Range = config.Range or 15
	self.AnimationId = config.AnimationId or ""
	self.AnimationDuration = config.AnimationDuration or 1.0
	self.Icon = config.Icon or "rbxassetid://0"
	self.VFXName = config.VFXName or ""

	-- Functions (to be overridden by specific abilities)
	self.OnActivate = config.OnActivate or function() end
	self.PlayVFX = config.PlayVFX or function() end
	self.CreateDebris = config.CreateDebris or function() end

	return self
end

function BaseAbility:SpawnDebris(position, debrisConfig)
	local debris = Instance.new("Part")
	debris.Name = debrisConfig.Name or "Debris"
	debris.Size = debrisConfig.Size or Vector3.new(2, 2, 2)
	debris.CFrame = position * CFrame.new(
		math.random(-5, 5),
		math.random(0, 2),
		math.random(-5, 5)
	)
	debris.Material = debrisConfig.Material or Enum.Material.Slate
	debris.Color = debrisConfig.Color or Color3.fromRGB(100, 100, 100)
	debris.CanCollide = true
	debris.Parent = workspace

	debris.CFrame = debris.CFrame * CFrame.Angles(
		math.rad(math.random(0, 360)),
		math.rad(math.random(0, 360)),
		math.rad(math.random(0, 360))
	)

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(50000, 50000, 50000)
	bodyVelocity.Velocity = debrisConfig.Velocity or Vector3.new(
		math.random(-30, 30),
		math.random(40, 70),
		math.random(-30, 30)
	)
	bodyVelocity.Parent = debris

	local bodyAngularVelocity = Instance.new("BodyAngularVelocity")
	bodyAngularVelocity.MaxTorque = Vector3.new(50000, 50000, 50000)
	bodyAngularVelocity.AngularVelocity = Vector3.new(
		math.random(-10, 10),
		math.random(-10, 10),
		math.random(-10, 10)
	)
	bodyAngularVelocity.Parent = debris

	task.delay(0.2, function()
		if bodyVelocity.Parent then bodyVelocity:Destroy() end
		if bodyAngularVelocity.Parent then bodyAngularVelocity:Destroy() end
	end)

	task.delay(1.5, function()
		if debris.Parent then
			TweenService:Create(debris, TweenInfo.new(1), {
				Transparency = 1
			}):Play()
		end
	end)

	Debris:AddItem(debris, 2.5)

	return debris
end

function BaseAbility:CreateShockwave(position, config)
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

	TweenService:Create(shockwave, TweenInfo.new(
		config.Duration or 0.5,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
		), {
			Size = config.EndSize or Vector3.new(30, 15, 30),
			Transparency = 1
		}):Play()

	Debris:AddItem(shockwave, (config.Duration or 0.5) + 0.1)

	return shockwave
end

function BaseAbility:EmitParticles(vfxClone, emitCount)
	for _, descendant in pairs(vfxClone:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			local count = descendant:GetAttribute("EmitCount") or emitCount or 50
			descendant:Emit(count)
		elseif descendant:IsA("Beam") then
			descendant.Enabled = true
			task.delay(1, function()
				if descendant then descendant.Enabled = false end
			end)
		end
	end
end

function BaseAbility:EnableContinuousVFX(vfxClone, duration)
	for _, descendant in pairs(vfxClone:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = true
		elseif descendant:IsA("Beam") then
			descendant.Enabled = true
		elseif descendant:IsA("Trail") then
			descendant.Enabled = true
		end
	end

	task.delay(duration, function()
		for _, descendant in pairs(vfxClone:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then
				descendant.Enabled = false
			elseif descendant:IsA("Beam") then
				descendant.Enabled = false
			elseif descendant:IsA("Trail") then
				descendant.Enabled = false
			end
		end
	end)
end

return BaseAbility