-- DirectorMain.server.lua
-- Entry point. Place in ServerScriptService.
-- Boots the AI Director system on server start.

local ServerScriptService = game:GetService("ServerScriptService")

-- Resolve paths (adjust if folder names differ)
local AI             = ServerScriptService:WaitForChild("AI")
local DirectorFolder = AI:WaitForChild("Director")

local DirectorController = require(DirectorFolder:WaitForChild("DirectorController"))

-- ──────────────────────────────────────────────
--  Boot
-- ──────────────────────────────────────────────

local director = DirectorController.new()
director:Initialize()

-- ──────────────────────────────────────────────
--  Expose globally (optional — for other scripts to reference)
-- ──────────────────────────────────────────────
_G.AIDirector = director

-- ──────────────────────────────────────────────
--  Example: Wire up weapon hit reports
-- ──────────────────────────────────────────────
--[[
-- In your weapon script:
--   _G.AIDirector:ReportShot(true)   -- hit
--   _G.AIDirector:ReportShot(false)  -- miss
--   _G.AIDirector:ReportKill()       -- enemy killed
--]]

-- ──────────────────────────────────────────────
--  Optional: Print debug snapshot every 30s
-- ──────────────────────────────────────────────
local DebugFolder  = AI:WaitForChild("Debug")
local Debugger     = require(DebugFolder:WaitForChild("DirectorDebugger"))
local debugger     = Debugger.new(director)

task.spawn(function()
	while task.wait(30) do
		debugger:PrintSnapshot()
	end
end)

print("[DirectorMain] AI Director system running ✓")
