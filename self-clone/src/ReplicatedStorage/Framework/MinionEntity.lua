--!strict
-- MinionEntity.lua
-- Represents a single minion instance. Owns components, attributes, and
-- lifecycle signals. Components never reference each other directly; they
-- communicate through the entity's attribute store and signals.

local Signal = require(script.Parent.Signal)

export type Component = {
	Init: ((self: any, entity: MinionEntity) -> ())?,
	Start: ((self: any) -> ())?,
	Stop: ((self: any) -> ())?,
	Update: ((self: any, dt: number) -> ())?,
	Destroy: (self: any) -> (),
}

export type MinionEntity = {
	Id: number,
	Owner: Player,
	Model: Model?,
	CreatedAt: number,
	Destroyed: boolean,

	Destroying: Signal.Signal,
	AttributeChanged: Signal.Signal,

	AddComponent: (self: MinionEntity, name: string, component: Component) -> Component,
	RemoveComponent: (self: MinionEntity, name: string) -> (),
	GetComponent: (self: MinionEntity, name: string) -> Component?,
	HasComponent: (self: MinionEntity, name: string) -> boolean,

	SetAttribute: (self: MinionEntity, key: string, value: any) -> (),
	GetAttribute: (self: MinionEntity, key: string) -> any,
	HasAttribute: (self: MinionEntity, key: string) -> boolean,
	RemoveAttribute: (self: MinionEntity, key: string) -> (),
	GetAttributes: (self: MinionEntity) -> { [string]: any },

	Destroy: (self: MinionEntity) -> (),

	_components: { [string]: Component },
	_componentOrder: { string },
	_attributes: { [string]: any },
}

local MinionEntity = {}
MinionEntity.__index = MinionEntity

function MinionEntity:AddComponent(name: string, component: Component): Component
	if self.Destroyed then
		error("Cannot add component to a destroyed MinionEntity", 2)
	end
	if self._components[name] then
		error(string.format("Component %q already exists on entity %d", name, self.Id), 2)
	end

	self._components[name] = component
	table.insert(self._componentOrder, name)

	if component.Init then
		component:Init(self)
	end
	if component.Start then
		component:Start()
	end

	return component
end

function MinionEntity:RemoveComponent(name: string)
	local component = self._components[name]
	if not component then
		return
	end

	if component.Stop then
		component:Stop()
	end
	component:Destroy()

	self._components[name] = nil
	for i, n in ipairs(self._componentOrder) do
		if n == name then
			table.remove(self._componentOrder, i)
			break
		end
	end
end

function MinionEntity:GetComponent(name: string): Component?
	return self._components[name]
end

function MinionEntity:HasComponent(name: string): boolean
	return self._components[name] ~= nil
end

function MinionEntity:SetAttribute(key: string, value: any)
	local old = self._attributes[key]
	if old == value then
		return
	end
	self._attributes[key] = value
	self.AttributeChanged:Fire(key, value, old)
end

function MinionEntity:GetAttribute(key: string): any
	return self._attributes[key]
end

function MinionEntity:HasAttribute(key: string): boolean
	return self._attributes[key] ~= nil
end

function MinionEntity:RemoveAttribute(key: string)
	if self._attributes[key] == nil then
		return
	end
	local old = self._attributes[key]
	self._attributes[key] = nil
	self.AttributeChanged:Fire(key, nil, old)
end

function MinionEntity:GetAttributes(): { [string]: any }
	local copy = {}
	for k, v in pairs(self._attributes) do
		copy[k] = v
	end
	return copy
end

function MinionEntity:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true

	self.Destroying:Fire(self)

	-- Destroy components in reverse insertion order so dependents
	-- (added later) tear down before their dependencies.
	for i = #self._componentOrder, 1, -1 do
		local name = self._componentOrder[i]
		local component = self._components[name]
		if component then
			if component.Stop then
				component:Stop()
			end
			component:Destroy()
		end
	end

	table.clear(self._components)
	table.clear(self._componentOrder)
	table.clear(self._attributes)

	self.Destroying:Destroy()
	self.AttributeChanged:Destroy()

	if self.Model then
		self.Model:Destroy()
		self.Model = nil
	end
end

local function new(id: number, owner: Player, model: Model?): MinionEntity
	local self = setmetatable({
		Id = id,
		Owner = owner,
		Model = model,
		CreatedAt = os.clock(),
		Destroyed = false,

		Destroying = Signal.new(),
		AttributeChanged = Signal.new(),

		_components = {},
		_componentOrder = {},
		_attributes = {},
	}, MinionEntity)

	return (self :: any) :: MinionEntity
end

return {
	new = new,
}
