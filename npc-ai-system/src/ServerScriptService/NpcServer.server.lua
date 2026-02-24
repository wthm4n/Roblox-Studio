-- NPCController.lua  (ServerScript → ServerScriptService)
-- Spawns an NPC and activates the AI to follow the nearest player.
-- Requires "NPCAIService" ModuleScript in ServerScriptService.
-- Requires an NPC Model named "NPC" inside ServerStorage.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage       = game:GetService("ServerStorage")

local NPCAIService = require(ServerScriptService.NPCAIModule:WaitForChild("NPCService"))

-- ══════════════════════════════════════════════════════════════════
--  YOUR CUSTOM SETTINGS (all optional — just override what you want)
-- ══════════════════════════════════════════════════════════════════
local MY_SETTINGS = {

	-- Follow range
	FollowRange      = 80,     -- chase player within 80 studs
	StopDistance     = 5,      -- stop 5 studs away
	LoseTargetRange  = 110,    -- give up past 110 studs

	-- Speeds
	WalkSpeed        = 16,
	RunSpeed         = 26,
	RunThreshold     = 25,     -- run when player > 25 studs away
	CrouchSpeed      = 5,
	SwimSpeed        = 11,
	ClimbSpeed       = 9,

	-- Abilities
	CanJump          = true,
	CanSwim          = true,
	CanClimb         = true,
	CanCrouch        = true,
	JumpPower        = 55,

	-- Path recalc & precision
	RecalcRate       = 0.12,
	WaypointRadius   = 3,

	-- Stuck recovery
	StuckTimeout     = 1.8,
	StuckJumpMax     = 3,

	-- ✦ Purple glowing path balls ✦
	ShowPath         = true,
	BallColor        = Color3.fromRGB(168, 0, 255),    -- deep purple
	BallGlow         = Color3.fromRGB(210, 100, 255),  -- light purple glow
	BallSize         = 0.6,
	BallFadeTime     = 0.3,
	GlowBrightness   = 5,
	GlowRange        = 10,
}

-- ══════════════════════════════════════════════════════════════════
--  SPAWN + START AI
-- ══════════════════════════════════════════════════════════════════
local SPAWN_POS = Vector3.new(0, 5, 0)

local function getClosestPlayer(fromPos)
	local best, bestDist = nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		if ch then
			local r = ch:FindFirstChild("HumanoidRootPart")
			if r then
				local d = (r.Position - fromPos).Magnitude
				if d < bestDist then best, bestDist = p, d end
			end
		end
	end
	return best
end

local function spawnNPC()
	local template = ServerStorage:FindFirstChild("NPC")
	if not template then
		warn("[NPCController] No Model named 'NPC' found in ServerStorage!")
		return
	end

	local npc = template:Clone()
	npc.Name  = "AI_NPC"
	npc:SetPrimaryPartCFrame(CFrame.new(SPAWN_POS))
	npc.Parent = workspace

	-- Wait for a player if none are in yet
	local target = getClosestPlayer(SPAWN_POS)
	if not target then
		target = Players.PlayerAdded:Wait()
		task.wait(1) -- let character load
	end

	print(("[NPCController] NPC spawned → following '%s'"):format(target.Name))
	local ai = NPCAIService(npc, target, MY_SETTINGS)

	-- Switch target when one leaves
	Players.PlayerRemoving:Connect(function(leaving)
		if ai.target == leaving then
			task.delay(0.5, function()
				local next = getClosestPlayer(npc.PrimaryPart.Position)
				if next then
					print(("[NPCController] Target left → switching to '%s'"):format(next.Name))
					ai:setTarget(next)
				else
					ai:pause()
					Players.PlayerAdded:Once(function(p)
						p.CharacterAdded:Wait()
						ai:setTarget(p)
						ai:resume()
					end)
				end
			end)
		end
	end)

	-- Clean up on NPC death
	local hum = npc:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			print("[NPCController] NPC died. Cleaning up.")
			ai:destroy()
			task.delay(5, function() npc:Destroy() end)
		end)
	end

	return ai
end

-- ══════════════════════════════════════════════════════════════════
--  ENTRY POINT
-- ══════════════════════════════════════════════════════════════════
if #Players:GetPlayers() > 0 then
	spawnNPC()
else
	Players.PlayerAdded:Once(function()
		task.wait(1)
		spawnNPC()
	end)
end

--[[
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RUNTIME API CHEATSHEET
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local ai = NPCAIService(npcModel, player, settings)

ai:setTarget(player)          -- change follow target
ai:configure({ WalkSpeed=20, ShowPath=false })  -- change settings live
ai:pause()                    -- stop AI
ai:resume()                   -- resume AI
ai:getState()                 -- "idle"|"walk"|"run"|"swim"|"climb"|"crouch"
ai:destroy()                  -- full cleanup
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
]]