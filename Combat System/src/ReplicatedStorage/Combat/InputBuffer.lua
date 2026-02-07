--[[
	INPUT BUFFER
	
	Stores player inputs with frame timestamps.
	Handles priority resolution when multiple inputs exist.
	Makes combat feel responsive even under lag.
	
	Inputs don't execute immediately - they're buffered and validated by Core.
]]

local InputBuffer = {}
InputBuffer.__index = InputBuffer

-- Input priority (higher = processed first)
local INPUT_PRIORITY = {
	Ability = 10, -- Abilities take priority
	Dash = 8,
	M1 = 5,
	Block = 7,
	Jump = 3,
}

function InputBuffer.new(bufferWindowFrames: number)
	local self = setmetatable({}, InputBuffer)
	
	self.Buffer = {} -- Array of buffered inputs
	self.BufferWindow = bufferWindowFrames -- How long inputs stay valid
	self.MaxBufferSize = 10 -- Prevent buffer overflow exploits
	
	return self
end

--[[
	Add input to buffer with timestamp
]]
function InputBuffer:Add(inputType: string, inputData: any, currentFrame: number)
	-- Check buffer size
	if #self.Buffer >= self.MaxBufferSize then
		-- Remove oldest input
		table.remove(self.Buffer, 1)
	end
	
	local input = {
		Type = inputType,
		Data = inputData,
		Frame = currentFrame,
		Priority = INPUT_PRIORITY[inputType] or 0,
		Consumed = false,
	}
	
	table.insert(self.Buffer, input)
end

--[[
	Get the next valid input based on priority and timing
	Returns the highest priority input that's still within the buffer window
]]
function InputBuffer:GetNextValid(currentFrame: number)
	-- Remove expired inputs
	self:CleanExpired(currentFrame)
	
	if #self.Buffer == 0 then
		return nil
	end
	
	-- Sort by priority (highest first)
	table.sort(self.Buffer, function(a, b)
		if a.Priority == b.Priority then
			return a.Frame < b.Frame -- Older first if same priority
		end
		return a.Priority > b.Priority
	end)
	
	-- Return highest priority unconsumed input
	for _, input in ipairs(self.Buffer) do
		if not input.Consumed then
			return input
		end
	end
	
	return nil
end

--[[
	Mark input as consumed (successfully executed)
]]
function InputBuffer:Consume(input)
	input.Consumed = true
	
	-- Remove consumed inputs immediately
	for i = #self.Buffer, 1, -1 do
		if self.Buffer[i].Consumed then
			table.remove(self.Buffer, i)
		end
	end
end

--[[
	Remove inputs that are too old
]]
function InputBuffer:CleanExpired(currentFrame: number)
	for i = #self.Buffer, 1, -1 do
		local input = self.Buffer[i]
		local age = currentFrame - input.Frame
		
		if age > self.BufferWindow then
			table.remove(self.Buffer, i)
		end
	end
end

--[[
	Clear all buffered inputs
	Used when state changes require buffer flush
]]
function InputBuffer:Clear()
	self.Buffer = {}
end

--[[
	Debug: Get buffer contents
]]
function InputBuffer:GetBufferContents()
	return self.Buffer
end

function InputBuffer:GetBufferSize(): number
	return #self.Buffer
end

return InputBuffer
