--[[
	NETWORK SYNC
	
	CLIENT: Predicts actions, sends requests
	SERVER: Validates, confirms, corrects if needed
	
	Uses lag compensation: server rewinds positions to validate hits fairly.
	Prevents "I hit on my screen but nothing happened" and speed exploits.
]]

local NetworkSync = {}
NetworkSync.__index = NetworkSync

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Remote events (would be in ReplicatedStorage)
-- For this example, we'll assume they exist
local function GetRemotes()
	local folder = ReplicatedStorage:FindFirstChild("CombatRemotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CombatRemotes"
		folder.Parent = ReplicatedStorage
		
		-- Create remotes
		local actionRequest = Instance.new("RemoteEvent")
		actionRequest.Name = "ActionRequest"
		actionRequest.Parent = folder
		
		local actionConfirm = Instance.new("RemoteEvent")
		actionConfirm.Name = "ActionConfirm"
		actionConfirm.Parent = folder
		
		local stateSync = Instance.new("RemoteEvent")
		stateSync.Name = "StateSync"
		stateSync.Parent = folder
		
		local hitValidation = Instance.new("RemoteEvent")
		hitValidation.Name = "HitValidation"
		hitValidation.Parent = folder
	end
	
	return {
		ActionRequest = folder.ActionRequest,
		ActionConfirm = folder.ActionConfirm,
		StateSync = folder.StateSync,
		HitValidation = folder.HitValidation,
	}
end

--[[
	SERVER NETWORK SYNC
]]
function NetworkSync.newServer(core)
	local self = setmetatable({}, NetworkSync)
	
	self.Core = core
	self.IsServer = true
	self.Remotes = GetRemotes()
	
	-- Position history for lag compensation
	self.PositionHistory = {} -- { frame = {position, timestamp} }
	self.MaxHistorySize = 120 -- 2 seconds at 60fps
	
	-- Listen for client action requests
	self.Remotes.ActionRequest.OnServerEvent:Connect(function(player, actionType, actionData, clientFrame, clientTimestamp)
		self:HandleActionRequest(player, actionType, actionData, clientFrame, clientTimestamp)
	end)
	
	-- Listen for hit reports from client (will be validated)
	self.Remotes.HitValidation.OnServerEvent:Connect(function(player, targetPlayer, hitData)
		self:HandleHitReport(player, targetPlayer, hitData)
	end)
	
	return self
end

function NetworkSync:HandleActionRequest(player: Player, actionType: string, actionData: any, clientFrame: number, clientTimestamp: number)
	-- Validate the request
	-- This is where the server decides if the client's action is legal
	
	-- Basic validation: does player's character exist?
	if not player.Character or player.Character ~= self.Core.Character then
		return -- Not this core's player
	end
	
	-- Queue the input in the core
	-- The core will validate state, cooldowns, etc.
	self.Core:QueueInput(actionType, actionData)
	
	-- Note: We could add additional server-side validation here
	-- For example, checking if player has stamina, mana, etc.
end

function NetworkSync:HandleHitReport(attackerPlayer: Player, targetPlayer: Player, hitData: any)
	-- LAG COMPENSATION
	-- Rewind target position to when the hit was registered on attacker's client
	
	if not attackerPlayer.Character or attackerPlayer.Character ~= self.Core.Character then
		return
	end
	
	-- Get target's position at the time of the hit (using timestamp)
	local rewindedPosition = self:GetHistoricalPosition(targetPlayer, hitData.Timestamp)
	
	if not rewindedPosition then
		-- Couldn't find historical position, use current
		rewindedPosition = targetPlayer.Character.HumanoidRootPart.Position
	end
	
	-- Validate hit using rewinded position
	local hitValid = self:ValidateHitGeometry(
		hitData.HitboxData,
		rewindedPosition,
		hitData.HitPosition
	)
	
	if hitValid then
		-- Confirm hit
		local targetCore = self:GetCoreForPlayer(targetPlayer)
		if targetCore then
			-- Apply damage and knockback on target
			self:ApplyHit(targetCore, hitData)
		end
		
		-- Confirm to attacker
		self.Remotes.ActionConfirm:FireClient(attackerPlayer, "HitConfirmed", hitData)
	else
		-- Hit was invalid (probably lag or exploit attempt)
		-- Don't confirm, client will see no effect
	end
end

function NetworkSync:ValidateHitGeometry(hitboxData, targetPosition: Vector3, reportedHitPosition: Vector3): boolean
	-- Simplified hit validation
	-- In production, this would check oriented bounding boxes, swept volumes, etc.
	
	local distance = (targetPosition - reportedHitPosition).Magnitude
	return distance < 10 -- Placeholder threshold
end

function NetworkSync:ApplyHit(targetCore, hitData)
	-- Deal damage
	local damage = hitData.Damage or 10
	local humanoid = targetCore.Humanoid
	
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(damage)
		
		-- Apply hitstun
		targetCore.StateManager:ForceState("Hitstun", 15) -- 15 frame hitstun
		
		-- Apply knockback (would be handled by physics system)
		local knockback = hitData.Knockback or Vector3.new(0, 0, 0)
		-- Physics system would apply this force
		
		-- Notify target
		targetCore:ConfirmHit(self.Core.Character, damage, knockback)
	end
end

function NetworkSync:ServerUpdate()
	-- Record position history for lag compensation
	local hrp = self.Core.HumanoidRootPart
	
	table.insert(self.PositionHistory, {
		Frame = self.Core.CurrentFrame,
		Timestamp = tick(),
		Position = hrp.Position,
		CFrame = hrp.CFrame,
	})
	
	-- Trim old history
	if #self.PositionHistory > self.MaxHistorySize then
		table.remove(self.PositionHistory, 1)
	end
	
	-- Periodically sync state to client
	-- This corrects any desyncs
	if self.Core.CurrentFrame % 30 == 0 then -- Every 0.5s
		self:BroadcastStateSync()
	end
end

function NetworkSync:BroadcastStateSync()
	local player = game.Players:GetPlayerFromCharacter(self.Core.Character)
	if not player then return end
	
	-- Send current authoritative state
	self.Remotes.StateSync:FireClient(player, {
		State = self.Core.CurrentState,
		Frame = self.Core.CurrentFrame,
		Position = self.Core.HumanoidRootPart.Position,
		Velocity = self.Core.HumanoidRootPart.AssemblyVelocity,
	})
end

function NetworkSync:GetHistoricalPosition(player: Player, timestamp: number)
	-- Find closest position in history to given timestamp
	local closest = nil
	local closestDiff = math.huge
	
	for _, record in ipairs(self.PositionHistory) do
		local diff = math.abs(record.Timestamp - timestamp)
		if diff < closestDiff then
			closestDiff = diff
			closest = record
		end
	end
	
	return closest and closest.Position or nil
end

function NetworkSync:GetCoreForPlayer(player: Player)
	-- In a real implementation, you'd have a registry of cores
	-- For now, placeholder
	return nil
end

--[[
	CLIENT NETWORK SYNC
]]
function NetworkSync.newClient(core)
	local self = setmetatable({}, NetworkSync)
	
	self.Core = core
	self.IsServer = false
	self.Remotes = GetRemotes()
	
	-- Client prediction state
	self.PendingActions = {} -- Actions awaiting server confirmation
	self.LastServerFrame = 0
	
	-- Listen for server confirmations
	self.Remotes.ActionConfirm.OnClientEvent:Connect(function(confirmType, data)
		self:HandleServerConfirm(confirmType, data)
	end)
	
	-- Listen for state syncs
	self.Remotes.StateSync.OnClientEvent:Connect(function(syncData)
		self:HandleStateSync(syncData)
	end)
	
	return self
end

function NetworkSync:ClientUpdate()
	-- Client predicts actions optimistically
	-- If current action exists and hasn't been confirmed, it's a prediction
	
	-- Clean up old pending actions
	for i = #self.PendingActions, 1, -1 do
		local action = self.PendingActions[i]
		if self.Core.CurrentFrame - action.Frame > 120 then -- 2s timeout
			table.remove(self.PendingActions, i)
		end
	end
end

--[[
	Request action from server
	Client predicts optimistically but must get server approval
]]
function NetworkSync:RequestAction(actionType: string, actionData: any)
	-- Send to server
	self.Remotes.ActionRequest:FireServer(
		actionType,
		actionData,
		self.Core.CurrentFrame,
		tick()
	)
	
	-- Track as pending
	table.insert(self.PendingActions, {
		Type = actionType,
		Data = actionData,
		Frame = self.Core.CurrentFrame,
	})
end

function NetworkSync:HandleServerConfirm(confirmType: string, data: any)
	if confirmType == "HitConfirmed" then
		-- Server validated our hit
		-- Play hit effects, sounds, etc.
		self.Core.Events.HitConfirmed:Fire(data)
	elseif confirmType == "ActionDenied" then
		-- Server rejected our action
		-- Need to correct our prediction
		self:CorrectPrediction(data)
	end
end

function NetworkSync:HandleStateSync(syncData)
	-- Server sent authoritative state update
	-- Check if we're desynced
	
	local frameDiff = math.abs(self.Core.CurrentFrame - syncData.Frame)
	
	if frameDiff > 10 then -- More than 10 frames off
		-- Significant desync, correct it
		self.Core.CurrentFrame = syncData.Frame
		self.Core.CurrentState = syncData.State
		
		-- Could also correct position here
		-- self.Core.HumanoidRootPart.Position = syncData.Position
	end
	
	self.LastServerFrame = syncData.Frame
end

function NetworkSync:CorrectPrediction(correctionData)
	-- Server said our prediction was wrong
	-- Rollback and replay with correct state
	
	-- For now, just force end current action
	if self.Core.CurrentAction then
		self.Core:EndCurrentAction(true)
	end
	
	-- In a more advanced system, we'd rewind and replay inputs
end

--[[
	Report a hit to server for validation
	Client detects hit locally, but server must confirm
]]
function NetworkSync:ReportHit(target: Model, hitData: any)
	local targetPlayer = game.Players:GetPlayerFromCharacter(target)
	if not targetPlayer then return end
	
	-- Add timestamp for lag compensation
	hitData.Timestamp = tick()
	
	-- Send to server
	self.Remotes.HitValidation:FireServer(targetPlayer, hitData)
end

function NetworkSync:Destroy()
	-- Cleanup connections
end

return NetworkSync
