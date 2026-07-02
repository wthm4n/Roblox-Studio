local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_handlers = {},
	}, Signal)
end

function Signal:Connect(fn)
	local handler = { fn = fn, connected = true }
	table.insert(self._handlers, handler)

	local connection = {}
	function connection.Disconnect()
		handler.connected = false
	end

	return connection
end

function Signal:Fire(...)
	for _, handler in ipairs(self._handlers) do
		if handler.connected then
			task.spawn(handler.fn, ...)
		end
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
