--[[
	StatusService.lua
	Applies, refreshes, and removes status effects.
	All status state lives on the server in PlayerState.

	Supported statuses (extensible):
	  Stun, Slow, Burn, GuardBreak, Ragdoll
]]

local StatusService = {}
StatusService.__index = StatusService

local StatusEffect = require(script.Parent.Parent.Classes.StatusEffect)
local Players      = game:GetService("Players")

-- ─── Status Definitions ───────────────────────────────────────────────────────
-- Each definition returns onApply / onRemove functions given the character.

local StatusDefs: { [string]: (char: Model, state: any) -> (()->(), ()->()) } = {

	Stun = function(char, state)
		return
			function()  -- onApply
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then hum.WalkSpeed = 0 end
				state:SetState("Stunned")
			end,
			function()  -- onRemove
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then hum.WalkSpeed = state.Stats.Speed end
				state:SetState("Idle")
				state:RemoveStatus("Stun")
			end
	end,

	Slow = function(char, state)
		local origSpeed = state.Stats.Speed
		return
			function()
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then hum.WalkSpeed = origSpeed * 0.4 end
			end,
			function()
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then hum.WalkSpeed = origSpeed end
				state:RemoveStatus("Slow")
			end
	end,

	Burn = function(char, state)
		local burnThread
		return
			function()
				-- Tick damage every 0.5s for the duration
				burnThread = task.spawn(function()
					while state:HasStatus("Burn") do
						local hum = char:FindFirstChildOfClass("Humanoid")
						if not hum or hum.Health <= 0 then break end
						hum:TakeDamage(3)
						task.wait(0.5)
					end
				end)
			end,
			function()
				if burnThread then
					task.cancel(burnThread)
				end
				state:RemoveStatus("Burn")
			end
	end,

	GuardBreak = function(char, state)
		return
			function()
				state.GuardBroken = true
				if state:Is("Blocking") then
					state:SetState("Stunned")
				end
			end,
			function()
				state:RestoreGuard()
				if state:Is("Stunned") then
					state:SetState("Idle")
				end
				state:RemoveStatus("GuardBreak")
			end
	end,

	Ragdoll = function(char, state)
		-- Convert Motor6Ds → BallSocketConstraints for ragdoll physics
		local savedMotors = {}

		return
			function()
				state:SetState("Ragdolled")
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then
					hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
					hum:ChangeState(Enum.HumanoidStateType.Physics)
				end

				for _, desc in ipairs(char:GetDescendants()) do
					if desc:IsA("Motor6D") and desc.Part0 and desc.Part1 then
						local socket = Instance.new("BallSocketConstraint")
						local a0 = Instance.new("Attachment")
						local a1 = Instance.new("Attachment")
						a0.CFrame = desc.C0
						a1.CFrame = desc.C1
						a0.Parent = desc.Part0
						a1.Parent = desc.Part1
						socket.Attachment0 = a0
						socket.Attachment1 = a1
						socket.Parent = desc.Part0

						table.insert(savedMotors, {
							Motor  = desc,
							Socket = socket,
							A0     = a0,
							A1     = a1,
							Enabled = desc.Enabled,
						})
						desc.Enabled = false
					end
				end
			end,
			function()
				-- Restore motors
				for _, data in ipairs(savedMotors) do
					data.Motor.Enabled = data.Enabled
					data.Socket:Destroy()
					data.A0:Destroy()
					data.A1:Destroy()
				end
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then
					hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
				state:SetState("Idle")
				state:RemoveStatus("Ragdoll")
			end
	end,
}

-- ─── Constructor ──────────────────────────────────────────────────────────────

function StatusService.new()
	return setmetatable({}, StatusService)
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--[[
	Apply(victimPlayer, victimState, statusName, duration)

	If the status is already active it refreshes (cancels old, starts new).
	If status doesn't exist in StatusDefs it warns and returns.
]]
function StatusService:Apply(victimTarget, victimState, statusName: string, duration: number)
	local char = victimTarget._isNPC and victimTarget.Character or victimTarget.Character
	if not char then return end

	local def = StatusDefs[statusName]
	if not def then
		warn("[StatusService] Unknown status: " .. statusName)
		return
	end

	-- Refresh if already active
	if victimState:HasStatus(statusName) then
		victimState.Statuses[statusName]:Cancel()
	end

	local onApply, onRemove = def(char, victimState)
	local effect = StatusEffect.new(statusName, duration, onApply, onRemove)
	victimState:AddStatus(statusName, effect)
	effect:Start()
end

function StatusService:Remove(victimTarget, victimState, statusName: string)
	if victimState:HasStatus(statusName) then
		victimState.Statuses[statusName]:Cancel()
	end
end

function StatusService:ClearAll(victimState)
	for name, effect in pairs(victimState.Statuses) do
		effect:Cancel()
	end
end

return StatusService