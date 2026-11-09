--!strict
-- AIStateMachine.luau
-- Clean generic finite-state-machine for NPC behaviours

export type StateHandler = {
	Enter: (context: any) -> (),
	Update: (context: any, dt: number) -> (),
	Exit: (context: any) -> (),
}

export type StateMachine = {
	CurrentState: string?,
	AddState: (self: StateMachine, name: string, handler: StateHandler) -> (),
	TransitionTo: (self: StateMachine, name: string, context: any) -> (),
	Update: (self: StateMachine, context: any, dt: number) -> (),
}

local AIStateMachine = {}
AIStateMachine.__index = AIStateMachine

function AIStateMachine.new(): StateMachine
	local self = setmetatable({
		CurrentState = nil,
		_states = {},
	}, AIStateMachine)
	return (self :: any) :: StateMachine
end

function AIStateMachine:AddState(name: string, handler: StateHandler)
	self._states[name] = handler
end

function AIStateMachine:TransitionTo(name: string, context: any)
	if self.CurrentState == name then return end
	if self.CurrentState and self._states[self.CurrentState] then
		self._states[self.CurrentState].Exit(context)
	end
	self.CurrentState = name
	if self._states[name] then
		self._states[name].Enter(context)
	end
end

function AIStateMachine:Update(context: any, dt: number)
	if self.CurrentState and self._states[self.CurrentState] then
		self._states[self.CurrentState].Update(context, dt)
	end
end

return AIStateMachine
