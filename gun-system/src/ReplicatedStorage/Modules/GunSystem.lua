--[[
	GunSystem Module
	Main gun system handler - Place in ReplicatedStorage
	
	Handles:
	- Gun creation and initialization
	- Raycast bullet system (hitscan)
	- Damage calculation with falloff
	- Magazine and ammo management
	- Fire rate control
	- Recoil patterns
	- Server-to-client communication for VFX
]]

local GunSystem = {}
GunSystem.__index = GunSystem

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Remote Events (create these in ReplicatedStorage > GunRemotes folder)
local function getOrCreateRemotes()
	local remoteFolder = ReplicatedStorage:FindFirstChild("GunRemotes")
	if not remoteFolder then
		remoteFolder = Instance.new("Folder")
		remoteFolder.Name = "GunRemotes"
		remoteFolder.Parent = ReplicatedStorage
	end

	local function getOrCreateRemote(name, className)
		local remote = remoteFolder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = remoteFolder
		end
		return remote
	end

	return {
		FireGun = getOrCreateRemote("FireGun", "RemoteEvent"),
		ReloadGun = getOrCreateRemote("ReloadGun", "RemoteEvent"),
		PlayEffect = getOrCreateRemote("PlayEffect", "RemoteEvent"),
		UpdateAmmo = getOrCreateRemote("UpdateAmmo", "RemoteEvent"),
		EquipGun = getOrCreateRemote("EquipGun", "RemoteEvent"),
		UnequipGun = getOrCreateRemote("UnequipGun", "RemoteEvent"),
	}
end

local Remotes = getOrCreateRemotes()

-- Default gun configuration
local DEFAULT_CONFIG = {
	-- Damage
	BaseDamage = 30,
	HeadshotMultiplier = 2.0,
	DamageFalloffStart = 50, -- studs
	DamageFalloffEnd = 150, -- studs
	MinDamage = 10, -- minimum damage at max range

	-- Fire Rate
	FireRate = 600, -- RPM (Rounds Per Minute)
	FireMode = "Auto", -- "Auto", "Semi", "Burst"
	BurstCount = 3,
	BurstDelay = 0.1,

	-- Ammo
	MagazineSize = 30,
	ReserveAmmo = 90,
	ReloadTimeTactical = 2.0, -- reload with bullet in chamber
	ReloadTimeEmpty = 2.5, -- reload from empty

	-- Recoil Pattern (vertical, horizontal)
	RecoilPattern = {
		{ 0.3, 0.1 }, -- Shot 1
		{ 0.35, -0.05 }, -- Shot 2
		{ 0.4, 0.15 }, -- Shot 3
		{ 0.38, -0.1 }, -- Shot 4
		{ 0.42, 0.2 }, -- Shot 5
		{ 0.45, -0.15 }, -- Shot 6
		{ 0.4, 0.1 }, -- Shot 7
		{ 0.38, -0.05 }, -- Shot 8
		{ 0.4, 0.12 }, -- Shot 9
		{ 0.43, -0.08 }, -- Shot 10
	},
	RecoilRecovery = 0.1, -- time to recover recoil

	-- Bloom/Spread
	BaseSpread = 0.5, -- degrees
	SpreadIncrease = 0.2, -- per shot
	MaxSpread = 3.0, -- max spread
	SpreadRecovery = 0.15, -- recovery per second

	-- Range
	MaxRange = 500, -- studs

	-- Animations (Animation IDs)
	Animations = {
		Idle = 0,
		Walk = 0,
		Fire = 0,
		ReloadTactical = 0,
		ReloadEmpty = 0,
	},

	-- Gun Info
	GunName = "Pistol",
	GunImage = "rbxassetid://0", -- ImageLabel asset

	-- Assets (Sounds & Effects)
	Assets = {
		-- Sounds
		FireSound = nil, -- Sound instance or asset path
		ReloadSound = nil,
		EmptyClickSound = nil,
		ShellEjectSound = nil,

		-- VFX (Optional - override defaults)
		MuzzleFlash = nil, -- ParticleEmitter or path to particle
		BulletTracer = nil, -- Beam or path to beam
		HitEffect = nil, -- ParticleEmitter or path
		ShellCasing = nil, -- Part or MeshPart for shell ejection
	},
}

-- Create new gun instance
function GunSystem.new(config)
	local self = setmetatable({}, GunSystem)

	-- Deep copy defaults first
	self.Config = table.clone(DEFAULT_CONFIG)

	-- Proper deep merge
	for key, value in pairs(config) do
		if type(value) == "table" and type(self.Config[key]) == "table" then
			for subKey, subValue in pairs(value) do
				self.Config[key][subKey] = subValue
			end
		else
			self.Config[key] = value
		end
	end

	-- Gun state
	self.CurrentAmmo = self.Config.MagazineSize
	self.ReserveAmmo = self.Config.ReserveAmmo
	self.IsReloading = false
	self.LastFireTime = 0
	self.CurrentRecoilIndex = 1
	self.CurrentSpread = self.Config.BaseSpread
	self.BurstShotsFired = 0

	-- Calculate fire delay from RPM
	self.FireDelay = 60 / self.Config.FireRate

	-- Tool references (set when equipped)
	self.Tool = nil
	self.Player = nil
	self.Character = nil
	self.Humanoid = nil
	self.Muzzle = nil
	self.Handle = nil

	return self
end

-- Initialize gun when tool is equipped
function GunSystem:Initialize(tool, player)
	self.Tool = tool
	self.Player = player
	self.Character = player.Character or player.CharacterAdded:Wait()
	self.Humanoid = self.Character:WaitForChild("Humanoid")

	-- Get gun parts
	self.Handle = tool:FindFirstChild("Handle")
	self.Muzzle = tool:FindFirstChild("Muzzle")
	self.EjectionPort = tool:FindFirstChild("EjectionPort") or self.Muzzle

	if not self.Muzzle then
		warn("Gun missing Muzzle part!")
	end

	-- Reset ammo to full on equip
	self.CurrentAmmo = self.Config.MagazineSize
	self.IsReloading = false

	-- Send equip event to client
	Remotes.EquipGun:FireClient(player, self.Config)
	self:UpdateAmmoUI()
end

-- Fire the gun
function GunSystem:Fire(targetPosition)
	if not self.Tool or not self.Character then
		return false
	end

	-- Check if can fire
	local currentTime = tick()
	if currentTime - self.LastFireTime < self.FireDelay then
		return false
	end

	if self.IsReloading then
		return false
	end

	if self.CurrentAmmo <= 0 then
		-- Play empty click sound
		Remotes.PlayEffect:FireClient(self.Player, "EmptyClick")
		return false
	end

	-- Handle burst mode
	if self.Config.FireMode == "Burst" then
		if self.BurstShotsFired >= self.Config.BurstCount then
			if currentTime - self.LastFireTime < self.Config.BurstDelay then
				return false
			end
			self.BurstShotsFired = 0
		end
	end

	-- Update fire time
	self.LastFireTime = currentTime

	-- Consume ammo
	self.CurrentAmmo = self.CurrentAmmo - 1

	-- Perform raycast
	local hitResult = self:PerformRaycast(targetPosition)

	-- Update recoil index
	self.CurrentRecoilIndex = self.CurrentRecoilIndex + 1
	if self.CurrentRecoilIndex > #self.Config.RecoilPattern then
		self.CurrentRecoilIndex = 1
	end

	-- Increase spread
	self.CurrentSpread = math.min(self.CurrentSpread + self.Config.SpreadIncrease, self.Config.MaxSpread)

	-- Update burst counter
	if self.Config.FireMode == "Burst" then
		self.BurstShotsFired = self.BurstShotsFired + 1
	end

	-- Get recoil for this shot
	local recoilData = self.Config.RecoilPattern[self.CurrentRecoilIndex] or { 0.3, 0 }

	-- Send fire event to client for VFX
	Remotes.PlayEffect:FireClient(self.Player, "Fire", {
		MuzzlePosition = self.Muzzle and self.Muzzle.Position or Vector3.new(),
		HitResult = hitResult,
		Recoil = recoilData,
		Spread = self.CurrentSpread,
	})

	-- Update ammo UI
	self:UpdateAmmoUI()

	return true
end

-- Perform hitscan raycast
function GunSystem:PerformRaycast(targetPosition)
	if not self.Muzzle or not self.Character then
		return nil
	end

	local origin = self.Muzzle.Position
	local direction = (targetPosition - origin).Unit

	-- Apply spread
	local spreadAngle = math.rad(self.CurrentSpread)
	local randomX = (math.random() - 0.5) * spreadAngle * 2
	local randomY = (math.random() - 0.5) * spreadAngle * 2

	-- Rotate direction by spread
	local spreadDirection = CFrame.new(Vector3.new(), direction) * CFrame.Angles(randomY, randomX, 0)
	direction = spreadDirection.LookVector

	-- Create raycast params
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { self.Character, self.Tool }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true

	-- Perform raycast
	local maxDistance = self.Config.MaxRange
	local rayResult = workspace:Raycast(origin, direction * maxDistance, raycastParams)

	local hitResult = {
		Hit = false,
		Position = origin + direction * maxDistance,
		Normal = Vector3.new(0, 1, 0),
		Material = Enum.Material.Plastic,
		Instance = nil,
	}

	if rayResult then
		hitResult.Hit = true
		hitResult.Position = rayResult.Position
		hitResult.Normal = rayResult.Normal
		hitResult.Material = rayResult.Material
		hitResult.Instance = rayResult.Instance

		-- Calculate damage
		local distance = (origin - rayResult.Position).Magnitude
		local damage = self:CalculateDamage(distance)

		-- Check for headshot
		local isHeadshot = false
		if rayResult.Instance and rayResult.Instance.Parent then
			local humanoid = rayResult.Instance.Parent:FindFirstChildOfClass("Humanoid")
			if humanoid and rayResult.Instance.Name == "Head" then
				isHeadshot = true
				damage = damage * self.Config.HeadshotMultiplier
			end

			-- Apply damage
			if humanoid and humanoid.Health > 0 then
				humanoid:TakeDamage(damage)
				hitResult.Damage = damage
				hitResult.IsHeadshot = isHeadshot
			end
		end
	end

	return hitResult
end

-- Calculate damage with falloff
function GunSystem:CalculateDamage(distance)
	local falloffStart = self.Config.DamageFalloffStart
	local falloffEnd = self.Config.DamageFalloffEnd
	local baseDamage = self.Config.BaseDamage
	local minDamage = self.Config.MinDamage

	if distance <= falloffStart then
		return baseDamage
	elseif distance >= falloffEnd then
		return minDamage
	else
		-- Linear interpolation between start and end
		local falloffRange = falloffEnd - falloffStart
		local falloffProgress = (distance - falloffStart) / falloffRange
		return baseDamage - (baseDamage - minDamage) * falloffProgress
	end
end

-- Reload the gun
function GunSystem:Reload()
	if self.IsReloading then
		return false
	end
	if self.CurrentAmmo == self.Config.MagazineSize then
		return false
	end
	if self.ReserveAmmo <= 0 then
		return false
	end

	self.IsReloading = true

	-- Determine reload time (tactical vs empty)
	local reloadTime = self.CurrentAmmo > 0 and self.Config.ReloadTimeTactical or self.Config.ReloadTimeEmpty

	local reloadType = self.CurrentAmmo > 0 and "Tactical" or "Empty"

	-- Send reload event to client
	Remotes.PlayEffect:FireClient(self.Player, "Reload", {
		ReloadTime = reloadTime,
		ReloadType = reloadType,
	})

	-- Wait for reload
	task.wait(reloadTime)

	-- Calculate ammo to reload
	local ammoNeeded = self.Config.MagazineSize - self.CurrentAmmo
	local ammoToReload = math.min(ammoNeeded, self.ReserveAmmo)

	-- Update ammo counts
	self.CurrentAmmo = self.CurrentAmmo + ammoToReload
	self.ReserveAmmo = self.ReserveAmmo - ammoToReload

	self.IsReloading = false

	-- Reset recoil
	self.CurrentRecoilIndex = 1
	self.CurrentSpread = self.Config.BaseSpread

	-- Update UI
	self:UpdateAmmoUI()

	return true
end

-- Update ammo UI
function GunSystem:UpdateAmmoUI()
	if not self.Player then
		return
	end

	Remotes.UpdateAmmo:FireClient(self.Player, {
		CurrentAmmo = self.CurrentAmmo,
		ReserveAmmo = self.ReserveAmmo,
		MagazineSize = self.Config.MagazineSize,
		GunName = self.Config.GunName,
		GunImage = self.Config.GunImage,
	})
end

-- Spread recovery (call in heartbeat)
function GunSystem:UpdateSpread(deltaTime)
	if self.CurrentSpread > self.Config.BaseSpread then
		self.CurrentSpread =
			math.max(self.CurrentSpread - self.Config.SpreadRecovery * deltaTime, self.Config.BaseSpread)
	end
end

-- Clean up when unequipped
function GunSystem:Unequip()
	if self.Player then
		Remotes.UnequipGun:FireClient(self.Player)
	end

	self.Tool = nil
	self.Player = nil
	self.Character = nil
	self.Humanoid = nil
	self.Muzzle = nil
	self.Handle = nil
end

return GunSystem
