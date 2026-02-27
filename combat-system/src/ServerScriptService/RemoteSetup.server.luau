--[[
	RemoteSetup.lua  (SERVER — runs first, before CombatService)
	Creates the Remotes folder and all RemoteEvents used by the combat system.
	Run as a Script in ServerScriptService with RunContext = Server, or place it
	at the top of your server init.

	Place in: ServerScriptService/RemoteSetup
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatSettings    = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CombatSettings"))

-- Create Remotes folder if it doesn't exist
local folder = ReplicatedStorage:FindFirstChild("Remotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name   = "Remotes"
	folder.Parent = ReplicatedStorage
end

local function _ensureRemote(name: string)
	if not folder:FindFirstChild(name) then
		local re      = Instance.new("RemoteEvent")
		re.Name       = name
		re.Parent     = folder
	end
end

-- Create every remote declared in CombatSettings
for _, remoteName in pairs(CombatSettings.Remotes) do
	_ensureRemote(remoteName)
end

print("[RemoteSetup] All combat remotes ready.")
