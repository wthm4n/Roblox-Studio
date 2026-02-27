--[[
	SetupSpawnPoints.lua
	Run this as a Script in ServerScriptService ONE TIME to auto-create
	spawn points with all 4 personality types in your workspace.
	Delete this script after running it.
--]]

local folder = workspace:FindFirstChild("NPCSpawnPoints")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "NPCSpawnPoints"
	folder.Parent = workspace
end

-- Each entry: { position offset from 0,0,0 , personality }
local spawns = {
	{ pos = Vector3.new(  0, 1,   0), personality = "Aggressive" },
	{ pos = Vector3.new( 15, 1,   0), personality = "Aggressive" },
	{ pos = Vector3.new(-15, 1,   0), personality = "Passive"    },
	{ pos = Vector3.new(  0, 1,  15), personality = "Passive"    },
	{ pos = Vector3.new( 15, 1,  15), personality = "Scared"     },
	{ pos = Vector3.new(-15, 1,  15), personality = "Scared"     },
	{ pos = Vector3.new(  0, 1, -15), personality = "Tactical"   },
	{ pos = Vector3.new( 15, 1, -15), personality = "Tactical"   }, -- needs 2 to coordinate
}

for i, data in ipairs(spawns) do
	local part = Instance.new("Part")
	part.Name      = "SpawnPoint_" .. data.personality .. "_" .. i
	part.Size      = Vector3.new(2, 1, 2)
	part.CFrame    = CFrame.new(data.pos)
	part.Anchored  = true
	part.CanCollide = false
	part.Transparency = 0.5
	part.BrickColor = BrickColor.new(
		data.personality == "Aggressive" and "Bright red"   or
		data.personality == "Passive"    and "Bright green" or
		data.personality == "Scared"     and "Bright yellow" or
		"Bright blue"  -- Tactical
	)

	part:SetAttribute("NPCTemplate", "EnemyNPC")
	part:SetAttribute("Personality",  data.personality)
	part:SetAttribute("RespawnDelay", 10)

	part.Parent = folder
	print(("Created spawn point: %s at %s"):format(data.personality, tostring(data.pos)))
end

print("Done! " .. #spawns .. " spawn points created in workspace.NPCSpawnPoints")
print("You can now delete this script.")