local RunService = game:GetService("RunService")

local Scheduler = {}
Scheduler._systems = {}
Scheduler._started = false


function Scheduler.Register(system)
	assert(type(system.Update) == "function", "Scheduler.Register: system must have an Update(dt) function")
	table.insert(Scheduler._systems, system)
end

function Scheduler.Start()
	if Scheduler._started then
		return
	end
	Scheduler._started = true

	RunService.Heartbeat:Connect(function(dt)
		for _, system in ipairs(Scheduler._systems) do
			system.Update(dt)
		end
	end)
end

return Scheduler
