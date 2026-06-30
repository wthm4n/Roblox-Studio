--!strict
-- Signal.lua
-- Lightweight pure-Luau signal implementation. No BindableEvents.
-- Linked-list based connection storage to avoid table shifting / array holes.

local FreeRunnerThread: thread? = nil

local function RunHandlerInFreeThread(callback: (...any) -> (), ...: any)
	local acquiredThread = FreeRunnerThread
	FreeRunnerThread = nil
	callback(...)
	FreeRunnerThread = acquiredThread
end

local function RunnerThreadLoop()
	while true do
		RunHandlerInFreeThread(coroutine.yield())
	end
end

type Connection = {
	Connected: boolean,
	_signal: Signal,
	_fn: (...any) -> (),
	_next: Connection?,
	_prev: Connection?,
	_once: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	_head: Connection?,
	_destroyed: boolean,
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Once: (self: Signal, fn: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
	Destroy: (self: Signal) -> (),
}

local Connection = {}
Connection.__index = Connection

local function newConnection(signal: Signal, fn: (...any) -> (), once: boolean): Connection
	return setmetatable({
		Connected = true,
		_signal = signal,
		_fn = fn,
		_next = nil,
		_prev = nil,
		_once = once,
	}, Connection) :: any
end

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false

	local signal = self._signal
	local prev = self._prev
	local next = self._next

	if prev then
		prev._next = next
	else
		signal._head = next
	end

	if next then
		next._prev = prev
	end

	self._prev = nil
	self._next = nil
end

local Signal = {}
Signal.__index = Signal

local function connect(self: Signal, fn: (...any) -> (), once: boolean): Connection
	if self._destroyed then
		error("Cannot connect to a destroyed Signal", 2)
	end

	local conn = newConnection(self, fn, once)
	local head = self._head
	if head then
		head._prev = conn
		conn._next = head
	end
	self._head = conn
	return conn
end

function Signal:Connect(fn: (...any) -> ()): Connection
	return connect(self, fn, false)
end

function Signal:Once(fn: (...any) -> ()): Connection
	return connect(self, fn, true)
end

function Signal:Fire(...: any)
	local conn = self._head
	while conn do
		local nextConn = conn._next
		if conn.Connected then
			if not FreeRunnerThread then
				FreeRunnerThread = coroutine.create(RunnerThreadLoop)
				coroutine.resume(FreeRunnerThread :: thread)
			end
			task.spawn(FreeRunnerThread :: thread, conn._fn, ...)
			if conn._once then
				conn:Disconnect()
			end
		end
		conn = nextConn
	end
end

function Signal:DisconnectAll()
	local conn = self._head
	while conn do
		local nextConn = conn._next
		conn.Connected = false
		conn._prev = nil
		conn._next = nil
		conn = nextConn
	end
	self._head = nil
end

function Signal:Destroy()
	if self._destroyed then
		return
	end
	self:DisconnectAll()
	self._destroyed = true
end

local function new(): Signal
	return setmetatable({
		_head = nil,
		_destroyed = false,
	}, Signal) :: any
end

return {
	new = new,
}
