--!strict
-- Signal.luau
-- Lightweight, reliable Luau event dispatcher for decoupled architecture

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	Destroy: (self: Signal<T...>) -> (),
}

type InternalConnection = {
	Disconnect: (self: InternalConnection) -> (),
	Connected: boolean,
	_callback: (...any) -> (),
	_next: InternalConnection?,
	_prev: InternalConnection?,
	_signal: InternalSignal,
}

type InternalSignal = {
	_head: InternalConnection?,
	_tail: InternalConnection?,
	Connect: (self: InternalSignal, callback: (...any) -> ()) -> Connection,
	Once: (self: InternalSignal, callback: (...any) -> ()) -> Connection,
	Fire: (self: InternalSignal, ...any) -> (),
	Wait: (self: InternalSignal) -> ...any,
	Destroy: (self: InternalSignal) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal<...any>
	local self = setmetatable({
		_head = nil,
		_tail = nil,
	}, Signal)
	return (self :: any) :: Signal<...any>
end

function Signal.Connect(self: InternalSignal, callback: (...any) -> ()): Connection
	local connection: InternalConnection
	connection = {
		Connected = true,
		_callback = callback,
		_next = nil,
		_prev = self._tail,
		_signal = self,
		Disconnect = function(conn)
			if not conn.Connected then return end
			conn.Connected = false
			if conn._prev then
				conn._prev._next = conn._next
			else
				self._head = conn._next
			end
			if conn._next then
				conn._next._prev = conn._prev
			else
				self._tail = conn._prev
			end
			conn._callback = nil :: any
		end,
	}

	if self._tail then
		self._tail._next = connection
		self._tail = connection
	else
		self._head = connection
		self._tail = connection
	end

	return connection
end

function Signal.Once(self: InternalSignal, callback: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal.Fire(self: InternalSignal, ...: any)
	local current = self._head
	while current do
		local nextConn = current._next
		if current.Connected and current._callback then
			task.spawn(current._callback, ...)
		end
		current = nextConn
	end
end

function Signal.Wait(self: InternalSignal): ...any
	local thread = coroutine.running()
	local conn: Connection
	conn = self:Connect(function(...)
		conn:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.Destroy(self: InternalSignal)
	local current = self._head
	while current do
		current.Connected = false
		current = current._next
	end
	self._head = nil
	self._tail = nil
end

return Signal
