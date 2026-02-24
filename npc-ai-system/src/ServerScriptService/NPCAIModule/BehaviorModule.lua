--[[
	BehaviorModule.lua
	Evaluates sensor data and drives state transitions.
	Pluggable: add new rules by inserting into _rules table.
--]]

local BehaviorModule = {}
BehaviorModule.__index = BehaviorModule

function BehaviorModule.new(npc)
	local self = setmetatable({}, BehaviorModule)
	self._npc = npc

	-- Priority-ordered rules. First match wins.
	-- Each rule: { condition = fn(npc) -> bool, targetState = string }
	self._rules = {
		-- Dead / near-death → flee
		{
			condition = function(n)
				local hpPct = n.Humanoid.Health / n.Config.maxHealth
				return hpPct < n.Config.fearHealthThreshold
			end,
			targetState = "scared",
		},
		-- Player in aggro range with LOS → aggressive
		{
			condition = function(n)
				return n.Sensor.NearestPlayer ~= nil
					and n.Sensor.NearestDist <= n.Config.aggroRange
					and n.Sensor.HasLOS
					and (n.Humanoid.Health / n.Config.maxHealth) >= n.Config.fearHealthThreshold
			end,
			targetState = "aggressive",
		},
		-- Player in flee range but NPC is "scared" type or low HP
		{
			condition = function(n)
				return n.Sensor.NearestPlayer ~= nil
					and n.Sensor.NearestDist <= n.Config.fleeRange
					and (n.Config.defaultState == "scared")
			end,
			targetState = "scared",
		},
		-- No threat → return to default state
		{
			condition = function(n)
				return n.Sensor.NearestPlayer == nil
					or n.Sensor.NearestDist > n.Config.aggroRange
			end,
			targetState = n and n.Config and n.Config.defaultState or "passive",
		},
	}

	return self
end

function BehaviorModule:Evaluate()
	local npc = self._npc

	-- Fix closure issue: last rule needs live defaultState
	self._rules[#self._rules].targetState = npc.Config.defaultState

	for _, rule in ipairs(self._rules) do
		local ok, result = pcall(rule.condition, npc)
		if ok and result then
			local current = npc.State:Get()
			if current ~= rule.targetState then
				npc.State:Set(rule.targetState)

				-- Sync target when switching to aggressive
				if rule.targetState == "aggressive" then
					npc.Target = npc.Sensor.NearestPlayer
				elseif rule.targetState == "scared" then
					npc.Target = npc.Sensor.NearestPlayer
				else
					npc.Target = nil
				end

				if npc.Config.debugMode then
					print(("[Behavior] %s: %s → %s"):format(
						npc.Model.Name, current, rule.targetState))
				end
			end
			return  -- first match wins
		end
	end
end

-- Add a custom rule from outside
-- rule = { condition = fn(npc)->bool, targetState = string, priority = number? }
function BehaviorModule:AddRule(rule, priority: number?)
	local insertAt = priority or 1
	table.insert(self._rules, insertAt, rule)
end

return BehaviorModule
