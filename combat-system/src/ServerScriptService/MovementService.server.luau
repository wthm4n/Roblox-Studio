-- ServerScriptService/GameInit
local ServerScriptService = game:GetService("ServerScriptService")

local MovementService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("MovementService"))

MovementService.init(nil, nil)

print("[GameInit] MovementService started.")