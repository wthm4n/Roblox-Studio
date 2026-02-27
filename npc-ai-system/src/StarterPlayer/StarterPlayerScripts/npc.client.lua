--[[
	NPCAnimateClient.lua  ← LocalScript in StarterPlayerScripts
	
	The Animate script inside an NPC only runs if Roblox loads it as a
	character. For server-spawned NPCs it never fires automatically.
	
	This script watches for NPCs added to workspace and manually runs
	their Animate LocalScript on the client, exactly like Roblox does
	for player characters.
	
	SETUP:
	  1. Place this as a LocalScript in StarterPlayerScripts
	  2. Make sure your NPC model has the "Animate" LocalScript inside it
	  3. Add an Attribute "IsNPC" = true (boolean) on the NPC model in Studio
	  4. That's it
--]]

local NPC_TAG = "IsNPC"
local handled = {}

local function handleNPC(model: Model)
	if handled[model] then return end
	if not model:GetAttribute(NPC_TAG) then return end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animateScript = model:FindFirstChild("Animate")
	if not animateScript or not animateScript:IsA("LocalScript") then
		warn("[NPCAnimateClient] No 'Animate' LocalScript in", model.Name)
		return
	end

	handled[model] = true

	-- Disable the original, clone it fresh so it executes properly
	animateScript.Enabled = false
	local clone = animateScript:Clone()
	clone.Enabled = true
	clone.Parent = model

	model.AncestryChanged:Connect(function()
		if not model.Parent then
			handled[model] = nil
			clone:Destroy()
		end
	end)

	print("[NPCAnimateClient] Animate running for", model.Name)
end

local function watchFolder(folder: Instance)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			task.wait(0.1)
			handleNPC(child)
		end
	end

	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.wait(0.1)
			handleNPC(child)
		end
	end)
end

watchFolder(workspace)