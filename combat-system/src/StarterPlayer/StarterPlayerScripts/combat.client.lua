--[[
	CombatClient.client.lua
	Handles input → FireServer, and plays VFX/sounds on confirmed hits.
	ZERO gameplay logic here. Client only requests and reacts.
]]

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()

-- ─── Remotes ──────────────────────────────────────────────────────────────────

local remotes       = ReplicatedStorage:WaitForChild("CombatRemotes")
local abilityRemote = remotes:WaitForChild("AbilityRequest")
local vfxRemote     = remotes:WaitForChild("VFXEvent")

-- ─── Audio Config ─────────────────────────────────────────────────────────────

local Audio = {
	HitSounds = {
		"rbxassetid://137630794322989",
		"rbxassetid://137630794322989",
		"rbxassetid://137630794322989",
		"rbxassetid://137630794322989",
		"rbxassetid://137630794322989",
	},
	BlockHit   = "rbxassetid://137630794322989",
	BlockBreak = "rbxassetid://137630794322989",
	Volume     = 0.5,
	HitVolume  = 5.0,
}

-- ─── Sound Helper ─────────────────────────────────────────────────────────────

local function PlaySound(id: string, volume: number?, parent: Instance?)
	local s = Instance.new("Sound")
	s.SoundId  = id
	s.Volume   = volume or Audio.Volume
	s.Parent   = parent or workspace
	s:Play()
	game:GetService("Debris"):AddItem(s, 3)
end

-- ─── UI Cooldowns (display only — server enforces real CDs) ───────────────────

local uiCooldowns: { [string]: number } = {}

local function SetUICooldown(name: string, duration: number)
	uiCooldowns[name] = os.clock() + duration
	-- Drive your UI bar/icon here if you have one
end

local function UICooldownReady(name: string): boolean
	local t = uiCooldowns[name]
	return not t or os.clock() >= t
end

-- ─── Direction Helper ─────────────────────────────────────────────────────────

local function GetDashDir(): string
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then return "Left"  end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then return "Right" end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then return "Back"  end
	return "Forward"
end

-- ─── Input ────────────────────────────────────────────────────────────────────

local blockHeld = false

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not UICooldownReady("M1") then return end
		abilityRemote:FireServer("M1")
		SetUICooldown("M1", 0.35)

	elseif input.KeyCode == Enum.KeyCode.Q then
		if not UICooldownReady("Dash") then return end
		abilityRemote:FireServer("Dash", { Direction = GetDashDir() })
		SetUICooldown("Dash", 4)

	elseif input.KeyCode == Enum.KeyCode.E then
		if not UICooldownReady("Fireball") then return end
		abilityRemote:FireServer("Fireball")
		SetUICooldown("Fireball", 6)

	elseif input.KeyCode == Enum.KeyCode.F then
		if blockHeld then return end
		blockHeld = true
		abilityRemote:FireServer("Block")
	end
end)

UserInputService.InputEnded:Connect(function(input, gpe)
	if input.KeyCode == Enum.KeyCode.F and blockHeld then
		blockHeld = false
		abilityRemote:FireServer("BlockRelease")
	end
end)

-- ─── VFX Handler ──────────────────────────────────────────────────────────────

vfxRemote.OnClientEvent:Connect(function(eventName: string, data: {})

	if eventName == "HitEffect" then
		local vol = data.IsCrit and Audio.HitVolume or Audio.Volume
		local soundId = Audio.HitSounds[data.ComboIndex] or Audio.HitSounds[1]

		-- Play hit sound at impact position
		if data.Position then
			local part = Instance.new("Part")
			part.Anchored   = true
			part.CanCollide = false
			part.Transparency = 1
			part.Size   = Vector3.one
			part.Position = data.Position
			part.Parent = workspace

			PlaySound(soundId, vol, part)
			game:GetService("Debris"):AddItem(part, 3)
		end

		-- Screen shake for local player if they took the hit
		if data.AttackerId ~= player.UserId then
			-- They hit us — screen shake
			local cam = workspace.CurrentCamera
			if cam and data.Position then
				local dist = (cam.CFrame.Position - data.Position).Magnitude
				if dist < 30 then
					-- Simple camera punch — replace with your shake module if you have one
					local original = cam.CFrame
					task.spawn(function()
						for i = 1, 3 do
							cam.CFrame = original * CFrame.Angles(
								math.rad(math.random(-2, 2)),
								math.rad(math.random(-2, 2)),
								0
							)
							task.wait(0.04)
						end
						cam.CFrame = original
					end)
				end
			end
		end

	elseif eventName == "DashEffect" then
		local dashPlayer = Players:GetPlayerByUserId(data.PlayerId)
		if not dashPlayer or not dashPlayer.Character then return end
		-- TODO: spawn afterimage / trail VFX on dashPlayer.Character

	elseif eventName == "FireballEffect" then
		-- Spawn a visual-only projectile tween — no gameplay effect
		-- TODO: tween a part from data.Origin to data.HitPos, then destroy

	elseif eventName == "BlockStart" then
		local blockPlayer = Players:GetPlayerByUserId(data.PlayerId)
		if not blockPlayer or not blockPlayer.Character then return end
		-- TODO: play block animation / shield glow on that character

	elseif eventName == "BlockEnd" then
		-- TODO: stop block VFX

	end
end)