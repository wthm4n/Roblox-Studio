--!strict
-- HealthComponent.lua
-- Manages health only. Knows nothing about movement, following, or combat.
-- Exposes a Signal so other systems (added later, e.g. combat/UI) can react
-- to damage/death without this component knowing they exist.

local Signal = require(game:GetService("ReplicatedStorage").Framework.Signal)

export type HealthComponentConfig = {
	MaxHealth: number,
}

export type HealthComponent = {
	MaxHealth: number,
	Health: number,
	Dead: boolean,

	HealthChanged: Signal.Signal, -- (newHealth, oldHealth)
	Died: Signal.Signal, -- ()

	Init: (self: HealthComponent, entity: any) -> (),
	Damage: (self: HealthComponent, amount: number) -> (),
	Heal: (self: HealthComponent, amount: number) -> (),
	SetHealth: (self: HealthComponent, value: number) -> (),
	IsDead: (self: HealthComponent) -> boolean,
	Destroy: (self: HealthComponent) -> (),

	_entity: any,
}

local HealthComponent = {}
HealthComponent.__index = HealthComponent

function HealthComponent:Init(entity: any)
	self._entity = entity
end

function HealthComponent:SetHealth(value: number)
	if self.Dead then
		return
	end

	local clamped = math.clamp(value, 0, self.MaxHealth)
	if clamped == self.Health then
		return
	end

	local old = self.Health
	self.Health = clamped
	self.HealthChanged:Fire(clamped, old)

	if clamped <= 0 then
		self.Dead = true
		self.Died:Fire()
	end
end

function HealthComponent:Damage(amount: number)
	if amount <= 0 or self.Dead then
		return
	end
	self:SetHealth(self.Health - amount)
end

function HealthComponent:Heal(amount: number)
	if amount <= 0 or self.Dead then
		return
	end
	self:SetHealth(self.Health + amount)
end

function HealthComponent:IsDead(): boolean
	return self.Dead
end

function HealthComponent:Destroy()
	self.HealthChanged:Destroy()
	self.Died:Destroy()
	self._entity = nil
end

local function new(config: HealthComponentConfig): HealthComponent
	local self = setmetatable({
		MaxHealth = config.MaxHealth,
		Health = config.MaxHealth,
		Dead = false,

		HealthChanged = Signal.new(),
		Died = Signal.new(),

		_entity = nil,
	}, HealthComponent)

	return (self :: any) :: HealthComponent
end

return {
	new = new,
}
