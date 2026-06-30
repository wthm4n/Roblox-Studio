--!strict
-- OverheadGuiComponent.lua
-- Clones a BillboardGui template (built by hand in Studio — see the naming
-- convention below) onto the minion's Head, and keeps its TextLabels in
-- sync with the entity's attributes and Health component automatically.
--
-- This component does NOT build any GUI itself. It expects a template at
-- ReplicatedStorage.GUI.MinionOverheadGui (override the path via config)
-- containing TextLabels named after the fields you want to show. Any label
-- whose name isn't found is silently skipped, so you can add/remove fields
-- in Studio without touching this script.
--
-- Expected template contents (build this in Studio):
--   ReplicatedStorage
--     GUI
--       MinionOverheadGui            (BillboardGui)
--         NameLabel                  (TextLabel)  — minion's display name
--         OwnerLabel                 (TextLabel)  — "Owner: <player>"
--         LevelLabel                 (TextLabel)  — "Lv. 3"
--         RarityLabel                (TextLabel)  — "Common" / "Legendary" / etc.
--         HealthLabel                (TextLabel)  — "80 / 100" (optional, if no health bar)
--         HealthBarBack              (Frame, optional)
--           HealthBarFill            (Frame, optional, AnchorPoint 0,0.5 + Size driven by code)
--
-- BillboardGui suggested properties: Size = UDim2.new(4, 0, 1.6, 0),
-- StudsOffset = Vector3.new(0, 2.4, 0), AlwaysOnTop = true, MaxDistance = 60.
-- Every label/frame name above is optional — only what exists gets driven.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type OverheadGuiConfig = {
	TemplatePath: { Instance }?, -- override lookup path; defaults to ReplicatedStorage.GUI.MinionOverheadGui
	NameText: string?, -- static display name; defaults to Model.Name
}

export type OverheadGuiComponent = {
	Init: (self: OverheadGuiComponent, entity: any) -> (),
	Start: (self: OverheadGuiComponent) -> (),
	Stop: (self: OverheadGuiComponent) -> (),
	Destroy: (self: OverheadGuiComponent) -> (),

	SetLine: (self: OverheadGuiComponent, labelName: string, text: string) -> (),
	SetHealthFraction: (self: OverheadGuiComponent, fraction: number) -> (),

	_entity: any,
	_billboard: BillboardGui?,
	_connections: { RBXScriptConnection },
	_config: OverheadGuiConfig?,
}

local OverheadGuiComponent = {}
OverheadGuiComponent.__index = OverheadGuiComponent

local function findTemplate(config: OverheadGuiConfig?): BillboardGui?
	if config and config.TemplatePath then
		local current: Instance? = nil
		for i, step in ipairs(config.TemplatePath) do
			current = if i == 1 then step else (current :: Instance):FindFirstChild((step :: any).Name)
		end
		return current :: BillboardGui?
	end

	local guiFolder = ReplicatedStorage:FindFirstChild("GUI")
	local template = guiFolder and guiFolder:FindFirstChild("MinionOverheadGui")
	return template :: BillboardGui?
end

function OverheadGuiComponent:SetLine(labelName: string, text: string)
	local billboard = self._billboard
	if not billboard then
		return
	end
	local label = billboard.Main:FindFirstChild(labelName)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

function OverheadGuiComponent:SetHealthFraction(fraction: number)
	local billboard = self._billboard
	if not billboard then
		return
	end
	local fill = billboard.Main:FindFirstChild("HealthBarBack")
	fill = fill and fill:FindFirstChild("HealthBarFill")
	if fill and fill:IsA("Frame") then
		fill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
	end
end

function OverheadGuiComponent:Init(entity: any)
	self._entity = entity

	local model = entity.Model
	local head = model and model:FindFirstChild("Head")
	if not head then
		return
	end

	local template = findTemplate(self._config)
	if not template then
		warn("OverheadGuiComponent: no template found at ReplicatedStorage.GUI.MinionOverheadGui")
		return
	end

	local billboard = template:Clone()
	billboard.Adornee = head :: BasePart
	billboard.Parent = head
	self._billboard = billboard

	local config = self._config
	self:SetLine("NameLabel", (config and config.NameText) or model.Name)
	self:SetLine("OwnerLabel", "Owner: " .. entity.Owner.Name)

	local attrConn = entity.AttributeChanged:Connect(function(key: string, newVal: any)
		if key == "Level" then
			self:SetLine("LevelLabel", "Lv. " .. tostring(newVal))
		elseif key == "Rarity" then
			self:SetLine("RarityLabel", tostring(newVal))
		end
	end)
	table.insert(self._connections, attrConn)
end

function OverheadGuiComponent:Start()
	-- Hook Health component if present; safe no-op if added later or absent.
	local entity = self._entity
	if not entity then
		return
	end

	local health = entity:GetComponent("Health")
	if health then
		self:SetLine("HealthLabel", string.format("%d / %d", health.Health, health.MaxHealth))
		self:SetHealthFraction(health.Health / health.MaxHealth)

		local healthConn = health.HealthChanged:Connect(function(newHealth: number, _oldHealth: number)
			self:SetLine("HealthLabel", string.format("%d / %d", newHealth, health.MaxHealth))
			self:SetHealthFraction(newHealth / health.MaxHealth)
		end)
		table.insert(self._connections, healthConn)
	end
end

function OverheadGuiComponent:Stop()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

function OverheadGuiComponent:Destroy()
	self:Stop()
	if self._billboard then
		self._billboard:Destroy()
		self._billboard = nil
	end
	self._entity = nil
end

local function new(config: OverheadGuiConfig?): OverheadGuiComponent
	local self = setmetatable({
		_entity = nil,
		_billboard = nil,
		_connections = {},
		_config = config,
	}, OverheadGuiComponent)

	return (self :: any) :: OverheadGuiComponent
end

return {
	new = new,
}