-- NPCController.lua
-- Place as a ServerScript in ServerScriptService
-- Requires NPCAIService ModuleScript to be in ServerScriptService (or adjust path)

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- Adjust this path to wherever you put the ModuleScript
local NPCAIService = require(ServerScriptService:WaitForChild("NPCAIService"))

-- ─── CONFIG ───────────────────────────────────────────────────────────────────
local NPC_TEMPLATE_NAME = "NPC"   -- Name of your NPC model in Workspace or ServerStorage
local SPAWN_POSITION    = Vector3.new(0, 5, 0)

-- ─── HELPERS ─────────────────────────────────────────────────────────────────

local function getClosestPlayer(fromPosition)
	local closest, closestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				local d = (root.Position - fromPosition).Magnitude
				if d < closestDist then
					closest, closestDist = player, d
				end
			end
		end
	end
	return closest
end

-- ─── SPAWN NPC ────────────────────────────────────────────────────────────────

local function spawnNPC()
	-- Clone your NPC from ServerStorage or Workspace
	local template = game:GetService("ServerStorage"):FindFirstChild(NPC_TEMPLATE_NAME)
		or workspace:FindFirstChild(NPC_TEMPLATE_NAME)

	if not template then
		warn("NPCController: Could not find NPC template named '"..NPC_TEMPLATE_NAME.."'")
		warn("Create a Model with a Humanoid + HumanoidRootPart in ServerStorage or Workspace.")
		return
	end

	local npc = template:Clone()
	npc.Name = "AI_" .. NPC_TEMPLATE_NAME
	npc:SetPrimaryPartCFrame(CFrame.new(SPAWN_POSITION))
	npc.Parent = workspace

	-- Find who to follow (closest player, or wait for one)
	local function startFollowing()
		local target = getClosestPlayer(SPAWN_POSITION)

		if not target then
			-- Wait for a player to join
			Players.PlayerAdded:Wait()
			target = Players:GetPlayers()[1]
		end

		print(("NPCController: NPC '%s' will follow player '%s'"):format(npc.Name, target.Name))

		local ai = NPCAIService(npc, target)

		-- If NPC dies, clean up
		local hum = npc:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Died:Connect(function()
				ai:destroy()
				task.delay(5, function()
					npc:Destroy()
				end)
			end)
		end

		-- If target leaves, switch to next available player
		Players.PlayerRemoving:Connect(function(leavingPlayer)
			if ai.target == leavingPlayer then
				task.delay(1, function()
					local newTarget = getClosestPlayer(npc.PrimaryPart.Position)
					if newTarget then
						print("NPCController: Switching follow target to " .. newTarget.Name)
						ai:setTarget(newTarget)
					else
						ai:pause()
						-- Resume when someone joins
						Players.PlayerAdded:Connect(function(p)
							ai:setTarget(p)
							ai:resume()
						end)
					end
				end)
			end
		end)

		return ai
	end

	task.spawn(startFollowing)
end

-- ─── ENTRY POINT ─────────────────────────────────────────────────────────────

-- Spawn immediately if a player is already in, or wait
if #Players:GetPlayers() > 0 then
	spawnNPC()
else
	Players.PlayerAdded:Once(function()
		task.delay(1, spawnNPC) -- slight delay so character loads
	end)
end

-- Optional: spawn one NPC per player who joins
--[[
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.delay(1, spawnNPC)
	end)
end)
]]