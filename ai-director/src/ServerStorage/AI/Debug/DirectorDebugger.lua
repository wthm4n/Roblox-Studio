-- DirectorDebugger.lua
-- Real-time debug overlay for the AI Director system.
-- Creates a ScreenGui with live stats, pacing state visualization,
-- stress bar, and spawn point gizmos. Server-side gizmos use Adornments.

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local TweenService   = game:GetService("TweenService")

local DirectorDebugger = {}
DirectorDebugger.__index = DirectorDebugger

-- ──────────────────────────────────────────────
--  Config
-- ──────────────────────────────────────────────
local REFRESH_RATE    = 0.25   -- seconds between UI updates
local PANEL_WIDTH     = 280
local PANEL_OPACITY   = 0.82

-- Pacing state → colour
local STATE_COLORS = {
	RELAX    = Color3.fromRGB(60,  180, 90),
	BUILDUP  = Color3.fromRGB(240, 190, 40),
	PEAK     = Color3.fromRGB(220, 60,  60),
	RECOVERY = Color3.fromRGB(60,  140, 220),
}

-- Stress bar gradient stops
local STRESS_COLORS = {
	low    = Color3.fromRGB(60,  200, 80),   -- 0–35
	mid    = Color3.fromRGB(240, 200, 40),   -- 35–65
	high   = Color3.fromRGB(220, 60,  60),   -- 65–100
}

-- ──────────────────────────────────────────────
--  Constructor
-- ──────────────────────────────────────────────
function DirectorDebugger.new(director)
	assert(director, "[DirectorDebugger] director is required")

	local self = setmetatable({}, DirectorDebugger)

	self._director    = director
	self._enabled     = false
	self._gui         = nil
	self._conn        = nil
	self._accum       = 0
	self._gizmos      = {}   -- {adornment, label} pairs for spawn points

	return self
end

-- ──────────────────────────────────────────────
--  UI Construction Helpers
-- ──────────────────────────────────────────────

local function makeInstance(className, props)
	local inst = Instance.new(className)
	for k, v in pairs(props) do inst[k] = v end
	return inst
end

local function makeLabel(props)
	return makeInstance("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.Code,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 18),
		...props,
	})
end

-- ──────────────────────────────────────────────
--  Enable / Disable
-- ──────────────────────────────────────────────

function DirectorDebugger:Enable()
	if self._enabled then return end
	self._enabled = true
	self:_buildGui()
	self:_buildSpawnGizmos()

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self._accum += dt
		if self._accum >= REFRESH_RATE then
			self._accum = 0
			self:_refresh()
		end
	end)
end

function DirectorDebugger:Disable()
	if not self._enabled then return end
	self._enabled = false

	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	if self._gui then
		self._gui:Destroy()
		self._gui = nil
	end
	self:_clearGizmos()
end

-- ──────────────────────────────────────────────
--  GUI Build
-- ──────────────────────────────────────────────

function DirectorDebugger:_buildGui()
	-- Attach to local player's PlayerGui
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		warn("[DirectorDebugger] Must run on client")
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name            = "DirectorDebugUI"
	gui.ResetOnSpawn    = false
	gui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
	gui.Parent          = localPlayer.PlayerGui
	self._gui = gui

	-- ── Background Panel ──
	local panel = makeInstance("Frame", {
		Name              = "Panel",
		Size              = UDim2.new(0, PANEL_WIDTH, 0, 440),
		Position          = UDim2.new(0, 8, 0.5, -220),
		BackgroundColor3  = Color3.fromRGB(10, 10, 20),
		BackgroundTransparency = 1 - PANEL_OPACITY,
		BorderSizePixel   = 0,
		Parent            = gui,
	})
	makeInstance("UICorner",    {CornerRadius = UDim.new(0, 8),  Parent = panel})
	makeInstance("UIStroke",    {Color = Color3.fromRGB(80,80,120), Thickness = 1, Parent = panel})
	makeInstance("UIPadding",   {
		PaddingLeft   = UDim.new(0, 10),
		PaddingRight  = UDim.new(0, 10),
		PaddingTop    = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		Parent = panel
	})
	makeInstance("UIListLayout", {
		SortOrder  = Enum.SortOrder.LayoutOrder,
		Padding    = UDim.new(0, 4),
		Parent     = panel,
	})

	-- ── Header ──
	local header = makeInstance("TextLabel", {
		Name                   = "Header",
		Text                   = "⚙ AI DIRECTOR",
		Size                   = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		TextColor3             = Color3.fromRGB(180, 200, 255),
		Font                   = Enum.Font.GothamBold,
		TextSize               = 15,
		TextXAlignment         = Enum.TextXAlignment.Center,
		LayoutOrder            = 0,
		Parent                 = panel,
	})

	makeInstance("Frame", {
		Name            = "Divider",
		Size            = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Color3.fromRGB(80, 80, 120),
		BorderSizePixel  = 0,
		LayoutOrder      = 1,
		Parent           = panel,
	})

	-- ── Stress Bar ──
	local stressContainer = makeInstance("Frame", {
		Name            = "StressContainer",
		Size            = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		LayoutOrder     = 2,
		Parent          = panel,
	})
	makeInstance("TextLabel", {
		Text       = "STRESS",
		Size       = UDim2.new(0, 60, 1, 0),
		Position   = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(180, 180, 180),
		Font       = Enum.Font.Code,
		TextSize   = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent     = stressContainer,
	})
	local stressTrack = makeInstance("Frame", {
		Name            = "Track",
		Size            = UDim2.new(1, -65, 0, 14),
		Position        = UDim2.new(0, 65, 0.5, -7),
		BackgroundColor3 = Color3.fromRGB(30, 30, 40),
		BorderSizePixel  = 0,
		Parent           = stressContainer,
	})
	makeInstance("UICorner", {CornerRadius = UDim.new(0, 3), Parent = stressTrack})
	makeInstance("Frame", {
		Name            = "Fill",
		Size            = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = STRESS_COLORS.low,
		BorderSizePixel  = 0,
		Parent           = stressTrack,
	}):FindFirstChild("UICorner") -- Ensure UICorner is added
	local stressFill = stressTrack:FindFirstChild("Fill") or makeInstance("Frame", {
		Name = "Fill", Size = UDim2.new(0,0,1,0), BackgroundColor3 = STRESS_COLORS.low,
		BorderSizePixel = 0, Parent = stressTrack,
	})
	makeInstance("UICorner", {CornerRadius = UDim.new(0, 3), Parent = stressFill})
	makeInstance("TextLabel", {
		Name       = "StressValue",
		Text       = "0",
		Size       = UDim2.new(0, 30, 1, 0),
		Position   = UDim2.new(1, 2, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1,1,1),
		Font       = Enum.Font.Code,
		TextSize   = 11,
		Parent     = stressTrack,
	})
	self._stressFill  = stressFill
	self._stressValue = stressTrack:FindFirstChild("StressValue") or stressFill

	-- ── Pacing State Indicator ──
	local pacingRow = makeInstance("Frame", {
		Name            = "PacingRow",
		Size            = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder     = 3,
		Parent          = panel,
	})
	makeInstance("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = pacingRow})
	self._stateLabels = {}
	for _, state in ipairs({"RELAX", "BUILDUP", "PEAK", "RECOVERY"}) do
		local btn = makeInstance("TextLabel", {
			Text       = state,
			Size       = UDim2.new(0.24, -4, 1, 0),
			BackgroundColor3 = Color3.fromRGB(30, 30, 40),
			TextColor3 = Color3.fromRGB(120, 120, 140),
			Font       = Enum.Font.GothamBold,
			TextSize   = 10,
			Parent     = pacingRow,
		})
		makeInstance("UICorner", {CornerRadius = UDim.new(0, 4), Parent = btn})
		self._stateLabels[state] = btn
	end

	-- ── Stats Lines ──
	local STAT_DEFS = {
		{key = "pacing",    label = "Pacing"},
		{key = "mult",      label = "Spawn Mult"},
		{key = "enemies",   label = "Enemies"},
		{key = "spawnRate", label = "Spawn Rate"},
		{key = "diffMod",   label = "Difficulty"},
		{key = "skill",     label = "Skill Score"},
		{key = "accuracy",  label = "Accuracy"},
		{key = "kpm",       label = "KPM"},
		{key = "events",    label = "Events Fired"},
		{key = "transitions", label = "Transitions"},
		{key = "spawnPool", label = "Spawn Pool"},
	}
	self._statLabels = {}
	for i, def in ipairs(STAT_DEFS) do
		local row = makeInstance("Frame", {
			Size            = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			LayoutOrder     = 10 + i,
			Parent          = panel,
		})
		makeInstance("TextLabel", {
			Text  = def.label .. ":",
			Size  = UDim2.new(0.48, 0, 1, 0),
			BackgroundTransparency = 1,
			TextColor3 = Color3.fromRGB(140, 140, 160),
			Font  = Enum.Font.Code,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local valLbl = makeInstance("TextLabel", {
			Name  = "Val",
			Text  = "—",
			Size  = UDim2.new(0.52, 0, 1, 0),
			Position = UDim2.new(0.48, 0, 0, 0),
			BackgroundTransparency = 1,
			TextColor3 = Color3.new(1, 1, 1),
			Font  = Enum.Font.Code,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		self._statLabels[def.key] = valLbl
	end

	-- ── Event Log (last 4 events) ──
	makeInstance("Frame", {
		Name            = "Divider2",
		Size            = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Color3.fromRGB(80, 80, 120),
		BorderSizePixel  = 0,
		LayoutOrder      = 30,
		Parent           = panel,
	})
	makeInstance("TextLabel", {
		Text       = "EVENT LOG",
		Size       = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(180, 180, 200),
		Font       = Enum.Font.GothamBold,
		TextSize   = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 31,
		Parent     = panel,
	})
	self._eventLogLabels = {}
	for i = 1, 4 do
		local lbl = makeInstance("TextLabel", {
			Text       = "",
			Size       = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			TextColor3 = Color3.fromRGB(180, 200, 140),
			Font       = Enum.Font.Code,
			TextSize   = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			RichText   = true,
			LayoutOrder = 31 + i,
			Parent     = panel,
		})
		table.insert(self._eventLogLabels, lbl)
	end
end

-- ──────────────────────────────────────────────
--  Refresh
-- ──────────────────────────────────────────────

function DirectorDebugger:_refresh()
	if not self._gui then return end
	local info = self._director:GetDebugInfo()

	local stress = tonumber(info.Director.Stress) or 0
	local stressFrac = stress / 100

	-- Stress bar
	if self._stressFill then
		TweenService:Create(self._stressFill,
			TweenInfo.new(0.2, Enum.EasingStyle.Linear),
			{Size = UDim2.new(stressFrac, 0, 1, 0)}
		):Play()

		local col
		if stress < 35 then
			col = STRESS_COLORS.low
		elseif stress < 65 then
			col = STRESS_COLORS.mid
		else
			col = STRESS_COLORS.high
		end
		self._stressFill.BackgroundColor3 = col
	end

	-- Pacing state pills
	local currentPacing = info.Pacing.CurrentState
	for state, lbl in pairs(self._stateLabels) do
		if state == currentPacing then
			lbl.BackgroundColor3 = STATE_COLORS[state] or Color3.fromRGB(100, 100, 100)
			lbl.TextColor3 = Color3.new(0, 0, 0)
		else
			lbl.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
			lbl.TextColor3 = Color3.fromRGB(90, 90, 110)
		end
	end

	-- Stat labels
	local S = self._statLabels
	local function set(key, val) if S[key] then S[key].Text = tostring(val) end end

	set("pacing",      currentPacing)
	set("mult",        info.Pacing.SpawnMultiplier)
	set("enemies",     info.Director.ActiveEnemies)
	set("spawnRate",   info.Spawning.SpawnRate or "—")
	set("diffMod",     info.Difficulty.DifficultyMod or "—")
	set("skill",       info.Difficulty.SkillScore or "—")
	set("accuracy",    info.Difficulty.Accuracy or "—")
	set("kpm",         info.Difficulty.KPM or "—")
	set("events",      info.Events.TotalEventsFired or 0)
	set("transitions", info.Pacing.TransitionCount or 0)
	set("spawnPool",   string.format("%d pts (%d ready)",
		info.Pool.TotalPoints or 0, info.Pool.ReadyPoints or 0))

	-- Event log
	local log = self._director:GetEventManager() and
		self._director:GetEventManager():GetEventLog() or {}
	local recent = {}
	for i = math.max(1, #log - 3), #log do
		table.insert(recent, log[i])
	end
	for i, lbl in ipairs(self._eventLogLabels) do
		local entry = recent[i]
		if entry then
			local elapsed = math.floor(tick() - entry.time)
			lbl.Text = string.format("• %s  <font color='#888'>%ds ago</font>",
				entry.event:upper(), elapsed)
		else
			lbl.Text = ""
		end
	end
end

-- ──────────────────────────────────────────────
--  World Gizmos (spawn point visualizers)
-- ──────────────────────────────────────────────

function DirectorDebugger:_buildSpawnGizmos()
	local pool = self._director:GetSpawnPool()
	if not pool then return end

	for _, pt in ipairs(pool:GetAllPoints()) do
		local part = pt.Part
		if not part then continue end

		-- Highlight box
		local sel = Instance.new("SelectionBox")
		sel.Adornee     = part
		sel.Color3      = Color3.fromRGB(60, 220, 100)
		sel.LineThickness = 0.04
		sel.SurfaceTransparency = 0.8
		sel.SurfaceColor3 = Color3.fromRGB(60, 220, 100)
		sel.Parent      = workspace

		-- Billboard label
		local bb = Instance.new("BillboardGui")
		bb.Adornee  = part
		bb.Size     = UDim2.new(0, 100, 0, 30)
		bb.StudsOffset = Vector3.new(0, 3, 0)
		bb.AlwaysOnTop = true
		bb.Parent   = workspace

		local lbl = Instance.new("TextLabel")
		lbl.Size   = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 0.5
		lbl.BackgroundColor3 = Color3.fromRGB(0,0,0)
		lbl.TextColor3 = Color3.new(1,1,1)
		lbl.Font   = Enum.Font.Code
		lbl.TextSize = 11
		lbl.Text   = "SP [" .. table.concat(pt.Tags, ",") .. "]"
		lbl.Parent = bb

		table.insert(self._gizmos, {sel = sel, bb = bb})
	end
end

function DirectorDebugger:_clearGizmos()
	for _, g in ipairs(self._gizmos) do
		if g.sel then g.sel:Destroy() end
		if g.bb  then g.bb:Destroy()  end
	end
	self._gizmos = {}
end

-- ──────────────────────────────────────────────
--  Print Snapshot (server-side, no GUI)
-- ──────────────────────────────────────────────

function DirectorDebugger:PrintSnapshot()
	local info = self._director:GetDebugInfo()
	print("═══════════ DIRECTOR SNAPSHOT ═══════════")
	print("Stress:      " .. info.Director.Stress)
	print("Pacing:      " .. (info.Pacing.CurrentState or "—"))
	print("Enemies:     " .. info.Director.ActiveEnemies)
	print("Difficulty:  " .. (info.Difficulty.DifficultyMod or "—"))
	print("Skill Score: " .. (info.Difficulty.SkillScore or "—"))
	print("Spawn Rate:  " .. (info.Spawning.SpawnRate or "—"))
	print("Events Fired:" .. (info.Events.TotalEventsFired or 0))
	print("═════════════════════════════════════════")
end

return DirectorDebugger
